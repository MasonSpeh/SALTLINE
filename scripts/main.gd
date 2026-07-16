extends Node3D
## Main orchestrator: builds environment/ocean/rig/player/UI in code, then runs the
## slice's scripted beats — cold open, PA crackle at dusk, crab at night, dawn end card.

var rig: RigBuilder
var player: CharacterBody3D
var hud: HUD
var sun_ctl: SunController
var _countdown: float = 0.0   # retained for the screenshot harness; no longer ticks
var _cold_open_active: bool = true
var _ending: bool = false
var _contact_handled: bool = false

func _ready() -> void:
	_build_environment()
	_build_ocean()
	rig = RigBuilder.new()
	add_child(rig)
	var jelly := JellyGlow.new()
	add_child(jelly)
	add_child(BloomFauna.new())   # gulls, jellies, barnacles, eel, shoal, ray, worms
	add_child(Gyre.new())         # the turning water south of the rig, and what it collects
	player = load("res://scenes/Player.tscn").instantiate()
	add_child(player)
	player.global_position = rig.player_spawn
	player.rotation.y = deg_to_rad(180)   # face the hatch (+Z), so forward walks out
	player.respawn_point = rig.wet_deck_respawn
	hud = HUD.new()
	add_child(hud)
	add_child(PauseMenu.new())
	# Scripted beats.
	GameClock.dusk.connect(_on_dusk)
	GameClock.night.connect(_on_night)
	GameClock.dawn.connect(_on_dawn)
	PowerGrid.circuit_powered.connect(_on_circuit_powered)
	EventBus.creature_contact.connect(_on_creature_contact)
	# Drop a few loose grabbables on the wet deck — something to physically handle.
	_spawn_props()
	# Immediate start — no countdown, no black screen, no locked input. The hatch is
	# already unlocked, so the player can look at it and press E to swing it open on
	# the first try, then walk straight out onto the rig.
	AudioDirector.play_one_shot("hiss", Vector3.ZERO, -6.0)
	hud.set_objective("Surface pressure equalized. Open the hatch [E] and get out.")
	rig.sphl_hatch.interacted.connect(_on_hatch_used)

func _spawn_props() -> void:
	var base: Vector3 = rig.wet_deck_respawn
	var specs := [
		[Vector3(1.4, 0.6, 0.8), Vector3(0.4, 0.4, 0.4), Color(0.55, 0.3, 0.18)],
		[Vector3(-1.2, 0.6, 1.4), Vector3(0.35, 0.35, 0.35), Color(0.3, 0.45, 0.5)],
		[Vector3(0.6, 0.6, 2.2), Vector3(0.45, 0.3, 0.3), Color(0.6, 0.55, 0.25)],
	]
	for s in specs:
		var prop := PhysProp.new()
		add_child(prop)
		prop.global_position = base + (s[0] as Vector3)
		prop.mass = 1.2
		var size: Vector3 = s[1]
		var mesh_inst := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh_inst.mesh = box
		mesh_inst.material_override = MatLib.flat(s[2])
		prop.add_child(mesh_inst)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		prop.add_child(col)

func _build_environment() -> void:
	# Physical sky: real sun disc, natural dawn/dusk scattering, black at night.
	var sky_mat := PhysicalSkyMaterial.new()
	sky_mat.sun_disk_scale = 3.0
	sky_mat.mie_coefficient = 0.012
	sky_mat.mie_eccentricity = 0.85
	sky_mat.turbidity = 4.0
	sky_mat.ground_color = Color(0.08, 0.1, 0.12)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 4.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.8
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.5
	# Screen-space indirect light: the spill omnis and emissive windows bounce a
	# little, which grounds the PBR texture set indoors without real GI cost.
	env.ssil_enabled = true
	env.ssil_intensity = 0.9
	env.fog_enabled = true
	env.fog_density = 0.0008
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_length = 110.0
	env.volumetric_fog_sky_affect = 0.05
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	# Auto-exposure: the eye adapts — dark scenes stay readable without lying about night.
	var cam_attrs := CameraAttributesPractical.new()
	cam_attrs.auto_exposure_enabled = true
	cam_attrs.auto_exposure_scale = 0.3
	cam_attrs.auto_exposure_speed = 0.4
	we.camera_attributes = cam_attrs
	add_child(we)
	var sun := DirectionalLight3D.new()   # must be first DirectionalLight: sky tracks it
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.72, 0.95)
	moon.light_energy = 0.0
	moon.shadow_enabled = true
	moon.rotation_degrees = Vector3(-42, 140, 0)
	add_child(moon)
	# Star dome, faded in by the controller at night.
	var star_mat := ShaderMaterial.new()
	star_mat.shader = load("res://materials/stars.gdshader")
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 1600.0
	dome_mesh.height = 3200.0
	dome_mesh.material = star_mat
	var dome := MeshInstance3D.new()
	dome.mesh = dome_mesh
	add_child(dome)
	sun_ctl = SunController.new()
	add_child(sun_ctl)
	sun_ctl.setup(sun, moon, env, star_mat)

func _build_ocean() -> void:
	var shader: Shader = load("res://materials/ocean_water.gdshader")
	# Near mesh: dense enough for vertex waves around the rig.
	var near_mat := ShaderMaterial.new()
	near_mat.shader = shader
	var near_mesh := PlaneMesh.new()
	near_mesh.size = Vector2(500, 500)
	near_mesh.subdivide_width = 250
	near_mesh.subdivide_depth = 250
	near_mesh.material = near_mat
	var near := MeshInstance3D.new()
	near.mesh = near_mesh
	add_child(near)
	# Far plane: flat, fragment ripples only, meets the horizon under the fog.
	var far_mat := ShaderMaterial.new()
	far_mat.shader = shader
	far_mat.set_shader_parameter("vertex_waves", false)
	var far_mesh := PlaneMesh.new()
	far_mesh.size = Vector2(6000, 6000)
	far_mesh.material = far_mat
	var far := MeshInstance3D.new()
	far.mesh = far_mesh
	add_child(far)
	far.position.y = -1.35   # below the deepest v2 trough so it never pokes through

func _on_hatch_used(_verb: String) -> void:
	# First time the player opens the SPHL hatch, advance from the intro beat.
	_end_cold_open()

func _end_cold_open() -> void:
	if not _cold_open_active:
		return
	_cold_open_active = false
	rig.countdown_label.text = "PRESSURE — EQUALIZED"
	rig.countdown_label.modulate = Color(0.3, 0.9, 0.4)
	AudioDirector.play_one_shot("hiss", rig.sphl_interior, 0.0)
	rig.sphl_hatch.unlock()
	hud.set_hint("")   # hand the prompt chip back to the interaction system
	hud.set_objective("Get out. Find the cable spool and restore power before dark.")
	hud.toast("Cold air. You're on the rig.")
	EventBus.cold_open_finished.emit()

func _on_circuit_powered(id: String) -> void:
	if id == "topside_floodlights":
		hud.set_objective("Power's on. When night comes, stay inside the light.")
		hud.toast("The floodlights hum to life.")

func _on_dusk() -> void:
	# The PA crackle: one half-sentence of static-mangled speech, then dead (GDD 5.8).
	AudioDirector.play_one_shot("pa_crackle", rig.pa_speaker_pos, 2.0)
	if not _ending:
		if PowerGrid.is_powered("topside_floodlights"):
			hud.set_objective("Light's failing. Get to a lit deck before full dark.")
		else:
			hud.set_objective("No power and no light. Get the floodlights on — now.")

func _on_night() -> void:
	if _ending:
		return
	hud.set_objective("Something's out there. Stay in the light until dawn.")
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
		hud.set_objective("You made it. The sun is up.")
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
