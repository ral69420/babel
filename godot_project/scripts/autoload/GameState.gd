extends Node
## Singleton holding global game state.
##
## Owns the long-lived [BabelSim] handle. Loaded as autoload at boot so any
## scene can access the simulation through `GameState.sim`.
##
## When the GDExtension `babel_gd` is unavailable, falls back to StubSim —
## a pure-GDScript procedural world with society loop for demo / testing.

var sim = null           # BabelSim (Resource) or StubSim (Node)
var sim_ready: bool = false
var _stub: Node = null   # keep reference when using StubSim

func _ready() -> void:
	_init_sim()

func _init_sim() -> void:
	# Use StubSim for the society loop demo — it has NPC/building logic.
	# BabelSim (Rust) doesn't expose society loop yet.
	var use_stub := true
	if ClassDB.class_exists("BabelSim") and not use_stub:
		sim = ClassDB.instantiate("BabelSim")
		sim_ready = true
		print("[GameState] BabelSim extension loaded.")
	else:
		print("[GameState] Using StubSim for society loop demo.")
		var StubSimScript := preload("res://scripts/autoload/StubSim.gd")
		_stub = StubSimScript.new()
		add_child(_stub)
		sim = _stub
		sim_ready = true

func start_world(seed_value: int, width: int, height: int) -> bool:
	if not sim_ready:
		return false
	return sim.start(seed_value, width, height)

func advance(frame_ticks: int) -> int:
	if not sim_ready:
		return 0
	return sim.advance(frame_ticks)

func set_time_scale(scale: int) -> bool:
	if not sim_ready:
		return false
	return sim.set_time_scale(scale)

func dims() -> Vector2i:
	if not sim_ready:
		return Vector2i.ZERO
	return sim.dims()

func tile_biome(x: int, y: int) -> int:
	if not sim_ready:
		return 255
	return sim.tile_biome(x, y)

func tile_elevation(x: int, y: int) -> int:
	if not sim_ready:
		return 0
	return sim.tile_elevation(x, y)

func tile_tags(x: int, y: int) -> int:
	if not sim_ready:
		return 0
	return sim.tile_tags(x, y)

func ticks() -> int:
	if not sim_ready:
		return 0
	return sim.ticks()

func year() -> int:
	if not sim_ready:
		return 0
	return sim.year()

func day_of_year() -> int:
	if not sim_ready:
		return 0
	return sim.day_of_year()

func hour() -> int:
	if not sim_ready:
		return 0
	return sim.hour()

func season() -> int:
	if not sim_ready:
		return 0
	return sim.season()

func get_npcs() -> Array:
	if not sim_ready:
		return []
	if sim.has_method("get_npcs"):
		return sim.get_npcs()
	return []

func get_buildings() -> Array:
	if not sim_ready:
		return []
	if sim.has_method("get_buildings"):
		return sim.get_buildings()
	return []
