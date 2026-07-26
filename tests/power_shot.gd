extends Node
## Visual check on the power-on lighting budget: the same four vantages, at NIGHT, with
## the breaker OPEN and then CLOSED. Run WINDOWED (never --headless — headless renders
## nothing and every PNG comes out black).
##
## This is the companion to tests/PowerPerf.tscn. That one proves the shadow rationing in
## render_budget.gd got the frame cost down; this one proves it did not cost the look —
## the floodlights still pool, the lenses still go emissive, the interiors still warm up.
## Saves /tmp/power_<name>_(off|on).png.

var main: Node3D

const SPOTS := [
	# label, feet position, yaw deg, pitch deg
	["deck", Vector3(0.0, 18.1, -1.0), -55.0, -6.0],
	["corridor", Vector3(6.0, 21.7, 12.0), -90.0, -3.0],
	["stairs", Vector3(26.0, 14.1, 0.0), 0.0, 20.0],
	["wetdeck", Vector3(16.0, 2.6, -19.0), 35.0, -5.0],
]

func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(26.0).timeout   # let the dressing stream + budget sweep
	main._countdown = 0.0
	main.hud.fade_rect.color.a = 0.0
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	GameClock.force_phase(GameClock.Phase.NIGHT)
	await get_tree().create_timer(1.5).timeout

	for s in SPOTS:
		await _shot(s, "off")
	PowerGrid.power_circuit("topside_floodlights")
	await get_tree().create_timer(3.0).timeout   # let the stagger queue drain
	for s in SPOTS:
		await _shot(s, "on")
	get_tree().quit()

func _shot(s: Array, tag: String) -> void:
	var p: Node3D = main.player
	p.global_position = s[1]
	p.rotation.y = deg_to_rad(float(s[2]))
	p.get_node("Head").rotation.x = deg_to_rad(float(s[3]))
	p.set("velocity", Vector3.ZERO)
	p.set("input_locked", true)
	# Two settles: the first lets the camera land, the second lets render_budget's shadow
	# ranking (SHADOW_POLL, 4x a second) react to where the camera actually ended up.
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "/tmp/power_%s_%s.png" % [s[0], tag]
	print("[pshot] ", path, " err=", img.save_png(path))
