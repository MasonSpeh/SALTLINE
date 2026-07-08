class_name LamplightCrab extends Node3D
## The night threat (GDD 5.5): one dog-sized crab, simple FSM on authored waypoints.
## Avoids powered LightZones; pursues the player in darkness within detect radius;
## contact = blackout + wake at dawn in the SPHL (handled by Main via EventBus).
## Its audio is the real design — claw-steps audible through decks, long before sight.

enum State { PATROL_Z1, ASCEND, PATROL_TOP, PURSUE, RETREAT, GONE }

var z1_loop: Array = []
var ascend_path: Array = []
var z4_loop: Array = []
var exit_point: Vector3

var state: State = State.PATROL_Z1
var _wp_index: int = 0
var _resume_state: State = State.PATROL_Z1
var patrol_speed: float = 1.6
var pursue_speed: float = 3.8
var detect_radius: float = 6.0
var contact_radius: float = 1.2
var _contact_fired: bool = false
var _claw_timer: Timer

func _ready() -> void:
	patrol_speed = PlayerState.tuning.get("crab_patrol_speed", 1.6)
	pursue_speed = PlayerState.tuning.get("crab_pursue_speed", 3.8)
	detect_radius = PlayerState.tuning.get("crab_detect_radius", 6.0)
	contact_radius = PlayerState.tuning.get("crab_contact_radius", 1.2)
	_build_body()
	_claw_timer = AudioDirector.attach_loop("claw", self, 0.5)
	GameClock.dawn.connect(_on_dawn)

func _build_body() -> void:
	# Capsule + legs placeholder, faint teal lamplight spots (Bloom canon: adapted, not corrupted).
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.1
	cap.material = MatLib.flat(Color(0.2, 0.16, 0.14))
	body.mesh = cap
	add_child(body)
	body.rotation.z = deg_to_rad(90)
	body.position.y = 0.4
	for i in range(6):
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.08, 0.6, 0.08)
		lm.material = MatLib.flat(Color(0.15, 0.12, 0.1))
		leg.mesh = lm
		add_child(leg)
		var side: float = 1.0 if i % 2 == 0 else -1.0
		leg.position = Vector3(-0.4 + (i / 2) * 0.4, 0.25, side * 0.4)
		leg.rotation.x = side * deg_to_rad(30)
	for i in range(4):
		var spot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		sm.material = MatLib.flat(Color(0.2, 0.9, 0.85), true, 2.0)
		spot.mesh = sm
		add_child(spot)
		spot.position = Vector3(-0.3 + i * 0.2, 0.62, 0.1 * (1 if i % 2 == 0 else -1))

func _process(delta: float) -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	match state:
		State.GONE:
			return
		State.RETREAT:
			_retreat(delta)
			return
		State.PURSUE:
			_pursue(delta, player)
			return
		_:
			pass
	# Detection: darkness only, same layer-ish height, never into powered light.
	if player and GameClock.current_phase == GameClock.Phase.NIGHT:
		var d: float = global_position.distance_to(player.global_position)
		if d < detect_radius \
				and absf(player.global_position.y - global_position.y) < 2.5 \
				and not LightZone.point_is_safe(get_tree(), player.global_position):
			_resume_state = state
			state = State.PURSUE
			return
	# Patrol schedule ascends over the night (GDD 5.5).
	var f: float = GameClock.phase_fraction()
	match state:
		State.PATROL_Z1:
			_follow_loop(z1_loop, delta)
			if f > 0.35:
				state = State.ASCEND
				_wp_index = 0
		State.ASCEND:
			if _follow_path(ascend_path, delta):
				# Topside reached: patrol it only if it is dark territory (Rule 7).
				if LightZone.point_is_safe(get_tree(), z4_loop[0]):
					state = State.ASCEND    # loiter on the stairs — light holds the deck
					_wp_index = maxi(ascend_path.size() - 4, 0)
				else:
					state = State.PATROL_TOP
					_wp_index = 0
		State.PATROL_TOP:
			_follow_loop(z4_loop, delta)

func _follow_loop(loop: Array, delta: float) -> void:
	if loop.is_empty():
		return
	var target: Vector3 = loop[_wp_index % loop.size()]
	if _step_toward(target, patrol_speed, delta):
		_wp_index = (_wp_index + 1) % loop.size()

func _follow_path(path: Array, delta: float) -> bool:
	if _wp_index >= path.size():
		return true
	if _step_toward(path[_wp_index], patrol_speed, delta):
		_wp_index += 1
	return _wp_index >= path.size()

func _step_toward(target: Vector3, speed: float, delta: float) -> bool:
	var to_target: Vector3 = target - global_position
	if to_target.length() < 0.25:
		return true
	var step: Vector3 = to_target.normalized() * speed * delta
	global_position += step
	if to_target.length_squared() > 0.04:
		look_at(Vector3(target.x, global_position.y, target.z), Vector3.UP)
	return false

func _pursue(delta: float, player: Node3D) -> void:
	if player == null or GameClock.current_phase != GameClock.Phase.NIGHT:
		state = _resume_state
		return
	var p: Vector3 = player.global_position
	# It cannot enter powered light. It never attacks in light. (Canon.)
	if LightZone.point_is_safe(get_tree(), p) or global_position.distance_to(p) > detect_radius * 2.0:
		state = _resume_state
		return
	var target := Vector3(p.x, global_position.y, p.z)
	_step_toward(target, pursue_speed, delta)
	if global_position.distance_to(p) < contact_radius and not _contact_fired:
		_contact_fired = true
		EventBus.creature_contact.emit()
		state = State.RETREAT
		_wp_index = 0

func _on_dawn() -> void:
	if state != State.GONE:
		state = State.RETREAT
		_wp_index = 0

func _retreat(delta: float) -> void:
	# Visible exit: it slides off the Wet Deck edge into the sea (GDD 5.8).
	if _wp_index == 0:
		if _step_toward(exit_point, pursue_speed * 0.8, delta):
			_wp_index = 1
	else:
		global_position.y -= delta * 1.2
		global_position += (global_transform.basis * Vector3(0, 0, -1)) * delta * 0.6
		if global_position.y < -1.5:
			state = State.GONE
			if _claw_timer:
				_claw_timer.stop()
			AudioDirector.play_one_shot("splash", global_position)
			queue_free()
