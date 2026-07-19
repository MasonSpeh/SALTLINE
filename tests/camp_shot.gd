extends Node3D
## CAMP SHOT — visual proof for the base-building pass. Boots the real Main scene,
## lays out an actual camp on the wet deck the way a player would (Structures.build,
## grounded on the real floor, ComfortFurniture attaching for real), then photographs
## it at night and by day. Also captures every new kit at least once, a stripped
## salvage prop, and the bench UI with the expanded recipe tree.
##
## Saves /tmp/ws_camp_*.png. The night camp shot is the one that matters: if that does
## not read as somewhere a person lives, the pass has not landed regardless of tests.

const STRUCTURES := preload("res://scripts/world/structures.gd")
const BENCH_PANEL := preload("res://scripts/ui/bench_panel.gd")

var _cam: Camera3D
var _main: Node3D
var _player: Node3D

## A camp, laid out like somewhere someone chose to sleep: fire and chair facing each
## other, bed tucked behind the windbreak, light overhead, work and stores to one side.
## Offsets are relative to a camp centre SCOUTED at runtime — hardcoded wet-deck
## coordinates put the first version of this shot inside a machinery space, with the
## whole camp jammed against a concrete wall and nine of the eleven kits out of frame.
const CAMP := [
	["bedroll_kit", Vector3(-1.8, 0, -0.6), 90.0],
	["brazier_kit", Vector3(0.4, 0, -0.6), 0.0],
	["chair_kit", Vector3(1.6, 0, 0.6), -135.0],
	["lamp_post_kit", Vector3(-0.1, 0, -2.6), 0.0],
	["rug_kit", Vector3(0.3, 0, 0.4), 0.0],
	["windbreak_kit", Vector3(-2.6, 0, 1.0), 0.0],
	["locker_kit", Vector3(-2.4, 0, -2.4), 45.0],
	["workbench_kit", Vector3(2.2, 0, -2.2), -90.0],
	["drying_rack_kit", Vector3(2.4, 0, 2.2), 0.0],
	["rain_catcher_kit", Vector3(-3.4, 0, -1.6), 0.0],
	["planter_kit", Vector3(-3.6, 0, 1.8), 0.0],
]

## The kits the camp doesn't include, shot separately so every one of the eighteen
## is seen at least once. Also centre-relative.
const SOLO := [
	["walkway_kit", Vector3(5.2, 0, 1.2), 0.0],
	["wall_panel_kit", Vector3(6.4, 0, -0.4), 0.0],
	["barricade_kit", Vector3(5.2, 0, -1.8), 0.0],
	["leanto_kit", Vector3(7.2, 0, 2.0), 0.0],
	["bloom_lamp_kit", Vector3(7.2, 0, -1.8), 0.0],
	["drop_net_kit", Vector3(4.4, 0, -3.4), 0.0],
]

## Where to hunt for a camp site, and what "open" has to mean.
const SCOUT_MIN := Vector2(-6.0, -24.0)
const SCOUT_MAX := Vector2(24.0, -4.0)
const SCOUT_STEP: float = 1.0
const DECK_Y_LO: float = 1.4
const DECK_Y_HI: float = 3.2
const OPEN_RADIUS: float = 5.0    ## how much clear deck a camp + its solo row needs
const HEADROOM: float = 5.0       ## sky, or at least a high roof, straight up

var _centre: Vector3 = Vector3(13.0, 2.0, -14.0)

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(2.5).timeout
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.set_physics_process(false)
		_player.set_process(false)
		_player.global_position = Vector3(13.0, 3.0, -14.0)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true

	_centre = _scout()
	print("camp centre: ", _centre)
	if _player:
		_player.global_position = _centre + Vector3(0, 1.0, 0)
	for row in CAMP:
		_drop(row[0], _centre + (row[1] as Vector3), row[2])
	for row in SOLO:
		_drop(row[0], _centre + (row[1] as Vector3), row[2])
	# Let ComfortFurniture attach and light the fire, so the night shot has a fire in it.
	await get_tree().create_timer(2.5).timeout
	_light_the_fire()
	await get_tree().create_timer(1.0).timeout

	# Camera framings, also centre-relative: eye offset, aim offset, fov.
	var C := _centre
	# Which way to shoot the camp from. Fixed offsets put a bulkhead across half the
	# night frame — the site is chosen for the camp, so the lens has to be chosen for
	# the site. Pick the compass bearing that can actually see the most furniture.
	var wide: Vector3 = _best_eye(C, 6.2, 2.7)
	var low: Vector3 = _best_eye(C, 4.4, 1.6)
	print("framing: wide eye %s   low eye %s" % [wide, low])

	# --- night: the shot the whole pass is for ---
	GameClock.force_phase(GameClock.Phase.NIGHT)
	await get_tree().create_timer(1.2).timeout
	await _shot("camp_night", wide, C + Vector3(-0.4, 0.5, -0.6), 62.0)
	await _shot("camp_night_low", low, C + Vector3(-0.8, 0.5, -0.8), 55.0)
	await _shot("camp_night_bed", C + Vector3(1.0, 1.4, 2.0), C + Vector3(-1.8, 0.3, -0.6), 50.0)

	# --- day: read the geometry honestly, no light hiding the joins ---
	GameClock.force_phase(GameClock.Phase.DAY)
	await get_tree().create_timer(1.2).timeout
	await _shot("camp_day", wide + Vector3(0, 0.2, 0), C + Vector3(-0.4, 0.5, -0.6), 62.0)
	await _shot("camp_day_work", C + Vector3(5.0, 1.9, -0.4), C + Vector3(2.2, 0.6, -2.0), 55.0)
	await _shot("camp_day_util", C + Vector3(-6.2, 1.9, -0.2), C + Vector3(-3.4, 0.6, -0.4), 60.0)
	await _shot("solo_kits", C + Vector3(9.6, 2.8, 3.4), C + Vector3(5.8, 0.5, -0.6), 66.0)
	await _shot("solo_kits_b", C + Vector3(2.8, 2.2, -4.8), C + Vector3(6.4, 0.6, -0.8), 60.0)

	await _shot_salvaged()
	await _shot_bench()

	print("camp shots done")
	get_tree().quit()

## Find real open deck: flat floor at wet-deck height, sky (or high roof) overhead,
## and OPEN_RADIUS of unobstructed deck all round including the solo row to the east.
func _scout() -> Vector3:
	var best: Vector3 = Vector3(13.0, 2.0, -14.0)
	var best_score: float = -1.0
	var x: float = SCOUT_MIN.x
	while x <= SCOUT_MAX.x:
		var z: float = SCOUT_MIN.y
		while z <= SCOUT_MAX.y:
			var s: float = _score(x, z)
			if s > best_score:
				best_score = s
				var y: float = _floor_y(x, z)
				best = Vector3(x, y, z)
			z += SCOUT_STEP
		x += SCOUT_STEP
	print("scout: best score %.2f" % best_score)
	return best

func _floor_y(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 6.0, z), Vector3(x, -2.0, z))
	var hit: Dictionary = get_viewport().world_3d.direct_space_state.intersect_ray(q)
	return float(hit["position"].y) if hit.has("position") else -99.0

## Score the site by the layout we are ACTUALLY going to put there — every kit and the
## whole solo row must land on level deck. Scoring generic "openness" instead sent the
## first version of this to the seaward edge, where half the camp hung over the water
## and a caisson filled the frame.
func _score(x: float, z: float) -> float:
	var y: float = _floor_y(x, z)
	if y < DECK_Y_LO or y > DECK_Y_HI:
		return -1.0
	var space := get_viewport().world_3d.direct_space_state
	# Headroom: a camp you cannot see the sky from photographs as a cupboard.
	var up := PhysicsRayQueryParameters3D.create(
		Vector3(x, y + 0.3, z), Vector3(x, y + HEADROOM, z))
	if space.intersect_ray(up).has("position"):
		return -1.0
	# Every kit must land on level deck. Both rows are near-mandatory: a camp with
	# half its furniture hanging over the sea is not a camp.
	var score: float = 0.0
	for row in CAMP:
		var o: Vector3 = row[1]
		score += 1.0 if absf(_floor_y(x + o.x, z + o.z) - y) <= 0.3 else -6.0
		var probe := PhysicsRayQueryParameters3D.create(
			Vector3(x + o.x, y + 0.9, z + o.z), Vector3(x + o.x, y + 0.9, z + o.z) + Vector3(0.6, 0, 0))
		if space.intersect_ray(probe).has("position"):
			score -= 0.6
	for row in SOLO:
		var o2: Vector3 = row[1]
		score += 0.8 if absf(_floor_y(x + o2.x, z + o2.z) - y) <= 0.3 else -4.0
	# Elbow room, measured as DECK CONTINUITY — is there still floor out there?
	#
	# This used to reward rays that hit NOTHING, which made the open sea score higher
	# than any real deck: at the seaward edge all sixteen probes fly off into empty air
	# and collect full marks. The scout duly picked the rig's outer lip, put the solo
	# row over the water and the camera inside a caisson. What "room to breathe" really
	# means is deck you could walk on, so sample the floor instead of the air, and let
	# a missing floor cost what falling off it would.
	for i in range(16):
		var a: float = TAU * float(i) / 16.0
		var dir := Vector3(cos(a), 0, sin(a))
		for r: float in [OPEN_RADIUS * 0.5, OPEN_RADIUS]:
			var p: Vector3 = Vector3(x, y, z) + dir * r
			var fy: float = _floor_y(p.x, p.z)
			if fy < DECK_Y_LO - 1.0:
				score -= 0.9         # no deck at all out there: the edge, or the sea
			elif absf(fy - y) <= 0.4:
				score += 0.35        # continuous walkable deck
	# Not boxed into a corner: the camp needs air at eye height, not a wall in its face.
	var walls: int = 0
	for i in range(12):
		var a2: float = TAU * float(i) / 12.0
		var q2 := PhysicsRayQueryParameters3D.create(Vector3(x, y + 1.5, z),
			Vector3(x, y + 1.5, z) + Vector3(cos(a2), 0, sin(a2)) * 4.0)
		if space.intersect_ray(q2).has("position"):
			walls += 1
	score -= 1.6 * float(walls)
	# THE SHOT HAS TO SEE THE CAMP. Deck continuity alone picked a site with a concrete
	# bulkhead standing through the middle of it: every kit landed on good level plate,
	# and the camera photographed the wall. Standing on deck is not the requirement —
	# clear line of sight from each camera standpoint to the camp is, so score that
	# directly and let a blocked view cost more than anything else can earn back.
	for eye: Vector3 in [Vector3(4.6, 2.8, 4.2), Vector3(-6.2, 1.9, -0.2), Vector3(11.0, 2.8, 3.4)]:
		if absf(_floor_y(x + eye.x, z + eye.z) - y) > 0.5:
			score -= 3.0
		var from: Vector3 = Vector3(x + eye.x, y + eye.y, z + eye.z)
		# sample the camp itself, not just its centre — a pillar between the lens and the
		# bedroll ruins the frame even when the middle of the camp is visible
		for probe: Vector3 in [Vector3(0, 0.5, 0), Vector3(-1.8, 0.4, -0.6), Vector3(1.6, 0.5, 0.6)]:
			var q3 := PhysicsRayQueryParameters3D.create(from,
				Vector3(x, y, z) + probe)
			if space.intersect_ray(q3).has("position"):
				score -= 4.0
	return score

## Choose a camera standpoint by what it can SEE, not by a hardcoded compass bearing.
##
## The camp is dropped wherever the site scout found room, so a fixed eye offset is a
## guess about a location that was not known when it was written — and it guessed into
## a bulkhead, which took the left half of the night frame as a flat grey slab. Sweep
## the ring at `radius`, raycast from each candidate to every kit in the camp, and keep
## the bearing that sees the most of them (ties broken by standing on level deck).
func _best_eye(c: Vector3, radius: float, height: float) -> Vector3:
	var space := get_viewport().world_3d.direct_space_state
	var best: Vector3 = c + Vector3(radius * 0.72, height, radius * 0.72)
	var best_score: float = -1.0e9
	for i in range(24):
		var a: float = TAU * float(i) / 24.0
		var eye: Vector3 = c + Vector3(cos(a) * radius, height, sin(a) * radius)
		# The lens must not be buried inside geometry, and wants deck under it.
		var fy: float = _floor_y(eye.x, eye.z)
		var score: float = 0.0
		if fy < DECK_Y_LO - 1.0:
			score -= 6.0                      # standing off the edge / over the sea
		elif absf(fy - c.y) <= 0.6:
			score += 2.0
		if eye.y - fy < 0.4:
			score -= 8.0                      # eye is inside the floor or a solid
		var seen: int = 0
		for row in CAMP:
			var o: Vector3 = row[1]
			var target: Vector3 = c + Vector3(o.x, 0.45, o.z)
			var q := PhysicsRayQueryParameters3D.create(eye, target)
			var h: Dictionary = space.intersect_ray(q)
			# A hit very near the target IS the furniture — that counts as seeing it.
			if not h.has("position") or (Vector3(h["position"]) - target).length() < 0.55:
				seen += 1
		score += float(seen)
		if score > best_score:
			best_score = score
			best = eye
	return best

## Put a structure on the real deck: build it, drop it, then raycast the floor under
## it so it stands ON the plate instead of hovering above or sunk into it.
func _drop(kit: String, at: Vector3, yaw_deg: float) -> Node3D:
	var n: Node3D = STRUCTURES.build(kit, false)
	_main.add_child(n)
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(at.x, 6.0, at.z), Vector3(at.x, -2.0, at.z))
	var hit: Dictionary = space.intersect_ray(q)
	var pos: Vector3 = at
	var y: float = 2.0
	if hit.has("position"):
		y = float(hit["position"].y)
	else:
		# No deck here. Parking it at y=2.0 anyway is how the lean-to ended up standing
		# in mid-air over open water with one leg on the plate. Walk inward toward the
		# camp centre until there is real floor to stand it on.
		var found: bool = false
		for step in range(1, 9):
			var t: float = float(step) / 9.0
			var p: Vector3 = at.lerp(_centre, t)
			var fy: float = _floor_y(p.x, p.z)
			if fy > DECK_Y_LO - 1.0:
				pos = Vector3(p.x, fy, p.z)
				y = fy
				found = true
				print("  %s: no deck at (%.1f, %.1f) — moved inboard to (%.1f, %.1f)"
					% [kit, at.x, at.z, p.x, p.z])
				break
		if not found:
			print("  WARN %s: no deck anywhere between (%.1f, %.1f) and the camp"
				% [kit, at.x, at.z])
	n.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(pos.x, y, pos.z))
	return n

func _light_the_fire() -> void:
	for m in get_tree().get_nodes_in_group("comfort_furniture"):
		if String(m.get_meta("kind", "")) != "fire":
			continue
		for c in (m as Node).get_children():
			if c is Interactable:
				PlayerState.add_item("driftwood")
				(c as Interactable).interact("LIGHT", _player)
				print("  lit the brazier: ", c.get("lit"))

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

## This harness runs WINDOWED (gl_compatibility renders nothing headless), so the run
## sits behind whatever else is on screen and the game's own focus-loss handler opens
## the pause menu over the top of it. That is not cosmetic: a paused tree also freezes
## the SceneTreeTimers this function awaits, so the phase change never settles and the
## night shot comes back as a black frame with a PAUSED panel across it. Clear it
## immediately before the capture, every time.
func _unpause() -> void:
	get_tree().paused = false
	for n in get_tree().get_nodes_in_group("pause_menu"):
		if n is CanvasItem:
			(n as CanvasItem).visible = false
	# The menu is not always grouped — find it by script and shut it off by name too.
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		var s: Script = cur.get_script()
		if s != null and String(s.resource_path).contains("pause_menu") and cur is CanvasItem:
			(cur as CanvasItem).visible = false

## A prop that has actually been taken apart — proof the world remembers.
func _shot_salvaged() -> void:
	# Manufactured yields mean a PropLib model that gets visibly taken apart. A natural
	# node (a snagged float, a tar seam) just vanishes an object and proves nothing about
	# the stripped state, so try the real props first and only fall back to the rest.
	const MADE := ["steel_plate", "pipe_length", "wire_spool", "bolt_handful",
		"glass_pane", "copper_coil", "ceramic_shard", "rubber_hose"]
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

	var target: Node3D = null
	for s in ordered:
		# A harvest node regrows and looks identical afterwards — it proves nothing about
		# the stripped state. Only a real prop keeps standing with its parts pulled off.
		if float(s.get("regrow_sec")) > 0.0:
			continue
		var req = s.get("required_tools")
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
			target = s as Node3D
			break
	if target == null:
		print("  no prop could be stripped for the salvage shot")
		return
	print("  stripped: %s" % target.get("display_name"))
	var o: Vector3 = target.global_position
	await _shot("salvaged_prop", o + Vector3(1.1, 0.8, 1.1), o + Vector3(0, 0.15, 0), 42.0)

## The bench, with a real pack behind it, so the recipe list is shot at full length.
func _shot_bench() -> void:
	var panel: Control = BENCH_PANEL.new()
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(panel)
	await get_tree().process_frame
	panel.visible = true
	# BenchPanel._ready sets position (-310, -283) because the HUD parents it to a
	# centre-anchored node. Parented anywhere else that puts it off the top-left corner,
	# which is how the first version of this shot photographed four stray buttons.
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	panel.position = (vp - panel.custom_minimum_size) * 0.5
	# Stock a believable mid-game pack so the hint tree has something to say.
	for id in ["steel_plate", "canvas_scrap", "rope", "kelp_fiber", "driftwood",
			"pipe_length", "wire_spool", "bolt_handful", "hacksaw", "hammer_tool"]:
		PlayerState.add_item(id)
	panel.call("lay_item", "canvas_scrap")
	panel.call("refresh")
	_unpause()
	await get_tree().create_timer(0.8).timeout
	_unpause()
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/ws_bench_ui.png")
	print("shot: bench_ui")
	panel.call("return_all")
	layer.queue_free()
