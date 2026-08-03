extends Node3D
## THE s35 CLOSE-OUT PASS — every visual claim this session makes, on ONE windowed build.
##
## Same contract as s34_shot.gd, which this is grown from: the owner judges by screenshot,
## so nothing is reported until the frame has been rendered and READ BACK; and the whole
## session's verification is ONE world build, because relaunching Godot repeatedly lags the
## owner's machine.
##
## What is new here beyond s34's list is that several of this session's claims are about
## something being ABSENT (floating text, connector tubes, a blocked doorway), and an
## absence photographs identically to a camera pointed at the wrong place. So every such
## shot is aimed from a position derived from the prop's own authored constant, and the log
## line prints the distance to the subject — a frame of empty deck with "subject 14.2 m"
## next to it is a miss, not a pass.
##
## MUST RUN WINDOWED AND IN THE FOREGROUND (--headless never draws; a backgrounded windowed
## Godot freezes its renderer counters at their first-frame values).
##     godot --path . res://tests/S35Shot.tscn -- /tmp/s35
##     godot --path . res://tests/S35Shot.tscn -- /tmp/s35 --only=cat

const SHOT_PX := Vector2i(1280, 720)

## [name, eye, target, what it is for]
##
## Coordinates are taken from the authored constants, not typed by eye:
##   TIDE_STAFF      rig_builder.gd:3886   (6.4, 0.0, -16.35)
##   KING_DENS       bloom_fauna.gd:299    (27, -8, -9.5) and (-27, -8, -12.5)
##   store_room      RIG_ATLAS             x[10,16]  z[-22,-16]  y[1.8,5.4]
##   pump_ready_room RIG_ATLAS             x[10,18]  z[-14,-6]   y[1.8,5.4]
##   stair_tower     RIG_ATLAS             x[21,31]  z[-6,2]     y[2,21.2]
##   caisson faces   AGENT_TRAPS           |x| = 25.00 unbroken, y 1.0 .. -23.5
const SHOTS := [
	["tide_staff", Vector3(8.6, 2.4, -16.35), Vector3(6.4, 1.2, -16.35),
		"the tide staff — the six floating Label3D glyphs must be GONE, bands remain"],
	["tide_staff_far", Vector3(11.0, 3.2, -13.0), Vector3(6.4, 0.8, -16.35),
		"the staff from the walkway the owner reads it from"],
	["store_door", Vector3(13.0, 3.0, -13.6), Vector3(13.0, 2.6, -18.0),
		"the store-room doorway — the tubes stay, and a crouch gap under them"],
	["pump_door", Vector3(14.0, 3.0, -4.2), Vector3(14.0, 2.6, -8.5),
		"the pump-room doorway — this is the blockage that had to go"],
	["pump_room", Vector3(11.0, 3.2, -10.0), Vector3(17.5, 2.5, -10.0),
		"inside the pump room, along its length — is there a lane through it"],
	["king_crab", Vector3(30.5, -7.2, -9.5), Vector3(25.6, -8.0, -9.5),
		"the big crab on the SE caisson face — sideways, and no tubes under it"],
	["king_crab_wide", Vector3(33.0, -5.0, -4.0), Vector3(25.5, -8.0, -9.5),
		"...and from further off, so 'clinging to the wall' is legible as a relationship"],
	# THE WALL PAIR. Two eyes 3 m apart aimed at the SAME point on the same caisson face.
	# A world-mapped texture keeps its pattern pinned to the concrete between these two
	# frames; a texture that swims with the viewer does not. One frame cannot show this,
	# which is why the previous "it still moves" report had nothing to check it against.
	["wall_a", Vector3(31.0, -5.0, -12.0), Vector3(25.0, -6.0, -12.0),
		"caisson face from the east — reference frame for the texture pair"],
	["wall_b", Vector3(31.0, -5.0, -9.0), Vector3(25.0, -6.0, -12.0),
		"same wall point, camera moved 3 m — the texture must not have moved with it"],
	["stairs_low", Vector3(26.0, 4.2, 3.4), Vector3(26.0, 7.0, -1.0),
		"the stair tower flight from its foot — treads and the landing they meet"],
	["stairs_top", Vector3(26.0, 19.6, 2.6), Vector3(26.0, 17.6, -1.5),
		"the head of the flight — the junction where the platform glitch lives"],
	["reef_top", Vector3(34.0, -9.0, -12.0), Vector3(22.0, -12.0, -12.0),
		"the coral band top from 12 m"],
	["reef_mid", Vector3(37.0, -15.0, -12.0), Vector3(22.0, -16.0, -12.0),
		"the dense colonies from 15 m — the frame the water complaint was about"],
	["reef_deep", Vector3(31.0, -28.0, -12.0), Vector3(22.0, -30.0, -12.0),
		"the deep band — coral against the abyss ramp"],
	["plants", Vector3(30.0, -15.0, -14.5), Vector3(25.0, -17.0, -11.5),
		"plants rooted into the concrete, close — do they exist and do they sway"],
	["kelp", Vector3(30.0, -20.0, -12.0), Vector3(23.0, -22.0, -12.0),
		"the kelp tiers down the leg"],
	["surface_fish", Vector3(6.0, -2.2, -20.0), Vector3(-6.0, -3.0, -20.0),
		"the shallow band — the owner wants visual density HERE"],
	["abyss_down", Vector3(8.0, -6.0, -4.0), Vector3(8.0, -40.0, -4.0),
		"straight down — the -92 floor must still be invisible"],
]

var _dir: String = "/tmp/s35"
var _only: String = ""
var _main: Node3D
var _fail: int = 0
var _done: bool = false

func _process(_d: float) -> void:
	# Force-unpause AND hide the panel every frame: another window stealing focus pauses
	# the world, a paused world still renders, and the PAUSED dialog lives on its own
	# CanvasLayer that un-pausing does not take down.
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
	# A parse error anywhere hands back a bare node with its script dropped, and every
	# assertion downstream then passes vacuously over an empty tree.
	if _main == null or _main.get_script() == null:
		print("[s35] Main.tscn came back WITHOUT its script — aborting")
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
	# The player STAYS in the `player` group. underwater_fx finds it through that group and
	# returns immediately without one, so dropping it switches off the ENTIRE depth grade
	# and main.gd's fallback curve becomes the only writer — the trap that cost s34 an hour
	# of photographing the wrong fog.

	for shot in SHOTS:
		if _only != "" and not String(shot[0]).begins_with(_only):
			continue
		await _shoot(shot, player, cam)
	if _only == "" or _only == "cat":
		await _cat_states(player, cam)
	if _only == "" or _only == "rod":
		await _rod(player, cam, hud)
	print("[s35] done -> %s   MISMATCHES: %d" % [_dir, _fail])
	_done = true
	get_tree().quit(1 if _fail > 0 else 0)

## Hold the weather and the sun still. A squall rolling in mid-pass changes the fog density
## and the light, and two frames taken either side of it are not comparable — which is how
## an s34 fog sweep produced a set of candidates that could not be ranked.
func _pin() -> void:
	var st: Node = _main.get("storm")
	if st != null:
		st.set_process(false)
		st.set("_intensity", 0.0)
		st.set("_phase", 0)
	# force_phase() RESETS the phase clock and DAY f=0 is a low red sun, so it is called
	# once and the position is then written directly.
	GameClock._phase_elapsed_sec = \
		float(GameClock.phase_durations_minutes[GameClock.Phase.DAY]) * 60.0 * 0.45

func _shoot(shot: Array, player: Node3D, cam: Camera3D, tag: String = "") -> void:
	var eye: Vector3 = shot[1]
	var target: Vector3 = shot[2]
	var aim: Vector3 = (target - eye).normalized()
	# look_at degenerates when the aim is parallel to up — the abyss shot points straight
	# down and would otherwise photograph a random yaw.
	var up: Vector3 = Vector3.UP if absf(aim.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	# Re-assert the pose EVERY frame of the settle: the controller keeps integrating across
	# an await, and s21 lost three frames to cameras up to 3 m from where they were aimed.
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
	var nm: String = String(shot[0]) + tag
	img.save_png("%s/%s.png" % [_dir, nm])
	# Print where the camera ACTUALLY ended up and how far the subject is: a frame of empty
	# water is indistinguishable from a correct frame of a deleted prop without this.
	print("  %-16s got %s (%.2f m off aim), subject %.1f m — %s"
		% [nm, str(got.round()), eye.distance_to(got), got.distance_to(target),
			String(shot[3])])

## THE CAT, IN EACH STATE, driven the way the game drives it — the player is put where each
## state needs them rather than the state being poked in directly. A photograph of a state
## nothing produced is not evidence.
func _cat_states(player: Node3D, cam: Camera3D) -> void:
	var cat: Node3D = get_tree().get_first_node_in_group("ship_cat")
	if cat == null:
		print("  [cat] no cat found")
		_fail += 1
		return
	print("  [cat] found at %s" % str(cat.global_position.round()))
	await _cat_frame(cat, player, cam, "cat_groom", func() -> void:
		player.global_position = cat.global_position + Vector3(3.0, 0.0, 0.0))
	for c in cat.get_children():
		if c is Interactable:
			(c as Interactable).emit_signal("interacted", "SAY HELLO")
	await _cat_frame(cat, player, cam, "cat_follow", func() -> void:
		player.global_position = cat.global_position + Vector3(5.0, 0.0, 1.0))
	# RUN must be caught WHILE running — a full settle photographs a cat that already
	# arrived and sat down.
	await _cat_frame(cat, player, cam, "cat_run", func() -> void:
		player.global_position = cat.global_position + Vector3(23.0, 0.0, 0.0), 20)
	await _cat_frame(cat, player, cam, "cat_sit", func() -> void:
		player.global_position = cat.global_position + Vector3(1.6, 0.0, 0.0))
	await _cat_frame(cat, player, cam, "cat_sleep", func() -> void:
		player.set("_lying", true)
		player.set("_lying_sleeping", true))
	player.set("_lying", false)
	player.set("_lying_sleeping", false)

func _cat_frame(cat: Node3D, player: Node3D, cam: Camera3D, nm: String, setup: Callable,
		settle: int = 240) -> void:
	setup.call()
	for i in range(settle):
		_pin()
		await get_tree().process_frame
	var at: Vector3 = cat.global_position
	# Waist height, a little back and to the side: how you actually see a cat by your feet.
	# Taken along the cat's OWN forward so a walking cat is photographed from the quarter
	# rather than from wherever the world axes happen to put the lens — which also makes
	# "is it walking head-first" legible in the frame instead of only in the probe.
	var fwd: Vector3 = -cat.global_transform.basis.z
	var side: Vector3 = cat.global_transform.basis.x
	var eye: Vector3 = at + fwd * 1.25 + side * 0.95 + Vector3(0, 0.85, 0)
	for i in range(20):
		_pin()
		cam.global_position = eye
		cam.look_at(at + Vector3(0, 0.16, 0), Vector3.UP)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.resize(SHOT_PX.x, SHOT_PX.y)
	img.save_png("%s/%s.png" % [_dir, nm])
	# THE POSE MUST MATCH THE STATE — the assertion s34's first close-out lacked, which is
	# how a cat photographed as SIT while still wearing the walk mesh got through.
	var want: String = String(cat.get("STATE_POSE").get(int(cat.get("_state")), "?")) \
		if cat.get("STATE_POSE") != null else String(cat.get("_pose"))
	var ok: bool = String(cat.get("_pose")) == want
	if not ok:
		_fail += 1
	# ...and the RIG has to be driving, or this is the s34 cat with more machinery. A pose
	# with no entry in _rigs is a static mesh however good the state machine looks.
	var rigs: Dictionary = cat.get("_rigs")
	var rigged: bool = rigs != null and rigs.has(String(cat.get("_pose")))
	if not rigged:
		_fail += 1
	print("  %-16s state=%s pose=%s (want %s)%s rigged=%s at %s"
		% [nm, str(cat.get("_state")), str(cat.get("_pose")), want,
			"" if ok else "   <- MISMATCH", str(rigged), str(at.round())])

## THE FISHING ROD, IN HAND. The owner reports the visual gone; this is a first-person
## viewmodel, so the frame has to be taken from the player's own eye with the rod SELECTED
## — a third-person shot of the rig proves nothing about it either way.
func _rod(player: Node3D, cam: Camera3D, hud: Node) -> void:
	var slot: int = -1
	PlayerState.add_item("fishing_rod")
	for i in range(PlayerState.hotbar.size()):
		if String(PlayerState.hotbar[i]).begins_with("fishing_rod"):
			slot = i
			break
	if slot < 0:
		print("  [rod] fishing_rod would not go into the hotbar — cannot photograph it")
		_fail += 1
		return
	PlayerState.selected_hotbar = slot
	# Stand on the wet deck looking out over the water, which is where you would fish from.
	for i in range(90):
		_pin()
		player.global_position = Vector3(8.0, 2.05, -20.0)
		cam.global_position = Vector3(8.0, 3.65, -20.0)
		cam.look_at(Vector3(2.0, 2.6, -26.0), Vector3.UP)
		await get_tree().process_frame
	if hud:
		hud.set("visible", true)      # the hotbar is part of what "the rod is equipped" means
	for i in range(10):
		_pin()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.resize(SHOT_PX.x, SHOT_PX.y)
	img.save_png("%s/rod_in_hand.png" % _dir)
	if hud:
		hud.set("visible", false)
	print("  %-16s slot=%d item=%s — the rod must be VISIBLE in the lower right"
		% ["rod_in_hand", slot, str(PlayerState.hotbar[slot])])
