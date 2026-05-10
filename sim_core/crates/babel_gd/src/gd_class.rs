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

    /// Number of live civilizations.
    #[func]
    fn civ_count(&self) -> i32 {
        self.inner.civ_count() as i32
    }

    /// Name of the `idx`-th civilization.
    #[func]
    fn civ_name(&self, idx: i32) -> GString {
        GString::from(self.inner.civ_name(idx.max(0) as u32))
    }

    /// Number of live cities.
    #[func]
    fn city_count(&self) -> i32 {
        self.inner.city_count() as i32
    }

    /// Name of the `idx`-th city.
    #[func]
    fn city_name(&self, idx: i32) -> GString {
        GString::from(self.inner.city_name(idx.max(0) as u32))
    }

    /// Position `(x, y)` of the `idx`-th city.
    #[func]
    fn city_pos(&self, idx: i32) -> Vector2i {
        let (x, y) = self.inner.city_pos(idx.max(0) as u32);
        Vector2i::new(x, y)
    }

    /// Population of the `idx`-th city.
    #[func]
    fn city_population(&self, idx: i32) -> i32 {
        self.inner.city_population(idx.max(0) as u32) as i32
    }

    /// Up to `max` most-recent events as headline strings.
    #[func]
    fn recent_events(&self, max: i32) -> PackedStringArray {
        let evts = self.inner.recent_events(max.max(0) as u32);
        let mut arr = PackedStringArray::new();
        for e in evts {
            arr.push(&GString::from(e));
        }
        arr
    }

    /// Number of live NPCs.
    #[func]
    fn npc_count(&self) -> i32 {
        self.inner.npc_count() as i32
    }

    /// Name of the `idx`-th live NPC.
    #[func]
    fn npc_name(&self, idx: i32) -> GString {
        GString::from(self.inner.npc_name(idx.max(0) as u32))
    }

    /// Role of the `idx`-th live NPC.
    #[func]
    fn npc_role(&self, idx: i32) -> GString {
        GString::from(self.inner.npc_role(idx.max(0) as u32))
    }

    /// Civ name of the `idx`-th live NPC.
    #[func]
    fn npc_civ_name(&self, idx: i32) -> GString {
        GString::from(self.inner.npc_civ_name(idx.max(0) as u32))
    }

    /// Position of the `idx`-th live NPC.
    #[func]
    fn npc_pos(&self, idx: i32) -> Vector2i {
        let (x, y) = self.inner.npc_pos(idx.max(0) as u32);
        Vector2i::new(x, y)
    }

    /// Health of the `idx`-th live NPC.
    #[func]
    fn npc_health(&self, idx: i32) -> i32 {
        i32::from(self.inner.npc_health(idx.max(0) as u32))
    }

    /// Age in sim-years of the `idx`-th live NPC.
    #[func]
    fn npc_age_years(&self, idx: i32) -> i32 {
        self.inner.npc_age_years(idx.max(0) as u32) as i32
    }

    /// Age in sim-days of the `idx`-th live NPC.
    #[func]
    fn npc_age_days(&self, idx: i32) -> i32 {
        self.inner.npc_age_days(idx.max(0) as u32) as i32
    }

    /// Sex (`"M"` / `"F"`) of the `idx`-th live NPC.
    #[func]
    fn npc_sex(&self, idx: i32) -> GString {
        GString::from(self.inner.npc_sex(idx.max(0) as u32))
    }

    /// Life-state string (`"child"` / `"single"` / `"paired"` /
    /// `"pregnant"`) for the `idx`-th live NPC.
    #[func]
    fn npc_state(&self, idx: i32) -> GString {
        GString::from(self.inner.npc_state(idx.max(0) as u32))
    }

    /// Number of placed buildings (any stage).
    #[func]
    fn building_count(&self) -> i32 {
        self.inner.building_count() as i32
    }

    /// Position of the `idx`-th building.
    #[func]
    fn building_pos(&self, idx: i32) -> Vector2i {
        let (x, y) = self.inner.building_pos(idx.max(0) as u32);
        Vector2i::new(x, y)
    }

    /// Construction stage index for the `idx`-th building.
    /// 0 Foundation, 1 Frame, 2 Walls, 3 Roof, 4 Complete.
    #[func]
    fn building_stage(&self, idx: i32) -> i32 {
        i32::from(self.inner.building_stage(idx.max(0) as u32))
    }

    /// Build progress 0..=100 for the `idx`-th building.
    #[func]
    fn building_progress_pct(&self, idx: i32) -> i32 {
        self.inner.building_progress_pct(idx.max(0) as u32) as i32
    }

    /// Kind name (`"Granary"`, …) for the `idx`-th building.
    #[func]
    fn building_kind(&self, idx: i32) -> GString {
        GString::from(self.inner.building_kind(idx.max(0) as u32))
    }

    /// Summon a Strugatsky "Zone" anomaly at `(x, y)`. Returns tiles tagged.
    #[func]
    fn summon_zone(&mut self, x: i32, y: i32) -> i32 {
        self.inner.summon_zone(x, y) as i32
    }
}
