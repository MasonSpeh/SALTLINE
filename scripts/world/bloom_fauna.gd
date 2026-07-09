class_name BloomFauna extends Node3D
## The rig's wildlife (GDD canon: the Bloom is curious, not hostile — light and life,
## never combat). Seven species, all cheap procedural geometry in the Bloom palette
## (teal / pearl glow), all keyed off GameClock phases per A6:
##   Gulls        — day flyers circling the high iron
##   JellyDrifter — night surface drifters, slow teal bells
##   Barnacles    — leg growths that pulse at night and clam up when you get close
##   LampEel      — glowing chain swimming figure-eights off the north pontoon
##   FiddlerShoal — day fish schooling under the wet deck lip
##   MantleRay    — huge slow glider that crosses over the rig at night
##   TideWorms    — dawn/dusk deck crawlers that retreat into their holes

const TEAL := Color(0.2, 0.9, 0.85)
const DIM_TEAL := Color(0.12, 0.5, 0.48)
const PEARL := Color(0.88, 0.94, 0.92)

func _ready() -> void:
	for i in range(5):
		add_child(Gull.new(i))
	for i in range(7):
		add_child(JellyDrifter.new(i))
	# Barnacle clusters on the inner leg faces near the waterline.
	for spec in [
		[Vector3(-19.2, 1.0, -12.0), 0.0], [Vector3(19.2, 1.2, 12.0), 180.0],
		[Vector3(-22.0, 0.8, -9.2), 90.0], [Vector3(22.0, 1.4, 9.2), -90.0],
		[Vector3(25.0, 0.9, -12.0), 180.0],
	]:
		var b := BarnacleCluster.new()
		add_child(b)
		b.global_position = spec[0]
		b.rotation.y = deg_to_rad(spec[1])
	add_child(LampEel.new())
	add_child(FiddlerShoal.new())
	add_child(MantleRay.new())
	# Tide worms along the wet-deck tide line and out on the pontoon.
	for p in [Vector3(24.5, 2.02, -17.5), Vector3(21.5, 2.02, -19.5), Vector3(26.5, 2.02, -13.0),
			Vector3(2.0, 0.97, -12.0), Vector3(-6.0, 0.97, -11.0)]:
		var w := TideWorm.new()
		add_child(w)
		w.global_position = p

static func glow_mat(color: Color, energy: float, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.5
	return m

static func is_dark_phase() -> bool:
	return GameClock.current_phase == GameClock.Phase.NIGHT \
		or GameClock.current_phase == GameClock.Phase.DUSK

# ---------------------------------------------------------------- Gull
class Gull extends Node3D:
	var _idx: int
	var _t: float
	var _center: Vector3
	var _radius: float
	var _speed: float
	var _wing_l: MeshInstance3D
	var _wing_r: MeshInstance3D
	var _leave: float = 0.0   # rises when dusk hits; gulls spiral off to the horizon

	func _init(idx: int) -> void:
		_idx = idx
		_t = idx * 1.7
		_center = Vector3(2 + idx * 3.0 - 6.0, 40.0 + idx * 2.5, -14.0 + idx * 4.0)
		_radius = 10.0 + idx * 3.5
		_speed = 0.5 + idx * 0.07

	func _ready() -> void:
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.16, 0.62)
		bm.material = BloomFauna.glow_mat(BloomFauna.PEARL, 0.1)
		body.mesh = bm
		add_child(body)
		var beak := MeshInstance3D.new()
		var km := BoxMesh.new()
		km.size = Vector3(0.06, 0.05, 0.16)
		km.material = BloomFauna.glow_mat(Color(0.85, 0.6, 0.2), 0.05)
		beak.mesh = km
		add_child(beak)
		beak.position = Vector3(0, 0.02, -0.36)
		_wing_l = _wing(-1)
		_wing_r = _wing(1)

	func _wing(side: int) -> MeshInstance3D:
		var w := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(0.85, 0.03, 0.3)
		wm.material = BloomFauna.glow_mat(BloomFauna.PEARL, 0.1)
		w.mesh = wm
		add_child(w)
		w.position = Vector3(side * 0.5, 0.04, 0)
		return w

	func _process(delta: float) -> void:
		var day: bool = GameClock.current_phase == GameClock.Phase.DAY \
			or GameClock.current_phase == GameClock.Phase.DAWN
		_leave = move_toward(_leave, 0.0 if day else 1.0, delta * 0.12)
		visible = _leave < 0.98
		if not visible:
			return
		_t += delta * _speed
		var r: float = _radius + _leave * 220.0          # spiral out when leaving
		var y: float = _center.y + sin(_t * 0.9 + _idx) * 2.0 + _leave * 60.0
		var next := Vector3(_center.x + cos(_t) * r, y, _center.z + sin(_t) * r)
		var vel: Vector3 = next - global_position
		global_position = next
		if vel.length_squared() > 0.0001:
			look_at(next + vel, Vector3.UP)
		var flap: float = sin(_t * 9.0) * 0.55
		_wing_l.rotation.z = flap
		_wing_r.rotation.z = -flap

# ---------------------------------------------------------- JellyDrifter
class JellyDrifter extends Node3D:
	var _idx: int
	var _t: float
	var _mat: StandardMaterial3D
	var _presence: float = 0.0   # 0 by day, 1 by night

	func _init(idx: int) -> void:
		_idx = idx
		_t = idx * 2.3

	func _ready() -> void:
		_mat = BloomFauna.glow_mat(BloomFauna.TEAL, 0.0, 0.55)
		var bell := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.42
		sm.height = 0.5
		sm.material = _mat
		bell.mesh = sm
		add_child(bell)
		for i in range(3):
			var tent := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(0.03, 0.7, 0.03)
			tm.material = _mat
			tent.mesh = tm
			add_child(tent)
			tent.position = Vector3(cos(i * 2.1) * 0.18, -0.5, sin(i * 2.1) * 0.18)

	func _process(delta: float) -> void:
		_presence = move_toward(_presence, 1.0 if BloomFauna.is_dark_phase() else 0.0, delta * 0.1)
		visible = _presence > 0.02
		_mat.emission_energy_multiplier = _presence * (1.3 + 0.5 * sin(_t * 1.1))
		_mat.albedo_color.a = _presence * 0.55
		if not visible:
			return
		_t += delta
		var angle: float = _idx * 0.9 + _t * 0.045
		var radius: float = 15.0 + _idx * 3.2 + sin(_t * 0.2 + _idx) * 2.0
		global_position = Vector3(cos(angle) * radius, 0.35 + sin(_t * 0.8 + _idx) * 0.25, sin(angle) * radius)
		scale.y = 1.0 + sin(_t * 2.2 + _idx) * 0.12   # bell contraction

# -------------------------------------------------------- BarnacleCluster
class BarnacleCluster extends Node3D:
	var _mat: StandardMaterial3D
	var _t: float = 0.0
	var _phase_offset: float

	func _ready() -> void:
		_phase_offset = global_position.x * 0.7 + global_position.z * 0.3
		_mat = BloomFauna.glow_mat(BloomFauna.DIM_TEAL, 0.05)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(global_position.x * 17.0 + global_position.z * 31.0)
		for i in range(rng.randi_range(6, 9)):
			var cone := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.015
			cm.bottom_radius = rng.randf_range(0.06, 0.14)
			cm.height = rng.randf_range(0.1, 0.24)
			cm.material = _mat
			cone.mesh = cm
			add_child(cone)
			cone.position = Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.4, 0.4), 0.05)
			cone.rotation.x = deg_to_rad(90)   # point out of the leg face

	func _process(delta: float) -> void:
		_t += delta
		var target: float = 0.05
		if GameClock.current_phase == GameClock.Phase.NIGHT:
			target = 0.9 + 0.5 * sin(_t * 1.3 + _phase_offset)
			var player: Node3D = get_tree().get_first_node_in_group("player")
			if player and player.global_position.distance_to(global_position) < 4.5:
				target = 0.03   # they feel you coming and go dark
		_mat.emission_energy_multiplier = lerpf(_mat.emission_energy_multiplier, target, delta * 2.5)

# ------------------------------------------------------------- LampEel
class LampEel extends Node3D:
	const SEGMENTS: int = 9
	const SPACING: float = 0.5
	var _t: float = 0.0
	var _segs: Array[Node3D] = []
	var _mats: Array[StandardMaterial3D] = []
	var _presence: float = 0.0

	func _ready() -> void:
		for i in range(SEGMENTS):
			var seg := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var r: float = 0.22 - i * 0.015
			sm.radius = r
			sm.height = r * 2.0
			var m: StandardMaterial3D = BloomFauna.glow_mat(BloomFauna.TEAL, 0.0)
			sm.material = m
			_mats.append(m)
			seg.mesh = sm
			add_child(seg)
			seg.position = Vector3(-i * SPACING, 0, 0)
			_segs.append(seg)

	func _process(delta: float) -> void:
		_presence = move_toward(_presence, 1.0 if GameClock.current_phase == GameClock.Phase.NIGHT else 0.0, delta * 0.15)
		visible = _presence > 0.02
		for i in range(_mats.size()):
			_mats[i].emission_energy_multiplier = _presence * (1.8 - i * 0.17)
		if not visible:
			return
		_t += delta
		# Figure-eights at the surface off the north edge, clear of the deck overhang.
		var head := Vector3(sin(_t * 0.5) * 13.0, 0.12, 26.0 + sin(_t * 1.0) * 5.0)
		_segs[0].global_position = _segs[0].global_position.lerp(head, delta * 4.0)
		for i in range(1, SEGMENTS):
			var prev: Vector3 = _segs[i - 1].global_position
			var cur: Vector3 = _segs[i].global_position
			var d: Vector3 = cur - prev
			if d.length() > 0.001:
				_segs[i].global_position = prev + d.normalized() * SPACING

# ---------------------------------------------------------- FiddlerShoal
class FiddlerShoal extends Node3D:
	const COUNT: int = 14
	var _t: float = 0.0
	var _fish: Array[MeshInstance3D] = []
	var _mat: StandardMaterial3D

	func _ready() -> void:
		_mat = BloomFauna.glow_mat(Color(0.7, 0.78, 0.8), 0.15)
		for i in range(COUNT):
			var f := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(0.05, 0.09, 0.28)
			fm.material = _mat
			f.mesh = fm
			add_child(f)
			_fish.append(f)

	func _process(delta: float) -> void:
		var active: bool = GameClock.current_phase != GameClock.Phase.NIGHT
		visible = active   # they hide from what walks at night
		if not active:
			return
		_t += delta
		# At dusk the shoal picks up a bloom-touched glint.
		_mat.emission = BloomFauna.TEAL if GameClock.current_phase == GameClock.Phase.DUSK else Color(0.7, 0.78, 0.8)
		_mat.emission_energy_multiplier = 0.7 if GameClock.current_phase == GameClock.Phase.DUSK else 0.15
		var center := Vector3(19.0 + cos(_t * 0.13) * 8.0, -0.15, -10.0 + sin(_t * 0.19) * 7.0)
		for i in range(COUNT):
			var a: float = _t * 1.6 + i * (TAU / COUNT)
			var r: float = 1.2 + sin(_t * 0.9 + i) * 0.5
			var next := center + Vector3(cos(a) * r, sin(_t * 2.0 + i) * 0.1, sin(a) * r * 0.7)
			var vel: Vector3 = next - _fish[i].global_position
			_fish[i].global_position = next
			if vel.length_squared() > 0.0001:
				_fish[i].look_at(next + vel, Vector3.UP)

# ------------------------------------------------------------ MantleRay
class MantleRay extends Node3D:
	var _t: float = 0.0
	var _flying: bool = false
	var _from: Vector3
	var _to: Vector3
	var _progress: float = 0.0
	var _cooldown: float = 25.0    # first pass comes fairly soon into the night
	var _wing_l: MeshInstance3D
	var _wing_r: MeshInstance3D

	func _ready() -> void:
		visible = false
		var dark := BloomFauna.glow_mat(Color(0.1, 0.14, 0.16), 0.0)
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.2, 0.5, 7.0)
		bm.material = dark
		body.mesh = bm
		add_child(body)
		_wing_l = _wing(-1, dark)
		_wing_r = _wing(1, dark)
		# Bloom speckles under the wings — the give-away glow overhead.
		var rng := RandomNumberGenerator.new()
		rng.seed = 7717
		for i in range(14):
			var dot := MeshInstance3D.new()
			var dm := SphereMesh.new()
			dm.radius = 0.09
			dm.height = 0.18
			dm.material = BloomFauna.glow_mat(BloomFauna.TEAL, 2.2)
			dot.mesh = dm
			add_child(dot)
			dot.position = Vector3(rng.randf_range(-4.5, 4.5), -0.3, rng.randf_range(-2.8, 2.8))

	func _wing(side: int, mat: Material) -> MeshInstance3D:
		var w := MeshInstance3D.new()
		var wm := PrismMesh.new()
		wm.size = Vector3(5.0, 0.25, 5.5)
		wm.material = mat
		w.mesh = wm
		add_child(w)
		w.position = Vector3(side * 3.4, 0, 0)
		w.rotation.z = deg_to_rad(90.0 * side)
		return w

	func _process(delta: float) -> void:
		_t += delta
		if not _flying:
			if GameClock.current_phase == GameClock.Phase.NIGHT:
				_cooldown -= delta
				if _cooldown <= 0.0:
					_begin_pass()
			return
		_progress += delta / 45.0    # one slow crossing takes 45s
		if _progress >= 1.0:
			_flying = false
			visible = false
			_cooldown = randf_range(90.0, 150.0)
			return
		var pos: Vector3 = _from.lerp(_to, _progress)
		pos.y += sin(_progress * PI) * -6.0   # dips lowest right over the deck
		global_position = pos
		look_at(pos + (_to - _from).normalized(), Vector3.UP)
		var flap: float = sin(_t * 1.1) * 0.18
		_wing_l.rotation.x = flap
		_wing_r.rotation.x = -flap

	func _begin_pass() -> void:
		_flying = true
		visible = true
		_progress = 0.0
		var angle: float = randf_range(0, TAU)
		var dir := Vector3(cos(angle), 0, sin(angle))
		_from = -dir * 180.0 + Vector3(0, randf_range(38.0, 50.0), 0)
		_to = dir * 180.0 + Vector3(0, randf_range(38.0, 50.0), 0)
		AudioDirector.play_one_shot("groan", global_position, -8.0)   # a vast, soft call

# ------------------------------------------------------------- TideWorm
class TideWorm extends Node3D:
	var _t: float = 0.0
	var _body: Node3D
	var _emerge: float = 0.0

	func _ready() -> void:
		_t = global_position.x * 1.3
		var hole := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.14
		hm.bottom_radius = 0.14
		hm.height = 0.02
		hm.material = BloomFauna.glow_mat(Color(0.04, 0.05, 0.06), 0.0)
		hole.mesh = hm
		add_child(hole)
		_body = Node3D.new()
		add_child(_body)
		for i in range(4):
			var seg := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var r: float = 0.07 - i * 0.012
			sm.radius = r
			sm.height = r * 2.0
			sm.material = BloomFauna.glow_mat(BloomFauna.TEAL if i == 3 else Color(0.3, 0.34, 0.3), 1.4 if i == 3 else 0.1)
			seg.mesh = sm
			add_child(seg)   # re-parented below for scale control
			remove_child(seg)
			_body.add_child(seg)
			seg.position = Vector3(0, 0.06 + i * 0.11, 0)

	func _process(delta: float) -> void:
		_t += delta
		var tide_time: bool = GameClock.current_phase == GameClock.Phase.DAWN \
			or GameClock.current_phase == GameClock.Phase.DUSK
		var want: float = 1.0 if tide_time else 0.0
		var player: Node3D = get_tree().get_first_node_in_group("player")
		if player and player.global_position.distance_to(global_position) < 2.5:
			want = 0.0   # felt your footsteps — gone
		_emerge = move_toward(_emerge, want, delta * (2.5 if want < _emerge else 0.35))
		_body.scale.y = maxf(_emerge, 0.001)
		_body.visible = _emerge > 0.02
		_body.rotation.x = sin(_t * 1.7) * 0.22 * _emerge
		_body.rotation.z = cos(_t * 1.3) * 0.22 * _emerge
