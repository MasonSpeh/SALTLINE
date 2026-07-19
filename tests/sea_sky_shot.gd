extends Node
## Sea + sky visual audit. Boots Main, parks the camera at the vantages where the two
## failure modes this work exists to kill are most visible, and saves PNGs:
##   * SEA at a LOW GRAZING ANGLE, calm and storm — grazing is where parallel identical
##     crests (the "sine rows" tell) show up. Straight-down hides them.
##   * NIGHT SKY looking UP and along the HORIZON — up is where a star LATTICE reads as
##     a grid, the horizon is where a shell/dome edge and missing extinction read.
##   * DUSK and DAY — the sun/moon disc must sit where the light actually comes from.
##   * GYRE debris at eye level — Gerstner moves water sideways, so debris that only
##     samples height drifts off the crest it should be sitting on.
## Run windowed (real GPU): see the header of this file's runner invocation in the
## builder notes. Writes to the scratchpad dir, never /tmp root.

const OUT := "/private/tmp/claude-501/-Users-mjspeh-Desktop-UltraInbox/87d5de70-f27c-48d3-bab9-cb1e9a8f822d/scratchpad"

var main: Node3D

func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.5).timeout
	main.hud.fade_rect.color.a = 0.0
	# Hide the HUD chrome so it does not sit on top of the sky we are judging.
	main.hud.visible = false
	var p: Node3D = main.player
	p._fly = true
	p.set_collision_layer_value(1, false)
	p.set_collision_mask_value(1, false)
	p.input_locked = true
	# Freeze the schedule: the clock must not slide out of the phase mid-sequence, and
	# StormSystem must not stomp the sea_state/storm we force for the squall shots.
	main.storm.set_process(false)

	# ---------------- SEA, calm ----------------
	_set_phase(GameClock.Phase.DAY)
	main.sun_ctl.set_storm(0.0)
	await _shot(Vector3(60, 2.6, 60), -135.0, -4.0, "sky_sea_calm_graze")
	# Same water, a different heading: if crests are parallel rows, rotating the camera
	# 90 deg makes them snap from "toward you" to "across you" and the rows give it away.
	await _shot(Vector3(60, 2.6, 60), -45.0, -4.0, "sky_sea_calm_graze_cross")
	# Near field from just above the swell: is there resolvable 1.5 m chop, or one smooth face?
	await _shot(Vector3(60, 3.4, 60), -135.0, -14.0, "sky_sea_calm_near")

	# ---------------- SEA, storm ----------------
	main.sun_ctl.set_storm(1.0)
	await get_tree().create_timer(0.6).timeout
	await _shot(Vector3(60, 4.0, 60), -135.0, -4.0, "sky_sea_storm_graze")
	await _shot(Vector3(60, 9.0, 60), -135.0, -11.0, "sky_sea_storm_wide")
	main.sun_ctl.set_storm(0.0)

	# ---------------- GYRE: does the flotsam sit ON the water? ----------------
	# Gyre eye is at z = -52; yaw 0 faces -Z (Godot forward), so this looks INTO the
	# gyre from 18 m out at debris eye level, clear of the rig deck overhead.
	await _shot(Vector3(0, 1.5, -34), 0.0, -2.0, "sky_gyre_debris")
	await _shot(Vector3(-14, 1.5, -44), -55.0, -2.0, "sky_gyre_debris_b")

	# ---------------- NIGHT SKY ----------------
	_set_phase(GameClock.Phase.NIGHT)
	await get_tree().create_timer(0.8).timeout
	await _shot(Vector3(60, 6.0, 60), -135.0, 84.0, "sky_night_zenith")   # straight up: lattice hunt
	await _shot(Vector3(60, 6.0, 60), -135.0, 34.0, "sky_night_mid")      # Milky Way band
	await _shot(Vector3(60, 6.0, 60), -135.0, 5.0, "sky_night_horizon")   # extinction + shell edge
	await _shot(Vector3(60, 6.0, 60), 45.0, 12.0, "sky_night_horizon_b")  # opposite bearing
	# Storm at night must be genuinely overcast and starless.
	main.sun_ctl.set_storm(1.0)
	await get_tree().create_timer(0.6).timeout
	await _shot(Vector3(60, 6.0, 60), -135.0, 40.0, "sky_night_storm")
	main.sun_ctl.set_storm(0.0)

	# ---------------- DUSK / DAY ----------------
	_set_phase(GameClock.Phase.DUSK)
	await get_tree().create_timer(0.8).timeout
	await _shot(Vector3(60, 4.0, 60), -135.0, 6.0, "sky_dusk")
	await _shot(Vector3(60, 4.0, 60), 45.0, 6.0, "sky_dusk_anti")
	_set_phase(GameClock.Phase.DAY)
	await get_tree().create_timer(0.8).timeout
	await _shot(Vector3(60, 4.0, 60), -135.0, 20.0, "sky_day")

	# ---------------- DAWN: the whole rig seen from the water ----------------
	# The money shot and the one that judges the INTEGRATION rather than any single
	# system: sea, sky, horizon seam and the rig's silhouette all in one frame, at the
	# hour where a wrong sun bearing or a mismatched horizon is most obvious. Yaw 180
	# faces +Z, i.e. back toward the rig at the origin, from open water to the south.
	_set_phase_at(GameClock.Phase.DAWN, 0.62)   # sun up, still low and warm
	await get_tree().create_timer(0.8).timeout
	await _shot(Vector3(0, 2.4, -78), 180.0, 4.0, "sky_dawn_rig_wide")
	await _shot(Vector3(46, 3.0, -46), 145.0, 3.0, "sky_dawn_rig_quarter")
	get_tree().quit()

func _set_phase(ph: int) -> void:
	_set_phase_at(ph, 0.0)

## force_phase() always lands at fraction 0, which for DAWN is the moment night ENDS —
## sun still below the horizon, sky still black. To photograph an actual dawn we have to
## push the clock into the phase, then re-emit so SunController re-runs its curves.
func _set_phase_at(ph: int, frac: float) -> void:
	GameClock.set_running(true)
	GameClock.force_phase(ph)
	GameClock._phase_elapsed_sec = GameClock.phase_durations_minutes[ph] * 60.0 * frac
	GameClock.time_updated.emit(clampf(frac, 0.0, 1.0))
	GameClock.set_running(false)

func _shot(pos: Vector3, yaw_deg: float, pitch_deg: float, name_: String) -> void:
	var p: Node3D = main.player
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw_deg)
	p.get_node("Head").rotation.x = deg_to_rad(pitch_deg)
	p.velocity = Vector3.ZERO
	await get_tree().create_timer(0.9).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, name_])
	print("saved %s/%s.png" % [OUT, name_])
