extends Node2D
## Renders the simulation tile grid as a single Sprite2D-backed image, using
## a per-biome library of 32×32 variants and gradient alpha-blend edge
## blending so adjacent biomes (sand vs grass etc.) fade into one another
## smoothly instead of meeting at a hard rectangular seam.
##
## Pipeline:
##   1. _load_variants() at _ready: parse every PNG under
##      assets/tiles/<biome>/variants/ into an array of [Image].
##   2. _build_blend_masks(): pre-bake four alpha [Image] masks (one per
##      cardinal edge) whose alpha varies smoothly with distance from the
##      tile seam (full opacity at the seam, fading to 0 inward).
##   3. _rebuild_image(): for each tile in the world,
##        a. blit a deterministic variant of the tile's own biome,
##        b. for every 4-neighbour with a *different* biome,
##           blend_rect_mask the neighbour's variant through the matching
##           gradient mask, sourcing pixels from the neighbour's far edge
##           so the texture reads as continuous across the seam.
##   4. invalidate_tile(x, y): patch a small region in-place when a tile
##      changes without redrawing the whole world.
##
## All variants live as a Dictionary keyed by biome name; if a biome has no
## variants on disk we fall back to the legacy flat colour stamp so the
## game still renders.

const TILE_PX := 32  ## Image pixels per tile. Matches variant size.
# Blend tuning. The blend lays a per-pixel alpha mask over the boundary
# band: each tile pulls a thin slice of the neighbour's variant onto its
# own outer edge. Three failure modes drove the choice of parameters:
#
#  - Wide bands (>10px) average two contrasting biome colours into a
#    muddy intermediate that reads as an inverted outline.
#  - Asymmetric peak (e.g. 0.85) produces a one-sided overshoot on the
#    seam pixel, painting a hard stripe.
#  - Pure smooth gradients of any shape still create a *banded* fade
#    that feels mechanical at zoomed-out scale.
#
# Solution: a very narrow band (4 px) plus per-pixel hash noise on the
# alpha. The blend region is small enough that no muddy stripe forms,
# and the noise breaks the boundary into a ragged single-pixel fringe
# that perceptually reads as a natural pixel-art edge.
const BLEND_BAND := 3
const BLEND_PEAK := 0.35
const BLEND_GAMMA := 1.8
# Per-pixel noise amplitude added to the gradient ramp before alpha is
# computed. 0 → smooth band; 1 → essentially binary threshold. Higher
# values give the seam a more "speckled / pixel-art tuft" character.
const BLEND_NOISE := 0.65
const FRINGE_SEED := 0xB1B1_9001

const BIOME_NAMES := ["ocean", "coast", "plains", "forest",
					  "hills", "mountain", "desert", "tundra"]

const BIOME_FALLBACK_COLORS := {
	0: Color8(28,  46,  76,  255),  # Ocean
	1: Color8(64,  102, 132, 255),  # Coast
	2: Color8(159, 175, 102, 255),  # Plains
	3: Color8(58,  100, 64,  255),  # Forest
	4: Color8(124, 132, 96,  255),  # Hills
	5: Color8(110, 100, 92,  255),  # Mountain
	6: Color8(206, 184, 124, 255),  # Desert
	7: Color8(214, 220, 224, 255),  # Tundra
}

# Tile-tag bits are kept here for hover-label use only — we no longer paint
# rivers / ruins / zones as solid coloured squares because they were too
# visually loud against the textured terrain.
const TILE_TAG_RUIN  := 0x01
const TILE_TAG_RIVER := 0x04
const TILE_TAG_ZONE  := 0x10  ## babel_sim::tile_tags::ZONE

var _state: Node = null
var _dims: Vector2i = Vector2i.ZERO
var _sprite: Sprite2D
var _texture: ImageTexture
var _image: Image

# biome_name -> Array[Image]
var _variants: Dictionary = {}
# biome_name -> Image (used when variants are missing)
var _fallback_tiles: Dictionary = {}

# Pre-baked alpha gradient masks, keyed by direction string. Each mask is
# TILE_PX×TILE_PX with non-zero alpha only inside the BLEND_BAND-wide band
# along the matching edge. Alpha varies smoothly with distance from the
# seam so blend_rect_mask produces a true alpha gradient at the boundary.
var _blend_masks: Dictionary = {}

# Source rects used to sample neighbour variants for each directional blit.
var _neighbour_src_rects: Dictionary = {}
# Destination offsets within a tile for each directional band.
var _band_dst_offsets: Dictionary = {}

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_load_variants()
	_build_blend_masks()
	_build_blit_geometry()

func bind(state: Node) -> void:
	_state = state
	_dims = state.dims()
	if _dims.x <= 0 or _dims.y <= 0:
		return
	_rebuild_image()
	# Sprite is rendered 1:1 — image already carries native pixel detail.
	_sprite.scale = Vector2(1.0, 1.0)

## World-space rect occupied by the rendered map.
func world_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(_dims) * float(TILE_PX))

## Convert a world-space point to integer tile coords.
## Returns `Vector2i(-1, -1)` if outside the map.
func world_to_tile(world_pos: Vector2) -> Vector2i:
	var tx := int(floor(world_pos.x / float(TILE_PX)))
	var ty := int(floor(world_pos.y / float(TILE_PX)))
	if tx < 0 or ty < 0 or tx >= _dims.x or ty >= _dims.y:
		return Vector2i(-1, -1)
	return Vector2i(tx, ty)

## Convert an integer tile coord to its world-space top-left corner.
func tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(tile.x, tile.y) * float(TILE_PX)

## Mark a tile dirty and re-render it (and its 4-neighbours so the dither
## bands stay consistent). Cheap — only ~9 small blits.
func invalidate_tile(x: int, y: int) -> void:
	if _image == null:
		return
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			_paint_tile(x + dx, y + dy)
	_texture.update(_image)

# ----- internals -----

func _load_variants() -> void:
	# Variants ship as imported PNGs under res://assets/tiles/<biome>/variants/.
	# We pull each through ResourceLoader (so it goes through Godot's import
	# pipeline and works in exported builds) and then unwrap the underlying
	# Image so the renderer can blit it directly.
	for biome in BIOME_NAMES:
		var dir_path := "res://assets/tiles/%s/variants" % biome
		var imgs: Array[Image] = []
		var dir := DirAccess.open(dir_path)
		if dir != null:
			dir.list_dir_begin()
			var files: Array[String] = []
			while true:
				var fn := dir.get_next()
				if fn == "":
					break
				# Imported textures show up as plain .png in DirAccess; their
				# .import sidecar is filtered out by checking the extension.
				if fn.ends_with(".png"):
					files.append(fn)
			dir.list_dir_end()
			files.sort()
			for fn in files:
				var path := "%s/%s" % [dir_path, fn]
				var tex: Texture2D = load(path) as Texture2D
				if tex == null:
					continue
				var img := tex.get_image()
				if img == null:
					continue
				if img.get_width() != TILE_PX or img.get_height() != TILE_PX:
					continue
				if img.is_compressed():
					img.decompress()
				if img.get_format() != Image.FORMAT_RGBA8:
					img.convert(Image.FORMAT_RGBA8)
				imgs.append(img)
		_variants[biome] = imgs
		# Build a flat-colour fallback tile for biomes with no variants.
		var biome_idx := BIOME_NAMES.find(biome)
		var color: Color = BIOME_FALLBACK_COLORS.get(biome_idx, Color(1.0, 0.0, 1.0))
		var fallback := Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
		fallback.fill(color)
		_fallback_tiles[biome] = fallback
		print("[WorldView] biome '%s': %d variants" % [biome, imgs.size()])

func _build_blend_masks() -> void:
	# Each directional mask is the same size as the variant image
	# (TILE_PX×TILE_PX) so blend_rect_mask can sample it. Non-zero alpha is
	# confined to the BLEND_BAND-wide band that the matching src_rect reads:
	#
	#   N (we paint our top from neighbour's bottom)  → bottom band
	#   S (we paint our bottom from neighbour's top)  → top band
	#   W (our left from neighbour's right)            → right band
	#   E (our right from neighbour's left)            → left band
	#
	# Inside the band, alpha = round(255 * BLEND_PEAK * (1 - d/BAND)^GAMMA),
	# where d is the distance to the seam. Higher gamma keeps the blend
	# concentrated near the seam, giving a soft gradient instead of a
	# uniform translucent overlay.
	_blend_masks["N"] = _make_gradient_mask("N")
	_blend_masks["S"] = _make_gradient_mask("S")
	_blend_masks["W"] = _make_gradient_mask("W")
	_blend_masks["E"] = _make_gradient_mask("E")

func _make_gradient_mask(direction: String) -> Image:
	# `d` is the distance, in destination space, from the seam (the tile's
	# outer edge facing the neighbour). Alpha peaks at d=0 and falls off
	# inward.
	#
	# The mask is sampled at *source* coords (because Image.blend_rect_mask
	# reads the mask at the same pixel as the source pixel being blended).
	# For directions where the source rect's top-left does NOT correspond to
	# the dst seam, `d` and the source-axis index move in OPPOSITE
	# directions; this is what trips up casual implementations and produces
	# a thin "outline" stripe inside the tile instead of a fade at the
	# boundary.
	#
	# Per-pixel hash noise is then mixed into the alpha so the boundary
	# becomes a ragged fringe of speckled pixels rather than a clean
	# rectangular band.
	var mask := Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
	mask.fill(Color8(0, 0, 0, 0))
	if BLEND_BAND <= 0:
		return mask
	for y in TILE_PX:
		for x in TILE_PX:
			var d: int = -1
			match direction:
				"N":
					if y >= TILE_PX - BLEND_BAND:
						d = y - (TILE_PX - BLEND_BAND)
				"S":
					if y < BLEND_BAND:
						d = (BLEND_BAND - 1) - y
				"W":
					if x >= TILE_PX - BLEND_BAND:
						d = x - (TILE_PX - BLEND_BAND)
				"E":
					if x < BLEND_BAND:
						d = (BLEND_BAND - 1) - x
			if d < 0:
				continue
			var t := 1.0 - float(d) / float(BLEND_BAND)
			var ramp := BLEND_PEAK * pow(t, BLEND_GAMMA)
			# Hash (x, y, direction-index) into a [0, 1] noise value so each
			# direction has an uncorrelated speckle pattern and adjacent
			# tiles' fringes interlock instead of forming a uniform stripe.
			var dir_idx: int = "NSWE".find(direction)
			var n: float = _hash01(x, y, dir_idx)
			var a := ramp + (n - 0.5) * BLEND_NOISE
			var alpha := int(round(clampf(a, 0.0, 1.0) * 255.0))
			if alpha > 0:
				mask.set_pixel(x, y, Color8(255, 255, 255, alpha))
	return mask

func _hash01(x: int, y: int, k: int) -> float:
	# 32-bit integer mix → [0, 1] float. Avoids any pattern visible at the
	# 32×32 tile scale.
	var h: int = (x * 374761393) ^ (y * 668265263) ^ (k * 2147483647) ^ FRINGE_SEED
	h = (h ^ (h >> 13)) * 1274126177
	h = (h ^ (h >> 16)) & 0x7FFFFFFF
	return float(h % 65536) / 65535.0

func _build_blit_geometry() -> void:
	# When blitting a *neighbour's* variant onto our tile via a directional
	# mask, we need to source pixels from the neighbour's far edge so the
	# texture content visually continues across the seam.
	#
	# E.g. for N (above us): pull from the bottom BLEND_BAND rows of the
	# neighbour and lay them along our top BLEND_BAND rows.
	_neighbour_src_rects["N"] = Rect2i(0, TILE_PX - BLEND_BAND, TILE_PX, BLEND_BAND)
	_neighbour_src_rects["S"] = Rect2i(0, 0, TILE_PX, BLEND_BAND)
	_neighbour_src_rects["W"] = Rect2i(TILE_PX - BLEND_BAND, 0, BLEND_BAND, TILE_PX)
	_neighbour_src_rects["E"] = Rect2i(0, 0, BLEND_BAND, TILE_PX)
	_band_dst_offsets["N"] = Vector2i(0, 0)
	_band_dst_offsets["S"] = Vector2i(0, TILE_PX - BLEND_BAND)
	_band_dst_offsets["W"] = Vector2i(0, 0)
	_band_dst_offsets["E"] = Vector2i(TILE_PX - BLEND_BAND, 0)

func _rebuild_image() -> void:
	var w := _dims.x * TILE_PX
	var h := _dims.y * TILE_PX
	_image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var t0 := Time.get_ticks_msec()
	for y in _dims.y:
		for x in _dims.x:
			_paint_tile(x, y)
	var t1 := Time.get_ticks_msec()
	print("[WorldView] baked %dx%d image in %d ms" % [w, h, t1 - t0])
	_texture = ImageTexture.create_from_image(_image)
	_sprite.texture = _texture

func _paint_tile(x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= _dims.x or y >= _dims.y:
		return
	var biome_id: int = _state.tile_biome(x, y)
	var biome_name: String = BIOME_NAMES[biome_id] if biome_id >= 0 and biome_id < BIOME_NAMES.size() else ""
	var dst := Vector2i(x * TILE_PX, y * TILE_PX)
	var base := _variant_for_tile(biome_name, x, y)
	_image.blit_rect(base, Rect2i(0, 0, TILE_PX, TILE_PX), dst)

	# Edge dither blending — only when neighbour exists and is a different biome.
	var neighbour_dirs := [
		["N", x, y - 1],
		["S", x, y + 1],
		["W", x - 1, y],
		["E", x + 1, y],
	]
	if BLEND_BAND <= 0:
		return
	for entry in neighbour_dirs:
		var dir_name: String = entry[0]
		var nx: int = entry[1]
		var ny: int = entry[2]
		if nx < 0 or ny < 0 or nx >= _dims.x or ny >= _dims.y:
			continue
		var n_biome_id: int = _state.tile_biome(nx, ny)
		if n_biome_id == biome_id:
			continue
		var n_biome_name: String = BIOME_NAMES[n_biome_id] if n_biome_id >= 0 and n_biome_id < BIOME_NAMES.size() else ""
		var n_variant := _variant_for_tile(n_biome_name, nx, ny)
		var src_rect: Rect2i = _neighbour_src_rects[dir_name]
		var band_off: Vector2i = _band_dst_offsets[dir_name]
		var mask: Image = _blend_masks[dir_name]
		_image.blend_rect_mask(n_variant, mask, src_rect, dst + band_off)

func _variant_for_tile(biome_name: String, x: int, y: int) -> Image:
	var arr: Array = _variants.get(biome_name, [])
	if arr.is_empty():
		return _fallback_tiles.get(biome_name, _fallback_tiles[BIOME_NAMES[0]])
	# Stable hash over coords so replays look identical.
	var h: int = (x * 73856093) ^ (y * 19349663)
	h ^= h >> 13
	h *= 0x5BD1E995
	h &= 0x7FFFFFFF
	return arr[h % arr.size()]


