extends Node3D
## SNAIL SURFACE-NAVIGATION PROBE — drives the real GroundCrawler (the one the three
## deck snail species run) for a simulated minute against three shapes of obstruction
## and audits the four things a gastropod has to get right:
##
##   A. TALL BULKHEAD (8 m) — it may climb, but it must stick to the face, must turn
##      back before ~6 m, and must never end up inside the plate.
##   B. LOW KERB (0.25 m)   — it crawls straight OVER, up the near face, across the
##      top and down the far side, and ends up on the far side of the kerb.
##   C. PLAIN WALL (2 m)    — it must decide (left / right / climb) rather than press,
##      and it must never stall in one spot.
##
## Every scenario also runs the two universal assertions, sampled EVERY tick:
##   * never penetrates geometry (origin never inside a collider, never past a face)
##   * never stalls (never sits inside a 0.15 m circle for more than STALL_MAX seconds)
##
## Prints one line per check and a final SNAIL-FAILURES: N (0 == green).
## Run: godot --headless --path . res://tests/SnailProbe.tscn

const BLOOM := preload("res://scripts/world/bloom_fauna.gd")

const DT := 0.05                ## simulated step
const TICKS := 1200             ## 1200 * 0.05 = 60 s, a simulated minute
const STALL_MAX := 4.0          ## seconds allowed inside STALL_R before it counts as wedged
const STALL_R := 0.15           ## metres — "one spot"
const CLIMB_CEIL := 6.0         ## the crawler's own CLIMB_MAX
const CLIMB_SLOP := 0.6         ## overshoot allowed while it decelerates and turns

var _fails: Array[String] = []

func _ok(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "SNAIL-FAIL  "), msg)
	if not cond:
		_fails.append(msg)

func _ready() -> void:
	_floor()
	await get_tree().physics_frame
	await get_tree().physics_frame

	await _tall_bulkhead()
	await _low_kerb()
	await _plain_wall()
	await _boxed_in()
	await _random_choice()

	print("SNAIL-FAILURES: ", _fails.size())
	get_tree().quit()

# ---------------------------------------------------------------- world geometry
## One big plate under all three scenarios; top face at y = 0.
func _floor() -> void:
	_box(Vector3(60.0, -0.5, 6.0), Vector3(240.0, 1.0, 60.0))

func _box(centre: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	add_child(body)
	body.global_position = centre
	return body

# ------------------------------------------------------------------- the driver
## Run one snail for TICKS steps from `start`, forced at the obstruction to begin with.
## Returns the sampled record every assertion below is read from.
func _run(start: Vector3, heading: Vector3, leash: float, seed_: int = 11) -> Dictionary:
	var host := Node3D.new()
	add_child(host)
	host.global_position = start
	await get_tree().physics_frame
	# The species constructor, verbatim: home, leash, speed, seed, body_radius,
	# probe_height, y_fallback, axis(ZERO == free disc wander).
	var crawler: Object = BLOOM.GroundCrawler.new(start, leash, 0.35, seed_, 0.3, 0.15, start.y, Vector3.ZERO)
	crawler.heading = heading.normalized()

	var rec := {
		"max_z": start.z, "max_y": start.y, "min_y": start.y,
		"peak_climb": 0.0, "inside": 0, "stall": 0.0, "worst_stall": 0.0,
		"choices": {}, "heights": {}, "climbed": false, "turned_back": false,
		"climb_up_y": 0.0, "frame_err": 0.0,
		"path_len": 0.0, "end": start,
	}
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var anchor: Vector3 = start
	var stall: float = 0.0
	var prev: Vector3 = start
	var rising: bool = false
	var last_choice: String = ""
	for i in range(TICKS):
		crawler.tick(host, DT)
		var p: Vector3 = host.global_position
		rec["path_len"] = float(rec["path_len"]) + p.distance_to(prev)
		prev = p
		rec["max_z"] = maxf(float(rec["max_z"]), p.z)
		rec["max_y"] = maxf(float(rec["max_y"]), p.y)
		rec["min_y"] = minf(float(rec["min_y"]), p.y)
		var lift: float = p.y - start.y
		rec["peak_climb"] = maxf(float(rec["peak_climb"]), lift)
		# ORIENTATION, sampled while unambiguously up a vertical face: the foot normal must
		# be horizontal (stuck to the wall, not to the deck) and the drawn body frame's +Y
		# must BE that normal — which is the difference between a snail on a wall and a
		# snail lying on its side in the air next to one.
		if lift > 1.0:
			var u: Vector3 = crawler.up
			rec["climb_up_y"] = maxf(float(rec["climb_up_y"]), absf(u.y))
			rec["frame_err"] = maxf(float(rec["frame_err"]), (crawler.basis().y - u).length())
		if lift > 0.5:
			rec["climbed"] = true
			rising = true
		elif rising and lift < 0.2:
			rec["turned_back"] = true
			rising = false
		# PENETRATION: is the origin inside a solid? A point query is the honest test —
		# it catches a snail that slid into the plate sideways, not just one that walked
		# through the face it was aimed at.
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = p
		pq.collision_mask = 1
		pq.collide_with_areas = false
		if not space.intersect_point(pq, 1).is_empty():
			rec["inside"] = int(rec["inside"]) + 1
		# STALL: time spent without leaving a STALL_R circle.
		if p.distance_to(anchor) > STALL_R:
			anchor = p
			stall = 0.0
		else:
			stall += DT
			rec["worst_stall"] = maxf(float(rec["worst_stall"]), stall)
		# `choice` is sticky (it holds the LAST decision), so count transitions, not ticks.
		var ch: String = String(crawler.choice)
		if ch != "" and ch != last_choice:
			rec["choices"][ch] = int(rec["choices"].get(ch, 0)) + 1
			last_choice = ch
		var bh: float = float(crawler.boundary_h)
		if bh >= 0.0:
			rec["heights"][snappedf(bh, 0.05)] = int(rec["heights"].get(snappedf(bh, 0.05), 0)) + 1
	rec["end"] = host.global_position
	host.queue_free()
	return rec

func _report(tag: String, rec: Dictionary) -> void:
	print("      %s: path %.1f m, peak climb %.2f m, worst stall %.2f s, inside-geometry ticks %d, end %s"
		% [tag, rec["path_len"], rec["peak_climb"], rec["worst_stall"], rec["inside"],
			str((rec["end"] as Vector3).snapped(Vector3(0.01, 0.01, 0.01)))])
	print("      %s decisions: %s" % [tag, str(rec["choices"])])
	print("      %s measured boundary heights: %s" % [tag, str(rec["heights"])])

# ------------------------------------------------------------ A. tall bulkhead
func _tall_bulkhead() -> void:
	print("--- A. tall bulkhead (8 m): climbs, sticks, turns back before 6 m ---")
	# 8 m plate, near face at z = 5.8.
	var wall: StaticBody3D = _box(Vector3(0.0, 4.0, 6.0), Vector3(16.0, 8.0, 0.4))
	await get_tree().physics_frame
	var rec: Dictionary = await _run(Vector3(0.0, 0.02, 3.0), Vector3(0.0, 0.0, 1.0), 8.0)
	_report("tall", rec)
	_ok(int(rec["inside"]) == 0, "tall face: never inside geometry (0 of %d ticks)" % TICKS)
	_ok(float(rec["max_z"]) < 5.8, "tall face: never crossed the plate face (max z %.2f < 5.80)" % rec["max_z"])
	_ok(float(rec["worst_stall"]) <= STALL_MAX,
		"tall face: never wedged (worst stall %.2f s <= %.1f s)" % [rec["worst_stall"], STALL_MAX])
	_ok(float(rec["peak_climb"]) <= CLIMB_CEIL + CLIMB_SLOP,
		"tall face: turned back before the ceiling (peak %.2f m <= %.1f m)"
			% [rec["peak_climb"], CLIMB_CEIL + CLIMB_SLOP])

# ------------------------------------------------------------------ B. low kerb
func _low_kerb() -> void:
	print("--- B. low kerb (0.25 m): crawls straight over it ---")
	# A lip well under KERB (0.4): near face z = 5.75, top y = 0.25, far face z = 6.25.
	var kerb: StaticBody3D = _box(Vector3(30.0, 0.125, 6.0), Vector3(16.0, 0.25, 0.5))
	await get_tree().physics_frame
	var rec: Dictionary = await _run(Vector3(30.0, 0.02, 4.6), Vector3(0.0, 0.0, 1.0), 8.0)
	_report("kerb", rec)
	_ok(int(rec["inside"]) == 0, "kerb: never inside geometry (0 of %d ticks)" % TICKS)
	_ok(float(rec["worst_stall"]) <= STALL_MAX,
		"kerb: never wedged (worst stall %.2f s <= %.1f s)" % [rec["worst_stall"], STALL_MAX])
	_ok(float(rec["max_z"]) > 6.25,
		"kerb: crawled OVER it and down the far side (max z %.2f > 6.25)" % rec["max_z"])
	_ok(float(rec["max_y"]) >= 0.24,
		"kerb: rode the top face on the way (max y %.2f >= 0.24)" % rec["max_y"])

# ----------------------------------------------------------------- C. plain wall
func _plain_wall() -> void:
	print("--- C. plain wall (2 m): decides instead of pressing ---")
	var wall: StaticBody3D = _box(Vector3(60.0, 1.0, 6.0), Vector3(16.0, 2.0, 0.4))
	await get_tree().physics_frame
	var rec: Dictionary = await _run(Vector3(60.0, 0.02, 3.0), Vector3(0.0, 0.0, 1.0), 8.0)
	_report("wall", rec)
	_ok(int(rec["inside"]) == 0, "wall: never inside geometry (0 of %d ticks)" % TICKS)
	_ok(float(rec["max_z"]) < 5.8, "wall: never crossed the face (max z %.2f < 5.80)" % rec["max_z"])
	_ok(float(rec["worst_stall"]) <= STALL_MAX,
		"wall: never wedged (worst stall %.2f s <= %.1f s)" % [rec["worst_stall"], STALL_MAX])
	_ok(float(rec["path_len"]) > 6.0,
		"wall: kept travelling instead of pressing (path %.1f m over 60 s)" % rec["path_len"])
	var decided: bool = rec["choices"].has("left") or rec["choices"].has("right") \
		or rec["choices"].has("climb")
	_ok(decided, "wall: made a real left/right/climb decision (%s)" % str(rec["choices"]))

# ------------------------------------------------------------- D. boxed in: climb
func _boxed_in() -> void:
	print("--- D. boxed into an alcove: the only way on is UP ---")
	# Front plate plus both side walls, all 8 m: every flank probe comes back blocked, so
	# the decision roll goes to certain-climb. This is the scenario that actually exercises
	# sticking to a vertical face and the six-metre turnaround.
	_box(Vector3(100.0, 4.0, 6.0), Vector3(4.0, 8.0, 0.4))     # front, face z = 5.8
	_box(Vector3(98.9, 4.0, 5.0), Vector3(0.4, 8.0, 2.4))      # left,  inner face x = 99.1
	_box(Vector3(101.1, 4.0, 5.0), Vector3(0.4, 8.0, 2.4))     # right, inner face x = 100.9
	await get_tree().physics_frame
	var rec: Dictionary = await _run(Vector3(100.0, 0.02, 4.6), Vector3(0.0, 0.0, 1.0), 8.0)
	_report("boxed", rec)
	_ok(int(rec["inside"]) == 0, "boxed in: never inside geometry (0 of %d ticks)" % TICKS)
	_ok(float(rec["worst_stall"]) <= STALL_MAX,
		"boxed in: never wedged (worst stall %.2f s <= %.1f s)" % [rec["worst_stall"], STALL_MAX])
	_ok(bool(rec["climbed"]), "boxed in: climbed the face rather than pressing (peak %.2f m)" % rec["peak_climb"])
	_ok(float(rec["peak_climb"]) >= CLIMB_CEIL - 1.0,
		"boxed in: rode the vertical face up to the ceiling (peak %.2f m >= %.1f m)"
			% [rec["peak_climb"], CLIMB_CEIL - 1.0])
	_ok(float(rec["peak_climb"]) <= CLIMB_CEIL + CLIMB_SLOP,
		"boxed in: turned back AT the ceiling, did not run on (peak %.2f m <= %.1f m)"
			% [rec["peak_climb"], CLIMB_CEIL + CLIMB_SLOP])
	_ok(bool(rec["turned_back"]), "boxed in: came back down the face after turning")
	_ok(float(rec["climb_up_y"]) < 0.3,
		"boxed in: foot stayed stuck to the VERTICAL face (max |up.y| %.3f < 0.3)" % rec["climb_up_y"])
	_ok(float(rec["frame_err"]) < 0.02,
		"boxed in: body frame is square to the face, not lying on its side (max error %.4f)"
			% rec["frame_err"])

# --------------------------------------------------- E. the choice is actually random
func _random_choice() -> void:
	print("--- E. the same wall, 24 snails: left / right / climb all occur ---")
	# The defect this whole task is about was a snail that tracked ONE fixed response to a
	# wall. Same geometry, same approach, different seeds: the first decision must vary.
	_box(Vector3(130.0, 4.0, 6.0), Vector3(16.0, 8.0, 0.4))
	await get_tree().physics_frame
	var tally := {}
	for trial in range(24):
		var host := Node3D.new()
		add_child(host)
		host.global_position = Vector3(130.0, 0.02, 4.8)
		await get_tree().physics_frame
		var crawler: Object = BLOOM.GroundCrawler.new(host.global_position, 8.0, 0.35,
			1000 + trial * 37, 0.3, 0.15, 0.02, Vector3.ZERO)
		crawler.heading = Vector3(0.0, 0.0, 1.0)
		for i in range(400):
			crawler.tick(host, DT)
			if int(crawler.decisions) > 0:
				break
		var ch: String = String(crawler.choice)
		tally[ch] = int(tally.get(ch, 0)) + 1
		host.queue_free()
	print("      first decision over 24 trials: %s" % str(tally))
	var kinds: int = 0
	for k in ["left", "right", "climb"]:
		if tally.has(k):
			kinds += 1
	_ok(kinds >= 2, "the response to a wall varies between snails (%d of left/right/climb seen)" % kinds)
	_ok(tally.has("climb"), "climbing is one of the outcomes it actually rolls (%s)" % str(tally))
	_ok(tally.has("left") and tally.has("right"), "it turns both ways, not one fixed way (%s)" % str(tally))
