extends Node3D
## THE REAL CORAL, in the tank (s60). The owner's point, verbatim: the game already ships
## twenty REAL reef species around rig 1's legs (assets/models/fauna/reef/*) and the
## oceanarium was still dressed in tinted boxes. This node plants the actual meshes —
## one MultiMesh per species, hand-curated transforms on the reef bed and up the coral
## core, per-instance colour variation exactly the way leg_reef does it.
##
## Loader is a compact copy of leg_reef._load's contract (first MeshInstance3D of the
## GLB, material duplicated with vertex-colour albedo, mesh treated as 1 m-normalised by
## its longest axis). Placement is DETERMINISTIC (golden-angle series, no RNG) so the
## save-independent tank looks the same every boot. Every piece is rooted: bases sink
## 6-12 cm into the bed or the core rock, never floating.
##
## Cost: ~12 MultiMesh draws, range-culled at 90 m — the tank is indoors and invisible
## from further than the drum anyway. Not part of the Bake, so the field's far-chunk
## budget (a bake-group count) is untouched; the draws are logged at load instead.

var tank_centre := Vector3.ZERO   ## set by the builder before add_child
var tank_r: float = 5.0
var y0: float = 0.0               ## water floor (bed level = y0 + ~1.1 in tank terms)
var y1: float = 1.0

const REEF_PATH := "res://assets/models/fauna/reef/%s/%s.glb"

## [slug, count, on_core, base_scale, scale_jitter, tint_a, tint_b]
const SET: Array = [
	["reefmass_a", 3, false, 1.20, 0.35, Color(0.85, 0.80, 0.72), Color(0.70, 0.72, 0.66)],
	["reefmass_b", 3, false, 1.05, 0.30, Color(0.80, 0.76, 0.70), Color(0.66, 0.70, 0.64)],
	["coral_brain", 5, false, 0.62, 0.30, Color(0.95, 0.78, 0.55), Color(0.88, 0.60, 0.50)],
	["coral_bubble", 4, false, 0.50, 0.30, Color(0.92, 0.88, 0.78), Color(0.80, 0.85, 0.75)],
	["coral_plate", 3, false, 0.80, 0.30, Color(0.90, 0.62, 0.40), Color(0.85, 0.75, 0.45)],
	["sponge_barrel", 4, false, 0.55, 0.35, Color(0.85, 0.50, 0.42), Color(0.75, 0.55, 0.60)],
	["bloom_anemone", 5, false, 0.42, 0.30, Color(0.55, 0.90, 0.85), Color(0.90, 0.70, 0.90)],
	["coral_fan_a", 5, false, 1.00, 0.35, Color(0.90, 0.45, 0.50), Color(0.75, 0.55, 0.85)],
	["coral_branch_a", 4, true, 0.70, 0.30, Color(0.95, 0.60, 0.35), Color(0.90, 0.50, 0.55)],
	["coral_branch_b", 4, true, 0.62, 0.30, Color(0.80, 0.70, 0.40), Color(0.60, 0.80, 0.70)],
	["barnacle_cluster_a", 4, true, 0.55, 0.30, Color(0.82, 0.80, 0.72), Color(0.70, 0.68, 0.62)],
	["sponge_tube_cluster", 3, true, 0.55, 0.30, Color(0.70, 0.60, 0.85), Color(0.55, 0.75, 0.80)],
]

func _ready() -> void:
	var bed_y: float = y0 + 1.12
	var core_h: float = (y1 - y0) - 1.8
	var draws: int = 0
	var seq: int = 0
	for sp in SET:
		var slug: String = sp[0]
		var path: String = REEF_PATH % [slug, slug]
		if not ResourceLoader.exists(path):
			push_warning("[tank_reef] missing %s" % path)
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var inst := packed.instantiate()
		var found: MeshInstance3D = null
		for node in inst.find_children("*", "MeshInstance3D", true, false):
			found = node
			break
		if found == null or found.mesh == null:
			inst.queue_free()
			continue
		var mesh: Mesh = found.mesh
		var aabb: AABB = mesh.get_aabb()
		var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		var src: Material = found.get_active_material(0)
		inst.queue_free()
		var mat: StandardMaterial3D = src.duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = maxf(mat.roughness, 0.75)
		mat.metallic = 0.0
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		var count: int = int(sp[1])
		mm.instance_count = count
		var on_core: bool = bool(sp[2])
		for i in range(count):
			seq += 1
			var t: float = fmod(float(seq) * 0.618, 1.0)
			var a: float = float(seq) * 2.39996
			var k: float = (float(sp[3]) + float(sp[4]) * (fmod(float(seq) * 0.47, 1.0) - 0.5)) / maxf(longest, 0.01)
			var pos: Vector3
			var tilt := Basis(Vector3.UP, a)
			if on_core:
				# On the rock column: hug its tapering radius, tilted outward so the
				# piece grows OFF the face rather than hovering beside it.
				var ct: float = 0.12 + 0.75 * t
				var cr: float = lerpf(1.62, 0.90, ct) + 0.04
				pos = tank_centre + Vector3(cos(a) * cr, bed_y - tank_centre.y + core_h * ct, sin(a) * cr)
				tilt = Basis(Vector3(sin(a), 0, -cos(a)).normalized(), deg_to_rad(48.0)) * tilt
			else:
				# On the bed: annulus between core clearance and the kelp line, sunk in.
				var br: float = lerpf(2.1, tank_r - 1.15, t)
				pos = tank_centre + Vector3(cos(a) * br, bed_y - tank_centre.y - 0.08, sin(a) * br)
				tilt = Basis(Vector3.RIGHT, deg_to_rad(6.0 * (fmod(float(seq) * 0.31, 1.0) - 0.5))) * tilt
			var xf := Transform3D(tilt.scaled(Vector3.ONE * k), pos - global_position)
			mm.set_instance_transform(i, xf)
			mm.set_instance_color(i, (sp[5] as Color).lerp(sp[6] as Color, fmod(float(seq) * 0.71, 1.0)))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.visibility_range_end = 90.0
		mi.visibility_range_end_margin = 8.0
		add_child(mi)
		draws += 1
	print("[tank_reef] %d species planted as %d MultiMesh draws" % [SET.size(), draws])
