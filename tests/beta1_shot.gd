extends Node
## BETA1 VISUAL PROOF — photographs the ~8 things the Beta1 batch claims to have fixed,
## so they can be judged as pictures. Windowed; needs a real viewport (gl_compat GPU).
## Run: godot --path . res://tests/Beta1Shot.tscn -- <output_dir> [--only=<substr>]

var main: Node3D
var _dir: String = "/tmp"
var _only: String = ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7).to_lower()
		elif not a.begins_with("--"):
			_dir = a
	print("[b1] booting, output -> ", _dir, ("" if _only == "" else "  (filter: %s)" % _only))
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(9.0).timeout
	main._countdown = 0.0
	if main.hud != null:
		if main.hud.fade_rect != null:
			main.hud.fade_rect.color.a = 0.0
		main.hud.visible = false
	var p: Node3D = main.player
	p.set("_fly", true)
	(p as CollisionObject3D).set_collision_layer_value(1, false)
	(p as CollisionObject3D).set_collision_mask_value(1, false)
	print("[b1] world up")

	# ============================================================ DAY topside / interiors
	GameClock.force_phase(GameClock.Phase.DAY)
	await get_tree().process_frame

	# (h) LIFEBOAT — orange TEMPSC in its davits at the south muster edge (-3.5, ~19.35, -18.2)
	await _shot(Vector3(-3.5, 19.6, -13.6), 0.0, -6.0, "lifeboat")
	await _shot(Vector3(-6.6, 19.6, -14.2), 22.0, -8.0, "lifeboat_oblique")

	# (d) TOPSIDE MAIN DECK — wide establishing, no floating furniture in the rooms
	await _shot(Vector3(0.0, 26.5, 4.0), 178.0, -34.0, "topside_wide")
	await _shot(Vector3(6.0, 19.2, 9.4), 178.0, -8.0, "room_galley")
	await _shot(Vector3(22.5, 19.2, 9.4), 178.0, -8.0, "room_rec")
	await _shot(Vector3(-20.0, 19.2, 8.0), 155.0, -8.0, "room_bunk")

	# (e) SPHL / spawn pod (wet deck) + machine shop — real props flush, no flat blocks
	await _shot(Vector3(20.5, 3.3, -20.5), 6.0, -6.0, "sphl_spawn")
	# THIS SHOT WAS NOT INSIDE THE POD. It stood at z -20.0 looking down +Z at the outside of
	# a bulkhead — but `_build_sphl` puts the interior at x 14.9..21.1, z -25.3..-22.9, floor
	# WET_Y 2.0, ceiling 4.2, and both benches at z -23.2 / -24.8. So the frame named
	# "sphl_interior" has been photographing an exterior wall, which is why the owner's
	# twice-reported red lines were never in a picture anyone checked.
	# `_place` moves the PLAYER and the eye rides ~1.6 m above its feet (AGENT_TRAPS), so the
	# argument is a FLOOR position: y = WET_Y 2.0 puts the eye at 3.6, inside the 2.0..4.2
	# shell. Anything higher stands the camera on the roof — y 3.3 photographed open sea.
	await _shot(Vector3(20.5, 2.0, -24.0), 90.0, -15.0, "sphl_interior")
	await _shot(Vector3(-24.5, 18.95, -12.2), -90.0, -3.0, "machine_shop")
	await _shot(Vector3(-24.5, 18.95, -9.0), -70.0, -3.0, "machine_shop_bench")

	# (f) EYE-PROTECTION sign + SAFETY EQUIPMENT locker — text fits its plate
	await _shot(Vector3(-18.7, 18.95, -8.6), 180.0, 2.0, "eye_sign")
	# Locker sits against the bunkhouse south wall in the west alley (front faces -z at
	# x -27.2, z ~3.0). Stand south of it in the alley, looking north.
	await _shot(Vector3(-26.4, 18.85, 1.2), 172.0, 0.0, "safety_locker")
	await _shot(Vector3(-27.2, 18.85, 0.6), 180.0, 2.0, "safety_locker_head")

	# (c) LAMP SNAIL underwater — opaque body, not see-through
	await _snail_shot()

	# ============================================================ STORM (rain shape)
	_storm_on()
	await get_tree().create_timer(3.0).timeout
	await _shot(Vector3(0.0, 20.5, -18.0), 0.0, 2.0, "rain_sea")
	await _shot(Vector3(6.0, 20.5, -20.0), -20.0, 4.0, "rain_sea2")
	_storm_off()
	await get_tree().create_timer(1.0).timeout

	# ============================================================ NIGHT — emergency lights (UNPOWERED)
	GameClock.force_phase(GameClock.Phase.NIGHT)
	await get_tree().create_timer(0.5).timeout
	await _emergency_shot(Vector3(23.6, 21.0, -5.75), -90.0, 2.0, "emergency_stairshaft")
	await _emergency_shot(Vector3(23.2, 12.6, 6.0), -90.0, 0.0, "emergency_breaker")

	# ============================================================ NIGHT — crabs on the wet deck
	await _crab_shot()

	print("[b1] done")
	get_tree().quit(0)

# ---------------------------------------------------------------- storm control
func _storm_on() -> void:
	var st = main.storm
	if st == null:
		return
	st._phase = StormSystem.StormPhase.RAGING
	st._intensity = 1.0
	st._timer = 9999.0

func _storm_off() -> void:
	var st = main.storm
	if st == null:
		return
	st._phase = StormSystem.StormPhase.CLEAR
	st._intensity = 0.0
	st._timer = 9999.0
	if st.sun_ctl:
		st.sun_ctl.set_storm(0.0)

# ---------------------------------------------------------------- emergency flasher shot
func _emergency_shot(pos: Vector3, yaw_deg: float, pitch_deg: float, name_: String) -> void:
	if _only != "" and not name_.to_lower().contains(_only):
		return
	_place(pos, yaw_deg, pitch_deg)
	await get_tree().create_timer(0.6).timeout
	# Force every red flasher into the bright half of its blink for the frame we grab.
	for n in _all_nodes(main):
		if n is Node3D and n.get("_lens") != null and n.get("_light") != null and n.get("_peak") != null and n.get("_period") != null:
			n.set("_t", 0.0)
			var lt = n.get("_light")
			if lt:
				lt.light_energy = n.get("_peak")
			var lens = n.get("_lens")
			if lens:
				lens.emission_energy_multiplier = 6.0
	await RenderingServer.frame_post_draw
	_save(name_)

# ---------------------------------------------------------------- lamp snail shot
func _snail_shot() -> void:
	if _only != "" and not "snail".contains(_only) and not "lamp".contains(_only):
		return
	# Freeze one lamp snail and set it in clean open water off the east rim, below the
	# swell, with a photographer's fill so it reads. If the shell were see-through the
	# teal murk behind would show THROUGH it — opaque reads as a solid body carrying the
	# glow constellation. DAY, so the whole body (not just the glow) is lit.
	var snails := get_tree().get_nodes_in_group("snail_lamp")
	var target := Vector3(31.0, -3.2, -14.0)
	var fill: OmniLight3D = null
	if snails.size() > 0:
		var s: Node3D = snails[0]
		for n in _all_nodes(s):
			n.set_process(false)
			n.set_physics_process(false)
		s.global_position = target
		print("[b1] snail at ", s.global_position)
		fill = OmniLight3D.new()
		fill.light_energy = 3.0
		fill.omni_range = 5.0
		fill.light_color = Color(0.85, 0.92, 1.0)
		fill.shadow_enabled = false
		main.add_child(fill)
		fill.global_position = target + Vector3(0.5, 0.7, 1.1)
	_place(target + Vector3(-0.15, 0.2, 1.5), -6.0, -7.0)
	await get_tree().create_timer(0.4).timeout
	if snails.size() > 0:
		(snails[0] as Node3D).global_position = target
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	_save("lamp_snail_uw")
	if fill:
		fill.queue_free()

# ---------------------------------------------------------------- crab night shot
func _crab_shot() -> void:
	if _only != "" and not "crab".contains(_only):
		return
	# A photographer's fill light over the wet-deck rim so the naturalistic (unlit) crabs
	# read at night — the game leaves this dark, this is only for the proof frame.
	var fill := OmniLight3D.new()
	fill.light_energy = 3.0
	fill.omni_range = 22.0
	fill.light_color = Color(0.75, 0.82, 0.95)
	fill.shadow_enabled = false
	main.add_child(fill)
	fill.global_position = Vector3(26.0, 7.0, -14.0)
	# Stage the pack on the east rim: a couple mid-climb over the lip, the rest patrolling.
	var crabs := get_tree().get_nodes_in_group("giant_crab")
	var stage := [
		[Vector3(29.3, 2.6, -10.0), GiantCrab.State.PATROL],
		[Vector3(27.0, 2.6, -13.0), GiantCrab.State.PATROL],
		[Vector3(29.3, 2.2, -16.0), GiantCrab.State.EMERGE],
		[Vector3(30.6, 0.9, -14.0), GiantCrab.State.EMERGE],
		[Vector3(26.0, 2.6, -18.0), GiantCrab.State.PATROL],
		[Vector3(28.5, 2.6, -20.0), GiantCrab.State.PATROL],
	]
	for i in range(crabs.size()):
		var c: Node3D = crabs[i]
		var spec = stage[i % stage.size()]
		c.set("state", spec[1])
		c.global_position = spec[0]
	_place(Vector3(22.0, 4.6, -14.0), -90.0, -7.0, false)
	await get_tree().create_timer(0.6).timeout
	# Re-assert positions in case the FSM drifted them during the settle.
	for i in range(crabs.size()):
		var c: Node3D = crabs[i]
		c.global_position = stage[i % stage.size()][0]
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	_save("night_crabs")

# ---------------------------------------------------------------- shared plumbing
## pos is FEET; the eye sits ~1.7m above it. Yaw: forward = (-sin y, 0, -cos y).
func _place(pos: Vector3, yaw_deg: float, pitch_deg: float, eye_offset: bool = true) -> void:
	var p: Node3D = main.player
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw_deg)
	p.get_node("Head").rotation.x = deg_to_rad(pitch_deg)
	p.set("velocity", Vector3.ZERO)
	p.set("input_locked", true)

func _shot(pos: Vector3, yaw_deg: float, pitch_deg: float, name_: String) -> void:
	if _only != "" and not name_.to_lower().contains(_only):
		return
	_place(pos, yaw_deg, pitch_deg)
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	_save(name_)

func _save(name_: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/beta1_%s.png" % [_dir, name_]
	var err: int = img.save_png(path)
	print("[b1] saved ", path, " err=", err)

func _all_nodes(root: Node) -> Array:
	var out: Array = [root]
	for c in root.get_children():
		out.append_array(_all_nodes(c))
	return out
