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

const CRAB := preload("res://scripts/world/crab.gd")
const TIME_SCALE: float = 8.0
const SETTLE_SEC: float = 110.0   ## game seconds of daylight before the first frame: long
## enough for every crab to have walked off its spawn den into its own strip and slice, and to
## be part-way through a roam leg rather than standing on the exact point it started from.
const CORNER_OUT: float = 10.5    ## how far off the shared corner the diver hovers. Wide
## enough that a pair 5-10 m apart both fit the ~107 degree view; near enough to out-range the
## underwater fog, which measurably swallows the rig past about 30 m — the first cut of this
## harness took three "whole pack" frames from 46 m out and every one came back as flat teal.
const PORTRAIT_OUT: float = 5.0   ## and how close a single-animal portrait is taken from. A
## giant crab is ~1.1 m across and the view is ~107 degrees, so this is what makes it fill a
## useful part of the frame rather than being the seven pixels s20's reef fish taught us about.

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
	# One portrait each: every animal alone on its own stretch of concrete, close enough to be
	# read as a crab. This is the "individually, not lined up together" half of the brief.
	for c in crabs:
		await _portrait(c)
	# Then the pair frames — the spacing itself. Twice: once in honest daylight, and once with
	# a photographer's fill, because fifteen metres down the daylight is heavily graded and a
	# census nobody can count is not a census. Every filename says which it is.
	for key in legs:
		await _pair_shot(key, legs[key] as Array, "")
	_light_the_set()
	await get_tree().create_timer(0.4).timeout
	for key in legs:
		await _pair_shot(key, legs[key] as Array, "_lit")
	_douse()

	_roll_call(crabs)
	_say("[spread] done")
	get_tree().quit(0)

## One animal, face on, from the water in front of its own patch.
func _portrait(c: Node3D) -> void:
	var n: Vector3 = c.territory()["face"]
	var at: Vector3 = c.global_position
	await _shot(at + n * PORTRAIT_OUT + Vector3.UP * 0.9, at,
		"%s_crab%d" % [_tag, int(c.spawn_index)], [c])

## The corner shot: the two crabs that share a caisson, together in one frame.
##
## The diver hovers out along the SUM of the face normals they occupy — the bisector of the
## corner between their two walls — and aims at THE CORNER, not at the midpoint of the pair.
## Aiming at the pair looks obvious and is wrong: the midpoint sits well off the bisector once
## the two animals are properly spread, which swings the view round until one of the two faces
## is edge on. The first cut of this harness did exactly that and the SE frame came back with
## one crab clearly on a wall and the other on a foreshortened sliver of concrete four pixels
## wide. Aim down the bisector and both faces sit at 45 degrees.
func _pair_shot(key: String, group: Array, suffix: String) -> void:
	var leg: Vector3 = group[0].territory()["leg"]
	var out: Vector3 = Vector3.ZERO
	var mid_y: float = 0.0
	for c in group:
		out += (c.territory()["face"] as Vector3)
		mid_y += (c as Node3D).global_position.y
	mid_y /= float(group.size())
	if out.length() < 0.3:
		# The pair is on OPPOSITE faces — six metres of concrete between them, so no vantage
		# outside the leg can hold both. Shoot the shallower one's wall square on.
		out = group[0].territory()["face"]
	# The point being aimed at: LEG_HALF out along EACH occupied normal, i.e. the shared corner
	# for a perpendicular pair and the face centre for a single wall. The un-normalized sum does
	# both without a special case.
	var axis: Vector3 = Vector3(leg.x, mid_y, leg.z)
	var corner: Vector3 = axis + out * float(CRAB.LEG_HALF)
	var eye: Vector3 = axis + out.normalized() * CORNER_OUT
	await _shot(eye, corner, "%s_pair_%s%s" % [_tag, key, suffix], group)

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
	# EVERY crab in the pack, not only the ones this frame is aimed at. Reading a frame back by
	# eye and asking "is that a second crab behind the kelp?" is exactly the kind of squinting
	# that gets a wrong answer written down as a result, so the harness answers it: who is in
	# this frustum, how far off, and which of them the shot was actually about.
	var want: Array[int] = []
	for c in subjects:
		want.append(int(c.spawn_index))
	var seen: Array[String] = []
	for c in get_tree().get_nodes_in_group("giant_crab"):
		if not c.has_method("territory"):
			continue                 # a surfaced King Crab: not part of the day pack
		var q: Vector3 = (c as Node3D).global_position
		var i: int = int(c.spawn_index)
		if not cam.is_position_in_frustum(q):
			if want.has(i):
				seen.append("%d:OFF-FRAME" % i)
			continue
		seen.append("%s%d@%.1fm" % ["*" if want.has(i) else "", i,
			cam.global_position.distance_to(q)])
	_say("[spread] %s  err=%d  eye asked %s got %s  aim %s  in frame (*=subject): %s"
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
	if not _lights.is_empty():
		return
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

func _douse() -> void:
	for l in _lights:
		l.queue_free()
	_lights.clear()

## get_process_delta_time() is already scaled by Engine.time_scale, so it is summed raw —
## multiplying by the scale again is the classic mistake here.
func _run_for(sec: float) -> void:
	Engine.time_scale = TIME_SCALE
	var t: float = 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()
	Engine.time_scale = 1.0
