class_name DayNightCycle
extends Node

signal phase_changed(phase: int, phase_name: String)

enum Phase { DAY, DUSK, NIGHT, TWILIGHT }

const SEVENTH_DURATION := 60.0
const CYCLE_DURATION := SEVENTH_DURATION * 7.0
const DAY_END := SEVENTH_DURATION * 3.0
const DUSK_END := SEVENTH_DURATION * 4.0
const NIGHT_END := SEVENTH_DURATION * 6.0

# Ambient is a cave floor, not outdoor skylight. Day brightness lives on the
# sun and the entrance leak so walking inside actually gets darker.
const NIGHT_AMBIENT_ENERGY := 0.16
const NIGHT_SUN_ENERGY := 0.32
const NIGHT_ENTRANCE_FILL_ENERGY := 0.42
const NIGHT_BRIGHTNESS := 0.90
const NIGHT_CONTRAST := 1.16
const NIGHT_SATURATION := 0.82
const NIGHT_AMBIENT_COLOR := Color("#354247")
const NIGHT_BACKGROUND_COLOR := Color("#020304")
const NIGHT_ENTRANCE_FILL_COLOR := Color("#77866a")

const DAY_AMBIENT_ENERGY := 0.18
const DAY_SUN_ENERGY := 1.15
const DAY_ENTRANCE_FILL_ENERGY := 0.95
const DAY_BRIGHTNESS := 1.04
const DAY_CONTRAST := 1.08
const DAY_SATURATION := 0.96
const DAY_AMBIENT_COLOR := Color("#806f91")
const DAY_BACKGROUND_COLOR := Color("#403847")
const DAY_ENTRANCE_FILL_COLOR := Color("#b39a68")

var environment: Environment
var sun: DirectionalLight3D
var entrance_fill: OmniLight3D
var cycle_time := DUSK_END + SEVENTH_DURATION # Middle of the night phase.
var current_phase := -1
var daylight_strength := 0.0


func setup(
	target_environment: Environment,
	target_sun: DirectionalLight3D,
	target_entrance_fill: OmniLight3D
) -> void:
	environment = target_environment
	sun = target_sun
	entrance_fill = target_entrance_fill
	_apply_cycle_time()


func _process(delta: float) -> void:
	if environment == null or sun == null or entrance_fill == null:
		return
	cycle_time = fmod(cycle_time + delta, CYCLE_DURATION)
	_apply_cycle_time()


func set_phase(phase: int) -> void:
	match phase:
		Phase.DAY:
			cycle_time = DAY_END * 0.5
		Phase.DUSK:
			cycle_time = DAY_END + SEVENTH_DURATION * 0.5
		Phase.NIGHT:
			cycle_time = DUSK_END + SEVENTH_DURATION
		Phase.TWILIGHT:
			cycle_time = NIGHT_END + SEVENTH_DURATION * 0.5
	_apply_cycle_time()


func get_phase_name() -> String:
	return _phase_name(current_phase)


func get_daylight_strength() -> float:
	return daylight_strength


func _apply_cycle_time() -> void:
	var phase := Phase.DAY
	var daylight := 1.0
	if cycle_time < DAY_END:
		phase = Phase.DAY
		daylight = 1.0
	elif cycle_time < DUSK_END:
		phase = Phase.DUSK
		daylight = 1.0 - (cycle_time - DAY_END) / SEVENTH_DURATION
	elif cycle_time < NIGHT_END:
		phase = Phase.NIGHT
		daylight = 0.0
	else:
		phase = Phase.TWILIGHT
		daylight = (cycle_time - NIGHT_END) / SEVENTH_DURATION

	# Smoothstep makes both horizon transitions gradual. At their midpoints,
	# dusk and twilight have identical brightness by construction.
	daylight = smoothstep(0.0, 1.0, daylight)
	daylight_strength = daylight
	environment.ambient_light_energy = lerpf(NIGHT_AMBIENT_ENERGY, DAY_AMBIENT_ENERGY, daylight)
	environment.ambient_light_color = NIGHT_AMBIENT_COLOR.lerp(DAY_AMBIENT_COLOR, daylight)
	environment.adjustment_brightness = lerpf(NIGHT_BRIGHTNESS, DAY_BRIGHTNESS, daylight)
	environment.adjustment_contrast = lerpf(NIGHT_CONTRAST, DAY_CONTRAST, daylight)
	environment.adjustment_saturation = lerpf(NIGHT_SATURATION, DAY_SATURATION, daylight)
	environment.background_color = NIGHT_BACKGROUND_COLOR.lerp(DAY_BACKGROUND_COLOR, daylight)
	sun.light_energy = lerpf(NIGHT_SUN_ENERGY, DAY_SUN_ENERGY, daylight)
	sun.light_color = Color("#9eafbd").lerp(Color("#ffe0ad"), daylight)
	entrance_fill.light_energy = lerpf(
		NIGHT_ENTRANCE_FILL_ENERGY,
		DAY_ENTRANCE_FILL_ENERGY,
		daylight
	)
	entrance_fill.light_color = NIGHT_ENTRANCE_FILL_COLOR.lerp(
		DAY_ENTRANCE_FILL_COLOR,
		daylight
	)

	if phase != current_phase:
		current_phase = phase
		phase_changed.emit(current_phase, _phase_name(current_phase))


func _phase_name(phase: int) -> String:
	return ["DAY", "DUSK", "NIGHT", "TWILIGHT"][clampi(phase, 0, 3)]
