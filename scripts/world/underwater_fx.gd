extends Node3D
## Underwater visibility & light: everything that sells the water as a lit MEDIUM the
## player is inside of, rather than a teal void. Owns nothing topside — it reads the
## surface height (Gyre), the daylight (GameClock), the sun bearing (the scene's sun)
## and the storm, and drives:
##   - THE SURFACE FROM BELOW: a Snell's-window plane held over the player just under
##     the swell (the biggest "I'm underwater" cue — bright rippling disc overhead).
##   - CAUSTICS: the surface's focused-light net wrapped on the upper legs.
##   - DEPTH-GRADED WATER: re-grades the camera's underwater Environment continuously
##     from the player's depth (green & clear near the surface -> blue-black & near-dark
##     at the bottom) and thickens the near-surface murk when a storm stirs the sediment.
##
## It is added as a child of underwater_world (which owns being in the scene), so main.gd
## is never touched; it only READS the environment main.gd puts on the camera and writes
## better values into it after main has run (process_priority keeps us last).

const LEGS: Array[Vector2] = [Vector2(-22, -12), Vector2(22, -12), Vector2(-22, 12), Vector2(22, 12)]

var _root: Node3D                     # everything visible, toggled by camera depth
var _snell: MeshInstance3D
var _snell_mat: ShaderMaterial
var _caustic_mats: Array[ShaderMaterial] = []
var _sun: DirectionalLight3D
var _storm: Node = null

# --- submerged sun attenuation (see _grade_sun) ---
var _sun_topside_energy: float = -1.0
var _sun_topside_color: Color = Color.WHITE
var _wrote_energy: float = -1.0
var _wrote_color: Color = Color.WHITE

## Direct sunlight lost the instant it crosses the surface — Fresnel reflection off the
## swell plus immediate forward scatter. Underwater the beam is DIFFUSE, and that is the
## whole point of this constant: it is what stops the sun drawing hard-edged shadows down
## here. The pontoon slab overhead was casting a razor-sharp horizontal shadow edge onto
## every caisson at y -3 — geometrically correct, and the exact "hard horizontal seam a few
## metres under the surface" that has been blamed on the caustic quads through two previous
## fixes. (It is not the caustics: a strength-0 capture is identical, and it survives
## merging the leg into a single mesh. See the scratchpad exp_* frames.) Sunlight four
## metres down simply is not a hard light source, so the fix is to stop lighting it like one.
const SUN_SURFACE_LOSS: float = 0.55
## Extinction of direct sunlight per metre of water, on top of the surface loss: about a
## fifth of it left at 4 m, a fiftieth by 15 m, where ambient scatter takes over entirely.
const SUN_EXTINCTION: float = 0.22
## Sunlight that survives to the seabed as scattered blue-green, so nothing goes pure black.
const SUN_FLOOR: float = 0.06
## Water absorbs red first, then green. The deep colour direct sunlight decays TOWARD.
const DEEP_LIGHT := Color(0.16, 0.62, 0.72)

# graded underwater colours (near surface -> seabed)
const NEAR_FOG := Color(0.10, 0.27, 0.24)     # greenish, lit from above
const DEEP_FOG := Color(0.006, 0.022, 0.045)  # blue-black deep
const NEAR_AMB := Color(0.16, 0.34, 0.32)
const DEEP_AMB := Color(0.04, 0.10, 0.15)
const STORM_MURK := Color(0.13, 0.17, 0.12)   # stirred sediment, near the surface

## ============================================================================ THE GRADE
## THE WATER WAS TOO THICK TO SEE A REEF THROUGH, and the arithmetic says so plainly.
## Owner, s34: "this is a coral reef for christ's sake" — the water reads hazy and detail
## does not carry. Measured against the shipped curve (day, no storm), fog density was
## 0.1107/m at y -8, 0.1856 at y -12 and 0.1992 at y -15. Godot's depth fog transmits
## exp(-density * distance), so at y -12 a body 15 m away arrived at 6% contrast: the
## coral colonies live at y -12.7 to -22 and were, in the most literal sense, behind a wall.
##
## THREE THINGS WERE WRONG, not one:
##   1. The curve resolved over 13 m and the REEF IS 22 m TALL. Everything below -13
##      clamped to MAX_DENS and then got the abyss ramp on top, so the entire lower two
##      thirds of the reef sat at or past the densest the shallow grade can go.
##   2. MAX_DENS 0.19 is a 12 m visibility ceiling. Fine as "the death line is murky",
##      wrong as "the reef band".
##   3. The abyss ramp started at 13 m, i.e. INSIDE the reef, so the murk that exists to
##      hide the -92 floor was being applied to the coral.
##
## So the two jobs are separated. The clear-water grade now resolves over the REEF's own
## height, and the abyss ramp starts BELOW the reef instead of half way up it. The dive
## band is unchanged in character — the surface is still 0.028 and it still darkens with
## depth — it just stops going opaque where the content is.
##
## SWEPT, NOT GUESSED: three candidate curves re-exposed on ONE windowed build
## (tests/FogShot.tscn --fog=a,b,c, the trick ReefShot uses for the reef glow), because
## picking a look across separate launches means comparing thermal states. See DEVLOG s34.
##
## THESE ARE `var`, NOT `const`, AND THAT IS DELIBERATE: a harness cannot sweep a constant
## (GDScript raises "Invalid assignment on read-only value" mid-function and, in a windowed
## run, hangs Godot for ever — docs/AGENT_TRAPS.md, s22). They are written by the sweep
## harness and by nothing else in the game.
## How many metres of depth the clear-water grade resolves over. Was 13.0 (the breath-gated
## "reachable" depth); the reef's own band bottoms at -22, so grading over 13 m put its
## lower half past the end of the curve. Named for what it now measures.
var reef_depth_m: float = 24.0
## Fog never gets denser than this in the graded band: caps how far it can swallow a nearby
## animal into flat fog colour, so a grouper (or the rig, the reef) is always visible as at
## least a shape. Was 0.19, which transmits 6% at 15 m; 0.105 transmits 21%.
var max_dens: float = 0.105
## Where the ABYSS ramp starts — the separate, much heavier murk whose only job is to hide
## the -92 gyre floor from anyone looking down from the surface. Was implicitly
## REACHABLE_DEPTH_M (13 m), which put it inside the reef.
var abyss_start_m: float = 26.0
## The shallow end of the grade. Was an unnamed literal 0.028 inside the lerp, which is
## exactly the kind of number a sweep needs to be able to reach.
var near_dens: float = 0.028
## Ambient light never drops below this at depth, for the same reason as max_dens — a
## silhouette needs SOME rim light to read as a silhouette rather than pure black.
##
## RAISED IN s34 FROM 0.20, AND THE SWEEP IS WHY. Thinning the fog alone did not answer the
## owner's ask. Side by side on one build, the clearer curves resolved the far leg and the
## kelp at 25 m where the shipped one lost them — a real improvement, and still a dark
## picture, because "can you see it" has two terms and only one of them is the medium. At
## the coral band the ambient was 0.53 falling to 0.20, against an ambient COLOUR that is
## itself only (0.10, 0.21, 0.23): there was very little light down there to be clear about.
## Clarity and illumination were swept together in the end (candidates d and e) and the
## reef band needs both.
var amb_floor: float = 0.34
## The shallow end of the ambient curve, i.e. how lit the water is just under the surface.
var amb_near: float = 1.05
## HOW FAR ALONG THE NEAR->DEEP COLOUR RAMP THE REEF FLOOR SITS.
##
## Density and colour used to share one curve, so arriving at the bottom of the graded band
## meant arriving at DEEP_FOG (0.006, 0.022, 0.045) — near-black. That was survivable while
## the band ended at 13 m and there was nothing down there to look at. It is not survivable
## now: the band ends at 24 m, the coral runs to -22 and s34 extends it further down the
## legs, so the colour ramp would land the whole new lower reef in black water that you can
## nonetheless see a long way through, which reads as wrong rather than as deep. Colour now
## reaches only this fraction of the way to DEEP_FOG by the reef floor and finishes the
## journey on the abyss ramp, where being black is the entire point.
var col_reach: float = 0.72

func _ready() -> void:
	# main.gd carries a simpler fallback grade for scenes built without this node, and it
	# checks this group to know whether to stand down. Before s34 the two wrote the same
	# Environment every frame and this one won only by process order.
	add_to_group("underwater_fx")
	process_priority = 100   # run AFTER main.gd's environment write, so our grade wins
	_root = Node3D.new()
	add_child(_root)
	_build_snell()
	_build_caustics()

# ---------------------------------------------------------------- build

func _build_snell() -> void:
	_snell_mat = ShaderMaterial.new()
	_snell_mat.shader = load("res://materials/underwater_surface.gdshader")
	var plane := PlaneMesh.new()
	plane.size = Vector2(620, 620)   # large enough to occlude the far surface toward the horizon
	plane.subdivide_width = 48       # enough that per-vertex world pos feeds smooth ripple
	plane.subdivide_depth = 48
	plane.material = _snell_mat
	_snell = MeshInstance3D.new()
	_snell.mesh = plane
	_snell.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_snell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snell.extra_cull_margin = 200.0    # it's always overhead; never let it cull out
	_root.add_child(_snell)

## Caustic light on the upper legs — one flat quad laid on each of the four caisson
## faces (NOT a box sleeve, which reads as a glass box haloing past the leg). Each quad
## is the exact size of the face and sits 6 cm proud, additive, so the rippling net
## lands ON the steel with no overhang. Fades out by ~6 m down. One shared material.
func _build_caustics() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://materials/caustics.gdshader")
	# Reach must die INSIDE the quad, not at its edge. The quads span 8 m (y +2 down to
	# y -6) and a 6.5 m reach still left a residue lit where the mesh simply stops, which
	# an additive pass on dark water draws as a straight horizontal line right across every
	# caisson face — the "translucent box sleeved over the leg" seam again, by another
	# route. 4.6 m is fully faded a metre and a half above the bottom edge.
	mat.set_shader_parameter("reach", 4.6)
	mat.set_shader_parameter("scale", 0.85)
	mat.set_shader_parameter("strength", 1.1)
	_caustic_mats.append(mat)
	# face offset dir (unit), yaw so the QuadMesh (+Z normal) faces outward
	var faces := [
		[Vector3(1, 0, 0), PI * 0.5], [Vector3(-1, 0, 0), -PI * 0.5],
		[Vector3(0, 0, 1), 0.0], [Vector3(0, 0, -1), PI],
	]
	for leg in LEGS:
		for f in faces:
			var dir: Vector3 = f[0]
			var q := QuadMesh.new()
			q.size = Vector2(6.0, 8.0)   # exact caisson face width, 8 m tall (y2..-6)
			q.material = mat
			var mi := MeshInstance3D.new()
			mi.mesh = q
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_root.add_child(mi)
			mi.position = Vector3(leg.x, -2.0, leg.y) + dir * 3.06   # just proud of the 6 m face
			mi.rotation.y = f[1]

# ---------------------------------------------------------------- per frame

func _find_sun() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	for n in scene.find_children("*", "DirectionalLight3D", true, false):
		_sun = n
		return

func _daylight() -> float:
	var fr: float = clampf(GameClock.phase_fraction(), 0.0, 1.0)
	match GameClock.current_phase:
		GameClock.Phase.DAY:
			return 1.0
		GameClock.Phase.DAWN:
			return lerpf(0.12, 1.0, fr)
		GameClock.Phase.DUSK:
			return lerpf(1.0, 0.12, fr)
		_:
			return 0.08

## Find the StormSystem by walking the tree (works whether the scene root is Main or a
## test harness), cached once located.
func _storm_node() -> Node:
	if _storm != null and is_instance_valid(_storm):
		return _storm
	var stack: Array = [get_tree().root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is StormSystem:
			_storm = n
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func _storm_intensity() -> float:
	var st: Node = _storm_node()
	if st == null:
		return 0.0
	var v: Variant = st.get("_intensity")
	return clampf(float(v), 0.0, 1.0) if v != null else 0.0

## Clamp the DIRECT sun on submerged surfaces by the same depth curve the water volume is
## graded with.
##
## The environment fog grades the medium, but fog is a function of distance from the camera,
## so a concrete caisson five metres away came through it almost untouched: its sunlit face
## rendered near-white cream with a hard shadow edge, completely untinted, while every cubic
## metre of water around it was teal. The water graded and the rig standing in it did not,
## which reads as the rig being pasted over the sea rather than standing in it — at 15 m
## down, where no direct sunlight of that colour or intensity exists.
##
## Sunlight entering water loses red within a couple of metres and most of its intensity
## within ten, so the fix is to attenuate the directional light itself while the camera is
## under, on the same extinction curve, and shift what survives toward blue-green.
##
## SunController owns this light and rewrites it on every clock tick. Rather than fight it,
## remember the last value we wrote: anything we did not write is a fresh topside value from
## the controller, so a phase change or a squall mid-dive still comes through, and surfacing
## restores the light exactly. Above water the attenuation is 1.0 and this is a no-op.
func _grade_sun(surf: float, cam_y: float, under: bool, storm: float) -> void:
	if _sun == null:
		return
	if _sun_topside_energy < 0.0 or not is_equal_approx(_sun.light_energy, _wrote_energy):
		_sun_topside_energy = _sun.light_energy
	if _sun.light_color != _wrote_color:
		_sun_topside_color = _sun.light_color
	var atten: float = 1.0
	var tint: float = 0.0
	if under:
		var depth: float = maxf(surf - cam_y, 0.0)
		atten = SUN_FLOOR + (SUN_SURFACE_LOSS - SUN_FLOOR) * exp(-depth * SUN_EXTINCTION)
		# A squall stirs sediment into the top of the column: less light gets in at all.
		atten *= (1.0 - storm * 0.45)
		# Red is gone within a couple of metres; the shift saturates well before the seabed.
		tint = clampf(depth / 7.0, 0.0, 1.0)
	var e: float = _sun_topside_energy * atten
	var c: Color = _sun_topside_color.lerp(DEEP_LIGHT, tint)
	_sun.light_energy = e
	_sun.light_color = c
	_wrote_energy = e
	_wrote_color = c

func _process(_delta: float) -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		_root.visible = false
		return
	var cam: Camera3D = player.get_node_or_null("Head/Camera3D")
	if cam == null:
		return
	if _sun == null:
		_find_sun()

	var px: float = player.global_position.x
	var pz: float = player.global_position.z
	var surf: float = Gyre.swim_line(Vector2(px, pz), Gyre.water_time())
	var cam_y: float = cam.global_position.y
	var under: bool = cam_y < surf

	# Only render the FX when the camera is at/under the surface (small margin so the
	# caustics on the legs are already there as you break through).
	var showing: bool = cam_y < surf + 1.5
	_root.visible = showing

	# NOTHING BELOW THIS LINE HAS AN EFFECT WHILE `showing` IS FALSE, and all of it was
	# running anyway on every frame of a game that is mostly played on deck: the Snell
	# window's 4 uniforms and 2 on the caustic material — ~7 RenderingServer parameter
	# writes a frame into materials on hidden meshes (it was ~19 before s34 deleted the six
	# light-shaft materials) — plus a `look_at`-grade basis read and the Gerstner surface
	# sample they are fed from. Same contract as underwater_world's topside cull: every one of these is
	# a pure function of the CURRENT frame's surf/day/storm, so there is no state to carry
	# and the first frame back under the surface writes them all again before it is drawn.
	#
	# _grade_sun is the exception and stays outside the gate: it OWNS a restore (it puts the
	# sun's topside energy and colour back when you surface), so skipping it while topside
	# would leave a dive's attenuation latched on above water.
	if not showing:
		# `under` is false by construction here (surf + 1.5 > surf), and _grade_sun ignores
		# `storm` unless under — so this is bit-for-bit the call the full path would make.
		_grade_sun(surf, cam_y, false, 0.0)
		return

	var day: float = _daylight()
	var storm: float = _storm_intensity()
	var sun_dir := Vector3(0.25, 0.85, 0.2)
	if _sun != null:
		sun_dir = _sun.global_transform.basis.z   # points back toward the sun

	# Snell window: park it over the player, just under the swell.
	if _snell != null:
		_snell.global_position = Vector3(px, surf - 0.15, pz)
		_snell_mat.set_shader_parameter("daylight", day)
		_snell_mat.set_shader_parameter("sun_dir", sun_dir)
		# a storm chops the surface: soften the window and knock the light back
		_snell_mat.set_shader_parameter("ripple", 1.0 + storm * 1.4)
		_snell_mat.set_shader_parameter("window_color",
			Color(0.42, 0.72, 0.74).lerp(Color(0.20, 0.34, 0.30), storm * 0.7))

	for m in _caustic_mats:
		m.set_shader_parameter("daylight", day * (1.0 - storm * 0.6))
		m.set_shader_parameter("top_y", surf)

	# ---- the rig's own surfaces must obey the water too ----
	_grade_sun(surf, cam_y, under, storm)

	# ---- depth-graded water: re-grade the camera's underwater environment ----
	if under:
		var env: Environment = cam.environment
		if env != null and env.fog_enabled:
			var depth: float = maxf(surf - cam_y, 0.0)
			# Normalised over THE REEF'S OWN HEIGHT (0..reef_depth_m), not over the
			# breath-gated depth a player can survive to. Those are different questions, and
			# conflating them is what made the water opaque: the survivable column is ~13 m
			# and the coral band bottoms at -22, so a curve that finished at 13 m had the
			# whole lower half of the content clamped at its densest value. The measured
			# numbers are in the block at `reef_depth_m`.
			var t: float = clampf(depth / reef_depth_m, 0.0, 1.0)   # 0 surface..1 reef floor
			# Three readable bands instead of one smooth curve: SHALLOW (0..~0.22, ~0-3m)
			# stays close to clear water so the rig, reef and fauna read in real detail;
			# MID (~0.22..1.0) is where it visibly starts murking up and keeps thickening;
			# it never reaches full opacity (see max_dens/amb_floor) so something like a
			# grouper is always at least a silhouette, never swallowed to flat fog colour.
			var tc: float = clampf((t - 0.22) / 0.78, 0.0, 1.0)
			tc = tc * tc * (3.0 - 2.0 * tc)   # smoothstep: gentle at both ends, steep between
			# Colour runs a SHORTER ramp than density — see col_reach.
			var tcc: float = tc * col_reach
			var fog_col: Color = NEAR_FOG.lerp(DEEP_FOG, tcc)
			var amb_col: Color = NEAR_AMB.lerp(DEEP_AMB, tcc)
			# Extinction of the MEDIUM. Shallow starts genuinely clear (near_dens — a caisson
			# face 10+ m off still reads); by the death line it is thick enough to feel like
			# a real depth limit without ever fully swallowing a nearby animal — density is
			# capped at max_dens and the ambient floor (amb_floor) never goes fully dark, so
			# anything close always shows as at least a shape.
			var dens: float = lerpf(near_dens, max_dens, tc)
			var amb_e: float = lerpf(amb_near, amb_floor, tc)
			# Wavy top: sunlight through a moving swell dapples the shallows, not a flat
			# wash — a slow, position-locked shimmer on the near-surface band only, faded
			# out by the time the mid band takes over, so the water reads as genuinely lit
			# from above near the top and genuinely still and dark going deeper.
			var shimmer_zone: float = 1.0 - smoothstep(0.0, 0.3, t)
			if shimmer_zone > 0.0:
				var wt: float = Gyre.water_time()
				var s1: float = sin(px * 0.22 + wt * 1.6)
				var s2: float = sin(pz * 0.19 - wt * 1.3 + 1.7)
				var shimmer: float = (0.5 + 0.5 * s1) * (0.5 + 0.5 * s2)
				amb_e *= 1.0 + shimmer * 0.4 * shimmer_zone * day
				dens *= 1.0 - shimmer * 0.15 * shimmer_zone
			# storm stirs sediment near the surface: denser, murkier, dimmer up top
			var near: float = (1.0 - t)
			dens += storm * near * 0.11
			fog_col = fog_col.lerp(STORM_MURK, storm * near * 0.6)
			amb_e *= (1.0 - storm * near * 0.35)
			dens = minf(dens, max_dens + storm * 0.08)
			amb_e = maxf(amb_e, amb_floor * 0.5)
			# THE ABYSS, AND IT IS A SEPARATE JOB FROM THE GRADE ABOVE. Below the reef the
			# water keeps closing in for another 50 m — fog thickening past the silhouette
			# cap, ambient collapsing, colour going to near-black — so the -92 floor can
			# never be seen from anywhere a camera can be. It used to start at the DEATH LINE
			# (13 m), which is half way up the coral, so the murk whose only purpose is
			# hiding the gyre floor was being applied to the reef. It starts below the reef
			# now (abyss_start_m) and the two no longer fight.
			var abyss: float = clampf((depth - abyss_start_m) / 50.0, 0.0, 1.0)
			if abyss > 0.0:
				dens = lerpf(dens, 0.42, abyss)
				amb_e = lerpf(amb_e, 0.03, abyss)
				fog_col = fog_col.lerp(Color(0.002, 0.006, 0.012), abyss)
			# night pulls the whole column toward the dark, leaving the Bloom's own glow
			# (seabed shader, fauna rims) as the main light — brightest by day.
			var lum: float = 0.28 + 0.72 * day
			fog_col *= lum
			amb_col *= (0.4 + 0.6 * day)
			amb_e *= lum
			env.fog_light_color = fog_col
			env.fog_density = dens
			env.background_color = fog_col.darkened(0.35)
			env.ambient_light_color = amb_col
			env.ambient_light_energy = amb_e
