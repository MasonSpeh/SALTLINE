extends Node3D
## Orientation diagnostic: photographs every generated model from a fixed SIDE view
## (camera on +X looking at the model centre) so authored facing can be read off the
## image: head pointing screen-RIGHT = faces -Z (Godot forward, correct); screen-LEFT =
## faces +Z (will move backwards); toward/away from camera = authored along ±X.
## Saves /tmp/face_<slug>.png. Raw meshes, no motion shader — pose only.

const SLUGS := [
	"ultra_hammerhead", "epic_four_eyed_whale", "mantle_ray", "herring_gull",
	"lamp_eel", "sea_gull", "tide_worm", "lamp_snail", "rust_snail", "glass_snail",
	"jelly_drifter", "barnacle_cluster", "anchor_limpet", "glow_worm",
	"harbor_seal", "bait_fish", "lamplight_crab", "giant_crab",   # post-regen
	"glow_kelp", "glow_creeper", "bloom_anemone",           # flora
	# s15 (2026-07-26): the new fish-table species. Every one of these was checked
	# through this harness before it was called done — the ray in particular, because
	# the mantle_ray taught us Meshy likes to author a flat fish standing on its tail.
	"fish_bilge_blenny", "fish_tallow_pollock", "fish_gannet_mackerel",
	"fish_rust_wrasse", "fish_kelp_pipefish", "fish_squall_garfish",
	"fish_lantern_dogfish", "fish_anchor_ray",
	"pyramid_snail",   # s20 (2026-07-29): first real mesh installed for this species
]
const ANIM := preload("res://scripts/world/creature_anim.gd")
var _cam: Camera3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.09, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_energy = 1.1
	env.environment = e
	add_child(env)
	var l := DirectionalLight3D.new()
	add_child(l)
	l.position = Vector3(4, 5, 2)
	l.light_energy = 1.4
	l.look_at(Vector3.ZERO, Vector3.UP)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	for s in SLUGS:
		await _shoot(s)
	get_tree().quit()

func _shoot(slug: String) -> void:
	var path := "res://assets/models/fauna/%s/%s.glb" % [slug, slug]
	var model := ANIM.load_model(path, 2.0)   # uniform size: comparing pose, not scale
	if model == null:
		print("absent: ", slug)
		return
	var host := Node3D.new()
	add_child(host)
	host.add_child(model)
	var acc := AABB()
	var first := true
	for n in host.find_children("*", "MeshInstance3D", true, false):
		var w: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb()
		acc = w if first else acc.merge(w)
		first = false
	var f: Vector3 = acc.get_center()
	_cam.position = f + Vector3(3.2, 0.55, 0.0)   # pure side view from +X
	_cam.look_at(f, Vector3.UP)
	await get_tree().create_timer(0.35).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/face_%s.png" % slug)
	print("face: ", slug)
	host.queue_free()
	await get_tree().process_frame
