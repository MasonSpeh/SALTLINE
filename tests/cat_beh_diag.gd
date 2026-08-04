extends Node
## A STATE TRACE for the ship's cat — what it is doing, once a second, while a scenario runs.
##
## CatProbe asserts; this one narrates. It exists because "when the player sleeps, the cat
## curls up" came back FAIL with the cat wearing the walk pose two metres from the bed, and no
## assertion in the suite can say WHY a cat is walking. The trace prints the state, the pose,
## the held sleep target, the distance left to it and whether the movement code is refusing
## its step — which turns "it did not lie down" into a line you can point at.
##
##   godot --headless --path . res://tests/CatBehDiag.tscn

var _cat: Node3D
var _player: Node3D

func _ready() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(6.0).timeout
	for i in range(10):
		await get_tree().physics_frame
	_cat = get_tree().get_first_node_in_group("ship_cat")
	_player = get_tree().get_first_node_in_group("player")
	if _cat == null or _player == null:
		print("no cat / no player")
		get_tree().quit(1)
		return
	_player.set_physics_process(false)
	_player.set_process(false)
	for c in _cat.get_children():
		if c is Interactable:
			(c as Interactable).interact("SAY HELLO", _player)

	# ---- scenario 1: the player turns in, in the bunkhouse, exactly as CatProbe does it.
	_player.set("_lying", false)
	_player.set("_lying_sleeping", false)
	PlayerState.selected_hotbar = -1
	_player.global_position = Vector3(-22.0, 18.1, 12.0)
	for i in range(30):
		await get_tree().physics_frame
	print("\n=== the player lies down at %s; cat at %s ==="
		% [str(_player.global_position.snappedf(0.1)), str(_cat.global_position.snappedf(0.1))])
	_player.set("_lying", true)
	_player.set("_lying_sleeping", true)
	await _trace(20, "sleep")

	# ---- scenario 2: awake, out on the open deck, where the gulls are.
	_player.set("_lying", false)
	_player.set("_lying_sleeping", false)
	_cat.global_position = Vector3(0.5, 18.0, 4.0)
	if _cat.has_method("_reseat"):
		_cat.call("_reseat")
	_player.global_position = Vector3(1.5, 18.1, 4.0)
	for i in range(20):
		await get_tree().physics_frame
	print("\n=== awake on the main deck near the gulls ===")
	var gulls: Array = get_tree().get_nodes_in_group("deck_gull")
	print("  deck gulls in the group: %d" % gulls.size())
	for g in gulls:
		print("    at %s  flushing=%.2f" % [str((g as Node3D).global_position.snappedf(0.1)),
			float((g as Node3D).get("_flushing"))])
	await _trace(45, "hunt")
	get_tree().quit()

func _trace(seconds: int, tag: String) -> void:
	var names := ["GROOM", "FOLLOW", "RUN", "SIT", "SLEEP", "FISH", "PET", "JUMP",
		"STALK", "POUNCE", "GIFT", "PLAY", "PERCH", "STRETCH"]
	var seen := {}
	for s in range(seconds):
		for i in range(30):
			await get_tree().physics_frame
		var st: int = int(_cat.get("_state"))
		seen[st] = true
		var tgt: Vector3 = _cat.get("_sleep_target")
		print("[%s %2ds] %-7s pose=%-6s pos=%s  d_player=%.2f  sleep_tgt=%s d=%.2f  hunt=%d cd=%.1f zoom=%.1f/%.1f play=%.1f/%.1f carry=%s"
			% [tag, s, names[st] if st < names.size() else str(st), str(_cat.get("_pose")),
				str(_cat.global_position.snappedf(0.1)),
				_cat.global_position.distance_to(_player.global_position),
				("none" if tgt == Vector3.ZERO else str(tgt.snappedf(0.1))),
				(0.0 if tgt == Vector3.ZERO else _cat.global_position.distance_to(tgt)),
				int(_cat.get("_hunt")), float(_cat.get("_hunt_cd")),
				float(_cat.get("_zoom_t")), float(_cat.get("_zoom_cd")),
				float(_cat.get("_play_t")), float(_cat.get("_play_cd")),
				str(_cat.get("_carry"))])
	var got: Array = []
	for k in seen:
		got.append(names[int(k)] if int(k) < names.size() else str(k))
	print("[%s] states visited: %s" % [tag, str(got)])
