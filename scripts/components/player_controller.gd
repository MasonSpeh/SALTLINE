extends CharacterBody3D
## First-person controller, deliberately unheroic (GDD A5): weighty and careful,
## not shooter-floaty. No jump; climbing only at Ladder nodes. Falling in water is a
## fade-out + Wet Deck respawn with a warmth penalty (the death-model stub).

const WALK_SPEED: float = 3.2
const SPRINT_SPEED: float = 5.0
const CROUCH_SPEED: float = 1.5
const CLIMB_SPEED: float = 1.8
const ACCELERATION: float = 8.0
const GRAVITY: float = 9.8
const JUMP_VELOCITY: float = 4.2
const MOUSE_SENSITIVITY: float = 0.0025
const HEAD_BOB_WALK_FREQ: float = 1.8
const HEAD_BOB_SPRINT_FREQ: float = 2.6
const HEAD_BOB_AMPLITUDE: float = 0.03
const WATER_LEVEL: float = 0.4

# Crouch: halves the standing capsule and drops the eye line. Held on the crouch key.
const STAND_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 0.9
const STAND_COL_Y: float = 0.9
const CROUCH_COL_Y: float = 0.45
const STAND_HEAD_Y: float = 1.6
const CROUCH_HEAD_Y: float = 0.85
const CROUCH_LERP: float = 12.0

const STAMINA_MAX: float = 1.0
const STAMINA_DRAIN_PER_SEC: float = 0.2
const STAMINA_REGEN_PER_SEC: float = 0.15
const STAMINA_MIN_TO_SPRINT: float = 0.1

@export var invert_y: bool = false
@export var mouse_sensitivity_scale: float = 1.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var _col: CollisionShape3D = $CollisionShape3D

var _hand_item: Node3D = null  ## visual item mesh held in right hand
var _held_item_id: String = ""

var input_locked: bool = false     ## cold open / cutscenes: look allowed, movement not
var respawn_point: Vector3 = Vector3.ZERO
var carried: Node3D = null         ## currently held physics object
var hook_out: bool = false         ## throwing hook is in flight / reeling
var ui_locked: bool = false        ## a HUD panel (inventory/journal/help/bench) is open
var build: BuildMode = null        ## build mode controller (B)
var crouching: bool = false        ## held crouch — half height, slower, harder to detect
var _stamina: float = STAMINA_MAX
var _head_bob_time: float = 0.0
var _camera_base_y: float
var _crouch_t: float = 0.0         ## 0 = standing, 1 = fully crouched
var _jump_buffer: float = 0.0      ## brief window after a jump press, so it still fires on landing
var _jump_was_pressed: bool = false
var _climbing: Ladder = null
var _drowning: bool = false
var _step_accum: float = 0.0

const JUMP_BUFFER_TIME: float = 0.15

## How detectable the player is to creatures right now (1.0 standing, 0.5 crouched).
## The Lamplight Crab multiplies its detect radius by this.
func detection_factor() -> float:
	return 0.5 if crouching else 1.0

func _ready() -> void:
	add_to_group("player")
	camera.fov = 75.0
	_camera_base_y = head.position.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var ray := InteractionRay.new()
	camera.add_child(ray)
	build = BuildMode.new()
	add_child(build)
	build.setup(self, camera)
	# Create hand item holder (positioned in front of camera, to the right)
	_hand_item = Node3D.new()
	camera.add_child(_hand_item)
	_hand_item.position = Vector3(0.35, -0.3, -0.8)
	PlayerState.inventory_changed.connect(_update_held_item)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: Vector2 = event.relative
		rotate_y(-motion.x * MOUSE_SENSITIVITY * mouse_sensitivity_scale)
		var pitch_delta: float = -motion.y * MOUSE_SENSITIVITY * mouse_sensitivity_scale
		if invert_y:
			pitch_delta = -pitch_delta
		head.rotate_x(pitch_delta)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	# Carrying a prop: left-click throws, E or G sets it down.
	if carried and not input_locked:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_throw_carried()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("interact") or (event is InputEventKey and event.keycode == KEY_G and event.pressed):
			drop_carried()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and not input_locked:
		match event.keycode:
			KEY_1:
				PlayerState.selected_hotbar = 0
				_update_held_item()
			KEY_2:
				PlayerState.selected_hotbar = 1
				_update_held_item()
			KEY_3:
				PlayerState.selected_hotbar = 2
				_update_held_item()
			KEY_4:
				PlayerState.selected_hotbar = 3
				_update_held_item()
			KEY_F: _throw_hook()
			KEY_B:
				if not ui_locked and not _climbing:
					build.toggle()

func _throw_hook() -> void:
	if hook_out or carried or _climbing or ui_locked or build.active \
			or not PlayerState.has_item("throwing_hook"):
		return
	hook_out = true
	var hook := ThrowingHook.new()
	get_tree().current_scene.add_child(hook)
	hook.setup(self, camera)
	AudioDirector.play_one_shot("splash", global_position, -20.0)   # the heave grunt stand-in

func hook_returned() -> void:
	hook_out = false

func _physics_process(delta: float) -> void:
	if _climbing:
		_climb_process(delta)
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	_update_crouch(delta)

	var can_act: bool = not input_locked and not ui_locked and not (build and build.active)
	# Jump: buffer the rising edge of the press (polled, so it survives frame timing),
	# then fire on the next grounded frame. A press just before landing still counts.
	var jump_pressed: bool = can_act and Input.is_action_pressed("jump")
	if jump_pressed and not _jump_was_pressed:
		_jump_buffer = JUMP_BUFFER_TIME
	_jump_was_pressed = jump_pressed
	if _jump_buffer > 0.0:
		_jump_buffer -= delta
	if can_act and _jump_buffer > 0.0 and is_on_floor() and not crouching:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0

	var input_dir: Vector2 = Vector2.ZERO
	if not input_locked and not ui_locked:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Crouch is slow and steady; sprint is disabled while crouched.
	var wants_sprint: bool = Input.is_action_pressed("sprint") and _stamina > STAMINA_MIN_TO_SPRINT and not crouching
	var stamina_ceiling: float = PlayerState.stamina_ceiling_multiplier()
	var base_speed: float = CROUCH_SPEED if crouching else (SPRINT_SPEED if wants_sprint else WALK_SPEED)
	var target_speed: float = base_speed * stamina_ceiling

	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var target_velocity: Vector3 = direction * target_speed

	velocity.x = move_toward(velocity.x, target_velocity.x, ACCELERATION * delta * target_speed)
	velocity.z = move_toward(velocity.z, target_velocity.z, ACCELERATION * delta * target_speed)

	move_and_slide()
	_update_stamina(delta, wants_sprint and direction.length() > 0.0)
	_update_head_bob(delta, direction.length() > 0.0, wants_sprint)
	_update_footsteps(delta)
	_check_water()

## Held crouch: lerp the capsule height, collider offset, and eye line together so the
## feet stay planted. Sets `crouching` for creature detection to read.
func _update_crouch(delta: float) -> void:
	crouching = Input.is_action_pressed("crouch") and not input_locked and not ui_locked \
		and not (build and build.active)
	_crouch_t = move_toward(_crouch_t, 1.0 if crouching else 0.0, CROUCH_LERP * delta)
	var cap := _col.shape as CapsuleShape3D
	if cap:
		cap.height = lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch_t)
	_col.position.y = lerpf(STAND_COL_Y, CROUCH_COL_Y, _crouch_t)
	_camera_base_y = lerpf(STAND_HEAD_Y, CROUCH_HEAD_Y, _crouch_t)

func _update_footsteps(_delta: float) -> void:
	if not is_on_floor():
		return
	var horizontal: Vector3 = Vector3(velocity.x, 0, velocity.z)
	_step_accum += horizontal.length() * _delta
	# Crouched steps are longer-spaced and much quieter — the stealth payoff.
	var stride: float = 3.6 if crouching else (2.6 if Input.is_action_pressed("sprint") else 2.1)
	if _step_accum >= stride:
		_step_accum = 0.0
		var vol: float = -28.0 if crouching else -16.0
		AudioDirector.play_one_shot("step", global_position + Vector3(0, -0.6, 0), vol)

func start_climb(ladder: Ladder) -> void:
	_climbing = ladder
	velocity = Vector3.ZERO
	var base: Vector3 = ladder.bottom_point()
	var y: float = clampf(global_position.y, base.y, ladder.top_point().y)
	global_position = Vector3(base.x, y, base.z) + ladder.face_dir() * 0.45

func _climb_process(_delta: float) -> void:
	# Exit climbing if E is released or player input-locked (cutscene)
	if not Input.is_action_pressed("interact") or input_locked:
		_climbing = null
		return

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
		# Settle to the current base briskly so crouching drops the eye line right away.
		head.position.y = move_toward(head.position.y, _camera_base_y, delta * 4.0)

func try_grab(prop: Node3D) -> void:
	if carried:
		drop_carried()
	carried = prop
	if carried is PhysProp:
		(carried as PhysProp).held_by = self
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_prompt_raw("[LMB] throw    [E] set down")

func drop_carried() -> void:
	if carried is PhysProp:
		(carried as PhysProp).held_by = null
	carried = null
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_prompt("")

func _throw_carried() -> void:
	var prop: Node3D = carried
	drop_carried()
	if prop is RigidBody3D:
		var forward: Vector3 = -camera.global_transform.basis.z
		(prop as RigidBody3D).apply_central_impulse(forward * 6.5 + Vector3(0, 1.6, 0))
		AudioDirector.play_one_shot("clang", prop.global_position, -12.0)

func _update_held_item() -> void:
	# Clear previous hand item
	for child in _hand_item.get_children():
		child.queue_free()
	_held_item_id = ""
	
	# Show the selected hotbar item in hand
	if PlayerState.selected_hotbar >= 0 and PlayerState.selected_hotbar < PlayerState.HOTBAR_SIZE:
		var item_id: String = PlayerState.hotbar[PlayerState.selected_hotbar]
		if item_id:
			_held_item_id = item_id
			var mesh: Node3D = ItemVisual.build(item_id)
			if mesh:
				_hand_item.add_child(mesh)
				mesh.scale *= 0.6
