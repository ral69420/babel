extends Control
## Main entry-point scene shown at game launch.
##
## Boots straight to a New Game flow. "Continue" is a placeholder until
## the save/load system lands in Phase 5.

@onready var _start_button: Button = %StartButton
@onready var _continue_button: Button = %ContinueButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_start_button.pressed.connect(_on_start)
	_continue_button.pressed.connect(_on_continue)
	_quit_button.pressed.connect(_on_quit)
	_continue_button.disabled = true   # save/load lands in Phase 5


func _on_start() -> void:
	# Start a fresh run; clear any previous RunConfig in case the menu is
	# re-entered after a game session.
	RunConfig.reset()
	get_tree().change_scene_to_file("res://scenes/NewGame.tscn")


func _on_continue() -> void:
	pass   # Phase 5


func _on_quit() -> void:
	get_tree().quit()
