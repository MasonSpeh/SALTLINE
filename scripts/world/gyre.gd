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

# -- shader-matched wave math (keep in sync with ocean_water.gdshader) -------

static func _warp(p: Vector2, t: float) -> Vector2:
	return p + 4.0 * Vector2(sin(p.y * 0.021 + t * 0.06), sin(p.x * 0.017 - t * 0.05))

static func wave_height(raw_p: Vector2, t: float) -> float:
	var p: Vector2 = _warp(raw_p, t)
	var h: float = 0.0
	h += 0.5 * sin(Vector2(1.0, 0.32).normalized().dot(p) * (TAU / 64.0) + t * 0.9)
	h += 0.25 * sin(Vector2(-0.62, 1.0).normalized().dot(p) * (TAU / 24.0) + t * 1.4)
	h += 0.12 * sin(Vector2(0.41, -1.0).normalized().dot(p) * (TAU / 10.0) + t * 2.1)
	h += 0.3 * sin(Vector2(-0.9, -0.44).normalized().dot(p) * (TAU / 110.0) + t * 0.55)
	return h

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
		var qm := BoxMesh.new()
		qm.size = Vector3(_rng.randf_range(1.6, 3.4), 0.02, 0.3)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.9, 0.9, 0.32)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qm.material = m
		streak.mesh = qm
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
		s.global_position = CENTER + Vector3(cos(a) * r, wave_height(Vector2(CENTER.x + cos(a) * r, CENTER.z + sin(a) * r), t) + 0.06, sin(a) * r)
		s.rotation.y = -a

## One piece of flotsam riding the gyre. Hook it to claim its resource.
class FloatingDebris extends Node3D:
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
			global_position.y = Gyre.wave_height(Vector2(global_position.x, global_position.z), t2) * 0.85 + 0.08
			return
		# Spiral: angular speed rises toward the eye (conservation of drama).
		var speed: float = 0.06 + 1.6 / maxf(gyre_radius, 3.0)
		gyre_angle += speed * delta
		gyre_radius = maxf(Gyre.EYE_RADIUS + sin(gyre_angle * 0.5) * 1.2, gyre_radius - delta * 0.11)
		var t: float = Gyre.water_time()
		var x: float = Gyre.CENTER.x + cos(gyre_angle) * gyre_radius
		var z: float = Gyre.CENTER.z + sin(gyre_angle) * gyre_radius
		global_position = Vector3(x, Gyre.wave_height(Vector2(x, z), t) * 0.85 + 0.08, z)
		rotation.y = -gyre_angle - PI * 0.5
		rotation.x = sin(t * 0.9 + gyre_angle) * 0.08

	func collect(player: Node3D) -> void:
		PlayerState.add_item(item_id)
		var hud: Node = player.get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("Hauled in: %s" % display_name)
		queue_free()
