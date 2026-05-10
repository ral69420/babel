extends Node3D
## Top-level 3D scene controller.
##
## Responsibilities:
##   - boot the sim through GameState
##   - drive per-frame `advance` calls
##   - hand off rendering to [HexGrid]
##   - hand off UI to [HUD]

const DEFAULT_SEED := 0x000B_ABE1
const DEFAULT_WIDTH := 256
const DEFAULT_HEIGHT := 256
const TICKS_PER_FRAME := 1

@onready var hex_grid: Node3D = $WorldRoot/HexGrid
@onready var orbit_cam: Node3D = $WorldRoot/OrbitCamera
@onready var hud: CanvasLayer = $HUD

func _ready() -> void:
	if GameState.sim_ready:
		var ok := GameState.start_world(DEFAULT_SEED, DEFAULT_WIDTH, DEFAULT_HEIGHT)
		if not ok:
			push_warning("[Main] Failed to start world.")
		else:
			hex_grid.bind(GameState)
			orbit_cam.set_world_bounds(hex_grid.world_rect_3d())
			hud.bind(GameState, hex_grid, orbit_cam)
	else:
		push_warning("[Main] No sim. Running in inert mode.")
		hud.bind(null, null, null)

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
