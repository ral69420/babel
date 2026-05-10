extends SceneTree
## Headless sim-invariant runner (Phase 0.4).
##
## Run with:
##   godot --headless --path godot_project -s tests/run_all.gd
##
## Boots a fresh `StubSim` (the GDScript society loop), advances it
## with a fixed seed, and asserts a handful of invariants that
## previous PRs put in place. Any future regression that breaks one
## of them prints `[run_all] FAIL: ...` and exits 1.
##
## Covers (Plan v2):
##   - Phase 0.5.b regression net: ocean fraction stays small
##   - Phase 0.5.c regression net: TUNDRA never produced
##   - Phase 0.5.d regression net: DESERT never produced
##   - Phase 0.5.e regression net: vegetation_wind shader resource exists
##   - Sim sanity: NPCs survive a 1000-day run, no civ has negative wood
##   - Determinism: same seed/dims => same `territory_version` after the run
##
## We deliberately don't boot `Main.tscn` or `GameState`. Spinning up
## `StubSim` directly keeps the test fast (≈1s) and isolated from
## render code that wouldn't run in headless anyway.

const SEED := 0xBABE1
const MAP_W := 96
const MAP_H := 96
const CIV_COUNT := 3
const SIM_DAYS := 1000

var _ran := false
var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	# `_initialize` runs before autoloads have had a chance to fully
	# wire up. Defer the actual work to the first `_process` tick so
	# any preload/translation/etc. on root has had its `_ready` called.
	pass

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run_all()
	if _failures == 0:
		print("[run_all] PASS · %d checks · seed=0x%X · %dx%d · %d sim-days" % [
			_checks, SEED, MAP_W, MAP_H, SIM_DAYS,
		])
		quit(0)
	else:
		printerr("[run_all] FAIL · %d/%d checks failed" % [_failures, _checks])
		quit(1)
	return true

func _run_all() -> void:
	var sim_script: GDScript = load("res://scripts/autoload/StubSim.gd") as GDScript
	if sim_script == null:
		_fail("could not load StubSim.gd")
		return

	var sim: Node = sim_script.new()
	root.add_child(sim)
	var ok: bool = sim.start(SEED, MAP_W, MAP_H, CIV_COUNT)
	_check(ok, "StubSim.start() returned true")

	# TICK_RATE constant on StubSim drives sim-day cadence. We pull it
	# off the instance instead of hard-coding so tests follow if it ever
	# changes.
	var tick_rate: int = int(sim.get("TICK_RATE"))
	if tick_rate <= 0:
		tick_rate = 6
	sim.advance(SIM_DAYS * tick_rate)

	_check_population(sim)
	_check_no_negative_wood(sim)
	_check_biomes(sim)
	_check_assets()

	var ver1: int = int(sim.territory_version())
	sim.queue_free()
	root.remove_child(sim)
	# Free deferred is ok — we just need a fresh slate before the
	# determinism re-run.

	var sim2: Node = sim_script.new()
	root.add_child(sim2)
	sim2.start(SEED, MAP_W, MAP_H, CIV_COUNT)
	sim2.advance(SIM_DAYS * tick_rate)
	var ver2: int = int(sim2.territory_version())
	_check(
		ver1 == ver2,
		"territory_version deterministic across two runs (got %d vs %d)" % [ver1, ver2],
	)
	sim2.queue_free()

func _check_population(sim: Node) -> void:
	var npcs: Array = sim.get_npcs()
	_check(npcs.size() > 0, "npcs present after %d sim-days (got %d)" % [SIM_DAYS, npcs.size()])

	var civs: Array = sim.get_civs()
	_check(civs.size() == CIV_COUNT, "civ count == requested (got %d)" % civs.size())

func _check_no_negative_wood(sim: Node) -> void:
	var civs: Array = sim.get_civs()
	for c in civs:
		var wood: int = int(c.stockpile.wood)
		_check(wood >= 0, "civ %d wood >= 0 (got %d)" % [int(c.id), wood])

func _check_biomes(sim: Node) -> void:
	# Pull biome enum off the script class so this stays in sync with
	# StubSim if the enum order ever shifts.
	var sim_script: GDScript = load("res://scripts/autoload/StubSim.gd") as GDScript
	var b_const: Dictionary = sim_script.get_script_constant_map()
	var biome_map: Dictionary = b_const.get("Biome", {})
	var ocean_id: int = int(biome_map.get("OCEAN", 0))
	var tundra_id: int = int(biome_map.get("TUNDRA", 7))
	var desert_id: int = int(biome_map.get("DESERT", 6))

	var dims: Vector2i = sim.dims()
	var total: int = dims.x * dims.y
	var ocean: int = 0
	var tundra: int = 0
	var desert: int = 0
	for y in dims.y:
		for x in dims.x:
			var b: int = int(sim.tile_biome(x, y))
			if b == ocean_id:
				ocean += 1
			elif b == tundra_id:
				tundra += 1
			elif b == desert_id:
				desert += 1
	_check(tundra == 0, "no TUNDRA tiles produced (got %d, Phase 0.5.c)" % tundra)
	_check(desert == 0, "no DESERT tiles produced (got %d, Phase 0.5.d)" % desert)
	var ocean_frac: float = float(ocean) / float(total)
	# Probed across 5 seeds (BABE1, CAFE, 1234, FEED, DEAD) at 256x256
	# the current generator lands at 22-30% ocean; pick a slightly
	# generous ceiling so we don't false-positive on noise variance
	# but still catch a regression that puts ocean back at ~50%.
	_check(
		ocean_frac < 0.35,
		"ocean fraction < 35%% (got %.1f%%, Phase 0.5.b regression net)" % (ocean_frac * 100.0),
	)

func _check_assets() -> void:
	# Phase 0.5.e regression net — make sure the wind shader file
	# is loadable. We don't render in headless, so this is purely a
	# "did someone delete the file" check.
	var sh: Shader = load("res://shaders/vegetation_wind.gdshader") as Shader
	_check(sh != null, "vegetation_wind.gdshader loads (Phase 0.5.e)")

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  [run_all] OK · " + msg)
	else:
		_failures += 1
		printerr("  [run_all] FAIL · " + msg)

func _fail(msg: String) -> void:
	_checks += 1
	_failures += 1
	printerr("  [run_all] FAIL · " + msg)
