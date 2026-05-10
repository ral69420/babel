extends Node3D
## Top-level 3D scene controller.
##
## Responsibilities:
##   - boot the sim through GameState
##   - drive per-frame `advance` calls
##   - hand off rendering to [HexGrid]
##   - hand off UI to [HUD]

const TICKS_PER_FRAME := 1

@onready var hex_grid: Node3D = $WorldRoot/HexGrid
@onready var orbit_cam: Node3D = $WorldRoot/OrbitCamera
@onready var hud: CanvasLayer = $HUD

func _ready() -> void:
	start_game()

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
		hex_grid.update_entities()
		hud.refresh()

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
