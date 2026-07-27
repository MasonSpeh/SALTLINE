class_name ItemIcons extends Node
## Inventory icons, rendered from the items themselves.
##
## Owner call, 2026-07-26: the pack used to be a grid of wide buttons with the item's NAME
## written in them — "Salvaged Bottle", "Cooked Lantern Herring" — which is a list, not an
## inventory. Slots are square now and show the item, so a glance reads the pack.
##
## THE IDEA: don't author icon art. Every item in this game already has a 3D look —
## ItemVisual.build() returns the exact node the world puts on the ground and in your hand,
## including the real generated fish meshes. So an icon is just that node, photographed
## once: a tiny SubViewport with its own World3D, a key light, an orthogonal camera framed
## to the item's own bounding box, one frame, and the result copied into an ImageTexture.
##
## Consequences worth knowing:
##   * Icons can never drift from the world. Re-model an item and its icon re-renders to
##     match, because it IS the model. A hand-drawn icon set would have to be chased.
##   * Framing is per-item from its AABB, so scale is normalised: a 3.5 m oarfish and a
##     4 cm bolt both fill their slot. Real size is what the hand and the world are for.
##   * A species fish gets its actual species mesh and tint, so the pack distinguishes a
##     herring from a grouper without reading a word.
##
## Cost: one 96x96 render per DISTINCT item ever seen, amortised at one per frame and then
## cached for the session. The whole roster is ~50 items — under a second of background
## work, spread out, and it only happens for items the player actually acquires.

const ICON_PX: int = 96
## How much of the frame the item fills. 1.0 would have the widest item touching the edges
## and clipping its own outline under the slot's rounded corner; a little air reads better.
const FRAME_FILL: float = 0.78
## Three-quarter view. Straight-on renders a lot of this game's items — planks, plates,
## lids, fillets — as featureless rectangles; turning them shows thickness and silhouette.
const VIEW_DIR := Vector3(0.62, 0.55, 0.78)

signal icon_ready(item_id: String)

var _vp: SubViewport
var _cam: Camera3D
var _stage: Node3D                      ## the item under the camera, one at a time
var _cache: Dictionary = {}             ## item_id -> ImageTexture (or null = tried, no art)
var _queue: Array[String] = []
var _busy: bool = false

func _ready() -> void:
	name = "ItemIcons"
	_vp = SubViewport.new()
	_vp.size = Vector2i(ICON_PX, ICON_PX)
	# own_world_3d keeps the game world out: without it this camera would be sitting in the
	# middle of the rig, photographing the sea behind every bolt.
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_stage = Node3D.new()
	_vp.add_child(_stage)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)
	# An isolated World3D has no sun and no sky, so an unlit item renders as a silhouette.
	# A key light, a fill from the opposite side, and a lifted ambient floor give every item
	# readable form without any of them going to pure black in the shadowed corner.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -140, 0)
	key.light_energy = 1.5
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, 45, 0)
	fill.light_energy = 0.55
	fill.light_color = Color(0.82, 0.88, 1.0)
	_vp.add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.65, 0.7)
	env.ambient_light_energy = 1.0
	_cam.environment = env

## The icon for an item, or null if it is not rendered yet (or has no art). Safe to call
## every refresh: the first call for an id queues the render, later ones hit the cache.
## Listen to icon_ready to refresh the slot when it lands.
func get_icon(item_id: String) -> Texture2D:
	if _cache.has(item_id):
		return _cache[item_id]
	if not _queue.has(item_id):
		_queue.append(item_id)
	return null

func _process(_delta: float) -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	_render(_queue.pop_front())

func _render(item_id: String) -> void:
	for c in _stage.get_children():
		c.queue_free()
	var model: Node3D = null
	# ItemVisual builds from the same table the world does; an unknown id yields an empty
	# node rather than throwing, which the AABB check below turns into "no art".
	model = ItemVisual.build(item_id)
	if model == null:
		_finish(item_id, null)
		return
	_stage.add_child(model)
	# Wait a frame so children added inside _ready() (the fish meshes load theirs there)
	# exist before the bounds are measured — measuring too early frames an empty node and
	# renders a blank slot for exactly the items with the best art.
	await get_tree().process_frame
	var box: AABB = _bounds(model)
	if box.size.length() <= 0.0001:
		_finish(item_id, null)
		return
	# Frame it: orthogonal size from the item's largest on-screen extent, camera pulled
	# back along the view direction far enough that nothing crosses the near plane.
	var centre: Vector3 = box.position + box.size * 0.5
	var extent: float = maxf(maxf(box.size.x, box.size.y), box.size.z)
	_cam.size = maxf(extent, 0.001) / FRAME_FILL
	_cam.near = 0.01
	_cam.far = extent * 8.0 + 10.0
	_cam.global_position = centre + VIEW_DIR.normalized() * (extent * 3.0 + 1.0)
	_cam.look_at(centre, Vector3.UP)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img: Image = _vp.get_texture().get_image()
	# COPY into an ImageTexture. The SubViewport's own texture is a single reused target —
	# handing it out directly would give every slot the same picture, whichever item was
	# photographed last.
	_finish(item_id, ImageTexture.create_from_image(img) if img != null else null)

func _finish(item_id: String, tex: Texture2D) -> void:
	_cache[item_id] = tex
	for c in _stage.get_children():
		c.queue_free()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_busy = false
	icon_ready.emit(item_id)

## World-space bounds of every mesh under a node, in the node's own space.
func _bounds(root: Node3D) -> AABB:
	var out := AABB()
	var got: bool = false
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		# Into root space, so a part offset by its own transform still counts.
		var local: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		var b: AABB = local * mi.mesh.get_aabb()
		out = b if not got else out.merge(b)
		got = true
	return out if got else AABB()
