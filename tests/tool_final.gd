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
##   2. BOTH TOOLS IN HAND, IDLE AND CASTING — four frames, because the owner has reported the
##      held orientation wrong twice and the two poses are different objects to look at. Each
##      frame is printed with where the tool's OWN axes ended up in camera space, so "on its
##      side" and "reel up" are a number as well as a picture.
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
		{"centre": Vector3(-0.08, 0.55, 0.04), "size": 0.62},
		{"centre": Vector3(-0.10, 0.53, 0.06), "size": 0.50},
		{"centre": Vector3(-0.12, 0.52, 0.08), "size": 0.42},
		{"centre": Vector3(-0.04, 0.52, 0.04), "size": 0.78},
	],
	"fishing_rod": [
		{"centre": Vector3(-0.01, 0.62, 0.0), "size": 0.40},
		{"centre": Vector3(-0.02, 0.66, 0.0), "size": 0.52},
		{"centre": Vector3(-0.05, 0.72, 0.0), "size": 0.66},
		{"centre": Vector3(-0.10, 0.80, 0.0), "size": 0.86},
	],
}

## Where a cast is taken from: the crane's machinery deck. Derived from rig_builder's own
## constants rather than typed — CRANE_X 2.0, CRANE_Z -14.0, CRANE_DECK_HALF 3.5 — so the
## vantage cannot drift away from the deck if the crane moves.
const RB := preload("res://scripts/world/rig_builder.gd")
## Preloaded by path, not by class_name — the project's own rule, and the reason
## player_controller._start_fishing() does the same.
const FR := preload("res://scripts/components/fishing_rod.gd")
const EYE_UP: float = 1.6
## The shipping hand-pose table. `Object.get()` does not resolve script constants.
const FR_POSE := preload("res://scripts/components/player_controller.gd").HAND_TOOL_POSE

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
		# TOP EVERYTHING UP EVERY FRAME. Round 3 came back with an OXYGEN bar in the HUD over
		# every cast frame — the run is long enough for the survival clocks to bite, and a
		# photograph of a drowning player is a photograph of the wrong thing. This is the s21
		# lesson ("top the air up every frame of any underwater interaction test") applied to a
		# shot list rather than a probe.
		#
		# NOTE what is deliberately NOT here: GameClock.force_phase(). Calling it per frame
		# looks like the obvious way to hold the light still and is the opposite — it resets
		# `_phase_elapsed_sec` to 0, i.e. it PINS the sun at DAY f=0, which SunController maps
		# to 16° of elevation. Round 4's frames came back with pink deck plate and salmon
		# girders for exactly that reason. DAY runs 34 minutes, so nothing in a four-minute
		# harness can leave it: set the clock to mid-DAY once (see _cast_shots) and leave it be.
		PlayerState.oxygen = 1.0
		PlayerState.life = 1.0
		PlayerState.warmth = 1.0

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

func _icon_sweep() -> void:
	print("\n[tool] ================ PACK SLOT (%d px, the size it is drawn at) ================"
		% SLOT_PX)
	var ico: Node = ItemIcons.new()
	add_child(ico)
	for id in IDS:
		# The SHIPPING picture first, straight out of ItemIcons.get_icon(), so the sweep has
		# something to be checked against rather than merely resembling.
		ico.call("get_icon", id)
		var live: Texture2D = null
		for i in range(400):
			await get_tree().process_frame
			live = (ico.get("_cache") as Dictionary).get(id, null)
			if live != null:
				break
		if live == null:
			print("[tool] icon %s: the SHIPPING path rendered nothing" % id)
			continue
		_slot_pngs(live.get_image(), "%s/slot_%s_shipping" % [_out, id])
		var cands: Array = ICON_CANDS[id]
		for ci in range(cands.size()):
			var c: Dictionary = cands[ci]
			var img: Image = await _icon_render(ico, id, c)
			if img == null:
				print("[tool] icon %s cand%d: NOT RENDERED" % [id, ci])
				continue
			var small: Image = _slot_pngs(img, "%s/slot_%s_c%d" % [_out, id, ci])
			var note: String = ""
			if ci == 0:
				# Candidate 0 IS the installed entry, so this diff is the proof that the
				# harness's copy of the framing is the shipping framing. Anything but ~0
				# means the sweep is photographing code that is not going to ship.
				note = "   <-- INSTALLED, diff vs shipping render = %.4f" % _diff(img, live.get_image())
			print("[tool] icon %-14s cand%d centre=%s size=%.2f  ink=%.1f%% of the slot%s"
				% [id, ci, str(c["centre"]), float(c["size"]), _ink(small) * 100.0, note])
	ico.queue_free()

## One icon, framed by `focus`, on ItemIcons' own stage. The eight framing lines are copied
## from ItemIcons._render because a `const` Dictionary cannot be swapped (see the header);
## everything expensive to get wrong — the lights, the environment, the orthogonal
## projection, the two-frame settle — is the shipping code, called on the shipping node.
func _icon_render(ico: Node, id: String, focus: Dictionary) -> Image:
	var model: Node3D = ItemVisual.build(id)
	if model == null:
		return null
	var stage: Array = ico.call("_stage", Vector2i(ItemIcons.ICON_PX, ItemIcons.ICON_PX))
	var vp: SubViewport = stage[0]
	var cam: Camera3D = stage[1]
	vp.add_child(model)
	await get_tree().process_frame
	var box: AABB = ico.call("_bounds", model)
	if box.size.length() <= 0.0001:
		ico.call("_drop_stage", vp)
		return null
	var centre: Vector3 = focus["centre"]
	var reach: float = maxf(box.size.length(), 0.001)
	cam.near = 0.01
	cam.far = reach * 8.0 + 10.0
	cam.global_position = centre + ItemIcons.VIEW_DIR.normalized() * (reach * 3.0 + 1.0)
	cam.look_at(centre, Vector3.UP)
	cam.size = maxf(float(focus["size"]), 0.001) / ItemIcons.FRAME_FILL
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	ico.call("_drop_stage", vp)
	return img

## Save the honest 74 px AND the same pixels blown up NEAREST, so the slot can be inspected
## without a resampler inventing detail the slot will not have. Returns the 74 px image.
func _slot_pngs(img: Image, stem: String) -> Image:
	var small: Image = img.duplicate()
	small.resize(SLOT_PX, SLOT_PX, Image.INTERPOLATE_LANCZOS)
	small.save_png("%s_true74.png" % stem)
	var zoom: Image = small.duplicate()
	zoom.resize(SLOT_PX * ZOOM, SLOT_PX * ZOOM, Image.INTERPOLATE_NEAREST)
	zoom.save_png("%s_zoom.png" % stem)
	return small

## Mean absolute RGBA difference between two same-size images, 0..1.
func _diff(a: Image, b: Image) -> float:
	if a.get_size() != b.get_size():
		return 1.0
	var acc: float = 0.0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			acc += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a)
	return acc / float(a.get_width() * a.get_height() * 4)

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

## HAND_TOOL_POSE is a `const` Dictionary and therefore read-only, so a candidate is applied
## by OVERWRITING the container the controller just posed: `_normalize_hand_visual` sets
## `container.rotation` outright and adds `off` to a position that starts at zero, so writing
## both afterwards is exactly equivalent to a different table entry. The installed values are
## read back off the container rather than restated here, so this cannot drift from the table.
func _held_sweep() -> void:
	print("\n[tool] ================ BOTH TOOLS IN HAND, IDLE AND CASTING ================")
	var p: Node3D = main.player
	p.set("_fly", true)
	PlayerState.add_item("deep_rig_pole")
	PlayerState.add_item("fishing_rod")
	for i in range(4):
		PlayerState.add_item("fish_herring")
	# The open-water vantage item_shot.gd and option_shot.gd both proved has sky and sea behind
	# the tool: a held shot against the SPHL's hull photographs a rusty wall.
	for id in ["fishing_rod", "deep_rig_pole"]:
		await _park(Vector3(27.4, 2.2, -20.0), -90.0, -6.0)
		_select(id)
		p.call("_update_held_item")
		await get_tree().process_frame
		for i in range(3):
			await RenderingServer.frame_post_draw
		_save("hold_%s_idle" % id)
		_axes(p, id, "idle")
		print("[tool] idle  %-14s %s" % [id, _tip_line(p)])
	# ...and the SURFACE ROD ACTUALLY CASTING, from the same spot. The winch's cast needs the
	# 45 m of air off the crane deck and gets its own section; the wand fishes the surface from
	# the wet deck, which is where a player uses it. input_locked stays FALSE and the pose is
	# held by _process — fishing_rod._physics_process reels the line straight in otherwise.
	_select("fishing_rod")
	p.call("_update_held_item")
	_hold = {"pos": Vector3(27.4, 2.2, -20.0), "yaw": deg_to_rad(-90.0), "pitch": deg_to_rad(-14.0)}
	p.set("input_locked", false)
	p.set("ui_locked", false)
	await get_tree().create_timer(0.8).timeout
	p.call("_start_fishing")
	var rod: Variant = p.get("fishing")
	if rod == null:
		print("[tool] the wand did not cast at all")
	else:
		var frames: int = 0
		var got: bool = false
		while frames < 600 and is_instance_valid(rod):
			await get_tree().physics_frame
			frames += 1
			# State 1 == DRIFT: the float is on the water and the line is out.
			if int(rod.get("_state")) == 1:
				for i in range(3):
					await RenderingServer.frame_post_draw
				_save("hold_fishing_rod_cast")
				_axes(p, "fishing_rod", "cast")
				print("[tool] cast  fishing_rod  float at %s, %s"
					% [str((rod as Node3D).global_position.snappedf(0.01)), _tip_line(p)])
				got = true
				break
		if not got:
			print("[tool] the wand's cast never reached DRIFT (frames=%d, alive=%s)"
				% [frames, str(is_instance_valid(rod))])
		if is_instance_valid(rod):
			(rod as Node).queue_free()
		p.set("fishing", null)
		await get_tree().physics_frame
		await get_tree().physics_frame
	_hold = {}
	# The winch from two more angles at the installed pose, and the rod in the same light — the
	# only honest test of whether a palette reads as salt-hazed gunmetal or as pale plastic.
	_select("deep_rig_pole")
	p.call("_update_held_item")
	for spot in [[Vector3(27.0, 2.3, -20.0), 0.0, -8.0], [Vector3(14.0, 3.2, -23.4), 84.0, -2.0]]:
		await _park(spot[0], float(spot[1]), float(spot[2]))
		_save("hold_deep_rig_pole_yaw%d" % int(spot[1]))
	_select("fishing_rod")
	p.call("_update_held_item")
	await _park(Vector3(27.4, 2.2, -20.0), -90.0, -6.0)
	_save("hold_rod_same_light")

## WHERE THE TOOL'S OWN AXES ACTUALLY POINT, in camera space, for the pose on screen right now.
## This is the measurement the owner's complaint is about: "on its side" is the reel-side axis
## having a big RIGHT component and almost no UP one. Printed next to every held frame so the
## picture and the number are the same evidence.
func _axes(p: Node, id: String, tag: String) -> void:
	var hand: Node3D = p.get("_hand_item")
	if hand == null or hand.get_child_count() == 0:
		return
	var container: Node3D = hand.get_child(0)
	var visual: Node3D = container.get_child(0) as Node3D
	var marker: Node = visual.find_child("hand_tip", true, false)
	if not (marker is Node3D):
		return
	var pivot: Node3D = (marker as Node3D).get_parent() as Node3D
	var cam: Camera3D = p.get("camera")
	var inv: Basis = cam.global_transform.basis.inverse()
	var b: Basis = pivot.global_transform.basis.orthonormalized()
	var long_axis: Vector3 = inv * (b * Vector3(0, 1, 0))
	# Read out of the shipping table, not restated: s23 changed the winch's `face` from its
	# drum AXLE to the drum BRACKET (which side the reel is on), which is the axis the owner's
	# report was always about.
	var face: Vector3 = inv * (b * Vector3(
		FR_POSE.get(id, {}).get("face", Vector3(1, 0, 0))))
	var centre: Vector3 = inv * (container.global_position - cam.global_position)
	print("[tool]   %-14s %-4s long axis -> cam %s | reel/drum axis -> cam %s | tool centre x=%+.2f"
		% [id, tag, str(long_axis.snappedf(0.01)), str(face.snappedf(0.01)), centre.x])
	print("[tool]        (cam space: +x right, +y up, +z back toward the player)")

## The cast photographed from BESIDE the line. Derived from the two live endpoints — the
## fairlead and the lead — rather than typed: the lens goes out along the horizontal normal to
## the line's own vertical plane, level with a third of the way down, and looks at that point.
func _along_the_line(p: Node, rod: Node3D) -> void:
	var top: Vector3 = p.call("hand_tip_world")
	var bot: Vector3 = rod.global_position
	var flat := Vector3(bot.x - top.x, 0.0, bot.z - top.z)
	if flat.length() < 0.5:
		flat = Vector3(0, 0, -1)
	var side: Vector3 = flat.normalized().cross(Vector3.UP)     # perpendicular, horizontal
	var cam := Camera3D.new()
	cam.fov = 62.0
	add_child(cam)
	# THREE FRAMES, BECAUSE ONE CANNOT DO IT. The line is 50.6 m long and 12 mm thick: a lens far
	# enough back to hold both ends (25 m of half-height at fov 62 needs ~42 m of standoff) draws
	# it a quarter of a pixel wide, and a lens close enough for it to read holds a few metres of
	# it. So: the TOP (does it leave the fairlead?), the WHOLE RUN (is it one continuous line
	# from the tool to the water?), and the BOTTOM (does it reach the lead?). Every frame prints
	# where the two ends actually landed on screen, so a frame that missed is visible in the log.
	for job in [["full", 0.5, 48.0], ["lead", 1.0, 7.0]]:
		var aim: Vector3 = top.lerp(bot, float(job[1]))
		var back: float = float(job[2])
		cam.global_position = aim + side * back + Vector3(0, back * 0.10, 0)
		cam.look_at(aim, Vector3.UP)
		cam.current = true
		for i in range(4):
			await RenderingServer.frame_post_draw
		_save("cast_beside_%s" % str(job[0]))
		var s_top: String = "BEHIND LENS" if cam.is_position_behind(top) \
			else str(cam.unproject_position(top).snappedf(1.0))
		var s_bot: String = "BEHIND LENS" if cam.is_position_behind(bot) \
			else str(cam.unproject_position(bot).snappedf(1.0))
		print("[tool] beside-the-line '%s' at %.0f m: lens %s aim %s -> fairlead %s, lead %s"
			% [str(job[0]), back, str(cam.global_position.snappedf(0.1)),
				str(aim.snappedf(0.1)), s_top, s_bot])
	cam.current = false
	cam.queue_free()

## WHERE ON SCREEN THE LINE STARTS, and where the fist is, in the same pixels. This is the
## measurement behind "the line leaves the fairlead, not the player's fist": the line is drawn
## from hand_tip_world() to the lead, so if the marker were lost the start point would collapse
## onto the container's centre — which is the grip. Printing both projected positions makes the
## difference a number in the log rather than something to be squinted at in the PNG.
func _line_origin(p: Node, rod: Node3D, yaw: float, depth: float) -> void:
	var cam: Camera3D = p.get("camera")
	var hand: Node3D = p.get("_hand_item")
	var container: Node3D = hand.get_child(0)
	var tip: Vector3 = p.call("hand_tip_world")
	var fist: Vector3 = container.global_position
	var lead: Vector3 = rod.global_position
	var s_tip: Vector2 = cam.unproject_position(tip)
	var s_fist: Vector2 = cam.unproject_position(fist)
	var s_lead: String = "off frame" if cam.is_position_behind(lead) \
		else str(cam.unproject_position(lead).snappedf(1.0))
	print("[tool] cast yaw %.0f depth %.1f m: line %s -> %s (%.1f m of line)"
		% [yaw, depth, str(tip.snappedf(0.01)), str(lead.snappedf(0.01)), tip.distance_to(lead)])
	print("[tool]     on screen: fairlead %s   fist %s   %.0f px apart   lead %s"
		% [str(s_tip.snappedf(1.0)), str(s_fist.snappedf(1.0)), s_tip.distance_to(s_fist),
			s_lead])
	# A CROP AROUND THE FAIRLEAD, because that is the owner's actual condition and a 12 mm line
	# 40 m long is a handful of pixels wide in a 1280 px frame. The crop is centred on the
	# PROJECTED marker position, not on a guess, and blown up NEAREST so no resampler invents a
	# line that is not there. If the line were anchored in the fist instead, this crop would
	# show a bare hoop — the fist is 389 px away.
	var img: Image = get_viewport().get_texture().get_image()
	var w: int = 300
	var h: int = 220
	var x0: int = clampi(int(s_tip.x) - w / 2, 0, maxi(img.get_width() - w, 0))
	var y0: int = clampi(int(s_tip.y) - h / 2, 0, maxi(img.get_height() - h, 0))
	var crop: Image = img.get_region(Rect2i(x0, y0, mini(w, img.get_width()),
		mini(h, img.get_height())))
	crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/cast_fairlead_crop_d%d.png" % [_out, int(depth)])

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
	# Stand 0.7 m inside the deck's NORTH rail and heave north (yaw 0 = −Z). Direction matters
	# and is derived, not chosen: the topside deck below runs x[−30,30] z[−20,20] and the wet
	# deck only starts at x 6, so from the crane's x≈3.6 the north edge is 3.2 m away and there
	# is nothing under the lead after that but sea. Heaving SOUTH from here goes further INTO
	# the footprint (+z is south on this rig) and the lead lands on the topside deck, which
	# fishing_rod's in-flight foul ray correctly refuses.
	var deck_y: float = RB.CRANE_DECK_TOP
	var stand := Vector3(RB.CRANE_X + 1.6, deck_y, RB.CRANE_Z - RB.CRANE_DECK_HALF + 0.7)
	print("[tool] crane machinery deck top y=%.3f, standing at %s (eye %.2f)"
		% [deck_y, str(stand.snappedf(0.01)), stand.y + EYE_UP])
	# MID-DAY, ONCE. force_phase(DAY) alone leaves the sun at 16° (see the note in _process),
	# which photographs everything on this rig in low warm light; winding the phase clock to
	# 45% of DAY's 34 minutes puts the sun high and white, and it stays there because a
	# four-minute harness cannot run DAY out.
	GameClock.force_phase(GameClock.Phase.DAY)
	GameClock.set("_phase_elapsed_sec",
		float(GameClock.phase_durations_minutes[GameClock.Phase.DAY]) * 60.0 * 0.45)
	print("[tool] clock parked at DAY f=%.2f" % GameClock.phase_fraction())
	# BAIT FIRST, THEN DROP: fishing_rod.setup() refuses a bare hook and lets the first
	# physics frame reel it in, so the [B] press has to be simulated (try_bait_now) before
	# every attempt or the "cast" is a one-frame abort with a toast and no line at all.
	for i in range(6):
		PlayerState.add_item("fish_herring")
	_select("deep_rig_pole")
	p.call("_update_held_item")
	# The HUD stays ON for these frames: the deep rig's depth readout is what makes the
	# picture self-documenting — a line to the sea could be anything, "42 m" cannot.
	if main.hud != null:
		main.hud.visible = true
	var shot: bool = false
	for yaw in [0.0, 340.0, 20.0, 315.0, 45.0]:
		if shot:
			break
		_select("deep_rig_pole")
		# PITCH IS NOT A TASTE CHOICE HERE. The lead leaves the fairlead 35.7 m above the sea
		# and lands 17.4 m out, so it is ~64° BELOW the horizontal: at the -24° a player looks
		# out to sea at, the lead and most of the line are off the bottom of the frame and the
		# picture proves nothing. The frame covers pitch ± 37.5° (fov 75, KEEP_HEIGHT), so -52°
		# puts the splash-down point at -12° inside it while the winch — parented to the camera
		# — stays exactly where it is. The deep heave ignores pitch entirely
		# (fishing_rod.setup flattens the look direction), so aiming down cannot change the cast.
		_hold = {"pos": stand, "yaw": deg_to_rad(yaw), "pitch": deg_to_rad(-52.0)}
		p.set("_fly", true)
		p.set("input_locked", false)
		p.set("ui_locked", false)
		# A cast in flight already? Reel it before starting another.
		if p.get("fishing") != null and is_instance_valid(p.get("fishing")):
			(p.get("fishing") as Node).queue_free()
			p.set("fishing", null)
		await get_tree().create_timer(0.8).timeout
		var baited: bool = bool(FR.try_bait_now(p))
		p.call("_start_fishing")
		var rod: Variant = p.get("fishing")
		if rod == null:
			print("[tool] yaw %.0f: no cast object spawned (baited=%s)" % [yaw, str(baited)])
			continue
		print("[tool] yaw %.0f: cast away, baited=%s" % [yaw, str(baited)])
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
				if depth > 0.4 + saved * 4.0 and saved < 3:
					for i in range(2):
						await RenderingServer.frame_post_draw
					_save("cast_yaw%d_d%d" % [int(yaw), int(depth)])
					_line_origin(p, rod as Node3D, yaw, depth)
					saved += 1
			if saved >= 3:
				# THE LINE IS RADIAL TO THE VIEW WHEN YOU LOOK AT WHAT YOU CAST AT, and a
				# radial line has no length on screen: it runs from 0.5 m away (the fairlead)
				# to 44 m away (the lead), 12 mm thick, so at the cast azimuth it foreshortens
				# to a streak a few pixels long next to the lead and the picture proves nothing.
				# Turning the PLAYER (not the lead) puts the same line side-on: the winch is
				# parented to the camera so the fairlead stays put at the top right, while the
				# lead swings left and the line becomes a diagonal across the frame. Turning
				# right (decreasing yaw) is what moves it LEFT, i.e. clear of the HUD's depth
				# panel. The player does not MOVE, so CANCEL_DISTANCE is never tripped.
				for job in [[30.0, -40.0], [50.0, -40.0], [45.0, -30.0]]:
					_hold = {"pos": stand, "yaw": deg_to_rad(yaw - float(job[0])),
						"pitch": deg_to_rad(float(job[1]))}
					await get_tree().create_timer(0.6).timeout
					for i in range(3):
						await RenderingServer.frame_post_draw
					if not is_instance_valid(rod):
						print("[tool] the line went while turning %.0f° off the cast" % float(job[0]))
						break
					_save("cast_sideon_y%d_p%d" % [int(job[0]), int(-float(job[1]))])
					_line_origin(p, rod as Node3D, yaw - float(job[0]), float(rod.get("_depth")))
				# ...and the same line from a lens set BESIDE it, which is the only frame that can
				# hold all 50 m: from the deck the run is either radial to the view or crossed by
				# the crane's own edge rails. The lens is placed perpendicular to the line's
				# vertical plane, level with its upper third, and aimed a third of the way down —
				# so the fairlead, the player and the whole descent are in one picture.
				if is_instance_valid(rod):
					await _along_the_line(p, rod as Node3D)
				shot = true
				break
		if not shot:
			print("[tool] yaw %.0f: cast did not hold — reached water=%s, frames=%d, %s"
				% [yaw, str(reached_water), frames,
					"line gone (fouled or out of range)" if not is_instance_valid(rod) \
						else "state=%d depth=%.1f" % [int(rod.get("_state")), float(rod.get("_depth"))]])
	if not shot:
		print("[tool] NO CAST WAS PHOTOGRAPHED from the crane deck — see the per-yaw lines above")
	# A second wide frame of the same cast, aimed at the line's midpoint from further out.
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
	if main.hud != null:
		main.hud.visible = false
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
