class_name BreakerPanel extends Interactable
## OPERATE verb: master breaker for a circuit. Requires its CableSegment to be spliced
## first — then powers the circuit through PowerGrid (the slice's midpoint victory).

@export var circuit_id: String = "topside_floodlights"

var _cable: CableSegment = null

func _init() -> void:
	verbs = ["OPERATE"] as Array[String]

func set_cable(c: CableSegment) -> void:
	_cable = c

func available_verbs() -> Array[String]:
	var out: Array[String] = []
	if not PowerGrid.is_powered(circuit_id):
		out.append("OPERATE")
	return out

func interact(verb: String, player: Node3D) -> void:
	super(verb, player)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if _cable and not _cable.connected:
		if hud:
			hud.toast("Dead. The feed line is burned out somewhere down the corridor.")
		return
	PowerGrid.power_circuit(circuit_id)
	if hud:
		hud.toast("Breaker closed. Somewhere above, something hums awake.")
	AudioDirector.play_one_shot("breaker", global_position)
