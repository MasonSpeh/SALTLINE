extends Node
## AV2 pass 2 — corrects three false positives from av2_probe and adds the
## reachability repro for the two SCRIPT ERROR sites it uncovered.
## Run: godot --headless --path . res://tests/AV2Focus.tscn

var _main: Node3D
var _player: Node3D

func _ready() -> void:
	await _run()
	get_tree().quit(0)

func _p(tag: String, m: String) -> void:
	print("%-9s %s" % [tag, m])

func _all(root: Node, type) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if is_instance_of(n, type):
			out.append(n)
	return out

func _clear_pack() -> void:
	for i in range(PlayerState.HOTBAR_SIZE):
		PlayerState.hotbar[i] = null
	PlayerState.inventory.clear()

func _run() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().create_timer(2.5).timeout
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.set_physics_process(false)
		_player.set_process(false)
	PlayerState.set_depleting(false)

	await _salvage_real_prop()
	await _harvest_standing_close()
	await _placement_over_water()
	await _reachability_repro()

# ---- 1: salvage a REAL rig prop, standing next to it (Salvage.NEAR_M = 4) ----
func _salvage_real_prop() -> void:
	print("\n---- SALVAGE (real prop, player in reach) ----")
	var target: Salvage = null
	for s in get_tree().get_nodes_in_group("salvageable"):
		var sv := s as Salvage
		if sv == null or sv.regrow_sec > 0.0 or sv.required_tools.is_empty():
			continue
		if _all(sv, MeshInstance3D).size() >= 3:
			target = sv
			break
	if target == null:
		_p("[DEFECT]", "no multi-mesh tool-gated rig prop found to dismantle")
		return
	_clear_pack()
	_player.global_position = target.global_position + Vector3(0, 0.5, 1.0)
	# --- no tool ---
	var v: Array[String] = target.available_verbs()
	if v.size() == 1 and v[0] == "LOOK":
		_p("[OK]", "%s without the tool offers only LOOK (wants %s)" % [target.display_name, target.required_tools])
	else:
		_p("[DEFECT]", "%s offered %s with no tool" % [target.display_name, v])
	target.interact("LOOK", _player)
	await get_tree().create_timer(0.4).timeout
	if target.spent:
		_p("[DEFECT]", "toolless interaction still stripped the prop")
	else:
		_p("[OK]", "no tool = no yield")
	# --- with the tool ---
	PlayerState.add_item(String(target.required_tools[0]))
	var meshes: Array = _all(target, MeshInstance3D)
	var vis_before: int = 0
	for m in meshes:
		if (m as MeshInstance3D).visible: vis_before += 1
	target.interact(target.verb, _player)
	await get_tree().create_timer(target.work_sec + 2.0).timeout
	if not target.spent:
		_p("[DEFECT]", "%s never completed its work cycle in reach" % target.display_name)
		return
	_p("[OK]", "%s (%s) dismantles with %s" % [target.display_name, target.verb, target.required_tools])
	var missing: Array = []
	for id in target.yields:
		if not PlayerState.has_item(id):
			missing.append(id)
	if missing.is_empty():
		_p("[OK]", "yields landed in the pack: %s" % target.yields)
	else:
		_p("[DEFECT]", "missing yields: %s" % [missing])
	var vis_after: int = 0
	var sooted: int = 0
	for m in meshes:
		if (m as MeshInstance3D).visible: vis_after += 1
		if (m as MeshInstance3D).material_overlay != null: sooted += 1
	if vis_before - vis_after > 0 or sooted > 0:
		_p("[OK]", "visible wound: %d/%d parts pulled off, %d sooted"
			% [vis_before - vis_after, vis_before, sooted])
	else:
		_p("[DEFECT]", "prop looks identical after salvage")
	if target.is_in_group("salvaged"):
		_p("[OK]", "stripped prop joins group 'salvaged' and renames to '%s'" % target.display_name)
	else:
		_p("[DEFECT]", "stripped prop not in group 'salvaged'")
	if target.available_verbs().is_empty():
		_p("[OK]", "a spent prop is silent (no repeat farming)")
	else:
		_p("[DEFECT]", "spent prop still offers %s" % [target.available_verbs()])
	_clear_pack()

# ---- 2: harvest a renewable node from close range, then watch it regrow ----
func _harvest_standing_close() -> void:
	print("\n---- HARVEST (in reach) + REGROW ----")
	var node: Salvage = null
	for s in get_tree().get_nodes_in_group("salvageable"):
		var sv := s as Salvage
		if sv and sv.regrow_sec > 0.0 and sv.yields.has("kelp_bundle"):
			node = sv
			break
	if node == null:
		_p("[DEFECT]", "no kelp harvest node found")
		return
	_clear_pack()
	_player.global_position = node.global_position + Vector3(0, 0.5, 0.8)
	node.interact(node.verb, _player)
	await get_tree().create_timer(node.work_sec + 2.0).timeout
	if not node.spent:
		_p("[DEFECT]", "kelp harvest never completed in reach")
		return
	_p("[OK]", "kelp harvest completes (%s), yielded=%s" % [node.verb, PlayerState.has_item("kelp_bundle")])
	node._regrow_left = 0.2
	await get_tree().create_timer(0.8).timeout
	if node.spent:
		_p("[DEFECT]", "renewable node never regrew after its timer elapsed")
	else:
		_p("[OK]", "renewable node regrows and leaves group 'salvaged' (%s)"
			% (not node.is_in_group("salvaged")))
	_clear_pack()

# ---- 3: placement validity aimed OUT TO SEA (no deck under the aim point) ----
func _placement_over_water() -> void:
	print("\n---- BUILD MODE placement over open water ----")
	var bm: Node = null
	for n in _all(_main, Node):
		if n is BuildMode:
			bm = n
			break
	if bm == null:
		_p("[DEFECT]", "no BuildMode in the scene")
		return
	_clear_pack()
	PlayerState.add_item("chair_kit")
	bm.call("toggle")
	var cam: Camera3D = _player.get("camera") as Camera3D
	# Stand at the seaward lip of the wet deck, look straight out over the water.
	_player.global_position = Vector3(20.0, 3.0, -21.0)
	cam.global_position = Vector3(20.0, 3.6, -21.0)
	cam.look_at(Vector3(20.0, 2.4, -60.0), Vector3.UP)
	for i in 15:
		await get_tree().physics_frame
	if bool(bm.get("_valid")):
		_p("[DEFECT]", "aiming at open sea reads VALID at %s (would place a chair on the water)"
			% bm.get("_place_pos"))
	else:
		_p("[OK]", "aiming at open sea reads invalid — no footing there")
	# straight down at the deck for contrast
	cam.look_at(Vector3(20.2, 2.0, -20.5), Vector3.UP)
	for i in 15:
		await get_tree().physics_frame
	if bool(bm.get("_valid")):
		_p("[OK]", "aiming back at the deck reads valid again")
	else:
		_p("[DEFECT]", "aiming at real deck reads invalid")
	bm.call("exit")
	_clear_pack()

# ---- 4: is the error spam reachable by NORMAL PLAY? build then dismantle ----
func _reachability_repro() -> void:
	print("\n---- REACHABILITY: build then dismantle a brazier + drying rack ----")
	var bm: Node = null
	for n in _all(_main, Node):
		if n is BuildMode:
			bm = n
			break
	_clear_pack()
	# Put both structures down by hand at a real deck spot, let comfort attach + let
	# ambience pick up the drying line, then take them apart the way [X] does.
	var spot: Vector3 = Vector3(16.0, 2.05, -12.0)
	var fire: Node3D = Structures.build("brazier_kit", false)
	_main.add_child(fire); fire.global_position = spot
	var rack: Node3D = Structures.build("drying_rack_kit", false)
	_main.add_child(rack); rack.global_position = spot + Vector3(2.0, 0, 0)
	_player.global_position = spot + Vector3(0, 0.5, 1.5)
	# comfort scan is 1.5s; ambience sway rescan is 6s — wait past both
	await get_tree().create_timer(8.0).timeout
	var amb: Node = get_node_or_null("/root/Ambience")
	var sway_n: int = (amb.get("_sway") as Array).size() if amb else -1
	_p("[INFO]", "before dismantle: sway targets=%d" % sway_n)
	print(">>> MARK_DISMANTLE")
	# Exactly what BuildMode.dismantle() does to the node.
	fire.queue_free()
	rack.queue_free()
	await get_tree().create_timer(5.0).timeout
	print(">>> MARK_END")
	_p("[INFO]", "5s of normal running after dismantling two placed structures")
