extends Node3D
## WALL SHOT — the vertical-lines discriminator. Films one concrete wall, up close, at a
## grazing view angle, under LOW sun and then HIGH sun, standing still and then strafing.
##
## The owner's report has narrowed once already: after anisotropic filtering went 2x -> 16x
## the lines stopped MOVING but are still there. The two candidates that survive are
## shadow-texel acne (bands come and go with SUN angle, indifferent to the camera) and
## static texture/normal banding (identical at every sun angle). One reel at two clock
## positions separates them in a single windowed run:
##   godot --path . --fixed-fps 60 tests/WallShot.tscn -- /tmp/wallshot
##
## Subject: the stair tower's WEST wall (x = 21, z -6..2, rising from y 2) — big, flat,
## concrete_tower(), reachable eye positions, and the surface the owner stares at while
## climbing. Camera at deck eye height, 1.2 m off the wall, looking along it at a grazing
## angle — the geometry that maximises both candidate artifacts.

const SHOT_PX := Vector2i(1152, 648)

var _dir: String = "/tmp/wallshot"
var _main: Node3D
var _cam: Camera3D
var _frame_i: int = 0

func _process(_d: float) -> void:
	if get_tree().paused:
		get_tree().paused = false
	var pm: Node = get_tree().get_first_node_in_group("pause_menu")
	if pm != null and pm.get("panel") != null:
		(pm.get("panel") as CanvasItem).visible = false

func _pin_storm() -> void:
	if _main == null:
		return
	var st: Node = _main.get("storm")
	if st != null:
		st.set_process(false)
		st.set("_intensity", 0.0)
		st.set("_phase", 0)

## Park the day at a chosen fraction. force_phase alone resets to f=0 (the red end — the
## s22 trap), so the intra-day position is written explicitly.
func _set_day(frac: float) -> void:
	GameClock.force_phase(GameClock.Phase.DAY)
	GameClock._phase_elapsed_sec = \
		float(GameClock.phase_durations_minutes[GameClock.Phase.DAY]) * 60.0 * frac

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_dir = a
	DirAccess.make_dir_recursive_absolute(_dir)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	if _main == null or _main.get_script() == null:
		print("[wall] Main.tscn came back WITHOUT its script")
		get_tree().quit(1)
		return
	add_child(_main)
	var t0: int = Time.get_ticks_msec()
	var waited: int = 0
	while Time.get_ticks_msec() - t0 < 22000 or waited < 180:
		await get_tree().process_frame
		waited += 1
	print("[wall] world built in %d ms" % (Time.get_ticks_msec() - t0))
	var player: Node3D = get_tree().get_first_node_in_group("player")
	player.set_physics_process(false)
	_cam = player.get_node("Head/Camera3D")
	_cam.current = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	# Eye 1.2 m out from the tower's west face (x 21), at standing eye height on the main
	# deck (y 18 + 1.6), near the wall's south end, looking NORTH along the wall so the
	# face crosses the frame at a hard grazing angle.
	var eye := Vector3(21.0 - 1.2, 19.6, -5.0)
	var aim := Vector3(21.0, 19.4, 1.5)
	# Also confirm the sun landed where we put it — the read-back rule.
	var sun: DirectionalLight3D = null
	for n in _main.find_children("*", "DirectionalLight3D", false, false):
		sun = n
		break
	# Pass 3 is the CARRIER experiment: same noon light, concrete normal maps OFF. The
	# striping survives both sun angles (so it is not shadow acne) and the source textures
	# measure isotropic (so it is not painted in) — what remains is the sampling path, and
	# the normal map is the one input whose grazing-angle shading could manufacture
	# regular bands out of nothing. One toggled pass names the carrier for certain.
	var toggled: Array[StandardMaterial3D] = []
	for pass_spec in [[0.45, "noon", false], [0.45, "soft", true]]:
		_set_day(float(pass_spec[0]))
		_pin_storm()
		if bool(pass_spec[2]):
			# THE SOFT-ALBEDO EXPERIMENT. The normal-map toggles measured a wall-region
			# diff of exactly 0.0, so the carrier is the ALBEDO SAMPLE itself; this pass
			# swaps the whole Concrete012 family onto a 1.1 px pre-blurred copy — energy
			# above the grazing-angle Nyquist removed at the SOURCE, which no filter
			# setting on this backend has managed to do.
			var soft: Texture2D = load("res://assets/textures/Concrete012_soft/Concrete012_1K-JPG_Color.jpg")
			var softn: Texture2D = load("res://assets/textures/Concrete012_soft/Concrete012_1K-JPG_NormalGL.jpg")
			for key in ["concrete", "concrete_tower", "concrete_tower_base", "concrete_floor", "tide_band", "interior_wall", "dirty_white_panel"]:
				var m = MatLib._cache.get(key)
				if m is StandardMaterial3D:
					(m as StandardMaterial3D).albedo_texture = soft
					(m as StandardMaterial3D).normal_texture = softn
					toggled.append(m)
			print("[wall] soft maps ON for %d concrete materials" % toggled.size())
		for i in range(30):
			await get_tree().process_frame
		if sun != null:
			print("[wall] %s sun rotation %s" % [pass_spec[1],
				str(sun.rotation_degrees.snappedf(0.1))])
		# IDENTIFY THE SURFACE IN FRAME — the trap file's "search from the PICTURE" rule,
		# learned again the hard way: two carrier experiments toggled seven materials to
		# provable zero effect because the striped wall was never any of them. The ray
		# through the striped pixels ends the guessing.
		if pass_spec[1] == "lowsun":
			var vp: Vector2 = get_viewport().get_visible_rect().size
			for px in [Vector2(0.22, 0.42), Vector2(0.35, 0.45)]:
				var origin: Vector3 = _cam.project_ray_origin(px * vp)
				var dirn: Vector3 = _cam.project_ray_normal(px * vp)
				var q := PhysicsRayQueryParameters3D.create(origin, origin + dirn * 30.0)
				q.collision_mask = 1
				var hit: Dictionary = get_tree().root.world_3d.direct_space_state.intersect_ray(q)
				if hit.is_empty():
					print("[wall] pixel %s: no hit" % str(px))
					continue
				var col: Node = hit["collider"]
				print("[wall] pixel %s hits %s at %s (owner path %s)"
					% [str(px), col.name, str((hit["position"] as Vector3).snappedf(0.01)),
						str(col.get_path())])
		# 2 s standing still, then 2 s strafing along the wall — 12 frames each at ~6 fps.
		for f in range(24):
			_pin_storm()
			var slide: float = 0.0 if f < 12 else float(f - 12) * 0.18
			_cam.global_position = eye + Vector3(0, 0, slide)
			_cam.look_at(aim + Vector3(0, 0, slide * 0.4), Vector3.UP)
			for w in range(10):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var tex: Texture2D = get_viewport().get_texture()
			var img: Image = tex.get_image() if tex != null else null
			if img != null:
				# NATIVE PIXELS, NO RESIZE. The first six investigation passes measured a
				# striping that survived every material intervention at exactly the same
				# amplitude — because the downscale HERE was manufacturing it: a ~2:1
				# bilinear resize of fine concrete texture is a moire generator, and the
				# instrument was photographing its own artifact (the s38 capture-cost
				# lesson in spatial rather than temporal form). Frames now ship at native
				# resolution; disk is cheaper than another false carrier.
				img.save_png("%s/wall_%s_%02d.png" % [_dir, pass_spec[1], f])
			_frame_i += 1
	for m in toggled:
		m.normal_enabled = true
	print("[wall] done -> %s (%d frames)" % [_dir, _frame_i])
	get_tree().quit()
