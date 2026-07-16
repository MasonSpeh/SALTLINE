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
##   GlowWorms    — night den-dwellers in the dark corners; crouch close to grab one
##   Epic4EyedWhale — four-eyed vastness that swims the night air, high and rare
##   HarborSeal   — day patrol, porpoises to breathe, watches you (befriendable)
##   LampSnail    — night constellations of glow-spots circling the leg bases (§54)
##   CorvidGull   — perched Bloom-intelligent gull that tracks the player (§26)

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
	add_child(Epic4EyedWhale.new())  # night visitor from the deep
	# New Codex species.
	add_child(HarborSeal.new())      # day patrol + curiosity (befriendable canon)
	add_child(HarborSeal.new())
	# Lamp Snails: glowing constellations circling the leg bases at night (§54).
	var snail_legs: Array[Vector3] = [Vector3(-19, 0, -12), Vector3(19, 0, -12), Vector3(-19, 0, 12),
			Vector3(19, 0, 12), Vector3(-22, 0, -9), Vector3(22, 0, 9)]
	for i in range(snail_legs.size()):
		add_child(LampSnail.new(i, snail_legs[i] + Vector3(0, 0.3, 0)))
	# Corvid-Gulls perched on rails, watching (§26).
	for perch in [Vector3(24.9, 2.75, -16.0), Vector3(-8.6, 18.75, 6.4), Vector3(27.6, 18.75, 4.0)]:
		var cg := CorvidGull.new(perch)
		add_child(cg)
	# Glow worms — rare, edible; a den network wakes two dark corners per night.
	add_child(GlowWormColony.new())
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
		var pearl: Material = BloomFauna.glow_mat(BloomFauna.PEARL, 0.08)
		var grey: Material = BloomFauna.glow_mat(Color(0.62, 0.66, 0.7), 0.04)
		# Tapered capsule body — reads as a gull, not a brick.
		var body := MeshInstance3D.new()
		var bm := CapsuleMesh.new()
		bm.radius = 0.11
		bm.height = 0.6
		bm.material = pearl
		body.mesh = bm
		add_child(body)
		body.rotation.x = deg_to_rad(90)
		# Head + neck.
		var head := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.1
		hm.height = 0.2
		hm.material = pearl
		head.mesh = hm
		add_child(head)
		head.position = Vector3(0, 0.06, -0.3)
		# Beak.
		var beak := MeshInstance3D.new()
		var km := CylinderMesh.new()
		km.top_radius = 0.005
		km.bottom_radius = 0.035
		km.height = 0.16
		km.material = BloomFauna.glow_mat(Color(0.9, 0.62, 0.15), 0.05)
		beak.mesh = km
		add_child(beak)
		beak.position = Vector3(0, 0.05, -0.42)
		beak.rotation.x = deg_to_rad(-90)
		# Fanned tail.
		var tail := MeshInstance3D.new()
		var tm := PrismMesh.new()
		tm.size = Vector3(0.26, 0.02, 0.3)
		tm.material = grey
		tail.mesh = tm
		add_child(tail)
		tail.position = Vector3(0, 0.02, 0.34)
		tail.rotation.x = deg_to_rad(180)
		_wing_l = _wing(-1, pearl, grey)
		_wing_r = _wing(1, pearl, grey)

	func _wing(side: int, pearl: Material, grey: Material) -> MeshInstance3D:
		# Two-segment wing: inner arm + swept grey primary tips.
		var w := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(0.5, 0.025, 0.26)
		wm.material = pearl
		w.mesh = wm
		add_child(w)
		w.position = Vector3(side * 0.32, 0.05, 0)
		var tip := MeshInstance3D.new()
		var tp := PrismMesh.new()
		tp.size = Vector3(0.5, 0.02, 0.2)
		tp.material = grey
		tip.mesh = tp
		w.add_child(tip)
		tip.position = Vector3(side * 0.42, 0, 0.02)
		tip.rotation.y = deg_to_rad(-28 * side)
		return w

	func _process(delta: float) -> void:
		var day: bool = GameClock.current_phase == GameClock.Phase.DAY \
			or GameClock.current_phase == GameClock.Phase.DAWN
		_leave = move_toward(_leave, 0.0 if day else 1.0, delta * 0.12)
		visible = _leave < 0.98
		if not visible:
			return
		_t += delta * _speed
		Journal.discover_if_near(self, "creature_gull", 35.0)
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
		Journal.discover_if_near(self, "creature_jelly_drifter", 16.0)
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
			Journal.discover_if_near(self, "creature_barnacle", 7.0)
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
		Journal.discover_if_near(_segs[0], "creature_lamp_eel", 24.0)
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
	const COUNT: int = 18
	var _t: float = 0.0
	var _fish: Array[Node3D] = []
	var _mat: StandardMaterial3D

	func _ready() -> void:
		_mat = BloomFauna.glow_mat(Color(0.7, 0.78, 0.8), 0.15)
		for i in range(COUNT):
			# Each fish: a tapered capsule body with a forked tail fin.
			var f := Node3D.new()
			add_child(f)
			var body := MeshInstance3D.new()
			var fm := CapsuleMesh.new()
			fm.radius = 0.035
			fm.height = 0.24
			fm.material = _mat
			body.mesh = fm
			body.rotation.x = deg_to_rad(90)
			f.add_child(body)
			var tail := MeshInstance3D.new()
			var tm := PrismMesh.new()
			tm.size = Vector3(0.11, 0.005, 0.1)
			tm.material = _mat
			tail.mesh = tm
			tail.position = Vector3(0, 0, 0.16)
			tail.rotation.x = deg_to_rad(90)
			f.add_child(tail)
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
		global_position = center
		Journal.discover_if_near(self, "creature_fiddler_shoal", 13.0)
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
		pos.y += sin(_progress * PI) * -6.0
		Journal.discover_if_near(self, "creature_mantle_ray", 90.0)   # dips lowest right over the deck
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
		if _emerge > 0.5:
			Journal.discover_if_near(self, "creature_tide_worm", 5.0)
		_body.scale.y = maxf(_emerge, 0.001)
		_body.visible = _emerge > 0.02
		_body.rotation.x = sin(_t * 1.7) * 0.22 * _emerge
		_body.rotation.z = cos(_t * 1.3) * 0.22 * _emerge


# ------------------------------------------------- Glow Worm
class GlowWorm extends Interactable:
	## A skittish knuckle of Bloom light denned in a dark corner (GDD canon: light
	## and life, never combat). Wakes only on nights its den is picked. It feels
	## footsteps through the plate and sinks back into the den; crouch-walking
	## shrinks its senses and slows the retreat — sneaking is how you catch one.
	const TRIGGER_RADIUS: float = 4.5
	const TRIGGER_RADIUS_CROUCHED: float = 1.8
	const RETREAT_RATE: float = 1.25         # full hide in ~0.8s
	const RETREAT_RATE_CROUCHED: float = 0.5  # slow enough to close in and grab
	const EMERGE_RATE: float = 0.6
	const CATCHABLE_PRESENCE: float = 0.6     # mostly-hidden worms can't be taken

	var _t: float = 0.0
	var _presence: float = 0.0      ## 0 = in the den, 1 = fully emerged
	var _active_tonight: bool = false
	var _respawn_sec: float = 0.0   ## after a grab, counts down through dark phases only
	var _body: Node3D
	var _glow_mat: StandardMaterial3D
	var _col: CollisionShape3D

	func _init() -> void:
		display_name = "Glow Worm"
		var v: Array[String] = ["GRAB"]
		verbs = v

	func _ready() -> void:
		_t = global_position.x * 2.1 + global_position.z
		# Den mouth — a dark disc flush with the plate.
		var hole := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.16
		hm.bottom_radius = 0.16
		hm.height = 0.02
		hm.material = BloomFauna.glow_mat(Color(0.04, 0.05, 0.06), 0.0)
		hole.mesh = hm
		add_child(hole)
		# Body rises out of the den; scale.y is the hide/emerge axis.
		_body = Node3D.new()
		add_child(_body)
		_glow_mat = BloomFauna.glow_mat(BloomFauna.TEAL, 0.0)
		var dim_mat := BloomFauna.glow_mat(BloomFauna.DIM_TEAL, 0.15)
		for i in range(4):
			var seg := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var r: float = 0.09 - i * 0.014
			sm.radius = r
			sm.height = r * 2.0
			sm.material = _glow_mat if i >= 2 else dim_mat
			seg.mesh = sm
			_body.add_child(seg)
			seg.position = Vector3(0, 0.08 + i * 0.13, 0)
		# Small grab target for the interaction ray; disabled whenever hidden
		# or in daylight so there is never an invisible blocker.
		_col = CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.25
		_col.shape = shape
		_col.disabled = true
		add_child(_col)
		_col.position = Vector3(0, 0.25, 0)

	## Colony calls this at dusk: this den is (not) one of tonight's two.
	func set_active(value: bool) -> void:
		_active_tonight = value
		_respawn_sec = 0.0

	func _catchable() -> bool:
		return _active_tonight and _respawn_sec <= 0.0 \
			and BloomFauna.is_dark_phase() and _presence > CATCHABLE_PRESENCE

	## Hidden worms show no prompt and take no ray hits.
	func available_verbs() -> Array[String]:
		if _catchable():
			return verbs
		var none: Array[String] = []
		return none

	func interact(verb: String, _player: Node3D) -> void:
		if verb != "GRAB" or not _catchable():
			return
		if not PlayerState.add_item("glow_worm"):
			return   # pack full — the worm lives another night
		AudioDirector.play_one_shot("splash", global_position, -18.0)   # soft, wet
		Journal.discover("creature_glow_worm")
		_presence = 0.0
		_col.disabled = true
		_respawn_sec = randf_range(90.0, 150.0)   # den re-opens later in the night
		super.interact(verb, _player)

	func _process(delta: float) -> void:
		_t += delta
		var dark: bool = BloomFauna.is_dark_phase()
		if _respawn_sec > 0.0 and dark:
			_respawn_sec -= delta
		var want_out: bool = _active_tonight and dark and _respawn_sec <= 0.0
		var rate: float = EMERGE_RATE if want_out else RETREAT_RATE
		if want_out:
			var player: Node3D = get_tree().get_first_node_in_group("player")
			if player:
				var crouched: bool = player.crouching
				var trigger: float = TRIGGER_RADIUS_CROUCHED if crouched else TRIGGER_RADIUS
				if global_position.distance_to(player.global_position) < trigger:
					want_out = false   # felt you through the plate
					rate = RETREAT_RATE_CROUCHED if crouched else RETREAT_RATE
		_presence = move_toward(_presence, 1.0 if want_out else 0.0, delta * rate)
		_body.scale.y = maxf(_presence, 0.001)
		_body.visible = _presence > 0.02
		_body.rotation.x = sin(_t * 1.9) * 0.18 * _presence
		_body.rotation.z = cos(_t * 1.4) * 0.18 * _presence
		_glow_mat.emission_energy_multiplier = _presence * (1.1 + 0.5 * sin(_t * 2.3))
		_col.disabled = not _catchable()
		if _presence > 0.5:
			Journal.discover_if_near(self, "creature_glow_worm", 7.0)

# ------------------------------------------------- Glow Worm Colony
class GlowWormColony extends Node3D:
	## The den network. Eight dens in the rig's dark corners; each dusk exactly
	## two wake, rolled fresh with our own RNG so the picks move night to night.
	const DENS: Array[Vector3] = [
		Vector3(27.4, 2.02, -4.6),    # under the first stair ramp, tower ground floor
		Vector3(18.7, 2.02, -10.6),   # base of the SE leg where it punches the wet deck
		Vector3(12.5, 2.02, -5.5),    # foot of the pump-room north wall, pipe shadow
		Vector3(10.7, 2.02, -21.2),   # loot room, dark inner corner
		Vector3(22.7, 2.02, -18.4),   # among the tide-line drums
		Vector3(19.0, 2.02, -21.6),   # beside the SPHL gangplank, cradle shadow
		Vector3(8.6, 18.02, -15.0),   # topside, shadow of the pallet stack
		Vector3(-26.0, 18.02, -12.4), # machine shop, gap between the parts bins
	]

	var _worms: Array[GlowWorm] = []
	var _rng := RandomNumberGenerator.new()
	var _last_a: int = -1
	var _last_b: int = -1

	func _ready() -> void:
		_rng.randomize()
		for den in DENS:
			var w := GlowWorm.new()
			add_child(w)
			w.global_position = den
			_worms.append(w)
		GameClock.dusk.connect(_pick_tonights_dens)
		if BloomFauna.is_dark_phase():
			_pick_tonights_dens()   # loaded into an ongoing night

	func _pick_tonights_dens() -> void:
		var a: int = _rng.randi_range(0, _worms.size() - 1)
		var b: int = _rng.randi_range(0, _worms.size() - 2)
		if b >= a:
			b += 1   # distinct pair, uniform over all pairs
		if (a == _last_a and b == _last_b) or (a == _last_b and b == _last_a):
			a = (a + 1) % _worms.size()   # nudge off last night's exact pair
			if a == b:
				a = (a + 1) % _worms.size()
		_last_a = a
		_last_b = b
		for i in range(_worms.size()):
			_worms[i].set_active(i == a or i == b)

# ------------------------------------------------- Epic 4-Eyed Whale
class Epic4EyedWhale extends Node3D:
	var _t: float = 0.0
	var _presence: float = 0.0
	var _flying: bool = false
	var _from: Vector3
	var _to: Vector3
	var _progress: float = 0.0
	var _cooldown: float = 40.0
	var _body_mesh: MeshInstance3D
	var _eye_mats: Array[StandardMaterial3D] = []
	var _fin_mats: Array[StandardMaterial3D] = []

	func _ready() -> void:
		visible = false
		_body_mesh = MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 4.5
		bm.height = 9.0
		var hull_mat := BloomFauna.glow_mat(Color(0.08, 0.25, 0.24), 0.35)
		bm.material = hull_mat
		_body_mesh.mesh = bm
		add_child(_body_mesh)

		# Four glowing eyes — two sets on top, alien and epic
		var eye_color := BloomFauna.TEAL
		for i in range(4):
			var eye := MeshInstance3D.new()
			var em := SphereMesh.new()
			em.radius = 0.35
			em.height = 0.7
			var eye_mat := BloomFauna.glow_mat(eye_color, 1.8)
			_eye_mats.append(eye_mat)
			em.material = eye_mat
			eye.mesh = em
			add_child(eye)
			var side: float = -2.0 if i < 2 else 2.0
			var forward: float = -3.0 + (i % 2) * 4.0
			eye.position = Vector3(side, 3.2 + (i % 2) * 0.8, forward)

		# Six wild fins
		for i in range(6):
			var fin := MeshInstance3D.new()
			var fm := PrismMesh.new()
			fm.size = Vector3(1.2, 2.8, 3.2)
			var fin_mat := BloomFauna.glow_mat(Color(0.15, 0.35, 0.33), 0.5)
			_fin_mats.append(fin_mat)
			fm.material = fin_mat
			fin.mesh = fm
			add_child(fin)
			var y: float = 4.8 if i < 3 else -4.8
			var z: float = -1.5 + (i % 3) * 1.5
			fin.position = Vector3(0, y, z)
			fin.rotation.x = deg_to_rad(45) * (-1 if i < 3 else 1)
			fin.scale = Vector3(0.6, 1.0, 1.0)

	func _process(delta: float) -> void:
		_t += delta
		_presence = move_toward(_presence, 1.0 if GameClock.current_phase == GameClock.Phase.NIGHT else 0.0, delta * 0.08)
		visible = _presence > 0.02

		for mat in _eye_mats:
			mat.emission_energy_multiplier = _presence * (1.5 + 0.8 * sin(_t * 0.8))
		for mat in _fin_mats:
			mat.emission_energy_multiplier = _presence * (0.4 + 0.3 * sin(_t * 1.2))

		if not visible:
			return

		if not _flying:
			if GameClock.current_phase == GameClock.Phase.NIGHT:
				_cooldown -= delta
				if _cooldown <= 0.0:
					_begin_pass()
			return

		_progress += delta / 60.0
		if _progress >= 1.0:
			_flying = false
			visible = false
			_cooldown = randf_range(120.0, 180.0)
			return

		var pos: Vector3 = _from.lerp(_to, _progress)
		pos.y += sin(_progress * PI) * -8.0
		Journal.discover_if_near(self, "creature_epic_whale", 120.0)
		global_position = pos
		look_at(pos + (_to - _from).normalized(), Vector3.UP)

		for i in range(get_child_count()):
			var ch = get_child(i)
			if ch is MeshInstance3D and ch != _body_mesh:
				if i < 5:
					continue
				var fin_idx: int = i - 5
				ch.rotation.z = sin(_t * (1.5 + fin_idx * 0.4)) * (0.6 + fin_idx * 0.15)

	func _begin_pass() -> void:
		_flying = true
		visible = true
		_progress = 0.0
		var angle: float = randf_range(0, TAU)
		var dist: float = 240.0
		var dir := Vector3(cos(angle), 0, sin(angle))
		_from = -dir * dist + Vector3(0, randf_range(45.0, 55.0), 0)
		_to = dir * dist + Vector3(0, randf_range(45.0, 55.0), 0)
		AudioDirector.play_one_shot("groan", global_position, -4.0)

# ------------------------------------------------- Harbor Seal (Bloom)
class HarborSeal extends Node3D:
	## A befriended-able fishing partner (Codex §29). Cruises the water south of
	## the rig, porpoising up to breathe, and by day hauls out to bask on the wet
	## deck edge. Curious, never afraid — it turns to watch a nearby player.
	var _t: float = 0.0
	var _head: Node3D
	var _mat: StandardMaterial3D

	func _ready() -> void:
		_t = randf() * 10.0
		_mat = BloomFauna.glow_mat(Color(0.32, 0.34, 0.38), 0.0)
		_mat.emission_enabled = false
		_mat.roughness = 0.6
		# Body: a fat tapered capsule.
		var body := MeshInstance3D.new()
		var bm := CapsuleMesh.new()
		bm.radius = 0.42
		bm.height = 1.9
		bm.material = _mat
		body.mesh = bm
		body.rotation.x = deg_to_rad(90)
		add_child(body)
		# Head on a short neck.
		_head = Node3D.new()
		add_child(_head)
		_head.position = Vector3(0, 0.12, -1.0)
		var hm := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.3
		hs.height = 0.62
		hs.material = _mat
		hm.mesh = hs
		_head.add_child(hm)
		var snout := MeshInstance3D.new()
		var ss := SphereMesh.new()
		ss.radius = 0.16
		ss.height = 0.34
		ss.material = _mat
		snout.mesh = ss
		snout.position = Vector3(0, -0.05, -0.28)
		_head.add_child(snout)
		# Dark eyes + a couple of whisker lines.
		var eyemat := BloomFauna.glow_mat(Color(0.05, 0.05, 0.06), 0.0)
		for sx in [-0.12, 0.12]:
			var eye := MeshInstance3D.new()
			var es := SphereMesh.new()
			es.radius = 0.06
			es.height = 0.12
			es.material = eyemat
			eye.mesh = es
			eye.position = Vector3(sx, 0.05, -0.2)
			_head.add_child(eye)
		# Fore flippers + tail flippers.
		for side in [-1, 1]:
			var fl := MeshInstance3D.new()
			var fm := PrismMesh.new()
			fm.size = Vector3(0.16, 0.05, 0.6)
			fm.material = _mat
			fl.mesh = fm
			fl.position = Vector3(side * 0.42, -0.1, -0.2)
			fl.rotation.y = deg_to_rad(-25 * side)
			add_child(fl)
		var tail := MeshInstance3D.new()
		var tm := PrismMesh.new()
		tm.size = Vector3(0.7, 0.05, 0.4)
		tm.material = _mat
		tail.mesh = tm
		tail.position = Vector3(0, 0, 1.05)
		add_child(tail)

	func _process(delta: float) -> void:
		_t += delta
		# A long looping patrol south of the rig, near the surface.
		var ang: float = _t * 0.16
		var r: float = 20.0 + sin(_t * 0.1) * 6.0
		var breathe: float = sin(_t * 0.6)          # porpoising rhythm
		var y: float = -0.15 + maxf(breathe, 0.0) * 0.5   # crests above the surface to breathe
		var pos := Vector3(cos(ang) * r * 0.7, y, -34.0 + sin(ang) * r)
		var vel: Vector3 = pos - global_position
		global_position = pos
		if vel.length_squared() > 0.0001:
			look_at(pos + vel, Vector3.UP)
		# Curiosity: if the player is close and on the deck, the head turns to them.
		var player: Node3D = get_tree().get_first_node_in_group("player")
		if player and player.global_position.distance_to(global_position) < 18.0:
			Journal.discover_if_near(self, "creature_seal", 18.0)
			var to_p: Vector3 = player.global_position - _head.global_position
			if to_p.length_squared() > 0.01:
				var flat := Vector3(to_p.x, 0, to_p.z).normalized()
				_head.rotation.y = lerp_angle(_head.rotation.y, atan2(flat.x, flat.z) - rotation.y, delta * 2.0)
		# Body roll as it swims.
		rotation.z = sin(_t * 1.2) * 0.15

# ------------------------------------------------- Lamp Snail constellation
class LampSnail extends Node3D:
	## Wheelbarrow-sized gastropods (Codex §54), shells constellated with
	## bioluminescent spots. By night they drift the rig-leg bases; their glow is
	## visible through the water — the "lean over the rail" wonder-beat.
	var _t: float
	var _base: Vector3
	var _spots: Array[StandardMaterial3D] = []
	var _idx: int

	func _init(idx: int, base: Vector3) -> void:
		_idx = idx
		_base = base
		_t = idx * 1.9

	func _ready() -> void:
		# Shell: a coiled dark dome.
		var shell := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.45
		sm.height = 0.7
		sm.is_hemisphere = true
		sm.material = BloomFauna.glow_mat(Color(0.1, 0.12, 0.14), 0.0)
		shell.mesh = sm
		add_child(shell)
		# The foot beneath.
		var foot := MeshInstance3D.new()
		var fm := CapsuleMesh.new()
		fm.radius = 0.2
		fm.height = 0.9
		fm.material = BloomFauna.glow_mat(Color(0.18, 0.2, 0.22), 0.0)
		foot.mesh = fm
		foot.rotation.x = deg_to_rad(90)
		foot.position.y = -0.15
		add_child(foot)
		# The constellation: glow spots scattered on the shell.
		var rng := RandomNumberGenerator.new()
		rng.seed = 400 + _idx
		for i in range(rng.randi_range(7, 11)):
			var spot := MeshInstance3D.new()
			var pm := SphereMesh.new()
			pm.radius = 0.05
			pm.height = 0.1
			var m := BloomFauna.glow_mat(BloomFauna.TEAL, 2.0)
			_spots.append(m)
			pm.material = m
			spot.mesh = pm
			var u: float = rng.randf() * TAU
			var v: float = rng.randf_range(0.1, 0.95)
			spot.position = Vector3(cos(u) * 0.42 * sqrt(1.0 - v * v), v * 0.42, sin(u) * 0.42 * sqrt(1.0 - v * v))
			add_child(spot)

	func _process(delta: float) -> void:
		_t += delta
		var night: bool = GameClock.current_phase == GameClock.Phase.NIGHT
		var glow: float = 2.0 if night else 0.0
		for i in range(_spots.size()):
			# The constellation twinkles — each spot on its own slow beat.
			_spots[i].emission_energy_multiplier = lerpf(_spots[i].emission_energy_multiplier,
				glow * (0.55 + 0.45 * sin(_t * 0.8 + i * 1.3)), delta * 1.5)
		visible = night or global_position.y > 0.0
		if night:
			Journal.discover_if_near(self, "creature_lamp_snail", 12.0)
		# A slow crawl circling the leg base, just under the surface.
		var ang: float = _t * 0.05 + _idx
		global_position = _base + Vector3(cos(ang) * 1.6, -0.4 + sin(_t * 0.4) * 0.15, sin(ang) * 1.6)
		rotation.y = -ang

# ------------------------------------------------- Corvid-Gull (perched)
class CorvidGull extends Node3D:
	## A Bloom-intelligent gull (Codex §26) perched on a rail, watching. Tilts its
	## head to track the player — the first hint that the birds here are thinking.
	var _t: float
	var _head: Node3D
	var _perch: Vector3

	func _init(perch: Vector3) -> void:
		_perch = perch
		_t = randf() * 6.0

	func _ready() -> void:
		global_position = _perch
		var slate: Material = BloomFauna.glow_mat(Color(0.28, 0.3, 0.34), 0.02)
		var body := MeshInstance3D.new()
		var bm := CapsuleMesh.new()
		bm.radius = 0.13
		bm.height = 0.5
		bm.material = slate
		body.mesh = bm
		body.rotation.x = deg_to_rad(70)
		add_child(body)
		_head = Node3D.new()
		_head.position = Vector3(0, 0.28, -0.14)
		add_child(_head)
		var hm := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.11
		hs.height = 0.22
		hs.material = slate
		hm.mesh = hs
		_head.add_child(hm)
		var beak := MeshInstance3D.new()
		var km := CylinderMesh.new()
		km.top_radius = 0.006
		km.bottom_radius = 0.03
		km.height = 0.14
		km.material = BloomFauna.glow_mat(Color(0.85, 0.75, 0.2), 0.03)
		beak.mesh = km
		beak.position = Vector3(0, 0, -0.14)
		beak.rotation.x = deg_to_rad(-90)
		_head.add_child(beak)
		# A bright, knowing eye.
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.03
		es.height = 0.06
		es.material = BloomFauna.glow_mat(Color(0.95, 0.85, 0.3), 0.6)
		eye.mesh = es
		eye.position = Vector3(0.07, 0.03, -0.05)
		_head.add_child(eye)
		# Legs.
		for sx in [-0.05, 0.05]:
			var leg := MeshInstance3D.new()
			var lm := CylinderMesh.new()
			lm.top_radius = 0.012
			lm.bottom_radius = 0.012
			lm.height = 0.18
			lm.material = BloomFauna.glow_mat(Color(0.8, 0.6, 0.2), 0.02)
			leg.mesh = lm
			leg.position = Vector3(sx, -0.22, 0.02)
			add_child(leg)

	func _process(delta: float) -> void:
		_t += delta
		var day: bool = GameClock.current_phase == GameClock.Phase.DAY \
			or GameClock.current_phase == GameClock.Phase.DAWN
		visible = day
		if not day:
			return
		var player: Node3D = get_tree().get_first_node_in_group("player")
		if player and player.global_position.distance_to(global_position) < 20.0:
			Journal.discover_if_near(self, "creature_corvid_gull", 20.0)
			var to_p: Vector3 = player.global_position - global_position
			var flat := Vector3(to_p.x, 0, to_p.z)
			if flat.length_squared() > 0.01:
				rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), delta * 2.5)
			# A curious head-tilt while it watches.
			_head.rotation.z = sin(_t * 0.7) * 0.35
		else:
			_head.rotation.z = move_toward(_head.rotation.z, 0.0, delta)
		# Occasional preen bob.
		_head.position.y = 0.28 + maxf(sin(_t * 0.5) - 0.7, 0.0) * 0.3
