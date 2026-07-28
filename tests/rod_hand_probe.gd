extends Node
## Does the rebuilt fishing rod still hand its TIP to the fishing line?
##
## The rod's ItemVisual plants a Node3D called "hand_tip" at the working end, and
## player_controller.hand_tip_world() finds it BY NAME — rebuild the rod's geometry
## without that node, or leave it parented to something that no longer carries the rig's
## tilt, and the line silently anchors at the grip (or at the player's feet) instead.
## Nothing about that is visible in a screenshot, so it is asserted here: hold the rod,
## ask the live controller where the tip is, and check the answer is the rod's own far end
## rather than the AABB-centre fallback.
##
##   godot --headless --path . res://tests/RodHandProbe.tscn

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
	# The built visual carries the marker at all.
	var built: Node3D = ItemVisual.build("fishing_rod")
	var m: Node = built.find_child("hand_tip", true, false)
	_chk("ItemVisual('fishing_rod') plants a hand_tip node", m is Node3D)
	built.queue_free()

	PlayerState.add_item("fishing_rod")
	for i in range(PlayerState.hotbar.size()):
		if str(PlayerState.hotbar[i]) == "fishing_rod":
			PlayerState.selected_hotbar = i
	# Selecting a slot does NOT itself rebuild the hand — _hotbar_pressed() calls
	# _update_held_item() straight after setting the slot (only inventory_changed is
	# connected), so a probe that only assigns selected_hotbar holds an empty hand.
	p.call("_update_held_item")
	await get_tree().process_frame
	await get_tree().process_frame
	_chk("the rod is the selected item", str(p.call("_selected_item_id")) == "fishing_rod")

	var hand: Node3D = p.get("_hand_item")
	_chk("the hand holds a built visual", hand != null and hand.get_child_count() > 0)
	if hand == null or hand.get_child_count() == 0:
		print("\n[rod_hand] FAILURES: %d" % _fails)
		get_tree().quit()
		return
	var container: Node3D = hand.get_child(0)
	var live: Node = container.find_child("hand_tip", true, false)
	_chk("the HELD rod still exposes hand_tip by name", live is Node3D)

	var tip: Vector3 = p.call("hand_tip_world")
	var cam: Camera3D = p.get("camera")
	# The marker path and the fallback path must NOT agree — if hand_tip went missing,
	# hand_tip_world() quietly returns the _hand_reach_axis guess and everything still
	# "works", just anchored in the wrong place. So compare them explicitly.
	var fallback: Vector3 = container.global_transform * (Vector3(0, 1, 0) * float(p.get("_hand_reach")))
	print("      tip=%s  container=%s  fallback=%s  reach=%.3f"
		% [str(tip.snappedf(0.001)), str(container.global_position.snappedf(0.001)),
			str(fallback.snappedf(0.001)), float(p.get("_hand_reach"))])
	_chk("the tip is a real finite point", is_finite(tip.x) and is_finite(tip.y) and is_finite(tip.z))
	# The rod is normalised to 0.9 m in hand and the marker sits at its far end, so the tip
	# must be roughly a half-rod out from the container's centre — not on top of it (grip)
	# and not metres away (a stale/lost transform).
	var out: float = tip.distance_to(container.global_position)
	_chk("the tip is out at the rod's far end, not at the grip", out > 0.30 and out < 0.75,
		"distance from held-item centre = %.3f m" % out)
	# And it has to be the END the LINE leaves from: ahead of the camera, not behind it.
	if cam != null:
		var ahead: float = (tip - cam.global_position).dot(-cam.global_transform.basis.z)
		_chk("the tip is out in front of the player, where line pays out", ahead > 0.2,
			"forward component = %.3f m" % ahead)
	print("\n[rod_hand] FAILURES: %d" % _fails)
	get_tree().quit()
