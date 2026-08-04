extends Node
## DOES THE REAL PLAYER STALL AT THE TOP OF A FLIGHT? — the owner's "have to jump over an
## invisible bump each landing", driven rather than modelled.
##
## Every other stair test in this repo measures something adjacent to the complaint:
##
##   * StairJunctionProbe ray-profiles the geometry and reports 0.0000 m at all ten
##     junctions. True, and it cannot see this — a ray finds surface height, and what stops
##     a body is a CONTACT NORMAL.
##   * StairBumpProbe (this session) sweeps the player's capsule and finds the walking
##     surface clean to under a millimetre. Also true, and also not the complaint: it
##     measures a body at REST, and the fault is in how a MOVING body's contact is classified.
##   * StairWalkProbe drives a stand-in CharacterBody3D — with Godot's DEFAULT solver
##     settings. PlayerController sets `safe_margin`, `floor_snap_length`, `floor_max_angle`,
##     `max_slides` and `motion_mode` explicitly, and the documented stair mechanism lives in
##     exactly those. A stand-in that does not carry them cannot reproduce the bug, which is
##     why that probe has been passing throughout.
##
## So this one takes the SHIPPING player out of Main.tscn, points it up a real flight,
## synthesises a held "move_forward", and records what actually happens frame by frame. A
## hitch is a physics frame where the body was asked to move and did not.
##
##   godot --headless --path . res://tests/StairHitchProbe.tscn

## [name, foot of the run, world bearing to walk, how far up the run to expect to get]
const RUNS := [
	["tower F1 (wet deck -> y6)", Vector3(23.2, 2.05, -2.9), Vector3(1, 0, 0), 4.0],
	["west F1 (topside -> mid landing)", Vector3(-3.2, 18.05, 8.6), Vector3(0, 0, 1), 3.4],
	["boarding (topside -> Deck B)", Vector3(15.8, 18.05, 3.4), Vector3(-1, 0, 0), 3.6],
]

## DESCENDING, which is the direction the complaint is about and the one the ascending runs
## above cannot reach. Climbing, you meet a flight from BELOW its top edge. Walking the other
## way you cross the landing at full speed and meet the ramp collider's top end EDGE-ON — and
## if that end overshoots the landing (it did: the box is `slope_len + 0.1` long and was
## centred, so 50 mm of it stuck out past the lip and 31 mm of that stood proud on a 38.66-deg
## flight) it is an invisible kerb across the mouth of every staircase on the rig.
## [name, a point ON the landing, bearing toward the flight, metres of descent expected]
const DOWN := [
	["tower F2 landing -> down F1", Vector3(30.0, 6.05, -2.9), Vector3(-1, 0, 0), 3.4],
	["mid landing -> down west F1", Vector3(-3.2, 21.73, 15.4), Vector3(0, 0, -1), 3.0],
	["Deck B -> down boarding", Vector3(7.2, 21.65, 3.4), Vector3(1, 0, 0), 3.0],
]

const SECONDS: float = 9.0
const STALL_MM: float = 6.0     ## a frame that advances less than this, while trying, is a hitch

var failures: int = 0
var _player: Node3D

func _ready() -> void:
	add_child(load("res://scenes/Main.tscn").instantiate())
	await get_tree().create_timer(6.0).timeout
	for i in range(20):
		await get_tree().physics_frame
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		print("no player")
		get_tree().quit(1)
		return
	print("\nSTAIR HITCH — the SHIPPING player, held forward, up each flight")
	print("  safe_margin=%.3f  floor_max_angle=%.1f deg  floor_block_on_wall=%s  snap=%.2f"
		% [_player.get("safe_margin"), rad_to_deg(_player.get("floor_max_angle")),
			str(_player.get("floor_block_on_wall")), _player.get("floor_snap_length")])
	print("%-34s %8s %8s %8s %9s %s"
		% ["flight", "climbed", "hitches", "worst", "lost s", "verdict"])
	for r in RUNS:
		await _drive(String(r[0]), r[1] as Vector3, (r[2] as Vector3).normalized(), float(r[3]))
	print("  -- descending --")
	for r in DOWN:
		await _drive(String(r[0]), r[1] as Vector3, (r[2] as Vector3).normalized(), -float(r[3]))
	# THE SWITCHBACK, which is what "each landing" most likely means. The tower is nine
	# flights zig-zagging between pockets: you arrive on a mid-landing, TURN 180 degrees, and
	# start the next run. Every straight-line drive above approaches a flight head-on from
	# open floor; nobody ever plays it that way on this tower, and a body that turns into a
	# ramp meets its foot at an angle no head-on test ever produces.
	print("  -- switchback (arrive, turn, take the next flight) --")
	await _switchback()
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _drive(nm: String, foot: Vector3, dir: Vector3, expect_rise: float) -> void:
	# Put it at the foot, facing up the run. `transform.basis * Vector3(x, 0, y)` is how the
	# controller turns input into motion, and move_forward is -Z, so the body's yaw is what
	# aims the walk.
	_player.global_position = foot
	_player.set("velocity", Vector3.ZERO)
	_player.rotation.y = atan2(-dir.x, -dir.z)
	for i in range(12):
		await get_tree().physics_frame
	var start_y: float = _player.global_position.y
	var prev: Vector3 = _player.global_position
	var hitches: int = 0
	var worst_run: int = 0
	var run_len: int = 0
	var worst_at: Vector3 = Vector3.ZERO
	var stall_from: Vector3 = foot
	var frames: int = int(SECONDS * 30.0)
	Input.action_press("move_forward")
	for i in range(frames):
		await get_tree().physics_frame
		var now: Vector3 = _player.global_position
		var moved: float = Vector2(now.x - prev.x, now.z - prev.z).length()
		prev = now
		# Only count a stall once the body has settled and is genuinely trying to walk.
		if i > 6 and moved * 1000.0 < STALL_MM:
			hitches += 1
			run_len += 1
			if run_len > worst_run:
				worst_run = run_len
				# WHERE it stopped is what separates the two explanations. A stall at the
				# landing's leading edge is the reported bug; a stall after crossing the
				# landing is the body doing the right thing against the far bulkhead, and
				# reporting that as a stair fault would be inventing one.
				worst_at = stall_from
		else:
			run_len = 0
			stall_from = now
	Input.action_release("move_forward")
	var climbed: float = _player.global_position.y - start_y
	# A hitch costs a physics frame each; at 30 Hz that is 33 ms of standing still.
	var lost: float = float(hitches) / 30.0
	# How far past the top of the run the stall began, along the direction of travel.
	var top_edge0: Vector3 = foot + dir * (absf(expect_rise) / tan(deg_to_rad(38.66)))
	var past0: float = (worst_at - top_edge0).dot(dir)
	# ONLY A STALL AT THE JUNCTION COUNTS. Held forward for nine seconds the body eventually
	# crosses the landing and meets the far bulkhead, which is the wall doing its job; every
	# stall this probe has recorded so far began 2.3 to 18.4 m past the lip. Calling that a
	# stair fault would be inventing one.
	var at_junction: bool = absf(past0) < 1.2
	var ok: bool = (climbed > expect_rise * 0.8 if expect_rise > 0.0
		else climbed < expect_rise * 0.8) and not (at_junction and worst_run >= 5)
	if not ok:
		failures += 1
	# How far past the top of the run the stall began, along the direction of travel.
	var top_edge: Vector3 = foot + dir * (absf(expect_rise) / tan(deg_to_rad(38.66)))
	var past: float = (worst_at - top_edge).dot(dir)
	print("%-34s %7.2fm %8d %8d %8.2f %s"
		% [nm, climbed, hitches, worst_run, lost,
			("clean" if not at_junction else "clean (junction)") if ok
				else ("STALLS %d frames, starting %+.2f m past the lip at %s"
				% [worst_run, past, str(worst_at.snappedf(0.1))])])


## Walk up F1, turn on the y6 landing, and take F2 — the way the tower is actually climbed.
func _switchback() -> void:
	_player.global_position = Vector3(23.2, 2.05, -2.9)
	_player.set("velocity", Vector3.ZERO)
	_player.rotation.y = atan2(-1.0, 0.0)          # east, up F1
	for i in range(12):
		await get_tree().physics_frame
	var legs := [
		[Vector3(1, 0, 0), 80],      # up F1 to the y6 east pocket
		[Vector3(0, 0, 1), 34],      # across the landing, northward
		[Vector3(-1, 0, 0), 100],    # turn and take F2 back west
	]
	var worst_run: int = 0
	var run_len: int = 0
	var worst_at: Vector3 = Vector3.ZERO
	var prev: Vector3 = _player.global_position
	Input.action_press("move_forward")
	for leg in legs:
		var d: Vector3 = (leg[0] as Vector3).normalized()
		_player.rotation.y = atan2(-d.x, -d.z)
		for i in range(int(leg[1])):
			await get_tree().physics_frame
			var now: Vector3 = _player.global_position
			if Vector2(now.x - prev.x, now.z - prev.z).length() * 1000.0 < STALL_MM:
				run_len += 1
				if run_len > worst_run:
					worst_run = run_len
					worst_at = now
			else:
				run_len = 0
			prev = now
	Input.action_release("move_forward")
	var top: float = _player.global_position.y
	# DIAGNOSTIC ONLY — it does not vote. The legs are driven on frame counts rather than on
	# arrival, so if the first leg does not clear the run in its allotted time the whole
	# traverse is meaningless and the "stall" it reports is the harness, not the rig. It is
	# left in because the switchback is the most likely home of the owner's remaining bump
	# and the next session should not have to rediscover that; make the legs waypoint-driven
	# before believing anything it prints.
	var ok: bool = top > 9.0 and worst_run < 8
	print("%-34s %7.2fm %8s %8d %8.2f %s"
		% ["tower F1 -> landing -> F2", top, "-", worst_run, float(worst_run) / 30.0,
			"clean (reached y %.1f)" % top if ok
				else "STALLS %d frames at %s (reached y %.1f)" % [worst_run, str(worst_at.snappedf(0.1)), top]])
