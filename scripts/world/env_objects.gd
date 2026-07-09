class_name EnvObjects extends RefCounted
## Six environmental object builders for the rig. Static factories keep RigBuilder
## readable; the animated ones (fire barrel, crane hook, beacon, vent fan) are
## self-contained inner classes with their own _process.

## 1. Oil drum — a loose physics prop you can carry, throw, and knock around.
static func oil_drum(parent: Node3D, pos: Vector3) -> PhysProp:
	var drum := PhysProp.new()
	parent.add_child(drum)
	drum.global_position = pos
	drum.mass = 2.5
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.32
	cm.bottom_radius = 0.32
	cm.height = 0.9
	cm.material = MatLib.rusty_metal()
	mi.mesh = cm
	drum.add_child(mi)
	# Rim rings read as "drum" even in greybox.
	for ry in [-0.28, 0.0, 0.28]:
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.335
		rm.bottom_radius = 0.335
		rm.height = 0.04
		rm.material = MatLib.dark_metal()
		ring.mesh = rm
		drum.add_child(ring)
		ring.position.y = ry
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.34
	shape.height = 0.92
	col.shape = shape
	drum.add_child(col)
	return drum

## 2. Life ring — pearl torus on a rail post; one variant is takeable.
static func life_ring(parent: Node3D, pos: Vector3, takeable: bool = false) -> void:
	var root: Node3D
	if takeable:
		var t := Takeable.new()
		t.item_id = "life_ring"
		t.display_name = "Life Ring"
		parent.add_child(t)
		t.global_position = pos
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.8, 0.8, 0.3)
		shape.shape = box
		t.add_child(shape)
		root = t
	else:
		root = Node3D.new()
		parent.add_child(root)
		root.global_position = pos
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.22
	tm.outer_radius = 0.38
	tm.material = MatLib.flat(Color(0.9, 0.55, 0.2))
	ring.mesh = tm
	root.add_child(ring)
	ring.rotation.x = deg_to_rad(90)
	# Rope loops (four pale arcs, faked with small boxes).
	for i in range(4):
		var knot := MeshInstance3D.new()
		var km := BoxMesh.new()
		km.size = Vector3(0.1, 0.1, 0.06)
		km.material = MatLib.flat(Color(0.85, 0.82, 0.7))
		knot.mesh = km
		root.add_child(knot)
		var a: float = i * TAU / 4.0 + 0.4
		knot.position = Vector3(cos(a) * 0.38, sin(a) * 0.38, 0)

## 3. Fire barrel — early warmth before the power puzzle; flickering light + heat zone.
class FireBarrel extends Node3D:
	var _light: OmniLight3D
	var _coals: StandardMaterial3D
	var _t: float = 0.0

	func _ready() -> void:
		var body := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.36
		cm.bottom_radius = 0.36
		cm.height = 1.0
		cm.material = MatLib.dark_metal()
		body.mesh = cm
		add_child(body)
		body.position.y = 0.5
		var col := CollisionShape3D.new()   # parented to a StaticBody so you can't walk through it
		var sb := StaticBody3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.38
		shape.height = 1.0
		col.shape = shape
		sb.add_child(col)
		add_child(sb)
		col.position.y = 0.5
		_coals = StandardMaterial3D.new()
		_coals.albedo_color = Color(1.0, 0.45, 0.1)
		_coals.emission_enabled = true
		_coals.emission = Color(1.0, 0.5, 0.12)
		_coals.emission_energy_multiplier = 2.0
		var glow := MeshInstance3D.new()
		var gm := CylinderMesh.new()
		gm.top_radius = 0.3
		gm.bottom_radius = 0.3
		gm.height = 0.08
		gm.material = _coals
		glow.mesh = gm
		add_child(glow)
		glow.position.y = 1.0
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.6, 0.25)
		_light.omni_range = 9.0
		_light.light_energy = 2.2
		_light.light_volumetric_fog_energy = 1.6
		_light.shadow_enabled = true
		add_child(_light)
		_light.position.y = 1.5
		var heat := WarmthZone.new()
		heat.mode = 1
		heat.setup(Vector3(5, 3, 5))
		add_child(heat)
		heat.position.y = 1.2

	func _process(delta: float) -> void:
		_t += delta
		var flicker: float = 2.2 + sin(_t * 9.0) * 0.35 + sin(_t * 23.0) * 0.2
		_light.light_energy = flicker
		_coals.emission_energy_multiplier = flicker * 0.9

## 4. Crane — mast, jib out over the deck, and a hook that swings in the wind.
class CraneHook extends Node3D:
	var _pivot: Node3D
	var _t: float = 0.0

	func _ready() -> void:
		var mast := MeshInstance3D.new()
		var mm := BoxMesh.new()
		mm.size = Vector3(0.8, 9.0, 0.8)
		mm.material = MatLib.rust_steel()
		mast.mesh = mm
		add_child(mast)
		mast.position.y = 4.5
		var jib := MeshInstance3D.new()
		var jm := BoxMesh.new()
		jm.size = Vector3(0.5, 0.5, 9.0)
		jm.material = MatLib.rust_steel()
		jib.mesh = jm
		add_child(jib)
		jib.position = Vector3(0, 8.8, -4.2)
		# The swinging assembly hangs from the jib tip.
		_pivot = Node3D.new()
		add_child(_pivot)
		_pivot.position = Vector3(0, 8.5, -8.0)
		var cable := MeshInstance3D.new()
		var cbm := BoxMesh.new()
		cbm.size = Vector3(0.06, 4.5, 0.06)
		cbm.material = MatLib.dark_metal()
		cable.mesh = cbm
		_pivot.add_child(cable)
		cable.position.y = -2.25
		var hook_body := StaticBody3D.new()
		_pivot.add_child(hook_body)
		hook_body.position.y = -4.7
		var hook := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.5, 0.7, 0.3)
		hm.material = MatLib.dark_metal()
		hook.mesh = hm
		hook_body.add_child(hook)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.5, 0.7, 0.3)
		col.shape = shape
		hook_body.add_child(col)

	func _process(delta: float) -> void:
		_t += delta
		# Slow pendulum with a slight cross-swing: wind, not machinery.
		_pivot.rotation.x = sin(_t * 0.5) * 0.06
		_pivot.rotation.z = sin(_t * 0.34 + 1.2) * 0.05

## 5. Antenna array — dishes and poles with a blinking red aircraft beacon.
class AntennaArray extends Node3D:
	var _beacon_mat: StandardMaterial3D
	var _beacon_light: OmniLight3D
	var _t: float = 0.0

	func _ready() -> void:
		for spec in [[Vector3(-0.8, 0, 0.4), 3.6], [Vector3(0.7, 0, -0.3), 2.6]]:
			var pole := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.04
			pm.bottom_radius = 0.07
			pm.height = spec[1]
			pm.material = MatLib.dark_metal()
			pole.mesh = pm
			add_child(pole)
			pole.position = spec[0] + Vector3(0, spec[1] * 0.5, 0)
		var dish := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = 0.55
		dm.bottom_radius = 0.1
		dm.height = 0.25
		dm.material = MatLib.painted_steel()
		dish.mesh = dm
		add_child(dish)
		dish.position = Vector3(0.7, 2.0, -0.3)
		dish.rotation.x = deg_to_rad(55)
		_beacon_mat = StandardMaterial3D.new()
		_beacon_mat.albedo_color = Color(0.8, 0.1, 0.08)
		_beacon_mat.emission_enabled = true
		_beacon_mat.emission = Color(1.0, 0.12, 0.08)
		var bulb := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.12
		bm.height = 0.24
		bm.material = _beacon_mat
		bulb.mesh = bm
		add_child(bulb)
		bulb.position = Vector3(-0.8, 3.75, 0.4)
		_beacon_light = OmniLight3D.new()
		_beacon_light.light_color = Color(1.0, 0.15, 0.1)
		_beacon_light.omni_range = 7.0
		add_child(_beacon_light)
		_beacon_light.position = bulb.position

	func _process(delta: float) -> void:
		_t += delta
		var on: bool = fmod(_t, 2.4) < 0.25
		_beacon_mat.emission_energy_multiplier = 5.0 if on else 0.05
		_beacon_light.light_energy = 2.5 if on else 0.0

## 6. Vent fan — roof unit; idles in the wind, spins up when the grid is live.
class VentFan extends Node3D:
	var _blades: Node3D
	var _speed: float = 0.8

	func _ready() -> void:
		var housing := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.55
		hm.bottom_radius = 0.55
		hm.height = 0.5
		hm.material = MatLib.painted_steel()
		housing.mesh = hm
		add_child(housing)
		housing.position.y = 0.25
		_blades = Node3D.new()
		add_child(_blades)
		_blades.position.y = 0.42
		for i in range(2):
			var blade := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.9, 0.04, 0.16)
			bm.material = MatLib.dark_metal()
			blade.mesh = bm
			_blades.add_child(blade)
			blade.rotation.y = i * PI * 0.5
		PowerGrid.circuit_powered.connect(func(id: String) -> void:
			if id == "topside_floodlights":
				_speed = 9.0)
		PowerGrid.circuit_lost.connect(func(id: String) -> void:
			if id == "topside_floodlights":
				_speed = 0.8)

	func _process(delta: float) -> void:
		_blades.rotation.y += _speed * delta
