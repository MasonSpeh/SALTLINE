extends Node
## THE CRAB TEST. The owner's complaint was "crabs don't seem to attack, and they stay around
## their base". The old code had a 2.5 m height gate on detection, so a player anywhere above
## the wet-deck plating (topside is y18) was 15 m outside it and the crab had no reason to
## leave its 8x15 m patrol ring. This probe puts the player TOPSIDE at night and watches
## whether the pack actually leaves the water, gains height, and closes.
const WARMUP := 6.0
const WATCH := 100.0
var _t := 0.0
var _next := 0.0
var _armed := false
var _player: Node3D
var _min_dist := 9999.0
var _max_y := -99.0
var _start_y := 0.0
var _states := {}
func _ready() -> void:
	add_child((load("res://scenes/Main.tscn") as PackedScene).instantiate())
func _crabs() -> Array:
	return get_tree().get_nodes_in_group("giant_crab")
func _kings() -> Array:
	return get_tree().get_nodes_in_group("king_crab")
func _process(d: float) -> void:
	_t += d
	if _t < WARMUP: return
	if not _armed:
		_armed = true
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			print("FAIL no player"); get_tree().quit(); return
		_player.set_physics_process(false)
		_player.set_process(false)
		# Stand on the OPEN TOPSIDE DECK, clear of any powered light pool (the old code also
		# treated a lit zone as total amnesia, which made topside crab-proof).
		_player.global_position = Vector3(-24.0, 19.0, -2.0)
		GameClock.force_phase(GameClock.Phase.NIGHT)
		var ys: Array = []
		for c in _crabs(): ys.append(round((c as Node3D).global_position.y * 10) / 10.0)
		_start_y = ys.max() if not ys.is_empty() else 0.0
		print("[crab] player topside at %s | pack=%d kings=%d | crab y at night-fall: %s"
			% [str(_player.global_position), _crabs().size(), _kings().size(), str(ys)])
		return
	if _t < _next: return
	_next = _t + 5.0
	var line := ""
	for c in _crabs() + _kings():
		if not is_instance_valid(c): continue
		var n: Node3D = c
		var dist: float = n.global_position.distance_to(_player.global_position)
		_min_dist = minf(_min_dist, dist)
		_max_y = maxf(_max_y, n.global_position.y)
		var st: Variant = n.get("state")
		if st == null: st = n.get("_state")
		_states[str(st)] = true
		line += " [y%5.1f d%5.1f s%s]" % [n.global_position.y, dist, str(st)]
	print("t=%5.1f%s" % [_t, line])
	if _t > WARMUP + WATCH:
		print("\n=== RESULT ===")
		print("  highest crab y reached : %.1f  (started %.1f; topside deck is y18)" % [_max_y, _start_y])
		print("  closest approach       : %.1f m" % _min_dist)
		print("  states seen            : %s" % str(_states.keys()))
		var climbed: bool = _max_y > 10.0
		var closed: bool = _min_dist < 6.0
		print("  %s left the water and gained real height" % ("PASS" if climbed else "FAIL"))
		print("  %s closed on the player" % ("PASS" if closed else "FAIL"))
		get_tree().quit()
