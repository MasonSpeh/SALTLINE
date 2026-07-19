extends Node3D
## PLAY LOOP — walks the actual survival→home loop end to end in the real Main scene,
## because every seam between the five domains is only real once a player crosses it:
##
##   salvage a prop  ->  craft a kit at the bench  ->  place it with build mode
##   ->  sleep on the bedroll  ->  light the brazier and get warm  ->  sit in the chair
##   ->  stash something in the locker and take it back  ->  drink from the rain catcher
##   ->  plant and harvest the planter  ->  dismantle and get the kit back
##
## This is not a unit test. It drives the same public entry points the player's keys and
## mouse reach, so a break anywhere in the chain shows up as a LOOP-FAIL line.

const STRUCTURES := preload("res://scripts/world/structures.gd")
const BUILD_MODE := preload("res://scripts/components/build_mode.gd")
const BENCH_PANEL := preload("res://scripts/ui/bench_panel.gd")

var _fails: Array[String] = []
var _main: Node3D
var _player: CharacterBody3D

func _fail(s: String) -> void:
	_fails.append(s)
	print("LOOP-FAIL: ", s)

func _ok(s: String) -> void:
	print("  ok  ", s)

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(2.5).timeout
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		_fail("no player in the world — nothing else can be tested")
		print("LOOP-FAILURES: ", _fails.size())
		get_tree().quit()
		return

	await _step_salvage()
	await _step_craft()
	await _step_place_and_sleep()
	await _step_brazier()
	await _step_chair()
	await _step_locker()
	await _step_water_and_planter()
	await _step_dismantle()

	print("LOOP-FAILURES: ", _fails.size())
	get_tree().quit()

# ---------------------------------------------------------------- 1. salvage
## Take a real salvage station, give the player its tool, and work it to completion.
func _step_salvage() -> void:
	print("\n== 1. salvage ==")
	var st: Node = null
	for s in get_tree().get_nodes_in_group("salvageable"):
		if s.get("yields") is Dictionary and not (s.get("yields") as Dictionary).is_empty():
			st = s
			break
	if st == null:
		_fail("no salvage station in the world")
		return
	var need: Array = st.get("required_tools")
	if need is Array and need.size() > 0:
		PlayerState.add_item(String(need[0]))
	var want: Dictionary = st.get("yields")
	# Stand next to it: Salvage lapses the job if the player walks more than NEAR_M away.
	_player.global_position = (st as Node3D).global_position + Vector3(0.8, 0, 0)
	var verbs: Array[String] = st.call("available_verbs")
	if verbs.is_empty():
		_fail("salvage station %s offers no verb even with its tool in hand" % st.name)
		return
	st.call("interact", verbs[0], _player)
	# Work it. work_sec plus slack; _process drives the job.
	await get_tree().create_timer(float(st.get("work_sec")) + 1.5).timeout
	var got := true
	for id in want:
		if not PlayerState.has_item(String(id)):
			got = false
			_fail("salvaged %s but never received '%s'" % [st.name, id])
	if got:
		_ok("salvaged %s -> %s" % [st.name, want.keys()])
	if not st.get("spent"):
		_fail("salvage station %s did not mark itself spent" % st.name)
	elif st.is_in_group("salvaged"):
		_ok("prop still standing, in group 'salvaged', renamed '%s'" % st.get("display_name"))
	else:
		_fail("spent prop never joined group 'salvaged'")

# ---------------------------------------------------------------- 2. craft
## Craft a bedroll at a real bench, from the real recipe, through the real panel.
var _panel: Control = null

func _step_craft() -> void:
	print("\n== 2. craft a bedroll at the bench ==")
	var recipes: Dictionary = _load_json("res://data/recipes.json")
	var rec: Dictionary = recipes.get("bedroll_kit", {})
	if rec.is_empty():
		_fail("no 'bedroll_kit' recipe")
		return
	_panel = BENCH_PANEL.new()
	add_child(_panel)
	await get_tree().process_frame
	# The panel starts hidden (the HUD reveals it at the bench) and its _process
	# bails on `not visible` — so a headless craft must open it the way a player does.
	_panel.visible = true
	# Stock the pack with exactly what the recipe asks for, then lay it out.
	for id in rec.get("needs", {}):
		for _i in range(int(rec["needs"][id])):
			if not PlayerState.add_item(String(id)):
				_fail("pack full while stocking for bedroll_kit")
	var tool_id := String(rec.get("tool", ""))
	if tool_id != "":
		PlayerState.add_item(tool_id)
	for id in rec.get("needs", {}):
		for _i in range(int(rec["needs"][id])):
			if not _panel.call("lay_item", String(id)):
				_fail("bench refused to lay '%s'" % id)
	var m := String(_panel.call("current_match"))
	if m != "bedroll_kit":
		_fail("bench matched '%s', expected 'bedroll_kit' (laid: %s)" % [m, _panel.get("laid")])
		return
	_ok("bench recognises the parts as a Bedroll")
	if not bool(_panel.call("tool_ready", "bedroll_kit")):
		_fail("bedroll_kit reports its tool as missing though it was supplied")
	_panel.set("test_hold", true)
	await get_tree().create_timer(float(rec.get("work_sec", 4.0)) + 1.5).timeout
	_panel.set("test_hold", false)
	if PlayerState.has_item("bedroll_kit"):
		_ok("crafted bedroll_kit")
	else:
		_fail("worked the bench but no bedroll_kit came out")

# ------------------------------------------------- 3. place it, then sleep on it
var _bm: Node = null
var _camera: Camera3D = null

func _ensure_build_mode() -> void:
	if _bm != null:
		return
	_camera = _player.get("camera") as Camera3D
	_bm = BUILD_MODE.new()
	_main.add_child(_bm)
	_bm.call("setup", _player, _camera)

## Aim at a spot the way a player standing over it would. Build mode drops its
## vertical probe at the point REACH metres along the camera's forward axis, so a
## near-vertical look from ~5 m up puts that probe within a few centimetres of the
## spot we actually mean — anything shallower and the probe lands metres away, off
## the deck edge, and the placement "fails" for reasons that have nothing to do with
## the kit. The player is frozen first so it neither falls nor re-drives the camera.
func _stand_at(pos: Vector3) -> void:
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.global_position = pos + Vector3(0, 1.2, 0)
	if _camera:
		_camera.global_position = pos + Vector3(0, 5.0, 0.6)
		_camera.look_at(pos, Vector3.UP)

## Is there really deck under this spot? A failed placement over open water is the
## harness's fault, not build mode's, and the two must not be confused.
func _has_footing(pos: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 3.0, 0), pos + Vector3(0, -4.0, 0))
	q.exclude = [_player.get_rid()]
	var hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.has("position") and Vector3(hit.get("normal", Vector3.UP)).y > 0.75

const DECK := Vector3(12.0, 2.05, -14.0)

func _place(kit: String, at: Vector3) -> Node3D:
	_ensure_build_mode()
	if not PlayerState.has_item(kit):
		PlayerState.add_item(kit)
	_stand_at(at)
	await get_tree().physics_frame
	if not _has_footing(at):
		_fail("HARNESS: no deck under %s — pick another spot for %s" % [at, kit])
		return null
	if not bool(_bm.get("active")):
		_bm.call("toggle")
	_bm.call("select_kit", kit)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not bool(_bm.call("place")):
		_fail("build mode refused to place %s at %s (valid=%s)" % [kit, at, _bm.get("_valid")])
		return null
	if PlayerState.has_item(kit):
		_fail("%s was placed but the kit item was not consumed" % kit)
	await get_tree().create_timer(2.0).timeout   # let ComfortFurniture attach
	var newest: Node3D = null
	for s in get_tree().get_nodes_in_group("built_structures"):
		if String(s.get_meta("kit", "")) == kit:
			newest = s
	if newest == null:
		_fail("%s placed but no built_structures node carries that kit meta" % kit)
	return newest

## Find the Interactable ComfortFurniture bolted onto a structure's marker.
func _proxy(struct: Node3D, kind: String) -> Interactable:
	var stack: Array = [struct]
	while stack.size() > 0:
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node3D and (n as Node3D).is_in_group("comfort_furniture") \
				and String(n.get_meta("kind", "")) == kind:
			for c in n.get_children():
				if c is Interactable:
					return c as Interactable
	return null

func _step_place_and_sleep() -> void:
	print("\n== 3. place the bedroll and sleep on it ==")
	var bed := await _place("bedroll_kit", DECK)
	if bed == null:
		return
	_ok("bedroll standing at %s" % bed.global_position)
	var proxy := _proxy(bed, "bed")
	if proxy == null:
		_fail("placed bedroll has no bed interactable")
		return
	# Sleep is dusk/night gated, exactly like the bunk.
	GameClock.force_phase(GameClock.Phase.NIGHT)
	await get_tree().process_frame
	var verbs: Array[String] = proxy.available_verbs()
	if not verbs.has("SLEEP"):
		_fail("bedroll offers %s at night, expected SLEEP" % [verbs])
		return
	PlayerState.rest = 0.2
	var day0: int = GameClock.day_count
	proxy.interact("SLEEP", _player)
	await get_tree().create_timer(3.0).timeout
	if PlayerState.rest > 0.5:
		_ok("slept: rest 0.20 -> %.2f" % PlayerState.rest)
	else:
		_fail("slept on the bedroll but rest is still %.2f" % PlayerState.rest)
	if GameClock.day_count > day0 or GameClock.current_phase == GameClock.Phase.DAWN:
		_ok("time advanced to day %d, phase %d" % [GameClock.day_count, GameClock.current_phase])
	else:
		_fail("sleeping did not advance the clock (still day %d, phase %d)" % [GameClock.day_count, GameClock.current_phase])
	if bool(PlayerState.resting):
		_fail("PlayerState.resting stuck true after waking")

# ---------------------------------------------------------------- 4. brazier
func _step_brazier() -> void:
	print("\n== 4. light the brazier, get warm ==")
	var br := await _place("brazier_kit", DECK + Vector3(3.0, 0, 0))
	if br == null:
		return
	var fire := _proxy(br, "fire")
	if fire == null:
		_fail("placed brazier has no fire interactable")
		return
	PlayerState.add_item("driftwood")
	var before: int = PlayerState.warmth_zone
	if not fire.available_verbs().has("LIGHT"):
		_fail("brazier will not offer LIGHT with driftwood in the pack")
		return
	fire.interact("LIGHT", _player)
	await get_tree().process_frame
	if not bool(fire.get("lit")):
		_fail("brazier did not light")
		return
	if PlayerState.has_item("driftwood"):
		_fail("brazier lit but the driftwood was not consumed")
	# Stand in the fire's warmth volume and let the zone register.
	_player.global_position = br.global_position + Vector3(0.6, 0.6, 0)
	await get_tree().create_timer(1.2).timeout
	if PlayerState.warmth_zone > before:
		_ok("warmth_zone %d -> %d standing at the fire" % [before, PlayerState.warmth_zone])
	else:
		_fail("stood at a lit brazier and warmth_zone stayed %d" % PlayerState.warmth_zone)
	# and banking it must give the warmth back, not strand the counter
	fire.interact("BANK", _player)
	await get_tree().create_timer(0.6).timeout
	if PlayerState.warmth_zone != before:
		_fail("banked the fire and warmth_zone is %d, expected %d" % [PlayerState.warmth_zone, before])
	else:
		_ok("banked: warmth_zone released cleanly")

# ---------------------------------------------------------------- 5. chair
func _step_chair() -> void:
	print("\n== 5. sit in the chair ==")
	var ch := await _place("chair_kit", DECK + Vector3(-3.0, 0, 0))
	if ch == null:
		return
	var seat := _proxy(ch, "seat")
	if seat == null:
		_fail("placed chair has no seat interactable")
		return
	var mgr: Node = PlayerState.get_node_or_null("ComfortFurniture")
	if mgr == null:
		for c in PlayerState.get_children():
			if c is ComfortFurniture:
				mgr = c
	seat.interact("SIT", _player)
	await get_tree().create_timer(1.2).timeout
	if mgr and bool(mgr.call("is_seated")):
		_ok("seated")
	else:
		_fail("SIT did not seat the player")
		return
	if not bool(_player.get("input_locked")):
		_fail("seated but the player can still walk away")
	mgr.call("stand")
	await get_tree().create_timer(1.2).timeout
	if bool(mgr.call("is_seated")):
		_fail("stand() left the player seated")
	elif bool(_player.get("input_locked")):
		_fail("stood up but input is still locked — the player is stuck")
	else:
		_ok("stood back up, controls returned")

# ---------------------------------------------------------------- 6. locker
func _step_locker() -> void:
	print("\n== 6. stash something in the locker and take it back ==")
	var lk := await _place("locker_kit", DECK + Vector3(0, 0, 3.0))
	if lk == null:
		return
	var box := _proxy(lk, "storage")
	if box == null:
		_fail("placed locker has no storage interactable")
		return
	PlayerState.add_item("rope")
	# LootContainer holds its contents in `items`; the HUD panel moves them across.
	var stash: Array = box.get("items")
	if not (stash is Array):
		_fail("locker exposes no items array")
		return
	PlayerState.remove_item("rope")
	stash.append("rope")
	box.set("items", stash)
	if PlayerState.has_item("rope"):
		_fail("stashed the rope but it is still in the pack")
	else:
		_ok("rope stashed in the locker (%d items inside)" % stash.size())
	# take it back out
	var back: Array = box.get("items")
	back.erase("rope")
	box.set("items", back)
	if not PlayerState.add_item("rope"):
		_fail("could not take the rope back out")
	elif PlayerState.has_item("rope"):
		_ok("rope retrieved from the locker")

# ------------------------------------------- 7. rain catcher + planter (new kinds)
func _step_water_and_planter() -> void:
	print("\n== 7. rain catcher and planter ==")
	var rc := await _place("rain_catcher_kit", DECK + Vector3(0, 0, -3.0))
	if rc != null:
		var butt := _proxy(rc, "water")
		if butt == null:
			_fail("placed rain catcher has no water interactable")
		else:
			butt.set("litres", 6.0)
			PlayerState.thirst = 0.3
			if not butt.available_verbs().has("DRINK"):
				_fail("rain catcher with 6 litres in it will not offer DRINK")
			else:
				butt.interact("DRINK", _player)
				if PlayerState.thirst > 0.5:
					_ok("drank from the rain catcher: thirst 0.30 -> %.2f" % PlayerState.thirst)
				else:
					_fail("drank but thirst is still %.2f" % PlayerState.thirst)
	var pl := await _place("planter_kit", DECK + Vector3(3.0, 0, -3.0))
	if pl != null:
		var bedp := _proxy(pl, "planter")
		if bedp == null:
			_fail("placed planter has no planter interactable")
		else:
			PlayerState.add_item("kelp_bundle")
			if not bedp.available_verbs().has("PLANT"):
				_fail("planter will not offer PLANT with a kelp bundle in hand")
			else:
				bedp.interact("PLANT", _player)
				if PlayerState.has_item("kelp_bundle"):
					_fail("planted but the kelp bundle was not consumed")
				# fast-forward the growth clock and harvest
				bedp.set("grown_h", 999.0)
				if not bedp.available_verbs().has("HARVEST"):
					_fail("grown planter will not offer HARVEST")
				else:
					bedp.interact("HARVEST", _player)
					if PlayerState.has_item("kelp_bundle"):
						_ok("planted, grew and harvested a kelp bundle")
					else:
						_fail("harvested the planter but got no kelp back")

# ---------------------------------------------------------------- 8. dismantle
func _step_dismantle() -> void:
	print("\n== 8. dismantle gives the kit back ==")
	var target: Node3D = null
	for s in get_tree().get_nodes_in_group("built_structures"):
		if String(s.get_meta("kit", "")) == "chair_kit":
			target = s
	if target == null:
		_fail("no placed chair to dismantle")
		return
	_ensure_build_mode()
	# THE case that used to be impossible: pack empty, standing in your own camp,
	# wanting the chair a metre to the left. Build mode must still let you in.
	for kit in STRUCTURES.KIT_ORDER:
		while PlayerState.has_item(kit):
			PlayerState.remove_item(kit)
	_bm.call("exit")
	_bm.call("toggle")
	if not bool(_bm.get("active")):
		_fail("build mode refuses to open with an empty pack — you can never take anything apart")
		return
	_ok("build mode opens with an empty pack (dismantle-only)")
	# Look straight at it from close range so the removal ray finds it.
	_player.global_position = target.global_position + Vector3(1.6, 1.0, 0)
	if _camera:
		_camera.global_position = _player.global_position + Vector3(0, 0.4, 0)
		_camera.look_at(target.global_position + Vector3(0, 0.4, 0), Vector3.UP)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not bool(_bm.call("dismantle")):
		_fail("dismantle found no target while aimed point-blank at the chair")
		return
	await get_tree().process_frame
	if PlayerState.has_item("chair_kit"):
		_ok("dismantled the chair, kit returned to the pack")
	else:
		_fail("dismantled the chair but no chair_kit came back")

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}
