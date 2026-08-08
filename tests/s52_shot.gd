extends Node3D
## s52: photographs HELD fish through the real ItemVisual path, which is the only way to
## see two things that no headless run can check.
##
## 1. materials/fish_skin.gdshader. Seven species shipped as Meshy PREVIEW meshes with ZERO
##    materials in the GLB (parsed and confirmed), and s15 covered that with one flat albedo
##    — the owner's "it shouldnt be just 1 color". The shader replaces it with countershading
##    off the WORLD normal, body-locked mottle and a wet fresnel rim. A shader either draws
##    or it does not, and --headless never draws, so this must run WINDOWED.
## 2. The held-fish yaw. item_visual yawed every fish -90 assuming a Z-authored mesh; the
##    three X-authored ones (trop_angel, trop_butterfly, fish_ribbon_eel) came out END-ON,
##    nose at the camera. fish_ribbon_eel had shipped that way since it was wired in.
##
## Row 1 is the seven untextured species (the shader). Row 2 is the controls: a textured
## fish that must be UNTOUCHED, the three facing cases, and one cooked fish — because the
## sear path takes a different branch and a ShaderMaterial that fell through it would plate
## a pure white fish, silently, only when cooked.
##
## Run: godot --path . tests/S52Shot.tscn -- /tmp/s52   (WINDOWED — no --headless)

const IV := preload("res://scripts/world/item_visual.gd")

## The seven with no material in the GLB — every one of these is a shader test.
const UNTEXTURED := ["fish_tallow_pollock", "fish_squall_garfish", "fish_rust_wrasse",
	"fish_anchor_ray", "fish_gannet_mackerel", "fish_kelp_pipefish", "fish_lantern_dogfish"]
## Controls. herring is TEXTURED and must come through unchanged; the next three are the
## facing cases; the last is the cooked branch.
const CONTROLS := ["fish_herring", "fish_emperor_angel", "fish_butterflyfish",
	"fish_ribbon_eel", "COOKED:fish_tallow_pollock"]

const COLS: int = 7
const PITCH: float = 0.62

func _ready() -> void:
	var out_dir: String = "/tmp/s52"
	for a in OS.get_cmdline_user_args():
		out_dir = a
	DirAccess.make_dir_recursive_absolute(out_dir)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	# Mid neutral grey: a flat-coloured fish and a countershaded one separate against it,
	# and neither the dark backs nor the pale bellies clip into the background.
	e.background_color = Color(0.20, 0.22, 0.24)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.60, 0.66)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)

	# Keyed from ABOVE on purpose. The countershade keys off the world normal, so a light
	# from overhead is the case it is built for — and the case a flat albedo cannot fake.
	var key := DirectionalLight3D.new()
	add_child(key)
	key.position = Vector3(2.0, 6.0, 3.0)
	key.light_energy = 1.5
	key.look_at(Vector3.ZERO, Vector3.UP)

	var fill := DirectionalLight3D.new()
	add_child(fill)
	fill.position = Vector3(-3.0, -1.0, 2.0)
	fill.light_energy = 0.35
	fill.look_at(Vector3.ZERO, Vector3.UP)

	var rows: Array = [UNTEXTURED, CONTROLS]
	for r in range(rows.size()):
		var row: Array = rows[r]
		for c in range(row.size()):
			var spec: String = String(row[c])
			var cooked: bool = spec.begins_with("COOKED:")
			var id: String = spec.trim_prefix("COOKED:")
			var item: String = ("cooked_" + id) if cooked else id
			var n: Node3D = IV.build(item)
			if n == null:
				push_warning("[s52] no visual for %s" % item)
				continue
			add_child(n)
			n.global_position = Vector3((c - (COLS - 1) * 0.5) * PITCH,
				-float(r) * PITCH, 0.0)

	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, -PITCH * 0.5, 3.1)
	cam.current = true

	# Let the shader compile and the frame settle before reading it back. A single frame
	# photographs an unlit, half-built scene.
	for _i in range(12):
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout

	var img: Image = get_viewport().get_texture().get_image()
	var path: String = out_dir + "/held_fish.png"
	img.save_png(path)
	print("[s52] wrote %s  (%dx%d)" % [path, img.get_width(), img.get_height()])
	print("[s52] row 1 = the seven untextured (shader); row 2 = herring control, "
		+ "angel/butterfly/ribbon-eel facing, cooked pollock")
	get_tree().quit()
