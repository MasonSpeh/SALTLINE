extends Node
## THE WHOLE ROUND TRIP, the way a player takes it: boot Main, build a camp, stash items
## in a locker, fill the pack, walk somewhere, save — then throw the world away, reset the
## autoloads to their cold-boot values, and come back in through SaveManager.begin_continue
## exactly as the start screen's CONTINUE does.
##
## Everything else that tests saving in this repo pokes SaveManager against whatever scene
## it happens to be in. This is the only check that the ORDERING holds in the real Main
## boot — world first, then load, with containers and structures claiming their contents on
## the way up — which is the half of the system that was actually broken.
##
## Run: godot --headless --path . res://tests/BootSaveProbe.tscn

const MAIN: String = "res://scenes/Main.tscn"
const SLOT_PREFIX: String = "boot_probe_slot_"
## ON the y18 main deck (RigBuilder.DECK_Y), not the arbitrary y19 this used to sit at:
## a fixture floating a metre up is a floating camp the moment it reaches a save slot.
const CAMP_AT := Vector3(11.0, 18.0, -4.0)
const STOOD_AT := Vector3(23.5, 3.4, -14.0)

func _ready() -> void:
	# A node parented to the scene ROOT rather than being the current scene, so
	# change_scene_to_file() does not free the thing driving the test.
	var d := Driver.new()
	d.name = "BootSaveDriver"
	get_tree().root.add_child.call_deferred(d)


class Driver extends Node:
	var _pass: int = 0
	var _fail: int = 0
	## What boot 1 wrote down, for boot 2 to look for.
	var _locker_key: String = ""
	var _locker_pos := Vector3.ZERO
	## Where the player ACTUALLY stood at the instant of the save. Read back out of the
	## file rather than assumed from STOOD_AT: STOOD_AT is a hand-typed standing point, the
	## player is a physics body, and the deck is where the deck is. Comparing against the
	## typed number would be testing the guess, not the round trip.
	var _saved_pos := Vector3.ZERO

	func _ok(cond: bool, msg: String) -> void:
		if cond:
			_pass += 1
			print("  PASS  %s" % msg)
		else:
			_fail += 1
			print("  FAIL  %s" % msg)

	func _ready() -> void:
		SaveManager.slot_file_prefix = SLOT_PREFIX
		SaveManager.begin_new_game(1)
		await _boot()
		await _first_run()
		await _cold_boot()
		await _second_run()
		SaveManager.erase_slot(1)
		print("\n[boot_save_probe] %d passed, %d failed" % [_pass, _fail])
		get_tree().quit(1 if _fail > 0 else 0)

	## Swap in Main and give the rig, dressing and player time to finish arriving.
	func _boot() -> void:
		get_tree().change_scene_to_file(MAIN)
		await get_tree().process_frame
		await get_tree().create_timer(6.0).timeout

	# ---------------------------------------------------------------- boot 1
	func _first_run() -> void:
		print("\n-- run one: build a camp and save it --")
		var scene: Node = get_tree().current_scene
		_ok(scene != null and scene.get("rig") != null, "Main booted with a rig")

		# A placed structure, as build mode leaves one.
		var kit: Node3D = Structures.build("brazier_kit", false)
		scene.add_child(kit)
		kit.global_position = CAMP_AT

		# A container the WORLD owns — the ordering that mattered. Pick deterministically
		# (lowest x, then y, then z) so boot 2 looks at the same one.
		var lockers: Array = get_tree().get_nodes_in_group("loot_container")
		_ok(lockers.size() > 0, "the rig has containers in it (%d)" % lockers.size())
		var pick: Node3D = _lowest(lockers)
		_ok(pick != null, "picked a container to stash something in")
		if pick:
			_locker_pos = pick.global_position
			_locker_key = String(pick.get("display_name"))
			pick.set("items", ["flare", "rope"] as Array[String])
			print("     stashing in '%s' at %v" % [_locker_key, _locker_pos])

		# The pack.
		PlayerState.load_inventory(["crude_knife", null, null, null], [1],
			["scrap_metal", "driftwood"], [4, 2])

		# Somewhere that is not the spawn.
		var pl: Node3D = get_tree().get_first_node_in_group("player")
		_ok(pl != null, "the player is in the tree")
		if pl:
			pl.global_position = STOOD_AT
			pl.rotation.y = 2.35
		GameClock.day_count = 4
		await get_tree().process_frame

		_ok(SaveManager.save_game(), "the manual save reports success")
		var info: Dictionary = SaveManager.slot_info(1)
		_ok(bool(info.get("exists", false)), "the slot now offers CONTINUE (%s)" % info.get("label"))
		var wrote: Dictionary = _on_disk()
		var pa: Variant = wrote.get("player_pos")
		if typeof(pa) == TYPE_ARRAY and (pa as Array).size() >= 3:
			_saved_pos = Vector3(float(pa[0]), float(pa[1]), float(pa[2]))
		_ok(_saved_pos != Vector3.ZERO, "the save recorded a player position (%v)" % _saved_pos)

	## Wipe the autoloads back to cold-boot values. A real second launch gets fresh ones;
	## without this the probe would be testing its own leftover memory, not the file.
	func _cold_boot() -> void:
		print("\n-- wiping state, as a fresh launch would --")
		PlayerState.load_inventory([null, null, null, null], [], [], [])
		PlayerState.hunger = 1.0
		PlayerState.thirst = 1.0
		PlayerState.warmth = 1.0
		PlayerState.life = 1.0
		PlayerState.camp_found = false
		GameClock.day_count = 0
		GameClock.force_phase(GameClock.Phase.DAY)
		_ok(PlayerState.hotbar[0] == null and PlayerState.inventory.is_empty(),
			"the pack is empty before the reload")
		# The real CONTINUE path: the start screen flags the slot, Main consumes it.
		SaveManager.begin_continue(1)
		await _boot()

	# ---------------------------------------------------------------- boot 2
	func _second_run() -> void:
		print("\n-- run two: what came back --")
		# Main defers _resume_saved_game by a frame, and world_storage keeps adopting
		# containers for ~18 s; give the whole arrival sequence room.
		await get_tree().create_timer(4.0).timeout

		_ok(GameClock.day_count == 4, "the day count came back (got %d)" % GameClock.day_count)

		# 1. ITEMS.
		_ok(PlayerState.hotbar[0] == "crude_knife",
			"the hotbar came back (got %s)" % str(PlayerState.hotbar[0]))
		_ok(PlayerState.inventory.has("scrap_metal") and PlayerState.inventory.has("driftwood"),
			"the pack came back (%s)" % str(PlayerState.inventory))
		var si: int = PlayerState.inventory.find("scrap_metal")
		_ok(si >= 0 and int(PlayerState.inventory_counts[si]) == 4,
			"stack counts came back (got %d)"
				% (int(PlayerState.inventory_counts[si]) if si >= 0 else -1))

		# 2. STORAGE CONTAINERS.
		var again: Node3D = _at(_locker_pos, _locker_key)
		_ok(again != null, "the stashed-in container exists again on this boot")
		if again:
			var its: Variant = again.get("items")
			_ok(typeof(its) == TYPE_ARRAY and (its as Array).has("flare")
					and (its as Array).has("rope"),
				"its contents came back (got %s)" % str(its))

		# 3. NEW BUILDS.
		var camp: Array = get_tree().get_nodes_in_group("built_structures")
		var found: Node3D = null
		for s in camp:
			if String((s as Node3D).get_meta("kit", "")) == "brazier_kit" \
					and (s as Node3D).global_position.distance_to(CAMP_AT) < 0.1:
				found = s as Node3D
		_ok(found != null, "the placed structure came back where it was put (%d built)" % camp.size())

		# 4. LAST LOCATION. Judged on the FLOOR PLAN — where on the rig they came back —
		# with Y allowed to settle: the player is a physics body dropped into a restored
		# world, so it lands on the plating under the saved point rather than hanging at
		# the saved altitude. Landing is right; drifting across the deck would not be.
		var pl: Node3D = get_tree().get_first_node_in_group("player")
		var here: Vector3 = pl.global_position if pl else Vector3.ZERO
		var flat: float = Vector2(here.x - _saved_pos.x, here.z - _saved_pos.z).length()
		_ok(pl != null and flat < 0.5,
			"the player came back on the same spot of deck (%.2f m from the saved point)" % flat)
		_ok(pl != null and here.y <= _saved_pos.y + 0.3 and here.y > _saved_pos.y - 3.0,
			"and at the right level — settled onto it, not fallen through (y %.2f, saved %.2f)"
				% [here.y, _saved_pos.y])

		# 5. AND THE FILE IS STILL GOOD — the bug that made all of the above a lie.
		var d: Dictionary = _on_disk()
		_ok((d.get("structures", []) as Array).size() >= 1,
			"the save file on disk STILL holds the camp after the load")
		var conts: Dictionary = d.get("containers", {})
		var still: bool = false
		for k in conts:
			if typeof(conts[k]) == TYPE_ARRAY and (conts[k] as Array).has("flare"):
				still = true
		_ok(still, "the save file on disk STILL holds the stash after the load")

	## The slot as a NEXT BOOT would find it — read off disk, never off memory.
	func _on_disk() -> Dictionary:
		var p: String = SaveManager.slot_path(1)
		if not FileAccess.file_exists(p):
			return {}
		var f: FileAccess = FileAccess.open(p, FileAccess.READ)
		if f == null:
			return {}
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

	func _lowest(nodes: Array) -> Node3D:
		var best: Node3D = null
		for n in nodes:
			if not (n is Node3D) or not is_instance_valid(n):
				continue
			var c := n as Node3D
			if best == null or _before(c.global_position, best.global_position):
				best = c
		return best

	func _before(a: Vector3, b: Vector3) -> bool:
		if absf(a.x - b.x) > 0.001:
			return a.x < b.x
		if absf(a.y - b.y) > 0.001:
			return a.y < b.y
		return a.z < b.z

	## The container standing at a remembered spot with a remembered name — the same
	## identity SaveManager keys contents by.
	func _at(pos: Vector3, name_: String) -> Node3D:
		for n in get_tree().get_nodes_in_group("loot_container"):
			if not (n is Node3D) or not is_instance_valid(n):
				continue
			if (n as Node3D).global_position.distance_to(pos) < 0.05 \
					and String(n.get("display_name")) == name_:
				return n as Node3D
		return null
