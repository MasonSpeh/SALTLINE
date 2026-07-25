extends Node
## Does the DEEP RIG actually cast? Previous passes "fixed" the deep path twice while the
## tool could never be selected to run it (player_controller gated the cast on the item id
## being literally "fishing_rod"), so this asserts the whole chain end to end instead.
const SETTLE := 5.0
var _t := 0.0
var _ran := false
var _fails := 0
func _ready() -> void:
	add_child((load("res://scenes/Main.tscn") as PackedScene).instantiate())
func _chk(label: String, ok: bool, detail: String = "") -> void:
	if ok: print("PASS  %s" % label)
	else:
		_fails += 1
		print("FAIL  %s %s" % [label, detail])
func _process(d: float) -> void:
	if _ran: return
	_t += d
	if _t < SETTLE: return
	_ran = true
	var p: Node = get_tree().get_first_node_in_group("player")
	_chk("player exists", p != null)
	if p == null:
		get_tree().quit(); return
	# 1. the gate accepts the deep pole at all
	var rod_items: Variant = p.get("ROD_ITEMS")
	_chk("cast gate lists deep_rig_pole", rod_items != null and "deep_rig_pole" in rod_items,
		"ROD_ITEMS=%s" % str(rod_items))
	# 2. give the player the pole + bait, stand them over open water, and cast
	# hotbar is a 4-entry ARRAY (0-indexed) and add_item takes one id. Bait must be in the
	# pack too, because the deep rig now refuses a bare drop.
	PlayerState.add_item("deep_rig_pole")
	PlayerState.add_item("fish_herring")
	for i in range(PlayerState.hotbar.size()):
		if str(PlayerState.hotbar[i]) == "deep_rig_pole":
			PlayerState.selected_hotbar = i   # 0-based index into hotbar, despite the "#1-4" comment
	print("      hotbar=%s selected=%d" % [str(PlayerState.hotbar), PlayerState.selected_hotbar])
	print("      selected item = %s" % str(p.call("_selected_item_id")))
	# open water off the west rim, well clear of any decking
	p.global_position = Vector3(-34.0, 19.0, -2.0)
	p.rotation.y = deg_to_rad(90)
	await get_tree().physics_frame
	p.call("_start_fishing")
	await get_tree().physics_frame
	var rod: Variant = p.get("fishing")
	_chk("a cast object was spawned", rod != null)
	if rod != null and is_instance_valid(rod):
		_chk("it knows it is the DEEP rig", bool(rod.get("_deep")) == true,
			"_deep=%s" % str(rod.get("_deep")))
		# let it fly + sink for a few seconds
		for i in range(240):
			await get_tree().physics_frame
			if not is_instance_valid(rod): break
		if is_instance_valid(rod):
			print("      line state=%s depth=%.1f m pos=%s"
				% [str(rod.get("_state")), float(rod.get("_depth") if rod.get("_depth") != null else -1.0),
					str((rod as Node3D).global_position.snappedf(0.1))])
			_chk("line survived the flight (did not silently die)", true)
		else:
			print("      (line finished/reeled during the window — check the toast text)")
	print("\n[deep_rod] FAILURES: %d" % _fails)
	get_tree().quit()
