# Babel

Cozy ambient civilization simulator. Watch civilizations rise, develop language, build cities, fight wars, and write their own history — all without your direct control.

> **Status:** pre-alpha (M0). Architectural skeleton + simulation core under active development.

## Pillars

1. **Observation, not management.** The player is a director, not a manager. Civilizations live their own lives.
2. **Procedural language as magic.** Each people speaks a generated language (Markov chain over phoneme sets — no AI). Magic comes from semantic gaps between languages.
3. **Auto-generated chronicle.** A book is written by an in-world chronicler who has personality, biases, and a finite lifespan. Template-based, deterministic — no LLM.
4. **Ritual ossification.** Traditions accumulate. Old societies drown in their own ceremony. Reformers can break the cycle (and pay the cost).
5. **No fail states.** Civilizations end, but their patterns can be re-summoned in later cycles. Egan's "dust theory" applied to a sim.

## Tech stack

- **Engine:** Godot 4.3 (GDScript for UI/glue)
- **Simulation core:** Rust 1.83 (`sim_core`), exposed to Godot via [gdext](https://github.com/godot-rust/gdext) GDExtension
- **Chronicle:** template engine in Rust (TOML templates) + Python (`chronicle_service`) for PDF export only via WeasyPrint
- **Determinism:** seedable xoroshiro256++ RNG, fixed-tick simulation, replay-safe save format
- **Save format:** custom binary + zstd, versioned with migration support
- **Localisation:** Godot built-in `tr()` + Crowdin (planned)

## Repository layout

```
babel/
├── godot_project/          # Godot 4.3 project (UI, scenes, glue GDScript)
│   ├── project.godot
│   ├── addons/sim_core/    # built gdext library + .gdextension
│   ├── scenes/
│   ├── scripts/
│   ├── ui/
│   └── assets/
├── sim_core/               # Rust simulation core (Cargo workspace)
│   ├── Cargo.toml
│   ├── crates/
│   │   ├── babel_sim/      # core ECS-style sim, deterministic
│   │   ├── babel_lang/     # procedural language generation (Markov)
│   │   ├── babel_chronicle/# template-based event writer (no LLM)
│   │   ├── babel_save/     # binary + zstd save/load with migrations
│   │   └── babel_gd/       # gdext bindings (only crate Godot links)
├── chronicle_service/      # Python: PDF export only (no AI)
├── content/                # hand-authored content (templates, phoneme sets, etc.)
│   ├── chronicle_templates/
│   ├── phoneme_sets/
│   ├── traditions/
│   ├── religions/
│   └── flags/
├── docs/                   # design + technical docs
├── tools/                  # scripts (build, test, package)
├── tests/                  # headless integration tests
└── .github/workflows/      # CI (lint, test, build)
```

## Building

### Prerequisites
- Rust 1.83+ (`rustup`, with `clippy` and `rustfmt`)
- Godot 4.3 (matches the version `babel_gd` is built against)
- Python 3.11+ (only for `chronicle_service` PDF export — optional for core dev)

### Build the simulation core
```bash
cd sim_core
cargo build --release
./tools/install_gdext.sh   # copies .so/.dll/.dylib into godot_project/addons/sim_core
```

### Run the Godot project
```bash
godot4 --path godot_project
```

### Run headless tests
```bash
cd sim_core && cargo test --workspace
godot4 --headless --path godot_project --script res://tests/run_all.gd
```

## Development principles

1. **Sim core is engine-agnostic.** `babel_sim` must compile and run under `cargo test` with no Godot dependency. Only `babel_gd` links Godot.
2. **Determinism is sacred.** All randomness must go through `DetRng`. No `std::time` in sim. No `HashMap` iteration in sim outputs (use `BTreeMap` or sorted vecs).
3. **No allocations in the hot tick path.** Pre-allocate. If you must allocate, justify in PR description.
4. **No LLM, no AI text/image generation in the game.** Period. Hand-written templates with deterministic slot filling.
5. **Profile before optimizing.** `cargo flamegraph` is in `tools/`.
6. **Save migrations are mandatory** for any change to persistent data structures.
7. **Test the sim, not the rendering.** Integration tests run headless and assert on chronicle output and world state.

## License

TBD (likely MIT for code + CC-BY-NC for content).

## Contact

`@ral69420` on GitHub.
