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

func start_world(seed_value: int, width: int, height: int) -> bool:
	if not sim_ready:
		return false
	var ok: bool = sim.start(seed_value, width, height)
	if _society and _society != sim:
		_society.start(seed_value, width, height)
	return ok

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
