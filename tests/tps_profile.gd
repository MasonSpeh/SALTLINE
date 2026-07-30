extends Node
## TPS / FRAME PROFILER — ranks what actually costs us, by A/B/A measurement.
##
## Performance monitors give TOTALS, not attribution: "_process is 44 ms" doesn't say which
## of forty subsystems spent it. So measure it: switch ONE subsystem off, measure, switch it
## back. Two independent sweeps —
##   SCRIPT sweep : process_mode = DISABLED   (stops ticking, still drawn)
##   RENDER sweep : visible = false           (stops drawing, still ticking)
## — so "expensive to think about" is separated from "expensive to draw".
##
## THREE THINGS THE FIRST VERSION GOT WRONG, all of which produced confident nonsense
## (disabling PowerGrid, which does nothing per frame, "saved" -1.66 ms):
##
##  1. ONE BASELINE FOR THE WHOLE RUN. Frame time drifts as the world runs — the sun moves,
##     shadow cascades change, squalls arrive, fauna swim in and out of frame. Every sample
##     was compared against a baseline measured a minute earlier, so the table was ranking
##     drift. Now each target is measured ON / OFF / ON and the cost is the mean of the two
##     ON windows minus the OFF window, which cancels slow drift.
##  2. MEAN OF FRAME TIMES. One 250 ms hitch swamps a 45-frame mean. Now the MEDIAN.
##  3. TESTING NODES THAT CANNOT HAVE SCRIPT COST. A DirectionalLight3D has no script, so
##     "disabling" it can only measure noise — yet it ranked third. The script sweep now
##     only tests nodes that actually carry a script (plus autoloads).
##
## The world is also FROZEN for the run: GameClock and the storm are parked so lighting and
## weather cannot change underneath the measurement. Both are then measured on their own.
##
## VSYNC IS FORCED OFF — with it on every sample pins to the refresh interval.
##
## Run WINDOWED (rendering monitors read 0 headless), and IN THE FOREGROUND (a windowed
## Godot backgrounded on macOS reports FROZEN renderer counters — see docs/AGENT_TRAPS.md):
##   godot --path . res://tests/tps_profile.tscn
##
## ---------------------------------------------------------------------------------------
## SPECIES MODE (s23) — `--species`
##
## The subsystem table has said "bloom_fauna's per-frame GDScript is 4.5-6.1 ms" at every
## vantage for three sessions without ever naming WHICH of its ~27 species spent it. The DRILL
## below was meant to answer that and cannot, for two reasons that are both about the toggle:
##
##  1. IT GROUPS BY `_label()`, which reads `get_script().resource_path` — and an inner class
##     of bloom_fauna.gd has an EMPTY resource_path. Every one of the twenty-odd inner-class
##     species therefore fell into the `"(no script) Node3D"` bucket together, i.e. the drill
##     measured "all of bloom_fauna" a second time and called it a breakdown. Species mode
##     keys on the SCRIPT OBJECT ITSELF (one GDScript instance per inner class, shared by
##     every instance of it) and gets the readable name out of the host script's
##     `get_script_constant_map()`, where inner classes are registered by name.
##  2. IT TOGGLES `process_mode`, WHICH PROPAGATES TO CHILDREN. A parent species with scripted
##     children is then charged for its children too, and the children's own rows double-count
##     it. Species mode calls `set_process(false)` / `set_physics_process(false)` on exactly
##     the nodes in the group, which does NOT propagate — so the rows are additive.
##
## It also parks the camera at a real vantage (default the Wet Deck standing eye, which
## KNOWN_ISSUES records as the heaviest frame in the game) instead of profiling from wherever
## the player happens to spawn, because AiBudget decimates by DISTANCE TO THE EYE: a species
## measured from inside the SPHL pod is being measured at a stride the player never sees.
##
## Null pairs are interleaved through the job list (`--species` inserts one every NULL_EVERY
## jobs) rather than run once at the start: the honest noise floor for a job in the middle of
## a four-minute run is measured in the middle of a four-minute run.
##
##   godot --path . res://tests/tps_profile.tscn -- --species
##   godot --path . res://tests/tps_profile.tscn -- --species --vantage=submerged_deep

var WARMUP_SEC: float = 32.0       ## past render_budget's 8 streaming sweeps
var SETTLE_FRAMES: int = 10
var SAMPLE_FRAMES: int = 31        ## odd, so the median is a real sample

## WHY SPECIES MODE BRACKETS THE SCRIPT STEP WITH ITS OWN MICROSECOND TIMERS.
##
## TWO instruments were tried before this one and both produced full, plausible, wrong tables.
##
## 1. THE FRAME DELTA — what every other row in this harness uses. It cannot see a species.
##    The delta on this machine is quantised at ~0.2 ms and drifts ~0.8 ms over a four-minute
##    run, so the eleven interleaved NULL PAIRS — which toggle nothing at all — came back at a
##    median 0.40 ms and a worst 0.93 ms. bloom_fauna's whole per-frame GDScript is 4.5-6.1 ms
##    spread across ~20 species, i.e. about 0.25 ms each: the entire quantity being measured
##    sits UNDER the floor of the instrument. Six rows "beat" that floor and three of them were
##    animals 85-104 m away that cannot cost anything at this vantage. The table was ranking
##    drift — precisely the mistake this file's own header says the first version made.
##
## 2. `Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS`. This looks like the right monitor and
##    is not: Godot updates those two ONCE PER SECOND and stores the MAXIMUM over that second,
##    not a per-frame value. Inside a 51-frame window they take one or two distinct values, both
##    of them spikes. The tell was unmissable once printed — a "script step" of 33.26 ms inside
##    a 29.23 ms frame, a null-pair floor of 8.98 ms, and a species measured at -219% — but a
##    quieter version of the same error would have read as a result.
##
## What actually works is bracketing: two `Bracket` nodes, one forced to the FIRST child of the
## scene root and one to the LAST, each reading `Time.get_ticks_usec()`. Processing is
## depth-first in tree order, so the difference between them is the wall time the engine spent
## in the whole idle `_process` pass — autoloads, the world, everything — at microsecond
## resolution, every single frame. The same pair brackets `_physics_process`. That is the number
## a species' `_process` is actually part of, and its null floor is two orders of magnitude
## below the frame delta's.
##
## Frame delta is still sampled and still printed, because "did the frame get cheaper" is the
## question that matters and script time is only the evidence for it.
var SPECIES_SETTLE: int = 8
var SPECIES_FRAMES: int = 51

## Bracket markers. Two instances: one is forced to be the first-processed node in the tree and
## one the last, and the pair measures the idle and physics script passes end to end.
class Bracket extends Node:
	var other: Bracket = null      ## set on the LAST marker only; points at the FIRST
	var t_proc0: int = 0
	var t_phys0: int = 0
	var proc_us: int = 0           ## duration of the most recent complete idle pass
	var phys_us: int = 0           ## physics time that ran immediately before this idle pass
	var _phys_acc: int = 0

	func _init(is_first: bool, first: Bracket = null) -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		if not is_first:
			other = first

	func _process(_d: float) -> void:
		if other == null:
			# FIRST: open the idle bracket, and publish the physics time banked since the last
			# idle pass (Godot runs 0-2 physics ticks per rendered frame, before the idle step).
			phys_us = _phys_acc
			_phys_acc = 0
			t_proc0 = Time.get_ticks_usec()
		else:
			other.proc_us = Time.get_ticks_usec() - other.t_proc0

	func _physics_process(_d: float) -> void:
		if other == null:
			t_phys0 = Time.get_ticks_usec()
		else:
			other._phys_acc += Time.get_ticks_usec() - other.t_phys0
## Subsystems worth breaking down per-species after the top-level sweep.
const DRILL: Array = ["bloom_fauna", "underwater_world"]

## --species: per-species attribution instead of the subsystem/render/drill sweeps.
var SPECIES_MODE: bool = false
## Where the camera sits in species mode. AiBudget strides by distance to the EYE, so the
## vantage is part of the measurement, not scene-setting.
var VANTAGE: String = "wet_deck_stand"
## A null pair every this many species jobs — the noise floor, sampled throughout the run.
const NULL_EVERY: int = 6

## Eye + look-at, kept in sync with tests/vantage_perf.gd's SPOTS. The eye is the CAMERA
## position: the Wet Deck plating is y 2.0 and a standing eye is 1.6 m over the feet, so 3.6
## is where the player's head actually is — and underwater_world.TOPSIDE_MARGIN is 4.0, so
## 4.0 is the OTHER side of the topside cull and a different frame entirely.
const VANTAGES: Dictionary = {
	"wet_deck_stand": [Vector3(16.0, 3.6, -19.0), Vector3(13.0, 3.1, -12.0)],
	"wet_deck": [Vector3(16.0, 4.0, -19.0), Vector3(13.0, 3.5, -12.0)],
	"deck_floodlit": [Vector3(0.0, 20.0, -1.0), Vector3(14.0, 19.0, 7.0)],
	"pontoon_rail": [Vector3(-18.0, 2.6, -12.0), Vector3(-30.0, -1.0, -22.0)],
	"waterline": [Vector3(0.0, 1.1, -17.0), Vector3(0.0, -2.0, -34.0)],
	"submerged_mid": [Vector3(0.0, -5.0, -16.0), Vector3(0.0, -6.0, -34.0)],
	"submerged_deep": [Vector3(-8.0, -12.0, -6.0), Vector3(8.0, -13.0, 6.0)],
}

enum Phase { WARMUP, RUN, DONE }

var _phase: int = Phase.WARMUP
var _t: float = 0.0
var _main: Node
var _jobs: Array = []              ## [{name, node, mode:"script"|"render"}]
var _job: int = 0
var _step: int = 0                 ## 0 = ON(a1), 1 = OFF(b), 2 = ON(a2)
var _settle: int = 0
var _frames: Array = []
var _draws: Array = []
var _procs: Array = []             ## script ms, measured by the Bracket pair
var _b_first: Bracket = null
var _b_last: Bracket = null
var _win: Array = []               ## the three windows' medians for this job
var _win_draw: Array = []
var _win_proc: Array = []
var _base_proc: float = 0.0
var _rows: Array = []
var _baseline_ms: float = 0.0
var _baseline_draw: float = 0.0
var _player: Node3D = null
var _cam: Camera3D = null
var _pause_panel: CanvasItem = null
var _unpaused: int = 0
## script/class -> readable name, built from the host scripts' constant maps.
var _names: Dictionary = {}

func _args() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a == "--species":
			SPECIES_MODE = true
		elif a.begins_with("--vantage="):
			VANTAGE = a.split("=")[1]
		elif a.begins_with("--warmup="):
			WARMUP_SEC = float(a.split("=")[1])
		elif a.begins_with("--frames="):
			SAMPLE_FRAMES = maxi(3, int(a.split("=")[1]))

func _ready() -> void:
	# PROCESS_MODE_ALWAYS is not optional. pause_menu.gd auto-pauses on focus-out; this node
	# inherits PAUSABLE, so the instant that happens the harness stops processing and can never
	# un-pause the tree again — while the run completes over a FROZEN world and prints stable,
	# plausible, meaningless numbers. See docs/AGENT_TRAPS.md.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_args()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var m: Node = packed.instantiate()
	# ALWAYS above propagates to everything that inherits, i.e. the whole game. Put the world
	# back on the shipped mode so what is measured is the game as it runs.
	m.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(m)
	print("[tps] vsync=%d  refresh=%.1f Hz  window=%s  mode=%s"
		% [DisplayServer.window_get_vsync_mode(), DisplayServer.screen_get_refresh_rate(),
			str(DisplayServer.window_get_size()), "species" if SPECIES_MODE else "subsystem"])
	print("[tps] warming up %.0fs, then A/B/A per %s…"
		% [WARMUP_SEC, "species" if SPECIES_MODE else "subsystem"])
	# Deferred: adding to the scene root from inside a child's own _ready() lands while the
	# tree is still busy setting that child up.
	call_deferred("_install_brackets")

## Put one marker at the very front of the processing order and one at the very back. Node
## callbacks run depth-first in tree order, so root's first child is processed before every
## autoload and root's last child after the whole world.
func _install_brackets() -> void:
	var root: Window = get_tree().root
	_b_first = Bracket.new(true)
	root.add_child(_b_first)
	root.move_child(_b_first, 0)
	_b_last = Bracket.new(false, _b_first)
	root.add_child(_b_last)
	root.move_child(_b_last, root.get_child_count() - 1)

## Freeze anything that changes the scene's cost on its own while we measure.
func _freeze_world() -> void:
	for n in get_tree().root.get_children():
		if str(n.name) == "GameClock":
			n.process_mode = Node.PROCESS_MODE_DISABLED
	var storm: Node = _main.get("storm")
	if storm != null and is_instance_valid(storm):
		storm.process_mode = Node.PROCESS_MODE_DISABLED
	print("[tps] world frozen (clock + storm parked) so lighting/weather hold still")

## Park the camera at a named vantage and stop the player integrating away from it.
## Species mode only: the subsystem sweep has always measured from the spawn and its history
## is only comparable to itself.
func _place_camera() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_warning("[tps] no player; measuring from wherever the camera is")
		return
	_player.set_physics_process(false)
	_player.set_process(false)
	_cam = _player.get_node_or_null("Head/Camera3D") as Camera3D
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.set("visible", false)
	if not VANTAGES.has(VANTAGE):
		push_warning("[tps] unknown vantage '%s'; staying at spawn" % VANTAGE)
		return
	var v: Array = VANTAGES[VANTAGE]
	_player.global_position = (v[0] as Vector3) - Vector3(0.0, 1.6, 0.0)
	if _cam != null:
		_cam.current = true
		_cam.global_position = v[0]
		_cam.look_at(v[1], Vector3.UP)

## A readable identity: the SCRIPT is what tells you which subsystem this is — the node
## names are autogenerated (@Node3D@8019) because every subsystem is built in code.
func _label(n: Node) -> String:
	var s: Script = n.get_script()
	if s != null and s.resource_path != "":
		return s.resource_path.get_file().get_basename()
	return "%s(%s)" % [str(n.name), n.get_class()]

func _has_script_deep(n: Node, depth: int = 2) -> bool:
	if n.get_script() != null:
		return true
	if depth <= 0:
		return false
	for c in n.get_children():
		if _has_script_deep(c, depth - 1):
			return true
	return false

func _build_jobs() -> void:
	# Find Main EXPLICITLY by its script. An earlier version looked for the child with NO
	# script, which is backwards (Main carries main.gd), fell through to a guess, and
	# silently profiled nothing but the autoloads — 11 rows that all looked plausible.
	_main = get_child(0)
	for c in get_children():
		var s: Script = c.get_script()
		if s != null and String(s.resource_path).ends_with("main.gd"):
			_main = c
			break
	print("[tps] main scene = %s (%d children)" % [str(_main.name), _main.get_child_count()])
	if SPECIES_MODE:
		_build_species_jobs()
		return
	# SCRIPT sweep: autoloads + any child of Main that carries a script.
	for n in get_tree().root.get_children():
		if n == self or n is Window:
			continue
		_jobs.append({"name": "autoload/" + str(n.name), "node": n, "mode": "script"})
	for n in _main.get_children():
		if _has_script_deep(n):
			_jobs.append({"name": _label(n), "node": n, "mode": "script"})
	# RENDER sweep: every visible Node3D child of Main, plus the lights/env, since the
	# directional shadow pass is a prime suspect.
	for n in _main.get_children():
		if n is Node3D and (n as Node3D).visible:
			_jobs.append({"name": _label(n), "node": n, "mode": "render"})
	# DRILL: the subsystem-level table says "bloom_fauna costs 8 ms" without saying which of
	# its forty creatures spent it. Toggle each SPECIES (all instances of one script at once,
	# since there are six crabs and three snails) so the table names the actual offender.
	for parent_name in DRILL:
		for n in _main.get_children():
			if _label(n) != parent_name:
				continue
			var by_script: Dictionary = {}
			for c in n.get_children():
				# GROUP BY SCRIPT, and by CLASS when there is no script. _label() falls back to
				# "name(Class)" for a scriptless node, and every autogenerated name is unique —
				# so the 48 school-pod roots (plain Node3Ds) each became their own A/B/A job.
				# That is what took this harness from ~85 measurements to 341 and turned an
				# eight-minute run into an hour, which is long enough that the run gets killed
				# before it prints and the whole hour buys nothing. One bucket per KIND.
				var key: String = _label(c) if c.get_script() != null \
					else "(no script) " + c.get_class()
				if not by_script.has(key):
					by_script[key] = []
				(by_script[key] as Array).append(c)
			for key in by_script:
				var group: Array = by_script[key]
				_jobs.append({"name": "%s > %s x%d" % [parent_name, key, group.size()],
					"nodes": group, "mode": "drill"})

# ------------------------------------------------------------------ species mode

## Walk every script reachable from the tree and record the name each INNER CLASS is
## registered under in its host's constant map. This is the only way to name an inner class
## at runtime: `get_script()` on an inner-class instance returns a GDScript whose
## `resource_path` is empty and whose `get_global_name()` is empty, so the script object is a
## perfect grouping KEY and a useless label. The host script knows the name — `class Gull` is
## a script constant of bloom_fauna.gd called "Gull" — so read it from there.
func _index_names(s: Script, prefix: String, depth: int) -> void:
	if depth <= 0 or s == null or not (s is GDScript):
		return
	var consts: Dictionary = (s as GDScript).get_script_constant_map()
	for k in consts:
		var v: Variant = consts[k]
		if not (v is GDScript):
			continue
		var g: GDScript = v
		if _names.has(g):
			continue
		var path: String = String(g.resource_path)
		if path != "":
			# A preloaded sibling FILE, not an inner class — it names itself, but its own
			# inner classes still need indexing (fauna_move.gd's SurfaceCrawler, for one).
			_names[g] = path.get_file().get_basename()
			_index_names(g, path.get_file().get_basename(), depth - 1)
		else:
			_names[g] = "%s.%s" % [prefix, str(k)]
			_index_names(g, "%s.%s" % [prefix, str(k)], depth - 1)

## The nearest ancestor whose script is a FILE, i.e. which subsystem this node lives under.
func _host_of(n: Node) -> String:
	var p: Node = n.get_parent()
	while p != null and p != _main:
		var s: Script = p.get_script()
		if s != null and String(s.resource_path) != "":
			return String(s.resource_path).get_file().get_basename()
		p = p.get_parent()
	return "main"

func _build_species_jobs() -> void:
	# Pass 1: index names off every FILE script in the tree, so inner classes are labelled.
	var stack: Array = [_main]
	var seen_files: Dictionary = {}
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var s: Script = n.get_script()
		if s == null:
			continue
		var p: String = String(s.resource_path)
		if p == "" or seen_files.has(p):
			continue
		seen_files[p] = true
		_names[s] = p.get_file().get_basename()
		_index_names(s, p.get_file().get_basename(), 3)
	# Pass 2: collect every node that will actually receive a per-frame callback THIS frame.
	#
	# `is_processing()` rather than `has_method("_process")`: Godot turns processing on when a
	# script defines the virtual, and a node that has turned its own processing OFF costs
	# nothing and must not appear in a cost table as a zero.
	var groups: Dictionary = {}          # key (Script or String) -> [nodes]
	stack = [_main]
	while not stack.is_empty():
		var n2: Node = stack.pop_back()
		for c in n2.get_children():
			stack.append(c)
		if not (n2.is_processing() or n2.is_physics_processing()):
			continue
		var sc: Script = n2.get_script()
		var key: Variant = sc if sc != null else ("engine/" + n2.get_class())
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(n2)
	var species: Array = []
	for key in groups:
		var nodes: Array = groups[key]
		var nm: String = _names.get(key, "") if key is Script else String(key)
		if nm == "":
			# An inner class the constant-map walk did not reach (nested deeper than the walk,
			# or belonging to a script that is only reachable through a node the walk started
			# below). Name it by the nearest ANCESTOR that does have a file script, so the row
			# still says which subsystem it belongs to instead of "unnamed" twice on one page.
			nm = "%s.?%s" % [_host_of(nodes[0]), (nodes[0] as Node).get_class()]
		species.append({"name": nm, "nodes": nodes})
	# Biggest populations first — not because they must be dearest, but because a run that gets
	# killed early should have printed the rows most likely to matter.
	species.sort_custom(func(a, b): return (a["nodes"] as Array).size() > (b["nodes"] as Array).size())
	var n_null: int = 0
	# AGGREGATES first, so the sum of the individual rows can be checked against the whole. A
	# per-species table whose parts do not add up to the subsystem row is measuring something
	# other than what it says, and this is the cheapest way to notice.
	var agg_fauna: Array = []
	var agg_bloom: Array = []
	const FAUNA_HOSTS: Array[String] = ["bloom_fauna", "underwater_world", "leg_reef",
		"reef_fish", "reef_life", "crab", "king_crab", "shark", "gyre"]
	for s in species:
		var nm2: String = s["name"]
		if nm2.begins_with("bloom_fauna"):
			agg_bloom.append_array(s["nodes"])
		for h in FAUNA_HOSTS:
			if nm2 == h or nm2.begins_with(h + "."):
				agg_fauna.append_array(s["nodes"])
				break
	_jobs.append({"name": "(null pair %d)" % n_null, "nodes": [], "mode": "species"})
	n_null += 1
	if not agg_bloom.is_empty():
		_jobs.append({"name": "== ALL bloom_fauna ==", "nodes": agg_bloom, "mode": "species"})
	if not agg_fauna.is_empty():
		_jobs.append({"name": "== ALL fauna ==", "nodes": agg_fauna, "mode": "species"})
	for i in range(species.size()):
		if i > 0 and i % NULL_EVERY == 0:
			_jobs.append({"name": "(null pair %d)" % n_null, "nodes": [], "mode": "species"})
			n_null += 1
		species[i]["mode"] = "species"
		_jobs.append(species[i])
	print("[tps] species mode: %d groups + %d null pairs at vantage '%s'"
		% [species.size(), n_null, VANTAGE])
	# Budget the run OUT LOUD. A profiling harness that takes an hour gets killed before it
	# prints (docs/AGENT_TRAPS.md) — so say how long this one is going to be, up front.
	var f: int = _jobs.size() * 3 * (SPECIES_SETTLE + SPECIES_FRAMES)
	print("[tps] %d A/B/A measurements, %d frames (~%.0f s at 30 ms/frame)"
		% [_jobs.size(), f, f * 0.030])

## Distance from the eye to the nearest instance of a group, and how many sit inside
## AiBudget's full-rate radius. This is the column that says whether a row is expensive
## BECAUSE it is near the player (ticking every frame) or in spite of being decimated.
func _group_geometry(nodes: Array) -> Array:
	if _cam == null or nodes.is_empty():
		return [-1.0, 0]
	var eye: Vector3 = _cam.global_position
	var nearest: float = 1.0e9
	var near_n: int = 0
	for x in nodes:
		var n3 := x as Node3D
		if n3 == null or not is_instance_valid(n3):
			continue
		var d: float = eye.distance_to(n3.global_position)
		nearest = minf(nearest, d)
		if d <= AiBudget.NEAR_M:
			near_n += 1
	return [nearest if nearest < 1.0e9 else -1.0, near_n]

func _process(delta: float) -> void:
	# pause_menu.gd auto-pauses on focus-out and a PAUSED world still renders — losing focus
	# mid-run yields beautiful, stable, completely meaningless samples. Force it open. And take
	# the PANEL down too: it is its own CanvasLayer, so un-pausing leaves it drawn over every
	# subsequent frame, and a full-screen panel is not free to fill.
	if get_tree().paused:
		get_tree().paused = false
		_unpaused += 1
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
			_main = get_child(0)
			if SPECIES_MODE:
				GameClock.force_phase(GameClock.Phase.DAY)
				_place_camera()
			_build_jobs()
			_freeze_world()
			if SPECIES_MODE and _cam != null:
				# TWO DECIMALS, not .round(). A vantage 40 cm off is a DIFFERENT FRAME here —
				# TOPSIDE_MARGIN is 4.0 and the standing eye is 3.6 — and a rounded print
				# reports both of them as "4.0", which is the one thing this line exists to
				# rule out. See docs/AGENT_TRAPS.md.
				var e: Vector3 = _cam.global_position
				var f: Vector3 = -_cam.global_transform.basis.z
				print("[tps] eye (%.2f, %.2f, %.2f)  fwd (%.2f, %.2f, %.2f)"
					% [e.x, e.y, e.z, f.x, f.y, f.z])
			print("[tps] %d measurements queued" % _jobs.size())
			_start_window()
			_phase = Phase.RUN
		Phase.RUN:
			# Hold the pose. player_controller keeps integrating buoyancy and drift across a
			# long run even with _process off (physics ticks, other systems push it), and a
			# vantage that walks away mid-run is a different frame — s21 lost three frames to
			# exactly this (docs/AGENT_TRAPS.md).
			if SPECIES_MODE and _cam != null and VANTAGES.has(VANTAGE):
				var v: Array = VANTAGES[VANTAGE]
				_cam.global_position = v[0]
				_cam.look_at(v[1], Vector3.UP)
			if not _sample(delta):
				return
			_end_window()
		Phase.DONE:
			pass

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

func _start_window() -> void:
	_settle = SPECIES_SETTLE if SPECIES_MODE else SETTLE_FRAMES
	_frames.clear()
	_draws.clear()
	_procs.clear()

func _sample(delta: float) -> bool:
	if _settle > 0:
		_settle -= 1
		return false
	_frames.append(delta * 1000.0)
	_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	# The script step on its own — see the Bracket note at the top of this file.
	if _b_first != null:
		_procs.append(0.001 * float(_b_first.proc_us + _b_first.phys_us))
	return _frames.size() >= (SPECIES_FRAMES if SPECIES_MODE else SAMPLE_FRAMES)

func _median(a: Array) -> float:
	var b: Array = a.duplicate()
	b.sort()
	return float(b[b.size() / 2])

func _toggle(job: Dictionary, on: bool) -> void:
	# SPECIES: set_process / set_physics_process on exactly these nodes. NOT process_mode —
	# that propagates down the subtree, so a species with scripted children (GlowWormColony
	# over its GlowWorms, leg_reef over its snails) would be charged for them and the
	# children's own rows would double-count the same milliseconds. These two calls stop this
	# node's callbacks and nothing else's, which is what makes the rows additive.
	if job["mode"] == "species":
		for x in (job["nodes"] as Array):
			var n2 := x as Node
			if not is_instance_valid(n2):
				continue
			n2.set_process(on)
			n2.set_physics_process(on)
		return
	# A drill job owns MANY nodes (every instance of one species), toggled together.
	if job.has("nodes"):
		for x in (job["nodes"] as Array):
			if is_instance_valid(x):
				(x as Node).process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		return
	var n: Node = job["node"]
	if not is_instance_valid(n):
		return
	if job["mode"] == "script":
		n.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	elif n is Node3D:
		(n as Node3D).visible = on

func _end_window() -> void:
	_win.append(_median(_frames))
	_win_draw.append(_median(_draws))
	_win_proc.append(_median(_procs) if not _procs.is_empty() else 0.0)
	var job: Dictionary = _jobs[_job]
	if _step == 0:
		_toggle(job, false)          # -> OFF window
		_step = 1
		_start_window()
		return
	if _step == 1:
		_toggle(job, true)           # -> ON again
		_step = 2
		_start_window()
		return
	# three windows done
	var on_ms: float = (_win[0] + _win[2]) * 0.5
	var off_ms: float = _win[1]
	var on_draw: float = (_win_draw[0] + _win_draw[2]) * 0.5
	var off_draw: float = _win_draw[1]
	var on_proc: float = (_win_proc[0] + _win_proc[2]) * 0.5
	var row: Dictionary = {"name": job["name"], "mode": job["mode"],
		"saved": on_ms - off_ms, "draw": on_draw - off_draw,
		"noise": absf(_win[0] - _win[2]), "on": on_ms,
		"proc": on_proc - _win_proc[1], "proc_noise": absf(_win_proc[0] - _win_proc[2])}
	if job["mode"] == "species":
		var nodes: Array = job["nodes"]
		var geo: Array = _group_geometry(nodes)
		row["n"] = nodes.size()
		row["near_d"] = geo[0]
		row["near_n"] = geo[1]
	_rows.append(row)
	if _baseline_ms <= 0.0:
		_baseline_ms = on_ms
		_baseline_draw = on_draw
		_base_proc = on_proc
		print("[tps] baseline %.2f ms (%.1f fps), %.0f draw calls, script %.2f ms"
			% [_baseline_ms, 1000.0 / maxf(_baseline_ms, 0.001), _baseline_draw, _base_proc])
	if SPECIES_MODE:
		print("  [%2d/%2d] %-34s x%-4s script %6.3f ms (n %.3f)  frame %6.2f ms"
			% [_job + 1, _jobs.size(), row["name"], str(row.get("n", 0)),
				row["proc"], row["proc_noise"], row["saved"]])
	_win.clear()
	_win_draw.clear()
	_win_proc.clear()
	_step = 0
	_job += 1
	if _job >= _jobs.size():
		_report()
		return
	_start_window()

func _report() -> void:
	_phase = Phase.DONE
	if SPECIES_MODE:
		_report_species()
		return
	print("\n\n================ TPS PROFILE ================")
	print("baseline: %.2f ms/frame (%.1f fps), %.0f draw calls"
		% [_baseline_ms, 1000.0 / maxf(_baseline_ms, 0.001), _baseline_draw])
	print("'noise' is the spread between this row's two ON windows — a cost smaller than")
	print("its own noise figure is not a measurement, it is drift. Ignore those rows.")
	for mode in ["script", "render", "drill"]:
		var rows: Array = _rows.filter(func(r): return r["mode"] == mode)
		rows.sort_custom(func(a, b): return a["saved"] > b["saved"])
		print("\n--- %s COST — ms/frame recovered when switched off ---"
			% {"script": "SCRIPT (process_mode)", "render": "RENDER (visible=false)", "drill": "PER-SPECIES (process_mode)"}[mode])
		print("      ms    %%frame   draw calls   noise    subsystem")
		for r in rows:
			var trust: String = "  " if absf(r["saved"]) > r["noise"] else " ?"
			print("%s %7.2f  %5.1f%%  %9.0f  %6.2f    %s"
				% [trust, r["saved"], 100.0 * r["saved"] / maxf(_baseline_ms, 0.001),
					r["draw"], r["noise"], r["name"]])
	print("\n('?' = below its own noise floor)")
	print("=============================================\n")
	get_tree().quit()

func _report_species() -> void:
	var nulls: Array = []
	var nulls_f: Array = []
	for r in _rows:
		if String(r["name"]).begins_with("(null pair"):
			nulls.append(absf(r["proc"]))
			nulls_f.append(absf(r["saved"]))
	nulls.sort()
	nulls_f.sort()
	var floor_ms: float = float(nulls[nulls.size() / 2]) if not nulls.is_empty() else 0.0
	var worst_null: float = float(nulls.back()) if not nulls.is_empty() else 0.0
	var floor_frame: float = float(nulls_f[nulls_f.size() / 2]) if not nulls_f.is_empty() else 0.0
	print("\n\n============ PER-SPECIES COST — vantage '%s' ============" % VANTAGE)
	print("baseline: %.2f ms/frame (%.1f fps), %.0f draw calls, script step %.2f ms"
		% [_baseline_ms, 1000.0 / maxf(_baseline_ms, 0.001), _baseline_draw, _base_proc])
	print("Recovered when THIS species' _process/_physics_process is switched off, measured")
	print("ON/OFF/ON so slow drift cancels. set_process only — it does not propagate to")
	print("children, so the rows are additive.")
	print("")
	print("SCRIPT ms is the ranking column: the idle + physics script passes, measured end to")
	print("end by a pair of Bracket nodes forced to the first and last processing slots in the")
	print("tree. The frame delta is quantised at ~0.2 ms and drifts ~0.8 ms over a run, which")
	print("is larger than a whole species; Performance.TIME_PROCESS is a per-SECOND maximum and")
	print("is worse. Both were tried — see the note at the head of this file.")
	print("FRAME ms is the same A/B/A on the frame delta, kept because 'did the frame get")
	print("cheaper' is the real question; below its own floor it means only 'too small to see'.")
	print("")
	print("null pairs (toggle NOTHING): %d.  script floor: median %.3f ms, worst %.3f ms."
		% [nulls.size(), floor_ms, worst_null])
	print("                             frame floor: median %.2f ms." % floor_frame)
	print("('?' = below its own two-ON-window noise OR below the null median.)")
	print("'near' = instances inside AiBudget.NEAR_M (%.0f m), which tick EVERY frame."
		% AiBudget.NEAR_M)
	print("")
	print("%-3s %-32s %4s %9s %8s %8s %8s %8s %6s"
		% ["", "species", "n", "script ms", "%script", "noise", "frame ms", "nearest", "near"])
	var rows: Array = _rows.filter(func(r): return not String(r["name"]).begins_with("(null pair"))
	rows.sort_custom(func(a, b): return a["proc"] > b["proc"])
	var total: float = 0.0
	for r in rows:
		var nf: float = maxf(floor_ms, float(r["proc_noise"]))
		var trust: String = "  " if absf(r["proc"]) > nf else " ?"
		# The two "== ALL ... ==" rows are UNIONS of rows already in this table — counting them
		# in the sum double-counts every species in them and reported 254% of the script step.
		if r["proc"] > nf and not String(r["name"]).begins_with("=="):
			total += r["proc"]
		print("%s %-32s %4d %9.3f %7.1f%% %8.3f %8.2f %8.1f %6d"
			% [trust, r["name"], int(r.get("n", 0)), r["proc"],
				100.0 * r["proc"] / maxf(_base_proc, 0.001), r["proc_noise"],
				r["saved"], float(r.get("near_d", -1.0)), int(r.get("near_n", 0))])
	print("\nsum of script rows above the floor: %.2f ms of a %.2f ms script step (%.0f%%)"
		% [total, _base_proc, 100.0 * total / maxf(_base_proc, 0.001)])
	print("focus-out re-unpauses during the run: %d (0 is ideal)" % _unpaused)
	print("==========================================================\n")
	get_tree().quit()
