//! Entity storage.
//!
//! We do not pull in a full ECS crate (Bevy/hecs/legion). The sim is small
//! enough that custom typed slot-vectors give us:
//!
//! - Tighter control over memory layout (cache-friendly hot tables).
//! - Stable ids regardless of vector growth/compaction.
//! - Trivial serde (no archetype graphs to persist).
//! - No dependency drift.
//!
//! Each entity kind has its own [`SlotVec`]. Ids are `(index, generation)`
//! tuples packed into a single `u64` so dangling references are detectable.

use serde::{Deserialize, Serialize};

/// Strongly-typed id wrapper. Bit layout: low 32 = index, high 32 = generation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct EntityId(u64);

impl EntityId {
    /// Sentinel value meaning "no entity". All ones.
    pub const NONE: Self = Self(u64::MAX);

    fn pack(idx: u32, gen: u32) -> Self {
        Self((u64::from(gen) << 32) | u64::from(idx))
    }

    /// Index into the slot vec.
    #[must_use]
    pub fn idx(self) -> u32 {
        self.0 as u32
    }

    /// Generation counter.
    #[must_use]
    pub fn gen(self) -> u32 {
        (self.0 >> 32) as u32
    }

    /// `true` iff this is the sentinel "none" id.
    #[must_use]
    pub fn is_none(self) -> bool {
        self == Self::NONE
    }
}

/// Newtype wrappers prevent mixing up ids of different kinds at the type level.
macro_rules! id_newtype {
    ($name:ident, $doc:expr) => {
        #[doc = $doc]
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
        pub struct $name(pub EntityId);

        impl $name {
            /// Sentinel "none" value.
            pub const NONE: Self = Self(EntityId::NONE);

            /// `true` iff sentinel.
            #[must_use]
            pub fn is_none(self) -> bool {
                self.0.is_none()
            }
        }
    };
}

id_newtype!(NpcId, "Stable id for an NPC.");
id_newtype!(CityId, "Stable id for a city.");
id_newtype!(CivId, "Stable id for a civilization.");
id_newtype!(FactionId, "Stable id for a faction (rebel / cult / guild).");
id_newtype!(
    BuildingId,
    "Stable id for a building (granary, house, etc.)."
);

/// Generic slot-vector with generations. Insertions reuse free slots; removed
/// slots bump the generation counter so stale ids can be detected.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SlotVec<T> {
    items: Vec<Option<T>>,
    gens: Vec<u32>,
    free: Vec<u32>,
    len: u32,
}

impl<T> Default for SlotVec<T> {
    fn default() -> Self {
        Self {
            items: Vec::new(),
            gens: Vec::new(),
            free: Vec::new(),
            len: 0,
        }
    }
}

impl<T> SlotVec<T> {
    /// Number of live entries.
    #[must_use]
    pub fn len(&self) -> usize {
        self.len as usize
    }

    /// `true` if no live entries.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// Insert and return a new id.
    pub fn insert(&mut self, value: T) -> EntityId {
        if let Some(idx) = self.free.pop() {
            let gen = self.gens[idx as usize];
            self.items[idx as usize] = Some(value);
            self.len += 1;
            EntityId::pack(idx, gen)
        } else {
            let idx = self.items.len() as u32;
            self.items.push(Some(value));
            self.gens.push(0);
            self.len += 1;
            EntityId::pack(idx, 0)
        }
    }

    /// Look up by id, validating generation.
    #[must_use]
    pub fn get(&self, id: EntityId) -> Option<&T> {
        let idx = id.idx() as usize;
        if idx >= self.items.len() {
            return None;
        }
        if self.gens[idx] != id.gen() {
            return None;
        }
        self.items[idx].as_ref()
    }

    /// Mutable look-up by id.
    pub fn get_mut(&mut self, id: EntityId) -> Option<&mut T> {
        let idx = id.idx() as usize;
        if idx >= self.items.len() {
            return None;
        }
        if self.gens[idx] != id.gen() {
            return None;
        }
        self.items[idx].as_mut()
    }

    /// Remove and bump generation.
    pub fn remove(&mut self, id: EntityId) -> Option<T> {
        let idx = id.idx() as usize;
        if idx >= self.items.len() || self.gens[idx] != id.gen() {
            return None;
        }
        let v = self.items[idx].take()?;
        self.gens[idx] = self.gens[idx].wrapping_add(1);
        self.free.push(idx as u32);
        self.len -= 1;
        Some(v)
    }

    /// Iterate over `(id, &T)` for live entries, in **index order**.
    /// Index order is stable across runs given identical insert/remove
    /// sequences — required for determinism.
    pub fn iter(&self) -> impl Iterator<Item = (EntityId, &T)> {
        self.items.iter().enumerate().filter_map(move |(i, slot)| {
            slot.as_ref()
                .map(|v| (EntityId::pack(i as u32, self.gens[i]), v))
        })
    }

    /// Iterate over `(id, &mut T)`.
    pub fn iter_mut(&mut self) -> impl Iterator<Item = (EntityId, &mut T)> {
        let gens = &self.gens;
        self.items
            .iter_mut()
            .enumerate()
            .filter_map(move |(i, slot)| {
                slot.as_mut()
                    .map(|v| (EntityId::pack(i as u32, gens[i]), v))
            })
    }
}

// =====================================================================
// Component data types
// =====================================================================

/// Sex (kept simple — used for genealogy and procedural names only).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Sex {
    /// Male.
    M,
    /// Female.
    F,
}

/// One simulated person.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Npc {
    /// Display name (procedurally generated from civ's language).
    pub name: String,
    /// Owning civilization.
    pub civ: CivId,
    /// Tile coordinate.
    pub x: i32,
    /// Tile coordinate.
    pub y: i32,
    /// Birth tick. Used to derive age. For NPCs seeded with a non-zero
    /// starting age, [`Npc::age_days`] holds the actual ageable counter
    /// instead — `birth_tick` only records the tick of insertion.
    pub birth_tick: u64,
    /// Death tick, or `u64::MAX` if alive.
    pub death_tick: u64,
    /// Sex.
    pub sex: Sex,
    /// Stats — used by AI and event triggers. Keep this small (each field
    /// is `0..=100`).
    pub traits: NpcTraits,
    /// Current high-level role. Encoded as enum for cheap matching.
    pub role: NpcRole,
    /// Faction membership (or NONE).
    pub faction: FactionId,
    /// Spouse, if any.
    pub spouse: NpcId,
    /// Mother, if known.
    pub mother: NpcId,
    /// Father, if known.
    pub father: NpcId,
    // ----- Society loop: ageing, pairing, gestation, housing -----
    /// Age in sim-days. Incremented by the daily pulse. Decoupled from
    /// `birth_tick` so seeded adults can spawn at e.g. 18 sim-years old
    /// without back-dating the world clock.
    pub age_days: u32,
    /// Last day-of-sim on which this NPC gave birth, used as cooldown
    /// gate. `u32::MAX` = never.
    pub last_birth_day: u32,
    /// Days remaining in active gestation, or `u16::MAX` if not pregnant.
    pub gestation_days: u16,
    /// Home building, if any. `BuildingId::NONE` = no fixed home (yet).
    pub home: BuildingId,
}

/// Compact stat block. Total size 8 bytes.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NpcTraits {
    /// Loyalty to current ruler / civ. `0..=100`.
    pub loyalty: u8,
    /// Piety / religious devotion.
    pub piety: u8,
    /// Curiosity — drives discovery / heresy / migration.
    pub curiosity: u8,
    /// Aggression — drives violence / war.
    pub aggression: u8,
    /// Intellect — drives invention.
    pub intellect: u8,
    /// Charisma — drives leadership / faction formation.
    pub charisma: u8,
    /// Health — `0` is dead.
    pub health: u8,
    /// Reserved.
    pub _pad: u8,
}

/// High-level role used for selection in events. Cheap to match against.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum NpcRole {
    /// Ordinary citizen.
    Citizen,
    /// Civic / hereditary ruler.
    Ruler,
    /// Civilization-wide chronicler. Writes the book.
    Chronicler,
    /// Religious authority.
    Priest,
    /// Standing army member.
    Soldier,
    /// Researcher / inventor — unlocks knowledge nodes.
    Scholar,
    /// Faction leader.
    Rebel,
}

/// A settled urban centre.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct City {
    /// Display name.
    pub name: String,
    /// Owning civ.
    pub civ: CivId,
    /// Tile coordinate.
    pub x: i32,
    /// Tile coordinate.
    pub y: i32,
    /// Founding tick.
    pub founded_tick: u64,
    /// Sum of NPC populations + ambient pop on owned tiles.
    pub population: u32,
    /// Calvino-style abstract identity (set at founding).
    pub theme: CityTheme,
    /// Cumulative number of structures built.
    pub buildings: u16,
    /// Has city walls.
    pub walls: bool,
}

/// Calvino-inspired city archetype. Determines event templates and
/// procedural appearance.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CityTheme {
    /// Defined by mirrors, twins, doubles. Buildings reflect each other.
    Mirror,
    /// Defined by memory / archives. Always growing libraries and crypts.
    Memory,
    /// Defined by trade routes. Caravans, multilingual quarters.
    Trade,
    /// Defined by the dead — necropolis as much as living city.
    Death,
    /// Defined by water — canals, bridges, flooding.
    Water,
    /// Defined by signs / language — every wall is text.
    Signs,
    /// Defined by desire — garden, festival, marketplace.
    Desire,
    /// Defined by the sky — towers, observatories, oracles.
    Sky,
    /// Continuous — never sleeps, never silent.
    Continuous,
    /// Hidden — half its inhabitants live underground.
    Hidden,
    /// Thin — built improbably on cliffs / stilts.
    Thin,
    /// Eyes — its citizens watch each other constantly (Gormenghast hint).
    Eyes,
}

impl CityTheme {
    /// All themes, for procedural picking.
    pub const ALL: [Self; 12] = [
        Self::Mirror,
        Self::Memory,
        Self::Trade,
        Self::Death,
        Self::Water,
        Self::Signs,
        Self::Desire,
        Self::Sky,
        Self::Continuous,
        Self::Hidden,
        Self::Thin,
        Self::Eyes,
    ];
}

/// A nation / culture.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Civilization {
    /// Public display name.
    pub name: String,
    /// Self-name in their own generated language.
    pub endonym: String,
    /// Founding tick.
    pub founded_tick: u64,
    /// Capital city, if any.
    pub capital: CityId,
    /// Procedurally generated language id (lookup in `babel_lang`).
    pub language_id: u32,
    /// Religion id (lookup in religion table).
    pub religion_id: u32,
    /// Flag id (lookup in flag table — built from history events).
    pub flag_id: u32,
    /// Number of accumulated traditions.
    pub tradition_count: u16,
    /// Color RGB packed (used for map ownership rendering).
    pub color_rgb: u32,
}

/// A faction within a civ — the "thieves' guild" mechanic from the GDD.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Faction {
    /// Display name.
    pub name: String,
    /// Civ they exist within.
    pub civ: CivId,
    /// Founding tick.
    pub founded_tick: u64,
    /// Type / motivation.
    pub kind: FactionKind,
    /// Member count.
    pub members: u32,
    /// Hostility to civ ruler. `0..=100`.
    pub hostility: u8,
    /// Strength / capability. `0..=100`.
    pub strength: u8,
}

/// Type of placed structure. Visual-only for now; gameplay treats all
/// kinds the same (single-family residence).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum BuildingKind {
    /// Round-roof granary — the bootstrap residence used by the very
    /// first families before specialised house types are added.
    Granary = 0,
}

/// Construction stage for a [`Building`]. Stages are entered when the
/// build progress crosses fixed thresholds — see
/// [`BuildingStage::for_progress`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum BuildingStage {
    /// Foundation laid, no walls yet.
    Foundation = 0,
    /// Wooden frame visible, walls partial.
    Frame = 1,
    /// Walls complete, roof not yet placed.
    Walls = 2,
    /// Roofed but not yet trimmed — last visible WIP step.
    Roof = 3,
    /// Construction finished. Sprite is the final asset.
    Complete = 4,
}

/// Total construction time in sim-days. Drives stage thresholds and the
/// progress bar shown above the building.
pub const BUILDING_TOTAL_DAYS: u16 = 30;

impl BuildingStage {
    /// Decide which stage corresponds to a progress count in sim-days.
    /// Thresholds: 0–5 Foundation, 5–12 Frame, 12–22 Walls, 22–30 Roof,
    /// ≥30 Complete.
    #[must_use]
    pub fn for_progress(days: u16) -> Self {
        match days {
            0..=4 => Self::Foundation,
            5..=11 => Self::Frame,
            12..=21 => Self::Walls,
            22..=29 => Self::Roof,
            _ => Self::Complete,
        }
    }
}

/// One placed structure.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Building {
    /// Visual / functional kind.
    pub kind: BuildingKind,
    /// Tile coordinate (top-left for multi-tile footprints).
    pub x: i32,
    /// Tile coordinate.
    pub y: i32,
    /// Owning civ.
    pub civ: CivId,
    /// First owner of the pair, if any.
    pub owner_a: NpcId,
    /// Second owner of the pair, if any.
    pub owner_b: NpcId,
    /// Tick at which construction was started.
    pub founded_tick: u64,
    /// Construction progress in sim-days, capped at
    /// [`BUILDING_TOTAL_DAYS`].
    pub progress_days: u16,
    /// Cached stage; recomputed from `progress_days` each tick.
    pub stage: BuildingStage,
}

impl Building {
    /// Final stage reached?
    #[must_use]
    pub fn is_complete(&self) -> bool {
        self.stage == BuildingStage::Complete
    }
}

/// Why does a faction exist?
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum FactionKind {
    /// Wants to overthrow the ruler.
    Rebel,
    /// Religious dissent / heresy.
    Heretic,
    /// Trade guild — economic, not political (mostly).
    Guild,
    /// Underground criminal network.
    Underworld,
    /// Reformers — want to break a tradition cycle (Gormenghast).
    Reformer,
}

// =====================================================================
// Containers
// =====================================================================

/// All NPCs.
#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct Npcs(pub SlotVec<Npc>);
/// All cities.
#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct Cities(pub SlotVec<City>);
/// All civilizations.
#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct Civilizations(pub SlotVec<Civilization>);
/// All factions.
#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct Factions(pub SlotVec<Faction>);
/// All placed buildings.
#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct Buildings(pub SlotVec<Building>);

impl Npcs {
    /// Insert a new NPC, returning a typed id.
    pub fn insert(&mut self, npc: Npc) -> NpcId {
        NpcId(self.0.insert(npc))
    }
    /// Get by typed id.
    #[must_use]
    pub fn get(&self, id: NpcId) -> Option<&Npc> {
        self.0.get(id.0)
    }
    /// Get mut by typed id.
    pub fn get_mut(&mut self, id: NpcId) -> Option<&mut Npc> {
        self.0.get_mut(id.0)
    }
    /// Remove by typed id.
    pub fn remove(&mut self, id: NpcId) -> Option<Npc> {
        self.0.remove(id.0)
    }
    /// Live count.
    #[must_use]
    pub fn len(&self) -> usize {
        self.0.len()
    }
    /// True if empty.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
    /// Iterate `(id, &Npc)` in stable order.
    pub fn iter(&self) -> impl Iterator<Item = (NpcId, &Npc)> {
        self.0.iter().map(|(id, n)| (NpcId(id), n))
    }
    /// Iterate `(id, &mut Npc)`.
    pub fn iter_mut(&mut self) -> impl Iterator<Item = (NpcId, &mut Npc)> {
        self.0.iter_mut().map(|(id, n)| (NpcId(id), n))
    }
}

impl Cities {
    /// Insert.
    pub fn insert(&mut self, c: City) -> CityId {
        CityId(self.0.insert(c))
    }
    /// Get.
    #[must_use]
    pub fn get(&self, id: CityId) -> Option<&City> {
        self.0.get(id.0)
    }
    /// Mut get.
    pub fn get_mut(&mut self, id: CityId) -> Option<&mut City> {
        self.0.get_mut(id.0)
    }
    /// Remove.
    pub fn remove(&mut self, id: CityId) -> Option<City> {
        self.0.remove(id.0)
    }
    /// Live count.
    #[must_use]
    pub fn len(&self) -> usize {
        self.0.len()
    }
    /// Empty?
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
    /// Iter.
    pub fn iter(&self) -> impl Iterator<Item = (CityId, &City)> {
        self.0.iter().map(|(id, n)| (CityId(id), n))
    }
    /// Iter mut.
    pub fn iter_mut(&mut self) -> impl Iterator<Item = (CityId, &mut City)> {
        self.0.iter_mut().map(|(id, n)| (CityId(id), n))
    }
}

impl Civilizations {
    /// Insert.
    pub fn insert(&mut self, c: Civilization) -> CivId {
        CivId(self.0.insert(c))
    }
    /// Get.
    #[must_use]
    pub fn get(&self, id: CivId) -> Option<&Civilization> {
        self.0.get(id.0)
    }
    /// Mut get.
    pub fn get_mut(&mut self, id: CivId) -> Option<&mut Civilization> {
        self.0.get_mut(id.0)
    }
    /// Remove.
    pub fn remove(&mut self, id: CivId) -> Option<Civilization> {
        self.0.remove(id.0)
    }
    /// Live count.
    #[must_use]
    pub fn len(&self) -> usize {
        self.0.len()
    }
    /// Empty?
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
    /// Iter.
    pub fn iter(&self) -> impl Iterator<Item = (CivId, &Civilization)> {
        self.0.iter().map(|(id, n)| (CivId(id), n))
    }
    /// Iter mut.
    pub fn iter_mut(&mut self) -> impl Iterator<Item = (CivId, &mut Civilization)> {
        self.0.iter_mut().map(|(id, n)| (CivId(id), n))
    }
}

impl Factions {
    /// Insert.
    pub fn insert(&mut self, f: Faction) -> FactionId {
        FactionId(self.0.insert(f))
    }
    /// Get.
    #[must_use]
    pub fn get(&self, id: FactionId) -> Option<&Faction> {
        self.0.get(id.0)
    }
    /// Mut get.
    pub fn get_mut(&mut self, id: FactionId) -> Option<&mut Faction> {
        self.0.get_mut(id.0)
    }
    /// Remove.
    pub fn remove(&mut self, id: FactionId) -> Option<Faction> {
        self.0.remove(id.0)
    }
    /// Live count.
    #[must_use]
    pub fn len(&self) -> usize {
        self.0.len()
    }
    /// Empty?
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
    /// Iter.
    pub fn iter(&self) -> impl Iterator<Item = (FactionId, &Faction)> {
        self.0.iter().map(|(id, n)| (FactionId(id), n))
    }
    /// Iter mut.
    pub fn iter_mut(&mut self) -> impl Iterator<Item = (FactionId, &mut Faction)> {
        self.0.iter_mut().map(|(id, n)| (FactionId(id), n))
    }
}

impl Buildings {
    /// Insert.
    pub fn insert(&mut self, b: Building) -> BuildingId {
        BuildingId(self.0.insert(b))
    }
    /// Get.
    #[must_use]
    pub fn get(&self, id: BuildingId) -> Option<&Building> {
        self.0.get(id.0)
    }
    /// Mut get.
    pub fn get_mut(&mut self, id: BuildingId) -> Option<&mut Building> {
        self.0.get_mut(id.0)
    }
    /// Remove.
    pub fn remove(&mut self, id: BuildingId) -> Option<Building> {
        self.0.remove(id.0)
    }
    /// Live count.
    #[must_use]
    pub fn len(&self) -> usize {
        self.0.len()
    }
    /// Empty?
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
    /// Iter.
    pub fn iter(&self) -> impl Iterator<Item = (BuildingId, &Building)> {
        self.0.iter().map(|(id, n)| (BuildingId(id), n))
    }
    /// Iter mut.
    pub fn iter_mut(&mut self) -> impl Iterator<Item = (BuildingId, &mut Building)> {
        self.0.iter_mut().map(|(id, n)| (BuildingId(id), n))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slotvec_insert_get_remove() {
        let mut sv: SlotVec<i32> = SlotVec::default();
        let a = sv.insert(10);
        let b = sv.insert(20);
        assert_eq!(sv.len(), 2);
        assert_eq!(*sv.get(a).unwrap(), 10);
        assert_eq!(*sv.get(b).unwrap(), 20);
        assert_eq!(sv.remove(a), Some(10));
        assert!(sv.get(a).is_none()); // stale
        let c = sv.insert(30); // reuses a's slot
        assert_eq!(c.idx(), a.idx());
        assert_ne!(c.gen(), a.gen()); // but new generation
    }

    #[test]
    fn id_size_and_layout() {
        // Whole id round-trips to/from u64 cleanly.
        let id = EntityId::pack(0xCAFE, 0xBABE);
        assert_eq!(id.idx(), 0xCAFE);
        assert_eq!(id.gen(), 0xBABE);
    }

    #[test]
    fn typed_ids_dont_mix() {
        // Compile-time-only test — we simply assert the wrappers exist and
        // do not implicitly convert.
        let _: NpcId = NpcId::NONE;
        let _: CivId = CivId::NONE;
    }
}
