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
## A life ring mounted FLAT on a wall/rail: a backboard sits flush on the surface
## at `pos`, the ring stands proud in front of it, and the whole thing faces along
## `face_yaw` (degrees; 0 = faces +Z, 180 = faces -Z, 90 = faces +X). Placed on a
## wall face with face_yaw pointing into the open, it never reads edge-on or
## half-embedded. `pos` should be ON the wall face.
static func life_ring(parent: Node3D, pos: Vector3, face_yaw: float = 0.0, takeable: bool = false) -> void:
	var root: Node3D
	if takeable:
		var t := Takeable.new()
		t.item_id = "life_ring"
		t.display_name = "Life Ring"
		parent.add_child(t)
		t.global_position = pos
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.86, 0.86, 0.22)
		shape.shape = box
		shape.position = Vector3(0, 0, 0.1)
		t.add_child(shape)
		root = t
	else:
		root = Node3D.new()
		parent.add_child(root)
		root.global_position = pos
	# `mount` carries the facing: everything is built facing +Z, then swung to face_yaw.
	var mount := Node3D.new()
	root.add_child(mount)
	mount.rotation.y = deg_to_rad(face_yaw)
	# Backboard flush on the wall, so the fixture reads mounted (and hides any seam).
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.5, 0.05)
	bm.material = MatLib.painted_steel()
	board.mesh = bm
	mount.add_child(board)
	board.position = Vector3(0, 0, 0.025)   # front face at z=+0.05, flush-proud
	# The ring standing proud in front of the board — disc in XY, face along +Z.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.22
	tm.outer_radius = 0.38
	tm.material = MatLib.flat(Color(0.9, 0.55, 0.2))
	ring.mesh = tm
	mount.add_child(ring)
	ring.rotation.x = deg_to_rad(90)
	ring.position = Vector3(0, 0, 0.14)     # proud of the board
	# Four pale rope lashings around the face.
	for i in range(4):
		var knot := MeshInstance3D.new()
		var km := BoxMesh.new()
		km.size = Vector3(0.1, 0.1, 0.06)
		km.material = MatLib.flat(Color(0.85, 0.82, 0.7))
		knot.mesh = km
		mount.add_child(knot)
		var a: float = i * TAU / 4.0 + 0.4
		knot.position = Vector3(cos(a) * 0.38, sin(a) * 0.38, 0.14)
	# Two mounting straps from the board across the ring (top + bottom).
	for sy in [0.3, -0.3]:
		var strap := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.12, 0.32, 0.03)
		sm.material = MatLib.dark_metal()
		strap.mesh = sm
		mount.add_child(strap)
		strap.position = Vector3(0, sy, 0.1)

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
		Journal.discover_if_near(self, "place_fire_barrel", 5.0)
		var flicker: float = 2.2 + sin(_t * 9.0) * 0.35 + sin(_t * 23.0) * 0.2
		_light.light_energy = flicker
		_coals.emission_energy_multiplier = flicker * 0.9

## 4. Crane — mast, jib out over the deck, and a hook block that swings in the wind.
## The mast/jib used to be plain boxes and the "hook" a single 0.5x0.7x0.3 block on a
## square cable — pure greybox. Now the mast is a tapered tube with a tie-back strut, the
## jib tip carries a real grooved SHEAVE between cheek plates, the fall is round rope, and
## the hook is a segmented block-and-hook (swivel, cheeks, pin, and a curved point).
class CraneHook extends Node3D:
	var _pivot: Node3D
	var _t: float = 0.0

	static func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		parent.add_child(mi)
		mi.position = pos
		return mi

	static func _cyl(r: float, h: float, mat: Material) -> CylinderMesh:
		var m := CylinderMesh.new()
		m.top_radius = r
		m.bottom_radius = r
		m.height = h
		m.material = mat
		return m

	static func _box_mesh(size: Vector3, mat: Material) -> BoxMesh:
		var m := BoxMesh.new()
		m.size = size
		m.material = mat
		return m

	func _ready() -> void:
		var steel: Material = MatLib.rust_steel()
		var dark: Material = MatLib.dark_metal()
		var galv: Material = MatLib.galvanized()
		# Mast: a tapered tube (was a square 0.8m box), on a small base plate.
		var mm := CylinderMesh.new()
		mm.top_radius = 0.26
		mm.bottom_radius = 0.36
		mm.height = 9.0
		mm.material = steel
		_mesh(self, mm, Vector3(0, 4.5, 0))
		_mesh(self, _box_mesh(Vector3(1.0, 0.2, 1.0), dark), Vector3(0, 0.1, 0))
		# Jib out over the deck, with a diagonal tie back to the mast head so it reads as
		# a braced boom rather than one floating bar.
		_mesh(self, _box_mesh(Vector3(0.34, 0.34, 9.0), steel), Vector3(0, 8.8, -4.2))
		var tie := _mesh(self, _box_mesh(Vector3(0.14, 0.14, 5.6), dark), Vector3(0, 9.5, -3.0))
		tie.rotation.x = deg_to_rad(28.0)
		# --- sheave at the jib tip: two cheek plates and a grooved wheel between them ---
		var tip := Vector3(0, 8.6, -8.2)
		for s in [-0.12, 0.12]:
			_mesh(self, _box_mesh(Vector3(0.06, 0.7, 0.6), dark), tip + Vector3(s, 0, 0))
		var wheel := MeshInstance3D.new()
		var wm := TorusMesh.new()
		wm.inner_radius = 0.16
		wm.outer_radius = 0.28
		wm.material = galv
		wheel.mesh = wm
		add_child(wheel)
		wheel.position = tip
		wheel.rotation.y = deg_to_rad(90)   # wheel plane faces along the jib (swings in Z)
		# --- the swinging block-and-hook, hung from the sheave on a round fall ---
		_pivot = Node3D.new()
		add_child(_pivot)
		_pivot.position = tip
		_mesh(_pivot, _cyl(0.03, 4.2, dark), Vector3(0, -2.1, 0))          # wire rope fall
		var block_y: float = -4.2
		_mesh(_pivot, _box_mesh(Vector3(0.34, 0.42, 0.26), dark), Vector3(0, block_y, 0))  # hook block cheeks
		var pin := _mesh(_pivot, _cyl(0.14, 0.4, galv), Vector3(0, block_y, 0))            # sheave pin
		pin.rotation.z = deg_to_rad(90)
		# Swivel + shank down to the throat.
		_mesh(_pivot, _cyl(0.05, 0.22, galv), Vector3(0, block_y - 0.32, 0))
		var hook_body := StaticBody3D.new()
		_pivot.add_child(hook_body)
		hook_body.position = Vector3(0, block_y - 0.55, 0)
		_mesh(hook_body, _cyl(0.06, 0.4, galv), Vector3(0, 0.1, 0))        # shank
		# The curved point, swept from three short segments back up to a tip.
		var bend := [
			[Vector3(0.0, -0.14, 0.0), 0.0],
			[Vector3(0.11, -0.24, 0.0), 55.0],
			[Vector3(0.24, -0.20, 0.0), 110.0],
			[Vector3(0.30, -0.08, 0.0), 150.0],
		]
		for seg in bend:
			var m := _mesh(hook_body, _box_mesh(Vector3(0.09, 0.16, 0.09), galv), seg[0])
			m.rotation.z = deg_to_rad(seg[1])
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.42, 0.7, 0.3)
		col.shape = shape
		col.position = Vector3(0.1, -0.1, 0)
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

## 7. Emergency red flasher — a battery beacon that PULSES while the grid is dead, so a
## player in the blackout always has a red heartbeat to steer by. When mains power comes
## back it drops to a steady dim standby (the deck lamps take over). NOT a LightZone: the
## dark stays dangerous, this only gives the player something to see BY. Cheap OmniLight,
## shadows off (gl_compat). Call setup() BEFORE add_child (which fires _ready).
class RedFlasher extends Node3D:
	var _light: OmniLight3D
	var _lens: StandardMaterial3D
	var _t: float = 0.0
	var _powered: bool = false
	var _rng: float = 8.0
	var _peak: float = 3.0
	var _scale: float = 1.0
	var _period: float = 1.3

	## rng = light range, peak = flash energy, sz = housing scale, period = seconds/flash.
	func setup(rng: float, peak: float, sz: float = 1.0, period: float = 1.3) -> void:
		_rng = rng
		_peak = peak
		_scale = sz
		_period = period

	func _ready() -> void:
		# Dark housing can on a short stalk, a red lens dome, and a small guard cage.
		var housing := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.13 * _scale
		hm.bottom_radius = 0.15 * _scale
		hm.height = 0.16 * _scale
		hm.material = MatLib.dark_metal()
		housing.mesh = hm
		add_child(housing)
		housing.position.y = 0.08 * _scale
		_lens = StandardMaterial3D.new()
		_lens.albedo_color = Color(0.7, 0.06, 0.05)
		_lens.emission_enabled = true
		_lens.emission = Color(1.0, 0.12, 0.08)
		_lens.emission_energy_multiplier = 5.0
		var lens := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.12 * _scale
		lm.height = 0.2 * _scale
		lm.material = _lens
		lens.mesh = lm
		add_child(lens)
		lens.position.y = 0.2 * _scale
		# Guard ribs over the lens.
		for i in range(3):
			var rib := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(0.015 * _scale, 0.24 * _scale, 0.015 * _scale)
			rm.material = MatLib.dark_metal()
			rib.mesh = rm
			add_child(rib)
			var a: float = i * PI / 3.0
			rib.position = Vector3(cos(a) * 0.13 * _scale, 0.2 * _scale, sin(a) * 0.13 * _scale)
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.14, 0.1)
		_light.omni_range = _rng
		_light.light_energy = _peak
		_light.shadow_enabled = false
		_light.light_volumetric_fog_energy = 1.4
		add_child(_light)
		_light.position.y = 0.2 * _scale
		PowerGrid.circuit_powered.connect(func(id: String) -> void:
			if id == "topside_floodlights":
				_powered = true)
		PowerGrid.circuit_lost.connect(func(id: String) -> void:
			if id == "topside_floodlights":
				_powered = false)

	func _process(delta: float) -> void:
		_t += delta
		if _powered:
			# Steady dim standby once the deck is lit.
			_light.light_energy = 0.35
			_lens.emission_energy_multiplier = 0.8
			return
		# A double-blink heartbeat: bright on the first third of the period.
		var ph: float = fmod(_t, _period)
		var on: bool = ph < _period * 0.28
		_light.light_energy = _peak if on else 0.0
		_lens.emission_energy_multiplier = 6.0 if on else 0.35
