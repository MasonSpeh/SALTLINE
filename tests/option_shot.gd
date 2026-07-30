extends Node
## Photograph every fishing-tool design option (tests/tool_options.gd) the same way, so the
## owner can pick one by looking rather than by reading a description.
##
## Three views per option, because those are the three places the owner judges a tool:
##   * STUDIO — the whole thing on a neutral stage, 3/4 view, same lights as the pack icon
##     renderer. This is the "what is it" view.
##   * HELD — in the hand, in the live world, over open water, from a vantage item_shot.gd
##     already proved has sky and sea behind it. This is the "does it look right in the game"
##     view, and it is where the owner said the last one looked weird.
##   * SLOT — the 74 px an inventory slot actually draws, resampled up so it can be inspected.
##
## Mesh and triangle counts are printed per option, measured off the built node.
##
## Run WINDOWED:  godot --path . res://tests/OptionShot.tscn -- <out_dir>

const OPT := preload("res://tests/tool_options.gd")

const STUDIO_PX := Vector2i(560, 800)
const SLOT_PX: int = 74
const ZOOM: int = 6
## Straight off scripts/ui/item_icons.gd so the studio frame matches the pack's own framing.
const VIEW_DIR := Vector3(0.62, 0.55, 0.78)
const FRAME_FILL: float = 0.90

var main: Node3D
var _out: String = "/tmp/tool_options"
var _pause: CanvasLayer = null

func _process(_d: float) -> void:
	get_tree().paused = false
	if _pause == null:
		_pause = _find_pause(get_tree().root)
	if _pause != null:
		var panel: Variant = _pause.get("panel")
		if panel is CanvasItem:
			(panel as CanvasItem).visible = false

func _find_pause(n: Node) -> CanvasLayer:
	var s: Script = n.get_script()
	if s != null and String(s.resource_path).ends_with("pause_menu.gd"):
		return n as CanvasLayer
	for c in n.get_children():
		var got: CanvasLayer = _find_pause(c)
		if got != null:
			return got
	return null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	# Each family leads with the tool that SHIPS NOW, so every option is compared against the
	# thing being replaced rather than against the other options only.
	var ids: Array = ["deep_rig_pole"]
	ids.append_array(OPT.DEEP)
	ids.append("fishing_rod")
	ids.append_array(OPT.RODS)
	# ---- studio + slot first: these need no world, so a build error shows up in seconds.
	print("\n[opt] ================ GEOMETRY ================")
	for id in ids:
		await _studio(String(id))
	# ---- and now the live world, for the held views.
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(14.0).timeout
	main._countdown = 0.0
	if main.hud != null:
		if main.hud.fade_rect != null:
			main.hud.fade_rect.color.a = 0.0
		main.hud.visible = false
	GameClock.force_phase(GameClock.Phase.DAY)
	var p: Node3D = main.player
	p.set("_fly", true)
	# item_shot.gd's proven open-water vantage: sky and sea behind the tool, nothing else.
	p.global_position = Vector3(27.4, 2.2, -20.0)
	p.rotation.y = deg_to_rad(-90)
	p.get_node("Head").rotation.x = deg_to_rad(-4)
	p.velocity = Vector3.ZERO
	p.set("input_locked", true)
	await get_tree().create_timer(1.5).timeout
	print("\n[opt] ================ HELD, IN WORLD ================")
	for id in ids:
		await _held(p, String(id))
	print("\n[opt] done -> %s" % _out)
	get_tree().quit()

# ------------------------------------------------------------------ studio + slot

func _studio(id: String) -> void:
	var model: Node3D = OPT.build(id)
	var meshes: int = 0
	var tris: int = 0
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		meshes += 1
		tris += mi.mesh.get_faces().size() / 3
	var marker: Node = model.find_child("hand_tip", true, false)
	# ONE FIXED FRAME PER FAMILY, not per option. Auto-framing each tool to its own extent is
	# what the pack icon does, and it is exactly wrong here: it normalises away the only thing
	# being judged. Four rods framed to fit each came back as four identical pictures. A common
	# frame across the family means a 19 mm blank IS drawn thinner than a 36 mm one, and a
	# 1.26 m pole IS drawn shorter than a 1.65 m rod.
	var family: float = 1.90 if id.begins_with("deep") else 2.30
	var extent := Vector3.ZERO
	for job in [["studio", STUDIO_PX, family, 0.5], ["detail", STUDIO_PX, 0.42, 0.34],
			["slot", Vector2i(SLOT_PX * ZOOM, SLOT_PX * ZOOM), 0.0, 0.5]]:
		var px: Vector2i = job[1]
		var stage: Array = _stage(px)
		var vp: SubViewport = stage[0]
		var cam: Camera3D = stage[1]
		var copy: Node3D = OPT.build(id)
		vp.add_child(copy)
		await get_tree().process_frame
		var box: AABB = _bounds(copy)
		extent = box.size
		# `detail` looks at the reel/drum end — a third of the way up — at a hard 0.42 m frame,
		# which is the magnification at which a section difference of a few millimetres reads.
		var centre: Vector3 = box.position + Vector3(box.size.x * 0.5,
			box.size.y * float(job[3]), box.size.z * 0.5)
		var reach: float = maxf(box.size.length(), 0.001)
		cam.near = 0.01
		cam.far = reach * 8.0 + 10.0
		cam.global_position = centre + VIEW_DIR.normalized() * (reach * 3.0 + 2.0)
		cam.look_at(centre, Vector3.UP)
		if float(job[2]) > 0.0:
			cam.size = float(job[2])
		else:
			var span: Vector2 = _span(box, cam)
			cam.size = maxf(maxf(span.x * float(px.y) / float(px.x), span.y), 0.001) / FRAME_FILL
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img: Image = vp.get_texture().get_image()
		if String(job[0]) == "slot":
			# Down to the size a slot really draws, then back up with NEAREST so what is
			# inspected is the information a 74 px icon actually carries.
			img.resize(SLOT_PX, SLOT_PX, Image.INTERPOLATE_LANCZOS)
			img.resize(SLOT_PX * ZOOM, SLOT_PX * ZOOM, Image.INTERPOLATE_NEAREST)
		img.save_png("%s/%s_%s.png" % [_out, job[0], id])
		remove_child(vp)
		vp.queue_free()
	print("[opt] %-14s meshes=%3d tris=%6d extent=%s hand_tip=%s   %s"
		% [id, meshes, tris, str(extent.snappedf(0.001)),
			str((marker as Node3D).position.snappedf(0.001)) if marker is Node3D else "MISSING",
			OPT.blurb(id)])
	model.queue_free()

## Same one-shot photographic stage scripts/ui/item_icons.gd builds for a pack icon: its own
## World3D so the rig is not behind every bolt, an orthogonal camera, a key/fill pair over a
## lifted ambient floor.
func _stage(px: Vector2i) -> Array:
	var vp := SubViewport.new()
	vp.size = px
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
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

static func _span(box: AABB, cam: Camera3D) -> Vector2:
	var right: Vector3 = cam.global_transform.basis.x
	var up: Vector3 = cam.global_transform.basis.y
	var u := Vector2(INF, -INF)
	var v := Vector2(INF, -INF)
	for i in range(8):
		var c: Vector3 = box.get_endpoint(i)
		u = Vector2(minf(u.x, c.dot(right)), maxf(u.y, c.dot(right)))
		v = Vector2(minf(v.x, c.dot(up)), maxf(v.y, c.dot(up)))
	return Vector2(u.y - u.x, v.y - v.x)

func _bounds(root: Node3D) -> AABB:
	var out := AABB()
	var got: bool = false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var local: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		var b: AABB = local * mi.mesh.get_aabb()
		out = b if not got else out.merge(b)
		got = true
	return out if got else AABB()

# ------------------------------------------------------------------ held in world

## Put an option in the player's hand without touching ItemVisual. _update_held_item() only
## ever builds from the item table, so the container is assembled here and handed to the
## controller's own _normalize_hand_visual — which is what applies the 0.9 m rescale, the
## rod tilt and the lift, i.e. exactly the treatment a real installed tool would get.
func _held(p: Node3D, id: String) -> void:
	var hand: Node3D = p.get("_hand_item")
	for c in hand.get_children():
		hand.remove_child(c)
		c.queue_free()
	# The ROD_ITEMS branch in _normalize_hand_visual keys off _held_item_id, so borrow the id
	# of whichever real tool this option is a candidate for.
	p.set("_held_item_id", "deep_rig_pole" if id.begins_with("deep") else "fishing_rod")
	var visual: Node3D = OPT.build(id)
	var container := Node3D.new()
	container.add_child(visual)
	hand.add_child(container)
	p.call("_normalize_hand_visual", container, visual)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/held_%s.png" % [_out, id])
	var marker: Node = container.find_child("hand_tip", true, false)
	var tip: Vector3 = p.call("hand_tip_world")
	var axis: Variant = p.get("_hand_reach_axis")
	var fb: Vector3 = container.global_transform * (
		(axis if axis is Vector3 else Vector3(0, 0, -1)) * float(p.get("_hand_reach")))
	print("[opt] %-14s hand_tip=%-7s tip=%s  fallback delta=%.3f  out from centre=%.3f"
		% [id, "found" if marker is Node3D else "MISSING", str(tip.snappedf(0.001)),
			tip.distance_to(fb), tip.distance_to(container.global_position)])
