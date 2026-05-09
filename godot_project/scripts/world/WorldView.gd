extends Node2D
## Renders the simulation tile grid as a single Sprite2D-backed image.
##
## We bake the whole map into one [Image] (one image-pixel per tile) and then
## scale it with [member Sprite2D.scale] so a "tile" on screen becomes
## `TILE_PX` pixels. This avoids the 65k draw_rect calls a naïve `_draw`
## implementation would do every frame and lets us pan/zoom via [Camera2D]
## without redrawing.
##
## When tile art is hand-authored we'll swap [member Sprite2D.texture] for a
## [TileMap] keyed off the same biome ids — the bind/state contract stays
## identical.

const TILE_PX := 4   ## Screen pixels per tile at Camera2D zoom = 1.0.

const BIOME_COLORS := {
	0: Color8(28,  46,  76,  255),  # Ocean       — deep navy
	1: Color8(64,  102, 132, 255),  # Coast       — muted teal
	2: Color8(159, 175, 102, 255),  # Plains      — warm olive
	3: Color8(58,  100, 64,  255),  # Forest      — mossy green
	4: Color8(124, 132, 96,  255),  # Hills       — dusty sage
	5: Color8(110, 100, 92,  255),  # Mountain    — slate brown
	6: Color8(206, 184, 124, 255),  # Desert      — pale ochre
	7: Color8(214, 220, 224, 255),  # Tundra      — bone white
}

const RIVER_COLOR := Color8(78,  138, 184, 255)
const RUIN_COLOR  := Color8(72,  64,  76,  255)

var _state: Node = null
var _dims: Vector2i = Vector2i.ZERO
var _sprite: Sprite2D
var _texture: ImageTexture

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)

func bind(state: Node) -> void:
	_state = state
	_dims = state.dims()
	if _dims.x <= 0 or _dims.y <= 0:
		return
	_rebuild_image()
	# One image-pixel = TILE_PX screen pixels at zoom 1.0.
	_sprite.scale = Vector2(TILE_PX, TILE_PX)

## World-space rect occupied by the rendered map (in screen-equivalent px).
func world_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(_dims) * float(TILE_PX))

## Convert a world-space point to integer tile coords.
## Returns `Vector2i(-1, -1)` if outside the map.
func world_to_tile(world_pos: Vector2) -> Vector2i:
	var tx := int(floor(world_pos.x / float(TILE_PX)))
	var ty := int(floor(world_pos.y / float(TILE_PX)))
	if tx < 0 or ty < 0 or tx >= _dims.x or ty >= _dims.y:
		return Vector2i(-1, -1)
	return Vector2i(tx, ty)

func _rebuild_image() -> void:
	var img := Image.create(_dims.x, _dims.y, false, Image.FORMAT_RGBA8)
	for y in _dims.y:
		for x in _dims.x:
			var b: int = _state.tile_biome(x, y)
			var c: Color = BIOME_COLORS.get(b, Color(1.0, 0.0, 1.0))
			var tags: int = _state.tile_tags(x, y)
			# Bit 2 = RIVER (matches babel_sim::world::tile_tags::RIVER).
			# Bit 0 = RUIN. River wins visually if both set.
			if (tags & 0x04) != 0:
				c = RIVER_COLOR
			elif (tags & 0x01) != 0:
				c = RUIN_COLOR
			# Subtle elevation shading so terrain isn't perfectly flat.
			var elev: int = _state.tile_elevation(x, y)
			var shade := (float(elev) - 128.0) / 768.0
			c = Color(
				clamp(c.r + shade, 0.0, 1.0),
				clamp(c.g + shade, 0.0, 1.0),
				clamp(c.b + shade, 0.0, 1.0),
				1.0
			)
			img.set_pixel(x, y, c)
	_texture = ImageTexture.create_from_image(img)
	_sprite.texture = _texture
