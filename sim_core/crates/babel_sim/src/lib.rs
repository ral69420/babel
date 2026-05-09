//! `babel_sim` — deterministic, engine-agnostic simulation core for Babel.
//!
//! ## Invariants
//!
//! 1. **No engine deps.** This crate must compile and run under `cargo test`
//!    with no Godot, no SDL, nothing. `babel_gd` is the only crate that links
//!    a game engine.
//! 2. **Determinism.** All randomness flows through [`det_rng::DetRng`]. There
//!    is no `std::time`, no `rand::thread_rng`, no `HashMap` iteration on
//!    output paths (use [`ahash::AHashMap`] only for internal lookups, never
//!    for ordering-dependent iteration; use `BTreeMap` or sorted vecs when
//!    iteration order matters).
//! 3. **Fixed-tick.** The sim is driven by [`tick::TickClock`] at a fixed
//!    rate. Wall-clock time does not enter the sim.
//! 4. **No global state.** Everything hangs off [`World`].
//!
//! ## Layout
//!
//! - [`det_rng`]   — seedable xoroshiro256++ RNG
//! - [`tick`]      — fixed timestep clock + scheduling
//! - [`time_sys`]  — in-game calendar (year/season/day)
//! - [`world`]     — tile map + biomes
//! - [`entity`]    — NPCs, cities, civilizations, factions
//! - [`event`]     — event log (consumed by chronicle layer)
//! - [`worldgen`]  — initial world generation (Perlin)

#![deny(missing_docs)]

pub mod det_rng;
pub mod entity;
pub mod event;
pub mod tick;
pub mod time_sys;
pub mod world;
pub mod worldgen;

mod systems;

pub use det_rng::DetRng;
pub use entity::{CityId, CivId, FactionId, NpcId};
pub use event::{Event, EventKind, EventLog};
pub use tick::TickClock;
pub use time_sys::{Calendar, Season};
pub use world::{Biome, Tile, World, WorldDims};

use serde::{Deserialize, Serialize};

/// Top-level configuration for a new sim instance.
///
/// Kept small and serializable — full config lives in `content/sim_config.toml`
/// and is loaded by the host (Godot or test harness) before constructing this.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimConfig {
    /// Seed for the master RNG.  All other RNGs are derived from this.
    pub seed: u64,
    /// Map dimensions (width, height) in tiles.
    pub dims: WorldDims,
    /// Number of starting civilizations.
    pub starting_civs: u32,
    /// Number of starting NPCs per civilization.
    pub starting_npcs_per_civ: u32,
}

impl Default for SimConfig {
    fn default() -> Self {
        Self {
            seed: 0x000B_ABE1_u64,
            dims: WorldDims { w: 256, h: 256 },
            starting_civs: 4,
            starting_npcs_per_civ: 25,
        }
    }
}

/// Errors that can occur while running the sim.
#[derive(Debug, thiserror::Error)]
pub enum SimError {
    /// Configuration provided to [`World::new`] is invalid (e.g. zero-sized
    /// map).
    #[error("invalid sim config: {0}")]
    InvalidConfig(&'static str),
    /// A system tried to access an entity that no longer exists.  This should
    /// be impossible — if you see this in the wild it is a bug.
    #[error("entity not found: {0}")]
    EntityNotFound(u64),
}

/// Result type used throughout the crate.
pub type SimResult<T> = std::result::Result<T, SimError>;
