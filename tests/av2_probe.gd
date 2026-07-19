extends Node
## ADVERSARIAL VERIFIER 2 — runtime lens. Independent of cross_wire.gd on purpose:
## where cross_wire hand-runs a conversion ("the bench would do this"), this file
## drives the REAL object and reads the REAL side effect. Judge-only; changes nothing.
##
## Run: godot --headless --path . res://tests/AV2Probe.tscn

const SL := preload("res://scripts/world/structure_lib.gd")
const IV := preload("res://scripts/world/item_visual.gd")
const BENCH_PANEL := preload("res://scripts/ui/bench_panel.gd")

var _main: Node3D
var _player: Node3D
var _notes: Array[String] = []

func _ready() -> void:
	await _run()
	print("\n================ AV2 FINDINGS ================")
	for n in _notes:
		print(n)
	print("================ END ================")
	get_tree().quit(0)

func _note(tag: String, msg: String) -> void:
	_notes.append("%-9s %s" % [tag, msg])
	print("%-9s %s" % [tag, msg])

func _ok(msg: String) -> void: _note("[OK]", msg)
func _bad(msg: String) -> void: _note("[DEFECT]", msg)
func _info(msg: String) -> void: _note("[INFO]", msg)

# ---------------------------------------------------------------- helpers

func _all(root: Node, type) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if is_instance_of(n, type):
			out.append(n)
	return out

func _marker(root: Node) -> Node3D:
	for n in _all(root, Node3D):
		if (n as Node3D).is_in_group("comfort_furniture"):
			return n
	return null

func _proxy(marker: Node) -> Interactable:
	if marker == null:
		return null
	for c in marker.get_children():
		if c is Interactable:
			return c
	return null

func _aabb(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for mi in _all(root, MeshInstance3D):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != null and n != root:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b: AABB = xf * m.get_aabb()
		if first:
			acc = b; first = false
		else:
			acc = acc.merge(b)
	return acc

func _mgr() -> Node:
	for c in PlayerState.get_children():
		if c is ComfortFurniture:
			return c
	return null

func _settle(sec: float = 2.0) -> void:
	await get_tree().process_frame
	await get_tree().create_timer(sec).timeout

func _clear_pack() -> void:
	for i in range(PlayerState.HOTBAR_SIZE):
		PlayerState.hotbar[i] = null
	PlayerState.inventory.clear()

# ---------------------------------------------------------------- the run

func _run() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.set_physics_process(false)
		_player.set_process(false)
	PlayerState.set_depleting(false)

	await _probe_geometry()
	await _probe_salvage()
	await _probe_harvest()
	await _probe_bench_tool_gate()
	await _probe_buildmode()
	await _probe_comfort()
	await _probe_camp()
	await _probe_visuals()
	await _probe_ambience()

# ====================================================== 5: geometry census
func _probe_geometry() -> void:
	print("\n---- STRUCTURE GEOMETRY ----")
	for kit in Structures.KIT_ORDER:
		var s: Node3D = Structures.build(kit, false)
		_main.add_child(s)
		s.global_position = Vector3(0, 60, 0)
		var meshes: int = _all(s, MeshInstance3D).size()
		var bodies: int = _all(s, StaticBody3D).size()
		var lights: int = _all(s, Light3D).size()
		var b: AABB = _aabb(s)
		var line := "%-18s meshes=%-4d colliders=%-3d lights=%d  size=(%.2f, %.2f, %.2f)" % [
			kit, meshes, bodies, lights, b.size.x, b.size.y, b.size.z]
		print("  " + line)
		if meshes < 5:
			_bad("%s has only %d mesh parts — not 'real, recognisable geometry'" % [kit, meshes])
		if b.size.y > 4.0 or b.size.x > 4.0 or b.size.z > 4.0:
			_bad("%s is oversized for a hand-built kit: %s" % [kit, b.size])
		# Ghost must be collider-free and light-free (build_mode spawns one per frame).
		var g: Node3D = Structures.build(kit, true)
		var gb: int = _all(g, StaticBody3D).size()
		var gl: int = _all(g, Light3D).size()
		if gb > 0:
			_bad("%s GHOST carries %d colliders — the preview blocks the player" % [kit, gb])
		if gl > 0:
			_bad("%s GHOST carries %d lights" % [kit, gl])
		g.queue_free()
		s.queue_free()
	await get_tree().process_frame

# ====================================================== 1: salvage
func _probe_salvage() -> void:
	print("\n---- SALVAGE ----")
	var perm: int = 0
	var renew: int = 0
	var by_tool: Dictionary = {}
	var sample: Node = null
	for s in get_tree().get_nodes_in_group("salvageable"):
		var rg: float = float(s.get("regrow_sec"))
		if rg > 0.0: renew += 1
		else:
			perm += 1
			if sample == null: sample = s
		var t: Array = s.get("required_tools")
		var key: String = "bare" if t.is_empty() else String(t[0])
		by_tool[key] = int(by_tool.get(key, 0)) + 1
	_info("salvageable in the live world: %d permanent + %d renewable" % [perm, renew])
	_info("  by tool gate: %s" % by_tool)
	if perm >= 40:
		_ok("40+ dismantleable rig props (%d permanent)" % perm)
	else:
		_bad("only %d permanent salvage props — checklist wants 40+" % perm)

	if sample == null:
		_bad("no permanent salvage prop to exercise")
		return
	# --- tool gating: no tool -> LOOK only, and interact() must not yield ---
	_clear_pack()
	var sv := sample as Interactable
	var vlist: Array[String] = sv.available_verbs()
	var need: Array = sample.get("required_tools")
	if not need.is_empty():
		if vlist.size() == 1 and vlist[0] == "LOOK":
			_ok("toolless salvage offers only LOOK (%s wants %s)" % [sv.display_name, need])
		else:
			_bad("toolless salvage offered %s on %s" % [vlist, sv.display_name])
		sv.interact("LOOK", _player)
		await get_tree().create_timer(0.3).timeout
		if bool(sample.get("spent")):
			_bad("salvaging without the tool still stripped %s" % sv.display_name)
		else:
			_ok("no tool = no yield")
	# --- with the tool: work it and check yields + the visible wound ---
	if not need.is_empty():
		PlayerState.add_item(String(need[0]))
	var yields: Dictionary = sample.get("yields")
	var meshes: Array = _all(sample, MeshInstance3D)
	var vis_before: int = 0
	for m in meshes:
		if (m as MeshInstance3D).visible: vis_before += 1
	sv.interact(String(sample.get("verb")), _player)
	var work: float = float(sample.get("work_sec")) + 1.5
	await get_tree().create_timer(work).timeout
	if bool(sample.get("spent")):
		_ok("%s dismantles with %s" % [sv.display_name, need])
	else:
		_bad("%s never completed its work cycle" % sv.display_name)
	var got_all := true
	for id in yields:
		if not PlayerState.has_item(id):
			got_all = false
			_bad("salvaging %s did not yield %s" % [sv.display_name, id])
	if got_all:
		_ok("yields landed in the pack: %s" % yields)
	# visible wound: either meshes hidden, or a soot overlay applied
	var vis_after: int = 0
	var overlaid: int = 0
	for m in meshes:
		if (m as MeshInstance3D).visible: vis_after += 1
		if (m as MeshInstance3D).material_overlay != null: overlaid += 1
	if vis_after < vis_before or overlaid > 0:
		_ok("visible wound: %d/%d meshes removed, %d sooted" % [vis_before - vis_after, vis_before, overlaid])
	else:
		_bad("%s looks identical after salvage (no parts pulled, no soot)" % sv.display_name)
	if sample.is_in_group("salvaged"):
		_ok("stripped prop joins group 'salvaged'")
	else:
		_bad("stripped prop is not in group 'salvaged'")
	# How many props are big enough for the "pull parts off" path at all?
	var thin: int = 0
	var total: int = 0
	for s in get_tree().get_nodes_in_group("salvageable"):
		if float(s.get("regrow_sec")) > 0.0: continue
		total += 1
		if _all(s, MeshInstance3D).size() < 3: thin += 1
	if thin > 0:
		_info("%d/%d permanent props have <3 meshes — soot only, no parts pulled" % [thin, total])
	_clear_pack()

# ====================================================== 2: harvest nodes
func _probe_harvest() -> void:
	print("\n---- HARVEST NODES ----")
	var want := {"tar_lump": 0, "shell_grit": 0, "float_buoy": 0, "kelp_bundle": 0, "fish_bone": 0}
	var renewable := {}
	var sample: Node = null
	for s in get_tree().get_nodes_in_group("salvageable"):
		var y: Variant = s.get("yields")
		if not (y is Dictionary): continue
		for id in y:
			if want.has(id):
				want[id] = int(want[id]) + 1
				if float(s.get("regrow_sec")) > 0.0:
					renewable[id] = true
					if id == "kelp_bundle" and sample == null and not bool(s.get("spent")):
						sample = s
	for id in want:
		if int(want[id]) > 0:
			_ok("%s: %d live harvest node(s), renewable=%s" % [id, want[id], renewable.has(id)])
		else:
			_bad("%s has NO harvest node in the live world" % id)
	if not renewable.has("float_buoy"):
		_info("float_buoy is deliberately one-shot (no regrow) per harvest_nodes.gd")
	# Prove regrowth is real, not just configured: spend one and fast-forward it.
	if sample:
		var sv := sample as Interactable
		sv.interact(String(sample.get("verb")), _player)
		await get_tree().create_timer(float(sample.get("work_sec")) + 1.0).timeout
		if bool(sample.get("spent")):
			sample.set("_regrow_left", 0.15)   # skip the 200s wait
			await get_tree().create_timer(0.6).timeout
			if not bool(sample.get("spent")):
				_ok("renewable node regrows (kelp came back, left group 'salvaged'=%s)"
					% (not sample.is_in_group("salvaged")))
			else:
				_bad("renewable node never regrew after its timer elapsed")
		else:
			_bad("kelp harvest never completed")
	_clear_pack()

# ====================================================== 3: bench tool gating
func _probe_bench_tool_gate() -> void:
	print("\n---- BENCH / CRAFT ----")
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		_bad("no HUD in the tree — cannot drive the bench")
		return
	var panel = hud.get("bench_panel")
	if panel == null:
		_bad("HUD has no bench_panel")
		return
	# locker_kit needs hammer_tool held. Lay the parts WITHOUT the tool first.
	_clear_pack()
	panel.laid.clear()
	for i in 2: PlayerState.add_item("steel_plate")
	PlayerState.add_item("bolt_handful")
	panel.visible = true
	panel.lay_item("steel_plate"); panel.lay_item("steel_plate"); panel.lay_item("bolt_handful")
	panel.refresh()
	var m: String = panel.current_match()
	if m != "locker_kit":
		_bad("bench did not recognise 2x steel_plate + bolt_handful as locker_kit (got '%s')" % m)
	else:
		_ok("bench matches laid parts -> locker_kit")
	if panel.tool_ready("locker_kit"):
		_bad("tool gate FAILED OPEN: locker_kit reads ready with no hammer_tool held")
	else:
		_ok("tool gate closed without hammer_tool")
	if not panel._work_button.disabled:
		_bad("work button is ENABLED without the required tool")
	else:
		_ok("work button disabled without the required tool")
	# Try to force the work through anyway — the gate must survive it.
	panel.test_hold = true
	await get_tree().create_timer(3.0).timeout
	panel.test_hold = false
	if PlayerState.has_item("locker_kit"):
		_bad("holding the work button crafted locker_kit WITHOUT the tool")
	else:
		_ok("forced work does not bypass the tool gate")
	# Now hand over the tool and craft for real.
	PlayerState.add_item("hammer_tool")
	panel.refresh()
	if panel._work_button.disabled:
		_bad("work button still disabled WITH hammer_tool in hand")
	panel.test_hold = true
	await get_tree().create_timer(float(BENCH_PANEL.recipes.get("locker_kit", {}).get("work_sec", 3.0)) + 1.5).timeout
	panel.test_hold = false
	if PlayerState.has_item("locker_kit"):
		_ok("real bench craft produced locker_kit (tool kept: %s)" % PlayerState.has_item("hammer_tool"))
	else:
		_bad("bench never produced locker_kit even with the tool")
	if not PlayerState.has_item("hammer_tool"):
		_bad("the bench CONSUMED the tool — tools are supposed to be held, not spent")
	# Hint list: how many partials does one common part produce, and how many show?
	panel.return_all()
	_clear_pack()
	PlayerState.add_item("steel_plate")
	panel.lay_item("steel_plate")
	var partials: Array = panel.partial_matches()
	_info("one steel_plate is a partial for %d recipes; the panel shows at most %d"
		% [partials.size(), panel.MAX_HINT_LINES])
	if partials.size() > panel.MAX_HINT_LINES:
		_info("overflow line covers the remaining %d" % (partials.size() - panel.MAX_HINT_LINES))
	panel.return_all()
	panel.visible = false
	_clear_pack()

# ====================================================== 6: build mode
func _probe_buildmode() -> void:
	print("\n---- BUILD MODE ----")
	var bm: Node = null
	for n in _all(_main, Node):
		if n is BuildMode:
			bm = n
			break
	if bm == null:
		_bad("no BuildMode node in the running scene")
		return
	_ok("BuildMode is live in the scene")
	_clear_pack()
	PlayerState.add_item("chair_kit")
	PlayerState.add_item("rug_kit")
	bm.call("toggle")
	if not bool(bm.get("active")):
		_bad("build mode would not open with kits in the pack")
		return
	_ok("build mode opens with kits held")
	var kits: Array = bm.call("owned_kits")
	if kits.size() != 2:
		_bad("kit picker sees %d kits, expected 2" % kits.size())
	else:
		_ok("kit picker lists both owned kits: %s" % [kits])
	# rotation
	var y0: float = float(bm.get("_yaw"))
	bm.call("_rotate", bm.ROT_STEP)
	var y1: float = float(bm.get("_yaw"))
	if is_equal_approx(y0, y1):
		_bad("rotation did not change _yaw")
	else:
		_ok("rotate steps yaw %.0f deg -> %.0f deg" % [rad_to_deg(y0), rad_to_deg(y1)])
	# cycling
	var k0: String = String(bm.get("_kit"))
	bm.call("cycle_kit", 1)
	var k1: String = String(bm.get("_kit"))
	if k0 == k1:
		_bad("cycle_kit did not change the selected kit")
	else:
		_ok("cycle_kit: %s -> %s" % [k0, k1])
	# Aim at real deck and place for real.
	var cam: Camera3D = _player.get("camera") as Camera3D
	if cam == null:
		_bad("player has no camera; cannot drive placement")
		bm.call("exit")
		return
	# Stand on the wet deck looking down at it.
	_player.global_position = Vector3(16.0, 3.2, -12.0)
	cam.global_position = Vector3(16.0, 3.8, -12.0)
	cam.look_at(Vector3(16.5, 2.0, -13.5), Vector3.UP)
	bm.call("select_kit", "chair_kit")
	for i in 12:
		await get_tree().physics_frame
	var valid: bool = bool(bm.get("_valid"))
	var ppos: Vector3 = bm.get("_place_pos")
	if valid:
		_ok("valid placement found on the wet deck at %s" % ppos)
		var gx: float = absf(ppos.x - snappedf(ppos.x, bm.GRID))
		var gz: float = absf(ppos.z - snappedf(ppos.z, bm.GRID))
		if gx < 0.001 and gz < 0.001:
			_ok("placement snaps to the %.2fm grid" % bm.GRID)
		else:
			_bad("placement is NOT grid-snapped: %s" % ppos)
	else:
		_bad("no valid placement while aimed straight at the wet deck")
	# ghost tint feedback
	var ghost: Node3D = bm.get("_ghost")
	if ghost == null:
		_bad("no ghost preview spawned")
	else:
		_ok("ghost preview exists (%d meshes)" % _all(ghost, MeshInstance3D).size())
	# invalid feedback: aim at the sky
	cam.look_at(Vector3(16.0, 40.0, -60.0), Vector3.UP)
	for i in 12:
		await get_tree().physics_frame
	if bool(bm.get("_valid")):
		_bad("aiming at open sky still reads as a VALID placement")
	else:
		_ok("aiming at nothing reads invalid")
	# place for real
	cam.look_at(Vector3(16.5, 2.0, -13.5), Vector3.UP)
	for i in 12:
		await get_tree().physics_frame
	var before: int = get_tree().get_nodes_in_group("built_structures").size()
	var placed: bool = bool(bm.call("place"))
	var after: int = get_tree().get_nodes_in_group("built_structures").size()
	if placed and after > before:
		_ok("place() built a real structure (%d -> %d in built_structures)" % [before, after])
	else:
		_bad("place() did not add a structure (%d -> %d)" % [before, after])
	if PlayerState.has_item("chair_kit"):
		_bad("placing did not consume the kit")
	else:
		_ok("placing consumed the chair_kit")
	# dismantle refund
	for i in 12:
		await get_tree().physics_frame
	var tgt: Node3D = bm.get("_remove_target")
	if tgt == null:
		_info("aim-based dismantle target not acquired; forcing the chair as target")
		for s in get_tree().get_nodes_in_group("built_structures"):
			if String(s.get_meta("kit", "")) == "chair_kit":
				bm.set("_remove_target", s)
				break
	var refunded: bool = bool(bm.call("dismantle"))
	if refunded and PlayerState.has_item("chair_kit"):
		_ok("dismantle returns the KIT to the pack")
	else:
		_bad("dismantle did not refund (returned %s, holds kit=%s)" % [refunded, PlayerState.has_item("chair_kit")])
	_info("dismantle refunds the KIT, not the raw materials it was made from")
	bm.call("exit")
	if bool(bm.get("active")):
		_bad("build mode would not exit")
	_clear_pack()

# ====================================================== 7: comfort interactions
func _probe_comfort() -> void:
	print("\n---- COMFORT INTERACTIONS ----")
	var mgr: Node = _mgr()
	if mgr == null:
		_bad("ComfortFurniture manager is not mounted under PlayerState")
		return
	_ok("ComfortFurniture manager is mounted")
	var base: Vector3 = Vector3(14.0, 2.05, -8.0)
	var built: Dictionary = {}
	var kits := ["bedroll_kit", "chair_kit", "brazier_kit", "locker_kit",
		"rain_catcher_kit", "planter_kit", "drying_rack_kit", "workbench_kit"]
	var i: int = 0
	for kit in kits:
		var s: Node3D = Structures.build(kit, false)
		_main.add_child(s)
		s.global_position = base + Vector3(2.2 * float(i), 0, 0)
		built[kit] = s
		i += 1
	await _settle(2.5)
	for kit in kits:
		var mk: Node3D = _marker(built[kit])
		var px: Interactable = _proxy(mk)
		if px == null:
			_bad("%s never received a comfort proxy" % kit)
		else:
			_ok("%s -> %s proxy" % [kit, px.get_class() if px.get_script() == null else String(px.get_script().resource_path).get_file()])

	# ---- BED: drive the REAL SLEEP verb, not sleep_recovery() ----
	var bedm: Node3D = _marker(built["bedroll_kit"])
	var bed: Interactable = _proxy(bedm)
	if bed:
		GameClock.force_phase(GameClock.Phase.DAY)
		await get_tree().process_frame
		if bed.available_verbs().has("SLEEP"):
			_bad("bedroll offers SLEEP in broad daylight (should be night/dusk only)")
		else:
			_ok("bedroll refuses SLEEP during the day")
		GameClock.force_phase(GameClock.Phase.NIGHT)
		await get_tree().process_frame
		if not bed.available_verbs().has("SLEEP"):
			_bad("bedroll does not offer SLEEP at night")
		PlayerState.rest = 0.2
		PlayerState.hunger = 0.9
		var day_before: int = GameClock.day_count
		bed.interact("SLEEP", _player)
		await get_tree().create_timer(4.0).timeout
		if PlayerState.rest > 0.9:
			_ok("real SLEEP interaction restored rest 0.20 -> %.2f" % PlayerState.rest)
		else:
			_bad("SLEEP interaction left rest at %.2f" % PlayerState.rest)
		if PlayerState.hunger < 0.9:
			_ok("sleeping costs hunger (%.2f) — real cost/benefit" % PlayerState.hunger)
		else:
			_bad("sleeping had no hunger cost")
		if GameClock.day_count > day_before or GameClock.current_phase == GameClock.Phase.DAWN:
			_ok("sleeping advanced the clock to dawn (day %d)" % GameClock.day_count)
		else:
			_bad("sleeping did not advance the clock")
		if PlayerState.resting:
			_bad("still flagged resting after waking")
		if _player and bool(_player.get("input_locked")):
			_bad("player left input_locked after waking from the bedroll")
		else:
			_ok("control returns after waking")

	# ---- SEAT ----
	var seatm: Node3D = _marker(built["chair_kit"])
	var seat: Interactable = _proxy(seatm)
	if seat:
		var cam_before: Camera3D = get_viewport().get_camera_3d()
		seat.interact("SIT", _player)
		await get_tree().create_timer(1.2).timeout
		if bool(mgr.call("is_seated")):
			_ok("SIT registers with the manager")
		else:
			_bad("SIT did not register")
		if not PlayerState.resting:
			_bad("sitting did not set PlayerState.resting")
		var cam_now: Camera3D = get_viewport().get_camera_3d()
		if cam_now != cam_before:
			_ok("sitting swapped in a dedicated seat camera")
		else:
			_bad("seat camera never became current — no camera-lowered rest state")
		if _player and not bool(_player.get("input_locked")):
			_bad("seated player is not movement-locked")
		else:
			_ok("seated player is movement-locked")
		# camera should settle near the marker's eye height, not the standing eye
		if cam_now and seatm:
			var d: float = cam_now.global_position.distance_to(seatm.global_position)
			if d < 1.2:
				_ok("seat camera settled %.2fm from the seat marker (lowered)" % d)
			else:
				_bad("seat camera is %.2fm from the seat — never blended down" % d)
		mgr.call("stand")
		await get_tree().process_frame
		if PlayerState.resting:
			_bad("standing did not clear resting")
		else:
			_ok("stand() releases the seat")

	# ---- BRAZIER: light, warmth, fuel burn, gutter out ----
	var firem: Node3D = _marker(built["brazier_kit"])
	var fire: Interactable = _proxy(firem)
	if fire:
		_clear_pack()
		if not fire.available_verbs().is_empty():
			_bad("cold brazier with no fuel still offers %s" % [fire.available_verbs()])
		else:
			_ok("cold brazier with no driftwood is silent")
		PlayerState.add_item("driftwood")
		if not fire.available_verbs().has("LIGHT"):
			_bad("brazier will not offer LIGHT with driftwood held")
		_player.global_position = firem.global_position
		for k in 6:
			await get_tree().physics_frame
		var warm_before: int = PlayerState.warmth_zone
		fire.interact("LIGHT", _player)
		await get_tree().process_frame
		if not bool(fire.get("lit")):
			_bad("brazier did not light")
		else:
			_ok("brazier lights and consumes the log (holds driftwood=%s)" % PlayerState.has_item("driftwood"))
		for k in 10:
			await get_tree().physics_frame
		if PlayerState.warmth_zone > warm_before:
			_ok("standing at the lit brazier raises warmth_zone %d -> %d" % [warm_before, PlayerState.warmth_zone])
		else:
			_bad("lit brazier does not warm the player standing in it")
		# warmth RADIUS: step outside the zone and it must drop back
		_player.global_position = firem.global_position + Vector3(12, 0, 0)
		for k in 12:
			await get_tree().physics_frame
		if PlayerState.warmth_zone == warm_before:
			_ok("warmth is a real radius — stepping 12m away drops the counter back")
		else:
			_bad("warmth_zone stayed %d at 12m from the fire (no radius)" % PlayerState.warmth_zone)
		_player.global_position = firem.global_position
		# fuel burn
		var f0: float = float(fire.get("fuel_h"))
		var ts: float = GameClock.time_scale
		GameClock.time_scale = ts * 400.0
		await get_tree().create_timer(1.0).timeout
		var f1: float = float(fire.get("fuel_h"))
		if f1 < f0:
			_ok("fuel burns down %.2fh -> %.2fh under fast time" % [f0, f1])
		else:
			_bad("brazier fuel does not deplete (%.2f -> %.2f)" % [f0, f1])
		await get_tree().create_timer(3.0).timeout
		if not bool(fire.get("lit")):
			_ok("brazier guts out when the fuel is gone")
		else:
			_info("brazier still lit after the burn window (fuel %.2fh)" % float(fire.get("fuel_h")))
		GameClock.time_scale = ts
		for k in 12:
			await get_tree().physics_frame
		if PlayerState.warmth_zone != warm_before:
			_bad("warmth_zone leaked after the fire died: %d vs %d" % [PlayerState.warmth_zone, warm_before])
		else:
			_ok("no warmth_zone leak after the fire dies")

	# ---- LOCKER: real round trip through the crate exchange ----
	var lockm: Node3D = _marker(built["locker_kit"])
	var lock: Interactable = _proxy(lockm)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if lock and hud:
		_clear_pack()
		PlayerState.add_item("rope")
		lock.interact("OPEN", _player)
		await get_tree().process_frame
		var cp = hud.get("crate_panel")
		if cp == null or not bool(cp.visible):
			_bad("OPEN on the locker did not open the crate exchange panel")
		else:
			_ok("locker OPEN raises the crate ⇄ pack panel")
			hud.call("_crate_stow", "rope")
			await get_tree().process_frame
			var items: Array = lock.get("items")
			if items.has("rope") and not PlayerState.has_item("rope"):
				_ok("stash: rope moved pack -> locker through the real UI path")
			else:
				_bad("stash failed: locker=%s pack_has=%s" % [items, PlayerState.has_item("rope")])
			hud.call("_crate_take", "rope")
			await get_tree().process_frame
			if PlayerState.has_item("rope") and not (lock.get("items") as Array).has("rope"):
				_ok("retrieve: rope came back out of the locker")
			else:
				_bad("retrieve failed")
			hud.call("toggle_panel", "crate")
	_clear_pack()

	# ---- RAIN CATCHER ----
	var waterm: Node3D = _marker(built["rain_catcher_kit"])
	var butt: Interactable = _proxy(waterm)
	if butt:
		butt.set("litres", 6.0)
		PlayerState.thirst = 0.3
		if not butt.available_verbs().has("DRINK"):
			_bad("rain catcher with 6L will not offer DRINK")
		else:
			butt.interact("DRINK", _player)
			await get_tree().process_frame
			if PlayerState.thirst > 0.3:
				_ok("DRINK from the rain catcher restores thirst -> %.2f" % PlayerState.thirst)
			else:
				_bad("DRINK did not restore thirst")
		butt.set("litres", 0.0)
		if butt.available_verbs().has("DRINK"):
			_bad("empty rain catcher still offers DRINK")
		else:
			_ok("empty rain catcher is silent")
		# the water-level indicator the code claims to drive
		var wnode = butt.get("_water")
		if wnode == null:
			_bad("RainButt._water is NULL — the drum's water-level indicator is never found, so the level never reads visually")
		else:
			_ok("rain catcher found its water disc")

	# ---- PLANTER ----
	var planm: Node3D = _marker(built["planter_kit"])
	var plan: Interactable = _proxy(planm)
	if plan:
		_clear_pack()
		if plan.available_verbs().has("PLANT"):
			_bad("planter offers PLANT with no kelp bundle held")
		PlayerState.add_item("kelp_bundle")
		if not plan.available_verbs().has("PLANT"):
			_bad("planter will not offer PLANT with a kelp bundle held")
		else:
			plan.interact("PLANT", _player)
			await get_tree().process_frame
			if bool(plan.get("planted")):
				_ok("planter accepts a kelp bundle (consumed=%s)" % (not PlayerState.has_item("kelp_bundle")))
			else:
				_bad("PLANT did not take")
		var blades: Array = plan.get("_blades")
		if blades.is_empty():
			_bad("Planter._blades is EMPTY — the growth animation ('the only progress bar this game gets') never runs")
		else:
			_ok("planter tracks %d blades for growth" % blades.size())
		var ts2: float = GameClock.time_scale
		GameClock.time_scale = ts2 * 3000.0
		await get_tree().create_timer(3.0).timeout
		GameClock.time_scale = ts2
		if plan.available_verbs().has("HARVEST"):
			_ok("planter ripens to HARVEST after ~20 game hours")
			plan.interact("HARVEST", _player)
			await get_tree().process_frame
			if PlayerState.has_item("kelp_bundle"):
				_ok("harvest returns a kelp bundle")
			else:
				_bad("harvest gave nothing")
		else:
			_bad("planter never ripened (grown_h=%.1f)" % float(plan.get("grown_h")))

	# ---- DRYING RACK ----
	var drym: Node3D = _marker(built["drying_rack_kit"])
	var dry: Interactable = _proxy(drym)
	if dry:
		_clear_pack()
		PlayerState.add_item("cooked_fish")
		PlayerState.selected_hotbar = 0
		var verbs: Array[String] = dry.available_verbs()
		if verbs.is_empty():
			_bad("drying rack offers nothing with a cooked fish selected (verbs=%s)" % [verbs])
		else:
			_ok("drying rack offers %s" % [verbs])
			dry.interact(verbs[0], _player)
			await get_tree().process_frame
			var hung: Array = dry.get("_hung")
			if hung.is_empty():
				_bad("HANG did not put the fish on the line")
			else:
				_ok("fish hangs on the drying line (%d slot(s) used)" % hung.size())
				var ts3: float = GameClock.time_scale
				GameClock.time_scale = ts3 * 3000.0
				await get_tree().create_timer(3.0).timeout
				GameClock.time_scale = ts3
				var h2: Array = dry.get("_hung")
				if not h2.is_empty() and String(h2[0]["id"]) != "cooked_fish":
					_ok("cooked fish cured on the line -> %s" % h2[0]["id"])
				else:
					_bad("nothing cured on the drying line after a long soak")

	# ---- WORKBENCH: crafting away from the wet deck ----
	var wbm: Node3D = _marker(built["workbench_kit"])
	var wb: Interactable = _proxy(wbm)
	if wb:
		if wb.available_verbs().is_empty():
			_bad("placed workbench offers no verb")
		else:
			_ok("placed workbench offers %s" % [wb.available_verbs()])
	_clear_pack()
	for kit in kits:
		(built[kit] as Node3D).queue_free()
	await get_tree().process_frame

# ====================================================== 10: camp
func _probe_camp() -> void:
	print("\n---- CAMP DETECTION ----")
	PlayerState.camp_found = false
	var mgr: Node = _mgr()
	# Two structures + a bed: below and at the threshold.
	var spot: Vector3 = Vector3(20.0, 2.05, -6.0)
	var a: Node3D = Structures.build("bedroll_kit", false)
	_main.add_child(a); a.global_position = spot
	var b: Node3D = Structures.build("rug_kit", false)
	_main.add_child(b); b.global_position = spot + Vector3(1.5, 0, 0)
	await _settle(2.5)
	_player.global_position = spot + Vector3(0, 0.5, 0)
	mgr.call("_update_comfort")
	if PlayerState.camp_found:
		_bad("camp fired with only 2 structures (min is 3)")
	else:
		_ok("2 structures is not yet a camp")
	var c: Node3D = Structures.build("chair_kit", false)
	_main.add_child(c); c.global_position = spot + Vector3(0, 0, 1.5)
	await _settle(2.5)
	mgr.call("_update_comfort")
	if PlayerState.camp_found:
		_ok("3 structures around a bed is recognised as a camp")
	else:
		_bad("3 structures around a bedroll did NOT trigger camp detection")
	# Far apart must NOT count.
	PlayerState.camp_found = false
	c.global_position = spot + Vector3(40, 0, 0)
	b.global_position = spot + Vector3(40, 0, 4)
	await get_tree().process_frame
	mgr.call("_update_comfort")
	if PlayerState.camp_found:
		_bad("camp still fires with the other structures 40m away (radius not enforced)")
	else:
		_ok("scattering the structures 40m apart is not a camp")
	# comfort must actually move
	PlayerState.camp_found = false
	c.global_position = spot + Vector3(0, 0, 1.5)
	b.global_position = spot + Vector3(1.5, 0, 0)
	await get_tree().process_frame
	mgr.call("_update_comfort")
	var tgt: float = PlayerState.comfort_target
	if tgt > 0.0:
		_ok("standing in camp drives comfort_target to %.2f" % tgt)
	else:
		_bad("comfort_target stayed 0 inside a recognised camp")
	# and the HUD must be showing rest
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.get("rest_bar") != null:
		_ok("HUD carries a REST bar")
	else:
		_bad("HUD has no rest bar")
	if hud and hud.get("comfort_label") != null:
		_ok("HUD carries a quiet comfort line (not a number)")
	a.queue_free(); b.queue_free(); c.queue_free()
	await get_tree().process_frame

# ====================================================== 14: item visuals
func _probe_visuals() -> void:
	print("\n---- ITEM VISUALS ----")
	var ids := ["steel_plate", "pipe_length", "wire_spool", "bolt_handful", "glass_pane",
		"canvas_scrap", "foam_block", "ceramic_shard", "copper_coil", "rubber_hose",
		"kelp_fiber", "fish_bone", "shell_grit", "tar_lump", "float_buoy", "wood_slat",
		"raw_fillet", "bedroll_kit", "locker_kit", "rain_catcher_kit", "brazier_kit",
		"chair_kit", "workbench_kit", "drying_rack_kit", "planter_kit", "shelf_kit",
		"wall_panel_kit", "lamp_post_kit", "windbreak_kit", "rug_kit",
		"honed_knife", "honed_spear", "tool_belt", "storm_lantern", "patched_boots"]
	var sigs: Dictionary = {}
	var empty: Array[String] = []
	for id in ids:
		var v: Node3D = IV.build(id)
		if v == null:
			empty.append(id)
			continue
		var meshes: Array = _all(v, MeshInstance3D)
		if meshes.is_empty():
			empty.append(id)
			v.queue_free()
			continue
		# signature: part count + rounded sizes + colours
		var parts: Array = []
		for m in meshes:
			var mesh: Mesh = (m as MeshInstance3D).mesh
			var col := Color(0, 0, 0)
			var mat: Material = mesh.surface_get_material(0) if mesh.get_surface_count() > 0 else null
			if mat is StandardMaterial3D:
				col = (mat as StandardMaterial3D).albedo_color
			parts.append("%s:%.2f:%.2f:%.2f" % [mesh.get_class(),
				snappedf(col.r, 0.02), snappedf(col.g, 0.02), snappedf(col.b, 0.02)])
		parts.sort()
		var sig: String = "%d|%s" % [meshes.size(), "/".join(parts)]
		if sigs.has(sig):
			_bad("item visual for %s is IDENTICAL to %s" % [id, sigs[sig]])
		else:
			sigs[sig] = id
		v.queue_free()
	if empty.is_empty():
		_ok("all %d new item ids build a non-empty world visual" % ids.size())
	else:
		_bad("no world visual for: %s" % [empty])
	if sigs.size() == ids.size() - empty.size():
		_ok("all %d visuals are geometrically distinct" % sigs.size())

# ====================================================== 11/12/13: ambience
func _probe_ambience() -> void:
	print("\n---- AMBIENCE / FOOTSTEPS / VISUALS ----")
	var amb: Node = get_node_or_null("/root/Ambience")
	if amb == null:
		_bad("Ambience autoload missing")
		return
	_ok("Ambience autoload is in the tree")
	var players: Array = _all(amb, AudioStreamPlayer)
	var playing: int = 0
	var loaded: int = 0
	for p in players:
		if (p as AudioStreamPlayer).stream != null:
			loaded += 1
		if (p as AudioStreamPlayer).playing:
			playing += 1
	_info("ambience: %d stream players, %d with a stream, %d playing" % [players.size(), loaded, playing])
	if loaded == 0:
		_bad("no ambience bed has an actual audio stream loaded")
	# beds respond to situation
	var levels_a: Dictionary = {}
	for p in players:
		levels_a[(p as AudioStreamPlayer).name] = (p as AudioStreamPlayer).volume_db
	# move the player from open deck to deep inside and re-mix
	_player.global_position = Vector3(16.0, 3.0, -12.0)
	amb.call("_sample_situation")
	amb.call("_compute_targets")
	amb.call("_apply_bed_levels", 1.0)
	var levels_b: Dictionary = {}
	for p in players:
		levels_b[(p as AudioStreamPlayer).name] = (p as AudioStreamPlayer).volume_db
	_player.global_position = Vector3(0.0, 40.0, 0.0)
	amb.call("_sample_situation")
	amb.call("_compute_targets")
	amb.call("_apply_bed_levels", 1.0)
	var levels_c: Dictionary = {}
	for p in players:
		levels_c[(p as AudioStreamPlayer).name] = (p as AudioStreamPlayer).volume_db
	var moved: int = 0
	for k in levels_b:
		if absf(float(levels_b[k]) - float(levels_c[k])) > 0.5:
			moved += 1
	if moved > 0:
		_ok("bed mix responds to position: %d of %d beds changed level between wet deck and y=40" % [moved, levels_b.size()])
	else:
		_bad("bed levels IDENTICAL on the wet deck and 40m up — no situational mixing")
	# footstep material classification
	var kinds: Dictionary = {}
	for spot in [Vector3(16.0, 3.0, -12.0), Vector3(12.0, 19.5, 10.0), Vector3(0.0, 1.0, 0.0),
			Vector3(23.0, 19.6, 11.0), Vector3(26.0, 3.4, -16.5)]:
		_player.global_position = spot
		await get_tree().physics_frame
		var k: String = String(amb.call("_classify_ground"))
		kinds[k] = int(kinds.get(k, 0)) + 1
	_info("footstep surfaces sampled: %s" % kinds)
	if kinds.size() >= 2:
		_ok("footsteps classify more than one surface material (%d kinds)" % kinds.size())
	else:
		_bad("footstep classifier returned a single kind everywhere: %s" % kinds)
	# posture awareness
	var src: String = FileAccess.get_file_as_string("res://scripts/world/ambience.gd")
	for token in ["crouch", "sprint"]:
		if src.contains(token):
			_ok("footstep cadence references posture '%s'" % token)
		else:
			_bad("no posture term '%s' in the footstep code" % token)
	# environmental visuals
	var parts: Array = _all(amb, GPUParticles3D)
	var cpu: Array = _all(amb, CPUParticles3D)
	_info("ambience visual emitters: %d GPUParticles3D, %d CPUParticles3D" % [parts.size(), cpu.size()])
	if parts.is_empty() and cpu.is_empty():
		_bad("no spray/mote emitters built by ambience")
	else:
		var named: Array[String] = []
		for p in parts: named.append((p as Node).name)
		for p in cpu: named.append((p as Node).name)
		_ok("emitters present: %s" % [named])
	# wind sway
	var sway: Variant = amb.get("_sway")
	if sway is Array:
		_info("wind-sway targets currently tracked: %d" % (sway as Array).size())
		if (sway as Array).is_empty():
			_bad("sway list is EMPTY near the player — nothing is actually swaying")
		else:
			_ok("%d hanging things registered for wind sway" % (sway as Array).size())
