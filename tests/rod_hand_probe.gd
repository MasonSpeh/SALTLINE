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
