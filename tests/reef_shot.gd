extends Node
## Photographs the caisson-leg reef and the foundation starfish from the water, at the
## depths and angles a diving player actually sees them from. The owner judges this work
## by picture, so this is the harness the work is iterated against.
##
## Flies the PLAYER rather than a free camera: underwater_fx keys its fog, colour grade
## and light off the player's own position, so a detached camera would photograph the
## reef in air. Force-unpauses every frame — the pause menu auto-pauses on focus-out and
## a paused world still renders, which yields beautiful meaningless frames
## (docs/AGENT_TRAPS.md).
##
## Must run WINDOWED. --headless never draws.
##   godot --path . res://tests/ReefShot.tscn -- <out_dir> [--only=<substr>] [--night]

var main: Node3D
var _dir: String = "/tmp"
var _only: String = ""
var _night: bool = false

## EMISSION SWEEP. `--glow=0.2,0.35,0.5` re-shoots the whole (or `--only=`) list once per
## value, scaling every reef material's emission energy by that value over LegReef.GLOW.
## It exists because the right number cannot be reasoned to: the world environment blooms
## above 0.8, the underwater colour grade sits on top of that, and the first s20 attempt at
## 1.35 rendered the entire reef as featureless white. One launch, one world build, N
## exposures of the same frame — which is the only way to compare them honestly.
var _glows: Array[float] = []
## material -> the energy LegReef gave it, so the sweep scales rather than flattens the
## per-species factors (the barnacles are chalk and run at 0.45 of a coral).
var _base_glow: Dictionary = {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7).to_lower()
		elif a.begins_with("--glow="):
			for v in a.substr(7).split(","):
				_glows.append(float(v))
		elif a == "--night":
			_night = true
		elif not a.begins_with("--"):
			_dir = a
	# PROCESS_MODE_ALWAYS or the unpause in _process stops being called the moment the tree
	# pauses — a Node's default process_mode resolves to PAUSABLE at the root, so the handler
	# that is supposed to recover from a focus-out pause is itself switched off by it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(_dir)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	main = packed.instantiate() if packed != null else null
	# A parse error anywhere in the world scripts hands back a bare Node3D with its
	# script dropped, which builds nothing and photographs black water. Fall back to
	# rig + reef + a key light so the geometry can still be judged while a neighbouring
	# session has main.gd's dependency graph broken.
	if main != null and main.get_script() == null:
		main.queue_free()
		main = null
	if main == null:
		print("[reef] Main.tscn did not load — RIG-ONLY render (no ocean, no fog)")
		await _rig_only()
		return
	add_child(main)
	await get_tree().create_timer(9.0).timeout
	main._countdown = 0.0
	if main.hud != null:
		if main.hud.fade_rect != null:
			main.hud.fade_rect.color.a = 0.0
		main.hud.visible = false
	var p: Node3D = main.player
	p.set("_fly", true)
	(p as CollisionObject3D).set_collision_layer_value(1, false)
	(p as CollisionObject3D).set_collision_mask_value(1, false)
	# Fauna hunts anything in the "player" group; leaving the lens in it once produced a
	# crab census of six crabs chasing the camera.
	p.remove_from_group("player")
	GameClock.force_phase(GameClock.Phase.NIGHT if _night else GameClock.Phase.DAY)
	print("[reef] world up, output -> ", _dir)

	var tag: String = "night" if _night else "day"
	if _glows.is_empty():
		await _shots(tag)
	else:
		for g in _glows:
			_set_glow(g)
			await _shots("g%03d_%s" % [int(round(g * 100.0)), tag])
	print("[reef] done")
	get_tree().quit()

## One camera per LIVE snail — found in the tree, not derived from the spawn table.
##
## The first version of this read LegReef.SNAIL_SPOTS and framed each seat. Every frame came
## back with no snail in it, for the obvious reason: they crawl. By the time the shutter fires
## (nine seconds of world start-up plus a shot list) a 0.13 m/s animal has moved metres, and
## half the seats are inside the kelp stand anyway. So this asks the world where they actually
## are and puts the lens 2.4 m off the face in front of each one.
func _snail_frames() -> Array:
	var out: Array = []
	var lr: GDScript = load("res://scripts/world/leg_reef.gd")
	var legs: Array = lr.LEGS
	var i: int = 0
	for group in ["snail_lamp", "snail_pyramid"]:
		for node in get_tree().get_nodes_in_group(group):
			if not (node is Node3D):
				continue
			var pos: Vector3 = (node as Node3D).global_position
			# only the ones on a caisson — BloomFauna's own snails live on the pontoon tops
			# and the topside plate and are somebody else's picture
			if pos.y > -3.0:
				continue
			var leg: Vector2 = legs[0]
			for l in legs:
				if Vector2(pos.x - l.x, pos.z - l.y).length() \
						< Vector2(pos.x - leg.x, pos.z - leg.y).length():
					leg = l
			var d := Vector2(pos.x - leg.x, pos.z - leg.y)
			var n := Vector3(signf(d.x), 0.0, 0.0) if absf(d.x) > absf(d.y) \
				else Vector3(0.0, 0.0, signf(d.y))
			# yaw convention: forward = (-sin y, 0, -cos y), so looking back along -n
			i += 1
			# 1.4 m off the face: a 0.9 m animal on a wall covered in pale coral of roughly
			# its own colour is not readable from 2.4 m out, which is what the first pass
			# proved. Close enough that the shell fills a third of the frame.
			out.append([pos + n * 1.4 + Vector3(0.0, 0.22, 0.0),
				rad_to_deg(atan2(n.x, n.z)), -9.0,
				"snail%02d_%s" % [i, "lamp" if group == "snail_lamp" else "pyramid"]])
	return out

## Scale every reef material's emission to `g`, keeping the per-species ratio LegReef chose.
func _set_glow(g: float) -> void:
	var n: int = 0
	for node in main.find_children("LegReef_*", "MultiMeshInstance3D", true, false):
		var mat: Material = (node as MultiMeshInstance3D).material_override
		if not (mat is StandardMaterial3D):
			continue
		var sm: StandardMaterial3D = mat
		if not _base_glow.has(sm):
			_base_glow[sm] = sm.emission_energy_multiplier
		var base: float = float(_base_glow[sm])
		var ref: float = load("res://scripts/world/leg_reef.gd").GLOW
		sm.emission_energy_multiplier = g * (base / maxf(ref, 0.001))
		n += 1
	print("[reef] glow -> %.2f on %d reef materials" % [g, n])

func _shots(tag: String) -> void:
	# Positions below are EYE positions; _shot drops the body by EYE_UP.
	# Yaw convention, checked rather than assumed: forward = (-sin y, 0, -cos y), so
	# yaw 0 looks -Z, 90 looks -X, -90 looks +X, 180 looks +Z. The first pass of this
	# list had every leg shot facing away from the leg.
	# --- down the SE leg (x 22, z -12): the leg a swimmer meets first off the wet deck
	await _shot(Vector3(30.0, -13.5, -12.0), 90.0, -4.0, "leg_se_band_" + tag)
	await _shot(Vector3(29.0, -9.0, -12.0), 90.0, -34.0, "leg_se_downlook_" + tag)
	await _shot(Vector3(27.5, -21.0, -12.0), 90.0, 24.0, "leg_se_uplook_" + tag)
	await _shot(Vector3(26.5, -16.0, -17.0), 138.0, -6.0, "leg_se_oblique_" + tag)
	# --- close enough to read one colony's seating against the concrete
	await _shot(Vector3(26.8, -14.0, -12.4), 90.0, -8.0, "colony_close_" + tag)
	await _shot(Vector3(25.9, -18.5, -10.5), 69.0, 10.0, "colony_close2_" + tag)
	# --- the NE leg from inboard, so the reef is seen against open water
	await _shot(Vector3(22.0, -15.0, 4.0), 180.0, -6.0, "leg_ne_inboard_" + tag)
	# --- the whole west side: two legs and the band between them
	await _shot(Vector3(-34.0, -14.0, 0.0), -90.0, -2.0, "west_wide_" + tag)
	# --- the reef band's top edge, showing it starts BELOW the kelp
	await _shot(Vector3(30.0, -10.0, -12.0), 90.0, -26.0, "band_top_kelp_" + tag)
	# --- foundation starfish: the south pontoon's outer wall (z -16), seen from south
	await _shot(Vector3(-6.0, -1.6, -21.0), 180.0, -2.0, "foundation_south_" + tag)
	await _shot(Vector3(-13.0, -1.4, -20.0), 200.0, -4.0, "foundation_south2_" + tag)
	# --- foundation starfish: under the pontoon, looking up at the underside (y -3.05)
	await _shot(Vector3(10.0, -6.5, -12.0), 10.0, 52.0, "foundation_under_" + tag)
	await _shot(Vector3(-2.0, -5.6, 12.0), 0.0, 46.0, "foundation_under2_" + tag)
	# --- the seven-arm giant on the south wall at (-6, -1.7, -16)
	await _shot(Vector3(-6.0, -1.7, -19.0), 180.0, 0.0, "star_huge_" + tag)
	# --- THE SNAILS on the caisson. Positions are derived from LegReef.SNAIL_SPOTS the same
	# way LegReef derives them (lerp CRUST_TOP..BAND_BOTTOM by the spot's depth fraction), so
	# these frames follow the spawn table instead of restating it. Shot 3 m off the face; the
	# animals crawl at 0.13 m/s so they are still in frame by the time the shot is taken.
	for spot in _snail_frames():
		await _shot(spot[0], spot[1], spot[2], spot[3] + "_" + tag)
	# --- the whole underwater silhouette from off the south-east quarter
	await _shot(Vector3(40.0, -9.0, -30.0), 127.0, -6.0, "rig_underwater_" + tag)

## Rig + reef + a key light + a free camera. Same shot list, no ocean.
var _cam: Camera3D

func _rig_only() -> void:
	var root := Node3D.new()
	root.add_child(RigBuilder.new())
	root.add_child(load("res://scripts/world/leg_reef.gd").new())
	add_child(root)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, -128.0, 0.0)
	key.light_energy = 1.5
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, 62.0, 0.0)
	fill.light_energy = 0.7
	fill.light_color = Color(0.72, 0.86, 1.0)
	add_child(fill)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.11, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.62, 0.68)
	env.ambient_light_energy = 0.9
	we.environment = env
	add_child(we)
	_cam = Camera3D.new()
	_cam.current = true
	add_child(_cam)
	for i in range(30):
		await get_tree().process_frame
	await _shots("rigonly")
	print("[reef] done (rig-only)")
	get_tree().quit()

var _pause: CanvasLayer = null

func _process(_d: float) -> void:
	# a focus-out pause freezes the world mid-capture and pastes PAUSED over every frame
	get_tree().paused = false
	# Unpausing is not enough: PauseMenu's panel is its own CanvasLayer, and it stays drawn
	# after the tree resumes. The s20 pass lost a whole render this way — the first eight
	# frames were clean and every frame after the moment another session's window took focus
	# had a PAUSED dialog across the middle of it. Hide the panel, every frame, as
	# reef_fish_shot and handbook_shot already do.
	if _pause == null:
		_pause = _find_pause(get_tree().root)
	if _pause != null:
		var panel: Variant = _pause.get("panel")
		if panel is CanvasItem:
			(panel as CanvasItem).visible = false

func _find_pause(n: Node) -> CanvasLayer:
	var s: Script = n.get_script()
	if s != null and String(s.resource_path).ends_with("pause_menu.gd"):
		return n as CanvasLayer
	for c in n.get_children():
		var got: CanvasLayer = _find_pause(c)
		if got != null:
			return got
	return null

## The camera's eye is ~1.6 m above the player node's origin, so aiming a shot from the
## node position photographs the water 1.6 m below what you meant to look at.
const EYE_UP: float = 1.6

func _place(pos: Vector3, yaw_deg: float, pitch_deg: float) -> void:
	if _cam != null:
		_cam.global_position = pos
		_cam.rotation = Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0)
		return
	var p: Node3D = main.player
	p.global_position = pos - Vector3(0.0, EYE_UP, 0.0)
	p.rotation.y = deg_to_rad(yaw_deg)
	p.get_node("Head").rotation.x = deg_to_rad(pitch_deg)
	p.set("velocity", Vector3.ZERO)
	p.set("input_locked", true)

func _shot(pos: Vector3, yaw_deg: float, pitch_deg: float, name_: String) -> void:
	if _only != "" and not name_.to_lower().contains(_only):
		return
	_place(pos, yaw_deg, pitch_deg)
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/reef_%s.png" % [_dir, name_]
	print("[reef] saved ", path, " err=", img.save_png(path))
