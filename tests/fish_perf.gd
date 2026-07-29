extends Node3D
## DO THE FISH COST ANYTHING? — attribution harness for the shoals in underwater_world.gd.
##
## Run WINDOWED on a real GPU (--headless renders nothing and every counter reads zero):
##     godot --path . res://tests/FishPerf.tscn
##
## ocean_perf.gd already answers "what do the ocean systems cost" as a whole. This one
## isolates ONE population — the 24 species x SCHOOL_PODS pods of schooling fish — and
## measures what removing it buys back, in milliseconds.
##
## THREE THINGS THIS HARNESS DOES THAT A NAIVE ONE DOES NOT, each because the naive
## version produced a number that was wrong:
##
##  1. IT REPORTS FRAME TIME, NOT FPS, and it disables vsync first. At 60 fps capped
##     every sample reads 16.67 ms and a 2 ms saving is invisible; and an fps delta is
##     not linear in cost (90 -> 85 fps is 0.65 ms, 20 -> 18 fps is 5.6 ms).
##  2. IT INTERLEAVES AND TAKES THE MEDIAN. A first pass measured "fish cost 3.2 ms" at a
##     vantage where the fish were provably not being drawn at all (identical triangle AND
##     draw-call counts on both sides) — that was thermal drift on an M1 between two
##     samples taken a few seconds apart, not fish. Every measurement here is REPEATS
##     alternating on/off pairs, reported as the median delta with the full spread, and
##     each spot is preceded by a NULL PAIR that changes nothing, whose delta is this
##     machine's honest noise floor for the run. A cost smaller than the null pair is not
##     a measurement.
##  3. IT REMOVES THE PODS FROM THE SIM LIST rather than switching _process off. The swim
##     loop re-asserts `root.visible = want` every frame, so hiding the roots alone does
##     nothing; but switching the whole node's _process off would also stop the kelp sway,
##     the marine-snow storm response and _cull_topside, and charge all of it to the fish.
##     Emptying `_schools` (and restoring it after) removes exactly the fish and nothing
##     else, on both the CPU and the GPU side.
##
## TIME_PROCESS is reported next to frame time because the two costs are different
## problems: 500 fish each running a look_at() in GDScript is CPU, and the ~10k-triangle
## generated species meshes are GPU.

const SPOTS := [
	# The historical worst case: standing on deck looking out to the fog horizon.
	# NOTE underwater_world._cull_topside() hides this entire subtree whenever the camera
	# is more than TOPSIDE_MARGIN above the swell, so the expected answer here is ZERO —
	# which is worth measuring precisely because it is where the game is actually played.
	["deck_horizon", Vector3(0.0, 26.0, 0.0), Vector3(120.0, 8.0, 120.0)],
	# THE ONE THAT DECIDES IT. _cull_topside's margin is 4 m above the swell, so standing on
	# the PONTOON at the waterline — leaning on the rail over the leg bases, which is where
	# the lamp snails crawl and where the whole "look down at the water" beat happens — the
	# entire ocean below is live and simulating. It is the only place the player routinely
	# stands where the fish are being paid for at all.
	# y is deliberately LOW. The cull margin is measured against the LIVE swell, so a camera
	# at rail height sits right on the boundary and the whole ocean below flickers on and off
	# with the waves — which measured as a 4 ms cost with a 2.9..7.2 ms spread, i.e. as noise.
	# At 0.9 m (the pontoon top the lamp snails crawl) it is inside the margin in any sea.
	["pontoon_rail", Vector3(-18.0, 0.9, -12.0), Vector3(-52.0, -3.0, -34.0)],
	# In the water among the legs, where the near-rig pod 0 shoals work.
	["midwater_leg", Vector3(15.0, -4.2, -6.0), Vector3(22.0, -5.5, -12.0)],
	# Out in the open water at shoal depth, looking back at the rig THROUGH the pods —
	# the most fish that can be on screen at once.
	["open_shoal", Vector3(34.0, -3.4, 34.0), Vector3(0.0, -4.0, 0.0)],
]
const REPEATS: int = 5
const SETTLE: float = 0.45
const WINDOW: float = 1.4

var _main: Node3D
var _uww: Node3D
var _stash: Array = []
var _fish_nodes: int = 0

## This is launched from a terminal, so the game window never holds focus — and
## pause_menu.gd pauses the whole tree on NOTIFICATION_APPLICATION_FOCUS_OUT. A paused
## world still RENDERS, so a paused run does not look broken: it looks like a beautifully
## stable measurement in which every triangle count is identical and nothing costs
## anything. The NIGHT half of one run came back with exactly +0 triangles on every single
## row, noise floor included, which is what tipped it off. Unpause every frame, with the
## harness itself exempt (fauna_fix_shot.gd does the same for the same reason).
func _process(_d: float) -> void:
	if get_tree().paused:
		get_tree().paused = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# UNCAP THE FRAME. With vsync on, every sample above 60 fps quantises to 16.67 ms and a
	# cost of 2 ms is invisible; the whole point here is a millisecond delta.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	# Same 28 s as ocean_perf.gd: the dressing streams in and render_budget.gd sweeps
	# behind it, so an early sample measures a half-built rig with no frame budget applied.
	await get_tree().create_timer(28.0).timeout
	var player: Node3D = get_tree().get_first_node_in_group("player")
	player.set_physics_process(false)
	player.set_process(false)
	var cam: Camera3D = player.get_node("Head/Camera3D")
	cam.current = true
	cam.fov = 72.0
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	_main.storm.set_process(false)
	_main.sun_ctl.set_storm(0.0)

	_uww = _by_script(_main, "underwater_world.gd")
	for s in (_uww.get("_schools") as Array):
		_fish_nodes += (s["fish"] as Array).size()

	for phase_name in ["DAY", "NIGHT"]:
		GameClock.force_phase(GameClock.Phase.DAY if phase_name == "DAY" else GameClock.Phase.NIGHT)
		await get_tree().create_timer(1.0).timeout
		var live_pods: int = 0
		var live_fish: int = 0
		for s in (_uww.get("_schools") as Array):
			if (s["root"] as Node3D).visible:
				live_pods += 1
				live_fish += (s["fish"] as Array).size()
		print("\n=== %s | %d pods / %d fish spawned | %d pods / %d fish LIVE this phase ==="
			% [phase_name, (_uww.get("_schools") as Array).size(), _fish_nodes, live_pods, live_fish])
		for sp in SPOTS:
			player.global_position = sp[1]
			cam.global_position = sp[1]
			cam.look_at(sp[2], Vector3.UP)
			await get_tree().create_timer(1.0).timeout
			# What the frame costs in total here, so every delta below has a denominator.
			var abs_s: Array = await _sample()
			print("  %-13s frame %6.2f ms   %d tris   %d draws"
				% [sp[0], abs_s[0], int(abs_s[2]), int(abs_s[3])])
			await _paired(sp[0] + " NOISE FLOOR", func(_on: bool) -> void: pass)
			await _paired(sp[0] + " fish", _set_schools)
			# Cheap tripwire for the restore bug above: if this ever prints 0 the numbers
			# on the line before it are two identical fishless frames, not a measurement.
			if (_uww.get("_schools") as Array).size() != 48:
				print("     !! schools not restored: %d" % (_uww.get("_schools") as Array).size())
	print("\n=== what else is in the frame (open_shoal, DAY) ===")
	GameClock.force_phase(GameClock.Phase.DAY)
	player.global_position = SPOTS[2][1]
	cam.global_position = SPOTS[2][1]
	cam.look_at(SPOTS[2][2], Vector3.UP)
	await get_tree().create_timer(1.0).timeout
	var seabed: Node3D = _by_script(_main, "seabed.gd")
	var fx: Node3D = _by_script(_main, "underwater_fx.gd")
	await _paired("seabed+wreck+reef", func(on: bool) -> void: seabed.visible = on)
	await _paired("underwater FX", func(on: bool) -> void: fx.visible = on)
	# NOT `_uww.visible = on`: _cull_topside() re-asserts that flag from the node's own
	# _process every frame, so toggling it measured a perfectly steady nothing. Hide the
	# CHILDREN — nothing re-asserts those.
	# The pod roots need the _schools stash as well, or the swim loop re-shows them.
	await _paired("ALL underwater", func(on: bool) -> void:
		_set_schools(on)
		for c in _uww.get_children():
			var n3 := c as Node3D
			if n3 != null:
				n3.visible = on)
	get_tree().quit()

## Take the fish out of the world — off the GPU (roots hidden) and off the CPU (the swim
## loop iterates `_schools`, so an empty list is zero fish work) — and put them back.
func _set_schools(on: bool) -> void:
	if on:
		# Idempotent on purpose. _paired() calls the toggle ON at the top of every repeat as
		# well as after it, so a naive restore would hand back an EMPTY stash the first time
		# and delete the world's fish for the rest of the run — which is exactly what the
		# first draft did, and it reported a beautifully consistent "fish cost 0.2 ms"
		# measured between two identical fishless frames. Only restore what was taken.
		if _stash.is_empty():
			return
		_uww.set("_schools", _stash)
		_stash = []
		return
	if not _stash.is_empty():
		return
	_stash = _uww.get("_schools")
	for s in _stash:
		(s["root"] as Node3D).visible = false
	_uww.set("_schools", [])

## REPEATS interleaved on/off pairs of one toggle; report the median delta and the spread.
## Triangle and draw-call deltas are medians too — a single pair's counts wander by
## thousands of triangles on their own as visibility ranges fade and the marine-snow
## particle system breathes.
func _paired(label: String, toggle: Callable) -> void:
	var d_ms: Array[float] = []
	var d_proc: Array[float] = []
	var d_tri: Array[float] = []
	var d_draw: Array[float] = []
	for r in range(REPEATS):
		toggle.call(true)
		var on_s: Array = await _sample()
		toggle.call(false)
		var off_s: Array = await _sample()
		toggle.call(true)
		d_ms.append(on_s[0] - off_s[0])
		d_proc.append(on_s[1] - off_s[1])
		d_tri.append(float(on_s[2] - off_s[2]))
		d_draw.append(float(on_s[3] - off_s[3]))
	d_ms.sort()
	d_proc.sort()
	d_tri.sort()
	d_draw.sort()
	var mid: int = REPEATS / 2
	print("  %-26s %+6.2f ms  (proc %+5.2f ms)  spread %+.2f..%+.2f  |  %+d tris  %+d draws"
		% [label, d_ms[mid], d_proc[mid], d_ms[0], d_ms[REPEATS - 1],
		int(d_tri[mid]), int(d_draw[mid])])

## Average over a real window. Returns [frame ms, _process ms, tris, draws].
func _sample() -> Array:
	await get_tree().create_timer(SETTLE).timeout
	var frames: int = 0
	var acc_ms: float = 0.0
	var acc_proc: float = 0.0
	var t0: float = Time.get_ticks_msec() / 1000.0
	while (Time.get_ticks_msec() / 1000.0) - t0 < WINDOW:
		await get_tree().process_frame
		frames += 1
		acc_ms += get_process_delta_time() * 1000.0
		acc_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var n: float = maxf(float(frames), 1.0)
	return [acc_ms / n, acc_proc / n,
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))]

func _by_script(root: Node, tail: String) -> Node3D:
	var stack: Array = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		var s: Script = n.get_script()
		if s != null and s.resource_path.ends_with(tail):
			return n as Node3D
		for c in n.get_children():
			stack.append(c)
	return null
