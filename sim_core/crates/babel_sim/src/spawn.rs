//! Initial civilization seeding and runtime city founding.
//!
//! Why this lives in `babel_sim` and not in `babel_gd`:
//!
//! - The seeding *algorithm* (where do civs go, in what order) is part of the
//!   simulation's deterministic contract. Two runs with the same seed must
//!   produce the same set of capitals.
//! - Seeding does not need a procedural language to do its job; it only
//!   needs *strings* for civ and city names. The bridge layer
//!   (`babel_gd::bridge`) generates those strings via [`babel_lang`] and
//!   passes them in as part of [`CivSpec`].
//!
//! This keeps `babel_sim` free of any language dependency while still
//! letting it own placement logic.

use crate::det_rng::DetRng;
use crate::entity::{
    BuildingId, City, CityId, CityTheme, CivId, Civilization, FactionId, Npc, NpcId, NpcRole,
    NpcTraits, Sex,
};
use crate::event::EventKind;
use crate::world::World;

/// Specification for one civilization to be seeded.
///
/// All naming is done by the caller (the bridge layer). The spawn algorithm
/// is responsible only for picking *where* to place the civ and inserting
/// the records.
#[derive(Debug, Clone)]
pub struct CivSpec {
    /// Display name in the player's tongue (caller-generated).
    pub name: String,
    /// Endonym — what the civ calls itself in its own generated language.
    pub endonym: String,
    /// Index into `babel_lang::Culture::ALL`. Stored on `Civilization`
    /// so the chronicle layer can pick the right language for new names.
    pub language_id: u32,
    /// Packed RGB used for map ownership tinting (`0xRRGGBB`).
    pub color_rgb: u32,
    /// Capital's display name (caller-generated).
    pub capital_name: String,
    /// Capital's `CityTheme`. Caller picks; spawn does not synthesise one.
    pub capital_theme: CityTheme,
}

/// Outcome of seeding: per civ in `specs`, the freshly inserted ids.
#[derive(Debug, Clone, Copy)]
pub struct SeededCiv {
    /// New civ id.
    pub civ: CivId,
    /// New capital city id.
    pub capital: CityId,
    /// Capital tile coordinate.
    pub x: i32,
    /// Capital tile coordinate.
    pub y: i32,
}

/// One unread event surfaced for the bridge layer's recent-events ticker.
#[derive(Debug, Clone)]
pub struct EventSummary {
    /// Tick at which the event occurred.
    pub tick: u64,
    /// Short human-readable summary (e.g. `"Civ Kheltari founded"`).
    pub headline: String,
}

/// Errors raised by the spawn layer.
#[derive(Debug, thiserror::Error)]
pub enum SpawnError {
    /// World had no settleable tiles at all (worldgen produced an all-water
    /// or all-mountain map). Caller should regenerate with a different seed.
    #[error("world has no settleable tiles for civilization seeding")]
    NoSettleableTiles,
    /// Could not place all requested civs respecting the minimum-distance
    /// constraint. Returned when the world is too small or too constrained
    /// for the requested count.
    #[error("could only place {placed} of {requested} civs given minimum spacing")]
    NotEnoughRoom {
        /// How many civs the algorithm managed to place.
        placed: u32,
        /// How many were requested.
        requested: u32,
    },
}

/// Population the capital starts with.
pub const STARTING_CAPITAL_POPULATION: u32 = 50;

/// Maximum number of civs we are ever willing to seed at once. Sanity bound.
pub const MAX_STARTING_CIVS: u32 = 32;

/// Seed a fresh world with civilizations and capitals.
///
/// Picks settleable tiles, spreads them out, inserts a [`Civilization`] +
/// capital [`City`] per spec, marks the chosen tile as owned + occupied,
/// and pushes `CivFounded` + `CityFounded` events to the world's log.
///
/// Determinism: the function uses a forked RNG derived from `world.rng`,
/// so two worlds with the same generated terrain and same `specs` produce
/// byte-identical results.
///
/// On error the world is left unchanged.
pub fn seed_world(world: &mut World, specs: &[CivSpec]) -> Result<Vec<SeededCiv>, SpawnError> {
    if specs.is_empty() {
        return Ok(Vec::new());
    }
    if specs.len() as u32 > MAX_STARTING_CIVS {
        // Soft limit; surfaces as NotEnoughRoom which is the closest thing.
        return Err(SpawnError::NotEnoughRoom {
            placed: 0,
            requested: specs.len() as u32,
        });
    }

    // Collect candidate tile indices in deterministic (row-major) order.
    let mut candidates: Vec<usize> = world
        .tiles
        .iter()
        .enumerate()
        .filter_map(|(i, t)| if t.is_settleable() { Some(i) } else { None })
        .collect();
    if candidates.is_empty() {
        return Err(SpawnError::NoSettleableTiles);
    }

    // Shuffle deterministically with a forked RNG so the master stream isn't
    // perturbed by the count of candidate tiles.
    let mut spawn_rng = world.rng.fork();
    fisher_yates(&mut candidates, &mut spawn_rng);

    // Greedy pick: walk the shuffled list, accept tiles whose distance to
    // every previously-picked tile is at least `min_distance`.
    let dims = world.dims;
    let area = dims.area();
    // Heuristic spacing: roughly the side of a square that holds ~8 civs.
    // Bounded below by 6 to avoid clumping on tiny test worlds.
    let min_distance = ((area as f64 / 16.0).sqrt() as i32).max(6);

    let mut picks: Vec<(i32, i32)> = Vec::with_capacity(specs.len());
    for tile_idx in &candidates {
        if picks.len() == specs.len() {
            break;
        }
        let x = (*tile_idx % dims.w as usize) as i32;
        let y = (*tile_idx / dims.w as usize) as i32;
        let far_enough = picks
            .iter()
            .all(|(px, py)| chebyshev((*px, *py), (x, y)) >= min_distance);
        if far_enough {
            picks.push((x, y));
        }
    }

    // Relax min_distance progressively if the world was too constrained.
    let mut effective_distance = min_distance;
    while picks.len() < specs.len() && effective_distance > 1 {
        effective_distance = (effective_distance * 3) / 4;
        picks.clear();
        for tile_idx in &candidates {
            if picks.len() == specs.len() {
                break;
            }
            let x = (*tile_idx % dims.w as usize) as i32;
            let y = (*tile_idx / dims.w as usize) as i32;
            let far_enough = picks
                .iter()
                .all(|(px, py)| chebyshev((*px, *py), (x, y)) >= effective_distance);
            if far_enough {
                picks.push((x, y));
            }
        }
    }

    if picks.len() < specs.len() {
        return Err(SpawnError::NotEnoughRoom {
            placed: picks.len() as u32,
            requested: specs.len() as u32,
        });
    }

    let founded_tick = world.clock.ticks();
    let mut out = Vec::with_capacity(specs.len());
    for (spec, (x, y)) in specs.iter().zip(picks) {
        // Insert civ first so the capital can reference it.
        let civ_id = world.civs.insert(Civilization {
            name: spec.name.clone(),
            endonym: spec.endonym.clone(),
            founded_tick,
            capital: CityId::NONE,
            language_id: spec.language_id,
            religion_id: 0,
            flag_id: 0,
            tradition_count: 0,
            color_rgb: spec.color_rgb,
        });

        // Insert capital city.
        let city_id = world.cities.insert(City {
            name: spec.capital_name.clone(),
            civ: civ_id,
            x,
            y,
            founded_tick,
            population: STARTING_CAPITAL_POPULATION,
            theme: spec.capital_theme,
            buildings: 0,
            walls: false,
        });

        // Wire capital into civ.
        if let Some(c) = world.civs.get_mut(civ_id) {
            c.capital = city_id;
        }

        // Stamp tile ownership + occupant. Slot index fits in u16 because
        // we cap civ count at MAX_STARTING_CIVS = 32.
        if let Some(tile) = world.tile_mut(x, y) {
            tile.owner = civ_id.0.idx().min(u16::MAX as u32) as u16;
            tile.city = city_id.0.idx().min(u16::MAX as u32) as u16;
            tile.pop = STARTING_CAPITAL_POPULATION.min(u16::MAX as u32) as u16;
        }

        // Record events.
        world.events.push(
            founded_tick,
            EventKind::CivFounded {
                civ: civ_id,
                name: spec.name.clone(),
            },
        );
        world.events.push(
            founded_tick,
            EventKind::CityFounded {
                city: city_id,
                civ: civ_id,
                x,
                y,
                name: spec.capital_name.clone(),
            },
        );

        out.push(SeededCiv {
            civ: civ_id,
            capital: city_id,
            x,
            y,
        });
    }

    Ok(out)
}

/// Found a single new city for an existing civ at runtime. Used by the
/// bridge layer's per-year spawn cadence.
///
/// Returns `Some(CityId)` on success. Returns `None` if `(x, y)` is out of
/// bounds, the tile is not settleable, the tile already hosts a city, or
/// `civ` is unknown.
pub fn found_city(
    world: &mut World,
    civ: CivId,
    x: i32,
    y: i32,
    name: String,
    theme: CityTheme,
    initial_population: u32,
) -> Option<CityId> {
    world.civs.get(civ)?;
    let tile = world.tile(x, y)?;
    if !tile.is_settleable() {
        return None;
    }
    if tile.city != u16::MAX {
        return None;
    }

    let founded_tick = world.clock.ticks();
    let city_id = world.cities.insert(City {
        name: name.clone(),
        civ,
        x,
        y,
        founded_tick,
        population: initial_population,
        theme,
        buildings: 0,
        walls: false,
    });

    if let Some(t) = world.tile_mut(x, y) {
        t.owner = civ.0.idx().min(u16::MAX as u32) as u16;
        t.city = city_id.0.idx().min(u16::MAX as u32) as u16;
        t.pop = initial_population.min(u16::MAX as u32) as u16;
    }
    world.events.push(
        founded_tick,
        EventKind::CityFounded {
            city: city_id,
            civ,
            x,
            y,
            name,
        },
    );
    Some(city_id)
}

/// Spawn `count` NPCs for `civ` at position `(cx, cy)`.
///
/// Names are supplied by the caller (generated via `babel_lang`). The
/// function assigns deterministic roles (first NPC = Ruler, second =
/// Chronicler, rest = Citizens) and randomised traits from `rng`.
///
/// Returns the ids of all successfully inserted NPCs.
pub fn spawn_npcs(world: &mut World, civ: CivId, cx: i32, cy: i32, names: &[String]) -> Vec<NpcId> {
    let tick = world.clock.ticks();
    let mut out = Vec::with_capacity(names.len());
    // Scatter starting NPCs in a 5×5 grid around the capital so they
    // don't all overlap on the same tile. Deterministic — driven by
    // index, not RNG.
    const SCATTER_R: i32 = 2;
    let dims = world.dims;
    for (i, name) in names.iter().enumerate() {
        // Place along a deterministic spiral inside [-2, 2]×[-2, 2].
        let dx = ((i % 5) as i32) - SCATTER_R;
        let dy = (((i / 5) % 5) as i32) - SCATTER_R;
        let mut nx = cx + dx;
        let mut ny = cy + dy;
        if dims.idx(nx, ny).is_none() {
            nx = cx;
            ny = cy;
        }
        let role = match i {
            0 => NpcRole::Ruler,
            1 => NpcRole::Chronicler,
            2 => NpcRole::Priest,
            3..=5 => NpcRole::Soldier,
            6 => NpcRole::Scholar,
            _ => NpcRole::Citizen,
        };
        let sex = if i & 1 == 0 { Sex::F } else { Sex::M };
        let traits = NpcTraits {
            loyalty: 50 + (world.rng.gen_range_u32(40) as u8),
            piety: 20 + (world.rng.gen_range_u32(60) as u8),
            curiosity: 20 + (world.rng.gen_range_u32(60) as u8),
            aggression: 10 + (world.rng.gen_range_u32(50) as u8),
            intellect: 30 + (world.rng.gen_range_u32(50) as u8),
            charisma: 20 + (world.rng.gen_range_u32(60) as u8),
            health: 80 + (world.rng.gen_range_u32(21) as u8),
            _pad: 0,
        };
        // Spawn with a varied "starting age" so day-1 doesn't look like a
        // crèche. We give initial NPCs a mix of late-teens through
        // early-30s in sim-years (5040..=11880 sim-days). Days_per_year
        // matches the calendar (`time_sys::DAYS_PER_YEAR`).
        let starting_age_years = 18 + world.rng.gen_range_u32(15); // 18..=32
        let age_days = starting_age_years * 360;
        let npc_id = world.npcs.insert(Npc {
            name: name.clone(),
            civ,
            x: nx,
            y: ny,
            birth_tick: tick,
            death_tick: u64::MAX,
            sex,
            traits,
            role,
            faction: FactionId::NONE,
            spouse: NpcId::NONE,
            mother: NpcId::NONE,
            father: NpcId::NONE,
            age_days,
            last_birth_day: u32::MAX,
            gestation_days: u16::MAX,
            home: BuildingId::NONE,
        });
        world
            .events
            .push(tick, EventKind::NpcBorn { npc: npc_id, civ });
        out.push(npc_id);
    }
    out
}

// ---------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------

fn chebyshev(a: (i32, i32), b: (i32, i32)) -> i32 {
    (a.0 - b.0).abs().max((a.1 - b.1).abs())
}

fn fisher_yates<T>(slice: &mut [T], rng: &mut DetRng) {
    if slice.len() < 2 {
        return;
    }
    for i in (1..slice.len()).rev() {
        let j = rng.gen_range_u32((i + 1) as u32) as usize;
        slice.swap(i, j);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::worldgen::{generate, WorldGenParams};
    use crate::{SimConfig, WorldDims};

    fn test_specs(n: usize) -> Vec<CivSpec> {
        (0..n)
            .map(|i| CivSpec {
                name: format!("Civ{i}"),
                endonym: format!("Endo{i}"),
                language_id: (i as u32) % 7,
                color_rgb: 0x336699 ^ (i as u32 * 0x010203),
                capital_name: format!("Cap{i}"),
                capital_theme: CityTheme::Memory,
            })
            .collect()
    }

    fn build_world(seed: u64, w: u32, h: u32) -> World {
        let cfg = SimConfig {
            seed,
            dims: WorldDims { w, h },
            starting_civs: 0,
            starting_npcs_per_civ: 0,
        };
        let mut world = World::new(&cfg).unwrap();
        generate(&mut world, &WorldGenParams::default()).unwrap();
        world
    }

    #[test]
    fn seeds_requested_count() {
        let mut w = build_world(0xABCD_1234, 64, 64);
        let specs = test_specs(4);
        let out = seed_world(&mut w, &specs).expect("seed ok");
        assert_eq!(out.len(), 4);
        assert_eq!(w.civs.len(), 4);
        assert_eq!(w.cities.len(), 4);
    }

    #[test]
    fn deterministic_for_same_seed() {
        let specs = test_specs(4);
        let mut w1 = build_world(0xDEAD_BEEF, 64, 64);
        let mut w2 = build_world(0xDEAD_BEEF, 64, 64);
        let r1 = seed_world(&mut w1, &specs).unwrap();
        let r2 = seed_world(&mut w2, &specs).unwrap();
        assert_eq!(r1.len(), r2.len());
        for (a, b) in r1.iter().zip(r2.iter()) {
            assert_eq!(a.x, b.x);
            assert_eq!(a.y, b.y);
        }
    }

    #[test]
    fn capitals_on_settleable_tiles() {
        let mut w = build_world(0x1234_5678, 64, 64);
        let specs = test_specs(4);
        let out = seed_world(&mut w, &specs).unwrap();
        for s in &out {
            let tile = w.tile(s.x, s.y).expect("tile in bounds");
            assert!(
                tile.is_settleable(),
                "capital at ({},{}) not on settleable biome: {:?}",
                s.x,
                s.y,
                tile.biome,
            );
            assert_ne!(
                tile.city,
                u16::MAX,
                "capital tile should have city id stamped"
            );
            assert_ne!(
                tile.owner,
                u16::MAX,
                "capital tile should have owner stamped"
            );
        }
    }

    #[test]
    fn capitals_minimum_distance() {
        let mut w = build_world(0xC0FE_BABE, 96, 96);
        let specs = test_specs(4);
        let out = seed_world(&mut w, &specs).unwrap();
        // Pairs should be at least a few tiles apart on a 96x96 map.
        for i in 0..out.len() {
            for j in (i + 1)..out.len() {
                let d = chebyshev((out[i].x, out[i].y), (out[j].x, out[j].y));
                assert!(d >= 3, "capitals {i} and {j} too close: d={d}");
            }
        }
    }

    #[test]
    fn pushes_founding_events() {
        let mut w = build_world(0xFEED_FACE, 64, 64);
        let specs = test_specs(3);
        seed_world(&mut w, &specs).unwrap();
        let civ_events = w
            .events
            .events
            .iter()
            .filter(|e| matches!(e.kind, EventKind::CivFounded { .. }))
            .count();
        let city_events = w
            .events
            .events
            .iter()
            .filter(|e| matches!(e.kind, EventKind::CityFounded { .. }))
            .count();
        assert_eq!(civ_events, 3);
        assert_eq!(city_events, 3);
    }

    #[test]
    fn empty_specs_is_ok() {
        let mut w = build_world(0, 32, 32);
        let out = seed_world(&mut w, &[]).unwrap();
        assert!(out.is_empty());
        assert_eq!(w.civs.len(), 0);
    }

    #[test]
    fn found_city_succeeds_on_settleable_tile() {
        let mut w = build_world(0x9999, 64, 64);
        let specs = test_specs(1);
        let seeded = seed_world(&mut w, &specs).unwrap();
        let parent = seeded[0];
        // Find any settleable tile not occupied by the capital.
        let mut child_xy = None;
        'outer: for dy in -8..=8 {
            for dx in -8..=8 {
                if dx == 0 && dy == 0 {
                    continue;
                }
                let tx = parent.x + dx;
                let ty = parent.y + dy;
                if let Some(t) = w.tile(tx, ty) {
                    if t.is_settleable() && t.city == u16::MAX {
                        child_xy = Some((tx, ty));
                        break 'outer;
                    }
                }
            }
        }
        let (cx, cy) = child_xy.expect("test world should have a free tile");
        let new_id = found_city(
            &mut w,
            parent.civ,
            cx,
            cy,
            "Childville".into(),
            CityTheme::Trade,
            10,
        );
        assert!(new_id.is_some());
        assert_eq!(w.cities.len(), 2);
    }

    #[test]
    fn found_city_rejects_occupied_tile() {
        let mut w = build_world(0xAAAA, 64, 64);
        let specs = test_specs(1);
        let seeded = seed_world(&mut w, &specs).unwrap();
        let parent = seeded[0];
        let result = found_city(
            &mut w,
            parent.civ,
            parent.x,
            parent.y,
            "OnTopOfCapital".into(),
            CityTheme::Memory,
            5,
        );
        assert!(result.is_none());
    }
}
