#!/usr/bin/env bash
# Build the babel_gd GDExtension and copy the resulting library into the
# Godot project's addon folder.
#
# Usage:
#   ./tools/build_gdext.sh           # debug build
#   ./tools/build_gdext.sh release   # release build

set -euo pipefail

PROFILE="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM_DIR="$ROOT/sim_core"
DEST_DIR="$ROOT/godot_project/addons/babel_gd/lib"

mkdir -p "$DEST_DIR"

case "$PROFILE" in
  debug)
    (cd "$SIM_DIR" && cargo build -p babel_gd --features gdext)
    SRC="$SIM_DIR/target/debug/libbabel_gd.so"
    ;;
  release)
    (cd "$SIM_DIR" && cargo build -p babel_gd --features gdext --release)
    SRC="$SIM_DIR/target/release/libbabel_gd.so"
    ;;
  *)
    echo "Usage: $0 [debug|release]" >&2
    exit 2
    ;;
esac

if [[ ! -f "$SRC" ]]; then
  echo "Build artefact not found: $SRC" >&2
  exit 1
fi

cp "$SRC" "$DEST_DIR/"
echo "Copied $SRC -> $DEST_DIR/"
