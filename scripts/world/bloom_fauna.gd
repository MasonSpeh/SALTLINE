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
##   LampSnail    — night constellations of glow-spots circling the leg bases (§54)
##   CorvidGull   — perched Bloom-intelligent gull that tracks the player (§26)
##   GiantCrab    — the night threat: fourteen, free-roaming, and they climb after you
##   KingCrab     — two boss-tier giants in the deep; each rolls 50% a night to come up

const ANIMH := preload("res://scripts/world/creature_anim.gd")
const CRAB := preload("res://scripts/world/crab.gd")   # by path: class cache lags new names
const TEAL := Color(0.2, 0.9, 0.85)
const DIM_TEAL := Color(0.12, 0.5, 0.48)
const PEARL := Color(0.88, 0.94, 0.92)

## --- Giant crabs (s15): FOURTEEN, spread around the four caisson legs --------------
## DAY: every crab clings to a submerged face of one of the 4 caisson legs (6x6 boxes at
## x=±22 z=±12 — SE fills x[19,25] z[-15,-9]), sidling its cling loop — visible to anyone
## who leans over a rim or swims. The crab carries a snail-style surface frame now
## (crab.gd `up` + per-frame seat), so each loop names the FACE NORMAL it clings to and
## the seat pins the feet to the real concrete: no more hovering at hand-typed heights.
## NIGHT: on a staggered cue each crosses to the EAST rim (x~30.25, the one clean water
## edge), climbs an authored lane, and then FREE ROAMS — s16 replaced the two fixed patrol
## rings with roam boxes that live in crab.gd's level tree, and a crab that senses you on
## another deck climbs the stair tower to reach you. Waypoint heights are advisory; the
## seat owns the floor.
const CRAB_COUNT: int = 14
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

## Build one emergence climb up the east deck rim at depth-lane z: open water beyond the
## rim (x31) -> up the rim face -> onto the deck lip (x29.3, y2.6). Walked in reverse at
## dawn / when scared, to go back over the side.
func _crab_climb(z: float) -> Array:
	return [Vector3(31.0, -0.5, z), Vector3(30.6, 0.6, z),
		Vector3(30.3, 1.7, z), Vector3(29.3, 2.6, z)]

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
	# 14 crabs over 10 authored cling loops: the modulo doubles four of them up. A
	# lane-mate offset walks the second crab a couple of metres along its loop so the
	# pair reads as two animals sharing a leg face, not one crab drawn twice.
	for i in range(CRAB_COUNT):
		var crab: Node3D = CRAB.new()
		crab.spawn_index = i
		var roost: Dictionary = CRAB_ROOSTS[i % CRAB_ROOSTS.size()]
		crab.roost_loop = roost["loop"]
		crab.roost_up = roost["up"]
		# Transit legs: the climb lanes are all on the EAST rim, so crabs roosting on
		# the west and north legs get authored swim waypoints routing them AROUND the
		# solid pontoon (x16..28, z-16..-8) and the deck structures instead of straight
		# through them — the emergence is direct (probe-free) motion, so without these
		# a NW crab would swim through 40m of concrete on its way to the rim. FLEE walks
		# the same list backwards, so the retreat retraces the same honest route home.
		var lead: Array = []
		var rk: int = i % CRAB_ROOSTS.size()
		if rk in [3, 4]:        # NE leg: east around the rim, outside x30.25
			lead = [Vector3(30.8, -1.2, 4.0)]
		elif rk in [5, 6, 7]:   # SW leg: south of the pontoon, along the dock lane
			lead = [Vector3(-22.0, -1.2, -18.5), Vector3(0.0, -1.4, -19.8),
				Vector3(22.0, -1.2, -20.5)]
		elif rk in [8, 9]:      # NW leg: across the north face, then down the east rim
			lead = [Vector3(0.0, -1.2, 17.0), Vector3(30.8, -1.2, 4.0)]
		crab.emerge_path = lead + _crab_climb(CRAB_EMERGE_Z[i % CRAB_EMERGE_Z.size()])
		crab.patrol_loop = CRAB_PATROL_EAST if (i % 2) == 0 else CRAB_PATROL_SOUTH
		crab.patrol_offset = offsets[i % offsets.size()]
		add_child(crab)
		var seat: Vector3 = crab.roost_loop[0]
		if i >= CRAB_ROOSTS.size():
			var loop: Array = crab.roost_loop
			seat = (loop[0] as Vector3).lerp(loop[1] as Vector3, 0.55)
		crab.global_position = seat

## --- KING CRABS (s16): exactly TWO, and neither is a given -------------------------
## Two boss-tier animals, and that is the hard cap — the owner's spec is "at most 2 active
## at a time". They do not roost on the legs with the pack: each lies up in DEEP water well
## off the east rim (y-8, past the boat-landing lane at x34, so nothing on the rig can be
## walked into on the way in), and each independently rolls a 50% chance every night of
## hauling out to hunt. The roll lives in king_crab._on_night(); all this does is place
## them and hand each one its own haul-out lane.
##
## Lanes are the SAME rim climb the pack uses (x31 -> x29.3 over the lip), on two depth
## lanes of their own — z-9.5 and z-19.5 — so a king never comes up a lane the pack is
## queued in, and the two kings never share one. RETREAT walks the list backwards.
const KING := preload("res://scripts/world/king_crab.gd")   # by path: class cache lags new files
const KING_COUNT: int = 2
const KING_LANE_Z: Array = [-9.5, -19.5]

func _spawn_king_crabs() -> void:
	for i in range(KING_COUNT):
		var z: float = KING_LANE_Z[i % KING_LANE_Z.size()]
		var king: Node3D = KING.new()
		king.spawn_index = i
		king.den = Vector3(38.0, -8.0, z)
		king.rise_path = [Vector3(34.5, -5.0, z), Vector3(32.0, -2.0, z)] + _crab_climb(z)
		add_child(king)
		king.global_position = king.den

func _ready() -> void:
	_spawn_giant_crabs()
	_spawn_king_crabs()
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
	add_child(HarborSeal.new())      # day patrol + curiosity (befriendable canon)
	add_child(HarborSeal.new())
	# Lamp Snails: glowing constellations circling the leg bases at night (§54).
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
	# Anchor limpets welded into the splash zone (54d), near the barnacle faces.
	var limpet_spots: Array[Vector3] = [Vector3(-19.0, 1.55, -11.4), Vector3(19.0, 1.7, 11.4),
			Vector3(-21.6, 1.35, -9.6), Vector3(24.6, 1.5, -12.4), Vector3(22.2, 1.25, 9.6)]
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
	var perches := [Vector3(24.9, 2.75, -16.0), Vector3(-8.6, 18.75, 6.4), Vector3(27.6, 18.75, 4.0)]
	for i in range(perches.size()):
		var cg := CorvidGull.new(perches[i])
		cg.thief = i == 1   # the bunkhouse-rail bird works the topside deck
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
	add_child(ReefFish.new(Vector3(19.0, 0.0, -12.0)))
	add_child(ReefFish.new(Vector3(22.0, 0.0, 9.0)))
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
const SNAIL_GROUPS: Dictionary = {"lamp": "snail_lamp", "rust": "snail_rust", "glass": "snail_glass"}

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

	func _process(delta: float) -> void:
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

	func _process(delta: float) -> void:
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
		global_position = Vector3(cos(angle) * radius, 0.35 + sin(_t * 0.8 + _idx) * 0.25, sin(angle) * radius)
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

	func _process(delta: float) -> void:
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

	func _process(delta: float) -> void:
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

	func _process(delta: float) -> void:
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

	func _process(delta: float) -> void:
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
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/tide_worm/tide_worm.glb"
	var _gen_mats: Array = []
	var _t: float = 0.0
	var _body: Node3D
	var _emerge: float = 0.0

	func _ready() -> void:
		_t = global_position.x * 1.3
		var hole := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.14
		hm.bottom_radius = 0.14
		hm.height = 0.02
		hm.material = BloomFauna.glow_mat(Color(0.04, 0.05, 0.06), 0.0)
		hole.mesh = hm
		add_child(hole)
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
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 0.32, ANIM.Mode.UNDULATE, 0.07, 1.1, BloomFauna.TEAL)
		if not gen.is_empty():
			_gen_mats = gen["mats"]
			ANIM.drive(_gen_mats, 1.1, 0.45)

	func _process(delta: float) -> void:
		_t += delta
		var tide_time: bool = GameClock.current_phase == GameClock.Phase.DAWN \
			or GameClock.current_phase == GameClock.Phase.DUSK
		var want: float = 1.0 if tide_time else 0.0
		var player: Node3D = get_tree().get_first_node_in_group("player")
		if player and player.global_position.distance_to(global_position) < 2.5:
			want = 0.0   # felt your footsteps — gone
		_emerge = move_toward(_emerge, want, delta * (2.5 if want < _emerge else 0.35))
		if _emerge > 0.5:
			Journal.discover_if_near(self, "creature_tide_worm", 5.0)
		_body.scale.y = maxf(_emerge, 0.001)
		_body.visible = _emerge > 0.02
		_body.rotation.x = sin(_t * 1.7) * 0.22 * _emerge
		# Retracted worms don't ripple: the wave fades out with the animal.
		ANIM.drive(_gen_mats, 1.1 * _emerge, 0.45 * _emerge, 0.07 * _emerge)
		_body.rotation.z = cos(_t * 1.3) * 0.22 * _emerge


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

	func _process(delta: float) -> void:
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

	func _process(delta: float) -> void:
		_t += delta
		_presence = move_toward(_presence, 1.0 if GameClock.current_phase == GameClock.Phase.NIGHT else 0.0, delta * 0.08)
		visible = _presence > 0.02
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
		_from = -dir * dist + Vector3(0, randf_range(45.0, 55.0), 0)
		_to = dir * dist + Vector3(0, randf_range(45.0, 55.0), 0)
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
	## the rig, porpoising up to breathe, and by day hauls out to bask on the wet
	## deck edge. Curious, never afraid — it turns to watch a nearby player.
	var _t: float = 0.0
	var _head: Node3D
	var _mat: StandardMaterial3D
	var _flippers: Array = []
	var _hauled: bool = false            ## day rest on the dock corner
	var _haul_timer: float = 0.0
	const HAUL_SPOT := Vector3(9.0, 2.25, -21.2)    # SW tide-line corner, off the walk lanes
## Twice moved, now settled: (25.8,-20.6) put its head inside a rusted drum, and
## (24.2,-19.2) parked it in the respawn->stairs walk lane where players tripped over
## it. The south-west corner by the deck edge is off every route (dock gangplank lands
## x19.5, stairs are x23.6, stores door faces north) and its head hangs over open
## water at the rim, which is exactly where a hauled-out seal would point.

	func _ready() -> void:
		_t = randf() * 10.0
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
		# Touchable when hauled out: pet it, or offer a fish (Codex §29 befriending).
		var touch := FaunaTouch.new("Harbor Seal", 0.95, _touch_verbs, _touch_act)
		add_child(touch)
		touch.position = Vector3(0, 0.3, 0)

	func _process(delta: float) -> void:
		_t += delta
		var player: Node3D = get_tree().get_first_node_in_group("player")
		# Haul-out: by day it sometimes lugs itself onto the tide-line corner and
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
			global_position = global_position.lerp(HAUL_SPOT, delta * 1.5)
			rotation.z = lerp_angle(rotation.z, 0.0, delta * 2.0)
			rotation.x = lerp_angle(rotation.x, -0.12, delta * 2.0)   # chest-up rest pose
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
		var ang: float = _t * 0.16
		var r: float = 20.0 + sin(_t * 0.1) * 6.0
		var breathe: float = sin(_t * 0.6)          # porpoising rhythm
		var y: float = -0.15 + maxf(breathe, 0.0) * 0.5   # crests above the surface to breathe
		var pos := Vector3(cos(ang) * r * 0.7, y, -34.0 + sin(ang) * r)
		var vel: Vector3 = pos - global_position
		global_position = pos
		if vel.length_squared() > 0.0001:
			look_at(pos + vel, Vector3.UP)
		rotation.x += clampf(vel.y * 2.0, -0.4, 0.4)   # pitch into the porpoise arc
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

	## Only the first seal hauls out — one resident, one patroller.
	func _idx_zero() -> bool:
		return get_index() % 2 == 0

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


# ------------------------------------------------- Lamp Snail constellation
class LampSnail extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL_PATH := "res://assets/models/fauna/lamp_snail/lamp_snail.glb"
	var _gen_mats: Array = []
	## Wheelbarrow-sized gastropods (Codex §54), shells constellated with
	## bioluminescent spots. By night they drift the rig-leg bases; their glow is
	## visible through the water — the "lean over the rail" wonder-beat.
	var _t: float
	var _base: Vector3
	var _spots: Array[StandardMaterial3D] = []
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
		# The dome carries a dim teal bioluminescence of its own — at energy 0.0 the shell
		# was matte black and only the pin-prick spots lit, so the "lamp" snail read as a
		# dark lump with sparkles instead of a glowing animal.
		sm.material = BloomFauna.glow_mat(Color(0.09, 0.30, 0.30), 0.55)
		shell.mesh = sm
		add_child(shell)
		# The foot beneath.
		var foot := MeshInstance3D.new()
		var fm := CapsuleMesh.new()
		fm.radius = 0.2
		fm.height = 0.9
		# The foot glows fainter than the dome — light bleeding through soft tissue.
		fm.material = BloomFauna.glow_mat(Color(0.10, 0.24, 0.24), 0.30)
		foot.mesh = fm
		foot.rotation.x = deg_to_rad(90)
		foot.position.y = -0.15
		add_child(foot)
		# Two optic tentacles reaching off the leading edge of the foot (+Z), each
		# tipped with a small light-sensing eye bulb — the snail "reads" the dark.
		_eye_mat = BloomFauna.glow_mat(BloomFauna.TEAL, 1.5)
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
		# The constellation: glow spots scattered on the shell.
		var rng := RandomNumberGenerator.new()
		rng.seed = 400 + _idx
		for i in range(rng.randi_range(7, 11)):
			var spot := MeshInstance3D.new()
			var pm := SphereMesh.new()
			pm.radius = 0.05
			pm.height = 0.1
			var m := BloomFauna.glow_mat(BloomFauna.TEAL, 2.0)
			_spots.append(m)
			pm.material = m
			spot.mesh = pm
			var u: float = rng.randf() * TAU
			var v: float = rng.randf_range(0.1, 0.95)
			spot.position = Vector3(cos(u) * 0.42 * sqrt(1.0 - v * v), v * 0.42, sin(u) * 0.42 * sqrt(1.0 - v * v))
			add_child(spot)
		# A gentle pool of light cast on the deck plate — warm teal, soft attenuation, no shadow.
		_lamp_light = OmniLight3D.new()
		_lamp_light.light_energy = 0.65
		_lamp_light.omni_range = 3.0
		_lamp_light.light_color = Color(0.35, 0.95, 0.88)  # warm teal
		_lamp_light.shadow_enabled = false
		add_child(_lamp_light)
		# The journal's promised beat: a gentle harvest takes the glow-mucus, leaves the
		# animal. Only at night, and the constellation needs time to re-charge. Crouch
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
		# Generated mesh: a faint shell flex; the constellation does the real work.
		# PEDAL: the foot ripples back-to-front, which is how a snail actually travels.
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 0.9, ANIM.Mode.PEDAL, 0.03, 0.55, BloomFauna.TEAL)
		if not gen.is_empty():
			_gen_mats = gen["mats"]
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
			hud.toast("It takes the greens eagerly — the constellation brightens.")

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
	## snail leaving the deck dims the constellation by exactly one light, same as a
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

	func _process(delta: float) -> void:
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
		var glow: float = 2.0 if night else 0.0
		if _harvest_cd > 120.0:
			glow *= 0.15   # freshly wiped — the constellation re-charges slowly
		# Fed reads as visibly brighter and a touch faster — the "I fed it" feedback.
		var pulse_rate: float = 1.05 if _fed else 0.8
		var pulse_mul: float = 1.3 if _fed else 1.0
		for i in range(_spots.size()):
			# The constellation twinkles — each spot on its own slow beat.
			_spots[i].emission_energy_multiplier = lerpf(_spots[i].emission_energy_multiplier,
				glow * pulse_mul * (0.55 + 0.45 * sin(_t * pulse_rate + i * 1.3)), delta * 1.5)
		# The lamp light pulses with the constellation, dimming when freshly harvested.
		if _lamp_light:
			var light_energy: float = glow * pulse_mul * (0.55 + 0.45 * sin(_t * pulse_rate)) * 0.325
			_lamp_light.light_energy = lerpf(_lamp_light.light_energy, light_energy, delta * 1.5)
		visible = night or global_position.y > 0.0
		# The pedal wave runs only while it is out crawling.
		ANIM.drive(_gen_mats, 0.55 if night else 0.0, glow * 0.35, 0.03 if night else 0.0)
		if night:
			Journal.discover_if_near(self, "creature_lamp_snail", 12.0)
		# Eye stalks sway on their own slow rhythm; the eye bulbs pick up the glow.
		if _eye_mat:
			_eye_mat.emission_energy_multiplier = lerpf(_eye_mat.emission_energy_multiplier, 1.5 if night else 0.0, delta * 2.0)
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

# -------------------------------------------------------------- DeckGull
class DeckGull extends Node3D:
	## A gull DOWN ON THE DECK, strutting between pecks — the ordinary life the rig
	## still carries. Walks its little patch; feels you coming and FLUSHES: leaps,
	## climbs away to nothing, and lands again somewhere else a minute later.
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MOVE := preload("res://scripts/world/fauna_move.gd")
	const MODEL_PATH := "res://assets/models/fauna/corvid_gull/corvid_gull.glb"
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
	var _closest: float = 1e9     ## closest the player has crept this landing (threat roll)
	var _look_cd: float = 0.0     ## idle head-turn clock
	var _look_yaw: float = 0.0
	## Legs: the generated body (like every text-to-3D asset here — see
	## creature_anim.gd) is a single static mesh with no skeleton to animate, so a
	## real walk cycle needs its own procedural pivots, the same way crab.gd's 8 legs
	## do. Two is enough to read as a strutting bird; ANIM.attach (unlike .replace)
	## never hides pre-existing geometry, so these stay visible next to the model.
	var _leg_l: Node3D
	var _leg_r: Node3D

	func _init(home: Vector3) -> void:
		_home = home
		_target = home

	func _ready() -> void:
		var gen: Dictionary = ANIM.attach(self, MODEL_PATH, 0.5, ANIM.Mode.FLAP,
			0.012, 0.6, Color(0.30, 0.85, 0.80), randf() * TAU)
		if gen.is_empty():
			queue_free()   # no mesh, no bird — walkers have no procedural fallback
			return
		_model = gen["model"]
		_gen_mats = gen["mats"]
		ANIM.drive(_gen_mats, 0.6, 0.15)
		global_position = _home
		_peck = randf_range(2.0, 5.0)
		_leg_l = _build_leg(-0.045)
		_leg_r = _build_leg(0.045)
		# Grab it if you can reach it before it flushes — crouch-sneak to close the gap.
		var touch := FaunaTouch.new("Deck Gull", 0.9, _grab_verbs, _grab_act)
		add_child(touch)

	## A hip pivot at the body with a thin shin hanging from it, so rotating the
	## pivot swings the whole leg from the top the way a real stride works instead
	## of just tilting a stick planted at the ground.
	func _build_leg(side_x: float) -> Node3D:
		var hip := Node3D.new()
		add_child(hip)
		hip.position = Vector3(side_x, 0.16, 0.0)
		var shin := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.008
		cm.bottom_radius = 0.011
		cm.height = 0.14
		cm.material = BloomFauna.glow_mat(Color(0.8, 0.6, 0.2), 0.0)
		shin.mesh = cm
		hip.add_child(shin)
		shin.position = Vector3(0, -0.07, 0)
		return hip

	func _process(delta: float) -> void:
		_t += delta
		if _regen > 0.0:
			_regen -= delta
			if _regen <= 0.0:
				# Lands again a few metres from home, grounded state reset.
				global_position = _home + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
				_flushing = -1.0
				visible = true
				_closest = 1e9   # a fresh bird lets the player re-earn the flush
				ANIM.drive(_gen_mats, 0.6, 0.15, 0.012)
			return
		var player: Node3D = get_tree().get_first_node_in_group("player")
		if _flushing >= 0.0:
			# Airborne: climb away hard, wings at full beat, then gone until respawn.
			_flushing += delta
			global_position += _flush_dir * delta * 6.5 + Vector3(0, delta * 3.2, 0)
			rotation.y = atan2(_flush_dir.x, _flush_dir.z) + PI
			# Legs tuck up under the body in flight, not stay planted for the ground stride.
			if _leg_l and _leg_r:
				_leg_l.rotation.x = lerpf(_leg_l.rotation.x, deg_to_rad(-100.0), delta * 6.0)
				_leg_r.rotation.x = lerpf(_leg_r.rotation.x, deg_to_rad(-100.0), delta * 6.0)
			if _flushing > 3.0:
				visible = false
				_regen = randf_range(45.0, 90.0)
			return
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
			if _leg_l and _leg_r:
				# Opposite-phase stride, same swing frequency as the waddle above so the
				# legs and the body roll read as one gait rather than two separate ticks.
				_leg_l.rotation.x = sin(_t * 7.0) * 0.5
				_leg_r.rotation.x = sin(_t * 7.0 + PI) * 0.5
		elif _model:
			# Pecking: quick bow, twice, then upright — reads as feeding.
			_model.rotation.x = maxf(sin(_t * 5.0), 0.0) * 0.5 * maxf(sin(_t * 0.7), 0.0)
			_model.rotation.z = lerpf(_model.rotation.z, 0.0, delta * 4.0)
			if _leg_l and _leg_r:
				_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, delta * 5.0)
				_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, delta * 5.0)
			# Idle head-turns: it glances around on its own organic clock.
			_look_cd -= delta
			if _look_cd <= 0.0:
				_look_cd = randf_range(1.4, 4.2)
				_look_yaw = rotation.y + randf_range(-1.3, 1.3)
			rotation.y = lerp_angle(rotation.y, _look_yaw, delta * 2.5)

	## Airborne flush: leap up and away from the player, then gone until it re-lands.
	func _flush(player: Node3D) -> void:
		_flushing = 0.0
		var away: Vector3 = (global_position - player.global_position) if player else Vector3(1, 0, 0)
		away.y = 0.0
		_flush_dir = away.normalized() if away.length() > 0.1 else Vector3(1, 0, 0)
		ANIM.drive(_gen_mats, 3.2, 0.25, 0.07)   # wings open, full beat
		AudioDirector.play_one_shot("gull", global_position, -8.0)
		Journal.discover("creature_corvid_gull")

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
		Journal.discover("creature_corvid_gull")
		AudioDirector.play_one_shot("gull", global_position, -6.0)
		visible = false
		_flushing = -1.0
		_regen = randf_range(60.0, 120.0)   # another gull drops onto the deck later
		if hud and hud.has_method("toast"):
			hud.toast("You get both hands round it before it can bolt. A sea-bird for the pot.")

# -------------------------------------------------------------- ReefFish
class ReefFish extends Node3D:
	## A loose school of mutated reef fish at diving depth around a rig leg — colour
	## variants of the one bait-fish mesh (tint + glow), each on its own wander orbit.
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
			ANIM.drive(gen["mats"], 2.4, 0.5)
			_fish.append({"node": f, "r": randf_range(1.2, 3.2), "h": randf_range(-4.2, -1.6),
				"spd": randf_range(0.25, 0.55) * (1.0 if i % 2 == 0 else -1.0),
				"ph": randf_range(0.0, TAU), "gone": 0.0})
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

	func _process(delta: float) -> void:
		for f in _fish:
			if f["gone"] > 0.0:
				f["gone"] -= delta
				if f["gone"] <= 0.0:
					(f["node"] as Node3D).visible = true
			var a: float = Time.get_ticks_msec() * 0.001 * f["spd"] + f["ph"]
			var pos: Vector3 = _centre + Vector3(cos(a) * f["r"], f["h"] + sin(a * 2.3) * 0.3, sin(a) * f["r"])
			var node: Node3D = f["node"]
			# These orbit a rig leg — don't let one clip through the caisson. Stop it at the
			# steel; its orbit carries it back out next frame.
			pos = FaunaMove.swim_clear(node, node.global_position, pos, 0.25)["pos"]
			var vel: Vector3 = pos - node.global_position
			node.global_position = pos
			if vel.length_squared() > 0.00001:
				node.look_at(pos + vel, Vector3.UP)
		var player: Node3D = get_tree().get_first_node_in_group("player")
		if player and player.get("swimming") and player.swimming 				and player.global_position.distance_to(_centre) < 8.0:
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

	func _process(delta: float) -> void:
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

	func _process(delta: float) -> void:
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

	func _process(delta: float) -> void:
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
	const MODEL_PATH := "res://assets/models/fauna/corvid_gull/corvid_gull.glb"
	const GLOW := Color(0.30, 0.85, 0.80)
	var _gen_mats: Array = []
	## A Bloom-intelligent gull (Codex §26) perched on a rail, watching. Tilts its
	## head to track the player — and one of them STEALS: loose takeables on the
	## topside deck get carried, visibly, to the nest on the bunkhouse roof.
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
		var gen: Dictionary = ANIM.replace(self, MODEL_PATH, 0.55, ANIM.Mode.FLAP, 0.05, 1.0, GLOW)
		if not gen.is_empty():
			_gen_mats = gen["mats"]
			ANIM.drive(_gen_mats, 1.0, 0.2)   # steady — no per-frame cost

	func _process(delta: float) -> void:
		_t += delta
		var day: bool = GameClock.current_phase == GameClock.Phase.DAY \
			or GameClock.current_phase == GameClock.Phase.DAWN
		# Flee (Codex threat behaviour): it bolts off the perch and returns later.
		if _flee_regen > 0.0:
			_flee_regen -= delta
			if _flee_regen <= 0.0:
				global_position = _perch   # settles back on its rail
				_fleeing = -1.0
				_closest = 1e9
			else:
				return
		if _fleeing >= 0.0:
			_fleeing += delta
			global_position += _flee_dir * delta * 6.5 + Vector3(0, delta * 3.4, 0)
			rotation.y = atan2(_flee_dir.x, _flee_dir.z) + PI
			ANIM.drive(_gen_mats, 3.0, 0.2, 0.07)
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
			Journal.discover_if_near(self, "creature_corvid_gull", 20.0)
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
		AudioDirector.play_one_shot("gull", global_position, -8.0)
		Journal.discover("creature_corvid_gull")

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
		# Arc a little upward mid-flight so it reads as flight, not sliding.
		var step: Vector3 = to.limit_length(speed * delta)
		step.y += minf(to.length() * 0.02, 0.05)
		global_position += step
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
