extends Node3D
## Portrait harness for the Ultra Hammerhead (scripts/world/shark.gd).
##
## Photographs the LIVE species node — generated GLB plus every procedural overlay the
## script layers on after ANIM.replace() — from four fixed angles, framed on the COMBINED
## world AABB of everything under it (glTF pivots are not centred, so look_at(ZERO) misses).
## FRONT proves the four-eye X and its mirroring; SIDE shows armour, colour and teeth.
##
## Run windowed (headless has no rasteriser):
##     godot --path . res://tests/SharkShot.tscn
## Output directory is overridable with `--shotdir <path>`.

const SHARK := preload("res://scripts/world/shark.gd")

var _out: String = "/tmp"
var _cam: Camera3D
var _shark: Node3D

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--shotdir" and i + 1 < args.size():
			_out = args[i + 1]
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.055, 0.075, 0.095)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.52, 0.62)
	e.ambient_light_energy = 0.85
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	add_child(key)
	key.position = Vector3(5, 7, 5)
	key.light_energy = 2.0
	key.look_at(Vector3.ZERO, Vector3.UP)
	var fill := DirectionalLight3D.new()
	add_child(fill)
	fill.position = Vector3(-6, 2, -5)
	fill.light_energy = 0.7
	fill.light_color = Color(0.6, 0.75, 0.95)
	fill.look_at(Vector3.ZERO, Vector3.UP)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true

	_shark = SHARK.new(0)
	add_child(_shark)
	_shark.set_process(false)
	_shark.global_position = Vector3.ZERO
	await get_tree().process_frame
	await get_tree().process_frame

	_assert_eye_x()
	var acc: AABB = _bounds()
	var c: Vector3 = acc.get_center()
	var r: float = maxf(acc.size.length() * 0.5, 0.5)
	print("shark bounds pos=%s size=%s center=%s" % [acc.position, acc.size, c])
	# head is -Z: FRONT looks from -Z back along +Z.
	var head := Vector3(c.x, c.y, acc.position.z)
	await _shot("front", head + Vector3(0.0, 0.15, -2.9), head + Vector3(0, 0.05, 0))
	await _shot("front_wide", head + Vector3(0.0, 0.55, -4.2), head + Vector3(0, -0.1, 0.4))
	await _shot("charge", head + Vector3(0.55, -0.75, -3.4), head + Vector3(0, -0.15, 0.3))
	await _shot("side", c + Vector3(r * 1.7, 0.25, 0.0), c)
	await _shot("head_side", head + Vector3(3.0, 0.25, 0.9), head + Vector3(0, 0, 0.5))
	await _shot("quarter", c + Vector3(r * 1.25, r * 0.5, -r * 1.25), c)
	await _shot("under", head + Vector3(0.0, -1.8, -1.9), head + Vector3(0, -0.35, 0.15))
	await _shot("mouth", head + Vector3(1.1, -1.0, -1.5), head + Vector3(0, -0.4, -0.15))
	await _shot("top", c + Vector3(0.0, r * 1.8, 0.01), c)
	await _fallback_preview()
	get_tree().quit()

## THE NO-GLB PATH. shark.gd dresses the primitive fallback body from its own anchor set
## (DRESS_PROC), and that branch only runs when the asset is missing — which it never is
## on this machine. Renaming the .glb aside to force it makes Godot rescan the whole
## project, so instead this rebuilds the same situation in place: a second hammerhead with
## everything it built hidden, a stand-in capsule where the fallback body would be, and the
## PROC dressing built on top. It proves the second anchor set is complete and sits right.
func _fallback_preview() -> void:
	_shark.visible = false          # the generated hammerhead is at the origin too
	var s2: Node3D = SHARK.new(1)
	add_child(s2)
	s2.set_process(false)
	await get_tree().process_frame
	s2.global_position = Vector3(0, 0, 0)
	for n in s2.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).visible = false
	# Stand-in for the primitive body: the same 5m capsule shark.gd builds in _ready().
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.55
	cm.height = 5.0
	body.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = s2.HIDE_COL * 1.25
	bm.roughness = 0.34
	body.material_override = bm
	s2.add_child(body)
	body.rotation_degrees = Vector3(90, 0, 0)
	s2._build_bloom(s2.DRESS_PROC)
	await get_tree().process_frame
	var e2: Array = s2.eye_positions()
	print("fallback eyes: ", e2)
	await _shot("proc_side", Vector3(4.6, 0.2, 0.0), Vector3.ZERO)
	await _shot("proc_front", Vector3(0.0, -0.05, -3.3), Vector3(0, -0.1, -2.4))

## The four-eye X, checked numerically instead of eyeballed off the render: the upper pair
## must be equal and opposite in x, the lower pair likewise, both pairs must share a y, and
## all four must sit the same distance from the head centre.
func _assert_eye_x() -> void:
	var e: Array = _shark.eye_positions()   # [L-up, L-down, R-up, R-down]
	if e.size() != 4:
		print("EYES: expected 4, got ", e.size())
		return
	var head: Vector3 = _shark.to_global(_shark.DRESS_GEN["head"])
	print("head centre (world) = ", head)
	var names := ["left-up ", "left-dn ", "right-up", "right-dn"]
	for i in range(4):
		var p: Vector3 = e[i]
		print("  %s  %+.4f, %+.4f, %+.4f   r_from_head=%.4f" % [
			names[i], p.x, p.y, p.z, (p - head).length()])
	var ok_up: bool = absf(e[0].x + e[2].x) < 1e-4 and absf(e[0].y - e[2].y) < 1e-4
	var ok_dn: bool = absf(e[1].x + e[3].x) < 1e-4 and absf(e[1].y - e[3].y) < 1e-4
	var r: Array = []
	for p in e:
		r.append((p - head).length())
	var ok_r: bool = maxf(maxf(r[0], r[1]), maxf(r[2], r[3])) \
		- minf(minf(r[0], r[1]), minf(r[2], r[3])) < 1e-4
	var ok_split: bool = e[0].y > head.y and e[1].y < head.y and absf(e[0].x) > 0.9
	print("MIRROR upper=%s lower=%s equidistant=%s X-split=%s" % [ok_up, ok_dn, ok_r, ok_split])

func _bounds() -> AABB:
	var acc := AABB()
	var first := true
	for n in _shark.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var w: AABB = mi.global_transform * mi.get_aabb()
		acc = w if first else acc.merge(w)
		first = false
	return acc

func _shot(tag: String, eye: Vector3, look: Vector3) -> void:
	_cam.position = eye
	_cam.look_at(look, Vector3.UP)
	await get_tree().create_timer(0.35).timeout
	var p := "%s/shark_%s.png" % [_out, tag]
	get_viewport().get_texture().get_image().save_png(p)
	print("shot: ", p)
