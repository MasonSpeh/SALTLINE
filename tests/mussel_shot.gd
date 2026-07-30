extends Node
## Photographs the mussel feature end to end, in ONE world build: the beds growing among the
## coral, the GATHER prompt, a picked-over bed, the two items in the pack, and the pot coming
## to the boil on the range. The owner judges this work by picture, so this is the harness the
## work is iterated against.
##
## Flies the PLAYER rather than a free camera — underwater_fx keys its fog, colour grade and
## light off the player's own position, so a detached camera photographs the reef in air.
##
## VANTAGES ARE DERIVED FROM THE LIVE OBJECTS, never typed: the bed frames come off
## MusselBeds.beds and the galley frames off the stove node's own transform. s20 lost a whole
## render pass to hand-typed vantages that photographed bare wall, and a shot list that only
## reports its INTENDED camera position cannot tell you it missed — so every frame prints the
## position it actually ended up at and the distance to its subject.
##
## Must run WINDOWED. --headless never draws (docs/AGENT_TRAPS.md).
##   godot --path . res://tests/MusselShot.tscn -- <out_dir> [--only=<substr>] [--night]

var main: Node3D
var _dir: String = "/tmp/mussels"
var _only: String = ""
var _night: bool = false
var _subject: Vector3 = Vector3.ZERO   ## what the current frame is aimed at, for the log

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7).to_lower()
		elif a == "--night":
			_night = true
		elif not a.begins_with("--"):
			_dir = a
	# PROCESS_MODE_ALWAYS or the unpause in _process stops being called the moment the tree
	# pauses — a Node's default process_mode resolves to PAUSABLE at the root, so the handler
	# meant to recover from a focus-out pause is itself switched off by it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(_dir)
	# The harness drives the clock and powers circuits; SaveManager autosaves on dawn/dusk, so
	# point it at a throwaway stem before anything can trip that.
	SaveManager.slot_file_prefix = "mussel_shot_slot_"
	var packed: PackedScene = load("res://scenes/Main.tscn")
	main = packed.instantiate() if packed != null else null
	if main != null and main.get_script() == null:
		print("[mussel] Main.tscn instantiated WITHOUT its script — a world script does not parse.")
		get_tree().quit(1)
		return
	if main == null:
		print("[mussel] Main.tscn did not load")
		get_tree().quit(1)
		return
	add_child(main)
	await get_tree().create_timer(9.0).timeout
	main._countdown = 0.0
	if main.hud != null and main.hud.fade_rect != null:
		main.hud.fade_rect.color.a = 0.0
	var p: Node3D = main.player
	p.set("_fly", true)
	(p as CollisionObject3D).set_collision_layer_value(1, false)
	(p as CollisionObject3D).set_collision_mask_value(1, false)
	# Fauna hunts anything in the "player" group; leaving the lens in it once produced a crab
	# census of six crabs chasing the camera. The interaction ray still works without it — it
	# guards every use of _player() against null — which is what the prompt frames need.
	p.remove_from_group("player")
	GameClock.force_phase(GameClock.Phase.NIGHT if _night else GameClock.Phase.DAY)
	# The range runs on the mains like everything else up here.
	PowerGrid.power_circuit("topside_floodlights")
	var beds_node: Node = _find(main, "MusselBeds")
	if beds_node == null:
		print("[mussel] no MusselBeds node")
		get_tree().quit(1)
		return
	var beds: Array = beds_node.get("beds")
	print("[mussel] world up, %d beds, output -> %s" % [beds.size(), _dir])
	var tag: String = "night" if _night else "day"
	await _reef_shots(beds, tag)
	await _harvest_shots(beds, tag)
	await _pack_shots()
	await _stove_shots()
	SaveManager.erase_slot(SaveManager.active_slot)
	print("[mussel] done")
	get_tree().quit()

func _find(root: Node, node_name: String) -> Node:
	for n in root.find_children(node_name, "", true, false):
		return n
	return null

## The caisson face a bed is on, worked out from the leg it is nearest — the same derivation
## reef_shot uses for the snails, and the reason no face normal is typed in this file.
func _face_of(pos: Vector3) -> Vector3:
	var legs: Array = load("res://scripts/world/leg_reef.gd").LEGS
	var leg: Vector2 = legs[0]
	for l in legs:
		if Vector2(pos.x - l.x, pos.z - l.y).length() \
				< Vector2(pos.x - leg.x, pos.z - leg.y).length():
			leg = l
	var d := Vector2(pos.x - leg.x, pos.z - leg.y)
	return Vector3(signf(d.x), 0.0, 0.0) if absf(d.x) > absf(d.y) \
		else Vector3(0.0, 0.0, signf(d.y))

## Eye position and yaw that put `pos` in the middle of the frame from `dist` off its face.
## Yaw convention, checked rather than assumed: forward = (-sin y, 0, -cos y).
func _frame(pos: Vector3, dist: float, rise: float = 0.0) -> Array:
	var n: Vector3 = _face_of(pos)
	var eye: Vector3 = pos + n * dist + Vector3(0.0, rise, 0.0)
	var yaw: float = rad_to_deg(atan2(n.x, n.z))
	var pitch: float = rad_to_deg(atan2(-rise, dist))
	return [eye, yaw, pitch]

# --------------------------------------------------------------------- the reef

func _reef_shots(beds: Array, tag: String) -> void:
	if beds.is_empty():
		return
	# Sort by depth so the picks are spread up and down the band rather than being whatever
	# order the placement pass happened to build them in.
	var sorted: Array = beds.duplicate()
	sorted.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.y > b.global_position.y)
	main.hud.visible = false
	# SIX beds at reading distance, spread across the whole array. Six rather than three
	# because occlusion cannot be raycast here: the coral is MultiMesh and carries no
	# collider, so nothing can measure whether a 1.4 m bed is behind a 3 m reef mass from a
	# given vantage — and about a third of them are. Sampling more of them is the honest
	# answer to an occluder the harness cannot see (docs/AGENT_TRAPS.md: occlusion has to be
	# scored, and where it cannot be, over-sample).
	var step: int = maxi(1, sorted.size() / 6)
	for i in range(mini(6, sorted.size())):
		var bed: Node3D = sorted[mini(i * step, sorted.size() - 1)]
		var f: Array = _frame(bed.global_position, 2.4, 0.45)
		_subject = bed.global_position
		await _shot(f[0], f[1], f[2], "bed_close%02d_%s" % [i + 1, tag])
	# And two stood back far enough to show them AMONG THE CORAL, which is what the brief
	# asked for — mussels scattered through the reef, not mussels on bare concrete.
	for i in range(mini(2, sorted.size())):
		var bed: Node3D = sorted[i * 3]
		var f: Array = _frame(bed.global_position, 6.2, 1.4)
		_subject = bed.global_position
		await _shot(f[0], f[1], f[2], "bed_among_coral%02d_%s" % [i + 1, tag])
	# One wide frame down the leg, so the scatter reads as scatter.
	var b0: Node3D = sorted[0]
	var f0: Array = _frame(b0.global_position, 11.0, 2.8)
	_subject = b0.global_position
	await _shot(f0[0], f0[1], f0[2], "bed_leg_wide_" + tag)

# ------------------------------------------------------------------ the harvest

func _harvest_shots(beds: Array, tag: String) -> void:
	var bed: Node3D = beds[0]
	var f: Array = _frame(bed.global_position, 2.3, 0.45)
	_subject = bed.global_position
	# HUD ON: this frame is about the prompt chip the interaction ray writes, so the shot has
	# to prove the ray actually found the bed from a real standing distance.
	main.hud.visible = true
	await _shot(f[0], f[1], f[2], "harvest_prompt_" + tag)
	print("[mussel]   prompt on screen: '%s'" % bed.call("get_prompt"))
	# Now take it. Called directly rather than through a synthetic input event, so the frame
	# is about the RESULT and not about whether the harness can fake a keypress.
	for i in range(PlayerState.HOTBAR_SIZE):
		PlayerState.hotbar[i] = null
	bed.call("interact", "GATHER", main.player)
	for i in range(4000):
		if bed.get("_working") != true:
			break
		PlayerState.oxygen = 1.0
		await get_tree().process_frame
	print("[mussel]   bed spent=%s, pack now holds %s"
		% [bed.get("spent"), str(PlayerState.hotbar)])
	# Let MusselBed's ease finish — the survivors shrink and the bare scar fades in over
	# about a second, so a shot taken immediately photographs a full bed with soot on it.
	await get_tree().create_timer(2.4).timeout
	main.hud.visible = false
	await _shot(f[0], f[1], f[2], "bed_spent_" + tag)
	main.hud.visible = true
	await _shot(f[0], f[1], f[2], "bed_spent_prompt_" + tag)
	print("[mussel]   spent bed prompt: '%s' (empty = silent, as a picked node should be)"
		% bed.call("get_prompt"))

# --------------------------------------------------------------------- the pack

func _pack_shots() -> void:
	# Fill the belt with both states of the item so one frame shows the pair.
	for i in range(PlayerState.HOTBAR_SIZE):
		PlayerState.hotbar[i] = null
	PlayerState.add_item("mussels")
	PlayerState.add_item("mussels")
	PlayerState.add_item("mussels")
	PlayerState.add_item("mussels_boiled")
	PlayerState.add_item("mussels_boiled")
	main.hud.visible = true
	main.hud.toggle_panel("inventory")
	# Icons render on demand into a SubViewport, one item per frame — give them time to land.
	await get_tree().create_timer(2.5).timeout
	_subject = main.player.global_position
	await _shot_here("pack_mussels")
	main.hud.toggle_panel("inventory")

# -------------------------------------------------------------------- the stove

func _stove_shots() -> void:
	var stove: Node3D = null
	for n in main.find_children("*", "Interactable", true, false):
		var s: Script = n.get_script()
		if s != null and String(s.resource_path).ends_with("cook_stove.gd"):
			stove = n
			break
	if stove == null:
		print("[mussel] no CookStove in the tree")
		return
	# Derived from the stove's own transform. Its oven door faces -Z (rig_builder builds it
	# against the servery counter with its face toward the hall), so the cook stands south of
	# it; the pot is on the left hob at local (-0.3, 0.52, -0.3).
	var pot: Vector3 = stove.global_position + Vector3(-0.3, 0.52, -0.3)
	var eye: Vector3 = stove.global_position + Vector3(-0.25, 1.28, -1.35)
	var yaw: float = rad_to_deg(atan2(pot.x - eye.x, pot.z - eye.z)) + 180.0
	var pitch: float = rad_to_deg(atan2(pot.y - eye.y, Vector2(pot.x - eye.x, pot.z - eye.z).length()))
	_subject = pot
	# Mussels in hand, so the range offers BOIL rather than COOK.
	for i in range(PlayerState.HOTBAR_SIZE):
		PlayerState.hotbar[i] = null
	PlayerState.add_item("mussels")
	PlayerState.selected_hotbar = 0
	main.hud.visible = true
	await _shot(eye, yaw, pitch, "stove_boil_prompt")
	print("[mussel]   stove prompt: '%s' (verbs %s, powered=%s)"
		% [stove.call("get_prompt"), str(stove.call("available_verbs")),
			PowerGrid.is_powered("topside_floodlights")])
	stove.call("interact", "BOIL", main.player)
	await get_tree().create_timer(2.0).timeout
	main.hud.visible = false
	await _shot(eye, yaw, pitch, "stove_boiling")
	# Closer, on the pot itself, so the water and the lit hob read.
	await _shot(pot + Vector3(-0.02, 0.60, -0.52), yaw, -48.0, "stove_pot_close")
	# And the result.
	await get_tree().create_timer(6.0).timeout
	main.hud.visible = true
	await _shot(eye, yaw, pitch, "stove_boiled_result")
	print("[mussel]   after the boil, pack holds %s" % str(PlayerState.hotbar))

# ------------------------------------------------------------------- plumbing

var _pause: CanvasLayer = null

func _process(_d: float) -> void:
	# A focus-out pause freezes the world mid-capture, and a paused world still RENDERS —
	# beautiful, stable, meaningless frames. Unpausing is not enough either: PauseMenu's panel
	# is its own CanvasLayer (layer 15, not part of the HUD) and stays drawn after the tree
	# resumes. Both, every frame.
	get_tree().paused = false
	if _pause == null:
		_pause = _find_pause(get_tree().root)
	if _pause != null:
		var panel: Variant = _pause.get("panel")
		if panel is CanvasItem:
			(panel as CanvasItem).visible = false

func _find_pause(n: Node) -> CanvasLayer:
	var s: Script = n.get_script()
	if s != null and String(s.resource_path).ends_with("pause_menu.gd"):
		return n as CanvasLayer
	for c in n.get_children():
		var got: CanvasLayer = _find_pause(c)
		if got != null:
			return got
	return null

## The camera's eye is ~1.6 m above the player node's origin, so aiming a shot from the node
## position photographs the floor, or a wall on the far side of the room.
const EYE_UP: float = 1.6

func _shot(pos: Vector3, yaw_deg: float, pitch_deg: float, name_: String) -> void:
	if _only != "" and not name_.to_lower().contains(_only):
		return
	# HOLD THE POSE FOR THE WHOLE SETTLE, not just at the start. Setting it once and awaiting
	# a timer photographed three frames from up to 3 m away from where they were aimed — the
	# controller keeps integrating (buoyancy, the fly drift) across the wait, and the log's
	# "asked vs got" line is what caught it. Re-asserting every frame is the fix, and it is
	# also why _save prints the position the camera really ended up at.
	var p: Node3D = main.player
	for i in range(54):
		p.global_position = pos - Vector3(0.0, EYE_UP, 0.0)
		p.rotation.y = deg_to_rad(yaw_deg)
		p.get_node("Head").rotation.x = deg_to_rad(pitch_deg)
		p.set("velocity", Vector3.ZERO)
		p.set("input_locked", true)
		PlayerState.oxygen = 1.0
		await get_tree().process_frame
	await _save(name_, pos)

func _shot_here(name_: String) -> void:
	if _only != "" and not name_.to_lower().contains(_only):
		return
	await _save(name_, main.player.global_position + Vector3(0.0, EYE_UP, 0.0))

## Report the position the camera ACTUALLY ended up at and its distance to the subject, not
## the one the shot list asked for. That difference is what proves a frame is framed.
func _save(name_: String, want: Vector3) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/mussel_%s.png" % [_dir, name_]
	var got: Vector3 = main.player.global_position + Vector3(0.0, EYE_UP, 0.0)
	print("[mussel] %-28s eye asked (%.1f, %.1f, %.1f) got (%.1f, %.1f, %.1f) d(subject) %.2f m  err=%s"
		% [name_, want.x, want.y, want.z, got.x, got.y, got.z,
			got.distance_to(_subject), img.save_png(path)])
