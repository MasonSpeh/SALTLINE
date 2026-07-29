extends Node3D
## THE OWNER JUDGES BY LOOKING, so this photographs the three fixes in the real Main scene
## and prints the measurement beside each frame:
##
##   * LAMP SNAIL — at night on the pontoon, in a dark interior, and in broad DAY, to prove
##     the moon palette landed and that the animal is never dark and never unlit. Each pair
##     is a close view and a "pool" view aimed at the plating BESIDE it, which is the only
##     way to see whether the cast light is really there or the shell is just emissive.
##   * CORVID GULLS — each of the three perches, near and at foot level. The boots view is
##     level and at foot height so the surface runs across the frame as a straight line
##     through the feet: floating shows as a gap you can count pixels in.
##   * HARBOR SEAL — forced to haul out, photographed on the pontoon foundation, with its
##     body AABB tested against the world for intersections.
##
## Run WINDOWED — the viewport texture comes back empty headless:
##   godot --path . res://tests/FaunaFixShot.tscn [out_dir]

const DEFAULT_OUT := "/private/tmp/claude-501/-Users-mjspeh-Desktop-UltraInbox/7cb79fc2-367f-4871-ad61-e3f271b05ed7/scratchpad/fauna"
## A genuinely unlit room: the stores, wet-deck level, one door, no window, and the rig has
## no power until the player fixes the breaker. If the snail reads there it reads anywhere.
const DARK_ROOM := Vector3(13.0, 2.05, -19.0)

var _out: String = DEFAULT_OUT
var _cam: Camera3D
var _skip: Array[RID] = []
var _pause_panel: Control

func _ready() -> void:
	# This has to run WINDOWED (the viewport texture is empty headless) and it is launched
	# from a terminal, so the game window never holds focus — and pause_menu.gd pauses the
	# tree on NOTIFICATION_APPLICATION_FOCUS_OUT. Unpaused every frame, with the harness
	# itself exempt, or the world freezes halfway through and the later subjects are
	# photographed and measured in whatever pose they were stopped in.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	add_child(load("res://scenes/Main.tscn").instantiate())
	await get_tree().process_frame
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	_cam.far = 900.0
	_cam.fov = 55.0
	# PARK THE PLAYER FIRST, before anything has had time to react to it. The wet-deck perch
	# is 7.1 m from the spawn point, well inside the 10 m flush radius, so waiting even a
	# couple of seconds means photographing an empty drum and a bird climbing out of frame.
	var player: Node3D = null
	for i in range(240):
		player = get_tree().get_first_node_in_group("player")
		if player:
			break
		await get_tree().process_frame
	if player:
		player.set_physics_process(false)
		player.set_process(false)
		player.global_position = Vector3(170, 60, 170)   # far enough not to flush a bird
	await get_tree().create_timer(4.0).timeout
	for n in get_tree().root.find_children("*", "CollisionObject3D", true, false):
		var host: Node = n
		while host != null:
			var s: Script = host.get_script()
			if s != null and String(s.resource_path).ends_with("bloom_fauna.gd"):
				_skip.append((n as CollisionObject3D).get_rid())
				break
			host = host.get_parent()

	# ---------------------------------------------------------------- the snail
	var fauna: Node = _fauna_root()
	var dark_snail: Node3D = null
	if fauna:
		var cls: GDScript = load("res://scripts/world/bloom_fauna.gd")
		# The stores get a snail of their own for the dark-interior frame. Same class, same
		# _process — this is the shipping animal, not a mock-up of it.
		dark_snail = (cls as Object).get("LampSnail").new(90, DARK_ROOM)
		fauna.add_child(dark_snail)
		dark_snail.global_position = DARK_ROOM
	_phase(GameClock.Phase.NIGHT)
	await get_tree().create_timer(3.0).timeout
	var snails: Array = get_tree().get_nodes_in_group("snail_lamp")
	print("[fix] %d lamp snails" % snails.size())
	var pontoon: Node3D = _pick(snails, Vector3(-10.0, 0.95, -12.0))
	# Shots FIRST, reading second: the render budget only keeps what the active camera is
	# near, so a level read while the camera is still parked on the previous subject reports
	# a culled animal as an unlit one.
	if pontoon:
		await _shots("snail_night", pontoon.global_position)
		_snail_report("night pontoon", pontoon)
	if dark_snail:
		await _shots("snail_dark", dark_snail.global_position)
		_snail_report("night stores", dark_snail)
	_phase(GameClock.Phase.DAY)
	await get_tree().create_timer(2.5).timeout
	if pontoon:
		await _shots("snail_day", pontoon.global_position)
		_snail_report("day  pontoon", pontoon)
	if dark_snail:
		await _shots("snail_dark_day", dark_snail.global_position)
		_snail_report("day  stores", dark_snail)

	# ---------------------------------------------------------------- the gulls
	# Mid-DAY, not the phase's first second: DAY opens with the sun at 16 degrees and the
	# whole deck in raking shadow, which is the one light you cannot judge a white bird in.
	_phase(GameClock.Phase.DAY)
	GameClock._phase_elapsed_sec = GameClock.phase_durations_minutes[GameClock.Phase.DAY] * 30.0
	await get_tree().create_timer(2.0).timeout
	var perched: Array = _with_prop("_perch")
	print("[fix] %d corvid gulls" % perched.size())
	for i in range(perched.size()):
		var g: Node3D = perched[i]
		_bird_report(i, g)
		await _shots("perch%d" % i, g.global_position + Vector3(0, 0.2, 0), 1.3, 2.4)

	# ---------------------------------------------------------------- the seal
	var seals: Array = _with_prop("_haul")
	print("[fix] %d harbor seals" % seals.size())
	# Only force the one the game itself would ever haul (HarborSeal._idx_zero). Forcing both
	# parks two 1.8 m animals on the same square metre, which is a harness artifact that
	# looks exactly like a placement bug in the photograph.
	for s in seals:
		if (s as Node).get_index() % 2 == 0:
			s.set("_hauled", true)
			s.set("_haul_timer", 600.0)
	# It lerps to the haul spot at delta*1.5, so a few seconds is plenty to arrive.
	await get_tree().create_timer(8.0).timeout
	# Photograph the one that is actually ON the shelf. Only the _idx_zero() seal hauls out
	# by design, so which array slot that is varies run to run.
	var resting: Node3D = null
	for i in range(seals.size()):
		var s: Node3D = seals[i]
		_seal_report(i, s)
		if s.global_position.distance_to(s.get("_haul")) < 1.0:
			resting = s
	if resting:
		_reach_check(resting)
		await _shots("seal", resting.global_position, 3.2, 6.0)
	else:
		print("[fix] NO seal reached the haul spot — nothing photographed")
	get_tree().quit()

## Undo the focus-out auto-pause every frame: the tree, and the PANEL it opens, which would
## otherwise sit across the middle of every frame this harness saves.
func _process(_d: float) -> void:
	if get_tree().paused:
		get_tree().paused = false
	# PauseMenu is a CanvasLayer, not a Control — searching for Control finds nothing and the
	# overlay sits across every saved frame.
	if _pause_panel == null:
		for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
			var s: Script = n.get_script()
			if s != null and String(s.resource_path).ends_with("pause_menu.gd"):
				_pause_panel = n.get("panel") as Control
				break
	if _pause_panel and _pause_panel.visible:
		_pause_panel.visible = false

# ------------------------------------------------------------------ photography

## Five angles per subject. `near`/`wide` frame it; `boots` is the ground-truth view — camera
## AT the subject's base, aimed dead level, so whatever it stands on runs as a straight line
## through its feet; `pool` looks DOWN at the plating beside it, which is where a cast light
## either exists or does not.
func _shots(tag: String, aim: Vector3, near_d: float = 2.0, wide_d: float = 4.5) -> void:
	for view in [["near", near_d, 0.45, Vector3(0.72, 0, 0.7), false],
			["wide", wide_d, 1.4, Vector3(0.72, 0, 0.7), false],
			["profile", near_d, 0.15, Vector3(-0.85, 0, 0.5), false],
			["boots", wide_d * 0.6, -0.02, Vector3(0.7, 0, -0.72), true],
			["pool", near_d * 1.2, 2.0, Vector3(-0.3, 0, -0.95), false]]:
		var back: Vector3 = (view[3] as Vector3).normalized() * float(view[1])
		var lift := Vector3(0, float(view[2]), 0)
		_cam.global_position = aim + back + lift
		_cam.look_at(aim + (lift if bool(view[4]) else Vector3.ZERO), Vector3.UP)
		await get_tree().create_timer(0.35).timeout
		var f := "%s/%s_%s.png" % [_out, tag, view[0]]
		get_viewport().get_texture().get_image().save_png(f)
		print("shot: ", f)

# ------------------------------------------------------------------ measurement

func _snail_report(tag: String, s: Node3D) -> void:
	var lamp: OmniLight3D = null
	for c in s.get_children():
		if c is OmniLight3D:
			lamp = c
	var vein: float = 0.0
	var col := Color(0, 0, 0)
	for n in _meshes(s):
		var mi: MeshInstance3D = n
		for si in range(mi.mesh.get_surface_count()):
			var sm := mi.get_surface_override_material(si) as ShaderMaterial
			if sm == null:
				continue
			var v = sm.get_shader_parameter("vein_energy")
			if v != null:
				vein = maxf(vein, float(v))
				col = sm.get_shader_parameter("vein_color")
	print("[snail %-13s] pos=(%.2f,%.2f,%.2f) visible=%s vein_energy=%.3f light=%.3f vein_rgb=(%.2f,%.2f,%.2f)"
		% [tag, s.global_position.x, s.global_position.y, s.global_position.z, str(s.visible),
			vein, lamp.light_energy if lamp else -1.0, col.r, col.g, col.b])

func _bird_report(i: int, g: Node3D) -> void:
	var acc: AABB = _world_aabb(g)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var c: Vector3 = acc.get_center()
	var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, acc.position.y + 0.05, c.z),
		Vector3(c.x, acc.position.y - 6.0, c.z))
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_areas = false
	q.exclude = _skip
	var hit: Dictionary = space.intersect_ray(q)
	var fy: float = hit["position"].y if not hit.is_empty() else NAN
	print("[gull #%d] perch=(%.2f,%.3f,%.2f) feet=%.4f crown=%.4f floor=%.4f (%s) clearance=%+.1fmm  wall=%.2fm"
		% [i, g.get("_perch").x, g.get("_perch").y, g.get("_perch").z,
			acc.position.y, acc.position.y + acc.size.y, fy,
			_name_of(hit["collider"]) if not hit.is_empty() else "<none>",
			(acc.position.y - fy) * 1000.0, _open_air(c)])

func _seal_report(i: int, s: Node3D) -> void:
	var acc: AABB = _world_aabb(s)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var c: Vector3 = acc.get_center()
	# Start the ray well ABOVE the body: from just under the belly it begins inside the slab
	# the animal is resting on and a box collider does not answer a ray fired from inside it.
	var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, acc.position.y + 2.0, c.z),
		Vector3(c.x, acc.position.y - 8.0, c.z))
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_areas = false
	q.exclude = _skip
	var hit: Dictionary = space.intersect_ray(q)
	var fy: float = hit["position"].y if not hit.is_empty() else NAN
	# The real test: does the ANIMAL'S OWN VOLUME hit anything? A point probe under the
	# belly says "clear" for a seal with a pipe through its shoulder. The box is lifted 40 mm
	# off the body's underside so RESTING on a shelf is not reported as clipping through it —
	# only something reaching into the animal counts.
	var sp := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(acc.size.x * 0.92, maxf(acc.size.y - 0.04, 0.05), acc.size.z * 0.92)
	sp.shape = box
	sp.transform = Transform3D(Basis(), Vector3(c.x, c.y + 0.04, c.z))
	sp.collision_mask = 0xFFFFFFFF
	sp.collide_with_areas = false
	sp.exclude = _skip
	var block: String = ""
	for h in space.intersect_shape(sp, 8):
		block += _name_of(h["collider"]) + " "
	var haul: Vector3 = s.get("_haul")
	print("[seal #%d] haul=(%.2f,%.3f,%.2f) timer=%.1f dist=%.2f" % [i, haul.x, haul.y, haul.z,
		float(s.get("_haul_timer")), s.global_position.distance_to(haul)])
	print("[seal #%d] pos=(%.2f,%.3f,%.2f) hauled=%s size=(%.2f,%.2f,%.2f) belly=%.4f floor=%.4f (%s) clearance=%+.1fmm  body=%s"
		% [i, s.global_position.x, s.global_position.y, s.global_position.z, str(s.get("_hauled")),
			acc.size.x, acc.size.y, acc.size.z, acc.position.y, fy,
			_name_of(hit["collider"]) if not hit.is_empty() else "<none>",
			(acc.position.y - fy) * 1000.0, "CLEAR" if block == "" else ("HITS " + block)])

## Can a player standing on the shelf actually PET it? A well-seated animal in an unreachable
## spot is still a bug, and "befriendable" is the whole point of this species. Stands where
## the walk from the Pontoon Ladder puts you, at eye height, and fires the same kind of ray
## the InteractionRay does — the FaunaTouch body has to be the FIRST thing hit.
func _reach_check(s: Node3D) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var verbs: Array = []
	for c in s.get_children():
		if c.has_method("available_verbs"):
			verbs = c.call("available_verbs")
	for stand in [Vector3(5.2, 0.95, -12.0), Vector3(3.0, 0.95, -13.8), Vector3(1.0, 0.95, -12.0)]:
		var eye: Vector3 = stand + Vector3(0, 1.6, 0)
		var q := PhysicsRayQueryParameters3D.create(eye, s.global_position + Vector3(0, 0.3, 0))
		q.collision_mask = 0xFFFFFFFF
		q.collide_with_areas = false
		var hit: Dictionary = space.intersect_ray(q)
		var who: String = _name_of(hit["collider"]) if not hit.is_empty() else "<nothing>"
		var touch: bool = not hit.is_empty() and (hit["collider"] as Node).has_method("available_verbs")
		print("[reach] from (%.1f,%.1f) d=%.2fm  first hit: %s  %s"
			% [stand.x, stand.z, eye.distance_to(s.global_position), who,
				"TOUCHABLE" if touch else "*** BLOCKED ***"])
	print("[reach] verbs offered while hauled: %s" % str(verbs))

# ------------------------------------------------------------------ plumbing

func _phase(p: int) -> void:
	GameClock.force_phase(p)

func _fauna_root() -> Node:
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var s: Script = n.get_script()
		if s != null and String(s.resource_path).ends_with("bloom_fauna.gd"):
			return n
	return null

## Species instances identified by a property only that class declares — inner classes all
## report the same script path, so the property IS the type test.
func _with_prop(prop: String) -> Array:
	var out: Array = []
	var root: Node = _fauna_root()
	if root == null:
		return out
	for c in root.get_children():
		if c is Node3D and c.get(prop) != null:
			out.append(c)
	return out

func _pick(nodes: Array, near: Vector3) -> Node3D:
	var best: Node3D = null
	var bd: float = 1e9
	for n in nodes:
		var d: float = (n as Node3D).global_position.distance_to(near)
		if d < bd:
			bd = d
			best = n
	return best

func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out

func _world_aabb(n: Node) -> AABB:
	var acc := AABB()
	var first := true
	for m in _meshes(n):
		var mi: MeshInstance3D = m
		if not mi.visible:
			continue
		var w: AABB = mi.global_transform * mi.get_aabb()
		acc = w if first else acc.merge(w)
		first = false
	return acc

func _open_air(from: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var near: float = 6.0
	for i in range(8):
		var a: float = TAU * i / 8.0
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(cos(a), 0, sin(a)) * 6.0)
		q.collision_mask = 0xFFFFFFFF
		q.collide_with_areas = false
		q.exclude = _skip
		var h: Dictionary = space.intersect_ray(q)
		if not h.is_empty():
			near = minf(near, from.distance_to(h["position"]))
	return near

func _name_of(c: Object) -> String:
	var n: Node = c as Node
	if n == null:
		return "<null>"
	var parts: Array[String] = [n.name]
	var p: Node = n.get_parent()
	for i in range(2):
		if p == null:
			break
		parts.push_front(p.name)
		p = p.get_parent()
	return "/".join(parts)
