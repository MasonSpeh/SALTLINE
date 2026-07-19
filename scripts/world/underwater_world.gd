extends Node3D
## The ocean below the wave line: the rig's legs keep going down, kelp sways on
## the moorings, marine snow drifts, bubbles rise off the steel — and the fish
## you can actually catch swim their real depth bands (schools are spawned from
## data/fish.json, so what you SEE under the surface is what's biting above it).
## Best appreciated in fly mode or falling in; diving proper is a later phase.

const FISH := preload("res://scripts/world/fish_table.gd")
const ANIM := preload("res://scripts/world/creature_anim.gd")
const SEABED := preload("res://scripts/world/seabed.gd")
const FX := preload("res://scripts/world/underwater_fx.gd")

const LEGS := [Vector3(-22, 0, -12), Vector3(22, 0, -12), Vector3(-22, 0, 12), Vector3(22, 0, 12)]
const DEPTH_BAND := {"surface": -1.2, "mid": -4.5, "deep": -9.5}

var _kelp: Array[Node3D] = []
var _schools: Array = []   # [{root, fish[], def, band_y, center, t}]
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _snow: GPUParticles3D          # marine snow, storm/depth-reactive in _process
var _storm: Node = null

func _ready() -> void:
	_rng.seed = 7411
	_kelp_forest()
	_marine_snow()
	_bubble_vents()
	_mooring_chains()
	_spawn_schools()
	# The sculpted sea floor + wreck field + reef communities, and the visibility /
	# light FX (Snell window, shafts, caustics, depth-graded fog). Both self-contain,
	# so wiring them here keeps main.gd (owned by the waves/sky builder) untouched.
	add_child(SEABED.new())
	add_child(FX.new())
	# Nothing below the wave line casts a directional shadow: it is all under 20+ m of
	# water the sunlight never reaches usefully, but Godot was still drawing every one of
	# these meshes (seabed, riprap, wreck field, reef, kelp, chains) into each shadow
	# split. Switching the whole subtree off is the single cheapest thing in this file.
	_no_shadows(self)

## Recursively stop a subtree casting shadows.
func _no_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		var g: GeometryInstance3D = n
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for c in n.get_children():
		_no_shadows(c)

# ---------------------------------------------------------------- structure

## The caissons are ONE casting each, authored in rig_builder._build_structure() and run
## from the deck rim down to y -23 in a single box. There used to be a second set of boxes
## here extending them below -3.8; see the comment on that _box call for why merging them
## was the only thing that removed the hard horizontal seam under every leg.

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
	snow.amount = 1200               # headroom; amount_ratio scales the live count cheaply
	snow.amount_ratio = 0.55         # calm baseline; storm ramps it toward 1.0
	snow.lifetime = 14.0
	snow.preprocess = 14.0
	snow.local_coords = false
	snow.visibility_aabb = AABB(Vector3(-45, -18, -45), Vector3(90, 18, 90))
	_snow = snow
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Keep the top of the emission box well BELOW the deepest wave trough. Spawning to
	# y -1 put unshaded white billboards above the waterline every time a trough passed,
	# and they read from the deck as hard white squares littering the night sea. The
	# swell reaches ~2.8 m of amplitude at full sea state, so -4 is the shallowest safe
	# ceiling; snow still greets you as soon as you are a couple of metres under.
	mat.emission_box_extents = Vector3(40, 6, 40)   # node sits at y -10 -> spans -16..-4
	mat.gravity = Vector3(0.25, -0.12, 0.18)   # the gyre's slow underwater set
	mat.initial_velocity_min = 0.02
	mat.initial_velocity_max = 0.1
	# Marine snow is aggregate: flakes range from barely-there specks to visible tufts.
	# Every mote being the SAME size was half of why the field read as scattered confetti
	# rather than suspended particulate — identical size plus billboarding means identical
	# on-screen shape for every single one.
	mat.scale_min = 0.45
	mat.scale_max = 2.3
	snow.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	quad.material = MatLib.soft_mote(Color(0.75, 0.85, 0.85, 0.5))
	snow.draw_pass_1 = quad
	add_child(snow)
	snow.position = Vector3(0, -10, 0)

func _bubble_vents() -> void:
	for leg in [LEGS[1], LEGS[2]]:
		var bub := GPUParticles3D.new()
		bub.amount = 60
		bub.lifetime = 5.0    # with the gravity below, a plume tops out around y -6
		bub.preprocess = 5.0
		bub.local_coords = false
		bub.visibility_aabb = AABB(Vector3(-3, 0, -3), Vector3(6, 14, 6))
		var mat := ParticleProcessMaterial.new()
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		mat.emission_sphere_radius = 0.6
		# Buoyancy, not a rocket. At 1.9 m/s^2 over a 6 s life a bubble climbed
		# 0.5*1.9*36 = 34 m from its -13.5 m vent, i.e. it burst out of the sea and kept
		# going 20 m into the air. Dialled to a rise that tops out several metres under
		# the swell, which is also what a real vent plume looks like from below.
		mat.gravity = Vector3(0, 0.42, 0)
		mat.initial_velocity_min = 0.2
		mat.initial_velocity_max = 0.5
		bub.process_material = mat
		var quad := QuadMesh.new()
		quad.size = Vector2(0.06, 0.06)
		quad.material = MatLib.soft_mote(Color(0.85, 0.95, 0.95, 0.6))
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

func _storm_node() -> Node:
	if _storm != null and is_instance_valid(_storm):
		return _storm
	var stack: Array = [get_tree().root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is StormSystem:
			_storm = n
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func _storm_intensity() -> float:
	var st: Node = _storm_node()
	if st == null:
		return 0.0
	var v: Variant = st.get("_intensity")
	return clampf(float(v), 0.0, 1.0) if v != null else 0.0

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
		var shape: String = String(school.get("shape", "slender"))
		# The species' real generated skin: the SAME mesh the caught/held fish and the
		# reef shoals use. Godot caches the .glb, so every member of a school shares the
		# one mesh resource — only the node instances repeat. Tinted per the school entry,
		# swimming on the UNDULATE body wave, each fish on its own phase so the school
		# doesn't beat in lockstep. Missing asset -> the tinted primitive silhouette, so a
		# fish still generating in the background never leaves a hole in the water.
		var glow: Color = Color(0.2, 0.9, 0.85) if id == "fish_herring" else tint
		var model_len: float = maxf(size, 0.3) * 0.7
		var model_path: String = "res://assets/models/fauna/%s/%s.glb" % [id, id]
		var members: Array = []
		for i in range(int(school["count"])):
			var f := Node3D.new()
			root.add_child(f)
			var gen: Dictionary = ANIM.attach(f, model_path, model_len, ANIM.Mode.UNDULATE,
				0.1, 2.2, glow, float(i) * 0.5)
			if gen.is_empty():
				_build_fish(f, shape, size, mat)   # no generated mesh yet — keep the silhouette
			else:
				for m in gen["mats"]:
					(m as ShaderMaterial).set_shader_parameter("tint", tint)
				if id == "fish_herring":
					ANIM.drive(gen["mats"], 2.2, 0.5)   # the lantern shoal keeps its glow
			members.append(f)
		var band_y: float = DEPTH_BAND.get(def.get("depth", "mid"), -4.5)
		_schools.append({
			"root": root, "fish": members, "def": def, "id": id,
			"band_y": band_y, "size": size,
			"center": Vector3(_rng.randf_range(-26, 26), band_y, _rng.randf_range(-30, 30)),
			"t": _rng.randf_range(0, 100.0),
		})

## Build one fish's body under `f`. Convention: head faces -Z, tail at +Z (the
## school code look_at()s -Z toward the swim target). Each `shape` reads as a
## different silhouette in the water so a squid, a sole and a pike never blur
## into "generic fish". `mat` is the species tint (shared per school).
func _build_fish(f: Node3D, shape: String, size: float, mat: Material) -> void:
	match shape:
		"flat":            # flatfish: wide, paper-thin oval gliding horizontally
			_ellipsoid(f, mat, Vector3.ZERO, Vector3(0.30, 0.04, 0.24) * size)
			_tail(f, mat, size, 0.34 * size, 0.9, 0.5)
			for sx in [-1.0, 1.0]:   # both eyes topside — the flatfish giveaway
				_ellipsoid(f, _eye(), Vector3(sx * 0.05 * size, 0.045 * size, -0.13 * size), Vector3.ONE * 0.02 * size)
		"eel":             # long ribbon, a dorsal frill running the body, tiny head
			_capsuleZ(f, mat, Vector3(0, 0, 0.28 * size), 0.035 * size, 1.05 * size)
			_dorsal(f, mat, Vector3(0, 0.05 * size, 0.28 * size), 0.11 * size, 1.0 * size)
			_ellipsoid(f, _eye(), Vector3(0.03 * size, 0.02 * size, -0.26 * size), Vector3.ONE * 0.02 * size)
		"pike":            # torpedo with a pointed snout — the ambush shape
			_capsuleZ(f, mat, Vector3(0, 0, 0.06 * size), 0.045 * size, 0.46 * size)
			var snout := _cone(mat)
			var mi := MeshInstance3D.new(); mi.mesh = snout; f.add_child(mi)
			mi.scale = Vector3(0.09, 0.22, 0.09) * size   # slim spike
			mi.position = Vector3(0, 0, -0.3 * size)
			mi.rotation.x = deg_to_rad(-90)               # point forward (-Z)
			_tail(f, mat, size, 0.11 * size, 0.9, 0.34)
		"squid":           # mantle + fin flaps + a bundle of trailing arms
			var mantle := _cone(mat)
			var mm := MeshInstance3D.new(); mm.mesh = mantle; f.add_child(mm)
			mm.scale = Vector3(0.10, 0.42, 0.10) * size
			mm.position = Vector3(0, 0, 0.18 * size)
			mm.rotation.x = deg_to_rad(90)                # taper trails (+Z)
			for sx2 in [-1.0, 1.0]:
				_dorsalFlat(f, mat, Vector3(sx2 * 0.08 * size, 0, 0.28 * size), Vector3(0.16, 0.01, 0.12) * size)
			for k in range(6):    # arms fanning off the head (-Z)
				_capsuleZ(f, mat, Vector3((k - 2.5) * 0.014 * size, 0, -0.18 * size), 0.008 * size, 0.2 * size)
			_ellipsoid(f, _eye(), Vector3(0.055 * size, 0, -0.02 * size), Vector3.ONE * 0.03 * size)
		"barrel":          # fat rounded grouper, big head, stubby tail
			_ellipsoid(f, mat, Vector3.ZERO, Vector3(0.16, 0.17, 0.23) * size)
			_tail(f, mat, size, 0.11 * size, 0.9, 0.26)
			_dorsal(f, mat, Vector3(0, 0.14 * size, 0.02 * size), 0.09 * size, 0.34 * size)
		"deep":            # slab-sided bream/jack: tall, thin, forked tail
			_ellipsoid(f, mat, Vector3.ZERO, Vector3(0.075, 0.24, 0.18) * size)
			_tail(f, mat, size, 0.16 * size, 1.3, 0.26)
			_dorsal(f, mat, Vector3(0, 0.22 * size, 0.0), 0.16 * size, 0.4 * size)
		"fusiform":        # honest fish with a dorsal fin and a forked tail
			_capsuleZ(f, mat, Vector3.ZERO, 0.055 * size, 0.3 * size, 1.3)
			_tail(f, mat, size, 0.12 * size, 1.1, 0.21)
			_dorsal(f, mat, Vector3(0, 0.085 * size, 0.0), 0.08 * size, 0.28 * size)
		_:                 # "slender" — the schooling sprat/herring default
			_capsuleZ(f, mat, Vector3.ZERO, 0.045 * size, 0.34 * size)
			_tail(f, mat, size, 0.1 * size, 1.0, 0.22)

# --- silhouette primitives (head -Z, tail +Z) ---
func _capsuleZ(f: Node3D, mat: Material, pos: Vector3, r: float, h: float, y_scale: float = 1.0) -> void:
	var mi := MeshInstance3D.new()
	var c := CapsuleMesh.new(); c.radius = r; c.height = h; c.material = mat
	mi.mesh = c; f.add_child(mi)
	mi.position = pos; mi.rotation.x = deg_to_rad(90); mi.scale.y = y_scale   # long axis -> Z

func _ellipsoid(f: Node3D, mat: Material, pos: Vector3, half: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new(); s.radius = 1.0; s.height = 2.0; s.material = mat
	mi.mesh = s; f.add_child(mi)
	mi.position = pos; mi.scale = half

func _tail(f: Node3D, mat: Material, size: float, w: float, h_mul: float, z: float) -> void:
	var mi := MeshInstance3D.new()
	var p := PrismMesh.new(); p.size = Vector3(w, 0.01 * size, 0.1 * size * h_mul); p.material = mat
	mi.mesh = p; f.add_child(mi)
	mi.position = Vector3(0, 0, z * size); mi.rotation.x = deg_to_rad(90)   # vertical caudal fin

func _dorsal(f: Node3D, mat: Material, pos: Vector3, height: float, length: float) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = Vector3(0.015, height, length); b.material = mat
	mi.mesh = b; f.add_child(mi); mi.position = pos

func _dorsalFlat(f: Node3D, mat: Material, pos: Vector3, sz: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = sz; b.material = mat
	mi.mesh = b; f.add_child(mi); mi.position = pos

func _cone(mat: Material) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = 0.0; c.bottom_radius = 1.0; c.height = 1.0; c.material = mat; return c
func _eye() -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.02, 0.02, 0.03); m.roughness = 0.3; return m

## Above the surface, none of this is visible — and none of it should be SUBMITTED.
##
## ocean_water.gdshader is depth_draw_opaque, so from a deck 24 m up you cannot see the
## seabed, the wreck field, the reef, the kelp or the marine snow through the water: they
## are all behind an opaque surface. Godot's Compatibility renderer has no occlusion
## culling, though, so every one of those meshes was still being drawn and then discarded
## by the depth test on every frame the player spent topside — which is nearly all of them.
## Measured from sea level it was ~4.9 M triangles and ~4,100 draw calls of pure waste.
##
## The margin keeps everything alive well before the camera reaches the water, so nothing
## pops in as you climb down the tidal ladder or a fish breaks the surface beside you.
const TOPSIDE_MARGIN: float = 4.0

func _cull_topside() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp: Vector3 = cam.global_position
	var surf: float = Gyre.wave_height(Vector2(cp.x, cp.z), Gyre.water_time()) * 0.85
	var want: bool = cp.y < surf + TOPSIDE_MARGIN
	if visible != want:
		visible = want

func _process(delta: float) -> void:
	_cull_topside()
	_t += delta
	# Marine snow thickens and drives harder when a storm stirs the water column —
	# the same sediment that fogs the near-surface visibility (see underwater_fx).
	if _snow != null:
		var storm: float = _storm_intensity()
		_snow.amount_ratio = clampf(0.55 + storm * 0.45, 0.0, 1.0)
		_snow.speed_scale = 1.0 + storm * 0.7
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
			# Never let a school breach. The "surface" band sits at -1.2, which was under
			# water when the sea was a flat plane; against the Gerstner swell (±2 m calm,
			# more in a squall) it put whole shoals of fish flapping above the waterline.
			# Clamp to the live surface, so a squall pushes the shallow bands down with it.
			# Full wave height: the 0.85 camera-test factor lifts a point above the true
			# surface in troughs, which is exactly where a shallow school would breach.
			var surf: float = Gyre.wave_height(Vector2(next.x, next.z), Gyre.water_time())
			next.y = minf(next.y, surf - 0.5 - s["size"] * 0.5)
			var vel: Vector3 = next - f.global_position
			f.global_position = next
			# Steer by the FLAT velocity only — a vertical bob aligned with UP
			# makes look_at error-spam hard enough to choke the editor debugger.
			var flat := Vector3(vel.x, 0.0, vel.z)
			if flat.length_squared() > 0.0001:
				f.look_at(next + flat, Vector3.UP)
