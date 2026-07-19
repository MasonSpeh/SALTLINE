extends Node
## FENG SHUI AUDIT — measures whether the rig's dressing is actually PLACED.
##
## Run: godot --headless --path . res://tests/PlacementProbe.tscn
##
## Two lists, both of which should read 0:
##   FLOATING — a loose object whose underside hangs more than TOL above the surface
##              beneath it. Support is resolved from VISUAL geometry (SupportIndex), not
##              from colliders: this rig's furniture is mostly non-colliding, so the old
##              collider-based version of this probe measured the deck under a desk and
##              reported every desk item as "resting" while calling shelf items floating.
##              Its absolute number was meaningless. This one agrees with what you see.
##   BLOCKING — a loose object standing in the middle 1.2m of a living corridor. Corridors
##              are for walking; furniture belongs on the wall line, clutter belongs in the
##              rooms it came from.
##
## Exempt by design: anything in the "placement_exempt" group (wall-mounted and hanging
## dressing declares itself), thin vertical panels (posters, boards, mirrors), fauna and
## weather, structure and furniture too big to be clutter, and anything with no visual
## surface at all within REACH below it — that is a hanging fixture, not a dropped mug.

const SUPPORT := preload("res://scripts/world/support_index.gd")

const TOL: float = 0.05            ## gap that counts as floating
const REACH: float = 2.0           ## no surface within this below => hanging, exempt
const CLUTTER_SPAN: float = 2.0    ## loose-object footprint cap (bigger = furniture)
const CLUTTER_H: float = 1.6

## FURNITURE floating: an object too big to be clutter still needs a foot on something.
## The float branch above skips anything over CLUTTER_SPAN/CLUTTER_H, which structurally
## excluded every exterior_dress assembly — pipe racks, gas cages, the gen set, the HVAC,
## the cargo basket, drums, the radome — from the audit that was being quoted as proof
## they do not float. They get their own, looser, check: a 3 m gen set resting 4 cm proud
## of its plinth is a modelling choice, one hanging 40 cm over the roof is a bug.
const FURN_SPAN: float = 12.0      ## bigger than this is structure, not placed furniture
const FURN_TOL: float = 0.18       ## gap that counts as a floating assembly
const FURN_REACH: float = 3.0      ## nothing within this below => it is a hung fixture

## PENETRATION: the float test only ever measured a POSITIVE gap, so an object driven
## THROUGH the surface it is supposed to rest on scored a perfect zero — which is how a
## coil of wire rope sunk into the boom-heel plate passed an audit reading FLOATING 0.
## Some interpenetration is correct (a plank lying across a frame, a bolt in a plate), so
## the threshold scales with the object: flag it once it is buried past a third of its own
## height, or past PEN_ABS, whichever is shallower.
const PEN_ABS: float = 0.10
const PEN_FRAC: float = 0.34
const BLOCK_SPAN: float = 4.0      ## blocking check also covers furniture-sized objects
const CONTAINER_CHILDREN: int = 40 ## a node with more children than this is a builder

## Living corridors: x range, FULL z bounds (wall to wall), floor Y. An object standing in
## one is only a problem if it doesn't leave a walkable lane past it, so the test is the
## clear width remaining on the wider side — a bench on the wall line passes, a table in
## the middle does not.
const CORRIDORS := [
	{"name": "A bunkhouse", "x0": -28.0, "x1": -8.0, "z0": 10.0, "z1": 12.0, "y": 18.0},
	{"name": "B quarters", "x0": -2.0, "x1": 28.0, "z0": 11.0, "z1": 13.0, "y": 21.6},
	{"name": "C control", "x0": 4.0, "x1": 28.0, "z0": 12.0, "z1": 14.0, "y": 25.1},
	{"name": "D works", "x0": 8.0, "x1": 23.0, "z0": 13.0, "z1": 15.0, "y": 28.6},
]
const WALK_H: float = 1.9          ## below this above the floor is walking volume
const MIN_CLEAR: float = 1.2       ## required walking width past anything in a corridor

func _ready() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	# The dressing streams in a few props per frame and settles itself at the end of the
	# stream; give it room, plus physics ticks so SurfaceSnap has run and rigid props rest.
	# The world build grew a lot (seabed, reef, exterior dressing) and now takes ~25s;
	# an 8s wait made this probe report against a half-built rig, or hang outright.
	await get_tree().create_timer(30.0).timeout
	for i in range(10):
		await get_tree().physics_frame

	var index = SUPPORT.new()
	index.build(main)

	var objects: Array = _objects(main)
	var floating: Array = []
	var blocking: Array = []
	var scenery_float: Array = []
	var scenery_block: Array = []
	var on_floor: Array = []
	var furniture: Array = []      ## managed assemblies bigger than clutter, hanging free
	var penetrating: Array = []    ## managed objects driven THROUGH their support
	var checked: int = 0
	var furn_checked: int = 0
	var hanging: int = 0

	for o in objects:
		var node: Node3D = o
		var a: AABB = SUPPORT.world_aabb_of_tree(node)
		if a.size == Vector3.ZERO or a.position.y < 0.5:
			continue
		# Placed objects — dressing props, pickups, grabbables — are what the placement
		# system owns and what this probe drives to zero. Bare CSG/mesh decoration built
		# into the rooms by the structure builders is reported separately: it is somebody
		# else's file, and much of it (books in a case, tools on a pegboard) is drawn
		# inside its furniture rather than resting on it.
		var managed: bool = _managed(node)
		var span: float = maxf(a.size.x, a.size.z)
		# --- BLOCKING: does it leave a walkable lane past it?
		if span <= BLOCK_SPAN and a.size.y > 0.06:
			var cor: String = _corridor_hit(a)
			if cor != "":
				var line: String = "%-28s %-12s at %s  size %.2fx%.2f" % [
					_label(node), cor, _v(a.get_center()), a.size.x, a.size.z]
				if managed:
					blocking.append(line)
				else:
					scenery_block.append(line)
		# --- FLOATING FURNITURE: assemblies too big to be clutter still need a foot on
		# something. Reported separately because the tolerance has to be looser — this
		# catches a gen set hanging over a roof, not a 3 cm modelling gap under a plinth.
		if span > CLUTTER_SPAN or a.size.y > CLUTTER_H:
			if managed and span <= FURN_SPAN and not _exempt(node) \
					and not SUPPORT.is_wall_panel(a) and not _simulated(node):
				var ftop: float = index.support_top(a, node, 0.0)
				if ftop != -INF and a.position.y - ftop <= FURN_REACH:
					furn_checked += 1
					var fgap: float = a.position.y - ftop
					if fgap > FURN_TOL:
						furniture.append("%-28s gap=%.3f  at %s  size %.1fx%.1fx%.1f  (%s)" % [
							_label(node), fgap, _v(a.get_center()),
							a.size.x, a.size.y, a.size.z, _owner(node)])
					else:
						var ctop: float = _centre_support(index, a, node)
						if ctop != -INF and a.position.y - ctop < -_pen_limit(a):
							penetrating.append("%-28s sunk=%.3f  at %s  size %.1fx%.1fx%.1f  (%s)" % [
								_label(node), ctop - a.position.y, _v(a.get_center()),
								a.size.x, a.size.y, a.size.z, _owner(node)])
			continue
		if _exempt(node) or SUPPORT.is_wall_panel(a) or _simulated(node):
			continue
		var top: float = index.support_top(a, node, 0.0)
		if managed:
			checked += 1
		if top == -INF or a.position.y - top > REACH:
			hanging += 1
			continue
		# Advisory: tabletop-sized clutter that ended up lying on a deck. Not a bug on a
		# working deck, but a mug or a pair of spectacles on the floor of a cabin is one.
		if managed and maxf(a.size.x, a.size.z) < 0.7 and a.size.y < 0.5 and _on_deck(top):
			on_floor.append("%-28s at %s" % [_label(node), _v(a.get_center())])
		var gap: float = a.position.y - top
		if gap > TOL:
			var f: String = "%-28s gap=%.3f  at %s  (%s)" % [
				_label(node), gap, _v(a.get_center()), _owner(node)]
			if managed:
				floating.append(f)
			else:
				scenery_float.append([gap, f])
		elif managed:
			# Driven THROUGH its support rather than resting on it. Invisible to the float
			# test, which only ever measured a positive gap.
			var ctop: float = _centre_support(index, a, node)
			if ctop != -INF and a.position.y - ctop < -_pen_limit(a):
				penetrating.append("%-28s sunk=%.3f  at %s  size %.2fx%.2fx%.2f  (%s)" % [
					_label(node), ctop - a.position.y, _v(a.get_center()),
					a.size.x, a.size.y, a.size.z, _owner(node)])

	floating.sort()
	blocking.sort()
	furniture.sort()
	penetrating.sort()
	print("--- placement probe (visual-support) ---")
	print("support surfaces indexed: ", index.surface_count())
	print("placed objects checked: ", checked, "   (hanging/exempt-by-reach: ", hanging, ")")
	print("FLOATING: ", floating.size())
	for f in floating.slice(0, 40):
		print("   ", f)
	print("BLOCKING: ", blocking.size())
	for b in blocking.slice(0, 40):
		print("   ", b)
	print("furniture-sized assemblies checked: ", furn_checked)
	print("FLOATING FURNITURE: ", furniture.size())
	for f in furniture.slice(0, 40):
		print("   ", f)
	print("PENETRATING: ", penetrating.size())
	for p in penetrating.slice(0, 40):
		print("   ", p)
	on_floor.sort()
	print("ADVISORY small items resting on a deck: ", on_floor.size())
	for f in on_floor.slice(0, 40):
		print("   ", f)
	print("-- structure-builder decoration (not placement-managed; hand-off only) --")
	print("scenery floating: ", scenery_float.size(), "   scenery blocking: ", scenery_block.size())
	for b in scenery_block.slice(0, 10):
		print("   ", b)
	# Worst-gap first. A bare count is not a hand-off — most of this list is decoration
	# drawn INSIDE its furniture (books in a case, tools on a board) and reads correctly
	# in game, so whoever picks this up needs the big gaps, which are the real ones.
	scenery_float.sort_custom(func(a, b): return a[0] > b[0])
	print("   worst 25 by gap:")
	for e in scenery_float.slice(0, 25):
		print("      ", e[1])
	get_tree().quit(0)

## Deck slab levels: a support top at one of these is the floor, not furniture.
const DECKS := [2.0, 6.0, 10.0, 18.0, 21.6, 25.1, 28.6, 32.1]

## How deep an object may sink into its support before it counts as interpenetration. A
## plank lying across a frame legitimately overlaps it by its own thickness; a coil of rope
## buried to a third of its height does not.
func _pen_limit(a: AABB) -> float:
	return minf(PEN_ABS, maxf(a.size.y * PEN_FRAC, 0.02))

## Penetration depth under an object's CENTRE COLUMN, or -INF if nothing is under it.
##
## Support has to be resolved from a narrow column here, not from the full AABB the float
## test uses. Full-AABB resolution answers "is there anything at all beneath this footprint",
## which is the right question for floating and the wrong one for burial: it fires on any
## low object that merely clips a corner of the footprint. Both of the first hits this check
## produced were that artefact — a cable tray terminating inside the radome's tripod base,
## and a roof ladder standing on the deck beside a low kerb — neither of which is buried in
## anything. A column at 30% of the footprint only sees what the object is actually sitting
## on top of.
func _centre_support(index, a: AABB, node: Node) -> float:
	var c: Vector3 = a.get_center()
	var hx: float = maxf(a.size.x * 0.15, 0.02)
	var hz: float = maxf(a.size.z * 0.15, 0.02)
	var col := AABB(Vector3(c.x - hx, a.position.y, c.z - hz),
		Vector3(hx * 2.0, a.size.y, hz * 2.0))
	return index.support_top(col, node, 0.0)

func _on_deck(top: float) -> bool:
	for d in DECKS:
		if absf(top - d) < 0.14:
			return true
	return false

## Objects physics is actively simulating settle themselves; measuring them mid-bounce
## says nothing about how the world was authored.
func _simulated(n: Node) -> bool:
	var rb := n as RigidBody3D
	return rb != null and not rb.freeze

## Objects the placement system is responsible for: everything the dressing pass spawns,
## plus every physical/interactive body (pickups, grabbables, crates, benches).
func _managed(n: Node) -> bool:
	return n.is_in_group("dress_prop") or n is CollisionObject3D

# ---------------------------------------------------------------- object enumeration

## One entry per placed OBJECT, not per mesh: walk up from each drawn surface to the
## outermost node that still belongs to a single prop (its parent being a builder node
## with many children marks the boundary).
func _objects(root: Node) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if _skip_subtree(n):
			continue
		for c in n.get_children():
			stack.append(c)
		if not SUPPORT.is_geometry(n):
			continue
		var obj: Node = _object_root(n, root)
		if obj == null or not (obj is Node3D) or seen.has(obj.get_instance_id()):
			continue
		seen[obj.get_instance_id()] = true
		out.append(obj)
	return out

func _object_root(n: Node, root: Node) -> Node:
	var cur: Node = n
	while cur.get_parent() != null and cur.get_parent() != root:
		var p: Node = cur.get_parent()
		if p.get_child_count() > CONTAINER_CHILDREN:
			return cur
		cur = p
	return cur

func _skip_subtree(n: Node) -> bool:
	if n.is_in_group("player") or n.is_in_group("floating_debris") \
			or n.is_in_group("gyre_streaks") or n.is_in_group("lit_flares"):
		return true
	var s: Script = n.get_script() as Script
	if s != null:
		for frag in SUPPORT.SKIP_SCRIPTS:
			if s.resource_path.ends_with(frag):
				return true
	return false

# ---------------------------------------------------------------- predicates

func _exempt(n: Node) -> bool:
	var cur: Node = n
	while cur != null:
		if cur.is_in_group("placement_exempt"):
			return true
		cur = cur.get_parent()
	return false

func _corridor_hit(a: AABB) -> String:
	var c: Vector3 = a.get_center()
	for cor in CORRIDORS:
		var fy: float = cor["y"]
		if a.position.y < fy - 0.4 or a.position.y > fy + WALK_H:
			continue
		if c.x < cor["x0"] or c.x > cor["x1"]:
			continue
		var z0: float = cor["z0"]
		var z1: float = cor["z1"]
		if a.position.z + a.size.z <= z0 or a.position.z >= z1:
			continue
		# Walk past on whichever side is wider; that lane must stay at least MIN_CLEAR.
		var clear: float = maxf(a.position.z - z0, z1 - (a.position.z + a.size.z))
		if clear >= MIN_CLEAR:
			continue
		return cor["name"]
	return ""

# ---------------------------------------------------------------- reporting

func _label(n: Node) -> String:
	var s: String = n.name
	if n.has_method("get") and n.get("display_name") != null and str(n.get("display_name")) != "":
		s = "%s[%s]" % [n.name, n.get("display_name")]
	return s.substr(0, 28)

func _owner(n: Node) -> String:
	var p: Node = n.get_parent()
	return p.name if p != null else "?"

func _v(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]
