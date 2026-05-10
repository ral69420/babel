extends SceneTree
## Headless smoke check for Phase 5 plumbing.
##
## Run with:
##   godot --headless --path godot_project -s scripts/_phase5_test.gd
##
## Verifies:
##   1. StubSim.to_save_dict() round-trips through JSON
##   2. StubSim.load_from_dict() restores civ count, NPC count, ticks
##   3. Localization keys resolve to non-empty English strings
##   4. SaveManager autoload is registered

var _ran: bool = false

func _initialize() -> void:
	# `_initialize` runs after autoloads are *added* to root, but
	# their `_ready` (and hence Localization.add_translation) only
	# fires on the first physics_frame. Defer to `_process` so every
	# autoload has had a chance to wire itself up.
	pass

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var failures: int = 0
	failures += _test_savedict_roundtrip()
	failures += _test_save_manager()
	failures += _test_localization()
	if failures == 0:
		print("[phase5_test] ALL CHECKS PASSED")
		quit(0)
	else:
		printerr("[phase5_test] %d FAILURES" % failures)
		quit(1)
	return true

func _test_savedict_roundtrip() -> int:
	# Spin up a fresh society by scripting StubSim directly. This avoids
	# the need to boot GameState (which loads the GDExtension) — we
	# only care that the save dict survives JSON encoding.
	var sim_script: GDScript = load("res://scripts/autoload/StubSim.gd") as GDScript
	if sim_script == null:
		printerr("  [savedict] cannot load StubSim.gd")
		return 1
	var sim: Node = sim_script.new()
	root.add_child(sim)
	sim.start(0xBABE5_5, 64, 48, 3)
	for _i in 50:
		sim.advance(1)
	var snap: Dictionary = sim.to_save_dict()
	var encoded: String = JSON.stringify(snap)
	if encoded.length() < 100:
		printerr("  [savedict] encoded too short: %d" % encoded.length())
		return 1
	var decoded: Variant = JSON.parse_string(encoded)
	if typeof(decoded) != TYPE_DICTIONARY:
		printerr("  [savedict] decoded not dict")
		return 1
	# Spin up a second StubSim to load into.
	var sim2: Node = sim_script.new()
	root.add_child(sim2)
	if not sim2.load_from_dict(decoded):
		printerr("  [savedict] load_from_dict failed")
		return 1
	if sim2.get_npcs().size() != sim.get_npcs().size():
		printerr("  [savedict] npc count mismatch")
		return 1
	if sim2.get_civs().size() != sim.get_civs().size():
		printerr("  [savedict] civ count mismatch")
		return 1
	if sim2.current_sim_day() != sim.current_sim_day():
		printerr("  [savedict] sim day mismatch (%d vs %d)" % [sim2.current_sim_day(), sim.current_sim_day()])
		return 1
	if sim2.dims() != sim.dims():
		printerr("  [savedict] dims mismatch")
		return 1
	print("  [savedict] OK (%d npcs · %d civs · day %d · dims %s)" % [
		sim.get_npcs().size(), sim.get_civs().size(), sim.current_sim_day(), sim.dims(),
	])
	sim.queue_free()
	sim2.queue_free()
	return 0

func _test_save_manager() -> int:
	var sm: Node = root.get_node_or_null("SaveManager")
	if sm == null:
		printerr("  [save_manager] autoload missing")
		return 1
	if not sm.has_method("quick_save") or not sm.has_method("quick_load"):
		printerr("  [save_manager] api missing")
		return 1
	print("  [save_manager] autoload present")
	return 0

func _test_localization() -> int:
	# Localization autoload registers translations; verify a couple of
	# keys resolve to humane English strings (not the literal key).
	var keys := ["top.save", "top.load", "civ_panel.no_leader", "toast.saved"]
	var fails: int = 0
	for k in keys:
		var v := tr(k)
		if v == k or v.is_empty():
			printerr("  [locale] key %s did not resolve" % k)
			fails += 1
	if fails == 0:
		print("  [locale] OK (%d keys resolved)" % keys.size())
	return fails
