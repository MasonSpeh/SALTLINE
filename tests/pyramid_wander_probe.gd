extends Node
## PYRAMID SNAIL: does it actually wander the rig, and does it sit FLUSH on the plating?
##
## Two things this species has to get right that the other three did not:
##   1. FREE EXPLORATION — a fresh random heading held for a randomised stretch of tens of
##      seconds. So the tell is not "does it circle" (SnailPathProbe's test) but "does it
##      travel": high straightness, real net displacement, and headings that differ
##      between animals rather than three snails marching in step.
##   2. FLUSH SEATING — the known bug in this project's history is snails floating ~6 cm
##      proud of the plating from a badly-cast grounding ray. Measured here by dropping a
##      ray from above each animal and comparing the hit to its origin: SurfaceCrawler
##      holds the foot FOOT (0.02 m) off the face, so anything much over that is a float.
##
## Run: godot --headless --path . res://tests/PyramidWanderProbe.tscn

const SAMPLE_SEC: float = 120.0
const FOOT_TOL: float = 0.06     ## metres of clearance we will accept over the FOOT offset

func _ready() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(3.0).timeout

	var snails: Array = get_tree().get_nodes_in_group("snail_pyramid")
	if snails.is_empty():
		print("no pyramid snails found")
		get_tree().quit(1)
		return
	var tracks: Dictionary = {}
	for n in snails:
		tracks[n.get_instance_id()] = {
			"start": (n as Node3D).global_position, "prev": (n as Node3D).global_position,
			"path": 0.0, "turn": 0.0, "last_dir": Vector3.ZERO,
			"float_max": 0.0, "float_sum": 0.0, "float_n": 0, "heads": [],
			"climb_n": 0, "sample_n": 0, "y_min": 1e9, "y_max": -1e9,
		}
	var elapsed: float = 0.0
	var next_sample: float = 0.0
	while elapsed < SAMPLE_SEC:
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		elapsed += dt
		var sample: bool = elapsed >= next_sample
		if sample:
			next_sample = elapsed + 2.0
		for n in snails:
			if not is_instance_valid(n):
				continue
			var tr: Dictionary = tracks[n.get_instance_id()]
			var d: Vector3 = (n as Node3D).global_position - tr["prev"]
			d.y = 0.0
			tr["path"] += d.length()
			if d.length() > 0.0005:
				var dir: Vector3 = d.normalized()
				if tr["last_dir"] != Vector3.ZERO:
					tr["turn"] += rad_to_deg(atan2(tr["last_dir"].cross(dir).y,
						clampf(tr["last_dir"].dot(dir), -1.0, 1.0)))
				tr["last_dir"] = dir
			tr["prev"] = (n as Node3D).global_position
			if sample:
				tr["heads"].append(rad_to_deg(atan2(n.get("_crawler").heading.x,
					n.get("_crawler").heading.z)))
				tr["sample_n"] += 1
				tr["y_min"] = minf(tr["y_min"], (n as Node3D).global_position.y)
				tr["y_max"] = maxf(tr["y_max"], (n as Node3D).global_position.y)
				if n.get("_crawler").up.y < 0.9:
					tr["climb_n"] += 1
				var gap: float = _clearance(n)
				if gap >= 0.0:
					tr["float_max"] = maxf(tr["float_max"], gap)
					tr["float_sum"] += gap
					tr["float_n"] += 1

	print("--- pyramid snail wander probe (%.0fs, %d animals) ---" % [SAMPLE_SEC, snails.size()])
	var fails: int = 0
	for n in snails:
		var tr: Dictionary = tracks[n.get_instance_id()]
		var net: float = ((n as Node3D).global_position - tr["start"]).length()
		var path: float = tr["path"]
		var straight: float = (net / path) if path > 0.01 else 0.0
		var mean_gap: float = (tr["float_sum"] / float(tr["float_n"])) if tr["float_n"] > 0 else -1.0
		var turns: int = _distinct_headings(tr["heads"])
		var verdict := "OK"
		if path < 1.5:
			verdict = "NOT MOVING"
			fails += 1
		if straight < 0.15 and absf(tr["turn"]) / 360.0 > 3.0:
			verdict = "CIRCLING"
			fails += 1
		if mean_gap > FOOT_TOL:
			verdict += " FLOATING(mean %.3fm)" % mean_gap
			fails += 1
		print("  path=%5.2fm net=%5.2fm straight=%.2f turn=%6.0fdeg legs=%d  seat mean=%.3fm max=%.3fm  y %.2f..%.2f  climbing %d/%d  %s"
			% [path, net, straight, tr["turn"], turns, mean_gap, tr["float_max"],
				tr["y_min"], tr["y_max"], tr["climb_n"], tr["sample_n"], verdict])
	print("PYRAMID-FAILURES: ", fails)
	get_tree().quit(0)

## Metres between the snail's origin and the real surface it is stuck to (fauna excluded,
## so a passing animal's touch sphere is never mistaken for the deck). -1 when nothing is
## under it. The ray is cast along the crawler's OWN up, not world down: this species may
## legitimately be halfway up a bulkhead, where a world-down ray measures the distance to
## the floor and calls a perfectly seated snail a floater.
func _clearance(n: Node3D) -> float:
	var world: World3D = n.get_world_3d()
	if world == null:
		return -1.0
	var up: Vector3 = n.get("_crawler").up
	var q := PhysicsRayQueryParameters3D.create(n.global_position + up * 0.8,
		n.global_position - up * 2.0)
	q.collide_with_areas = false
	q.exclude = BloomFauna.fauna_bodies(n)
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return -1.0
	return absf((n.global_position - (hit["position"] as Vector3)).dot(up))

## How many times the sampled heading changed by more than 40 degrees — a count of legs.
func _distinct_headings(heads: Array) -> int:
	var legs: int = 0
	for i in range(1, heads.size()):
		if absf(angle_difference(deg_to_rad(heads[i - 1]), deg_to_rad(heads[i]))) > deg_to_rad(40.0):
			legs += 1
	return legs
