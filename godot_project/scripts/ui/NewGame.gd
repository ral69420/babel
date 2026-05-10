extends Control
## "New Game" screen — pick seed / map size / civ count, then go to
## world generation.

## Map-size presets shown in the New Game screen.
## Phase 0.5 widens the slider to 256 – 2048; the larger options need the
## Big-World perf track (MultiMesh terrain, sim/render decoupling) before
## they hit the 240+ FPS target on mid-range hardware.
const MAP_PRESETS := {
	"small": Vector2i(256, 256),
	"medium": Vector2i(512, 512),
	"large": Vector2i(1024, 1024),
	"huge": Vector2i(2048, 2048),
}

@onready var _seed_input: LineEdit = %SeedInput
@onready var _seed_random: Button = %SeedRandomButton
@onready var _size_buttons: HBoxContainer = %SizeButtons
@onready var _civ_slider: HSlider = %CivCountSlider
@onready var _civ_label: Label = %CivCountLabel
@onready var _generate_button: Button = %GenerateButton
@onready var _back_button: Button = %BackButton

var _selected_size_key: String = "small"


func _ready() -> void:
	_seed_random.pressed.connect(_on_seed_random)
	_generate_button.pressed.connect(_on_generate)
	_back_button.pressed.connect(_on_back)
	_civ_slider.value_changed.connect(_on_civ_changed)
	_civ_slider.min_value = 2
	_civ_slider.max_value = 6
	_civ_slider.step = 1
	_civ_slider.value = 4
	_on_civ_changed(4)
	_on_seed_random()
	_setup_size_buttons()


func _setup_size_buttons() -> void:
	for child in _size_buttons.get_children():
		if child is Button:
			var btn := child as Button
			btn.toggle_mode = true
			btn.pressed.connect(_on_size_pressed.bind(btn))
			if btn.name == "Small":
				btn.button_pressed = true


func _on_size_pressed(btn: Button) -> void:
	for child in _size_buttons.get_children():
		if child is Button and child != btn:
			(child as Button).button_pressed = false
	btn.button_pressed = true
	_selected_size_key = btn.name.to_lower()


func _on_seed_random() -> void:
	# Godot ints are 64-bit; keep the visible seed within 32 bits so it's
	# easy for the player to type back from a screenshot.
	_seed_input.text = str(randi() & 0x7FFFFFFF)


func _on_civ_changed(v: float) -> void:
	_civ_label.text = "%d civilizations" % int(v)


func _parse_seed() -> int:
	var raw: String = _seed_input.text.strip_edges()
	if raw.is_valid_int():
		return raw.to_int()
	# Hash arbitrary text so "babel" is a usable seed.
	return raw.hash()


func _on_generate() -> void:
	var dims: Vector2i = MAP_PRESETS.get(_selected_size_key, MAP_PRESETS["small"])
	RunConfig.configure(
		_parse_seed(),
		dims.x,
		dims.y,
		int(_civ_slider.value),
		0,   # player_civ_id chosen on next screen
	)
	get_tree().change_scene_to_file("res://scenes/WorldGen.tscn")


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
