extends Node3D
## POLE SHOT — the caisson-leg vertical-lines instrument. The owner reports the moving
## vertical lines are BACK, specifically on the foundation pole coming up through the Wet
## Deck. That is a DIFFERENT surface from the tower wall WallShot characterised in s43b
## (MatLib.concrete() at uv 0.45 — 461 texel/m, twice the tower's post-s42 density — vs
## concrete_tower() at 0.22), and "moving" needs a different discriminator than a static
## residue: the reel has to separate WHAT the motion is locked to. Three segments per
## light condition do that in one windowed run:
##
##   hold    30 frames / 5.0 s sim, camera fixed, GameClock FROZEN (sun pinned), storm
##           pinned off. Anything that still moves here is driven by wall-clock TIME
##           (shader TIME, Gyre.water_time — both keep running) and nothing else.
##   clock   12 frames / 2 s at GameClock.time_scale 40 = 80 s of game clock: the sun
##           sweeps ~5.6 deg of azimuth, so shadow-cascade texel crawl — invisible in
##           5 s at the real 0.07 deg/s — becomes a per-frame signal.
##   strafe  12 frames sliding 0.18 m/frame along the face, clock frozen again: the
##           viewer-locked artifacts — grazing-angle mip/aliasing shimmer (the s42 aniso
##           question) and the parallax of anything standing proud of the face.
##
## Subject: the SE leg (centre (22, 0, -12), rig_builder.gd:712; the pillar the player
## spawns beside), whose 6 m faces rise from the Wet Deck slab. The camera films the
## SOUTH face (bare MatLib.concrete(), no dressing at eye height — the clean instrument)
## 0.8 m off the face at a ~10 deg graze, then one bonus reel on the WEST/inboard face,
## which carries the rust-bleed stickers authored to a hand-typed 3.14/3.15 half-width
## against the real 3.0 (rig_builder.gd:3582) — they and the riser pipes hover ~0.15 m
## proud of the concrete, and only a moving camera can show whether their parallax is
## the owner's "moving lines".
##
## Positions are PROBED, not trusted: the deck is found by down-ray, the face plane by a
## horizontal ray, and after framing three pixel rays print what is actually in shot
## (the s43b lesson — two carrier experiments were wasted on a wall that was never the
## photographed surface). Fauna and the player are excluded from every ray (the s20
## FaunaTouch trap). The pose actually used is printed per segment.
##
##   godot --path . --fixed-fps 60 tests/PoleShot.tscn -- /tmp/pole_lines
##
## Frames land in tests/out/pole_lines/ unless a positional arg overrides.

const RB := preload("res://scripts/world/rig_builder.gd")
const FAUNA := preload("res://scripts/world/bloom_fauna.gd")

## The legs array is a local literal in RigBuilder._build_structure (rig_builder.gd:712),
## so it cannot be imported — this copy is verified at runtime by the face ray below and
## the collider paths in the log.
const SE_LEG := Vector3(22.0, 0.0, -12.0)
const EYE_UP: float = 1.6      ## standing eye above the floor — the s21 vantage rule
const CAPTURE_GAP: int = 10    ## process frames per capture: 6 fps at --fixed-fps 60
const HOLD_N: int = 30         ## x gap = 5.0 s of sim, camera and clock both still
const CLOCK_N: int = 12
const CLOCK_SCALE: float = 40.0
const STRAFE_N: int = 12
const STRAFE_STEP: float = 0.18

var _dir: String = ProjectSettings.globalize_path("res://tests/out/pole_lines")
var _main: Node3D
var _cam: Camera3D
var _player: Node3D
var _exclude: Array[RID] = []
var _frame_i: int = 0

func _process(_d: float) -> void:
	if get_tree().paused:
		get_tree().paused = false
	var pm: Node = get_tree().get_first_node_in_group("pause_menu")
	if pm != null and pm.get("panel") != null:
		(pm.get("panel") as CanvasItem).visible = false

func _pin_storm() -> void:
	if _main == null:
		return
	var st: Node = _main.get("storm")
	if st != null:
		st.set_process(false)
		st.set("_intensity", 0.0)
		st.set("_phase", 0)

## Park the day at a chosen fraction. force_phase alone resets to f=0 (the s22 trap), so
## the intra-day position is written explicitly. NOTE: SunController only reads the new
## fraction on the next time_updated, which only fires while the clock RUNS — so freezing
## must happen a few frames after this call, never in the same one.
func _set_day(frac: float) -> void:
	GameClock.force_phase(GameClock.Phase.DAY)
	GameClock._phase_elapsed_sec = \
		float(GameClock.phase_durations_minutes[GameClock.Phase.DAY]) * 60.0 * frac

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = _exclude
	return get_tree().root.world_3d.direct_space_state.intersect_ray(q)

## Print what the framed pixels actually photograph — name, path, world position.
func _identify(tag: String) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	for px in [Vector2(0.30, 0.45), Vector2(0.55, 0.50), Vector2(0.78, 0.58)]:
		var origin: Vector3 = _cam.project_ray_origin(px * vp)
		var dirn: Vector3 = _cam.project_ray_normal(px * vp)
		var hit: Dictionary = _ray(origin, origin + dirn * 30.0)
		if hit.is_empty():
			print("[pole] %s pixel %s: no hit" % [tag, str(px)])
			continue
		var col: Node = hit["collider"]
		print("[pole] %s pixel %s hits %s at %s (path %s)" % [tag, str(px), col.name,
			str((hit["position"] as Vector3).snappedf(0.01)), str(col.get_path())])

func _print_suns() -> void:
	for n in _main.find_children("*", "DirectionalLight3D", true, false):
		print("[pole] light %s rotation %s energy %.2f" % [n.name,
			str((n as Node3D).rotation_degrees.snappedf(0.1)), (n as Light3D).light_energy])

## The two halves of the s42 aniso question GDScript can read back (the driver's actual
## anisotropy is not queryable from here — that half stays for the film).
func _print_aniso() -> void:
	print("[pole] project aniso level = %s (4 = 16x)" % str(ProjectSettings.get_setting(
		"rendering/textures/default_filters/anisotropic_filtering_level")))
	var cm: Variant = MatLib._cache.get("concrete")
	if cm is BaseMaterial3D:
		var tf: int = (cm as BaseMaterial3D).texture_filter
		print("[pole] concrete().texture_filter = %d, anisotropic-mipmap = %s" % [tf,
			str(tf == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC)])
	else:
		print("[pole] concrete() not in MatLib cache — world did not build it?")

## The caustic-gate arithmetic, live: the caustic/snell root draws only while
## cam_y < surf + 1.5 (underwater_fx.gd:303), and its lit band tops out at
## Gyre.tide() <= +0.7 — both printed so the reel's conditions are on record.
func _print_gate(eye: Vector3) -> void:
	var surf: float = Gyre.swim_line(Vector2(eye.x, eye.z), Gyre.water_time())
	var vis: String = "VISIBLE" if eye.y < surf + 1.5 else "hidden"
	print("[pole] gate: tide %.2f surf@cam %.2f cam_y %.2f -> caustic root %s (lit band tops at tide)"
		% [Gyre.tide(), surf, eye.y, vis])

func _capture(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var tex: Texture2D = get_viewport().get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img != null:
		# Native pixels, no resize — the s43b lesson: a ~2:1 bilinear downscale of fine
		# concrete is a moire generator and the instrument photographs its own artifact.
		img.save_png("%s/%s.png" % [_dir, name_])
	_frame_i += 1

func _aim_cam(eye: Vector3, aim: Vector3) -> void:
	_cam.global_position = eye
	_cam.look_at(aim, Vector3.UP)

## One full discriminator reel at the current framing: hold / clock / strafe.
## strafe_dir is the unit direction the eye slides along the face.
func _reel(label: String, eye: Vector3, aim: Vector3, strafe_dir: Vector3, frac: float) -> void:
	_aim_cam(eye, aim)
	print("[pole] %s eye %s aim %s fwd %s" % [label, str(eye.snappedf(0.01)),
		str(aim.snappedf(0.01)), str((-_cam.global_transform.basis.z).snappedf(0.001))])
	_print_gate(eye)
	_identify(label)
	# HOLD — clock frozen (sun pinned by construction: SunController only moves on
	# time_updated, which never fires while the clock is stopped).
	GameClock.set_running(false)
	for f in range(HOLD_N):
		_pin_storm()
		_aim_cam(eye, aim)
		for w in range(CAPTURE_GAP):
			await get_tree().process_frame
		await _capture("pole_%s_hold_%02d" % [label, f])
	# CLOCK — the one segment where game time runs, at x40 so cascade crawl shows.
	GameClock.time_scale = CLOCK_SCALE
	GameClock.set_running(true)
	for f in range(CLOCK_N):
		_pin_storm()
		_aim_cam(eye, aim)
		for w in range(CAPTURE_GAP):
			await get_tree().process_frame
		await _capture("pole_%s_clock_%02d" % [label, f])
	# Re-park the day so the strafe shares the hold's light, then freeze again.
	GameClock.time_scale = 1.0
	_set_day(frac)
	for w in range(3):
		await get_tree().process_frame   # one running tick moves the sun back
	GameClock.set_running(false)
	_print_suns()
	# STRAFE — camera motion is now the only moving part.
	for f in range(STRAFE_N):
		_pin_storm()
		var slide: Vector3 = strafe_dir * STRAFE_STEP * float(f)
		_aim_cam(eye + slide, aim + slide * 0.4)
		for w in range(CAPTURE_GAP):
			await get_tree().process_frame
		await _capture("pole_%s_strafe_%02d" % [label, f])

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_dir = a
	DirAccess.make_dir_recursive_absolute(_dir)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	if _main == null or _main.get_script() == null:
		print("[pole] Main.tscn came back WITHOUT its script")
		get_tree().quit(1)
		return
	add_child(_main)
	var t0: int = Time.get_ticks_msec()
	var waited: int = 0
	while Time.get_ticks_msec() - t0 < 22000 or waited < 180:
		await get_tree().process_frame
		waited += 1
	print("[pole] world built in %d ms" % (Time.get_ticks_msec() - t0))
	_player = get_tree().get_first_node_in_group("player")
	_player.set_physics_process(false)
	_cam = _player.get_node("Head/Camera3D")
	_cam.current = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)

	# Ray hygiene: exclude the player's body and every fauna collider (FaunaTouch is a
	# solid StaticBody3D on layer 1 — the s20 trap that "moved" a caisson 606 mm).
	if _player is CollisionObject3D:
		_exclude.append((_player as CollisionObject3D).get_rid())
	var fauna_root: Node3D = null
	for n in _main.find_children("*", "Node3D", true, false):
		var s: Script = n.get_script()
		if s != null and String(s.resource_path).ends_with("bloom_fauna.gd"):
			fauna_root = n
			break
	if fauna_root != null:
		_exclude.append_array(FAUNA.fauna_bodies(fauna_root))
	print("[pole] excluding %d colliders from rays" % _exclude.size())

	# Park the player behind the south-face camera so the body is in no frame.
	_player.global_position = Vector3(27.5, RB.WET_Y + 0.6, -18.5)

	# ---- PROBE THE SUBJECT (never hand-type what a ray can measure) ----
	var south_z_expect: float = SE_LEG.z - RB.LEG_SIZE.z * 0.5   # -15.0
	var cam_x: float = SE_LEG.x + 2.3
	var floor_hit: Dictionary = _ray(Vector3(cam_x, RB.WET_Y + 4.0, south_z_expect - 0.8),
		Vector3(cam_x, RB.WET_Y - 2.0, south_z_expect - 0.8))
	var floor_y: float = RB.WET_Y
	if floor_hit.is_empty():
		print("[pole] DOWN-PROBE MISSED — falling back to WET_Y %.2f" % RB.WET_Y)
	else:
		floor_y = (floor_hit["position"] as Vector3).y
		print("[pole] deck under camera: y %.3f on %s" % [floor_y,
			str((floor_hit["collider"] as Node).get_path())])
	var eye_y: float = floor_y + EYE_UP
	var face_hit: Dictionary = _ray(Vector3(cam_x, eye_y, south_z_expect - 3.0),
		Vector3(cam_x, eye_y, south_z_expect + 2.0))
	var face_z: float = south_z_expect
	if face_hit.is_empty():
		print("[pole] FACE-PROBE MISSED — falling back to z %.2f" % south_z_expect)
	else:
		face_z = (face_hit["position"] as Vector3).z
		print("[pole] south face plane: z %.3f on %s" % [face_z,
			str((face_hit["collider"] as Node).get_path())])
	_print_aniso()

	# ---- SOUTH FACE, two light conditions. 0.45 is high sun (elev ~55 deg); 0.02 is
	# early-day raking light (elev ~18 deg) — the pair WallShot used to split sun-driven
	# from sun-indifferent banding, applied to the new surface.
	var eye := Vector3(cam_x, eye_y, face_z - 0.8)
	var aim := Vector3(SE_LEG.x - 2.4, floor_y + 1.35, face_z)
	for pass_spec in [[0.45, "noon"], [0.02, "lowsun"]]:
		var frac: float = float(pass_spec[0])
		GameClock.time_scale = 1.0
		GameClock.set_running(true)
		_set_day(frac)
		_pin_storm()
		for i in range(30):
			await get_tree().process_frame
		_print_suns()
		await _reel(str(pass_spec[1]), eye, aim, Vector3(-1, 0, 0), frac)

	# ---- WEST (inboard) FACE bonus reel, noon only: the sticker/riser standoff test.
	# The wash sticker spans y 2.2..4.8 at ~0.155 m proud (rig_builder.gd:3582-3585 +
	# detail_decal.gd:20); the risers ride the same 0.15 standoff (rig_builder.gd:3830).
	# From the open SW deck every sightline to this face grazes the pump-room SE corner
	# post within centimetres (traced against _wall/_corner_posts geometry), so the reel
	# stands where a player would: inside the 0.86 m alley between the pump room's east
	# wall (x 18, rig_builder.gd:790) and the face, same ~10 deg graze as the south reel,
	# strafing NORTH up the alley so the 0.15 m standoff has to parallax if it is going to.
	GameClock.time_scale = 1.0
	GameClock.set_running(true)
	_set_day(0.45)
	for i in range(10):
		await get_tree().process_frame
	var west_x_expect: float = SE_LEG.x - RB.LEG_SIZE.x * 0.5   # 19.0
	var wf_hit: Dictionary = _ray(Vector3(west_x_expect - 3.0, eye_y, SE_LEG.z - 2.5),
		Vector3(west_x_expect + 2.0, eye_y, SE_LEG.z - 2.5))
	var west_x: float = west_x_expect
	if wf_hit.is_empty():
		print("[pole] WEST-PROBE MISSED — falling back to x %.2f" % west_x_expect)
	else:
		west_x = (wf_hit["position"] as Vector3).x
		print("[pole] west face plane: x %.3f on %s" % [west_x,
			str((wf_hit["collider"] as Node).get_path())])
	var weye := Vector3(west_x - 0.65, eye_y, SE_LEG.z - 2.3)
	var waim := Vector3(west_x, floor_y + 1.3, SE_LEG.z + 1.5)
	await _reel("westface", weye, waim, Vector3(0, 0, 1), 0.45)

	GameClock.set_running(true)
	GameClock.time_scale = 1.0
	print("[pole] done -> %s (%d frames)" % [_dir, _frame_i])
	get_tree().quit()
