class_name BloomFauna extends Node3D
## The rig's wildlife (GDD canon: the Bloom is curious, not hostile — light and life,
## never combat). Seven species, all cheap procedural geometry in the Bloom palette
## (teal / pearl glow), all keyed off GameClock phases per A6:
##   Gulls        — day flyers circling the high iron
##   JellyDrifter — night surface drifters, slow teal bells
##   Barnacles    — leg growths that pulse at night and clam up when you get close
##   LampEel      — glowing chain swimming figure-eights off the north pontoon
##   FiddlerShoal — day fish schooling under the wet deck lip
##   MantleRay    — huge slow glider that crosses over the rig at night
##   TideWorms    — dawn/dusk deck crawlers that retreat into their holes
##   GlowWorms    — night den-dwellers in the dark corners; crouch close to grab one
##   Epic4EyedWhale — four-eyed vastness that swims the night air, high and rare
##   HarborSeal   — day patrol, porpoises to breathe, watches you (befriendable)
##   LampSnail    — marble-veined lamps circling the leg bases at night (§54)
##   PyramidSnail — banded ziggurat-shelled wanderer that free-roams the whole rig
##   CorvidGull   — perched Bloom-intelligent gull that tracks the player (§26)
##   GiantCrab    — the night threat: a pool of eight, free-roaming, killable, and they
##                  climb the caisson legs and the stair tower after you
##   KingCrab     — two boss-tier giants in the deep; each rolls 50% a night to come up

const ANIMH := preload("res://scripts/world/creature_anim.gd")
## AI decimation. Preloaded by PATH, not by its class_name — the global class cache lags
## for a new file and the failure surfaces as an unrelated "Could not resolve class".
const AIB := preload("res://scripts/world/ai_budget.gd")
const CRAB := preload("res://scripts/world/crab.gd")   # by path: class cache lags new names
## Shell patterning: marble veining, spiral banding and soft flesh, all in one shader.
## See materials/shell_marble.gdshader for why the lamp snail's glow stopped being
## geometry, and BloomFauna.shell_mat() for how a mesh gets dressed in it.
const SHELL_SHADER := preload("res://materials/shell_marble.gdshader")
const TEAL := Color(0.2, 0.9, 0.85)
const DIM_TEAL := Color(0.12, 0.5, 0.48)
const PEARL := Color(0.88, 0.94, 0.92)

## THE ONE THING THAT TELLS AN ANIMAL FROM SCENERY. Every collider belonging to a living
## creature joins this group at the moment it is constructed, and nothing else ever does.
##
## It exists because "is it under the fauna root?" is not that question. This node's subtree
## carries the Bloom GROWTH — creeper-wrapped pipes, kelp stands, anemone clumps — and the
## corvids' nest alongside the animals, and those are world geometry that a body is supposed
## to stop at. ship_cat's wall ray tried the subtree walk and CatHuntProbe's burial sweep went
## from 2 mm to 65 mm, A/B'd both ways, so the walk was removed rather than tuned.
##
## Membership is declared at the two places a creature collider is BUILT: FaunaTouch, which is
## every species' interaction handle wherever it ends up parented (leg_reef spawns LampSnail
## and PyramidSnail out of this file), and GlowWorm, which is its own Interactable instead of
## carrying one. So a species added later inherits the tag by taking a FaunaTouch, and an
## untagged animal is only possible by building a collider some third way.
##
## Reach it as `BloomFauna.CREATURE_GROUP`, never through `Object.get()` — that returns null
## for a script constant and the caller then silently uses its own fallback (AGENT_TRAPS).
const CREATURE_GROUP := "creature_body"

## --- Giant crabs: a pool of EIGHT, spread around the four caisson legs --------------
## DAY: every crab clings to a submerged face of one of the 4 caisson legs (6x6 boxes at
## x=±22 z=±12 — SE fills x[19,25] z[-15,-9]) and crawls slowly UP AND DOWN it, below the
## pontoon skirt, checking back in at its own den every minute or two rather than sitting in
## it. The crab carries a snail-style surface frame (crab.gd `up` + per-frame seat), so each
## loop names the FACE NORMAL it clings to and the seat pins the feet to the real concrete:
## no more hovering at hand-typed heights. The cling loops below still name the face and the
## footprint; the DEPTH each crab works is crab.gd's (see THE DAY COLUMN there — the band
## these loops are written at turned out to be inside the skirt, where nothing can see it).
## NIGHT: they come up on a SCHEDULE, not a cue — each crab draws its own hour, weighted
## late, so early night is one or two animals and the deck keeps gaining them until dawn
## (crab.gd THE NIGHT RAMP). A crab on one of the three free-standing legs
## CLIMBS ITS OWN SUPPORT — straight up the concrete and over the topside rim, see
## _crab_leg_climbs; the SE trio (the caisson the wet deck is built through) crosses to the
## EAST rim (x~30.25, the one clean water edge) and climbs its authored lane. Either way it
## then FREE ROAMS — s16 replaced the two fixed patrol rings with roam boxes that live in
## crab.gd's level tree, and a crab that senses you on another deck climbs the stair tower
## to reach you. Waypoint heights are advisory; the seat owns the floor.
## EIGHT small crabs around the base of the rig (owner's call, 2026-07-26; was 6, was 14).
## Fourteen 1.1 m crabs on 10 cling loops meant four leg faces carried a doubled-up pair and
## the pack read as an infestation rather than a threat; six read as a threat but left the
## rig thin once crabs could be KILLED (crab.gd MAX_HP — a night's hunting can now take one
## out of the pool until the next dusk). Eight is the pool, NOT the turnout: each crab rolls
## crab.gd SURFACE_CHANCE independently every night, so a typical night puts three or four
## of them on the plating and some nights half the roosts stay dark. Eight still fits the
## ten authored cling loops one crab per face, which is what keeps every crab an individual
## you notice and track — the first EIGHT roosts are the SE leg (3, the leg by the spawn),
## the NE leg (2) and all three SW faces.
const CRAB_COUNT: int = 8
# The old patrol rings. They are no longer walked as routes: crab.gd roams boxes instead,
# and keeps these as the wet-deck UNSTICK ANCHOR — a short list of points that are known
# good to drop a pinned crab back onto.
const CRAB_PATROL_EAST: Array = [   # east corridor -> foot of the stair tower (z stays >-6.5)
	Vector3(26, 2.6, -7.0), Vector3(29, 2.6, -7.0),
	Vector3(29, 2.6, -16.0), Vector3(26, 2.6, -16.0),
]
const CRAB_PATROL_SOUTH: Array = [  # spawn/SPHL flat, south of the SE leg (z stays <-15)
	Vector3(22, 2.6, -16.0), Vector3(29, 2.6, -16.0),
	Vector3(29, 2.6, -22.0), Vector3(22, 2.6, -22.0),
]
# Emergence: climbs up the EAST rim, one depth-lane each, spaced along the whole water
# edge the player faces (z-8..-22; each lip landing x29.3 sits inboard of the rim
# bollard). Ten crabs share the six lanes; the emergence stagger keeps lane-mates apart.
const CRAB_EMERGE_Z: Array = [-8.0, -11.0, -14.0, -17.0, -20.0, -22.0]
# Day roosts: one cling loop per crab on a caisson-leg face, 3+2+3+2 around the four
# legs. Each entry names the face plane it crawls (points ~0.3 m proud — the seat pulls
# the feet onto the concrete) and the OUTWARD normal of that face as `up`.
const CRAB_ROOSTS: Array = [
	# SE leg (x19..25, z-15..-9) — the leg by the spawn, 3 crabs
	{"up": Vector3(1, 0, 0), "loop": [Vector3(25.3, -0.35, -10.0), Vector3(25.3, -0.35, -14.0),
		Vector3(25.3, -1.35, -14.0), Vector3(25.3, -1.35, -10.0)]},
	{"up": Vector3(0, 0, -1), "loop": [Vector3(24.0, -0.35, -15.3), Vector3(20.0, -0.35, -15.3),
		Vector3(20.0, -1.35, -15.3), Vector3(24.0, -1.35, -15.3)]},
	{"up": Vector3(-1, 0, 0), "loop": [Vector3(18.7, -0.35, -14.0), Vector3(18.7, -0.35, -10.0),
		Vector3(18.7, -1.35, -10.0), Vector3(18.7, -1.35, -14.0)]},
	# NE leg (x19..25, z9..15) — 2 crabs
	{"up": Vector3(1, 0, 0), "loop": [Vector3(25.3, -0.35, 10.0), Vector3(25.3, -0.35, 14.0),
		Vector3(25.3, -1.35, 14.0), Vector3(25.3, -1.35, 10.0)]},
	{"up": Vector3(0, 0, 1), "loop": [Vector3(20.0, -0.35, 15.3), Vector3(24.0, -0.35, 15.3),
		Vector3(24.0, -1.35, 15.3), Vector3(20.0, -1.35, 15.3)]},
	# SW leg (x-25..-19, z-15..-9) — 3 crabs
	{"up": Vector3(0, 0, -1), "loop": [Vector3(-20.0, -0.35, -15.3), Vector3(-24.0, -0.35, -15.3),
		Vector3(-24.0, -1.35, -15.3), Vector3(-20.0, -1.35, -15.3)]},
	{"up": Vector3(-1, 0, 0), "loop": [Vector3(-25.3, -0.35, -14.0), Vector3(-25.3, -0.35, -10.0),
		Vector3(-25.3, -1.35, -10.0), Vector3(-25.3, -1.35, -14.0)]},
	{"up": Vector3(1, 0, 0), "loop": [Vector3(-18.7, -0.35, -10.0), Vector3(-18.7, -0.35, -14.0),
		Vector3(-18.7, -1.35, -14.0), Vector3(-18.7, -1.35, -10.0)]},
	# NW leg (x-25..-19, z9..15) — 2 crabs
	{"up": Vector3(-1, 0, 0), "loop": [Vector3(-25.3, -0.35, 10.0), Vector3(-25.3, -0.35, 14.0),
		Vector3(-25.3, -1.35, 14.0), Vector3(-25.3, -1.35, 10.0)]},
	{"up": Vector3(0, 0, 1), "loop": [Vector3(-24.0, -0.35, 15.3), Vector3(-20.0, -0.35, 15.3),
		Vector3(-20.0, -1.35, 15.3), Vector3(-24.0, -1.35, 15.3)]},
]

## WHICH LOOP EACH CRAB GETS, and it is not simply the first eight. Handing them out in
## authored order (SE, SE, SE, NE, NE, SW, SW, SW, ...) filled three caissons and left the
## NW leg empty every single run — measured, not assumed: CrabLifeProbe reported the day
## spread as {SE:3, NE:2, SW:3} with nothing on the fourth leg at all. The owner's brief is
## that the dens should be "spaced out naturally around", so the loops are dealt ROUND THE
## RIG instead of down the list: one leg after another, so the first eight land two per
## caisson and a ninth or tenth crab would still spread rather than double anything up.
## The authored loops themselves are untouched; only the order they are handed out in.
const CRAB_ROOST_ORDER: Array = [0, 3, 5, 8, 1, 4, 6, 9, 2, 7]

## Build one emergence climb up the east deck rim at depth-lane z: open water beyond the
## rim (x31) -> up the rim face -> onto the deck lip (x29.3, y2.6). Walked in reverse at
## dawn / when scared, to go back over the side.
func _crab_climb(z: float) -> Array:
	return [Vector3(31.0, -0.5, z), Vector3(30.6, 0.6, z),
		Vector3(30.3, 1.7, z), Vector3(29.3, 2.6, z)]

## --- THE SUPPORT CLIMB (owner spec, 2026-07-26) ------------------------------------
## "Crabs should climb the rig supports at night." The supports are the four caisson legs,
## and rig_builder._build_structure builds each as ONE 6x6 concrete casting centred on
## (+-22, +-12) running unbroken from the seabed to y17 — the underside of the topside
## plate. That makes a leg the only surface on this rig a crab can get from the water to
## the main deck on without a single stair, and these routes are that climb: haul out at
## the leg's foot, go up the bare face, out along the underside of the deck, and over the
## rim. crab.gd walks them through its existing climb buffer (_begin_leg_climb ->
## _walk_link -> _finish_climb), so nothing here is a second movement system.
##
## THE NUMBERS ARE THE RIG'S OWN:
##   leg faces          |x| 19..25, |z| 9..15          (6x6 boxes at +-22, +-12)
##   pontoon skirts     y -3.05..0.95, x -28..28, |z| 8..16   (the feet, and the haul-out)
##   topside plate      y 17..18, x -30..30, z -20..20  (underside at 17, walking top at 18)
##   under-deck girders y ~16.9..17.85                  (hence a 16.4 traverse, below them)
## The SE leg (x19..25, z-15..-9) gets NO route: it is the one caisson the WET DECK is
## built straight through (slab x8..30, z-22..2 at y2), so its faces are interrupted and a
## climb up them would pass through the plating. Those three crabs keep the east rim lane,
## which lands them on the wet deck a few metres from the leg anyway.
const LEG_FACE_OFF: float = 0.45    ## how far the body's origin rides off the concrete
const LEG_FOOT_Y: float = 1.45      ## just clear of the pontoon top (0.95) at the foot
const LEG_UNDER_Y: float = 16.4     ## traverse height: under the deck, under the girders
const LEG_OVER_Y: float = 18.7      ## crest height going over the rim rail (rail top 18.61)
const LEG_LAND_Y: float = 18.25     ## on the plate (top 18.0; the seat owns the last 0.15)

## One support climb, as a polyline. `foot` is the haul-out on the pontoon at the leg's
## foot; `face` is the (x, z) column the crab crawls up; `edge` is the (x, z) just OUTBOARD
## of the topside rim it crosses; `land` is where it comes down on the plate.
func _leg_route(foot: Vector3, face: Vector2, edge: Vector2, land: Vector3) -> Array:
	return [
		foot,                                             # out of the sea at the leg's foot
		Vector3(face.x, LEG_FOOT_Y + 1.4, face.y),        # onto the concrete, belly to it
		Vector3(face.x, 9.0, face.y),                     # mid-climb, level with nothing
		Vector3(face.x, LEG_UNDER_Y, face.y),             # up under the deck
		Vector3(edge.x, LEG_UNDER_Y, edge.y),             # out along the underside to the rim
		Vector3(edge.x, LEG_OVER_Y, edge.y),              # up the outside face of the plate
		land,                                             # over the rail, down on the deck
	]

## Per-roost support routes, indexed the same way CRAB_ROOSTS is (a crab climbs the leg it
## slept on, up the face it slept on wherever that face is exposed). Empty = no climb.
##   3    — NE leg east face, over the EAST rim at z14: the one gap in the east rail, where
##          the broken bridge leaves the deck. It lands in the x29 lane, which runs clear
##          from z5 to z19 past the deck containers.
##   4    — NE leg north face, over the NORTH rim east of the galley (galley is x-2..14).
##   5-7  — SW leg, all three faces, over the SOUTH rim into the lane between the machine
##          shop's south wall and the south rail.
##   8, 9 — NW leg, over the NORTH rim into the matching lane north of the bunkhouse. Not
##          populated at CRAB_COUNT 8, but authored so raising the count stays safe.
##
## EVERY LANDING IS MEASURED, NOT GUESSED. z19.0 / z-19.0 / the x29 lane are the rows a
## sphere-cast sweep of the topside plate came back clear on (deck under it at exactly y18,
## nothing within a 0.45 m body radius above it) — the deck a metre either side of them is
## containers, rails and hut walls. CrabNightProbe re-runs that same sweep against these
## routes every time it runs, so a future deck-dressing pass cannot quietly wall one off.
func _crab_leg_climbs() -> Array:
	var none: Array = []
	return [
		none, none, none,                                  # 0-2: SE leg — see the note above
		_leg_route(Vector3(26.6, LEG_FOOT_Y, 13.4), Vector2(25.0 + LEG_FACE_OFF, 13.4),
			Vector2(30.7, 14.0), Vector3(29.0, LEG_LAND_Y, 14.0)),
		_leg_route(Vector3(22.0, LEG_FOOT_Y, 15.7), Vector2(22.0, 15.0 + LEG_FACE_OFF),
			Vector2(22.0, 20.7), Vector3(22.0, LEG_LAND_Y, 19.0)),
		_leg_route(Vector3(-22.0, LEG_FOOT_Y, -15.7), Vector2(-22.0, -15.0 - LEG_FACE_OFF),
			Vector2(-22.0, -20.7), Vector3(-22.0, LEG_LAND_Y, -19.0)),
		_leg_route(Vector3(-26.6, LEG_FOOT_Y, -12.0), Vector2(-25.0 - LEG_FACE_OFF, -12.0),
			Vector2(-24.5, -20.7), Vector3(-24.5, LEG_LAND_Y, -19.0)),
		_leg_route(Vector3(-17.4, LEG_FOOT_Y, -12.0), Vector2(-19.0 + LEG_FACE_OFF, -12.0),
			Vector2(-19.5, -20.7), Vector3(-19.5, LEG_LAND_Y, -19.0)),
		_leg_route(Vector3(-26.6, LEG_FOOT_Y, 12.0), Vector2(-25.0 - LEG_FACE_OFF, 12.0),
			Vector2(-24.5, 20.7), Vector3(-24.5, LEG_LAND_Y, 19.0)),
		_leg_route(Vector3(-22.0, LEG_FOOT_Y, 15.7), Vector2(-22.0, 15.0 + LEG_FACE_OFF),
			Vector2(-22.0, 20.7), Vector3(-22.0, LEG_LAND_Y, 19.0)),
	]

func _spawn_giant_crabs() -> void:
	# Ring assignment alternates so both rings stay manned all night; the offsets fan
	# the shared loops. Each nudge <=0.4 m and pointed INBOARD / away from the nearest
	# rim, so base+offset never leaves the open deck. The crab also wall-probes between
	# waypoints and the unstick guard relocates it if a prop pins it.
	var offsets: Array = [
		Vector3.ZERO, Vector3(-0.4, 0, -0.4), Vector3(-0.4, 0, 0.3),
		Vector3(0.3, 0, -0.3), Vector3(-0.4, 0, 0.4), Vector3(-0.3, 0, 0.4),
		Vector3(0.2, 0, 0.4), Vector3(-0.2, 0, -0.45), Vector3(0.4, 0, 0.2),
		Vector3(0.45, 0, -0.15), Vector3(-0.45, 0, 0.15), Vector3(0.15, 0, -0.45),
		Vector3(-0.15, 0, 0.45), Vector3(0.35, 0, 0.35),
	]
	# EIGHT crabs over 10 authored cling loops, so the modulo never wraps and no leg face
	# carries two. (The lane-mate offsets below are kept: they still fan the spawn points a
	# little, and they are what makes a higher CRAB_COUNT safe if it is ever raised again.)
	var leg_routes: Array = _crab_leg_climbs()
	for i in range(CRAB_COUNT):
		var crab: Node3D = CRAB.new()
		crab.spawn_index = i
		# One index for all three: the loop, the face normal and the support route are the
		# SAME leg face, so they have to be dealt together or a crab sleeps on one caisson
		# and climbs another.
		var rk: int = CRAB_ROOST_ORDER[i % CRAB_ROOST_ORDER.size()]
		var roost: Dictionary = CRAB_ROOSTS[rk]
		crab.roost_loop = roost["loop"]
		crab.roost_up = roost["up"]
		crab.leg_climb = leg_routes[rk]
		# Transit legs: the climb lanes are all on the EAST rim, so crabs roosting on
		# the west and north legs get authored swim waypoints routing them AROUND the
		# solid pontoon (x16..28, z-16..-8) and the deck structures instead of straight
		# through them — the emergence is direct (probe-free) motion, so without these
		# a NW crab would swim through 40m of concrete on its way to the rim. FLEE walks
		# the same list backwards, so the retreat retraces the same honest route home.
		# Every lane below stays OUTBOARD of the pontoon's plan (x -28..28, |z| 8..16): the
		# corner points at |z| 16.8 / |x| 30.5 are there so the turn from the north or south
		# face onto the east rim happens in open water instead of cutting the slab's corner.
		# crab.gd's haul-out riser hands the animal over at exactly those coordinates.
		var lead: Array = []
		if rk in [3, 4]:        # NE leg: east around the rim, outside x30.25
			lead = [Vector3(30.5, -1.2, 16.8), Vector3(30.8, -1.2, 4.0)]
		elif rk in [5, 6, 7]:   # SW leg: south of the pontoon, along the dock lane
			lead = [Vector3(-22.0, -1.2, -18.5), Vector3(0.0, -1.4, -19.8),
				Vector3(22.0, -1.2, -20.5), Vector3(30.5, -1.2, -19.0)]
		elif rk in [8, 9]:      # NW leg: across the north face, then down the east rim
			lead = [Vector3(0.0, -1.2, 16.8), Vector3(30.5, -1.2, 16.8),
				Vector3(30.8, -1.2, 4.0)]
		crab.emerge_path = lead + _crab_climb(CRAB_EMERGE_Z[i % CRAB_EMERGE_Z.size()])
		crab.patrol_loop = CRAB_PATROL_EAST if (i % 2) == 0 else CRAB_PATROL_SOUTH
		crab.patrol_offset = offsets[i % offsets.size()]
		# The corpse's touch target. Built HERE and not in crab.gd because FaunaTouch is an
		# inner class of this file and crab.gd is preloaded BY this file — a crab reaching
		# back for BloomFauna would close a script cycle. It is attached from spawn (so
		# FaunaMove.kin_bodies, which caches every fauna collider exactly once, already
		# knows about it) but crab._ready parks it on collision_layer 0: a living crab must
		# never shove the player or answer [E]. Death turns it solid; the harvest and the
		# respawn take it away again.
		var corpse := FaunaTouch.new("Dead Giant Crab", 0.9, crab.corpse_verbs, crab.corpse_act)
		crab.add_child(corpse)
		crab.corpse_touch = corpse
		add_child(crab)
		# Set down in its OWN DEN, which crab.gd picked in _ready off the loop it was just
		# handed. The authored cling point is not a legal resting place any more: it sits at
		# y -0.35, inside the pontoon skirt that sleeves all four legs, so a crab seated there
		# spends its first seconds buried in the foundations before it crawls clear. The den
		# is the same face, at this crab's own depth down the exposed column.
		crab.global_position = crab.den_seat()

## --- KING CRABS (s16): exactly TWO, and neither is a given -------------------------
## Two boss-tier animals, and that is the hard cap — the owner's spec is "at most 2 active
## at a time". They do not roost on the legs with the pack: each lies up in DEEP water well
## off the east rim (y-8, past the boat-landing lane at x34, so nothing on the rig can be
## walked into on the way in), and each independently rolls a 50% chance every night of
## hauling out to hunt. The roll lives in king_crab._on_night(); all this does is place
## them and hand each one its own haul-out lane.
##
## Lanes are the SAME rim climb the pack uses (x31 -> x29.3 over the lip), on two depth
## lanes of their own — z-9.5 and z-12.5 — so a king never comes up a lane the pack is
## queued in (pack lanes: -8, -11, -14, -17, -20, -22), and the two kings never share one.
## RETREAT walks the list backwards.
##
## Owner call, 2026-07-25b: both dens moved off the far open water (was x38, well past
## the boat-landing lane) to sit against the SE leg's own submerged foot instead — the
## leg's east face runs x19..25, so x27 clears it by a couple of metres of open water,
## same depth the far den used to lie at. The kings now rest at the base of the rig
## during the day (king_crab.gd _den) rather than lying up somewhere out in the sea.
const KING := preload("res://scripts/world/king_crab.gd")   # by path: class cache lags new files
const KING_COUNT: int = 2
## ONE KING PER CAISSON FOOT, not two on the same one.
##
## Owner, twice: "the two big crabs still just sit right next to each other all day". They
## did. Both dens were on the SE leg and differed only in z, by 3.00 m — and KingCrab's DAY
## state is an explicit hold-position, so each walks to its one authored point and stops. It
## has no territory system of its own (the s21 "give each crab its own territory" pass was
## the GIANT crabs; the kings never got one), so nothing else was ever going to separate them.
##
## Two animals this size should not be in the same sightline, so they get different legs: the
## south-east foot and the south-west one, 54 m apart across the under-rig water. Each keeps
## its own transit lane and its own climb, so their night routes do not converge either.
const KING_DENS: Array[Vector3] = [Vector3(27.0, -8.0, -9.5), Vector3(-27.0, -8.0, -12.5)]
## The outboard point each king swims to before it starts up the leg — on the same side as
## its own den, or a king would cross the whole rig to begin a climb.
const KING_RISE_X: Array[float] = [29.5, -29.5]

func _spawn_king_crabs() -> void:
	for i in range(KING_COUNT):
		var den: Vector3 = KING_DENS[i % KING_DENS.size()]
		var king: Node3D = KING.new()
		king.spawn_index = i
		king.den = den
		king.rise_path = [Vector3(KING_RISE_X[i % KING_RISE_X.size()], -3.0, den.z)] + _crab_climb(den.z)
		add_child(king)
		king.global_position = king.den

const SHIP_CAT := preload("res://scripts/world/ship_cat.gd")   # by path: class cache lags new files

func _ready() -> void:
	_spawn_giant_crabs()
	_spawn_king_crabs()
	# The one animal on this rig that is company rather than weather. It is in the bunkhouse
	# from the first minute, washing a paw, and nothing points at it — you find it or you do
	# not. See scripts/world/ship_cat.gd.
	add_child(SHIP_CAT.new())
	for i in range(5):
		add_child(Gull.new(i))
	for i in range(7):
		add_child(JellyDrifter.new(i))
	# Barnacle clusters on the inner leg faces near the waterline.
	for spec in [
		[Vector3(-19.2, 1.0, -12.0), 0.0], [Vector3(19.2, 1.2, 12.0), 180.0],
		[Vector3(-22.0, 0.8, -9.2), 90.0], [Vector3(22.0, 1.4, 9.2), -90.0],
		[Vector3(25.0, 0.9, -12.0), 180.0],
	]:
		var b := BarnacleCluster.new()
		add_child(b)
		b.global_position = spec[0]
		b.rotation.y = deg_to_rad(spec[1])
	add_child(LampEel.new())
	add_child(FiddlerShoal.new())
	add_child(MantleRay.new())
	add_child(Epic4EyedWhale.new())  # night visitor from the deep
	# New Codex species.
	for si in range(2):
		var seal := HarborSeal.new()
		seal.spawn_index = si          # day patrol + curiosity (befriendable canon);
		add_child(seal)                 # distinct phase/lane keeps the pair from overlapping
	# Lamp Snails: marble-veined shells circling the leg bases at night (§54).
	# Centres sit INBOARD of the caisson faces (the legs occupy |x| 19..25), so a 1.6 m
	# ring clears the concrete instead of sweeping through it, and on the pontoon decks
	# (top y 0.95) rather than the old y 0.3 which buried them in the slab.
	var snail_legs: Array[Vector3] = [Vector3(-17.2, 0, -12), Vector3(17.2, 0, -12),
			Vector3(-17.2, 0, 12), Vector3(17.2, 0, 12), Vector3(-10.0, 0, -12), Vector3(10.0, 0, 12)]
	for i in range(snail_legs.size()):
		add_child(LampSnail.new(i, snail_legs[i] + Vector3(0, 0.95, 0)))
	# Rust snails grazing the STEEL itself (54b) -- each works a scoured track along a
	# rail or a deck seam. Placed where the player already walks, so the amber glow and
	# the cleaned metal behind them get noticed.
	# Rust snails live in the splash zone (§54b: they eat the rig at the tide line) — never
	# high topside. Every run sits within a couple of metres of the waterline (y=0).
	# Wet deck tops out at y 2.0 and the pontoons at 0.95; the runs used to be authored
	# a few cm above both. The SW-leg run sat at x -19.0, which is exactly the caisson's
	# inboard face, so that snail crawled along the inside of the concrete.
	var graze_runs: Array = [
		# CLEAR STRETCH: this run used to be x24.6 z-18.4..-12.6, which drove the seam
		# STRAIGHT INTO the rigging bench (x24-26, z-17.5) — and its home sat in that
		# clutter too, so the snail pinballed off the bench and spun in place (measured
		# ~4.4 laps / 0.2 m net). Moved to the open plate north of the pump room, a real
		# clear seam it can actually patrol end to end.
		[Vector3(11.5, 2.0, -4.0), Vector3(19.5, 2.0, -4.0)],       # wet-deck plate (open)
		[Vector3(-17.4, 0.95, -13.4), Vector3(-17.4, 0.95, -10.6)], # SW leg splash zone
		[Vector3(13.0, 2.0, -18.2), Vector3(19.0, 2.0, -18.2)],     # wet-deck plate seam
		[Vector3(3.0, 0.95, -12.4), Vector3(9.0, 0.95, -12.4)],     # pontoon seam
	]
	for i in range(graze_runs.size()):
		add_child(RustSnail.new(i, graze_runs[i][0], graze_runs[i][1]))
	# Glass snails on the submerged plate under the wet-deck lip (54c) -- lean over the
	# rail and their gut-coils are the only thing visible down there.
	# The plate is real geometry: top face y -1.30, spanning x 10.5..22.5, z -21.5..-18.5.
	# The old bases (x 20.0-2.4i, z -14.0+1.1i) had the right DEPTH but sat out over open
	# water north of it, so three of the four hung in mid-water with nothing beneath them
	# and the fourth was riding a passing animal's touch sphere. These sit on the plate
	# with ~0.4 m of margin left over for the 0.9 m drift orbit.
	var glass_beds: Array[Vector3] = [
		Vector3(13.0, -1.3, -20.2), Vector3(15.4, -1.3, -19.8),
		Vector3(17.8, -1.3, -20.2), Vector3(20.2, -1.3, -19.8),
	]
	for i in range(glass_beds.size()):
		add_child(GlassSnail.new(i, glass_beds[i]))
	# Pyramid snails: the one gastropod with NO tie to water, so they are seeded on the
	# TOPSIDE PLATE (y18, x[-30,30] z[-20,20]) and left to walk it. These are start points,
	# not homes — each picks a fresh random heading every 16-42 s and keeps going, so where
	# you meet one has nothing to do with where it was spawned. The three points are in the
	# open lanes between the deckhouses (machine shop x[-28,-14] z[-18,-6]; bunkhouse
	# x[-28,-8] z[4,18]; galley x[-2,14] z[8,18]; rec room x[18,28] z[8,18]), and sit a
	# little proud of the plating so the crawler's first wide grounding probe seats them
	# flush on the real deck rather than trusting a hand-typed y.
	var pyramid_starts: Array[Vector3] = [
		Vector3(2.0, 18.3, -10.0),    # open mid-deck, north of the wet-deck hatch runs
		Vector3(6.0, 18.3, 0.5),      # dead centre of the plate, clear of every deckhouse
		Vector3(-6.0, 18.3, -2.0),    # west spine, clear of the machine shop
	]
	for i in range(pyramid_starts.size()):
		add_child(PyramidSnail.new(i, pyramid_starts[i]))
	# Anchor limpets welded into the splash zone (54d), near the barnacle faces.
	#
	# THREE OF THE FIVE WERE AUTHORED INSIDE SOLID CASTINGS. The caisson legs are 6x6 boxes
	# centred on (+-22, +-12) with faces at |x| 19/25 and |z| 9/15, and (24.6, 1.5, -12.4)
	# sits 0.4 m INSIDE the east face — which is the owner's "there is a barrel of anchor
	# limpets stuck there". It is a named Interactable, so the crosshair reads "Anchor
	# Limpet" off a thing you cannot see, on the SE casting the pontoon walk runs along at
	# eye height.
	#
	# Index 3 is the one the owner asked to go INTO THE WATER, and it does — but NOT at the
	# 2.6 m depth first proposed. `Gyre.trough_floor()` is the analytic deepest the sea can
	# EVER reach (-6.44 m at the shipped sea state), so anything above that line is left dry
	# in a trough, which is the opposite of the request. It goes to y -8.0 on the same
	# |x| 25.00 plane the two working limpets already use: permanently submerged, 4.1 m clear
	# of the king crab's east-face den at (25, -8, -9.5), and 4.6 m above the coral band
	# (BAND_TOP_FALLBACK -12.6).
	# The other two come out to their nearest face and stay in the splash zone where they
	# belong.
	var limpet_spots: Array[Vector3] = [Vector3(-19.0, 1.55, -11.4), Vector3(19.0, 1.7, 11.4),
			Vector3(-21.6, 1.35, -9.0), Vector3(25.0, -8.0, -13.6), Vector3(22.2, 1.25, 9.0)]
	for i in range(limpet_spots.size()):
		var lim := AnchorLimpet.new(i)
		add_child(lim)
		lim.global_position = limpet_spots[i]
	# Corvid-Gulls perched on rails, watching (§26) — and one of them steals.
	# Loose deck items vanish to a findable nest on the bunkhouse roof (F10/M14):
	# theft becomes a treasure hunt, and the nest occasionally overpays.
	var nest := LootContainer.new()
	var nest_items: Array[String] = ["sealed_tin"]
	nest.items = nest_items
	nest.display_name = "Gull Nest"
	add_child(nest)
	nest.add_to_group("gull_nest")
	nest.global_position = Vector3(-20, 21.25, 12)
	nest.build_box_visual(Vector3(0.7, 0.25, 0.7), Color(0.45, 0.38, 0.26), false, true,
		MatLib.weathered_wood())
	var twigs := CSGTorus3D.new()
	twigs.inner_radius = 0.22
	twigs.outer_radius = 0.42
	twigs.material = MatLib.weathered_wood()
	twigs.use_collision = false
	add_child(twigs)
	twigs.global_position = Vector3(-20, 21.42, 12)
	# PERCHES: an XZ each, and a y that only has to BRACKET the real surface — CorvidGull
	# probes for it (_snap_to_perch) the way the deck gulls do. All three used to be typed
	# at "rail height", 0.75 m over a rail rig_builder does not put at that XZ, so all three
	# hovered (measured: +750.0 mm each, tests/FaunaSpotProbe) and the middle one hung
	# 0.48 m off a blank bunkhouse wall.
	#
	# NOT ON THE PERIMETER RAILS, deliberately. rig_builder draws the top bar at y18.61 and
	# fences the run with one smooth collision slab whose top is y19.225 — so a bird that
	# honestly probes down onto a rail lands 615 mm above the steel you can see, which is
	# the same bug in a new place. Every spot below is a surface whose collider IS its
	# visible top (verified 0.0 mm gap, tests/FaunaFixProbe), with open sky over it:
	#   0  a tide-line drum on the wet deck, 6.0 m of clear air, over the dock walk
	#   1  the bunkhouse EAST roofline — the thief's own roof, its nest 12 m behind it
	#   2  the roof of container SLN-098 on the south deck, 2.6 m up, watching the yard
	# The rec-room roof looks like the obvious third one and is not: deck B's floor is
	# 0.28 m above it, so a bird up there is a bird in a room.
	var perches := [Vector3(26.0, 3.4, -21.4), Vector3(-8.6, 21.7, 14.0), Vector3(26.6, 21.0, -15.6)]
	for i in range(perches.size()):
		var cg := CorvidGull.new(perches[i])
		cg.thief = i == 1   # the bunkhouse-roof bird works the topside deck
		add_child(cg)
	# Glow worms — rare, edible; a den network wakes two dark corners per night.
	add_child(GlowWormColony.new())
	# Deck gulls: down among your boots, strutting and pecking — and they FLUSH when
	# you walk at them, which is the cheapest aliveness a deck can buy.
	for home in [Vector3(24.0, 2.0, -15.5), Vector3(26.5, 2.0, -19.0),
			Vector3(-3.0, 18.75, 3.5), Vector3(2.5, 18.75, 6.5)]:
		add_child(DeckGull.new(home))
	# Reef fish: mutated colour-shoals at diving depth off two legs — the reason to
	# put your head under.
	# ORBIT CENTRES ARE THE LEG CENTRES, not points on their faces. (19, -12) was the SE
	# caisson's west FACE and (22, 9) the NE leg's south face — so the old 1.2-3.2 m orbits
	# swept through the concrete on every lap and swim_clear snapped the shoal at the steel
	# twice a circuit. Centred on the legs themselves (SE 22,-12; NE 22,12), s43's 5.0-6.8 m
	# rings circled the whole pillar — and the owner still saw them hugging it ("circle
	# wider around the poles", 2026-08-06), so the rings are now 8.0-11.5 m and sit BELOW
	# the pontoon slab (see the class for both sets of numbers and what each buys).
	add_child(ReefFish.new(Vector3(22.0, 0.0, -12.0)))
	add_child(ReefFish.new(Vector3(22.0, 0.0, 12.0)))
	# The Bloom growing ON the rig: creeper-wrapped pipes in the splash zone, kelp
	# stands below the waterline, anemone clumps under the barnacle faces. Each patch
	# frees itself if its mesh hasn't been generated yet.
	var flora: Array = [
		["glow_creeper", Vector3(-19.0, 0.2, -11.6), 2.6, ANIMH.Mode.SWAY, 0.03, 0.25, 0.9],
		["glow_creeper", Vector3(19.1, 0.4, 11.6), 2.2, ANIMH.Mode.SWAY, 0.03, 0.22, 0.9],
		["glow_creeper", Vector3(24.7, 0.3, -12.3), 2.4, ANIMH.Mode.SWAY, 0.03, 0.28, 0.9],
		["glow_kelp", Vector3(-20.6, -4.2, -13.4), 4.0, ANIMH.Mode.SWAY, 0.3, 0.18, 0.7],
		["glow_kelp", Vector3(20.8, -4.2, 13.2), 3.6, ANIMH.Mode.SWAY, 0.28, 0.15, 0.7],
		["glow_kelp", Vector3(23.5, -4.0, -9.8), 3.2, ANIMH.Mode.SWAY, 0.26, 0.2, 0.7],
		["glow_kelp", Vector3(14.5, -4.2, -20.5), 3.8, ANIMH.Mode.SWAY, 0.3, 0.17, 0.7],
		["bloom_anemone", Vector3(-19.2, -0.35, -11.8), 0.9, ANIMH.Mode.CIRRI, 0.03, 0.3, 1.1],
		["bloom_anemone", Vector3(19.2, -0.5, 11.9), 0.8, ANIMH.Mode.CIRRI, 0.03, 0.33, 1.1],
		["bloom_anemone", Vector3(25.0, -0.35, -11.7), 0.9, ANIMH.Mode.CIRRI, 0.03, 0.27, 1.1],
	]
	for f in flora:
		var patch := FloraPatch.new(f[0], f[2], f[3], f[4], f[5], f[6])
		add_child(patch)
		patch.global_position = f[1]
		# Tide worms along the wet-deck tide line and out on the pontoon.
	for p in [Vector3(24.5, 2.02, -17.5), Vector3(21.5, 2.02, -19.5), Vector3(26.5, 2.02, -13.0),
			Vector3(2.0, 0.97, -12.0), Vector3(-6.0, 0.97, -11.0)]:
		var w := TideWorm.new()
		add_child(w)
		w.global_position = p

static func glow_mat(color: Color, energy: float, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.5
	return m

## A shell-pattern material on SHELL_SHADER, with `aabb` pushed in as the object-space
## window the pattern is sampled over — the shader normalises VERTEX by it, so passing
## the mesh's own bounds is what makes one marbling span exactly one shell whatever size
## it was built at. `params` sets any uniform by name (pattern_mode, vein_color, ...).
##
## Used two ways, both of them the GlassSnail precedent: dressed straight onto procedural
## geometry, and swapped onto a GENERATED model's surfaces after CreatureAnim.attach —
## ShaderMaterial carries every parameter across a shader change by name, so the baked
## PBR maps, the authored facing and the pedal motion survive the swap.
static func shell_mat(aabb: AABB, params: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHELL_SHADER
	m.set_shader_parameter("bounds_min", aabb.position)
	m.set_shader_parameter("bounds_size", aabb.size)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m

## Re-dress already-generated creature surfaces in the shell shader (the swap above),
## returning them so the species can keep a handle for its per-frame dimming.
static func reshell(mats: Array, params: Dictionary = {}) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for m in mats:
		var sm: ShaderMaterial = m
		sm.shader = SHELL_SHADER
		for k in params:
			sm.set_shader_parameter(k, params[k])
		out.append(sm)
	return out

static func is_dark_phase() -> bool:
	return GameClock.current_phase == GameClock.Phase.NIGHT \
		or GameClock.current_phase == GameClock.Phase.DUSK

## --- Snail feeding + breeding (Codex §54e): feed any CRAWLING snail (lamp/rust/glass
## — the anchor limpet never moves and keeps its own PRY -> shell mechanic) a greens
## item, and two fed snails of the SAME species within BREED_RADIUS spawn a permanent
## baby between them. Babies start at BABY_SCALE and grow to full size over GROW_HOURS
## game-hours (hang_line.gd's game-hour-per-real-second trick). COLLECT (crouch near any
## of the three species) takes the live animal for the pot as `snail_live`, which the
## galley stove sears into `escargot` (cook_stove.gd EXTRA_COOK).
const GREENS: Array[String] = ["kelp_bundle"]   # any greens item counts as feed
const BREED_RADIUS: float = 4.0
const BABY_SCALE: float = 0.4
const GROW_HOURS: float = 48.0                  # ~2 game days to reach full size
const SNAIL_GROUPS: Dictionary = {"lamp": "snail_lamp", "rust": "snail_rust",
	"glass": "snail_glass", "pyramid": "snail_pyramid"}

static func has_greens() -> bool:
	for g in GREENS:
		if PlayerState.has_item(g):
			return true
	return false

## Spend one greens item, hotbar first (mirrors every other consumable). Returns false
## (and takes nothing) when the player is carrying none.
static func consume_greens() -> bool:
	for g in GREENS:
		if PlayerState.remove_item(g):
			return true
	return false

## True while the player is crouching in reach — the deliberate gesture that means
## COLLECT instead of the standing-default GRAB/FEED/HARVEST (the same idea as
## GlowWorm's crouch-gated catch window, just steering a verb instead of a timer).
static func player_crouching(host: Node) -> bool:
	var p: Node = host.get_tree().get_first_node_in_group("player")
	return p != null and bool(p.get("crouching"))

## The other FED sibling of the same script class within `radius`, or null. "Same
## species" is the script itself — lamp/rust/glass snails never cross-breed.
static func find_breed_partner(self_node: Node3D, radius: float) -> Node3D:
	var parent: Node = self_node.get_parent()
	if parent == null:
		return null
	var script: Script = self_node.get_script()
	for sib in parent.get_children():
		if sib == self_node or not is_instance_valid(sib) or sib.get_script() != script:
			continue
		if sib.get("_fed") != true:
			continue
		if (sib as Node3D).global_position.distance_to(self_node.global_position) <= radius:
			return sib
	return null

## One in-game hour, in real seconds — hang_line.gd's clock-plan trick, reused here so
## baby growth agrees with the same day length raw fish rots by.
static func game_hour_per_sec() -> float:
	var day_sec: float = 0.0
	for phase in GameClock.phase_durations_minutes:
		day_sec += GameClock.phase_durations_minutes[phase] * 60.0
	return 24.0 / maxf(day_sec, 1.0)

## Wrap every current child of a freshly-built baby into a scaled pivot, so it reads
## small without fighting SurfaceCrawler.orient(): that assigns `host.global_basis` to a
## pure-rotation Basis every frame, which would silently strip any scale set directly on
## the crawled node itself. FaunaTouch stays a direct child (grab_snail's
## _snail_touch_solid walks get_children() looking for it), so it is excluded here.
static func shrink_to_baby(host: Node3D, factor: float) -> Node3D:
	var pivot := Node3D.new()
	host.add_child(pivot)
	for ch in host.get_children():
		if ch == pivot or ch is FaunaTouch:
			continue
		host.remove_child(ch)
		pivot.add_child(ch)
	pivot.scale = Vector3.ONE * factor
	return pivot

## --- SaveManager hooks --------------------------------------------------------------
## Every original adult's fed flag, keyed "species:idx" (idx never collides between an
## original and a baby — see the 5000+ offset in each _breed_with), plus every BABY in
## full (species + position + fed + growth): babies are not part of the deterministic
## _ready() spawn list, so they must be recreated wholesale on load.
static func snail_payload(tree: SceneTree) -> Dictionary:
	var fed: Dictionary = {}
	var babies: Array = []
	for species in SNAIL_GROUPS:
		for n in tree.get_nodes_in_group(SNAIL_GROUPS[species]):
			if not is_instance_valid(n):
				continue
			if bool(n.get("_is_baby")):
				var p: Vector3 = (n as Node3D).global_position
				babies.append({
					"species": species, "fed": bool(n.get("_fed")),
					"grow_h": float(n.get("_grow_h")),
					"pos": [p.x, p.y, p.z],
				})
			else:
				fed["%s:%d" % [species, int(n.get("_idx"))]] = bool(n.get("_fed"))
	return {"fed": fed, "babies": babies}

## Reapply fed flags to the existing (deterministic) adults, clear any babies already
## standing (a second load must not double them — restore_structures' own rule), and
## spawn every saved baby fresh at its saved position/growth.
static func snail_restore(tree: SceneTree, data: Dictionary) -> void:
	var fed: Dictionary = data.get("fed", {}) if typeof(data.get("fed")) == TYPE_DICTIONARY else {}
	var parent: Node = null
	for species in SNAIL_GROUPS:
		for n in tree.get_nodes_in_group(SNAIL_GROUPS[species]):
			if not is_instance_valid(n):
				continue
			if parent == null:
				parent = n.get_parent()
			if bool(n.get("_is_baby")):
				n.queue_free()
				continue
			var key: String = "%s:%d" % [species, int(n.get("_idx"))]
			if fed.has(key):
				n.set("_fed", bool(fed[key]))
	if parent == null:
		return
	var babies: Variant = data.get("babies", [])
	if typeof(babies) != TYPE_ARRAY:
		return
	for entry in babies:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var species: String = String(entry.get("species", ""))
		var pos_a: Variant = entry.get("pos", [])
		if not SNAIL_GROUPS.has(species) or typeof(pos_a) != TYPE_ARRAY or (pos_a as Array).size() < 3:
			continue
		var pos := Vector3(float(pos_a[0]), float(pos_a[1]), float(pos_a[2]))
		var idx: int = 5000 + (randi() % 100000)
		var baby: Node3D = null
		match species:
			"lamp":
				baby = LampSnail.new(idx, pos)
			"rust":
				baby = RustSnail.new(idx, pos, pos + Vector3(1.4, 0, 0))
			"glass":
				baby = GlassSnail.new(idx, pos)
			"pyramid":
				baby = PyramidSnail.new(idx, pos)
		if baby == null:
			continue
		baby.set("_is_baby", true)
		baby.set("_fed", bool(entry.get("fed", false)))
		baby.set("_grow_h", float(entry.get("grow_h", 0.0)))
		parent.add_child(baby)
		baby.global_position = pos

## Pick up a whole snail like a normal deck item — an actual carry of the LIVE animal.
## The snail is NOT swapped for a box: it keeps its own shell, gut-glow and pedal
## animation, is held out in front of you, and when you set it down it resumes crawling
## from wherever you put it (see SurfaceCrawler.reseat + snail_carry below). It goes into
## the same `carried` slot movable props use, so [E]/[G] sets it down and [LMB] tosses it.
## Snails are plain Node3D crawlers (never RigidBody3D — that is what lets them climb and
## hug walls), so they can't ride the PhysProp carry physics; snail_carry() moves them.
static func grab_snail(species: Node3D, player: Node3D) -> void:
	if species == null or player == null or not player.has_method("try_grab"):
		return
	species.set("_carried_by", player)
	_snail_touch_solid(species, false)   # don't let the held snail shove the player
	player.try_grab(species)

## Toggle the snail's FaunaTouch collider on/off. While carried it floats a hand's reach
## in front of the camera, exactly where the player walks — a live StaticBody there would
## shove the player around, so its collision layer is cleared until it is set back down.
static func _snail_touch_solid(species: Node3D, solid: bool) -> void:
	for ch in species.get_children():
		if ch is FaunaTouch:
			(ch as FaunaTouch).collision_layer = 1 if solid else 0

## Per-frame carry for a live snail. Call it at the top of the species' crawl step:
## returns true while the animal is being carried (the species should then skip its
## world crawl but keep animating), false otherwise. On the frame it is set down it
## re-homes the crawler at the drop point so the snail crawls on from there.
static func snail_carry(species: Node3D, crawler, delta: float) -> bool:
	var by: Variant = species.get("_carried_by")
	if by == null:
		return false
	# Dropped (set down, thrown, or the carrier vanished): resume crawling here.
	if not is_instance_valid(by) or by.get("carried") != species:
		species.set("_carried_by", null)
		_snail_touch_solid(species, true)   # grabbable again where it was set down
		if crawler != null:
			crawler.reseat(species.global_position)
		return false
	# Carried: ride a hand's reach in front of the carrier's gaze, a little below centre.
	var cam: Node = by.get_node_or_null("Head/Camera3D")
	if cam is Camera3D:
		var c: Camera3D = cam
		var target: Vector3 = c.global_position - c.global_transform.basis.z * 0.95 + Vector3(0, -0.28, 0)
		species.global_position = species.global_position.lerp(target, clampf(delta * 12.0, 0.0, 1.0))
	return true

## Drop a just-attached generated model so its lowest point sits at the host's local
## origin — the foot touches the surface instead of floating. Same trick FloraPatch
## uses; scoped to the MODEL's meshes so the hidden procedural body is ignored.
static func ground_model(host: Node3D, model: Node3D) -> void:
	if model == null:
		return
	var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	var low: float = 0.0
	var first := true
	for mi in meshes:
		var w: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		low = w.position.y if first else minf(low, w.position.y)
		first = false
	if first:
		return   # no meshes to measure
	model.position.y -= (low - host.global_position.y)

## Every fauna collision body in the world, gathered once for a crawler's ground ray.
## A creature must be ruled out as GROUND, and not just its own body: FaunaTouch is a
## StaticBody3D, so a passing fish or seal reads to the ray as solid footing. Measured:
## a glass snail was crawling on another animal's 0.45 m touch sphere at y -3.45, two
## metres under the plate it belongs on, and the grounding probe scored that as a pass.
## Call once and cache — the fauna set is built in one pass in _ready(), so the list
## never needs rebuilding, and walking it per-frame per-snail would not be cheap.
##
## THE SET IS "EVERY COLLIDER UNDER THE FAUNA ROOT", WHICH IS NOT THE SET OF ANIMALS. It also
## picks up the ship's cat's own handle (built in ship_cat.gd) and the corvids' nest, a
## LootContainer, i.e. scenery — and it MISSES the animals parented elsewhere, which is the
## trap that had a crab standing on a leg_reef snail for a day (AGENT_TRAPS, s21). Left as it
## is because every caller here is a creature ruling its own neighbourhood out of its own
## ground ray, where one extra 0.7 m box on the bunkhouse roof changes no measurement taken so
## far. A consumer that means ANIMALS should read CREATURE_GROUP instead.
static func fauna_bodies(host: Node3D) -> Array[RID]:
	var out: Array[RID] = []
	var root: Node = host
	while root != null:
		var s: Script = root.get_script()
		if s != null and String(s.resource_path).ends_with("bloom_fauna.gd"):
			break
		root = root.get_parent()
	if root == null:
		root = host   # not parented under the fauna root — at least skip ourselves
	for b in root.find_children("*", "CollisionObject3D", true, false):
		out.append((b as CollisionObject3D).get_rid())
	return out

## The y of the world surface under `p`, so a crawler rides what is actually there
## instead of a hard-coded depth. Snails were authored with fixed y offsets measured
## against geometry that has since moved: the lamp ring sat 1.05 m INSIDE the pontoon
## and every grounded snail floated ~6 cm proud of its plating. The ray starts above
## `p` so it still finds the top face when the creature has drifted inside something.
## Pass `skip` (from fauna_bodies) so live animals are never mistaken for footing.
## Returns `fallback` when nothing is underneath.
static func surface_y(host: Node3D, p: Vector3, fallback: float, up: float = 1.2,
		down: float = 2.5, skip: Array[RID] = []) -> float:
	var world: World3D = host.get_world_3d()
	if world == null:
		return fallback
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, up, 0), p - Vector3(0, down, 0))
	q.collide_with_areas = false
	q.exclude = skip if not skip.is_empty() else fauna_bodies(host)
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	return hit["position"].y if not hit.is_empty() else fallback

## The gulls' flush test (Codex threat behaviour). Track the closest the player has ever
## crept to `pos`; each time they close another ~1m inside `range_m`, roll `chance` to
## bolt. Crouch-sneaking multiplies the odds by `crouch_factor` (0.0 = the roll is
## skipped entirely). Returns [flush: bool, closest: float] — the caller stores closest.
static func gull_flush_roll(player: Node3D, pos: Vector3, closest: float,
		range_m: float, chance: float, crouch_factor: float) -> Array:
	if player == null:
		return [false, closest]
	var d: float = player.global_position.distance_to(pos)
	if d <= closest - 1.0:
		closest = d   # advanced another metre closer than ever before
		if d < range_m:
			var odds: float = chance
			if player.get("crouching") == true:
				odds *= crouch_factor
			if odds > 0.0 and randf() < odds:
				return [true, closest]
	return [false, closest]

# ---------------------------------------------------------------- Gull
class Gull extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/sea_gull/sea_gull.glb"
	var _gen_mats: Array = []
	var _idx: int
	var _t: float
	var _center: Vector3
	var _radius: float
	var _speed: float
	var _wing_l: MeshInstance3D
	var _wing_r: MeshInstance3D
	var _leave: float = 0.0   # rises when dusk hits; gulls spiral off to the horizon

	func _init(idx: int) -> void:
		_idx = idx
		_t = idx * 1.7
		_center = Vector3(2 + idx * 3.0 - 6.0, 40.0 + idx * 2.5, -14.0 + idx * 4.0)
		_radius = 10.0 + idx * 3.5
		_speed = 0.5 + idx * 0.07

	func _ready() -> void:
		var pearl: Material = BloomFauna.glow_mat(BloomFauna.PEARL, 0.08)
		var grey: Material = BloomFauna.glow_mat(Color(0.62, 0.66, 0.7), 0.04)
		# Tapered capsule body — reads as a gull, not a brick.
		var body := MeshInstance3D.new()
		var bm := CapsuleMesh.new()
		bm.radius = 0.11
		bm.height = 0.6
		bm.material = pearl
		body.mesh = bm
		add_child(body)
		body.rotation.x = deg_to_rad(90)
		# Head + neck.
		var head := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.1
		hm.height = 0.2
		hm.material = pearl
		head.mesh = hm
		add_child(head)
		head.position = Vector3(0, 0.06, -0.3)
		# Beak.
		var beak := MeshInstance3D.new()
		var km := CylinderMesh.new()
		km.top_radius = 0.005
		km.bottom_radius = 0.035
		km.height = 0.16
		km.material = BloomFauna.glow_mat(Color(0.9, 0.62, 0.15), 0.05)
		beak.mesh = km
		add_child(beak)
		beak.position = Vector3(0, 0.05, -0.42)
		beak.rotation.x = deg_to_rad(-90)
		# Fanned tail.
		var tail := MeshInstance3D.new()
		var tm := PrismMesh.new()
		tm.size = Vector3(0.26, 0.02, 0.3)
		tm.material = grey
		tail.mesh = tm
		add_child(tail)
		tail.position = Vector3(0, 0.02, 0.34)
		tail.rotation.x = deg_to_rad(180)
		_wing_l = _wing(-1, pearl, grey)
		_wing_r = _wing(1, pearl, grey)
		# Generated mesh: wings beat as it circles the high iron.
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 0.55, ANIM.Mode.FLAP, 0.06, 1.4, BloomFauna.PEARL)
		if not gen.is_empty():
			_gen_mats = gen["mats"]
			ANIM.drive(_gen_mats, 1.4, 0.12)

	func _wing(side: int, pearl: Material, grey: Material) -> MeshInstance3D:
		# Two-segment wing: inner arm + swept grey primary tips.
		var w := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(0.5, 0.025, 0.26)
		wm.material = pearl
		w.mesh = wm
		add_child(w)
		w.position = Vector3(side * 0.32, 0.05, 0)
		var tip := MeshInstance3D.new()
		var tp := PrismMesh.new()
		tp.size = Vector3(0.5, 0.02, 0.2)
		tp.material = grey
		tip.mesh = tp
		w.add_child(tip)
		tip.position = Vector3(side * 0.42, 0, 0.02)
		tip.rotation.y = deg_to_rad(-28 * side)
		return w

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		var day: bool = GameClock.current_phase == GameClock.Phase.DAY \
			or GameClock.current_phase == GameClock.Phase.DAWN
		_leave = move_toward(_leave, 0.0 if day else 1.0, delta * 0.12)
		visible = _leave < 0.98
		if not visible:
			return
		# Wingbeat tracks how hard this bird is actually flying.
		ANIM.drive(_gen_mats, 1.1 + _speed * 0.5, 0.12)
		_t += delta * _speed
		Journal.discover_if_near(self, "creature_gull", 35.0)
		var r: float = _radius + _leave * 220.0          # spiral out when leaving
		var y: float = _center.y + sin(_t * 0.9 + _idx) * 2.0 + _leave * 60.0
		var next := Vector3(_center.x + cos(_t) * r, y, _center.z + sin(_t) * r)
		var vel: Vector3 = next - global_position
		global_position = next
		if vel.length_squared() > 0.0001:
			look_at(next + vel, Vector3.UP)
		# Real bird flight: bank into the circle, and alternate flap bursts with
		# stiff-winged glides — gulls work the wind, they don't row through it.
		var gliding: bool = sin(_t * 0.31 + _idx * 1.3) > 0.15
		var flap: float = (0.1 if gliding else 0.6) * sin(_t * 9.0) + (0.12 if gliding else 0.0)
		_wing_l.rotation.z = flap
		_wing_r.rotation.z = -flap
		rotation.z = lerp_angle(rotation.z, -0.35 * signf(_speed), delta * 2.0)   # bank

# ---------------------------------------------------------- JellyDrifter
class JellyDrifter extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/jelly_drifter/jelly_drifter.glb"
	const GLOW := Color(0.30, 0.90, 0.90)
	var _gen_mats: Array = []
	var _idx: int
	var _t: float
	var _mat: StandardMaterial3D
	var _presence: float = 0.0   # 0 by day, 1 by night

	func _init(idx: int) -> void:
		_idx = idx
		_t = idx * 2.3

	var _bell: Node3D
	var _core_mat: StandardMaterial3D
	var _tentacles: Array = []   # arrays of segment pivots, whip-lagged

	func _ready() -> void:
		var kit := preload("res://scripts/world/creature_kit.gd")
		_mat = BloomFauna.glow_mat(BloomFauna.TEAL, 0.0, 0.4)
		# The bell: translucent dome over a skirt rim, with a bright organ core —
		# the classic moonjelly read, Bloom-lit from inside.
		_bell = Node3D.new()
		add_child(_bell)
		kit.ball(_bell, Vector3.ZERO, 0.42, _mat, Vector3(1.0, 0.62, 1.0))
		kit.ball(_bell, Vector3(0, -0.1, 0), 0.4, _mat, Vector3(1.06, 0.3, 1.06))   # skirt
		_core_mat = kit.glow_spot(_bell, Vector3(0, 0.02, 0), 0.16, BloomFauna.TEAL, 0.0)
		for i in range(4):   # the four-leaf organ ring
			var a: float = i * PI * 0.5
			kit.glow_spot(_bell, Vector3(cos(a) * 0.12, 0.08, sin(a) * 0.12), 0.06, BloomFauna.PEARL, 0.0)
		# Eight trailing tentacles: 3 chained segments each, lagging the drift.
		for i in range(8):
			var a: float = i * TAU / 8.0
			var root := Node3D.new()
			_bell.add_child(root)
			root.position = Vector3(cos(a) * 0.3, -0.18, sin(a) * 0.3)
			var chain: Array = [root]
			var holder: Node3D = root
			for s in range(3):
				var seg := Node3D.new()
				holder.add_child(seg)
				seg.position = Vector3(0, -0.26, 0)
				kit.ball(seg, Vector3(0, -0.12, 0), 0.028 - s * 0.007, _mat, Vector3(0.8, 4.6, 0.8))
				chain.append(seg)
				holder = seg
			_tentacles.append(chain)
		# Generated mesh: the bell pulses — the way it actually swims.
		# (Meshy auto-rigs humanoids only, so the motion is CreatureAnim's vertex shader.)
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 1.1, ANIM.Mode.PULSE, 0.08, 0.6, GLOW)
		if not gen.is_empty():
			_gen_mats = gen["mats"]
			ANIM.drive(_gen_mats, 0.6, 0.8)   # steady — no per-frame cost

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_presence = move_toward(_presence, 1.0 if BloomFauna.is_dark_phase() else 0.0, delta * 0.1)
		visible = _presence > 0.02
		_mat.emission_energy_multiplier = _presence * (1.0 + 0.4 * sin(_t * 1.1))
		_mat.albedo_color.a = _presence * 0.42
		_core_mat.emission_energy_multiplier = _presence * (1.8 + 1.4 * maxf(sin(_t * 2.2 + _idx), 0.0))
		# The bell pulse fades up with the animal instead of thrashing an invisible jelly.
		ANIM.drive(_gen_mats, 0.6 * _presence, _presence * 1.2, 0.08 * _presence)
		if not visible:
			return
		_t += delta
		Journal.discover_if_near(self, "creature_jelly_drifter", 16.0)
		var angle: float = _idx * 0.9 + _t * 0.045
		var radius: float = 15.0 + _idx * 3.2 + sin(_t * 0.2 + _idx) * 2.0
		# RIDE THE WATER, not the world origin. This ring is the file's only declared SURFACE
		# animal and was the only one that never asked Gyre anything — at low water all seven
		# glowing bells hovered about a metre up in open air, in a ring that passes the
		# wet-deck south rail, which is the first thing anyone would look at from the deck.
		var jx: float = cos(angle) * radius
		var jz: float = sin(angle) * radius
		var sea: float = Gyre.wave_height(Vector2(jx, jz), Gyre.water_time())
		# BELOW the surface, not above it. s29 correctly made this ring ride the swell but kept
		# the old flat-sea offset with its sign unchanged — and wave_height() IS the drawn
		# surface, so `sea + 0.35` put the node up to 0.60 m OVER the water and the bell's own
		# half-height lifted it further. Seven glowing jellies hovering in open air beside the
		# wet-deck rail. The offset is sized off the model: 0.55 m half-height + the 0.25 m bob,
		# so the bell rides fully submerged just under the surface where it belongs.
		global_position = Vector3(jx, sea - 0.80 + sin(_t * 0.8 + _idx) * 0.25, jz)
		# The pulse: the bell squeezes, the body surges up a beat later.
		var squeeze: float = sin(_t * 2.2 + _idx)
		_bell.scale = Vector3(1.0 - squeeze * 0.08, 1.0 + squeeze * 0.16, 1.0 - squeeze * 0.08)
		# Tentacles whip-lag behind the pulse, each segment a phase later.
		for chain in _tentacles:
			for s in range(1, chain.size()):
				(chain[s] as Node3D).rotation.x = sin(_t * 2.2 + _idx - s * 0.7) * 0.14
				(chain[s] as Node3D).rotation.z = cos(_t * 1.7 + _idx - s * 0.55) * 0.14

# -------------------------------------------------------- BarnacleCluster
class BarnacleCluster extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/barnacle_cluster/barnacle_cluster.glb"
	var _gen_mats: Array = []
	var _mat: StandardMaterial3D
	var _cirri_mat: StandardMaterial3D
	var _t: float = 0.0
	var _phase_offset: float
	var _cirri: Array[Node3D] = []   # feeding-leg fans, one pivot per shell mouth
	var _sweep: float = 0.0

	func _ready() -> void:
		_phase_offset = global_position.x * 0.7 + global_position.z * 0.3
		_mat = BloomFauna.glow_mat(BloomFauna.DIM_TEAL, 0.05)
		_cirri_mat = BloomFauna.glow_mat(Color(0.75, 0.9, 0.85), 0.4)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(global_position.x * 17.0 + global_position.z * 31.0)
		for i in range(rng.randi_range(6, 9)):
			var cone := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.015
			cm.bottom_radius = rng.randf_range(0.06, 0.14)
			cm.height = rng.randf_range(0.1, 0.24)
			cm.material = _mat
			cone.mesh = cm
			add_child(cone)
			var mouth := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.4, 0.4), 0.05)
			cone.position = mouth
			cone.rotation.x = deg_to_rad(90)   # point out of the leg face
			# Feeding cirri: a fan of fine curved legs that comb the water when the
			# barnacle is feeding, folded back into the shell when it's not.
			var pivot := Node3D.new()
			add_child(pivot)
			pivot.position = mouth + Vector3(0, 0, cm.height * 0.55)
			var legs: int = rng.randi_range(4, 6)
			for k in range(legs):
				var leg := MeshInstance3D.new()
				var lm := CylinderMesh.new()
				lm.top_radius = 0.004
				lm.bottom_radius = 0.011
				lm.height = rng.randf_range(0.12, 0.19)
				lm.material = _cirri_mat
				leg.mesh = lm
				pivot.add_child(leg)
				var spread: float = (float(k) / float(legs - 1) - 0.5) * 1.4
				leg.rotation = Vector3(deg_to_rad(90), spread, 0)
				leg.position = Vector3(sin(spread) * 0.02, 0, lm.height * 0.5)
			_cirri.append(pivot)
		# Generated mesh: the cirri stir; the cluster breathes.
		# CIRRI: the feeding sweep — they rake the water and fold back.
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 0.8, ANIM.Mode.CIRRI, 0.022, 0.55, BloomFauna.TEAL)
		if not gen.is_empty():
			_gen_mats = gen["mats"]
			ANIM.drive(_gen_mats, 0.5, 0.5)

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_t += delta
		var target: float = 0.05
		var feeding: bool = false
		if GameClock.current_phase == GameClock.Phase.NIGHT:
			Journal.discover_if_near(self, "creature_barnacle", 7.0)
			target = 0.9 + 0.5 * sin(_t * 1.3 + _phase_offset)
			feeding = true
			var player: Node3D = get_tree().get_first_node_in_group("player")
			if player and player.global_position.distance_to(global_position) < 4.5:
				target = 0.03   # they feel you coming and go dark
				feeding = false
		_mat.emission_energy_multiplier = lerpf(_mat.emission_energy_multiplier, target, delta * 2.5)
		# The generated cluster rakes the water only while feeding — clammed shut, the
		# sweep stops dead, which is the same tell as the light going out.
		ANIM.drive(_gen_mats, 0.55 if feeding else 0.0, target * 0.6, 0.022 if feeding else 0.0)
		# Cirri comb the water on a ~1.4Hz rake; snap shut when not feeding.
		var rake: float = (0.55 + 0.45 * sin(_t * 4.2 + _phase_offset)) if feeding else 0.0
		_sweep = lerpf(_sweep, rake, delta * 6.0)
		_cirri_mat.emission_energy_multiplier = lerpf(_cirri_mat.emission_energy_multiplier, 0.4 if feeding else 0.0, delta * 3.0)
		for pivot in _cirri:
			pivot.scale = Vector3(1.0, 1.0, lerpf(0.12, 1.0, _sweep))
			pivot.rotation.x = _sweep * 0.5

# ------------------------------------------------------------- LampEel
class LampEel extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/lamp_eel/lamp_eel.glb"
	const GLOW := Color(0.25, 0.95, 0.88)
	var _gen_mats: Array = []
	const SEGMENTS: int = 9
	const SPACING: float = 0.5
	var _t: float = 0.0
	var _segs: Array[Node3D] = []
	var _mats: Array[StandardMaterial3D] = []
	var _presence: float = 0.0
	var _jaw: Node3D
	var _lure_mat: StandardMaterial3D

	func _ready() -> void:
		for i in range(SEGMENTS):
			var seg := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var r: float = 0.22 - i * 0.015
			sm.radius = r
			sm.height = r * 2.0
			var m: StandardMaterial3D = BloomFauna.glow_mat(BloomFauna.TEAL, 0.0)
			sm.material = m
			_mats.append(m)
			seg.mesh = sm
			add_child(seg)
			seg.position = Vector3(-i * SPACING, 0, 0)
			if i == 0:
				_build_head(seg, m)
			_segs.append(seg)
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 4.5, ANIM.Mode.UNDULATE, 0.18, 1.6, GLOW)
		if not gen.is_empty():
			_gen_mats = gen["mats"]
			# The class swims by moving its SEGMENTS; the root stays parked. Ride the
			# head segment (look_at'd down the travel every frame) and trail behind it.
			var m: Node3D = gen["model"]
			m.reparent(_segs[0], false)
			m.position = Vector3(0, 0, 1.8)

	## A proper head on segment 0: a tapered snout over a hinged lower jaw, two
	## eyes, and a lure barbel arcing off the brow with a glowing tip. Built facing
	## -Z; the head is look_at()'d down its swim direction each frame.
	func _build_head(head: MeshInstance3D, body_mat: StandardMaterial3D) -> void:
		var snout := MeshInstance3D.new()
		var snm := SphereMesh.new()
		snm.radius = 0.19; snm.height = 0.38; snm.material = body_mat
		snout.mesh = snm
		snout.scale = Vector3(0.85, 0.7, 1.5)   # draw it forward into a muzzle
		snout.position = Vector3(0, 0.02, -0.18)
		head.add_child(snout)
		_jaw = Node3D.new()
		head.add_child(_jaw)
		_jaw.position = Vector3(0, -0.11, -0.14)
		var jaw := MeshInstance3D.new()
		var jm := SphereMesh.new()
		jm.radius = 0.15; jm.height = 0.16; jm.material = body_mat
		jaw.mesh = jm
		jaw.scale = Vector3(0.85, 0.45, 1.5)
		jaw.position = Vector3(0, 0, -0.08)
		_jaw.add_child(jaw)
		var eye_mat := BloomFauna.glow_mat(Color(0.9, 0.95, 0.7), 1.2)
		for sx in [-0.12, 0.12]:
			var eye := MeshInstance3D.new()
			var em := SphereMesh.new()
			em.radius = 0.05; em.height = 0.1; em.material = eye_mat
			eye.mesh = em
			eye.position = Vector3(sx, 0.08, -0.16)
			head.add_child(eye)
		# The lure: a slim barbel arcing forward off the brow, tipped with a light.
		var stalk := MeshInstance3D.new()
		var stm := CapsuleMesh.new()
		stm.radius = 0.012; stm.height = 0.42; stm.material = body_mat
		stalk.mesh = stm
		stalk.rotation.x = deg_to_rad(35)
		stalk.position = Vector3(0, 0.24, -0.24)
		head.add_child(stalk)
		_lure_mat = BloomFauna.glow_mat(BloomFauna.TEAL, 3.0)
		var bulb := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.05; bm.height = 0.1; bm.material = _lure_mat
		bulb.mesh = bm
		bulb.position = Vector3(0, 0.42, -0.42)
		head.add_child(bulb)
		# Generated mesh: the whole ribbon body waves; the lantern chain is its own light.
		# (Meshy auto-rigs humanoids only, so the motion is CreatureAnim's vertex shader.)

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_presence = move_toward(_presence, 1.0 if GameClock.current_phase == GameClock.Phase.NIGHT else 0.0, delta * 0.15)
		visible = _presence > 0.02
		for i in range(_mats.size()):
			_mats[i].emission_energy_multiplier = _presence * (1.8 - i * 0.17)
		if not visible:
			return
		_t += delta
		if _lure_mat:
			_lure_mat.emission_energy_multiplier = _presence * (2.4 + 0.9 * sin(_t * 1.8))
		if _jaw:
			_jaw.rotation.x = 0.14 + 0.12 * sin(_t * 0.9)   # slow gulp
		Journal.discover_if_near(_segs[0], "creature_lamp_eel", 24.0)
		# Figure-eights at the surface off the north edge, clear of the deck overhang.
		# Tracks the swell rather than a fixed y: at +0.12 on a flat sea this skimmed the
		# surface, but against 2 m of Gerstner it swam through open air over the troughs.
		var hx: float = sin(_t * 0.5) * 13.0
		var hz: float = 26.0 + sin(_t * 1.0) * 5.0
		var hsurf: float = Gyre.wave_height(Vector2(hx, hz), Gyre.water_time())
		var head := Vector3(hx, hsurf - 0.25, hz)
		var from: Vector3 = _segs[0].global_position
		_segs[0].global_position = from.lerp(head, delta * 4.0)
		var dir: Vector3 = _segs[0].global_position - from
		# Ribbon wave tracks real head speed — it never swims on the spot.
		ANIM.drive(_gen_mats, clampf(dir.length() / maxf(delta, 0.0001) * 0.5, 0.6, 3.2), 0.9)
		if dir.length() > 0.0005:
			_segs[0].look_at(_segs[0].global_position + dir, Vector3.UP)
		for i in range(1, SEGMENTS):
			var prev: Vector3 = _segs[i - 1].global_position
			var cur: Vector3 = _segs[i].global_position
			var d: Vector3 = cur - prev
			if d.length() > 0.001:
				_segs[i].global_position = prev + d.normalized() * SPACING

# ---------------------------------------------------------- FiddlerShoal
class FiddlerShoal extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/bait_fish/bait_fish.glb"
	const COUNT: int = 18
	const FISH_ID := "fish_herring"
	const REACH: float = 1.4   ## how close a hand has to be to close on a fish
	var _t: float = 0.0
	var _fish: Array[Node3D] = []
	var _gone: Array[float] = []   ## per-fish respawn countdown after a grab (0 = present)
	var _mat: StandardMaterial3D
	var _gen_mats: Array = []

	func _ready() -> void:
		_mat = BloomFauna.glow_mat(Color(0.7, 0.78, 0.8), 0.15)
		for i in range(COUNT):
			# Each fish: a tapered capsule body with a forked tail fin.
			var f := Node3D.new()
			add_child(f)
			var body := MeshInstance3D.new()
			var fm := CapsuleMesh.new()
			fm.radius = 0.035
			fm.height = 0.24
			fm.material = _mat
			body.mesh = fm
			body.rotation.x = deg_to_rad(90)
			f.add_child(body)
			var tail := MeshInstance3D.new()
			var tm := PrismMesh.new()
			tm.size = Vector3(0.11, 0.005, 0.1)
			tm.material = _mat
			tail.mesh = tm
			tail.position = Vector3(0, 0, 0.16)
			tail.rotation.x = deg_to_rad(90)
			f.add_child(tail)
			# Generated mesh, per fish — the shoal is 18 individuals, so each gets its
			# own copy (the mesh resource itself is shared by Godot, only nodes repeat).
			# Each carries a different phase so the school doesn't beat in lockstep.
			var gen: Dictionary = ANIM.replace(f, MODEL_PATH, 0.24, ANIM.Mode.UNDULATE,
				0.13, 2.6, BloomFauna.PEARL, float(i) * 0.37)
			if not gen.is_empty():
				_gen_mats.append_array(gen["mats"])
			_fish.append(f)
			_gone.append(0.0)
			# Swimming or kneeling at the waterline, you can snatch one out of the school.
			# 0.45 was too fine a target to put a crosshair on from the deck edge — these
			# are 24 cm fish on their own orbits, and the grab has to be winnable.
			var idx := i
			var touch := FaunaTouch.new("Bait Fish", 0.6,
				func() -> Array: return _grab_verbs(idx),
				func(v: String, pl: Node3D) -> void: _grab_fish(idx, pl))
			f.add_child(touch)

	## Offered to anyone with a hand actually on a fish — in the water OR kneeling at the
	## waterline. Gating on `swimming` meant the shoal passing a hand's breadth under the
	## wet-deck lip could not be touched unless you got in with it, which is the opposite
	## of the beat: the school runs shallow, and reaching down for one is the whole point.
	## Distance is the honest gate — the shoal swims at y -0.15, so from the pontoon top
	## (0.95) you have to be crouched at the very edge to be inside REACH.
	func _grab_verbs(idx: int) -> Array:
		if idx >= _fish.size() or _gone[idx] > 0.0 or not _fish[idx].visible:
			return []
		var player: Node3D = get_tree().get_first_node_in_group("player")
		if player == null:
			return []
		if player.global_position.distance_to(_fish[idx].global_position) > REACH:
			return []
		return ["GRAB"]

	func _grab_fish(idx: int, _player: Node3D) -> void:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if idx >= _fish.size() or _gone[idx] > 0.0 or not _fish[idx].visible:
			return
		if not PlayerState.add_item(FISH_ID):
			if hud and hud.has_method("toast"):
				hud.toast("Your hands are full — the fish darts off.")
			return
		_fish[idx].visible = false
		_gone[idx] = randf_range(50.0, 110.0)   # this one rejoins the school later
		Journal.discover("creature_fiddler_shoal")
		AudioDirector.play_one_shot("splash", _fish[idx].global_position, -16.0)
		if hud and hud.has_method("toast"):
			hud.toast("You close your hand in the shoal and come up with a bait-fish.")

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		var active: bool = GameClock.current_phase != GameClock.Phase.NIGHT
		visible = active   # they hide from what walks at night
		if not active:
			return
		_t += delta
		# Whole school beats together but each fish keeps its own phase offset.
		ANIM.drive(_gen_mats, 2.6, 0.15)
		# At dusk the shoal picks up a bloom-touched glint.
		_mat.emission = BloomFauna.TEAL if GameClock.current_phase == GameClock.Phase.DUSK else Color(0.7, 0.78, 0.8)
		_mat.emission_energy_multiplier = 0.7 if GameClock.current_phase == GameClock.Phase.DUSK else 0.15
		# The shoal runs SHALLOW — that is the whole point, you reach down and grab one —
		# but "shallow" was authored as a fixed y -0.15 against a flat sea. The sea now
		# has 2 m of Gerstner swell, so a fixed y left eighteen fish flapping in mid-air
		# over every trough. Ride the actual surface instead, a constant depth under it,
		# using the same waterline main.gd tests the camera against. The grab still wins
		# on the crests, when the swell lifts the school up to the pontoon lip.
		var cx: float = 19.0 + cos(_t * 0.13) * 8.0
		var cz: float = -10.0 + sin(_t * 0.19) * 7.0
		# Full Gerstner height, NOT main.gd's 0.85 camera-test fudge: 0.85 compresses the
		# wave toward zero and so lifts the school above the real surface in every trough.
		var surf: float = Gyre.wave_height(Vector2(cx, cz), Gyre.water_time())
		var center := Vector3(cx, surf - 0.45, cz)
		global_position = center
		Journal.discover_if_near(self, "creature_fiddler_shoal", 13.0)
		for i in range(COUNT):
			# A grabbed fish keeps orbiting invisibly, then pops back into formation.
			if _gone[i] > 0.0:
				_gone[i] -= delta
				if _gone[i] <= 0.0:
					_fish[i].visible = true
			var a: float = _t * 1.6 + i * (TAU / COUNT)
			var r: float = 1.2 + sin(_t * 0.9 + i) * 0.5
			var next := center + Vector3(cos(a) * r, sin(_t * 2.0 + i) * 0.1, sin(a) * r * 0.7)
			# They shoal under the wet-deck lip and around the legs — keep them out of the steel.
			next = FaunaMove.swim_clear(_fish[i], _fish[i].global_position, next, 0.2)["pos"]
			var vel: Vector3 = next - _fish[i].global_position
			_fish[i].global_position = next
			if vel.length_squared() > 0.0001:
				_fish[i].look_at(next + vel, Vector3.UP)

# ------------------------------------------------------------ MantleRay
class MantleRay extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/mantle_ray/mantle_ray.glb"
	const GLOW := Color(0.25, 0.95, 0.88)
	var _gen_mats: Array = []
	var _t: float = 0.0
	var _flying: bool = false
	var _from: Vector3
	var _to: Vector3
	var _progress: float = 0.0
	var _cooldown: float = 25.0    # first pass comes fairly soon into the night

	var _wing_sections: Array = []   # [{pivot, side, idx}] — the traveling wave

	func _ready() -> void:
		visible = false
		var kit := preload("res://scripts/world/creature_kit.gd")
		var hide_mat := kit.mat(Color(0.1, 0.14, 0.16), 0.6)
		var belly := kit.mat(Color(0.55, 0.62, 0.62), 0.65)
		# Body: a smooth diamond mass with a pale underside and cephalic fins.
		kit.ball(self, Vector3.ZERO, 1.2, hide_mat, Vector3(1.1, 0.32, 2.6))
		kit.ball(self, Vector3(0, -0.14, 0.2), 1.05, belly, Vector3(0.95, 0.18, 2.2))
		for side in [-1.0, 1.0]:
			kit.fin(self, Vector3(side * 0.5, -0.05, -2.9), Vector3(0.35, 0.15, 1.0), hide_mat,
				Vector3(0, 0, -20 * side))
		# Tail filament.
		kit.ball(self, Vector3(0, 0.05, 3.6), 0.5, hide_mat, Vector3(0.12, 0.08, 2.2))
		# Wings: three chained sections per side — flapped with a phase offset so
		# the whole span undulates like fabric instead of hinging like a door.
		for side in [-1.0, 1.0]:
			var holder: Node3D = self
			var attach := Vector3(side * 0.9, 0, 0)
			for s in range(3):
				var pivot := Node3D.new()
				holder.add_child(pivot)
				pivot.position = attach
				var mi := MeshInstance3D.new()
				var wm := BoxMesh.new()
				wm.size = Vector3(1.6, 0.14 - s * 0.03, 4.6 - s * 1.2)
				wm.material = hide_mat
				mi.mesh = wm
				pivot.add_child(mi)
				mi.position = Vector3(side * 0.8, 0, 0)
				_wing_sections.append({"pivot": pivot, "side": side, "idx": s})
				holder = pivot
				attach = Vector3(side * 1.6, 0, 0)
		# Bloom speckles under the wings — the give-away glow overhead.
		var rng := RandomNumberGenerator.new()
		rng.seed = 7717
		for i in range(14):
			kit.glow_spot(self, Vector3(rng.randf_range(-3.2, 3.2), -0.28, rng.randf_range(-2.6, 2.6)),
				0.09, BloomFauna.TEAL, 2.2)
		# Generated mesh: the wings beat; edge patterns burn through the dark.
		# (Meshy auto-rigs humanoids only, so the motion is CreatureAnim's vertex shader.)
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 6.0, ANIM.Mode.WING, 0.14, 0.45, GLOW)
		if not gen.is_empty():
			_gen_mats = gen["mats"]
			ANIM.drive(_gen_mats, 0.45, 0.5)   # steady — no per-frame cost

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_t += delta
		if not _flying:
			if GameClock.current_phase == GameClock.Phase.NIGHT:
				_cooldown -= delta
				if _cooldown <= 0.0:
					_begin_pass()
			return
		# Wings beat only on the crossing — parked, the animal is not in the sky at all.
		ANIM.drive(_gen_mats, 0.45, 0.5)
		_progress += delta / 45.0    # one slow crossing takes 45s
		if _progress >= 1.0:
			_flying = false
			visible = false
			_cooldown = randf_range(90.0, 150.0)
			return
		var pos: Vector3 = _from.lerp(_to, _progress)
		pos.y += sin(_progress * PI) * -6.0
		Journal.discover_if_near(self, "creature_mantle_ray", 90.0)   # dips lowest right over the deck
		# Reading the roof tally AND seeing the Mantle yourself closes the loop: "The Count".
		if Journal.discovered.has("creature_mantle_ray") and Journal.read_logs.has("roof_mark"):
			Journal.discover("codex_the_count")
		global_position = pos
		look_at(pos + (_to - _from).normalized(), Vector3.UP)
		# The undulation: each wing section a phase behind the last — a wave
		# traveling out along the span, the way a real mantle swims.
		for w in _wing_sections:
			(w["pivot"] as Node3D).rotation.z = w["side"] * sin(_t * 1.3 - w["idx"] * 0.85) * 0.24

	func _begin_pass() -> void:
		_flying = true
		visible = true
		_progress = 0.0
		var angle: float = randf_range(0, TAU)
		var dir := Vector3(cos(angle), 0, sin(angle))
		_from = -dir * 180.0 + Vector3(0, randf_range(38.0, 50.0), 0)
		_to = dir * 180.0 + Vector3(0, randf_range(38.0, 50.0), 0)
		AudioDirector.play_one_shot("groan", global_position, -8.0)   # a vast, soft call

# ------------------------------------------------------------- TideWorm
class TideWorm extends Node3D:
	## A burrow worm on the tide line: up at dawn and dusk, gone the rest of the time, and
	## gone INSTANTLY if it feels you coming.
	##
	## OWNER BUG 2026-07-30: "there are weird grubs on the wet deck that dont move and player
	## cant interact with". Both halves were one fault. When a real tide_worm.glb landed, the
	## whole emerge/retract machine below went on driving `_body` — the four procedural
	## segments — while CreatureAnim.replace() hid those and parented the GENERATED mesh to the
	## host instead. So the visible animal was never scaled, never hidden, never swayed and
	## never retracted: measured (tests/FaunaBugsProbe) as 6 meshes of which exactly 1 visible,
	## a 0.32 x 0.13 m body sitting on the plating at all five spots, `_emerge` 0.000 and
	## `_body.visible` false, i.e. the code believed it was fully underground. And because the
	## per-frame drive was `rate = 1.1 * _emerge`, at _emerge 0 the vertex shader's beat was
	## multiplied to ZERO — a frozen grub, all day, every day. Fixed by giving the generated
	## mesh the same retract the procedural body always had (it SINKS into the plate, which is
	## 0.5 m of solid checker plate under it, rather than squashing) and by holding the wave
	## rate constant and spending the emergence on AMPLITUDE — `rate` is a time multiplier in
	## creature_swim.gdshader, so writing it per frame teleports the wave (see GliderRay).
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/tide_worm/tide_worm.glb"
	## Set once and never driven — see the note above and creature_swim.gdshader's `rate`.
	const RIPPLE_HZ: float = 1.1
	## How close you get before it feels the plate ring and goes. Crouching halves its senses,
	## the same bargain the glow worm offers: move slowly and you get to watch one.
	const SPOOK_M: float = 2.5
	const SPOOK_M_CROUCHED: float = 1.1
	var _gen_mats: Array = []
	var _t: float = 0.0
	var _body: Node3D
	var _emerge: float = 0.0
	var _model: Node3D = null      ## the generated mesh, retracted by _sink rather than scale
	var _rise: float = 0.06        ## measured half-depth: lift that puts the body ON the plate
	var _sink: float = 0.30        ## how far under the plate a fully retracted worm goes

	func _ready() -> void:
		_t = global_position.x * 1.3
		_body = Node3D.new()
		add_child(_body)
		for i in range(4):
			var seg := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var r: float = 0.07 - i * 0.012
			sm.radius = r
			sm.height = r * 2.0
			sm.material = BloomFauna.glow_mat(BloomFauna.TEAL if i == 3 else Color(0.3, 0.34, 0.3), 1.4 if i == 3 else 0.1)
			seg.mesh = sm
			add_child(seg)   # re-parented below for scale control
			remove_child(seg)
			_body.add_child(seg)
			seg.position = Vector3(0, 0.06 + i * 0.11, 0)
		# Generated mesh: the segments ripple as it works the tide line.
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 0.32, ANIM.Mode.UNDULATE,
			0.07, RIPPLE_HZ, BloomFauna.TEAL)
		if not gen.is_empty():
			_gen_mats = gen["mats"]
			ANIM.drive(_gen_mats, RIPPLE_HZ, 0.45)
			_model = gen["model"]
			# Reparented onto the same node the retract already drove, so ONE state variable
			# moves the whole animal whichever body it is wearing. The sink depth is the
			# model's own height plus clearance, measured off the built mesh rather than
			# typed, so a re-cut asset cannot leave a hump of worm on the plating.
			var box: AABB = AABB()
			var first: bool = true
			for m in ANIM._mesh_instances(_model):
				var mi: MeshInstance3D = m
				if mi.mesh == null:
					continue
				var w: AABB = (_model.global_transform.affine_inverse() * mi.global_transform) \
					* mi.get_aabb()
				box = w if first else box.merge(w)
				first = false
			if not first:
				_rise = -box.position.y * _model.scale.y
				_sink = box.size.y * _model.scale.y + 0.06
			self.remove_child(_model)
			_body.add_child(_model)
		# THE DEN MOUTH, built AFTER the replace on purpose: ANIM.replace() hides every mesh
		# that existed before it, so a hole built first is a hole nobody ever sees (and this is
		# the only thing left on the plating once the animal is under it).
		var hole := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.14
		hm.bottom_radius = 0.14
		hm.height = 0.02
		hm.material = BloomFauna.glow_mat(Color(0.04, 0.05, 0.06), 0.0)
		hole.mesh = hm
		hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(hole)

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_t += delta
		# THE TIDE WORM NOW READS THE TIDE. It is named for the tide line, its Codex entry says
		# it works the tide line, and until the sea started moving it had nothing to read — so
		# it keyed off DAWN/DUSK, which is a clock, not a water level. A worm that feeds on
		# what the falling water leaves behind comes out when the water LEAVES: it is out on the
		# ebb and through low water, and gone once the flood covers its burrow again.
		#
		# This also makes it the game's free tide indicator. The worms are on the wet-deck tide
		# line where the player walks past them constantly, so "the worms are out" becomes a
		# readable signal that the pontoon walkway is exposed and worth going down to — taught
		# by an animal rather than by a HUD gauge.
		var tide_now: float = Gyre.tide()
		var out_below: float = Gyre.TIDE_AMP * 0.35     # the lower third of the cycle
		var want: float = 1.0 if tide_now < out_below else 0.0
		var player: Node3D = get_tree().get_first_node_in_group("player")
		if player:
			var spook: float = SPOOK_M_CROUCHED if BloomFauna.player_crouching(self) else SPOOK_M
			if player.global_position.distance_to(global_position) < spook:
				want = 0.0   # felt your footsteps — gone
		_emerge = move_toward(_emerge, want, delta * (2.5 if want < _emerge else 0.35))
		if _emerge > 0.5:
			Journal.discover_if_near(self, "creature_tide_worm", 5.0)
		# The procedural body retracts by SQUASHING (four stacked spheres, so that reads); a
		# generated worm is one closed mesh and would flatten into a pancake, so it SINKS
		# through the 0.5 m plate it is burrowed into instead. One `_emerge`, two bodies.
		if _model != null:
			_body.scale.y = 1.0
			# Fully out it lies ON the plating (the generated mesh is centred on its own box,
			# so it used to be buried to the waterline — measured: 82 mm of a 125 mm-deep worm
			# showing); fully in it is under the plate.
			_model.position.y = lerpf(-_sink, _rise, _emerge)
		else:
			_body.scale.y = maxf(_emerge, 0.001)
		_body.visible = _emerge > 0.02
		_body.rotation.x = sin(_t * 1.7) * 0.22 * _emerge
		_body.rotation.z = cos(_t * 1.3) * 0.22 * _emerge
		# A retracted worm does not ripple — but the RATE is never what says so. `rate` is a
		# time multiplier in creature_swim.gdshader (t = TIME * rate + phase), so driving it
		# from _emerge teleported the wave phase on every frame the emergence moved, and at
		# _emerge 0 it multiplied the beat to a dead stop: this is why the owner's grubs were
		# frozen. The beat is constant; the AMPLITUDE is what fades the animal out.
		ANIM.drive(_gen_mats, RIPPLE_HZ, 0.45 * _emerge, 0.07 * _emerge)


# ------------------------------------------------- Glow Worm
class GlowWorm extends Interactable:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/glow_worm/glow_worm.glb"
	var _gen_mats: Array = []
	## A skittish knuckle of Bloom light denned in a dark corner (GDD canon: light
	## and life, never combat). Wakes only on nights its den is picked. It feels
	## footsteps through the plate and sinks back into the den; crouch-walking
	## shrinks its senses and slows the retreat — sneaking is how you catch one.
	const TRIGGER_RADIUS: float = 4.5
	const TRIGGER_RADIUS_CROUCHED: float = 1.8
	const RETREAT_RATE: float = 1.25         # full hide in ~0.8s
	const RETREAT_RATE_CROUCHED: float = 0.5  # slow enough to close in and grab
	const EMERGE_RATE: float = 0.6
	const CATCHABLE_PRESENCE: float = 0.6     # mostly-hidden worms can't be taken

	var _t: float = 0.0
	var _presence: float = 0.0      ## 0 = in the den, 1 = fully emerged
	var _active_tonight: bool = false
	var _respawn_sec: float = 0.0   ## after a grab, counts down through dark phases only
	var _body: Node3D
	var _glow_mat: StandardMaterial3D
	var _col: CollisionShape3D

	func _init() -> void:
		display_name = "Glow Worm"
		var v: Array[String] = ["GRAB"]
		verbs = v
		# The one animal in this file that IS its own Interactable rather than carrying a
		# FaunaTouch, so it is the one collider the shared tag in FaunaTouch._init misses.
		# Tagged whether or not the den is awake: _col.disabled comes and goes every night,
		# and a skip list that only holds the animals currently emerged is a hole with a
		# schedule. See CREATURE_GROUP.
		add_to_group(BloomFauna.CREATURE_GROUP)

	func _ready() -> void:
		_t = global_position.x * 2.1 + global_position.z
		# Den mouth — a dark disc flush with the plate.
		var hole := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.16
		hm.bottom_radius = 0.16
		hm.height = 0.02
		hm.material = BloomFauna.glow_mat(Color(0.04, 0.05, 0.06), 0.0)
		hole.mesh = hm
		add_child(hole)
		# Body rises out of the den; scale.y is the hide/emerge axis.
		_body = Node3D.new()
		add_child(_body)
		_glow_mat = BloomFauna.glow_mat(BloomFauna.TEAL, 0.0)
		var dim_mat := BloomFauna.glow_mat(BloomFauna.DIM_TEAL, 0.15)
		for i in range(4):
			var seg := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var r: float = 0.09 - i * 0.014
			sm.radius = r
			sm.height = r * 2.0
			sm.material = _glow_mat if i >= 2 else dim_mat
			seg.mesh = sm
			_body.add_child(seg)
			seg.position = Vector3(0, 0.08 + i * 0.13, 0)
		# Small grab target for the interaction ray; disabled whenever hidden
		# or in daylight so there is never an invisible blocker.
		_col = CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.25
		_col.shape = shape
		_col.disabled = true
		add_child(_col)
		_col.position = Vector3(0, 0.25, 0)

	## Colony calls this at dusk: this den is (not) one of tonight's two.
		# Generated mesh: the lit core shifts inside the body.
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 0.26, ANIM.Mode.BREATHE, 0.05, 0.9, BloomFauna.TEAL)
		if not gen.is_empty():
			_gen_mats = gen["mats"]
			ANIM.drive(_gen_mats, 0.9, 1.6)
	func set_active(value: bool) -> void:
		_active_tonight = value
		_respawn_sec = 0.0

	func _catchable() -> bool:
		return _active_tonight and _respawn_sec <= 0.0 \
			and BloomFauna.is_dark_phase() and _presence > CATCHABLE_PRESENCE

	## Hidden worms show no prompt and take no ray hits.
	func available_verbs() -> Array[String]:
		if _catchable():
			return verbs
		var none: Array[String] = []
		return none

	func interact(verb: String, _player: Node3D) -> void:
		if verb != "GRAB" or not _catchable():
			return
		if not PlayerState.add_item("glow_worm"):
			return   # pack full — the worm lives another night
		AudioDirector.play_one_shot("splash", global_position, -18.0)   # soft, wet
		Journal.discover("creature_glow_worm")
		_presence = 0.0
		_col.disabled = true
		_respawn_sec = randf_range(90.0, 150.0)   # den re-opens later in the night
		super.interact(verb, _player)

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_t += delta
		var dark: bool = BloomFauna.is_dark_phase()
		if _respawn_sec > 0.0 and dark:
			_respawn_sec -= delta
		var want_out: bool = _active_tonight and dark and _respawn_sec <= 0.0
		var rate: float = EMERGE_RATE if want_out else RETREAT_RATE
		if want_out:
			var player: Node3D = get_tree().get_first_node_in_group("player")
			if player:
				var crouched: bool = player.crouching
				var trigger: float = TRIGGER_RADIUS_CROUCHED if crouched else TRIGGER_RADIUS
				if global_position.distance_to(player.global_position) < trigger:
					want_out = false   # felt you through the plate
					rate = RETREAT_RATE_CROUCHED if crouched else RETREAT_RATE
		_presence = move_toward(_presence, 1.0 if want_out else 0.0, delta * rate)
		_body.scale.y = maxf(_presence, 0.001)
		_body.visible = _presence > 0.02
		_body.rotation.x = sin(_t * 1.9) * 0.18 * _presence
		_body.rotation.z = cos(_t * 1.4) * 0.18 * _presence
		_glow_mat.emission_energy_multiplier = _presence * (1.1 + 0.5 * sin(_t * 2.3))
		# Denned, it is perfectly still; the swell comes up with the animal.
		ANIM.drive(_gen_mats, 0.9 * _presence, _presence * 1.6, 0.06 * _presence)
		_col.disabled = not _catchable()
		if _presence > 0.5:
			Journal.discover_if_near(self, "creature_glow_worm", 7.0)

# ------------------------------------------------- Glow Worm Colony
class GlowWormColony extends Node3D:
	## The den network. Eight dens in the rig's dark corners; each dusk exactly
	## two wake, rolled fresh with our own RNG so the picks move night to night.
	const DENS: Array[Vector3] = [
		Vector3(27.4, 2.02, -4.6),    # under the first stair ramp, tower ground floor
		Vector3(18.7, 2.02, -10.6),   # base of the SE leg where it punches the wet deck
		Vector3(12.5, 2.02, -5.5),    # foot of the pump-room north wall, pipe shadow
		Vector3(10.7, 2.02, -21.2),   # loot room, dark inner corner
		Vector3(22.7, 2.02, -18.4),   # among the tide-line drums
		Vector3(19.0, 2.02, -21.6),   # beside the SPHL gangplank, cradle shadow
		Vector3(8.6, 18.02, -15.0),   # topside, shadow of the pallet stack
		Vector3(-26.0, 18.02, -12.4), # machine shop, gap between the parts bins
	]

	var _worms: Array[GlowWorm] = []
	var _rng := RandomNumberGenerator.new()
	var _last_a: int = -1
	var _last_b: int = -1

	func _ready() -> void:
		_rng.randomize()
		for den in DENS:
			var w := GlowWorm.new()
			add_child(w)
			w.global_position = den
			_worms.append(w)
		GameClock.dusk.connect(_pick_tonights_dens)
		if BloomFauna.is_dark_phase():
			_pick_tonights_dens()   # loaded into an ongoing night

	func _pick_tonights_dens() -> void:
		var a: int = _rng.randi_range(0, _worms.size() - 1)
		var b: int = _rng.randi_range(0, _worms.size() - 2)
		if b >= a:
			b += 1   # distinct pair, uniform over all pairs
		if (a == _last_a and b == _last_b) or (a == _last_b and b == _last_a):
			a = (a + 1) % _worms.size()   # nudge off last night's exact pair
			if a == b:
				a = (a + 1) % _worms.size()
		_last_a = a
		_last_b = b
		for i in range(_worms.size()):
			_worms[i].set_active(i == a or i == b)

# ------------------------------------------------- Epic 4-Eyed Whale
class Epic4EyedWhale extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/epic_four_eyed_whale/epic_four_eyed_whale.glb"
	const GLOW := Color(0.30, 0.80, 0.95)
	var _gen_mats: Array = []
	var _t: float = 0.0
	var _presence: float = 0.0
	var _flying: bool = false
	var _from: Vector3
	var _to: Vector3
	var _progress: float = 0.0
	var _cooldown: float = 40.0
	var _eye_mats: Array[StandardMaterial3D] = []

	var _spine: Array = []
	var _fin_pivots: Array = []
	var _blink: Array = []   # per-eye blink phase offsets

	func _ready() -> void:
		visible = false
		var kit := preload("res://scripts/world/creature_kit.gd")
		var hide_mat := kit.mat(Color(0.08, 0.22, 0.21), 0.7, 0.25)
		var pale := kit.mat(Color(0.3, 0.42, 0.4), 0.7, 0.1)
		# The body: a tapered five-segment mass, nose to tailstock, that sways as
		# one animal instead of drifting as one balloon. ~22m of whale.
		var radii := [3.0, 3.6, 3.2, 2.2, 1.2]
		var z: float = -8.0
		for i in range(radii.size()):
			var seg := Node3D.new()
			add_child(seg)
			seg.position = Vector3(0, 0, z)
			kit.ball(seg, Vector3.ZERO, radii[i], hide_mat, Vector3(0.85, 0.78, 1.15))
			_spine.append(seg)
			z += radii[i] * 1.35
		# Pale jaw slab under the head, and a scatter of barnacle guests.
		kit.ball(_spine[0], Vector3(0, -1.3, -0.6), 2.0, pale, Vector3(0.75, 0.4, 1.0))
		var rng := RandomNumberGenerator.new()
		rng.seed = 4114
		for i in range(8):
			kit.ball(_spine[rng.randi_range(0, 2)],
				Vector3(rng.randf_range(-1.8, 1.8), rng.randf_range(1.4, 2.6), rng.randf_range(-1.5, 1.5)),
				rng.randf_range(0.12, 0.24), kit.mat(Color(0.5, 0.52, 0.48), 0.9))
		# The fluke, and two long rowing side fins.
		kit.fin(_spine[4], Vector3(0, 0, 1.6), Vector3(4.6, 0.25, 2.2), hide_mat, Vector3(0, 0, 90))
		for side in [-1.0, 1.0]:
			var f := kit.fin(_spine[1], Vector3(side * 2.8, -0.8, 0), Vector3(0.3, 1.2, 3.4), hide_mat,
				Vector3(0, 0, 70 * side))
			_fin_pivots.append(f)
		# The four eyes: two pairs high on the head, each a bright iris inside a
		# soft halo. They blink in sequence, never together — the eerie part.
		for i in range(4):
			var side: float = -1.0 if i < 2 else 1.0
			var fwd: float = -1.6 + (i % 2) * 2.4
			var pos := Vector3(side * 2.0, 2.2 + (i % 2) * 0.7, fwd)
			var halo := BloomFauna.glow_mat(BloomFauna.TEAL, 0.6, 0.3)
			var halo_ball := MeshInstance3D.new()
			var hm := SphereMesh.new()
			hm.radius = 0.62
			hm.height = 1.24
			hm.material = halo
			halo_ball.mesh = hm
			_spine[0].add_child(halo_ball)
			halo_ball.position = pos
			var eye_mat := BloomFauna.glow_mat(BloomFauna.TEAL, 1.8)
			_eye_mats.append(eye_mat)
			var em := SphereMesh.new()
			em.radius = 0.34
			em.height = 0.68
			em.material = eye_mat
			var eye := MeshInstance3D.new()
			eye.mesh = em
			_spine[0].add_child(eye)
			eye.position = pos
			_blink.append(rng.randf_range(0.0, 20.0))
		# The generated four-eyed whale, if it exists: a slow body wave from the vertex
		# shader (Meshy can't rig animals) and a glow that rises with its night presence.
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 14.0, ANIM.Mode.UNDULATE,
			0.22, 0.28, GLOW)
		if not gen.is_empty():
			_gen_mats = gen["mats"]

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_t += delta
		_presence = move_toward(_presence, 1.0 if GameClock.current_phase == GameClock.Phase.NIGHT else 0.0, delta * 0.08)
		# GATED ON _flying, and that is the whole "the whale was inside the rig" bug. Position
		# is only ever WRITTEN inside the flying branch below, so between passes this node sits
		# at its parent's untouched origin — the middle of the rig. Showing it on night
		# presence alone therefore parked a 20 m animal inside the structure until a pass
		# began, at which point it "disappeared and started flying".
		visible = _flying and _presence > 0.02
		# Generated mesh: the vein-glow swells as it fades in out of the dark.
		ANIM.drive(_gen_mats, 0.28, _presence * 1.5)

		# Eyes blink one at a time, on long uneven clocks — never all four dark.
		for i in range(_eye_mats.size()):
			var blink: float = clampf(sin(_t * 0.45 + _blink[i]) * 14.0 - 12.6, 0.0, 1.0)
			_eye_mats[i].emission_energy_multiplier = _presence * (1.5 + 0.8 * sin(_t * 0.8 + i)) * (1.0 - blink)

		if not visible:
			return
		# Body sway: each segment trails the one ahead; fins row slow and out of
		# phase — twenty meters of animal moving like weather.
		for i in range(_spine.size()):
			(_spine[i] as Node3D).position.x = sin(_t * 0.7 - i * 0.55) * (0.25 + i * 0.22)
		for i in range(_fin_pivots.size()):
			(_fin_pivots[i] as Node3D).rotation.x = sin(_t * 0.5 + i * PI) * 0.3

		if not _flying:
			if GameClock.current_phase == GameClock.Phase.NIGHT:
				_cooldown -= delta
				if _cooldown <= 0.0:
					_begin_pass()
			return

		_progress += delta / 60.0
		if _progress >= 1.0:
			_flying = false
			visible = false
			_cooldown = randf_range(120.0, 180.0)
			return

		var pos: Vector3 = _from.lerp(_to, _progress)
		pos.y += sin(_progress * PI) * -8.0
		Journal.discover_if_near(self, "creature_epic_whale", 120.0)
		global_position = pos
		look_at(pos + (_to - _from).normalized(), Vector3.UP)

	func _begin_pass() -> void:
		_flying = true
		visible = true
		_progress = 0.0
		var angle: float = randf_range(0, TAU)
		var dist: float = 240.0
		var dir := Vector3(cos(angle), 0, sin(angle))
		# HIGH ENOUGH TO CLEAR THE RIG. The track is a straight line whose XZ path crosses the
		# world origin — i.e. the rig's own axis — every single pass, and _process dips the arc
		# 8 m at its midpoint, which is exactly over the structure. At 45-55 that put the
		# lowest point at 37-47 m, inside the derrick and comms mast (high iron reaches y 52).
		# 66-76 puts the mid-arc low point at 58-68 m: clear of the tallest steel, and still
		# close enough overhead to read as twenty metres of animal rather than a distant shape.
		_from = -dir * dist + Vector3(0, randf_range(66.0, 76.0), 0)
		_to = dir * dist + Vector3(0, randf_range(66.0, 76.0), 0)
		AudioDirector.play_one_shot("groan", global_position, -4.0)

# ------------------------------------------------- Harbor Seal (Bloom)
class HarborSeal extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/harbor_seal/harbor_seal.glb"
	const GLOW := Color(0.35, 0.90, 0.85)
	const FISH_IDS := ["fish_herring", "fish_slate_cod", "fish_mirrorjack", "fish_chimefish", "fish_sable_hake"]
	var _gen_mats: Array = []
	var _pet_bump: float = 0.0    ## seconds of happy-wiggle left after a pet
	var _fed: bool = false        ## took a fish from your hand — bonded for the day
	## A befriended-able fishing partner (Codex §29). Cruises the water south of
	## the rig, porpoising up to breathe, and by day hauls out to bask on the pontoon
	## shelf under the rig. Curious, never afraid — it turns to watch a nearby player.
	var _t: float = 0.0
	var _head: Node3D
	var _mat: StandardMaterial3D
	var _flippers: Array = []
	var _hauled: bool = false            ## day rest on the pontoon
	var _haul_timer: float = 0.0
	## WHERE IT HAULS OUT — in PLAN ONLY. The height is measured off the world at runtime
	## (_snap_haul), never typed, because every hand-typed y this animal has ever had was
	## wrong within a batch or two.
	##
	## Four moves now, and the first three were all the same mistake — looking for a clear
	## patch of WET DECK. (25.8,-20.6) put its head inside a rusted drum; (24.2,-19.2)
	## parked it in the respawn->stairs walk lane; (9.0,2.25,-21.2) looked clear to a
	## point-probe and was not — a body-sized box on that spot intersects FIVE colliders
	## (measured, tests/FaunaFixProbe), the deck-edge pipework among them, because a 1.8 m
	## animal's flanks reach a metre either side of the point anyone checks.
	##
	## The wet deck is simply the wrong deck for it: it is the rig's working floor, wall to
	## wall with pipe banks, drums and walk lanes. So it moved DOWN a level, to the open
	## foundation — the south pontoon walkway (slab top y0.95, x-28..28, z-16..-8, reached
	## by the Pontoon Ladder that lands at 7.8,-12). That is a bare concrete shelf a metre
	## off the water with nothing built on it, which is exactly what a real seal hauls out
	## on, and it is 1.05 m BELOW the wet deck so the animal is finally under the rig rather
	## than in the middle of it. x3/z-12 is 4.8 m west of the ladder foot — the first thing
	## you see stepping off it — with 5 m of clear air around and clear of the lamp snails
	## that ride this same pontoon at x-17.2 / -10 / 17.2.
	const HAUL_XZ := Vector2(3.0, -12.0)
	var _haul: Vector3 = Vector3(HAUL_XZ.x, 1.5, HAUL_XZ.y)   ## y replaced by _snap_haul
	var _haul_snapped: bool = false
	var _haul_floor: float = 0.95        ## measured shelf height under HAUL_XZ
	var _belly: float = 0.0              ## model half-depth: node origin -> lowest point
	var _crown: float = 0.0              ## model half-depth: node origin -> HIGHEST point
	var _model: Node3D                   ## the generated mesh, for the haul-out seat
	## Smoothed swim heading — see the look_at() note in _process.
	var _heading: Vector3 = Vector3.ZERO
	## THE WATERLINE, and the second time this animal has been reported floating.
	##
	## s23 took the swim depth off the wave surface instead of a fixed y and asserted the fix
	## as "the BELLY is above the water on 0 of 600 frames". That assertion is still true and
	## the owner still reports it floating, because the belly was the wrong end of the animal
	## to measure. Re-measured off the drawn (Gerstner-displaced) surface with
	## tests/SealFloatProbe.tscn: some part of the body was out of the water on 600 OF 600
	## FRAMES, a mean of 0.575 m of back proud of the sea, and the node — the animal's own
	## CENTRE — rode up to +0.159 m ABOVE the waterline. A seal whose middle is above the
	## water is not swimming, it is sitting on the sea.
	##
	## The heights below are stated where a player reads them, at the BACK, and are turned
	## into a node height through the model's own measured crown so a re-generated mesh
	## cannot silently re-float the animal:
	##   CRUISE_UNDER  the back rides this far UNDER the surface for most of the cycle
	##   BREACH_PROUD  ...and this far OVER it at the top of the breath, briefly
	const CRUISE_UNDER: float = 0.18
	const BREACH_PROUD: float = 0.08
	## Shape of the breath. `maxf(sin, 0)` (what this used to be) is at or near its peak for
	## half of every cycle — a permanent perch, not a porpoise. Cubed, the animal is at cruise
	## depth for most of the ~10 s and rolls through the surface for about a second of it.
	const BREACH_SHARPNESS: float = 3.0
	## How close (in plan) the animal gets to HAUL_XZ before it starts lifting out of the
	## water. The pontoon's south face is at z -16 and HAUL_XZ is at z -12, so anything under
	## 4 m would have it swimming at sea level with the slab already under it.
	const HAUL_CLIMB_M: float = 5.0
	## Which seal of the pair this is (0/1). Set by BloomFauna before add_child. Used to
	## put the two animals on opposite sides of the same patrol loop at all times — see
	## the phase offset in _ready and the lane offset in _process. Without this both seals
	## ran the identical ang/r(_t) formula with only a 0..10s randf() head start against a
	## ~39s loop period, so they were frequently in near-identical phase and visibly
	## overlapped/clipped through each other (the reported glitching).
	var spawn_index: int = 0

	func _ready() -> void:
		# Half the ~39s loop period (2*PI/0.16) puts the two seals permanently on opposite
		# sides of the patrol ellipse instead of drifting in and out of the same spot.
		_t = randf() * 10.0 + spawn_index * 19.6
		_mat = BloomFauna.glow_mat(Color(0.32, 0.34, 0.38), 0.0)
		_mat.emission_enabled = false
		_mat.roughness = 0.6
		# Body: a fat tapered capsule.
		var body := MeshInstance3D.new()
		var bm := CapsuleMesh.new()
		bm.radius = 0.42
		bm.height = 1.9
		bm.material = _mat
		body.mesh = bm
		body.rotation.x = deg_to_rad(90)
		add_child(body)
		# Head on a short neck.
		_head = Node3D.new()
		add_child(_head)
		_head.position = Vector3(0, 0.12, -1.0)
		var hm := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.3
		hs.height = 0.62
		hs.material = _mat
		hm.mesh = hs
		_head.add_child(hm)
		var snout := MeshInstance3D.new()
		var ss := SphereMesh.new()
		ss.radius = 0.16
		ss.height = 0.34
		ss.material = _mat
		snout.mesh = ss
		snout.position = Vector3(0, -0.05, -0.28)
		_head.add_child(snout)
		# Dark eyes + a couple of whisker lines.
		var eyemat := BloomFauna.glow_mat(Color(0.05, 0.05, 0.06), 0.0)
		for sx in [-0.12, 0.12]:
			var eye := MeshInstance3D.new()
			var es := SphereMesh.new()
			es.radius = 0.06
			es.height = 0.12
			es.material = eyemat
			eye.mesh = es
			eye.position = Vector3(sx, 0.05, -0.2)
			_head.add_child(eye)
		# Fore flippers on pivots (they row), whisker quills, tail flippers.
		for side in [-1, 1]:
			var fl := Node3D.new()
			add_child(fl)
			fl.position = Vector3(side * 0.42, -0.1, -0.2)
			var mi := MeshInstance3D.new()
			var fm := PrismMesh.new()
			fm.size = Vector3(0.16, 0.05, 0.6)
			fm.material = _mat
			mi.mesh = fm
			fl.add_child(mi)
			mi.position = Vector3(side * 0.1, 0, -0.15)
			mi.rotation.y = deg_to_rad(-25 * side)
			_flippers.append(fl)
		for side in [-1, 1]:
			for w in range(3):
				var whisker := MeshInstance3D.new()
				var wm := CylinderMesh.new()
				wm.top_radius = 0.004
				wm.bottom_radius = 0.004
				wm.height = 0.22
				wm.material = BloomFauna.glow_mat(Color(0.85, 0.85, 0.8), 0.0)
				whisker.mesh = wm
				_head.add_child(whisker)
				whisker.position = Vector3(side * 0.12, -0.08, -0.32)
				whisker.rotation_degrees = Vector3(0, 0, side * (55 + w * 18))
		var tail := MeshInstance3D.new()
		var tm := PrismMesh.new()
		tm.size = Vector3(0.7, 0.05, 0.4)
		tm.material = _mat
		tail.mesh = tm
		tail.position = Vector3(0, 0, 1.05)
		add_child(tail)
		# Generated mesh: a lazy body roll as it cruises and hauls out.
		# (Meshy auto-rigs humanoids only, so the motion is CreatureAnim's vertex shader.)
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 1.8, ANIM.Mode.UNDULATE, 0.05, 1.0, GLOW)
		if not gen.is_empty():
			_gen_mats = gen["mats"]
			ANIM.drive(_gen_mats, 1.0, 0.22)   # re-driven per frame below
			# Measured, NOT grounded: it swims centred on its node and only needs the
			# offset when it hauls out (see HAUL_XZ / _snap_haul).
			_model = gen["model"]
			_belly = ANIM.belly(self, _model)
			_crown = _crown_of(_model)
		# Touchable when hauled out: pet it, or offer a fish (Codex §29 befriending).
		var touch := FaunaTouch.new("Harbor Seal", 0.95, _touch_verbs, _touch_act)
		add_child(touch)
		touch.position = Vector3(0, 0.3, 0)

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_t += delta
		# Deferred out of _ready: the rig is CSG and has no collider to probe until physics
		# has stepped once, so a haul height taken in _ready would find nothing.
		if not _haul_snapped:
			_haul_snapped = true
			_snap_haul()
		var player: Node3D = get_tree().get_first_node_in_group("player")
		# Haul-out: by day it sometimes lugs itself onto the pontoon shelf under the rig and
		# just... lies there, watching you work. The rig has a resident now.
		_haul_timer -= delta
		if _haul_timer <= 0.0:
			var day: bool = GameClock.current_phase == GameClock.Phase.DAY
			_hauled = day and randf() < 0.55 and _idx_zero()
			_haul_timer = randf_range(35.0, 70.0)
		# Hauled out it only breathes; in the water the body wave does the work — a real
		# amplitude, or the seal reads as a towed prop (the exact user complaint).
		_pet_bump = maxf(_pet_bump - delta, 0.0)
		var wiggle: float = 1.0 + _pet_bump * 2.2          # petting doubles the wriggle
		var bond_glow: float = 0.65 if _fed else 0.3
		ANIM.drive(_gen_mats, (0.4 if _hauled else 1.3) * wiggle, bond_glow + _pet_bump * 0.8,
			(0.025 if _hauled else 0.11) * wiggle)
		if _hauled:
			# THE APPROACH SWIMS, AND ONLY THEN CLIMBS. This used to lerp the whole Vector3,
			# so an animal that decided to haul out from the far side of the loop left the sea
			# the instant it turned for the shelf and crossed the last twenty metres of open
			# water at shelf height — the reported "floats above the surface", in a shorter
			# burst than the patrol's and right where the player is standing. The plan closes
			# as before; the HEIGHT stays on the water until the slab is actually under it.
			# HAUL_CLIMB_M clears the pontoon's south face (z -16, 4 m out from HAUL_XZ) so
			# the climb starts just BEFORE the concrete rather than inside it.
			var k: float = clampf(delta * 1.5, 0.0, 1.0)
			var to_haul: float = Vector2(_haul.x - global_position.x,
				_haul.z - global_position.z).length()
			global_position.x = lerpf(global_position.x, _haul.x, k)
			global_position.z = lerpf(global_position.z, _haul.z, k)
			# THE 1-2 m HOVER, AND IT WAS A LOW-PASS FILTER ON A WAVE.
			#
			# Both of these used to LERP y with the same `k = delta * 1.5`. That is a
			# first-order filter with a 0.667 s time constant, and the eleven Gerstner bands
			# run at omega 0.83-6.02 rad/s — so the animal could not track the sea it was
			# steering by. It held near mean water while the surface swung around it: summed
			# per-band lag is ~0.53 m RMS and ~1.50 m peak at the shipped calm sea state, and
			# 1.07 / 3.00 m in a squall. It fires only on the run in toward the pontoon, which
			# is exactly when the animal is seen against the foundation — hence the report.
			#
			# The patrol branch never had this because it ASSIGNS (`global_position = pos`),
			# which is also why both existing probes missed it: SealFloatProbe forces
			# `_hauled = false` and FaunaBugsProbe teleports the seal onto the shelf, so the
			# approach had never been measured at all.
			var sea_y: float = Gyre.wave_height(
				Vector2(global_position.x, global_position.z), Gyre.water_time()) \
				- CRUISE_UNDER - _crown
			if to_haul > HAUL_CLIMB_M:
				global_position.y = sea_y      # assigned, like the patrol — no filter, no lag
			else:
				# THE CLIMB OUT, driven by DISTANCE rather than by time. A time-based lerp let
				# the horizontal approach outrun the vertical one, so the animal crossed the
				# slab face (z -16, top y 0.95) still down at sea level and transited ~3 m of
				# solid concrete before surfacing. As a function of how far it still has to go,
				# it is provably at the sea when the climb begins and at the seat when it
				# arrives, whatever the frame rate.
				var climb: float = clampf(1.0 - to_haul / HAUL_CLIMB_M, 0.0, 1.0)
				global_position.y = lerpf(sea_y, _haul.y, smoothstep(0.0, 1.0, climb))
			rotation.z = lerp_angle(rotation.z, 0.0, delta * 2.0)
			rotation.x = lerp_angle(rotation.x, -0.12, delta * 2.0)   # chest-up rest pose
			# THE SEAT owns the height once it has arrived — see _seat(). Gated on being
			# over the spot so the approach lerp isn't yanked down onto the shelf while the
			# animal is still out over the water.
			if Vector2(global_position.x - _haul.x, global_position.z - _haul.z).length() < 1.0:
				_seat()
			for f in _flippers:
				(f as Node3D).rotation.x = lerp_angle((f as Node3D).rotation.x, 0.0, delta * 3.0)
			if player:
				Journal.discover_if_near(self, "creature_seal", 18.0)
				var to_pl: Vector3 = player.global_position - _head.global_position
				var flat_pl := Vector3(to_pl.x, 0, to_pl.z)
				if flat_pl.length_squared() > 0.01:
					_head.rotation.y = lerp_angle(_head.rotation.y, atan2(flat_pl.x, flat_pl.z) - rotation.y, delta * 2.0)
			return
		# A long looping patrol south of the rig, near the surface.
		#
		# THE RADIUS IS A CLEARANCE, not a taste call. The loop is an ellipse of x-radius
		# 0.7r and z-radius r about (0, -34), so its northernmost point is z = -34 + r_max.
		# r used to swing 14..26, which put that point at z -8 — INSIDE the south pontoon
		# (x-28..28, z-16..-8, slab y-3.05..0.95) at the y0-ish depth this animal swims,
		# so every wide lap drove it straight through the concrete. r_max 16 stops it at
		# z -18: two metres clear of the pontoon's south face, and clear of the submerged
		# work plate's hanger rods (x12/21, z-19/-21) because the loop only reaches x ±11
		# at z -34, far south of them. Closer to the rig than the old loop, and visible
		# from the wet-deck south rail the whole way round.
		var ang: float = _t * 0.16
		# +/-1.5m lane split by spawn_index so even a phase-alignment moment (e.g. right
		# after a haul-out) still leaves the two seals on distinct rings, not coincident.
		#
		# THE SWING IS 2.5, NOT 4.0, AND THAT IS THE LANE'S RENT. r_max is a hard clearance
		# (see the block above: 16 is what keeps the loop two metres off the pontoon's south
		# face at z -16), so the lane offset has to come OUT of the swing rather than be added
		# on top of it — 12 + 4.0 + 1.5 would have put the outer seal's ring at z -16.5 with a
		# 1.8 m animal on it, i.e. its flank inside the concrete. 12 + 2.5 + 1.5 = 16 exactly.
		var r: float = 12.0 + sin(_t * 0.1) * 2.5 + (spawn_index * 2 - 1) * 1.5
		var breathe: float = sin(_t * 0.6)          # porpoising rhythm
		# THE SEAL SWIMS IN THE SEA, NOT AT y = 0 (owner, s23: "the harbor seal floats above
		# the surface"). The haul-out seat is fine — measured at a 0.0 mm gap on the pontoon
		# shelf — and this is the other half of the animal: the patrol wrote a FIXED height
		# into an ocean whose surface is an 11-band Gerstner sum running to a -6.44 m trough
		# floor. Measured over 600 frames before the fix: the belly was clear of the water on
		# 134 of them, 22.3% of the loop, by up to 379 mm — an animal flying over the troughs
		# and submerged through the crests, which is exactly "hovering". The depth is now taken
		# from the wave surface AT THE SEAL'S OWN xz, so the animal rides the swell rather
		# than a fixed line through it. Two Gyre calls per seal per frame; the term s19
		# profiled out was 512 of them.
		#
		# ...AND THAT WAS NECESSARY, NOT SUFFICIENT — s24, same owner, same words. Riding the
		# swell fixed WHERE the animal was; it was still written as `sea - 0.45 + up to 0.55`,
		# a lift big enough to carry the animal's own CENTRE above the waterline. Re-measured
		# against the drawn surface (tests/SealFloatProbe.tscn): some part of the body out of
		# the water on 600 OF 600 FRAMES, a mean 0.575 m of back proud of the sea, node up to
		# +0.159 m ABOVE it. The height is now stated at the BACK and converted through the
		# model's own measured crown (CRUISE_UNDER / BREACH_PROUD), so the animal cruises
		# submerged and only rolls through the surface to breathe. `_crown` is 0 on the
		# procedural fallback body, which lands within a few centimetres of the old resting
		# depth — no worse than it was, and correct the moment a mesh is there.
		var flat_xz := Vector2(cos(ang) * r * 0.7, -34.0 + sin(ang) * r)
		var sea: float = Gyre.wave_height(flat_xz, Gyre.water_time())
		var surfacing: float = pow(maxf(breathe, 0.0), BREACH_SHARPNESS)
		var back_y: float = -CRUISE_UNDER + surfacing * (CRUISE_UNDER + BREACH_PROUD)
		var y: float = sea + back_y - _crown
		var pos := Vector3(flat_xz.x, y, flat_xz.y)
		var vel: Vector3 = pos - global_position
		global_position = pos
		# AIM ALONG A SMOOTHED HEADING, not the raw per-frame delta.
		#
		# `vel` carries the SEA's vertical velocity as well as the animal's, and the short
		# chop bands (1.7 m wavelength, omega ~6 rad/s) run to metres per second — so
		# look_at()ing the raw delta pitched a 1.8 m animal by ~30 deg up and down for every
		# wavelet it crossed. Measured before the fix: a world AABB 1.581 m TALL on a body
		# 0.76 m deep, which is most of what read as "bobbing" rather than swimming. The
		# heading is eased toward the travel direction and its climb is capped at ~20 deg, so
		# the body follows the swell and ignores the ripple. The old extra
		# `rotation.x += vel.y * 2.0` is gone with it: look_at() already pitches into the
		# arc, and that term was a second helping of the same pitch.
		if vel.length_squared() > 1.0e-8:
			_heading = vel if _heading.length_squared() <= 0.0 \
				else _heading.lerp(vel, clampf(delta * 3.0, 0.0, 1.0))
		var flat_h: float = Vector2(_heading.x, _heading.z).length()
		if flat_h > 1.0e-5:
			var climb: float = clampf(_heading.y, -flat_h * 0.36, flat_h * 0.36)
			look_at(pos + Vector3(_heading.x, climb, _heading.z), Vector3.UP)
		# Fore flippers row on the dive beat.
		for i in range(_flippers.size()):
			(_flippers[i] as Node3D).rotation.x = sin(_t * 2.4 + i * PI) * 0.5
		# Curiosity: if the player is close and on the deck, the head turns to them.
		if player and player.global_position.distance_to(global_position) < 18.0:
			Journal.discover_if_near(self, "creature_seal", 18.0)
			var to_p: Vector3 = player.global_position - _head.global_position
			if to_p.length_squared() > 0.01:
				var flat := Vector3(to_p.x, 0, to_p.z).normalized()
				_head.rotation.y = lerp_angle(_head.rotation.y, atan2(flat.x, flat.z) - rotation.y, delta * 2.0)
		# Body roll as it swims.
		rotation.z = sin(_t * 1.2) * 0.15

	## Find the pontoon shelf under HAUL_XZ and seat the animal ON it: the node goes the
	## model's own belly depth above whatever the ray hits, so the flippers rest on the
	## concrete instead of the body being buried to its waterline in it.
	func _snap_haul() -> void:
		var world: World3D = get_world_3d()
		if world == null:
			return
		var from := Vector3(HAUL_XZ.x, 4.0, HAUL_XZ.y)
		var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 7.0, 0))
		q.collision_mask = 1          # world geometry
		q.collide_with_areas = false
		q.exclude = BloomFauna.fauna_bodies(self)   # not another animal's touch collider
		var hit: Dictionary = world.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return                    # nothing under it — keep the conservative default
		_haul_floor = hit["position"].y
		_haul = Vector3(HAUL_XZ.x, _haul_floor + _belly, HAUL_XZ.y)

	## Rest the animal ON the shelf whatever pose it settled into.
	##
	## _snap_haul's height comes off the model's UNPITCHED bounds, and the rest pose is
	## pitched: chest up, tail down. On this 2 m body that buried the tail 105 mm in the
	## concrete (measured). Correcting the constant would only hold until the pose changed,
	## so the live low point is what the height is derived from instead — the same "the seat
	## owns the floor" rule the crab and the snails already run on.
	##
	## s34: AND THEN IT FLOATED, BY ALMOST EXACTLY THE AMOUNT IT HAD BEEN BURIED. Owner:
	## "when it rests on the foundation there's like a meter of room under it", against a
	## probe reporting GAP +0.0 mm. `ANIM.low_point` is a BOUND — the axis-aligned box of the
	## ROTATED box — and on this mesh at this pitch that bound sits 102.0 mm below the lowest
	## real vertex (computed exactly from the GLB: true low 0.385001 m under the node,
	## low_point 0.487041 m). Seating the bound on the concrete therefore hangs the animal
	## 102 mm over it. The fix is to seat the MESH: ANIM.low_vertex is exact (a support query
	## over the cached convex hull) and costs a couple of hundred dot products on the frames
	## the animal is actually hauled out.
	func _seat() -> void:
		if _model == null:
			return
		var low: float = ANIM.low_vertex(_model)
		if low == INF:
			return
		global_position.y += _haul_floor - low

	## How far the model's HIGHEST point stands above the host origin, metres — the mirror of
	## CreatureAnim.belly(), and the number the waterline is stated against. Measured in
	## _ready, in the same unrotated frame belly() is, so the two are the same statement about
	## the same mesh: a regenerated seal moves its own waterline and nothing has to be retyped.
	func _crown_of(model: Node3D) -> float:
		var acc := AABB()
		var first := true
		var inv: Transform3D = global_transform.affine_inverse()
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var inst: MeshInstance3D = n
			if inst.mesh == null:
				continue
			var box: AABB = (inv * inst.global_transform) * inst.get_aabb()
			acc = box if first else acc.merge(box)
			first = false
		return 0.0 if first else acc.position.y + acc.size.y

	## Only the first seal hauls out — one resident, one patroller.
	##
	## Was `get_index() % 2 == 0`, which asks the SCENE TREE which animal this is: it happened
	## to pick exactly one of the pair only because the two are added back to back, and it
	## picked the seal with spawn_index 1 (measured: indices 31 and 32), i.e. the opposite one
	## from the pair's own numbering. spawn_index is the identity BloomFauna actually assigns,
	## so ask that instead and the resident is the same animal every run.
	func _idx_zero() -> bool:
		return spawn_index == 0

	func _touch_verbs() -> Array:
		if not _hauled:
			return []            # in the water it is out of reach — deck-side only
		var v: Array = ["PET"]
		for id in FISH_IDS:
			if PlayerState.has_item(id):
				v = ["FEED", "PET"]   # offering food takes precedence on the prompt
				break
		return v

	func _touch_act(verb: String, _player: Node3D) -> void:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		Journal.discover("creature_seal")
		if verb == "FEED":
			for id in FISH_IDS:
				if PlayerState.has_item(id):
					PlayerState.remove_item(id)
					_fed = true
					_pet_bump = 3.0
					AudioDirector.play_one_shot("splash", global_position, -8.0)
					if hud and hud.has_method("toast"):
						hud.toast("It takes the fish gently and looks at you a long moment. You have a fishing partner now.")
					return
		_pet_bump = 2.0
		if hud and hud.has_method("toast"):
			hud.toast("Wet fur, warm under. It leans into your hand." if not _fed
				else "It rolls over. Entirely shameless.")

# ------------------------------------------------- shared surface crawler
class GroundCrawler extends FaunaMove.SurfaceCrawler:
	## The wander a slow grazer runs — the three snails, and anything else that works a
	## patch on foot. It is a SURFACE crawler, not a ground walker: the whole behaviour
	## (frame carried on the face it is stuck to, obstruction decisions, kerbs crawled
	## over, tall faces climbed and turned back from at six metres) lives in
	## FaunaMove.SurfaceCrawler so the crab and the deck gulls can take it later.
	##
	## Kept as a named species-side class because that is what every snail and the E2E
	## wall probe construct; the constructor, `heading`, `blocked`, `tick()` and
	## `face_yaw()` are unchanged. New: `up`, `basis()`, `orient()`, `climbing`,
	## `climb_peak` and `choice`, which are what a climbing animal needs to be drawn
	## and to be audited.
	pass


# --------------------------------------------------- Lamp Snail (marbled shell)
class LampSnail extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/lamp_snail/lamp_snail.glb"
	var _gen_mats: Array = []
	## Wheelbarrow-sized gastropods (Codex §54). The shell is BACKLIT MARBLE — wavy
	## luminous veins flowing through a pale MOON-ROCK shell body, like light behind
	## alabaster — not the old scatter of star-dots. They drift the rig-leg bases day and
	## night and never go dark (see VEIN_FLOOR / LIGHT_FLOOR): the read is a small moon
	## crossing the plating, its own light travelling with it. Brightest after dark, where
	## the glow through the water is the "lean over the rail" wonder-beat.
	var _t: float
	var _base: Vector3
	## THE NEVER-DARK FLOOR (owner call, 2026-07-28: "a small moving moon").
	##
	## The glow used to be a pure day/night switch multiplied by a harvest penalty and a
	## fed bonus, all of which bottomed out at literal zero — so by day, or for the two and
	## a half minutes after a harvest, the animal was an unlit lump you could stand on top
	## of and not find. The bright/dim states are worth keeping (they are the whole read on
	## "I fed it" / "I just harvested it"), so they stay as RELATIVE variation and this goes
	## under them as an absolute minimum: whatever the state, the shell emits at least this
	## much and the lamp casts at least LIGHT_FLOOR onto whatever it is crawling over.
	##
	## Values are set where they land, not by taste. VEIN_FLOOR 0.42 puts the shader's
	## emission term (vein_color * vein_energy * ribbon) at ~0.35 of a near-white — plainly
	## visible in an unlit interior, invisible against a lit deck by day, which is exactly
	## "faint glow in the dark, never fully dark". Night peaks at 2.0 (x1.3 fed), so the
	## floor is ~20% of full and the dynamic range the player reads is untouched.
	const VEIN_FLOOR: float = 0.42
	## The cast light's floor. The shell alone would be a glow that lights nothing — the
	## thing that sells a moon is the pool it puts on the plating under it, and that pool
	## has to survive daylight and the harvest penalty too. Night peak is 0.65 (see the
	## x0.325 below), so 0.20 is a third of full: a soft disc that moves with the animal.
	const LIGHT_FLOOR: float = 0.20
	## MOON PALETTE (owner call: white / light blue, not teal/green). The shell body is
	## pale blue-grey rock and the veins are cold moonlight. Kept slightly blue rather than
	## pure white so it separates from the rig's warm sodium floodlights at night.
	const SHELL_BODY := Color(0.62, 0.68, 0.80)
	const SHELL_VEIN := Color(0.82, 0.90, 1.00)
	const MOON_LIGHT := Color(0.70, 0.82, 1.00)
	## THE SHELL'S LIGHT. This replaces the old `_spots` array of glowing sphere meshes
	## one-for-one: same job (a handle the game dims and lights every frame), same call
	## sites, but it is now the shell SURFACE — materials/shell_marble.gdshader draws
	## flowing marbled veins of light through the shell body instead of dotting stars on
	## it. Cheaper too: the constellation was up to eleven extra meshes per snail, and
	## since CreatureAnim.replace() hides everything built before it, not one of them was
	## even being drawn once lamp_snail.glb landed.
	var _vein_mats: Array[ShaderMaterial] = []
	var _vein_energy: float = 0.0     ## the eased glow level pushed into `vein_energy`
	var _idx: int
	var _stalks: Array[Node3D] = []   # the two optic tentacles, waving
	var _eye_mat: StandardMaterial3D
	var _harvest_cd: float = 0.0      ## regrowth time after a mucus harvest
	var _crawler: GroundCrawler       ## wall-aware wander around the leg base
	var _carried_by: Node3D = null    ## set while the player is carrying this live snail
	var _lamp_light: OmniLight3D      ## gentle bioluminescent pool of light
	var _fed: bool = false            ## took a greens item; breeds when a fed sibling is close
	var _is_baby: bool = false        ## spawned by breeding — permanent, ~0.4 scale, grows in
	var _grow_h: float = 0.0          ## game-hours since birth (baby only)
	var _body_pivot: Node3D = null    ## baby-only scale wrapper (see BloomFauna.shrink_to_baby)

	func _init(idx: int, base: Vector3) -> void:
		_idx = idx
		_base = base
		_t = idx * 1.9

	func _ready() -> void:
		add_to_group("snail_lamp")
		# Shell: a coiled dark dome.
		var shell := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.45
		sm.height = 0.7
		sm.is_hemisphere = true
		# MARBLED, not spotted. The dome is a pale moon-rock shell body with luminous
		# ribbons running through it — backlit nacre. Bounds come off the mesh so the
		# veining is scaled to this dome and not to some assumed unit size. mask_lo/hi are
		# pushed below zero because this mesh is ALL shell (nothing to mask the foot out of).
		var shell_mat: ShaderMaterial = BloomFauna.shell_mat(sm.get_aabb(), {
			"pattern_mode": 0,
			"base_color": SHELL_BODY,
			"vein_color": SHELL_VEIN,
			"tint": Color(1, 1, 1, 1),
			"roughness_v": 0.38,
			"pattern_scale": 2.8, "vein_width": 0.40, "vein_sharp": 0.52,
			# MORPH RATE. The veins are not a fixed pattern being scrolled — the field they
			# are drawn from slowly reshapes, so channels fork, close and wander. 0.001 is
			# about a minute per full re-cut of the veining and ~1% of one in the couple of
			# seconds you might stand and stare: imperceptible while you watch it, a
			# different shell if you look back later. Photographed at 0/2/20/60/120 s by
			# tests/ShellMorphShot.tscn; see pattern_scroll in shell_marble.gdshader.
			"warp_strength": 1.7, "pattern_scroll": 0.001,
			"mask_lo": -0.5, "mask_hi": -0.4,
			"mode": 0,   # static: the procedural dome has no foot to ripple
		})
		_vein_mats.append(shell_mat)
		sm.material = shell_mat
		shell.mesh = sm
		add_child(shell)
		# The foot beneath.
		var foot := MeshInstance3D.new()
		var fm := CapsuleMesh.new()
		fm.radius = 0.2
		fm.height = 0.9
		# The foot glows fainter than the dome — light bleeding through soft tissue.
		fm.material = BloomFauna.glow_mat(Color(0.26, 0.30, 0.36), 0.30)
		foot.mesh = fm
		foot.rotation.x = deg_to_rad(90)
		foot.position.y = -0.15
		add_child(foot)
		# Two optic tentacles reaching off the leading edge of the foot (+Z), each
		# tipped with a small light-sensing eye bulb — the snail "reads" the dark.
		_eye_mat = BloomFauna.glow_mat(SHELL_VEIN, 1.5)
		for sx in [-0.11, 0.11]:
			var pivot := Node3D.new()
			add_child(pivot)
			pivot.position = Vector3(sx, -0.02, 0.46)
			var stalk := MeshInstance3D.new()
			var stm := CapsuleMesh.new()
			stm.radius = 0.022
			stm.height = 0.32
			stm.material = BloomFauna.glow_mat(Color(0.16, 0.2, 0.22), 0.0)
			stalk.mesh = stm
			stalk.rotation.x = deg_to_rad(58)   # angle up and forward
			stalk.position = Vector3(0, 0.08, 0.09)
			pivot.add_child(stalk)
			var eye := MeshInstance3D.new()
			var em := SphereMesh.new()
			em.radius = 0.045
			em.height = 0.09
			em.material = _eye_mat
			eye.mesh = em
			eye.position = Vector3(0, 0.22, 0.24)   # at the stalk tip
			pivot.add_child(eye)
			_stalks.append(pivot)
		# A gentle pool of MOONLIGHT cast on the plate — cold white-blue, soft attenuation,
		# no shadow. It is parented to the animal, so the pool travels with it: a shell that
		# glowed without lighting anything under it would read as a decal, not a lamp.
		# Starts at the floor rather than at zero so the very first frame is already lit.
		_lamp_light = OmniLight3D.new()
		_lamp_light.light_energy = LIGHT_FLOOR
		_lamp_light.omni_range = 3.0
		_lamp_light.light_color = MOON_LIGHT
		_lamp_light.shadow_enabled = false
		add_child(_lamp_light)
		# The journal's promised beat: a gentle harvest takes the glow-mucus, leaves the
		# animal. Only at night, and the veining needs time to re-charge. Crouch
		# near it and E means COLLECT instead (BloomFauna.player_crouching); standing,
		# offering greens (FEED) takes precedence the same way HarborSeal's FEED beats
		# PET, then HARVEST, then the GRAB fallback.
		var touch := FaunaTouch.new("Lamp Snail", 0.85,
			func() -> Array:
				if BloomFauna.player_crouching(self):
					return ["COLLECT"]
				var night: bool = GameClock.current_phase == GameClock.Phase.NIGHT
				var out: Array = ["GRAB"]
				if night and _harvest_cd <= 0.0:
					out.push_front("HARVEST")
				if not _is_baby and not _fed and BloomFauna.has_greens():
					out.push_front("FEED")
				return out,
			_touch_act)
		add_child(touch)
		# Generated mesh: a faint shell flex; the marbling does the real work.
		# PEDAL: the foot ripples back-to-front, which is how a snail actually travels.
		# The rim colour is the MOON vein, not the house teal — the base shader's fresnel
		# term rides on top of the marbling, and a teal rim over white-blue veins was reading
		# as a green fringe on every ribbon.
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 0.9, ANIM.Mode.PEDAL, 0.03, 0.55, SHELL_VEIN)
		if not gen.is_empty():
			_gen_mats = gen["mats"]
			# Swap the generated surfaces onto the shell shader — the GlassSnail move. The
			# generator bakes an opaque albedo and cannot be asked for veins of light, so
			# the pattern goes on here, over the baked skin. base_color multiplies that
			# skin down to a deep shell tone; mask_lo/hi keep the veining on the shell and
			# off the foot (one mesh covers both), and the PEDAL motion, PBR maps and
			# authored facing all ride across the shader swap untouched.
			_vein_mats.append_array(BloomFauna.reshell(_gen_mats, {
				"pattern_mode": 0,
				"base_color": SHELL_BODY,
				"base_desat": 1.0, "skin_mix": 0.12,   # the baked star decals go
				"vein_color": SHELL_VEIN,
				"roughness_v": 0.36,
				"pattern_scale": 2.9, "vein_width": 0.40, "vein_sharp": 0.52,
				"warp_strength": 1.7, "pattern_scroll": 0.001,   # see the dome above
				"mask_lo": 0.24, "mask_hi": 0.44,
			}))
			BloomFauna.ground_model(self, gen["model"])   # foot on the surface, not floating
		# Wanders the leg base instead of tracing a rigid circle through the concrete: it
		# heads out, and when the caisson or a rail stops it, it turns and grazes on.
		global_position = _base
		_crawler = GroundCrawler.new(_base, 4.2, 0.13, 400 + _idx, 0.35, 0.2, _base.y)
		if _is_baby:
			_body_pivot = BloomFauna.shrink_to_baby(self, BloomFauna.BABY_SCALE)

	func _touch_act(verb: String, player: Node3D) -> void:
		match verb:
			"GRAB":
				BloomFauna.grab_snail(self, player)
			"FEED":
				_feed(player)
			"COLLECT":
				_collect(player)
			_:
				_harvest(verb, player)

	func _harvest(_verb: String, _player: Node3D) -> void:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if not PlayerState.add_item("glow_mucus"):
			if hud and hud.has_method("toast"):
				hud.toast("Hands full — the snail keeps its light tonight.")
			return
		_harvest_cd = 150.0
		Journal.discover("creature_lamp_snail")
		if hud and hud.has_method("toast"):
			hud.toast("You wipe a palmful of cold light off the shell. The snail never slows down.")

	## Feed it a greens item. Fed reads as a brighter, faster pulse (_process); breeding
	## itself is checked continuously in _process so a snail carried over to a second fed
	## one (the natural way to actually pair them) breeds on arrival, not only at feed time.
	func _feed(_player: Node3D) -> void:
		if _is_baby or _fed or not BloomFauna.consume_greens():
			return
		_fed = true
		Journal.discover("system_snail_breeding")
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toast"):
			hud.toast("It takes the greens eagerly — the veins in the shell run brighter.")

	## Two fed lamp snails in reach of each other: a permanent baby, half-grown light
	## between them. Resets both parents so the next baby needs a fresh pair of feeds.
	func _breed_with(partner: Node3D) -> void:
		var mid: Vector3 = (global_position + partner.global_position) * 0.5
		var baby := LampSnail.new(5000 + (randi() % 100000), mid)
		baby._is_baby = true
		get_parent().add_child(baby)
		baby.global_position = mid
		_fed = false
		partner.set("_fed", false)
		Journal.discover("creature_snail_baby")
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toast"):
			hud.toast("Two fed lights lean together, and a third blinks on between them.")

	## COLLECT: the whole animal, for the pot. Works on a baby or a grown one — a lamp
	## snail leaving the deck dims the rig by exactly one light, same as a
	## harvest dims one shell, except this light does not come back.
	func _collect(_player: Node3D) -> void:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if not PlayerState.add_item("snail_live"):
			if hud and hud.has_method("toast"):
				hud.toast("Hands full — it stays where it is.")
			return
		Journal.discover("item_snail_live")
		if hud and hud.has_method("toast"):
			hud.toast("Into the pack it goes, shell dimming, foot still working the air.")
		queue_free()

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_t += delta
		# Baby growth: scale eases from BABY_SCALE to full over GROW_HOURS game-hours.
		# Feeding (and so breeding) stays off-limits until it graduates (verbs_fn gates
		# FEED on `not _is_baby`) — a still-growing snail cannot itself be a parent yet.
		if _is_baby:
			_grow_h += delta * GameClock.time_scale * BloomFauna.game_hour_per_sec()
			if _body_pivot:
				_body_pivot.scale = Vector3.ONE * lerpf(BloomFauna.BABY_SCALE, 1.0,
					clampf(_grow_h / BloomFauna.GROW_HOURS, 0.0, 1.0))
			if _grow_h >= BloomFauna.GROW_HOURS:
				_is_baby = false
		elif _fed:
			# Checked every frame (not just at feed time) so carrying an already-fed
			# snail over to a second one and setting it down close by breeds them too.
			var partner: Node3D = BloomFauna.find_breed_partner(self, BloomFauna.BREED_RADIUS)
			if partner:
				_breed_with(partner)
		_harvest_cd = maxf(_harvest_cd - delta, 0.0)
		var night: bool = GameClock.current_phase == GameClock.Phase.NIGHT
		# Day is no longer OFF, it is DIM: the animal is a lamp that happens to be brighter
		# after dark, not a lamp that gets switched off at dawn.
		var glow: float = 2.0 if night else 0.6
		if _harvest_cd > 120.0:
			glow *= 0.15   # freshly wiped — the shell's veining re-charges slowly
		# Fed reads as visibly brighter and a touch faster — the "I fed it" feedback.
		var pulse_rate: float = 1.05 if _fed else 0.8
		var pulse_mul: float = 1.3 if _fed else 1.0
		# THE DIMMER (was the per-spot emission loop). Same eased level, same rate, same
		# semantics — full at night, dim by day, knocked to 15% while the shell recharges
		# after a harvest — pushed into one shader uniform instead of eleven materials.
		# The per-spot twinkle offset is now spatial: the shader varies the ribbons across
		# the shell so the marbling breathes unevenly rather than as one flat lamp.
		#
		# maxf, not lerp-toward-zero: every one of those multipliers can reach zero, and the
		# floor is what stops the animal ever going dark. It is applied to the FINAL level so
		# the pulse still breathes above it instead of being clamped flat.
		var level: float = maxf(glow * pulse_mul * (0.55 + 0.45 * sin(_t * pulse_rate)), VEIN_FLOOR)
		_vein_energy = lerpf(_vein_energy, level, delta * 1.5)
		for m in _vein_mats:
			m.set_shader_parameter("vein_energy", _vein_energy)
		# The cast light rides the SAME eased level as the shell, so the pool on the plating
		# can never disagree with the glow that is supposed to be making it — including at
		# the floor, where the animal is still a small moon crossing a dark deck.
		if _lamp_light:
			_lamp_light.light_energy = maxf(_vein_energy * 0.325, LIGHT_FLOOR)
		# ALWAYS DRAWN. This used to read `night or global_position.y > 0.0`, which hid a
		# submerged snail by day — but the animal is now findable at all times by design, and
		# a carried one dipped below the waterline blinking out is the bug that rule buys.
		visible = true
		# The pedal wave never fully stops either: the crawler walks it round the clock, and
		# a sliding snail with a frozen foot is worse than a slow one. Rim glow rides the
		# eased level so it, too, has the floor under it.
		ANIM.drive(_gen_mats, 0.55 if night else 0.3, _vein_energy * 0.35, 0.03 if night else 0.02)
		if night:
			Journal.discover_if_near(self, "creature_lamp_snail", 12.0)
		# Eye stalks sway on their own slow rhythm; the eye bulbs pick up the glow — and
		# keep a lit ember by day for the same reason the shell does.
		if _eye_mat:
			_eye_mat.emission_energy_multiplier = lerpf(_eye_mat.emission_energy_multiplier, 1.5 if night else 0.5, delta * 2.0)
		for i in range(_stalks.size()):
			var s: Node3D = _stalks[i]
			s.rotation.z = sin(_t * 0.6 + i * PI) * 0.22
			s.rotation.y = sin(_t * 0.4 + i * 1.7) * 0.18
		# Being carried: hold in front of the player, keep the pedal animation, don't crawl.
		if BloomFauna.snail_carry(self, _crawler, delta):
			return
		# A slow wander round the leg base, riding the pontoon top and turning away from the
		# caisson instead of tracing a rigid circle through it. Grounds every frame so it
		# never floats; the +PI in face_yaw leads the yaw-normalised (-Z-forward) model
		# head-first instead of crawling backwards.
		_crawler.tick(self, delta)
		# The FULL surface frame, not a yaw: -Z leads the travel and +Y is the face normal,
		# so one of these on the caisson wall reads as a snail stuck to the caisson wall
		# rather than a snail lying on its side in the air beside it.
		_crawler.orient(self, delta)

# ------------------------------------------------------------ FaunaTouch
class FaunaTouch extends Interactable:
	## An invisible touch-target that rides a creature and proxies the interaction
	## verbs to it. The species stay Node3D (their movement code owns the transform);
	## this small StaticBody3D child is what the player's InteractionRay actually hits.
	var verbs_fn: Callable   ## () -> Array[String] — live, state-dependent
	var act_fn: Callable     ## (verb: String, player: Node3D) -> void

	func _init(name_: String, radius: float, verbs_fn_: Callable, act_fn_: Callable) -> void:
		display_name = name_
		verbs_fn = verbs_fn_
		act_fn = act_fn_
		# TAGGED AT CONSTRUCTION, not at any of the ten call sites, because that is the only
		# version of the habit a species added next session cannot forget to copy — and it is
		# what carries the tag to the handles built under other hosts (leg_reef's climbing
		# snails are LampSnail / PyramidSnail instances parented over there). A group is legal
		# on a node that is not in the tree yet; it registers on _enter_tree. See CREATURE_GROUP.
		add_to_group(BloomFauna.CREATURE_GROUP)
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = radius
		cs.shape = sph
		add_child(cs)

	func available_verbs() -> Array[String]:
		var out: Array[String] = []
		out.assign(verbs_fn.call())
		return out

	func interact(verb: String, player: Node3D) -> void:
		act_fn.call(verb, player)
		interacted.emit(verb)

# -------------------------------------------------------------- GullWings
class GullWings extends RefCounted:
	## Overlay flight wings for the herring-gull species (DeckGull, CorvidGull).
	##
	## s43 played the flight wingbeat through creature_swim's vertex sine and the owner's
	## verdict was that nothing visibly changed. The ceiling is the asset: the herring gull
	## is ONE unrigged surface authored with the wings FOLDED, so a vertex sine on it peaks
	## at a ~3 cm shimmer — invisible at gameplay distance. Visible flapping needs geometry
	## that moves, so: two tapered PrismMesh panels (the seal-flipper idiom) on shoulder
	## pivots, rotating about the body's fore-aft axis — a dihedral beat.
	##
	## HIDDEN ON THE GROUND. The folded wings are already painted into the authored mesh,
	## so a grounded bird wearing this pair has four wings; the panels show only while the
	## species' own airborne state says so — every write to that state flips them, never a
	## parallel flag that can drift. Solid prisms rather than quads because a flying bird
	## is mostly seen from BELOW, where a single-sided face would cull away.
	const RAISE := 1.0        ## rad — both wings thrown straight up at flush
	const HOLD_S := 0.12      ## s the raise is held before the first downstroke
	const GLIDE := 0.15       ## rad — glide dihedral; gulls glide wings-up, never flat
	const FLAP_BASE := 0.18   ## rad — centreline the stroke swings about
	var l: Node3D
	var r: Node3D
	var phase: float = 0.0    ## integrated sim dt * rate — see drive()
	var base: float = GLIDE   ## smoothed dihedral centreline, rad
	var amp: float = 0.0      ## smoothed stroke amplitude, rad

	## Build both panels under the post-attach model. Every dimension is derived from the
	## model's own merged local-frame bounds, never hand-typed (the trap file's rule), so
	## a SIZE_M change or a re-rolled asset re-fits the wings for free. Frame facts from
	## the herring_gull FACING_OVERRIDES entry: no yaw, head at MIN local Z — so local -Z
	## is the bird's forward, and the shoulder line sits 0.30 of the body length behind
	## the min-z end at mid-height. Roots tuck to 35% of the half-width so the stroke
	## never opens a gap along the flank: the root chord IS the rotation axis.
	func build(model: Node3D, tint: Color) -> void:
		var acc := AABB()
		var first := true
		var inv: Transform3D = model.global_transform.affine_inverse()
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var src := n as MeshInstance3D
			if src.mesh == null:
				continue
			var box: AABB = (inv * src.global_transform) * src.get_aabb()
			acc = box if first else acc.merge(box)
			first = false
		if first:
			return
		var body_l: float = acc.size.z
		var shoulder := Vector3(acc.position.x + acc.size.x * 0.5,
			acc.position.y + acc.size.y * 0.5, acc.position.z + body_l * 0.30)
		# One flat plumage tone for both panels, at the corvid slate's 0.02 emission —
		# enough self-light to read against a dusk sky, nowhere near main.gd's 0.8 glow
		# threshold.
		var mat: StandardMaterial3D = BloomFauna.glow_mat(tint, 0.02)
		for side in [-1.0, 1.0]:
			var pivot := Node3D.new()
			model.add_child(pivot)
			pivot.position = shoulder + Vector3(side * acc.size.x * 0.5 * 0.35, 0.0, 0.0)
			pivot.visible = false
			var mi := MeshInstance3D.new()
			var pm := PrismMesh.new()
			# The prism's XY triangle, laid flat by the rotation below, IS the planform:
			# root chord (prism x) 0.35 of the body along the flank, span (prism y) 0.50
			# of the body out to a point, extrusion the panel's thickness. left_to_right
			# displaces the apex along prism x — mapped fore-aft here — sweeping the tip
			# 20% of the chord tailward, mirrored by the sign of `side`.
			pm.size = Vector3(body_l * 0.35, body_l * 0.50, body_l * 0.02)
			pm.left_to_right = 0.5 - side * 0.2
			pm.material = mat
			mi.mesh = pm
			# YXZ euler: prism +Y (apex) lands on the outboard ±X, prism +X on the body
			# axis, extrusion vertical. The mesh is centred, so the half-span shift puts
			# the root chord exactly on the pivot.
			mi.rotation = Vector3(PI * 0.5, side * PI * 0.5, 0.0)
			mi.position = Vector3(side * body_l * 0.25, 0.0, 0.0)
			pivot.add_child(mi)
			if side < 0.0:
				l = pivot
			else:
				r = pivot

	## The flush-instant silhouette the owner asked for: both wings snapped straight up
	## and held. Phase starts at the stroke TOP, so the first beat after the hold falls
	## out of the raise as a downstroke instead of teleporting to mid-cycle.
	func takeoff() -> void:
		phase = PI * 0.5
		base = RAISE
		amp = 0.0
		shown(true)

	## One thinking frame of beat. `delta` is the species' ACCUMULATED decimated dt (the
	## AiBudget prologue's delta), so d(phase)/d(wall clock) rides through any stride —
	## and the phase is INTEGRATED (`phase += rate * dt`), never `t * rate`: the rate
	## slides between launch/cruise/glide, and `t * rate` rewinds the stroke every time
	## the rate drops (the trap file's mutable-rate trap). `airtime` is the species' own
	## airborne clock (_flushing / _fleeing); `gliding` is the s43 flap/glide phrasing
	## bit, shared with the shader ripple so skin and geometry beat as one wing. base/amp
	## chase their targets through 1-exp smoothing — stable at AiBudget.MAX_STEP, where
	## delta*k lerps are not — so a glide folds the stroke out instead of freezing it
	## mid-swing, and the next burst grows back from wherever the phase stopped.
	func drive(delta: float, airtime: float, gliding: bool) -> void:
		if not (is_instance_valid(l) and is_instance_valid(r)):
			return
		var k: float = 1.0 - exp(-10.0 * delta)
		if airtime < HOLD_S:
			base = RAISE
			amp = 0.0
		elif gliding:
			base = lerpf(base, GLIDE, k)
			amp = lerpf(amp, 0.0, k)
		else:
			# Launch climbs on deep fast strokes (~0.9 rad at 6.6 Hz), settling into the
			# cruise burst — the same 4.8 + launch * 1.8 curve the shader ripple runs.
			var launch: float = clampf(1.0 - airtime / 0.8, 0.0, 1.0)
			phase += TAU * (4.8 + launch * 1.8) * delta
			base = lerpf(base, FLAP_BASE, k)
			amp = lerpf(amp, 0.55 + launch * 0.35, k)
		var ang: float = base + sin(phase) * amp
		r.rotation.z = ang     # +z rolls the +X tip up...
		l.rotation.z = -ang    # ...and the -X tip needs the mirror to rise with it

	func shown(on: bool) -> void:
		if is_instance_valid(l):
			l.visible = on
		if is_instance_valid(r):
			r.visible = on

# -------------------------------------------------------------- DeckGull
class DeckGull extends Node3D:
	## A gull DOWN ON THE DECK, strutting between pecks — the ordinary life the rig
	## still carries. Walks its little patch; feels you coming and FLUSHES: leaps,
	## climbs away to nothing, and lands again somewhere else a minute later.
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MOVE := preload("res://scripts/world/fauna_move.gd")
	const MODEL_PATH := "res://assets/models/fauna/herring_gull/herring_gull.glb"
	## Standing height at the crown, metres — a real herring gull is 0.35-0.40m on its
	## feet. attach() normalises the LONGEST axis, which on this mesh is bill-to-tail
	## (1.00 raw against 0.94 of height), so 0.42 lands the crown at 0.396m.
	const SIZE_M := 0.42
	var _home: Vector3
	var _target: Vector3
	var _t: float = 0.0
	var _skip: Array[RID] = []    ## fauna bodies the strut probe must ignore
	var _bound: bool = false
	var _peck: float = 0.0        ## countdown to next peck pause
	var _flush_dir: Vector3
	var _flushing: float = -1.0   ## <0 grounded; else seconds airborne
	var _regen: float = 0.0       ## respawn countdown after flying off
	var _gen_mats: Array = []
	var _model: Node3D
	var _wings: GullWings = null  ## overlay flight wings — GullWings explains why they exist
	var _closest: float = 1e9     ## closest the player has crept this landing (threat roll)
	var _look_cd: float = 0.0     ## idle head-turn clock
	var _look_yaw: float = 0.0
	## LEGS: PAINTED INTO THE MESH — THE CEILING, AND WHY THEY DO NOT TUCK IN FLIGHT.
	##
	## A real gull trails its legs straight back under the tail the moment it is up and drops
	## them again to land ("seagull legs should tuck when flying"). This bird cannot: there is
	## no leg to pose. Measured off the asset, not assumed —
	## assets/models/fauna/herring_gull/herring_gull.glb is ONE node holding ONE mesh with ONE
	## primitive: 250,356 vertices and 453,620 triangles carrying POSITION, NORMAL and
	## TEXCOORD_0 and nothing else. No skin, no joints, no animation clips, no morph targets.
	## The legs and the webbed feet are simply the bottom quarter of that single welded
	## surface — 36,993 verts below 0.25 of local height, of which 23,951 are in the bottom
	## 5%: the feet, splayed across the full 0.374 body width. At SIZE_M that is 0.099 m of
	## undercarriage and a 0.157 m span of foot hanging under a 0.396 m bird, which is why it
	## reads at the flush.
	##
	## THREE WAYS TO FAKE IT AND WHY NONE OF THEM IS TAKEN:
	##   * hide the legs, fly an overlay pair (the GullWings idiom above) — needs the legs to
	##     be their own MeshInstance3D. They are not. Hiding them hides the whole bird.
	##   * bend them in the vertex program — with no weights, the only selector available is a
	##     BOX in local space. The waist is at least in the right place (13,042 verts spread
	##     over the whole 0.05-0.25 height band against 24,782 in the 0.25-0.28 band alone —
	##     the shanks are thin and the belly above them is dense), but the surface is
	##     continuous across it: an unfeathered rotation TEARS the bird at the hip and a
	##     feathered one drags the lower belly round with the legs. It also cannot be written
	##     from this file — the vertex program lives in creature_anim.gd and would need a new
	##     uniform. This is the cat's "deforming face without face geometry" case
	##     (docs/CAT_RIG_CEILING.md §2): worse than leaving it still.
	##   * a box on height alone is not even the right box. 1,617 of those sub-quarter verts
	##     are the TAIL TIP, at local z +0.2..+0.5, the other end of the animal.
	##
	## RE-ROLL ASK, if this is ever worth an asset pass: a RIGGED gull — hip / tibiotarsus /
	## tarsometatarsus / toe per side, weights stopping at the belly line — and wing bones in
	## the same pass. Wings would retire GullWings entirely (those overlay panels exist for
	## exactly this reason: the mesh is authored wings-FOLDED and cannot open them), so one
	## rigged asset closes both holes. Nothing procedural closes either.
	##
	## The history, kept because it is why this class calls ANIM.attach and not ANIM.replace:
	## the old mesh was a dark long-legged wader whose model sank a quarter-metre into the
	## plating, so two procedural pivot-and-shin legs were built here to be the feet the
	## player actually saw (attach does not hide pre-existing geometry; replace does). The
	## herring gull brings its own pink legs and webbed feet, so keeping the procedural pair
	## would have put FOUR legs under one bird — and the built ones were glowing amber
	## cylinders that looked nothing like the mesh's. They are gone; the gait lives in the
	## body (see the strut below), which costs a stiffer stride and buys a bird that reads as
	## a real animal from two metres away.
	var _lift: float = 0.0   ## metres the model was raised to stand its feet on the deck
	var _snapped: bool = false   ## has the deck under this landing been probed yet?

	func _init(home: Vector3) -> void:
		_home = home
		_target = home

	func _ready() -> void:
		# THE CAT HUNTS THESE. A group is how it finds them: ship_cat sweeps "deck_gull" for
		# something to stalk, and the alternative — walking the whole tree looking for an inner
		# class by type — is both slower and silently broken by any refactor. Grouping is the
		# repo's own idiom (gull_nest, snail_lamp, player, ship_cat all do it).
		add_to_group("deck_gull")
		var gen: Dictionary = ANIM.attach(self, MODEL_PATH, SIZE_M, ANIM.Mode.FLAP,
			0.012, 0.6, Color(0.30, 0.85, 0.80), randf() * TAU)
		if gen.is_empty():
			queue_free()   # no mesh, no bird — walkers have no procedural fallback
			return
		_model = gen["model"]
		_gen_mats = gen["mats"]
		# The mesh is authored centred on its bounds, so left alone the bird stands with
		# its knees in the plating. Lift it by its own measured half-height instead.
		_lift = ANIM.ground(self, _model)
		ANIM.drive(_gen_mats, 0.6, 0.15)
		# Flight wings, hidden until a flush. Pale gull-grey, splitting the mantle/white
		# difference in one flat tone — the panels are seen from above and below in the
		# same three-second flight.
		_wings = GullWings.new()
		_wings.build(_model, Color(0.78, 0.82, 0.84))
		global_position = _home
		_peck = randf_range(2.0, 5.0)
		# Grab it if you can reach it before it flushes — crouch-sneak to close the gap.
		var touch := FaunaTouch.new("Deck Gull", 0.9, _grab_verbs, _grab_act)
		add_child(touch)

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_t += delta
		if _regen > 0.0:
			_regen -= delta
			if _regen <= 0.0:
				# Lands again a few metres from home, grounded state reset.
				global_position = _home + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
				_flushing = -1.0
				if _wings:
					_wings.shown(false)   # grounded: the authored folded wings take over
				_snapped = false   # new spot, new deck height — re-probe before it struts
				visible = true
				_closest = 1e9   # a fresh bird lets the player re-earn the flush
				if _model:
					# Out of the climb attitude — it comes down level, on its feet.
					_model.rotation.x = 0.0
					_model.rotation.z = 0.0
					_model.position.y = _lift
				ANIM.drive(_gen_mats, 0.6, 0.15, 0.012)
			return
		var player: Node3D = get_tree().get_first_node_in_group("player")
		if _flushing >= 0.0:
			# AIRBORNE — and three things changed here on the owner's call ("their wings
			# should flap, wings up when they fly away, and they cant fly through walls").
			_flushing += delta
			if not _bound:
				_skip = BloomFauna.fauna_bodies(self)
				_bound = true
			# 1. THE WINGS BEAT, DRIVEN EVERY THINKING FRAME. A real gull CLIMBS on deep
			# fast strokes and then alternates flap bursts with glides — the beat drops
			# out entirely for 0.8 s of every 2.4, which is the single most bird-reading
			# thing a flight cycle does. s43 played this phrasing through the vertex sine
			# alone and the owner could not see it: the mesh is one unrigged surface
			# authored wings-FOLDED, so the ripple peaks ~3 cm — a bird held stiff. The
			# ripple stays (feather shimmer over the body), but the visible stroke is now
			# GEOMETRY — the overlay panels, beating the same phrasing off the same two
			# locals, so skin and silhouette cannot drift apart.
			var launch: float = clampf(1.0 - _flushing / 0.8, 0.0, 1.0)
			var gliding: bool = _flushing > 1.6 and fposmod(_flushing, 2.4) > 1.6
			var beat_rate: float = (1.1 if gliding else 4.8) + launch * 1.8
			var beat_amp: float = (0.05 if gliding else 0.15) + launch * 0.09
			ANIM.drive(_gen_mats, beat_rate, 0.25, beat_amp)
			if _wings:
				_wings.drive(delta, _flushing, gliding)
			# 2. THE PATH IS WALL-TESTED. This line used to be a bare
			# `global_position += dir * 6.5 * delta` — a straight uncollided run of up to
			# 20 m that passed through bulkheads, containers and the bunkhouse whole.
			# FaunaMove.swim_clear is the exact probe the fish and the shark already fly
			# their 3D moves through (its own doc names flyers), stopping short of any
			# surface; on a block the bird banks away along whichever tangent is open and
			# trades the lost ground for climb, which is also what a real gull does when a
			# wall fills its windscreen.
			var climb: float = 3.2 + launch * 1.6
			var want: Vector3 = global_position + _flush_dir * delta * 6.5 \
				+ Vector3(0, delta * climb, 0)
			var res: Dictionary = MOVE.swim_clear(self, global_position, want, 0.30, _skip)
			if bool(res["blocked"]):
				for side in [1.0, -1.0]:
					var alt: Vector3 = _flush_dir.rotated(Vector3.UP, side * 0.9)
					var probe: Dictionary = MOVE.swim_clear(self, global_position,
						global_position + alt * 1.2 + Vector3(0, 0.6, 0), 0.30, _skip)
					if not bool(probe["blocked"]):
						_flush_dir = alt
						break
			global_position = res["pos"]
			rotation.y = lerp_angle(rotation.y,
				atan2(_flush_dir.x, _flush_dir.z) + PI, 1.0 - exp(-6.0 * delta))
			# 3. THE TAKEOFF POSE IS ITS OWN BEAT. Launch: nose hauled up hard and fast
			# (0.45 rad at rate 12) — the claw for height. Cruise: it settles to a shallow
			# 0.16 and picks up a small glide-phase pitch trim, nose dipping as the beat
			# stops, exactly the see-saw of flap-climb / glide-sink.
			if _model:
				var pitch: float = 0.45 if launch > 0.0 else (0.06 if gliding else 0.16)
				_model.rotation.x = lerpf(_model.rotation.x, pitch,
					1.0 - exp(-(12.0 if launch > 0.0 else 4.0) * delta))
				_model.rotation.z = lerpf(_model.rotation.z, 0.0, 1.0 - exp(-5.0 * delta))
			if _flushing > 3.0:
				visible = false
				_regen = randf_range(45.0, 90.0)
			return
		if not _snapped:
			_snapped = true
			_snap_to_deck()
		# Grounded threat: track the closest the player has crept and roll a flush at each
		# ~1m they close inside 10m. Crouch-sneaking CUTS the odds (crouch_factor 0.3)
		# rather than skipping the roll: sneaking should improve your chances, not make
		# you flatly undetectable, or the grab stops being a gamble worth taking.
		# Non-crouched and right on top of it always flushes.
		if player:
			var res: Array = BloomFauna.gull_flush_roll(player, global_position, _closest, 10.0, 0.34, 0.3)
			_closest = res[1]
			var crouched: bool = player.get("crouching") == true
			if res[0] or (not crouched and player.global_position.distance_to(global_position) < 1.5):
				_flush(player)
				return
		# Strut / peck loop.
		_peck -= delta
		if _peck <= 0.0:
			_target = _home + Vector3(randf_range(-2.2, 2.2), 0, randf_range(-2.2, 2.2))
			_peck = randf_range(2.5, 6.0)
		var to: Vector3 = _target - global_position
		to.y = 0.0
		if to.length() > 0.15:
			if not _bound:
				_skip = BloomFauna.fauna_bodies(self)
				_bound = true
			# Strut the deck without walking through crates or rails: the step is wall-tested,
			# and if it boxes itself in it just picks a fresh spot to peck at.
			var stepv: Vector3 = to.limit_length(delta * 0.55)
			var moved: Vector3 = MOVE.step(self, stepv, 0.2, 0.14, _skip)
			if moved.length() < stepv.length() * 0.5:
				_target = _home + Vector3(randf_range(-2.2, 2.2), 0.0, randf_range(-2.2, 2.2))
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z) + PI, delta * 5.0)
			if _model:
				_model.rotation.z = sin(_t * 7.0) * 0.06   # the waddle
				# The stride, without legs to swing: the body rocks side to side and rides
				# up on each step. UPWARD only (absf) and a centimetre at most, so the
				# webbed feet skim the plating and never dip through it. Both run at the
				# waddle's frequency — one gait, not two ticks — and the pitch lags a
				# quarter cycle so the head leads the body the way a walking gull's does.
				_model.position.y = _lift + absf(sin(_t * 7.0)) * 0.010
				_model.rotation.x = sin(_t * 7.0 - PI * 0.5) * 0.035
		elif _model:
			# Pecking: quick bow, twice, then upright — reads as feeding. NEGATIVE x is
			# the bow: this mesh faces -Z (see FACING_OVERRIDES), so +x pitches it nose-UP.
			_model.rotation.x = -maxf(sin(_t * 5.0), 0.0) * 0.5 * maxf(sin(_t * 0.7), 0.0)
			_model.rotation.z = lerpf(_model.rotation.z, 0.0, delta * 4.0)
			_model.position.y = lerpf(_model.position.y, _lift, delta * 8.0)
			# Idle head-turns: it glances around on its own organic clock.
			_look_cd -= delta
			if _look_cd <= 0.0:
				_look_cd = randf_range(1.4, 4.2)
				_look_yaw = rotation.y + randf_range(-1.3, 1.3)
			rotation.y = lerp_angle(rotation.y, _look_yaw, delta * 2.5)

	## Put the bird down on whatever it is actually standing over, and remember that as the
	## height of this patch.
	##
	## Two of the four spawn points are hand-typed at y 18.75 against a topside deck that
	## rig_builder.gd puts at DECK_Y = 18.0 — three quarters of a metre of daylight under
	## the bird. It went unnoticed for as long as it did because the OLD mesh was a wader
	## whose visible feet were procedural sticks nobody had measured, and because the
	## constants read plausibly next to the rail perches at the same y. A photoreal gull
	## hovering over the plating is the first thing anyone sees. Probing beats re-typing
	## the constants: it also re-grounds the bird wherever it happens to land after a
	## flush, and it stays right the next time a deck moves.
	## Deferred out of _ready deliberately — the deck is CSG and has no collider to hit
	## until physics has stepped once.
	func _snap_to_deck() -> void:
		var world: World3D = get_world_3d()
		if world == null:
			return
		var from: Vector3 = global_position + Vector3(0, 1.0, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 4.0, 0))
		q.collision_mask = 1          # world geometry, same as the strut probe
		q.collide_with_areas = false
		if not _bound:
			_skip = BloomFauna.fauna_bodies(self)
			_bound = true
		q.exclude = _skip             # don't perch on another animal's collider
		var hit: Dictionary = world.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return                    # nothing under it — leave the authored height alone
		global_position.y = hit["position"].y
		_home.y = global_position.y

	## Airborne flush: leap up and away from the player, then gone until it re-lands.
	func _flush(player: Node3D) -> void:
		_flushing = 0.0
		var away: Vector3 = (global_position - player.global_position) if player else Vector3(1, 0, 0)
		away.y = 0.0
		_flush_dir = away.normalized() if away.length() > 0.1 else Vector3(1, 0, 0)
		# The launch-instant burst — deepest and fastest stroke of the whole flight. The
		# airborne branch re-drives this every thinking frame from here on (flap bursts
		# alternating with glides), so this line only has to sell frame one.
		ANIM.drive(_gen_mats, 6.4, 0.25, 0.24)
		if _wings:
			_wings.takeoff()   # wings thrown up and held ~0.12 s — the flush silhouette
		AudioDirector.play_one_shot("wingbeat", global_position, -8.0)   # wings, not voice
		Journal.discover("creature_gull")

	## Grabbable only while grounded and within reach — sneak in before it bolts.
	func _grab_verbs() -> Array:
		if _flushing >= 0.0 or _regen > 0.0 or not visible:
			return []
		var player: Node3D = get_tree().get_first_node_in_group("player")
		if player == null or player.global_position.distance_to(global_position) > 1.6:
			return []
		return ["GRAB"]

	func _grab_act(_verb: String, _player: Node3D) -> void:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if _flushing >= 0.0 or _regen > 0.0 or not visible:
			return
		if not PlayerState.add_item("raw_sea_bird"):
			if hud and hud.has_method("toast"):
				hud.toast("No room for it — the gull thrashes free.")
			return
		Journal.discover("creature_gull")
		AudioDirector.play_one_shot("wingbeat", global_position, -6.0)   # it thrashes, it doesn't sing
		visible = false
		_flushing = -1.0
		if _wings:
			_wings.shown(false)   # flag and wings move together, at every write
		_regen = randf_range(60.0, 120.0)   # another gull drops onto the deck later
		if hud and hud.has_method("toast"):
			hud.toast("You get both hands round it before it can bolt. A sea-bird for the pot.")

# -------------------------------------------------------------- ReefFish
class ReefFish extends Node3D:
	## A loose school of mutated reef fish at diving depth around a rig leg — colour
	## variants of the one bait-fish mesh (albedo tint; the rim glow that used to ride
	## with it fell to the owner's 2026-08-06 no-glow call), each on its own wander orbit.
	## The reason to duck your head under and look.
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/bait_fish/bait_fish.glb"
	const VARIANTS := [
		[Color(1.0, 1.0, 1.0), Color(0.25, 0.95, 0.88)],   # pearl / teal — the Bloom norm
		[Color(0.85, 0.9, 1.2), Color(0.45, 0.65, 1.0)],   # blue-shifted
		[Color(1.2, 0.95, 0.8), Color(1.0, 0.55, 0.18)],   # the rust snail's amber lineage
	]
	const FISH_ID := "fish_copper_sprat"
	var _centre: Vector3
	var _fish: Array = []   ## [{node, mats, r, h, spd, ph, gone}]

	func _init(centre: Vector3) -> void:
		_centre = centre

	func _ready() -> void:
		for i in range(9):
			var f := Node3D.new()
			add_child(f)
			var gen: Dictionary = ANIM.attach(f, MODEL_PATH, 0.3, ANIM.Mode.UNDULATE,
				0.1, 2.4, VARIANTS[i % 3][1], float(i) * 0.7)
			if gen.is_empty():
				f.queue_free()
				continue
			for m in gen["mats"]:
				(m as ShaderMaterial).set_shader_parameter("tint", VARIANTS[i % 3][0])
			# Glow retired (owner, 2026-08-06: "remove any unnatural glow overlay, should be
			# just raw graphic texture") — this drive carried 0.5 of rim energy, the loudest
			# fish light in the game after the herring's. Rate-only now; the tint variants
			# alone carry the mutation read.
			ANIM.drive(gen["mats"], 2.4, 0.0)
			# THE ORBIT GOES ROUND THE PILLAR, NOT INTO IT — the owner's "they go too close
			# and snap around". The old seed drew radii of 1.2-3.2 m around a centre sitting
			# ON a caisson FACE, so a large arc of every orbit was geometrically inside the
			# concrete; swim_clear hard-stopped the fish at the steel and the next frame's
			# wall-clock recompute snapped it back onto the ideal circle. s43 moved the
			# CENTRES onto the leg centres and widened the rings to 5.0-6.8 m; the owner
			# still saw the shoal hugging the steel ("The schools ... should circle wider
			# around the poles", 2026-08-06), so the ring is now 8.0-11.5 m — clear of the
			# leg's 4.24 m half-diagonal by 3.7+ m, clear of the kelp stand's 6.0 m
			# holdfast ring, open water the whole lap.
			#
			# THE BAND DROPS WITH IT, -3.8..-5.6 (was -1.6..-4.2), because the top of the
			# old band was inside the PONTOON: the slabs run y -3.05..0.95 over |z| 8..16
			# and both spawn legs stand at z ±12, so every fish above -3.05 spent the
			# inboard arc of its lap stopped against concrete — the safety ray "should
			# never fire" claim below was wrong for half the shoal. -3.8 plus the +-0.3
			# height sway in _process tops out at -3.5, which clears the slab's -3.05
			# underside by more than the 0.35 clearance underwater_world grants its own
			# schools — so "water on every side" is finally true of the whole band, at
			# any radius.
			#
			# SPEED SCALES DOWN AS THE RADIUS SCALES UP, 0.10-0.19 rad/s against the old
			# 0.16-0.30: angular rate times the new radius lands on the same 0.8-2.2 m/s
			# swim the s43 ring had, so the wider circle reads as the same unhurried fish
			# on a longer lap, not a speed-up. (Constant per fish, integrated below — the
			# tunable never multiplies the clock inside a sine.)
			#
			# PHASE IS EVENLY DEALT, i * TAU/9 plus a small personal wander — the pelagic
			# pods' own spacing idiom — so nine fish spread round the whole ring instead of
			# clumping wherever randf landed them. `_a` is the fish's OWN integrated angle:
			# the old code recomputed position from Time.get_ticks_msec every frame, which
			# is the wall-clock-inside-a-sine trap AGENT_TRAPS documents, and it is also
			# WHY it snapped — an absolute clock cannot remember where the fish actually
			# was after a collision stop.
			_fish.append({"node": f, "r": randf_range(8.0, 11.5), "h": randf_range(-5.6, -3.8),
				"spd": randf_range(0.10, 0.19) * (1.0 if i % 2 == 0 else -1.0),
				"ph": randf_range(0.0, 0.5), "gone": 0.0,
				"a": float(i) * TAU / 9.0})
			# A swimming player can grab an individual fish out of the shoal.
			var idx := _fish.size() - 1
			var touch := FaunaTouch.new("Reef Fish", 0.45,
				func() -> Array: return _grab_verbs(idx),
				func(v: String, pl: Node3D) -> void: _grab_fish(idx, pl))
			f.add_child(touch)
		if _fish.is_empty():
			queue_free()

	func _grab_verbs(idx: int) -> Array:
		if idx >= _fish.size():
			return []
		var fd: Dictionary = _fish[idx]
		if fd["gone"] > 0.0 or not (fd["node"] as Node3D).visible:
			return []
		var player: Node3D = get_tree().get_first_node_in_group("player")
		if player == null or player.get("swimming") != true:
			return []
		if player.global_position.distance_to((fd["node"] as Node3D).global_position) > 1.2:
			return []
		return ["GRAB"]

	func _grab_fish(idx: int, _player: Node3D) -> void:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if idx >= _fish.size():
			return
		var fd: Dictionary = _fish[idx]
		if fd["gone"] > 0.0 or not (fd["node"] as Node3D).visible:
			return
		if not PlayerState.add_item(FISH_ID):
			if hud and hud.has_method("toast"):
				hud.toast("Your hands are full — it slips away into the murk.")
			return
		fd["gone"] = randf_range(50.0, 110.0)   # rejoins the shoal later
		(fd["node"] as Node3D).visible = false
		Journal.discover("creature_fiddler_shoal")
		AudioDirector.play_one_shot("splash", (fd["node"] as Node3D).global_position, -16.0)
		if hud and hud.has_method("toast"):
			hud.toast("A quick grab in the deep colour and you've got one.")

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		for f in _fish:
			if f["gone"] > 0.0:
				f["gone"] -= delta
				if f["gone"] <= 0.0:
					(f["node"] as Node3D).visible = true
			# The angle is INTEGRATED (a += spd*dt), not derived from the wall clock, so a
			# collision stop, a decimated frame, or a pause leaves the fish where it truly
			# is instead of teleporting it back onto an absolute schedule. The breathing
			# radius and slow height sway ride the same personal angle.
			f["a"] = fposmod(float(f["a"]) + float(f["spd"]) * delta, TAU)
			var a: float = float(f["a"])
			var r: float = float(f["r"]) + sin(a * 1.7 + float(f["ph"]) * TAU) * 0.45
			var pos: Vector3 = _centre + Vector3(cos(a) * r,
				float(f["h"]) + sin(a * 2.3) * 0.3, sin(a) * r)
			var node: Node3D = f["node"]
			# The safety ray stays (another session can always bolt something new to the
			# leg), but with the orbit clear of the concrete it should never fire.
			pos = FaunaMove.swim_clear(node, node.global_position, pos, 0.25)["pos"]
			# EASED toward the target, and the heading is REMEMBERED — the two fixes every
			# other motion system in this file already carries (reef_fish.gd: "the heading
			# is remembered, not re-derived"): a per-frame look_at down the raw displacement
			# is what whipped the facing around on every correction.
			var cur: Vector3 = node.global_position
			var nxt: Vector3 = cur.lerp(pos, 1.0 - exp(-3.0 * delta))
			var vel: Vector3 = nxt - cur
			node.global_position = nxt
			if vel.length() > 0.0005:
				var want_fwd: Vector3 = vel.normalized()
				var cur_fwd: Vector3 = -node.global_transform.basis.z
				var blend: Vector3 = cur_fwd.slerp(want_fwd, 1.0 - exp(-4.0 * delta))
				if blend.length_squared() > 0.0001:
					node.look_at(nxt + blend, Vector3.UP)
		var player: Node3D = get_tree().get_first_node_in_group("player")
		# 13 m, not the old 8: the discovery range is measured from the LEG the shoal
		# orbits, and the 2026-08-06 ring runs 8.0-11.5 m out — at 8.0 a swimmer sharing
		# water with the fish could no longer log them without touching the pillar.
		if player and player.get("swimming") and player.swimming 				and player.global_position.distance_to(_centre) < 13.0:
			Journal.discover("creature_fiddler_shoal")

# ------------------------------------------------------------ FloraPatch
class FloraPatch extends Node3D:
	## One placed piece of the Bloom growing on the rig: kelp, creeper-covered pipe,
	## anemone clump. Static placement, alive through the SWAY/CIRRI shader. Frees
	## itself when the mesh hasn't been generated yet — safe to spawn optimistically.
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	var _slug: String
	var _size: float
	var _mode: int
	var _amp: float
	var _rate: float
	var _energy: float

	func _init(slug: String, size: float, mode: int, amp: float, rate: float, energy: float) -> void:
		_slug = slug
		_size = size
		_mode = mode
		_amp = amp
		_rate = rate
		_energy = energy

	func _ready() -> void:
		var path := "res://assets/models/fauna/%s/%s.glb" % [_slug, _slug]
		var gen: Dictionary = ANIM.attach(self, path, _size, _mode, _amp, _rate,
			Color(0.25, 0.95, 0.88), randf() * TAU)
		if gen.is_empty():
			queue_free()
			return
		ANIM.drive(gen["mats"], _rate, _energy)
		# Ground the mesh: flora pivots are wherever the generator left them, so drop
		# the model until its lowest point sits at this patch's origin.
		var model: Node3D = gen["model"]
		var low: float = 0.0
		var first := true
		for mi in find_children("*", "MeshInstance3D", true, false):
			var w: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			low = w.position.y if first else minf(low, w.position.y)
			first = false
		model.position.y -= (low - global_position.y)

# ------------------------------------------------------------ Rust Snail
class RustSnail extends Node3D:
	## The one that EATS THE RIG (Codex §54b). Where the lamp snails graze the legs for
	## algae, these rasp the steel itself — you find them at the end of a scoured track
	## in the corrosion, shell grown the colour of what they consume. Amber, not teal:
	## a Bloom creature that took its palette from rust instead of light. They are the
	## reason the handrails thin out, and they do not care that you are watching.
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/rust_snail/rust_snail.glb"
	const AMBER := Color(1.0, 0.55, 0.18)
	var _gen_mats: Array = []
	var _t: float
	var _from: Vector3
	var _to: Vector3
	var _idx: int
	var _glow_mats: Array[StandardMaterial3D] = []
	var _crawler: GroundCrawler       ## wall-aware patrol along the scoured seam
	var _carried_by: Node3D = null    ## set while the player is carrying this live snail
	var _fed: bool = false            ## took a greens item; breeds when a fed sibling is close
	var _is_baby: bool = false        ## spawned by breeding — permanent, ~0.4 scale, grows in
	var _grow_h: float = 0.0          ## game-hours since birth (baby only)
	var _body_pivot: Node3D = null    ## baby-only scale wrapper (see BloomFauna.shrink_to_baby)

	func _init(idx: int, from_p: Vector3, to_p: Vector3) -> void:
		_idx = idx
		_from = from_p
		_to = to_p
		_t = idx * 3.1

	func _ready() -> void:
		add_to_group("snail_rust")
		var shell := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.3
		sm.height = 0.44
		sm.is_hemisphere = true
		var shell_mat := BloomFauna.glow_mat(Color(0.42, 0.22, 0.1), 0.0)
		shell_mat.roughness = 0.95        # flaking oxide, not a wet shell
		sm.material = shell_mat
		shell.mesh = sm
		add_child(shell)
		var foot := MeshInstance3D.new()
		var fm := CapsuleMesh.new()
		fm.radius = 0.14
		fm.height = 0.62
		fm.material = BloomFauna.glow_mat(Color(0.16, 0.14, 0.13), 0.0)
		foot.mesh = fm
		foot.rotation.x = deg_to_rad(90)
		foot.position.y = -0.1
		add_child(foot)
		# Heat-glow deep in the whorls — the only warm light on the whole rig.
		for i in range(3):
			var vent := MeshInstance3D.new()
			var vm := SphereMesh.new()
			vm.radius = 0.035
			vm.height = 0.07
			var m := BloomFauna.glow_mat(AMBER, 1.2)
			_glow_mats.append(m)
			vm.material = m
			vent.mesh = vm
			vent.position = Vector3(-0.12 + i * 0.12, 0.12 + i * 0.04, -0.1)
			add_child(vent)
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 0.62, ANIM.Mode.PEDAL,
			0.028, 0.8, AMBER)
		if not gen.is_empty():
			_gen_mats = gen["mats"]
			BloomFauna.ground_model(self, gen["model"])   # foot flush to the rail/seam
		# A real patrol, not a rigid oscillation: it works the seam end to end, turns at
		# each end (or wherever a rail blocks it), and pauses to rasp. Grounds every frame.
		global_position = _from
		var mid: Vector3 = _from.lerp(_to, 0.5)
		_crawler = GroundCrawler.new(mid, _from.distance_to(_to) * 0.5, 0.1, 700 + _idx,
			0.2, 0.15, _from.y, _to - _from)
		# Grab it like any other loose item — it comes off the rail into your hands. Crouch
		# for COLLECT instead; carrying greens and unfed offers FEED first (same priority
		# order as the lamp snail and HarborSeal's FEED-beats-PET precedent).
		var touch := FaunaTouch.new("Rust Snail", 0.5,
			func() -> Array:
				if BloomFauna.player_crouching(self):
					return ["COLLECT"]
				var out: Array = ["GRAB"]
				if not _is_baby and not _fed and BloomFauna.has_greens():
					out.push_front("FEED")
				return out,
			_touch_act)
		add_child(touch)
		if _is_baby:
			_body_pivot = BloomFauna.shrink_to_baby(self, BloomFauna.BABY_SCALE)

	func _touch_act(verb: String, player: Node3D) -> void:
		match verb:
			"FEED":
				_feed(player)
			"COLLECT":
				_collect(player)
			_:
				BloomFauna.grab_snail(self, player)

	func _feed(_player: Node3D) -> void:
		if _is_baby or _fed or not BloomFauna.consume_greens():
			return
		_fed = true
		Journal.discover("system_snail_breeding")
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toast"):
			hud.toast("It takes the greens — the whorls glow a little hotter.")

	func _breed_with(partner: Node3D) -> void:
		var mid: Vector3 = (global_position + partner.global_position) * 0.5
		var baby := RustSnail.new(5000 + (randi() % 100000), mid, mid + Vector3(1.4, 0, 0))
		baby._is_baby = true
		get_parent().add_child(baby)
		baby.global_position = mid
		_fed = false
		partner.set("_fed", false)
		Journal.discover("creature_snail_baby")
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toast"):
			hud.toast("Two fed shells lean together, and a smaller one is rasping between them.")

	func _collect(_player: Node3D) -> void:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if not PlayerState.add_item("snail_live"):
			if hud and hud.has_method("toast"):
				hud.toast("Hands full — it stays where it is.")
			return
		Journal.discover("item_snail_live")
		if hud and hud.has_method("toast"):
			hud.toast("Into the pack it goes, still working the rail with its foot.")
		queue_free()

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_t += delta
		if _is_baby:
			_grow_h += delta * GameClock.time_scale * BloomFauna.game_hour_per_sec()
			if _body_pivot:
				_body_pivot.scale = Vector3.ONE * lerpf(BloomFauna.BABY_SCALE, 1.0,
					clampf(_grow_h / BloomFauna.GROW_HOURS, 0.0, 1.0))
			if _grow_h >= BloomFauna.GROW_HOURS:
				_is_baby = false
		elif _fed:
			var partner: Node3D = BloomFauna.find_breed_partner(self, BloomFauna.BREED_RADIUS)
			if partner:
				_breed_with(partner)
		if BloomFauna.snail_carry(self, _crawler, delta):
			return
		# Patrol the scoured seam, respecting whatever rail or bulkhead crosses it.
		_crawler.tick(self, delta)
		# Rasping — the shell rocks side to side as the radula works the steel. The rock is
		# handed to orient() as a body-local roll so it rides ON the surface frame: rasping
		# up a vertical rail rocks across the rail, and the foot stays on the steel.
		_crawler.orient(self, delta, 4.0, sin(_t * 2.4) * 0.06)
		# Fed reads as visibly hotter, faster-breathing vents — the "I fed it" feedback.
		var heat_rate: float = 1.9 if _fed else 1.3
		var heat_mul: float = 1.35 if _fed else 1.0
		var heat: float = heat_mul * (0.8 + 0.5 * sin(_t * 0.7 + _idx))
		for i in range(_glow_mats.size()):
			_glow_mats[i].emission_energy_multiplier = heat * (0.7 + 0.3 * sin(_t * heat_rate + i))
		# The foot wave keeps time with the rasping, and the shell heat breathes with it.
		ANIM.drive(_gen_mats, 0.8, heat * 0.5)
		Journal.discover_if_near(self, "creature_rust_snail", 9.0)

# ----------------------------------------------------------- Glass Snail
class GlassSnail extends Node3D:
	## Transparent-shelled gastropod on the submerged steel (Codex §54c). You can watch
	## its gut work through the shell — a spiral of teal light with no animal visible
	## around it. Bloom-curious per canon: come close and it does not flee, it BRIGHTENS,
	## turning its lit coil toward you like it wants a look back.
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/glass_snail/glass_snail.glb"
	# Transparent shader variant — the shared creature shader is opaque; only this species
	# swaps to it so its shell stays see-through (see the swap in _ready).
	const GLASS_SHADER := preload("res://materials/creature_swim_glass.gdshader")
	var _gen_mats: Array = []
	var _t: float
	var _base: Vector3
	var _idx: int
	var _gut_mats: Array[StandardMaterial3D] = []
	var _interest: float = 0.0
	var _crawler: GroundCrawler       ## wall-aware drift across the submerged plate
	var _carried_by: Node3D = null    ## set while the player is carrying this live snail
	var _fed: bool = false            ## took a greens item; breeds when a fed sibling is close
	var _is_baby: bool = false        ## spawned by breeding — permanent, ~0.4 scale, grows in
	var _grow_h: float = 0.0          ## game-hours since birth (baby only)
	var _body_pivot: Node3D = null    ## baby-only scale wrapper (see BloomFauna.shrink_to_baby)

	func _init(idx: int, base: Vector3) -> void:
		_idx = idx
		_base = base
		_t = idx * 2.7

	func _ready() -> void:
		add_to_group("snail_glass")
		var shell := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.26
		sm.height = 0.4
		sm.is_hemisphere = true
		# Actually transparent — the point of the animal is seeing through it.
		sm.material = BloomFauna.glow_mat(Color(0.75, 0.92, 0.95), 0.1, 0.22)
		shell.mesh = sm
		add_child(shell)
		# The gut coil, lit, sitting INSIDE the shell where it can be seen.
		for i in range(5):
			var seg := MeshInstance3D.new()
			var gm := SphereMesh.new()
			gm.radius = 0.055 - i * 0.006
			gm.height = 0.11 - i * 0.012
			var m := BloomFauna.glow_mat(BloomFauna.TEAL, 2.2)
			_gut_mats.append(m)
			gm.material = m
			seg.mesh = gm
			var a: float = i * 1.15
			var r: float = 0.15 - i * 0.022
			seg.position = Vector3(cos(a) * r, 0.06 + i * 0.025, sin(a) * r)
			add_child(seg)
		var foot := MeshInstance3D.new()
		var fm := CapsuleMesh.new()
		fm.radius = 0.1
		fm.height = 0.5
		fm.material = BloomFauna.glow_mat(Color(0.8, 0.9, 0.9), 0.05, 0.5)
		foot.mesh = fm
		foot.rotation.x = deg_to_rad(90)
		foot.position.y = -0.08
		add_child(foot)
		# 0.35 opacity: the shell goes see-through so the lit gut reads THROUGH it, which
		# is the whole species. The generator will not produce real glass, so we do it here.
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 0.5, ANIM.Mode.PEDAL,
			0.025, 0.6, BloomFauna.TEAL, 0.0, 0.35)
		if not gen.is_empty():
			_gen_mats = gen["mats"]
			# The shared creature shader is OPAQUE now (so lamp/rust snails stopped reading
			# see-through). Glass is the one species that must stay translucent, so swap its
			# generated surfaces to the transparent variant. ShaderMaterial keeps every
			# parameter across a shader change (matched by name), so the PEDAL motion, PBR
			# maps and authored facing all carry over; re-assert the 0.35 opacity that lets
			# the lit gut-coil read through the shell.
			for m in _gen_mats:
				var gsm: ShaderMaterial = m
				gsm.shader = GLASS_SHADER
				gsm.set_shader_parameter("opacity", 0.35)
			BloomFauna.ground_model(self, gen["model"])   # foot on the submerged plate
		# Drifts the plate on a short leash so it stays on the steel, grounding every frame
		# and turning back at the plate edge instead of hanging out over open water.
		global_position = _base
		_crawler = GroundCrawler.new(_base, 3.0, 0.08, 900 + _idx, 0.18, 0.12, _base.y)
		# Grab it like any other loose item — the curious one comes along easily too.
		# Crouch for COLLECT; carrying greens and unfed offers FEED first.
		var touch := FaunaTouch.new("Glass Snail", 0.4,
			func() -> Array:
				if BloomFauna.player_crouching(self):
					return ["COLLECT"]
				var out: Array = ["GRAB"]
				if not _is_baby and not _fed and BloomFauna.has_greens():
					out.push_front("FEED")
				return out,
			_touch_act)
		add_child(touch)
		if _is_baby:
			_body_pivot = BloomFauna.shrink_to_baby(self, BloomFauna.BABY_SCALE)

	func _touch_act(verb: String, player: Node3D) -> void:
		match verb:
			"FEED":
				_feed(player)
			"COLLECT":
				_collect(player)
			_:
				BloomFauna.grab_snail(self, player)

	func _feed(_player: Node3D) -> void:
		if _is_baby or _fed or not BloomFauna.consume_greens():
			return
		_fed = true
		Journal.discover("system_snail_breeding")
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toast"):
			hud.toast("It takes the greens without ever looking away from you.")

	func _breed_with(partner: Node3D) -> void:
		var mid: Vector3 = (global_position + partner.global_position) * 0.5
		var baby := GlassSnail.new(5000 + (randi() % 100000), mid)
		baby._is_baby = true
		get_parent().add_child(baby)
		baby.global_position = mid
		_fed = false
		partner.set("_fed", false)
		Journal.discover("creature_snail_baby")
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toast"):
			hud.toast("Two lit coils turn toward each other, and a third, smaller one, blinks on between them.")

	func _collect(_player: Node3D) -> void:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if not PlayerState.add_item("snail_live"):
			if hud and hud.has_method("toast"):
				hud.toast("Hands full — it stays where it is.")
			return
		Journal.discover("item_snail_live")
		if hud and hud.has_method("toast"):
			hud.toast("Into the pack — the lit coil dims to nothing in the dark.")
		queue_free()

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_t += delta
		if _is_baby:
			_grow_h += delta * GameClock.time_scale * BloomFauna.game_hour_per_sec()
			if _body_pivot:
				_body_pivot.scale = Vector3.ONE * lerpf(BloomFauna.BABY_SCALE, 1.0,
					clampf(_grow_h / BloomFauna.GROW_HOURS, 0.0, 1.0))
			if _grow_h >= BloomFauna.GROW_HOURS:
				_is_baby = false
		elif _fed:
			var partner: Node3D = BloomFauna.find_breed_partner(self, BloomFauna.BREED_RADIUS)
			if partner:
				_breed_with(partner)
		# Curiosity, not fear: the closer you are, the harder its gut burns.
		var player: Node3D = get_tree().get_first_node_in_group("player")
		var near: bool = player != null and player.global_position.distance_to(global_position) < 7.0
		_interest = move_toward(_interest, 1.0 if near else 0.0, delta * 0.8)
		# Fed reads as a visibly brighter, slightly faster peristalsis down the coil.
		var pulse_rate: float = 1.5 if _fed else 1.1
		var pulse_mul: float = 1.3 if _fed else 1.0
		for i in range(_gut_mats.size()):
			var pulse: float = pulse_mul * (0.6 + 0.4 * sin(_t * pulse_rate - i * 0.7))   # peristalsis down the coil
			_gut_mats[i].emission_energy_multiplier = pulse * lerpf(1.4, 4.0, _interest)
		if _gen_mats.size() > 0:
			ANIM.drive(_gen_mats, 0.6, lerpf(0.6, 2.2, _interest))
		if BloomFauna.snail_carry(self, _crawler, delta):
			return
		# A slow wander across the submerged plate, kept on the steel by its short leash so
		# the ground ray always has metal under it and the foot rides the plate, not water.
		_crawler.tick(self, delta)
		# Model is yaw-normalised to -Z-forward, so the +PI in face_yaw turns its lit gut
		# coil (the head end) into its travel; when you lean over the rail it turns to look.
		if near and player:
			# Curiosity, kept on the plate: the look direction is projected into the face it
			# is stuck to, so it turns its lit coil toward you ACROSS the steel instead of
			# rolling its foot off the surface to point at you.
			var want: Basis = _crawler.look_basis(player.global_position - global_position)
			global_basis = global_basis.orthonormalized().slerp(want, clampf(delta * 0.9, 0.0, 1.0))
		else:
			_crawler.orient(self, delta, 2.0)
		if near:
			Journal.discover_if_near(self, "creature_glass_snail", 7.0)

# --------------------------------------------------------- Pyramid Snail
class PyramidSnail extends Node3D:
	## THE WANDERER (owner brief, 2026-07-27). The other three gastropods are all tied to
	## water — the lamp snails graze the leg bases, the rust snails work the splash-zone
	## seams, the glass snails never leave their submerged plate. This one has no such
	## tether: it walks the whole rig, picks a direction, holds it for half a minute, then
	## picks another. You meet it in the middle of the topside plate on a walk to the
	## galley, which is exactly the point of it.
	##
	## The shell is the other half: a stepped ziggurat spiral climbing to a point, banded
	## black and white like a textile cone, with a ring of mineral spikes on every whorl's
	## shoulder. Evolved-bloom armour — graphic and beautiful, not menacing — and a
	## silhouette nobody will confuse with the other three domes at any distance.
	##
	## THERE IS NO GENERATED MESH FOR IT (no generation credits), so the procedural body
	## IS the animal rather than a fallback nobody sees. It still ASKS for the asset first
	## — CreatureAnim.replace returns {} when the file is absent, which is this project's
	## documented signal to build the primitive body — so the day a pyramid_snail.glb does
	## land, it takes over with no code change.
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/pyramid_snail/pyramid_snail.glb"
	const PEARL := Color(0.93, 0.93, 0.89)
	# --- shell geometry -----------------------------------------------------------
	const TIERS: int = 9          ## whorls in the ziggurat
	const SEG: int = 18           ## segments round a whorl
	const R0: float = 0.275       ## radius of the bottom whorl
	const SHELL_H: float = 0.70   ## base to the last whorl (the apex spike is extra)
	const TWIST: float = 0.40     ## radians each whorl rotates over the one below it
	const SPIKES: int = 6         ## tubercles per whorl shoulder
	# --- the body -----------------------------------------------------------------
	const FOOT_HW: float = 0.33   ## half-width of the pedal sole
	const FOOT_HL: float = 0.54   ## half-length
	const FOOT_HT: float = 0.17   ## height of the flank at midships
	# --- the wander ---------------------------------------------------------------
	## Speed sits between the lamp snail (0.13) and the rust snail (0.10) — the same
	## grazing idiom, not a new kind of movement.
	const SPEED: float = 0.115
	## Big enough to be the WHOLE RIG rather than a patch: the crawler's own leash is what
	## eventually turns a stray back, and at 17 m from home that is the deck edge, not a
	## circle it paces. Direction changes come from the timer below, not from the leash.
	const LEASH: float = 17.0
	const TURN_MIN: float = 16.0  ## seconds it holds one heading, low end...
	const TURN_MAX: float = 42.0  ## ...and high. Randomised per leg AND seeded per animal,
	                              ## so two of them never turn on the same beat.
	## Hard keep-aboard box, in from the topside plate's x±30 / z±20 rim. The crawler
	## already refuses a step with no footing under it (SurfaceCrawler._has_footing) and
	## turns back at a convex edge, so this is the belt to that pair of braces: a heading
	## that is carrying the animal out over the rail gets REFLECTED back inboard.
	const ROAM_X: float = 27.5
	const ROAM_Z: float = 17.5
	## Albedo-keyed self-lighting (creature_swim.gdshader `body_glow`). See _ready().
	## Deliberately under leg_reef's 1.35 and reef_fish's 1.25: a snail that out-glows the
	## coral it is sitting on reads as a lamp, not an animal.
	const DECK_GLOW: float = 0.12
	const DEEP_GLOW: float = 0.95

	var _gen_mats: Array = []
	var _t: float
	var _base: Vector3
	var _idx: int
	var _shell_mats: Array[ShaderMaterial] = []   ## the banded shell (spiral pattern mode)
	var _flesh_mats: Array[ShaderMaterial] = []   ## foot / collar / head / tentacles
	var _stalks: Array[Node3D] = []               ## eye stalks, waving
	var _tents: Array[Node3D] = []                ## the shorter oral (sensory) tentacles
	var _eye_mat: StandardMaterial3D
	var _crawler: GroundCrawler       ## free-roaming surface wander over the whole rig
	var _turn_cd: float = 0.0         ## seconds until it picks a fresh random heading
	var _carried_by: Node3D = null    ## set while the player is carrying this live snail
	var _fed: bool = false            ## took a greens item; breeds when a fed sibling is close
	var _is_baby: bool = false        ## spawned by breeding — permanent, ~0.4 scale, grows in
	var _grow_h: float = 0.0          ## game-hours since birth (baby only)
	var _body_pivot: Node3D = null    ## baby-only scale wrapper (see BloomFauna.shrink_to_baby)
	var _rng := RandomNumberGenerator.new()

	func _init(idx: int, base: Vector3) -> void:
		_idx = idx
		_base = base
		_t = idx * 2.3
		_rng.seed = 1300 + idx

	func _ready() -> void:
		add_to_group("snail_pyramid")
		# Ask for the generated asset first. It is not there (and will not be until someone
		# spends generation credits on it), so this returns {} and the procedural body gets
		# built — the documented degrade path, used here as the primary path.
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 0.95, ANIM.Mode.PEDAL,
			0.03, 0.6, PEARL)
		if gen.is_empty():
			_build_body()
		else:
			_gen_mats = gen["mats"]
			BloomFauna.ground_model(self, gen["model"])
			# HOW HARD IT LIGHTS ITSELF, and why it is not one number (owner, s23: "please
			# also brighten them slightly, they seem extra dark in game, moreso than their
			# model"). Most of that was the metallicRoughness map the motion shader was not
			# sampling — see creature_anim.gd; fixing it alone brings the three DECK snails
			# up to the brightness of the model render, and any emission on top of full
			# daylight would only push a near-white shell through main.gd's 0.8 glow
			# threshold. The other six live on caisson concrete 11-19 m down, where there is
			# no direct light at all, and they photographed as pure black silhouettes against
			# coral that is EMISSIVE at 1.35 — the same "a lit surface at depth renders
			# near-black whatever its albedo" that cost s21 three albedo passes on the mussel
			# scar. So the deep ones get their own colour back and the deck ones get a sheen.
			var lit: float = DECK_GLOW if _base.y > 0.0 else DEEP_GLOW
			for m in _gen_mats:
				(m as ShaderMaterial).set_shader_parameter("body_glow", lit)
		# Same verb set as the other three crawlers: crouch for COLLECT, greens offer FEED
		# ahead of the GRAB fallback.
		var touch := FaunaTouch.new("Pyramid Snail", 0.6,
			func() -> Array:
				if BloomFauna.player_crouching(self):
					return ["COLLECT"]
				var out: Array = ["GRAB"]
				if not _is_baby and not _fed and BloomFauna.has_greens():
					out.push_front("FEED")
				return out,
			_touch_act)
		add_child(touch)
		global_position = _base
		# FREE EXPLORATION. Same GroundCrawler every snail uses — so the surface-snapping,
		# the kerb-crawling and the refusal to step where there is no footing all come
		# along — but on a rig-sized leash with the heading driven by _pick_heading()'s
		# timer instead of by a patch. Seating is the crawler's: its first tick runs a wide
		# grounding probe from ABOVE the animal and pins the origin FOOT (2 cm) off the
		# real face, which is the fix for the old hand-typed-Y float (see surface_y's note)
		# — so the authored y here only has to be roughly right and the snail still sits
		# flush on the plating. The procedural body is built with its sole at local y=0 so
		# that 2 cm is all the clearance there is.
		_crawler = GroundCrawler.new(_base, LEASH, SPEED, 1300 + _idx, 0.30, 0.22, _base.y)
		_pick_heading()
		# Stagger the FIRST leg across the whole window as well, or three snails spawned in
		# the same frame would still take their first turn together.
		_turn_cd = _rng.randf_range(TURN_MIN * 0.25, TURN_MAX)
		if _is_baby:
			_body_pivot = BloomFauna.shrink_to_baby(self, BloomFauna.BABY_SCALE)

	# ---------------------------------------------------------------- procedural body
	func _build_body() -> void:
		_build_flesh()      # foot first: the shell sits on top of it
		_build_shell()
		_build_head()

	## One triangle with an explicitly computed OUTWARD normal. `ref` is any point inside
	## the solid at that spot; the normal is flipped to point away from it. Doing it this
	## way (rather than SurfaceTool.generate_normals()) means the lighting cannot come out
	## inverted from a winding mistake in the ring loops below, which on a nine-tier
	## spiral is a genuinely easy mistake to make and a horrible one to spot.
	static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ref: Vector3) -> void:
		var n: Vector3 = (b - a).cross(c - a)
		if n.length() < 1e-9:
			return
		n = n.normalized()
		if n.dot((a + b + c) / 3.0 - ref) < 0.0:
			n = -n
		st.set_normal(n)
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)

	static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
			ref: Vector3) -> void:
		_tri(st, a, b, c, ref)
		_tri(st, a, c, d, ref)

	## Soft-tissue quad: per-VERTEX normals, so the foot and the mantle read as smooth
	## muscle instead of the faceted low-poly the flat-shaded shell wants. The shell shader
	## is cull_disabled, so winding does not matter here — only the normals do.
	static func _quad_smooth(st: SurfaceTool, p: Array[Vector3], n: Array[Vector3]) -> void:
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k in tri:
				st.set_normal(n[k])
				st.add_vertex(p[k])

	## A band of quads between two horizontal rings — the riser and the tread of one
	## ziggurat step. The two rings carry different rotations, which is what makes the
	## stack SPIRAL instead of merely stacking.
	static func _ring_band(st: SurfaceTool, ra: float, ya: float, rota: float,
			rb: float, yb: float, rotb: float) -> void:
		for j in range(SEG):
			var f0: float = float(j) * TAU / float(SEG)
			var f1: float = float(j + 1) * TAU / float(SEG)
			var p0 := Vector3(cos(rota + f0) * ra, ya, sin(rota + f0) * ra)
			var p1 := Vector3(cos(rota + f1) * ra, ya, sin(rota + f1) * ra)
			var q0 := Vector3(cos(rotb + f0) * rb, yb, sin(rotb + f0) * rb)
			var q1 := Vector3(cos(rotb + f1) * rb, yb, sin(rotb + f1) * rb)
			# Reference point on the shell's axis, well below the band: for a riser that makes
			# the normal radial-outward, for a tread it makes it point up.
			var ref := Vector3(0.0, minf(ya, yb) - 0.6, 0.0)
			_quad(st, p0, p1, q1, q0, ref)

	## One whorl's ring of spikes: a five-sided cone standing off the shoulder, aimed
	## outward and canted up. Each ring is rolled a little further round than the one
	## below, so the tubercles themselves trace the spiral up the shell.
	static func _spike_ring(st: SurfaceTool, tier: int, r: float, y: float, rot: float,
			length: float) -> void:
		for j in range(SPIKES):
			var a: float = rot + float(j) * TAU / float(SPIKES) + float(tier) * 0.33
			var outw := Vector3(cos(a), 0.0, sin(a))
			var base_c: Vector3 = outw * (r * 0.90) + Vector3(0.0, y, 0.0)
			var dir: Vector3 = (outw + Vector3(0.0, 0.42, 0.0)).normalized()
			var tip: Vector3 = base_c + dir * length
			var u: Vector3 = dir.cross(Vector3.UP)
			u = u.normalized() if u.length() > 0.01 else Vector3.RIGHT
			var v: Vector3 = dir.cross(u).normalized()
			var br: float = length * 0.34
			var pts: Array[Vector3] = []
			for k in range(5):
				var th: float = float(k) * TAU / 5.0
				pts.append(base_c + (u * cos(th) + v * sin(th)) * br)
			for k in range(5):
				_tri(st, pts[k], pts[(k + 1) % 5], tip, base_c)

	## The shell: a stepped conical spiral, two surfaces — the banded whorls and the
	## pale mineral spikes — on ONE ArrayMesh, so the whole thing is two draw calls and,
	## more importantly, one continuous object space for the shader. That last part is
	## why the tiers are not separate MeshInstance3Ds: the spiral band pattern is sampled
	## in object space, and per-tier meshes would each restart it.
	func _build_shell() -> void:
		var body := SurfaceTool.new()
		body.begin(Mesh.PRIMITIVE_TRIANGLES)
		var spikes := SurfaceTool.new()
		spikes.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(TIERS):
			var f0: float = float(i) / float(TIERS)
			var f1: float = float(i + 1) / float(TIERS)
			var r0: float = R0 * pow(1.0 - f0, 0.85)
			var r1: float = R0 * pow(1.0 - f1, 0.85)
			var y0: float = SHELL_H * f0
			var y1: float = SHELL_H * f1
			var yw: float = lerpf(y0, y1, 0.62)          # top of the vertical riser
			var t0: float = float(i) * TWIST
			var tw: float = t0 + TWIST * 0.62
			var t1: float = float(i + 1) * TWIST
			_ring_band(body, r0, y0, t0, r0, yw, tw)     # riser
			_ring_band(body, r0, yw, tw, r1, y1, t1)     # tread
			# Longest on the bottom whorls, shrinking hard with the shell — a cone's armour
			# is heaviest at the aperture. A flat taper made the apex a ball of thorns.
			_spike_ring(spikes, i, r0, lerpf(y0, yw, 0.45), t0,
				0.035 + 0.115 * pow(1.0 - f0, 1.4))
		# The point: a slim cone finishing the spiral.
		var r_top: float = R0 * pow(1.0 / float(TIERS), 0.85)
		var apex := Vector3(0.0, SHELL_H + 0.09, 0.0)
		var t_top: float = float(TIERS) * TWIST
		for j in range(SEG):
			var f0: float = float(j) * TAU / float(SEG)
			var f1: float = float(j + 1) * TAU / float(SEG)
			_tri(body, Vector3(cos(t_top + f0) * r_top, SHELL_H, sin(t_top + f0) * r_top),
				Vector3(cos(t_top + f1) * r_top, SHELL_H, sin(t_top + f1) * r_top), apex,
				Vector3(0.0, SHELL_H - 0.3, 0.0))
		var mesh := ArrayMesh.new()
		body.commit(mesh)
		spikes.commit(mesh)
		# BLACK AND WHITE, WINDING UP. band_turns is an integer on purpose: the shader's
		# angular term is an atan, and only a whole number of turns closes seamlessly
		# across the -PI/+PI cut instead of leaving a visible vertical join.
		var shell_mat: ShaderMaterial = BloomFauna.shell_mat(mesh.get_aabb(), {
			"pattern_mode": 1,
			"band_dark": Color(0.035, 0.035, 0.045),
			"band_light": Color(0.96, 0.95, 0.91),
			# 4 turns of stripe per revolution against only 4 up the shell: the angular
			# term dominates, so the bands cut ACROSS the nine whorls at a steep diagonal.
			# The first pass used band_freq 9 — one stripe per tier — and the pattern just
			# re-drew the steps instead of winding through them.
			"band_turns": 4.0, "band_freq": 4.0, "band_edge": 0.09,
			"vein_color": Color(0.55, 0.95, 0.95), "vein_energy": 0.10,
			"roughness_v": 0.42, "pattern_scale": 2.6,
			"mode": 0,
		})
		mesh.surface_set_material(0, shell_mat)
		_shell_mats.append(shell_mat)
		# The spikes stay pale mineral all the way round rather than picking up the banding
		# — that contrast is what makes them read as armour grown ON the shell.
		var spike_mat := StandardMaterial3D.new()
		spike_mat.albedo_color = PEARL
		spike_mat.roughness = 0.24
		spike_mat.metallic = 0.15
		spike_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		spike_mat.emission_enabled = true
		spike_mat.emission = Color(0.55, 0.85, 0.85)
		spike_mat.emission_energy_multiplier = 0.12
		mesh.surface_set_material(1, spike_mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(0.0, 0.15, 0.07)   # seated on the foot, a touch aft
		mi.rotation.x = deg_to_rad(13.0)         # carried tipped back, the way a snail does
		add_child(mi)

	## A point on the pedal foot. `s` runs -1 (tail) to +1 (head, at -Z: the crawler puts
	## -Z on the heading), `a` runs round the cross-section from the SOLE (a=0, y=0) over
	## the flank to the back (a=PI). The sole therefore sits exactly on local y=0, which
	## is what lets the crawler seat the animal flush — a body modelled around its centre
	## would hover by half its own thickness.
	static func _foot_point(s: float, a: float) -> Vector3:
		var prof: float = sqrt(maxf(0.0, 1.0 - s * s))
		# Muscular ripple: the flank swells and narrows in waves down the body, which is
		# the pedal wave standing still. The shader animates it on top of this.
		var w: float = FOOT_HW * prof * (1.0 + 0.10 * sin(s * 11.0 + 0.7))
		var ht: float = FOOT_HT * prof * (1.0 + 0.07 * sin(s * 11.0 + 0.7))
		return Vector3(w * sin(a), ht * 0.5 * (1.0 - cos(a)), -s * FOOT_HL)

	## Outward surface normal of the foot at (s, a), by central difference. Smooth muscle
	## needs per-vertex normals; the flat-shaded treatment that suits the mineral shell
	## turns the same mesh into a lump of faceted salmon.
	static func _foot_normal(s_in: float, a: float) -> Vector3:
		# Pull off the poles: at |s| = 1 the cross-section collapses to a point, the cross
		# product degenerates and the tail cap ends up shaded with a flat black facet.
		# Sampling the normal a hair inboard gives the pole the normal of its own rim.
		var s: float = clampf(s_in, -0.985, 0.985)
		var d: float = 0.006
		var da: Vector3 = _foot_point(s, a + d) - _foot_point(s, a - d)
		var ds: Vector3 = _foot_point(minf(s + d, 1.0), a) - _foot_point(maxf(s - d, -1.0), a)
		var n: Vector3 = da.cross(ds)
		if n.length() < 1e-8:
			return Vector3.UP
		n = n.normalized()
		# Reference INBOARD along the body axis (0.55 of the way, not the same station), so
		# near the nose and tail — where the cross-section has collapsed to almost nothing
		# and a same-station reference gives a near-zero vector — the outward test still
		# has a strong component to work with. A same-station ref left the tail cap shaded
		# as one flat dark facet, which read as a bite out of the animal.
		if n.dot(_foot_point(s, a) - Vector3(0.0, FOOT_HT * 0.5, -s * FOOT_HL * 0.55)) < 0.0:
			n = -n
		return n

	func _build_flesh() -> void:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var NL: int = 30
		var NA: int = 22
		for i in range(NL):
			for j in range(NA):
				var pts: Array[Vector3] = []
				var nms: Array[Vector3] = []
				for e in [[0, 0], [0, 1], [1, 1], [1, 0]]:
					var s: float = -1.0 + 2.0 * float(i + int(e[0])) / float(NL)
					var a: float = float(j + int(e[1])) * TAU / float(NA)
					pts.append(_foot_point(s, a))
					nms.append(_foot_normal(s, a))
				_quad_smooth(st, pts, nms)
		var foot := ArrayMesh.new()
		st.commit(foot)
		var mi := MeshInstance3D.new()
		mi.mesh = foot
		# PEDAL on the foot itself: the shader's muscular wave runs tail -> head down the
		# sole. flow_flip 0 because this body is built head-first at -Z (n.z = 0), not the
		# generated-asset convention of head at +Z.
		foot.surface_set_material(0, _flesh_material(foot.get_aabb(), true))
		add_child(mi)
		# MANTLE COLLAR — the lip of soft tissue where the flesh meets the shell, sitting
		# tight around the bottom whorl so the shell reads as GROWN OUT of the animal.
		# (First pass ringed it at 1.16x the whorl radius, which read as a pink lifebuoy
		# parked around the shell rather than as part of the snail.)
		var cst := SurfaceTool.new()
		cst.begin(Mesh.PRIMITIVE_TRIANGLES)
		var CA: int = 34
		var CT: int = 8
		var cr: float = R0 * 1.03
		for i in range(CA):
			for k in range(CT):
				var pts: Array[Vector3] = []
				var nms: Array[Vector3] = []
				for e in [[0, 0], [1, 0], [1, 1], [0, 1]]:
					var a: float = float(i + int(e[0])) * TAU / float(CA)
					var th: float = float(k + int(e[1])) * TAU / float(CT)
					var radial := Vector3(cos(a), 0.0, sin(a))
					var rr: float = cr + 0.014 * sin(a * 11.0)      # a soft scalloped lip
					var nrm: Vector3 = (radial * cos(th) + Vector3.UP * sin(th)).normalized()
					pts.append(radial * rr + nrm * 0.036)
					nms.append(nrm)
				_quad_smooth(cst, pts, nms)
		var collar := ArrayMesh.new()
		cst.commit(collar)
		collar.surface_set_material(0, _flesh_material(collar.get_aabb(), false))
		var cmi := MeshInstance3D.new()
		cmi.mesh = collar
		cmi.position = Vector3(0.0, 0.148, 0.06)
		cmi.scale = Vector3(1.06, 0.72, 1.06)
		add_child(cmi)

	## Head, eye stalks and oral tentacles — the part the owner wanted PROMINENT. A snail
	## reads as an animal (rather than as a shell that slides) entirely through this end.
	func _build_head() -> void:
		var head := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.5
		hm.height = 1.0
		hm.radial_segments = 20
		hm.rings = 12
		hm.material = _flesh_material(hm.get_aabb(), false)
		head.mesh = hm
		head.scale = Vector3(0.34, 0.27, 0.46)
		head.position = Vector3(0.0, 0.155, -0.40)
		add_child(head)
		# A short muzzle carrying the mouth, so the head has a front and not just a curve.
		var snout := MeshInstance3D.new()
		var nm := SphereMesh.new()
		nm.radius = 0.5
		nm.height = 1.0
		nm.radial_segments = 16
		nm.rings = 9
		nm.material = _flesh_material(nm.get_aabb(), false)
		snout.mesh = nm
		snout.scale = Vector3(0.23, 0.17, 0.22)
		snout.position = Vector3(0.0, 0.125, -0.555)
		add_child(snout)
		# Eyes at the tips of long retractile stalks — a gastropod's actual anatomy, and
		# the tell that this species watches you back.
		# A dark wet bead with a teal glint in it, not a lit bulb: the first pass ran the
		# emission hot enough that the eyes read as two solid teal lollipops.
		_eye_mat = BloomFauna.glow_mat(Color(0.05, 0.07, 0.09), 0.0)
		_eye_mat.roughness = 0.06
		_eye_mat.metallic = 0.25
		_eye_mat.emission = Color(0.35, 0.95, 0.9)
		for sx in [-0.085, 0.085]:
			var pivot := Node3D.new()
			add_child(pivot)
			pivot.position = Vector3(sx, 0.25, -0.42)
			var stalk := MeshInstance3D.new()
			var stm := CapsuleMesh.new()
			stm.radius = 0.014
			stm.height = 0.34
			stm.material = _flesh_material(stm.get_aabb(), false)
			stalk.mesh = stm
			stalk.rotation.x = deg_to_rad(-32)          # up and forward
			stalk.position = Vector3(0.0, 0.125, -0.085)
			pivot.add_child(stalk)
			var eye := MeshInstance3D.new()
			var em := SphereMesh.new()
			em.radius = 0.030
			em.height = 0.060
			em.radial_segments = 14
			em.rings = 8
			em.material = _eye_mat
			eye.mesh = em
			eye.position = Vector3(0.0, 0.267, -0.185)   # at the stalk tip
			pivot.add_child(eye)
			_stalks.append(pivot)
		# The shorter, lower pair: oral tentacles, which taste the plating ahead of it.
		for sx in [-0.062, 0.062]:
			var pivot := Node3D.new()
			add_child(pivot)
			pivot.position = Vector3(sx, 0.10, -0.60)
			var tent := MeshInstance3D.new()
			var tm := CapsuleMesh.new()
			tm.radius = 0.015
			tm.height = 0.14
			tm.material = _flesh_material(tm.get_aabb(), false)
			tent.mesh = tm
			tent.rotation.x = deg_to_rad(-64)
			tent.position = Vector3(0.0, 0.005, -0.055)
			pivot.add_child(tent)
			_tents.append(pivot)

	## Soft tissue: mottled, with a warm rim that stands in for the subsurface scattering
	## the compatibility renderer does not have. `pedal` turns on the shader's foot wave.
	func _flesh_material(aabb: AABB, pedal: bool) -> ShaderMaterial:
		var m: ShaderMaterial = BloomFauna.shell_mat(aabb, {
			"pattern_mode": 2,
			# Wet-grey tissue with a warm cast, not the salmon the first pass produced —
			# a snail's foot is a muted, faintly translucent grey once it is out of a
			# terrarium photograph, and the warmth belongs in the rim, not the albedo.
			"base_color": Color(0.55, 0.53, 0.50),
			"vein_color": Color(0.80, 0.66, 0.60),
			"vein_energy": 0.22,
			"roughness_v": 0.62,
			"pattern_scale": 3.0,
			"rim_power": 2.4,
			"mode": 5 if pedal else 0,
			"amp": 0.012, "rate": 0.6,
			"flow_axis": 0, "flow_flip": 0.0,   # head at -Z on this hand-built body
		})
		_flesh_mats.append(m)
		return m

	# ------------------------------------------------------------------ interactions
	func _touch_act(verb: String, player: Node3D) -> void:
		match verb:
			"FEED":
				_feed(player)
			"COLLECT":
				_collect(player)
			_:
				BloomFauna.grab_snail(self, player)

	func _feed(_player: Node3D) -> void:
		if _is_baby or _fed or not BloomFauna.consume_greens():
			return
		_fed = true
		Journal.discover("system_snail_breeding")
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toast"):
			hud.toast("It stops mid-stride, takes the greens, and both eye stalks swing up to look at you.")

	func _breed_with(partner: Node3D) -> void:
		var mid: Vector3 = (global_position + partner.global_position) * 0.5
		var baby := PyramidSnail.new(5000 + (randi() % 100000), mid)
		baby._is_baby = true
		get_parent().add_child(baby)
		baby.global_position = mid
		_fed = false
		partner.set("_fed", false)
		Journal.discover("creature_snail_baby")
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toast"):
			hud.toast("Two banded spires meet, lean together a while, and leave a third one between them.")

	func _collect(_player: Node3D) -> void:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if not PlayerState.add_item("snail_live"):
			if hud and hud.has_method("toast"):
				hud.toast("Hands full — it stays where it is.")
			return
		Journal.discover("item_snail_live")
		if hud and hud.has_method("toast"):
			hud.toast("Into the pack it goes, spikes and all, stalks still reading the air.")
		queue_free()

	# ---------------------------------------------------------------------- wandering
	## Turn onto `dir`, projected into whatever face the foot is currently stuck to (so a
	## heading picked in world XZ still makes sense halfway up a bulkhead).
	func _steer(dir: Vector3) -> void:
		var u: Vector3 = _crawler.up
		var t: Vector3 = dir - u * dir.dot(u)
		if t.length() < 0.001:
			return
		_crawler.heading = t.normalized()
		# The crawler's own free-wander turns on a DISTANCE counter. Push it out of reach:
		# on this species the TIMER owns direction changes, and the leash keeps its role of
		# hauling a stray back inboard.
		_crawler._leg = 1.0e9

	func _pick_heading() -> void:
		var a: float = _rng.randf() * TAU
		_steer(Vector3(cos(a), 0.0, sin(a)))
		_turn_cd = _rng.randf_range(TURN_MIN, TURN_MAX)

	## Reflect off the rig's rim. The crawler will not step where there is no footing, so
	## this is not what stops it falling — it is what stops it spending a whole leg nosing
	## along a handrail looking for a way out over the sea.
	func _keep_aboard() -> void:
		var p: Vector3 = global_position
		var h: Vector3 = _crawler.heading
		var turned := false
		if absf(p.x) > ROAM_X and p.x * h.x > 0.0:
			h.x = -h.x
			turned = true
		if absf(p.z) > ROAM_Z and p.z * h.z > 0.0:
			h.z = -h.z
			turned = true
		if turned:
			_steer(h)
			_turn_cd = maxf(_turn_cd, 6.0)   # hold the new heading long enough to get clear

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_t += delta
		if _is_baby:
			_grow_h += delta * GameClock.time_scale * BloomFauna.game_hour_per_sec()
			if _body_pivot:
				_body_pivot.scale = Vector3.ONE * lerpf(BloomFauna.BABY_SCALE, 1.0,
					clampf(_grow_h / BloomFauna.GROW_HOURS, 0.0, 1.0))
			if _grow_h >= BloomFauna.GROW_HOURS:
				_is_baby = false
		elif _fed:
			var partner: Node3D = BloomFauna.find_breed_partner(self, BloomFauna.BREED_RADIUS)
			if partner:
				_breed_with(partner)
		# Night lifts the pale bands and the flesh a little — bioluminescence, not a lamp:
		# this species is a day-and-night animal, unlike the lamp snails.
		var night: bool = BloomFauna.is_dark_phase()
		var lift: float = (0.55 if night else 0.10) * (1.25 if _fed else 1.0)
		for m in _shell_mats:
			m.set_shader_parameter("vein_energy", lift)
		for m in _flesh_mats:
			m.set_shader_parameter("vein_energy", 0.16 + lift * 0.35)
		if _eye_mat:
			_eye_mat.emission_energy_multiplier = lerpf(_eye_mat.emission_energy_multiplier,
				0.5 if night else 0.12, delta * 2.0)
		if _gen_mats.size() > 0:
			ANIM.drive(_gen_mats, 0.6, lift)
		# Stalks and tentacles read the air on their own slow rhythms.
		for i in range(_stalks.size()):
			var s: Node3D = _stalks[i]
			s.rotation.z = sin(_t * 0.55 + i * PI) * 0.20
			s.rotation.y = sin(_t * 0.37 + i * 1.7) * 0.24
		for i in range(_tents.size()):
			var tn: Node3D = _tents[i]
			tn.rotation.y = sin(_t * 0.9 + i * 2.1) * 0.30
			tn.rotation.x = sin(_t * 0.7 + i) * 0.12
		if BloomFauna.snail_carry(self, _crawler, delta):
			return
		# THE WANDER: hold a heading for a randomised stretch of tens of seconds, then take
		# a fresh random one. Not a patrol and not a patch — the only things that turn it
		# early are the rig itself (walls, kerbs, deck edges, all the crawler's) and the
		# keep-aboard reflection.
		_turn_cd -= delta
		if _turn_cd <= 0.0:
			_pick_heading()
		_keep_aboard()
		_crawler.tick(self, delta)
		_crawler.orient(self, delta, 3.0)
		Journal.discover_if_near(self, "creature_pyramid_snail", 10.0)

# --------------------------------------------------------- Anchor Limpet
class AnchorLimpet extends Node3D:
	## Armoured limpet welded to the splash zone (Codex §54d). It does not crawl and it
	## does not run — it CLAMPS, and the ring of light under its rim goes out as it seals.
	## The rig's own stubbornness rendered as an animal: the storm cannot move it and
	## neither can you. Getting the glow back just means standing still long enough.
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/anchor_limpet/anchor_limpet.glb"
	var _gen_mats: Array = []
	var _t: float
	var _idx: int
	var _rim_mats: Array[StandardMaterial3D] = []
	var _clamp: float = 0.0        ## 0 = open and lit, 1 = sealed to the plate
	var _shell: Node3D

	func _init(idx: int) -> void:
		_idx = idx
		_t = idx * 1.4

	func _ready() -> void:
		_shell = Node3D.new()
		add_child(_shell)
		var shell := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.06
		sm.bottom_radius = 0.34
		sm.height = 0.22
		var shell_mat := BloomFauna.glow_mat(Color(0.2, 0.26, 0.25), 0.0)
		shell_mat.roughness = 0.9
		sm.material = shell_mat
		shell.mesh = sm
		_shell.add_child(shell)
		# The rim light: a ring of small emitters under the shell edge.
		for i in range(8):
			var a: float = i * TAU / 8.0
			var glim := MeshInstance3D.new()
			var gm := SphereMesh.new()
			gm.radius = 0.03
			gm.height = 0.06
			var m := BloomFauna.glow_mat(BloomFauna.TEAL, 1.8)
			_rim_mats.append(m)
			gm.material = m
			glim.mesh = gm
			glim.position = Vector3(cos(a) * 0.31, -0.1, sin(a) * 0.31)
			add_child(glim)
		# BREATHE: a slow resting swell. It stops dead when the animal clamps, which is
		# the tell — a limpet that has sealed is indistinguishable from the rig.
		var gen: Dictionary = ANIM.replace(_shell, MODEL_PATH, 0.6, ANIM.Mode.BREATHE,
			0.02, 0.3, BloomFauna.TEAL)
		if not gen.is_empty():
			_gen_mats = gen["mats"]
		# The one way to move it: a prybar. The shell is the prize; the rig keeps the scar.
		var touch := FaunaTouch.new("Anchor Limpet", 0.6,
			func() -> Array:
				return ["PRY"] if PlayerState.has_item("prybar") else [],
			_pry)
		add_child(touch)

	func _pry(_verb: String, _player: Node3D) -> void:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if not PlayerState.add_item("limpet_shell"):
			if hud and hud.has_method("toast"):
				hud.toast("No room to carry the shell — it stays clamped.")
			return
		Journal.discover("creature_anchor_limpet")
		AudioDirector.play_one_shot("clang", global_position, -4.0)
		if hud and hud.has_method("toast"):
			hud.toast("It fights the bar the whole way, then POPS free — an iron-hard dome in your hands.")
		queue_free()

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_t += delta
		# Footsteps through the plate: it seals long before you can reach it.
		var player: Node3D = get_tree().get_first_node_in_group("player")
		var d: float = player.global_position.distance_to(global_position) if player else 99.0
		var threatened: bool = d < 3.2
		_clamp = move_toward(_clamp, 1.0 if threatened else 0.0, delta * (2.5 if threatened else 0.35))
		# Sealing pulls the shell down onto the steel and puts the rim light out.
		if _shell:
			_shell.position.y = lerpf(0.0, -0.06, _clamp)
			_shell.scale = Vector3(1.0, lerpf(1.0, 0.82, _clamp), 1.0)
		var breath: float = 0.75 + 0.25 * sin(_t * 0.5 + _idx)
		for i in range(_rim_mats.size()):
			_rim_mats[i].emission_energy_multiplier = lerpf(breath * 1.8, 0.0, _clamp)
		if _gen_mats.size() > 0:
			# Breathing slows to nothing as it seals; the rim light goes with it.
			ANIM.drive(_gen_mats, lerpf(0.3, 0.0, _clamp), lerpf(1.0, 0.0, _clamp),
				lerpf(0.02, 0.0, _clamp))
		if d < 6.0:
			Journal.discover_if_near(self, "creature_anchor_limpet", 6.0)

# ------------------------------------------------- Corvid-Gull (perched)
class CorvidGull extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/herring_gull/herring_gull.glb"
	## Same bird as the deck gulls (DeckGull.SIZE_M) — the thief on the bunkhouse rail is the
	## same species standing on a different surface, so it is the same size, and it inherits
	## the same asset ceiling: its legs are painted into the one unrigged surface and cannot
	## tuck when it flies (DeckGull's LEGS note carries the measurements and the re-roll ask).
	const SIZE_M := 0.42
	const GLOW := Color(0.30, 0.85, 0.80)
	var _gen_mats: Array = []
	var _wings: GullWings = null   ## overlay flight wings — GullWings explains why
	## A Bloom-intelligent gull (Codex §26) perched on a high point of the rig, watching.
	## Tilts its head to track the player — and one of them STEALS: loose takeables on the
	## topside deck get carried, visibly, to the nest on the bunkhouse roof.
	## The perch heights are PROBED, never authored — see _snap_to_perch and the perch list
	## in BloomFauna._ready for why not one of them stands on a rail.
	## Story-critical tools are beneath its interest (and our mercy).
	const NEVER_STEAL := ["cable_spool", "fishing_rod", "throwing_hook", "prybar"]

	var thief: bool = false
	var _t: float
	var _head: Node3D
	var _perch: Vector3
	var _steal_timer: float = 70.0
	var _steal_phase: int = 0          ## 0 idle · 1 to target · 2 to nest · 3 home
	var _target: Node3D = null
	var _loot_id: String = ""
	var _carry: Node3D = null
	var _closest: float = 1e9          ## closest the player has crept (threat roll)
	var _fleeing: float = -1.0         ## <0 perched; else seconds airborne bolting off
	var _flee_regen: float = 0.0       ## respawn countdown after fleeing
	var _flee_dir: Vector3
	var _look_cd: float = 0.0          ## idle head-turn clock
	var _look_yaw: float = 0.0
	var _snapped: bool = false         ## has the surface under this perch been probed yet?

	func _init(perch: Vector3) -> void:
		_perch = perch
		_t = randf() * 6.0

	func _ready() -> void:
		global_position = _perch
		var slate: Material = BloomFauna.glow_mat(Color(0.28, 0.3, 0.34), 0.02)
		var body := MeshInstance3D.new()
		var bm := CapsuleMesh.new()
		bm.radius = 0.13
		bm.height = 0.5
		bm.material = slate
		body.mesh = bm
		body.rotation.x = deg_to_rad(70)
		add_child(body)
		_head = Node3D.new()
		_head.position = Vector3(0, 0.28, -0.14)
		add_child(_head)
		var hm := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.11
		hs.height = 0.22
		hs.material = slate
		hm.mesh = hs
		_head.add_child(hm)
		var beak := MeshInstance3D.new()
		var km := CylinderMesh.new()
		km.top_radius = 0.006
		km.bottom_radius = 0.03
		km.height = 0.14
		km.material = BloomFauna.glow_mat(Color(0.85, 0.75, 0.2), 0.03)
		beak.mesh = km
		beak.position = Vector3(0, 0, -0.14)
		beak.rotation.x = deg_to_rad(-90)
		_head.add_child(beak)
		# A bright, knowing eye.
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.03
		es.height = 0.06
		es.material = BloomFauna.glow_mat(Color(0.95, 0.85, 0.3), 0.6)
		eye.mesh = es
		eye.position = Vector3(0.07, 0.03, -0.05)
		_head.add_child(eye)
		# Legs.
		for sx in [-0.05, 0.05]:
			var leg := MeshInstance3D.new()
			var lm := CylinderMesh.new()
			lm.top_radius = 0.012
			lm.bottom_radius = 0.012
			lm.height = 0.18
			lm.material = BloomFauna.glow_mat(Color(0.8, 0.6, 0.2), 0.02)
			leg.mesh = lm
			leg.position = Vector3(sx, -0.22, 0.02)
			add_child(leg)
		# Generated mesh: wing filaments twitch even while it's perched and watching.
		# (Meshy auto-rigs humanoids only, so the motion is CreatureAnim's vertex shader.)
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, SIZE_M, ANIM.Mode.FLAP, 0.05, 1.0, GLOW)
		if not gen.is_empty():
			_gen_mats = gen["mats"]
			# Perched means STANDING on the rail, so the same grounding the deck gulls get:
			# the mesh is centred on its bounds and would otherwise hang half through it.
			ANIM.ground(self, gen["model"])
			ANIM.drive(_gen_mats, 1.0, 0.2)   # steady — no per-frame cost
			# Built AFTER replace() on purpose — replace hides every mesh that precedes
			# it (docs/AGENT_TRAPS.md), and these must draw. Slate rather than the deck
			# birds' pale grey: this bird's own body colour.
			_wings = GullWings.new()
			_wings.build(gen["model"], Color(0.28, 0.3, 0.34))

	## AI decimation state — see scripts/world/ai_budget.gd.
	var _ai_acc: float = 0.0

	func _process(delta: float) -> void:
		# DECIMATED when far away or not being drawn, and handed every skipped frame's delta
		# so the animal covers the same ground per second (ai_budget.gd explains why that is
		# not optional). Inside AiBudget.NEAR_M this is a no-op — nothing the player is close
		# enough to read the motion of is ever run at less than full rate.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_t += delta
		# Deferred out of _ready for the same reason DeckGull._snap_to_deck is: the rig is
		# CSG and has no collider to probe against until physics has stepped once.
		if not _snapped:
			_snapped = true
			_snap_to_perch()
		var day: bool = GameClock.current_phase == GameClock.Phase.DAY \
			or GameClock.current_phase == GameClock.Phase.DAWN
		# Flee (Codex threat behaviour): it bolts off the perch and returns later.
		if _flee_regen > 0.0:
			_flee_regen -= delta
			if _flee_regen <= 0.0:
				global_position = _perch   # settles back on its rail
				_fleeing = -1.0
				if _wings:
					_wings.shown(false)   # perched: the authored folded wings take over
				_closest = 1e9
			else:
				return
		if _fleeing >= 0.0:
			# Same species, same flight, same three fixes as DeckGull's flush: per-frame
			# wingbeat with flap/glide phrasing, a wall-tested path (this line was a bare
			# uncollided += that carried the thief through the bunkhouse), and a launch
			# posture distinct from cruise.
			_fleeing += delta
			var launch: float = clampf(1.0 - _fleeing / 0.8, 0.0, 1.0)
			var gliding: bool = _fleeing > 1.6 and fposmod(_fleeing, 2.4) > 1.6
			ANIM.drive(_gen_mats, (1.1 if gliding else 4.8) + launch * 1.8, 0.2,
				(0.05 if gliding else 0.15) + launch * 0.09)
			if _wings:
				_wings.drive(delta, _fleeing, gliding)
			var want: Vector3 = global_position + _flee_dir * delta * 6.5 \
				+ Vector3(0, delta * (3.4 + launch * 1.4), 0)
			var res: Dictionary = FaunaMove.swim_clear(self, global_position, want, 0.30,
				BloomFauna.fauna_bodies(self))
			if bool(res["blocked"]):
				for side in [1.0, -1.0]:
					var alt: Vector3 = _flee_dir.rotated(Vector3.UP, side * 0.9)
					var probe: Dictionary = FaunaMove.swim_clear(self, global_position,
						global_position + alt * 1.2 + Vector3(0, 0.6, 0), 0.30,
						BloomFauna.fauna_bodies(self))
					if not bool(probe["blocked"]):
						_flee_dir = alt
						break
			global_position = res["pos"]
			rotation.y = lerp_angle(rotation.y,
				atan2(_flee_dir.x, _flee_dir.z) + PI, 1.0 - exp(-6.0 * delta))
			if _fleeing > 3.0:
				visible = false
				_flee_regen = randf_range(30.0, 70.0)
			return
		visible = day or _steal_phase != 0
		if not visible:
			return
		# Perched it only ruffles; mid-theft it is airborne and beating properly.
		var airborne: bool = _steal_phase != 0
		ANIM.drive(_gen_mats, 2.4 if airborne else 0.5, 0.2, 0.06 if airborne else 0.012)
		if _wings:
			# Keyed to the SAME `airborne` the shader line reads, so the panels can never
			# disagree with the heist state machine. No takeoff hold here: a heist leaves
			# from a hop into _fly_to's arc, not a standing flush, so the beat opens
			# straight into the cruise burst (airtime past every launch window).
			_wings.shown(airborne)
			if airborne:
				_wings.drive(delta, 1e9, false)
		if thief and day:
			_theft(delta)
			if _steal_phase != 0:
				return   # mid-heist: flying overrides perching
		var player: Node3D = get_tree().get_first_node_in_group("player")
		# Threat roll while perched: creep inside 10m and each ~1m closer may flush it.
		# Crouch-sneaking cuts the odds (crouch_factor 0.3) rather than skipping them.
		if day and player:
			var res: Array = BloomFauna.gull_flush_roll(player, global_position, _closest, 10.0, 0.34, 0.3)
			_closest = res[1]
			if res[0]:
				_begin_flee(player)
				return
		if player and player.global_position.distance_to(global_position) < 20.0:
			Journal.discover_if_near(self, "creature_gull", 20.0)
			var to_p: Vector3 = player.global_position - global_position
			var flat := Vector3(to_p.x, 0, to_p.z)
			if flat.length_squared() > 0.01:
				# +PI: the model is yaw-normalised to -Z-forward, so this turns the head
				# toward the player instead of pointing its tail at them.
				rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z) + PI, delta * 2.5)
			# A curious head-tilt while it watches.
			_head.rotation.z = sin(_t * 0.7) * 0.35
			# It keeps breaking the stare to glance about, on the same organic clock it
			# uses when unobserved but with a tighter arc. Pinning the head yaw to dead
			# ahead the whole time you are near read as animatronic rather than curious.
			_look_cd -= delta
			if _look_cd <= 0.0:
				_look_cd = randf_range(1.1, 3.0)
				_look_yaw = randf_range(-0.5, 0.5)
			_head.rotation.y = lerp_angle(_head.rotation.y, _look_yaw, delta * 2.0)
		else:
			_head.rotation.z = move_toward(_head.rotation.z, 0.0, delta)
			# Idle head-turns: it glances around the rail on its own organic clock.
			_look_cd -= delta
			if _look_cd <= 0.0:
				_look_cd = randf_range(1.6, 4.8)
				_look_yaw = randf_range(-1.1, 1.1)
			_head.rotation.y = lerp_angle(_head.rotation.y, _look_yaw, delta * 2.0)
		# Occasional preen bob.
		_head.position.y = 0.28 + maxf(sin(_t * 0.5) - 0.7, 0.0) * 0.3

	## Stand the bird on whatever its perch XZ is actually over, and keep that as the perch —
	## _perch is also the flee-return and the end of the heist, so correcting the constant
	## itself is what stops the bird flying home to the old floating height.
	##
	## ANIM.ground() has already put the model's feet on this node's origin, so the hit point
	## is the answer directly. Authored y only has to bracket the surface: the ray runs from
	## a metre above it to four below.
	func _snap_to_perch() -> void:
		var world: World3D = get_world_3d()
		if world == null:
			return
		var from: Vector3 = _perch + Vector3(0, 1.0, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 5.0, 0))
		q.collision_mask = 1          # world geometry
		q.collide_with_areas = false
		q.exclude = BloomFauna.fauna_bodies(self)   # don't perch on another animal
		var hit: Dictionary = world.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return                    # nothing under it — leave the authored height alone
		_perch.y = hit["position"].y
		global_position.y = _perch.y

	## Bolt off the perch away from the player; gone until it settles back later.
	func _begin_flee(player: Node3D) -> void:
		_fleeing = 0.0
		var away: Vector3 = (global_position - player.global_position) if player else Vector3(1, 0, 0)
		away.y = 0.0
		_flee_dir = away.normalized() if away.length() > 0.1 else Vector3(1, 0, 0)
		_steal_phase = 0   # a spooked thief drops the heist
		if _carry:
			_carry.queue_free()
			_carry = null
		ANIM.drive(_gen_mats, 3.0, 0.2, 0.07)
		if _wings:
			_wings.takeoff()   # same thrown-up flush silhouette as the deck birds
		AudioDirector.play_one_shot("wingbeat", global_position, -8.0)   # wings, not voice
		Journal.discover("creature_gull")

	## The heist loop: pick a loose topside takeable, swoop, carry it — in view,
	## dangling — to the nest, and glide home like nothing happened.
	func _theft(delta: float) -> void:
		match _steal_phase:
			0:
				_steal_timer -= delta
				if _steal_timer <= 0.0:
					_steal_timer = randf_range(90.0, 160.0)
					_target = _find_loot()
					if _target:
						_steal_phase = 1
			1:
				if not is_instance_valid(_target):
					_steal_phase = 3
					return
				if _fly_to(_target.global_position + Vector3(0, 0.3, 0), delta, 6.0):
					_loot_id = _target.item_id
					_target.queue_free()
					_carry = ItemVisual.build(_loot_id)
					add_child(_carry)
					_carry.position = Vector3(0, -0.35, 0)
					_carry.scale = Vector3(0.7, 0.7, 0.7)
					var player: Node3D = get_tree().get_first_node_in_group("player")
					var hud: Node = get_tree().get_first_node_in_group("hud")
					if hud and player and player.global_position.distance_to(global_position) < 28.0:
						hud.toast("A gull just made off with something. It flew toward the bunkhouse roof.")
					_steal_phase = 2
			2:
				var nests: Array = get_tree().get_nodes_in_group("gull_nest")
				var nest: Node = nests.front() if not nests.is_empty() else null
				var nest_pos: Vector3 = nest.global_position if nest else _perch
				if _fly_to(nest_pos + Vector3(0, 0.6, 0), delta, 5.0):
					if nest and _loot_id != "":
						nest.items.append(_loot_id)
					if _carry:
						_carry.queue_free()
						_carry = null
					_loot_id = ""
					_steal_phase = 3
			3:
				if _fly_to(_perch, delta, 5.0):
					_steal_phase = 0

	func _fly_to(dest: Vector3, delta: float, speed: float) -> bool:
		var to: Vector3 = dest - global_position
		if to.length() < 0.35:
			return true
		# Arc a little upward mid-flight so it reads as flight, not sliding — and beat the
		# wings while doing it: the heist swoops used to fly on whatever rate/amp the last
		# state left in the shader, i.e. usually the perched idle's near-nothing.
		ANIM.drive(_gen_mats, 4.4, 0.2, 0.13)
		var step: Vector3 = to.limit_length(speed * delta)
		step.y += minf(to.length() * 0.02, 0.05)
		# Wall-tested like every other 3D move on this rig now. On a block it climbs —
		# the loot run detours over an obstacle rather than through it.
		var res: Dictionary = FaunaMove.swim_clear(self, global_position,
			global_position + step, 0.30, BloomFauna.fauna_bodies(self))
		if bool(res["blocked"]):
			res = FaunaMove.swim_clear(self, global_position,
				global_position + Vector3(0, speed * delta * 0.8, 0), 0.30,
				BloomFauna.fauna_bodies(self))
		global_position = res["pos"]
		var flat := Vector3(to.x, 0, to.z)
		if flat.length_squared() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), delta * 4.0)
		return false

	## Loose loot = takeables sitting on the open topside deck, nothing story-critical.
	func _find_loot() -> Node3D:
		var best: Node3D = null
		var best_d: float = 26.0
		var stack: Array[Node] = [get_tree().current_scene]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if n is Takeable and not NEVER_STEAL.has(n.item_id):
				var p: Vector3 = (n as Node3D).global_position
				if p.y > 17.9 and p.y < 19.6 and absf(p.x) < 30.0 and absf(p.z) < 22.0:
					var d: float = p.distance_to(global_position)
					if d < best_d:
						best_d = d
						best = n
		return best
