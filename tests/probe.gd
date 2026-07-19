extends Node3D
## Narrow geometry query tool. Boots the REAL Main scene and, for each point in
## QUERIES, reports the nearest VISUAL mesh surfaces around it — meshes, not physics,
## because most rig dressing is non-colliding and a raycast under-reports badly.
##
## Containment is tested in each mesh's OWN local space (an exact oriented-box test).
## Testing world-space AABBs instead passes everything: the rig is full of rotated
## pipes and derrick steel whose axis-aligned world bounds enclose many times the
## volume they occupy, so a point in open air lands "inside" a girder metres away.
##
## This is deliberately NOT a pass/fail gate over every Label3D. That version was
## written first and its verdict swung between 0 and 67 unbacked across runs, because
## glyph-quad extents are guesswork and the sample points wander off panel edges.
## Run: --headless res://tests/Probe.tscn

# label / snail sites under review — world point, and what it is supposed to sit on
const QUERIES := [
	["GALLEY sign (known good)", Vector3(6.6, 20.4, 7.9)],
	["bdeck sign", Vector3(0.0, 20.6, 2.55)],
	["PIPE DECK old", Vector3(13.0, 19.7, -17.5)],
	["FLARE BOOM old", Vector3(-28.0, 19.35, -16.32)],
	["SPAN OUT old", Vector3(50.07, 19.45, 19.38)],
	["LIFEBOAT 2 old", Vector3(-10.5, 18.04, -17.9)],
]

# x/z columns to scan vertically, to find what surface is actually underfoot
const COLUMNS := []

var _meshes: Array[GeometryInstance3D] = []

func _ready() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	_collect(main)
	print("PROBE meshes=%d" % _meshes.size())
	for q in QUERIES:
		_report(String(q[0]), q[1])
	for c in COLUMNS:
		_raydown(String(c[0]), c[1])
	print("PROBE DONE")
	get_tree().quit()

func _collect(n: Node) -> void:
	# GeometryInstance3D, not MeshInstance3D: the rig's PRIMARY structure — decks,
	# pontoons, bulkheads, caissons — is built from CSGBox3D. Collecting only
	# MeshInstance3D sees just the decorative detail layer and reports solid steel
	# bulkheads as open air.
	if n is GeometryInstance3D and not (n is Label3D):
		# Skip world-scale volumes — the sky dome (3200 units across) and the ocean
		# planes enclose the whole rig, so they "contain" every point tested.
		var sz: Vector3 = (n as GeometryInstance3D).get_aabb().size
		if maxf(sz.x, maxf(sz.y, sz.z)) < 200.0:
			_meshes.append(n)
	for c in n.get_children():
		_collect(c)

## Distance from world point `q` to a mesh's oriented bounds (0 = inside).
func _dist(mi: GeometryInstance3D, q: Vector3) -> float:
	var ab: AABB = mi.get_aabb()
	var lq: Vector3 = mi.global_transform.affine_inverse() * q
	var c: Vector3 = ab.get_center()
	var h: Vector3 = ab.size * 0.5
	return Vector3(maxf(absf(lq.x - c.x) - h.x, 0.0), maxf(absf(lq.y - c.y) - h.y, 0.0),
		maxf(absf(lq.z - c.z) - h.z, 0.0)).length()

func _report(label: String, q: Vector3) -> void:
	var best: Array = []
	for mi in _meshes:
		var d: float = _dist(mi, q)
		if d < 1.2:
			best.append([d, mi])
	best.sort_custom(func(a, b): return a[0] < b[0])
	if best.is_empty():
		print("QUERY %-24s @%s -> NOTHING within 1.2m (open air)" % [label, str(q)])
		return
	var out: String = ""
	for i in range(mini(6, best.size())):
		var mi: GeometryInstance3D = best[i][1]
		out += "\n    %.3fm %s size=%s at=%s" % [best[i][0], mi.name, str(mi.get_aabb().size), str(mi.global_position)]
	print("QUERY %-24s @%s ->%s" % [label, str(q), out])

## Walk a vertical column and print every solid/air transition — the reliable way to
## find what a creature is actually standing on (or buried in).
func _column(label: String, xz: Vector2) -> void:
	var out: String = ""
	var prev: bool = false
	var y: float = 4.0
	while y > -4.0:
		var solid: bool = false
		for mi in _meshes:
			if _dist(mi, Vector3(xz.x, y, xz.y)) <= 0.0:
				solid = true
				break
		if solid != prev:
			out += " %s@%.2f" % ["ENTER" if solid else "EXIT", y]
			prev = solid
		y -= 0.02
	print("COLUMN %-22s (x=%.2f z=%.2f) ->%s" % [label, xz.x, xz.y, out if out != "" else " all air"])

## Physics raycast straight down onto the world colliders — this is what a runtime
## "settle onto the surface" helper will actually see, as opposed to the visual-mesh
## scan above (which includes non-colliding dressing).
func _raydown(label: String, xz: Vector2) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from := Vector3(xz.x, 4.0, xz.y)
	var to := Vector3(xz.x, -4.0, xz.y)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		print("RAY %-22s (x=%.2f z=%.2f) -> NO HIT" % [label, xz.x, xz.y])
	else:
		print("RAY %-22s (x=%.2f z=%.2f) -> y=%.3f on %s" % [label, xz.x, xz.y,
			hit["position"].y, str(hit["collider"].name)])
