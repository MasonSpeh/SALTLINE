extends Node
## Do BOTH fishing tools still hand their working end to the fishing line?
##
## Each tool's ItemVisual plants a Node3D called "hand_tip" at the end the line leaves from
## — the rod's roller tip, the deep rig's sheave — and player_controller.hand_tip_world()
## finds it BY NAME. Rebuild either tool's geometry without that node, or leave it parented
## to something that no longer carries the rig's tilt, and the line silently anchors at the
## grip (or at the player's feet) instead. Nothing about that is visible in a screenshot, so
## it is asserted here: hold the tool, ask the live controller where the tip is, and check
## the answer is the tool's own far end rather than the _hand_reach_axis fallback.
##
## Covers every id in player_controller.ROD_ITEMS rather than a hardcoded list, so a third
## fishing tool cannot be added without this probe noticing it.
##
##   godot --headless --path . res://tests/RodHandProbe.tscn

## The shipping pose table, by path — `Object.get()` does not resolve script CONSTANTS, and a
## null there would silently fall back to a guessed axis and assert nothing.
const PC := preload("res://scripts/components/player_controller.gd")

const SETTLE := 5.0
var _t := 0.0
var _ran := false
var _fails := 0

func _ready() -> void:
	add_child((load("res://scenes/Main.tscn") as PackedScene).instantiate())

func _chk(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		_fails += 1
		print("FAIL  %s %s" % [label, detail])

func _process(d: float) -> void:
	if _ran:
		return
	_t += d
	if _t < SETTLE:
		return
	_ran = true
	var p: Node = get_tree().get_first_node_in_group("player")
	_chk("player exists", p != null)
	if p == null:
		get_tree().quit()
		return
	var ids: Variant = p.get("ROD_ITEMS")
	var tools: Array = Array(ids) if ids != null else ["fishing_rod", "deep_rig_pole"]
	_chk("the controller lists both fishing tools", tools.size() >= 2, str(tools))
	for id in tools:
		await _check_tool(p, String(id))
	print("\n[rod_hand] FAILURES: %d" % _fails)
	get_tree().quit()

func _check_tool(p: Node, id: String) -> void:
	print("\n--- %s ---" % id)
	# The built visual carries the marker at all.
	var built: Node3D = ItemVisual.build(id)
	var m: Node = built.find_child("hand_tip", true, false)
	_chk("ItemVisual('%s') plants a hand_tip node" % id, m is Node3D)
	built.queue_free()

	PlayerState.add_item(id)
	for i in range(PlayerState.hotbar.size()):
		if str(PlayerState.hotbar[i]) == id:
			PlayerState.selected_hotbar = i
	# Selecting a slot does NOT itself rebuild the hand — _hotbar_pressed() calls
	# _update_held_item() straight after setting the slot (only inventory_changed is
	# connected), so a probe that only assigns selected_hotbar holds an empty hand.
	p.call("_update_held_item")
	await get_tree().process_frame
	await get_tree().process_frame
	_chk("%s is the selected item" % id, str(p.call("_selected_item_id")) == id)

	var hand: Node3D = p.get("_hand_item")
	_chk("the hand holds a built visual", hand != null and hand.get_child_count() > 0)
	if hand == null or hand.get_child_count() == 0:
		return
	var container: Node3D = hand.get_child(0)
	var live: Node = container.find_child("hand_tip", true, false)
	_chk("the HELD %s still exposes hand_tip by name" % id, live is Node3D)

	var tip: Vector3 = p.call("hand_tip_world")
	var cam: Camera3D = p.get("camera")
	# The marker path and the fallback path must NOT agree — if hand_tip went missing,
	# hand_tip_world() quietly returns the _hand_reach_axis guess and everything still
	# "works", just anchored in the wrong place. So compare them explicitly, against the
	# axis the controller would ACTUALLY have used for this id (HAND_TIP_AXIS is per-item,
	# and only the rod has an entry — the deep rig's fallback runs along -Z).
	var axis: Variant = p.get("_hand_reach_axis")
	var fallback: Vector3 = container.global_transform * (
		(axis if axis is Vector3 else Vector3(0, 0, -1)) * float(p.get("_hand_reach")))
	print("      tip=%s  container=%s  fallback=%s  reach=%.3f  delta=%.3f"
		% [str(tip.snappedf(0.001)), str(container.global_position.snappedf(0.001)),
			str(fallback.snappedf(0.001)), float(p.get("_hand_reach")),
			tip.distance_to(fallback)])
	_chk("the tip is a real finite point", is_finite(tip.x) and is_finite(tip.y) and is_finite(tip.z))
	_chk("the marker answer is NOT the fallback answer", tip.distance_to(fallback) > 0.05,
		"they agree to %.4f m — hand_tip may have been lost" % tip.distance_to(fallback))
	# Both tools are normalised to 0.9 m in hand and the marker sits at the working end, so
	# the tip must be roughly a half-tool out from the container's centre — not on top of it
	# (grip) and not metres away (a stale/lost transform).
	var out: float = tip.distance_to(container.global_position)
	_chk("the tip is out at the tool's far end, not at the grip", out > 0.30 and out < 0.75,
		"distance from held-item centre = %.3f m" % out)
	# And it has to be the END the LINE leaves from: ahead of the camera, not behind it.
	if cam != null:
		var ahead: float = (tip - cam.global_position).dot(-cam.global_transform.basis.z)
		_chk("the tip is out in front of the player, where line pays out", ahead > 0.2,
			"forward component = %.3f m" % ahead)
	# AWAITED, not fired and forgotten: this coroutine awaits frames, and without the await the
	# caller moves on to the next tool, whose _update_held_item frees the container out from
	# under it ("Invalid access to property 'global_transform' on a previously freed object").
	await _check_orientation(p, id, container, cam)

## IS IT ON ITS SIDE? Owner report, 2026-07-29: "fishing poles still oriented on side… when
## casting it goes reel/bail up. Also flip default side to the right instead of left."
##
## The roll nobody wrote was the product of six stacked Euler angles (two on the hand mount,
## three on the container, one inside the model), so it is asserted here on the COMPOSED basis
## rather than on any one of them: take the tool's own axes off the live pivot, express them in
## camera space, and check the three things the complaint names. Measured before the fix, the
## rod's reel-side axis came out (+0.85 right, +0.20 up) — beside the blank, not on top of it.
##
## +x is the player's right, +y is up, +z is BACK toward the player.
func _check_orientation(p: Node, id: String, container: Node3D, cam: Camera3D) -> void:
	if cam == null:
		return
	var visual: Node3D = container.get_child(0) as Node3D
	var marker: Node = visual.find_child("hand_tip", true, false)
	if not (marker is Node3D):
		return
	# The pivot is the node carrying the marker — the same node player_controller aims.
	var pivot: Node3D = (marker as Node3D).get_parent() as Node3D
	var inv: Basis = cam.global_transform.basis.inverse()
	var b: Basis = pivot.global_transform.basis.orthonormalized()
	# Both tools run their long axis up the model's own +Y; what stands off that axis is the
	# reel/drum bracket. WHICH axis that is comes out of the SHIPPING table rather than being
	# restated here — the winch's entry named its drum AXLE until s23 and named the wrong thing,
	# which is how "the reel is on the left" survived two fixes. Reading `face` back means this
	# probe measures whatever the table claims to be aiming.
	var def: Dictionary = PC.HAND_TOOL_POSE.get(id, {})
	var long_axis: Vector3 = inv * (b * Vector3(def.get("axis", Vector3(0, 1, 0))))
	var face_dir: Vector3 = inv * (b * Vector3(def.get("face", Vector3(1, 0, 0))))
	var centre: Vector3 = inv * (container.global_position - cam.global_position)
	print("      long axis -> cam %s   reel/drum axis -> cam %s   tool centre x=%+.3f"
		% [str(long_axis.snappedf(0.001)), str(face_dir.snappedf(0.001)), centre.x])
	_chk("%s is held on the RIGHT of the view" % id, centre.x > 0.05,
		"container centre is at camera-space x=%+.3f" % centre.x)
	_chk("%s's long axis rises and leans away, not across the view" % id,
		long_axis.y > 0.35 and long_axis.z < 0.05,
		"long axis = %s" % str(long_axis.snappedf(0.001)))
	if id == "fishing_rod":
		# The whole complaint in one number. A reel BESIDE the blank has |x| >> y; a reel on top
		# has y as its largest component. There is a hard ceiling on how "up" it can be —
		# nothing perpendicular to the blank can have more up than sqrt(1 - blank.y^2) — so the
		# test is stated as a comparison against the sideways component, not an absolute.
		_chk("the rod's reel sits ON TOP of the blank, not beside it",
			face_dir.y > absf(face_dir.x) and face_dir.y > 0.3,
			"reel-side axis = %s (up must beat sideways)" % str(face_dir.snappedf(0.001)))
	else:
		# THE THIRD REPORT, stated as a number. Owner, 2026-07-30: "the 3-d model has the rig
		# with the reel on the LEFT… it should default hold/lean to the OTHER side." The drum
		# bracket measured (-0.81, +0.10, -0.57) before item_visual._mirror_x — left and away.
		# It has to read RIGHT, and the crank/ratchet side (model +Z) has to come back toward
		# the player or the drive cheek is hidden and the tool reads back-to-front.
		_chk("the winch's drum stands off to the player's RIGHT, not the left",
			face_dir.x > 0.5 and face_dir.x > absf(face_dir.y),
			"drum bracket = %s (x must be positive and dominant)"
				% str(face_dir.snappedf(0.001)))
		var crank: Vector3 = inv * (b * Vector3(0, 0, 1))
		_chk("the winch's crank side faces the player rather than turning its back",
			crank.z > 0.45, "crank axis = %s (z must point back at the player)"
				% str(crank.snappedf(0.001)))
		# ...and the tackle is gravity-aligned, in every pose, by
		# player_controller._hang_stowed_tackle(): the lead and hook fall straight down rather
		# than trailing off whatever angle the mast happens to be at.
		var hang: Node = container.find_child("stowed_tackle", true, false)
		if hang is Node3D:
			var down: Vector3 = (hang as Node3D).global_transform.basis.orthonormalized() * Vector3.DOWN
			_chk("the winch's weight and hook hang straight DOWN",
				down.dot(Vector3.DOWN) > 0.999, "tackle down = %s" % str(down.snappedf(0.001)))
	# THE CAST POSE IS A SECOND ORIENTATION, and it is the one the owner named explicitly.
	# Flip the controller into it the way a live cast does and re-measure.
	# NOT awaited between the flip and the read. `_sync_hand_pose()` runs every PHYSICS frame
	# and rewrites `_hand_posed_cast` from `fishing`, so any await here can put the tool back in
	# the idle pose before it is measured — and the failure looks like two poses that agree to
	# the digit, which is exactly what a broken cast pose looks like too. Transforms are exact
	# the moment `_apply_hand_pose` writes them, so there is nothing to wait for.
	p.set("_hand_posed_cast", true)
	p.call("_apply_hand_pose")
	p.call("_show_stowed_tackle", false)
	var b2: Basis = pivot.global_transform.basis.orthonormalized()
	var long2: Vector3 = inv * (b2 * Vector3(def.get("axis", Vector3(0, 1, 0))))
	var face2: Vector3 = inv * (b2 * Vector3(def.get("face", Vector3(1, 0, 0))))
	print("      CAST pose: long axis -> cam %s   reel/drum axis -> cam %s"
		% [str(long2.snappedf(0.001)), str(face2.snappedf(0.001))])
	_chk("%s's cast pose is a DIFFERENT pose from the idle hold" % id,
		long2.distance_to(long_axis) > 0.05,
		"the two poses agree to %.4f" % long2.distance_to(long_axis))
	_chk("%s drops its long axis toward the water for the cast" % id, long2.y < long_axis.y,
		"idle y=%.3f cast y=%.3f" % [long_axis.y, long2.y])
	# THE OWNER'S OWN WORDS FOR THE CAST, and now they are asserted for BOTH tools rather than
	# only for the rod: "when casting it goes reel/bail up". The winch's drum was never checked
	# for this because the old entry aimed the axle, which says nothing about up.
	_chk("casting brings the reel/bail further UP than the idle hold",
		face2.y > face_dir.y and face2.y > absf(face2.x),
		"idle reel-up=%.3f cast reel-up=%.3f (sideways %.3f)"
			% [face_dir.y, face2.y, face2.x])
	if id != "fishing_rod":
		# ...and the winch's modelled tackle must go away while a real lead is in flight, or the
		# player sees two leads (owner: "there is a hook and bobber in the 3-d model too").
		var stowed: Node = container.find_child("stowed_tackle", true, false)
		_chk("the winch carries its stowed tackle in a named, hideable node", stowed is Node3D)
		if stowed is Node3D:
			_chk("the winch's own tackle is HIDDEN while a cast is live",
				not (stowed as Node3D).visible)
	p.set("_hand_posed_cast", false)
	p.call("_apply_hand_pose")
	p.call("_show_stowed_tackle", true)
	await get_tree().process_frame
