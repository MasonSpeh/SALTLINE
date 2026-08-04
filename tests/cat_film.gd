extends Node3D
## THE FILM STRIP — a fixed WORLD camera watching the cat actually behave. The owner's ask,
## verbatim: "take a video so you can have a point of context".
##
## WHY EVERY PREVIOUS INSTRUMENT MISSED A SIDEWAYS CAT. CatProbe's facing assertion reads
## `-cat.global_transform.basis.z` — the NODE — and the close-out camera positions itself
## from the cat's own basis. If the drawn mesh is rotated inside the node (a wrong
## FACING_OVERRIDES entry, a re-export that changed axes), the node still aims dead at its
## travel, the probe still prints +0.94, and the camera still frames "the front" — while
## the animal walks flank-first. Both instruments measure the claim, not the pixels.
##
## This one cannot be fooled: the camera is bolted to the WORLD, the cat is driven along a
## KNOWN world direction across the frame, and the strip shows which end leads. Then it
## sits, grooms and gallops back, so the transitions are on film too.
##
##   godot --path . res://tests/CatFilm.tscn -- /tmp/catfilm

const SHOT_PX := Vector2i(1152, 648)
var _dir: String = "/tmp/catfilm"
var _main: Node3D

func world_ds(n: Node3D) -> PhysicsDirectSpaceState3D:
	return n.get_world_3d().direct_space_state

## The probed film eye: world-fixed preferred bearings, first one whose ray from the cat
## is clear. Used by BOTH loops — the showcase's first cut used a fixed offset and filmed
## the inside of a wall from the cat's final resting spot.
func film_eye(cat: Node3D, bearings: Array, dist: float = 2.1) -> Vector3:
	var base: Vector3 = cat.global_position + Vector3(0, 0.35, 0)
	for b in bearings:
		var cand: Vector3 = base + (b as Vector3) * dist + Vector3(0, dist * 0.26, 0)
		var rq := PhysicsRayQueryParameters3D.create(base, cand)
		rq.collision_mask = 1
		if world_ds(cat).intersect_ray(rq).is_empty():
			return cand
	return base + Vector3(0, 0.55, 2.1)

## PIN THE WEATHER AND THE SUN EVERY FRAME. Setting the clock ONCE at the start is not
## enough: the film runs long enough for StormSystem to roll a squall in, and the s37 deck
## showcase came back shot at night in the rain with the cat in shadow. force_phase resets
## the phase clock (DAY f=0 is a low red sun), so it is called once and the position is
## written directly, exactly as tests/s35_shot.gd does it.
func _pin() -> void:
	if _main == null:
		return
	var st: Node = _main.get("storm")
	if st != null:
		st.set_process(false)
		st.set("_intensity", 0.0)
		st.set("_phase", 0)
	GameClock._phase_elapsed_sec = \
		float(GameClock.phase_durations_minutes[GameClock.Phase.DAY]) * 60.0 * 0.45

func _process(_d: float) -> void:
	if get_tree().paused:
		get_tree().paused = false
	var pm: Node = get_tree().get_first_node_in_group("pause_menu")
	if pm != null and pm.get("panel") != null:
		(pm.get("panel") as CanvasItem).visible = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_dir = a
	DirAccess.make_dir_recursive_absolute(_dir)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	if _main == null or _main.get_script() == null:
		print("[film] Main.tscn came back WITHOUT its script")
		get_tree().quit(1)
		return
	add_child(_main)
	await get_tree().create_timer(24.0).timeout
	GameClock.force_phase(GameClock.Phase.DAY)
	GameClock._phase_elapsed_sec = \
		float(GameClock.phase_durations_minutes[GameClock.Phase.DAY]) * 60.0 * 0.45
	var player: Node3D = get_tree().get_first_node_in_group("player")
	var cam: Camera3D = player.get_node("Head/Camera3D")
	cam.current = true
	player.set_physics_process(false)
	for p in player.find_children("*", "CollisionObject3D", true, false):
		(p as CollisionObject3D).set_collision_mask_value(1, false)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)

	var cat: Node3D = get_tree().get_first_node_in_group("ship_cat")
	if cat == null:
		print("[film] no cat")
		get_tree().quit(1)
		return
	# Befriend it so it follows.
	for c in cat.get_children():
		if c is Interactable:
			(c as Interactable).emit_signal("interacted", "SAY HELLO")

	# STAGE IT ON THE OPEN MAIN DECK, in daylight, in plain sight — the owner's ask. The
	# spot is PROBED, not typed: tests/DeckFind.tscn sweeps the topside for floor at y18
	# with open sky and >= 3 m of clearance on all four sides, and (3, 18, -3) came back
	# with 8 m clear in every direction and no roof. Filming in the bunkhouse aisle put a
	# bulkhead in every frame and cost three re-shoots.
	var stage := Vector3(3.0, 18.0, -3.0)
	cat.global_position = stage
	if cat.has_method("_reseat"):
		cat.call("_reseat")
	player.global_position = stage + Vector3(2.0, 0.1, 0.0)
	for i in range(30):
		await get_tree().physics_frame

	# THE CAMERA IS BOLTED TO THE WORLD. Bunkhouse aisle, looking north-west from above
	# head height, covering x -26..-14 — the cat will cross the frame left-to-right and
	# back, so "which end of the animal leads" is a fact of the strip, not of a basis.
	# Side-on and LOW: perpendicular to the walk line (which runs along x at z 11.4), at
	# cat height, close enough that the animal fills a readable slice of frame.
	# The camera derives PER FRAME: from the cat's position, at a WORLD-FIXED preferred
	# bearing (south first — so a yaw error in the mesh is fully visible, unlike a
	# basis-relative camera), stepping through bearings until a ray from the cat clears —
	# hand-typed spots kept landing inside bunk geometry, and a ray STARTING inside CSG
	# reports nothing, so "probed clear" was vacuous twice.
	var bearings: Array = [
		Vector3(0, 0, 1), Vector3(0.7, 0, 0.7), Vector3(-0.7, 0, 0.7),
		Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, -1)]

	# The script of the film: [player_pos, seconds, label]. The cat follows the player, so
	# the player is the lead actor and the cat's whole behaviour stack is what is filmed:
	# walk east, sit, groom (long stillness), gallop west, sleep.
	# All along the open deck, so every beat is in plain sight against sky and plating.
	var script_beats: Array = [
		[Vector3(10.0, 18.1, -3.0), 4.0, "walk_east"],
		[Vector3(10.0, 18.1, -3.0), 4.0, "settle_sit"],
		[Vector3(-4.0, 18.1, -3.0), 3.5, "gallop_west"],
		[Vector3(0.0, 18.1, -9.0), 3.0, "cross_south"],
		[Vector3(0.0, 18.1, -9.0), 3.5, "settle_two"],
	]
	var frame_i: int = 0
	for beat in script_beats:
		player.global_position = beat[0]
		var frames: int = int(float(beat[1]) * 8.0)   # 8 fps film
		for f in range(frames):
			for w in range(5):                         # 5 sim frames per film frame
				_pin()
				cam.global_position = film_eye(cat, bearings)
				cam.look_at(cat.global_position + Vector3(0, 0.35, 0), Vector3.UP)
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			img.resize(SHOT_PX.x, SHOT_PX.y)
			img.save_png("%s/f%03d_%s.png" % [_dir, frame_i, String(beat[2])])
			frame_i += 1
			# The caption that makes the strip self-reading: node yaw, drawn head bearing,
			# travel bearing. If the drawn head disagrees with the node, it prints here.
			var skel: Skeleton3D = null
			for n in (cat.get("_host") as Node3D).find_children("*", "Skeleton3D", true, false):
				skel = n
				break
			if skel != null:
				var hb: int = skel.find_bone("Head")
				var pb: int = skel.find_bone("Pelvis")
				var head_w: Vector3 = (skel.global_transform * skel.get_bone_global_pose(hb)).origin
				var pelv_w: Vector3 = (skel.global_transform * skel.get_bone_global_pose(pb)).origin
				var drawn: Vector3 = head_w - pelv_w
				drawn.y = 0.0
				# THE PIXELS' OWN POSITION: where the skinned mesh is actually drawn. If this
				# disagrees with the node, the mesh is not following the animal.
				var mi_c: Vector3 = Vector3.INF
				for m in (cat.get("_host") as Node3D).find_children("*", "MeshInstance3D", true, false):
					var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
					mi_c = b.get_center()
					break
				var dvec: Vector3 = head_w - pelv_w
				var pitch_deg: float = rad_to_deg(asin(clampf(dvec.normalized().y, -1.0, 1.0)))
				var roll_axis: Vector3 = (skel.global_transform.basis * Vector3(0, 1, 0)).normalized()
				print("[film] f%03d %s cat=%s pose=%s pitch=%+.0f up_y=%.2f hipY=%.2f node_fwd=%.0f drawn_head=%.0f" % [
					frame_i, String(beat[2]), str(cat.global_position.snappedf(0.1)),
					str(cat.get("_pose")), pitch_deg, roll_axis.y, pelv_w.y,
					rad_to_deg(atan2(-cat.global_transform.basis.z.x, -cat.global_transform.basis.z.z)),
					rad_to_deg(atan2(drawn.x, drawn.z))])
	# THE PLAYGROUND — the owner asked to see the cat in a BUNCH of positions. The natural
	# behaviours above cover walk/gallop/sit; this section directs the rest through the
	# blender itself, on open deck, every transition live on film.
	var rig = cat.get("_rig")
	var showcase: Array = [
		["sit", 2.5], ["groom", 3.0], ["stretch", 2.5],
		["sleep", 3.0], ["stretch", 2.0], ["stand", 1.5],
	]
	# Three-quarter front first: the cat is left standing facing +X (east) after the beats.
	var show_bearings: Array = [
		Vector3(0.82, 0, 0.57), Vector3(0.82, 0, -0.57), Vector3(0, 0, 1),
		Vector3(0, 0, -1), Vector3(-0.82, 0, 0.57), Vector3(-1, 0, 0)]
	cat.set_process(false)   # the state machine would fight the directed poses
	for pose_beat in showcase:
		rig.set_pose(String(pose_beat[0]), 5.0)
		var pframes: int = int(float(pose_beat[1]) * 8.0)
		for f in range(pframes):
			for w in range(5):
				_pin()
				# ticked by hand while the state machine is off
				rig.tick(1.0 / 60.0, 0.0, 0.0)
				# Closer for the pose showcase, and biased to a THREE-QUARTER FRONT — the
				# behaviour reel deliberately shoots from world-fixed bearings to expose a
				# yaw error, but for judging a POSE the silhouette has to read.
				cam.global_position = film_eye(cat, show_bearings, 1.35)
				cam.look_at(cat.global_position + Vector3(0, 0.26, 0), Vector3.UP)
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img2: Image = get_viewport().get_texture().get_image()
			img2.resize(SHOT_PX.x, SHOT_PX.y)
			img2.save_png("%s/p%03d_%s.png" % [_dir, frame_i, String(pose_beat[0])])
			frame_i += 1
	cat.set_process(true)
	print("[film] done -> %s" % _dir)
	get_tree().quit()
