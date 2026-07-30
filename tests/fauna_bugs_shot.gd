extends Node
## The three s23 fixes that are VISUAL, photographed off one world build.
##
##   1. PYRAMID SNAIL — a frame taken from AHEAD of the animal (on its own heading) must show
##      the head, eye stalks and oral tentacles; the frame from behind must show the back of
##      the shell. That is the whole facing test, and it cannot be faked by a still: the
##      camera is placed from the animal's LIVE heading, so if the mesh were reversed the
##      "ahead" frame would photograph its tail. Same frames answer "is it still too dark".
##   2. HARBOR SEAL — hauled out on the pontoon shelf, close, from the side, so the flippers
##      can be seen resting ON the concrete rather than in it or over it.
##   3. TROPICAL REEF FISH — the player flown in on a damsel station from 8 m to 1.4 m, a
##      frame every 1.1 m, so the flee can be watched rather than asserted.
##
## MUST RUN WINDOWED AND IN THE FOREGROUND (docs/AGENT_TRAPS.md: --headless never draws, and
## a backgrounded windowed Godot freezes its renderer counters).
##   godot --path . res://tests/FaunaBugsShot.tscn -- <out_dir>

var main: Node3D
var _dir: String = "/tmp/fauna_s23"
var _pause: CanvasLayer = null

const EYE_UP: float = 1.6

func _ready() -> void:
	# A harness that un-pauses in _process must ALSO be PROCESS_MODE_ALWAYS, or a focus-out
	# pause stops it processing and it can never un-pause itself again.
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
	# force_phase RESETS the phase clock and DAY f=0 is a low red sun, so write the fraction
	# of DAY we actually want once (docs/AGENT_TRAPS.md, s22).
	GameClock.set("_phase_elapsed_sec",
		float(GameClock.phase_durations_minutes[GameClock.Phase.DAY]) * 60.0 * 0.45)
	print("[s23] world up, output -> ", _dir)
	await _snails()
	if not "--snails" in args:
		await _seal()
		await _fish()
	print("[s23] done")
	get_tree().quit()

# ---------------------------------------------------------------------------- snails
func _snails() -> void:
	var shot: int = 0
	for node in get_tree().get_nodes_in_group("snail_pyramid"):
		var s: Node3D = node
		if s.global_position.y < 10.0:
			continue          # the caisson climbers are a different (dark) picture
		shot += 1
		# The animal's own forward, off the live node: the crawler orients the host so that
		# -Z runs down the heading.
		var fwd: Vector3 = s.global_transform.basis * Vector3.FORWARD
		var flat := Vector3(fwd.x, 0.0, fwd.z)
		if flat.length() < 0.01:
			flat = Vector3.FORWARD
		flat = flat.normalized()
		var c: Vector3 = s.global_position + Vector3(0.0, 0.30, 0.0)
		await _look(c + flat * 1.15 + Vector3(0.0, 0.22, 0.0), c,
			"snail%d_ahead_MUST_SHOW_HEAD" % shot)
		await _look(c - flat * 1.15 + Vector3(0.0, 0.26, 0.0), c,
			"snail%d_behind_MUST_SHOW_SHELL" % shot)
		var side: Vector3 = flat.cross(Vector3.UP).normalized()
		await _look(c + side * 1.25 + Vector3(0.0, 0.20, 0.0), c, "snail%d_side" % shot)
		if shot >= 2:
			break
	# THE CAISSON CLIMBERS. Six of the nine live on concrete 11-19 m down, where there is no
	# direct light at all — the band where s21 found a lit surface renders near-black whatever
	# its albedo. If the metallicRoughness fix is enough on its own it has to be enough here.
	var deep: int = 0
	for node in get_tree().get_nodes_in_group("snail_pyramid"):
		var s: Node3D = node
		if s.global_position.y > -3.0:
			continue
		deep += 1
		var legs: Array = load("res://scripts/world/leg_reef.gd").LEGS
		var pos: Vector3 = s.global_position
		var leg: Vector2 = legs[0]
		for l in legs:
			if Vector2(pos.x - l.x, pos.z - l.y).length() \
					< Vector2(pos.x - leg.x, pos.z - leg.y).length():
				leg = l
		var d := Vector2(pos.x - leg.x, pos.z - leg.y)
		var n := Vector3(signf(d.x), 0.0, 0.0) if absf(d.x) > absf(d.y) \
			else Vector3(0.0, 0.0, signf(d.y))
		await _look(pos + n * 1.35 + Vector3(0.0, 0.20, 0.0), pos, "snail_deep%d_y%.0f"
			% [deep, pos.y])
		if deep >= 3:
			break

# ------------------------------------------------------------------------------ seal
func _seal() -> void:
	var seal: Node3D = null
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		if n.get("_haul") != null and n.get("_haul_floor") != null:
			seal = n
			break
	if seal == null:
		print("[s23] no seal found")
		return
	var haul: Vector3 = seal.get("_haul")
	seal.set("_hauled", true)
	seal.set("_haul_timer", 1.0e9)
	seal.global_position = Vector3(haul.x, haul.y, haul.z)
	for i in range(180):
		seal.set("_hauled", true)
		seal.set("_haul_timer", 1.0e9)
		await get_tree().process_frame
	var c: Vector3 = seal.global_position
	await _look(c + Vector3(3.4, 0.9, 0.4), c, "seal_hauled_side")
	await _look(c + Vector3(0.6, 0.55, 3.4), c, "seal_hauled_quarter")
	await _look(c + Vector3(2.2, 0.25, 1.6), c, "seal_hauled_low")
	# ...and in the water, riding the swell.
	seal.set("_hauled", false)
	seal.set("_haul_timer", 1.0e9)
	for i in range(120):
		seal.set("_hauled", false)
		seal.set("_haul_timer", 1.0e9)
		await get_tree().process_frame
	for k in range(4):
		for i in range(45):
			seal.set("_hauled", false)
			seal.set("_haul_timer", 1.0e9)
			await get_tree().process_frame
		var sc: Vector3 = seal.global_position
		var away: Vector3 = (sc - Vector3(0.0, 0.0, -34.0))
		away.y = 0.0
		if away.length() < 0.5:
			away = Vector3(0.0, 0.0, -1.0)
		await _look(sc + away.normalized() * 6.5 + Vector3(0.0, 1.1, 0.0), sc,
			"seal_swim_%d" % k)

# ------------------------------------------------------------------------------ fish
func _fish() -> void:
	var rf: Node = null
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var s: Script = n.get_script()
		if s != null and String(s.resource_path).ends_with("reef_fish.gd"):
			rf = n
			break
	if rf == null:
		print("[s23] reef_fish node not found")
		return
	var stations: Array = rf.get("_stations")
	for want in ["trop_damsel", "trop_anthias"]:
		var pick: Dictionary = {}
		for st in stations:
			if String(st["sp"]["slug"]) == want:
				pick = st
				break
		if pick.is_empty():
			continue
		var centre: Vector3 = pick["centre"]
		var outv: Vector3 = pick["out"]
		for k in range(6):
			var d: float = lerpf(8.0, 1.4, float(k) / 5.0)
			# Hold the pose every frame of the settle: the controller keeps integrating
			# through an await and three s21 frames were taken up to 3 m off their mark.
			for i in range(50):
				_place(centre + outv * d, centre)
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			var eye: Vector3 = main.player.global_position + Vector3(0.0, EYE_UP, 0.0)
			var path: String = "%s/%s_%.1fm.png" % [_dir, want, d]
			print("[s23] saved %s  asked %.2f m, actually %.2f m  alarm %.3f  err=%s"
				% [path, d, eye.distance_to(centre), float(pick["alarm"]),
					img.save_png(path)])

# --------------------------------------------------------------------------- plumbing
func _place(eye: Vector3, target: Vector3) -> void:
	var p: Node3D = main.player
	p.global_position = eye - Vector3(0.0, EYE_UP, 0.0)
	var d: Vector3 = target - eye
	var flat: float = Vector2(d.x, d.z).length()
	p.rotation.y = atan2(-d.x, -d.z)
	(p.get_node("Head") as Node3D).rotation.x = atan2(d.y, flat)
	p.set("velocity", Vector3.ZERO)
	p.set("input_locked", true)

func _look(eye: Vector3, target: Vector3, name_: String) -> void:
	for i in range(45):
		_place(eye, target)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var got: Vector3 = main.player.global_position + Vector3(0.0, EYE_UP, 0.0)
	var path: String = "%s/%s.png" % [_dir, name_]
	print("[s23] saved %s  asked eye %s got %s  d=%.2f m  err=%s"
		% [path, str(eye.snappedf(0.01)), str(got.snappedf(0.01)),
			got.distance_to(target), img.save_png(path)])

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
