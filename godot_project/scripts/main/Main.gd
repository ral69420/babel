extends Node2D
## Top-level scene controller.
##
## Responsibilities:
##   - boot the sim through GameState
##   - drive per-frame `advance` calls
##   - hand off rendering to [WorldView]
##   - hand off UI to [HUD]
##
## Keeps no state of its own — just orchestration.

const DEFAULT_SEED := 0x000B_ABE1  # mirrors babel_sim::SimConfig::default
const DEFAULT_WIDTH := 256
const DEFAULT_HEIGHT := 256
const TICKS_PER_FRAME := 1

@onready var world_view: Node2D = $WorldRoot/WorldView
@onready var camera: Camera2D = $WorldRoot/CameraRig
@onready var hud: CanvasLayer = $HUD

func _ready() -> void:
	if GameState.sim_ready:
		var ok := GameState.start_world(DEFAULT_SEED, DEFAULT_WIDTH, DEFAULT_HEIGHT)
		if not ok:
			push_warning("[Main] Failed to start world. Check BabelSim extension.")
		else:
			world_view.bind(GameState)
			camera.set_world_rect(world_view.world_rect())
			hud.bind(GameState, world_view, camera)
	else:
		push_warning("[Main] No sim. Running in inert mode.")
		hud.bind(null, null, null)

func _process(_delta: float) -> void:
	if GameState.sim_ready:
		GameState.advance(TICKS_PER_FRAME)
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
