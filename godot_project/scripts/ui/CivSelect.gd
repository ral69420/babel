extends Control
## Civilization-picker shown after the world is generated.
##
## Renders a static mini-map from the freshly-generated tile data,
## overlays one coloured marker per civ at its spawn point, and lets the
## player click a marker (or its row in the list) to pick which people
## they will observe. A confirmed pick stores [member RunConfig.player_civ_id]
## and transitions to [code]res://scenes/Main.tscn[/code].

const Biome := preload("res://scripts/autoload/StubSim.gd").Biome

const BIOME_PIXEL := {
	0: Color(0.18, 0.32, 0.55),  # Ocean
	1: Color(0.85, 0.79, 0.55),  # Coast
	2: Color(0.55, 0.78, 0.45),  # Plains
	3: Color(0.20, 0.45, 0.25),  # Forest
	4: Color(0.55, 0.50, 0.30),  # Hills
	5: Color(0.45, 0.42, 0.40),  # Mountain
	6: Color(0.90, 0.80, 0.45),  # Desert
	7: Color(0.85, 0.92, 0.95),  # Tundra
}

const MARKER_SIZE := 14.0
const MARKER_RING := 3.0

@onready var _minimap: TextureRect = %Minimap
@onready var _marker_layer: Control = %MarkerLayer
@onready var _civ_list: VBoxContainer = %CivList
@onready var _confirm_button: Button = %ConfirmButton
@onready var _back_button: Button = %BackButton
@onready var _detail_name: Label = %DetailName
@onready var _detail_biome: Label = %DetailBiome
@onready var _detail_population: Label = %DetailPopulation

var _civs: Array = []
var _selected_id: int = -1
var _markers: Dictionary = {}
var _list_buttons: Dictionary = {}


func _ready() -> void:
	_civs = GameState.get_civs()
	_render_minimap()
	_marker_layer.draw.connect(_draw_markers)
	_marker_layer.gui_input.connect(_on_marker_input)
	_populate_civ_list()
	_confirm_button.pressed.connect(_on_confirm)
	_back_button.pressed.connect(_on_back)
	_confirm_button.disabled = true
	if not _civs.is_empty():
		_select_civ(int(_civs[0].id))


func _render_minimap() -> void:
	var dims: Vector2i = GameState.dims()
	if dims.x <= 0 or dims.y <= 0:
		return
	var img := Image.create(dims.x, dims.y, false, Image.FORMAT_RGBA8)
	for y in dims.y:
		for x in dims.x:
			var biome: int = GameState.tile_biome(x, y)
			var col: Color = BIOME_PIXEL.get(biome, Color.MAGENTA)
			# Subtle elevation shading so plains aren't a flat block.
			var e: float = float(GameState.tile_elevation(x, y)) / 255.0
			col = col.lerp(Color.BLACK, clampf((1.0 - e) * 0.25, 0.0, 0.25))
			img.set_pixel(x, y, col)
	_minimap.texture = ImageTexture.create_from_image(img)


func _populate_civ_list() -> void:
	for civ in _civs:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = "%s   (spawn %d, %d)" % [civ.name, int(civ.spawn_x), int(civ.spawn_y)]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_color_override("font_color", _civ_color(int(civ.id)))
		btn.custom_minimum_size = Vector2(0, 32)
		btn.pressed.connect(_select_civ.bind(int(civ.id)))
		_civ_list.add_child(btn)
		_list_buttons[int(civ.id)] = btn


func _civ_color(civ_id: int) -> Color:
	if civ_id < 0 or civ_id >= _civs.size():
		return Color.WHITE
	return _civs[civ_id].color


func _draw_markers() -> void:
	var dims: Vector2i = GameState.dims()
	if dims.x <= 0 or dims.y <= 0 or _civs.is_empty():
		return
	var rect: Rect2 = _minimap.get_rect()
	for civ in _civs:
		var p: Vector2 = _world_to_minimap(int(civ.spawn_x), int(civ.spawn_y), dims, rect)
		var col: Color = civ.color
		_marker_layer.draw_circle(p, MARKER_SIZE, col)
		_marker_layer.draw_arc(p, MARKER_SIZE + MARKER_RING, 0.0, TAU, 32, Color.WHITE, 2.0)
		if int(civ.id) == _selected_id:
			_marker_layer.draw_arc(p, MARKER_SIZE + MARKER_RING * 2.5, 0.0, TAU, 32, Color.WHITE, 3.0)


func _world_to_minimap(tx: int, ty: int, dims: Vector2i, rect: Rect2) -> Vector2:
	var u: float = float(tx) / float(dims.x)
	var v: float = float(ty) / float(dims.y)
	return rect.position + Vector2(u * rect.size.x, v * rect.size.y)


func _on_marker_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var dims: Vector2i = GameState.dims()
	if dims.x <= 0 or dims.y <= 0 or _civs.is_empty():
		return
	var rect: Rect2 = _minimap.get_rect()
	var best_id: int = -1
	var best_dist: float = MARKER_SIZE * 1.8
	for civ in _civs:
		var p: Vector2 = _world_to_minimap(int(civ.spawn_x), int(civ.spawn_y), dims, rect)
		var d: float = p.distance_to(mb.position)
		if d < best_dist:
			best_dist = d
			best_id = int(civ.id)
	if best_id != -1:
		_select_civ(best_id)


func _select_civ(id: int) -> void:
	_selected_id = id
	_confirm_button.disabled = false
	_marker_layer.queue_redraw()
	for cid in _list_buttons:
		(_list_buttons[cid] as Button).button_pressed = (cid == id)
	_update_detail_panel(id)


func _update_detail_panel(id: int) -> void:
	if id < 0 or id >= _civs.size():
		_detail_name.text = ""
		_detail_biome.text = ""
		_detail_population.text = ""
		return
	var civ: Dictionary = _civs[id]
	_detail_name.text = civ.name
	_detail_name.add_theme_color_override("font_color", _civ_color(id))
	var biome: int = GameState.tile_biome(int(civ.spawn_x), int(civ.spawn_y))
	_detail_biome.text = "Homeland: %s" % _biome_name(biome)
	var pop := 0
	for npc in GameState.get_npcs():
		if int(npc.civ_id) == id and npc.alive:
			pop += 1
	var houses := 0
	for b in GameState.get_buildings():
		if int(b.civ_id) == id:
			houses += 1
	_detail_population.text = "Population: %d   ·   Buildings: %d" % [pop, houses]


func _biome_name(b: int) -> String:
	match b:
		0: return "Ocean"
		1: return "Coast"
		2: return "Plains"
		3: return "Forest"
		4: return "Hills"
		5: return "Mountain"
		6: return "Desert"
		7: return "Tundra"
		_: return "Unknown"


func _on_confirm() -> void:
	if _selected_id < 0:
		return
	RunConfig.player_civ_id = _selected_id
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_back() -> void:
	# Throw away the generated world so going back to NewGame doesn't
	# silently keep the old terrain.
	GameState.clear_world()
	get_tree().change_scene_to_file("res://scenes/NewGame.tscn")
