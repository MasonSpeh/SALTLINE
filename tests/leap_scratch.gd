extends Node
## SCRATCH — WHICH GATE REFUSES THE LEAP? Four films have shown the cat walking up to a real
## ledge and not jumping, and a film can only ever say "it didn't". This asks each gate in
## `_walk_toward`'s jump path by hand, at a ledge probed the same way the reel probes one,
## and prints the verdicts in order. The first FALSE is the answer.

const STAGE := Vector3(3.0, 18.0, -3.0)

func _ready() -> void:
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	var t0: int = Time.get_ticks_msec()
	var waited: int = 0
	while Time.get_ticks_msec() - t0 < 9000 or waited < 180:
		await get_tree().physics_frame
		waited += 1
	var cat: Node3D = get_tree().get_first_node_in_group("ship_cat")
	var player: Node3D = get_tree().get_first_node_in_group("player")
	player.set_physics_process(false)
	player.set_process(false)
	for c in cat.get_children():
		if c is Interactable:
			(c as Interactable).emit_signal("interacted", "SAY HELLO")
			break
	# A CRATE WE BUILT, NOT A LEDGE WE FOUND. Probing the world for "any surface in the
	# 0.66-1.20 m band" keeps returning small props the cat simply walks around, so the test
	# was measuring the pathfinder rather than the leap and gave a different answer each run.
	# A known box at a known spot on open deck makes the question deterministic: there is
	# exactly one thing in front of the animal, it is exactly one jump high, and the only
	# way onto it is up.
	var world: World3D = cat.get_world_3d()
	var deck: float = 18.0
	var crate := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(2.4, 1.0, 2.4)
	cs.shape = bx
	crate.add_child(cs)
	add_child(crate)
	crate.global_position = STAGE + Vector3(2.6, 0.5, 0.0)
	for i in range(6):
		await get_tree().physics_frame
	var ledge: Vector3 = crate.global_position + Vector3(0, 0.5, 0)   # top face centre
	print("[leap] ledge at %s (rise %.2f)" % [str(ledge.snappedf(0.01)), ledge.y - deck])
	# Stand the cat at the FOOT, facing the lip; the player on top.
	# STAGED EXPLICITLY. The outward-walk foot finder kept seating the cat ON the crate
	# (its own down-ray hits the crate top wherever it stops inside the footprint), so the
	# test measured a cat already standing on the thing it was meant to jump onto.
	var foot: Vector3 = STAGE
	cat.global_position = foot
	cat.call("_reseat")
	cat.set("_hunt_cd", 999.0)
	cat.set("_zoom_cd", 999.0)
	cat.set("_play_cd", 999.0)
	cat.set("_idle_cd", 999.0)   # the instinct layer is an idler too (s54)
	cat.set("_roam_cd", 999.0)
	player.global_position = ledge + Vector3(0, 0.2, 0)
	for i in range(20):
		await get_tree().physics_frame
	var dir := Vector3(1, 0, 0)
	print("[leap] cat at %s facing %s, player at %s"
		% [str(cat.global_position.snappedf(0.01)), str(dir.snappedf(0.01)),
			str(player.global_position.snappedf(0.01))])
	# WALK IT IN UNTIL THE STEP IS ACTUALLY REFUSED — that is the only frame the leap path
	# runs on, and testing from a standoff (as the first cut did) reports "all clear" from
	# 1.65 m out, which is true and useless.
	var ground: float = cat.global_position.y
	var clear: bool = true
	var travelled: float = 0.0
	while travelled < 3.0:
		var want: Vector3 = cat.global_position + dir * 0.05
		var q2 := PhysicsRayQueryParameters3D.create(
			want + Vector3(0, 0.75, 0), want + Vector3(0, 0.75, 0) - Vector3(0, 1.85, 0))
		q2.collision_mask = 1
		q2.exclude = cat.call("_walk_skip")
		var h2: Dictionary = world.direct_space_state.intersect_ray(q2)
		if h2.is_empty():
			print("[leap] no deck under the next footfall at %.2f m in — edge, not a ledge"
				% travelled)
			break
		ground = (h2["position"] as Vector3).y
		clear = bool(cat.call("_step_clear", Vector3(want.x, ground, want.z), dir))
		if not clear:
			break
		cat.global_position = Vector3(want.x, ground, want.z)
		travelled += 0.05
	print("[leap] walked %.2f m to %s; step now %s (rise %.2f)"
		% [travelled, str(cat.global_position.snappedf(0.01)),
			"BLOCKED — the leap path runs" if not clear else "still clear (never blocked)",
			ground - cat.global_position.y])
	var blen: float = float(cat.call("_body_len"))
	var look: Vector3 = cat.global_position + dir * (blen * 0.95)
	var hq := PhysicsRayQueryParameters3D.create(
		look + Vector3(0, 1.70, 0), look + Vector3(0, 0.05, 0))
	hq.collision_mask = 1
	hq.exclude = cat.call("_walk_skip")
	var hh: Dictionary = world.direct_space_state.intersect_ray(hq)
	if hh.is_empty():
		print("[leap] ledge ray %.2f m ahead: NOTHING (this is the refusal)" % (blen * 0.95))
		get_tree().quit()
		return
	var top: float = (hh["position"] as Vector3).y
	var lift: float = top - cat.global_position.y
	print("[leap] ledge ray %.2f m ahead: top %.2f, lift %.2f (band %.2f..%.2f) -> %s"
		% [blen * 0.95, top, lift, 0.62, 1.25,
			"IN BAND" if (lift > 0.62 and lift <= 1.25) else "OUT OF BAND"])
	print("[leap] _reachable_up(%.2f): %s" % [top, str(cat.call("_reachable_up", top))])
	print("[leap] _step_clear on the ledge top: %s"
		% str(cat.call("_step_clear", Vector3(look.x, top, look.z), dir)))
	print("[leap] _arc_clear to the ledge top: %s"
		% str(cat.call("_arc_clear", Vector3(look.x, top, look.z), dir)))
	# ...AND NOW THE REAL LOOP. Every gate above can pass while the shipping code still
	# never reaches them — that is exactly how the first version of this fix sat dead behind
	# the detour fan's early return. So drive the animal's own _process, as the game does,
	# and watch for the wind-up arming and the body leaving the deck.
	cat.set("_dbg_leap", true)
	var wind_seen: bool = false
	var air_seen: bool = false
	var y0: float = cat.global_position.y
	var y_max: float = y0
	for i in range(240):
		player.global_position = ledge + Vector3(0, 0.2, 0)
		cat.set("_hunt_cd", 999.0)
		cat.set("_zoom_cd", 999.0)
		cat.set("_play_cd", 999.0)
		cat.set("_idle_cd", 999.0)   # the instinct layer is an idler too (s54)
		cat.set("_roam_cd", 999.0)
		cat.call("_process", 1.0 / 60.0)
		if float(cat.get("_jump_wind")) > 0.0:
			wind_seen = true
		if float(cat.get("_jump_t")) > 0.0:
			air_seen = true
		y_max = maxf(y_max, cat.global_position.y)
		await get_tree().physics_frame
	print("[leap] REAL LOOP: wind-up armed %s, flight ran %s, y %.2f -> %.2f (rise %.2f), final %s"
		% [str(wind_seen), str(air_seen), y0, y_max, y_max - y0,
			str(cat.global_position.snappedf(0.01))])
	get_tree().quit()
