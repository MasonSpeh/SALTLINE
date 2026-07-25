extends Node
## PLINTH CHECK — proof that stripping the generated display stand off a fish left the fish
## intact: correct silhouette, textures still bound, nothing lopped off a fin.
##
## Meshy fuses the plinth it invents into the SAME mesh primitive and material as the
## animal, so it was removed by offline geometry surgery (welding vertices, isolating the
## connected component that sat entirely below the body, and dropping those triangles —
## see the tooling note in the batch report). A silhouette is the only way to confirm that
## worked, since a bad component pick would silently delete a fin instead.
##
## Run WINDOWED (a headless viewport captures nothing):
##   godot --path . res://tests/plinth_check.tscn
## Saves /tmp/plinth_<slug>.png, prints the model's true extents, and self-quits.

const ANIM := preload("res://scripts/world/creature_anim.gd")

## The four models that carried a baked stand. Sizes are the in-game target lengths.
const SUBJECTS := [
	["fish_herring", 0.30],
	["fish_lodestone_bream", 0.42],
	["fish_mirrorjack", 0.55],
	["fish_ribbon_eel", 0.85],
]

var _cam: Camera3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.07, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.40, 0.46, 0.54)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	for spec in [[Vector3(3, 4, 3), 1.7], [Vector3(-4, 2, -2), 0.8]]:
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

## Combined world-space bounds of every surface — glTF pivots are rarely centred.
func _bounds(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var world: AABB = mi.global_transform * mi.get_aabb()
		acc = world if first else acc.merge(world)
		first = false
	return acc

func _shoot(spec: Array) -> void:
	var slug: String = spec[0]
	var size: float = float(spec[1])
	var path := "res://assets/models/fauna/%s/%s.glb" % [slug, slug]
	var host := Node3D.new()
	add_child(host)
	var gen: Dictionary = ANIM.attach(host, path, size, ANIM.Mode.UNDULATE,
		0.05, 1.4, Color(0.25, 0.95, 0.88), 0.0)
	if gen.is_empty():
		print("MISSING: ", slug)
		host.queue_free()
		return
	var b: AABB = _bounds(host)
	# A dead-side-on view is the read that shows a stand: the plinth appears as a slab under
	# the belly and inflates the vertical extent. "Side on" means PERPENDICULAR to the body's
	# long axis, and that axis is not the same for every model — the ribbon eel runs along X
	# while the fish run along Z, so a fixed +X camera photographed the eel end-on and it read
	# as a featureless spike. Pick the short horizontal axis to stand off along.
	var d: float = size * 1.5 + 0.3
	var focus: Vector3 = b.get_center()
	var offset: Vector3 = Vector3(d, 0.0, 0.0) if b.size.z >= b.size.x else Vector3(0.0, 0.0, d)
	_cam.position = focus + offset
	_cam.look_at(focus, Vector3.UP)
	await get_tree().create_timer(0.6).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/plinth_%s.png" % slug)
	# height/length ratio is the numeric tell: a fish is far longer than it is tall, and a
	# baked stand pushes the ratio up toward square.
	var ratio: float = b.size.y / maxf(b.size.x, maxf(b.size.y, b.size.z))
	print("saved /tmp/plinth_%s.png  extents=%s  height/longest=%.3f"
		% [slug, str(b.size.snappedf(0.001)), ratio])
	host.queue_free()
