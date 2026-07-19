extends Node3D
## Main orchestrator: builds environment/ocean/rig/player/UI in code, then runs the
## slice's scripted beats — cold open, PA crackle at dusk, crab at night, dawn end card.

var rig: RigBuilder
var player: CharacterBody3D
var hud: HUD
var sun_ctl: SunController
var storm: StormSystem
@warning_ignore("unused_private_class_variable")
var _countdown: float = 0.0   # retained for the screenshot harness; no longer ticks
var _cold_open_active: bool = true
var _ending: bool = false
var _contact_handled: bool = false
var jelly := JellyGlow.new()

func _ready() -> void:
	_build_environment()
	_build_ocean()
	rig = RigBuilder.new()
	add_child(rig)
	add_child(jelly)
	add_child(BloomFauna.new())   # gulls, jellies, barnacles, eel, shoal, ray, worms
	add_child(Gyre.new())         # the turning water south of the rig, and what it collects
	# Below the wave line: kelp, marine snow, mooring chains, and the catchable
	# species swimming their real depth bands (spawned from data/fish.json).
	add_child(preload("res://scripts/world/underwater_world.gd").new())
	# The patrol predators. They never bother what stays on deck.
	for i in range(3):
		add_child(preload("res://scripts/world/shark.gd").new(i))
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
	env.fog_enabled = true
	env.fog_density = 0.0008
	env.ambient_light_energy = 1.0
	# SSIL and volumetric fog are Forward+-only. The project ships on the
	# Compatibility (OpenGL) renderer for broad Mac/GPU support — Forward+ greys
	# out on some machines — so we only switch these on when Forward+ is actually
	# active. Flip the renderer back to Forward+ in Project Settings and they
	# return automatically. (RenderingDevice is null on the Compatibility path.)
	if RenderingServer.get_rendering_device() != null:
		env.ssil_enabled = true
		env.ssil_intensity = 0.9
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.012
		env.volumetric_fog_length = 110.0
		env.volumetric_fog_sky_affect = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	# Auto-exposure: the eye adapts — dark scenes stay readable without lying about
	# night. Forward+-only; the ambient floor (SunController) keeps night readable
	# on Compatibility without it.
	if RenderingServer.get_rendering_device() != null:
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
	# A 1600 m sphere must never be a shadow CASTER. Left on (the default), it drags the
	# directional light's caster bounds out to enclose the entire dome, so every shadow
	# split is fitted to a 3 km volume — the dome is redrawn into each split and the
	# whole rig's shadow resolution collapses at the same time.
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(dome)
	_star_dome = dome
	sun_ctl = SunController.new()
	add_child(sun_ctl)
	sun_ctl.setup(sun, moon, env, star_mat)
	# Violent squalls roll through now and then — rain, wind, lightning, thunder.
	storm = StormSystem.new()
	add_child(storm)
	storm.setup(sun_ctl)

func _build_ocean() -> void:
	# One camera-following radial mesh (OceanSurface): resolution grades from ~0.4 m
	# quads at the player's feet to the fog horizon, so real 1.5 m chop is resolvable
	# near the camera and there is no far-plane seam. Gerstner waves live in
	# ocean_water.gdshader; sea_state is driven by the storm via SunController.
	var ocean: Variant = preload("res://scripts/world/ocean_surface.gd").new()
	add_child(ocean)
	sun_ctl.register_ocean(ocean.get_material_ref())

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
	# A pack of three, staggered so they don't stack or move in lockstep — each keeps the
	# full one-crab drama (repellable, blackout on contact) via its own independent FSM.
	var offsets := [Vector3.ZERO, Vector3(-2.4, 0, 1.6), Vector3(2.2, 0, -1.4)]
	for i in range(3):
		var crab := LamplightCrab.new()
		crab.spawn_index = i
		crab.patrol_offset = offsets[i]
		crab.z1_loop = rig.crab_z1_loop
		crab.ascend_path = rig.crab_ascend_path
		crab.z4_loop = rig.crab_z4_loop
		crab.exit_point = rig.crab_exit_point
		add_child(crab)
		crab.global_position = rig.crab_spawn + offsets[i]

func _on_dawn() -> void:
	# The v0.1 slice ended the game at the first dawn — an end card and a paused tree.
	# That made SLEEPING end the game (both sleep paths call skip_to_next_dawn, which
	# bumps day_count past the threshold). SALTLINE is open-ended survival now: the first
	# dawn is a story beat, not a terminus. The end-card flow stays available for a real
	# finale trigger later; nothing arms it automatically anymore.
	if GameClock.day_count == 1 and not _ending:
		hud.set_objective("You made it through the first night.")
		hud.toast("The sun is up. The rig is yours to live on.")

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

# ---------- below the wave line: camera environment swap ----------

var _underwater_env: Environment = null
var _was_under: bool = false
var _star_dome: MeshInstance3D = null

## Swap the camera's own Environment when it dips below the swell — dense teal
## fog, dim ambient, no sky — and duck the topside audio. Camera-level override
## means SunController and the storms keep owning the surface environment.
func _process(_delta: float) -> void:
	if player == null:
		return
	var cam: Camera3D = player.get_node_or_null("Head/Camera3D")
	if cam == null:
		return
	var wave_y: float = Gyre.wave_height(Vector2(cam.global_position.x, cam.global_position.z), Gyre.water_time()) * 0.85
	var under: bool = cam.global_position.y < wave_y
	if under and _underwater_env == null:
		_underwater_env = Environment.new()
		_underwater_env.background_mode = Environment.BG_COLOR
		_underwater_env.background_color = Color(0.015, 0.075, 0.09)
		_underwater_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_underwater_env.ambient_light_color = Color(0.12, 0.27, 0.29)
		_underwater_env.ambient_light_energy = 0.7
		_underwater_env.fog_enabled = true
		_underwater_env.fog_light_color = Color(0.045, 0.16, 0.18)   # North Atlantic murk, not lagoon
		_underwater_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if under:
		# Deeper = darker and thicker; near the surface the world still glows.
		var depth: float = maxf(wave_y - cam.global_position.y, 0.0)
		_underwater_env.fog_density = lerpf(0.055, 0.17, clampf(depth / 14.0, 0.0, 1.0))
		_underwater_env.ambient_light_energy = lerpf(0.8, 0.25, clampf(depth / 14.0, 0.0, 1.0))
	if under != _was_under:
		_was_under = under
		cam.environment = _underwater_env if under else null
		AudioDirector.set_underwater(under)
		# The ocean surface is single-sided (cull_back), so from below you look straight
		# THROUGH it — and the 1600 m star dome, which draws the whole sky, was showing
		# up as a bright blue-grey band across the top of every mid-water shot. The Snell
		# plane cannot cover this: it is 620 m wide, so at 15 m down every ray within
		# ~3 deg of horizontal passes its edge and reaches the dome anyway. Underwater the
		# sky is simply not visible — hide the dome and let the graded fog own the
		# distance, which is what "the deep" is supposed to look like.
		if _star_dome != null:
			_star_dome.visible = not under
