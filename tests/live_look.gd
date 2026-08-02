extends Node
## LIVE LOOK — the two Phase A items that no headless probe can settle: does the cat actually
## read as a cat following you around a real game, and do the eleven new species actually show
## up in the water where their depth bands say they should.
##
## Both were only ever verified headless (CatProbe's transforms, CatchProbe's 120k rolls), and
## this project's whole history is that positional and visual faults are caught by eyes, never
## by assertions. WINDOWED ONLY.
##
##   godot --path . tests/LiveLook.tscn

const OUT: String = "res://tests/out/live"
var _pp: CanvasItem = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await get_tree().create_timer(10.0).timeout
	var player: Node3D = get_tree().get_first_node_in_group("player")
	var cam: Camera3D = player.get_node("Head/Camera3D")
	cam.current = true
	var hud: Node = get_tree().get_first_node_in_group("hud")

	# ---- THE CAT, in the bunkhouse, as the player meets it ----------------------------------
	var cat: Node3D = get_tree().get_first_node_in_group("ship_cat")
	if cat != null:
		player.set_physics_process(false)
		player.set_process(false)
		# Stood in the bunkhouse doorway looking at where it lives.
		var cp: Vector3 = cat.global_position
		# PICK THE ANGLE BY RAYCAST, not by guessing one. The bunkhouse is partitioned and the
		# first version of this shot aimed straight through a bulkhead — a photograph of a wall
		# with the subject behind it, which is exactly the class of "looked right in the log,
		# useless as evidence" this repo keeps recording.
		await _place_with_los(player, cam, cp + Vector3(0, 0.22, 0), 1.9)
		cam.fov = 60.0
		await get_tree().create_timer(0.6).timeout
		await _shot("cat_found")
		# Befriend it and walk away, so the follow can be photographed actually happening.
		for c in cat.get_children():
			if c is Interactable:
				(c as Interactable).interact("SAY HELLO", player)
				break
		await get_tree().physics_frame
		player.global_position = cp + Vector3(7.0, 0.0, 0.0)
		for i in range(240):
			await get_tree().physics_frame
		await _place_with_los(player, cam, cat.global_position + Vector3(0, 0.22, 0), 2.3)
		await get_tree().create_timer(0.4).timeout
		await _shot("cat_followed")
		print("[live] cat is %.1f m from the player after following"
			% cat.global_position.distance_to(player.global_position))

	# ---- THE NEW SPECIES, in the water at their own depth bands -----------------------------
	var uw: Node = get_tree().get_first_node_in_group("underwater_world")
	if uw == null:
		get_tree().quit()
		return
	# Get under so the cull shows the subtree and the pods actually swim, then let them seat.
	player.global_position = Vector3(0.0, -10.0, 0.0)
	for i in range(30):
		await get_tree().process_frame
	var schools: Array = uw.get("_schools")
	var want: Array = ["fish_bluefin_tuna", "fish_yellowfin_tuna", "fish_mahi_mahi",
		"fish_leopard_grouper", "fish_peacock_grouper", "fish_skipjack_tuna"]
	var shot: Dictionary = {}
	for s in schools:
		var id: String = String(s["id"])
		if not want.has(id) or shot.has(id):
			continue
		var root: Node3D = s["root"]
		if not root.visible:
			continue
		var members: Array = s["fish"]
		if members.is_empty():
			continue
		var f: Node3D = members[0]
		if f.global_position.length() < 1.0:
			continue      # unseated
		var fp: Vector3 = f.global_position
		player.global_position = fp + Vector3(3.2, -1.6, 3.2)
		await get_tree().process_frame
		cam.look_at(fp, Vector3.UP)
		cam.fov = 62.0
		await get_tree().create_timer(0.5).timeout
		await _shot("water_%s" % id)
		print("[live] %s photographed at depth %.1f m" % [id, -fp.y])
		shot[id] = true
	print("[live] %d of %d requested species were in the water" % [shot.size(), want.size()])
	get_tree().quit()

## Stand the player where the subject is actually VISIBLE: try eight directions around it at
## `dist`, keep the first with an unobstructed line to the subject, and fall back to the least
## bad one rather than silently photographing a bulkhead.
func _place_with_los(player: Node3D, cam: Camera3D, subject: Vector3, dist: float) -> void:
	var world: World3D = player.get_world_3d()
	var best: Vector3 = subject + Vector3(dist, 0.9, dist)
	for i in range(8):
		var a: float = TAU * float(i) / 8.0
		var eye: Vector3 = subject + Vector3(cos(a) * dist, 0.9, sin(a) * dist)
		var q := PhysicsRayQueryParameters3D.create(eye, subject)
		q.collision_mask = 1
		q.collide_with_areas = false
		if world.direct_space_state.intersect_ray(q).is_empty():
			best = eye
			break
	player.global_position = best - Vector3(0, 1.6, 0)   # eye is 1.6 over the body origin
	await get_tree().process_frame
	cam.global_position = best
	cam.look_at(subject, Vector3.UP)
	await get_tree().process_frame
	# PRINT WHERE THE CAMERA ACTUALLY ENDED UP. Two runs were spent on shots that turned out to
	# be photographs of the spawn hatch: the log said the placement had happened and the image
	# said otherwise, which is only distinguishable by reading the transform back.
	print("[live] placed eye at %s looking at %s (player %s, cam.current=%s)"
		% [str(cam.global_position.round()), str(subject.round()),
			str(player.global_position.round()), str(cam.current)])

func _shot(name: String) -> void:
	# WAIT FOR THE DRAW. get_viewport().get_texture() hands back whatever the renderer last
	# finished, which is not necessarily the frame the camera was just moved for — two runs
	# produced identical images of the spawn while the transform readback proved the camera
	# was in the bunkhouse. frame_post_draw is the documented sync point.
	await RenderingServer.frame_post_draw
	var f: String = "%s/%s.png" % [OUT, name]
	get_viewport().get_texture().get_image().save_png(f)
	print("shot: %s" % f)

func _process(_d: float) -> void:
	if get_tree().paused:
		get_tree().paused = false
		if _pp == null:
			var st: Array = [get_tree().root]
			while not st.is_empty():
				var n: Node = st.pop_back()
				for c in n.get_children():
					st.append(c)
				var sc: Script = n.get_script()
				if sc != null and String(sc.resource_path).ends_with("pause_menu.gd"):
					_pp = n.get("panel") as CanvasItem
					break
		if _pp != null:
			_pp.visible = false
