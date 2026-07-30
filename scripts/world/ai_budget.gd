class_name AiBudget extends RefCounted
## AI DECIMATION — run distant and hidden creatures less often, at the SAME speed.
##
## Measured (tests/tps_profile.tscn): the fauna's per-frame GDScript, not its draw calls, is
## what holds this rig under 30 fps. Almost all of that is spent on animals nobody is looking
## at — the reef community 40-90 m down in the wreck field, the deep giants under an opaque
## sea while the player is on deck. They cannot be deleted (they are the world) and they
## cannot simply be frozen (their day/night state machines have to keep their place). So they
## are TICKED LESS OFTEN, and handed the time they missed.
##
## THE TRAP THIS EXISTS TO AVOID, which is not obvious and which every naive attempt hits:
## skipping frames with `process_mode` (or an early `return`) SLOWS THE ANIMAL DOWN. Godot
## hands `_process` the time since the LAST FRAME, not the time since that node last ran. A
## creature that runs one frame in four therefore integrates a quarter of the elapsed time
## and crawls at a quarter speed — a shark on a 4x stride patrols at 25% and a crab's night
## emergence takes four times as long, which reads as the world going wrong, not as an
## optimisation. Every caller here accumulates its own delta and acts on the SUM, so the
## animal covers exactly the same ground in the same wall-clock time. tests/AiBudgetProbe
## asserts that: it measures real creature speeds at stride 1 and at max stride and fails if
## they differ.
##
## Usage — four lines at the top of a species' _process, nothing else changes:
##     var _ai_acc: float = 0.0
##     func _process(delta: float) -> void:
##         _ai_acc += delta
##         if not AiBudget.due(self, _ai_acc):
##             return
##         delta = _ai_acc
##         _ai_acc = 0.0
##         ...body unchanged, `delta` now means "time since this animal last thought"...

## Tick every frame inside this radius. Anything the player can be close enough to read the
## motion of runs at full rate — decimation must never be visible, and the only honest way
## to guarantee that is to not do it where it could be seen.
const NEAR_M: float = 18.0
## Half rate out to here, quarter rate beyond.
const MID_M: float = 42.0
const FAR_STRIDE: int = 4
## Anything not actually being drawn — the whole underwater world while the camera is
## topside (underwater_world._cull_topside), a flushed gull, a species outside its hours.
##
## THIS IS DELIBERATELY LOOSER THAN FAR_STRIDE, and MAX_STEP is what makes that safe. A far
## creature is still on screen, so its motion has to hold up to being watched; a hidden one
## is not being drawn at all, and the only thing that has to hold up is that its state
## machine and its position agree with wall-clock time when it comes back — which the delta
## accumulation guarantees exactly, at any stride.
##
## So the real ceiling here is not visual, it is numerical: the species code smooths with
## `lerpf(x, target, delta * k)` and the largest k is 6.0, so no accumulated step may exceed
## MAX_STEP. `due()` enforces that unconditionally, which means raising this number cannot
## make any creature take a bigger step than it already can — it can only stop the stride
## being the binding constraint before MAX_STEP is. At a 20 ms frame, 8 frames is 0.16 s and
## MAX_STEP releases it at 7; at 60 fps it releases at 9. Either way the animal thinks at
## ~6 Hz instead of ~12 Hz while nobody is looking at it.
##
## Worked, because the bound moved and the next reader deserves the number rather than the
## reassurance: at 30 fps the accumulator crosses MAX_STEP on the 5th frame at 0.1667 s, so
## k_max * step is 6.0 * 0.1667 = 1.000 — `lerpf`'s snap point, the last stable value, where
## stride 4 sat at 0.800. Above 4 the stride stops setting the worst step at all (MAX_STEP
## plus one frame does), which is why there is nothing to gain from going higher and why
## MAX_STEP is the constant that must not move. tests/TestRunner asserts both bounds directly
## for every stride these constants name.
const HIDDEN_STRIDE: int = 8

## THE CEILING ON HOW MUCH TIME MAY BE HANDED OVER AT ONCE, seconds.
##
## The species code is full of `lerpf(x, target, delta * k)` smoothing. That form is stable
## only while `delta * k < 1`; past 1 it overshoots the target and past 2 it oscillates
## away from it. The largest k in the decimated classes is 6.0 (the isopod's freeze
## reaction), so the accumulated step is capped where 6 * step stays under 1. The cap is
## applied by SHORTENING THE STRIDE, never by clipping the delta — clipping the delta is
## just the frame-skipping bug again, wearing a hat.
const MAX_STEP: float = 0.15

## Set false to measure/verify against undecimated behaviour (tests/AiBudgetProbe).
static var enabled: bool = true

# The camera position, fetched ONCE per frame. Every creature needs it and there are ~90 of
# them; get_viewport().get_camera_3d() per creature per frame is a tree walk each time.
static var _eye_frame: int = -1
static var _eye: Vector3 = Vector3.ZERO
static var _eye_ok: bool = false

static func eye(n: Node) -> Vector3:
	var f: int = Engine.get_process_frames()
	if f != _eye_frame:
		_eye_frame = f
		_eye_ok = false
		if n.is_inside_tree():
			var cam: Camera3D = n.get_viewport().get_camera_3d()
			if cam != null:
				_eye = cam.global_position
				_eye_ok = true
	return _eye

## How many frames apart this node may think, right now.
static func stride(n: Node3D, near_m: float = NEAR_M) -> int:
	if not enabled:
		return 1
	if not n.is_visible_in_tree():
		return HIDDEN_STRIDE
	var e: Vector3 = eye(n)
	if not _eye_ok:
		return 1
	var d2: float = e.distance_squared_to(n.global_position)
	if d2 > MID_M * MID_M:
		return FAR_STRIDE
	if d2 > near_m * near_m:
		return 2
	return 1

## Is this the frame `n` gets to think on? `acc` is its accumulated delta.
##
## The phase comes from the instance id, so the ~90 decimated creatures do not all land on
## the same frame — spreading them is the difference between a smaller average frame and the
## same average frame with a stutter every fourth one.
##
## The MAX_STEP rule is deliberately a SEPARATE, unconditional gate rather than a smaller
## stride: whatever the distance says, no animal ever goes longer than MAX_STEP without
## thinking, so the accumulated delta a caller receives is bounded and its `delta * k`
## smoothing stays in its stable range. At a 30 fps frame that makes 4 the real ceiling
## anyway; at 15 fps it quietly falls back to 2, which is the right direction — a machine
## already missing frames should not also be handing its animals quarter-second steps.
static func due(n: Node3D, acc: float, near_m: float = NEAR_M) -> bool:
	if not enabled or acc >= MAX_STEP:
		return true
	var s: int = stride(n, near_m)
	if s <= 1:
		return true
	return (Engine.get_process_frames() + int(n.get_instance_id())) % s == 0
