extends RefCounted
## ONE SKELETON, EVERY POSE BLENDED — the s37 cat animation core.
##
## NO `class_name` ON PURPOSE — preload by path (AGENT_TRAPS: a global class on a new file
## breaks the import creating its own cache entry).
##
## WHAT THIS REPLACES, AND WHY IT COULD NEVER BE SMOOTH. s35/s36 drove SIX separate rigged
## meshes and changed state with a `visible` flip: one frame a walking cat, the next frame a
## sitting one, with nothing in between — a whole-body teleport at every transition, which is
## exactly the owner's "doesn't move intuitively/fluidly with its body skeleton". Worse, the
## gait swung limbs on meshes AUTHORED mid-stride (cat_run2 is a frozen gallop), so the
## oscillation was layered on top of an already-posed body and the legs double-counted.
##
## THE ARCHITECTURE NOW. One mesh — the neutral STANDING cat — one 41-bone skeleton, and a
## pose LIBRARY extracted from the other rigged meshes' rest poses (they all share Tripo's
## humanoid template bone-for-bone; tools/extract_cat_poses.py asserts it). Each behaviour
## state names a target pose; every frame each bone SLERPS toward its target and the gait is
## ADDED on top as small swing rotations. Nothing is ever swapped, so every transition —
## sit to walk, run to groom, anything to anything — is continuous by construction, and the
## blend cost is ~40 slerps a frame on one animal.
##
## THE TWO RATE RULES, both from AGENT_TRAPS and both load-bearing here:
##   * every ease uses `1 - exp(-rate * dt)` — `delta * k` overshoots past dt*k > 1 and this
##     animal is under AiBudget, which hands it SUMMED deltas;
##   * the gait phase is advanced by DISTANCE ACTUALLY MOVED / stride, never by `t * speed` —
##     a rate written into an accumulating clock teleports the phase (the shoal detonation
##     bug), and commanded-speed advance treadmills the legs against a blocked step.

const SWING := Vector3(1, 0, 0)   ## limb chains run local +Y; fore-aft swing is about X

## THE BODY'S OWN AXES, in skeleton space — measured, not assumed (tests/BoneDump prints the
## stand mesh's AABB as 1.0 x 0.566 x 0.265, so the nose-to-tail axis is X, up is Y, across
## the body is Z). The node's yaw carries the whole skeleton, so skeleton space IS body space.
const BODY_FWD := Vector3(1, 0, 0)
const BODY_UP := Vector3(0, 1, 0)
const BODY_SIDE := Vector3(0, 0, 1)

## HOW FAR THE DISTAL JOINTS LAG THE PROXIMAL ONE, in cycles. Overlapping action: an animator
## never keys a whole limb on the same frame — the paw follows the wrist follows the elbow, and
## that lag is most of what separates a live limb from a hinged stick. Small on purpose; past
## about 0.06 the paw visibly detaches from the leg.
const DRAG: float = 0.045   ## s45c: a touch more overlap down the limb — "smoother"

## WHERE IN THE SWING THE PAW TOPS OUT, as a fraction of the swing. Well before the middle on
## purpose, and MEASURED rather than chosen: the paw's whole lift has to be traversed in about
## eleven frames at this cadence, so where the apex sits decides how that budget is split
## between LEAVING the deck and ARRIVING at it. An early apex snaps the paw up and then gives
## it the long back half of the swing to settle — which is both what a cat does and what the
## brief asks for ("touchdown is quiet"; a fast toe-off is "less objectionable").
##
## Measured (tests/GaitScratch block 9, drawn paw, mm of one-frame step at each transition):
##     apex   step@toe-off lf/rf   step@touchdown lf/rf/rh   vertical speed into contact
##     0.26        22.1  27.4          5.7   4.4  14.9         17.6  14.1   5.5
##     0.32        14.9  18.3         13.9   5.3  18.9         20.3  20.7   9.4
##     0.42         8.4  10.7         25.7  19.7  22.8         27.2  27.1  14.4
## The total is roughly conserved and the apex decides which end pays it. 0.30 puts the
## quieter end at the plant.
##
## STAYS AT 0.30 (s54), AND HERE IS WHY THE OBVIOUS MOVE IS WRONG. A design pass this session
## argued 0.30 -> 0.15 on a real measurement: the DRAWN apex trails the commanded one by about
## 0.20 of the swing (commanded 0.15 -> drawn 0.325, 0.22 -> 0.375, 0.30 -> 0.425, 0.40 ->
## 0.625), so 0.15 is the commanded value that puts the drawn peak where this header wants it,
## and it does halve the touchdown step (lf 7.52 -> 2.95 mm).
##
## IT WAS SCORED ON ONE END OF THE SWING. Measured on BOTH, at the same speed, drawn:
##     apex   toe-off step lf/rf/lh/rh        touchdown step lf/rf/lh/rh      seam total
##     0.30    14.9  17.7   8.6   5.7          7.5   4.8   3.1  17.5           79.8 mm
##     0.15    39.1  43.4  29.2   8.2          3.0   2.7   1.6  12.2          139.3 mm
## The apex is bounded from below BY THE FRAME RATE, and no amount of C1 continuity fixes it:
## the swing is ~11.4 frames, so an apex at 0.15 is 1.7 frames, and `_swing_bump` is already at
## 63% of full lift one frame after toe-off — 54 mm of commanded paw in a single frame. The
## zero rate at s=0 is true and irrelevant at a scale four times finer than a frame. Trading a
## 7 mm slap at the plant for a 39 mm snap at the lift is not a fix, it is a relocation.
##
## What DID survive from that pass is the half of it that costs nothing: the authored knee fold
## does not move an IK target, so it can have its own, earlier apex (`FOLD_APEX`) and the paw
## does not have to pay for it. With `FOLD_FORE/HIND` down to 0.18/0.15 and `FOLD_APEX` 0.18,
## at 0.30 the plant improves on every limb and the lift does not move:
##     toe-off   14.9 -> 14.8   17.7 -> 17.8   8.6 -> 8.6   5.7 -> 5.8 mm
##     touchdown  7.5 ->  4.0    4.8 ->  3.7   3.1 -> 2.4  17.5 -> 12.2 mm
##     arrival   18.5 -> 10.6   14.0 -> 10.5   9.6 -> 7.6   9.7 ->  6.7 mm/frame
##
## See `_swing_bump` — the profile is C1 at both ends AND at the apex, so a zero rate here is
## a real maximum rather than the per-segment ease this repo has a trap about (`0.5-0.5*cos`
## applied to every segment stops the value dead at every key).
static var SWING_APEX: float = 0.30
## HOW MUCH OF THE DERIVED BODY DROP IS ACTUALLY PAID (see `_body_drop`), and HOW BIG THE
## WALK'S HIP BOB IS. These two are ONE decision, not two, because they are the only things
## that move a socket vertically at a walk — and on this rig three of the four chains sit at
## 98-100% of their own reach cap, so a socket that rises carries a PLANTED PAW up with it
## however hard the solve tries to hold it. The bob is therefore a term in the foot-slap
## budget, not a style knob, and the pair has to be measured together.
##
## Measured (tests/GaitScratch block 8, live walk at 1.125 m/s, paw rise scored over the
## middle 70% of each phase-gated contact so touchdown and toe-off do not count; lh omitted —
## it cannot span its own stance at any body height and is the re-rig, see `_body_drop`):
##
##   crouch  bob | hip below rest | PLANTED PAW RISE lf/rf/rh |  IN-STANCE SLIDE lf/rf/rh
##     0.00   38 |      -19 mm    |   54.2   27.1   31.6 mm   |  4.26  2.57  3.70 mm/frame
##     0.55   14 |       14.7     |   15.9    5.0    7.4      |  1.23  2.49  0.78
##     0.65   14 |       18.6     |   12.3    5.0    4.7      |  1.09  0.20  0.78
##     0.75   10 |       24.6     |    6.0    4.9    6.2      |  0.19  0.19  1.91
##     0.75   14 |       22.6     |    8.6    5.0    4.3      |  0.51  0.20  2.53
##     0.85   14 |       26.5     |    6.0    4.9    5.8      |  0.20  0.19  5.24
##     1.20   38 |       28.4     |   13.3    5.1   13.9      |  1.07  0.35  8.91
##
## There is a WINDOW, and it is about twelve millimetres wide. Above ~19 mm of drop the
## saturated chains stop riding their sockets and the paws go quiet; below ~31 mm the binding
## hind's hip is still inside ROM_PROX. A 38 mm bob is three times that window, which is why
## the s52 walk lifted its planted paws 27-54 mm — the bob was doing it, and the stance arc
## was doing the rest. 0.75 of the derived drop with a 14 mm bob sits in the middle of the
## window: every payable paw travels 4-9 mm while it is on the deck and slides 0.2-2.5 mm a
## frame, against 27-54 mm and 2.6-4.3 before.
##
## THE BOB IS SMALLER AND THAT IS THE POINT, not a regression. s52 raised it to 38 mm for
## "little bounces"; this brief asks for the opposite and is right — "the trunk stays level
## and quiet; the visible motion is in the limbs". A walking cat's trunk barely rises. If the
## owner wants the bounce back the cost is now a number rather than an argument: at 38 mm the
## planted left fore rides 34 mm and the right hind 25 mm (crouch 0.60 row of the same grid).
static var CROUCH_K: float = 0.75
static var BOB_WALK: float = 0.014
## HOW MUCH OF EACH LIMB'S REST FORE-AFT OFFSET IS TAKEN OUT OF ITS STANCE SWEEP — see
## `_centre_off`. 0 = sweep centred on the rest paw (every session up to s52), 1 = centred
## under the socket. A VAR because it moves where the animal plants its feet.
static var STANCE_CENTRE: float = 1.0
## THE AUTHORED SWING FOLD, radians of elbow / stifle on top of whatever the IK already had to
## bend to reach the path — the knee half of the owner's "knee and wrist bends back... then
## knee straightens and paw sticks back out to catch".
##
## 0.42/0.36 -> 0.18/0.15 (s54), AND THE TOP HALF OF THE OLD AMPLITUDE WAS NEVER DRAWN. The
## elbow/stifle bound is `ROM_DIST_FOLD` = 1.35 rad = 77.35 deg, and measured at the shipped
## walk lf, rf and rh all sat at EXACTLY 77.35 for three to four consecutive frames — a flat
## top, which is the same clamp artefact s50 found on ROM_BLADE and which draws as a stutter
## at the top of the fold rather than as a deeper bend. A/B at 0.21/0.18: drawn peak LIFT
## unchanged (lf 92.9, rf 113.4 mm) and drawn peak elbow unchanged, because the surplus was
## being clamped away — it existed only as a touchdown penalty on the way back down.
##
## Measured at the shipped walk, fraction of swing frames with the elbow/stifle sitting exactly
## on ROM_DIST_FOLD — i.e. how much of the fold is a clamp rather than a bend:
##     0.42/0.36   lf 21.5%   rf 18.9%   rh 23.7%
##     0.18/0.15   lf 11.5%   rf 11.9%   rh 21.2%
## and the drawn early-swing elbow is UNCHANGED (s 0.05/0.15/0.25: 19.9/39.5/58.7 deg before,
## 20.0/39.6/58.8 after) — the bend the owner sees comes from the path the IK has to reach, not
## from this layer, which is the lesson the s49 revert paid for. rh does not improve because
## its IK demand alone saturates: that is the rig (docs/CAT_RIG_CEILING.md §3).
##
## It is ALSO a rate decision. The fold rides `_swing_bump`, whose peak slope on the rise is
## `PI/(2*FOLD_APEX)` per unit s; over an 11.4-frame swing that is 22.09 deg/frame for a 0.42
## fold at an 0.18 apex, against a `LIMB_MAX_RATE` ceiling of 18.14 — i.e. the old amplitude at
## the new timing would ask for MORE THAN THE LIMITER WILL PASS and be smeared as well as
## clamped. At 0.18 it is 9.47. Kept as vars so tests/gait_scratch.gd can sweep them in one run.
static var FOLD_FORE: float = 0.18
static var FOLD_HIND: float = 0.15
## ...AND THE FOLD KEEPS ITS OWN APEX, because it is not paying the same bill as the lift.
## `SWING_APEX` moves the PATH, and the path's apex is bounded from below by the frame rate:
## the paw has to traverse its whole 85 mm inside `apex * 11.4` frames, so an apex at 0.15 is
## 1.7 frames and snaps the foot off the deck (measured: drawn toe-off step 14.9 -> 39.1 mm on
## lf). The authored fold moves no target — it is composed onto the solved bone — so its only
## cost is its own joint rate, and 0.18 rad over 2 frames is 5.2 deg/frame against an 18.14
## ceiling. So the KNEE can lead and the PAW does not have to: the fold peaks early (the
## owner's "leg goes up, forward, knee and wrist bends back") while the lift keeps the
## gentler apex that keeps both ends of the swing quiet.
static var FOLD_APEX: float = 0.18
## HOW MUCH OF THE LIMB'S SWING THE SHOULDER BLADE TAKES — and the old 0.34 is why the owner
## could not see it. A cat has no functional clavicle: the scapula floats on muscle and IS the
## proximal foreleg segment, travelling further than almost any other mammal's, and it riding
## up over the line of the spine at the top of the reach is most of why a walking cat flows
## instead of hinging at the humerus. Arithmetic on the shipped numbers: the walk table's peak
## reach is 0.30 and `amp` at a walk is ~0.85, so 0.34 bought +/-5.0 degrees — TEN degrees
## peak-to-peak on a joint whose real travel is twenty to twenty-five. It was working exactly
## as written and far too small to see. 0.85 puts it at 24.8 peak-to-peak, inside ROM_BLADE's
## 21.8 either way.
const BLADE_TRAVEL: float = 0.85

## ---------------------------------------------------------------- the girdles (s52)
##
## THE OWNER'S "LEGS SHOULD ARTICULATE MORE TO MOVE THE BODY FORWARD" IS A DESCRIPTION OF
## GIRDLE EXCURSION, AND THIS RIG CAN ONLY PAY A LITTLE OF IT. In a real cat the scapula
## slides fore-aft over the ribcage and the pelvis counter-rotates about its long axis, so a
## large slice of the stride is girdle reach rather than leg swing. The engine had none of it:
## every limb swung from a socket pinned to the torso.
##
## Both girdles are now driven, phase-locked to the gait, and `_solve_leg` sees them EXACTLY
## because it already carries its target back through the live parent chain — so a socket that
## moves forward at the plant costs the leg that much less reach, and the ground the paw covers
## is leg sweep PLUS girdle travel. The budget below is MEASURED off the skeleton at bake
## (`_prep_ik`), never assumed, and it is added to the sweep the stride is derived from — so
## foot-lock survives by construction, which is the property the whole design rests on.
##
## WHAT IT IS ACTUALLY WORTH HERE, measured (tests/GaitScratch, block 2), in metres of
## fore-aft SOCKET travel per radian of girdle rotation:
##     pelvis yaw -> hip socket        lh -0.0189   rh +0.0189
##     chest  yaw -> shoulder socket   lf -0.0712   rf +0.0906
##     blade swing -> shoulder socket  lf +0.0003   rf -0.0230
## The pelvic lever is TINY and the reason is a measured defect, not a tuning choice: this
## auto-rig puts the right hind socket 9 mm off the body centreline (`sock_z` +0.0090) and the
## left hind's socket at x +0.1686 — at the FRONT of the animal, the stretched-backwards chain
## docs/CAT_RIG_CEILING.md §3 describes. A yaw's lever arm IS that lateral offset, so the
## binding limb's pelvic girdle is worth about 8 mm of stride and can never be worth more
## without a re-rig. The thoracic lever is real (71-91 mm/rad) and the fore girdle earns
## 19-24 mm. Both are in; neither is where the stride came from. See the s52 DEVLOG.
##
## THE YAWS ARE OFF (s53), AND THIS IS THE OWNER'S "SHE WOBBLES SIDE TO SIDE WHEN SHE WALKS".
##
## Two things make it a defect rather than a taste call, and the second is the one that settles
## it. First the axis: the paragraph above justifies the amplitude by citing a walking
## quadruped's pelvis rotating "about its LONG AXIS by ~10-15 degrees" — a quadruped's long
## axis is the fore-aft one, so that citation describes ROLL (pelvic list), and the code
## applied YAW, about the vertical. The anatomy never supported the axis that shipped.
##
## Then the ledger, measured on this rig rather than argued (tests/GaitScratch block 7,
## a live walk at each amplitude, reading the DRAWN bones):
##
##     pelv  chest | rump lateral  head lateral  Spine02 lateral | walk sweep   stride
##     0.22   0.16 |    77.69 mm      46.65 mm         27.41 mm  |   0.2316    0.4453
##     0.00   0.16 |     1.61            37.69          3.65     |   0.2233    0.4293
##     0.22   0.00 |    77.69            27.36         27.41     |   0.2316    0.4453
##     0.00   0.00 |     1.61             2.66          3.65     |   0.2233    0.4293
##     0.08   0.00 |    28.49            10.36         10.58     |   0.2263    0.4352
##
## The two yaws own 76.1 of the 77.7 mm of rump swing and 44.0 of the 46.6 mm at the head; the
## pelvis and chest ROLLS and the spine bend together own 1.6-3.7 mm. There is no other lateral
## contributor of any size — the bob is vertical and `ship_cat._face` is a monotone exponential
## toward the heading with nothing per-stride in it. That 77.7 mm of rump, at 2.5 strides a
## second, IS the report.
##
## And what it bought: CHEST_YAW buys EXACTLY NOTHING. The stride is set by the shortest limb
## and that is rh, a hind — the fores' envelopes (0.369 and 0.401 m) are not remotely binding,
## so the thoracic girdle's real 71-91 mm/rad of socket travel never reaches the stride at all.
## PELVIS_YAW buys 8.3 mm of the binding limb's 232 mm sweep, i.e. 16 mm of stride (3.6%), for
## 25.2 degrees of visible rump swing. Even at 0.08 rad it is 28.5 mm of waddle for 3 mm of
## sweep. That is not a trade, and the honest thing is to take the 16 mm back — see
## `ship_cat.WALK_SPEED`, which is re-derived against the shorter stride so the CADENCE the
## owner asked for is what is preserved.
##
## Kept as VARS at zero rather than deleted: `_prep_ik` still measures the levers and still
## budgets whatever amplitude it is handed, so a re-rig that moves the hind sockets off the
## centreline can turn this back on and be paid for it. tests/GaitScratch block 7 is the A/B.
static var PELVIS_YAW: float = 0.0    ## rad, +/- — was 0.22; 25.2 deg of rump swing for 16 mm
static var CHEST_YAW: float = 0.0     ## rad, +/- — was 0.16; bought no stride at all
## ...AND THE ROLL THE ANATOMY ACTUALLY DESCRIBES STAYS, which is where a walking cat's
## sinuousness really lives: the pelvis lists toward the supporting side and the thorax
## counter-rolls, so the trunk reads as a spine working rather than a rump swinging. These
## were inline literals; they are named so the lateral budget can price them too. At these
## amplitudes the whole trunk moves 1.6-3.7 mm side to side, which is the difference between
## "sinuous" and "wobbling".
static var PELVIS_ROLL: float = 0.050   ## rad, +/- — pelvic list, phase-locked to the footfall
static var CHEST_ROLL: float = 0.038    ## rad, +/- — the thorax counter-rolling against it

## THE TAIL, AND IT IS NOT WHERE ANY NAMING CONVENTION WOULD PUT IT.
##
## Three sessions have recorded "the tail has no bones — Tripo's template ends at the pelvis",
## and that is true of the template and FALSE of this fit. tests/CatTailDiag assigns every
## vertex to the bone with the largest weight on it and reports where those vertices sit:
##
##   R_ThighTwist01   29363 verts   centroid (-0.246, 0.251, -0.029)   0.237 m BEHIND the hip
##
## A quarter of the whole mesh, centred well behind the pelvis, elevated, spanning 0.434 m
## along the body axis. That is the tail (with the rump). The auto-rig stretched the RIGHT
## THIGH CHAIN backwards to cover it — which is also the long-standing mystery of why this
## rig's right hind bones are a quarter the length of its left ones (`R_Thigh -> R_Calf` 0.086
## against `L_Thigh -> L_Calf` 0.336): the "thigh" is largely the tail root.
##
## Two consequences, one bad and one good. The bad one is that the tail is a CHILD of R_Thigh,
## so it has been dragged through the gait by the right hind leg for as long as the cat has
## walked — a tail that twitches once per stride in lockstep with one foot. The good one is
## that flaw 5 costs one layer here instead of a re-rig.
##
## Named rather than detected because detecting it means reading 115k vertices at load, and
## cat_rig is handed a Skeleton3D and no mesh. If the cat is ever re-rolled or re-rigged, re-run
## tests/CatTailDiag and change this line; a name that no longer exists disables the layer
## rather than crashing.
const TAIL_BONE := "R_ThighTwist01"
## How far the tail may be driven. Deliberately small: the bone owns the rump as well as the
## tail, so a big rotation bends the hindquarters with it. Verified by render, not by taste.
const TAIL_MAX: float = 0.30

## HOW FAR THE STAND MESH'S HEAD IS TURNED, in radians about the body's up axis, and the
## correction applied to the rest pose at load (see `_init`). +0.597 = 34.2 degrees, the
## angle between the head's own mirror-symmetry plane and the torso's, measured off the
## GLB's vertices rather than off its joint frames — which is the only way to see it,
## because every joint-frame instrument in this repo calibrates the rest pose to zero.
## SET BY EYE, ON A HEAD-ON FILM — because the eye is the customer and the measurement was
## answering a different question. TENTH owner report; read this before touching the number.
##
## The mesh-derived solve (tests/NoseScratch.tscn) says -0.3325 puts the drawn muzzle EXACTLY
## 0.00 deg off the travel line, and it is not lying about what it measures: the mean
## direction of the head-weighted vertices farthest from the neck joint. That axis simply is
## not where the FACE reads. This head is generator-made and asymmetric — the jaw, the ruff
## and the white bib do not sit symmetrically about the muzzle's vertex axis — so the
## geometric long axis and the visual facing differ by about 12 degrees, and every instrument
## I built measured the former while the owner watched the latter. Nine answers of the form
## "the numbers say it is straight" were all true and all useless.
##
## tests/CatFilm's `headsweep` reel settles it the only way that counts: six values, one run,
## camera dead ahead on the travel line, pick the frame whose face is square. Read off that
## strip — -0.33 is visibly turned to the cat's left, -0.65 and -0.75 over-rotate the other
## way, and -0.55 lands with both eyes level, ears even and the muzzle centred.
##
## If the asset is re-rolled, re-run the SWEEP and pick again by eye. Do not re-derive it, do
## not trust a gate whose forward axis comes from this same skeleton, and do not "correct"
## this back toward the computed value — that is the loop this comment exists to break.
## (The old derivation note is kept below for the record.)
##
## SOLVED OFF THE MESH, AFTER NINE OWNER REPORTS AND FOUR WRONG VALUES. The whole history,
## because the failure mode repeated four times and the cure is a method, not a number.
##
## Every previous value was fitted by EYE against a film, and every instrument used to check
## it defined the head's forward FROM THE SKELETON — the very thing being corrected — so each
## new constant silently re-zeroed its own gate (this repo's s34 tautology, four times over).
## The values tried were 0.597 (derived from symmetry planes), 1.30, and 1.72; measured, they
## leave the drawn muzzle 19, 54, 94 and 118 degrees off the line of travel respectively. They
## were not converging. They were walking away, because the sign was wrong from the start.
##
## tests/nose_scratch.gd settles it without any constant of ours in the loop: it takes the
## muzzle direction from the MESH — the mean direction of the head-weighted vertices farthest
## from the neck joint, which is the one definition ears cannot fool (the head's principal
## horizontal axis IS the ear line, 84 degrees off, and that is the trap the first cut fell
## into) — and sweeps this constant, reading the drawn nose each time. Measured:
##
##     HEAD_MESH_YAW   0.000   0.597   1.300   1.720   2.200
##     drawn nose yaw -19.05  -53.25  -93.53 -117.60 -145.10   degrees off +X
##
## Perfectly linear at -57.29 deg/rad — i.e. EXACTLY unit gain, negative sign, which is what
## the algebra always said (R_rest * Q(local_up, t) == Q(BODY_UP, t) * R_rest). The mesh's own
## bias is 19.05 degrees, so the correction is -19.05/57.2958 = -0.3325 rad, and the sign is
## the entire lesson: four sessions of "tune it a bit further" were adding to the error.
##
## If the asset is ever re-rolled, re-run tests/NoseScratch.tscn and read the zero off the
## table. Do not eyeball it, and do not trust any gate whose definition of forward comes from
## the skeleton this constant edits.
static var HEAD_MESH_YAW: float = -0.55

## Footfall phase offsets per limb, in cycles. The gait MODE is not a switch: the active
## offsets are themselves eased between these tables as speed crosses the bands, so a cat
## accelerating from amble to gallop re-times its legs continuously instead of stuttering
## between patterns.
## Footfall offsets per gait. Walk is the cat's LATERAL SEQUENCE (LH, LF, RH, RF a quarter
## apart); the gallop is ROTARY — hinds land nearly together, then the fores, with two
## airborne moments between. These are the orders every quadruped-animation reference
## teaches, and the thing the s37 sine gait ignored.
const WALK_OFF := {"lh": 0.00, "lf": 0.25, "rh": 0.50, "rf": 0.75}
const TROT_OFF := {"lh": 0.00, "rf": 0.02, "rh": 0.50, "lf": 0.52}
const GALLOP_OFF := {"lh": 0.00, "rh": 0.12, "rf": 0.55, "lf": 0.67}

## THE LIMB CYCLE, AS AN ANIMATOR KEYS IT — not as a sine. Keys are
## (cycle_t, reach, flex, paw) with touchdown at t=0: plant reaching, rotate back nearly
## straight through stance (duty ~0.62 walking — a leg is on the ground far longer than it
## swings, and 50/50 is exactly what reads as clockwork), toe-off trailing, then the FOLD —
## the knee/elbow flexes to lift the paw, carries it forward folded, and extends again to
## plant. The fold is the whole difference between an animal and a toy horse.
## `reach` +ve is toward the head, `flex` +ve bends the joint, paw follows through. Signs
## are mapped per limb below — this table is semantic.
## THE PAW COLUMN NOW BENDS BACK AT TOE-OFF (the owner's "paws to bend back slightly"), and
## it is the one part of the walk a viewer reads without being told what to look at. The old
## column drove the carpus FORWARD (+0.18) at the moment the paw leaves the deck, which is a
## paw being lifted flat like a table leg. A real cat's wrist EXTENDS as the foot peels off —
## the paw trails behind the leg, hanging back — then flexes to fold under, carries forward
## folded, and opens flat just before the plant. So the value at the toe-off key goes negative
## (trailing) and the fold peak moves later, which is also what puts the flick in the right
## place relative to the knee (read a DRAG later than the shoulder).
##
## The hind carries less of it than the fore on purpose: the hock is a much stiffer joint than
## the carpus, and a hind foot that flicks like a wrist reads as a limp.
##
## THE PAW COLUMN IS RETIMED AND THERE IS A KEY AT TOE-OFF NOW (s54) — the owner's "the paw
## doesnt draw down like it should when leg lifts up... then when leg reaches final velocity
## and starts to go down, knee straightens and paw sticks back out like normal to catch".
##
## WHY IT COULD NOT BE FIXED BY CHANGING NUMBERS: the carpus is read at `ph - DRAG`, and with
## a duty of 0.52 and `DRAG` 0.045 the swing occupies table t 0.475..0.955. Only THREE of the
## six shipped keys fell inside it (0.62 -> swing s 0.302, 0.72 -> 0.510, 0.86 -> 0.802).
## There was no key at toe-off and none in the carry, so the wrist's "trail" could not fire
## until a quarter of the way into the swing and there was nothing to hold it folded. Measured
## before: peak extension -10.24 deg at s 0.225, peak flexion +14.82 at s 0.53 — the wrist
## tucking SIMULTANEOUSLY with the elbow's plateau instead of following it. One key had to be
## INSERTED; the numbers alone could never reach it.
##
## THE KEY IS AT t = 0.49 AND THE DUTY IS WHY. A table time maps to swing progress as
## `s = (t + DRAG - duty) / (1 - duty)`, so where a key lands depends on the DUTY IN USE — and
## the shipped walk now runs at duty 0.466 (mix 0.17), not 0.52. The first cut of this put the
## key at 0.52, which is s 0.094 at duty 0.52 and s 0.185 at 0.466: measured, the drawn trough
## fell from -12.8 deg to -7.3, i.e. SHALLOWER THAN THE COLUMN IT REPLACED, because the toe-off
## key had drifted a fifth of a swing late. 0.49 lands at s 0.031 / 0.129 across that range and
## works at both ends; a key any earlier goes into late stance at the walk duty.
##
## The inserted key's `reach` is read off the SHIPPED curve at that t (fore -0.1968, hind
## -0.1976) so adding it does not move the scapula or the hip drive: measured residual
## perturbation of the `reach` column over the whole cycle is under 0.01 rad, and `reach` only
## reaches the animal through `reach_lead * BLADE_TRAVEL`, i.e. under half a degree of scapula
## against ROM_BLADE's 29.79. (`flex`, column 2, is not read by anything and is carried for
## readability only.)
##
## What it draws, measured through the shipped cyclic Catmull-Rom at the real frame rate, deg
## of carpus by swing s (0 = toe-off, 1 = touchdown):
##            s ->   .05    .15    .25    .35    .45    .55    .65    .75    .85    .95
##   fore was       -8.2   -9.7  -10.2   -4.2   13.2   14.8   11.9    7.8    5.0    1.8
##   fore now      -12.8  -10.1    1.1   13.7   21.2   20.3   16.2   11.3    7.4    2.5
##   hind was       -5.0   -6.2   -6.7   -3.2    8.2   11.9   10.6    7.5    4.6    2.4
##   hind now       -8.5   -8.1   -1.2    7.7   14.2   15.5   13.7   10.4    7.1    3.7
## i.e. the wrist now breaks back AT the lift, folds under through the first third, CARRIES
## folded, and opens flat into the plant — and it still ends within 2.5 / 3.7 deg of neutral
## at touchdown, which is what "sticks back out to catch" means for a paw that has to land.
##
## NOTHING WAS WIDENED TO PAY FOR IT. Peak |carpus| 21.2 deg fore / 15.6 hind against
## ROM_PAW's 28.65 (74% / 54%), and the worst one-frame step FALLS — 0.2140 -> 0.1957 rad fore
## and 0.1464 -> 0.1215 hind against the 0.3167 limiter — because inserting a key removes a
## steep Catmull-Rom transient between two distant ones. The range came off the elbow (see
## `FOLD_FORE`) and went onto the carpus, which is the joint that had 13.6 deg of unused
## flexion at a walk. The GALLOP tables are untouched: the two are blended by `mix`, so
## deepening the walk alone cannot reach the run, where the fore carpus already draws 26.0 of
## the 28.65.
const CYC_WALK_FORE := [
	[0.00, 0.30, 0.08, -0.10], [0.30, 0.02, 0.03, 0.00], [0.49, -0.1968, -0.0027, -0.32],
	[0.62, -0.30, 0.06, 0.20], [0.72, -0.12, 0.60, 0.44], [0.86, 0.24, 0.42, 0.18],
	[1.00, 0.30, 0.08, -0.10]]
const CYC_WALK_HIND := [
	[0.00, 0.34, 0.06, -0.06], [0.34, 0.02, 0.03, 0.00], [0.49, -0.1976, 0.0117, -0.23],
	[0.62, -0.34, 0.09, 0.10], [0.74, -0.12, 0.72, 0.32], [0.88, 0.28, 0.48, 0.14],
	[1.00, 0.34, 0.06, -0.06]]
## Gallop: shorter stance (duty ~0.38), far bigger reach and fold. The legs GATHER under
## the body and EXTEND — but half of a real gallop lives in the spine engine below.
const CYC_GAL_FORE := [
	[0.00, 0.55, 0.10, -0.15], [0.24, -0.05, 0.06, 0.10], [0.38, -0.55, 0.12, 0.30],
	[0.55, -0.20, 0.85, 0.45], [0.80, 0.45, 0.55, 0.05], [1.00, 0.55, 0.10, -0.15]]
const CYC_GAL_HIND := [
	[0.00, 0.50, 0.08, 0.00], [0.22, -0.05, 0.05, 0.05], [0.38, -0.60, 0.12, 0.15],
	[0.56, -0.25, 0.95, 0.35], [0.82, 0.42, 0.55, 0.05], [1.00, 0.50, 0.08, 0.00]]
## Speed bands (m/s): below WALK_V pure walk offsets; between, eased; above TROT_V pure
## bound. Chosen against WALK_SPEED 1.55 / TROT 2.6 / RUN 4.4 in ship_cat.gd.
##
## RE-SITED ON REAL FELINE TRANSITION SPEEDS (s54), which is the fix KNOWN_ISSUES asked for and
## the honest half of the owner's "the cat speed needs to increase by ~25%".
##
## They were two sessions stale: 1.8 / 3.4 were chosen against WALK_SPEED 1.55 and TROT 2.6,
## and those constants have been 1.084 and 1.9 since s52. At TROT_SPEED the mix computed to
## 0.06 — the "trot" was a walk cycle at 1.9 m/s, 4.16 strides a second, and it measured as the
## worst-behaved band in the animal (phase-gated slide rf 33.7, lh 47.2 mm/frame).
##
## `mix` is not a style dial. It sets the footfall order (WALK_OFF at 0, TROT_OFF at 0.5,
## GALLOP_OFF at 1), the duty (WALK_DUTY -> GALLOP_DUTY) and therefore the stride, the sweep
## envelope, the bob and the swing lift. So a band is a claim about WHICH GAIT the animal uses
## at a given ground speed, and that claim is checkable against the animal: a domestic cat
## walks up to about 1.0-1.3 m/s, trots from there to about 2.4-3.0, and gallops above it
## (Blaszczyk & Loeb's treadmill cats change gait in those two windows). So:
##     WALK_V 1.30  — the walk -> trot transition; below it the lateral-sequence walk
##     TROT_V 2.90  — the trot -> gallop transition; above it the full bound
## which puts ship_cat's three speeds at mix 0.038 / 0.675 / 1.000 instead of 0.000 / 0.063 /
## 1.000. THE MIDDLE ONE IS THE POINT: TROT_SPEED now actually draws a trot, at duty 0.304 and
## a 0.640 m stride, instead of a walk cycle flogged at 1.9 m/s.
##
## AND 1.30 RATHER THAN 1.05, WHICH IS A GATE DECISION AND IS WRITTEN DOWN AS ONE. 1.05 is the
## more central figure for an animal this size and it was tried first: it puts the shipped walk
## at mix 0.168, buying a longer stride (0.463 m vs 0.436) and a slower step (2.94/s vs 3.12).
## It also takes CatReviewProbe's `[walk] slide_frame` from 9.16 to 12.45 mm/frame against a
## 10 mm gate, and `[lookwalk]` from 8.07 to 11.34. Decomposed by running the probe with the
## mix pinned:
##     1.084 m/s, mix 0  ->  6.99 mm/frame        (the pre-s54 build)
##     1.360 m/s, mix 0  ->  8.76                 (pure speed: it scales 1:1 with ground speed)
##     1.360 m/s, mix 0.168 -> 12.45              (the band)
## So the speed rise costs 1.8 mm/frame and is unavoidable if the animal is to go faster; the
## deeper band costs another 3.7 and is a CHOICE. This repo does not widen a gate to make a
## change fit, so the band stops where the gate does. If a future session ports GaitScratch's
## phase gate into cat_review_probe.gd (KNOWN_ISSUES names this as the fix) and the 10 mm bar
## then means what it says, 1.05 is the better number and this line is the only edit.
##
## THIS IS ALSO WHERE THE OWNER'S EXTRA GROUND SPEED COMES FROM, and the arithmetic says it
## could not have come from anywhere else. `stride = sweep / duty`; the walk's sweep is capped
## by the binding hind's `2*c0*sin(ROM_PROX)` (0.2233 m — and ROM_PROX must not be widened, see
## KNOWN_ISSUES) and WALK_DUTY 0.52 is already at the definitional floor of a walk (four limbs
## at duty d average 4d feet down, so 0.50 IS the walk/trot boundary). A pure walk on this rig
## therefore tops out at a 0.429 m stride, so +25% ground speed on a pure walk IS +25% cadence.
## At mix 0.038 the stride grows 1.7% and the cadence rises 23% rather than 25%: honest, small,
## and the reason the number is stated in ship_cat rather than hidden.
const WALK_V: float = 1.30
const TROT_V: float = 2.90

## THE STANCE FRACTION AT EACH END OF THE GAIT, and the second half of `stride = sweep/duty`.
##
## WALK 0.52. A gait is a walk while at least two feet are down on average, and with four
## limbs that average is exactly `4 * duty` — so 0.50 IS the walk/trot boundary and there is
## no room below it whatever the owner asks for. s45c took it 0.62 -> 0.55 for "wider, slower,
## smoother"; 0.52 is the last of it, worth 6% of stride, and going further would not make the
## step longer so much as make it a trot with the walk's footfall order, which is a limp.
##
## GALLOP 0.20. A galloping cat is airborne about 80% of the time (the appendix's measured
## figure is ~0.18), so a short contact and a long stride is what a gallop IS rather than a
## cheat — see the long note in `tick` about the 7.5-strides-a-second bug this fixed.
const WALK_DUTY: float = 0.52
const GALLOP_DUTY: float = 0.20

var _sk: Skeleton3D = null
var _idx: Dictionary = {}          ## bone name -> index in THIS skeleton
var _rest: Dictionary = {}         ## index -> rest Quaternion (the stand mesh's pose)
var _rest_t: Dictionary = {}       ## index -> rest origin, for the Hip height blend
var _limb: Dictionary = {}
var _spine := -1
var _spine2 := -1
var _neck := -1
var _head := -1
var _hip := -1

## The pose library: name -> {q: {index: Quaternion}, hip_t: Vector3}. `stand` is the
## skeleton's own rest and always present.
var _poses: Dictionary = {}
## The blend state — what is actually on the bones right now.
var _cur_q: Dictionary = {}        ## index -> Quaternion
var _cur_hip: Vector3 = Vector3.ZERO
var _target: String = "stand"
var _blend_rate: float = 7.0
## Gait state.
var _phase: float = 0.0
var _gait_w: float = 0.0           ## eased 0..1 — how much gait rides on the pose
var _speed_s: float = 0.0          ## eased speed, for amplitude and mode mixing
## Look state, applied last so it wins over the gait's neck motion.
##
## TARGETS AND APPLIED VALUES ARE SEPARATE, because `look()` is called with whatever the
## caller is watching THIS frame and callers fight: an idle glance re-picks a new mark every
## few seconds, and the chatter re-aims at a moving gull while a glance is live. Applying the
## raw target snapped the drawn head up to 0.8 rad in a single 60 Hz frame — measured, and
## the single largest discontinuity anywhere in the walk. The `_s` values ease toward the
## targets fast enough to read as a saccade (~0.2 s) and never as a teleport.
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var _look_w: float = 0.0
var _look_yaw_s: float = 0.0
var _look_pitch_s: float = 0.0
var _look_w_s: float = 0.0
## The head stabiliser's lagged view of what the trunk is doing (see section 5e).
var _stab_pitch: float = 0.0
var _stab_roll: float = 0.0
## The wash layer's eased weight — see the note at the groom block. A boolean gate on the
## pose name dropped 31 degrees of neck yaw in one frame every time a bout ended.
var _groom_w: float = 0.0
## Last frame's WRITTEN local rotation per limb bone, for the limb rate ceiling above.
var _limb_prev: Dictionary = {}
## Last frame's DRAWN head orientation in skeleton space, for the total-rate ceiling.
var _head_prev_g: Quaternion = Quaternion.IDENTITY
## The reactions that used to be whole-body node rotations (see section 5f). Decaying
## weights for the momentary ones; eased targets for the two that are states rather than
## events.
var _pet_w: float = 0.0
var _delight_w: float = 0.0
var _wiggle_w: float = 0.0
var _shift_t2: float = 0.0
var _shift_s: float = 0.0
var _slope_t: float = 0.0
var _slope_s: float = 0.0
## The one animation clock: accumulated SIM time. Every secondary sine (breath, tail, groom
## strokes, shake, chatter) runs on this, never on Time.get_ticks_msec() — under AiBudget
## frame-summing the wall clock jumps while the sim stands still, so a wall-clocked layer
## twitches exactly when the animal is being ticked least.
var _anim_t: float = 0.0
var _chat_w: float = 0.0
var _groom_style: int = 0
## WHICH WAY IS THE SCRATCHING SIDE, as a sign along BODY_SIDE. Measured off the rest skeleton
## in `_measure_gains`, never typed: the ear scratch's head tilt rolls TOWARD this sign, and a
## left/right sign taken from a bone's name is how this rig's right foreleg spent every session
## of the gait's life being driven about an axis that moved it 0.005 m/rad.
var _scratch_side: float = -1.0
var _shake_w: float = 0.0
## bone index -> its limb's sagittal hinge, in that bone's OWN local frame. Derived from the
## skeleton's geometry in `_measure_gains`; replaces the hand-written local-X + sign map.
var _hinge: Dictionary = {}
## Each bone's global-pose BASIS at rest, cached once. `_mul_body` uses it to turn an intent
## expressed in body axes ("yaw", "roll") into the rotation that bone actually needs — which is
## how the torso layers stop being a guess about which local axis does what.
var _rest_gb: Dictionary = {}
## Turn-in-place: how fast the body is yawing, eased. Drives the step-in-place gait so the cat
## picks its feet up to turn instead of pivoting like a turntable.
var _yaw_rate: float = 0.0
var _turn_phase: float = 0.0
## THE TAIL. `_tail_up` is carriage (+1 straight up in greeting, -1 clamped down), `_tail_sway`
## is how much it moves and `_tail_rate` how fast — a slow arc while walking, a hard fast flick
## while hunting or annoyed. All three are eased, because a tail that snaps between carriages
## is the one part of a cat that must never look digital.
var _tail_up: float = 0.0
var _tail_sway: float = 0.35
var _tail_rate: float = 1.0
var _tail_up_t: float = 0.0
var _tail_sway_t: float = 0.35
var _tail_rate_t: float = 1.0
var _tail: int = -1
## THE TAIL IS A SPRING, NOT A DIAL. The drive above says where the tail WANTS to be; these
## carry where it IS, as an underdamped second-order spring per axis (yaw across the body,
## pitch for carriage). What that buys, for four state variables: the tail LAGS every change
## like a thing with mass, OVERSHOOTS ~15% on stops and settles back — the follow-through
## that separates a limb from a lever — and counter-swings against the body's turns. One
## bone is still one bone (see docs/CAT_RIG_CEILING.md for what a real chain would add);
## this is the ceiling of what it can say, reached honestly.
var _tail_yaw: float = 0.0
var _tail_yaw_v: float = 0.0
## Which way the last flick went, so a lashing tail alternates instead of twitching one way.
var _flick_side: float = 1.0
var _tail_pitch: float = 0.0
var _tail_pitch_v: float = 0.0
## The tail's absolute world target for this frame, and the world orientation it actually drew
## last frame — see TAIL_MAX_RATE and the re-solve at the end of `tick`.
var _tail_gwant: Quaternion = Quaternion.IDENTITY
var _tail_prev_g: Quaternion = Quaternion.IDENTITY
## Every bone's FINAL local rotation this frame, after the ROM clamp and the rate ceiling — the
## only buffer from which a bone posed absolutely can be solved honestly.
var _fin: Dictionary = {}
## TRANSITION TIMELINE (P6): a short queue of [pose, hold_sec, rate] sub-poses played before
## the blend settles on `_target`. This is what turns "melt between two statics" into
## anticipation -> extreme -> settle: a cat shifts its weight BACK before it sits, sinks a
## whisker DEEPER than the sit it ends in, and rises rear-first. The grammar lives in
## set_pose so every caller — behaviour, film, probe — gets it for free.
var _seq: Array = []
var _seq_t: float = 0.0

func _init(skel: Skeleton3D, pose_json_path: String = "") -> void:
	_sk = skel
	if _sk == null:
		return
	for i in range(_sk.get_bone_count()):
		var nm: String = _sk.get_bone_name(i)
		_idx[nm] = i
		var rest: Transform3D = _sk.get_bone_rest(i)
		_rest[i] = rest.basis.get_rotation_quaternion()
		_rest_t[i] = rest.origin
		_cur_q[i] = _rest[i]
	# `blade` is the SCAPULA and `toe` the paw's last joint. Both were sitting unused on this
	# skeleton while the gait swung the limb from the humerus alone. A cat's shoulder blade
	# travels further than almost any other mammal's — it rides up above the spine at the top
	# of the reach and is a large part of why a cat reads as a cat and not as a small dog —
	# and a paw that never rolls at the plant is the other half of "toy horse". Both are
	# optional: `_b` returns -1 on a rig that lacks them and `_mul` ignores -1.
	_limb = {
		"lf": {"prox": _b("L_Upperarm"), "dist": _b("L_Forearm"), "paw": _b("L_Hand"),
			"blade": _b("L_Clavicle"), "toe": -1},
		"rf": {"prox": _b("R_Upperarm"), "dist": _b("R_Forearm"), "paw": _b("R_Hand"),
			"blade": _b("R_Clavicle"), "toe": -1},
		"lh": {"prox": _b("L_Thigh"), "dist": _b("L_Calf"), "paw": _b("L_Foot"),
			"blade": -1, "toe": _b("L_ToeBase")},
		"rh": {"prox": _b("R_Thigh"), "dist": _b("R_Calf"), "paw": _b("R_Foot"),
			"blade": -1, "toe": _b("R_ToeBase")},
	}
	_spine = _b("Spine01")
	_spine2 = _b("Spine02")
	_neck = _b("NeckTwist01")
	_head = _b("Head")
	_hip = _b("Hip")
	_tail = _b(TAIL_BONE)
	# THE MESH'S HEAD IS GENERATED TURNED, AND EVERY INSTRUMENT WE HAD DEFINED THAT AWAY.
	#
	# The owner has said in capitals that the cat's head defaults to pointing right while
	# it walks. Three sessions "measured" a 0.91 degree residual and called it nearly
	# solved. Both instruments were tautologies: tests/cat_film.gd::_calibrate_face takes
	# the Head bone's local vector that EQUALS the node's forward at rest and calls that
	# the nose (`bearings are now ZERO at rest by construction`), and cat_yaw_diag does the
	# same thing against model +X — so a head baked turned in the asset reads as perfectly
	# straight, for ever, by construction.
	#
	# Measured off the GLB geometry instead of the joint frame: the head's own
	# mirror-symmetry plane sits 34.2 degrees off the torso's (residuals 2.2 mm and 4.6 mm,
	# so both are genuine planes), and the Head-joint-to-nose ray reads -38.9 degrees. The
	# walk pose is `_pose_from({}, 0.0)` — the bare rest — so a walking cat's nose sits
	# ~35 degrees off its line of travel as a pure constant. That is the complaint, exactly,
	# and no amount of gait work could ever have touched it.
	#
	# Corrected here, on the REST pose, so the whole library and every blend inherit a cat
	# whose head faces the way it is going. Poses that WANT a turned head still say so.
	if _head >= 0 and absf(HEAD_MESH_YAW) > 1e-4:
		_sk.reset_bone_poses()
		_sk.force_update_all_bone_transforms()
		var head_gb: Basis = _sk.get_bone_global_pose(_head).basis.orthonormalized()
		var ax: Vector3 = (head_gb.inverse() * BODY_UP).normalized()
		_rest[_head] = (_rest[_head] * Quaternion(ax, HEAD_MESH_YAW)).normalized()
		_cur_q[_head] = _rest[_head]
		_sk.set_bone_pose_rotation(_head, _rest[_head])
	_cur_hip = _rest_t.get(_hip, Vector3.ZERO)
	# `stand` is the base skeleton's own rest — present even with no library on disk.
	# `loco: true` marks a pose the gait may ride (see tick: the gate is the FLAG, never a
	# name list — a name list is how stalk and carry shipped moonwalking).
	var stand := {"q": {}, "hip_t": _rest_t.get(_hip, Vector3.ZERO), "loco": true}
	for i in _rest:
		stand["q"][i] = _rest[i]
	_poses["stand"] = stand
	# THE LIBRARY IS AUTHORED, NOT TRANSFERRED. The donor-transfer experiment is kept in
	# _load_library for the record, but it is not called: rendering every transferred pose
	# (tests/out/cat_blend, s37) showed the auto-rig joint FRAMES disagree between fits —
	# sit arrived ~70% right, sleep and run arrived candy-wrapped inside their own torsos,
	# groom reared the cat vertical. Rotations are only meaningful on the skeleton they
	# were measured on, so every pose here is FK offsets from THIS skeleton's rest — the
	# same method the gait and the s35 wash already proved on these bones.
	# THE REST BASES ARE CACHED FIRST, because `_build_poses` now needs them: a pose may state
	# an offset in BODY axes (see `_pose_from`), and converting one takes the bone's rest basis.
	# GAINS BEFORE POSES: _measure_gains derives each limb's hinge from the rest skeleton,
	# and _build_poses may author on those hinges (axis code 6). The reverse order would
	# hand code-6 poses the local-X fallback — the exact wrong axis the code exists to end.
	# ...AND IK BEFORE POSES, WHICH IS THE OWNER'S "SITTING CAT ANGLED BACKWARDS".
	#
	# `_prep_ik` is where `_rom` is built — the joint limits, derived here because this is
	# where each knee's fold DIRECTION is already a measured fact. `_build_poses` ran BEFORE
	# it for every session the bake has existed, so `_rom` was an empty dictionary throughout
	# the bake and `_clamp_joint` was a silent no-op: **not one pose in the library has ever
	# been solved inside the animal's own joint limits.** `tick`'s write loop then clamps
	# every frame, so what the library believed it had planted and what the skeleton drew were
	# two different animals. Measured on the sit before this line moved: the runtime clamp
	# took 12.31 deg off `L_Forearm`, 8.14 off `R_Calf` and 3.09 off `L_Calf` against the
	# baked pose, standing perfectly still, which put the forepaws ~9 mm further off the deck
	# and the hind ~13 mm further through it than the pose library said.
	#
	# `_prep_ik` reads only the rest skeleton and `_limb`, never `_poses`, so the swap is
	# free — and with it the bake's CCD solves in range and the trim below can see the true
	# residual instead of one the clamp will change later.
	_cache_rest_bases()
	_measure_gains()
	_prep_ik()
	var bake_t0: int = Time.get_ticks_msec()
	_build_poses()
	# THE BAKE REPORTS WHAT IT ACHIEVED. The library is solved, not authored, so "the paws are
	# planted" is a claim with a number behind it — the worst VERTICAL miss across every
	# planted paw of every pose, in millimetres, and what the whole thing cost at load.
	var worst_mm: float = 0.0
	var worst_where: String = ""
	for nm in _poses:
		for k in ((_poses[nm] as Dictionary).get("paw_dy_mm", {}) as Dictionary):
			var v: float = absf(float(_poses[nm]["paw_dy_mm"][k]))
			if v > worst_mm:
				worst_mm = v
				worst_where = "%s/%s" % [nm, k]
	print("[cat_rig] %d poses baked in %d ms — worst planted-paw miss %.1f mm (%s)"
		% [_poses.size(), Time.get_ticks_msec() - bake_t0, worst_mm, worst_where])

## RE-APPLY THE HEAD CORRECTION TO A LIVE RIG. The bake runs once at load, so a harness that
## changes HEAD_MESH_YAW afterwards would film the old value on every beat. Rebuilds the head's
## rest entry from the SKELETON's untouched bone rest, so repeated calls cannot compound.
func rebake_head() -> void:
	if _sk == null or _head < 0:
		return
	var base: Quaternion = _sk.get_bone_rest(_head).basis.get_rotation_quaternion()
	var gb: Basis = _rest_gb.get(_head, Basis.IDENTITY)
	var ax: Vector3 = (gb.inverse() * BODY_UP).normalized()
	_rest[_head] = (base * Quaternion(ax, HEAD_MESH_YAW)).normalized()
	for nm in _poses:
		var e: Dictionary = _poses[nm]
		(e["q"] as Dictionary)[_head] = _rest[_head]
	_cur_q[_head] = _rest[_head]

func _b(nm: String) -> int:
	return int(_idx.get(nm, -1))

## ---------------------------------------------------------------- body-space rotation
##
## WHICH LOCAL AXIS IS "YAW" IS NOT THE SAME QUESTION ON ANY TWO BONES OF THIS RIG, and every
## time it has been answered by reading the code it has been answered wrong. tests/CatYawDiag
## measures it: +0.2 rad about Spine01's local X pitches the head +11.4 deg; about local Y it
## rolls +10.0 AND yaws +5.5; about local Z it YAWS +10.0 and rolls -5.6. So the breath layer,
## which was written as a chest motion about local Z, was in fact turning the cat's head
## sideways by +/-2.6 deg on every pose it has ever worn — the owner's "it looks to the side
## when walking", measured at +3.4 deg mean off the travel line in tests/CatFilm.
##
## The fix is not a better guess. It is to stop expressing torso motion in bone axes at all:
## say "roll the chest 3 degrees" in the BODY's frame and let this convert it. A layer that
## asks for roll then cannot leak yaw, on this rig or on the next species' rig.
##
## The basis used is the bone's REST global pose, cached once, NOT its live one. That is
## deliberate: feeding a live transform back into the rotation that produces it is the exact
## shape of the two accumulator bugs this file's header is about. A constant map cannot
## accumulate, and the torso never travels far enough from rest for the difference to read.
func _cache_rest_bases() -> void:
	if _sk == null:
		return
	var rest_q := {}
	for i in _rest:
		rest_q[i] = _rest[i]
	_set_chain(rest_q)
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, _rest_t[_hip])
	for i in _rest:
		_rest_gb[i] = _sk.get_bone_global_pose(i).basis.orthonormalized()

## Rotate `bone` by `ang` about a BODY axis (BODY_UP = yaw, BODY_FWD = roll, BODY_SIDE = pitch).
func _mul_body(bone: int, body_axis: Vector3, ang: float) -> void:
	if bone < 0 or absf(ang) < 1e-6:
		return
	var gb: Basis = _rest_gb.get(bone, Basis.IDENTITY)
	var local_axis: Vector3 = (gb.inverse() * body_axis).normalized()
	_mul(bone, Quaternion(local_axis, ang))

## The GLOBAL basis `bone` will draw with THIS frame, composed from the frame's own _out
## (falling back to the blend state) down the parent chain. The Skeleton3D itself still
## holds LAST frame's pose at any point inside tick, so get_bone_global_pose here would be
## one frame stale — and a frame of staleness in an axis map is a feedback loop.
func _live_basis(bone: int) -> Basis:
	var chain: Array[int] = []
	var i: int = bone
	while i >= 0:
		chain.push_front(i)
		i = _sk.get_bone_parent(i)
	var b := Basis.IDENTITY
	for j in chain:
		b = b * Basis(_out.get(j, _cur_q.get(j, Quaternion.IDENTITY)) as Quaternion)
	return b

## A BONE'S POSE POSITION LIVES IN ITS PARENT'S FRAME, AND THIS RIG'S ROOT POINTS ITS LOCAL
## Y ALONG THE BODY AXIS. Measured (tests/hip_bob_scratch): writing rest + (0, +0.2, 0) to
## the Hip's pose position moved its GLOBAL origin by (-0.2, 0, 0) — fore-aft, not up. So
## every skeleton-space hip translation ever written raw — the s37 sit and sleep crouches,
## the whole-body bob — SLID THE PELVIS ALONG THE BODY instead of dropping it, silently,
## since the one-skeleton cat was built. (The sits still read plausibly because the IK bake
## re-planted the paws from wherever the pelvis actually went.) Every hip translation now
## converts its skeleton-space intent through the parent's rest basis.
func _hip_pose_pos(skel_delta: Vector3) -> Vector3:
	var par: int = _sk.get_bone_parent(_hip)
	var pb: Basis = _rest_gb.get(par, Basis.IDENTITY) if par >= 0 else Basis.IDENTITY
	return (_rest_t[_hip] as Vector3) + pb.inverse() * skel_delta

## The frame-live GLOBAL transform of `bone` — basis AND origin — composed like _live_basis
## but carrying the hip's translated pose position. The leg solve needs it: reading the
## Skeleton3D mid-tick hands back LAST frame's parent, and a one-frame-stale socket under a
## bobbing pelvis is a per-frame paw error of exactly the pelvis's per-frame motion.
func _live_xform(bone: int) -> Transform3D:
	var chain: Array[int] = []
	var i: int = bone
	while i >= 0:
		chain.push_front(i)
		i = _sk.get_bone_parent(i)
	var x := Transform3D.IDENTITY
	for j in chain:
		var pos: Vector3 = _rest_t.get(j, Vector3.ZERO)
		if j == _hip:
			pos = _hip_pose_pos(_out_hip - (_rest_t[_hip] as Vector3))
		x = x * Transform3D(Basis(_out.get(j, _cur_q.get(j, Quaternion.IDENTITY)) as Quaternion), pos)
	return x

## _mul_body against the frame's LIVE pose instead of the cached rest pose. The rest map is
## right for small layers riding a near-rest torso (breath, sway) and WRONG for a large
## rotation on a torso far from rest: the look on a SITTING cat — hip pitched ~33 deg — put
## 22 deg of roll into a commanded pure yaw through the rest map, because the axis it
## computed belonged to a standing animal. Reads only bones already composed this frame, so
## it cannot feed back into itself (the accumulator shape _cache_rest_bases warns about
## needs persistent state; _out is rebuilt from scratch every tick).
func _mul_body_live(bone: int, body_axis: Vector3, ang: float) -> void:
	if bone < 0 or absf(ang) < 1e-6:
		return
	var local_axis: Vector3 = (_live_basis(bone).inverse() * body_axis).normalized()
	_mul(bone, Quaternion(local_axis, ang))

## ---------------------------------------------------------------- measured limb gains
##
## THE TWO SIDES OF THIS RIG ARE NOT THE SAME LENGTH, and the runtime gait did not know.
##
## tests/BoneDump on cat_stand_idle.glb: L_Thigh->L_Calf is 0.336 m and R_Thigh->R_Calf is
## 0.086 m — the right femur is a QUARTER of the left. (L_Upperarm->L_Forearm 0.178 vs R 0.228,
## and the hands and feet differ too.) It is a documented Tripo defect and the pose bake already
## absorbs it, because IK solves each leg with that leg's own bones. The per-frame gait did not:
## it fed the same `reach` and `flex` in RADIANS to both sides, so tests/CatFilm measured the
## left hind paw lifting 206 mm per stride against the right hind's 28 mm — a 7.5x difference,
## which is a limp, and a limp is most of what "choppy" looks like from the front.
##
## So the tables stop being angles and start being INTENTIONS. Measure, once, how far each paw
## actually travels per radian at its own joints, and scale each limb so all four describe
## matched arcs. Measured on the skeleton itself, in the repo's own idiom — the same method the
## axis atlas and the IK bake use, and the reason none of this is a guess.
## THE SWING AXIS IS NOT local X, AND ON ONE LIMB IT NEVER WAS.
##
## The first cut of this function measured how far each paw travels fore-and-aft per radian
## about `SWING` (local X, the axis the whole gait was written against) and got:
##     lf 0.198   rf 0.005   lh 0.200   rh 0.189   metres per radian.
## Three limbs agree to within 5%. The RIGHT FORELIMB is at one fortieth of the others —
## rotating R_Upperarm about its local X does not swing that leg fore-and-aft at all, because
## the auto-rig fitted that bone's frame turned about 90 degrees from its opposite number. The
## sign map above calls the upperarms "MIRRORED" and flips a sign for it; a mirror would have
## given -0.198, not +0.005. So the right foreleg has been driven about the wrong axis for
## every session this gait has existed, and no amount of tuning the tables could fix it.
##
## The answer is not a fourth guess. A limb is a PLANAR linkage: it swings in the sagittal
## plane containing the shoulder, the paw and the body's fore-aft axis. Rotating a joint about
## the normal `n` of that plane displaces the paw by `theta * (n x r)` — so choose
## `n = normalise(r x BODY_FWD)` and positive theta moves the paw FORWARD, on every limb, with
## a gain of exactly |r|. That is geometry, not a convention: it derives the axis AND the sign
## AND the gain from the rig in front of it, so it is equally correct on the next species'
## skeleton and on a re-export of this one.
func _measure_gains() -> void:
	if not valid():
		return
	var rest_q := {}
	for i in _rest:
		rest_q[i] = _rest[i]
	_set_chain(rest_q)
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, _rest_t[_hip])
	# One sagittal plane per limb, shared by every joint in that chain so the leg stays planar.
	for k in _limb:
		var L: Dictionary = _limb[k]
		var prox_o: Vector3 = _sk.get_bone_global_pose(L["prox"]).origin
		var r: Vector3 = _paw_pos(L["paw"]) - prox_o
		var n: Vector3 = r.cross(BODY_FWD)
		n = BODY_SIDE if n.length() < 1e-5 else n.normalized()
		for key in ["prox", "dist", "paw", "blade", "toe"]:
			var b: int = int(L[key])
			if b < 0:
				continue
			_hinge[b] = (_sk.get_bone_global_pose(b).basis.orthonormalized().inverse() * n).normalized()
	var base := {}
	for k in _limb:
		base[k] = _paw_pos(_limb[k]["paw"])
	# WHICH SIDE THE EAR SCRATCH WORKS ON. The scratching limb can only be the left hind on
	# this fit (`_build_poses` gives the measurement), but which way "left" points along
	# BODY_SIDE is a fact about the fit rather than about the bone's name — here L_Foot rests
	# at z -0.098 and R_Foot at +0.069. Read off the rest anchor so a mirrored re-export tilts
	# the head toward the paw instead of away from it. Not `signf`, which answers 0 on 0.
	_scratch_side = -1.0 if (base["lh"] as Vector3).z < 0.0 else 1.0
	const D: float = 0.25
	var gr := {}
	var gf := {}
	for k in _limb:
		var L: Dictionary = _limb[k]
		_set_chain(rest_q)
		_sk.set_bone_pose_rotation(L["prox"], _rest[L["prox"]] * Quaternion(_hinge_of(L["prox"]), D))
		gr[k] = absf((_paw_pos(L["paw"]) - base[k]).dot(BODY_FWD)) / D
		# The FOLD's gain is simply the KNEE-TO-PAW LEVER — first order and exact. Perturbing
		# the joint and measuring the paw's HEIGHT change (the first attempt) reads a
		# second-order effect on a leg that hangs straight down, so it scaled with the size of
		# the test rotation and came back as noise: 0.010 on one hind against 0.086 on the
		# other, from bones whose real levers are 0.106 and 0.111.
		gf[k] = maxf(base[k].distance_to(_sk.get_bone_global_pose(L["dist"]).origin), 1e-3)
	_set_chain(rest_q)
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, _rest_t[_hip])
	# A RIG REPORT, printed once. These numbers no longer scale anything — the legs are solved
	# to a path in metres now, which makes per-limb gain compensation unnecessary by
	# construction — but they are the cheapest possible check that a re-exported or re-rigged
	# cat still has four comparable legs. A `reach` column with one entry near zero means that
	# limb's hinge derivation has gone wrong, and it is worth knowing at load rather than
	# discovering it in a film three sessions later, which is what happened here.
	print("[cat_rig] limb levers m/rad: reach %s  knee %s"
		% [str(_round_d(gr)), str(_round_d(gf))])

## A bone's sagittal hinge in its own local frame, falling back to the historic local-X for
## anything not part of a measured limb chain.
func _hinge_of(bone: int) -> Vector3:
	return _hinge.get(bone, SWING) as Vector3

## ---------------------------------------------------------------- the foot path (runtime IK)
##
## WHY THE LEGS STOPPED BEING DRIVEN AS ANGLES.
##
## With the hinges derived and the amplitudes normalised, the FK gait finally swung all four
## limbs the same distance fore-and-aft — and tests/CatFilm still measured two things it could
## never fix. First, every stance paw SLID at 1.4-1.6 m/s while the body moved at 1.55: the
## paws were not planted at all, they were skating, which is the weightless "moonwalk" read.
## Second, the hind paws' LIFT stayed 6.4x apart (226 mm against 35 mm) even with matched
## fore-aft travel, because the two hind chains sit at different angular positions on their own
## swing circles — the same joint angle traces a mostly-horizontal arc on one side and a
## mostly-vertical one on the other. No amount of per-limb gain can fix that: the fault is that
## a JOINT ANGLE is the wrong thing to author. Where the paw goes is the thing that matters.
##
## So the cycle tables now describe A PATH IN BODY SPACE, and the joints are solved to follow it:
##   STANCE — the paw is on the deck and travels BACKWARD at exactly the speed the body travels
##            FORWARD, so it is stationary in the world. That is foot-lock, and it falls out of
##            the definition rather than being bolted on.
##   SWING  — it lifts, carries forward over an arc, and reaches out to the next plant.
## Both sides are handed the same path relative to their own rest stance, so a rig whose left
## and right bones disagree by a factor of four draws two identical legs.
##
## The solve is ANALYTIC, not CCD. Every limb here is a two-bone chain on a single sagittal
## hinge, so the law of cosines gives both angles in closed form — no iteration, no skeleton
## round-trips, ~20 flops a leg. `_ik_leg`'s hinge-constrained CCD stays where it belongs, at
## pose-BAKE time, where the chain has to reach an arbitrary target from an arbitrary torso.
var _ik: Dictionary = {}
## How far a paw may sweep during stance, metres — the shortest leg's envelope, shared by all
## four. It sets the stride, which is what makes foot-lock exact instead of approximate.
## This one is the GALLOP's, unchanged since s45c (0.94 * c0 on the binding limb).
var _sweep_cap: float = 0.24
## ...and the WALK's, which is larger, and the whole of s52's stride. Two numbers rather than
## one because the two ends of the gait are limited by different things and only one of them
## has an instrument that can see its stance:
##   * the walk envelope is `2*c0*sin(ROM_PROX)` plus the measured girdle travel — i.e. the
##     joint limit this file ALREADY enforces, rather than the hand-set 0.94*c0 (= 2*sin(28
##     deg)) that has stood since the gait ran at 4.7 strides a second;
##   * the gallop keeps 0.94, because CatReviewProbe's run scenario finds ZERO to ONE stance
##     pairs in 7.5 m — its slide gate is vacuous today (it reported a perfect 0.0000 from an
##     empty window), so a wider gallop stride cannot be validated there. Measured, not
##     guessed: pushing the gallop to the walk envelope took the run's slide from a vacuous
##     0.00 to 23.7 mm/frame the moment the window became non-empty. Widen it when the run
##     has a gate that can see it, and not before.
## `tick` lerps between them by the same `mix` that eases the footfall offsets, so the stride
## stays DERIVED from whatever sweep is actually in use and foot-lock survives the blend.
var _sweep_walk: float = 0.24
## Which limb binds the walk envelope, and how much of that envelope its girdle paid for —
## printed at bake so the split is on the record rather than in a comment.
var _bind_limb: String = ""
var _sweep_girdle: float = 0.0
## Which way each girdle must rotate to carry a socket TOWARD its own planting paw. Derived
## in `_prep_ik` from the measured lever, never typed — see the note there.
var _pelv_sign: float = 1.0
var _chest_sign: float = 1.0
## How much VERTICAL give an out-of-reach leg is allowed before it must shorten its step
## (see _solve_leg). Written by tick per frame: the whole-body bob asks the legs to extend
## with it, so the give grows with gait intensity — held at the old tight cap the bob's
## peak popped the straight-bound left hind's knee against the reach clamp every cycle.
var _reach_give: float = 0.022
## Last tick's solved [prox, dist] per limb, for the slew limiter in tick.
var _sol_prev: Dictionary = {}

## ---------------------------------------------------------------- anatomy, enforced
##
## RANGE OF MOTION PER JOINT, in radians about that joint's own MEASURED hinge, signed so
## that positive swings the paw forward (see `_measure_gains` — the hinge is derived from
## the rig's geometry, so this convention holds on every limb of an asymmetric auto-rig).
##
## THIS IS THE OWNER'S "ITS LIMBS ARE TURNING AGAINST ITS JOINTS", AND IT WAS MEASURABLE
## ALL ALONG. tests/CatJointProbe on the pre-fix animal, over ordinary walking, sitting,
## grooming and running:
##     R_Thigh  -78.9 .. +24.4 deg   (range 103.3)
##     R_Calf     0.0 .. +126.9 deg  (range 126.9)
##     L_Calf   -38.0 .. +52.7 deg   (range  90.7)
## A cat's hip cycles about 47 degrees and its stifle about 37. The right hind was being
## driven through more than twice a real animal's ENTIRE range, in both directions, every
## stride — because that chain's bones are a stub (R_Thigh->R_Calf is 0.086 m against the
## left's 0.336) so the solver needs absurd angles to put the paw anywhere. Nothing in the
## engine said no. Now something does.
##
## The ranges below are anatomical, not cosmetic: generous enough that ordinary gait,
## sitting and the pose library all pass untouched, tight enough that a hyperextended
## elbow or a hip swung past vertical cannot be drawn at all. The DISTAL joints
## (elbow/carpus, stifle/hock) are deliberately ASYMMETRIC — those joints bend one way
## only, and bending one backwards is the single creepiest thing this animal did.
const ROM_PROX := 0.62        ## shoulder / hip, either way
const ROM_DIST_FOLD := 1.35   ## elbow / stifle, in the folding direction
const ROM_DIST_BACK := 0.12   ## ...and the hard stop against hyperextension
const ROM_PAW := 0.50         ## carpus / hock
const ROM_TOE := 0.40
## SCAPULA TRAVEL, RAISED BECAUSE THE JOINT WAS SATURATING ITS OWN LIMIT. With BLADE_TRAVEL
## at 0.85 the joint probe measured L/R_Clavicle at exactly -21.8..+21.8 deg — i.e. pinned on
## 0.38 rad at BOTH ends through a run, which flat-tops the sine and draws as a stutter with
## no visible cause (the same trap the ear-scratch stroke amplitudes were sized to avoid).
## A real scapula travels FURTHER at a gallop than at a walk, so the ceiling was the wrong
## bound, not the amplitude: 0.52 rad clears the gallop's own peak (0.55 x amp x 0.85 = 0.47)
## with room, and the walk sits at 0.22 — well inside.
const ROM_BLADE := 0.52       ## scapula travel
## Radians per second the LOOK may sweep the head — the neck and head weights sum to 1.0,
## so this IS the drawn head's yaw rate. 2.8 rad/s puts a 90 degree glance at a third of a
## second: brisk, and nothing like the 600-1200 deg/s the owner was watching.
const LOOK_MAX_RATE: float = 2.8
## ...and the ceiling on the head's TOTAL drawn angular rate, enforced at the skeleton
## write on the composed result. Every head layer is individually calm — the look is
## rate-limited, the stabiliser residual is small, the chatter tremor is a few degrees —
## but the owner's eye sees their SUM, and CatJointProbe measured p99 sums of 214 deg/s
## (sit, stare re-targeting across a crossing gull) and 264 (run, tremor riding the
## stabiliser residual): each layer green, the head still too quick. Capping any one
## layer cannot bound a sum; the choke point can — the same shape as the ROM clamp, for
## the same reason. 3.3 rad/s is ~189 deg/s, under the probe's 200 gate with margin.
## 2.4 rad/s = 137 deg/s. Was 3.3, and the sit scenario measured a p99 of 182 — i.e. the head
## was living AT its own ceiling while glancing, which is the owner's "shakes side to side"
## in its calm-state form: a saccade that saturates its limiter reads as a snap rather than a
## look. A cat's casual head turn is brisk, not violent; the chatter tremor and the stabiliser
## both sit far below this, so this bounds the glance and nothing else.
const HEAD_MAX_RATE: float = 2.4
## ...and the same idea for the LIMBS, which is where KNOWN_ISSUES' s49 entry said the next
## session should start. The `_solve_leg` slew limiter in `tick` bounds the SOLVE and nothing
## else, and four layers are applied to those bones after it — the swing fold, the paw roll,
## the toe follow-through and the ROM clamp's own rebuild — so the drawn joint could step
## further than the limiter's ceiling by whatever they added. Measured before this: a walk
## limiter of 20 rad/s (0.333 rad/frame at 60 Hz) drew 0.472 rad/frame, and CatReviewProbe's
## joint_step gate failed honestly in six scenarios at once. Capping any one layer cannot
## bound a sum; the choke point can, which is the argument HEAD_MAX_RATE already makes one
## paragraph up, applied to the other end of the animal.
##
## 19 rad/s is 0.317 rad/frame at 60 Hz — inside the 0.35 gate with margin, and comfortably
## ABOVE what this gait legitimately asks for: the short-shank knees work at ~0.31 rad/frame
## at 4.74 strides a second (the figure the old ceiling was set against) and s52's walk runs
## at 2.47, so the honest requirement is ~0.16. A cat's elbow at a gallop cycles about 90
## degrees in 0.1 s, i.e. ~16 rad/s, so this is an anatomical ceiling rather than a numerical
## one and it is not scaled by gait: a joint that wants to move faster than a real cat's is
## the artefact, whatever speed the animal is going.
##
## It is applied to the LOCAL pose rotation, which is exactly the quantity CatReviewProbe
## measures, and only to bones that carry a ROM entry — the limbs. The torso, neck, head and
## tail have their own governors.
const LIMB_MAX_RATE: float = 19.0
## ...AND THE THIRD GOVERNOR, WHICH IS THE COVERAGE GAP KNOWN_ISSUES LEFT OPEN.
##
## `LIMB_MAX_RATE` is applied `if _rom.has(i)` — i.e. only to bones that carry a joint limit,
## which `_prep_ik` builds for the four limbs and nothing else. `R_ThighTwist01` has no ROM
## entry, so the one bone that carries the tail AND the rump (docs/CAT_RIG_CEILING.md §1) has
## never had a rate ceiling of any kind. CatReviewProbe knows to gate its WORLD orientation
## rather than its local pose — a bone posed absolutely against a moving parent legitimately
## steps locally as fast as that parent does — and that world gate WAS ALREADY FAILING at
## HEAD, in a band nothing routinely measures:
##     tail world step, rad/frame, gate 0.35:   HEAD walk 0.3317   HEAD trot 0.3662  ✗
##                                              s53 walk 0.3343    s53 trot 0.3675   ✗
##                                              s53 run  0.4608 ✗
## and re-siting the speed bands takes the walk over it too (0.4237).
##
## AND THE CAUSE IS NOT THE TAIL. 5d solves this bone's LOCAL rotation so that its WORLD basis
## equals a smooth spring target: `_out[tail] = _live_basis(parent).inverse() * g_want`. But
## `_live_basis` composes the frame's `_out` buffer, which is the PRE-CLAMP, PRE-LIMITER value,
## and the parent is `R_Thigh` — the binding hind's own hip, which is ROM-clamped 37% of its
## stance and sits on the limiter every swing. So the whole clamp-and-limiter residue of the
## worst-conditioned chain on the rig leaked straight out of the tail, at frame rate. That is
## the "capping any one layer cannot bound a sum" argument one more time, from the other side:
## the tail was cancelling a parent motion THAT NEVER HAPPENED.
##
## Both halves are fixed at the write (see the end of `tick`): the tail is re-solved against
## the parent's FINAL drawn basis, and then bounded in world space exactly the way the head is.
## 16 rad/s = 0.267 rad/frame at 60 Hz, chosen against the measured distribution rather than
## the gate — after the re-solve the gait's own 95th percentile is 0.09 rad/frame, so this is
## six times what healthy motion asks for and only the leak is clipped.
const TAIL_MAX_RATE: float = 16.0
## How much of the trunk's own pitch and roll the neck cancels. Cats are among the best
## head-stabilisers in the animal kingdom — the eyes hold a near-constant horizon while
## the body does whatever the gait demands — and the gait's spine engine pitches the chest
## up to 0.26 rad at a gallop with only 0.10 countered at the neck, so the head was riding
## the whole bob. Not 1.0: a perfectly pinned head reads as a puppet on a stick.
## A VAR rather than a const so tests/hip_bob_scratch.gd can sweep it in one run — the
## sign and the strength of a stabiliser are exactly the kind of thing this repo has three
## traps about guessing.
## 0.88 measured against the sweep (tests/hip_bob_scratch.gd), which prints head motion
## relative to the body at each setting: 0.0 -> 53 deg/s walking and 384 at a run; 0.88 ->
## about 14 and 90. Not 1.0 — a perfectly pinned head is a gyroscope, and the residual is
## what reads as a real neck absorbing the last of the stride.
static var HEAD_STAB: float = 0.88
## bone index -> [min, max] about that bone's hinge. Built in `_prep_ik`, where the fold
## DIRECTION of each knee is already measured rather than assumed.
var _rom: Dictionary = {}

## Clamp one composed bone rotation into its joint's range, preserving whatever off-hinge
## component it carries (a slerp between two authored poses picks up a little, and killing
## it outright would fight the pose library rather than the bug).
func _clamp_joint(bone: int, q: Quaternion) -> Quaternion:
	var lim = _rom.get(bone)
	if lim == null:
		return q
	var rest_q: Quaternion = _rest[bone]
	var hinge: Vector3 = _hinge_of(bone)
	var rel: Quaternion = rest_q.inverse() * q
	if rel.w < 0.0:
		rel = Quaternion(-rel.x, -rel.y, -rel.z, -rel.w)
	var v := Vector3(rel.x, rel.y, rel.z)
	var along: float = v.dot(hinge)
	var ang: float = 2.0 * atan2(along, maxf(rel.w, 1e-9))
	var cl: float = clampf(ang, float(lim[0]), float(lim[1]))
	if absf(cl - ang) < 1e-5:
		return q
	# Swing/twist: strip the hinge rotation off, put the clamped one back.
	var swing: Quaternion = rel * Quaternion(hinge, ang).inverse()
	return (rest_q * swing * Quaternion(hinge, cl)).normalized()

## Metres of fore-aft travel at `target`'s origin per radian of BODY-YAW at `driver` —
## the girdle's lever arm on this limb, measured off the rest skeleton exactly the way
## `_measure_gains` measures a hinge. A two-sided difference so a nonlinearity cannot bias it.
## Leaves the skeleton on the rest pose the caller handed in.
func _yaw_gain(driver: int, target: int, rest_q: Dictionary) -> float:
	if driver < 0 or target < 0:
		return 0.0
	var d: float = 0.12
	var ax: Vector3 = ((_rest_gb.get(driver, Basis.IDENTITY) as Basis).inverse() * BODY_UP).normalized()
	var out: Array[float] = []
	for sgn in [-d, d]:
		_set_chain(rest_q)
		_sk.set_bone_pose_rotation(driver, (_rest[driver] as Quaternion) * Quaternion(ax, sgn))
		out.append(_paw_pos(target).dot(BODY_FWD))
	_set_chain(rest_q)
	return (out[1] - out[0]) / (2.0 * d)

## HOW FAR THE BODY MUST SIT BELOW ITS REST HEIGHT, in metres, for every payable limb to cover
## `sweep` of ground on a FLAT stance without the two-bone solve having to shorten the chain.
##
## SAME TRIANGLE, DIFFERENT PAYER (s53). s52 derived this quantity per limb and spent it as
## paw LIFT during contact, which bought the stride and cost the plant: a paw that rides 38-59
## mm up and down while it is bearing weight is the slap the owner reported, and the two ends
## of that parabola do not meet the swing curve, so it teleported as well (see `_foot_path`).
## The solve only ever sees the socket-to-target VECTOR, so lowering the socket by h and
## raising the paw by h are the same number to every limb — and only one of them is what an
## animal does. Take the rest vector's components in the limb's own sagittal plane (`d_fw`
## forward, `d_up` down), push the paw `sweep/2` to the worse end, and ask what socket height
## puts the target back on the reach sphere:  h = -d_up - sqrt(cmax^2 - (d_fw +- sweep/2)^2).
##
## A LIMB THAT CANNOT SPAN ITS STANCE AT ANY HEIGHT GETS NO VOTE. `rad <= 0` means the worst
## end is outside the reach sphere however low the body goes — this rig's LEFT HIND, whose
## socket the auto-rig put 0.169 m forward and whose paw sits 0.364 m behind it (its demand
## computes as 170 mm, i.e. the animal on its belly, for a limb that would still clamp).
## That leg clamps and slides today and will keep doing so until the re-rig
## (docs/CAT_RIG_CEILING.md §3, KNOWN_ISSUES); crouching the whole animal for it would buy
## nothing and cost everything. The payable maximum on this fit is 48.7 mm, set by rh.
##
## AND IT IS NOT A PURE REACH SUM, WHICH IS THE TRAP THIS FUNCTION FELL INTO FIRST. Dropping
## the body shortens the chain the leg needs, and it also STEEPENS the hip: covering the same
## ground from a lower socket takes a bigger swing angle, and `ROM_PROX` is a real clamp. The
## first cut asked only "what height puts the target inside cmax" and answered 45.2 mm, at
## which the binding limb's hip pinned on ROM_PROX instead and its in-stance slide went 5.4 ->
## 16.6 mm/frame — a fix that traded one clamp for another. Measured, tests/GaitScratch block 8.
##
## Both constraints, per limb, for a half-sweep of x:
##     reach:  h <= sqrt(cmax^2 - x^2)         the chain must span it
##     hip:    h >= x / tan(ROM_PROX)          the swing angle must stay legal
## Any h between them works and the HIGHEST one is the least crouch, so take the reach bound —
## unless the two have crossed (x > cmax*sin(ROM_PROX), i.e. the sweep is wider than this limb
## can cover at any height), where the best compromise is exactly where they meet,
## h = cmax*cos(ROM_PROX). On this fit the three payable limbs then ask for 36.1 / 38.4 / 38.0
## mm and the fourth (lh, whose paw sits 0.364 m behind a socket 0.156 m up) asks for none:
## they AGREE, which is why one body height can serve four chains this mismatched.
##
## Recomputed per frame from the sweep actually in use, so a pose that shortens its stride
## (the stalk's `sweep_k`) automatically stands taller: a few flops and a sqrt per limb.
## HOW FAR THIS LIMB'S STANCE SWEEP IS SHIFTED BACK so it straddles the ground under its own
## socket instead of the ground under its REST PAW.
##
## A symmetric sweep about a paw that does not sit under its own socket is not symmetric in
## REACH: the far end costs `|fw_off| + sweep/2` of horizontal span and the near end
## `|fw_off| - sweep/2`. On this fit the left fore's rest paw is 45 mm AHEAD of its shoulder
## and that chain is 99.7% extended at rest, so its touchdown target sat 163 mm forward of a
## socket 285 mm up — 0.3276 m of span against 0.319 m of chain. The solve then held the paw
## ~25 mm high through the last frames of swing and dropped it in one, which is a slap that no
## amount of path smoothing can reach because the path was never the problem there.
##
## Centring costs NOTHING: the paw covers the same ground, foot-lock is unchanged (it is a
## constant offset, not a rate), and the shift itself fades with `step_w` because the solve's
## output does. It moves where the animal puts its feet, which is a real visual change and is
## why it is a knob rather than a silent constant.
##
## A LIMB WHOSE PAW IS FURTHER FROM ITS SOCKET THAN HALF ITS OWN REACH IS NOT A LEG in the
## two-bone sense and gets no shift — the left hind again, whose "thigh" is largely the tail
## root (docs/CAT_RIG_CEILING.md §3): its paw is 364 mm behind a socket with 440 mm of chain,
## and centring it would walk that foot 364 mm forward of where the pose puts it. Same
## exclusion rule, and the same limb, as `_body_drop`.
func _centre_off(k: String) -> float:
	var S: Dictionary = _ik.get(k, {})
	if S.is_empty():
		return 0.0
	var fw: float = float(S["fw_off"])
	if absf(fw) > float(S["cmax"]) * 0.5:
		return 0.0
	return fw * STANCE_CENTRE

## ...AND IT IS PRICED AT THE SWEEP THE ANIMAL ACTUALLY WALKS (s54). This function and
## `_centre_off` disagreed about where the stance sits: the path plants the sweep about the
## SOCKET (`STANCE_CENTRE` 1.0 subtracts each limb's `fw_off`), while the demand here was still
## measured about the REST PAW, `d_fw ± sweep/2`. On a rig whose rest paws sit 45-82 mm off
## their own sockets that is a different triangle, and it over-charged the two forelegs and
## under-read which limb was binding: the ledger said rf asked for 38.4 mm and set the crouch,
## when rf centred asks for ~0 and the real payer is rh at 37.7 mm. The crouch itself barely
## moves (0.5 mm at CROUCH_K 0.75) — what moves is that the number is now about the leg that
## is actually in trouble, which is the leg any future tuning has to be aimed at.
func _body_drop(sweep: float) -> float:
	var h: float = 0.0
	for k in _ik:
		var S: Dictionary = _ik[k]
		var cmax: float = float(S["cmax"])
		# Where this limb's stance is centred, socket-relative, after `_centre_off`. (The two
		# are measured on slightly different axes — `d_fw` in the limb's own sagittal plane,
		# `fw_off` along BODY_FWD — which on this fit differ by under a millimetre.)
		var mid: float = float(S["d_fw"]) - _centre_off(k)
		var x: float = maxf(absf(mid + sweep * 0.5), absf(mid - sweep * 0.5))
		var reach: float = cmax * cmax - x * x
		var want: float = maxf(sqrt(reach) if reach > 0.0 else 0.0, cmax * cos(ROM_PROX))
		h = maxf(h, -float(S["d_up"]) - want)
	return h

func _prep_ik() -> void:
	if not valid():
		return
	var rest_q := {}
	for i in _rest:
		rest_q[i] = _rest[i]
	_set_chain(rest_q)
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, _rest_t[_hip])
	for k in _limb:
		var L: Dictionary = _limb[k]
		var P: Vector3 = _sk.get_bone_global_pose(L["prox"]).origin
		var D0: Vector3 = _sk.get_bone_global_pose(L["dist"]).origin
		var W0: Vector3 = _paw_pos(L["paw"])
		var n: Vector3 = (W0 - P).cross(BODY_FWD)
		n = BODY_SIDE if n.length() < 1e-5 else n.normalized()
		var a: float = (D0 - P).length()
		var b: float = (W0 - D0).length()
		var c0: float = (W0 - P).length()
		if a < 1e-4 or b < 1e-4 or c0 < 1e-4:
			continue
		var e0: Vector3 = _flat(W0 - P, n)
		# WHICH WAY THE KNEE FOLDS IS MEASURED, NOT ASSUMED — the same discipline the hinge
		# derivation uses, and the reason this works on a rig whose two sides disagree. Rotate
		# the lower bone a little about its own hinge and see whether the chain shortens.
		_set_chain(rest_q)
		_sk.set_bone_pose_rotation(L["dist"], _rest[L["dist"]] * Quaternion(_hinge_of(L["dist"]), 0.2))
		var c_test: float = (_paw_pos(L["paw"]) - P).length()
		_set_chain(rest_q)
		var par: int = _sk.get_bone_parent(L["prox"])
		var par_t: Transform3D = _sk.get_bone_global_pose(par) if par >= 0 else Transform3D.IDENTITY
		# THE GIRDLE'S LEVER, MEASURED ON THIS SKELETON. Rotate the girdle bone about the
		# body's own up axis and read how far THIS limb's socket travels fore-aft. Same
		# discipline as the knee-fold test above, and the reason the s52 note can state what
		# the pelvis is worth on this fit instead of what a pelvis is worth in general.
		var g_bone: int = _spine2 if int(L["blade"]) >= 0 else _hip
		var g_amp: float = CHEST_YAW if int(L["blade"]) >= 0 else PELVIS_YAW
		var g_gain: float = _yaw_gain(g_bone, int(L["prox"]), rest_q)
		_set_chain(rest_q)
		if _hip >= 0:
			_sk.set_bone_pose_position(_hip, _rest_t[_hip])
		# THE STANCE PATH IS AN ARC, AND HOW DEEP AN ARC IS THE CHAIN'S OWN BUSINESS —
		# cached here so `tick` can ask for it in a few flops and a sqrt (see `_body_drop`):
		# the rest vector's components along the sagittal plane's forward and up, plus the
		# reach cap the solve clamps against.
		var e_up: Vector3 = _flat(BODY_UP, n)
		var e_fw: Vector3 = _flat(BODY_FWD, n)
		_ik[k] = {
			"P": P, "n": n, "a": a, "b": b, "c0": c0, "e0": e0, "W0": W0,
			"cmax": (a + b) * 0.985,
			"d_fw": (W0 - P).dot(e_fw),
			"d_up": (W0 - P).dot(e_up),
			# Metres of fore-aft SOCKET travel per radian of this limb's girdle rotation,
			# and the amplitude that rotation runs at. Turned into a stride budget in the
			# second pass below, once every limb's gain is known and the DRIVE SIGN can be
			# read off the reference limb instead of guessed.
			"g_gain": g_gain,
			"g_amp": g_amp,
			"girdle": 0.0,
			# HOW FAR THIS LIMB'S REST PAW SITS AHEAD OF ITS OWN SOCKET, in the body's frame
			# — the thing that makes one end of a symmetric sweep far harder than the other.
			# See `_centre_off`. Measured, like everything else in this dict.
			"fw_off": (W0 - P).dot(BODY_FWD),
			"alpha0": _tri_angle(a, c0, b), "beta0": _tri_angle(a, b, c0),
			# +1 when a positive rotation at the knee FOLDS the leg.
			"knee": -1.0 if c_test > c0 else 1.0,
			# HOW FAR THIS LEG CAN ACTUALLY SWING. Geometry, not a feel number: a limb of
			# reach c0 swinging +/-theta about its socket covers 2*c0*sin(theta) of ground.
			# The SHORTEST of the four still sets the stride for all of them — per-limb
			# envelopes truncate the two hinds by different amounts and put the limp straight
			# back — so these two numbers are the whole animal's, decided by the worst chain.
			#
			# 0.94*c0 IS 2*sin(28 deg), AND IT WAS A POLICY, NOT A LIMIT. Its history is worth
			# keeping because it is the trap this session nearly repeated. s45c raised it 0.845
			# -> 0.94 for the owner's "wider gait"; s49 pushed to 1.05 and MEASURED foot-lock
			# breaking (14.7 mm/frame of in-stance drift against a 10 mm gate), and the file has
			# said ever since that 0.94 is "this rig's ceiling". It is not, and the reason it
			# looked like one is that BOTH those measurements were taken on a gait running at
			# 4.7 strides a second. s51 halved the cadence (WALK_SPEED 1.55 -> 0.95) and nobody
			# re-measured the envelope underneath it. Slide per FRAME scales with cadence.
			#
			# What actually broke at 1.05 was not the swing angle, it was the PATH. A chain of
			# reach c0 covering s of ground traces an ARC — the paw cannot stay level, because
			# staying level means shortening a chain that is already at full stretch (this rig's
			# binding limb rests at 101.4% of the two-bone model's reach cap). `_foot_path` asked
			# for a flat stance with a hand-set 12 mm of rise at the ends; the geometry wanted
			# 25.6 mm at the old sweep and 39 at 1.05*c0. The difference came out of
			# `_reach_give`, and past ~1.0*c0 the give ran out, the solve fell back to SHORTENING
			# the reach, and a shortened stance path is exactly what a skate is. `_body_drop`
			# now derives that rise per limb from the limb's own triangle, so the clamp stops
			# firing and the envelope can go to the joint limit this file already enforces.
			#
			# WALK: 2*c0*sin(ROM_PROX) — the hip/shoulder clamp, so the swing envelope and the
			# anatomy clamp can no longer disagree — plus the measured girdle travel. GALLOP:
			# still 0.94, and see `_sweep_walk` for why the run does not get the new one.
			"sweep_max": 0.94 * c0,
			"sweep_walk": 2.0 * c0 * sin(ROM_PROX),
			# Which side of the chain line the knee sits on, so the thigh's own rotation adds
			# or subtracts the triangle's apex angle.
			"side": 1.0 if _flat(D0 - P, n).cross(e0).dot(n) < 0.0 else -1.0,
			# The socket this leg hangs from, and where it sat at rest — see `_solve_leg`.
			"parent": par,
			"parent_b0": par_t.basis.orthonormalized(),
			"parent_off": par_t.affine_inverse() * P,
		}
	_set_chain(rest_q)
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, _rest_t[_hip])
	# THE JOINT LIMITS, built here because this is where each knee's FOLD DIRECTION is
	# already a measured fact (`knee`) rather than a guess. Every limb bone gets a range;
	# the torso and the tail are governed by their own layers and are left alone.
	for k in _limb:
		var L2: Dictionary = _limb[k]
		var knee: float = float(_ik.get(k, {}).get("knee", 1.0))
		_rom[L2["prox"]] = [-ROM_PROX, ROM_PROX]
		# The one-way joint. `knee` is +1 when a POSITIVE rotation folds this leg, so the
		# generous end goes on that side and the hard stop on the other.
		_rom[L2["dist"]] = [-ROM_DIST_BACK, ROM_DIST_FOLD] if knee > 0.0 \
			else [-ROM_DIST_FOLD, ROM_DIST_BACK]
		_rom[L2["paw"]] = [-ROM_PAW, ROM_PAW]
		if int(L2["toe"]) >= 0:
			_rom[L2["toe"]] = [-ROM_TOE, ROM_TOE]
		if int(L2["blade"]) >= 0:
			_rom[L2["blade"]] = [-ROM_BLADE, ROM_BLADE]
	# THE GIRDLE'S DRIVE SIGN IS READ OFF THE MEASUREMENT, NOT ASSERTED — and it had to be.
	# The first cut of this drove the pelvis with +cos(phase) because that is the phase the
	# LEFT HIND's paw path peaks at, which is correct arithmetic about the paw and says nothing
	# about the bone: on this fit a positive pelvic yaw moves the left hip socket BACKWARD
	# (gain -0.0189 m/rad). Half a cycle out, the socket retreats from the planting paw, the
	# leg is asked for MORE reach rather than less, and the stride budget added on top of it
	# would have been a straight lie. So the sign comes from the measured gain of the
	# REFERENCE limb of each girdle — the one whose footfall offset the drive is written
	# against — and every other limb inherits it through its own WALK_OFF phase.
	var ref_h: float = float(_ik.get("lh", {}).get("g_gain", 1.0))
	var ref_f: float = float(_ik.get("lf", {}).get("g_gain", 1.0))
	_pelv_sign = -1.0 if ref_h < 0.0 else 1.0
	_chest_sign = -1.0 if ref_f < 0.0 else 1.0
	for k in _ik:
		var S3: Dictionary = _ik[k]
		var fore3: bool = int(_limb[k]["blade"]) >= 0
		var ref_off: float = float(WALK_OFF["lf" if fore3 else "lh"])
		var sgn3: float = _chest_sign if fore3 else _pelv_sign
		# The drive's value at THIS limb's own plant, as a fraction of its amplitude.
		var at_plant: float = sgn3 * cos(TAU * (ref_off - float(WALK_OFF[k])))
		# ...and the ground it is worth over a whole cycle. Negative means this girdle works
		# AGAINST this limb (two limbs of a pair whose measured gains share a sign, which a
		# yaw cannot serve) — it then earns no budget rather than a fictional one.
		var contrib: float = 2.0 * float(S3["g_amp"]) * float(S3["g_gain"]) * at_plant
		S3["girdle"] = maxf(0.0, contrib)
		S3["sweep_walk"] = float(S3["sweep_walk"]) + float(S3["girdle"])
	# The stride the whole animal can hold, set by whichever leg runs out first.
	_sweep_cap = 1e9
	_sweep_walk = 1e9
	for k in _ik:
		_sweep_cap = minf(_sweep_cap, float(_ik[k]["sweep_max"]))
		_sweep_walk = minf(_sweep_walk, float(_ik[k]["sweep_walk"]))
	if _sweep_cap > 1e8:
		_sweep_cap = 0.24
	if _sweep_walk > 1e8:
		_sweep_walk = _sweep_cap
	_sweep_walk = maxf(_sweep_walk, _sweep_cap)
	_bind_limb = ""
	for k in _ik:
		if is_equal_approx(float(_ik[k]["sweep_walk"]), _sweep_walk):
			_bind_limb = k
			_sweep_girdle = float(_ik[k]["girdle"])
			break
	# THE DIAGNOSTIC READS THE CONSTANTS THE GAIT READS. It divided by a hard-typed 0.62
	# and 0.38 for four sessions after the duties moved to 0.55 and 0.20, so the one line
	# anybody checks the stride against under-reported the walk by 11% (0.291 against a
	# true 0.329) and over-reported the gallop. A diagnostic that does not read the live
	# value is a comment that can lie, which is the same failure mode as an assertion that
	# cannot fail — and this repo has a trap filed about each.
	print("[cat_rig] foot-lock sweep %.3f m walking (leg %.3f + girdle %.3f, bound by %s)"
		% [_sweep_walk, _sweep_walk - _sweep_girdle, _sweep_girdle, _bind_limb]
		+ ", %.3f m at a gallop" % _sweep_cap)
	print("[cat_rig]   -> stride %.3f m at duty %.2f walking, %.3f m at duty %.2f galloping"
		% [_sweep_walk / WALK_DUTY, WALK_DUTY, _sweep_cap / GALLOP_DUTY, GALLOP_DUTY])
	# The solve triangles, one line per leg — the cheapest check that the two-bone model
	# FITS each chain: a rest reach (c0) OUTSIDE [fold-floor, reach-cap] means that leg's
	# law-of-cosines saturates at rest and its knee will spike wherever the clamps engage.
	for k2 in _ik:
		var S2: Dictionary = _ik[k2]
		print("[cat_rig]   %s  a %.3f  b %.3f  c0 %.3f  fold-floor %.3f  reach-cap %.3f"
			% [k2, S2["a"], S2["b"], S2["c0"],
				absf(float(S2["a"]) - float(S2["b"])) * 1.05, (float(S2["a"]) + float(S2["b"])) * 0.985])

## A vector flattened into the plane perpendicular to `n`, normalised.
func _flat(v: Vector3, n: Vector3) -> Vector3:
	var f: Vector3 = v - n * n.dot(v)
	return Vector3(1, 0, 0) if f.length() < 1e-6 else f.normalized()

## The angle opposite side `opp` in a triangle with the other two sides `s1`, `s2`.
func _tri_angle(s1: float, s2: float, opp: float) -> float:
	return acos(clampf((s1 * s1 + s2 * s2 - opp * opp) / maxf(2.0 * s1 * s2, 1e-6), -1.0, 1.0))

## Solve one leg to put its paw at `target` (skeleton space). Returns [prox, dist] rotations
## about that limb's hinge, RELATIVE TO REST — which is exactly the form the additive layer
## wants, so the result composes onto the blended pose like every other layer here.
func _solve_leg(k: String, target: Vector3) -> Array:
	var S: Dictionary = _ik.get(k, {})
	if S.is_empty():
		return [0.0, 0.0]
	# THE LEG ROOT MOVES, AND THE SOLVE HAS TO KNOW. Half of a gallop is the spine: the back
	# rounds and hollows, the pelvis tucks, the hip bobs — so the shoulder and hip sockets the
	# legs hang from are somewhere different every frame. Solved against the REST socket the
	# targets drift, and because the four sockets drift by different amounts it drew as a limp
	# at speed (hind reach ratio 0.70) on a walk that was already symmetric.
	#
	# So the target is carried back into rest space through the PARENT's motion, and the solve
	# stays in the frame it was measured in. The parent chain is read, never the limb's own
	# bones, so this cannot feed back on itself — a leg's own solve has no influence on where
	# its socket is.
	var P: Vector3 = S["P"]
	var n: Vector3 = S["n"]
	var par: int = int(S["parent"])
	if par >= 0:
		# THE PARENT IS THIS FRAME'S, NOT LAST FRAME'S. get_bone_global_pose here reads the
		# skeleton, which still holds the previous tick — and a one-frame-stale socket under
		# a moving pelvis slides every stance paw by exactly the pelvis's per-frame motion.
		# The torso layers run before the legs now, so the live chain is complete.
		var bp: Transform3D = _live_xform(par)
		var r: Basis = bp.basis.orthonormalized() * (S["parent_b0"] as Basis).inverse()
		var p_live: Vector3 = bp * (S["parent_off"] as Vector3)
		target = P + r.inverse() * (target - p_live)
	var a: float = S["a"]
	var b: float = S["b"]
	var v: Vector3 = target - P
	v -= n * n.dot(v)
	# OUT OF REACH IS RESOLVED UPWARD, NOT INWARD.
	#
	# The obvious clamp — scale the target back along its own ray — shortens the stride, and
	# it shortens it by a DIFFERENT amount on each leg because no two chains on this rig are
	# the same length. That is what kept the limp alive at a gallop (hind reach ratio 0.67)
	# after the walk had been made symmetric: the left hind is straight in its bind pose, so
	# it ran out of reach first and quietly gave up 70 mm of stride the right hind kept.
	#
	# A real leg at full stretch does not shorten its stride, it LIFTS ITS PAW. So the target
	# is raised until it is reachable and its fore-aft component is preserved exactly — which
	# keeps both sides covering the same ground, whatever their bones are doing.
	var cmax: float = (a + b) * 0.985
	if v.length() > cmax:
		var up_p: Vector3 = _flat(BODY_UP, n)
		var hb: float = v.dot(up_p)
		var disc: float = hb * hb - (v.length_squared() - cmax * cmax)
		# THE NEAR ROOT, AND ONLY A LITTLE OF IT. Both roots put the paw back on the reach
		# sphere; the far one carries it up past the socket and out the other side, which
		# measured as a 636 mm paw lift on a 0.66 m cat — the leg swinging over its own hip.
		# The near root is the small rise that was wanted, but it is CAPPED: the left hind is
		# straight in its bind pose and so is at its limit almost all the time, and an
		# uncapped rise let it float 143 mm while its opposite number stayed at 43. Past the
		# cap the honest answer is that this leg cannot cover that ground, so fall back to
		# shortening the reach.
		if disc >= 0.0:
			v += up_p * clampf(-hb - sqrt(disc), 0.0, _reach_give)
		if v.length() > cmax:
			v = v.normalized() * cmax
	var c: float = clampf(v.length(), absf(a - b) * 1.05 + 1e-3, cmax)
	var e: Vector3 = _flat(v, n)
	var e0: Vector3 = S["e0"]
	var dphi: float = atan2(e0.cross(e).dot(n), e0.dot(e))
	var alpha: float = _tri_angle(a, c, b)
	var beta: float = _tri_angle(a, b, c)
	var prox: float = dphi + float(S["side"]) * (alpha - float(S["alpha0"]))
	var dist: float = float(S["knee"]) * (float(S["beta0"]) - beta)
	return [prox, dist]

## THE FOOT PATH, in metres relative to this limb's own rest stance: [fore-aft, lift].
##
## `duty` is the fraction of the cycle the paw spends on the deck — 0.62 at a walk, 0.38 at a
## gallop, which is the number the old keyframe tables encoded and the thing that stops a gait
## reading as clockwork. `sweep` is how far the paw travels during stance, and it is NOT the
## stride: the body covers `stride` in a whole cycle, so a paw down for `duty` of that cycle
## must travel `stride * duty` backwards to stay put. Getting that product right is the whole
## of foot-lock.
## THE WHOLE CYCLE IS ONE CONTINUOUS CURVE NOW (s53), and the three defects it had were all
## in the seams rather than in the shapes:
##
##   * THE PAW TELEPORTED VERTICALLY BY `arc` AT BOTH TRANSITIONS. Stance height was
##     `arc*e^2`, which is `arc` at BOTH ends of the contact; swing height was `lift*sin(PI*s)`,
##     which is ZERO at both ends of the swing. So the drawn paw jumped DOWN by arc at toe-off
##     and UP by arc at touchdown, every footfall, on every limb. Measured before the fix
##     (tests/GaitScratch block 5): 39.6 / 41.2 / 12.0 / 41.1 mm — a four-centimetre vertical
##     teleport at every plant. Two continuous shapes joined at a discontinuity is still a
##     discontinuity, and it is the owner's "feet slap".
##   * THE PLANTED PAW ROSE 38-59 mm WHILE BEARING WEIGHT. Foot-lock in this engine is
##     HORIZONTAL: the paw sweeps backward at body speed, and `arc*e^2` then moved it up and
##     down through the contact. A real paw does not travel six centimetres vertically while
##     it is on the ground.
##   * IT ARRIVED AT MAXIMUM DOWNWARD SPEED. d/ds of `lift*sin(PI*s)` is `lift*PI*cos(PI*s)`,
##     i.e. `-lift*PI` at s=1 — the fastest descent of the whole swing, at the exact instant
##     of contact, under a comment claiming the opposite. Vertical speed at touchdown must go
##     to ZERO; that is the entire difference between a step and a slap.
##
## THE ARC ITSELF WAS RIGHT ABOUT THE GEOMETRY AND WRONG ABOUT WHO PAYS. A chain of reach c0
## covering s of ground cannot stay level — this rig's binding limb (rh) is 0.192 m of bone
## covering 0.232 m of deck — so SOMETHING has to give by ~40-49 mm. A real quadruped whose
## leg reaches full extension DROPS ITS HIP; it does not lift its planted paw. The same
## millimetres are now taken out of the BODY (`_body_drop`, applied to the hip in `tick`),
## which is exactly equivalent for every limb's reach — the solve only ever sees the socket-
## to-target vector — and leaves the paw flat, planted and continuous. Verified: with the
## drop in, saturation and in-stance slide are unchanged or better, and the paw's whole
## vertical is one C1 curve.
##
## `duty` is the fraction of the cycle the paw spends on the deck. `sweep` is how far the paw
## travels during stance, and it is NOT the stride: the body covers `stride` in a whole cycle,
## so a paw down for `duty` of that cycle must travel `stride * duty` backwards to stay put.
## Getting that product right is the whole of foot-lock.
func _foot_path(t: float, duty: float, sweep: float, lift: float) -> Vector2:
	if t < duty:
		# STANCE — flat, and a straight line backwards at body speed. The paw is on the deck;
		# it stays on the deck; the headroom the chain needs comes out of the body.
		return Vector2(sweep * (0.5 - t / maxf(duty, 1e-4)), 0.0)
	var s: float = (t - duty) / maxf(1.0 - duty, 1e-4)
	# SWING, FORE-AFT — the end SLOPES MATCH THE STANCE'S, so the paw is stationary IN THE
	# WORLD at toe-off and at touchdown rather than stationary relative to the BODY. The old
	# smoothstep did the latter (its comment said "what a real limb does"; it is the opposite):
	# zero body-relative velocity at contact means the paw is travelling FORWARD at body speed
	# the instant it lands and must stop dead in one frame, which is a horizontal scuff on top
	# of the vertical one. A cubic Hermite with both end slopes set to the stance rate
	# `-sweep*(1-duty)/duty` fixes it and costs one extra term. It also produces SWING-LEG
	# RETRACTION for free — the paw reaches ~4% of the sweep past its landing point and comes
	# back to meet the ground — which is what real animals do and why their touchdowns are quiet.
	var m: float = -sweep * (1.0 - duty) / maxf(duty, 1e-4)
	var x: float = sweep * (s * s * (3.0 - 2.0 * s) - 0.5) + m * s * (2.0 * s - 1.0) * (s - 1.0)
	return Vector2(x, lift * _swing_bump(s))

## THE SHAPE OF EVERYTHING THAT HAPPENS DURING A SWING AND MUST BE OVER BY THE PLANT — the
## paw's lift and the authored knee fold both ride this, because they are the same event
## (the leg folds in order to lift the paw) and because both had the same defect.
##
## Zero VALUE and zero RATE at both ends, apex before the middle. Two raised cosines meeting
## at the apex, so it is C1 at 0, at the apex and at 1 with no flat top to punctuate it. The
## `sin(PI*s)` this replaces is zero at both ends and moving FASTEST there: at s=1 its rate is
## -PI x amplitude, i.e. the whole layer unwinds at maximum speed at the exact instant of
## contact. That was true of the paw's lift AND of the swing fold, and the fold is the larger
## of the two on this rig — 0.42 rad of elbow at ~0.145 m of forearm is ~17 mm of paw in the
## last frame before touchdown, on top of the lift's own.
func _swing_bump(s: float, apex: float = -1.0) -> float:
	var p: float = SWING_APEX if apex < 0.0 else apex
	if s < p:
		return 0.5 - 0.5 * cos(PI * s / maxf(p, 1e-4))
	return 0.5 + 0.5 * cos(PI * (s - p) / maxf(1.0 - p, 1e-4))

func _round_d(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d:
		o[k] = snappedf(float(d[k]), 0.001)
	return o

func valid() -> bool:
	return _sk != null and _limb.get("lf", {}).get("prox", -1) >= 0

func has_pose(nm: String) -> bool:
	return _poses.has(nm)

func pose_count() -> int:
	return _poses.size()

## ---------------------------------------------------------------- the library

## Donor poses come from the OTHER rigged meshes' rest poses. Same bone names, same
## template, different stances — a bone's local rest rotation IS the pose, to the accuracy
## the auto-rig fits agree, and that accuracy was settled by rendering every pose in
## tests/CatBlendShot before any of this shipped.
func _load_library(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or not d.has("poses"):
		return
	var stand_hip: Array = d["poses"].get("stand", {}).get("hip_t", [0, 0, 0])
	for pose_name in d["poses"]:
		var src: Dictionary = d["poses"][pose_name]
		var entry := {"q": {}, "hip_t": _rest_t.get(_hip, Vector3.ZERO)}
		for bone_name in src.get("bones", {}):
			var i: int = _b(bone_name)
			if i < 0:
				continue
			var a: Array = src["bones"][bone_name]
			entry["q"][i] = Quaternion(a[0], a[1], a[2], a[3]).normalized()
		# The Hip TRANSLATION carries the crouch: a sitting pelvis is lower than a standing
		# one and no rotation can express that. Applied as a DELTA off the donor set's own
		# stand, onto this skeleton's rest — absolute donor positions belong to the donor's
		# skeleton, not this one.
		var ht: Array = src.get("hip_t", stand_hip)
		var dh := Vector3(ht[0] - stand_hip[0], ht[1] - stand_hip[1], ht[2] - stand_hip[2])
		entry["hip_t"] = _rest_t.get(_hip, Vector3.ZERO) + dh
		_poses[pose_name] = entry

## ---------------------------------------------------------------- driving

## Name the pose the behaviour wants. Cheap and idempotent — the blend does the rest.
## `rate` is how urgently to get there: a startled bolt blends faster than settling to sleep.
##
## THE TRANSITION GRAMMAR LIVES HERE, so every caller — behaviour, film, probe — gets it
## for free. A single exponential crossfade between two static poses MELTS: no weight
## shift, no anticipation, no settle, and a sit<->gallop midpoint puts the cat through the
## floor. So family crossings route through short authored sub-pose timelines
## (anticipation -> extreme -> settle), with §-minimum holds that never crossfade shorter:
##   * standing/moving -> sit family: weight rocks BACK (sit_pre), sinks a whisker DEEPER
##     than the target (sit_deep — the overshoot a body with mass has), then the target.
##   * sit family -> moving: the REAR lifts first (rise) — a cat never stands as one rigid
##     unit — then off. Both directions pass through crouched keys, so no blend can
##     midpoint the animal through the deck.
##   * stand -> walk/run: a 0.1 s forward lean, the small weight shift before the first
##     stride. The lean is itself a locomotion pose, so the stride can begin under it.
## Same-family changes (sit <-> groom, walk <-> run) stay plain crossfades — their
## midpoints are all legal cat.
const _SIT_FAMILY := ["sit", "groom", "groom_flat", "groom_scratch", "sleep"]
const _MOVE_FAMILY := ["walk", "run", "stalk", "carry", "stand", "jump", "stretch"]

func set_pose(nm: String, rate: float = 7.0) -> void:
	if not _poses.has(nm):
		return
	if nm == _target:
		_blend_rate = rate
		return
	var from: String = _target
	_target = nm
	_blend_rate = rate
	_seq = []
	_seq_t = 0.0
	if from in _SIT_FAMILY and nm in _MOVE_FAMILY and _poses.has("rise"):
		_seq = [["rise", 0.20, 9.0]]
	elif from in _MOVE_FAMILY and nm in _SIT_FAMILY and _poses.has("sit_pre"):
		_seq = [["sit_pre", 0.16, 9.0], ["sit_deep", 0.14, 7.0]]
	elif from == "stand" and (nm == "walk" or nm == "run") and _poses.has("lean"):
		_seq = [["lean", 0.10, 12.0]]

## Play an explicit sub-pose timeline ([[pose, hold_sec, rate], ...]) and settle on
## `final`. For transitions whose timing is owned by the caller — the jump's crouch is held
## while the body is still on the deck, and the land pose while it absorbs.
func play_seq(steps: Array, final: String, final_rate: float = 7.0) -> void:
	if not _poses.has(final):
		return
	_target = final
	_blend_rate = final_rate
	_seq = []
	_seq_t = 0.0
	for s in steps:
		if _poses.has(String(s[0])):
			_seq.append([String(s[0]), maxf(float(s[1]), 0.0), float(s[2])])

func target() -> String:
	return _target

## SAY WHAT THE TAIL IS DOING. `up` is carriage: +1 is the vertical greeting flag a cat raises
## when it comes to meet someone, 0 is level, -1 is clamped down over the hocks. `sway` is how
## wide it moves and `rate` how fast — the two together are the whole vocabulary, because a
## slow wide arc means content and a hard fast flick means the opposite, and everyone reads
## both without being taught. Eased in `tick`, never snapped.
func tail(up: float, sway: float, rate: float) -> void:
	_tail_up_t = clampf(up, -1.0, 1.0)
	_tail_sway_t = clampf(sway, 0.0, 1.5)
	_tail_rate_t = clampf(rate, 0.0, 14.0)

## WHICH WASH IS IT? A cat does not have one grooming animation, it has a repertoire, and
## running the same paw-lick every time is what makes an idle animal read as a loop. The
## styles differ in which part of the body does the work, so they are legible from across a
## deck without any facial detail:
##   0 PAW     — the classic. Forepaw up to the lowered muzzle, short quick strokes.
##   1 FLANK   — head right round to the shoulder and side, long slow strokes, body curled in.
##   2 CHEST   — head down between the forelegs, small strokes, the most hunched of the four.
##   3 SCRATCH — the hind foot up at the ear, weight rolled onto the other hip. Three paws on
##               the deck and one working, which is why it needs a pose of its own.
##
## EACH STYLE NAMES ITS OWN BODY, in one table, because a style is a body plus a motion and the
## two have been separated once already: the raised forepaw was baked into the single `groom`
## pose, so the flank wash filmed as a cat washing its shoulder while holding a paw in the air.
## `tick` gates the strokes on this same table, so a style can never be drawn on a body that
## does not belong to it.
const _GROOM_POSE := ["groom", "groom_flat", "groom_flat", "groom_scratch"]

func groom_style(i: int) -> void:
	_groom_style = clampi(i, 0, _GROOM_POSE.size() - 1)
	# Retargeting here rather than at the call site means a caller cannot pick a style and
	# forget the body that goes with it.
	if _GROOM_POSE.has(_target):
		set_pose(String(_GROOM_POSE[_groom_style]), _blend_rate)

## A FULL-BODY SHAKE — the wet-dog ripple, which cats do on waking, after rain, and after any
## indignity. Decays like the look, so one call is one shake.
func shake(w: float) -> void:
	_shake_w = maxf(_shake_w, clampf(w, 0.0, 1.0))

## ---------------------------------------------------------------- skeletal reactions
##
## These five replace every whole-body node rotation ship_cat used to write (see the long
## note at section 5f). All of them are expressed in the animal's own body, so a cat being
## petted arches and presses instead of tipping over, and a cat on a ramp pitches its chest
## instead of hinging as one plank about its origin.

## Being stroked: the back arches into the hand, the head presses up into it. Decaying, so
## one call per pet is enough and repeated calls keep it going.
func pet(w: float = 1.0) -> void:
	_pet_w = maxf(_pet_w, clampf(w, 0.0, 1.0))

## Fed, and briefly delighted about it.
func delight(w: float = 1.0) -> void:
	_delight_w = maxf(_delight_w, clampf(w, 0.0, 1.0))

## The tread — the hind-foot paddle and rear waggle that winds up a pounce.
func wiggle(w: float = 1.0) -> void:
	_wiggle_w = maxf(_wiggle_w, clampf(w, 0.0, 1.0))

## A settled animal shifting its weight, -1..1 across the body. Held, not decaying.
func weight_shift(x: float) -> void:
	_shift_t2 = clampf(x, -1.0, 1.0)

## The ground's slope under the animal, radians, +ve nose-up. Held and eased.
func slope(rad: float) -> void:
	_slope_t = clampf(rad, -0.7, 0.7)

## A TAIL FLICK — an IMPULSE, not a pose.
##
## The sway layer moves where the tail wants to be and the spring follows it, which gives
## a lovely slow arc and cannot flick: a flick is not a change of intent, it is a muscular
## snap that the tail's own mass then rides out. So this injects ANGULAR VELOCITY straight
## into the spring and lets the physics do the rest — the tail whips over, overshoots,
## comes back past centre and settles, all out of the same damped equation that carries
## the sway. `power` is roughly the peak rate in rad/s; sign picks the side, and zero
## alternates so repeated flicks read as a lashing tail rather than a twitch.
func tail_flick(power: float = 1.0) -> void:
	if _tail < 0:
		return
	# Sized against the spring: omega = sqrt(55) = 7.4 rad/s, so an impulse v produces a
	# peak of roughly 0.6*v/omega. 4.0 puts a full-power flick at ~0.32 rad, which is just
	# inside the bone's 0.36 rad hard stop — the tail reaches its limit on the biggest
	# flick and never slams into it.
	var p: float = clampf(absf(power), 0.0, 1.0) * 4.0
	_flick_side = -_flick_side if absf(power) < 0.001 or signf(power) == _flick_side \
		else signf(power)
	_tail_yaw_v += p * _flick_side

## THE CHATTER — the staccato jaw rattle a cat makes at a bird it cannot reach. There is no jaw
## bone on this rig, so it is carried as a fast, tiny head tremor, which is what actually reads
## at game distance anyway. Decays like the look, so it stops unless renewed.
func chatter(w: float) -> void:
	_chat_w = maxf(_chat_w, clampf(w, 0.0, 1.0))

## Point the head. Weight decays in tick, so a glance fades unless renewed.
func look(yaw: float, pitch: float, weight: float) -> void:
	_look_yaw = clampf(yaw, -1.05, 1.05)
	_look_pitch = clampf(pitch, -0.5, 0.5)
	_look_w = maxf(_look_w, clampf(weight, 0.0, 1.0))

## THE ONE WRITER. Called once per frame by ship_cat with:
##   dt     — the (possibly AiBudget-summed) delta
##   speed  — the speed the animal is trying to move at, m/s
##   moved  — metres ACTUALLY covered this frame (drives the phase; a blocked cat's legs stop)
##   yaw_rate — rad/s the BODY is actually turning at, which drives the turn-in-place step
##              cycle. Optional so every existing caller keeps working unchanged.
func tick(dt: float, speed: float, moved: float, yaw_rate: float = 0.0) -> void:
	if not valid():
		return
	_anim_t += dt
	# 0. The transition timeline, if one is playing: the front sub-pose is the blend target
	# until its hold elapses, then the next, then `_target`. Advanced on SIM time like
	# everything else here.
	var pose_name: String = _target
	var rate: float = _blend_rate
	if not _seq.is_empty():
		_seq_t += dt
		while not _seq.is_empty() and _seq_t >= float(_seq[0][1]):
			_seq_t -= float(_seq[0][1])
			_seq.pop_front()
		if not _seq.is_empty():
			pose_name = String(_seq[0][0])
			rate = float(_seq[0][2])
	var k: float = 1.0 - exp(-rate * dt)
	var pose: Dictionary = _poses.get(pose_name, _poses["stand"])
	# 1. Blend every bone toward the target pose — this dict is the ONLY persistent state,
	# and only pose targets ever land in it.
	#
	# THE PELVIS LEADS AND THE HEAD TRAILS, per bone, always: a transition that reaches
	# every joint on the same exponential moves as one rigid unit, and "the whole cat
	# arrives at once" is most of what a melt is. The hip drives, the spine follows, the
	# neck and head land last — the successive breaking of joints, priced into the blend
	# itself so no timeline has to fake it.
	for i in _cur_q:
		var want: Quaternion = pose["q"].get(i, _rest[i])
		var lead: float = 1.0
		if i == _hip:
			lead = 1.35
		elif i == _spine or i == _spine2:
			lead = 1.1
		elif i == _neck:
			lead = 0.8
		elif i == _head:
			lead = 0.7
		var kb: float = k if lead == 1.0 else 1.0 - exp(-rate * lead * dt)
		_cur_q[i] = (_cur_q[i] as Quaternion).slerp(want, kb)
	_cur_hip = _cur_hip.lerp(pose["hip_t"], 1.0 - exp(-rate * 1.35 * dt))
	# The frame's write starts as the blended pose; everything after this multiplies into
	# the frame, not into the state.
	_out.clear()
	_out_hip = _cur_hip
	# 2. Gait weight and smoothed speed. The weight fades IN with motion and OUT at rest,
	# so stopping mid-stride eases the legs home instead of snapping them.
	var moving: float = clampf(speed / 0.4, 0.0, 1.0) * clampf(moved / maxf(dt * 0.05, 1e-6), 0.0, 1.0)
	# THE GAIT RIDES ANY POSE THAT LOCOMOTES — a per-pose flag, never a name list. The list
	# this replaces allowed walk/run/stand and silently excluded "stalk" and "carry", both of
	# which translate the body through ship_cat._walk_toward: the predatory creep and the
	# gift walk — the two beats a companion cat is watched hardest — slid across the deck on
	# frozen legs. Measured before the fix (tests/CatReviewProbe): stalk moved 2.68 m at gait
	# weight 0.000, paws drifting 10.5 mm/frame — exactly body speed, the textbook moonwalk.
	# Any pose that moves the body must carry the flag; the probe's locomotes=>steps gate
	# fails any that forgets.
	if not bool(pose.get("loco", false)):
		moving = 0.0
	# Engage FAST, disengage soft: a cat's first stride is abrupt (the appendix's "don't
	# over-smooth away the snap"), and a slow engage is ~0.4 s of body moving on legs at
	# partial amplitude — which is a brief, real skate. Stopping still hands the legs back
	# gently.
	_gait_w = lerpf(_gait_w, moving, 1.0 - exp((-14.0 if moving > _gait_w else -6.0) * dt))
	_speed_s = lerpf(_speed_s, speed, 1.0 - exp(-6.0 * dt))
	# 3. Phase from DISTANCE, not time — and the STRIDE COMES OUT OF THE ANIMAL'S OWN LEGS.
	#
	# It used to be `0.52 + speed/4.4 * 0.35`, two hand-picked numbers, and they asked for a
	# stride of 0.64 m from a cat whose hind leg is 0.19 m from hip to paw. A leg that long can
	# sweep about 0.25 m of deck however it is driven, so the other 0.39 m per cycle had to come
	# from somewhere, and it came from the paws SLIDING — 24 to 30 mm every frame, measured, at
	# almost exactly body speed. That is the skating, and no keyframe could have fixed it,
	# because the gait was asking for ground the animal did not have the legs to cover.
	#
	# Now: a paw is down for `duty` of the cycle and can sweep `_sweep_cap` while it is there,
	# so the stride is exactly `_sweep_cap / duty` and foot-lock is a consequence rather than a
	# feature. It falls out at every speed — a shorter duty at a gallop lengthens the stride on
	# its own, which is what a real animal does — and it re-derives itself for any future rig
	# whose legs are a different length.
	var mix: float = clampf((_speed_s - WALK_V) / (TROT_V - WALK_V), 0.0, 1.0)
	# A pose may reshape the gait without new code: `duty` (ground fraction), `sweep_k`
	# (stride envelope) and `lift_k` (paw lift) — the stalk uses all three to fold the walk
	# into a creep: feet still IK-planted, steps short and low, duty high. The stride stays
	# derived (`sweep / duty`), so foot-lock survives every override by construction.
	# DUTY AT A GALLOP WAS THE CADENCE BUG, and the cadence was half of "his whole body
	# moves unnaturally / bobs up and down too quick".
	#
	# Stride is `sweep / duty`, so a duty of 0.38 on this cat's 0.221 m sweep gave a
	# 0.58 m stride — and at RUN_SPEED 4.4 m/s that is SEVEN AND A HALF STRIDES A SECOND.
	# A real cat gallops at three to four. Everything phase-locked to the cycle inherited
	# that: the spine engine swung 0.42 rad at 7 Hz, which is over a thousand degrees a
	# second of trunk rotation for the head to inherit, and no stabiliser can filter a
	# signal that fast.
	#
	# The fix is the duty itself. A galloping cat is AIRBORNE about 80% of the time — the
	# appendix's measured figure is ~0.18 — so a short contact and a long stride is not a
	# cheat, it is what a gallop is. At 0.20 the stride becomes 1.1 m and the cadence 4 Hz,
	# which is a real cat's. Foot-lock is untouched: it only ever applied during contact,
	# and contact is still exact.
	# Walk duty 0.62 -> 0.55 (s45c, the owner's "wider, slower, smoother"): stride is
	# sweep/duty, so a shorter stance fraction LENGTHENS the stride and drops the walking
	# cadence ~20%% — fewer, longer, more deliberate steps at the same ground speed.
	var duty: float = float(pose.get("duty", lerpf(WALK_DUTY, GALLOP_DUTY, mix)))
	var sweep_k: float = float(pose.get("sweep_k", 1.0))
	var lift_k: float = float(pose.get("lift_k", 1.0))
	# THE ENVELOPE IS THE WALK'S AT A WALK AND THE GALLOP'S AT A GALLOP, eased by the same
	# `mix` that eases the footfall offsets — because the girdle drive that pays for part of
	# the walk's extra reach is itself walk-only (GALLOP_OFF lands the hinds 0.12 apart, so
	# there is no differential for a pelvic yaw to express) and because the run has no gate
	# that can see its stance yet. See `_sweep_walk`.
	var sweep_env: float = lerpf(_sweep_walk, _sweep_cap, mix)
	var stride: float = maxf(sweep_env * sweep_k, 0.05) / duty
	_phase = fposmod(_phase + moved / stride, 1.0)
	# 3b. TURN IN PLACE IS A GAIT, NOT A TURNTABLE (flaw 4). `_face` lerps the node's yaw with
	# the feet planted, so a cat asked to turn round pivots like a display stand and all four
	# paws skate. A real cat picks its feet up and shuffles them round. When the body is
	# yawing appreciably and going nowhere, run a low quick diagonal-pair step cycle driven by
	# the YAW — the same "phase comes from what the body actually did" rule this file already
	# applies to translation, applied to rotation.
	_yaw_rate = lerpf(_yaw_rate, yaw_rate, 1.0 - exp(-10.0 * dt))
	var turn_w: float = clampf((absf(_yaw_rate) - 0.30) / 1.10, 0.0, 1.0) \
		* clampf(1.0 - _gait_w * 1.6, 0.0, 1.0)
	if not bool(pose.get("loco", false)):
		turn_w = 0.0
	_turn_phase = fposmod(_turn_phase + absf(_yaw_rate) * dt * 0.42, 1.0)
	# 4. The gait — keyframed limb cycles plus the spine engine, if any of it is live.
	var step_w: float = maxf(_gait_w, turn_w)
	if step_w > 0.003:
		# A turning shuffle is a diagonal-pair pattern that barely reaches at all — it is
		# almost pure lift-and-place. Blend toward that when the turn is what is driving.
		var turning: float = clampf(turn_w / maxf(step_w, 1e-5), 0.0, 1.0)
		var base_ph: float = lerpf(_phase, _turn_phase, turning)
		var amp: float = (0.85 + 0.15 * mix) * step_w
		var reach_k: float = lerpf(1.0, 0.22, turning)
		# THE TORSO MOVES FIRST, THE LEGS SOLVE AGAINST IT. The spine engine and the body
		# vertical below reshape the sockets the legs hang from; solving the legs first
		# meant every stance paw chased a socket one write behind — and reading the
		# Skeleton3D instead is one whole FRAME behind (it still holds last tick).
		#
		# THE SPINE ENGINE — half of a gallop is the back. The body GATHERS (spine rounds,
		# pelvis tucks, hips rise) as the hinds come under, and EXTENDS (back hollows, full
		# stretch) as the fores reach. Scaled by the gallop mix so a walking spine only
		# carries the gentle lateral sway a walking cat has.
		#
		# EVERY TORSO LAYER IS EXPRESSED IN BODY AXES (see `_mul_body`); the NECK COUNTERS
		# route through the LIVE map, because a stabiliser's whole job is to hold the head
		# the animal actually has, and the rest map is wrong by whatever the look layer and
		# the pose have already turned it.
		var body_ph: float = base_ph * TAU
		var ext: float = sin(body_ph)
		var gal: float = mix * _gait_w
		if gal > 0.01:
			_mul_body(_spine, BODY_SIDE, ext * 0.26 * gal)
			_mul_body(_spine2, BODY_SIDE, ext * 0.16 * gal)
			_mul_body(_hip, BODY_SIDE, -ext * 0.22 * gal)
			# (no ad-hoc neck counter here any more — the general head stabiliser below
			# cancels whatever the trunk actually did, which is both the anatomical
			# mechanism and one place instead of three to get wrong.)
		var sway: float = sin(body_ph)
		var walk_w: float = (1.0 - mix) * step_w
		if walk_w > 0.01:
			# THE BODY SNAKES, THE HEAD DOES NOT — the owner's ask, by construction rather
			# than by tuning: the two spine yaws are equal and OPPOSITE, so the bend is
			# fully visible in the trunk and sums to zero at the neck; the pelvis roll is
			# likewise cancelled at the neck, so the face stays level as well as straight.
			var bend: float = sway * 0.055 * walk_w
			_mul_body(_spine, BODY_UP, bend)
			_mul_body(_spine2, BODY_UP, -bend)
			_mul_body(_hip, BODY_FWD, sway * PELVIS_ROLL * walk_w)
			# THE SHOULDER GIRDLE ROLLS AGAINST THE PELVIS. In a walking quadruped the chest
			# and the hips counter-rotate — the girdle settling weight onto the stance
			# foreleg while the pelvis rolls the other way — and this rig had the pelvis half
			# of it and not the chest half, so the back of the animal worked while the front
			# stayed flat. Antiphase and a little smaller, because a cat's thorax is the
			# stiffer end. The head stabiliser cancels it at the neck (5e), so putting roll
			# into the chest cannot tip the face.
			_mul_body(_spine2, BODY_FWD, -sway * CHEST_ROLL * walk_w)
			# THE GIRDLES SWING, AND THE LEGS SOLVE AGAINST THEM (s52). This is the owner's
			# "legs should articulate more to move the body forward": in a real quadruped a
			# slice of every stride is the pelvis rotating about its long axis and the shoulder
			# girdle doing the same at the front, so the socket is already travelling forward
			# when the paw plants and already travelling back at toe-off. The engine had none of
			# it — every limb swung from a socket welded to the torso.
			#
			# PHASE IS BY CONSTRUCTION, NOT BY EAR. A yaw is DIFFERENTIAL: it can only serve a
			# pair whose phases are exactly half a cycle apart, and WALK_OFF gives exactly that
			# twice over — lh 0.00 / rh 0.50 at the back, lf 0.25 / rf 0.75 at the front. A
			# paw's fore-aft path peaks at its own phase 0, so the pelvis wants cos(base_ph)
			# (lh's phase) and the chest wants cos(base_ph + 0.25), which is `-sway`. Getting
			# this wrong by half a cycle would drive the socket AWAY from the planting paw and
			# COST stride rather than buy it, so it is derived here rather than fitted — and the
			# budget it earns is measured off the skeleton in `_prep_ik`, not asserted.
			#
			# Each is CANCELLED one joint along, so the girdle moves and the animal above it
			# does not: the pelvis's yaw comes back out at Spine01 (its child) and the chest's
			# at the neck. Without that the whole trunk and the head yaw with the hips, which
			# is a fish, not a cat.
			var pelv: float = _pelv_sign * PELVIS_YAW * walk_w \
				* cos(TAU * (base_ph + float(WALK_OFF["lh"])))
			_mul_body(_hip, BODY_UP, pelv)
			_mul_body(_spine, BODY_UP, -pelv)
			var chest: float = _chest_sign * CHEST_YAW * walk_w \
				* cos(TAU * (base_ph + float(WALK_OFF["lf"])))
			_mul_body(_spine2, BODY_UP, chest)
			# ...and the chest's cancel goes through the LIVE map, not the rest map. At the
			# 0.055 rad of the spine bend above, a rest-basis cancel is close enough; at
			# CHEST_YAW's 0.16 the residual is three times larger, and on a torso far from rest
			# it is not even a yaw — the CARRY pose measured 4.8 deg of head ROLL out of a
			# commanded pure yaw, which is the same trap `_mul_body_live` was written for when
			# the look banked a sitting cat's face by 22 degrees.
			_mul_body_live(_neck, BODY_UP, -chest)
		# WEIGHT — ONE whole-body vertical, phase-locked to the footfall (the pelvis rides
		# `base_ph`, the same variable the paws are planted from, so it CANNOT drift off
		# the steps). Two bobs per cycle, minima 0.125 after each HIND plant — the
		# DOWN/recoil beat. `abs(sin)` forms are gone: abs() doubles the frequency and puts
		# a corner at every zero. Amplitude grows walk -> gallop, with a small extra bounce
		# through the trot band for the diagonal-pair spring a trot is.
		# Walk amplitude is the spec's ±2% of shoulder height (~±6 mm) — bigger reads well
		# but pushes the straight-bound left hind past its reach at every bob peak, and the
		# clamp pops the knee. The out-of-reach vertical give below scales with the same mix.
		# "Very slightly bouncy like a real cat" — the walk end was the spec's +-2% of
		# shoulder height (~6 mm each way) and read as a glide. 18 mm is nearer a real cat's
		# step, and still small enough not to push the straight-bound left hind past its
		# reach at the bob peaks, which is what pops that knee.
		# 0.028 AT A WALK — the owner's "little bounces". The same 18 mm that read as a
		# vibration at 4.7 Hz reads as a bounce at 2.9, because a bob is judged by its
		# rate as much as its size; the slower cycle is what makes a bigger one legible
		# instead of buzzy. Two per stride, minima on the contacts, so it is the body
		# arcing over each planted foot rather than a hover.
		# 0.038 AT A WALK (s52). The same argument one turn further on: the cadence drops
		# 2.89 -> 2.47 strides a second with the longer stride, and a bob is judged by its
		# RATE as much as its size, so the amplitude that read as a bounce at 2.9 reads as a
		# glide at 2.5 unless it grows with the step. Measured at the write: see the s52
		# DEVLOG table.
		# 0.014 AT A WALK (s53), and the argument above was measuring the wrong thing. Every
		# session judged this number against how the TRUNK reads and none against how the FEET
		# read — but three of the four chains sit at 98-100% of their reach cap, so a hip that
		# rises 38 mm drags a PLANTED PAW up with it, and the planted paw is the thing the
		# owner is reporting. See BOB_WALK for the grid. The gallop end is untouched: its
		# stance is 20% of a much longer cycle and no instrument here can see it yet.
		# ...AND THE RAMP BETWEEN THE TWO ENDS IS HELD OFF UNTIL THE GALLOP (s54). Both
		# endpoints are unchanged and both were measured; the INTERPOLATION between them never
		# was, because until this session `mix` was 0.00 at the shipped walk and 0.06 at the
		# shipped trot — every instrument that has ever looked at this line was looking at the
		# walk end of it. Re-siting the speed bands on the animal's real transitions (see
		# WALK_V) puts the shipped walk at mix 0.17 and the shipped trot at 0.72, and a straight
		# lerp then quietly hands the WALK a 22.6 mm bob and 24.7 mm of reach-give. Measured
		# cost of that: right hind planted-paw travel 7.6 -> 18.1 mm and its in-stance slide
		# 0.60 -> 6.49 mm/frame — which is exactly the 38 mm-bob regression BOB_WALK's own grid
		# documents, arriving through the back door of a constant nobody edited.
		# `maxf(mix*2-1, 0)` holds both at their measured walk values across the whole walk-and-
		# trot band and ramps them into the gallop, which is the only place the larger numbers
		# were ever wanted and the one band no instrument here can see.
		var gal_ramp: float = maxf(mix * 2.0 - 1.0, 0.0)
		var bob_amp: float = lerpf(BOB_WALK, 0.045, gal_ramp)
		bob_amp += maxf(1.0 - absf(mix - 0.5) * 2.0, 0.0) * 0.010
		var bob_min_ph: float = lerpf(0.125, 0.15, mix)
		_reach_give = 0.018 + 0.04 * gal_ramp
		# ...AND THE CROUCH, which is the OTHER half of the s53 foot fix and rides this same
		# channel. A chain of reach c0 covering `sweep` of ground has to give somewhere; s52
		# gave at the PAW, and the paw is the one part of the animal that must not move while
		# it is on the ground. `_body_drop` is the same triangle spent at the BODY — the animal
		# settles onto its legs as the gait engages and stands back up when it stops, which is
		# what a quadruped at full extension actually does. DERIVED from the sweep in use, so a
		# shorter-strided pose (the stalk's `sweep_k`) stands taller without a second constant,
		# and eased by `step_w` like the bob so there is no step at the engage.
		var crouch: float = _body_drop(sweep_env * sweep_k * reach_k) * CROUCH_K
		_out_hip += Vector3(0,
			(0.5 - 0.5 * cos((base_ph - bob_min_ph) * 2.0 * TAU)) * bob_amp * step_w
				- crouch * step_w, 0)
		for limb_key in WALK_OFF:
			# Offsets ease walk -> trot -> gallop so the footfall order re-times
			# continuously as the animal changes pace.
			var off: float
			if mix < 0.5:
				off = lerpf(WALK_OFF[limb_key], TROT_OFF[limb_key], mix * 2.0)
			else:
				off = lerpf(TROT_OFF[limb_key], GALLOP_OFF[limb_key], mix * 2.0 - 1.0)
			off = lerpf(off, TROT_OFF[limb_key], turning)
			var ph: float = fposmod(base_ph + off, 1.0)
			# OVERLAPPING ACTION: the knee, then the paw, then the toe are read a little LATER
			# in the cycle than the shoulder, so the limb unfolds down its own length instead
			# of every joint hitting its key on the same frame. It is the cheapest thing that
			# separates a live limb from a hinged stick.
			var ph_t: float = fposmod(ph - DRAG, 1.0)
			var fore: bool = limb_key.ends_with("f")
			var w: Array = _cyc_eval(CYC_WALK_FORE if fore else CYC_WALK_HIND, ph)
			var g: Array = _cyc_eval(CYC_GAL_FORE if fore else CYC_GAL_HIND, ph)
			var wt: Array = _cyc_eval(CYC_WALK_FORE if fore else CYC_WALK_HIND, ph_t)
			var gt: Array = _cyc_eval(CYC_GAL_FORE if fore else CYC_GAL_HIND, ph_t)
			# The tables now shape the parts of the limb that ARE angles — the scapula's travel
			# and the paw's roll through the plant. Where the paw itself goes is a path, below.
			var reach: float = lerpf(w[0], g[0], mix) * amp * reach_k
			var paw: float = lerpf(wt[2], gt[2], mix) * amp
			var L: Dictionary = _limb[limb_key]
			# THE LEG FOLLOWS A PATH, NOT AN ANGLE (see `_foot_path` / `_solve_leg`). Stated in
			# METRES in the body's own frame and handed to both sides identically, which is why
			# a rig whose left femur is four times its right draws two matching legs; and the
			# stance leg tracks backward at exactly the speed the body goes forward, which is
			# what plants it. The duty factor is the same 0.62-walking / 0.38-galloping the
			# keyed tables carried, and it is what stops a gait reading as clockwork.
			# ONE SWEEP FOR ALL FOUR PAWS. It is set by the SHORTEST limb, because on a rigid
			# body every paw must cover the same ground per cycle or the animal tears itself
			# apart — and because capping each limb at its own envelope is what put the limp
			# back: the two hinds have different geometry, so per-limb clamping truncated them
			# by different amounts and the hind reach ratio went straight back to 1.23.
			# PAW LIFT — and this is most of the owner's "his knees dont bend, legs move
			# like peg legs". A leg only visibly FOLDS when the swing target is high
			# enough to force it to: at 34 mm on a 0.66 m cat the paw skimmed the deck and
			# the chain stayed nearly straight all the way round, which is a peg leg
			# however smoothly it swings. A walking cat picks its paw up roughly a fifth
			# of its leg length. 58 mm fore is that, and the IK then has to fold the elbow
			# and stifle to reach it — the fold is a CONSEQUENCE of the path, which is the
			# same principle that made foot-lock fall out of the stance definition.
			# 0.072 AT A WALK, RAISED BECAUSE THERE IS NOW TIME TO SEE IT. At 4.7 strides a
			# second a 58 mm lift was a blur; at 2.9 the swing is a third longer in
			# wall-clock and a deliberate step reads as deliberate. It also deepens the
			# fold the honest way — through the PATH the IK has to reach, which is the
			# lesson the s49 revert paid for (a fold authored on top of the solution is a
			# flick, not a bend).
			# 0.085 AT A WALK (s52), up again for the same reason and by the same route:
			# the stride is a third longer in wall-clock than at s51, so the paw can lift
			# further without the swing RATE rising. It is the honest lever for "articulate
			# more" — a higher arc is ground the IK must FOLD the elbow and stifle to reach,
			# where an authored fold on top of the solve is the flick s49 was reverted for.
			var lift_m: float = lerpf(0.085, 0.125, mix) * (1.0 if fore else 0.88) * lift_k
			var sweep_m: float = sweep_env * reach_k * sweep_k
			# The stance is FLAT (s53) — the headroom this limb's triangle needs at this
			# sweep was taken out of the body above, not out of the planted paw.
			var pth: Vector2 = _foot_path(ph, duty, sweep_m, lift_m)
			# +12 mm of stance width per side (s45c, "wider"): the rest anchors carry the
			# bind pose's narrow track, and widening at the TARGET keeps foot-lock exact —
			# the paw plants and stays planted, just a whisker further out from the
			# centreline, which is what keeps a slower stride from reading tightrope.
			var w0: Vector3 = _ik.get(limb_key, {}).get("W0", Vector3.ZERO) as Vector3
			var target: Vector3 = w0 + BODY_FWD * (pth.x - _centre_off(limb_key)) \
				+ BODY_UP * pth.y + BODY_SIDE * signf(w0.z) * 0.012
			# THE SHOULDER BLADE WRITES BEFORE THE SOLVE, because the solve compensates
			# through the LIVE parent chain and the blade IS the fore leg's parent: written
			# after (as it was), its swing rode on top of solved angles and carried the paw
			# off its planted target by the whole scapular travel — measured as fore lifts
			# doubling and a 67 mm/frame phantom skate the moment the parent reads went
			# live. Written first, the scapula rides up over the spine at the top of the
			# reach — the signature cat shoulder — while the paw stays exactly planted,
			# which is the anatomical truth of a floating shoulder girdle.
			# ...AND IT LEADS THE LEG. Overlapping action runs proximal-to-distal, so the
			# knee and paw are already read a DRAG LATER than the shoulder (`ph_t`); the
			# scapula is the most proximal segment of the chain and was being read at the
			# same instant as the humerus — the one place in the limb where nothing was
			# offset from anything. Reading it a DRAG EARLIER completes the sequence: blade,
			# shoulder, knee, paw, toe. That ripple down the limb is what separates a walk
			# from four levers on one crank.
			var ph_lead: float = fposmod(ph + DRAG, 1.0)
			var reach_lead: float = lerpf(
				float(_cyc_eval(CYC_WALK_FORE if fore else CYC_WALK_HIND, ph_lead)[0]),
				float(_cyc_eval(CYC_GAL_FORE if fore else CYC_GAL_HIND, ph_lead)[0]),
				mix) * amp * reach_k
			_mul(L["blade"], Quaternion(_hinge_of(L["blade"]), reach_lead * BLADE_TRAVEL))
			var sol: Array = _solve_leg(limb_key, target)
			# SLEW-LIMITED, because two of these chains rest ON the two-bone model's
			# singularity (the load report above prints the triangles: rf rests at 99.7% of
			# its clamped reach, rh BEYOND it — the dead-straight bind) and there
			# d(knee)/d(target) is unbounded: a smoothly moving paw target snapped the calf
			# up to 1.8 rad in one frame at the clamp boundary. The limiter trades those
			# pops for a few frames of millimetre-scale paw deviation at the extremes; in
			# the well-conditioned range legit gait velocities pass untouched. The ceiling
			# is a measured trade against THIS rig's legit motion — short shanks work their
			# knees at ~0.31 rad/frame in an ordinary walk (dβ/dc scales with 1/(a·b)).
			# Whatever the ceiling, the singular event itself surfaces as a brief ~75 mm
			# paw excursion once per few seconds (measured at ceilings 20 and 26 alike):
			# that residue belongs to the two chains that REST on the model's singularity
			# (see the triangle report above and docs/CAT_RIG_CEILING.md §3) and only a
			# re-rig removes it. The ceiling is set where healthy walk strides pass clean.
			var slew: float = (20.0 + 32.0 * mix) * dt
			var sp: Array = _sol_prev.get(limb_key, sol)
			sol[0] = clampf(float(sol[0]), float(sp[0]) - slew, float(sp[0]) + slew)
			sol[1] = clampf(float(sol[1]), float(sp[1]) - slew, float(sp[1]) + slew)
			_sol_prev[limb_key] = [float(sol[0]), float(sol[1])]
			# Eased in by the gait weight so a cat coming to a stop hands its legs back to the
			# blended pose instead of dropping them.
			# (The tail's per-limb de-drag cancel that lived here is gone: the tail is now
			# posed ABSOLUTELY against the frame's live parent chain in 5d, which decouples
			# it from the right hind leg exactly rather than approximately.)
			_mul(L["prox"], Quaternion(_hinge_of(L["prox"]), float(sol[0]) * step_w))
			_mul(L["dist"], Quaternion(_hinge_of(L["dist"]), float(sol[1]) * step_w))
			# THE SWING FOLD — the authored knee, and the actual cure for "legs move like
			# peg legs". The IK only folds a joint as much as reaching the path REQUIRES,
			# and on chains whose rest reach is ~97-100% of the bones' total length (this
			# rig's, by the load report) a 58 mm lift needs only a shallow flex — smooth,
			# planted, and dead straight to the eye. A real cat's stifle cycles ~37 deg and
			# its elbow folds hard as the paw comes through; that fold is a STYLE, not a
			# necessity, so it has to be authored, not hoped for from the solver.
			#
			# Windowed strictly to the SWING (sin over swing progress, zero at toe-off and
			# again at the plant), so during stance the joint carries exactly the solved
			# angle and foot-lock stays exact to the millimetre. Mid-swing the paw is
			# airborne — pulling it up under the body with a folded knee is precisely what
			# the reference footage shows. Direction is each chain's own measured fold
			# sign; magnitude eases off toward the gallop, whose 125 mm lift already folds
			# the legs for real.
			if ph > duty:
				# BACK TO THE SHALLOWER FOLD, AND THE PAW CURL IS GONE. The s49 pass took the
				# fold to 0.62/0.52 and added a toe-off paw curl, and the owner's verdict was
				# that the legs "flap up unnaturally" — worse than what it replaced. Both
				# terms were authored ON TOP of a solve that had already put the paw where
				# the path wanted it, so they did not deepen a bend, they ADDED a second
				# motion to a limb that was already articulating: the visible result is a
				# flick, not a fold. A deeper knee has to come from the PATH (a higher swing
				# arc the IK must fold to reach), not from a layer bolted onto the solution —
				# that is the same lesson `_foot_path`'s header records about authoring where
				# the paw goes rather than what the joints do. Filed for the next pass.
				# ...AND IT RIDES `_swing_bump`, NOT `sin(PI*s)` (s53). The sine is zero at the
				# plant and moving at its maximum rate there, so this layer unwound 0.42 rad of
				# elbow in the last frame or two before contact — about 17 mm of paw on a
				# 0.145 m forearm, arriving downward at full speed. Measured: it was the LARGEST
				# single contributor to the drawn touchdown step once the path itself was made
				# continuous (lf 44.1 mm with the sine, against a commanded 5.1).
				# ...AND IT IS 0.18/0.15 NOW, NOT 0.42/0.36 (s54). See FOLD_FORE: the elbow was
				# sitting on ROM_DIST_FOLD for three to four consecutive frames of every swing,
				# so the surplus drew as a flat top and a touchdown penalty rather than as a
				# deeper bend. The visible fold is unchanged and the plant is quiet.
				var s_sw: float = (ph - duty) / maxf(1.0 - duty, 1e-4)
				var fold_amp: float = (FOLD_FORE if fore else FOLD_HIND) * lerpf(1.0, 0.45, mix)
				var kn: float = float(_ik.get(limb_key, {}).get("knee", 1.0))
				_mul(L["dist"], Quaternion(_hinge_of(L["dist"]),
					kn * _swing_bump(s_sw, FOLD_APEX) * fold_amp * step_w))
			_mul(L["paw"], Quaternion(_hinge_of(L["paw"]), paw))
			# THE TOE. A paw that never rolls through the plant is the other half of the toy
			# horse: contact is heel-ish down, roll forward, push off the toes.
			#
			# ...AND IT IS READ A SECOND DRAG LATER (s54). The file's stated overlapping-action
			# sequence is blade, shoulder, knee, paw, TOE — blade at `ph + DRAG`, shoulder at
			# `ph`, knee/paw at `ph - DRAG` — and the toe was reading at the SAME instant as the
			# carpus, so the ripple down the limb stopped one segment short and the last joint
			# in the chain moved in lockstep with its parent. One more table read; the toe's own
			# amplitude is 6 deg of ROM_TOE's 22.92 and its worst step 24% of the limiter, so
			# there is no rate or range cost to pay for it.
			if int(L["toe"]) >= 0:
				var ph_t2: float = fposmod(ph - DRAG * 2.0, 1.0)
				var paw_toe: float = lerpf(
					float(_cyc_eval(CYC_WALK_FORE if fore else CYC_WALK_HIND, ph_t2)[2]),
					float(_cyc_eval(CYC_GAL_FORE if fore else CYC_GAL_HIND, ph_t2)[2]),
					mix) * amp
				_mul(L["toe"], Quaternion(_hinge_of(L["toe"]), paw_toe * 0.5))
	# 5. Idle life on top of ANY pose: slow breath always; it is what stops a still pose
	# reading as a freeze-frame. Softer while asleep.
	#
	# THE BREATH USED TO TURN THE CAT'S HEAD, and this is the owner's "it looks to the side
	# when walking". It was applied about the spine's local Z at 0.032 rad, and local Z on
	# this rig is 87% YAW (tests/CatYawDiag) — so the face swung +/-2.6 deg off the line of
	# travel every few seconds, in every state, for as long as the cat has existed.
	# tests/CatFilm measured the live walk at +3.4 deg mean and +6.4 worst, never once
	# crossing to the other side. Breathing is the CHEST rising: a pitch, at the ribs,
	# cancelled at the neck so the head is not carried along with it.
	#
	# `t` IS SIM TIME, NOT THE WALL CLOCK. This line read Time.get_ticks_msec() for every
	# session the rig has existed, so under AiBudget frame-summing (and in any harness that
	# runs faster or slower than real time) the breath, the tail, the strokes, the shake and
	# the chatter all ran on a clock the rest of the animal was not on — jumping furthest
	# exactly when the animal was ticked least. Distance-driven layers froze, wall-clocked
	# ones twitched: two clocks, one body.
	var t: float = _anim_t
	var slept: bool = _target == "sleep"
	var breath: float = sin(t * (0.8 if slept else 1.6)) * (0.016 if slept else 0.022)
	_mul_body(_spine, BODY_SIDE, breath)
	_mul_body(_spine2, BODY_SIDE, breath * 0.55)
	_mul_body(_neck, BODY_SIDE, -breath * 1.35)
	# THE WASH FADES, IT DOES NOT VANISH — and this is the owner's "head glitches around a
	# good bit after licking, it visibly shakes side to side".
	#
	# Every stroke below used to be gated on `_GROOM_POSE.has(_target)` alone, which is a
	# BOOLEAN on the pose NAME. So the frame a wash ended, the whole layer disappeared at
	# once — and these are not small oscillations, they are large DC offsets: the flank wash
	# holds the neck 0.55 rad (31 degrees) round toward the shoulder, the chest wash holds it
	# -0.42. Dropping 31 degrees of neck yaw in a single frame is a step discontinuity, and
	# the head-rate ceiling then has no choice but to smear it across ten frames at its
	# 189 deg/s limit, which is precisely what a visible side-to-side shake IS. The pose
	# itself was crossfading politely the whole time; the layer riding on top was not.
	#
	# So the layer gets a WEIGHT, eased in and out like every other reaction in this file
	# (pet, delight, wiggle, shake) — the offsets ride it to zero over about a third of a
	# second, in the same direction they came from, and there is no step left to smear.
	var groom_want: float = 1.0 if _GROOM_POSE.has(_target) else 0.0
	_groom_w = lerpf(_groom_w, groom_want, 1.0 - exp(-4.5 * dt))
	if _groom_w > 0.008:
		var gw: float = _groom_w
		match _groom_style:
			1:
				# FLANK. The head goes right round to the shoulder and the strokes are long
				# and slow; the trunk curls toward the side being worked on.
				var s1: float = sin(t * 1.6)
				_mul_body(_neck, BODY_UP, (0.55 + s1 * 0.16) * gw)
				_mul_body(_head, BODY_UP, (0.30) * gw)
				_mul_body(_head, BODY_SIDE, (-0.22 + s1 * 0.14) * gw)
				_mul_body(_spine2, BODY_UP, (0.16) * gw)
			2:
				# CHEST. Head straight down between the forelegs, small fast strokes, and the
				# most hunched of the set.
				var s2: float = sin(t * 3.3)
				_mul_body(_neck, BODY_SIDE, (-0.42 + s2 * 0.10) * gw)
				_mul_body(_head, BODY_SIDE, (-0.26 + s2 * 0.12) * gw)
				_mul_body(_spine2, BODY_SIDE, (-0.12) * gw)
			3:
				# EAR SCRATCH. The POSTURE is authored — `groom_scratch` takes the left hind
				# out of the bake's plant and holds it up and abducted (see `_build_poses`,
				# which also records how far short of the ear this rig's hip can carry it).
				# This is the WORK: the fast small paw arc, and the head tilted into it.
				#
				# 7 Hz (44 rad/s), which is the animal's own rate for this action and most of
				# why it reads as a scratch rather than a wave. The low end of the 6-9 Hz band
				# on purpose: `_anim_t` advances by AiBudget's SUMMED delta, capped at 0.15 s,
				# so a faster sine aliases into noise on exactly the frames the animal is
				# thought about least.
				var s3: float = sin(t * 44.0)
				var L3: Dictionary = _limb["lh"]
				# THE HOCK DOES THE WORK AND THE THIGH BARELY MOVES — a scratching cat flicks
				# from the stifle down. The amplitudes are sized against the headroom
				# `groom_scratch` deliberately leaves under the ROM clamp (thigh -0.48 of 0.62,
				# stifle 0.92 of 1.35, hock 0.22 of 0.50), so the peaks land INSIDE it: a
				# clamped stroke flattens one half of its own arc and draws as a stutter with
				# no visible cause. 48 mm of paw travel peak-to-peak, which is the few
				# centimetres the real action covers.
				_mul(L3["prox"], Quaternion(_hinge_of(L3["prox"]), (s3 * 0.05) * gw))
				_mul(L3["dist"], Quaternion(_hinge_of(L3["dist"]), (s3 * 0.18) * gw))
				# Overlapping action down the limb, the gait's DRAG idiom: the hock and then
				# the toes are read a little later in the cycle than the stifle.
				_mul(L3["paw"], Quaternion(_hinge_of(L3["paw"]), (sin(t * 44.0 - 0.55) * 0.13) * gw))
				_mul(L3["toe"], Quaternion(_hinge_of(L3["toe"]), (sin(t * 44.0 - 0.95) * 0.09) * gw))
				# THE HEAD TILTS INTO THE PAW, and on this rig the tilt carries most of the
				# read — the hip clamp stops the paw 0.61 m short of the ear. A ROLL toward the
				# scratching side, a small drop, and a whisker of yaw the same way so the ear
				# is presented rather than merely lowered; plus the paw's own rhythm at a sixth
				# of its amplitude, which is what "the head barely moves relative to the paw"
				# looks like from outside.
				#
				# LIVE map, neck before head: this torso is both pitched and rolled, and the
				# rest map turns a commanded roll into yaw on a sitting cat.
				_mul_body_live(_neck, BODY_FWD, (_scratch_side * 0.15) * gw)
				_mul_body_live(_neck, BODY_SIDE, (-0.10) * gw)
				_mul_body_live(_head, BODY_FWD, (_scratch_side * (0.25 + s3 * 0.04)) * gw)
				_mul_body_live(_head, BODY_UP, (_scratch_side * -0.10) * gw)
			_:
				# PAW. The classic: forepaw up to the lowered muzzle, short quick strokes.
				# BODY pitch for the nods and the measured hinge for the forearm — this
				# branch was the last raw-local-axis user in the file, sitting beside two
				# wash styles already converted, and on these bones a raw X is not a nod.
				var stroke: float = sin(t * 2.9)
				_mul_body(_neck, BODY_SIDE, (-stroke * 0.13) * gw)
				_mul_body(_head, BODY_SIDE, (-stroke * 0.16) * gw)
				var L2: Dictionary = _limb["lf"]
				_mul(L2["dist"], Quaternion(_hinge_of(L2["dist"]), (stroke * 0.10) * gw))
	# 5b2. THE SHAKE — a fast damped ripple that runs from the shoulders back, which is what a
	# cat does on waking, after rain, and after anything undignified. Rolling the segments in
	# sequence rather than together is the whole effect; in phase it is a wobble, out of phase
	# it is a shake.
	_shake_w = maxf(0.0, _shake_w - dt * 1.4)
	if _shake_w > 0.01:
		var sh: float = _shake_w * _shake_w        # dies away rather than stopping dead
		_mul_body(_neck, BODY_FWD, sin(t * 30.0) * 0.30 * sh)
		_mul_body(_spine2, BODY_FWD, sin(t * 30.0 - 0.7) * 0.24 * sh)
		_mul_body(_spine, BODY_FWD, sin(t * 30.0 - 1.4) * 0.20 * sh)
		_mul_body(_hip, BODY_FWD, sin(t * 30.0 - 2.1) * 0.16 * sh)
	# 5c. The chatter, if a bird is being watched and cannot be had.
	_chat_w = maxf(0.0, _chat_w - dt * 1.2)
	if _chat_w > 0.01:
		_mul_body(_head, BODY_SIDE, sin(t * 34.0) * 0.042 * _chat_w)
		_mul_body(_head, BODY_UP, sin(t * 29.0) * 0.016 * _chat_w)
	# 5f. THE REACTIONS THAT USED TO ROTATE THE WHOLE ANIMAL.
	#
	# THIRTEEN separate lines in ship_cat.gd wrote `_body.rotation` or `_body.position` —
	# the pet lean, the fed wiggle, the two grooming sways, the displacement wash, the
	# hunt's tread waggle, the play waggle, the seated weight-shift, the slope lean. Every
	# one of them rotated the ENTIRE CAT about its own origin, which is why the owner said
	# "the game rotates the entire cat instead of moving a limb" and, of the pet, "the
	# whole model tilts to the side instead of the cat reacting happy". Measured before
	# this change (tests/CatJointProbe): a constant 4.67 degrees of whole-body tilt in
	# every state sampled, and the pet leaned the animal 12.6 degrees off vertical with
	# its paws still welded flat to the deck — a cat on a hinge, not a cat.
	#
	# Everything below does the same job through the SKELETON, where a real animal does
	# it: the back arches, the pelvis rolls, the hips waggle, the chest pitches into a
	# slope. The paws stay where the IK put them, because the legs solve against these
	# sockets rather than being carried bodily sideways with them.
	#
	# Placed before the tail, which poses itself absolutely against its live parent chain
	# and must therefore see the final torso.
	_pet_w = maxf(0.0, _pet_w - dt * 1.1)
	if _pet_w > 0.01:
		# THE ARCH. A cat being stroked lifts its back INTO the hand and drops the pelvis
		# a little — the classic elevator-butt. The head press is applied further down,
		# after the stabiliser, so it survives as a deliberate motion instead of being
		# cancelled as trunk noise.
		var pw: float = _pet_w * _pet_w
		_mul_body(_spine, BODY_SIDE, -0.11 * pw)
		_mul_body(_spine2, BODY_SIDE, -0.07 * pw)
		_mul_body(_hip, BODY_SIDE, 0.06 * pw)
		_out_hip += Vector3(0, -0.010 * pw, 0)
	_delight_w = maxf(0.0, _delight_w - dt * 0.8)
	if _delight_w > 0.01:
		# Fed, and briefly very pleased about it: a quick shimmy through the trunk.
		var dq: float = sin(t * 15.0) * 0.055 * _delight_w
		_mul_body(_hip, BODY_UP, dq)
		_mul_body(_spine, BODY_UP, -dq * 0.6)
	_wiggle_w = maxf(0.0, _wiggle_w - dt * 2.0)
	if _wiggle_w > 0.01:
		# THE TREAD — the plié before a pounce. Hind feet paddling and the rear waggling,
		# which is a PELVIS motion; done at the node it swung the shoulders and the head
		# with it, which is precisely the wrong end of the cat.
		var wg: float = sin(t * 19.0) * 0.11 * _wiggle_w
		_mul_body(_hip, BODY_UP, wg)
		_mul_body(_spine, BODY_UP, -wg * 0.45)
		_out_hip += Vector3(0, (0.5 - 0.5 * cos(t * 38.0)) * 0.010 * _wiggle_w, 0)
	_shift_s = lerpf(_shift_s, _shift_t2, 1.0 - exp(-2.5 * dt))
	if absf(_shift_s) > 0.004:
		# The settled cat re-planting its weight: a pelvis roll, not a turntable yaw.
		_mul_body(_hip, BODY_FWD, _shift_s * 0.055)
		_mul_body(_spine, BODY_FWD, _shift_s * 0.028)
	_slope_s = lerpf(_slope_s, _slope_t, 1.0 - exp(-5.0 * dt))
	if absf(_slope_s) > 0.002:
		# THE SLOPE. Leaning the whole node pitched the animal as a plank and left its
		# paws intersecting the ramp; pitching the trunk lets the four legs solve to the
		# ground they are actually standing on.
		_mul_body(_hip, BODY_SIDE, -_slope_s * 0.34)
		_mul_body(_spine, BODY_SIDE, -_slope_s * 0.20)
	# 5d. THE TAIL — the loudest thing a cat says and the only channel this body has for it.
	# There is no facial rig, the ears do not move and the pupils are painted on, so carriage
	# and sway carry the entire signal: up and quivering to greet you, out and arcing slowly
	# while it walks, flat and flicking while it hunts, still while it sleeps.
	#
	# Driven as a SPRING against an ABSOLUTE body-space target, late in the frame so the
	# parent chain is final:
	#   * the DRIVER (carriage + its own sway loop + the walk's hip sway, lagged + a
	#     counter-swing against the body's turn) says where the tail wants to be;
	#   * an underdamped second-order spring says where it IS — so every change lags like
	#     mass, overshoots ~15% on stops and settles, instead of snapping between carriages;
	#   * the bone is then posed by solving its LOCAL rotation against the frame's LIVE
	#     parent basis (_live_basis), which decouples it from the right hind leg EXACTLY —
	#     the old approach applied the gait to the thigh and then subtracted an
	#     approximation of it from the tail through the rest basis, and the residue was the
	#     once-per-stride twitch.
	# Semi-implicit Euler, stable at AiBudget's 0.15 s worst case (K*dt^2 = 1.24 < 2).
	if _tail >= 0:
		var te: float = 1.0 - exp(-3.5 * dt)
		_tail_up = lerpf(_tail_up, _tail_up_t, te)
		_tail_sway = lerpf(_tail_sway, _tail_sway_t, te)
		_tail_rate = lerpf(_tail_rate, _tail_rate_t, te)
		var yaw_tgt: float = sin(t * _tail_rate) * _tail_sway * TAIL_MAX
		yaw_tgt += sin((_phase - 0.16) * TAU) * 0.30 * TAIL_MAX * _gait_w * (1.0 - mix)
		yaw_tgt += -clampf(_yaw_rate * 0.30, -0.6, 0.6) * TAIL_MAX
		var pitch_tgt: float = -_tail_up * TAIL_MAX
		var ks: float = 55.0
		var cs: float = 7.4
		_tail_yaw_v += ((yaw_tgt - _tail_yaw) * ks - cs * _tail_yaw_v) * dt
		var yaw_raw: float = _tail_yaw + _tail_yaw_v * dt
		_tail_yaw = clampf(yaw_raw, -TAIL_MAX * 1.2, TAIL_MAX * 1.2)
		# A JOINT AT ITS STOP HAS NO VELOCITY LEFT. Without this a hard flick presses the
		# tail against its limit and holds there while the spring slowly wins — a tail
		# stuck out sideways, which is the opposite of a flick.
		if absf(yaw_raw - _tail_yaw) > 1e-6:
			_tail_yaw_v = 0.0
		_tail_pitch_v += ((pitch_tgt - _tail_pitch) * ks - cs * _tail_pitch_v) * dt
		_tail_pitch = clampf(_tail_pitch + _tail_pitch_v * dt, -TAIL_MAX * 1.2, TAIL_MAX * 1.2)
		var p_live: Basis = _live_basis(_sk.get_bone_parent(_tail))
		var g_want: Basis = Basis(BODY_UP, _tail_yaw) * Basis(BODY_SIDE, _tail_pitch) \
			* (_rest_gb.get(_tail, Basis.IDENTITY) as Basis)
		_out[_tail] = (p_live.inverse() * g_want).get_rotation_quaternion().normalized()
		# ...and the same target is kept for the RE-SOLVE at the end of the write, where the
		# parent's clamped, rate-limited value is finally known. See TAIL_MAX_RATE.
		_tail_gwant = g_want.get_rotation_quaternion().normalized()
	# 5e. THE HEAD IS STABILISED AGAINST THE TRUNK — the vestibular reflex, which is most
	# of why a cat's face reads as calm while its body is doing something violent.
	#
	# Every layer above moves the chest: the spine engine pitches it up to 0.26 rad at a
	# gallop, the walk rolls the pelvis, the breath pitches the ribs, the shake ripples
	# the lot. All of that was being INHERITED by the head, which is the owner's "bobs up
	# and down too quick" and half of "his whole body moves unnaturally". Two ad-hoc
	# counters used to sit inside the gait blocks with hand-picked fractions; they could
	# only cancel the terms their own author remembered.
	#
	# This measures what the neck's parent ACTUALLY did this frame — live, composed,
	# including every layer — and gives most of it back. Lagged a couple of frames,
	# because a head that corrects instantly is a gyro, not an animal.
	if _neck >= 0:
		var par_n: int = _sk.get_bone_parent(_neck)
		if par_n >= 0:
			var d: Quaternion = (_live_basis(par_n)
				* (_rest_gb.get(par_n, Basis.IDENTITY) as Basis).inverse()
				).get_rotation_quaternion()
			if d.w < 0.0:
				d = Quaternion(-d.x, -d.y, -d.z, -d.w)
			# Small-angle rotation vector: 2*(x,y,z) is the axis-angle to first order,
			# which is all this needs — the trunk never travels far from rest.
			var rv := Vector3(d.x, d.y, d.z) * 2.0
			# THE FILTER HAS TO TRACK WHAT IT IS CANCELLING. At rate 22 this is a
			# first-order low-pass with a ~3.5 Hz corner, so against a gallop's trunk
			# oscillation it passed less than half the signal through and lagged it 60
			# degrees — a stabiliser that cancels the walk and gives up exactly where the
			# animal needs it most (measured: stab 0.0 -> 704 deg/s of head motion at a
			# run, stab 1.0 -> 554; the missing cancellation was all filter roll-off).
			# Rate 90 tracks to ~14 Hz; the natural head lag now comes from HEAD_STAB
			# being less than one, which is a residual rather than a delay.
			var lag: float = 1.0 - exp(-90.0 * dt)
			_stab_pitch = lerpf(_stab_pitch, rv.dot(BODY_SIDE), lag)
			_stab_roll = lerpf(_stab_roll, rv.dot(BODY_FWD), lag)
			_mul_body_live(_neck, BODY_SIDE, -_stab_pitch * HEAD_STAB)
			_mul_body_live(_neck, BODY_FWD, -_stab_roll * HEAD_STAB)
	# 6. The look, LAST, so attention wins over everything — IN BODY AXES.
	#
	# This layer sat on raw local axes for every session it has existed, two lines from the
	# torso layers that were all moved to _mul_body for exactly this fault. On this rig the
	# raw axes are not approximately right, they are chaos — measured before the fix
	# (tests/CatReviewProbe look_cal): a commanded 34-degree pure yaw drew +4.8 of yaw and
	# 44.5 of ROLL; a commanded 20-degree pitch-up drew 4 degrees of pitch DOWN. Because a
	# companion cat watches the player almost constantly, that skew was live in nearly every
	# frame the owner ever saw — the "looks to the side", as an axis fault, not a gait one.
	# BODY yaw and BODY pitch cannot leak roll, on this rig or the next one.
	# A SACCADE HAS A SPEED LIMIT. The ease alone does not give one: an exponential at
	# rate 14 covers 21% of the gap in a 60 Hz frame, so a glance re-targeting by a radian
	# moved the head 12 degrees in one frame — 720 deg/s. Measured on the pre-fix animal
	# (tests/CatJointProbe): head angular speed p99 of 631 deg/s while SITTING and 673 at
	# a run. That is the owner's "his head shakes back and forth way too fast". A real cat
	# turns its head fast, and there is a ceiling: this one is brisk (a 90 degree glance
	# in a third of a second) and cannot whip.
	# THE CAP IS ON WHAT IS APPLIED, NOT ON THE TARGET — and that distinction was worth
	# 400 deg/s. Rate-limiting the target angle while a separate WEIGHT eased in at rate
	# 10 left the product free to move at (angle x weight-rate): a glance firing at a full
	# radian scaled that radian on over a tenth of a second, so the drawn head still whipped
	# at 600 deg/s with a perfectly well-behaved cap sitting right above it. Limiting the
	# product is the only formulation that bounds what the eye sees.
	_look_w = maxf(0.0, _look_w - dt * 1.5)
	var want_y: float = _look_yaw * _look_w
	var want_p: float = _look_pitch * _look_w
	var lke: float = 1.0 - exp(-9.0 * dt)
	var cap: float = LOOK_MAX_RATE * dt
	_look_yaw_s += clampf(lerpf(_look_yaw_s, want_y, lke) - _look_yaw_s, -cap, cap)
	_look_pitch_s += clampf(lerpf(_look_pitch_s, want_p, lke) - _look_pitch_s, -cap, cap)
	if absf(_look_yaw_s) + absf(_look_pitch_s) > 0.004 and _target != "sleep":
		# LIVE mapping, neck before head: the head's live frame then includes the neck's
		# just-written turn, so the two joints chain like a real neck instead of both
		# guessing from rest — and the map stays true on a sitting torso, where the rest
		# map measured 22 deg of roll on a pure yaw.
		#
		# THE PITCH AXIS IS THE YAWED TRANSVERSE — elevation in the GAZE plane. Pitching
		# about the body's own transverse while the head is yawed 40 deg to a mark banks
		# the face by sin(yaw) * pitch (measured 4.7 deg on the walking look) — the
		# spherical-coordinate order matters: yaw about up, then pitch about the axis the
		# yaw just carried the ears onto.
		var yn: float = _look_yaw_s * 0.55
		var yh: float = _look_yaw_s * 0.45
		var pt: float = _look_pitch_s * 0.5
		_mul_body_live(_neck, BODY_UP, yn)
		_mul_body_live(_neck, Basis(BODY_UP, yn) * BODY_SIDE, pt)
		_mul_body_live(_head, BODY_UP, yh)
		_mul_body_live(_head, Basis(BODY_UP, yn + yh) * BODY_SIDE, pt)
	# THE HEAD PRESS, after the stabiliser on purpose: a cat pushing its skull up into a
	# hand is a deliberate act, and the stabiliser's whole job is to cancel motion the
	# animal did not intend. Nose up, and a small roll — the head-tilt everyone who has
	# ever scratched a cat's cheek has seen.
	if _pet_w > 0.01:
		var ph: float = _pet_w * _pet_w
		_mul_body_live(_neck, BODY_SIDE, 0.17 * ph)
		_mul_body_live(_head, BODY_SIDE, 0.13 * ph)
		_mul_body_live(_head, BODY_FWD, 0.11 * ph)
	# 7. Write the skeleton, once — the blended state where no layer touched a bone, the
	# composed frame where one did.
	# THE ANATOMY CHOKE POINT. Every layer in this file — the pose blend, the gait solve,
	# the strokes, the look, the shake, anything a future session adds — passes through
	# here, so no writer can produce a joint the animal does not have. Cheap: a quaternion
	# decomposition on ~16 limb bones, and only the ones actually out of range rebuild.
	_fin.clear()
	for i in _cur_q:
		var q_out: Quaternion = _out.get(i, _cur_q[i])
		if _rom.has(i):
			q_out = _clamp_joint(i, q_out)
			# THE LIMB RATE CEILING (see LIMB_MAX_RATE) — after the ROM clamp, because the
			# clamp's rebuild is itself one of the fast terms it has to bound, and because a
			# rate limit applied before a clamp is a rate limit on something that is not what
			# gets drawn. Scaled by dt so a summed AiBudget think and a 60 Hz frame agree.
			var pv = _limb_prev.get(i)
			if pv != null:
				var st: float = (pv as Quaternion).angle_to(q_out)
				var cap_l: float = LIMB_MAX_RATE * dt
				if st > cap_l and st > 1e-5:
					q_out = (pv as Quaternion).slerp(q_out, cap_l / st).normalized()
			_limb_prev[i] = q_out
		# THE HEAD RATE CEILING — the sum-of-layers cap (see HEAD_MAX_RATE), applied to the
		# head's SKELETON-SPACE orientation, parent chain included. A local-bone cap was
		# tried first and bounded nothing: the fast paths live upstream (the look's
		# neck-share, the stabiliser, the strokes — all NECK writers), and the fastest of
		# all is the look-weight RAMP — a glance re-acquired at invisible weight snaps its
		# yaw silently (correct) and then the weight eases 0 -> 0.85 in ~150 ms, sweeping
		# the drawn head through weight x target at 400-800 deg/s. No yaw-rate limit can
		# see that product term; a ceiling on the drawn orientation bounds it and every
		# future layer besides, exactly as the ROM clamp does for the limbs. The node's
		# steering yaw is outside skeleton space, so a fast body turn is never fought.
		if i == _head:
			var par_h: int = _sk.get_bone_parent(_head)
			var gp: Basis = _live_basis(par_h) if par_h >= 0 else Basis.IDENTITY
			var g_want: Quaternion = (gp * Basis(q_out)).get_rotation_quaternion().normalized()
			if _head_prev_g != Quaternion.IDENTITY:
				var step_g: float = _head_prev_g.angle_to(g_want)
				var allow: float = HEAD_MAX_RATE * dt
				if step_g > allow and step_g > 1e-4:
					g_want = _head_prev_g.slerp(g_want, allow / step_g).normalized()
					q_out = (gp.get_rotation_quaternion().inverse() * g_want).normalized()
			_head_prev_g = g_want
		_fin[i] = q_out
		_sk.set_bone_pose_rotation(i, q_out)
	# 7b. THE TAIL, RE-SOLVED AGAINST THE PARENT THAT ACTUALLY DREW — and then bounded in world
	# space, which is the third governor and the coverage gap KNOWN_ISSUES left open. See
	# TAIL_MAX_RATE for the measurement; the short version is that 5d cancels its parent through
	# `_live_basis`, which is the PRE-clamp, PRE-limiter buffer, and its parent is the binding
	# hind's hip — the most clamped and most rate-limited joint on the animal. The tail was
	# subtracting a thigh motion that never happened, at frame rate, and CatReviewProbe's
	# tail_world_step gate has been failing on it since before this session.
	if _tail >= 0 and _rest_gb.has(_tail):
		var par_t2: int = _sk.get_bone_parent(_tail)
		var gp_t: Basis = _fin_basis(par_t2) if par_t2 >= 0 else Basis.IDENTITY
		var gw: Quaternion = _tail_gwant
		if _tail_prev_g != Quaternion.IDENTITY:
			var st_t: float = _tail_prev_g.angle_to(gw)
			var allow_t: float = TAIL_MAX_RATE * dt
			if st_t > allow_t and st_t > 1e-5:
				gw = _tail_prev_g.slerp(gw, allow_t / st_t).normalized()
		_tail_prev_g = gw
		_fin[_tail] = (gp_t.get_rotation_quaternion().inverse() * gw).normalized()
		_sk.set_bone_pose_rotation(_tail, _fin[_tail])
	if _hip >= 0:
		# Through the parent-frame conversion — see _hip_pose_pos for why raw was fore-aft.
		_sk.set_bone_pose_position(_hip, _hip_pose_pos(_out_hip - (_rest_t[_hip] as Vector3)))

## `_live_basis`, but composed from the FINAL rotations — after the ROM clamp and both rate
## ceilings. The difference between the two is exactly the residue a bone posed absolutely has
## to cancel, and reading the pre-clamp buffer instead is what leaked it into the tail.
func _fin_basis(bone: int) -> Basis:
	var chain: Array[int] = []
	var i: int = bone
	while i >= 0:
		chain.push_front(i)
		i = _sk.get_bone_parent(i)
	var b := Basis.IDENTITY
	for j in chain:
		b = b * Basis(_fin.get(j, _out.get(j, _cur_q.get(j, Quaternion.IDENTITY))) as Quaternion)
	return b

## Evaluate a limb cycle table at cycle position `t` (0..1). Returns [reach, flex, paw].
##
## THIS WAS THE CHOPPINESS, and it is worth stating precisely because three sessions of tuning
## the numbers could never have found it — the fault was not in any number, it was in what
## happened BETWEEN them.
##
## The previous version eased every segment with `0.5 - 0.5*cos(k*PI)`. That is a smoothstep:
## its derivative is ZERO at both ends. Applied to every segment of a six-key table it does not
## smooth the cycle, it PUNCTUATES it — the paw's velocity is forced to zero at every single
## key, so a limb that should accelerate once, carry, and decelerate into the plant instead
## stops and restarts five times a stride. tests/CatFilm measured it at 4.5 near-stops per gait
## cycle per paw, with peak paw speeds of 3.7 m/s on a cat walking at 1.55. That is the owner's
## "still choppy", exactly, and it is an interpolation artefact rather than a gait fault.
##
## Now: a CYCLIC Catmull-Rom. It still passes through every authored key — the poses an animator
## chose are untouched — but each key's tangent is estimated from its neighbours, so velocity is
## continuous across the whole cycle and the only places the paw actually stops are the places
## the motion genuinely reverses (the plant, the top of the fold). The table WRAPS: the key
## before t=0 is the second-to-last key sitting at t-1, so the plant is smooth across the seam
## instead of being a hard restart every stride.
##
## Tangents are scaled by TAN_K < 1. Full Catmull-Rom overshoots between unevenly spaced keys,
## and an overshoot on `flex` at the plant drives the paw through the deck.
const TAN_K: float = 0.82

func _cyc_eval(tab: Array, t: float) -> Array:
	# The tables repeat their first key at t=1, so the distinct keys are 0..n-2 and the wrap
	# neighbours come from that range.
	var n: int = tab.size()
	var last: int = n - 1
	var seg: int = 0
	for i in range(last):
		if t <= float(tab[i + 1][0]):
			seg = i
			break
		seg = last - 1
	var p1: Array = tab[seg]
	var p2: Array = tab[seg + 1]
	var t1: float = float(p1[0])
	var t2: float = float(p2[0])
	# Wrapped neighbours, with their times shifted into this segment's own frame so the
	# tangents are correct across the seam rather than merely continuous-looking.
	var i0: int = seg - 1
	var t0: float = 0.0
	var p0: Array
	if i0 < 0:
		p0 = tab[last - 1]
		t0 = float(p0[0]) - 1.0
	else:
		p0 = tab[i0]
		t0 = float(p0[0])
	var i3: int = seg + 2
	var t3: float = 0.0
	var p3: Array
	if i3 > last:
		p3 = tab[1]
		t3 = float(p3[0]) + 1.0
	else:
		p3 = tab[i3]
		t3 = float(p3[0])
	var span: float = t2 - t1
	var k: float = 0.0 if span <= 1e-6 else clampf((t - t1) / span, 0.0, 1.0)
	var k2: float = k * k
	var k3: float = k2 * k
	# Cubic Hermite basis.
	var h00: float = 2.0 * k3 - 3.0 * k2 + 1.0
	var h10: float = k3 - 2.0 * k2 + k
	var h01: float = -2.0 * k3 + 3.0 * k2
	var h11: float = k3 - k2
	var out: Array = [0.0, 0.0, 0.0]
	for c in range(1, 4):
		var v0: float = float(p0[c])
		var v1: float = float(p1[c])
		var v2: float = float(p2[c])
		var v3: float = float(p3[c])
		# Non-uniform Catmull-Rom tangents: the secant through the neighbours, in this
		# segment's parameter units.
		var m1: float = TAN_K * (v2 - v0) / maxf(t2 - t0, 1e-6) * span
		var m2: float = TAN_K * (v3 - v1) / maxf(t3 - t1, 1e-6) * span
		out[c - 1] = h00 * v1 + h10 * m1 + h01 * v2 + h11 * m2
	return out

## THE FRAME'S OUTPUT, composed fresh every tick: _out starts as a copy of the blended
## pose state and the additive layers (gait, breath, strokes, look) multiply into _OUT,
## never into _cur_q. The first version multiplied into _cur_q itself — the persistent
## state — so every per-frame additive ACCUMULATED: the skeleton settled ~30 deg from any
## target (measured off the live game: Hip 31.5 deg, Spine01 29.8 deg from rest while
## "walking"), which drew as a permanently reared, twisted animal. The comment on that
## version claimed additives could not accumulate; the code did the opposite. Kept as the
## sharpest example this repo has of a comment asserting what the code must do instead of
## what it does.
var _out: Dictionary = {}
var _out_hip: Vector3 = Vector3.ZERO
func _mul(bone: int, q: Quaternion) -> void:
	if bone < 0:
		return
	_out[bone] = (_out.get(bone, _cur_q[bone]) as Quaternion) * q

## How far the drawn pose is from the target, 0..1 — lets behaviour wait for a settle
## ("stand up BEFORE walking") without hard-coding times.
func settle() -> float:
	var pose: Dictionary = _poses.get(_target, _poses["stand"])
	var worst: float = 0.0
	for i in [_spine, _hip, _limb["lf"]["prox"], _limb["lh"]["prox"]]:
		if i < 0:
			continue
		var want: Quaternion = pose["q"].get(i, _rest[i])
		worst = maxf(worst, (_cur_q[i] as Quaternion).angle_to(want))
	return clampf(worst / 0.8, 0.0, 1.0)

## ---------------------------------------------------------------- authored poses
##
## Every pose is a set of [axis, radians] offsets from the STAND rest, plus a hip drop.
## Axis codes 0/1/2 are the bone's own local X/Y/Z. Codes 3/4/5 are the BODY's pitch / yaw /
## roll, converted through that bone's rest basis — and on any bone whose local frame is not
## aligned with the body, those are the only ones that mean what they say.
##
## THE HIP IS SUCH A BONE, AND IT COST THE SIT POSE. `sit` asked for 0.58 rad about the Hip's
## local X, meaning "pitch the body up about the pelvis". tests/CatYawDiag measures what Hip
## local X actually does, per 0.2 rad: roll +8.03, pitch +5.18, yaw -5.92. It is not a pitch
## axis at all — it is mostly ROLL. At 0.58 rad that is roughly 23 degrees of roll and 17 of
## yaw, and the rear-view reel shows the result exactly: a cat that appears to have fallen
## over on its side with its head twisted up, which is the owner's "the hind legs trail
## instead of tucking" seen from the one angle that reveals it. Compare Spine01, where local X
## IS a clean pitch (+11.43, with 0.3 of yaw) — which is why the same idiom worked everywhere
## else and hid this.
##
## Same root cause as the breath layer turning the head: a bone axis is not an intention.
const _AXES := [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
const _BODY_AXES := [Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0)]  ## pitch, yaw, roll

func _pose_from(offsets: Dictionary, hip_drop: float) -> Dictionary:
	var e := {"q": {}, "hip_t": _rest_t.get(_hip, Vector3.ZERO) + Vector3(0, -hip_drop, 0)}
	for i in _rest:
		e["q"][i] = _rest[i]
	for bone_name in offsets:
		var i: int = _b(bone_name)
		if i < 0:
			continue
		var q: Quaternion = _rest[i]
		for pair in offsets[bone_name]:
			var code: int = int(pair[0])
			var ax: Vector3
			if code < 3:
				ax = _AXES[code]
			elif code < 6:
				ax = ((_rest_gb.get(i, Basis.IDENTITY) as Basis).inverse()
					* _BODY_AXES[code - 3]).normalized()
			else:
				# Code 6: this limb's MEASURED sagittal hinge — positive swings the paw
				# FORWARD, by derivation, on every limb (see _measure_gains). The jump used
				# to author its limbs on raw local X, the axis the repo itself proves is
				# ~90 deg off the true swing on R_Upperarm (0.005 m/rad against 0.198) — so
				# the airborne stretch came out twisted and left/right asymmetric.
				ax = _hinge_of(i)
			q = q * Quaternion(ax, pair[1])
		e["q"][i] = q
	return e

## ---------------------------------------------------------------- pose baking (with IK)
##
## HAND-TUNED FOLD ANGLES CANNOT SIT A CAT. Two rounds of authored angles proved it in
## renders: without something pinning the paws, every torso change sends the feet wherever
## the fold happens to leave them, and the two rig fits carry different bone LENGTHS on the
## left and right legs (a documented Tripo defect), so one set of angles cannot even be
## symmetric. The tool for "torso moves, paws stay planted" is IK, and it also absorbs the
## length asymmetry for free — it solves each leg with that leg's own bones.
##
## The IK is hinge-constrained CCD: every limb joint here is a hinge about its own local X
## (measured off the rendered axis atlas, tests/out/cat_axes*), so each step rotates one
## joint about its hinge by the angle that best carries the paw toward the target,
## projected into the plane the hinge allows. Runs at POSE-BUILD time only — the results
## are baked into the library and runtime stays ~40 slerps a frame.

func _set_chain(q: Dictionary) -> void:
	for i in q:
		_sk.set_bone_pose_rotation(i, q[i])

func _paw_pos(paw: int) -> Vector3:
	return _sk.get_bone_global_pose(paw).origin

## One hinged-CCD solve of `chain` (proximal..distal) carrying `paw` to `target`,
## editing `q` in place. The seed pose in `q` picks the knee's branch — seed folded and
## the solution folds the anatomical way.
## THE BAKE SOLVES ABOUT THE MEASURED HINGE, and this is the owner's "his arms go so wide
## when he sits".
##
## This function used to rotate every joint about its RAW LOCAL X — the axis this repo
## measured, three sessions ago, as ~90 degrees off the true swing on `R_Upperarm`
## (0.005 m of paw travel per radian against 0.198 on the others). Constraining CCD to the
## wrong plane does not stop it reaching the target: it reaches it THROUGH THAT PLANE, so
## the paw arrives at the right place having been swung out sideways to get there. Every
## baked pose that shifts a forepaw — the sit, the groom, the sleep tuck — therefore
## splayed its forelegs, and the sit splayed hardest because it moves all four paws.
##
## The runtime gait was moved onto derived hinges in s38 and the bake was not; they have
## been solving in different planes ever since. `_measure_gains` now runs before
## `_build_poses` precisely so this can use the same axis the gait does.
## HOW HARD THE BAKE ARGUES WITH ITSELF. Build-time only — six two-joint CCD solves per limb
## per pose is free at load and buys the paws being where the pose says they are. 1 mm is well
## under the mesh's own paw thickness and an order of magnitude under what an eye reads.
const PAW_PASSES: int = 6
const PAW_TOL: float = 0.001
## ...and how many times the TORSO is allowed to answer back. Four is enough for a converging
## fixed point on a geometry this smooth, and the best pass is kept regardless, so the only
## cost of a pose that does not respond is build time.
const TRIM_PASSES: int = 10

func _ik_leg(q: Dictionary, chain: Array, paw: int, target: Vector3, iters: int = 8) -> void:
	# THE TARGET IS PROJECTED INTO THE LIMB'S OWN SWING PLANE FIRST, and this is the rest
	# of "his arms go so wide when he sits".
	#
	# A limb here is a planar linkage: every joint in the chain shares one hinge, so the
	# paw can only travel in the plane through the socket normal to that hinge. But the
	# targets a pose asks for are the paws' REST anchors, and a pose that pitches the
	# torso (the sit rotates the Hip 0.58 rad) swings the shoulder sockets — which carries
	# each limb's PLANE away from the anchor it is being sent to. CCD cannot reach a point
	# off its own plane, so it does the only thing it can: it drives the chain hard toward
	# the target and the paw ends up out to the SIDE. That is the splay, and it is worst
	# in the sit because the sit both pitches the torso and moves all four paws.
	#
	# Projecting the target onto the plane asks the leg for the closest point it can
	# actually reach, in the plane it actually swings in. The paw lands a centimetre or so
	# from the authored anchor and stays under the animal instead of out beside it.
	if not chain.is_empty():
		_set_chain(q)
		var root: int = int(chain[0])
		var rt: Transform3D = _sk.get_bone_global_pose(root)
		var n_w: Vector3 = (rt.basis * _hinge_of(root)).normalized()
		target -= n_w * n_w.dot(target - rt.origin)
	for _it in range(iters):
		for j in chain:
			_set_chain(q)
			var jt: Transform3D = _sk.get_bone_global_pose(j)
			var hinge: Vector3 = _hinge_of(j)
			var axis: Vector3 = (jt.basis * hinge).normalized()
			var v1: Vector3 = _paw_pos(paw) - jt.origin
			var v2: Vector3 = target - jt.origin
			v1 -= axis * axis.dot(v1)
			v2 -= axis * axis.dot(v2)
			if v1.length() < 1e-4 or v2.length() < 1e-4:
				continue
			var ang: float = atan2(v1.cross(v2).dot(axis), v1.dot(v2))
			# Rotating a bone about a local axis moves the world exactly about that axis's
			# world image, so the signed world angle maps 1:1 onto the local hinge.
			q[j] = (q[j] as Quaternion) * Quaternion(hinge, clampf(ang, -0.6, 0.6))
			# ...AND INSIDE THE SAME ROM THE RUNTIME ENFORCES, which the bake has never been.
			#
			# `tick`'s write loop passes every bone that carries a `_rom` entry through
			# `_clamp_joint` — the "anatomy choke point" that stops any layer producing a joint
			# the animal does not have. The bake ran outside it, so a pose could be SOLVED at
			# an angle that is then CLAMPED the instant it is drawn, and the paw the library
			# believed it had planted is not the paw on screen. Measured on the sit: the static
			# pose put the left forepaw 18.2 mm above the deck and the LIVE animal wearing that
			# same pose put it 30.4 mm above, with nothing moving — 12 mm of pure disagreement
			# between the two, in a pose the player looks at more than any other.
			#
			# Clamping here makes the solve honest about the animal it is solving: CCD simply
			# converges to the best in-range answer, and whatever it cannot buy is left as a
			# residual for the body trim below to take up.
			if _rom.has(j):
				q[j] = _clamp_joint(j, q[j])

## Build a pose: torso offsets first, then IK every leg to its target. Targets default to
## the paws' REST positions — "the feet stay where they stand" — with optional shifts.
##
## `free_leg` NAMES A LIMB THAT IS NOT ON THE DECK, and it is the whole of why the ear scratch
## can exist. `arms_too` could already drop BOTH forelimbs out of the plant; nothing could drop
## ONE hind, and a scratch is a tripod — three paws planted, the fourth posed. Left in the bake
## a leg is solved to its rest anchor on the deck, so any lift authored on top of it is fighting
## the IK that just put it back down: that is exactly why the first cut of this style could only
## twitch. Default "" matches no limb key, so every existing caller bakes as it always did.
func _bake(torso: Dictionary, hip_drop: float, paw_shift: Dictionary = {},
		seed_fold: float = 0.0, arms_too: bool = true, free_leg: String = "") -> Dictionary:
	var paw_err := {}
	# Rest paw anchors, measured once per bake from the skeleton itself.
	var rest_q := {}
	for i in _rest:
		rest_q[i] = _rest[i]
	_set_chain(rest_q)
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, _rest_t[_hip])
	var anchors := {}
	for k in _limb:
		anchors[k] = _paw_pos(_limb[k]["paw"])
	# THE BODY TRIM, and this is the half the leg solve cannot buy.
	#
	# The legs are hinges of fixed length inside a ROM this rig measured off its own bones.
	# When a pose drops the pelvis 118 mm and pitches it 0.58 rad, the four sockets go where
	# the torso sends them, and the reachable set of a two-bone chain in its own swing plane
	# simply may not contain the deck anchor any more. Then the paw stops at its closest
	# approach and the animal is DRAWN with a foot in the air or through the plating — which
	# is precisely the owner's report, and precisely what the pose library has been shipping.
	#
	# The classical answer is the one a rigger would give: if the feet are planted and the
	# legs cannot lie, the BODY is the free variable. So the bake iterates the torso against
	# the paws it actually lands — the mean vertical error becomes hip height, the fore-minus-
	# hind difference becomes a pitch trim over the animal's own measured wheelbase — and
	# re-solves. It is the same feedback shape as the per-leg loop, one level up.
	#
	# DERIVED, KEPT ONLY IF IT HELPS, AND REPORTED. The best pass wins on measured error, so a
	# pose whose geometry does not respond (or an axis sign that turned out the other way) ends
	# at the untrimmed bake rather than being walked somewhere worse; and the trim it settled
	# on is written onto the entry as `trim` so a probe can see what the bake had to spend.
	var fore_n: int = 0
	var hind_n: int = 0
	var fore_x: float = 0.0
	var hind_x: float = 0.0
	for k in _limb:
		if k == free_leg or (not k.ends_with("h") and not arms_too):
			continue
		var a: Vector3 = anchors[k]
		if k.ends_with("h"):
			hind_n += 1
			hind_x += a.dot(BODY_FWD)
		else:
			fore_n += 1
			fore_x += a.dot(BODY_FWD)
	# The lever the pitch trim works over: the fore-to-hind span of the planted anchors, off
	# this skeleton. Never a typed number — a re-rig changes it and nothing here has to know.
	var wheel: float = 0.0
	if fore_n > 0 and hind_n > 0:
		wheel = absf(fore_x / float(fore_n) - hind_x / float(hind_n))
	var trim_y: float = 0.0
	var trim_pitch: float = 0.0
	var best_trim := Vector2.ZERO
	var best_worst: float = 1e9
	var best_e: Dictionary = {}
	var best_perr: Dictionary = {}
	var best_dy: Dictionary = {}
	var e: Dictionary = {}
	var q: Dictionary = {}
	for _trim_pass in range(TRIM_PASSES):
		paw_err = {}
		var dy := {}
		var torso2: Dictionary = torso.duplicate(true)
		if absf(trim_pitch) > 1e-6:
			var hp: Array = (torso2.get("Hip", []) as Array).duplicate()
			hp.append([3, trim_pitch])
			torso2["Hip"] = hp
		# Start from rest + torso, with the hip dropped — GENUINELY dropped: this write went
		# raw into the parent frame for every session the bake has existed, so "hip_drop" slid
		# the pelvis fore-aft and the crouch depth lived entirely in the Hip pitch.
		e = _pose_from(torso2, hip_drop - trim_y)
		q = e["q"]
		if _hip >= 0:
			_sk.set_bone_pose_position(_hip,
				_hip_pose_pos((e["hip_t"] as Vector3) - (_rest_t[_hip] as Vector3)))
		_bake_legs(q, anchors, paw_shift, seed_fold, arms_too, free_leg, paw_err, dy)
		var worst: float = 0.0
		for k in dy:
			worst = maxf(worst, absf(float(dy[k])))
		if worst < best_worst:
			best_worst = worst
			best_trim = Vector2(trim_y, trim_pitch)
			best_e = e
			best_perr = paw_err.duplicate()
			best_dy = {}
			for k2 in dy:
				best_dy[k2] = float(dy[k2]) * 1000.0
		if worst < PAW_TOL:
			break
		var f_sum: float = 0.0
		var h_sum: float = 0.0
		var n_all: int = 0
		var all_sum: float = 0.0
		for k in dy:
			var v: float = float(dy[k])
			all_sum += v
			n_all += 1
			if k.ends_with("h"):
				h_sum += v
			else:
				f_sum += v
		if n_all == 0:
			break
		# Vertical: the mean error is height the body owes the deck. `hip_drop` is a DROP, so a
		# paw stranded ABOVE its anchor (dy < 0) has to become a LARGER drop.
		trim_y += all_sum / float(n_all)
		# Pitch: [3, θ] is the measured body pitch and +θ is nose-UP (the sit's +0.58, the
		# stretch's -0.26 with its chest on the floor). A nose-up θ raises the fore anchors by
		# wheel/2 and lowers the hind by the same, so the θ that closes the difference is
		# (dy_fore - dy_hind) / wheel.
		if fore_n > 0 and hind_n > 0 and wheel > 0.02:
			trim_pitch += (f_sum / float(fore_n) - h_sum / float(hind_n)) / wheel
	if not best_e.is_empty() and (best_trim.x != trim_y or best_trim.y != trim_pitch):
		e = best_e
		q = e["q"]
		paw_err = best_perr
	e["trim"] = [best_trim.x, best_trim.y]
	e["paw_err_mm"] = paw_err
	e["paw_dy_mm"] = best_dy
	# Skeleton back to rest so nothing leaks out of the bake.
	_set_chain(rest_q)
	if _hip >= 0:
		_sk.set_bone_pose_position(_hip, _rest_t[_hip])
	return e

## One full four-leg solve for `_bake`, filling `paw_err` (3D residual, mm) and `dy` (the
## SIGNED vertical residual in metres — target minus paw, so negative is a floating paw).
## Split out so the body-trim loop above can run it more than once without duplicating it.
func _bake_legs(q: Dictionary, anchors: Dictionary, paw_shift: Dictionary, seed_fold: float,
		arms_too: bool, free_leg: String, paw_err: Dictionary, dy: Dictionary) -> void:
	# Seed the legs folded so CCD converges to the anatomical branch (knees fold, never
	# hyperextend), then solve each leg to its (possibly shifted) anchor.
	for k in _limb:
		var L: Dictionary = _limb[k]
		var hind: bool = k.ends_with("h")
		if k == free_leg:
			continue
		if not hind and not arms_too:
			continue
		if seed_fold > 0.0:
			# Seeded about the MEASURED hinge for the same reason the solve is — a seed in
			# the wrong plane starts the chain splayed and CCD has no reason to bring it
			# back in.
			q[L["prox"]] = (q[L["prox"]] as Quaternion) \
				* Quaternion(_hinge_of(L["prox"]), seed_fold)
			q[L["dist"]] = (q[L["dist"]] as Quaternion) \
				* Quaternion(_hinge_of(L["dist"]), seed_fold)
		var target: Vector3 = anchors[k] + paw_shift.get(k, Vector3.ZERO)
		# CLOSE THE LOOP ON THE PAW THAT IS ACTUALLY DRAWN. This is the owner's "when the cat
		# is sitting the game angled him backwards, causing front paws to float an inch above
		# and back paws to be sinking an inch" — and it was never a pitch layer leaking. It
		# was THIS function quietly not arriving.
		#
		# One `_ik_leg` call is eight sweeps of a two-joint chain with a +/-0.6 rad per-step
		# clamp, run against a target first PROJECTED into that limb's own swing plane. Every
		# one of those is right and none of them guarantees arrival: the solve converges toward
		# the projected point and stops wherever eight passes leave it. Measured on the shipped
		# sit (tests/SitScratch), against the same paw bones in `stand`: fore +18.6 / +8.8 mm
		# ABOVE the deck, hind -14.2 / -7.2 mm THROUGH it. That is 24 mm of fore-to-hind
		# difference over a 0.348 m wheelbase — 4.0 degrees of nose-up pitch, baked into the
		# pose library itself, with the runtime layers adding ~12 mm more on top.
		#
		# So the bake measures its own result and asks again. The residual is fed back into the
		# AIM (target plus accumulated error) while the residual is always judged against the
		# REAL target — the standard retarget loop — and the best pass is kept, so a limb that
		# genuinely cannot reach ends at its closest approach instead of being driven to an
		# extreme by a runaway aim. The per-limb residual is recorded on the pose entry
		# (`paw_err_mm`) so a probe can read what the bake ACHIEVED rather than trusting that
		# it did; an IK loop that reports no residual is the same class of
		# instrument-that-cannot-fail this file keeps having to dismantle.
		var aim: Vector3 = target
		var best_q: Dictionary = {}
		var best_err: float = 1e9
		for _pass in range(PAW_PASSES):
			_ik_leg(q, [L["prox"], L["dist"]], L["paw"], aim)
			_set_chain(q)
			var err: Vector3 = target - _paw_pos(L["paw"])
			if err.length() < best_err:
				best_err = err.length()
				best_q = {L["prox"]: q[L["prox"]], L["dist"]: q[L["dist"]]}
			if err.length() < PAW_TOL:
				break
			aim += err
		for bi in best_q:
			q[bi] = best_q[bi]
		paw_err[k] = best_err * 1000.0
		# The VERTICAL residual, signed and kept separate: the 3D number above is the honest
		# report of the solve, but the trim can only spend height and pitch, so it needs the
		# component it can actually pay. Skeleton space IS body space here (see BODY_UP), and
		# a settled cat's node carries no pitch or roll, so this is the deck normal.
		dy[k] = (target - _paw_pos(L["paw"])).dot(BODY_UP)

func _build_poses() -> void:
	if not valid():
		return
	# WALK / RUN wear the neutral stance — the gait IS the pose. `loco` marks every pose the
	# body translates through; forget it on a new moving pose and CatReviewProbe's
	# locomotes=>steps gate fails the state by name.
	_poses["walk"] = _pose_from({}, 0.0)
	_poses["walk"]["loco"] = true
	_poses["run"] = _pose_from({"NeckTwist01": [[0, 0.10]]}, 0.012)
	_poses["run"]["loco"] = true
	# SIT: pelvis down and body pitched about the hip; the hind paws step a little forward
	# under the dropped pelvis, the fore paws hold their ground; IK keeps all four planted.
	# The neck counters only PART of the body pitch: countering all of it (the first cut,
	# -0.28) buried the head inside the body silhouette and the sit read as a sprawl from
	# behind — a sitting cat's head must stand clearly ABOVE its shoulders.
	_poses["sit"] = _bake({
		"Hip": [[3, 0.58]],
		"NeckTwist01": [[0, -0.06]], "Head": [[0, 0.04]],
	}, 0.118, {"lf": Vector3(-0.06, 0, 0), "rf": Vector3(-0.06, 0, 0),
		"lh": Vector3(0.13, 0, 0), "rh": Vector3(0.13, 0, 0)}, 0.7)
	# GROOM: the sit, then the left forepaw raised to the lowered muzzle — the arm override
	# happens AFTER the bake, which is what a raised paw is.
	var g: Dictionary = _bake({
		"Hip": [[3, 0.58]],
		"Spine02": [[1, 0.15]],
		"NeckTwist01": [[0, -0.55]], "Head": [[0, -0.28]],
	}, 0.118, {}, 0.7)
	# THE LAST RAW-LOCAL-X WRITER IN THE FILE, and it was throwing the paw through the
	# chest. On this rig L_Upperarm's local X is an ABDUCTION axis (0.245 m of lateral paw
	# travel per radian), so -1.05 rad about it swung the raised forepaw 160 mm ACROSS THE
	# MIDLINE — a limb inside the body, in the pose the player sees most. Measured on the
	# same measured hinges the gait and the bake now share.
	var gl: Dictionary = _limb["lf"]
	g["q"][gl["prox"]] = _rest[gl["prox"]] * Quaternion(_hinge_of(gl["prox"]), 0.95)
	g["q"][gl["dist"]] = _rest[gl["dist"]] * Quaternion(_hinge_of(gl["dist"]), 0.55)
	g["q"][gl["paw"]] = _rest[gl["paw"]] * Quaternion(_hinge_of(gl["paw"]), -0.35)
	_poses["groom"] = g
	# ...AND THE SAME SIT WITHOUT THE RAISED PAW. The forepaw held up to the muzzle belongs to
	# the paw-lick and to nothing else, but it was baked into the one groom pose, so every
	# other wash style inherited it: the flank wash filmed as a cat washing its shoulder while
	# holding a paw in the air for no reason. Styles that work with the head alone get this
	# one instead (see `groom_style`).
	_poses["groom_flat"] = _bake({
		"Hip": [[3, 0.58]],
		"Spine02": [[1, 0.15]],
		"NeckTwist01": [[0, -0.55]], "Head": [[0, -0.28]],
	}, 0.118, {}, 0.7)
	# GROOM_SCRATCH: the ear scratch, and the one pose in the library with a leg OUT of the
	# bake. A scratching cat is a TRIPOD — it rolls its weight onto one hip, keeps two forepaws
	# and one hind on the deck, and works with the fourth. So the left hind is handed to `_bake`
	# as `free_leg` and authored here instead of being solved to an anchor on the deck. That is
	# the whole difference from the version this replaces, which was driven off the `groom` sit
	# with all four feet planted and could only twitch: the lift was fighting the IK that had
	# just put the foot back down.
	#
	# WHY THE LEFT HIND, MEASURED RATHER THAN CHOSEN. This fit's two hind chains are not the
	# same animal. Thigh->calf->foot is 0.336 + 0.111 m on the left against 0.086 + 0.106 on
	# the right, and the right hind rests at 99.9% of its own reach (the dead-straight bind the
	# load report prints). The left paw therefore travels more than twice as far per radian of
	# hip, and it is the only one of the four whose reach envelope contains the head at all:
	# 0.447 m of chain against a 0.424 m socket-to-ear. The right hind would repeat the twitch
	# for a second, different reason.
	#
	# AND HERE IS THE CEILING, because what fails is not the leg's LENGTH. The paw has to swing
	# about 155 degrees from where it rests to point at the ear, and `_rom` allows +/-0.62 rad
	# (35.5) at the hip — a limit that exists because this animal was measured driving that
	# joint through 103 degrees a stride. Sweeping the hip with the clamp lifted: -0.62 leaves
	# the paw 0.589 m from the ear, -1.30 leaves 0.464, and it takes about -2.60 rad (149
	# degrees, 4.2x ROM_PROX) to close to 0.16 m. Widening one joint's clamp fourfold to buy one
	# pose hands the same licence to the gait, which is the defect the clamp was added to stop,
	# so the pose stops where the anatomy stops. At -0.48 the hock stands 0.204 m up — level
	# with the top of the back — and the paw 0.132 m up and 0.172 m out, outside the body's own
	# half-width of 0.133. The leg reads as raised, folded and working; the paw is at the
	# shoulder rather than the ear, and the head does the rest of the travelling by tilting into
	# it (`tick`, style 3).
	#
	# The trunk sits at 0.34 rad and not the sit's 0.58 because the hip pitch FIGHTS the lift:
	# it rotates the whole limb's swing plane backward, and at 0.58 the same authored leg draws
	# its hock below its own socket. Rolled 0.14 rad onto the right hip — a few degrees, toward
	# the planted side — with the thorax keeping a little of it back so the shoulders stay level
	# over the two planted forepaws: they land within 4 mm of their rest anchors, and the
	# planted right hind lands 19 mm low against `groom_flat`'s 61.
	_poses["groom_scratch"] = _bake({
		"Hip": [[3, 0.34], [5, 0.14]],
		"Spine01": [[5, -0.05]], "Spine02": [[5, -0.04]],
		"NeckTwist01": [[0, -0.18]], "Head": [[0, -0.08]],
		# The free limb, on BODY axes and the measured hinge and never on raw local X, which on
		# these bones is an abduction axis as often as a swing. [6] lifts the leg in its own
		# sagittal plane, [5] rolls it out from under the belly, [4] swings it clear of the
		# flank — and the last two are perpendicular to the hinge, so `_clamp_joint` (which
		# bounds the hinge component and preserves the rest) passes them through untouched.
		# Only the 0.48 spends ROM.
		"L_Thigh": [[6, -0.48], [5, 0.65], [4, -0.32]],
		"L_Calf": [[6, 0.92]],          # the stifle folded, carrying the paw up under the hock
		"L_Foot": [[6, 0.22]], "L_ToeBase": [[6, 0.16]],
	}, 0.118, {"rh": Vector3(0.13, 0, 0)}, 0.7, true, "lh")
	# SLEEP: the loaf — belly nearly on the deck, all four paws tucked in under the body,
	# head sunk and turned. The tuck is the paw targets pulled inward and up a whisker.
	_poses["sleep"] = _bake({
		"Spine01": [[1, 0.22]], "Spine02": [[1, 0.22]],
		"NeckTwist01": [[0, -0.52], [1, 0.32]], "Head": [[0, -0.34]],
	}, 0.190, {
		"lf": Vector3(0, 0.02, -0.06), "rf": Vector3(0, 0.02, 0.06),
		"lh": Vector3(0, 0.02, -0.05), "rh": Vector3(0, 0.02, 0.05),
	}, 1.0)
	# STRETCH: chest to the floor, rear high, forepaws reaching far forward on the deck.
	_poses["stretch"] = _bake({
		"Hip": [[3, -0.26]],
		"NeckTwist01": [[0, 0.42]], "Head": [[0, 0.20]],
	}, 0.035, {
		"lf": Vector3(0.16, 0, 0), "rf": Vector3(0.16, 0, 0),
	}, 0.35)
	# STALK: the creep. Belly close to the deck, elbows and hocks folded so the whole animal
	# drops without the paws leaving the ground, shoulders high over a lowered chest, head
	# pushed FORWARD and held level — a stalking cat keeps its eyes on the line of the prey
	# however low the rest of it gets, and a stalk whose head droops with the body reads as a
	# sick animal rather than a hunting one. The forepaws creep a little further under the
	# chest, which is what gathers it for the launch.
	_poses["stalk"] = _bake({
		"NeckTwist01": [[0, -0.16]], "Head": [[0, 0.20]],
	}, 0.112, {"lf": Vector3(0.035, 0, 0), "rf": Vector3(0.035, 0, 0)}, 0.85)
	# The creep LOCOMOTES (ship_cat drives it at STALK_SPEED), and its gait is the walk
	# folded down: high duty (a stalking cat is never airborne), short strides, paws barely
	# leaving the deck. The freezes ship_cat inserts read against moving feet, not sliding
	# ones.
	_poses["stalk"]["loco"] = true
	_poses["stalk"]["duty"] = 0.78
	_poses["stalk"]["sweep_k"] = 0.80
	_poses["stalk"]["lift_k"] = 0.45
	# CARRY: the walk with the head and neck lifted — a cat bringing something back holds it
	# clear of its own feet, and the raised head is the whole read at a distance.
	_poses["carry"] = _pose_from({
		"NeckTwist01": [[0, 0.24]], "Head": [[0, -0.10]],
	}, 0.0)
	# "The walk with the head lifted" — so it WALKS: the comment always said so, the gait
	# gate never let it. Normal cycle under the raised-head overlay.
	_poses["carry"]["loco"] = true
	# JUMP: airborne, so no planting — the flight stretch, fores reaching, hinds driving.
	# On MEASURED hinges (code 6, +ve = paw forward): the old raw-local-X authoring drove
	# R_Upperarm about an axis that moves its paw 0.005 m/rad — a twisted, asymmetric leap.
	_poses["jump"] = _pose_from({
		"Hip": [[3, 0.14]],
		"L_Upperarm": [[6, 0.85]], "R_Upperarm": [[6, 0.85]],
		"L_Forearm": [[6, 0.30]], "R_Forearm": [[6, 0.30]],
		"L_Thigh": [[6, -0.80]], "R_Thigh": [[6, -0.80]],
		"L_Calf": [[6, -0.30]], "R_Calf": [[6, -0.30]],
	}, -0.02)
	# ---------------- transition sub-poses (see set_pose's grammar) ----------------
	# RISE: the first beat of standing up — the REAR lifts while the head is still low.
	_poses["rise"] = _bake({
		"Hip": [[3, -0.10]],
		"NeckTwist01": [[0, -0.20]],
	}, 0.045, {}, 0.4)
	# SIT_PRE: the weight rocks back and the head dips — the anticipation before folding.
	_poses["sit_pre"] = _bake({
		"Hip": [[3, 0.22]],
		"NeckTwist01": [[0, -0.14]],
	}, 0.055, {}, 0.4)
	# SIT_DEEP: a whisker past the sit — the overshoot a settling body has, held ~0.14 s
	# on the way in so the sit lands with weight instead of easing asymptotically into
	# place.
	_poses["sit_deep"] = _bake({
		"Hip": [[3, 0.66]],
		"NeckTwist01": [[0, -0.08]], "Head": [[0, 0.05]],
	}, 0.135, {"lf": Vector3(-0.06, 0, 0), "rf": Vector3(-0.06, 0, 0),
		"lh": Vector3(0.13, 0, 0), "rh": Vector3(0.13, 0, 0)}, 0.7)
	# LEAN: the small forward weight-shift before the first stride. Locomotes, so the
	# stride can begin under it.
	_poses["lean"] = _pose_from({"Hip": [[3, -0.05]]}, 0.008)
	_poses["lean"]["loco"] = true
	# JUMP_CROUCH: the loaded spring — deep fold, all four paws still planted, COM back.
	# Held by ship_cat for the anticipation beat BEFORE the body leaves the deck.
	_poses["jump_crouch"] = _bake({
		"Hip": [[3, 0.10]],
		"NeckTwist01": [[0, -0.10]],
	}, 0.16, {}, 1.0)
	# JUMP_LAND: fore-paws-first absorption — chest low over reaching fores, hips high.
	_poses["jump_land"] = _bake({
		"Hip": [[3, -0.18]],
		"NeckTwist01": [[0, -0.25]],
	}, 0.06, {"lf": Vector3(0.05, 0, 0), "rf": Vector3(0.05, 0, 0)}, 0.5)
	# JUMP_LAUNCH: the push-off — hinds driven to full extension behind, fores tucked to the
	# chest. The first quarter of every flight wears this, so the leap visibly COMES FROM
	# the hind legs (the owner's "pushes off hind legs") instead of teleporting into the
	# full mid-air sprawl on frame one. Airborne, so authored (no planting bake), on
	# measured hinges like the flight stretch.
	_poses["jump_launch"] = _pose_from({
		"Hip": [[3, 0.22]],
		"L_Upperarm": [[6, 0.30]], "R_Upperarm": [[6, 0.30]],
		"L_Forearm": [[6, 0.80]], "R_Forearm": [[6, 0.80]],
		"L_Thigh": [[6, -1.05]], "R_Thigh": [[6, -1.05]],
		"L_Calf": [[6, -0.20]], "R_Calf": [[6, -0.20]],
	}, -0.03)
	# JUMP_DESCEND: front feet first — fores reaching long and DOWN for the landing spot,
	# hinds trailing folded, nose over the paws. The last third of the flight wears this so
	# the animal arrives the way a cat arrives, forehand first, before jump_land absorbs.
	_poses["jump_descend"] = _pose_from({
		"Hip": [[3, -0.20]],
		"NeckTwist01": [[0, -0.15]],
		"L_Upperarm": [[6, 1.00]], "R_Upperarm": [[6, 1.00]],
		"L_Forearm": [[6, 0.15]], "R_Forearm": [[6, 0.15]],
		"L_Thigh": [[6, 0.55]], "R_Thigh": [[6, 0.55]],
		"L_Calf": [[6, 0.45]], "R_Calf": [[6, 0.45]],
	}, 0.0)
