extends Node
## Singleton holding global game state.
##
## Uses BabelSim (Rust GDExtension) when available for CI compatibility.
## Always creates a StubSim overlay that provides the society loop
## (NPCs, buildings, aging, pairing, construction).

var sim = null
var sim_ready: bool = false
var _society: Node = null

func _ready() -> void:
	_init_sim()

func _init_sim() -> void:
	if ClassDB.class_exists("BabelSim"):
		sim = ClassDB.instantiate("BabelSim")
		sim_ready = true
		print("[GameState] BabelSim extension loaded.")
	else:
		push_warning("[GameState] BabelSim not found — using StubSim.")
		var FallbackScript := preload("res://scripts/autoload/StubSim.gd")
		var stub := FallbackScript.new()
		add_child(stub)
		sim = stub
		sim_ready = true

	var SocietyScript := preload("res://scripts/autoload/StubSim.gd")
	_society = SocietyScript.new()
	_society.name = "SocietyLoop"
	add_child(_society)

func start_world(seed_value: int, width: int, height: int, civ_count: int = 4) -> bool:
	if not sim_ready:
		return false
	var ok: bool = sim.start(seed_value, width, height)
	if _society and _society != sim:
		_society.start(seed_value, width, height, civ_count)
	return ok

## True once a world has been generated for the current process. Lets
## Main.tscn skip a redundant generation when the menu / new-game flow
## already produced one.
func world_ready() -> bool:
	if _society == null:
		return false
	var v: Variant = _society.get("world_started")
	return typeof(v) == TYPE_BOOL and v

## Mark the current world as discarded. Next call to [start_world] will
## re-generate. Used when the player backs out of CivSelect.
func clear_world() -> void:
	if _society:
		_society.set("world_started", false)

func advance(frame_ticks: int) -> int:
	if not sim_ready:
		return 0
	var result: int = sim.advance(frame_ticks)
	if _society and _society != sim:
		_society.advance(frame_ticks)
	return result

func set_time_scale(scale: int) -> bool:
	if not sim_ready:
		return false
	var ok: bool = sim.set_time_scale(scale)
	if _society and _society != sim:
		_society.set_time_scale(scale)
	return ok

func dims() -> Vector2i:
	if _society and _society.has_method("dims"):
		return _society.dims()
	if not sim_ready:
		return Vector2i.ZERO
	return sim.dims()

func tile_biome(x: int, y: int) -> int:
	if _society and _society.has_method("tile_biome"):
		return _society.tile_biome(x, y)
	if not sim_ready:
		return 255
	return sim.tile_biome(x, y)

func tile_elevation(x: int, y: int) -> int:
	if _society and _society.has_method("tile_elevation"):
		return _society.tile_elevation(x, y)
	if not sim_ready:
		return 0
	return sim.tile_elevation(x, y)

func tile_tags(x: int, y: int) -> int:
	if _society and _society.has_method("tile_tags"):
		return _society.tile_tags(x, y)
	if not sim_ready:
		return 0
	return sim.tile_tags(x, y)

func ticks() -> int:
	if _society and _society.has_method("ticks"):
		return _society.ticks()
	if not sim_ready:
		return 0
	return sim.ticks()

func year() -> int:
	if _society and _society.has_method("year"):
		return _society.year()
	if not sim_ready:
		return 0
	return sim.year()

func day_of_year() -> int:
	if _society and _society.has_method("day_of_year"):
		return _society.day_of_year()
	if not sim_ready:
		return 0
	return sim.day_of_year()

func hour() -> int:
	if _society and _society.has_method("hour"):
		return _society.hour()
	if not sim_ready:
		return 0
	return sim.hour()

func season() -> int:
	if _society and _society.has_method("season"):
		return _society.season()
	if not sim_ready:
		return 0
	return sim.season()

func get_npcs() -> Array:
	if _society and _society.has_method("get_npcs"):
		return _society.get_npcs()
	return []

func get_buildings() -> Array:
	if _society and _society.has_method("get_buildings"):
		return _society.get_buildings()
	return []

func get_civs() -> Array:
	if _society and _society.has_method("get_civs"):
		return _society.get_civs()
	return []

func civ_color(civ_id: int) -> Color:
	if _society and _society.has_method("civ_color"):
		return _society.civ_color(civ_id)
	return Color(0.7, 0.7, 0.7)

func get_trees() -> Array:
	if _society and _society.has_method("get_trees"):
		return _society.get_trees()
	return []

func civ_wood(civ_id: int) -> int:
	if _society and _society.has_method("civ_wood"):
		return _society.civ_wood(civ_id)
	return 0

func tile_owner(x: int, y: int) -> int:
	if _society and _society.has_method("tile_owner"):
		return _society.tile_owner(x, y)
	return -1

func territory_version() -> int:
	if _society and _society.has_method("territory_version"):
		return _society.territory_version()
	return 0
