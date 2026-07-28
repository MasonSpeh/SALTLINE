extends Node
## ACCESS PROBE — physics ground truth for the crane's TWO ladder hatches, the way down off
## the machinery deck (y 34.15) and off the mid landing (y 26.0). Each floor in turn was
## one solid plate with a ladder topping out INSIDE its footprint, so there was no opening:
## you could climb up (climbing runs with world collision off) and then had no way back
## down but a 16 m / 8 m drop.
##
## The mid-landing half of this probe does not stop at geometry. The landing's trap was not
## only "no hole" — it was also "no rungs you can point at", because the two runs were
## stacked on one axis and the UPPER run stood in the sight-line to the lower one. Rays
## through an empty hatch would have passed that. So the landing section also DRIVES THE
## REAL PLAYER down the real climb code (see _drive_descent), which is the only thing that
## proves a descent, and asserts the whole drop happened at CLIMB_SPEED — a fall would
## reach the deck too, faster, which is exactly the bug.
##
## USE RAYS, NOT SHAPE QUERIES. Every structural box here is a CSGBox3D, and CSG collision
## is baked to a ConcavePolygonShape3D — a one-sided trimesh. `intersect_shape` against a
## trimesh does not reliably report containment, so an earlier version of this probe called
## the deck "not solid" in three places out of four and looked like a catastrophic bug.
## `intersect_ray` handles trimesh correctly. Do not reintroduce shape queries here.
##
## The machine-shop roof ladder's blockers (cable tray, conduit) are NON-COLLIDING dressing
## and are therefore invisible to physics entirely — that fix is verified geometrically off
## the sonar scan (AABB overlap against the climb corridor), not here.
##
## Run headless: godot --headless --path . res://tests/access_probe.tscn

const SETTLE_SEC: float = 5.0
## Hatch cut in the machinery deck, mirroring rig_builder's CRANE_HATCH_* constants.
const HX0: float = -0.95
const HX1: float = 0.15
const HZ0: float = -15.35
const HZ1: float = -13.85
const PLATE_TOP: float = 34.15
## Hatch cut in the mid landing, mirroring rig_builder's LAND_HATCH_* constants.
const LX0: float = 4.35
const LX1: float = 5.0
const LZ0: float = -14.75
const LZ1: float = -13.25
const LAND_TOP: float = 26.0
const LAND_LADDER_X: float = 4.675     ## descent run axis
const LAND_EXIT_X: float = 3.675       ## where both of its mantles put you (x - exit_forward)
const DECK_TOP: float = 18.0
const CRANE_X_T: float = 2.0           ## rig_builder CRANE_X — the tower/slew axis
const CAP_R: float = 0.4               ## Player.tscn CapsuleShape3D.radius
const CAP_H: float = 1.8               ## PlayerController.STAND_HEIGHT
const CLIMB_SPEED: float = 1.8         ## PlayerController.CLIMB_SPEED
## Machinery deck. The upper run is mounted flush to the hatch's NORTH cheek (not down the
## middle of the hole — see rig_builder.CRANE_LADDER_Z) at x -0.40 / z -14.025, facing north,
## with exit_forward 0.825, so both its mantles still land at z -13.2.
const UP_LADDER := Vector2(-0.40, -14.025)
const UP_LADDER_HEAD: float = 34.35               ## stiles stand 0.20 m proud of the plate
const UP_LADDER_FACE: float = -14.20              ## south face of its 0.35 m-deep climb box
## The clear half of the hatch: everything south of the ladder's face, which is the lane a
## body actually descends through. 1.10 m (x) x 1.15 m (z) against a 0.80 m-wide capsule.
const DESCENT_LANE := Vector2(-0.40, -14.775)
const DECK_EXIT := Vector3(-0.40, 34.75, -13.2)   ## machinery-deck mantle spot
const KING_POST_R: float = 1.15        ## rig_builder KING_POST_R
const RACE_R1: float = 1.85            ## rig_builder RACE_R1
const RACE_PROUD: float = 0.10         ## race height — must stay under the capsule roll-up

var _fails: int = 0
var _t: float = 0.0
var _ran: bool = false
var _main: Node3D

func _ready() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	add_child(_main)

func _process(delta: float) -> void:
	if _ran:
		return
	_t += delta
	if _t < SETTLE_SEC:
		return
	_ran = true
	_finish()

func _finish() -> void:
	_run()
	await _run_landing()
	await _run_perimeter()
	print("\n[access_probe] FAILURES: %d" % _fails)
	get_tree().quit()

## THE TOPSIDE PERIMETER GUARD still guards. rig_builder._build_topside() used to fence the
## deck with a single colliding 0.12 m bar at waist height — the shape a capsule wedges
## under — and now fences it the way the rest of the rig does: visual steel plus one smooth
## full-height slab, shaved back RAIL_END_SHAVE at each end so a diagonal past a junction
## slides instead of catching. Swapping a collider for a different collider is exactly the
## edit that quietly turns a deck into a hole, so walk into all four runs and check.
##
## The three numbers that matter: you must NOT end up in the sea, you must NOT end up past
## the rail line, and you must actually be STOPPED (a guard you slide along forever is fine;
## one you walk through is not).
const TOPSIDE_Y: float = 18.0
func _run_perimeter() -> void:
	print("\n=== topside perimeter rail: rebuilt collision still stops you at the edge ===")
	var p: CharacterBody3D = _main.get("player") as CharacterBody3D
	if p == null:
		_check("player found", false)
		return
	p.input_locked = false
	# [label, start x, start z, yaw (faces the rail), axis, rail coordinate, outward sign]
	for spec in [["south rail  (z -19.8)", 0.0, -18.2, 0.0, "z", -19.8, -1.0],
			["north rail  (z  19.8)", 0.0, 18.2, PI, "z", 19.8, 1.0],
			["west rail   (x -29.8)", -28.2, 0.0, PI / 2.0, "x", -29.8, -1.0],
			["east rail   (x  29.8)", 28.2, 6.0, -PI / 2.0, "x", 29.8, 1.0]]:
		p.global_position = Vector3(float(spec[1]), TOPSIDE_Y + 0.1, float(spec[2]))
		p.velocity = Vector3.ZERO
		p.rotation.y = float(spec[3])
		await _settle(20)
		if absf(p.global_position.y - TOPSIDE_Y) > 0.5:
			_check("%s — start point is on the topside deck" % spec[0], false,
				"y%.2f" % p.global_position.y)
			continue
		Input.action_press("move_forward")
		for i in range(150):     # 5 s at 30 Hz — long enough to cross 1.6 m at walk pace
			await get_tree().physics_frame
			if p.global_position.y < TOPSIDE_Y - 2.0:
				break
		Input.action_release("move_forward")
		await _settle(10)
		var out: float = p.global_position.x if String(spec[4]) == "x" else p.global_position.z
		var rail: float = float(spec[5])
		var sign_: float = float(spec[6])
		_check("%s — did not fall off the deck" % spec[0],
			p.global_position.y > TOPSIDE_Y - 1.0, "ended at y%.2f" % p.global_position.y)
		_check("%s — stopped inboard of the rail line" % spec[0],
			(out - rail) * sign_ < 0.0,
			"walked to %s %.2f, rail is at %.2f" % [spec[4], out, rail])
	Input.action_release("move_forward")

## Height of the first surface under (x,z), or NAN if the column is empty down to y30.
func _floor_at(x: float, z: float) -> float:
	var space: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 35.4, z), Vector3(x, 30.0, z))
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	return NAN if hit.is_empty() else (hit["position"] as Vector3).y

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		_fails += 1
		print("FAIL  %s %s" % [label, detail])

func _run() -> void:
	print("\n=== CRANE machinery deck — the ladder hatch is a real hole ===")
	# Inside the hatch but CLEAR OF THE LADDER (its collider legitimately fills
	# x -0.75..-0.05, z -14.20..-13.85 — the north cheek — and stands 0.20 m proud).
	for p in [Vector2(-0.88, -14.60), Vector2(0.08, -14.60), Vector2(-0.40, -15.20),
			Vector2(-0.40, -14.90), DESCENT_LANE]:
		var y: float = _floor_at(p.x, p.y)
		_check("hatch open at (%.2f, %.2f)" % [p.x, p.y], is_nan(y),
			"found a surface at y%.2f" % y if not is_nan(y) else "")
	# The ladder must still be there, in the hole, to climb down — and its head must stand
	# PROUD of the plate rather than stopping flush with it, so it can be seen and aimed at
	# from standing height on the deck instead of only from inside the opening.
	var yl: float = _floor_at(UP_LADDER.x, UP_LADDER.y)
	_check("ladder is present inside the hatch", not is_nan(yl) and yl >= PLATE_TOP - 0.05,
		"ray down the ladder line found y%.2f" % yl)
	_check("ladder head stands proud of the plate, not flush with it",
		not is_nan(yl) and yl > PLATE_TOP + 0.1 and yl < PLATE_TOP + 0.45,
		"head at y%.2f, plate at %.2f" % [yl, PLATE_TOP])
	# ...and the plate all round it must still carry you.
	# NEVER sample a strip's exact CENTRE LINE. CSG boxes are triangulated, and a ray fired
	# straight down the middle of one can slip through the seam where the tessellation splits:
	# a 0.1 m sweep across the south strip returned solid 34.15 at every step except exactly
	# z -16.20, its centre. That is a degenerate ray-vs-trimesh hit, not a hole — but it will
	# read as "deck cut away" and send you hunting a bug that isn't there.
	for p in [Vector2(-1.30, -14.60), Vector2(-0.40, -16.20), Vector2(-0.40, -13.20),
			Vector2(-1.30, -11.00), Vector2(-1.30, -16.80)]:
		var y2: float = _floor_at(p.x, p.y)
		_check("plate solid at (%.2f, %.2f)" % [p.x, p.y],
			not is_nan(y2) and y2 >= PLATE_TOP - 0.05,
			"got y%.2f" % y2 if not is_nan(y2) else "NOTHING THERE — deck cut away")
	# You have to be able to stand beside the opening to get onto the rungs. NORTH lip now:
	# that is the side the run exits toward.
	var ys: float = _floor_at(-0.40, -13.60)
	_check("standing room on the hatch's north lip", not is_nan(ys),
		"nothing to stand on at (-0.40, -13.60)")

	print("\n=== the upper mast ladder head lands in the opening ===")
	var lad: Node3D = _find_ladder("Mast Ladder — Upper")
	_check("upper mast ladder exists", lad != null)
	if lad != null:
		var lp: Vector3 = lad.global_position
		var inside: bool = lp.x > HX0 and lp.x < HX1 and lp.z > HZ0 and lp.z < HZ1
		_check("ladder axis inside the hatch footprint", inside, "at %s" % str(lp.snappedf(0.01)))
		_check("ladder reaches the plate line",
			lp.y + float(lad.get("height")) >= PLATE_TOP,
			"top at y%.2f, plate at %.2f" % [lp.y + float(lad.get("height")), PLATE_TOP])
		# OFF-CENTRE, FLUSH TO THE NORTH CHEEK. This is the whole fix: a run standing on the
		# hatch's centre line splits a 1.50 m opening into two 0.575 m strips, and a player
		# capsule is 0.80 m across, so there is no route through the hole for a BODY — only
		# for the climb state, which turns world collision off and therefore hid it.
		_check("ladder is mounted on the hatch cheek, not down the middle",
			absf(lp.z - (HZ1 - 0.175)) < 0.02,
			"axis at z%.3f; flush to the north cheek is z%.3f" % [lp.z, HZ1 - 0.175])
		_check("nothing of the ladder overhangs the opening",
			lp.z + 0.175 <= HZ1 + 0.001,
			"climb box reaches z%.3f, cheek is at z%.3f" % [lp.z + 0.175, HZ1])

	print("\n=== a player-sized body actually FITS down the crane hatch ===")
	# The assertion the old probe never made, and the reason the owner ended up stranded on
	# the crane. Every earlier check here was a RAY — rays are 0 m wide and will happily
	# thread a gap no body can use. These are the real capsule, in the real descent lane,
	# straddling the plate plane: feet below it, shoulders above it, which is the moment a
	# descending player is half in and half out of the hole.
	for feet_y in [PLATE_TOP - 1.6, PLATE_TOP - 0.85, PLATE_TOP - 0.4, PLATE_TOP + 0.05]:
		_clear_check("capsule fits in the descent lane with feet at y%.2f" % feet_y,
			Vector3(DESCENT_LANE.x, feet_y, DESCENT_LANE.y))
	# ...and it has slack, so this is a hatch and not a keyhole the next edit closes.
	for off in [Vector2(0.14, 0.0), Vector2(-0.14, 0.0), Vector2(0.0, -0.14)]:
		_clear_check("descent lane has slack at (%+.2f, %+.2f)" % [off.x, off.y],
			Vector3(DESCENT_LANE.x + off.x, PLATE_TOP - 0.85, DESCENT_LANE.y + off.y))
	# The lane must be open ABOVE the plate too — a coaming, a guard hoop or a rail closing
	# the top of the opening would mean you can never step over the lip onto the rungs.
	var cap_top: float = _surface(DESCENT_LANE.x, DESCENT_LANE.y, PLATE_TOP + 2.4, PLATE_TOP + 0.12)
	_check("nothing caps the hatch from above", is_nan(cap_top),
		"something at y%.2f is roofing the opening" % cap_top)

	print("\n=== the slew bearing is a race round a king post, not a 4 m plateau ===")
	# The old solid disc (r 1.95, 0.4 m proud) is why this deck could not be walked. What
	# replaced it has to keep BOTH properties: a king post you walk around, and a race low
	# enough to walk over. Sample along +X from the tower axis at z -14.
	var post_y: float = _floor_at(CRANE_X_T + 0.6, -14.0)
	_check("king post still carries the house", not is_nan(post_y) and post_y > PLATE_TOP + 0.3,
		"surface 0.6 m off the axis is y%.2f" % post_y)
	var race_y: float = _floor_at(CRANE_X_T + 1.65, -14.0)
	_check("race stands proud of the plate", not is_nan(race_y) and race_y > PLATE_TOP + 0.04,
		"surface at r1.65 is y%.2f" % race_y)
	_check("race is low enough to walk over",
		not is_nan(race_y) and race_y <= PLATE_TOP + RACE_PROUD + 0.02,
		"race top y%.2f is %.2f m proud — a 0.4 m capsule rolls up only ~0.117 m"
			% [race_y, race_y - PLATE_TOP])
	var open_y: float = _floor_at(CRANE_X_T + 2.35, -14.0)
	_check("plate is open again outside the race",
		not is_nan(open_y) and absf(open_y - PLATE_TOP) < 0.06,
		"surface at r2.35 is y%.2f" % open_y)
	# The readable that the solid disc swallowed must now sit on plate you can reach.
	var note: Node3D = _find_readable("lookout_note")
	_check("the lookout note exists", note != null)
	if note != null:
		var d: float = Vector2(note.global_position.x - CRANE_X_T,
			note.global_position.z + 14.0).length()
		_check("lookout note is clear of the bearing, not buried in it", d > RACE_R1 + 0.2,
			"only %.2f m from the tower axis (race outer %.2f)" % [d, RACE_R1])

func _find_readable(id: String) -> Node3D:
	for n in get_tree().root.find_children("*", "StaticBody3D", true, false):
		var v: Variant = n.get("readable_id")
		if v != null and String(v) == id:
			return n as Node3D
	return null

func _find_ladder(name_: String) -> Node3D:
	for n in get_tree().root.find_children("*", "StaticBody3D", true, false):
		var dn: Variant = n.get("display_name")
		if dn != null and String(dn) == name_:
			return n as Node3D
	return null


# ---------------------------------------------------------------- the mid landing (y26)

## First surface strictly between y_from and y_to under (x,z), or NAN for an empty column.
## Rays, not shape queries — see the header. Shape queries appear below ONLY to ask
## "does this capsule cross a surface", never "is this point inside a solid".
func _surface(x: float, z: float, y_from: float, y_to: float) -> float:
	var space: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, y_from, z), Vector3(x, y_to, z))
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	return NAN if hit.is_empty() else (hit["position"] as Vector3).y

## Does the PLAYER'S EXACT capsule fit with its feet here? radius 0.4, height 1.8,
## collider centred 0.9 above the feet (Player.tscn / PlayerController.STAND_COL_Y).
##
## Feet are lifted STAND_EPS off the quoted height before the query. A capsule whose
## bottom sits exactly on the floor plane is touching the floor, and intersect_shape says
## so — the first run of this probe read the landing grating as an obstruction under every
## spot a player can legitimately stand on. The lift is smaller than the step height, so
## nothing a capsule would really hit can hide under it.
const STAND_EPS: float = 0.05
func _capsule_clear(feet: Vector3) -> Array:
	var space: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = CAP_R
	cap.height = CAP_H
	var pq := PhysicsShapeQueryParameters3D.new()
	pq.shape = cap
	pq.transform = Transform3D(Basis(), feet + Vector3(0, CAP_H * 0.5 + STAND_EPS, 0))
	pq.collision_mask = 1
	# The player is a body on the same layer; without this every check made while the
	# player stands on the spot reports the player as the thing in the way.
	var pl: Node = _main.get("player") as Node
	if pl != null and pl is CollisionObject3D:
		pq.exclude = [(pl as CollisionObject3D).get_rid()]
	var res: Array[Dictionary] = space.intersect_shape(pq, 8)
	var names: PackedStringArray = PackedStringArray()
	for r in res:
		names.append(str((r["collider"] as Node).name))
	return [res.is_empty(), ", ".join(names)]

func _clear_check(label: String, feet: Vector3) -> void:
	var r: Array = _capsule_clear(feet)
	_check(label, bool(r[0]), "capsule at %s hits %s" % [str(feet.snappedf(0.01)), r[1]])

func _run_landing() -> void:
	print("\n=== CRANE mid landing (y26) — the descent hatch is a real hole ===")
	# Inside the hatch but CLEAR OF THE LADDER (its collider legitimately fills
	# x 4.50..4.85, z -14.35..-13.65 and tops out at the plate line).
	for p in [Vector2(4.42, -14.00), Vector2(4.92, -14.00), Vector2(4.675, -14.62),
			Vector2(4.675, -13.42)]:
		var y: float = _surface(p.x, p.y, 26.9, 19.5)
		_check("hatch open at (%.2f, %.2f)" % [p.x, p.y], is_nan(y),
			"found a surface at y%.2f" % y if not is_nan(y) else "")
	# The descent ladder must be there, in the hole, to climb down.
	var yl: float = _surface(LAND_LADDER_X, -14.0, 26.9, 19.5)
	_check("descent ladder is present inside the hatch",
		not is_nan(yl) and absf(yl - LAND_TOP) < 0.2,
		"ray down the ladder line found y%.2f" % yl)
	# ...and the grating all round it must still carry you. Never sample a strip's exact
	# centre line: a ray straight down the middle of a CSG box can slip through the seam
	# where its tessellation splits and read as a hole that is not there.
	for p in [Vector2(3.00, -14.20), Vector2(0.00, -13.00), Vector2(-1.00, -15.20),
			Vector2(4.45, -15.20), Vector2(4.90, -15.00), Vector2(4.45, -12.80),
			Vector2(4.90, -13.00)]:
		var y2: float = _surface(p.x, p.y, 26.9, 19.5)
		_check("landing solid at (%.2f, %.2f)" % [p.x, p.y],
			not is_nan(y2) and y2 >= LAND_TOP - 0.05,
			"got y%.2f" % y2 if not is_nan(y2) else "NOTHING THERE — landing cut away")

	print("\n=== the two runs are OFFSET, and the descent run spans deck to landing ===")
	var low: Node3D = _find_ladder("Mast Ladder")
	var up: Node3D = _find_ladder("Mast Ladder — Upper")
	_check("descent run exists", low != null)
	_check("upper run exists", up != null)
	if low != null and up != null:
		var lp: Vector3 = low.global_position
		_check("descent run axis inside the landing hatch",
			lp.x > LX0 and lp.x < LX1 and lp.z > LZ0 and lp.z < LZ1,
			"at %s" % str(lp.snappedf(0.01)))
		_check("descent run stands on the deck", absf(lp.y - DECK_TOP) < 0.05,
			"foot at y%.2f" % lp.y)
		_check("descent run reaches the landing line",
			absf(lp.y + float(low.get("height")) - LAND_TOP) < 0.2,
			"head at y%.2f" % (lp.y + float(low.get("height"))))
		# THE OFFSET ITSELF. Stacked on one axis, the upper run stands in the sight-line to
		# the lower one and you can never put a crosshair on the rungs going down. Two
		# capsule-widths apart is the assertion that keeps them apart.
		var gap: float = absf(lp.x - up.global_position.x)
		_check("runs offset by more than a body width", gap > 2.0 * CAP_R,
			"only %.2f m apart in x" % gap)

	print("\n=== a 0.4 m capsule fits where each mantle drops you ===")
	_clear_check("landing mantle spot (top of the descent run)",
		Vector3(LAND_EXIT_X, LAND_TOP + 0.4, -14.0))
	_clear_check("standing on the landing beside the hatch",
		Vector3(LAND_EXIT_X, LAND_TOP, -14.0))
	_clear_check("deck mantle spot (bottom of the descent run)",
		Vector3(LAND_EXIT_X, DECK_TOP + 0.1, -14.0))
	# 0.1 m of slack each way. The deck mantle sits between the rotary block's east face
	# (x 3.1) and the hatch coaming (x 4.26) with ~0.18 m either side; if a later edit
	# eats that, this is the assertion that says so instead of the player discovering it
	# as a capsule buried in the rotary block with no way out.
	for dx in [-0.1, 0.1]:
		_clear_check("deck mantle has %+.2f m of slack in x" % dx,
			Vector3(LAND_EXIT_X + dx, DECK_TOP + 0.1, -14.0))
		_clear_check("landing mantle has %+.2f m of slack in x" % dx,
			Vector3(LAND_EXIT_X + dx, LAND_TOP, -14.0))

	print("\n=== the descent corridor is clear the whole way down ===")
	for y in [18.0, 19.0, 21.0, 23.0]:
		_clear_check("corridor beside the rungs at y%.0f" % y,
			Vector3(LAND_EXIT_X, y, -14.0))

	await _drive_descent()
	await _drive_ascent()

## THE ONLY PROOF THAT COUNTS: put the real PlayerController on the machinery deck and
## drive it down both runs with the real climb code and real input actions, then check it
## arrived on the deck at CLIMB_SPEED. Geometry can be perfect and the route still be
## unusable — that is exactly what the stacked runs were — so this walks it.
##
## Nothing here jumps, and nothing teleports the player between rungs. The descent is
## start_climb() + held "interact" + "move_back", which is what a player's hands do.
func _drive_descent() -> void:
	print("\n=== driving the real player down: machinery deck -> landing -> deck ===")
	var p: CharacterBody3D = _main.get("player") as CharacterBody3D
	if p == null:
		_check("player found", false, "Main has no player")
		return
	p.input_locked = false
	p.global_position = Vector3(-0.40, PLATE_TOP + 0.05, -13.30)   # machinery deck, north hatch lip
	p.velocity = Vector3.ZERO
	await _settle(20)
	_check("player stands on the machinery deck",
		absf(p.global_position.y - PLATE_TOP) < 0.2, "y%.2f" % p.global_position.y)

	var upper: Node3D = _find_ladder("Mast Ladder — Upper")
	var lower: Node3D = _find_ladder("Mast Ladder")
	if upper == null or lower == null:
		_check("both mast runs found", false)
		return

	var top_fall: float = await _ride_down(p, upper, LAND_TOP)
	_check("rode the upper run down to the landing",
		absf(p.global_position.y - LAND_TOP) < 0.6,
		"ended at y%.2f" % p.global_position.y)
	_check("upper run was a CLIMB, not a fall (peak %.2f m/s)" % top_fall,
		top_fall <= CLIMB_SPEED + 0.6)
	var okc: Array = _capsule_clear(p.global_position)
	_check("landed on the landing without being buried", bool(okc[0]), str(okc[1]))

	# WALK east across the landing to the hatch. This is the leg the offset added, and a
	# rail post, the rigger's kit or the coaming catching the capsule would show up here
	# as a stall rather than as a slow crossing.
	var reached: bool = await _walk_route(p, [Vector2(LAND_EXIT_X, -14.0)])
	_check("walked east across the landing to the hatch lip", reached,
		"stopped at %s" % str(p.global_position.snappedf(0.01)))

	var low_fall: float = await _ride_down(p, lower, DECK_TOP)
	_check("rode the descent run down to the deck",
		absf(p.global_position.y - DECK_TOP) < 0.6,
		"ended at y%.2f" % p.global_position.y)
	_check("descent run was a CLIMB, not a fall (peak %.2f m/s)" % low_fall,
		low_fall <= CLIMB_SPEED + 0.6)
	var okd: Array = _capsule_clear(p.global_position)
	_check("stepped off onto open deck, not into the rotary block", bool(okd[0]), str(okd[1]))
	print("  final resting place: %s" % str(p.global_position.snappedf(0.01)))
	# Landing on a spot the capsule fits is not the same as landing somewhere you can
	# LEAVE. The deck mantle sits in the 1.5 m slot between the rotary block and the mast's
	# east leg line; walk out of it eastward to prove the slot is a route and not a pocket.
	# The mantle drops you in the slot between the rotary block (x 3.1), the mast's east
	# legs (z -16 / -12) and the run you just came off. It is a real route out, but not a
	# straight one — you step SOUTH of the ladder and then east onto open deck, which is
	# what a player does and what this walks.
	_check("can walk out of the deck slot onto open deck",
		await _walk_route(p, [Vector2(3.70, -14.90), Vector2(5.10, -14.90)]),
		"pinned at %s" % str(p.global_position.snappedf(0.01)))

## Latch the ladder and hold E+S until the run bottoms out. Returns the greatest downward
## speed seen — the fall/climb discriminator.
func _ride_down(p: CharacterBody3D, ladder: Node3D, target_y: float) -> float:
	p.call("start_climb", ladder)
	Input.action_press("interact")
	Input.action_press("move_back")
	var worst: float = 0.0
	for i in range(1200):
		await get_tree().physics_frame
		worst = maxf(worst, -p.velocity.y)
		if p.get("_climbing") == null and p.global_position.y <= target_y + 0.6:
			break
	Input.action_release("move_back")
	Input.action_release("interact")
	await _settle(40)
	return worst

## Hold E (no S) until the run tops out and mantles. Returns the peak downward speed,
## which must stay at zero-ish: a mantle that drops you is a mantle onto nothing.
func _ride_up(p: CharacterBody3D, ladder: Node3D, target_y: float) -> bool:
	p.call("start_climb", ladder)
	Input.action_press("interact")
	for i in range(1200):
		await get_tree().physics_frame
		if p.get("_climbing") == null and p.global_position.y >= target_y - 0.6:
			break
	Input.action_release("interact")
	await _settle(40)
	return absf(p.global_position.y - target_y) < 0.6

## Walk the real player to each waypoint in turn, steering every frame and holding W —
## no teleporting, no jumping. Returns false the moment a leg stops making progress, which
## is what a rail post, a coaming or a machine block catching the capsule looks like.
func _walk_route(p: CharacterBody3D, route: Array) -> bool:
	Input.action_press("move_forward")
	var ok: bool = true
	for wp in route:
		var target: Vector2 = wp
		var best: float = INF
		var stalled: int = 0
		var got: bool = false
		for i in range(900):
			var here := Vector2(p.global_position.x, p.global_position.z)
			var d: Vector2 = target - here
			if d.length() < 0.35:
				got = true
				break
			# forward is -Z: yaw so that -Z points at the waypoint.
			p.rotation.y = atan2(-d.x, -d.y)
			await get_tree().physics_frame
			var dist: float = (target - Vector2(p.global_position.x, p.global_position.z)).length()
			if dist < best - 0.01:
				best = dist
				stalled = 0
			else:
				stalled += 1
				if stalled > 120:      # 2 s of no closing = caught on something
					break
		if not got:
			ok = false
			break
	Input.action_release("move_forward")
	await _settle(20)
	return ok

## The climb has to work in both directions. Moving the lower run east could have fixed
## the way down and broken the way up — this drives the whole ascent back, deck to crane.
func _drive_ascent() -> void:
	print("\n=== driving the real player back up: deck -> landing -> machinery deck ===")
	var p: CharacterBody3D = _main.get("player") as CharacterBody3D
	var lower: Node3D = _find_ladder("Mast Ladder")
	var upper: Node3D = _find_ladder("Mast Ladder — Upper")
	if p == null or lower == null or upper == null:
		_check("player and both runs found", false)
		return
	p.global_position = Vector3(LAND_EXIT_X, DECK_TOP + 0.05, -14.0)
	p.velocity = Vector3.ZERO
	await _settle(20)
	_check("climbed the descent run back up to the landing",
		await _ride_up(p, lower, LAND_TOP), "ended at y%.2f" % p.global_position.y)
	# Cross back west to the upper run. Its mantle drops you at x 0.85, so aim short of it.
	_check("walked west across the landing to the upper run",
		await _walk_route(p, [Vector2(0.85, -14.0)]), "stopped at x%.2f" % p.global_position.x)
	_check("climbed the upper run back onto the machinery deck",
		await _ride_up(p, upper, PLATE_TOP), "ended at y%.2f" % p.global_position.y)
	var ok: Array = _capsule_clear(p.global_position)
	_check("standing free on the machinery deck", bool(ok[0]), str(ok[1]))
	print("  final resting place: %s" % str(p.global_position.snappedf(0.01)))
	# ARRIVING IS NOT THE SAME AS BEING ABLE TO USE THE DECK. This is the assertion that
	# used to be a NOTE reading "moved the player 0.00 m": the run mantled you into the
	# turret's AABB, _dismount_clear() rejected all nine candidates, the last resort dropped
	# you on the ladder head, and the machine walled you in on every side. Measure it now.
	#
	# East and west are SHORT here on purpose and always will be: the arrival lane is the
	# 2 m gap between the deck's west guard rail and the turret's west face, so those two
	# numbers are the machine and the handrail, not a bug. North and south are the deck.
	var walks: Dictionary = {}
	for d in ["N", "S", "E", "W"]:
		walks[d] = await _walk_dir(p, DECK_EXIT, d)
	print("  walk-off from the machinery-deck mantle spot: N %.2fm  S %.2fm  E %.2fm  W %.2fm"
		% [walks["N"], walks["S"], walks["E"], walks["W"]])
	var real_dirs: int = 0
	for d in ["N", "S", "E", "W"]:
		if float(walks[d]) >= 1.5:
			real_dirs += 1
	_check("can walk a real distance off the mantle spot in more than one direction",
		real_dirs >= 2, "only %d direction(s) cleared 1.5 m: %s" % [real_dirs, str(walks)])
	_check("north off the mantle spot is open deck, not a wall",
		float(walks["N"]) >= 1.5, "%.2f m" % float(walks["N"]))
	_check("south off the mantle spot is open deck, not a wall",
		float(walks["S"]) >= 1.5, "%.2f m" % float(walks["S"]))

	# ...and the deck must be ONE floor, not a set of pens. Walk from the arrival, round the
	# turret's west side, along the north band and back down the east side to the cab —
	# the route to the deep rig pole and the crane cab, which is the reason to be up here.
	p.global_position = DECK_EXIT
	p.velocity = Vector3.ZERO
	await _settle(20)
	_check("the machinery deck is one connected floor (arrival -> north band -> cab side)",
		await _walk_route(p, [Vector2(-0.40, -11.20), Vector2(4.60, -11.20), Vector2(4.60, -13.00)]),
		"stopped at %s" % str(p.global_position.snappedf(0.01)))

	# The race has to be walked OVER, not stopped at. From 0.75 m south of it, a player who
	# gets more than 0.9 m has crossed the band and been stopped by the king post beyond it;
	# a player stopped by the race itself gets ~0.75 m.
	var over: float = await _walk_dir(p, Vector3(CRANE_X_T, PLATE_TOP + 0.05, -16.6), "N")
	print("  north from 0.75 m south of the race: %.2f m" % over)
	_check("the bearing race is walked over, not stopped at", over > 0.9,
		"only %.2f m — the race is behaving like a wall again" % over)

## Drop the player at `feet`, face one compass direction and hold W for 6 s. Returns the
## distance travelled, or a NEGATIVE distance if they left the deck downward.
func _walk_dir(p: CharacterBody3D, feet: Vector3, dir_name: String) -> float:
	var yaw: float = {"E": -PI / 2, "W": PI / 2, "S": 0.0, "N": PI}[dir_name]
	p.global_position = feet
	p.velocity = Vector3.ZERO
	p.rotation.y = yaw
	await _settle(20)
	var from: Vector3 = p.global_position
	Input.action_press("move_forward")
	var fell: bool = false
	for i in range(180):
		await get_tree().physics_frame
		if p.global_position.y < PLATE_TOP - 2.0:
			fell = true
			break
	Input.action_release("move_forward")
	await _settle(10)
	var moved: float = Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length()
	return -moved if fell else moved

func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame
