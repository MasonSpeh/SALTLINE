extends Node
## Photographs the tropical reef fish among the coral — day and night in ONE launch, because
## relaunching Godot lags the owner's machine.
##
## THE VANTAGES ARE DERIVED FROM THE LIVE STATIONS, not authored. The first version of this
## file hand-typed camera positions off the caisson faces and came back with sixteen frames of
## empty coral: with 42 stations spread over 16 leg faces, a guessed vantage is far more likely
## to be looking at a bare patch than at a shoal. So it asks reef_fish.gd where its shoals
## actually are (`census()`), and frames each species from a measured offset along its own
## station's face normal. Same rule as everything else here — probe, don't guess.
##
## Flies the PLAYER rather than a free camera: underwater_fx keys its fog, colour grade and
## light off the player's own position, so a detached camera photographs the reef in air.
## Force-unpauses AND force-hides the pause PANEL every frame — the panel is a separate
## CanvasLayer from the HUD, so hiding the HUD alone left "PAUSED" pasted over a third of the
## first pass (docs/AGENT_TRAPS.md: a paused world still renders).
##
## Must run WINDOWED. --headless never draws.
##   godot --path . res://tests/ReefFishShot.tscn -- <out_dir> [--only=<substr>]
##                                                  [--day|--night] [--nocoral]
##
## --nocoral hides leg_reef's coral MultiMeshes. That is a DIAGNOSTIC, not a shot: it is the
## only way to judge the fish themselves while the reef's own emission is being retuned in a
## concurrent session.

var main: Node3D
var _dir: String = "/tmp/reef_fish"
var _only: String = ""
var _phases: Array[String] = ["day", "night"]
var _nocoral: bool = false
var _diag: bool = false
var _norange: bool = false
var _rf: Node = null
var _pause: CanvasLayer = null

## What one station's fish ACTUALLY are, off the live tree — the only honest way to tell an
## empty frame caused by bad framing from one caused by a fish that is not being drawn.
func _dump() -> void:
	var stations: Array = _rf.get("_stations")
	for st in stations:
		print("[diag] station %s centre %s out %s  root.visible=%s in_tree=%s"
			% [st["sp"]["slug"], str((st["centre"] as Vector3).snappedf(0.01)),
				str(st["out"]), st["root"].visible, (st["root"] as Node3D).is_visible_in_tree()])
		var i: int = 0
		for f in st["fish"]:
			var host: Node3D = f
			var meshes: Array = host.find_children("*", "MeshInstance3D", true, false)
			var line: String = "[diag]   fish %2d at %s  meshes=%d" % [i,
				str(host.global_position.snappedf(0.01)), meshes.size()]
			for m in meshes:
				var mi: MeshInstance3D = m
				var world: AABB = mi.global_transform * mi.get_aabb()
				line += "  | vis=%s range=%.1f worldAABB=%s scale=%.3f mat=%s" % [
					mi.is_visible_in_tree(), mi.visibility_range_end,
					str(world.size.snappedf(0.01)), mi.global_transform.basis.get_scale().x,
					"override" if mi.get_surface_override_material(0) != null else "NONE"]
			print(line)
			i += 1
			if i >= 4:
				break
		return

func _ready() -> void:
	# WITHOUT THIS THE UNPAUSE BELOW NEVER RUNS. A node inherits PROCESS_MODE_PAUSABLE, so the
	# moment the pause menu auto-pauses on focus-out this harness stops processing and can no
	# longer un-pause itself — while `create_timer` keeps ticking (it ignores pause by default),
	# so the shot list runs to completion over a frozen world. That is worse than a crash: the
	# fish stop swimming AND underwater_fx stops updating its depth grade, so the whole pass
	# came back with pale, un-fogged water and a PAUSED panel over every frame.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7).to_lower()
		elif a == "--night":
			_phases = ["night"]
		elif a == "--day":
			_phases = ["day"]
		elif a == "--nocoral":
			_nocoral = true
		elif a == "--diag":
			_diag = true
		elif a == "--norange":
			_norange = true
		elif not a.begins_with("--"):
			_dir = a
	DirAccess.make_dir_recursive_absolute(_dir)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	main = packed.instantiate() if packed != null else null
	# A parse error anywhere in the world graph hands back a bare node with its script
	# dropped: it builds nothing and photographs black water while reporting success.
	if main != null and main.get_script() == null:
		print("[fishshot] Main.tscn instantiated WITHOUT its script — aborting")
		get_tree().quit(1)
		return
	add_child(main)
	await get_tree().create_timer(14.0).timeout
	main._countdown = 0.0
	if main.hud != null:
		if main.hud.fade_rect != null:
			main.hud.fade_rect.color.a = 0.0
		main.hud.visible = false
	var p: Node3D = main.player
	p.set("_fly", true)
	(p as CollisionObject3D).set_collision_layer_value(1, false)
	(p as CollisionObject3D).set_collision_mask_value(1, false)
	# Fauna reacts to the "player" group; the startle shots put the lens back in it on purpose.
	p.remove_from_group("player")
	main.storm.set_process(false)
	_rf = _by_script(main, "reef_fish.gd")
	if _rf == null:
		print("[fishshot] no ReefFish node — nothing to photograph")
		get_tree().quit(1)
		return
	if _diag:
		_dump()
	if _norange:
		var n: int = 0
		for st in (_rf.get("_stations") as Array):
			for f in st["fish"]:
				for mi in (f as Node3D).find_children("*", "MeshInstance3D", true, false):
					(mi as MeshInstance3D).visibility_range_end = 0.0
					n += 1
		print("[fishshot] --norange: cleared visibility_range_end on %d fish meshes" % n)
	if _nocoral:
		var lr: Node = _by_script(main, "leg_reef.gd")
		if lr != null:
			for c in lr.get_children():
				var mmi := c as MultiMeshInstance3D
				if mmi != null:
					mmi.visible = false
			print("[fishshot] --nocoral: leg_reef MultiMeshes hidden")
	print("[fishshot] world up, output -> ", _dir)
	for phase in _phases:
		GameClock.force_phase(GameClock.Phase.NIGHT if phase == "night" else GameClock.Phase.DAY)
		await get_tree().create_timer(2.0).timeout
		await _shots(phase)
	print("[fishshot] done")
	get_tree().quit()

## One framed portrait per species from its own biggest station, plus wide views of the two
## depth bands and the startle pair.
func _shots(tag: String) -> void:
	_gather_kelp()
	# ONE STATION PER SPECIES, PICKED FOR A CLEAR LINE OF SIGHT. Biggest shoal is the obvious
	# criterion and on its own it is the wrong one: underwater_world stands 15 kelp strands on a
	# 3.2-6.0 m holdfast ring around every leg, growing 7-11 m up from y -12, so a shallow
	# station is inside a forest and the pass that just took the biggest shoal came back with
	# four frames of nothing but green blade. Every candidate is now scored on how many strands
	# stand between the lens and the shoal, measured off the real strand positions, and the
	# shoal size only breaks ties.
	var by_slug: Dictionary = {}
	var best_score: Dictionary = {}
	for s in _rf.call("census"):
		var slug: String = s["slug"]
		var eye_try: Vector3 = (s["centre"] as Vector3) + (s["out"] as Vector3) * _back(s)
		var score: float = float(_blockers(eye_try, s["centre"])) * 100.0 \
			- float((s["fish"] as Array).size())
		if not by_slug.has(slug) or score < float(best_score[slug]):
			by_slug[slug] = s
			best_score[slug] = score
	print("[fishshot] framing %d species from their own stations" % by_slug.size())
	for slug in by_slug.keys():
		var s: Dictionary = by_slug[slug]
		var back: float = _back(s)
		var out_ax: Vector3 = s["out"]
		var centre: Vector3 = s["centre"]
		var eye: Vector3 = centre + out_ax * back + Vector3.UP * 0.35
		var short_slug: String = String(slug).trim_prefix("trop_")
		await _look(eye, centre, "%s_%s" % [short_slug, tag])
		# ...and two obliques, so the shoal is seen against the wall rather than face-on, and so
		# a single unlucky frond cannot lose a species.
		var tan_ax: Vector3 = out_ax.cross(Vector3.UP).normalized()
		await _look(centre + out_ax * back * 0.8 + tan_ax * back * 0.85 + Vector3.UP * 0.5,
			centre, "%s_obliqueA_%s" % [short_slug, tag])
		await _look(centre + out_ax * back * 0.8 - tan_ax * back * 0.85 - Vector3.UP * 0.4,
			centre, "%s_obliqueB_%s" % [short_slug, tag])

	# --- wide views of each band, from a station's own depth but well back
	var shallow: Dictionary = by_slug.get("trop_damsel", {})
	var deep: Dictionary = by_slug.get("trop_anthias", {})
	if not shallow.is_empty():
		var c: Vector3 = shallow["centre"]
		await _look(c + (shallow["out"] as Vector3) * 5.0 + Vector3.UP * 1.0, c, "wide_shallow_" + tag)
	if not deep.is_empty():
		var c2: Vector3 = deep["centre"]
		await _look(c2 + (deep["out"] as Vector3) * 6.5, c2, "wide_band_" + tag)
		# the whole column down one leg, from above the shallow band
		await _look(Vector3(c2.x + 3.0, -6.0, c2.z), Vector3(c2.x, -17.0, c2.z), "column_" + tag)
		await _look(Vector3(c2.x + 6.0, -21.0, c2.z), Vector3(c2.x, -8.0, c2.z), "column_up_" + tag)
	# --- STARTLE: the lens rejoins the "player" group so the shoals treat it as the player.
	if not shallow.is_empty():
		await _startle(shallow, "startle_" + tag)

## How far off a shoal the lens stands. Scaled by the shoal's own range, not typed — but SHORT.
## The player's view is 107 degrees across, so a 0.3 m fish at 7 m is twenty pixels: the first
## pass framed every station from stand + 1.5*rad + 2.2 and came back with ten frames of empty
## water that in fact contained all the fish. This is the range a diver reads a reef fish from.
func _back(s: Dictionary) -> float:
	return float(s["stand"]) + float(s["rad"]) * 0.45 + 1.15

## Every kelp strand's plan position and the height it reaches, off the live tree. The strands
## carry a `sway` meta (that is how leg_reef identifies them too), so this measures the stand
## that is actually there rather than re-deriving underwater_world's spawn numbers.
var _kelp: Array = []

func _gather_kelp() -> void:
	if not _kelp.is_empty():
		return
	var uww: Node = _by_script(main, "underwater_world.gd")
	if uww == null:
		return
	for c in uww.get_children():
		var n3 := c as Node3D
		if n3 == null or not n3.has_meta("sway"):
			continue
		var top: float = n3.global_position.y
		for m in n3.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = m
			if mi.mesh != null:
				top = maxf(top, (mi.global_transform * mi.get_aabb()).end.y)
		_kelp.append([Vector2(n3.global_position.x, n3.global_position.z),
			n3.global_position.y, top])
	print("[fishshot] kelp stand: %d strands measured for occlusion scoring" % _kelp.size())

## How many kelp strands stand between the lens and the shoal. Plan-space distance from the
## strand to the sight LINE, gated on the strand actually reaching the depth being looked at —
## a holdfast 8 m below the shot blocks nothing.
const BLADE_R: float = 0.65

func _blockers(eye: Vector3, target: Vector3) -> int:
	var a := Vector2(eye.x, eye.z)
	var b := Vector2(target.x, target.z)
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	if len2 < 0.0001:
		return 0
	var n: int = 0
	for k in _kelp:
		var p: Vector2 = k[0]
		var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		var off: float = a.lerp(b, t).distance_to(p)
		# A STRAND AT THE LENS COUNTS DOUBLE, and counts at a wider radius. Distance to the
		# sight line alone is not enough: a frond 0.9 m from the camera is off the line by more
		# than BLADE_R and still fills the entire frame, which is exactly how the first scored
		# pass still handed back a wrasse portrait made of green blade.
		var near_eye: bool = p.distance_to(a) < 1.6
		if off > (BLADE_R if not near_eye else 1.6):
			continue
		# the sight line's height where the strand is; the strand has to span it
		var y: float = lerpf(eye.y, target.y, t)
		if y >= float(k[1]) - 0.5 and y <= float(k[2]) + 0.5:
			n += 2 if near_eye else 1
	return n

func _startle(s: Dictionary, name_: String) -> void:
	if _only != "" and not name_.to_lower().contains(_only):
		return
	var centre: Vector3 = s["centre"]
	var out_ax: Vector3 = s["out"]
	var eye: Vector3 = centre + out_ax * (float(s["rad"]) * 0.55 + 1.7)
	_place(eye, centre)
	await get_tree().create_timer(3.5).timeout
	await _grab(name_ + "_calm")
	main.player.add_to_group("player")
	await get_tree().create_timer(1.4).timeout
	await _grab(name_ + "_ducking")
	main.player.remove_from_group("player")
	await get_tree().create_timer(0.2).timeout

const EYE_UP: float = 1.6

## Point the player's head at a world target. Yaw/pitch are derived rather than typed —
## forward is (-sin y, 0, -cos y), and the first pass of a hand-authored list in this repo had
## every leg shot facing away from the leg.
func _place(eye: Vector3, target: Vector3) -> void:
	var p: Node3D = main.player
	p.global_position = eye - Vector3(0.0, EYE_UP, 0.0)
	var d: Vector3 = target - eye
	p.rotation.y = atan2(-d.x, -d.z)
	var flat: float = sqrt(d.x * d.x + d.z * d.z)
	p.get_node("Head").rotation.x = atan2(d.y, maxf(flat, 0.001))
	p.set("velocity", Vector3.ZERO)
	p.set("input_locked", true)

func _look(eye: Vector3, target: Vector3, name_: String) -> void:
	if _only != "" and not name_.to_lower().contains(_only):
		return
	_place(eye, target)
	# Long enough for the station to come out of its cull freeze, seat its fish and settle.
	await get_tree().create_timer(1.6).timeout
	# WHERE THE LENS ACTUALLY ENDED UP. Printed because the first pass of this harness framed
	# every deep station from ~17 m when it had asked for 7 — a shot list that reports only the
	# position it INTENDED is a shot list that cannot tell you it missed.
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		print("[fishshot]   %-24s asked %s got %s  target %.1f m  fov %.0f"
			% [name_, str(eye.snappedf(0.1)), str(cam.global_position.snappedf(0.1)),
				cam.global_position.distance_to(target), cam.fov])
	await _grab(name_)

func _grab(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/fish_%s.png" % [_dir, name_]
	print("[fishshot] saved ", path, " err=", img.save_png(path))

func _process(_d: float) -> void:
	get_tree().paused = false
	# The pause PANEL is its own CanvasLayer (layer 15), not part of the HUD — hiding the HUD
	# left "PAUSED" pasted over a third of the first pass.
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

func _by_script(root: Node, tail: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var s: Script = n.get_script()
		if s != null and String(s.resource_path).ends_with(tail):
			return n
	return null
