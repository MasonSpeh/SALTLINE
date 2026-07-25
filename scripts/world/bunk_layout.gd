extends RefCounted
## SINGLE SOURCE OF TRUTH for the bunkhouse cabin furniture grid (topside / Deck A).
##
## WHY THIS FILE EXISTS. The bunk positions used to be hand-typed in rig_builder AND
## hand-typed again in interior_props, and the two drifted: rig_builder moved the wardrobe
## lockers onto the head wall, interior_props kept placing each crew member's mug, towel and
## keepsake on the locker top's OLD bed-relative offset, and six objects ended up hovering in
## mid-air where the lockers used to stand. Lining the bunks up against the cabin walls moved
## them again and would have re-broken the same six placements a second time.
##
## So the geometry lives here once and both builders derive from it. Nothing in this file
## depends on either builder, so there is no load cycle — preload it BY PATH from both
## (the project convention: Godot's global class cache lags newly added class_name files).
##
## Room: x -28..-8, z 4..18, floor y 18.0. Corridor z 10..12 stays empty. Cabins are the
## three bays either side of it, split by dividers on the CABIN_X lines.

const DECK_Y: float = 18.0
## The walking surface, NOT the structural deck: every finished room carries a 3 cm floor
## covering laid at deck + 0.035, so anything standing on the floor has its base here.
const FLOOR_TOP: float = 18.05

## Cabin divider lines (wall CENTRES). Three cabins per row: [i]..[i+1].
const CABIN_X: Array = [-28.0, -21.33, -14.66, -8.0]
const Z_WALL_SOUTH: float = 4.0     ## south row's outer (head) wall line
const Z_WALL_NORTH: float = 18.0    ## north row's outer (head) wall line

const WALL_HALF: float = 0.125      ## walls are WALL_T 0.25 centred on their line
const BED_HALF_W: float = 0.5       ## bed frame is 1.0 x 2.1 (bed.gd)
const BED_HALF_L: float = 1.05
const CLEAR: float = 0.02           ## breathing room so nothing z-fights the plaster

## Wardrobe locker: 0.5 x 1.8 x 0.5 visual centred at y+0.9, tucked to the head wall.
const LOCK_DX: float = 1.15         ## locker centre, east of the bunk centre
const LOCK_Z_S: float = 4.55        ## south row head wall
const LOCK_Z_N: float = 17.45       ## north row head wall
const LOCK_HALF: float = 0.25       ## half its 0.5 m footprint
## Resting plane on the locker lid, above DECK_Y: 0.9 centre + 0.9 half-height, lid proud.
const LOCK_TOP: float = 1.86

## A bunk sits in the CORNER of its cabin: long side against the cabin's west divider,
## head against the outer wall. `cabin` is 0..2 (west to east), `south` picks the row.
static func bed_pos(cabin: int, south: bool) -> Vector3:
	var x: float = float(CABIN_X[cabin]) + WALL_HALF + BED_HALF_W + CLEAR
	var z: float = (Z_WALL_SOUTH + WALL_HALF + BED_HALF_L + CLEAR) if south \
		else (Z_WALL_NORTH - WALL_HALF - BED_HALF_L - CLEAR)
	return Vector3(x, DECK_Y, z)

## Heads point at the wall they are against: south row faces -Z, north row +Z.
static func bed_yaw(south: bool) -> float:
	return 0.0 if south else 180.0

## All six bunks, south row first (west to east), then north row — the order every
## consumer indexes by, so bunk i is the same bunk in every file.
static func beds() -> Array:
	var out: Array = []
	for south in [true, false]:
		for c in range(3):
			out.append(bed_pos(c, bool(south)))
	return out

## Centre of the locker lid belonging to a given bunk — the surface personal items rest on.
static func locker_pos(bed: Vector3) -> Vector3:
	var lz: float = LOCK_Z_S if bed.z < 11.0 else LOCK_Z_N
	return Vector3(bed.x + LOCK_DX, DECK_Y + 0.9, lz)

static func locker_top(bed: Vector3) -> Vector3:
	var p: Vector3 = locker_pos(bed)
	return Vector3(p.x, DECK_Y + LOCK_TOP, p.z)
