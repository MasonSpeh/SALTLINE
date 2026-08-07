extends Node
## SPEAR SHOT — photograph spearfishing, because the owner judges by screenshot and
## "23 checks pass" says nothing about whether the moment reads.
##
## What has to be visible in these frames:
##   * a shoal, at the range a thrust actually happens at, through the underwater grade
##   * the spear in hand, in the underwater pose
##   * the prompt chip naming the fish — the only thing that tells a player the verb exists
##
## WINDOWED ONLY. --headless never draws and the read-back would hang forever. Force-unpause
## and hide the pause panel every frame: pause_menu auto-pauses on focus-out, a paused world
## still renders, and the panel survives un-pausing on its own CanvasLayer (docs/AGENT_TRAPS.md).
##
## Run: godot --path . tests/SpearShot.tscn

const OUT_DIR: String = "res://tests/out"
const WARMUP_SEC: float = 6.0     ## the shoals must be SEATED — see below
const SEAT_FRAMES: int = 24

var _main: Node
var _player: Node3D
var _cam: Camera3D
var _pause_panel: CanvasItem = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_main = load("res://scenes/Main.tscn").instantiate()
	_main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_main)
	await _run()

func _process(_delta: float) -> void:
	if get_tree().paused:
		get_tree().paused = false
		if _pause_panel == null:
			var pm: Node = _find_script(get_tree().root, "pause_menu.gd")
			if pm != null:
				_pause_panel = pm.get("panel") as CanvasItem
		if _pause_panel != null:
			_pause_panel.visible = false

func _run() -> void:
	await get_tree().create_timer(WARMUP_SEC).timeout
	_player = get_tree().get_first_node_in_group("player")
	var uw: Node = get_tree().get_first_node_in_group("underwater_world")
	if _player == null or uw == null:
		push_error("[spearshot] player or underwater_world missing")
		get_tree().quit()
		return
	_cam = _player.get_node("Head/Camera3D")
	_cam.current = true
	# The player carries the camera, and the cull only swims the shoals while the camera is
	# under — so get under FIRST and let the pods seat, or every fish is still stacked on the
	# pod root at the world origin. (That is exactly what fooled SpearProbe's first run.)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.global_position = Vector3(0.0, -10.0, 0.0)
	for i in range(SEAT_FRAMES):
		await get_tree().process_frame

	# Spear in hand, selected, so the hand pose and the prompt are both real.
	PlayerState.add_item("crude_spear")
	for i in range(PlayerState.hotbar.size()):
		if String(PlayerState.hotbar[i]) == "crude_spear":
			PlayerState.selected_hotbar = i
			break

	var schools: Array = uw.get("_schools")
	var shots: int = 0
	for s in schools:
		if shots >= 3:
			break
		var root: Node3D = s["root"]
		if not root.visible:
			continue
		var members: Array = s["fish"]
		if members.size() < 4:
			continue
		var fish: Node3D = members[0]
		if fish.global_position.length() < 1.0:
			continue      # unseated
		# DEEP ENOUGH THAT THE HEAD IS UNAMBIGUOUSLY UNDER. The first run photographed pods at
		# 0.9-1.5 m and got no prompt: the swell runs to about +/-1.4 m, so an eye that shallow
		# is above the water in every trough and _head_underwater is correctly false.
		if fish.global_position.y > -5.0:
			continue
		# Swim up to it: eye about a thrust away, slightly off the shoal's axis so the frame
		# has the fish being aimed at AND the shoal behind it, which is what the moment is.
		var fp: Vector3 = fish.global_position
		var back := Vector3(1.5, 0.45, 1.5).normalized() * 3.6
		_player.global_position = fp + back - Vector3(0, 1.6, 0)
		await get_tree().process_frame
		_cam.look_at(fp, Vector3.UP)
		_cam.fov = 62.0
		# Let the prompt poll fire and the chip fade in before the shutter.
		# The poll lives in _physics_process, which this harness turned OFF on the player to
		# stop it swimming away from the shot — so drive it by hand rather than waiting for a
		# tick that will never come.
		await get_tree().create_timer(0.6).timeout
		_player.set("_spear_prompt_t", 0.0)
		_player.call("_update_spear_prompt", 0.0)
		# interaction_ray reads that value in ITS _process and writes the chip; the shutter
		# has to come AFTER that frame or the prompt is set on the player and absent from the
		# picture, which is what the first run photographed.
		await get_tree().process_frame
		await get_tree().process_frame
		var line: String = String(_player.call("spear_prompt_text"))
		var f: String = "%s/spear_%d_%s.png" % [OUT_DIR, shots, String(s["id"])]
		get_viewport().get_texture().get_image().save_png(f)
		print("shot: %s   depth %.1f m   prompt: %s"
			% [f, -fp.y, line if line != "" else "(none)"])
		shots += 1
		# LEGIBILITY SWEEP, off ONE world build. The shoals carry no emission of their own —
		# s27's rim/body lift was removed on the owner's 2026-08-06 no-glow call (the story is
		# on _spawn_pod), so this sweep is now the instrument for CANDIDATE lifts only, should
		# one ever be argued for again; picking such a value by eye across separate launches
		# would be three windowed runs and three different thermal/lighting states. Re-expose
		# the SAME frame at each candidate instead — the same trick ReefShot uses for the reef.
		if shots == 1:
			for pair in [[0.20, 0.10], [0.45, 0.22], [0.75, 0.38]]:
				for m in _pod_mats(root):
					m.set_shader_parameter("glow_energy", float(pair[0]))
					m.set_shader_parameter("body_glow", float(pair[1]))
				await get_tree().process_frame
				await get_tree().process_frame
				var g: String = "%s/glow_rim%.2f_body%.2f.png" % [OUT_DIR, pair[0], pair[1]]
				get_viewport().get_texture().get_image().save_png(g)
				print("sweep: %s" % g)
	if shots == 0:
		push_error("[spearshot] no seated pod was photographable")
	get_tree().quit()

## Every creature_swim ShaderMaterial under one pod, so the sweep can re-expose the same frame.
func _pod_mats(root: Node) -> Array:
	var out: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as ShaderMaterial
		if m != null:
			out.append(m)
		for i in range((mi as MeshInstance3D).get_surface_override_material_count()):
			var sm := (mi as MeshInstance3D).get_surface_override_material(i) as ShaderMaterial
			if sm != null:
				out.append(sm)
	return out

func _find_script(root: Node, frag: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var sc: Script = n.get_script()
		if sc != null and String(sc.resource_path).ends_with(frag):
			return n
	return null
