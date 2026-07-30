extends Node
## VANTAGE FRAME TIME — the before/after ruler for optimisation work.
##
## tps_profile.gd answers "which subsystem owns the frame". This answers the other half:
## "did the change actually make the frame cheaper, at the places a player stands?" It
## parks the camera at a fixed list of vantages, samples, and prints a median per vantage
## — so the same script run before and after an edit is a like-for-like comparison.
##
## Why it is built the way it is (all three learned the expensive way in this repo):
##
##  1. VSYNC OFF. With it on, every sample quantises to the refresh interval and a 4 ms
##     win reads as zero.
##  2. MEDIAN, NEVER MEAN. One 250 ms hitch swamps a 41-frame mean.
##  3. A PUBLISHED NOISE FLOOR. Each vantage is visited ROUNDS times, round-robin, and the
##     spread between the rounds' medians is printed next to the result. A change smaller
##     than its vantage's own noise figure is not a result, it is thermal drift — this
##     machine drifts several fps over a run.
##
## The world is FROZEN (clock forced, storm parked, player process off) so lighting and
## weather cannot change underneath the measurement, and the tree is FORCE-UNPAUSED every
## frame: pause_menu.gd auto-pauses on focus-out, and a paused world still renders, so
## losing focus mid-run yields beautiful, stable, meaningless numbers.
##
## Run WINDOWED (--headless draws nothing and every render monitor reads 0):
##   godot --path . res://tests/VantagePerf.tscn

## Defaults; every one is overridable on the command line so a diagnostic pass costs 40
## seconds instead of six minutes (--warmup=8 --rounds=1 --nosweep). Batching Godot runs
## matters here: relaunching the editor repeatedly lags the machine this is measured on.
var WARMUP_SEC: float = 33.0      ## past render_budget's 8 streaming sweeps (t=24 s)
var SETTLE_FRAMES: int = 14       ## let visibility ranges + culling resolve after a jump
var SAMPLE_FRAMES: int = 41       ## odd, so the median is a real sample
var ROUNDS: int = 3               ## revisits per vantage; the spread across them is the noise
var DO_SWEEP: bool = true
## --cullproof: don't measure, PROVE THE CULL IS INVISIBLE. See _cull_proof().
var CULL_PROOF: bool = false

func _args() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--warmup="):
			WARMUP_SEC = float(a.split("=")[1])
		elif a.begins_with("--rounds="):
			ROUNDS = maxi(1, int(a.split("=")[1]))
		elif a.begins_with("--frames="):
			SAMPLE_FRAMES = maxi(3, int(a.split("=")[1]))
		elif a == "--nosweep":
			DO_SWEEP = false
		elif a == "--cullproof":
			CULL_PROOF = true
			DO_SWEEP = false

## [name, eye, look_at]. The eye is the CAMERA position (the player's eye is ~1.6 m above
## its origin — aiming from the node origin photographs the floor).
const SPOTS := [
	["deck_floodlit", Vector3(0.0, 20.0, -1.0), Vector3(14.0, 19.0, 7.0)],
	["ops_lookout", Vector3(26.0, 39.0, -2.0), Vector3(20.0, 38.0, 6.0)],
	["wet_deck", Vector3(16.0, 4.0, -19.0), Vector3(13.0, 3.5, -12.0)],
	["waterline", Vector3(0.0, 1.1, -17.0), Vector3(0.0, -2.0, -34.0)],
	["submerged_mid", Vector3(0.0, -5.0, -16.0), Vector3(0.0, -6.0, -34.0)],
	["submerged_deep", Vector3(-8.0, -12.0, -6.0), Vector3(8.0, -13.0, 6.0)],
]

## WHAT GETS AN A/B/A. Order matters for two of these:
##   * "none" is the NULL PAIR — it toggles nothing at all, so its "cost" column is this
##     vantage's pure measurement noise for a job of exactly this shape and length. Every
##     other row on the same vantage has to beat it to be a result. (The per-row `noise`
##     figure is the same idea from inside the row; the null pair is the honest outside view,
##     because a toggle that costs nothing still perturbs nothing and should read ~0.)
##   * "reef_fish" is measured BEFORE "leg_reef" and hides only the fish; "leg_reef" hides
##     only the coral MultiMeshes (not the whole node) so the two are separable rather than
##     nested — s20 parents reef_fish.gd UNDER leg_reef.gd, so `_reef.visible = false` would
##     have charged the coral for the fish.
##   * "fauna_sim" and "uw_sim" are SCRIPT attribution, not render attribution: they stop the
##     subtree processing without hiding it, which is the only way to separate "what is this
##     costing to draw" from "what is this costing to think". They are diagnostics — a
##     measurement of the ceiling, not a proposal — because a world whose animals do not move
##     is not the game.
##   * "reef_cull" and "hidden_stride" are THIS session's own optimisations, measured the same
##     way as everything else. Both are switchable at runtime specifically so they can be A/B'd
##     here rather than across two runs: the machine's drift between runs is ~1-2 ms, which is
##     larger than either effect, and a cross-run table cannot honestly resolve them.
const SWEEPS: Array[String] = [
	"none", "reef_cull", "hidden_stride", "sun_shadow", "fauna_sim",
]

enum Phase { WARMUP, RUN, SWEEP, DONE }

var _phase: int = Phase.WARMUP
var _t: float = 0.0
var _main: Node
var _player: Node3D
var _cam: Camera3D
var _round: int = 0
var _spot: int = 0
var _settle: int = 0
var _frames: Array = []
var _procs: Array = []
var _draws: Array = []
var _prims: Array = []
## name -> [{ms, proc, draw, prim}] one entry per round
var _res: Dictionary = {}
## SWEEP: [{vantage, name, kind}] — one A/B/A per toggle per vantage.
var _jobs: Array = []
var _job: int = 0
var _step: int = 0                ## 0 = ON, 1 = OFF, 2 = ON again
var _win_ms: Array = []
var _win_draw: Array = []
var _sweep_rows: Array = []
var _reef: Node3D = null
var _reef_mm: Array = []          ## the coral MultiMeshInstance3Ds, hidden without the fish
var _fish: Node3D = null
var _sun: DirectionalLight3D = null
var _envs: Array = []             ## surface Environment + the camera's underwater one
var _uw: Node3D = null            ## underwater_world, whose topside cull owns 4.5 M prims
var _fauna: Node3D = null         ## bloom_fauna, the 27-species host
var _uw_flips: int = 0            ## how often that cull changed its mind inside one window
var _uw_last: bool = true
var _pause_panel: CanvasItem = null
var _unpaused: int = 0            ## how often focus-out tried to freeze the run

func _ready() -> void:
	# PROCESS_MODE_ALWAYS is not optional and it is not belt-and-braces. Un-pausing every
	# frame (below) is necessary and NOT sufficient: this node inherits PAUSABLE, so the
	# instant pause_menu.gd auto-pauses on focus-out — which happens on a long background run
	# every time anything else takes the screen — the harness itself stops processing and can
	# never un-pause the tree again, while `create_timer` keeps firing. The run then completes
	# over a FROZEN world and prints stable, plausible, meaningless numbers. Cost s20 a whole
	# render pass; see docs/AGENT_TRAPS.md.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_args()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_main = load("res://scenes/Main.tscn").instantiate()
	# PROCESS_MODE_ALWAYS above propagates to every child that inherits, i.e. to the whole
	# game. Put the world back on the shipped mode explicitly so what is being measured is
	# the game as it runs, and only the HARNESS is pause-proof.
	_main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_main)
	# Say the measurement conditions out loud. vsync quantises every sample to the refresh
	# interval and a 4 ms win then reads as zero, so "vsync off" is a claim that has to be
	# checkable from the log rather than trusted. RUN THIS IN THE FOREGROUND: a windowed Godot
	# launched into the background on macOS came back with the renderer counters FROZEN at
	# their first-frame values (identical draws/prims at all six vantages) and a constant
	# 6.90 ms delta — stable, plausible and completely fictional.
	print("[vantage] vsync=%d  refresh=%.1f Hz  window=%s  max_fps=%d"
		% [DisplayServer.window_get_vsync_mode(), DisplayServer.screen_get_refresh_rate(),
			str(DisplayServer.window_get_size()), Engine.max_fps])
	print("[vantage] warming up %.0f s, then %d vantages x %d rounds…" % [WARMUP_SEC, SPOTS.size(), ROUNDS])

func _freeze_world() -> void:
	GameClock.force_phase(GameClock.Phase.DAY)
	for n in get_tree().root.get_children():
		if str(n.name) == "GameClock":
			n.process_mode = Node.PROCESS_MODE_DISABLED
	var storm: Node = _main.get("storm")
	if storm != null and is_instance_valid(storm):
		storm.process_mode = Node.PROCESS_MODE_DISABLED
	_player = get_tree().get_first_node_in_group("player")
	_player.set_physics_process(false)
	_player.set_process(false)
	_cam = _player.get_node("Head/Camera3D")
	_cam.current = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	_reef = _find_script(_main, "leg_reef.gd") as Node3D
	if _reef != null:
		for n in _reef.find_children("LegReef_*", "MultiMeshInstance3D", false, false):
			_reef_mm.append(n)
	_fish = _find_script(_main, "reef_fish.gd") as Node3D
	_uw = _find_script(_main, "underwater_world.gd") as Node3D
	_fauna = _find_script(_main, "bloom_fauna.gd") as Node3D
	# The sun is the first DirectionalLight3D under Main (main.gd depends on that too — the
	# sky tracks it). The moon is authored shadowless, so "sun_shadow" cannot pick it up.
	for n in _main.get_children():
		var dl := n as DirectionalLight3D
		if dl != null and dl.shadow_enabled and _sun == null:
			_sun = dl
	for n in _main.get_children():
		var we := n as WorldEnvironment
		if we != null and we.environment != null:
			_envs.append(we.environment)
	var uw_env: Variant = _main.get("_underwater_env")
	if uw_env is Environment:
		_envs.append(uw_env)
	print("[vantage] world frozen (clock DAY + parked, storm parked, player process off)")
	print("[vantage] leg reef: %s (%d coral MultiMeshes)   reef fish: %s   sun: %s   envs: %d"
		% ["found" if _reef != null else "NOT PRESENT", _reef_mm.size(),
			"found" if _fish != null else "NOT PRESENT",
			"found" if _sun != null else "NOT PRESENT", _envs.size()])

## Find a node by the file its script came from — the world is built in code, so node names
## are autogenerated and the script IS the identity.
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

## Flip one sweep target. Toggles are chosen so each isolates ONE question: what is the AI
## decimation actually buying at this vantage, and what is the new leg reef actually costing.
func _toggle(kind: String, on: bool) -> void:
	match kind:
		"none":
			pass                      # the null pair — see SWEEPS
		"ai_decimation":
			AiBudget.enabled = on
		"leg_reef":
			for n in _reef_mm:
				(n as Node3D).visible = on
		"reef_fish":
			if _fish != null:
				_fish.visible = on
		"glow":
			for e in _envs:
				(e as Environment).glow_enabled = on
		"sun_shadow":
			if _sun != null:
				_sun.shadow_enabled = on
		"reef_cull":
			if _reef != null:
				_reef.set("cull_above_water", on)
		"hidden_stride":
			# OFF = back to the s19 value. Not 1: the point is what the LOOSER stride bought on
			# top of the decimation that already existed, not what decimation is worth (that is
			# the ai_decimation row).
			AiBudget.HIDDEN_STRIDE = 8 if on else 4
		"fauna_sim":
			if _fauna != null:
				_fauna.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		"uw_sim":
			if _uw != null:
				# Do NOT hide it — that would measure its DRAW cost, which the leg_reef and
				# reef_fish rows already isolate. Stopping _process stops the swim, the kelp
				# sway and the topside cull, i.e. exactly the GDScript.
				_uw.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED

func _place(s: Array) -> void:
	_player.global_position = (s[1] as Vector3) - Vector3(0.0, 1.6, 0.0)
	_cam.global_position = s[1]
	_cam.look_at(s[2], Vector3.UP)

func _process(delta: float) -> void:
	# pause_menu auto-pauses on focus-out; a paused world still renders.
	if get_tree().paused:
		get_tree().paused = false
		_unpaused += 1
		# Resuming the tree does NOT take the panel down — it is its own CanvasLayer, so it
		# stays drawn over every subsequent frame (and a full-screen panel is not free to
		# fill). Take it down with the pause.
		if _pause_panel == null:
			var pm: Node = _find_script(get_tree().root, "pause_menu.gd")
			if pm != null:
				_pause_panel = pm.get("panel") as CanvasItem
		if _pause_panel != null:
			_pause_panel.visible = false
	match _phase:
		Phase.WARMUP:
			_t += delta
			if _t < WARMUP_SEC:
				return
			_freeze_world()
			if CULL_PROOF:
				_phase = Phase.DONE
				_cull_proof()
				return
			_phase = Phase.RUN
			_place(SPOTS[0])
			_start()
		Phase.RUN:
			if _uw != null:
				# underwater_world._cull_topside hides ~4.5 M primitives whenever the camera is
				# more than TOPSIDE_MARGIN above the SWELL AT ITS OWN XZ — a moving threshold.
				# Count every time it changes its mind inside a sample window: a vantage within
				# the wave amplitude of that boundary toggles a several-thousand-node subtree
				# several times a second, which is both a real hitch and the reason such a
				# vantage cannot be measured (see KNOWN_ISSUES on wet_deck).
				if _uw.visible != _uw_last:
					_uw_last = _uw.visible
					_uw_flips += 1
			if _settle > 0:
				_settle -= 1
				return
			_frames.append(delta * 1000.0)
			_procs.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			_prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			if _frames.size() < SAMPLE_FRAMES:
				return
			_record()
		Phase.SWEEP:
			if _settle > 0:
				_settle -= 1
				return
			_frames.append(delta * 1000.0)
			_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			if _frames.size() < SAMPLE_FRAMES:
				return
			_sweep_step()
		Phase.DONE:
			pass

## ---------------------------------------------------------------- proving the cull
##
## underwater_world hides its whole subtree once the camera is TOPSIDE_MARGIN above the sea.
## That is a CULL, so the only thing that makes it legitimate is that the player cannot tell:
## ocean_water.gdshader is `depth_draw_opaque` with no blend mode, i.e. genuinely opaque, so
## nothing below it should reach the frame from any angle. "Should" is an argument. This is
## the measurement.
##
## Three captures per vantage, and the reason there are three is the same reason the frame
## timing uses a null pair: the sea and the deck fauna are moving, so two IDENTICAL frames do
## not match either, and a difference is only evidence if it beats the difference that changing
## nothing produces. So: underwater world ON, ON again, then OFF. The ON/ON pair is the null.
## If ON/OFF is no worse than ON/ON, the cull removed nothing that was reaching the screen.
##
## The subtree's own _process is stopped for the duration (it would re-assert `visible` from
## the cull rule this is testing, and it also freezes the fish so the null pair is clean).
## A LADDER OF CAMERA HEIGHTS, because the question is not "is this cull visible" but "from
## what height up does it stop being visible" — and that is the margin, measured instead of
## typed. Each row leans out over open water and looks down into it at ~25 degrees, which is
## the sight line that sees furthest into a surface (straight down sees least, because the
## fan's near quads fill the frame).
const PROOF_HEIGHTS: Array[float] = [2.05, 3.0, 3.6, 4.5, 6.0]
## Where from. z -17 is off the south pontoon over open water; the wet deck plating is y 2.0,
## so 3.6 is a standing eye there and 1.2 is lying on the pontoon edge.
const PROOF_EYE_XZ := Vector2(0.0, -17.0)
const PROOF_LOOK := Vector3(0.0, -6.0, -30.0)

func _cull_proof() -> void:
	print("\n=========== WHAT IS VISIBLE FROM ABOVE THE WATER? ===========")
	print("Two culls, measured the same way: the WHOLE underwater world, and the LEG REEF on")
	print("its own (y -3.4..-22, 4.26 M tris, the expensive half). Each is hidden and the frame")
	print("compared against the same frame with it shown.")
	print("'null' is show-vs-show — the sea and the fauna are moving, so this is the difference")
	print("that changing NOTHING produces, and no smaller difference is evidence of anything.")
	print("A cull whose numbers sit on the null floor removed nothing that reached the screen.")
	var targets: Array = []
	if _uw != null:
		targets.append(["uw_world", _uw])
	if _reef != null:
		targets.append(["leg_reef", _reef])
	if targets.is_empty():
		print("nothing found to prove")
		get_tree().quit()
		return
	# Stop the subtree processing for the duration: underwater_world would re-assert `visible`
	# from the very rule under test, and freezing the fish is also what makes the null pair a
	# null pair rather than a measurement of swimming.
	var prev_uw: int = _uw.process_mode if _uw != null else 0
	if _uw != null:
		_uw.process_mode = Node.PROCESS_MODE_DISABLED
	# THE SEA NEVER STOPS, and the first version of this test was destroyed by that. The null
	# pair was captured ONE frame apart and the cull pair FIVE, so the cull "cost" was five
	# frames of swell measured against one — a constant ~4x, at every height, for both targets,
	# entirely independent of the thing being varied. A textbook fake result.
	#
	# The fix is EQUAL GAPS: every capture is GAP frames after the one before it, so whatever
	# is still moving moves the same amount inside the null window as inside the test window.
	#
	# The obvious alternative — Engine.time_scale = 0, freezing the world outright — was tried
	# and is a TRAP worth the paragraph. A zero delta divides by zero inside the fauna movement
	# code and produces the NaN that defeats every guard in this repo (docs/AGENT_TRAPS.md):
	# the run filled stderr with "Vector3 cannot be normalized" at frame rate and had written
	# 5.4 GB before it was killed. Freeze a world by removing its motion, never by zeroing its
	# clock.
	#
	# GAP IS 1 FOR A REASON, and 6 was the second way to get a useless answer out of this. With
	# equal 6-frame gaps the arithmetic is fair but the sea has moved so far in both windows
	# that the null floor (mean ~3, 1400-3700 pixels over threshold) is larger than anything a
	# hidden reef could contribute, and EVERY row certifies "invisible" — including a camera at
	# 1.2 m that is sometimes under a crest and where the answer is definitely no. A `visible`
	# flag applies to the next drawn frame, so one frame is all the gap the toggle needs, and
	# one frame is as still as this ocean ever gets.
	const GAP: int = 1
	# THE STATISTIC, and why it is not a frame difference. A moving sea differs from itself
	# everywhere by a little (specular shimmer over the whole surface), and the amplitude cannot
	# be turned off — the ocean shader's amp_scale bottoms out at 0.18, not 0. So no whole-frame
	# mean or max can separate "the reef is showing through" from "the swell moved".
	#
	# What CAN: three captures one frame apart, A / middle / C, with A and C both showing the
	# target. |A - C| is then a per-pixel MOTION MASK over the same two-frame span the test
	# straddles. Count only pixels where the middle frame differs from A by a lot AND the mask
	# says that pixel was steady. Those are pixels the TOGGLE changed and motion did not, which
	# is exactly the question. Run the identical statistic with nothing toggled and you get the
	# null count, which is what the answer has to beat.
	print("\n%-10s %6s %12s %12s   %s"
		% ["target", "eye y", "null px", "cull px", "verdict"])
	for t in targets:
		var node: Node3D = t[1]
		for hy in PROOF_HEIGHTS:
			_place(["proof", Vector3(PROOF_EYE_XZ.x, hy, PROOF_EYE_XZ.y), PROOF_LOOK])
			node.visible = true
			for i in range(SETTLE_FRAMES):
				await get_tree().process_frame
			var null_px: float = await _triple(node, false, GAP)
			var cull_px: float = await _triple(node, true, GAP)
			node.visible = true
			var clean: bool = cull_px <= maxf(null_px * 2.0, 12.0)
			print("  %-8s %6.2f %12.0f %12.0f   %s"
				% [t[0], hy, null_px, cull_px, "invisible" if clean else "VISIBLE"])
	if _uw != null:
		_uw.process_mode = prev_uw
	print("\nThe margin each cull needs is the lowest eye y whose row reads 'invisible' and")
	print("stays invisible above it. PNG pairs for every VISIBLE row are in /tmp/cullproof_*.")
	print("=============================================================")
	get_tree().quit()

## Capture A / middle / C one frame apart, optionally hiding `node` for the middle frame only,
## and return how many sampled pixels the middle frame changed A LOT in that were STEADY between
## A and C. With `toggle` false this is the null: the same statistic with nothing changed.
func _triple(node: Node3D, toggle: bool, gap: int) -> float:
	node.visible = true
	var a: Image = await _grab()
	if toggle:
		node.visible = false
	for i in range(gap):
		await get_tree().process_frame
	var mid: Image = await _grab()
	node.visible = true
	for i in range(gap):
		await get_tree().process_frame
	var c: Image = await _grab()
	if a.get_size() != mid.get_size() or a.get_size() != c.get_size():
		return 1.0e9
	var hits: int = 0
	for y in range(0, a.get_height(), 3):
		for x in range(0, a.get_width(), 3):
			var ca: Color = a.get_pixel(x, y)
			var cc: Color = c.get_pixel(x, y)
			var moved: float = 255.0 * maxf(maxf(absf(ca.r - cc.r), absf(ca.g - cc.g)),
				absf(ca.b - cc.b))
			if moved > 8.0:
				continue                      # the sea moved here; this pixel cannot testify
			var cm: Color = mid.get_pixel(x, y)
			var d: float = 255.0 * maxf(maxf(absf(ca.r - cm.r), absf(ca.g - cm.g)),
				absf(ca.b - cm.b))
			if d > BIG_DIFF:
				hits += 1
	return float(hits)

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

## [mean, max, count over BIG] per-channel absolute difference, 0..255.
const BIG_DIFF: float = 24.0

func _diff(a: Image, b: Image) -> Array:
	if a.get_size() != b.get_size():
		return [255.0, 255.0, 1.0e9]
	var w: int = a.get_width()
	var h: int = a.get_height()
	var total: float = 0.0
	var worst: float = 0.0
	var big: int = 0
	# Every 3rd row and column: 1/9 of ~0.9 M pixels is still 100k samples, which is plenty to
	# find a reef that should not be there, and it keeps the whole proof inside one frame's
	# worth of GDScript per capture.
	var n: int = 0
	for y in range(0, h, 3):
		for x in range(0, w, 3):
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			var d: float = 255.0 * maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b))
			total += d
			worst = maxf(worst, d)
			if d > BIG_DIFF:
				big += 1
			n += 1
	return [total / maxf(float(n), 1.0), worst, float(big)]

func _start() -> void:
	_settle = SETTLE_FRAMES
	_frames.clear()
	_procs.clear()
	_draws.clear()
	_prims.clear()

func _median(a: Array) -> float:
	var b: Array = a.duplicate()
	b.sort()
	return float(b[b.size() / 2])

func _record() -> void:
	var name: String = SPOTS[_spot][0]
	if not _res.has(name):
		_res[name] = []
	(_res[name] as Array).append({
		"ms": _median(_frames), "proc": _median(_procs),
		"draw": _median(_draws), "prim": _median(_prims),
		"uw": _uw != null and _uw.visible, "flips": _uw_flips,
		"eye": _cam.global_position, "fwd": -_cam.global_transform.basis.z})
	# PRINT WHERE THE CAMERA ACTUALLY ENDED UP, not where it was asked to go. A shot list
	# that reports only its intended position cannot tell you it missed (docs/AGENT_TRAPS.md),
	# and identical draw counts at six different vantages is exactly what a camera that never
	# moved looks like.
	print("  [%-14s r%d] eye %s  draws %.0f  prims %.0f  uw_vis %-3s reef %-3s flips %d"
		% [name, _round, str(_cam.global_position.round()),
			_median(_draws), _median(_prims),
			"yes" if (_uw != null and _uw.visible) else "no",
			"yes" if (_reef != null and _reef.is_visible_in_tree()) else "no", _uw_flips])
	_uw_flips = 0
	_spot += 1
	if _spot >= SPOTS.size():
		_spot = 0
		_round += 1
		if _round >= ROUNDS:
			_report()
			if not DO_SWEEP:
				_phase = Phase.DONE
				get_tree().quit()
				return
			_begin_sweep()
			return
	_place(SPOTS[_spot])
	_start()

## THE ATTRIBUTION HALF. The vantage table above says what the frame costs today; it cannot
## say what any one change is worth, because the only honest comparison — the same build,
## the same content, the same thermal state — is impossible across two runs an hour apart.
## (This mattered here: a 560-instance coral reef landed between the before and after runs,
## so the plain table is measuring my optimisation AND somebody else's new content at once.)
## So each toggle is measured ON / OFF / ON in ONE session, at each vantage, and the spread
## between the two ON windows is published next to the result as that row's noise floor.
func _begin_sweep() -> void:
	for s in SPOTS:
		for kind in SWEEPS:
			if kind == "reef_cull" and _reef == null:
				continue
			if kind == "leg_reef" and _reef_mm.is_empty():
				continue
			if kind == "reef_fish" and _fish == null:
				continue
			if kind == "sun_shadow" and _sun == null:
				continue
			if kind == "fauna_sim" and _fauna == null:
				continue
			if kind == "uw_sim" and _uw == null:
				continue
			_jobs.append({"vantage": s, "kind": kind})
	# Budget the run out loud. A profiling harness that takes an hour gets killed before it
	# prints (docs/AGENT_TRAPS.md) — so say how long this one is going to be, up front.
	var f: int = _jobs.size() * 3 * (SETTLE_FRAMES + SAMPLE_FRAMES)
	print("\n[vantage] sweep: %d A/B/A measurements, %d frames (~%.0f s at 30 ms)…"
		% [_jobs.size(), f, f * 0.030])
	_phase = Phase.SWEEP
	_job = 0
	_step = 0
	_win_ms.clear()
	_win_draw.clear()
	_place(_jobs[0]["vantage"])
	_start()

func _sweep_step() -> void:
	_win_ms.append(_median(_frames))
	_win_draw.append(_median(_draws))
	var job: Dictionary = _jobs[_job]
	if _step == 0:
		_toggle(job["kind"], false)
		_step = 1
		_start()
		return
	if _step == 1:
		_toggle(job["kind"], true)
		_step = 2
		_start()
		return
	var on_ms: float = (_win_ms[0] + _win_ms[2]) * 0.5
	# The draw delta is the PROOF THE TOGGLE LANDED. A row whose ms moved while its draw
	# count did not is the shape of a measurement that is really thermal drift — and a row
	# that reads 0 ms AND 0 draws was never testing anything at this vantage (the reef is
	# frustum-culled from the deck, for instance), which is a different and useful answer.
	_sweep_rows.append({"vantage": job["vantage"][0], "kind": job["kind"],
		"cost": on_ms - _win_ms[1], "on": on_ms, "noise": absf(_win_ms[0] - _win_ms[2]),
		"draw": (_win_draw[0] + _win_draw[2]) * 0.5 - _win_draw[1]})
	_win_ms.clear()
	_win_draw.clear()
	_step = 0
	_job += 1
	if _job >= _jobs.size():
		_report_sweep()
		return
	_place(_jobs[_job]["vantage"])
	_start()

func _report_sweep() -> void:
	_phase = Phase.DONE
	print("\n=========== WHAT EACH THING COSTS, PER VANTAGE ===========")
	print("ms recovered when the thing is switched OFF, measured ON/OFF/ON in one session.")
	print("'noise' is this row's own spread between its two ON windows — a cost smaller")
	print("than its own noise figure is drift, not a measurement.")
	# The null pair per vantage, so every other row can be read against it.
	var null_floor: Dictionary = {}
	for r in _sweep_rows:
		if r["kind"] == "none":
			null_floor[r["vantage"]] = absf(r["cost"])
	print("%-16s %-14s %9s %9s %8s %8s %8s" % ["vantage", "thing", "ms saved", "of ms", "%", "noise", "draws"])
	for r in _sweep_rows:
		var nf: float = maxf(float(null_floor.get(r["vantage"], 0.0)), r["noise"])
		var trust: String = "  " if absf(r["cost"]) > nf else " ?"
		print("%s %-14s %-14s %9.2f %9.2f %7.1f%% %8.2f %8.0f"
			% [trust, r["vantage"], r["kind"], r["cost"], r["on"],
				100.0 * r["cost"] / maxf(r["on"], 0.001), r["noise"], r["draw"]])
	print("\nfocus-out re-unpauses during the run: %d — 0 is ideal; any number here means the"
		% _unpaused)
	print("window lost focus and the world would have FROZEN without PROCESS_MODE_ALWAYS.")
	print("\n('?' = below its own noise floor OR below this vantage's null pair)")
	print("null pair per vantage (ms): %s" % str(null_floor))
	print("ai_decimation OFF means every creature ticks every frame — the pre-change")
	print("behaviour. leg_reef OFF hides the coral MultiMeshes only; reef_fish OFF hides the")
	print("252 reef fish only; glow OFF drops the environment bloom post-process; sun_shadow")
	print("OFF drops the directional shadow pass entirely (a ceiling, not a proposal).")
	print("=========================================================\n")
	get_tree().quit()

func _report() -> void:
	_phase = Phase.DONE
	print("\n\n================ VANTAGE FRAME TIME ================")
	print("median of %d frames per visit, %d visits per vantage." % [SAMPLE_FRAMES, ROUNDS])
	print("'noise' = spread between this vantage's own repeat visits. A before/after")
	print("difference smaller than that figure is drift, not a result.")
	print("%-16s %8s %8s %8s %9s %11s" % ["vantage", "ms", "fps", "noise", "script ms", "draw calls"])
	for s in SPOTS:
		var name: String = s[0]
		var runs: Array = _res.get(name, [])
		if runs.is_empty():
			continue
		var ms: Array = []
		var pr: Array = []
		for r in runs:
			ms.append(r["ms"])
			pr.append(r["proc"])
		var med: float = _median(ms)
		var lo: float = ms.min()
		var hi: float = ms.max()
		print("%-16s %8.2f %8.1f %8.2f %9.2f %11.0f" % [name, med, 1000.0 / maxf(med, 0.001),
			hi - lo, _median(pr), float(runs[0]["draw"])])
	print("\nper-visit detail (ms):")
	for s in SPOTS:
		var name: String = s[0]
		var runs: Array = _res.get(name, [])
		if runs.is_empty():
			continue
		var parts: Array = []
		for r in runs:
			parts.append("%.2f" % float(r["ms"]))
		print("  %-16s %s   prims %.0f" % [name, ", ".join(parts), float(runs[0]["prim"])])
	print("===================================================")
