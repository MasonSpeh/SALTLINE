class_name SunController extends Node
## Animates the DirectionalLight + ProceduralSky through GameClock phases (A6:
## everything keys off GameClock signals, never its own timers). Palette per canon:
## dawn honey, day flat, dusk violet-gray, night black + cold moonlight.

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial

# Per-phase keys: [elev_start, elev_end, energy_start, energy_end, color_a, color_b,
#                  sky_top_a, sky_top_b, horizon_a, horizon_b]
var _keys: Dictionary = {}

func setup(sun_in: DirectionalLight3D, env_in: Environment) -> void:
	sun = sun_in
	env = env_in
	sky_mat = env.sky.sky_material as ProceduralSkyMaterial
	_keys = {
		GameClock.Phase.DAWN: [-6.0, 16.0, 0.15, 1.0,
			Color(1.0, 0.62, 0.4), Color(1.0, 0.88, 0.7),
			Color(0.18, 0.22, 0.32), Color(0.4, 0.55, 0.72),
			Color(0.85, 0.55, 0.4), Color(0.8, 0.82, 0.8)],
		GameClock.Phase.DAY: [16.0, 16.0, 1.0, 1.1,
			Color(1.0, 0.95, 0.88), Color(1.0, 0.97, 0.92),
			Color(0.36, 0.52, 0.7), Color(0.38, 0.55, 0.72),
			Color(0.75, 0.8, 0.84), Color(0.72, 0.78, 0.82)],
		GameClock.Phase.DUSK: [16.0, -10.0, 1.0, 0.03,
			Color(1.0, 0.55, 0.35), Color(0.5, 0.35, 0.45),
			Color(0.3, 0.32, 0.48), Color(0.05, 0.06, 0.1),
			Color(0.8, 0.5, 0.45), Color(0.12, 0.1, 0.16)],
		GameClock.Phase.NIGHT: [30.0, 30.0, 0.05, 0.05,
			Color(0.55, 0.65, 0.85), Color(0.55, 0.65, 0.85),
			Color(0.01, 0.015, 0.03), Color(0.01, 0.015, 0.03),
			Color(0.03, 0.04, 0.07), Color(0.03, 0.04, 0.07)],
	}
	GameClock.time_updated.connect(_on_tick)
	GameClock.phase_changed.connect(func(_p: GameClock.Phase) -> void: _on_tick(0.0))
	_on_tick(0.0)

func _on_tick(f: float) -> void:
	if sun == null:
		return
	var phase: GameClock.Phase = GameClock.current_phase
	var k: Array = _keys[phase]
	var elev: float
	if phase == GameClock.Phase.DAY:
		elev = 16.0 + 40.0 * sin(f * PI)   # arc: up to 56 deg at midday, back down
	else:
		elev = lerpf(k[0], k[1], f)
	var azimuth: float = lerpf(80.0, 280.0, _global_day_fraction(phase, f))
	sun.rotation_degrees = Vector3(-elev, -azimuth, 0)
	sun.light_energy = lerpf(k[2], k[3], f)
	sun.light_color = (k[4] as Color).lerp(k[5], f)
	sky_mat.sky_top_color = (k[6] as Color).lerp(k[7], f)
	sky_mat.sky_horizon_color = (k[8] as Color).lerp(k[9], f)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color.darkened(0.3)
	env.ambient_light_energy = clampf(sun.light_energy * 0.6, 0.2, 0.7)
	env.fog_light_color = sky_mat.sky_horizon_color.darkened(0.2)
	if phase == GameClock.Phase.NIGHT:
		env.ambient_light_energy = 0.05
	# Interior daylight-spill lights track the sun: bright rooms by day, black at night.
	var spill_energy: float = 0.55 * clampf(sun.light_energy, 0.0, 1.0)
	if phase == GameClock.Phase.NIGHT:
		spill_energy = 0.0
	for l in get_tree().get_nodes_in_group("spill_lights"):
		l.light_energy = spill_energy

func _global_day_fraction(phase: GameClock.Phase, f: float) -> float:
	# Sun sweeps east->west across dawn+day+dusk; parked for night (it's the moon then).
	match phase:
		GameClock.Phase.DAWN:
			return f * 0.12
		GameClock.Phase.DAY:
			return 0.12 + f * 0.72
		GameClock.Phase.DUSK:
			return 0.84 + f * 0.16
		_:
			return 0.5
