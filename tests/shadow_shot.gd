extends Node
## Visual check on the sun's shadow quality and budget. Run WINDOWED (and --always-on-top:
## an occluded window presents nothing and saves black or stale frames).
##
##   godot --path . --resolution 1280x720 --always-on-top res://tests/ShadowShot.tscn -- matrix
##   godot --path . --resolution 1280x720 --always-on-top res://tests/ShadowShot.tscn -- dusk
##   godot --path . --resolution 1280x720 --always-on-top res://tests/ShadowShot.tscn -- shot after
##
## MATRIX mode is the one that settles arguments. It boots the world ONCE, parks the camera
## on the open deck, and then re-shoots the SAME frame under a list of candidate shadow
## configurations applied at runtime — so every difference between two PNGs is the setting
## and nothing else (same sun angle, same sea state, same streamed dressing). It prints fps
## and draw calls per config, because on this renderer map resolution is nearly free and
## caster count is not, and the two have to be reported together.
##
## Several entries in the matrix exist only to prove a NEGATIVE — that a knob the project
## currently spends words on does nothing on gl_compatibility. Those pairs (B vs A, D vs E)
## must be compared as images; if the PNGs are byte-identical the setting is inert here.
##
## SHOT mode takes the single canonical deck frame under whatever the project currently
## configures — that is the before/after pair.
##
## DUSK mode is the original transition guard: sun_controller.gd switches the whole cascade
## off under 0.03 energy and back on over 0.08, and walking the sun down must not show a
## frame where shadows visibly snap out.
##
## Saves to /tmp/shadowfix/ (matrix, shot) or /tmp/shadow_<phase>.png (dusk).

const OUT_DIR: String = "/tmp/shadowfix"
## Two crop windows over the canonical frame, upscaled NEAREST so a shadow-map texel is
## countable by eye in the saved PNG rather than being a claim a reviewer has to take on
## trust. DECK is the long shallow shadow boundary running across the sunlit plating —
## the worst case, because a near-horizontal edge exposes the full width of a shadow texel.
## WALL is the stair-stringer shadow thrown onto the white bulkhead, where the staircase is
## unmistakable against a flat unlit surface.
const CROP_DECK: Rect2i = Rect2i(140, 330, 430, 240)
const CROP_DECK_ZOOM: int = 3
const CROP_WALL: Rect2i = Rect2i(680, 258, 190, 105)
const CROP_WALL_ZOOM: int = 6

## Window the blockiness METRIC scans: a stretch of the deck shadow boundary that is
## shallow in y (a few pixels of rise across many columns), so a perfectly resolved edge
## would step about every 2 px and a blocky one steps every shadow texel.
const EDGE_X: Vector2i = Vector2i(170, 430)
const EDGE_Y: Vector2i = Vector2i(345, 545)

var main: Node3D
var sun: DirectionalLight3D

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "shot"
	var tag: String = args[1] if args.size() > 1 else "current"

	_api_audit()

	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(30.0).timeout
	main._countdown = 0.0
	main.hud.fade_rect.color.a = 0.0
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	# The moon is a DirectionalLight3D too and it is added second; take the one that is
	# actually lighting the scene, not whichever comes first in the child list.
	for c in main.get_children():
		if c is DirectionalLight3D and (c as DirectionalLight3D).shadow_enabled:
			sun = c
			break
	if sun == null:
		for c in main.get_children():
			if c is DirectionalLight3D:
				sun = c
				break
	_park_camera()
	_kill_pause()

	match mode:
		"matrix":
			await _freeze()
			await _matrix()
		"dusk":
			await _dusk()
		_:
			await _single(tag)
	get_tree().quit()

## PauseMenu opens itself on NOTIFICATION_APPLICATION_FOCUS_OUT, and a screenshot harness is
## by definition running unattended in a window nobody is clicking on. Every frame of the
## first frozen matrix came back with the pause panel across the middle of it and the whole
## scene dimmed behind the overlay — a completely valid A/B, of the wrong picture. Delete
## the node rather than trying to out-race the notification: nothing in a capture run needs
## it, and leaving it alive means one stray focus event silently invalidates the evidence.
func _kill_pause() -> void:
	for c in main.get_children():
		if c is PauseMenu:
			c.queue_free()
	get_tree().paused = false

## MATRIX ONLY. A config that takes four seconds to shoot is four seconds in which the sun
## moves, a squall rolls in and the snail walks — and the first run of this matrix produced
## a pair of "identical" frames differing by 5/255 per pixel from drift alone, against a
## 12/255 signal from the settings themselves. That is not a controlled experiment.
##
## Three things get nailed down, in this order:
##   * the WEATHER, because StormSystem had genuinely dropped a squall on the rig halfway
##     through the first matrix and darkened every config after it;
##   * the CLOCK, because the sun is what casts the shadow being measured;
##   * ENGINE time, which stops physics, fauna and every _process in the game.
## Shader TIME keeps running (it comes from the rendering server, not the scene tree), so
## the sea and the creature vertex shaders still move; the diff windows used to compare
## these PNGs must sit on static geometry. Deck plating and bulkhead qualify.
func _freeze() -> void:
	for c in main.get_children():
		if c.get_script() != null and String(c.get_script().resource_path).ends_with("storm_system.gd"):
			c.process_mode = Node.PROCESS_MODE_DISABLED
	if main.sun_ctl != null:
		main.sun_ctl.set_storm(0.0)
		if main.sun_ctl.has_method("set_fog"):
			main.sun_ctl.set_fog(0.0)
	_day()
	GameClock.time_scale = 0.0
	# Let the controller push the pinned clock through to sun angle, sky and ambient
	# BEFORE the engine stops stepping _process, or the frozen frame keeps the old sky.
	await get_tree().create_timer(2.0).timeout
	Engine.time_scale = 0.0
	await _frames(30)

func _frames(n: int) -> void:
	for i in range(n):
		await RenderingServer.frame_post_draw

## EVERY name this harness pokes, checked for existence before it is trusted. Assigning a
## property Godot does not have is a silent no-op and calling a RenderingServer method it
## does not have is a hard error one frame later; both have bitten this file's subject
## matter before (`directional_shadow_normal_bias`, which never existed on any class).
func _api_audit() -> void:
	print("---- API audit (a MISSING name below means that line of code does nothing) ----")
	var props: Array[String] = [
		"shadow_bias", "shadow_normal_bias", "shadow_blur", "shadow_opacity",
		"directional_shadow_mode", "directional_shadow_max_distance",
		"directional_shadow_split_1", "directional_shadow_blend_splits",
		"directional_shadow_fade_start", "directional_shadow_pancake_size",
		"directional_shadow_normal_bias",  # known-bad, must report MISSING
	]
	var have: Dictionary = {}
	for p in ClassDB.class_get_property_list("DirectionalLight3D", false):
		have[p["name"]] = true
	for p in props:
		print("  DirectionalLight3D.%-34s %s" % [p, "ok" if have.has(p) else "MISSING (no-op)"])
	for m in ["directional_shadow_atlas_set_size", "directional_soft_shadow_filter_set_quality",
			"positional_soft_shadow_filter_set_quality"]:
		print("  RenderingServer.%-38s %s"
			% [m, "ok" if RenderingServer.has_method(m) else "MISSING"])

## Open deck, mid-morning light raking across the plating and the ironwork: the clearest
## read there is on shadow quality, and the vantage the owner is complaining about.
func _park_camera() -> void:
	var p: Node3D = main.player
	p.global_position = Vector3(2.0, 18.1, 2.0)
	p.rotation.y = deg_to_rad(-120.0)
	p.get_node("Head").rotation.x = deg_to_rad(-12.0)
	p.set("velocity", Vector3.ZERO)
	p.set("input_locked", true)

func _day() -> void:
	GameClock.force_phase(GameClock.Phase.DAY)
	GameClock._phase_elapsed_sec = \
		GameClock.phase_durations_minutes[GameClock.Phase.DAY] * 60.0 * 0.35

# ---------------------------------------------------------------- single canonical frame
## fps is measured with the world still LIVE — physics, fauna, weather and all — because a
## frame rate taken from a frozen scene is not a frame rate anyone plays at. The PICTURE is
## then taken frozen, so a before/after pair differs by the shadow settings and by nothing
## else. Those are two different requirements and they need the two different worlds.
func _single(tag: String) -> void:
	_day()
	await get_tree().create_timer(1.5).timeout
	var fps: float = await _measure()
	await _freeze()
	var step: float = await _save(tag)
	print("[shadow] %s: mode=%d max_dist=%.1f split1=%.2f blend=%s nbias=%.3f bias=%.4f blur=%.2f dsize=%s d16=%s dfilter=%s pfilter=%s"
		% [tag, sun.directional_shadow_mode, sun.directional_shadow_max_distance,
			sun.directional_shadow_split_1, str(sun.directional_shadow_blend_splits),
			sun.shadow_normal_bias, sun.shadow_bias, sun.shadow_blur,
			str(_s("directional_shadow/size")), str(_s("directional_shadow/16_bits")),
			str(_s("directional_shadow/soft_shadow_filter_quality")),
			str(_s("positional_shadow/soft_shadow_filter_quality"))])
	print("[shadow] %s: fps %5.1f  draws %6d  objs %5d  edge-step %.2f px"
		% [tag, fps,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), step])

func _s(k: String) -> Variant:
	return ProjectSettings.get_setting("rendering/lights_and_shadows/" + k, "<UNSET>")

# ---------------------------------------------------------------- the A/B matrix
## Each entry names a candidate and the knobs it moves. All of them are runtime-settable, so
## the whole matrix runs inside one boot of the world.
##   mode  : DirectionalLight3D.SHADOW_* (0 orthogonal / 1 two splits / 2 four splits)
##   dsize : directional shadow atlas edge, pushed through RenderingServer
##   d16   : 16-bit depth for that atlas (Godot's default is true)
##   dfilt : RenderingServer.SHADOW_QUALITY_* for the DIRECTIONAL filter
##   pfilt : ...and for the POSITIONAL one. gl_compatibility's scene shader has a SINGLE
##           SHADOW_MODE_PCF_* specialisation shared by both, so these two cannot disagree
##           and one of them is inert. B/C exist to find out which.
const BASE: Dictionary = {
	"mode": 1, "md": 45.0, "s1": 0.14, "blend": false,
	"dsize": 4096, "d16": true, "dfilt": 1, "pfilt": 3,
	"nbias": 0.45, "bias": 0.035, "blur": 0.7,
}

func _matrix() -> void:
	var configs: Array = [
		# A1/A2/A3 are the SAME config shot three times, spread through the run. They are
		# the noise floor: no other pair of frames may be called "different" by less than
		# the amount two identical configs differ by.
		{"n": "A1_shipped"},
		# --- proving negatives -------------------------------------------------------
		# gl_compatibility's scene shader has ONE SHADOW_MODE_PCF_* specialisation, shared
		# by the directional and the spot path (verified in the shipped binary's embedded
		# GLES3 scene.glsl). Both of these cannot be honoured. B moves only the directional
		# setting, C moves only the positional one; whichever changes the SUN's edge is the
		# one that actually compiles the variant, and the other is a dead line in
		# project.godot.
		{"n": "B_dfilt_hard", "dfilt": 0},
		{"n": "C_pfilt_hard", "pfilt": 0},
		# The GLES3 sample_shadow() is handed shadow_atlas_pixel_size with no blur term in
		# sight. If blur 0 and blur 4 land on the same pixels, shadow_blur is inert here
		# and three lines of tuning in main.gd and render_budget.gd are decoration.
		{"n": "D_blur0", "blur": 0.0},
		{"n": "E_blur4", "blur": 4.0},
		{"n": "A2_shipped"},
		# --- things that should actually help ----------------------------------------
		# THE HYPOTHESIS. PARALLEL_2_SPLITS hands each split HALF the atlas edge (2048 of
		# 4096), and split_1 = 0.14 spends that whole first 2048 map on the nearest 6.3 m,
		# leaving 6.3-45 m — everything the player actually looks at — on one 2048 map:
		# 53 texels/metre. ORTHOGONAL gives the single split the WHOLE 4096 over the whole
		# 45 m: 91 texels/metre, for FEWER draw calls, because nothing is rasterised twice.
		{"n": "F_ortho_4096_md45", "mode": 0},
		# Same, with the map doubled. Resolution is depth-only fill: it should cost no
		# draw calls at all, which is the claim being tested as much as the quality is.
		{"n": "G_ortho_8192_md45", "mode": 0, "dsize": 8192},
		# Resolution bought with cascade length instead of memory: no extra VRAM, but
		# shadows stop at 32 m.
		{"n": "H_ortho_4096_md32", "mode": 0, "md": 32.0},
		# Keep two splits, but rebalanced and on a bigger atlas: best near-field density
		# of the lot, at the cost of drawing mid-range casters into both splits.
		{"n": "I_2split_8192_s030", "s1": 0.30, "blend": true, "dsize": 8192},
		{"n": "J_ortho_8192_md32", "mode": 0, "md": 32.0, "dsize": 8192},
		# Does the bias still need to be this big once the texel is a third the size?
		{"n": "K_ortho_8192_lowbias", "mode": 0, "dsize": 8192, "nbias": 0.2, "bias": 0.02},
		{"n": "A3_shipped"},
	]
	for cfg in configs:
		_apply(cfg)
		await _frames(45)
		var fps: float = await _measure()
		var step: float = await _save(cfg["n"])
		print("[matrix] %-22s fps %5.1f  draws %6d  edge-step %5.2f px   (%s)"
			% [cfg["n"], fps,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				step, _desc(cfg)])

func _v(cfg: Dictionary, k: String) -> Variant:
	return cfg[k] if cfg.has(k) else BASE[k]

## ...plus the number the whole argument is about: shadow-map texels per metre in the split
## that covers the mid-field, which is where a deck railing's shadow lives.
func _desc(cfg: Dictionary) -> String:
	var edge: int = int(_v(cfg, "dsize"))
	var md: float = _v(cfg, "md")
	var far_m: float = md
	if int(_v(cfg, "mode")) != 0:
		edge /= 2                       # PARALLEL_2_SPLITS: half the atlas edge per split
		far_m = md * (1.0 - float(_v(cfg, "s1")))
	return "mode %d md %.0f s1 %.2f blend %s %d%s dfilt %d pfilt %d blur %.1f nb %.2f -> %.0f tex/m" % [
		_v(cfg, "mode"), md, _v(cfg, "s1"), str(_v(cfg, "blend")),
		_v(cfg, "dsize"), "/16" if _v(cfg, "d16") else "/32",
		_v(cfg, "dfilt"), _v(cfg, "pfilt"), _v(cfg, "blur"), _v(cfg, "nbias"),
		float(edge) / maxf(far_m, 0.001)]

func _apply(cfg: Dictionary) -> void:
	sun.directional_shadow_mode = _v(cfg, "mode")
	sun.directional_shadow_max_distance = _v(cfg, "md")
	sun.directional_shadow_split_1 = _v(cfg, "s1")
	sun.directional_shadow_blend_splits = _v(cfg, "blend")
	sun.shadow_normal_bias = _v(cfg, "nbias")
	sun.shadow_bias = _v(cfg, "bias")
	sun.shadow_blur = _v(cfg, "blur")
	RenderingServer.directional_shadow_atlas_set_size(int(_v(cfg, "dsize")), bool(_v(cfg, "d16")))
	RenderingServer.directional_soft_shadow_filter_set_quality(_v(cfg, "dfilt"))
	RenderingServer.positional_soft_shadow_filter_set_quality(_v(cfg, "pfilt"))

## Average fps over ~45 settled frames, so a config is never judged on the frame that
## reallocated its shadow map.
func _measure() -> float:
	for i in range(20):
		await RenderingServer.frame_post_draw
	var acc: float = 0.0
	var n: int = 45
	for i in range(n):
		await RenderingServer.frame_post_draw
		acc += Engine.get_frames_per_second()
	return acc / float(n)

# ---------------------------------------------------------------- dusk transition guard
func _dusk() -> void:
	await _shot(GameClock.Phase.DAY, 0.35, "day")
	for f in [0.0, 0.45, 0.75, 0.9, 1.0]:
		await _shot(GameClock.Phase.DUSK, f, "dusk%02d" % int(f * 100))
	await _shot(GameClock.Phase.NIGHT, 0.3, "night")

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

# ---------------------------------------------------------------- capture
## Saves the full frame plus two nearest-neighbour zooms, because a two-pixel staircase in a
## 1280-wide screenshot is not something anyone can honestly claim to see. Returns the
## blockiness metric so the caller can print it next to fps.
func _save(tag: String) -> float:
	get_tree().paused = false     # belt and braces: a focus event must not dim the capture
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, tag])
	_crop(img, CROP_DECK, CROP_DECK_ZOOM, "%s/%s_zoom.png" % [OUT_DIR, tag])
	_crop(img, CROP_WALL, CROP_WALL_ZOOM, "%s/%s_wall.png" % [OUT_DIR, tag])
	return _edge_step(img)

func _crop(img: Image, rect: Rect2i, zoom: int, path: String) -> void:
	var r: Rect2i = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x < 4 or r.size.y < 4:
		return
	var c: Image = img.get_region(r)
	c.resize(r.size.x * zoom, r.size.y * zoom, Image.INTERPOLATE_NEAREST)
	c.save_png(path)

## BLOCKINESS, as a number. Walk the columns of EDGE_X across the deck shadow boundary; in
## each column find the row of the strongest light->dark step (on a 5-row box-smoothed
## luminance profile, so the diamond-plate texture does not win). On a well-resolved edge
## that row creeps down by a pixel or two every column; on a blocky one it sits still for a
## whole shadow texel and then jumps. So: mean plateau length, in screen pixels, of the
## shadow boundary. Lower is smoother. It is a proxy, not a texel count — the images are
## still the evidence — but it is the same proxy for every config, measured identically.
func _edge_step(img: Image) -> float:
	var rows: Array[int] = []
	for x in range(EDGE_X.x, EDGE_X.y):
		if x >= img.get_width():
			break
		var prof: PackedFloat32Array = PackedFloat32Array()
		for y in range(EDGE_Y.x, EDGE_Y.y):
			if y >= img.get_height():
				break
			prof.append(img.get_pixel(x, y).get_luminance())
		if prof.size() < 16:
			return 0.0
		# 5-tap box smooth, then strongest downward step.
		var best_y: int = -1
		var best_d: float = 0.0
		for i in range(4, prof.size() - 4):
			var a: float = (prof[i - 4] + prof[i - 3] + prof[i - 2] + prof[i - 1]) * 0.25
			var b: float = (prof[i + 1] + prof[i + 2] + prof[i + 3] + prof[i + 4]) * 0.25
			if a - b > best_d:
				best_d = a - b
				best_y = i
		if best_y < 0 or best_d < 0.03:
			continue      # no legible edge in this column; skip it rather than invent one
		rows.append(best_y)
	if rows.size() < 8:
		return 0.0
	var moves: int = 0
	for i in range(1, rows.size()):
		if absi(rows[i] - rows[i - 1]) >= 1:
			moves += 1
	return float(rows.size()) / maxf(float(moves), 1.0)
