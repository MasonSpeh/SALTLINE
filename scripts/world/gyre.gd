class_name Gyre extends Node3D
## The rotational gyre: a slow whirl in the water south of the rig where the current
## collects what the sea carries. Debris spawns on the outer ring, spirals inward,
## and lingers turning in the eye — capture it with the throwing hook for resources.
## Wave math mirrors ocean_water.gdshader so debris rides the actual swell.

const CENTER := Vector3(0, 0, -52)
const EYE_RADIUS: float = 6.5
const SPAWN_RADIUS_MIN: float = 16.0
const SPAWN_RADIUS_MAX: float = 30.0
const MAX_DEBRIS: int = 14

const DEBRIS_TYPES := [
	{"id": "driftwood", "name": "Driftwood Plank", "weight": 3},
	{"id": "scrap_metal", "name": "Scrap Metal", "weight": 2},
	{"id": "rope", "name": "Rope Coil", "weight": 2},
	{"id": "tarp", "name": "Canvas Tarp", "weight": 1},
	{"id": "sealed_tin", "name": "Sealed Tin", "weight": 2},
	{"id": "kelp_bundle", "name": "Kelp Bundle", "weight": 3},
]

var _rng := RandomNumberGenerator.new()
var _sheen_mat: StandardMaterial3D

# -- shader-matched wave math (keep in sync with ocean_water.gdshader) --------
# Gerstner sum, mirrored so floating debris rides the SAME swell the water shows.
# Gerstner displaces horizontally toward crests, so debris needs that offset too or
# it drifts off the peak it should sit on.
#
# SEA STATE IS LIVE. This used to mirror the ocean at a hard-coded calm 0.4 while the
# shader's sea_state was driven up toward 1.0 by StormSystem. Amplitude scales as
# 0.18 + 0.92*ss, so a full squall drew waves TWICE the height this math believed in:
# every plank hung in mid-air over a trough, and main.gd's "is the camera underwater"
# test (same function) missed the wave tops. SunController.set_sea_state() now feeds
# the same value it hands the shader, so the CPU and GPU seas are the one sea.
const G_WAVE: float = 9.81
const WAVE_SEA_STATE: float = 0.4   # calm baseline; == SunController.BASE_SEA_STATE

static var _sea_state: float = WAVE_SEA_STATE

## The sea state the wave math is currently mirroring (SunController drives this).
static func sea_state() -> float:
	return _sea_state

static func set_sea_state(v: float) -> void:
	_sea_state = clampf(v, 0.0, 1.0)
const W_DIR: Array[Vector2] = [
	Vector2(0.990, 0.139), Vector2(0.995, -0.105), Vector2(0.951, 0.309),
	Vector2(0.866, 0.500), Vector2(0.940, -0.342), Vector2(0.695, 0.719),
	Vector2(0.788, -0.616), Vector2(0.500, 0.866), Vector2(0.574, -0.819),
	Vector2(0.259, 0.966), Vector2(0.342, -0.940),
]
const W_LEN: Array[float] = [90.0, 62.0, 48.0, 24.0, 16.0, 11.0, 8.5, 5.5, 3.8, 2.6, 1.7]
const W_AMP: Array[float] = [1.40, 1.05, 0.82, 0.52, 0.40, 0.29, 0.22, 0.15, 0.11, 0.078, 0.052]
const W_STEEP: Array[float] = [0.62, 0.68, 0.72, 0.80, 0.82, 0.85, 0.85, 0.90, 0.90, 0.92, 0.95]
const SET_DIR_A: Vector2 = Vector2(0.97, 0.24)
const SET_DIR_B: Vector2 = Vector2(0.20, -0.98)

static func _warp(p: Vector2, t: float) -> Vector2:
	return p + 3.0 * Vector2(sin(p.y * 0.018 + t * 0.05), sin(p.x * 0.015 - t * 0.04))

## Full Gerstner displacement at world xz: (horizontal_x, surface_height, horizontal_z).
static func wave_offset(raw_p: Vector2, t: float) -> Vector3:
	var w: Vector2 = _warp(raw_p, t)
	var ss: float = _sea_state
	var amp_scale: float = 0.18 + 0.92 * ss
	var steep_scale: float = 0.35 + 0.65 * ss
	var dx: float = 0.0
	var dz: float = 0.0
	var h: float = 0.0
	for i in range(11):
		var dir: Vector2 = W_DIR[i]
		var k: float = TAU / W_LEN[i]
		var omega: float = sqrt(G_WAVE * k)
		var a: float = W_AMP[i] * amp_scale
		if i < 3:
			var sd: Vector2 = SET_DIR_B if i == 1 else SET_DIR_A
			var env: float = sd.dot(raw_p) * 0.010 - t * (0.045 + 0.02 * float(i))
			a *= 0.55 + 0.45 * sin(env)
		var steep_eff: float = W_STEEP[i] * steep_scale
		var qa: float = steep_eff / (k * 11.0)
		var phase: float = k * dir.dot(w) - omega * t
		var c: float = cos(phase)
		dx += qa * dir.x * c
		dz += qa * dir.y * c
		h += a * sin(phase)
	return Vector3(dx, h, dz)

static func wave_height(raw_p: Vector2, t: float) -> float:
	return wave_offset(raw_p, t).y

static func water_time() -> float:
	return Time.get_ticks_msec() * 0.001

func _ready() -> void:
	_rng.seed = 90210
	for i in range(MAX_DEBRIS):
		_spawn_debris(true)
	_build_surface_hints()

func _process(_delta: float) -> void:
	var _pl: Node3D = get_tree().get_first_node_in_group("player")
	if _pl and _pl.global_position.distance_to(CENTER) < 45.0:
		Journal.discover("place_gyre")
	# The Bloom gathers faintly under the eye at night.
	var want: float = 0.0
	if GameClock.current_phase == GameClock.Phase.NIGHT:
		want = 0.6 + 0.25 * sin(water_time() * 0.7)
	elif GameClock.current_phase == GameClock.Phase.DUSK:
		want = 0.2
	_sheen_mat.emission_energy_multiplier = lerpf(_sheen_mat.emission_energy_multiplier, want, _delta * 1.5)
	# By day the eye is just faintly slicked water; the teal belongs to the night.
	_sheen_mat.albedo_color.a = 0.04 + _sheen_mat.emission_energy_multiplier * 0.22
	# Keep the eye stocked.
	if get_tree().get_nodes_in_group("floating_debris").size() < MAX_DEBRIS and _rng.randf() < 0.002:
		_spawn_debris(false)

func _spawn_debris(anywhere: bool) -> void:
	var spec: Dictionary = _pick_type()
	var d := FloatingDebris.new()
	d.item_id = spec["id"]
	d.display_name = spec["name"]
	add_child(d)
	var angle: float = _rng.randf_range(0, TAU)
	var radius: float = _rng.randf_range(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX) if not anywhere \
		else _rng.randf_range(EYE_RADIUS, SPAWN_RADIUS_MAX)
	d.gyre_angle = angle
	d.gyre_radius = radius
	d.global_position = CENTER + Vector3(cos(angle) * radius, 0.2, sin(angle) * radius)

func _pick_type() -> Dictionary:
	var total: int = 0
	for t in DEBRIS_TYPES:
		total += t["weight"]
	var roll: int = _rng.randi_range(1, total)
	for t in DEBRIS_TYPES:
		roll -= t["weight"]
		if roll <= 0:
			return t
	return DEBRIS_TYPES[0]

func _build_surface_hints() -> void:
	# Foam streaks turning with the current — the gyre is readable from the deck.
	for i in range(9):
		var streak := MeshInstance3D.new()
		# Soft-edged sprites lying ON the water, not lit boxes floating in it. As solid
		# alpha BoxMeshes these caught the moonlight as hard pale rectangles and read from
		# a distance as litter scattered over the night sea — the streaks are meant to be
		# foam the current has drawn out, so they get a radial falloff, no shading, and a
		# lower alpha. Flat quad rather than a box: nothing here has thickness.
		var qm := QuadMesh.new()
		qm.size = Vector2(_rng.randf_range(1.6, 3.4), _rng.randf_range(0.5, 0.9))
		qm.material = MatLib.soft_mote(Color(0.85, 0.9, 0.9, 0.20), false)
		streak.mesh = qm
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		streak.add_to_group("gyre_streaks")
		add_child(streak)
		streak.set_meta("angle", _rng.randf_range(0, TAU))
		streak.set_meta("radius", _rng.randf_range(4.0, 12.0))
	# Faint teal sheen in the eye — at night the Bloom answers the turning water.
	_sheen_mat = StandardMaterial3D.new()
	_sheen_mat.albedo_color = Color(0.2, 0.9, 0.85, 0.18)
	_sheen_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sheen_mat.emission_enabled = true
	_sheen_mat.emission = Color(0.2, 0.9, 0.85)
	_sheen_mat.emission_energy_multiplier = 0.0
	var sheen := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = EYE_RADIUS
	sm.bottom_radius = EYE_RADIUS
	sm.height = 0.02
	sm.material = _sheen_mat
	sheen.mesh = sm
	add_child(sheen)
	sheen.global_position = CENTER + Vector3(0, 0.05, 0)

func _physics_process(delta: float) -> void:
	var t: float = water_time()
	for s in get_tree().get_nodes_in_group("gyre_streaks"):
		var a: float = s.get_meta("angle") + delta * 0.25
		s.set_meta("angle", a)
		var r: float = s.get_meta("radius")
		var sx: float = CENTER.x + cos(a) * r
		var sz: float = CENTER.z + sin(a) * r
		var so: Vector3 = wave_offset(Vector2(sx, sz), t)
		s.global_position = Vector3(sx + so.x, so.y + 0.06, sz + so.z)
		# QuadMesh faces +Z, so lay it flat on the water (-90 about X) then turn it to
		# follow the current. It used to be a BoxMesh, which needed no such pitch.
		s.rotation = Vector3(-PI * 0.5, -a, 0.0)

## One piece of flotsam riding the gyre. Hook it to claim its resource.
class FloatingDebris extends Node3D:
	## How proud of the surface the flotsam floats. A CONSTANT, because that is what a
	## draft is. This used to be `wave_height * 0.9 + 0.06`, which scales the error with
	## the swell: harmless in a calm 1.5 m sea, but a squall doubles the wave height and
	## the same 10% sinks every plank a third of a metre into the face of each crest.
	const DRAFT: float = 0.05

	var item_id: String = "driftwood"
	var display_name: String = "Debris"
	var gyre_angle: float = 0.0
	var gyre_radius: float = 20.0
	var hooked_by: Node3D = null

	func _ready() -> void:
		add_to_group("floating_debris")
		_build_visual()

	func _build_visual() -> void:
		match item_id:
			"driftwood":
				_mesh_box(Vector3(1.3, 0.14, 0.32), Color(0.5, 0.4, 0.28))
			"scrap_metal":
				var m := _mesh_box(Vector3(0.7, 0.2, 0.5), Color(0.35, 0.36, 0.4))
				m.rotation.z = 0.3
			"rope":
				var torus := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.14
				tm.outer_radius = 0.34
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(0.75, 0.68, 0.5)
				tm.material = mat
				torus.mesh = tm
				add_child(torus)
				torus.rotation.x = deg_to_rad(90)
			"tarp":
				_mesh_box(Vector3(0.9, 0.08, 0.7), Color(0.65, 0.68, 0.62))
			"sealed_tin":
				var tin := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.16
				cm.bottom_radius = 0.16
				cm.height = 0.22
				var mat2 := StandardMaterial3D.new()
				mat2.albedo_color = Color(0.66, 0.62, 0.5)
				mat2.metallic = 0.4
				cm.material = mat2
				tin.mesh = cm
				add_child(tin)
			"kelp_bundle":
				for i in range(3):
					var blob := MeshInstance3D.new()
					var sm := SphereMesh.new()
					sm.radius = 0.16 - i * 0.03
					sm.height = sm.radius * 2.0
					var mat3 := StandardMaterial3D.new()
					mat3.albedo_color = Color(0.15, 0.4, 0.3)
					mat3.emission_enabled = true
					mat3.emission = Color(0.2, 0.9, 0.85)
					mat3.emission_energy_multiplier = 0.4
					sm.material = mat3
					blob.mesh = sm
					add_child(blob)
					blob.position = Vector3(i * 0.2 - 0.2, 0.02, sin(i * 2.1) * 0.1)

	func _mesh_box(size: Vector3, color: Color) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.85
		bm.material = mat
		mi.mesh = bm
		add_child(mi)
		return mi

	func _physics_process(delta: float) -> void:
		if hooked_by:
			# In tow: trail just behind the hook.
			var target: Vector3 = hooked_by.global_position
			global_position = global_position.lerp(Vector3(target.x, global_position.y, target.z), delta * 8.0)
			var t2: float = Gyre.water_time()
			global_position.y = Gyre.wave_offset(Vector2(global_position.x, global_position.z), t2).y + DRAFT
			return
		# Spiral: angular speed rises toward the eye (conservation of drama).
		var speed: float = 0.06 + 1.6 / maxf(gyre_radius, 3.0)
		gyre_angle += speed * delta
		gyre_radius = maxf(Gyre.EYE_RADIUS + sin(gyre_angle * 0.5) * 1.2, gyre_radius - delta * 0.11)
		var t: float = Gyre.water_time()
		var x: float = Gyre.CENTER.x + cos(gyre_angle) * gyre_radius
		var z: float = Gyre.CENTER.z + sin(gyre_angle) * gyre_radius
		var wo: Vector3 = Gyre.wave_offset(Vector2(x, z), t)
		global_position = Vector3(x + wo.x, wo.y + DRAFT, z + wo.z)
		rotation.y = -gyre_angle - PI * 0.5
		rotation.x = sin(t * 0.9 + gyre_angle) * 0.08

	func collect(player: Node3D) -> void:
		PlayerState.add_item(item_id)
		var hud: Node = player.get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("Hauled in: %s" % display_name)
		queue_free()
