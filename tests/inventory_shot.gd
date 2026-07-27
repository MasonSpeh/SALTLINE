extends Node
## Visual check on the square icon slots. Run WINDOWED with --always-on-top — an occluded
## window presents nothing and saves a black or stale frame.
##
## Fills the pack with a deliberately mixed load and photographs the pack panel and the
## hotbar, so the question "does every item actually read as itself?" has an answer you can
## look at rather than infer. Prints which items got an icon and which fell back to a name.
##
## It ALSO writes /tmp/inv_models.png: the same items, one isolated render each, straight
## off ItemVisual.build(). See _model_sheet() for why that second pass exists.

## The pack holds 4 hotbar slots + 12 pack slots, 16 with a tool belt, so a load is 20 items
## at most — hence two batches. Batch A is the galley stores authored on 2026-07-26 with
## three older foods mixed in as controls; swap to batch B for the kits, the four vessels
## and the medical shelf. The tool belt goes FIRST so the extra slots exist before the pack
## fills up.
const LOAD := [
	"tool_belt",
	"dried_fish", "croissant", "carrot_cake", "bananas", "apple", "avocado",
	"burger_buns", "lemon", "chocolate_cake", "cheese_wedge", "ration_tin",
	"long_life_ration", "wine_bottle", "water_jug", "galley_stew", "kelp_brew",
	"canned_food", "cooked_fish", "water_ration",
]
## Batch B — uncomment to shoot the other half.
#const LOAD := [
#	"tool_belt",
#	"bottle_empty", "bottle_water", "thermos_empty", "thermos_water",
#	"storage_bin_kit", "door_kit", "floor_panel_kit", "window_panel_kit",
#	"bandage", "medkit", "bloom_tonic", "glow_mucus", "limpet_shell",
#	"walkway_kit", "locker_kit", "wall_panel_kit", "rain_catcher_kit",
#	"storm_lantern", "rope",
#]

const SHEET_PX: int = 128     ## contact-sheet tile; bigger than an icon so shapes are legible
const SHEET_COLS: int = 5
## Straight off item_icons.gd, so the contact sheet frames items exactly as the pack does.
const VIEW_DIR := Vector3(0.62, 0.55, 0.78)
const FRAME_FILL: float = 0.78

var main: Node3D

func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(24.0).timeout
	main._countdown = 0.0
	main.hud.fade_rect.color.a = 0.0
	# HOTBAR_SIZE is the live source of truth (grew 4 -> 6 on 2026-07-27, see
	# player_state.gd) — a hardcoded 4-slot array here silently desynced add_item's
	# bounds checks from the real hotbar and made every add_item in LOAD fail quietly,
	# which is why this harness started photographing an empty pack.
	PlayerState.hotbar = PlayerState._new_hotbar()
	PlayerState.hotbar_counts = PlayerState._new_hotbar_counts()
	PlayerState.inventory.clear()
	PlayerState.inventory_counts.clear()
	for id in LOAD:
		PlayerState.add_item(id)
	# A stack, so the ×N glyph is exercised against a picture.
	for i in range(5):
		PlayerState.add_item("scrap_metal")
	PlayerState.inventory_changed.emit()
	main.hud.toggle_panel("inventory")
	# Icons bake one per frame; this load is ~20 distinct items, so a couple of seconds is
	# generous. If a slot still shows a word after this, that item genuinely has no art.
	await get_tree().create_timer(6.0).timeout
	# Verification-only: simulate hovering "galley_stew" (unified idx 15 — LOAD fills
	# hotbar then pack in order, so this lands on the richest-stat item: hunger, thirst,
	# warmth, and a returns-a-bottle loop) so the hover-info redesign is visible in the
	# same screenshot without a real mouse move.
	main.hud._inv_slot_hovered(15)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	print("[inv] saved err=", img.save_png("/tmp/inv_icons.png"))
	# Report coverage explicitly — a screenshot shows the slots that ARE filled, but the
	# list of what fell back is the actionable half ("most holdable items have good
	# visual graphics" is the owner's bar, so name the ones that miss it).
	var icons: Node = main.hud._icons
	var missing: Array[String] = []
	for id in LOAD:
		if icons._cache.get(id, null) == null:
			missing.append(id)
	print("[inv] items with no icon (%d of %d): %s" % [missing.size(), LOAD.size(), ", ".join(missing)])
	await _model_sheet()
	get_tree().quit()

## The same items, rendered ONE PER SUBVIEWPORT, into /tmp/inv_models.png.
##
## 2026-07-26: baking the icon set through ItemIcons came out double-exposed — every icon
## from the second one on carried a ghost of another item's geometry, and the ghost is in
## the BAKED TEXTURE, not the slot (dumped the ImageTextures on their own to be sure). The
## stage is empty between renders and forcing CLEAR_MODE_ALWAYS changes nothing, so the
## contamination is in that one shared render target being reused for every item. That is
## item_icons.gd's to fix; this pass exists so that authoring an item's LOOK can still be
## checked in the meantime. A viewport per item cannot smear one item into the next.
func _model_sheet() -> void:
	var rows: int = int(ceil(float(LOAD.size()) / float(SHEET_COLS)))
	var sheet := Image.create(SHEET_COLS * SHEET_PX, rows * SHEET_PX, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.09, 0.09, 0.1))
	for i in range(LOAD.size()):
		var shot: Image = await _shoot(String(LOAD[i]))
		if shot == null:
			continue
		shot.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, shot.get_size()),
			Vector2i((i % SHEET_COLS) * SHEET_PX, (i / SHEET_COLS) * SHEET_PX))
	print("[inv] model sheet err=", sheet.save_png("/tmp/inv_models.png"))

func _shoot(item_id: String) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(SHEET_PX, SHEET_PX)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -140, 0)
	key.light_energy = 1.5
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, 45, 0)
	fill.light_energy = 0.55
	fill.light_color = Color(0.82, 0.88, 1.0)
	vp.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.09, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.65, 0.7)
	env.ambient_light_energy = 1.0
	cam.environment = env
	vp.add_child(cam)
	var model: Node3D = ItemVisual.build(item_id)
	vp.add_child(model)
	await get_tree().process_frame
	var box: AABB = _bounds(model)
	if box.size.length() <= 0.0001:
		vp.queue_free()
		return null
	var centre: Vector3 = box.position + box.size * 0.5
	var extent: float = maxf(maxf(box.size.x, box.size.y), box.size.z)
	cam.size = maxf(extent, 0.001) / FRAME_FILL
	cam.near = 0.01
	cam.far = extent * 8.0 + 10.0
	cam.global_position = centre + VIEW_DIR.normalized() * (extent * 3.0 + 1.0)
	cam.look_at(centre, Vector3.UP)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var out: Image = vp.get_texture().get_image()
	vp.queue_free()
	return out

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
		var local: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		var b: AABB = local * mi.mesh.get_aabb()
		out = b if not got else out.merge(b)
		got = true
	return out if got else AABB()
