extends Node
## PERCH / LEAP SCRATCH — the same two CatProbe scenarios, N times, in ONE boot.
##
##   godot --headless --path . res://tests/PerchScratch.tscn
##
## An INSTRUMENT, not a gate. CatProbe's leap-onto-a-crate and perch-onto-a-crate checks are
## both intermittent — one run of the full probe failed the leap row, the next failed the two
## perch rows and passed the leap — and a ten-minute probe that shows one sample of a flaky
## behaviour cannot tell you WHY. This boots the world once and repeats each scenario, printing
## the outcome per trial and a per-frame trace of the trials that fail.
##
## It asserts nothing. Read the traces.

const DT: float = 1.0 / 60.0
const DECK := Vector3(3.0, 18.0, -3.0)
const TRIALS: int = 6

var _cat: Node3D
var _player: Node3D

func _ready() -> void:
	var main: Node3D = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	var t0: int = Time.get_ticks_msec()
	var waited: int = 0
	while Time.get_ticks_msec() - t0 < 9000 or waited < 180:
		await get_tree().physics_frame
		waited += 1
	GameClock.force_phase(GameClock.Phase.DAY)
	_player = get_tree().get_first_node_in_group("player")
	_cat = get_tree().get_first_node_in_group("ship_cat")
	for c in _cat.get_children():
		if c is Interactable:
			(c as Interactable).emit_signal("interacted", "SAY HELLO")
			break
	await get_tree().physics_frame

	var crate := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(2.4, 1.0, 2.4)
	cs.shape = bx
	crate.add_child(cs)
	get_tree().current_scene.add_child(crate)
	crate.global_position = Vector3(5.6, 18.5, -3.0)
	print("")
	print("=== LEAP: crate top y 19.00, player standing ON it at 19.2")
	var leap_ok: int = 0
	for t in range(TRIALS):
		if await _leap_trial(t):
			leap_ok += 1
	print("  LEAP: %d/%d trials ended on the crate" % [leap_ok, TRIALS])
	crate.queue_free()
	await get_tree().physics_frame

	var pc := StaticBody3D.new()
	var pcs := CollisionShape3D.new()
	var pbx := BoxShape3D.new()
	pbx.size = Vector3(1.8, 0.9, 1.8)
	pcs.shape = pbx
	pc.add_child(pcs)
	get_tree().current_scene.add_child(pc)
	pc.global_position = Vector3(5.0, 18.45, -3.0)
	print("")
	print("=== PERCH: crate top y 18.90, player on the deck at (3.8, 18.1, -2.0)")
	var perch_ok: int = 0
	for t in range(TRIALS):
		if await _perch_trial(t):
			perch_ok += 1
	print("  PERCH: %d/%d trials reached State.PERCH" % [perch_ok, TRIALS])
	pc.queue_free()
	print("---")
	print("FAILURES: 0")
	get_tree().quit(0)

func _hold() -> void:
	_cat.set("_hunt_cd", 999.0)
	_cat.set("_zoom_cd", 999.0)
	_cat.set("_play_cd", 999.0)

func _row(i: int) -> String:
	return "t%3d st%2d act=%-6s it=%5.1f y=%.2f at=%s jt=%.2f jw=%.2f jc=%.2f ds=%.2f pb=%.2f ps=%.2f" \
		% [i, int(_cat.get("_state")), str(_cat.get("_idle_act")), float(_cat.get("_idle_t")),
			_cat.global_position.y, str(_cat.global_position.snappedf(0.01)),
			float(_cat.get("_jump_t")), float(_cat.get("_jump_wind")),
			float(_cat.get("_jump_cd")), float(_cat.get("_drop_stall")),
			float(_cat.get("_perch_best")), float(_cat.get("_perch_stall"))]

func _leap_trial(t: int) -> bool:
	_cat.global_position = DECK
	_cat.call("_reseat")
	_cat.call("_end_idle")
	_cat.set("_wash_t", 0.0)
	_cat.set("_stayed", false)
	_cat.set("_jump_cd", 0.0)
	for i in range(20):
		_player.global_position = Vector3(5.6, 19.2, -3.0)
		await get_tree().physics_frame
	var y0: float = _cat.global_position.y
	var top: float = y0
	var flew: bool = false
	var trace: Array = []
	for i in range(600):
		_player.global_position = Vector3(5.6, 19.2, -3.0)
		_cat.set("_roam_cd", 999.0)
		_cat.set("_idle_cd", 999.0)
		_hold()
		await get_tree().physics_frame
		top = maxf(top, _cat.global_position.y)
		if float(_cat.get("_jump_t")) > 0.0:
			flew = true
		if i % 30 == 0:
			trace.append(_row(i))
	var ended_on: bool = _cat.global_position.y > y0 + 0.5
	print("  leap trial %d: flew=%s rose=%.2f ended y=%.2f (%s)"
		% [t, str(flew), top - y0, _cat.global_position.y, "ON" if ended_on else "OFF"])
	if not ended_on:
		for r in trace:
			print("      %s" % r)
	return ended_on

func _perch_trial(t: int) -> bool:
	_cat.global_position = DECK
	_cat.call("_reseat")
	_cat.call("_end_idle")
	_player.global_position = Vector3(3.8, 18.1, -2.0)
	_cat.set("_roam_cd", 0.0)
	_cat.set("_idle_cd", 0.0)
	_cat.set("_still", 30.0)
	_cat.set("_wash_t", 0.0)
	_cat.set("_stretch_t", 0.0)
	_cat.set("_was_asleep", false)
	_cat.set("_jump_cd", 0.0)
	for i in range(10):
		_hold()
		await get_tree().physics_frame
	_cat.call("_begin_action", "perch")
	var aim: Vector3 = _cat.get("_idle_at")
	var act: String = String(_cat.get("_idle_act"))
	var got: bool = false
	var top: float = _cat.global_position.y
	var trace: Array = []
	for i in range(600):
		_hold()
		await get_tree().physics_frame
		top = maxf(top, _cat.global_position.y)
		if i % 30 == 0:
			trace.append(_row(i))
		if int(_cat.get("_state")) == 12:
			got = true
			break
	print("  perch trial %d: act=%s aim=%s reached=%s peak y=%.2f"
		% [t, act, str(aim.snappedf(0.01)), str(got), top])
	if not got:
		for r in trace:
			print("      %s" % r)
	return got
