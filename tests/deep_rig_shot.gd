extends Node
## Two owner-reported visual jobs, in one windowed pass (a SubViewport read-back needs a
## real frame, and --headless never draws):
##
##   1. THE WET DECK'S "blank yellow block". Reported more than once, never located. This
##      walks the DRAWN geometry inside the wet-deck volume (physics rays miss dressing,
##      which has no collider) and prints every candidate with its albedo, whether that
##      albedo carries a texture at all, whether anything holds a collider, and — the part
##      that actually names the culprit — the resource_path of the nearest ancestor script.
##      Then it photographs each candidate from a vantage DERIVED from the object's own
##      AABB, because a hand-typed vantage in a rig this dense photographs a wall.
##
##   2. THE DEEP RIG POLE. Mesh and triangle counts (measured off the built node, not
##      asserted), the world copy on the crane machinery deck, the copy in hand, and the
##      pack icon at three sizes — including the 74 px the slot actually draws, because
##      that is the size the owner judges an icon at.
##
## Run WINDOWED:  godot --path . res://tests/DeepRigShot.tscn -- <out_dir>

const WET := AABB(Vector3(4.0, 0.8, -30.0), Vector3(30.0, 6.4, 28.0))   ## the search volume
## An icon slot draws 74 px. Rendered at 160 and resampled here so "does it read in the
## pack" is a question about a picture rather than about a claim.
const SLOT_PX: int = 74
const ZOOM: int = 6

var main: Node3D
var _cam: Camera3D
var _out: String = "/tmp/deep_rig"
var _pause: CanvasLayer = null

# ------------------------------------------------------------------ pause defence
## PauseMenu auto-pauses on focus-out. Unpausing is not enough (the panel is its own
## CanvasLayer and stays drawn) and _process cannot unpause at all unless this node is
## PROCESS_MODE_ALWAYS — both cost earlier sessions a whole render pass.
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
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(14.0).timeout
	main._countdown = 0.0
	if main.hud != null:
		if main.hud.fade_rect != null:
			main.hud.fade_rect.color.a = 0.0
		main.hud.visible = false
	GameClock.force_phase(GameClock.Phase.DAY)
	_cam = Camera3D.new()
	_cam.fov = 62.0
	add_child(_cam)
	for i in range(10):
		await get_tree().process_frame

	_count_meshes()
	await _scan_wet_deck()
	await _pole_shots()
	print("[deeprig] done -> %s" % _out)
	get_tree().quit()

# =============================================================== 1. the yellow block

func _scan_wet_deck() -> void:
	var cands: Array = []
	var blanks: Array = []
	var walked: int = 0
	var stack: Array[Node] = [get_tree().current_scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.is_in_group("player"):
			continue
		var vi := n as VisualInstance3D
		if vi == null or not vi.is_inside_tree():
			continue
		var raw: AABB = vi.get_aabb()
		if raw.size == Vector3.ZERO:
			continue
		walked += 1
		var box: AABB = vi.global_transform * raw
		var c2: Vector3 = box.get_center()
		if not WET.has_point(c2):
			continue
		# Skip deck/hull-scale slabs: the thing reported is a BLOCK, and a 22 m plate would
		# swamp the list (this is the same cap F9 uses).
		if box.size.x > 12.0 or box.size.z > 12.0 or box.size.y > 12.0:
			continue
		var info: Dictionary = _describe(vi, box)
		if info["yellow"]:
			cands.append(info)
		elif info["blank_block"]:
			blanks.append(info)
	cands.sort_custom(func(a, b): return float(a["vol"]) > float(b["vol"]))
	blanks.sort_custom(func(a, b): return float(a["vol"]) > float(b["vol"]))
	print("\n[deeprig] ================ WET DECK SCAN ================")
	print("[deeprig] drawn nodes walked=%d   yellow candidates=%d   other blank blocks=%d"
		% [walked, cands.size(), blanks.size()])
	print("[deeprig] --- YELLOW (hue 35-75, sat>=0.40, val>=0.30) ---")
	for i in range(cands.size()):
		_report(i, cands[i])
	print("[deeprig] --- other untextured blocks, min dim >= 0.25 m (top 12) ---")
	for i in range(mini(blanks.size(), 12)):
		_report(i, blanks[i])
	# Photograph the yellow ones. Vantage is derived from the object's own box, never typed.
	for i in range(mini(cands.size(), 6)):
		await _look_at_box(cands[i]["box"], "wetdeck_cand%d" % i)
	# The two gangplank bollards, from the EXACT vantage the first scan photographed the blank
	# yellow block from — so the before and after frames are the same picture of the same spot
	# and the change is the only difference between them.
	for bx in [17.4, 21.6]:
		await _look_from(Vector3(bx, 2.28, -21.7), 2.60,
			Vector3(0.66, 0.42, 0.62).normalized(), "bollard_%d" % int(bx * 10))
	# ...and the whole dock apron, which is what the player actually walks across.
	await _look_from(Vector3(19.5, 2.35, -21.4), 5.4, Vector3(0.10, 0.30, 0.95).normalized(),
		"bollard_dock")

## Everything about one drawn node that the report needs, measured off the live node.
func _describe(vi: VisualInstance3D, box: AABB) -> Dictionary:
	var col := Color(0, 0, 0, 0)
	var textured: bool = false
	var mat_class: String = "(none)"
	for m in _materials(vi):
		var sm := m as BaseMaterial3D
		if sm == null:
			mat_class = m.get_class()
			continue
		mat_class = sm.get_class()
		col = sm.albedo_color
		textured = sm.albedo_texture != null
		break
	var h: float = col.h * 360.0
	var yellow: bool = col.a > 0.0 and h >= 35.0 and h <= 75.0 and col.s >= 0.40 and col.v >= 0.30
	var min_dim: float = minf(box.size.x, minf(box.size.y, box.size.z))
	var mesh_class: String = "CSG/" + vi.get_class()
	var mi := vi as MeshInstance3D
	if mi != null and mi.mesh != null:
		mesh_class = mi.mesh.get_class()
	return {
		"chain": _chain(vi), "script": _owner_script(vi), "mesh": mesh_class,
		"col": col, "hue": h, "textured": textured, "mat": mat_class,
		"box": box, "vol": box.size.x * box.size.y * box.size.z,
		"solid": _collides(vi), "yellow": yellow,
		"blank_block": (not textured) and min_dim >= 0.25 and mesh_class.contains("Box"),
	}

func _report(i: int, d: Dictionary) -> void:
	var b: AABB = d["box"]
	print("[deeprig]  #%d %s\n            script=%s mesh=%s mat=%s tex=%s\n            albedo=%s hue=%.0f sat=%.2f val=%.2f\n            centre=%s size=%s base_y=%.3f vol=%.4f collides=%s"
		% [i, d["chain"], d["script"], d["mesh"], d["mat"], str(d["textured"]),
			(d["col"] as Color).to_html(false), d["hue"], (d["col"] as Color).s,
			(d["col"] as Color).v, str(b.get_center().snappedf(0.01)),
			str(b.size.snappedf(0.01)), b.position.y, d["vol"], str(d["solid"])])

func _materials(vi: VisualInstance3D) -> Array:
	var out: Array = []
	if vi.get("material_override") is Material:
		out.append(vi.get("material_override"))
	var mi := vi as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i in range(mi.mesh.get_surface_count()):
			var m: Material = mi.get_active_material(i)
			if m != null:
				out.append(m)
		if mi.mesh.get("material") is Material:
			out.append(mi.mesh.get("material"))
	elif vi.get("material") is Material:
		out.append(vi.get("material"))    # CSGPrimitive3D
	return out

## Is anything about this node solid? A placeholder that turns out to be a collider or a
## trigger volume must NOT be deleted, so the report says so up front.
func _collides(vi: VisualInstance3D) -> String:
	if vi.get("use_collision") == true:
		return "CSG use_collision=true"
	var p: Node = vi
	for i in range(4):
		if p == null:
			break
		if p is CollisionObject3D:
			var kids: int = 0
			for c in p.get_children():
				if c is CollisionShape3D:
					kids += 1
			return "%s(%s) with %d shapes" % [p.get_class(), p.name, kids]
		p = p.get_parent()
	for c in vi.get_children():
		if c is CollisionShape3D or c is CollisionObject3D:
			return "child %s" % c.get_class()
	return "no"

func _chain(n: Node) -> String:
	var s: String = String(n.name)
	var p: Node = n.get_parent()
	for i in range(4):
		if p == null or p == get_tree().current_scene:
			break
		s = "%s/%s" % [p.name, s]
		p = p.get_parent()
	return s

func _owner_script(n: Node) -> String:
	var p: Node = n
	while p != null:
		var s: Script = p.get_script()
		if s != null:
			return String(s.resource_path).get_file()
		p = p.get_parent()
	return "(no script ancestor)"

## Frame a box from off its own diagonal, backed off far enough that the whole thing fits.
func _look_at_box(box: AABB, tag: String) -> void:
	var back: float = maxf(box.size.length() * 1.9, 2.6)
	await _look_from(box.get_center(), back, Vector3(0.66, 0.42, 0.62).normalized(), tag)

## Same, but the vantage is SCORED rather than hoped for. The deep rig sits on the crane
## machinery deck inside a lattice of king post, rails and rams, and the first pass
## photographed a caisson from 2.6 m away: the aim point was right and a girder was in the
## way. So this rays every candidate azimuth back to the subject and photographs EVERY one
## with a clear line — which face of a tool reads best is a judgement made by looking, and the
## crane deck only affords a couple of clear sight lines anyway. Blocked azimuths are named
## with the distance at which they were blocked, instead of silently saving a wall.
func _look_at_clear(centre: Vector3, back: float, tag: String) -> void:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var shot: int = 0
	for i in range(8):
		var a: float = i * TAU / 8.0
		var dir: Vector3 = Vector3(cos(a), 0.30, sin(a)).normalized()
		var eye: Vector3 = centre + dir * back
		var q := PhysicsRayQueryParameters3D.create(eye, centre)
		q.collide_with_areas = false
		var hit: Dictionary = space.intersect_ray(q)
		# A hit within 0.3 m of the subject IS the subject (or its own collider).
		if not hit.is_empty() and (hit["position"] as Vector3).distance_to(centre) > 0.3:
			print("[deeprig] %s azimuth %.0f° blocked %.2f m out" % [tag, rad_to_deg(a),
				(hit["position"] as Vector3).distance_to(eye)])
			continue
		shot += 1
		await _look_from(centre, back, dir, "%s_a%d" % [tag, int(round(rad_to_deg(a)))])
	if shot == 0:
		print("[deeprig] %s: NO CLEAR VANTAGE at all — shooting the default anyway" % tag)
		await _look_from(centre, back, Vector3(0.66, 0.42, 0.62).normalized(), tag)

func _look_from(centre: Vector3, back: float, dir: Vector3, tag: String) -> void:
	_cam.current = true
	_cam.global_position = centre + dir * back
	_cam.look_at(centre, Vector3.UP)
	for i in range(4):
		await RenderingServer.frame_post_draw
	_save(tag)
	print("[deeprig] shot %s: subject %s, lens %s, %.2f m out"
		% [tag, str(centre.snappedf(0.01)), str(_cam.global_position.snappedf(0.01)), back])

# ============================================================== 2. the deep rig pole

## Measured, not asserted: what the two fishing tools actually cost as geometry.
func _count_meshes() -> void:
	print("\n[deeprig] ================ ITEM GEOMETRY ================")
	for id in ["fishing_rod", "deep_rig_pole"]:
		var n: Node3D = ItemVisual.build(id)
		var meshes: int = 0
		var tris: int = 0
		var box := AABB()
		var got: bool = false
		var stack: Array[Node] = [n]
		while not stack.is_empty():
			var x: Node = stack.pop_back()
			for c in x.get_children():
				stack.append(c)
			var mi := x as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			meshes += 1
			tris += mi.mesh.get_faces().size() / 3
			var b: AABB = _rel(mi, n) * mi.mesh.get_aabb()
			box = b if not got else box.merge(b)
			got = true
		var marker: Node = n.find_child("hand_tip", true, false)
		print("[deeprig] %-14s meshes=%3d tris=%6d  extent=%s  hand_tip=%s"
			% [id, meshes, tris, str(box.size.snappedf(0.001)),
				str((marker as Node3D).position) if marker is Node3D else "MISSING"])
		if marker is Node3D:
			print("[deeprig]                marker in model space = %s (root-relative %s)"
				% [str((marker as Node3D).position.snappedf(0.001)),
					str((_rel(marker as Node3D, n) * Vector3.ZERO).snappedf(0.001))])
		n.queue_free()

func _rel(node: Node3D, base: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node3D = node
	while cur != null and cur != base:
		t = cur.transform * t
		cur = cur.get_parent() as Node3D
	return t

func _pole_shots() -> void:
	print("\n[deeprig] ================ DEEP RIG POLE ================")
	var p: Node3D = main.player
	# --- the WORLD copy, on the crane machinery deck where rig_builder leaves it.
	var found: Node3D = null
	var stack: Array[Node] = [get_tree().current_scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if str(n.get("item_id")) == "deep_rig_pole":
			found = n as Node3D
			break
	if found != null:
		print("[deeprig] world pickup at %s" % str(found.global_position.snappedf(0.01)))
		# The pole is 1.15 m tall standing on its own foot, so aim at its middle, not its base.
		var mid: Vector3 = found.global_position + Vector3(0, 0.58, 0)
		await _look_at_clear(mid, 1.45, "pole_world")
	else:
		print("[deeprig] NO world deep_rig_pole found")
	# --- HELD. Park the player on the crane deck edge so the sea is behind the pole.
	_cam.current = false
	PlayerState.add_item("deep_rig_pole")
	for i in range(PlayerState.hotbar.size()):
		if str(PlayerState.hotbar[i]) == "deep_rig_pole":
			PlayerState.selected_hotbar = i
	p.call("_update_held_item")
	await get_tree().process_frame
	# Vantages that item_shot.gd already proved put OPEN WATER behind the tool — a held shot
	# against the SPHL's own hull photographs a rusty wall and nothing else (that is exactly
	# what the first pass at yaw 190 came back with).
	for spot in [[Vector3(27.0, 2.3, -20.0), 0.0, -8.0], [Vector3(27.4, 2.2, -20.0), -90.0, -4.0],
			[Vector3(14.0, 3.2, -23.4), 84.0, -2.0]]:
		await _park(spot[0], float(spot[1]), float(spot[2]))
		_save("pole_held_%s" % str(int(spot[1])))
	_report_tip(p)
	# THE ROD, from the same vantage, in the same light. Without this there is no way to judge
	# whether the deep rig's palette is "salt-hazed gunmetal" or "pale plastic": the icon stage
	# has its own lights and the game's daylight lifts every albedo, so the only honest test of
	# a value is the tool this one is supposed to be family with, photographed side by side.
	PlayerState.add_item("fishing_rod")
	for i in range(PlayerState.hotbar.size()):
		if str(PlayerState.hotbar[i]) == "fishing_rod":
			PlayerState.selected_hotbar = i
	p.call("_update_held_item")
	await get_tree().process_frame
	await _park(Vector3(27.4, 2.2, -20.0), -90.0, -4.0)
	_save("rod_held_same_light")
	# --- the PACK ICON, at the size the slot draws it.
	var ico: Node = ItemIcons.new()
	add_child(ico)
	ico.call("get_icon", "deep_rig_pole")
	ico.call("get_icon", "fishing_rod")
	for i in range(240):
		await get_tree().process_frame
		if ico.get("_cache").get("deep_rig_pole", null) != null \
				and ico.get("_cache").get("fishing_rod", null) != null:
			break
	for id in ["deep_rig_pole", "fishing_rod"]:
		var tex: Texture2D = ico.get("_cache").get(id, null)
		if tex == null:
			print("[deeprig] icon %s: NOT RENDERED" % id)
			continue
		var img: Image = tex.get_image()
		img.save_png("%s/icon_%s_full.png" % [_out, id])
		var small: Image = img.duplicate()
		small.resize(SLOT_PX, SLOT_PX, Image.INTERPOLATE_LANCZOS)
		small.resize(SLOT_PX * ZOOM, SLOT_PX * ZOOM, Image.INTERPOLATE_NEAREST)
		small.save_png("%s/icon_%s_slot.png" % [_out, id])
		print("[deeprig] icon %s: %dpx saved, plus the %d px slot view at %dx"
			% [id, img.get_width(), SLOT_PX, ZOOM])
	# --- and the real pack panel, which is the thing the player looks at.
	if main.hud != null:
		main.hud.visible = true
		for id in ["fishing_rod", "prybar", "wrench", "rope", "flare", "canned_food"]:
			PlayerState.add_item(id)
		main.hud.toggle_panel("inventory")
		await get_tree().create_timer(4.0).timeout
		_save("pole_pack")
		main.hud.toggle_panel("inventory")
		main.hud.visible = false

func _report_tip(p: Node) -> void:
	var hand: Node3D = p.get("_hand_item")
	if hand == null or hand.get_child_count() == 0:
		print("[deeprig] hand is EMPTY")
		return
	var container: Node3D = hand.get_child(0)
	var marker: Node = container.find_child("hand_tip", true, false)
	var tip: Vector3 = p.call("hand_tip_world")
	var fb: Vector3 = container.global_transform * (Vector3(0, 0, -1) * float(p.get("_hand_reach")))
	print("[deeprig] hand_tip=%s tip=%s fallback=%s delta=%.3f  out_from_centre=%.3f"
		% ["found" if marker is Node3D else "MISSING", str(tip.snappedf(0.001)),
			str(fb.snappedf(0.001)), tip.distance_to(fb),
			tip.distance_to(container.global_position)])

# ------------------------------------------------------------------------- plumbing

const EYE_UP: float = 1.6    ## the camera's eye sits this far above the player node origin

func _park(pos: Vector3, yaw_deg: float, pitch_deg: float) -> void:
	var p: Node3D = main.player
	p.set("_fly", true)
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw_deg)
	p.get_node("Head").rotation.x = deg_to_rad(pitch_deg)
	p.velocity = Vector3.ZERO
	p.input_locked = true
	await get_tree().create_timer(1.1).timeout

func _save(tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png("%s/%s.png" % [_out, tag])
	if err != OK:
		print("[deeprig] SAVE FAILED %s err=%d" % [tag, err])
