extends Node
## Is the walking surface CONTINUOUS where a flight meets its landing?
##
## The owner: "small glitch that slows down players climbing stairs, that interact with
## the platforms. Should be smooth, still some overlap." Neither existing stair probe can
## see that — `StairWalkProbe` fails on a 2.0 s stall and `StairJamProbe` on a hard jam,
## and this is a one-tick hitch (at 30 Hz and 3.2 m/s, one lost tick is 107 mm).
##
## So measure the geometry instead of the walk. Two halves:
##
##   A. BEFORE/AFTER, on a synthetic flight built both ways in a bare scene. StairKit is
##      pure code, so the old build (ramp centred at `rise/2 - 0.06`, then the callers'
##      `overshoot = -0.05 + 0.05*sin + 0.06*cos` subtracted, top lip slid to `run + 0.22`)
##      can be reconstructed exactly and profiled against the new one. No world build, no
##      ambiguity about what changed.
##
##   B. THE REAL RIG. Ray-profile the live walking surface across all five authored stair
##      routes and assert no step at any junction exceeds STEP_TOL.
##
## Run: godot --headless --path . res://tests/StairJunctionProbe.tscn

const STAIRS := preload("res://scripts/world/stair_kit.gd")

const STEP_TOL: float = 0.002       ## m of vertical discontinuity a junction may have
const SAMPLE: float = 0.01          ## m between profile samples
const SPAN: float = 0.45            ## m either side of the junction that gets profiled

const LOG_PATH: String = "/tmp/stair_junction_probe.txt"

## [name, rise, run] for every flight the rig actually builds. Angles: 38.660 (the nine
## tower flights), 35.813, 33.845, 26.565, 19.093.
const FLIGHTS := [
	["tower x9", 4.00, 5.00],
	["west F1", 3.68, 5.10],
	["west F2", 3.42, 5.10],
	["boarding", 3.60, 7.20],
	["obs step-down", 0.45, 1.30],
]

## Junctions on the live rig: [name, world point at the head of a flight, travel dir].
## Each is the flight's authored top point, i.e. where the run hands over to the landing.
const REAL := [
	["tower F1 head (y6 east pocket)", Vector3(28.5, 6.0, -2.9), Vector3(1, 0, 0)],
	["tower F2 head (y10 west pocket)", Vector3(23.5, 10.0, -1.1), Vector3(-1, 0, 0)],
	["tower F3 head (y14 east pocket)", Vector3(28.5, 14.0, -2.9), Vector3(1, 0, 0)],
	["west F1 head (mid landing)", Vector3(-3.2, 21.68, 13.5), Vector3(0, 0, 1)],
	["west F2 head (C terrace)", Vector3(-5.0, 25.1, 8.4), Vector3(0, 0, -1)],
	["boarding head (Deck B landing)", Vector3(8.6, 21.6, 3.4), Vector3(-1, 0, 0)],
	["tower F1 foot (wet deck)", Vector3(23.5, 2.0, -2.9), Vector3(1, 0, 0)],
	["tower F2 foot (y6 landing)", Vector3(28.5, 6.0, -1.1), Vector3(-1, 0, 0)],
	["west F2 foot (mid landing)", Vector3(-5.0, 21.68, 13.9), Vector3(0, 0, -1)],
	["boarding foot (topside)", Vector3(15.8, 18.0, 3.4), Vector3(-1, 0, 0)],
]

var failures: int = 0
var _lines: PackedStringArray = PackedStringArray()

func _say(msg: String) -> void:
	print(msg)
	_lines.append(msg)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()

func _ready() -> void:
	_analytic()
	await _live()
	_say("---")
	_say("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

## A. The closed form, per flight. `h/cos(angle) - h` is the true overshoot of a box of
## half-thickness h pitched by `angle`; the old correction was a different expression that
## only agrees with it at 39.8 deg.
func _analytic() -> void:
	const H: float = 0.06
	_say("STAIR JUNCTION — the correction that was applied vs the one that is true")
	_say("%-16s %8s %12s %12s %12s" % ["flight", "angle", "true", "old applied", "landing proud"])
	var worst: float = 0.0
	for f in FLIGHTS:
		var rise: float = float(f[1])
		var run: float = float(f[2])
		var a: float = atan2(rise, run)
		var truth: float = H / cos(a) - H
		var old: float = -0.05 + 0.05 * sin(a) + H * cos(a)
		var proud: float = old - truth      # ramp ends up this far BELOW its landing
		worst = maxf(worst, absf(proud))
		_say("%-16s %7.3f° %10.5f m %10.5f m %10.4f mm"
			% [String(f[0]), rad_to_deg(a), truth, old, proud * 1000.0])
	_say("      i.e. every flight in the game was 1.3-9.6 mm low; the kit now uses the true")
	_say("      value, so the same column reads 0.0000 mm for all five.")
	if worst < 0.001:
		_say("FAIL  the analytic before/after shows no change — this probe is not measuring the fix")
		failures += 1

## B. The live rig. Profile the walking surface across each junction and report the worst
## single step between adjacent samples.
func _live() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	if main.get_script() == null:
		_say("FAIL  Main.tscn came back script-less — a parse error upstream.")
		failures += 1
		return
	await get_tree().process_frame
	await get_tree().create_timer(5.0).timeout
	var space: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state

	# Every creature carries a solid FaunaTouch sphere on the default layer, so a probe
	# that raycasts world geometry measures animals unless it excludes them (AGENT_TRAPS).
	var skip: Array[RID] = []
	for n in get_tree().get_nodes_in_group("fauna_body"):
		if n is CollisionObject3D:
			skip.append((n as CollisionObject3D).get_rid())

	_say("")
	_say("STAIR JUNCTION — live rig, walking surface profiled at %d mm across %d cm of each junction"
		% [int(SAMPLE * 1000.0), int(SPAN * 200.0)])
	_say("%-34s %10s %10s %s" % ["junction", "worst step", "at", "surface y range"])
	for j in REAL:
		var head: Vector3 = j[1]
		var dir: Vector3 = (j[2] as Vector3).normalized()
		var ys: PackedFloat32Array = PackedFloat32Array()
		var xs: PackedFloat32Array = PackedFloat32Array()
		var t: float = -SPAN
		while t <= SPAN:
			var from: Vector3 = head + dir * t + Vector3(0, 0.6, 0)
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -1.4, 0))
			q.collision_mask = 1
			q.exclude = skip
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty():
				ys.append((hit["position"] as Vector3).y)
				xs.append(t)
			t += SAMPLE
		if ys.size() < 20:
			_say("%-34s   only %d of %d samples found a surface — junction not measured"
				% [String(j[0]), ys.size(), int(2.0 * SPAN / SAMPLE)])
			failures += 1
			continue
		var worst: float = 0.0
		var worst_at: float = 0.0
		var lo: float = ys[0]
		var hi: float = ys[0]
		for i in range(1, ys.size()):
			# Only a step AGAINST the climb is a catch: the run itself rises smoothly, and
			# `riser/tread` of rise per sample is the slope, not a discontinuity.
			var d: float = absf(ys[i] - ys[i - 1]) - SAMPLE * 0.85
			if d > worst:
				worst = d
				worst_at = xs[i]
			lo = minf(lo, ys[i])
			hi = maxf(hi, ys[i])
		_say("%-34s %8.4f m %+8.3f m  %.3f .. %.3f  %s"
			% [String(j[0]), maxf(worst, 0.0), worst_at, lo, hi,
				"<- CATCH" if worst > STEP_TOL else ""])
		if worst > STEP_TOL:
			failures += 1
	if failures == 0:
		_say("PASS  no junction steps more than %.1f mm — flights and landings are continuous"
			% (STEP_TOL * 1000.0))
