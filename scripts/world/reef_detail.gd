class_name ReefDetail extends Node3D
## The rig's history on the bottom, and where life will colonise it.
##
## A rig sheds for years. This scatters the sunken evidence across the mudline so a
## dive is navigable by landmark and the rig's story reads without a word of text:
## a capsized workboat, a toppled crane boom, racked and rolled drill pipe, oil drums
## (some burst), a lost stockless anchor, coils of wire rope, a crushed container.
## Everything is half-buried at varied angles and encrusted (seabed_rock crust), and
## every piece plants on Seabed.floor_height so it rides the real silt.
##
## It also lays down the LIFE HOOKS the reef domain asked for: broad flat rock
## shelves and current-swept faces at known coordinates (see coral_shelves()), plus a
## rock reef ridge that climbs into the reachable band. reef_detail owns only the
## GEOMETRY — bloom_fauna's FloraPatch (not ours) reads the coordinates we report.
##
## Spawned as a child of Seabed; visual only, no collision.

const SEABED := preload("res://scripts/world/seabed.gd")
const REEF_LIFE := preload("res://scripts/world/reef_life.gd")

var _rng := RandomNumberGenerator.new()
var _rock_mat: ShaderMaterial
var _shelves: Array[Dictionary] = []

func _ready() -> void:
	_rng.seed = 1974
	_rock_mat = ShaderMaterial.new()
	_rock_mat.shader = load("res://materials/seabed_rock.gdshader")
	_rock_mat.set_shader_parameter("crust_amount", 0.5)
	_build_reef_ridge()
	_build_wreck_field(Vector2(0, -52))     # the main field, under the gyre eye
	_build_east_scatter(Vector2(40, 4))     # a second landmark cluster on the flank
	_build_reef_slabs()
	_report()
	# Depth-zoned reef communities seated on the shelves/faces we just reported.
	add_child(REEF_LIFE.new(_shelves))

# --------------------------------------------------------------- floor helpers

func floor_y(x: float, z: float) -> float:
	return SEABED.floor_height(Vector2(x, z))

## y that beds an object of half-height `hh` into the silt by `sink` metres.
func bed(x: float, z: float, hh: float, sink: float) -> float:
	return floor_y(x, z) + hh - sink

# --------------------------------------------------------------- primitives

func _box(pos: Vector3, size: Vector3, mat: Material, euler := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	mi.position = pos
	mi.rotation = euler
	return mi

func _cyl(pos: Vector3, r: float, h: float, mat: Material, euler := Vector3.ZERO, rings := 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = rings
	cm.material = mat
	mi.mesh = cm
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	mi.position = pos
	mi.rotation = euler
	return mi

func _blob(pos: Vector3, half: Vector3, mat: Material, euler := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 12
	sm.rings = 7
	sm.material = mat
	mi.mesh = sm
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	mi.position = pos
	mi.scale = half
	mi.rotation = euler
	return mi

func _torus(pos: Vector3, inner: float, outer: float, mat: Material, euler := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 10
	tm.ring_segments = 8
	tm.material = mat
	mi.mesh = tm
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	mi.position = pos
	mi.rotation = euler
	return mi

# --------------------------------------------------------------- reef ridge

## A rock reef ridge rising off the deep silt — overlapping boulders reading as a
## spine, its broad top and current-swept flank prime coral ground. A landmark on the
## swim south toward the gyre. FLOOR-RELATIVE: the crest used to lerp toward an
## absolute y -12 ("reachable"), which was ~11 m of relief over the old -23 floor;
## against the 4x-deeper abyssal floor that formula would have extruded 80 m rock
## spires, so the ridge now keeps the same ~11 m of relief above wherever the mud is.
func _build_reef_ridge() -> void:
	var base := Vector2(9, -30)
	var axis := Vector2(0.5, -0.86).normalized()   # runs SSW->NNE
	var n := 9
	for i in range(n):
		var f: float = float(i) / float(n - 1)
		var along: float = (f - 0.5) * 22.0
		var c := base + axis * along
		var crest: float = 1.0 - abs(f - 0.45) * 1.7          # tallest just past middle
		crest = clampf(crest, 0.0, 1.0)
		var top_y: float = lerpf(floor_y(c.x, c.y) + 2.0, floor_y(c.x, c.y) + 11.0, crest)
		var span: float = _rng.randf_range(3.0, 5.5)
		var lo: float = floor_y(c.x, c.y) - 0.5
		var cy: float = (top_y + lo) * 0.5
		var hh: float = (top_y - lo) * 0.5
		_blob(Vector3(c.x, cy, c.y),
			Vector3(span, maxf(hh, 1.2), span * _rng.randf_range(0.8, 1.2)),
			_rock_mat,
			Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf_range(0, TAU), _rng.randf_range(-0.2, 0.2)))
		# a couple of skirt boulders so the base isn't a clean ellipsoid seam
		for _k in range(2):
			var a: float = _rng.randf_range(0, TAU)
			var rr: float = span * _rng.randf_range(0.7, 1.1)
			var bx: float = c.x + cos(a) * rr
			var bz: float = c.y + sin(a) * rr
			var bs: float = _rng.randf_range(1.0, 2.2)
			_blob(Vector3(bx, floor_y(bx, bz) + bs * 0.35, bz), Vector3(bs, bs * 0.6, bs), _rock_mat,
				Vector3(0, _rng.randf_range(0, TAU), 0))
	# broad flat top = coral shelf; note the swept south face too (floor-relative now)
	var topc := base + axis * (0.45 - 0.5) * 22.0
	_shelf(Vector3(topc.x, floor_y(topc.x, topc.y) + 10.8, topc.y),
		"reef ridge crown: broad flat, high current")
	_shelf(Vector3(base.x + 4.0, floor_y(base.x + 4.0, base.y + 3.0) + 5.5, base.y + 3.0),
		"reef ridge SW flank: current-swept face")

# --------------------------------------------------------------- wreck field

func _build_wreck_field(c: Vector2) -> void:
	var rust := MatLib.rust_steel()
	var dark := MatLib.dark_metal()
	var galv := MatLib.galvanized()
	var red := MatLib.red_paint()
	var hazard := MatLib.hazard_stripe()
	var rope := MatLib.rope_mat()

	# --- capsized workboat hull (the big landmark), rolled onto its side ---
	_workboat(Vector3(c.x - 3.0, 0, c.y + 2.0), 2.5, rust, dark)

	# --- toppled crane boom: a lattice truss thrown down across the floor ---
	_crane_boom(Vector3(c.x + 9.0, 0, c.y - 8.0), -0.9, hazard, dark)

	# --- drill pipe: a collapsed rack of green pipe + a few rolled loose ---
	_pipe_stack(Vector3(c.x - 11.0, 0, c.y - 6.0), 1.1, galv)

	# --- oil drums: upright, toppled, and a couple burst open ---
	_drum_scatter(c, 8, red, dark, rust)

	# --- lost stockless anchor with a short heavy chain trailing ---
	_anchor(Vector3(c.x + 4.0, 0, c.y + 11.0), 2.3, dark)

	# --- coils of wire rope ---
	for i in range(3):
		var x: float = c.x - 6.0 + i * 2.4
		var z: float = c.y + 9.0 + sin(i * 1.7) * 1.5
		_torus(Vector3(x, floor_y(x, z) + 0.28, z), 0.28, 0.85, rope,
			Vector3(PI * 0.5 + _rng.randf_range(-0.12, 0.12), _rng.randf_range(0, TAU), 0))

	# --- a crushed shipping container, doors sprung, half sunk ---
	_container(Vector3(c.x + 13.0, 0, c.y + 4.0), 0.7, MatLib.container(Color(0.5, 0.42, 0.3)))

	# the workboat's up-turned bilge and the container roof are flat colonisable faces —
	# both wrecks rest ON the mud (floor_y), so their shelf tops ride it too
	_shelf(Vector3(c.x - 3.0, floor_y(c.x - 3.0, c.y + 2.0) + 3.4, c.y + 2.0),
		"capsized workboat bilge: broad flat steel, encrusted")
	_shelf(Vector3(c.x + 13.0, floor_y(c.x + 13.0, c.y + 4.0) + 2.9, c.y + 4.0),
		"crushed container roof: flat shelf near the gyre eye")

func _workboat(base: Vector3, yaw: float, hull_mat: Material, dark: Material) -> void:
	var root := Node3D.new()
	add_child(root)
	var gy: float = floor_y(base.x, base.z)
	root.position = Vector3(base.x, gy + 1.4, base.z)
	root.rotation = Vector3(0, yaw, 2.35)   # rolled hard onto its side
	# rounded hull
	_blob_under(root, Vector3.ZERO, Vector3(2.4, 1.7, 6.8), hull_mat)
	# keel line (now pointing up-and-out)
	_box_under(root, Vector3(0, 1.7, 0), Vector3(0.35, 0.4, 12.5), dark)
	# stub of a wheelhouse crushed against the mud
	_box_under(root, Vector3(-0.2, -0.4, -3.2), Vector3(2.2, 1.8, 2.6), dark)
	# a bent rail rib
	_box_under(root, Vector3(1.9, 0.2, 1.5), Vector3(0.12, 1.4, 0.12), dark, Vector3(0, 0, 0.4))

func _crane_boom(base: Vector3, pitch: float, chord_mat: Material, web_mat: Material) -> void:
	var root := Node3D.new()
	add_child(root)
	var gy: float = floor_y(base.x, base.z)
	root.position = Vector3(base.x, gy + 0.6, base.z)
	root.rotation = Vector3(pitch, _rng.randf_range(0, TAU), 0.15)
	var length := 17.0
	var side := 0.9
	# four chords
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			_box_under(root, Vector3(sx * side * 0.5, sy * side * 0.5, 0),
				Vector3(0.12, 0.12, length), chord_mat)
	# lattice webbing
	var bays := 9
	for i in range(bays):
		var z: float = -length * 0.5 + (float(i) + 0.5) * (length / float(bays))
		_box_under(root, Vector3(0, side * 0.5, z), Vector3(side, 0.08, 0.08), web_mat, Vector3(0, 0, 0))
		_box_under(root, Vector3(0, -side * 0.5, z), Vector3(side, 0.08, 0.08), web_mat)
		_box_under(root, Vector3(side * 0.5, 0, z), Vector3(0.08, side, 0.08), web_mat)
		_box_under(root, Vector3(-side * 0.5, 0, z), Vector3(0.08, side, 0.08), web_mat)
	# the sheave head at the tip, resting on a boulder
	_box_under(root, Vector3(0, 0, length * 0.5 + 0.4), Vector3(1.1, 1.1, 0.9), web_mat)

func _pipe_stack(base: Vector3, yaw: float, mat: Material) -> void:
	var root := Node3D.new()
	add_child(root)
	var gy: float = floor_y(base.x, base.z)
	root.position = Vector3(base.x, gy, base.z)
	root.rotation = Vector3(0, yaw, 0)
	# a slumped pyramid of racked pipe (each ~5 m, r 0.16)
	var rows := [4, 3, 2]
	var y := 0.2
	for count in rows:
		for i in range(count):
			var x: float = (float(i) - float(count - 1) * 0.5) * 0.42
			_cyl_under(root, Vector3(x + _rng.randf_range(-0.03, 0.03), y, 0), 0.16, 5.0, mat,
				Vector3(PI * 0.5, 0, 0), 8)
		y += 0.34
	# two that rolled off the rack
	_cyl_under(root, Vector3(2.4, 0.16, 1.6), 0.16, 4.6, mat, Vector3(PI * 0.5, 0.5, 0), 8)
	_cyl_under(root, Vector3(-2.1, 0.16, -1.2), 0.16, 4.2, mat, Vector3(PI * 0.5, -0.7, 0), 8)

func _drum_scatter(c: Vector2, n: int, red: Material, dark: Material, rust: Material) -> void:
	for i in range(n):
		var a: float = _rng.randf_range(0, TAU)
		var r: float = _rng.randf_range(4.0, 14.0)
		var x: float = c.x + cos(a) * r
		var z: float = c.y + sin(a) * r
		var mat: Material = red if i % 3 == 0 else (dark if i % 3 == 1 else rust)
		var roll := _rng.randf()
		if roll < 0.45:
			# upright, half sunk
			_cyl(Vector3(x, bed(x, z, 0.44, 0.35), z), 0.30, 0.88, mat,
				Vector3(_rng.randf_range(-0.1, 0.1), _rng.randf_range(0, TAU), _rng.randf_range(-0.1, 0.1)))
		elif roll < 0.8:
			# toppled on its side
			_cyl(Vector3(x, floor_y(x, z) + 0.24, z), 0.30, 0.88, mat,
				Vector3(PI * 0.5, _rng.randf_range(0, TAU), 0))
		else:
			# burst: crushed flat with a dark spill stain sheet
			_cyl(Vector3(x, floor_y(x, z) + 0.12, z), 0.32, 0.55, rust,
				Vector3(PI * 0.5, _rng.randf_range(0, TAU), _rng.randf_range(-0.3, 0.3)))
			var stain := StandardMaterial3D.new()
			stain.albedo_color = Color(0.03, 0.03, 0.04, 0.55)
			stain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			stain.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var sheet := PlaneMesh.new()
			sheet.size = Vector2(_rng.randf_range(2.0, 3.4), _rng.randf_range(2.0, 3.4))
			sheet.material = stain
			var mi := MeshInstance3D.new()
			mi.mesh = sheet
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			add_child(mi)
			mi.position = Vector3(x + 1.0, floor_y(x + 1.0, z) + 0.06, z)

func _anchor(base: Vector3, yaw: float, mat: Material) -> void:
	var root := Node3D.new()
	add_child(root)
	var gy: float = floor_y(base.x, base.z)
	root.position = Vector3(base.x, gy + 0.35, base.z)
	root.rotation = Vector3(0.5, yaw, 0)   # tilted, one fluke dug in
	# shank
	_box_under(root, Vector3(0, 0.3, 0), Vector3(0.28, 0.28, 3.0), mat, Vector3(PI * 0.5, 0, 0))
	# crown + two flukes
	_box_under(root, Vector3(0.7, -0.1, 1.4), Vector3(0.9, 0.25, 1.1), mat, Vector3(0, 0, -0.5))
	_box_under(root, Vector3(-0.7, -0.1, 1.4), Vector3(0.9, 0.25, 1.1), mat, Vector3(0, 0, 0.5))
	# a stump of chain trailing off into the silt
	var prev := Vector3(base.x, gy + 0.7, base.z)
	for s in range(5):
		var nx: float = base.x - 1.2 - s * 1.1
		var nz: float = base.z + 0.6 + s * 0.5
		var ny: float = floor_y(nx, nz) - 0.15 * float(s > 1)
		var here := Vector3(nx, minf(ny + 0.4, prev.y), nz)
		var link := _cyl(Vector3.ZERO, 0.14, prev.distance_to(here), mat, Vector3.ZERO, 6)
		link.global_position = (prev + here) * 0.5
		if prev.distance_to(here) > 0.01:
			link.look_at_from_position(link.global_position, here, Vector3.UP)
			link.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		prev = here

func _container(base: Vector3, yaw: float, mat: Material) -> void:
	var root := Node3D.new()
	add_child(root)
	var gy: float = floor_y(base.x, base.z)
	root.position = Vector3(base.x, gy + 1.0, base.z)
	root.rotation = Vector3(0.12, yaw, 0.18)   # settled askew
	_box_under(root, Vector3.ZERO, Vector3(2.4, 2.4, 6.0), mat)
	# a sprung door hanging off one end
	_box_under(root, Vector3(1.3, 0, 3.2), Vector3(0.1, 2.3, 1.1), MatLib.rusty_metal(), Vector3(0, 0.7, 0))

func _east_outcrop(c: Vector2) -> void:
	for i in range(5):
		var a: float = _rng.randf_range(0, TAU)
		var r: float = _rng.randf_range(0.0, 4.0)
		var x: float = c.x + cos(a) * r
		var z: float = c.y + sin(a) * r
		var s: float = _rng.randf_range(1.4, 3.4)
		_blob(Vector3(x, floor_y(x, z) + s * 0.35, z), Vector3(s, s * 0.6, s * _rng.randf_range(0.8, 1.2)),
			_rock_mat, Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf_range(0, TAU), _rng.randf_range(-0.2, 0.2)))

func _build_east_scatter(c: Vector2) -> void:
	_east_outcrop(c)
	var rust := MatLib.rust_steel()
	var dark := MatLib.dark_metal()
	# a length of pipe and a few drums make a second, smaller landmark
	_cyl(Vector3(c.x + 3.0, floor_y(c.x + 3.0, c.y - 2.0) + 0.16, c.y - 2.0), 0.18, 5.5, MatLib.galvanized(),
		Vector3(PI * 0.5, 0.6, 0), 8)
	_drum_scatter(c + Vector2(2.0, 2.0), 3, MatLib.red_paint(), dark, rust)
	_shelf(Vector3(c.x, floor_y(c.x, c.y) + 1.6, c.y), "east outcrop crown: flat rock, off the mooring lines")

## Low flat rock slabs bedded in the silt near the wreck — deliberate coral shelves
## in the deeper band for corals that want the bottom, not the ridge.
func _build_reef_slabs() -> void:
	var spots := [Vector2(-8, -44), Vector2(6, -60), Vector2(-16, -50)]
	for sp in spots:
		var y: float = floor_y(sp.x, sp.y)
		# a broad low slab (flattened blob) with a clean top face
		_blob(Vector3(sp.x, y + 0.35, sp.y), Vector3(_rng.randf_range(2.6, 4.0), 0.5, _rng.randf_range(2.6, 4.0)),
			_rock_mat, Vector3(0, _rng.randf_range(0, TAU), 0))
		_shelf(Vector3(sp.x, y + 0.8, sp.y), "low reef slab (deep band ~ -22): flat top, silted margins")

# --------------------------------------------------------------- node-scoped helpers

func _blob_under(root: Node3D, pos: Vector3, half: Vector3, mat: Material, euler := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 12
	sm.rings = 7
	sm.material = mat
	mi.mesh = sm
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi)
	mi.position = pos
	mi.scale = half
	mi.rotation = euler

func _box_under(root: Node3D, pos: Vector3, size: Vector3, mat: Material, euler := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi)
	mi.position = pos
	mi.rotation = euler

func _cyl_under(root: Node3D, pos: Vector3, r: float, h: float, mat: Material, euler := Vector3.ZERO, rings := 8) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = rings
	cm.material = mat
	mi.mesh = cm
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi)
	mi.position = pos
	mi.rotation = euler

# --------------------------------------------------------------- life hooks

func _shelf(pos: Vector3, note: String) -> void:
	_shelves.append({"pos": pos, "note": note})

## Flat / current-swept faces the reef domain can seat corals on. Returned so the
## FloraPatch owner can place life without guessing where the geometry actually is.
func coral_shelves() -> Array[Dictionary]:
	return _shelves

func _report() -> void:
	print("[reef_detail] coral shelves (world coords):")
	for s in _shelves:
		var p: Vector3 = s["pos"]
		print("  (%.1f, %.1f, %.1f)  %s" % [p.x, p.y, p.z, s["note"]])
