class_name InteractionRay extends RayCast3D
## Player's single interaction driver (GDD A4): raycast from camera, one context prompt,
## primary-verb dispatch on the interact action. Created by the player controller in code.

const REACH: float = 2.6

var _current: Node3D = null   # Interactable or PhysProp

func _ready() -> void:
	target_position = Vector3(0, 0, -REACH)
	collide_with_areas = false
	collide_with_bodies = true

func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player")

func _physics_process(_delta: float) -> void:
	var player: Node3D = _player()
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if player and (player.carried or player.ui_locked or (player.build and player.build.active)):
		# Carrying, in a panel, or building — someone else owns the prompt.
		_current = null
		return
	if player and player.get("fishing") != null and player.fishing != null:
		# A cast is out — the rod owns the prompt and the mouse. No grabbing
		# props mid-fight, no prompt chip fighting over the strike banner.
		_current = null
		return
	var hit: Object = get_collider() if is_colliding() else null
	var next: Node3D = null
	if hit is Interactable and not (hit as Interactable).available_verbs().is_empty():
		next = hit
	elif hit is PhysProp and (hit as PhysProp).held_by == null:
		next = hit
	if next != _current:
		_current = next
		if hud:
			hud.show_prompt(_current.get_prompt() if _current else "")

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or _current == null:
		return
	var player: Node3D = _player()
	if player and (player.carried or player.ui_locked or (player.build and player.build.active)
			or (player.get("fishing") != null and player.fishing != null)):
		return
	if _current is Interactable:
		var v: Array[String] = (_current as Interactable).available_verbs()
		if not v.is_empty():
			(_current as Interactable).interact(v[0], player)
	elif _current is PhysProp and player:
		player.try_grab(_current)
	# Consume this interact press. Otherwise the SAME event propagates to
	# player_controller._unhandled_input, whose "carrying: [E] sets down" branch
	# fires on the prop we just grabbed (carried is now set) — grab + instant drop,
	# so nothing appears to happen. While carrying, _physics_process forces _current
	# null, so this never eats the intended set-down press.
	get_viewport().set_input_as_handled()
	# State may have changed; refresh prompt next frame.
	_current = null
