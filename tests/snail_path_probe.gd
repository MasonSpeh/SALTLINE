extends Node
## Does a snail WANDER, or does it orbit? Boots the real world, follows each snail for a
## simulated stretch, and measures the shape of its path.
##
## The tell for circling is CUMULATIVE SIGNED TURN: a wanderer's heading changes direction
## as often as not, so its signed turns cancel and the total stays near zero. An orbiting
## animal turns the same way every time, so the total grows without bound — a full lap is
## 360 degrees, so several thousand degrees over a minute means it has been going round
## and round. Net displacement over path length says the same thing from the other side:
## a circler travels far and arrives nowhere.

const SAMPLE_SEC: float = 45.0
const FAUNA := preload("res://scripts/world/bloom_fauna.gd")

func _ready() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(3.0).timeout

	var snails: Array = []
	for t in [FAUNA.LampSnail, FAUNA.RustSnail, FAUNA.GlassSnail]:
		var n: Node3D = _find(main, t)
		if n:
			snails.append([n, str(t).get_slice("(", 0)])
	if snails.is_empty():
		print("no snails found")
		get_tree().quit(1)
		return

	var tracks: Dictionary = {}
	for s in snails:
		tracks[s[0].get_instance_id()] = {
			"name": s[1], "start": (s[0] as Node3D).global_position,
			"prev": (s[0] as Node3D).global_position, "path": 0.0,
			"turn": 0.0, "last_dir": Vector3.ZERO, "stuck": 0.0, "max_stuck": 0.0,
		}
	var elapsed: float = 0.0
	while elapsed < SAMPLE_SEC:
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		elapsed += dt
		for s in snails:
			var n: Node3D = s[0]
			if not is_instance_valid(n):
				continue
			var tr: Dictionary = tracks[n.get_instance_id()]
			var d: Vector3 = n.global_position - tr["prev"]
			d.y = 0.0
			var step: float = d.length()
			tr["path"] += step
			if step < 0.0005:
				tr["stuck"] += dt
				tr["max_stuck"] = maxf(tr["max_stuck"], tr["stuck"])
			else:
				tr["stuck"] = 0.0
				var dir: Vector3 = d.normalized()
				if tr["last_dir"] != Vector3.ZERO:
					# Signed turn about UP: positive one way, negative the other.
					var cross: float = tr["last_dir"].cross(dir).y
					var dot: float = clampf(tr["last_dir"].dot(dir), -1.0, 1.0)
					tr["turn"] += rad_to_deg(atan2(cross, dot))
				tr["last_dir"] = dir
			tr["prev"] = n.global_position

	print("--- snail path probe (%.0fs) ---" % SAMPLE_SEC)
	var fails: int = 0
	for s in snails:
		var n: Node3D = s[0]
		var tr: Dictionary = tracks[n.get_instance_id()]
		var net: float = (n.global_position - tr["start"]).length()
		var path: float = tr["path"]
		var straightness: float = (net / path) if path > 0.01 else 0.0
		var laps: float = absf(tr["turn"]) / 360.0
		var verdict := "OK"
		# A circler: many laps of same-signed turn and almost no net progress.
		if laps > 3.0 and straightness < 0.15:
			verdict = "CIRCLING"
			fails += 1
		if tr["max_stuck"] > 6.0:
			verdict += " STUCK(%.1fs)" % tr["max_stuck"]
			fails += 1
		print("  %-12s path=%.2fm net=%.2fm straightness=%.2f signed-turn=%.0fdeg (%.1f laps) %s"
			% [tr["name"], path, net, straightness, tr["turn"], laps, verdict])
	print("SNAIL-FAILURES: ", fails)
	get_tree().quit(0)

func _find(root: Node, type) -> Node3D:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if is_instance_of(n, type):
			return n as Node3D
	return null
