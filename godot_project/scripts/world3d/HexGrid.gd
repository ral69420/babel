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
const GROUND_BIAS := 0.02       ## Tiny lift to avoid z-fighting with terrain.

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
	-0.4,   # Ocean
	-0.02,  # Coast
	0.0,    # Plains
	0.08,   # Forest
	0.3,    # Hills
	0.8,    # Mountain
	0.03,   # Desert
	0.1,    # Tundra
]

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
var _smooth_elev: PackedFloat32Array

# Territory overlay
var _territory_root: Node3D
var _territory_visible: bool = true
var _last_territory_version: int = -1
const TERRITORY_Y_OFFSET := 0.06
const TERRITORY_INTERIOR_ALPHA := 0.22
const TERRITORY_BORDER_ALPHA := 0.65

func _ready() -> void:
	_npc_texture = load("res://assets/npcs/default/walk_south.png") as Texture2D
	_building_texture = load("res://assets/buildings/default/house.png") as Texture2D
	_tree_texture = load("res://assets/decorations/tree_pine/tree_pine.png") as Texture2D
	_entity_root = Node3D.new()
	_entity_root.name = "Entities"
	add_child(_entity_root)
	_territory_root = Node3D.new()
	_territory_root.name = "Territory"
	add_child(_territory_root)

func bind(state: Node) -> void:
	_state = state
	_dims = state.dims()
	if _dims.x <= 0 or _dims.y <= 0:
		return
	_precompute_smooth_elevation()
	_build_terrain()

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
	_maybe_rebuild_territory()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		if k.keycode == KEY_T:
			_territory_visible = not _territory_visible
			if _territory_root:
				_territory_root.visible = _territory_visible

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
const TREE_BASE_PIXEL := 0.024
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
			sprite.pixel_size = 0.021
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
			sprite.pixel_size = 0.015
		else:
			sprite.pixel_size = 0.021

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

		# Update pixel_size + modulate first (stage-dependent),
		# then anchor so the sprite bottom rests on the terrain.
		var stage: int = bld.stage
		if stage == 4:
			sprite.modulate = Color(1, 1, 1, 1)
			sprite.pixel_size = 0.035
		elif stage == 3:
			sprite.modulate = Color(0.9, 0.9, 0.9, 0.95)
			sprite.pixel_size = 0.032
		elif stage == 2:
			sprite.modulate = Color(0.7, 0.7, 0.7, 0.85)
			sprite.pixel_size = 0.028
		elif stage == 1:
			sprite.modulate = Color(0.6, 0.6, 0.5, 0.7)
			sprite.pixel_size = 0.021
		else:
			sprite.modulate = Color(0.5, 0.5, 0.4, 0.5)
			sprite.pixel_size = 0.014

		var pos: Vector3 = hex_center(int(bld.tile_x), int(bld.tile_y))
		sprite.position = Vector3(pos.x, _ground_anchor_y(pos.y, HOUSE_TEX_H, sprite.pixel_size), pos.z)

# ─── Territory overlay ──────────────────────────────────────────────────────
## Compares the sim's [territory_version] against our last cached value.
## Only does a full mesh rebuild when the sim has actually recomputed
## ownership (typically every TERRITORY_RECOMPUTE_DAYS sim-days).
func _maybe_rebuild_territory() -> void:
	if not _state.has_method("territory_version"):
		return
	var v: int = int(_state.territory_version())
	if v == _last_territory_version:
		return
	_last_territory_version = v
	_rebuild_territory()

## Border-detection helper. A tile is on the border of its civ's
## territory if any of its hex neighbours is owned by a different civ
## (or unowned, or off-map).
func _is_border_for(q: int, r: int, civ_id: int) -> bool:
	var nb := _hex_neighbors(q, r)
	for n in nb:
		if n.x < 0 or n.y < 0 or n.x >= _dims.x or n.y >= _dims.y:
			return true
		if int(_state.tile_owner(n.x, n.y)) != civ_id:
			return true
	return false

func _make_overlay_material(rgb: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(rgb.r, rgb.g, rgb.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Keep default depth-draw (opaque-only) so trees / NPCs drawn over
	# the overlay still depth-test correctly, and the overlay itself
	# doesn't occlude what's above it.
	return m

func _rebuild_territory() -> void:
	if _territory_root == null or _state == null:
		return
	for c in _territory_root.get_children():
		c.queue_free()

	var civs_arr: Array = _state.get_civs()
	if civs_arr.is_empty():
		return

	# Collect per-civ tile lists in a single map pass, splitting into
	# border vs interior up front so the per-civ mesh build is linear.
	var civ_count: int = civs_arr.size()
	var interior_tiles: Array = []
	var border_tiles: Array = []
	for _i in civ_count:
		interior_tiles.append([])
		border_tiles.append([])

	for r in _dims.y:
		for q in _dims.x:
			var owner: int = int(_state.tile_owner(q, r))
			if owner < 0 or owner >= civ_count:
				continue
			if _is_border_for(q, r, owner):
				(border_tiles[owner] as Array).append(Vector2i(q, r))
			else:
				(interior_tiles[owner] as Array).append(Vector2i(q, r))

	for civ_id in civ_count:
		var civ: Dictionary = civs_arr[civ_id]
		var col: Color = civ.color
		var iv := _build_overlay_verts(interior_tiles[civ_id])
		if iv.size() > 0:
			_territory_root.add_child(_make_overlay_instance(
				iv, _make_overlay_material(col, TERRITORY_INTERIOR_ALPHA),
				"Civ%d_Interior" % civ_id,
			))
		var bv := _build_overlay_verts(border_tiles[civ_id])
		if bv.size() > 0:
			_territory_root.add_child(_make_overlay_instance(
				bv, _make_overlay_material(col, TERRITORY_BORDER_ALPHA),
				"Civ%d_Border" % civ_id,
			))
	_territory_root.visible = _territory_visible

func _build_overlay_verts(tiles: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(tiles.size() * 18)   # 6 fan triangles × 3 verts per tile
	var i: int = 0
	for t in tiles:
		var coords: Vector2i = t
		var center: Vector3 = hex_center(coords.x, coords.y)
		center.y += TERRITORY_Y_OFFSET
		var corners: Array[Vector3] = []
		for k in 6:
			var c: Vector3 = _hex_corner_smooth(coords.x, coords.y, hex_center(coords.x, coords.y), k)
			c.y += TERRITORY_Y_OFFSET
			corners.append(c)
		for k in 6:
			var nxt: int = (k + 1) % 6
			out[i] = center
			i += 1
			out[i] = corners[k]
			i += 1
			out[i] = corners[nxt]
			i += 1
	return out

func _make_overlay_instance(verts: PackedVector3Array, mat: Material, mesh_name: String) -> MeshInstance3D:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	# Flat overlay → all normals up; lets unshaded material short-circuit
	# but fills the array so the shader doesn't complain.
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in verts.size():
		normals[i] = Vector3.UP
	arr[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = mesh_name
	return mi
