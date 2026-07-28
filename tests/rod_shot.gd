extends Node
## Photographs ONE item's ItemVisual on its own, from several angles, so a geometry claim
## ("this reads as a heavy offshore rod") can be looked at rather than asserted.
##
## Renders into a per-shot SubViewport with its own World3D — the same isolation
## ui/item_icons.gd uses — so nothing depends on the game window being unoccluded.
##
##   godot --path . res://tests/RodShot.tscn -- <out_dir> [item_id ...]

const SHOT_PX: int = 640
## Angles worth judging a held tool by: the side-on silhouette, a three-quarter that shows
## the reel standing off the seat, the pack's own icon direction, and a close butt view.
const VIEWS := {
	"side": Vector3(0.05, 0.10, 1.0),
	"threequarter": Vector3(0.62, 0.35, 0.78),
	"icon": Vector3(0.62, 0.55, 0.78),
	"reelside": Vector3(-0.75, 0.25, 0.55),
}

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp"
	var ids: Array = []
	for i in range(1, args.size()):
		ids.append(args[i])
	if ids.is_empty():
		ids = ["fishing_rod"]
	DirAccess.make_dir_recursive_absolute(out)
	for id in ids:
		for view in VIEWS:
			var img: Image = await _shoot(String(id), VIEWS[view])
			if img == null:
				print("[rod] %s: no geometry" % id)
				continue
			print("[rod] %s/%s_%s.png err=%d" % [out, id, view,
				img.save_png("%s/%s_%s.png" % [out, id, view])])
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

func _shoot(item_id: String, dir: Vector3) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(SHOT_PX, SHOT_PX)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -140, 0)
	key.light_energy = 1.6
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 55, 0)
	fill.light_energy = 0.7
	fill.light_color = Color(0.8, 0.87, 1.0)
	vp.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.14, 0.15, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.64, 0.7)
	env.ambient_light_energy = 1.0
	cam.environment = env
	vp.add_child(cam)
	var model: Node3D = ItemVisual.build(item_id)
	vp.add_child(model)
	await get_tree().process_frame
	var box: AABB = _bounds(model)
	if box.size.length() <= 0.0001 or not is_finite(box.size.length()):
		vp.queue_free()
		return null
	var centre: Vector3 = box.get_center()
	var span: float = maxf(maxf(box.size.x, maxf(box.size.y, box.size.z)), 0.2)
	cam.size = span * 1.12   # the LONGEST axis plus air, or a rod loses its butt off-frame
	cam.position = centre + dir.normalized() * span * 2.0
	cam.look_at(centre, Vector3.UP)
	# Report what the framing camera and the hand normaliser will actually see, plus the
	# marker the fishing line hangs off — a screenshot cannot show a NaN or a lost node.
	var marker: Node = model.find_child("hand_tip", true, false)
	print("[rod] %-14s aabb pos=%s size=%s meshes=%d hand_tip=%s" % [item_id,
		str(box.position.snappedf(0.001)), str(box.size.snappedf(0.001)),
		model.find_children("*", "MeshInstance3D", true, false).size(),
		str((marker as Node3D).global_position.snappedf(0.001)) if marker is Node3D else "MISSING"])
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img
