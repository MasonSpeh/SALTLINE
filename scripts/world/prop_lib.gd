class_name PropLib extends RefCounted
## Loader for the CC0 glTF prop library in res://assets/models (Poly Haven, all
## CC0 — see assets/models/LICENSES.md). Call PropLib.spawn("metal_toolbox", ...)
## to get an instanced, scaled, optionally-collidable prop. Scenes are cached and
## duplicated per spawn. Missing models fall back to a labelled crate so a bad id
## never breaks a room.

const ROOT := "res://assets/models/"

static var _cache: Dictionary = {}     # id -> PackedScene (or null if absent)

## Real-world longest-axis size (m) per prop, so we can normalize wildly varying
## source scales to something that reads right on the deck. Tuned by eye.
const SIZE_HINT := {
	"Barrel_01": 0.9, "Barrel_02": 0.9, "barrel_03": 0.9, "barrel_stove": 1.0,
	"wooden_crate_01": 0.7, "wooden_crate_02": 0.7, "wooden_military_crate": 1.1,
	"old_military_crate": 0.9, "plastic_crate_01": 0.6, "plastic_crate_02": 0.5,
	"ammo_box": 0.5, "medical_box": 0.4, "utility_box_01": 0.4, "utility_box_02": 0.4,
	"metal_jerrycan": 0.5, "metal_jerrycan_green": 0.5, "plastic_jerrycan": 0.5,
	"propane_tank": 0.9, "small_lpg_tank": 0.7, "propane_torch": 0.5,
	"oil_tin": 0.3, "small_oil_can_01": 0.2, "cleaner_tin_01": 0.25, "can_rusted": 0.15,
	"russian_food_cans_01": 0.12, "long_life_food": 0.3,
	"metal_toolbox": 0.5, "metal_tool_chest": 0.9, "tool_cart": 0.9,
	"industrial_storage_cart": 1.1, "hand_truck": 1.3, "portable_welding_cart": 1.1, "pipe_wrench": 0.4,
	"korean_fire_extinguisher_01": 0.6, "fire_alarm": 0.2, "lifebuoy": 0.75,
	"life_jacket": 0.6, "ocean_buoy": 1.4, "old_gas_mask": 0.3, "WetFloorSign_01": 0.6,
	"wooden_bucket_01": 0.35, "wooden_bucket_02": 0.35, "metal_trash_can": 0.7, "cement_bag": 0.6,
	"Lantern_01": 0.35, "hanging_industrial_lamp": 0.4, "industrial_wall_lamp": 0.35,
	"industrial_pipe_lamp": 0.4, "caged_hanging_light": 0.4, "mounted_fluorescent_lights": 1.2,
	"security_light": 0.35, "vintage_flashlight": 0.25, "portable_searchlight": 0.5,
	"metal_stool_01": 0.6, "metal_stool_02": 0.6, "plastic_monobloc_chair_01": 0.85,
	"folding_wooden_stool": 0.5, "wooden_stool_01": 0.5, "painted_wooden_chair_01": 0.9,
	"metal_office_desk": 1.3, "dining_table": 1.6, "small_wooden_table_01": 0.9,
	"old_bed_frame": 2.0, "vintage_day_bed": 1.9,
	"steel_frame_shelves_01": 1.0, "steel_frame_shelves_02": 1.0, "worn_metal_rack": 1.0,
	"wooden_bookshelf_worn": 1.0, "drawer_cabinet": 0.9,
	"modified_thermos": 0.3, "plastic_thermos": 0.3, "vintage_electric_kettle": 0.3,
	"binder_notebook": 0.3, "office_notepads": 0.25,
	"vintage_radio_transceiver": 0.5, "boombox": 0.5, "retro_multimeter": 0.2,
	"television_02": 0.6, "power_box_01": 0.6, "portable_generator": 0.9,
	"modular_industrial_pipes_01": 2.0, "modular_pipes": 2.0,
	"wooden_ladder": 2.5, "ladder_sectioned_01": 3.0, "old_tyre": 0.7,
	# --- wave 2/3 furniture & decor ---
	"ArmChair_01": 0.95, "Sofa_01": 2.0, "WoodenChair_01": 0.9, "GreenChair_01": 0.9,
	"Ottoman_01": 0.7, "chinese_stool": 0.5, "bar_chair_round_01": 0.9, "dining_chair_02": 0.9,
	"Rockingchair_01": 1.0, "CoffeeTable_01": 1.1, "WoodenTable_01": 1.4, "WoodenTable_02": 1.4,
	"WoodenTable_03": 1.4, "chinese_tea_table": 1.2, "SchoolDesk_01": 1.1, "Shelf_01": 1.0,
	"GothicCabinet_01": 1.8, "ClassicNightstand_01": 0.6, "chinese_cabinet": 1.6,
	"anthurium_botany_01": 0.5, "calathea_orbifolia_01": 0.6, "fern_02": 0.5, "celandine_01": 0.3,
	"ceramic_pot": 0.4, "fir_sapling": 0.9, "brass_pan_01": 0.35, "brass_pot_01": 0.3,
	"brass_pot_02": 0.3, "ceramic_vase_01": 0.35, "ceramic_vase_02": 0.35, "ceramic_vase_03": 0.35,
	"brass_goblets": 0.15, "brass_vase_01": 0.4, "carrot_cake": 0.25, "croissant": 0.15,
	"bananas": 0.2, "food_apple_01": 0.1, "food_avocado_01": 0.12,
	"fancy_picture_frame_01": 0.5, "fancy_picture_frame_02": 0.5, "alarm_clock_01": 0.15,
	"decorative_book_set_01": 0.3, "book_encyclopedia_set_01": 0.35, "chess_set": 0.45,
	"dartboard": 0.5, "adjustable_wrench": 0.3, "bolt_cutters_01": 0.6, "crowbar_01": 0.7,
	"cross_pein_hammer": 0.35, "bench_vice_01": 0.35, "combination_wrench": 0.3,
	"cassette_player": 0.3, "classic_laptop": 0.35, "Camera_01": 0.15, "binoculars": 0.2,
	"bronze_whale_statue": 0.6, "bronze_shark_statue": 0.6, "bronze_ray_statue": 0.5,
	"Chandelier_01": 0.7, "ceiling_fan": 1.0, "clipboard": 0.3, "screwdriver": 0.25, "dustpan": 0.35,
}

static func has(id: String) -> bool:
	return ResourceLoader.exists(_path(id))

static func _path(id: String) -> String:
	return "%s%s/%s.gltf" % [ROOT, id, id]

static func _scene(id: String) -> PackedScene:
	if _cache.has(id):
		return _cache[id]
	var p := _path(id)
	var scene: PackedScene = null
	if ResourceLoader.exists(p):
		scene = load(p)
	_cache[id] = scene
	return scene

## Spawn a prop under `parent` at global `pos`.
##  yaw_deg   — rotation about Y
##  scale_mul — multiply the auto-normalized size (1.0 = size hint)
##  collide   — wrap in a StaticBody3D with an auto AABB box collider
##  target_m  — override the longest-axis size in meters (else SIZE_HINT / 1.0)
## Returns the spawned root Node3D (a fallback crate if the id is missing).
static func spawn(id: String, parent: Node3D, pos: Vector3, yaw_deg: float = 0.0,
		scale_mul: float = 1.0, collide: bool = false, target_m: float = -1.0) -> Node3D:
	var scene := _scene(id)
	if scene == null:
		return _fallback(id, parent, pos, yaw_deg)
	var inst: Node3D = scene.instantiate()
	# Normalize source scale to the target real-world size.
	var aabb := _aabb(inst)
	var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var want: float = target_m if target_m > 0.0 else float(SIZE_HINT.get(id, 0.6))
	var s: float = (want / longest) * scale_mul if longest > 0.0001 else scale_mul
	inst.scale = Vector3(s, s, s)
	inst.rotation.y = deg_to_rad(yaw_deg)
	var holder: Node3D = inst
	if collide:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size * s
		shape.shape = box
		shape.position = (aabb.position + aabb.size * 0.5) * s
		body.add_child(shape)
		body.add_child(inst)
		holder = body
	parent.add_child(holder)
	holder.global_position = pos
	return holder

## Convenience: scatter several ids near a point with slight jitter (deterministic
## by index so saves stay stable — no Math.random in this engine build anyway).
static func clutter(parent: Node3D, center: Vector3, ids: Array, spread: float = 0.5) -> void:
	for i in range(ids.size()):
		var a: float = i * 2.399963   # golden-angle spread
		var off := Vector3(cos(a), 0, sin(a)) * (spread * (0.4 + 0.6 * (float(i) / maxf(1.0, ids.size()))))
		spawn(str(ids[i]), parent, center + off, rad_to_deg(a) * 3.0)

static func _aabb(node: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for mi in _all_meshes(node):
		var mesh_aabb: AABB = mi.get_aabb()
		# Transform into the instance-root space.
		var xf: Transform3D = _relative_xform(node, mi)
		var t_aabb := xf * mesh_aabb
		if first:
			acc = t_aabb
			first = false
		else:
			acc = acc.merge(t_aabb)
	if first:
		return AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 0.6, 0.6))
	return acc

static func _relative_xform(root: Node3D, child: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = child
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

static func _all_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_meshes(c))
	return out

static func _fallback(id: String, parent: Node3D, pos: Vector3, yaw_deg: float) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var sz: float = float(SIZE_HINT.get(id, 0.5))
	bm.size = Vector3(sz, sz * 0.8, sz)
	bm.material = MatLib.weathered_wood()
	mi.mesh = bm
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, sz * 0.4, 0)
	mi.rotation.y = deg_to_rad(yaw_deg)
	return mi
