extends Node3D
## Civ 6-style orbiting camera for the 3D hex world.
##
## Controls:
##   Mouse wheel     — zoom in/out
##   Middle-drag     — orbit (rotate around pivot)
##   Right-drag      — pan
##   WASD / Arrows   — pan
##   Q / E           — rotate left/right

const MIN_DISTANCE := 5.0
const MAX_DISTANCE := 300.0
const MIN_PITCH := -85.0
const MAX_PITCH := -20.0
const PAN_SPEED := 0.5
const ORBIT_SPEED := 0.3
const ZOOM_STEP := 0.15
const KEY_PAN_SPEED := 30.0

@onready var _camera: Camera3D = $Camera3D

var _distance: float = 40.0
var _yaw: float = 0.0
var _pitch: float = -50.0
var _pivot: Vector3 = Vector3.ZERO
var _dragging_orbit := false
var _dragging_pan := false
var _world_bounds: AABB = AABB()

func _ready() -> void:
	if not _camera:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		add_child(_camera)
	_camera.near = 0.5
	_camera.far = 1000.0
	_camera.fov = 45.0
	_update_transform()

func set_world_bounds(bounds: AABB) -> void:
	_world_bounds = bounds
	_pivot = bounds.get_center()
	_pivot.y = 0.0
	_distance = bounds.size.length() * 0.4
	_update_transform()

func get_zoom_level() -> float:
	return _distance

func _unhandled_input(event: InputEvent) -> void:
	# Zoom
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance * (1.0 - ZOOM_STEP), MIN_DISTANCE)
			_update_transform()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance * (1.0 + ZOOM_STEP), MAX_DISTANCE)
			_update_transform()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging_orbit = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_LEFT:
			# Either mouse button drags the camera. Track which is held so a
			# release of one doesn't cancel a drag started with the other.
			if mb.pressed:
				_dragging_pan = true
			else:
				_dragging_pan = (
					Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
					or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
				)

	# Orbit / Pan with mouse
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging_orbit:
			_yaw -= mm.relative.x * ORBIT_SPEED
			_pitch -= mm.relative.y * ORBIT_SPEED
			_pitch = clampf(_pitch, MIN_PITCH, MAX_PITCH)
			_update_transform()
		elif _dragging_pan:
			var right := _camera.global_transform.basis.x
			# In Godot, Camera3D looks down its local -Z, so basis.z is the
			# camera's *backward* direction. Negate to get true forward.
			var forward := -_camera.global_transform.basis.z
			forward.y = 0.0
			forward = forward.normalized()
			right.y = 0.0
			right = right.normalized()
			var pan_scale: float = _distance * 0.002
			# Mouse-direction = view-direction: drag right → camera moves
			# right, drag down → camera moves backward (away from look dir).
			_pivot += right * mm.relative.x * pan_scale
			_pivot -= forward * mm.relative.y * pan_scale
			_update_transform()

func _process(delta: float) -> void:
	# WASD / Arrow key panning. W = forward, S = back, A = left, D = right,
	# all relative to the camera's current horizontal facing direction.
	var move := Vector2.ZERO
	if Input.is_action_pressed("pan_up"):
		move.y += 1.0   # forward
	if Input.is_action_pressed("pan_down"):
		move.y -= 1.0   # backward
	if Input.is_action_pressed("pan_left"):
		move.x -= 1.0   # left
	if Input.is_action_pressed("pan_right"):
		move.x += 1.0   # right

	if move.length() > 0.0:
		var right := _camera.global_transform.basis.x
		# basis.z is camera-backward; use -basis.z for actual look direction.
		var forward := -_camera.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		right.y = 0.0
		right = right.normalized()
		var speed: float = KEY_PAN_SPEED * delta * (_distance / 40.0)
		_pivot += right * move.x * speed
		_pivot += forward * move.y * speed
		_update_transform()

	# Q/E rotation
	if Input.is_key_pressed(KEY_Q):
		_yaw += 60.0 * delta
		_update_transform()
	if Input.is_key_pressed(KEY_E):
		_yaw -= 60.0 * delta
		_update_transform()

func _update_transform() -> void:
	var pitch_rad := deg_to_rad(_pitch)
	var yaw_rad := deg_to_rad(_yaw)

	var offset := Vector3(
		_distance * cos(pitch_rad) * sin(yaw_rad),
		-_distance * sin(pitch_rad),
		_distance * cos(pitch_rad) * cos(yaw_rad)
	)

	global_position = _pivot + offset
	_camera.global_position = global_position
	_camera.look_at(_pivot, Vector3.UP)
