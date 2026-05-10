extends Node2D
## Single test NPC for end-to-end animation/integration check.
##
## Loads `walk_south.png` (8 horizontally-tiled frames, 24×40 each) into a
## Sprite2D, cycles the frame on a timer, and walks the world rect in a
## clockwise square so we exercise every cardinal direction. The sprite
## sheet only contains south-facing frames for now, so all directions
## reuse the same row — that's a deliberate placeholder until the user
## ships N/E/W sprites.
##
## Movement is independent of the sim's per-tick advance — it lives in
## continuous _process time so the walk reads as smooth even when the
## sim is paused.

const SHEET_PATH := "res://assets/npcs/test_walker/walk_south.png"
const FRAME_W := 24
const FRAME_H := 40
const FRAME_COUNT := 8
const ANIM_FPS := 8.0
const SPEED_PX := 28.0  # pixels/sec — feels gentle at TILE_PX=32

# Square route in pixel space, looped indefinitely. Filled in by setup().
var _route: Array = []
var _route_idx: int = 0
var _anim_t: float = 0.0
var _sprite: Sprite2D
var _moving: bool = true

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex: Texture2D = load(SHEET_PATH) as Texture2D
	if tex == null:
		push_warning("[TestNpc] sheet not loaded: %s" % SHEET_PATH)
		return
	_sprite.texture = tex
	_sprite.hframes = FRAME_COUNT
	_sprite.vframes = 1
	_sprite.frame = 0
	# Place the sprite so its feet sit at this node's origin (anchor at
	# bottom-centre). That way `position` aligns with a tile centre and
	# the body stands on top.
	_sprite.position = Vector2(-FRAME_W * 0.5, -FRAME_H + (FRAME_H - 32) * 0.5 - 4)
	add_child(_sprite)

## Configure the patrol route in pixel space. `world_rect` is the full
## map rect; the NPC walks a small square centred in the view so it's
## visible at the default starting zoom without scrolling.
func setup(world_rect: Rect2) -> void:
	var center := world_rect.position + world_rect.size * 0.5
	var radius: Vector2 = world_rect.size * 0.08  # ~8% of map → ~10 tiles per side
	_route = [
		center + Vector2(-radius.x, -radius.y),
		center + Vector2( radius.x, -radius.y),
		center + Vector2( radius.x,  radius.y),
		center + Vector2(-radius.x,  radius.y),
	]
	position = _route[0]
	_route_idx = 1

func _process(delta: float) -> void:
	if _route.is_empty() or _sprite == null:
		return
	# Advance walk-cycle frame.
	_anim_t += delta
	var f := int(_anim_t * ANIM_FPS) % FRAME_COUNT
	_sprite.frame = f
	# Step toward next waypoint.
	var target: Vector2 = _route[_route_idx]
	var to_target: Vector2 = target - position
	var step := SPEED_PX * delta
	if to_target.length() <= step:
		position = target
		_route_idx = (_route_idx + 1) % _route.size()
	else:
		position += to_target.normalized() * step
