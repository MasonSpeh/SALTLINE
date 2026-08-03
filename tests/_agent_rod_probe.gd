extends Node
## TEMPORARY agent probe — delete after use.
##
## Holds the fishing rod in the LIVE world and re-measures the held visual across the whole
## streaming window (render_budget sweeps to 22.5 s, rig_batcher fires on settle_done), asking
## the three questions a screenshot would answer: is anything parented under the hand, is it
## visible in tree, and does it project inside the frustum.
##
##   godot --headless --path . --script res://tests/_agent_rod_probe.gd

const SAMPLES: Array[float] = [6.0, 12.0, 20.0, 28.0, 34.0]

var _t: float = 0.0
var _next: int = 0
var _armed: bool = false

func _ready() -> void:
	add_child((load("res://scenes/Main.tscn") as PackedScene).instantiate())

func _process(d: float) -> void:
	_t += d
	if not _armed and _t > 4.0:
		_armed = true
		_equip()
	if _next >= SAMPLES.size():
		return
	if _t < SAMPLES[_next]:
		return
	_report(SAMPLES[_next])
	_next += 1
	if _next >= SAMPLES.size():
		get_tree().quit()

func _equip() -> void:
	var p: Node = get_tree().get_first_node_in_group("player")
	if p == null:
		print("NO PLAYER")
		get_tree().quit()
		return
	PlayerState.add_item("fishing_rod")
	for i in range(PlayerState.hotbar.size()):
		if str(PlayerState.hotbar[i]) == "fishing_rod":
			PlayerState.selected_hotbar = i
	p.call("_update_held_item")
	print("[probe] equipped, selected_hotbar=%d  held=%s"
		% [PlayerState.selected_hotbar, str(p.get("_held_item_id"))])

func _report(at: float) -> void:
	var p: Node = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	var hand: Node3D = p.get("_hand_item")
	var cam: Camera3D = p.get("camera")
	print("\n--- t=%.0fs ---" % at)
	if hand == null:
		print("  _hand_item is NULL")
		return
	print("  held id: '%s'   hand children: %d   hand.visible=%s in_tree=%s"
		% [str(p.get("_held_item_id")), hand.get_child_count(), str(hand.visible),
			str(hand.is_visible_in_tree())])
	print("  hand.position=%s  hand.rotation(deg)=%s  (built at (0.28,-0.24,-0.5) / (8.6,-20.1,0))"
		% [str(hand.position.snappedf(0.001)),
			str((hand.rotation * 180.0 / PI).snappedf(0.1))])
	if hand.get_child_count() == 0:
		print("  NOTHING IN HAND")
		return
	var container: Node3D = hand.get_child(0) as Node3D
	print("  container.visible=%s in_tree=%s  scale=%s  pos=%s"
		% [str(container.visible), str(container.is_visible_in_tree()),
			str(container.transform.basis.get_scale().snappedf(0.001)),
			str(container.position.snappedf(0.001))])
	var meshes: int = 0
	var hidden: int = 0
	var nolayer: int = 0
	var noshadow: int = 0
	var ranged: int = 0
	var alpha0: int = 0
	var on: int = 0
	var total: int = 0
	var nearest: float = 1e9
	var min_ndc := Vector2(1e9, 1e9)
	var max_ndc := Vector2(-1e9, -1e9)
	var aspect: float = 16.0 / 9.0
	var tan_half: float = tan(deg_to_rad(cam.fov) * 0.5)
	var cam_inv: Transform3D = cam.global_transform.affine_inverse()
	var stack: Array[Node] = [container]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		meshes += 1
		if not mi.is_visible_in_tree():
			hidden += 1
		if mi.layers == 0:
			nolayer += 1
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			noshadow += 1
		if mi.visibility_range_end > 0.0:
			ranged += 1
		var mat := mi.get_active_material(0) as StandardMaterial3D
		if mat != null and mat.albedo_color.a < 0.02:
			alpha0 += 1
		var bx: AABB = (cam_inv * mi.global_transform) * mi.mesh.get_aabb()
		for i in range(8):
			var q: Vector3 = bx.get_endpoint(i)
			total += 1
			var dd: float = -q.z
			nearest = minf(nearest, dd)
			if dd <= cam.near:
				continue
			var ndc := Vector2(q.x / (dd * tan_half * aspect), q.y / (dd * tan_half))
			min_ndc = Vector2(minf(min_ndc.x, ndc.x), minf(min_ndc.y, ndc.y))
			max_ndc = Vector2(maxf(max_ndc.x, ndc.x), maxf(max_ndc.y, ndc.y))
			if absf(ndc.x) <= 1.0 and absf(ndc.y) <= 1.0:
				on += 1
	print("  meshes=%d  hidden=%d  layers==0: %d  shadow_off=%d  vis_range_set=%d  alpha0=%d"
		% [meshes, hidden, nolayer, noshadow, ranged, alpha0])
	print("  corners on screen %d/%d   nearest %.3f m (cam.near %.3f)  cull_mask=%d"
		% [on, total, nearest, cam.near, cam.cull_mask])
	print("  NDC x %.2f..%.2f  y %.2f..%.2f" % [min_ndc.x, max_ndc.x, min_ndc.y, max_ndc.y])
