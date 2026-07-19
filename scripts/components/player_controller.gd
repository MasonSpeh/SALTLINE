extends CharacterBody3D
## First-person controller, deliberately unheroic (GDD A5): weighty and careful,
## not shooter-floaty. A short functional jump; climbing only at Ladder nodes —
## hold E to ascend, E+S to descend. Falling in water is a fade-out + Wet Deck
## respawn with a warmth penalty; running life dry blacks out the same way.

const WALK_SPEED: float = 3.2
const SPRINT_SPEED: float = 5.0
const CROUCH_SPEED: float = 1.5
const PRONE_SPEED: float = 0.9          ## a slow belly-crawl along the plating
const CLIMB_SPEED: float = 1.8
const ACCELERATION: float = 8.0
const GRAVITY: float = 9.8
const JUMP_VELOCITY: float = 4.2
const MOUSE_SENSITIVITY: float = 0.0025
const HEAD_BOB_WALK_FREQ: float = 1.8
const HEAD_BOB_SPRINT_FREQ: float = 2.6
const HEAD_BOB_AMPLITUDE: float = 0.03
const WATER_LEVEL: float = 0.4

# Postures: STAND (default), CROUCH (held on the crouch key), PRONE (Z toggle — lie
# flat on the deck). Each is a capsule height, a collider y-offset, and an eye line.
# Standing back up from a shorter posture is gated by a headroom check (_posture_fits).
const POSTURE_STAND: int = 0
const POSTURE_CROUCH: int = 1
const POSTURE_PRONE: int = 2

const STAND_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 0.9
const PRONE_HEIGHT: float = 0.8         ## lowest capsule the 0.4 radius allows (2*radius)
const STAND_COL_Y: float = 0.9
const CROUCH_COL_Y: float = 0.45
const PRONE_COL_Y: float = 0.4          ## capsule centered so it rests flat on the deck
const STAND_HEAD_Y: float = 1.6
const CROUCH_HEAD_Y: float = 0.85
const PRONE_HEAD_Y: float = 0.35        ## eye a hand's width off the plating, watching the sky
const CROUCH_LERP: float = 12.0         ## crouch / rising blend — quick and responsive
const PRONE_LERP: float = 5.5           ## easing DOWN onto the deck is slower, heavier, calm

const STAMINA_MAX: float = 1.0
const STAMINA_DRAIN_PER_SEC: float = 0.2
const STAMINA_REGEN_PER_SEC: float = 0.15
const STAMINA_MIN_TO_SPRINT: float = 0.1

# Held item: bottom-right of view, tilted slightly inward, never over the crosshair.
const HAND_ITEM_POS: Vector3 = Vector3(0.28, -0.24, -0.5)
const HAND_ITEM_MAX_DIM: float = 0.18   ## largest dimension of the normalized visual (m)
const HAND_SWAY_AMPLITUDE: float = 0.008

const CLIMB_TOP_GRACE: float = 0.3      ## grab-at-the-top zone where we hold, not mantle

# Dev fly mode (testing only): double-tap F to toggle noclip free-flight.
const FLY_SPEED: float = 9.0
const FLY_SPRINT_MULT: float = 3.5
const DOUBLE_TAP_MS: int = 320

# Swimming (GDD §31: competent, not heroic). Buoyant at the surface, dive with
# crouch, and the deep is not negotiable — past DEEP_DEATH_M the dark takes you.
const SWIM_SPEED: float = 2.3
const SWIM_SPRINT_MULT: float = 1.5
const FLOAT_DEPTH: float = 0.45        ## neutral float: this far under the swell, head above
const SWIM_WARMTH_DRAIN: float = 0.016 ## the North Atlantic taxes you per second
const DEEP_DEATH_M: float = 13.0
const DEEP_GRACE_SEC: float = 1.6

@export var invert_y: bool = false
@export var mouse_sensitivity_scale: float = 1.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var _col: CollisionShape3D = $CollisionShape3D

var _hand_item: Node3D = null  ## visual item mesh held in right hand
var _attack_cd: float = 0.0    ## melee swing cooldown
var _held_item_id: String = ""

var input_locked: bool = false     ## cold open / cutscenes: look allowed, movement not
var respawn_point: Vector3 = Vector3.ZERO
var carried: Node3D = null         ## currently held physics object
var hook_out: bool = false         ## throwing hook is in flight / reeling
var fishing: Node3D = null         ## a cast is out (FishingRod owns the line)
var ui_locked: bool = false        ## a HUD panel (inventory/journal/help/bench) is open
var build: BuildMode = null        ## build mode controller (B)
var crouching: bool = false        ## true while in the CROUCH posture (fauna read this)
var _posture: int = POSTURE_STAND  ## resolved every frame from crouch key + _prone toggle
var _prone: bool = false           ## Z toggle: lying flat on the deck (a comfort posture)
var _stamina: float = STAMINA_MAX
var _head_bob_time: float = 0.0
var _camera_base_y: float
var _jump_buffer: float = 0.0      ## brief window after a jump press, so it still fires on landing
var _jump_was_pressed: bool = false
var _climbing: Ladder = null
var _climb_from_top: bool = false  ## climb grabbed near the top — hold, don't insta-mantle
var _drowning: bool = false        ## shared blackout guard: water respawn OR life-out respawn
var _step_accum: float = 0.0
var _fly: bool = false             ## dev noclip fly mode (double-tap F)
var _last_f_ms: int = -10000       ## for double-tap F detection
var swimming: bool = false         ## in the water, buoyant, mortal
var _deep_t: float = 0.0           ## seconds spent past the deep-death line

const JUMP_BUFFER_TIME: float = 0.15

## How detectable the player is to creatures right now (1.0 standing, 0.5 crouched,
## 0.3 flat on the deck). The Lamplight Crab multiplies its detect radius by this.
func detection_factor() -> float:
	match _posture:
		POSTURE_PRONE:
			return 0.3
		POSTURE_CROUCH:
			return 0.5
		_:
			return 1.0

## Storm lantern: bloom-mucus behind glass. Warm-but-green, close, and steady —
## it should read as YOUR light against the teal, not as another bloom organ.
const LANTERN_COLOR: Color = Color(1.0, 0.86, 0.62)
const LANTERN_RANGE: float = 9.0
const LANTERN_ENERGY: float = 1.5
var _lantern_light: OmniLight3D = null

func _ready() -> void:
	add_to_group("player")
	camera.fov = 75.0
	_camera_base_y = head.position.y
	_ensure_posture_bindings()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var ray := InteractionRay.new()
	camera.add_child(ray)
	build = BuildMode.new()
	add_child(build)
	build.setup(self, camera)
	# Create hand item holder: low-right of the view, angled slightly inward.
	_hand_item = Node3D.new()
	camera.add_child(_hand_item)
	_hand_item.position = HAND_ITEM_POS
	_hand_item.rotation.y = -0.35
	_hand_item.rotation.x = 0.15
	# The storm lantern is worn light, not a held tool: carrying one lights the deck
	# around you and keeps doing it in a squall. Without this the recipe promised
	# "Wind can't touch it, rain can't touch it. It just burns." and then burned
	# nothing — the item existed only as a world visual.
	_lantern_light = OmniLight3D.new()
	_lantern_light.light_color = LANTERN_COLOR
	_lantern_light.light_energy = 0.0
	_lantern_light.omni_range = LANTERN_RANGE
	_lantern_light.shadow_enabled = false   # gl_compatibility: keep the omni cheap
	add_child(_lantern_light)
	_lantern_light.position = Vector3(0, 1.1, 0)
	PlayerState.inventory_changed.connect(_update_held_item)
	PlayerState.inventory_changed.connect(_update_lantern)
	PlayerState.player_died.connect(_on_player_died)
	_update_lantern()

## Guarantee the posture actions exist even if project.godot lacks them. `crouch` is
## defined in the project map (Ctrl); `prone` is registered here at runtime (Z) so we
## never have to touch project.godot. Safe to call once — skips actions already present.
func _ensure_posture_bindings() -> void:
	if not InputMap.has_action("crouch"):
		InputMap.add_action("crouch")
		var ev_ctrl := InputEventKey.new()
		ev_ctrl.physical_keycode = KEY_CTRL
		InputMap.action_add_event("crouch", ev_ctrl)
	if not InputMap.has_action("prone"):
		InputMap.add_action("prone")
		var ev_z := InputEventKey.new()
		ev_z.physical_keycode = KEY_Z
		InputMap.action_add_event("prone", ev_z)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: Vector2 = event.relative
		rotate_y(-motion.x * MOUSE_SENSITIVITY * mouse_sensitivity_scale)
		var pitch_delta: float = -motion.y * MOUSE_SENSITIVITY * mouse_sensitivity_scale
		if invert_y:
			pitch_delta = -pitch_delta
		head.rotate_x(pitch_delta)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	# Rod selected + LMB = cast. (While a cast is out, the FishingRod handles LMB.)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and not input_locked and not ui_locked and fishing == null \
			and carried == null and not _climbing and not hook_out \
			and not (build and build.active) and _selected_item_id() == "fishing_rod":
		_start_fishing()
		get_viewport().set_input_as_handled()
		return
	# A melee weapon selected + LMB = swing at whatever's in reach ahead.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and not input_locked and not ui_locked and fishing == null \
			and carried == null and not _climbing and not hook_out \
			and not (build and build.active) and _is_weapon(_selected_item_id()):
		_melee_attack()
		get_viewport().set_input_as_handled()
		return
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
	# Prone toggle (Z): only on land, and never while a panel/cutscene owns input.
	if event.is_action_pressed("prone") and not input_locked and not ui_locked \
			and not (build and build.active) and not _climbing and not swimming and not _fly:
		_toggle_prone()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and not input_locked:
		match event.keycode:
			KEY_1: _hotbar_pressed(0)
			KEY_2: _hotbar_pressed(1)
			KEY_3: _hotbar_pressed(2)
			KEY_4: _hotbar_pressed(3)
			KEY_F: _f_pressed()
			KEY_B:
				if not ui_locked and not _climbing:
					build.toggle()

## Select-then-use: first press of a number selects the slot (item shows in hand),
## pressing the SAME number again uses it. Selecting an empty slot clears the hand.
func _hotbar_pressed(slot: int) -> void:
	if ui_locked:
		return
	if PlayerState.selected_hotbar == slot and PlayerState.hotbar[slot] != null:
		PlayerState.use_hotbar(slot)   # inventory_changed refreshes the hand visual
	else:
		PlayerState.selected_hotbar = slot
	_update_held_item()

## F is a double-purpose key: a single press throws the rigging hook (gameplay),
## a quick double-tap toggles dev fly mode (testing). The stray single-tap hook
## on the way into a double-tap is harmless — it needs a hook item and reels back.
func _f_pressed() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_f_ms <= DOUBLE_TAP_MS:
		_last_f_ms = -10000
		_toggle_fly()
		return
	_last_f_ms = now
	_throw_hook()

func _toggle_fly() -> void:
	_fly = not _fly
	velocity = Vector3.ZERO
	_climbing = null
	# Ignore the world while flying so noclip can pass through structure.
	set_collision_layer_value(1, not _fly)
	set_collision_mask_value(1, not _fly)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("FLY MODE %s  ·  Space up / Ctrl down / Shift boost" % ("ON" if _fly else "OFF"))

## Free 6-axis noclip flight for testing. Look direction drives horizontal thrust
## (pitch-aware), Space/Ctrl handle vertical, Shift boosts. Moves the transform
## directly so it passes through geometry.
func _fly_process(delta: float) -> void:
	var speed: float = FLY_SPEED * (FLY_SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)
	var input_dir: Vector2 = Vector2.ZERO
	if not ui_locked:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move: Vector3 = head.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	if Input.is_action_pressed("jump"):
		move.y += 1.0
	if Input.is_action_pressed("crouch"):
		move.y -= 1.0
	if move.length() > 0.001:
		global_position += move.normalized() * speed * delta
	velocity = Vector3.ZERO

func _selected_item_id() -> String:
	var slot: int = PlayerState.selected_hotbar
	if slot < 0 or slot >= PlayerState.HOTBAR_SIZE or PlayerState.hotbar[slot] == null:
		return ""
	return String(PlayerState.hotbar[slot])

## True when the in-hand item defines melee stats (a crafted weapon).
func _is_weapon(id: String) -> bool:
	return id != "" and PlayerState.items.get(id, {}).has("melee_damage")

## Swing the held weapon: a quick arc of the hand item, a whistle of air, and a
## hit on the nearest creature ahead within reach. Crabs and other fauna that
## implement repel() get driven off; the spear's longer reach keeps claws away.
func _melee_attack() -> void:
	if _attack_cd > 0.0:
		return
	var id: String = _selected_item_id()
	var data: Dictionary = PlayerState.items.get(id, {})
	var reach: float = float(data.get("melee_reach", 2.0))
	var dmg: float = float(data.get("melee_damage", 1.0))
	_attack_cd = float(data.get("swing_sec", 0.5))
	_swing_hand(_attack_cd)
	AudioDirector.play_one_shot("hiss", global_position, -18.0)   # a whistle of air
	# Closest hittable roughly in front, within reach. Distance is measured from the
	# body (not the raised camera) so a ground-level crab isn't out of reach on height.
	var origin: Vector3 = global_position
	var forward: Vector3 = -camera.global_transform.basis.z
	var best: Node3D = null
	var best_d: float = reach + 0.01
	for c in get_tree().get_nodes_in_group("hittable"):
		if not (c is Node3D) or not c.has_method("repel"):
			continue
		var to: Vector3 = (c as Node3D).global_position - origin
		var dist: float = to.length()
		if dist > reach or dist < 0.05:
			continue
		if to.normalized().dot(forward) < 0.4:   # must be in the swing arc
			continue
		if dist < best_d:
			best = c
			best_d = dist
	if best:
		best.repel(global_position, dmg)

## Arc the hand item down-and-across, then settle back — a melee swing.
func _swing_hand(dur: float) -> void:
	if _hand_item == null:
		return
	var rest: Vector3 = _hand_item.rotation
	var tw: Tween = create_tween()
	tw.tween_property(_hand_item, "rotation", rest + Vector3(deg_to_rad(-70), deg_to_rad(35), 0), dur * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_hand_item, "rotation", rest, dur * 0.65).set_trans(Tween.TRANS_SINE)

func _start_fishing() -> void:
	# Preloaded by path — the global class cache may not know the new file yet.
	var rod: Node3D = preload("res://scripts/components/fishing_rod.gd").new()
	get_tree().current_scene.add_child(rod)
	rod.setup(self, camera)
	fishing = rod

func fishing_done() -> void:
	fishing = null

func _throw_hook() -> void:
	if hook_out or carried or _climbing or ui_locked or build.active or fishing \
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
	if _attack_cd > 0.0:
		_attack_cd -= delta
	if _fly:
		_fly_process(delta)
		return
	if _climbing:
		_climb_process(delta)
		return
	if swimming:
		_swim_process(delta)
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	_update_posture(delta)

	var can_act: bool = not input_locked and not ui_locked and not (build and build.active)
	# Jump: buffer the rising edge of the press (polled, so it survives frame timing),
	# then fire on the next grounded frame. A press just before landing still counts.
	var jump_pressed: bool = can_act and Input.is_action_pressed("jump")
	if jump_pressed and not _jump_was_pressed:
		if _posture == POSTURE_PRONE:
			_prone = false   # jump gets you up off the deck instead of leaping
		else:
			_jump_buffer = JUMP_BUFFER_TIME
	_jump_was_pressed = jump_pressed
	if _jump_buffer > 0.0:
		_jump_buffer -= delta
	# Only a full stand can jump — crouched and prone are pinned to the deck.
	if can_act and _jump_buffer > 0.0 and is_on_floor() and _posture == POSTURE_STAND:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0

	var input_dir: Vector2 = Vector2.ZERO
	if not input_locked and not ui_locked:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Sprint only stands: crouch is a slow steady walk, prone is a crawl.
	var wants_sprint: bool = Input.is_action_pressed("sprint") and _stamina > STAMINA_MIN_TO_SPRINT and _posture == POSTURE_STAND
	var stamina_ceiling: float = PlayerState.stamina_ceiling_multiplier()
	var base_speed: float
	match _posture:
		POSTURE_PRONE:
			base_speed = PRONE_SPEED
		POSTURE_CROUCH:
			base_speed = CROUCH_SPEED
		_:
			base_speed = SPRINT_SPEED if wants_sprint else WALK_SPEED
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

## Resolve the posture (crouch key + prone toggle), gate any RISE by a headroom check,
## then ease the capsule height, collider offset, and eye line toward it in lockstep so
## the feet stay planted. Writes `crouching` for creature detection to read.
func _update_posture(delta: float) -> void:
	var desired: int = _resolve_posture()
	# Rising into a taller posture is refused under a low ceiling — hold where we are.
	if _posture_rank(desired) > _posture_rank(_posture) and not _posture_fits(desired):
		desired = _posture
	_posture = desired
	crouching = _posture == POSTURE_CROUCH

	# Coming up is crisp; easing DOWN onto the deck is slower and calm.
	var rate: float = PRONE_LERP if _posture == POSTURE_PRONE else CROUCH_LERP
	var t: float = clampf(rate * delta, 0.0, 1.0)
	var cap := _col.shape as CapsuleShape3D
	if cap:
		cap.height = lerpf(cap.height, _posture_height(_posture), t)
	_col.position.y = lerpf(_col.position.y, _posture_col_y(_posture), t)
	_camera_base_y = lerpf(_camera_base_y, _posture_head_y(_posture), t)

## What the player is asking for this frame. Held crouch beats the prone toggle and
## clears it (tap crouch while prone → rise into a crouch). During a panel/cutscene the
## crouch key is ignored — matching the old crouch — but a standing prone toggle persists,
## so you can lie on the deck and still open the journal without popping upright.
func _resolve_posture() -> int:
	var can_key: bool = not input_locked and not ui_locked and not (build and build.active)
	if can_key and Input.is_action_pressed("crouch"):
		_prone = false
		return POSTURE_CROUCH
	if _prone:
		return POSTURE_PRONE
	return POSTURE_STAND

## Tallest posture ranks highest, so a bigger rank means "standing up more".
func _posture_rank(p: int) -> int:
	match p:
		POSTURE_PRONE:
			return 0
		POSTURE_CROUCH:
			return 1
		_:
			return 2

func _posture_height(p: int) -> float:
	match p:
		POSTURE_PRONE:
			return PRONE_HEIGHT
		POSTURE_CROUCH:
			return CROUCH_HEIGHT
		_:
			return STAND_HEIGHT

func _posture_col_y(p: int) -> float:
	match p:
		POSTURE_PRONE:
			return PRONE_COL_Y
		POSTURE_CROUCH:
			return CROUCH_COL_Y
		_:
			return STAND_COL_Y

func _posture_head_y(p: int) -> float:
	match p:
		POSTURE_PRONE:
			return PRONE_HEAD_Y
		POSTURE_CROUCH:
			return CROUCH_HEAD_Y
		_:
			return STAND_HEAD_Y

## How much the head bobs per posture — a belly-crawl barely rocks; a crouch is muted.
func _posture_bob_scale() -> float:
	match _posture:
		POSTURE_PRONE:
			return 0.25
		POSTURE_CROUCH:
			return 0.6
		_:
			return 1.0

## True if a taller capsule would clear whatever's overhead. A slim sphere probe (radius
## under the body radius, so side walls never trip it) is placed where the new head would
## sit; if world geometry is already there, the rise is blocked and we stay low.
func _posture_fits(target: int) -> bool:
	var world: World3D = get_world_3d()
	if world == null:
		return true
	var top: float = _posture_col_y(target) + _posture_height(target) * 0.5
	var probe := SphereShape3D.new()
	probe.radius = 0.3
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.collision_mask = 1   # world only — fauna drifting overhead don't pin you down
	params.exclude = [get_rid()]
	params.transform = Transform3D(Basis(), global_position + Vector3(0.0, top + 0.05, 0.0))
	return world.direct_space_state.intersect_shape(params, 1).is_empty()

## Z toggles lying flat on the deck. Dropping down is always allowed; getting up is a
## normal rise, so the headroom gate in _update_posture can keep you down under an overhang
## (crawl clear, or tap crouch to come up as far as the ceiling lets you).
func _toggle_prone() -> void:
	_prone = not _prone
	if _prone:
		AudioDirector.play_one_shot("hiss", global_position, -26.0)   # a slow exhale, settling
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("You lie back on the deck plating. The sky does its slow turning.")

## Carrying the lantern lights you. Eased rather than snapped so picking it up or
## stowing it reads as a lamp being lifted, not as a switch being thrown.
func _update_lantern() -> void:
	if _lantern_light == null or not is_instance_valid(_lantern_light):
		return
	var want: float = LANTERN_ENERGY if PlayerState.has_item("storm_lantern") else 0.0
	if is_equal_approx(_lantern_light.light_energy, want):
		return
	var tw: Tween = create_tween()
	tw.tween_property(_lantern_light, "light_energy", want, 0.6)

func _update_footsteps(_delta: float) -> void:
	if not is_on_floor():
		return
	var horizontal: Vector3 = Vector3(velocity.x, 0, velocity.z)
	_step_accum += horizontal.length() * _delta
	# Lower postures space their contacts out — the stealth payoff. Prone is a
	# near-silent drag of cloth on plating. Ambience owns the LEVEL of each step
	# (it reads posture too); this only owns the cadence.
	var stride: float
	match _posture:
		POSTURE_PRONE:
			stride = 4.8
		POSTURE_CROUCH:
			stride = 3.6
		_:
			stride = 2.6 if Input.is_action_pressed("sprint") else 2.1
	if _step_accum >= stride:
		# The accumulator reset IS the footstep event — Ambience triggers off it and
		# plays the surface-correct sample (grate / plate / concrete / wood / water /
		# wet). The generic "step" one-shot that used to fire here layered one fixed
		# transient under all twelve of those, so wood and grate shared an attack and
		# the material distinction the samples exist for was flattened away.
		_step_accum = 0.0

## Latch onto a ladder. Hold-E climbing: E alone rises, E+S (move_back) descends,
## releasing E lets go at the current height. Grabbing from within CLIMB_TOP_GRACE of
## the top arms a hold so the player can start a descent instead of insta-mantling.
func start_climb(ladder: Ladder) -> void:
	if _climbing != null:
		return   # already climbing — never re-latch or switch ladders mid-climb
	_climbing = ladder
	_prone = false   # you don't take a ladder lying down — stand before the rungs
	velocity = Vector3.ZERO
	# Climb free of world collision: the interior well's ladder box sits ~0.35m from
	# the shaft wall and the 0.8m player capsule can't fit that gap — it jams and can't
	# rise, descend, or dismount (the "stuck on the ladder" trap). _leave_climb() re-arms.
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	var base: Vector3 = ladder.bottom_point()
	var y: float = clampf(global_position.y, base.y, ladder.top_point().y)
	global_position = Vector3(base.x, y, base.z) + ladder.face_dir() * 0.45
	_climb_from_top = y >= ladder.top_point().y - CLIMB_TOP_GRACE

## Every climb exit routes here: re-arm the world collision start_climb() disabled
## and drop the latch, so normal movement never resumes with collision ghosted off.
func _leave_climb() -> void:
	set_collision_layer_value(1, true)
	set_collision_mask_value(1, true)
	_climbing = null

func _climb_process(_delta: float) -> void:
	# Let go when E is released or the player is input-locked (cutscene) — gravity resumes.
	if not Input.is_action_pressed("interact") or input_locked:
		_leave_climb()
		return

	# Hold E = climb up automatically; add S (move_back) to climb down instead.
	var up_input: float = -1.0 if Input.is_action_pressed("move_back") else 1.0
	var ladder: Ladder = _climbing
	# Space bails out of any climb — the universal unstick: hop off the rungs.
	if Input.is_action_just_pressed("jump"):
		_leave_climb()
		velocity = ladder.face_dir() * 2.0 + Vector3(0, 1.5, 0)
		return
	var top_y: float = ladder.top_point().y
	var bottom_y: float = ladder.bottom_point().y
	# Grabbed near the top: hold there instead of mantling, until a descent clears it.
	if _climb_from_top:
		if global_position.y < top_y - CLIMB_TOP_GRACE - 0.05:
			_climb_from_top = false
		elif up_input > 0.0 and global_position.y >= top_y - 0.2:
			up_input = 0.0
	velocity = Vector3(0, up_input * CLIMB_SPEED, 0)
	move_and_slide()
	if global_position.y >= top_y - 0.2 and up_input > 0.0 and not _climb_from_top:
		# Mantle off the top, onto the open exit side (clear of the rungs and wall).
		global_position = ladder.top_point() - ladder.face_dir() * ladder.exit_forward + Vector3(0, 0.4, 0)
		_leave_climb()
	elif global_position.y <= bottom_y + 0.1 and up_input < 0.0:
		# Step off the bottom onto the open side so re-armed collision doesn't drop the
		# capsule straight back into the pinch between the rungs and the shaft wall.
		global_position = ladder.bottom_point() - ladder.face_dir() * ladder.exit_forward + Vector3(0, 0.1, 0)
		_leave_climb()

## Entering the water no longer teleports you out — you swim (GDD §31). The sea
## takes warmth constantly, ladders are the way back up, and the deep is death.
func _check_water() -> void:
	if _drowning or _fly:
		return
	var wave_y: float = Gyre.wave_height(Vector2(global_position.x, global_position.z), Gyre.water_time()) * 0.85
	var now_swimming: bool = global_position.y < wave_y - 0.15
	if now_swimming and not swimming:
		AudioDirector.play_one_shot("splash", global_position, -4.0)
		_prone = false   # you don't belly-crawl in the swell
		if _climbing:
			_leave_climb()   # fell off the ladder into the sea — re-arm world collision
		if carried:
			drop_carried()
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("Cold. Swim — find a ladder before the sea does the counting.")
	swimming = now_swimming
	if not swimming:
		_deep_t = 0.0

## Buoyant first-person swimming: look-direction drive, Space up, crouch dives,
## drifting toward a neutral float just under the swell. Cold drains warmth the
## whole time, and past DEEP_DEATH_M the dark below starts counting.
func _swim_process(delta: float) -> void:
	var wave_y: float = Gyre.wave_height(Vector2(global_position.x, global_position.z), Gyre.water_time()) * 0.85
	var input_dir: Vector2 = Vector2.ZERO
	if not input_locked and not ui_locked:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var speed: float = SWIM_SPEED * (SWIM_SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)
	var move: Vector3 = head.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	if not input_locked and not ui_locked:
		if Input.is_action_pressed("jump"):
			move.y += 0.8
		if Input.is_action_pressed("crouch"):
			move.y -= 0.8
	var target_vel: Vector3 = move.normalized() * speed if move.length() > 0.01 else Vector3.ZERO
	# Buoyancy: with no vertical intent, ease back up toward the neutral float line.
	var float_y: float = wave_y - FLOAT_DEPTH
	if absf(move.y) < 0.05:
		target_vel.y = clampf((float_y - global_position.y) * 1.6, -1.2, 1.6)
	velocity = velocity.lerp(target_vel, delta * 5.0)
	move_and_slide()
	PlayerState.warmth -= SWIM_WARMTH_DRAIN * delta
	_update_posture(delta)   # keeps the capsule sane if a posture was held on entry
	# The deep: light dies fast, and below the line something notices you.
	var depth: float = wave_y - global_position.y
	if depth > DEEP_DEATH_M:
		_deep_t += delta
		if _deep_t >= DEEP_GRACE_SEC:
			_deep_death()
			return
	else:
		_deep_t = maxf(_deep_t - delta * 2.0, 0.0)
	_check_water()

## Too deep, too long. No monster shown, no explanation given — canon.
func _deep_death() -> void:
	if _drowning:
		return
	_drowning = true
	input_locked = true
	swimming = false
	AudioDirector.play_one_shot("groan", global_position, -2.0)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		var tw: Tween = hud.fade_to_black(0.9)
		tw.tween_callback(_respawn)
	else:
		_respawn()

func _respawn() -> void:
	global_position = respawn_point
	velocity = Vector3.ZERO
	swimming = false
	_prone = false
	_deep_t = 0.0
	PlayerState.warmth -= 0.3
	PlayerState.life = maxf(PlayerState.life, 0.3)   # the sea returns you breathing
	_drowning = false
	input_locked = false
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.fade_from_black(1.5)
		hud.toast("You don't remember surfacing. You're on the deck, soaked through.")

## Life hit zero: same blackout shape as drowning, sharing the _drowning guard so the
## two fade/respawn flows can never run over each other.
func _on_player_died() -> void:
	if _drowning:
		return
	_drowning = true
	input_locked = true
	if _climbing:
		_leave_climb()   # dying mid-climb must re-arm the collision disabled on grab
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		var tw: Tween = hud.fade_to_black(1.2)
		tw.tween_callback(_respawn_from_death)
	else:
		_respawn_from_death()

func _respawn_from_death() -> void:
	global_position = respawn_point
	velocity = Vector3.ZERO
	_prone = false
	PlayerState.life = 0.5
	PlayerState.hunger = 0.4
	PlayerState.thirst = 0.4
	_drowning = false
	input_locked = false
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.fade_from_black(1.5)
		hud.toast("You blacked out. The rig gave you back.")

func _update_stamina(delta: float, is_sprinting: bool) -> void:
	if is_sprinting:
		_stamina = maxf(0.0, _stamina - STAMINA_DRAIN_PER_SEC * delta)
	else:
		_stamina = minf(STAMINA_MAX, _stamina + STAMINA_REGEN_PER_SEC * delta)

func _update_head_bob(delta: float, is_moving: bool, is_sprinting: bool) -> void:
	if is_moving and is_on_floor():
		var freq: float = HEAD_BOB_SPRINT_FREQ if is_sprinting else HEAD_BOB_WALK_FREQ
		_head_bob_time += delta * freq * TAU
		head.position.y = _camera_base_y + sin(_head_bob_time) * HEAD_BOB_AMPLITUDE * _posture_bob_scale()
		# Subtle counter-phase sway on the held item; drifts around HAND_ITEM_POS,
		# far too small to ever reach the crosshair.
		_hand_item.position = HAND_ITEM_POS + Vector3(
			cos(_head_bob_time * 0.5) * HAND_SWAY_AMPLITUDE,
			-sin(_head_bob_time) * HAND_SWAY_AMPLITUDE,
			0.0)
	else:
		_head_bob_time = 0.0
		# Settle to the current base briskly so crouching drops the eye line right away.
		head.position.y = move_toward(head.position.y, _camera_base_y, delta * 4.0)
		_hand_item.position = _hand_item.position.move_toward(HAND_ITEM_POS, delta * 0.1)

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

## Rebuild the in-hand visual for the selected hotbar slot. ItemVisual meshes are
## world-scale props with internal offsets, so we normalize at runtime: recenter on the
## combined AABB and uniform-scale so the largest dimension is HAND_ITEM_MAX_DIM.
func _update_held_item() -> void:
	# Clear previous hand item
	for child in _hand_item.get_children():
		_hand_item.remove_child(child)
		child.queue_free()
	_held_item_id = ""

	# Show the selected hotbar item in hand; an empty/deselected slot leaves the hand bare.
	if PlayerState.selected_hotbar < 0 or PlayerState.selected_hotbar >= PlayerState.HOTBAR_SIZE:
		return
	var item: Variant = PlayerState.hotbar[PlayerState.selected_hotbar]
	if item == null or String(item).is_empty():
		return
	_held_item_id = String(item)
	var visual: Node3D = ItemVisual.build(_held_item_id)
	if visual == null:
		return
	var container := Node3D.new()
	container.add_child(visual)
	_hand_item.add_child(container)
	_normalize_hand_visual(container, visual)

## Recenter + rescale a freshly built ItemVisual so it reads as a small held prop.
## Also kills shadow casting on every mesh — a hand item shadowing the world looks wrong.
func _normalize_hand_visual(container: Node3D, visual: Node3D) -> void:
	var combined: AABB = AABB()
	var found: bool = false
	var stack: Array[Node] = [visual]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.append(c)
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh == null:
			continue
		var box: AABB = _transform_relative_to(mi, visual) * mi.mesh.get_aabb()
		combined = box if not found else combined.merge(box)
		found = true
	if not found:
		return
	var largest: float = maxf(combined.size.x, maxf(combined.size.y, combined.size.z))
	# Tools that should read at working size in hand override the pocket scale —
	# the rod especially: you fish WITH it, it shouldn't look like a pencil.
	var target: float = HAND_ITEM_MAX_DIM
	match _held_item_id:
		"fishing_rod":
			target = 0.62
		"prybar":
			target = 0.4
	if largest > 0.0001:
		container.scale = Vector3.ONE * (target / largest)
	visual.position = -combined.get_center()
	if _held_item_id == "fishing_rod":
		# Angle the rod out over the water like it's actually being fished.
		container.rotation = Vector3(deg_to_rad(-24), deg_to_rad(-14), 0)
		container.position += Vector3(0.05, -0.05, -0.1)

## Composed local transform of `node` relative to ancestor `root` (tree-independent).
static func _transform_relative_to(node: Node3D, root: Node3D) -> Transform3D:
	var t: Transform3D = Transform3D.IDENTITY
	var n: Node3D = node
	while n != null and n != root:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t
