extends Node
## Singleton holding global game state.
##
## Owns the long-lived [BabelSim] handle. Loaded as autoload at boot so any
## scene can access the simulation through `GameState.sim`.
##
## When the GDExtension `babel_gd` is unavailable (e.g. release without the
## .so present, CI lint-only run), `sim` falls back to a stub that returns
## sensible defaults so scenes still load.

# Note: BabelSim is registered as a GDExtension Resource. If the extension
# isn't loaded yet, `ClassDB.class_exists("BabelSim")` returns false.

var sim: Resource = null
var sim_ready: bool = false

func _ready() -> void:
	_init_sim()

func _init_sim() -> void:
	if ClassDB.class_exists("BabelSim"):
		sim = ClassDB.instantiate("BabelSim")
		sim_ready = true
		print("[GameState] BabelSim extension loaded.")
	else:
		push_warning("[GameState] BabelSim extension NOT loaded. Running in stub mode.")
		sim = null
		sim_ready = false

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

## Summon a Strugatsky "Zone" anomaly at `(x, y)`.
## Returns number of tiles tagged (0 = out of bounds).
func summon_zone(x: int, y: int) -> int:
	if not sim_ready:
		return 0
	return sim.summon_zone(x, y)
