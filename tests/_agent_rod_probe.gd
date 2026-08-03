extends SceneTree
## TEMPORARY agent probe — delete after use.
## Rebuilds the held-rod chain OUTSIDE the world (no Main, no rig) and asks the one
## question a screenshot would: after ItemVisual.build + _normalize_hand_visual +
## _apply_hand_pose, is any of the rod inside the camera frustum?

const PC := preload("res://scripts/components/player_controller.gd")

## Copied verbatim from player_controller (that script cannot COMPILE under --script
## because the autoloads are absent, so its statics are unreachable here).
const HAND_ITEM_POS := Vector3(0.28, -0.24, -0.5)
const POSE := {
	"fishing_rod": {
		"axis": Vector3(0, 1, 0), "face": Vector3(1, 0, 0),
		"idle": {"axis_to": Vector3(0.34, 0.80, -0.50), "face_to": Vector3(0.0, 0.86, 0.51),
			"off": Vector3(0.08, 0.21, -0.04)},
	},
	"deep_rig_pole": {
		"axis": Vector3(0, 1, 0), "face": Vector3(1, 0, 0),
		"idle": {"axis_to": Vector3(-0.24, 0.93, -0.28), "face_to": Vector3(0.91, 0.18, 0.37),
			"off": Vector3(0.0, 0.12, -0.08)},
	},
}

static func _aim_basis(axis: Vector3, face: Vector3, axis_to: Vector3, face_to: Vector3) -> Basis:
	var a1: Vector3 = axis.normalized()
	var f1: Vector3 = face - a1 * face.dot(a1)
	var a2: Vector3 = axis_to.normalized()
	var f2: Vector3 = face_to - a2 * face_to.dot(a2)
	if f1.length() < 0.001:
		f1 = a1.cross(Vector3.UP if absf(a1.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)
	if f2.length() < 0.001:
		f2 = a2.cross(Vector3.UP if absf(a2.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)
	f1 = f1.normalized()
	f2 = f2.normalized()
	var s := Basis(a1, f1, a1.cross(f1))
	var t := Basis(a2, f2, a2.cross(f2))
	return t * s.transposed()

func _initialize() -> void:
	for id in ["fishing_rod", "deep_rig_pole"]:
		_check(id)
	quit()

func _basis_relative_to(node: Node3D, base: Node3D) -> Basis:
	var b: Basis = Basis.IDENTITY
	var cur: Node3D = node
	while cur != null and cur != base:
		b = cur.transform.basis * b
		cur = cur.get_parent() as Node3D
	return b

func _xf_relative_to(node: Node3D, base: Node3D) -> Transform3D:
	var t: Transform3D = Transform3D.IDENTITY
	var cur: Node3D = node
	while cur != null and cur != base:
		t = cur.transform * t
		cur = cur.get_parent() as Node3D
	return t

func _check(id: String) -> void:
	print("\n=== %s ===" % id)
	var visual: Node3D = ItemVisual.build(id)
	if visual == null:
		print("  BUILD RETURNED NULL")
		return
	# --- what _normalize_hand_visual measures ---
	var combined := AABB()
	var found := false
	var meshes := 0
	var stack: Array[Node] = [visual]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		meshes += 1
		var box: AABB = _xf_relative_to(mi, visual) * mi.mesh.get_aabb()
		combined = box if not found else combined.merge(box)
		found = true
	print("  meshes with geometry: %d   found=%s" % [meshes, found])
	if not found:
		print("  NO MESHES -> _normalize_hand_visual returns early, no pose, nothing scaled")
		return
	print("  combined AABB pos=%s size=%s" % [str(combined.position.snappedf(0.001)),
		str(combined.size.snappedf(0.001))])
	var largest: float = maxf(combined.size.x, maxf(combined.size.y, combined.size.z))
	var target: float = 0.18
	if id == "fishing_rod" or id == "deep_rig_pole":
		target = 0.9
	target = maxf(target, ItemVisual.hand_size_m(id))
	var hand_scale: float = (target / largest) if largest > 0.0001 else 1.0
	print("  largest=%.4f  target=%.3f  hand_scale=%.4f" % [largest, target, hand_scale])

	# --- rebuild the live node chain: camera -> _hand_item -> container -> visual ---
	var cam := Camera3D.new()
	cam.fov = 75.0
	var hand := Node3D.new()
	cam.add_child(hand)
	hand.position = HAND_ITEM_POS
	hand.rotation.y = -0.35
	hand.rotation.x = 0.15
	var container := Node3D.new()
	hand.add_child(container)
	container.add_child(visual)
	visual.position = -combined.get_center()

	var marker: Node = visual.find_child("hand_tip", true, false)
	print("  hand_tip present: %s" % str(marker is Node3D))
	var pivot: Node3D = null
	if marker is Node3D:
		pivot = (marker as Node3D).get_parent() as Node3D
	var b_pivot: Basis = Basis.IDENTITY
	if pivot != null and pivot != visual:
		b_pivot = _basis_relative_to(pivot, visual)
	var def: Dictionary = POSE[id]
	var pose: Dictionary = def["idle"]
	var aim: Basis = _aim_basis(def["axis"], def["face"], pose["axis_to"], pose["face_to"])
	var b: Basis = hand.transform.basis.inverse() * aim * b_pivot.inverse()
	container.transform = Transform3D(b.scaled(Vector3.ONE * hand_scale), pose["off"])

	# --- project every mesh corner into the camera's clip space ---
	var aspect: float = 16.0 / 9.0
	var near: float = 0.05
	var tan_half: float = tan(deg_to_rad(cam.fov) * 0.5)     # fov is VERTICAL in Godot
	var on: int = 0
	var total: int = 0
	var min_ndc := Vector2(1e9, 1e9)
	var max_ndc := Vector2(-1e9, -1e9)
	var nearest: float = 1e9
	var farthest: float = 0.0
	stack = [visual]
	while not stack.is_empty():
		var n2: Node = stack.pop_back()
		for c in n2.get_children():
			stack.append(c)
		var mi2 := n2 as MeshInstance3D
		if mi2 == null or mi2.mesh == null:
			continue
		var xf: Transform3D = _xf_relative_to(mi2, cam)
		var bx: AABB = xf * mi2.mesh.get_aabb()
		for i in range(8):
			var p: Vector3 = bx.get_endpoint(i)
			total += 1
			var d: float = -p.z
			nearest = minf(nearest, d)
			farthest = maxf(farthest, d)
			if d <= near:
				continue
			var ndc := Vector2(p.x / (d * tan_half * aspect), p.y / (d * tan_half))
			min_ndc = Vector2(minf(min_ndc.x, ndc.x), minf(min_ndc.y, ndc.y))
			max_ndc = Vector2(maxf(max_ndc.x, ndc.x), maxf(max_ndc.y, ndc.y))
			if absf(ndc.x) <= 1.0 and absf(ndc.y) <= 1.0:
				on += 1
	print("  corners on screen: %d / %d" % [on, total])
	print("  depth in front of eye: %.3f .. %.3f m (near plane %.3f)" % [nearest, farthest, near])
	print("  NDC x %.2f..%.2f   y %.2f..%.2f   (on screen = -1..1)"
		% [min_ndc.x, max_ndc.x, min_ndc.y, max_ndc.y])
	cam.free()
