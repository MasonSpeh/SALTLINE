extends Node3D
## Main orchestrator: builds environment/ocean/rig/player/UI in code, then runs the
## slice's scripted beats — cold open, PA crackle at dusk, crab at night, dawn end card.

const COUNTDOWN_SECONDS: float = 90.0

var rig: RigBuilder
var player: CharacterBody3D
var hud: HUD
var sun_ctl: SunController
var _countdown: float = COUNTDOWN_SECONDS
var _cold_open_active: bool = true
var _clang_accum: float = 0.0
var _ending: bool = false
var _contact_handled: bool = false

func _ready() -> void:
	_build_environment()
	_build_ocean()
	rig = RigBuilder.new()
	add_child(rig)
	var jelly := JellyGlow.new()
	add_child(jelly)
	player = load("res://scenes/Player.tscn").instantiate()
	add_child(player)
	player.global_position = rig.player_spawn
	player.rotation.y = deg_to_rad(-90)   # face the hatch end
	player.respawn_point = rig.wet_deck_respawn
	hud = HUD.new()
	add_child(hud)
	add_child(PauseMenu.new())
	# Scripted beats.
	GameClock.dusk.connect(_on_dusk)
	GameClock.night.connect(_on_night)
	GameClock.dawn.connect(_on_dawn)
	EventBus.creature_contact.connect(_on_creature_contact)
	# Cold open: black screen, regulator hiss, rhythmic hull clang.
	hud.set_black()
	AudioDirector.play_one_shot("hiss", Vector3.ZERO, -6.0)
	var t := get_tree().create_timer(1.2)
	t.timeout.connect(func() -> void: hud.fade_from_black(3.0))

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.fog_enabled = true
	env.fog_density = 0.0012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	add_child(sun)
	sun_ctl = SunController.new()
	add_child(sun_ctl)
	sun_ctl.setup(sun, env)

func _build_ocean() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(3000, 3000)
	mesh.subdivide_width = 64
	mesh.subdivide_depth = 64
	var mat := ShaderMaterial.new()
	mat.shader = load("res://materials/ocean_water.gdshader")
	mesh.material = mat
	var ocean := MeshInstance3D.new()
	ocean.mesh = mesh
	add_child(ocean)

func _process(delta: float) -> void:
	if _cold_open_active:
		_countdown -= delta
		_clang_accum += delta
		if _clang_accum > 4.0:
			_clang_accum = 0.0
			AudioDirector.play_one_shot("clang", rig.sphl_interior, -4.0)
		if _countdown <= 0.0:
			_end_cold_open()
		else:
			var m: int = int(_countdown) / 60
			var s: int = int(_countdown) % 60
			rig.countdown_label.text = "SURFACE PRESSURE — %02d:%02d:%02d" % [0, m, s]

func _end_cold_open() -> void:
	_cold_open_active = false
	rig.countdown_label.text = "SURFACE PRESSURE — 00:00:00"
	rig.countdown_label.modulate = Color(0.3, 0.9, 0.4)
	AudioDirector.play_one_shot("hiss", rig.sphl_interior, 0.0)
	rig.sphl_hatch.unlock()
	EventBus.cold_open_finished.emit()

func _on_dusk() -> void:
	# The PA crackle: one half-sentence of static-mangled speech, then dead (GDD 5.8).
	AudioDirector.play_one_shot("pa_crackle", rig.pa_speaker_pos, 2.0)

func _on_night() -> void:
	if _ending:
		return
	var crab := LamplightCrab.new()
	crab.z1_loop = rig.crab_z1_loop
	crab.ascend_path = rig.crab_ascend_path
	crab.z4_loop = rig.crab_z4_loop
	crab.exit_point = rig.crab_exit_point
	add_child(crab)
	crab.global_position = rig.crab_spawn

func _on_dawn() -> void:
	if GameClock.day_count >= 1 and not _ending:
		_ending = true
		# 30 seconds of peace, then the card (GDD 5.8).
		var t := get_tree().create_timer(30.0)
		t.timeout.connect(func() -> void:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			hud.show_end_card()
			EventBus.slice_complete.emit()
			get_tree().paused = true)

func _on_creature_contact() -> void:
	if _contact_handled:
		return
	_contact_handled = true
	# Screen dark + scuffle + wake at dawn in the SPHL with penalties (GDD 5.5).
	player.input_locked = true
	AudioDirector.play_one_shot("splash", player.global_position, 2.0)
	AudioDirector.play_one_shot("claw", player.global_position, 4.0)
	var tw: Tween = hud.fade_to_black(0.5)
	tw.tween_interval(2.0)
	tw.tween_callback(func() -> void:
		player.global_position = rig.sphl_interior
		player.velocity = Vector3.ZERO
		PlayerState.hunger -= 0.25
		PlayerState.warmth -= 0.25
		GameClock.skip_to_next_dawn()
		player.input_locked = false
		_contact_handled = false
		hud.fade_from_black(3.0)
		hud.toast("You wake in the lifeboat. Something carried you back."))
