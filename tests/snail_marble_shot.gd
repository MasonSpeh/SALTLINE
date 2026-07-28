extends Node3D
## GASTROPOD LOOK-CHECK. Unlike BestiaryShot (which photographs the raw generated .glb),
## this stages the LIVE SPECIES CLASSES — LampSnail with its new marbled shell shader and
## PyramidSnail with its fully procedural banded ziggurat body — because on both of those
## the look is produced by the species script, not by the asset.
##
## Saves PNGs to the path in SHOT_DIR. Run:
##   godot --headless --path . res://tests/SnailMarbleShot.tscn

const SHOT_DIR := "/private/tmp/claude-501/-Users-mjspeh-Desktop-UltraInbox/3a1fdfbb-2f00-4108-9969-13805825a6fc/scratchpad"

var _cam: Camera3D

func _ready() -> void:
	get_viewport().size = Vector2i(1280, 900)
	GameClock.force_phase(GameClock.Phase.NIGHT)   # the lamp snail only lights after dark
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.07, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.34, 0.42, 0.5)
	e.ambient_light_energy = 0.75
	env.environment = e
	add_child(env)
	for spec in [[Vector3(3, 4, 3), 1.5], [Vector3(-4, 2.5, -2.5), 0.75]]:
		var l := DirectionalLight3D.new()
		add_child(l)
		l.position = spec[0]
		l.light_energy = spec[1]
		l.look_at(Vector3.ZERO, Vector3.UP)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.fov = 45.0        # long-ish lens: less perspective stretch on a 1 m animal
	_cam.current = true

	var lamp := BloomFauna.LampSnail.new(0, Vector3.ZERO)
	add_child(lamp)
	await _frames(60)
	_freeze(lamp)
	await _shoot(lamp, "lamp_snail_marble_a", 0.95, Vector3(0.85, 0.45, 0.95))
	await _shoot(lamp, "lamp_snail_marble_b", 0.9, Vector3(-0.2, 0.30, 1.0))
	# THE DIMMER, proved: the same shell with vein_energy driven to 0 is the daytime /
	# freshly-harvested state the game already depended on when it was dimming _spots.
	for m in lamp._vein_mats:
		(m as ShaderMaterial).set_shader_parameter("vein_energy", 0.0)
	await _shoot(lamp, "lamp_snail_marble_dimmed", 0.95, Vector3(0.85, 0.45, 0.95))
	lamp.queue_free()
	await _frames(4)

	var pyr := BloomFauna.PyramidSnail.new(0, Vector3.ZERO)
	add_child(pyr)
	await _frames(60)
	_freeze(pyr)
	await _shoot(pyr, "pyramid_snail_three_quarter", 1.0, Vector3(0.9, 0.42, -0.75))
	await _shoot(pyr, "pyramid_snail_side", 0.95, Vector3(1.0, 0.14, 0.05))
	await _shoot(pyr, "pyramid_snail_rear_quarter", 1.0, Vector3(0.8, 0.40, 0.95))
	await _shoot(pyr, "pyramid_snail_close_head", 0.55, Vector3(0.5, 0.28, -0.95))
	get_tree().quit()

## Stop the crawler and square the animal up to the axes. Both species assign
## global_basis every frame from the surface frame they are stuck to, so without this the
## subject is yawed onto a random heading and "side view" photographs whatever it fancied.
## Vertex-shader motion keeps running (it is on TIME), which is what we want to see.
func _freeze(subject: Node3D) -> void:
	subject.set_process(false)
	subject.global_transform = Transform3D(Basis(), Vector3.ZERO)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

## Combined world AABB of everything visible under `root` — the species build their bodies
## out of many meshes with off-centre pivots, so framing on the node origin misses.
func _bounds(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if not mi.visible:
			continue
		var world: AABB = mi.global_transform * mi.get_aabb()
		acc = world if first else acc.merge(world)
		first = false
	return acc

func _shoot(subject: Node3D, slug: String, dist_mul: float, dir: Vector3) -> void:
	var b: AABB = _bounds(subject)
	var focus: Vector3 = b.get_center()
	# Fill the frame: at fov 45 the distance that fits a sphere of diameter `span` is
	# (span/2)/tan(22.5) ~= 1.21*span, so dist_mul 1.0 is a tight, filling shot.
	var span: float = maxf(b.size.length(), 0.2)
	_cam.position = focus + dir.normalized() * span * dist_mul * 1.21
	_cam.look_at(focus, Vector3.UP)
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [SHOT_DIR, slug])
	print("saved %s/%s.png   bounds=%s" % [SHOT_DIR, slug, b])
