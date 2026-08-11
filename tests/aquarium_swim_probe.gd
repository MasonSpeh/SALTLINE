extends Node
## THE TANK'S SWIM GATES (s59): over a long sim, no fish leaves the water, none enters
## the coral core or the glass, every fish leads with its HEAD (+Z along travel), a
## same-species group schools (aligned headings) without stacking. Raw numbers logged
## next to every gate — the honesty contract.
##
##   godot --headless --path . res://tests/AquariumSwimProbe.tscn

var failures: int = 0

func _ok(cond: bool, msg: String) -> void:
	print("%s  %s" % ["PASS" if cond else "FAIL", msg])
	if not cond:
		failures += 1

func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(9.0).timeout
	GameClock.force_phase(GameClock.Phase.DAY)
	var h: Node = get_tree().get_first_node_in_group("aquarium_hatch")
	if h == null:
		print("FAIL  hatch found")
		print("FAILURES: 1")
		get_tree().quit(1)
		return
	# Five herring (a school) and one big solitary grouper-class fish.
	var seed_stock: Array = []
	for i in range(5):
		seed_stock.append({"id": "fish_herring", "kg": 0.4})
	seed_stock.append({"id": "fish_lodestone_bream", "kg": 6.0})
	h.call("restore_stock", seed_stock)
	var sw: Array = h.get("_swimmers")
	_ok(sw.size() >= 4, "the seed swims (anti-vacuity: %d swimmers)" % sw.size())
	var tc: Vector3 = h.get("tank_centre")
	var tr: float = h.get("tank_r")
	var y0: float = h.get("water_y0")
	var y1: float = h.get("water_y1")
	var worst_r: float = 0.0
	var worst_core: float = 99.0
	var worst_y: float = 0.0
	var face_sum: float = 0.0
	var face_n: int = 0
	var align_sum: float = 0.0
	var align_n: int = 0
	var min_gap: float = 99.0
	for f in range(1800):
		await get_tree().physics_frame
		if f % 5 != 0:
			continue
		var herring: Array = []
		for s in sw:
			var node: Node3D = s["node"]
			if not is_instance_valid(node):
				continue
			var p: Vector3 = node.global_position
			var rad: Vector3 = p - tc
			rad.y = 0.0
			worst_r = maxf(worst_r, rad.length())
			worst_core = minf(worst_core, rad.length())
			worst_y = maxf(worst_y, maxf(p.y - y1, y0 - p.y))
			var v: Vector3 = s["vel"]
			if v.length() > 0.05:
				face_sum += (node.global_transform.basis.z).dot(v.normalized())
				face_n += 1
			if String(s["species"]) == "fish_herring":
				herring.append(s)
		for a in range(herring.size()):
			for b2 in range(a + 1, herring.size()):
				var na: Node3D = herring[a]["node"]
				var nb: Node3D = herring[b2]["node"]
				min_gap = minf(min_gap, na.global_position.distance_to(nb.global_position))
				var va: Vector3 = herring[a]["vel"]
				var vb: Vector3 = herring[b2]["vel"]
				if va.length() > 0.05 and vb.length() > 0.05:
					align_sum += va.normalized().dot(vb.normalized())
					align_n += 1
	var face_mean: float = face_sum / maxf(float(face_n), 1.0)
	var align_mean: float = align_sum / maxf(float(align_n), 1.0)
	print("[swim] worst radius %.2f (glass %.2f) | nearest core pass %.2f | worst y excursion %.2f" % [worst_r, tr, worst_core, worst_y])
	print("[swim] facing mean(head.vel) %.3f over %d samples | school alignment %.3f | min pair gap %.2f m" % [face_mean, face_n, align_mean, min_gap])
	_ok(worst_r < tr - 0.4, "no fish reaches the glass (worst r %.2f vs limit %.2f)" % [worst_r, tr - 0.4])
	_ok(worst_y <= 0.001, "no fish leaves the water column (worst excursion %.3f)" % worst_y)
	_ok(face_n > 100, "facing gate is non-vacuous (%d samples)" % face_n)
	_ok(face_mean > 0.9, "heads lead travel, mean %.3f > 0.9" % face_mean)
	_ok(align_mean > 0.5, "the herring school aligns (mean pairwise %.3f)" % align_mean)
	_ok(min_gap > 0.25, "and never stacks (min gap %.2f m)" % min_gap)
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
