extends Node3D
## Generates a 3D hex-tile terrain mesh with smooth realistic elevation.
##
## Uses flat-top hexagons in offset coordinates (q, r).
## Terrain has smooth elevation transitions using neighbor averaging.
## Billboard sprites (buildings, trees, NPCs) are bottom-anchored to the
## terrain so they don't sink into the mesh or appear to float at the same Y.

const HEX_SIZE := 1.0
const SQRT3 := 1.7320508
const ELEV_SCALE := 0.025       ## More pronounced elevation.

## Texture heights (px) used to anchor billboard sprites to the ground.
## With Sprite3D's default centered = true, position.y is the sprite
## centre, so we offset by half_height_world to put the bottom edge on
## the terrain instead of burying half the sprite underground.
const HOUSE_TEX_H := 64.0
const TREE_TEX_H := 64.0
const NPC_TEX_FRAME_H := 48.0
const GRASS_TEX_H := 128.0
const GROUND_BIAS := 0.02       ## Tiny lift to avoid z-fighting with terrain.

## Visual scale for entities. Heights are world units (~1.0 = a hex radius).
## NPC adult height ≈ 0.336 → tree adult height = 3 × NPC = 1.008 →
## house complete height ≈ tree height (slightly taller for civic builds).
const NPC_PIXEL_ADULT := 0.007
const NPC_PIXEL_CHILD := 0.005

## Biome enum is preserved for save-compat (StubSim.Biome). After the
## Phase 0.5 world-tweaks pass, world generation never produces COAST,
## DESERT or TUNDRA — those slots fall back to plains art so legacy
## indexing keeps working.
const BIOME_TEXTURES := [
	"res://assets/tiles/ocean/ocean.png",
	"res://assets/tiles/plains/plains.png",  # was coast — now plains fallback
	"res://assets/tiles/plains/plains.png",
	"res://assets/tiles/forest/forest.png",
	"res://assets/tiles/hills/hills.png",
	"res://assets/tiles/mountain/mountain.png",
	"res://assets/tiles/plains/plains.png",  # was desert — now plains fallback
	"res://assets/tiles/plains/plains.png",  # was tundra — now plains fallback
]

const BIOME_BASE_ELEV := [
	-0.4,   # Ocean
	0.0,    # (legacy Coast slot) → plains elevation
	0.0,    # Plains
	0.08,   # Forest
	0.3,    # Hills
	0.8,    # Mountain
	0.0,    # (legacy Desert slot) → plains elevation
	0.0,    # (legacy Tundra slot) → plains elevation
]

## Decoration density per biome (used by the grass MultiMesh).
const GRASS_DENSITY_PER_BIOME := {
	2: 4,   # Plains  — ~4 tufts/tile
	3: 5,   # Forest  — ~5 tufts/tile (forest floor)
	4: 2,   # Hills   — ~2 tufts/tile
}

## Fallback civ colour palette used when [GameState.get_civs] is empty
## (e.g. running directly from Main.tscn without going through the menu).
## Must contain at least as many entries as the new-game civ-count slider
## allows (currently 6).
const CIV_COLORS := [
	Color(1.00, 0.50, 0.50),
	Color(0.50, 0.70, 1.00),
	Color(0.55, 1.00, 0.60),
	Color(1.00, 0.90, 0.40),
	Color(0.85, 0.55, 1.00),
	Color(1.00, 0.65, 0.30),
]

var _state: Node = null
var _dims: Vector2i = Vector2i.ZERO
var _entity_root: Node3D
var _npc_sprites: Dictionary = {}
var _building_sprites: Dictionary = {}
var _tree_sprites: Dictionary = {}   # tree_id (int) → Node3D
var _npc_texture: Texture2D
var _building_texture: Texture2D
var _tree_texture: Texture2D
var _grass_texture: Texture2D
var _vegetation_shader: Shader
var _tree_wind_material: ShaderMaterial
var _grass_wind_material: ShaderMaterial
var _grass_multimesh: MultiMeshInstance3D
var _leaves_particles: GPUParticles3D
var _smooth_elev: PackedFloat32Array

func _ready() -> void:
	_npc_texture = load("res://assets/npcs/default/walk_south.png") as Texture2D
	_building_texture = load("res://assets/buildings/default/house.png") as Texture2D
	_tree_texture = load("res://assets/decorations/tree_pine/tree_pine.png") as Texture2D
	_grass_texture = load("res://assets/decorations/grass/grass.png") as Texture2D
	_vegetation_shader = load("res://shaders/vegetation_wind.gdshader") as Shader
	_tree_wind_material = _make_wind_material(_tree_texture, 0.04, 0.7, 0.4)
	_grass_wind_material = _make_wind_material(_grass_texture, 0.02, 1.4, 1.1)
	_entity_root = Node3D.new()
	_entity_root.name = "Entities"
	add_child(_entity_root)

## Build a single ShaderMaterial that all instances of a given foliage
## kind share — keeps draw calls + state changes minimal. Per-plant
## variation comes from world position inside the shader.
func _make_wind_material(
	tex: Texture2D,
	strength: float,
	speed: float,
	jitter: float,
) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _vegetation_shader
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("tint", Color.WHITE)
	mat.set_shader_parameter("wind_strength", strength)
	mat.set_shader_parameter("wind_speed", speed)
	mat.set_shader_parameter("wind_jitter", jitter)
	mat.set_shader_parameter("alpha_cutoff", 0.5)
	return mat

func bind(state: Node) -> void:
	_state = state
	_dims = state.dims()
	if _dims.x <= 0 or _dims.y <= 0:
		return
	_precompute_smooth_elevation()
	_build_terrain()
	_build_grass_multimesh()
	_spawn_leaves_particles()
	_spawn_fireflies_particles()

func world_rect_3d() -> AABB:
	var max_x: float = HEX_SIZE * 1.5 * _dims.x
	var max_z: float = HEX_SIZE * SQRT3 * _dims.y
	return AABB(Vector3.ZERO, Vector3(max_x, 4.0, max_z))

func hex_to_world(q: int, r: int) -> Vector3:
	var x: float = HEX_SIZE * 1.5 * q
	var z: float = HEX_SIZE * SQRT3 * (r + 0.5 * (q & 1))
	var elev: float = _get_smooth_elevation(q, r)
	return Vector3(x, elev, z)

func hex_center(q: int, r: int) -> Vector3:
	return hex_to_world(q, r)

func update_entities() -> void:
	if _state == null:
		return
	_update_npcs()
	_update_buildings()
	_update_trees()

# ─── Smooth elevation ────────────────────────────────────────────────
func _precompute_smooth_elevation() -> void:
	# First pass: raw elevation per tile
	var raw := PackedFloat32Array()
	raw.resize(_dims.x * _dims.y)
	for r in _dims.y:
		for q in _dims.x:
			var biome: int = clampi(_state.tile_biome(q, r), 0, BIOME_BASE_ELEV.size() - 1)
			var raw_elev: int = _state.tile_elevation(q, r)
			raw[r * _dims.x + q] = BIOME_BASE_ELEV[biome] + float(raw_elev) * ELEV_SCALE

	# Multi-pass smooth for very gentle terrain transitions
	_smooth_elev = PackedFloat32Array()
	_smooth_elev.resize(_dims.x * _dims.y)
	for pass_i in 4:
		var src: PackedFloat32Array = raw if pass_i == 0 else _smooth_elev.duplicate()
		for r in _dims.y:
			for q in _dims.x:
				var total: float = src[r * _dims.x + q] * 4.0
				var weight: float = 4.0
				# Sample 6 hex neighbors
				var neighbors := _hex_neighbors(q, r)
				for n in neighbors:
					if n.x >= 0 and n.x < _dims.x and n.y >= 0 and n.y < _dims.y:
						total += src[n.y * _dims.x + n.x]
						weight += 1.0
				_smooth_elev[r * _dims.x + q] = total / weight

func _hex_neighbors(q: int, r: int) -> Array[Vector2i]:
	var parity: int = q & 1
	if parity == 0:
		return [
			Vector2i(q+1, r), Vector2i(q+1, r-1),
			Vector2i(q, r-1), Vector2i(q-1, r-1),
			Vector2i(q-1, r), Vector2i(q, r+1),
		]
	else:
		return [
			Vector2i(q+1, r+1), Vector2i(q+1, r),
			Vector2i(q, r-1), Vector2i(q-1, r),
			Vector2i(q-1, r+1), Vector2i(q, r+1),
		]

func _get_smooth_elevation(q: int, r: int) -> float:
	if q < 0 or r < 0 or q >= _dims.x or r >= _dims.y:
		return -0.8
	return _smooth_elev[r * _dims.x + q]

## Returns the Y position that places the *bottom* of a centered Sprite3D
## flush with the terrain at the given hex centre, plus a small bias.
func _ground_anchor_y(ground_y: float, tex_h_px: float, pixel_size_world: float) -> float:
	return ground_y + tex_h_px * pixel_size_world * 0.5 + GROUND_BIAS

const HEX_CORNER_SCALE := 1.06  ## Overlap to close gaps between hexes.

func _hex_corner_smooth(center_q: int, center_r: int, center_pos: Vector3, i: int) -> Vector3:
	var angle_deg: float = 60.0 * i
	var angle_rad: float = deg_to_rad(angle_deg)
	var corner_x: float = center_pos.x + HEX_SIZE * HEX_CORNER_SCALE * cos(angle_rad)
	var corner_z: float = center_pos.z + HEX_SIZE * HEX_CORNER_SCALE * sin(angle_rad)
	# Average elevation between center and adjacent hex for smooth edges
	var adj := _hex_neighbors(center_q, center_r)
	var corner_y: float = center_pos.y
	# Blend with the two adjacent hexes that share this corner
	var n1_idx: int = i % 6
	var n2_idx: int = (i + 5) % 6
	if n1_idx < adj.size() and n2_idx < adj.size():
		var n1: Vector2i = adj[n1_idx]
		var n2: Vector2i = adj[n2_idx]
		var e1: float = _get_smooth_elevation(n1.x, n1.y)
		var e2: float = _get_smooth_elevation(n2.x, n2.y)
		corner_y = (center_pos.y + e1 + e2) / 3.0
	return Vector3(corner_x, corner_y, corner_z)

# ─── Terrain mesh generation ────────────────────────────────────────
func _build_terrain() -> void:
	print("[HexGrid] Building 3D terrain %d×%d..." % [_dims.x, _dims.y])

	var biome_materials: Array[StandardMaterial3D] = []
	for i in BIOME_TEXTURES.size():
		var mat := StandardMaterial3D.new()
		var tex := load(BIOME_TEXTURES[i]) as Texture2D
		mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.vertex_color_use_as_albedo = false
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mat.roughness = 1.0
		biome_materials.append(mat)

	var biome_verts: Array = []
	var biome_uvs: Array = []
	var biome_normals: Array = []
	for _i in BIOME_TEXTURES.size():
		biome_verts.append(PackedVector3Array())
		biome_uvs.append(PackedVector2Array())
		biome_normals.append(PackedVector3Array())

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
				corners.append(_hex_corner_smooth(q, r, center, i))

			for i in 6:
				var next: int = (i + 1) % 6
				var v0: Vector3 = center
				var v1: Vector3 = corners[i]
				var v2: Vector3 = corners[next]
				# Compute proper face normal
				var edge1: Vector3 = v1 - v0
				var edge2: Vector3 = v2 - v0
				var normal: Vector3 = edge1.cross(edge2).normalized()
				if normal.y < 0:
					normal = -normal

				biome_verts[biome].append(v0)
				biome_verts[biome].append(v1)
				biome_verts[biome].append(v2)
				biome_uvs[biome].append(uv_center)
				biome_uvs[biome].append(uv_corners[i])
				biome_uvs[biome].append(uv_corners[next])
				biome_normals[biome].append(normal)
				biome_normals[biome].append(normal)
				biome_normals[biome].append(normal)

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

	_add_water_plane()
	print("[HexGrid] Terrain built.")

func _add_water_plane() -> void:
	var max_x: float = HEX_SIZE * 1.5 * _dims.x + HEX_SIZE
	var max_z: float = HEX_SIZE * SQRT3 * _dims.y + HEX_SIZE

	# Ground plane: fills gaps between hex tiles with terrain-like color
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.45, 0.55, 0.30, 1.0)
	ground_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	ground_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	ground_mat.roughness = 1.0
	ground_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var ground_plane := PlaneMesh.new()
	ground_plane.size = Vector2(max_x * 1.2, max_z * 1.2)
	ground_plane.material = ground_mat

	var ground_mi := MeshInstance3D.new()
	ground_mi.mesh = ground_plane
	ground_mi.name = "GroundPlane"
	ground_mi.position = Vector3(max_x * 0.5, -0.5, max_z * 0.5)
	add_child(ground_mi)

	# Water plane: only visible in deep ocean areas
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.10, 0.28, 0.52, 1.0)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	water_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	water_mat.roughness = 0.3
	water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var water_plane := PlaneMesh.new()
	water_plane.size = Vector2(max_x * 1.2, max_z * 1.2)
	water_plane.material = water_mat

	var water_mi := MeshInstance3D.new()
	water_mi.mesh = water_plane
	water_mi.name = "WaterPlane"
	water_mi.position = Vector3(max_x * 0.5, -0.45, max_z * 0.5)
	add_child(water_mi)

## Pixel-size used for an ADULT tree. Younger stages scale down off this.
## Adult tree height = TREE_BASE_PIXEL × TREE_TEX_H = 0.01575 × 64 ≈ 1.008,
## i.e. exactly 3 × adult-NPC height (0.336). Buildings match this height
## by default; civic buildings (added later) can scale up off it.
const TREE_BASE_PIXEL := 0.01575
## Cosmetic only — yaw + tile offsets are derived deterministically from
## the tile coords so the same tree always looks the same.
func _tree_jitter(tx: int, ty: int) -> Vector3:
	# 16 × 16 pseudo-random table baked from tile coords.
	var a: float = float((tx * 73856093) ^ (ty * 19349663))
	var b: float = float((tx * 83492791) ^ (ty * 12289))
	var yaw: float = fposmod(a * 0.0001, TAU)
	var ox: float = (fposmod(b * 0.0001, 1.0) - 0.5) * HEX_SIZE * 0.6
	var oz: float = (fposmod(a * 0.00013, 1.0) - 0.5) * HEX_SIZE * 0.6
	return Vector3(ox, yaw, oz)

func _scale_for_tree_stage(stage: int) -> float:
	# StubSim.TreeStage: 0=SAPLING 1=YOUNG 2=ADULT 3=STUMP 4=EMPTY
	match stage:
		0: return 0.35
		1: return 0.65
		2: return 1.0
		3: return 0.25
		_: return 0.0

func _modulate_for_tree_stage(stage: int) -> Color:
	match stage:
		0: return Color(0.85, 1.10, 0.85)   # bright sapling
		1: return Color(0.95, 1.05, 0.95)
		2: return Color.WHITE
		3: return Color(0.45, 0.32, 0.22)   # brown stump
		_: return Color.WHITE

func _spawn_tree_node(pos: Vector3, jitter: Vector3, base_pixel: float) -> Node3D:
	var root := Node3D.new()
	var y := _ground_anchor_y(pos.y, TREE_TEX_H, base_pixel)
	root.position = Vector3(pos.x + jitter.x, y, pos.z + jitter.z)
	root.rotation.y = jitter.y
	for i in 2:
		var quad := Sprite3D.new()
		quad.texture = _tree_texture
		quad.pixel_size = base_pixel
		quad.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		quad.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		quad.transparent = true
		quad.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		quad.double_sided = true
		quad.rotation.y = i * (PI * 0.5)
		# Single shared ShaderMaterial across all tree quads → one draw
		# call per tree pass, plus per-tree wind variance derived from
		# world position inside the shader (no per-instance uniforms).
		if _tree_wind_material:
			quad.material_override = _tree_wind_material
		root.add_child(quad)
	return root

func _update_trees() -> void:
	if not _tree_texture:
		return
	var tree_list: Array = _state.get_trees()
	var active_ids: Dictionary = {}
	for t in tree_list:
		var tid: int = int(t.id)
		var stage: int = int(t.stage)
		var scale_factor: float = _scale_for_tree_stage(stage)
		if scale_factor <= 0.0:
			continue   # EMPTY — don't render
		active_ids[tid] = true
		var tx: int = int(t.x)
		var ty: int = int(t.y)
		var pos: Vector3 = hex_center(tx, ty)
		var jitter: Vector3 = _tree_jitter(tx, ty)
		var pixel_size: float = TREE_BASE_PIXEL * scale_factor
		var root: Node3D = _tree_sprites.get(tid, null) as Node3D
		if root == null:
			root = _spawn_tree_node(pos, jitter, pixel_size)
			_entity_root.add_child(root)
			_tree_sprites[tid] = root
		else:
			# Stage may have changed (e.g. SAPLING→YOUNG, ADULT→STUMP).
			# Just re-anchor and re-scale on every refresh — cheap.
			root.position = Vector3(
				pos.x + jitter.x,
				_ground_anchor_y(pos.y, TREE_TEX_H, pixel_size),
				pos.z + jitter.z,
			)
		# Update each quad's pixel_size + tint to reflect the current stage.
		var tint: Color = _modulate_for_tree_stage(stage)
		for child in root.get_children():
			if child is Sprite3D:
				var s: Sprite3D = child
				s.pixel_size = pixel_size
				s.modulate = tint
	# Drop any sprites whose tree disappeared (regrowth-failure pruning).
	var to_drop: Array[int] = []
	for key in _tree_sprites.keys():
		if not active_ids.has(int(key)):
			to_drop.append(int(key))
	for key in to_drop:
		var n: Node = _tree_sprites[key]
		if is_instance_valid(n):
			n.queue_free()
		_tree_sprites.erase(key)

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
			sprite.pixel_size = NPC_PIXEL_ADULT
			sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			sprite.transparent = true
			sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			var civ_idx: int = clampi(int(npc.civ_id), 0, CIV_COLORS.size() - 1)
			sprite.modulate = CIV_COLORS[civ_idx]
			_entity_root.add_child(sprite)
			_npc_sprites[npc.id] = sprite

		# Set pixel_size first so anchoring uses the correct half-height.
		if npc.is_child:
			sprite.pixel_size = NPC_PIXEL_CHILD
		else:
			sprite.pixel_size = NPC_PIXEL_ADULT

		var pos: Vector3 = hex_center(int(npc.x), int(npc.y))
		sprite.position = Vector3(pos.x, _ground_anchor_y(pos.y, NPC_TEX_FRAME_H, sprite.pixel_size), pos.z)

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
			sprite.pixel_size = 0.035
			sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			sprite.transparent = true
			sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			_entity_root.add_child(sprite)
			_building_sprites[bld.id] = sprite

		# Stage-driven scale + tint. Complete (stage 4) house matches the
		# adult-tree silhouette so towns and forests don't look mismatched.
		var stage: int = bld.stage
		var bld_complete_pixel: float = TREE_BASE_PIXEL
		if stage == 4:
			sprite.modulate = Color(1, 1, 1, 1)
			sprite.pixel_size = bld_complete_pixel
		elif stage == 3:
			sprite.modulate = Color(0.9, 0.9, 0.9, 0.95)
			sprite.pixel_size = bld_complete_pixel * 0.92
		elif stage == 2:
			sprite.modulate = Color(0.7, 0.7, 0.7, 0.85)
			sprite.pixel_size = bld_complete_pixel * 0.78
		elif stage == 1:
			sprite.modulate = Color(0.6, 0.6, 0.5, 0.7)
			sprite.pixel_size = bld_complete_pixel * 0.6
		else:
			sprite.modulate = Color(0.5, 0.5, 0.4, 0.5)
			sprite.pixel_size = bld_complete_pixel * 0.4

		var pos: Vector3 = hex_center(int(bld.tile_x), int(bld.tile_y))
		sprite.position = Vector3(pos.x, _ground_anchor_y(pos.y, HOUSE_TEX_H, sprite.pixel_size), pos.z)


# ─── Grass decoration (mega-optimised cross-billboard MultiMesh) ─────
#
# One MultiMeshInstance3D for the entire map: the per-instance "mesh"
# is itself a CROSS of two perpendicular quads (so each grass tuft
# looks 3-D from any orbit angle), and we bake all transforms once
# during world load. After bake the GPU just instances + applies the
# shared vegetation_wind shader — no per-frame script work, one draw
# call regardless of tuft count.
const GRASS_PIXEL := 0.005
const GRASS_QUAD_HALF_W := 0.32   ## Half-width of each cross quad (world units).
const GRASS_QUAD_HEIGHT := 0.64   ## Height of each cross quad (world units).
const GRASS_TILE_OFFSET_RADIUS := 0.55

## Build the X-shape (two perpendicular quads in one ArrayMesh) used as
## the per-instance mesh of the grass MultiMesh.
func _build_grass_cross_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var hw := GRASS_QUAD_HALF_W
	var h := GRASS_QUAD_HEIGHT

	# Two perpendicular quads (XY-plane and ZY-plane), both anchored at
	# y = 0 (root) growing up to y = h (top).
	var quad_axes: Array[Vector3] = [Vector3(1, 0, 0), Vector3(0, 0, 1)]
	for axis in quad_axes:
		var base_idx := verts.size()
		verts.append(Vector3(-hw * axis.x, 0.0, -hw * axis.z))
		verts.append(Vector3( hw * axis.x, 0.0,  hw * axis.z))
		verts.append(Vector3( hw * axis.x, h,    hw * axis.z))
		verts.append(Vector3(-hw * axis.x, h,   -hw * axis.z))
		# UV: V grows top→bottom of the texture (top of plant = V 0).
		uvs.append(Vector2(0.0, 1.0))
		uvs.append(Vector2(1.0, 1.0))
		uvs.append(Vector2(1.0, 0.0))
		uvs.append(Vector2(0.0, 0.0))
		# Normals point along the quad axis (so it shades like a
		# vertical card facing the perpendicular direction).
		var n := Vector3(axis.z, 0.0, axis.x)   # 90° rotation in XZ
		for _i in 4:
			normals.append(n)
		indices.append(base_idx + 0)
		indices.append(base_idx + 1)
		indices.append(base_idx + 2)
		indices.append(base_idx + 0)
		indices.append(base_idx + 2)
		indices.append(base_idx + 3)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Deterministic per-tile pseudo-random in [0, 1).
func _grass_hash(seed_a: int, seed_b: int, salt: int) -> float:
	var h: int = (seed_a * 73856093) ^ (seed_b * 19349663) ^ (salt * 83492791)
	# Fold to [0, 1).
	return fposmod(float(h) * 0.0001, 1.0)

func _build_grass_multimesh() -> void:
	if _grass_texture == null or _grass_wind_material == null:
		return

	# 1. Count instances first — biome-driven density.
	var instance_count: int = 0
	for r in _dims.y:
		for q in _dims.x:
			var biome: int = int(_state.tile_biome(q, r))
			if GRASS_DENSITY_PER_BIOME.has(biome):
				instance_count += int(GRASS_DENSITY_PER_BIOME[biome])
	if instance_count <= 0:
		print("[HexGrid] No grass instances to bake.")
		return

	# 2. Build the per-instance cross mesh + wire up the shared shader.
	var cross := _build_grass_cross_mesh()
	cross.surface_set_material(0, _grass_wind_material)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = cross
	mm.instance_count = instance_count

	# 3. Bake transforms (and a subtle per-tuft tint).
	var idx: int = 0
	var base_tint := Color(1.0, 1.0, 1.0, 1.0)
	for r in _dims.y:
		for q in _dims.x:
			var biome: int = int(_state.tile_biome(q, r))
			if not GRASS_DENSITY_PER_BIOME.has(biome):
				continue
			var density: int = int(GRASS_DENSITY_PER_BIOME[biome])
			var center: Vector3 = hex_to_world(q, r)
			for k in density:
				var rx: float = (_grass_hash(q, r, k * 2 + 0) - 0.5) \
					* GRASS_TILE_OFFSET_RADIUS * 2.0
				var rz: float = (_grass_hash(q, r, k * 2 + 1) - 0.5) \
					* GRASS_TILE_OFFSET_RADIUS * 2.0
				var yaw: float = _grass_hash(q, r, k + 311) * TAU
				var s: float = 0.7 + _grass_hash(q, r, k + 53) * 0.6  # 0.7..1.3
				var t := Transform3D()
				t.basis = Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
				t.origin = Vector3(
					center.x + rx,
					center.y + GROUND_BIAS,
					center.z + rz,
				)
				mm.set_instance_transform(idx, t)
				# Slight per-tuft hue jitter so the field isn't flat.
				var tint_v: float = 0.85 + _grass_hash(q, r, k + 97) * 0.30
				mm.set_instance_color(
					idx,
					base_tint * Color(tint_v, tint_v, tint_v, 1.0),
				)
				idx += 1

	# 4. Drop into the scene tree under a dedicated node so
	#    Phase 5's auto-camera and any future culling layer can find
	#    it by name.
	var prev: Node = get_node_or_null("GrassMultiMesh")
	if prev:
		prev.queue_free()
	_grass_multimesh = MultiMeshInstance3D.new()
	_grass_multimesh.name = "GrassMultiMesh"
	_grass_multimesh.multimesh = mm
	add_child(_grass_multimesh)
	print("[HexGrid] Grass MultiMesh: %d cross-billboard tufts, 1 draw call." % instance_count)


# ─── Falling leaves (single global GPUParticles3D) ───────────────────
#
# One particle system covers the whole world. Leaves spawn high above
# the canopy, fall slowly, drift on a soft horizontal wind. ~300
# concurrent particles total — visually "everywhere", measurably free.
func _spawn_leaves_particles() -> void:
	if _grass_texture == null:   # use grass green as a leaf stand-in
		return

	var rect: AABB = world_rect_3d()
	var canopy_y: float = TREE_BASE_PIXEL * TREE_TEX_H + 0.5

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(rect.size.x * 0.5, 0.01, rect.size.z * 0.5)
	pm.gravity = Vector3(0.0, -0.35, 0.0)
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.15
	# Very gentle horizontal drift so leaves don't fall straight down.
	pm.direction = Vector3(0.4, -1.0, 0.2)
	pm.spread = 25.0
	pm.angular_velocity_min = -45.0
	pm.angular_velocity_max =  45.0
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	pm.color = Color(0.85, 1.0, 0.7, 1.0)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.15, 0.15)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_texture = _grass_texture
	leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	leaf_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	leaf_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	leaf_mat.billboard_keep_scale = true
	leaf_mat.no_depth_test = false
	quad.material = leaf_mat

	var gp := GPUParticles3D.new()
	gp.name = "LeavesParticles"
	gp.amount = 300
	gp.lifetime = 8.0
	gp.preprocess = 4.0
	gp.fixed_fps = 30
	gp.process_material = pm
	gp.draw_pass_1 = quad
	gp.transform.origin = Vector3(
		rect.position.x + rect.size.x * 0.5,
		canopy_y,
		rect.position.z + rect.size.z * 0.5,
	)
	gp.visibility_aabb = AABB(
		Vector3(rect.position.x, -1.0, rect.position.z),
		Vector3(rect.size.x, canopy_y + 4.0, rect.size.z),
	)

	var prev: Node = get_node_or_null("LeavesParticles")
	if prev:
		prev.queue_free()
	_leaves_particles = gp
	add_child(gp)
	print("[HexGrid] Falling leaves particles spawned (1 GPUParticles3D, amount=%d)." % gp.amount)


# ─── Fireflies (single global GPUParticles3D, on at night only) ──────
#
# Like the falling leaves, this is one particle system covering the
# whole map. The TimeOfDay autoload toggles emission on/off when the
# phase enters/leaves PHASE_NIGHT, so we pay zero CPU during the day
# (zero spawns) and at most a few hundred small additive quads at
# night. Net cost is ~0.05 ms GPU on a mid-range card.
var _fireflies_particles: GPUParticles3D
const _FIREFLIES_AMOUNT_NIGHT := 500

func _spawn_fireflies_particles() -> void:
	var rect: AABB = world_rect_3d()

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(rect.size.x * 0.5, 0.6, rect.size.z * 0.5)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.15
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 180.0
	pm.angular_velocity_min = 0.0
	pm.angular_velocity_max = 0.0
	# Soft drift so they don't hold a perfect line.
	pm.linear_accel_min = -0.05
	pm.linear_accel_max = 0.05
	# Fade in/out via colour ramp so the additive blend doesn't pop.
	var ramp := Gradient.new()
	ramp.add_point(0.0, Color(0.95, 1.00, 0.55, 0.0))
	ramp.add_point(0.15, Color(0.95, 1.00, 0.55, 0.85))
	ramp.add_point(0.85, Color(0.95, 1.00, 0.55, 0.85))
	ramp.add_point(1.0, Color(0.95, 1.00, 0.55, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex

	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	leaf_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD   # glowing dot feel
	leaf_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	leaf_mat.billboard_keep_scale = true
	leaf_mat.albedo_color = Color(0.95, 1.0, 0.55, 1.0)
	leaf_mat.no_depth_test = false
	quad.material = leaf_mat

	var gp := GPUParticles3D.new()
	gp.name = "FirefliesParticles"
	gp.amount = _FIREFLIES_AMOUNT_NIGHT
	gp.lifetime = 6.0
	gp.preprocess = 2.0
	gp.fixed_fps = 30
	gp.emitting = false   # off until night phase fires the listener
	gp.process_material = pm
	gp.draw_pass_1 = quad
	gp.transform.origin = Vector3(
		rect.position.x + rect.size.x * 0.5,
		1.2,    # hover above ground
		rect.position.z + rect.size.z * 0.5,
	)
	gp.visibility_aabb = AABB(
		Vector3(rect.position.x, -1.0, rect.position.z),
		Vector3(rect.size.x, 5.0, rect.size.z),
	)

	var prev: Node = get_node_or_null("FirefliesParticles")
	if prev:
		prev.queue_free()
	_fireflies_particles = gp
	add_child(gp)

	# Wire up to the day/night cycle: emit only during the NIGHT phase.
	# TimeOfDay is registered as an autoload (project.godot), so the
	# global identifier always resolves at runtime.
	TimeOfDay.register_phase_listener(_on_phase_changed_fireflies)
	print("[HexGrid] Fireflies particle system spawned (off until night).")

func _on_phase_changed_fireflies(phase: String) -> void:
	if _fireflies_particles == null:
		return
	_fireflies_particles.emitting = (phase == TimeOfDay.PHASE_NIGHT)
