extends CanvasLayer
## On-screen UI shell — 3D hex world version.

const SEASON_NAMES := ["Spring", "Summer", "Autumn", "Winter"]
const SEASON_COLORS := [
	Color8(180, 198, 130, 255),
	Color8(214, 188, 110, 255),
	Color8(190, 138, 96,  255),
	Color8(180, 196, 210, 255),
]
const BIOME_NAMES := ["Ocean", "Coast", "Plains", "Forest", "Hills", "Mountain", "Desert", "Tundra"]

@onready var era_label: Label = $TopBar/Bar/Left/Era
@onready var year_label: Label = $TopBar/Bar/Left/YearSeason
@onready var pause_btn: Button = $TopBar/Bar/Center/Pause
@onready var normal_btn: Button = $TopBar/Bar/Center/Normal
@onready var fast_btn: Button = $TopBar/Bar/Center/Fast
@onready var very_fast_btn: Button = $TopBar/Bar/Center/VeryFast
@onready var coords_label: Label = $TopBar/Bar/Right/Coords
@onready var hover_label: Label = $BottomBar/Hover
@onready var legend_box: HBoxContainer = $BottomBar/Legend

var _state: Node = null
var _hex_grid: Node3D = null
var _orbit_cam: Node3D = null
var _current_scale: int = 1

func _ready() -> void:
	_wire_speed_buttons()
	_build_legend()

func bind(state: Node, hex_grid: Node3D, orbit_cam: Node3D) -> void:
	_state = state
	_hex_grid = hex_grid
	_orbit_cam = orbit_cam
	refresh()

func refresh() -> void:
	if _state == null:
		year_label.text = "(no sim)"
		era_label.text = ""
		coords_label.text = ""
		hover_label.text = ""
		return
	var year: int = _state.year()
	var season_idx: int = _state.season()
	var hour: int = _state.hour()
	year_label.text = "Year %d  ·  %s  ·  %02d:00" % [year, SEASON_NAMES[season_idx], hour]
	year_label.add_theme_color_override("font_color", SEASON_COLORS[season_idx])

	var npc_count: int = _state.get_npcs().size()
	var bld_count: int = _state.get_buildings().size()
	var wood: int = _state.civ_wood(RunConfig.player_civ_id) if _state.has_method("civ_wood") else 0
	era_label.text = "%s  ·  %d pop  ·  %d bld  ·  %d wood" % [
		_era_for_year(year), npc_count, bld_count, wood,
	]

	if _orbit_cam:
		coords_label.text = "zoom %.0f  ·  [T] borders" % _orbit_cam.get_zoom_level()
	hover_label.text = ""

func _wire_speed_buttons() -> void:
	pause_btn.pressed.connect(func() -> void: _set_scale(0))
	normal_btn.pressed.connect(func() -> void: _set_scale(1))
	fast_btn.pressed.connect(func() -> void: _set_scale(4))
	very_fast_btn.pressed.connect(func() -> void: _set_scale(16))
	_update_button_state()

func _set_scale(scale: int) -> void:
	if _state == null:
		return
	_state.set_time_scale(scale)
	_current_scale = scale
	_update_button_state()

func _update_button_state() -> void:
	pause_btn.button_pressed = (_current_scale == 0)
	normal_btn.button_pressed = (_current_scale == 1)
	fast_btn.button_pressed = (_current_scale == 4)
	very_fast_btn.button_pressed = (_current_scale == 16)

func _build_legend() -> void:
	var swatches := [
		[Color8(28, 46, 76),    "Ocean"],
		[Color8(64, 102, 132),  "Coast"],
		[Color8(159, 175, 102), "Plains"],
		[Color8(58, 100, 64),   "Forest"],
		[Color8(124, 132, 96),  "Hills"],
		[Color8(110, 100, 92),  "Mountain"],
		[Color8(206, 184, 124), "Desert"],
		[Color8(214, 220, 224), "Tundra"],
	]
	for entry in swatches:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		var swatch := ColorRect.new()
		swatch.color = entry[0]
		swatch.custom_minimum_size = Vector2(12, 12)
		hb.add_child(swatch)
		var l := Label.new()
		l.text = entry[1]
		l.add_theme_font_size_override("font_size", 11)
		hb.add_child(l)
		legend_box.add_child(hb)

func _era_for_year(year: int) -> String:
	if year < 50:
		return "Era: Pre-classical"
	if year < 200:
		return "Era: Foundation"
	if year < 600:
		return "Era: Classical"
	if year < 1200:
		return "Era: Imperial"
	return "Era: Twilight"

func current_scale() -> int:
	return _current_scale
