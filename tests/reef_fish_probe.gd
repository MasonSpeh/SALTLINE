extends Node3D
## DO THE REEF FISH LIVE WHERE THEY SHOULD, AND WHAT DO THEY COST?
##
## Two jobs in one launch, because relaunching Godot lags the owner's machine and both need
## the same fully-built world:
##
##   1. CORRECTNESS. Re-derives, from the LIVE tree, everything reef_fish.gd claims: that no
##      fish is inside a caisson or inside the pontoon slab, that every fish stays inside its
##      station's home range instead of wandering off like a pelagic shoal, that the stations
##      really are on the coral, and that nothing is NaN.
##   2. COST. The fish_perf.gd methodology, applied to this population: frame TIME with vsync
##      off, interleaved on/off pairs reported as a median with the spread, and a null pair
##      first so the machine's own noise floor is published next to the answer.
##
## Run WINDOWED. --headless never draws, so every renderer counter reads zero and the frame
## time is meaningless.
##     godot --path . res://tests/ReefFishProbe.tscn
##
## WHY THE CULL IS DISABLED FOR THE CORRECTNESS HALF: reef_fish freezes a station that is
## past its own draw range, so a probe that just watched from one spot would certify 40
## stations that never moved. Every station's cull radius is opened up and AiBudget switched
## off for the swim window, then both are put back before the cost half runs — measuring the
## decimated cost is the whole point of the cost half.

const SWIM_SECONDS: float = 26.0
const SAMPLE_HZ: float = 6.0
## fish_perf.gd's numbers, same reasons.
const REPEATS: int = 7
const SETTLE: float = 0.45
const WINDOW: float = 1.8
## Verified by sonar and re-checked by ReefProbe every run.
const LEG_HALF: float = 3.0
const LEGS := [Vector2(-22, -12), Vector2(22, -12), Vector2(-22, 12), Vector2(22, 12)]
## The pontoon skirt: underside y -3.05, slab top y 0.95, plan x[-28,28], |z| in [8,16].
const SKIRT := {"lo": -3.05, "hi": 0.95, "x": 28.0, "z_in": 8.0, "z_out": 16.0}

## Where the cost is measured. The two that decide it are the ones a player is actually at.
const SPOTS := [
	# On deck. The topside cull hides the whole underwater subtree, so the expected answer
	# is exactly zero — which is worth measuring because it is where the game is played.
	["deck_horizon", Vector3(0.0, 26.0, 0.0), Vector3(120.0, 8.0, 120.0)],
	# In the water at the top of the shallow band, right among the clownfish and damsels.
	["shallow_leg", Vector3(27.5, -6.0, -12.0), Vector3(22.0, -7.0, -12.0)],
	# Down on the coral band, the anthias/angelfish depth.
	["coral_band", Vector3(28.0, -15.0, -12.0), Vector3(22.0, -15.5, -12.0)],
	# Off the corner looking back along two legs — the most stations that can be live at once.
	["two_legs", Vector3(34.0, -10.0, 0.0), Vector3(0.0, -12.0, -6.0)],
]

var _main: Node3D
var _rf: Node3D
var _stash: Array = []
var _fail: int = 0

func _process(_d: float) -> void:
	# A focus-out pause freezes the world and still renders: beautiful, stable, meaningless.
	if get_tree().paused:
		get_tree().paused = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_main = load("res://scenes/Main.tscn").instantiate()
	# A GDScript parse error anywhere in the world graph hands back a bare Node with its
	# script dropped: it builds nothing and every assertion below passes vacuously.
	if _main.get_script() == null:
		print("[reeffish] Main.tscn instantiated WITHOUT its script — aborting, nothing here "
			+ "would be a real measurement")
		get_tree().quit(1)
		return
	add_child(_main)
	# The dressing streams in and render_budget sweeps behind it; leg_reef then awaits physics
	# frames before it grows anything and reef_fish is built after that.
	await get_tree().create_timer(28.0).timeout
	var player: Node3D = get_tree().get_first_node_in_group("player")
	player.set_physics_process(false)
	player.set_process(false)
	# Fauna hunts the "player" group; a lens left in it gets followed.
	player.remove_from_group("player")
	var cam: Camera3D = player.get_node("Head/Camera3D")
	cam.current = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	_main.storm.set_process(false)
	GameClock.force_phase(GameClock.Phase.DAY)

	_rf = _by_script(_main, "reef_fish.gd")
	if _rf == null:
		print("[reeffish] FAIL: no ReefFish node in the tree")
		get_tree().quit(1)
		return
	await _correctness(player, cam)
	await _cost(player, cam)
	print("\n[reeffish] FAILURES: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

# ------------------------------------------------------------ correctness

func _correctness(player: Node3D, cam: Camera3D) -> void:
	var stations: Array = _rf.get("_stations")
	print("\n=== reef fish: what got built ===")
	var total: int = 0
	for st in stations:
		total += (st["fish"] as Array).size()
	print("  %d stations, %d fish" % [stations.size(), total])
	if stations.is_empty():
		print("  FAIL: nothing built")
		_fail += 1
		return
	# Open every station up and stop the decimation, so all of them are actually simulated
	# for the window instead of frozen at their spawn pose.
	var stash_cull: Array = []
	for st in stations:
		stash_cull.append(st["cull2"])
		st["cull2"] = 1.0e12
	var was_budget: bool = AiBudget.enabled
	AiBudget.enabled = false
	# Park the camera far enough off that nothing is alarmed — the home-range test is about
	# the resting behaviour, and the startle response is checked separately below.
	player.global_position = Vector3(0.0, -13.0, 0.0)
	cam.global_position = Vector3(0.0, -13.0, 0.0)

	# Worst case per station over the whole window, sampled rather than taken once: a fish
	# that only leaves home at one phase of its wander would pass a single snapshot.
	var drift: Dictionary = {}      # slug -> max distance from its station's wall seat
	var clear: float = 1.0e9        # min clearance outside any caisson
	var in_slab: int = 0
	var nan_n: int = 0
	var depth_lo: float = 1.0e9
	var depth_hi: float = -1.0e9
	var samples: int = 0
	var t0: float = Time.get_ticks_msec() / 1000.0
	while (Time.get_ticks_msec() / 1000.0) - t0 < SWIM_SECONDS:
		await get_tree().create_timer(1.0 / SAMPLE_HZ).timeout
		samples += 1
		for s in _rf.call("census"):
			var slug: String = s["slug"]
			var wall: Vector3 = s["wall"]
			for p in s["fish"]:
				var q: Vector3 = p
				if not (is_finite(q.x) and is_finite(q.y) and is_finite(q.z)):
					nan_n += 1
					continue
				drift[slug] = maxf(float(drift.get(slug, 0.0)), wall.distance_to(q))
				clear = minf(clear, _leg_clearance(q))
				if _in_slab(q):
					in_slab += 1
				depth_lo = minf(depth_lo, q.y)
				depth_hi = maxf(depth_hi, q.y)
		samples += 0
	print("  %d samples over %.0f s" % [samples, SWIM_SECONDS])

	# 1. NOT INSIDE A CAISSON. The clearance is the Chebyshev distance out from the nearest
	#    leg centre line minus the half-width, so a positive number is metres of open water
	#    between the fish and the concrete.
	if clear > 0.02:
		print("  PASS  caisson clearance: closest fish sat %.3f m clear of the concrete" % clear)
	else:
		print("  FAIL  caisson clearance %.3f m — a fish was inside a leg" % clear)
		_fail += 1
	# 2. NOT INSIDE THE PONTOON SLAB.
	if in_slab == 0:
		print("  PASS  pontoon slab: 0 fish-samples inside it")
	else:
		print("  FAIL  %d fish-samples inside the pontoon slab" % in_slab)
		_fail += 1
	# 3. NO NaN. A single NaN frame becomes a permanently lost animal (docs/AGENT_TRAPS.md).
	if nan_n == 0:
		print("  PASS  no non-finite positions")
	else:
		print("  FAIL  %d non-finite positions" % nan_n)
		_fail += 1
	# 4. HOME RANGE. This is the behavioural claim of the whole file — a reef fish has an
	#    address. The bound is what the station's own numbers allow: the wander reaches
	#    1.8x `rad` along the wall and 1.8x `vrt` up it, plus the standoff out from the
	#    concrete, plus a metre of easing slack.
	print("  home range (max distance any fish got from its station's seat on the wall):")
	var roam_fail: int = 0
	for st in stations:
		var sp: Dictionary = st["sp"]
		var slug: String = sp["slug"]
		if not drift.has(slug):
			continue
		var bound: float = sqrt(pow(1.8 * float(sp["rad"]), 2.0) + pow(1.8 * float(sp["vrt"]), 2.0)
			+ pow(float(sp["stand"]) * 1.3 + MINSTAND, 2.0)) + 1.0
		var got: float = float(drift[slug])
		var ok: bool = got <= bound
		if not ok:
			roam_fail += 1
		print("    %-18s %5.2f m  (allowed %5.2f)  %s" % [slug, got, bound, "ok" if ok else "OUT"])
		drift.erase(slug)
	if roam_fail == 0:
		print("  PASS  every species stayed inside its own home range")
	else:
		print("  FAIL  %d species roamed past their home range" % roam_fail)
		_fail += 1
	print("  depth spread: y %.1f .. %.1f" % [depth_hi, depth_lo])

	# 5. THE STATIONS ARE ON THE REEF. Every seat should be exactly on a caisson face, which
	#    is the surface leg_reef grows coral on and underwater_world encrusts with growth.
	var off_face: int = 0
	for st in stations:
		if absf(_leg_chebyshev(st["wall"]) - LEG_HALF) > 0.25:
			off_face += 1
	if off_face == 0:
		print("  PASS  all %d station seats are on a caisson face (3.00 m from its centre line)"
			% stations.size())
	else:
		print("  FAIL  %d station seats are not on a face" % off_face)
		_fail += 1

	# 6. THE STARTLE RESPONSE ACTUALLY FIRES. Swim the camera into a shoal and check it moves
	#    toward its wall — this is the behaviour the brief asked for by name and the one thing
	#    a static census can never see.
	var probe_st: Dictionary = {}
	for st in stations:
		if String(st["sp"]["slug"]) == "trop_damsel":
			probe_st = st
			break
	if not probe_st.is_empty():
		var before: float = _mean_standoff(probe_st)
		var c: Vector3 = probe_st["centre"]
		player.global_position = c + (probe_st["out"] as Vector3) * 1.6
		cam.global_position = player.global_position
		await get_tree().create_timer(3.0).timeout
		var after: float = _mean_standoff(probe_st)
		if after < before - 0.05:
			print("  PASS  startle: the damsel shoal pulled in from %.2f m off the wall to %.2f m"
				% [before, after])
		else:
			print("  FAIL  startle: shoal did not duck (%.2f m -> %.2f m)" % [before, after])
			_fail += 1

	# 7. EVERY FISH IN A SHOAL IS FACED THE SAME WAY.
	#    Only the first fish on each phase variant is built by CreatureAnim.attach; every other
	#    one goes through reef_fish._skin, which loads the mesh and re-applies the authored
	#    facing BY HAND so it can share the materials. If those two ever disagree, two thirds of
	#    every shoal swims backwards — and no still frame can show it, which is exactly how a
	#    hammerhead shipped swimming broadside (docs/AGENT_TRAPS.md). Checked against the
	#    FACING table rather than against the first fish, so it also catches both paths being
	#    wrong together.
	var face_bad: int = 0
	var checked: int = 0
	for st in stations:
		var slug: String = st["sp"]["slug"]
		var want: Dictionary = CreatureAnim.facing_for("res://x/%s.glb" % slug)
		var want_rot := Vector3(deg_to_rad(want["pitch"]), deg_to_rad(want["yaw"]), 0.0)
		for f in st["fish"]:
			for c in (f as Node3D).get_children():
				var model := c as Node3D
				if model == null:
					continue
				checked += 1
				if model.rotation.distance_to(want_rot) > 0.001:
					face_bad += 1
	if face_bad == 0:
		print("  PASS  facing: all %d fish models carry the authored rotation (attach and _skin agree)"
			% checked)
	else:
		print("  FAIL  facing: %d of %d fish models are rotated wrongly" % [face_bad, checked])
		_fail += 1

	for i in range(stations.size()):
		stations[i]["cull2"] = stash_cull[i]
	AiBudget.enabled = was_budget

const MINSTAND: float = 0.45

func _mean_standoff(st: Dictionary) -> float:
	var wall: Vector3 = st["wall"]
	var out_ax: Vector3 = st["out"]
	var acc: float = 0.0
	var n: int = 0
	for f in st["fish"]:
		acc += (f as Node3D).global_position.distance_to(wall) * 1.0
		n += 1
	return acc / maxf(float(n), 1.0)

## Chebyshev distance out from the nearest leg's centre line, metres.
func _leg_chebyshev(p: Vector3) -> float:
	var best: float = 1.0e9
	for leg in LEGS:
		best = minf(best, maxf(absf(p.x - leg.x), absf(p.z - leg.y)))
	return best

func _leg_clearance(p: Vector3) -> float:
	return _leg_chebyshev(p) - LEG_HALF

func _in_slab(p: Vector3) -> bool:
	return p.y > SKIRT["lo"] and p.y < SKIRT["hi"] and absf(p.x) < SKIRT["x"] \
		and absf(p.z) > SKIRT["z_in"] and absf(p.z) < SKIRT["z_out"]

# ------------------------------------------------------------ cost

## What removing exactly these fish buys back. Taking `_stations` away removes them from the
## CPU (the swim loop iterates it) and, with the roots hidden, from the GPU too — and nothing
## else in the world changes, which is the difference between an attribution and a guess.
func _cost(player: Node3D, cam: Camera3D) -> void:
	print("\n=== reef fish: what they cost (vsync off, median of %d interleaved pairs) ===" % REPEATS)
	var fish: int = 0
	for st in (_rf.get("_stations") as Array):
		fish += (st["fish"] as Array).size()
	for sp in SPOTS:
		player.global_position = sp[1]
		cam.global_position = sp[1]
		cam.look_at(sp[2], Vector3.UP)
		await get_tree().create_timer(1.2).timeout
		var live: int = 0
		var live_st: int = 0
		for st in (_rf.get("_stations") as Array):
			# is_visible_in_tree, NOT the root's own `visible` flag. Topside, underwater_world
			# hides the whole subtree and reef_fish._process returns before it ever touches a
			# station root — so the flag still reads true while nothing is drawn or simulated.
			# The first pass of this harness reported "42/42 stations live" on deck because of it.
			if (st["root"] as Node3D).is_visible_in_tree():
				live_st += 1
				live += (st["fish"] as Array).size()
		var abs_s: Array = await _sample()
		print("  %-13s frame %6.2f ms  %d tris  %d draws   |  %d/%d stations live (%d/%d fish)"
			% [sp[0], abs_s[0], int(abs_s[2]), int(abs_s[3]), live_st,
				(_rf.get("_stations") as Array).size(), live, fish])
		await _paired(sp[0] + " NOISE FLOOR", func(_on: bool) -> void: pass)
		await _paired(sp[0] + " reef fish", _toggle)
		if (_rf.get("_stations") as Array).is_empty():
			print("     !! stations not restored — the line above is two identical fishless frames")

func _toggle(on: bool) -> void:
	# Idempotent: _paired calls this ON at the top of every repeat as well as after it, so a
	# naive restore hands back an empty stash and deletes the fish for the rest of the run.
	if on:
		if _stash.is_empty():
			return
		_rf.set("_stations", _stash)
		_stash = []
		return
	if not _stash.is_empty():
		return
	_stash = _rf.get("_stations")
	for st in _stash:
		(st["root"] as Node3D).visible = false
	_rf.set("_stations", [])

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
	print("  %-28s %+6.2f ms  (proc %+5.2f ms)  spread %+.2f..%+.2f  |  %+d tris  %+d draws"
		% [label, d_ms[mid], d_proc[mid], d_ms[0], d_ms[REPEATS - 1],
			int(d_tri[mid]), int(d_draw[mid])])

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
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var s: Script = n.get_script()
		if s != null and String(s.resource_path).ends_with(tail):
			return n as Node3D
	return null
