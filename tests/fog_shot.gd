extends Node3D
## THE FOG SWEEP — how clear should the reef water be?
##
## Owner, s34: the water reads hazier than it used to and "this is a coral reef for
## christ's sake". The shipped grade put 0.186/m of fog at the top of the coral band, i.e.
## 6% contrast on anything 15 m away, so there was nothing to look AT even where the coral
## is densest. underwater_fx now exposes the four numbers that decide this as writable
## vars; this harness re-exposes the SAME frame at each candidate set.
##
## WHY ONE LAUNCH. Picking a look across separate Godot runs compares thermal states, not
## curves — this machine's frame times and therefore its sun/phase positions drift enough
## between launches to make cross-run judgement meaningless. Same reason ReefShot sweeps
## --glow and SpearShot sweeps the fish rim on one build (docs/AGENT_TRAPS.md). The world
## is built once, the candidates are written into the live node, and the shutter fires
## again from the identical camera pose.
##
## MUST RUN WINDOWED. --headless never draws and every PNG comes back empty.
##
##     godot --path . res://tests/FogShot.tscn -- /tmp/fog
##     godot --path . res://tests/FogShot.tscn -- /tmp/fog --only=reef_mid
##
## Candidate A is the SHIPPED-BEFORE-s34 curve, kept as the control: a sweep with no
## before-picture in it cannot show that anything improved.

const SHOT_PX := Vector2i(1280, 720)

## [label, reef_depth_m, max_dens, abyss_start_m, near_dens, amb_floor, amb_near, col_reach]
##
## THE SECOND ROUND ADDED THE AMBIENT, and it had to. Round one swept fog density alone:
## b and c both resolved the far leg and the kelp at 25 m where the shipped curve lost
## them, which is a real improvement and still a dark picture. "Can you see it" has two
## terms — how much medium is in the way, and how much light is on the subject — and the
## reef band was short of both. d and e are b and c with the ambient curve lifted.
const CANDIDATES := [
	["a_shipped", 13.0, 0.190, 13.0, 0.028, 0.20, 0.90, 1.00],  # the control: what s33 shipped
	["b_clear", 24.0, 0.105, 26.0, 0.028, 0.20, 0.90, 1.00],    # clarity only
	["c_clearest", 28.0, 0.075, 30.0, 0.024, 0.20, 0.90, 1.00], # more clarity, to bracket it
	["d_clear_lit", 24.0, 0.105, 26.0, 0.028, 0.34, 1.05, 1.00],# clarity + light
	["e_clearest_lit", 28.0, 0.075, 30.0, 0.024, 0.40, 1.15, 1.00],
	# ...and the colour ramp, which only matters once the band is deep enough to reach the
	# bottom of it. f/g are d with the near->deep COLOUR journey shortened so the lower reef
	# is not sitting in black water you can see 20 m through.
	["f_col72", 24.0, 0.105, 26.0, 0.028, 0.34, 1.05, 0.72],
	["g_col55", 24.0, 0.105, 26.0, 0.028, 0.34, 1.05, 0.55],
]

## Where the camera goes and what it looks at. Every one of these is a place the owner's
## complaint is about — the reef read at range — and the distances are named so the picture
## can be judged against the arithmetic rather than against a mood.
## [name, eye, target, "what this is testing"]
const SHOTS := [
	["reef_top", Vector3(34.0, -9.0, -12.0), Vector3(22.0, -12.0, -12.0),
		"the coral band top from 12 m off the leg"],
	["reef_mid", Vector3(37.0, -15.0, -12.0), Vector3(22.0, -16.0, -12.0),
		"the dense colonies from 15 m — the shot the complaint is about"],
	["reef_deep", Vector3(30.0, -20.0, -12.0), Vector3(22.0, -21.0, -12.0),
		"the band bottom from 8 m, where the abyss ramp used to start"],
	["two_legs", Vector3(0.0, -13.0, 0.0), Vector3(22.0, -14.0, -12.0),
		"across the rig at 26 m: does the far leg exist at all"],
	["look_down", Vector3(8.0, -6.0, -4.0), Vector3(8.0, -40.0, -4.0),
		"straight down — the abyss must still swallow the floor"],
	["surface_up", Vector3(10.0, -4.0, -6.0), Vector3(11.5, 1.0, -5.0),
		"the Snell window: the shallow shimmer must survive the re-grade"],
]

var _dir: String = "/tmp/fog"
var _only: String = ""
var _main: Node3D
var _fx: Node
var _done: bool = false

func _process(_d: float) -> void:
	# A focus-out pause freezes the world and STILL RENDERS: stable, plausible, meaningless
	# frames. Unpausing is not enough — the panel is its own CanvasLayer and stays drawn.
	if get_tree().paused:
		get_tree().paused = false
	_hide_pause()

func _hide_pause() -> void:
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
	# A parse error anywhere in the world graph hands back a bare Node with its script
	# dropped: it builds nothing and photographs black water that looks like a result.
	if _main == null or _main.get_script() == null:
		print("[fog] Main.tscn came back WITHOUT its script — aborting")
		get_tree().quit(1)
		return
	add_child(_main)
	await get_tree().create_timer(22.0).timeout
	GameClock.force_phase(GameClock.Phase.DAY)
	# force_phase RESETS the phase clock, and DAY f=0 is a low, red 16-degree sun — calling
	# it every frame pins the reddest end of day over the whole pass (s22 lost a render pass
	# to exactly this, and blamed a damage vignette). Set it ONCE, then write the fraction
	# of DAY wanted: 0.45 is mid-afternoon, the sun high enough to light the water properly.
	GameClock._phase_elapsed_sec = \
		float(GameClock.phase_durations_minutes[GameClock.Phase.DAY]) * 60.0 * 0.45

	_fx = _by_script(_main, "underwater_fx.gd")
	if _fx == null:
		print("[fog] no UnderwaterFX in the tree — aborting")
		get_tree().quit(1)
		return
	var player: Node3D = get_tree().get_first_node_in_group("player")
	var cam: Camera3D = player.get_node("Head/Camera3D")
	cam.current = true
	player.set_physics_process(false)
	# THE PLAYER STAYS IN THE "player" GROUP, and that is not an oversight.
	#
	# Every other shot harness here drops the lens out of that group so the fauna stop
	# hunting it (s20's crab census photographed six crabs chasing the camera). Doing it
	# HERE silently disables the entire thing under test: underwater_fx._process finds the
	# player with `get_tree().get_first_node_in_group("player")` and returns immediately
	# when there isn't one, so its depth grade never runs and main.gd's fallback curve is
	# the only writer left. The first version of this harness did exactly that and got
	# `fog_density=0.1700` back off the live camera for all five candidates — main.gd's
	# lerp at its ceiling — while confidently logging five different candidate values it
	# had written into a node that was no longer listening.
	#
	# The cost is that a curious fish may swim through a frame. That is much cheaper than
	# measuring the wrong grade, and it is also what the real game looks like.
	for p in player.find_children("*", "CollisionObject3D", true, false):
		(p as CollisionObject3D).set_collision_mask_value(1, false)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)

	for cand in CANDIDATES:
		_apply(cand)
		for shot in SHOTS:
			if _only != "" and String(shot[0]) != _only:
				continue
			await _shoot(String(cand[0]), shot, player, cam)
	print("[fog] done -> ", _dir)
	_done = true
	get_tree().quit()

## PIN THE WEATHER AND THE SUN BEFORE EVERY CANDIDATE, NOT ONCE AT THE START.
##
## The first full 30-exposure pass was thrown away because a squall rolled in half way
## through it: the grade adds `storm * (1 - t) * 0.11` to density and lerps the fog colour
## toward STORM_MURK, so the later candidates were photographed through weather the earlier
## ones never saw — and the frames look plausible, just darker, which is exactly the shape
## of a wrong conclusion. The clock drifts too: DAY runs 34 minutes and a five-candidate
## pass takes minutes, so the sun moves several degrees between the first exposure and the
## last. Both are re-pinned per candidate so every frame in the set is the same world.
func _pin_world() -> void:
	var st: Node = _main.get("storm")
	if st != null:
		st.set_process(false)
		st.set("_intensity", 0.0)
		st.set("_phase", 0)
	GameClock._phase_elapsed_sec = \
		float(GameClock.phase_durations_minutes[GameClock.Phase.DAY]) * 60.0 * 0.45

func _apply(c: Array) -> void:
	_pin_world()
	_fx.set("reef_depth_m", float(c[1]))
	_fx.set("max_dens", float(c[2]))
	_fx.set("abyss_start_m", float(c[3]))
	_fx.set("near_dens", float(c[4]))
	_fx.set("amb_floor", float(c[5]))
	_fx.set("amb_near", float(c[6]))
	_fx.set("col_reach", float(c[7]))
	# READ IT BACK. A property name that does not exist fails SILENTLY in Godot — the
	# canonical trap in this repo (shadow_normal_bias sat wrong for months). If the sweep
	# is not actually landing, every candidate photographs identically and the pass looks
	# like "the fog does not matter".
	print(("[fog] candidate %s -> reef_depth_m=%.1f max_dens=%.3f abyss_start_m=%.1f "
		+ "near_dens=%.3f amb_floor=%.2f amb_near=%.2f")
		% [c[0], _fx.get("reef_depth_m"), _fx.get("max_dens"), _fx.get("abyss_start_m"),
			_fx.get("near_dens"), _fx.get("amb_floor"), _fx.get("amb_near")])

func _shoot(tag: String, shot: Array, player: Node3D, cam: Camera3D) -> void:
	var eye: Vector3 = shot[1]
	var target: Vector3 = shot[2]
	# THE POSE HAS TO BE HELD, NOT SET. The controller keeps integrating across an await —
	# buoyancy and the fly drift — and s21 lost three frames to cameras up to 3 m from where
	# they were aimed. Re-assert every frame of the settle, then print where it ACTUALLY
	# ended up next to where it was asked for, so a camera that never arrived is visible.
	# A look_at whose direction is parallel to the up hint has no solution and Godot spams a
	# backtrace per frame while leaving the basis untouched — so the "straight down" shot
	# photographed whatever the previous frame was aimed at. Pick an up hint that cannot be
	# parallel to this particular aim.
	var aim: Vector3 = (target - eye).normalized()
	var up: Vector3 = Vector3.UP if absf(aim.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	for i in range(24):
		_pin_world()
		player.global_position = eye - Vector3(0, 1.6, 0)   # the eye is 1.6 m above the origin
		cam.global_position = eye
		cam.look_at(target, up)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	# READ THE ENVIRONMENT BACK OFF THE LIVE CAMERA. Printing the value we WROTE into
	# underwater_fx proves only that the setter ran; what decides the picture is what is on
	# the camera's Environment at shutter time, and if something else writes it after us
	# (main.gd also grades an environment) the whole sweep is a set of identical frames with
	# a confident log. This is the "read the property back off the live node" rule.
	var e: Environment = cam.environment
	var envline: String = "no environment"
	if e != null:
		envline = "fog_enabled=%s density=%.4f fog_col=%s amb_e=%.3f" % [
			str(e.fog_enabled), e.fog_density, str(e.fog_light_color), e.ambient_light_energy]
	var got: Vector3 = cam.global_position
	var img: Image = get_viewport().get_texture().get_image()
	img.resize(SHOT_PX.x, SHOT_PX.y)
	var path: String = "%s/%s_%s.png" % [_dir, tag, String(shot[0])]
	img.save_png(path)
	print("  %-15s %-11s got %s (%.2f m off), subject %.1f m | %s"
		% [tag, String(shot[0]), str(got.round()),
			eye.distance_to(got), got.distance_to(target), envline])

func _by_script(root: Node, file: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var sc: Script = n.get_script()
		if sc != null and sc.resource_path.get_file() == file:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
