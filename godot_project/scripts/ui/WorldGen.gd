extends Control
## Loading screen that actually drives world generation.
##
## Generation is a single blocking call inside [GameState.start_world],
## so we deferred-call it after one frame so the progress bar and label
## have a chance to render. Once it returns we transition to the
## civilization-picker.

@onready var _progress: ProgressBar = %Progress
@onready var _status: Label = %Status
@onready var _flavour: Label = %Flavour

const FLAVOUR_LINES := [
	"Carving rivers into the heightmap...",
	"Seeding forests and tundra...",
	"Choosing where peoples will rise...",
	"Naming the founding clans...",
	"Lighting the first hearths...",
]


func _ready() -> void:
	_progress.min_value = 0
	_progress.max_value = 4
	_progress.value = 0
	_status.text = "Preparing the world"
	_flavour.text = FLAVOUR_LINES[0]
	# Defer the heavy work so the UI paints once before we block.
	_generate.call_deferred()


func _generate() -> void:
	# Step 0: show the screen for a frame.
	await get_tree().process_frame
	_progress.value = 1
	_flavour.text = FLAVOUR_LINES[1]
	await get_tree().process_frame

	# Step 1: actually start the world. This is the slow step.
	_status.text = "Generating terrain"
	_progress.value = 2
	_flavour.text = FLAVOUR_LINES[2]
	await get_tree().process_frame

	var ok: bool = GameState.start_world(
		RunConfig.seed,
		RunConfig.map_width,
		RunConfig.map_height,
		RunConfig.civ_count,
	)
	if not ok:
		_status.text = "Failed to generate world."
		return

	_progress.value = 3
	_status.text = "Settling civilizations"
	_flavour.text = FLAVOUR_LINES[3]
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout

	_progress.value = 4
	_status.text = "Ready"
	_flavour.text = FLAVOUR_LINES[4]
	await get_tree().create_timer(0.3).timeout

	get_tree().change_scene_to_file("res://scenes/CivSelect.tscn")
