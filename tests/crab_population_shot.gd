extends Node
## PICTURES OF THE PACK'S DAY. Three census frames from ONE camera — daylight, early night,
## deep night — so the emergence ramp can be judged by eye instead of from a table, plus a
## dive on the day column to show where they actually spend the daylight now.
##
## The clock is RUN, not jumped. Landing straight on "90% of the night" would photograph a
## pack that has not had time to climb anything; this lets nightfall happen and rides it at
## Engine.time_scale, so what is in the frame is what the schedule really produced.
##
## Windowed; needs a real viewport (gl_compat GPU).
## Run: godot --path . res://tests/CrabPopulationShot.tscn -- <output_dir>

const TIME_SCALE: float = 8.0
const EMERGED_Y: float = 0.5

var main: Node3D
var _dir: String = "/tmp"
var _fill: Array[OmniLight3D] = []
var _pause_panel: Control = null

## Undo the focus-out auto-pause every frame — the tree AND the panel it opens. A harness
## driven from a terminal never holds the window focus, so pause_menu.gd pauses on
## NOTIFICATION_APPLICATION_FOCUS_OUT: the panel lands across the middle of every saved
## frame, and a paused tree freezes the very emergence this script exists to photograph.
func _process(_d: float) -> void:
	if get_tree().paused:
		get_tree().paused = false
	if _pause_panel == null:
		# PauseMenu is a CanvasLayer, not a Control — searching for Control finds nothing.
		for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
			var s: Script = n.get_script()
			if s != null and String(s.resource_path).ends_with("pause_menu.gd"):
				_pause_panel = n.get("panel") as Control
				break
	if _pause_panel and _pause_panel.visible:
		_pause_panel.visible = false

## Weather is not the subject. A squall rolling in mid-census puts a curtain of rain between
## the camera and the animals being counted, so the sky is held clear for the whole run.
func _calm() -> void:
	var st = main.storm
	if st == null:
		return
	st._phase = StormSystem.StormPhase.CLEAR
	st._intensity = 0.0
	st._timer = 9999.0
	if st.sun_ctl:
		st.sun_ctl.set_storm(0.0)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_dir = a
	print("[crabpop] booting, output -> ", _dir)
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
	# TAKE THE CAMERA OUT OF THE "player" GROUP. This is not tidiness, it is the difference
	# between a census and a chase: crab.gd finds its quarry with get_first_node_in_group
	# ("player"), so the flying camera IS the player, and the first run of this script
	# photographed six crabs standing in a row on Deck B at y21.7 — not the deep-night
	# distribution at all, but the whole pack that had climbed the accommodation stack after
	# the lens. Dropping the collision layers does nothing about that; leaving the group
	# does. (light_pressure_at and _sense both null-guard the player, so nothing else
	# changes.) The lights the crabs actually avoid are LightZones and flares, and those are
	# untouched.
	p.remove_from_group("player")
	print("[crabpop] world up — camera removed from the player group, so the pack ignores it")

	# ---------------------------------------------------------------- DAY
	GameClock.force_phase(GameClock.Phase.DAY)
	GameClock.set("_phase_elapsed_sec", 0.4 * 34.0 * 60.0)
	await _run_for(50.0)          # let them settle onto their columns and start ranging
	await _census("day")
	# And the column itself: in the water off two caissons, looking back along the corner so
	# both exposed faces of the leg are in frame. Yaws are solved from the geometry, not
	# eyeballed — forward is (-sin yaw, 0, -cos yaw), so a camera at (29,-6,-16.5) aimed at
	# the leg corner (25,-8,-13) needs yaw 131, and its mirror on the NW leg needs -49.
	await _shot(Vector3(29.0, -6.0, -16.5), 131.0, -6.0, "day_column_se")
	await _shot(Vector3(-29.0, -6.0, 16.5), -49.0, -6.0, "day_column_nw")

	# ---------------------------------------------------------------- NIGHT, twice
	GameClock.force_phase(GameClock.Phase.NIGHT)
	_light_the_set()
	await _ride_to(0.16)
	await _census("early_night")
	await _ride_to(0.92)
	await _census("deep_night")

	print("[crabpop] done")
	get_tree().quit(0)

## The census pair, shot from the same two marks every time so the three time-of-day frames
## can be laid side by side and simply counted. WIDE takes in the topside rim and the water;
## WETDECK looks straight in under the topside plate at the plating the rim lane lands on
## (that deck is roofed by the plate above it, so there is no useful shot from overhead).
func _census(tag: String) -> void:
	_roll_call(tag)
	await _shot(Vector3(52.0, 22.0, -30.0), 121.0, -18.0, "census_%s" % tag)
	await _shot(Vector3(40.0, 5.5, -14.0), 90.0, -2.0, "wetdeck_%s" % tag)
	# TOPSIDE. Six of the eight crabs climb their own caisson straight to the main deck, so
	# most of a deep night is up here and none of it shows in the two frames above — the
	# topside plate roofs the wet deck, and from outboard you see its underside.
	await _shot(Vector3(6.0, 33.0, -4.0), 96.0, -46.0, "topside_%s" % tag)

## Where every crab actually is at this census, so the frames can be read against a list
## rather than squinted at.
func _roll_call(tag: String) -> void:
	var CrabS := preload("res://scripts/world/crab.gd")
	var where: Array[String] = []
	for c in get_tree().get_nodes_in_group("giant_crab"):
		var p: Vector3 = (c as Node3D).global_position
		var band: String = "water"
		if p.y > 16.0:
			band = "TOPSIDE"
		elif p.y > EMERGED_Y:
			band = "wet deck" if p.y < 4.6 else "climbing"
		where.append("%d:%s(y%.1f,%s)" % [int(c.spawn_index), band, p.y,
			CrabS.State.keys()[int(c.state)]])
	print("[crabpop] roll call %s — %s" % [tag, " ".join(where)])

## A photographer's fill over the rig's east face. The crabs are naturalistic — no glow, no
## lamp — so an honest night frame of them is a black rectangle. The game ships dark; this
## light exists only so the census can be counted.
func _light_the_set() -> void:
	# Three of them, strung along the east face: one lamp at census range leaves the far end
	# of the wet deck and the whole topside rim in the dark, and a census you cannot count is
	# not a census. Shadows off — these are fill, not lighting design.
	for p in [Vector3(34.0, 6.0, -18.0), Vector3(34.0, 6.0, -6.0), Vector3(34.0, 21.0, -10.0)]:
		var l := OmniLight3D.new()
		l.light_energy = 10.0
		l.omni_range = 46.0
		l.light_color = Color(0.72, 0.80, 0.95)
		l.shadow_enabled = false
		main.add_child(l)
		l.global_position = p
		_fill.append(l)

func _emerged() -> int:
	var n: int = 0
	for c in get_tree().get_nodes_in_group("giant_crab"):
		if (c as Node3D).global_position.y > EMERGED_Y:
			n += 1
	return n

## Let `sec` of GAME time pass, compressed. get_process_delta_time() is already scaled by
## Engine.time_scale, so it is summed raw — multiplying again is the classic mistake here.
func _run_for(sec: float) -> void:
	Engine.time_scale = TIME_SCALE
	var t: float = 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()
	Engine.time_scale = 1.0

func _ride_to(frac: float) -> void:
	Engine.time_scale = TIME_SCALE
	while GameClock.current_phase == GameClock.Phase.NIGHT \
			and GameClock.phase_fraction() < frac:
		await get_tree().process_frame
	Engine.time_scale = 1.0

func _place(pos: Vector3, yaw_deg: float, pitch_deg: float) -> void:
	var p: Node3D = main.player
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw_deg)
	p.get_node("Head").rotation.x = deg_to_rad(pitch_deg)
	p.set("velocity", Vector3.ZERO)
	p.set("input_locked", true)

func _shot(pos: Vector3, yaw_deg: float, pitch_deg: float, name_: String) -> void:
	_calm()
	_place(pos, yaw_deg, pitch_deg)
	await get_tree().create_timer(0.8).timeout
	_calm()
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/crabpop_%s.png" % [_dir, name_]
	var err: int = img.save_png(path)
	print("[crabpop] saved %s  err=%d   phase=%s frac=%.2f  emerged=%d/8"
		% [path, err, GameClock.Phase.keys()[GameClock.current_phase],
			GameClock.phase_fraction(), _emerged()])
