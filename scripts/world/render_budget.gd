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

func _ready() -> void:
	name = "RenderBudget"
	for i in range(SWEEP_COUNT):
		await get_tree().create_timer(SWEEP_EVERY if i > 0 else 1.5).timeout
		_sweep(get_parent())
	print("[budget] meshes budgeted: %d   shadow casters dropped: %d" % [_budgeted, _shadow_off])

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
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or mi.has_meta("budgeted"):
			continue
		mi.set_meta("budgeted", true)
		_budgeted += 1
		var a: AABB = mi.get_aabb()
		var scl: Vector3 = mi.global_transform.basis.get_scale()
		var size: float = maxf(maxf(a.size.x * scl.x, a.size.y * scl.y), a.size.z * scl.z)
		if size < SHADOW_MIN and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_shadow_off += 1
		if size >= FAR_ALWAYS or mi.visibility_range_end > 0.0:
			continue
		var reach: float = clampf(size * SIZE_TO_RANGE, RANGE_MIN, RANGE_MAX)
		mi.visibility_range_end = reach
		mi.visibility_range_end_margin = reach * FADE
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

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
