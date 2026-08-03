extends Node
## Judges the s37 one-skeleton cat: every library pose applied to the STANDING mesh, and
## the transitions between them as strips.
##
## The pose transfer is an EMPIRICAL claim — donor rest rotations applied across two
## auto-rig fits of the same template — and this is the instrument that settles it. Two
## kinds of frame:
##   pose_<name>.png            the pose at 100% blend (is the transfer even right?)
##   trans_<a>_to_<b>_pN.png    eight steps of a live blend (is the JOURNEY sane — no limb
##                              sweeping through the body, no candy-wrapped spine?)
##
## WINDOWED (--headless never draws):
##   godot --path . res://tests/CatBlendShot.tscn -- <out_dir>

const RIG := preload("res://scripts/world/cat_rig.gd")
const SHOT_PX: int = 560
const BASE := "res://assets/models/fauna/_rigged/cat_stand_idle.glb"
const LIB := "res://assets/models/fauna/_rigged/cat_poses.json"
const POSES := ["stand", "sit", "groom", "walk", "run", "jump", "sleep", "stretch"]
const TRANSITIONS := [["walk", "sit"], ["sit", "groom"], ["run", "sit"], ["sleep", "stretch"]]

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "tests/out/cat_blend"
	DirAccess.make_dir_recursive_absolute(out)
	await _shoot(out)
	print("[blend] done")
	get_tree().quit()

func _bounds(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		acc = (mi.global_transform * mi.get_aabb()) if first \
			else acc.merge(mi.global_transform * mi.get_aabb())
		first = false
	return acc if not first else AABB()

func _shoot(out: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SHOT_PX, SHOT_PX)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -135, 0)
	key.light_energy = 1.5
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-8, 60, 0)
	fill.light_energy = 0.8
	vp.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.72)
	cam.environment = env
	vp.add_child(cam)

	var model: Node3D = (load(BASE) as PackedScene).instantiate()
	vp.add_child(model)
	await get_tree().process_frame
	var floor_mesh := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(6, 0.02, 6)
	floor_mesh.mesh = bx
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.33, 0.30)
	floor_mesh.material_override = fm
	vp.add_child(floor_mesh)
	for n in model.find_children("*", "AnimationPlayer", true, false):
		(n as AnimationPlayer).stop()
		(n as AnimationPlayer).active = false
	var skels: Array = model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		print("[blend] NO SKELETON")
		return
	var rig = RIG.new(skels[0] as Skeleton3D, LIB)
	print("[blend] valid=%s poses=%d" % [str(rig.valid()), rig.pose_count()])

	var box: AABB = _bounds(model)
	var centre: Vector3 = box.get_center()
	floor_mesh.position = Vector3(centre.x, box.position.y - 0.01, centre.z)
	var span: float = maxf(box.size.length() * 0.62, 0.1)
	cam.size = span * 1.2
	cam.position = centre + Vector3(1.0, 0.16, 0.30).normalized() * span * 2.2
	cam.look_at(centre, Vector3.UP)

	# Stills: force the blend to the target by ticking with a huge rate.
	for pose_name in POSES:
		if not rig.has_pose(pose_name):
			print("[blend] no pose: %s" % pose_name)
			continue
		rig.set_pose(pose_name, 100.0)
		for i in range(6):
			rig.tick(0.25, 0.0, 0.0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("%s/pose_%s.png" % [out, pose_name])
		print("[blend] pose_%s" % pose_name)
	# Transition strips: start hard at A, then blend live toward B at the shipping rate.
	for pair in TRANSITIONS:
		if not (rig.has_pose(pair[0]) and rig.has_pose(pair[1])):
			continue
		rig.set_pose(pair[0], 100.0)
		for i in range(6):
			rig.tick(0.25, 0.0, 0.0)
		rig.set_pose(pair[1], 6.0)
		for p in range(8):
			rig.tick(1.0 / 16.0, 0.0, 0.0)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png(
				"%s/trans_%s_to_%s_p%d.png" % [out, pair[0], pair[1], p])
	# Gait strip on the blended walk pose, phase advanced by fake distance.
	rig.set_pose("walk", 100.0)
	for i in range(6):
		rig.tick(0.25, 0.0, 0.0)
	for p in range(8):
		rig.tick(1.0 / 16.0, 1.55, 1.55 / 16.0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("%s/gait_p%d.png" % [out, p])
	vp.queue_free()
