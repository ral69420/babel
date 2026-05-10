extends Node2D
## Renders all sim buildings as Sprite2D + progress-bar pairs.
##
## Driven by [BabelSim] via the [GameState] autoload. Each frame we sync
## the on-screen pool with `building_count()` and update sprite stage
## textures + progress bars in place. Pool grows; never shrinks (cheap
## reuse — completed buildings stay rendered).
##
## Five textures are loaded once at `_ready`, one per
## [enum babel_sim::entity::BuildingStage] index.
##
##   stage 0  Foundation
##   stage 1  Frame
##   stage 2  Walls
##   stage 3  Roof
##   stage 4  Complete   (no progress bar)

const TILE_PX := 32  ## Same constant as WorldView; one tile = 32 image px.

# Each child = one Sprite2D + a small ProgressBar layered above.
class _Slot:
	extends RefCounted
	var sprite: Sprite2D
	var bar: ColorRect
	var bar_bg: ColorRect

# Loaded once at `_ready`. Indexed by stage.
var _stage_textures_64: Array[Texture2D] = []
var _stage_textures_32: Array[Texture2D] = []

var _state: Node = null
# Array of pooled `_Slot` instances.
var _slots: Array = []

func _ready() -> void:
	_load_stage_textures()
	z_index = 5  # above the world map sprite, below NPCs

func bind(state: Node) -> void:
	_state = state

func _process(_delta: float) -> void:
	if _state == null or not _state.sim_ready:
		return
	_sync_pool()

# ----- internals -----

const _STAGE_NAMES := ["foundation", "frame", "walls", "roof", "complete"]

func _load_stage_textures() -> void:
	for n in _STAGE_NAMES:
		var path64 := "res://assets/buildings/house/stage_%s_64.png" % n
		var path32 := "res://assets/buildings/house/stage_%s_32.png" % n
		var tex64: Texture2D = load(path64) as Texture2D
		var tex32: Texture2D = load(path32) as Texture2D
		_stage_textures_64.append(tex64)
		_stage_textures_32.append(tex32)

func _ensure_slot_count(n: int) -> void:
	while _slots.size() < n:
		var slot := _Slot.new()
		slot.sprite = Sprite2D.new()
		slot.sprite.centered = true
		slot.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(slot.sprite)
		# Progress bar = small white-bordered yellow rect above the sprite.
		slot.bar_bg = ColorRect.new()
		slot.bar_bg.color = Color(0.05, 0.05, 0.08, 0.85)
		slot.bar_bg.size = Vector2(36, 5)
		slot.bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot.bar_bg)
		slot.bar = ColorRect.new()
		slot.bar.color = Color(1.0, 0.82, 0.32, 1.0)
		slot.bar.size = Vector2(0, 5)
		slot.bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot.bar)
		_slots.append(slot)

func _sync_pool() -> void:
	var n := int(_state.building_count())
	_ensure_slot_count(n)
	# First, hide everything past the live count.
	for i in range(_slots.size()):
		var s: _Slot = _slots[i]
		if i >= n:
			s.sprite.visible = false
			s.bar.visible = false
			s.bar_bg.visible = false
			continue
		var pos: Vector2i = _state.building_pos(i)
		if pos.x < 0:
			s.sprite.visible = false
			s.bar.visible = false
			s.bar_bg.visible = false
			continue
		var stage: int = int(_state.building_stage(i))
		stage = clamp(stage, 0, _stage_textures_64.size() - 1)
		s.sprite.texture = _stage_textures_64[stage]
		# Anchor the sprite so that the bottom-centre of the 64px tex
		# sits at the bottom-centre of the tile, making it look planted.
		# Tile origin at (pos.x*32, pos.y*32) → bottom-centre =
		# (pos.x*32 + 16, pos.y*32 + 32). Sprite is 64px tall so its
		# centre needs to be 32px above that (i.e. at pos.y*32 + 0).
		var bottom_centre := Vector2(
			pos.x * TILE_PX + TILE_PX * 0.5,
			pos.y * TILE_PX + TILE_PX
		)
		# 64-px sprite centred on the bottom-centre point would put its
		# top 32 px above the tile.
		s.sprite.position = bottom_centre - Vector2(0, 32)
		s.sprite.visible = true
		# Progress bar above the roof, only while in-progress.
		var pct: int = int(_state.building_progress_pct(i))
		var bar_visible := stage < 4 and pct < 100
		s.bar_bg.visible = bar_visible
		s.bar.visible = bar_visible
		if bar_visible:
			var bar_pos := bottom_centre - Vector2(18, 76)
			s.bar_bg.position = bar_pos
			s.bar.position = bar_pos
			s.bar.size = Vector2(36.0 * float(pct) * 0.01, 5.0)
