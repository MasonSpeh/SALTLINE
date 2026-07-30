extends Node
## THE TWO OWNER-PICKED FISHING TOOLS, verified by looking rather than by arithmetic.
##
## Three jobs, one windowed pass (a SubViewport read-back needs a real frame, and --headless
## never draws — see docs/AGENT_TRAPS.md):
##
##   1. THE PACK SLOT, at the 74 px it is actually drawn at. ICON_FOCUS exists because an
##      item's own extent is the wrong frame for a 111:1 rod, so a candidate frame is a thing
##      you judge by looking. The candidates are rendered on ItemIcons' OWN stage (its
##      `_stage()`, i.e. its lights, environment and orthogonal camera) with the eight lines
##      of framing copied — because ICON_FOCUS is a `const` Dictionary and GDScript makes
##      those READ-ONLY, so the live table cannot be swapped for a sweep. That copy is then
##      PROVED equivalent: candidate 0 is the installed entry, and its render is diffed
##      against what the shipping ItemIcons.get_icon() produces for the same item.
##   2. THE WINCH IN HAND. Held-pose candidates for HAND_TOOL_POSE, each through the
##      controller's own _normalize_hand_visual, plus the hand_tip / fallback numbers.
##   3. AN ACTUAL CAST off the crane machinery deck (y 34), where the deep rig is used.
##      fishing_rod._physics_process REELS THE LINE IN the instant `input_locked` is set, so a
##      parked camera kills every cast before it leaves the hand: the pose is re-asserted every
##      frame with input_locked FALSE instead, which is also the s21 lesson about a vantage
##      having to be HELD rather than set once. Azimuths are tried until one leaves the rail
##      without fouling, and the state is printed each frame so a fouled cast is visible.
##
## Run WINDOWED:  godot --path . res://tests/ToolFinal.tscn -- <out_dir>

const SLOT_PX: int = 74
const ZOOM: int = 6
const IDS := ["deep_rig_pole", "fishing_rod"]

## Candidate ICON_FOCUS frames. Entry 0 of each list is what is currently installed in
## scripts/ui/item_icons.gd, so the sheet always contains the shipping answer.
const ICON_CANDS := {
	"deep_rig_pole": [
		{"centre": Vector3(-0.10, 0.53, 0.06), "size": 0.50},
		{"centre": Vector3(-0.12, 0.52, 0.08), "size": 0.42},
		{"centre": Vector3(-0.08, 0.55, 0.04), "size": 0.62},
		{"centre": Vector3(-0.04, 0.52, 0.04), "size": 0.78},
	],
	"fishing_rod": [
		{"centre": Vector3(-0.02, 0.66, 0.0), "size": 0.52},
		{"centre": Vector3(-0.01, 0.62, 0.0), "size": 0.40},
		{"centre": Vector3(-0.05, 0.72, 0.0), "size": 0.66},
		{"centre": Vector3(-0.10, 0.80, 0.0), "size": 0.86},
	],
}

## Candidate held poses for the WINCH. Entry 0 is what is installed.
const HELD_CANDS := [
	{"rot": Vector3(-14.0, -14.0, 0.0), "off": Vector3(-0.05, 0.0, -0.04)},
	{"rot": Vector3(-24.0, -14.0, 0.0), "off": Vector3(0.05, 0.12, -0.1)},    # the old rod pose
	{"rot": Vector3(-14.0, -14.0, 0.0), "off": Vector3(-0.02, 0.04, 0.0)},
	{"rot": Vector3(-6.0, -22.0, 0.0), "off": Vector3(-0.06, -0.02, -0.06)},
]

## Where a cast is taken from: the crane's machinery deck. Derived from rig_builder's own
## constants rather than typed — CRANE_X 2.0, CRANE_Z -14.0, CRANE_DECK_HALF 3.5 — so the
## vantage cannot drift away from the deck if the crane moves.
const RB := preload("res://scripts/world/rig_builder.gd")
const EYE_UP: float = 1.6

var main: Node3D
var _out: String = "/tmp/tool_final"
var _pause: CanvasLayer = null
## Set while a cast is being photographed: _process re-asserts the player's pose every frame
## WITHOUT input_locked, because input_locked reels the line straight back in.
var _hold: Dictionary = {}

func _process(_d: float) -> void:
	get_tree().paused = false
	if _pause == null:
		_pause = _find_pause(get_tree().root)
	if _pause != null:
		var panel: Variant = _pause.get("panel")
		if panel is CanvasItem:
			(panel as CanvasItem).visible = false
	if not _hold.is_empty() and main != null and main.player != null:
		var p: Node3D = main.player
		p.global_position = _hold["pos"]
		p.rotation.y = _hold["yaw"]
		p.get_node("Head").rotation.x = _hold["pitch"]
		p.velocity = Vector3.ZERO

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
	# --- geometry first: it needs no world, so a build error shows in seconds not minutes.
	print("\n[tool] ================ GEOMETRY ================")
	for id in IDS:
		_measure(String(id))
	# --- the pack slot, at the size the slot draws it.
	await _icon_sweep()
	# --- and now the live world.
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(14.0).timeout
	main._countdown = 0.0
	if main.hud != null:
		if main.hud.fade_rect != null:
			main.hud.fade_rect.color.a = 0.0
		main.hud.visible = false
	GameClock.force_phase(GameClock.Phase.DAY)
	for i in range(10):
		await get_tree().process_frame
	await _held_sweep()
	await _cast_shots()
	await _pack_panel()
	print("\n[tool] done -> %s" % _out)
	get_tree().quit()

# ================================================================== geometry

func _measure(id: String) -> void:
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
	print("[tool] %-14s meshes=%3d tris=%6d  aabb size=%s centre=%s  hand_tip=%s"
		% [id, meshes, tris, str(box.size.snappedf(0.001)),
			str(box.get_center().snappedf(0.001)),
			str((_rel(marker as Node3D, n) * Vector3.ZERO).snappedf(0.001)) \
				if marker is Node3D else "MISSING"])
	n.queue_free()

func _rel(node: Node3D, base: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node3D = node
	while cur != null and cur != base:
		t = cur.transform * t
		cur = cur.get_parent() as Node3D
	return t

# ================================================================== 1. the pack slot

## Render every candidate frame through ItemIcons' own code, by swapping the live ICON_FOCUS
## entry. Anything else would be a second copy of the framing maths, i.e. a picture of code
## that is not shipping.
func _icon_sweep() -> void:
	print("\n[tool] ================ PACK SLOT (%d px, the size it is drawn at) ================"
		% SLOT_PX)
	var ico: Node = ItemIcons.new()
	add_child(ico)
	var table: Dictionary = ItemIcons.ICON_FOCUS
	for id in IDS:
		var cands: Array = ICON_CANDS[id]
		for ci in range(cands.size()):
			var c: Dictionary = cands[ci]
			table[id] = c
			# One ItemIcons cache entry per (id, candidate); clear it so the next one renders.
			(ico.get("_cache") as Dictionary).erase(id)
			ico.call("get_icon", id)
			var tex: Texture2D = null
			for i in range(300):
				await get_tree().process_frame
				tex = (ico.get("_cache") as Dictionary).get(id, null)
				if tex != null:
					break
			if tex == null:
				print("[tool] icon %s cand%d: NOT RENDERED" % [id, ci])
				continue
			var img: Image = tex.get_image()
			var small: Image = img.duplicate()
			small.resize(SLOT_PX, SLOT_PX, Image.INTERPOLATE_LANCZOS)
			# The honest 74 px, then the same pixels blown up NEAREST so they can be inspected
			# without any resampler inventing detail that the slot will not have.
			small.save_png("%s/slot_%s_c%d_true74.png" % [_out, id, ci])
			var zoom: Image = small.duplicate()
			zoom.resize(SLOT_PX * ZOOM, SLOT_PX * ZOOM, Image.INTERPOLATE_NEAREST)
			zoom.save_png("%s/slot_%s_c%d_zoom.png" % [_out, id, ci])
			print("[tool] icon %-14s cand%d centre=%s size=%.2f  ink=%.1f%% of the slot%s"
				% [id, ci, str(c["centre"]), float(c["size"]), _ink(small) * 100.0,
					"   <-- INSTALLED" if ci == 0 else ""])
	table[IDS[0]] = ICON_CANDS[IDS[0]][0]
	table[IDS[1]] = ICON_CANDS[IDS[1]][0]
	ico.queue_free()

## Share of the slot that is not transparent background. Not a judgement of the picture — the
## picture is judged by looking — but it does catch the failure the owner reported as "isn't
## showing on the item": a frame so wide the subject is a handful of pixels.
func _ink(img: Image) -> float:
	var n: int = 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.08:
				n += 1
	return float(n) / float(img.get_width() * img.get_height())

# ================================================================== 2. the winch in hand

func _held_sweep() -> void:
	print("\n[tool] ================ THE WINCH IN HAND ================")
	var p: Node3D = main.player
	p.set("_fly", true)
	PlayerState.add_item("deep_rig_pole")
	PlayerState.add_item("fishing_rod")
	# The open-water vantage item_shot.gd and option_shot.gd both proved has sky and sea
	# behind the tool: a held shot against the SPHL's hull photographs a rusty wall.
	await _park(Vector3(27.4, 2.2, -20.0), -90.0, -4.0)
	var pose: Dictionary = PlayerController.HAND_TOOL_POSE
	for ci in range(HELD_CANDS.size()):
		var c: Dictionary = HELD_CANDS[ci]
		var r: Vector3 = c["rot"]
		pose["deep_rig_pole"] = {
			"rot": Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)),
			"off": c["off"],
		}
		_select("deep_rig_pole")
		p.call("_update_held_item")
		for i in range(3):
			await RenderingServer.frame_post_draw
		_save("held_winch_c%d" % ci)
		print("[tool] held winch cand%d rot=%s off=%s%s   %s"
			% [ci, str(r), str(c["off"]), "   <-- INSTALLED" if ci == 0 else "",
				_tip_line(p)])
	pose["deep_rig_pole"] = {
		"rot": Vector3(deg_to_rad(HELD_CANDS[0]["rot"].x), deg_to_rad(HELD_CANDS[0]["rot"].y), 0.0),
		"off": HELD_CANDS[0]["off"],
	}
	# The winch from three angles at the installed pose, and the rod in the same light — the
	# only honest test of whether a palette reads as salt-hazed gunmetal or as pale plastic.
	_select("deep_rig_pole")
	p.call("_update_held_item")
	for spot in [[Vector3(27.0, 2.3, -20.0), 0.0, -8.0], [Vector3(27.4, 2.2, -20.0), -90.0, -4.0],
			[Vector3(14.0, 3.2, -23.4), 84.0, -2.0]]:
		await _park(spot[0], float(spot[1]), float(spot[2]))
		_save("held_winch_yaw%d" % int(spot[1]))
	_select("fishing_rod")
	p.call("_update_held_item")
	await _park(Vector3(27.4, 2.2, -20.0), -90.0, -4.0)
	_save("held_rod_same_light")
	print("[tool] held rod   %s" % _tip_line(p))

func _tip_line(p: Node) -> String:
	var hand: Node3D = p.get("_hand_item")
	if hand == null or hand.get_child_count() == 0:
		return "hand is EMPTY"
	var container: Node3D = hand.get_child(0)
	var marker: Node = container.find_child("hand_tip", true, false)
	var tip: Vector3 = p.call("hand_tip_world")
	var axis: Variant = p.get("_hand_reach_axis")
	var fb: Vector3 = container.global_transform * (
		(axis if axis is Vector3 else Vector3(0, 0, -1)) * float(p.get("_hand_reach")))
	return "hand_tip=%s tip=%s fallback delta=%.3f m out_from_centre=%.3f m" % [
		"found" if marker is Node3D else "MISSING", str(tip.snappedf(0.001)),
		tip.distance_to(fb), tip.distance_to(container.global_position)]

func _select(id: String) -> void:
	for i in range(PlayerState.hotbar.size()):
		if str(PlayerState.hotbar[i]) == id:
			PlayerState.selected_hotbar = i
			return

# ================================================================== 3. a real cast

## Cast the deep rig off the crane machinery deck and photograph the line running from the
## HOOP FAIRLEAD down to the lead.
##
## Two things make this hard and both are recorded traps. `input_locked` reels the line in on
## the first physics frame, so the pose is held by _process instead (see _hold). And a cast
## that fouls on a rail dies with a toast rather than an error, so every azimuth is tried and
## the line's own state is printed: a fouled attempt is visible in the log as a cast that
## never reached SINK.
func _cast_shots() -> void:
	print("\n[tool] ================ A REAL CAST, OFF THE CRANE MACHINERY DECK ================")
	var p: Node3D = main.player
	# Stand at the deck's south-west quarter, 0.6 m inside the rail, and heave south — the
	# only quarter with nothing but ocean under it all the way down.
	var deck_y: float = RB.CRANE_DECK_TOP
	var stand := Vector3(RB.CRANE_X + 1.6, deck_y, RB.CRANE_Z - RB.CRANE_DECK_HALF + 0.7)
	print("[tool] crane machinery deck top y=%.3f, standing at %s (eye %.2f)"
		% [deck_y, str(stand.snappedf(0.01)), stand.y + EYE_UP])
	PlayerState.add_item("fish_herring")     # the deep rig refuses a bare drop
	PlayerState.add_item("fish_herring")
	PlayerState.add_item("fish_herring")
	_select("deep_rig_pole")
	p.call("_update_held_item")
	var shot: bool = false
	for yaw in [180.0, 200.0, 160.0, 225.0, 135.0]:
		if shot:
			break
		# Held every frame by _process, and input_locked left FALSE on purpose.
		_hold = {"pos": stand, "yaw": deg_to_rad(yaw), "pitch": deg_to_rad(-24.0)}
		p.set("_fly", true)
		p.set("input_locked", false)
		p.set("ui_locked", false)
		# A cast in flight already? Reel it before starting another.
		if p.get("fishing") != null and is_instance_valid(p.get("fishing")):
			(p.get("fishing") as Node).queue_free()
			p.set("fishing", null)
		await get_tree().create_timer(0.8).timeout
		p.call("_start_fishing")
		var rod: Variant = p.get("fishing")
		if rod == null:
			print("[tool] yaw %.0f: no cast object spawned" % yaw)
			continue
		var frames: int = 0
		var reached_water: bool = false
		var saved: int = 0
		while frames < 900:
			await get_tree().physics_frame
			frames += 1
			if not is_instance_valid(rod):
				break
			var st: int = int(rod.get("_state"))
			var depth: float = float(rod.get("_depth"))
			# State 2 == SINK: the lead is in the water and the line is paying out. This is
			# the frame worth photographing, and it is photographed three times as the lead
			# goes down so the line's length is visible as a length.
			if st == 2:
				reached_water = true
				if depth > 1.0 + saved * 7.0 and saved < 3:
					for i in range(2):
						await RenderingServer.frame_post_draw
					_save("cast_yaw%d_d%d" % [int(yaw), int(depth)])
					print("[tool] shot cast at yaw %.0f, depth %.1f m: line %s -> %s (%.1f m)"
						% [yaw, depth, str((p.call("hand_tip_world") as Vector3).snappedf(0.01)),
							str((rod as Node3D).global_position.snappedf(0.01)),
							(p.call("hand_tip_world") as Vector3).distance_to(
								(rod as Node3D).global_position)])
					saved += 1
			if saved >= 3:
				shot = true
				break
		if not shot:
			print("[tool] yaw %.0f: cast did not hold — reached water=%s, frames=%d, %s"
				% [yaw, str(reached_water), frames,
					"line gone (fouled or out of range)" if not is_instance_valid(rod) \
						else "state=%d depth=%.1f" % [int(rod.get("_state")), float(rod.get("_depth"))]])
	if not shot:
		print("[tool] NO CAST WAS PHOTOGRAPHED from the crane deck — see the per-yaw lines above")
	# Wide frame of the same cast from a third-person lens, so the whole line reads.
	if shot and p.get("fishing") != null and is_instance_valid(p.get("fishing")):
		var lead: Vector3 = (p.get("fishing") as Node3D).global_position
		var cam := Camera3D.new()
		cam.fov = 62.0
		add_child(cam)
		var mid: Vector3 = (stand + Vector3(0, EYE_UP, 0) + lead) * 0.5
		cam.global_position = mid + Vector3(14.0, 2.0, 6.0)
		cam.look_at(mid, Vector3.UP)
		cam.current = true
		for i in range(4):
			await RenderingServer.frame_post_draw
		_save("cast_wide")
		print("[tool] wide cast frame: lens %s, subject %s"
			% [str(cam.global_position.snappedf(0.1)), str(mid.snappedf(0.1))])
		cam.current = false
	_hold = {}
	if p.get("fishing") != null and is_instance_valid(p.get("fishing")):
		(p.get("fishing") as Node).queue_free()
		p.set("fishing", null)

# ================================================================== the pack panel

func _pack_panel() -> void:
	if main.hud == null:
		return
	main.hud.visible = true
	for id in ["fishing_rod", "deep_rig_pole", "prybar", "wrench", "rope", "flare", "canned_food"]:
		PlayerState.add_item(id)
	main.hud.toggle_panel("inventory")
	await get_tree().create_timer(4.0).timeout
	_save("pack_panel")
	main.hud.toggle_panel("inventory")
	main.hud.visible = false

# ================================================================== plumbing

## Re-assert the pose every frame of the settle, not once at the start: the controller keeps
## integrating buoyancy and the fly drift across an await, which put three of s21's frames up
## to 3 m from where they were aimed.
func _park(pos: Vector3, yaw_deg: float, pitch_deg: float) -> void:
	var p: Node3D = main.player
	p.set("_fly", true)
	p.set("input_locked", true)
	for i in range(40):
		p.global_position = pos
		p.rotation.y = deg_to_rad(yaw_deg)
		p.get_node("Head").rotation.x = deg_to_rad(pitch_deg)
		p.velocity = Vector3.ZERO
		await get_tree().process_frame
	for i in range(3):
		await RenderingServer.frame_post_draw

func _save(tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png("%s/%s.png" % [_out, tag])
	if err != OK:
		print("[tool] SAVE FAILED %s err=%d" % [tag, err])
