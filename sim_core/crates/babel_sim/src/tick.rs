//! Fixed-timestep clock for the simulation.
//!
//! The host (Godot or a test harness) calls [`TickClock::advance`] with the
//! number of ticks to step. The sim never reads wall-clock time. This makes
//! the sim trivially pausable, replayable, and headless-testable.

use serde::{Deserialize, Serialize};

/// Number of game-time minutes that pass per simulation tick.
///
/// At 1 tick / 60 minutes, a year (360 days × 1440 min) advances in
/// 8640 ticks. At 60 ticks/sec real-time, that's ~144 seconds per game year
/// at 1× speed — adjusted by [`TimeScale`].
pub const MINUTES_PER_TICK: u32 = 60;

/// Player-facing time scale. Discrete steps so we never lose determinism
/// to floating-point speed values.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TimeScale {
    /// Paused — no ticks advance.
    Paused,
    /// 1×.
    Normal,
    /// 4×.
    Fast,
    /// 16×.
    VeryFast,
    /// 64× (debug / replay).
    Debug,
}

impl TimeScale {
    /// Multiplier applied to ticks-per-frame.
    #[must_use]
    pub fn multiplier(self) -> u32 {
        match self {
            Self::Paused => 0,
            Self::Normal => 1,
            Self::Fast => 4,
            Self::VeryFast => 16,
            Self::Debug => 64,
        }
    }
}

/// Monotonic tick counter + scale.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TickClock {
    /// Total ticks elapsed since the sim started. Saved in the world file.
    ticks: u64,
    /// Current player-selected scale.
    scale: TimeScale,
}

impl TickClock {
    /// New clock starting at tick 0, [`TimeScale::Normal`].
    #[must_use]
    pub fn new() -> Self {
        Self {
            ticks: 0,
            scale: TimeScale::Normal,
        }
    }

    /// Total ticks elapsed.
    #[must_use]
    pub fn ticks(&self) -> u64 {
        self.ticks
    }

    /// Current scale.
    #[must_use]
    pub fn scale(&self) -> TimeScale {
        self.scale
    }

    /// Set the scale. Does not advance the clock.
    pub fn set_scale(&mut self, scale: TimeScale) {
        self.scale = scale;
    }

    /// Advance by N raw ticks (ignoring scale). Used by tests + replay.
    pub fn advance_raw(&mut self, n: u64) {
        self.ticks = self.ticks.saturating_add(n);
    }

    /// Advance by `frame_ticks * scale.multiplier()`. The host calls this
    /// once per host frame with `frame_ticks = 1`.
    ///
    /// Returns the number of ticks actually applied.
    pub fn advance_frame(&mut self, frame_ticks: u32) -> u32 {
        let n = frame_ticks.saturating_mul(self.scale.multiplier());
        if n == 0 {
            return 0;
        }
        self.ticks = self.ticks.saturating_add(u64::from(n));
        n
    }
}

impl Default for TickClock {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paused_does_not_advance() {
        let mut c = TickClock::new();
        c.set_scale(TimeScale::Paused);
        assert_eq!(c.advance_frame(1), 0);
        assert_eq!(c.ticks(), 0);
    }

    #[test]
    fn normal_advances_one_per_frame() {
        let mut c = TickClock::new();
        for _ in 0..100 {
            c.advance_frame(1);
        }
        assert_eq!(c.ticks(), 100);
    }

    #[test]
    fn fast_advances_four_per_frame() {
        let mut c = TickClock::new();
        c.set_scale(TimeScale::Fast);
        c.advance_frame(1);
        assert_eq!(c.ticks(), 4);
    }

    #[test]
    fn raw_advance_is_unaffected_by_scale() {
        let mut c = TickClock::new();
        c.set_scale(TimeScale::Paused);
        c.advance_raw(50);
        assert_eq!(c.ticks(), 50);
    }
}
