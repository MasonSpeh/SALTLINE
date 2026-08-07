extends CharacterBody3D
## First-person controller, deliberately unheroic (GDD A5): weighty and careful,
## not shooter-floaty. A short functional jump; climbing only at Ladder nodes —
## hold E to ascend, E+S to descend. Falling in water is a fade-out + Wet Deck
## respawn with a warmth penalty; running life dry blacks out the same way.

const WALK_SPEED: float = 3.2
const SPRINT_SPEED: float = 5.0
const CROUCH_SPEED: float = 1.5
const PRONE_SPEED: float = 0.9          ## a slow belly-crawl along the plating
const CLIMB_SPEED: float = 1.8
const ACCELERATION: float = 8.0
const GRAVITY: float = 9.8
const JUMP_VELOCITY: float = 4.2
const MOUSE_SENSITIVITY: float = 0.0025
const HEAD_BOB_WALK_FREQ: float = 1.8
const HEAD_BOB_SPRINT_FREQ: float = 2.6
const HEAD_BOB_AMPLITUDE: float = 0.03
const WATER_LEVEL: float = 0.4

# Fall damage (GDD A5: the deck is unforgiving — but not a tripwire). A fall is scored by the
# impact speed the body carries into the ground, read back as the height it fell from
# (h = v^2 / 2g under our own GRAVITY). A short drop or a normal jump (~0.9m) lands clean; past
# FALL_SAFE_HEIGHT life bleeds along FALL_DAMAGE_CURVE, and a fall of FALL_LETHAL_HEIGHT or more
# empties the bar — routing into the existing death/respawn blackout. NEVER applied while
# swimming, climbing, mantling, flying, or on the buoyant water landing (the sea breaks the fall).
#
# The rig is stacked walkways and half-storey step-downs, and the old 3.5m/11.5m linear pair
# meant routine deck traversal was chipping life off for hops the player could not read as
# dangerous. Both thresholds moved up and the curve between them was softened, so a misjudged
# step is a lesson and only a genuine long drop is fatal.
const FALL_SAFE_HEIGHT: float = 5.0      ## drops shorter than this never hurt (was 3.5; a jump is ~0.9m)
const FALL_LETHAL_HEIGHT: float = 16.0   ## a single landing from at/above this blacks you out (was 11.5)
const FALL_DAMAGE_AT_LETHAL: float = 1.0 ## life removed at exactly the lethal height (a full bar)
## Shape of the bleed between safe and lethal. 1.0 is the old straight line; above 1.0 the
## first metres past the safe height cost almost nothing and the price piles up toward the
## lethal end — which is where the fear belongs.
const FALL_DAMAGE_CURVE: float = 2.0
const FALL_TOAST_MIN: float = 0.02 ## below this the hit isn't worth a line of text

# Postures: STAND (default), CROUCH (held on the crouch key), PRONE (Z toggle — lie
# flat on the deck). Each is a capsule height, a collider y-offset, and an eye line.
# Standing back up from a shorter posture is gated by a headroom check (_posture_fits).
const POSTURE_STAND: int = 0
const POSTURE_CROUCH: int = 1
const POSTURE_PRONE: int = 2

const STAND_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 0.9
const PRONE_HEIGHT: float = 0.8         ## lowest capsule the 0.4 radius allows (2*radius)
const STAND_COL_Y: float = 0.9
const CROUCH_COL_Y: float = 0.45
const PRONE_COL_Y: float = 0.4          ## capsule centered so it rests flat on the deck
const STAND_HEAD_Y: float = 1.6
const CROUCH_HEAD_Y: float = 0.85
const PRONE_HEAD_Y: float = 0.35        ## eye a hand's width off the plating, watching the sky
const CROUCH_LERP: float = 12.0         ## crouch / rising blend — quick and responsive
const PRONE_LERP: float = 5.5           ## easing DOWN onto the deck is slower, heavier, calm

const STAMINA_MAX: float = 1.0
const STAMINA_DRAIN_PER_SEC: float = 0.2
const STAMINA_REGEN_PER_SEC: float = 0.15
const STAMINA_MIN_TO_SPRINT: float = 0.1

# Held item: bottom-right of view, tilted slightly inward, never over the crosshair.
const HAND_ITEM_POS: Vector3 = Vector3(0.28, -0.24, -0.5)
const HAND_ITEM_MAX_DIM: float = 0.18   ## largest dimension of the normalized visual (m)
const HAND_SWAY_AMPLITUDE: float = 0.008

const CLIMB_TOP_GRACE: float = 0.3      ## grab-at-the-top zone where we hold, not mantle

# Dev fly mode (testing only): double-tap F to toggle noclip free-flight.
const FLY_SPEED: float = 9.0
const FLY_SPRINT_MULT: float = 3.5
const DOUBLE_TAP_MS: int = 320

# Swimming (GDD §31: competent, not heroic). Buoyant at the surface, dive with
# crouch. You can go as deep as your breath allows — the sea no longer kills you at a
# fixed line, your OWN AIR does. Surface to breathe; run the bar dry and you drown.
const SWIM_SPEED: float = 2.3
const SWIM_SPRINT_MULT: float = 1.5
const FLOAT_DEPTH: float = 0.45        ## neutral float: this far under the swell, head above
## How deep the water has to get over a floor you are STANDING ON before it stops being wading
## and starts being swimming. Chest-deep on a 1.8 m capsule: below this you keep the walking
## controls (and can walk back out), above it the sea has you. Only consulted when there is a
## floor underfoot — step off the edge and any depth past 0.15 m is a swim, as before.
const WADE_DEPTH: float = 1.15
const SWIM_WARMTH_DRAIN: float = 0.016 ## the North Atlantic taxes you per second
## Seconds between "Cold. Swim…" warnings — see the note in _check_water(). A swell washing
## the Wet Deck puts the player under the wave line for a moment at a time, and without this
## the warning fired on every one of them.
const COLD_WARN_COOLDOWN: float = 120.0
var _cold_warn_t: float = -1000.0      ## last time the cold warning was actually shown
# Oxygen: a held breath, and now the ONE thing that limits a dive. Owner: "get rid of the
# dive too deep mechanic, player should be able to go as deep as they want until oxygen runs
# out", and "increase breath by 25%".
#
# THE DEPTH RULE THAT WAS LEFT. The fixed deep-death line went several sessions ago, but a
# second depth rule survived inside the oxygen system and was doing the same job more
# quietly: past DEEP_UNEASE_M the bar burned at 1/16 instead of 1/28, i.e. 1.75x. That is a
# depth cap wearing the breath's clothes — integrated over a straight down-and-back at
# SWIM_SPEED it stopped you at 25.3 m no matter how good your lungs were, because every
# metre past 16 cost nearly twice what it was worth. One rate at any depth now: the sea is
# as deep as you have air for.
#
# THE BREATH, +25%: 28.0 s submerged -> 35.0 s (1/28 -> 1/35 per second), plus DROWN_GRACE_SEC
# of flailing before the black. What that buys, integrated over a straight down-and-back at
# swimming speed with no pause at the bottom — both terms, since the rate change and the
# removed penalty compound:
#     walk-speed dive    25.26 m  ->  40.25 m
#     holding sprint     34.46 m  ->  60.37 m
# The reef's own floor is y -40 and the seabed is y -92, so the bottom of the coral is now
# just inside a very good breath and the abyss below it still is not.
const OXYGEN_DRAIN: float = 1.0 / 35.0     ## per second, head submerged, AT ANY DEPTH
const OXYGEN_RECOVER: float = 0.5          ## per second, breathing at the surface (~2s)
const OXYGEN_RECOVER_LAND: float = 1.5     ## per second, out of the water entirely
const DROWN_GRACE_SEC: float = 1.2         ## flailing on an empty chest before the black
## RETAINED, NOT USED HERE. `mussel_beds.gd` and `tests/mussel_probe.gd` integrate the
## controller's drain piecewise across these two to derive how deep a harvestable bed may
## sit, and neither file is this session's to edit — deleting the pair would drop their
## scripts at parse time. Held equal to OXYGEN_DRAIN so that integration still evaluates to
## the single rate above and their answer stays correct. Delete all three when those two
## files can be changed with them.
const DEEP_UNEASE_M: float = 16.0
const OXYGEN_DRAIN_DEEP: float = OXYGEN_DRAIN

@export var invert_y: bool = false
@export var mouse_sensitivity_scale: float = 1.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var _col: CollisionShape3D = $CollisionShape3D

var _hand_item: Node3D = null  ## visual item mesh held in right hand
var _attack_cd: float = 0.0    ## melee swing cooldown
var _held_item_id: String = ""
var _hand_reach: float = 0.0   ## half the held item's longest dimension — see hand_tip_world()
## The LOCAL (container-space) direction from the held item's centre out to its "tip" —
## most props are authored lying flat pointing out along -Z, but the fishing rod's shaft
## (item_visual.gd) runs up the mesh's own +Y instead, so a single hardcoded axis put the
## computed "tip" near the grip, barely off the hand, instead of out at the rod's real end.
const HAND_TIP_AXIS := {
	"fishing_rod": Vector3(0, 1, 0),
}
var _hand_reach_axis: Vector3 = Vector3(0, 0, -1)

## HOW A FISHING TOOL SITS IN THE HAND — AIMED, NOT NUDGED.
##
## Owner report, 2026-07-29: "fishing poles still oriented on side… when casting it goes
## reel/bail up. Also flip default side to the right instead of left, and give slight tilt."
##
## This used to be three Euler angles per item stacked on top of two more on `_hand_item` and
## one more inside the model (`item_visual.gd` leans its own pivot on Z), and the roll the
## owner is complaining about was the PRODUCT of all six — nobody wrote it. Measured on the
## composed basis: the rod's blank came out 0.94 up (near vertical) and its reel stuck out
## (+0.85 right, +0.20 up), i.e. the reel sat BESIDE the blank rather than on top of it. That
## is the complaint, exactly, and it is why nudging one of the six angles could never fix it.
##
## So the pose is now stated as what it has to LOOK like and solved for: name the model's own
## long axis and the direction its reel/drum stands off that axis, name where each should
## point in CAMERA space, and let `_aim_basis()` build the rotation. Every earlier stage —
## `_hand_item`'s mount angles and the model's internal lean — is divided back out
## (`_apply_hand_pose`), so the answer is the aim and nothing else, and adding a lean to a
## model in item_visual.gd can no longer roll the tool in the player's hands.
##
## TWO POSES, because a rod at rest and a rod being fished are different objects to look at
## (owner: "player should see it both ways"). `idle` is a carry: butt low on the right, blank
## up and out to the RIGHT of the view so it does not cross the middle of the screen, reel on
## top and canted back so you can see the spool. `cast` is the working pose: the blank drops
## toward the water it is fishing and the reel comes squarely UP. The swap happens the instant
## a line goes out and back again when it comes in (see the pose sync in `_physics_process`).
##
## WHICH WAY THE CRANK ENDS UP IS NOT FREE. The model is a right-handed triad — blank +Y, reel
## standing off +X, crank on +Z — so "reel up" and "tip away from the player" force the crank
## to the far side; asking for reel-up AND crank-right AND tip-away needs a basis with
## determinant -1, i.e. a mirror. The reel therefore reads as a LEFT-HAND-WIND conventional
## reel, which is what a lot of stand-up offshore gear actually is (the rod stays in the right
## hand). `face_to` is tilted back off vertical rather than straight up so the crank and the
## drag lever swing over the top of the reel into view instead of hiding behind the blank.
const HAND_TOOL_POSE := {
	"fishing_rod": {
		"axis": Vector3(0, 1, 0),          ## the blank runs up the model's own +Y
		"face": Vector3(1, 0, 0),          ## the reel stands off the blank on the model's +X
		"idle": {
			"axis_to": Vector3(0.34, 0.80, -0.50),   # up, out to the RIGHT, leaning away
			"face_to": Vector3(0.0, 0.86, 0.51),     # reel on top, canted back into view
			# LIFTED 0.10 m over the first cut of this pose, measured off the render: the AABB
			# recentre puts the rod's own middle on the hand point and the reel is 0.17 m DOWN
			# the blank from there, so the reel — the one part that says "offshore gear" — sat
			# half off the bottom edge of the screen. Same failure the old Euler pose had.
			"off": Vector3(0.08, 0.21, -0.04),
		},
		"cast": {
			"axis_to": Vector3(0.22, 0.46, -0.86),   # dropped toward the water being fished
			"face_to": Vector3(0.0, 1.0, 0.0),       # reel/bail SQUARELY up
			"off": Vector3(0.07, 0.16, -0.02),
		},
	},
	## THE WINCH, THIRD REPORT. Two things were wrong with the old entry and only one of them
	## was a number.
	##
	## (1) It named `face` as the drum's AXLE (+Z, the crank side) rather than as the direction
	## the drum stands off the mast — the one axis the owner's complaint is actually about
	## ("the reel on the left"). Aiming the axle leaves the drum's SIDE free to land wherever
	## the solve puts it, and it landed left: measured on the composed basis, the drum bracket
	## came out at (-0.81 left, +0.10 up, -0.57 away). So `face` is now the bracket, stated the
	## same way the rod's is, and where the reel sits is a number in this table again.
	##
	## (2) Drum-on-the-right was geometrically unreachable while the mast was up, because the
	## model's triad fixed the crank as mast × bracket. `item_visual._mirror_x` reflects the
	## whole machine (see the long note there), which is what the owner asked for in as many
	## words — "it should default hold/lean to the OTHER side". After the mirror the drum
	## bracket stands off on +X and the boom, the hoop fairlead and the tackle are on -X.
	##
	## IDLE is a carry: the mast up with a slight tilt, its head canted LEFT and away — the
	## other side from the old pose — and the drum out to the player's RIGHT, turned three
	## quarters toward them so the drive cheek, the ratchet and the crank knob all read
	## instead of a flat disc filling the middle of the screen. CAST is the working pose: the
	## mast tips out over the water it is fishing so the fairlead leads the line away high and
	## outboard, and the drum comes squarely UP (0.85 up against 0.14 sideways). The tackle
	## hangs DOWN from the fairlead in both, because it is gravity-aligned every frame rather
	## than carried by the pose — see _hang_stowed_tackle().
	"deep_rig_pole": {
		"axis": Vector3(0, 1, 0),          ## the mast
		"face": Vector3(1, 0, 0),          ## the drum bracket, i.e. WHICH SIDE THE REEL IS ON
		"idle": {
			"axis_to": Vector3(-0.24, 0.93, -0.28),  # mast up, head canted left: a slight tilt
			"face_to": Vector3(0.91, 0.18, 0.37),    # drum out to the RIGHT, turned to the player
			# Framed off the render, not chosen: at the first cut the fairlead projected to
			# (626, 212) of 1280x720 and the lead hanging under it finished ON the crosshair.
			# The head is canted a little further away and the whole tool lifted and pushed
			# right, which walks the hanging tackle clear of the sight line without taking the
			# drum off the right-hand edge (it reaches x~1185 of 1280).
			"off": Vector3(0.0, 0.12, -0.08),
		},
		"cast": {
			"axis_to": Vector3(-0.24, 0.62, -0.75),  # tipped out over the side it is fishing
			"face_to": Vector3(0.26, 0.78, 0.57),    # drum/bail UP, still turned to the player
			"off": Vector3(0.02, 0.02, -0.14),
		},
	},
}
## True while the hand is posed for a live cast, so the swap happens once on each transition
## rather than every frame.
var _hand_posed_cast: bool = false
## Uniform scale `_normalize_hand_visual` fitted the held item to, kept so `_apply_hand_pose`
## can rewrite the container's whole basis (rotation AND scale) in one assignment.
var _hand_scale: float = 1.0
## The held tool's own terminal tackle, if it models any (only the deck winch does). Cached at
## build time rather than found by name every frame — `_hang_stowed_tackle` runs per physics
## frame and the winch is 69 meshes deep.
var _stowed_tackle: Node3D = null

var input_locked: bool = false     ## cold open / cutscenes: look allowed, movement not
var respawn_point: Vector3 = Vector3.ZERO
var carried: Node3D = null         ## currently held physics object
var hook_out: bool = false         ## throwing hook is in flight / reeling
## Both fishing tools. FishingRod itself decides which behaviour to run from the selected
## hotbar item (`_is_deep_selected()`); this list is only "what can start a cast at all".
const ROD_ITEMS: Array[String] = ["fishing_rod", "deep_rig_pole"]
## The carryable readable. Preloaded by path (handbook.gd is newer than the class cache
## this file parses against) and used for exactly one thing: the [F] branch in _f_pressed.
const HANDBOOK := preload("res://scripts/components/handbook.gd")

var fishing: Node3D = null         ## a cast is out (FishingRod owns the line)
var ui_locked: bool = false        ## a HUD panel (inventory/journal/help/bench) is open
var build: BuildMode = null        ## build mode controller (B)
var crouching: bool = false        ## true while in the CROUCH posture (fauna read this)
var _posture: int = POSTURE_STAND  ## resolved every frame from crouch key + _prone toggle
var _prone: bool = false           ## Z toggle: lying flat on the deck (a comfort posture)
var _stamina: float = STAMINA_MAX
var _head_bob_time: float = 0.0
var _camera_base_y: float
var _jump_buffer: float = 0.0      ## brief window after a jump press, so it still fires on landing
var _jump_was_pressed: bool = false
var _fall_peak_speed: float = 0.0  ## fastest downward speed (m/s) built up since leaving the floor; scores the landing
var _climbing: Ladder = null
var _climb_from_top: bool = false  ## climb grabbed near the top — hold, don't insta-mantle
var _drowning: bool = false        ## shared blackout guard: water respawn OR life-out respawn
var _step_accum: float = 0.0
var _fly: bool = false             ## dev noclip fly mode (double-tap F)
var _last_f_ms: int = -10000       ## for double-tap F detection
var swimming: bool = false         ## in the water, buoyant, mortal
var _airless_t: float = 0.0        ## seconds spent on an empty lungful (see _swim_process)
var _low_air_warned: bool = false  ## one-shot "surface now" toast per breath

# Lying on a bed/bunk (Task: beds are lie-down-able any time). A scripted park like
# sitting, but it reuses the controller's own PRONE posture so the eye line and stealth
# are the ones the game already knows. S sleeps (the bed gates it to dusk/night), E gets
# up. Wired by bed.gd (bunks) and comfort_furniture.gd's CampBed (placed bedrolls).
var _lying: bool = false
var _lying_bed: Node = null        ## the bunk/bedroll we're turned in on
var _lying_pos: Vector3 = Vector3.ZERO  ## world point the body settles to (the mattress)
var _lying_sleeping: bool = false  ## true while the S-to-dawn fade is running

# Ledge mantle: pull up onto a knee-to-chest ledge from the air or the water (wet-deck
# lip, pontoon edges). A short assisted lerp, not a teleport. Never onto thin railings,
# never while prone.
const MANTLE_TIME: float = 0.28    ## seconds for the assisted pull-up
const MANTLE_MIN_H: float = 0.4    ## knee height — below this you just step up
const MANTLE_MAX_H: float = 1.3    ## chest height — above this it's a climb, not a mantle
var _mantling: bool = false
var _mantle_from: Vector3 = Vector3.ZERO
var _mantle_to: Vector3 = Vector3.ZERO
var _mantle_t: float = 0.0
var _mantle_cd: float = 0.0        ## brief lockout so a mantle can't instantly re-fire

const JUMP_BUFFER_TIME: float = 0.15

# ============================ not getting stuck on the rig ============================
# The rig is not a level made of clean brushes — it is ~6,800 authored primitives, and the
# walkways are lined with railings, coamings, kick plates, cleats, davit posts and hatch
# stanchions. Every one of those is a box a 0.4 m capsule can find a corner on. Three
# separate mechanisms below, because "the player keeps snagging" is three different bugs:
#
#   1. STEP-UP (_try_step_up) — a coaming, a kick plate, a door sill, a plate seam. A
#      capsule of radius r rolls up only about r*(1-cos(floor_max_angle)) ~ 0.117 m before
#      the contact normal tips past floor_max_angle and CharacterBody3D calls the lip a
#      WALL. Everything from 0.12 m to knee height is therefore an invisible fence. This
#      lifts the body over it the way a leg does.
#   2. UNSTICK (_unstick_nudge) — the wedge: the player is ASKING to move, has a real target
#      velocity, and the body has gone nowhere for several frames WHILE a direction it is
#      allowed to travel still exists. Note the last clause, which is new and which is most
#      of the fix: a right-angle rail corner does NOT trap a 0.37 m capsule (measured — 17 of
#      24 headings out of a seated corner carry you 2.2-3.1 m per second, and the 7 that do
#      not are the ones pointing into it), so a body pressed into one is stopped, not stuck,
#      and shoving it is how the assist became the bug it was written to fix.
#   3. Solver margins, set in _ready() — safe_margin, floor_snap_length, max_slides.
#
# Deliberately NOT a fix for a genuinely embedded capsule: that is _leave_climb() and
# _dismount_clear()'s job, and those run at the moment collision is re-armed.
const PLAYER_RADIUS: float = 0.37       ## see _ready(): 0.40 minus a corner-forgiveness shave
const STEP_MAX_HEIGHT: float = 0.34     ## lips up to this are stepped over, not walled off
const STEP_PROBE_FWD: float = 0.30      ## how far past the lip we must land to call it a step
const STEP_MIN_BLOCKED: float = 0.35    ## step only if we kept under this fraction of intended travel
## THE MICRO TIER — the owner's "tiny step friendly mini steps that allow player to walk
## over even if there was an imaginary bump".
##
## The tier above is deliberately hard to trigger: it will lift the body a third of a metre,
## so it may only fire when a frame was almost completely stopped (STEP_MIN_BLOCKED 0.35).
## That leaves a whole class of complaint untouched — a lip that does not STOP you but
## costs you half a stride, every stride, which is felt as a snag or a bump rather than as
## a wall, and which no amount of "the junction profiles 0.0000 m" ever addresses.
##
## So: a second tier with the opposite trade. It fires on ANY measurable loss of travel,
## and in exchange it may only lift the body a few centimetres — small enough that a
## spurious firing is imperceptible (it is under a third of the 0.107 m a normal walk frame
## covers), while being more than the ~0.117 m a 0.37 m capsule can roll over unaided and
## far more than any join tolerance on this rig. Both tiers run the SAME four proofs below
## (headroom, no wall above, something solid to land on, destination not occupied), so this
## cannot walk the player into or onto anything the conservative tier would refuse.
const MICRO_STEP_HEIGHT: float = 0.13   ## the tallest "bump" the generous tier will climb
const MICRO_MIN_BLOCKED: float = 0.92   ## ...and it fires on losing even 8% of a frame's travel
const STUCK_SPEED: float = 0.22         ## m/s of real travel under which a moving player counts as stuck
const STUCK_FRAMES: float = 0.30        ## seconds of that before we push the body out
const STUCK_NUDGE: float = 0.10         ## how hard the push is (a shove, not a teleport)
## How much of the player's own wish has to survive the faces they are touching before the
## body counts as WEDGED rather than merely STOPPED. Pressing into a corner leaves nothing —
## both faces take their component out and the remainder is ~0 — and stopping there is the
## right answer, not a bug to shove your way out of. See _unstick_nudge.
const FREE_DIR_MIN: float = 0.20
## Margin for "is this spot inside geometry?" overlap tests. Deliberately NOT safe_margin:
## a resting body sits roughly one safe_margin off the surface it stands on, so an overlap
## test run at safe_margin calls every standable spot occupied. See _try_step_up step 4.
## MEASURED on the shipping body (0.37 capsule, safe_margin 0.01, Jolt, 30 Hz): at rest the
## body sits y +0.0091 above the plating, and the zero-motion overlap test answers
## clear / clear / BLOCKED / BLOCKED / BLOCKED at margins 0.001 / 0.005 / 0.01 / 0.02 / 0.03.
## The deck you are standing on is the thing that answers. Any probe that asks "is that spot
## free?" at safe_margin has already decided the answer is no.
const OCCUPANCY_MARGIN: float = 0.001
var _stuck_t: float = 0.0

## How detectable the player is to creatures right now (1.0 standing, 0.5 crouched,
## 0.3 flat on the deck). The giant crab multiplies its detect radius by this.
func detection_factor() -> float:
	match _posture:
		POSTURE_PRONE:
			return 0.3
		POSTURE_CROUCH:
			return 0.5
		_:
			return 1.0

## Storm lantern: bloom-mucus behind glass. Warm-but-green, close, and steady —
## it should read as YOUR light against the teal, not as another bloom organ.
const LANTERN_COLOR: Color = Color(1.0, 0.86, 0.62)
const LANTERN_RANGE: float = 9.0
const LANTERN_ENERGY: float = 1.5
var _lantern_light: OmniLight3D = null

## Flashlight: a cold hard beam you aim where you look — the tool for the dark decks,
## the pump room, the stairwell. Unlike the storm lantern (a warm pool that's simply on
## whenever it's in hand), the flashlight is a SpotLight you TOGGLE: hold one and press F
## to click it on and off. Lit only while a flashlight is the item in hand AND switched on.
const FLASHLIGHT_COLOR: Color = Color(0.85, 0.9, 1.0)
const FLASHLIGHT_ENERGY: float = 4.0
var _flashlight: SpotLight3D = null
var _flashlight_on: bool = true   ## picked up switched on, like a working torch

func _ready() -> void:
	add_to_group("player")
	camera.fov = 75.0
	_camera_base_y = head.position.y
	_ensure_posture_bindings()
	_configure_body()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var ray := InteractionRay.new()
	camera.add_child(ray)
	build = BuildMode.new()
	add_child(build)
	build.setup(self, camera)
	# Create hand item holder: low-right of the view, angled slightly inward.
	_hand_item = Node3D.new()
	camera.add_child(_hand_item)
	_hand_item.position = HAND_ITEM_POS
	_hand_item.rotation.y = -0.35
	_hand_item.rotation.x = 0.15
	# The storm lantern is light you carry IN HAND: when it's the selected hotbar item it
	# throws a warm pool that moves and points with your view (an OmniLight on the camera
	# rig, down toward the held hand). Wind can't touch it, rain can't touch it — but it
	# only burns while it's the thing in your hand, not merely somewhere in the pack.
	_lantern_light = OmniLight3D.new()
	_lantern_light.light_color = LANTERN_COLOR
	_lantern_light.light_energy = 0.0
	_lantern_light.omni_range = LANTERN_RANGE
	# gl_compatibility: keep the omni cheap. Investigated 2026-07-27 against a report of
	# "the lantern isn't updating shadows correctly" raised alongside the world-fixture
	# shadow budget going 2 -> 3 (render_budget.gd): NOT related. render_budget.gd's
	# _budget_light() only enrols lights it finds with shadow_enabled == true at sweep time,
	# and this one is built false right here and never toggled — it never enters that
	# rationing system at all, so raising or lowering SHADOW_BUDGET cannot touch it. If the
	# lantern's shadow behaviour still looks wrong after this, the cause is elsewhere.
	_lantern_light.shadow_enabled = false
	camera.add_child(_lantern_light)
	_lantern_light.position = Vector3(0.25, -0.2, -0.35)
	# The flashlight beam: a SpotLight on the camera pointing where you look (a Node3D's
	# -Z is forward, and the camera already faces -Z). Off until a flashlight is in hand
	# and switched on. Shadowless on gl_compatibility to keep it cheap.
	_flashlight = SpotLight3D.new()
	_flashlight.light_color = FLASHLIGHT_COLOR
	_flashlight.light_energy = 0.0
	_flashlight.spot_range = 22.0
	_flashlight.spot_angle = 32.0
	_flashlight.spot_attenuation = 1.2
	_flashlight.shadow_enabled = false
	camera.add_child(_flashlight)
	_flashlight.position = Vector3(0.2, -0.15, 0.0)
	# _update_held_item runs on both inventory changes AND slot selection, and it drives
	# the lantern too — so selecting/holstering the lantern lights or darkens the hand.
	PlayerState.inventory_changed.connect(_update_held_item)
	# ...AND ON THE SELECTION ITSELF. `inventory_changed` alone is not "what is in my hand
	# changed": the pack panel equips a slot by writing `PlayerState.selected_hotbar` and
	# nothing else (hud.gd `_inv_slot_clicked`), which fires `hotbar_selection_changed` —
	# so the HUD moved its amber outline onto the item and popped its name while the hand
	# still held the previous slot. Measured: drop the rod into an empty hotbar square from
	# the pack and `selected_hotbar` is that square, `hotbar[square]` is "fishing_rod", and
	# `_held_item_id` is still "". The rod is "in your hand" everywhere except your hand.
	#
	# Connected here rather than adding a second `_update_held_item()` call at that one HUD
	# site, because the HUD is not the only writer (`use_hotbar`, scripted setups) and the
	# next one added would make the same mistake silently. PlayerState already announces
	# every write for exactly this reason — see the setter's own note.
	PlayerState.hotbar_selection_changed.connect(_on_hotbar_selection_changed)
	PlayerState.player_died.connect(_on_player_died)
	_update_lantern()
	_update_flashlight()

## CharacterBody3D solver setup. Done here rather than in Player.tscn so the reasoning
## lives next to the movement code that depends on it, and so a scene re-save can't quietly
## drop it back to defaults.
func _configure_body() -> void:
	# CORNER FORGIVENESS: 0.40 -> 0.37. Every authored clearance on this rig (the crane
	# hatch cheeks, the mid-landing mantle, the stair-tower flights) was measured against a
	# 0.4 m-radius capsule and is asserted in tests/access_probe.gd, so a SMALLER body is
	# strictly slack against all of them — it can never fail a gap that 0.4 fitted. What the
	# 3 cm buys is the diagonal past a railing junction: two rail runs meeting at a right
	# angle leave a corner the capsule has to round, and at 0.4 it arrives on both faces at
	# once and stops dead instead of sliding along one.
	var cap := _col.shape as CapsuleShape3D
	if cap:
		cap.radius = PLAYER_RADIUS
	# COLLISION MARGIN — 0.03 -> 0.01, AND THIS IS THE STAIR HITCH.
	#
	# Godot's default 0.001 lets the solver resolve a contact so shallow that the next frame
	# re-penetrates it, which on a seam between two butted deck plates can read as a stutter,
	# so a margin bigger than the default is right. 0.03 was not: it is 8% of the body radius,
	# and it is what turned every stair-top into a wall.
	#
	# THE MECHANISM, measured with the real controller (tests drove the actual player up the
	# tower, not a stand-in capsule). The margin inflates the capsule for contact generation,
	# so climbing a flight the body's lower sphere touches the LANDING SLAB'S LEADING TOP EDGE
	# while it is still `sqrt(2*r*m + m^2)` back down the run — 0.15 m at r=0.37, m=0.03. That
	# early contact is against a convex EDGE from below, so its normal is far steeper than the
	# ramp's own: 55-61 deg off vertical, measured, against a floor_max_angle of 46. Godot
	# therefore calls the top of the stairs a WALL, and `floor_block_on_wall` (default true)
	# answers a grounded body walking into a wall by setting `velocity` to exactly zero and
	# discarding the frame's whole motion. The player stops dead 0.35 m short of the landing;
	# _unstick_nudge then shoves them 0.10 m BACK DOWN the run every 0.30 s, they re-accelerate
	# from zero, and the cycle repeats. That is the reported "extra second onto every platform
	# off stair", and it is systemic because every flight on the rig ends in the same edge.
	#
	# The join geometry is NOT at fault and was not touched: stair_kit.gd's closed-form flush
	# ramp is correct to the millimetre, and the probe confirms the ramp's top surface passes
	# exactly through the landing's leading edge. It is the margin meeting a sharp convex
	# corner that manufactures a wall out of a flush join, which is why fixing the geometry
	# twice did not fix the report.
	#
	# 0.01 is not a guess: the failure cliff was bisected on the steepest flight in the game
	# (the tower's 38.66 deg runs). 0.015 walks the junction clean, 0.020 sticks hard. 0.01 is
	# 10x Godot's default — it keeps the anti-restitution sliver the 0.03 was reaching for,
	# measured as identical on flat plating (a 13 m topside traverse runs 4.13 s at both) —
	# and sits well under the cliff. The repaired step-up in _try_step_up is the second,
	# independent net: with both fixes the junction clears even at the old 0.03.
	safe_margin = 0.01
	# Stay glued to the deck across plate seams, grating joins and the top of a stair run.
	# Default 0.1 is shorter than the lips this rig is built from, so the body would go
	# briefly airborne, lose is_on_floor(), and re-land — which is also what made walking
	# off a small step feel like snagging.
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(46.0)   # ~the rig's steepest walkable ramp, plus a hair
	floor_stop_on_slope = true
	floor_constant_speed = true          # a ramp costs no speed; it just goes up
	# WALL SLIDE. This is what makes a glancing hit on a railing post slide along it instead
	# of stopping the body. Both are Godot defaults and both are load-bearing here, so they
	# are set explicitly: a future motion_mode/`stop_on_slope` edit can't silently turn the
	# slide off. max_slides 4 -> 6 because a railing corner is genuinely 3+ contacts (post,
	# rail run, deck) and the solver running out of iterations mid-corner IS the snag.
	wall_min_slide_angle = deg_to_rad(12.0)
	max_slides = 6
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	# THE PROPERTY THIS FILE DIAGNOSED THREE TIMES AND NEVER SET.
	#
	# The comment on `safe_margin` above works the failure out in full — a convex landing
	# edge generates a 55-61 deg contact normal against a floor_max_angle of 46, Godot
	# classes it a WALL, and "`floor_block_on_wall` (default true) answers a grounded body
	# walking into a wall by setting `velocity` to exactly zero and discarding the frame's
	# whole motion". Three comments in this file describe that mechanism. None of them ever
	# assigned the property, so it has been at Godot's default `true` for the entire life
	# of the project and every one of those frames was still being thrown away. KNOWN_ISSUES
	# flagged the omission after s39 and it stayed open.
	#
	# False lets a grounded body ride over a contact the solver has mislabelled instead of
	# being stopped dead by it. It does NOT let the player walk up real walls: a vertical
	# face has a horizontal normal, so motion into it resolves to zero vertical lift — what
	# changes is only the treatment of shallow, transient, convex edges like the top of
	# every flight on this rig.
	floor_block_on_wall = false

## Guarantee the posture actions exist even if project.godot lacks them. `crouch` is
## defined in the project map — CTRL, OPTION and COMMAND all crouch (owner's s38 call:
## sprint went back to Shift, and every macOS modifier on that side of the keyboard does
## the same crouch so there is no wrong key to hold). `prone` is registered here at
## runtime (Z) so we never have to touch project.godot. Safe to call once.
##
## This fallback has to be kept in step with the map by hand, and it is exactly the kind
## of second copy that goes stale — it has now carried three generations of this binding.
func _ensure_posture_bindings() -> void:
	if not InputMap.has_action("crouch"):
		InputMap.add_action("crouch")
		for code in [KEY_CTRL, KEY_ALT, KEY_META]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event("crouch", ev)
	if not InputMap.has_action("prone"):
		InputMap.add_action("prone")
		var ev_z := InputEventKey.new()
		ev_z.physical_keycode = KEY_Z
		InputMap.action_add_event("prone", ev_z)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: Vector2 = event.relative
		rotate_y(-motion.x * MOUSE_SENSITIVITY * mouse_sensitivity_scale)
		var pitch_delta: float = -motion.y * MOUSE_SENSITIVITY * mouse_sensitivity_scale
		if invert_y:
			pitch_delta = -pitch_delta
		head.rotate_x(pitch_delta)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	# Lying on a bed owns everything but the look: S sleeps, E gets up, nothing else fires.
	if _lying:
		_handle_lying_input(event)
		return
	# Rod selected + LMB = cast. (While a cast is out, the FishingRod handles LMB.)
	#
	# BOTH rods, and this is why the deep rig read as completely broken: FishingRod has always
	# understood the deep drop (`_is_deep_selected()` reads the selected hotbar item), but
	# nothing ever SPAWNED one unless the selected item was literally "fishing_rod". Selecting
	# the deep rig pole and clicking did nothing at all — no cast, no message. Earlier passes
	# fixed real faults further down the deep path (the line running out of range and dying
	# silently) that could never actually run, because this gate stopped it here first.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and not input_locked and not ui_locked and fishing == null \
			and carried == null and not _climbing and not hook_out \
			and not (build and build.active) and _selected_item_id() in ROD_ITEMS:
		_start_fishing()
		get_viewport().set_input_as_handled()
		return
	# A melee weapon selected + LMB = swing at whatever's in reach ahead.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and not input_locked and not ui_locked and fishing == null \
			and carried == null and not _climbing and not hook_out \
			and not (build and build.active) and _is_weapon(_selected_item_id()):
		_melee_attack()
		get_viewport().set_input_as_handled()
		return
	# Carrying a prop: left-click throws, E or G sets it down.
	if carried and not input_locked:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_throw_carried()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("interact") or (event is InputEventKey and event.keycode == KEY_G and event.pressed):
			drop_carried()
			get_viewport().set_input_as_handled()
			return
	# Prone toggle (Z): only on land, and never while a panel/cutscene owns input.
	if event.is_action_pressed("prone") and not input_locked and not ui_locked \
			and not (build and build.active) and not _climbing and not swimming and not _fly:
		_toggle_prone()
		get_viewport().set_input_as_handled()
		return
	# [B] is shared between Build Mode's own binding (below) and baiting the deep-drop rig
	# (owner spec 2026-07-27) — they were never going to collide in practice, since Build
	# Mode only ever meant anything with a build kit selected, not the rod, but the raw
	# KEY_B match below doesn't know that on its own. FishingRod.try_bait_now() owns the
	# call: it only claims the press while the deep rig is actually the wielded, idle tool
	# (see deep_rig_idle()), and returns false otherwise so B falls straight through to
	# Build Mode exactly as it always has.
	if event.is_action_pressed("bait_hook") and not ui_locked and not input_locked \
			and preload("res://scripts/components/fishing_rod.gd").try_bait_now(self):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and not input_locked:
		match event.keycode:
			KEY_1: _hotbar_pressed(0)
			KEY_2: _hotbar_pressed(1)
			KEY_3: _hotbar_pressed(2)
			KEY_4: _hotbar_pressed(3)
			# 5 and 6: the hotbar grew from 4 to 6 slots (owner call, 2026-07-27) and these
			# two keys were simply never bound — the two new slots were only reachable by
			# clicking the pack panel. KEY_B is not free (Build Mode), and KEY_F9 is debug.
			KEY_5: _hotbar_pressed(4)
			KEY_6: _hotbar_pressed(5)
			KEY_F: _f_pressed()
			KEY_F9: _identify_looked_at()
			KEY_B:
				if not ui_locked and not _climbing:
					build.toggle()

## DEBUG (F9) — name whatever you are looking at, and say how far its underside sits
## above the deck. Physics rays miss most dressing (it has no collider), so this walks
## the drawn geometry and picks the nearest mesh the view ray actually crosses. Built to
## pin down "that thing is floating" reports without guessing from screenshots.
func _identify_looked_at() -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	var origin: Vector3 = camera.global_position
	var dir: Vector3 = -camera.global_transform.basis.z
	var best: Node3D = null
	var best_d: float = 1.0e9
	var best_box := AABB()
	var stack: Array[Node] = [get_tree().current_scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.is_in_group("player"):
			continue
		var vi := n as VisualInstance3D
		if vi == null or not vi.is_inside_tree() or vi.get_aabb().size == Vector3.ZERO:
			continue
		var box: AABB = vi.global_transform * vi.get_aabb()
		if box.size.x > 40.0 or box.size.z > 40.0:
			continue                                  # skip decks/hull-scale slabs
		var hit: Variant = box.intersects_ray(origin, dir)
		if hit == null:
			continue
		var d: float = origin.distance_to(hit as Vector3)
		if d < best_d and d < 25.0:
			best_d = d
			best = vi
			best_box = box
	if best == null:
		hud.toast("F9: nothing in view within 25 m.")
		return
	var chain: String = String(best.name)
	var p: Node = best.get_parent()
	for i in 3:
		if p == null or p == get_tree().current_scene:
			break
		chain = "%s/%s" % [p.name, chain]
		p = p.get_parent()
	var c2: Vector3 = best_box.get_center()
	hud.toast("F9: %s  @(%.1f, %.1f, %.1f)  base_y=%.2f  %.1fm away" % [
		chain, c2.x, c2.y, c2.z, best_box.position.y, best_d])
	print("[F9] ", chain, "  centre=", c2, "  base_y=", best_box.position.y)

## PURE SELECTION. A number key brings the slot to hand and does nothing else.
##
## It used to be select-THEN-use: pressing a number that was already selected consumed the
## item. That reads fine written down and is a trap in play, because the inventory panel makes
## the destination slot the selected one — so stashing a fish and then pressing its number to
## LOOK at it hit the already-selected branch and ate it. Owner: "sometimes it glitches and
## just eats it... player should have to click E to eat or use those inventory items."
##
## Using is now an explicit, separate verb on E (see _try_use_held), which is also where every
## other "do the thing in front of you" verb in this game lives.
func _hotbar_pressed(slot: int) -> void:
	if ui_locked:
		return
	PlayerState.selected_hotbar = slot
	_update_held_item()

## E WITH NOTHING TO INTERACT WITH = CONSUME OR EQUIP the selected item.
##
## interaction_ray owns E whenever the crosshair is on something and consumes the event
## (interaction_ray._unhandled_input), so this only ever runs when the ray found no target —
## which makes it a free verb rather than a conflict: looking at a stove and pressing E still
## opens the stove, and looking at nothing while holding a fish eats the fish.
##
## WHAT IT DID BEFORE, and why it needed the second half. Its own comment said "only
## CONSUMABLES answer to E", but the gate it wrote was `use == ""` — and data/items.json gives
## every tool `"use": "tool"` and every build kit `"use": "build"`. So a tool DID pass the
## gate, went straight into `PlayerState.use_hotbar()`, whose entire body is inside an
## `if use == "eat" or use == "drink"` — and then returned TRUE. Pressing E at open air with
## the knife, the spear, either rod or a build kit in hand therefore did nothing at all AND
## swallowed the keypress, in three separate places that each looked correct on its own.
##
## Owner: "moving forward it should be consume/equip". Read as: the use verb should always
## resolve to one of the two, never to silence. ASSUMED, and worth a second's thought before
## it ships: there is no wear/wield SLOT in this game — the selected hotbar item IS what your
## hand holds — so "equip" can only mean "bring this slot to hand and say so". That is a real
## action rather than a no-op only because the hand and the selection can disagree: hud.gd's
## pack panel re-points `selected_hotbar` without an inventory change (the s35 fishing-rod
## bug), and a failed ItemVisual.build leaves `_held_item_id` empty. E now resyncs both.
## Already in hand and not edible: return false and let the press fall through rather than
## eat it, which is strictly more than it did before.
func _try_use_held() -> bool:
	if ui_locked or input_locked or carried != null or fishing != null:
		return false
	var slot: int = PlayerState.selected_hotbar
	if slot < 0 or slot >= PlayerState.HOTBAR_SIZE or PlayerState.hotbar[slot] == null:
		return false
	var id: String = String(PlayerState.hotbar[slot])
	var use: String = String(PlayerState.items.get(id, {}).get("use", ""))
	# CONSUME. Only eat/drink is spendable — a tool must never be silently used up by a stray
	# press at open air, which is the whole reason the number keys stopped doubling as an eat
	# button (see _hotbar_pressed).
	if use == "eat" or use == "drink":
		PlayerState.use_hotbar(slot)   # inventory_changed refreshes the hand visual
		_update_held_item()
		return true
	# EQUIP. Everything else comes to hand instead of being spent.
	if _held_item_id == id and _hand_item.get_child_count() > 0:
		return false
	_update_held_item()
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast("In hand: %s." % String(PlayerState.items.get(id, {}).get("name", id)))
	return true

## F is a double-purpose key: a single press throws the rigging hook (gameplay),
## a quick double-tap toggles dev fly mode (testing). The stray single-tap hook
## on the way into a double-tap is harmless — it needs a hook item and reels back.
func _f_pressed() -> void:
	# With a flashlight in hand, F is its on/off switch — the intuitive key wins over the
	# rigging hook, which needs its own item and is rarely held at the same time as a torch.
	if _selected_item_id() == "flashlight":
		_flashlight_on = not _flashlight_on
		_update_flashlight()
		AudioDirector.play_one_shot("clang", global_position, -30.0)   # a soft switch click
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toast"):
			hud.toast("Flashlight %s." % ("on" if _flashlight_on else "off"))
		return
	# The Fisherman's Handbook, on the same "F is whatever the hand is holding" principle:
	# it pockets the book you are standing over reading, and it opens the one you are
	# carrying. Handbook.f_pressed() answers false in every other situation, so the hook
	# and the double-tap below are untouched. See scripts/components/handbook.gd.
	if HANDBOOK.f_pressed(self):
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_f_ms <= DOUBLE_TAP_MS:
		_last_f_ms = -10000
		_toggle_fly()
		return
	_last_f_ms = now
	_throw_hook()

func _toggle_fly() -> void:
	_fly = not _fly
	velocity = Vector3.ZERO
	_climbing = null
	# Ignore the world while flying so noclip can pass through structure.
	set_collision_layer_value(1, not _fly)
	set_collision_mask_value(1, not _fly)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("FLY MODE %s  ·  Space up / Ctrl down / Shift boost" % ("ON" if _fly else "OFF"))

## Free 6-axis noclip flight for testing. Look direction drives horizontal thrust
## (pitch-aware), Space/Shift handle vertical, Ctrl boosts (it reads `jump`/`crouch`/`sprint`,
## so it followed the owner's key swap on its own — only the toast naming them had to move).
## Moves the transform directly so it passes through geometry.
func _fly_process(delta: float) -> void:
	var speed: float = FLY_SPEED * (FLY_SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)
	var input_dir: Vector2 = Vector2.ZERO
	if not ui_locked:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move: Vector3 = head.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	if Input.is_action_pressed("jump"):
		move.y += 1.0
	if Input.is_action_pressed("crouch"):
		move.y -= 1.0
	if move.length() > 0.001:
		global_position += move.normalized() * speed * delta
	velocity = Vector3.ZERO

func _selected_item_id() -> String:
	var slot: int = PlayerState.selected_hotbar
	if slot < 0 or slot >= PlayerState.HOTBAR_SIZE or PlayerState.hotbar[slot] == null:
		return ""
	return String(PlayerState.hotbar[slot])

## True when the in-hand item defines melee stats (a crafted weapon).
func _is_weapon(id: String) -> bool:
	return id != "" and PlayerState.items.get(id, {}).has("melee_damage")

## Swing the held weapon: a quick arc of the hand item, a whistle of air, and a
## hit on the nearest creature ahead within reach. Crabs and other fauna that
## implement repel() get driven off; the spear's longer reach keeps claws away.
func _melee_attack() -> void:
	if _attack_cd > 0.0:
		return
	var id: String = _selected_item_id()
	var data: Dictionary = PlayerState.items.get(id, {})
	var reach: float = float(data.get("melee_reach", 2.0))
	var dmg: float = float(data.get("melee_damage", 1.0))
	_attack_cd = float(data.get("swing_sec", 0.5))
	# UNDERWATER, A SPEAR IS FOR FISH. No new binding, no new mode to enter: the same weapon
	# on the same button does the thing the situation calls for, which is the whole "it just
	# works" contract the rest of this game's interactions are held to. On deck it stays the
	# crab-repelling swing it has always been.
	if data.get("spearfishing", false) and _head_underwater():
		_spear_thrust(reach)
		return
	_swing_hand(_attack_cd)
	AudioDirector.play_one_shot("hiss", global_position, -18.0)   # a whistle of air
	# Closest hittable roughly in front, within reach. Distance is measured from the
	# body (not the raised camera) so a ground-level crab isn't out of reach on height.
	var origin: Vector3 = global_position
	var forward: Vector3 = -camera.global_transform.basis.z
	var best: Node3D = null
	var best_d: float = reach + 0.01
	for c in get_tree().get_nodes_in_group("hittable"):
		if not (c is Node3D) or not c.has_method("repel"):
			continue
		var to: Vector3 = (c as Node3D).global_position - origin
		var dist: float = to.length()
		if dist > reach or dist < 0.05:
			continue
		if to.normalized().dot(forward) < 0.4:   # must be in the swing arc
			continue
		if dist < best_d:
			best = c
			best_d = dist
	if best:
		best.repel(global_position, dmg)

## TELLING THE PLAYER THE SPEAR FISHES, by the same contract as every other prompt in the game:
## look at a thing, and the answer is already there. A verb nobody can find is not a verb, and
## this one has no binding of its own to advertise — it is the melee button doing the sensible
## thing underwater, which is only obvious once you have seen it work.
##
## Polled rather than evented because the fish come to YOU: nothing about a shoal drifting into
## range would raise a signal. Held to SPEAR_PROMPT_HZ because bloom_fauna's per-frame GDScript
## is already the wall at every vantage (KNOWN_ISSUES) and a per-frame walk of 48 pods to write
## a label nobody asked for is exactly the kind of cost this project keeps having to claw back.
## The query's own pod-level distance reject means most of those 48 stop at one comparison.
const SPEAR_PROMPT_HZ: float = 10.0
var _spear_prompt: String = ""
var _spear_prompt_t: float = 0.0

## Read by interaction_ray, which yields the chip to whichever system owns it — the same way it
## already yields to carrying, building and a live cast.
func spear_prompt_text() -> String:
	return _spear_prompt

func _update_spear_prompt(delta: float) -> void:
	_spear_prompt_t -= delta
	if _spear_prompt_t > 0.0:
		return
	_spear_prompt_t = 1.0 / SPEAR_PROMPT_HZ
	_spear_prompt = ""
	if ui_locked or input_locked or carried != null or fishing != null:
		return
	var id: String = _selected_item_id()
	var data: Dictionary = PlayerState.items.get(id, {})
	if not data.get("spearfishing", false) or not _head_underwater():
		return
	var uw: Node = get_tree().get_first_node_in_group("underwater_world")
	if uw == null:
		return
	var hit: Dictionary = uw.spear_target(head.global_position,
		-camera.global_transform.basis.z, float(data.get("melee_reach", 3.0)))
	if hit.is_empty():
		return
	var fid: String = String(hit["id"])
	_spear_prompt = "[LMB]   Spear the %s" % String(PlayerState.items.get(fid, {}).get("name", fid))

## Is the EYE under the swell? The same test main.gd and underwater_fx use, so "the screen has
## gone underwater" and "the spear fishes" can never disagree. Not `swimming`, which is true the
## moment the body is in the water — you can tread water with your head out, and a thrust from
## up there should be the deck swing.
func _head_underwater() -> bool:
	if head == null:
		return false
	var p: Vector3 = head.global_position
	return p.y < Gyre.swim_line(Vector2(p.x, p.z), Gyre.water_time())

## THE SPEAR THRUST — the other half of this game's fishing, and the opposite verb to the rod.
##
## The rod fishes the water from above it: you stand on the plating, cast, and the table rolls
## you an anonymous fish out of whatever is theoretically down there. The spear makes you go in
## and pick one. What you hit is the individual you were aiming at, out of the shoal you swam
## into, at the depth it actually lives — so the two systems reach different fish and neither
## makes the other redundant. Breath is the cost, and it is already ticking.
const SPEAR_SCATTER_R: float = 4.5    ## how far the shoal feels a thrust go past
const SPEAR_SCATTER_HIT: float = 1.4  ## metres the startled members are shoved
const SPEAR_SCATTER_MISS: float = 2.1 ## a miss spooks them HARDER — nothing died to calm it

func _spear_thrust(reach: float) -> void:
	_lunge_hand(_attack_cd)
	var uw: Node = get_tree().get_first_node_in_group("underwater_world")
	if uw == null:
		return
	var origin: Vector3 = head.global_position
	var forward: Vector3 = -camera.global_transform.basis.z
	var hit: Dictionary = uw.spear_target(origin, forward, reach)
	if hit.is_empty():
		# A miss still moves the water. Without this a thrust into empty water is silent and
		# reads as a broken control rather than a missed fish.
		uw.scatter_fish(origin + forward * reach * 0.6, SPEAR_SCATTER_R, SPEAR_SCATTER_MISS)
		AudioDirector.play_one_shot("splash", global_position, -22.0)
		return
	var point: Vector3 = (hit["node"] as Node3D).global_position
	var taken: Dictionary = uw.take_speared(hit)
	uw.scatter_fish(point, SPEAR_SCATTER_R, SPEAR_SCATTER_HIT)
	if taken.is_empty():
		return
	_land_speared(String(taken["id"]), point)

## Bank a speared fish. Deliberately the SAME landing path as the rod (fishing_rod._land):
## journal discovery, pack-or-spill, the size roll, the record book and the fillet count all
## have to behave identically or a fish would mean different things depending on how it was
## caught — and the stove and drying line read those numbers.
func _land_speared(id: String, point: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	Journal.discover(id)
	AudioDirector.play_one_shot("splash", global_position, -8.0)
	# The size rolls BEFORE the pack is tried, for the same reason the rod's does: a
	# stowed fish's weight goes on the ledger, a spilled fish carries it into the world.
	var kg: float = FishTable.roll_size(id, rng)
	# A FULL PACK MUST NOT COST YOU THE FISH — same rule the rod follows. Underwater there is
	# no deck to spill onto, so it goes into the world at the kill and can be swum back for.
	var stowed: bool = PlayerState.add_item(id)
	if stowed:
		if kg > 0.0:
			FishTable.record_size(id, kg)
	else:
		SaveManager.drop_into_world(id, point, Vector3.ZERO, kg)
	var spill: String = "" if stowed else "  Pack's full — it's in the water where you took it."
	var data: Dictionary = PlayerState.items.get(id, {})
	var fish_name: String = String(data.get("name", id))
	if kg <= 0.0:
		_spear_toast("Speared: %s%s" % [fish_name, spill])
		return
	var big: String = ", a trophy" if FishTable.is_trophy_size(id, kg) else ""
	var n: int = FishTable.fillets_for(id, kg)
	if n <= 1:
		_spear_toast("Speared: %s — %.1f kg%s%s" % [fish_name, kg, big, spill])
		return
	_spear_toast("Speared: %s — %.1f kg%s. That'll fillet out %d times over.%s"
		% [fish_name, kg, big, n, spill])

func _spear_toast(text: String) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast(text)

## A THRUST, not a swing. The deck arc is a wide down-and-across sweep that reads as clubbing;
## underwater the same motion on the same weapon should drive straight out along the aim and
## come back, or the spear looks like it is being waved at the fish.
func _lunge_hand(dur: float) -> void:
	if _hand_item == null:
		return
	var rest: Vector3 = _hand_item.position
	var tw: Tween = create_tween()
	tw.tween_property(_hand_item, "position", rest + Vector3(0, 0, -0.55), dur * 0.28) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_hand_item, "position", rest, dur * 0.72).set_trans(Tween.TRANS_SINE)

## Arc the hand item down-and-across, then settle back — a melee swing.
func _swing_hand(dur: float) -> void:
	if _hand_item == null:
		return
	var rest: Vector3 = _hand_item.rotation
	var tw: Tween = create_tween()
	tw.tween_property(_hand_item, "rotation", rest + Vector3(deg_to_rad(-70), deg_to_rad(35), 0), dur * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_hand_item, "rotation", rest, dur * 0.65).set_trans(Tween.TRANS_SINE)

func _start_fishing() -> void:
	# Preloaded by path — the global class cache may not know the new file yet.
	var rod: Node3D = preload("res://scripts/components/fishing_rod.gd").new()
	get_tree().current_scene.add_child(rod)
	rod.setup(self, camera)
	fishing = rod

func fishing_done() -> void:
	fishing = null

func _throw_hook() -> void:
	if hook_out or carried or _climbing or ui_locked or build.active or fishing \
			or not PlayerState.has_item("throwing_hook"):
		return
	hook_out = true
	var hook := ThrowingHook.new()
	get_tree().current_scene.add_child(hook)
	hook.setup(self, camera)
	AudioDirector.play_one_shot("splash", global_position, -20.0)   # the heave grunt stand-in

func hook_returned() -> void:
	hook_out = false

func _physics_process(delta: float) -> void:
	_sync_hand_pose()
	_hang_stowed_tackle()
	if _attack_cd > 0.0:
		_attack_cd -= delta
	if _mantle_cd > 0.0:
		_mantle_cd -= delta
	_update_spear_prompt(delta)
	# Fall damage is scored only in the normal locomotion path further down. Any special
	# movement state — fly, mantle, lie, climb, or swimming (a splash into the sea) — clears
	# the fall accumulator here, so a drop that ends by grabbing a ladder, mantling a lip, or
	# hitting the water can never cash its speed in as damage on some unrelated later landing.
	if _fly or _mantling or _lying or _climbing or swimming:
		_fall_peak_speed = 0.0
	if _fly:
		_fly_process(delta)
		return
	if _mantling:
		_mantle_process(delta)
		return
	if _lying:
		_lie_process(delta)
		return
	if _climbing:
		_climb_process(delta)
		return
	# From the air or the water, a push toward a knee-to-chest ledge pulls you up onto it.
	if (swimming or not is_on_floor()) and _try_begin_mantle():
		_mantle_process(delta)
		return
	if swimming:
		_swim_process(delta)
		return
	# Fall tracking: remember whether we were grounded coming into this frame, and while
	# airborne accumulate the fastest downward speed reached — sampled after gravity so it is
	# the speed the body carries into the ground on the frame it finally lands. That peak,
	# read back as a fall height, scores the landing detected after move_and_slide() below.
	var was_on_floor: bool = is_on_floor()
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		_fall_peak_speed = maxf(_fall_peak_speed, -velocity.y)

	_update_posture(delta)

	var can_act: bool = not input_locked and not ui_locked and not (build and build.active)
	# Jump: buffer the rising edge of the press (polled, so it survives frame timing),
	# then fire on the next grounded frame. A press just before landing still counts.
	var jump_pressed: bool = can_act and Input.is_action_pressed("jump")
	if jump_pressed and not _jump_was_pressed:
		if _posture == POSTURE_PRONE:
			_prone = false   # jump gets you up off the deck instead of leaping
		else:
			_jump_buffer = JUMP_BUFFER_TIME
	_jump_was_pressed = jump_pressed
	if _jump_buffer > 0.0:
		_jump_buffer -= delta
	# Only a full stand can jump — crouched and prone are pinned to the deck.
	if can_act and _jump_buffer > 0.0 and is_on_floor() and _posture == POSTURE_STAND:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0

	var input_dir: Vector2 = Vector2.ZERO
	if not input_locked and not ui_locked:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Sprint only stands: crouch is a slow steady walk, prone is a crawl.
	var wants_sprint: bool = Input.is_action_pressed("sprint") and _stamina > STAMINA_MIN_TO_SPRINT and _posture == POSTURE_STAND
	var stamina_ceiling: float = PlayerState.stamina_ceiling_multiplier()
	var base_speed: float
	match _posture:
		POSTURE_PRONE:
			base_speed = PRONE_SPEED
		POSTURE_CROUCH:
			base_speed = CROUCH_SPEED
		_:
			base_speed = SPRINT_SPEED if wants_sprint else WALK_SPEED
	var target_speed: float = base_speed * stamina_ceiling

	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var target_velocity: Vector3 = direction * target_speed

	velocity.x = move_toward(velocity.x, target_velocity.x, ACCELERATION * delta * target_speed)
	velocity.z = move_toward(velocity.z, target_velocity.z, ACCELERATION * delta * target_speed)

	var before: Vector3 = global_position
	# HOW FAR THIS FRAME MEANT TO GO, MEASURED BEFORE move_and_slide() TOUCHES IT.
	# _try_step_up used to re-read `velocity` afterwards to work out how much travel the
	# frame had cost — but Godot's `floor_block_on_wall` path sets `velocity` to exactly
	# Vector3.ZERO when a grounded body is refused a wall, so the intended travel read back
	# as 0, the "did we get blocked?" test bailed on `wanted < 0.001`, and the step-up
	# assist was silently unavailable in the one situation it exists for. Capturing it here
	# is the whole fix; see the note on that test.
	var wanted_travel: float = Vector2(velocity.x, velocity.z).length() * delta
	move_and_slide()
	# The two anti-snag passes, in order: try to STEP the obstruction first (the common
	# case — a coaming, a kick plate, a rail's own foot), and only if we are still pinned
	# after several frames of asking to move does the unstick shove fire.
	if not _try_step_up(direction, before, wanted_travel):
		_unstick_nudge(direction, before, delta)
	else:
		_stuck_t = 0.0
	_update_fall_landing(was_on_floor)
	_update_stamina(delta, wants_sprint and direction.length() > 0.0)
	_update_head_bob(delta, direction.length() > 0.0, wants_sprint)
	_update_footsteps(delta)
	_check_water()

## STEP-UP. Called right after move_and_slide(): if we are walking, on the floor, and the
## frame ate our horizontal travel against a wall, see whether that "wall" is really a lip
## a leg would step over — and if so, place the body on top of it.
##
## The probe is three tests and it refuses on any of them, which is what keeps this from
## becoming a climbing exploit:
##   1. Is there headroom to rise STEP_MAX_HEIGHT? (No: it's a wall with a shelf, or a
##      low overhang — stepping would bury the head.)
##   2. Raised by that much, is the lane forward clear for STEP_PROBE_FWD? (No: it's a
##      wall, full stop.)
##   3. Dropping back down from there, do we LAND on something walkable? (No: it was a
##      railing bar or a hatch coaming with a hole behind it — refusing here is what stops
##      the step-up from walking the player over a guard rail and off the deck.)
## Returns true when a step was taken.
func _try_step_up(wish: Vector3, before: Vector3, wanted: float) -> bool:
	if not is_on_floor() or _posture == POSTURE_PRONE or wish.length_squared() < 0.0001:
		return false
	var dir: Vector3 = Vector3(wish.x, 0.0, wish.z)
	if dir.length() < 0.001:
		return false
	dir = dir.normalized()
	# Did the frame actually cost us travel? A clear walk moves ~speed*delta; a blocked one
	# moves a rounding error. Only bother probing when we kept less than a third of it.
	#
	# `wanted` is the pre-move value passed in by the caller, NOT `velocity` read back here.
	# move_and_slide() zeroes `velocity` outright whenever floor_block_on_wall refuses a
	# grounded body a wall, so reading it here reported "we never intended to move" for
	# exactly the frames where the body had just been hard-stopped by a lip.
	var moved: Vector3 = global_position - before
	var got: float = Vector2(moved.x, moved.z).length()
	if wanted < 0.001 or got > wanted * MICRO_MIN_BLOCKED:
		return false
	# TWO TIERS, ONE SET OF PROOFS. A frame that was almost completely stopped may be
	# rescued with a full step; a frame that merely lost a slice of its travel gets the
	# micro lift only. Everything below is shared, so the generous trigger buys no extra
	# licence — it just means a small bump no longer has to STOP the player before the
	# assist is allowed to notice it.
	var max_h: float = STEP_MAX_HEIGHT if got <= wanted * STEP_MIN_BLOCKED \
		else MICRO_STEP_HEIGHT
	var up := Vector3(0.0, max_h, 0.0)
	var base: Transform3D = global_transform
	if test_move(base, up, null, safe_margin):
		return false                                   # 1. no headroom to rise
	var raised := Transform3D(base.basis, base.origin + up)
	if test_move(raised, dir * STEP_PROBE_FWD, null, safe_margin):
		return false                                   # 2. still a wall up there
	var ahead := Transform3D(base.basis, raised.origin + dir * STEP_PROBE_FWD)
	var land := KinematicCollision3D.new()
	var fall: Vector3 = Vector3(0.0, -(max_h + 0.02), 0.0)
	if not test_move(ahead, fall, land, safe_margin):
		return false                                   # 3. nothing to stand on — a hole, not a step
	if land.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return false                                   # landed on a slope too steep to be a step
	var drop: float = land.get_travel().length()
	if drop >= max_h + 0.015:
		return false                                   # fell the whole way back: nothing was there
	var top: Vector3 = ahead.origin + Vector3(0.0, -drop, 0.0)
	if top.y - base.origin.y < 0.01:
		return false                                   # not actually a rise; let the solver have it
	# 4. Is the destination genuinely inside something? MEASURED WITH A HAIR'S-BREADTH
	# MARGIN, NOT `safe_margin`. `recovery_as_collision` reports anything the solver would
	# have to push the body out of — and a body RESTING on a surface sits about one margin
	# off it, so asking this question at safe_margin (0.03) answers "occupied" for every
	# spot the player could actually stand. The step-up therefore refused every step it
	# ever computed correctly, including the top of every stair on the rig. The same
	# reasoning is already written out in _leave_climb(), which is why that one uses 0.001.
	if test_move(Transform3D(base.basis, top), Vector3.ZERO, null, OCCUPANCY_MARGIN, true):
		return false                                   # the destination is occupied
	# RISE IN PLACE. DO NOT TELEPORT TO `top` — that is the owner's "some stairs are worse".
	#
	# `top` is 0.30 m forward (STEP_PROBE_FWD) and up to 0.34 m up (STEP_MAX_HEIGHT) of the
	# body's position, and assigning it moved the player all of that IN ONE 30 Hz TICK
	# against a normal walk step of ~0.107 m — a 3x lurch forward with a vertical pop on top,
	# fired on any flight that presents a momentary blocking contact. s25 un-broke this
	# assist (it had been dead its whole life, refusing every step it correctly computed
	# because it asked the occupancy question at safe_margin), and un-breaking it is exactly
	# when the lurch started being felt.
	#
	# The forward half was never the part that helps. What unblocks a capsule caught on a
	# lip is the RISE; once it is above the tread, ordinary movement carries it forward at
	# walking pace on the next frame. So take the height and leave the travel to the solver.
	# The probes above are unchanged and still prove there is a real tread to land on — this
	# only changes what the assist DOES once it has proven it, and step 1 already established
	# that the vertical lane is clear.
	var lift := Vector3(base.origin.x, top.y, base.origin.z)
	if test_move(Transform3D(base.basis, lift), Vector3.ZERO, null, OCCUPANCY_MARGIN, true):
		# Rising in place is blocked (a soffit or an overhang directly above). Fall back to
		# the old behaviour rather than refusing the step outright — a jerk beats a wall.
		global_position = top
	else:
		global_position = lift
	velocity.y = maxf(velocity.y, 0.0)
	apply_floor_snap()
	return true

## UNSTICK. The wedge case the step-up cannot help with: a capsule pinched where two
## colliders meet, where every slide direction move_and_slide() picks is blocked by the other
## face. The trigger is unchanged — the player is HOLDING a movement key, the body has a real
## target velocity, and it has travelled essentially nothing for STUCK_FRAMES seconds.
##
## OWNER, THIS SESSION: "player still gets stuck badly on railing corners". Reproduced and
## measured off the shipping configuration in an isolated project (the real body constants,
## Jolt, 30 Hz, against a corner built from rig_builder's own _rail_slab grammar including
## RAIL_END_SHAVE). Two separate faults, and NEITHER of them is the rail geometry:
##
## 1. THIS FUNCTION ASKED ITS CLEARANCE QUESTION AT `safe_margin`, SO THE DECK ANSWERED IT.
##    A resting body sits one safe_margin off the plating — measured y +0.0091 at
##    safe_margin 0.01 — so a zero-motion overlap test at that same margin reports every
##    horizontal candidate BLOCKED, by the floor underfoot, not by anything you are stuck on.
##    `-dir`, `side` and `-side` — the only three that can free a wedged capsule — were
##    therefore rejected on 100% of firings on flat plating; at OCCUPANCY_MARGIN the same
##    spots read clear. This is the identical defect that left `_try_step_up` dead for its
##    whole life (s25), in the same file, three functions apart; OCCUPANCY_MARGIN exists
##    BECAUSE of it and this call site was never converted.
##
## 2. SO THE ONLY CANDIDATE THAT EVER FIRED WAS THE ONE THAT LEAVES THE FLOOR, and what the
##    player felt as "stuck badly" was this assist rather than the corner. Measured, holding
##    a heading into a rail corner for 4 s: 12 firings, 12 of them `Vector3.UP`, the body
##    teleported +0.100 m and floor-snapped back every 0.30 s — a 10 cm vertical pop through
##    the eye line, three times a second, for as long as you lean on the rail. With BOTH rail
##    faces in contact even that one is blocked (the faces are inside safe_margin too): 12
##    firings, 0 mm of movement. Fire and do nothing, or fire and judder.
##
## STOPPED IS NOT STUCK, and that is the fix rather than a bigger shove. What the body may
## still legally travel is the wish with the into-the-face component of every wall contact
## removed; at a corner both faces take their share and nothing is left, which means the body
## is not trapped, it has arrived — measured from a seated corner position, 17 of 24 headings
## carry you 2.2-3.1 m in one second and the 7 that do not are exactly the ones pointing into
## the corner. So the assist stands down there, and only pushes when a legal direction exists
## and the solver still delivered nothing. That also retires the s35 stair complaint at the
## cause ("_unstick_nudge then shoves them 0.10 m BACK DOWN the run every 0.30 s", see
## _configure_body): a convex stair edge reads as a wall dead ahead, so nothing survives and
## nothing is shoved. REJECTED: simply swapping the margin. On its own it converts the pop
## into a 0.10 m backwards shove every 0.30 s against any flat wall you walk into, which is
## that stair stutter re-created on the whole rig.
##
## Measured after the change, same harness: leaning on a rail or a corner fires 0 nudges and
## moves the eye 0.000 m vertically; the escape sweep and a 3 s open-plating traverse
## (9.48 m, 0.0000 m of wobble, 0 nudges) are unchanged to the millimetre.
func _unstick_nudge(wish: Vector3, before: Vector3, delta: float) -> void:
	var dir: Vector3 = Vector3(wish.x, 0.0, wish.z)
	if dir.length() < 0.001 or not is_on_floor():
		_stuck_t = 0.0
		return
	dir = dir.normalized()
	var moved: Vector3 = global_position - before
	if Vector2(moved.x, moved.z).length() / maxf(delta, 0.0001) > STUCK_SPEED:
		_stuck_t = 0.0
		return
	_stuck_t += delta
	if _stuck_t < STUCK_FRAMES:
		return
	# What is still legal to walk this frame, from the faces the solver actually reported.
	# Read here rather than raycast: move_and_slide()'s own contacts are the ground truth for
	# what stopped it, and _try_step_up's refusal paths only test_move, which leaves them.
	var free: Vector3 = dir
	for i in get_slide_collision_count():
		var n: Vector3 = get_slide_collision(i).get_normal()
		if n.angle_to(Vector3.UP) <= floor_max_angle:
			continue                        # the deck holding you up, not something in the way
		var flat := Vector3(n.x, 0.0, n.z)
		if flat.length() < 0.01:
			continue                        # a soffit overhead blocks no horizontal travel
		flat = flat.normalized()
		if free.dot(flat) < 0.0:
			free = free.slide(flat)
	free.y = 0.0
	if free.length() < FREE_DIR_MIN:
		_stuck_t = 0.0                      # pressed into a corner or a wall: stopped, not stuck
		return
	_stuck_t = 0.0
	# A legal direction exists and the frame delivered nothing: push along what the player is
	# actually still allowed to do, then the plain retreat, then a hop for a capsule caught on
	# something low. Every spot is proved clear at OCCUPANCY_MARGIN first, so this can still
	# never shove the player through a bulkhead or off a deck.
	for d in [free, -dir, Vector3.UP]:
		var off: Vector3 = d.normalized() * STUCK_NUDGE
		var to := Transform3D(global_transform.basis, global_position + off)
		if not test_move(to, Vector3.ZERO, null, OCCUPANCY_MARGIN, true):
			global_position += off
			return

## Resolve the posture (crouch key + prone toggle), gate any RISE by a headroom check,
## then ease the capsule height, collider offset, and eye line toward it in lockstep so
## the feet stay planted. Writes `crouching` for creature detection to read.
func _update_posture(delta: float) -> void:
	var desired: int = _resolve_posture()
	# Rising into a taller posture is refused under a low ceiling — hold where we are.
	if _posture_rank(desired) > _posture_rank(_posture) and not _posture_fits(desired):
		desired = _posture
	_posture = desired
	crouching = _posture == POSTURE_CROUCH

	# Coming up is crisp; easing DOWN onto the deck is slower and calm.
	var rate: float = PRONE_LERP if _posture == POSTURE_PRONE else CROUCH_LERP
	var t: float = clampf(rate * delta, 0.0, 1.0)
	var cap := _col.shape as CapsuleShape3D
	if cap:
		cap.height = lerpf(cap.height, _posture_height(_posture), t)
	_col.position.y = lerpf(_col.position.y, _posture_col_y(_posture), t)
	_camera_base_y = lerpf(_camera_base_y, _posture_head_y(_posture), t)

## What the player is asking for this frame. Held crouch beats the prone toggle and
## clears it (tap crouch while prone → rise into a crouch). During a panel/cutscene the
## crouch key is ignored — matching the old crouch — but a standing prone toggle persists,
## so you can lie on the deck and still open the journal without popping upright.
func _resolve_posture() -> int:
	var can_key: bool = not input_locked and not ui_locked and not (build and build.active)
	if can_key and Input.is_action_pressed("crouch"):
		_prone = false
		return POSTURE_CROUCH
	if _prone:
		return POSTURE_PRONE
	return POSTURE_STAND

## Tallest posture ranks highest, so a bigger rank means "standing up more".
func _posture_rank(p: int) -> int:
	match p:
		POSTURE_PRONE:
			return 0
		POSTURE_CROUCH:
			return 1
		_:
			return 2

func _posture_height(p: int) -> float:
	match p:
		POSTURE_PRONE:
			return PRONE_HEIGHT
		POSTURE_CROUCH:
			return CROUCH_HEIGHT
		_:
			return STAND_HEIGHT

func _posture_col_y(p: int) -> float:
	match p:
		POSTURE_PRONE:
			return PRONE_COL_Y
		POSTURE_CROUCH:
			return CROUCH_COL_Y
		_:
			return STAND_COL_Y

func _posture_head_y(p: int) -> float:
	match p:
		POSTURE_PRONE:
			return PRONE_HEAD_Y
		POSTURE_CROUCH:
			return CROUCH_HEAD_Y
		_:
			return STAND_HEAD_Y

## How much the head bobs per posture — a belly-crawl barely rocks; a crouch is muted.
func _posture_bob_scale() -> float:
	match _posture:
		POSTURE_PRONE:
			return 0.25
		POSTURE_CROUCH:
			return 0.6
		_:
			return 1.0

## True if a taller capsule would clear whatever's overhead.
##
## IT USED TO PROBE ONLY WHERE THE NEW HEAD WOULD SIT — a 0.3 m sphere at the top of the target
## capsule — which leaves the body's whole growth path unchecked. Standing spans 0.0..1.8 and
## crouched spans 0.0..0.9, so the sphere sat at 1.55..2.15 and NOTHING between 0.9 and 1.55 was
## ever tested: a beam, a pipe run or a bunk frame at chest height passed the check and the
## capsule then grew straight into it. That 0.65 m blind band is the surviving half of
## KNOWN_ISSUES' "un-crouching has no headroom check" — the head-height gate had landed, the
## entry was never updated, and nothing tested a BLOCKED rise, so both halves stayed invisible
## (an assertion that only ever stands up in open air cannot tell a working gate from a missing
## one). Found s28 while trying to prove the entry stale.
##
## Now it sweeps the whole band the body is about to occupy, as a slim capsule from the current
## top to the new top. Slim on purpose — radius 0.3 against a 0.37 body radius — so a player
## standing against a bulkhead is not pinned by the wall beside them, which is why the original
## used a narrow probe and is a property worth keeping.
func _posture_fits(target: int) -> bool:
	var world: World3D = get_world_3d()
	if world == null:
		return true
	var new_top: float = _posture_col_y(target) + _posture_height(target) * 0.5
	var cur_top: float = _posture_col_y(_posture) + _posture_height(_posture) * 0.5
	if new_top <= cur_top:
		return true                 # not growing upward; nothing to clear
	const PROBE_R: float = 0.3
	var probe := CapsuleShape3D.new()
	probe.radius = PROBE_R
	# CapsuleShape3D.height is the TOTAL height including both hemispherical caps and may not
	# be less than twice the radius, so a short band still yields a legal shape.
	probe.height = maxf(new_top - cur_top + 0.1, PROBE_R * 2.0 + 0.01)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.collision_mask = 1   # world only — fauna drifting overhead don't pin you down
	params.exclude = [get_rid()]
	params.transform = Transform3D(Basis(),
		global_position + Vector3(0.0, (cur_top + new_top) * 0.5 + 0.05, 0.0))
	return world.direct_space_state.intersect_shape(params, 1).is_empty()

## Z toggles lying flat on the deck. Dropping down is always allowed; getting up is a
## normal rise, so the headroom gate in _update_posture can keep you down under an overhang
## (crawl clear, or tap crouch to come up as far as the ceiling lets you).
func _toggle_prone() -> void:
	_prone = not _prone
	if _prone:
		AudioDirector.play_one_shot("hiss", global_position, -26.0)   # a slow exhale, settling
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("You lie back on the deck plating. The sky does its slow turning.")

## Carrying the lantern lights you. Eased rather than snapped so picking it up or
## stowing it reads as a lamp being lifted, not as a switch being thrown.
func _update_lantern() -> void:
	if _lantern_light == null or not is_instance_valid(_lantern_light):
		return
	# Lit only when the lantern is BOTH owned and the selected hotbar item (in hand).
	var lit: bool = PlayerState.has_item("storm_lantern") and _selected_item_id() == "storm_lantern"
	var want: float = LANTERN_ENERGY if lit else 0.0
	if is_equal_approx(_lantern_light.light_energy, want):
		return
	var tw: Tween = create_tween()
	tw.tween_property(_lantern_light, "light_energy", want, 0.6)

## The flashlight beam is on only while a flashlight is the item in hand AND its switch
## is on. Snappier than the lantern ease — a torch clicks, it doesn't fade.
func _update_flashlight() -> void:
	if _flashlight == null or not is_instance_valid(_flashlight):
		return
	var lit: bool = _flashlight_on and _selected_item_id() == "flashlight"
	_flashlight.light_energy = FLASHLIGHT_ENERGY if lit else 0.0

## Light-scare hook (s11 giant crab): true when a held light is genuinely ON a world
## point right now. The flashlight counts as a BEAM — within ~8 m and ~30 degrees of
## where the camera looks. The storm lantern is an omni pool, so it only counts up
## close. Creatures accumulate this over time (~0.5 s) before they bolt.
const LIGHT_SCARE_DIST: float = 8.0
const LIGHT_SCARE_COS: float = 0.866   # cos(30 deg)
const LANTERN_SCARE_DIST: float = 4.5

func light_aimed_at(target: Vector3) -> bool:
	if camera == null:
		return false
	var to: Vector3 = target - camera.global_position
	var d: float = to.length()
	if _flashlight_on and _selected_item_id() == "flashlight":
		if d < LIGHT_SCARE_DIST and d > 0.05 \
				and to.normalized().dot(-camera.global_transform.basis.z) > LIGHT_SCARE_COS:
			return true
	if _selected_item_id() == "storm_lantern" and PlayerState.has_item("storm_lantern"):
		if d < LANTERN_SCARE_DIST:
			return true
	return false

func _update_footsteps(_delta: float) -> void:
	if not is_on_floor():
		return
	var horizontal: Vector3 = Vector3(velocity.x, 0, velocity.z)
	_step_accum += horizontal.length() * _delta
	# Lower postures space their contacts out — the stealth payoff. Prone is a
	# near-silent drag of cloth on plating. Ambience owns the LEVEL of each step
	# (it reads posture too); this only owns the cadence.
	var stride: float
	match _posture:
		POSTURE_PRONE:
			stride = 4.8
		POSTURE_CROUCH:
			stride = 3.6
		_:
			stride = 2.6 if Input.is_action_pressed("sprint") else 2.1
	if _step_accum >= stride:
		# The accumulator reset IS the footstep event — Ambience triggers off it and
		# plays the surface-correct sample (grate / plate / concrete / wood / water /
		# wet). The generic "step" one-shot that used to fire here layered one fixed
		# transient under all twelve of those, so wood and grate shared an attack and
		# the material distinction the samples exist for was flattened away.
		_step_accum = 0.0

## Latch onto a ladder. Hold-E climbing: E alone rises, E+S (move_back) descends,
## releasing E lets go at the current height. Grabbing from within CLIMB_TOP_GRACE of
## the top arms a hold so the player can start a descent instead of insta-mantling.
func start_climb(ladder: Ladder) -> void:
	if _climbing != null:
		return   # already climbing — never re-latch or switch ladders mid-climb
	_climbing = ladder
	_prone = false   # you don't take a ladder lying down — stand before the rungs
	velocity = Vector3.ZERO
	# Climb free of world collision: the interior well's ladder box sits ~0.35m from
	# the shaft wall and the 0.8m player capsule can't fit that gap — it jams and can't
	# rise, descend, or dismount (the "stuck on the ladder" trap). _leave_climb() re-arms.
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	var base: Vector3 = ladder.bottom_point()
	var y: float = clampf(global_position.y, base.y, ladder.top_point().y)
	global_position = Vector3(base.x, y, base.z) + ladder.face_dir() * 0.45
	_climb_from_top = y >= ladder.top_point().y - CLIMB_TOP_GRACE

## Every climb exit routes here: re-arm the world collision start_climb() disabled
## and drop the latch, so normal movement never resumes with collision ghosted off.
##
## THE MID-CLIMB STUCK TRAP. The top/bottom mantles go through _dismount_clear, but
## releasing E (or jumping off) can happen at ANY height — including the exact frames the
## capsule is passing through a hatch slab, or overlapping the shaft wall the interior
## well ladders stand 0.35 m off. Collision is off for the whole climb, so re-arming it
## right there re-armed it around a capsule already buried in the floor plate, and
## move_and_slide() cannot depenetrate a fully-embedded body: permanently stuck, out of
## the climb state, no bail key applicable. Now every route through here checks for an
## overlap after re-arming and, if buried, nudges to the nearest clear spot (off the
## ladder's wall side first, then the other way, then vertically).
func _leave_climb() -> void:
	set_collision_layer_value(1, true)
	set_collision_mask_value(1, true)
	var ladder: Ladder = _climbing
	_climbing = null
	# Zero-motion test with recovery_as_collision: true only when the capsule already
	# overlaps something (resting contact separation is far above the 0.001 margin).
	if not test_move(global_transform, Vector3.ZERO, null, 0.001, true):
		return
	var dirs: Array[Vector3] = []
	if ladder != null and is_instance_valid(ladder):
		dirs.append(ladder.face_dir())      # away from the wall the ladder faces
		dirs.append(-ladder.face_dir())
	dirs.append(Vector3.UP)                 # up out of a hatch slab
	dirs.append(Vector3.DOWN)               # down out of a ceiling lip
	for d in dirs:
		for dist in [0.35, 0.7, 1.1, 1.6]:
			var c: Vector3 = global_position + d * dist
			if not test_move(Transform3D(global_transform.basis, c), Vector3.ZERO, null, 0.001, true):
				global_position = c
				return

func _climb_process(_delta: float) -> void:
	# Let go when E is released or the player is input-locked (cutscene) — gravity resumes.
	if not Input.is_action_pressed("interact") or input_locked:
		_leave_climb()
		return

	# Hold E = climb up automatically; add S (move_back) to climb down instead.
	var up_input: float = -1.0 if Input.is_action_pressed("move_back") else 1.0
	var ladder: Ladder = _climbing
	# Space bails out of any climb — the universal unstick: hop off the rungs.
	if Input.is_action_just_pressed("jump"):
		_leave_climb()
		velocity = ladder.face_dir() * 2.0 + Vector3(0, 1.5, 0)
		return
	var top_y: float = ladder.top_point().y
	var bottom_y: float = ladder.bottom_point().y
	# Grabbed near the top: hold there instead of mantling, until a descent clears it.
	if _climb_from_top:
		if global_position.y < top_y - CLIMB_TOP_GRACE - 0.05:
			_climb_from_top = false
		elif up_input > 0.0 and global_position.y >= top_y - 0.2:
			up_input = 0.0
	velocity = Vector3(0, up_input * CLIMB_SPEED, 0)
	move_and_slide()
	if global_position.y >= top_y - 0.2 and up_input > 0.0 and not _climb_from_top:
		# Mantle off the top, onto a spot that is actually clear (never blind — see below).
		_dismount_clear(ladder.top_point() + Vector3(0, 0.4, 0), -ladder.face_dir(), ladder.exit_forward)
	elif global_position.y <= bottom_y + 0.1 and up_input < 0.0:
		# Step off the bottom onto a clear spot, not the pinch between rungs and shaft wall.
		_dismount_clear(ladder.bottom_point() + Vector3(0, 0.1, 0), -ladder.face_dir(), ladder.exit_forward)

## Leave the ladder onto a spot the capsule actually FITS. This is the fix for the
## permanent "stuck near a ladder" trap: the old exit teleported the player blind to
## anchor - face_dir*exit_forward. Collision is off during the whole climb, so if a crate,
## drum, bench or wall happened to sit at that spot, the player was dropped INSIDE it and,
## the instant collision re-armed, move_and_slide() could never depenetrate a fully-buried
## capsule — dead stuck, and out of the climb state, so none of the bail keys applied.
##
## Now: re-arm collision FIRST (so the test can see the world), then try a spread of exit
## spots — the intended one, then progressively further out, then half a body to each side,
## then straight up out of the pinch — and take the first that is clear. test_move with
## recovery_as_collision reports an initial overlap even with zero travel, so "clear" means
## the capsule does not already intersect anything there.
func _dismount_clear(anchor: Vector3, into: Vector3, ef: float) -> void:
	set_collision_layer_value(1, true)
	set_collision_mask_value(1, true)
	_climbing = null
	var flat: Vector3 = Vector3(into.x, 0.0, into.z)
	flat = flat.normalized() if flat.length() > 0.01 else -global_transform.basis.z
	var side: Vector3 = flat.cross(Vector3.UP).normalized()
	var cands: Array[Vector3] = []
	for d in [ef, ef + 0.6, ef + 1.3]:
		cands.append(anchor + flat * d)
		cands.append(anchor + flat * d + side * 0.55)
		cands.append(anchor + flat * d - side * 0.55)
	# THEN THE OTHER SIDE. `into` is derived from the ladder's facing, and the two ends of
	# one ladder do not agree on which way "off" is: a roof-access ladder mantles at the
	# top TOWARD the building it is bolted to, and steps off at the bottom AWAY from it.
	# The caller can only pass one direction, so when every spot on that side is solid —
	# which is exactly what "the intended side is the wall" looks like — try the mirror
	# before falling through. Only reached when the preferred side has already failed, so
	# a working exit never changes; this replaces "give up and bury the player".
	for d in [ef, ef + 0.6]:
		cands.append(anchor - flat * d)
		cands.append(anchor - flat * d + side * 0.55)
		cands.append(anchor - flat * d - side * 0.55)
	cands.append(anchor + Vector3(0, 1.3, 0))   # last resort: straight up
	# "Clear" is not enough on its own: the far side of a bulkhead is beautifully clear,
	# and taking it teleports the player THROUGH the wall into the next room. The shaft
	# well's exit landed 1.1 m past the shaft wall that way, and the machine-shop roof
	# ladder's bottom exit landed inside the shop. So a candidate must also be REACHABLE —
	# nothing solid on the straight line from the anchor to it, tested at body height.
	var open: Vector3 = Vector3.INF
	for c in cands:
		var xf := Transform3D(global_transform.basis, c)
		if test_move(xf, Vector3(0, -0.05, 0), null, 0.001, true):
			continue
		if open == Vector3.INF:
			open = c          # clear but maybe behind something — the old behaviour
		if _exit_reachable(anchor, c):
			global_position = c
			return
	# Nothing both clear and reachable: a clear spot still beats being buried.
	global_position = open if open != Vector3.INF else cands[0]

## Is there a straight, unobstructed line from the dismount anchor to `to`? Cast at the
## capsule's centre height so the deck underfoot is never the obstruction.
func _exit_reachable(from: Vector3, to: Vector3) -> bool:
	var lift := Vector3(0, _col.position.y, 0)
	var q := PhysicsRayQueryParameters3D.create(from + lift, to + lift)
	q.exclude = [get_rid()]
	q.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## Entering the water no longer teleports you out — you swim (GDD §31). The sea
## takes warmth constantly, ladders are the way back up, and your breath (oxygen) is
## the clock underwater. Out of the water this tops the breath back up.
func _check_water() -> void:
	if _drowning or _fly:
		return
	var wave_y: float = Gyre.swim_line(Vector2(global_position.x, global_position.z), Gyre.water_time())
	# DEPTH ALONE IS NOT ENOUGH ONCE THE SEA MOVES. The wet deck plating is WET_Y = 2.0 and the
	# tide takes mean water to +0.70, so an ordinary crest already washes over the plate — and
	# on the intertidal pontoon walkway (top y +0.95) the water is over your boots at every
	# high tide by design. Testing depth by itself would latch `swimming` while the player is
	# stood on solid steel, and _physics_process hands the whole frame to _swim_process: no
	# jump, no sprint, no footsteps, no step-up, so every coaming becomes a wall and the
	# controls change under someone who has not moved.
	#
	# You are swimming when the water has taken you, not when it has reached you. Standing on a
	# floor keeps you walking until it is genuinely deep enough to lift you — which is also just
	# true: you can wade.
	var deep: float = wave_y - global_position.y
	var now_swimming: bool = deep > 0.15 and (not is_on_floor() or deep > WADE_DEPTH)
	if now_swimming and not swimming:
		AudioDirector.play_one_shot("splash", global_position, -4.0)
		_prone = false   # you don't belly-crawl in the swell
		if _climbing:
			_leave_climb()   # fell off the ladder into the sea — re-arm world collision
		if carried:
			drop_carried()
		# THE COLD WARNING IS ON A COOLDOWN. Owner, 2026-07-30: "Add a longer toggle in between
		# the popup for the cold waves hitting, because they come all the time on the wetdeck."
		# There was no cooldown at all — the line fired on every transition into the water, and
		# the Wet Deck sits low enough that a running swell washes the plate repeatedly, so a
		# player standing at the rail got it as a ticker. It is a warning about the sea, not a
		# commentary on each wave: one every COLD_WARN_COOLDOWN seconds at most.
		var now: float = float(Time.get_ticks_msec()) * 0.001
		if now - _cold_warn_t >= COLD_WARN_COOLDOWN:
			_cold_warn_t = now
			var hud: Node = get_tree().get_first_node_in_group("hud")
			if hud:
				hud.toast("Cold. Swim — find a ladder before the sea does the counting.")
	swimming = now_swimming
	if not swimming:
		# Out of the water: catch your breath fast, and clear the drown timers.
		_airless_t = 0.0
		_low_air_warned = false
		if PlayerState.oxygen < 1.0:
			PlayerState.oxygen = minf(PlayerState.oxygen + OXYGEN_RECOVER_LAND * get_physics_process_delta_time(), 1.0)

## Buoyant first-person swimming: look-direction drive, Space up, crouch dives,
## drifting toward a neutral float just under the swell. Cold drains warmth the
## whole time; submerging spends the breath in PlayerState.oxygen, and an empty
## chest (past DROWN_GRACE_SEC) drowns you.
func _swim_process(delta: float) -> void:
	var wave_y: float = Gyre.swim_line(Vector2(global_position.x, global_position.z), Gyre.water_time())
	var input_dir: Vector2 = Vector2.ZERO
	if not input_locked and not ui_locked:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var speed: float = SWIM_SPEED * (SWIM_SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)
	var move: Vector3 = head.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	if not input_locked and not ui_locked:
		if Input.is_action_pressed("jump"):
			move.y += 0.8
		if Input.is_action_pressed("crouch"):
			move.y -= 0.8
	var target_vel: Vector3 = move.normalized() * speed if move.length() > 0.01 else Vector3.ZERO
	# Buoyancy: with no vertical intent, ease back up toward the neutral float line.
	var float_y: float = wave_y - FLOAT_DEPTH
	if absf(move.y) < 0.05:
		target_vel.y = clampf((float_y - global_position.y) * 1.6, -1.2, 1.6)
	velocity = velocity.lerp(target_vel, delta * 5.0)
	move_and_slide()
	PlayerState.warmth -= SWIM_WARMTH_DRAIN * delta
	_update_posture(delta)   # keeps the capsule sane if a posture was held on entry
	# Breath. Your head under the swell spends air; at the surface you breathe. ONE rate, at
	# any depth — the water 30 m down costs exactly what the water 3 m down costs, and how
	# far you get is a question about your lungs and nothing else (see OXYGEN_DRAIN).
	var head_submerged: bool = head.global_position.y < wave_y
	if head_submerged:
		PlayerState.oxygen = maxf(PlayerState.oxygen - OXYGEN_DRAIN * delta, 0.0)
		if PlayerState.oxygen <= 0.25 and not _low_air_warned:
			_low_air_warned = true
			var hud0: Node = get_tree().get_first_node_in_group("hud")
			if hud0:
				hud0.toast("Lungs burning. Get to the surface.")
		if PlayerState.oxygen <= 0.0:
			_airless_t += delta
			if _airless_t >= DROWN_GRACE_SEC:
				_drown()
				return
	else:
		# Breathing at the surface: air comes back, and the drown timer resets.
		PlayerState.oxygen = minf(PlayerState.oxygen + OXYGEN_RECOVER * delta, 1.0)
		_airless_t = 0.0
		if PlayerState.oxygen > 0.4:
			_low_air_warned = false
	_check_water()

## The breath ran out. Not a fixed depth line any more — you drowned. Same quiet
## respawn as before: the sea returns you to the deck with no memory of surfacing.
func _drown() -> void:
	if _drowning:
		return
	_drowning = true
	input_locked = true
	swimming = false
	AudioDirector.play_one_shot("groan", global_position, -2.0)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		var tw: Tween = hud.fade_to_black(0.9)
		tw.tween_callback(_respawn)
	else:
		_respawn()

func _respawn() -> void:
	_clear_lying_state()
	_mantling = false
	global_position = respawn_point
	velocity = Vector3.ZERO
	swimming = false
	_prone = false
	_airless_t = 0.0
	_low_air_warned = false
	_fall_peak_speed = 0.0
	PlayerState.oxygen = 1.0
	PlayerState.warmth -= 0.3
	PlayerState.life = maxf(PlayerState.life, 0.3)   # the sea returns you breathing
	_drowning = false
	input_locked = false
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.fade_from_black(1.5)
		hud.toast("You don't remember surfacing. You're on the deck, soaked through.")

## Life hit zero: same blackout shape as drowning, sharing the _drowning guard so the
## two fade/respawn flows can never run over each other.
func _on_player_died() -> void:
	if _drowning:
		return
	_drowning = true
	input_locked = true
	if _climbing:
		_leave_climb()   # dying mid-climb must re-arm the collision disabled on grab
	_clear_lying_state()  # dying while turned in drops the lie lock cleanly
	_mantling = false
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		var tw: Tween = hud.fade_to_black(1.2)
		tw.tween_callback(_respawn_from_death)
	else:
		_respawn_from_death()

func _respawn_from_death() -> void:
	_clear_lying_state()
	_mantling = false
	global_position = respawn_point
	velocity = Vector3.ZERO
	_prone = false
	swimming = false
	_airless_t = 0.0
	_low_air_warned = false
	_fall_peak_speed = 0.0
	PlayerState.oxygen = 1.0
	PlayerState.life = 0.5
	PlayerState.hunger = 0.4
	PlayerState.thirst = 0.4
	_drowning = false
	input_locked = false
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.fade_from_black(1.5)
		hud.toast("You blacked out. The rig gave you back.")

## Landing check, run right after move_and_slide(): if we just touched down (grounded now,
## airborne last frame) a fast enough arrival hurts. Grounded frames keep the accumulator
## zeroed, so only a genuine fall carries speed into the next landing. Skipped during a
## cutscene lock or the death fade, and when the sea broke the fall (a buoyant water landing).
func _update_fall_landing(was_on_floor: bool) -> void:
	if is_on_floor():
		if not was_on_floor and not input_locked and not _drowning and not _landing_in_water():
			_apply_fall_damage(_fall_peak_speed)
		_fall_peak_speed = 0.0

## True when the spot we just landed on sits under the swell — the water cushioned the fall,
## so it is a buoyant water landing, not a hard deck impact. Mirrors _check_water's swim line
## so "the sea broke your fall" means exactly "you are in swimming water".
func _landing_in_water() -> bool:
	var wave_y: float = Gyre.swim_line(Vector2(global_position.x, global_position.z), Gyre.water_time())
	return global_position.y < wave_y - 0.15

## A hard landing bleeds life with the drop. The tracked impact speed is read back as a fall
## height (h = v^2 / 2g under our own GRAVITY): under FALL_SAFE_HEIGHT you land clean; above it
## damage climbs along FALL_DAMAGE_CURVE, reaching a full bar at FALL_LETHAL_HEIGHT and beyond —
## which zeroes life through PlayerState.set_life and fires player_died -> _on_player_died, the
## same blackout/respawn the drown and life-out paths use. Reuses the "groan" one-shot (the game's
## existing pained-body cue, as in _drown) as the grunt of impact, louder the harder you hit.
func _apply_fall_damage(peak_speed: float) -> void:
	var fall_h: float = (peak_speed * peak_speed) / (2.0 * GRAVITY)
	if fall_h <= FALL_SAFE_HEIGHT:
		return   # a short step-down or a normal jump — landed clean, no cost
	var over: float = (fall_h - FALL_SAFE_HEIGHT) / maxf(0.01, FALL_LETHAL_HEIGHT - FALL_SAFE_HEIGHT)
	# Curved, not linear: at the halfway mark this costs a quarter bar instead of a half.
	# `over` is deliberately NOT clamped first — at or past the lethal height it is >= 1, where
	# the exponent leaves a full bar or more, so the blackout at the far end still stands.
	var damage: float = pow(over, FALL_DAMAGE_CURVE) * FALL_DAMAGE_AT_LETHAL
	PlayerState.life -= damage   # >= a full bar past lethal -> blackout
	AudioDirector.play_one_shot("groan", global_position, lerpf(-16.0, -2.0, clampf(damage, 0.0, 1.0)))
	# A word on the survivable hits; the lethal one hands off to the death flow's own toast.
	# Only when it actually cost something: the softened curve means the first metre past the
	# safe height takes a rounding error off the bar, and "that one cost you" over a fall the
	# player barely felt would train them to distrust the line.
	if PlayerState.life > 0.0 and damage > FALL_TOAST_MIN:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toast"):
			hud.toast("You hit the deck hard. That one cost you.")

func _update_stamina(delta: float, is_sprinting: bool) -> void:
	if is_sprinting:
		_stamina = maxf(0.0, _stamina - STAMINA_DRAIN_PER_SEC * delta)
	else:
		_stamina = minf(STAMINA_MAX, _stamina + STAMINA_REGEN_PER_SEC * delta)

func _update_head_bob(delta: float, is_moving: bool, is_sprinting: bool) -> void:
	if is_moving and is_on_floor():
		var freq: float = HEAD_BOB_SPRINT_FREQ if is_sprinting else HEAD_BOB_WALK_FREQ
		_head_bob_time += delta * freq * TAU
		head.position.y = _camera_base_y + sin(_head_bob_time) * HEAD_BOB_AMPLITUDE * _posture_bob_scale()
		# Subtle counter-phase sway on the held item; drifts around HAND_ITEM_POS,
		# far too small to ever reach the crosshair.
		_hand_item.position = HAND_ITEM_POS + Vector3(
			cos(_head_bob_time * 0.5) * HAND_SWAY_AMPLITUDE,
			-sin(_head_bob_time) * HAND_SWAY_AMPLITUDE,
			0.0)
	else:
		_head_bob_time = 0.0
		# Settle to the current base briskly so crouching drops the eye line right away.
		head.position.y = move_toward(head.position.y, _camera_base_y, delta * 4.0)
		_hand_item.position = _hand_item.position.move_toward(HAND_ITEM_POS, delta * 0.1)

func try_grab(prop: Node3D) -> void:
	if carried:
		drop_carried()
	carried = prop
	if carried is PhysProp:
		(carried as PhysProp).held_by = self
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_prompt_raw("[LMB] throw    [E] set down")

func drop_carried() -> void:
	if carried is PhysProp:
		(carried as PhysProp).held_by = null
	carried = null
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_prompt("")

func _throw_carried() -> void:
	var prop: Node3D = carried
	drop_carried()
	if prop is RigidBody3D:
		var forward: Vector3 = -camera.global_transform.basis.z
		(prop as RigidBody3D).apply_central_impulse(forward * 6.5 + Vector3(0, 1.6, 0))
		AudioDirector.play_one_shot("clang", prop.global_position, -12.0)

## The selection moved. A separate function only because the signal carries the slot, which
## the hand does not need — it reads the slot back off PlayerState like everything else here.
func _on_hotbar_selection_changed(_slot: int) -> void:
	_update_held_item()

## Rebuild the in-hand visual for the selected hotbar slot. ItemVisual meshes are
## world-scale props with internal offsets, so we normalize at runtime: recenter on the
## combined AABB and uniform-scale so the largest dimension is HAND_ITEM_MAX_DIM.
func _update_held_item() -> void:
	# The hand lights track the selected slot too — refresh them whenever the hand does.
	_update_lantern()
	_update_flashlight()
	# NOTHING TO REBUILD IF IT IS THE SAME OBJECT. This now runs on selection changes as
	# well as inventory changes, and several actions raise both (a number key sets the slot
	# and calls this directly; `use_hotbar` sets the slot AND emits inventory_changed), so
	# without this the rod's 63-mesh build ran twice per press. It also drops the rebuild a
	# stack going 5 -> 4 used to cost, which cannot change the picture.
	if _selected_item_id() == _held_item_id and _hand_item.get_child_count() > 0:
		return
	# Clear previous hand item
	for child in _hand_item.get_children():
		_hand_item.remove_child(child)
		child.queue_free()
	_held_item_id = ""
	_stowed_tackle = null

	# Show the selected hotbar item in hand; an empty/deselected slot leaves the hand bare.
	if PlayerState.selected_hotbar < 0 or PlayerState.selected_hotbar >= PlayerState.HOTBAR_SIZE:
		return
	var item: Variant = PlayerState.hotbar[PlayerState.selected_hotbar]
	if item == null or String(item).is_empty():
		return
	_held_item_id = String(item)
	var visual: Node3D = ItemVisual.build(_held_item_id)
	if visual == null:
		return
	var container := Node3D.new()
	container.add_child(visual)
	_hand_item.add_child(container)
	_normalize_hand_visual(container, visual)

## Recenter + rescale a freshly built ItemVisual so it reads as a small held prop.
## Also kills shadow casting on every mesh — a hand item shadowing the world looks wrong.
func _normalize_hand_visual(container: Node3D, visual: Node3D) -> void:
	var combined: AABB = AABB()
	var found: bool = false
	var stack: Array[Node] = [visual]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.append(c)
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh == null:
			continue
		var box: AABB = _transform_relative_to(mi, visual) * mi.mesh.get_aabb()
		combined = box if not found else combined.merge(box)
		found = true
	if not found:
		return
	var largest: float = maxf(combined.size.x, maxf(combined.size.y, combined.size.z))
	# Tools that should read at working size in hand override the pocket scale —
	# the rod especially: you fish WITH it, it shouldn't look like a pencil.
	var target: float = HAND_ITEM_MAX_DIM
	# Keep every pattern on ONE line — GDScript cannot parse a match pattern list that wraps.
	match _held_item_id:
		"fishing_rod", "deep_rig_pole":
			target = 0.9   # a full-length rod actually reads as a rod, not a twig
		"prybar":
			target = 0.4
	# ...and a CAUGHT FISH is held at its own size. The pack already photographs a fish at its
	# real body length (item_icons._render_preview), so a 48 kg barrel grouper's portrait is a
	# two-handed monster while the same fish in the hand was 18 cm of grouper — the owner's
	# "when i hold the barrel grouper it is tiny". ItemVisual.hand_size_m() owns the number and
	# derives it from the same body length the portrait uses; it returns HAND_ITEM_MAX_DIM for
	# everything that is not a raw species fish, so maxf() leaves the whole rest of the roster
	# (and the three overrides above) exactly where it was.
	target = maxf(target, ItemVisual.hand_size_m(_held_item_id))
	_hand_scale = (target / largest) if largest > 0.0001 else 1.0
	container.scale = Vector3.ONE * _hand_scale
	visual.position = -combined.get_center()
	# Half the item's longest dimension, in CONTAINER-local units (after the
	# recentre above, the visual's AABB is symmetric about the container origin).
	# hand_tip_world() uses this to find the far end of whatever is held, so a
	# line/string anchored there tracks the actual held object instead of a
	# fixed offset from the player's feet.
	_hand_reach = largest * 0.5
	_hand_reach_axis = HAND_TIP_AXIS.get(_held_item_id, Vector3(0, 0, -1))
	_stowed_tackle = container.find_child("stowed_tackle", true, false) as Node3D
	# ...and the aimed pose LAST, because it reads the container's own scale/position state.
	_hand_posed_cast = fishing != null
	_apply_hand_pose()
	_show_stowed_tackle(fishing == null)

## A line going out (or coming in) changes the pose, and neither event passes through
## `_update_held_item`, so the transition is watched here — once per change, not per frame.
## `fishing` is set by _start_fishing and cleared by FishingRod._finish, which is also what
## makes this cover a reel-in, a fouled cast, a walked-away cancel and a landed fish alike.
func _sync_hand_pose() -> void:
	var live: bool = fishing != null and is_instance_valid(fishing)
	if live == _hand_posed_cast:
		return
	_hand_posed_cast = live
	_apply_hand_pose()
	_show_stowed_tackle(not live)

## Aim the held tool: solve the container's rotation from what the tool must LOOK like rather
## than stacking another Euler offset on the five that are already in the chain.
##
## The chain is camera -> _hand_item (mount angles) -> container (this) -> visual (recentre
## only) -> the model's own pivot (its authored lean). What has to be true is a statement about
## the LAST of those in CAMERA space, so both of the others are divided back out:
##
##     basis(pivot, camera space) = B_hand * B_container * B_pivot   ==   A (the aim)
##  => B_container = B_hand.inverse() * A * B_pivot.inverse()
##
## That is the whole fix for "oriented on side". A counter-rotation bolted onto B_container
## would have produced the same picture today and drifted again the moment anyone touched
## `_hand_item`'s mount angles or added a lean to a model — which is exactly how the roll got
## there in the first place.
##
## The pivot is found as the PARENT OF THE "hand_tip" MARKER, not as child 0: every fishing
## tool already has to plant that marker on the node carrying its lean (or the fishing line
## anchors somewhere that does not move with the tool), so the one node this function needs is
## the one node the tool is already required to identify.
func _apply_hand_pose() -> void:
	if _hand_item == null or _hand_item.get_child_count() == 0:
		return
	if not HAND_TOOL_POSE.has(_held_item_id):
		return
	var container: Node3D = _hand_item.get_child(0)
	var def: Dictionary = HAND_TOOL_POSE[_held_item_id]
	var pose: Dictionary = def["cast" if _hand_posed_cast else "idle"]
	var visual: Node3D = container.get_child(0) as Node3D
	if visual == null:
		return
	var marker: Node = visual.find_child("hand_tip", true, false)
	var pivot: Node3D = null
	if marker is Node3D:
		pivot = (marker as Node3D).get_parent() as Node3D
	var b_pivot: Basis = Basis.IDENTITY
	if pivot != null and pivot != visual:
		b_pivot = _basis_relative_to(pivot, visual)
	var aim: Basis = _aim_basis(def["axis"], def["face"], pose["axis_to"], pose["face_to"])
	var b: Basis = _hand_item.transform.basis.inverse() * aim * b_pivot.inverse()
	# The 0.9 m hand scale lives on the container's basis too, so it goes on in the same write
	# rather than through the `scale` setter afterwards (which re-derives the basis from Euler
	# angles and is the sort of round trip that put a roll here in the first place).
	container.transform = Transform3D(b.scaled(Vector3.ONE * _hand_scale), pose["off"])

## The rotation that sends the model's own `axis` to `axis_to` and puts `face` as near `face_to`
## as a rotation can. Built from two orthonormal frames rather than from angles, so it cannot
## introduce a roll of its own: R = T * S.transposed(), where S is the model frame and T the
## camera-space frame it has to land on.
static func _aim_basis(axis: Vector3, face: Vector3, axis_to: Vector3, face_to: Vector3) -> Basis:
	var a1: Vector3 = axis.normalized()
	var f1: Vector3 = face - a1 * face.dot(a1)
	var a2: Vector3 = axis_to.normalized()
	var f2: Vector3 = face_to - a2 * face_to.dot(a2)
	# A `face` parallel to `axis` says nothing about roll; fall back to any perpendicular so the
	# result is still a valid rotation instead of a collapsed basis.
	if f1.length() < 0.001:
		f1 = a1.cross(Vector3.UP if absf(a1.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)
	if f2.length() < 0.001:
		f2 = a2.cross(Vector3.UP if absf(a2.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)
	f1 = f1.normalized()
	f2 = f2.normalized()
	var s := Basis(a1, f1, a1.cross(f1))
	var t := Basis(a2, f2, a2.cross(f2))
	return t * s.transposed()

## Accumulated basis of `node` relative to `base`, walking up the parents.
static func _basis_relative_to(node: Node3D, base: Node3D) -> Basis:
	var b: Basis = Basis.IDENTITY
	var cur: Node3D = node
	while cur != null and cur != base:
		b = cur.transform.basis * b
		cur = cur.get_parent() as Node3D
	return b

## THE TACKLE THAT IS PART OF THE MODEL, hidden while a cast is live.
##
## Owner note, 2026-07-29: "There is a hook and bobber in the 3-d model too already, consider
## the mesh portion." The deck winch carries its terminal tackle hove up short under the hoop
## fairlead — swivel, three-way, torpedo lead, snooded hook, lumo bead — because that is how a
## hand-line is carried between drops. `fishing_rod.gd` then spawns its OWN lead for the cast,
## so a live cast drew the lead twice: one on the hook 44 m down and a second still hanging off
## the tool. The model's copy is the one that gives way, since the flying one is the one the
## game is simulating. Nothing to do for the wand rod, which carries no tackle in its mesh.
func _show_stowed_tackle(shown: bool) -> void:
	if is_instance_valid(_stowed_tackle):
		_stowed_tackle.visible = shown

## THE WEIGHT HANGS DOWN. Owner, 2026-07-30, on the winch: "when casting it goes reel/bail up,
## and the weight/hook points down."
##
## `_tool_tackle` builds the lead and the snooded hook straight down the model's own -Y from
## the fairlead, so with the tool aimed they trailed off at whatever angle the mast happened to
## be at — sideways in the working pose, and swinging as the player looked around, which is
## exactly what a 1.4 kg torpedo lead never does. Rather than trade the mast's angle away for
## it, the tackle is counter-rotated to WORLD DOWN every frame: it is the one part of the
## machine gravity owns, so it is the one part that is not posed.
##
## Cheap and self-limiting — one basis write, only while a winch is actually in the hand with
## its tackle shown (a live cast hides it, see _show_stowed_tackle). The node's own scale is
## rebuilt from the parent's so the hand normalisation is not divided out twice.
func _hang_stowed_tackle() -> void:
	if not is_instance_valid(_stowed_tackle) or not _stowed_tackle.visible:
		return
	var node: Node3D = _stowed_tackle
	var parent: Node3D = node.get_parent() as Node3D
	if parent == null:
		return
	# The tackle's own +Y must come back to world up; its swing plane is kept as square to the
	# view as the aim allows so the hook reads against the water rather than end-on.
	var pb: Basis = parent.global_transform.basis.orthonormalized()
	var up: Vector3 = Vector3.UP
	var side: Vector3 = camera.global_transform.basis.x if camera != null else Vector3.RIGHT
	side = side - up * side.dot(up)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var want := Basis(side, up, side.cross(up))
	node.transform.basis = pb.inverse() * want

## World position of the far end of whatever is currently in the hand — the
## fishing rod anchors its line/string here instead of a fixed offset from the
## player's feet, which never tracked the camera at all (turn to look around and
## the old anchor stayed put while the rod visual swung with the view, so the
## line read as "glitched away" from the rod). container is _hand_item's first
## (and only) child, built fresh by _update_held_item whenever a hotbar slot changes;
## its LIVE global_transform already carries the camera's position/look, the
## idle sway, and the per-item angle/offset tweak above.
##
## If the item's ItemVisual placed an exact "hand_tip" marker (see item_visual.gd's
## fishing_rod case), that node's own global_position is used directly — the real
## rendered tip, not a guess. Otherwise a local point along _hand_reach_axis (most
## props are built lying flat along -Z; a few, like the rod, run up their own +Y —
## see HAND_TIP_AXIS) approximates the far end of whatever is held.
func hand_tip_world() -> Vector3:
	if _hand_item == null or _hand_item.get_child_count() == 0:
		return camera.global_position - camera.global_transform.basis.z * 0.6
	var container: Node3D = _hand_item.get_child(0)
	var marker: Node = container.find_child("hand_tip", true, false)
	if marker is Node3D:
		return (marker as Node3D).global_position
	return container.global_transform * (_hand_reach_axis * _hand_reach)

# ============================== lying on a bed ==============================

## E on a bunk/bedroll: lie down on the mattress in the PRONE posture the controller
## already owns — movement parked, but the look is free. From here S sleeps (the bed
## gates it to dusk/night) and E gets you up, both shown as a HUD hint. Called by
## bed.gd (bunks) and comfort_furniture.gd's CampBed (placed bedrolls); each hands us
## where the body should park (the mattress) and which way to face.
func lie_on_bed(bed: Node) -> void:
	if _lying or _mantling or _climbing or swimming or _fly:
		return
	if bed == null or not is_instance_valid(bed) or not bed.has_method("bed_lie_pos"):
		return
	_lying = true
	_lying_bed = bed
	_lying_sleeping = false
	_prone = true
	ui_locked = true          # the interaction ray stands down — we own E now
	velocity = Vector3.ZERO
	_lying_pos = bed.bed_lie_pos()
	rotation.y = float(bed.bed_lie_yaw())
	PlayerState.resting = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hint"):
		hud.set_hint("[S]  sleep      [E]  get up")

## Movement while lying: settle onto the mattress (a short assisted move, not a snap),
## hold there, and keep easing the eye line down into the prone posture.
func _lie_process(delta: float) -> void:
	velocity = Vector3.ZERO
	global_position = global_position.lerp(_lying_pos, clampf(delta * 8.0, 0.0, 1.0))
	_prone = true
	_update_posture(delta)
	_update_head_bob(delta, false, false)

## While lying, S asks the bed to sleep and E gets up. The fade window (S-to-dawn) is
## owned by the bed; ignore keys until it hands control back through bed_sleep_finished().
func _handle_lying_input(event: InputEvent) -> void:
	if _lying_sleeping:
		return
	if event.is_action_pressed("interact"):
		_end_lying()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_back"):
		_try_bed_sleep()
		get_viewport().set_input_as_handled()

## S while lying: sleep, if the bed allows it right now (its own dusk/night gate). The
## bed runs the existing fade -> skip-to-dawn -> wake flow and, on waking, calls
## bed_sleep_finished() to stand us up — so the S path reuses the exact sleep code the
## standing SLEEP verb (and the sleep probes) drive.
func _try_bed_sleep() -> void:
	if _lying_bed == null or not is_instance_valid(_lying_bed):
		return
	if not bool(_lying_bed.call("bed_can_sleep")):
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toast"):
			hud.toast("Not dark enough to sleep. Rest here — dusk will come.")
		return
	_lying_sleeping = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hint"):
		hud.set_hint("")   # release the lie hint; the fade owns the screen now
	_lying_bed.interact("SLEEP", self)

## The bed's wake callback lands here after an S-to-sleep. Stand back up. Guarded so a
## direct SLEEP interact (the sleep probes, never lying) harmlessly no-ops.
func bed_sleep_finished() -> void:
	if not _lying:
		return
	_end_lying()

## Get up: drop the lying lock, rise out of prone, hand input back, clear the hint.
func _end_lying() -> void:
	if not _lying:
		return
	_lying = false
	_lying_bed = null
	_lying_sleeping = false
	_prone = false
	ui_locked = false
	PlayerState.resting = false
	velocity = Vector3.ZERO
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hint"):
		hud.set_hint("")

## Force the lying state off without any wake choreography — for death/respawn, where
## the fade and control handoff are owned by the death flow, not the bed.
func _clear_lying_state() -> void:
	if not _lying and not _lying_sleeping:
		return
	_lying = false
	_lying_bed = null
	_lying_sleeping = false
	ui_locked = false
	PlayerState.resting = false
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hint"):
		hud.set_hint("")

# ============================== ledge mantle ================================

## From the air or the water, pushing toward a knee-to-chest ledge with standing room
## above pulls you up onto it — the wet-deck lip from the sea, a pontoon edge, a low
## parapet. Conservative by design: it refuses thin railings (a solid face must sit
## below the lip) and never fires while prone. Returns true when a mantle was armed.
func _try_begin_mantle() -> bool:
	if _mantle_cd > 0.0 or _lying or _climbing or _fly:
		return false
	if input_locked or ui_locked or (build and build.active):
		return false
	if _posture == POSTURE_PRONE:
		return false
	# Must be actively pushing toward the ledge (a lean, not a drift-by).
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_dir.length() < 0.5:
		return false
	var forward: Vector3 = transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	forward.y = 0.0
	if forward.length() < 0.1:
		return false
	forward = forward.normalized()
	var world: World3D = get_world_3d()
	if world == null:
		return false
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var feet_y: float = global_position.y
	var radius: float = 0.4
	var ahead: Vector3 = Vector3(global_position.x, 0.0, global_position.z) + forward * (radius + 0.35)
	# 1. Drop a ray just past the capsule to find the ledge top, and require it be a
	#    walkable surface sitting between knee and chest height above the feet.
	var top_hit: Dictionary = _mantle_ray(space,
		Vector3(ahead.x, feet_y + MANTLE_MAX_H + 0.1, ahead.z),
		Vector3(ahead.x, feet_y + MANTLE_MIN_H - 0.1, ahead.z))
	if top_hit.is_empty() or float(top_hit.normal.y) < 0.7:
		return false
	var ledge_y: float = float(top_hit.position.y)
	var ledge_h: float = ledge_y - feet_y
	if ledge_h < MANTLE_MIN_H or ledge_h > MANTLE_MAX_H:
		return false
	# 2. A solid face must sit below the lip at knee height — a step, not a thin rail.
	#    Railings leave a gap there (posts are slim and get missed), so this refuses them.
	if _mantle_ray(space,
			Vector3(global_position.x, feet_y + 0.3, global_position.z),
			Vector3(global_position.x, feet_y + 0.3, global_position.z) + forward * (radius + 0.45)).is_empty():
		return false
	# 3. Standing room for a full stand on the ledge, or there's nowhere to end up.
	var dest: Vector3 = Vector3(ahead.x, ledge_y + 0.05, ahead.z)
	if not _mantle_room(space, dest):
		return false
	_mantle_from = global_position
	_mantle_to = dest
	_mantle_t = 0.0
	_mantling = true
	velocity = Vector3.ZERO
	return true

## The assisted pull-up: a smoothstepped lerp from the takeoff point up onto the ledge
## over MANTLE_TIME. Direct position moves (no move_and_slide) so it rides cleanly over
## the lip; the destination was already proven clear before we committed.
func _mantle_process(delta: float) -> void:
	_mantle_t += delta
	var a: float = clampf(_mantle_t / MANTLE_TIME, 0.0, 1.0)
	var s: float = a * a * (3.0 - 2.0 * a)
	global_position = _mantle_from.lerp(_mantle_to, s)
	velocity = Vector3.ZERO
	if a >= 1.0:
		_mantling = false
		_mantle_cd = 0.35
		swimming = false     # a mantle out of the sea lands you dry on the deck
		_airless_t = 0.0

## A world-only ray (collision layer 1, excluding the player) as a plain hit Dictionary.
func _mantle_ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return space.intersect_ray(q)

## True if a full standing capsule fits at `dest_feet` clear of world geometry — the
## "is there room up there to stand" check that keeps mantles off cramped ledges.
func _mantle_room(space: PhysicsDirectSpaceState3D, dest_feet: Vector3) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = STAND_HEIGHT
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = cap
	params.collision_mask = 1
	params.exclude = [get_rid()]
	params.transform = Transform3D(Basis(), dest_feet + Vector3(0.0, STAND_HEIGHT * 0.5, 0.0))
	return space.intersect_shape(params, 1).is_empty()

## Composed local transform of `node` relative to ancestor `root` (tree-independent).
static func _transform_relative_to(node: Node3D, root: Node3D) -> Transform3D:
	var t: Transform3D = Transform3D.IDENTITY
	var n: Node3D = node
	while n != null and n != root:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t
