extends Node
## Photographs a RAW GLB straight off disk, so a generated candidate can be judged
## before anything is wired into a species script. Text-to-3D is a lottery on unusual
## anatomy (four eyes, a hammer head) — this is how you buy several rolls and pick the
## winner by looking instead of trusting the first download.
##
## Renders into a per-shot SubViewport with its own World3D, the same isolation
## rod_shot.gd uses, so it never depends on an unoccluded game window.
##
##   godot --path . res://tests/CandShot.tscn -- <out_dir> <res://path.glb> [more.glb ...]

const SHOT_PX: int = 640
## Front is the view that decides the hammerhead (the eye X only reads head-on);
## side decides the bird silhouette. Both get the other angles as corroboration.
const VIEWS := {
	"front": Vector3(0.0, 0.06, 1.0),
	"side": Vector3(1.0, 0.10, 0.02),
	"threequarter": Vector3(0.72, 0.30, 0.62),
	"top": Vector3(0.02, 1.0, 0.12),
}

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("[cand] usage: <out_dir> <res://path.glb> ...")
		get_tree().quit()
		return
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	for i in range(1, args.size()):
		var path: String = args[i]
		var slug: String = path.get_file().get_basename()
		if not ResourceLoader.exists(path):
			print("[cand] %s: NOT IMPORTED (%s)" % [slug, path])
			continue
		for view in VIEWS:
			var img: Image = await _shoot(path, slug, VIEWS[view])
			if img == null:
				print("[cand] %s: no geometry" % slug)
				break
			img.save_png("%s/%s_%s.png" % [out, slug, view])
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

func _shoot(path: String, slug: String, dir: Vector3) -> Image:
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
	var scene: PackedScene = load(path)
	var model: Node3D = scene.instantiate()
	vp.add_child(model)
	await get_tree().process_frame
	var box: AABB = _bounds(model)
	if box.size.length() <= 0.0001 or not is_finite(box.size.length()):
		vp.queue_free()
		return null
	var centre: Vector3 = box.get_center()
	var span: float = maxf(maxf(box.size.x, maxf(box.size.y, box.size.z)), 0.1)
	cam.size = span * 1.1
	cam.position = centre + dir.normalized() * span * 2.0
	cam.look_at(centre, Vector3.UP)
	print("[cand] %-12s size=%s meshes=%d" % [slug, str(box.size.snappedf(0.01)),
		model.find_children("*", "MeshInstance3D", true, false).size()])
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img
