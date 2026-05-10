extends Node
## Day / night cycle driver.
##
## Owns the wall-clock that ticks one full day every [DAY_LENGTH_SECS]
## (default 5 minutes). Each frame it interpolates between four hand-tuned
## "moods" — dawn, day, dusk, night — and pushes the result into the
## [WorldEnvironment], the sun [DirectionalLight3D] and any registered
## listeners (e.g. fireflies).
##
## This is intentionally an autoload (singleton) so any scene can read
## the current phase via [is_night] / [phase_name] / [day_progress] without
## hunting for a node, and so the cycle keeps running across scene
## changes in case we ever fade between menu / world.

signal phase_changed(new_phase: String)

const DAY_LENGTH_SECS := 300.0   ## 5 minutes per full day/night cycle.

## Cycle phases — each takes a quarter of the day. Boundaries at
## 0.0  (dawn start) → 0.25 (day start) → 0.5 (dusk start) → 0.75 (night start)
## back to 1.0 (== 0.0).
const PHASE_DAWN  := "dawn"
const PHASE_DAY   := "day"
const PHASE_DUSK  := "dusk"
const PHASE_NIGHT := "night"

## Mood presets. Tuned to feel cozy + melancholic, never garish.
const MOODS := {
	PHASE_DAWN: {
		"sun_color":      Color(1.00, 0.78, 0.92),   # soft pink-purple sunrise
		"sun_energy":     0.55,
		"fill_color":     Color(0.78, 0.70, 0.95),   # purple ambient bounce
		"fill_energy":    0.30,
		"sky_top":        Color(0.42, 0.36, 0.62),
		"sky_horizon":    Color(0.92, 0.65, 0.78),
		"ground_horizon": Color(0.55, 0.45, 0.55),
		"ground_bottom":  Color(0.18, 0.18, 0.22),
		"ambient":        Color(0.62, 0.55, 0.78),
		"ambient_energy": 0.45,
		"fog_color":      Color(0.78, 0.62, 0.78),
		"sun_pitch_deg":  -8.0,    # low, just over horizon
	},
	PHASE_DAY: {
		"sun_color":      Color(1.00, 0.97, 0.88),   # warm white
		"sun_energy":     1.20,
		"fill_color":     Color(0.78, 0.86, 1.00),
		"fill_energy":    0.45,
		"sky_top":        Color(0.42, 0.60, 0.85),
		"sky_horizon":    Color(0.74, 0.83, 0.92),
		"ground_horizon": Color(0.50, 0.55, 0.50),
		"ground_bottom":  Color(0.18, 0.22, 0.12),
		"ambient":        Color(0.62, 0.68, 0.74),
		"ambient_energy": 0.55,
		"fog_color":      Color(0.74, 0.83, 0.92),
		"sun_pitch_deg":  -55.0,   # high noon-ish
	},
	PHASE_DUSK: {
		"sun_color":      Color(1.00, 0.72, 0.60),   # rose / amber
		"sun_energy":     0.65,
		"fill_color":     Color(0.95, 0.62, 0.70),
		"fill_energy":    0.35,
		"sky_top":        Color(0.36, 0.28, 0.52),
		"sky_horizon":    Color(0.98, 0.55, 0.55),
		"ground_horizon": Color(0.45, 0.30, 0.35),
		"ground_bottom":  Color(0.14, 0.12, 0.16),
		"ambient":        Color(0.78, 0.55, 0.62),
		"ambient_energy": 0.40,
		"fog_color":      Color(0.92, 0.58, 0.62),
		"sun_pitch_deg":  -8.0,
	},
	PHASE_NIGHT: {
		"sun_color":      Color(0.62, 0.68, 0.95),   # moonlight
		"sun_energy":     0.18,
		"fill_color":     Color(0.40, 0.48, 0.78),
		"fill_energy":    0.18,
		"sky_top":        Color(0.05, 0.05, 0.14),
		"sky_horizon":    Color(0.10, 0.12, 0.24),
		"ground_horizon": Color(0.06, 0.08, 0.12),
		"ground_bottom":  Color(0.02, 0.02, 0.05),
		"ambient":        Color(0.20, 0.26, 0.46),
		"ambient_energy": 0.22,
		"fog_color":      Color(0.10, 0.14, 0.26),
		"sun_pitch_deg":  -130.0,   # below horizon → moonlight from opposite side
	},
}

const _PHASE_ORDER: Array = [PHASE_DAWN, PHASE_DAY, PHASE_DUSK, PHASE_NIGHT]

var _time_in_day: float = 0.25 * DAY_LENGTH_SECS   ## start at sunrise → day
var _phase: String = PHASE_DAY

## Optional bindings set up by [Main.gd] once the world is built.
var _world_environment: WorldEnvironment = null
var _sun: DirectionalLight3D = null
var _fill_light: DirectionalLight3D = null
var _camera_node: Node3D = null

## Listeners that want to react to the cycle (fireflies, etc).
var _phase_listeners: Array[Callable] = []

func _process(delta: float) -> void:
	_time_in_day = fposmod(_time_in_day + delta, DAY_LENGTH_SECS)
	var p: float = _time_in_day / DAY_LENGTH_SECS    # 0..1 across the day

	# Determine current phase + local 0..1 progress within the phase.
	var slot: int = clampi(int(p * 4.0), 0, 3)
	var local_t: float = clamp(p * 4.0 - float(slot), 0.0, 1.0)
	var current_phase: String = _PHASE_ORDER[slot]
	var next_phase: String = _PHASE_ORDER[(slot + 1) % _PHASE_ORDER.size()]

	if current_phase != _phase:
		_phase = current_phase
		phase_changed.emit(_phase)
		for cb in _phase_listeners:
			if cb.is_valid():
				cb.call(_phase)

	# Smooth-step the boundary so transitions don't feel like a step.
	var smooth_t: float = local_t * local_t * (3.0 - 2.0 * local_t)
	var mood_a: Dictionary = MOODS[current_phase]
	var mood_b: Dictionary = MOODS[next_phase]
	_apply_mood_lerp(mood_a, mood_b, smooth_t)

func _apply_mood_lerp(a: Dictionary, b: Dictionary, t: float) -> void:
	if _sun:
		_sun.light_color = (a["sun_color"] as Color).lerp(b["sun_color"], t)
		_sun.light_energy = lerpf(a["sun_energy"], b["sun_energy"], t)
		var pitch: float = lerpf(a["sun_pitch_deg"], b["sun_pitch_deg"], t)
		_sun.rotation_degrees = Vector3(pitch, 35.0, 0.0)
	if _fill_light:
		_fill_light.light_color = (a["fill_color"] as Color).lerp(b["fill_color"], t)
		_fill_light.light_energy = lerpf(a["fill_energy"], b["fill_energy"], t)
	if _world_environment and _world_environment.environment:
		var env: Environment = _world_environment.environment
		env.ambient_light_color = (a["ambient"] as Color).lerp(b["ambient"], t)
		env.ambient_light_energy = lerpf(a["ambient_energy"], b["ambient_energy"], t)
		env.fog_light_color = (a["fog_color"] as Color).lerp(b["fog_color"], t)
		_apply_sky_lerp(env, a, b, t)
		_apply_camera_distance_fog(env)

func _apply_sky_lerp(env: Environment, a: Dictionary, b: Dictionary, t: float) -> void:
	if env.sky == null or env.sky.sky_material == null:
		return
	var sky_mat: ProceduralSkyMaterial = env.sky.sky_material as ProceduralSkyMaterial
	if sky_mat == null:
		return
	sky_mat.sky_top_color = (a["sky_top"] as Color).lerp(b["sky_top"], t)
	sky_mat.sky_horizon_color = (a["sky_horizon"] as Color).lerp(b["sky_horizon"], t)
	sky_mat.ground_horizon_color = (a["ground_horizon"] as Color).lerp(b["ground_horizon"], t)
	sky_mat.ground_bottom_color = (a["ground_bottom"] as Color).lerp(b["ground_bottom"], t)

## Camera-distance-driven aerial perspective: when zoomed out the world
## fades into haze on the horizon. Up close the fog disappears so you
## can read tile-level detail. Density curves are mild on purpose.
func _apply_camera_distance_fog(env: Environment) -> void:
	if _camera_node == null:
		env.fog_enabled = false
		return
	# OrbitCamera exposes get_zoom_level(). Fall back to a constant if
	# the node is something else.
	var dist: float = 40.0
	if _camera_node.has_method("get_zoom_level"):
		dist = float(_camera_node.call("get_zoom_level"))
	# Map distance [10..200] → fog density [0..0.04].
	var t: float = clamp((dist - 10.0) / 190.0, 0.0, 1.0)
	env.fog_enabled = true
	env.fog_density = lerpf(0.0, 0.045, t)

# ─── Public API ──────────────────────────────────────────────────────
func bind_world(env: WorldEnvironment, sun: DirectionalLight3D, fill: DirectionalLight3D, camera: Node3D) -> void:
	_world_environment = env
	_sun = sun
	_fill_light = fill
	_camera_node = camera

func register_phase_listener(cb: Callable) -> void:
	_phase_listeners.append(cb)
	if cb.is_valid():
		cb.call(_phase)

func unregister_phase_listener(cb: Callable) -> void:
	_phase_listeners.erase(cb)

func phase_name() -> String:
	return _phase

func is_night() -> bool:
	return _phase == PHASE_NIGHT

## 0..1 progress across the entire day. Useful for HUD clocks.
func day_progress() -> float:
	return _time_in_day / DAY_LENGTH_SECS

## Force the cycle to a specific point — e.g. for "skip to night" debug
## hotkeys or save/load restoration. [t] is in [0, 1).
func set_progress(t: float) -> void:
	_time_in_day = clamp(t, 0.0, 1.0) * DAY_LENGTH_SECS
