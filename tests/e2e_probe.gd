extends Node3D
## END-TO-END INTEGRATION PROBE — boots the real Main scene and DRIVES the five
## cross-domain behaviours this integrator batch has to prove at runtime (a static
## grep can confirm none of them):
##
##   1. save with a placed structure + a stocked container + a stacked item ->
##      wipe -> reload -> everything comes back (counts included).
##   2. lie on a bunk -> sleep -> the clock advances to a NEW dawn and the game does
##      NOT end (open-ended survival; the tree never pauses, no end card arms).
##   3. grab a prop and turn -> its yaw follows the camera instead of holding its
##      old world facing.
##   4. a snail crawling into a wall TURNS instead of clipping through it.
##   5. a school fish wears its real generated .glb when the asset exists, and falls
##      back to the primitive silhouette when it doesn't.
##
## Prints one line per check; a final E2E-FAILURES: N (0 == green).
## Run: godot --headless --path . res://tests/E2EProbe.tscn

const STRUCTURES := preload("res://scripts/world/structures.gd")
const MOVE := preload("res://scripts/world/fauna_move.gd")
const ANIM := preload("res://scripts/world/creature_anim.gd")
const BLOOM := preload("res://scripts/world/bloom_fauna.gd")
const PROP := preload("res://scripts/components/phys_prop.gd")
const MOVABLE := preload("res://scripts/components/movable_prop.gd")

var _fails: Array[String] = []
var _main: Node3D
## The real slot stem, restored on the way out so nothing downstream inherits the
## throwaway one this probe writes into.
var _slot_prefix: String = ""

func _ok(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "E2E-FAIL  "), msg)
	if not cond:
		_fails.append(msg)

func _ready() -> void:
	# Check 1 below calls SaveManager.save_game() for real. Without this redirect it wrote
	# saltline_slot_1.json — the SAME file the start screen's "Continue" loads — so every
	# run of this probe replaced the player's camp with the probe's own fixture: a brazier
	# hanging at (11, 19, -4), a full metre above the y18 main deck. That is the "floating
	# chair / overlapping fireplace on the main deck that keeps coming back". Point the
	# stem at a throwaway, exactly as test_runner.gd and save_probe.gd already do.
	_slot_prefix = SaveManager.slot_file_prefix
	SaveManager.slot_file_prefix = "e2e_probe_slot_"
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	# Let the world stream in, dress itself, and settle its physics.
	await get_tree().create_timer(4.0).timeout
	for i in range(12):
		await get_tree().physics_frame

	await _c1_save_reload()
	await _c2_sleep_no_end()
	await _c3_carry_yaw()
	await _c4_snail_wall()
	_c5_fish_glb()

	# Clear the throwaway slot and hand the real stem back.
	SaveManager.erase_slot(SaveManager.active_slot)
	SaveManager.slot_file_prefix = _slot_prefix

	print("E2E-FAILURES: ", _fails.size())
	get_tree().quit()

# ------------------------------------------------------------------ 1. save/reload
func _c1_save_reload() -> void:
	print("--- 1. save/reload: structure + stocked container + stacked item ---")
	for s in get_tree().get_nodes_in_group("built_structures"):
		s.free()
	# a placed structure
	var kit: Node3D = STRUCTURES.build("brazier_kit", false)
	get_tree().current_scene.add_child(kit)
	kit.global_position = Vector3(11.0, 18.0, -4.0)   # on the y18 main deck, not above it
	# a stocked container (reuse a pre-placed world locker/nest — it never moves, so its
	# save key is stable)
	var cont: Node3D = null
	for c in get_tree().get_nodes_in_group("loot_container"):
		if c is Node3D and is_instance_valid(c):
			cont = c
			break
	_ok(cont != null, "found a loot container to stock")
	var stocked: Array[String] = ["canned_food", "water_ration", "kelp_bundle"]
	if cont:
		cont.set("items", stocked.duplicate())
	# a stacked item (canned_food is use:eat -> genuinely stackable)
	PlayerState.load_inventory([], [], [], [])
	for i in range(5):
		PlayerState.add_item("canned_food")
	_ok(PlayerState.count_item("canned_food") == 5, "stacked 5 canned_food before save (got %d)" % PlayerState.count_item("canned_food"))
	await get_tree().process_frame
	SaveManager.save_game()

	# wipe every trace, then reload
	for s in get_tree().get_nodes_in_group("built_structures"):
		s.free()
	if cont:
		cont.set("items", [] as Array[String])
	PlayerState.load_inventory([], [], [], [])
	_ok(PlayerState.count_item("canned_food") == 0, "inventory wiped before reload")

	_ok(SaveManager.load_game(), "save reloads")
	await get_tree().process_frame
	await get_tree().process_frame   # deferred container claim + rebuilt structures settle

	var back: Array = get_tree().get_nodes_in_group("built_structures")
	_ok(back.size() >= 1, "placed structure came back (got %d)" % back.size())
	_ok(PlayerState.count_item("canned_food") == 5,
		"stacked count restored on reload (got %d)" % PlayerState.count_item("canned_food"))
	var restored: Variant = cont.get("items") if cont else []
	_ok(typeof(restored) == TYPE_ARRAY and (restored as Array).size() == 3,
		"stocked container contents restored (got %s)" % [restored])

# ------------------------------------------------------------------ 2. sleep, no end
func _c2_sleep_no_end() -> void:
	print("--- 2. lie on a bunk, sleep to dawn, game does NOT end ---")
	var player: Node3D = get_tree().get_first_node_in_group("player")
	_ok(player != null, "player present")
	if player == null:
		return
	var bed: Node = _find_bed(_main)
	_ok(bed != null, "a bunk with the lie-down/sleep API exists")
	if bed == null:
		return
	GameClock.force_phase(GameClock.Phase.NIGHT)   # SLEEP only joins the menu once dark
	var day0: int = GameClock.day_count
	player.lie_on_bed(bed)
	_ok(bool(player.get("_lying")), "player is lying on the bunk")
	player.call("_try_bed_sleep")                   # the S-while-lying path -> bed SLEEP flow
	# The bed runs a fade -> skip-to-dawn -> fade-back -> wake tween chain (~2s w/ HUD).
	await get_tree().create_timer(3.5).timeout
	_ok(GameClock.day_count > day0, "sleeping advanced the clock to a new dawn (%d -> %d)" % [day0, GameClock.day_count])
	_ok(GameClock.current_phase == GameClock.Phase.DAWN, "woke at dawn")
	_ok(not get_tree().paused, "the tree is not paused after dawn (game still running)")
	_ok(not bool(_main.get("_ending")), "no end card armed — dawn is a beat, not a terminus")
	_ok(not bool(player.get("_lying")), "player stood back up after sleeping")

# ------------------------------------------------------------------ 3. carried yaw
func _c3_carry_yaw() -> void:
	print("--- 3. carried prop yaw follows the camera ---")
	# Prove it for the raw PhysProp AND for a MovableProp — the latter is what every
	# grabbable chair/bucket/lantern actually is (prop_lib.spawn movable=true), and it
	# fully overrides _physics_process, so a base-class-only test would miss a regression
	# where the furniture stops yaw-following.
	await _carry_yaw_case(PROP.new(), "PhysProp")
	await _carry_yaw_case(MOVABLE.new(), "MovableProp (furniture)")

func _carry_yaw_case(prop: RigidBody3D, label: String) -> void:
	# A dummy carrier with the Head/Camera3D rig phys_prop expects, so we can rotate the
	# "gaze" and watch the held prop physically track it.
	var pivot := Node3D.new()
	_main.add_child(pivot)
	pivot.global_position = Vector3(0.0, 40.0, 0.0)
	var head := Node3D.new()
	head.name = "Head"
	pivot.add_child(head)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = false
	head.add_child(cam)
	prop.gravity_scale = 0.0
	prop.can_sleep = false                    # never nap mid-turn and stop tracking
	# A real furniture collider so the MovableProp behaves like the spawned article.
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	shape.shape = box
	prop.add_child(shape)
	_main.add_child(prop)
	prop.global_position = Vector3(0.0, 40.0, 0.0)
	prop.held_by = pivot
	for i in range(24):
		await get_tree().physics_frame        # let it settle in front of the camera
	var yaw_before: float = prop.global_rotation.y
	pivot.rotation.y = PI * 0.5               # look 90 degrees to the side
	for i in range(48):
		await get_tree().physics_frame
	var turned: float = absf(wrapf(prop.global_rotation.y - yaw_before, -PI, PI))
	_ok(turned > 0.6, "%s turned with the camera (%.2f rad of a %.2f rad gaze)" % [label, turned, PI * 0.5])
	prop.held_by = null
	prop.queue_free()
	pivot.queue_free()

# ------------------------------------------------------------------ 4. snail vs wall
func _c4_snail_wall() -> void:
	print("--- 4. a snail meeting a wall turns instead of clipping ---")
	# A controlled bulkhead well away from the rig, and a snail driven straight at it by
	# the SAME GroundCrawler the deck snails use.
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(4.0, 2.0, 0.4)
	cs.shape = bs
	wall.add_child(cs)
	_main.add_child(wall)
	var wall_z: float = 40.0
	wall.global_position = Vector3(60.0, 25.0, wall_z)       # face at z = wall_z - 0.2 = 39.8
	var face_z: float = wall_z - 0.2
	var host := Node3D.new()
	_main.add_child(host)
	host.global_position = Vector3(60.0, 25.3, wall_z - 1.4) # 1.2 m clear of the face
	await get_tree().physics_frame
	var crawler: Object = BLOOM.GroundCrawler.new(host.global_position, 3.0, 1.4, 7, 0.3, 0.2, 25.3, Vector3.ZERO)
	crawler.heading = Vector3(0.0, 0.0, 1.0)                 # force it straight at the wall
	var max_z: float = host.global_position.z
	var turned: bool = false
	for i in range(160):
		crawler.tick(host, 0.05)
		max_z = maxf(max_z, host.global_position.z)
		if bool(crawler.blocked) or crawler.heading.z < 0.6:
			turned = true
	_ok(max_z < face_z, "snail never clipped through the wall (max z %.2f < face %.2f)" % [max_z, face_z])
	_ok(turned, "snail turned away when the wall blocked it")
	host.queue_free()
	wall.queue_free()

# ------------------------------------------------------------------ 5. school fish glb
func _c5_fish_glb() -> void:
	print("--- 5. school fish wears its real .glb when present, silhouette when not ---")
	# The exact call underwater_world._spawn_schools makes per fish.
	var host := Node3D.new()
	add_child(host)
	var real := ANIM.attach(host, "res://assets/models/fauna/fish_herring/fish_herring.glb",
		0.3, ANIM.Mode.UNDULATE, 0.1, 2.2)
	_ok(not real.is_empty() and real.has("model") and is_instance_valid(real.get("model")),
		"school fish loads its real generated model when the .glb exists")
	_ok((real.get("mats", []) as Array).size() > 0,
		"the loaded model carries the swim-shader materials the school tints")
	host.queue_free()
	var host2 := Node3D.new()
	add_child(host2)
	var missing := ANIM.attach(host2, "res://assets/models/fauna/_no_such_species/_no_such_species.glb",
		0.3, ANIM.Mode.UNDULATE)
	_ok(missing.is_empty(), "a missing .glb returns empty so the silhouette fallback takes over")
	host2.queue_free()
	# And confirm the LIVE world took the real-model path for a school whose asset exists.
	var uw: Node = _find_underwater(_main)
	if uw != null and uw.get("_schools") != null:
		var used_glb: bool = false
		for s in (uw.get("_schools") as Array):
			if String(s.get("id", "")) != "fish_herring":
				continue
			for f in (s.get("fish", []) as Array):
				if _has_shader_mesh(f as Node):
					used_glb = true
					break
		_ok(used_glb, "the live herring school renders on the generated .glb (shader-driven mesh found)")
	else:
		print("      (no live underwater school to inspect — direct attach path proven above)")

# ---------------------------------------------------------------------- helpers
func _find_bed(root: Node) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.has_method("bed_lie_pos") and n.has_method("bed_can_sleep"):
			return n
	return null

func _find_underwater(root: Node) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var s: Script = n.get_script() as Script
		if s != null and s.resource_path.ends_with("underwater_world.gd"):
			return n
	return null

func _has_shader_mesh(n: Node) -> bool:
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		var mi := cur as MeshInstance3D
		if mi != null:
			if mi.material_override is ShaderMaterial:
				return true
			for i in range(mi.get_surface_override_material_count()):
				if mi.get_surface_override_material(i) is ShaderMaterial:
					return true
			if mi.mesh != null:
				for i in range(mi.mesh.get_surface_count()):
					if mi.mesh.surface_get_material(i) is ShaderMaterial:
						return true
	return false
