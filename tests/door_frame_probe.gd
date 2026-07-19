extends Node
## DOORFRAME AUDIT — every opening on the rig must be a hole its casing actually fits.
##
## Run: godot --headless --path . res://tests/DoorFrameProbe.tscn
##
## The class of bug this exists to prevent from coming back: frames that were authored
## beside the hole they were meant to line instead of derived from it. Heads floating
## above their openings, jambs overshooting the corner and leaving a stub of steel in
## open air, casings z-fighting the wall face they sat flush with. All three are the same
## defect — two independent sets of numbers for one rect — and all three are invisible to
## every other probe here, because the geometry is perfectly valid, just wrong.
##
## Every opening registers itself in group DoorFrame.GROUP carrying the rect it was cut
## from (see scripts/world/door_frame.gd). This walks that list and asserts five things:
##
##   1. SIDES     the casing brackets the opening width exactly — reaches both edges,
##                protrudes past neither by more than TOL.
##   2. HEIGHT    it stands on the floor and tops out at the head of the opening.
##   3. DEPTH     it is centred on the wall plane and stands PROUD of both faces, so no
##                frame face is ever coplanar with a wall face (coplanar faces z-fight).
##   4. CORNERS   the head's underside lands on the jamb tops and its ends land on the
##                jamb outers: the two corners butt-join closed, no gap, no overshoot.
##   5. WALL      — the one that catches the real bug — the wall must actually CLOSE
##                around the hole. A ray fired along the wall axis out of the middle of
##                the opening has to strike wall at exactly half the opening's width. If
##                it flies off into the sea, the hole ran past the end of its wall and
##                the jamb standing there is hanging in space.
##
## FAILURES must read 0. An opening that does not come through DoorFrame is invisible
## here, so route openings through it rather than around it.

const SUPPORT := preload("res://scripts/world/support_index.gd")
const FRAME := preload("res://scripts/world/door_frame.gd")

const TOL: float = 0.02          ## the owner's "clean corners" tolerance: 2cm
const JOIN_TOL: float = 0.01     ## head/jamb butt joint — tighter, it is one weld
const WALL_TOL: float = 0.06     ## a wall's cut face may sit a little proud of the hole
const RAY_LEN: float = 30.0

var _fails: Array[String] = []
var _checked: int = 0

func _ready() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	# CSG rebuilds and the dressing stream both need a moment; the ray test reads real
	# collision, so give physics time to have baked the CSG walls into the world.
	await get_tree().create_timer(6.0).timeout
	for i in range(10):
		await get_tree().physics_frame

	var frames: Array = get_tree().get_nodes_in_group(FRAME.GROUP)
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	# Everything with a CollisionObject3D node is a prop, a rail guard, a hinged leaf or
	# a pickup — never structure. The rig's walls are CSG shapes, which register their
	# collision without a node, so excluding all of these leaves exactly the masonry.
	var exclude: Array[RID] = _collision_object_rids(main)

	for f in frames:
		var node := f as Node3D
		if node == null:
			continue
		_checked += 1
		_check(node, space, exclude)

	_fails.sort()
	print("--- door frame probe ---")
	print("openings audited: ", _checked)
	print("FAILURES: ", _fails.size())
	for f in _fails:
		print("   ", f)
	get_tree().quit(0)

func _check(f: Node3D, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> void:
	var c: Vector3 = f.get_meta("open_center")
	var along_x: bool = f.get_meta("open_along_x")
	var w: float = f.get_meta("open_w")
	var h: float = f.get_meta("open_h")
	var t: float = f.get_meta("open_t")
	var ax: int = 0 if along_x else 2          # along the wall
	var nx: int = 2 if along_x else 0          # through the wall
	var id: String = "%s %s w=%.2f h=%.2f" % [f.get_parent().name, _v(c), w, h]

	var a: AABB = SUPPORT.world_aabb_of_tree(f)
	if a.size == Vector3.ZERO:
		_fail(id, "casing has no geometry at all")
		return

	# 1. SIDES — reaches both edges of the opening, protrudes past neither.
	var half: float = w * 0.5
	_near(id, "casing west/south edge", a.position[ax], c[ax] - half, TOL)
	_near(id, "casing east/north edge", a.position[ax] + a.size[ax], c[ax] + half, TOL)

	# 2. HEIGHT — stands on the floor, tops out at the head of the opening.
	_near(id, "casing foot", a.position.y, c.y, TOL)
	_near(id, "casing head", a.position.y + a.size.y, c.y + h, TOL)

	# 3. DEPTH — centred on the wall plane, proud of both faces.
	_near(id, "casing centre through wall", a.position[nx] + a.size[nx] * 0.5, c[nx], TOL)
	_near(id, "casing depth", a.size[nx], t + FRAME.PROUD * 2.0, TOL)

	# 4. CORNERS — head sits on the jambs and ends flush with their outers.
	_check_corners(f, id, ax)

	# 5. WALL — the hole is a hole IN something, on both sides.
	var origin: Vector3 = c + Vector3(0, h * 0.5, 0)
	for dir_sign in [-1.0, 1.0]:
		var dir := Vector3.ZERO
		dir[ax] = dir_sign
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * RAY_LEN)
		q.exclude = exclude
		q.hit_from_inside = false
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			_fail(id, "no wall %s of the opening — the hole runs off the end of its wall and this jamb hangs in space" % _side(ax, dir_sign))
			continue
		var d: float = origin.distance_to(hit["position"])
		if d > half + WALL_TOL:
			_fail(id, "wall %s of the opening starts %.2fm out, %.2fm past the jamb — hole is wider than its casing" % [_side(ax, dir_sign), d, d - half])
		elif d < half - TOL:
			_fail(id, "wall %s of the opening intrudes %.2fm inside the casing" % [_side(ax, dir_sign), half - d])

## The head must land ON the jambs, and end WITH them. Members are identified by height:
## the head is the tallest-topped one, the jambs are whatever tops out at the head's
## underside, and the sill (if any) sits below them all.
func _check_corners(f: Node3D, id: String, ax: int) -> void:
	var parts: Array = []
	for child in f.get_children():
		if child is MeshInstance3D:
			parts.append(SUPPORT.world_aabb_of(child))
	if parts.size() < 3:
		_fail(id, "casing has %d members — a frame is a head and two jambs at minimum" % parts.size())
		return
	var head: AABB = parts[0]
	for p in parts:
		if p.position.y + p.size.y > head.position.y + head.size.y:
			head = p
	var soffit: float = head.position.y
	var jambs: Array = []
	for p in parts:
		if p != head and absf(p.position.y + p.size.y - soffit) <= JOIN_TOL:
			jambs.append(p)
	if jambs.size() != 2:
		_fail(id, "head underside meets %d jamb tops, not 2 — the corners do not close" % jambs.size())
		return
	# Ends flush: each jamb's OUTER edge lands on the head's matching end.
	var lo: AABB = jambs[0] if jambs[0].position[ax] < jambs[1].position[ax] else jambs[1]
	var hi: AABB = jambs[1] if lo == jambs[0] else jambs[0]
	_near(id, "head overshoots past the low corner", head.position[ax], lo.position[ax], TOL)
	_near(id, "head overshoots past the high corner",
		head.position[ax] + head.size[ax], hi.position[ax] + hi.size[ax], TOL)
	# Jambs must run all the way DOWN, not stop in mid air above the floor.
	for j in jambs:
		_near(id, "jamb foot", j.position.y, f.get_meta("open_center").y, TOL)

func _near(id: String, what: String, got: float, want: float, tol: float) -> void:
	if absf(got - want) > tol:
		_fail(id, "%s off by %.3fm (%.3f vs %.3f)" % [what, got - want, got, want])

func _fail(id: String, msg: String) -> void:
	_fails.append("%-52s %s" % [id, msg])

func _side(ax: int, s: float) -> String:
	if ax == 0:
		return "west" if s < 0.0 else "east"
	return "south" if s < 0.0 else "north"

func _collision_object_rids(root: Node) -> Array[RID]:
	var out: Array[RID] = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var co := n as CollisionObject3D
		if co != null:
			out.append(co.get_rid())
	return out

func _v(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]
