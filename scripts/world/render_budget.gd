extends Node
## FRAME BUDGET — the pass that makes this rig run on a MacBook.
##
## gl_compatibility draws one call per mesh surface, per shadow split it casts into. The
## rig is built from ~6,800 individual primitives (every bolt, cleat, rung, hinge and
## placard is its own MeshInstance3D), which is exactly the right way to author it and
## exactly the wrong thing to hand a GL renderer unbudgeted: measured at 19,966 draw calls
## and 9.3 fps standing on deck looking at the horizon, against a stated bar of 60.
##
## Nothing here changes what the world IS. It changes what is worth drawing:
##
##   1. SMALL THINGS DO NOT CAST SHADOWS. A 4 cm bolt head casts a shadow smaller than the
##      shadow map's own texel — it costs a draw call per split and contributes literally
##      nothing visible. Anything whose largest dimension is under SHADOW_MIN drops out of
##      the shadow passes. Structure, furniture and machinery still cast.
##   2. SMALL THINGS FADE OUT AT DISTANCE. A 6 cm rivet is sub-pixel past ~40 m. Godot's
##      visibility_range culls it on the CPU before it ever reaches a draw call, with a
##      fade margin so nothing pops. The cutoff scales with the object's own size, so a
##      handrail survives to 200 m and a bolt does not survive to 40.
##
## Both are reversible per-node and neither touches transforms, so the placement probes,
## the support index and every screenshot vantage inside FAR_ALWAYS still see the world
## they audited. Run as a child of Main; it re-sweeps while the dressing streams in.

## Largest dimension under which a mesh stops casting directional shadows.
const SHADOW_MIN: float = 0.80
## Groups whose meshes keep their shadow whatever their size — see the `hero` note in the
## shadow audit below. A companion animal the player crouches down to look at is not
## dressing, and the size rule cannot tell the difference on its own.
const HERO_GROUPS: Array[StringName] = [&"ship_cat"]

## Is this mesh part of a hero object? Walks up to the nearest group-bearing ancestor,
## because the MeshInstance3D itself is buried under CreatureAnim's host/model nodes and
## is never the node carrying the group.
static func _is_hero(mi: Node) -> bool:
	var n: Node = mi
	while n != null:
		for g in HERO_GROUPS:
			if n.is_in_group(g):
				return true
		n = n.get_parent()
	return false
## A "plate": thinner than this and no wider than THIN_PLATE_MAX_SPAN casts no useful shadow.
## Above the span limit an object this thin is structure (bulkhead, deck plate) and still casts.
const THIN_PLATE_MAX_THICK: float = 0.09
const THIN_PLATE_MAX_SPAN: float = 2.60
## Objects at least this big always draw, at any distance (structure, tanks, containers).
const FAR_ALWAYS: float = 3.0
## Distance budget: an object of size `s` draws out to clampf(s * SIZE_TO_RANGE, MIN, MAX).
const SIZE_TO_RANGE: float = 110.0
const RANGE_MIN: float = 30.0
const RANGE_MAX: float = 200.0
const FADE: float = 0.18          ## fraction of the range spent fading, so nothing pops

## The dressing streams in over several seconds, so one pass at t=0 would miss most of it.
## Sweep repeatedly; already-budgeted nodes are skipped by a meta flag, so a sweep that
## finds nothing new costs one tree walk.
const SWEEP_COUNT: int = 8
const SWEEP_EVERY: float = 3.0

# ---------------------------------------------------------------- the LIGHT budget
## Rules 1 and 2 above are about MESHES, and they are why the rig draws at all. They do
## nothing for the second cliff, which the breaker falls off: closing the topside circuit
## took the rig from ~20 fps to ~12 and made it "unbearably glitchy". Measured with
## tests/PowerPerf.tscn (windowed, real GPU) the blame is not what it looks like:
##
##   * turning 60 interior lights OFF bought back 4%. The light COUNT is not the problem.
##   * turning shadows off on the FIVE shadow-casting omni/spots took 20.7 -> 31.9 fps and
##     dropped 700 draw calls. FIVE lights were costing more than half the frame.
##
## A shadow-casting spot re-renders every caster in its range into a shadow map, every
## frame, whether or not the player can see the result. Four pole floodlights standing on
## an open deck do that four times over, and the three you are not standing under
## contribute nothing you would ever notice.
##
## So: shadows stay ON — they are the whole point of restoring power — but only for the
## lights CLOSE ENOUGH FOR THE SHADOW TO BE WORTH DRAWING. Stand under a floodlight and it
## still throws your shadow across the plating; the three poles across the deck give you
## their light without also each rendering a shadow map you cannot resolve at that range.
##
## This is done by toggling `shadow_enabled` from _process, NOT with Light3D's own
## `distance_fade_shadow`. That property is the obvious tool and it is the wrong one here:
## it is implemented in Forward+ and Mobile only, and the Compatibility renderer this game
## ships on ignores it outright. Measured with tests/PowerPerf.tscn, setting it changed the
## draw-call count by nothing at all, while flipping `shadow_enabled` on the same five
## lights dropped ~700 draw calls. The flag is real in GL; the fade is not.
##
## DIRECTIONAL lights are exempt — the sun's shadow is the whole sky and has no position
## to be near or far from.
const SHADOW_NEAR: float = 20.0     ## a shadow-casting light further than this stops casting
const SHADOW_ALWAYS: float = 9.0    ## ...but this close it casts even when the fixture is off screen
## AT MOST TWO SHADOW-CASTING POSITIONAL LIGHTS AT A TIME. This is deliberate and it is a
## PERFORMANCE cap, not an aesthetic one — do not raise it again without re-measuring.
##
## It was tried at 3 on 2026-07-27 and reverted the same day. Two things went wrong, and the
## second one is the non-obvious one:
##   * FRAME. Each live caster re-renders every mesh in its range into a shadow map every
##     frame. tests/PowerPerf.tscn measured five casters at ~700 draw calls, i.e. ~140 draw
##     calls per caster — a third more shadow work for a third light nobody was looking at.
##   * RESOLUTION. The positional shadow ATLAS is a fixed budget split between whoever is
##     casting. Three lights contending for it drove Godot's allocator into more finely
##     subdivided quadrants, so every live shadow got a SMALLER map than it had at two —
##     which is exactly the "shadows look more pixelated than before" the owner reported
##     alongside the chop. Adding a caster made the other two worse.
## At 2, project.godot hands each caster a whole 2048x2048 atlas quadrant (see the
## atlas_quadrant_*_subdiv block there — those numbers assume this cap).
const SHADOW_BUDGET: int = 2
## A currently-casting light needs to fall this many metres further back than a currently-
## dark one before the ranking swaps them. Two lights sitting near the SHADOW_BUDGET cutoff
## (a player walking a corridor lined with fixtures, say) used to trade the last slot back
## and forth every SHADOW_POLL tick as their distances crossed — each swap tears down one
## shadow map and stands up another, which reads as a shadow visibly popping / relighting
## for no reason the player did. The margin only ever helps the light that already has the
## slot, so it cannot let a light that is genuinely much closer keep waiting its turn.
const SHADOW_HYSTERESIS: float = 1.5
const SHADOW_POLL: float = 0.25     ## seconds between re-rankings; lights and player both move slowly

## Never touch these: they are already hand-tuned, camera-relative, or shader-displaced far
## outside their authored AABB, so a size-derived range would cull them wrongly.
const SKIP_SCRIPTS: Array[String] = [
	"ocean_surface.gd", "underwater_fx.gd", "gyre.gd", "storm_system.gd",
	"jelly_glow.gd", "stars.gdshader",
	# mesh_batcher.gd's welded chunks already carry the longest visibility range of the
	# primitives inside them; re-deriving one from the merged AABB would cull a whole
	# bucket at the range of a single bolt.
	"mesh_batcher.gd",
]
const SKIP_GROUPS: Array[String] = [
	"player", "floating_debris", "gyre_streaks", "lit_flares", "ocean_surface",
]

var _budgeted: int = 0
var _shadow_off: int = 0
var _lights_faded: int = 0
var _shadow_lights: Array[Light3D] = []   ## every non-directional light authored to cast
var _poll_t: float = 0.0

func _ready() -> void:
	name = "RenderBudget"
	for i in range(SWEEP_COUNT):
		await get_tree().create_timer(SWEEP_EVERY if i > 0 else 1.5).timeout
		_sweep(get_parent())
	print("[budget] meshes budgeted: %d   shadow casters dropped: %d   shadow lights rationed: %d"
		% [_budgeted, _shadow_off, _lights_faded])

func _process(delta: float) -> void:
	if _shadow_lights.is_empty():
		return
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = SHADOW_POLL
		_rank_shadows()

func _sweep(root: Node) -> void:
	if root == null:
		return
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if _skip(n):
			continue
		for c in n.get_children():
			stack.append(c)
		# Lights are budgeted on the same sweep — a brazier the player lit two minutes ago
		# and a floodlight built at startup both come through here exactly once.
		var lt := n as Light3D
		if lt != null:
			_budget_light(lt)
			continue
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or mi.has_meta("budgeted"):
			continue
		mi.set_meta("budgeted", true)
		_budgeted += 1
		var a: AABB = mi.get_aabb()
		var scl: Vector3 = mi.global_transform.basis.get_scale()
		var dim := Vector3(a.size.x * scl.x, a.size.y * scl.y, a.size.z * scl.z)
		var size: float = maxf(maxf(dim.x, dim.y), dim.z)
		var thin: float = minf(minf(dim.x, dim.y), dim.z)
		# A shadow caster earns its place in the shadow passes (one draw call per cascade it
		# lands in) only if it would actually darken something. Two ways to fail that:
		#
		#  1. TOO SMALL to resolve — smaller than a shadow-map texel. That is SHADOW_MIN.
		#  2. TOO THIN to read — a PLATE. Signs, placards, deck paint, warning panels, cable
		#     trays, wall stencils: 1.0 x 0.4 x 0.03 has a largest dimension of 1.0, so the
		#     size test passes it and it casts, but the shadow it throws is a hairline no
		#     player will ever notice against rusted steel. The rig is dressed with hundreds
		#     of these and they were all in the shadow budget.
		#
		# Anything genuinely structural stays: a 3 mm-thin object 3 m across is a bulkhead or
		# a deck plate, and those must still cast, so the thin rule only applies below
		# THIN_PLATE_MAX_SPAN.
		#
		#  3. ...UNLESS IT IS A HERO. The size rule is written for dressing, and it was
		#     quietly stripping the shadow off the one thing on this rig a player looks
		#     AT: the ship's cat is 0.66 m nose to tail, under SHADOW_MIN, so the hero
		#     animal was the only object on deck throwing nothing — which reads as a
		#     cut-out pasted onto the plating however good the model is, and is a real
		#     part of "sharpen the detail of the cat". It costs one draw call: the whole
		#     animal is a single surface with one material.
		var negligible: bool = not _is_hero(mi) and (size < SHADOW_MIN \
			or (thin <= THIN_PLATE_MAX_THICK and size <= THIN_PLATE_MAX_SPAN))
		if negligible and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_shadow_off += 1
		if size >= FAR_ALWAYS or mi.visibility_range_end > 0.0:
			continue
		var reach: float = clampf(size * SIZE_TO_RANGE, RANGE_MIN, RANGE_MAX)
		mi.visibility_range_end = reach
		mi.visibility_range_end_margin = reach * FADE
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

## Enrol one light in the shadow budget. The light itself is never touched — same colour,
## same energy, same range, same lens — only its shadow pass is rationed, by _rank_shadows
## below. A light that was authored WITHOUT shadows costs nothing here and is skipped, so
## the ~180 shadowless omnis on the rig fall straight through and stay shadowless.
func _budget_light(l: Light3D) -> void:
	if l.has_meta("budgeted"):
		return
	l.set_meta("budgeted", true)
	if l is DirectionalLight3D or not l.shadow_enabled:
		return
	# SHADOW QUALITY, applied once, centrally. Only SHADOW_BUDGET of these are ever live at
	# a time and project.godot gives each of those a full 2048x2048 atlas quadrant, so the
	# texel these values are fighting is ~4x smaller than Godot's per-light defaults were
	# tuned for. Left at the defaults, the same world-space bias that used to be a texel or
	# two is now eight — contact shadows detach from their object (peter-panning) and the
	# stepped edge that reads as "pixelated" is a bias artefact as much as a resolution one.
	#   normal_bias 2.0 -> 0.55 : the big one. Offsets the sample along the surface normal;
	#                             at 2048 per light it can come right in without acne.
	#   bias        0.03 -> 0.012 : depth offset, scaled down with the texel for the same reason.
	# There used to be a third line here, `shadow_blur = 0.7`, and it never did anything.
	# The property is real on Light3D so it raised no error, but gl_compatibility's scene
	# shader passes its PCF kernel the raw shadow_atlas_pixel_size with no blur term in the
	# path; tests/ShadowShot.tscn shot blur 0.0 against blur 4.0 on a frozen frame and got
	# BYTE-IDENTICAL PNGs. Removed rather than left as a comment-shaped promise that some
	# future reader tunes for an afternoon.
	# Every shadow-casting fixture on the rig comes through here (structures.gd braziers and
	# lamps, env_objects.gd fires, rig_builder.gd's four deck floodlights, comfort_furniture
	# stoves), so this is the one place that reaches all of them without editing five files.
	l.shadow_normal_bias = 0.55
	l.shadow_bias = 0.012
	_shadow_lights.append(l)
	_lights_faded += 1

## Keep only the SHADOW_BUDGET nearest shadow-casters live, and only inside SHADOW_NEAR.
## Cheap: a handful of lights, a distance each, four times a second.
func _rank_shadows() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var eye: Vector3 = cam.global_position
	var live: Array = []      # [distance, light] for everything in range
	for i in range(_shadow_lights.size() - 1, -1, -1):
		var l: Light3D = _shadow_lights[i]
		if not is_instance_valid(l):
			_shadow_lights.remove_at(i)
			continue
		if not l.visible:
			l.shadow_enabled = false
			continue
		var d: float = l.global_position.distance_to(eye)
		# Near enough AND either on screen or close enough to be overhead. The frustum test
		# is the one that matters indoors: standing in a Deck B cabin puts you within 11 m
		# of two pole floodlights that are outside the hull and one deck down, and they
		# were each rendering a shadow map through the floor that nothing in the room could
		# ever show. Distance alone cannot tell those apart from the pole you are standing
		# under; "is the fixture itself in shot" can, for one dot product per light.
		#
		# SHADOW_ALWAYS is the exception that keeps the payoff: stand at the foot of a
		# floodlight and look DOWN at the pool of light, and the fixture is above and
		# behind the camera — out of frustum, in the one spot where your own shadow
		# stretching across the plating is the whole reason the light is there.
		var seen: bool = d <= SHADOW_ALWAYS or cam.is_position_in_frustum(l.global_position)
		if d > SHADOW_NEAR or not seen:
			l.shadow_enabled = false
		else:
			# Hysteresis: a light already holding a shadow slot is measured as if it were
			# SHADOW_HYSTERESIS metres closer than it really is, so it does not lose the slot
			# to a rival that is only marginally nearer this tick than last tick.
			var ranked_d: float = d - (SHADOW_HYSTERESIS if l.shadow_enabled else 0.0)
			live.append([ranked_d, l])
	live.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in range(live.size()):
		(live[i][1] as Light3D).shadow_enabled = i < SHADOW_BUDGET

func _skip(n: Node) -> bool:
	for g in SKIP_GROUPS:
		if n.is_in_group(g):
			return true
	var s: Script = n.get_script() as Script
	if s != null:
		for frag in SKIP_SCRIPTS:
			if s.resource_path.ends_with(frag):
				return true
	return false
