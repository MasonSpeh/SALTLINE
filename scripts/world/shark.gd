class_name UltraHammerhead extends Node3D
## The Bloom's patrol predator: a hammerhead grown past reason, cruising slow
## ellipses below the swell. Swimmers who stray close get judged — most passes
## (~70%) end in a charge and a hit; the rest it circles you once, close enough
## to count your heartbeats, and moves on. It never bothers what stays on deck.
## Rule 3′: aggression is ecological and readable — you can watch it decide.

enum SState { PATROL, CIRCLE, CHARGE, FLEE }

const NOTICE_RADIUS: float = 9.0
const BITE_RADIUS: float = 1.6
const ATTACK_CHANCE: float = 0.7      # "3-4 out of 5"
const BITE_DAMAGE: float = 0.35
const PATROL_SPEED: float = 3.6
const CHARGE_SPEED: float = 8.5
const COOLDOWN_SEC_MIN: float = 12.0
const COOLDOWN_SEC_MAX: float = 22.0

const ANIM := preload("res://scripts/world/creature_anim.gd")
const MODEL_PATH := "res://assets/models/fauna/ultra_hammerhead/ultra_hammerhead.glb"
const GLOW := Color(0.30, 0.85, 0.95)
var _mats: Array = []

var _idx: int = 0
var _t: float = 0.0
var _state: SState = SState.PATROL
var _center: Vector3
var _radius: float
var _depth: float
var _cooldown: float = 0.0
var _judged: bool = false           ## one roll per approach
var _circle_t: float = 0.0
var _flee_target: Vector3
var _tail: Node3D
var _rng := RandomNumberGenerator.new()

func _init(idx: int = 0) -> void:
	_idx = idx
	_t = idx * 7.3
	_rng.randomize()
	_center = [Vector3(0, 0, -38), Vector3(30, 0, 8), Vector3(-34, 0, -4)][idx % 3]
	_radius = 14.0 + idx * 4.0
	_depth = -2.6 - idx * 1.2

func _ready() -> void:
	var hide_mat := StandardMaterial3D.new()
	hide_mat.albedo_color = Color(0.36, 0.4, 0.44)
	hide_mat.roughness = 0.55
	var belly := StandardMaterial3D.new()
	belly.albedo_color = Color(0.75, 0.78, 0.78)
	belly.roughness = 0.6
	# Body: a 5m tapered capsule with a pale underside slab.
	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.55
	bm.height = 5.0
	bm.material = hide_mat
	body.mesh = bm
	body.rotation.x = deg_to_rad(90)
	add_child(body)
	var under := MeshInstance3D.new()
	var um := BoxMesh.new()
	um.size = Vector3(0.7, 0.18, 3.4)
	um.material = belly
	under.mesh = um
	under.position = Vector3(0, -0.42, 0.2)
	add_child(under)
	# The hammer: the crossbar that names it, an eye bulb at each end.
	var hammer := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(2.3, 0.3, 0.6)
	hm.material = hide_mat
	hammer.mesh = hm
	hammer.position = Vector3(0, 0, -2.5)
	add_child(hammer)
	for sx in [-1.15, 1.15]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.09
		em.height = 0.18
		em.material = StandardMaterial3D.new()
		(em.material as StandardMaterial3D).albedo_color = Color(0.05, 0.05, 0.06)
		eye.mesh = em
		eye.position = Vector3(sx, 0, -2.5)
		add_child(eye)
	# Dorsal fin, second dorsal, pectorals, gill slits, and a heterocercal tail
	# on its own pivot — the long upper lobe that writes the silhouette.
	var fin := MeshInstance3D.new()
	var fm := PrismMesh.new()
	fm.size = Vector3(0.16, 1.0, 1.1)
	fm.material = hide_mat
	fin.mesh = fm
	fin.position = Vector3(0, 0.85, 0.2)
	add_child(fin)
	var fin2 := MeshInstance3D.new()
	var f2m := PrismMesh.new()
	f2m.size = Vector3(0.1, 0.4, 0.5)
	f2m.material = hide_mat
	fin2.mesh = f2m
	fin2.position = Vector3(0, 0.6, 1.7)
	add_child(fin2)
	for side in [-1.0, 1.0]:
		var pec := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.1, 0.5, 1.3)
		pm.material = hide_mat
		pec.mesh = pm
		pec.position = Vector3(side * 0.65, -0.25, -0.9)
		pec.rotation_degrees = Vector3(0, 0, 105 * side)
		add_child(pec)
		# Five gill slits ahead of each pectoral.
		for g in range(5):
			var slit := MeshInstance3D.new()
			var sm2 := BoxMesh.new()
			sm2.size = Vector3(0.015, 0.3, 0.06)
			sm2.material = StandardMaterial3D.new()
			(sm2.material as StandardMaterial3D).albedo_color = Color(0.12, 0.14, 0.16)
			slit.mesh = sm2
			slit.position = Vector3(side * 0.52, 0.0, -1.5 + g * 0.13)
			add_child(slit)
	_tail = Node3D.new()
	add_child(_tail)
	_tail.position = Vector3(0, 0.1, 2.5)
	var upper := MeshInstance3D.new()
	var tm := PrismMesh.new()
	tm.size = Vector3(0.14, 1.7, 1.0)
	tm.material = hide_mat
	upper.mesh = tm
	upper.position = Vector3(0, 0.5, 0.4)
	upper.rotation.x = deg_to_rad(24)
	_tail.add_child(upper)
	var lower := MeshInstance3D.new()
	var lm := PrismMesh.new()
	lm.size = Vector3(0.12, 0.6, 0.5)
	lm.material = hide_mat
	lower.mesh = lm
	lower.position = Vector3(0, -0.3, 0.3)
	lower.rotation.x = deg_to_rad(155)
	_tail.add_child(lower)
	# Swap in the generated hammerhead if it's been produced; the body wave comes from
	# CreatureAnim's vertex shader (Meshy can't rig animals), driven below by swim effort.
	var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 5.0, ANIM.Mode.UNDULATE,
		0.09, 1.1, GLOW)
	if not gen.is_empty():
		_mats = gen["mats"]
	global_position = _center + Vector3(_radius, _depth, 0)

func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player")

func _process(delta: float) -> void:
	_t += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	# The tail works harder the harder it swims; the body wiggles a beat ahead.
	if _tail:
		var effort: float = 2.2 if _state == SState.CHARGE else 1.0
		_tail.rotation.y = sin(_t * 3.2 * effort) * 0.35
		rotation.y += sin(_t * 3.2 * effort + PI * 0.5) * 0.006 * effort
		# Generated mesh: body wave + cephalofoil ridge glow track the same effort.
		ANIM.drive(_mats, 0.9 * effort, 0.5 if _state == SState.CHARGE else 0.22)
	var player: Node3D = _player()
	var swimmer: bool = player != null and player.get("swimming") and player.swimming
	match _state:
		SState.PATROL:
			var a: float = _t * (PATROL_SPEED / _radius)
			var next: Vector3 = _center + Vector3(cos(a) * _radius, _depth + sin(_t * 0.3) * 0.6, sin(a) * _radius)
			_move_toward_point(next, delta, PATROL_SPEED)
			if swimmer and _cooldown <= 0.0 \
					and player.global_position.distance_to(global_position) < NOTICE_RADIUS:
				Journal.discover("creature_hammerhead")
				if not _judged:
					_judged = true
					if _rng.randf() < ATTACK_CHANCE:
						_state = SState.CHARGE
						AudioDirector.play_one_shot("groan", global_position, -10.0)
					else:
						_state = SState.CIRCLE
						_circle_t = 0.0
			elif not swimmer or player.global_position.distance_to(global_position) > NOTICE_RADIUS + 4.0:
				_judged = false   # the next approach is a fresh judgment
		SState.CIRCLE:
			# Spared — this pass. One slow ring around the swimmer, then away.
			_circle_t += delta
			if not swimmer or _circle_t > 7.0:
				_state = SState.PATROL
				_cooldown = 6.0
				return
			var ca: float = _circle_t * 0.9
			var around: Vector3 = player.global_position + Vector3(cos(ca) * 5.0, -0.8, sin(ca) * 5.0)
			_move_toward_point(around, delta, PATROL_SPEED * 1.2)
		SState.CHARGE:
			if not swimmer:
				_state = SState.PATROL   # target climbed out — the deck is not its world
				_cooldown = 4.0
				return
			var target: Vector3 = player.global_position + Vector3(0, -0.3, 0)
			_move_toward_point(target, delta, CHARGE_SPEED)
			if global_position.distance_to(player.global_position) < BITE_RADIUS:
				_bite(player)
		SState.FLEE:
			_move_toward_point(_flee_target, delta, CHARGE_SPEED * 0.8)
			if global_position.distance_to(_flee_target) < 3.0:
				_state = SState.PATROL

func _bite(player: Node3D) -> void:
	PlayerState.life -= BITE_DAMAGE
	PlayerState.warmth -= 0.1
	AudioDirector.play_one_shot("claw", global_position, 2.0)
	AudioDirector.play_one_shot("splash", global_position, -2.0)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("HAMMERHEAD — it hit you. Get out of the water!")
	# Shove the swimmer aside and leave — a test, not a meal (Rule 3′).
	if player is CharacterBody3D:
		var away: Vector3 = (player.global_position - global_position).normalized()
		(player as CharacterBody3D).velocity += away * 6.0 + Vector3(0, 2.0, 0)
	_cooldown = _rng.randf_range(COOLDOWN_SEC_MIN, COOLDOWN_SEC_MAX)
	_flee_target = global_position + (global_position - player.global_position).normalized() * 18.0
	_flee_target.y = _depth
	_state = SState.FLEE

func _move_toward_point(target: Vector3, delta: float, speed: float) -> void:
	var to: Vector3 = target - global_position
	if to.length() < 0.05:
		return
	global_position += to.limit_length(speed * delta)
	var flat := Vector3(to.x, 0, to.z)
	if flat.length_squared() > 0.0001:
		var desired: float = atan2(flat.x, flat.z)
		rotation.y = lerp_angle(rotation.y, desired + PI, delta * 3.0)
	rotation.z = lerp_angle(rotation.z, clampf(to.x * 0.02, -0.25, 0.25), delta * 2.0)
