# Babel — Art Generation Brief v1

Brief for any artist or AI image generator producing visual assets for Babel.
Read the **Art Bible** first, then use the **Master Prompt Prefix** at the
start of every generation. Per-asset sections (tiles, NPCs, buildings, …)
give the slot-fill text and the negative prompt.

---

## 0. Read this first — non-negotiables

- **Top-down view, slight 3/4 lean (~75°).** Not pure isometric. Not flat
  top-down. Think *Songs of Syx*, *Stardew Valley* world view, *Caves of Qud*
  if it had pretty art.
- **Tile size: 32 × 32 px.** Everything snaps to this grid. NPCs are 24 × 32
  (taller than wide, fits inside one tile vertically with a 4 px footprint
  shadow). Buildings are 1×1, 2×2, or 3×3 tiles.
- **Colour palette: max 32 colours total across the project.** Pinned palette
  below. Every asset must use *only* these hex values. This is what makes the
  game look like one game and not a Frankenstein of stock packs.
- **No outlines.** Pixels carry shape; black outlines look toy-like and clash
  with the cozy mood. Use 1-px self-shadow on the inside of silhouettes
  instead.
- **Read at thumbnail size.** A tile must be identifiable as forest / desert /
  ruin from 4 metres away on a TV. Squint test: if you can't tell biome at a
  glance, redo.
- **No text in any asset.** The chronicle book is rendered with a real font;
  banners are procedural. Anything with letters in the sprite will be
  rejected on intake.
- **Authored, not procedural.** No noise overlays from Substance, no AI-style
  smudge. Pixel-perfect, by-hand or hand-corrected AI.

---

## 1. Art Bible

### 1.1 Tone

Cozy ambient civilization sim. The player observes — they don't manage. The
art has to reward looking at it for a long time, so:

- **Warm, slightly desaturated.** Hue rotated 5° toward gold on warms, 5°
  toward teal on cools. No primary red, no primary blue.
- **Soft contrast.** Mid-tones do most of the work. Highlights only on water,
  metal, and ritual fire. Shadows are tinted (cool indigo on warm tiles,
  warm umber on cool tiles), never black.
- **Hand-painted-pixel, not retro-pixel.** The reference is *Eastward* and
  *Sea of Stars*, not *Stardew*. Pixels are still discrete, but anti-alias
  with 1-px hue ramps inside the silhouette.

### 1.2 Mood references (literal — google these)

- *Songs of Syx* — top-down density, dirt textures
- *Sea of Stars* — palette discipline, water highlights
- *Townscaper* — quiet pastels, no UI clutter
- *Ymir* — hand-authored top-down civ tiles
- *The Banner Saga* — mood of decline
- *Caves of Qud* (modern art mod) — ruins-as-current-life vibe
- *Tunic* — small, readable silhouettes

Anti-references (do **not** look like): WorldBox (too cartoony), RimWorld
(too sterile/medical), Civ VI (too 3D / hex-explicit), Don't Starve (too
high-contrast / too gothic), generic "voxel-art" itch.io packs.

### 1.3 Palette (32 colours, locked)

Group A — earth (8):
`#1a0f0a #2c1d10 #4a3522 #6b4c2f #8a6845 #a98a64 #c9b18a #e6d3b3`

Group B — vegetation (5):
`#0e2117 #1b3b27 #2f6b3f #4f9657 #87b86a`

Group C — water (4):
`#0a1a2c #14304a #2a5b86 #5fa3c9`

Group D — sky / cool stone (4):
`#3b3f55 #5b6080 #8a90a8 #c3c8d9`

Group E — warm accent (4):
`#3f1518 #7a2a23 #c45a36 #f0a45a`

Group F — ritual / magic (4):
`#2b1a3b #5b2e7a #b463cf #f3c8ff`

Group G — bone / ash / fade (3):
`#e8e3d3 #b8b1a0 #6b6757`

Save as `content/palette/babel_v1.gpl` (GIMP/Aseprite palette). Every
generation tool must be locked to this palette. AI generations get
post-processed through Aseprite "convert to indexed → babel_v1.gpl".

### 1.4 Lighting

- Sun is up-and-to-the-left (NW). Shadows fall down-and-to-the-right (SE),
  4 px long for NPCs, 8 px for trees, 0–2 px for tiles.
- Time of day is *fixed*. We don't do day/night cycles in v1.
- Ritual fire and "Zone" anomalies are the only emissive sources. They
  cast a 1-tile soft glow, palette group F.

### 1.5 Perspective rules

- Tiles: orthographic top-down, but everything *on* a tile (trees, rocks,
  buildings) leans 75° so you see the front face. This means trees are
  drawn as if from a security camera 3 m up — top of foliage at the back,
  trunk visible at the front.
- NPCs always face camera (no back / side sprites in v1; rotation handled
  via flip-x for left-facing).
- Buildings: front-3/4, with the long axis aligned NE–SW so two of the four
  walls are visible.

---

## 2. Master Prompt Prefix (paste before every per-asset prompt)

Use this verbatim at the start of every Stable Diffusion / Flux / Midjourney
prompt. Only the per-asset slot changes.

> Top-down 3/4 pixel art for a cozy ambient civilization sim, 32×32 grid,
> hand-painted pixel style (Sea of Stars + Songs of Syx + Eastward), warm
> desaturated palette of 32 locked colours (earth ochres, mossy greens,
> teal water, dusty violet ritual accent), no black outlines, soft tinted
> 1-px inner shadow, sun coming from the upper-left, shadows fall to the
> lower-right, no text, no UI, no border, transparent background, single
> asset centred, sprite ready for a Godot 4.3 TileMap / AnimatedSprite2D.

Negative prompt (always):

> 3D render, isometric tile (rhombic), photorealistic, oil painting, watercolour,
> blurry, jpeg artefacts, signature, watermark, text, letters, numbers, UI,
> health bar, cursor, frame, border, gradient background, gradient sky,
> bright saturated red, bright saturated blue, neon, anime, chibi big-eyes,
> realistic anatomy, motion blur, lens flare, drop shadow under sprite

Sampler / settings (SDXL or Flux, by default):

- Steps: 30–35 (DPM++ 2M Karras for SDXL; default for Flux)
- CFG: 5.5 (SDXL) / 3.0 (Flux)
- Seed: vary; once a culture's "look" is locked, fix the seed and only
  change the slot text
- Resolution: generate at 512×512, downscale via Aseprite "Nearest" to
  32×32 (or 64×64 for buildings, 96×128 for NPC sheets) — never let the
  AI output the final pixel art directly, the resolution is too low to
  produce clean pixels.

Aseprite post-process for every AI output:

1. Image → Color Mode → Indexed → palette `babel_v1.gpl`, dither = none,
   matching = best
2. Sprite → Sprite Size → 32 px (or asset-specific) using Resampling = "Nearest"
3. Hand-touch any pixel that the indexed conversion butchered (silhouette
   edges, eyes, ritual fire)
4. Save as PNG, no alpha pre-multiplication

---

## 3. Terrain — 8 biome tiles + transitions + decorations

We already enumerate these in code at
`sim_core/crates/babel_sim/src/world.rs::Biome`. Eight values, exact match.

Each biome is a **3×3 atlas** (9 variants of the same tile, jittered) so the
TileMap doesn't tile-repeat visibly. Each biome also gets 4 **decoration
sprites** (tree, rock, etc.) drawn on a separate layer.

### 3.1 Biome tile prompts (slot text)

| Biome   | Slot text |
|---------|-----------|
| Ocean    | "deep ocean tile, dark teal water with two lighter highlight pixels suggesting subsurface light, faint horizontal current lines, no foam" |
| Coast    | "coastal shallows tile, sandbar visible through teal water, single line of breaking foam at the lower edge, wet golden sand at the bottom-left corner" |
| Plains   | "open grassland tile, mossy green base with three subtle tufts of taller grass and one wildflower, faint cart-track running NE to SW" |
| Forest   | "temperate forest floor tile, dark moss with fallen leaves, hint of root crossing the tile, dappled sun pixel highlight in the middle, moss has 1-px lichen patches" |
| Hills    | "rolling hill tile, lighter ochre on the sun-facing side, darker on the shadow side, 1-px crest line running diagonally, sparse short grass" |
| Mountain | "stone mountain tile, layered grey-violet rock striations, snow patch top-left, scree gravel bottom-right, no trees" |
| Desert   | "desert tile, warm ochre sand with wind ripple lines running NE to SW, one bleached bone fragment, one dry tuft, no cactus" |
| Tundra   | "tundra tile, frost-white with cool indigo shadows, three pebbles poking through thin snow, lichen circle, dry grass blade" |

For every biome, generate **9 variants** by adding `, variant {1..9}, slight
random shift of decoration position` and rerolling the seed.

### 3.2 Transition tiles (autotile)

Godot 4.3 TileSet supports terrain matching. We need 13-tile Wang sets per
biome boundary. The *most-used* boundaries are:

- Ocean ↔ Coast
- Coast ↔ Plains
- Plains ↔ Forest
- Plains ↔ Hills
- Hills ↔ Mountain
- Plains ↔ Desert
- Plains ↔ Tundra
- Forest ↔ Hills

For each boundary, run the same prompt as the *destination* biome but with
`, half {origin biome} blended into the {compass} side, soft pixel-dither
border 2 px wide` appended.

### 3.3 Decorations (per biome — 4 sprites each, 16×16 or 24×32)

| Biome | Decorations |
|-------|-------------|
| Plains  | wildflower clump, lone rock, small berry bush, abandoned cart wheel |
| Forest  | conifer 24×32, deciduous 24×32, fern 16×16, mushroom ring 16×16 |
| Hills   | standing stone 16×24, scrub bush 16×16, eagle nest 16×16, small cairn 16×16 |
| Mountain| dwarf pine 16×24, snow-capped boulder 16×16, ice patch 16×16, mountain goat skull 16×16 |
| Desert  | bleached tree 16×24, lone obelisk 16×24, sand drift 16×16, jackal-ear cactus (made-up) 16×16 |
| Tundra  | frozen sapling 16×24, ice spike 16×24, lichen patch 16×16, antler shed 16×16 |
| Coast   | reed cluster 16×16, fishing buoy 16×16, washed-up driftwood 16×16, gull 16×16 |

### 3.4 Tile-tag overlays (RUIN, RIVER, ROAD, ZONE, FADED, SACRED)

These are **overlay sprites** drawn on top of the biome tile, not biome
variants. 32×32, mostly transparent.

- **RUIN** — single broken column or sunken arch fragment. Palette group A
  + group G ash. Reads as "someone built here once". 4 variants.
- **RIVER** — water-flow line crossing the tile. Wang-set with 4
  configurations (NS, EW, NE-bend, NW-bend, T-junctions × 4, cross). Total
  13 tiles for autotile.
- **ROAD** — packed dirt path overlay. Same 13-tile Wang set as river.
- **ZONE** (Strugatsky anomaly) — palette group F glow ring with one of:
  floating geometric shard, time-frozen object, gravity-warped grass.
  3 variants. **Animated** (4 frames, 0.4s loop, gentle pulse).
- **FADED** (Memory Police) — desaturated overlay, 60 % grey wash, the
  decoration on the tile is half-erased into bone-ash colour. 1 sprite that
  composites on any biome.
- **SACRED** — soft palette-F glow + small ritual cairn. 2 variants.

---

## 4. NPCs — 7 cultures × 4 archetypes × 4-frame walk + idle

Cultures (mirror `content/phoneme_sets/*.toml`):

| Code     | Vibe                          | Skin tones        | Hair         | Garment palette         |
|----------|-------------------------------|-------------------|--------------|-------------------------|
| kheltari | sand-stone, sibilant, arid    | warm tan → bronze | dark brown   | ochre + ash linen       |
| orunmare | river-island, vowel-heavy     | warm olive        | black braids | teal + bone             |
| dvarni   | stone-mountain, hard          | pale → ruddy      | red-brown    | indigo + iron           |
| eluran   | forest-twilight, lateral-rich | cool olive        | green-black  | moss + violet           |
| qarasil  | desert-trader, guttural       | deep bronze       | black        | warm umber + brass      |
| ningaer  | snow-tundra, palatalised      | pale, freckled    | flax blond   | bone + sky              |
| sankhara | river-temple, retroflex       | warm brown        | jet black    | saffron + crimson       |

Archetypes (per culture):

1. **Commoner** — neutral pose, working clothes
2. **Elder** — slightly stooped, cane optional, more textured robe
3. **Warrior** — light armour appropriate to biome (kheltari = scale, dvarni
   = mail, ningaer = furs, etc.)
4. **Priest** — robes with one small ritual icon, distinct headdress

That's **7 × 4 = 28 NPC sprite-sheets**.

### 4.1 Sheet layout (every NPC)

Single 96 × 128 PNG, 3 cols × 4 rows of 32×32 cells:

```
[idle_0] [walk_0] [walk_2]
[walk_1] [work_0] [work_2]
[work_1] [bow_0]  [bow_2]   <- bow = ritual / talk gesture
[bow_1]  [die_0]  [die_1]
```

Walk cycle is 4 frames (idle, step-A, mid, step-B), played at 5 fps. Work
is 3-frame loop (chop / sow / hammer depending on context, kept abstract).
Bow is 2-frame ease (down + held). Die is 2-frame fall.

### 4.2 Slot text per (culture, archetype)

Use this template — fill in the bold parts from the table above:

> 32×32 pixel-art top-down 3/4 NPC, **{culture} {archetype}**, **{skin
> tone}** skin, **{hair}** hair, wearing **{garment palette}**, single
> figure facing camera, idle pose, no weapon raised, no large props, fits
> inside a 24×32 silhouette with a 4-px shadow at the feet, palette locked
> to babel_v1, no outline.

Then duplicate the prompt 9 times changing only `idle pose` to: `walk step
left foot forward`, `walk mid stride`, `walk step right foot forward`,
`working: chopping/sowing/hammering down-stroke`, `working: mid-stroke`,
`working: up-stroke`, `bowing down`, `bowing held`, `falling sideways
clutching chest`. Hand-correct in Aseprite for frame coherence.

### 4.3 Cultural sigil (1 per culture, 16×16)

A single 16×16 emblem to mark capital flags / tradition icons / ritual
banners. Made up of palette-locked geometric forms — *not* a logo with
text.

> 16×16 pixel-art emblem for the **{culture}** culture, abstract symbol
> referencing **{vibe noun: dune / river / mountain / forest / oasis /
> tundra / temple}**, palette babel_v1 group **{warm/cold/etc}**, on
> transparent background, no text, no border, fits inside a 14×14 visual
> field with 1-px breathing room.

---

## 5. Buildings — per culture, 3 city tiers

Cities have 3 tiers (Hamlet → Town → City) and a few special buildings. Per
culture × tier × type:

### Per culture, generate:

| Type        | Tile footprint | Tier 1 (Hamlet)            | Tier 2 (Town)              | Tier 3 (City)               |
|-------------|---------------:|----------------------------|----------------------------|-----------------------------|
| Dwelling    | 1×1            | hut                        | longhouse / 2-storey       | terraced row                |
| Granary     | 1×1            | thatched silo              | timber granary             | stone granary with awning   |
| Market      | 2×2            | tarp stalls                | open market square         | covered bazaar              |
| Temple      | 2×2            | shrine cairn               | wooden shrine              | stone temple with bell      |
| Palace      | 3×3            | (none)                     | chieftain's hall           | royal/council palace        |
| Wall        | 1×1 (autotile) | wooden palisade            | stone wall                 | reinforced stone wall       |
| Workshop    | 1×1            | hide tent                  | timber workshop            | stone workshop              |

Per culture, that's 7 buildings × 3 tiers - 1 (no T1 palace) = **20
buildings** × 7 cultures = **140 building sprites**. (Yes, this is real
content — start with kheltari + orunmare + dvarni for v1, defer the other
4 to DLC if budget bites.)

### 5.1 Building prompt template

> 64×64 (or 96×96 / 128×128 for 2×2 / 3×3) pixel-art top-down 3/4 building,
> **{culture}** **{tier}** **{type}**, NE–SW long axis, two visible walls,
> palette babel_v1, **{garment palette of culture, scaled up to architecture
> materials}** for cloth/awnings, dominant material is **{cultural
> material: clay/timber/stone/lattice}**, smoke from chimney if relevant,
> single grounding shadow at the base, no surrounding terrain.

For walls, generate the standard 13-tile Wang autotile set (straight, T,
L, cross, end-cap × 4 directions).

### 5.2 Special procedural overlays on buildings

These are *not* AI-generated, they're composited at runtime:

- **Faction banner** — 16×8 cloth that hangs from palaces / temples,
  coloured by procedural civilization palette + sigil. Generate a single
  blank-cloth template per culture (with appropriate cloth-fold style) and
  the engine tints it per civ at runtime. Similar to how Banner Saga handles
  banners.

---

## 6. Animations — full asset list

| Animation              | Frames | Used by                    | Source           |
|------------------------|-------:|----------------------------|------------------|
| NPC walk               | 4      | every NPC                  | NPC sheet rows   |
| NPC idle               | 1+breathing 2nd | every NPC         | NPC sheet        |
| NPC work               | 3      | every NPC                  | NPC sheet        |
| NPC bow / talk         | 2      | every NPC                  | NPC sheet        |
| NPC die                | 2      | every NPC                  | NPC sheet        |
| Smoke (chimney)        | 4      | dwellings / workshops      | separate sheet   |
| Ritual fire            | 4      | temples, sacred tiles      | separate sheet   |
| Water shimmer          | 3      | ocean/coast/river overlay  | separate sheet   |
| Banner wave            | 4      | palace / temple banners    | separate sheet   |
| Zone anomaly pulse     | 4      | ZONE-tagged tiles          | separate sheet   |
| Fade dust              | 3      | FADED-tagged tiles         | separate sheet   |
| Combat clash flash     | 2      | tile combat marker         | separate sheet   |

Each separate-sheet animation is a strip of frames left-to-right, no
padding, frame size declared in filename suffix
(`fire_32x32_4f.png`).

---

## 7. UI — chronicle book + HUD + icons

### 7.1 Chronicle book

The book is the player's main artefact. It must look like a leather-bound
manuscript that can be opened anywhere on the screen. Spec:

- **Closed cover**: 256×320 px, brown leather + brass corners + cultural
  sigil of the dominant civilization embossed on front.
- **Open spread**: 768×480 px, two cream pages with subtle paper grain (5
  % opacity, palette G), faint inner shadow at the spine.
- **Page corner curl**: 16×16 px, animated 3-frame turn.
- **Bookmark ribbons**: 8×80 px, 3 colour variants (red, gold, green).

Prompt:

> 768×480 pixel-art open book spread, hand-painted pixel style, two cream
> manuscript pages with subtle paper grain, leather binding visible at the
> spine, no text, palette babel_v1 earth + bone groups, soft warm
> lighting, no border, single open book centred on transparent background.

### 7.2 HUD

Minimal HUD per the cozy / Gen Z brief:

- Year + tick label (lower-left), no chrome — text rendered with
  `Inter Variable` (already free), tinted bone-ash.
- Speed indicator (4 dots, fills based on TimeScale 0/1/4/16). 24×8 px.
- Pause / play / fast / very-fast buttons. 24×24 px each. 4 sprites total.
- Toggle Chronicle (book icon). 24×24 px.
- Toggle Map overlay (compass-rose icon). 24×24 px.
- Toggle Zoom level (magnifier +/-). 24×24 px.

Prompt template for icons:

> 24×24 pixel-art icon, **{icon name: pause/play/fast-forward/double-fast/
> book/compass/magnifier-plus/magnifier-minus}**, palette babel_v1 bone +
> earth, single solid silhouette with one accent pixel of palette E (warm
> accent), centred, no border, transparent background.

### 7.3 Cursor + selection ring

- Default cursor: 16×16, classic arrow but tinted bone, palette G.
- Tile selection ring: 32×32 dashed outline that breathes (4-frame loop).
- Civilization border: 32×32 wang-set, dashed, 1-px wide, tinted by
  procedural civ colour at runtime. Generate a single white-mask template
  and let the engine tint it.

---

## 8. Effects — Zones, magic, combat, weather (v1.0 minimum)

### 8.1 Strugatsky-style anomaly Zones

3 distinct anomaly types. All loop 4 frames at 0.4 s.

> 32×32 pixel-art animated overlay, 4 frames left-to-right strip, magical
> anomaly pulse: **{type 1: floating broken geometry; type 2: time-frozen
> falling petals; type 3: gravity-warped grass curling upward}**, palette
> babel_v1 magic-violet group F, glow softly through alpha, no outline,
> single overlay on transparent background.

### 8.2 Magic ritual flash (Babel-style two-word magic)

Used once per ritual cast. 32×32, 5 frames, 0.6 s total.

> 32×32 pixel-art ritual flash, 5-frame strip, two glyph fragments meeting
> in the centre and bursting into silver-violet light, palette babel_v1
> group F + bone, expand-then-fade, transparent background, no text on
> glyphs.

### 8.3 Combat clash marker

When two factions collide on a tile, draw a clash X for 0.5 s, no detailed
combat in v1.

> 32×32 pixel-art combat clash, 2-frame strip, two crossed weapons (sword
> and spear) silhouette over a dust burst, palette babel_v1 earth + bone,
> no characters, no blood, single overlay on transparent background.

### 8.4 Weather overlays (deferred)

In v1.0 we do **fixed seasons** via tinting, not weather sprites. Prompts
for weather (rain / snow / heatwave / storm) move to v1.1.

---

## 9. Folder layout — drop assets exactly here

```
godot_project/assets/
  tiles/
    ocean/        ocean_a1.png … ocean_a9.png
    coast/        coast_a1.png … coast_a9.png
    plains/       …
    forest/       …
    hills/        …
    mountain/     …
    desert/       …
    tundra/       …
    transitions/  ocean_to_coast/ … plains_to_forest/ … (13-tile Wang sets)
    overlays/
      ruin/       ruin_1.png … ruin_4.png
      river/      river_wang13.png    (13-tile strip)
      road/       road_wang13.png
      zone/       zone_a_4f.png  zone_b_4f.png  zone_c_4f.png
      faded/      faded.png
      sacred/     sacred_1.png  sacred_2.png
  decorations/
    plains/       wildflower.png  rock.png  berry_bush.png  cart_wheel.png
    forest/       conifer.png     deciduous.png  fern.png   mushrooms.png
    hills/        …
    mountain/     …
    desert/       …
    tundra/       …
    coast/        …
  npcs/
    kheltari/
      commoner_sheet.png   (96×128, 3×4 grid as in §4.1)
      elder_sheet.png
      warrior_sheet.png
      priest_sheet.png
      sigil.png            (16×16)
    orunmare/   …
    dvarni/     …
    eluran/     …
    qarasil/    …
    ningaer/    …
    sankhara/   …
  buildings/
    kheltari/
      hamlet/
        dwelling.png    granary.png   market.png   temple.png
        wall_wang13.png workshop.png
      town/
        dwelling.png    granary.png   market.png   temple.png
        palace.png      wall_wang13.png  workshop.png
      city/
        … (same set, larger / more ornate)
    orunmare/   …
    …
  effects/
    fire_32x32_4f.png
    smoke_16x32_4f.png
    water_shimmer_32x32_3f.png
    banner_blank_kheltari.png  …  (one per culture)
    clash_32x32_2f.png
    ritual_flash_32x32_5f.png
  ui/
    book_closed.png
    book_open.png
    book_corner_curl_3f.png
    bookmark_red.png   bookmark_gold.png   bookmark_green.png
    icon_pause.png     icon_play.png       icon_fast.png      icon_very_fast.png
    icon_book.png      icon_compass.png    icon_zoom_in.png   icon_zoom_out.png
    cursor.png
    selection_ring_32x32_4f.png
    civ_border_wang13.png
  palette/
    babel_v1.gpl       (32-colour palette for Aseprite / GIMP)
    babel_v1.png       (16×2 strip of swatches, used by tooling)
```

**File naming rules:**

- Lowercase, snake_case, ASCII only.
- Animation strips: `name_{w}x{h}_{nframes}f.png` (e.g. `fire_32x32_4f.png`).
- Wang autotile sets: `name_wang13.png` (13 tiles in a known grid: row-major
  Godot 4.3 Terrains layout).
- Multi-variant statics: `name_a1.png … name_a9.png` (no zero-pad past 9).

---

## 10. AI tool recommendations

Pick one and stick with it for the whole pass — mixing tools mid-asset
makes palette consistency a nightmare.

### 10.1 Stable Diffusion XL + custom LoRA — best end state

- Run locally (RTX 3060 12 GB or rented A40 on Vast.ai $0.30/h is enough).
- Train a tiny LoRA (~50 images) of the *Sea of Stars* + *Eastward* +
  hand-pixelled tiles look. Unlocked once trained: every prompt above will
  produce on-style output.
- Pipeline: SDXL at 512×512 → Aseprite indexed-mode → palette `babel_v1.gpl`
  → resize 32×32 nearest → hand touch.

### 10.2 Flux.1-dev (open) — fastest start, no LoRA

- Better text alignment than SDXL out of the box. No training step needed.
- Same post-process pipeline through Aseprite.

### 10.3 Midjourney v6.1 — fastest, but watch licensing

- Use `--style raw --ar 1:1 --v 6.1`. Can produce strong pixel-art with the
  right prompt, but consistency across batches is weak unless you use
  `--cref` heavily.
- Licensing: ensure subscription tier permits commercial use before relying
  on it.

### 10.4 DALL-E 3 — fastest UI / icon turnaround

- Best for the chronicle book and isolated UI elements. Worst for tile
  consistency.

### 10.5 Hand-only Aseprite pass — fallback

- For a solo dev: start from `babel_v1.gpl`, use the brushes from
  https://daltoncalford.itch.io/30-pixel-art-brushes for free, follow Pedro
  Medeiros's tutorials. Budget ≈ 2 weeks per culture if you're skilled.

### 10.6 Last resort: stock packs

- Kenney.nl "Tiny Town", "Roguelike Pack" — free, CC0, but very limited
  variation and *off-style*. Use only as placeholder before art-pass.

---

## 11. Quality gates — what I check on intake

When you drop assets in `godot_project/assets/`, I run them through these
checks before integrating:

### 11.1 Automated (will be a Python script in `tools/asset_lint.py`):

1. **Indexed mode + palette match.** Every PNG must be in indexed colour
   mode with palette ⊆ `babel_v1.gpl`. Off-palette colours rejected.
2. **Power-of-two dimensions or exact tile multiple.** 32, 64, 96, 128,
   etc. No 33-pixel-wide sprites.
3. **No fully-opaque background.** Sprites must be alpha-isolated; tile
   art is alpha-opaque only on the tile silhouette.
4. **Animation strip integrity.** Filename `_{n}f` matches actual frame
   count. Frame width = strip width / n exact.
5. **No EXIF, no XMP, no thumbnails.** PNG only, stripped.
6. **Filename matches §9.** Snake_case ASCII, in the right folder.

### 11.2 Manual (squint test):

1. Read at 100 % zoom on a 1080p screen → does it match mood ref?
2. Read at 25 % zoom (thumbnail) → is biome/role still clear?
3. Compare adjacent tiles — does forest match plains at the seam? If a
   transition tile is needed, is it present?
4. Animation: play in Aseprite at the frame rate above. Does it look like
   it's breathing, not vibrating?

### 11.3 Failure handling

Any rejected asset gets sent back with a one-paragraph note quoting which
gate it failed and the exact prompt to retry. I don't try to "fix it
myself" — palette drift compounds.

---

## 12. Production order — start here

If we're just bringing one culture to demo quality first, the right order is:

1. **Palette & art-bible spread** — generate 1 sample frame of *each* asset
   type just to lock the look.
2. **Plains + Forest tiles + transitions + decorations.** Cheapest way to
   make the world look populated.
3. **Kheltari culture full set** (NPCs + buildings, all 3 tiers). Demo
   culture.
4. **UI** — chronicle book, HUD icons, cursor, selection ring.
5. **Effects** — water shimmer, ritual fire, smoke. The world feels alive
   from these alone.
6. **Coast + Hills + Mountain** tiles + their decorations.
7. **Orunmare + Dvarni cultures** (so demos can show 3 cultures
   interacting).
8. **Anomaly Zone overlays** (Strugatsky DLC1 tease).
9. **Desert + Tundra** tiles and their decorations.
10. **Eluran, Qarasil, Ningaer, Sankhara** cultures.
11. **Faded overlay + ritual flash + combat clash.**

This is **~600 sprites** at v1.0 if every item ships. Realistic budget for
a solo / 2-person team is 4–6 months of art with the AI pipeline above, or
8–12 months hand-made.

---

## 13. Drop-in test set — minimum viable demo (50 sprites)

To unblock the engine *immediately*, you only need to ship these 50
sprites first:

- 9 plains variants
- 4 plains decorations (wildflower, rock, berry bush, cart wheel)
- 9 forest variants
- 4 forest decorations (conifer, deciduous, fern, mushroom)
- 1 kheltari commoner sheet (96×128)
- 1 kheltari hamlet dwelling (32×32)
- 1 kheltari hamlet temple (64×64)
- 1 ritual fire animation (32×32 × 4 frames)
- 1 smoke animation (16×32 × 4 frames)
- 1 water shimmer (32×32 × 3 frames)
- 8 UI icons (pause/play/fast/very-fast/book/compass/zoom in/out)
- 1 book closed
- 1 book open
- 1 cursor
- 7 misc (banner blank, clash, ritual flash, selection ring, civ border,
  ruin overlay, sacred overlay)

50 assets total. The engine already uses placeholder rectangles; swapping
them in lights up the whole sim.

---

## 14. Hand-off checklist (paste into a sprint board)

- [ ] Palette `babel_v1.gpl` saved to `godot_project/assets/palette/`
- [ ] Master prompt prefix saved as a snippet in your AI tool
- [ ] Folder skeleton created (empty `tiles/`, `npcs/`, etc.)
- [ ] Drop-in test set (50 sprites) generated and lint-passed
- [ ] First in-game screenshot taken with the test set, sent for review
- [ ] Lock the SDXL/Flux seed for "kheltari look", record it in
      `godot_project/assets/npcs/kheltari/_seed.txt`
- [ ] Repeat per culture

---

End of brief. Generate against the master prefix; drop everything in
`godot_project/assets/`; ping me with the folder name when you're ready
and I'll lint, integrate, and screenshot the result.
