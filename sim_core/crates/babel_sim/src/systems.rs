//! Per-tick simulation systems.
//!
//! Kept as a private module — the only public entry point is
//! [`run_one_tick`], called from [`crate::world::World::run_systems_one_tick`].
//!
//! Each system takes `&mut World` and runs in a fixed, documented order. The
//! ordering is part of the determinism contract — never reorder casually.

use crate::entity::{NpcRole, NpcTraits, Sex};
use crate::event::{DeathCause, EventKind};
use crate::time_sys::TICKS_PER_YEAR;
use crate::world::World;

/// Drive everything that happens in a single tick. Order:
///
/// 1. `aging` — increment age, mark very old NPCs for death roll.
/// 2. `mortality` — health-driven deaths.
/// 3. `daily_pulse` — once per game-day systems (births, social drift).
/// 4. `yearly_pulse` — once per game-year systems (tradition drift, faction
///    formation, war declarations).
///
/// Currently the systems are intentionally minimal — this scaffolding exists
/// to lock the call order and tick boundaries.
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
    }
}

fn daily_pulse(w: &mut World, _tick: u64) {
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
}

fn yearly_pulse(w: &mut World, _tick: u64) {
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
}
