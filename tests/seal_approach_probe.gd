extends Node
## SEAL APPROACH PROBE — the state neither existing probe covers, and the one that carried the
## owner's "seal hovering 1-2 m above the foundation".
##
## SealFloatProbe forces `_hauled = false` (patrol only) and FaunaBugsProbe teleports the animal
## onto the shelf, so the RUN IN toward the pontoon — the branch that lerped y toward the sea
## with a 0.667 s filter against waves at omega 0.83-6.02 rad/s — had never been measured. It is
## also the only branch seen against the foundation, which is why the report named the foundation.
##
##   godot --headless --path . res://tests/SealApproachProbe.tscn

const CRUISE_UNDER: float = 0.10   # mirrors HarborSeal's own constant

var failures: int = 0
var _completed: bool = false

func _ready() -> void:
	AiBudget.enabled = false     # full rate: this is a measurement, not a frame budget
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in range(40):
		await get_tree().physics_frame
	await _run()
	if not _completed:
		print("FAIL  probe ran to completion (it did NOT)")
		failures += 1
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _ok(c: bool, m: String) -> void:
	print("%s  %s" % ["PASS" if c else "FAIL", m])
	if not c:
		failures += 1

func _seal() -> Node3D:
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var sc: Script = n.get_script()
		if sc == null:
			continue
		var cm: Dictionary = {}
		if n.get("_belly") != null and n.get("_haul") != null:
			return n as Node3D
	return null

func _run() -> void:
	var seal: Node3D = _seal()
	_ok(seal != null, "found a harbor seal")
	if seal == null:
		return
	var crown: float = float(seal.get("_crown"))
	var haul: Vector3 = seal.get("_haul")
	# FORCE THE APPROACH: hauled, but still well outside HAUL_CLIMB_M (5 m) so the branch under
	# test is the swimming run-in rather than the climb.
	seal.set("_hauled", true)
	seal.global_position = Vector3(haul.x + 34.0, 0.0, haul.z - 8.0)
	var worst: float = 0.0
	var sum: float = 0.0
	var n: int = 0
	for i in range(240):
		await get_tree().physics_frame
		var to_haul: float = Vector2(haul.x - seal.global_position.x,
			haul.z - seal.global_position.z).length()
		if to_haul <= 6.0:
			break     # into the climb — a different branch, tested below
		var sea: float = Gyre.wave_height(
			Vector2(seal.global_position.x, seal.global_position.z), Gyre.water_time())
		var want: float = sea - CRUISE_UNDER - crown
		var err: float = absf(seal.global_position.y - want)
		worst = maxf(worst, err)
		sum += err
		n += 1
	var mean: float = sum / maxf(float(n), 1.0)
	print("[approach] %d frames measured, mean |y error| %.4f m, worst %.4f m" % [n, mean, worst])
	# The branch ASSIGNS now, so the error is float noise. Before the fix this filter lagged the
	# sea by ~0.53 m RMS and ~1.50 m peak at the calm sea state.
	_ok(n >= 30, "the approach branch actually ran (%d frames)" % n)
	# TOLERANCE, and why it is not zero. The seal assigns y from the sea sampled inside its own
	# _process; this probe reads the result a frame later, by which time the sea has moved. The
	# fast Gerstner bands run to omega 6.02 rad/s, so one 16 ms frame is up to ~0.10 m of
	# genuine surface motion — an artefact of WHEN the two sides sample, not of the animal.
	# 0.35 m sits well above that floor and far below the 1.50 m peak the filter used to lag by,
	# so it distinguishes the two states without pretending to a precision the sampling cannot
	# support.
	_ok(worst < 0.35,
		"the seal tracks the sea on its run in — worst |y error| %.4f m (the filter lagged ~1.50 m)" % worst)
	_completed = true
