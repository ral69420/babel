//! Pure-Rust bridge layer.
//!
//! Every method exposed to GDScript via [`gd_class`](super::gd_class) maps
//! 1:1 to a method on [`SimHandle`]. This means the engine-bound class is a
//! thin wrapper, and `cargo test` covers all the actual logic.

use babel_lang::{default_languages, Culture, Language};
use babel_sim::event::{Event, EventKind};
use babel_sim::spawn::{self, CivSpec};
use babel_sim::tick::TimeScale;
use babel_sim::worldgen::{generate, WorldGenParams};
use babel_sim::{CityTheme, SimConfig, World, WorldDims};

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
        let starting_civs = 4u32;
        let cfg = SimConfig {
            seed,
            dims: WorldDims {
                w: width,
                h: height,
            },
            starting_civs,
            starting_npcs_per_civ: 25,
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

        // Build CivSpecs from babel_lang-generated names.
        let langs = default_languages();
        let mut name_rng = world.rng.fork();
        let specs = build_civ_specs(&mut name_rng, &langs, starting_civs);
        let seeded = match spawn::seed_world(&mut world, &specs) {
            Ok(s) => s,
            Err(e) => {
                self.last_error = Some(e.to_string());
                return false;
            }
        };

        // Spawn starting NPCs per civ at each capital.
        let npcs_per_civ = cfg.starting_npcs_per_civ;
        for sc in &seeded {
            let culture_idx = world.civs.get(sc.civ).map_or(0, |c| c.language_id as usize);
            let lang = &langs[culture_idx % langs.len()];
            let names: Vec<String> = (0..npcs_per_civ)
                .map(|_| lang.name(&mut name_rng))
                .collect();
            spawn::spawn_npcs(&mut world, sc.civ, sc.x, sc.y, &names);
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

    /// Current day-of-year `0..=359`.
    #[must_use]
    pub fn day_of_year(&self) -> u32 {
        self.world.as_ref().map_or(0, |w| w.calendar().day_of_year)
    }

    /// Current hour-of-day `0..=23`.
    #[must_use]
    pub fn hour(&self) -> u32 {
        self.world.as_ref().map_or(0, |w| w.calendar().hour)
    }

    /// Season as `u8` — 0=Spring, 1=Summer, 2=Autumn, 3=Winter.
    #[must_use]
    pub fn season(&self) -> u8 {
        self.world.as_ref().map_or(0, |w| {
            use babel_sim::Season;
            match w.calendar().season() {
                Season::Spring => 0,
                Season::Summer => 1,
                Season::Autumn => 2,
                Season::Winter => 3,
            }
        })
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

    /// Number of live civilizations.
    #[must_use]
    pub fn civ_count(&self) -> u32 {
        self.world.as_ref().map_or(0, |w| w.civs.len() as u32)
    }

    /// Name of the `idx`-th civilization (iteration order). Empty if invalid.
    #[must_use]
    pub fn civ_name(&self, idx: u32) -> String {
        self.world
            .as_ref()
            .and_then(|w| w.civs.iter().nth(idx as usize))
            .map_or_else(String::new, |(_, c)| c.name.clone())
    }

    /// Number of live cities.
    #[must_use]
    pub fn city_count(&self) -> u32 {
        self.world.as_ref().map_or(0, |w| w.cities.len() as u32)
    }

    /// Name of the `idx`-th city. Empty if invalid.
    #[must_use]
    pub fn city_name(&self, idx: u32) -> String {
        self.world
            .as_ref()
            .and_then(|w| w.cities.iter().nth(idx as usize))
            .map_or_else(String::new, |(_, c)| c.name.clone())
    }

    /// Position of the `idx`-th city. Returns `(-1, -1)` if invalid.
    #[must_use]
    pub fn city_pos(&self, idx: u32) -> (i32, i32) {
        self.world
            .as_ref()
            .and_then(|w| w.cities.iter().nth(idx as usize))
            .map_or((-1, -1), |(_, c)| (c.x, c.y))
    }

    /// Population of the `idx`-th city. Returns 0 if invalid.
    #[must_use]
    pub fn city_population(&self, idx: u32) -> u32 {
        self.world
            .as_ref()
            .and_then(|w| w.cities.iter().nth(idx as usize))
            .map_or(0, |(_, c)| c.population)
    }

    /// Up to `max` most-recent events as short headline strings.
    #[must_use]
    pub fn recent_events(&self, max: u32) -> Vec<String> {
        let Some(world) = self.world.as_ref() else {
            return Vec::new();
        };
        let events = &world.events.events;
        let start = events.len().saturating_sub(max as usize);
        events[start..]
            .iter()
            .rev()
            .map(|e| event_headline(e, world))
            .collect()
    }

    /// Number of live (not dead) NPCs.
    #[must_use]
    pub fn npc_count(&self) -> u32 {
        self.world.as_ref().map_or(0, |w| {
            w.npcs
                .iter()
                .filter(|(_, n)| n.death_tick == u64::MAX)
                .count() as u32
        })
    }

    /// Name of the `idx`-th live NPC. Empty if invalid.
    #[must_use]
    pub fn npc_name(&self, idx: u32) -> String {
        self.world
            .as_ref()
            .and_then(|w| {
                w.npcs
                    .iter()
                    .filter(|(_, n)| n.death_tick == u64::MAX)
                    .nth(idx as usize)
            })
            .map_or_else(String::new, |(_, n)| n.name.clone())
    }

    /// Role of the `idx`-th live NPC as a string.
    #[must_use]
    pub fn npc_role(&self, idx: u32) -> String {
        self.world
            .as_ref()
            .and_then(|w| {
                w.npcs
                    .iter()
                    .filter(|(_, n)| n.death_tick == u64::MAX)
                    .nth(idx as usize)
            })
            .map_or_else(String::new, |(_, n)| format!("{:?}", n.role))
    }

    /// Civ name of the `idx`-th live NPC.
    #[must_use]
    pub fn npc_civ_name(&self, idx: u32) -> String {
        self.world
            .as_ref()
            .and_then(|w| {
                let (_, npc) = w
                    .npcs
                    .iter()
                    .filter(|(_, n)| n.death_tick == u64::MAX)
                    .nth(idx as usize)?;
                w.civs.get(npc.civ).map(|c| c.name.clone())
            })
            .unwrap_or_default()
    }

    /// Position of the `idx`-th live NPC. Returns `(-1, -1)` if invalid.
    #[must_use]
    pub fn npc_pos(&self, idx: u32) -> (i32, i32) {
        self.world
            .as_ref()
            .and_then(|w| {
                w.npcs
                    .iter()
                    .filter(|(_, n)| n.death_tick == u64::MAX)
                    .nth(idx as usize)
            })
            .map_or((-1, -1), |(_, n)| (n.x, n.y))
    }

    /// Health of the `idx`-th live NPC (0..=100).
    #[must_use]
    pub fn npc_health(&self, idx: u32) -> u8 {
        self.world
            .as_ref()
            .and_then(|w| {
                w.npcs
                    .iter()
                    .filter(|(_, n)| n.death_tick == u64::MAX)
                    .nth(idx as usize)
            })
            .map_or(0, |(_, n)| n.traits.health)
    }

    /// Summon a Strugatsky "Zone" anomaly at `(x, y)`. Returns the number of
    /// tiles tagged.
    pub fn summon_zone(&mut self, x: i32, y: i32) -> u32 {
        let Some(world) = self.world.as_mut() else {
            self.last_error = Some("no world".into());
            return 0;
        };
        world.summon_zone(x, y)
    }
}

// =====================================================================
// Helpers
// =====================================================================

/// Map ownership palette (packed 0xRRGGBB). Indexing wraps.
const CIV_COLORS: [u32; 8] = [
    0xB0_30_30, // Red
    0x30_70_B0, // Blue
    0x40_90_40, // Green
    0xB0_80_20, // Gold
    0x80_40_A0, // Purple
    0x20_A0_90, // Teal
    0xB0_60_20, // Orange
    0x60_60_60, // Grey
];

/// Build `n` [`CivSpec`]s using procedural names from babel_lang.
fn build_civ_specs(rng: &mut babel_sim::DetRng, langs: &[Language], n: u32) -> Vec<CivSpec> {
    let cultures = Culture::ALL;
    (0..n)
        .map(|i| {
            let culture = cultures[i as usize % cultures.len()];
            let lang = &langs[culture.id() as usize];
            let name = lang.name(rng);
            let endonym = lang.name(rng);
            let capital_name = lang.city_name(rng);
            let theme_idx = rng.gen_range_u32(CityTheme::ALL.len() as u32) as usize;
            CivSpec {
                name,
                endonym,
                language_id: culture.id(),
                color_rgb: CIV_COLORS[i as usize % CIV_COLORS.len()],
                capital_name,
                capital_theme: CityTheme::ALL[theme_idx],
            }
        })
        .collect()
}

/// Format an [`Event`] into a short human-readable headline.
fn event_headline(event: &Event, world: &World) -> String {
    match &event.kind {
        EventKind::WorldGenerated { seed } => {
            format!("World generated (seed {seed:#X})")
        }
        EventKind::CivFounded { name, .. } => {
            format!("Civilization {name} founded")
        }
        EventKind::CityFounded { name, x, y, .. } => {
            format!("City {name} founded at ({x},{y})")
        }
        EventKind::NpcBorn { npc, .. } => {
            format!("NPC {:?} born", npc.0.idx())
        }
        EventKind::NpcDied { npc, cause } => {
            format!("NPC {:?} died ({cause:?})", npc.0.idx())
        }
        EventKind::TraditionAdopted { tradition_id, .. } => {
            format!("Tradition #{tradition_id} adopted")
        }
        EventKind::TraditionBroken { tradition_id, .. } => {
            format!("Tradition #{tradition_id} broken")
        }
        EventKind::FactionFounded { .. } => "Faction founded".to_string(),
        EventKind::WarDeclared { attacker, defender } => {
            let a = world.civs.get(*attacker).map_or("?", |c| c.name.as_str());
            let d = world.civs.get(*defender).map_or("?", |c| c.name.as_str());
            format!("{a} declared war on {d}")
        }
        EventKind::PeaceMade { a, b } => {
            let na = world.civs.get(*a).map_or("?", |c| c.name.as_str());
            let nb = world.civs.get(*b).map_or("?", |c| c.name.as_str());
            format!("Peace between {na} and {nb}")
        }
        EventKind::ConceptFading { concept_id, .. } => {
            format!("Concept #{concept_id} fading")
        }
        EventKind::ZoneAppeared { x, y } => {
            format!("Zone anomaly at ({x},{y})")
        }
        EventKind::Flavour { template_id, .. } => {
            format!("Event #{template_id}")
        }
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

    #[test]
    fn start_seeds_four_civs_and_cities() {
        let mut h = SimHandle::new();
        assert!(h.start(0x000B_ABE1, 64, 64));
        assert_eq!(h.civ_count(), 4);
        assert_eq!(h.city_count(), 4);
        for i in 0..4 {
            assert!(!h.civ_name(i).is_empty(), "civ {i} should have a name");
            assert!(!h.city_name(i).is_empty(), "city {i} should have a name");
            let (x, y) = h.city_pos(i);
            assert!(x >= 0 && y >= 0, "city {i} should be on map");
            assert!(h.city_population(i) > 0, "city {i} should have pop");
        }
    }

    #[test]
    fn start_spawns_npcs() {
        let mut h = SimHandle::new();
        assert!(h.start(0x000B_ABE1, 64, 64));
        // 4 civs * 25 NPCs each = 100
        assert_eq!(h.npc_count(), 100);
        assert!(!h.npc_name(0).is_empty());
        let role = h.npc_role(0);
        assert!(!role.is_empty());
        assert!(!h.npc_civ_name(0).is_empty());
        let (x, y) = h.npc_pos(0);
        assert!(x >= 0 && y >= 0);
        assert!(h.npc_health(0) > 0);
    }

    #[test]
    fn recent_events_includes_founding() {
        let mut h = SimHandle::new();
        assert!(h.start(0x000B_ABE1, 64, 64));
        let evts = h.recent_events(200);
        // worldgen + 4 civs + 4 cities + 100 NPCs born
        assert!(
            evts.len() >= 9,
            "should have at least worldgen+founding events"
        );
        assert!(evts.iter().any(|e| e.contains("founded")));
    }

    #[test]
    fn summon_zone_works() {
        let mut h = SimHandle::new();
        assert!(h.start(1, 32, 32));
        let tagged = h.summon_zone(10, 10);
        assert!(tagged > 0);
        let evts = h.recent_events(5);
        assert!(evts.iter().any(|e| e.contains("Zone")));
    }
}
