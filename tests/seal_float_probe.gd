extends Node3D
## HARBOR SEAL WATERLINE — ground truth for the repeat "the seal still floats" report.
##
## s23 already fixed one half of this (the patrol wrote a FIXED y into a Gerstner sea) and
## asserted it with "belly above Gyre.wave_height() on 0 of 600 frames". That assertion is
## true and the animal still reads as floating, so the metric was the wrong one: a seal
## whose BELLY is 50 mm under the water and whose whole BACK is a third of a metre proud of
## it is, to look at, a seal sitting on top of the sea.
##
## So this measures the thing a player actually sees — HOW MUCH OF THE BODY IS OUT OF THE
## WATER — for both seals, in both states, against two different statements of where the
## water is:
##
##   sea_h   Gyre.wave_height(xz)      the number the seal's own code steers by
##   sea_g   the true Gerstner surface the SHADER draws at that same world xz, found by
##           inverting the horizontal displacement (ocean_water.gdshader displaces
##           sideways as well as up; Gyre.wave_height answers at the UNDISPLACED
##           parameter point, so the two are not the same water)
##
## Also re-measures the haul-out seat (which collider, at what height, what gap) and the
## patrol's closest approach to the south pontoon, since the s24 lane-split widened r.
##
##   godot --headless --path . res://tests/SealFloatProbe.tscn

const ANIM := preload("res://scripts/world/creature_anim.gd")

var _main: Node3D

func _ready() -> void:
	AiBudget.enabled = false          # every animal at full rate: this is a measurement
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	for i in range(30):
		await get_tree().physics_frame
	var seals: Array = _seals()
	print("\n=== harbor seals found: %d ===" % seals.size())
	for s in seals:
		print("[seal] %s  idx=%d  spawn_index=%s  _belly=%.4f  _haul=%s  _haul_floor=%.4f"
			% [s.name, (s as Node3D).get_index(), str(s.get("spawn_index")),
				float(s.get("_belly")), str((s.get("_haul") as Vector3).snappedf(0.001)),
				float(s.get("_haul_floor"))])
		var m: Node3D = s.get("_model")
		if m == null:
			print("[seal]   NO GENERATED MODEL — the procedural body is what is drawn")
			continue
		var box: AABB = _world_bounds(m)
		print("[seal]   model world AABB pos=%s size=%s   node y=%.3f"
			% [str(box.position.snappedf(0.001)), str(box.size.snappedf(0.001)),
				(s as Node3D).global_position.y])
	if seals.is_empty():
		get_tree().quit()
		return
	_haul_report(seals[0])
	await _swim_report(seals[0], "seal A")
	if seals.size() > 1:
		await _swim_report(seals[1], "seal B")
	get_tree().quit()

# ------------------------------------------------------------------ the haul-out seat
func _haul_report(seal: Node3D) -> void:
	print("\n=== haul-out seat ===")
	var haul: Vector3 = seal.get("_haul")
	var from := Vector3(haul.x, 4.0, haul.z)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 8.0, 0))
	q.collision_mask = 1
	q.exclude = _fauna_rids()
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		print("[haul] NOTHING under (%.2f, %.2f) between y 4 and y -4" % [haul.x, haul.z])
		return
	var col: Object = hit.get("collider")
	print("[haul] floor under (%.2f, %.2f): y=%.4f  collider=%s  parent=%s"
		% [haul.x, haul.z, float((hit["position"] as Vector3).y), str(col),
			str((col as Node).get_parent().name if col is Node else "?")])
	print("[haul] pontoon slab top is y0.95, wet deck plating is y2.00 — which one is that?")

# ------------------------------------------------------------------ the swimming half
func _swim_report(seal: Node3D, label: String) -> void:
	print("\n=== %s : swimming waterline over 600 frames ===" % label)
	var model: Node3D = seal.get("_model")
	if model == null:
		print("[%s] no generated model" % label)
		return
	# SETTLE FIRST. The resident seal may be sitting on the pontoon when the probe starts, and
	# a seal that is still walking its haul-out lerp out of frame 0 is not the thing being
	# measured. AiBudget is re-forced every frame: main.gd turns decimation back on as the
	# world finishes building, and a decimated animal simply does not move on most frames.
	for i in range(90):
		AiBudget.enabled = false
		seal.set("_hauled", false)
		seal.set("_haul_timer", 1.0e9)
		await get_tree().process_frame
	var frames: int = 600
	var out_frames: int = 0            # any part of the body clear of the water
	var proud_sum: float = 0.0         # metres of body height above the surface
	var proud_max: float = -1.0e9
	var frac_sum: float = 0.0          # fraction of body HEIGHT above the surface
	var frac_max: float = 0.0
	var low_max: float = -1.0e9        # highest the belly ever gets, relative to the sea
	var node_max: float = -1.0e9
	var gerstner_gap_sum: float = 0.0  # sea_g - sea_h, i.e. how wrong the steering water is
	var gerstner_gap_max: float = 0.0
	var z_max: float = -1.0e9          # closest approach to the pontoon (z -16)
	for i in range(frames):
		AiBudget.enabled = false
		seal.set("_hauled", false)
		seal.set("_haul_timer", 1.0e9)
		await get_tree().process_frame
		var p: Vector3 = seal.global_position
		var t: float = Gyre.water_time()
		var sea_h: float = Gyre.wave_height(Vector2(p.x, p.z), t)
		var sea_g: float = _surface_at(Vector2(p.x, p.z), t)
		var box: AABB = _world_bounds(model)
		var low: float = box.position.y
		var high: float = box.position.y + box.size.y
		var proud: float = high - sea_g
		if proud > 0.0:
			out_frames += 1
			proud_sum += proud
			proud_max = maxf(proud_max, proud)
			var frac: float = clampf(proud / maxf(box.size.y, 0.001), 0.0, 1.0)
			frac_sum += frac
			frac_max = maxf(frac_max, frac)
		low_max = maxf(low_max, low - sea_g)
		node_max = maxf(node_max, p.y - sea_g)
		gerstner_gap_sum += sea_g - sea_h
		gerstner_gap_max = maxf(gerstner_gap_max, absf(sea_g - sea_h))
		z_max = maxf(z_max, p.z)
	var f: float = float(frames)
	print("[%s] body height (model AABB y) is the denominator for the fractions below" % label)
	print("[%s] SOME PART OF THE BODY OUT OF THE WATER on %d of %d frames (%.1f%%)"
		% [label, out_frames, frames, 100.0 * float(out_frames) / f])
	print("[%s]   when out: mean %.3f m of back proud of the sea, worst %.3f m"
		% [label, proud_sum / maxf(float(out_frames), 1.0), proud_max])
	print("[%s]   when out: mean %.1f%% of the body height above water, worst %.1f%%"
		% [label, 100.0 * frac_sum / maxf(float(out_frames), 1.0), 100.0 * frac_max])
	print("[%s] highest the BELLY reached: %+.3f m relative to the drawn surface" % [label, low_max])
	print("[%s] highest the NODE reached:  %+.3f m relative to the drawn surface" % [label, node_max])
	print("[%s] steering water vs drawn water: mean %+.3f m, worst |%.3f| m"
		% [label, gerstner_gap_sum / f, gerstner_gap_max])
	print("[%s] northernmost z reached: %.2f  (south pontoon face is z -16.00, slab y -3.05..0.95)"
		% [label, z_max])

## The height of the surface the SHADER actually draws at world xz.
##
## ocean_water.gdshader evaluates Gerstner at a parameter point x0 and then moves that
## vertex sideways by disp.xz — so the surface point that ENDS UP over world xz came from
## x0 = xz - disp.xz(x0). Three fixed-point iterations are plenty at this steepness.
func _surface_at(xz: Vector2, t: float) -> float:
	var p: Vector2 = xz
	for _i in range(3):
		var d: Vector3 = Gyre.wave_offset(p, t)
		p = xz - Vector2(d.x, d.z)
	return Gyre.wave_offset(p, t).y

# ------------------------------------------------------------------------- helpers
func _seals() -> Array:
	var out: Array = []
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		if n.get("_haul") != null and n.get("_haul_floor") != null:
			out.append(n)
	return out

func _world_bounds(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var w: AABB = mi.global_transform * mi.get_aabb()
		acc = w if first else acc.merge(w)
		first = false
	return acc

## FaunaTouch is a StaticBody3D on layer 1 and will happily be measured as "the floor".
func _fauna_rids() -> Array[RID]:
	var out: Array[RID] = []
	for n in get_tree().root.find_children("*", "CollisionObject3D", true, false):
		var host: Node = n
		var depth: int = 0
		while host != null and depth < 12:
			var s: Script = host.get_script()
			if s != null:
				var rp: String = String(s.resource_path)
				if rp.ends_with("bloom_fauna.gd") or rp.ends_with("leg_reef.gd") \
						or rp.ends_with("mussel_beds.gd") or rp.ends_with("reef_life.gd"):
					out.append((n as CollisionObject3D).get_rid())
					break
			host = host.get_parent()
			depth += 1
	return out
