//! In-game calendar.
//!
//! Babel uses a simplified 360-day calendar: 4 seasons of 90 days, 24h days,
//! [`crate::tick::MINUTES_PER_TICK`] minutes per tick.

use serde::{Deserialize, Serialize};

use crate::tick::MINUTES_PER_TICK;

/// Days per game year.
pub const DAYS_PER_YEAR: u32 = 360;
/// Days per season.
pub const DAYS_PER_SEASON: u32 = 90;
/// Hours per day.
pub const HOURS_PER_DAY: u32 = 24;
/// Minutes per hour.
pub const MINUTES_PER_HOUR: u32 = 60;
/// Total ticks in one game year.
pub const TICKS_PER_YEAR: u32 = DAYS_PER_YEAR * HOURS_PER_DAY * MINUTES_PER_HOUR / MINUTES_PER_TICK;

/// Four classic seasons.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Season {
    /// Spring.
    Spring,
    /// Summer.
    Summer,
    /// Autumn.
    Autumn,
    /// Winter.
    Winter,
}

impl Season {
    /// Determine season from day-of-year `[0, 360)`.
    #[must_use]
    pub fn from_day_of_year(day: u32) -> Self {
        match day / DAYS_PER_SEASON {
            0 => Self::Spring,
            1 => Self::Summer,
            2 => Self::Autumn,
            _ => Self::Winter,
        }
    }
}

/// Decoded calendar state at a given tick. Cheap to compute on demand.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Calendar {
    /// Year since founding (0-based).
    pub year: u32,
    /// Day of year `[0, 360)`.
    pub day_of_year: u32,
    /// Hour of day `[0, 24)`.
    pub hour: u32,
}

impl Calendar {
    /// Decode a calendar from total ticks.
    #[must_use]
    pub fn from_ticks(ticks: u64) -> Self {
        let total_minutes = ticks.saturating_mul(u64::from(MINUTES_PER_TICK));
        let total_hours = total_minutes / u64::from(MINUTES_PER_HOUR);
        let total_days = total_hours / u64::from(HOURS_PER_DAY);
        let hour = (total_hours % u64::from(HOURS_PER_DAY)) as u32;
        let day_of_year = (total_days % u64::from(DAYS_PER_YEAR)) as u32;
        let year = (total_days / u64::from(DAYS_PER_YEAR)) as u32;
        Self {
            year,
            day_of_year,
            hour,
        }
    }

    /// Current season.
    #[must_use]
    pub fn season(self) -> Season {
        Season::from_day_of_year(self.day_of_year)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zero_ticks_is_year_zero() {
        let c = Calendar::from_ticks(0);
        assert_eq!(c.year, 0);
        assert_eq!(c.day_of_year, 0);
        assert_eq!(c.hour, 0);
        assert_eq!(c.season(), Season::Spring);
    }

    #[test]
    fn one_year_passes() {
        let c = Calendar::from_ticks(u64::from(TICKS_PER_YEAR));
        assert_eq!(c.year, 1);
        assert_eq!(c.day_of_year, 0);
    }

    #[test]
    fn seasons_align() {
        assert_eq!(Season::from_day_of_year(0), Season::Spring);
        assert_eq!(Season::from_day_of_year(89), Season::Spring);
        assert_eq!(Season::from_day_of_year(90), Season::Summer);
        assert_eq!(Season::from_day_of_year(180), Season::Autumn);
        assert_eq!(Season::from_day_of_year(270), Season::Winter);
        assert_eq!(Season::from_day_of_year(359), Season::Winter);
    }
}
