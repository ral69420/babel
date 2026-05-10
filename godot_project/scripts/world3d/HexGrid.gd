extends Node3D
## Generates a 3D hex-tile terrain mesh with elevation and biome textures.
##
## Uses flat-top hexagons in axial coordinates (q, r).
## Each hex becomes geometry in a batched ArrayMesh for performance.

const HEX_SIZE := 1.0          ## Outer radius of each hex.
const SQRT3 := 1.7320508        ## sqrt(3)
const ELEV_SCALE := 0.015       ## World-units per elevation unit (0..255).

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

const BIOME_BASE_ELEV := [
	-0.5,   # Ocean — below sea level
	-0.05,  # Coast — just at water line
	0.0,    # Plains — flat
	0.1,    # Forest — slight rise
	0.4,    # Hills
	1.2,    # Mountain — tall
	0.05,   # Desert — flat
	0.15,   # Tundra — slight rise
]

const CIV_COLORS := [
	Color(1.0, 0.5, 0.5),
	Color(0.5, 0.7, 1.0),
	Color(0.5, 1.0, 0.6),
	Color(1.0, 0.9, 0.4),
]

var _state: Node = null
var _dims: Vector2i = Vector2i.ZERO
var _entity_root: Node3D
var _npc_sprites: Dictionary = {}
var _building_sprites: Dictionary = {}
var _npc_texture: Texture2D
var _building_texture: Texture2D

func _ready() -> void:
	_npc_texture = load("res://assets/npcs/default/walk_south.png") as Texture2D
	_building_texture = load("res://assets/buildings/default/house.png") as Texture2D
	_entity_root = Node3D.new()
	_entity_root.name = "Entities"
	add_child(_entity_root)

func bind(state: Node) -> void:
	_state = state
	_dims = state.dims()
	if _dims.x <= 0 or _dims.y <= 0:
		return
	_build_terrain()

func world_rect_3d() -> AABB:
	var max_x: float = HEX_SIZE * 1.5 * _dims.x
	var max_z: float = HEX_SIZE * SQRT3 * _dims.y
	return AABB(Vector3.ZERO, Vector3(max_x, 3.0, max_z))

## Convert axial hex coords (q, r) to 3D world position (flat-top hex).
func hex_to_world(q: int, r: int) -> Vector3:
	var x: float = HEX_SIZE * 1.5 * q
	var z: float = HEX_SIZE * SQRT3 * (r + 0.5 * (q & 1))
	var elev: float = _get_hex_elevation(q, r)
	return Vector3(x, elev, z)

## Get hex center world position for entity placement.
func hex_center(q: int, r: int) -> Vector3:
	return hex_to_world(q, r)

func update_entities() -> void:
	if _state == null:
		return
	_update_npcs()
	_update_buildings()

# ─── Hex elevation ───────────────────────────────────────────────────
func _get_hex_elevation(q: int, r: int) -> float:
	if _state == null:
		return 0.0
	var biome: int = clampi(_state.tile_biome(q, r), 0, BIOME_BASE_ELEV.size() - 1)
	var raw_elev: int = _state.tile_elevation(q, r)
	return BIOME_BASE_ELEV[biome] + float(raw_elev) * ELEV_SCALE

# ─── Hex vertices (flat-top) ────────────────────────────────────────
func _hex_corner(center: Vector3, i: int) -> Vector3:
	var angle_deg: float = 60.0 * i
	var angle_rad: float = deg_to_rad(angle_deg)
	return Vector3(
		center.x + HEX_SIZE * cos(angle_rad),
		center.y,
		center.z + HEX_SIZE * sin(angle_rad)
	)

# ─── Terrain mesh generation ────────────────────────────────────────
func _build_terrain() -> void:
	print("[HexGrid] Building 3D terrain %d×%d..." % [_dims.x, _dims.y])

	# Load biome textures into an atlas texture or use individual materials
	var biome_materials: Array[StandardMaterial3D] = []
	for i in BIOME_TEXTURES.size():
		var mat := StandardMaterial3D.new()
		var tex := load(BIOME_TEXTURES[i]) as Texture2D
		mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		mat.vertex_color_use_as_albedo = false
		# No specular for pixel art look
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mat.roughness = 1.0
		biome_materials.append(mat)

	# Group hexes by biome to batch into fewer meshes
	var biome_verts: Array = []
	var biome_uvs: Array = []
	var biome_normals: Array = []
	for _i in BIOME_TEXTURES.size():
		biome_verts.append(PackedVector3Array())
		biome_uvs.append(PackedVector2Array())
		biome_normals.append(PackedVector3Array())

	# UV coordinates for hex: map hex shape to a square texture
	var uv_center := Vector2(0.5, 0.5)
	var uv_corners: Array[Vector2] = []
	for i in 6:
		var angle: float = deg_to_rad(60.0 * i)
		uv_corners.append(Vector2(0.5 + 0.5 * cos(angle), 0.5 + 0.5 * sin(angle)))

	for r in _dims.y:
		for q in _dims.x:
			var biome: int = clampi(_state.tile_biome(q, r), 0, BIOME_TEXTURES.size() - 1)
			var center: Vector3 = hex_to_world(q, r)
			var corners: Array[Vector3] = []
			for i in 6:
				corners.append(_hex_corner(center, i))

			var up := Vector3.UP
			# 6 triangles: center → corner[i] → corner[i+1]
			for i in 6:
				var next: int = (i + 1) % 6
				biome_verts[biome].append(center)
				biome_verts[biome].append(corners[i])
				biome_verts[biome].append(corners[next])
				biome_uvs[biome].append(uv_center)
				biome_uvs[biome].append(uv_corners[i])
				biome_uvs[biome].append(uv_corners[next])
				biome_normals[biome].append(up)
				biome_normals[biome].append(up)
				biome_normals[biome].append(up)

	# Create MeshInstance3D per biome
	for i in BIOME_TEXTURES.size():
		var verts: PackedVector3Array = biome_verts[i]
		if verts.size() == 0:
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = biome_normals[i]
		arr[Mesh.ARRAY_TEX_UV] = biome_uvs[i]

		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(0, biome_materials[i])

		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = "Biome_%d" % i
		add_child(mi)

	# Add water plane for ocean areas
	_add_water_plane()
	print("[HexGrid] Terrain built.")

func _add_water_plane() -> void:
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.15, 0.35, 0.65, 0.7)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	water_mat.roughness = 0.3
	water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var max_x: float = HEX_SIZE * 1.5 * _dims.x + HEX_SIZE
	var max_z: float = HEX_SIZE * SQRT3 * _dims.y + HEX_SIZE
	var plane := PlaneMesh.new()
	plane.size = Vector2(max_x * 1.2, max_z * 1.2)
	plane.material = water_mat

	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.name = "WaterPlane"
	mi.position = Vector3(max_x * 0.5, -0.15, max_z * 0.5)
	add_child(mi)

# ─── Entity rendering ───────────────────────────────────────────────
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

		var sprite: Sprite3D
		if _npc_sprites.has(npc.id):
			sprite = _npc_sprites[npc.id]
		else:
			sprite = Sprite3D.new()
			sprite.texture = _npc_texture
			sprite.hframes = 6
			sprite.pixel_size = 0.03
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			sprite.transparent = true
			sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			var civ_idx: int = clampi(int(npc.civ_id), 0, CIV_COLORS.size() - 1)
			sprite.modulate = CIV_COLORS[civ_idx]
			_entity_root.add_child(sprite)
			_npc_sprites[npc.id] = sprite

		var pos: Vector3 = hex_center(int(npc.x), int(npc.y))
		sprite.position = Vector3(pos.x, pos.y + 0.5, pos.z)

		if npc.is_child:
			sprite.pixel_size = 0.022
		else:
			sprite.pixel_size = 0.03

		var frame_idx: int = (Engine.get_frames_drawn() / 8 + int(npc.id)) % 6
		sprite.frame = frame_idx

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
		var sprite: Sprite3D

		if _building_sprites.has(bld.id):
			sprite = _building_sprites[bld.id]
		else:
			sprite = Sprite3D.new()
			sprite.texture = _building_texture
			sprite.pixel_size = 0.05
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			sprite.transparent = true
			sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			_entity_root.add_child(sprite)
			_building_sprites[bld.id] = sprite

		var pos: Vector3 = hex_center(int(bld.tile_x), int(bld.tile_y))
		sprite.position = Vector3(pos.x, pos.y + 0.4, pos.z)

		var stage: int = bld.stage
		if stage == 4:
			sprite.modulate = Color(1, 1, 1, 1)
			sprite.pixel_size = 0.05
		elif stage == 3:
			sprite.modulate = Color(0.9, 0.9, 0.9, 0.95)
			sprite.pixel_size = 0.045
		elif stage == 2:
			sprite.modulate = Color(0.7, 0.7, 0.7, 0.85)
			sprite.pixel_size = 0.04
		elif stage == 1:
			sprite.modulate = Color(0.6, 0.6, 0.5, 0.7)
			sprite.pixel_size = 0.03
		else:
			sprite.modulate = Color(0.5, 0.5, 0.4, 0.5)
			sprite.pixel_size = 0.02
