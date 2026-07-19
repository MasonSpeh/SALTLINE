extends RefCounted
## DOORFRAME — the ONE source of truth for the casing around every opening on the rig.
##
## The bug this exists to kill: frames were hand-authored next to the hole they were
## meant to line, with their own literal numbers. When a hole moved, or a wall got a
## different height, or an opening was cut 1.6m wide instead of 1.4m, the frame did not
## follow — so heads floated above their openings, jambs overshot corners and left stubs
## of steel hanging in space, and casings z-fought the wall face they were flush with.
##
## The fix is that a frame is never authored: it is DERIVED from the opening rect. Every
## doorway builder hands this the rect it actually cut — floor-level centre, width,
## height, wall thickness, wall axis — and gets back a frame that can only agree with it.
##
## GEOMETRY (all measured from the opening rect, nothing literal):
##   jambs  occupy the reveal, inboard from each opening edge:  [w/2-JAMB, w/2]
##          and run from the FLOOR to the underside of the head: [0, h-HEAD]
##   head   spans jamb-outer to jamb-outer (= the full opening width) and fills the
##          remaining height: [h-HEAD, h]. Its ends land exactly on the jamb outers, so
##          the two corners butt-join closed — no overshoot past the corner, no gap.
##   sill   (optional coaming) butts BETWEEN the jambs: [-w/2+JAMB, w/2-JAMB].
##   depth  is wall_t + 2*PROUD, centred on the wall plane, so the liner stands a little
##          proud of BOTH wall faces and no frame face is ever coplanar with a wall face
##          (coplanar faces are what z-fight).
##
## BITE is a 4mm bite taken into the wall at each outer edge so the frame/wall join is a
## solid overlap rather than two coincident faces. It is an order of magnitude below the
## 2cm tolerance DoorFrameProbe allows, so it never reads as an overshoot.
##
## CLEAR OPENING: because the jambs line the reveal, the walkable/hangable hole is
## clear_w() x clear_h(), not w x h. Door leaves MUST be sized off those, or the leaf
## clips through its own frame. That is the whole reason both are exposed as functions.
##
## Every frame registers itself in group GROUP with the opening rect in metadata, which
## is what tests/DoorFrameProbe.tscn audits. A doorway that does not come through here
## is invisible to the probe, so route openings through it rather than around it.

const JAMB: float = 0.09      ## jamb thickness, measured into the opening
const HEAD: float = 0.10      ## head depth, measured down from the opening top
const PROUD: float = 0.03     ## how far the liner stands off each wall face
const BITE: float = 0.004     ## overlap into the wall, kills coplanar-face z-fighting
const SILL_H: float = 0.035   ## coaming height
const GROUP: String = "doorframe"

## Clear width/height of the hole once the liner is in — size door leaves off THESE.
static func clear_w(w: float) -> float:
	return w - 2.0 * JAMB

static func clear_h(h: float) -> float:
	return h - HEAD

## Build head + jambs (+ sill) for an opening whose floor-level centre is `floor_center`,
## lying in a wall that runs along X when `along_x`, else along Z. Frame members are
## visual only: the wall around the hole already carries the collision, and a colliding
## liner would pinch a 1.4m doorway down to something a 0.4m capsule catches on.
static func build(parent: Node3D, floor_center: Vector3, along_x: bool, w: float, h: float,
		wall_t: float, mat: Material, sill: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "DoorFrame"
	parent.add_child(root)
	root.global_position = floor_center
	root.add_to_group(GROUP)
	root.set_meta("open_center", floor_center)
	root.set_meta("open_along_x", along_x)
	root.set_meta("open_w", w)
	root.set_meta("open_h", h)
	root.set_meta("open_t", wall_t)
	var depth: float = wall_t + PROUD * 2.0
	var half: float = w * 0.5
	var jamb_h: float = h - HEAD
	# Jambs: inboard face at +-(half-JAMB), outboard face biting BITE into the wall.
	for s in [-1.0, 1.0]:
		var inner: float = s * (half - JAMB)
		var outer: float = s * (half + BITE)
		_slab(root, mat, (inner + outer) * 0.5, jamb_h * 0.5,
			absf(outer - inner), jamb_h, depth, along_x)
	# Head: ends land on the jamb outers, underside lands on the jamb tops.
	_slab(root, mat, 0.0, jamb_h + HEAD * 0.5, w + BITE * 2.0, HEAD, depth, along_x)
	if sill:
		_slab(root, mat, 0.0, SILL_H * 0.5, clear_w(w), SILL_H, depth, along_x)
	return root

## One frame member. `u` is the offset along the wall, `y` the height off the floor.
static func _slab(root: Node3D, mat: Material, u: float, y: float,
		su: float, sy: float, depth: float, along_x: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(su, sy, depth) if along_x else Vector3(depth, sy, su)
	bm.material = mat
	mi.mesh = bm
	root.add_child(mi)
	mi.position = Vector3(u, y, 0.0) if along_x else Vector3(0.0, y, u)
