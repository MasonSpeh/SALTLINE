extends Node
## FIXER repro: the freed-instance error spam that TestRunner structurally cannot see,
## because it never dismantles a structure.
##
## Before the fix this printed hundreds of:
##   ambience.gd:716  "Trying to assign invalid previously freed instance"  (every frame)
##   comfort_furniture.gd:317  `is` against a freed instance                (every 0.35s)
## Run: godot --headless --path . res://tests/FixerDismantleProbe.tscn

var _main: Node3D

func _ready() -> void:
	await _run()
	get_tree().quit(0)

func _run() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player:
		player.set_physics_process(false)
		player.set_process(false)
		player.global_position = Vector3(10.0, 19.5, -4.0)
	await get_tree().process_frame

	# Build the two kits the sway scanner and the comfort tick both latch onto: a
	# brazier becomes a Hearth proxy, a drying rack matches the "drying" sway name.
	var kits: Array[String] = ["brazier_kit", "drying_rack_kit", "bedroll_kit"]
	var built: Array[Node3D] = []
	for i in range(kits.size()):
		var n: Node3D = Structures.build(kits[i], false)
		get_tree().current_scene.add_child(n)
		n.global_position = Vector3(9.0 + float(i) * 1.6, 18.9, -4.0)
		built.append(n)
	print("built %d structures" % built.size())

	# Let ComfortFurniture attach its proxies and Ambience's 6s sweep find the rack.
	await get_tree().create_timer(4.0).timeout
	var sway_n: int = 0
	if Ambience and Ambience.get("_sway") != null:
		sway_n = (Ambience.get("_sway") as Array).size()
	print("before dismantle: sway targets=%d" % sway_n)

	# Exactly what BuildMode's [X] dismantle does to the node.
	print("---- DISMANTLE ----")
	for n in built:
		n.queue_free()
	# Ride out several comfort ticks (0.35s) and a full ambience rescan (6s). This is
	# the window that used to fill with hundreds of freed-instance errors.
	await get_tree().create_timer(4.0).timeout
	print("---- SURVIVED 4.0s AFTER DISMANTLE ----")
	var after: int = 0
	if Ambience and Ambience.get("_sway") != null:
		after = (Ambience.get("_sway") as Array).size()
	print("after dismantle: sway targets=%d" % after)

	# The sway scanner must find SOMETHING on this rig, or the wind-sway feature is
	# silently doing nothing because no prop happens to be named for it.
	if sway_n > 0:
		print("[OK] sway scanner found a non-zero set (%d)" % sway_n)
	else:
		print("[DEFECT] sway scanner matched nothing — wind sway is inert")
