extends Node
## CAT SPAWN PROBE — is the cat's HOME a real, standable, LIT place?
##
##   godot --headless --path . res://tests/CatSpawnProbe.tscn
##
## Owner: "Have the cat spawn in the 2nd internal room near a light so it is illuminated in
## the dark." Four separate claims are hiding in that sentence and each one is a way for a
## spawn to be wrong, so each gets its own gate:
##
##   1. THERE IS A FLOOR. Probed, never trusted — `ship_cat.HOME` carries a Y and the file's
##      own comment says that Y is decoration (`_seat` re-rays it at spawn). Every
##      floating-prop bug in this repo came from believing a typed elevation.
##   2. THE CAT IS NOT INSIDE ANYTHING. The animal's OWN clearance test (`_step_clear`), not
##      a ray: a ray from the origin let the cat stop with 0.48 m of itself inside a bulkhead
##      and photograph as fine.
##   3. IT IS INDOORS. A ceiling over the seat, at room height — otherwise "internal room" is
##      an assertion about a coordinate rather than about the world.
##   4. IT IS LIT, AND LIT IN COLOUR. Sampled off the LIVE lights in the scene with their real
##      energies, ranges and attenuations, with a line-of-sight test so a lamp through a wall
##      does not count — and with a saturation gate, because the SPHL pod's only lamp is
##      Color(0.9, 0.15, 0.1) at energy 1.6 and would pass any brightness test while drawing a
##      cat as a red silhouette (s52 spent a session on exactly that physics).
##
## Candidates are printed as a table before the gates so the choice can be re-made cheaply if
## the owner meant a different room.

const CANDIDATES := {
	"store_room  by the lantern": Vector3(13.80, 2.0, -17.60),
	"store_room  mid floor":      Vector3(13.20, 2.0, -18.40),
	"store_room  SE of crate":    Vector3(14.20, 2.0, -18.60),
	"store_room  west shelf end": Vector3(12.40, 2.0, -17.40),
	"pump_ready  under pipe lamp": Vector3(14.30, 2.0, -7.60),
	"sphl_pod    (red lamp)":     Vector3(16.50, 2.0, -24.00),
}

var failures: int = 0
var _cat: Node3D

func _ready() -> void:
	var main: Node3D = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	var t0: int = Time.get_ticks_msec()
	var waited: int = 0
	while Time.get_ticks_msec() - t0 < 9000 or waited < 180:
		await get_tree().physics_frame
		waited += 1
	# NIGHT, because the ask is "so it is illuminated IN THE DARK". Measuring the lamp's reach
	# at noon would certify a spawn the sun was lighting.
	GameClock.force_phase(GameClock.Phase.NIGHT)
	await get_tree().physics_frame
	_cat = get_tree().get_first_node_in_group("ship_cat")
	if _cat == null:
		print("FAIL  found the cat")
		get_tree().quit(1)
		return

	print("")
	print("  %-28s %8s %8s %7s %8s %7s  %s"
		% ["candidate", "floor y", "clear", "ceil", "lux", "sat", "brightest lamp"])
	for nm in CANDIDATES:
		var r: Dictionary = _assess(CANDIDATES[nm])
		print("  %-28s %8s %8s %7s %8.3f %7.2f  %s"
			% [nm, ("%.3f" % r["floor"]) if bool(r["has_floor"]) else "   none",
				"yes" if r["clear"] else " NO", ("%.2f" % r["ceil"]) if r["ceil"] > 0.0 else "  none",
				r["lux"], r["sat"], r["lamp"]])

	# ...AND THEN THE ONE THAT SHIPPED. Read off the constant, so this cannot drift away from
	# what the game actually does.
	print("")
	var home: Vector3 = _cat.get("HOME")
	var h: Dictionary = _assess(home)
	print("  ship_cat.HOME = %s" % str(home))
	_ok(bool(h["has_floor"]), "HOME has a real floor under it (y %.3f)" % float(h["floor"]))
	_ok(bool(h["clear"]), "...and the cat's own body fits there, unburied")
	_ok(float(h["ceil"]) > 0.0 and float(h["ceil"]) < 4.5,
		"...and it is INDOORS — a ceiling %.2f m up" % float(h["ceil"]))
	# 0.05 is a tenth of the lantern's own energy delivered at its own range: enough that the
	# animal reads as lit rather than as a shape in the dark, and low enough that it is not a
	# transcription of today's fixture.
	_ok(float(h["lux"]) > 0.05,
		"...and a light actually reaches it (%.3f from %s)" % [float(h["lux"]), h["lamp"]])
	_ok(float(h["sat"]) < 0.60,
		"...in a colour a cat can be seen in, not the pod's red-only lamp (saturation %.2f)"
			% float(h["sat"]))
	# AND THE ANIMAL IS REALLY THERE — the constant could be perfect and the spawn still put it
	# somewhere else, which is the only thing the player would ever notice.
	_ok(_cat.global_position.distance_to(Vector3(home.x, _cat.global_position.y, home.z)) < 0.35,
		"the cat SPAWNED there (at %s)" % str(_cat.global_position.snappedf(0.01)))
	_ok(absf(_cat.global_position.y - float(h["floor"])) < 0.06,
		"...seated ON that floor, not floating above it (cat y %.3f, floor %.3f)"
			% [_cat.global_position.y, float(h["floor"])])
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _ok(cond: bool, msg: String) -> void:
	print("%s  %s" % ["PASS" if cond else "FAIL", msg])
	if not cond:
		failures += 1

## Everything measurable about one candidate seat.
func _assess(at: Vector3) -> Dictionary:
	var world: World3D = _cat.get_world_3d()
	var ss := world.direct_space_state
	var out := {"has_floor": false, "floor": 0.0, "clear": false, "ceil": 0.0,
		"lux": 0.0, "sat": 0.0, "lamp": "-"}
	# 1. The floor, from well above the seat so a candidate authored a little low still finds
	# the deck rather than starting inside it.
	var from: Vector3 = at + Vector3(0, 1.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 4.0, 0))
	q.collision_mask = 1
	q.collide_with_areas = false
	var hit: Dictionary = ss.intersect_ray(q)
	if hit.is_empty():
		return out
	out["has_floor"] = true
	var floor_y: float = (hit["position"] as Vector3).y
	out["floor"] = floor_y
	var seat := Vector3(at.x, floor_y, at.z)
	# 2. The cat's OWN clearance test, on the cat itself, at the seat. Asking the animal is the
	# only way this stays true if `_body_r` or the mesh scale ever changes.
	out["clear"] = bool(_cat.call("_step_clear", seat, Vector3(1, 0, 0)))
	# 3. A ceiling — the difference between "an interior coordinate" and a room.
	var cf: Vector3 = seat + Vector3(0, 0.2, 0)
	var cq := PhysicsRayQueryParameters3D.create(cf, cf + Vector3(0, 6.0, 0))
	cq.collision_mask = 1
	cq.collide_with_areas = false
	var ch: Dictionary = ss.intersect_ray(cq)
	if not ch.is_empty():
		out["ceil"] = (ch["position"] as Vector3).y - floor_y
	# 4. THE LIGHT, SAMPLED. Every visible OmniLight in the tree, at its real energy, range and
	# attenuation, with the engine's own falloff shape — and only if the light can SEE the seat.
	var probe: Vector3 = seat + Vector3(0, 0.18, 0)     # the cat's own flank height
	var best: float = 0.0
	var acc := Color(0, 0, 0)
	for n in get_tree().get_root().find_children("*", "OmniLight3D", true, false):
		var l := n as OmniLight3D
		if l == null or not l.is_visible_in_tree() or l.light_energy <= 0.0:
			continue
		var d: float = l.global_position.distance_to(probe)
		if d > l.omni_range:
			continue
		var lq := PhysicsRayQueryParameters3D.create(l.global_position, probe)
		lq.collision_mask = 1
		lq.collide_with_areas = false
		if not ss.intersect_ray(lq).is_empty():
			continue                                     # a lamp through a wall lights nothing
		# Godot's omni falloff: (1 - d/range) raised to the attenuation exponent.
		var f: float = pow(clampf(1.0 - d / maxf(l.omni_range, 0.001), 0.0, 1.0),
			maxf(l.omni_attenuation, 0.01))
		var e: float = l.light_energy * f
		acc += l.light_color * e
		if e > best:
			best = e
			out["lamp"] = "%s e%.2f r%.1f d%.2f" % [l.name, l.light_energy, l.omni_range, d]
	out["lux"] = (acc.r + acc.g + acc.b) / 3.0
	var mx: float = maxf(acc.r, maxf(acc.g, acc.b))
	# Saturation of the light the cat is actually standing in — the s52 lesson: no albedo
	# survives a single-channel lamp, so a red-only pod reads as a red silhouette however
	# bright it is.
	out["sat"] = 0.0 if mx <= 1e-5 else (mx - minf(acc.r, minf(acc.g, acc.b))) / mx
	return out
