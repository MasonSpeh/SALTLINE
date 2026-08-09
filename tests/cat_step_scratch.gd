extends Node
## HOW TALL A THING CAN THE CAT ACTUALLY GET ONTO? A sweep, not an argument.
##
##   godot --headless --path . res://tests/CatStepScratch.tscn
##
## WHY THIS EXISTS. `ship_cat.gd` documents three bands — step (rise <= CLIMB_UP 0.62), leap
## (CLIMB_UP..JUMP_UP 1.25) and refuse (above that) — and the s54 perch action ran straight into
## a case the bands do not describe: the animal stalled 0.9 m short of a 0.45 m crate, which is
## squarely inside the "step" band. The suspected cause is that the two probes disagree about
## WHERE they look. The footfall ray probes `want`, one step ahead (18 mm at a walk), so it only
## sees a rise once the cat's ORIGIN is within a step of the obstacle's footprint — while
## `_step_clear`'s nose sphere refuses any position whose nose is inside the face, which is
## `_body_len()/2 - r + r` = 0.33 m out. The origin can therefore never get close enough for the
## footfall ray to see a vertical face at all, and the only thing that can rescue it is the
## LEDGE probe a body-length ahead, which is gated `lift > CLIMB_UP` and so declines everything
## the cat is allowed to simply step onto.
##
## That is a reasoned story about two constants, and this repo's rule is that a reasoned story
## is not a measurement. So: build a box, stand the player on it, and see.
##
## Nothing here asserts. It prints a table, and the table is the finding.

const HEIGHTS: Array = [0.20, 0.35, 0.45, 0.55, 0.62, 0.70, 0.85, 1.00, 1.15]
## Open deck with room around it — the same spot CatProbe's leap check builds its crate on.
const FOOT := Vector3(5.6, 18.0, -3.0)
const CAT_AT := Vector3(3.0, 18.0, -3.0)

var _cat: Node3D
var _player: Node3D

func _ready() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	if main.get_script() == null:
		print("Main.tscn lost its script — a parse error somewhere. Nothing below is real.")
		get_tree().quit(1)
		return
	await get_tree().create_timer(6.0).timeout
	for i in range(10):
		await get_tree().physics_frame
	_cat = get_tree().get_first_node_in_group("ship_cat")
	_player = get_tree().get_first_node_in_group("player")
	if _cat == null or _player == null:
		print("no cat / no player")
		get_tree().quit(1)
		return
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.set("_lying", false)
	_player.set("_lying_sleeping", false)
	PlayerState.selected_hotbar = -1
	for c in _cat.get_children():
		if c is Interactable:
			(c as Interactable).interact("SAY HELLO", _player)
	await get_tree().physics_frame

	print("\n=== how tall a thing can the cat get onto? (CLIMB_UP 0.62, JUMP_UP 1.25) ===")
	print("  the player stands ON the box, 2.6 m from the cat, for 400 frames (13 s)")
	print("  %-8s %-9s %-9s %-8s %-8s %s"
		% ["height", "got_up", "max_rise", "flew", "end_gap", "end_y"])
	for h in HEIGHTS:
		var r: Dictionary = await _try(float(h))
		print("  %-8.2f %-9s %-9.3f %-8s %-8.2f %.2f"
			% [float(h), "YES" if r["up"] else "no", float(r["rise"]),
				"jump" if r["flew"] else "-", float(r["gap"]), float(r["y"])])
	print("\n  got_up  = the cat's settled height ended within 0.15 m of the box top")
	print("  flew    = a `_jump_t`/`_jump_wind` flight fired at any point")
	print("  end_gap = flat metres between the cat and the box centre at the end")
	get_tree().quit(0)

func _try(h: float) -> Dictionary:
	var box := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = Vector3(2.0, h, 2.0)
	cs.shape = shp
	box.add_child(cs)
	get_tree().current_scene.add_child(box)
	box.global_position = FOOT + Vector3(0, h * 0.5, 0)     # foot on the deck, top at 18 + h
	_cat.global_position = CAT_AT
	_cat.call("_reseat")
	_cat.set("_stayed", false)
	_cat.set("_wash_t", 0.0)
	_cat.set("_stretch_t", 0.0)
	_cat.set("_was_asleep", false)
	_cat.call("_end_idle")
	var top: float = FOOT.y + h
	var rise: float = 0.0
	var flew: bool = false
	for i in range(400):
		# The player stands ON it — the strongest legitimate pull the follow has, and the same
		# staging CatProbe's leap check uses.
		_player.global_position = Vector3(FOOT.x, top + 0.1, FOOT.z)
		_cat.set("_hunt_cd", 999.0)
		_cat.set("_zoom_cd", 999.0)
		_cat.set("_play_cd", 999.0)
		_cat.set("_idle_cd", 999.0)
		_cat.set("_roam_cd", 999.0)
		await get_tree().physics_frame
		rise = maxf(rise, _cat.global_position.y - FOOT.y)
		if float(_cat.get("_jump_t")) > 0.0 or float(_cat.get("_jump_wind")) > 0.0:
			flew = true
	var gap: float = Vector2(_cat.global_position.x - FOOT.x,
		_cat.global_position.z - FOOT.z).length()
	var up: bool = absf(_cat.global_position.y - top) < 0.15
	var y: float = _cat.global_position.y
	box.queue_free()
	_cat.global_position = CAT_AT
	_cat.call("_reseat")
	await get_tree().physics_frame
	return {"up": up, "rise": rise, "flew": flew, "gap": gap, "y": y}
