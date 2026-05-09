extends Camera2D
## Pannable, zoomable observer camera.
##
## Babel is an *observation* game — the camera is the player's primary
## interaction. Four input modes, all mappable later:
##
##   - Mouse wheel              → smooth zoom around the cursor
##   - Left / right / middle    → click-and-drag to pan the map
##   - WASD / arrows            → pan with keyboard, scaled by current zoom
##
## The camera clamps itself to the map rect (no flying off into the void).

const ZOOM_MIN := 0.5
const ZOOM_MAX := 8.0
const ZOOM_STEP := 1.15
const KEY_PAN_SPEED := 600.0  # pixels/second at zoom 1.0

var _drag_active: bool = false
var _drag_anchor: Vector2 = Vector2.ZERO
var _world_rect: Rect2 = Rect2()

func _ready() -> void:
	make_current()
	# Default zoom: fit ~half the map vertically so player sees a meaningful
	# chunk but not the whole world. Adjusted again in `set_world_rect`.
	zoom = Vector2(1.0, 1.0)

## Tell the camera the bounds of the rendered world so it can clamp pan.
func set_world_rect(r: Rect2) -> void:
	_world_rect = r
	# Center the camera on the map and pick a starting zoom that frames it
	# nicely in the viewport.
	position = r.position + r.size * 0.5
	var vp := get_viewport_rect().size
	var fit := minf(vp.x / r.size.x, vp.y / r.size.y) * 0.95
	zoom = Vector2(clampf(fit, ZOOM_MIN, ZOOM_MAX), clampf(fit, ZOOM_MIN, ZOOM_MAX))

func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("pan_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("pan_down"):
		dir.y += 1.0
	if Input.is_action_pressed("pan_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("pan_right"):
		dir.x += 1.0
	if dir != Vector2.ZERO:
		# Camera2D.zoom is "magnification" — bigger = zoomed in. Pan distance
		# in world space therefore divides by zoom so keys feel consistent.
		position += dir.normalized() * KEY_PAN_SPEED * delta / zoom.x
		_clamp_position()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_active = mb.pressed
			_drag_anchor = mb.position
	elif event is InputEventMouseMotion and _drag_active:
		var motion: InputEventMouseMotion = event
		# Same zoom-divide rationale as keyboard pan.
		position -= motion.relative / zoom.x
		_clamp_position()

func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var pre_world := get_world_pos(screen_pos)
	var z: float = clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)
	var post_world := get_world_pos(screen_pos)
	# Keep the point under the cursor stationary while zooming.
	position += pre_world - post_world
	_clamp_position()

## Convert a screen-space pixel into a world-space coordinate (factoring zoom
## and current camera position).
func get_world_pos(screen_pos: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	return position + (screen_pos - vp * 0.5) / zoom.x

func _clamp_position() -> void:
	if _world_rect.size == Vector2.ZERO:
		return
	var vp := get_viewport_rect().size
	var half_view := vp * 0.5 / zoom.x
	# When the world is smaller than the view (zoomed out a lot), park the
	# camera at the centre and exit. Otherwise clamp.
	if half_view.x * 2.0 >= _world_rect.size.x and half_view.y * 2.0 >= _world_rect.size.y:
		position = _world_rect.position + _world_rect.size * 0.5
		return
	position.x = clampf(position.x, _world_rect.position.x + half_view.x, _world_rect.end.x - half_view.x)
	position.y = clampf(position.y, _world_rect.position.y + half_view.y, _world_rect.end.y - half_view.y)
