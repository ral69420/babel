extends CanvasLayer
## On-screen UI shell.
##
## Layout:
##   ┌──────────────────────────────────────────────────────────────────────┐
##   │  Year XXX · Spring · Era      [⏸ ▶︎ ⏩ ⏭]            zoom 2.0× 64,128 │  ← TopBar
##   │                                                                      │
##   │                                                                      │
##   │                                                                      │
##   │  Biome legend                                  Hover:  Plains / hill │  ← bottom
##   └──────────────────────────────────────────────────────────────────────┘
##
## All labels read directly from the [GameState] autoload via the `_state`
## handle bound at startup, so the HUD has no game logic of its own.

const SEASON_NAMES := ["Spring", "Summer", "Autumn", "Winter"]
const SEASON_COLORS := [
	Color8(180, 198, 130, 255),  # Spring — fresh olive
	Color8(214, 188, 110, 255),  # Summer — warm amber
	Color8(190, 138, 96,  255),  # Autumn — copper
	Color8(180, 196, 210, 255),  # Winter — cold pewter
]
const BIOME_NAMES := ["Ocean", "Coast", "Plains", "Forest", "Hills", "Mountain", "Desert", "Tundra"]

const TILE_TAG_RUIN  := 0x01
const TILE_TAG_RIVER := 0x04

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
var _world_view: Node2D = null
var _camera: Camera2D = null
var _current_scale: int = 1

func _ready() -> void:
	_wire_speed_buttons()
	_build_legend()

func bind(state: Node, world_view: Node2D, camera: Camera2D) -> void:
	_state = state
	_world_view = world_view
	_camera = camera
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
	# Show NPC/building stats alongside era
	var npc_count := 0
	var bld_count := 0
	if _state.has_method("get_npcs"):
		var npc_list: Array = _state.get_npcs()
		for n in npc_list:
			if n.alive:
				npc_count += 1
	if _state.has_method("get_buildings"):
		bld_count = _state.get_buildings().size()
	era_label.text = "%s  ·  %d pop  ·  %d bld" % [_era_for_year(year), npc_count, bld_count]
	_refresh_coords_label()
	_refresh_hover_label()

func _refresh_coords_label() -> void:
	if _camera == null:
		coords_label.text = ""
		return
	coords_label.text = "zoom %.1f×" % _camera.zoom.x

func _refresh_hover_label() -> void:
	if _world_view == null or _camera == null:
		hover_label.text = ""
		return
	var screen_pos := _camera.get_viewport().get_mouse_position()
	var world_pos: Vector2 = _camera.get_world_pos(screen_pos)
	var t: Vector2i = _world_view.world_to_tile(world_pos)
	if t.x < 0:
		hover_label.text = "—"
		return
	var b: int = _state.tile_biome(t.x, t.y)
	var elev: int = _state.tile_elevation(t.x, t.y)
	var tags: int = _state.tile_tags(t.x, t.y)
	var name: String = BIOME_NAMES[b] if b >= 0 and b < BIOME_NAMES.size() else "?"
	var extra: String = ""
	if (tags & TILE_TAG_RIVER) != 0:
		extra = " · river"
	elif (tags & TILE_TAG_RUIN) != 0:
		extra = " · ruin"
	hover_label.text = "(%d, %d)  %s  elev %d%s" % [t.x, t.y, name, elev, extra]

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
	# Match WorldView.BIOME_COLORS so the legend stays accurate.
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
	# Deterministic era bands. Tweak alongside the chronicle templates.
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
