class_name LightSwitch extends Interactable
## OPERATE verb: room light switch. Dead until its circuit is powered — power is
## spatial and felt (canon): restoring the breaker makes every switch on the line live.

@export var circuit_id: String = "topside_floodlights"

var is_on: bool = false
var _lights: Array[Light3D] = []

func _init() -> void:
	verbs = ["OPERATE"]
	display_name = "Light Switch"

func add_light(l: Light3D) -> void:
	# Parented to the rig, referenced here — placed next to fixtures, not the switch.
	_lights.append(l)
	l.visible = false

func interact(verb: String, player: Node3D) -> void:
	super(verb, player)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if not PowerGrid.is_powered(circuit_id):
		if hud:
			hud.toast("Dead. Nothing hums behind this wall.")
		return
	is_on = not is_on
	for l in _lights:
		l.visible = is_on
	AudioDirector.play_one_shot("breaker", global_position, -8.0)
