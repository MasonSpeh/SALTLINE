extends Node
## THE DECK WINCH IN HAND — IDLE AND CASTING, photographed and measured.
##
## Owner report, THREE times (2026-07-29 x2, 2026-07-30): "the deep sea rod… looks weird
## casting on its side, by default the 3-d model has the rig with the reel on the left and rod
## curving away to the right, and that never changes. It should default hold/lean to the OTHER
## side, give slight tilt… player should see it both ways, but when casting it goes reel/bail
## up, and the weight/hook points down."
##
## tests/ToolFinal.tscn photographs the winch IDLE only — its cast section shoots the line off
## the crane deck, not the hand — so the pose the owner is complaining about had never been
## rendered at all. This is the missing frame, plus a candidate sweep, plus the rod beside it
## as the accepted control; it runs in ~1 min against ToolFinal's several.
##
## TWO TRAPS THIS FILE EXISTS TO NOT FALL INTO AGAIN:
##
##   * `_hand_posed_cast` CANNOT be set by hand and left. `_sync_hand_pose()` runs every
##     physics frame and rewrites it from `fishing != null`, so a harness that sets the flag
##     and then awaits anything is photographed back in the IDLE pose — with plausible numbers
##     and no error. The first run of this file did exactly that: idle and cast printed
##     identical axes to the digit. A cast pose is held by giving the controller a live
##     `fishing` node, the same way a real cast does.
##   * `HAND_TOOL_POSE` is a `const` Dictionary and therefore READ-ONLY (docs/AGENT_TRAPS.md),
##     so a sweep cannot write into it. `_pose()` re-implements the five lines of
##     `_apply_hand_pose` and candidate 0 of every sweep IS the installed entry, read back out
##     of the shipping table, so the copy is always shown next to the thing it copies.
##
## Run WINDOWED:  godot --path . res://tests/WinchPoseShot.tscn -- <out_dir> [sweep]

const PC := preload("res://scripts/components/player_controller.gd")
## The open-water vantage tool_final.gd proved has sky and sea behind the tool rather than the
## SPHL's rusty hull.
const SPOT := Vector3(27.4, 2.2, -20.0)

## Candidate holds, swept only when the harness is asked for a sweep. Entry 0 of each list is
## filled in from the shipping table at run time — see _cands().
const IDLE_CANDS := [
	{},
	{"axis_to": Vector3(-0.24, 0.93, -0.28), "face_to": Vector3(0.91, 0.18, 0.37),
		"off": Vector3(0.03, 0.10, -0.10)},
]
const CAST_CANDS := [
	{},
	{"axis_to": Vector3(-0.20, 0.68, -0.70), "face_to": Vector3(0.30, 0.72, 0.62),
		"off": Vector3(0.04, 0.00, -0.16)},
	{"axis_to": Vector3(-0.16, 0.62, -0.77), "face_to": Vector3(0.34, 0.70, 0.63),
		"off": Vector3(0.02, 0.02, -0.18)},
	{"axis_to": Vector3(-0.28, 0.70, -0.66), "face_to": Vector3(0.22, 0.72, 0.66),
		"off": Vector3(0.02, 0.04, -0.12)},
]

var main: Node3D
var _out: String = "/tmp/winch_pose"
var _sweep: bool = false
var _pause: CanvasLayer = null
var _fake_cast: Node3D = null

func _process(_d: float) -> void:
	# Both halves of the pause trap: unpause, AND hide the panel, which lives on its own
	# CanvasLayer and stays drawn after the world resumes (docs/AGENT_TRAPS.md).
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
	_sweep = args.size() > 1 and args[1] == "sweep"
	DirAccess.make_dir_recursive_absolute(_out)
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(14.0).timeout
	main._countdown = 0.0
	if main.hud != null:
		if main.hud.fade_rect != null:
			main.hud.fade_rect.color.a = 0.0
		main.hud.visible = false
	# Force the phase ONCE and then leave it: force_phase per frame resets _phase_elapsed_sec
	# and pins the sun at 16° of elevation (docs/AGENT_TRAPS.md).
	GameClock.force_phase(GameClock.Phase.DAY)
	for i in range(10):
		await get_tree().process_frame
	var p: Node3D = main.player
	p.set("_fly", true)
	PlayerState.add_item("deep_rig_pole")
	PlayerState.add_item("fishing_rod")
	_fake_cast = Node3D.new()
	add_child(_fake_cast)
	if _sweep:
		await _sweep_holds(p)
	else:
		await _shipping(p)
	print("\n[winch] done -> %s" % _out)
	get_tree().quit()

## The installed table, photographed exactly as the game draws it.
func _shipping(p: Node3D) -> void:
	for id in ["deep_rig_pole", "fishing_rod"]:
		for yaw in [-90.0, -20.0]:
			await _park(SPOT, yaw, -6.0)
			_select(String(id))
			p.call("_update_held_item")
			await _settle()
			_save("%s_idle_yaw%d" % [id, int(yaw)])
			_axes(p, String(id), "idle")
			await _set_casting(p, true)
			_save("%s_cast_yaw%d" % [id, int(yaw)])
			_axes(p, String(id), "cast")
			await _set_casting(p, false)

## Candidate holds side by side, at the frame size they are judged at.
func _sweep_holds(p: Node3D) -> void:
	await _park(SPOT, -90.0, -6.0)
	_select("deep_rig_pole")
	p.call("_update_held_item")
	await _settle()
	for tag in ["idle", "cast"]:
		var cands: Array = _cands(tag)
		await _set_casting(p, tag == "cast")
		for i in range(cands.size()):
			var c: Dictionary = cands[i]
			for yaw in [-90.0, -20.0]:
				await _park(SPOT, yaw, -6.0)
				_pose(p, c)
				await _settle()
				_save("cand_%s_%d_yaw%d" % [tag, i, int(yaw)])
			_pose(p, c)
			await _settle()
			print("[winch] candidate %s %d  axis_to=%s face_to=%s off=%s"
				% [tag, i, str(c["axis_to"]), str(c["face_to"]), str(c["off"])])
			_axes(p, "deep_rig_pole", tag)
		await _set_casting(p, false)

## Candidate list with entry 0 filled in from the SHIPPING table, so the sheet always contains
## the installed answer and a candidate can be compared against it rather than against memory.
func _cands(tag: String) -> Array:
	var src: Array = IDLE_CANDS if tag == "idle" else CAST_CANDS
	var out: Array = []
	var live: Dictionary = PC.HAND_TOOL_POSE["deep_rig_pole"][tag]
	for i in range(src.size()):
		var c: Dictionary = src[i]
		out.append(c if not c.is_empty() else {
			"axis_to": live["axis_to"], "face_to": live["face_to"], "off": live["off"]})
	return out

## Drive the controller into (or out of) the cast pose the way a live cast does: through
## `fishing`, which is what `_sync_hand_pose` reads every physics frame. Setting
## `_hand_posed_cast` directly is silently undone on the next physics tick.
func _set_casting(p: Node3D, on: bool) -> void:
	p.set("fishing", _fake_cast if on else null)
	await get_tree().physics_frame
	await _settle()

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	for i in range(3):
		await RenderingServer.frame_post_draw

func _select(id: String) -> void:
	for i in range(PlayerState.hotbar.size()):
		if str(PlayerState.hotbar[i]) == id:
			PlayerState.selected_hotbar = i
			return

func _park(pos: Vector3, yaw: float, pitch: float) -> void:
	var p: Node3D = main.player
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw)
	p.get_node("Head").rotation.x = deg_to_rad(pitch)
	p.velocity = Vector3.ZERO
	PlayerState.oxygen = 1.0
	PlayerState.life = 1.0
	PlayerState.warmth = 1.0
	await _settle()

## _apply_hand_pose's five lines, against a candidate instead of the const table.
func _pose(p: Node3D, c: Dictionary) -> void:
	var hand: Node3D = p.get("_hand_item")
	if hand == null or hand.get_child_count() == 0:
		return
	var container: Node3D = hand.get_child(0)
	var visual: Node3D = container.get_child(0) as Node3D
	var marker: Node = visual.find_child("hand_tip", true, false)
	if not (marker is Node3D):
		return
	var pivot: Node3D = (marker as Node3D).get_parent() as Node3D
	var b_pivot: Basis = Basis.IDENTITY
	var cur: Node3D = pivot
	while cur != null and cur != visual:
		b_pivot = cur.transform.basis * b_pivot
		cur = cur.get_parent() as Node3D
	var def: Dictionary = PC.HAND_TOOL_POSE["deep_rig_pole"]
	var aim: Basis = PC._aim_basis(def["axis"], def["face"], c["axis_to"], c["face_to"])
	var b: Basis = hand.transform.basis.inverse() * aim * b_pivot.inverse()
	container.transform = Transform3D(
		b.scaled(Vector3.ONE * float(p.get("_hand_scale"))), c["off"])

func _save(tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, tag])

## WHERE THE TOOL'S OWN AXES ACTUALLY POINT. `face` is read out of the shipping
## HAND_TOOL_POSE table rather than restated, so this cannot drift from what is installed —
## the winch's entry names its DRUM BRACKET now, not the drum's axle.
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
	var def: Dictionary = PC.HAND_TOOL_POSE.get(id, {})
	var m_axis: Vector3 = def.get("axis", Vector3(0, 1, 0))
	var m_face: Vector3 = def.get("face", Vector3(1, 0, 0))
	var long_axis: Vector3 = inv * (b * m_axis)
	var face: Vector3 = inv * (b * m_face)
	# The crank/ratchet side is the model's +Z on the winch; it is what tells you whether the
	# player is looking at the drive cheek or at the blank far cheek.
	var crank: Vector3 = inv * (b * Vector3(0, 0, 1))
	var centre: Vector3 = inv * (container.global_position - cam.global_position)
	# ...and where the line actually leaves, in SCREEN pixels, which is the only way to see
	# that the fairlead and its tackle are sitting on top of the crosshair.
	var tip: Vector3 = (marker as Node3D).global_position
	var px: Vector2 = cam.unproject_position(tip)
	print("[winch] %-14s %-4s  long %s | reel/drum %s | crank %s | centre x=%+.2f | fairlead px %s of %s"
		% [id, tag, str(long_axis.snappedf(0.01)), str(face.snappedf(0.01)),
			str(crank.snappedf(0.01)), centre.x, str(px.round()),
			str(get_viewport().get_visible_rect().size)])
	var stowed: Node = container.find_child("stowed_tackle", true, false)
	if stowed is Node3D and (stowed as Node3D).visible:
		var down: Vector3 = (stowed as Node3D).global_transform.basis.orthonormalized() * Vector3.DOWN
		print("[winch]                    tackle hangs toward WORLD %s (down·(0,-1,0)=%+.3f)"
			% [str(down.snappedf(0.01)), down.dot(Vector3.DOWN)])
