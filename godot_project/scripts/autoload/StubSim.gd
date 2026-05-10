extends Node
## GDScript stub replacing the Rust BabelSim for demo / testing.
##
## Generates a procedural world using FastNoiseLite and runs a minimal
## society loop entirely in GDScript so artists can preview assets
## without compiling the Rust backend.

# ── World parameters ─────────────────────────────────────────────────
const DEFAULT_MAP_W := 256
const DEFAULT_MAP_H := 256
const TICK_RATE := 6          # ticks per sim-day
const DAYS_PER_YEAR := 360

## 6 civ colour slots (more than the historical 4) so the new-game civ
## count slider can go up to 6 without rendering using out-of-range
## indices. HexGrid / WorldView read from this same palette.
const CIV_PALETTE: Array[Color] = [
	Color(1.00, 0.50, 0.50),  # red
	Color(0.50, 0.70, 1.00),  # blue
	Color(0.55, 1.00, 0.60),  # green
	Color(1.00, 0.90, 0.40),  # yellow
	Color(0.85, 0.55, 1.00),  # purple
	Color(1.00, 0.65, 0.30),  # orange
]

var map_w: int = DEFAULT_MAP_W
var map_h: int = DEFAULT_MAP_H

# ── Biome IDs (must match WorldView) ─────────────────────────────────
enum Biome { OCEAN, COAST, PLAINS, FOREST, HILLS, MOUNTAIN, DESERT, TUNDRA }

# ── Building stages ──────────────────────────────────────────────────
enum BuildStage { FOUNDATION, FRAME, WALLS, ROOF, COMPLETE }
## Cumulative wood required to clear each stage. progress_days (formerly
## a pure time counter) now mirrors wood_invested 1:1.
const STAGE_THRESHOLDS := [5, 12, 22, 30]
const BUILDING_TOTAL_WOOD := 30

# ── NPC age stages ───────────────────────────────────────────────────
enum AgeStage { CHILD, ADULT, ELDER }

# ── Trees ───────────────────────────────────────────────────────────────────
enum TreeStage { SAPLING, YOUNG, ADULT, STUMP, EMPTY }
## Days a tree spends in each stage before promoting to the next.
## ADULT entries don't auto-decay; they only leave that stage when
## chopped. EMPTY tiles are pruned and never re-enter the array.
const TREE_SAPLING_DAYS := 60
const TREE_YOUNG_DAYS := 90
const TREE_STUMP_DAYS := 30
const TREE_CHOP_DAYS := 5
const WOOD_PER_TREE := 10
const TREE_REGROWTH_RADIUS := 4

# ── NPC task FSM ────────────────────────────────────────────────────────────────
enum NpcTask { IDLE, GOTO_TREE, CHOPPING }
## A civ stops dispatching new choppers once its stockpile holds at
## least this much wood. Keeps the forest alive when it isn't needed.
const CIV_WOOD_TARGET := BUILDING_TOTAL_WOOD * 2
## How far a chopper will walk for a tree (Manhattan distance, tiles).
const CHOPPER_RANGE := 18

# ── Territory ───────────────────────────────────────────────────────────────────────────
## Tiles within this Manhattan distance of any of a civ's buildings are
## considered claimed by that civ. Conflicts are resolved by closest
## building.
const TERRITORY_RADIUS := 12
## Recompute interval (sim-days). Lower = snappier border updates, more
## CPU; 10 days is fine even on a 384² map.
const TERRITORY_RECOMPUTE_DAYS := 10

# ── Leadership ──────────────────────────────────────────────────────────────────────────
## Re-election interval. After this many sim-years the oldest living
## adult is re-evaluated; the same NPC may keep the post if still
## eldest. Death of the leader triggers an immediate re-election
## regardless of term length.
const LEADER_TERM_YEARS := 30

# ── Internal arrays ──────────────────────────────────────────────────
var _biomes: PackedByteArray
var _elevation: PackedByteArray
var _tags: PackedByteArray
var _seed_value: int = 0
var _ticks: int = 0
var _time_scale: int = 1

# ── NPC data ─────────────────────────────────────────────────────────
var npcs: Array[Dictionary] = []
var next_npc_id: int = 0

# ── Building data ────────────────────────────────────────────────────
var buildings: Array[Dictionary] = []
var next_building_id: int = 0

# ── Tree data ────────────────────────────────────────────────────────────────────
var trees: Array[Dictionary] = []
var next_tree_id: int = 0
## Tile (x,y) → index into [trees]. Lets _system_trees() check whether a
## given tile is already occupied without an O(n) scan, which matters
## once we have ~20k trees on a 256×256 forested map.
var _tree_at_tile: Dictionary = {}

# ── Territory ownership ────────────────────────────────────────────────────────────────
var _tile_owner: PackedInt32Array
## Bumped whenever territory is recomputed; HexGrid watches this to know
## when to rebuild the overlay meshes.
var _territory_version: int = 0

# ── Civilizations ────────────────────────────────────────────────────
## Each entry: { id, name, color, spawn_x, spawn_y }. Populated during
## [_spawn_initial_civs]. Exposed via [GameState.get_civs] for the menu /
## civ-select scene and for the in-game HUD.
var civs: Array[Dictionary] = []

## True once [start] has run for the current process. Lets the menu flow
## generate the world ahead of time and lets Main.tscn skip a redundant
## restart.
var world_started: bool = false

# ── Recent events for chronicle ──────────────────────────────────────
var _recent_events: Array[Dictionary] = []

# ── RNG ──────────────────────────────────────────────────────────────
var _rng := RandomNumberGenerator.new()

# ─────────────────────────────────────────────────────────────────────
func start(seed_val: int, w: int = DEFAULT_MAP_W, h: int = DEFAULT_MAP_H, civ_count: int = 4) -> bool:
	map_w = max(64, w)
	map_h = max(64, h)
	_seed_value = seed_val
	_rng.seed = seed_val
	npcs.clear()
	buildings.clear()
	civs.clear()
	trees.clear()
	_tree_at_tile.clear()
	next_npc_id = 0
	next_building_id = 0
	next_tree_id = 0
	_ticks = 0
	_biomes.resize(map_w * map_h)
	_elevation.resize(map_w * map_h)
	_tags.resize(map_w * map_h)
	_generate_world()
	_seed_initial_trees()
	_spawn_initial_civs(civ_count)
	_tile_owner = PackedInt32Array()
	_tile_owner.resize(map_w * map_h)
	for i in _tile_owner.size():
		_tile_owner[i] = -1
	_recompute_territory()
	world_started = true
	print(
		"[StubSim] World started. %dx%d, %d civs, NPCs: %d, Buildings: %d, Trees: %d"
		% [map_w, map_h, civs.size(), npcs.size(), buildings.size(), trees.size()]
	)
	return true

func dims() -> Vector2i:
	return Vector2i(map_w, map_h)

func tile_biome(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= map_w or y >= map_h:
		return 0
	return _biomes[y * map_w + x]

func tile_elevation(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= map_w or y >= map_h:
		return 0
	return _elevation[y * map_w + x]

func tile_tags(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= map_w or y >= map_h:
		return 0
	return _tags[y * map_w + x]

func get_civs() -> Array:
	return civs

func civ_color(civ_id: int) -> Color:
	if civ_id < 0 or civ_id >= civs.size():
		return Color(0.7, 0.7, 0.7)
	return civs[civ_id].color

func get_trees() -> Array[Dictionary]:
	return trees

func civ_wood(civ_id: int) -> int:
	if civ_id < 0 or civ_id >= civs.size():
		return 0
	return int(civs[civ_id].stockpile.wood)

## Civ that owns the tile at (x,y), or -1 if unclaimed / out of bounds.
func tile_owner(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= map_w or y >= map_h:
		return -1
	if _tile_owner.is_empty():
		return -1
	return _tile_owner[y * map_w + x]

## Monotonic counter that increments each time territory is recomputed.
## Renderers cache the last value they saw and rebuild only when it changes.
func territory_version() -> int:
	return _territory_version

func advance(frame_ticks: int) -> int:
	var total := frame_ticks * _time_scale
	for i in total:
		_ticks += 1
		# Run systems once per sim-day (every TICK_RATE ticks)
		if _ticks % TICK_RATE == 0:
			_tick_daily()
	return total

func set_time_scale(scale: int) -> bool:
	_time_scale = scale
	return true

func ticks() -> int:
	return _ticks

func year() -> int:
	return _ticks / (TICK_RATE * DAYS_PER_YEAR)

func day_of_year() -> int:
	return (_ticks / TICK_RATE) % DAYS_PER_YEAR

func hour() -> int:
	return (_ticks % TICK_RATE) * (24 / TICK_RATE)

func season() -> int:
	var doy := day_of_year()
	return clampi(doy / 90, 0, 3)

func get_npcs() -> Array[Dictionary]:
	return npcs

func get_buildings() -> Array[Dictionary]:
	return buildings

func recent_events() -> Array[Dictionary]:
	var evts := _recent_events.duplicate()
	_recent_events.clear()
	return evts

# ─────────────────────────────────────────────────────────────────────
# Save / Load
# ─────────────────────────────────────────────────────────────────────
const SAVE_FORMAT_VERSION := 1

## Snapshot the entire society loop state into a JSON-safe Dictionary.
## Inverse: [load_from_dict]. Pass-through is in [SaveManager], not in
## GameState — this keeps the save format owned by the data layer.
##
## PackedByteArrays are emitted as base64 strings so the save file stays
## reasonably small (~85 KB for a 256² map vs. ~400 KB if we wrote raw
## arrays of ints). PackedInt32Array uses the same trick via
## [_int32_array_to_b64].
##
## Civ Dictionaries get a shallow copy so we can replace [color] with an
## RGBA array (JSON has no Color type). NPC / building / tree dicts are
## already plain primitives and round-trip directly.
func to_save_dict() -> Dictionary:
	return {
		"version": SAVE_FORMAT_VERSION,
		"map_w": map_w,
		"map_h": map_h,
		"seed_value": _seed_value,
		"ticks": _ticks,
		"time_scale": _time_scale,
		"rng_state": int(_rng.state),
		"world_started": world_started,
		"biomes_b64": Marshalls.raw_to_base64(_biomes),
		"elevation_b64": Marshalls.raw_to_base64(_elevation),
		"tags_b64": Marshalls.raw_to_base64(_tags),
		"tile_owner_b64": _int32_array_to_b64(_tile_owner),
		"territory_version": _territory_version,
		"next_npc_id": next_npc_id,
		"next_building_id": next_building_id,
		"next_tree_id": next_tree_id,
		"npcs": npcs,
		"buildings": buildings,
		"trees": trees,
		"tree_at_tile": _tree_at_tile_to_save(),
		"civs": _civs_to_save(),
	}

## Replace the entire society loop state with [d]. Bails out (returning
## false) on a missing required key or a version we don't know how to
## migrate. Caller is expected to call this before any [advance] /
## [recent_events] consumption that frame so the simulation tick we
## resume from sees the loaded snapshot, not a stale one.
func load_from_dict(d: Dictionary) -> bool:
	if not d.has("version"):
		push_warning("[StubSim] save dict missing version")
		return false
	if int(d.version) != SAVE_FORMAT_VERSION:
		push_warning("[StubSim] save format v%d not supported (need v%d)" % [int(d.version), SAVE_FORMAT_VERSION])
		return false
	map_w = int(d.map_w)
	map_h = int(d.map_h)
	_seed_value = int(d.seed_value)
	_ticks = int(d.ticks)
	_time_scale = int(d.time_scale)
	_rng.seed = _seed_value
	if d.has("rng_state"):
		_rng.state = int(d.rng_state)
	world_started = bool(d.world_started)
	_biomes = Marshalls.base64_to_raw(String(d.biomes_b64))
	_elevation = Marshalls.base64_to_raw(String(d.elevation_b64))
	_tags = Marshalls.base64_to_raw(String(d.tags_b64))
	_tile_owner = _b64_to_int32_array(String(d.tile_owner_b64))
	_territory_version = int(d.territory_version)
	next_npc_id = int(d.next_npc_id)
	next_building_id = int(d.next_building_id)
	next_tree_id = int(d.next_tree_id)
	npcs = _array_of_dicts(d.npcs)
	buildings = _array_of_dicts(d.buildings)
	trees = _array_of_dicts(d.trees)
	_tree_at_tile = _tree_at_tile_from_save(d.tree_at_tile)
	civs = _civs_from_save(d.civs)
	_recent_events.clear()
	return true

func _civs_to_save() -> Array:
	var out: Array = []
	for c in civs:
		var copy: Dictionary = c.duplicate(true)
		var col: Color = c.color if c.has("color") else Color.WHITE
		copy["color"] = [col.r, col.g, col.b, col.a]
		out.append(copy)
	return out

func _civs_from_save(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var copy: Dictionary = (entry as Dictionary).duplicate(true)
		var col_data: Variant = copy.get("color", null)
		if typeof(col_data) == TYPE_ARRAY and (col_data as Array).size() == 4:
			var arr: Array = col_data
			copy["color"] = Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
		else:
			copy["color"] = Color.WHITE
		out.append(copy)
	return out

func _array_of_dicts(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry in raw:
		if typeof(entry) == TYPE_DICTIONARY:
			out.append((entry as Dictionary).duplicate(true))
	return out

## Dictionary{int → int} round-trips through JSON as Dictionary{String →
## int} (JSON object keys are always strings). Convert both ways here so
## the rest of the sim can keep using ints.
func _tree_at_tile_to_save() -> Dictionary:
	var out: Dictionary = {}
	for k in _tree_at_tile.keys():
		out[str(int(k))] = int(_tree_at_tile[k])
	return out

func _tree_at_tile_from_save(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for k in (raw as Dictionary).keys():
		out[int(String(k))] = int((raw as Dictionary)[k])
	return out

func _int32_array_to_b64(arr: PackedInt32Array) -> String:
	if arr.is_empty():
		return ""
	var pba := PackedByteArray()
	pba.resize(arr.size() * 4)
	for i in arr.size():
		pba.encode_s32(i * 4, arr[i])
	return Marshalls.raw_to_base64(pba)

func _b64_to_int32_array(s: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	if s.is_empty():
		return out
	var pba := Marshalls.base64_to_raw(s)
	if pba.size() % 4 != 0:
		push_warning("[StubSim] tile_owner blob has unaligned length %d" % pba.size())
		return out
	out.resize(pba.size() / 4)
	for i in out.size():
		out[i] = pba.decode_s32(i * 4)
	return out

# ─────────────────────────────────────────────────────────────────────
# World generation
# ─────────────────────────────────────────────────────────────────────
func _generate_world() -> void:
	var noise_elev := FastNoiseLite.new()
	noise_elev.seed = _seed_value
	noise_elev.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_elev.frequency = 0.012
	noise_elev.fractal_octaves = 5

	var noise_temp := FastNoiseLite.new()
	noise_temp.seed = _seed_value + 1000
	noise_temp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_temp.frequency = 0.008
	noise_temp.fractal_octaves = 3

	var noise_moist := FastNoiseLite.new()
	noise_moist.seed = _seed_value + 2000
	noise_moist.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_moist.frequency = 0.010
	noise_moist.fractal_octaves = 3

	for y in map_h:
		for x in map_w:
			var idx := y * map_w + x
			# Island shape — softer fade so the playable land takes up more of
			# the map and the ocean is a thin border instead of half the world.
			var dx := (float(x) / map_w - 0.5) * 2.0
			var dy := (float(y) / map_h - 0.5) * 2.0
			var dist := sqrt(dx * dx + dy * dy)
			var e := (noise_elev.get_noise_2d(x, y) + 1.0) * 0.5
			e -= dist * 0.4
			e = clampf(e, 0.0, 1.0)
			_elevation[idx] = int(e * 255.0)

			var moist := (noise_moist.get_noise_2d(x, y) + 1.0) * 0.5
			# noise_temp is no longer sampled now that the temperature-driven
			# biomes (TUNDRA, DESERT) are removed; the seed offset is kept
			# above so re-introducing temperature later doesn't shift seeds.

			# Six-biome world: OCEAN (thin border), MOUNTAIN, FOREST, HILLS,
			# PLAINS. COAST/DESERT/TUNDRA enum slots are kept for save-compat
			# but never produced.
			var biome: int
			if e < 0.18:
				biome = Biome.OCEAN
			elif e > 0.80:
				biome = Biome.MOUNTAIN
			elif moist > 0.55:
				biome = Biome.FOREST
			elif e > 0.55:
				biome = Biome.HILLS
			else:
				biome = Biome.PLAINS
			_biomes[idx] = biome
			_tags[idx] = 0

func _is_walkable(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= map_w or y >= map_h:
		return false
	var b := tile_biome(x, y)
	# OCEAN and MOUNTAIN are non-walkable; legacy COAST tiles (kept in the
	# enum for save-compat but never generated) are treated as walkable
	# plains-equivalents.
	return b != Biome.OCEAN and b != Biome.MOUNTAIN

func _tile_occupied_by_building(x: int, y: int) -> bool:
	for b in buildings:
		if b.tile_x == x and b.tile_y == y:
			return true
		if b.tile_x + 1 == x and b.tile_y == y:
			return true
		if b.tile_x == x and b.tile_y + 1 == y:
			return true
		if b.tile_x + 1 == x and b.tile_y + 1 == y:
			return true
	return false

# ─────────────────────────────────────────────────────────────────────
# Initial spawning
# ─────────────────────────────────────────────────────────────────────
func _spawn_initial_civs(civ_count: int) -> void:
	var count: int = clampi(civ_count, 1, CIV_PALETTE.size())
	var spawn_points: Array[Vector2i] = _find_spawn_points(count)
	for civ_id in spawn_points.size():
		var center := spawn_points[civ_id]
		civs.append({
			"id": civ_id,
			"name": _generate_civ_name(civ_id),
			"color": CIV_PALETTE[civ_id],
			"spawn_x": center.x,
			"spawn_y": center.y,
			"stockpile": {"wood": BUILDING_TOTAL_WOOD},
			"leader_id": -1,
			"leader_term_started_day": 0,
		})
		# Place 2 starter houses
		for _h in 2:
			var hx := center.x + _rng.randi_range(-4, 4)
			var hy := center.y + _rng.randi_range(-4, 4)
			hx = clampi(hx, 2, map_w - 3)
			hy = clampi(hy, 2, map_h - 3)
			if _is_walkable(hx, hy) and not _tile_occupied_by_building(hx, hy):
				_place_building(hx, hy, civ_id, true)
		# Spawn 12 NPCs near center
		for _n in 12:
			var nx := center.x + _rng.randi_range(-6, 6)
			var ny := center.y + _rng.randi_range(-6, 6)
			nx = clampi(nx, 1, map_w - 2)
			ny = clampi(ny, 1, map_h - 2)
			if _is_walkable(nx, ny):
				_spawn_npc(nx, ny, civ_id, _rng.randi_range(16, 40))

func _find_spawn_points(count: int) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var attempts := 0
	var margin: int = mini(20, mini(map_w, map_h) / 4)
	var min_dist: int = maxi(15, mini(map_w, map_h) / 8)
	while points.size() < count and attempts < 2000:
		attempts += 1
		var x := _rng.randi_range(margin, map_w - margin)
		var y := _rng.randi_range(margin, map_h - margin)
		if not _is_walkable(x, y):
			continue
		var b := tile_biome(x, y)
		if b == Biome.DESERT or b == Biome.TUNDRA:
			continue
		var too_close := false
		for p in points:
			if p.distance_to(Vector2i(x, y)) < min_dist:
				too_close = true
				break
		if not too_close:
			points.append(Vector2i(x, y))
	return points

## Procedural civ name. Simple consonant/vowel pattern; will be replaced
## by the babel_lang Markov generator once it is wired into GDScript.
func _generate_civ_name(civ_id: int) -> String:
	const CONS := ["k", "t", "r", "n", "s", "m", "l", "v", "d", "th", "sh", "y"]
	const VOW := ["a", "e", "i", "o", "u", "a", "e", "i"]
	# Stable per civ_id + seed so the same world always names civs the same way.
	var local := RandomNumberGenerator.new()
	local.seed = _seed_value ^ (civ_id * 0x9E3779B9)
	var syllables: int = local.randi_range(2, 3)
	var s := ""
	for i in syllables:
		s += CONS[local.randi() % CONS.size()]
		s += VOW[local.randi() % VOW.size()]
	return s.capitalize()

## Procedural NPC name, derived deterministically from npc_id + world
## seed. Used for the leader-portrait label and hover tooltips. Stable
## for the lifetime of the world: same npc_id always yields the same
## name. Cheap enough to compute on demand — no per-NPC storage.
func npc_name(npc_id: int) -> String:
	const CONS := ["k", "t", "r", "n", "s", "m", "l", "v", "d", "h", "sh"]
	const VOW := ["a", "e", "i", "o", "u"]
	var local := RandomNumberGenerator.new()
	local.seed = _seed_value ^ (npc_id * 0xCC9E2D51)
	var syllables: int = local.randi_range(2, 3)
	var s := ""
	for i in syllables:
		s += CONS[local.randi() % CONS.size()]
		s += VOW[local.randi() % VOW.size()]
	return s.capitalize()

func _spawn_npc(x: int, y: int, civ_id: int, age_years: int) -> int:
	var id := next_npc_id
	next_npc_id += 1
	var npc := {
		"id": id,
		"x": x,
		"y": y,
		"fx": float(x),
		"fy": float(y),
		"civ_id": civ_id,
		"age_days": age_years * DAYS_PER_YEAR,
		"partner_id": -1,
		"home_id": -1,
		"alive": true,
		"gestation_days": -1,
		"last_birth_day": -99999,
		"move_timer": _rng.randi_range(0, 5),
		"target_x": x,
		"target_y": y,
		"is_child": age_years < 14,
		"task": NpcTask.IDLE,
		"task_target_id": -1,
		"task_progress": 0,
	}
	npcs.append(npc)
	return id

func _place_building(x: int, y: int, civ_id: int, instant: bool = false) -> int:
	var id := next_building_id
	next_building_id += 1
	var b := {
		"id": id,
		"tile_x": x,
		"tile_y": y,
		"civ_id": civ_id,
		"stage": BuildStage.COMPLETE if instant else BuildStage.FOUNDATION,
		"progress_days": BUILDING_TOTAL_WOOD if instant else 0,
		"wood_invested": BUILDING_TOTAL_WOOD if instant else 0,
		"builder_ids": [],
		"owner_pair": [-1, -1],
	}
	buildings.append(b)
	_recent_events.append({"type": "building_founded", "x": x, "y": y, "civ_id": civ_id})
	return id

# ─────────────────────────────────────────────────────────────────────
# Daily tick systems
# ─────────────────────────────────────────────────────────────────────
func _tick_daily() -> void:
	_system_aging()
	_system_npc_tasks()
	_system_movement()
	_system_pairing()
	_system_gestation()
	_system_trees()
	_system_construction()
	_system_building_request()
	_system_leadership()
	if _current_sim_day() % TERRITORY_RECOMPUTE_DAYS == 0:
		_recompute_territory()

func _current_sim_day() -> int:
	return _ticks / TICK_RATE

## Public accessor for the absolute sim-day count. Used by the HUD to
## compute things like \"years in power since leader_term_started_day\".
func current_sim_day() -> int:
	return _current_sim_day()

func _npc_age_years(npc: Dictionary) -> int:
	return npc.age_days / DAYS_PER_YEAR

func _system_aging() -> void:
	for npc in npcs:
		if not npc.alive:
			continue
		npc.age_days += 1
		var age_y := _npc_age_years(npc)
		npc.is_child = age_y < 14
		# Death check yearly
		if npc.age_days % DAYS_PER_YEAR == 0 and age_y > 40:
			var chance := 0.02 * pow(float(age_y - 40), 1.5) / 50.0
			if _rng.randf() < chance:
				npc.alive = false
				_recent_events.append({"type": "death", "id": npc.id, "age": age_y})
				# Free partner
				if npc.partner_id >= 0:
					var partner = _find_npc(npc.partner_id)
					if partner != null:
						partner.partner_id = -1

func _system_movement() -> void:
	for npc in npcs:
		if not npc.alive:
			continue
		if int(npc.task) == NpcTask.CHOPPING:
			continue   # chopper stands still while felling
		if int(npc.task) != NpcTask.GOTO_TREE:
			npc.move_timer -= 1
			if npc.move_timer <= 0:
				npc.move_timer = _rng.randi_range(2, 8)
				var radius: int = 3 if npc.is_child else 5
				var tx: int = int(npc.x) + _rng.randi_range(-radius, radius)
				var ty: int = int(npc.y) + _rng.randi_range(-radius, radius)
				tx = clampi(tx, 1, map_w - 2)
				ty = clampi(ty, 1, map_h - 2)
				if _is_walkable(tx, ty):
					npc.target_x = tx
					npc.target_y = ty
		# Move toward target (idle wander or task target)
		if npc.x != npc.target_x or npc.y != npc.target_y:
			var dx: int = signi(int(npc.target_x) - int(npc.x))
			var dy: int = signi(int(npc.target_y) - int(npc.y))
			var new_x: int = int(npc.x) + dx
			var new_y: int = int(npc.y) + dy
			if _is_walkable(new_x, new_y):
				npc.x = new_x
				npc.y = new_y

func _system_pairing() -> void:
	for npc in npcs:
		if not npc.alive or npc.is_child:
			continue
		if npc.partner_id >= 0:
			continue
		var age_y: int = _npc_age_years(npc)
		if age_y < 14 or age_y > 50:
			continue
		# Search radius 6 for another single adult of same civ
		for other in npcs:
			if other.id == npc.id or not other.alive or other.is_child:
				continue
			if other.partner_id >= 0 or other.civ_id != npc.civ_id:
				continue
			var other_age: int = _npc_age_years(other)
			if other_age < 14 or other_age > 50:
				continue
			var dist: int = absi(int(npc.x) - int(other.x)) + absi(int(npc.y) - int(other.y))
			if dist <= 6:
				if _rng.randf() < 0.10:
					npc.partner_id = other.id
					other.partner_id = npc.id
					_recent_events.append({
						"type": "marriage",
						"npc1": npc.id,
						"npc2": other.id,
						"civ_id": npc.civ_id
					})
				break

func _system_gestation() -> void:
	for npc in npcs:
		if not npc.alive or npc.partner_id < 0:
			continue
		var partner = _find_npc(npc.partner_id)
		if partner == null or not partner.alive:
			continue
		# Start gestation
		if npc.gestation_days < 0 and partner.gestation_days < 0:
			var age_y := _npc_age_years(npc)
			if age_y < 14 or age_y > 50:
				continue
			var day := _current_sim_day()
			if day - npc.last_birth_day < 2 * DAYS_PER_YEAR:
				continue
			var dist: int = absi(int(npc.x) - int(partner.x)) + absi(int(npc.y) - int(partner.y))
			if dist > 6:
				continue
			if _rng.randf() < 0.05:
				npc.gestation_days = 0
		# Progress gestation
		elif npc.gestation_days >= 0:
			npc.gestation_days += 1
			if npc.gestation_days >= 9:
				# Birth!
				npc.gestation_days = -1
				npc.last_birth_day = _current_sim_day()
				var child_id := _spawn_npc(npc.x, npc.y, npc.civ_id, 0)
				var child = _find_npc(child_id)
				if child != null:
					child.home_id = npc.home_id
				_recent_events.append({
					"type": "birth",
					"parent1": npc.id,
					"parent2": npc.partner_id,
					"child": child_id,
					"civ_id": npc.civ_id
				})

func _system_construction() -> void:
	for b in buildings:
		if b.stage == BuildStage.COMPLETE:
			continue
		var builder_count := 0
		for bid in b.builder_ids:
			var builder = _find_npc(bid)
			if builder != null and builder.alive:
				builder_count += 1
		if builder_count == 0:
			builder_count = 1   # at least one ghost builder
		# Wood-gated progress: a building only advances if its civ has wood
		# left to spend. Each unit of wood = one day of progress, capped by
		# the number of available builders (parallel labour).
		var civ_id: int = int(b.civ_id)
		if civ_id < 0 or civ_id >= civs.size():
			continue
		var stockpile: Dictionary = civs[civ_id].stockpile
		var need: int = BUILDING_TOTAL_WOOD - int(b.wood_invested)
		var transfer: int = mini(builder_count, mini(need, int(stockpile.wood)))
		if transfer <= 0:
			continue
		stockpile.wood = int(stockpile.wood) - transfer
		var prev_stage: int = int(b.stage)
		b.wood_invested = int(b.wood_invested) + transfer
		b.progress_days = int(b.wood_invested)
		if b.progress_days >= STAGE_THRESHOLDS[3]:
			if b.stage != BuildStage.COMPLETE:
				b.stage = BuildStage.COMPLETE
				_recent_events.append({"type": "building_complete", "id": int(b.id), "x": int(b.tile_x), "y": int(b.tile_y), "civ_id": civ_id})
		elif b.progress_days >= STAGE_THRESHOLDS[2]:
			b.stage = BuildStage.ROOF
		elif b.progress_days >= STAGE_THRESHOLDS[1]:
			b.stage = BuildStage.WALLS
		elif b.progress_days >= STAGE_THRESHOLDS[0]:
			b.stage = BuildStage.FRAME
		if int(b.stage) != prev_stage and int(b.stage) != BuildStage.COMPLETE:
			_recent_events.append({"type": "building_progress", "id": int(b.id), "x": int(b.tile_x), "y": int(b.tile_y), "stage": int(b.stage), "civ_id": civ_id})

func _system_building_request() -> void:
	# Every 5 days, unhomed pairs try to build
	if _current_sim_day() % 5 != 0:
		return
	for npc in npcs:
		if not npc.alive or npc.partner_id < 0 or npc.home_id >= 0:
			continue
		var partner = _find_npc(npc.partner_id)
		if partner == null or not partner.alive:
			continue
		if partner.home_id >= 0:
			continue
		# Find build location
		var cx: int = int(npc.x + partner.x) / 2
		var cy: int = int(npc.y + partner.y) / 2
		var best_x: int = -1
		var best_y: int = -1
		var best_dist: int = 999
		for _attempt in 8:
			var tx: int = cx + _rng.randi_range(-12, 12)
			var ty: int = cy + _rng.randi_range(-12, 12)
			tx = clampi(tx, 2, map_w - 3)
			ty = clampi(ty, 2, map_h - 3)
			if not _is_walkable(tx, ty):
				continue
			if _tile_occupied_by_building(tx, ty):
				continue
			# Check min 5 tiles from other buildings
			var too_close := false
			for b in buildings:
				if abs(b.tile_x - tx) < 5 and abs(b.tile_y - ty) < 5:
					too_close = true
					break
			if too_close:
				continue
			var d: int = absi(tx - cx) + absi(ty - cy)
			if d < best_dist:
				best_dist = d
				best_x = tx
				best_y = ty
		if best_x >= 0:
			var bid := _place_building(best_x, best_y, npc.civ_id, false)
			npc.home_id = bid
			partner.home_id = bid
			# Assign builders
			buildings[buildings.size() - 1].builder_ids = [npc.id, partner.id]
			buildings[buildings.size() - 1].owner_pair = [npc.id, partner.id]

# ─────────────────────────────────────────────────────────────────────
# Territory
# ─────────────────────────────────────────────────────────────────────
## Recompute the per-tile civ ownership map. A tile is owned by the civ
## whose nearest building is within [TERRITORY_RADIUS] tiles (Manhattan).
## Ties broken by lower civ_id for determinism.
##
## This is O(map_w * map_h * num_buildings); on a 256² map with a few
## dozen buildings that's ~2M ops per recompute, called every
## [TERRITORY_RECOMPUTE_DAYS] sim-days.
func _recompute_territory() -> void:
	if _tile_owner.is_empty():
		return
	var n: int = map_w * map_h
	for i in n:
		_tile_owner[i] = -1
	if buildings.is_empty():
		_territory_version += 1
		return
	# Reusable best-distance map; smaller = closer.
	var best_dist := PackedInt32Array()
	best_dist.resize(n)
	var sentinel: int = TERRITORY_RADIUS + 1
	for i in n:
		best_dist[i] = sentinel
	for b in buildings:
		var bx: int = int(b.tile_x)
		var by: int = int(b.tile_y)
		var civ_id: int = int(b.civ_id)
		var x0: int = maxi(0, bx - TERRITORY_RADIUS)
		var x1: int = mini(map_w - 1, bx + TERRITORY_RADIUS)
		var y0: int = maxi(0, by - TERRITORY_RADIUS)
		var y1: int = mini(map_h - 1, by + TERRITORY_RADIUS)
		for ty in range(y0, y1 + 1):
			var dy: int = absi(ty - by)
			for tx in range(x0, x1 + 1):
				var d: int = dy + absi(tx - bx)
				if d > TERRITORY_RADIUS:
					continue
				var idx: int = ty * map_w + tx
				if d < best_dist[idx] or (d == best_dist[idx] and civ_id < _tile_owner[idx]):
					best_dist[idx] = d
					_tile_owner[idx] = civ_id
	_territory_version += 1

# ─────────────────────────────────────────────────────────────────────
# Tree systems
# ─────────────────────────────────────────────────────────────────────
func _tree_key(x: int, y: int) -> int:
	return y * map_w + x

func _seed_initial_trees() -> void:
	# One tree per qualifying tile, with biome-dependent density.
	# Forest tiles get a tree most of the time, hills sometimes, plains
	# rarely. Trees start ADULT so the world doesn't read as bald on
	# day 1, and so chopping is meaningful right away.
	for ty in map_h:
		for tx in map_w:
			var biome: int = tile_biome(tx, ty)
			var chance: float
			match biome:
				Biome.FOREST: chance = 0.55
				Biome.HILLS:  chance = 0.18
				Biome.PLAINS: chance = 0.06
				_: chance = 0.0
			if chance == 0.0 or _rng.randf() > chance:
				continue
			_spawn_tree(tx, ty, TreeStage.ADULT)

func _spawn_tree(x: int, y: int, stage: int) -> int:
	if _tree_at_tile.has(_tree_key(x, y)):
		return -1
	var id := next_tree_id
	next_tree_id += 1
	var t := {
		"id": id,
		"x": x,
		"y": y,
		"stage": stage,
		"age_in_stage": 0,
		"chop_progress": 0,
		"chopper_id": -1,
	}
	trees.append(t)
	_tree_at_tile[_tree_key(x, y)] = id
	return id

func _find_tree(id: int):
	for t in trees:
		if t.id == id:
			return t
	return null

func _has_adult_neighbour(x: int, y: int, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var key: int = _tree_key(x + dx, y + dy)
			if not _tree_at_tile.has(key):
				continue
			var tid: int = int(_tree_at_tile[key])
			var t = _find_tree(tid)
			if t != null and int(t.stage) == TreeStage.ADULT:
				return true
	return false

func _system_trees() -> void:
	var to_remove: Array[int] = []
	for t in trees:
		t.age_in_stage += 1
		match int(t.stage):
			TreeStage.SAPLING:
				if int(t.age_in_stage) >= TREE_SAPLING_DAYS:
					t.stage = TreeStage.YOUNG
					t.age_in_stage = 0
			TreeStage.YOUNG:
				if int(t.age_in_stage) >= TREE_YOUNG_DAYS:
					t.stage = TreeStage.ADULT
					t.age_in_stage = 0
			TreeStage.STUMP:
				if int(t.age_in_stage) >= TREE_STUMP_DAYS:
					if _has_adult_neighbour(int(t.x), int(t.y), TREE_REGROWTH_RADIUS):
						t.stage = TreeStage.SAPLING
						t.age_in_stage = 0
					else:
						# No seed source nearby - mark for removal so the
						# tile becomes available again.
						to_remove.append(int(t.id))
			_: pass
	if not to_remove.is_empty():
		_prune_trees(to_remove)

func _prune_trees(ids: Array[int]) -> void:
	var lookup: Dictionary = {}
	for id in ids:
		lookup[id] = true
	var kept: Array[Dictionary] = []
	for t in trees:
		if lookup.has(int(t.id)):
			_tree_at_tile.erase(_tree_key(int(t.x), int(t.y)))
			continue
		kept.append(t)
	trees = kept

# ─────────────────────────────────────────────────────────────────────
# NPC task FSM
# ─────────────────────────────────────────────────────────────────────
func _can_assign_chopping(npc: Dictionary) -> bool:
	if not npc.alive or npc.is_child:
		return false
	if int(npc.task) != NpcTask.IDLE:
		return false
	if int(npc.gestation_days) >= 0:
		return false
	# A pregnant or already-housed-but-incomplete builder we leave alone
	# only if their building is still under construction.
	if int(npc.home_id) >= 0:
		for b in buildings:
			if int(b.id) == int(npc.home_id) and int(b.stage) != BuildStage.COMPLETE:
				return false
	return true

func _find_nearest_adult_tree(from_x: int, from_y: int, max_dist: int) -> int:
	var best_id: int = -1
	var best_d: int = max_dist + 1
	for t in trees:
		if int(t.stage) != TreeStage.ADULT:
			continue
		if int(t.chopper_id) >= 0:
			continue
		var d: int = absi(int(t.x) - from_x) + absi(int(t.y) - from_y)
		if d < best_d:
			best_d = d
			best_id = int(t.id)
	return best_id

func _system_npc_tasks() -> void:
	# 1) For each civ that needs wood, dispatch idle adults toward the
	#    nearest unreserved adult tree.
	for civ in civs:
		var civ_id: int = int(civ.id)
		var stockpile: Dictionary = civ.stockpile
		if int(stockpile.wood) >= CIV_WOOD_TARGET:
			continue
		for npc in npcs:
			if int(npc.civ_id) != civ_id:
				continue
			if not _can_assign_chopping(npc):
				continue
			var tid: int = _find_nearest_adult_tree(int(npc.x), int(npc.y), CHOPPER_RANGE)
			if tid < 0:
				continue
			var t = _find_tree(tid)
			if t == null:
				continue
			t.chopper_id = int(npc.id)
			npc.task = NpcTask.GOTO_TREE
			npc.task_target_id = tid
			npc.task_progress = 0
			npc.target_x = int(t.x)
			npc.target_y = int(t.y)
	# 2) Advance each task in flight.
	for npc in npcs:
		if not npc.alive:
			continue
		var task: int = int(npc.task)
		if task == NpcTask.IDLE:
			continue
		var t = _find_tree(int(npc.task_target_id))
		if t == null or int(t.stage) != TreeStage.ADULT:
			# Tree disappeared (chopped by someone else, removed, etc.) —
			# release the chopper without crediting wood.
			_release_chopper(npc)
			continue
		# Keep walking: target may have shifted, e.g. tree was moved (it
		# can't be, but defensive).
		npc.target_x = int(t.x)
		npc.target_y = int(t.y)
		var dist: int = absi(int(npc.x) - int(t.x)) + absi(int(npc.y) - int(t.y))
		if task == NpcTask.GOTO_TREE:
			if dist <= 1:
				npc.task = NpcTask.CHOPPING
				npc.task_progress = 0
		elif task == NpcTask.CHOPPING:
			if dist > 1:
				# Got displaced — restart approach.
				npc.task = NpcTask.GOTO_TREE
				continue
			npc.task_progress = int(npc.task_progress) + 1
			if int(npc.task_progress) >= TREE_CHOP_DAYS:
				_complete_chopping(npc, t)

func _complete_chopping(npc: Dictionary, t: Dictionary) -> void:
	t.stage = TreeStage.STUMP
	t.age_in_stage = 0
	t.chopper_id = -1
	var civ_id: int = int(npc.civ_id)
	if civ_id >= 0 and civ_id < civs.size():
		civs[civ_id].stockpile.wood = int(civs[civ_id].stockpile.wood) + WOOD_PER_TREE
	_recent_events.append({
		"type": "tree_chopped",
		"civ_id": civ_id,
		"npc_id": int(npc.id),
		"tree_id": int(t.id),
		"x": int(t.x),
		"y": int(t.y),
	})
	npc.task = NpcTask.IDLE
	npc.task_target_id = -1
	npc.task_progress = 0

func _release_chopper(npc: Dictionary) -> void:
	npc.task = NpcTask.IDLE
	npc.task_target_id = -1
	npc.task_progress = 0

func _find_npc(id: int):
	for npc in npcs:
		if npc.id == id:
			return npc
	return null

## Public lookup by NPC id. Returns the Dictionary entry from [npcs] or
## an empty Dictionary if no live NPC has that id. Used by the HUD /
## hover code to read leader stats without needing to scan the array.
func find_npc(id: int) -> Dictionary:
	var npc = _find_npc(id)
	return npc if npc != null else {}

# ──────────────────────────────────────────────────────────────────────
# Leadership
# ──────────────────────────────────────────────────────────────────────
## Re-evaluate every civ's leader once per sim-day. Selection rule
## (V0): the oldest living adult of the civ wins. Death of the leader
## triggers an immediate re-election; otherwise the post is renewed
## every [LEADER_TERM_YEARS] sim-years.
##
## A civ has no leader until it owns at least one COMPLETE building —
## leadership is a society construct, not a default. Once a civ loses
## all adults, [civ.leader_id] reverts to -1 and the seat stays empty
## until a new adult comes of age.
func _system_leadership() -> void:
	var today: int = _current_sim_day()
	var term_days: int = LEADER_TERM_YEARS * DAYS_PER_YEAR
	for civ in civs:
		var civ_id: int = int(civ.id)
		if not _civ_has_completed_building(civ_id):
			continue
		var current_id: int = int(civ.leader_id)
		var current_npc = _find_npc(current_id) if current_id >= 0 else null
		var leader_alive: bool = current_npc != null and bool(current_npc.alive) and not bool(current_npc.is_child)
		var term_started: int = int(civ.leader_term_started_day)
		var term_expired: bool = leader_alive and (today - term_started) >= term_days
		if leader_alive and not term_expired:
			continue
		var best_id: int = _oldest_adult_of_civ(civ_id)
		if best_id < 0:
			# No eligible adult: vacate the seat. Will be refilled when a
			# child grows up or an adult migrates in.
			if not leader_alive and current_id >= 0:
				civ.leader_id = -1
			continue
		if best_id != current_id:
			var event_type: String = "leader_chosen" if not leader_alive else "leader_changed"
			civ.leader_id = best_id
			civ.leader_term_started_day = today
			_recent_events.append({
				"type": event_type,
				"civ_id": civ_id,
				"leader_id": best_id,
				"previous_id": current_id,
			})
		elif term_expired:
			# Same elder still tops the list — simply renew the term.
			civ.leader_term_started_day = today
			_recent_events.append({
				"type": "leader_reelected",
				"civ_id": civ_id,
				"leader_id": best_id,
			})

func _civ_has_completed_building(civ_id: int) -> bool:
	for b in buildings:
		if int(b.civ_id) == civ_id and int(b.stage) == BuildStage.COMPLETE:
			return true
	return false

func _oldest_adult_of_civ(civ_id: int) -> int:
	var best_id: int = -1
	var best_age: int = -1
	for npc in npcs:
		if not bool(npc.alive) or bool(npc.is_child):
			continue
		if int(npc.civ_id) != civ_id:
			continue
		var age_y: int = _npc_age_years(npc)
		if age_y > best_age:
			best_age = age_y
			best_id = int(npc.id)
	return best_id

## Current leader of [civ_id], or -1 if the seat is empty (or the civ
## doesn't exist).
func civ_leader_id(civ_id: int) -> int:
	if civ_id < 0 or civ_id >= civs.size():
		return -1
	return int(civs[civ_id].leader_id)

## Sim-day on which the current leader's term began. Used by the HUD to
## display “N years in power”. Meaningless when [civ_leader_id] is -1.
func civ_leader_term_started_day(civ_id: int) -> int:
	if civ_id < 0 or civ_id >= civs.size():
		return 0
	return int(civs[civ_id].leader_term_started_day)

func civ_population(civ_id: int) -> int:
	var n: int = 0
	for npc in npcs:
		if bool(npc.alive) and int(npc.civ_id) == civ_id:
			n += 1
	return n

func civ_buildings_count(civ_id: int) -> int:
	var n: int = 0
	for b in buildings:
		if int(b.civ_id) == civ_id and int(b.stage) == BuildStage.COMPLETE:
			n += 1
	return n

func civ_territory_tile_count(civ_id: int) -> int:
	if _tile_owner.is_empty():
		return 0
	var n: int = 0
	for i in _tile_owner.size():
		if _tile_owner[i] == civ_id:
			n += 1
	return n

func total_owned_tile_count() -> int:
	if _tile_owner.is_empty():
		return 0
	var n: int = 0
	for i in _tile_owner.size():
		if _tile_owner[i] >= 0:
			n += 1
	return n
