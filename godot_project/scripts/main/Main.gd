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
# Textured renderer bakes the whole map at 32 px per tile, so a 256×256
# world becomes an 8192×8192 image (~256 MB). 128×128 → 4096×4096 (~64 MB)
# stays well under typical GPU/driver limits while still feeling expansive.
const DEFAULT_WIDTH := 128
const DEFAULT_HEIGHT := 128
const TICKS_PER_FRAME := 1

@onready var world_view: Node2D = $WorldRoot/WorldView
@onready var buildings_layer: Node2D = $WorldRoot/BuildingsLayer
@onready var npc_layer: Node2D = $WorldRoot/NpcLayer
@onready var camera: Camera2D = $WorldRoot/CameraRig
@onready var test_npc: Node2D = $WorldRoot/TestNpc
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
			# Society layers — sync sprites + progress bars from sim.
			buildings_layer.bind(GameState)
			npc_layer.bind(GameState)
			# TestNpc is a smoke check that the sprite/animation pipeline
			# works end-to-end. It walks a clockwise square inside the
			# map and is unrelated to the sim's NPC entities.
			test_npc.setup(world_view.world_rect())
			# Auto-pick a higher speed so the society loop is observable
			# without the user having to fiddle with hotkeys. 16× ≈ 1
			# sim-year per ~33 real seconds.
			GameState.set_time_scale(16)
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
	elif event.is_action_pressed("zone_summon"):
		_summon_zone_at_cursor()

# Spawn a Strugatsky-style anomaly under the mouse cursor and refresh the
# affected tiles. The renderer only repaints the 3×3 zone footprint plus a
# 1-tile margin so the dither bands stay correct.
func _summon_zone_at_cursor() -> void:
	if not GameState.sim_ready:
		return
	var screen_pos := get_viewport().get_mouse_position()
	var world_pos: Vector2 = camera.get_world_pos(screen_pos)
	var t: Vector2i = world_view.world_to_tile(world_pos)
	if t.x < 0:
		return
	var tagged: int = GameState.summon_zone(t.x, t.y)
	if tagged > 0:
		# Repaint the 3×3 zone footprint + 1-tile dither margin.
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				world_view.invalidate_tile(t.x + dx, t.y + dy)
