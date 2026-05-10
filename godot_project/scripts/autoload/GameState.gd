extends Node
## Singleton holding global game state.
##
## Owns the long-lived [BabelSim] handle. Loaded as autoload at boot so any
## scene can access the simulation through `GameState.sim`.
##
## When the GDExtension `babel_gd` is unavailable, falls back to StubSim.
## When BabelSim is available but lacks society loop API, a StubSim overlay
## provides NPC/building data alongside BabelSim's terrain.

var sim = null           # BabelSim (Resource) or StubSim (Node)
var sim_ready: bool = false
var _society: Node = null  # StubSim for society loop (NPCs, buildings)

func _ready() -> void:
	_init_sim()

func _init_sim() -> void:
	if ClassDB.class_exists("BabelSim"):
		sim = ClassDB.instantiate("BabelSim")
		sim_ready = true
		print("[GameState] BabelSim extension loaded.")
	else:
		push_warning("[GameState] BabelSim not found — using StubSim for everything.")
		var FallbackScript := preload("res://scripts/autoload/StubSim.gd")
		var stub := FallbackScript.new()
		add_child(stub)
		sim = stub
		sim_ready = true

	# Always create a StubSim for the society loop demo (NPCs, buildings)
	var SocietyScript := preload("res://scripts/autoload/StubSim.gd")
	_society = SocietyScript.new()
	_society.name = "SocietyLoop"
	add_child(_society)

func start_world(seed_value: int, width: int, height: int) -> bool:
	if not sim_ready:
		return false
	var ok: bool = sim.start(seed_value, width, height)
	# Also start the society overlay with the same seed
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
	if not sim_ready:
		return Vector2i.ZERO
	# Prefer society's dims (StubSim uses 128x128)
	if _society and _society.has_method("dims"):
		return _society.dims()
	return sim.dims()

func tile_biome(x: int, y: int) -> int:
	if not sim_ready:
		return 255
	# Use society's terrain data for consistent NPC/building placement
	if _society and _society.has_method("tile_biome"):
		return _society.tile_biome(x, y)
	return sim.tile_biome(x, y)

func tile_elevation(x: int, y: int) -> int:
	if not sim_ready:
		return 0
	if _society and _society.has_method("tile_elevation"):
		return _society.tile_elevation(x, y)
	return sim.tile_elevation(x, y)

func tile_tags(x: int, y: int) -> int:
	if not sim_ready:
		return 0
	if _society and _society.has_method("tile_tags"):
		return _society.tile_tags(x, y)
	return sim.tile_tags(x, y)

func ticks() -> int:
	if not sim_ready:
		return 0
	if _society and _society.has_method("ticks"):
		return _society.ticks()
	return sim.ticks()

func year() -> int:
	if not sim_ready:
		return 0
	if _society and _society.has_method("year"):
		return _society.year()
	return sim.year()

func day_of_year() -> int:
	if not sim_ready:
		return 0
	if _society and _society.has_method("day_of_year"):
		return _society.day_of_year()
	return sim.day_of_year()

func hour() -> int:
	if not sim_ready:
		return 0
	if _society and _society.has_method("hour"):
		return _society.hour()
	return sim.hour()

func season() -> int:
	if not sim_ready:
		return 0
	if _society and _society.has_method("season"):
		return _society.season()
	return sim.season()

func get_npcs() -> Array:
	if _society and _society.has_method("get_npcs"):
		return _society.get_npcs()
	if sim_ready and sim.has_method("get_npcs"):
		return sim.get_npcs()
	return []

func get_buildings() -> Array:
	if _society and _society.has_method("get_buildings"):
		return _society.get_buildings()
	if sim_ready and sim.has_method("get_buildings"):
		return sim.get_buildings()
	return []
