# Contributing

## Quick rules

- Follow `rustfmt` and pass `clippy --all-targets --all-features -D warnings`.
- Keep `cargo test --workspace` green at all times on `main`.
- No `unwrap()` / `expect()` in `sim_core` non-test code unless invariants are documented.
- No `std::time`, no `rand::thread_rng`, no `HashMap` iteration in sim output paths.
- Save format changes require a migration in `babel_save::migrations`.
- All new content (templates, phoneme sets) must round-trip through `cargo test` (parsed + validated).
- Branches: `devin/{timestamp}-{slug}` or `feat/{slug}`, `fix/{slug}`, `chore/{slug}`.

## Architecture invariants

These are non-negotiable. Violations are blocking review.

1. **`babel_sim` does not depend on Godot or any GUI.** Only `babel_gd` links `godot`.
2. **Determinism.** Same seed + same inputs = byte-identical sim trace. Enforced by `tests/determinism.rs`.
3. **No allocations in the per-tick hot path.** If you must, document why.
4. **Public sim API is `&mut World` based.** No globals. No `lazy_static`. No `Arc<Mutex<World>>`.

## PR checklist

- [ ] `cargo fmt` clean
- [ ] `cargo clippy -- -D warnings` clean
- [ ] `cargo test --workspace` green
- [ ] Updated `docs/CHANGELOG.md` if user-facing
- [ ] Save format change? Migration added.
- [ ] Performance-sensitive change? Bench before/after numbers in PR.
