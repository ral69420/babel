//! Pure-Rust bridge layer.
//!
//! Every method exposed to GDScript via [`gd_class`](super::gd_class) maps
//! 1:1 to a method on [`SimHandle`]. This means the engine-bound class is a
//! thin wrapper, and `cargo test` covers all the actual logic.

use babel_sim::tick::TimeScale;
use babel_sim::worldgen::{generate, WorldGenParams};
use babel_sim::{SimConfig, World, WorldDims};

/// A long-lived simulation handle. Owns a [`World`] and exposes a stable
/// API to the host (Godot or test harness).
#[derive(Debug)]
pub struct SimHandle {
    world: Option<World>,
    last_error: Option<String>,
}

impl Default for SimHandle {
    fn default() -> Self {
        Self::new()
    }
}

impl SimHandle {
    /// Empty handle. Call [`SimHandle::start`] to populate.
    #[must_use]
    pub fn new() -> Self {
        Self {
            world: None,
            last_error: None,
        }
    }

    /// `true` if a world has been started successfully.
    #[must_use]
    pub fn is_ready(&self) -> bool {
        self.world.is_some()
    }

    /// Most recent error, or empty string. Cleared by any successful call.
    #[must_use]
    pub fn last_error(&self) -> &str {
        self.last_error.as_deref().unwrap_or("")
    }

    /// Boot a fresh world. Replaces any existing one.
    pub fn start(&mut self, seed: u64, width: u32, height: u32) -> bool {
        self.last_error = None;
        let cfg = SimConfig {
            seed,
            dims: WorldDims {
                w: width,
                h: height,
            },
            starting_civs: 0,
            starting_npcs_per_civ: 0,
        };
        let mut world = match World::new(&cfg) {
            Ok(w) => w,
            Err(e) => {
                self.last_error = Some(e.to_string());
                return false;
            }
        };
        if let Err(e) = generate(&mut world, &WorldGenParams::default()) {
            self.last_error = Some(e.to_string());
            return false;
        }
        self.world = Some(world);
        true
    }

    /// Set time scale. `0=Paused, 1=Normal, 4=Fast, 16=VeryFast, 64=Debug`.
    pub fn set_time_scale(&mut self, scale: u32) -> bool {
        let Some(world) = self.world.as_mut() else {
            self.last_error = Some("no world".into());
            return false;
        };
        let s = match scale {
            0 => TimeScale::Paused,
            1 => TimeScale::Normal,
            4 => TimeScale::Fast,
            16 => TimeScale::VeryFast,
            64 => TimeScale::Debug,
            _ => {
                self.last_error = Some("invalid scale".into());
                return false;
            }
        };
        world.clock.set_scale(s);
        true
    }

    /// Advance the sim by `frame_ticks * scale`. Returns ticks applied.
    pub fn advance(&mut self, frame_ticks: u32) -> u32 {
        let Some(world) = self.world.as_mut() else {
            self.last_error = Some("no world".into());
            return 0;
        };
        let n = world.clock.advance_frame(frame_ticks);
        for _ in 0..n {
            world.run_systems_one_tick();
        }
        n
    }

    /// Current tick count.
    #[must_use]
    pub fn ticks(&self) -> u64 {
        self.world.as_ref().map_or(0, |w| w.clock.ticks())
    }

    /// Current year (decoded calendar).
    #[must_use]
    pub fn year(&self) -> u32 {
        self.world.as_ref().map_or(0, |w| w.calendar().year)
    }

    /// `(width, height)` of the current world, or `(0, 0)`.
    #[must_use]
    pub fn dims(&self) -> (u32, u32) {
        self.world.as_ref().map_or((0, 0), |w| (w.dims.w, w.dims.h))
    }

    /// Read tile biome as `u8`. Returns `255` for out-of-bounds.
    #[must_use]
    pub fn tile_biome(&self, x: i32, y: i32) -> u8 {
        let Some(world) = self.world.as_ref() else {
            return 255;
        };
        match world.tile(x, y) {
            Some(t) => t.biome as u8,
            None => 255,
        }
    }

    /// Read elevation `0..=255`. Returns `0` for out-of-bounds.
    #[must_use]
    pub fn tile_elevation(&self, x: i32, y: i32) -> u8 {
        self.world
            .as_ref()
            .and_then(|w| w.tile(x, y))
            .map_or(0, |t| t.elevation)
    }

    /// Read tag bitfield. Returns `0` for out-of-bounds.
    #[must_use]
    pub fn tile_tags(&self, x: i32, y: i32) -> u16 {
        self.world
            .as_ref()
            .and_then(|w| w.tile(x, y))
            .map_or(0, |t| t.tags)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn start_then_advance() {
        let mut h = SimHandle::new();
        assert!(!h.is_ready());
        assert!(h.start(1, 32, 32));
        assert!(h.is_ready());
        assert_eq!(h.dims(), (32, 32));
        assert_eq!(h.advance(10), 10);
        assert_eq!(h.ticks(), 10);
    }

    #[test]
    fn paused_does_not_advance() {
        let mut h = SimHandle::new();
        assert!(h.start(1, 8, 8));
        assert!(h.set_time_scale(0));
        assert_eq!(h.advance(100), 0);
        assert_eq!(h.ticks(), 0);
    }

    #[test]
    fn out_of_bounds_returns_sentinels() {
        let mut h = SimHandle::new();
        assert!(h.start(1, 4, 4));
        assert_eq!(h.tile_biome(-1, 0), 255);
        assert_eq!(h.tile_elevation(99, 99), 0);
    }

    #[test]
    fn invalid_scale_sets_error() {
        let mut h = SimHandle::new();
        assert!(h.start(1, 4, 4));
        assert!(!h.set_time_scale(7));
        assert!(!h.last_error().is_empty());
    }
}
