extends Node3D
## SOOT SHOT — the A/B for the salvage soot overlay's specular.
##
## `_strip()` set `soot.specular = 0.05` for months. StandardMaterial3D has no
## `specular` — the Godot 3.x remap swallowed it and warned, so the "killed specular"
## the comment above the material claims never actually happened, and every stripped
## prop on the rig kept its full highlight under the grime. The fix is one word
## (`metallic_specular`), but it changes how EVERY stripped prop looks, so it has to
## be judged on a render at the ratio it ships.
##
## Two separate CampShot runs cannot answer this: that harness scouts its camp site at
## a fixed 2.5 s after boot, so the site — and the frame — moves between runs with
## machine load. This shoots the SAME prop instance twice from the SAME camera in ONE
## run, changing nothing between the two frames but the one number under test:
##
##   /tmp/ws_soot_before_day.png    metallic_specular 0.5   (Godot's default — what the
##   /tmp/ws_soot_before_night.png                           broken line actually left)
##   /tmp/ws_soot_after_day.png     metallic_specular 0.05  (the fix, as it now ships)
##   /tmp/ws_soot_after_night.png
##
## Night matters as much as day: the rig's floodlights are where a wrong specular reads
## either as wet grime or as a flat matte shader fault.

## What the broken assignment left on the material, and what the fix puts there.
const SPEC_BROKEN: float = 0.5     ## StandardMaterial3D's default, untouched for months
const SPEC_FIXED: float = 0.05     ## what salvage.gd:_strip now actually sets

## Manufactured yields mean a PropLib model that visibly comes apart — same rule
## CampShot._shot_salvaged() uses, so this shoots the same class of prop it does.
const MADE := ["steel_plate", "pipe_length", "wire_spool", "bolt_handful",
	"glass_pane", "copper_coil", "ceramic_shard", "rubber_hose"]

var _cam: Camera3D
var _main: Node3D
var _player: Node3D

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(2.5).timeout
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.set_physics_process(false)
		_player.set_process(false)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true

	var target: Node3D = await _strip_one()
	if target == null:
		print("SOOT SHOT: no prop could be stripped — nothing to photograph")
		get_tree().quit()
		return

	var mats: Array = _overlay_mats(target)
	print("soot overlay materials on the stripped prop: %d" % mats.size())
	if mats.is_empty():
		print("SOOT SHOT: the stripped prop carries NO overlay material — the soot never landed")
		get_tree().quit()
		return

	# Frame it the way CampShot frames its salvage shot, so these read against that one.
	var o: Vector3 = target.global_position
	var eye: Vector3 = o + Vector3(1.1, 0.8, 1.1)
	var aim: Vector3 = o + Vector3(0, 0.15, 0)
	print("prop '%s' at %s" % [target.get("display_name"), o])

	for phase in ["day", "night"]:
		GameClock.force_phase(GameClock.Phase.DAY if phase == "day" else GameClock.Phase.NIGHT)
		await get_tree().create_timer(1.2).timeout
		# BEFORE first, so the pair is shot in the order the reader compares them in.
		_apply(mats, SPEC_BROKEN)
		await _shot("soot_before_%s" % phase, eye, aim, 42.0)
		_apply(mats, SPEC_FIXED)
		await _shot("soot_after_%s" % phase, eye, aim, 42.0)

	print("soot shots done")
	get_tree().quit()

## Set the one parameter under test, then READ IT BACK — this whole bug was an
## assignment that silently did not take, so asserting it landed is not good enough.
func _apply(mats: Array, v: float) -> void:
	for m in mats:
		(m as StandardMaterial3D).metallic_specular = v
	var got: float = float((mats[0] as StandardMaterial3D).metallic_specular)
	print("  metallic_specular set %.2f -> reads back %.2f%s"
		% [v, got, "" if is_equal_approx(got, v) else "   *** DID NOT TAKE ***"])

## Every distinct overlay material on the prop (one instance is shared across its
## meshes, but collect by identity rather than assuming that).
func _overlay_mats(target: Node3D) -> Array:
	var out: Array = []
	var stack: Array[Node] = [target]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		if cur is MeshInstance3D:
			var m: Material = (cur as MeshInstance3D).material_overlay
			if m is StandardMaterial3D and not out.has(m):
				out.append(m)
	return out

## Take a permanent prop apart through the real interact path — no hand-built material.
func _strip_one() -> Node3D:
	var ordered: Array = []
	var rest: Array = []
	for s in get_tree().get_nodes_in_group("salvageable"):
		var y: Variant = s.get("yields")
		var made: bool = false
		if y is Dictionary:
			for id in y:
				if MADE.has(String(id)):
					made = true
					break
		if made:
			ordered.append(s)
		else:
			rest.append(s)
	ordered.append_array(rest)
	for s in ordered:
		# A renewable node regrows and looks identical afterwards: it proves nothing.
		if float(s.get("regrow_sec")) > 0.0:
			continue
		var req: Variant = s.get("required_tools")
		if req is Array and (req as Array).size() > 0:
			PlayerState.add_item(String((req as Array)[0]))
		if _player:
			_player.global_position = (s as Node3D).global_position + Vector3(0.6, 0, 0)
		var verbs: Array[String] = s.call("available_verbs")
		if verbs.is_empty():
			continue
		s.call("interact", verbs[0], _player)
		_unpause()
		await get_tree().create_timer(float(s.get("work_sec")) + 1.2).timeout
		if bool(s.get("spent")):
			return s as Node3D
	return null

func _shot(name: String, eye: Vector3, aim: Vector3, fov: float) -> void:
	_cam.global_position = eye
	_cam.look_at(aim, Vector3.UP)
	_cam.fov = fov
	_cam.current = true
	if _player:
		_player.global_position = eye   # rain/ambience emitters ride the player
	_unpause()
	await get_tree().create_timer(1.2).timeout
	_unpause()
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/ws_%s.png" % name)
	print("shot: ", name)

## Windowed harness (gl_compatibility renders nothing headless), so the game's
## focus-loss handler opens the pause menu over the run — and a paused tree freezes the
## SceneTreeTimers awaited above, which returns black frames. Same guard CampShot uses.
func _unpause() -> void:
	get_tree().paused = false
	for n in get_tree().get_nodes_in_group("pause_menu"):
		if n is CanvasItem:
			(n as CanvasItem).visible = false
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		var s: Script = cur.get_script()
		if s != null and String(s.resource_path).contains("pause_menu") and cur is CanvasItem:
			(cur as CanvasItem).visible = false
