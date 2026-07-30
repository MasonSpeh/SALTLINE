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
const SWIM_WARMTH_DRAIN: float = 0.016 ## the North Atlantic taxes you per second
# Oxygen: a held breath, not a fixed death line. A full lungful lasts ~28s submerged;
# the deep (past DEEP_UNEASE_M) burns it near twice as fast — pressure and dread — so
# you CAN dive to glimpse what lives down there, but never linger. Surfacing (head above
# the swell) refills fast; climbing out tops you off almost at once.
const OXYGEN_DRAIN: float = 1.0 / 28.0     ## per second, head submerged, shallow
const OXYGEN_DRAIN_DEEP: float = 1.0 / 16.0 ## per second, past the unease line
const OXYGEN_RECOVER: float = 0.5          ## per second, breathing at the surface (~2s)
const OXYGEN_RECOVER_LAND: float = 1.5     ## per second, out of the water entirely
const DEEP_UNEASE_M: float = 16.0          ## below this the dark eats air faster
const DROWN_GRACE_SEC: float = 1.2         ## flailing on an empty chest before the black

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

## HOW A FISHING TOOL SITS IN THE HAND, per item, because the two tools have nothing in
## common geometrically. `_normalize_hand_visual` recentres a held item on its own AABB and
## scales the longest axis to 0.9 m; both of those are right, and both mean the offset that
## frames one tool cannot frame the other.
##
##   fishing_rod — 2.10 m of blank, AABB centre a long way up the shaft, reel a quarter of
##     the way up from the butt. Centring the 0.9 m rig on the hand point put the one part
##     that says "offshore gear" just under the bottom edge of the screen and the player
##     held a bare stick, so it is LIFTED by about half a reel. Unchanged.
##   deep_rig_pole — a 1.03 x 0.64 x 0.46 m deck winch. Its AABB centre already lands on
##     the drum (measured: centre y 0.505 against a drum axis at 0.511), so the rod's
##     +0.12 m lift is a lift it does not need: it pushed the foot out of frame and carried
##     the hoop fairlead and its hanging tackle up into the top edge, and the rod's +0.05 m
##     of right-shift ran the tackle off the right edge — this tool is 0.56 m wide in hand
##     against a rod's thin diagonal. So: no lift, shifted LEFT and pulled a little nearer,
##     and tipped less far over (-14° against the rod's -24°) because a machine has to read
##     round and upright, not foreshortened. Verified by render, not by arithmetic.
const HAND_TOOL_POSE := {
	"fishing_rod": {
		"rot": Vector3(deg_to_rad(-24.0), deg_to_rad(-14.0), 0.0),
		"off": Vector3(0.05, 0.12, -0.1),
	},
	"deep_rig_pole": {
		"rot": Vector3(deg_to_rad(-14.0), deg_to_rad(-14.0), 0.0),
		"off": Vector3(-0.05, 0.0, -0.04),
	},
}

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
#   2. UNSTICK (_unstick_nudge) — the wedge. Two colliders meeting at a corner can trap the
#      capsule in a pocket where every slide direction is blocked by the other face, and
#      move_and_slide() will happily spend the rest of the session there. If the player is
#      ASKING to move and the body has gone nowhere for several frames, we push it out.
#   3. Solver margins, set in _ready() — safe_margin, floor_snap_length, max_slides.
#
# Deliberately NOT a fix for a genuinely embedded capsule: that is _leave_climb() and
# _dismount_clear()'s job, and those run at the moment collision is re-armed.
const PLAYER_RADIUS: float = 0.37       ## see _ready(): 0.40 minus a corner-forgiveness shave
const STEP_MAX_HEIGHT: float = 0.34     ## lips up to this are stepped over, not walled off
const STEP_PROBE_FWD: float = 0.30      ## how far past the lip we must land to call it a step
const STEP_MIN_BLOCKED: float = 0.35    ## step only if we kept under this fraction of intended travel
const STUCK_SPEED: float = 0.22         ## m/s of real travel under which a moving player counts as stuck
const STUCK_FRAMES: float = 0.30        ## seconds of that before we push the body out
const STUCK_NUDGE: float = 0.10         ## how hard the push is (a shove, not a teleport)
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
	# Collision margin. The default 0.001 lets the solver resolve a contact so shallow that
	# the next frame re-penetrates it, which on a seam between two butted deck plates reads
	# as a stutter. 0.03 keeps the body a visible sliver off every surface.
	safe_margin = 0.03
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

## Guarantee the posture actions exist even if project.godot lacks them. `crouch` is
## defined in the project map (Ctrl); `prone` is registered here at runtime (Z) so we
## never have to touch project.godot. Safe to call once — skips actions already present.
func _ensure_posture_bindings() -> void:
	if not InputMap.has_action("crouch"):
		InputMap.add_action("crouch")
		var ev_ctrl := InputEventKey.new()
		ev_ctrl.physical_keycode = KEY_CTRL
		InputMap.action_add_event("crouch", ev_ctrl)
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

## Select-then-use: first press of a number selects the slot (item shows in hand),
## pressing the SAME number again uses it. Selecting an empty slot clears the hand.
func _hotbar_pressed(slot: int) -> void:
	if ui_locked:
		return
	if PlayerState.selected_hotbar == slot and PlayerState.hotbar[slot] != null:
		PlayerState.use_hotbar(slot)   # inventory_changed refreshes the hand visual
	else:
		PlayerState.selected_hotbar = slot
	_update_held_item()

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
## (pitch-aware), Space/Ctrl handle vertical, Shift boosts. Moves the transform
## directly so it passes through geometry.
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
	if _attack_cd > 0.0:
		_attack_cd -= delta
	if _mantle_cd > 0.0:
		_mantle_cd -= delta
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
	move_and_slide()
	# The two anti-snag passes, in order: try to STEP the obstruction first (the common
	# case — a coaming, a kick plate, a rail's own foot), and only if we are still pinned
	# after several frames of asking to move does the unstick shove fire.
	if not _try_step_up(direction, before):
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
func _try_step_up(wish: Vector3, before: Vector3) -> bool:
	if not is_on_floor() or _posture == POSTURE_PRONE or wish.length_squared() < 0.0001:
		return false
	var dir: Vector3 = Vector3(wish.x, 0.0, wish.z)
	if dir.length() < 0.001:
		return false
	dir = dir.normalized()
	# Did the frame actually cost us travel? A clear walk moves ~speed*delta; a blocked one
	# moves a rounding error. Only bother probing when we kept less than a third of it.
	var moved: Vector3 = global_position - before
	var got: float = Vector2(moved.x, moved.z).length()
	var wanted: float = Vector2(velocity.x, velocity.z).length() * get_physics_process_delta_time()
	if wanted < 0.001 or got > wanted * STEP_MIN_BLOCKED:
		return false
	var up := Vector3(0.0, STEP_MAX_HEIGHT, 0.0)
	var base: Transform3D = global_transform
	if test_move(base, up, null, safe_margin):
		return false                                   # 1. no headroom to rise
	var raised := Transform3D(base.basis, base.origin + up)
	if test_move(raised, dir * STEP_PROBE_FWD, null, safe_margin):
		return false                                   # 2. still a wall up there
	var ahead := Transform3D(base.basis, raised.origin + dir * STEP_PROBE_FWD)
	var land := KinematicCollision3D.new()
	var fall: Vector3 = Vector3(0.0, -(STEP_MAX_HEIGHT + 0.02), 0.0)
	if not test_move(ahead, fall, land, safe_margin):
		return false                                   # 3. nothing to stand on — a hole, not a step
	if land.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return false                                   # landed on a slope too steep to be a step
	var drop: float = land.get_travel().length()
	if drop >= STEP_MAX_HEIGHT + 0.015:
		return false                                   # fell the whole way back: nothing was there
	var top: Vector3 = ahead.origin + Vector3(0.0, -drop, 0.0)
	if top.y - base.origin.y < 0.01:
		return false                                   # not actually a rise; let the solver have it
	if test_move(Transform3D(base.basis, top), Vector3.ZERO, null, safe_margin, true):
		return false                                   # the destination is occupied
	global_position = top
	velocity.y = maxf(velocity.y, 0.0)
	apply_floor_snap()
	return true

## UNSTICK. The wedge case the step-up cannot help with: a capsule pinched in the pocket
## where two colliders meet, where every slide direction move_and_slide() picks is blocked
## by the other face. The signature is unambiguous — the player is HOLDING a movement key,
## the body has a real target velocity, and it has travelled essentially nothing for
## STUCK_FRAMES seconds — so we can act on it without ever firing on someone who is simply
## standing still or pressed against a bulkhead on purpose (walking into a wall head-on
## still moves you along it, and releasing the key resets the timer immediately).
##
## The push is small and it is tried in the least-surprising order: back the way we came
## first (undo the wedge), then the two sideways slides, then a short hop's worth of lift.
## Anything that does not land the capsule somewhere genuinely clear is discarded, so this
## can never shove the player through a bulkhead or off a deck.
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
	_stuck_t = 0.0
	var side: Vector3 = dir.cross(Vector3.UP).normalized()
	for d in [-dir, side, -side, dir + Vector3.UP, Vector3.UP]:
		var off: Vector3 = d.normalized() * STUCK_NUDGE
		var to := Transform3D(global_transform.basis, global_position + off)
		if not test_move(to, Vector3.ZERO, null, safe_margin, true):
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

## True if a taller capsule would clear whatever's overhead. A slim sphere probe (radius
## under the body radius, so side walls never trip it) is placed where the new head would
## sit; if world geometry is already there, the rise is blocked and we stay low.
func _posture_fits(target: int) -> bool:
	var world: World3D = get_world_3d()
	if world == null:
		return true
	var top: float = _posture_col_y(target) + _posture_height(target) * 0.5
	var probe := SphereShape3D.new()
	probe.radius = 0.3
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.collision_mask = 1   # world only — fauna drifting overhead don't pin you down
	params.exclude = [get_rid()]
	params.transform = Transform3D(Basis(), global_position + Vector3(0.0, top + 0.05, 0.0))
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
	var wave_y: float = Gyre.wave_height(Vector2(global_position.x, global_position.z), Gyre.water_time()) * 0.85
	var now_swimming: bool = global_position.y < wave_y - 0.15
	if now_swimming and not swimming:
		AudioDirector.play_one_shot("splash", global_position, -4.0)
		_prone = false   # you don't belly-crawl in the swell
		if _climbing:
			_leave_climb()   # fell off the ladder into the sea — re-arm world collision
		if carried:
			drop_carried()
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
	var wave_y: float = Gyre.wave_height(Vector2(global_position.x, global_position.z), Gyre.water_time()) * 0.85
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
	# Breath. Your head under the swell spends air; at the surface you breathe. The deep
	# burns it faster — you can dive to see what's down there, but you're racing your lungs.
	var depth: float = wave_y - global_position.y
	var head_submerged: bool = head.global_position.y < wave_y
	if head_submerged:
		var rate: float = OXYGEN_DRAIN_DEEP if depth > DEEP_UNEASE_M else OXYGEN_DRAIN
		PlayerState.oxygen = maxf(PlayerState.oxygen - rate * delta, 0.0)
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
	var wave_y: float = Gyre.wave_height(Vector2(global_position.x, global_position.z), Gyre.water_time()) * 0.85
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

## Rebuild the in-hand visual for the selected hotbar slot. ItemVisual meshes are
## world-scale props with internal offsets, so we normalize at runtime: recenter on the
## combined AABB and uniform-scale so the largest dimension is HAND_ITEM_MAX_DIM.
func _update_held_item() -> void:
	# The hand lights track the selected slot too — refresh them whenever the hand does.
	_update_lantern()
	_update_flashlight()
	# Clear previous hand item
	for child in _hand_item.get_children():
		_hand_item.remove_child(child)
		child.queue_free()
	_held_item_id = ""

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
	if largest > 0.0001:
		container.scale = Vector3.ONE * (target / largest)
	visual.position = -combined.get_center()
	if HAND_TOOL_POSE.has(_held_item_id):
		var pose: Dictionary = HAND_TOOL_POSE[_held_item_id]
		container.rotation = pose["rot"]
		container.position += pose["off"] as Vector3
	# Half the item's longest dimension, in CONTAINER-local units (after the
	# recentre above, the visual's AABB is symmetric about the container origin).
	# hand_tip_world() uses this to find the far end of whatever is held, so a
	# line/string anchored there tracks the actual held object instead of a
	# fixed offset from the player's feet.
	_hand_reach = largest * 0.5
	_hand_reach_axis = HAND_TIP_AXIS.get(_held_item_id, Vector3(0, 0, -1))

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
