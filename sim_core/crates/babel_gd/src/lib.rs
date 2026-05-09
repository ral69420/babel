//! `babel_gd` — Godot bindings for Babel's simulation core.
//!
//! Two compilation modes:
//!
//! - **`--features gdext`** — pulls in the `godot` crate and exposes a
//!   `BabelSim` GDExtension class to Godot 4.3.
//! - **default (no features)** — provides plain Rust APIs that mirror the
//!   GDScript surface exactly. CI runs `cargo test` in this mode so we can
//!   catch logic regressions without Godot installed.
//!
//! The default mode is **not** an in-process Godot stub; it is a clean
//! pass-through wrapping [`World`]. The GDScript-facing surface lives in
//! `bridge.rs` as plain methods so the same code is exercised by both modes.

#![deny(missing_docs)]
// `unsafe` is unavoidable when the `gdext` feature is on (see SAFETY note
// below at `unsafe impl ExtensionLibrary`). We allow it crate-wide only when
// the feature is enabled.
#![cfg_attr(feature = "gdext", allow(unsafe_code))]

mod bridge;

pub use bridge::SimHandle;

#[cfg(feature = "gdext")]
mod gd_class;

#[cfg(feature = "gdext")]
use godot::prelude::*;

#[cfg(feature = "gdext")]
struct BabelExt;

// SAFETY: `ExtensionLibrary` is declared `unsafe trait` by the `godot` crate
// because Godot's plugin loader calls into this entry point during engine
// startup, before any other Rust code runs. The trait has no methods we
// override; the empty impl just registers `BabelExt` as the GDExtension
// entry point. There are no invariants for us to uphold beyond "this struct
// exists for the lifetime of the process", which it does (it's a ZST
// referenced from a `static` produced by the `#[gdextension]` macro).
#[cfg(feature = "gdext")]
#[gdextension]
unsafe impl ExtensionLibrary for BabelExt {}
