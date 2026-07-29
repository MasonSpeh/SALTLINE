extends Node
## Ground truth for the caisson-leg reef and the foundation starfish.
##
## Everything this file measures used to be a hand-typed constant somewhere. The
## reef has to start BELOW the existing kelp/grass, sit FLUSH on the real concrete
## and never stand in a route — none of which can be read off builder source,
## because the vegetation is procedural and the leg faces are one fused casting.
##
## Reports, per leg:
##   * the true y-extent of the existing vegetation and leg growth (so the reef's
##     top can be derived from it instead of guessed)
##   * physics-raycast face positions on the caisson, cross-checked against the
##     sonar scan (leg faces at |d| = 3.0 m from centre)
##   * every placed reef instance's clearance to the surface it claims to sit on
##   * the Dock Ladder climb column and the wet-deck swim lane, unobstructed
##
## MUST RUN WINDOWED. MultiMesh instance transforms live in the RenderingServer, and
## under --headless the dummy renderer silently drops every write and returns IDENTITY
## to every read — so a headless run of this file reports 0 floating instances because
## it measured 292 corals all sitting on the world origin. Verified both ways.
##
## Run: godot --path . res://tests/ReefProbe.tscn

const LEGS := [Vector2(-22, -12), Vector2(22, -12), Vector2(-22, 12), Vector2(22, 12)]
const LOG_PATH: String = "/tmp/reef_probe.txt"

var failures: int = 0
var _lines: PackedStringArray = PackedStringArray()
var _space: PhysicsDirectSpaceState3D

## Every LIVE ANIMAL's collider, excluded from every ray this file fires.
##
## This is not tidiness, it is correctness, and s20 proved it the expensive way. Every
## creature in bloom_fauna.gd carries a FaunaTouch — an Interactable, i.e. a StaticBody3D
## with a 0.6-0.85 m sphere on the default collision layer, which is how the player's
## interaction ray finds it. The moment LegReef started seeding snails on the CAISSON FACES,
## those spheres sat 0.6-0.9 m proud of the concrete in exactly the band this harness
## measures — and every ray that clipped one came back with the wrong answer: the caisson
## "moved" 606 mm off its own centre line, and nineteen perfectly seated corals were
## reported BURIED by up to 926 mm because the ray hit a passing snail's touch sphere before
## it reached the wall. Both readings were confident, plausible and wrong.
##
## bloom_fauna's own helpers (fauna_bodies, surface_y) already take a skip list for this
## reason; they walk up to a bloom_fauna.gd host, which does not find snails parented under
## LegReef. This collects by SCRIPT FILE instead, so anything living under any of the fauna
## scripts is skipped wherever it is parented.
const FAUNA_SCRIPTS := ["bloom_fauna.gd", "reef_life.gd", "reef_fish.gd", "leg_reef.gd"]
var _skip: Array[RID] = []

func _collect_fauna(root: Node) -> void:
	for node in root.find_children("*", "CollisionObject3D", true, false):
		var p: Node = node
		while p != null:
			var s: Script = p.get_script()
			if s != null:
				var f: String = String(s.resource_path).get_file()
				if FAUNA_SCRIPTS.has(f):
					_skip.append((node as CollisionObject3D).get_rid())
					break
			p = p.get_parent()
	_say("  excluding %d live-animal colliders from every ray (FaunaTouch spheres)"
		% _skip.size())

## One ray, with the animals excluded. Every query in this file goes through here.
func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = _skip
	return _space.intersect_ray(q)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # see _unpause
	# RIG-ONLY FALLBACK. Main.tscn pulls in every world script, so one parse error
	# anywhere (a neighbouring session mid-edit, most often) makes the whole world fail
	# to instantiate and every check below reports a vacuous pass on an empty tree.
	# Detect that and fall back to the two things this harness actually needs — the rig
	# (for the caisson colliders) and LegReef itself — so a broken neighbour degrades
	# the report instead of silently invalidating it.
	var main: Node3D = null
	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed != null:
		main = packed.instantiate()
	# A parse error does not make instantiate() fail — it hands back a bare Node3D with
	# its script dropped, which then builds nothing. Check for the script, not for null.
	if main != null and main.get_script() == null:
		main.queue_free()
		main = null
	if main == null:
		_say("NOTE  Main.tscn did not load — running RIG-ONLY (no ocean, no vegetation)")
		main = Node3D.new()
		main.add_child(RigBuilder.new())
		main.add_child(load("res://scripts/world/leg_reef.gd").new())
	add_child(main)
	for i in range(90):
		await get_tree().process_frame
	_space = get_viewport().world_3d.direct_space_state
	_collect_fauna(main)
	_vegetation_extent(main)
	_leg_faces()
	_reef_seating(main)
	await _snails(main)
	_routes()
	_say("---")
	_say("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

## PAUSE. The pause menu opens itself whenever the window loses focus, and another session's
## Godot taking focus mid-run freezes the world — which matters here because the snail checks
## measure MOTION over three seconds, and a paused snail is indistinguishable from a wedged
## one. It cost exactly that: a run that reported "0 of 13 moved, furthest 0.00 m" while the
## same code in the same tree had just measured 1.30 m.
##
## `_process` alone does NOT fix it. A Node's default process_mode is INHERIT, which resolves
## to PAUSABLE at the root — so the moment the tree pauses, the very `_process` that would
## unpause it stops being called and the harness can never recover. PROCESS_MODE_ALWAYS is
## the part that makes the standard "force-unpause every frame" advice actually work in a
## `_process` handler. Set in _ready.
var _pause: CanvasLayer = null

func _process(_delta: float) -> void:
	_unpause()

func _unpause() -> void:
	get_tree().paused = false
	# The PAUSED dialog is its own CanvasLayer and stays drawn after the tree resumes.
	if _pause == null:
		_pause = _find_pause(get_tree().root)
	if _pause != null:
		var panel: Variant = _pause.get("panel")
		if panel is CanvasItem:
			(panel as CanvasItem).visible = false

func _find_pause(n: Node) -> CanvasLayer:
	var sc: Script = n.get_script()
	if sc != null and String(sc.resource_path).ends_with("pause_menu.gd"):
		return n as CanvasLayer
	for c in n.get_children():
		var got: CanvasLayer = _find_pause(c)
		if got != null:
			return got
	return null

func _say(msg: String) -> void:
	print(msg)
	_lines.append(msg)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_say("PASS  " + label + ("  — " + detail if detail != "" else ""))
	else:
		failures += 1
		_say("FAIL  " + label + ("  — " + detail if detail != "" else ""))

func _meshes(root: Node) -> Array:
	return root.find_children("*", "MeshInstance3D", true, false)

## World AABB of a mesh instance, or a zero box when it has no mesh yet.
func _world_aabb(mi: MeshInstance3D) -> AABB:
	if mi.mesh == null:
		return AABB()
	return mi.global_transform * mi.get_aabb()

# ------------------------------------------------------- vegetation

## Where does the kelp/grass actually END? Walks every drawable within 8 m of a leg
## centre in the swimmable column and reports the lowest point vegetation reaches.
func _vegetation_extent(main: Node) -> void:
	_say("== vegetation extent (measured, not authored) ==")
	var low: float = 1e9
	var high: float = -1e9
	var kelp_low: float = 1e9
	var n: int = 0
	for node in _meshes(main):
		var mi: MeshInstance3D = node
		if mi.mesh == null:
			continue
		var a: AABB = _world_aabb(mi)
		var c: Vector3 = a.get_center()
		if c.y > 0.5 or c.y < -40.0:
			continue
		var near: bool = false
		for leg in LEGS:
			if Vector2(c.x - leg.x, c.z - leg.y).length() < 9.0:
				near = true
		if not near:
			continue
		# vegetation = anything under the UnderwaterWorld kelp/growth subtree
		var p: Node = mi
		var tag: String = ""
		while p != null:
			if p.get_script() != null:
				tag = String(p.get_script().resource_path).get_file()
				break
			p = p.get_parent()
		if tag != "underwater_world.gd":
			continue
		n += 1
		low = minf(low, a.position.y)
		high = maxf(high, a.position.y + a.size.y)
	# The kelp stand proper — the strands _kelp_forest tags with `sway`. Reported next
	# to the naive number on purpose: "everything underwater_world drew near a leg"
	# bottoms out ~8 m deeper than the plants do, because the deepest things by a
	# footing are the floodlight cones, the god-ray quads and any fish passing through.
	# LegReef derives its band top from the tagged strands for exactly that reason.
	var uw: Node = null
	for node in main.find_children("*", "Node3D", true, false):
		if node.get_script() != null \
				and String(node.get_script().resource_path).ends_with("underwater_world.gd"):
			uw = node
			break
	var strands: int = 0
	if uw != null:
		for node in uw.get_children():
			if not (node is Node3D) or not node.has_meta("sway"):
				continue
			strands += 1
			for child in (node as Node3D).find_children("*", "MeshInstance3D", true, false):
				var m2: MeshInstance3D = child
				if m2.mesh != null:
					kelp_low = minf(kelp_low, (m2.global_transform * m2.get_aabb()).position.y)
	_say("  underwater_world drawables near legs: %d (naive floor y %.2f, ceiling y %.2f)"
		% [n, low, high])
	_say("  kelp stand: %d tagged strands, floor y %.2f" % [strands, kelp_low])
	_check("kelp stand found and measured", strands > 0 and kelp_low < 0.0,
		"%d strands, floor y %.2f" % [strands, kelp_low])
	_check("coral band starts below the kelp", _band_top(false) < kelp_low,
		"coral top y %.2f vs kelp floor y %.2f" % [_band_top(false), kelp_low])
	# The CRUST is meant to overlap the kelp — see LegReef.CRUST_TOP. Reported, not asserted
	# against the kelp: barnacles and starfish deliberately run up to just under the pontoon
	# skirt so the bare stripe between the shallow growth and the reef proper is closed.
	_say("  crust/starfish top y %.2f (deliberately above the kelp floor)" % _band_top(true))

## The top of the reef band, read back off the built instances rather than off LegReef's
## constants — the point is to confirm where the coral actually IS.
##
## `with_crust` is the distinction the s20 pass introduced. The COLONIES (coral, sponges,
## reef masses) still start below the measured kelp floor, which is the invariant worth
## asserting. The barnacle crust and the big starfish do not: they run the whole leg from
## just under the pontoon, on purpose, and asserting the old blanket rule against them
## reported a deliberate design change as a failure.
func _band_top(with_crust: bool) -> float:
	var top: float = -1.0e9
	for node in get_tree().root.find_children("LegReef_Leg_*", "MultiMeshInstance3D", true, false):
		var mmi: MultiMeshInstance3D = node
		var crust: bool = String(mmi.name).contains("barnacle") or String(mmi.name).contains("star")
		if crust != with_crust:
			continue
		for i in range(mmi.multimesh.instance_count):
			top = maxf(top, (mmi.global_transform * mmi.multimesh.get_instance_transform(i)).origin.y)
	return top

# ------------------------------------------------------- leg faces

## Cross-check the sonar scan against the live physics colliders. Sonar says every
## caisson face is exactly 3.0 m from its centre line; if the collider disagrees, the
## reef is seated against a surface that is not there.
func _leg_faces() -> void:
	_say("== caisson faces (physics raycast vs sonar) ==")
	var worst: float = 0.0
	for leg in LEGS:
		for depth in [-12.0, -16.0, -20.0, -26.0]:
			for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
				var centre := Vector3(leg.x, depth, leg.y)
				var hit: Dictionary = _ray(centre + d * 12.0, centre)
				if hit.is_empty():
					_check("face %s @ y%.0f leg(%.0f,%.0f)" % [d, depth, leg.x, leg.y], false, "no hit")
					continue
				var dist: float = (hit["position"] - centre).length()
				worst = maxf(worst, absf(dist - 3.0))
	_check("caisson faces are 3.00 m from centre", worst < 0.05,
		"worst deviation %.3f m across 64 rays" % worst)

# ------------------------------------------------------- reef seating

## Every reef instance must be FLUSH: its base within tolerance of the concrete it
## claims to be growing on, and never floating in open water.
func _reef_seating(main: Node) -> void:
	_say("== reef seating ==")
	var reefs: Array = main.find_children("LegReef_*", "MultiMeshInstance3D", true, false)
	if reefs.is_empty():
		_check("reef multimeshes present", false, "found none")
		return
	var total: int = 0
	var tris: int = 0
	var floated: int = 0
	var buried: int = 0
	var unprobed: int = 0
	var gaps: Array[float] = []
	for node in reefs:
		var mmi: MultiMeshInstance3D = node
		var mm: MultiMesh = mmi.multimesh
		total += mm.instance_count
		tris += mm.instance_count * int(mm.mesh.get_faces().size() / 3.0)
		for i in range(mm.instance_count):
			var t: Transform3D = mmi.global_transform * mm.get_instance_transform(i)
			# Each piece's +Y is its growth axis and its base sits at the node origin
			# (baked by tools/decimate_reef.py), so casting along -Y from just outside
			# finds the surface it claims to be growing on. Positive gap = the base is
			# recessed into the concrete, which is intended; negative = it is floating,
			# which is the bug this whole harness exists to catch.
			var up: Vector3 = t.basis.y.normalized()
			var hit: Dictionary = _ray(t.origin + up * 1.1, t.origin - up * 0.9)
			if hit.is_empty():
				unprobed += 1
				continue
			# Measured along the growth axis, which leans off the surface normal — so
			# convert to the PERPENDICULAR depth into the concrete before judging it,
			# or a coral leaning 44 deg reads as 40% more buried than it is.
			var along: float = (hit["position"] - t.origin).dot(up)
			var gap: float = along * absf(up.dot(hit["normal"]))
			gaps.append(gap)
			if gap < -0.02:
				floated += 1
				if floated <= 5:
					_say("  FLOAT  %s[%d] at %v by %.0f mm" % [mmi.name, i, t.origin, -gap * 1000.0])
			elif gap > 0.25:
				buried += 1
				if buried <= 5:
					_say("  BURIED %s[%d] at %v by %.0f mm" % [mmi.name, i, t.origin, gap * 1000.0])
	gaps.sort()
	var med: float = gaps[gaps.size() / 2] if not gaps.is_empty() else 0.0
	_say("  instances %d in %d MultiMesh draws · %d triangles" % [total, reefs.size(), tris])
	_say("  seating gap: median %+.0f mm, min %+.0f mm, max %+.0f mm (positive = recessed)"
		% [med * 1000.0, gaps[0] * 1000.0 if not gaps.is_empty() else 0.0,
			gaps[gaps.size() - 1] * 1000.0 if not gaps.is_empty() else 0.0])
	_say("  %d of %d instances sit on collider the probe could re-measure" % [gaps.size(), total])
	# Guard against the vacuous pass: "0 floating" means nothing if nothing was measured.
	_check("seating was actually measurable (run windowed!)", gaps.size() > total / 2,
		"%d of %d re-measured" % [gaps.size(), total])
	_check("no reef instance floats off its surface", floated == 0, "%d floating" % floated)
	_check("no reef instance is buried past 250 mm", buried == 0, "%d buried" % buried)

# ------------------------------------------------------- snails on the concrete

## The lamp and pyramid snails LegReef seeds on the caisson faces. Three things have to be
## true and none of them can be asserted from source: the foot is on the real concrete (not
## hanging the 60 mm of seating clearance out in the water), the BODY is square to the wall
## rather than lying flat in the world the way a yaw-only orientation leaves it, and the
## animal is actually crawling — a SurfaceCrawler with nothing under its foot holds position
## silently and looks exactly like a seated one in a single frame.
func _snails(main: Node) -> void:
	_say("== snails on the caisson ==")
	var reef: Node = null
	for node in main.find_children("*", "Node3D", true, false):
		if node.get_script() != null \
				and String(node.get_script().resource_path).ends_with("leg_reef.gd"):
			reef = node
			break
	if reef == null:
		_check("LegReef found", false, "no node with leg_reef.gd")
		return
	var snails: Array = []
	for node in reef.get_children():
		if node is Node3D and (node.is_in_group("snail_lamp") or node.is_in_group("snail_pyramid")):
			snails.append(node)
	_check("snails seeded on the legs", snails.size() >= 8, "%d found" % snails.size())
	if snails.is_empty():
		return
	var start: Array[Vector3] = []
	var worst_gap: float = 0.0
	var worst_tilt: float = 1.0
	var off_wall: int = 0
	var floating: int = 0
	for s in snails:
		var n3: Node3D = s
		start.append(n3.global_position)
		# nearest leg, and the outward normal of the face it is on
		var leg: Vector2 = LEGS[0]
		for l in LEGS:
			if Vector2(n3.global_position.x - l.x, n3.global_position.z - l.y).length() \
					< Vector2(n3.global_position.x - leg.x, n3.global_position.z - leg.y).length():
				leg = l
		var d := Vector2(n3.global_position.x - leg.x, n3.global_position.z - leg.y)
		# the face is whichever axis it is furthest out along; gap = how far past the 3.0 m
		# face plane the animal's origin sits
		var face := Vector3(signf(d.x), 0.0, 0.0) if absf(d.x) > absf(d.y) \
			else Vector3(0.0, 0.0, signf(d.y))
		var gap: float = maxf(absf(d.x), absf(d.y)) - 3.0
		worst_gap = maxf(worst_gap, gap)
		if gap > 0.35 or gap < -0.10:
			floating += 1
			_say("  OFF   %s at %v — %.0f mm off the face" % [n3.name, n3.global_position, gap * 1000.0])
		# body +Y on the face normal: a snail stuck to a wall, not lying on its side
		var tilt: float = n3.global_basis.y.normalized().dot(face)
		worst_tilt = minf(worst_tilt, tilt)
		if tilt < 0.75:
			off_wall += 1
	_check("every snail's foot is on the caisson face", floating == 0,
		"%d off, worst %+.0f mm past the face" % [floating, worst_gap * 1000.0])
	_check("every snail's body is square to the wall", off_wall == 0,
		"worst up-vs-face-normal %.2f (1.0 = flat on the wall)" % worst_tilt)
	# Let them run: a wedged crawler and a seated one are indistinguishable in one frame.
	for i in range(180):
		_unpause()
		await get_tree().process_frame
	var moved: int = 0
	var far: float = 0.0
	var still_on: int = 0
	for i in range(snails.size()):
		var n3: Node3D = snails[i]
		if not is_instance_valid(n3):
			continue
		var d: float = n3.global_position.distance_to(start[i])
		far = maxf(far, d)
		if d > 0.05:
			moved += 1
		var leg: Vector2 = LEGS[0]
		for l in LEGS:
			if Vector2(n3.global_position.x - l.x, n3.global_position.z - l.y).length() \
					< Vector2(n3.global_position.x - leg.x, n3.global_position.z - leg.y).length():
				leg = l
		var dx: float = absf(n3.global_position.x - leg.x)
		var dz: float = absf(n3.global_position.z - leg.y)
		var off: float = maxf(dx, dz) - 3.0
		# ON THE CAISSON means: out at the face plane on one axis, and inside the casting's
		# 6 m plan on the other. The first version tested only the first half, which flagged a
		# snail that had crawled round a CONVEX CORNER — legitimately 3.02 m out on BOTH axes,
		# and legitimately still stuck to the concrete. The extra 0.1 m of slack past the
		# corner is the crawler easing its origin onto the new face over a few frames.
		if off > -0.10 and off < 0.35 and minf(dx, dz) < 3.15:
			still_on += 1
		else:
			_say("  DRIFT  %s at %v — face offset %+.0f mm, other axis %.2f m"
				% [n3.name, n3.global_position, off * 1000.0, minf(dx, dz)])
	_check("snails are crawling, not wedged", moved >= snails.size() / 2,
		"%d of %d moved in 3 s, furthest %.2f m" % [moved, snails.size(), far])
	_check("snails stay on the caisson while crawling", still_on == snails.size(),
		"%d of %d still on a face after 3 s" % [still_on, snails.size()])

# ------------------------------------------------------- routes

## Nothing may stand in the Dock Ladder's climb column or the swim lane a player
## uses to get back onto the wet deck.
func _routes() -> void:
	_say("== routes ==")
	# Dock Ladder: rig_builder places it at (24.6, -1.4, -22.42); the controller
	# latches at base + face_dir * 0.45 and the climb column is a 0.37 m capsule.
	var ladder := Vector3(24.6, -1.4, -22.42)
	var blocked: int = 0
	for k in range(24):
		var y: float = -3.4 + k * 0.25
		var p := Vector3(ladder.x, y, ladder.z + 0.45)
		if not _ray(p + Vector3(0.6, 0, 0), p - Vector3(0.6, 0, 0)).is_empty():
			blocked += 1
	_check("Dock Ladder climb column clear", blocked == 0, "%d of 24 samples blocked" % blocked)
	# Swim lane in to the wet deck: the open water south of the SE leg.
	var lane_blocked: int = 0
	for k in range(20):
		var p := Vector3(20.0, -2.0 - k * 0.4, -20.0)
		if not _ray(p + Vector3(0, 0, 3.0), p - Vector3(0, 0, 3.0)).is_empty():
			lane_blocked += 1
	_check("wet-deck swim lane clear", lane_blocked == 0, "%d of 20 samples blocked" % lane_blocked)
