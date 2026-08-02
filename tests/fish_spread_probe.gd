extends Node3D
## WHERE THE SHOALS ACTUALLY ARE, AND WHICH WAY THEY ARE POINTING.
##
## Two owner complaints, one harness, because both are about the same 40 species and
## relaunching Godot lags the owner's machine:
##
##   1. "The fish generation got messed up under the rig with the new fish species."
##      s31 added eleven species and every one of them was stocked into the same
##      ±24 x ±28 m box the other twenty-nine work, because `water` in data/fish.json
##      steered the CATCH ROLL and nothing else. This probe counts members by water class
##      and measures how many bodies are in the volume a player looks down into from the
##      wet deck, so "less crowded under the rig" is a number rather than an impression.
##
##   2. "At least one of the new grouper models is swimming backwards."
##      The facing table is measured off the raw mesh (tools/measure_facing.py) and read
##      off a render (tests/CandShot). Neither of those watches the animal SWIM, so
##      neither can catch a species that is correct in the table and reversed in the
##      world. This one correlates each species' live travel direction against its own
##      mesh geometry — no reference to CreatureAnim.FACING_OVERRIDES at all, so it is an
##      independent check of that table rather than a restatement of it.
##
## HOW THE HEAD END IS FOUND WITHOUT ASKING THE FACING TABLE. A fish's mass runs forward:
## the head carries the skull, the gill mass and the pectoral girdle while the tail tapers
## to a peduncle. So along the mesh's longest axis, the VERTEX CENTROID sits on the head
## side of the bounding-box centre. tools/measure_facing.py calibrated exactly this
## statistic against the fourteen fish whose facing is already pinned in creature_anim.gd
## and got 14/14 — it is only unreliable on non-fish (it calls the herring gull backwards),
## and every species here is a fish.
##
## HEADLESS IS HONEST HERE. The shoals are real Node3Ds, not a MultiMesh, so their
## transforms read back correctly under --headless (the MultiMesh identity trap does not
## apply). What DOES apply is that underwater_world only swims a school while its subtree
## is visible, and _cull_topside keys that off camera height — so the camera is put under
## the water before anything is measured, and the probe asserts the pods left the origin.
##
##     godot --headless --path . res://tests/FishSpreadProbe.tscn

const ANIM := preload("res://scripts/world/creature_anim.gd")

## The volume the owner is complaining about: what you see looking down off the wet deck.
## The rig's own footprint plus the walkways — legs at |x| 22 / |z| 12, pontoon out to
## x ±28, so a body inside this box is "under the rig" in the sense that was meant.
const RIG_BOX := Vector2(30.0, 34.0)
const LEGS := [Vector2(-22, -12), Vector2(22, -12), Vector2(-22, 12), Vector2(22, 12)]

## The eleven species s31 added. Broken out on its own line in the report because THIS is
## the number the owner's complaint is actually about — "a few extra appearances" — and
## the all-species total hides it: pulling the pelagics out to the open ring while pulling
## the groupers in onto the legs leaves the gross under-rig count nearly flat while
## completely changing whose bodies those are.
const S31_SPECIES := [
	"fish_bluefin_tuna", "fish_yellowfin_tuna", "fish_bigeye_tuna", "fish_albacore_tuna",
	"fish_skipjack_tuna", "fish_bluelined_grouper", "fish_peacock_grouper",
	"fish_humpback_grouper", "fish_leopard_grouper", "fish_mahi_mahi", "fish_swallowtail",
]

## EVERY PHASE GETS A WINDOW, because a species that keeps hours is HIDDEN outside them and
## a hidden pod does not move at all (`root.visible = want`, then `continue`). A first cut
## of this probe measured in DAY only and reported 26 pods "still on the world origin" and
## thirteen species with "not enough travel to judge" — all of them the night shift, all of
## them working exactly as designed. Measuring one phase cannot see two thirds of the table.
const PHASES := ["DAY", "NIGHT", "DAWN", "DUSK"]   ## ...plus a forced squall, see _run()
## Per phase. The slowest circuit (the open ring at 58 m) runs at 1.15 m/s.
const SWIM_SECONDS: float = 26.0
const TIME_SCALE: float = 4.0
## Where the camera sits while it all happens. Below TOPSIDE_MARGIN so the subtree is
## visible and the schools tick, and deep enough to be in the band rather than on it.
const EYE := Vector3(0.0, -8.0, 0.0)

## A species passes the facing check when its mesh's head end leads its travel. The bar is
## deliberately low: this is looking for a model that is REVERSED (dot near -1) or BROADSIDE
## (dot near 0), not for a few degrees of yaw lag through a turn, and a shoal fish is
## banking constantly. Every correctly-facing species measures +0.93 or better.
const FACING_MIN: float = 0.25

## WHERE THIS INSTRUMENT CANNOT JUDGE, AND WHAT WAS DONE INSTEAD.
##
## The head-end statistic assumes a fish's mass runs forward along its longest axis. FIVE
## species in this table break that assumption, and every one of them is the same two body
## plans: a bill/needle snout that carries no mass in front of a heavy tail, or a ray whose
## WINGS are longer than its body. The probe called four of them backwards on its first run
## and all four were false alarms. They are named here rather than silently tolerated, with
## what a render actually showed, because an assertion that is quietly skipped is how a
## real defect hides:
##
##   fish_glasspike     — a needle snout carries almost no mass while the forked tail
##                        carries a lot, so the centroid lands aft. CandShot side view
##                        s34: beak screen-LEFT = local +Z = the default, CORRECT.
##   fish_kelp_pipefish — same shape problem, worse: the tail is a broad paddle. CandShot
##                        three-quarter view s34 shows the pectoral fin and the eye at the
##                        needle end, screen-LEFT = local +Z = the default, CORRECT.
##   fish_squall_garfish— a billfish: 1.99 m of body with a bill on the front and a heavy
##                        forked tail behind. Only ever on shift during a squall, so the
##                        forced-storm window below is the only thing that has ever watched
##                        it swim. CandShot side view s34: bill screen-LEFT = local +Z =
##                        the default, CORRECT.
##   fish_anchor_ray    — a ray's WINGSPAN is its longest axis (2.000 X against 1.919 Z),
##                        so "along the body" picks the wrong axis outright and the answer
##                        is meaningless rather than merely noisy. CandShot front view s34
##                        photographs it head-on with the wings spanning the frame, i.e.
##                        nose on +Z = the default, CORRECT.
##   fish_ribbon_eel    — authored along X and CURVED, so the centroid is weak (vol -0.029,
##                        width -0.007). This one was NOT a false alarm: the probe read
##                        +0.011, i.e. perpendicular, and the render confirmed a body lying
##                        across Godot's forward. Fixed s34 with a FACING_OVERRIDES entry.
##                        It stays listed because the STATISTIC still cannot judge it — the
##                        fix was verified by eye, and a future regression here would have
##                        to be caught the same way.
const MESH_UNJUDGEABLE := {
	"fish_glasspike": "needle snout, mass aft — render s34: +Z, default correct",
	"fish_kelp_pipefish": "needle snout + paddle tail — render s34: +Z, default correct",
	"fish_squall_garfish": "billfish, mass aft — render s34: +Z, default correct",
	"fish_anchor_ray": "wingspan is the long axis — render s34: +Z, default correct",
	"fish_ribbon_eel": "curved, X-authored — render s34: head at -X, override added",
}

var _main: Node3D
var _uw: Node3D
var _fail: int = 0
## THE COMPLETION SENTINEL. A script error inside an awaited coroutine abandons it and
## returns quietly to the caller, which then reports FAILURES: 0 over a run that stopped a
## third of the way through (docs/AGENT_TRAPS.md, s27). Set on the last line of the body.
var _done: bool = false

func _process(_d: float) -> void:
	if get_tree().paused:
		get_tree().paused = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = load("res://scenes/Main.tscn").instantiate()
	# A parse error anywhere in the world graph hands back a bare Node with its script
	# dropped, which builds nothing and passes every assertion below vacuously.
	if _main.get_script() == null:
		print("[fishspread] Main.tscn instantiated WITHOUT its script — aborting")
		get_tree().quit(1)
		return
	add_child(_main)
	await _run()
	# THE SENTINEL, CHECKED. `_run` sets `_done` on its own last line; if a script error
	# inside it abandoned the coroutine, control returns here with `_done` still false and
	# the report says so instead of printing a clean pass over a run that stopped early.
	if not _done:
		print("[fishspread] the probe body did not reach its end — a script error inside an "
			+ "awaited coroutine abandoned it. Everything above is a PARTIAL run.")
		_fail += 1
	print("\n[fishspread] FAILURES: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

func _run() -> void:
	await get_tree().create_timer(20.0).timeout
	GameClock.force_phase(GameClock.Phase.DAY)

	_uw = _by_script(_main, "underwater_world.gd")
	if _uw == null:
		print("[fishspread] FAIL: no UnderwaterWorld in the tree")
		_fail += 1
		_done = true
		return

	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player != null:
		player.set_physics_process(false)
		player.set_process(false)
		player.remove_from_group("player")     # or the fauna hunts the lens
		player.global_position = EYE
	# _cull_topside reads the CAMERA, not the player, so the camera is what has to be down
	# here — and it is re-asserted every frame of the swim window below, because the
	# controller keeps integrating across an await (the s21 "a vantage has to be HELD" trap).
	var cam: Camera3D = _camera(player)

	for ph in PHASES:
		GameClock.force_phase(GameClock.Phase[ph])
		await _swim(player, cam)
		_snapshot(ph)
	# ...AND ONE SQUALL. Two species (the drum croaker chorus and the squall garfish) carry
	# an EMPTY `active` list, which underwater_world reads as "on shift when it is storming"
	# rather than "never" — so a probe that only walks the four daylight phases leaves 20
	# fish per pod unjudged and prints a clean pass over them. `_phase` is pinned alongside
	# `_intensity` because the storm's own _process would ramp it straight back down.
	var st: Node = _main.get("storm")
	if st != null:
		st.set_process(false)
		st.set("_intensity", 1.0)
		st.set("_phase", 2)
		await _swim(player, cam)
		_snapshot("STORM")
		st.set("_intensity", 0.0)
	_report_spread()
	_report_facing()
	_done = true

func _camera(player: Node3D) -> Camera3D:
	if player != null and player.has_node("Head/Camera3D"):
		var c: Camera3D = player.get_node("Head/Camera3D")
		c.current = true
		return c
	return null

## THE ALIGNMENT IS ACCUMULATED PER FRAME, NOT AS A NET DISPLACEMENT. The first cut summed
## each pod's displacement over the whole window and took the direction of the sum, which
## reported the herring, the cod, the pipefish and three groupers as BACKWARDS — and every
## one of those was an artifact: a pod wanders a CLOSED circuit, so over a full lap the
## displacements cancel and the residual points wherever the lap happened to stop. What is
## wanted is the correlation the traps file asks for — "correlate travel direction against
## the model's own local axes over a few hundred frames" — so each frame contributes
## dot(mesh head, that frame's velocity) and the answer is the mean of those.
var _dot_sum: Dictionary = {}     # species id -> sum of per-frame alignment
var _samples: Dictionary = {}     # species id -> how many frames went into it
var _dist: Dictionary = {}        # species id -> path length actually swum
## The mesh's head axis in its OWN local frame, per species. A property of the geometry, so
## it is computed once and reused — and computing it once is what makes the per-frame dot
## affordable.
var _head_local: Dictionary = {}

func _swim(player: Node3D, cam: Camera3D) -> void:
	Engine.time_scale = TIME_SCALE
	var prev: Dictionary = {}
	var elapsed: float = 0.0
	while elapsed < SWIM_SECONDS:
		# Re-assert the pose every frame — see the note at the call site.
		if player != null:
			player.global_position = EYE
		if cam != null:
			cam.global_position = EYE
		await get_tree().process_frame
		elapsed += get_process_delta_time() * TIME_SCALE
		for s in _schools():
			var root: Node3D = s["root"]
			if not root.visible:
				continue          # off-shift: hidden, and deliberately not simulated
			var id: String = String(s["id"])
			var fish: Array = s["fish"]
			if fish.is_empty():
				continue
			# One representative member per pod is enough and keeps this O(pods): every
			# member of a shoal shares the pod's heading to within its own orbit wobble.
			var f: Node3D = fish[0]
			if not is_instance_valid(f):
				continue
			var p: Vector3 = f.global_position
			var key: String = "%s#%d" % [id, int(s["pod"])]
			if prev.has(key):
				var d: Vector3 = p - (prev[key] as Vector3)
				# Skip the seat frame and any teleport: a pod's first live frame moves its
				# fish from the world origin, which is not travel.
				if d.length() > 0.002 and d.length() < 3.0:
					var head: Vector3 = _head_dir_world(f, id)
					if head != Vector3.ZERO:
						var a := Vector3(head.x, 0.0, head.z)
						var b := Vector3(d.x, 0.0, d.z)
						if a.length() > 0.01 and b.length() > 0.0001:
							_dot_sum[id] = float(_dot_sum.get(id, 0.0)) \
								+ a.normalized().dot(b.normalized())
							_samples[id] = int(_samples.get(id, 0)) + 1
							_dist[id] = float(_dist.get(id, 0.0)) + d.length()
			prev[key] = p
	Engine.time_scale = 1.0

## One position snapshot per phase, of the pods that are ACTUALLY ON SHIFT — a hidden pod
## is parked at its anchor and counting it would report the night shift as a crowd under
## the rig that no player can ever see.
var _snap: Array = []             # [{id, water, pos, visible_pods}]

func _snapshot(phase: String) -> void:
	var shown: int = 0
	var hidden: int = 0
	for s in _schools():
		var root: Node3D = s["root"]
		if not root.visible:
			hidden += 1
			continue
		shown += 1
		var water: String = String((s["def"] as Dictionary).get("water", "any"))
		for f in s["fish"]:
			if is_instance_valid(f):
				_snap.append({"id": s["id"], "water": water, "pos": (f as Node3D).global_position,
					"centre": s["centre"], "phase": phase})
	print("  [%s] %d pods on shift, %d off" % [phase, shown, hidden])

func _schools() -> Array:
	var v: Variant = _uw.get("_schools")
	return (v as Array) if v != null else []

# ------------------------------------------------------------------ 1. spread

func _report_spread() -> void:
	print("\n=== where the shoals are (pods on shift, averaged over all four phases) ===")
	var by_water: Dictionary = {}       # water class -> [members, in_box, dist_sum]
	var total: int = 0
	var in_box: int = 0
	var origin_pods: int = 0
	for row_v in _snap:
		var e: Dictionary = row_v
		var water: String = String(e["water"])
		var row: Array = by_water.get(water, [0, 0, 0.0])
		var p: Vector3 = e["pos"]
		var centre: Vector3 = e["centre"]
		# THE TRAP: a pod that never got a live frame is still stacked on its anchor, and
		# every measurement taken off it is fiction that looks like a pass. Checked here
		# rather than over all pods, because an OFF-SHIFT pod is parked on purpose.
		if Vector2(centre.x, centre.z).length() < 0.001:
			origin_pods += 1
		total += 1
		row[0] = int(row[0]) + 1
		row[2] = float(row[2]) + Vector2(p.x, p.z).length()
		if absf(p.x) <= RIG_BOX.x and absf(p.z) <= RIG_BOX.y:
			in_box += 1
			row[1] = int(row[1]) + 1
		by_water[water] = row
	print("  %d fish-samples over %d phases" % [total, PHASES.size()])
	for w in ["near", "any", "open"]:
		if not by_water.has(w):
			continue
		var r: Array = by_water[w]
		var n: int = int(r[0])
		print("  %-5s %4d fish, %4d of them under the rig, mean %.1f m from centre"
			% [w, n, int(r[1]), float(r[2]) / maxf(float(n), 1.0)])
	print("  UNDER THE RIG (|x|<=%.0f, |z|<=%.0f): %d of %d fish (%.1f%%)"
		% [RIG_BOX.x, RIG_BOX.y, in_box, total, 100.0 * float(in_box) / maxf(float(total), 1.0)])

	# The owner's actual question: how much of the water is the NEW eleven?
	var s31_total: int = 0
	var s31_box: int = 0
	for row_v3 in _snap:
		var e3: Dictionary = row_v3
		if not S31_SPECIES.has(String(e3["id"])):
			continue
		s31_total += 1
		var p3: Vector3 = e3["pos"]
		if absf(p3.x) <= RIG_BOX.x and absf(p3.z) <= RIG_BOX.y:
			s31_box += 1
	print("  of which the ELEVEN s31 SPECIES: %d fish (%.1f%% of the ocean), %d under the rig "
		% [s31_total, 100.0 * float(s31_total) / maxf(float(total), 1.0), s31_box]
		+ "(%.1f%% of what is under there)" % [100.0 * float(s31_box) / maxf(float(in_box), 1.0)])

	_ok(total > 400, "the ocean is stocked (%d samples)" % total)
	_ok(origin_pods == 0,
		"every ON-SHIFT pod left its spawn point (%d still on it — those measure nothing)"
			% origin_pods)

	# The near species hold a caisson. Measured against the LEG RING, not against a box,
	# because "tight groups near the legs" is a statement about the structure.
	var near_far: float = 0.0
	var near_pods: int = 0
	for row_v2 in _snap:
		var e2: Dictionary = row_v2
		if String(e2["water"]) != "near":
			continue
		near_pods += 1
		var c: Vector3 = e2["centre"]
		var best: float = 1e9
		for l in LEGS:
			best = minf(best, Vector2(c.x, c.z).distance_to(l))
		near_far = maxf(near_far, best)
	if near_pods > 0:
		print("  worst `near` pod centre is %.1f m from its nearest caisson" % near_far)
		# DERIVED, NOT GUESSED — and the first version of this bound was wrong because it
		# forgot pod 1. A `near` species runs TWO pods about its legs: ±6.5 x ±7.5 and
		# ±9.0 x ±10.5, each with the wander's 16% second octave on top. The furthest a
		# centre can legitimately reach is therefore hypot(9.0, 10.5) * 1.16 = 16.04 m, so
		# anything under 17 is the design working and 24+ would mean a pod escaped its leg.
		_ok(near_far < 17.0,
			"every `near` pod is holding a caisson (worst %.1f m, ceiling 16.0)" % near_far)

	# And the pelagics are OUT. An `open` species averaging less than the rig's own
	# half-width from the centre line is swimming under the rig, whatever the table says.
	if by_water.has("open"):
		var r2: Array = by_water["open"]
		var mean_d: float = float(r2[2]) / maxf(float(int(r2[0])), 1.0)
		_ok(mean_d > 30.0,
			"`open` species average %.1f m out, past the rig footprint" % mean_d)

# ------------------------------------------------------------------ 2. facing

func _report_facing() -> void:
	print("\n=== is every species swimming forwards? ===")
	print("  %-26s %8s %7s %7s  %s" % ["species", "mean dot", "frames", "swum", ""])
	var ids: Array = []
	for s in _schools():
		if not ids.has(s["id"]):
			ids.append(s["id"])
	ids.sort()
	for id_v in ids:
		var id: String = String(id_v)
		var n: int = int(_samples.get(id, 0))
		if n < 60:
			print("  %-26s        —       —       —  too few frames to judge (%d)" % [id, n])
			continue
		var d: float = float(_dot_sum.get(id, 0.0)) / float(n)
		if MESH_UNJUDGEABLE.has(id):
			print("  %-26s %+8.3f %7d %7.1f  not judged — %s"
				% [id, d, n, float(_dist.get(id, 0.0)), MESH_UNJUDGEABLE[id]])
			continue
		var verdict: String = "ok" if d >= FACING_MIN else \
			("BROADSIDE" if d > -FACING_MIN else "BACKWARDS")
		print("  %-26s %+8.3f %7d %7.1f  %s" % [id, d, n, float(_dist.get(id, 0.0)), verdict])
		_ok(d >= FACING_MIN, "%s swims head-first (mean mesh-head . velocity = %+.3f)" % [id, d])

## Where this fish's MESH says its head is, in world space. Derived from the geometry the
## generator produced — the vertex centroid sits on the head side of the bounding-box
## centre along the body's longest axis — so it owes nothing to the facing table it is
## checking. Returns ZERO when there is no generated mesh under this node.
##
## The LOCAL axis is a property of the species' mesh, so it is resolved once and cached;
## only the basis multiply is paid per frame.
func _head_dir_world(f: Node3D, id: String) -> Vector3:
	var mi: MeshInstance3D = null
	for n in f.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = n
		if m.mesh != null and m.mesh.get_surface_count() > 0:
			mi = m
			break
	if mi == null:
		return Vector3.ZERO
	if not _head_local.has(id):
		_head_local[id] = _head_axis_local(mi)
	var local: Vector3 = _head_local[id]
	if local == Vector3.ZERO:
		return Vector3.ZERO
	# Into world space through the mesh instance's own basis, which carries every rotation
	# CreatureAnim applied — the model node's yaw AND the host's look_at.
	return (mi.global_transform.basis * local).normalized()

func _head_axis_local(mi: MeshInstance3D) -> Vector3:
	var box: AABB = mi.get_aabb()
	var ext: Vector3 = box.size
	var axis: int = 0
	if ext.y > ext.x and ext.y >= ext.z:
		axis = 1
	elif ext.z > ext.x and ext.z >= ext.y:
		axis = 2
	# Vertex centroid, one surface is plenty — these are single-surface generated meshes and
	# a second surface is a fin cluster that would only sharpen the same answer.
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		return Vector3.ZERO
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return Vector3.ZERO
	var sum: float = 0.0
	for v in verts:
		sum += v[axis]
	var mean: float = sum / float(verts.size())
	var mid: float = box.position[axis] + box.size[axis] * 0.5
	var local := Vector3.ZERO
	local[axis] = 1.0 if mean > mid else -1.0
	return local

# ------------------------------------------------------------------ plumbing

func _ok(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		_fail += 1

func _by_script(root: Node, file: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var sc: Script = n.get_script()
		if sc != null and sc.resource_path.get_file() == file:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
