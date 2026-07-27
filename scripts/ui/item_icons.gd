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
## once: in a SubViewport with its own World3D, a key light, an orthogonal camera framed
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




var _cache: Dictionary = {}             ## item_id -> ImageTexture (or null = tried, no art)
var _queue: Array[String] = []
var _busy: bool = false

func _ready() -> void:
	name = "ItemIcons"

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

## Photograph ONE item in a viewport built for it and thrown away afterwards.
##
## The first version shared one long-lived SubViewport across every item, and every icon
## after the first came back with another item's geometry baked into it. Two plausible
## causes were fixed and NEITHER of them was it: deferred queue_free() leaving the outgoing
## model in the tree for a frame, and the capture racing the viewport's UPDATE_ONCE. Both
## were real bugs worth fixing; neither was this one.
##
## Rather than keep guessing at a shared mutable render target, each render now gets its own
## viewport, its own World3D and its own lights, and frees them when it is done. There is no
## state to leak between items because there is no shared state. That is also exactly how
## the per-item sheet in tests/inventory_shot.gd renders — which came out clean while the
## shared path did not, and was the evidence that the target itself was the variable.
##
## The cost is a SubViewport per DISTINCT item ever picked up, alive for about two frames.
## Against the alternative of a subtle wrong picture in the player's pack, that is nothing.
func _render(item_id: String) -> void:
	# ItemVisual builds from the same table the world does; an unknown id yields an empty
	# node rather than throwing, which the AABB check below turns into "no art".
	var model: Node3D = ItemVisual.build(item_id)
	if model == null:
		_finish(item_id, null, null)
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(ICON_PX, ICON_PX)
	# own_world_3d keeps the game world out: without it this camera would be sitting in the
	# middle of the rig, photographing the sea behind every bolt.
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# An isolated World3D has no sun and no sky, so an unlit item renders as a silhouette.
	# A key, a fill from the opposite side and a lifted ambient floor give every item
	# readable form without any of it going to pure black in the shadowed corner.
	# The background is CLEAR_COLOR, not CANVAS: BG_CANVAS pulls the 2D layer in behind the
	# subject, which is both wrong here and not what transparent_bg wants underneath it.
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.65, 0.7)
	env.ambient_light_energy = 1.0
	cam.environment = env
	vp.add_child(cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -140, 0)
	key.light_energy = 1.5
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, 45, 0)
	fill.light_energy = 0.55
	fill.light_color = Color(0.82, 0.88, 1.0)
	vp.add_child(fill)
	vp.add_child(model)
	# Wait a frame so children added inside _ready() (the fish meshes load theirs there)
	# exist before the bounds are measured — measuring too early frames an empty node and
	# renders a blank slot for exactly the items with the best art.
	await get_tree().process_frame
	var box: AABB = _bounds(model)
	if box.size.length() <= 0.0001:
		_finish(item_id, null, vp)
		return
	# Frame it: orthogonal size from the item's largest on-screen extent, camera pulled
	# back along the view direction far enough that nothing crosses the near plane.
	var centre: Vector3 = box.position + box.size * 0.5
	var extent: float = maxf(maxf(box.size.x, box.size.y), box.size.z)
	cam.size = maxf(extent, 0.001) / FRAME_FILL
	cam.near = 0.01
	cam.far = extent * 8.0 + 10.0
	cam.global_position = centre + VIEW_DIR.normalized() * (extent * 3.0 + 1.0)
	cam.look_at(centre, Vector3.UP)
	# Two frames: one to draw the framed subject, one to be certain it landed before the
	# texture is read back.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	# COPY into an ImageTexture — the viewport's own texture dies with the viewport below.
	_finish(item_id, ImageTexture.create_from_image(img) if img != null else null, vp)

func _finish(item_id: String, tex: Texture2D, vp: SubViewport) -> void:
	_cache[item_id] = tex
	if vp != null:
		remove_child(vp)     # out of the render tree at once; freed on the normal schedule
		vp.queue_free()
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
