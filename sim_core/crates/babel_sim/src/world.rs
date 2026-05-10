//! Tile-based world: dimensions, biomes, terrain, civilization ownership.
//!
//! The world is the root of the sim state. Everything that gets saved hangs
//! off of here.
//!
//! # Memory layout
//!
//! Tiles are stored in a single flat `Vec<Tile>` of size `w * h`. Index by
//! `y * w + x`. Tiles are intentionally small (16 bytes) so a 256×256 map
//! is ~1 MiB and fits comfortably in L2.

use serde::{Deserialize, Serialize};

use crate::det_rng::DetRng;
use crate::entity::{Cities, Civilizations, Factions, Npcs};
use crate::event::EventLog;
use crate::tick::TickClock;
use crate::time_sys::Calendar;
use crate::{SimConfig, SimError, SimResult};

/// Map dimensions in tiles. Capped at `4096 * 4096` to keep indices in `u32`
/// and to make sure a single allocation never blows past sane RAM limits.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorldDims {
    /// Width in tiles. Must be `> 0` and `<= 4096`.
    pub w: u32,
    /// Height in tiles. Must be `> 0` and `<= 4096`.
    pub h: u32,
}

impl WorldDims {
    /// Total tile count (`w * h`).
    #[must_use]
    pub fn area(self) -> usize {
        self.w as usize * self.h as usize
    }

    /// Validate. Bounds: `1..=4096` per axis.
    pub fn validate(self) -> SimResult<()> {
        if self.w == 0 || self.h == 0 {
            return Err(SimError::InvalidConfig("world dims must be > 0"));
        }
        if self.w > 4096 || self.h > 4096 {
            return Err(SimError::InvalidConfig("world dims must be <= 4096"));
        }
        Ok(())
    }

    /// Convert `(x, y)` to flat index. Returns `None` if out of bounds.
    #[must_use]
    pub fn idx(self, x: i32, y: i32) -> Option<usize> {
        if x < 0 || y < 0 {
            return None;
        }
        let (xu, yu) = (x as u32, y as u32);
        if xu >= self.w || yu >= self.h {
            return None;
        }
        Some(yu as usize * self.w as usize + xu as usize)
    }
}

/// Coarse biome class for a tile.
///
/// We deliberately keep this small (8 variants, 1 byte) — visual variation
/// comes from elevation/moisture/temperature gradients in the renderer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum Biome {
    /// Deep ocean, impassable to land units.
    Ocean = 0,
    /// Coast or shallow sea.
    Coast = 1,
    /// Plain grassland — best for farming.
    Plains = 2,
    /// Forest — provides wood, restricts movement slightly.
    Forest = 3,
    /// Hills — moderate movement cost, defensive bonus.
    Hills = 4,
    /// Mountains — impassable to most units, source of stone/ore.
    Mountain = 5,
    /// Desert — low food, high travel cost.
    Desert = 6,
    /// Tundra — low food, harsh winters.
    Tundra = 7,
}

/// 16-byte tile. Anything bigger goes in side tables, not here.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(C)]
pub struct Tile {
    /// Biome class.
    pub biome: Biome,
    /// Elevation in 0..=255 (display + worldgen).
    pub elevation: u8,
    /// Moisture in 0..=255.
    pub moisture: u8,
    /// Temperature in 0..=255 (255 = hot equator, 0 = polar cold).
    pub temperature: u8,
    /// Owning civilization, or `u16::MAX` if unclaimed.
    pub owner: u16,
    /// Population on this tile (clamped to `u16::MAX`).
    pub pop: u16,
    /// City id occupying this tile, or `u16::MAX` if none.
    pub city: u16,
    /// Tags (bitfield: ruin, sacred, river, road, …).
    pub tags: u16,
    /// Reserved for future packing — keeps the struct at 16 B for cache
    /// alignment.
    pub _reserved_a: u16,
    /// Reserved for future packing.
    pub _reserved_b: u16,
}

/// Bitfield flags for [`Tile::tags`].
pub mod tile_tags {
    /// Ruin from a previous civilization (Harrison: "inverted progression").
    pub const RUIN: u16 = 1 << 0;
    /// Sacred site — modifies traditions, magic, religion.
    pub const SACRED: u16 = 1 << 1;
    /// River runs through. Movement bonus, wet biome.
    pub const RIVER: u16 = 1 << 2;
    /// Road built by some civ.
    pub const ROAD: u16 = 1 << 3;
    /// "Zone" anomaly (Strugatsky: alien artifacts here).
    pub const ZONE: u16 = 1 << 4;
    /// "Fading" — concept that's been forgotten lives here (Memory Police).
    pub const FADED: u16 = 1 << 5;
}

impl Tile {
    /// Empty plains tile, no owner.
    #[must_use]
    pub const fn empty() -> Self {
        Self {
            biome: Biome::Plains,
            elevation: 128,
            moisture: 128,
            temperature: 128,
            owner: u16::MAX,
            pop: 0,
            city: u16::MAX,
            tags: 0,
            _reserved_a: 0,
            _reserved_b: 0,
        }
    }

    /// `true` if a tile can support a city / agriculture.
    #[must_use]
    pub fn is_settleable(&self) -> bool {
        matches!(
            self.biome,
            Biome::Plains | Biome::Forest | Biome::Hills | Biome::Coast
        )
    }

    /// Test a tag bit.
    #[must_use]
    pub fn has_tag(&self, tag: u16) -> bool {
        self.tags & tag != 0
    }

    /// Set a tag bit.
    pub fn set_tag(&mut self, tag: u16) {
        self.tags |= tag;
    }

    /// Clear a tag bit.
    pub fn clear_tag(&mut self, tag: u16) {
        self.tags &= !tag;
    }
}

const _: () = {
    // Compile-time assertion that Tile is exactly 16 bytes.
    let _ = [(); 16 - std::mem::size_of::<Tile>()];
    let _ = [(); std::mem::size_of::<Tile>() - 16];
};

/// The whole world. `World` is the only `&mut` you ever need to thread.
#[derive(Debug, Serialize, Deserialize)]
pub struct World {
    /// Map dimensions.
    pub dims: WorldDims,
    /// Flat tile grid, `dims.area()` long.
    pub tiles: Vec<Tile>,
    /// Master clock.
    pub clock: TickClock,
    /// Master RNG. Each subsystem forks its own from here at boot.
    pub rng: DetRng,
    /// Event log (consumed by chronicle layer).
    pub events: EventLog,
    /// Civilization storage.
    pub civs: Civilizations,
    /// City storage.
    pub cities: Cities,
    /// NPC storage (citizens + special characters).
    pub npcs: Npcs,
    /// Faction storage (rebel groups, religious orders, guilds).
    pub factions: Factions,
    /// Sim version — bumped on schema-breaking changes; save migrations key off
    /// this.
    pub sim_version: u32,
}

/// Current sim schema version. Bump on any change to a serialized struct.
pub const SIM_VERSION: u32 = 1;

impl World {
    /// Construct a new empty world from config. Does not run worldgen.
    pub fn new(cfg: &SimConfig) -> SimResult<Self> {
        cfg.dims.validate()?;
        let area = cfg.dims.area();
        Ok(Self {
            dims: cfg.dims,
            tiles: vec![Tile::empty(); area],
            clock: TickClock::new(),
            rng: DetRng::from_seed(cfg.seed),
            events: EventLog::default(),
            civs: Civilizations::default(),
            cities: Cities::default(),
            npcs: Npcs::default(),
            factions: Factions::default(),
            sim_version: SIM_VERSION,
        })
    }

    /// Read tile by `(x, y)`, returning `None` if out of bounds.
    #[must_use]
    pub fn tile(&self, x: i32, y: i32) -> Option<&Tile> {
        self.dims.idx(x, y).map(|i| &self.tiles[i])
    }

    /// Mutable read of tile by `(x, y)`.
    pub fn tile_mut(&mut self, x: i32, y: i32) -> Option<&mut Tile> {
        let i = self.dims.idx(x, y)?;
        Some(&mut self.tiles[i])
    }

    /// Decoded current calendar.
    #[must_use]
    pub fn calendar(&self) -> Calendar {
        Calendar::from_ticks(self.clock.ticks())
    }

    /// Advance the simulation by N raw ticks. Used by tests, replay, headless
    /// host. Real-time hosts should use [`crate::tick::TickClock::advance_frame`]
    /// then call [`World::run_systems`] themselves.
    pub fn step(&mut self, ticks: u32) {
        for _ in 0..ticks {
            self.clock.advance_raw(1);
            self.run_systems_one_tick();
        }
    }

    /// Run all systems for exactly one tick. The host may call this directly
    /// after advancing the clock by N ticks if it wants to fold ticks into
    /// fewer system invocations (e.g. a "fast forward" mode that runs systems
    /// every Nth tick).
    pub fn run_systems_one_tick(&mut self) {
        crate::systems::run_one_tick(self);
    }

    /// Tag `(cx, cy)` and its 8-neighbours with [`tile_tags::ZONE`] and push
    /// a [`crate::event::EventKind::ZoneAppeared`] event. This is the
    /// Strugatsky "Roadside Picnic" anomaly hook the player can fire from
    /// the host (e.g. on Z key).
    ///
    /// Returns the number of tiles successfully tagged (1..=9, depending on
    /// boundary clipping). Returns `0` if the centre tile itself was out of
    /// bounds.
    pub fn summon_zone(&mut self, cx: i32, cy: i32) -> u32 {
        if self.tile(cx, cy).is_none() {
            return 0;
        }
        let mut tagged = 0u32;
        for dy in -1..=1 {
            for dx in -1..=1 {
                if let Some(tile) = self.tile_mut(cx + dx, cy + dy) {
                    tile.set_tag(tile_tags::ZONE);
                    tagged += 1;
                }
            }
        }
        let tick = self.clock.ticks();
        self.events
            .push(tick, crate::event::EventKind::ZoneAppeared { x: cx, y: cy });
        tagged
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::SimConfig;

    #[test]
    fn dims_validate() {
        assert!(WorldDims { w: 0, h: 1 }.validate().is_err());
        assert!(WorldDims { w: 1, h: 0 }.validate().is_err());
        assert!(WorldDims { w: 8192, h: 1 }.validate().is_err());
        assert!(WorldDims { w: 256, h: 256 }.validate().is_ok());
    }

    #[test]
    fn tile_size_is_16() {
        assert_eq!(std::mem::size_of::<Tile>(), 16);
    }

    #[test]
    fn world_construct_zeroed() {
        let cfg = SimConfig {
            seed: 0,
            dims: WorldDims { w: 8, h: 8 },
            starting_civs: 0,
            starting_npcs_per_civ: 0,
        };
        let w = World::new(&cfg).unwrap();
        assert_eq!(w.tiles.len(), 64);
        assert_eq!(w.tiles[0], Tile::empty());
        assert_eq!(w.clock.ticks(), 0);
    }

    #[test]
    fn out_of_bounds_returns_none() {
        let cfg = SimConfig {
            seed: 0,
            dims: WorldDims { w: 4, h: 4 },
            starting_civs: 0,
            starting_npcs_per_civ: 0,
        };
        let w = World::new(&cfg).unwrap();
        assert!(w.tile(-1, 0).is_none());
        assert!(w.tile(0, -1).is_none());
        assert!(w.tile(4, 0).is_none());
        assert!(w.tile(0, 4).is_none());
        assert!(w.tile(3, 3).is_some());
    }

    #[test]
    fn summon_zone_tags_3x3_and_pushes_event() {
        let cfg = SimConfig {
            seed: 0,
            dims: WorldDims { w: 8, h: 8 },
            starting_civs: 0,
            starting_npcs_per_civ: 0,
        };
        let mut w = World::new(&cfg).unwrap();
        let tagged = w.summon_zone(4, 4);
        assert_eq!(tagged, 9, "interior cell should tag full 3x3");
        for dy in -1..=1 {
            for dx in -1..=1 {
                let t = w.tile(4 + dx, 4 + dy).unwrap();
                assert!(t.has_tag(tile_tags::ZONE));
            }
        }
        // Outside the 3x3 should NOT be tagged.
        assert!(!w.tile(2, 4).unwrap().has_tag(tile_tags::ZONE));
        // Event recorded.
        assert_eq!(w.events.len(), 1);
        let ev = &w.events.events[0];
        match ev.kind {
            crate::event::EventKind::ZoneAppeared { x, y } => {
                assert_eq!((x, y), (4, 4));
            }
            ref other => panic!("expected ZoneAppeared, got {other:?}"),
        }
    }

    #[test]
    fn summon_zone_clips_at_corner() {
        let cfg = SimConfig {
            seed: 0,
            dims: WorldDims { w: 4, h: 4 },
            starting_civs: 0,
            starting_npcs_per_civ: 0,
        };
        let mut w = World::new(&cfg).unwrap();
        // Top-left corner — only 4 tiles should be reachable.
        let tagged = w.summon_zone(0, 0);
        assert_eq!(tagged, 4);
    }

    #[test]
    fn summon_zone_rejects_out_of_bounds() {
        let cfg = SimConfig {
            seed: 0,
            dims: WorldDims { w: 4, h: 4 },
            starting_civs: 0,
            starting_npcs_per_civ: 0,
        };
        let mut w = World::new(&cfg).unwrap();
        assert_eq!(w.summon_zone(-1, 0), 0);
        assert_eq!(w.summon_zone(0, 4), 0);
        assert!(w.events.is_empty());
    }
}
