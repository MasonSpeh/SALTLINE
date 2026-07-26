extends Node
## Visual check on the sun's shadow budget. Run WINDOWED (and --always-on-top: an occluded
## window presents nothing and saves black or stale frames).
##
## Two things to prove, both introduced by the frame-cost pass:
##   1. QUALITY. The directional shadow map went 4096 -> 2048 and its PCF filter from
##      medium to low, and the cascade range from 60 m to 45 m. Daylight shadows still have
##      to read as shadows — crisp at your feet, present on the ironwork around you.
##   2. THE TRANSITION. sun_controller.gd now switches the whole cascade OFF once the sun's
##      energy falls under 0.03 and back on over 0.08. Walking the sun through dusk must
##      not show a frame where shadows visibly snap out; by the time the latch trips there
##      should be no readable shadow left to lose.
##
## Saves /tmp/shadow_<phase><frac>.png plus the sun's energy and shadow flag per shot.

var main: Node3D
var sun: DirectionalLight3D

func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(30.0).timeout
	main._countdown = 0.0
	main.hud.fade_rect.color.a = 0.0
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	for c in main.get_children():
		if c is DirectionalLight3D:
			sun = c
			break
	# Open deck, mid-morning light across the plating: the clearest read on shadow quality.
	var p: Node3D = main.player
	p.global_position = Vector3(2.0, 18.1, 2.0)
	p.rotation.y = deg_to_rad(-120.0)
	p.get_node("Head").rotation.x = deg_to_rad(-12.0)
	p.set("velocity", Vector3.ZERO)
	p.set("input_locked", true)

	# Full day, then the dusk walk-down in steps, then full night.
	await _shot(GameClock.Phase.DAY, 0.35, "day")
	for f in [0.0, 0.45, 0.75, 0.9, 1.0]:
		await _shot(GameClock.Phase.DUSK, f, "dusk%02d" % int(f * 100))
	await _shot(GameClock.Phase.NIGHT, 0.3, "night")
	get_tree().quit()

func _shot(phase: int, frac: float, tag: String) -> void:
	GameClock.force_phase(phase)
	# Drive the controller to the exact point in the phase rather than waiting it out.
	# force_phase resets the counter to 0, so this is set after it, not before.
	GameClock._phase_elapsed_sec = GameClock.phase_durations_minutes[phase] * 60.0 * frac
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "/tmp/shadow_%s.png" % tag
	img.save_png(path)
	print("[shadow] %-8s sun_energy %5.3f  shadow_enabled %s  -> %s"
		% [tag, sun.light_energy, sun.shadow_enabled, path])
