#!/usr/bin/env python3
"""Procedural biome-tile generator for the Babel demo.

Generates 32x32 RGBA seamless tiles using wrap-around Perlin noise + the
locked Babel palette (`godot_project/assets/palette/babel_v1.gpl`). Edges
are mathematically seamless because the noise sampler uses a periodic
domain (octave_period = tile_size).

Each biome is a small declarative recipe in `BIOME_RECIPES`:
    base   = list of palette indices (sorted dark -> light)
    detail = optional list of (palette_idx, density) pairs for
             scattered detail pixels (small grass tufts, rocks, etc.)
    noise_scale, octaves, persistence: standard Perlin parameters

Usage:
    python3 tools/gen_biome_tile.py hills
    python3 tools/gen_biome_tile.py --all
    python3 tools/gen_biome_tile.py hills --seed 42 --out /tmp/hills.png

Determinism: same seed + same recipe = byte-identical PNG.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import List, Tuple

import numpy as np
from PIL import Image

try:
    from noise import pnoise2
except ImportError as exc:  # pragma: no cover
    print("noise lib missing; pip install noise", file=sys.stderr)
    raise SystemExit(1) from exc


REPO_ROOT = Path(__file__).resolve().parent.parent
PALETTE_PATH = REPO_ROOT / "godot_project" / "assets" / "palette" / "babel_v1.gpl"


def load_palette() -> List[Tuple[int, int, int]]:
    """Parse babel_v1.gpl, return list of RGB tuples in declaration order."""
    cols: List[Tuple[int, int, int]] = []
    for line in PALETTE_PATH.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith(("#", "GIMP", "Name:", "Columns:")):
            continue
        parts = line.split(maxsplit=3)
        if len(parts) < 3:
            continue
        try:
            r, g, b = int(parts[0]), int(parts[1]), int(parts[2])
        except ValueError:
            continue
        cols.append((r, g, b))
    return cols


# Indices into babel_v1.gpl (0-based, in declaration order):
#   0..7   = A1..A8 earth (dark -> pale)
#   8..12  = B1..B5 vegetation
#   13..16 = C1..C4 water
#   17..20 = D1..D4 cool stone
#   21..24 = E1..E4 warm accents
#   25..28 = F1..F4 ritual/magic
#   29..31 = G1..G3 bone/ash/fade

# Each recipe defines the palette ramp (light density grouped low->high) and
# optional scattered detail dots. Recipes intentionally avoid using "forest"
# or "tree" structure -- those go in decoration overlays.
BIOME_RECIPES = {
    "hills": dict(
        base_indices=[1, 2, 3, 4, 5, 11],  # A2..A6 earth + B4 leaf accent
        # detail: (palette_idx, count_per_tile)
        detail=[(11, 6), (12, 3), (3, 4)],  # leaf tufts + grass highlight + dark rock
        noise_scale=4,
        octaves=2,
        persistence=0.55,
        ramp_levels=6,
    ),
    "mountain": dict(
        base_indices=[0, 1, 17, 18, 19, 31],  # earth + cool stone + fade grey
        detail=[(0, 6), (19, 3), (29, 2)],  # crack pixels + sky-pale highlight + bone
        noise_scale=4,
        octaves=2,
        persistence=0.55,
        ramp_levels=6,
    ),
    "desert": dict(
        base_indices=[5, 6, 7, 4],  # A6 sand, A7 pale sand, A8 cream, A5 tan
        detail=[(2, 3), (23, 1)],  # rare umber pebble + ritual gold (sand sparkle)
        noise_scale=4,
        octaves=2,
        persistence=0.45,
        ramp_levels=4,
    ),
    "tundra": dict(
        base_indices=[31, 30, 29, 19, 20],  # G3 fade, G2 ash, G1 bone, D3 cool stone light, D4 sky pale
        detail=[(20, 5), (29, 4), (1, 3)],  # snow patches + bone + earth peek-through
        noise_scale=4,
        octaves=2,
        persistence=0.5,
        ramp_levels=5,
    ),
    # Extra recipes (re-rolls of existing PixelLab tiles, kept for parity).
    "plains_proc": dict(
        base_indices=[8, 9, 10, 11, 12],  # B1..B5 vegetation ramp
        detail=[(12, 4), (23, 1), (10, 3)],  # grass highlight + ritual gold (one wildflower)
        noise_scale=4,
        octaves=2,
        persistence=0.5,
        ramp_levels=5,
    ),
    "ocean_proc": dict(
        base_indices=[13, 14, 15, 16],  # C1..C4 water
        detail=[(16, 3), (15, 2)],  # water highlight scatter
        noise_scale=4,
        octaves=2,
        persistence=0.6,
        ramp_levels=4,
    ),
}


def seamless_perlin(
    width: int,
    height: int,
    *,
    scale: float,
    octaves: int,
    persistence: float,
    seed: int,
) -> np.ndarray:
    """Return float32 array (height, width) of values in [0, 1].

    Uses pnoise2 with `repeatx=period`, `repeaty=period`. The library
    snaps the sampling lattice to integer multiples of the period, so
    sampling x in [0, period) and y in [0, period) gives a tile whose
    left edge equals its right edge and whose top equals its bottom --
    *byte-identical* on the boundary, not "approximately seamless".

    `scale` is the number of noise periods per tile (so scale=2.5 means
    2-3 noise features per 32px tile). `seed` selects a different
    region of the noise field via the `base` parameter.
    """
    arr = np.empty((height, width), dtype=np.float32)
    period = max(1, int(round(scale)))
    base_offset = (seed % 256)  # 'base' supports up to 256 distinct fields
    sx = period / width
    sy = period / height
    for y in range(height):
        for x in range(width):
            arr[y, x] = pnoise2(
                x * sx,
                y * sy,
                octaves=octaves,
                persistence=persistence,
                repeatx=period,
                repeaty=period,
                base=base_offset,
            )
    lo, hi = arr.min(), arr.max()
    if hi > lo:
        arr = (arr - lo) / (hi - lo)
    return arr


class DetRng:
    """Tiny deterministic LCG so detail dots are stable across runs."""

    def __init__(self, seed: int):
        self.state = (seed * 6364136223846793005 + 1442695040888963407) & 0xFFFF_FFFF_FFFF_FFFF

    def next_u32(self) -> int:
        self.state = (self.state * 6364136223846793005 + 1442695040888963407) & 0xFFFF_FFFF_FFFF_FFFF
        return (self.state >> 32) & 0xFFFF_FFFF

    def randrange(self, n: int) -> int:
        return self.next_u32() % n


def render_tile(biome: str, palette: List[Tuple[int, int, int]], *, seed: int, size: int = 32) -> Image.Image:
    if biome not in BIOME_RECIPES:
        raise ValueError(f"unknown biome '{biome}'; known={list(BIOME_RECIPES)}")
    recipe = BIOME_RECIPES[biome]
    base_indices = recipe["base_indices"]
    n_levels = recipe["ramp_levels"]
    if n_levels > len(base_indices):
        n_levels = len(base_indices)

    field = seamless_perlin(
        size,
        size,
        scale=recipe["noise_scale"],
        octaves=recipe["octaves"],
        persistence=recipe["persistence"],
        seed=seed,
    )

    # Quantize noise field into n_levels bins, map each to base_indices[i].
    bins = np.clip((field * n_levels).astype(np.int32), 0, n_levels - 1)
    img = np.zeros((size, size, 4), dtype=np.uint8)
    img[..., 3] = 255
    for level in range(n_levels):
        rgb = palette[base_indices[level]]
        mask = bins == level
        img[mask, 0] = rgb[0]
        img[mask, 1] = rgb[1]
        img[mask, 2] = rgb[2]

    # Scatter detail dots deterministically.
    rng = DetRng(seed * 9176 + 31337)
    for pal_idx, count in recipe.get("detail", []):
        rgb = palette[pal_idx]
        for _ in range(count):
            x = rng.randrange(size)
            y = rng.randrange(size)
            img[y, x, 0] = rgb[0]
            img[y, x, 1] = rgb[1]
            img[y, x, 2] = rgb[2]

    return Image.fromarray(img, mode="RGBA")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("biome", nargs="?", help="biome name; omit with --all")
    p.add_argument("--all", action="store_true", help="generate all known biomes")
    p.add_argument("--seed", type=int, default=0xBABE_1, help="rng seed")
    p.add_argument("--size", type=int, default=32)
    p.add_argument("--out", type=Path, help="output path (single biome only)")
    p.add_argument(
        "--out-dir",
        type=Path,
        default=REPO_ROOT / "godot_project" / "assets" / "tiles",
        help="root output dir; tiles saved to <out-dir>/<biome>/<biome>.png",
    )
    args = p.parse_args()

    palette = load_palette()
    if len(palette) < 32:
        print(f"palette too short ({len(palette)})", file=sys.stderr)
        return 1

    if args.all:
        names = list(BIOME_RECIPES)
    elif args.biome:
        names = [args.biome]
    else:
        p.error("specify a biome name or --all")
        return 2

    for name in names:
        img = render_tile(name, palette, seed=args.seed + hash(name) & 0xFFFF, size=args.size)
        if args.out and len(names) == 1:
            target = args.out
            target.parent.mkdir(parents=True, exist_ok=True)
        else:
            biome_dir = (args.out_dir / name).resolve()
            biome_dir.mkdir(parents=True, exist_ok=True)
            target = biome_dir / f"{name}.png"
        img.save(target)
        print(f"wrote {target} ({img.size}, {len(set(img.getdata()))} unique pixels)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
