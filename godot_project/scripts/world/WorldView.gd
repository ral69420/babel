extends Node2D
## Renders the simulation tile grid using texture tiles with smooth blending.
##
## Uses individual Sprite2D nodes per tile (batched via CanvasItem) and a
## blending overlay layer for smooth biome transitions. NPC and building
## sprites are managed as child nodes.

const TILE_PX := 32   ## Tile size in pixels (matches texture dimensions).

## Biome texture paths — order matches biome IDs 0..7.
const BIOME_TEXTURES := [
	"res://assets/tiles/ocean/ocean.png",
	"res://assets/tiles/coast/coast.png",
	"res://assets/tiles/plains/plains.png",
	"res://assets/tiles/forest/forest.png",
	"res://assets/tiles/hills/hills.png",
	"res://assets/tiles/mountain/mountain.png",
	"res://assets/tiles/desert/desert.png",
	"res://assets/tiles/tundra/tundra.png",
]

const CIV_COLORS := [
	Color(0.9, 0.3, 0.3),   # Civ 0 — red
	Color(0.3, 0.6, 0.9),   # Civ 1 — blue
	Color(0.3, 0.9, 0.4),   # Civ 2 — green
	Color(0.9, 0.8, 0.2),   # Civ 3 — yellow
]

var _state: Node = null
var _dims: Vector2i = Vector2i.ZERO
var _tile_textures: Array[Texture2D] = []
var _tile_image: Image           # baked map image (1px per tile, used for mini-map + blending)
var _tile_texture: ImageTexture  # uploaded version

# Sub-layers
var _terrain_layer: Node2D       # holds the baked terrain sprite
var _blend_layer: Node2D         # semi-transparent edge blending
var _building_layer: Node2D      # building sprites
var _npc_layer: Node2D           # NPC sprites

var _npc_sprites: Dictionary = {}      # npc_id → Sprite2D
var _building_sprites: Dictionary = {} # building_id → Sprite2D

var _npc_texture: Texture2D
var _building_texture: Texture2D

func _ready() -> void:
	# Load biome textures
	for path in BIOME_TEXTURES:
		_tile_textures.append(load(path) as Texture2D)

	# Load NPC and building textures
	_npc_texture = load("res://assets/npcs/default/walk_south.png") as Texture2D
	_building_texture = load("res://assets/buildings/default/house.png") as Texture2D

	# Create render layers
	_terrain_layer = Node2D.new()
	_terrain_layer.name = "TerrainLayer"
	add_child(_terrain_layer)

	_blend_layer = Node2D.new()
	_blend_layer.name = "BlendLayer"
	add_child(_blend_layer)

	_building_layer = Node2D.new()
	_building_layer.name = "BuildingLayer"
	add_child(_building_layer)

	_npc_layer = Node2D.new()
	_npc_layer.name = "NPCLayer"
	add_child(_npc_layer)

func bind(state: Node) -> void:
	_state = state
	_dims = state.dims()
	if _dims.x <= 0 or _dims.y <= 0:
		return
	_build_terrain()

## World-space rect occupied by the rendered map.
func world_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(_dims) * float(TILE_PX))

## Convert a world-space point to integer tile coords.
func world_to_tile(world_pos: Vector2) -> Vector2i:
	var tx := int(floor(world_pos.x / float(TILE_PX)))
	var ty := int(floor(world_pos.y / float(TILE_PX)))
	if tx < 0 or ty < 0 or tx >= _dims.x or ty >= _dims.y:
		return Vector2i(-1, -1)
	return Vector2i(tx, ty)

func update_entities() -> void:
	if _state == null:
		return
	_update_npcs()
	_update_buildings()

# ─────────────────────────────────────────────────────────────────────
# Terrain rendering — bake the map into a single large image using tiles
# ─────────────────────────────────────────────────────────────────────
func _build_terrain() -> void:
	# Create a large image by tiling biome textures
	var map_img := Image.create(_dims.x * TILE_PX, _dims.y * TILE_PX, false, Image.FORMAT_RGBA8)

	# Load source images for each biome
	var biome_images: Array[Image] = []
	for tex in _tile_textures:
		biome_images.append(tex.get_image())

	# Paint tiles
	for y in _dims.y:
		for x in _dims.x:
			var b: int = _state.tile_biome(x, y)
			b = clampi(b, 0, biome_images.size() - 1)
			var src: Image = biome_images[b]
			var dst_x := x * TILE_PX
			var dst_y := y * TILE_PX
			map_img.blit_rect(src, Rect2i(0, 0, TILE_PX, TILE_PX), Vector2i(dst_x, dst_y))

	# Apply edge blending — for each tile, blend with neighbours
	_apply_edge_blending(map_img, biome_images)

	# Apply subtle elevation shading
	for y in _dims.y:
		for x in _dims.x:
			var elev: int = _state.tile_elevation(x, y)
			var shade := (float(elev) - 128.0) / 512.0
			if abs(shade) > 0.01:
				for py in TILE_PX:
					for px in TILE_PX:
						var ix := x * TILE_PX + px
						var iy := y * TILE_PX + py
						var c := map_img.get_pixel(ix, iy)
						c = Color(
							clampf(c.r + shade, 0.0, 1.0),
							clampf(c.g + shade, 0.0, 1.0),
							clampf(c.b + shade, 0.0, 1.0),
							c.a
						)
						map_img.set_pixel(ix, iy, c)

	var tex := ImageTexture.create_from_image(map_img)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_terrain_layer.add_child(sprite)

func _apply_edge_blending(map_img: Image, biome_images: Array[Image]) -> void:
	## Blend edges between different biomes for smooth transitions.
	## For each tile, if a neighbor has a different biome, blend the edge
	## pixels with a gradient.
	var blend_px := 6  # pixels of blending at each edge

	for y in _dims.y:
		for x in _dims.x:
			var b: int = _state.tile_biome(x, y)
			# Check 4 neighbours
			var neighbors := [
				[x, y - 1, 0],   # top
				[x, y + 1, 1],   # bottom
				[x - 1, y, 2],   # left
				[x + 1, y, 3],   # right
			]
			for n in neighbors:
				var nx: int = n[0]
				var ny: int = n[1]
				var side: int = n[2]
				if nx < 0 or ny < 0 or nx >= _dims.x or ny >= _dims.y:
					continue
				var nb: int = _state.tile_biome(nx, ny)
				if nb == b:
					continue
				nb = clampi(nb, 0, biome_images.size() - 1)
				var nb_img: Image = biome_images[nb]
				# Blend pixels at the edge
				for i in blend_px:
					var alpha := 1.0 - float(i) / float(blend_px)
					alpha *= 0.5  # softer blend
					for j in TILE_PX:
						var px: int
						var py: int
						var src_px: int
						var src_py: int
						match side:
							0:  # top edge
								px = x * TILE_PX + j
								py = y * TILE_PX + i
								src_px = j % nb_img.get_width()
								src_py = (TILE_PX - blend_px + i) % nb_img.get_height()
							1:  # bottom edge
								px = x * TILE_PX + j
								py = y * TILE_PX + (TILE_PX - 1 - i)
								src_px = j % nb_img.get_width()
								src_py = i % nb_img.get_height()
							2:  # left edge
								px = x * TILE_PX + i
								py = y * TILE_PX + j
								src_px = (TILE_PX - blend_px + i) % nb_img.get_width()
								src_py = j % nb_img.get_height()
							3:  # right edge
								px = x * TILE_PX + (TILE_PX - 1 - i)
								py = y * TILE_PX + j
								src_px = i % nb_img.get_width()
								src_py = j % nb_img.get_height()
						if px >= 0 and px < map_img.get_width() and py >= 0 and py < map_img.get_height():
							var existing := map_img.get_pixel(px, py)
							var nb_color := nb_img.get_pixel(src_px, src_py)
							var blended := existing.lerp(nb_color, alpha)
							map_img.set_pixel(px, py, blended)

# ─────────────────────────────────────────────────────────────────────
# Entity rendering
# ─────────────────────────────────────────────────────────────────────
func _update_npcs() -> void:
	var npc_list: Array = _state.get_npcs()
	var active_ids: Dictionary = {}

	for npc in npc_list:
		if not npc.alive:
			if _npc_sprites.has(npc.id):
				_npc_sprites[npc.id].queue_free()
				_npc_sprites.erase(npc.id)
			continue

		active_ids[npc.id] = true
		var sprite: Sprite2D

		if _npc_sprites.has(npc.id):
			sprite = _npc_sprites[npc.id]
		else:
			sprite = Sprite2D.new()
			sprite.texture = _npc_texture
			sprite.hframes = 6
			sprite.centered = true
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			# Tint by civilization
			var civ_idx: int = clampi(npc.civ_id, 0, CIV_COLORS.size() - 1)
			sprite.modulate = CIV_COLORS[civ_idx]
			_npc_layer.add_child(sprite)
			_npc_sprites[npc.id] = sprite

		# Position
		sprite.position = Vector2(npc.x * TILE_PX + TILE_PX / 2, npc.y * TILE_PX + TILE_PX / 2)

		# Scale children smaller
		if npc.is_child:
			sprite.scale = Vector2(0.75, 0.75)
		else:
			sprite.scale = Vector2(1.0, 1.0)

		# Animate walk frame
		var frame_idx := (Engine.get_frames_drawn() / 8 + npc.id) % 6
		sprite.frame = frame_idx

	# Remove sprites for dead/gone NPCs
	var to_remove: Array = []
	for npc_id in _npc_sprites:
		if not active_ids.has(npc_id):
			to_remove.append(npc_id)
	for npc_id in to_remove:
		_npc_sprites[npc_id].queue_free()
		_npc_sprites.erase(npc_id)

func _update_buildings() -> void:
	var bld_list: Array = _state.get_buildings()
	var active_ids: Dictionary = {}

	for bld in bld_list:
		active_ids[bld.id] = true
		var sprite: Sprite2D

		if _building_sprites.has(bld.id):
			sprite = _building_sprites[bld.id]
		else:
			sprite = Sprite2D.new()
			sprite.texture = _building_texture
			sprite.centered = false
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_building_layer.add_child(sprite)
			_building_sprites[bld.id] = sprite

		# Position (2×2 tile footprint)
		sprite.position = Vector2(bld.tile_x * TILE_PX, bld.tile_y * TILE_PX)

		# Stage-based appearance
		var stage: int = bld.stage
		if stage == 4:  # COMPLETE
			sprite.modulate = Color(1, 1, 1, 1)
			sprite.scale = Vector2(1.0, 1.0)
		elif stage == 3:  # ROOF
			sprite.modulate = Color(0.9, 0.9, 0.9, 0.95)
			sprite.scale = Vector2(1.0, 0.95)
		elif stage == 2:  # WALLS
			sprite.modulate = Color(0.7, 0.7, 0.7, 0.85)
			sprite.scale = Vector2(1.0, 0.7)
		elif stage == 1:  # FRAME
			sprite.modulate = Color(0.6, 0.6, 0.5, 0.7)
			sprite.scale = Vector2(1.0, 0.4)
		else:  # FOUNDATION
			sprite.modulate = Color(0.5, 0.5, 0.4, 0.5)
			sprite.scale = Vector2(1.0, 0.2)

		# Progress bar for incomplete buildings
		if stage < 4:
			_draw_progress_bar(sprite, bld)

func _draw_progress_bar(sprite: Sprite2D, bld: Dictionary) -> void:
	# Use a simple ColorRect child as progress bar
	var bar_name := "ProgressBar"
	var bg_name := "ProgressBG"
	var bar: ColorRect
	var bg: ColorRect

	if sprite.has_node(bar_name):
		bar = sprite.get_node(bar_name) as ColorRect
		bg = sprite.get_node(bg_name) as ColorRect
	else:
		bg = ColorRect.new()
		bg.name = bg_name
		bg.color = Color(0.2, 0.2, 0.2, 0.8)
		bg.size = Vector2(48, 4)
		bg.position = Vector2(8, -8)
		sprite.add_child(bg)

		bar = ColorRect.new()
		bar.name = bar_name
		bar.color = Color(1.0, 0.85, 0.2, 0.9)
		bar.size = Vector2(0, 4)
		bar.position = Vector2(8, -8)
		sprite.add_child(bar)

	var pct := clampf(float(bld.progress_days) / 30.0, 0.0, 1.0)
	bar.size.x = 48.0 * pct
