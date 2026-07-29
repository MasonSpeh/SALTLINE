extends Node
## DOES DECIMATION CHANGE HOW THE ANIMALS MOVE? A behaviour probe, not a perf probe.
##
## AiBudget runs distant and hidden creatures on every 2nd or 4th frame. The whole design
## rests on one claim — that handing a creature the delta it missed leaves its speed
## untouched — and that claim is exactly the kind that looks true and is not. Godot passes
## `_process` the FRAME delta, so the naive version of this optimisation quietly runs every
## decimated animal at a quarter speed: the shark still patrols, the crab still emerges, the
## snail still crawls, all of them wrong, none of them broken enough to notice from a
## screenshot.
##
## So this measures it. Same world, same vantage, same creatures, back to back:
##   A. AiBudget.enabled = false — every creature ticks every frame (the old behaviour)
##   B. AiBudget.enabled = true  — decimation live
## and compares, per species:
##   * CLOCK RATE — d(_t)/d(wall). Every decimated body derives its motion from its own
##     accumulated `_t`, so this is the single number the frame-skip bug corrupts: it reads
##     1.00 when the delta is conserved and 0.25 when it is not.
##   * PATH SPEED — metres of travel per second of wall clock, measured off the real
##     global_position. The physical cross-check: a clock can be right while the body is
##     not moving with it.
##
## Both must agree between A and B inside TOL. Run WINDOWED — decimation keys off the
## camera, and `--headless` has no camera and no visibility to test against:
##   godot --path . res://tests/AiBudgetProbe.tscn

const WARMUP_SEC: float = 33.0
## Long enough that the SPEED column's noise floor is real. At 24 s the seal's haul-out coin
## flip (every 35-70 s) landed the same way in both undecimated windows, so the row published
## a noise of 0.18 m/s while its true run-to-run spread is over 1 — and then flagged itself.
## 45 s windows cover at least one haul cycle each, which is what makes |A1 - A2| an honest
## measurement of how much this animal varies on its own rather than a lucky pair.
const WINDOW_SEC: float = 45.0
## THE INVARIANT, and the thing the frame-skip bug destroys: seconds of the animal's own
## clock per second of wall clock. Conserving the delta makes this exactly 1.00; skipping
## frames without conserving it makes it 1/stride. 1% is as tight as the two windows allow.
const TOL_CLOCK: float = 0.01
## The physical cross-check. Looser on purpose — mean path speed over two DIFFERENT windows
## of a wandering animal genuinely differs — but nowhere near loose enough to hide the
## failure this exists to catch, which is a 50-75% speed loss.
const TOL_SPEED: float = 0.12
## A per-frame step longer than this is a TELEPORT, not travel: the mantle ray and the whale
## begin each flyover 180 m out. Counting those as distance made one row read 14,580 m/s.
const TELEPORT_M: float = 2.0

## Underwater, so the schools and the deep giants are live and measurable. Far enough out
## that most of them fall past AiBudget.MID_M and are genuinely being decimated.
const EYE := Vector3(0.0, -5.0, -16.0)
const LOOK := Vector3(0.0, -6.0, -34.0)

enum Phase { WARMUP, RUN_A1, RUN_B, RUN_A2, DONE }

var _phase: int = Phase.WARMUP
var _t: float = 0.0
var _win: float = 0.0
var _main: Node
var _uw: Node
var _cam: Camera3D
var _tracked: Array = []          ## [{node, label}]
var _a1: Dictionary = {}
var _b: Dictionary = {}
var _a2: Dictionary = {}
var _start_t: Dictionary = {}
var _start_p: Dictionary = {}
var _path: Dictionary = {}
var _last_p: Dictionary = {}
var _strides: Dictionary = {}     ## label -> max stride seen in run B

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	print("[aibudget] warming up %.0f s…" % WARMUP_SEC)

func _label(n: Node) -> String:
	var s: Script = n.get_script()
	return s.resource_path.get_file().get_basename() if s != null else str(n.get_class())

## Inner classes (LampSnail, GliderRay, Nudibranch, …) have no resource_path, so the obvious
## `get_script().resource_path.get_file()` labels every one of them "" and collapses 26
## species into one row — which is how the first run of this probe reported two nameless
## species and proved nothing. The outer script exposes its inner classes as script
## constants, so build Script -> name from there.
func _species_names() -> Dictionary:
	var out: Dictionary = {}
	for path in ["res://scripts/world/bloom_fauna.gd", "res://scripts/world/reef_life.gd",
			"res://scripts/world/underwater_world.gd"]:
		var sc: GDScript = load(path)
		if sc == null:
			continue
		var consts: Dictionary = sc.get_script_constant_map()
		for k in consts:
			if consts[k] is GDScript:
				out[consts[k]] = String(k)
	return out

## Every node in the tree that carries an `_ai_acc` — i.e. everything this change decimated.
func _collect() -> void:
	var names: Dictionary = _species_names()
	var by_kind: Dictionary = {}
	var stack: Array = [_main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is Node3D) or n.get_script() == null:
			continue
		var props: Array = n.get_property_list()
		var has_acc: bool = false
		var has_t: bool = false
		for p in props:
			if p["name"] == "_ai_acc":
				has_acc = true
			elif p["name"] == "_t":
				has_t = true
		if not has_acc:
			continue
		if not has_t:
			# A decimated class with no `_t` of its own (the furl star runs purely on lerps
			# toward a day/night target). No clock to compare — its row reports speed only.
			pass
		# One representative per species is enough and keeps the table readable; the class
		# is what was edited, not the instance.
		var sc: Variant = n.get_script()
		var k: String = String(names.get(sc, _label(n)))
		if k == "":
			k = str(n.get_class())
		if by_kind.has(k):
			continue
		by_kind[k] = true
		_tracked.append({"node": n, "label": k})
	print("[aibudget] tracking %d decimated species: %s"
		% [_tracked.size(), ", ".join(_tracked.map(func(x): return x["label"]))])

func _setup() -> void:
	GameClock.force_phase(GameClock.Phase.NIGHT)   # the reef life's state machines awake
	for n in get_tree().root.get_children():
		if str(n.name) == "GameClock":
			n.process_mode = Node.PROCESS_MODE_DISABLED
	var storm: Node = _main.get("storm")
	if storm != null and is_instance_valid(storm):
		storm.process_mode = Node.PROCESS_MODE_DISABLED
	var player: Node3D = get_tree().get_first_node_in_group("player")
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = EYE - Vector3(0, 1.6, 0)
	_cam = player.get_node("Head/Camera3D")
	_cam.current = true
	_cam.global_position = EYE
	_cam.look_at(LOOK, Vector3.UP)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	for c in _main.get_children():
		if _label(c) == "underwater_world":
			_uw = c
	_collect()

func _open_window() -> void:
	_win = 0.0
	_start_t.clear()
	_start_p.clear()
	_path.clear()
	_last_p.clear()
	for e in _tracked:
		var n: Node3D = e["node"]
		var tv: Variant = n.get("_t")
		_start_t[e["label"]] = float(tv) if tv != null else NAN
		_start_p[e["label"]] = n.global_position
		_last_p[e["label"]] = n.global_position
		_path[e["label"]] = 0.0
	# The pods keep their clock on a dictionary, not a node.
	if _uw != null:
		var sc: Array = _uw.get("_schools")
		for i in range(sc.size()):
			_start_t["pod%d" % i] = float((sc[i] as Dictionary)["t"])

func _close_window(into: Dictionary) -> void:
	for e in _tracked:
		var l: String = e["label"]
		var n: Node3D = e["node"]
		var tv: Variant = n.get("_t")
		var clock: float = ((float(tv) - float(_start_t[l])) / _win) if tv != null else 1.0
		into[l] = {"clock": clock, "speed": float(_path[l]) / _win}
	if _uw != null:
		# ACTIVE pods only. A shoal outside its species' hours never advances its clock at
		# all — that is pre-existing behaviour, not decimation — and averaging the dormant
		# ones in drags the mean to ~0.5 and hides what is being measured.
		var sc: Array = _uw.get("_schools")
		var acc: float = 0.0
		var live: int = 0
		for i in range(sc.size()):
			var r: float = (float((sc[i] as Dictionary)["t"]) - float(_start_t["pod%d" % i])) / _win
			if r > 0.5:
				acc += r
				live += 1
		into["SCHOOL PODS (mean of %d live)" % live] = {"clock": acc / maxf(float(live), 1.0), "speed": -1.0}

func _sample(delta: float) -> void:
	_win += delta
	for e in _tracked:
		var l: String = e["label"]
		var n: Node3D = e["node"]
		var p: Vector3 = n.global_position
		var d: float = p.distance_to(_last_p[l])
		# A teleport is not travel — see TELEPORT_M.
		if d <= TELEPORT_M:
			_path[l] = float(_path[l]) + d
		_last_p[l] = p
		if _phase == Phase.RUN_B:
			var st: int = AiBudget.stride(n)
			_strides[l] = maxi(int(_strides.get(l, 1)), st)

func _process(delta: float) -> void:
	if get_tree().paused:
		get_tree().paused = false
	match _phase:
		Phase.WARMUP:
			_t += delta
			if _t < WARMUP_SEC:
				return
			_setup()
			AiBudget.enabled = false
			print("[aibudget] A1 (decimation OFF) %.0f s…" % WINDOW_SEC)
			_phase = Phase.RUN_A1
			_open_window()
		Phase.RUN_A1:
			_sample(delta)
			if _win < WINDOW_SEC:
				return
			_close_window(_a1)
			AiBudget.enabled = true
			print("[aibudget] B  (decimation ON)  %.0f s…" % WINDOW_SEC)
			_phase = Phase.RUN_B
			_open_window()
		Phase.RUN_B:
			_sample(delta)
			if _win < WINDOW_SEC:
				return
			_close_window(_b)
			AiBudget.enabled = false
			print("[aibudget] A2 (decimation OFF) %.0f s…" % WINDOW_SEC)
			_phase = Phase.RUN_A2
			_open_window()
		Phase.RUN_A2:
			_sample(delta)
			if _win < WINDOW_SEC:
				return
			_close_window(_a2)
			AiBudget.enabled = true
			_report()
		Phase.DONE:
			pass

func _report() -> void:
	_phase = Phase.DONE
	var fails: int = 0
	print("\n\n=========== AI DECIMATION — BEHAVIOUR A/B/A ===========")
	print("A1 (off) / B (on) / A2 (off), not a single A-vs-B pair, because a pair cannot tell")
	print("decimation apart from the world moving on: the seal decides at random every")
	print("35-70 s whether to haul out, the gulls leave at dusk, and the anglerfish's circuit")
	print("is 140 s long against a %.0f s window. Each row prints the spread between its own" % WINDOW_SEC)
	print("two UNDECIMATED windows as its noise floor — a difference smaller than that figure")
	print("is the animal living its life, not the optimisation.")
	print("")
	print("clock = seconds of the creature's own _t per second of wall clock. THIS is the")
	print("  invariant the frame-skip trap destroys: conserve the delta and it reads 1.00,")
	print("  skip frames without conserving it and it reads 1/stride. Every decimated body")
	print("  derives its motion from _t, so a conserved clock IS an unchanged trajectory.")
	print("speed = metres actually travelled per second — the physical cross-check.")
	print("")
	print("%-24s %5s %7s %7s %7s   %8s %8s %8s"
		% ["species", "strid", "clkA", "clkB", "clkNoi", "spdA", "spdB", "spdNoise"])
	for k in _a1:
		var ca: float = 0.5 * (float(_a1[k]["clock"]) + float(_a2[k]["clock"]))
		var cb: float = float(_b[k]["clock"])
		var cn: float = absf(float(_a1[k]["clock"]) - float(_a2[k]["clock"]))
		var sa: float = 0.5 * (float(_a1[k]["speed"]) + float(_a2[k]["speed"]))
		var sb: float = float(_b[k]["speed"])
		var sn: float = absf(float(_a1[k]["speed"]) - float(_a2[k]["speed"]))
		var cbad: bool = absf(cb - ca) > maxf(TOL_CLOCK * maxf(ca, 0.01), cn)
		var sbad: bool = sa > 0.02 and absf(sb - sa) > maxf(TOL_SPEED * sa, sn)
		if cbad or sbad:
			fails += 1
		print("%s %-22s %5d %7.3f %7.3f %7.3f   %8.4f %8.4f %8.4f%s"
			% ["!!" if (cbad or sbad) else "  ", k, int(_strides.get(k, 1)),
				ca, cb, cn, sa, sb, sn,
				("  <-clock" if cbad else "") + ("  <-speed" if sbad else "")])
	print("\nA stride of 1 everywhere would mean nothing was actually decimated at this")
	print("vantage and the comparison proved nothing — read the stride column first.")
	print("FAILURES: %d  (clock: %.0f%% or the row's own noise; speed: %.0f%% or its own noise)"
		% [fails, TOL_CLOCK * 100.0, TOL_SPEED * 100.0])
	print("======================================================\n")
	get_tree().quit(1 if fails > 0 else 0)
