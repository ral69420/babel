//! Deterministic, seedable RNG used everywhere in the sim.
//!
//! Wrapping `xoroshiro256++` from `rand_xoshiro`. We re-export only the
//! operations we actually need so that no system can accidentally use
//! `thread_rng()` or another non-deterministic source.
//!
//! ### Forking
//!
//! Each subsystem (worldgen, lang, chronicle, etc.) gets its own
//! [`DetRng`] *forked* from the master RNG via [`DetRng::fork`]. This means
//! one subsystem advancing its RNG does not affect another — critical for
//! save-replay determinism.

use rand_core::{RngCore, SeedableRng};
use rand_xoshiro::Xoshiro256PlusPlus;
use serde::{Deserialize, Serialize};

/// Deterministic RNG wrapper.
///
/// `Clone` is intentional — cloning gives an *independent* RNG with the same
/// state. Use [`DetRng::fork`] to derive a child stream from the current
/// state.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DetRng {
    inner: Xoshiro256PlusPlus,
}

impl DetRng {
    /// Construct from a 64-bit seed. Two `DetRng`s built from the same seed
    /// produce identical streams.
    #[must_use]
    pub fn from_seed(seed: u64) -> Self {
        Self {
            inner: Xoshiro256PlusPlus::seed_from_u64(seed),
        }
    }

    /// Construct from a fully-specified 256-bit seed. Useful for forking.
    #[must_use]
    pub fn from_seed_256(seed: [u8; 32]) -> Self {
        Self {
            inner: Xoshiro256PlusPlus::from_seed(seed),
        }
    }

    /// Derive an independent child RNG. Advances `self` so the same fork
    /// cannot be derived twice from the same parent state.
    #[must_use]
    pub fn fork(&mut self) -> Self {
        let mut seed = [0u8; 32];
        self.fill_bytes(&mut seed);
        Self::from_seed_256(seed)
    }

    /// Next u32.
    pub fn next_u32(&mut self) -> u32 {
        self.inner.next_u32()
    }

    /// Next u64.
    pub fn next_u64(&mut self) -> u64 {
        self.inner.next_u64()
    }

    /// Fill a byte slice.
    pub fn fill_bytes(&mut self, dest: &mut [u8]) {
        self.inner.fill_bytes(dest);
    }

    /// Uniform integer in `[0, max)`. Returns `0` if `max == 0`.
    pub fn gen_range_u32(&mut self, max: u32) -> u32 {
        if max == 0 {
            return 0;
        }
        // Lemire's bounded fast method — branchless and unbiased.
        let mut x = self.next_u32();
        let mut m = u64::from(x).wrapping_mul(u64::from(max));
        let mut l = m as u32;
        if l < max {
            let t = max.wrapping_neg() % max;
            while l < t {
                x = self.next_u32();
                m = u64::from(x).wrapping_mul(u64::from(max));
                l = m as u32;
            }
        }
        (m >> 32) as u32
    }

    /// Uniform float in `[0, 1)`.
    pub fn gen_unit_f32(&mut self) -> f32 {
        // 24 bits of mantissa entropy.
        (self.next_u32() >> 8) as f32 / (1u32 << 24) as f32
    }

    /// Uniform float in `[0, 1)`, double precision.
    pub fn gen_unit_f64(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 / (1u64 << 53) as f64
    }

    /// `true` with probability `p`. Clamped to `[0, 1]`.
    pub fn chance(&mut self, p: f32) -> bool {
        if p <= 0.0 {
            return false;
        }
        if p >= 1.0 {
            return true;
        }
        self.gen_unit_f32() < p
    }

    /// Pick one element uniformly from a non-empty slice. Returns `None` if
    /// the slice is empty.
    pub fn pick<'a, T>(&mut self, items: &'a [T]) -> Option<&'a T> {
        if items.is_empty() {
            return None;
        }
        let i = self.gen_range_u32(items.len() as u32) as usize;
        Some(&items[i])
    }
}

impl RngCore for DetRng {
    fn next_u32(&mut self) -> u32 {
        self.inner.next_u32()
    }

    fn next_u64(&mut self) -> u64 {
        self.inner.next_u64()
    }

    fn fill_bytes(&mut self, dest: &mut [u8]) {
        self.inner.fill_bytes(dest);
    }

    fn try_fill_bytes(&mut self, dest: &mut [u8]) -> Result<(), rand_core::Error> {
        self.inner.try_fill_bytes(dest)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn same_seed_same_stream() {
        let mut a = DetRng::from_seed(42);
        let mut b = DetRng::from_seed(42);
        for _ in 0..1024 {
            assert_eq!(a.next_u64(), b.next_u64());
        }
    }

    #[test]
    fn different_seed_different_stream() {
        let mut a = DetRng::from_seed(1);
        let mut b = DetRng::from_seed(2);
        let differs = (0..32).any(|_| a.next_u64() != b.next_u64());
        assert!(differs);
    }

    #[test]
    fn fork_is_independent() {
        let mut parent = DetRng::from_seed(7);
        let mut child = parent.fork();
        // Re-derive the same parent up to the fork point.
        let mut parent_clone = DetRng::from_seed(7);
        let _ = parent_clone.fork(); // advance it identically
        for _ in 0..256 {
            assert_eq!(parent.next_u64(), parent_clone.next_u64());
        }
        // Child stream is its own thing — just sanity check it produces values.
        let _ = child.next_u64();
    }

    #[test]
    fn gen_range_is_bounded() {
        let mut r = DetRng::from_seed(0xDEAD_BEEF);
        for _ in 0..10_000 {
            let v = r.gen_range_u32(7);
            assert!(v < 7);
        }
    }

    #[test]
    fn gen_range_zero() {
        let mut r = DetRng::from_seed(0);
        assert_eq!(r.gen_range_u32(0), 0);
    }

    #[test]
    fn unit_floats_in_range() {
        let mut r = DetRng::from_seed(123);
        for _ in 0..10_000 {
            let f = r.gen_unit_f32();
            assert!((0.0..1.0).contains(&f));
        }
    }

    #[test]
    fn pick_empty_returns_none() {
        let mut r = DetRng::from_seed(0);
        let v: &[u32] = &[];
        assert!(r.pick(v).is_none());
    }
}
