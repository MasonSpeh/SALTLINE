extends Node
## Acceptance test for the owner's two stair bugs: "got PERMANENTLY STUCK on a stair
## railing and had to restart", and an exterior run that climbs into the deck above.
##
## Drives a CharacterBody3D carrying the PLAYER'S EXACT capsule (radius 0.4, height
## 1.8, collider centred at y 0.9, collision mask 1) up every stair run in the rig and
## the full switchback tower, using move_and_slide toward a chain of waypoints.
##
## Nothing in here ever jumps. That is the point: if a run needs a jump, or a rail
## post catches the capsule, the body stops closing on its waypoint and the stall
## detector fires. Two assertions per route:
##   (a) it reaches every waypoint without progress stalling for > STALL_SECONDS
##   (b) no jump is ever required — y climbs monotonically enough along the treads
##       (a drop of more than DROP_TOL below the running maximum means it fell off
##       the run rather than walked up it)
##
## Run: godot --headless --path . res://tests/StairWalkProbe.tscn

const RADIUS: float = 0.4            ## Player.tscn CapsuleShape3D.radius
const HEIGHT: float = 1.8            ## PlayerController.STAND_HEIGHT
const COL_Y: float = 0.9             ## PlayerController.STAND_COL_Y
const SPEED: float = 3.2             ## PlayerController.WALK_SPEED
const GRAVITY: float = 9.8           ## PlayerController.GRAVITY

const STALL_SECONDS: float = 2.0     ## no closing on the waypoint for this long = stuck
const PROGRESS_EPS: float = 0.04     ## metres of closing that counts as progress
const REACH_XZ: float = 0.6          ## horizontal arrival tolerance
const REACH_Y: float = 1.0           ## vertical arrival tolerance
const DROP_TOL: float = 0.6          ## fell off the run if y sinks this far below its max
const ROUTE_SECONDS: float = 60.0    ## per-route budget
const MIN_HEADROOM: float = 1.85     ## a 1.8m player must not meet the soffit above a run

# ---- stair tower geometry (mirrors RigBuilder's consts; kept local so the probe
# ---- fails loudly if the tower is re-parameterised without updating the test).
const WET_Y: float = 2.0
const STAIR_RISE: float = 4.0
const STAIR_N: int = 9
const STAIR_XW: float = 23.5
const STAIR_XE: float = 28.5
const STAIR_ZS: float = -2.9
const STAIR_ZN: float = -1.1
const OPS_Y: float = WET_Y + STAIR_N * STAIR_RISE   # 38.0

const LOG_PATH: String = "/tmp/stair_walk_probe.txt"

var failures: int = 0
var _body: CharacterBody3D
var _step: float = 1.0 / 60.0
var _lines: PackedStringArray = PackedStringArray()

func _ready() -> void:
	await _run()
	_say("---")
	_say("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

## Every line goes to stdout AND to a file, rewritten after each line. Headless runs
## of this probe lose buffered stdout when the tree quits, and a stair probe whose
## verdict evaporates is worse than no probe at all.
func _say(msg: String) -> void:
	print(msg)
	_lines.append(msg)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()

func _fail(msg: String) -> void:
	failures += 1
	_say("FAIL  " + msg)

func _pass(msg: String) -> void:
	_say("PASS  " + msg)

func _run() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	# The rig streams its dressing over several frames; let it finish and let the
	# physics server build every CSG trimesh before we walk on any of it.
	await get_tree().create_timer(4.0).timeout
	for i in range(10):
		await get_tree().physics_frame

	_step = 1.0 / float(Engine.physics_ticks_per_second)

	# Park the real player: it is a CharacterBody3D on layer 1 and would otherwise
	# be a moving obstacle in the middle of a run.
	var p: Node3D = main.get("player")
	if p != null and p is CollisionObject3D:
		var pc := p as CollisionObject3D
		pc.set_collision_layer_value(1, false)
		pc.set_collision_mask_value(1, false)
		(p as Node3D).global_position = Vector3(0, 400, 0)

	_body = CharacterBody3D.new()
	_body.collision_layer = 0          # nothing else needs to see the probe
	_body.collision_mask = 1           # ...but it walks on the world, like the player
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	shape.shape = cap
	_body.add_child(shape)
	shape.position = Vector3(0, COL_Y, 0)
	add_child(_body)

	# `-- --route=tower` runs a single run instead of all of them. The whole sweep is
	# ~50s of simulated walking, and on a tree several builders are running headless
	# Godot against at once, a short targeted burst is often the only thing that
	# survives to print a verdict.
	var only: String = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--route="):
			only = a.substr(8).to_lower()

	_say("PROBE booted, capsule ready" + ("" if only == "" else "  (filter: %s)" % only))
	for route in _routes():
		var name_: String = String(route[0])
		if only != "" and not name_.to_lower().contains(only):
			continue
		_say("ROUTE " + name_)
		await _walk(name_, route[1] as Array, route.size() > 2 and bool(route[2]))

## Every stair run in the rig, as a chain of floor-level waypoints. Each route starts
## on flat ground at the foot and ends on flat ground at the top.
func _routes() -> Array:
	return [
		["boarding stairs -> Deck B balcony", [
			Vector3(17.5, 18.05, 3.4),      # topside deck, east of the run
			Vector3(15.8, 18.05, 3.4),      # foot of the flight
			Vector3(8.6, 21.65, 3.4),       # top of the flight, on the landing
			Vector3(6.8, 21.65, 3.4),       # across the landing to the balcony edge
			Vector3(2.0, 21.65, 4.2),       # out onto the balcony toward the quarters
		]],
		["west stairs -> Deck B level -> C terrace", [
			Vector3(-3.2, 18.05, 6.6),      # topside deck at the foot
			Vector3(-3.2, 18.05, 8.4),      # foot of flight 1
			Vector3(-3.3, 21.72, 14.9),     # top of flight 1, out past the rail end
			Vector3(-5.0, 21.72, 14.9),     # west across the mid landing
			Vector3(-5.0, 21.72, 13.55),    # turn south onto flight 2's foot
			Vector3(-5.0, 25.15, 8.5),      # top of flight 2 / top landing
			Vector3(-3.9, 25.15, 7.4),      # onto the C-deck terrace
		]],
		["observation platform step-down", [
			Vector3(-29.0, 18.05, -11.0),
			Vector3(-29.9, 18.05, -11.0),
			Vector3(-31.8, 17.6, -11.0),    # down onto the cantilevered platform
			Vector3(-29.9, 18.05, -11.0),   # ...and back up, the direction that traps
		]],
		["stair tower: wet deck y2 -> ops lookout y38", _tower_waypoints()],
		# Not a stair — this one guards the SPHL pod's new roof collider. The pod shell
		# is a CSG combiner with collision off (it would seal the hatch and trap you at
		# spawn), so the interior ceiling now carries the collision that shelter and
		# cover queries need. That plate has to be solid overhead AND high enough to
		# leave the pod walkable, which is exactly what this route measures: it walks
		# the full interior and REQUIRES a finite headroom reading the whole way.
		["SPHL pod interior (roof must be solid, floor must stay walkable)", [
			Vector3(15.5, 2.05, -24.0),     # aft benches, west end
			Vector3(20.5, 2.05, -24.0),     # forward, past the hatch line
			Vector3(20.0, 2.05, -23.3),     # in front of the hatch
			Vector3(16.0, 2.05, -24.8),     # back across the pod
		], true],
	]

## The full switchback, derived from the tower's own parameters: up each flight, across
## each turn platform, and finally out of the stairwell hole onto the ops-room floor.
func _tower_waypoints() -> Array:
	var wp: Array = [Vector3(23.0, WET_Y + 0.1, -4.6)]   # entry pad off the wet-deck door
	for k in range(1, STAIR_N + 1):
		var y0: float = WET_Y + (k - 1) * STAIR_RISE
		var y1: float = WET_Y + k * STAIR_RISE
		var odd: bool = (k % 2) == 1
		var foot_x: float = STAIR_XW if odd else STAIR_XE
		var top_x: float = STAIR_XE if odd else STAIR_XW
		var lane_z: float = STAIR_ZS if odd else STAIR_ZN
		wp.append(Vector3(foot_x, y0 + 0.05, lane_z))
		wp.append(Vector3(top_x, y1 + 0.05, lane_z))
		if k == STAIR_N:
			break
		# Cross the turn platform in the wall-end pocket to the next flight's foot.
		var park_x: float = 29.3 if odd else 22.7
		var next_z: float = STAIR_ZN if odd else STAIR_ZS
		wp.append(Vector3(park_x, y1 + 0.05, lane_z))
		wp.append(Vector3(park_x, y1 + 0.05, next_z))
	# Step east out of the stairwell hole onto solid ops-room floor.
	wp.append(Vector3(29.8, OPS_Y + 0.05, STAIR_ZS))
	wp.append(Vector3(30.4, OPS_Y + 0.05, 0.5))
	return wp

## Drive the capsule along one waypoint chain. Returns after the route finishes,
## stalls, or blows its time budget.
func _walk(label: String, waypoints: Array, needs_roof: bool = false) -> void:
	var start: Vector3 = waypoints[0]
	_body.global_position = start + Vector3(0, 0.25, 0)
	_body.velocity = Vector3.ZERO
	# Let it settle onto the plating before the clock starts.
	for i in range(30):
		_body.velocity.y -= GRAVITY * _step
		_body.move_and_slide()
		await get_tree().physics_frame
	if not _body.is_on_floor():
		_fail("%s: capsule never found the floor at the start point %s (landed y=%.2f)"
			% [label, str(start), _body.global_position.y])
		return

	var idx: int = 1
	var elapsed: float = 0.0
	var stall: float = 0.0
	var best: float = INF
	var y_max: float = _body.global_position.y
	var worst_drop: float = 0.0
	var start_y: float = _body.global_position.y
	var low_head: float = INF
	var low_head_at: Vector3 = Vector3.ZERO

	while idx < waypoints.size():
		var target: Vector3 = waypoints[idx]
		var pos: Vector3 = _body.global_position
		var flat := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
		var dist: float = flat.length()

		if dist < REACH_XZ and absf(target.y - pos.y) < REACH_Y:
			idx += 1
			best = INF
			stall = 0.0
			continue

		# Score progress on the full 3D gap so a capsule that is sliding sideways
		# along a rail at constant distance still reads as stalled.
		var gap: float = pos.distance_to(target)
		if gap < best - PROGRESS_EPS:
			best = gap
			stall = 0.0
		else:
			stall += _step
			if stall > STALL_SECONDS:
				_fail("%s: STUCK for %.1fs at %s heading for waypoint %d %s (gap %.2fm, on_floor=%s, on_wall=%s) blockers: %s"
					% [label, stall, str(pos.snappedf(0.01)), idx, str(target), gap,
						str(_body.is_on_floor()), str(_body.is_on_wall()), _blockers()])
				return

		var dir: Vector3 = flat.normalized() if dist > 0.001 else Vector3.ZERO
		_body.velocity.x = dir.x * SPEED
		_body.velocity.z = dir.z * SPEED
		if _body.is_on_floor():
			_body.velocity.y = 0.0
		else:
			_body.velocity.y -= GRAVITY * _step
		_body.move_and_slide()
		await get_tree().physics_frame

		pos = _body.global_position
		y_max = maxf(y_max, pos.y)
		worst_drop = maxf(worst_drop, y_max - pos.y)
		# Headroom over the walking surface: a run that climbs into the underside of
		# the deck above shows up here long before the capsule physically jams.
		if _body.is_on_floor():
			var head: float = _headroom(pos)
			if head < low_head:
				low_head = head
				low_head_at = pos
		elapsed += _step
		if elapsed > ROUTE_SECONDS:
			_fail("%s: ran out of time (%.0fs) at %s heading for waypoint %d %s"
				% [label, elapsed, str(pos.snappedf(0.01)), idx, str(target)])
			return

	var end_y: float = _body.global_position.y
	# A jump would show up as the only way past a lip: the capsule can't jump here, so
	# reaching the top at all proves it didn't need one. What this guards is the other
	# half — that it walked the treads instead of falling off and taking another line.
	if worst_drop > DROP_TOL:
		_fail("%s: left the run — y fell %.2fm below its running maximum (limit %.2f)"
			% [label, worst_drop, DROP_TOL])
		return
	if low_head < MIN_HEADROOM:
		_fail("%s: run climbs into the structure above — only %.2fm of headroom at %s (need %.2f)"
			% [label, low_head, str(low_head_at.snappedf(0.01)), MIN_HEADROOM])
		return
	if needs_roof and low_head == INF:
		_fail("%s: OPEN SKY overhead for the whole route — the roof has no collider, so "
			% label + "shelter and cover queries see straight through it")
		return
	_pass("%s: walked %.1fm of climb in %.1fs, no jump, max backslide %.2fm, min headroom %s"
		% [label, end_y - start_y, elapsed, worst_drop,
			"open sky" if low_head == INF else "%.2fm" % low_head])

## Clearance from the capsule's feet to whatever is directly overhead.
func _headroom(pos: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	if space == null:
		return INF
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.05, 0),
		pos + Vector3(0, 0.05 + 4.0, 0))
	q.collision_mask = 1
	q.exclude = [_body.get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return INF
	return float(hit["position"].y) - pos.y

## What the capsule is actually pressed against — the difference between "a rail
## post caught me" and "the deck above has no opening".
func _blockers() -> String:
	var seen: Array[String] = []
	for i in range(_body.get_slide_collision_count()):
		var c: KinematicCollision3D = _body.get_slide_collision(i)
		var who: Object = c.get_collider()
		var name_: String = "?"
		if who is Node:
			name_ = String((who as Node).get_path())
		var entry: String = "%s n=%s" % [name_, str(c.get_normal().snappedf(0.01))]
		if not seen.has(entry):
			seen.append(entry)
	return "; ".join(seen) if not seen.is_empty() else "(none reported)"
