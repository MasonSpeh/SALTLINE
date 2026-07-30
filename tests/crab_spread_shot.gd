extends Node
## PICTURES OF THE PACK'S SPACING. The owner's s21 report is a visual one — "the giant crabs
## still just sit unnaturally next to each other all day" — so the fix has to be judged in a
## frame, not only in CrabLifeProbe's table.
##
## EVERY VANTAGE IS DERIVED FROM THE LIVE ANIMALS, never typed. crab.gd works its day
## territory out at runtime from the spawner's cling loops and its own pack-mates, so a
## hand-written camera mark would be a guess about where the crabs ended up — and the s20 reef
## pass lost a whole render pass to exactly that (ten frames of bare coral, because the shot
## list only ever reported the camera position it *asked* for). This asks the pack where it is,
## puts the diver out in open water off the corner the two crabs on a caisson share, and aims
## at the midpoint of the pair. Both animals in one frame is the whole point: a picture of one
## crab proves nothing about spacing.
##
## Flies the PLAYER, not a free camera — underwater_fx keys its fog, grade and light off the
## player's own position, so a detached camera photographs the reef in air. And it takes the
## lens OUT of the "player" group, because crab.gd hunts that group and a previous crab census
## photographed six crabs lined up chasing the camera, which is itself a way to fake a
## clustering bug.
##
## Must run WINDOWED. --headless never draws.
##   godot --path . res://tests/CrabSpreadShot.tscn -- <out_dir> [--fill] [--tag=<name>]

const TIME_SCALE: float = 8.0
const SETTLE_SEC: float = 110.0   ## game seconds of daylight before the first frame: long
## enough for every crab to have walked off its spawn den into its own strip and slice, and to
## be part-way through a roam leg rather than standing on the exact point it started from.
const CORNER_OUT: float = 12.0    ## how far off the shared corner the diver hovers. Wide
## enough that a pair 5-8 m apart both fit the ~107 degree view; near enough to out-range the
## underwater fog.

var main: Node3D
var _dir: String = "/tmp/crab_spread"
var _tag: String = "day"
var _fill: bool = false
var _lights: Array[OmniLight3D] = []
var _pause_panel: Control = null
var _log: PackedStringArray = PackedStringArray()

## Undo the focus-out auto-pause EVERY frame, and hide the panel it opens. A harness driven
## from a terminal never holds window focus, so pause_menu.gd pauses on
## NOTIFICATION_APPLICATION_FOCUS_OUT: a paused world still renders, so the frames come back
## beautiful, stable and meaningless, with a PAUSED panel across the middle. The panel is its
## own CanvasLayer and survives get_tree().paused = false, so it has to be hidden separately.
func _process(_d: float) -> void:
	if get_tree().paused:
		get_tree().paused = false
	if _pause_panel == null:
		for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
			var s: Script = n.get_script()
			if s != null and String(s.resource_path).ends_with("pause_menu.gd"):
				_pause_panel = n.get("panel") as Control
				break
	if _pause_panel and _pause_panel.visible:
		_pause_panel.visible = false

func _say(msg: String) -> void:
	print(msg)
	_log.append(msg)
	var f := FileAccess.open(_dir + "/shots.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_log) + "\n")
		f.close()

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--fill":
			_fill = true
		elif a.begins_with("--tag="):
			_tag = a.substr(6)
		elif not a.begins_with("--"):
			_dir = a
	# PROCESS_MODE_ALWAYS, or the unpause above is itself switched off the instant the tree
	# pauses (a Node inherits PAUSABLE) while create_timer keeps firing — so the shot list runs
	# to completion over a frozen world. Necessary AND not sufficient on its own; see _process.
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(_dir)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	main = packed.instantiate() if packed != null else null
	# A parse error anywhere in the world scripts hands back a bare Node3D with its script
	# dropped: it builds nothing and photographs black water while every probe passes
	# vacuously. Refuse rather than publish an empty frame.
	if main == null or main.get_script() == null:
		print("[spread] Main.tscn did not load with its script — ABORT, nothing to photograph")
		get_tree().quit(1)
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
	p.remove_from_group("player")
	_say("[spread] world up — lens dropped from the 'player' group, so the pack ignores it")

	GameClock.force_phase(GameClock.Phase.DAY)
	GameClock.set("_phase_elapsed_sec", 0.4 * 34.0 * 60.0)
	_calm()
	if _fill:
		_light_the_set()
	await _run_for(SETTLE_SEC)
	_calm()

	var crabs: Array = []
	for c in get_tree().get_nodes_in_group("giant_crab"):
		if c.has_method("territory") and bool(c.territory()["ready"]):
			crabs.append(c)
	crabs.sort_custom(func(a, b): return int(a.spawn_index) < int(b.spawn_index))
	_say("[spread] %d crabs with a day territory" % crabs.size())
	if crabs.is_empty():
		get_tree().quit(1)
		return

	# ---- one frame per caisson: the two crabs that share it, together in shot.
	var legs: Dictionary = {}
	for c in crabs:
		var leg: Vector3 = c.territory()["leg"]
		var key: String = ("N" if leg.z > 0.0 else "S") + ("E" if leg.x > 0.0 else "W")
		if not legs.has(key):
			legs[key] = []
		(legs[key] as Array).append(c)
	for key in legs:
		await _pair_shot(key, legs[key] as Array)

	# ---- and the pack at rig scale, from out in the water off each end.
	await _wide_shot(crabs, Vector3(46.0, -7.0, -30.0), "wide_south")
	await _wide_shot(crabs, Vector3(-46.0, -7.0, 30.0), "wide_north")
	await _wide_shot(crabs, Vector3(46.0, -7.0, 30.0), "wide_east")

	_roll_call(crabs)
	_say("[spread] done")
	get_tree().quit(0)

## The corner shot. `group` is the crabs on one caisson; the diver hovers out along the sum of
## the face normals they occupy — i.e. off the corner between their two walls — and looks at
## the midpoint of the pair, so the frame contains both of them and the concrete between.
func _pair_shot(key: String, group: Array) -> void:
	var leg: Vector3 = group[0].territory()["leg"]
	var out: Vector3 = Vector3.ZERO
	var mid: Vector3 = Vector3.ZERO
	for c in group:
		out += (c.territory()["face"] as Vector3)
		mid += (c as Node3D).global_position
	mid /= float(group.size())
	if out.length() < 0.3:
		# The pair is on OPPOSITE faces (six metres of concrete between them, so they can
		# never be in one frame from outside). Shoot along the face of the shallower one.
		out = group[0].territory()["face"]
	out = out.normalized()
	var eye: Vector3 = Vector3(leg.x, mid.y, leg.z) + out * CORNER_OUT
	await _shot(eye, mid, "%s_pair_%s" % [_tag, key], group)

## The whole submerged rig from one corner of the ocean, aimed at the middle of the pack.
func _wide_shot(crabs: Array, eye: Vector3, name_: String) -> void:
	var mid: Vector3 = Vector3.ZERO
	for c in crabs:
		mid += (c as Node3D).global_position
	mid /= float(crabs.size())
	await _shot(eye, mid, "%s_%s" % [_tag, name_], crabs)

## Place, then AIM FROM WHERE THE EYE ACTUALLY IS. The camera sits ~1.6 m above the player's
## origin, so solving the yaw and pitch from the position we asked for frames a point well
## below the subject. So: set the body, read the real camera transform back, solve the angles
## against that, and print both — the reported eye and the distance to the subject are what
## prove the framing was right (or that the subject was simply tiny, which is how s20's reef
## fish shots were finally understood).
func _aim(eye: Vector3, at: Vector3) -> Camera3D:
	var p: Node3D = main.player
	p.set("input_locked", true)
	p.set("velocity", Vector3.ZERO)
	p.global_position = eye
	var cam: Camera3D = p.get_node_or_null("Head/Camera3D") as Camera3D
	if cam == null:
		return null
	p.global_position = eye - (cam.global_position - p.global_position)
	var dir: Vector3 = (at - cam.global_position).normalized()
	var flat: Vector2 = Vector2(dir.x, dir.z)
	if flat.length() > 0.001:
		p.rotation.y = atan2(-dir.x, -dir.z)
	(p.get_node("Head") as Node3D).rotation.x = asin(clampf(dir.y, -1.0, 1.0))
	return cam

func _shot(eye: Vector3, at: Vector3, name_: String, subjects: Array) -> void:
	_calm()
	var cam: Camera3D = _aim(eye, at)
	await get_tree().create_timer(0.9).timeout
	_calm()
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/crab_%s.png" % [_dir, name_]
	var err: int = img.save_png(path)
	var seen: Array[String] = []
	for c in subjects:
		var q: Vector3 = (c as Node3D).global_position
		seen.append("%d@%.1fm%s" % [int(c.spawn_index), cam.global_position.distance_to(q),
			"" if cam.is_position_in_frustum(q) else "(OFF FRAME)"])
	_say("[spread] %s  err=%d  eye asked %s got %s  subject %s  ->  %s"
		% [path, err, str(eye.snapped(Vector3.ONE * 0.1)),
			str(cam.global_position.snapped(Vector3.ONE * 0.1)),
			str(at.snapped(Vector3.ONE * 0.1)), " ".join(seen)])

## Where every crab is, and how far from its nearest pack-mate, next to the frames — so the
## pictures can be read against a list instead of squinted at.
func _roll_call(crabs: Array) -> void:
	_say("[spread] roll call (day):")
	var worst: float = INF
	for i in range(crabs.size()):
		var near: float = INF
		var who: int = -1
		for j in range(crabs.size()):
			if i == j:
				continue
			var d: float = (crabs[i] as Node3D).global_position.distance_to(
				(crabs[j] as Node3D).global_position)
			if d < near:
				near = d
				who = int(crabs[j].spawn_index)
		worst = minf(worst, near)
		_say("   crab %d at %-24s nearest pack-mate: crab %d at %.2f m"
			% [int(crabs[i].spawn_index),
				str((crabs[i] as Node3D).global_position.snapped(Vector3.ONE * 0.01)),
				who, near])
	_say("[spread] closest pair in this frame set: %.2f m" % worst)

## Weather is not the subject: a squall mid-pass puts a curtain of rain between the lens and
## the animals and drops the light.
func _calm() -> void:
	var st = main.storm
	if st == null:
		return
	st._phase = StormSystem.StormPhase.CLEAR
	st._intensity = 0.0
	st._timer = 9999.0
	if st.sun_ctl:
		st.sun_ctl.set_storm(0.0)

## Optional photographer's fill, off by default. The crabs are naturalistic — no glow — and
## fifteen metres down the daylight is already heavily graded, so `--fill` exists for the case
## where an honest frame is too dark to count animals in. It is lighting for a census, not
## lighting design, and every frame says whether it was used.
func _light_the_set() -> void:
	for p in [Vector3(34.0, -8.0, -12.0), Vector3(-34.0, -8.0, 12.0),
			Vector3(34.0, -8.0, 12.0), Vector3(-34.0, -8.0, -12.0)]:
		var l := OmniLight3D.new()
		l.light_energy = 6.0
		l.omni_range = 40.0
		l.light_color = Color(0.74, 0.86, 0.95)
		l.shadow_enabled = false
		main.add_child(l)
		l.global_position = p
		_lights.append(l)

## get_process_delta_time() is already scaled by Engine.time_scale, so it is summed raw —
## multiplying by the scale again is the classic mistake here.
func _run_for(sec: float) -> void:
	Engine.time_scale = TIME_SCALE
	var t: float = 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()
	Engine.time_scale = 1.0
