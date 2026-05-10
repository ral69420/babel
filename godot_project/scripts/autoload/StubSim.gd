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
const STAGE_THRESHOLDS := [5, 12, 22, 30]

# ── NPC age stages ───────────────────────────────────────────────────
enum AgeStage { CHILD, ADULT, ELDER }

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
	next_npc_id = 0
	next_building_id = 0
	_ticks = 0
	_biomes.resize(map_w * map_h)
	_elevation.resize(map_w * map_h)
	_tags.resize(map_w * map_h)
	_generate_world()
	_spawn_initial_civs(civ_count)
	world_started = true
	print(
		"[StubSim] World started. %dx%d, %d civs, NPCs: %d, Buildings: %d"
		% [map_w, map_h, civs.size(), npcs.size(), buildings.size()]
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
			# Island shape — fade to ocean at edges
			var dx := (float(x) / map_w - 0.5) * 2.0
			var dy := (float(y) / map_h - 0.5) * 2.0
			var dist := sqrt(dx * dx + dy * dy)
			var e := (noise_elev.get_noise_2d(x, y) + 1.0) * 0.5
			e -= dist * 0.7
			e = clampf(e, 0.0, 1.0)
			_elevation[idx] = int(e * 255.0)

			var temp := (noise_temp.get_noise_2d(x, y) + 1.0) * 0.5
			var moist := (noise_moist.get_noise_2d(x, y) + 1.0) * 0.5

			var biome: int
			if e < 0.25:
				biome = Biome.OCEAN
			elif e < 0.30:
				biome = Biome.COAST
			elif e > 0.80:
				biome = Biome.MOUNTAIN
			elif temp < 0.25:
				biome = Biome.TUNDRA
			elif temp > 0.70 and moist < 0.35:
				biome = Biome.DESERT
			elif moist > 0.55:
				biome = Biome.FOREST
			elif e > 0.60:
				biome = Biome.HILLS
			else:
				biome = Biome.PLAINS
			_biomes[idx] = biome
			_tags[idx] = 0

func _is_walkable(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= map_w or y >= map_h:
		return false
	var b := tile_biome(x, y)
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
		"progress_days": 30 if instant else 0,
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
	_system_movement()
	_system_pairing()
	_system_gestation()
	_system_construction()
	_system_building_request()

func _current_sim_day() -> int:
	return _ticks / TICK_RATE

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
		npc.move_timer -= 1
		if npc.move_timer <= 0:
			npc.move_timer = _rng.randi_range(2, 8)
			# Pick new target within radius
			var radius: int = 3 if npc.is_child else 5
			var tx: int = int(npc.x) + _rng.randi_range(-radius, radius)
			var ty: int = int(npc.y) + _rng.randi_range(-radius, radius)
			tx = clampi(tx, 1, map_w - 2)
			ty = clampi(ty, 1, map_h - 2)
			if _is_walkable(tx, ty):
				npc.target_x = tx
				npc.target_y = ty
		# Move toward target
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
			builder_count = 1  # At least slow progress
		b.progress_days += builder_count
		# Update stage
		if b.progress_days >= STAGE_THRESHOLDS[3]:
			b.stage = BuildStage.COMPLETE
			_recent_events.append({"type": "building_complete", "id": b.id})
		elif b.progress_days >= STAGE_THRESHOLDS[2]:
			b.stage = BuildStage.ROOF
		elif b.progress_days >= STAGE_THRESHOLDS[1]:
			b.stage = BuildStage.WALLS
		elif b.progress_days >= STAGE_THRESHOLDS[0]:
			b.stage = BuildStage.FRAME

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

func _find_npc(id: int):
	for npc in npcs:
		if npc.id == id:
			return npc
	return null
