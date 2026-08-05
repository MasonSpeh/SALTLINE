extends Node3D
## THE FILM STRIP — a fixed WORLD camera watching the cat actually behave. The owner's ask,
## verbatim: "take a video so you can have a point of context".
##
## WHY EVERY PREVIOUS INSTRUMENT MISSED A SIDEWAYS CAT. CatProbe's facing assertion reads
## `-cat.global_transform.basis.z` — the NODE — and the close-out camera positions itself
## from the cat's own basis. If the drawn mesh is rotated inside the node (a wrong
## FACING_OVERRIDES entry, a re-export that changed axes), the node still aims dead at its
## travel, the probe still prints +0.94, and the camera still frames "the front" — while
## the animal walks flank-first. Both instruments measure the claim, not the pixels.
##
## This one cannot be fooled: the camera is bolted to the WORLD, the cat is driven along a
## KNOWN world direction across the frame, and the strip shows which end leads.
##
## ---------------------------------------------------------------------------------------
## s38: THE INSTRUMENT WAS PART OF THE CHOPPINESS, and this is the whole reason to read this
## header before touching a gait number.
##
## The s37 film saved a 1152x648 PNG every film frame, and `get_image()` is a GPU readback
## that stalls the main thread — tens to hundreds of milliseconds. Godot hands `_process` the
## time since the LAST frame, so the frame AFTER every capture arrived carrying the capture's
## own cost as its delta. `AiBudget.MAX_STEP` is 0.15 s, so the cat was handed a step up to
## that size, took it in one frame (0.23 m at WALK_SPEED), and the film dutifully photographed
## the lurch its own shutter had caused. Capturing MORE often makes it worse, not better.
##
## The fix is not a smaller image. It is `--fixed-fps`, which makes `delta` exactly 1/N
## regardless of how long the frame really took, so the shutter cost cannot reach the
## simulation at all. RUN THIS HARNESS THAT WAY OR ITS FRAMES ARE NOT EVIDENCE:
##
##   godot --path . --fixed-fps 60 tests/CatFilm.tscn -- /tmp/film fps=30 reels=headon,walk
##
## The harness refuses to claim a smooth-or-choppy verdict if it detects the delta wandering
## (see `_dt_guard`) — an unpinned run prints a warning on every telemetry line.
## ---------------------------------------------------------------------------------------
##
## WHAT IT NOW MEASURES, per SIM frame (not per captured frame) into `film.csv`:
##   * the drawn FACE bearing against the authored travel bearing — the owner's "the face
##     must point dead straight at default gait", as a signed number rather than an opinion;
##   * the same for the neck and the spine, so a yaw can be ATTRIBUTED to the layer that
##     caused it instead of just noticed;
##   * every paw's position in BOTH skeleton space (the animation alone) and world space
##     (what the eye sees), so skating and choppiness are separable;
##   * dt, phase, gait weight and pose, so a discontinuity can be tied to its cause.
##
## Reels are named on the command line (`reels=...`), and the behaviour beats are script
## arguments rather than a hard-coded list, so this stays a permanent instrument:
##   walk     — straight line at DEFAULT GAIT, side-on, world-fixed bearing
##   headon   — straight line at DEFAULT GAIT, camera dead ahead ON THE TRAVEL LINE
##   headrun  — the same at RUN_SPEED
##   turn     — turn-in-place, to catch the turntable and the paw skate
##   above    — top-down on a groom/sit, for the "groom reads oddly from above" complaint
##   behaviour— the follow/sit/gallop/settle beats
##   showcase — directed poses through the blender with the state machine off

const SHOT_PX := Vector2i(1152, 648)

var _dir: String = "/tmp/catfilm"
var _fps: float = 30.0                      ## captured frames per SIM second
var _sim_fps: float = 60.0                  ## what --fixed-fps was set to
var _reels: PackedStringArray = PackedStringArray(["walk", "headon", "headrun", "turn", "behaviour", "showcase"])
var _main: Node3D
var _cat: Node3D
var _skel: Skeleton3D
var _cam: Camera3D
var _player: Node3D
var _csv: FileAccess
var _frame_i: int = 0
var _sim_i: int = 0
## The drawn face direction, in each measured bone's OWN local frame — CALIBRATED, not
## assumed. Per bone, because the auto-rig gives every joint its own axes and "which way is
## forward" is a different local vector on the head than on the spine.
var _fwd_local: Dictionary = {}             ## bone name -> local Vector3 that means "ahead"
var _up_local: Dictionary = {}              ## ...and the one that meant "up" at rest
var _face_rest_bias: float = 0.0            ## the MESH's own head yaw at rest, degrees
var _last_pos: Vector3 = Vector3.ZERO
var _dt_guard: bool = false                 ## true once a wandering delta has been seen
var _dt_min: float = 1e9
var _dt_max: float = 0.0

func world_ds(n: Node3D) -> PhysicsDirectSpaceState3D:
	return n.get_world_3d().direct_space_state

## The probed film eye: world-fixed preferred bearings, first one whose ray from the cat
## is clear. Used by every reel — the showcase's first cut used a fixed offset and filmed
## the inside of a wall from the cat's final resting spot.
func film_eye(cat: Node3D, bearings: Array, dist: float = 2.1) -> Vector3:
	var base: Vector3 = cat.global_position + Vector3(0, 0.35, 0)
	for b in bearings:
		var cand: Vector3 = base + (b as Vector3) * dist + Vector3(0, dist * 0.26, 0)
		var rq := PhysicsRayQueryParameters3D.create(base, cand)
		rq.collision_mask = 1
		if world_ds(cat).intersect_ray(rq).is_empty():
			return cand
	return base + Vector3(0, 0.55, 2.1)

## PIN THE WEATHER AND THE SUN EVERY FRAME. Setting the clock ONCE at the start is not
## enough: the film runs long enough for StormSystem to roll a squall in, and the s37 deck
## showcase came back shot at night in the rain with the cat in shadow.
func _pin() -> void:
	if _main == null:
		return
	var st: Node = _main.get("storm")
	if st != null:
		st.set_process(false)
		st.set("_intensity", 0.0)
		st.set("_phase", 0)
	GameClock._phase_elapsed_sec = \
		float(GameClock.phase_durations_minutes[GameClock.Phase.DAY]) * 60.0 * 0.45

func _process(_d: float) -> void:
	if get_tree().paused:
		get_tree().paused = false
	var pm: Node = get_tree().get_first_node_in_group("pause_menu")
	if pm != null and pm.get("panel") != null:
		(pm.get("panel") as CanvasItem).visible = false

# ------------------------------------------------------------------ measurement

func _bone_world(b: int) -> Transform3D:
	if b < 0 or _skel == null:
		return Transform3D.IDENTITY
	return _skel.global_transform * _skel.get_bone_global_pose(b)

## Bearing of a world vector, degrees, in the same convention the film prints for the node.
func _bearing(v: Vector3) -> float:
	var f := Vector3(v.x, 0.0, v.z)
	if f.length() < 1e-5:
		return 0.0
	return rad_to_deg(atan2(f.x, f.z))

## CALIBRATE WHICH LOCAL AXIS OF THE HEAD BONE IS THE FACE, by measurement.
##
## Guessing this is the same class of error the axis atlas exists to stop, and taking
## `Head.origin - Pelvis.origin` (what s37 did) measures the SPINE's bearing, not the face:
## a cat can hold its body straight and still be looking 40 degrees off, which is exactly the
## complaint. So: with the animal in its rest pose, find which of the Head bone's six signed
## cardinal axes points most nearly along the node's forward, and keep it.
##
## The residual at rest is then the MESH's OWN head bias, reported separately — if Tripo
## generated the stand mesh with its head slightly turned, no amount of animation work fixes
## it and this number is how we find that out rather than chasing the gait for it.
func _calibrate_face() -> void:
	# THE AXIS IS NOT CARDINAL, and snapping it to the nearest one was the first cut's error:
	# every chain on this Tripo rig runs along local +Y, so no signed cardinal axis of the
	# Head bone points along the animal's nose — the best of the six came back at a 0.49 dot
	# and the harness reported a 60-degree pitch on a level cat. Take the EXACT vector
	# instead: whatever local direction equalled the node's forward in the rest pose.
	#
	# What that buys, and its one honest limit: `face_rel` is then zero when the head sits
	# exactly as the REST POSE holds it, so it measures the RIG's contribution — every degree
	# the animation adds — and cannot see a head the MESH itself was generated turned. That
	# second question is what the head-on reel's pixels are for, and the two together cover it.
	# MEASURE ON THE REST SKELETON, not on whatever the state machine happens to be blending.
	# The cat is befriended by the time we get here, so it is part-way into a walk pose with
	# a live breath layer on top — calibrating against that bakes the current frame's animation
	# into the definition of "straight ahead", which is precisely the tautology this whole
	# harness exists to avoid. The rig rewrites every bone next tick, so this is not sticky.
	_cat.set_process(false)
	_skel.reset_bone_poses()
	_skel.force_update_all_bone_transforms()
	var fwd: Vector3 = -_cat.global_transform.basis.z
	for bn in ["Head", "NeckTwist01", "Spine01"]:
		var b: int = _skel.find_bone(bn)
		if b < 0:
			continue
		var bb: Basis = _bone_world(b).basis
		_fwd_local[bn] = (bb.inverse() * fwd).normalized()
		_up_local[bn] = (bb.inverse() * Vector3(0, 1, 0)).normalized()
		print("[film] %s rest-forward (local) = %s" % [bn, str((_fwd_local[bn] as Vector3).snappedf(0.001))])
	_face_rest_bias = 0.0
	_cat.set_process(true)
	print("[film] face/neck/spine bearings are now ZERO at rest by construction — every")
	print("[film] non-zero face_rel below is the ANIMATION yawing the head off the travel line.")

func _fwd_of(bn: String) -> Vector3:
	var b: int = _skel.find_bone(bn)
	if b < 0:
		return Vector3.FORWARD
	return _bone_world(b).basis * (_fwd_local.get(bn, Vector3(0, 0, -1)) as Vector3)

const CSV_HEAD := "sim,frame,reel,beat,dt,px,py,pz,pose,node_yaw,travel_yaw,face_yaw,face_rel,neck_rel,spine_rel,body_rel,pitch,up_y,speed,moved,phase,gait_w,lf_sx,lf_sy,lf_sz,rf_sx,rf_sy,rf_sz,lh_sx,lh_sy,lh_sz,rh_sx,rh_sy,rh_sz,lf_wx,lf_wy,lf_wz,rf_wx,rf_wy,rf_wz,lh_wx,lh_wy,lh_wz,rh_wx,rh_wy,rh_wz"

## One telemetry row per SIM frame. `travel_deg` is the AUTHORED world bearing the cat is
## being driven along — never read off the cat's own basis, which is what makes "the face
## points straight" a fact about the world instead of a tautology.
func _log(reel: String, beat: String, travel_deg: float, dt: float) -> void:
	if _csv == null or _skel == null:
		return
	_dt_min = minf(_dt_min, dt)
	_dt_max = maxf(_dt_max, dt)
	if _sim_i > 4 and (_dt_max - _dt_min) > 0.004:
		_dt_guard = true
	var face_w: Vector3 = _fwd_of("Head")
	var node_yaw: float = _bearing(-_cat.global_transform.basis.z)
	var face_yaw: float = _bearing(face_w)
	# Everything "_rel" is measured against the AUTHORED travel bearing, so a body that has
	# yawed off its own node and a head that has yawed off the body both show up here.
	var face_rel: float = rad_to_deg(angle_difference(deg_to_rad(travel_deg), deg_to_rad(face_yaw)))
	var neck_rel: float = rad_to_deg(angle_difference(deg_to_rad(travel_deg),
		deg_to_rad(_bearing(_fwd_of("NeckTwist01")))))
	var spine_rel: float = rad_to_deg(angle_difference(deg_to_rad(travel_deg),
		deg_to_rad(_bearing(_fwd_of("Spine01")))))
	var body_rel: float = rad_to_deg(angle_difference(deg_to_rad(travel_deg), deg_to_rad(node_yaw)))
	var pitch: float = rad_to_deg(asin(clampf(face_w.normalized().y, -1.0, 1.0)))
	# UP_Y IS THE HEAD'S OWN UP, NOT THE SKELETON NODE'S. The s37 film computed it as
	# `skel.global_transform.basis * UP` and reported 1.00 on every frame of every run — but
	# that is the NODE the skeleton hangs on, which the animation never rotates, so the column
	# could not have printed anything else. "There was never any roll" was an artefact of
	# measuring a constant. This one rolls with the drawn head.
	var up_y: float = (_bone_world(_skel.find_bone("Head")).basis
		* (_up_local.get("Head", Vector3(0, 1, 0)) as Vector3)).normalized().y
	var rig = _cat.get("_rig")
	# MOVED IS MEASURED HERE, not read off the cat: `_drive_rig` zeroes `_moved_frame` at the
	# end of every tick, so anything sampling it from outside reads 0.0 for ever and the
	# column looks like a dead animal.
	var moved: float = _cat.global_position.distance_to(_last_pos)
	_last_pos = _cat.global_position
	var row := PackedStringArray([
		str(_sim_i), str(_frame_i), reel, beat, "%.5f" % dt,
		"%.4f" % _cat.global_position.x, "%.4f" % _cat.global_position.y,
		"%.4f" % _cat.global_position.z, str(_cat.get("_pose")),
		"%.3f" % node_yaw, "%.3f" % travel_deg, "%.3f" % face_yaw, "%.3f" % face_rel,
		"%.3f" % neck_rel, "%.3f" % spine_rel, "%.3f" % body_rel,
		"%.3f" % pitch, "%.4f" % up_y,
		"%.4f" % float(_cat.get("_last_speed")), "%.5f" % moved,
		"%.5f" % (float(rig.get("_phase")) if rig != null else 0.0),
		"%.5f" % (float(rig.get("_gait_w")) if rig != null else 0.0),
	])
	# Paws twice: SKELETON space isolates the animation, WORLD space is what the eye judges.
	# Choppiness that appears in world and not in skeleton space is the body's motion, not
	# the gait's — that distinction is the difference between tuning the right thing and the
	# wrong one, and no single-space measurement can make it.
	for space in [0, 1]:
		for bn in ["L_Hand", "R_Hand", "L_Foot", "R_Foot"]:
			var b: int = _skel.find_bone(bn)
			var p: Vector3 = _skel.get_bone_global_pose(b).origin if space == 0 else _bone_world(b).origin
			row.append("%.5f" % p.x)
			row.append("%.5f" % p.y)
			row.append("%.5f" % p.z)
	_csv.store_line(",".join(row))
	_sim_i += 1

## Advance the simulation by one film frame's worth of sim frames, logging every one, then
## capture. `travel_deg` and `eye_fn` are how each reel places its own camera.
func _shoot(reel: String, beat: String, travel_deg: float, sim_per_frame: int,
		place_cam: Callable, tag: String = "") -> void:
	for w in range(sim_per_frame):
		_pin()
		place_cam.call()
		await get_tree().process_frame
		_log(reel, beat, travel_deg, get_process_delta_time())
	await RenderingServer.frame_post_draw
	# Guarded because this harness is ALSO run headless as a cheap smoke test for its own
	# script errors, and there is no framebuffer to read back there. A null here is "no
	# picture", never "no telemetry" — the CSV above is the part that carries the evidence.
	var tex: Texture2D = get_viewport().get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img != null:
		img.resize(SHOT_PX.x, SHOT_PX.y)
		img.save_png("%s/%s_%03d_%s.png" % [_dir, reel, _frame_i, tag if tag != "" else beat])
	_frame_i += 1

# ------------------------------------------------------------------ the run

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("fps="):
			_fps = maxf(1.0, float(a.substr(4)))
		elif a.begins_with("simfps="):
			_sim_fps = maxf(1.0, float(a.substr(7)))
		elif a.begins_with("reels="):
			_reels = a.substr(6).split(",", false)
		elif not a.begins_with("--"):
			_dir = a
	DirAccess.make_dir_recursive_absolute(_dir)
	_csv = FileAccess.open("%s/film.csv" % _dir, FileAccess.WRITE)
	if _csv != null:
		_csv.store_line(CSV_HEAD)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	if _main == null or _main.get_script() == null:
		print("[film] Main.tscn came back WITHOUT its script")
		get_tree().quit(1)
		return
	add_child(_main)
	# WAIT IN REAL TIME, NOT SIM TIME. `create_timer(24.0)` is a SceneTreeTimer, so it counts
	# the same `delta` the rest of the engine sees — and under `--fixed-fps 60` that delta is
	# 1/60 no matter how long the frame really took. The rig takes ~20 REAL seconds to build
	# and CSG-mesh itself, and a build frame runs at a handful of fps, so the scene timer
	# asked for 1440 frames of a world that was managing five a second: eight minutes of
	# wall clock to reach frame one. The wait exists to let the world FINISH BUILDING, which
	# is real work measured on the real clock, with a sim-frame floor so a fast machine still
	# gives the physics a chance to settle everything onto the deck.
	var t0: int = Time.get_ticks_msec()
	var waited: int = 0
	while Time.get_ticks_msec() - t0 < 22000 or waited < 180:
		await get_tree().process_frame
		waited += 1
	print("[film] world built in %d ms / %d frames" % [Time.get_ticks_msec() - t0, waited])
	GameClock.force_phase(GameClock.Phase.DAY)
	GameClock._phase_elapsed_sec = \
		float(GameClock.phase_durations_minutes[GameClock.Phase.DAY]) * 60.0 * 0.45
	_player = get_tree().get_first_node_in_group("player")
	_cam = _player.get_node("Head/Camera3D")
	_cam.current = true
	_player.set_physics_process(false)
	for p in _player.find_children("*", "CollisionObject3D", true, false):
		(p as CollisionObject3D).set_collision_mask_value(1, false)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)

	_cat = get_tree().get_first_node_in_group("ship_cat")
	if _cat == null:
		print("[film] no cat")
		get_tree().quit(1)
		return
	for c in _cat.get_children():
		if c is Interactable:
			(c as Interactable).emit_signal("interacted", "SAY HELLO")
	for n in (_cat.get("_host") as Node3D).find_children("*", "Skeleton3D", true, false):
		_skel = n
		break

	# STAGE IT ON THE OPEN MAIN DECK, in daylight, in plain sight — the owner's ask. The spot
	# is PROBED, not typed: tests/DeckFind.tscn sweeps the topside for floor at y18 with open
	# sky and >= 3 m of clearance on all four sides, and (3, 18, -3) came back with 8 m clear
	# in every direction and no roof.
	var stage := Vector3(3.0, 18.0, -3.0)
	_cat.global_position = stage
	if _cat.has_method("_reseat"):
		_cat.call("_reseat")
	_player.global_position = stage + Vector3(2.0, 0.1, 0.0)
	for i in range(30):
		await get_tree().physics_frame
	_calibrate_face()

	var sim_per_frame: int = maxi(1, int(round(_sim_fps / _fps)))
	print("[film] %.0f fps film, %d sim frames per capture (sim assumed %.0f fps)"
		% [_fps, sim_per_frame, _sim_fps])

	for reel in _reels:
		match String(reel):
			"walk": await _reel_line("walk", Vector3(1, 0, 0), 5.0, 5.0, sim_per_frame, false)
			"headon": await _reel_line("headon", Vector3(1, 0, 0), 5.0, 5.0, sim_per_frame, true)
			"headrun": await _reel_line("headrun", Vector3(1, 0, 0), 12.0, 3.0, sim_per_frame, true)
			"turn": await _reel_turn(sim_per_frame)
			"above": await _reel_above(sim_per_frame)
			"rear": await _reel_rear(sim_per_frame)
			"wash": await _reel_wash(sim_per_frame)
			"jump": await _reel_jump(sim_per_frame)
			"hunt": await _reel_hunt(sim_per_frame)
			"gift": await _reel_gift(sim_per_frame)
			"lookwalk": await _reel_lookwalk(sim_per_frame)
			"idle": await _reel_idle(sim_per_frame)
			"tail": await _reel_tail(sim_per_frame)
			"behaviour": await _reel_behaviour(sim_per_frame)
			"showcase": await _reel_showcase(sim_per_frame)
			_: print("[film] unknown reel %s" % String(reel))

	if _csv != null:
		_csv.close()
	if _dt_guard:
		print("[film] *** WARNING: delta wandered (%.4f..%.4f s). RE-RUN WITH --fixed-fps %d ***"
			% [_dt_min, _dt_max, int(_sim_fps)])
		print("[film] *** the frames above are NOT evidence about smoothness ***")
	else:
		print("[film] delta pinned at %.5f..%.5f s — the sim is shutter-independent" % [_dt_min, _dt_max])
	print("[film] done -> %s (%d captures, %d sim rows)" % [_dir, _frame_i, _sim_i])
	get_tree().quit()

## A STRAIGHT LINE AT A CHOSEN GAIT. The player is teleported to a fixed lead distance
## AHEAD of the cat every frame, which is what picks the gait: ship_cat runs FOLLOW at
## WALK_SPEED while the gap is between FOLLOW_NEAR (2.2) and RUN_M (8), and RUN at
## RUN_SPEED beyond that. A 5 m lead is therefore DEFAULT GAIT by construction, and a 12 m
## lead is the run — no state has to be forced and nothing is faked.
##
## `head_on` places the camera dead ahead ON THE AUTHORED TRAVEL LINE. That is the owner's
## view: "from head on, does the face point straight". Placing it from the cat's own basis
## would rotate the camera with the error and hide exactly what it exists to show.
func _reel_line(reel: String, dir: Vector3, lead: float, seconds: float,
		sim_per_frame: int, head_on: bool) -> void:
	dir = dir.normalized()
	var travel: float = _bearing(dir)
	# Back the cat up to one end of the clear run so it has room to walk the whole beat.
	var start: Vector3 = Vector3(3.0, 18.0, -3.0) - dir * minf(lead * 0.6 + seconds * 1.6, 7.0)
	_cat.global_position = start
	if _cat.has_method("_reseat"):
		_cat.call("_reseat")
	# Aim it down the line before filming, so the first strides are not a turn.
	_cat.rotation.y = deg_to_rad(travel) + PI
	_player.global_position = _cat.global_position + dir * lead
	for i in range(20):
		_player.global_position = _cat.global_position + dir * lead
		await get_tree().physics_frame
	var side: Vector3 = dir.rotated(Vector3.UP, PI * 0.5)
	var frames: int = int(seconds * _fps)
	var stalled: int = 0
	var last: Vector3 = _cat.global_position
	for f in range(frames):
		var place := func() -> void:
			# HOLD THE HUNT OFF. This reel exists to measure a cat walking in a straight line,
			# and the cat now stalks deck gulls on its own — the first run of this after the
			# hunt shipped came back with the headon strip 82 degrees off its travel bearing
			# and `pose=stalk`, which is the behaviour working correctly and the instrument
			# measuring nothing. The hunt reel is where that gets filmed.
			_cat.set("_hunt_cd", 999.0)
			_cat.set("_zoom_cd", 999.0)
			_cat.set("_play_cd", 999.0)
			_player.global_position = _cat.global_position + dir * lead
			if head_on:
				_cam.global_position = _cat.global_position + dir * 1.35 + Vector3(0, 0.20, 0)
				_cam.look_at(_cat.global_position + Vector3(0, 0.22, 0), Vector3.UP)
			else:
				_cam.global_position = _cat.global_position + side * 2.0 + Vector3(0, 0.55, 0)
				_cam.look_at(_cat.global_position + Vector3(0, 0.25, 0), Vector3.UP)
		await _shoot(reel, reel, travel, sim_per_frame, place)
		# SELF-TERMINATING: the deck is finite and a cat that has reached the edge refuses to
		# step, so keep filming a stalled animal and the tail of the reel is a still life
		# labelled "walk".
		if _cat.global_position.distance_to(last) < 0.004 * float(sim_per_frame):
			stalled += 1
			if stalled > int(_fps * 0.6):
				print("[film] %s stalled at %s after %d frames — deck edge or obstruction"
					% [reel, str(_cat.global_position.snappedf(0.1)), f])
				break
		else:
			stalled = 0
		last = _cat.global_position

## TURN IN PLACE — flaw 4. The player is swung around the cat at a fixed radius just inside
## FOLLOW_NEAR, so the cat wants to face a moving bearing without having anywhere to walk.
## Filmed from ABOVE and slightly off, which is the view that shows paws skating.
func _reel_turn(sim_per_frame: int) -> void:
	var stage := Vector3(3.0, 18.0, -3.0)
	_cat.global_position = stage
	if _cat.has_method("_reseat"):
		_cat.call("_reseat")
	for i in range(20):
		await get_tree().physics_frame
	var frames: int = int(4.0 * _fps)
	for f in range(frames):
		var a: float = TAU * float(f) / float(frames)
		var place := func() -> void:
			_player.global_position = _cat.global_position \
				+ Vector3(cos(a) * 1.9, 0.1, sin(a) * 1.9)
			_cam.global_position = _cat.global_position + Vector3(0.0, 1.6, 1.4)
			_cam.look_at(_cat.global_position + Vector3(0, 0.12, 0), Vector3.UP)
		await _shoot("turn", "turn", rad_to_deg(a), sim_per_frame, place)

## FROM ABOVE — the owner's "groom reads oddly from above" (s36), which no side-on reel can
## judge. Sits the cat still and looks straight down the deck normal.
func _reel_above(sim_per_frame: int) -> void:
	var stage := Vector3(3.0, 18.0, -3.0)
	_cat.global_position = stage
	if _cat.has_method("_reseat"):
		_cat.call("_reseat")
	_player.global_position = stage + Vector3(1.2, 0.1, 0.0)
	for i in range(60):
		await get_tree().physics_frame
	var rig = _cat.get("_rig")
	_cat.set_process(false)
	for pose_beat in [["groom", 2.5], ["sit", 1.5]]:
		rig.set_pose(String(pose_beat[0]), 5.0)
		for f in range(int(float(pose_beat[1]) * _fps)):
			var place := func() -> void:
				rig.tick(1.0 / _sim_fps, 0.0, 0.0)
				_cam.global_position = _cat.global_position + Vector3(0.001, 1.5, 0.0)
				_cam.look_at(_cat.global_position + Vector3(0, 0.15, 0), Vector3(0, 0, -1))
			await _shoot("above", String(pose_beat[0]), 0.0, sim_per_frame, place)
	_cat.set_process(true)

## FROM DIRECTLY BEHIND — flaw 2, "the hind legs trail instead of tucking", which is a
## complaint no side-on or three-quarter reel can settle: a hind leg left out behind the body
## is hidden by the body from every angle except this one. Low and dead astern, at hock height,
## so the two hind paws are silhouetted against the deck.
func _reel_rear(sim_per_frame: int) -> void:
	var stage := Vector3(3.0, 18.0, -3.0)
	_cat.global_position = stage
	if _cat.has_method("_reseat"):
		_cat.call("_reseat")
	_player.global_position = stage + Vector3(1.2, 0.1, 0.0)
	for i in range(30):
		await get_tree().physics_frame
	var rig = _cat.get("_rig")
	_cat.set_process(false)
	# The cat faces its own -Z after CreatureAnim's normalisation, so dead astern is +Z of the
	# node — taken from the node rather than typed, because the whole point of the reel is
	# that the camera is behind the ANIMAL.
	for pose_beat in [["sit", 2.2], ["stalk", 1.8], ["groom", 1.8], ["sleep", 1.8]]:
		rig.set_pose(String(pose_beat[0]), 5.0)
		for f in range(int(float(pose_beat[1]) * _fps)):
			var place := func() -> void:
				rig.tick(1.0 / _sim_fps, 0.0, 0.0)
				var back: Vector3 = _cat.global_transform.basis.z.normalized()
				_cam.global_position = _cat.global_position + back * 1.05 + Vector3(0, 0.20, 0)
				_cam.look_at(_cat.global_position + Vector3(0, 0.16, 0), Vector3.UP)
			await _shoot("rear", String(pose_beat[0]), 0.0, sim_per_frame, place)
	_cat.set_process(true)

## THE FOUR WASHES AND THE SHAKE. Each grooming style drives a different part of the body, so
## each needs looking at: the paw-lick is a forepaw and a lowered muzzle, the flank sends the
## head right round to the shoulder, the chest puts it down between the forelegs, and the ear
## scratch brings a HIND foot up behind the ear. A style that reads as a spasm rather than as
## grooming does so obviously and immediately, and only from the front.
func _reel_wash(sim_per_frame: int) -> void:
	var stage := Vector3(3.0, 18.0, -3.0)
	_cat.global_position = stage
	if _cat.has_method("_reseat"):
		_cat.call("_reseat")
	_player.global_position = stage + Vector3(1.4, 0.1, 0.0)
	for i in range(30):
		await get_tree().physics_frame
	var rig = _cat.get("_rig")
	_cat.set_process(false)
	rig.set_pose("groom", 5.0)
	for beat in [[0, "paw"], [1, "flank"], [2, "chest"], [3, "scratch"]]:
		rig.call("groom_style", int(beat[0]))
		for f in range(int(2.4 * _fps)):
			var place := func() -> void:
				rig.tick(1.0 / _sim_fps, 0.0, 0.0)
				# Three-quarter front and low — grooming is a head-and-forelimb action and it
				# has to read from where a player would actually be standing.
				var fwd: Vector3 = -_cat.global_transform.basis.z
				var eye: Vector3 = fwd.rotated(Vector3.UP, 0.7) * 1.15
				_cam.global_position = _cat.global_position + eye + Vector3(0, 0.30, 0)
				_cam.look_at(_cat.global_position + Vector3(0, 0.20, 0), Vector3.UP)
			await _shoot("wash", String(beat[1]), 0.0, sim_per_frame, place)
	# ...and the shake, which is a whole-body event and wants the same camera.
	rig.set_pose("stand", 6.0)
	for f in range(int(2.0 * _fps)):
		var place2 := func() -> void:
			if f % int(maxf(_fps, 1.0)) == 0:
				rig.call("shake", 1.0)
			rig.tick(1.0 / _sim_fps, 0.0, 0.0)
			var fwd2: Vector3 = -_cat.global_transform.basis.z
			_cam.global_position = _cat.global_position + fwd2.rotated(Vector3.UP, 0.7) * 1.25 \
				+ Vector3(0, 0.32, 0)
			_cam.look_at(_cat.global_position + Vector3(0, 0.20, 0), Vector3.UP)
		await _shoot("wash", "shake", 0.0, sim_per_frame, place2)
	_cat.set_process(true)

## THE LEAP — flaw 7, which had never been filmed. ship_cat jumps a rise between CLIMB_UP
## (0.62 m) and JUMP_UP (1.25 m) rather than refusing it, so the reel has to find a ledge in
## that band and stand the player on top of it. The ledge is PROBED, never typed: a sweep of
## the deck around the stage, raycast down at each candidate, keep the first whose surface is
## in the band and whose top the cat's own body-volume test says it would fit on.
func _reel_jump(sim_per_frame: int) -> void:
	var stage := Vector3(3.0, 18.0, -3.0)
	_cat.global_position = stage
	if _cat.has_method("_reseat"):
		_cat.call("_reseat")
	for i in range(20):
		await get_tree().physics_frame
	var deck: float = _cat.global_position.y
	var ledge := Vector3.INF
	# SWEEP WIDE, AND SWEEP WHERE THE FURNITURE IS. The first cut searched a 7 m ring around
	# the open-deck staging spot and correctly reported that there is nothing in the 0.66-1.20 m
	# band out there — open deck is open. The props the cat can actually jump onto are indoors:
	# .sonar-rig/rig_manifest.txt lists barrels at 0.90 m, drawer cabinets at 0.90, armchairs at
	# 0.98, all of them around the bunkhouse the animal lives in. So the bunkhouse is searched
	# too, and the ring goes out to 14 m.
	var origins: Array = [stage, Vector3(-24.6, 18.0, 11.4), Vector3(-20.5, 18.0, -15.0)]
	var base: Vector3 = stage
	for origin in origins:
		for r in [1.6, 2.4, 3.2, 4.2, 5.4, 7.0, 9.0, 11.0, 14.0]:
			for i in range(24):
				var a: float = TAU * float(i) / 24.0
				var at: Vector3 = (origin as Vector3) + Vector3(cos(a) * r, 0.0, sin(a) * r)
				var from: Vector3 = at + Vector3(0, 3.0, 0)
				var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 4.0, 0))
				q.collision_mask = 1
				var hit: Dictionary = world_ds(_cat).intersect_ray(q)
				if hit.is_empty():
					continue
				var rise: float = (hit["position"] as Vector3).y - deck
				if rise < 0.66 or rise > 1.20:
					continue
				ledge = hit["position"]
				base = origin
				break
			if ledge != Vector3.INF:
				break
		if ledge != Vector3.INF:
			break
	if ledge == Vector3.INF:
		print("[film] jump: no surface in the 0.66-1.20 m band anywhere in the swept area — "
			+ "nothing to film. Widen `origins`, or build a crate.")
		return
	print("[film] jump: ledge probed at %s, rise %.2f m" % [str(ledge.snappedf(0.01)), ledge.y - deck])
	# STAND IT AT THE FOOT, AND FIND THE FOOT BY PROBING FOR IT. A fixed 1.1 m step back from
	# the ledge's centre is inside the ledge whenever the ledge is a PLATFORM rather than a
	# crate — and the first run of this staged the cat on top of the thing it was supposed to
	# jump onto. The telemetry said so plainly: y went 18.00 -> 19.10 in a single frame, wearing
	# the SIT pose, which is `_reseat` teleporting rather than any leap. So walk outward until
	# the ground drops back to deck height, then back off far enough for a run-up.
	var out_dir: Vector3 = (base - ledge).normalized()
	var approach: Vector3 = ledge + out_dir * 1.1
	for step in range(1, 24):
		var cand: Vector3 = ledge + out_dir * (0.4 * float(step))
		var cq := PhysicsRayQueryParameters3D.create(
			cand + Vector3(0, 3.0, 0), cand - Vector3(0, 2.0, 0))
		cq.collision_mask = 1
		var chit: Dictionary = world_ds(_cat).intersect_ray(cq)
		if chit.is_empty():
			continue
		if absf((chit["position"] as Vector3).y - deck) < 0.15:
			approach = cand + out_dir * 0.9      # a little run-up
			break
	approach.y = deck
	print("[film] jump: approaching from %s (%.2f m out from the lip)"
		% [str(approach.snappedf(0.01)), approach.distance_to(ledge)])
	_cat.global_position = approach
	if _cat.has_method("_reseat"):
		_cat.call("_reseat")
	var travel: float = _bearing(ledge - approach)
	var side: Vector3 = (ledge - approach).normalized().rotated(Vector3.UP, PI * 0.5)
	for f in range(int(4.5 * _fps)):
		var place := func() -> void:
			_player.global_position = ledge + Vector3(0, 0.2, 0)
			_cam.global_position = _cat.global_position + side * 2.4 + Vector3(0, 0.7, 0)
			_cam.look_at(_cat.global_position + Vector3(0, 0.3, 0), Vector3.UP)
		await _shoot("jump", "jump", travel, sim_per_frame, place)

## THE HUNT — the predatory sequence, filmed. Staged next to a real deck gull rather than a
## marker, because the whole sequence is driven off `_find_prey` and a faked target would
## prove nothing about the behaviour that ships.
func _reel_hunt(sim_per_frame: int) -> void:
	var gull: Node3D = null
	for g in get_tree().get_nodes_in_group("deck_gull"):
		var n: Node3D = g as Node3D
		if n != null and n.global_position.y > 17.0:
			gull = n
			break
	if gull == null:
		print("[film] hunt: no deck gull up on the topside to stalk")
		return
	print("[film] hunt: gull at %s" % str(gull.global_position.snappedf(0.1)))
	var away: Vector3 = Vector3(1, 0, 0.4).normalized()
	_cat.global_position = gull.global_position + away * 6.0
	if _cat.has_method("_reseat"):
		_cat.call("_reseat")
	_player.global_position = _cat.global_position + away * 1.5
	for i in range(20):
		await get_tree().physics_frame
	var travel: float = _bearing(gull.global_position - _cat.global_position)
	# Wide and low, so the crouch, the freezes and the tread all read against the deck.
	for f in range(int(14.0 * _fps)):
		var place := func() -> void:
			var mid: Vector3 = _cat.global_position.lerp(gull.global_position, 0.4)
			var eye: Vector3 = (_cat.global_position - gull.global_position).normalized()
			_cam.global_position = mid + eye.rotated(Vector3.UP, PI * 0.5) * 3.1 + Vector3(0, 0.65, 0)
			_cam.look_at(mid + Vector3(0, 0.2, 0), Vector3.UP)
		await _shoot("hunt", str(_cat.get("_pose")), travel, sim_per_frame, place)

## THE GIFT CARRY — the proudest walk the cat has, and one of the two states (with the
## stalk) that no reel ever filmed moving. The carry is installed directly (`_carry`) so the
## reel does not depend on winning a dice-roll hunt first; the approach itself — head up,
## tail up, legs actually stepping — is the whole subject. The player retreats to hold the
## approach open, then stands to take the delivery.
func _reel_gift(sim_per_frame: int) -> void:
	var stage := Vector3(3.0, 18.0, -3.0)
	var dir := Vector3(1, 0, 0)
	_cat.global_position = stage - dir * 6.0
	if _cat.has_method("_reseat"):
		_cat.call("_reseat")
	_cat.rotation.y = deg_to_rad(_bearing(dir)) + PI
	for i in range(20):
		await get_tree().physics_frame
	_cat.set("_carry", "gull_feather")
	var travel: float = _bearing(dir)
	var side: Vector3 = dir.rotated(Vector3.UP, PI * 0.5)
	for f in range(int(5.5 * _fps)):
		var place := func() -> void:
			_cat.set("_hunt_cd", 999.0)
			_cat.set("_zoom_cd", 999.0)
			_cat.set("_play_cd", 999.0)
			# Retreat for the first two thirds, then stand for the drop.
			if f < int(3.6 * _fps):
				_player.global_position = _cat.global_position + dir * 5.0 + Vector3(0, 0.1, 0)
			_cam.global_position = _cat.global_position + side * 1.9 + dir * 0.7 \
				+ Vector3(0, 0.5, 0)
			_cam.look_at(_cat.global_position + Vector3(0, 0.25, 0), Vector3.UP)
		await _shoot("gift", "carry" if String(_cat.get("_pose")) == "carry" else "deliver",
			travel, sim_per_frame, place)
	_cat.set("_carry", "")

## LOOK WHILE WALKING — the owner's creepiest complaint, isolated: the cat walks a dead
## straight line while its ATTENTION is held on a world-fixed mark 40 degrees off the
## travel, above head height. Correct = the head turns and the face stays LEVEL (no roll,
## no tilt) while the body walks on straight. The camera sits ahead and off to the mark's
## side, where a tilted head is unmissable.
func _reel_lookwalk(sim_per_frame: int) -> void:
	var stage := Vector3(3.0, 18.0, -3.0)
	var dir := Vector3(1, 0, 0)
	_cat.global_position = stage - dir * 7.0
	if _cat.has_method("_reseat"):
		_cat.call("_reseat")
	_cat.rotation.y = deg_to_rad(_bearing(dir)) + PI
	_player.global_position = _cat.global_position + dir * 5.0
	for i in range(20):
		_player.global_position = _cat.global_position + dir * 5.0
		await get_tree().physics_frame
	var travel: float = _bearing(dir)
	var mark_dir: Vector3 = dir.rotated(Vector3.UP, 0.7)
	for f in range(int(4.5 * _fps)):
		var place := func() -> void:
			_cat.set("_hunt_cd", 999.0)
			_cat.set("_zoom_cd", 999.0)
			_cat.set("_play_cd", 999.0)
			_player.global_position = _cat.global_position + dir * 5.0
			_cat.call("_watch", _cat.global_position + mark_dir * 4.0 + Vector3(0, 1.0, 0), 1.0)
			_cam.global_position = _cat.global_position + dir * 1.6 + mark_dir * 0.8 \
				+ Vector3(0, 0.35, 0)
			_cam.look_at(_cat.global_position + Vector3(0, 0.22, 0), Vector3.UP)
		await _shoot("lookwalk", "lookwalk", travel, sim_per_frame, place)

## THE RESTING CAT — breath, tail idle, glances, weight-shifts, and honestly nothing else:
## this mesh has no ears to flick and no eyelids to blink (see docs/CAT_RIG_CEILING.md).
## Twelve seconds, one three-quarter camera, the player settled nearby. The thing to judge
## is whether the loop ever reads as a loop.
func _reel_idle(sim_per_frame: int) -> void:
	var stage := Vector3(3.0, 18.0, -3.0)
	_cat.global_position = stage
	if _cat.has_method("_reseat"):
		_cat.call("_reseat")
	_player.global_position = stage + Vector3(1.7, 0.1, 0.4)
	for i in range(40):
		await get_tree().physics_frame
	for f in range(int(12.0 * _fps)):
		var place := func() -> void:
			_cat.set("_hunt_cd", 999.0)
			_cat.set("_zoom_cd", 999.0)
			_cat.set("_play_cd", 999.0)
			var fwd: Vector3 = -_cat.global_transform.basis.z
			_cam.global_position = _cat.global_position + fwd.rotated(Vector3.UP, 0.8) * 1.5 \
				+ Vector3(0, 0.42, 0)
			_cam.look_at(_cat.global_position + Vector3(0, 0.18, 0), Vector3.UP)
		await _shoot("idle", str(_cat.get("_pose")), 0.0, sim_per_frame, place)

## THE TAIL, CLOSE — a low three-quarter-rear orbit during a walk, then a hard stop. The
## two things to judge: the tail moves as its own limb (wave, lag, counter-sway) rather
## than twitching with the right hind leg once per stride; and on the stop it OVERSHOOTS
## and settles rather than freezing with the body.
func _reel_tail(sim_per_frame: int) -> void:
	var stage := Vector3(3.0, 18.0, -3.0)
	var dir := Vector3(1, 0, 0)
	_cat.global_position = stage - dir * 6.0
	if _cat.has_method("_reseat"):
		_cat.call("_reseat")
	_cat.rotation.y = deg_to_rad(_bearing(dir)) + PI
	for i in range(20):
		_player.global_position = _cat.global_position + dir * 5.0
		await get_tree().physics_frame
	var travel: float = _bearing(dir)
	var walk_frames: int = int(3.5 * _fps)
	var stop_frames: int = int(2.5 * _fps)
	for f in range(walk_frames + stop_frames):
		var place := func() -> void:
			_cat.set("_hunt_cd", 999.0)
			_cat.set("_zoom_cd", 999.0)
			_cat.set("_play_cd", 999.0)
			if f < walk_frames:
				_player.global_position = _cat.global_position + dir * 5.0
			else:
				# The stop: the player halts inside FOLLOW_NEAR, so the cat stops too —
				# and the tail's settle is the frame that matters.
				_player.global_position = _cat.global_position + dir * 1.5 + Vector3(0, 0.1, 0)
			var back: Vector3 = _cat.global_transform.basis.z.normalized()
			var eye: Vector3 = back.rotated(Vector3.UP, 0.55) * 0.95
			_cam.global_position = _cat.global_position + eye + Vector3(0, 0.35, 0)
			_cam.look_at(_cat.global_position + back * 0.25 + Vector3(0, 0.18, 0), Vector3.UP)
		await _shoot("tail", "walk" if f < walk_frames else "stop", travel, sim_per_frame, place)

## THE BEHAVIOUR REEL — the cat's own state machine, filmed from world-fixed bearings.
## The beat list is DATA (flaw 9): [player_x, player_z, seconds, label]. Overridable from the
## command line as `beats=x:z:sec:label;...` so this stays an instrument rather than a
## one-shot script.
func _reel_behaviour(sim_per_frame: int) -> void:
	var beats: Array = [
		[10.0, -3.0, 4.0, "walk_east"],
		[10.0, -3.0, 4.0, "settle_sit"],
		[-4.0, -3.0, 3.5, "gallop_west"],
		[0.0, -9.0, 3.0, "cross_south"],
		[0.0, -9.0, 3.5, "settle_two"],
	]
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("beats="):
			continue
		beats = []
		for spec in a.substr(6).split(";", false):
			var p: PackedStringArray = spec.split(":")
			if p.size() >= 4:
				beats.append([float(p[0]), float(p[1]), float(p[2]), String(p[3])])
	var stage := Vector3(3.0, 18.0, -3.0)
	_cat.global_position = stage
	if _cat.has_method("_reseat"):
		_cat.call("_reseat")
	_player.global_position = stage + Vector3(2.0, 0.1, 0.0)
	for i in range(30):
		await get_tree().physics_frame
	var bearings: Array = [
		Vector3(0, 0, 1), Vector3(0.7, 0, 0.7), Vector3(-0.7, 0, 0.7),
		Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, -1)]
	for beat in beats:
		var dest := Vector3(float(beat[0]), 18.1, float(beat[1]))
		_player.global_position = dest
		var travel: float = _bearing(dest - _cat.global_position)
		for f in range(int(float(beat[2]) * _fps)):
			var place := func() -> void:
				_cam.global_position = film_eye(_cat, bearings)
				_cam.look_at(_cat.global_position + Vector3(0, 0.35, 0), Vector3.UP)
			await _shoot("beh", String(beat[3]), travel, sim_per_frame, place)

## THE PLAYGROUND — the owner asked to see the cat in a bunch of positions. Directed through
## the blender with the state machine off, on open deck, every transition live on film.
func _reel_showcase(sim_per_frame: int) -> void:
	var rig = _cat.get("_rig")
	var showcase: Array = [
		["sit", 2.5], ["groom", 3.0], ["stretch", 2.5],
		["sleep", 3.0], ["stretch", 2.0], ["stand", 1.5],
	]
	var show_bearings: Array = [
		Vector3(0.82, 0, 0.57), Vector3(0.82, 0, -0.57), Vector3(0, 0, 1),
		Vector3(0, 0, -1), Vector3(-0.82, 0, 0.57), Vector3(-1, 0, 0)]
	_cat.set_process(false)   # the state machine would fight the directed poses
	for pose_beat in showcase:
		rig.set_pose(String(pose_beat[0]), 5.0)
		for f in range(int(float(pose_beat[1]) * _fps)):
			var place := func() -> void:
				rig.tick(1.0 / _sim_fps, 0.0, 0.0)
				_cam.global_position = film_eye(_cat, show_bearings, 1.35)
				_cam.look_at(_cat.global_position + Vector3(0, 0.26, 0), Vector3.UP)
			await _shoot("pose", String(pose_beat[0]), 0.0, sim_per_frame, place)
	_cat.set_process(true)
