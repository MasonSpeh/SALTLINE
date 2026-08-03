extends Node
## AXIS ATLAS for the stand skeleton: one bone, one axis, +0.6 rad, one frame each.
## Reading these 15 frames back replaces guessing rotation signs with knowing them.
##   godot --path . res://tests/CatAxisDiag.tscn -- <out_dir>
const RIG := preload("res://scripts/world/cat_rig.gd")
const BASE := "res://assets/models/fauna/_rigged/cat_stand_idle.glb"
const PROBES := [
	["R_Thigh", 0], ["L_Thigh", 0], ["R_Thigh", 1], ["R_Thigh", 2],
	["R_Calf", 0],
	["R_Upperarm", 0], ["L_Upperarm", 0], ["R_Upperarm", 2],
	["R_Forearm", 0],
	["Spine01", 0], ["Spine01", 1], ["Spine01", 2],
	["NeckTwist01", 0], ["NeckTwist01", 1],
	["Head", 0],
	["Hip", 0], ["Hip", 2],
]
const AXES := [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "tests/out/cat_axes"
	DirAccess.make_dir_recursive_absolute(out)
	var vp := SubViewport.new()
	vp.size = Vector2i(520, 520)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -135, 0)
	key.light_energy = 1.6
	vp.add_child(key)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.68, 0.72)
	cam.environment = env
	vp.add_child(cam)
	var model: Node3D = (load(BASE) as PackedScene).instantiate()
	vp.add_child(model)
	await get_tree().process_frame
	# A floor at the rest paws — without one, "is it sitting ON something" is guesswork.
	var floor_mesh := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(6, 0.02, 6)
	floor_mesh.mesh = bx
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.33, 0.30)
	floor_mesh.material_override = fm
	vp.add_child(floor_mesh)
	for n in model.find_children("*", "AnimationPlayer", true, false):
		(n as AnimationPlayer).active = false
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var box := AABB()
	var first := true
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		box = (mi.global_transform * mi.get_aabb()) if first else box.merge(mi.global_transform * mi.get_aabb())
		first = false
	var centre: Vector3 = box.get_center()
	floor_mesh.position = Vector3(centre.x, box.position.y - 0.01, centre.z)
	var span: float = box.size.length() * 0.62
	cam.size = span * 1.25
	# Side view of the +X-authored mesh: look down -X? The body runs local X; camera on +Z
	# sees it side-on.
	cam.position = centre + Vector3(0.25, 0.18, 1.0).normalized() * span * 2.2
	cam.look_at(centre, Vector3.UP)
	# rest frame first
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("%s/rest.png" % out)
	for probe in PROBES:
		# reset all
		for i in range(sk.get_bone_count()):
			sk.set_bone_pose_rotation(i, sk.get_bone_rest(i).basis.get_rotation_quaternion())
		var bi: int = sk.find_bone(probe[0])
		if bi < 0:
			print("[axes] no bone ", probe[0])
			continue
		var rest: Quaternion = sk.get_bone_rest(bi).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(bi, rest * Quaternion(AXES[probe[1]], 0.6))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("%s/%s_ax%d.png" % [out, probe[0], probe[1]])
		print("[axes] %s ax%d" % [probe[0], probe[1]])
	print("[axes] done")
	get_tree().quit()
