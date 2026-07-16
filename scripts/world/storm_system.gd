class_name StormSystem extends Node3D
## Violent North Atlantic squalls that roll through every now and then: driving
## rain that follows the player, howling wind, a slate-dark sky, and lightning
## with delayed thunder. A storm ramps in, rages for a few minutes, then clears.
## Ties the sky/ambient darkening into SunController and the audio into
## AudioDirector; the rain is a GPU particle emitter parented above the player.

enum StormPhase { CLEAR, RAMP_IN, RAGING, RAMP_OUT }

const RAMP_IN_SEC: float = 22.0
const RAMP_OUT_SEC: float = 32.0
const FIRST_DELAY_MIN: float = 70.0     # first squall comes fairly soon so it's seen
const FIRST_DELAY_MAX: float = 150.0
const CALM_MIN: float = 260.0           # clear spells between storms (~4.5–9 min)
const CALM_MAX: float = 540.0
const RAGE_MIN: float = 90.0            # a storm rages 1.5–3.5 min
const RAGE_MAX: float = 210.0

var sun_ctl: SunController
var _phase: StormPhase = StormPhase.CLEAR
var _timer: float = 0.0
var _intensity: float = 0.0
var _rain: GPUParticles3D
var _rain_mat: ParticleProcessMaterial
var _flash: DirectionalLight3D
var _flash_energy: float = 0.0
var _lightning_cd: float = 0.0
var _wind: Vector2 = Vector2(1, 0)
var _rng := RandomNumberGenerator.new()
var _audio_cd: float = 0.0

func setup(sun_controller: SunController) -> void:
	sun_ctl = sun_controller

func _ready() -> void:
	_rng.randomize()
	_build_rain()
	_build_flash()
	_timer = _rng.randf_range(FIRST_DELAY_MIN, FIRST_DELAY_MAX)
	_wind = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()

## Force a squall now (debug/testing hook).
func trigger_storm() -> void:
	if _phase == StormPhase.CLEAR or _phase == StormPhase.RAMP_OUT:
		_wind = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
		_phase = StormPhase.RAMP_IN
		_timer = RAMP_IN_SEC

func is_storming() -> bool:
	return _intensity > 0.25

# ---------------------------------------------------------------- build

func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 5000
	_rain.lifetime = 1.0
	_rain.preprocess = 1.0
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	_rain.emitting = false
	_rain_mat = ParticleProcessMaterial.new()
	_rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_mat.emission_box_extents = Vector3(26, 0.5, 26)
	_rain_mat.direction = Vector3(0, -1, 0)
	_rain_mat.spread = 2.0
	_rain_mat.gravity = Vector3(0, -42, 0)
	_rain_mat.initial_velocity_min = 14.0
	_rain_mat.initial_velocity_max = 18.0
	_rain.process_material = _rain_mat
	# A thin bright streak, billboarded — reads as fast rain at any angle.
	var streak := QuadMesh.new()
	streak.size = Vector2(0.025, 0.55)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.75, 0.82, 0.92, 0.55)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.billboard_keep_scale = true
	streak.material = smat
	_rain.draw_pass_1 = streak
	add_child(_rain)

func _build_flash() -> void:
	_flash = DirectionalLight3D.new()
	_flash.light_energy = 0.0
	_flash.light_color = Color(0.82, 0.88, 1.0)
	_flash.rotation_degrees = Vector3(-58, 35, 0)
	_flash.shadow_enabled = false
	add_child(_flash)

# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	_advance_schedule(delta)
	_apply_intensity()
	_follow_player()
	_update_lightning(delta)

func _advance_schedule(delta: float) -> void:
	_timer -= delta
	match _phase:
		StormPhase.CLEAR:
			_intensity = move_toward(_intensity, 0.0, delta * 0.3)
			if _timer <= 0.0:
				_phase = StormPhase.RAMP_IN
				_timer = RAMP_IN_SEC
				_wind = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
		StormPhase.RAMP_IN:
			_intensity = move_toward(_intensity, 1.0, delta / RAMP_IN_SEC)
			if _timer <= 0.0:
				_phase = StormPhase.RAGING
				_timer = _rng.randf_range(RAGE_MIN, RAGE_MAX)
		StormPhase.RAGING:
			_intensity = move_toward(_intensity, 1.0, delta * 0.5)
			# The wind wanders during the storm so the rain angle shifts.
			_wind = (_wind + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * delta * 0.15).normalized()
			if _timer <= 0.0:
				_phase = StormPhase.RAMP_OUT
				_timer = RAMP_OUT_SEC
		StormPhase.RAMP_OUT:
			_intensity = move_toward(_intensity, 0.0, delta / RAMP_OUT_SEC)
			if _timer <= 0.0:
				_phase = StormPhase.CLEAR
				_timer = _rng.randf_range(CALM_MIN, CALM_MAX)

func _apply_intensity() -> void:
	var i: float = _intensity
	_rain.emitting = i > 0.02
	_rain.amount_ratio = clampf(i, 0.0, 1.0)
	# Slant the rain with the wind (stronger tilt at full storm).
	_rain_mat.gravity = Vector3(_wind.x * 22.0 * i, -42.0, _wind.y * 22.0 * i)
	if sun_ctl:
		sun_ctl.set_storm(i)
	# Audio follows intensity, but re-fading every frame thrashes tweens — throttle.
	_audio_cd -= get_process_delta_time()
	if _audio_cd <= 0.0:
		AudioDirector.set_storm(i)
		_audio_cd = 0.4

func _follow_player() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	# Rain box sits above the player, nudged upwind so it sweeps across the view.
	_rain.global_position = player.global_position + Vector3(-_wind.x * 6.0, 16.0, -_wind.y * 6.0)

func _update_lightning(delta: float) -> void:
	# Decay the last flash toward dark, fast.
	_flash_energy = move_toward(_flash_energy, 0.0, delta * 22.0)
	_flash.light_energy = _flash_energy
	if _intensity < 0.4:
		return
	_lightning_cd -= delta
	if _lightning_cd <= 0.0:
		_strike()
		_lightning_cd = _rng.randf_range(5.0, 15.0) * (1.5 - _intensity)

func _strike() -> void:
	# A sharp flash with a quick secondary flicker, then thunder after the light
	# has travelled — closer strikes flash brighter and rumble sooner.
	var near: float = _rng.randf()          # 0 = distant, 1 = right overhead
	_flash_energy = lerpf(1.6, 4.5, near)
	var t2 := get_tree().create_timer(0.09)
	t2.timeout.connect(func() -> void: _flash_energy = lerpf(1.0, 3.0, near))
	var delay: float = lerpf(2.6, 0.3, near)
	var vol: float = lerpf(-16.0, 2.0, near)
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func() -> void:
		var player: Node3D = get_tree().get_first_node_in_group("player")
		var pos: Vector3 = player.global_position if player else Vector3.ZERO
		AudioDirector.play_one_shot("thunder", pos + Vector3(0, 30, 0), vol))
