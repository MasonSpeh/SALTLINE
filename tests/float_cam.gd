extends Node3D
## FLOAT CAM — photographs the open deck south of the bunkhouse looking north/north-west
## and up, which is the frame the owner's screenshot was taken from, and re-runs the
## float scan with SCRIPT ATTRIBUTION so each hit names the builder file that made it.
##
## Run WINDOWED (viewport texture is empty headless):
##   godot --path . res://tests/FloatCam.tscn
## PNGs land in the scratchpad as fc_<name>.png.

const SUPPORT := preload("res://scripts/world/support_index.gd")
const OUT := "/private/tmp/claude-501/-Users-mjspeh-Desktop-UltraInbox/87d5de70-f27c-48d3-bab9-cb1e9a8f822d/scratchpad"

# name, eye, aim, fov
#
# The owner's frame is from the ALLEY — the strip of open deck between the machine shop's
# north face (z -5.875) and the bunkhouse's south face (z 3.875). That south face is the
# pale wall carrying ACCOMMODATION / EYEWASH / FIRE HOSE REEL / SAFETY EQUIPMENT, all of
# which exterior_dress.gd paints at yaw 180 (facing -Z, i.e. into the alley). Looking north
# from the alley puts the open sea on the RIGHT of frame, which is the west end past x -28.
# An earlier pass shot from z 8-12 and photographed the inside of the bunkhouse.
const SHOTS := [
	["alley_n_up",     Vector3(-24.0, 19.6, -1.5), Vector3(-23.0, 22.4,  3.6), 75.0],
	["alley_n_up_w",   Vector3(-25.5, 19.6, -3.0), Vector3(-22.5, 23.2,  3.8), 80.0],
	["alley_nw_up",    Vector3(-19.0, 19.6, -2.0), Vector3(-25.0, 22.4,  3.6), 78.0],
	["alley_ne_up",    Vector3(-25.0, 19.6, -2.0), Vector3(-17.0, 22.4,  3.6), 78.0],
	["alley_sign_wall",Vector3(-22.0, 19.7, -1.0), Vector3(-22.4, 20.2,  3.6), 70.0],
	# Along the alley: anything hanging in its air stands in profile against the far end.
	["alley_look_w",   Vector3(-11.0, 21.0, -1.0), Vector3(-32.0, 21.6, -1.0), 72.0],
	["alley_look_e",   Vector3(-30.0, 21.0, -1.0), Vector3( -9.0, 21.6, -1.0), 72.0],
	# From out over the water off the west end, looking back into the alley mouth: the
	# cleanest test for "is that thing standing on anything".
	["alley_from_sea", Vector3(-46.0, 23.0, -1.0), Vector3(-20.0, 21.8, -0.5), 50.0],
	# Straight up from the alley floor.
	["alley_up_hard",  Vector3(-22.0, 19.4, -1.0), Vector3(-22.5, 26.0,  2.0), 85.0],
	# Down on the alley from the south-west, high.
	["alley_above",    Vector3(-34.0, 30.0, -14.0), Vector3(-21.0, 20.5, -0.5), 65.0],
]

const BX0 := -34.0
const BX1 :=  -6.0
const BY0 :=  19.0
const BY1 :=  34.0
const BZ0 :=  -8.0
const BZ1 :=   5.0
const DROP: float = 1.5
const SPAN_CAP: float = 70.0

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
	print("[fc] world added, waiting for build")
	for i in range(24):
		await get_tree().create_timer(1.0).timeout
	print("[fc] wait done")
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player:
		player.set_physics_process(false)
		player.set_process(false)
		player.global_position = Vector3(160, 60, 160)
	GameClock.force_phase(GameClock.Phase.DAY)
	await get_tree().create_timer(0.6).timeout

	_scan()

	print("[fc] entering shot loop")
	for s in SHOTS:
		_cam.global_position = s[1]
		_cam.look_at(s[2], Vector3.UP)
		_cam.fov = s[3]
		_cam.current = true
		await get_tree().create_timer(0.3).timeout
		get_viewport().get_texture().get_image().save_png("%s/fc_%s.png" % [OUT, s[0]])
		print("[fc] shot: ", s[0])
		for p in PICKS:
			if str(p[0]) == str(s[0]):
				_pick(s[0], int(p[1]), int(p[2]))
	print("[fc] done")
	get_tree().quit()

## Screen pixels to identify: [shot_name, x, y]. Answers "what IS that thing in the
## picture" without guessing — casts the camera ray and reports every geometry whose world
## AABB it crosses, nearest first, with the builder script that made it.
const PICKS := [
	["alley_look_e", 1000, 620],
	["alley_look_e",  930, 595],
	["alley_look_e", 1150, 640],
	["alley_n_up_w",  950, 670],
	["alley_n_up_w",  810, 635],
]

func _pick(shot: String, px: int, py: int) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var sp := Vector2(float(px) * vp.x / 1280.0, float(py) * vp.y / 720.0)
	var o: Vector3 = _cam.project_ray_origin(sp)
	var d: Vector3 = _cam.project_ray_normal(sp)
	var hits: Array = []
	for n in _geometry(_main):
		var vi := n as VisualInstance3D
		if vi == null or not is_instance_valid(vi) or not vi.is_inside_tree():
			continue
		var local: AABB = vi.get_aabb()
		if local.size == Vector3.ZERO:
			continue
		var a: AABB = vi.global_transform * local
		if a.size == Vector3.ZERO or a.size.x > SPAN_CAP or a.size.z > SPAN_CAP:
			continue
		var p = a.intersects_ray(o, d)
		if p == null:
			continue
		var dist: float = o.distance_to(p)
		hits.append([dist, "%-22s d=%6.2f  size %5.2fx%5.2fx%5.2f  ctr %s\n        owner: %s  chain: %s" % [
			vi.name, dist, a.size.x, a.size.y, a.size.z, _v(a.get_center()),
			_owner_script(vi), _chain(vi)]])
	hits.sort_custom(func(x, y): return x[0] < y[0])
	print("--- PICK %s (%d,%d): %d hits ---" % [shot, px, py, hits.size()])
	for h in hits.slice(0, 8):
		print("   ", h[1])

# ---------------------------------------------------------------- scan

func _scan() -> void:
	var index = SUPPORT.new()
	index.build(_main)
	print("[fc] surfaces indexed: ", index.surface_count())
	var hits: Array = []
	var in_box: int = 0
	for n in _geometry(_main):
		var vi := n as VisualInstance3D
		if vi == null or not is_instance_valid(vi) or not vi.is_inside_tree():
			continue
		var local: AABB = vi.get_aabb()
		if local.size == Vector3.ZERO:
			continue
		var a: AABB = vi.global_transform * local
		if a.size == Vector3.ZERO or a.size.x > SPAN_CAP or a.size.z > SPAN_CAP:
			continue
		var c: Vector3 = a.get_center()
		if c.x < BX0 or c.x > BX1 or c.y < BY0 or c.y > BY1 or c.z < BZ0 or c.z > BZ1:
			continue
		in_box += 1
		var top: float = index.support_top(a, vi, 0.05)
		var gap: float = INF if top == -INF else a.position.y - top
		if gap <= DROP:
			continue
		var vol: float = a.size.x * a.size.y * a.size.z
		hits.append([vol, "%-22s size %5.2fx%5.2fx%5.2f  ctr %s  base %6.2f  gap %s\n      owner: %s\n      chain: %s" % [
			vi.name, a.size.x, a.size.y, a.size.z, _v(c), a.position.y,
			("NONE BELOW" if top == -INF else "%.2f" % gap),
			_owner_script(vi), _chain(vi)]])
	print("[fc] geometry in box: ", in_box)
	hits.sort_custom(func(x, y): return x[0] > y[0])
	print("=== FLOATING (biggest first): ", hits.size(), " ===")
	for h in hits.slice(0, 30):
		print("  vol %8.3f  %s" % [h[0], h[1]])

## The builder that made this node: nearest ancestor (inclusive) carrying a script.
func _owner_script(n: Node) -> String:
	var cur: Node = n
	while cur != null:
		var s: Script = cur.get_script() as Script
		if s != null:
			return "%s  <%s>" % [s.resource_path.get_file(), cur.name]
		cur = cur.get_parent()
	return "?"

## Nearest ancestors that have real (non auto-generated) names — those are the ones a
## human typed, so they name the feature.
func _chain(n: Node) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var cur: Node = n
	var guard: int = 0
	while cur != null and guard < 40:
		var nm: String = str(cur.name)
		if not nm.begins_with("@"):
			parts.append(nm)
		cur = cur.get_parent()
		guard += 1
	parts.reverse()
	return "/".join(parts)

func _geometry(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_in_group("player") or n.is_in_group("floating_debris") \
				or n.is_in_group("gyre_streaks") or n.is_in_group("lit_flares"):
			continue
		var s: Script = n.get_script() as Script
		var skip: bool = false
		if s != null:
			for frag in SUPPORT.SKIP_SCRIPTS:
				if s.resource_path.ends_with(frag):
					skip = true
					break
		if skip:
			continue
		for c in n.get_children():
			stack.append(c)
		if SUPPORT.is_geometry(n):
			out.append(n)
	return out

func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
