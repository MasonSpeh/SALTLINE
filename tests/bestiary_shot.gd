extends Node3D
## Bestiary contact sheet: loads each generated creature mesh with its motion shader on a
## neutral stage and photographs it, so the meshes + shader can be judged without hunting
## the animals down in-world. Saves /tmp/bs_<slug>.png.

const ANIM := preload("res://scripts/world/creature_anim.gd")

# slug, target size (m), shader mode, amp, rate, glow energy, [glow colour], [opacity]
const SUBJECTS := [
	["giant_crab", 1.1, 4, 0.045, 1.4, 0.0],   # naturalistic — no glow
	["lamplight_crab", 0.9, 0, 0.012, 1.2, 1.4],
	["ultra_hammerhead", 5.0, 0, 0.09, 1.1, 0.5],
	["epic_four_eyed_whale", 14.0, 0, 0.22, 0.28, 1.2],
	["harbor_seal", 1.8, 0, 0.05, 1.0, 0.4],
	["mantle_ray", 6.0, 1, 0.14, 0.45, 0.7],
	["corvid_gull", 0.55, 3, 0.05, 1.0, 0.35],
	["lamp_eel", 4.5, 0, 0.14, 1.6, 1.0],
	["jelly_drifter", 1.1, 2, 0.08, 0.6, 1.0],
	# Small fauna
	["sea_gull", 0.55, 3, 0.06, 1.4, 0.12],
	["bait_fish", 0.24, 0, 0.13, 2.6, 0.15],
	["tide_worm", 0.32, 0, 0.07, 1.1, 0.45],
	["glow_worm", 0.26, 0, 0.06, 0.9, 1.6],
	["barnacle_cluster", 0.8, 2, 0.01, 0.5, 0.5],
	# The four gastropods
	["lamp_snail", 0.9, 0, 0.015, 0.5, 1.2],
	["rust_snail", 0.62, 0, 0.02, 0.7, 0.55, Color(1.0, 0.55, 0.18)],  # amber, not teal
	["glass_snail", 0.5, 0, 0.02, 0.6, 1.4, Color(0.25, 0.95, 0.88), 0.35],  # see-through shell
	["anchor_limpet", 0.6, 2, 0.015, 0.35, 1.0],
]

var _cam: Camera3D

func _ready() -> void:
	# Neutral studio: dim key + fill so the PBR and the rim glow both read.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.08, 0.10)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.42, 0.5)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	for spec in [[Vector3(3, 4, 3), 1.6], [Vector3(-4, 2, -2), 0.7]]:
		var l := DirectionalLight3D.new()
		add_child(l)
		l.position = spec[0]
		l.light_energy = spec[1]
		l.look_at(Vector3.ZERO, Vector3.UP)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true

	for s in SUBJECTS:
		await _shoot(s)
	get_tree().quit()

## Centre of the model's combined world-space bounds — glTF pivots are rarely centred.
func _centre(root: Node3D) -> Vector3:
	var acc := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var world: AABB = mi.global_transform * mi.get_aabb()
		acc = world if first else acc.merge(world)
		first = false
	return acc.get_center() if not first else Vector3.ZERO

func _shoot(spec: Array) -> void:
	var slug: String = spec[0]
	var size: float = spec[1]
	var path := "res://assets/models/fauna/%s/%s.glb" % [slug, slug]
	var host := Node3D.new()
	add_child(host)
	# Most of the bestiary glows Bloom-teal; a species can override (the rust snail is amber).
	var glow: Color = spec[6] if spec.size() > 6 else Color(0.25, 0.95, 0.88)
	var opacity: float = spec[7] if spec.size() > 7 else 1.0
	var gen: Dictionary = ANIM.attach(host, path, size, spec[2], spec[3], spec[4], glow,
		0.0, opacity)
	if gen.is_empty():
		print("MISSING: ", slug)
		host.queue_free()
		return
	ANIM.drive(gen["mats"], spec[4], spec[5])
	# Frame it: three-quarter view, distance scaled to the subject.
	var d: float = size * 0.75 + 0.25
	_cam.position = Vector3(d * 0.8, d * 0.45, d * 0.9)
	var focus: Vector3 = _centre(host)
	_cam.position += focus
	_cam.look_at(focus, Vector3.UP)
	await get_tree().create_timer(0.7).timeout        # let the shader tick + textures land
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/bs_%s.png" % slug)
	print("saved /tmp/bs_%s.png  (%.1fm)" % [slug, size])
	host.queue_free()
	await get_tree().process_frame
