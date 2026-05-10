//! `babel_chronicle` — template-based chronicle writer.
//!
//! The chronicle is the auto-generated history book for a civilization. It is
//! written by an in-world chronicler NPC. Each chronicler has a small,
//! deterministic stylistic profile (tone bias, sentence-length bias) that
//! shifts how templates are filled.
//!
//! **No LLM, no AI.** Templates are hand-authored TOML files in
//! `content/chronicle_templates/`. Slots are filled deterministically from
//! the [`babel_sim::Event`] log + [`babel_lang::Language`] for procedurally
//! generated names.
//!
//! ## Template format
//!
//! ```toml
//! [[entry]]
//! id = "civ_founded_001"
//! kind = "CivFounded"
//! lines = [
//!     "In the year {year}, the people of {civ_endonym} first gathered under one banner.",
//!     "It is said that the elders called themselves the {civ_endonym}, meaning 'the chosen'.",
//! ]
//! ```

#![deny(missing_docs)]

use serde::{Deserialize, Serialize};

use babel_sim::{Calendar, DetRng, Event, EventKind, World};

/// One chronicle entry template.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EntryTemplate {
    /// Stable id (used for save migration + content authoring).
    pub id: String,
    /// Which event kind this template handles.
    pub kind: String,
    /// Candidate text lines. Picked deterministically per chronicler style.
    pub lines: Vec<String>,
}

/// Raw template file as parsed from TOML.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateFile {
    /// Set of entries.
    #[serde(default, rename = "entry")]
    pub entries: Vec<EntryTemplate>,
}

/// Parse errors.
#[derive(Debug, thiserror::Error)]
pub enum ChronicleError {
    /// TOML parse failure.
    #[error("toml parse: {0}")]
    Toml(#[from] toml::de::Error),
    /// Required slot missing in a template.
    #[error("missing slot {slot} in template {id}")]
    MissingSlot {
        /// Slot name.
        slot: String,
        /// Template id.
        id: String,
    },
}

/// Loaded template library.
#[derive(Debug, Clone)]
pub struct TemplateLib {
    by_kind: ahash::AHashMap<String, Vec<EntryTemplate>>,
}

impl Default for TemplateLib {
    fn default() -> Self {
        Self {
            by_kind: ahash::AHashMap::new(),
        }
    }
}

impl TemplateLib {
    /// Empty library.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Add templates from a parsed TOML file.
    pub fn add_file(&mut self, file: TemplateFile) {
        for e in file.entries {
            self.by_kind.entry(e.kind.clone()).or_default().push(e);
        }
    }

    /// Parse + add a TOML string.
    pub fn add_toml(&mut self, s: &str) -> Result<(), ChronicleError> {
        let f: TemplateFile = toml::from_str(s)?;
        self.add_file(f);
        Ok(())
    }

    /// Number of templates of the given kind.
    #[must_use]
    pub fn count(&self, kind: &str) -> usize {
        self.by_kind.get(kind).map_or(0, Vec::len)
    }

    /// Total templates across all kinds.
    #[must_use]
    pub fn total(&self) -> usize {
        self.by_kind.values().map(Vec::len).sum()
    }

    /// Pick a template for an event kind. Selection is deterministic given
    /// the RNG state.
    fn pick<'a>(&'a self, kind: &str, rng: &mut DetRng) -> Option<&'a EntryTemplate> {
        let pool = self.by_kind.get(kind)?;
        rng.pick(pool.as_slice())
    }
}

/// Stylistic profile of a chronicler. Deterministic — derived once at
/// chronicler appointment from their NPC traits.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct ChroniclerStyle {
    /// Bias toward formal vs colloquial. `0..=100`.
    pub formality: u8,
    /// Bias toward dramatic vs neutral phrasing. `0..=100`.
    pub drama: u8,
    /// Bias toward focusing on individuals vs the masses. `0..=100`.
    pub personalism: u8,
    /// Stable RNG seed for "which line gets picked".
    pub rng_seed: u64,
}

impl ChroniclerStyle {
    /// Build from NPC traits + seed.
    #[must_use]
    pub fn from_traits(traits: &babel_sim::entity::NpcTraits, seed: u64) -> Self {
        Self {
            formality: traits.intellect,
            drama: traits.charisma,
            personalism: traits.curiosity,
            rng_seed: seed,
        }
    }
}

/// Rendered chronicle entry — what ends up in the book.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChronicleEntry {
    /// Year of the event.
    pub year: u32,
    /// Day of year.
    pub day: u32,
    /// Final rendered text.
    pub text: String,
}

/// Renders one event into a chronicle entry.
///
/// Returns `None` if no template matched the event kind. Caller is expected
/// to log + skip in that case.
#[must_use]
pub fn render_event(
    event: &Event,
    world: &World,
    lib: &TemplateLib,
    style: &ChroniclerStyle,
) -> Option<ChronicleEntry> {
    let cal = Calendar::from_ticks(event.tick);
    let kind = event_kind_name(&event.kind);
    let mut rng = DetRng::from_seed(style.rng_seed.wrapping_add(event.tick));
    let template = lib.pick(kind, &mut rng)?;
    let line = template.lines.first()?.clone();
    let text = fill_slots(&line, &cal, &event.kind, world);
    Some(ChronicleEntry {
        year: cal.year,
        day: cal.day_of_year,
        text,
    })
}

/// Render all unread events into entries. Acks the log when done.
#[must_use]
pub fn drain_events(
    world: &mut World,
    lib: &TemplateLib,
    style: &ChroniclerStyle,
) -> Vec<ChronicleEntry> {
    let mut out = Vec::new();
    let unread_len = world.events.unread().len();
    let mut events = Vec::with_capacity(unread_len);
    events.extend_from_slice(world.events.unread());
    for ev in &events {
        if let Some(entry) = render_event(ev, world, lib, style) {
            out.push(entry);
        }
    }
    world.events.ack_all();
    out
}

fn event_kind_name(kind: &EventKind) -> &'static str {
    match kind {
        EventKind::WorldGenerated { .. } => "WorldGenerated",
        EventKind::CivFounded { .. } => "CivFounded",
        EventKind::CityFounded { .. } => "CityFounded",
        EventKind::NpcBorn { .. } => "NpcBorn",
        EventKind::NpcDied { .. } => "NpcDied",
        EventKind::TraditionAdopted { .. } => "TraditionAdopted",
        EventKind::TraditionBroken { .. } => "TraditionBroken",
        EventKind::FactionFounded { .. } => "FactionFounded",
        EventKind::WarDeclared { .. } => "WarDeclared",
        EventKind::PeaceMade { .. } => "PeaceMade",
        EventKind::ConceptFading { .. } => "ConceptFading",
        EventKind::ZoneAppeared { .. } => "ZoneAppeared",
        EventKind::NpcPaired { .. } => "NpcPaired",
        EventKind::BuildingFounded { .. } => "BuildingFounded",
        EventKind::BuildingCompleted { .. } => "BuildingCompleted",
        EventKind::Flavour { .. } => "Flavour",
    }
}

fn fill_slots(line: &str, cal: &Calendar, kind: &EventKind, world: &World) -> String {
    let mut out = String::with_capacity(line.len() + 16);
    let mut i = 0;
    let bytes = line.as_bytes();
    while i < bytes.len() {
        if bytes[i] == b'{' {
            if let Some(end) = line[i + 1..].find('}') {
                let slot = &line[i + 1..i + 1 + end];
                if let Some(val) = resolve_slot(slot, cal, kind, world) {
                    out.push_str(&val);
                } else {
                    out.push('{');
                    out.push_str(slot);
                    out.push('}');
                }
                i = i + 1 + end + 1;
                continue;
            }
        }
        // Push one UTF-8 char.
        let c = line[i..].chars().next().expect("valid utf-8");
        out.push(c);
        i += c.len_utf8();
    }
    out
}

fn resolve_slot(slot: &str, cal: &Calendar, kind: &EventKind, world: &World) -> Option<String> {
    match slot {
        "year" => Some(cal.year.to_string()),
        "day" => Some(cal.day_of_year.to_string()),
        "civ_name" => match kind {
            EventKind::CivFounded { civ, .. }
            | EventKind::TraditionAdopted { civ, .. }
            | EventKind::TraditionBroken { civ, .. }
            | EventKind::FactionFounded { civ, .. }
            | EventKind::ConceptFading { civ, .. }
            | EventKind::CityFounded { civ, .. } => world.civs.get(*civ).map(|c| c.name.clone()),
            _ => None,
        },
        "civ_endonym" => match kind {
            EventKind::CivFounded { civ, .. }
            | EventKind::TraditionAdopted { civ, .. }
            | EventKind::TraditionBroken { civ, .. }
            | EventKind::FactionFounded { civ, .. }
            | EventKind::ConceptFading { civ, .. }
            | EventKind::CityFounded { civ, .. } => world.civs.get(*civ).map(|c| c.endonym.clone()),
            _ => None,
        },
        "city_name" => match kind {
            EventKind::CityFounded { city, .. } => world.cities.get(*city).map(|c| c.name.clone()),
            _ => None,
        },
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use babel_sim::{SimConfig, World, WorldDims};

    fn world() -> World {
        World::new(&SimConfig {
            seed: 0,
            dims: WorldDims { w: 4, h: 4 },
            starting_civs: 0,
            starting_npcs_per_civ: 0,
        })
        .unwrap()
    }

    #[test]
    fn template_lib_loads() {
        let toml = r#"
[[entry]]
id = "wg_001"
kind = "WorldGenerated"
lines = ["In the beginning was the seed."]
"#;
        let mut lib = TemplateLib::new();
        lib.add_toml(toml).unwrap();
        assert_eq!(lib.count("WorldGenerated"), 1);
    }

    #[test]
    fn render_basic() {
        let toml = r#"
[[entry]]
id = "wg_001"
kind = "WorldGenerated"
lines = ["Year {year}: the world was born."]
"#;
        let mut lib = TemplateLib::new();
        lib.add_toml(toml).unwrap();
        let style = ChroniclerStyle {
            formality: 50,
            drama: 50,
            personalism: 50,
            rng_seed: 0,
        };
        let world = world();
        let event = Event {
            tick: 0,
            kind: EventKind::WorldGenerated { seed: 1 },
        };
        let rendered = render_event(&event, &world, &lib, &style).unwrap();
        assert_eq!(rendered.text, "Year 0: the world was born.");
    }

    #[test]
    fn unknown_slot_left_as_literal() {
        let mut lib = TemplateLib::new();
        lib.add_toml(
            r#"
[[entry]]
id = "wg_001"
kind = "WorldGenerated"
lines = ["{not_a_slot} stays"]
"#,
        )
        .unwrap();
        let style = ChroniclerStyle {
            formality: 0,
            drama: 0,
            personalism: 0,
            rng_seed: 0,
        };
        let world = world();
        let event = Event {
            tick: 0,
            kind: EventKind::WorldGenerated { seed: 0 },
        };
        let rendered = render_event(&event, &world, &lib, &style).unwrap();
        assert_eq!(rendered.text, "{not_a_slot} stays");
    }
}
