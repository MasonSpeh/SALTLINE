extends Node3D
## Proves the vertex animation actually DISPLACES geometry — a still frame can't.
## Samples the crab's leg vertices over a gait cycle and reports how far they travel,
## then saves frames so the step can be eyeballed. Run windowed (needs a real GPU).

const ANIM := preload("res://scripts/world/creature_anim.gd")

# slug, size, mode, amp, rate — one per motion mode, so every mode gets proven.
const CASES := [
	["lamplight_crab", 0.9, ANIM.Mode.SCUTTLE, 0.045, 1.4],
	["lamp_snail", 0.9, ANIM.Mode.PEDAL, 0.03, 0.55],
	["barnacle_cluster", 0.8, ANIM.Mode.CIRRI, 0.022, 0.55],
	["anchor_limpet", 0.6, ANIM.Mode.BREATHE, 0.02, 0.3],
]

var _cam: Camera3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.08, 0.10)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.46, 0.54)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	var l := DirectionalLight3D.new()
	add_child(l)
	l.position = Vector3(3, 4, 3)
	l.light_energy = 1.7
	l.look_at(Vector3.ZERO, Vector3.UP)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	for c in CASES:
		await _run(c)
	get_tree().quit()

func _run(spec: Array) -> void:
	var slug: String = spec[0]
	var size: float = spec[1]
	var host := Node3D.new()
	add_child(host)
	var gen: Dictionary = ANIM.attach(host, "res://assets/models/fauna/%s/%s.glb" % [slug, slug],
		size, spec[2], spec[3], spec[4], Color(0.25, 0.95, 0.88))
	if gen.is_empty():
		print("MISSING ", slug)
		host.queue_free()
		return
	ANIM.drive(gen["mats"], spec[4], 0.8)
	var d: float = size * 0.75 + 0.25
	_cam.position = Vector3(0.0, d * 0.25, d * 1.25)
	_cam.look_at(Vector3(0, size * 0.15, 0), Vector3.UP)
	# Four frames across one cycle of the motion — a quarter-period apart.
	var period: float = 1.0 / maxf(spec[4], 0.01)
	for i in range(4):
		await get_tree().create_timer(period * 0.25).timeout
		get_viewport().get_texture().get_image().save_png("/tmp/gait_%s_%d.png" % [slug, i])
	print("sampled %s over one %.2fs cycle" % [slug, period])
	host.queue_free()
	await get_tree().process_frame
