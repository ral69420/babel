extends Node
## Autoload — wraps quick-save / quick-load of the StubSim society state
## to a JSON file under [user://saves/].
##
## We only persist what the society loop owns ([StubSim]) plus the
## [RunConfig] selection that produced it. The Rust BabelSim-side world
## (biomes, elevation, tags) round-trips through StubSim too, since the
## society loop owns its own copy of those buffers — so a load fully
## reconstructs without touching the Rust extension.

const SAVE_PATH := "user://saves/quick.json"
const SAVE_DIR := "user://saves"

signal saved(ok: bool, path: String)
signal loaded(ok: bool, path: String)

func _ready() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("saves"):
		dir.make_dir("saves")

## Returns true if [SAVE_PATH] exists on disk. Cheap — used to enable /
## disable the Load button without actually parsing the file.
func has_quicksave() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## Snapshot the running [StubSim] (via GameState) and the player's civ
## selection to disk. Returns true on success; on failure
## [push_warning]s and emits [saved] with ok=false so the UI can react.
func quick_save() -> bool:
	var state: Node = _society()
	if state == null or not state.has_method("to_save_dict"):
		push_warning("[SaveManager] no society loop to save")
		saved.emit(false, SAVE_PATH)
		return false
	var payload: Dictionary = {
		"format": "babel.savegame",
		"format_version": 1,
		"sim": state.to_save_dict(),
		"run_config": _runconfig_to_dict(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[SaveManager] cannot open %s for write (err %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		saved.emit(false, SAVE_PATH)
		return false
	f.store_string(JSON.stringify(payload))
	f.close()
	saved.emit(true, SAVE_PATH)
	return true

## Read [SAVE_PATH] back into the running [StubSim]. Caller (typically
## Main / a pause-menu button) is responsible for telling the world
## renderer to rebuild from the new state — see [GameState.world_ready]
## and [HexGrid] in [Main.gd]. Returns true on success.
func quick_load() -> bool:
	var state: Node = _society()
	if state == null or not state.has_method("load_from_dict"):
		push_warning("[SaveManager] no society loop to load into")
		loaded.emit(false, SAVE_PATH)
		return false
	if not FileAccess.file_exists(SAVE_PATH):
		loaded.emit(false, SAVE_PATH)
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		loaded.emit(false, SAVE_PATH)
		return false
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[SaveManager] save file is not a dictionary")
		loaded.emit(false, SAVE_PATH)
		return false
	var payload: Dictionary = parsed
	if String(payload.get("format", "")) != "babel.savegame":
		push_warning("[SaveManager] save file format mismatch")
		loaded.emit(false, SAVE_PATH)
		return false
	var sim_data: Dictionary = payload.get("sim", {})
	if not state.load_from_dict(sim_data):
		loaded.emit(false, SAVE_PATH)
		return false
	_runconfig_from_dict(payload.get("run_config", {}))
	loaded.emit(true, SAVE_PATH)
	return true

func _society() -> Node:
	# GameState is auto-loaded before this script. We use the
	# [society()] accessor it exposes for save/load — same instance the
	# rest of the game runs through.
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	if gs == null or not gs.has_method("society"):
		return null
	return gs.society()

func _runconfig_to_dict() -> Dictionary:
	var rc: Node = get_tree().root.get_node_or_null("RunConfig")
	if rc == null:
		return {}
	return {
		"seed":          int(rc.get("seed")),
		"map_width":     int(rc.get("map_width")),
		"map_height":    int(rc.get("map_height")),
		"civ_count":     int(rc.get("civ_count")),
		"player_civ_id": int(rc.get("player_civ_id")),
	}

func _runconfig_from_dict(d: Dictionary) -> void:
	var rc: Node = get_tree().root.get_node_or_null("RunConfig")
	if rc == null or d.is_empty():
		return
	if d.has("seed"):
		rc.set("seed", int(d.seed))
	if d.has("map_width"):
		rc.set("map_width", int(d.map_width))
	if d.has("map_height"):
		rc.set("map_height", int(d.map_height))
	if d.has("civ_count"):
		rc.set("civ_count", int(d.civ_count))
	if d.has("player_civ_id"):
		rc.set("player_civ_id", int(d.player_civ_id))
	rc.set("is_initialized", true)
