extends Node3D
## Deck-gull swap check (2026-07-28): boots the real Main and photographs every gull
## WHERE IT ACTUALLY STANDS, because the thing that goes wrong with a generated mesh is
## never visible on a studio turntable — it is the feet, the size against the plating, and
## which way the bird is pointing when it walks.
##
## Also MEASURES rather than eyeballs: for each bird it takes the world AABB of the gull
## surfaces, raycasts straight down from the body to the deck, and prints crown height and
## foot clearance in millimetres. This rig has a documented history of animals floating a
## few centimetres proud (SurfaceCrawler.FOOT, the snail work) and a screenshot at three
## metres will not show you 30mm.
##
## Run WINDOWED — the viewport texture is empty headless:
##   godot --path . res://tests/GullShot.tscn [out_dir]

const DEFAULT_OUT := "/private/tmp/claude-501/-Users-mjspeh-Desktop-UltraInbox/3a1fdfbb-2f00-4108-9969-13805825a6fc/scratchpad/gull"
## The spawn points bloom_fauna.gd hands the birds. Deck gulls wander off theirs, so the
## camera aims at the bird it finds nearest, not at the constant.
const DECK_HOMES := [Vector3(24.0, 2.0, -15.5), Vector3(26.5, 2.0, -19.0),
	Vector3(-3.0, 18.75, 3.5), Vector3(2.5, 18.75, 6.5)]
const PERCHES := [Vector3(24.9, 2.75, -16.0), Vector3(-8.6, 18.75, 6.4), Vector3(27.6, 18.75, 4.0)]

var _out: String = DEFAULT_OUT
var _cam: Camera3D

func _ready() -> void:
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
	await get_tree().create_timer(4.0).timeout
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player:
		player.set_physics_process(false)
		player.set_process(false)
		player.global_position = Vector3(160, 60, 160)   # far enough not to flush anything
	# Mid-DAY, not the phase's first second: DAY starts with the sun at 16 degrees and the
	# whole deck in long raking shadow, which is the one lighting where you cannot judge a
	# white bird. Winding the phase clock to its midpoint puts the sun overhead.
	GameClock.force_phase(GameClock.Phase.DAY)
	GameClock._phase_elapsed_sec = GameClock.phase_durations_minutes[GameClock.Phase.DAY] * 30.0
	await get_tree().create_timer(1.5).timeout
	var birds: Array = _find_birds()
	print("[gull] found %d gull models" % birds.size())
	for i in range(birds.size()):
		_measure(i, birds[i])
	await _walk_check(birds)
	var spots: Array = []
	for h in DECK_HOMES:
		spots.append(["deck", h])
	for p in PERCHES:
		spots.append(["perch", p])
	for i in range(spots.size()):
		var kind: String = spots[i][0]
		var aim: Vector3 = _nearest(birds, spots[i][1])
		# Eye level, a metre and a bit out — the range the player actually meets them at —
		# plus a low profile from the far side, which is the view that shows the feet
		# touching and which end of the bird is leading.
		# "boots" is the ground-truth view: camera AT foot height, two metres out, aimed
		# dead level. Whatever the bird is standing on runs across the frame as a straight
		# line through its feet — floating or sinking shows up as a gap you can count
		# pixels in, which no three-quarter hero shot will ever tell you.
		for view in [["near", 1.1, 0.35, Vector3(0.72, 0, 0.7)],
				["wide", 3.0, 1.1, Vector3(0.72, 0, 0.7)],
				["profile", 1.0, 0.12, Vector3(-0.85, 0, 0.5)],
				["boots", 2.0, -0.20, Vector3(0.7, 0, -0.72)],
				["lit", 1.2, 0.22, Vector3(-0.7, 0, -0.72)]]:   # opposite side of profile
			var back: Vector3 = (view[3] as Vector3).normalized() * float(view[1])
			_cam.global_position = aim + back + Vector3(0, float(view[2]), 0)
			# The boots view stays LEVEL — tilting it would bend the deck line it exists
			# to compare against. Every other view frames the bird.
			_cam.look_at(aim + (Vector3(0, float(view[2]), 0) if view[0] == "boots" else Vector3.ZERO),
				Vector3.UP)
			_cam.fov = 55.0
			await get_tree().create_timer(0.3).timeout
			var f := "%s/gull_%s%d_%s.png" % [_out, kind, i, view[0]]
			get_viewport().get_texture().get_image().save_png(f)
			print("shot: ", f)
	get_tree().quit()

## Every gull surface in the world, grouped by the bird it belongs to. Identified off the
## motion shader's albedo texture, so the harness needs no hook inside the species classes.
func _find_birds() -> Array:
	var by_host: Dictionary = {}
	for n in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		var hit := false
		for s in range(mi.mesh.get_surface_count()):
			var sm := mi.get_surface_override_material(s) as ShaderMaterial
			if sm == null:
				continue
			var tex := sm.get_shader_parameter("albedo_tex") as Texture2D
			if tex and tex.resource_path.contains("herring_gull"):
				hit = true
		if not hit:
			continue
		var host: Node = _root_of(mi)
		if not by_host.has(host):
			by_host[host] = []
		(by_host[host] as Array).append(mi)
	return by_host.values()

func _measure(idx: int, meshes: Array) -> void:
	var acc := AABB()
	var first := true
	for m in meshes:
		var mi: MeshInstance3D = m
		var w: AABB = mi.global_transform * mi.get_aabb()
		acc = w if first else acc.merge(w)
		first = false
	if first:
		return
	var centre: Vector3 = acc.get_center()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(centre + Vector3(0, 0.05, 0),
		centre - Vector3(0, 6.0, 0))
	# ALL layers, not just world geometry: the topside plating and the rails do not
	# necessarily answer a mask-1 probe, and a mask-1-only reading quietly reports the
	# hull box eight metres below as "the deck" — which is how a floating bird passes.
	q.collision_mask = 0xFFFFFFFF
	var hit: Dictionary = space.intersect_ray(q)
	var floor_y: float = float(hit["position"].y) if not hit.is_empty() else NAN
	var what: String = str(hit["collider"].name) if not hit.is_empty() else "<nothing>"
	print("[gull] #%d feet_y=%.4f crown_y=%.4f height=%.3fm len=%.3fm floor_y=%.4f (%s) clearance=%+.1fmm"
		% [idx, acc.position.y, acc.position.y + acc.size.y, acc.size.y,
			maxf(acc.size.x, acc.size.z), floor_y, what, (acc.position.y - floor_y) * 1000.0])

## ORIENTATION, measured. The generated meshes in this project face +Z while Godot's
## forward is -Z (creature_anim.gd), so a new model that breaks the convention walks
## backwards — and a bird strutting tail-first is exactly the sort of thing that survives
## a screenshot. Sample each bird's travel over a few seconds and dot it against the
## direction the MODEL's own nose points: +1 = leading with its bill, -1 = moon-walking.
func _walk_check(birds: Array) -> void:
	var start: Array = []
	for meshes in birds:
		start.append(_root_of((meshes as Array)[0]).global_position)
	var samples: Array = []
	for i in range(birds.size()):
		samples.append([0.0, 0.0])   # [sum of dot*dist, sum of dist]
	var last: Array = start.duplicate()
	for _step in range(40):
		await get_tree().create_timer(0.15).timeout
		for i in range(birds.size()):
			var node: Node3D = _root_of((birds[i] as Array)[0])
			var d: Vector3 = node.global_position - last[i]
			d.y = 0.0
			last[i] = node.global_position
			if d.length() < 0.002:
				continue
			var nose: Vector3 = -node.global_transform.basis.z
			nose.y = 0.0
			if nose.length() < 0.01:
				continue
			samples[i][0] += d.normalized().dot(nose.normalized()) * d.length()
			samples[i][1] += d.length()
	for i in range(birds.size()):
		if samples[i][1] < 0.01:
			print("[gull] #%d never moved — no facing verdict" % i)
			continue
		var dot: float = samples[i][0] / samples[i][1]
		print("[gull] #%d travelled %.2fm, nose-vs-travel %+.2f  %s"
			% [i, samples[i][1], dot, "FORWARD" if dot > 0.5 else ("BACKWARD" if dot < -0.5 else "sideways/turning")])

## The species node a gull surface hangs under (the DeckGull / CorvidGull itself).
func _root_of(mi: Node) -> Node3D:
	var n: Node = mi
	while n.get_parent() != null and n.get_parent().get_script() == null:
		n = n.get_parent()
	var p: Node = n.get_parent()
	return (p as Node3D) if p is Node3D else (n as Node3D)

func _nearest(birds: Array, to: Vector3) -> Vector3:
	var best: Vector3 = to
	var bd: float = 6.0
	for meshes in birds:
		var mi: MeshInstance3D = (meshes as Array)[0]
		var w: AABB = mi.global_transform * mi.get_aabb()
		var c: Vector3 = w.get_center()
		var d: float = c.distance_to(to)
		if d < bd:
			bd = d
			best = c
	return best
