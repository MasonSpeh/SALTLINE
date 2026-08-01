extends Node
## s24 — LOOK AT THE SEAL. The waterline numbers are in tests/SealFloatProbe.tscn; this is
## the other half of the rule ("verify by looking"), and it is the seal ALONE so the launch
## is short: the repeat report is "it still floats", which is a picture, not a metric.
##
##   seal_swim_N   the patrolling animal, photographed from the water beside it, from just
##                 above the surface — the eye height a player at the wet-deck rail has.
##                 What must be visible: a strip of wet back and the head, and NOTHING
##                 underneath the animal but sea.
##   seal_haul_N   the resident on the pontoon shelf, flippers ON the concrete.
##   seal_climb    mid-haul-out, taken while it is still over open water — this is the frame
##                 that used to show a seal gliding in at shelf height.
##
## MUST RUN WINDOWED AND IN THE FOREGROUND (docs/AGENT_TRAPS.md: --headless never draws, and
## a backgrounded windowed Godot freezes its renderer counters).
##   godot --path . res://tests/SealShot.tscn -- <out_dir>

var main: Node3D
var _dir: String = "/tmp/seal_s24"
var _pause: CanvasLayer = null

const EYE_UP: float = 1.6

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_dir)
	main = load("res://scenes/Main.tscn").instantiate()
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
	GameClock.force_phase(GameClock.Phase.DAY)
	GameClock.set("_phase_elapsed_sec",
		float(GameClock.phase_durations_minutes[GameClock.Phase.DAY]) * 60.0 * 0.45)
	print("[s24] world up, output -> ", _dir)
	await _seal()
	print("[s24] done")
	get_tree().quit()

func _seal() -> void:
	AiBudget.enabled = false
	var seals: Array = []
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		if n.get("_haul") != null and n.get("_haul_floor") != null:
			seals.append(n)
	if seals.is_empty():
		print("[s24] no seal found")
		return
	var seal: Node3D = seals[-1]        # the patroller, not the resident
	# ------------------------------------------------------------------ in the water
	#
	# A WATERLINE CAMERA, not a deck camera. The first pass of this harness shot the animal
	# from 0.9 m above the sea and photographed an empty ocean four times over — which is the
	# right ANSWER (the surface is opaque and a submerged seal is behind it) and a useless
	# PICTURE. The eye sits ON the waterline instead, so the surface cuts the frame in half
	# and how much of the animal is above the cut can be read straight off the image.
	#
	# Eight frames across one breath cycle (sin(_t * 0.6), ~10.5 s) so the whole arc is on
	# record: the cruise, the roll up through the surface, and the way back down.
	for i in range(120):
		AiBudget.enabled = false
		seal.set("_hauled", false)
		seal.set("_haul_timer", 1.0e9)
		await get_tree().process_frame
	for k in range(5):
		for i in range(80):                 # ~1.33 s at 60 fps
			AiBudget.enabled = false
			seal.set("_hauled", false)
			seal.set("_haul_timer", 1.0e9)
			await get_tree().process_frame
		var sc: Vector3 = seal.global_position
		var away: Vector3 = sc - Vector3(0.0, 0.0, -34.0)
		away.y = 0.0
		if away.length() < 0.5:
			away = Vector3(0.0, 0.0, -1.0)
		var sea: float = Gyre.wave_height(Vector2(sc.x, sc.z), Gyre.water_time())
		print("[s24] swim_%d node y %.3f, sea %.3f, node-sea %+.3f"
			% [k, sc.y, sea, sc.y - sea])
		# TWO ANGLES, because the complaint and the proof want different cameras.
		#   _under  eye 1.3 m DOWN and 5 m off, looking slightly up: the animal is silhouetted
		#           against the underside of the surface, so where its back sits relative to
		#           the waterline is legible instead of inferred. An eye ON the waterline was
		#           tried first and is useless — it flickers in and out of the underwater
		#           overlay and any crest between camera and animal hides the shot.
		#   _deck   eye 6 m up and 9 m out, i.e. the wet-deck south rail: THE OWNER'S OWN VIEW,
		#           and the one that has to stop showing a seal sitting on the sea.
		await _follow(seal, away.normalized() * 5.0 + Vector3(0, -1.3, 0), "seal_under_%d" % k)
		await _follow(seal, away.normalized() * 9.0 + Vector3(0, 6.0, 0), "seal_deck_%d" % k)
	# -------------------------------------------------------------------- the climb
	var far: Vector3 = seal.global_position
	seal.set("_hauled", true)
	seal.set("_haul_timer", 1.0e9)
	for i in range(50):
		seal.set("_hauled", true)
		seal.set("_haul_timer", 1.0e9)
		await get_tree().process_frame
	var mid: Vector3 = seal.global_position
	print("[s24] climb: from %s to %s" % [str(far.snappedf(0.01)), str(mid.snappedf(0.01))])
	await _look(mid + Vector3(6.0, 1.0, 1.0), mid, "seal_climb")
	# ------------------------------------------------------------------ on the shelf
	for i in range(240):
		seal.set("_hauled", true)
		seal.set("_haul_timer", 1.0e9)
		await get_tree().process_frame
	var c: Vector3 = seal.global_position
	await _look(c + Vector3(3.4, 0.9, 0.4), c, "seal_haul_side")
	await _look(c + Vector3(2.2, 0.25, 1.6), c, "seal_haul_low")

## Track a MOVING animal. A fixed eye/target pair settles for 45 frames, and the seal covers
## about 1.4 m of its patrol in that time — enough to walk clean out of the middle of the
## frame. Re-solved every frame off the live node instead, with the eye pinned to the local
## WAVE HEIGHT so the surface stays across the middle of the picture.
func _follow(node: Node3D, offset: Vector3, name_: String) -> void:
	for i in range(30):
		AiBudget.enabled = false
		node.set("_hauled", false)
		node.set("_haul_timer", 1.0e9)
		var c: Vector3 = node.global_position
		# The offset's HEIGHT is relative to the local sea, not to y0 — a camera pinned to an
		# absolute height drifts a metre in and out of the water as the swell runs under it.
		var eye: Vector3 = c + Vector3(offset.x, 0.0, offset.z)
		eye.y = Gyre.wave_height(Vector2(eye.x, eye.z), Gyre.water_time()) + offset.y
		_place(eye, c)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s.png" % [_dir, name_]
	print("[s24] saved %s  err=%s" % [path, img.save_png(path)])

func _look(eye: Vector3, target: Vector3, name_: String) -> void:
	for i in range(45):
		_place(eye, target)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s.png" % [_dir, name_]
	print("[s24] saved %s  eye %s  target %s  err=%s"
		% [path, str(eye.snappedf(0.01)), str(target.snappedf(0.01)), img.save_png(path)])

func _place(eye: Vector3, target: Vector3) -> void:
	var p: Node3D = main.player
	p.global_position = eye - Vector3(0.0, EYE_UP, 0.0)
	var d: Vector3 = target - eye
	var flat: float = Vector2(d.x, d.z).length()
	p.rotation.y = atan2(-d.x, -d.z)
	(p.get_node("Head") as Node3D).rotation.x = atan2(d.y, flat)
	p.set("velocity", Vector3.ZERO)
	p.set("input_locked", true)

func _process(_d: float) -> void:
	get_tree().paused = false
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
