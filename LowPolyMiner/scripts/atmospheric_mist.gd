class_name AtmosphericMist
extends Node

# Always-on low haze plus softer thickenings. Floor stops it vanishing;
# peak stays below the old sliding-slab mix.
const MIST_DENSITY := 0.95
const MIST_OPACITY := 0.36
const MIST_AMBIENT := 0.10
const MIST_SCALE := 13.0
const MIST_SPEED := 0.16
const MIST_DIRECTION := Vector2(1.0, 0.22)
const MIST_CONTRAST := 0.55
const MIST_DEPTH_FALLOFF := 18.0
const MIST_NEAR_AMOUNT := 0.24
const MIST_FAR_AMOUNT := 0.85
const MIST_BEGIN := 2.6
const SPECKLE_DENSITY := 0.22
const SPECKLE_SIZE := 1.3
const SPECKLE_BRIGHTNESS := 0.40
const SPECKLE_SPEED := 0.07
const SPECKLE_COLOR := Color("#5c6640")
const DAY_MIST_MULTIPLIER := 0.82
const NIGHT_MIST_MULTIPLIER := 1.10
const DAY_MIST_COLOR := Color("#6a7358")
const NIGHT_MIST_COLOR := Color("#4a4552")
const CAVE_MIST_COLOR := Color("#0e100c")
const TRANSITION_MIST_BOOST := 1.16
const FOG_TRANSITION_EASE_POWER := 2.0
const CAVE_SHELL := 3.0
const CAVE_FADE := 8.0

var target_cycle: DayNightCycle
var target_camera: Camera3D
var mine_bounds := AABB()
var mist_material: ShaderMaterial
var applied_daylight := -1.0
var tune: Dictionary = {}


func default_tune() -> Dictionary:
	return {
		"density": MIST_DENSITY,
		"opacity": MIST_OPACITY,
		"ambient": MIST_AMBIENT,
		"scale": MIST_SCALE,
		"speed": MIST_SPEED,
		"contrast": MIST_CONTRAST,
		"depth_falloff": MIST_DEPTH_FALLOFF,
		"near_amount": MIST_NEAR_AMOUNT,
		"far_amount": MIST_FAR_AMOUNT,
		"begin": MIST_BEGIN,
		"speckle_density": SPECKLE_DENSITY,
		"speckle_size": SPECKLE_SIZE,
		"speckle_brightness": SPECKLE_BRIGHTNESS,
		"speckle_speed": SPECKLE_SPEED,
		"day_mul": DAY_MIST_MULTIPLIER,
		"night_mul": NIGHT_MIST_MULTIPLIER,
		"transition_boost": TRANSITION_MIST_BOOST
	}


func setup(camera: Camera3D, cycle: DayNightCycle) -> void:
	target_camera = camera
	target_cycle = cycle
	tune = default_tune()

	mist_material = ShaderMaterial.new()
	mist_material.shader = load("res://shaders/atmospheric_mist.gdshader") as Shader
	mist_material.set_shader_parameter("mist_direction", MIST_DIRECTION)
	mist_material.set_shader_parameter("speckle_color", SPECKLE_COLOR)
	_push_static_tune()

	# Behind the HUD CanvasLayer (0), in front of every 3D pass including RetroFog.
	var layer := CanvasLayer.new()
	layer.name = "AtmosphericMistLayer"
	layer.layer = -1
	layer.follow_viewport_enabled = false
	add_child(layer)

	var rect := ColorRect.new()
	rect.name = "AtmosphericMistPass"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color.WHITE
	rect.material = mist_material
	layer.add_child(rect)

	_upload_camera()
	_push_mine_bounds()
	_apply_daylight(target_cycle.get_daylight_strength())


func set_mine_bounds(aabb: AABB) -> void:
	mine_bounds = aabb
	_push_mine_bounds()
	if mist_material != null:
		_apply_daylight(applied_daylight if applied_daylight >= 0.0 else 0.0)


func _push_mine_bounds() -> void:
	if mist_material == null or mine_bounds.size == Vector3.ZERO:
		return
	mist_material.set_shader_parameter("mine_min", mine_bounds.position)
	mist_material.set_shader_parameter("mine_max", mine_bounds.end)
	mist_material.set_shader_parameter("cave_shell", CAVE_SHELL)
	mist_material.set_shader_parameter("cave_fade", CAVE_FADE)


func _process(_delta: float) -> void:
	if mist_material == null:
		return
	_upload_camera()
	if target_cycle == null:
		return
	var daylight := target_cycle.get_daylight_strength()
	if not is_equal_approx(daylight, applied_daylight):
		_apply_daylight(daylight)


func _upload_camera() -> void:
	if target_camera == null or mist_material == null:
		return
	mist_material.set_shader_parameter(
		"inv_projection_matrix",
		target_camera.get_camera_projection().inverse()
	)
	mist_material.set_shader_parameter("inv_view_matrix", target_camera.global_transform)


func get_tune_value(key: String) -> float:
	return float(tune.get(key, default_tune().get(key, 0.0)))


func set_tune_value(key: String, value: float) -> void:
	tune[key] = value
	_push_static_tune()
	var daylight := applied_daylight
	if daylight < 0.0 and target_cycle != null:
		daylight = target_cycle.get_daylight_strength()
	_apply_daylight(maxf(daylight, 0.0))


func reset_tune() -> void:
	tune = default_tune()
	_push_static_tune()
	var daylight := 0.0
	if target_cycle != null:
		daylight = target_cycle.get_daylight_strength()
	_apply_daylight(daylight)


func store_config(cfg: ConfigFile) -> void:
	for key: String in tune.keys():
		cfg.set_value("mist", key, tune[key])


func load_config(cfg: ConfigFile) -> void:
	if not cfg.has_section("mist"):
		return
	for key: String in default_tune().keys():
		tune[key] = float(cfg.get_value("mist", key, tune[key]))
	_push_static_tune()
	var daylight := 0.0
	if target_cycle != null:
		daylight = target_cycle.get_daylight_strength()
	_apply_daylight(daylight)


func _tunef(key: String, fallback: float) -> float:
	return float(tune.get(key, fallback))


func _push_static_tune() -> void:
	if mist_material == null:
		return
	mist_material.set_shader_parameter("mist_opacity", _tunef("opacity", MIST_OPACITY))
	mist_material.set_shader_parameter("mist_ambient", _tunef("ambient", MIST_AMBIENT))
	mist_material.set_shader_parameter("mist_scale", _tunef("scale", MIST_SCALE))
	mist_material.set_shader_parameter("mist_speed", _tunef("speed", MIST_SPEED))
	mist_material.set_shader_parameter("mist_contrast", _tunef("contrast", MIST_CONTRAST))
	mist_material.set_shader_parameter("mist_depth_falloff", _tunef("depth_falloff", MIST_DEPTH_FALLOFF))
	mist_material.set_shader_parameter("mist_near_amount", _tunef("near_amount", MIST_NEAR_AMOUNT))
	mist_material.set_shader_parameter("mist_far_amount", _tunef("far_amount", MIST_FAR_AMOUNT))
	mist_material.set_shader_parameter("mist_begin", _tunef("begin", MIST_BEGIN))
	mist_material.set_shader_parameter("speckle_density", _tunef("speckle_density", SPECKLE_DENSITY))
	mist_material.set_shader_parameter("speckle_size", _tunef("speckle_size", SPECKLE_SIZE))
	mist_material.set_shader_parameter("speckle_speed", _tunef("speckle_speed", SPECKLE_SPEED))


func _apply_daylight(daylight: float) -> void:
	if mist_material == null:
		return
	applied_daylight = clampf(daylight, 0.0, 1.0)
	var fog_daylight := 1.0 - pow(1.0 - applied_daylight, FOG_TRANSITION_EASE_POWER)
	var transition_axis := 4.0 * applied_daylight * (1.0 - applied_daylight)
	var transition_peak := smoothstep(0.0, 1.0, transition_axis)
	var night_mul := _tunef("night_mul", NIGHT_MIST_MULTIPLIER)
	var day_mul := _tunef("day_mul", DAY_MIST_MULTIPLIER)
	var boost := _tunef("transition_boost", TRANSITION_MIST_BOOST)
	var cycle_mul := lerpf(night_mul, day_mul, fog_daylight)
	cycle_mul = lerpf(cycle_mul, cycle_mul * boost, transition_peak)
	mist_material.set_shader_parameter("mist_density", _tunef("density", MIST_DENSITY) * cycle_mul)
	mist_material.set_shader_parameter(
		"mist_color",
		NIGHT_MIST_COLOR.lerp(DAY_MIST_COLOR, fog_daylight)
	)
	mist_material.set_shader_parameter("cave_mist_color", CAVE_MIST_COLOR)
	_push_mine_bounds()
	var speckle_base := _tunef("speckle_brightness", SPECKLE_BRIGHTNESS)
	mist_material.set_shader_parameter(
		"speckle_brightness",
		lerpf(speckle_base * 1.15, speckle_base * 0.88, fog_daylight)
	)
