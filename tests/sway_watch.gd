extends Node3D
## SWAY WATCH — proves (or disproves) that a named assembly is being swung through the
## air by ambience.gd's wind-sway animator.
##
## Run WINDOWED: godot --path . res://tests/SwayWatch.tscn
##
## exterior_dress.gd builds each prop as a bare Node3D at the WORLD ORIGIN whose children
## carry absolute world coordinates. ambience.gd::_collect_sway picks nodes up by name
## fragment ("tarp", "chain", "flag", ...) and writes transform.basis on them to make
## hanging things swing. Rotating a node whose origin is 25m away from its own geometry
## swings that geometry through an arc metres long — which is what the owner photographed.
##
## This samples the watched assembly's world AABB every frame for a while and reports how
## far its underside travels, saving a PNG at the highest point it reaches.

const SUPPORT := preload("res://scripts/world/support_index.gd")
const OUT := "/private/tmp/claude-501/-Users-mjspeh-Desktop-UltraInbox/87d5de70-f27c-48d3-bab9-cb1e9a8f822d/scratchpad"

## Assemblies to watch, and the camera that frames each one.
const WATCH := [
	["LashedPalletLoad", Vector3(-25.0, 19.4, -3.6), Vector3(-25.6, 19.4, 1.85), 70.0],
	["CargoBasket",   Vector3(-13.0, 19.4, -3.6), Vector3(-13.5, 19.2, 1.5), 70.0],
]
const SAMPLES: int = 120
const DT: float = 0.05

var _cam: Camera3D
var _main: Node3D

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	_cam.far = 900.0
	print("[sway] booting")
	for i in range(24):
		await get_tree().create_timer(1.0).timeout
		print("[sway] t=%ds" % (i + 1))
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player:
		player.set_physics_process(false)
		player.set_process(false)
		# Sway is only collected within 34m of the PLAYER, so it has to stay on the rig
		# for this to reproduce at all. Park it on the alley deck, out of frame.
		player.global_position = Vector3(-19.0, 18.2, -1.0)
	GameClock.force_phase(GameClock.Phase.DAY)
	# The owner's screenshot has rain in it, and ambience.gd scales sway amplitude by storm
	# intensity — so the bug was at its worst in exactly this weather. Test it here.
	var storm: Node = _find_script(_main, "storm_system.gd")
	if storm != null and storm.has_method("trigger_storm"):
		storm.trigger_storm()
		print("[sway] storm triggered")
	await get_tree().create_timer(3.0).timeout
	if storm != null:
		print("[sway] storm intensity = ", storm.get("_intensity"))

	for w in WATCH:
		await _watch(str(w[0]), w[1], w[2], float(w[3]))
	print("[sway] done")
	get_tree().quit()

func _watch(target: String, eye: Vector3, aim: Vector3, fov: float) -> void:
	var node: Node3D = _find(_main, target)
	if node == null:
		print("[sway] NOT FOUND: ", target)
		return
	_cam.global_position = eye
	_cam.look_at(aim, Vector3.UP)
	_cam.fov = fov
	_cam.current = true
	print("[sway] watching ", target)
	var lo: float = INF
	var hi: float = -INF
	var lo_r: float = 0.0
	var hi_r: float = 0.0
	var shot_at: float = -INF
	for i in range(SAMPLES):
		await get_tree().create_timer(DT).timeout
		var a: AABB = SUPPORT.world_aabb_of_tree(node)
		if a.size == Vector3.ZERO:
			continue
		var base: float = a.position.y
		var rot: float = rad_to_deg(node.transform.basis.get_euler().z)
		if base < lo:
			lo = base
			lo_r = rot
		if base > hi:
			hi = base
			hi_r = rot
			# Photograph it at its highest so the verdict is visual, not just numeric.
			if base > shot_at + 0.25:
				shot_at = base
				get_viewport().get_texture().get_image().save_png(
					"%s/sw_%s_high.png" % [OUT, target])
	# Low, side-on, from a few metres away: the one angle where "is it touching the deck"
	# is unambiguous. Shooting from above (as an earlier pass did) hides the gap entirely.
	for v in [[ "side", Vector3(-21.4, 18.35, 0.55)], ["front", Vector3(-25.6, 18.40, -2.4)]]:
		_cam.global_position = v[1]
		_cam.look_at(aim + Vector3(0, -0.25, 0), Vector3.UP)
		_cam.fov = 60.0
		await get_tree().create_timer(0.4).timeout
		get_viewport().get_texture().get_image().save_png(
			"%s/sw_%s_%s.png" % [OUT, target, str(v[0])])
	print("[sway] %s: underside travelled %.2f m  (low %.2f at %.2f deg, high %.2f at %.2f deg)"
		% [target, hi - lo, lo, lo_r, hi, hi_r])
	print("[sway]   deck is y 18.00 — anything above ~18.1 here is airborne")

func _find_script(root: Node, frag: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var sc: Script = n.get_script() as Script
		if sc != null and sc.resource_path.ends_with(frag):
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func _find(root: Node, nm: String) -> Node3D:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and str(n.name) == nm:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
