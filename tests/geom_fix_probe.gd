extends Node
## MEASUREMENT probe for the five world-geometry defects (breaker ceiling light, the
## DANGER placard, the splice stencil, the wet-deck crate/barrel pair, the machine-shop
## roof ladder). It asserts nothing on its own — it PRINTS the real numbers out of the
## built world so the fixes are measured instead of hand-typed. Every constant this
## project has drifted on (ceiling heights, wall faces, prop footprints) is read back
## from geometry here.
##
## Run: godot --headless --path . res://tests/GeomFixProbe.tscn

const LOG_PATH: String = "/tmp/geom_fix_probe.txt"
const PLAYER_RADIUS: float = 0.37   ## PlayerController.PLAYER_RADIUS
const PLAYER_HEIGHT: float = 1.8    ## STAND_HEIGHT
const COL_Y: float = 0.9            ## capsule centre above the feet

var _lines: PackedStringArray = PackedStringArray()
var _main: Node3D
var _space: PhysicsDirectSpaceState3D

func _say(msg: String) -> void:
	print(msg)
	_lines.append(msg)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().create_timer(6.0).timeout
	for i in range(10):
		await get_tree().physics_frame
	_space = get_viewport().world_3d.direct_space_state

	_breaker_ceiling()
	_danger_sign()
	_splice_label()
	_wet_deck_pairs()
	_roof_ladder()
	get_tree().quit()

# ------------------------------------------------------------------ helpers

## First solid hit from `from` along `dir` (max `dist`), or NAN-filled if nothing.
func _ray(from: Vector3, dir: Vector3, dist: float = 8.0) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * dist)
	q.collide_with_areas = false
	return _space.intersect_ray(q)

## World-space AABB of a node's own visual geometry plus every VisualInstance3D under it.
func _world_aabb(n: Node) -> AABB:
	var out := AABB()
	var got := false
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		for k in c.get_children():
			stack.append(k)
		if c is VisualInstance3D and not (c is Light3D):
			# Light3D's get_aabb() is its illumination volume, not geometry — it would
			# swallow half the rig and make every overlap test meaningless.
			var vi := c as VisualInstance3D
			var lb: AABB = vi.get_aabb()
			var xf: Transform3D = vi.global_transform
			var box := AABB(xf * lb.position, Vector3.ZERO)
			for i in range(8):
				box = box.expand(xf * (lb.position + lb.size * Vector3(
					float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1))))
			if got:
				out = out.merge(box)
			else:
				out = box
				got = true
	return out

func _fmt(a: AABB) -> String:
	return "x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % [
		a.position.x, a.end.x, a.position.y, a.end.y, a.position.z, a.end.z]

## A human-readable identity for an auto-named prop: its display name if it has one,
## else the mesh/resource names underneath it, which is what actually says "barrel".
func _ident(n: Node) -> String:
	var bits: PackedStringArray = PackedStringArray()
	if n.has_method("get") and n.get("display_name") != null and str(n.get("display_name")) != "":
		bits.append(str(n.get("display_name")))
	var stack: Array[Node] = [n]
	var seen: Dictionary = {}
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		for k in c.get_children():
			stack.append(k)
		if not c.name.begins_with("@") and not seen.has(c.name):
			seen[c.name] = true
			bits.append(String(c.name))
		if c is MeshInstance3D:
			var m: Mesh = (c as MeshInstance3D).mesh
			if m != null and m.resource_path != "" and not seen.has(m.resource_path):
				seen[m.resource_path] = true
				bits.append(m.resource_path.get_file())
	return " ".join(bits).substr(0, 90)

## World-space extents of a body's collision shapes — the only geometry an invisible
## barrier (a bare StaticBody3D with no mesh) actually has.
func _shape_boxes(n: Node) -> String:
	var bits: PackedStringArray = PackedStringArray()
	for c in n.get_children():
		if not (c is CollisionShape3D):
			continue
		var cs := c as CollisionShape3D
		if cs.shape is BoxShape3D:
			var half: Vector3 = (cs.shape as BoxShape3D).size * 0.5
			var p: Vector3 = cs.global_position
			bits.append(_fmt(AABB(p - half, half * 2.0)))
		else:
			bits.append("%s @ %s" % [cs.shape.get_class(), str(cs.global_position.snappedf(0.01))])
	return " | ".join(bits)

func _walk(root: Node, out: Array[Node]) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		out.append(n)

## Can a standing player capsule sit at `feet` without overlapping anything?
func _capsule_free(feet: Vector3, radius: float = PLAYER_RADIUS,
		skip: Array[RID] = []) -> bool:
	var sh := CapsuleShape3D.new()
	sh.radius = radius
	sh.height = PLAYER_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0, COL_Y, 0))
	q.collide_with_areas = false
	q.exclude = skip
	return _space.intersect_shape(q, 1).is_empty()

## Largest capsule radius (to 1 cm) that fits at `feet`, 0 if even 1 cm does not.
func _max_radius(feet: Vector3, skip: Array[RID] = []) -> float:
	var best: float = 0.0
	for i in range(1, 61):
		var r: float = i * 0.01
		if _capsule_free(feet, r, skip):
			best = r
		else:
			break
	return best

# ------------------------------------------------- 1. breaker-room ceiling

func _breaker_ceiling() -> void:
	_say("")
	_say("=== 1. BREAKER ROOM 4-A CEILING + RED BEACON ===")
	for p in [Vector3(25.5, 11.0, 6.0), Vector3(24.0, 11.0, 6.0), Vector3(23.0, 11.0, 5.0),
			Vector3(26.5, 11.0, 4.0), Vector3(22.0, 11.0, 7.5)]:
		var up: Dictionary = _ray(p, Vector3.UP, 6.0)
		var dn: Dictionary = _ray(p, Vector3.DOWN, 4.0)
		_say("  at (%.2f, %.2f) ceiling underside y=%s   floor y=%s" % [p.x, p.z,
			("%.4f" % up.position.y) if up.has("position") else "none",
			("%.4f" % dn.position.y) if dn.has("position") else "none"])
	var all: Array[Node] = []
	_walk(_main, all)
	for n in all:
		if n.get_class() == "Node3D" and (n as Node3D).global_position.distance_to(
				Vector3(25.5, 12.6, 6.0)) < 6.0 and n.get_child_count() > 0:
			var has_light := false
			for c in n.get_children():
				if c is OmniLight3D and (c as OmniLight3D).light_color.r > 0.8 \
						and (c as OmniLight3D).light_color.g < 0.3:
					has_light = true
			if has_light:
				var n3 := n as Node3D
				_say("  RED FLASHER '%s' origin %s  rot %s" % [n.name,
					str(n3.global_position.snappedf(0.001)),
					str((n3.global_rotation * 57.2957795).snappedf(0.1))])
				_say("    world AABB  %s" % _fmt(_world_aabb(n)))

# ------------------------------------------------------ 2. DANGER placard

func _danger_sign() -> void:
	_say("")
	_say("=== 2. DANGER / 440 V PLACARD ON THE SOUTH WALL ===")
	# Scan the south wall from inside the room: where is solid plate, where is the hole?
	for x in [22.30, 22.79, 23.10, 23.50, 24.00, 24.21, 24.30, 24.60, 25.00]:
		var col: PackedStringArray = PackedStringArray()
		for y in [10.4, 11.0, 11.45, 11.9, 12.2, 12.4, 12.6, 12.9]:
			var h: Dictionary = _ray(Vector3(x, y, 4.5), Vector3(0, 0, -1), 3.0)
			col.append("%.1f:%s" % [y, ("%.3f" % h.position.z) if h.has("position") else "OPEN"])
		_say("  x=%.2f  wall face z by height -> %s" % [x, " ".join(col)])
	# Exact east jamb and head of the opening, to the centimetre.
	var jamb: float = 0.0
	var x2: float = 24.00
	while x2 < 24.60:
		if not _ray(Vector3(x2, 11.45, 4.5), Vector3(0, 0, -1), 3.0).is_empty():
			jamb = x2
			break
		x2 += 0.01
	var head: float = 0.0
	var y2: float = 12.00
	while y2 < 12.80:
		if not _ray(Vector3(23.5, y2, 4.5), Vector3(0, 0, -1), 3.0).is_empty():
			head = y2
			break
		y2 += 0.01
	_say("  OPENING: east jamb first solid at x=%.2f, head first solid at y=%.2f" % [jamb, head])
	_say("  lintel band = y %.2f .. 13.075 (%.3f m of solid plate above the head)" % [head, 13.075 - head])
	var all: Array[Node] = []
	_walk(_main, all)
	_say("  -- geometry on the south wall (z < 2.7), y 11.0..13.1, x 21..27 --")
	var seen2: Dictionary = {}
	for n in all:
		if not (n is VisualInstance3D) or n is Label3D:
			continue
		var a: AABB = _world_aabb(n)
		if a.size == Vector3.ZERO or a.size.x > 8.0:
			continue
		if a.position.z > 2.7 or a.end.z < 1.8 or a.position.y > 13.1 or a.end.y < 11.0:
			continue
		if a.position.x > 27.0 or a.end.x < 21.0:
			continue
		var key2: String = _fmt(a)
		if seen2.has(key2):
			continue
		seen2[key2] = true
		_say("    %-30s %s" % [_ident(n.get_parent()).substr(0, 30), key2])
	for n in all:
		if n is Label3D and (n as Label3D).text.begins_with("DANGER"):
			_say("  LABEL '%s' at %s  AABB %s" % [(n as Label3D).text.replace("\n", " / "),
				str((n as Label3D).global_position.snappedf(0.001)), _fmt(_world_aabb(n))])

# ------------------------------------------------------- 3. splice stencil

func _splice_label() -> void:
	_say("")
	_say("=== 3. '1) SPLICE THE GAP' STENCIL ON THE PANEL WALL ===")
	var all: Array[Node] = []
	_walk(_main, all)
	var labels: Array[Label3D] = []
	for n in all:
		if n is Label3D:
			var l := n as Label3D
			if l.global_position.distance_to(Vector3(25.2, 11.8, 8.6)) < 6.0:
				labels.append(l)
	for l in labels:
		_say("  LABEL '%s'  pos %s  AABB %s" % [l.text.replace("\n", " / "),
			str(l.global_position.snappedf(0.001)), _fmt(_world_aabb(l))])
	# Everything solid-ish on the north wall band the stencils live in.
	_say("  -- geometry on the north wall (z > 8.2), y 10.8..13.1 --")
	var seen: Dictionary = {}
	for n in all:
		if not (n is VisualInstance3D) or n is Label3D:
			continue
		var a: AABB = _world_aabb(n)
		if a.size == Vector3.ZERO:
			continue
		if a.end.z < 8.2 or a.position.y > 13.1 or a.end.y < 10.8:
			continue
		if a.position.x > 28.0 or a.end.x < 21.0 or a.size.x > 8.0:
			continue
		var key: String = "%s|%s" % [n.get_parent().name, _fmt(a)]
		if seen.has(key):
			continue
		seen[key] = true
		_say("    %-28s %s" % [n.get_parent().name + "/" + n.name, _fmt(a)])

# --------------------------------------------------- 4. wet-deck overlaps

func _wet_deck_pairs() -> void:
	_say("")
	_say("=== 4. WET DECK: OVERLAPPING PROP PAIRS ===")
	var all: Array[Node] = []
	_walk(_main, all)
	var names: Array[String] = []
	var boxes: Array[AABB] = []
	for n in all:
		if not (n is Node3D):
			continue
		var n3 := n as Node3D
		# Only top-level dressed props / detail assemblies, not their sub-meshes.
		if not (n3.is_in_group("dress_prop") or n3 is Interactable):
			continue
		var a: AABB = _world_aabb(n3)
		if a.size == Vector3.ZERO:
			continue
		# The wet deck slab is y ~2; keep to that storey and its footprint.
		if a.position.y > 5.0 or a.end.y < 0.5:
			continue
		names.append(_ident(n3))
		boxes.append(a)
	_say("  %d wet-deck props indexed" % names.size())
	var hits: int = 0
	for i in range(names.size()):
		for j in range(i + 1, names.size()):
			var a: AABB = boxes[i]
			var b: AABB = boxes[j]
			if not a.intersects(b):
				continue
			var ov := Vector3(
				minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x),
				minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y),
				minf(a.end.z, b.end.z) - maxf(a.position.z, b.position.z))
			if ov.x < 0.04 or ov.z < 0.04 or ov.y < 0.04:
				continue   # touching, not clipping
			var vol: float = ov.x * ov.y * ov.z
			if vol < 0.004:
				continue
			hits += 1
			_say("  CLIP %.4f m3  overlap %s" % [vol, str(ov.snappedf(0.001))])
			_say("       A %s\n         %s" % [names[i], _fmt(a)])
			_say("       B %s\n         %s" % [names[j], _fmt(b)])
	_say("  %d clipping pairs" % hits)
	# The dress-prop sweep above only sees SPAWNED props. Crates are LootContainers and
	# the tide-line drums are plain builder cylinders, so the pair the owner reported can
	# only be found by asking physics what each crate's own volume is sitting inside.
	_say("  -- every crate on the wet deck, shape-queried against the world --")
	for n in all:
		if not (n is LootContainer):
			continue
		var c := n as LootContainer
		if c.global_position.y > 6.0 or c.global_position.y < 0.5:
			_say("  (crate '%s' at %s — outside the wet deck band)" % [
				c.display_name, str(c.global_position.snappedf(0.01))])
			continue
		var a: AABB = _world_aabb(c)
		_say("  CRATE '%s' at %s  %s" % [c.display_name,
			str(c.global_position.snappedf(0.001)), _fmt(a)])
		var q := PhysicsShapeQueryParameters3D.new()
		var bx := BoxShape3D.new()
		bx.size = a.size * 0.94        # shrink so face-to-face contact is not a "clip"
		q.shape = bx
		q.transform = Transform3D(Basis.IDENTITY, a.get_center())
		q.collide_with_areas = false
		q.exclude = [c.get_rid()]
		for hit in _space.intersect_shape(q, 24):
			var col: Node = hit.get("collider")
			if col == null or col == c or c.is_ancestor_of(col):
				continue
			_say("      INTERSECTS %s  %s" % [_ident(col).substr(0, 60), _fmt(_world_aabb(col))])
	# Candidate re-homes for the crate that clips: is the deck under it, is it clear?
	_say("  -- candidate spots for the Dock Locker (1.1 x 0.8 x 0.8) --")
	for cand in [Vector3(28.6, 2.405, -19.6), Vector3(28.6, 2.405, -18.6)]:
		_spot(cand, Vector3(1.1, 0.8, 0.8))
	# Where the machine-shop welding screen could stand without pinching the roof ladder.
	_say("  -- welding screen 2 candidate footprints (0.14 x 1.64 x 1.40) --")
	for sx in [-14.98, -18.05]:
		_spot(Vector3(sx, 18.82, -4.10), Vector3(0.14, 1.64, 1.40))

## Mirror of PlayerController._dismount_clear: preferred side, then the mirror side, then
## straight up — first candidate that is both capsule-clear AND reachable in a straight
## line from the anchor (so an exit can never land the player through a bulkhead).
func _resolve_exit(anchor: Vector3, into: Vector3, ef: float, skip: Array[RID]) -> String:
	var flat: Vector3 = Vector3(into.x, 0.0, into.z).normalized()
	var side: Vector3 = flat.cross(Vector3.UP).normalized()
	var cands: Array[Vector3] = []
	for d in [ef, ef + 0.6, ef + 1.3]:
		cands.append(anchor + flat * d)
		cands.append(anchor + flat * d + side * 0.55)
		cands.append(anchor + flat * d - side * 0.55)
	for d in [ef, ef + 0.6]:
		cands.append(anchor - flat * d)
		cands.append(anchor - flat * d + side * 0.55)
		cands.append(anchor - flat * d - side * 0.55)
	cands.append(anchor + Vector3(0, 1.3, 0))
	for c in cands:
		if not _capsule_free(c, PLAYER_RADIUS, skip):
			continue
		var lift := Vector3(0, COL_Y, 0)
		var q := PhysicsRayQueryParameters3D.create(anchor + lift, c + lift)
		q.collide_with_areas = false
		if not _space.intersect_ray(q).is_empty():
			continue
		var g: Dictionary = _ray(c + Vector3(0, 0.05, 0), Vector3.DOWN, 20.0)
		return "%s  ground %s (drop %s)" % [str(c.snappedf(0.01)),
			("y %.3f" % g.position.y) if g.has("position") else "NONE",
			("%.2f m" % (c.y - g.position.y)) if g.has("position") else "-"]
	return "NO CLEAR+REACHABLE SPOT"

## What a box of `size` centred at `c` would sit in: overlaps, the deck under it, and
## whether a walking capsule can still pass on each side.
func _spot(c: Vector3, size: Vector3) -> void:
	var q := PhysicsShapeQueryParameters3D.new()
	var bx := BoxShape3D.new()
	bx.size = size * 0.94
	q.shape = bx
	q.transform = Transform3D(Basis.IDENTITY, c)
	q.collide_with_areas = false
	var names: PackedStringArray = PackedStringArray()
	for hit in _space.intersect_shape(q, 16):
		var col: Node = hit.get("collider")
		if col != null:
			names.append("%s %s" % [_ident(col).substr(0, 30), _fmt(_world_aabb(col))])
	var floor_hit: Dictionary = _ray(c, Vector3.DOWN, 6.0)
	var walk: PackedStringArray = PackedStringArray()
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var feet: Vector3 = Vector3(c.x, c.y - size.y * 0.5, c.z) + d * (size.x * 0.5 + 0.55)
		walk.append("%s%s" % ["+x" if d.x > 0 else ("-x" if d.x < 0 else ("+z" if d.z > 0 else "-z")),
			":OK" if _capsule_free(feet) else ":blocked"])
	_say("    %s  base y %.3f (deck %s)  hits[%s]  walk[%s]" % [
		str(c.snappedf(0.01)), c.y - size.y * 0.5,
		("%.3f" % floor_hit.position.y) if floor_hit.has("position") else "NONE",
		", ".join(names), " ".join(walk)])

# ------------------------------------------------ 5. machine-shop ladder

func _roof_ladder() -> void:
	_say("")
	_say("=== 5. MACHINE SHOP ROOF LADDER ===")
	var all: Array[Node] = []
	_walk(_main, all)
	var lads: Array[Ladder] = []
	for n in all:
		if n is Ladder:
			lads.append(n as Ladder)
	# EVERY ladder, audited the same way: is the spot start_climb() latches the capsule
	# to actually open air, and does the top mantle land on ground rather than in space?
	# The ladder's own collider is excluded — collision is off for the whole climb, so
	# it is only the WORLD around the climb path that can trap or eject the player.
	_say("  %d ladders in the world (latch clearance / top-mantle ground):" % lads.size())
	for l in lads:
		var skip: Array[RID] = [l.get_rid()]
		var lb: Vector3 = l.bottom_point()
		var lt: Vector3 = l.top_point()
		var lf: Vector3 = l.face_dir()
		var latch2: Vector3 = lb + lf * 0.45
		var mid: Vector3 = latch2 + Vector3(0, (lt.y - lb.y) * 0.5, 0)
		var mantle2: Vector3 = lt + Vector3(0, 0.4, 0) - lf * l.exit_forward
		var g: Dictionary = _ray(mantle2, Vector3.DOWN, 20.0)
		var drop: float = (mantle2.y - g.position.y) if g.has("position") else 99.0
		_say("    %-26s yaw %4.0f  latch r %.2f  mid r %.2f  mantle drop %s  %s" % [
			"'" + l.display_name + "'", rad_to_deg(l.global_rotation.y),
			_max_radius(latch2, skip), _max_radius(mid, skip),
			("%.2f m" % drop) if drop < 90.0 else "NO GROUND",
			"OK" if (_max_radius(mid, skip) >= PLAYER_RADIUS and drop <= 1.6) else "** BAD **"])
		# Both exits, resolved exactly the way _dismount_clear resolves them.
		_say("        top mantle -> %s" % _resolve_exit(
			lt + Vector3(0, 0.4, 0), -lf, l.exit_forward, skip))
		_say("        bottom step-off -> %s" % _resolve_exit(
			lb + Vector3(0, 0.1, 0), -lf, l.exit_forward, skip))
	var lad: Ladder = null
	for l in lads:
		if l.display_name == "Machine Shop Roof Ladder":
			lad = l
	if lad == null:
		_say("  MACHINE SHOP ROOF LADDER NOT FOUND")
		return
	var base: Vector3 = lad.bottom_point()
	var top: Vector3 = lad.top_point()
	var fd: Vector3 = lad.face_dir()
	_say("  ladder '%s' base %s  top %s" % [lad.display_name,
		str(base.snappedf(0.001)), str(top.snappedf(0.001))])
	_say("  yaw %.1f deg   face_dir %s   exit_forward %.2f" % [
		rad_to_deg(lad.global_rotation.y), str(fd.snappedf(0.001)), lad.exit_forward])
	# The latch spot start_climb() teleports to, and the mantle spot _dismount_clear uses.
	var own: Array[RID] = [lad.get_rid()]
	var latch: Vector3 = Vector3(base.x, base.y, base.z) + fd * 0.45
	var mantle: Vector3 = top + Vector3(0, 0.4, 0) - fd * lad.exit_forward
	_say("  LATCH (base + face_dir*0.45)      %s  capsule clear: %s  max r %.2f" % [
		str(latch.snappedf(0.001)), str(_capsule_free(latch, PLAYER_RADIUS, own)),
		_max_radius(latch, own)])
	# Is the latch spot inside the building? Cast toward the shop and back.
	var toward: Dictionary = _ray(latch + Vector3(0, 1.2, 0), Vector3(0, 0, -1), 4.0)
	var away: Dictionary = _ray(latch + Vector3(0, 1.2, 0), Vector3(0, 0, 1), 4.0)
	_say("    from latch: wall to -Z at z=%s, to +Z at z=%s" % [
		("%.3f" % toward.position.z) if toward.has("position") else "none",
		("%.3f" % away.position.z) if away.has("position") else "none"])
	_say("  TOP MANTLE (top+0.4 - face_dir*ef) %s  capsule clear: %s  max r %.2f" % [
		str(mantle.snappedf(0.001)), str(_capsule_free(mantle, PLAYER_RADIUS, own)),
		_max_radius(mantle, own)])
	# What actually limits the capsule at the foot of the climb, if anything does.
	var qq := PhysicsShapeQueryParameters3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = PLAYER_RADIUS
	cs.height = PLAYER_HEIGHT
	qq.shape = cs
	qq.transform = Transform3D(Basis.IDENTITY, latch + Vector3(0, COL_Y, 0))
	qq.collide_with_areas = false
	qq.exclude = own
	for hit in _space.intersect_shape(qq, 8):
		var col: Node = hit.get("collider")
		if col != null:
			_say("    latch blocked by: %s  %s  shapes:%s" % [String(col.get_path()),
				_fmt(_world_aabb(col)), _shape_boxes(col)])
	var ground: Dictionary = _ray(mantle, Vector3.DOWN, 12.0)
	_say("    ground under the mantle spot: %s (drop %.3f m)" % [
		("y %.3f" % ground.position.y) if ground.has("position") else "NOTHING — open air",
		(mantle.y - ground.position.y) if ground.has("position") else -1.0])
	# The climb column itself: does a capsule fit beside the rungs the whole way up?
	_say("  climb column clearance (capsule at the latch XZ, every 0.5 m):")
	var worst: float = 99.0
	var y: float = base.y
	while y <= top.y + 0.01:
		var f: Vector3 = Vector3(latch.x, y, latch.z)
		var r: float = _max_radius(f, own)
		worst = minf(worst, r)
		_say("    y %.2f  max capsule radius %.2f  %s" % [y, r, "OK" if r >= PLAYER_RADIUS else "JAM"])
		y += 0.5
	_say("  worst radius on the climb: %.2f (player needs %.2f)" % [worst, PLAYER_RADIUS])
