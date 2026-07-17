class_name InteractDoor extends Interactable
## OPEN verb: swings 100 degrees around own origin (place origin at hinge edge).
## locked doors show no prompt until unlock() is called (SPHL hatch, machine shop).

@export var locked: bool = false

var is_open: bool = false
var _busy: bool = false

func _init() -> void:
	verbs = ["OPEN"] as Array[String]

func available_verbs() -> Array[String]:
	var out: Array[String] = []
	if locked or _busy:
		return out
	out.append("CLOSE" if is_open else "OPEN")
	return out

func unlock() -> void:
	locked = false

func interact(verb: String, player: Node3D) -> void:
	super(verb, player)
	_busy = true
	is_open = not is_open
	# An open door must never block the doorway — drop its collision while open so
	# the swung panel can't catch the player on the way through.
	_set_collision(not is_open)
	var target_y: float = deg_to_rad(-100.0) if is_open else 0.0
	var tw: Tween = create_tween()
	tw.tween_property(self, "rotation:y", target_y, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: _busy = false)
	AudioDirector.play_one_shot("hatch", global_position)

func _set_collision(enabled: bool) -> void:
	for c in get_children():
		if c is CollisionShape3D:
			c.disabled = not enabled
