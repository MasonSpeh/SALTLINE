extends Node
## INTEGRATOR HAND-OFF PROOF SHOTS — photographs the six things this batch must show
## as pictures, not coordinates:
##   1. the rigging-bench worklight on its new anchored gooseneck fixture
##   2. the toolbox on the deck to the right (east) of the rigging bench
##   3. a real wooden door half-open in its frame, header meeting the leaf (no gap above)
##   4. the pump room, unflooded (dry deck, dead pump, waterline stains — no water plane)
##   5. a school of skinned fish under the wave line (real generated .glb bodies)
##   6. a bunk with the lie-down interaction prompt showing on the HUD
##
## Windowed — needs a real viewport.
## Run: godot --path . res://tests/HandoffShot.tscn -- <output_dir> [--only=<substr>]

const ANIM := preload("res://scripts/world/creature_anim.gd")

var main: Node3D
var _dir: String = "/tmp"
var _only: String = ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7).to_lower()
		elif not a.begins_with("--"):
			_dir = a
	print("[shot] booting, output -> ", _dir, ("" if _only == "" else "  (filter %s)" % _only))
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(9.0).timeout        # let dressing stream + settle
	main.set("_countdown", 0.0)
	GameClock.force_phase(GameClock.Phase.DAY)
	var p: Node3D = main.player
	p.set("_fly", true)
	(p as CollisionObject3D).set_collision_layer_value(1, false)
	(p as CollisionObject3D).set_collision_mask_value(1, false)
	_hud_off()
	print("[shot] world up")

	# 1. bench worklight (gooseneck). Bench (25,2,-17.5); caged head ~ (25, 3.9, -17.5).
	await _shot_at(Vector3(22.6, 2.0, -16.2), Vector3(25.0, 3.6, -17.5), "bench_lamp")
	# 2. toolbox east of the bench. Toolbox on deck at (26.3, 2, -18.8); bench/chest behind.
	await _shot_at(Vector3(23.4, 2.0, -20.4), Vector3(26.2, 2.3, -18.9), "toolbox")
	# 3. wooden pump-room door, half-open in its frame. Shot from inside the room, east of
	# the dead pump, so the leaf + jambs + header read with nothing occluding the doorway.
	_pose_door_half_open()
	await _shot_at(Vector3(15.1, 2.0, -12.3), Vector3(14.05, 3.7, -13.95), "door_open")
	# 4. pump room interior, unflooded. Dead pump ~ (12, 2, -11); pipe/valve wall at z=-6.5.
	await _shot_at(Vector3(16.6, 2.0, -9.6), Vector3(12.4, 2.5, -11.0), "pump_room")
	# 5. school of skinned fish under the wave line.
	await _shot_school()
	# 6. bunk with the lie-down prompt (HUD on, real prompt text).
	await _shot_bed_prompt()

	print("[shot] done")
	get_tree().quit(0)

func _hud_off() -> void:
	if main.hud != null:
		if main.hud.get("fade_rect") != null:
			main.hud.fade_rect.color.a = 0.0
		main.hud.visible = false

## pos is FEET; the eye sits ~1.7 m above it. Yaw: forward = (-sin y, 0, -cos y).
func _place(pos: Vector3, yaw_deg: float, pitch_deg: float) -> void:
	var p: Node3D = main.player
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw_deg)
	p.get_node("Head").rotation.x = deg_to_rad(pitch_deg)
	p.set("velocity", Vector3.ZERO)
	p.set("input_locked", true)

func _save(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/shot_%s.png" % [_dir, name_]
	var err: int = img.save_png(path)
	print("[shot] saved ", path, " err=", err)

func _shot(pos: Vector3, yaw_deg: float, pitch_deg: float, name_: String) -> void:
	if _only != "" and not name_.to_lower().contains(_only):
		return
	_hud_off()
	_place(pos, yaw_deg, pitch_deg)
	await get_tree().create_timer(0.8).timeout
	await _save(name_)

## Aim from a feet position at a world target — no yaw-sign guesswork.
func _look_from(feet: Vector3, target: Vector3) -> void:
	var eye: Vector3 = feet + Vector3(0.0, 1.7, 0.0)
	var to: Vector3 = target - eye
	var yaw: float = atan2(-to.x, -to.z)
	var pitch: float = atan2(to.y, Vector2(to.x, to.z).length())
	_place(feet, rad_to_deg(yaw), rad_to_deg(pitch))

func _shot_at(feet: Vector3, target: Vector3, name_: String) -> void:
	if _only != "" and not name_.to_lower().contains(_only):
		return
	_hud_off()
	_look_from(feet, target)
	await get_tree().create_timer(0.8).timeout
	await _save(name_)

## Pose the pump-room wooden door statically half-open toward the pump room, collision
## dropped, so the still shows a real hinged leaf mid-swing inside its frame.
func _pose_door_half_open() -> void:
	var door: Node = _find_wooden_door_near(Vector3(14.0, 2.0, -14.0))
	if door == null:
		print("[shot] WARN no wooden door found near the pump room")
		return
	door.set("is_open", true)
	door.rotation.y = deg_to_rad(-52.0)   # ~half of the 100-degree full swing
	if door.has_method("_set_collision"):
		door.call("_set_collision", false)
	print("[shot] posed door ", door.name, " at ", door.global_position, " half-open")

func _shot_school() -> void:
	if _only != "" and not "school".contains(_only) and not "fish".contains(_only):
		return
	_hud_off()
	var uw: Node = _find_by_script(main, "underwater_world.gd")
	if uw == null or uw.get("_schools") == null:
		print("[shot] WARN no underwater world / schools")
		return
	# A school is only rendered when its species is active for the current phase (root
	# hidden otherwise). Sweep phases until a school whose real .glb exists is live.
	var target: Dictionary = {}
	for phase in [GameClock.Phase.NIGHT, GameClock.Phase.DUSK, GameClock.Phase.DAWN, GameClock.Phase.DAY]:
		GameClock.force_phase(phase)
		for i in range(6):
			await get_tree().process_frame            # let _process reveal + reposition
		for s in (uw.get("_schools") as Array):
			var id: String = String(s.get("id", ""))
			var root := s.get("root") as Node3D
			if root != null and root.visible \
					and ResourceLoader.exists("res://assets/models/fauna/%s/%s.glb" % [id, id]):
				target = s
				if id == "fish_herring":
					break
		if not target.is_empty():
			break
	if target.is_empty():
		print("[shot] WARN no live school with a .glb to frame")
		return
	# The shoal wanders and often drifts onto a rig caisson. Freeze the school animation
	# and relocate the members into a tidy cloud in clean open water, south of the rig.
	uw.set_process(false)
	var P := Vector3(0.0, -6.0, 40.0)                 # open sea, below the wave line
	var members: Array = target.get("fish", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for f in members:
		if f is Node3D and is_instance_valid(f):
			var off := Vector3(rng.randf_range(-1.7, 1.7), rng.randf_range(-0.9, 0.9), rng.randf_range(-1.7, 1.7))
			(f as Node3D).global_position = P + off
			(f as Node3D).look_at(P + off + Vector3(0.35, 0.0, -1.0), Vector3.UP)
	var root := target.get("root") as Node3D
	if root != null:
		root.visible = true
	print("[shot] school ", target.get("id"), " x", members.size(), " relocated to ", P)
	# Camera a few metres in front of the cloud, looking into it; teal fog is the backdrop.
	_look_from(P + Vector3(0.3, -1.3, 3.8), P)
	for i in range(3):
		await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	await _save("fish_school")

func _shot_bed_prompt() -> void:
	if _only != "" and not "bed".contains(_only) and not "prompt".contains(_only):
		return
	GameClock.force_phase(GameClock.Phase.DAY)    # the fish sweep may have left it at night
	# HUD ON for this one — we want the interaction prompt in the frame.
	if main.hud != null:
		main.hud.visible = true
		if main.hud.has_method("set_objective"):
			main.hud.set_objective("")            # clear the cold-open objective line
	var p: Node3D = main.player
	p.set("carried", null)
	p.set("ui_locked", false)
	# Bunkhouse bed at (-25.5, 18, 6.5), head to the -Z wall. Stand in the cabin, look at it.
	_look_from(Vector3(-23.6, 18.0, 8.2), Vector3(-25.2, 18.5, 6.6))
	# The cold open locks the prompt chip; release it, then publish the bunk's real prompt.
	var bed: Node = _find_nearest_bed(p.global_position)
	if main.hud != null and bed != null:
		main.hud.prompt_locked = false
		main.hud.show_prompt(bed.call("get_prompt"))   # "[E]   LIE DOWN  Bunk"
		print("[shot] bed prompt = ", bed.call("get_prompt"))
	for i in range(6):
		await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout
	await _save("bed_prompt")

# ---------------------------------------------------------------------- finders
func _find_wooden_door_near(p: Vector3) -> Node:
	var best: Node = null
	var best_d: float = 3.0
	var stack: Array = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var s: Script = n.get_script() as Script
		if s != null and s.resource_path.ends_with("door.gd") and n is Node3D:
			if bool(n.get("wooden")) and not bool(n.get("locked")):
				var d: float = (n as Node3D).global_position.distance_to(p)
				if d < best_d:
					best_d = d
					best = n
	return best

func _find_nearest_bed(p: Vector3) -> Node:
	var best: Node = null
	var best_d: float = 6.0
	var stack: Array = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.has_method("bed_lie_pos") and n.has_method("bed_can_sleep") and n is Node3D:
			var d: float = (n as Node3D).global_position.distance_to(p)
			if d < best_d:
				best_d = d
				best = n
	return best

func _find_by_script(root: Node, frag: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var s: Script = n.get_script() as Script
		if s != null and s.resource_path.ends_with(frag):
			return n
	return null
