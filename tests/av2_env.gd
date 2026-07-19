extends Node
## AV2 pass 3 — item 13: do the sea spray and the indoor motes actually EMIT
## where they are supposed to, and does the sway respond to weather?
## Run: godot --headless --path . res://tests/AV2Env.tscn

var _main: Node3D
var _player: Node3D

func _ready() -> void:
	await _run()
	get_tree().quit(0)

func _p(t: String, m: String) -> void:
	print("%-9s %s" % [t, m])

func _run() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().create_timer(3.0).timeout
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.set_physics_process(false)
		_player.set_process(false)
	var amb: Node = get_node_or_null("/root/Ambience")
	if amb == null:
		_p("[DEFECT]", "no Ambience autoload")
		return
	var spray = amb.get("_spray")
	var motes = amb.get("_motes")
	if spray == null:
		_p("[DEFECT]", "no sea-spray emitter built")
	if motes == null:
		_p("[DEFECT]", "no indoor-mote emitter built")

	# --- sea spray: down by the waterline vs high on the topside deck ---
	var storm: Node = null
	for c in _main.get_children():
		if c is StormSystem:
			storm = c
	_player.global_position = Vector3(16.0, 2.6, -20.0)   # wet deck, near the water
	for i in 10:
		await get_tree().physics_frame
	await get_tree().create_timer(1.0).timeout
	var low_on: bool = spray != null and bool(spray.emitting)
	var low_ratio: float = float(spray.amount_ratio) if spray else 0.0
	_player.global_position = Vector3(12.0, 26.0, 8.0)    # high topside
	for i in 10:
		await get_tree().physics_frame
	await get_tree().create_timer(1.0).timeout
	var high_on: bool = spray != null and bool(spray.emitting)
	var high_ratio: float = float(spray.amount_ratio) if spray else 0.0
	_p("[INFO]", "spray: waterline emitting=%s ratio=%.3f | topside emitting=%s ratio=%.3f"
		% [low_on, low_ratio, high_on, high_ratio])
	if low_on and low_ratio > high_ratio:
		_p("[OK]", "sea spray emits near the waterline and thins out with height")
	else:
		_p("[DEFECT]", "sea spray does not key off height as intended")
	# and it should thicken in a storm
	if storm:
		storm.set("_intensity", 1.0)
		storm.set("_phase", 2)
		_player.global_position = Vector3(16.0, 2.6, -20.0)
		for i in 10:
			await get_tree().physics_frame
		await get_tree().create_timer(1.2).timeout
		var storm_ratio: float = float(spray.amount_ratio) if spray else 0.0
		if storm_ratio > low_ratio:
			_p("[OK]", "spray thickens in a storm (%.3f -> %.3f)" % [low_ratio, storm_ratio])
		else:
			_p("[DEFECT]", "spray ignores the storm (%.3f -> %.3f)" % [low_ratio, storm_ratio])
		storm.set("_intensity", 0.0)
		storm.set("_phase", 0)

	# --- indoor motes: deep inside the rec room vs out on open deck ---
	_player.global_position = Vector3(20.0, 19.6, 11.0)   # inside the rec room
	for i in 12:
		await get_tree().physics_frame
	await get_tree().create_timer(1.2).timeout
	var in_on: bool = motes != null and bool(motes.emitting)
	var in_cover: float = float(amb.get("_cover"))
	_player.global_position = Vector3(-10.0, 19.0, -25.0) # open deck, nothing overhead
	for i in 12:
		await get_tree().physics_frame
	await get_tree().create_timer(1.2).timeout
	var out_on: bool = motes != null and bool(motes.emitting)
	var out_cover: float = float(amb.get("_cover"))
	_p("[INFO]", "motes: indoor emitting=%s cover=%.2f | outdoor emitting=%s cover=%.2f"
		% [in_on, in_cover, out_on, out_cover])
	if in_on and not out_on:
		_p("[OK]", "indoor motes appear inside and stop outdoors")
	elif in_on and out_on:
		_p("[DEFECT]", "motes emit outdoors too — not an indoor effect")
	else:
		_p("[DEFECT]", "indoor motes never emit even under a roof (cover=%.2f)" % in_cover)
