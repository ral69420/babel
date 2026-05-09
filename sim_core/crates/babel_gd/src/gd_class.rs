//! Godot-facing wrapper. Compiled only with `--features gdext`.
//!
//! Stays as thin as possible: every method delegates to [`SimHandle`] in
//! `bridge.rs`. The point of separating them is so the heavy lifting can be
//! unit-tested under `cargo test` without a Godot install.

use godot::prelude::*;

use crate::bridge::SimHandle;

/// `BabelSim` — registered as a `Resource` in Godot. GDScript holds one of
/// these and calls into it. We deliberately use `Resource` (not `Node`) so
/// the sim survives scene reloads.
#[derive(GodotClass)]
#[class(base=Resource, init)]
pub struct BabelSim {
    inner: SimHandle,
    base: Base<Resource>,
}

#[godot_api]
impl BabelSim {
    /// Boot a new world.
    #[func]
    fn start(&mut self, seed: i64, width: i32, height: i32) -> bool {
        let seed = seed as u64;
        let w = width.max(0) as u32;
        let h = height.max(0) as u32;
        self.inner.start(seed, w, h)
    }

    /// `0=Paused, 1=Normal, 4=Fast, 16=VeryFast, 64=Debug`.
    #[func]
    fn set_time_scale(&mut self, scale: i32) -> bool {
        let s = scale.max(0) as u32;
        self.inner.set_time_scale(s)
    }

    /// Advance by `frame_ticks * scale`. Returns ticks applied.
    #[func]
    fn advance(&mut self, frame_ticks: i32) -> i32 {
        let n = frame_ticks.max(0) as u32;
        self.inner.advance(n) as i32
    }

    /// Current year.
    #[func]
    fn year(&self) -> i32 {
        self.inner.year() as i32
    }

    /// Day of year `0..=359`.
    #[func]
    fn day_of_year(&self) -> i32 {
        self.inner.day_of_year() as i32
    }

    /// Hour of day `0..=23`.
    #[func]
    fn hour(&self) -> i32 {
        self.inner.hour() as i32
    }

    /// Season `0..=3` (Spring/Summer/Autumn/Winter).
    #[func]
    fn season(&self) -> i32 {
        i32::from(self.inner.season())
    }

    /// Current ticks.
    #[func]
    fn ticks(&self) -> i64 {
        self.inner.ticks() as i64
    }

    /// `(width, height)` of the current world.
    #[func]
    fn dims(&self) -> Vector2i {
        let (w, h) = self.inner.dims();
        Vector2i::new(w as i32, h as i32)
    }

    /// Biome class as `u8`. `255` = out of bounds.
    #[func]
    fn tile_biome(&self, x: i32, y: i32) -> i32 {
        i32::from(self.inner.tile_biome(x, y))
    }

    /// Elevation `0..=255`.
    #[func]
    fn tile_elevation(&self, x: i32, y: i32) -> i32 {
        i32::from(self.inner.tile_elevation(x, y))
    }

    /// Tag bitfield.
    #[func]
    fn tile_tags(&self, x: i32, y: i32) -> i32 {
        i32::from(self.inner.tile_tags(x, y))
    }

    /// Last error message; empty if last call succeeded.
    #[func]
    fn last_error(&self) -> GString {
        GString::from(self.inner.last_error())
    }
}
