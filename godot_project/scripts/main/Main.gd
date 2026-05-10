extends Node3D
## Top-level 3D scene controller.
##
## Responsibilities:
##   - boot the sim through GameState
##   - drive per-frame `advance` calls
##   - hand off rendering to [HexGrid]
##   - hand off UI to [HUD]
##   - drain the simulation event queue every frame and dispatch:
##       - one-shot 3D audio at the event location (chop / hammer)
##       - one-shot 2D audio (birth chime)
##       - "first-of-kind" auto-camera dives (Phase 5 polish)
##
## All Phase 5 polish hooks live here on purpose — this is the only
## scene-graph node that owns both the simulation event stream *and*
## references to the camera + audio players.

const TICKS_PER_FRAME := 1

const SND_AXE := preload("res://assets/audio/axe_chop.wav")
const SND_BUILD := preload("res://assets/audio/build_hammer.wav")
const SND_BIRTH := preload("res://assets/audio/birth_chime.wav")
const ONESHOT_MAX_DISTANCE := 60.0
const ONESHOT_VOLUME_DB := -6.0

@onready var hex_grid: Node3D = $WorldRoot/HexGrid
@onready var orbit_cam: Node3D = $WorldRoot/OrbitCamera
@onready var hud: CanvasLayer = $HUD
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $WorldRoot/Sun
@onready var fill_light: DirectionalLight3D = $WorldRoot/FillLight

var _audio_2d: AudioStreamPlayer = null
var _seen_first_chop: bool = false
var _seen_first_building: bool = false
var _seen_first_leader_change: bool = false

func _ready() -> void:
	_audio_2d = AudioStreamPlayer.new()
	_audio_2d.bus = "Master"
	add_child(_audio_2d)
	if SaveManager:
		SaveManager.loaded.connect(_on_save_loaded)
	start_game()
	# Hand off the lighting rig to the day/night autoload so it can drive
	# sun rotation/colour, sky, ambient and zoom-out fog every frame.
	TimeOfDay.bind_world(world_env, sun, fill_light, orbit_cam)

## Boot the world using the parameters in [RunConfig].
##
## Safe to call when Main.tscn is opened directly during development —
## [RunConfig.ensure_defaults] fills in fallbacks matching the previous
## hard-coded values. The menu / new-game flow populates RunConfig and
## generates the world ahead of time, so we skip a redundant generation
## when [GameState.world_ready] already returns true.
func start_game() -> void:
	RunConfig.ensure_defaults()
	if not GameState.sim_ready:
		push_warning("[Main] No sim. Running in inert mode.")
		hud.bind(null, null, null)
		return
	if not GameState.world_ready():
		var ok := GameState.start_world(
			RunConfig.seed,
			RunConfig.map_width,
			RunConfig.map_height,
			RunConfig.civ_count,
		)
		if not ok:
			push_warning("[Main] Failed to start world.")
			hud.bind(null, null, null)
			return
	hex_grid.bind(GameState)
	orbit_cam.set_world_bounds(hex_grid.world_rect_3d())
	hud.bind(GameState, hex_grid, orbit_cam)
	_focus_on_player_civ()

## Aim the camera at the spawn-point of the player's chosen civ so the
## game opens with their people on screen.
func _focus_on_player_civ() -> void:
	var civ_id: int = RunConfig.player_civ_id
	var civs: Array = GameState.get_civs()
	if civ_id < 0 or civ_id >= civs.size():
		return
	var civ: Dictionary = civs[civ_id]
	var pos: Vector3 = hex_grid.hex_center(int(civ.spawn_x), int(civ.spawn_y))
	orbit_cam.focus_on(pos)

func _process(_delta: float) -> void:
	if GameState.sim_ready:
		GameState.advance(TICKS_PER_FRAME)
		_consume_events()
		hex_grid.update_entities()
		hud.refresh()

## Drains [GameState.recent_events] every frame and reacts to the entries
## we care about (sounds, first-of-kind auto-camera). Other consumers of
## the queue must not co-exist — this drains it. If we add another
## consumer later it should subscribe to a fan-out signal here, not call
## [GameState.recent_events] itself.
func _consume_events() -> void:
	var events: Array = GameState.recent_events()
	if events.is_empty():
		return
	for e in events:
		var et := String(e.get("type", ""))
		match et:
			"tree_chopped":
				var pos: Vector3 = hex_grid.hex_center(int(e.get("x", 0)), int(e.get("y", 0)))
				_play_oneshot_3d(SND_AXE, pos)
				if not _seen_first_chop:
					_seen_first_chop = true
					orbit_cam.fly_to(pos)
			"building_progress":
				var pos: Vector3 = hex_grid.hex_center(int(e.get("x", 0)), int(e.get("y", 0)))
				_play_oneshot_3d(SND_BUILD, pos)
			"building_complete":
				var pos: Vector3 = hex_grid.hex_center(int(e.get("x", 0)), int(e.get("y", 0)))
				_play_oneshot_3d(SND_BUILD, pos)
				if not _seen_first_building:
					_seen_first_building = true
					orbit_cam.fly_to(pos)
			"birth":
				_audio_2d.stream = SND_BIRTH
				_audio_2d.volume_db = -3.0
				_audio_2d.play()
			"leader_changed", "leader_chosen":
				if _seen_first_leader_change:
					continue
				_seen_first_leader_change = true
				var leader: Dictionary = GameState.find_npc(int(e.get("leader_id", -1)))
				if leader.is_empty():
					continue
				var pos: Vector3 = hex_grid.hex_center(int(leader.get("x", 0)), int(leader.get("y", 0)))
				orbit_cam.fly_to(pos)
			_:
				pass

func _play_oneshot_3d(stream: AudioStream, world_pos: Vector3) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "Master"
	p.unit_size = 6.0
	p.max_distance = ONESHOT_MAX_DISTANCE
	p.volume_db = ONESHOT_VOLUME_DB
	p.position = world_pos + Vector3(0, 0.5, 0)
	p.attenuation_filter_db = 0.0
	$WorldRoot.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func _input(event: InputEvent) -> void:
	if not GameState.sim_ready:
		return
	if event.is_action_pressed("ui_pause"):
		GameState.set_time_scale(0)
	elif event.is_action_pressed("ui_speed_normal"):
		GameState.set_time_scale(1)
	elif event.is_action_pressed("ui_speed_fast"):
		GameState.set_time_scale(4)
	elif event.is_action_pressed("ui_speed_very_fast"):
		GameState.set_time_scale(16)

## After [SaveManager.quick_load], the simulation state is fully
## different — we need to rebuild the renderer (HexGrid caches per-tile
## meshes off [GameState.dims] and the territory version). Camera
## bounds also shift if the loaded world had different dims.
func _on_save_loaded(ok: bool, _path: String) -> void:
	if not ok:
		return
	hex_grid.bind(GameState)
	orbit_cam.set_world_bounds(hex_grid.world_rect_3d())
	_seen_first_chop = false
	_seen_first_building = false
	_seen_first_leader_change = false
	_focus_on_player_civ()
