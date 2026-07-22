class_name Seabed extends Node3D
## The sea floor under the rig, and the rig's footprint on it.
##
## DATUM: the silt sits at y = -23. That is where the existing leg-extension
## caissons (underwater_world.gd) already bottom out, so the legs plant flush into
## the mud with zero edits to that file. It is also far *below* the depth a breath of
## oxygen lets the player reach (player_controller: air-gated swimming, wave line ~y 0),
## so the true floor is set-dressing seen from above through fog — a hard breath-hold
## dive can glimpse it, never linger. Detail budget therefore goes into big silhouette (legs planting,
## scour moats, riprap, chains, wreckage) rather than micro-detail nobody can reach.
##
## The floor is not a flat plane: broad silt swells + megaripples (in the shader) +
## a scour depression dug around every leg with a deposition rim, the way real
## gravity-base structures scour. Riprap rock armour is dumped against each leg and
## heavy ground chains run off into the silt.
##
## floor_height(Vector2) is STATIC and is the single source of truth for the mudline
## — the mesh, the riprap/boulders, the chains and reef_detail.gd all plant on it,
## exactly the way gyre.gd mirrors the wave math. Change the sculpt here and every
## planted thing follows.
##
## Self-registers everything visual only (NO collision below the death line, so no
## existing physics changes) and spawns ReefDetail as a child so the integrator adds
## ONE line:  add_child(preload("res://scripts/world/seabed.gd").new())

const REEF := preload("res://scripts/world/reef_detail.gd")

## The true abyssal floor. Was -23; deepened 4x so the bottom is a place the light
## never reaches — from the surface the water just fades to black below (the fog grade
## in underwater_fx.gd swallows anything past ~40 m), and the 13 m death line keeps it
## forever out of reach. Everything planted here (riprap, chains, wreck, reef slabs)
## rides floor_height() and follows automatically.
const FLOOR_Y: float = -92.0
## The caissons (rig_builder._build_structure) run in ONE casting from the deck rim
## down to exactly this bottom, planted in the silt at PLANT_Y (a little ABOVE the
## bottom) so each leg is bedded in the mud rather than hovering over it.
const CAISSON_HALF: float = 3.0
const CAISSON_BOTTOM: float = -92.0
const BED_SINK: float = 0.45              # how far the mud climbs the caisson base
const PLANT_Y: float = CAISSON_BOTTOM + BED_SINK
const LEGS: Array[Vector2] = [Vector2(-22, -12), Vector2(22, -12), Vector2(-22, 12), Vector2(22, 12)]
const EXT: float = 90.0          # floor half-extent (180 x 180 m), fog hides the edge
const STEP: float = 2.25         # grid spacing; ripples live in the shader, not here

static var _fn: FastNoiseLite

var _haze_mat: ShaderMaterial
var _floor_mat: ShaderMaterial
var _bloom_glow: float = 0.28   # tracked here; reading it back off the shader returns Nil
var _rng := RandomNumberGenerator.new()

# -------------------------------------------------------------- sculpt (shared)

static func _noise() -> FastNoiseLite:
	if _fn == null:
		_fn = FastNoiseLite.new()
		_fn.seed = 5150
		_fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_fn.frequency = 0.02
		_fn.fractal_octaves = 3
	return _fn

## Distance from world (x, z) to the nearest point of a caisson's square footprint.
## 0 anywhere UNDER the leg, growing outward. Scour and bedding are shaped against
## this rather than against the distance to the leg CENTRE — a 6 m square structure
## does not scour in a circle, and more importantly nothing may be dug out from
## beneath the footprint itself.
static func _footprint_dist(p: Vector2, leg: Vector2) -> float:
	var d := (p - leg).abs() - Vector2(CAISSON_HALF, CAISSON_HALF)
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()

## The mudline at world (x, z). FLOOR_Y plus broad silt swells, a BEDDING plateau under
## each caisson, and a scour MOAT ringing it (with a deposition rim further out).
##
## The moat used to be a Gaussian bowl centred on the leg, i.e. deepest exactly where
## the caisson stands: it dug ~2.6 m of mud out from under every leg and left all four
## hovering over an open gap, which is the first thing you see swimming the bottom.
## Real gravity-base scour is an annulus — the structure is bedded IN the soil and the
## current excavates around its edge — so the sculpt is now: flat plant under the
## footprint (mud packed BED_SINK up the caisson base, so a leg plants and never
## floats), the moat peaking a few metres outboard, then the spoil rim.
static func floor_height(p: Vector2) -> float:
	var fn := _noise()
	var h := FLOOR_Y
	h += 1.9 * fn.get_noise_2d(p.x, p.y)
	h += 0.7 * fn.get_noise_2d(p.x * 2.7 + 100.0, p.y * 2.7 - 60.0)
	for leg in LEGS:
		var fd: float = _footprint_dist(p, leg)
		# Bedding: inside (and right up against) the footprint the mud is a flat pad at
		# the plant height, so the caisson bottom is buried, not bridged.
		var bed_w: float = 1.0 - smoothstep(0.0, 2.4, fd)
		h = lerpf(h, PLANT_Y, bed_w)
		# Scour moat: zero under the leg, deepest a few metres out, tailing away.
		var moat: float = exp(-((fd - 4.5) * (fd - 4.5)) / (2.0 * 2.8 * 2.8))
		h -= 2.8 * moat * smoothstep(1.6, 3.4, fd)
		# Spoil rim: what the current carried out of the moat.
		h += 0.85 * exp(-((fd - 13.0) * (fd - 13.0)) / (2.0 * 3.5 * 3.5))
	return h

static func floor_normal(p: Vector2) -> Vector3:
	var e := STEP * 0.5
	var hx := floor_height(p + Vector2(e, 0.0)) - floor_height(p - Vector2(e, 0.0))
	var hz := floor_height(p + Vector2(0.0, e)) - floor_height(p - Vector2(0.0, e))
	return Vector3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)).normalized()

# -------------------------------------------------------------- build

func _ready() -> void:
	_rng.seed = 24601
	_build_floor()
	_build_riprap()
	_build_boulders()
	_build_ground_chains()
	_build_silt_haze()
	_build_sediment()
	add_child(REEF.new())   # wreck field + reef shelves ride the same mudline

func _process(_delta: float) -> void:
	# The Bloom in the silt answers the night, like the gyre eye does.
	var want: float = 0.9 if GameClock.current_phase == GameClock.Phase.NIGHT else 0.28
	if _floor_mat:
		_bloom_glow = lerpf(_bloom_glow, want, _delta * 0.6)
		_floor_mat.set_shader_parameter("bloom_glow", _bloom_glow)

func _build_floor() -> void:
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = load("res://materials/seabed.gdshader")
	_floor_mat.set_shader_parameter("bloom_glow", _bloom_glow)
	var n: int = int(EXT * 2.0 / STEP)           # cells per side
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize((n + 1) * (n + 1))
	norms.resize((n + 1) * (n + 1))
	for j in range(n + 1):
		for i in range(n + 1):
			var x: float = -EXT + float(i) * STEP
			var z: float = -EXT + float(j) * STEP
			var vi: int = j * (n + 1) + i
			verts[vi] = Vector3(x, floor_height(Vector2(x, z)), z)
			norms[vi] = floor_normal(Vector2(x, z))
	for j in range(n):
		for i in range(n):
			var a: int = j * (n + 1) + i
			var b: int = a + 1
			var c: int = a + (n + 1)
			var d: int = c + 1
			idx.append_array([a, c, b, b, c, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, _floor_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)

# --- rock materials (cached on the node so instances share one) ---

func _rock_mat(crust: float = 0.4) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://materials/seabed_rock.gdshader")
	m.set_shader_parameter("crust_amount", crust)
	return m

## Angular quarried riprap dumped in a berm against each leg base — the rock armour
## that resists scour. One MultiMesh = one draw call for the whole armour field.
func _build_riprap() -> void:
	var chunk := BoxMesh.new()
	chunk.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = chunk
	var xforms: Array[Transform3D] = []
	for leg in LEGS:
		var rings := 46
		for k in range(rings):
			var a: float = _rng.randf_range(0, TAU)
			var ca: float = cos(a)
			var sa: float = sin(a)
			# Hug the SQUARE footprint, not a circle around its centre: a circle of
			# radius 3.4 passes inside the 4.24 m corners, so a third of the armour used
			# to be dumped inside the caisson where it is buried in concrete. Start at
			# the footprint boundary along this bearing and pile outward into the moat.
			var boundary: float = CAISSON_HALF / maxf(absf(ca), absf(sa))
			var out: float = _rng.randf_range(0.15, 5.0)
			var pos2 := leg + Vector2(ca, sa) * (boundary + out)
			var pile: float = clampf(1.0 - out / 5.0, 0.0, 1.0)   # taller against the leg
			var s: float = _rng.randf_range(0.8, 2.1)
			var y: float = floor_height(pos2) + s * 0.35 + pile * _rng.randf_range(0.0, 1.6)
			var basis := Basis.from_euler(Vector3(
				_rng.randf_range(0, TAU), _rng.randf_range(0, TAU), _rng.randf_range(0, TAU)))
			basis = basis.scaled(Vector3(s, s * _rng.randf_range(0.6, 0.9), s * _rng.randf_range(0.8, 1.1)))
			xforms.append(Transform3D(basis, Vector3(pos2.x, y, pos2.y)))
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _rock_mat(0.3)
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi)

## Natural boulder field + low outcrops scattered across the floor — geological, not
## dumped. Rounded rock (a deformed sphere) so it reads distinct from angular riprap.
func _build_boulders() -> void:
	var rock := SphereMesh.new()
	rock.radius = 1.0
	rock.height = 2.0
	rock.radial_segments = 10
	rock.rings = 6
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rock
	var xforms: Array[Transform3D] = []
	var tries := 0
	while xforms.size() < 64 and tries < 400:
		tries += 1
		var x: float = _rng.randf_range(-EXT + 6.0, EXT - 6.0)
		var z: float = _rng.randf_range(-EXT + 6.0, EXT - 6.0)
		var p := Vector2(x, z)
		# keep clear of the leg footprints (riprap owns those) and dead centre
		var near_leg := false
		for leg in LEGS:
			if p.distance_to(leg) < 6.5:
				near_leg = true
		if near_leg:
			continue
		var s: float = _rng.randf_range(0.7, 3.2)
		var y: float = floor_height(p) + s * _rng.randf_range(0.25, 0.5)   # partly bedded in silt
		var basis := Basis.from_euler(Vector3(
			_rng.randf_range(-0.3, 0.3), _rng.randf_range(0, TAU), _rng.randf_range(-0.3, 0.3)))
		basis = basis.scaled(Vector3(s * _rng.randf_range(0.9, 1.4), s * _rng.randf_range(0.45, 0.8), s * _rng.randf_range(0.9, 1.4)))
		xforms.append(Transform3D(basis, Vector3(x, y, z)))
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _rock_mat(0.45)
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi)

## Heavy ground chain / cable runs sagging off each leg and draping into the silt —
## the mooring gear the thin underwater_world chains hint at, here as real weight on
## the bottom. Routed toward the rig centre so they never overlay those diagonals.
func _build_ground_chains() -> void:
	var mat := MatLib.dark_metal()
	for leg in LEGS:
		var inward := Vector2(-signf(leg.x), -signf(leg.y))
		var start := leg + inward * 3.0
		var start3 := Vector3(start.x, -5.5, start.y)      # leaves the leg below the pontoon
		var run: float = _rng.randf_range(13.0, 18.0)
		var segs := 7
		var prev := start3
		for s in range(1, segs + 1):
			var f: float = float(s) / float(segs)
			var here2 := start + inward * (run * f)
			# catenary: hangs, touches down, then lies buried along the mud
			var touchdown: float = smoothstep(0.0, 0.55, f)
			var floor_y: float = floor_height(here2)
			var y: float = lerpf(start3.y, floor_y - 0.25, touchdown)
			var here := Vector3(here2.x, y, here2.y)
			_link(prev, here, 0.19, mat)
			prev = here

func _link(a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = 6
	cm.material = mat
	mi.mesh = cm
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	mi.global_position = (a + b) * 0.5
	if a.distance_to(b) > 0.001:
		mi.look_at_from_position(mi.global_position, b, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)

## A faint horizontal murk sheet a couple of metres off the bottom: the resuspended
## silt layer the current never quite lets settle. Read edge-on near the floor it is
## a haze deck; from above it just deepens the water. Cheap unshaded alpha.
func _build_silt_haze() -> void:
	_haze_mat = ShaderMaterial.new()
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.09, 0.20, 0.22, 0.05)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.no_depth_test = false
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(EXT * 1.9, EXT * 1.9)
	mesh.material = sm
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	mi.position = Vector3(0, FLOOR_Y + 1.8, 0)

## Suspended sediment drifting just over the mud — slow, sparse, big soft motes.
func _build_sediment() -> void:
	var p := GPUParticles3D.new()
	p.amount = 240
	p.lifetime = 18.0
	p.preprocess = 18.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-EXT, FLOOR_Y - 1.0, -EXT), Vector3(EXT * 2.0, 6.0, EXT * 2.0))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(EXT * 0.85, 2.0, EXT * 0.85)
	mat.gravity = Vector3(0.18, 0.02, -0.14)   # the slow bottom set
	mat.initial_velocity_min = 0.01
	mat.initial_velocity_max = 0.06
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	quad.material = MatLib.soft_mote(Color(0.6, 0.72, 0.72, 0.3))
	p.draw_pass_1 = quad
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(p)
	p.position = Vector3(0, FLOOR_Y + 2.0, 0)
