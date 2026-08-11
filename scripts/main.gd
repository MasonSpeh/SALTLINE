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
var jelly := JellyGlow.new()

func _ready() -> void:
	_build_environment()
	_build_ocean()
	# Built and shader-warmed at LOAD, not on the first dive — see _build_underwater_env().
	_build_underwater_env()
	_prewarm_underwater_env()
	# Item effects (heal / cures / empties-returned) listen on PlayerState.item_eaten, which
	# use_hotbar emits but does not itself implement. Mounted HERE, explicitly, because the
	# alternative was self-mounting off whatever unrelated call happened to run first — the
	# dressing pass and the build system were both being used as an "earliest hook", which
	# left healing quietly dependent on having salvaged or built something that session.
	add_child(preload("res://scripts/components/item_effects.gd").new())
	rig = RigBuilder.new()
	add_child(rig)
	# THE FIELD: the three neighbouring rigs and the bridges that chain them. Built after
	# rig 1 and entirely beside it — rig_field.gd owns every world coordinate the new
	# platforms occupy and rig_builder.gd is not touched by any of it. See rig_kit.gd for
	# why three whole rigs cost tens of draw calls rather than thousands.
	add_child(preload("res://scripts/world/rig_field.gd").new())
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
	# SPAWN ON THE LUXURY RIG for now (owner, s59b): the ANCHORAGE's south arrival deck,
	# facing the podium door. The field's Anchor markers publish each rig's spawn in world
	# space, and rig_field is already BUILT here — _ready runs inside add_child (the trap
	# this repo documents), so the markers exist by this line. Respawn moves with it: dying
	# on the show rig and waking three bridges away would be a punishment, not a respawn.
	for mk in get_tree().get_nodes_in_group("field_rig"):
		if mk.get_parent() != null and mk.get_parent().name == "Anchorage":
			var sp: Vector3 = mk.get_meta("spawn") as Vector3
			player.global_position = sp + Vector3(0, 0.3, 0)
			player.respawn_point = sp + Vector3(0, 0.5, 0)
			var fwd_d: Vector3 = (mk.get_meta("overview") as Vector3) - sp
			player.rotation.y = atan2(-fwd_d.x, -fwd_d.z)
			break
	hud = HUD.new()
	add_child(hud)
	add_child(PauseMenu.new())
	# Scripted beats.
	GameClock.dusk.connect(_on_dusk)
	GameClock.night.connect(_on_night)
	GameClock.dawn.connect(_on_dawn)
	PowerGrid.circuit_powered.connect(_on_circuit_powered)
	# Drop a few loose grabbables on the wet deck — something to physically handle.
	_spawn_props()
	# Frame budget: drop sub-texel geometry out of the shadow cascades and give small
	# dressing a distance range. See render_budget.gd — this is what keeps the rig's
	# ~6,800 authored primitives inside a MacBook's draw-call budget.
	add_child(preload("res://scripts/world/render_budget.gd").new())
	# Second half of the frame budget: once the dressing has streamed in and settled, bake
	# all the static co-material rig dressing (bolts, pipes, girders, panels, weld seams —
	# thousands of primitives) into one mesh per material, collapsing the draw calls that
	# render_budget's per-object shadow/range work could not. See rig_batcher.gd.
	var batcher: Node = preload("res://scripts/world/rig_batcher.gd").new()
	batcher.rig_root = rig
	add_child(batcher)
	# Immediate start — no countdown, no black screen, no locked input. The hatch is
	# already unlocked, so the player can look at it and press E to swing it open on
	# the first try, then walk straight out onto the rig.
	AudioDirector.play_one_shot("hiss", Vector3.ZERO, -6.0)
	hud.set_objective("Surface pressure equalized. Open the hatch [E] and get out.")
	rig.sphl_hatch.interacted.connect(_on_hatch_used)
	# CONTINUE: the start screen flagged a load for this slot. Restore it now that the
	# whole world, player and HUD exist. Deferred one frame so structures/containers
	# rebuild after the scene has fully entered the tree.
	if SaveManager.consume_pending_load():
		call_deferred("_resume_saved_game")
	elif get_tree().current_scene == self:
		# EDITOR PLAY / a direct Main boot: nobody chose a slot, and Main is the actual
		# scene root — a human is playing, so autosaves should have somewhere to go. A
		# probe's Main is a CHILD of the probe scene and never passes this check, which is
		# the whole fix for harnesses wiping real saves (see SaveManager.active_slot).
		SaveManager.begin_direct_session()

## Load the active slot and settle the player into the resumed run (not the cold open).
func _resume_saved_game() -> void:
	if not SaveManager.load_game():
		return
	_cold_open_active = false
	if is_instance_valid(hud):
		var names: Array = ["dawn", "day", "dusk", "night"]
		var pi: int = clampi(GameClock.current_phase, 0, 3)
		hud.set_objective("Day %d, %s. Back on the rig — carry on." % [GameClock.day_count + 1, names[pi]])

func _spawn_props() -> void:
	# Three loose things to physically handle on the way out of the pod. These used to be
	# MatLib.flat() boxes — untextured brown, blue-grey and TAN cubes sitting on the wet
	# deck, the only un-authored primitives the player meets in the first ten seconds, and
	# invisible to PlacementProbe because it exempts unfrozen rigid bodies. They are now
	# a timber dunnage block, a galvanised ammo-can and a rusted steel offcut: same
	# physics, same grab handles, but they read as salvage off a working deck.
	# wet_deck_respawn is a STANDING point (deck + 0.6), not the plating: dropping props
	# from it left them a metre in the air, free to bounce off dressing and come to rest
	# half inside a crate. Work from the plating itself and set each one down on its base.
	var base: Vector3 = rig.wet_deck_respawn
	var deck_y: float = base.y - 0.6
	var specs := [
		[Vector2(1.4, 0.8), Vector3(0.42, 0.26, 0.42), MatLib.weathered_wood(), 1.6],
		[Vector2(-1.2, 1.4), Vector3(0.34, 0.3, 0.24), MatLib.galvanized(), 1.1],
		[Vector2(0.6, 2.2), Vector3(0.46, 0.14, 0.3), MatLib.rust_steel(), 2.2],
	]
	for s in specs:
		var prop := PhysProp.new()
		add_child(prop)
		var size: Vector3 = s[1]
		var off: Vector2 = s[0]
		prop.global_position = Vector3(base.x + off.x, deck_y + size.y * 0.5 + 0.005, base.z + off.y)
		prop.mass = s[3]
		var mesh_inst := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh_inst.mesh = box
		mesh_inst.material_override = s[2]
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
	# ONE SPLIT, NOT TWO. This is the whole of the "shadows look blocky" fix and it was
	# counter-intuitive enough to survive two rounds of tuning that never touched it.
	#
	# PARALLEL_2_SPLITS does not give each cascade the shadow atlas. It gives each cascade
	# HALF the atlas edge — 2048 out of 4096 — and then split_1 decided how the world was
	# divided between them. At 0.14 the near cascade spent its entire 2048 map on the first
	# 6.3 metres (325 texels/metre, far finer than anything can show) and left 6.3-45 m —
	# every railing, stanchion and stair the player actually looks at — on the other 2048
	# map: 53 texels/metre, a shadow texel nearly 2 cm across. That is the staircase in the
	# owner's screenshots. It is not a filtering problem and no amount of bias fixes it.
	#
	# ORTHOGONAL gives the single cascade the WHOLE atlas over the whole 45 m. Measured with
	# tests/ShadowShot.tscn (matrix mode, frozen world, same frame): 91 texels/metre at the
	# same 4096, and SIXTY FEWER draw calls per frame, because nothing near the split
	# boundary is rasterised into two cascades any more. Better and cheaper, both.
	# Combined with the 8192 atlas in project.godot it is 182 texels/metre — 3.4x what the
	# mid-field had. Cost, measured over 120 frames alternating live: +0.5 ms/frame.
	#
	# The one thing given up is the near cascade's excess: inside ~6 m, shadows go from 325
	# to 182 texels/metre. Nothing in the capture shows that as a loss — 182/m is a 5 mm
	# texel — and it buys the other 39 metres.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	# 60 -> 45 m. max_distance IS the caster cull for the cascade: nothing past it is
	# drawn into a shadow map at all, so this is the one knob that removes shadow DRAW
	# CALLS rather than just making them cheaper to rasterise. tests/FrameAttrib.tscn put
	# the sun's pass at 31-42% of every draw call in the frame, and the rig is ~50 m
	# across, so 60 m was paying to shadow the far side of a structure that reads as
	# silhouette and fog from anywhere you can stand. 45 m still covers the whole deck you
	# are on and the ironwork immediately around it, which is all a shadow is legible on.
	#
	# It is ALSO the other resolution knob now that there is one cascade: texels/metre is
	# simply atlas/max_distance. 45 -> 32 m is therefore 182 -> 256 texels/metre, a 40%
	# sharper shadow, at the same time as it removes casters.
	#
	# s23: TAKEN, on the owner's call. The 45 m value was held because at 32 m the far
	# derrick stops casting onto the deck you are standing on — that loss is real and is
	# accepted. What it buys is measured, not argued: tests/VantagePerf.tscn now carries a
	# `shadow_dist` row that flips 45 <-> 32 inside ONE session (the machine drifts 1-2 ms
	# between runs, which is larger than the effect, so a cross-run table cannot resolve it).
	# Read that row for the current figure. The whole shadow PASS is 4.81 ms / 965 draws
	# (the `sun_shadow` row) and that is the ceiling this can approach but never reach:
	# 32 m still covers the deck you are on and the ironwork around it.
	sun.directional_shadow_max_distance = 32.0
	# No split_1 here on purpose: SHADOW_ORTHOGONAL has one cascade and the split fractions
	# are ignored. Setting it would read like a tuned value and be dead.
	#
	# Bias is measured in TEXELS in effect — Godot scales it by the cascade's texel size —
	# so tripling the resolution has already tightened these by the same factor and they do
	# NOT want re-tuning downward on top of that. Godot's directional defaults (normal_bias
	# 1.0, bias 0.1) detach a shadow from the thing casting it by a visible finger's width.
	# 0.2 was tried against 0.45 at 8192 in the matrix and changed nothing legible, so the
	# already-proven value stays rather than walking toward acne for no gain.
	#
	# NOTE: the property is shadow_normal_bias (inherited from Light3D). There is no
	# directional_shadow_normal_bias in Godot 4 — writing that name silently does nothing
	# and leaves the sun at the 1.0 default this line exists to bring down.
	sun.shadow_normal_bias = 0.45
	sun.shadow_bias = 0.035
	# NO shadow_blur. The property exists on Light3D, so assigning it is not an error — it
	# is simply ignored by this renderer. gl_compatibility's scene shader hands its PCF
	# kernel the raw shadow_atlas_pixel_size with no blur term anywhere in the path, and
	# the matrix proved it: blur 0.0 and blur 4.0 produced BYTE-IDENTICAL frames. A line
	# setting it would be a tuning knob that does not turn.
	add_child(sun)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.72, 0.95)
	moon.light_energy = 0.0
	# The moon peaks at 0.28 energy against an ambient night floor, so its shadows are
	# barely a shade — but with shadow_enabled it rendered a SECOND full cascade of the
	# whole rig every frame, all day, while its light energy was zero. Not worth a cascade.
	moon.shadow_enabled = false
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
	hud.set_objective("Get out. Power's dead — grab the cable spool from the PUMP ROOM, then up the stair tower to throw Breaker 4-A (Lvl 2).")
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
	# The giant crabs are PERSISTENT now (s11 remake): they live underwater by day and
	# climb the wet-deck rim at night on their own FSM. Spawned once by BloomFauna —
	# nothing to do here beyond the objective text.

func _on_dawn() -> void:
	# The v0.1 slice ended the game at the first dawn — an end card and a paused tree.
	# That made SLEEPING end the game (both sleep paths call skip_to_next_dawn, which
	# bumps day_count past the threshold). SALTLINE is open-ended survival now: the first
	# dawn is a story beat, not a terminus. The end-card flow stays available for a real
	# finale trigger later; nothing arms it automatically anymore.
	if GameClock.day_count == 1 and not _ending:
		hud.set_objective("You made it through the first night.")
		hud.toast("The sun is up. The rig is yours to live on.")

# ---------- below the wave line: camera environment swap ----------

var _underwater_env: Environment = null
var _was_under: bool = false
## Cached answer to "is underwater_fx in the tree and therefore grading the water?" —
## resolved once and re-resolved only while it is still missing, so a scene that builds the
## FX late still hands the grade over rather than fighting it for ever.
var _uw_fx: Node = null

func _fx_owns_grade() -> bool:
	if _uw_fx != null and is_instance_valid(_uw_fx):
		return true
	_uw_fx = null
	for n in get_tree().get_nodes_in_group("underwater_fx"):
		_uw_fx = n
		return true
	return false
var _star_dome: MeshInstance3D = null

## THE ONE-SECOND FREEZE ON GOING UNDER, and why it was self-inflicted.
##
## This Environment used to be built LAZILY, the first frame the camera dipped below the
## swell. Under gl_compatibility, handing the camera an Environment whose pipeline
## configuration the renderer has not seen yet forces it to compile those shader variants
## THERE AND THEN, synchronously, mid-dive — which is the hitch. Building it late also meant
## the very first dive of every session paid the cost, every session.
##
## Two changes. It is built up front, at load, with the rest of the world; and its pipeline
## configuration is deliberately kept as close to the surface environment's as the look
## allows (same FILMIC tonemap, glow and SSAO left ON) so the swap changes PARAMETER VALUES
## rather than the shape of the pipeline. Then `_prewarm_underwater_env()` renders one
## throwaway off-screen frame through it so the compile happens during load, where a stall
## is invisible, instead of the moment the player's head goes under.
func _build_underwater_env() -> void:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.015, 0.075, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.12, 0.27, 0.29)
	e.ambient_light_energy = 0.7
	e.fog_enabled = true
	e.fog_light_color = Color(0.045, 0.16, 0.18)   # North Atlantic murk, not lagoon
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 4.0
	# Matched to the surface environment on purpose — see the note above. These cost little
	# in a fogged-in view and keep the dive from switching pipeline shape.
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 0.8
	e.ssao_enabled = true
	e.ssao_radius = 2.0
	e.ssao_intensity = 1.5
	_underwater_env = e

## Render a single 8x8 off-screen frame through the underwater environment so its shader
## variants are compiled while the level is still loading. Deliberately a SubViewport and
## not the real camera: assigning it to the player's camera for a frame would compile the
## same thing but flash the whole screen teal on startup.
func _prewarm_underwater_env() -> void:
	if _underwater_env == null:
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(8, 8)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.own_world_3d = true
	add_child(vp)
	var c := Camera3D.new()
	c.environment = _underwater_env
	vp.add_child(c)
	c.current = true
	# Two frames: one to render, one to be sure it landed. Then it is dead weight — drop it.
	await get_tree().process_frame
	await get_tree().process_frame
	vp.queue_free()

## Swap the camera's own Environment when it dips below the swell — dense teal
## fog, dim ambient, no sky — and duck the topside audio. Camera-level override
## means SunController and the storms keep owning the surface environment.
func _process(_delta: float) -> void:
	if player == null:
		return
	var cam: Camera3D = player.get_node_or_null("Head/Camera3D")
	if cam == null:
		return
	var wave_y: float = Gyre.swim_line(Vector2(cam.global_position.x, cam.global_position.z), Gyre.water_time())
	var under: bool = cam.global_position.y < wave_y
	# The sun's shadow cascade is not worth rendering once the water has taken the sun (see
	# SunController.set_dive_depth — measured at 3.33 ms and 796 draw calls at -12 m). The
	# depth is already in hand here, so this is one float compare a frame and a flip on the
	# frames the state actually changes.
	if sun_ctl != null:
		sun_ctl.set_dive_depth(maxf(wave_y - cam.global_position.y, 0.0) if under else 0.0)
	if under and not _fx_owns_grade():
		# FALLBACK ONLY. Deeper = darker and thicker; near the surface the world still glows.
		#
		# TWO DEPTH GRADES WERE WRITING THIS ONE ENVIRONMENT EVERY FRAME, and s34 lost an
		# hour to it. underwater_fx has a far more careful grade (colour, shimmer, storm
		# murk, the abyss ramp) and `process_priority = 100` so it runs last and wins — which
		# means these two lines were dead in the shipped game while remaining the number a
		# debugger, a probe, or a fog sweep reads back off the camera. The s34 sweep
		# photographed five different candidate curves and got `density=0.1700` for all five:
		# exactly this lerp at its ceiling, because the harness had removed the player from
		# the "player" group and underwater_fx finds the player THROUGH that group, so the
		# real grade had silently switched itself off and left this one standing.
		#
		# So it is now explicitly the fallback it always was in practice: it still grades the
		# water for any scene that builds Main WITHOUT underwater_world's FX node, and it
		# stops fighting the owner of that environment everywhere else.
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
