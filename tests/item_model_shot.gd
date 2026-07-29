extends Node
## Photographs an INVENTORY ITEM's real mesh — PropLib.item_model(id) — so a mapping or a
## freshly generated GLB can be judged before it is wired in front of a player.
##
## CandShot photographs a raw GLB off disk; this photographs what the game would actually
## build for an item id, which is the thing that has to look right: the library prop after
## it has been picked down to one object, scaled to its real size and stood on the deck.
##
## Every item gets FOUR pictures, and the fourth is the one that decides it:
##   full/side/top — 512 px, is this recognisably the object?
##   icon          — 96 px, framed exactly the way ui/item_icons.gd frames a pack slot.
##                   Half the things that read fine at 512 are a smudge at 96, and 96 is
##                   where the player meets them.
##
##   godot --path . res://tests/ItemModelShot.tscn -- <out_dir> <item_id> [item_id ...]

const SHOT_PX: int = 512
## Mirrors ui/item_icons.gd exactly (ICON_PX / FRAME_FILL / VIEW_DIR). Kept as literals
## rather than reaching into ItemIcons: that is a Node with a render queue and a cache,
## and this harness must not depend on any of it to take a picture.
const ICON_PX: int = 96
const ICON_FILL: float = 0.78
const ICON_DIR := Vector3(0.62, 0.55, 0.78)

const VIEWS := {
	"full": Vector3(0.62, 0.55, 0.78),
	"side": Vector3(1.0, 0.10, 0.02),
	"top": Vector3(0.02, 1.0, 0.12),
}

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("[item] usage: <out_dir> <item_id> ...")
		get_tree().quit()
		return
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	for i in range(1, args.size()):
		var id: String = args[i]
		if not PropLib.has_item_model(id):
			print("[item] %-18s NO MODEL (neither generated nor mapped)" % id)
			continue
		for view in VIEWS:
			var img: Image = await _shoot(id, VIEWS[view], SHOT_PX, 1.1)
			if img == null:
				print("[item] %-18s no geometry" % id)
				break
			img.save_png("%s/%s_%s.png" % [out, id, view])
		var icon: Image = await _shoot(id, ICON_DIR, ICON_PX, 1.0 / ICON_FILL)
		if icon != null:
			icon.save_png("%s/%s_icon.png" % [out, id])
	get_tree().quit()

func _bounds(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		var world: AABB = mi.global_transform * mi.get_aabb()
		acc = world if first else acc.merge(world)
		first = false
	return acc if not first else AABB()

## One picture in its own SubViewport with its own World3D — the isolation ItemIcons
## settled on after a shared render target leaked one item's geometry into the next one's
## icon. Nothing is reused between shots here for the same reason.
func _shoot(id: String, dir: Vector3, px: int, pad: float) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
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
	var model: Node3D = PropLib.item_model(id)
	if model == null:
		vp.queue_free()
		return null
	vp.add_child(model)
	await get_tree().process_frame
	var box: AABB = _bounds(model)
	if box.size.length() <= 0.0001 or not is_finite(box.size.length()):
		vp.queue_free()
		return null
	var centre: Vector3 = box.get_center()
	var span: float = maxf(maxf(box.size.x, maxf(box.size.y, box.size.z)), 0.02)
	cam.size = span * pad
	cam.position = centre + dir.normalized() * span * 2.5
	cam.look_at(centre, Vector3.UP)
	if px == SHOT_PX and dir == VIEWS["full"]:
		print("[item] %-18s size=%s meshes=%d" % [id, str(box.size.snappedf(0.01)),
			model.find_children("*", "MeshInstance3D", true, false).size()])
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img
