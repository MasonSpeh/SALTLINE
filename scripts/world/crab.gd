class_name GiantCrab extends Node3D
## The night threat, remade again (s16): a FREE-ROAMING giant crab that hunts the whole
## rig, not a pack of animals orbiting a spawn point.
##
## WHERE IT IS depends on the CLOCK, not on a base. By DAY the pack is under the
## waterline, wandering the submerged concrete faces of the four caisson legs (the HUD
## hint and the journal both say so, and it is where you find them if you lean over a
## rim). At DUSK, once the light is more than half gone, they start coming up. All NIGHT
## they are up on the plating, roaming — and if you are on another deck they take the
## STAIRS and come after you, wet deck (y2) to the operations lookout (y38).
##
## THE HUNT. Detection is no longer height-locked: the old code refused to notice a
## player more than 2.5 m above or below the crab, which is precisely why the pack never
## left the wet deck while you stood topside. Now a crab that senses you on a different
## level enters CLIMB and walks the real switchback in the stair tower, one flight at a
## time, to the deck you are standing on. A chase you outrun still breaks — but you have
## to actually run: walking away no longer works.
##
## LIGHT. Ordinary light does not rout them any more (owner spec: "not AS scared of
## light — only super bright light deters them"). The bar is now a real brightness
## figure in Godot light-energy units, so a lit deck or a carried lantern is nothing to
## them and only a flashlight beam held straight on them at close range pushes them off
## — and it PUSHES them off: they break contact, circle out of the beam, and come back.
## Powered LightZones and burning flares are still hard no-go volumes (Rule 7), but a
## crab no longer FORGETS you when you step into one: it closes to the edge of the pool
## and waits there, claws up.
##
## Its sound is honest: soft chitin taps ONLY while moving, near, and actually visible.

enum State { ROOST, EMERGE, PATROL, PURSUE, FLEE, GONE, CLIMB }
## CLIMB is appended LAST on purpose: tests and shot scripts store these as ints
## (beta1_shot stages GiantCrab.State.PATROL, crab_night_probe prints State.keys()[st]),
## so inserting a state mid-enum would silently renumber every one of them.

## Authored routes, injected by the spawner (BloomFauna) — every point is validated
## against the sonar scan of the rig (see s11 crab evidence table).
var roost_loop: Array = []     ## underwater cling loop on a caisson-leg face
var roost_up: Vector3 = Vector3.UP   ## the face normal that loop clings to
var emerge_path: Array = []    ## water -> rim -> deck; walked in reverse to go home
var patrol_loop: Array = []    ## wet-deck seed points; now the unstick anchor, not a route
var spawn_index: int = 0
var patrol_offset: Vector3 = Vector3.ZERO   ## fans the pack out over the roam boxes

var state: State = State.ROOST
var _wp_index: int = 0
var patrol_speed: float = 1.6
var pursue_speed: float = 4.0
var detect_radius: float = 11.0
var hunt_radius: float = 46.0
var give_up_dist: float = 26.0
var contact_radius: float = 1.45
var scare_bright: float = 2.35
var hp: float = 3.0                 ## melee hits it can take before it quits the night

const ROOST_SPEED: float = 0.5      ## slow underwater sidle
const SURFACE_CHANCE: float = 0.5   ## owner spec (2026-07-25b): each crab, each night,
## independently has a 50% chance of coming up at all — same rule the King Crab already
## rolls. A pack that is ALWAYS fully out (the s16 default) is what made six crabs read
## as more than six; some nights half the roosts stay dark and empty.
const BITE_DAMAGE: float = 0.2      ## PlayerState.life is normalized 0..1 (owner spec: -0.2/hit)
const BITE_COOLDOWN: float = 1.6    ## was 2.5 — a crab that reaches you now keeps hurting you
const BITE_SHOVE: float = 7.0
const SCARE_TIME: float = 0.55      ## seconds of BRIGHT beam before it breaks off
const SAME_LEVEL_Y: float = 2.6     ## |dy| under this and you are on its deck
const COMMIT_TIME: float = 4.0      ## seconds a chase survives you being out of range
const FLARE_DETER: float = 5.0      ## mirrors FlareStick.DETER_RADIUS
const RETREAT_TIME: float = 3.2     ## how long a light-scared crab backs off before it returns
const EMERGE_STAGGER: float = 2.0   ## seconds between pack members leaving the water.
## The pack shares six rim-lanes, so the stagger is what keeps lane-mates from climbing
## through each other — but at the old 4 s the last crab waited a full minute before it
## even set off, on top of a 60 m swim in from the west legs. Halved: the whole pack is
## committed within ~30 s of nightfall and up on the plating well inside the night.

var _resume_state: State = State.PATROL
var _recoil: float = 0.0            ## stagger timer after a strike / bite lunge
var _bite_cd: float = 0.0
var _lit_t: float = 0.0             ## how long a BRIGHT player light has been on it
var _scare_cd: float = 0.0          ## re-approach cooldown after a light scare
var _night_wait: float = 0.0        ## emergence stagger countdown
var _surface_tonight: bool = true   ## this night's 50% coin; rolled fresh on GameClock.night
var _beaten: bool = false           ## repelled to zero hp: done for this night
var _fleeing_home: bool = false     ## FLEE reached the water and is walking to roost
var _scare_retreat: bool = false    ## FLEE is a short back-off from a beam, not a rout
var _retreat_t: float = 0.0
var _commit: float = 0.0            ## pursuit grace while you are out of reach
var _sense_cd: float = 0.0          ## brief blindness after a blocked approach, so a crab
## boxed in behind a crate walks a new roam leg instead of re-acquiring you on the very
## next frame and pressing the same crate again.

# Anatomy / motion.
const KIT := preload("res://scripts/world/creature_kit.gd")
const ANIM := preload("res://scripts/world/creature_anim.gd")
const MOVE := preload("res://scripts/world/fauna_move.gd")
const MODEL_PATH := "res://assets/models/fauna/giant_crab/giant_crab.glb"
const NO_GLOW := Color(0, 0, 0)     ## naturalistic: rim/fresnel glow stays dark
var _model: Node3D
var _mats: Array = []
var _legs: Array = []               ## procedural fallback only
var _model_base_y: float = 0.0      ## grounded rest height of the generated mesh
var _gait_t: float = 0.0
var _bob_t: float = 0.0
var _last_pos: Vector3
var _speed: float = 0.0
var _resting_pose: bool = true
var _snap_t: float = 0.0            ## claw-snap timer: bite and threat snips
var _beat: float = -1.0             ## last `rate` written to the motion shader

# Surface frame — the snail's trick (FaunaMove.SurfaceCrawler was written "so the crab
# can take it later"): carry the face normal the feet are stuck to, move in its tangent
# plane, and reseat against real geometry every frame. This is what killed the float —
# the old crab walked to waypoints hand-typed at y2.6 over a y2.0 deck with no ground
# check anywhere, so the whole pack hovered 0.6 m in the air.
const CLEAR: float = 0.10           ## body-origin height above the seated surface
const SWIM_SPEED: float = 3.4       ## open-water transit — a swimming crab is not crawling
const CLIMB_SPEED: float = 2.2      ## up the flights: heavy, deliberate, audible
var up: Vector3 = Vector3.UP
var heading: Vector3 = Vector3.FORWARD
var _seated: bool = false
var _skip: Array = []               ## other animals' collision RIDs — never ground
var _sidle_sign: float = 1.0        ## which side leads the sideways scuttle

# Scuttle audio: one-shots on the footfall cadence, hard-gated on visibility.
const SCUTTLE_SHOTS := ["scuttle_a", "scuttle_b", "scuttle_c"]
const SCUTTLE_DB: float = -20.0
const SCUTTLE_RANGE: float = 10.0
var _step_accum: float = 0.0
var _rng := RandomNumberGenerator.new()

# Unstick guard: authored points are sonar-validated, but props move and players shove.
const STUCK_EPS: float = 0.05
const STUCK_TIME: float = 3.0
var _guard_pos: Vector3
var _guard_t: float = 0.0

## ================= THE RIG, AS THE CRAB KNOWS IT =====================================
##
## A LEVEL TREE. Each entry is a floor the crab can stand on, the authored polyline that
## reaches it FROM ITS PARENT, and the boxes it is free to roam once it is there. The
## climb polylines are not invented: they are the stair tower's own numbers, lifted from
## rig_builder.gd — a 9-flight parametric switchback, 4 m of rise each, odd flights
## climbing west->east in the south lane (z -2.9) and topping out in the EAST wall pocket
## (x 28.5..31), even flights east->west in the north lane (z -1.1) into the WEST pocket
## (x 21..23.5). Walking those lines IS walking the stairs.
##
## HONEST LIMITS, stated in the code because they matter to whoever reads it next:
##   * The tower branch is complete and verified against rig_builder constants: y2 -> 6 ->
##     10 -> 14 -> 18 (topside) -> 22 -> 26 -> 30 -> 34 -> 38 (ops lookout).
##   * The accommodation stack is reached only as far as DECK B, over the real boarding
##     stairs (foot x15.8 z3.4 on the topside deck, topping out on the balcony landing at
##     x8.6, y21.6 — rig_superstructure._boarding_stairs). Deck C (25.1), Deck D (28.6)
##     and the stack roof (32.1) are served ONLY by the interior ladder well, which is
##     reached across the cabin block; that route is not authored here, so a crab hunting
##     you on C/D/roof climbs to Deck B and holds at the top of the stairs.
##   * Roam boxes above the wet deck are deliberately narrow — landing pockets, the
##     topside alley and south plating, the ops floor either side of the stairwell hole.
##     They are the stretches whose clearance the rig source proves.
const L_WATER: int = 0
const L_WET: int = 1
const L_TOPSIDE: int = 5
const L_OPS: int = 10
const L_DECK_B: int = 11

const LEVELS: Array = [
	# 0 — the water. Roam boxes come from the crab's OWN cling loop (per-crab), so the
	# day pack stays on its caisson leg where the daylight tests and the journal put it.
	{"name": "water", "y": -1.0, "parent": -1, "in": [], "roam": []},
	# 1 — WET DECK. Slab x8..30, z-22..2 (rig_builder._build_wet_deck). Three boxes that
	# clear the SE caisson leg (x19..25, z-15..-9), the pump room (x10..18, z-14..-6), the
	# store room (x10..16, z-22..-16) and the tower shell (x21..31, z-6..2). The rim climb
	# into this level is the crab's own emerge_path, not a shared line.
	{"name": "wet_deck", "y": 2.0, "parent": 0, "in": [],
		"roam": [
			[Vector3(25.6, 2.0, -21.5), Vector3(29.4, 2.0, -6.9)],   # east strip, clear of the leg
			[Vector3(21.5, 2.0, -21.5), Vector3(29.4, 2.0, -15.6)],  # south strip, clear of the leg
			[Vector3(10.0, 2.0, -5.0), Vector3(20.0, 2.0, 1.0)],     # north plating, clear of the pump room
		]},
	# 2 — tower landing y6 (machinery annex door is on this pocket's shaft edge).
	{"name": "tower_6", "y": 6.0, "parent": 1,
		"in": [Vector3(23.6, 2.0, -7.2), Vector3(23.6, 2.0, -5.0), Vector3(23.5, 2.0, -3.3),
			Vector3(23.5, 2.0, -2.9), Vector3(28.5, 6.0, -2.9), Vector3(29.7, 6.0, -2.4)],
		"roam": [[Vector3(28.8, 6.0, -3.7), Vector3(30.8, 6.0, 1.7)]]},
	# 3 — tower landing y10 (breaker annex door).
	{"name": "tower_10", "y": 10.0, "parent": 2,
		"in": [Vector3(29.7, 6.0, -1.1), Vector3(28.5, 6.0, -1.1), Vector3(23.5, 10.0, -1.1),
			Vector3(22.3, 10.0, -1.6)],
		"roam": [[Vector3(21.2, 10.0, -3.7), Vector3(23.2, 10.0, 1.7)]]},
	# 4 — tower landing y14.
	{"name": "tower_14", "y": 14.0, "parent": 3,
		"in": [Vector3(22.3, 10.0, -2.9), Vector3(23.5, 10.0, -2.9), Vector3(28.5, 14.0, -2.9),
			Vector3(29.7, 14.0, -2.4)],
		"roam": [[Vector3(28.8, 14.0, -3.7), Vector3(30.8, 14.0, 1.7)]]},
	# 5 — TOPSIDE. Flight 4 tops out in the west pocket at y18 and the tower's west wall
	# carries a deck-level doorway at x21, z-0.4..1.4 — so the climb spills straight onto
	# the main deck, exactly the way the player's does.
	{"name": "topside", "y": 18.0, "parent": 4,
		"in": [Vector3(29.7, 14.0, -1.1), Vector3(28.5, 14.0, -1.1), Vector3(23.5, 18.0, -1.1),
			Vector3(22.3, 18.0, 0.2), Vector3(21.0, 18.0, 0.5), Vector3(19.3, 18.0, 0.5)],
		"roam": [
			[Vector3(-25.5, 18.0, -5.2), Vector3(19.5, 18.0, 3.2)],   # the alley, shop to tower
			[Vector3(-12.5, 18.0, -18.5), Vector3(19.5, 18.0, -6.5)], # south plating
			# The gap box is narrow on purpose: the bunkhouse ends at x-8 and the galley
			# starts at x-2, so holding the crab's CENTRE a metre off each wall line is
			# what keeps a 0.42 m-radius body from grinding down both of them.
			[Vector3(-7.0, 18.0, 4.5), Vector3(-3.0, 18.0, 17.5)],    # bunkhouse/galley gap
		]},
	# 6..9 — the tower keeps going past topside. Back in through the deck door, onto the
	# foot of flight 5, and up. These landings are not rooms; they are where a crab is
	# while it is coming for someone in the lookout.
	{"name": "tower_22", "y": 22.0, "parent": 5,
		"in": [Vector3(20.0, 18.0, 0.5), Vector3(21.0, 18.0, 0.5), Vector3(22.3, 18.0, 0.2),
			Vector3(22.6, 18.0, -2.0), Vector3(23.5, 18.0, -2.9), Vector3(28.5, 22.0, -2.9),
			Vector3(29.7, 22.0, -2.4)],
		"roam": [[Vector3(28.8, 22.0, -3.7), Vector3(30.8, 22.0, 1.7)]]},
	{"name": "tower_26", "y": 26.0, "parent": 6,
		"in": [Vector3(29.7, 22.0, -1.1), Vector3(28.5, 22.0, -1.1), Vector3(23.5, 26.0, -1.1),
			Vector3(22.3, 26.0, -1.6)],
		"roam": [[Vector3(21.2, 26.0, -3.7), Vector3(23.2, 26.0, 1.7)]]},
	{"name": "tower_30", "y": 30.0, "parent": 7,
		"in": [Vector3(22.3, 26.0, -2.9), Vector3(23.5, 26.0, -2.9), Vector3(28.5, 30.0, -2.9),
			Vector3(29.7, 30.0, -2.4)],
		"roam": [[Vector3(28.8, 30.0, -3.7), Vector3(30.8, 30.0, 1.7)]]},
	{"name": "tower_34", "y": 34.0, "parent": 8,
		"in": [Vector3(29.7, 30.0, -1.1), Vector3(28.5, 30.0, -1.1), Vector3(23.5, 34.0, -1.1),
			Vector3(22.3, 34.0, -1.6)],
		"roam": [[Vector3(21.2, 34.0, -3.7), Vector3(23.2, 34.0, 1.7)]]},
	# 10 — the OPERATIONS LOOKOUT. Flight 9 emerges at the EAST end of the floor hole
	# (hole x22.7..28.7, z-4.2..-1.6), so the arrival point is solid plate. The two roam
	# boxes are the floor north and south of that hole — nothing walks over the void.
	{"name": "ops_lookout", "y": 38.0, "parent": 9,
		"in": [Vector3(22.3, 34.0, -2.9), Vector3(23.5, 34.0, -2.9), Vector3(28.5, 38.0, -2.9),
			Vector3(29.6, 38.0, -2.9)],
		"roam": [
			[Vector3(20.8, 38.0, -7.4), Vector3(31.4, 38.0, -4.5)],
			[Vector3(20.8, 38.0, -1.2), Vector3(31.4, 38.0, 3.4)],
		]},
	# 11 — DECK B, over the real boarding stairs: foot on open topside plating at
	# (15.8, 18, 3.4), topping out on the flight's own landing at (8.6, 21.6, 3.4). The
	# landing is x6..8.6 z2.6..4.2 and the balcony it butts against is x-6..6 z2.55..5.75,
	# so the two roam boxes are exactly those two slabs held clear of their rails — the
	# region east of x6 AND north of z4.2 is open air, which is why the balcony box stops at
	# x5.6 and the landing box at z3.9. The cabin block behind the balcony is not authored,
	# so this is where a crab hunting someone on Deck C/D/roof stops and waits.
	{"name": "deck_b", "y": 21.6, "parent": 5,
		"in": [Vector3(17.2, 18.0, 3.4), Vector3(15.8, 18.0, 3.4), Vector3(8.6, 21.6, 3.4),
			Vector3(7.0, 21.6, 3.4), Vector3(5.2, 21.6, 3.9)],
		"roam": [
			[Vector3(-5.4, 21.6, 2.95), Vector3(5.6, 21.6, 5.4)],   # the balcony
			[Vector3(6.3, 21.6, 3.1), Vector3(8.2, 21.6, 3.9)],     # the stairs' landing
		]},
]

## Tower footprint (shell x21..31 z-6..2, lookout x20..32 z-8..4). A player inside it is
## hunted UP THE TOWER; anyone else above the topside deck is hunted up the stack.
const TOWER_X0: float = 20.0
const TOWER_X1: float = 32.0
const TOWER_Z0: float = -8.0
const TOWER_Z1: float = 4.0

var _level: int = L_WATER
var _roam_target: Vector3
var _roam_hold: float = 0.0
var _hunt_cd: float = 0.0           ## stops the pack from all setting off up the same flight
var _climb_path: Array = []
var _climb_i: int = 0
var _climb_to: int = L_WET
var _descending: bool = false       ## FLEE is still walking the flights back down

## Brightness model. Mirrors PlayerController's own light setup (FLASHLIGHT_ENERGY 4.0,
## spot_range 22, spot_angle 32; LANTERN_ENERGY 1.5, LANTERN_RANGE 9) so what the crab
## reacts to has the same falloff shape as what the player is actually looking at. These
## are declared here rather than read off the Light3D nodes on purpose: the flashlight's
## energy is written by PlayerController's own per-frame update, so a node read is 0.0 on
## any frame where that update has not run yet, and a predator's nerve should not depend
## on frame order.
const BEAM_ENERGY: float = 4.0
const BEAM_RANGE: float = 22.0
const BEAM_HALF_DEG: float = 32.0
const LANTERN_ENERGY: float = 1.5
const LANTERN_RANGE: float = 9.0

func _ready() -> void:
	# TUNING KEYS. crab_patrol_speed is unchanged and still read from data/tuning.json.
	# The three aggression values got NEW key names (crab_sense_radius / crab_chase_speed
	# / crab_bite_reach) because tuning.json still carries the old, far tamer numbers
	# (crab_detect_radius 6.0, crab_pursue_speed 3.8, crab_contact_radius 1.2) and reading
	# those keys would have silently reverted this whole pass to the behaviour it fixes.
	patrol_speed = PlayerState.tuning.get("crab_patrol_speed", 1.6)
	pursue_speed = PlayerState.tuning.get("crab_chase_speed", 4.4)
	detect_radius = PlayerState.tuning.get("crab_sense_radius", 11.0)
	hunt_radius = PlayerState.tuning.get("crab_hunt_radius", 46.0)
	give_up_dist = PlayerState.tuning.get("crab_give_up_dist", 26.0)
	contact_radius = PlayerState.tuning.get("crab_bite_reach", 1.45)
	scare_bright = PlayerState.tuning.get("crab_light_scare_bright", 2.35)
	_rng.seed = hash("giant_crab") + spawn_index
	_sidle_sign = 1.0 if (spawn_index % 2) == 0 else -1.0
	up = roost_up
	_build_body()
	add_to_group("hittable")     # craftable melee weapons can drive it off
	add_to_group("giant_crab")
	GameClock.dawn.connect(_on_dawn)
	GameClock.night.connect(_on_night_roll)
	_last_pos = global_position
	_guard_pos = global_position
	_night_wait = float(spawn_index) * EMERGE_STAGGER
	_roam_target = global_position
	if not roost_loop.is_empty():
		_wp_index = spawn_index % roost_loop.size()

## ---------- body ----------

func _build_body() -> void:
	# Procedural fallback body first (kept invisible under the generated mesh), then the
	# Meshy giant crab swapped in over it. Naturalistic: glow colour black, energy 0.
	var shell: Material = KIT.mat(Color(0.35, 0.42, 0.48), 0.55)      # mottled blue-grey
	var limb: Material = KIT.mat(Color(0.78, 0.32, 0.16), 0.6)       # orange-red chitin
	var pale: Material = KIT.mat(Color(0.85, 0.8, 0.68), 0.7)        # cream underside
	KIT.ball(self, Vector3(0, 0.5, 0), 0.52, shell, Vector3(1.25, 0.55, 1.0))
	KIT.ball(self, Vector3(0, 0.36, 0), 0.44, pale, Vector3(1.05, 0.3, 0.85))
	for i in range(8):
		var side: float = 1.0 if i < 4 else -1.0
		var along: float = -0.38 + (i % 4) * 0.26
		var hip := Node3D.new()
		add_child(hip)
		hip.position = Vector3(along, 0.42, side * 0.5)
		KIT.limb(hip, Vector3.ZERO, Vector3(0, 0.28, side * 0.42), 0.045, limb)
		var knee := Node3D.new()
		hip.add_child(knee)
		knee.position = Vector3(0, 0.28, side * 0.42)
		KIT.limb(knee, Vector3.ZERO, Vector3(0, -0.68, side * 0.22), 0.035, limb)
		_legs.append({"hip": hip, "knee": knee,
			"phase": (i % 4) * PI * 0.5 + (0.0 if side > 0 else PI * 0.25), "side": side})
	# The generated mesh replaces all of that visually. SCUTTLE walks the legs in a
	# metachronal wave; the glow uniform is pinned dark — this crab does not shine.
	var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 1.1, ANIM.Mode.SCUTTLE,
		0.045, 1.4, NO_GLOW)
	if not gen.is_empty():
		_model = gen["model"]
		_mats = gen["mats"]
		_ground_generated()
	# NO procedural claw overlay. An earlier pass built one here (after ANIM.replace, so
	# it stayed visible) — but the generated shell HAS its own sculpted claws, so the
	# overlay hung a second set of prism jaws in front of them: the "weird shapes
	# hovering in front of crab claws". Menace is expressed on the real mesh instead —
	# see _animate(): the body rears back and the scuttle amplitude spikes in a chase,
	# and _snap_t drives a hard lurch on the bite. (The KING crab is the exception, and
	# it builds its jointed limbs in king_crab.gd — after replace(), never before.)

## Seat a generated mesh's FEET at its parent's origin, and return the y it settled at.
## The glb's own origin sits inside the body, which was a second, independent source of
## hover on top of the waypoint bug. STATIC: the King Crab grounds the same shell.
static func ground_model(model: Node3D) -> float:
	var lowest: float = INF
	var stack: Array = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var aabb: AABB = mi.get_aabb()
		for k in range(8):
			var corner: Vector3 = aabb.get_endpoint(k)
			var local: Vector3 = model.global_transform.affine_inverse() \
				* (mi.global_transform * corner)
			lowest = minf(lowest, local.y)
	if lowest < INF:
		model.position.y -= lowest * model.scale.y
	return model.position.y

func _ground_generated() -> void:
	_model_base_y = ground_model(_model)

## ---------- fightback ----------

## Struck by a melee weapon (player_controller._melee_attack). Each hit staggers it;
## enough damage and it gives up the night and goes back over the rim into the sea.
func repel(from_pos: Vector3, damage: float) -> void:
	if state == State.GONE or state == State.FLEE:
		return
	hp -= damage
	_recoil = 0.4
	_snap_t = maxf(_snap_t, 0.35)   # claws snip back at whatever hit it
	var away: Vector3 = global_position - from_pos
	away.y = 0.0
	if away.length() > 0.05:
		global_position += away.normalized() * 0.55
		_face_toward(from_pos)      # squares up to its attacker, claws forward
	AudioDirector.play_one_shot("clang", global_position, -6.0)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hp <= 0.0:
		_beaten = true
		_start_flee()
		if hud and hud.has_method("toast"):
			hud.toast("It breaks off and drops over the rim. Gone — for tonight.")
	else:
		_resume_state = State.PATROL
		state = State.PURSUE     # faces you down, but the recoil holds it off this beat
		_commit = COMMIT_TIME
		if hud and hud.has_method("toast"):
			hud.toast("You beat it back. It rears, claws high.")

## A genuinely BRIGHT light held on it. It breaks contact and circles out of the beam —
## it does not abandon the night. Only a beating or the dawn sends it over the rim.
func _light_scare() -> void:
	_lit_t = 0.0
	_scare_cd = _rng.randf_range(8.0, 14.0)   # was 20..40: pushed back, not routed
	_recoil = 0.3
	state = State.FLEE
	_scare_retreat = true
	_retreat_t = RETREAT_TIME
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast("The beam catches it full on — it throws itself back out of the light.")

## Retreat for real: down the flights it climbed, then over the rim and home. The descent
## happens INSIDE State.FLEE rather than in State.CLIMB — soak_test asserts that a crab is
## FLEE/ROOST/GONE a second after dawn, and a crab honestly walking down from the lookout
## would otherwise have been sitting in CLIMB and failed a test for doing the right thing.
func _start_flee() -> void:
	_scare_retreat = false
	state = State.FLEE
	_fleeing_home = false
	_descending = _level > L_WET and _set_link(next_toward(_level, L_WET))
	if not _descending:
		_wp_index = maxi(emerge_path.size() - 1, 0)   # walk the emergence path backwards

## ---------- the bite ----------

func _try_bite(player: Node3D) -> void:
	if _bite_cd > 0.0:
		return
	_bite_cd = BITE_COOLDOWN
	_recoil = 0.5   # the lunge spends the crab for a beat — no stun-lock
	_snap_t = 0.6   # the claws slam shut with the hit
	PlayerState.life -= BITE_DAMAGE
	AudioDirector.play_one_shot("crab_snap", global_position, -6.0)
	# Shove: horizontal knockback away from the crab, with a little lift.
	if player is CharacterBody3D:
		var dir: Vector3 = player.global_position - global_position
		dir.y = 0.0
		if dir.length() > 0.05:
			(player as CharacterBody3D).velocity += dir.normalized() * BITE_SHOVE + Vector3.UP * 2.0
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast("The claw catches you — get clear!")

## ---------- state machine ----------

func _process(delta: float) -> void:
	_animate(delta)
	_bite_cd = maxf(_bite_cd - delta, 0.0)
	_scare_cd = maxf(_scare_cd - delta, 0.0)
	_hunt_cd = maxf(_hunt_cd - delta, 0.0)
	_sense_cd = maxf(_sense_cd - delta, 0.0)
	if _recoil > 0.0:
		_recoil -= delta
		if state != State.FLEE:
			_seat(delta)
			return
	Journal.discover_if_near(self, "creature_lamplight_crab", 20.0)
	var player: Node3D = get_tree().get_first_node_in_group("player")
	_check_light_scare(delta, player)
	_unstick_guard(delta)
	match state:
		State.GONE:
			return
		State.ROOST:
			_roost(delta)
		State.EMERGE:
			_emerge(delta)
		State.PATROL:
			_patrol(delta, player)
		State.CLIMB:
			_climb(delta)
		State.PURSUE:
			_pursue(delta, player)
		State.FLEE:
			_flee(delta, player)
	_seat(delta)

## How willing it is to be out and hunting, by phase. DAY it is under the waterline
## (canon, the HUD hint, and where the daylight tests expect the whole pack to be);
## DUSK it comes up half-committed; NIGHT is its hour; DAWN it is already heading home
## and only lashes out at what walks into it.
func _aggression() -> float:
	match GameClock.current_phase:
		GameClock.Phase.NIGHT:
			return 1.0
		GameClock.Phase.DUSK:
			return 0.65
		GameClock.Phase.DAWN:
			return 0.35
		_:
			return 0.0

## Is it time to be up on the rig? All night, and the back half of dusk — the light is
## more than half gone by then and the first of them are already over the rim.
func _wants_up() -> bool:
	if not _surface_tonight:
		return false
	if GameClock.current_phase == GameClock.Phase.NIGHT:
		return true
	return GameClock.current_phase == GameClock.Phase.DUSK and GameClock.phase_fraction() > 0.45

## The nightly coin: independent per crab, same rule the King Crab already used.
func _on_night_roll() -> void:
	_surface_tonight = _rng.randf() < SURFACE_CHANCE

## Day home: a free wander over the crab's own submerged leg face — not a lap of a
## four-point rectangle. When the light goes it heads for its emergence lane, unless it
## is beaten or freshly scared.
func _roost(delta: float) -> void:
	# ROOST means "in the water, on my leg", so say so. Without this a crab forced into
	# ROOST from outside (TestRunner parks one back on its roost) would keep the deck roam
	# target it last picked and slowly swim up out of the sea toward it.
	if _level != L_WATER:
		_level = L_WATER
		_roam_target = _pick_water_target()
	if _roam_hold > 0.0:
		_roam_hold -= delta
		_orient(delta)
	elif _step_free(_roam_target, ROOST_SPEED, delta):
		_roam_target = _pick_water_target()
		_roam_hold = _rng.randf_range(0.6, 3.0)
		if _rng.randf() < 0.35:
			_sidle_sign = -_sidle_sign   # crabs swap their leading side
	if _wants_up() and not _beaten and _scare_cd <= 0.0:
		_night_wait -= delta
		if _night_wait <= 0.0:
			state = State.EMERGE
			_wp_index = 0

## Free wander on the cling face. Grown out from the authored loop so the pack drifts
## over the WHOLE submerged face, then clamped back inside the caisson's own footprint
## (|x| 17.6..26.4, |z| 7.6..16.4, y -2.2..-0.3) so a day roost is always ON its leg and
## never adrift in open water.
func _pick_water_target() -> Vector3:
	if roost_loop.is_empty():
		return global_position
	var a: Vector3 = roost_loop[_rng.randi() % roost_loop.size()]
	var b: Vector3 = roost_loop[_rng.randi() % roost_loop.size()]
	var p: Vector3 = a.lerp(b, _rng.randf())
	# Drift along the face, in the two directions that are not the face normal.
	var t1: Vector3 = up.cross(Vector3.UP)
	if t1.length() < 0.2:
		t1 = up.cross(Vector3.FORWARD)
	t1 = t1.normalized()
	p += t1 * _rng.randf_range(-1.6, 1.6) + Vector3.UP * _rng.randf_range(-0.5, 0.5)
	var sx: float = signf(p.x) if absf(p.x) > 0.01 else 1.0
	var sz: float = signf(p.z) if absf(p.z) > 0.01 else 1.0
	p.x = sx * clampf(absf(p.x), 17.6, 26.4)
	p.z = sz * clampf(absf(p.z), 7.6, 16.4)
	p.y = clampf(p.y, -2.2, -0.3)
	return p

## The visible climb out of the sea: water -> rim -> deck, no teleporting. Direct motion
## along the authored, sonar-validated lane; the surface frame grabs the deck at the lip.
func _emerge(delta: float) -> void:
	if not _wants_up():
		_start_flee()
		return
	if _follow_path_free(emerge_path, SWIM_SPEED, delta):
		_level = L_WET
		state = State.PATROL
		_roam_target = _pick_roam_target()
		_roam_hold = 0.0

## Up on the rig: roam this level, and hunt. Sensing owns the state — roaming only fills
## the time between one sighting and the next.
func _patrol(delta: float, player: Node3D) -> void:
	if not _wants_up():
		_start_flee()    # dawn / daylight: visibly go home over the rim
		return
	# Self-heal the level. Tests and the shot scripts set `state` and `global_position`
	# directly (beta1_shot stages the whole pack on the rim), which leaves _level saying
	# "water" for a crab standing on plating — and it would then roam toward a submerged
	# leg. Read the level off where the body actually is.
	if _level == L_WATER and global_position.y > 1.0:
		_level = level_for(global_position)
		_roam_target = _pick_roam_target()
	if _sense(player):
		return
	if _roam_hold > 0.0:
		_roam_hold -= delta
		_orient(delta)
		return
	if _step_deck(_roam_target, _roam_speed(), delta):
		_roam_target = _pick_roam_target()
		# Crabs stop dead, feel around, then go again. The pause is what makes a roaming
		# animal read as an animal instead of a patrol route.
		_roam_hold = _rng.randf_range(0.4, 2.6)
		if _rng.randf() < 0.35:
			_sidle_sign = -_sidle_sign

func _roam_speed() -> float:
	return patrol_speed * (1.0 if GameClock.current_phase == GameClock.Phase.NIGHT else 0.8)

## THE FIX for "crabs don't attack and stay around their base". The old detection was
##   dy < 2.5 AND dist < 6 AND the player not standing in any powered light
## — three separate vetoes, and the height one was fatal: a crab on the wet deck (y2.6)
## is 15 m below a player on topside (y18), so it could never notice anyone who was not
## down on the plating beside it, and therefore never had a reason to leave its ring.
## Now: on its deck and in range -> PURSUE. On ANOTHER deck -> take the stairs. And a
## player standing in light is still seen and still stalked; the light only stops the
## crab from stepping INTO it (see _light_safe / _step_move).
func _sense(player: Node3D) -> bool:
	if player == null:
		return false
	var aggr: float = _aggression()
	if aggr <= 0.0 or _scare_cd > 0.0 or _sense_cd > 0.0:
		return false
	var p: Vector3 = player.global_position
	var flat: float = Vector2(p.x - global_position.x, p.z - global_position.z).length()
	var eff: float = detect_radius * aggr
	if player.has_method("detection_factor"):
		eff *= player.detection_factor()
	if absf(p.y - global_position.y) < SAME_LEVEL_Y and flat < eff:
		_resume_state = State.PATROL
		state = State.PURSUE
		_commit = COMMIT_TIME
		return true
	# A different deck. The pack does not all set off up the same flight at once — each
	# crab sits on its own cooldown, so they arrive in ones and twos over the night.
	if flat < hunt_radius and aggr >= 0.6 and _hunt_cd <= 0.0:
		var want: int = level_for(p)
		if want != _level and _begin_climb_toward(want):
			return true
		_hunt_cd = _rng.randf_range(6.0, 26.0)
	return false

func _pursue(delta: float, player: Node3D) -> void:
	if player == null or _aggression() <= 0.0:
		_start_flee()
		return
	var p: Vector3 = player.global_position
	# You changed decks. It follows you up (or down) the real stairs instead of shrugging.
	if absf(p.y - global_position.y) > SAME_LEVEL_Y:
		var want: int = level_for(p)
		if want != _level and _begin_climb_toward(want):
			return
	var d: float = global_position.distance_to(p)
	if d > give_up_dist:
		# Running away still works — but it takes a few seconds of real distance, not one
		# frame of it. Walking away (3.2 m/s against its 4.4) does not.
		_commit -= delta
		if _commit <= 0.0:
			state = _resume_state
			_roam_target = _pick_roam_target()
			_hunt_cd = _rng.randf_range(4.0, 12.0)
			return
	else:
		_commit = COMMIT_TIME
	# A true return means EITHER "arrived" OR "boxed in and gave up" — the probe step reports
	# both the same way. Arriving is the point; still being far off means something (a
	# bulkhead, a crate stack) is square in the line of approach, so it stops grinding on it
	# and roams a beat, which picks a new line in. A crab pressed against a crate for the
	# rest of the night is a crab that never reaches you.
	if _step_deck(Vector3(p.x, global_position.y, p.z), pursue_speed, delta, p) \
			and d > contact_radius * 1.8:
		state = _resume_state
		_roam_target = _pick_roam_target()
		_roam_hold = 0.3
		_sense_cd = 2.5
		return
	# Threat snips: the claws clack while it closes, before any contact.
	if _snap_t <= 0.0 and _rng.randf() < delta * 0.7:
		_snap_t = 0.3
	if d < contact_radius:
		_try_bite(player)

## Retreat. Two very different things wear the same state, because the tests and the shot
## scripts both key off State.FLEE:
##   * a BEAM push-back — break contact, circle out of the light, resume the hunt;
##   * a real rout (beaten, or the dawn) — down the levels, over the rim, home.
func _flee(delta: float, player: Node3D) -> void:
	if _scare_retreat:
		_retreat_t -= delta
		if player != null:
			var away: Vector3 = global_position - player.global_position
			away.y = 0.0
			if away.length() > 0.05:
				_step_deck(global_position + away.normalized() * 4.0, pursue_speed * 0.8, delta)
		if _retreat_t <= 0.0:
			_scare_retreat = false
			state = State.PATROL
			_roam_target = _pick_roam_target()
			_roam_hold = 0.0
		return
	if _descending:
		_walk_link(delta, CLIMB_SPEED * 1.2)     # heavier and faster going down
		if _climb_i >= _climb_path.size():
			_level = _climb_to
			_seated = false
			_descending = _level > L_WET and _set_link(next_toward(_level, L_WET))
			if not _descending:
				_wp_index = maxi(emerge_path.size() - 1, 0)
		return
	if not _fleeing_home:
		# Walk the emergence path backwards: deck -> rim -> water.
		if _wp_index < 0 or emerge_path.is_empty():
			_fleeing_home = true
			return
		if _step_free(emerge_path[_wp_index], SWIM_SPEED, delta):
			_wp_index -= 1
			if _wp_index < 0:
				_fleeing_home = true
				AudioDirector.play_one_shot("splash", global_position, -8.0)
	else:
		var home: Vector3 = roost_loop[0] if not roost_loop.is_empty() else global_position
		if _step_free(home, SWIM_SPEED * 0.7, delta):
			state = State.ROOST
			_level = L_WATER
			_wp_index = 0
			up = roost_up            # back on its leg face: cling frame restored
			_seated = false
			_roam_target = _pick_water_target()
			_night_wait = float(spawn_index) * EMERGE_STAGGER

func _on_dawn() -> void:
	_beaten = false
	_scare_retreat = false
	_night_wait = float(spawn_index) * EMERGE_STAGGER
	if state == State.PATROL or state == State.PURSUE or state == State.EMERGE \
			or state == State.CLIMB:
		_start_flee()

## ---------- climbing ----------

## Which level a world point belongs to. Inside the stair tower's footprint the answer is
## the nearest tower landing; above the topside deck and outside it, the answer is Deck B
## — the highest authored stack level (see the LEVELS note on what is NOT reachable).
## STATIC, along with next_toward / link_path / roam_point: the King Crab hunts the same
## rig, and one copy of these coordinates is the only safe number of copies.
static func level_for(p: Vector3) -> int:
	if p.y < 1.0:
		return L_WATER
	if p.y < 4.6:
		return L_WET
	var in_tower: bool = p.x > TOWER_X0 and p.x < TOWER_X1 and p.z > TOWER_Z0 and p.z < TOWER_Z1
	if in_tower:
		var best: int = L_WET
		var best_d: float = INF
		for i in range(LEVELS.size()):
			if i == L_DECK_B:
				continue   # the stack is not in the tower
			var d: float = absf(float(LEVELS[i]["y"]) - p.y)
			if d < best_d:
				best_d = d
				best = i
		return best
	if p.y < 20.5:
		return L_TOPSIDE
	return L_DECK_B

## The neighbour level to move to next on the way to `target`: the child whose subtree
## holds the target, or this level's parent when the target lies below/aside.
static func next_toward(from_l: int, target: int) -> int:
	var walk: int = target
	while walk >= 0:
		var par: int = int(LEVELS[walk]["parent"])
		if par == from_l:
			return walk
		walk = par
	return int(LEVELS[from_l]["parent"])

## ONE hop's authored polyline, `from_l` -> `to_l`, or [] when there is no authored link.
## Up: the target level's own `in` line. Down: the same line, reversed — an animal goes
## home the way it came, which is what makes a retreat readable. Always a fresh copy: the
## source arrays live in a const and reversing one in place would corrupt the rig graph.
## The only empty link is water <-> wet deck, because that one is per-animal (each crab
## has its own rim lane in emerge_path) rather than shared.
static func link_path(from_l: int, to_l: int) -> Array:
	if from_l < 0 or to_l < 0 or from_l >= LEVELS.size() or to_l >= LEVELS.size() \
			or from_l == to_l:
		return []
	if int(LEVELS[to_l]["parent"]) == from_l:
		return (LEVELS[to_l]["in"] as Array).duplicate()
	if int(LEVELS[from_l]["parent"]) == to_l:
		var down: Array = (LEVELS[from_l]["in"] as Array).duplicate()
		down.reverse()
		return down
	return []

## A random point in one of `level`'s roam boxes. Water levels have none — those belong
## to the individual animal (a cling face, a den), not to the rig.
static func roam_point(level: int, rng: RandomNumberGenerator) -> Vector3:
	if level < 0 or level >= LEVELS.size():
		return Vector3.ZERO
	var boxes: Array = LEVELS[level]["roam"]
	if boxes.is_empty():
		return Vector3.ZERO
	var b: Array = boxes[rng.randi() % boxes.size()]
	var lo: Vector3 = b[0]
	var hi: Vector3 = b[1]
	return Vector3(rng.randf_range(lo.x, hi.x), lo.y, rng.randf_range(lo.z, hi.z))

## Load the next hop into the walk buffer without touching `state`.
func _set_link(next: int) -> bool:
	var path: Array = link_path(_level, next)
	if path.is_empty():
		return false
	_climb_path = path
	_climb_i = 0
	_climb_to = next
	_stalled = 0.0
	# Unseat NOW, not on the next _seat pass: the state tick runs first, and one frame of
	# seated movement would project the step into the deck's tangent plane and cancel the
	# whole vertical component of the first waypoint — sometimes reading as "arrived".
	_seated = false
	return true

## Start the next single hop UP (or across) toward `target`. One flight at a time,
## re-evaluated on arrival, so a player who moves mid-climb re-targets the crab instead
## of leaving it to finish a stale route.
func _begin_climb_toward(target: int) -> bool:
	if target == _level or not _set_link(next_toward(_level, target)):
		return false
	state = State.CLIMB
	return true

## Walk the loaded link. Shared by the hunting CLIMB and the homeward descent inside FLEE.
func _walk_link(delta: float, speed: float) -> void:
	if _climb_i >= _climb_path.size():
		return
	var target: Vector3 = _climb_path[_climb_i]
	# Tilt into the flight: perpendicular to travel, in the vertical plane through it.
	var dir: Vector3 = target - global_position
	if dir.length() > 0.05:
		up = up.lerp(slope_up(dir.normalized(), up), clampf(delta * 3.0, 0.0, 1.0)).normalized()
	if _step_free(target, speed, delta):
		_climb_i += 1

func _climb(delta: float) -> void:
	_walk_link(delta, CLIMB_SPEED)
	if _climb_i >= _climb_path.size():
		_finish_climb()

func _finish_climb() -> void:
	_level = _climb_to
	_climb_path = []
	_seated = false
	# Arrived. If the player has moved on again, keep going without a beat of hesitation.
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player != null and _wants_up():
		var want: int = level_for(player.global_position)
		if want != _level and _begin_climb_toward(want):
			return
	state = State.PATROL
	_roam_target = _pick_roam_target()
	_roam_hold = 0.0
	_hunt_cd = _rng.randf_range(2.0, 6.0)

## The `up` a body travelling along `dir` should carry. On a stair flight (4 m of rise
## over 5 m of run — 38 degrees) this leans the shell back into the climb; on a purely
## vertical run there is no such plane, so it keeps the up it already had.
static func slope_up(dir: Vector3, fallback: Vector3) -> Vector3:
	var side: Vector3 = dir.cross(Vector3.UP)
	if side.length() < 0.15:
		return fallback
	return side.normalized().cross(dir.normalized()).normalized()

## ---------- roaming ----------

## A random point in one of this level's roam boxes, fanned by the spawner's per-crab
## offset so pack-mates on one box do not converge on the same spot.
func _pick_roam_target() -> Vector3:
	if _level == L_WATER:
		return _pick_water_target()
	var p: Vector3 = roam_point(_level, _rng)
	if p == Vector3.ZERO:
		return global_position
	return p + patrol_offset

## ---------- light ----------

## Powered light the crab will not step into: a live LightZone (Rule 7 — the lamps and
## floodlights you build are the safe deck) or a burning flare. The flare case has been
## promised in flare_stick.gd's own docstring since it was written ("its radius counts as
## light — the crab will not cross it") and nothing implemented it until now.
## STATIC so the King Crab honours exactly the same volumes.
static func light_blocked(tree: SceneTree, p: Vector3) -> bool:
	if LightZone.point_is_safe(tree, p):
		return true
	for f in tree.get_nodes_in_group("lit_flares"):
		if f is Node3D and (f as Node3D).global_position.distance_to(p) < FLARE_DETER:
			return true
	return false

func _light_safe(p: Vector3) -> bool:
	return light_blocked(get_tree(), p)

## How bright the player's held light actually is ON THIS CRAB, in light-energy units:
## energy * falloff(distance / range) * beam cone. This is the new bar. The old test was
## presence only — any beam inside 8 m and 30 degrees — so turning to look at a crab that
## was closing on you cancelled the attack outright, which is the thing the owner asked
## to be rid of. light_aimed_at() is kept as the authority on "is a held light pointed at
## me" (it owns the flashlight's switch state); brightness decides whether that matters.
## STATIC, taking the point it should measure at, so the King Crab reads the same figure
## against its own (much higher) bar without a second copy of the falloff maths.
static func light_pressure_at(tree: SceneTree, player: Node3D, eye: Vector3) -> float:
	var best: float = 0.0
	# Burning flares are real, always-energised nodes: read them straight.
	for f in tree.get_nodes_in_group("lit_flares"):
		if not (f is Node3D):
			continue
		for l in (f as Node3D).find_children("*", "OmniLight3D", true, false):
			var ol := l as OmniLight3D
			if ol == null or not ol.is_visible_in_tree():
				continue
			best = maxf(best, ol.light_energy
				* falloff(ol.global_position.distance_to(eye), ol.omni_range))
	if player == null or not player.has_method("light_aimed_at"):
		return best
	if not player.light_aimed_at(eye):
		return best
	var cam: Variant = player.get("camera")
	var src: Vector3 = (cam as Node3D).global_position if cam is Node3D \
		else player.global_position + Vector3(0, 1.5, 0)
	var d: float = src.distance_to(eye)
	match held_item():
		"flashlight":
			# A beam: full strength dead centre, nothing at the cone edge. So it has to be
			# pointed AT them, up close — not merely in the general direction.
			var fwd: Vector3 = -(cam as Node3D).global_transform.basis.z if cam is Node3D \
				else Vector3.FORWARD
			var ang: float = rad_to_deg(fwd.angle_to(eye - src))
			var cone: float = clampf((BEAM_HALF_DEG - ang) / (BEAM_HALF_DEG * 0.6), 0.0, 1.0)
			best = maxf(best, BEAM_ENERGY * falloff(d, BEAM_RANGE) * cone)
		"storm_lantern":
			# An omni pool. At its own energy it can never reach the bar at any range —
			# which is the point: carrying a lantern is not a weapon any more.
			best = maxf(best, LANTERN_ENERGY * falloff(d, LANTERN_RANGE))
	return best

static func falloff(d: float, reach: float) -> float:
	var t: float = clampf(1.0 - d / maxf(reach, 0.01), 0.0, 1.0)
	return t * t

static func held_item() -> String:
	var slot: int = PlayerState.selected_hotbar
	if slot < 0 or slot >= PlayerState.hotbar.size() or PlayerState.hotbar[slot] == null:
		return ""
	return String(PlayerState.hotbar[slot])

func _light_pressure(player: Node3D) -> float:
	return light_pressure_at(get_tree(), player, global_position + Vector3(0, 0.3, 0))

## Not gated during CLIMB on purpose: a crab halfway up a flight has nowhere to throw
## itself back to, and a mid-air retreat off a stair reads as a bug, not as fear.
func _check_light_scare(delta: float, player: Node3D) -> void:
	if state != State.PATROL and state != State.PURSUE and state != State.EMERGE:
		_lit_t = 0.0
		return
	if _light_pressure(player) >= scare_bright:
		_lit_t += delta
		if _lit_t >= SCARE_TIME:
			_light_scare()
	else:
		_lit_t = maxf(_lit_t - delta * 2.0, 0.0)

## ---------- movement: the surface frame ----------

## Deck states use the shared wall-respecting probe step (it cannot clip crates or
## bulkheads); water/climb states move directly along authored, sonar-validated points.
## Either way the SEAT pass afterwards pins the feet to real geometry along `up`.
const BODY_R: float = 0.42
## How fast the ground seat is allowed to chase the body. MUST exceed the crab's own top
## speed (pursue 4.4 m/s) or the seat falls behind and the old code teleported to catch up.
const SEAT_CATCHUP: float = 9.0
## Inside this range a stuck-crab recovery must NOT teleport — the player would see it.
const RELOCATE_HIDE_DIST: float = 45.0
const PROBE_H: float = 0.35
const STALL_GIVE_UP: float = 2.5
var _stalled: float = 0.0

## Square up to a point (attacker, prey): claws toward it, in the seated face's plane.
func _face_toward(target: Vector3) -> void:
	_orient(1.0, target)

## Orientation. With no focus the crab travels SIDEWAYS — body square across the
## heading, alternating which side leads — because that is what a crab is. With a focus
## (the player, an attacker) the body faces it claws-first while still moving.
func _orient(delta: float, focus: Variant = null) -> void:
	var fwd: Vector3
	if focus != null:
		fwd = (focus as Vector3) - global_position
	else:
		fwd = heading.rotated(up, _sidle_sign * PI * 0.5)
	fwd = fwd - up * fwd.dot(up)
	if fwd.length() < 0.01:
		return
	var want := Basis.looking_at(fwd.normalized(), up)
	global_basis = global_basis.orthonormalized().slerp(want, clampf(delta * 6.0, 0.0, 1.0))

## One movement step toward `target`. Seated, motion is confined to the surface's
## tangent plane and arrival is measured IN that plane (authored waypoint heights are
## advisory — the seat owns the real height). Unseated (open water, a flight), motion is
## free 3D. A probed step also refuses to end inside powered light: it tries to slide
## along the boundary instead, so the crab shadows you around the edge of a lit pool
## rather than forgetting you were ever there.
func _step_move(target: Vector3, speed: float, delta: float, probe: bool,
		focus: Variant = null) -> bool:
	var to_t: Vector3 = target - global_position
	var arrive: Vector3 = to_t
	if _seated:
		arrive = to_t - up * to_t.dot(up)
	if arrive.length() < (0.3 if _seated else 0.25):
		_stalled = 0.0
		return true
	var dir: Vector3 = to_t
	if _seated:
		dir = dir - up * dir.dot(up)
		if dir.length() < 0.05:
			dir = to_t          # target is off this face (leaving a roost): go direct
	dir = dir.normalized()
	heading = dir
	var step: Vector3 = dir * speed * delta
	if probe and up.y > 0.7:
		if _light_safe(global_position + step):
			# The light is a wall. Sidle along it — either tangent will do, and the one
			# that is also clear of the light wins.
			var side: Vector3 = up.cross(dir).normalized() * speed * delta
			if _light_safe(global_position + side):
				side = -side
			if _light_safe(global_position + side):
				_orient(delta, focus)
				return false     # boxed in by light: hold at the edge, claws up
			step = side
		var moved: Vector3 = MOVE.step(self, step, BODY_R, PROBE_H)
		if moved.length() < step.length() * 0.25:
			_stalled += delta
			if _stalled > STALL_GIVE_UP:
				_stalled = 0.0
				return true
		else:
			_stalled = 0.0
	else:
		global_position += step.limit_length(to_t.length())
	_orient(delta, focus)
	return false

func _step_deck(target: Vector3, speed: float, delta: float,
		focus: Variant = null) -> bool:
	return _step_move(target, speed, delta, true, focus)

func _step_free(target: Vector3, speed: float, delta: float) -> bool:
	return _step_move(target, speed, delta, false)

## The reseat — run after every state tick. Cast along -up for footing; ease `up` onto
## the found normal (rides sloped plate and curved faces); wrap over a convex edge the
## way the snail crawler does (deck rim -> rim face) by trying the old heading as the
## new up; with no footing at all, it is swimming — ease upright and let the authored
## points carry it.
func _seat(delta: float) -> void:
	# A CLIMB (and the homeward descent, which is the same walk in reverse) owns its own
	# `up` — the flight's slope. Being seated would cancel the component of the step that
	# points up the ramp: the same projection bug that once stranded the west-leg pack
	# flat against the concrete.
	if state == State.CLIMB or (state == State.FLEE and _descending):
		_seated = false
		return
	# TRANSIT IS NOT SEATED. EMERGE and FLEE cross open water, and a crab that stays
	# stuck to a face while trying to leave it just slides along the concrete: the
	# projection in _step_move cancels the component pointing away from the wall. That
	# is exactly what stranded the west-leg pack — CrabNightProbe measured crab 9 moving
	# 0.4 m in 220 s of night, and only 4 of 10 ever reaching the plating. Swimming
	# crabs move in real 3D; the seat grabs again when they touch the rim.
	if state == State.EMERGE or (state == State.FLEE and not _scare_retreat):
		_seated = false
		up = up.lerp(Vector3.UP, clampf(delta * 2.5, 0.0, 1.0)).normalized()
		return
	if _skip.is_empty():
		_skip = MOVE.kin_bodies(self)
	var lift: float = 0.55
	var drop: float = 0.95
	if not _seated:
		lift = 0.9
		drop = 1.6
	var hit: Dictionary = MOVE.surface_hit(self, global_position, up, lift, drop, _skip)
	if hit.is_empty() and _seated:
		var wrap_up: Vector3 = heading
		if wrap_up.length() > 0.5:
			var h2: Dictionary = MOVE.surface_hit(self, global_position, wrap_up,
				0.7, 1.2, _skip)
			if not h2.is_empty():
				var old_up: Vector3 = up
				up = wrap_up.normalized()
				heading = -old_up
				hit = h2
	if hit.is_empty():
		_seated = false
		up = up.lerp(Vector3.UP, clampf(delta * 2.5, 0.0, 1.0)).normalized()
		return
	var n: Vector3 = hit["normal"]
	if n.dot(up) > 0.2:
		up = up.lerp(n, clampf(delta * 7.0, 0.0, 1.0)).normalized()
	var target: Vector3 = (hit["point"] as Vector3) + up * CLEAR
	var to_t: Vector3 = target - global_position
	# SNAP ONLY WHEN GENUINELY RE-ACQUIRING A SURFACE.
	#
	# This used to also snap whenever the seat had drifted more than 1.3 m — and the seat
	# followed at 3.0 m/s while the crab's own chase speed is 4.4 m/s. So a PURSUING crab
	# outran its own ground seat every single time, drifted past the threshold, and got
	# teleported forward. Measured over a 110 s night: 36 teleport-sized steps, worst 6.43 m.
	# On screen that is the crab blinking across the deck instead of scuttling at you, which
	# is both less smooth and much less frightening.
	#
	# The follow rate now comfortably exceeds any speed a crab can move at, so the seat
	# tracks continuously and the snap is reserved for spawn and for landing after a fall.
	if not _seated:
		global_position = target
	else:
		global_position += to_t.limit_length(SEAT_CATCHUP * delta)
	_seated = true

func _follow_path_free(path: Array, speed: float, delta: float) -> bool:
	if _wp_index >= path.size():
		return true
	if _step_free(path[_wp_index], speed, delta):
		_wp_index += 1
	return _wp_index >= path.size()

func _nearest_index(points: Array) -> int:
	var best: int = 0
	var best_d: float = INF
	for i in range(points.size()):
		var d: float = global_position.distance_to(points[i])
		if d < best_d:
			best_d = d
			best = i
	return best

## Recover a pinned crab to a known-good point — WITHOUT the player watching it blink.
##
## The unstick guard is a real safety net (a crab wedged behind a crate would otherwise
## grind at a wall until dawn), but it worked by assigning global_position outright, and a
## path anchor can be many metres away: the QA probe caught single-frame steps of 9.5 m.
## A teleport is only acceptable if nobody can see it, so:
##   * far away or behind the camera -> snap, as before. Invisible, and the net stays intact.
##   * in view and close            -> DO NOT snap. Drop the current leg and pick a fresh
##     roam target, so the crab visibly turns and walks out of the pin instead. Slower to
##     recover, but it never blinks in front of you, which is the entire point.
func _relocate(to: Vector3) -> void:
	var seen: bool = false
	var p: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if p != null and global_position.distance_to(p.global_position) < RELOCATE_HIDE_DIST:
		var cam: Camera3D = p.get_node_or_null("Head/Camera3D") as Camera3D
		# No camera to test against counts as SEEN: prefer the honest slow recovery over a
		# teleport we cannot prove was hidden.
		seen = cam == null or not cam.is_position_behind(global_position)
	if seen:
		_roam_target = _pick_roam_target()
		_roam_hold = 0.0
		return
	global_position = to
	_seated = false
	up = Vector3.UP

## Runtime unstick: authored points are validated, but if the crab is pinned mid-hunt
## or mid-climb (shoved into a prop, geometry edit), free it rather than let it grind
## forever. A pinned CLIMB skips the waypoint it cannot reach — relocating it would
## teleport it off a flight, which is the one thing a visible climb must never do.
func _unstick_guard(delta: float) -> void:
	if state != State.PURSUE and state != State.EMERGE and state != State.PATROL \
			and state != State.CLIMB:
		_guard_pos = global_position
		_guard_t = 0.0
		return
	if global_position.distance_to(_guard_pos) < STUCK_EPS:
		_guard_t += delta
		if _guard_t >= STUCK_TIME:
			if state == State.CLIMB:
				_climb_i += 1
			elif state == State.EMERGE:
				if not emerge_path.is_empty():
					_relocate(emerge_path[_nearest_index(emerge_path)])
			else:
				# Back to a known-good point on this level, then a fresh roam leg.
				if _level == L_WET and not patrol_loop.is_empty():
					_relocate(patrol_loop[_nearest_index(patrol_loop)])
				_roam_target = _pick_roam_target()
				_roam_hold = 0.0
			_guard_t = 0.0
			_guard_pos = global_position
	else:
		_guard_pos = global_position
		_guard_t = 0.0

## ---------- animation ----------

## Gait is driven by REAL ground speed (no moonwalking): still = BREATHE, a slow
## resting swell; moving = SCUTTLE at a rate locked to how fast it actually travels.
## Menace shows on the mesh itself — reared back in a chase, lurching on the bite.
func _animate(delta: float) -> void:
	var moved: float = global_position.distance_to(_last_pos)
	_last_pos = global_position
	_speed = moved / maxf(delta, 0.0001)
	_gait_t += delta * clampf(_speed * 3.2, 0.6, 9.0)
	_bob_t += delta
	if _model:
		if _speed > 0.1:
			_model.position.y = _model_base_y \
				+ sin(_bob_t * 9.0) * 0.018 * clampf(_speed, 0.2, 1.5)
			_model.rotation.z = sin(_bob_t * 4.5) * 0.035
		else:
			_model.position.y = lerpf(_model.position.y, _model_base_y, delta * 3.0)
			_model.rotation.z = lerpf(_model.rotation.z, 0.0, delta * 2.0)
		var resting: bool = _speed < 0.15
		if resting != _resting_pose:
			_resting_pose = resting
			for m in _mats:
				(m as ShaderMaterial).set_shader_parameter("mode",
					ANIM.Mode.BREATHE if resting else ANIM.Mode.SCUTTLE)
		# THREE beats, and they change only when the crab's state does — resting, roaming,
		# chasing. Deliberately NOT a continuous function of speed: see _set_beat.
		if resting:
			_set_beat(0.45, 0.02)
		elif state == State.PURSUE:
			_set_beat(3.6, 0.07)
		else:
			_set_beat(1.6, 0.045)
	else:
		# Primitive fallback: procedural gait.
		for leg in _legs:
			var swing: float = sin(_gait_t + leg["phase"])
			var lift: float = maxf(sin(_gait_t + leg["phase"] + PI * 0.5), 0.0)
			(leg["hip"] as Node3D).rotation.x = swing * 0.22 * clampf(_speed, 0.15, 1.0)
			(leg["knee"] as Node3D).rotation.z = leg["side"] * lift * 0.3 * clampf(_speed, 0.15, 1.0)
	# MENACE, expressed on the real mesh. No overlay geometry: the generated shell has
	# its own claws, and hanging procedural jaws in front of them is what produced the
	# floating shapes. A pursuing crab rears back on its rear legs — claws up, the pose a
	# real crab threatens with — and _snap_t punches a hard forward lurch on the bite.
	# Both ride the model's own transform, so nothing can detach from it.
	_snap_t = maxf(_snap_t - delta, 0.0)
	if _model:
		var menace: float = 1.0 if state == State.PURSUE else 0.0
		var rear: float = -0.30 * menace
		if _snap_t > 0.0:
			rear += 0.34 * sin(_snap_t * 26.0)      # the strike itself
		_model.rotation.x = lerpf(_model.rotation.x, rear,
			clampf(delta * (16.0 if _snap_t > 0.0 else 5.0), 0.0, 1.0))
		# Reared up it also stands taller.
		_model.position.y = lerpf(_model.position.y, _model_base_y + 0.11 * menace, delta * 4.0)

## The motion shader computes t = TIME * rate + phase, so writing a NEW rate at second T
## teleports the wave's phase by T * delta_rate — at 100 s in, a 0.01 nudge is a whole
## cycle, and the animation visibly explodes. So there are exactly three rates in this
## crab's life and each is written ONCE, on the state change that earns it. The old code
## drove this every single frame off a continuous speed value, which is the hazard itself.
func _set_beat(rate: float, amp: float) -> void:
	if is_equal_approx(rate, _beat):
		return
	_beat = rate
	ANIM.drive(_mats, rate, 0.0, amp)

## ---------- audio: the jingle is dead ----------

## Soft chitin taps on the footfall cadence, and ONLY when every gate holds:
## moving, within 10 m, inside the camera frustum, and unoccluded. Any gate false ->
## complete silence. One-shots, never a loop; nothing plays on a timer.
func _physics_process(delta: float) -> void:
	if _speed > 0.3 and _audio_gate_open():
		_step_accum += delta * clampf(_speed * 1.8, 0.9, 6.0)
		if _step_accum >= 1.0:
			_step_accum = fmod(_step_accum, 1.0)
			AudioDirector.play_one_shot(SCUTTLE_SHOTS[_rng.randi() % SCUTTLE_SHOTS.size()],
				global_position, SCUTTLE_DB)
	else:
		_step_accum = 0.0

func _audio_gate_open() -> bool:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	if global_position.distance_to(player.global_position) > SCUTTLE_RANGE:
		return false
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return false
	var ear: Vector3 = global_position + Vector3(0, 0.35, 0)
	if not cam.is_position_in_frustum(ear):
		return false
	# Occlusion: a clear line from the camera to the crab, or it stays silent.
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, ear)
	if player is CollisionObject3D:
		q.exclude = [(player as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()
