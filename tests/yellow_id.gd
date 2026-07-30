extends Node
## WHAT IS THAT YELLOW THING? Follow-up to tests/SpawnYellow.tscn, which found the pixels;
## this names the object behind them.
##
## Two ways of asking, both headless-safe (no rendering — an AABB walk and a camera ray are
## pure maths, and the project's viewport is 1280x720 either way, so a pixel from a windowed
## capture maps 1:1):
##
##   A. Shoot the camera's own ray through a given pixel of a given SpawnYellow frame and list
##      every drawn thing it crosses. Two corrections F9's _identify_looked_at does not make,
##      both of which cost a run: anything under the player is skipped (the flashlight is a
##      SpotLight3D with a 23 x 25 x 24 m AABB that swallows every ray, and F9's
##      is_in_group("player") test only looks at the node itself), and an AABB that CONTAINS
##      the ray origin is skipped — standing inside a 13 m MergedDressing chunk makes it the
##      nearest hit at 0.0 m for every pixel on screen, which is exactly what happened.
##
##   B. Dump every UNTEXTURED material within reach of the crate, of any hue. The yellow the
##      owner reports is a flat fill, and `MatLib.flat()` is documented as being for LIT
##      LENSES ONLY — so "untextured and a metre across" is the real signature, not "yellow".
##
##   godot --headless --path . res://tests/YellowId.tscn

const CRATE := Vector3(28.6, 2.0, -18.6)
const VIEW := Vector2(1280, 720)
## [tag, player position, yaw, pitch, pixel] — straight off the SpawnYellow frames.
const RAYS := [
	["crate_w_p-6_yaw90 blob", Vector3(25.6, 2.2, -18.6), 90.0, -6.0, Vector2(1140, 505)],
	["crate_e_p-26_yaw90 orange box", Vector3(31.0, 2.2, -18.6), 90.0, -26.0, Vector2(835, 310)],
	["crate_e_p-26_yaw90 blob", Vector3(31.0, 2.2, -18.6), 90.0, -26.0, Vector2(576, 351)],
]
const REACH: float = 12.0
var _t := 0.0
var _ran := false

func _ready() -> void:
	add_child((load("res://scenes/Main.tscn") as PackedScene).instantiate())

func _process(d: float) -> void:
	if _ran:
		return
	_t += d
	if _t < 6.0:
		return
	_ran = true
	var p: Node3D = get_tree().get_first_node_in_group("player")
	var cam: Camera3D = p.get("camera")
	print("\n[yid] ======== A. camera rays ========")
	for r in RAYS:
		p.global_position = r[1]
		p.rotation.y = deg_to_rad(float(r[2]))
		p.get_node("Head").rotation.x = deg_to_rad(float(r[3]))
		p.force_update_transform()
		cam.force_update_transform()
		await get_tree().process_frame
		var vs: Vector2 = cam.get_viewport().get_visible_rect().size
		var px: Vector2 = r[4]
		var at := Vector2(px.x / VIEW.x * vs.x, px.y / VIEW.y * vs.y)
		var o: Vector3 = cam.project_ray_origin(at)
		var dir: Vector3 = cam.project_ray_normal(at)
		print("\n[yid] --- %s   eye=%s dir=%s (viewport %s) ---"
			% [str(r[0]), str(o.snappedf(0.01)), str(dir.snappedf(0.001)), str(vs)])
		var hits: Array = []
		for vi in _all():
			var box: AABB = vi.global_transform * vi.get_aabb()
			if box.has_point(o):
				continue                       # standing inside it: tells you nothing
			if box.size.x > 20.0 or box.size.y > 20.0 or box.size.z > 20.0:
				continue
			var h: Variant = box.intersects_ray(o, dir)
			if h == null:
				continue
			var dd: float = o.distance_to(h as Vector3)
			if dd < 40.0:
				hits.append([dd, vi, box])
		hits.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		for i in range(mini(hits.size(), 5)):
			_say("#%d %.2fm" % [i, float(hits[i][0])], hits[i][1], hits[i][2])
	print("\n[yid] ======== B. every UNTEXTURED material within %.0f m of the crate ========" % REACH)
	var rows: Array = []
	for vi in _all():
		var box: AABB = vi.global_transform * vi.get_aabb()
		if box.get_center().distance_to(CRATE) > REACH:
			continue
		var m: BaseMaterial3D = _mat(vi)
		if m == null or m.albedo_texture != null:
			continue
		var vol: float = box.size.x * box.size.y * box.size.z
		rows.append([vol, vi, box, m])
	rows.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	print("[yid] %d untextured drawn nodes within reach" % rows.size())
	for i in range(mini(rows.size(), 26)):
		var m2: BaseMaterial3D = rows[i][3]
		_say("#%d vol=%.4f albedo=%s hue=%.0f sat=%.2f emis=%s" % [i, float(rows[i][0]),
			m2.albedo_color.to_html(false), m2.albedo_color.h * 360.0, m2.albedo_color.s,
			str(m2.emission_enabled)], rows[i][1], rows[i][2])
	print("\n[yid] ======== C. WHAT PROJECTS ONTO THAT PIXEL ========")
	# An AABB ray test is coarse and a merged chunk 10 m across swallows every ray, so ask the
	# opposite question: which SMALL drawn thing's own centre lands on this pixel? That is exact
	# for the size of object being hunted (a box, a drum lid, a blob) and immune to both.
	for r2 in RAYS:
		p.global_position = r2[1]
		p.rotation.y = deg_to_rad(float(r2[2]))
		p.get_node("Head").rotation.x = deg_to_rad(float(r2[3]))
		p.force_update_transform()
		cam.force_update_transform()
		await get_tree().process_frame
		var vs2: Vector2 = cam.get_viewport().get_visible_rect().size
		var px2: Vector2 = r2[4]
		var want := Vector2(px2.x / VIEW.x * vs2.x, px2.y / VIEW.y * vs2.y)
		print("\n[yid] --- %s   target pixel %s of %s ---" % [str(r2[0]), str(want), str(vs2)])
		var near: Array = []
		for vi in _all():
			var box2: AABB = vi.global_transform * vi.get_aabb()
			var c2: Vector3 = box2.get_center()
			if cam.is_position_behind(c2):
				continue
			if box2.size.length() > 4.0:
				continue                      # a merged chunk, not a prop
			var dd2: float = cam.unproject_position(c2).distance_to(want)
			if dd2 < 70.0:
				near.append([dd2, vi, box2])
		near.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		for i in range(mini(near.size(), 6)):
			_say("#%d %.0f px off, %.2f m out" % [i, float(near[i][0]),
				cam.global_position.distance_to((near[i][2] as AABB).get_center())],
				near[i][1], near[i][2])
	print("\n[yid] ======== D. MergedDressing chunks that carry a FLAT FILL ========")
	# rig_batcher welds the dressing by material, so a chunk's ONE material is the material the
	# author wrote. A chunk with no albedo_texture is therefore a chunk of hand-written
	# MatLib.flat() geometry — the thing docs/AGENT_TRAPS.md says keeps getting broken.
	for vi in _all():
		var par: Node = vi.get_parent()
		if par == null or not String(par.name).begins_with("MergedDressing"):
			continue
		var m3: BaseMaterial3D = _mat(vi)
		if m3 == null or m3.albedo_texture != null:
			continue
		var box3: AABB = vi.global_transform * vi.get_aabb()
		print("[yid] chunk albedo=%s hue=%.0f sat=%.2f  size=%s centre=%s  %.1f m from crate  %s"
			% [m3.albedo_color.to_html(false), m3.albedo_color.h * 360.0, m3.albedo_color.s,
				str(box3.size.snappedf(0.01)), str(box3.get_center().snappedf(0.01)),
				box3.get_center().distance_to(CRATE), String(vi.name)])
	get_tree().quit()

func _all() -> Array:
	var out: Array = []
	var stack: Array[Node] = [get_tree().current_scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var vi := n as GeometryInstance3D
		if vi == null or not vi.is_inside_tree() or _under_player(vi):
			continue
		if vi.get_aabb().size == Vector3.ZERO:
			continue
		out.append(vi)
	return out

func _under_player(n: Node) -> bool:
	var p: Node = n
	while p != null:
		if p.is_in_group("player"):
			return true
		p = p.get_parent()
	return false

func _mat(vi: GeometryInstance3D) -> BaseMaterial3D:
	if vi.get("material_override") is BaseMaterial3D:
		return vi.get("material_override")
	var mi := vi as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i in range(mi.mesh.get_surface_count()):
			var m: Material = mi.get_active_material(i)
			if m is BaseMaterial3D:
				return m
		if mi.mesh.get("material") is BaseMaterial3D:
			return mi.mesh.get("material")
	elif vi.get("material") is BaseMaterial3D:
		return vi.get("material")
	return null

func _say(head: String, vi: GeometryInstance3D, box: AABB) -> void:
	var mesh_class: String = "CSG/" + vi.get_class()
	var mi := vi as MeshInstance3D
	if mi != null and mi.mesh != null:
		mesh_class = mi.mesh.get_class()
	var m: BaseMaterial3D = _mat(vi)
	print("[yid] %s\n        %s\n        script=%s mesh=%s albedo=%s tex=%s size=%s centre=%s %.2f m from crate"
		% [head, _chain(vi), _owner(vi), mesh_class,
			m.albedo_color.to_html(false) if m != null else "(none)",
			str(m != null and m.albedo_texture != null),
			str(box.size.snappedf(0.01)), str(box.get_center().snappedf(0.01)),
			box.get_center().distance_to(CRATE)])

func _chain(n: Node) -> String:
	var s: String = String(n.name)
	var p: Node = n.get_parent()
	for i in range(6):
		if p == null or p == get_tree().current_scene:
			break
		s = "%s/%s" % [p.name, s]
		p = p.get_parent()
	return s

func _owner(n: Node) -> String:
	var p: Node = n
	while p != null:
		var s: Script = p.get_script()
		if s != null:
			return String(s.resource_path).get_file()
		p = p.get_parent()
	return "(no script ancestor)"
