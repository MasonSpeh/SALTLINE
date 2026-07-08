extends Node
## Cheat keys for tuning (GDD §7): F1 advance phase, F2 toggle power, F3 infinite stats,
## F4 teleport up a layer, F5 teleport to wet deck. Debug builds only.

@export var topside_circuit_id: String = "topside_floodlights"
@export var infinite_stats: bool = false

func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var player: Node3D = get_tree().get_first_node_in_group("player")
	match event.keycode:
		KEY_F1:
			GameClock.force_phase(((GameClock.current_phase + 1) % (GameClock.Phase.NIGHT + 1)) as GameClock.Phase)
			print("DEBUG: phase -> ", GameClock.Phase.keys()[GameClock.current_phase])
		KEY_F2:
			if PowerGrid.is_powered(topside_circuit_id):
				PowerGrid.lose_circuit(topside_circuit_id)
			else:
				PowerGrid.power_circuit(topside_circuit_id)
			print("DEBUG: power = ", PowerGrid.is_powered(topside_circuit_id))
		KEY_F3:
			infinite_stats = not infinite_stats
			print("DEBUG: infinite_stats = ", infinite_stats)
		KEY_F4:
			if player:
				player.global_position = Vector3(0, 20.5, 0)
				print("DEBUG: teleport topside")
		KEY_F5:
			if player:
				player.global_position = Vector3(20, 3.5, -8)
				print("DEBUG: teleport wet deck")
		KEY_F6:
			GameClock.time_scale = 20.0 if GameClock.time_scale == 1.0 else 1.0
			print("DEBUG: time_scale = ", GameClock.time_scale)

func _process(_delta: float) -> void:
	if infinite_stats:
		PlayerState.hunger = 1.0
		PlayerState.warmth = 1.0
