extends Node
## IS THERE A BUMP AT THE TOP OF EACH FLIGHT? — the owner's "have to jump over an invisible
## bump each landing", asked with the shape that actually walks the rig.
##
## WHY StairJunctionProbe CANNOT SEE THIS, which is the whole reason this file exists. That
## probe drops a RAY at 10 mm intervals and reports the worst STEP between adjacent samples.
## It comes back 0.0000 m at all ten junctions, and it is not lying — it is answering a
## different question. Two ways it misses a bump the player can feel:
##
##   1. A ray is a POINT. The thing that stops a 0.37 m capsule is anything protruding into
##      the volume it sweeps, and the capsule rests on the HIGHEST point under its whole
##      footprint — so a lip narrower than the sample spacing, or one the ray happens to
##      straddle, is invisible to it and solid to the player.
##   2. It measures DISCONTINUITY, not SHAPE. A ramp that overshoots its landing by 30 mm
##      over 50 mm of travel is a smooth 31-degree slope: every adjacent sample differs by
##      about 6 mm, so "worst step" stays tiny while the surface rises a full ankle above the
##      landing and comes back down. That is not a step. It is a bump, and you have to climb
##      it.
##
## So this one sweeps the PLAYER'S OWN CAPSULE down at each sample and records where it comes
## to rest — the real walkable height — then reports the profile's SHAPE across the junction:
## how far it rises above the landing it is joining, and whether that rise is a local hump
## rather than a monotonic arrival.
##
##   godot --headless --path . res://tests/StairBumpProbe.tscn

const PLAYER_RADIUS: float = 0.37
const STAND_HEIGHT: float = 1.8
## How far either side of the authored junction point to profile, and at what spacing.
const SPAN: float = 0.70
const SAMPLE: float = 0.02
## A rise above the landing plane bigger than this is something you can feel underfoot. The
## capsule rolls over about r*(1-cos(floor_max_angle)) = 117 mm before the contact normal
## calls it a wall, but long before that it is a stumble: 8 mm is roughly the point at which
## a plate seam stops being a seam.
const BUMP_TOL: float = 0.008

## [name, world point where the run hands over to the landing, direction of travel].
## Same ten junctions StairJunctionProbe uses, so the two are directly comparable.
const REAL := [
	["tower F1 head (y6 east pocket)", Vector3(28.5, 6.0, -2.9), Vector3(1, 0, 0)],
	["tower F2 head (y10 west pocket)", Vector3(23.5, 10.0, -1.1), Vector3(-1, 0, 0)],
	["tower F3 head (y14 east pocket)", Vector3(28.5, 14.0, -2.9), Vector3(1, 0, 0)],
	["west F1 head (mid landing)", Vector3(-3.2, 21.68, 13.5), Vector3(0, 0, 1)],
	["west F2 head (C terrace)", Vector3(-5.0, 25.1, 8.4), Vector3(0, 0, -1)],
	["boarding head (Deck B landing)", Vector3(8.6, 21.6, 3.4), Vector3(-1, 0, 0)],
	["tower F1 foot (wet deck)", Vector3(23.5, 2.0, -2.9), Vector3(1, 0, 0)],
	["tower F2 foot (y6 landing)", Vector3(28.5, 6.0, -1.1), Vector3(-1, 0, 0)],
	["west F2 foot (mid landing)", Vector3(-5.0, 21.68, 13.9), Vector3(0, 0, -1)],
	["boarding foot (topside)", Vector3(15.8, 18.0, 3.4), Vector3(-1, 0, 0)],
]

var failures: int = 0
var _space: PhysicsDirectSpaceState3D

func _ready() -> void:
	add_child(load("res://scenes/Main.tscn").instantiate())
	await get_tree().create_timer(6.0).timeout
	for i in range(20):
		await get_tree().physics_frame
	_space = get_viewport().get_world_3d().direct_space_state
	print("\nSTAIR BUMP — the PLAYER'S CAPSULE swept down every %d mm across each junction"
		% int(SAMPLE * 1000.0))
	print("%-36s %10s %10s %s" % ["junction", "over land", "hump", "verdict"])
	for j in REAL:
		_profile(String(j[0]), j[1] as Vector3, (j[2] as Vector3).normalized())
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

## Where does the player's capsule come to rest at `at`? Returns the height of the capsule's
## BOTTOM, i.e. the walkable floor as the body actually experiences it, or -1e9 for nothing.
func _floor_at(at: Vector3) -> float:
	var cap := CapsuleShape3D.new()
	cap.radius = PLAYER_RADIUS
	cap.height = STAND_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 1
	q.collide_with_areas = false
	# TWO CASTS, AND THE SECOND ONE IS THE MEASUREMENT.
	#
	# `cast_motion` bisects the motion it is given, and the result is quantised to roughly
	# 1/256 of it. Over the 3.2 m drop the first cut of this used, that is 12.5 mm — so the
	# probe reported a 12.5 mm "hump" at all ten junctions, identical to the millimetre and
	# unmoved by a real geometry change, because it was reporting its own step size rather
	# than the rig's. (A number that comes back the same everywhere is not a measurement, it
	# is a constant; this file's whole reason for existing is that the previous probe made the
	# same class of mistake.) So: one long cast to find the floor to within a centimetre, then
	# a second 40 mm cast straddling it, whose quantum is 0.16 mm.
	var coarse: float = _cast_from(q, at + Vector3(0, 1.6 + STAND_HEIGHT * 0.5, 0), 3.2)
	if coarse < -1e8:
		return -1e9
	var fine: float = _cast_from(q, Vector3(at.x, coarse + STAND_HEIGHT * 0.5 + 0.02, at.z), 0.04)
	return fine if fine > -1e8 else coarse

## One downward sweep; returns the height of the capsule's SOLE at rest, or -1e9 for nothing.
func _cast_from(q: PhysicsShapeQueryParameters3D, centre: Vector3, dist: float) -> float:
	q.transform = Transform3D(Basis.IDENTITY, centre)
	q.motion = Vector3(0, -dist, 0)
	var res: PackedFloat32Array = _space.cast_motion(q)
	if res.is_empty():
		return -1e9
	return centre.y - res[0] * dist - STAND_HEIGHT * 0.5

func _profile(nm: String, at: Vector3, dir: Vector3) -> void:
	var land: float = at.y
	var n: int = int(SPAN / SAMPLE)
	var over_max: float = 0.0          ## worst rise ABOVE the landing plane
	var over_at: float = 0.0
	var hump: float = 0.0              ## worst local maximum: rises then falls again
	var prof: Array[float] = []
	var offs: Array[float] = []
	for i in range(-n, n + 1):
		var d: float = float(i) * SAMPLE
		var f: float = _floor_at(at + dir * d)
		if f < -1e8:
			continue
		prof.append(f)
		offs.append(d)
	if prof.size() < 5:
		print("%-36s %10s %10s no surface" % [nm, "-", "-"])
		failures += 1
		return
	# The landing's own plateau: the far side of the junction, well past the lip.
	for i in range(prof.size()):
		if offs[i] < 0.05:
			continue
		over_max = maxf(over_max, prof[i] - land)
		if prof[i] - land > over_max - 1e-9:
			over_at = offs[i]
	# A HUMP is a rise you must come back DOWN from — the thing you notice. Anything that
	# merely arrives at the landing height and stays there is a correct junction.
	for i in range(1, prof.size() - 1):
		var later_min: float = prof[i]
		for k in range(i + 1, prof.size()):
			later_min = minf(later_min, prof[k])
		hump = maxf(hump, minf(prof[i] - prof[i - 1], prof[i] - later_min))
	# FAIL ON THE HUMP ALONE. `over land` is reported because it is worth seeing, but at a
	# flight's FOOT the surface ahead is a staircase and rising 675 mm over 700 mm is the
	# stairs working. What you can feel underfoot is a rise you then have to come back DOWN
	# from, and that is what `hump` measures.
	var bad: bool = hump > BUMP_TOL
	if bad:
		failures += 1
	print("%-36s %+9.1f %+9.1f %s" % [nm, over_max * 1000.0, hump * 1000.0,
		("BUMP at %+.2f m" % over_at) if bad else "clean"])
