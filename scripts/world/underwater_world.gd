extends Node3D
## The ocean below the wave line: the rig's legs keep going down, kelp sways on
## the moorings, marine snow drifts, bubbles rise off the steel — and the fish
## you can actually catch swim their real depth bands (schools are spawned from
## data/fish.json, so what you SEE under the surface is what's biting above it).
## Best appreciated in fly mode or falling in; diving proper is a later phase.

const FISH := preload("res://scripts/world/fish_table.gd")

const LEGS := [Vector3(-22, 0, -12), Vector3(22, 0, -12), Vector3(-22, 0, 12), Vector3(22, 0, 12)]
const DEPTH_BAND := {"surface": -1.2, "mid": -4.5, "deep": -9.5}

var _kelp: Array[Node3D] = []
var _schools: Array = []   # [{root, fish[], def, band_y, center, t}]
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 7411
	_leg_extensions()
	_kelp_forest()
	_marine_snow()
	_bubble_vents()
	_mooring_chains()
	_spawn_schools()

# ---------------------------------------------------------------- structure

## The caissons don't stop at the pontoons — carry them down into the dark so
## looking below the surface reads as architecture, not a void.
func _leg_extensions() -> void:
	var deep_conc := StandardMaterial3D.new()
	deep_conc.albedo_color = Color(0.3, 0.36, 0.36)
	deep_conc.roughness = 0.95
	for leg in LEGS:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(6.0, 20.0, 6.0)
		bm.material = deep_conc
		mi.mesh = bm
		add_child(mi)
		mi.position = Vector3(leg.x, -13.0, leg.z)

func _kelp_forest() -> void:
	var kelp_mat := StandardMaterial3D.new()
	kelp_mat.albedo_color = Color(0.14, 0.38, 0.28)
	kelp_mat.roughness = 0.9
	var tip_mat := StandardMaterial3D.new()
	tip_mat.albedo_color = Color(0.2, 0.6, 0.45)
	tip_mat.emission_enabled = true
	tip_mat.emission = Color(0.2, 0.9, 0.85)
	tip_mat.emission_energy_multiplier = 0.25
	for leg in LEGS:
		for i in range(6):
			var a: float = _rng.randf_range(0, TAU)
			var r: float = _rng.randf_range(3.6, 5.4)
			var base := Vector3(leg.x + cos(a) * r, -12.0, leg.z + sin(a) * r)
			var strand := Node3D.new()
			add_child(strand)
			strand.position = base
			var h: float = _rng.randf_range(7.0, 11.0)
			var segs: int = 4
			for s in range(segs):
				var blade := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.22 - s * 0.03, h / segs + 0.15, 0.05)
				bm.material = tip_mat if s == segs - 1 else kelp_mat
				blade.mesh = bm
				strand.add_child(blade)
				blade.position = Vector3(0, (s + 0.5) * h / segs, 0)
				blade.rotation.y = _rng.randf_range(0, TAU)
			strand.set_meta("sway", _rng.randf_range(0.8, 1.4))
			strand.set_meta("phase", _rng.randf_range(0, TAU))
			_kelp.append(strand)

## Marine snow: slow drifting particulate that sells the water as a medium.
func _marine_snow() -> void:
	var snow := GPUParticles3D.new()
	snow.amount = 700
	snow.lifetime = 14.0
	snow.preprocess = 14.0
	snow.local_coords = false
	snow.visibility_aabb = AABB(Vector3(-45, -16, -45), Vector3(90, 16, 90))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(40, 7, 40)
	mat.gravity = Vector3(0.25, -0.12, 0.18)   # the gyre's slow underwater set
	mat.initial_velocity_min = 0.02
	mat.initial_velocity_max = 0.1
	snow.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	var qm := StandardMaterial3D.new()
	qm.albedo_color = Color(0.75, 0.85, 0.85, 0.5)
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = qm
	snow.draw_pass_1 = quad
	add_child(snow)
	snow.position = Vector3(0, -8, 0)

func _bubble_vents() -> void:
	for leg in [LEGS[1], LEGS[2]]:
		var bub := GPUParticles3D.new()
		bub.amount = 60
		bub.lifetime = 6.0
		bub.preprocess = 6.0
		bub.local_coords = false
		bub.visibility_aabb = AABB(Vector3(-3, 0, -3), Vector3(6, 14, 6))
		var mat := ParticleProcessMaterial.new()
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		mat.emission_sphere_radius = 0.6
		mat.gravity = Vector3(0, 1.9, 0)
		mat.initial_velocity_min = 0.2
		mat.initial_velocity_max = 0.5
		bub.process_material = mat
		var quad := QuadMesh.new()
		quad.size = Vector2(0.05, 0.05)
		var qm := StandardMaterial3D.new()
		qm.albedo_color = Color(0.85, 0.95, 0.95, 0.6)
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		quad.material = qm
		bub.draw_pass_1 = quad
		add_child(bub)
		bub.position = Vector3(leg.x + 2.2, -13.5, leg.z - 1.5)

func _mooring_chains() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.19, 0.17)
	mat.roughness = 0.9
	for leg in LEGS:
		var dir := Vector3(signf(leg.x), 0, signf(leg.z)).normalized()
		var from := Vector3(leg.x, -2.5, leg.z) + dir * 3.2
		var to := from + dir * 26.0 + Vector3(0, -20.0, 0)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.09
		cm.bottom_radius = 0.09
		cm.height = from.distance_to(to)
		cm.material = mat
		mi.mesh = cm
		add_child(mi)
		mi.global_position = (from + to) * 0.5
		mi.look_at_from_position(mi.global_position, to, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)

# ---------------------------------------------------------------- schools

## Spawn a visible school for every species that declares one — same table the
## rod rolls. Depth band, size, count, tint, and active hours all come along.
func _spawn_schools() -> void:
	for id in FISH.all():
		var def: Dictionary = FISH.all()[id]
		var school: Dictionary = def.get("school", {})
		if int(school.get("count", 0)) <= 0:
			continue
		var root := Node3D.new()
		add_child(root)
		var tint_arr: Array = school["tint"]
		var tint := Color(tint_arr[0], tint_arr[1], tint_arr[2])
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mat.roughness = 0.6
		if id == "fish_herring":   # the lantern shoal glows, canon
			mat.emission_enabled = true
			mat.emission = Color(0.2, 0.9, 0.85)
			mat.emission_energy_multiplier = 0.5
		var size: float = float(school["size"])
		var members: Array = []
		for i in range(int(school["count"])):
			var f := Node3D.new()
			root.add_child(f)
			var body := MeshInstance3D.new()
			var bm := CapsuleMesh.new()
			bm.radius = 0.05 * size
			bm.height = 0.34 * size
			bm.material = mat
			body.mesh = bm
			body.rotation.x = deg_to_rad(90)
			f.add_child(body)
			var tail := MeshInstance3D.new()
			var tm := PrismMesh.new()
			tm.size = Vector3(0.12, 0.01, 0.1) * size
			tm.material = mat
			tail.mesh = tm
			tail.position = Vector3(0, 0, 0.22 * size)
			tail.rotation.x = deg_to_rad(90)
			f.add_child(tail)
			members.append(f)
		var band_y: float = DEPTH_BAND.get(def.get("depth", "mid"), -4.5)
		_schools.append({
			"root": root, "fish": members, "def": def, "id": id,
			"band_y": band_y, "size": size,
			"center": Vector3(_rng.randf_range(-26, 26), band_y, _rng.randf_range(-30, 30)),
			"t": _rng.randf_range(0, 100.0),
		})

func _process(delta: float) -> void:
	_t += delta
	# Kelp sways in the set of the current.
	for strand in _kelp:
		var sway: float = strand.get_meta("sway")
		var phase: float = strand.get_meta("phase")
		strand.rotation.x = sin(_t * 0.4 * sway + phase) * 0.1
		strand.rotation.z = cos(_t * 0.33 * sway + phase) * 0.1
	# Schools: wander their band, members orbit the moving center. Species keep
	# their active hours — the night shift appears as the day shoals thin out.
	var phase_key: String = "day"
	match GameClock.current_phase:
		GameClock.Phase.DAWN: phase_key = "dawn"
		GameClock.Phase.DUSK: phase_key = "dusk"
		GameClock.Phase.NIGHT: phase_key = "night"
	for s in _schools:
		var active: Array = s["def"]["school"].get("active", [])
		var want: bool = active.has(phase_key)
		var root: Node3D = s["root"]
		root.visible = want
		if not want:
			continue
		s["t"] += delta
		var t: float = s["t"]
		var drift := Vector3(cos(t * 0.05) * 24.0, 0, sin(t * 0.041) * 28.0)
		var center: Vector3 = Vector3(drift.x, s["band_y"] + sin(t * 0.11) * 0.8, drift.z)
		var members: Array = s["fish"]
		var n: int = members.size()
		for i in range(n):
			var f: Node3D = members[i]
			var a: float = t * (1.2 / maxf(s["size"], 0.6)) + i * (TAU / maxi(n, 1))
			var r: float = (0.8 + 0.5 * sin(t * 0.7 + i)) * (1.0 + s["size"] * 0.5)
			var next: Vector3 = center + Vector3(cos(a) * r, sin(t * 1.3 + i) * 0.25, sin(a) * r * 0.7)
			var vel: Vector3 = next - f.global_position
			f.global_position = next
			# Steer by the FLAT velocity only — a vertical bob aligned with UP
			# makes look_at error-spam hard enough to choke the editor debugger.
			var flat := Vector3(vel.x, 0.0, vel.z)
			if flat.length_squared() > 0.0001:
				f.look_at(next + flat, Vector3.UP)
