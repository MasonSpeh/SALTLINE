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

## Rendered at more than the 74 px the slot draws it at, so the downscale supersamples.
## An item like the rod is all thin hardware, and at 1:1 its guides alias into nothing.
const ICON_PX: int = 160
## How much of the frame the item fills. 1.0 would have the widest item touching the edges
## and clipping its own outline under the slot's rounded corner; a little air reads better.
const FRAME_FILL: float = 0.86
## Three-quarter view. Straight-on renders a lot of this game's items — planks, plates,
## lids, fillets — as featureless rectangles; turning them shows thickness and silhouette.
const VIEW_DIR := Vector3(0.62, 0.55, 0.78)

## ICONS ARE READ AT SLOT SIZE, AND SOME ITEMS CANNOT SURVIVE THAT WHOLE.
##
## Owner report, 2026-07-28: the rebuilt deep-sea rod "isn't showing on the item". It was
## showing — the world copy and the in-hand copy are the new 57-mesh offshore rig, and
## ItemVisual.build() hands this renderer the same node. What failed is the FRAME. The rod
## is 1.90 m long and 3.6 cm through the blank: a 53:1 sliver. Fitted whole into a square
## 74 px slot, the blank comes out ONE pixel wide, in dark graphite, on a dark slot — the
## slot reads as empty, and every part of the rebuild that carries the "offshore" claim
## (the lever-drag multiplier, the stepped guides, the gimbal) is far below a pixel.
##
## No amount of resolution fixes a ratio, so these items are framed on their business end
## instead: the box below is in the item's own model metres (the same coordinates the case
## in item_visual.gd is written in), and what it contains is what the icon shows. The
## world and the hand still show the whole tool — that is where length is legible.
##
## Anything not listed here is framed to its full extent exactly as before.
const ICON_FOCUS := {
	# Reel seat, lever-drag multiplier, foregrip and the first two guides — the part of a
	# stand-up rod you would recognise it from across a deck.
	"fishing_rod": {"centre": Vector3(0.06, 0.62, 0.0), "size": 0.62},
	# The deep rig reads from its line drum and the taped grip.
	"deep_rig_pole": {"centre": Vector3(-0.02, 0.36, 0.02), "size": 0.44},
	# 1.35 m of driftwood shaft; the lashing and the shard point are the whole read.
	"crude_spear": {"centre": Vector3(0.17, 1.16, 0.0), "size": 0.5},
}

signal icon_ready(item_id: String)
signal preview_ready(item_id: String)

# ======================= the pack's real-size fish preview =======================
# Owner spec, 2026-07-28: clicking a slot that holds a fish shows that fish AT ITS REAL
# SIZE, not a uniform thumbnail — a sprat and a giant oarfish must be obviously different
# animals, and the deep-water giants must fill the screen.
#
# Size comes from data/fish.json via ItemVisual.fish_length_m() — see the long note there
# for why the schema's size_kg (a landed WEIGHT) and this file's authored body lengths are
# combined the way they are. Everything below is FRAMING; none of it invents a size.

## Rendered wide, because the extreme case is a ribbon: the giant oarfish is 3.5 m of fish
## about 0.3 m deep, and a square frame would fit it by shrinking it to a thread.
const PREVIEW_PX := Vector2i(1180, 660)
## Near side-on, lifted a little. Fish meshes are built nose-to-−X (item_visual.build yaws
## the generated ones round for exactly this reason), so this is the flank view — the one
## angle where length reads as length.
const PREVIEW_VIEW_DIR := Vector3(0.10, 0.30, 1.0)
## The largest fish fills this much of the frame; nothing ever exceeds it, so every species
## is whole and clear of the edges. The one deliberate exception is CROP_TO_HEAD below.
const PREVIEW_MAX_FILL: float = 0.94
## ...and the smallest never drops below this, or a sprat would be a speck with no shape.
const PREVIEW_MIN_FILL: float = 0.17
## Frame share against real length. A straight ratio across a 7.8:1 length spread (sprat
## 0.45 m to oarfish 3.5 m) is honest but leaves everything under a metre tiny and pushes
## the mid-range fish together; a mild gamma keeps the ORDER and the obviousness of the
## spread while giving the deep-water giants the screen the owner asked for.
const PREVIEW_GAMMA: float = 0.75

## THE ONE FISH THAT IS NOT ALLOWED TO FIT.
##
## Owner spec: everything is fully visible "EXCEPT the full goliath grouper", framed so its
## head fills the view and it feels too big for the frame. The roster's goliath grouper is
## the Barrel Grouper — the game already calls it that in so many words (underwater_world's
## DeepGiant deepens its shoulder until it "reads ... as a goliath grouper"), it is the
## heaviest thing the rod itself can land, and it is the only grouper there is. The COOKED
## id is a fillet on a board, not a fish, so it frames normally like every other meal.
const CROP_TO_HEAD := {"fish_barrel_grouper": true}
## How much of the fish's body depth the cropped frame holds — under 1.0, so the animal
## runs off every edge. Small enough to read as "head", big enough to keep the eye and jaw.
const HEAD_CROP_FILL: float = 0.62

var _cache: Dictionary = {}             ## item_id -> ImageTexture (or null = tried, no art)
var _previews: Dictionary = {}          ## item_id -> ImageTexture, the big fish renders
var _queue: Array[String] = []
var _preview_queue: Array[String] = []
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

## The big real-size render of a fish, or null until it lands (listen to preview_ready).
## Same contract as get_icon, separate cache: a 1180x660 preview is not a 160 px icon.
func get_preview(item_id: String) -> Texture2D:
	if _previews.has(item_id):
		return _previews[item_id]
	if not _preview_queue.has(item_id):
		_preview_queue.append(item_id)
	return null

func _process(_delta: float) -> void:
	if _busy:
		return
	# Previews jump the queue: a player has just clicked a slot and is waiting on one,
	# while icons are background work for slots that already show their name and count.
	if not _preview_queue.is_empty():
		_busy = true
		_render_preview(_preview_queue.pop_front())
		return
	if _queue.is_empty():
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
	var stage: Array = _stage(Vector2i(ICON_PX, ICON_PX))
	var vp: SubViewport = stage[0]
	var cam: Camera3D = stage[1]
	vp.add_child(model)
	# Wait a frame so children added inside _ready() (the fish meshes load theirs there)
	# exist before the bounds are measured — measuring too early frames an empty node and
	# renders a blank slot for exactly the items with the best art.
	await get_tree().process_frame
	var box: AABB = _bounds(model)
	if box.size.length() <= 0.0001:
		_finish(item_id, null, vp)
		return
	var focus: Dictionary = ICON_FOCUS.get(item_id, {})
	var centre: Vector3 = focus["centre"] if focus.has("centre") else box.position + box.size * 0.5
	var reach: float = maxf(box.size.length(), 0.001)
	cam.near = 0.01
	cam.far = reach * 8.0 + 10.0
	# The camera is placed and aimed BEFORE the frame is sized, because the fit below reads
	# the basis this look_at produces.
	cam.global_position = centre + VIEW_DIR.normalized() * (reach * 3.0 + 1.0)
	cam.look_at(centre, Vector3.UP)
	# Size the frame to what the camera will ACTUALLY see, not to the item's longest world
	# axis. An orthogonal camera shows a rectangle of the view plane, so a metre of plank
	# lying along the view direction costs no frame at all; measuring in world axes zoomed
	# every long item further out than it needed to be, and made it smaller in its slot.
	var span: Vector2 = screen_span(box, cam)
	cam.size = maxf(float(focus["size"]) if focus.has("size") else maxf(span.x, span.y),
		0.001) / FRAME_FILL
	# Two frames: one to draw the framed subject, one to be certain it landed before the
	# texture is read back.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	# COPY into an ImageTexture — the viewport's own texture dies with the viewport below.
	_finish(item_id, ImageTexture.create_from_image(img) if img != null else null, vp)

func _finish(item_id: String, tex: Texture2D, vp: SubViewport) -> void:
	_cache[item_id] = tex
	_drop_stage(vp)
	icon_ready.emit(item_id)

## A one-shot photographic stage: its own World3D, an orthogonal camera and a key/fill pair
## over a lifted ambient floor. Returns [SubViewport, Camera3D]; the caller adds the model,
## frames the camera, reads the texture back and hands the viewport to _drop_stage. Both the
## slot icon and the fish preview photograph the same way — only the frame and the subject
## differ — so they share one stage rather than two drifting copies of it.
func _stage(px: Vector2i) -> Array:
	var vp := SubViewport.new()
	vp.size = px
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
	return [vp, cam]

func _drop_stage(vp: SubViewport) -> void:
	if vp != null:
		remove_child(vp)     # out of the render tree at once; freed on the normal schedule
		vp.queue_free()
	_busy = false

## Photograph a fish AT ITS REAL SIZE for the pack preview.
##
## The frame is fixed by the species' body length, so the picture answers "how big is this
## thing" rather than "what shape is it": a copper sprat comes back a fifth of the frame, a
## giant oarfish fills it corner to corner, and the difference between them is the data's,
## not a designer's. See ItemVisual.fish_length_m() for where the length comes from.
func _render_preview(item_id: String) -> void:
	var model: Node3D = ItemVisual.build(item_id)
	if model == null:
		_finish_preview(item_id, null, null)
		return
	var stage: Array = _stage(PREVIEW_PX)
	var vp: SubViewport = stage[0]
	var cam: Camera3D = stage[1]
	vp.add_child(model)
	# Same reason as the icon path: the generated fish meshes load their geometry in
	# _ready(), so measuring before the next frame frames an empty node.
	await get_tree().process_frame
	var box: AABB = _bounds(model)
	if box.size.length() <= 0.0001:
		_finish_preview(item_id, null, vp)
		return
	var species: String = item_id.trim_prefix("cooked_")
	var centre: Vector3 = box.position + box.size * 0.5
	var reach: float = maxf(box.size.length(), 0.001)
	cam.near = 0.01
	cam.far = reach * 8.0 + 10.0
	cam.global_position = centre + PREVIEW_VIEW_DIR.normalized() * (reach * 3.0 + 1.0)
	cam.look_at(centre, Vector3.UP)
	var span: Vector2 = screen_span(box, cam)
	var aspect: float = float(PREVIEW_PX.x) / float(PREVIEW_PX.y)
	if CROP_TO_HEAD.has(species) and not item_id.begins_with("cooked_"):
		# Deliberately too big for the frame. Sizing off the BODY DEPTH rather than the
		# length is what makes it overrun: at 62% of its own shoulder the grouper's head
		# and jaw fill the view and every edge of the animal is off-frame.
		cam.size = maxf(span.y * HEAD_CROP_FILL, 0.001)
		# Fish are built nose-to-−X (see PREVIEW_VIEW_DIR), so the head is the −X end. Slide
		# the frame onto it along the camera's own right axis, stopping about two thirds of a
		# body depth in from the snout: dead on the nose leaves a third of the frame empty
		# ahead of the fish, which reads as a badly aimed camera rather than a crop.
		var head_x: float = box.position.x + box.size.y * 0.7
		var right: Vector3 = cam.global_transform.basis.x
		cam.global_position += right * ((head_x - centre.x) * right.x)
	else:
		# Frame share from real length, then the frame that gives the fish exactly that
		# share of whichever axis binds first — so a deep-bodied grouper is held by its
		# shoulder and a ribbon oarfish by its length, and NEITHER touches an edge.
		var fill: float = clampf(pow(ItemVisual.fish_length_m(item_id)
			/ maxf(ItemVisual.longest_fish_m(), 0.001), PREVIEW_GAMMA),
			PREVIEW_MIN_FILL, PREVIEW_MAX_FILL)
		cam.size = maxf(maxf(span.y, span.x / aspect) / fill, 0.001)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	_finish_preview(item_id, ImageTexture.create_from_image(img) if img != null else null, vp)

## Previews are kept, but only a few: at 1180x660 RGBA each one is ~3 MB, and caching the
## whole 35-species roster would be 100 MB of VRAM to save a two-frame re-render. Oldest out.
const PREVIEW_CACHE_MAX: int = 4

func _finish_preview(item_id: String, tex: Texture2D, vp: SubViewport) -> void:
	_previews[item_id] = tex
	while _previews.size() > PREVIEW_CACHE_MAX:
		_previews.erase(_previews.keys()[0])
	_drop_stage(vp)
	preview_ready.emit(item_id)

## How much frame an ORTHOGONAL camera needs to hold `box`, as (width, height) in metres
## of the view plane: the box's eight corners projected onto the camera's own right and up
## axes. Shared with the fish preview below, which frames off the same measurement and then
## deliberately overruns it for the one species that is supposed to be too big for a frame.
static func screen_span(box: AABB, cam: Camera3D) -> Vector2:
	var right: Vector3 = cam.global_transform.basis.x
	var up: Vector3 = cam.global_transform.basis.y
	var u := Vector2(INF, -INF)   # (min, max) along the screen's horizontal
	var v := Vector2(INF, -INF)   # ...and its vertical
	for i in range(8):
		var c: Vector3 = box.get_endpoint(i)
		var du: float = c.dot(right)
		var dv: float = c.dot(up)
		u = Vector2(minf(u.x, du), maxf(u.y, du))
		v = Vector2(minf(v.x, dv), maxf(v.y, dv))
	return Vector2(u.y - u.x, v.y - v.x)

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
