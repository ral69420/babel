//! In-sim event log.
//!
//! Every meaningful state change pushes an [`Event`] to the world's
//! [`EventLog`]. The chronicle layer reads from the log to write the book.
//! Events are the *only* way the chronicle layer learns about the sim, which
//! decouples the two cleanly: tests can swap a fake chronicler in.
//!
//! ## Why a log and not callbacks?
//!
//! - Determinism: ordering is explicit and serializable.
//! - Snapshot-friendly: the log is part of the save.
//! - Replayable: a recorded log can be re-read into a fresh chronicle.
//!
//! ## Capacity
//!
//! Events are bounded. Old events past [`EventLog::CAPACITY`] are
//! summarized into a "compact era" record by the chronicle worker before
//! eviction — actual eviction happens off the hot path.

use serde::{Deserialize, Serialize};

use crate::entity::{BuildingId, CityId, CivId, FactionId, NpcId};

/// Maximum number of raw events held in the log before summarisation.
pub const DEFAULT_CAPACITY: usize = 65_536;

/// Event payload. New variants are *additive* — never reorder or remove,
/// or save-format compatibility breaks. Bump `SIM_VERSION` when adding.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EventKind {
    /// World was generated.
    WorldGenerated {
        /// Seed used.
        seed: u64,
    },
    /// A civilization was founded.
    CivFounded {
        /// New civ.
        civ: CivId,
        /// Display name at founding.
        name: String,
    },
    /// A city was founded.
    CityFounded {
        /// City id.
        city: CityId,
        /// Owning civ.
        civ: CivId,
        /// Tile (x, y).
        x: i32,
        /// Tile (x, y).
        y: i32,
        /// Display name.
        name: String,
    },
    /// An NPC was born.
    NpcBorn {
        /// New NPC.
        npc: NpcId,
        /// Civ.
        civ: CivId,
    },
    /// An NPC died.
    NpcDied {
        /// Decedent.
        npc: NpcId,
        /// Cause (encoded — chronicle layer maps to template).
        cause: DeathCause,
    },
    /// A new tradition was adopted by a civ.
    TraditionAdopted {
        /// Civ.
        civ: CivId,
        /// Tradition id (lookup in content/traditions).
        tradition_id: u32,
    },
    /// A tradition was abandoned (Gormenghast reformer mechanic).
    TraditionBroken {
        /// Civ.
        civ: CivId,
        /// Tradition id.
        tradition_id: u32,
        /// Faction that drove the break, if any.
        by_faction: FactionId,
    },
    /// A faction was founded.
    FactionFounded {
        /// New faction.
        faction: FactionId,
        /// Within civ.
        civ: CivId,
        /// Why.
        kind_repr: u8,
    },
    /// War declared between two civs.
    WarDeclared {
        /// Aggressor.
        attacker: CivId,
        /// Target.
        defender: CivId,
    },
    /// Peace concluded.
    PeaceMade {
        /// Civ A.
        a: CivId,
        /// Civ B.
        b: CivId,
    },
    /// A concept began fading from memory (Memory Police mechanic).
    ConceptFading {
        /// Civ where the concept is fading.
        civ: CivId,
        /// Concept id (from content/concepts).
        concept_id: u32,
    },
    /// A "Zone" anomaly appeared (Strugatsky).
    ZoneAppeared {
        /// Tile.
        x: i32,
        /// Tile.
        y: i32,
    },
    /// Two NPCs paired up. Both `partner_id`s are now set on each.
    NpcPaired {
        /// First partner.
        a: NpcId,
        /// Second partner.
        b: NpcId,
    },
    /// A foundation was laid for a new building.
    BuildingFounded {
        /// New building id.
        building: BuildingId,
        /// Owning civ.
        civ: CivId,
        /// Tile (x, y).
        x: i32,
        /// Tile (x, y).
        y: i32,
    },
    /// A building reached the `Complete` stage.
    BuildingCompleted {
        /// Building id.
        building: BuildingId,
        /// Owning civ.
        civ: CivId,
    },
    /// Generic flavour event from a content template.
    /// Used when no engine-level event applies but the chronicle should
    /// record something (festivals, omens, etc.).
    Flavour {
        /// Template id (lookup in content/chronicle_templates).
        template_id: u32,
        /// Optional civ context.
        civ: CivId,
        /// Optional NPC context.
        npc: NpcId,
    },
}

/// Cause of death codes. New entries are additive.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum DeathCause {
    /// Old age — the only natural cause currently used by the systems.
    OldAge = 0,
    /// Sickness / plague.
    Sickness = 1,
    /// Killed in combat / war.
    Combat = 2,
    /// Killed in faction violence.
    FactionViolence = 3,
    /// Famine.
    Famine = 4,
    /// Accident / fall / drowning.
    Accident = 5,
    /// Sacrifice (ritual).
    Sacrifice = 6,
    /// Unknown / unrecorded.
    Unknown = 255,
}

/// One event entry, time-stamped.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    /// Tick at which the event occurred.
    pub tick: u64,
    /// Payload.
    pub kind: EventKind,
}

/// Append-only log with a soft cap. The chronicle worker is responsible for
/// summarisation + eviction (it owns the read cursor).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventLog {
    /// All events in insertion order.
    pub events: Vec<Event>,
    /// Read cursor for the chronicle worker. Events with index `< cursor`
    /// have been processed and may be summarised.
    pub cursor: usize,
    /// Soft cap before summarisation kicks in.
    pub capacity: usize,
}

impl Default for EventLog {
    fn default() -> Self {
        Self {
            events: Vec::with_capacity(DEFAULT_CAPACITY / 8),
            cursor: 0,
            capacity: DEFAULT_CAPACITY,
        }
    }
}

impl EventLog {
    /// Capacity convenience for callers.
    pub const CAPACITY: usize = DEFAULT_CAPACITY;

    /// Append an event.
    pub fn push(&mut self, tick: u64, kind: EventKind) {
        self.events.push(Event { tick, kind });
    }

    /// Slice of events not yet read by the chronicle worker.
    #[must_use]
    pub fn unread(&self) -> &[Event] {
        &self.events[self.cursor..]
    }

    /// Mark all events up to `len()` as read.
    pub fn ack_all(&mut self) {
        self.cursor = self.events.len();
    }

    /// Total event count.
    #[must_use]
    pub fn len(&self) -> usize {
        self.events.len()
    }

    /// `true` if no events.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.events.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn push_and_ack() {
        let mut l = EventLog::default();
        l.push(0, EventKind::WorldGenerated { seed: 1 });
        l.push(1, EventKind::WorldGenerated { seed: 2 });
        assert_eq!(l.unread().len(), 2);
        l.ack_all();
        assert_eq!(l.unread().len(), 0);
    }
}
