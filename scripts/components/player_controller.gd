extends CharacterBody3D
## First-person controller, deliberately unheroic (GDD A5): weighty and careful,
## not shooter-floaty. No jump; climbing only at Ladder nodes. Falling in water is a
## fade-out + Wet Deck respawn with a warmth penalty (the death-model stub).

const WALK_SPEED: float = 3.2
const SPRINT_SPEED: float = 5.0
const CLIMB_SPEED: float = 1.8
const ACCELERATION: float = 8.0
const GRAVITY: float = 9.8
const MOUSE_SENSITIVITY: float = 0.0025
const HEAD_BOB_WALK_FREQ: float = 1.8
const HEAD_BOB_SPRINT_FREQ: float = 2.6
const HEAD_BOB_AMPLITUDE: float = 0.03
const WATER_LEVEL: float = 0.4

const STAMINA_MAX: float = 1.0
const STAMINA_DRAIN_PER_SEC: float = 0.2
const STAMINA_REGEN_PER_SEC: float = 0.15
const STAMINA_MIN_TO_SPRINT: float = 0.1

@export var invert_y: bool = false
@export var mouse_sensitivity_scale: float = 1.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var input_locked: bool = false     ## cold open / cutscenes: look allowed, movement not
var respawn_point: Vector3 = Vector3.ZERO
var _stamina: float = STAMINA_MAX
var _head_bob_time: float = 0.0
var _camera_base_y: float
var _climbing: Ladder = null
var _drowning: bool = false

func _ready() -> void:
	add_to_group("player")
	camera.fov = 75.0
	_camera_base_y = head.position.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var ray := InteractionRay.new()
	camera.add_child(ray)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: Vector2 = event.relative
		rotate_y(-motion.x * MOUSE_SENSITIVITY * mouse_sensitivity_scale)
		var pitch_delta: float = -motion.y * MOUSE_SENSITIVITY * mouse_sensitivity_scale
		if invert_y:
			pitch_delta = -pitch_delta
		head.rotate_x(pitch_delta)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	if event is InputEventKey and event.pressed and not event.echo and not input_locked:
		match event.keycode:
			KEY_1: PlayerState.use_hotbar(0)
			KEY_2: PlayerState.use_hotbar(1)
			KEY_3: PlayerState.use_hotbar(2)
			KEY_4: PlayerState.use_hotbar(3)

func _physics_process(delta: float) -> void:
	if _climbing:
		_climb_process(delta)
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var input_dir: Vector2 = Vector2.ZERO
	if not input_locked:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wants_sprint: bool = Input.is_action_pressed("sprint") and _stamina > STAMINA_MIN_TO_SPRINT
	var stamina_ceiling: float = PlayerState.stamina_ceiling_multiplier()
	var target_speed: float = (SPRINT_SPEED if wants_sprint else WALK_SPEED) * stamina_ceiling

	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var target_velocity: Vector3 = direction * target_speed

	velocity.x = move_toward(velocity.x, target_velocity.x, ACCELERATION * delta * target_speed)
	velocity.z = move_toward(velocity.z, target_velocity.z, ACCELERATION * delta * target_speed)

	move_and_slide()
	_update_stamina(delta, wants_sprint and direction.length() > 0.0)
	_update_head_bob(delta, direction.length() > 0.0, wants_sprint)
	_check_water()

func start_climb(ladder: Ladder) -> void:
	_climbing = ladder
	velocity = Vector3.ZERO
	var base: Vector3 = ladder.bottom_point()
	var y: float = clampf(global_position.y, base.y, ladder.top_point().y)
	global_position = Vector3(base.x, y, base.z) + ladder.face_dir() * 0.45

func _climb_process(_delta: float) -> void:
	var up_input: float = 0.0
	if not input_locked:
		up_input = Input.get_axis("move_back", "move_forward")
	velocity = Vector3(0, up_input * CLIMB_SPEED, 0)
	move_and_slide()
	var ladder: Ladder = _climbing
	var top_y: float = ladder.top_point().y
	var bottom_y: float = ladder.bottom_point().y
	if global_position.y >= top_y - 0.2 and up_input > 0.0:
		# Mantle off the top, onto the wall side.
		global_position = ladder.top_point() - ladder.face_dir() * ladder.exit_forward + Vector3(0, 0.4, 0)
		_climbing = null
	elif global_position.y <= bottom_y + 0.1 and up_input < 0.0:
		_climbing = null
	elif Input.is_action_just_pressed("interact"):
		_climbing = null

func _check_water() -> void:
	if _drowning or global_position.y > WATER_LEVEL:
		return
	_drowning = true
	input_locked = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	AudioDirector.play_one_shot("splash", global_position)
	if hud:
		var tw: Tween = hud.fade_to_black(1.2)
		tw.tween_callback(_respawn)
	else:
		_respawn()

func _respawn() -> void:
	global_position = respawn_point
	velocity = Vector3.ZERO
	PlayerState.warmth -= 0.3
	_drowning = false
	input_locked = false
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.fade_from_black(1.5)
		hud.toast("The sea let you go. This time.")

func _update_stamina(delta: float, is_sprinting: bool) -> void:
	if is_sprinting:
		_stamina = maxf(0.0, _stamina - STAMINA_DRAIN_PER_SEC * delta)
	else:
		_stamina = minf(STAMINA_MAX, _stamina + STAMINA_REGEN_PER_SEC * delta)

func _update_head_bob(delta: float, is_moving: bool, is_sprinting: bool) -> void:
	if is_moving and is_on_floor():
		var freq: float = HEAD_BOB_SPRINT_FREQ if is_sprinting else HEAD_BOB_WALK_FREQ
		_head_bob_time += delta * freq * TAU
		head.position.y = _camera_base_y + sin(_head_bob_time) * HEAD_BOB_AMPLITUDE
	else:
		_head_bob_time = 0.0
		head.position.y = move_toward(head.position.y, _camera_base_y, delta * 0.1)
