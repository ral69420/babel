extends Node2D
## Renders the simulation tile grid using texture tiles with smooth blending.

const TILE_PX := 32

const BIOME_TILE_PATHS := [
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
	Color(1.00, 0.50, 0.50),  # Civ 0 — red
	Color(0.50, 0.70, 1.00),  # Civ 1 — blue
	Color(0.55, 1.00, 0.60),  # Civ 2 — green
	Color(1.00, 0.90, 0.40),  # Civ 3 — yellow
	Color(0.85, 0.55, 1.00),  # Civ 4 — purple
	Color(1.00, 0.65, 0.30),  # Civ 5 — orange
]

var _state: Node = null
var _dims: Vector2i = Vector2i.ZERO

var _terrain_layer: Node2D
var _building_layer: Node2D
var _npc_layer: Node2D

var _npc_sprites: Dictionary = {}
var _building_sprites: Dictionary = {}

var _npc_texture: Texture2D
var _building_texture: Texture2D

func _ready() -> void:
	_npc_texture = load("res://assets/npcs/default/walk_south.png") as Texture2D
	_building_texture = load("res://assets/buildings/default/house.png") as Texture2D

	_terrain_layer = Node2D.new()
	_terrain_layer.name = "TerrainLayer"
	add_child(_terrain_layer)

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

func world_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(_dims) * float(TILE_PX))

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
# Terrain — bake into one image using blit_rect (fast)
# ─────────────────────────────────────────────────────────────────────
func _build_terrain() -> void:
	# Load biome images directly from disk for reliable RGBA8 format
	var biome_images: Array[Image] = []
	for path in BIOME_TILE_PATHS:
		var img := Image.new()
		# Get absolute path from res://
		var abs_path := ProjectSettings.globalize_path(path)
		var err := img.load(abs_path)
		if err != OK:
			# Fallback: try loading via resource and converting
			var tex := load(path) as Texture2D
			if tex:
				img = tex.get_image()
				if img:
					img.convert(Image.FORMAT_RGBA8)
				else:
					img = Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
					img.fill(Color.MAGENTA)
			else:
				img = Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
				img.fill(Color.MAGENTA)
		else:
			img.convert(Image.FORMAT_RGBA8)
		biome_images.append(img)
	
	print("[WorldView] Building terrain %d×%d tiles..." % [_dims.x, _dims.y])
	
	var map_w: int = _dims.x * TILE_PX
	var map_h: int = _dims.y * TILE_PX
	var map_img := Image.create(map_w, map_h, false, Image.FORMAT_RGBA8)

	# Blit tiles (fast — no per-pixel work)
	for y in _dims.y:
		for x in _dims.x:
			var b: int = clampi(_state.tile_biome(x, y), 0, biome_images.size() - 1)
			var src: Image = biome_images[b]
			map_img.blit_rect(src, Rect2i(0, 0, TILE_PX, TILE_PX), Vector2i(x * TILE_PX, y * TILE_PX))

	var tex := ImageTexture.create_from_image(map_img)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	# Apply GPU-based edge blending shader
	var shader := load("res://shaders/terrain_blend.gdshader") as Shader
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("blend_radius", 3.0)
		mat.set_shader_parameter("tile_size", Vector2(TILE_PX, TILE_PX))
		mat.set_shader_parameter("map_size_tiles", Vector2(_dims.x, _dims.y))
		sprite.material = mat

	_terrain_layer.add_child(sprite)
	print("[WorldView] Terrain built.")

func _apply_fast_blending(map_img: Image, biome_images: Array[Image]) -> void:
	var blend_size := 4
	for y in _dims.y:
		for x in _dims.x:
			var b: int = _state.tile_biome(x, y)
			# Only blend at boundaries — check right and bottom neighbours
			# Right neighbor
			if x + 1 < _dims.x:
				var nb: int = _state.tile_biome(x + 1, y)
				if nb != b:
					nb = clampi(nb, 0, biome_images.size() - 1)
					var nb_img: Image = biome_images[nb]
					var base_x: int = (x + 1) * TILE_PX
					for i in blend_size:
						var alpha: float = 0.4 * (1.0 - float(i) / float(blend_size))
						for py in TILE_PX:
							var px: int = base_x + i
							if px < map_img.get_width():
								var existing: Color = map_img.get_pixel(px, y * TILE_PX + py)
								var src_px: int = i % nb_img.get_width()
								var src_py: int = py % nb_img.get_height()
								var src_c: Color = nb_img.get_pixel(src_px, src_py)
								# Blend: pull existing toward the source biome's neighbor
								var cur_b_img: Image = biome_images[clampi(b, 0, biome_images.size() - 1)]
								var cur_c: Color = cur_b_img.get_pixel(src_px, src_py)
								map_img.set_pixel(px, y * TILE_PX + py, existing.lerp(cur_c, alpha))
					# Also blend the last pixels of current tile toward neighbor
					for i in blend_size:
						var alpha: float = 0.4 * (float(i + 1) / float(blend_size))
						for py in TILE_PX:
							var px: int = x * TILE_PX + TILE_PX - 1 - (blend_size - 1 - i)
							if px >= 0 and px < map_img.get_width():
								var existing: Color = map_img.get_pixel(px, y * TILE_PX + py)
								var src_py: int = py % nb_img.get_height()
								var src_px: int = (TILE_PX - blend_size + i) % nb_img.get_width()
								var nb_c: Color = nb_img.get_pixel(src_px, src_py)
								map_img.set_pixel(px, y * TILE_PX + py, existing.lerp(nb_c, alpha))
			# Bottom neighbor
			if y + 1 < _dims.y:
				var nb: int = _state.tile_biome(x, y + 1)
				if nb != b:
					nb = clampi(nb, 0, biome_images.size() - 1)
					var nb_img: Image = biome_images[nb]
					var base_y: int = (y + 1) * TILE_PX
					for i in blend_size:
						var alpha: float = 0.4 * (1.0 - float(i) / float(blend_size))
						for px in TILE_PX:
							var py: int = base_y + i
							if py < map_img.get_height():
								var existing: Color = map_img.get_pixel(x * TILE_PX + px, py)
								var src_px: int = px % nb_img.get_width()
								var src_py: int = i % nb_img.get_height()
								var cur_b_img: Image = biome_images[clampi(b, 0, biome_images.size() - 1)]
								var cur_c: Color = cur_b_img.get_pixel(src_px, src_py)
								map_img.set_pixel(x * TILE_PX + px, py, existing.lerp(cur_c, alpha))

# ─────────────────────────────────────────────────────────────────────
# NPC rendering
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
			var civ_idx: int = clampi(int(npc.civ_id), 0, CIV_COLORS.size() - 1)
			sprite.modulate = CIV_COLORS[civ_idx]
			_npc_layer.add_child(sprite)
			_npc_sprites[npc.id] = sprite

		sprite.position = Vector2(int(npc.x) * TILE_PX + TILE_PX / 2, int(npc.y) * TILE_PX + TILE_PX / 2)

		if npc.is_child:
			sprite.scale = Vector2(0.75, 0.75)
		else:
			sprite.scale = Vector2(1.0, 1.0)

		var frame_idx: int = (Engine.get_frames_drawn() / 8 + int(npc.id)) % 6
		sprite.frame = frame_idx

	var to_remove: Array = []
	for npc_id in _npc_sprites:
		if not active_ids.has(npc_id):
			to_remove.append(npc_id)
	for npc_id in to_remove:
		_npc_sprites[npc_id].queue_free()
		_npc_sprites.erase(npc_id)

# ─────────────────────────────────────────────────────────────────────
# Building rendering
# ─────────────────────────────────────────────────────────────────────
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

		sprite.position = Vector2(int(bld.tile_x) * TILE_PX, int(bld.tile_y) * TILE_PX)

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

		# Progress bar
		if stage < 4:
			_ensure_progress_bar(sprite, bld)

func _ensure_progress_bar(sprite: Sprite2D, bld: Dictionary) -> void:
	var bar_name := "ProgressBar"
	var bg_name := "ProgressBG"
	var bar: ColorRect
	var bg: ColorRect

	if sprite.has_node(bar_name):
		bar = sprite.get_node(bar_name) as ColorRect
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

	var pct: float = clampf(float(bld.progress_days) / 30.0, 0.0, 1.0)
	bar.size.x = 48.0 * pct
