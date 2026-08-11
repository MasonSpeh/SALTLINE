extends Node
## THE CATCH-UP TELEPORT, proven end to end: a befriended cat left 30 m behind on open
## deck must arrive BEHIND the player within seconds — a distance no walk covers at
## 1.15 m/s, so a pass is a pass because the teleport fired, not because the animal
## hurried (the anti-vacuity is arithmetic).
##
##   godot --headless --path . res://tests/CatCatchupProbe.tscn

var failures: int = 0

func _ok(cond: bool, msg: String) -> void:
	print("%s  %s" % ["PASS" if cond else "FAIL", msg])
	if not cond:
		failures += 1

func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(9.0).timeout
	GameClock.force_phase(GameClock.Phase.DAY)
	var cat: Node3D = get_tree().get_first_node_in_group("ship_cat")
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if cat == null or player == null:
		print("FAIL  world up (cat %s player %s)" % [cat, player])
		print("FAILURES: 1")
		get_tree().quit(1)
		return
	# Befriended, awake, and parked: the catch-up lives on the follow path only.
	cat.set("friend", true)
	cat.set("_spawn_nap", false)
	# Topside main deck, both on rig 1: cat by the bunkhouse door, player far south-east —
	# 30+ m of open deck, no route problem, just distance.
	cat.global_position = Vector3(-6.0, 18.7, 10.0)
	player.global_position = Vector3(18.0, 18.1, -8.0)
	player.rotation.y = deg_to_rad(35.0)
	# THE PLAYER WALKS. The pop is gated on a travelling player (a parked one leaves the
	# cat to solve on foot — that is the design, and CatProbe's maze/descent scenarios
	# depend on it), so the probe strolls the player along the south deck at ~1.9 m/s
	# instead of teleporting them and standing still.
	for i in range(70):
		player.global_position += Vector3(0.095, 0.0, -0.06)
		player.global_position.y = 18.1
		await get_tree().create_timer(0.05).timeout
	var d: float = cat.global_position.distance_to(player.global_position)
	_ok(d < 8.0, "the cat closed a 30+ m gap in 3.5 s — impossible on foot (d now %.1f m)" % d)
	var fwd: Vector3 = -player.global_transform.basis.z
	var rel: Vector3 = cat.global_position - player.global_position
	rel.y = 0.0
	_ok(fwd.dot(rel.normalized()) < 0.25,
		"...and arrived BEHIND the view, not in front of it (dot %.2f)" % fwd.dot(rel.normalized()))
	_ok(cat.global_position.y > 15.0, "...on the deck, not rescued from the sea (y %.1f)" % cat.global_position.y)
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
