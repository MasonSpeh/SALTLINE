class_name InteractionRay extends RayCast3D
## Player's single interaction driver (GDD A4): raycast from camera, one context prompt,
## primary-verb dispatch on the interact action. Created by the player controller in code.

const REACH: float = 2.6

var _current: Interactable = null

func _ready() -> void:
	target_position = Vector3(0, 0, -REACH)
	collide_with_areas = false
	collide_with_bodies = true

func _physics_process(_delta: float) -> void:
	var hit: Object = get_collider() if is_colliding() else null
	var next: Interactable = hit as Interactable
	if next != null and next.available_verbs().is_empty():
		next = null
	if next != _current:
		_current = next
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.show_prompt(_current.get_prompt() if _current else "")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _current:
		var v: Array[String] = _current.available_verbs()
		if not v.is_empty():
			_current.interact(v[0], get_tree().get_first_node_in_group("player"))
			# State may have changed; refresh prompt next frame.
			_current = null
