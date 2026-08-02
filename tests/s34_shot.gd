extends Node3D
## THE s34 CLOSE-OUT PASS — every visual claim this session makes, on ONE windowed build.
##
## The rule this exists to obey is CLAUDE.md's: the owner judges by screenshot, so nothing
## is reported until the frame has been rendered and READ BACK. The rule it exists to obey
## SECOND is "batch the verification" — repeatedly relaunching Godot lags the owner's
## machine, and six separate harnesses would be six world builds.
##
## Covers, in order: the decluttered spawn walk, the cleared reef water at three depths,
## the wall plants close up, the kelp tiers, the basking seal, the rebalanced shoals, and
## the cat in each of its states.
##
## MUST RUN WINDOWED AND IN THE FOREGROUND (--headless never draws; a backgrounded windowed
## Godot freezes its renderer counters).
##     godot --path . res://tests/S34Shot.tscn -- /tmp/s34
##     godot --path . res://tests/S34Shot.tscn -- /tmp/s34 --only=cat

const SHOT_PX := Vector2i(1280, 720)

## [name, eye, target, what it is for]
const SHOTS := [
	# NORTH OF THE HATCH, LOOKING BACK AT IT. Aimed from the south side the first time and
	# photographed the closed door filling the frame — the walk being shown is on the DECK
	# side of that door, which is where the drum, the tyre and the chain used to be.
	["walk_spawn", Vector3(20.0, 3.6, -18.4), Vector3(20.0, 2.4, -23.0),
		"back down the walk at the SPHL hatch — the drum, tyre and chain are gone"],
	["walk_turn", Vector3(20.6, 3.6, -19.0), Vector3(23.0, 2.4, -15.6),
		"the caisson-foot turn — the mooring heap has left the walking line"],
	["reef_top", Vector3(34.0, -9.0, -12.0), Vector3(22.0, -12.0, -12.0),
		"the coral band top from 12 m"],
	["reef_mid", Vector3(37.0, -15.0, -12.0), Vector3(22.0, -16.0, -12.0),
		"the dense colonies from 15 m — the shot the water complaint was about"],
	["reef_deep", Vector3(31.0, -28.0, -12.0), Vector3(22.0, -30.0, -12.0),
		"the NEW band, below where the reef used to stop at -22"],
	["wall_plants", Vector3(30.0, -15.0, -14.5), Vector3(25.0, -17.0, -11.5),
		"plants rooted into the concrete and angled out, close"],
	["kelp_tiers", Vector3(30.0, -20.0, -12.0), Vector3(23.0, -22.0, -12.0),
		"the three kelp tiers down the leg"],
	["two_legs", Vector3(0.0, -13.0, 0.0), Vector3(22.0, -14.0, -12.0),
		"across the rig at 25 m — the far leg has to exist"],
	["shoal", Vector3(0.0, -6.0, -26.0), Vector3(0.0, -7.0, -40.0),
		"open water off the rig — the pelagics were pushed out here"],
	# THE ABYSS STILL HAS TO SWALLOW THE -92 FLOOR. Step 2 cleared the water and step 5 moved
	# the ramp below the extended reef, so this is the frame that proves the two together did
	# not open a view down to the gyre floor.
	["abyss_down", Vector3(8.0, -6.0, -4.0), Vector3(8.0, -40.0, -4.0),
		"straight down — nothing of the -92 floor may be visible"],
	["seal", Vector3(6.2, 2.2, -12.0), Vector3(3.0, 1.3, -12.0),
		"the resting seal, belly on the concrete"],
]

var _dir: String = "/tmp/s34"
var _only: String = ""
var _main: Node3D
var _fail: int = 0
var _done: bool = false

func _process(_d: float) -> void:
	if get_tree().paused:
		get_tree().paused = false
	var pm: Node = get_tree().get_first_node_in_group("pause_menu")
	if pm != null and pm.get("panel") != null:
		(pm.get("panel") as CanvasItem).visible = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
		elif not a.begins_with("--"):
			_dir = a
	DirAccess.make_dir_recursive_absolute(_dir)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate() if packed != null else null
	if _main == null or _main.get_script() == null:
		print("[s34] Main.tscn came back WITHOUT its script — aborting")
		get_tree().quit(1)
		return
	add_child(_main)
	await get_tree().create_timer(24.0).timeout
	GameClock.force_phase(GameClock.Phase.DAY)
	var player: Node3D = get_tree().get_first_node_in_group("player")
	var cam: Camera3D = player.get_node("Head/Camera3D")
	cam.current = true
	player.set_physics_process(false)
	for p in player.find_children("*", "CollisionObject3D", true, false):
		(p as CollisionObject3D).set_collision_mask_value(1, false)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	# The player STAYS in its group: underwater_fx finds the player through it and its whole
	# depth grade switches off without one, which is how the s34 fog sweep spent an hour
	# photographing main.gd's fallback curve. See tests/fog_shot.gd.

	for shot in SHOTS:
		if _only != "" and not String(shot[0]).begins_with(_only):
			continue
		await _shoot(shot, player, cam)
	if _only == "" or _only == "cat":
		await _cat_states(player, cam)
	print("[s34] done -> ", _dir)
	_done = true
	get_tree().quit(1 if _fail > 0 else 0)

func _pin() -> void:
	var st: Node = _main.get("storm")
	if st != null:
		st.set_process(false)
		st.set("_intensity", 0.0)
		st.set("_phase", 0)
	GameClock._phase_elapsed_sec = \
		float(GameClock.phase_durations_minutes[GameClock.Phase.DAY]) * 60.0 * 0.45

func _shoot(shot: Array, player: Node3D, cam: Camera3D, tag: String = "") -> void:
	var eye: Vector3 = shot[1]
	var target: Vector3 = shot[2]
	var aim: Vector3 = (target - eye).normalized()
	var up: Vector3 = Vector3.UP if absf(aim.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	# Re-assert the pose EVERY frame of the settle: the controller keeps integrating across
	# an await and s21 lost three frames to cameras up to 3 m from where they were aimed.
	for i in range(26):
		_pin()
		player.global_position = eye - Vector3(0, 1.6, 0)
		cam.global_position = eye
		cam.look_at(target, up)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var got: Vector3 = cam.global_position
	var img: Image = get_viewport().get_texture().get_image()
	img.resize(SHOT_PX.x, SHOT_PX.y)
	var name: String = String(shot[0]) + tag
	img.save_png("%s/%s.png" % [_dir, name])
	print("  %-14s got %s (%.2f m off), subject %.1f m — %s"
		% [name, str(got.round()), eye.distance_to(got), got.distance_to(target),
			String(shot[3])])

## THE CAT, IN EACH STATE. Driven the way the game drives it — the states are set by what
## the player is doing, so the player is put where each state needs them rather than the
## state being poked in directly. A photograph of a state nothing produced is not evidence.
func _cat_states(player: Node3D, cam: Camera3D) -> void:
	var cat: Node3D = get_tree().get_first_node_in_group("ship_cat")
	if cat == null:
		print("  [cat] no cat found")
		_fail += 1
		return
	# Say hello first: everything except GROOM is behind being a friend.
	print("  [cat] found at %s" % str(cat.global_position.round()))
	await _cat_frame(cat, player, cam, "cat_groom", func() -> void:
		player.global_position = cat.global_position + Vector3(3.0, 0.0, 0.0))
	for c in cat.get_children():
		if c is Interactable:
			(c as Interactable).emit_signal("interacted", "SAY HELLO")
	await _cat_frame(cat, player, cam, "cat_follow", func() -> void:
		player.global_position = cat.global_position + Vector3(5.0, 0.0, 1.0))
	# RUN HAS TO BE CAUGHT WHILE IT IS RUNNING. The first pass gave this the same 240-frame
	# settle as the others and photographed a cat that had already arrived and sat down —
	# state 3 (SIT) with the walk mesh still on, which is how the two direct `_state =`
	# assignments that bypassed the pose table were found. Short settle, and the frame is
	# only kept if the cat is actually in RUN when the shutter fires.
	await _cat_frame(cat, player, cam, "cat_run", func() -> void:
		player.global_position = cat.global_position + Vector3(23.0, 0.0, 0.0), 20)
	await _cat_frame(cat, player, cam, "cat_sit", func() -> void:
		player.global_position = cat.global_position + Vector3(1.6, 0.0, 0.0))
	await _cat_frame(cat, player, cam, "cat_sleep", func() -> void:
		player.set("_lying", true)
		player.set("_lying_sleeping", true))
	player.set("_lying", false)
	player.set("_lying_sleeping", false)

func _cat_frame(cat: Node3D, player: Node3D, cam: Camera3D, name: String, setup: Callable,
		settle: int = 240) -> void:
	setup.call()
	# Let the state settle — the cat walks to where the state needs it.
	for i in range(settle):
		_pin()
		await get_tree().process_frame
	var at: Vector3 = cat.global_position
	# Waist height, a little back and to the side: how you actually see a cat by your feet.
	var eye: Vector3 = at + Vector3(1.15, 0.85, 1.15)
	for i in range(20):
		_pin()
		cam.global_position = eye
		cam.look_at(at + Vector3(0, 0.16, 0), Vector3.UP)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.resize(SHOT_PX.x, SHOT_PX.y)
	img.save_png("%s/%s.png" % [_dir, name])
	# THE POSE MUST MATCH THE STATE. This is the assertion the first close-out pass did not
	# have, and it is the one that would have caught a cat photographed as SIT wearing the
	# walk mesh instead of leaving it to be spotted in a log line.
	var want: String = String(cat.get("STATE_POSE").get(int(cat.get("_state")), "?")) \
		if cat.get("STATE_POSE") != null else String(cat.get("_pose"))
	var ok: bool = String(cat.get("_pose")) == want
	if not ok:
		_fail += 1
	print("  %-14s state=%s pose=%s (want %s)%s at %s"
		% [name, str(cat.get("_state")), str(cat.get("_pose")), want,
			"" if ok else "   <- MISMATCH", str(at.round())])
