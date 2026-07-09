class_name ThrowingHook extends Node3D
## The heaving hook: crafted at the rigging bench, thrown with F. Flies in an arc,
## splashes down, then reels back in — any floating debris it lands near comes with
## it. The rope pays out visually from the player's hand the whole way.

enum State { FLYING, SETTLING, REELING }

const THROW_SPEED: float = 17.0
const THROW_LIFT: float = 3.5
const GRAVITY: float = 9.8
const REEL_SPEED: float = 8.0
const CATCH_RADIUS: float = 3.2
const MAX_RANGE: float = 55.0
const LIFT_DISTANCE: float = 6.0   # hook skims the water until this close, then rises

var _player: Node3D
var _state: State = State.FLYING
var _velocity: Vector3
var _settle: float = 0.0
var _caught: Array[Node3D] = []
var _rope: MeshInstance3D
var _rope_mesh: CylinderMesh

func setup(player: Node3D, camera: Camera3D) -> void:
	_player = player
	global_position = camera.global_position - camera.global_transform.basis.z * 0.6
	_velocity = -camera.global_transform.basis.z * THROW_SPEED + Vector3(0, THROW_LIFT, 0)

func _ready() -> void:
	# The hook itself: a bent dark claw with a pale lashing.
	var claw := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.12, 0.3, 0.12)
	cm.material = MatLib.dark_metal()
	claw.mesh = cm
	add_child(claw)
	var barb := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.12, 0.26)
	bm.material = MatLib.dark_metal()
	barb.mesh = bm
	add_child(barb)
	barb.position = Vector3(0, -0.12, 0.1)
	var lash := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.14, 0.08, 0.14)
	lm.material = MatLib.flat(Color(0.75, 0.68, 0.5))
	lash.mesh = lm
	add_child(lash)
	lash.position.y = 0.16
	# Rope: one thin cylinder stretched hand-to-hook every frame.
	_rope_mesh = CylinderMesh.new()
	_rope_mesh.top_radius = 0.016
	_rope_mesh.bottom_radius = 0.016
	_rope_mesh.height = 1.0
	_rope_mesh.material = MatLib.flat(Color(0.75, 0.68, 0.5))
	_rope = MeshInstance3D.new()
	_rope.mesh = _rope_mesh
	_rope.top_level = true
	add_child(_rope)

func _hand_pos() -> Vector3:
	return _player.global_position + Vector3(0, 1.2, 0)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		queue_free()
		return
	var t: float = Gyre.water_time()
	match _state:
		State.FLYING:
			_velocity.y -= GRAVITY * delta
			global_position += _velocity * delta
			var water_y: float = Gyre.wave_height(Vector2(global_position.x, global_position.z), t) * 0.85
			if global_position.y <= water_y + 0.05:
				global_position.y = water_y + 0.05
				AudioDirector.play_one_shot("splash", global_position, -6.0)
				_state = State.SETTLING
				_settle = 0.5
			elif global_position.distance_to(_hand_pos()) > MAX_RANGE:
				_state = State.REELING
			_try_catch()
		State.SETTLING:
			global_position.y = Gyre.wave_height(Vector2(global_position.x, global_position.z), t) * 0.85 + 0.05
			_try_catch()
			_settle -= delta
			if _settle <= 0.0:
				_state = State.REELING
		State.REELING:
			var to_hand: Vector3 = _hand_pos() - global_position
			var dist: float = to_hand.length()
			if dist < 1.4:
				_land()
				return
			var flat: Vector3 = Vector3(to_hand.x, 0, to_hand.z)
			if dist > LIFT_DISTANCE and flat.length() > 0.5:
				# Drag phase: skim the surface toward the player — this is the sweep
				# that combs debris out of the water.
				global_position += flat.normalized() * REEL_SPEED * delta
				global_position.y = Gyre.wave_height(Vector2(global_position.x, global_position.z), t) * 0.85 + 0.05
			else:
				# Close in: lift out of the water up to the hand.
				global_position += to_hand.normalized() * REEL_SPEED * delta
			_try_catch()
	_update_rope()

func _try_catch() -> void:
	for d in get_tree().get_nodes_in_group("floating_debris"):
		if d.hooked_by == null and d.global_position.distance_to(global_position) < CATCH_RADIUS:
			d.hooked_by = self
			_caught.append(d)
			AudioDirector.play_one_shot("clang", global_position, -14.0)

func _land() -> void:
	for d in _caught:
		if is_instance_valid(d):
			d.collect(_player)
	if _caught.is_empty():
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("The hook comes back empty.")
	if _player.has_method("hook_returned"):
		_player.hook_returned()
	queue_free()

func _update_rope() -> void:
	var a: Vector3 = _hand_pos()
	var b: Vector3 = global_position
	var mid: Vector3 = (a + b) * 0.5
	# A little sag when slack, taut while reeling.
	if _state != State.REELING:
		mid.y -= minf(a.distance_to(b) * 0.06, 1.2)
	var dist: float = a.distance_to(b)
	_rope_mesh.height = dist
	_rope.global_position = mid
	if dist > 0.01:
		_rope.look_at(b, Vector3.UP)
		_rope.rotate_object_local(Vector3.RIGHT, PI * 0.5)
