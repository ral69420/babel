# Textures TODO — what you need to draw for BABEL

Single source of truth for art assets I'm asking you to make. Grouped by
priority. P0 = unblock current PR, P3 = late-game phases.

## Style guide (applies to all)

- **Pixel art**, no anti-aliasing, no sub-pixel detail.
- **8-bit / 16-bit feel**, limited palette (≤16 colours per sprite, ideally ≤8 from the GDD §13 palette).
- **Bottom-aligned**: the sprite "stands" on the bottom edge so I can
  anchor it to the terrain without it floating.
- **Transparent background** (PNG RGBA). Solid alpha edges — no soft
  fade — so `alpha_cut = DISCARD` keeps them crisp.
- **No drop shadows in the sprite itself**; lighting is added at runtime
  by the day/night cycle shader.
- **Cross-billboard pieces** (trees, grass, ruins) should be
  silhouette-readable from any rotation — they're drawn twice at 90°.
- **Square canvas preferred** (64×64 / 128×128) unless noted.

Drop new assets into `godot_project/assets/...` mirroring the existing
folder structure. Each PNG should sit next to a `.png.import` (Godot
auto-creates this on first open, but if you copy into the repo headless
just duplicate an existing `.png.import` and rename — I can wire the
correct path).

---

## P0 — optional polish for the current world-tweaks PR

These are *nice-to-have* — current code falls back to existing textures
or procedural colours, so you can ship without them. Make them when
you have time.

| File | Size | What | Notes |
|---|---|---|---|
| `assets/decorations/leaf/leaf.png` | 12×12 | Single falling leaf | Used by the global GPUParticles3D. Currently stands-in with `grass.png`. A small green/yellow leaf shape (rotated random angle, additive blend) reads better at zoom-out. |
| `assets/fx/firefly/firefly.png` | 8×8 | Soft glowing dot | Bright yellow-green core, fading alpha. Used additive at night. If you skip it, I render a procedural radial gradient. |
| `assets/sky/moon.png` | 64×64 | Pixel-art moon | Optional — currently I just lower the sun light at night. If you want a visible moon disc, draw a 64×64 with crescent variants. |

---

## P1 — Phase 7 (buildings) + Phase 8 (city themes)

Needed *before* I implement Phase 7. Drop into
`assets/buildings/<type>/<type>.png`.

| File | Size | What | Notes |
|---|---|---|---|
| `assets/buildings/granary/granary.png` | 64×64 | Granary | Wood + thatch silo. Same height as tree (≈64px tall). Base equal to a hex tile. |
| `assets/buildings/workshop/workshop.png` | 64×64 | Workshop | Smithy/anvil hut. Slightly squarer than granary. Same height as house. |
| `assets/buildings/temple/temple.png` | 96×96 | Temple | Taller (~1.5× tree). Stone+wood, simple silhouette, no specific religion. Same canvas width as others, extra height. |
| `assets/buildings/city_center/city_center.png` | 96×96 | City Center | Larger than house, banner / tall pole on top so it reads as the capital from afar. |

**Calvino city-theme icons** — 10 small icons that float above a city
center to show its theme. Each 24×24, transparent background, billboard
(2D). Drop into `assets/ui/themes/`:

| File | Theme | Visual hint |
|---|---|---|
| `assets/ui/themes/memory.png` | Memory | Open book / pillar |
| `assets/ui/themes/desire.png` | Desire | Heart / hand reaching |
| `assets/ui/themes/dead.png` | Dead | Tombstone / urn |
| `assets/ui/themes/sky.png` | Sky | Cloud / star |
| `assets/ui/themes/trading.png` | Trading | Scales / coin pile |
| `assets/ui/themes/thin.png` | Thin | Tower silhouette |
| `assets/ui/themes/continuous.png` | Continuous | Two arrows in a loop |
| `assets/ui/themes/hidden.png` | Hidden | Eye in a triangle / mask |
| `assets/ui/themes/sign.png` | Sign | Rune / symbol |
| `assets/ui/themes/eyes.png` | Eyes | Watchful eye |

---

## P2 — Phase 10 (research) + Phase 12 (ruins)

| File | Size | What | Notes |
|---|---|---|---|
| `assets/decorations/ruin/ruin.png` | 96×96 | Broken stone column | Greyscale, partly translucent, rotational symmetry not required (cross-billboard). |
| `assets/decorations/ruin/ruin_stones.png` | 64×64 | Scattered stone blocks | Lower variant for tiles where the column is too dramatic. |
| `assets/ui/research/<node>.png` × 30 | 24×24 each | Knowledge-node icons | I'll send the final list of 30 nodes when Phase 10 starts. Examples: *agriculture, metallurgy, writing, sailing, masonry, brewing, husbandry, weaving, pottery, herbalism*. Same icon style as the city-theme icons. |
| `assets/ui/chronicle_book.png` | 48×48 | Chronicle button | Pixel book icon for the bottom-right HUD button. |

---

## P3 — Phase 13 (underground), 14 (flags), 15 (aliens)

| File | Size | What | Notes |
|---|---|---|---|
| `assets/npcs/underground/walk_south.png` | 288×48 (6 frames × 48px) | Underground/dissident NPC variant | Same skeleton as the default NPC, darker palette, hood. |
| `assets/ui/flag_symbols/*.svg` × 60 | vector | Flag glyphs | SVG so I can recolour by palette. Suggested set: sun, moon, mountain, ship, hand, eye, tree, wave, fish, axe, sword, hammer, anvil, key, gear, book, scroll, crown, flame, river, wolf, bird, fox, snake, fish, leaf, antlers, skull, cross, circle, square, triangle, diamond, hexagon, hourglass, scales, anchor, chain, wheel, lantern, candle, bell, tower, bridge, archway, shield, helmet, footprint, feather, claw, tooth, raindrop, snowflake, lightning, rune-1..6. |
| `assets/npcs/alien/idle.png` | 96×96 | Alien sprite | Non-humanoid silhouette, 4-frame idle bobbing animation arranged horizontally (so 384×96). Cool teal / purple palette. |
| `assets/decorations/alien_pod/alien_pod.png` | 64×64 | Crash-landed pod | Single static sprite, marks the alien-arrival site. |

---

## How I'm prioritising this for you

1. **Now (this week):** P0 if you want to polish, otherwise zero. The
   current PR ships fine without you drawing anything.
2. **When I tell you Phase 7 is starting:** the four building sprites
   (granary, workshop, temple, city center) and the 10 Calvino theme
   icons. Without these, Phase 7 ships with the house sprite re-tinted
   per building type, which works but looks lazy.
3. **When I tell you Phase 10 is starting:** the chronicle book icon
   and the 30 research-node icons.
4. Everything in P3 has months of runway — don't worry about it yet.

If you'd rather I generate procedural placeholders (e.g. tinted
rectangles, geometric icons) until you have time to draw them, just
say "placeholders" in chat and I'll wire those in so playtesting isn't
blocked on art.
