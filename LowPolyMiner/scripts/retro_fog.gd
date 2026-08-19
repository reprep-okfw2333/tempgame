class_name RetroFog
extends Node

# Texture-free distance fog inspired by the PS2 Graphics Synthesizer: one fog
# coefficient blends the scene toward a far color, then a static 4x4 ordered
# pattern breaks up the limited number of coefficient steps.
const DAY_FOG_BEGIN := 5.0
const DAY_FOG_END := 38.0
const DAY_FOG_CURVE := 0.85
const DAY_FOG_INTENSITY := 0.88
const DAY_FOG_COLOR := Color("#718451")
const DAY_RETRO_MIX := 0.70

const NIGHT_FOG_BEGIN := 18.0
const NIGHT_FOG_END := 60.0
const NIGHT_FOG_CURVE := 1.0
const NIGHT_FOG_INTENSITY := 0.08
const NIGHT_FOG_COLOR := Color("#17131d")
const NIGHT_RETRO_MIX := 0.0

# Visible dark haze for inside the mountain. Darker than cave rock so it
# reads as depth, not a lamp. Strong enough to see. Not the Night 0.08 trace.
const CAVE_FOG_BEGIN := 6.0
const CAVE_FOG_END := 28.0
const CAVE_FOG_CURVE := 0.90
const CAVE_FOG_INTENSITY := 0.58
const CAVE_FOG_COLOR := Color("#0b0d09")
const CAVE_RETRO_MIX := 0.40
const CAVE_SHELL := 3.0
const CAVE_FADE := 8.0

const FOG_BAND_COUNT := 16.0
# Lighting changes linearly between its approved endpoints, but applying that
# same weight to range, strength, color, and banding at once made both
# transition midpoints read as if fog had switched off. This ease preserves
# the exact Day/Night endpoints while keeping Dusk and Twilight visibly foggy.
const FOG_TRANSITION_EASE_POWER := 2.0
# Transition phases deliberately crest above both constant endpoints. This
# hides the streamed-world horizon at Dusk/Twilight without making Day milkier
# or changing the approved faint Night trace.
const TRANSITION_FOG_INTENSITY := 0.96

var target_cycle: DayNightCycle
var target_camera: Camera3D
var mine_bounds := AABB()
var fog_material: ShaderMaterial
var applied_daylight := -1.0
var day_intensity := DAY_FOG_INTENSITY
var night_intensity := NIGHT_FOG_INTENSITY
var transition_intensity := TRANSITION_FOG_INTENSITY


func setup(camera: Camera3D, cycle: DayNightCycle) -> void:
	target_camera = camera
	target_cycle = cycle
	var fog_pass := MeshInstance3D.new()
	fog_pass.name = "RetroFogPass"
	fog_pass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fog_pass.extra_cull_margin = 16384.0

	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.flip_faces = true
	fog_pass.mesh = quad

	fog_material = ShaderMaterial.new()
	fog_material.shader = load("res://shaders/retro_fog.gdshader") as Shader
	fog_material.render_priority = 127
	fog_material.set_shader_parameter("fog_band_count", FOG_BAND_COUNT)
	fog_material.set_shader_parameter("cave_fog_color", CAVE_FOG_COLOR)
	fog_material.set_shader_parameter("cave_fog_intensity", CAVE_FOG_INTENSITY)
	fog_material.set_shader_parameter("cave_shell", CAVE_SHELL)
	fog_material.set_shader_parameter("cave_fade", CAVE_FADE)
	fog_pass.material_override = fog_material
	target_camera.add_child(fog_pass)
	_push_mine_bounds()
	_apply_daylight(target_cycle.get_daylight_strength())


func set_mine_bounds(aabb: AABB) -> void:
	mine_bounds = aabb
	_push_mine_bounds()
	if fog_material != null:
		_refresh()


func _push_mine_bounds() -> void:
	if fog_material == null or mine_bounds.size == Vector3.ZERO:
		return
	fog_material.set_shader_parameter("mine_min", mine_bounds.position)
	fog_material.set_shader_parameter("mine_max", mine_bounds.end)


func _process(_delta: float) -> void:
	if target_cycle == null or fog_material == null:
		return
	var daylight := target_cycle.get_daylight_strength()
	if not is_equal_approx(daylight, applied_daylight):
		_apply_daylight(daylight)


func _apply_daylight(daylight: float) -> void:
	applied_daylight = clampf(daylight, 0.0, 1.0)
	var fog_daylight := 1.0 - pow(1.0 - applied_daylight, FOG_TRANSITION_EASE_POWER)
	var transition_axis := 4.0 * applied_daylight * (1.0 - applied_daylight)
	var transition_peak := smoothstep(0.0, 1.0, transition_axis)
	var base_intensity := lerpf(night_intensity, day_intensity, fog_daylight)
	var fog_intensity := lerpf(base_intensity, transition_intensity, transition_peak)
	fog_material.set_shader_parameter(
		"fog_begin",
		lerpf(NIGHT_FOG_BEGIN, DAY_FOG_BEGIN, fog_daylight)
	)
	fog_material.set_shader_parameter(
		"fog_end",
		lerpf(NIGHT_FOG_END, DAY_FOG_END, fog_daylight)
	)
	fog_material.set_shader_parameter(
		"fog_curve",
		lerpf(NIGHT_FOG_CURVE, DAY_FOG_CURVE, fog_daylight)
	)
	fog_material.set_shader_parameter("fog_intensity", fog_intensity)
	fog_material.set_shader_parameter(
		"fog_color",
		NIGHT_FOG_COLOR.lerp(DAY_FOG_COLOR, fog_daylight)
	)
	fog_material.set_shader_parameter(
		"retro_mix",
		lerpf(NIGHT_RETRO_MIX, DAY_RETRO_MIX, fog_daylight)
	)
	fog_material.set_shader_parameter("cave_fog_color", CAVE_FOG_COLOR)
	fog_material.set_shader_parameter("cave_fog_intensity", CAVE_FOG_INTENSITY)
	_push_mine_bounds()


func get_tune_value(key: String) -> float:
	match key:
		"day_intensity":
			return day_intensity
		"night_intensity":
			return night_intensity
		"transition_intensity":
			return transition_intensity
		_:
			return 0.0


func set_tune_value(key: String, value: float) -> void:
	match key:
		"day_intensity":
			day_intensity = value
		"night_intensity":
			night_intensity = value
		"transition_intensity":
			transition_intensity = value
	_refresh()


func reset_tune() -> void:
	day_intensity = DAY_FOG_INTENSITY
	night_intensity = NIGHT_FOG_INTENSITY
	transition_intensity = TRANSITION_FOG_INTENSITY
	_refresh()


func store_config(cfg: ConfigFile) -> void:
	cfg.set_value("retro", "day_intensity", day_intensity)
	cfg.set_value("retro", "night_intensity", night_intensity)
	cfg.set_value("retro", "transition_intensity", transition_intensity)


func load_config(cfg: ConfigFile) -> void:
	if not cfg.has_section("retro"):
		return
	day_intensity = float(cfg.get_value("retro", "day_intensity", DAY_FOG_INTENSITY))
	night_intensity = float(cfg.get_value("retro", "night_intensity", NIGHT_FOG_INTENSITY))
	transition_intensity = float(cfg.get_value("retro", "transition_intensity", TRANSITION_FOG_INTENSITY))
	_refresh()


func _refresh() -> void:
	if fog_material == null:
		return
	var daylight := 0.0
	if target_cycle != null:
		daylight = target_cycle.get_daylight_strength()
	_apply_daylight(daylight)
