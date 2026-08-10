extends Node3D
## THE SHIP'S CAT — the one animal on this rig that is company rather than weather.
##
## Every other creature here is indifferent to you at best: the crabs want you off their leg,
## the gulls flush, the seal tolerates a pat. The cat is the only one that CHOOSES you, and the
## whole design follows from that one idea:
##
##   FOUND, not spawned at you. It is in the bunkhouse from the first minute of a run, sitting
##   on the deck washing a paw, and it stays there until somebody says hello. Nothing points at
##   it and nothing announces it — you find it or you don't.
##   ONCE, and then for good. There is no befriending minigame and no trust meter. You reach
##   out, it accepts, and that is the last decision either of you makes about it.
##   IT KEEPS ITS OWN COUNSEL. It follows, but at its own pace and its own distance, and it
##   stops to sit when you stop. A pet that teleports to heel is a HUD element with fur.
##   IT WANTS THE FISH. Hold one and it closes in, tail up, and will not be got rid of.
##
## Kinematic and un-navmeshed, like the crab, per the same brief — it walks the deck it is on
## and does not attempt stairs. That is deliberate: a cat that cannot follow you down a ladder
## is a cat, and one that clips through a bunk frame chasing you is a bug.

const ANIM := preload("res://scripts/world/creature_anim.gd")
const KIT := preload("res://scripts/world/creature_kit.gd")
const AIB := preload("res://scripts/world/ai_budget.gd")
const RIG := preload("res://scripts/world/cat_rig.gd")
const MODEL_PATH := "res://assets/models/fauna/ship_cat/ship_cat.glb"

## ONE MESH PER POSE, BUILT ONCE AND TOGGLED — not swapped through ANIM.replace().
##
## The s32 cat was a single standing mesh doing every state, so "sitting" was a static
## standing cat and "asleep" was a static standing cat leaning over. Tripo generated five
## poses in s34 from one coat description (see gen_cat_batch.py) and the states below drive
## them.
##
## WHY NOT `ANIM.replace()` PER TRANSITION, which is what the brief suggested: replace()
## hides every mesh built BEFORE it, which is the documented trap, but the real problem is
## that it re-instantiates the scene and rebuilds every ShaderMaterial on the frame the cat
## changes its mind — several times a minute, next to the player, on the animal whose whole
## job is to not read as a machine. All six are attached once in _ready and the transition
## is a `visible` flip. Godot does not draw a hidden MeshInstance, so the cost of the five
## that are off is their memory, and they share the cached .glb resources.
##
## `stand` is kept because the s32 mesh is the only one authored on all four feet and level,
## which is what the walk cycle's gait bob is tuned against.
## JUMP is APPENDED, never inserted. CatProbe and the close-out harness assert on the
## integer values of these (state 2 is RUN, state 5 is FISH), so inserting anywhere but the
## end silently re-numbers the states out from under every test that names one.
## APPENDED, NEVER INSERTED — CatProbe and the close-out harness assert on the INTEGER values
## (state 2 is RUN, state 5 is FISH), so a new state anywhere but the end silently renumbers
## the states out from under every test that names one.
##
## STALK / POUNCE / GIFT are the predatory sequence; PLAY is the same machinery with nothing
## on the end of it; PERCH is the cat's standing preference for being higher than you.
## SWIM is APPENDED for the same reason JUMP was — see the two paragraphs above. It is the
## recovery state for a cat that has ended up in the sea: it treads water, finds a lip it
## can board from, and climbs out. Nothing chooses it; only `_over_water` does.
enum State { GROOM, FOLLOW, RUN, SIT, SLEEP, FISH, PET, JUMP,
	STALK, POUNCE, GIFT, PLAY, PERCH, STRETCH, SWIM }

## s35: THE RIGGED MESHES, where they exist. Same five poses, same look — Tripo rigged the
## ALREADY-SHIPPING meshes off the task ids s34 logged, and the bind pose photographs
## identically to the static original (tests/out/cat_bind). What is new is 41 bones, which
## is the difference between a cat that changes pose and a cat that MOVES.
## The static paths remain the fallback: a missing rigged asset degrades to the s34 look
## rather than to a crash, which is the same contract every generated species here has.
## `run` is cat_run2, NOT cat_run. The s34 run mesh has its head and shoulders turned —
## the owner's "the cat is looking/turning to the left, so the running straight is
## currently crooked". That is a MESH fault and no amount of yaw fixes it: straightening
## the head by rotating the node would aim the body off the line of travel. s36 re-rolled
## the pose with the head, neck, spine and shoulders named explicitly in the prompt
## (tools/gen_cat_s36.py) and measured the result — the across-body extent fell from 0.488
## to 0.387 of the body length, i.e. the animal genuinely got straighter rather than just
## looking it from one angle.
## s37: ONE MESH, ONE SKELETON — the pose-per-mesh design is gone.
##
## Why it had to go: six separate rigged meshes swapped by a `visible` flip meant every
## state change was a whole-body teleport (one frame walking, the next sitting, nothing
## between), and the gait swung limbs on meshes AUTHORED mid-stride, double-posing the
## legs. That is unfixable by tuning — the architecture cannot express a transition.
##
## Now the neutral STANDING mesh is the only body, and every pose (sit, groom, sleep,
## run stance, jump stretch) is a set of joint rotations extracted from the other rigged
## meshes' rest poses (tools/extract_cat_poses.py — same Tripo template, bone-for-bone)
## and BLENDED onto the one skeleton by cat_rig.gd. Transitions are continuous by
## construction. BASE_FALLBACK keeps the s34 static path alive if the rigged stand is
## ever missing: the cat degrades to a statue, never to a crash.
const BASE_RIGGED := "res://assets/models/fauna/_rigged/cat_stand_idle.glb"
const BASE_FALLBACK := "res://assets/models/fauna/_rigged/cat_walk_walk.glb"
const POSE_LIBRARY := "res://assets/models/fauna/_rigged/cat_poses.json"
## Which pose each state wears. Kept as a table rather than a match statement inside the
## per-frame code so a state cannot silently forget to set one.
const STATE_POSE := {
	State.GROOM: "groom",
	State.FOLLOW: "walk",
	State.RUN: "run",
	State.SIT: "sit",
	State.SLEEP: "sleep",
	State.FISH: "walk",
	State.PET: "sit",
	State.JUMP: "jump",
	State.STALK: "stalk",
	State.POUNCE: "jump",
	State.GIFT: "carry",
	State.PLAY: "walk",
	State.PERCH: "sit",
	State.STRETCH: "stretch",
	# A swimming cat paddles: `walk` is the one locomoting pose whose cycle reads as legs
	# working under a body that is not bounding. Named here rather than left to the
	# fallback because `_enter`'s default is "stand" and a statue in the sea is worse than
	# a wrong gait. (`set_pose` no-ops silently on an unknown name — cat_rig.gd:1017.)
	State.SWIM: "walk",
}

# ------------------------------------------------------------------ the hunt
#
## THE PREDATORY SEQUENCE, which is one of the most legible behaviours any animal has and the
## thing people actually mean when they say a cat is a cat. Leyhausen's description of it has
## five beats and every one of them is readable at game distance on a body with no facial rig:
##
##   NOTICE  — the whole animal stops and locks on. Stillness after motion IS the tell.
##   STALK   — low, slow, belly close to the deck, and it FREEZES whenever it thinks it has
##             been seen. The freezing is what separates a stalk from a walk toward something.
##   TREAD   — the plié: hind feet paddle, the rear waggles, and everyone who has ever met a
##             cat knows exactly what is about to happen. This is the single highest-value
##             half-second in the whole sequence and it costs one sine wave.
##   POUNCE  — a real leap, forepaws first, over the existing jump arc.
##   AFTER   — and it MISSES most of the time. A cat that misses sits down at once and washes,
##             with enormous dignity, as though it had meant to do that. That displacement
##             groom is more characterful than a success, and it is why the miss rate here is
##             deliberately high rather than generous.
##
## On a catch it brings the thing to you, because that is what a cat does with a companion.
const HUNT_M: float = 11.0            ## it clocks a bird from here
const HUNT_GIVEUP_M: float = 16.0     ## ...and gives up if the bird gets this far away
const STALK_SPEED: float = 0.62       ## the creep — deliberately well under a walk
const POUNCE_M: float = 1.75          ## close enough to launch
const POUNCE_SEC: float = 0.42
const WIGGLE_SEC: float = 0.9         ## the tread-and-waggle before the launch
const HUNT_CD: float = 24.0           ## after a hunt, it lets the deck settle
## Birds are HARD. A house cat's success rate on birds is well under half, and the misses are
## the better animation anyway — see the displacement wash above.
const CATCH_CHANCE: float = 0.34
const WASH_SEC: float = 4.5           ## how long the "I meant to do that" wash lasts
## The zoomies (FRAP). Real, well documented, and they fire after a sleep and around dusk —
## the crepuscular activity peak every cat owner knows as the evening madness.
const ZOOM_SEC: float = 3.4
const ZOOM_CD: float = 95.0
const PLAY_CD: float = 38.0
const PLAY_SEC: float = 6.0


## Where it is found. THE STORE ROOM, under the lantern — owner: "Have the cat spawn in the
## 2nd internal room near a light so it is illuminated in the dark."
##
## WHICH ROOM, AND WHY. The player starts inside the SPHL pod at (20.0, 2.2, −24.7) facing its
## hatch; the store room (zone x[10,16] z[−22,−16]) is the next enclosed space along the wet
## deck, entered through the east archway at x 16, z −17.8..−19.2 — so it is the second
## interior the player is ever inside, and they walk into it rather than having to look for it.
## The pod itself was rejected on measurement, not taste: its only lamp is Color(0.9, 0.15,
## 0.1) at energy 1.6, and no albedo survives a single-channel light (s52) — the spawn probe
## measures that seat at saturation 0.89 and a cat in it is a red silhouette. The pump ready
## room, one further north, is the third interior and reads slightly brighter (0.241) but it
## is the RESPAWN room, which is a different job.
##
## THE SEAT IS THE BRIGHTEST STANDABLE SQUARE OF DECK IN THAT ROOM, and it was gridded, not
## chosen: `tests/CatSpawnProbe` sweeps a 5x5 grid of the floor at night and reports floor
## height, the cat's own `_step_clear`, ceiling height and sampled irradiance with a
## line-of-sight test. Most of the room reads 0.000 — the lantern stands ON the barrels at
## (15.3, −16.7) and the barrels shadow the floor behind them. This point takes 0.297 from it
## at 1.15 m, on real deck (y 2.000, not a crate top — several brighter grid points were
## standing on the stores), under a 3.07 m ceiling, clear of the north door lane
## (x 12.39..13.61) and of the archway.
##
## The Y is PROBED at spawn, never trusted from this constant.
##
## s55, owner's call: FOUND ASLEEP ON A BUNK. Cabin 1 of the bunkhouse north row
## (bunk_layout.bed_pos(1, false) = x -18.0, z 16.8), Y started above the mattress so the
## spawn probe seats her ON the bed, not the floor beside it. The hop down is the perch
## grammar the cat already owns.
const HOME := Vector3(-18.0, 18.7, 16.8)

## WATER RESCUE. The cat got washed out to sea: anything that puts her below the wet-deck
## walking band (a fall through a gap, a shove, a moved deck) ends with her treading water
## the session. Below RESCUE_Y for RESCUE_AFTER seconds -> teleported to the main deck by
## the bunkhouse door, reseated, states reset. The doggy-paddle swim home is a later pass;
## this is the safety net that makes losing her impossible.
const RESCUE_Y: float = 1.2
const RESCUE_AFTER: float = 0.9
const RESCUE_SPOT := Vector3(-6.0, 18.6, 10.0)
var _wet_t: float = 0.0

## THE LEGS LOOKED QUICK BECAUSE THEY WERE, AND THE CAUSE IS ARITHMETIC, NOT ANIMATION.
##
## Cadence is not a free parameter: stride = `_sweep_cap / duty`, and this rig's shortest leg
## caps the sweep at 0.180 m, so a walking stride is 0.327 m and nothing in the cycle tables
## can change that. At the old WALK_SPEED of 1.55 m/s the animal therefore had to take
## 1.55 / 0.327 = 4.7 STRIDES A SECOND. A real cat of this size walks at about two. Every
## attempt to make the walk read slower — retuning the tables, widening the sweep, easing the
## turn — was fighting a cadence set by a speed constant nobody had questioned; 1.55 m/s is a
## brisk TROT for a 0.66 m animal, being drawn with a walk cycle.
##
## 0.95 m/s put it at 2.9 strides/s, which is a walk. It also made the gait bands mean what
## they say for the first time: WALK_V is 1.8, so at 1.55 the "walk" was already 0.86 of the
## way into the walk->trot blend and carrying trot footfall timing. Now it sits at pure walk.
##
## 1.10 m/s (s52), AND THE STRIDE MOVED FIRST. The owner's next note was "step out further, be
## a bit slower, but pull the cat further at a faster rate" — cadence DOWN and speed UP at the
## same time, which is only possible if the stride rises by more than the speed does. It has:
## cat_rig's walk envelope went 0.181 -> 0.232 m (a per-limb derived stance arc plus a measured
## girdle) and the walk duty 0.55 -> 0.52, taking the stride 0.328 -> 0.445 m. At 1.10 m/s that
## is 2.47 strides/s — 15% FEWER steps per second than at 0.95, while covering 16% more ground.
## Raising this constant alone would have done the opposite; it is only safe after the stride.
##
## 1.084 m/s (s53), AND IT IS THE SAME CADENCE, NOT A SLOWER CAT. The girdle yaws came out
## this session — 25.2 degrees of drawn rump swing for 16 mm of stride, which is the owner's
## "wobbles side to side" (cat_rig.PELVIS_YAW has the ledger) — and the pelvic one was in the
## sweep budget, so removing it took the walk envelope 0.2316 -> 0.2233 m and the stride
## 0.4453 -> 0.4293 m. Cadence is `speed / stride`, so holding this constant at 1.125 would
## have quietly RAISED the step rate to 2.62/s. 1.084 keeps it at 2.525 — the number the
## previous session set and the owner signed off.
##   stride 0.4293 m   cadence 2.525 /s   (was 0.4453 m, 2.526 /s at 1.125)
## If the owner would rather have the 3.6% of ground speed back than the cadence, this line
## alone is the choice: 1.125 costs 0.10 strides a second and nothing else.
##
## The cat is genuinely slower on its feet than the player, which is correct and is what
## TROT_SPEED and RUN_SPEED are for — it ambles when it is beside you and trots or runs when
## it has ground to make up. That is the animal; a companion that matches your pace at all
## times is a camera on a stick.
##
## 1.36 m/s (s54) — the owner's "+25% at least", and the extra ground came from the GAIT BAND,
## not from the step rate. A pure walk on this rig cannot deliver it: stride = sweep / duty,
## the walk sweep is capped at 0.2233 m by the binding hind's own ROM and WALK_DUTY 0.52 is
## already at the walk's definitional floor, so 0.4293 m is the longest walking stride there
## is and +25% speed on a PURE walk is +25% cadence — the exact thing s51 and s52 removed.
##
## THE HONEST SPLIT, AND IT IS NOT ALL FREE. cat_rig's speed bands were two sessions stale
## (WALK_V 1.8 / TROT_V 3.4 against constants of 1.084 / 1.9) and are re-sited on the animal's
## real gait transitions, 1.30 and 2.90 — which is what finally makes TROT_SPEED draw a trot
## instead of a walk cycle flogged at 1.9 m/s. At 1.36 the walk sits just inside that band:
##   WALK 1.36  mix 0.038  duty 0.508  stride 0.4364 m  cadence 3.12 /s   (+25.5% ground)
##   TROT 2.38  mix 0.675  duty 0.304  stride 0.6397 m  cadence 3.72 /s   (+25.3% ground)
##   RUN  4.40  mix 1.000  duty 0.200  stride 0.9030 m  cadence 4.87 /s   (unchanged)
## So 2.5 points of the 25 come from a longer stride and the rest is step rate: the cadence goes
## 2.53 -> 3.12 /s, +23%. That is the part the owner should know about, because two turns ago the
## ask was for SLOWER legs. It cannot be had both ways on this rig — the sweep is capped by the
## binding hind's ROM and the duty by the definition of a walk — and the lever is one constant:
## cat_rig.WALK_V at 1.05 instead of 1.30 gives 2.94 /s and a 0.4635 m stride for the same
## 1.36 m/s, at the cost of taking CatReviewProbe's [walk] slide_frame from 9.16 to 12.45
## mm/frame against a 10 mm gate. Its note carries the full decomposition.
##
## Against a real cat: 3.1 strides/s at 1.36 m/s is at the top of the published range for an
## animal this size (2.6-3.1) and 3.7 at 2.38 is inside it; 4.87 at the gallop is NOT (a real
## cat gallops at three to four), which is why RUN_SPEED is left alone — see its note.
const WALK_SPEED: float = 1.36
const TROT_SPEED: float = 2.38       ## when it has fallen behind, or there is fish
const FOLLOW_NEAR: float = 2.2       ## closer than this and it stops walking
const FOLLOW_FAR: float = 14.0       ## further than this and it trots
## (LOST_M is gone: no distance gives up the follow — see the note above the follow
## branch. Parking the cat is the STAY verb's job now, a decision instead of a distance.)
const GREET_M: float = 2.4           ## how close you must come to say hello
const FISH_M: float = 9.0            ## it can smell a fish in your hands from here
const TURN_RATE: float = 6.0
## Further behind than this and the walk becomes a run.
const RUN_M: float = 8.0
## NOT RAISED WITH THE OTHER TWO (s54), and the reason is measured. `stride = sweep / duty` at
## GALLOP_DUTY 0.20 gives 0.903 m, so 4.4 m/s is already 4.87 strides a second — a real cat
## gallops at three to four. The run is the one band that is too FAST for its cycle rather
## than too slow, and +25% here would take it to 6.1 strides/s, which is the 7.5-strides bug
## s45 fixed coming back. Fixing it properly means a longer gallop stride, which means the
## sweep, which means the re-rig (docs/CAT_RIG_CEILING.md §3). Filed, not papered over.
const RUN_SPEED: float = 4.4
## How long the head-bump lean lasts when you pet it.
const PET_SEC: float = 1.1
## Feeding it a raw fish is worth this much comfort, once per game day. Small on purpose —
## it is a moment with an animal, not a food source.
const FED_COMFORT: float = 0.12
const FED_REST: float = 0.06
const STEP_UP: float = 0.45          ## the probe's own reach above the next footfall
## HOW HIGH A STEP IT WILL TAKE. Was STEP_UP, i.e. "coamings yes, stairs no" — the cat
## could not follow the player off the deck they met on, which reads as a pet that gives up
## rather than as a cat. A rig stair tread is well inside this, so it climbs one tread at a
## time; a bunk frame or a wall is still refused.
const CLIMB_UP: float = 0.62
## Taller than CLIMB_UP and up to this, the cat JUMPS instead of refusing. A real cat
## clears five times its shoulder height; this is deliberately far short of that, because
## the failure mode of a generous number is an animal that leaps onto things the level
## design assumed were out of reach.
const JUMP_UP: float = 1.25
const JUMP_SEC: float = 0.52
## Stops a cat that lands just under another lip from jumping every frame forever.
const JUMP_CD: float = 0.9
## HOW FAR IT WILL JUMP DOWN, and the asymmetry is the animal, not an oversight. A cat can
## step off things it could never leap onto — the owner's ask, verbatim, is ten metres — and
## until s52 this file had NO descent path at all. The comment above `_reachable_up` claimed
## "down is never gated"; it was gated, hard, by `_step_clear`: the landing sphere sits
## 0.157 m above the lower deck immediately beside the face the cat is stepping off, needs
## `_body_r()` = 0.117 m of clearance from it, and one walk step is 0.0158 m at 60 fps. Every
## down-step was refused, deterministically, for as long as the cat has existed. The cat on
## the rigging bench could not get off the rigging bench.
const DROP_MAX: float = 10.0
## A fall is not a hop: JUMP_SEC's fixed 0.52 s over a 10 m drop is 19 m/s, which is a
## trebuchet. The flight time comes from the physics instead — t = sqrt(2h/g) — so a step off
## a bench takes 0.43 s and a ten-metre drop takes 1.43 s, and both look like the same
## gravity. JUMP_SEC is KEPT for the up-jump (tests/cat_probe.gd polls `_jump_t` against it).
const DROP_G: float = 9.8
const DROP_SEC_MIN: float = 0.30
const DROP_SEC_MAX: float = 1.7
## The little push-out a cat gives leaving a ledge — it does not simply topple off the edge.
const DROP_HOP: float = 0.10
## Seconds of refused frames, while ABOVE whatever it is walking at, before the descent stops
## asking "is there a way down THIS way" and starts asking "is there a way down at all". The
## stranding escape hatch; every other wedge in this file has one (_detour_stall 0.35,
## _bed_stall 2.5, _trail_stall 0.9).
const DROP_STALL: float = 1.1
## THE SEA. `_reseat` had no `else` branch, so a cat whose seat ray found nothing simply kept
## its old height — and over open water the ray ALWAYS finds nothing, because the ocean
## surface is a shader-displaced visual mesh with no collider. The cat therefore stood at
## DECK_Y over the swell, permanently frozen, which is the owner's "walks on the water".
## Gravity is the honest else: it falls, it hits the sea, and SWIM brings it home.
const FALL_G: float = 12.0
const FALL_VMAX: float = 14.0
## How deep the body rides while treading water, and how fast it paddles. Slower than a walk
## on purpose — a swimming cat is working.
const SWIM_SINK: float = 0.12
## How hard the body chases the moving surface, and the most it may ever lag behind it.
const SWIM_RISE: float = 14.0
const SWIM_LAG_MAX: float = 0.20
## Under `_drive_rig`'s 0.8 m/s look-suppression threshold on purpose: a swimming cat must be
## able to look at the place it is trying to reach, and that gate would otherwise cut the head
## off exactly the one state whose whole tell is where it is looking.
const SWIM_SPEED: float = 0.70
## How often it looks for somewhere to climb out, and how far it looks.
const SWIM_SCAN_CD: float = 0.45
const BOARD_SCAN_M: float = 6.0
## The stand mesh's longest-axis target, hull-volume-equalised against walk@0.66 (s36's
## sizing method, one entry now that there is one mesh). Recomputed if the base mesh is
## ever re-rolled: tools/extract_cat_poses.py prints the reminder.
const STAND_SIZE_M: float = 0.66   ## nose-to-tail parity with the walk mesh's 0.66

## Seconds of stillness from the player before the cat decides this is a rest, not a pause.
const SETTLE_SEC: float = 6.0
## ...and how long it then sits before lying down properly.
const DOZE_SEC: float = 22.0

var friend: bool = false
var _state: int = State.GROOM
var _t: float = 0.0
var _still: float = 0.0
var _last_player_pos: Vector3 = Vector3.ZERO
var _gen_mats: Array = []
var _body: Node3D
## pose key -> the Node3D holding that mesh, and its ShaderMaterials.
## THE one drawn body. Kept as a single node rather than a dictionary of them because a
## dictionary of bodies is what made transitions teleports.
var _host: Node3D = null
var _pose: String = ""
## Petting: how long the head-bump lean lasts, and when the next purr is allowed.
var _pet_t: float = 0.0
## Feeding: the absolute GAME HOUR the cat was last fed, so "once per game day" survives a
## night's sleep. Measured in game hours rather than delta seconds for the reason
## KNOWN_ISSUES records about the mussel beds: sleeping advances the calendar and no real
## time passes, so a countdown in seconds sits through five slept nights unchanged.
var _fed_game_h: float = -1000.0
## Counts down after a feed — the happy wiggle, the seal's _pet_bump idea on a cat.
var _fed_wiggle: float = 0.0
var _touch: Interactable
var _ai_acc: float = 0.0
var _rng := RandomNumberGenerator.new()
var _meow_cd: float = 0.0
var _seated_y: float = 0.0
## pose key -> CatRig, for the poses whose GLB carried a skin. Empty for any that fell back
## to the static mesh, and every call site tolerates a missing entry.
var _rig = null   ## the cat_rig.gd blender driving _host's skeleton
## What the cat is currently paying attention to, in world space, and how strongly. This is
## the "every state should have a focus" the owner asked for: the head tracks it even when
## the body does not turn.
var _focus: Vector3 = Vector3.ZERO
var _focus_w: float = 0.0
## Signed slope of the ground under the last step, radians. Drives the body pitch so the cat
## leans into a climb and noses down a descent instead of staying level through both.
var _slope: float = 0.0
## The speed the last step was actually taken at, so the gait picks its footfall pattern
## from what the body did rather than from what a state hoped it would do.
var _last_speed: float = 0.0
## Metres the body ACTUALLY covered this frame — the blender's gait phase runs off this,
## never off commanded speed, so a blocked cat's legs stop instead of treadmilling.
var _moved_frame: float = 0.0
## Last frame's node yaw, so the rig can be told how fast the body is really turning.
var _yaw_prev: float = 0.0
## Detour commitment (see _walk_toward's fan): which side it last went around an obstacle,
## and how long that preference lasts. Order-bias only — never a hard constraint.
var _detour_side: float = 0.0
var _detour_t: float = 0.0
## Seconds of fully-refused frames — past 0.35 the animal backs out of the pocket.
var _detour_stall: float = 0.0
## The stair-grade window: rise and run accumulated with ~0.45 m distance decay, so a
## staircase reads as its true grade instead of a once-a-tread flicker.
var _grade_dy: float = 0.0
var _grade_run: float = 0.0
## STAY/COME — the owner's follow toggle. While true the cat holds its own patch (the spot
## it was told to stay at) and lives its own life there; a COME (or any re-greeting after
## time away) releases it.
var _stayed: bool = false
var _stay_spot: Vector3 = Vector3.ZERO
## THE HUNT. `_hunt` is the beat of the predatory sequence, not a boolean: 0 idle, 1 stalking,
## 2 treading (the wiggle), 3 in the air, 4 the aftermath.
## (There are THREE beats, not five. "4 the aftermath" above was never assigned anywhere in the
## file and `_hunt_step`'s match had no arm for 3 either — see the `_:` arm there.)
var _prey: Node3D = null
var _hunt: int = 0
var _wiggle_t: float = 0.0
var _freeze_t: float = 0.0        ## a stalking cat stops dead whenever it thinks it was seen
var _hunt_cd: float = 8.0
var _after_t: float = 0.0         ## the "I meant to do that" wash after a miss
var _pouncing: bool = false       ## this leap is a pounce, so the landing has to resolve it
var _carry: String = ""           ## what it is bringing you
var _chatter_cd: float = 0.0
## The zoomies, and object play — the other two things a cat does that nothing else on this
## rig does. Both are on cooldowns rather than dice per frame, so they read as events.
var _zoom_t: float = 0.0
var _zoom_cd: float = 30.0
var _zoom_to: Vector3 = Vector3.ZERO
var _play_t: float = 0.0
var _play_cd: float = 20.0
var _play_spot: Vector3 = Vector3.ZERO
## Waking up is a beat of its own: a cat that has been asleep STRETCHES before it walks.
var _stretch_t: float = 0.0
var _was_asleep: bool = false
## ENERGY, 0..1 — the thing that makes one evening different from the next.
##
## Everything the cat does for its own reasons (play, the zoomies, hunting, how long it will
## sit before it lies down) is gated on this rather than on a bare cooldown, so the animal has
## lively spells and lazy ones instead of firing every behaviour on a metronome. It falls with
## exertion, recovers with rest, and is pushed up hard at dawn and dusk — cats are crepuscular
## and the evening madness is the single most predictable thing about them.
var _energy: float = 0.6
## IDLE ATTENTION. A settled cat is not a statue: it looks at things, holds the look for a
## while, and looks somewhere else. `_glance_cd` is when it next picks something.
var _glance_cd: float = 1.0
var _glance_at: Vector3 = Vector3.ZERO
var _glance_hold: float = 0.0
## SELF-GROOMING. `_wash_t` is how long this bout has left and `_wash_style` which of the four
## it is; a cat washing its flank for six seconds and then its ear is a different animal from
## one running the same paw-lick loop for ever.
var _wash_t: float = 0.0
var _wash_style: int = 0
var _wash_cd: float = 12.0
var _shake_cd: float = 25.0
## Small per-frame speed variation, so the walk is not metronomic.
var _pace: float = 1.0
var _pace_cd: float = 0.0
## The occasional seated weight-shift: a settled cat re-plants its weight every ten or
## twenty seconds, irregularly — the difference between an animal at rest and a loop.
var _shift_cd: float = 8.0
var _shift_t: float = 0.0
var _shift_dur: float = 1.0
var _shift_amp: float = 0.0
## The held sleeping spot — picked once when the player turns in, cleared when they rise.
var _sleep_target: Vector3 = Vector3.ZERO
## How long it has been walking at the chosen spot without getting any closer, and the best it
## has managed — a held target it cannot reach is a cat that paces all night (see `_bed_down`).
var _bed_stall: float = 0.0
var _bed_best: float = 1e9
## The leap, in flight: time left, and the two ends of the arc. While `_jump_t` is positive
## the state machine hands the animal over to _fly_jump and nothing else moves it.
var _jump_t: float = 0.0
var _jump_cd: float = 0.0
## The anticipation: a jump is armed, the crouch is held, and the body has NOT left the
## deck yet. §-minimum 8 frames — the loaded spring is the beat that sells the leap, and
## the old jump skipped it entirely (airborne on the frame it decided).
var _jump_wind: float = 0.0
var _jump_from: Vector3 = Vector3.ZERO
var _jump_to: Vector3 = Vector3.ZERO
## HOW LONG THIS PARTICULAR FLIGHT LASTS. `_fly_jump` used to divide by the JUMP_SEC constant
## whatever `_jump_t` had been set to, which was already wrong before the drop existed: a
## pounce sets POUNCE_SEC (0.42) and the arc therefore STARTED at k = 1 - 0.42/0.52 = 0.19,
## i.e. the animal teleported a fifth of the way along its own leap on the first airborne
## frame. One duration, set wherever the flight is armed, read in exactly one place.
var _jump_dur: float = JUMP_SEC

## THE GET-UP-AND-TURN BEAT (see `_begin_restand`). `_restand_t` counts the whole thing down
## and owns the animal while it is positive; `_restand_sit` is the seat it will drop back into,
## so a grooming cat re-grooms and a perched one re-perches instead of everything becoming a
## plain sit.
var _restand_t: float = 0.0
var _restand_yaw: float = 0.0
var _restand_sit: int = State.SIT
var _restand_cd: float = 0.0
## Seconds spent refused while standing above what it is trying to reach — see DROP_STALL.
var _drop_stall: float = 0.0
## The fall. Non-zero only while the cat is off the world with nothing under it.
var _fall_v: float = 0.0
## SWIM: when it next looks for a way out, and the lip it found (INF for none).
var _swim_scan: float = 0.0
var _board: Vector3 = Vector3.INF
## The last place the seat ray found real ground. A cat in the water steers at this when it
## cannot see a boarding lip from where it is floating — it is the only point in the world
## this animal can prove it was once standing on.
var _last_ground: Vector3 = Vector3.INF
## THE BAIT TRAIL — the player's recent footsteps, oldest crumb first. Written by
## `_physics_process` (a recording, so it is never decimated) and read by `_trail_goal`.
var _trail: PackedVector3Array = PackedVector3Array()
## Last tick's player position, for the teleport break. INF means nothing sampled yet.
var _trail_prev: Vector3 = Vector3.INF
## True while the cat is steering at a CRUMB rather than at the player, so the follow branch
## knows whether `stop_at` means "short of the player" or "onto the waypoint".
var _trail_live: bool = false
## Seconds pinned on the same crumb — past TRAIL_STALL the thread is walked on anyway.
var _trail_stall: float = 0.0
## The string-pull's throttle, and a LATCH on its verdict: re-deciding a shortcut every frame
## is the same oscillation the detour fan's 0.8 s side commitment exists to stop.
var _pull_cd: float = 0.0
var _pull_free: bool = false
## The turn ease — 1.0 on a straight, TURN_EASE_MIN going into a right-angle doorway.
var _turn_slow: float = 1.0

func _ready() -> void:
	_rng.seed = 5150
	# THE DECISION STREAM IS ITS OWN STREAM — see BEHAVIOUR_SEED, down with the instinct layer.
	_brng.seed = BEHAVIOUR_SEED
	add_to_group("ship_cat")
	_body = Node3D.new()
	add_child(_body)
	# Every pose, attached once, all hidden but the first. Each one carries its own facing
	# (cat_sit and cat_groom are authored along +X, the rest along +Z — measured s34, see
	# CreatureAnim.FACING_OVERRIDES) and each is GROUNDED so its paws sit on the deck rather
	# than its origin: the five poses have wildly different heights, and a curled sleeping
	# cat centred like a standing one floats.
	# ONE host, ONE skeleton. attach_rigged keeps the imported PBR materials and stops
	# Tripo's baked clip; the pose library and every transition live in cat_rig.gd.
	var host := Node3D.new()
	_body.add_child(host)
	var pg: Dictionary = ANIM.attach_rigged(host, BASE_RIGGED, _pose_size("stand"))
	if pg.is_empty() or pg.get("skeleton") == null:
		if not pg.is_empty():
			(pg["model"] as Node3D).queue_free()
		pg = ANIM.attach_rigged(host, BASE_FALLBACK, _pose_size("stand"))
	var skel: Skeleton3D = pg.get("skeleton") as Skeleton3D if not pg.is_empty() else null
	if skel != null:
		_rig = RIG.new(skel, POSE_LIBRARY)
		if _rig != null and not _rig.valid():
			_rig = null
	if not pg.is_empty():
		ANIM.ground(host, pg["model"])
		_host = host
	else:
		host.queue_free()
	var gen: Dictionary = {"mats": []} if _host != null else {}
	if _rig != null:
		_wear("groom")
	if gen.is_empty():
		# No mesh on disk yet: a placeholder that still reads as a small four-legged animal,
		# so the behaviour can be played and tested before the asset lands.
		var m: Material = BloomFauna.glow_mat(Color(0.42, 0.40, 0.38), 0.0)
		KIT.ball(_body, Vector3(0, 0.20, 0), 0.22, m, Vector3(1.0, 0.9, 2.0))    # body
		KIT.ball(_body, Vector3(0, 0.30, -0.24), 0.13, m)                        # head
	else:
		_gen_mats = gen["mats"]
	# The interaction handle. Same contract every other creature uses, so the crosshair, the
	# prompt chip and the interaction ray all find it with no special cases.
	_touch = Interactable.new()
	_touch.display_name = "Ship's Cat"
	# The VERBS LIVE ON THE INTERACTABLE, not on this node. interaction_ray reads
	# `available_verbs()` off the collider it hit, which is the Interactable child — a method
	# of the same name on the parent is never consulted, so the prompt would have read the
	# base class's default "USE" while this script thought it was offering a greeting.
	_touch.verbs = ["SAY HELLO"] as Array[String]
	add_child(_touch)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.5, 0.7)
	col.shape = box
	col.position.y = 0.25
	_touch.add_child(col)
	# YOU CAN WALK THROUGH THE CAT. An Interactable is a StaticBody3D and nothing here ever
	# set its layer, so it sat on the default layer 1 — the layer the player's own capsule
	# masks — and a 0.6 x 0.5 x 0.7 solid box stood in the middle of the bunkhouse aisle.
	# Being physically stopped by a cat reads as a bug in a way that being stopped by a
	# crate does not, and the owner asked for it explicitly.
	#
	# It moves to layer 3 rather than to NO layer, because the layer is how the game finds
	# it: InteractionRay casts against a mask, and bloom_fauna's existing lever
	# (`collision_layer = 1 if solid else 0`) would make the animal unpettable as well as
	# unblocking. Layer 3 was unused by anything in this project, and InteractionRay now
	# masks 1 | 3 — so the cat is reachable by the crosshair and invisible to the capsule.
	#
	# The seat ray is a separate matter and stays excluded by RID (see _reseat): the cat
	# must not stand on itself even on a layer the player ignores.
	_touch.collision_layer = InteractionRay.INTERACT_LAYER
	_touch.collision_mask = 0
	_touch.interacted.connect(_on_touched)
	# PROBED, NOT TYPED. HOME's Y is the bunkhouse deck as authored, and every floating-prop
	# bug in this repo came from trusting exactly that kind of constant. Deferred because CSG
	# decks have no collider on the frame they enter the tree (see surface_snap.gd).
	global_position = HOME
	call_deferred("_seat")

## THE SEAT RAY MUST EXCLUDE THE CAT'S OWN HANDLE, and for two sessions it did not.
##
## `_touch` is an Interactable, i.e. a StaticBody3D on the default layer, carrying a
## 0.6 x 0.5 x 0.7 box centred 0.25 m above the feet. This ray drops from +1.2 with
## `collision_mask = 1` and no exclusions, so the FIRST thing it hit was the top face of
## that box at +0.50 — and the cat was then "seated" exactly 0.500 m in the air, every
## time, deterministically. That is the owner's "cat is found floating".
##
## The reason it looked intermittent — "floating UNTIL the player says hello" — is that the
## other two rays in this file already exclude the handle (`_walk_toward` and
## `_sleep_spot`), so the moment the cat took its first step it re-seated itself correctly
## and the bug vanished. Befriending it was never the cure; walking was.
func _seat() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_reseat()

## Put the cat on whatever is under it, right now. Called at spawn and then every frame it
## is NOT walking — because `_walk_toward` is the only thing that used to re-ground it, so
## a cat that stands still on a deck another session moves would hang in the air until it
## happened to take a step.
##
## ...AND IT HAD NO `else`, WHICH IS THE WHOLE OF "THE CAT WALKS ON THE WATER".
##
## When the ray finds nothing this used to silently keep the previous height and return, and
## it is called from a dozen sites, so it FAILED OPEN every time. Over open sea the ray always
## finds nothing — the ocean surface is a shader-displaced visual mesh with no collider — so a
## cat that left the deck horizontally (a play spot drawn blind over the side, a pounce at a
## gull on the rail) stood at DECK_Y 18.0 above the swell for the rest of the session, frozen:
## `_walk_toward` gets an empty deck hit and returns, `_unbury` finds nothing to push out of,
## and this held the height.
##
## A no-hit reseat is not a null result, it is a FINDING — the animal is off the world. It
## returns that finding now, and `_fall_step` acts on it.
func _reseat() -> bool:
	var world: World3D = get_world_3d()
	if world == null:
		return true
	var from: Vector3 = global_position + Vector3(0, 1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 4.0, 0))
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = [_touch.get_rid()]
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	global_position.y = (hit["position"] as Vector3).y
	_seated_y = global_position.y
	# PROVEN GROUND, REMEMBERED. The one point this animal can show its own working on, and
	# the only thing a cat adrift in the sea has to steer at.
	if not _over_water(global_position):
		_last_ground = global_position
	return true

## Kept for probes and for anything that asks the CAT rather than its handle; the handle's own
## `verbs` is what the interaction ray reads, and both are set together in _sync_verbs.
func available_verbs() -> Array:
	if not friend:
		return ["SAY HELLO"]
	return ["PET", "COME"] if _stayed else ["PET", "STAY"]

func _sync_verbs() -> void:
	var v: Array[String] = []
	for s in available_verbs():
		v.append(String(s))
	_touch.verbs = v

## `Interactable.interacted` carries ONE argument — the verb. It does not pass the player, so
## the player is looked up here; connecting a two-argument handler silently fails to fire at
## all, which is exactly what made the first version of this cat unbefriendable.
func _on_touched(verb: String) -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if not friend:
		friend = true
		_enter(State.FOLLOW)
		_sync_verbs()
		Journal.discover("creature_ship_cat")
		AudioDirector.play_one_shot("cat_chirp", global_position, -18.0)
		if hud and hud.has_method("toast"):
			hud.toast("The cat looks up, decides about you, and comes along.")
		return
	# THE FOLLOW TOGGLE — the owner's ask, verbatim: the player can tell it to stop
	# following; it then does its own thing; coming back and interacting perks it up and
	# it follows again. STAY anchors it to the spot it was told at (see _stay_behaviour);
	# COME — or, for the player who forgot which verb they left it on, any fresh greeting
	# — releases it with the little perk-up a cat gives someone it decided to keep.
	if verb == "STAY":
		_stayed = true
		_stay_spot = global_position
		_sync_verbs()
		_enter(State.SIT)
		AudioDirector.play_one_shot("cat_chirp", global_position, -22.0)
		if hud and hud.has_method("toast"):
			hud.toast("The cat blinks slowly, and settles in to keep its own counsel.")
		_meow_cd = 4.0
		return
	if verb == "COME":
		_stayed = false
		_sync_verbs()
		_enter(State.FOLLOW)
		_stretch_t = 0.0
		if _rig != null:
			_rig.call("delight", 0.7)      # the perk-up: ears would go up if it had them
			_rig.call("tail_flick", 0.8)
		AudioDirector.play_one_shot("meow", global_position, -14.0)
		if hud and hud.has_method("toast"):
			hud.toast("The cat perks up and falls in beside you.")
		_meow_cd = 4.0
		return
	# PETTING IS REPEATABLE, which is the whole point of it — the s32 cat offered PET and
	# then did nothing observable, so there was no reason to press it twice.
	_pet_t = PET_SEC
	AudioDirector.play_one_shot("purr", global_position, -14.0)
	if player != null and is_instance_valid(player):
		_face(player.global_position, 1.0)
	# ...and if you are holding a raw fish when you do it, that is FEEDING it. Once per game
	# DAY, counted in absolute game hours: sleeping advances the calendar without any real
	# time passing, so a cooldown in seconds would sit through a slept night untouched
	# (KNOWN_ISSUES records the same trap costing the mussel beds a regrowth cycle).
	var now_h: float = GameClock.game_time_hours()
	if _player_holding_fish(player) and now_h - _fed_game_h >= 24.0:
		var slot: int = PlayerState.selected_hotbar
		var fish_id: String = String(PlayerState.hotbar[slot])
		if PlayerState.remove_item(fish_id):
			_fed_game_h = now_h
			_fed_wiggle = 1.0
			PlayerState.comfort = clampf(PlayerState.comfort + FED_COMFORT, 0.0, 1.0)
			PlayerState.rest = clampf(PlayerState.rest + FED_REST, 0.0, 1.0)
			AudioDirector.play_one_shot("eat", global_position, -16.0)
			if hud and hud.has_method("toast"):
				hud.toast("The cat takes the fish, and is briefly very pleased with you.")
			_meow_cd = 2.0
			return
	if hud and hud.has_method("toast"):
		hud.toast("The cat leans into your hand.")
	_meow_cd = 6.0

func _process(delta: float) -> void:
	# Four-line AiBudget prologue — mandatory for anything new that runs per frame here, and
	# it hands back the SUM of the frames it skipped so the animal covers the same ground per
	# second rather than moving at 1/N speed (ai_budget.gd explains the trap).
	_ai_acc += delta
	if not AIB.due(self, _ai_acc):
		return
	delta = _ai_acc
	_ai_acc = 0.0
	_t += delta
	# Water rescue watchdog — see RESCUE_Y above. Cheap: one float compare a think.
	if global_position.y < RESCUE_Y:
		_wet_t += delta
		if _wet_t > RESCUE_AFTER:
			_wet_t = 0.0
			global_position = RESCUE_SPOT
			_reseat()
	else:
		_wet_t = 0.0
	if _meow_cd > 0.0:
		_meow_cd -= delta
	if _pet_t > 0.0:
		_pet_t -= delta
	# EVERY FRAME STARTS FROM A CLEAN BODY, and this is the whole of "it does not walk
	# straight". `_groom` wrote `_body.rotation.x` and `_pose_sit` wrote `_body.rotation.y`,
	# and NOTHING ever cleared either — only roll was eased home. So the cat picked up a few
	# degrees of permanent pitch the moment you met it, and a yaw skew off its direction of
	# travel every time it sat down, and carried both for the rest of the session. Each
	# state now writes the offsets it wants onto a body that is already neutral.
	# Every ease in this file is `1 - exp(-rate * dt)`: this animal runs under AiBudget and
	# is handed SUMMED deltas up to 0.15 s, where `delta * k` overshoots — measured as the
	# whole cat snapping to its turn/lean targets in one think (tests/CatReviewProbe bigdt:
	# the two dt paths disagreed by 19.7 deg on the same half-second of slope ease).
	# THE BODY NODE IS NOT AN ANIMATION CHANNEL — held at rest, permanently, and asserted
	# by tests/CatJointProbe (body_node_rot_max_deg < 1). Thirteen lines in this file used
	# to rotate and lift the whole animal about its own origin to express things a cat
	# expresses with its spine: the owner's "the game rotates the entire cat instead of
	# moving a limb". Every one of them now calls the rig instead (cat_rig section 5f).
	# The ONLY whole-animal transforms left in this file are the ones that are genuinely
	# whole-animal: the steering yaw in `_face`, and the jump arc's translation.
	_body.rotation = Vector3.ZERO
	_body.position = Vector3.ZERO
	if _fed_wiggle > 0.0:
		_fed_wiggle -= delta * 0.7
		if _rig != null:
			_rig.call("delight", clampf(_fed_wiggle, 0.0, 1.0))
	# A SLOPE ONLY EXISTS UNDER A WALKING CAT. _walk_toward is the only writer, so an animal
	# that stopped on a ramp wore the ramp's pitch for ever — sitting, sleeping, being petted
	# — because nothing ever decayed it. Ease it home whenever the body is not travelling.
	if _last_speed < 0.05:
		_slope = lerpf(_slope, 0.0, 1.0 - exp(-4.0 * delta))
	# The lean into a grade is a TRUNK pitch now (cat_rig.slope): the node version tipped
	# the animal as a plank and left its paws intersecting the ramp, because nothing under
	# it re-solved. Pitching the chest lets the four legs solve to the ground they are
	# actually on.
	if _rig != null:
		_rig.call("slope", _slope)
	_focus_w = maxf(0.0, _focus_w - delta * 1.5)
	# BEFORE ANYTHING ELSE DECIDES WHERE TO GO, GET OUT OF WHATEVER WE ARE IN. Unconditional
	# and state-independent on purpose: a predictive gate cannot rescue an animal that is
	# already buried, and every gate in this file is predictive.
	_unbury()
	if _jump_cd > 0.0:
		_jump_cd -= delta
	# THE WIND-UP: crouched, loaded, still on the deck. Owns the animal like the flight
	# does, so nothing walks it off its own launch spot mid-anticipation.
	if _jump_wind > 0.0:
		_jump_wind -= delta
		_last_speed = 0.0
		if _jump_wind <= 0.0:
			_jump_t = _jump_dur
			_enter(State.JUMP)
			AudioDirector.play_one_shot("cat_chirp", global_position, -24.0)
		_drive_rig(delta)
		return
	# A LEAP OWNS THE ANIMAL UNTIL IT LANDS. Taken before the state machine, so nothing
	# downstream can re-seat the cat onto the deck it just left — which is what would
	# otherwise cancel the jump on its first airborne frame.
	if _jump_t > 0.0:
		_fly_jump(delta)
		_drive_rig(delta)
		return
	# THE SEA OWNS THE ANIMAL TOO, and it is checked HERE — above the player lookup and above
	# the friend/_companion fork — for three reasons. It has to be reachable from the
	# companion, from `_stay_behaviour` and from the not-friend `_groom` path, because a cat
	# can end up in the water in any of them. It has to work with NO player: the follow
	# contract is why `_reachable_up` refuses to climb when nobody is there, and drowning is
	# not a thing to be polite about. And it must sit below the two jump blocks, because a
	# leap that legitimately passes over water is not a cat in the water.
	if _over_water(global_position):
		_swim(delta)
		_drive_rig(delta)
		return
	# ...AND NOTHING UNDER IT AT ALL IS THE OTHER HALF. See `_reseat`: no ground within reach
	# means the animal is off the world, and the honest answer to that is gravity.
	if _fall_step(delta):
		_drive_rig(delta)
		return
	# GETTING UP TO TURN ROUND OWNS THE ANIMAL, exactly as the wind-up and the flight do, and
	# it is placed with them — above the state machine — so nothing downstream can re-enter
	# the sit and cancel the beat on its own first frame.
	_restand_cd = maxf(0.0, _restand_cd - delta)
	if _restand_t > 0.0:
		_restand_step(delta)
		_drive_rig(delta)
		return
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if not friend:
		_groom(delta, player)
		_drive_rig(delta)
		return
	_companion(delta, player)
	_drive_rig(delta)

## The arc. A jump is not a lerp: a straight line between two points reads as an animal
## being slid up a ramp. The horizontal runs linearly and the vertical carries a parabola
## over the top, so the cat rises clear of the lip it is clearing and comes down onto it.
func _fly_jump(delta: float) -> void:
	_jump_t -= delta
	# `_jump_dur`, not JUMP_SEC — a ten-metre drop and a hop onto a crate are not the same
	# flight, and the pounce was never 0.52 s either (see `_jump_dur`).
	var k: float = clampf(1.0 - _jump_t / maxf(_jump_dur, 0.05), 0.0, 1.0)
	var flat: Vector3 = _arc_point(_jump_from, _jump_to, k)
	# (The `lift` local that used to sit here was dead: `_arc_point` owns the vertical, and
	# has since s47 — it was a leftover of the two-copies-of-the-formula era this file's own
	# comment warns about. Its live twin is `lift2` below, which the slope tangent reads.)
	var before_fly: Vector3 = global_position
	var descending: bool = _jump_to.y < _jump_from.y - 0.02
	global_position = flat
	# A LEAP TURNS THE SAFETY NET OFF, AND THAT IS WHY IT NEEDS ONE OF ITS OWN.
	#
	# `_unbury` runs unconditionally every frame precisely because no predictive gate can
	# rescue an animal that is already inside something — but it runs BEFORE this, and this
	# then overwrites the position it just corrected. So for the whole flight the one check
	# that cannot be fooled is disabled, and `_arc_clear`'s four samples are all that stands
	# between the cat and a bulkhead. Four samples are not a proof: the probe kept catching
	# the animal ~750 mm inside the quarters at 90% of an arc whose endpoints tested clear.
	#
	# So the arc gives up the moment it stops being clear, rather than flying on and hoping.
	# The cat drops where it last fitted, which is a slightly disappointing leap and never a
	# cat in a wall.
	if not _step_clear(global_position, (_jump_to - _jump_from).normalized()):
		global_position = before_fly
		_jump_t = 0.0
		_jump_cd = JUMP_CD
		# AND THE ABORT MUST NOT LEAVE THE CAT IN MID-AIR. `_reseat`'s ray reaches 2.8 m below
		# the feet — shorter than a fall it is now allowed to take — so aborting at 40% of a
		# ten-metre drop used to hang the animal in the sky with no ground under it and no
		# path back. The probed landing is the one point on this arc that has been proven to
		# be solid, dry and body-sized; take it. (`_fall_step` would catch the case anyway,
		# and does for any route that reaches here without a `_jump_to`, but arriving on the
		# spot it aimed at is a leap that fell short rather than a cat that fell.)
		if not _reseat():
			global_position = _jump_to
			_reseat()
		if _pouncing:
			_resolve_pounce()
		return
	_moved_frame += global_position.distance_to(before_fly)
	_face(_jump_to, delta * 2.0)
	_last_speed = RUN_SPEED
	# THE FLIGHT IS PHASED, NOT A FREEZE-FRAME — the owner's leap, beat for beat: push off
	# the hinds, sprawl through the top, then front feet reaching first into the landing.
	# One static mid-air stretch across the whole arc read as an animal hung from a wire.
	# `play_seq([], pose, rate)` is the grammar-free pose set (the family grammar would
	# route jump -> jump_descend through the sit machinery).
	#
	# A DROP IS THE SAME FOUR POSES ON A DIFFERENT CLOCK. Going up, most of the flight is the
	# sprawl and the reach is the last third. Coming down there is barely a push-off and the
	# whole middle of the fall is `jump_descend` — fores reaching long and DOWN, nose over the
	# paws — which is precisely "landing on its feet" and is why no new pose was authored for
	# any of this. (`play_seq`/`set_pose` no-op SILENTLY on a name that is not in the library,
	# so a typo here gives a cat falling in its walk pose and no error anywhere.)
	if _rig != null:
		var k_launch: float = 0.14 if descending else 0.24
		var k_reach: float = 0.34 if descending else 0.60
		if k < k_launch:
			_rig.call("play_seq", [], "jump_launch", 16.0)
		elif k < k_reach:
			_rig.call("play_seq", [], "jump", 14.0)
		else:
			_rig.call("play_seq", [], "jump_descend", 14.0)
		# ...AND THE BODY ROTATES THROUGH THE ARCH. The trunk pitch follows the arc's own
		# tangent — nose-up on the way up, level over the top, nose-down into the descent —
		# through the same skeletal slope channel the ramps use, so it is chest-and-pelvis
		# rotation, never the node. The stabiliser keeps the HEAD level on top of it, which
		# is exactly the flat-eyed arc every slow-motion cat jump shows.
		#
		# ON A DESCENT THE TANGENT IS TAKEN FROM `_arc_point` ITSELF rather than from the
		# closed form beside it. `maxf(rise, 0.0)` is zero for every drop, so the expression
		# below returns atan2(0, horiz) = 0 — a cat falling ten metres, dead level, all the
		# way down. Differencing the shared arc function cannot disagree with the path
		# actually flown, which is the rule this file learned the hard way in s47; the up
		# branch keeps its own expression only because a render pass is in flight against it.
		if descending:
			var a0: Vector3 = _arc_point(_jump_from, _jump_to, maxf(k - 0.06, 0.0))
			var a1: Vector3 = _arc_point(_jump_from, _jump_to, minf(k + 0.06, 1.0))
			var dv: Vector3 = a1 - a0
			_rig.call("slope", atan2(dv.y, maxf(Vector2(dv.x, dv.z).length(), 0.02)) * 0.85)
		else:
			var horiz: float = maxf(Vector2(_jump_to.x - _jump_from.x,
				_jump_to.z - _jump_from.z).length(), 0.2)
			var lift2: float = maxf(_jump_to.y - _jump_from.y, 0.0) * 0.35 + 0.14
			_rig.call("slope", atan2(PI * cos(k * PI) * lift2, horiz) * 0.85)
	if _jump_t <= 0.0:
		global_position = _jump_to
		# JUMP_CD exists to stop a cat that lands just under another lip from jumping every
		# frame for ever, which is an UP problem. A cat coming down a flight of coamings has
		# somewhere to be; 0.9 s between 0.2 m steps down is a companion in slow motion. So the
		# cooldown is proportional on a descent and untouched on a climb.
		_jump_cd = JUMP_CD
		if descending:
			_jump_cd = JUMP_CD * clampf((_jump_from.y - _jump_to.y) / 1.2, 0.22, 1.0)
		# LAND ON THE PROBED SPOT, not on whatever a 4 m ray can see from it. `_reseat` reaches
		# 2.8 m below the feet, which is fine at the top of a crate and useless at the bottom
		# of a ten-metre drop if the landing happens to be a grating edge the ray misses — and
		# its old failure mode was to keep the OLD height, i.e. to leave the cat in the air.
		# `_jump_to` was probed and volume-tested before the animal committed to any of this.
		if not _reseat():
			global_position = _jump_to
		_fall_v = 0.0
		_drop_stall = 0.0
		# LAND -> SETTLE: fore-paws-first absorption held a beat, then the state's own pose.
		# THE ABSORPTION GROWS WITH THE DROP. A cat stepping off a bench takes the landing on
		# its forepaws and walks on; one arriving from four metres crumples through the whole
		# forehand and takes a beat to unfold. Same pose, longer hold — 0.16 s at a hop,
		# 0.34 s off the top of DROP_MAX.
		if _rig != null:
			var fell: float = maxf(_jump_from.y - _jump_to.y, 0.0)
			_rig.call("play_seq",
				[["jump_land", 0.16 + 0.18 * clampf(fell / DROP_MAX, 0.0, 1.0), 14.0]],
				String(STATE_POSE.get(_state, "stand")), 8.0)
			_rig.call("tail_flick", 0.8)   # the counterweight swinging through touchdown
		# A POUNCE RESOLVES WHERE IT LANDS, not where it was aimed. Done here rather than in
		# the state machine because the leap deliberately owns the animal until touchdown, so
		# this is the only frame that knows whether the cat is standing on the bird.
		if _pouncing:
			_resolve_pounce()

## Before you find it: sitting where it lives, washing a paw, looking up when you get close.
##
## ...AND UNTIL NOW THAT SENTENCE WAS A PROMISE THE CODE DID NOT KEEP. `_process` hands the whole
## pre-friend path to this function and returns, so `_tick_energy`, `_idle_attention`, the wash,
## the shake, the seated weight-shift and every cooldown decay were unreachable BEFORE the player
## says hello — i.e. for the one stretch of the game the file's opening paragraph is actually
## about ("It is in the bunkhouse from the first minute of a run, sitting on the deck washing a
## paw, and it stays there until somebody says hello"). What shipped was a statue in the groom
## pose that turned its head. The instinct layer runs here too now, with the two actions that
## would carry it off its spot withheld: a cat that has not decided about you does not get up
## and follow you round the room, but it does wash, scratch, stretch, shake, stare at gulls and
## doze off.
func _groom(delta: float, player: Node3D) -> void:
	var d: float = global_position.distance_to(player.global_position)
	# The drives the companion path decays every frame. Spelled out here rather than hoisted
	# into `_process` so there is no chance of a double decrement on the friend path.
	_wash_cd = maxf(0.0, _wash_cd - delta)
	_shake_cd = maxf(0.0, _shake_cd - delta)
	_tick_energy(delta)
	_idle_attention(delta, player.global_position, d)
	# Anchored on ITSELF: a stranger has no leash to be at the end of, and `allow_roam` false
	# keeps both of the actions that could take it anywhere off the menu.
	if _idle_step(delta, global_position, 99.0, true):
		return
	_enter(State.GROOM)
	# It has not moved, so it must still be on the deck — the seat ray is the only thing
	# that grounds a cat that never walks, and before s35 it ran exactly once, at spawn,
	# against its own collider.
	_reseat()
	_last_speed = 0.0
	if d < GREET_M * 2.5:
		_face(player.global_position, delta)   # it has noticed you
		_watch(player.global_position + Vector3(0, 1.2, 0), 1.0)
	elif d < FISH_M * 2.0:
		# Further off it does not turn, but it does LOOK — a cat clocks you from across a
		# room without getting up, and this is the cheapest thing that says it is alive.
		_watch(player.global_position + Vector3(0, 1.2, 0), 0.55)
	# The wash itself is entirely skeletal (cat_rig's groom layer drives the neck, head and
	# forepaw); the node sway that used to ride on top of it was the whole animal rocking
	# on its own origin with four paws welded flat, which is what made grooming read oddly.
	_idle_tick(delta, false)

## After: it comes with you, at its own pace, and settles when you do.
func _companion(delta: float, player: Node3D) -> void:
	var ppos: Vector3 = player.global_position
	var d: float = global_position.distance_to(ppos)
	_hunt_cd = maxf(0.0, _hunt_cd - delta)
	_zoom_cd = maxf(0.0, _zoom_cd - delta)
	_play_cd = maxf(0.0, _play_cd - delta)
	_chatter_cd = maxf(0.0, _chatter_cd - delta)
	_wash_cd = maxf(0.0, _wash_cd - delta)
	_shake_cd = maxf(0.0, _shake_cd - delta)
	_tick_energy(delta)
	_idle_attention(delta, ppos, d)

	# WAKING UP IS ITS OWN BEAT. A cat that has been asleep does not stand up and walk: it
	# stretches, at length, and only then is it awake. Held here rather than inside the sleep
	# branch because waking can be caused by anything — the player getting up, a bird, a
	# noise — and the stretch has to happen whatever ended the sleep.
	if _state == State.SLEEP:
		_was_asleep = true
	elif _was_asleep:
		_was_asleep = false
		_stretch_t = _rng.randf_range(1.3, 2.4)
		if _rig != null:
			_rig.call("shake", 1.0)          # the first thing anything does on getting up
		# ...and a cat that has just woken is the likeliest cat in the world to tear off
		# across the deck for no reason at all. A full night's rest is what pays for it.
		if _rng.randf() < 0.30 + _energy * 0.45:
			_zoom_cd = minf(_zoom_cd, 2.5)
	# THE CHATTER. A cat that can see a bird it cannot possibly reach does not give up on it —
	# it fixes on the thing and makes that ridiculous staccato rattle. It is one of the most
	# recognisable things a cat does and it costs almost nothing here, so it rides ALONGSIDE
	# whatever the animal is otherwise doing rather than owning a state: no `return`, no beat
	# in the machine, just a head tremor and a look at a gull that is already in the air.
	if _hunt == 0 and _carry == "" and _chatter_cd <= 0.0:
		for g in get_tree().get_nodes_in_group("deck_gull"):
			var n: Node3D = g as Node3D
			if n == null or not is_instance_valid(n) or not _airborne(n):
				continue
			if global_position.distance_to(n.global_position) > HUNT_M:
				continue
			# A WALKING CAT GLANCES; A SITTING CAT STARES. This watch ran at full weight in
			# every state, and it is not gated by `_hunt_cd` — so with any gull in the air
			# within eleven metres (i.e., most of the time on this deck), the companion
			# walked with its head hauled a full look-clamp toward the bird. That is the
			# owner's eight-times-reported "head defaults to pointing sideways while it
			# walks": not a rig constant, an attention weight no walking animal would hold.
			# Stationary keeps the locked-on stare the chatter deserves; on the move it is
			# a flick of the ears and eyes, and the head stays on the line of travel.
			# Stationary only: a moving cat's chatter-watch is fully suppressed at the
			# rig feed (see _drive_rig) — the 0.22 walking whisper this used to carry was
			# still a visible head-turn, and the owner's rule is absolute.
			# 0.10 WHILE MOVING, and this is the last of "still crooked to the right a
			# little bit". The bare rig measures 0.00 deg off the travel line
			# (tests/NoseScratch.tscn), so the residual was never the bake — it was this:
			# a gull in the air anywhere within eleven metres held the head over at FULL
			# weight for as long as the bird stayed up, which on a 1.05 rad clamp is a
			# standing lean of tens of degrees. A moving cat notices a bird; it does not
			# stare at one.
			_watch(n.global_position, 0.10 if _last_speed > 0.2 else 1.0)
			if _rig != null:
				if _last_speed <= 0.2:
					_rig.call("chatter", 1.0)
				# A bird it cannot have is the single most reliable tail-lash there is.
				if _rng.randf() < delta * 2.2:
					_rig.call("tail_flick", 0.9)
			if _meow_cd <= 0.0:
				AudioDirector.play_one_shot("cat_chirp", global_position, -26.0)
				_meow_cd = 3.0
			_chatter_cd = _rng.randf_range(0.0, 0.35)   # renewed while the bird is still up
			break

	# ...and a hunt is over the moment the player leaves. The gate below only STOPS the hunt
	# branch running at range; without this the animal keeps its prey and its beat and picks
	# the stalk back up mid-crouch whenever the player wanders back, which reads as the cat
	# having been paused rather than having given up.
	# (A STAYED cat's hunt is its own business — the companion leash below only applies
	# while it is actually a companion.)
	if not _stayed and _hunt > 0 and d >= RUN_M:
		_end_hunt(false)

	# IS THE PLAYER RESTING? Not a flag they set — a thing the cat works out by watching. A
	# player who has not moved for SETTLE_SEC is resting whether they meant to or not, which
	# is also true of lying down and sitting, and it means the cat settles when you stop to
	# fish or read rather than only in a bed.
	var moved: float = ppos.distance_to(_last_player_pos)
	_last_player_pos = ppos
	# A STAYED cat does not care whether YOU are moving: its calm is its own, so `_still`
	# accumulates unconditionally and the sit -> doze -> sleep ladder runs on its clock.
	var resting: bool = _stayed or moved < 0.05 * maxf(delta, 0.001) * 60.0
	if bool(player.get("_lying")) or bool(player.get("crouching")):
		resting = true
	_still = (_still + delta) if resting else 0.0

	# BEING PETTED WINS OVER EVERYTHING for a moment: a head-bump you can interrupt is not
	# a head-bump. Short, so it never reads as the cat freezing.
	if _pet_t > 0.0:
		_enter(State.PET)
		_face(ppos, delta)
		# THE PET REACTION, IN THE ANIMAL. This was `_body.rotation.z = k * 0.22` — the
		# entire cat rolled 12.6 degrees onto its side, paws still flat on the deck, which
		# is the owner's "the whole model tilts to the side instead of the cat reacting
		# happy". A real cat arches its back up into the hand and presses its head into
		# it; cat_rig.pet does both, and the tail flag below finishes the reading.
		if _rig != null:
			_rig.call("pet", sin((1.0 - _pet_t / PET_SEC) * PI))
		_stretch_t = 0.0     # a hand on it ends the stretch; nothing outranks being petted
		return

	# THE STRETCH ON WAKING, below the hand but above everything else. Not if you have already
	# walked off, though: a cat that has to catch up does not stop to stretch first, and a
	# companion that does reads as broken rather than as characterful.
	if _stretch_t > 0.0 and d < RUN_M:
		_stretch_t -= delta
		_enter(State.STRETCH)
		_last_speed = 0.0
		_reseat()
		return
	_stretch_t = 0.0

	# STAYED: it was told to keep its own counsel, and it does — on its own patch, on its
	# own clock, with its own hunts. Below the pet and the wake-stretch (a hand on a
	# stayed cat still works) and above everything that follows the player around.
	if _stayed:
		_stay_behaviour(delta, ppos, d)
		return

	# THE FISH. It can smell one in your hands and it does not pretend otherwise: it closes
	# right up, and it will not settle while you are holding it.
	var has_fish: bool = _player_holding_fish(player)
	if has_fish and d < FISH_M:
		_enter(State.FISH)
		# Trailed like the follow is: FISH_M is 9 m and a cat that can smell a fish through a
		# bulkhead should still come round by the door.
		var fish_aim: Vector3 = _trail_goal(ppos, delta)
		_walk_toward(fish_aim, TROT_SPEED * _ease_turn(fish_aim, delta), delta,
			0.05 if _trail_live else 0.9)
		if _meow_cd <= 0.0:
			_meow_cd = _rng.randf_range(4.0, 9.0)
			AudioDirector.play_one_shot("cat_chirp", global_position, -20.0)
		return

	# THE PLAYER TURNING IN OUTRANKS EVERY GAME THE CAT KNOWS, and it has to, because the
	# alternative shipped and CatProbe caught it on the first run: `_still` climbs while the
	# player lies there, both cooldowns expire, and the cat spends the night doing zoomies and
	# pouncing on nothing three metres from the bed while the sleep branch below never gets a
	# frame. That is the same "paces beside the bed all night" the s37 sleep-spot fix cured
	# from a different cause, which is a good reason to keep this test and a better reason to
	# put the check HERE rather than further down where it reads more naturally.
	if _player_asleep(player):
		_bed_down(delta, ppos)
		return
	_sleep_target = Vector3.ZERO

	# THE AFTERMATH OF A MISS — see the sequence's header. It sits down exactly where it
	# failed and washes, with enormous dignity, as though that had been the plan. Held above
	# everything except being petted and being offered a fish, because a cat interrupted
	# mid-excuse is not a cat.
	#
	# AND IT NAMES ITS STYLE. `groom_style` had exactly one caller (`_self_groom`), so the most
	# characterful wash in the design played whatever body the LAST bout happened to leave
	# behind — for a session in which no bout had ever fired, that is style 0's raised forepaw
	# by accident rather than by choice, and after a flank wash it was a cat covering its
	# embarrassment by washing its shoulder. Style 0 is the right one and is now said out loud:
	# a miss is answered with a brisk paw-lick, not a leisurely flank.
	if _after_t > 0.0:
		_after_t -= delta
		_enter(State.GROOM)
		if _rig != null:
			_rig.call("groom_style", 0)
		_last_speed = 0.0
		_reseat()
		return

	# ...AND THE PRIZE. A cat brings what it catches to the people it lives with. It is not a
	# gift in any sense the cat would recognise, but it is the single most cat thing there is,
	# and it is worth the whole hunt.
	if _carry != "":
		_enter(State.GIFT)
		_watch(ppos + Vector3(0, 1.2, 0), 0.8)
		if d > 1.3:
			_walk_toward(ppos, TROT_SPEED, delta, 1.1)
		else:
			_deliver(player)
		return

	# THE HUNT. Only while the player is not being left behind — a companion that abandons you
	# across the rig to stalk a gull is a bug, however true to life.
	if (_hunt > 0 or (_hunt_cd <= 0.0 and _energy > 0.30)) and d < RUN_M:
		if _hunt_step(delta):
			_wash_t = 0.0        # a bird ends a wash mid-stroke, which is the honest order
			return

	# THE ZOOMIES, and object play. Both need the player to be somewhere near and settled,
	# because both read as the cat entertaining itself rather than ignoring you.
	# GATED ON MOOD, not just on a clock. A tired cat does not get the zoomies however long it
	# has been since the last ones, and a cat at dusk with a full tank barely stops. This is
	# what makes two evenings different without a second behaviour tree.
	if _zoom_t > 0.0 or (_zoom_cd <= 0.0 and d < FOLLOW_FAR and _still > 5.0 and _energy > 0.62):
		if _zoomies(delta, ppos):
			return
	if _play_t > 0.0 or (_play_cd <= 0.0 and d < FOLLOW_FAR and _still > SETTLE_SEC * 0.5
			and _energy > 0.34):
		if _play(delta):
			return

	# THE INSTINCT LAYER, MID-ACTION — the only rung whose CONTENT is chosen by a weighted draw
	# rather than by a situation (see the section at the bottom of the file). It sits ABOVE the
	# follow for one reason: a perched cat is by definition more than `near_gap` from a player
	# standing on the deck, so with this below the follow the animal would climb onto a crate
	# and be walked straight back off it on the next frame. The leash inside `_idle_holds` is
	# what keeps that from becoming an instinct that outranks the companion contract — the
	# instant the player moves, or opens five metres of ground, the action ends and the follow
	# takes this frame. Actions can only START from the settled branches below, i.e. only when
	# the follow had already declared the cat arrived.
	if _idle_step(delta, ppos, IDLE_LEASH, resting):
		return

	# NO DISTANCE GIVES UP THE FOLLOW ANY MORE. LOST_M (26 m) used to park the animal the
	# moment the player crossed the rig — the owner's ask is the opposite: it knows where
	# you are from anywhere, and if it is following you it WORKS the problem. The detour
	# fan gives it the means (it rounds corners and takes the stairs a tread at a time),
	# and where the rig genuinely cannot be walked — a dive, the boat — it closes to the
	# nearest reachable spot and waits there, which is what a real cat does at the top of
	# a companionway. The player who wants it parked has the STAY verb now, which is a
	# decision, not a distance.
	# THE COMPANIONABLE GAP SHRINKS WHEN YOU ARE STANDING ABOVE IT — and this gate, not the
	# one inside `_walk_toward`, is the one that decides whether the animal moves at all.
	# `d` is a 3D distance, so a player up on a 1.1 m ledge only 1.35 m away measures 1.87 m
	# — inside FOLLOW_NEAR — and the cat declares itself arrived and sits down on the deck
	# below, having never called the walk at all. Every gate in the leap path was verified
	# passing at that exact spot (tests/LeapScratch.tscn) while the shipping loop never
	# reached one of them: the jump was unreachable from the STATE MACHINE, not from the
	# geometry. Both the gate and the stop distance take the same shrunken gap now.
	#
	# ...AND IT SHRINKS BOTH WAYS, WHICH IS THE SINGLE HIGHEST-VALUE LINE IN THE DROP FIX.
	# The gate above was written for a player on a crate and only ever tested `ppos.y -
	# global_position.y`. Invert the picture — cat up on the rigging bench, player on the deck
	# beside it — and the 3D distance is again under FOLLOW_NEAR, so the animal declares
	# itself ARRIVED, enters SIT, and never calls `_walk_toward` at all. No descent code
	# anywhere in this file could have fired, because control never reached the walk: the cat
	# sat on the bench looking pleased with itself for as long as you cared to watch. Height
	# is not company in either direction.
	var near_gap: float = FOLLOW_NEAR
	if absf(ppos.y - global_position.y) > CLIMB_UP:
		near_gap = 0.35
	if d > near_gap:
		# ...and it BREAKS INTO A RUN when it has been left behind, which is the one moment a
		# follower reads as an animal rather than a marker: same walk otherwise.
		var running: bool = d > RUN_M
		_enter(State.RUN if running else State.FOLLOW)
		_still = 0.0
		_pace_cd -= delta
		if _pace_cd <= 0.0:
			_pace = _rng.randf_range(0.86, 1.14)
			_pace_cd = _rng.randf_range(0.6, 2.2)
		# BAIT-TRAILED. The goal is a point on the route the player actually walked, not the
		# player — see the trail section. It degrades to `ppos` the moment the trail has
		# nothing usable, so this line is the s45 behaviour whenever there is no route to
		# follow. `stop_at` follows the goal: stopping FOLLOW_NEAR short of a WAYPOINT would
		# park the animal a metre before every corner. The distance that decides whether to
		# walk at all is still `d`, which is measured to the player.
		var aim: Vector3 = _trail_goal(ppos, delta)
		# YOU CANNOT BE "NEAR" SOMEONE WHO IS STANDING ABOVE YOU. `FOLLOW_NEAR` is the
		# companionable gap on level ground, and applied to a player up on a crate it parked
		# the animal 2.2 m out on the deck — where the ledge is still a metre beyond its nose,
		# so the jump probe never fires and the cat simply gives up near the thing it should
		# be hopping onto. Filmed: staged at a real 1.00 m ledge, the cat walked to z 5.80 and
		# stopped dead, 2.2 m short of a lip at z 8.00, for all 270 frames.
		# So when the player is more than a step above, the target is the FOOT of whatever
		# they are on: close right up, let the ledge probe see it, and let the leap decide.
		_walk_toward(aim, (RUN_SPEED if running else (TROT_SPEED if d > FOLLOW_FAR else WALK_SPEED))
			* _pace * _ease_turn(aim, delta), delta, 0.05 if _trail_live else near_gap)
		return
	# (The `_self_groom` rung that used to sit here is gone, and it is gone because it became
	# unreachable rather than because the wash moved: `_idle_step` above takes any frame with
	# `_wash_t > 0` and, on the one branch where it declines, clears the claim itself. A wash
	# is still interrupted by the hunt above and still finishes before the settle below — the
	# order it always had. `_self_groom` remains the executor, called from there.)

	# Within arm's reach of a player who is not going anywhere.
	if _still > SETTLE_SEC:
		_settle(delta)
	else:
		_enter(State.SIT)
		_pose_sit(delta)
	# ...AND THEN IT DECIDES WHAT TO DO WITH ITSELF. Called from OUTSIDE the if/else, which is
	# the whole of the wash-window fix: the two lines that used to be in the `else` (a wash roll
	# and a shake roll) were reachable only while `3 < _still <= 6`. This runs for the whole of
	# "settled", dozing and asleep included — a sleeping cat's only option is `rouse`, which is
	# the edge that was missing from the sit -> doze -> sleep ladder and the reason a player who
	# stood still for half a minute got a cat that never moved again.
	_idle_tick(delta, true)

## A STAYED CAT'S OWN LIFE. Everything here already existed as companion behaviour — the
## hunt, the zoomies, the play pounce, the washes, the sit -> doze -> sleep ladder — the
## only new idea is the ANCHOR: games orbit the spot it was told to stay at instead of the
## player, the hunt ignores the companion leash entirely, and anything that carried it off
## its patch (a stalk, a zoomie) strolls back afterwards. A caught feather is still
## brought over — but only when you come near; it does not break a STAY to deliver.
func _stay_behaviour(delta: float, ppos: Vector3, d: float) -> void:
	if _carry != "":
		if d < 6.0:
			_enter(State.GIFT)
			_watch(ppos + Vector3(0, 1.2, 0), 0.8)
			if d > 1.3:
				_walk_toward(ppos, TROT_SPEED, delta, 1.1)
			else:
				var player: Node3D = get_tree().get_first_node_in_group("player")
				if player != null:
					_deliver(player)
		else:
			_enter(State.SIT)
			_pose_sit(delta)
			_watch(ppos + Vector3(0, 1.2, 0), 0.4)
		return
	if _after_t > 0.0:
		_after_t -= delta
		_enter(State.GROOM)
		if _rig != null:
			_rig.call("groom_style", 0)   # named, not inherited — see the companion's copy
		_last_speed = 0.0
		_reseat()
		return
	if _hunt > 0 or (_hunt_cd <= 0.0 and _energy > 0.30):
		if _hunt_step(delta):
			_wash_t = 0.0
			return
	if _zoom_t > 0.0 or (_zoom_cd <= 0.0 and _still > 5.0 and _energy > 0.62):
		if _zoomies(delta, _stay_spot):
			return
	if _play_t > 0.0 or (_play_cd <= 0.0 and _still > SETTLE_SEC * 0.5 and _energy > 0.34):
		if _play(delta):
			return
	# THE INSTINCT LAYER — and a stayed cat is who it was most missing. `resting` is
	# unconditionally true for one (its calm is its own), so its `_still` never resets and the
	# old three-second wash window could open exactly ONCE per STAY, ever. It anchors on the
	# patch rather than on the player, like every other game here, and the 4 m leash is the same
	# patch radius the stroll-home rung below uses — so an instinct can never carry it off the
	# spot it was told to keep.
	if _idle_step(delta, _stay_spot, 4.0, true):
		return
	# Wandered off the patch? Stroll home. 4 m of slack, because a cat told to stay in a
	# spot understands the spot to be roughly the size of a room.
	if global_position.distance_to(_stay_spot) > 4.0:
		_enter(State.FOLLOW)
		_walk_toward(_stay_spot, WALK_SPEED, delta, 1.0)
		return
	# (`_self_groom` moved up into `_idle_step`, as in the companion — see the note there.)
	if _still > SETTLE_SEC:
		_settle(delta)
	else:
		_enter(State.SIT)
		_pose_sit(delta)
	_idle_tick(delta, true)

## THE PLAYER HAS TURNED IN. A cat does not wait out a night standing up: it comes over, finds
## a spot NEAR the bed rather than on the walking line, and curls up there. The spot is PROBED
## (see _sleep_spot) — a hand-typed offset from a bed that another session moves is the whole
## floating-prop family of bugs in this repo.
func _bed_down(delta: float, ppos: Vector3) -> void:
	# THE SPOT IS CHOSEN ONCE AND HELD. _sleep_spot used to be re-run every frame, and its
	# winning candidate depends on the cat's own position — so as the animal walked, the target
	# could flip between two candidates and, in the wrong geometry, oscillate for ever: a cat
	# that paces beside the bed all night instead of lying down (seen as an intermittent probe
	# failure, ~1 run in 5). Hysteresis: keep the chosen spot while the player stays asleep,
	# re-picking only if it drifts out of plausibility.
	##
	## ...AND A HELD TARGET IT CANNOT REACH IS THE SAME BUG WEARING A HAT. The hysteresis above
	## cured the oscillation and replaced it with a cat that walks at one spot for ever: the
	## spot is only re-picked if the PLAYER moves, `_sleep_spot` only proves a thin ray at
	## +0.22 m is clear rather than that the body can walk the whole way, and `_walk_toward`
	## silently refuses a step it cannot take. So the animal closes to whatever the obstruction
	## allows and then stands there pressing into it all night. That is CatProbe's intermittent
	## failure — it fires or does not depending purely on where the cat happened to be standing
	## when the player lay down, which is exactly the shape of a "1 run in 6".
	##
	## The fix is not a longer window. A cat that cannot get to the good spot LIES DOWN WHERE IT
	## IS, which is both what a cat does and a state this machine can always reach.
	if _sleep_target == Vector3.ZERO or ppos.distance_to(_sleep_target) > 3.0:
		_sleep_target = _sleep_spot(ppos)
		_bed_stall = 0.0
		_bed_best = 1e9
	var togo: float = global_position.distance_to(_sleep_target)
	if togo > 0.55:
		# Progress is measured, not assumed: only closing the gap counts as getting there.
		if togo < _bed_best - 0.02:
			_bed_best = togo
			_bed_stall = 0.0
		else:
			_bed_stall += delta
		if _bed_stall > 2.5:
			_sleep_target = global_position
			togo = 0.0
	if togo > 0.55:
		_enter(State.FOLLOW)
		_walk_toward(_sleep_target, WALK_SPEED, delta, 0.35)
	else:
		_enter(State.SLEEP)
		ANIM.drive(_gen_mats, 0.5, 0.0)

## Is the player actually turned in? `_lying_sleeping` is the flag player_controller sets
## while the S-to-dawn fade runs; `_lying` is merely lying down. A cat curls up when you go
## to bed, not when you lie on the floor for a second.
func _player_asleep(player: Node3D) -> bool:
	return bool(player.get("_lying_sleeping")) or bool(player.get("_lying"))

func _settle(delta: float) -> void:
	if _still > SETTLE_SEC + DOZE_SEC:
		_enter(State.SLEEP)
		# Curled and breathing, nose tucked. The body sinks a little and the breathe rate
		# halves — the same trick the denned glow worm uses to read as asleep.
		# The curled mesh does the shape; this is only the breathing slowing down. The old
		# code rolled the body 0.55 rad to fake "lying down" with a standing mesh, which is
		# exactly what having a sleep pose removes the need for.
		ANIM.drive(_gen_mats, 0.5, 0.0)
	else:
		_enter(State.SIT)
		_pose_sit(delta)

func _pose_sit(delta: float) -> void:
	ANIM.drive(_gen_mats, 1.1, 0.0)
	_last_speed = 0.0
	# A sitting cat is on the deck it sat down on — and the seat ray is the only thing that
	# keeps it there if another session moves that deck.
	_reseat()
	# The small weight-shift of a cat that is awake and paying attention. ASSIGNED, never
	# `+=`: a per-tick += without a delta term reaches equilibrium against _process's ease
	# at rate_ratio * amplitude — measured at 75 DEGREES of body yaw on the live game,
	# which drew the cat walking sideways off its own node. The s36 comment on this line
	# argued += was safer than assignment; the opposite was true.
	#
	# ...and OCCASIONAL, not continuous: the old `sin(_t * 0.9)` swayed the seated animal on
	# a metronome, which is the signature of an idle loop. A real cat re-plants its weight
	# every ten or twenty seconds, irregularly, and is otherwise still (the breath layer
	# carries the rest of "alive").
	_shift_cd -= delta
	if _shift_cd <= 0.0 and _shift_t <= 0.0:
		_shift_dur = _rng.randf_range(0.8, 1.4)
		_shift_t = _shift_dur
		_shift_amp = _rng.randf_range(0.04, 0.08) * (1.0 if _rng.randf() < 0.5 else -1.0)
		_shift_cd = _rng.randf_range(9.0, 22.0)
	if _shift_t > 0.0:
		_shift_t -= delta
		# A PELVIS ROLL, not a node yaw. The node version was measured at a constant
		# 4.67 degrees of whole-body tilt in every state the joint probe sampled — the
		# single most persistent piece of "the game rotates the entire cat".
		if _rig != null:
			_rig.call("weight_shift", (_shift_amp / 0.08)
				* sin(clampf(1.0 - _shift_t / _shift_dur, 0.0, 1.0) * PI))
	elif _rig != null:
		_rig.call("weight_shift", 0.0)

## Walk the deck toward a point, stopping `stop_at` short. Kinematic and deliberately simple:
## it steps up a coaming, refuses anything taller, and re-seats on whatever it is standing on
## so it can never walk off into the air.
func _walk_toward(target: Vector3, speed: float, delta: float, stop_at: float) -> void:
	# A REFUSED STEP MUST REPORT ZERO SPEED, and this is the owner's "the legs went floppy
	# for a bit after the cat got caught in a corner".
	#
	# `_last_speed = speed` is assigned at the BOTTOM of this function, below every early
	# `return`. So a cat whose every candidate step is refused kept its last COMMANDED
	# speed for ever while actually covering no ground — and cat_rig reads the pair: zero
	# distance unloads `_gait_w`, but the stale speed keeps `_speed_s` (and therefore the
	# gait mix) pinned wherever it was. A cat that wedges while running therefore drops
	# into the turn-in-place shuffle — which `_gait_w` falling is exactly what opens —
	# running at GALLOP paw lift and gallop duty, i.e. 80% of the cycle airborne, on an
	# animal going nowhere. Four legs paddling in the air is precisely "floppy".
	_last_speed = 0.0
	_detour_t = maxf(0.0, _detour_t - delta)
	var to: Vector3 = target - global_position
	to.y = 0.0
	var dist: float = to.length()
	if dist <= stop_at or dist < 0.01:
		return
	var dir: Vector3 = to / dist
	_face(target, delta)
	var step: Vector3 = dir * speed * delta
	var want: Vector3 = global_position + step
	var world: World3D = get_world_3d()
	if world == null:
		return
	# Probe the deck under the next footfall. No hit means the step would walk it off an edge,
	# so it simply does not take it — a cat does not fall off a rig.
	#
	# DO NOT LENGTHEN THIS RAY. 1.85 m of reach is exactly what makes "a cat does not fall off
	# a rig" true; widening it to see the ten-metre drop the descent branch below can now take
	# would turn every deck edge into a walk-off, which is the mirror image of the s38 mistake
	# that stranded the animal at y 20.26. The descent asks its OWN question, further out, and
	# only when this one has already refused.
	var from: Vector3 = want + Vector3(0, STEP_UP + 0.3, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, STEP_UP + 1.4, 0))
	q.collision_mask = 1
	q.collide_with_areas = false
	# `_walk_skip()`, not the bare handle — the fan (below), the back-out and the ledge probe
	# all use the full list and this one did not, so the footfall ray alone could read another
	# animal's grab collider, or the player's own capsule, as the deck to stand on.
	q.exclude = _walk_skip()
	var jump_idle: bool = _jump_t <= 0.0 and _jump_wind <= 0.0 and _jump_cd <= 0.0
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		# NOTHING WITHIN 1.85 m OF THE NEXT FOOTFALL. Refusing the step stays right — it is
		# what keeps the cat off the edge of the rig — but refusing it and RETURNING is how an
		# animal on top of anything taller than this ray's reach stays there for the session:
		# the deck below passes under the ray entirely, so the descent branch further down is
		# never reached at all. Ask the way-down question before giving up.
		if jump_idle and target.y < global_position.y - STEP_UP:
			_try_descend(dir, delta)
		return
	var ground: float = (hit["position"] as Vector3).y
	var rise: float = ground - global_position.y
	# ...AND THE DECK IT FOUND MUST BE OUT OF THE SEA. A submerged surface answers this ray
	# perfectly well — the boat landing sits at y -3..1 — so without this the cat walks down
	# the landing and keeps going. Same swim line the player, main.gd, underwater_fx and this
	# file's own trail recorder test against, so "the cat will not follow you in" means the
	# same thing in all five places.
	if _over_water(Vector3(want.x, ground, want.z)):
		return
	# IS THERE A WALL IN THE WAY? The owner's "Cat glitches through walls".
	#
	# Every probe above asks about the FLOOR — "is there deck under the next footfall, and
	# is the step up small enough". None asked whether anything stands BETWEEN the cat and
	# that footfall, so a bulkhead with sound deck on both sides answered every question
	# correctly and the animal walked straight through it. The bunkhouse is full of exactly
	# that geometry.
	#
	# DOES THE BODY FIT WHERE THE FEET ARE GOING? Not a ray — see _step_clear. A ray from
	# the origin let the animal stop with up to 0.48 m of itself inside a bulkhead, which is
	# the state the owner photographed. The destination is tested as a VOLUME.
	#
	# AND IF IT DOES NOT FIT, SLIDE — do not stop dead. A companion that refuses a blocked
	# step just stands there vibrating against the obstruction, which is the "glitchy" read
	# even though nothing is intersecting: the first cut of this check did exactly that and
	# left the cat unable to close the last half-metre to its own sleeping spot. Real
	# movement code slides along what it touches, so this tries the direct line first and
	# then the two tangents, taking whichever still carries it toward the target.
	var moved_dir: Vector3 = dir
	# THE LEDGE THE FOOTFALL PROBE CANNOT SEE — and the reason the leap almost never fired.
	#
	# That probe starts at `STEP_UP + 0.3` = 0.75 m above the cat's feet, while `JUMP_UP` is
	# 1.25. Anything between those heights passes UNDER the ray, which then finds the lower
	# deck beyond and reports a rise of zero: the gate below reads "flat ground", the volume
	# check refuses the step because the lip is solid, and the animal walks into the face.
	# The jump could only ever fire in the narrow 0.62-0.75 m band — the owner's "clean up
	# the jump, and make it more frequent".
	#
	# So when the direct step is REFUSED, look higher before giving up. Only then: this ray
	# is the expensive, greedy question and asking it every step is what would make the cat
	# leap at scenery it should walk around.
	#
	# AND IT HAS TO RUN BEFORE THE DETOUR FAN, which is where the first cut of this put it
	# and why it changed nothing: the fan RETURNS when every candidate is refused, so on the
	# exact frames a ledge is worth looking for, control never reached the probe. Filmed at a
	# real 0.85 m ledge — inside the band that was invisible — and the telemetry read y 18.00
	# across all 270 sampled frames, i.e. identical to the pre-fix animal. Dead code passes
	# every test that does not watch the animal.
	# ASKED ONCE, READ THREE TIMES — the ledge probe, the descent probe and the fan all turn on
	# the same question, and asking it three times invited them to disagree.
	var direct_ok: bool = _step_clear(Vector3(want.x, ground, want.z), dir)
	if rise <= CLIMB_UP and not direct_ok and jump_idle:
		# LOOK WHERE THE LANDING IS, NOT WHERE THE NEXT FOOTFALL IS — and that is a second
		# thing the first cut got wrong. `want` is ONE STEP ahead (26 mm at a walk), while
		# `_step_clear` refuses the step when the cat's NOSE sphere touches the lip, which is
		# `_body_len()/2 - r + r` = about 0.33 m out. So a ray at `want` comes down a third of
		# a metre SHORT of the ledge, hits the deck the cat is already standing on, and reports
		# a rise of zero — the probe fired, found flat ground, and the animal walked into the
		# face exactly as before. Filmed twice against real 0.85 m and 1.10 m ledges before the
		# telemetry (y pinned at 18.00 across 270 frames) made it obvious.
		#
		# So probe a body-length out, and if a ledge is there, that probed point IS the
		# landing — jumping to `want` would put the cat down in mid-air off the lip.
		var lookahead: Vector3 = global_position + dir * (_body_len() * 0.95)
		var hq := PhysicsRayQueryParameters3D.create(
			lookahead + Vector3(0, JUMP_UP + 0.45, 0), lookahead + Vector3(0, 0.05, 0))
		hq.collision_mask = 1
		hq.collide_with_areas = false
		hq.exclude = _walk_skip()
		var hhit: Dictionary = world.direct_space_state.intersect_ray(hq)
		if not hhit.is_empty():
			var top: float = (hhit["position"] as Vector3).y
			var lift: float = top - global_position.y
			# ONLY CLAIM THE LEDGE IF THE LEAP IS ACTUALLY ON. Raising `rise` past CLIMB_UP
			# hands control to the jump gate below, which RETURNS whether or not it fires —
			# so a ledge the cat may see but not take (out of the reachability ceiling, arc
			# fouled, landing occupied) converted a perfectly ordinary walk-around into a
			# dead stop. Measured: CatHuntProbe's stalk froze 2.26 m short of the bird and
			# never pounced, because a structure near the deck answered this ray and the
			# refused jump ate the frame the detour fan should have had. Prove the whole
			# leap here; anything less and the fan keeps the step, as it did before.
			if lift > CLIMB_UP and lift <= JUMP_UP and _reachable_up(top) \
					and _step_clear(Vector3(lookahead.x, top, lookahead.z), dir) \
					and _arc_clear(Vector3(lookahead.x, top, lookahead.z), dir):
				want = Vector3(lookahead.x, top, lookahead.z)
				ground = top
				rise = lift
				direct_ok = true
	# ------------------------------------------------------------------ THE WAY DOWN
	#
	# THE DESCENT, which this animal has never had, and the comment above `_reachable_up` has
	# been saying "down is never gated" while it was gated absolutely.
	#
	# Trace the bench: the cat stands on a 0.90 m CraftBench top, the player is on the deck
	# beside it. The footfall ray at `want` clears the lip, finds the deck, reports rise
	# -0.90 — and then `_step_clear` puts the test sphere 0.157 m above that deck, hard
	# against the bench's vertical face, where it needs `_body_r()` = 0.117 m of clearance and
	# has 0.0158 m (one walk step at 60 fps). Refused. Refused again next frame, from 0.0158 m
	# further on. Refused for ever. Going UP the identical test sits ON TOP of the obstacle and
	# is trivially clear — the asymmetry is the whole bug, and it is not a tuning error, it is
	# a missing branch.
	#
	# WHERE THIS SITS IS LOAD-BEARING. After the ledge probe, before the detour fan: the fan
	# `return`s on refused frames, so anything below it is dead on exactly the frames it
	# matters (KNOWN_ISSUES:87-93 — the previous ledge fix was put there, filmed identically to
	# no fix at all, and telemetry read y 18.00 across all 270 frames).
	#
	# ONLY DOWNHILL, AND ONLY TOWARD SOMETHING LOWER. `target.y` below the cat is what keeps
	# this from turning every deck edge into a walk-off: a cat crossing a deck toward someone
	# standing on it never asks the question at all. The stall clause is the escape hatch — if
	# the animal has been stuck above its target for DROP_STALL seconds, it widens the search
	# to a fan of headings, because "the way down is not the way I am facing" is exactly how a
	# cat gets stranded on a bench it hopped onto from the other side.
	if not direct_ok and rise <= 0.0 and jump_idle \
			and target.y < global_position.y - STEP_UP:
		if _try_descend(dir, delta):
			return
	if not direct_ok:
		# THE DETOUR FAN — navigation for an animal with no navmesh, and the cure for the
		# corner the owner watched it wedge in.
		#
		# The old slide tried exactly the two perpendiculars and remembered nothing: a
		# doorway 30 degrees off the line was invisible (both tangents parallel the wall),
		# and at a concave corner the choice was re-rolled from scratch every frame, so
		# the animal flipped +90/-90/+90 against the pocket for ever — "caught in a
		# corner". Two changes, both cheap:
		#
		#   * A FAN, nearest-the-goal first: ±29, ±52, ±83, ±115 degrees. The first clear
		#     candidate wins, so the cat deviates as little as the geometry allows and can
		#     still take a heading past perpendicular — rounding a corner's far edge needs
		#     one — while anything beyond ±115 stays forbidden (a detour that points back
		#     the way it came is how an animal orbits a pillar).
		#   * COMMITMENT: taking a detour remembers its SIDE for 0.8 s, and the fan tries
		#     that side first at every magnitude while the memory lasts. Deciding is
		#     cheap; re-deciding every frame is what oscillates. The memory only biases
		#     the ORDER — if the committed side closes, the other side still gets tried
		#     the same frame.
		#
		# Cost: only on BLOCKED frames, worst case 8 candidate probes; an unobstructed
		# walk pays nothing.
		var slid := false
		var first: float = _detour_side if (_detour_t > 0.0 and absf(_detour_side) > 0.5) else 1.0
		for mag in [0.5, 0.9, 1.45, 2.0]:
			if slid:
				break
			for side_k in [first, -first]:
				var alt: Vector3 = dir.rotated(Vector3.UP, side_k * float(mag))
				var awant: Vector3 = global_position + alt * speed * delta
				var aq := PhysicsRayQueryParameters3D.create(
					awant + Vector3(0, STEP_UP + 0.3, 0),
					awant + Vector3(0, STEP_UP + 0.3, 0) - Vector3(0, STEP_UP + 1.4, 0))
				aq.collision_mask = 1
				aq.collide_with_areas = false
				aq.exclude = _walk_skip()
				var ahit: Dictionary = world.direct_space_state.intersect_ray(aq)
				if ahit.is_empty():
					continue
				var aground: float = (ahit["position"] as Vector3).y
				if absf(aground - global_position.y) > CLIMB_UP:
					continue
				# The same swim line the direct step is held to. A fan candidate is a STEP, and
				# a step onto a submerged surface is a step into the sea whichever heading it
				# was found on — without this the cat slides down the boat landing sideways.
				if _over_water(Vector3(awant.x, aground, awant.z)):
					continue
				if not _step_clear(Vector3(awant.x, aground, awant.z), alt):
					continue
				want = awant
				ground = aground
				rise = aground - global_position.y
				moved_dir = alt
				_detour_side = signf(side_k)
				_detour_t = 0.8
				slid = true
				break
		if not slid:
			# A DEAD POCKET — the whole fan refused. Greedy steering can walk into a U it
			# cannot steer out of (everything inside ±115° is blocked and the exit is
			# dead astern), which is exactly where the probe's COME test wedged: 0.8 m of
			# progress into a bunk niche and then zero for eight seconds, deterministic.
			# A real animal BACKS OUT. After 0.35 s of fully-refused frames, take the
			# reverse step if it is clear, and flip the committed side — so the next
			# approach rounds the obstacle the other way instead of re-entering the same
			# pocket for ever.
			_detour_stall += delta
			if _detour_stall > 0.35:
				var back: Vector3 = -dir
				var bwant: Vector3 = global_position + back * minf(speed, WALK_SPEED) * delta
				var bq := PhysicsRayQueryParameters3D.create(
					bwant + Vector3(0, STEP_UP + 0.3, 0),
					bwant + Vector3(0, STEP_UP + 0.3, 0) - Vector3(0, STEP_UP + 1.4, 0))
				bq.collision_mask = 1
				bq.collide_with_areas = false
				bq.exclude = _walk_skip()
				var bhit: Dictionary = world.direct_space_state.intersect_ray(bq)
				if not bhit.is_empty():
					var bground: float = (bhit["position"] as Vector3).y
					if absf(bground - global_position.y) <= CLIMB_UP \
							and _step_clear(Vector3(bwant.x, bground, bwant.z), back):
						var before_back: Vector3 = global_position
						global_position = Vector3(bwant.x, bground, bwant.z)
						_moved_frame += global_position.distance_to(before_back)
						_last_speed = minf(speed, WALK_SPEED) * 0.6
						_detour_side = -_detour_side if absf(_detour_side) > 0.5 else 1.0
						_detour_t = 1.2
			return
	# STAIRS. The old rule was "coamings yes, stairs no" (STEP_UP 0.45) and the cat simply
	# refused anything taller — which is why it could not follow you off the deck it met you
	# on. A rig stair tread rises STAIR_RISE per step, well inside CLIMB_UP, so the animal
	# takes them one tread at a time like everything else does; what it still refuses is a
	# wall or a bunk frame.
	# A RISE TOO TALL TO STEP IS A RISE TO JUMP. Between CLIMB_UP and JUMP_UP the cat leaves
	# the ground properly — which is what the jump mesh is for, and it is also the honest
	# answer to a follower that used to give up at every crate and coaming it could plainly
	# get onto. Above JUMP_UP it still refuses: a cat does not scale a bulkhead.
	if rise > CLIMB_UP:
		if rise <= JUMP_UP and _jump_t <= 0.0 and _jump_wind <= 0.0 and _jump_cd <= 0.0 \
				and _reachable_up(ground) \
				and _step_clear(Vector3(want.x, ground, want.z), dir) \
				and _arc_clear(Vector3(want.x, ground, want.z), dir):
			# ...and the ARC has to be clear, not just the ledge. Same hole the pounce had:
			# `_fly_jump` drives the body along the path with no gates of its own, so a leap
			# onto a legal ledge can still pass the animal through whatever is between.
			#
			# ARM the leap rather than taking it: the crouch is held on the deck for the
			# anticipation beat (crouch -> launch -> flight -> land -> settle, a timeline,
			# not a pose), and _process fires the flight when the wind-up elapses.
			_jump_wind = 0.34
			_jump_from = global_position
			_jump_to = Vector3(want.x, ground, want.z)
			_jump_dur = JUMP_SEC        # the climb keeps its authored beat, unchanged
			if _rig != null:
				_rig.call("play_seq", [["jump_crouch", 0.34, 14.0]], "jump", 10.0)
		return
	# A step was taken — whatever pocket the stall counter was accumulating toward is open.
	_detour_stall = 0.0
	_drop_stall = 0.0
	# The slope it is standing on, for the body pitch. Taken from the rise over the step
	# actually taken rather than from a second probe, so it cannot disagree with the move.
	# THE GRADE IS A WINDOW, NOT A STEP (s45c — the owner's "cat should angle up/down when
	# going down stairs"). Per-step atan2 cannot see a staircase: on treads the rise is
	# zero for ~a dozen steps and then a whole tread's drop lands in one 26 mm step
	# (atan2 saturates the clamp for a single frame), so the eased slope averaged to a
	# flicker near zero and the animal descended flights dead level. Accumulate rise and
	# run in a ~0.45 m distance-decayed window instead: on a rig stair that reads the
	# flight's true ~40-degree grade, steady, from the second tread on — and on flat deck
	# it decays to zero the way the old code did.
	var run: float = maxf(step.length(), 0.0001)
	var wf: float = exp(-run / 0.45)
	_grade_dy = _grade_dy * wf + rise
	_grade_run = _grade_run * wf + run
	_slope = lerpf(_slope, clampf(atan2(_grade_dy, maxf(_grade_run, 0.05)), -0.7, 0.7),
		1.0 - exp(-5.0 * delta))
	var before_step: Vector3 = global_position
	global_position = Vector3(want.x, ground, want.z)
	_last_speed = speed
	# The blender's phase runs off DISTANCE ACTUALLY MOVED (see cat_rig.tick) — recorded
	# here, where the movement really happens, so a refused or slid step is felt by the
	# legs instead of them cycling against a wall.
	#
	# THE NODE-LEVEL BOB THAT LIVED HERE IS GONE, AND IT MUST NOT COME BACK. It ran on its
	# own `_gait` accumulator against a constant STRIDE_M (0.62) while the legs plant off
	# cat_rig's `_phase` against a stride derived from the animal's own bones (0.356 m at a
	# walk) — two clocks at nearly 2:1, so the body rose while a foot was mid-swing instead
	# of arcing over the planted one: the floating pelvis. The whole-body vertical now lives
	# in cat_rig.tick on the SAME phase the paws plant from, where drift is impossible.
	_moved_frame += global_position.distance_to(before_step)

## `+ PI` IS THE WHOLE OF "THE CAT WALKS BACKWARDS", and it was the only call site in the
## repo missing it.
##
## `atan2(d.x, d.z)` is the yaw that puts a node's LOCAL +Z on the target. Godot's forward
## is -Z, and CreatureAnim normalises every generated mesh so its head sits on the host's
## -Z (the blanket 180 yaw). So without the half turn the cat aimed its TAIL at wherever it
## was going. Every sibling — fauna_move.gd:511, bloom_fauna.gd:2927/2969/4423/4455 — adds
## it, one of them with the comment "this turns the head toward the player instead of
## pointing its tail at them".
##
## Confirmed three ways rather than reasoned once: the algebra above; tools/measure_facing.py
## reading +Z off cat_walk/cat_run/cat_sleep with both statistics agreeing, so no mesh error
## cancels it; and the rendered side view in tests/out/cat_bind.
## THE CAT IS A VOLUME, NOT A POINT — and until s36 every check in this file forgot that.
##
## `_walk_toward` probed the deck with a ray from the ORIGIN and tested for walls with a ray
## from the ORIGIN, so the origin could stop perfectly legally with half the animal inside
## the concrete. Measured off the drawn meshes, the horizontal half-diagonal runs 0.35-0.48 m
## across the pose set: that is how much cat a point-check is allowed to leave in a wall, and
## it is what the owner photographed — a cat embedded in a bulkhead with its head out one
## face and its body out the other.
##
## Radius is the body's half-WIDTH rather than that half-diagonal, and measured from the
## pose actually being drawn rather than typed: a cat is not a sphere, and a disc the size
## of its length could not fit through a doorway it walks through nose-first every day.
## The nose is covered separately by testing the far end of the body too (see _step_clear).
## ONE FOOTPRINT, CONSTANT, DERIVED — never again measured off the drawn meshes.
##
## The per-pose AABB version wedged the animal by construction, and the s45 COME probe
## caught it red-handed: the collision radius CHANGED WITH THE ANIMATION POSE (groom
## cached 0.100, run fatter), so a spot the cat legally walked into under one pose became
## illegal the moment its state changed — at (-21.9, 18, 12) the detour fan's +0.9
## candidate measured CLEAR at groom's radius and BLOCKED at run's, and the animal stood
## pinned for eight seconds in an open aisle it could plainly leave. Worse, the numbers
## were never the body at all: attach_rigged GROWS every MeshInstance's custom_aabb by
## half a metre for cull safety (a hand-driven skeleton corrupts the automatic bounds),
## and get_aabb() returns that grown box — the "measurement" was debug-box arithmetic
## saturating the clamp. A footprint that breathes cannot navigate; every character
## controller fixes the capsule and animates inside it. Derived from the recorded stand
## mesh proportions (AABB 1.0 x 0.566 x 0.265, tests/BoneDump; nose-to-tail scaled to
## STAND_SIZE_M), plus 30 mm of whisker.
const BODY_ACROSS_RATIO: float = 0.265
func _body_r() -> float:
	return STAND_SIZE_M * BODY_ACROSS_RATIO * 0.5 + 0.03

## Would the cat's BODY fit at `at`? A sphere query rather than a ray, so a step that leaves
## the origin outside a wall but the flank inside it is refused. Tested at the body centre
## and again at the nose, which is the one place a width-sized disc cannot see.
## `nose` FALSE tests the BODY ONLY — for points the animal is FLYING through rather than
## standing at. The nose probe exists because a WALKING cat's origin can be clear while its
## head is buried in a bulkhead; applied mid-leap it double-counts, because a cat rising
## beside a crate legitimately has its muzzle out over the crate top. With it on, every
## tight vertical hop refused itself: measured at a 1.0 m crate directly ahead, reach and
## landing both clear and `_arc_clear` FALSE on every frame, because the nose sphere 0.2 m
## ahead of a body climbing past the lip is inside the lip. The landing sample still asks
## the full question — that is where the animal has to stand and walk away.
func _step_clear(at: Vector3, dir: Vector3, extra_skip: Array = [], nose: bool = true) -> bool:
	var world: World3D = get_world_3d()
	if world == null:
		return true
	var r: float = _body_r()
	var sphere := SphereShape3D.new()
	sphere.radius = r
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.collision_mask = 1
	q.collide_with_areas = false
	var skip: Array[RID] = _walk_skip()
	for e in extra_skip:
		if e is RID:
			skip.append(e as RID)
	q.exclude = skip
	# `_body_r` is a half-width; the nose reaches roughly a body length ahead of centre, so
	# probe there too or the animal walks its head into a bulkhead and stops with the face
	# buried while its centre is legally clear.
	var lead: float = _body_len() * 0.5 - r
	var probes: Array = [at + Vector3(0, r + 0.04, 0)]
	if nose:
		probes.append(at + dir * maxf(lead, 0.0) + Vector3(0, r + 0.04, 0))
	for probe in probes:
		q.transform = Transform3D(Basis.IDENTITY, probe)
		if not world.direct_space_state.intersect_shape(q, 1).is_empty():
			return false
	return true

## Fixed for the same reason as _body_r: the live-AABB version read the grown cull boxes
## and swung with the pose. The animal is STAND_SIZE_M long; that is what the nose probe
## should reach for, in every pose, for ever.
func _body_len() -> float:
	return STAND_SIZE_M

## THE SAFETY NET, and the reason this can be called "no glitches" rather than "fewer".
##
## Every gate above is predictive — it refuses a step that WOULD bury the animal. None of
## them can rescue a cat that is already buried, and a raycast fundamentally cannot: a ray
## whose origin lies inside a shape does not report that shape in Godot, so once the animal
## is in the concrete the entire detection scheme goes silent and it stays there for the
## session. That is what shipped, and it is why the owner's frame exists.
##
## So this runs every frame regardless of state: sweep the body sphere, take the deepest
## contact, and push straight back out along the contact normal. It cannot be defeated by a
## new movement path, by another session moving a wall onto the cat, or by a spawn point
## that turns out to be inside geometry.
func _unbury() -> void:
	var world: World3D = get_world_3d()
	if world == null:
		return
	var r: float = _body_r()
	var sphere := SphereShape3D.new()
	sphere.radius = r
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = _walk_skip()
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, r + 0.04, 0))
	var pairs: PackedVector3Array = world.direct_space_state.collide_shape(q, 8)
	if pairs.size() < 2:
		return
	# collide_shape returns [point_on_us, point_on_them, ...]. The vector between the pair
	# IS the overlap; take the deepest and step out along it.
	var push := Vector3.ZERO
	var worst: float = 0.0
	for i in range(0, pairs.size() - 1, 2):
		var sep: Vector3 = pairs[i] - pairs[i + 1]
		if sep.length() > worst:
			worst = sep.length()
			push = sep
	if worst <= 0.0005:
		return
	push.y = 0.0
	if push.length() < 0.0005:
		return
	global_position += push.normalized() * (worst + 0.02)
	_reseat()

## ---------------------------------------------------------------- persistence
##
## THE CAT HAD NO SAVE SECTION AT ALL, and the design's very first promise is the one that
## broke: "FOUND, not spawned at you... ONCE, and then for good. There is no befriending
## minigame and no trust meter. You reach out, it accepts, and that is the last decision
## either of you makes about it." `friend` was a plain var, so every reload made the animal
## a stranger again — the player had to re-befriend the cat every session, and the toast
## that is meant to happen once in a run happened every time they loaded.
##
## Saved here rather than left to a generic walker because these are DECISIONS the player
## made (met it, told it to stay, fed it today), not world geometry that gets rebuilt.
## `_stay_spot` rides along because a STAY that forgets WHERE is a different instruction on
## reload, and `_fed_game_h` because it is measured in absolute game hours precisely so it
## survives a slept night — surviving a save is the same requirement.
##
## Deliberately NOT saved: the behaviour state, the hunt beat, the pose, the trail. Those
## are momentary and the animal should wake up doing whatever its situation calls for; a
## restored mid-pounce would be a bug, not a feature.
func save_state() -> Dictionary:
	return {
		"friend": friend,
		"stayed": _stayed,
		"stay_spot": [_stay_spot.x, _stay_spot.y, _stay_spot.z],
		"fed_game_h": _fed_game_h,
		"energy": _energy,
	}

## Restore, defensively — every field optional, every type checked. A save written before
## this existed simply leaves the cat as it spawns, which is the old behaviour exactly.
func restore_state(d: Variant) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	var s: Dictionary = d
	friend = bool(s.get("friend", false))
	_stayed = bool(s.get("stayed", false))
	var sp: Variant = s.get("stay_spot", null)
	if sp is Array and (sp as Array).size() == 3:
		_stay_spot = Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
	_fed_game_h = float(s.get("fed_game_h", -1000.0))
	_energy = clampf(float(s.get("energy", 0.6)), 0.0, 1.0)
	# The handle's verbs are the player-visible half of `friend` and `_stayed`, and they are
	# set at interaction time — so a restored cat that skipped the interaction would offer
	# SAY HELLO to someone it already knows.
	if _touch != null:
		_sync_verbs()
	# A cat restored as a friend is a companion, not the stranger `_ready` left grooming.
	_enter(State.SIT if _stayed else State.FOLLOW) if friend else _enter(State.GROOM)

## ONE POINT ON THE LEAP ARC — used by BOTH the flight and the clearance check, because
## these were two copies of the same formula and a check that models a different path from
## the one flown is worse than no check at all.
##
## THE HORIZONTAL LAGS ON A STEEP LEAP, and that is the difference between a cat and a
## trebuchet. A constant-rate horizontal over a symmetric parabola is fine for a long flat
## bound and wrong for the commonest jump there is — onto something directly in front of
## you: at 35% of a 1.0 m rise over a 0.63 m run the animal is only 0.35 m up and already
## a third of the way in, i.e. INSIDE the crate it is trying to land on. Measured exactly
## that way (tests/LeapScratch.tscn: reach true, top clear true, arc FALSE, every frame) —
## the leap was refusing itself on a path no cat would take. A real cat rises almost
## vertically off the hocks and translates late, so the horizontal is eased by an exponent
## that grows with the rise-over-run: flat leaps keep their old linear travel exactly.
##
## A DROP NEEDS THE OPPOSITE EASING IN BOTH AXES, and the up formula does not merely look
## wrong on a descent, it is degenerate: `steep` clamps at 0 for any negative rise, so the
## horizontal runs linear, and `lift = maxf(rise, 0) * 0.35 + 0.14` throws the whole drop away
## — a ten-metre fall drawn as a straight line with a 0.14 m hump on it, at constant vertical
## speed, which is a cat on a zip wire. Gravity is the other way round from a leap: HORIZONTAL
## EARLY (the push-out off the ledge happens at the top, and there is nothing to accelerate it
## afterwards) and VERTICAL LATE (k², because that is what falling is). Both the flight and
## `_arc_clear` read this one function, and now so does the descent's nose-down pitch, so
## nothing can model a path the animal does not fly.
func _arc_point(from: Vector3, to: Vector3, k: float) -> Vector3:
	var rise: float = to.y - from.y
	var run: float = Vector2(to.x - from.x, to.z - from.z).length()
	if rise < -0.02:
		# The horizontal FRONT-LOADS, harder the steeper the drop: a cat stepping off a ten
		# metre ledge is over the edge in the first fifth of the fall and travelling nowhere
		# for the rest of it.
		var steep_d: float = clampf(-rise / maxf(run, 0.05), 0.0, 6.0)
		var kh_d: float = pow(k, 1.0 / (1.0 + steep_d * 0.55))
		return Vector3(
			lerpf(from.x, to.x, kh_d),
			lerpf(from.y, to.y, k * k) + sin(k * PI) * DROP_HOP,
			lerpf(from.z, to.z, kh_d))
	var steep: float = clampf(rise / maxf(run, 0.05), 0.0, 2.0)
	var kh: float = pow(k, 1.0 + steep)
	var lift: float = maxf(rise, 0.0) * 0.35 + 0.14
	return Vector3(
		lerpf(from.x, to.x, kh),
		lerpf(from.y, to.y, k) + sin(k * PI) * lift,
		lerpf(from.z, to.z, kh))

## HOW LONG A FALL OF `drop` METRES TAKES. t = sqrt(2h/g), floored so a 0.2 m step down is
## still a beat rather than a snap and capped so nothing can hang in the air.
func _drop_secs(drop: float) -> float:
	return clampf(sqrt(2.0 * maxf(drop, 0.0) / DROP_G), DROP_SEC_MIN, DROP_SEC_MAX)

## MAY THE CAT LEAP UP TO `top`, OR WOULD IT STRAND ITSELF THERE?
##
## THIS IS THE RULE THE PREVIOUS ATTEMPT LACKED, and its absence is why that attempt was
## reverted. s38 made high ledges visible to the jump gate (the same fix that sits above
## this) and CatHuntProbe immediately caught the animal at y 20.26 — 2.26 m above the deck,
## having climbed a STAIRCASE OF LEDGES, one legal 0.6-1.2 m hop at a time, each one fine
## on its own, with no way back down. `JUMP_UP`'s own comment warns about exactly that:
## "an animal that leaps onto things the level design assumed were out of reach".
##
## A longer ray cannot fix it because the fault is not perception, it is the lack of a
## stopping condition. The condition that works is the companion contract itself: this cat
## follows a person, that person is standing on a deck the level design says is walkable,
## and no cat needs to be more than one leap above the human it is following. So the ceiling
## is the PLAYER's own height plus one jump. It is free (no query), it cannot be climbed
## incrementally (every hop is measured against the same absolute reference, not against the
## last one), and it self-releases the moment the player goes up too — follow someone up the
## stair tower and the cat may hop the crates on that deck, exactly as it should.
##
## DOWN HAS ITS OWN RULE AND IT IS NOT THIS ONE. The line that used to sit here said "down is
## never gated: falling back to the deck is what `_walk_toward`'s own probe does, and an animal
## that may descend can always undo a mistake." Every clause of that was false. The probe
## reaches 1.85 m, so it cannot see a descent worth the name; `_step_clear` refused every
## down-step there was (see the descent branch in `_walk_toward`); and the mistake the animal
## could not undo was the ordinary one of hopping onto a workbench. Whatever gates a descent, it
## must NOT be a copy of this function — this one returns false when there is no player, which
## is the right answer to "may I climb" (no one to follow) and a cruel one to "may I get down".
## A stranded cat with nobody on the rig still has to be able to get off the bench.
func _reachable_up(top: float) -> bool:
	var player: Node3D = AIB.player(self)
	if player == null:
		# No one to follow, no reason to climb. Refusing is the safe half of the branch:
		# the animal simply walks round whatever it is, which is what it did before leaps
		# existed at all.
		return false
	return top <= player.global_position.y + JUMP_UP

# --------------------------------------------------------------- the water, and the way down

## IS `at` AT OR UNDER THE SEA?
##
## ONE SOURCE OF TRUTH, and it is `swim_line` rather than `wave_height` because this file
## already tested against `swim_line` in its trail recorder — a cat using the drawn surface in
## one gate and the swim line in another would disagree with itself by SWIM_SCALE * swell. The
## +0.1 m margin is that same line's margin, so "the cat will not go in the water" means
## exactly what "you are swimming" means to the player, main.gd and underwater_fx.
##
## DELIBERATELY NOT INSIDE `_step_clear`. That function is called mid-flight from `_fly_jump`
## and from every sample of `_arc_clear`, where the cat is legitimately airborne over whatever
## it is crossing; a water test there would abort every legal arc over the sea and, worse,
## would do it from inside the one gate the whole movement system trusts.
func _over_water(at: Vector3) -> bool:
	return at.y < Gyre.swim_line(Vector2(at.x, at.z), Gyre.water_time()) + 0.1

## IS THERE REAL, DRY DECK AT `at`, and where exactly? Returns the grounded point or INF.
##
## The same probe `_walk_toward` uses, made callable — because three separate behaviours (the
## play spot, the pounce landing, the zoomie heading) each named a position and then validated
## it with `_step_clear` ALONE, which is a VOLUME query: empty air over the open sea passes it
## with flying colours. That is how the cat got out over the water in the first place, and
## `_play` — a spot drawn blind 1.6-3.4 m in a random direction every PLAY_CD 38 s, then
## POUNCED at — is the likeliest single route of the three.
func _deck_at(at: Vector3, reach: float = 1.4) -> Vector3:
	var world: World3D = get_world_3d()
	if world == null:
		return Vector3.INF
	var from: Vector3 = at + Vector3(0, STEP_UP + 0.3, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, STEP_UP + reach, 0))
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = _walk_skip()
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return Vector3.INF
	var p: Vector3 = hit["position"]
	if _over_water(p):
		return Vector3.INF
	return p

## WHERE WOULD A STEP OFF THE LEDGE ON HEADING `hd` LAND? INF if the answer is "nowhere it
## should go". Called only from the descent branch, only on frames the direct step was already
## refused, so the cost is paid by cats that are actually stuck.
##
## The probe starts a body-length out — `want` is 16 mm ahead, which is still over the thing the
## cat is standing on, so a ray there measures the bench top and reports no drop at all. Same
## mistake, same distance, as the ledge probe's first cut (see its comment).
func _drop_landing(hd: Vector3) -> Vector3:
	var world: World3D = get_world_3d()
	if world == null:
		return Vector3.INF
	var out: Vector3 = global_position + hd * (_body_len() * 0.95)
	var from: Vector3 = out + Vector3(0, 0.30, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, DROP_MAX + 0.5, 0))
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = _walk_skip()
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return Vector3.INF      # nothing within DROP_MAX — that is a cliff, not a step down
	var land: Vector3 = hit["position"]
	var fell: float = global_position.y - land.y
	if fell <= 0.02 or fell > DROP_MAX:
		return Vector3.INF
	# The sea is not a landing, and this is the gate that stops the descent branch from being
	# a licence to walk off the rig into the water.
	if _over_water(land):
		return Vector3.INF
	# It has to be able to STAND there (full nose probe — this is where it walks away from) and
	# the whole fall has to be clear of the structure it is dropping past.
	if not _step_clear(land, hd):
		return Vector3.INF
	if not _arc_clear(land, hd):
		return Vector3.INF
	return land

## ARM A JUMP DOWN, if there is one to be had. Returns true when the leap is armed and the
## caller must stop moving the animal this frame.
##
## Called from the two places in `_walk_toward` where a descent can be the answer: the refused
## step (a lip inside the footfall ray's reach — the bench) and the empty footfall ray
## (anything taller than 1.85 m, where the deck below is invisible to that probe entirely).
## Both callers have already established that the animal is trying to get to somewhere LOWER.
func _try_descend(dir: Vector3, delta: float) -> bool:
	_drop_stall += delta
	# The way it is facing, first — a cat gets off a thing the way it is already pointed. Only
	# after DROP_STALL seconds of getting nowhere does it look over the other edges: that is
	# the stranding escape hatch, and every other wedge in this file has one (_detour_stall
	# 0.35, _bed_stall 2.5, _trail_stall 0.9).
	var headings: Array[Vector3] = [dir]
	if _drop_stall > DROP_STALL:
		for a in [0.8, -0.8, 1.6, -1.6, 2.4, -2.4, PI]:
			headings.append(dir.rotated(Vector3.UP, float(a)))
	for hd in headings:
		var land: Vector3 = _drop_landing(hd)
		if land == Vector3.INF:
			continue
		# Armed exactly as the up-jump is — the crouch is held ON THE DECK for the anticipation
		# beat and `_process` fires the flight when the wind-up elapses. The wind-up scales with
		# the drop: a fixed 0.34 s gather before a 0.2 m step off a coaming is a cat pretending
		# to be a diver, while one facing four metres genuinely does hesitate.
		var fell: float = global_position.y - land.y
		_jump_wind = 0.10 + 0.24 * clampf(fell / DROP_MAX, 0.0, 1.0)
		_jump_from = global_position
		_jump_to = land
		_jump_dur = _drop_secs(fell)
		_drop_stall = 0.0
		_face(land, delta)
		if _rig != null:
			_rig.call("play_seq", [["jump_crouch", _jump_wind, 14.0]], "jump", 10.0)
		return true
	return false

## NOTHING UNDER THE CAT: FALL. Returns true while the fall owns the animal.
##
## This is the `else` `_reseat` never had, made visible. It is a real integration rather than a
## snap to the surface because an 18 m teleport reads as a bug even when it is a fix, and
## because the whole file's rule is that anything time-based here runs on `1 - exp(-rate*dt)` or
## on an accumulated velocity — never on a per-call constant, since AiBudget hands out summed
## deltas up to 0.15 s.
func _fall_step(delta: float) -> bool:
	if _reseat():
		_fall_v = 0.0
		return false
	_fall_v = minf(_fall_v + FALL_G * delta, FALL_VMAX)
	var surf: float = Gyre.swim_line(
		Vector2(global_position.x, global_position.z), Gyre.water_time())
	# It never falls THROUGH the sea: the swim line is the floor of the fall, and `_over_water`
	# picks the animal up from there on the next think.
	global_position.y = maxf(global_position.y - _fall_v * delta, surf - 0.02)
	_last_speed = 0.0
	_moved_frame = 0.0
	if _rig != null:
		# Reaching for a landing it cannot see, which is what a falling cat does. Grammar-free
		# (`play_seq([], …)`) for the same reason the flight is — the family grammar would
		# route this through the sit machinery.
		_rig.call("play_seq", [], "jump_descend", 10.0)
		_rig.call("slope", -0.35)
	return true

## IT IS IN THE SEA. Tread water, find something to climb out onto, climb out.
##
## The owner's rule is "the cat never goes in the water; if it does, it treads water back
## toward the nearest landing and climbs back aboard" — so this is a RECOVERY, not a feature: no
## behaviour above chooses it and nothing here is on a cooldown. It also cannot use
## `_walk_toward`, whose deck ray refuses every step at sea by construction (that refusal is
## Bug B's fix and it is correct); a swimming animal needs a mover of its own.
func _swim(delta: float) -> void:
	_enter(State.SWIM)
	var t: float = Gyre.water_time()
	var surf: float = Gyre.swim_line(Vector2(global_position.x, global_position.z), t)
	# RIDE THE SURFACE, EASED. `1 - exp(-rate*dt)` like every other ease in this file: the
	# swell moves under the animal and a lerp with a bare `delta * k` overshoots on a summed
	# 0.15 s think. The vertical goes on the ROOT, never on `_body` — `_body.position` and
	# `_body.rotation` are forced to zero every frame and CatJointProbe asserts it.
	global_position.y = lerpf(global_position.y, surf - SWIM_SINK, 1.0 - exp(-SWIM_RISE * delta))
	# ...AND A HARD FLOOR UNDER THE EASE. Measured on the first run: the cat spent frames up to
	# 0.72 m below the swim line, because an exponential ease chasing a moving surface always
	# lags and AiBudget can hand this animal a 0.15 s think. A cat treading water is AT the
	# surface — the ease is there to keep the ride smooth, not to let the animal submerge.
	global_position.y = maxf(global_position.y, surf - SWIM_SINK - SWIM_LAG_MAX)
	_fall_v = 0.0
	# WHERE IS THE WAY OUT? Probed, on a throttle — never a hand-typed dock position.
	_swim_scan -= delta
	if _swim_scan <= 0.0 or _board == Vector3.INF:
		_swim_scan = SWIM_SCAN_CD
		_board = _find_board(surf)
	# Failing a visible lip, steer at the last place the seat ray proved was ground. That is
	# the only point in the world this animal can show its own working on, and it is where it
	# came from, so it is by construction reachable from somewhere near here.
	var goal: Vector3 = _board if _board != Vector3.INF else _last_ground
	if goal == Vector3.INF:
		goal = HOME
	var to: Vector3 = goal - global_position
	to.y = 0.0
	var span: float = to.length()
	_watch(goal + Vector3(0, 0.4, 0), 0.9)
	if span > 0.05:
		var dir: Vector3 = to / span
		_face(goal, delta)
		# CLIMB OUT the moment the lip is inside one jump: the ordinary up-jump, armed the
		# ordinary way, deliberately WITHOUT `_reachable_up` — that gate encodes the follow
		# contract ("no cat needs to be more than one leap above the human it is following")
		# and refuses outright when there is no player, which must not be able to hold an
		# animal in the water.
		if _board != Vector3.INF and span < _body_len() * 1.6 \
				and _board.y - global_position.y <= JUMP_UP \
				and _jump_t <= 0.0 and _jump_wind <= 0.0 and _jump_cd <= 0.0 \
				and _step_clear(_board, dir) and _arc_clear(_board, dir):
			_jump_wind = 0.20
			_jump_from = global_position
			_jump_to = _board
			_jump_dur = JUMP_SEC
			if _rig != null:
				_rig.call("play_seq", [["jump_crouch", 0.20, 14.0]], "jump", 10.0)
			return
		# The paddle. Body-checked like a walk step, because the rig's legs and pontoons are
		# solid at the waterline and a swimming cat must not be pushed into one.
		var want: Vector3 = global_position + dir * minf(SWIM_SPEED * delta, span)
		if _step_clear(want, dir, [], false):
			var before: Vector3 = global_position
			global_position.x = want.x
			global_position.z = want.z
			_moved_frame += global_position.distance_to(before)
			_last_speed = SWIM_SPEED
		else:
			# Blocked at the waterline — work along the obstruction rather than pressing into
			# it. Same idea as the detour fan, four candidates instead of eight.
			for a in [0.9, -0.9, 1.8, -1.8]:
				var alt: Vector3 = dir.rotated(Vector3.UP, float(a))
				var aw: Vector3 = global_position + alt * SWIM_SPEED * delta
				if _step_clear(aw, alt, [], false):
					global_position.x = aw.x
					global_position.z = aw.z
					_moved_frame += SWIM_SPEED * delta
					_last_speed = SWIM_SPEED * 0.7
					break
	if _rig != null:
		# Nose up out of the water, the one thing every photograph of a swimming cat has in
		# common. Through the rig's trunk pitch, never the node.
		_rig.call("slope", 0.22)

## SOMEWHERE TO CLIMB OUT ONTO, or INF. A ring scan: for each heading and radius, ray down
## through the waterline and keep the first surface that stands proud of the sea by more than
## the margin and is no more than one jump above the swimming cat.
##
## PROBED, NEVER TYPED — the standing rule. A hand-written "the boat landing is at (x, z)"
## would be the same class of bug as every floating prop this repo has fixed, and it would be
## wrong the first time somebody moves the pontoon.
func _find_board(surf: float) -> Vector3:
	var world: World3D = get_world_3d()
	if world == null:
		return Vector3.INF
	var skip: Array[RID] = _walk_skip()
	var best: Vector3 = Vector3.INF
	var best_d: float = 1e9
	# Bias the search toward where the animal came from, so a cat that fell off the west side
	# does not set out for the east one: the nearest lip wins, and `_last_ground` breaks ties
	# by being what the fallback steers at anyway.
	for r in [1.0, 2.0, 3.2, 4.6, BOARD_SCAN_M]:
		for i in range(12):
			var a: float = TAU * float(i) / 12.0
			var at: Vector3 = global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
			var from: Vector3 = Vector3(at.x, surf + JUMP_UP + 0.4, at.z)
			var q := PhysicsRayQueryParameters3D.create(
				from, Vector3(at.x, surf - 0.6, at.z))
			q.collision_mask = 1
			q.collide_with_areas = false
			q.exclude = skip
			var hit: Dictionary = world.direct_space_state.intersect_ray(q)
			if hit.is_empty():
				continue
			var p: Vector3 = hit["position"]
			if _over_water(p):
				continue      # a submerged shelf is not a way out of the water
			if p.y - global_position.y > JUMP_UP:
				continue
			if not _step_clear(p, (p - global_position).normalized()):
				continue
			var dd: float = global_position.distance_squared_to(p)
			if dd < best_d:
				best_d = dd
				best = p
		if best != Vector3.INF:
			break      # nearest ring wins; no reason to scan further out
	return best

# ------------------------------------------------------------------ the bait trail

## THE PLAYER'S OWN FOOTSTEPS, WHICH ARE THE ONLY NAVIGATION DATA THIS GAME HAS THAT IS
## GUARANTEED CORRECT.
##
## Steering at where the player IS draws a straight line, and a straight line across this rig
## goes through steel. The detour fan then has to solve — greedily, one 0.05 m step at a time,
## with every candidate confined to +-115 deg of "toward the player" — a routing problem the
## human already solved with their feet. It cannot, and the failure is not subtle: from the
## west bunk cabin the only opening is at x -24.665 (rig_builder._build_bunkhouse cuts a 1.4 m
## hole at the centre of each 6.67 m corridor segment; the dividers at x -21.33 / -14.66 are
## solid from z4 to z10), so a cat whose player walked EAST must first travel three metres
## WEST. No heading in the fan points there. It slides up and down the divider until something
## else interrupts it.
##
## So the cat follows the TRAIL. Every crumb is a place a body already stood, at a height a
## body already reached, joined to the next by a step a body actually took — a proof of
## walkability nothing in this file could synthesise, laid down for free by the player as they
## walk. Doorways, corners and stair flights come out right because the human routed through
## them, not because the cat understands them.
##
## THE TRAIL IS A HINT, NEVER A RAIL. Anything that makes it unavailable — a fresh session, a
## teleport, a player who swam off, a cat a harness moved across the rig — falls straight back
## to the direct line and the detour fan, i.e. exactly the animal that shipped in s45. There is
## no state in which this can stall it.
const TRAIL_STEP: float = 0.6      ## metres of PLAYER travel between crumbs
## 64 crumbs is 38 m of PATH, and path is the quantity that matters: the follow distances are
## straight-line (FOLLOW_NEAR 2.2, RUN_M 8, FOLLOW_FAR 14) while a route through these rooms
## runs two to three times its own chord. 768 bytes.
const TRAIL_MAX: int = 64
## A move no walking body could make in one physics tick. Physics runs at 30 Hz here, so a
## sprinting player (SPRINT_SPEED 5.0) covers 0.167 m; past 0.9 m the two positions are not
## joined by a step and the segment between them is a line through whatever stood in the way.
## One rule, and it covers every teleport in the game: _respawn, the death respawn, the ladder
## top, and the harnesses — CatProbe teleports the player a dozen times, so the trail is empty
## for every one of its existing checks and none of them change behaviour.
const TRAIL_JUMP: float = 0.9
## "I am standing on this crumb." Above the worst distance one think can cover (RUN_SPEED 4.4
## x AiBudget.MAX_STEP 0.15 = 0.66 m), so a running cat cannot overshoot the whole radius and
## be dragged backwards onto a crumb it has already passed.
const JOIN_NEAR: float = 1.0
## ...and how far off the thread it may be and still walk back to it. Beyond this the trail is
## not a route to anywhere useful and the direct line is honest.
const JOIN_FAR: float = 5.0
## Seconds pinned on one crumb before the thread is walked on regardless — the anti-wedge for
## a crumb the cat can see but cannot stand on (the player squeezed past furniture it cannot).
const TRAIL_STALL: float = 0.9
const PULL_M: float = 3.0          ## how long a shortcut may be, and therefore proven
const PULL_SEC: float = 0.25       ## how often the shortcut tests run
const PULL_TRIES: int = 2          ## crumbs that may be skipped per test
const SEG_SAMPLE_M: float = 0.35   ## roughly what one _step_clear (centre + nose) covers
const LOOK_M: float = 0.8          ## the lookahead blend distance
## The slow into a hard turn. A real cat does not take a doorway at a trot; TURN_EASE_RAD is
## the yaw error at which the ease bottoms out (1.6 rad = 92 deg, i.e. a square corner), and
## the floor is a slow, never a stop.
const TURN_EASE_RAD: float = 1.6
const TURN_EASE_MIN: float = 0.45
const TURN_EASE_RATE: float = 6.0
## ...AND A DEADZONE, WITHOUT WHICH THIS IS A TAX RATHER THAN A CHARACTER BEAT. The first
## cut ramped straight from zero error, so an ordinary 0.2 rad steering correction — which
## happens continuously while following a moving target — cost 12% of speed, permanently,
## on every straight. Measured: the settle and COME checks in CatProbe both went red purely
## from the compounded slowdown. A real cat does not brake for a ten-degree correction; it
## brakes for a doorway. Full speed inside 20 deg, ramping to the floor at the square corner.
const TURN_EASE_DEAD: float = 0.35

## RECORDING IS NOT THINKING, SO IT DOES NOT GO THROUGH AiBudget.
##
## The whole of this animal's decision-making runs decimated on summed deltas, which is
## correct — but a decimated RECORDER samples the player up to 0.15 s apart, and 0.15 s of a
## sprint is 0.9 m. That is longer than the crumb spacing, which means two consecutive crumbs
## could straddle a doorway with the segment between them running through the jamb: the trail
## would be recording a route the player never took. Physics ticks are fixed and never summed
## (the s38 shutter trap cannot reach them either), so the sampling here is 0.167 m at the
## worst, whatever the frame rate is doing.
##
## Cost is one distance compare per tick, plus one ray every 0.6 m of player travel — about
## four rays a second at a walk.
func _physics_process(_delta: float) -> void:
	var player: Node3D = AIB.player(self)
	if player == null:
		_trail_prev = Vector3.INF
		return
	var p: Vector3 = player.global_position
	var prev: Vector3 = _trail_prev
	_trail_prev = p
	if prev == Vector3.INF:
		return
	if p.distance_squared_to(prev) > TRAIL_JUMP * TRAIL_JUMP:
		_trail.clear()
		return
	if _trail.size() > 0 \
			and p.distance_squared_to(_trail[_trail.size() - 1]) < TRAIL_STEP * TRAIL_STEP:
		return
	var world: World3D = get_world_3d()
	if world == null:
		return
	# A CRUMB IS A FOOTFALL, NOT A POSITION. Probed rather than taken from the player's origin
	# for two reasons: it puts the crumb on the deck, where the cat's own origin lives (see
	# _reseat), so the two are comparable; and the probe IS the walkability gate — no deck
	# within reach means the player is swimming, falling, flying or halfway up a ladder, and
	# none of those are places a cat can be baited to.
	var from: Vector3 = p + Vector3(0, 0.9, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 1.6, 0))
	q.collision_mask = 1
	q.collide_with_areas = false
	q.exclude = _walk_skip()
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var foot: Vector3 = hit["position"]
	# ...AND IT MUST BE OUT OF THE SEA. A submerged surface passes the probe perfectly well —
	# the boat landing sits at y -3..1 — so the ray alone would happily bait the cat into the
	# water off the end of a dive. Same swim line the player, main.gd and underwater_fx test
	# against, so "the cat will not follow you in" means what it means everywhere else.
	if foot.y < Gyre.swim_line(Vector2(foot.x, foot.z), Gyre.water_time()) + 0.1:
		return
	if _trail.size() > 0 \
			and _trail[_trail.size() - 1].distance_squared_to(foot) > TRAIL_JUMP * TRAIL_JUMP:
		_trail.clear()
	_trail.push_back(foot)
	while _trail.size() > TRAIL_MAX:
		_trail.remove_at(0)

## Where to steer THIS frame: a point on the player's route, or the player themselves when the
## trail has nothing better to say. Never returns something that cannot be walked at.
func _trail_goal(ppos: Vector3, delta: float) -> Vector3:
	_trail_live = false
	_pull_cd -= delta
	var n: int = _trail.size()
	if n < 2:
		# One crumb is a spot, not a route — and steering at a spot the cat is already on is
		# the one way this could stall the animal.
		_trail_stall = 0.0
		return ppos
	# 1. WHERE ON THE THREAD AM I? Free — distance compares, no physics. Scanned NEWEST first,
	# which is how "a cat does not retrace a loop you walked" falls out for nothing: where the
	# route doubles back past itself, the later pass wins and the loop is never re-walked.
	var join: int = -1
	for i in range(n - 1, -1, -1):
		if global_position.distance_squared_to(_trail[i]) <= JOIN_NEAR * JOIN_NEAR:
			join = i
			break
	if join < 0:
		# Off the thread — after a COME, a harness move, or a spell blocked. Rejoin at the
		# NEAREST crumb, deliberately not the newest: at five metres "newest" is an unproven
		# shortcut through a bulkhead, which is the bug this whole section exists to fix.
		var best: float = JOIN_FAR * JOIN_FAR
		for i in range(n - 1, -1, -1):
			var dd: float = global_position.distance_squared_to(_trail[i])
			if dd < best:
				best = dd
				join = i
	if join < 0:
		_trail_stall = 0.0
		return ppos
	if join > 0:
		_trail = _trail.slice(join)
		_trail_stall = 0.0
	else:
		_trail_stall += delta
		if _trail_stall > TRAIL_STALL and _trail.size() > 1:
			# A crumb the player reached and the cat cannot (squeezed past a chair leg, say).
			# Walking the thread on is bounded and always makes progress; standing on it is
			# the wedge.
			_trail.remove_at(0)
			_trail_stall = 0.0
	# 2. THE STRING-PULL — the only physics this costs, throttled and LATCHED. Latched because
	# a shortcut re-decided every frame is the same flip-flop the fan's side commitment cures:
	# the aim point would alternate between the player and a crumb at frame rate.
	if global_position.distance_to(ppos) > PULL_M:
		_pull_free = false
	if _pull_cd <= 0.0:
		_pull_cd = PULL_SEC
		_pull_free = global_position.distance_to(ppos) <= PULL_M and _seg_clear(ppos)
		if not _pull_free:
			for _k in range(PULL_TRIES):
				if _trail.size() < 2 or global_position.distance_to(_trail[1]) > PULL_M \
						or not _seg_clear(_trail[1]):
					break
				_trail.remove_at(0)
				_trail_stall = 0.0
	if _pull_free or _trail.size() < 2:
		return ppos
	# 3. THE AIM POINT, WHICH IS WHY IT ROUNDS A CORNER INSTEAD OF CLIPPING IT. Slid along the
	# segment between the crumb it is on and the next one as it closes, so the animal is always
	# chasing a point a little further round the turn than itself and starts turning early.
	# It cannot aim into geometry: a point between two crumbs 0.6 m apart is ON the path the
	# player walked, by construction.
	_trail_live = true
	var c0: Vector3 = _trail[0]
	return c0.lerp(_trail[1],
		clampf(1.0 - global_position.distance_to(c0) / LOOK_M, 0.0, 1.0))

## Could the cat WALK the straight line from here to `to`? The crumbs prove the route the
## player took; this proves a shortcut ACROSS it.
##
## SAMPLED ON THE GROUND, NOT ON THE CHORD, and that distinction is the whole of stairs. A
## staircase surface is a zigzag of treads and risers, so the straight line between two points
## on it passes through the NOSING of every tread between them — a chord test calls every
## flight on this rig a wall, and the cat would refuse to string-pull up a stair it is standing
## on. Each sample is instead dropped onto whatever deck is under it with the same probe (and
## the same 1.1 m of downward reach) `_walk_toward` uses, and handed to the same `_step_clear`
## volume query, so a line this accepts is a line that function can actually walk. A sample
## more than CLIMB_UP above the last is refused, which is "one tread yes, a bulkhead no" — and
## it is also what stops a shortcut cutting through a stairwell wall between two crumbs on
## different flights, because the deck under the middle of that line is a whole storey off.
func _seg_clear(to: Vector3) -> bool:
	var world: World3D = get_world_3d()
	if world == null:
		return true
	var flat: Vector3 = to - global_position
	flat.y = 0.0
	var span: float = flat.length()
	if span < 0.01:
		return true
	var dir: Vector3 = flat / span
	# Bounded twice over: PULL_M caps the span, and this caps the samples whatever that becomes.
	var steps: int = mini(int(ceil(span / SEG_SAMPLE_M)), 12)
	var skip: Array[RID] = _walk_skip()
	var last_y: float = global_position.y
	for i in range(1, steps + 1):
		var at: Vector3 = global_position + dir * (span * float(i) / float(steps))
		var from: Vector3 = Vector3(at.x, last_y + CLIMB_UP + 0.3, at.z)
		var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, CLIMB_UP + 1.4, 0))
		q.collision_mask = 1
		q.collide_with_areas = false
		q.exclude = skip
		var hit: Dictionary = world.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return false
		var g: float = (hit["position"] as Vector3).y
		if g - last_y > CLIMB_UP:
			return false
		if not _step_clear(Vector3(at.x, g, at.z), dir):
			return false
		last_y = g
	return true

## A REAL CAT SLOWS INTO A DOORWAY. Multiplied into the commanded speed rather than applied
## inside `_walk_toward`, so the stalk, the zoomies and the play pounce keep their own pacing.
## `1 - exp(-rate * dt)` because this animal is handed SUMMED deltas up to 0.15 s and the
## clamped form snaps — the standing rule for every ease in this file.
func _ease_turn(aim: Vector3, delta: float) -> float:
	var to: Vector3 = aim - global_position
	to.y = 0.0
	var want: float = 1.0
	if to.length_squared() > 0.0004:
		var turn: float = absf(wrapf(atan2(to.x, to.z) + PI - rotation.y, -PI, PI))
		want = clampf(1.0 - maxf(turn - TURN_EASE_DEAD, 0.0)
			/ maxf(TURN_EASE_RAD - TURN_EASE_DEAD, 1e-3), TURN_EASE_MIN, 1.0)
	_turn_slow = lerpf(_turn_slow, want, 1.0 - exp(-TURN_EASE_RATE * delta))
	return _turn_slow

## Everything the cat's WALL ray must not mistake for a wall: its own handle, the player,
## and every other animal's touch sphere. Rebuilt each call rather than cached, because
## fauna are spawned and freed through the session and a stale RID is a silent hole in the
## skip list — the cost is a handful of group lookups on an animal that already raycasts
## twice a step.
func _walk_skip() -> Array[RID]:
	var skip: Array[RID] = [_touch.get_rid()]
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player != null and is_instance_valid(player):
		if player is CollisionObject3D:
			skip.append((player as CollisionObject3D).get_rid())
		for c in player.find_children("*", "CollisionObject3D", true, false):
			skip.append((c as CollisionObject3D).get_rid())
	# THE OTHER ANIMALS, BY TAG — NOT BY SUBTREE, AND THAT DISTINCTION IS THE WHOLE FIX.
	#
	# What used to sit here read `fauna_bodies`, a STATIC FUNCTION on bloom_fauna, through
	# `Object.get()`, which returns null for a method name: the branch added nothing from s36
	# until this replaced it. The repair that looks obvious — walk the bloom_fauna subtree and
	# skip every CollisionObject3D under it — was written, measured and removed, because that
	# subtree carries the corvids' nest (a real LootContainer collider) as well as the animals.
	#
	# `BloomFauna.CREATURE_GROUP` is the tag that pass asked for, applied where each creature
	# collider is BUILT — FaunaTouch._init, and GlowWorm, which is its own Interactable — so
	# no scenery can be in it however the subtree is rearranged, and the animals parented
	# OUTSIDE bloom_fauna (leg_reef's thirteen climbing snails, which the subtree walk could
	# never reach — the s21 crab-stood-on-a-snail trap) are in it anyway.
	for n in get_tree().get_nodes_in_group(BloomFauna.CREATURE_GROUP):
		var body := n as CollisionObject3D
		if body == null or body == _touch:
			continue
		skip.append(body.get_rid())
	return skip

## THE STATES IN WHICH THE BODY YAW IS LOCKED. Owner, verbatim: "Dont have cat spin when
## sitting, has to look around, or get up to turn."
##
## `_face` is the ONE place this file turns the whole animal, and it did it in every state —
## so a seated cat tracked you by rotating on the spot at TURN_RATE, four paws welded to the
## deck, which is the same turntable defect the walk was cured of two sessions ago wearing a
## different hat. Chosen per state, and the reasoning is worth keeping:
##   * SIT    — the owner's case, and the one the player sees most.
##   * GROOM  — a washing cat is a sitting cat. It is also the pose whose whole read is the
##              head working over the body, which a rotating body destroys.
##   * PET    — seated, and being stroked. It presses its head into the hand (cat_rig.pet);
##              it does not swing its hindquarters round.
##   * PERCH  — a sit on top of something 0.9 m up. Turning on a crate top is worse than
##              turning on a deck, not better.
##   * SLEEP  — locked, and it does not even get the stand-turn-sit escape below: a sleeping
##              cat that stands up to re-aim itself at you is not asleep.
## STRETCH is deliberately NOT here — it is a standing pose and a transitional beat, and
## locking a transition is how a cat ends up facing the wrong way for the walk that follows.
const SEATED_STATES := [State.SIT, State.GROOM, State.PET, State.PERCH, State.SLEEP]
## How far off the body line the animal will track something with its HEAD alone before it
## decides the answer is to get up. 1.05 rad = 60 degrees, which is about where a real cat
## stops being comfortable looking over its own shoulder; the look layer's own share of that
## is split neck/head in cat_rig, so nothing here has to know about it.
const SEAT_ARC: float = 1.05
## ...and the whole get-up-turn-sit-down beat, plus how long before it may happen again. The
## cooldown is what stops a player circling the animal from turning it into a metronome.
const RESTAND_RISE: float = 0.34
const RESTAND_TURN_MAX: float = 1.6
const RESTAND_SETTLE: float = 0.30
const RESTAND_CD: float = 3.5

## Is the body yaw locked right now? Also true for the whole get-up-and-turn beat, because
## that beat owns the yaw itself and a behaviour calling `_face` underneath it would fight it.
func _seated() -> bool:
	return _state in SEATED_STATES

func _face(target: Vector3, delta: float) -> void:
	var to: Vector3 = target - global_position
	to.y = 0.0
	if to.length_squared() < 0.0004:
		return
	var want: float = atan2(to.x, to.z) + PI
	# A SEATED CAT TURNS ITS HEAD, OR IT GETS UP. It does not rotate.
	#
	# The head is already doing the tracking: every seated caller of this function calls
	# `_watch` on the same frame with the same target, and the look layer (cat_rig's neck/head
	# channel, rate-capped by HEAD_MAX_RATE) carries it. So the honest thing here is simply to
	# decline the yaw — and then, when the bearing has gone past what a neck can pay, to spend
	# the ONE thing a real cat spends on it: getting up.
	if _seated():
		# THE HEAD TAKES THE DEMAND THE BODY JUST REFUSED, and it is done HERE rather than left
		# to each caller for the reason this whole block exists: `_face` is the one choke point,
		# so hanging the substitute off it means no seated caller can silently lose its
		# attention. It matters most where it is least obvious — the PET branch calls `_face`
		# and `_idle_attention` returns early while `_pet_t` is up, so simply declining the yaw
		# there would have produced a cat that ignores the hand stroking it. 0.9 is below the
		# deliberate stare `_idle_step`'s survey claims (0.95) and above a wandering glance, and
		# `_watch` gives the frame to the strongest claim rather than the latest.
		_watch(target + Vector3(0, 0.9, 0), 0.9)
		var off: float = angle_difference(rotation.y, want)
		if absf(off) > SEAT_ARC and _restand_cd <= 0.0 and _state != State.SLEEP:
			_begin_restand(want)
		return
	# `1 - exp` rather than `clampf(k * delta)`: under an AiBudget-summed 0.15 s think the
	# clamped form covered 90% of a commanded half-turn in ONE frame (measured: the summed
	# path snapped the full 90 deg while the fixed path read 80.6 over the same sim time).
	rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-TURN_RATE * delta))

## STAND UP, TURN, SIT BACK DOWN — the only way a seated cat changes which way it points.
##
## Nothing here authors a pose timeline: `cat_rig.set_pose` already carries the transition
## grammar (sit family -> move family plays `rise`; move family -> sit family plays `sit_pre`
## then `sit_deep`), so wearing "stand" and then wearing the sit again IS the sequence the
## brief asks for, and it stays correct if that grammar is ever re-authored. Both pose names
## are checked against the library before the beat is allowed to start, because `set_pose`
## no-ops SILENTLY on a name it does not have and a beat built on a missing pose would look
## exactly like the spin it replaced.
func _begin_restand(yaw: float) -> void:
	if _rig != null and not bool(_rig.call("has_pose", "rise")):
		return
	_restand_yaw = yaw
	_restand_t = RESTAND_RISE + RESTAND_TURN_MAX + RESTAND_SETTLE
	_restand_sit = _state
	_restand_cd = RESTAND_CD
	_wear("stand")
	_act_note("restand")

func _restand_step(delta: float) -> void:
	_restand_t -= delta
	_last_speed = 0.0
	_reseat()
	# It keeps LOOKING at the thing the whole time — the head led, the body follows, which is
	# the order a cat actually does this in.
	_watch(global_position + Vector3(sin(_restand_yaw + PI), 0.35, cos(_restand_yaw + PI)) * 2.0,
		0.8)
	var turn_left: float = _restand_t - RESTAND_SETTLE
	if turn_left <= 0.0:
		# Settled: back into whatever seat it got up from, and the grammar plays the sit down.
		#
		# UNCONDITIONALLY, and the guard that used to be here (`if _state != _restand_sit`) was
		# a real bug: `_state` never LEFT the seat — only the worn POSE did, because that is how
		# the beat borrows the animal — so the guard was false every time and the cat finished
		# the turn standing up in a `stand` pose that nothing would ever clear. `_enter` is
		# idempotent (`set_pose` returns early on a name it is already wearing).
		_enter(_restand_sit)
		if _restand_t <= 0.0:
			_restand_t = 0.0
		return
	if _restand_t > RESTAND_TURN_MAX + RESTAND_SETTLE:
		return           # still rising — the rear lifts before anything turns
	# THE TURN ITSELF, and it goes through `rotation.y` directly rather than through `_face`,
	# because `_face` is exactly what is locked. Standing, so this is a cat turning on its
	# feet, not a seated body swinging round.
	rotation.y = lerp_angle(rotation.y, _restand_yaw, 1.0 - exp(-TURN_RATE * delta))
	if absf(angle_difference(rotation.y, _restand_yaw)) < 0.10:
		_restand_t = minf(_restand_t, RESTAND_SETTLE)

## Is there a fish in the player's hand right now? Reads the hotbar the same way the spear
## prompt does, so "holding a fish" means exactly what it means everywhere else.
func _player_holding_fish(_player: Node3D) -> bool:
	var slot: int = PlayerState.selected_hotbar
	if slot < 0 or slot >= PlayerState.HOTBAR_SIZE or PlayerState.hotbar[slot] == null:
		return false
	var id: String = String(PlayerState.hotbar[slot])
	return id.begins_with("fish_") or id.begins_with("cooked_fish_") or id == "dried_fish"

# ------------------------------------------------------------------ mood and idle life

## ENERGY DRIFTS, and that is what stops the cat being a machine with cooldowns.
##
## Sleeping and sitting put it back; running, hunting and playing spend it. On top of that a
## crepuscular bump: cats are dawn-and-dusk animals and their evening burst is the most
## reliable thing they do, so the same cat is a different companion at 06:00 and at 14:00
## without a single behaviour having been rewritten.
func _tick_energy(delta: float) -> void:
	var spend: float = 0.0
	# SWIM IS NAMED, and it has to be: the `_:` arm below RECOVERS energy at -0.010, so an
	# unlisted state means a cat treading water for its life is quietly resting. Hardest work
	# this animal ever does.
	match _state:
		State.SWIM:
			spend = 0.120
		State.RUN, State.POUNCE, State.JUMP, State.PLAY:
			spend = 0.085
		State.STALK, State.FOLLOW, State.FISH, State.GIFT:
			spend = 0.030
		State.SLEEP:
			spend = -0.075
		State.SIT, State.GROOM, State.PERCH, State.STRETCH, State.PET:
			spend = -0.030
		_:
			# EVERY STATE IS NAMED ABOVE, and the enum is checked against this match whenever one
			# is added — because this arm RECOVERS, so a state left out of it is a cat that rests
			# while it works. JUMP and FISH were both falling through here (a leap and a trot at
			# TROT_SPEED, both quietly restful) until the instinct layer went in and the list was
			# audited; PET is a hand on the animal, which is rest and is now said rather than
			# defaulted. Nothing reaches this line today.
			spend = -0.010
	# The crepuscular pull. GameClock's phase is the cheapest honest source for it, and the
	# push is toward a HIGH target rather than a flat add so a tired cat still needs its rest.
	var ph: int = GameClock.current_phase
	var crepuscular: bool = ph == GameClock.Phase.DAWN or ph == GameClock.Phase.DUSK
	if crepuscular:
		_energy = lerpf(_energy, 1.0, 1.0 - exp(-0.09 * delta))
	_energy = clampf(_energy - spend * delta, 0.0, 1.0)

## A SETTLED CAT IS NOT A STATUE. It looks at things: at you, at a bird, at a noise, at
## nothing in particular, and it holds each look for a while before picking another. This is
## the cheapest aliveness there is and it runs ALONGSIDE whatever the animal is otherwise
## doing — no state, no `return`, so it never competes with the behaviour tree.
##
## Deliberately not a random head-jitter. A glance that lands on something and STAYS there
## reads as attention; one that wanders continuously reads as a broken servo.
func _idle_attention(delta: float, ppos: Vector3, d: float) -> void:
	# The hunt, the gift and being petted all aim the head themselves and outrank this.
	if _hunt > 0 or _carry != "" or _pet_t > 0.0 or _state == State.SLEEP:
		return
	# AND NOT WHILE SHE IS WALKING, which is a standing instruction rather than a preference.
	# The owner's requirement is that from head on, at default gait, the face points dead
	# straight — that is what the s38 work on the breath layer was for, measured down from
	# +3.43 deg off the travel line to +0.91. An idle glance layer is free to turn the head up
	# to a radian, so letting it run during FOLLOW would hand all of that straight back for
	# the sake of an idle flourish. A settled cat looks around; a walking one looks where she
	# is going.
	# ...BUT IT DOES GLANCE. Suppressing the layer outright was the right answer to "the head
	# defaults sideways" and the wrong one to "the cat should look around as it walks": a
	# companion whose head is welded to its travel line for a whole walk is a vehicle. The
	# two asks only conflict if a glance is a HELD STARE, which is what a full-weight look
	# is. A WALKING glance is brief, shallow, and returns all the way to zero — so straight
	# ahead is the RESTING state of the head, not an average it passes through. Predatory and
	# errand states keep the hard suppression: a stalk, a pounce and a leap aim the head
	# deliberately, and a gift-carry wants its eyes on the person.
	# SWIM joins the hard suppressions for the same reason JUMP is there: it aims the head
	# deliberately (at the way out) and an idle flourish while the animal is in the sea is the
	# wrong read by a mile.
	if _state in [State.STALK, State.POUNCE, State.GIFT, State.JUMP, State.SWIM]:
		_glance_hold = 0.0
		return
	var walking: bool = _last_speed > 0.2 \
		or _state in [State.FOLLOW, State.RUN, State.PLAY]
	if walking and _glance_hold <= 0.0 and _glance_cd > 0.0:
		_glance_cd -= delta
		return
	if _glance_hold > 0.0:
		_glance_hold -= delta
		_watch(_glance_at, 0.25 if walking else 0.85)
		return
	_glance_cd -= delta
	if _glance_cd > 0.0:
		return
	# Pick something worth looking at, weighted by what a cat would actually care about.
	var roll: float = _rng.randf()
	var picked := false
	if roll < 0.34 and d < FISH_M:
		_glance_at = ppos + Vector3(0, 1.2, 0)      # you, most often
		picked = true
	elif roll < 0.60:
		# The nearest bird, if there is one. Birds beat everything except you.
		var best_d: float = HUNT_M * 1.6
		for g in get_tree().get_nodes_in_group("deck_gull"):
			var n: Node3D = g as Node3D
			if n == null or not is_instance_valid(n):
				continue
			var gd: float = global_position.distance_to(n.global_position)
			if gd < best_d:
				best_d = gd
				_glance_at = n.global_position + Vector3(0, 0.1, 0)
				picked = true
	if not picked:
		# ...or nothing in particular, which is most of what a cat looks at. Off to one side
		# and roughly level, because a cat scanning a deck is not studying its own feet.
		var a: float = rotation.y + _rng.randf_range(-2.2, 2.2)
		_glance_at = global_position + Vector3(sin(a), 0, cos(a)) * _rng.randf_range(3.0, 9.0) \
			+ Vector3(0, _rng.randf_range(-0.1, 1.1), 0)
	# A settled cat studies a thing; a walking one flicks at it and looks back. Short holds
	# and long gaps are what keep straight-ahead the head's resting state.
	if walking:
		# RARE AND SHALLOW, and the numbers are chosen against the gate rather than by
		# taste: CatReviewProbe measures the head's rms yaw off the travel line at 3.5 deg,
		# which IS the owner's "straight by default" written down. A glance at weight 0.25
		# of the 1.05 rad look clamp is ~15 deg, so the duty cycle has to stay near 3% for
		# the rms to stay under the bar — 0.45 s of glancing in every 14 is exactly that,
		# and it still gives roughly four looks a minute while walking.
		_glance_hold = _rng.randf_range(0.30, 0.60)
		_glance_cd = _rng.randf_range(9.0, 20.0)
	else:
		_glance_hold = _rng.randf_range(0.7, 2.6)
		_glance_cd = _rng.randf_range(1.1, 4.5)

## A WASH IS A BOUT, NOT A LOOP. It runs for a few seconds in ONE style and stops, and the
## next one is a different style — which is the difference between a cat grooming and an
## idle animation playing. Returns true while it owns the animal.
func _self_groom(delta: float) -> bool:
	if _wash_t <= 0.0:
		return false
	_wash_t -= delta
	_enter(State.GROOM)
	if _rig != null:
		_rig.call("groom_style", _wash_style)
	_last_speed = 0.0
	_reseat()
	if _wash_t <= 0.0:
		# Longer bouts earn a longer break, so it never reads as a rota.
		_wash_cd = _rng.randf_range(14.0, 48.0)
	return true

## `_maybe_wash` USED TO LIVE HERE, AND ITS WINDOW WAS THREE SECONDS WIDE.
##
## s48 made the wash a random event rather than a greeting — the owner's "it shouldn't lick
## itself EVERY time right after stopping" — with a settling delay (WASH_SETTLE_S 3.0) and a
## Poisson roll (WASH_RATE 0.145/s). Both were right and neither was the problem. The function
## was called from exactly two sites, both inside the `else` of `if _still > SETTLE_SEC`, so a
## bout could only ever START in the band `3.0 < _still <= 6.0`: about a one-in-three chance
## per settle and then structurally impossible, because `_still` only goes up. `_wash_cd`'s own
## re-arm is 14-48 s, i.e. ALWAYS longer than the window it had to land inside, so most
## re-arms expired into a state where this function was not even being called. A STAYED cat
## was worse still: `resting` is unconditionally true for one, so its `_still` never resets and
## after the first window it could not wash again for the session.
##
## The rate and the styles survive, in `_action_weights` and `_start_wash`; what is gone is the
## window. The chooser runs from BOTH branches of the settle ladder and from the pre-friend
## path, so the whole of "awake and unbothered" is eligible.

## ARM A WASH BOUT IN A NAMED STYLE. One writer for `_wash_t` and `_wash_style`, because the
## style and the length of the bout are the same decision — the ear scratch is short and
## furious, the flank wash is long and unhurried, and a caller that picks one and forgets the
## other gets a two-second flank wash or a nine-second scratch.
func _start_wash(style: int) -> void:
	if _rig != null:
		_rig.call("tail_flick", 0.45)   # the small settling flick as it starts a wash
	_wash_style = clampi(style, 0, 3)
	_wash_t = {0: 4.5, 1: 7.0, 2: 5.0, 3: 2.8}.get(_wash_style, 4.0) * _rng.randf_range(0.7, 1.4)

# ============================================================ THE INSTINCT LAYER
#
## WHAT A CAT DOES WHEN NOTHING IS HAPPENING, AND WHY IT IS A DISTRIBUTION RATHER THAN A RUNG.
##
## Everything above this line is a PRIORITY LADDER: a fixed order of situations (a hand on it,
## a fish in your hand, a bird on the deck, you going to bed) each of which has exactly one
## right answer. That shape is correct for situations and wrong for the other 90% of the
## animal's screen time, where there is no situation at all and the honest answer is "one of a
## dozen things, and which one is the point". A ladder cannot say that: whatever sits highest
## wins every time, so the bottom of a ladder is a loop. That is precisely what was there —
## `_maybe_wash` plus a shake roll, and nothing else, in ONE branch.
##
## So the bottom of the ladder is a WEIGHTED DRAW instead. The weights are built from the
## drives that already exist in this file — `_energy`, `_still`, the wash and shake cooldowns,
## GameClock's phase — so the same code is a different animal at 06:00 with a full tank and at
## 14:00 after a run, without a second behaviour tree to keep in sync. Nothing here invents a
## drive; if a behaviour wants to know something, it asks a variable that was already there.
##
## THREE THINGS THIS WIRES UP THAT WERE WRITTEN AND NEVER RAN:
##   * PERCH (State 12) had a pose row, a `_tick_energy` arm and a tail line, and NO `_enter`
##     anywhere in the file. `perch` below is its first caller in the state's existence.
##   * STRETCH had exactly one setter — waking up. A cat also stretches after a long sit,
##     which is what `stretch` is; it re-uses `_stretch_t` so the existing rung 2 owns it and
##     no new executor was needed.
##   * The EAR SCRATCH (wash style 3, cat_rig's `groom_scratch`) was reachable only as 1 of 7
##     faces of a die rolled inside a three-second window that most cooldowns expired outside
##     of. It is a first-class action here.
##
## AND THE WINDOW ITSELF, which is the largest of the lot. `_maybe_wash` was called from inside
## the `else` of `if _still > SETTLE_SEC`, so a wash could only ever START while
## WASH_SETTLE_S (3.0) < `_still` <= SETTLE_SEC (6.0) — three seconds per settle, at 0.145/s,
## i.e. about a 1-in-3 chance and then never again. A STAYED cat was worse: its `_still` never
## resets, so after the first window it could not wash for the rest of the session. `_idle_tick`
## is called from BOTH branches (and from the pre-friend path, which had no behaviour at all),
## so the whole time the animal is awake and settled is eligible.
##
## EVERY ACTION IS A COMPOSITION, NOT A NEW STATE. The State enum is untouched — the probes
## assert on its integers and the header says APPENDED NEVER INSERTED — and every action drives
## states and poses that already exist and are already in `_tick_energy`'s match.

## The seed for the DECISION stream, and it is deliberately not `_rng`'s.
##
## `_rng` is drawn on by tail flicks, pace jitter, stalk freezes and a dozen other things at
## rates that depend on how many gulls happened to fly past, so "the Nth draw" is not a
## reproducible quantity even though the generator is seeded. A stochastic selector sharing it
## is untestable by construction, and this repo has two flaky-probe entries on file already.
## `_brng` is drawn EXACTLY ONCE PER DECISION and by nothing else, so reseeding it and taking N
## decisions is reproducible to the count — which is what `tests/cat_probe.gd` asserts on.
## Durations, targets and jitter still come from `_rng`, so they cannot shift the decision
## stream either.
const BEHAVIOUR_SEED: int = 20260808
var _brng := RandomNumberGenerator.new()
## The action that owns the animal right now ("" for none) and how long it has left.
var _idle_act: String = ""
var _idle_t: float = 0.0
## Where the current action is aimed — a survey mark, a mosey spot, a perch top.
var _idle_at: Vector3 = Vector3.ZERO
## Seconds until the next decision may be taken at all. Re-armed at the END of every action, so
## back-to-back behaviours are impossible and the gaps read as an animal rather than a playlist.
var _idle_cd: float = 6.0
## ...and a much longer one for the two actions that MOVE the animal off the spot it is on.
## Separate because "get up and go somewhere" is a rarer decision than "wash", and because a
## harness that needs the cat to hold still then has ONE number to pin — which is why the mosey
## and the perch share it rather than having one each.
##
## 35-95 s, and the number is a measurement rather than a taste. At the first cut's 55-150 s,
## tests/CatBehaviourProbe counted FIVE roam decisions across 1200 s of sim in four scenarios,
## all five of which happened to land on the mosey — i.e. the perch, which is the whole of
## wiring up State 12, was drawing about two chances a run at a coin flip. Halving the gap
## roughly doubles the sample without making the animal fidget: one decision to get up and go
## somewhere per minute or so, of which about half are a climb.
var _roam_cd: float = 40.0
## How long a perched cat has been up on its thing — kept apart from `_idle_t` so the approach
## and the sit are one action with two phases.
var _perch_on: float = 0.0
## ...and the approach's escape hatch: the closest it has got, and how long it has been failing
## to beat that. `_perch_spot` proves the TOP is standable and inside the reachability ceiling;
## it cannot prove the animal can get up there FROM WHERE IT IS STANDING, and the first live run
## of this caught exactly that — it picked a bunk frame 0.97 m up and 2.4 m away, walked to the
## bunk's side, and pressed at it for twenty seconds (tests/CatProbe's perch trace). Every other
## wedge in this file has a progress check for the same reason (`_bed_stall` 2.5, `_detour_stall`
## 0.35, `_drop_stall` 1.1, `_trail_stall` 0.9): a goal that is not getting closer is not a goal.
var _perch_stall: float = 0.0
var _perch_best: float = 1e9
const PERCH_STALL: float = 2.5
## THE ACTION LOG — how many of each, and when the last one was, on the sim clock. Not debug
## scaffolding: "the distribution is varied" is a claim about counts, and this file has been
## bitten before by behaviours that were argued rather than measured (the wash window above
## shipped for five sessions). `tests/cat_behaviour_probe.gd` reads these.
var _act_hist: Dictionary = {}
var _act_last: Dictionary = {}
var _act_gaps: Dictionary = {}

## Rate at which a settled, eligible cat starts SOMETHING, per second. With `_idle_cd`'s 4-14 s
## re-arm on top, an action lands roughly every six to sixteen seconds of settled time.
const IDLE_RATE: float = 0.55
## A sleeping cat's only decision is whether to wake up, and it takes it far more slowly.
const IDLE_SLEEP_SCALE: float = 0.22
## How far from its anchor (you, or the patch it was told to stay on) an action may carry the
## animal before the ladder above takes the frame back. This is the leash that keeps an instinct
## from outranking the follow: it is measured FLAT, because a cat on a crate above you has not
## gone anywhere.
const IDLE_LEASH: float = 5.0
## A perch has to be one the animal can actually get onto, and that band is NARROWER than this
## file's own documentation says. MEASURED (tests/CatStepScratch.tscn — build a box, stand the
## player on top of it, watch for 13 s, sweep the height):
##
##     height  0.20  0.35  0.45  0.55  0.62 | 0.70  0.85  1.00  1.15
##     got up   no    no    no    no    no  | YES   YES   YES   YES
##     max rise 0.000 0.000 0.000 0.000 0.000| 0.801 0.949 1.097 1.246   (metres off the deck)
##
## The cat cannot climb ANYTHING with a vertical face inside the "step" band it is supposedly
## allowed (rise <= CLIMB_UP 0.62) — it never leaves the deck by a millimetre — and it gets onto
## everything above that by LEAPING. Cause, and it is two constants disagreeing about where they
## look rather than a tuning error: `_walk_toward`'s footfall ray probes `want`, ONE STEP ahead
## (18 mm at a walk), so it can only see a rise once the origin is within a step of the
## obstacle's footprint — while `_step_clear`'s nose sphere refuses any origin whose nose is in
## the face, which is `_body_len()/2` = 0.33 m out. The origin can therefore never get close
## enough for the footfall ray to see a vertical face at all, and the only probe that looks a
## body-length ahead — the ledge probe — is gated `lift > CLIMB_UP` and so declines precisely
## the band the animal is allowed to step onto. It is the exact mirror of the s38 leap bug in
## KNOWN_ISSUES, one band down.
##
## That is a locomotion fault and it is NOT fixed here: this is a behaviour session, another
## builder is in the gait this hour, and opening the step band changes how the animal follows
## you past every coaming on the rig. Filed instead, with the instrument. What the perch does
## about it is refuse to want what the animal cannot have — derived from CLIMB_UP so the band
## moves if that constant ever does, rather than hand-typed at the 0.70 the sweep happened to
## test.
const PERCH_MIN: float = CLIMB_UP + 0.08

## THE MENU, AND WHAT EACH ITEM IS WORTH RIGHT NOW.
##
## Returns action name -> relative weight; `_pick_action` normalises. A weight of zero (or an
## absent key) means "not available", which is how the cooldowns are expressed — there is no
## second gate anywhere, so reading this dictionary tells you the whole truth about what the
## animal might do next. That is deliberate: it makes the selector testable as a pure function
## of the drives (see CatProbe), which a scatter of `if` statements would not be.
func _action_weights(allow_roam: bool = true) -> Dictionary:
	# ASLEEP: the only thing on the menu is waking up. Without this a dozing cat would keep
	# choosing washes it cannot perform, and — worse — `_settle`'s ladder means a player who
	# stands still for half a minute gets a cat that is asleep for the REST OF THE SESSION,
	# because nothing in this file ever reduced `_still`. `rouse` is that missing edge.
	if _state == State.SLEEP:
		return {"rouse": 1.0}
	var w: Dictionary = {}
	var lively: float = clampf(_energy, 0.0, 1.0)
	var tired: float = 1.0 - lively
	## How long past "settled" it has been sitting — a cat that has held one position for half a
	## minute is the one that gets up and stretches.
	var long_sat: float = clampf((_still - SETTLE_SEC) / 30.0, 0.0, 1.0)
	var ph: int = GameClock.current_phase
	var crepuscular: bool = ph == GameClock.Phase.DAWN or ph == GameClock.Phase.DUSK
	# THE FOUR WASHES, which is most of what a cat does with its day and is weighted like it.
	# They share ONE cooldown (`_wash_cd`, 14-48 s) so a bout is followed by a gap whatever
	# style it was, and the styles are ranked the way a cat ranks them: the paw-lick is the
	# default, the ear scratch is the rare one you notice.
	if _wash_cd <= 0.0 and _wash_t <= 0.0:
		w["wash_paw"] = 1.30
		w["wash_flank"] = 0.85
		w["wash_chest"] = 0.70
		w["scratch_ear"] = 0.60 + 0.50 * lively
	# LOOKING AT SOMETHING, at length. The cheapest action here and the one that most reads as
	# an animal minding its own business; a lively cat does more of it.
	w["survey"] = 0.85 + 1.15 * lively
	w["stretch"] = 0.30 + 0.95 * long_sat
	if _shake_cd <= 0.0:
		w["shake"] = 0.65
	if _meow_cd <= 0.0 and friend:
		w["chirp"] = 0.35
	# THE NAP. Weighted almost entirely on how tired it is, and OFF at dawn and dusk, which is
	# the same crepuscular fact `_tick_energy` uses from the other side: the hours a cat is
	# least likely to lie down are exactly the hours its tank is being topped up.
	if not crepuscular:
		w["loaf"] = 0.15 + 1.55 * tired
	# THE TWO THAT MOVE IT. Gated on their own long cooldown AND on the player having been
	# still long enough that getting up is not abandoning them mid-walk.
	if allow_roam and _roam_cd <= 0.0 and _still > SETTLE_SEC:
		w["mosey"] = 0.55 + 0.45 * lively
		w["perch"] = 0.50 + 0.70 * lively
	return w

## ONE DRAW, ONE DECISION. Roulette over the weights; returns "" only if the menu is empty,
## which `_action_weights` cannot produce (survey is unconditional) but a caller might.
##
## THE KEYS ARE SORTED, and that is not cosmetic. A roulette wheel maps a uniform draw onto
## whichever slot the iteration order happens to put under it, so an unsorted dictionary makes
## the ANSWER depend on insertion order — i.e. on the order the branches above happen to be
## written in. Sorting means a future session can re-order that function freely and the seeded
## stream still produces the same decisions, which is the difference between a reproducible
## test and one that has to be re-baselined after every edit.
func _pick_action(w: Dictionary) -> String:
	var keys: Array = w.keys()
	keys.sort()
	var total: float = 0.0
	for k in keys:
		total += maxf(float(w[k]), 0.0)
	if total <= 0.0:
		return ""
	var r: float = _brng.randf() * total
	for k in keys:
		r -= maxf(float(w[k]), 0.0)
		if r <= 0.0:
			return String(k)
	return String(keys[keys.size() - 1])

## Count it, and remember when — the mean interval between two of the same action is the number
## that says whether a behaviour is an event or a tic.
func _act_note(nm: String) -> void:
	_act_hist[nm] = int(_act_hist.get(nm, 0)) + 1
	if _act_last.has(nm):
		var g: Array = _act_gaps.get(nm, [0, 0.0])
		_act_gaps[nm] = [int(g[0]) + 1, float(g[1]) + (_t - float(_act_last[nm]))]
	_act_last[nm] = _t

## The histogram, for harnesses: name -> {n, share, mean_gap_s}. `share` is of all actions taken.
func behaviour_histogram() -> Dictionary:
	var total: int = 0
	for k in _act_hist:
		total += int(_act_hist[k])
	var out: Dictionary = {}
	for k in _act_hist:
		var g: Array = _act_gaps.get(k, [0, 0.0])
		out[k] = {
			"n": int(_act_hist[k]),
			"share": float(_act_hist[k]) / maxf(float(total), 1.0),
			"mean_gap_s": (float(g[1]) / float(g[0])) if int(g[0]) > 0 else 0.0,
		}
	return out

func behaviour_reset_log() -> void:
	_act_hist = {}
	_act_last = {}
	_act_gaps = {}

## Reseed the DECISION stream. For probes only — the game never calls it.
func set_behaviour_seed(s: int) -> void:
	_brng.seed = s

## Arm an action. Durations and targets come from `_rng`, never `_brng` — see BEHAVIOUR_SEED.
func _begin_action(nm: String) -> void:
	if nm == "":
		return
	_idle_act = nm
	_idle_t = 0.0
	_perch_on = 0.0
	_perch_stall = 0.0
	_perch_best = 1e9
	match nm:
		"wash_paw":
			_start_wash(0)
		"wash_flank":
			_start_wash(1)
		"wash_chest":
			_start_wash(2)
		"scratch_ear":
			_start_wash(3)
		"stretch":
			# HANDED TO THE EXISTING RUNG, not re-implemented. `_stretch_t` already has an owner
			# two rungs from the top of `_companion` — it was simply never set by anything but
			# waking up. One assignment gives the pose a second, commoner cause.
			_stretch_t = _rng.randf_range(1.1, 2.2)
		"shake":
			if _rig != null:
				_rig.call("shake", 1.0)
			_shake_cd = _rng.randf_range(40.0, 140.0)
		"chirp":
			_idle_t = _rng.randf_range(1.0, 1.6)
			AudioDirector.play_one_shot("cat_chirp", global_position, -24.0)
			_meow_cd = _rng.randf_range(9.0, 22.0)
			if _rig != null:
				_rig.call("tail_flick", 0.6)
		"survey":
			_idle_t = _rng.randf_range(2.4, 6.0)
			_idle_at = _survey_mark()
		"loaf":
			_idle_t = _rng.randf_range(7.0, 22.0)
		"rouse":
			# Out of the sleep band and back into the sit one. `_still` is the ONLY thing holding
			# the animal asleep (see `_settle`), so this is the whole of waking up — the existing
			# `_was_asleep` beat in `_companion` then supplies the stretch and the shake for free.
			_still = minf(_still, SETTLE_SEC + 2.0)
			_idle_cd = _rng.randf_range(20.0, 60.0)
			_act_note("rouse")
			_idle_act = ""
			return
		"mosey":
			# A cat gets up, walks a metre and a half, and sits down again for no reason anyone
			# has ever established. Short, probed, and it re-arms the long cooldown.
			_idle_at = _mosey_spot()
			_idle_t = _rng.randf_range(2.5, 6.0)
			_roam_cd = _rng.randf_range(35.0, 95.0)
			if _idle_at == Vector3.INF:
				_act_note("mosey_none")
				_end_idle()
				return
		"perch":
			_idle_at = _perch_spot()
			_idle_t = _rng.randf_range(16.0, 44.0)
			_roam_cd = _rng.randf_range(35.0, 95.0)
			if _idle_at == Vector3.INF:
				# NOTHING TO GET ONTO — logged under its own name rather than silently retried,
				# because "the cat never perches" and "there is nothing on this deck to perch on"
				# are different findings and a histogram that merges them cannot tell you which.
				_act_note("perch_none")
				_end_idle()
				return
		_:
			_idle_act = ""
			return
	# AN ANIMAL THAT IS DOING THINGS IS NOT HALF A MINUTE INTO A NAP, and this line is the
	# difference between an instinct layer that runs and one that is asleep.
	#
	# `_still` is the ONLY clock `_settle`'s sit -> doze -> sleep ladder runs on, and nothing in
	# this file has ever reduced it. So a player who stands still for SETTLE_SEC + DOZE_SEC —
	# 28 seconds, i.e. one go at the fishing rod — gets a cat that is asleep for as long as they
	# stay there, and everything below this comment is unreachable. MEASURED before this line
	# existed (tests/CatBehaviourProbe, 60 s of a stationary player): FOUR actions, of which one
	# was the wake-up, and three states ever visited. Doing something pushes the doze clock back,
	# and HOW FAR is the energy — a lively cat's own behaviour keeps it awake, a tired cat's does
	# not, so the same code drifts off in the afternoon and holds court at dusk.
	_still = minf(_still, SETTLE_SEC
		+ DOZE_SEC * (0.20 + 0.50 * (1.0 - clampf(_energy, 0.0, 1.0))))
	_act_note(nm)
	# The instantaneous ones own no frames; the gap is the cooldown's job.
	if _idle_t <= 0.0 and _wash_t <= 0.0:
		_end_idle()

func _end_idle() -> void:
	_idle_act = ""
	_idle_t = 0.0
	_perch_on = 0.0
	_perch_stall = 0.0
	_perch_best = 1e9
	_idle_cd = _rng.randf_range(4.0, 14.0)

## May the current action keep the frame? An instinct never outranks the companion contract:
## the moment the player moves, or opens more than IDLE_LEASH of flat ground, the action ends
## and the follow below takes over. That is the same order the wash always had — it just used
## to be expressed by sitting below the follow rung, which a perch cannot do (a perched cat is
## by definition more than `near_gap` from a player standing on the deck, so the follow rung
## would walk it straight back off again).
func _idle_holds(anchor: Vector3, leash: float, resting: bool) -> bool:
	if _over_water(global_position):
		return false
	var flat: float = Vector2(global_position.x - anchor.x,
		global_position.z - anchor.z).length()
	if flat > leash:
		return false
	# A MOVING PLAYER SHORTENS THE LEASH TO THE COMPANIONABLE GAP, and this line is the whole
	# of "an instinct never outranks the follow". While you are still, an action may range out
	# to `leash` — onto a crate, a metre and a half down the deck. The moment you move, anything
	# that has taken the animal further than FOLLOW_NEAR ends and the follow rung below gets the
	# frame. What the second clause preserves is the wash's ORIGINAL behaviour: sitting below the
	# follow rung, a bout within `near_gap` was never interrupted, because the follow rung did
	# not fire that close — so a cat at your feet does not abandon its paw because you shifted
	# your weight. Bare `not resting` was the first cut of this and it did exactly that.
	return resting or flat <= FOLLOW_NEAR

## Run the action that owns the animal, if one does. True while it holds the frame.
func _idle_step(delta: float, anchor: Vector3, leash: float, resting: bool) -> bool:
	# A WASH IS AN ACTION LIKE THE REST, and `_self_groom` stays its executor so anything that
	# arms `_wash_t` from outside (a harness, a future behaviour) still plays.
	if _wash_t > 0.0:
		if not _idle_holds(anchor, leash, resting):
			# `_wash_t` is LEFT ARMED, deliberately: "a wash in progress finishes" has been the
			# rule since the bout was written, and an interrupted one resumes when the animal
			# settles again rather than being thrown away. Only `_idle_act` is released, so the
			# chooser cannot start something else on top of it.
			_end_idle()
			return false
		return _self_groom(delta)
	if _idle_act == "":
		return false
	if not _idle_holds(anchor, leash, resting):
		_end_idle()
		return false
	_idle_t -= delta
	if _idle_t <= 0.0:
		_end_idle()
		return false
	match _idle_act:
		"survey":
			_enter(State.SIT)
			_pose_sit(delta)
			# Outranks the idle glance layer's 0.85 by design — `_watch` gives the frame to the
			# strongest claim, so a deliberate stare is not sawn in half by a wandering one.
			_watch(_idle_at, 0.95)
		"chirp":
			_enter(State.SIT)
			_pose_sit(delta)
			_watch(anchor + Vector3(0, 1.2, 0), 0.9)
		"loaf":
			_enter(State.SLEEP)
			_last_speed = 0.0
			_reseat()
		"mosey":
			if global_position.distance_to(_idle_at) < 0.35:
				_enter(State.SIT)
				_pose_sit(delta)
				_end_idle()
				return false
			_enter(State.FOLLOW)
			_walk_toward(_idle_at, WALK_SPEED * 0.75 * _ease_turn(_idle_at, delta), delta, 0.25)
		"perch":
			var flat: float = Vector2(global_position.x - _idle_at.x,
				global_position.z - _idle_at.z).length()
			# UP AND ON IT? Height AND footprint, because a cat standing at the foot of a crate
			# is exactly `flat` away from a point on top of it in plan view.
			if flat < 0.45 and global_position.y > _idle_at.y - 0.20:
				_perch_on += delta
				_enter(State.PERCH)
				_pose_sit(delta)
				# The whole point of being up there. It watches YOU, from above, which is the
				# single most cat thing this file does not otherwise say.
				_watch(anchor + Vector3(0, 1.2, 0), 0.6)
			else:
				_enter(State.FOLLOW)
				# `_walk_toward` owns the climb: a rise inside CLIMB_UP is a step, one between
				# CLIMB_UP and JUMP_UP arms the leap, and `_reachable_up` refuses anything that
				# would strand the animal. Nothing about the perch needs its own movement code.
				_walk_toward(_idle_at, WALK_SPEED * _ease_turn(_idle_at, delta), delta, 0.20)
				# PROGRESS IS MEASURED, NOT ASSUMED — see `_perch_stall`. Only closing the gap
				# counts as getting there; a couple of seconds of not closing it and the animal
				# gives the frame back rather than pressing at a face for the rest of the night.
				if flat < _perch_best - 0.02:
					_perch_best = flat
					_perch_stall = 0.0
				else:
					_perch_stall += delta
				if _perch_stall > PERCH_STALL:
					_act_note("perch_stall")
					_end_idle()
					return false
		_:
			_end_idle()
			return false
	return true

## Decide whether to start something. Called from the settled branches of both behaviours and
## from the pre-friend path — i.e. everywhere the animal has nothing it must be doing.
func _idle_tick(delta: float, allow_roam: bool) -> void:
	_idle_cd = maxf(0.0, _idle_cd - delta)
	_roam_cd = maxf(0.0, _roam_cd - delta)
	if _idle_act != "" or _wash_t > 0.0 or _stretch_t > 0.0 or _idle_cd > 0.0:
		return
	# A POISSON GATE IN ITS EXACT FORM. `rate * dt` is the approximation, and this animal is
	# handed AiBudget-summed deltas up to MAX_STEP 0.15 s where it is a percent light; the
	# closed form is the same arithmetic every ease in this file already uses and costs nothing.
	var rate: float = IDLE_RATE * (IDLE_SLEEP_SCALE if _state == State.SLEEP else 1.0)
	if _rng.randf() > 1.0 - exp(-rate * maxf(delta, 0.0)):
		return
	_begin_action(_pick_action(_action_weights(allow_roam)))

## Something worth staring at: a bird if there is one, otherwise you, otherwise a bearing off
## to one side. Same preference order as the glance layer, held ten times as long.
func _survey_mark() -> Vector3:
	var best: Node3D = null
	var best_d: float = HUNT_M * 1.8
	for g in get_tree().get_nodes_in_group("deck_gull"):
		var n: Node3D = g as Node3D
		if n == null or not is_instance_valid(n):
			continue
		var gd: float = global_position.distance_to(n.global_position)
		if gd < best_d:
			best_d = gd
			best = n
	if best != null:
		return best.global_position + Vector3(0, 0.1, 0)
	var player: Node3D = AIB.player(self)
	if player != null and is_instance_valid(player) \
			and global_position.distance_to(player.global_position) < FISH_M:
		return player.global_position + Vector3(0, 1.2, 0)
	var a: float = rotation.y + _rng.randf_range(-2.4, 2.4)
	return global_position + Vector3(sin(a), 0, cos(a)) * _rng.randf_range(4.0, 11.0) \
		+ Vector3(0, _rng.randf_range(-0.1, 1.2), 0)

## A metre or so of deck to move to, PROBED — the same `_deck_at` + `_step_clear` pair the play
## spot and the zoomie heading learned to use, and for the same reason: a named position that
## was not probed is how this animal ended up over the water.
func _mosey_spot() -> Vector3:
	for _try in range(6):
		var a: float = _rng.randf() * TAU
		var cand: Vector3 = global_position \
			+ Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(0.8, 1.8)
		cand.y = global_position.y
		var g: Vector3 = _deck_at(cand)
		if g == Vector3.INF:
			continue
		if absf(g.y - global_position.y) > STEP_UP:
			continue
		if _step_clear(g, (g - global_position).normalized()):
			return g
	return Vector3.INF

## SOMEWHERE HIGHER TO SIT. The first thing in this file's history to look for one.
##
## Probed on a ring, never typed, and every candidate has to survive the same three questions
## the walk asks: is it out of the sea, does the BODY fit up there, and — the one that matters —
## `_reachable_up`, which caps the height at the player's own deck plus one leap. That is the
## rule s38's reverted ledge fix lacked, and it is why this cannot build the staircase of
## legal-one-at-a-time hops that stranded the cat at y 20.26.
##
## The ray starts a whisker above JUMP_UP so it cannot see, and therefore cannot be blinded by,
## a beam or a deckhead over the candidate: anything above one leap is not a perch. The honest
## limit of that is a low crate UNDER an overhang, which this will miss.
## Does the surface at `top` hold a cat's whole footprint, or is `top` a lip? Eight rays on a
## ring of 1.6 body-radii, each of which must find the same surface within 60 mm — an edge, a
## bevel, a grating gap or the far side of a narrow pipe all fail it. See `_perch_spot`.
func _perch_footing(top: Vector3, skip: Array[RID]) -> bool:
	var world: World3D = get_world_3d()
	if world == null:
		return false
	var r: float = _body_r() * 1.6
	for i in range(8):
		var a: float = TAU * float(i) / 8.0
		var at: Vector3 = top + Vector3(cos(a) * r, 0.30, sin(a) * r)
		var q := PhysicsRayQueryParameters3D.create(at, at - Vector3(0, 0.60, 0))
		q.collision_mask = 1
		q.collide_with_areas = false
		q.exclude = skip
		var hit: Dictionary = world.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return false
		if absf((hit["position"] as Vector3).y - top.y) > 0.06:
			return false
	return true

func _perch_spot() -> Vector3:
	var world: World3D = get_world_3d()
	if world == null:
		return Vector3.INF
	var player: Node3D = AIB.player(self)
	var aim: Vector3 = player.global_position if player != null and is_instance_valid(player) \
		else global_position
	var best: Vector3 = Vector3.INF
	var best_score: float = -1e9
	# Built ONCE for all 24 candidates — `_walk_skip` is three group walks and a subtree scan,
	# and nothing it lists can appear or vanish inside one frame.
	var skip: Array[RID] = _walk_skip()
	for r in [1.5, 2.4, 3.4]:
		for i in range(8):
			var a: float = TAU * float(i) / 8.0 + _rng.randf_range(-0.2, 0.2)
			var at: Vector3 = global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
			var from: Vector3 = at + Vector3(0, JUMP_UP + 0.05, 0)
			var q := PhysicsRayQueryParameters3D.create(from, at + Vector3(0, PERCH_MIN, 0))
			q.collision_mask = 1
			q.collide_with_areas = false
			q.exclude = skip
			var hit: Dictionary = world.direct_space_state.intersect_ray(q)
			if hit.is_empty():
				continue
			var top: Vector3 = hit["position"]
			var lift: float = top.y - global_position.y
			if lift < PERCH_MIN or lift > JUMP_UP:
				continue
			if not _reachable_up(top.y):
				continue
			if _over_water(top):
				continue
			var dir: Vector3 = top - global_position
			dir.y = 0.0
			if dir.length() < 0.05:
				continue
			if not _step_clear(top, dir.normalized()):
				continue
			# ...AND THE SURFACE HAS TO CONTINUE UNDER THE ANIMAL. This is the perch flake.
			#
			# Every test above asks about the POINT: is it high enough, reachable, dry, and is
			# anything standing in the way. None of them asks whether there is anything to
			# stand ON around it — and the candidate is wherever a single downward ray on a
			# random ring point happened to land, which on a crate is as often the lip as the
			# middle. Reproduced (tests/PerchScratch, 6 trials against the same 1.8 m crate
			# CatProbe builds): five runs aimed at (4.48..4.50, −2.76..−3.22), well inside the
			# top face, and reached State.PERCH; the sixth aimed at (4.23, −2.14) — 0.13 m in
			# from the x edge and 0.04 m from the z edge — and the animal walked to the foot of
			# the corner, could not get its body onto a landing that small, stopped closing the
			# gap, and `_perch_stall` correctly gave up 2.5 s later. It then sat on the deck for
			# the rest of the window. That is one CatProbe row failing one run in six with no
			# bug in the leap, the climb or the stall detector: the AIM was never standable.
			#
			# Eight rays at 1.6 body-radii, which is the footprint a sitting cat actually needs
			# under it, and all eight must find the SAME top. Cheap — this only runs on the
			# handful of candidates that have already passed every other gate.
			if not _perch_footing(top, skip):
				continue
			# NEARNESS OUTWEIGHS HEIGHT, and that is the correction the first live run bought.
			# Scoring on height alone (`lift * 2.0 - dist * 0.25`) sent the animal at a bunk
			# frame 0.97 m up and 2.4 m away in preference to a crate half the distance off —
			# and the further a perch is, the more geometry there is between the cat and the
			# lip for the approach to founder on. A cat picks the vantage over the thing it is
			# watching, not the tallest object in the room.
			var score: float = lift * 1.2 - top.distance_to(aim) * 0.30
			if score > best_score:
				best_score = score
				best = top
	return best

# ------------------------------------------------------------------ the predatory sequence

## Is this bird already in the air? A gull in flight is not prey, and `_flushing` is DeckGull's
## own flag for it (< 0 grounded, >= 0 seconds airborne).
func _airborne(n: Node3D) -> bool:
	# THE FLAG, AND THEN THE GEOMETRY. `_flushing` is one species' one state variable, and
	# trusting it alone let the cat stalk — and once, pounce at — a bird that was plainly
	# in the air but not in that state (circling, or another species spelling its state
	# differently). Altitude cannot be argued with: anything holding itself more than a
	# body-height above the cat's own deck is not stalkable prey, whatever its flags say.
	# (A bird perched on a crate trips this too, which is correct twice over — the cat
	# cannot reach it, and chattering at it instead is exactly what a cat would do.)
	var f = n.get("_flushing")
	if f != null and float(f) >= 0.0:
		return true
	return n.global_position.y - global_position.y > 0.35

## The nearest gull on this deck that is on the ground and worth stalking. Birds in the air
## are not prey, they are frustration — see the chatter.
func _find_prey() -> Node3D:
	var best: Node3D = null
	var best_d: float = HUNT_M
	for g in get_tree().get_nodes_in_group("deck_gull"):
		var n: Node3D = g as Node3D
		if n == null or not is_instance_valid(n):
			continue
		# A bird already in the air, or one on another deck, is not a stalk.
		#
		# `get()` on a property a node does not have returns null, and `float(null)` is a hard
		# runtime error — so this is asked defensively rather than assumed. Only DeckGull is in
		# this group today; the group is the seam another species will be added at, and a crash
		# in the cat because a new bird spelled its state differently is a bad way to find out.
		if _airborne(n):
			continue
		if absf(n.global_position.y - global_position.y) > CLIMB_UP:
			continue
		var dd: float = global_position.distance_to(n.global_position)
		if dd < best_d:
			best_d = dd
			best = n
	return best

## One beat of the hunt. Returns true while the hunt owns the animal.
func _hunt_step(delta: float) -> bool:
	if _hunt == 0:
		_prey = _find_prey()
		if _prey == null:
			return false
		_hunt = 1
		_freeze_t = 0.0
	# The bird left, flew, or was freed. A cat that keeps stalking an empty patch of deck is
	# the "drone" read this whole file exists to avoid.
	if _prey == null or not is_instance_valid(_prey) or _airborne(_prey):
		_end_hunt(false)
		return false
	var target: Vector3 = _prey.global_position
	var pd: float = global_position.distance_to(target)
	if pd > HUNT_GIVEUP_M:
		_end_hunt(false)
		return false
	# The head is on the bird throughout, whatever the body is doing. This is the tell that
	# makes the whole sequence legible from across a deck.
	_watch(target + Vector3(0, 0.12, 0), 1.0)
	match _hunt:
		1:
			# THE STALK. Low, slow, and it FREEZES — the freezing is the difference between a
			# stalk and simply walking at something. A cat holds still when it thinks the prey
			# has clocked it, and the pauses are what make the approach read as intent.
			_enter(State.STALK)
			if _freeze_t > 0.0:
				_freeze_t -= delta
				_last_speed = 0.0
				_reseat()
				_face(target, delta * 1.5)
			else:
				_walk_toward(target, STALK_SPEED, delta, POUNCE_M * 0.85)
				if _rng.randf() < delta * 0.85:
					_freeze_t = _rng.randf_range(0.3, 1.1)
					# The tip lashes hardest at the freezes — a stalking cat holds its
					# body dead still and its tail does not get the message.
					if _rig != null:
						_rig.call("tail_flick", 1.0)
			if pd <= POUNCE_M:
				_hunt = 2
				_wiggle_t = WIGGLE_SEC
		2:
			# THE TREAD. Hind feet paddling, the rear waggling, the whole animal winding up.
			# Everyone who has met a cat knows precisely what happens next, and it costs one
			# sine wave.
			_enter(State.STALK)
			_face(target, delta * 3.0)
			_last_speed = 0.0
			_reseat()
			_wiggle_t -= delta
			var k: float = clampf(_wiggle_t / WIGGLE_SEC, 0.0, 1.0)
			# The waggle is the PELVIS. Swinging the node took the shoulders and the head
			# with it, which is the wrong end of the animal: the tread is hind feet
			# paddling under a still, locked-on front.
			if _rig != null:
				_rig.call("wiggle", 1.0 - k * 0.35)
			if _wiggle_t <= 0.0:
				_launch_pounce(target)
		_:
			# BEAT 3 IS "IN THE AIR", AND REACHING IT HERE MEANS THE AIR RAN OUT WITHOUT ANYONE
			# RESOLVING THE POUNCE. `_process` hands the animal to `_fly_jump` above the state
			# machine for the whole flight, so this arm is only reachable on an arc that ABORTED
			# (`_arc_clear` failing mid-flight) down a path that left `_pouncing` false. The old
			# body was `pass` — which still `return true`s, i.e. the hunt keeps owning the animal
			# and eats every frame while doing nothing at all, for ever. The var's own comment
			# also documents a beat 4 ("the aftermath") that is assigned nowhere in the file;
			# there are three beats, and this is the end of the last one.
			if _jump_t <= 0.0 and _jump_wind <= 0.0:
				_end_hunt(false)
				return false
	return true

func _launch_pounce(target: Vector3) -> void:
	# A LEAP MUST STILL FIT WHERE IT LANDS. `_fly_jump` drives the body along its arc directly,
	# with none of `_walk_toward`'s deck probe or volume check — the leap deliberately owns the
	# animal — so the only place a pounce can be made safe is before it starts. Without this
	# CatProbe's burial sweep caught the cat 229 mm inside the bunkhouse geometry twice in one
	# run: a hunt that ends with the animal in a bulkhead is worse than a hunt that never fires.
	var over: Vector3 = target - global_position
	over.y = 0.0
	if over.length() < 0.05:
		_end_hunt(false)
		return
	var dir: Vector3 = over.normalized()
	# THE BIRD IS NOT AN OBSTACLE — the whole point is to land on it. DeckGull carries a grab
	# collider on the solid layer, so the clearance test refused every single pounce and the
	# hunt stalled at the tread for ever: the cat crouched, waggled, and never jumped, which is
	# a far worse behaviour than not hunting at all. (The general fix — `_walk_skip` skipping
	# all other fauna — is filed in KNOWN_ISSUES; the branch that claims to do it reads a
	# STATIC FUNCTION as if it were a property and has been adding nothing for two sessions.)
	var prey_skip: Array = []
	if _prey != null and is_instance_valid(_prey):
		for c in _prey.find_children("*", "CollisionObject3D", true, false):
			prey_skip.append((c as CollisionObject3D).get_rid())
		if _prey is CollisionObject3D:
			prey_skip.append((_prey as CollisionObject3D).get_rid())
	# ...AND THE LANDING MUST BE DECK, NOT THE HEIGHT OF THE BIRD. `land.y = target.y` takes the
	# altitude from the GULL, and a gull on the rail is a gull over the sea: the arc check is a
	# volume query, so empty air off the side passes it and the pounce puts the cat in the
	# water. Probed instead — real ground, above the swim line — and the pounce is simply
	# declined if there is none, which is the same "wound up and could not go" the crowded case
	# already handles.
	var land: Vector3 = _pounce_land(global_position + over * _rng.randf_range(0.94, 1.12))
	if land == Vector3.INF or not _arc_clear(land, dir, prey_skip):
		# Try landing short before giving up — a cat crowded by furniture takes the shorter
		# leap rather than not leaping.
		land = _pounce_land(global_position + over * 0.6)
		if land == Vector3.INF or not _arc_clear(land, dir, prey_skip):
			# It wound up and could not go. That still has to READ, so it gets the same
			# affronted wash a miss gets rather than silently forgetting the whole thing.
			_after_t = WASH_SEC * 0.6
			_end_hunt(false)
			return
	_hunt = 3
	_pouncing = true
	_enter(State.POUNCE)
	# The tread was the long anticipation; the launch still GATHERS for a tenth of a second
	# — the spring compressing — before the flight stretch.
	if _rig != null:
		_rig.call("play_seq", [["jump_crouch", 0.10, 16.0]], "jump", 10.0)
	_jump_t = POUNCE_SEC
	_jump_dur = POUNCE_SEC
	_jump_from = global_position
	# Land ON the bird's patch of deck, not on the bird — the seat ray sorts the height out,
	# and a pounce that overshoots by a body length looks more like a cat than one that
	# arrives dead centre every time.
	_jump_to = land
	# THE BIRD REACTS TO THE LEAP, NOT TO BEING LANDED ON. Flushing only at touchdown left
	# the gull standing oblivious through the whole 0.4 s flight and then teleporting into
	# panic on the exact frame the cat arrived — the owner's "no physics/interaction, not
	# realistic". A real bird explodes upward the instant the cat leaves the deck, so the
	# flush fires HERE, and the catch (in _resolve_pounce) is now a race the cat usually
	# loses: it connects only if the bird is still inside the first wingbeats when the paws
	# arrive. Most pounces become a burst of gull with the cat landing in its wake — which
	# is what nine out of ten real pounces on birds look like.
	if _prey != null and is_instance_valid(_prey) and _prey.has_method("_flush"):
		_prey.call("_flush", self)
	AudioDirector.play_one_shot("cat_chirp", global_position, -22.0)

## IS THE WHOLE LEAP CLEAR, not just where it ends?
##
## Checking only the landing point is the obvious thing and it is not enough: the probe caught
## the cat 797 mm inside the quarters bulkhead at NINETY PER CENT of an arc whose destination
## tested perfectly clear. A gull standing a body-length from a wall is a completely ordinary
## thing for a gull to do, and the leap at it passes through the steel on the way in. `_fly_jump`
## drives the body along the arc directly with no gates of its own, so every point of that arc
## has to be proven here, before the animal commits to any of it.
##
## AND A DROP IS SAMPLED DENSER, because four samples over a ten-metre fall are 1.2 m apart at
## the top and 3 m apart at the bottom, which is a bulkhead-sized hole in the proof. Added as a
## separate list rather than by making the shared one adaptive: every up-jump in the game is
## tuned against exactly these four k values (the s47 leap fix measured against them), and a
## denser sweep refuses more arcs. New behaviour pays for its own gates.
func _arc_clear(to: Vector3, dir: Vector3, extra_skip: Array = []) -> bool:
	var from: Vector3 = global_position
	var ks: Array = [0.35, 0.6, 0.8, 1.0]
	var fall: float = from.y - to.y
	if fall > CLIMB_UP:
		ks = []
		var n: int = clampi(int(ceil(fall / 0.45)) + 2, 6, 26)
		for i in range(1, n + 1):
			ks.append(float(i) / float(n))
	for k in ks:
		var at: Vector3 = _arc_point(from, to, k)
		if not _step_clear(at, dir, extra_skip, k >= 1.0):
			return false
	return true

## Did it get there? Called on the frame the leap lands.
func _resolve_pounce() -> void:
	_pouncing = false
	var caught: bool = false
	if _prey != null and is_instance_valid(_prey):
		var pd: float = global_position.distance_to(_prey.global_position)
		# THE CATCH IS GATED BY GEOMETRY, NOT BY A FLAG. The bird was flushed at launch, so
		# by touchdown its `_flushing` flag is always set — the question is whether it is
		# still LOW: inside the first wingbeats, under half a metre off the deck, within a
		# paw's reach. A bird that is properly airborne cannot be caught, full stop — which
		# also closes the owner's "jumped on a bird that was just flying around": however
		# the flags read, altitude says no.
		var prey_alt: float = _prey.global_position.y - global_position.y
		caught = pd < 1.15 and prey_alt < 0.45 and _rng.randf() < CATCH_CHANCE
		# The bird goes either way — it is not eaten and it is not deleted. The flush at
		# launch already sent it; this repeat is harmless insurance for the paths that
		# reach here without one (an aborted arc mid-flight).
		if _prey.has_method("_flush"):
			_prey.call("_flush", self)
	if caught:
		_carry = "gull_feather"
		AudioDirector.play_one_shot("cat_chirp", global_position, -14.0)
	else:
		# THE WASH. It missed, and it would like everyone to understand that it was not
		# trying. This is a real displacement behaviour and it is better animation than the
		# success is.
		_after_t = WASH_SEC
	_end_hunt(caught)

## The pounce's landing, grounded and dried off. `at` names an xz; the height comes from the
## deck, not from the bird. Returns INF when there is nothing there to land on.
func _pounce_land(at: Vector3) -> Vector3:
	# A little more downward reach than a walk step: a gull three metres off can legitimately
	# be standing a coaming lower, and refusing that pounce loses the behaviour to be safe.
	return _deck_at(at, 1.9)

func _end_hunt(_caught: bool) -> void:
	_hunt = 0
	_prey = null
	_wiggle_t = 0.0
	_freeze_t = 0.0
	_hunt_cd = HUNT_CD * _rng.randf_range(0.7, 1.4)

## Drop what it is carrying at your feet.
func _deliver(player: Node3D) -> void:
	_face(player.global_position, 1.0)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if PlayerState.add_item(_carry):
		Journal.discover("cat_gift")
		PlayerState.comfort = clampf(PlayerState.comfort + 0.05, 0.0, 1.0)
		if hud and hud.has_method("toast"):
			hud.toast("The cat puts a gull feather down in front of you, and waits.")
	elif hud and hud.has_method("toast"):
		hud.toast("The cat tries to give you a feather. Your pack is full.")
	AudioDirector.play_one_shot("cat_chirp", global_position, -18.0)
	_carry = ""
	_meow_cd = 4.0

# ------------------------------------------------------------------ play and the zoomies

## FRAP — the evening madness. A short, pointless, flat-out burst across the deck, which is
## the one thing a cat does that no amount of following and sitting can imply.
func _zoomies(delta: float, ppos: Vector3) -> bool:
	if _zoom_t <= 0.0:
		_zoom_t = ZOOM_SEC
		_zoom_to = Vector3.ZERO
	_zoom_t -= delta
	if _zoom_t <= 0.0:
		_zoom_cd = ZOOM_CD * _rng.randf_range(0.7, 1.5)
		return false
	# A new heading every so often, which is what makes it read as madness rather than as
	# going somewhere. Drawn around the PLAYER rather than around the cat: a burst that
	# random-walks off the deck is a cat leaving, and "it settles rather than circling when
	# you rest" is a contract this animal has kept since s34. Orbiting keeps both.
	if _zoom_to == Vector3.ZERO or global_position.distance_to(_zoom_to) < 1.0:
		# PROBED, like the play spot beside it. `_zoom_to.y = global_position.y` was a heading
		# drawn blind at the cat's own altitude, and `_walk_toward` is the only thing that ever
		# refused it — which it does correctly, but a burst that spends its whole three seconds
		# pressed against a rail aimed over the sea is a zoomie that never happened.
		for _try in range(6):
			var a: float = _rng.randf() * TAU
			var cand: Vector3 = ppos + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(2.0, 3.4)
			cand.y = global_position.y
			var g: Vector3 = _deck_at(cand)
			if g == Vector3.INF:
				continue
			_zoom_to = g
			break
		if _zoom_to == Vector3.ZERO:
			# Nowhere to run. Ending the burst is the honest answer — the alternative is
			# `_walk_toward(Vector3.ZERO, …)`, i.e. the cat setting off for the world origin.
			_zoom_t = 0.0
			_zoom_cd = ZOOM_CD * _rng.randf_range(0.7, 1.5)
			return false
	_enter(State.RUN)
	_still = 0.0
	_walk_toward(_zoom_to, RUN_SPEED, delta, 0.4)
	return true

## OBJECT PLAY. It picks a spot on the deck, stalks it exactly as if it were alive, pounces on
## nothing at all, and does it again. The cat knows there is nothing there; that has never
## stopped one yet.
func _play(delta: float) -> bool:
	if _play_t <= 0.0:
		_play_t = PLAY_SEC
		_play_spot = Vector3.ZERO
	_play_t -= delta
	if _play_t <= 0.0:
		_play_cd = PLAY_CD * _rng.randf_range(0.7, 1.5)
		return false
	if _play_spot == Vector3.ZERO or global_position.distance_to(_play_spot) < 0.7:
		# PROBED, like everything else that names a position in this file. A spot drawn blind
		# lands inside a bunk frame about as often as not in the room the cat lives in, and
		# then the pounce that follows puts the animal in the steel.
		# ...AND `_step_clear` ALONE IS NOT "PROBED" — it is a VOLUME query, and empty air over
		# the open sea is the emptiest volume there is. It passed every candidate off the side
		# of the rig, `cand.y = global_position.y` then put that candidate at DECK HEIGHT over
		# the water, and the pounce below launched the animal into it: the most likely single
		# route to the owner's cat-on-the-water, firing on a 38 s cooldown for the whole
		# session. The deck ray is what makes a named position real.
		_play_spot = Vector3.ZERO
		for _try in range(6):
			var a: float = _rng.randf() * TAU
			var cand: Vector3 = global_position \
				+ Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(1.6, 3.4)
			cand.y = global_position.y
			var g: Vector3 = _deck_at(cand)
			if g == Vector3.INF:
				continue
			if _step_clear(g, (g - global_position).normalized()):
				_play_spot = g
				break
		if _play_spot == Vector3.ZERO:
			_play_t = 0.0
			_play_cd = PLAY_CD * _rng.randf_range(0.7, 1.5)
			return false
		_wiggle_t = WIGGLE_SEC * 0.6
	_enter(State.PLAY)
	_watch(_play_spot, 1.0)
	if _wiggle_t > 0.0 and global_position.distance_to(_play_spot) < POUNCE_M:
		_wiggle_t -= delta
		_face(_play_spot, delta * 3.0)
		_last_speed = 0.0
		if _rig != null:
			_rig.call("wiggle", 0.85)
		if _wiggle_t <= 0.0 and _jump_t <= 0.0 and _jump_cd <= 0.0 \
				and not _over_water(_play_spot) \
				and _step_clear(_play_spot, (_play_spot - global_position).normalized()):
			_jump_t = POUNCE_SEC
			_jump_dur = POUNCE_SEC
			_jump_from = global_position
			_jump_to = _play_spot
			_enter(State.POUNCE)
	else:
		_walk_toward(_play_spot, TROT_SPEED, delta, POUNCE_M * 0.8)
	return true

# ------------------------------------------------------------------ the rig

## POSE THE SKELETON FOR WHATEVER THE CAT IS DOING. One call at the end of the frame, after
## the state machine has decided, so there is exactly one writer and a state cannot forget.
##
## Every state gets its own motion AND its own focus, which is the owner's "every state
## should have a focus": the head tracks what the animal cares about even when the body is
## pointing somewhere else, and that is most of the difference between an animal and a prop.
## One call per frame, AFTER the state machine has decided. The state machine's whole
## output is a POSE NAME (set in _enter via the STATE_POSE table) plus the distance the
## body actually covered; the blender does everything else — the pose blend, the gait, the
## breathing, the look. There is no per-state animation code left to disagree with itself.
func _drive_rig(delta: float) -> void:
	if _rig == null:
		return
	# The head, first, so tick applies it this frame: attention wins over the gait's neck.
	# THE OWNER'S STANDING RULE, made structural at the ONE place looks reach the rig:
	# "the cat always looks straight while walking/running; when she pauses to sit, then
	# she looks around everywhere and does cat things." Above a threshold between the
	# stalk (0.62 — which keeps its locked-on creep, the whole tell of a stalk) and the
	# walk (1.55), NO look of any kind reaches the head: not a glance, not a chatter
	# whisper, not a gift-carry gaze. Suppressed HERE rather than at each caller so no
	# future behaviour can re-introduce a mid-stride head-turn — the ninth report of this
	# defect was caused by exactly such a caller nobody had gated.
	if _focus_w > 0.01 and _last_speed < 0.8:
		var to: Vector3 = _focus - global_position
		if to.length_squared() > 0.0004:
			# Into the BODY's frame: the neck yaw is relative to where the animal is facing,
			# so a cat walking north looking east is +90, not a world bearing.
			var want: float = atan2(to.x, to.z) + PI
			var rel: float = wrapf(want - rotation.y, -PI, PI)
			var pitch: float = atan2(to.y - 0.25, Vector2(to.x, to.z).length())
			_rig.look(rel, clampf(pitch, -0.5, 0.5), _focus_w)
	# WHAT THE TAIL IS SAYING, per state. This is the body language the owner asked for and
	# the only channel this mesh has: no facial rig, no ears, painted-on pupils. Carriage and
	# sway do all of it, and every one of these is a real signal a cat owner reads without
	# being taught — the vertical flag on approach, the slow wide arc of an unbothered animal,
	# the flat hard flick of one that is hunting, the quiver of one that has just been fed.
	#   tail(up, sway, rate): up +1 straight up / -1 clamped down, sway width, rate speed.
	match _state:
		State.STALK:
			_rig.tail(-0.85, 0.30, 9.0)      # flat to the deck, tip going hard
		State.POUNCE:
			_rig.tail(-0.4, 0.05, 2.0)       # committed: everything points one way
		State.RUN:
			_rig.tail(0.15, 0.20, 3.0)       # streamed out behind for balance
		State.GIFT:
			_rig.tail(0.95, 0.14, 7.0)       # up and pleased with itself
		State.PET, State.FISH:
			_rig.tail(1.0, 0.10, 8.0)        # the greeting flag, quivering
		State.SLEEP:
			_rig.tail(-0.5, 0.02, 0.4)       # wrapped in and still
		State.SWIM:
			# A wet tail is a rope. Clamped down, barely moving, and NOT signalling anything
			# — the one state where the tail has nothing to say.
			_rig.tail(-1.0, 0.04, 0.8)
		State.GROOM, State.SIT, State.PERCH:
			_rig.tail(-0.2, 0.16, 0.9)       # settled, an idle sweep along the deck
		State.PLAY:
			_rig.tail(-0.3, 0.34, 6.0)
		_:
			# FOLLOW and the rest: a cat walking to someone it likes carries its tail UP, and
			# it is the single most reliable "this animal is pleased to be here" there is.
			_rig.tail(0.55 if _fed_wiggle > 0.0 else 0.35, 0.28, 1.6)
	if _fed_wiggle > 0.0:
		_rig.tail(1.0, 0.10, 11.0)           # the delight quiver, briefly, over everything
	# HOW FAST THE BODY IS ACTUALLY TURNING, measured off the node rather than commanded. The
	# rig needs it for the turn-in-place step cycle (flaw 4): asked to face a new bearing while
	# standing still, `_face` used to swivel the whole animal with all four paws welded to the
	# deck. Measured here, where the yaw really changes, for the same reason `_moved_frame` is
	# measured where the movement really happens.
	var yaw_rate: float = wrapf(rotation.y - _yaw_prev, -PI, PI) / maxf(delta, 1e-4)
	_yaw_prev = rotation.y
	_rig.tick(delta, _last_speed, _moved_frame, yaw_rate)
	_moved_frame = 0.0

## Point the cat's ATTENTION at something without turning it. Weight decays, so a glance
## fades unless whatever caused it keeps calling.
func _watch(at: Vector3, weight: float = 1.0) -> void:
	var w: float = clampf(weight, 0.0, 1.0)
	# THE TARGET FOLLOWS THE STRONGEST CLAIM, NOT THE LATEST. Two watchers calling every
	# frame — a held glance and the chatter, say — used to alternate `_focus` A/B/A/B at
	# frame rate, and the drawn head SAWED between them: the single largest discontinuity
	# the review probe found anywhere in the walk (~0.8 rad/frame at the neck). A new
	# target must now outrank the current claim, renew it, or wait out its decay.
	if w > _focus_w + 0.001 or _focus_w <= 0.01 or at.distance_to(_focus) < 0.4:
		_focus = at
	_focus_w = maxf(_focus_w, w)

# ------------------------------------------------------------------ poses

## Target longest-axis size per pose, metres. NOT one number for all six: a cat curled
## asleep is a ~0.45 m ball and the same animal at full stride is ~0.75 m nose to tail, so
## normalising every mesh to the same longest axis would shrink the running cat and inflate
## the sleeping one until they read as two different animals. These are the real ratios of
## the same cat in those poses.
## MEASURED, NOT AUTHORED — and the previous numbers were the owner's "too small when
## sitting, too big when running, all states are currently different sizes".
##
## The bug is in the QUANTITY being normalised. `load_model` scales a mesh so its LONGEST
## AXIS equals this number, and the longest axis means a different part of the animal in
## every pose: nose-to-tail on a walking cat, but roughly height on a sitting one and
## roughly width on a curled one. Handing all of them one hand-picked length therefore
## guarantees they read as different-sized animals — it normalises the wrong thing.
##
## What is actually invariant is the CAT. Its body does not shrink when it sits down. So
## these are derived by equalising CONVEX HULL VOLUME across the pose set and anchoring on
## the walk mesh at 0.66 m, which is the one that already looked right. The hull rather
## than the raw volume because not one of the seven meshes is watertight (checked), and
## `Mesh.volume` on a non-watertight mesh is meaningless.
##
## The two biggest corrections fall out as +79% on sit and -9% on run — which are exactly
## the owner's two complaints, in the right directions. That agreement is the reason to
## trust the method rather than the individual numbers.
## ONE mesh now, so ONE number — and size consistency across states is by construction,
## which retires the s36 hull-volume table this replaces. The value is that table's method
## applied to the stand mesh: equal convex-hull volume with the walk mesh anchored at
## 0.66 m (computed offline; see the s37 DEVLOG entry).
func _pose_size(_key: String) -> float:
	return STAND_SIZE_M

## Show one pose, hide the rest. The transition is a visibility flip — see POSES for why it
## is not an ANIM.replace().
func _wear(key: String) -> void:
	if key == _pose:
		return
	_pose = key
	if _rig != null:
		# Settling into rest is gentle; being startled into motion is not. The rate is the
		# only thing that differs between "eases down to sleep" and "bolts upright".
		# A stalk SETTLES into itself — a cat sinking into a crouch is the slowest thing it
		# does, and snapping into the pose throws the whole tell away. Everything that is a
		# burst of motion blends fast; everything that is a decision blends slowly.
		var rate: float = 10.0 if key in ["run", "jump", "walk", "carry"] else \
			(3.2 if key == "stalk" else 5.0)
		_rig.set_pose(key, rate)

## The pose a state wears, applied every time the state is set so a transition cannot be
## made without one.
func _enter(st: int) -> void:
	# THE ONLY PLACE `_state` IS ASSIGNED. Two sites were still writing it directly after the
	# s34 pass and the close-out screenshots caught it: the cat photographed as state 3 (SIT)
	# wearing the WALK mesh, which is the exact class of bug the pose table exists to stop —
	# a state that is true in a variable and false on screen. `grep "_state = " ship_cat.gd`
	# should only ever find this line.
	_state = st
	_wear(String(STATE_POSE.get(st, "stand")))

## Somewhere to curl up NEAR the player, probed rather than typed. Returns the point, or
## the cat's own position if nothing suitable is under it — a cat that cannot find a spot
## sleeps where it is standing, which is also what a cat does.
func _sleep_spot(near: Vector3) -> Vector3:
	var world: World3D = get_world_3d()
	if world == null:
		return global_position
	# Ring of candidates around the player, nearest first — the foot of the bed, the edge of
	# the chair, the warm spot by whatever they are sitting at.
	for r in [0.9, 1.4, 2.0]:
		for i in range(8):
			var a: float = TAU * float(i) / 8.0
			var at: Vector3 = near + Vector3(cos(a) * r, 0.0, sin(a) * r)
			var from: Vector3 = at + Vector3(0, 1.4, 0)
			var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 3.0, 0))
			q.collision_mask = 1
			q.collide_with_areas = false
			q.exclude = [_touch.get_rid()]
			var hit: Dictionary = world.direct_space_state.intersect_ray(q)
			if hit.is_empty():
				continue
			var p: Vector3 = hit["position"]
			# Only a surface at about the height the cat is already on — it will not climb
			# onto a bunk or drop off a deck to go to sleep.
			if absf(p.y - global_position.y) > STEP_UP:
				continue
			# ...AND IT MUST BE ABLE TO WALK THERE. Until s36 this returned any surface it
			# could SEE, which was fine only because the cat could walk through whatever
			# stood in the way. Now that it cannot, an unreachable spot is a cat treading
			# water for ever: the ring is drawn around the PLAYER, the bunkhouse is full of
			# bunk frames, so a candidate behind one is easy to draw and impossible to reach.
			# Caught by the close-out pass — the cat held FOLLOW at one spot through four
			# frames while the player lay down 1.5 m away.
			var wq := PhysicsRayQueryParameters3D.create(
				global_position + Vector3(0, 0.22, 0), p + Vector3(0, 0.22, 0))
			wq.collision_mask = 1
			wq.collide_with_areas = false
			wq.exclude = _walk_skip()
			if not world.direct_space_state.intersect_ray(wq).is_empty():
				continue
			# ...and the BODY has to fit where it lies down. A spot the cat can see and walk
			# to can still be a spot it cannot occupy — a 0.9 m ring drawn round a player
			# standing against a bulkhead puts half its candidates inside the steel.
			if not _step_clear(p, (p - global_position).normalized()):
				continue
			return p
	return global_position
