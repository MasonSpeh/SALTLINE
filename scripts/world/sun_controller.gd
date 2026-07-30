class_name SunController extends Node
## Drives sun + moon + physical sky + ambient/fog/star curves off GameClock (A6).
## Night is dark but readable: cold moonlight, deep-blue ambient floor, auto-exposure.
## Warm light stays player-made (canon); the moon and stars are the world's.

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var star_mat: ShaderMaterial
var storm_intensity: float = 0.0   ## 0 clear .. 1 full storm; set by StormSystem
var _last_f: float = 0.0
var _sun_shadow_on: bool = true    ## hysteresis latch for the sun's cascade (see _apply)

## Ocean (ocean_water.gdshader) sea_state is driven from here so a squall raises the
## swell in lockstep with the sky/rain. Calm water is never glassy-flat — a working
## North Sea always has some sea running — so storm lerps from BASE_SEA_STATE, not 0.
const BASE_SEA_STATE: float = 0.4
var _ocean_mats: Array[ShaderMaterial] = []

func register_ocean(mat: ShaderMaterial) -> void:
	if mat and not _ocean_mats.has(mat):
		_ocean_mats.append(mat)
	_apply_sea_state()
	# Re-run the light tick so a freshly registered ocean gets the sky colour/radiance
	# it should be reflecting on its very first frame, not the uniform defaults.
	if sun != null:
		_on_tick(_last_f)

func _apply_sea_state() -> void:
	var ss: float = lerpf(BASE_SEA_STATE, 1.0, storm_intensity)
	for m in _ocean_mats:
		m.set_shader_parameter("sea_state", ss)
		# Rain dimpling/veil on the sea rides the storm intensity directly (0 when clear,
		# so the shader's rain branch is skipped entirely outside a squall).
		m.set_shader_parameter("rain_wet", storm_intensity)
	# The CPU mirror of the wave math (floating debris, and main.gd's underwater test)
	# has to run at the SAME sea state as the shader, or a squall raises the drawn
	# water above the water everything else believes in.
	Gyre.set_sea_state(ss)

## The sea mirrors the sky, so it needs to know what the sky is DOING. Feeds
## ocean_water.gdshader the horizon colour and radiance it should be reflecting —
## pale blue at noon, warm at dusk, near-black under stars, flat slate in a squall.
const SEA_SKY_DAY := Color(0.60, 0.70, 0.82)
const SEA_SKY_NIGHT := Color(0.07, 0.10, 0.18)
const SEA_SKY_STORM := Color(0.30, 0.34, 0.39)
const SEA_SKY_WARM := Color(0.85, 0.52, 0.34)

func _apply_sky_reflection(sun_h: float, night: float, storm: float) -> void:
	if _ocean_mats.is_empty():
		return
	var low: float = 1.0 - clampf(sun_h * 3.0, 0.0, 1.0)   # 1 when the sun is near the horizon
	var tint: Color = SEA_SKY_DAY.lerp(SEA_SKY_NIGHT, night)
	tint = tint.lerp(SEA_SKY_WARM, low * (1.0 - night) * 0.45)   # dusk/dawn fire on the water
	tint = tint.lerp(SEA_SKY_STORM, storm)
	var energy: float = lerpf(clampf(sun_h * 1.6 + 0.14, 0.05, 1.0), 0.06, night)
	# Overcast still lights the sea — the cloud deck BECOMES the light source. Crushing
	# this the way the sun gets crushed left the storm sea as black oil with no legible
	# whitecaps, which is the opposite of how a squall actually looks.
	energy *= lerpf(1.0, 0.72, storm)
	for m in _ocean_mats:
		m.set_shader_parameter("sky_tint", Vector3(tint.r, tint.g, tint.b))
		m.set_shader_parameter("sky_energy", energy)

## Storm darkening: kill the sun, crush the ambient toward slate, thicken the fog.
## Re-runs the light tick so the change takes immediately.
func set_storm(intensity: float) -> void:
	storm_intensity = clampf(intensity, 0.0, 1.0)

var fog_intensity: float = 0.0   ## post-squall sea fog, fed by StormSystem
func set_fog(v: float) -> void:
	fog_intensity = clampf(v, 0.0, 1.0)
	_apply_sea_state()
	_on_tick(_last_f)

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

## 0 at the moment the moon clears the horizon (late dusk) .. 1 as it sets (early dawn).
## Drives the moon's nightly arc so it is genuinely opposite the sun — which is also
## what makes the shader's phase term read as a FULL moon on a clear night.
func _moon_fraction(phase: GameClock.Phase, f: float) -> float:
	match phase:
		GameClock.Phase.DUSK:
			return f * 0.14
		GameClock.Phase.NIGHT:
			return 0.14 + f * 0.72
		GameClock.Phase.DAWN:
			return 0.86 + f * 0.14
		_:
			return 0.0   # daytime: below/behind the sun, disc is dark anyway

func _on_tick(f: float) -> void:
	if sun == null:
		return
	_last_f = f
	var phase: GameClock.Phase = GameClock.current_phase
	var elev: float = _elevation(phase, f)
	var azimuth: float = lerpf(80.0, 280.0, _global_day_fraction(phase, f))
	sun.rotation_degrees = Vector3(-elev, -azimuth, 0)
	var sun_h: float = sin(deg_to_rad(elev))   # -1..1 height factor
	var storm: float = storm_intensity
	sun.light_energy = clampf(sun_h * 1.7, 0.0, 1.3) * (1.0 - 0.9 * storm)
	sun.light_color = SUN_WARM.lerp(SUN_WHITE, clampf(sun_h * 2.8, 0.0, 1.0))

	var night: float = _night_amount(phase, f)
	# The moon rides its own arc across the night instead of hanging at a fixed bearing:
	# it lifts out of the east as dusk closes, tops out around the small hours, and sets
	# as dawn comes up. Driving it here (rather than a static rotation at construction)
	# is what lets the DOME's moon disc and the moon LIGHT agree — the disc is drawn from
	# moon_dir below, so a static light with a travelling disc would light the rig from a
	# direction with no moon in it.
	var mf: float = _moon_fraction(phase, f)
	var moon_elev: float = 6.0 + 48.0 * sin(PI * clampf(mf, 0.0, 1.0))
	var moon_az: float = lerpf(95.0, 265.0, clampf(mf, 0.0, 1.0))
	moon.rotation_degrees = Vector3(-moon_elev, -moon_az, 0)
	moon.light_energy = 0.28 * night * (1.0 - 0.8 * storm)   # cloud cover swallows the moon
	moon.visible = night > 0.01 and storm < 0.9
	if star_mat:
		# night_amount is the true day/night blend; the storm uniform drives the
		# overcast branch and extinguishes the stars. (Folding storm into night_amount
		# used to paint a starry night sky over a DAYTIME squall.)
		star_mat.set_shader_parameter("night_amount", night)
		star_mat.set_shader_parameter("storm", storm)
		# The dome draws the ENTIRE sky now (sun disc, moon disc, day gradient), so it
		# needs the actual celestial directions or the visible sun sits somewhere the
		# sunlight isn't. A DirectionalLight3D emits along its local -Z, so the direction
		# TOWARD the body is +basis.z. These four were never wired: the disc used to be
		# frozen at the uniform defaults, which put a full moon in a midday sky and pinned
		# the day-sky brightness to a permanent mid-morning.
		star_mat.set_shader_parameter("sun_dir", sun.global_transform.basis.z)
		star_mat.set_shader_parameter("moon_dir", moon.global_transform.basis.z)
		star_mat.set_shader_parameter("sun_height", sun_h)
		star_mat.set_shader_parameter("moon_bright", night * (1.0 - storm))
		# Keep the dome's horizon colour matched to the fog the SEA fades into, so the
		# water and sky meet with no seam where the ocean rim dies in the haze.
		var ft: Color = env.fog_light_color
		star_mat.set_shader_parameter("horizon_tint", Vector3(ft.r, ft.g, ft.b))
	_apply_sky_reflection(sun_h, night, storm)

	# Ambient floor keeps dark scenes readable — deep blue, never zero. A storm
	# drags the whole palette toward cold slate and darkens it.
	var amb: Color = AMBIENT_DAY.lerp(AMBIENT_NIGHT, night).lerp(Color(0.18, 0.2, 0.24), storm)
	env.ambient_light_color = amb
	env.ambient_light_energy = lerpf(lerpf(clampf(sun.light_energy * 0.55, 0.22, 0.65), 0.16, night), 0.14, storm)
	env.fog_light_color = env.ambient_light_color.darkened(0.25)
	env.volumetric_fog_albedo = Color(0.85, 0.88, 0.92).lerp(Color(0.5, 0.58, 0.7), night).lerp(Color(0.4, 0.42, 0.46), storm)
	env.volumetric_fog_density = lerpf(0.012, 0.05, storm) + 0.05 * fog_intensity
	# Sea fog is DENSER than squall haze — a bank you watch swallow the far derrick —
	# and it mutes the sun the way squall cloud does, just without the darkening.
	env.fog_density = lerpf(0.0008, 0.004, storm) + 0.0068 * fog_intensity
	sun.light_energy *= 1.0 - 0.38 * fog_intensity

	# A SUN THAT IS NOT LIGHTING ANYTHING MUST NOT RENDER A CASCADE.
	#
	# This is the same lesson the moon already learned in main.gd — it ships with
	# shadow_enabled = false because it was drawing a full cascade of the whole rig every
	# frame, all day, at zero energy. The SUN has exactly that problem in the other half of
	# the cycle: light_energy goes to 0 the moment it drops below the horizon, but
	# shadow_enabled stayed true all night, so every night frame paid for a shadow map of a
	# light contributing nothing. Measured in tests/PowerPerf.tscn at night, that pass was
	# 897 of 2192 draw calls — 41% of the frame — and turning it off took 15.5 -> 19.4 fps
	# with no visible difference whatsoever, because there is no sunlight to cast a shadow
	# from. It pays off in heavy storm too, where the same energy term is scaled to a tenth.
	#
	# Two thresholds, not one: energy crawls through this band slowly at dawn and dusk, and
	# a single cutoff would flip the flag back and forth for several real seconds, throwing
	# away and reallocating the shadow map each time. On at 0.08, off at 0.03 — well under
	# the ~0.22 ambient floor, so the first shadow appears only once there is enough sun to
	# read one.
	if _sun_shadow_on and sun.light_energy < 0.03:
		_sun_shadow_on = false
	elif not _sun_shadow_on and sun.light_energy > 0.08:
		_sun_shadow_on = true
	sun.shadow_enabled = _sun_shadow_on and not _deep_water

	# Interior daylight-spill lights track the sun; interiors go black at night (Rule 7)
	# unless the player flips the switches they earned.
	var spill_energy: float = 0.55 * clampf(sun.light_energy, 0.0, 1.0)
	for l in get_tree().get_nodes_in_group("spill_lights"):
		l.light_energy = spill_energy

## THE SAME ARGUMENT, ONE MEDIUM DOWN. Under water the sun is not a light that casts a
## readable shadow either, and for the same reason: underwater_fx._grade_sun attenuates the
## directional light on a measured extinction curve — 0.26 of its topside energy at 4 m
## down, 0.10 at 12 m, floor 0.06 — and the camera's own environment is fogging at 0.055 to
## 0.17 per metre on top of that. A cascade rendered into that is a hard-edged shadow from a
## light contributing a tenth of the ambient, seen through teal murk.
##
## Measured (tests/VantagePerf.tscn, A/B/A, each row against its own noise floor and the
## vantage's null pair): the sun's shadow pass cost 3.33 ms and 796 draw calls at
## `submerged_deep` (-12 m) and 1.54 ms / 26 draws at `submerged_mid` (-5 m) — 14.6% and
## 10.0% of those frames, for shadows that cannot be resolved.
##
## The night latch above already reaches this eventually (deep enough, the graded energy
## falls under its 0.03 threshold on its own), but only on the next GameClock tick and only
## in the abyss. This is the same test applied at dive depth and applied IMMEDIATELY, which
## is what a dive needs — hence a setter that re-applies rather than waiting for _apply.
const DEEP_SHADOW_OFF: float = 3.6    ## metres below the surface: stop casting
const DEEP_SHADOW_ON: float = 2.2     ## ...and start again here. Deadband, not one cutoff.
var _deep_water: bool = false

## Called every frame by main.gd, which already computes the camera's depth for the
## environment swap. Early-outs on no change, so the cost is one float compare a frame.
func set_dive_depth(depth: float) -> void:
	var want: bool = _deep_water
	if depth > DEEP_SHADOW_OFF:
		want = true
	elif depth < DEEP_SHADOW_ON:
		want = false
	if want == _deep_water:
		return
	_deep_water = want
	if sun != null:
		sun.shadow_enabled = _sun_shadow_on and not _deep_water

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
