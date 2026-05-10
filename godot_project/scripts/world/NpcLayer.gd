extends Node2D
## Renders all live sim NPCs as animated Sprite2Ds.
##
## Driven by [BabelSim] via the [GameState] autoload. Pool grows; never
## shrinks. Each frame:
##   1. Update pool size to match `npc_count()`.
##   2. For each NPC, copy `npc_pos()` into a smoothing target.
##   3. Smooth-lerp toward the target each frame so step-to-step jumps
##      from sim ticks read as fluid walking instead of teleporting.
##   4. Cycle the 8-frame walk_south spritesheet on a continuous timer
##      (ANIM_FPS Hz). All NPCs share the same animation phase — cheap
##      and reads fine in mass.
##   5. Children (`npc_state == "child"`) render at scale 0.6.
##   6. Pregnant women get a subtle yellow tint.
##
## The single-direction sprite (south-facing) is intentional — see
## TestNpc.gd. We'll add full 4-direction sheets when the user ships them.

const TILE_PX := 32

const SHEET_PATH := "res://assets/npcs/test_walker/walk_south.png"
const FRAME_W := 24
const FRAME_H := 40
const FRAME_COUNT := 8
const ANIM_FPS := 6.0

# How fast a sprite drifts toward its sim-given tile centre.
# Higher = snappier. 12 px/tick of smoothing reads as natural steps.
const SMOOTHING := 8.0

class _Slot:
	extends RefCounted
	var sprite: Sprite2D
	# Pixel-space target the sprite is drifting toward.
	var target: Vector2 = Vector2.ZERO
	# Last known sim tile so we only refresh `target` on changes.
	var last_tile: Vector2i = Vector2i(-9999, -9999)

var _state: Node = null
var _slots: Array = []
var _sheet: Texture2D
var _anim_t: float = 0.0

func _ready() -> void:
	_sheet = load(SHEET_PATH) as Texture2D
	z_index = 10  # above buildings layer

func bind(state: Node) -> void:
	_state = state

func _process(delta: float) -> void:
	if _state == null or not _state.sim_ready:
		return
	_anim_t += delta
	_sync_pool(delta)

# ----- internals -----

func _ensure_slot_count(n: int) -> void:
	while _slots.size() < n:
		var slot := _Slot.new()
		slot.sprite = Sprite2D.new()
		slot.sprite.centered = false
		slot.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		slot.sprite.texture = _sheet
		slot.sprite.hframes = FRAME_COUNT
		slot.sprite.vframes = 1
		# Anchor: feet at sprite root. Sprite is FRAME_W×FRAME_H drawn
		# from its top-left (centered=false).
		slot.sprite.offset = Vector2(-FRAME_W * 0.5, -FRAME_H)
		add_child(slot.sprite)
		_slots.append(slot)

func _sync_pool(delta: float) -> void:
	var n := int(_state.npc_count())
	_ensure_slot_count(n)
	# Frame index is shared across all NPCs — cheap mass-animation.
	var anim_frame := int(_anim_t * ANIM_FPS) % FRAME_COUNT
	for i in range(_slots.size()):
		var s: _Slot = _slots[i]
		if i >= n:
			s.sprite.visible = false
			continue
		var pos: Vector2i = _state.npc_pos(i)
		if pos.x < 0:
			s.sprite.visible = false
			continue
		# Centre of tile in pixel space; feet rest there.
		var tile_centre := Vector2(
			pos.x * TILE_PX + TILE_PX * 0.5,
			pos.y * TILE_PX + TILE_PX * 0.5
		)
		if pos != s.last_tile:
			s.target = tile_centre
			s.last_tile = pos
		# Smoothing — drift toward target.
		var sp := s.sprite.global_position
		var to_t := s.target - sp
		var step := SMOOTHING * delta * TILE_PX
		if to_t.length() <= step:
			s.sprite.global_position = s.target
		else:
			s.sprite.global_position = sp + to_t.normalized() * step
		# State / tints / scale.
		var state_str: String = _state.npc_state(i)
		var scale := 1.0
		var tint := Color(1.0, 1.0, 1.0, 1.0)
		if state_str == "child":
			# Children grow gradually 0.6 → 1.0 over their childhood. Use
			# raw age in days; CHILD_DAYS = 14 * 360 = 5040.
			var ad: int = int(_state.npc_age_days(i))
			var t: float = clamp(float(ad) / 5040.0, 0.0, 1.0)
			scale = lerp(0.6, 1.0, t)
		elif state_str == "pregnant":
			tint = Color(1.0, 0.94, 0.78, 1.0)
		s.sprite.scale = Vector2(scale, scale)
		s.sprite.modulate = tint
		s.sprite.frame = anim_frame
		s.sprite.visible = true
