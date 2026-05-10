#!/usr/bin/env python3
"""Generate four construction-stage variants of a building sprite.

Stage progression (visible bottom→top):

    Foundation: bottom 25% visible, blue stones only
    Frame:      bottom 50% visible
    Walls:      bottom 80% visible (no roof yet)
    Roof:       full sprite, slightly desaturated (under-construction tint)
    Complete:   full sprite, no tint  (rendered separately)

We also output a 32×32 downscale of each stage for low-zoom rendering and
a 64×64 downscale for high-zoom.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "godot_project" / "assets" / "buildings" / "house" / "source_256.png"
OUT = ROOT / "godot_project" / "assets" / "buildings" / "house"

# (label, visible_fraction_from_bottom)
STAGES = [
    ("foundation", 0.25),
    ("frame", 0.50),
    ("walls", 0.80),
    ("roof", 1.00),
    ("complete", 1.00),
]


def clip_bottom(img: Image.Image, frac: float) -> Image.Image:
    """Return a copy of `img` with only the bottom `frac` fraction visible
    (rest set to transparent)."""
    w, h = img.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    visible_h = int(round(h * frac))
    if visible_h > 0:
        bottom = img.crop((0, h - visible_h, w, h))
        out.paste(bottom, (0, h - visible_h))
    return out


def desaturate(img: Image.Image, factor: float) -> Image.Image:
    return ImageEnhance.Color(img).enhance(factor)


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    for label, frac in STAGES:
        clipped = clip_bottom(src, frac)
        if label == "roof":
            # subtle under-construction tint so roof reads as "fresh"
            clipped = desaturate(clipped, 0.85)
        clipped.save(OUT / f"stage_{label}_256.png")
        clipped.resize((64, 64), Image.LANCZOS).save(OUT / f"stage_{label}_64.png")
        clipped.resize((32, 32), Image.LANCZOS).save(OUT / f"stage_{label}_32.png")
        print(f"  stage {label}: frac={frac:.2f} -> 256/64/32 saved")


if __name__ == "__main__":
    main()
