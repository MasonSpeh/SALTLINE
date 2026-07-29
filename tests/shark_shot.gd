extends Node3D
## THE HAMMERHEAD IN THE WATER, at real scale, against something that has a known size.
##
## The rig's caisson legs are 6.00 m square concrete columns (rig_builder._build_structure:
## Vector3(6, 109, 6) at x +/-22, z +/-12) running from the deck to the seabed. Nothing else
## in the world is that unambiguously measurable, so the shark's patrol is moved onto one
## and photographed against it: a 6 m ruler standing in frame beats any amount of arguing
## about whether an animal "looks big".
##
## Also the load-bearing run for the per-frame `Vector3 cannot be normalized` spam, because
## that only appears once the real world's fauna are ticking against real geometry. It just
## boots the world and lets it run; the counting happens on stderr outside.
##
##   godot --path . res://tests/SharkShot.tscn            (windowed: headless cannot render)
##   godot --headless --path . res://tests/SharkShot.tscn  (spam count only, black frames)

const LEG := Vector3(22.0, 0.0, -12.0)   ## the SE caisson leg — 6 m square, x19..25 z-15..-9
const SHOT_Y: float = -5.0               ## mid-water: under the pontoon, well above the bed
const RUN_SEC: float = 25.0              ## seconds of world time held open after the shots

var _main: Node
var _shark: Node3D
var _cam: Camera3D

func _ready() -> void:
	GameClock.force_phase(GameClock.Phase.DAY)
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	for i in range(60):
		await get_tree().physics_frame
	print("[shot] world built")
	# Keep the player out of it: a swimmer in range makes the shark charge, and this shot
	# is of the patrol cruise. Frozen and parked topside, it also leaves main.gd's
	# underwater environment alone for us to drive by hand.
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = Vector3(0.0, 60.0, 120.0)
		player.set_physics_process(false)
	_shark = _find_shark()
	if _shark == null:
		print("[shot] NO SHARK FOUND")
		get_tree().quit()
		return
	# Move its patrol ring onto the caisson so it cruises past the 6 m column.
	_shark.set("_center", LEG)
	_shark.set("_radius", 11.0)
	_shark.set("_depth", SHOT_Y)
	_shark.set("_cooldown", 9999.0)     # never leaves PATROL, whatever wanders past
	_setup_cam()
	for i in range(40):
		await get_tree().process_frame

	# --- travel vs facing, measured in the real world (cross-check of HammerheadProbe) ---
	var model: Node3D = _model_of(_shark)
	var box: AABB = _world_bounds(model) if model else AABB()
	print("[shot] shark world AABB size=%s" % str(box.size.snappedf(0.01)))
	var dots: Dictionary = await _travel_dots(model)
	for k in dots:
		print("[shot] model %s . travel = %+.4f" % [k, dots[k]])

	# --- the frames ---
	await _shot("scale", 13.0, 0.055, 1.2)
	await _shot("close", 8.0, 0.045, 0.55)
	await _shot("wide", 22.0, 0.028, 2.2)
	await _shot("clarity", 11.0, 0.012, 0.9)

	# --- hold the world open so the fauna spam (if any) accumulates on stderr ---
	var t: float = 0.0
	while t < RUN_SEC:
		t += get_process_delta_time()
		await get_tree().process_frame
	print("[shot] held %.1f s of world time" % t)
	get_tree().quit()

## One frame: stand `dist` metres off the shark on the side away from the leg, so the
## column fills the background and the animal is read against it. `haze` is the teal fog
## density (main.gd runs 0.055 at the surface to 0.17 deep); `up` lifts the eye.
func _shot(tag: String, dist: float, haze: float, up: float) -> void:
	var e: Environment = _cam.environment
	if e:
		e.fog_density = haze
	var s: Vector3 = _shark.global_position
	# Away from the leg, so leg -> shark -> camera line up.
	var out: Vector3 = (s - LEG)
	out.y = 0.0
	if out.length() < 0.5:
		out = Vector3(0.0, 0.0, -1.0)
	out = out.normalized()
	_cam.global_position = s + out * dist + Vector3(0.0, up, 0.0)
	_cam.look_at(s, Vector3.UP)
	await get_tree().create_timer(0.25).timeout
	if DisplayServer.get_name() == "headless":
		print("[shot] %s skipped — headless has no renderer (run without --headless)" % tag)
		return
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/hh_%s.png" % tag)
	print("[shot] %s -> /tmp/hh_%s.png  cam=%s shark=%s dist=%.1f luma=%.3f"
		% [tag, tag, str(_cam.global_position.snappedf(0.1)), str(s.snappedf(0.1)),
			dist, _luma(img)])

## Correlate travel with the model node's local axes over a couple of seconds.
func _travel_dots(model: Node3D) -> Dictionary:
	var names := ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]
	var axes := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN,
		Vector3.BACK, Vector3.FORWARD]
	var sums := PackedFloat32Array()
	sums.resize(6)
	var n: int = 0
	var prev: Vector3 = _shark.global_position
	for i in range(150):
		await get_tree().process_frame
		var now: Vector3 = _shark.global_position
		var d: Vector3 = now - prev
		prev = now
		if d.length() < 0.0005 or model == null:
			continue
		var t: Vector3 = d.normalized()
		var mb: Basis = model.global_transform.basis.orthonormalized()
		for a in range(6):
			sums[a] += (mb * (axes[a] as Vector3)).normalized().dot(t)
		n += 1
	var out: Dictionary = {}
	for a in range(6):
		out[names[a]] = sums[a] / float(maxi(n, 1))
	return out

func _setup_cam() -> void:
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.far = 500.0
	_cam.fov = 70.0
	# main.gd's own dive environment, so the shot is the game's water and not a lookalike.
	var env: Environment = _main.get("_underwater_env")
	_cam.environment = env.duplicate() if env else null
	_cam.current = true

func _find_shark() -> Node3D:
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var s: Script = (n as Node).get_script() as Script
		if s != null and String(s.resource_path).ends_with("shark.gd"):
			return n as Node3D
	return null

## CreatureAnim.attach() adds the generated mesh as the last child of the species node.
func _model_of(host: Node3D) -> Node3D:
	for i in range(host.get_child_count() - 1, -1, -1):
		var c: Node = host.get_child(i)
		if c is Node3D and not (c is MeshInstance3D) \
				and (c as Node3D).find_children("*", "MeshInstance3D", true, false).size() > 0:
			return c as Node3D
	return null

func _world_bounds(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		var w: AABB = mi.global_transform * mi.get_aabb()
		acc = w if first else acc.merge(w)
		first = false
	return acc

func _luma(img: Image) -> float:
	var small: Image = img.duplicate()
	small.resize(48, 27, Image.INTERPOLATE_BILINEAR)
	var sum: float = 0.0
	for y in range(small.get_height()):
		for x in range(small.get_width()):
			sum += small.get_pixel(x, y).get_luminance()
	return sum / float(small.get_width() * small.get_height())
