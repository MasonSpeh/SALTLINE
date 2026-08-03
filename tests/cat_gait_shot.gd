extends Node
## Photographs the HAND-WRITTEN cat gait (scripts/world/cat_rig.gd) across its cycle, so
## the question "does FK on Tripo's asymmetric rig actually read as a walking cat" gets
## answered by looking instead of by hoping.
##
## The comparison that matters is against tests/out/cat_anim, which is the same mesh under
## Tripo's own retargeted clip — the one that photographs as a wrung-out cat. If this strip
## is not clearly better than that one, the rig route is dead and the honest move is to say
## so rather than ship a worse animal with more machinery behind it.
##
## WINDOWED (--headless never draws, and a skinned mesh's pose only reaches the frame
## through the renderer):
##   godot --path . res://tests/CatGaitShot.tscn -- <out_dir>

const RIG := preload("res://scripts/world/cat_rig.gd")
const SHOT_PX: int = 560
const PHASES: int = 8
const MODEL := "res://assets/models/fauna/_rigged/cat_walk_walk.glb"

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "tests/out/cat_gait"
	DirAccess.make_dir_recursive_absolute(out)
	await _shoot(out)
	print("[gait] done")
	get_tree().quit()

func _bounds(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var world: AABB = mi.global_transform * mi.get_aabb()
		acc = world if first else acc.merge(world)
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
	fill.light_color = Color(0.82, 0.88, 1.0)
	vp.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.ambient_light_energy = 1.0
	cam.environment = env
	vp.add_child(cam)

	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	vp.add_child(model)
	await get_tree().process_frame

	# Tripo's own clip must be STOPPED or it fights every pose written here — and it would
	# win, because AnimationPlayer writes the skeleton after this does.
	for n in model.find_children("*", "AnimationPlayer", true, false):
		(n as AnimationPlayer).stop()
		(n as AnimationPlayer).active = false
	var skels: Array = model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		print("[gait] NO SKELETON — nothing to drive")
		return
	var rig = RIG.new(skels[0] as Skeleton3D)
	print("[gait] rig valid=%s bones=%d" % [str(rig.valid()), (skels[0] as Skeleton3D).get_bone_count()])
	if not rig.valid():
		print("[gait] the limb bones were not found — check the names in bone_dump output")
		return

	var box: AABB = _bounds(model)
	var centre: Vector3 = box.get_center()
	var span: float = maxf(maxf(box.size.x, maxf(box.size.y, box.size.z)), 0.1)
	cam.size = span * 1.15
	cam.position = centre + Vector3(1.0, 0.10, 0.02).normalized() * span * 2.0
	cam.look_at(centre, Vector3.UP)

	for m in ["walk", "trot", "bound"]:
		for p in range(PHASES):
			rig.rest_pose()
			rig.walk(float(p) / float(PHASES), 0.42, m)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s/gait_%s_p%d.png" % [out, m, p])
	# The three still states, one frame each — enough to see the pose is not broken.
	for st in ["idle", "groom", "sleep"]:
		rig.rest_pose()
		if st == "idle":
			rig.idle(1.7)
		elif st == "groom":
			rig.groom(2.0)
		else:
			rig.sleep(1.0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("%s/pose_%s.png" % [out, st])
	vp.queue_free()
