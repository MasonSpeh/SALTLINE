extends Node
## DIVE PROBE — what does crossing the waterline actually cost?
##
## The owner reports "it freezes for a good second before you can see underwater". Nothing in
## DEVLOG, KNOWN_ISSUES or AGENT_TRAPS has ever put a number on it, so this harness exists to
## produce one before anything is changed.
##
## THE DISCRIMINATING EXPERIMENT is to dive TWICE. A cost only the FIRST dive pays is a one-off
## (something is being built/uploaded/compiled); a cost EVERY dive pays is the per-transition
## visibility walk, which flips `visible` on ~4,100 nodes in one frame. Both numbers are printed.
##
## WHAT s26 ESTABLISHED WITH THIS HARNESS — read before attempting a fix, because three
## plausible ones were built, measured and thrown away:
##
##   * The hitch is real and it is a one-off: dive 1 peaked 285.1 ms against 46.5 ms for an
##     identical dive 2. So the visibility walk is INNOCENT and needs no staggering.
##   * It is NOT first-draw of the subtree's materials. Drawing all 1,120 of them at load
##     through a SubViewport sharing the real World3D — verified rasterising 37.76 M primitives
##     a frame, not assumed — left the dive at 239.5 ms.
##   * It is NOT the underwater Environment. Hanging it on the real camera topside cost 275.5 ms
##     by itself and the dive STILL cost 239.6 ms afterwards: two separate ~250 ms bills.
##   * It is NOT load ordering. Gating a full rehearsal on rig_batcher's weld (so the warmed
##     configuration is the welded one) left the dive at 264.2 ms.
##
##   * IT DECAYS WITH TIME. Rehearse the transition, then sit topside before diving:
##         gap ~3 s -> 67 ms      gap 30 s -> 127 ms      gap ~36 s -> 264 ms      never -> 285 ms
##     Monotonic. Whatever goes cold is being released for not having been drawn recently —
##     consistent with GPU residency on this machine's GL-over-Metal path. THIS IS WHY NO
##     ONE-TIME PREWARM CAN WORK, and it is the constraint any future fix has to beat: the
##     candidate is keeping the subtree warm near the water (predictive/periodic), not at load.
##
## RUN WINDOWED AND IN THE FOREGROUND. --headless never draws, so it compiles no shaders and
## measures exactly nothing (it would report a clean pass). A windowed Godot launched into the
## BACKGROUND on macOS reports FROZEN renderer counters — stable, plausible, fictional. Both
## traps are in docs/AGENT_TRAPS.md.
##
##   godot --path . tests/DiveProbe.tscn

var WARMUP_SEC: float = 33.0     ## past render_budget's 8 streaming sweeps (t=24 s)
var SETTLE_FRAMES: int = 20      ## let culling/visibility ranges resolve after a jump
var SAMPLE_FRAMES: int = 41      ## odd, so the median is a real sample
var DIVE_FRAMES: int = 150       ## ~2.5 s at 60 fps: long enough to contain a 1 s freeze

## Camera heights, derived from the thresholds rather than by eye. underwater_world hides its
## subtree above TOPSIDE_MARGIN (2.8) and shows it below — and the eye is ~1.6 m above the
## player's feet, so these are FEET positions chosen to put the EYE clear of both sides.
const TOPSIDE_FEET: float = 4.0   ## eye 5.6 — well above the 3.4 hide threshold
const UNDER_FEET: float = -3.0    ## eye -1.4 — well below the 2.8 show threshold

## Hang the underwater Environment on the REAL camera for a few frames before dive 1, while the
## camera is still topside. main.gd already prewarms that Environment — but through an 8x8
## SubViewport with `own_world_3d = true`, i.e. an EMPTY world at a toy resolution. If the
## remaining stall is the main viewport instantiating that environment's pipeline (glow, SSAO,
## fog) against a real 1280x720 target with 14 M primitives in front of it, then paying it here
## will collapse dive 1 and the fix is to do exactly this at load. Set false to measure the
## untouched game.
var ENV_WARM: bool = false
var ENV_WARM_FRAMES: int = 6

## THE GHOST DIVE — the control. Actually ENTERING the underwater state is the only warm-up that
## covers the whole configuration, so this drops the camera under for a few frames, comes back
## up, and only then measures a "first" dive. Left FALSE because it is a diagnostic, not a fix:
## paired with GHOST_HOLD_SEC below it is what proved the warmth decays. Turn it on to re-derive
## the decay curve in the header, or to confirm the harness still detects a hitch when one exists.
var GHOST_DIVE: bool = false
var GHOST_FRAMES: int = 14
## Seconds to sit TOPSIDE between the ghost dive and the measured one. This is the experiment
## that separates the last two explanations of why a ghost dive at t=33 s works and main.gd's
## rehearsal at t=4 s does not:
##   * if warmth DECAYS with time, a long hold re-creates the hitch;
##   * if render_budget's 8 streaming sweeps (t=1.5..22.5 s) invalidate it, a hold that starts
##     after they finish changes nothing and the dive stays cheap.
var GHOST_HOLD_SEC: float = 30.0

enum Phase { WARMUP, GHOSTDOWN, GHOSTUP, HOLD, TOPSIDE, ENVWARM, DIVE1, UNDER, SURFACE, DIVE2, DONE }

var _phase: int = Phase.WARMUP
var _t: float = 0.0
var _main: Node
var _player: Node3D
var _cam: Camera3D
var _uw: Node3D = null
var _settle: int = 0
var _frames: Array = []
var _draws: Array = []
var _prims: Array = []
var _pause_panel: CanvasItem = null
var _unpaused: int = 0

## Per-dive traces, kept whole so the SHAPE of the hitch is visible, not just its peak.
var _dive1: Array = []
var _dive2: Array = []
var _flip1: int = -1              ## frame index within the dive at which the subtree appeared
var _flip2: int = -1
var _uw_last: bool = true

var _res: Dictionary = {}
var _env_warm_left: int = 0
var _env_trace: Array = []
var _ghost_left: int = 0
var _hold_t: float = 0.0
var _ghost_trace: Array = []

## THE FIRST DIVE OF THE SESSION — the one the player feels.
func _start_dive1() -> void:
	_uw_last = _uw.visible
	_dive1.clear()
	_flip1 = -1
	_place(UNDER_FEET)
	_phase = Phase.DIVE1

func _ready() -> void:
	# Not optional: this node inherits PAUSABLE, so a focus-out auto-pause would stop the
	# harness itself and it could never un-pause the tree again. See vantage_perf.gd.
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_main = load("res://scenes/Main.tscn").instantiate()
	_main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_main)
	print("[dive] vsync=%d  refresh=%.1f Hz  window=%s  max_fps=%d"
		% [DisplayServer.window_get_vsync_mode(), DisplayServer.screen_get_refresh_rate(),
			str(DisplayServer.window_get_size()), Engine.max_fps])
	print("[dive] warming up %.0f s…" % WARMUP_SEC)

func _freeze_world() -> void:
	# Same freeze as VantagePerf: the ONLY variable in this run is the dive itself.
	GameClock.force_phase(GameClock.Phase.DAY)
	for n in get_tree().root.get_children():
		if str(n.name) == "GameClock":
			n.process_mode = Node.PROCESS_MODE_DISABLED
	var storm: Node = _main.get("storm")
	if storm != null and is_instance_valid(storm):
		storm.process_mode = Node.PROCESS_MODE_DISABLED
	_player = get_tree().get_first_node_in_group("player")
	# Player process OFF, so _check_water() never fires and nothing fights the teleports below.
	_player.set_physics_process(false)
	_player.set_process(false)
	_cam = _player.get_node("Head/Camera3D")
	_cam.current = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	_uw = _find_script(_main, "underwater_world.gd") as Node3D
	if _uw == null:
		push_error("[dive] underwater_world not found — nothing to measure")
		_finish()
		return
	_survey_subtree()

## How big is the thing being toggled, and how many DISTINCT shaders does it hold? The second
## number is the whole case for the compilation theory: every unique shader in here is a
## compile that has never happened at the moment the player first goes under.
func _survey_subtree() -> void:
	var nodes: int = 0
	var visuals: int = 0
	var shaders: Dictionary = {}
	var stdmats: int = 0
	var stack: Array = [_uw]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		nodes += 1
		for c in n.get_children():
			stack.append(c)
		var vi := n as VisualInstance3D
		if vi != null:
			visuals += 1
		for m in _materials_of(n):
			var sm := m as ShaderMaterial
			if sm != null and sm.shader != null:
				var p: String = String(sm.shader.resource_path)
				shaders[p if p != "" else str(sm.shader.get_instance_id())] = true
			elif m is StandardMaterial3D:
				stdmats += 1
	_res["nodes"] = nodes
	_res["visuals"] = visuals
	_res["shaders"] = shaders.keys()
	_res["stdmats"] = stdmats
	print("[dive] subtree under underwater_world: %d nodes, %d VisualInstance3D" % [nodes, visuals])
	print("[dive] distinct ShaderMaterial shaders in that subtree: %d" % shaders.size())
	for k in shaders.keys():
		print("         %s" % k)
	print("[dive] StandardMaterial3D surfaces in that subtree: %d" % stdmats)

## Every material reachable off one node — override, per-surface override, and the mesh's own.
func _materials_of(n: Node) -> Array:
	var out: Array = []
	var gi := n as GeometryInstance3D
	if gi != null and gi.material_override != null:
		out.append(gi.material_override)
	var mi := n as MeshInstance3D
	if mi != null:
		for i in range(mi.get_surface_override_material_count()):
			var so: Material = mi.get_surface_override_material(i)
			if so != null:
				out.append(so)
		if mi.mesh != null:
			for i in range(mi.mesh.get_surface_count()):
				var sm: Material = mi.mesh.surface_get_material(i)
				if sm != null:
					out.append(sm)
	var mm := n as MultiMeshInstance3D
	if mm != null and mm.multimesh != null and mm.multimesh.mesh != null:
		for i in range(mm.multimesh.mesh.get_surface_count()):
			var sm2: Material = mm.multimesh.mesh.surface_get_material(i)
			if sm2 != null:
				out.append(sm2)
	return out

func _find_script(root: Node, frag: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var sc: Script = n.get_script()
		if sc != null and String(sc.resource_path).ends_with(frag):
			return n
	return null

func _place(feet_y: float) -> void:
	var p: Vector3 = _player.global_position
	_player.global_position = Vector3(p.x, feet_y, p.z)

func _begin(next: int, settle: int) -> void:
	_phase = next
	_settle = settle
	_frames.clear()
	_draws.clear()
	_prims.clear()

func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s: Array = a.duplicate()
	s.sort()
	return float(s[s.size() / 2])

func _peak(a: Array) -> float:
	var m: float = 0.0
	for v in a:
		m = maxf(m, float(v))
	return m

func _process(delta: float) -> void:
	# pause_menu auto-pauses on focus-out; a paused world still renders, so an unnoticed pause
	# produces stable, meaningless numbers.
	if get_tree().paused:
		get_tree().paused = false
		_unpaused += 1
		if _pause_panel == null:
			var pm: Node = _find_script(get_tree().root, "pause_menu.gd")
			if pm != null:
				_pause_panel = pm.get("panel") as CanvasItem
		if _pause_panel != null:
			_pause_panel.visible = false

	var ms: float = delta * 1000.0
	match _phase:
		Phase.WARMUP:
			_t += delta
			if _t < WARMUP_SEC:
				return
			_freeze_world()
			if _uw == null:
				return
			if GHOST_DIVE:
				_ghost_left = GHOST_FRAMES
				_ghost_trace.clear()
				_place(UNDER_FEET)
				_phase = Phase.GHOSTDOWN
				return
			_place(TOPSIDE_FEET)
			_begin(Phase.TOPSIDE, SETTLE_FRAMES)

		Phase.GHOSTDOWN:
			_ghost_trace.append(ms)
			_ghost_left -= 1
			if _ghost_left > 0:
				return
			print("[dive] GHOST    rehearsed the transition at load: %s ms"
				% _trace_head(_ghost_trace, 8))
			_ghost_left = GHOST_FRAMES
			_place(TOPSIDE_FEET)
			_phase = Phase.GHOSTUP

		Phase.GHOSTUP:
			# Come back up and let every system latch its topside state again, so the dive
			# measured below is a genuine cold transition in every respect except the one
			# being tested.
			_ghost_left -= 1
			if _ghost_left > 0:
				return
			_hold_t = 0.0
			_phase = Phase.HOLD

		Phase.HOLD:
			_hold_t += delta
			if _hold_t < GHOST_HOLD_SEC:
				return
			print("[dive] HOLD     sat topside %.1f s after the ghost dive" % _hold_t)
			_begin(Phase.TOPSIDE, SETTLE_FRAMES)

		Phase.TOPSIDE:
			if _settle > 0:
				_settle -= 1
				return
			_sample(ms)
			if _frames.size() < SAMPLE_FRAMES:
				return
			_res["topside_ms"] = _median(_frames)
			_res["topside_draws"] = _median(_draws)
			_res["topside_prims"] = _median(_prims)
			_res["topside_visible"] = _uw.visible
			print("[dive] TOPSIDE  median %.2f ms  draws %d  prims %.2f M  uw.visible=%s"
				% [_res["topside_ms"], int(_res["topside_draws"]),
					float(_res["topside_prims"]) / 1e6, str(_uw.visible)])
			if ENV_WARM:
				var env: Variant = _main.get("_underwater_env")
				if env is Environment:
					_cam.environment = env as Environment
					_env_warm_left = ENV_WARM_FRAMES
					_env_trace.clear()
					_phase = Phase.ENVWARM
					return
				push_warning("[dive] _underwater_env not readable — skipping the env warm")
			_start_dive1()

		Phase.ENVWARM:
			_env_trace.append(ms)
			_env_warm_left -= 1
			if _env_warm_left > 0:
				return
			# Put it back exactly as the game left it, so the dive itself is the untouched
			# transition — main._process will re-assign this on the frame it goes under.
			_cam.environment = null
			print("[dive] ENVWARM  paid the underwater Environment on the real camera topside: %s ms"
				% _trace_head(_env_trace, ENV_WARM_FRAMES))
			_start_dive1()

		Phase.DIVE1:
			if _uw.visible != _uw_last:
				_uw_last = _uw.visible
				if _flip1 < 0:
					_flip1 = _dive1.size()
			_dive1.append(ms)
			if _dive1.size() < DIVE_FRAMES:
				return
			_begin(Phase.UNDER, SETTLE_FRAMES)

		Phase.UNDER:
			if _settle > 0:
				_settle -= 1
				return
			_sample(ms)
			if _frames.size() < SAMPLE_FRAMES:
				return
			_res["under_ms"] = _median(_frames)
			_res["under_draws"] = _median(_draws)
			_res["under_prims"] = _median(_prims)
			print("[dive] UNDER    median %.2f ms  draws %d  prims %.2f M  uw.visible=%s"
				% [_res["under_ms"], int(_res["under_draws"]),
					float(_res["under_prims"]) / 1e6, str(_uw.visible)])
			_place(TOPSIDE_FEET)
			_begin(Phase.SURFACE, SETTLE_FRAMES)

		Phase.SURFACE:
			if _settle > 0:
				_settle -= 1
				return
			_sample(ms)
			if _frames.size() < SAMPLE_FRAMES:
				return
			# SECOND DIVE, identical move, same session. Every shader in that subtree has now
			# been drawn once. If this one is cheap, the freeze was compilation.
			_uw_last = _uw.visible
			_dive2.clear()
			_flip2 = -1
			_place(UNDER_FEET)
			_phase = Phase.DIVE2

		Phase.DIVE2:
			if _uw.visible != _uw_last:
				_uw_last = _uw.visible
				if _flip2 < 0:
					_flip2 = _dive2.size()
			_dive2.append(ms)
			if _dive2.size() < DIVE_FRAMES:
				return
			_report()
			_finish()

		Phase.DONE:
			pass

func _sample(ms: float) -> void:
	_frames.append(ms)
	_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))

## Frames over the hitch line, and the wall-clock they add up to. The line is 2x the steady
## underwater median: comfortably past ordinary frame noise, well under a visible stall.
func _hitch(trace: Array, line: float) -> Dictionary:
	var over: int = 0
	var lost: float = 0.0
	var peak: float = 0.0
	var peak_at: int = -1
	var total: float = 0.0
	for i in range(trace.size()):
		var v: float = float(trace[i])
		total += v
		if v > peak:
			peak = v
			peak_at = i
		if v > line:
			over += 1
			lost += v
	return {"over": over, "lost": lost, "peak": peak, "peak_at": peak_at, "total": total}

func _trace_head(trace: Array, n: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i in range(mini(n, trace.size())):
		parts.append("%.1f" % float(trace[i]))
	return ", ".join(parts)

func _report() -> void:
	var under_ms: float = float(_res.get("under_ms", 16.0))
	var line: float = under_ms * 2.0
	var h1: Dictionary = _hitch(_dive1, line)
	var h2: Dictionary = _hitch(_dive2, line)
	print("\n================ DIVE COST ================")
	print("steady frames:  topside %.2f ms   underwater %.2f ms" % [float(_res.get("topside_ms", 0.0)), under_ms])
	print("subtree toggled: %d nodes / %d VisualInstance3D / %d distinct shaders"
		% [int(_res.get("nodes", 0)), int(_res.get("visuals", 0)), (_res.get("shaders", []) as Array).size()])
	print("prims topside %.2f M -> underwater %.2f M   draws %d -> %d"
		% [float(_res.get("topside_prims", 0.0)) / 1e6, float(_res.get("under_prims", 0.0)) / 1e6,
			int(_res.get("topside_draws", 0)), int(_res.get("under_draws", 0))])
	print("hitch line (2x steady underwater): %.2f ms\n" % line)
	print("DIVE 1 (first of the session)  peak %.1f ms at frame %d   frames over line: %d   time in them: %.0f ms"
		% [h1["peak"], h1["peak_at"], h1["over"], h1["lost"]])
	print("   subtree appeared at frame %d;  first 12 frames: %s" % [_flip1, _trace_head(_dive1, 12)])
	print("DIVE 2 (same move, same session) peak %.1f ms at frame %d   frames over line: %d   time in them: %.0f ms"
		% [h2["peak"], h2["peak_at"], h2["over"], h2["lost"]])
	print("   subtree appeared at frame %d;  first 12 frames: %s" % [_flip2, _trace_head(_dive2, 12)])
	print("\n---- verdict ----")
	var p1: float = float(h1["peak"])
	var p2: float = float(h2["peak"])
	var ratio: float = p1 / maxf(p2, 0.001)
	if p1 < line and p2 < line:
		print("NO HITCH REPRODUCED at this vantage. Neither dive broke %.1f ms. Either the freeze" % line)
		print("needs a path this harness does not take (a real swim in, streaming still running,")
		print("or a cold shader cache in .godot/), or it is not in the transition at all.")
	elif ratio >= 2.0:
		print("A ONE-OFF COST, NOT THE VISIBILITY WALK. Dive 1 peaked %.1fx dive 2 (%.1f vs %.1f ms)" % [ratio, p1, p2])
		print("on an identical move, so the ~4,100-node visible flip is innocent and needs no")
		print("staggering. Do NOT reach for a load-time prewarm: s26 measured three of them and")
		print("all three failed, because the warm state DECAYS with time hidden. See the header.")
	else:
		print("THE VISIBILITY WALK, or nothing at all. Both dives cost about the same (%.1f vs" % p1)
		print("%.1f ms), so this is a per-transition cost rather than the one-off s26" % p2)
		print("characterised. Re-read the header before acting on it.")
	print("\nfocus-out re-unpauses during the run: %d (0 is ideal)" % _unpaused)
	print("===========================================")

func _finish() -> void:
	_phase = Phase.DONE
	await get_tree().create_timer(0.4).timeout
	get_tree().quit()
