class_name SunController extends Node
## Drives sun + moon + physical sky + ambient/fog/star curves off GameClock (A6).
## Night is dark but readable: cold moonlight, deep-blue ambient floor, auto-exposure.
## Warm light stays player-made (canon); the moon and stars are the world's.

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var star_mat: ShaderMaterial

const SUN_WARM := Color(1.0, 0.55, 0.3)
const SUN_WHITE := Color(1.0, 0.96, 0.9)
const AMBIENT_DAY := Color(0.55, 0.6, 0.67)
const AMBIENT_NIGHT := Color(0.1, 0.14, 0.24)

func setup(sun_in: DirectionalLight3D, moon_in: DirectionalLight3D, env_in: Environment, star_mat_in: ShaderMaterial) -> void:
	sun = sun_in
	moon = moon_in
	env = env_in
	star_mat = star_mat_in
	GameClock.time_updated.connect(_on_tick)
	GameClock.phase_changed.connect(func(_p: GameClock.Phase) -> void: _on_tick(0.0))
	_on_tick(0.0)

func _elevation(phase: GameClock.Phase, f: float) -> float:
	match phase:
		GameClock.Phase.DAWN:
			return lerpf(-8.0, 16.0, f)
		GameClock.Phase.DAY:
			return 16.0 + 40.0 * sin(f * PI)
		GameClock.Phase.DUSK:
			return lerpf(16.0, -12.0, f)
		_:
			return lerpf(-12.0, -8.0, f)   # night: sun travels under the world

func _night_amount(phase: GameClock.Phase, f: float) -> float:
	match phase:
		GameClock.Phase.NIGHT:
			return 1.0
		GameClock.Phase.DUSK:
			return smoothstep(0.55, 1.0, f)
		GameClock.Phase.DAWN:
			return 1.0 - smoothstep(0.0, 0.5, f)
		_:
			return 0.0

func _on_tick(f: float) -> void:
	if sun == null:
		return
	var phase: GameClock.Phase = GameClock.current_phase
	var elev: float = _elevation(phase, f)
	var azimuth: float = lerpf(80.0, 280.0, _global_day_fraction(phase, f))
	sun.rotation_degrees = Vector3(-elev, -azimuth, 0)
	var sun_h: float = sin(deg_to_rad(elev))   # -1..1 height factor
	sun.light_energy = clampf(sun_h * 1.7, 0.0, 1.3)
	sun.light_color = SUN_WARM.lerp(SUN_WHITE, clampf(sun_h * 2.8, 0.0, 1.0))

	var night: float = _night_amount(phase, f)
	moon.light_energy = 0.28 * night
	moon.visible = night > 0.01
	if star_mat:
		star_mat.set_shader_parameter("night_amount", night)

	# Ambient floor keeps dark scenes readable — deep blue, never zero.
	env.ambient_light_color = AMBIENT_DAY.lerp(AMBIENT_NIGHT, night)
	env.ambient_light_energy = lerpf(clampf(sun.light_energy * 0.55, 0.22, 0.65), 0.16, night)
	env.fog_light_color = env.ambient_light_color.darkened(0.25)
	env.volumetric_fog_albedo = Color(0.85, 0.88, 0.92).lerp(Color(0.5, 0.58, 0.7), night)

	# Interior daylight-spill lights track the sun; interiors go black at night (Rule 7)
	# unless the player flips the switches they earned.
	var spill_energy: float = 0.55 * clampf(sun.light_energy, 0.0, 1.0)
	for l in get_tree().get_nodes_in_group("spill_lights"):
		l.light_energy = spill_energy

func _global_day_fraction(phase: GameClock.Phase, f: float) -> float:
	match phase:
		GameClock.Phase.DAWN:
			return f * 0.12
		GameClock.Phase.DAY:
			return 0.12 + f * 0.72
		GameClock.Phase.DUSK:
			return 0.84 + f * 0.16
		_:
			return 0.999
