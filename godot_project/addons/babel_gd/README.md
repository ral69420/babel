# babel_gd — Godot GDExtension

The `lib/` directory holds the platform-specific shared library built from
the Rust crate at `sim_core/crates/babel_gd`. The Godot project loads it
at boot and exposes the `BabelSim` resource class.

## Building locally

```bash
# From repo root:
./tools/build_gdext.sh        # writes godot_project/addons/babel_gd/lib/...
```

## Why is `lib/` empty in fresh checkouts?

Built artefacts are not committed (see `.gitignore`). Run the build script
above, or download from the latest CI artifact, before opening the Godot
project. If the library is missing, `GameState` falls back to stub mode and
the simulation will not run.
