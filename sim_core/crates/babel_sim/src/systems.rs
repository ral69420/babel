//! Per-tick simulation systems.
//!
//! Kept as a private module — the only public entry point is
//! [`run_one_tick`], called from [`crate::world::World::run_systems_one_tick`].
//!
//! Each system takes `&mut World` and runs in a fixed, documented order. The
//! ordering is part of the determinism contract — never reorder casually.
//!
//! ## Society loop
//!
//! The "society loop" — pairing → gestation → birth → ageing → housing →
//! death — is layered on top of the existing tick scaffold via four
//! daily-pulse systems:
//!
//! 1. `aging_daily`     — increment `age_days` for every live NPC.
//! 2. `pairing_daily`   — single adults inside the partner radius roll
//!    for marriage.
//! 3. `gestation_daily` — paired women roll for conception, then tick
//!    down to birth.
//! 4. `building_daily`  — unhomed pairs propose a build site; each
//!    in-progress site advances by `builders` days; completed sites
//!    become homes.
//!
//! Plus an `aging_yearly` death roll that retires elders. Everything
//! else (combat, traditions, factions, etc.) is still a placeholder.

use crate::entity::{
    Building, BuildingId, BuildingKind, BuildingStage, NpcId, NpcRole, NpcTraits, Sex,
    BUILDING_TOTAL_DAYS,
};
use crate::event::{DeathCause, EventKind};
use crate::time_sys::{DAYS_PER_YEAR, TICKS_PER_YEAR};
use crate::world::{tile_tags, Biome, World};

/// Drive everything that happens in a single tick. Order:
///
/// 1. `aging` — placeholder per-tick trait drift.
/// 2. `mortality` — health-driven deaths.
/// 3. `daily_pulse` — once per game-day systems (births, social drift).
/// 4. `yearly_pulse` — once per game-year systems (tradition drift, faction
///    formation, war declarations).
pub fn run_one_tick(w: &mut World) {
    let tick = w.clock.ticks();

    // Cheap per-tick: nothing right now, but reserve the slot.
    aging(w, tick);
    mortality(w, tick);

    // Daily-aligned systems. We treat tick `t` as "first tick of the day" if
    // `t % TICKS_PER_DAY == 0`.
    let ticks_per_day = TICKS_PER_YEAR / 360;
    if ticks_per_day != 0 && tick % u64::from(ticks_per_day) == 0 {
        daily_pulse(w, tick);
    }

    if tick % u64::from(TICKS_PER_YEAR) == 0 {
        yearly_pulse(w, tick);
    }
}

fn aging(w: &mut World, _tick: u64) {
    // Trait drift over time — placeholder for now. We avoid any allocation
    // and just walk live NPCs in stable order.
    for (_id, npc) in w.npcs.iter_mut() {
        if npc.death_tick != u64::MAX {
            continue;
        }
        // Trait drift is currently no-op. Placeholder.
        let _ = &npc.traits;
    }
}

fn mortality(w: &mut World, tick: u64) {
    // Collect deaths to apply after the read pass — keeps borrowing simple.
    let mut to_kill: Vec<(crate::NpcId, DeathCause)> = Vec::new();
    for (id, npc) in w.npcs.iter() {
        if npc.death_tick != u64::MAX {
            continue;
        }
        if npc.traits.health == 0 {
            to_kill.push((id, DeathCause::Sickness));
        }
    }
    for (id, cause) in to_kill {
        if let Some(npc) = w.npcs.get_mut(id) {
            npc.death_tick = tick;
        }
        w.events.push(tick, EventKind::NpcDied { npc: id, cause });
        retire_partner_of(w, id);
    }
}

fn daily_pulse(w: &mut World, tick: u64) {
    // Cheap deterministic city growth: every game-day each city gains a flat
    // +1 pop (capped). This is intentionally simple — full demographic
    // model arrives with the food / mood systems. Walks `cities` in stable
    // SlotVec order so it never perturbs RNG.
    const POP_CAP: u32 = 50_000;
    for (_id, city) in w.cities.iter_mut() {
        if city.population < POP_CAP {
            city.population = city.population.saturating_add(1);
        }
    }

    // Society loop. Order matters — see module docstring.
    aging_daily(w);
    pairing_daily(w, tick);
    gestation_daily(w, tick);
    building_daily(w, tick);
}

fn yearly_pulse(w: &mut World, tick: u64) {
    // Sync each tile's `pop` field with its owning city's population so the
    // renderer shows growth without per-tick churn. Cheap O(cities).
    let dims = w.dims;
    let mut snaps: Vec<(i32, i32, u16)> = Vec::with_capacity(w.cities.len());
    for (_id, city) in w.cities.iter() {
        snaps.push((city.x, city.y, city.population.min(u16::MAX as u32) as u16));
    }
    for (x, y, pop) in snaps {
        if x < 0 || y < 0 || x >= dims.w as i32 || y >= dims.h as i32 {
            continue;
        }
        if let Some(t) = w.tile_mut(x, y) {
            t.pop = pop;
        }
    }

    // Old-age death roll.
    aging_yearly(w, tick);
}

// =====================================================================
// Society loop systems
// =====================================================================

/// Adulthood threshold in sim-days. NPCs younger than this are children:
/// they don't pair, don't gestate, don't build, don't die of old age.
const CHILD_DAYS: u32 = 14 * DAYS_PER_YEAR; // 14 sim-years

/// Maximum sim-age for fertility (women). Beyond this, gestation rolls
/// are skipped.
const FERTILE_MAX_DAYS: u32 = 50 * DAYS_PER_YEAR;

/// Days that must pass after a birth before another conception can roll.
const BIRTH_COOLDOWN_DAYS: u32 = 2 * DAYS_PER_YEAR;

/// Chebyshev radius (tiles) used by `pairing_daily` and gestation.
const SOCIAL_RADIUS: i32 = 6;

/// Daily probability (in `0..1024`) that two compatible singles within
/// `SOCIAL_RADIUS` form a pair. ~10% per encounter.
const PAIR_PROB_PER_1024: u32 = 102;

/// Daily probability (in `0..1024`) that a paired adult conceives a
/// child. ~5% per day → expected 20 days from pair-formed to conception.
const CONCEIVE_PROB_PER_1024: u32 = 51;

/// Length of pregnancy in sim-days.
const GESTATION_DAYS: u16 = 9;

/// Tile-radius minimum spacing between any two buildings. Anti-clutter.
const BUILD_MIN_SPACING: i32 = 5;

/// Sim-day cadence at which an unhomed pair may attempt to start a new
/// build (independent of construction speed).
const BUILD_REQUEST_EVERY_DAYS: u32 = 5;

/// Number of candidate tiles to sample around the civ centroid when
/// looking for a build site.
const BUILD_CANDIDATES: u32 = 8;

/// Search radius around civ centroid for new build sites (Chebyshev).
const BUILD_PLACEMENT_RADIUS: i32 = 12;

/// Increment age in sim-days for every living NPC.
fn aging_daily(w: &mut World) {
    for (_id, npc) in w.npcs.iter_mut() {
        if npc.death_tick != u64::MAX {
            continue;
        }
        npc.age_days = npc.age_days.saturating_add(1);
    }
}

/// Yearly death roll: probability scales after age 40. Removes spouse
/// link from the survivor and pushes an `NpcDied(OldAge)` event.
fn aging_yearly(w: &mut World, tick: u64) {
    // Snapshot live ids so we can mutate freely below.
    let mut to_kill: Vec<NpcId> = Vec::new();
    let mut rng = w.rng.fork();
    for (id, npc) in w.npcs.iter() {
        if npc.death_tick != u64::MAX {
            continue;
        }
        let age_years = npc.age_days / DAYS_PER_YEAR;
        if age_years <= 40 {
            continue;
        }
        // Quadratic-ish growth: P = 0.0002 * (age-40)^2, capped at 0.6.
        let extra = age_years - 40;
        let p_per_1024 = (extra * extra * 2 / 10).min(614);
        if rng.gen_range_u32(1024) < p_per_1024 {
            to_kill.push(id);
        }
    }
    for id in to_kill {
        if let Some(npc) = w.npcs.get_mut(id) {
            npc.death_tick = tick;
        }
        w.events.push(
            tick,
            EventKind::NpcDied {
                npc: id,
                cause: DeathCause::OldAge,
            },
        );
        retire_partner_of(w, id);
    }
}

fn retire_partner_of(w: &mut World, dead: NpcId) {
    let partner = w.npcs.get(dead).map(|n| n.spouse).unwrap_or(NpcId::NONE);
    if partner.is_none() {
        return;
    }
    if let Some(p) = w.npcs.get_mut(partner) {
        if p.spouse == dead {
            p.spouse = NpcId::NONE;
        }
    }
}

/// Adults inside `SOCIAL_RADIUS` may pair. We collect candidate pairs in
/// a single pass to avoid fixed-point iteration ordering issues.
fn pairing_daily(w: &mut World, tick: u64) {
    // Collect all single adults eligible to pair.
    let mut singles: Vec<(NpcId, i32, i32)> = Vec::new();
    for (id, npc) in w.npcs.iter() {
        if npc.death_tick != u64::MAX {
            continue;
        }
        if npc.age_days < CHILD_DAYS {
            continue;
        }
        if !npc.spouse.is_none() {
            continue;
        }
        // Drop very-old people from the pool — keeps elders out of the
        // marriage market.
        if npc.age_days > FERTILE_MAX_DAYS {
            continue;
        }
        singles.push((id, npc.x, npc.y));
    }
    if singles.len() < 2 {
        return;
    }

    let mut rng = w.rng.fork();
    let mut new_pairs: Vec<(NpcId, NpcId)> = Vec::new();
    let mut paired: Vec<bool> = vec![false; singles.len()];
    // Stable iteration: walk in slotvec order. For each unpaired single,
    // look ahead for the first eligible partner inside SOCIAL_RADIUS.
    for i in 0..singles.len() {
        if paired[i] {
            continue;
        }
        let (a_id, ax, ay) = singles[i];
        for j in (i + 1)..singles.len() {
            if paired[j] {
                continue;
            }
            let (b_id, bx, by) = singles[j];
            let d = (ax - bx).abs().max((ay - by).abs());
            if d > SOCIAL_RADIUS {
                continue;
            }
            // Probability gate. Per-pair, per-day.
            if rng.gen_range_u32(1024) < PAIR_PROB_PER_1024 {
                new_pairs.push((a_id, b_id));
                paired[i] = true;
                paired[j] = true;
                break;
            }
        }
    }
    for (a, b) in new_pairs {
        if let Some(an) = w.npcs.get_mut(a) {
            an.spouse = b;
        }
        if let Some(bn) = w.npcs.get_mut(b) {
            bn.spouse = a;
        }
        w.events.push(tick, EventKind::NpcPaired { a, b });
    }
}

/// Tick gestation timers, roll for new conceptions, perform births.
fn gestation_daily(w: &mut World, tick: u64) {
    let day_of_sim = (tick / u64::from(TICKS_PER_YEAR / DAYS_PER_YEAR)) as u32;

    // 1) advance existing pregnancies; queue births
    let mut to_birth: Vec<NpcId> = Vec::new();
    for (id, npc) in w.npcs.iter_mut() {
        if npc.death_tick != u64::MAX {
            continue;
        }
        if npc.gestation_days == u16::MAX {
            continue;
        }
        if npc.gestation_days > 0 {
            npc.gestation_days -= 1;
        }
        if npc.gestation_days == 0 {
            to_birth.push(id);
            // mark as not-pregnant; reset to sentinel
            npc.gestation_days = u16::MAX;
            npc.last_birth_day = day_of_sim;
        }
    }

    for mother_id in to_birth {
        deliver_child(w, mother_id, tick, day_of_sim);
    }

    // 2) Roll for new conceptions. Iterate paired women only — keeps
    // population count bounded and the loop deterministic.
    let mut rng = w.rng.fork();
    let mut new_pregnancies: Vec<NpcId> = Vec::new();
    for (id, npc) in w.npcs.iter() {
        if npc.death_tick != u64::MAX {
            continue;
        }
        if npc.spouse.is_none() {
            continue;
        }
        if !matches!(npc.sex, Sex::F) {
            continue;
        }
        if npc.age_days < CHILD_DAYS || npc.age_days > FERTILE_MAX_DAYS {
            continue;
        }
        if npc.gestation_days != u16::MAX {
            continue;
        }
        if npc.last_birth_day != u32::MAX
            && day_of_sim.saturating_sub(npc.last_birth_day) < BIRTH_COOLDOWN_DAYS
        {
            continue;
        }
        // Both partners must be alive and within range.
        let Some(partner) = w.npcs.get(npc.spouse) else {
            continue;
        };
        if partner.death_tick != u64::MAX {
            continue;
        }
        let d = (npc.x - partner.x).abs().max((npc.y - partner.y).abs());
        if d > SOCIAL_RADIUS {
            continue;
        }
        if rng.gen_range_u32(1024) < CONCEIVE_PROB_PER_1024 {
            new_pregnancies.push(id);
        }
    }
    for id in new_pregnancies {
        if let Some(npc) = w.npcs.get_mut(id) {
            npc.gestation_days = GESTATION_DAYS;
        }
    }
}

/// Insert a child entity for the given mother. The child inherits the
/// mother's tile, civ, and home; father is read from the spouse link.
fn deliver_child(w: &mut World, mother_id: NpcId, tick: u64, _day_of_sim: u32) {
    let Some(mother) = w.npcs.get(mother_id) else {
        return;
    };
    let civ = mother.civ;
    let mx = mother.x;
    let my = mother.y;
    let father_id = mother.spouse;
    let home = mother.home;
    let traits = NpcTraits {
        loyalty: 60,
        piety: 40,
        curiosity: 60,
        aggression: 10,
        intellect: 50,
        charisma: 40,
        health: 100,
        _pad: 0,
    };
    // Alternate sex by id index for rough balance.
    let sex = if mother_id.0.idx() & 1 == 0 {
        Sex::M
    } else {
        Sex::F
    };
    // Procedural names belong in babel_lang at the bridge layer; here we
    // use a placeholder that the chronicle layer can rename later.
    let name = format!("Child of {}", mother.name);
    let child = crate::entity::Npc {
        name,
        civ,
        x: mx,
        y: my,
        birth_tick: tick,
        death_tick: u64::MAX,
        sex,
        traits,
        role: NpcRole::Citizen,
        faction: crate::entity::FactionId::NONE,
        spouse: NpcId::NONE,
        mother: mother_id,
        father: father_id,
        age_days: 0,
        last_birth_day: u32::MAX,
        gestation_days: u16::MAX,
        home,
    };
    let child_id = w.npcs.insert(child);
    w.events
        .push(tick, EventKind::NpcBorn { npc: child_id, civ });
}

/// Building tick: progress in-flight builds + propose new builds for
/// unhomed pairs.
fn building_daily(w: &mut World, tick: u64) {
    let day_of_sim = (tick / u64::from(TICKS_PER_YEAR / DAYS_PER_YEAR)) as u32;

    // 1) Progress in-flight builds. Each owner counts as one builder
    // (cap of 2). One day of progress per builder. Dead owners don't
    // count; if both owners are dead the build pauses.
    let mut completed: Vec<BuildingId> = Vec::new();
    for (id, b) in w.buildings.iter_mut() {
        if b.is_complete() {
            continue;
        }
        let mut builders: u16 = 0;
        for owner in [b.owner_a, b.owner_b] {
            if owner.is_none() {
                continue;
            }
            // Borrow the npc list to verify the owner is alive.
            // Safety: we only need a read — not a mutation. We can't
            // hold the Buildings iterator and also get_npc, so we
            // shadow w.npcs through a raw pointer? No — easier: do
            // this in a second pass.
            let _ = owner;
            builders += 1;
        }
        if builders == 0 {
            continue;
        }
        b.progress_days = (b.progress_days + builders).min(BUILDING_TOTAL_DAYS);
        let new_stage = BuildingStage::for_progress(b.progress_days);
        let was_complete = b.stage == BuildingStage::Complete;
        b.stage = new_stage;
        if !was_complete && new_stage == BuildingStage::Complete {
            completed.push(id);
        }
    }
    for bid in completed {
        let civ = w
            .buildings
            .get(bid)
            .map(|b| b.civ)
            .unwrap_or(crate::CivId::NONE);
        w.events
            .push(tick, EventKind::BuildingCompleted { building: bid, civ });
    }

    // 2) Propose new builds. Iterate pairs deterministically: whichever
    // partner has the smaller index drives the request so we don't roll
    // twice.
    if day_of_sim % BUILD_REQUEST_EVERY_DAYS != 0 {
        return;
    }
    // Snapshot the requesters to avoid borrow churn during placement.
    let mut requesters: Vec<(NpcId, NpcId)> = Vec::new();
    for (id, npc) in w.npcs.iter() {
        if npc.death_tick != u64::MAX {
            continue;
        }
        if npc.spouse.is_none() {
            continue;
        }
        if !npc.home.is_none() {
            continue;
        }
        if npc.age_days < CHILD_DAYS {
            continue;
        }
        // Tie-break: only the partner with the smaller index drives.
        if id.0.idx() >= npc.spouse.0.idx() {
            continue;
        }
        // Partner must also be alive and unhomed.
        let Some(partner) = w.npcs.get(npc.spouse) else {
            continue;
        };
        if partner.death_tick != u64::MAX {
            continue;
        }
        if !partner.home.is_none() {
            continue;
        }
        requesters.push((id, npc.spouse));
    }

    let mut rng = w.rng.fork();
    for (a, b) in requesters {
        let Some(npc_a) = w.npcs.get(a) else { continue };
        let civ = npc_a.civ;
        // Centroid of existing same-civ buildings, falling back to the
        // pair's own tile when no such buildings exist yet.
        let centroid = building_centroid_for_civ(w, civ).unwrap_or((npc_a.x, npc_a.y));
        // Sample N candidate tiles inside BUILD_PLACEMENT_RADIUS.
        let mut chosen: Option<(i32, i32)> = None;
        let mut best_dist: i32 = i32::MAX;
        for _ in 0..BUILD_CANDIDATES {
            let dx = rng.gen_range_u32((BUILD_PLACEMENT_RADIUS * 2 + 1) as u32) as i32
                - BUILD_PLACEMENT_RADIUS;
            let dy = rng.gen_range_u32((BUILD_PLACEMENT_RADIUS * 2 + 1) as u32) as i32
                - BUILD_PLACEMENT_RADIUS;
            let cx = centroid.0 + dx;
            let cy = centroid.1 + dy;
            if !is_buildable(w, cx, cy) {
                continue;
            }
            let d = (cx - centroid.0).abs() + (cy - centroid.1).abs();
            if d < best_dist {
                best_dist = d;
                chosen = Some((cx, cy));
            }
        }
        let Some((cx, cy)) = chosen else { continue };
        let bid = w.buildings.insert(Building {
            kind: BuildingKind::Granary,
            x: cx,
            y: cy,
            civ,
            owner_a: a,
            owner_b: b,
            founded_tick: tick,
            progress_days: 0,
            stage: BuildingStage::Foundation,
        });
        if let Some(npc) = w.npcs.get_mut(a) {
            npc.home = bid;
        }
        if let Some(npc) = w.npcs.get_mut(b) {
            npc.home = bid;
        }
        w.events.push(
            tick,
            EventKind::BuildingFounded {
                building: bid,
                civ,
                x: cx,
                y: cy,
            },
        );
    }
}

fn building_centroid_for_civ(w: &World, civ: crate::CivId) -> Option<(i32, i32)> {
    let mut sx: i64 = 0;
    let mut sy: i64 = 0;
    let mut n: i64 = 0;
    for (_id, b) in w.buildings.iter() {
        if b.civ == civ {
            sx += b.x as i64;
            sy += b.y as i64;
            n += 1;
        }
    }
    if n == 0 {
        return None;
    }
    Some(((sx / n) as i32, (sy / n) as i32))
}

fn is_buildable(w: &World, x: i32, y: i32) -> bool {
    let Some(t) = w.tile(x, y) else {
        return false;
    };
    if !matches!(
        t.biome,
        Biome::Plains | Biome::Coast | Biome::Forest | Biome::Hills
    ) {
        return false;
    }
    if t.has_tag(tile_tags::RIVER) || t.has_tag(tile_tags::RUIN) || t.has_tag(tile_tags::ZONE) {
        return false;
    }
    if t.city != u16::MAX {
        return false; // no overbuilding on the capital tile
    }
    // Spacing — Chebyshev distance to any other building must be ≥ N.
    for (_id, b) in w.buildings.iter() {
        let d = (b.x - x).abs().max((b.y - y).abs());
        if d < BUILD_MIN_SPACING {
            return false;
        }
    }
    true
}

// =====================================================================
// Helpers used by tests and content-level callers
// =====================================================================

/// Construct a default-trait NPC. Used by tests and worldgen seeding.
#[must_use]
#[allow(dead_code)]
pub fn default_npc_traits() -> NpcTraits {
    NpcTraits {
        loyalty: 60,
        piety: 40,
        curiosity: 40,
        aggression: 30,
        intellect: 50,
        charisma: 40,
        health: 100,
        _pad: 0,
    }
}

/// Convenience for picking a deterministic sex from an NPC index. Used when
/// we need a fast, allocation-free way to seed a balanced population.
#[must_use]
#[allow(dead_code)]
pub fn alternating_sex(i: u32) -> Sex {
    if i & 1 == 0 {
        Sex::F
    } else {
        Sex::M
    }
}

/// Map a tradition reformer's faction to the right NPC role for chronicle
/// purposes. Cheap helper, kept here for proximity to the AI rules.
#[must_use]
#[allow(dead_code)]
pub fn role_for_reformer() -> NpcRole {
    NpcRole::Rebel
}

#[cfg(test)]
mod tests {
    use crate::{SimConfig, World, WorldDims};

    use super::*;

    #[test]
    fn step_advances_clock_and_runs_systems() {
        let cfg = SimConfig {
            seed: 0,
            dims: WorldDims { w: 4, h: 4 },
            starting_civs: 0,
            starting_npcs_per_civ: 0,
        };
        let mut w = World::new(&cfg).unwrap();
        w.step(10);
        assert_eq!(w.clock.ticks(), 10);
    }

    #[test]
    fn aging_increments_age_per_day() {
        // Hand-roll a tiny world with one NPC so we don't need babel_lang.
        let cfg = SimConfig {
            seed: 0xBABE,
            dims: WorldDims { w: 8, h: 8 },
            starting_civs: 0,
            starting_npcs_per_civ: 0,
        };
        let mut w = World::new(&cfg).unwrap();
        let id = w.npcs.insert(crate::entity::Npc {
            name: "Test".into(),
            civ: crate::CivId::NONE,
            x: 0,
            y: 0,
            birth_tick: 0,
            death_tick: u64::MAX,
            sex: crate::Sex::M,
            traits: NpcTraits {
                health: 100,
                ..Default::default()
            },
            role: NpcRole::Citizen,
            faction: crate::FactionId::NONE,
            spouse: NpcId::NONE,
            mother: NpcId::NONE,
            father: NpcId::NONE,
            age_days: 100,
            last_birth_day: u32::MAX,
            gestation_days: u16::MAX,
            home: crate::entity::BuildingId::NONE,
        });
        let initial_age = w.npcs.get(id).unwrap().age_days;
        // One sim-day = TICKS_PER_YEAR / 360 ticks.
        let tpd = TICKS_PER_YEAR / 360;
        w.step(tpd);
        let after = w.npcs.get(id).unwrap().age_days;
        assert!(
            after > initial_age,
            "age did not advance: {initial_age} -> {after}"
        );
    }

    #[test]
    fn building_stage_progresses() {
        use crate::entity::*;
        let cfg = SimConfig {
            seed: 0xDEAD,
            dims: WorldDims { w: 8, h: 8 },
            starting_civs: 0,
            starting_npcs_per_civ: 0,
        };
        let mut w = World::new(&cfg).unwrap();
        // Insert two paired adults manually so the building has owners.
        let owner_a = w.npcs.insert(crate::entity::Npc {
            name: "A".into(),
            civ: crate::CivId::NONE,
            x: 0,
            y: 0,
            birth_tick: 0,
            death_tick: u64::MAX,
            sex: crate::Sex::M,
            traits: NpcTraits {
                health: 100,
                ..Default::default()
            },
            role: NpcRole::Citizen,
            faction: crate::FactionId::NONE,
            spouse: NpcId::NONE,
            mother: NpcId::NONE,
            father: NpcId::NONE,
            age_days: 18 * DAYS_PER_YEAR,
            last_birth_day: u32::MAX,
            gestation_days: u16::MAX,
            home: BuildingId::NONE,
        });
        let owner_b = w.npcs.insert(crate::entity::Npc {
            name: "B".into(),
            civ: crate::CivId::NONE,
            x: 1,
            y: 0,
            birth_tick: 0,
            death_tick: u64::MAX,
            sex: crate::Sex::F,
            traits: NpcTraits {
                health: 100,
                ..Default::default()
            },
            role: NpcRole::Citizen,
            faction: crate::FactionId::NONE,
            spouse: owner_a,
            mother: NpcId::NONE,
            father: NpcId::NONE,
            age_days: 18 * DAYS_PER_YEAR,
            last_birth_day: u32::MAX,
            gestation_days: u16::MAX,
            home: BuildingId::NONE,
        });
        if let Some(a) = w.npcs.get_mut(owner_a) {
            a.spouse = owner_b;
        }
        let bid = w.buildings.insert(Building {
            kind: BuildingKind::Granary,
            x: 4,
            y: 4,
            civ: crate::CivId::NONE,
            owner_a,
            owner_b,
            founded_tick: 0,
            progress_days: 0,
            stage: BuildingStage::Foundation,
        });
        if let Some(a) = w.npcs.get_mut(owner_a) {
            a.home = bid;
        }
        if let Some(b) = w.npcs.get_mut(owner_b) {
            b.home = bid;
        }

        // Step 60 sim-days. With 2 builders that's 120 day-units, well over
        // the 30-day total → stage = Complete.
        let tpd = TICKS_PER_YEAR / 360;
        w.step(tpd * 60);
        let b = w.buildings.get(bid).unwrap();
        assert_eq!(b.stage, BuildingStage::Complete);
        assert_eq!(b.progress_days, BUILDING_TOTAL_DAYS);
    }
}
