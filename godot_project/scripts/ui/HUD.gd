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
const DAYS_PER_YEAR := 360

@onready var era_label: Label = $TopBar/Bar/Left/Era
@onready var year_label: Label = $TopBar/Bar/Left/YearSeason
@onready var pause_btn: Button = $TopBar/Bar/Center/Pause
@onready var normal_btn: Button = $TopBar/Bar/Center/Normal
@onready var fast_btn: Button = $TopBar/Bar/Center/Fast
@onready var very_fast_btn: Button = $TopBar/Bar/Center/VeryFast
@onready var coords_label: Label = $TopBar/Bar/Right/Coords
@onready var hover_label: Label = $BottomBar/Hover
@onready var legend_box: HBoxContainer = $BottomBar/Legend

# CivPanel widgets (bottom-left). Bound by unique-name-in-owner so the
# scene tree path can change without breaking these refs.
@onready var civ_panel: PanelContainer = $CivPanel
@onready var civ_flag: ColorRect = %Flag
@onready var civ_name_label: Label = %CivName
@onready var leader_portrait: TextureRect = %Portrait
@onready var leader_name_label: Label = %LeaderName
@onready var leader_sub_label: Label = %LeaderSub
@onready var civ_stats_label: Label = %Stats

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
		civ_panel.visible = false
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

	_refresh_civ_panel()
	_refresh_hover_tooltip()

# ── Civ panel (player's civ overview, bottom-left) ────────────────────
## Show name + flag colour + leader portrait / name / age / years in
## power, plus pop / houses / territory share, for the civ the player
## picked at start. Invisible if RunConfig has no valid civ id (e.g.
## Main.tscn opened directly with a fresh state).
func _refresh_civ_panel() -> void:
	var civs: Array = _state.get_civs()
	var civ_id: int = RunConfig.player_civ_id
	if civ_id < 0 or civ_id >= civs.size():
		civ_panel.visible = false
		return
	civ_panel.visible = true
	var civ: Dictionary = civs[civ_id]
	var civ_color: Color = civ.color if civ.has("color") else Color.WHITE
	civ_flag.color = civ_color
	civ_name_label.text = String(civ.name) if civ.has("name") else ""
	civ_name_label.add_theme_color_override("font_color", civ_color)

	var leader_id: int = -1
	if _state.has_method("civ_leader_id"):
		leader_id = _state.civ_leader_id(civ_id)
	leader_portrait.modulate = civ_color
	if leader_id < 0:
		leader_name_label.text = "★ (vacant)"
		leader_sub_label.text = "no eligible elder"
	else:
		var leader_name: String = ""
		if _state.has_method("npc_name"):
			leader_name = _state.npc_name(leader_id)
		var npc: Dictionary = _state.find_npc(leader_id) if _state.has_method("find_npc") else {}
		var age_y: int = 0
		if not npc.is_empty():
			age_y = int(npc.age_days) / DAYS_PER_YEAR
		var years_in_power: int = 0
		if _state.has_method("civ_leader_term_started_day") and _state.has_method("current_sim_day"):
			var term_started: int = _state.civ_leader_term_started_day(civ_id)
			var today: int = _state.current_sim_day()
			years_in_power = max(0, (today - term_started) / DAYS_PER_YEAR)
		leader_name_label.text = "★ %s" % leader_name
		leader_sub_label.text = "age %d  ·  %d y in power" % [age_y, years_in_power]

	var pop: int = _state.civ_population(civ_id) if _state.has_method("civ_population") else 0
	var houses: int = _state.civ_buildings_count(civ_id) if _state.has_method("civ_buildings_count") else 0
	var territory_pct: int = _territory_percent(civ_id)
	civ_stats_label.text = "%d pop  ·  %d houses  ·  %d%% land" % [pop, houses, territory_pct]

func _territory_percent(civ_id: int) -> int:
	if not (_state.has_method("civ_territory_tile_count") and _state.has_method("total_owned_tile_count")):
		return 0
	var owned: int = _state.civ_territory_tile_count(civ_id)
	var total: int = _state.total_owned_tile_count()
	if total <= 0:
		return 0
	return int(round(100.0 * float(owned) / float(total)))

# ── Tile hover tooltip ────────────────────────────────────────────────
## Cast a ray from the mouse cursor onto the world's ground plane and
## display the hovered tile's owner + leader in the bottom-right Hover
## label. No tooltip when the cursor is over UI or off the map.
func _refresh_hover_tooltip() -> void:
	if _hex_grid == null or _orbit_cam == null:
		hover_label.text = ""
		return
	var camera: Camera3D = _orbit_cam.get_node("Camera3D") as Camera3D
	if camera == null:
		hover_label.text = ""
		return
	var mouse_pos: Vector2 = _hex_grid.get_viewport().get_mouse_position()
	var tile: Vector2i = _hex_grid.screen_to_tile(mouse_pos, camera)
	if tile.x < 0:
		hover_label.text = ""
		return
	var owner_id: int = _state.tile_owner(tile.x, tile.y) if _state.has_method("tile_owner") else -1
	if owner_id < 0:
		hover_label.text = "Unclaimed (%d, %d)" % [tile.x, tile.y]
		return
	var civs: Array = _state.get_civs()
	if owner_id >= civs.size():
		hover_label.text = ""
		return
	var civ: Dictionary = civs[owner_id]
	var leader_part: String = "no leader"
	if _state.has_method("civ_leader_id"):
		var leader_id: int = _state.civ_leader_id(owner_id)
		if leader_id >= 0 and _state.has_method("npc_name"):
			var leader_name: String = _state.npc_name(leader_id)
			var npc: Dictionary = _state.find_npc(leader_id) if _state.has_method("find_npc") else {}
			var age_y: int = 0
			if not npc.is_empty():
				age_y = int(npc.age_days) / DAYS_PER_YEAR
			leader_part = "★ %s, %dy" % [leader_name, age_y]
	hover_label.text = "%s  —  %s" % [String(civ.name), leader_part]

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
