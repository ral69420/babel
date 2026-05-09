extends Node2D
## Renders the simulation tile grid.
##
## v0 implementation: just paints coloured squares per biome via `_draw`. Once
## tile-art is hand-authored we'll switch this to a [TileMap]. The render
## path stays read-only over the sim so we never accidentally introduce
## non-determinism by writing back into it.

const BIOME_COLORS := {
	0: Color(0.10, 0.18, 0.30),  # Ocean
	1: Color(0.30, 0.45, 0.55),  # Coast
	2: Color(0.65, 0.78, 0.45),  # Plains
	3: Color(0.18, 0.42, 0.22),  # Forest
	4: Color(0.55, 0.55, 0.40),  # Hills
	5: Color(0.45, 0.40, 0.40),  # Mountain
	6: Color(0.85, 0.78, 0.50),  # Desert
	7: Color(0.85, 0.88, 0.92),  # Tundra
}

const RIVER_COLOR := Color(0.20, 0.45, 0.75)
const RUIN_COLOR  := Color(0.30, 0.30, 0.30)

const TILE_SIZE := 4.0

var _state: Node = null
var _dims: Vector2i = Vector2i.ZERO

func bind(state: Node) -> void:
	_state = state
	_dims = state.dims()
	queue_redraw()

func _draw() -> void:
	if _state == null:
		return
	if _dims.x <= 0 or _dims.y <= 0:
		return
	for y in _dims.y:
		for x in _dims.x:
			var b: int = _state.tile_biome(x, y)
			var c: Color = BIOME_COLORS.get(b, Color(1.0, 0.0, 1.0))
			draw_rect(Rect2(Vector2(x * TILE_SIZE, y * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE)), c, true)
			var tags: int = _state.tile_tags(x, y)
			# Bit 2 = RIVER (matches babel_sim::world::tile_tags::RIVER).
			if (tags & 0x04) != 0:
				draw_rect(Rect2(Vector2(x * TILE_SIZE, y * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE)), RIVER_COLOR, true)
			# Bit 0 = RUIN.
			if (tags & 0x01) != 0:
				draw_circle(Vector2(x * TILE_SIZE + TILE_SIZE * 0.5, y * TILE_SIZE + TILE_SIZE * 0.5), TILE_SIZE * 0.3, RUIN_COLOR)
