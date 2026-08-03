class_name LegReef extends Node3D
## The coral reef growing down the four caisson legs, and the starfish on the rig's
## submerged foundation.
##
## s20 — LUSH (owner brief). The s19 reef was corals in patches on bare concrete. This is
## an ecosystem: pre-sculpted REEF MASSES (four growth forms fused into one piece) anchor
## every colony and the singles grow out of them, so the wall reads as a continuous living
## crust rather than ornaments hung on it; SPONGES and BARNACLE crusts fill between the
## colonies and run the whole leg from the pontoon down; four big STARFISH species ride the
## legs as well as the foundation; and two species of snail actually CRAWL the concrete.
## Emission was raised from 0.15 to a value that clears the environment's glow threshold —
## see GLOW.
##
## This is the reef a diving player actually swims through. underwater_world's
## `_leg_reef_growth` already dresses the *reachable* band on the legs (anemones,
## sponges, sea grass, y -2.5..-10.5) and `_kelp_forest` stands a kelp ring around
## each footing. Below that the concrete ran bare all the way to the mud. This grows
## the real reef into that gap: seven coral forms in patchy colonies down the steel,
## thinning with depth, and three starfish species scattered over the pontoon slabs.
##
## Spawned by reef_life.gd (which reef_detail spawns, which seabed spawns) so it lives
## in the same subtree and inherits the same visual-only, no-collision contract. It is
## its own file rather than more of reef_life because it shares nothing with the wreck-
## field communities: different geometry (steel, not mud), different seating (probed
## surfaces, not floor_height) and a different renderer path (MultiMesh, not one node
## and one ShaderMaterial per animal).
##
## WHAT IS MEASURED RATHER THAN TYPED
##   * the caisson faces — sonar scan says every one is exactly 3.0 m from its centre
##     line at every depth; a physics raycast per instance confirms it at build time
##     and supplies the exact seating point, so nothing here hand-types an X, Y or Z
##     against the concrete
##   * the top of the reef band — derived from the real world AABB of the vegetation
##     already standing on the legs, so the reef starts BELOW whatever kelp and grass
##     actually reach rather than below where the source says they should
##   * the foundation planes — probed the same way, from a point known to be in open
##     water toward the slab
##
## WHY MULTIMESH
## gl_compatibility is draw-call bound (see mesh_batcher.gd: frame time tracks call
## count almost linearly and barely notices triangles). Three hundred corals as three
## hundred nodes with three hundred ShaderMaterials would be a straight regression on
## a rig already measured at 9.3 fps. One MultiMesh per species PER LEG is 4 calls a
## species with a tight AABB, so looking at one leg frustum-culls the other three.

const REEF_PATH := "res://assets/models/fauna/reef/%s/%s.glb"
## The tropical fish that live ON this reef. Preloaded by PATH, not by class_name — the
## global class cache lags for a new file.
const REEF_FISH := preload("res://scripts/world/reef_fish.gd")
## The harvestable mussel beds among the coral (s21). Same contract as REEF_FISH: it is
## handed `colony_seats` and owns everything else itself, so this file stays the reef's LOOK
## and nothing about harvesting, saving or the game calendar lands in here.
const MUSSELS := preload("res://scripts/world/mussel_beds.gd")

## Verified by sonar (`spatial_raycast` along -x into the leg at eight depths, all
## hitting x=25.000 for the leg centred on x=22) and re-checked every run by
## tests/ReefProbe.tscn. The caisson is one casting from the deck rim to y -92, so
## this holds at every depth in the band.
const LEG_HALF: float = 3.0
const LEGS: Array[Vector2] = [Vector2(-22, -12), Vector2(22, -12),
		Vector2(-22, 12), Vector2(22, 12)]

## The pontoon skirt that sleeves all four footings: slab top y 0.95, underside
## y -3.05, plan x[-28,28] and |z| in [8,16]. Probed, not read off rig_builder —
## a ray up from y -40 at (22,-12) first meets solid at y -3.050.
const SKIRT_BOTTOM: float = -3.05
const SKIRT_X: float = 28.0
const SKIRT_Z_OUT: float = 16.0
const SKIRT_Z_IN: float = 8.0

## How far below the deepest vegetation the reef starts, and how far down it runs.
##
## s34: THE BAND RUNS TO -40 NOW, AND THE OLD REASON FOR -22 EXPIRED THIS SESSION. The note
## that used to sit here said "the fog grade swallows everything past ~40 m ... so growing
## coral below -30 is triangles nobody will ever see", and against the fog it was written
## for that was true: 0.19/m at the band, i.e. 5% contrast at 15 m. The s34 re-grade runs
## 0.105/m with the abyss ramp pushed to -26, so the water below -22 is now somewhere you
## can actually see, and it was 70 m of bare concrete between the reef bottom and the mud.
## The owner has asked three times for the reef to expand DOWN THE SUPPORTS; this is that.
##
## The band goes from ~9.3 m tall to ~27.3 m, and the placement counts scale with it (see
## BAND_SCALE) so the result is roughly 3x the coral rather than the same coral stretched
## thinner. What makes it affordable is s32's distance cull — REEF_DRAW_M 55 with an 18 m
## fade on every one of these MultiMeshes — so a diver at any one depth is only ever paying
## for the slice around them, not for the whole column.
const BAND_GAP: float = 0.6
const BAND_BOTTOM: float = -40.0
## Fallback if the vegetation walk finds nothing (it never has in practice) — the
## authored bottom of underwater_world's growth band, minus the gap.
const BAND_TOP_FALLBACK: float = -12.6

## How much taller the s34 band is than the one every count in this file was tuned against.
## DERIVED, so that moving BAND_BOTTOM again moves the stocking with it instead of quietly
## thinning the reef out: the old band ran from the measured vegetation floor (-12.69 on the
## last probe) to -22.0, i.e. 9.31 m, and every "attempts" number here was chosen against
## that. Anything that scatters over the band's full height is multiplied by this.
const OLD_BAND_H: float = 9.31
## ...but not linearly. Light and food both fall off with depth, so a real reef thins going
## down rather than repeating at constant density, and so should the triangle bill: 0.78
## puts ~2.3x the coral on a 2.9x taller band, which reads as a reef that keeps going and
## costs less than one that is uniformly dense to -40.
const BAND_TAPER: float = 0.78

static func band_scale(top: float) -> float:
	return maxf(1.0, ((top - BAND_BOTTOM) / OLD_BAND_H) * BAND_TAPER)

## Prevailing set. The gyre eye is at (0,0,-52), i.e. the water sets south past the
## rig, so a face looking north (+z) takes the oncoming flow. Colonies favour that,
## and favour the outboard faces over the ones standing in the structure's own wake.
const CURRENT := Vector3(0.0, 0.0, -1.0)

## Nothing may grow in these — the Dock Ladder's climb column (rig_builder puts the
## ladder at 24.6, -1.4, -22.42) and the open water a swimmer uses to reach the wet
## deck. Both are well clear of the leg faces and the pontoon, but they are checked
## rather than assumed, because "well clear" is what every floating prop in this repo
## was before somebody measured it.
const KEEP_OUT := [
	{"c": Vector3(24.6, -1.0, -22.42), "r": 2.2},   # Dock Ladder + its latch point
	{"c": Vector3(20.0, -4.0, -19.0), "r": 3.0},    # wet-deck swim approach
]

## slug, min/max longest-axis metres, spacing radius factor, tilt range (deg off the
## surface normal, toward the light), depth bias (0 = crowds the top of the band,
## 1 = crowds the bottom), colony weight, and the tint pair its per-instance colour
## is drawn between. Weights are per-colony DOMINANCE, so a reef reads as patches of
## one species with a few others in them rather than a uniform species soup.
##
## coral_whip was generated, decimated and PLACED before being cut: a sea whip is a
## 2 cm wand, and at any distance you actually see the caisson from, a colony of them
## renders as red scratches on the concrete — it read as paint damage, not as life.
## The asset judged fine in isolation; it lost on the wall. Looked at, not assumed.
## s20 REWEIGHT. The generated albedos skew pale — cream staghorn, off-white bubble, chalk
## barnacle — and the first lush render came back monochrome cream even though four of the
## species are strongly coloured. So weight moved off the pale-and-expensive species
## (coral_brain was the single biggest triangle line in the reef at 100 x 5,000) and onto the
## purple fan and the warm plate. Same total density, more hue.
const CORALS := [
	{"slug": "coral_branch_a", "lo": 0.55, "hi": 1.40, "space": 0.55, "tilt": [12.0, 38.0],
		"depth": 0.15, "w": 0.95, "a": Color(0.86, 0.84, 0.74), "b": Color(1.00, 0.96, 0.88)},
	{"slug": "coral_branch_b", "lo": 0.35, "hi": 0.90, "space": 0.60, "tilt": [8.0, 30.0],
		"depth": 0.35, "w": 1.10, "a": Color(0.62, 0.86, 1.00), "b": Color(0.88, 0.98, 1.00)},
	{"slug": "coral_plate", "lo": 0.60, "hi": 1.70, "space": 0.50, "tilt": [18.0, 44.0],
		"depth": 0.55, "w": 1.05, "a": Color(0.92, 0.68, 0.44), "b": Color(1.00, 0.88, 0.70)},
	{"slug": "coral_brain", "lo": 0.35, "hi": 0.95, "space": 0.62, "tilt": [4.0, 22.0],
		"depth": 0.50, "w": 0.75, "a": Color(0.72, 0.90, 0.68), "b": Color(0.92, 1.00, 0.82)},
	# THE ONE CORAL THAT SHOULD MOVE, AND DELIBERATELY DOES NOT YET (s35). A gorgonian is a
	# flexible protein skeleton and it is the one thing on a real reef that visibly flexes in
	# a surge, so `"sway": 0.03` here is written, tested and then REMOVED — because
	# reef_sway.gdshader is `cull_disabled` (the three flora meshes are glTF doubleSided and
	# lose half of every frond without it) and coral_fan_a's material is NOT: it is a solid
	# lattice, and moving it onto this shader would silently start rasterising the back faces
	# of 268 six-thousand-triangle instances. That is a real change to a species the owner
	# says is fine, on a backend nobody can render from this seat. The two-line fix is the
	# creature_swim / creature_swim_glass pattern — a `cull_back` copy of the shader — and it
	# is the first thing to do next session if the still fans read wrong beside moving kelp.
	{"slug": "coral_fan_a", "lo": 0.95, "hi": 1.95, "space": 0.42, "tilt": [10.0, 34.0],
		"depth": 0.45, "w": 1.20, "planar": true, "tilt_planar": [40.0, 70.0],
		"a": Color(0.62, 0.56, 0.92), "b": Color(0.90, 0.80, 0.96)},
	{"slug": "coral_bubble", "lo": 0.25, "hi": 0.58, "space": 0.68, "tilt": [4.0, 20.0],
		"depth": 0.30, "w": 0.32, "a": Color(0.94, 0.74, 0.72), "b": Color(1.00, 0.94, 0.90)},
]

## THE STRUCTURAL BASE (s20). Each of these is four or five growth forms fused into ONE
## piece — branching coral out of a domed head beside a plate and a field of knobs, on a
## crust rather than a rock. That is the whole answer to why the s19 reef read as
## decoration: a real reef is a continuous calcareous crust that individual colonies grow
## OUT of, and no arrangement of separate 60 cm ornaments makes that shape. So a colony now
## starts with one or two of these at its centre, at 1.6-3.2 m, and the singles are
## scattered into and around them.
##
## They are also the most expensive pieces in the set (7,000 tris), which is exactly right:
## one of them carries a whole patch's silhouette, and it replaces coral that would
## otherwise have been placed one instance at a time.
const MASSES := [
	{"slug": "reefmass_a", "lo": 1.60, "hi": 3.00, "space": 0.42, "tilt": [4.0, 18.0],
		"depth": 0.30, "w": 1.0, "a": Color(0.88, 0.86, 0.78), "b": Color(1.00, 0.98, 0.92)},
	{"slug": "reefmass_b", "lo": 1.70, "hi": 3.20, "space": 0.42, "tilt": [4.0, 18.0],
		"depth": 0.40, "w": 1.0, "a": Color(0.94, 0.78, 0.62), "b": Color(1.00, 0.96, 0.86)},
	{"slug": "reefmass_c", "lo": 1.60, "hi": 2.90, "space": 0.44, "tilt": [4.0, 16.0],
		"depth": 0.55, "w": 1.0, "a": Color(0.78, 0.72, 0.94), "b": Color(1.00, 0.94, 0.96)},
	# The flattest of the four (0.30 of its longest axis) — this is the sheet that knits
	# two colonies together instead of standing proud between them.
	{"slug": "reefmass_d", "lo": 1.80, "hi": 3.40, "space": 0.38, "tilt": [2.0, 12.0],
		"depth": 0.60, "w": 1.0, "a": Color(0.86, 0.88, 0.68), "b": Color(1.00, 1.00, 0.88)},
]

## SPONGES (s20). Filter feeders take the same schema as the corals and are drawn from the
## same colony pool at a lower weight, so a patch is coral WITH sponges in it rather than a
## sponge stripe next to a coral stripe.
##
## `sponge_fan` (elephant ear) was generated and REJECTED on the render: two thirds of the
## model is a smooth pale trumpet foot, which is the same "reads as a plinth" failure that
## cut coral_encrust in s19 — there is no way to seat it that does not show a bare stalk
## against the concrete.
##
## `rough` exists for sponge_tube_cluster: the generator returned a glassy violet skin
## (the documented default failure mode) and the specular on it read as plastic. Forcing
## roughness up is a one-line fix that keeps an otherwise strong silhouette and colour.
const SPONGES := [
	{"slug": "sponge_barrel", "lo": 0.50, "hi": 1.25, "space": 0.60, "tilt": [6.0, 22.0],
		"depth": 0.55, "w": 0.90, "a": Color(0.90, 0.66, 0.48), "b": Color(1.00, 0.90, 0.76)},
	{"slug": "sponge_tube_cluster", "lo": 0.55, "hi": 1.35, "space": 0.52, "tilt": [8.0, 26.0],
		"depth": 0.35, "w": 1.00, "rough": 0.88,
		"a": Color(0.68, 0.62, 1.00), "b": Color(0.94, 0.86, 1.00)},
	{"slug": "sponge_rope", "lo": 0.65, "hi": 1.60, "space": 0.46, "tilt": [12.0, 40.0],
		"depth": 0.25, "w": 0.85, "a": Color(0.96, 0.72, 0.44), "b": Color(1.00, 0.92, 0.74)},
]

## BARNACLE CRUSTS (s20) — the filler, and the reason the legs stop reading as concrete
## with things stuck to it. These are placed over the WHOLE leg face (CRUST_TOP down to
## BAND_BOTTOM), not just the coral band, so the bare stripe between underwater_world's
## shallow growth and the reef proper is encrusted too. Cheapest pieces in the set and by
## far the most numerous.
##
## They lie flat, like the starfish: `tilt` is near zero, because a barnacle does not lean.
const CRUSTS := [
	# Weight and tint were both moved after looking at the first render. cluster_a is the
	# whitest AND the most expensive crust (4,000 tris against giant's 1,400 — it shatters
	# below that, see tools/decimate_reef.py), and at w 1.30 there were 181 of them: the
	# legs read as whitewash and the crust alone cost 724k triangles. Halving its weight and
	# giving the warm, cheap species the bulk fixed the colour and the budget in one move.
	# The tint is chalk-grey rather than white for the same reason — a barnacle is dead
	# calcite on concrete, not a light source.
	#
	# s35 — HALVED AGAIN, and this is where the kelp is paid for. The s34 close-out frames
	# (/tmp/s34_final/reef_mid.png, reef_deep.png) are the measurement: at 20 m the caisson
	# reads as grey concrete with PALE SCABS on it, and the scabs are this pass. It is also
	# the documented cheapest lever in KNOWN_ISSUES, and the two moves — 0.70 -> 0.28 here
	# and the count in _crust_face — pull roughly 440k triangles out of the least-liked
	# thing on the wall. The crust's actual job (fill the concrete BETWEEN colonies) is
	# unchanged; it is barnacle_giant, warm and 1,400 tris, that now does it.
	{"slug": "barnacle_cluster_a", "lo": 0.35, "hi": 0.95, "space": 0.52, "tilt": [0.0, 9.0],
		"depth": 0.35, "w": 0.28, "glow": 0.40,
		"a": Color(0.68, 0.72, 0.76), "b": Color(0.90, 0.92, 0.92)},
	{"slug": "barnacle_giant", "lo": 0.28, "hi": 0.70, "space": 0.58, "tilt": [0.0, 12.0],
		"depth": 0.45, "w": 1.45, "glow": 0.40,
		"a": Color(0.88, 0.74, 0.72), "b": Color(1.00, 0.92, 0.90)},
	# `barnacle_goose` was generated twice (the first attempt 502'd mid-poll) and REJECTED
	# both on the render and on the numbers: the generator returned a radially symmetric
	# spiky ball — 0.97/0.99/0.93 on its three axes — not a bunch of stalked shells hanging
	# off a face, and decimation turned the spines into loose shards. Two crust species is
	# enough; the third would have been a sea urchin with the wrong name.
]

## Starfish emission, as a FRACTION of the reef's GLOW (see the sweep note above).
## Owner call 2026-07-29: halved. A starfish is an animal sitting on the reef, not one of
## the bloom-lit colonies — at full reef emission the small ones read as scattered lights
## rather than as flesh, which is also what made them so conspicuous at 96 instances.
const STAR_GLOW: float = 0.5

## BIG STARFISH (s20, owner call: larger, more prominent, and DOWN THE LEGS). These are
## 0.65-1.75 m — two to three times the s19 stars — and they ride the caisson faces over
## the full leg as well as the foundation, which is where the owner actually meets one.
##
## `star_big_blue` was generated and REJECTED on the render: glassy cobalt with bent,
## tapering arms, the textbook plastic-toy failure the traps file warns about, and its side
## profile is a warped disc rather than a star lying flat. Red, spiny (7-arm) and sunflower
## (10-arm) are three clearly different silhouettes and three clearly different colours,
## which is what the set needed.
const BIG_STARS := [
	{"slug": "star_big_red", "lo": 0.70, "hi": 1.30, "w": 1.15, "glow": STAR_GLOW,
		"a": Color(1.00, 0.62, 0.52), "b": Color(1.00, 0.92, 0.82)},
	{"slug": "star_big_spiny", "lo": 0.80, "hi": 1.55, "w": 0.80, "glow": STAR_GLOW,
		"a": Color(0.74, 0.68, 1.00), "b": Color(0.98, 0.92, 1.00)},
	{"slug": "star_big_sunflower", "lo": 0.90, "hi": 1.75, "w": 0.55, "glow": STAR_GLOW,
		"a": Color(1.00, 0.72, 0.50), "b": Color(1.00, 0.94, 0.80)},
]

## WALL PLANTS — the owner asked for plants ROOTED INTO THE WALL AND ANGLED OUT (s34, and
## twice before). The reef already roots everything by raycast and leans it off the normal
## (see _grow_axis), so what was missing was not the technique but the PLANTS: every green
## thing in the water was either a kelp holdfast standing on the seabed or one of
## underwater_world's growth-band pieces sitting on the concrete. These grow OUT of the
## face, all the way down the leg.
##
## They lean further than coral does — a weed on a wall reaches for the light, a massive
## coral hugs the rock — so the tilt ranges start where the coral's planar species end.
##
## THEY ARE THE EXISTING FLORA, RE-CUT FOR BULK. The first pass pointed these straight at
## the fauna GLBs underwater_world plants on the leg shelves, and the build report said what
## the traps file has always said about placing a generated mesh in bulk: 28,844 / 29,778 /
## 30,745 triangles a piece against a reef set that runs 1,400-7,000, so 363 plants cost
## 10.7 M of a 20.4 M total on their own. Re-cut through tools/decimate_reef.py to ~8,000,
## which also bakes the reef contract this placement code assumes (+Y is growth, base at
## y = 0, XZ centred) instead of leaving three special cases in GDScript.
##
## s35 — WHAT WAS ACTUALLY WRONG WITH THEM, MEASURED BEFORE ANYTHING WAS CHANGED. The owner
## says "nothing was updated/changed with the plants at all" and the s34 report says 363 wall
## plants. Both are true. The pass runs, the code path is reachable, nothing culls it — and
## it is invisible for three reasons that are all arithmetic:
##   1. THEY ARE SPREAD OVER WATER THE PLAYER CANNOT ENTER. `y` was drawn UNIFORMLY over the
##      whole 36.4 m band, and the death line is 13 m: only (13 − 3.6) / 36.4 = 25.8% of them,
##      i.e. ~94 plants over 16 leg faces, ~6 a face, are in water you can swim in.
##   2. THEY ARE THE SMALLEST THINGS ON THE WALL. 0.30–1.05 m longest axis against reef
##      masses at 1.6–3.4 and sea fans at 0.95–1.95, on a face 6 m wide and 36 m tall.
##   3. THEY ARE THE SAME THREE MESHES THAT WERE ALREADY THERE. bloom_sea_grass and
##      bloom_anemone are both in underwater_world._leg_reef_growth's species list, at the
##      same 0.3–1.0 m, in the band directly above. Nothing new arrived to be noticed.
## So the fix is not "place more": it is depth, size and motion. `t` is now biased hard toward
## the top (see _wall_plants), the sizes below roughly double, every one of them SWAYS, and
## the count comes DOWN — these are 8,000-triangle meshes, the joint most expensive pieces in
## the whole set, and 363 of them were 23% of the reef's triangle budget spent on the thing
## nobody could see.
##
## s36 — THE ANGLE, AND THE BASE (owner: "angle plants diagonal so they can root against the
## base"). `tilt` was degrees off the FACE NORMAL, and on a vertical caisson that convention
## makes small numbers mean HORIZONTAL: 20-24 deg is a plant fired straight out of the wall.
## /tmp/s35/plants.png is the evidence — a clump of sea grass rooted on the concrete with
## every blade radiating out over open water like a bottle brush. The range then ran to 56, so
## the family spanned "flat out of the wall" to "mostly up" and nothing in it was a diagonal.
##
## `diag` replaces it and is degrees off the DERIVED diagonal: the bisector of the probed face
## normal and world up (see _diag_axis), which is exactly 45 deg out of any vertical face and
## needs no number typed per face. A species keeps its character as a BAND about that bisector
## — the blade wanders furthest, the anemone (a column with a crown) least.
##
## `root` is the seating half, and it is the half the owner actually asked about. See _add: a
## rooted species is seated with its local XZ plane IN THE WALL PLANE and only its growth axis
## leaning out, which is what a holdfast does. The old rigid tilt rotated the base plate with
## the plant, so its down-slope edge lifted off the concrete — measured off the glTF at up to
## 128 mm on a 1.8 m sea grass at 56 deg, against a recess capped at 220 mm that could not
## reach it.
const PLANTS := [
	{"slug": "bloom_sea_grass", "lo": 0.70, "hi": 1.80, "space": 0.42,
		"diag": [-14.0, 14.0], "depth": 0.25, "w": 1.20, "sway": 0.055, "root": true,
		"a": Color(0.42, 0.86, 0.58), "b": Color(0.74, 1.00, 0.80)},
	{"slug": "glow_creeper", "lo": 0.60, "hi": 1.60, "space": 0.40,
		"diag": [-12.0, 12.0], "depth": 0.55, "w": 1.00, "sway": 0.065, "root": true,
		"a": Color(0.36, 0.78, 0.72), "b": Color(0.70, 1.00, 0.94)},
	# The anemone is a column with a crown, not a blade: it bends far less than weed does and
	# its own lean is most of what reads as motion, so it takes a third of the sway — and the
	# narrowest band about the diagonal, because a column that wanders reads as a mistake.
	{"slug": "bloom_anemone", "lo": 0.35, "hi": 0.85, "space": 0.44,
		"diag": [-8.0, 8.0], "depth": 0.75, "w": 0.85, "sway": 0.022, "root": true,
		"a": Color(0.92, 0.58, 0.72), "b": Color(1.00, 0.84, 0.90)},
]

## KELP AND SEAWEED (owner s35: "add underwater plants like kelp/seaweed"). Two entries, two
## meshes, and every form in a kelp bed comes out of them.
##
## NO NEW ASSET WAS GENERATED, AND NONE WAS NEEDED. What is on disk that is a plant and is
## already decimated to the reef's budget is exactly three meshes, and two of them are the
## right shape for this: bloom_sea_grass (glTF extent 1.357 x 1.905 x 1.163) and glow_creeper
## (0.565 x 1.896 x 0.908) are both TALLER than they are wide with their base on y = 0, which
## is a strap blade and a vine. The variety comes from the instance transform instead:
## `_add` now takes a NON-UNIFORM stretch, so one mesh spans a squat 1 m bush and a 7 m
## strand off a single `form` roll (see _weed_band). One MultiMesh per species per leg still.
##
## Cheap it is not — 8,000 triangles a piece — so the count is deliberately low and the size
## deliberately large. A kelp bed's job here is SILHOUETTE in the band the player swims in;
## 100-odd strands 3–7 m tall buy that, and 400 half-metre tufts do not, at four times the
## price. `sway` is high because this is the thing the owner will actually see moving.
##
## s36 — THESE TOOK THE SAME `diag` AND `root` TREATMENT AS THE WALL PLANTS, and they are the
## worse half of the defect rather than an extension of the fix. `tilt` 12-16 deg off a
## vertical wall's NORMAL is a 7.7 m kelp strand pointing HORIZONTALLY out over open water,
## and at 4.40 m x 1.75 stretch that is the largest single object this file plants. The fan of
## pale blades shooting sideways out of the caisson in /tmp/s35/plants.png is this pass, not
## the wall-plant pass. The bands are biased toward the vertical rather than centred: kelp
## carries gas bladders and reaches for the surface, and the sway shader's `lean` then bends
## it back downstream, so a symmetric band about 45 deg would double-count the bend.
const WEEDS := [
	{"key": "kelp_blade", "slug": "bloom_sea_grass", "space": 0.30,
		"diag": [-12.0, 16.0], "depth": 0.30, "w": 1.15, "sway": 0.090, "root": true,
		"a": Color(0.24, 0.62, 0.36), "b": Color(0.56, 0.96, 0.62)},
	{"key": "kelp_whip", "slug": "glow_creeper", "space": 0.28,
		"diag": [-10.0, 20.0], "depth": 0.60, "w": 1.00, "sway": 0.115, "root": true,
		"a": Color(0.20, 0.58, 0.52), "b": Color(0.52, 0.98, 0.86)},
]
## The form roll, and what it means. ONE random number per strand drives size, height stretch
## and width stretch together, so the bed is a continuum from short-and-bushy to tall-and-thin
## instead of a random mix of the two extremes:
##   f = 0  ->  0.9 m longest axis, 0.80 y-stretch, 1.45 xz  — a squat weed clump
##   f = 1  ->  4.4 m longest axis, 1.75 y-stretch, 0.46 xz  — a 7.7 m strand
## Both meshes are y-longest, so `size` IS the drawn height before the stretch multiplies it.
const WEED_SIZE := [0.90, 4.40]
const WEED_SY := [0.80, 1.75]
const WEED_SXZ := [1.45, 0.46]
## Attempts per leg face, before the band scaling. Four is not a typo — see the triangle note
## on WEEDS. At band_scale 2.29 this is ~9 a face, ~150 attempts, and the spacing rejection
## turns roughly 30% of them down (the rate _wall_plants measured at s34: 363 of 516).
const WEEDS_PER_FACE: int = 4
## THE TOP OF THE PLANT BAND, AND IT IS A HARD LINE, NOT A TASTE. The pontoon skirt's
## underside is y -3.05 and in plan it contains all four legs, so anything rooted (or grown)
## above that is inside the slab the player walks on. -3.60 leaves margin for the tip check
## below. This is the clamp the s34 brief asked for, set from the measured geometry rather
## than from the -2.5 the brief suggested — -2.5 is the top of underwater_world's growth
## band, which is a different number that happens to be nearby.
const PLANT_TOP: float = -3.60
## How many attempts per face. The spacing rejection turns a lot of these down on a leg
## that is now nearly covered in coral, which is the intended behaviour: plants fill in
## where the reef did not take.
##
## s35: 14 -> 11. This is not a retreat from the owner's ask, it is where the triangles for
## the kelp came from. 516 attempts took 363 plants at 8,000 tris each = 2.90 M, 23% of the
## whole reef, and 74% of them were below the death line. 405 attempts take ~284, and the new
## depth bias puts ~54% of those in reach: ~153 plants a player can swim to, against ~94
## before. Fewer plants, 1.6x the plants that can be SEEN, 624k triangles for the kelp.
const PLANTS_PER_FACE: int = 11
## How the plant band is stacked. `t` is raised to this before it is lerped from PLANT_TOP to
## BAND_BOTTOM, so the distribution crowds the lit water instead of being uniform over 36 m.
## Derived from the death line rather than tasted: the player cannot pass y -13, so the
## reachable slice is (13.0 - 3.6) / 36.4 = 0.258 of the band and a uniform draw puts 25.8% of
## the plants in it. pow(u, 2.2) puts 0.258 ^ (1 / 2.2) = 54.0% there. It is also the true
## thing — weed is light-limited in a way that a coral colony is not, which is why the coral
## band's own exponent stays at the near-uniform 1.05 it was tuned to.
const PLANT_TAPER: float = 2.2
## Kelp is more light-hungry still, and a 7 m strand at y -35 is triangles in the dark.
const WEED_TAPER: float = 3.0

## HUGE CORAL STRUCTURE (owner s35: "add more huge coral structure graphics" — things that
## read as STRUCTURE at distance, a bommie, an arch, a pillar, a big brain-coral head).
##
## THE SCALE DISTRIBUTION IS THE WHOLE PROBLEM, AND IT WAS MEASURED BEFORE ANYTHING WAS ADDED.
## Longest-axis metres per species, from the tables above, with the DRAWN HEIGHT taken from
## the decimated glTF extents (assets/models/fauna/reef/*/*.glb):
##     reefmass_a..d   1.60–3.40   tallest drawn height 2.90 x 0.824 = 2.39 m
##     coral_fan_a     0.95–1.95   sponges 0.50–1.60   coral_plate 0.60–1.70
##     coral_branch_a  0.55–1.40   coral_brain 0.35–0.95   coral_bubble 0.25–0.58
##     barnacles       0.28–0.95   wall plants 0.30–1.05   big starfish 0.70–1.75
## Nothing on this reef is over 3.4 m across or 2.4 m tall, on a caisson face 6 m wide and 36 m
## deep. That is exactly why the wall photographs as a texture rather than as a place: at 20 m
## through the fog grade every piece resolves to the same size blob, so the eye reads pattern
## and stops. No number of extra 1 m pieces fixes that — only a piece with its own silhouette.
##
## BUILT FROM WHAT IS ON DISK, BY COMPOSING AND SCALING. No asset was generated. A structure
## is a handful of EXISTING reef pieces at 2–5x their scattered size, arranged in a face-local
## frame (out = the probed normal, up = world up, side = the face tangent) and seated by the
## same raycast as everything else. Members register in `_placed`, so the colony and crust
## passes that run afterwards settle AROUND a structure instead of through it.
##
## `pool` is which family the member is drawn from — "mass"/"sponge" take this leg's palette
## slice (so a structure adds no new MultiMesh to a leg), a literal slug takes that species.
## `size` is longest-axis metres, `sy`/`sxz` the non-uniform stretch, `dy`/`ds` the offset from
## the structure root in the face frame, `dout` an extra push off the wall, `tilt` degrees.
##
## READ THE TILTS BEFORE CHANGING THEM — THEY ARE OFF THE WALL NORMAL, NOT OFF VERTICAL.
## `_grow_axis` builds the growth axis as normal*cos(tilt) + up*sin(tilt), so on a VERTICAL
## caisson face a tilt of 0 grows STRAIGHT OUT, horizontally, and only a tilt near 90 grows UP.
## Everything else in this file scatters small pieces at 0-40 deg, which is right for a coral
## head bulging off concrete — but the whole point of a bommie or a pillar is that its LONG
## axis is vertical, so the members that carry the silhouette sit at 72-84 deg. The first
## draft of this table had them at 6-12 deg and would have produced a 5 m sponge sticking out
## of the caisson like a cannon: the stretch went along whatever the growth axis was, and the
## growth axis was horizontal. Caught by working the arithmetic, not by rendering it.
##
## The consequence for seating is handled in _structure rather than authored here: a piece
## standing UP the wall carries half its own girth INTO the concrete (its local XZ plane now
## contains the wall normal), so the standoff is computed from the member's girth and how
## vertical it stands. `dout` is only a small extra bias on top of that.
const STRUCTURES := [
	# BOMMIE — a coral pillar growing UP the face. Three reef masses stretched along a
	# near-vertical growth axis and stacked with rising bases, so they fuse into one column
	# ~9.4 m tall, with a branching crown and a fan and a plate off its flanks. Nothing on
	# this reef today is over 2.4 m tall; this is the piece that changes what the wall is.
	{"name": "bommie", "members": [
		{"pool": "mass", "size": 3.40, "sy": 1.45, "sxz": 1.00, "dy": 0.0, "ds": 0.0, "dout": 0.10, "tilt": 74.0},
		{"pool": "mass", "size": 3.05, "sy": 1.55, "sxz": 0.95, "dy": 2.6, "ds": 0.5, "dout": 0.20, "tilt": 80.0},
		{"pool": "mass", "size": 2.40, "sy": 1.45, "sxz": 0.90, "dy": 5.0, "ds": -0.4, "dout": 0.10, "tilt": 76.0},
		{"pool": "coral_branch_a", "size": 1.90, "sy": 1.25, "sxz": 1.00, "dy": 6.6, "ds": 0.7, "dout": 0.0, "tilt": 55.0},
		{"pool": "coral_fan_a", "size": 2.60, "sy": 1.00, "sxz": 1.00, "dy": 3.9, "ds": -1.5, "dout": 0.25, "tilt": 52.0},
		{"pool": "coral_plate", "size": 2.40, "sy": 1.00, "sxz": 1.00, "dy": 1.5, "ds": 1.4, "dout": 0.0, "tilt": 40.0},
	]},
	# BRAIN HEAD — the cheapest structure in the file and the best value in it: ONE
	# coral_brain at 4.8 m is 5,000 triangles, 4.6 m across and 2.8 m proud of a 6 m face,
	# i.e. a boulder coral the size of a car for the price of one scattered colony member.
	# Low tilt is CORRECT here — a massive Porites really does grow out of a wall, not up it.
	{"name": "brain_head", "members": [
		{"pool": "coral_brain", "size": 4.80, "sy": 0.85, "sxz": 1.00, "dy": 0.0, "ds": 0.0, "dout": 0.0, "tilt": 12.0},
		{"pool": "coral_bubble", "size": 1.30, "sy": 1.00, "sxz": 1.00, "dy": 2.2, "ds": 1.6, "dout": 0.0, "tilt": 18.0},
		{"pool": "coral_branch_b", "size": 1.70, "sy": 1.20, "sxz": 1.00, "dy": 0.5, "ds": -2.0, "dout": 0.0, "tilt": 40.0},
	]},
	# TERRACE — three table corals cantilevered off the wall at rising heights. coral_plate is
	# a disc 0.30 of its longest axis thick, and its growth axis is the disc NORMAL, so a tilt
	# near 80 lays the slab out HORIZONTALLY: a 4.6 m one reaches 2.3 m out over open water and
	# throws a real shadow line under it. The closest thing this asset set has to an arch.
	{"name": "terrace", "members": [
		{"pool": "coral_plate", "size": 4.60, "sy": 1.00, "sxz": 1.00, "dy": 0.0, "ds": 0.0, "dout": 0.0, "tilt": 72.0},
		{"pool": "coral_plate", "size": 3.90, "sy": 1.00, "sxz": 1.00, "dy": 2.1, "ds": 1.1, "dout": 0.0, "tilt": 80.0},
		{"pool": "coral_plate", "size": 3.20, "sy": 1.00, "sxz": 1.00, "dy": 4.0, "ds": -0.9, "dout": 0.0, "tilt": 66.0},
	]},
	# FAN WALL — a gorgonian thicket at 2.7-3.6 m against a scattered fan's 0.95-1.95. The
	# `planar` flag turns its blade to the flow, so these are sails seen face-on rather than
	# the purple scratches the s19 render rejected.
	{"name": "fan_wall", "members": [
		{"pool": "coral_fan_a", "size": 3.60, "sy": 1.00, "sxz": 1.00, "dy": 0.0, "ds": 0.0, "dout": 0.25, "tilt": 58.0},
		{"pool": "coral_fan_a", "size": 3.10, "sy": 1.00, "sxz": 1.00, "dy": 1.6, "ds": 1.7, "dout": 0.25, "tilt": 64.0},
		{"pool": "coral_fan_a", "size": 2.70, "sy": 1.00, "sxz": 1.00, "dy": 2.9, "ds": -1.4, "dout": 0.25, "tilt": 50.0},
	]},
	# PILLAR — barrel sponges stretched into chimneys. sponge_barrel is y-longest, so at 2.6 m
	# and sy 1.70 it is a 4.4 m tube 1.8 m across; three of them staggered make a column with a
	# broken top, which is the silhouette a real sponge pillar has. ~7 m tall for 9,000 tris.
	{"name": "pillar", "members": [
		{"pool": "sponge", "size": 2.60, "sy": 1.70, "sxz": 0.85, "dy": 0.0, "ds": 0.0, "dout": 0.10, "tilt": 80.0},
		{"pool": "sponge", "size": 2.20, "sy": 1.85, "sxz": 0.80, "dy": 1.5, "ds": 1.2, "dout": 0.15, "tilt": 76.0},
		{"pool": "sponge", "size": 1.80, "sy": 1.60, "sxz": 0.80, "dy": 3.4, "ds": -0.8, "dout": 0.10, "tilt": 84.0},
	]},
]
## One structure per face, so four a leg and sixteen in the ocean, and the kind ROTATES with
## the leg the same way _palette rotates the species — every leg gets a different set, and no
## two structures on one leg are the same shape.
##
## The depth fractions are of the CRUST_TOP..BAND_BOTTOM span and are deliberately top-heavy:
## the player cannot pass the 13 m death line, so the shallowest two are things you swim up
## to and the deep two are things you look DOWN at. Each one is then clamped so its own grown
## top stays under PLANT_TOP — measured from the loaded meshes, not authored (see _structure).
const STRUCTURE_DEPTHS: Array[float] = [0.14, 0.31, 0.52, 0.76]

## WHAT COUNTS AS A STALK, and the number is measured off the meshes rather than tasted.
## Drawn height along the growth axis over drawn girth across it, taken over every member of
## every structure above on every leg, from the decimated glTF extents:
##     terrace 0.30 · fan_wall 0.68 · brain_head <=0.85 · bommie <=1.33
##     PILLAR  2.30 .. 2.89
## The set has an EMPTY BAND 0.97 wide between the pillar and everything else, and this sits
## in it. That is what tells a coral boulder stretched a bit tall (a bommie course at 1.33)
## from a mast (a rope sponge at 2.89) without naming either structure — so a later session
## that adds a stretched member gets judged on its shape rather than on its table entry.
const STALK_ASPECT: float = 1.60

## How many big starfish ride each caisson leg, and how many extra go on the foundation.
## These are ATTEMPTS — the spacing rejection turns some of them down, and on a leg that is
## now nearly covered in coral it turns down a lot. Counted off the build report: 11 a leg
## produced 41 big stars in the whole ocean, which is not the "starfish all down the legs"
## the brief asked for, so the attempt count went up and the claim radius (below) came down.
const BIG_STARS_PER_LEG: int = 18
const BIG_STARS_FOUNDATION: int = 26

## The top of everything this file places on a leg face. The coral band still starts below
## the MEASURED vegetation floor (see _vegetation_floor), but the crust and the starfish run
## the whole leg from just under the pontoon skirt, which is what closes the bare stripe
## between underwater_world's shallow growth and the reef.
const CRUST_TOP: float = SKIRT_BOTTOM - 0.35

const STARS := [
	{"slug": "star_small", "lo": 0.30, "hi": 0.55, "w": 1.55, "glow": STAR_GLOW,
		"a": Color(0.90, 0.62, 0.36), "b": Color(1.00, 0.94, 0.80)},
	{"slug": "star_mid", "lo": 0.42, "hi": 0.72, "w": 0.62, "glow": STAR_GLOW,
		"a": Color(0.70, 0.62, 1.00), "b": Color(1.00, 0.86, 0.94)},
]
## The seven-arm giant. Placed by hand-picked count, not by weight — it is meant to be
## a find, so there are exactly this many in the whole ocean.
const STAR_HUGE := {"slug": "star_huge", "lo": 0.95, "hi": 1.25, "glow": STAR_GLOW,
	"a": Color(0.66, 0.70, 1.00), "b": Color(0.92, 0.90, 1.00)}
const HUGE_COUNT: int = 3

## Deepest a piece may be sunk into the concrete, metres. See _add.
const RECESS_MAX: float = 0.22

## BLOOM EMISSION (owner call, s20: "turn up bloom emission to brighten the coral").
##
## Measured rather than tasted. main.gd runs the world environment with `glow_enabled` and
## `glow_hdr_threshold = 0.8`, so a surface only BLOOMS once its lit pixel clears 0.8 — and
## the s19 value of 0.15, keyed off the albedo map, put the emission term at roughly 0.1 of
## a mid-tone. That is nowhere near the threshold: the coral was brighter than unlit, and
## contributed nothing whatever to the glow buffer. There was never any bloom on this reef.
##
## Two changes get it there. The energy goes to GLOW, which pushes the brighter parts of a
## coral's own albedo over 0.8 and lets the post-process take them; and the emission COLOUR
## goes from the old cyan-white to near-white, so raising it brightens each piece in ITS OWN
## colour instead of washing the whole reef toward teal. (The s19 note that 0.24 "washed its
## colour out" was the tint doing that, not the energy — an emission of 0.78/0.96/0.93 pulls
## everything green-blue the harder you drive it.)
##
## THE VALUE IS THE RESULT OF A SWEEP, NOT A GUESS. `tests/ReefShot.tscn --glow=a,b,c` exists
## for this: it re-exposes the same frame at each value off one world build. The first attempt
## at 1.35 rendered the entire reef as featureless WHITE — emission is added after the
## instance tint, so past ~0.7 it swamps every colour the pieces have. Read off the ladder
## 0.10 / 0.20 / 0.30 / 0.45 / 0.65 / 0.90 at the SE leg, day and night:
##   0.10-0.20  a dark texture on dark concrete. This is roughly where s19 shipped.
##   0.30       reads, but flat — no bloom, colour muted.
##   0.50       bright, tips clear the glow threshold and actually bloom, hue intact.
##   0.65+      the massive species start fusing into one cream smear.
##   0.90       no colour left.
## 0.50 is 3.3x s19 and the top of the range that keeps the reef's own colours.
const GLOW: float = 0.50
## Not pure white: a faint cool cast keeps the reef reading as bioluminescence in teal water
## rather than as a lit shop display, without bending the piece's hue the way the old value
## did. Species that are chalk rather than living tissue (the barnacles) scale this down
## with their own `glow` factor.
const GLOW_TINT := Color(0.94, 1.00, 0.99)

var _rng := RandomNumberGenerator.new()
var _space: PhysicsDirectSpaceState3D
## slug -> {"mesh": Mesh, "mat": Material, "xf": Array[Transform3D], "col": Array[Color]}
var _batches: Dictionary = {}
var _placed: Array = []          ## [pos, radius] rejection list, for spacing
var _plant_pool: Array = []
## How many wall plants actually took, for the build report — attempts minus every kind of
## rejection, which is the only number that says whether the pass did anything.
var _plants: int = 0
## ...and how many of those a player can actually reach. s34 reported 363 plants and the
## owner reported no change; both were right, because three quarters of them were below the
## 13 m death line. A count that cannot distinguish those two states is not a measurement, so
## the report now carries the reachable one as well.
var _plants_reachable: int = 0
var _weeds: int = 0
var _weeds_reachable: int = 0
var _structures_built: int = 0
## THE BASE-CONTACT MEASUREMENT (s36) — see _check_root for what each of these is and why the
## pair of them is a PROOF that no rooted plant can have daylight under it, rather than a
## sample that happened to pass.
var _root_n: int = 0
var _root_fail: int = 0
var _root_flush_max: float = 0.0
var _root_bite_min: float = 1.0e9
var _root_bite_max: float = -1.0e9
var _root_det_min: float = 1.0e9
## Where the WALL CUTS THE STEM, as a fraction of the plant's own height, and what the sway
## shader is therefore doing at the point the plant meets the concrete. See _add.
var _root_cut_max: float = 0.0
var _root_sway_max: float = 0.0
## The s36 shallow stalk clamp — see STALK_ASPECT and _member_plan.
var _stalks_clamped: int = 0
var _stalks_dropped: int = 0
## The dive limit, from seabed.gd's own note ("the 13 m death line keeps it out of reach").
## Used only for reporting — nothing is placed or withheld because of it.
const DIVE_LIMIT: float = -13.0
var _band_top: float = 0.0
## Where the coral ACTUALLY went: one {pos, n} per colony that seated at least one piece,
## in world space. reef_fish.gd anchors its shoals to these, so a reef fish cannot end up
## hovering over a patch of bare concrete the spacing rejection threw away.
var colony_seats: Array = []

func _ready() -> void:
	_rng.seed = 90210
	# Physics is not queryable until a physics frame has run, and underwater_world's
	# kelp is built in its own _ready — so both of the things this measures need the
	# world to have ticked at least once. Building on frame 0 measured an empty space
	# state and seated the entire reef on the fallback.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_space = get_world_3d().direct_space_state
	_band_top = _vegetation_floor() - BAND_GAP
	for leg in LEGS:
		_placed.clear()
		_grow_leg(leg)
		_flush("Leg_%d_%d" % [int(leg.x), int(leg.y)])
	_placed.clear()
	_dress_foundation()
	_flush("Foundation")
	_grow_snails()
	_report()
	add_child(REEF_FISH.new(colony_seats, _band_top, BAND_BOTTOM, KEEP_OUT))
	add_child(MUSSELS.new(colony_seats, _band_top, BAND_BOTTOM, KEEP_OUT))

## Numbers, not impressions — this is what the session reports and what ReefProbe
## re-derives independently from the built tree.
func _report() -> void:
	var inst: int = 0
	var tris: int = 0
	var calls: int = 0
	var per_slug: Dictionary = {}
	var per_group: Dictionary = {}
	for node in find_children("LegReef_*", "MultiMeshInstance3D", false, false):
		var mmi: MultiMeshInstance3D = node
		var n: int = mmi.multimesh.instance_count
		var each: int = int(mmi.multimesh.mesh.get_faces().size() / 3.0)
		inst += n
		calls += 1
		tris += n * each
		var slug: String = String(mmi.name).split("_")[-1]
		for s in _batches.keys():
			if String(mmi.name).ends_with(String(s)):
				slug = String(s)
		per_slug[slug] = [int(per_slug.get(slug, [0, each])[0]) + n, each]
		var grp: String = String(mmi.name).trim_prefix("LegReef_").split("_" + slug)[0]
		per_group[grp] = int(per_group.get(grp, 0)) + n * each
	print("[leg_reef] band y %.2f .. %.2f (scale %.2fx) · %d instances · %d MultiMesh draws · %d tris"
		% [_band_top, BAND_BOTTOM, band_scale(_band_top), inst, calls, tris])
	# WITH the reachable split. "363 plants" was a true number that hid the whole defect.
	print("[leg_reef]   wall plants %d (%d above the %.0f m dive limit, %.0f%%)"
		% [_plants, _plants_reachable, -DIVE_LIMIT,
			100.0 * float(_plants_reachable) / maxf(1.0, float(_plants))])
	print("[leg_reef]   kelp/seaweed %d (%d above the dive limit, %.0f%%) · %d big structures"
		% [_weeds, _weeds_reachable,
			100.0 * float(_weeds_reachable) / maxf(1.0, float(_weeds)), _structures_built])
	# BASE CONTACT — the s36 owner item, as a number rather than a claim. This is measured off
	# the real holdfast vertices of each placed instance, not off the scalar that seated it.
	if _root_n > 0:
		print("[leg_reef]   base contact: %d rooted plants · cut edge %.1f..%.1f mm INSIDE the concrete · base plate off the wall plane by at most %.4f mm · min det %+.5f · %d failed"
			% [_root_n, _root_bite_min * 1000.0, _root_bite_max * 1000.0,
				_root_flush_max * 1000.0, _root_det_min, _root_fail])
		if _root_fail > 0:
			push_warning("[leg_reef] %d rooted plants are not flush on the concrete (worst base-plate error %.2f mm)"
				% [_root_fail, _root_flush_max * 1000.0])
		# ...and what that means for the sway shader, whose displacement is anchored at the
		# mesh's local y = 0 and grows as h^2. Because a rooted instance's local XZ plane IS
		# the wall plane, the concrete cuts every one of them at ONE local height, so this is
		# the whole answer to "does the anchor land at the holdfast".
		print("[leg_reef]   sway anchor: the concrete cuts a rooted plant at most %.1f%% up its own stem, where the shader moves it %.2f mm"
			% [_root_cut_max * 100.0, _root_sway_max * 1000.0])
	if _stalks_clamped > 0 or _stalks_dropped > 0:
		print("[leg_reef]   shallow stalk clamp: %d structure members unstretched above y %.1f, %d dropped to the scatter"
			% [_stalks_clamped, DIVE_LIMIT, _stalks_dropped])
	for slug in per_slug.keys():
		print("[leg_reef]   %-16s %4d x %5d tris = %8d"
			% [slug, per_slug[slug][0], per_slug[slug][1],
				per_slug[slug][0] * per_slug[slug][1]])
	for grp in per_group.keys():
		print("[leg_reef]   group %-16s %8d tris (its own MultiMesh AABB, culled as one)"
			% [grp, per_group[grp]])
	var lo: float = 1.0e9
	var hi: float = -1.0e9
	for c in _climbers:
		var y: float = (c["s"] as Node3D).global_position.y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	if not _climbers.is_empty():
		print("[leg_reef] snails: %d climbing the caissons, seated y %.2f .. %.2f (%d refused — no collider)"
			% [_climbers.size(), lo, hi, _snails_refused])
	print("[leg_reef] seating rays %d, of which %d fell back to the sonar-measured face"
		% [_rays, _fallbacks])

# ------------------------------------------------------------ measurement

## The lowest point the existing VEGETATION reaches on the legs, measured off the live
## tree so the reef starts below whatever is actually there rather than below where
## underwater_world's source says its kelp should be.
##
## WHAT COUNTS AS VEGETATION, and why this is not just "everything nearby".
## The first version of this walked every drawable underwater_world had built within
## 9 m of a footing and took the lowest. That measured -20.38 and collapsed the whole
## reef into a 1 m band — because the deepest things near a leg are not plants. They
## are the 15 m CYLINDER CONES of the floodlights bolted under the pontoons, the 17 m
## god-ray QUADS, and whatever FISH happened to be swimming past when the walk ran.
## A moving animal must never be allowed to set a level-design constant.
##
## So: vegetation is the kelp stand, identified by the `sway` meta that _kelp_forest
## puts on every strand it plants. The generated fronds and the leg growth are seated
## on the same holdfast ring by BloomFauna.ground_model, so the strands are the deepest
## of the three and measuring them measures the stand.
##
## The result is then held inside a sanity envelope. If the measurement ever lands
## outside it, something has changed shape and this should be looked at rather than
## quietly obeyed — so it warns and uses the authored fallback instead of silently
## building a one-metre reef again.
const VEG_FLOOR_MIN: float = -19.0
const VEG_FLOOR_MAX: float = -6.0

func _vegetation_floor() -> float:
	var uw: Node = self
	while uw != null and (uw.get_script() == null
			or not String(uw.get_script().resource_path).ends_with("underwater_world.gd")):
		uw = uw.get_parent()
	if uw == null:
		return BAND_TOP_FALLBACK + BAND_GAP
	var low: float = 1.0e9
	var strands: int = 0
	for node in uw.get_children():
		if not (node is Node3D) or not node.has_meta("sway"):
			continue
		strands += 1
		for child in (node as Node3D).find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = child
			if mi.mesh == null:
				continue
			low = minf(low, (mi.global_transform * mi.get_aabb()).position.y)
	if strands == 0 or low > 1.0e8:
		push_warning("[leg_reef] no kelp strands found — using the authored band top")
		return BAND_TOP_FALLBACK + BAND_GAP
	if low < VEG_FLOOR_MIN or low > VEG_FLOOR_MAX:
		push_warning("[leg_reef] kelp floor measured %.2f, outside [%.1f, %.1f] — using the authored band top"
			% [low, VEG_FLOOR_MIN, VEG_FLOOR_MAX])
		return BAND_TOP_FALLBACK + BAND_GAP
	print("[leg_reef] kelp stand: %d strands, floor y %.2f" % [strands, low])
	return low

## Fire a ray at a surface from a point known to be in open water and return the exact
## hit point and normal.
##
## FALLBACK, and why it is not "guessing a Y". The rig's colliders do not necessarily
## run the full depth of the casting — seabed.gd states outright that nothing below the
## death line carries collision — so a raycast at y -25 can legitimately find nothing
## even though 25 m of concrete is drawn there. When that happens this falls back to the
## face the SONAR SCAN measured (every caisson face exactly 3.0 m from its centre line,
## checked at eight depths), which is a measurement of the real geometry, not an
## authored constant. Every fallback is counted and reported so the ratio is visible
## rather than silent.
var _rays: int = 0
var _fallbacks: int = 0

func _probe(target: Vector3, normal: Vector3, from_out: float = 1.8) -> Dictionary:
	_rays += 1
	var q := PhysicsRayQueryParameters3D.create(target + normal * from_out,
		target - normal * 0.6)
	q.collision_mask = 1
	var hit: Dictionary = _space.intersect_ray(q)
	if not hit.is_empty():
		return hit
	_fallbacks += 1
	return {"position": target, "normal": normal, "measured": false}

func _blocked(p: Vector3) -> bool:
	for k in KEEP_OUT:
		if p.distance_to(k["c"]) < float(k["r"]):
			return true
	return false

# ------------------------------------------------------------ the legs

## How exposed a face is: half its weight from standing outboard of the rig (the
## inboard faces sit in the structure's wake), half from facing into the set.
func _exposure(leg: Vector2, n: Vector3) -> float:
	var outboard := Vector3(leg.x, 0.0, leg.y).normalized()
	var out_dot: float = maxf(0.0, n.dot(outboard))
	var up_dot: float = maxf(0.0, n.dot(-CURRENT))
	# The floor used to be 0.35, which left the two sheltered faces of every leg bare
	# concrete — the reef read as something that had been painted onto one side rather
	# than grown. A wake is a weaker settlement, not a sterile one.
	return 0.55 + 0.28 * out_dot + 0.17 * up_dot

## THE PER-LEG PALETTE, and why the whole species list is not on every leg.
##
## Each family is now four species deep, and one MultiMesh per species PER LEG is what buys
## the frustum culling — so putting every family member on every leg would take the leg's
## draw count from 6 to 21 for a variety nobody can see (you cannot look at two legs' worth
## of detail at once anyway). Instead each leg gets a SLICE of each family, rotated by leg
## index, which costs a third of the draws and has the side effect of making the four legs
## genuinely different communities: the NE leg is a purple-and-gold reef, the SW an
## orange-and-rust one.
func _palette(pool: Array, leg_i: int, n: int) -> Array:
	var out: Array = []
	for k in range(mini(n, pool.size())):
		out.append(pool[(leg_i * n + k) % pool.size()])
	return out

## Weighted pick from any species table. `depth_t` >= 0 biases toward the species whose
## preferred depth is nearest; -1 ignores depth (used to choose a colony's dominant).
func _pick(pool: Array, depth_t: float) -> Dictionary:
	if pool.is_empty():
		return {}
	var total: float = 0.0
	var w: Array[float] = []
	for sp in pool:
		var weight: float = float(sp["w"])
		if depth_t >= 0.0 and sp.has("depth"):
			# a species' weight peaks at its preferred depth and falls off either side
			weight *= 0.35 + 0.65 * (1.0 - absf(depth_t - float(sp["depth"])))
		w.append(weight)
		total += weight
	var roll: float = _rng.randf() * total
	for i in range(pool.size()):
		roll -= w[i]
		if roll <= 0.0:
			return pool[i]
	return pool[0]

func _pick_coral(depth_t: float) -> Dictionary:
	return _pick(CORALS, depth_t)

## This leg's slice of each family, set once per leg by _grow_leg and read by the passes.
var _mass_pool: Array = []
var _sponge_pool: Array = []
var _crust_pool: Array = []
var _bigstar_pool: Array = []

func _grow_leg(leg: Vector2) -> void:
	var leg_i: int = maxi(0, LEGS.find(leg))
	_mass_pool = _palette(MASSES, leg_i, 2)
	_sponge_pool = _palette(SPONGES, leg_i, 2)
	_crust_pool = _palette(CRUSTS, leg_i, 2)
	# ALL THREE, not a two-of-three slice. The plant pass is the sparsest on the wall
	# (11 attempts a face against the crust's 20 and a colony's 13 members), so slicing it
	# meant a whole leg could have exactly two kinds of green on it. Three MultiMeshes a leg
	# instead of two is +4 draws in the game for the family the owner is asking about.
	_plant_pool = _palette(PLANTS, leg_i, 3)
	_bigstar_pool = _palette(BIG_STARS, leg_i, 2)
	# STRUCTURES FIRST, so their members are in `_placed` before anything scatters and the
	# colonies settle around them — the same reason a colony seats its reef mass first.
	_structures(leg, leg_i)
	for n in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var ex: float = _exposure(leg, n)
		# Colony COUNT is what makes a reef read as patchy, so the exposure difference is
		# spent here rather than on making every face denser. s19 ran 3..9; s20 runs 5..12,
		# because with a reef mass anchoring each one the patches now overlap and knit
		# instead of sitting as separate islands on bare concrete.
		# Scaled with the band's height (BAND_SCALE) so extending it downward adds coral
		# instead of spreading the same coral thinner.
		var patches: int = int(round(lerpf(5.0, 12.0, ex) * band_scale(_band_top)))
		for c in range(patches):
			_colony(leg, n, ex)
		# and the crust BETWEEN the patches, over the whole leg rather than the coral band
		_crust_face(leg, n, ex)
		_wall_plants(leg, n, ex)
		_weed_band(leg, n, ex)
	_stars_down_leg(leg)

## One patch. Reefs grow out from a settled larva, so a colony is a dominant species
## with one accent in it, clustered on a centre, not a random draw per piece.
func _colony(leg: Vector2, n: Vector3, ex: float) -> void:
	var dom: Dictionary = _pick_coral(-1.0)
	# Colonies crowd the top of the band: light, food and the depth a player reaches.
	# s34: the exponent eased from 1.15 toward 1.0 when the band went from 9 m to 27 m. At
	# 1.15 over a band three times taller, the same "crowd the top" bias puts almost nothing
	# below -30 and the expansion would have been a comment rather than a reef; 1.05 keeps
	# the top denser than the bottom, which is the real behaviour, while actually reaching
	# the new depth.
	var t: float = pow(_rng.randf(), 1.05)
	var cy: float = lerpf(_band_top, BAND_BOTTOM, t)
	var ca: float = _rng.randf_range(-2.4, 2.4)
	var depth_t: float = clampf((cy - _band_top) / (BAND_BOTTOM - _band_top), 0.0, 1.0)
	var acc: Dictionary = _pick_coral(depth_t)
	var sponge: Dictionary = _pick(_sponge_pool, depth_t)
	var spread: float = _rng.randf_range(0.65, 2.05)
	var seated: int = _placed.size()
	# THE ANCHOR, placed FIRST so it wins the spacing rejection against its own colony and
	# the singles settle around it rather than the other way round. Most patches get one;
	# some get two overlapping, which is what makes a run of them read as continuous crust.
	if not _mass_pool.is_empty() and _rng.randf() < 0.82:
		for k in range(1 if _rng.randf() < 0.6 else 2):
			var mass: Dictionary = _pick(_mass_pool, depth_t)
			_seat_on_face(leg, n, ca + _rng.randf_range(-0.55, 0.55),
				cy + _rng.randf_range(-0.4, 0.4), mass)
	var members: int = int(round(lerpf(6.0, 15.0, ex) * _rng.randf_range(0.7, 1.3)))
	for m in range(members):
		var sp: Dictionary = dom if _rng.randf() < 0.58 else acc
		# A fifth of the members are sponges, so a patch is a MIXED community. Drawn from
		# this leg's sponge slice, not the whole family — see _palette.
		if not sponge.is_empty() and _rng.randf() < 0.22:
			sp = sponge
		# denser toward the colony centre, and elongated along the face rather than
		# circular — growth spreads sideways on a wall far more than it climbs
		var r: float = spread * pow(_rng.randf(), 0.65)
		var a: float = _rng.randf_range(0.0, TAU)
		var along: float = ca + cos(a) * r * 1.35
		var depth: float = cy + sin(a) * r * 0.8
		if depth > _band_top or depth < BAND_BOTTOM:
			continue
		if absf(along) > 2.55:      # stay off the caisson's corners
			continue
		_seat_on_face(leg, n, along, depth, sp)
	# Record the patch for the life that lives on it. Only if something actually grew here:
	# _placed gains one entry per accepted piece (and, during _grow_leg, only from coral), so
	# a colony the depth thinning or the spacing rejected outright is bare wall and must not
	# become somebody's address.
	if _placed.size() > seated:
		colony_seats.append({"pos": Vector3(leg.x, cy, leg.y) + n * LEG_HALF
			+ Vector3(n.z, 0.0, -n.x) * ca, "n": n})

## PLANTS ROOTED INTO THE WALL AND ANGLED OUT (owner, s34).
##
## Same raycast seat as everything else on these faces — probe the concrete, take the hit
## NORMAL as the base of the growth axis, lean it toward world up projected into the face
## plane — but over a taller band than the coral, because weed grows where coral will not:
## from just under the pontoon all the way down to the bottom of the reef.
##
## TWO CLAMPS, BOTH FROM MEASURED GEOMETRY RATHER THAN TASTE:
##   * the ROOT stays below PLANT_TOP (-3.60), because the pontoon underside is -3.05 and
##     in plan that slab contains all four legs;
##   * and the grown TIP is checked too, not just the root. A plant leaning 56 deg off a
##     vertical wall carries its tip up as well as out, so a legal root can still put
##     foliage inside the slab. The s34 brief called this out for the new plants — and the
##     EXISTING kelp stand turned out to be doing it already (see KELP_TIP_CEILING).
##
## s35 — THE DEPTH DRAW, AND WHY THE TIP CLAMP MOVED FROM A REJECT TO A CEILING.
## `y` used to be a flat `randf_range(BAND_BOTTOM, PLANT_TOP)`: 74% of the plants below the
## 13 m death line, in water the player cannot enter (see PLANT_TAPER for the arithmetic).
## It is now drawn from a tapered distribution over the same band.
## That change alone breaks the old tip REJECT, though, and in the worst possible way: the
## clamp threw away any plant whose grown tip cleared PLANT_TOP, which is exactly the tall
## ones at the top of the band — so biasing toward the top would have systematically deleted
## the big plants from the shallow water it was moving them into. The tip is now what sets
## the CEILING of the y draw, so the same plant is seated legally a little deeper instead of
## being discarded. Same guarantee, no bias, no wasted attempts.
func _wall_plants(leg: Vector2, n: Vector3, ex: float) -> void:
	if _plant_pool.is_empty():
		return
	var tangent := Vector3(n.z, 0.0, -n.x)
	var count: int = int(round(float(PLANTS_PER_FACE) * lerpf(0.7, 1.15, ex)
		* band_scale(_band_top)))
	for i in range(count):
		var t: float = pow(_rng.randf(), PLANT_TAPER)
		var sp: Dictionary = _pick(_plant_pool, t)
		var size: float = _rng.randf_range(float(sp["lo"]), float(sp["hi"]))
		var band: Array = sp["diag"]
		# THE LEAN IS DERIVED, NOT TYPED (s36). `_diag_axis` builds the bisector of this face
		# and world up and wanders `band` degrees about it; the species table no longer carries
		# an angle measured off the normal, which is the convention that let 20 deg mean
		# "horizontal" and produced the bottle-brush plants in the s35 frames.
		var off: float = deg_to_rad(_rng.randf_range(band[0], band[1]))
		var grow_n: Vector3 = _diag_axis(n, off)
		# The ceiling this plant may root at: the pontoon clamp, minus how far its own grown
		# tip rides UP the wall — measured off the mesh's radius-by-height profile rather than
		# from the growth axis alone, because a ROOTED plant's cross sections lie in the wall
		# plane and half its width is therefore also half its reach upward (see _tip_rise).
		var rise: float = _tip_rise(sp, size, grow_n.y, Vector3.ONE)
		var top: float = PLANT_TOP - rise
		if top <= BAND_BOTTOM:
			continue
		var y: float = lerpf(top, BAND_BOTTOM, t)
		var target := Vector3(leg.x, y, leg.y) + n * LEG_HALF \
			+ tangent * _rng.randf_range(-2.6, 2.6)
		var hit: Dictionary = _probe(target, n)
		if hit.is_empty():
			continue
		var surface: Vector3 = hit["position"]
		if _blocked(surface):
			continue
		# The face has to BE a face. An axis-aligned caisson normal dots its own axis at
		# 1.000, so anything softer than this is a fauna touch sphere or a passing prop that
		# the ray found instead of the concrete — the s21 mussel-bed trap, where three
		# patches seated on a snail and reported up-axes of (0.32, 0.16, -0.93).
		if absf((hit["normal"] as Vector3).dot(n)) < 0.985:
			continue
		if not _claim(surface, size * float(sp["space"])):
			continue
		# Rebuilt off the HIT normal rather than the face this loop aimed at: the 0.985 dot
		# check above only bounds them to ~10 deg of each other, and the plane the plant is
		# actually seated on is the one the shear has to lie in.
		var grow: Vector3 = _diag_axis(hit["normal"], off)
		# Belt and braces: the ray decides the seat, so the surface it returns can be a few
		# centimetres off the target it was aimed at. Cheap to re-check what was just derived.
		if surface.y + _tip_rise(sp, size, grow.y, Vector3.ONE) > PLANT_TOP:
			continue
		_add(sp, surface, hit["normal"], grow, size)
		_plants += 1
		if surface.y > DIVE_LIMIT:
			_plants_reachable += 1

## THE KELP BED (owner s35: "add underwater plants like kelp/seaweed").
##
## Same probed seat and the same two clamps as _wall_plants — this is deliberately not a new
## placement technique, because the technique was never what was missing. What is new is the
## FORM: one roll picks a strand's size and its non-uniform stretch together, so a single
## MultiMesh carries everything from a 0.9 m squat clump to a 7.7 m strand (see WEED_SIZE).
##
## It stands on the caisson faces rather than on the mud, and that is measured, not a
## preference: seabed.gd's floor is y -92 with underwater_fx's abyss ramp at -42, so anything
## planted on the bottom is drawn in black water 50 m below the deepest coral. The legs are
## where a kelp bed can both exist and be seen.
func _weed_band(leg: Vector2, n: Vector3, ex: float) -> void:
	var tangent := Vector3(n.z, 0.0, -n.x)
	var count: int = int(round(float(WEEDS_PER_FACE) * lerpf(0.7, 1.15, ex)
		* band_scale(_band_top)))
	for i in range(count):
		var t: float = pow(_rng.randf(), WEED_TAPER)
		var sp: Dictionary = _pick(WEEDS, t)
		if sp.is_empty():
			return
		# ONE form roll drives all three: tall strands are thin, short ones are bushy, and
		# nothing in between is a stretched copy of something else in the bed.
		var f: float = _rng.randf()
		var size: float = lerpf(WEED_SIZE[0], WEED_SIZE[1], f)
		var stretch := Vector3(lerpf(WEED_SXZ[0], WEED_SXZ[1], f),
			lerpf(WEED_SY[0], WEED_SY[1], f), lerpf(WEED_SXZ[0], WEED_SXZ[1], f))
		var band: Array = sp["diag"]
		var off: float = deg_to_rad(_rng.randf_range(band[0], band[1]))
		var grow_n: Vector3 = _diag_axis(n, off)
		# Both weed meshes are y-longest (bloom_sea_grass 1.905, glow_creeper 1.896 against
		# xz under 1.4), so hnorm is ~1.0 and `size` is very nearly the drawn height — but the
		# whole shape is READ rather than assumed, because a re-cut that changed the aspect
		# would otherwise put kelp tips through the pontoon without anything noticing.
		var top: float = PLANT_TOP - _tip_rise(sp, size, grow_n.y, stretch)
		if top <= BAND_BOTTOM:
			continue
		var y: float = lerpf(top, BAND_BOTTOM, t)
		var target := Vector3(leg.x, y, leg.y) + n * LEG_HALF \
			+ tangent * _rng.randf_range(-2.5, 2.5)
		var hit: Dictionary = _probe(target, n)
		if hit.is_empty():
			continue
		var surface: Vector3 = hit["position"]
		if _blocked(surface):
			continue
		if absf((hit["normal"] as Vector3).dot(n)) < 0.985:
			continue
		# A kelp strand claims by its FOOTPRINT, not by its height — a 7 m plant is a holdfast
		# the size of a fist. Claiming on `size` would have let one strand clear a 2 m circle
		# of wall and the bed would have come out as a dozen lonely poles.
		if not _claim(surface, size * stretch.x * float(sp["space"])):
			continue
		var grow: Vector3 = _diag_axis(hit["normal"], off)
		if surface.y + _tip_rise(sp, size, grow.y, stretch) > PLANT_TOP:
			continue
		_add(sp, surface, hit["normal"], grow, size, stretch)
		_weeds += 1
		if surface.y > DIVE_LIMIT:
			_weeds_reachable += 1

## ONE HUGE STRUCTURE PER FACE. See STRUCTURES for what they are and why the reef needed them.
##
## Members are laid out in the face frame around a root offset and EACH ONE is raycast onto
## the concrete separately, so a structure follows the wall rather than being rigidly posed
## off one probe — the same contract as every other pass here. They do NOT go through _claim
## (a structure is authored composition and must not be eaten by the spacing rejection) but
## they ARE registered in `_placed`, which is what makes the colony and crust passes that run
## afterwards settle around them instead of through them.
func _structures(leg: Vector2, leg_i: int) -> void:
	const FACES := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for i in range(FACES.size()):
		var n: Vector3 = FACES[i]
		var kind: Dictionary = STRUCTURES[(leg_i * FACES.size() + i) % STRUCTURES.size()]
		_structure(leg, n, kind, STRUCTURE_DEPTHS[i % STRUCTURE_DEPTHS.size()])

func _structure(leg: Vector2, n: Vector3, kind: Dictionary, depth_f: float) -> void:
	var tangent := Vector3(n.z, 0.0, -n.x)
	var members: Array = kind["members"]
	# THE CLAMP, DERIVED FROM THE LOADED MESHES. Every height below comes from the glTF AABB
	# the loader measured, so nothing here types a Y. Without it a bommie rooted at the
	# shallowest depth fraction would put 9 m of coral through the pontoon the player walks
	# on — the s34 kelp bug with a bigger mesh.
	#
	# TWO TERMS, and leaving the second one out is how a bommie ends up in the walkway. On a
	# VERTICAL face the growth axis is nearly HORIZONTAL (`tilt` is measured off the wall
	# NORMAL), so a reef mass at 6 deg grows almost straight out and its height contributes
	# almost nothing to how far up the wall it reaches. What does is its own girth: the mesh
	# is normalised to a 1 m longest axis, so it spans `size` across and half of that stands
	# above its seat. A clamp on the growth axis alone would have let the top member of a
	# bommie sit 1.7 m higher than it thought it was.
	var plan: Dictionary = _member_plan(members, false)
	var rise: float = plan["rise"]
	var y0: float = minf(lerpf(CRUST_TOP, BAND_BOTTOM, depth_f), PLANT_TOP - rise)
	if y0 - rise < BAND_BOTTOM:
		y0 = BAND_BOTTOM + rise
	# THE SHALLOW STALK CLAMP (owner s36: "reduce the extreme stalk coral near the surface").
	# Decided on the UNCLAMPED geometry — where the structure WOULD have grown to — so the test
	# cannot chase its own tail through the rise it is about to change. `DIVE_LIMIT` is the only
	# depth in it and it is already in this file, off seabed.gd: the water the player can be in.
	if y0 + rise > DIVE_LIMIT:
		plan = _member_plan(members, true)
		rise = plan["rise"]
		y0 = minf(lerpf(CRUST_TOP, BAND_BOTTOM, depth_f), PLANT_TOP - rise)
		if y0 - rise < BAND_BOTTOM:
			y0 = BAND_BOTTOM + rise
	var rows: Array = plan["rows"]
	var along0: float = _rng.randf_range(-0.9, 0.9)
	var seated: int = 0
	for mi in range(members.size()):
		var m: Dictionary = members[mi]
		var sp: Dictionary = _member_species(m, mi)
		if sp.is_empty() or not bool(rows[mi]["build"]):
			continue
		# KEEP THE MEMBER ON THE FACE. Everything else this file places is under a metre
		# across and the existing passes just cap the offset at 2.5-2.6 against a 3.0 m half
		# width; a 4.8 m brain head is 2.3 m of half width on its own, so the same cap would
		# hang half of it off the caisson corner over open water. The limit is the member's
		# own girth subtracted from the face, floored at zero so a piece wider than the
		# caisson simply centres on it rather than flipping sign.
		var halfw: float = float(m["size"]) * float(rows[mi]["sxz"]) * 0.5
		var room: float = maxf(0.0, LEG_HALF - 0.15 - halfw)
		var across: float = clampf(along0 + float(m["ds"]), -room, room)
		var target := Vector3(leg.x, y0 + float(m["dy"]), leg.y) + n * LEG_HALF \
			+ tangent * across
		var hit: Dictionary = _probe(target, n)
		if hit.is_empty():
			continue
		var surface: Vector3 = hit["position"]
		if _blocked(surface):
			continue
		if absf((hit["normal"] as Vector3).dot(n)) < 0.985:
			continue
		var size: float = float(m["size"])
		var stretch := Vector3(float(rows[mi]["sxz"]), float(rows[mi]["sy"]),
			float(rows[mi]["sxz"]))
		var tilt: float = deg_to_rad(float(m["tilt"]))
		var grow: Vector3 = _grow_axis(hit["normal"], tilt)
		# THE STANDOFF, and it is computed rather than authored because it is a consequence of
		# the tilt, not a taste. A piece grown straight OUT of the wall (tilt 0) has its girth
		# in the wall PLANE and needs no standoff; a piece grown UP the wall (tilt ~80, which
		# is what a bommie and a pillar are) has its local XZ plane containing the wall NORMAL,
		# so seating it on the surface buries half its width in the concrete. 0.85 of the half
		# girth leaves the inner edge just inside the wall, which is what "grown into it"
		# looks like. `dout` is a small authored bias on top.
		var stand: float = halfw * sin(tilt) * 0.85 + float(m["dout"])
		# ...except for the PLANAR species, whose girth along the wall normal is the blade
		# THICKNESS (coral_fan_a is 0.21 of its longest axis through the blade, against 1.00
		# across it). _add aligns their blade plane to the wall, so the general formula would
		# float a sea fan a metre off the concrete on its own stalk.
		if bool(sp.get("planar", false)):
			stand = float(m["dout"])
		_add(sp, surface + n * stand, hit["normal"], grow, size, stretch)
		_placed.append([surface, size * 0.55])
		seated += 1
	if seated > 0:
		_structures_built += 1
		# A structure is the best address on the wall, so the fish get told about it too.
		colony_seats.append({"pos": Vector3(leg.x, y0 + rise * 0.5, leg.y) + n * LEG_HALF
			+ tangent * along0, "n": n})

## WHAT EACH MEMBER OF A STRUCTURE IS ACTUALLY BUILT AT, and how high the whole thing reaches.
## Returns one row per member — {build, sy, sxz} — plus `rise`, so the two passes that need
## those numbers (the pontoon clamp, and the placement loop) cannot drift apart.
##
## `clamp` is the s36 owner item: "reduce the extreme stalk coral near the surface."
##
## WHAT THE OWNER IS LOOKING AT, identified rather than guessed. /tmp/s35/reef_top.png is shot
## from (34, -9, -12) at the SE leg's outboard face, and the tall cream branching thing in the
## middle of it is `sponge_rope` — its glTF silhouette is a narrow foot splitting into vertical
## finger-tubes, which is the shape in the frame, and its tint pair (0.96,0.72,0.44 ->
## 1.00,0.92,0.74) is the colour. The kind rotation puts a PILLAR on exactly that face, and the
## pillar stretches sponge_rope by sy 1.70 into a 4.42 m mast standing 1 m off the concrete.
## Root -10.58, top -3.60: it spans the whole of the water a player can be in.
##
## THE RULE: IN THAT WATER, A STALK MEMBER IS SCALED BUT NOT STRETCHED. `sy` comes down to
## `sxz`, which restores the mesh's OWN aspect (sponge_rope is 1.25 tall for 1 wide already —
## it is a bundle of finger-tubes; the stretch is what turns it into a mast) and takes nothing
## off its width, so the piece stays a big sponge instead of becoming a small one. Below the
## dive limit the pillar keeps every metre of its 7 m silhouette, which is the depth that
## silhouette was added for. Nothing else in STRUCTURES is a stalk — see STALK_ASPECT.
##
## AND THEN THE SECOND HALF, which is where the triangles go. A structure member exists to
## carry a silhouette the SCATTER cannot. Once the clamp has taken one down to no taller than
## the scatter's own maximum for that species, it is a duplicate of the scatter with a bespoke
## seat, so it is not built at all: on the shallow pillar that is the third course, 1.44 m
## against a scattered sponge_rope's 1.60 m.
##
## WHAT IT COMES TO, worked off the tables and the glTF extents rather than promised. Three
## pillars exist; two of them grow into reachable water and are clamped, the third does not:
##     leg SE face +x  y -10.58..-3.60 -> -8.52..-4.44, tallest member 4.42 -> 2.21 m,
##                     third course dropped (sponge_rope, 3,600 tris)
##     leg NW face -x  y -14.75..-7.76 -> -14.75..-9.19, tallest member 4.42 -> 2.21 m
##     leg NE face +z  y -22.43..-15.45  UNTOUCHED — it is below the dive limit
## Six members unstretched, one not built, -3,600 triangles. Nothing else in STRUCTURES is
## caught, at any depth: the next-most-slender thing on the reef is a bommie course at 1.33.
func _member_plan(members: Array, clamp: bool) -> Dictionary:
	var rows: Array = []
	var rise: float = 0.0
	for mi in range(members.size()):
		var m: Dictionary = members[mi]
		var sp: Dictionary = _member_species(m, mi)
		if sp.is_empty():
			rows.append({"build": false, "sy": float(m["sy"]), "sxz": float(m["sxz"])})
			continue
		var hn: float = _hnorm(sp)
		var sy: float = float(m["sy"])
		var sxz: float = float(m["sxz"])
		var build: bool = true
		# as DRAWN: height along the growth axis over width across it
		var aspect: float = (hn * sy) / maxf(_gnorm(sp) * sxz, 1.0e-4)
		if clamp and aspect > STALK_ASPECT and sy > sxz:
			sy = sxz
			_stalks_clamped += 1
			build = float(m["size"]) * hn * sy > float(sp["hi"]) * hn
			if not build:
				_stalks_dropped += 1
		rows.append({"build": build, "sy": sy, "sxz": sxz})
		if build:
			rise = maxf(rise, float(m["dy"])
				+ float(m["size"]) * hn * sy * sin(deg_to_rad(float(m["tilt"])))
				+ float(m["size"]) * sxz * 0.5)
	return {"rows": rows, "rise": rise}

## Which species a structure member is made of. A literal slug takes that species out of the
## full table; "mass"/"sponge" take THIS LEG's palette slice, which is what keeps a structure
## from adding a new MultiMesh (and a new draw call) to a leg that did not already have one.
## The member index walks the slice, so a three-mass bommie is not the same head three times.
func _member_species(m: Dictionary, i: int = 0) -> Dictionary:
	var pool: String = String(m["pool"])
	if pool == "mass":
		return _mass_pool[i % _mass_pool.size()] if not _mass_pool.is_empty() else {}
	if pool == "sponge":
		return _sponge_pool[i % _sponge_pool.size()] if not _sponge_pool.is_empty() else {}
	for sp in CORALS:
		if String(sp["slug"]) == pool:
			return sp
	return {}

## THE CRUST. Barnacles scattered over the whole face, from just under the pontoon skirt to
## the bottom of the reef band — deliberately NOT clustered into colonies, because what this
## is for is the concrete BETWEEN the colonies and the bare stripe above them. It is the
## cheapest pass in the file (1.4-4k tris a piece) and the one that does the most to stop a
## caisson reading as a painted wall.
func _crust_face(leg: Vector2, n: Vector3, ex: float) -> void:
	if _crust_pool.is_empty():
		return
	# Scattered over the WHOLE face, so extending the band downward without scaling this
	# would have thinned the crust per metre instead of covering the new concrete.
	#
	# s35: 13..25 -> 9..17, 782 attempts down to 534. KNOWN_ISSUES names this pass as one of
	# the two cheapest levers on the reef and the s34 close-out frames say it is also the one
	# doing the most damage to the look: reef_mid.png and reef_deep.png are a grey caisson
	# with PALE SCABS all over it, and this is the pass that puts them there. Cutting a third
	# of it and shifting the mix off the white 4,000-tri species (see CRUSTS) is the whole
	# payment for the kelp bed, and it should make the wall read better rather than worse.
	var count: int = int(round(lerpf(9.0, 17.0, ex) * band_scale(_band_top)))
	for i in range(count):
		var y: float = _rng.randf_range(CRUST_TOP, BAND_BOTTOM)
		var depth_t: float = clampf((y - _band_top) / (BAND_BOTTOM - _band_top), 0.0, 1.0)
		_seat_on_face(leg, n, _rng.randf_range(-2.5, 2.5), y, _pick(_crust_pool, depth_t))

## Big starfish DOWN THE LEG (owner call — they were only on the foundation in s19). Seated
## flat like the foundation ones, spread over the whole face rather than the coral band, and
## on a random face each so they are a thing you come across rather than a row.
func _stars_down_leg(leg: Vector2) -> void:
	if _bigstar_pool.is_empty():
		return
	const FACES := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for i in range(int(round(float(BIG_STARS_PER_LEG) * band_scale(_band_top)))):
		var n: Vector3 = FACES[_rng.randi_range(0, 3)]
		var tangent := Vector3(n.z, 0.0, -n.x)
		var y: float = _rng.randf_range(CRUST_TOP, BAND_BOTTOM)
		var target := Vector3(leg.x, y, leg.y) + n * LEG_HALF \
			+ tangent * _rng.randf_range(-2.3, 2.3)
		_seat_star(target, n, _pick(_bigstar_pool, -1.0))

## Put one coral on a caisson face. `along` is the offset across the face and `depth`
## the world y; the exact seating point and normal come from a raycast into the
## concrete, so this never assumes where the surface is.
func _seat_on_face(leg: Vector2, n: Vector3, along: float, depth: float, sp: Dictionary) -> void:
	var tangent := Vector3(n.z, 0.0, -n.x)
	var target := Vector3(leg.x, depth, leg.y) + n * LEG_HALF + tangent * along
	var hit: Dictionary = _probe(target, n)
	if hit.is_empty():
		return
	var surface: Vector3 = hit["position"]
	if _blocked(surface):
		return
	var size: float = _rng.randf_range(float(sp["lo"]), float(sp["hi"]))
	# depth thins the reef out: the top of the band is a wall of coral, the bottom is
	# scattered survivors
	var t: float = clampf((surface.y - _band_top) / (BAND_BOTTOM - _band_top), 0.0, 1.0)
	# s19 thinned to 0.60 keep / 0.72 size at the bottom of the band, which photographed as a
	# rich top and an almost bare deep half — the "colony_close2" frame at y -18.5 had two
	# pieces in it. Softened: still a gradient (reefs really do thin with light), but the
	# deep band is now scattered survivors rather than nothing.
	if _rng.randf() > lerpf(1.0, 0.78, t):
		return
	size *= lerpf(1.0, 0.80, t)
	var space: float = size * float(sp["space"])
	if not _claim(surface, space):
		return
	# A gorgonian on a vertical wall does not stand out of it like a signpost — it hugs
	# the concrete and fans UP and outward, which is also the only orientation that does
	# not read as a smear when you swim up to it face-on. So the planar species lean far
	# further off the normal than the massive ones do.
	var tilt: Array = sp.get("tilt_planar", sp["tilt"])
	var grow: Vector3 = _grow_axis(hit["normal"], deg_to_rad(_rng.randf_range(tilt[0], tilt[1])))
	_add(sp, surface, hit["normal"], grow, size)

## The growth direction: the surface normal, leaned toward the surface (up-current for a
## fan, toward the light for everything else). A coral on a vertical wall does not grow
## straight out of it.
func _grow_axis(normal: Vector3, tilt: float) -> Vector3:
	var lean := Vector3.UP
	if absf(normal.dot(Vector3.UP)) > 0.8:
		# a horizontal surface (the pontoon underside): lean in a random direction
		var a: float = _rng.randf_range(0.0, TAU)
		lean = Vector3(cos(a), 0.0, sin(a))
	return (normal * cos(tilt) + lean * sin(tilt)).normalized()

## THE DIAGONAL A WALL PLANT GROWS ALONG — derived from the probed face and world up, not
## typed per face (owner s36: "angle plants diagonal so they can root against the base").
##
## `up_face` is world up with the face's own normal component removed, so `normal + up_face`
## normalised is the BISECTOR: exactly 45 deg out of any of the sixteen vertical caisson faces
## and off any face the probe ever returns, with no per-face number anywhere. `off` is the
## per-instance wander about it (a species' `diag` band), in radians.
##
## WHY THE BISECTOR RATHER THAN A WIDER RANGE. `_grow_axis`' `tilt` is measured off the face
## NORMAL, so on a vertical wall a small tilt is HORIZONTAL, not upright — the s35 plant table
## started at 20-24 deg and photographed as blades fired straight out of the concrete. The
## diagonal is the one orientation that is neither "along the normal" nor "straight up", and
## it is the one a plant reaching from a wall toward the light actually takes.
##
## On a HORIZONTAL surface (the pontoon underside) world up has no component in the face and
## there is no diagonal to build, so this degrades to _grow_axis' random-azimuth lean — which
## is the right answer there for the same reason it always was.
func _diag_axis(normal: Vector3, off: float) -> Vector3:
	var up_face: Vector3 = Vector3.UP - normal * normal.y
	if up_face.length() < 0.05:
		return _grow_axis(normal, PI * 0.25 + off)
	up_face = up_face.normalized()
	# clamped well inside both ends, so no `diag` band a later session widens can flip a plant
	# back onto the normal or fold it flat against the wall
	var t: float = clampf(PI * 0.25 + off, 0.14, 1.43)
	return (normal * cos(t) + up_face * sin(t)).normalized()

## Spacing rejection — this is what stops the scatter reading as a repeating pattern
## or as one interpenetrating blob.
func _claim(pos: Vector3, radius: float) -> bool:
	for p in _placed:
		if pos.distance_to(p[0]) < (radius + p[1]) * 0.50:
			return false
	_placed.append([pos, radius])
	return true

# ------------------------------------------------------------ the foundation

## Starfish over the rig's submerged foundation: the pontoon slabs' outer walls, their
## inner walls, and the big shadowed underside a swimmer sees looking up. A handful
## also ride the leg faces in the band between the skirt and the coral, so the two
## communities meet instead of sitting in separate stripes.
func _dress_foundation() -> void:
	var faces: Array = []
	for sz in [-1.0, 1.0]:
		var zo: float = SKIRT_Z_OUT * sz
		var zi: float = SKIRT_Z_IN * sz
		# outer long wall, inner long wall
		faces.append({"n": Vector3(0, 0, sz), "fix": zo, "axis": "z", "span": [-27.0, 27.0], "n_inst": 20})
		faces.append({"n": Vector3(0, 0, -sz), "fix": zi, "axis": "z", "span": [-27.0, 27.0], "n_inst": 11})
		# the two end walls of this pontoon
		for sx in [-1.0, 1.0]:
			faces.append({"n": Vector3(sx, 0, 0), "fix": SKIRT_X * sx, "axis": "x",
				"span": [minf(zi, zo) + 0.8, maxf(zi, zo) - 0.8], "n_inst": 4})
	# The whole family is available down here — the foundation is one continuous surface,
	# so there is no per-leg culling argument for slicing it.
	_bigstar_pool = BIG_STARS
	for f in faces:
		_scatter_wall(f)
	_scatter_underside()
	_scatter_leg_shallows()
	_scatter_big_stars(faces)
	_place_giants()

## The big starfish on the foundation, in among the small ones. Same probed seating; the
## split between wall and underside is deliberate — a 1.5 m sunflower star hanging off the
## ceiling of the space under the rig is the single most findable animal down there.
func _scatter_big_stars(faces: Array) -> void:
	for i in range(BIG_STARS_FOUNDATION):
		var sp: Dictionary = _pick(BIG_STARS, -1.0)
		if _rng.randf() < 0.42:
			var x: float = _rng.randf_range(-26.0, 26.0)
			var sz: float = [-1.0, 1.0][_rng.randi_range(0, 1)]
			var z: float = sz * _rng.randf_range(SKIRT_Z_IN + 1.0, SKIRT_Z_OUT - 1.0)
			_seat_star(Vector3(x, SKIRT_BOTTOM, z), Vector3(0, -1, 0), sp)
			continue
		var f: Dictionary = faces[_rng.randi_range(0, faces.size() - 1)]
		var along: float = _rng.randf_range(f["span"][0], f["span"][1])
		var y: float = _rng.randf_range(SKIRT_BOTTOM + 0.5, -0.6)
		if f["axis"] == "z":
			_seat_star(Vector3(along, y, float(f["fix"])), f["n"], sp)
		else:
			_seat_star(Vector3(float(f["fix"]), y, along), f["n"], sp)

## A vertical foundation wall. The band is the skirt underside up to just under the
## waterline; every candidate is raycast onto the real slab.
func _scatter_wall(f: Dictionary) -> void:
	var n: Vector3 = f["n"]
	for i in range(int(f["n_inst"])):
		var along: float = _rng.randf_range(f["span"][0], f["span"][1])
		var y: float = _rng.randf_range(SKIRT_BOTTOM + 0.25, -0.35)
		var target: Vector3
		if f["axis"] == "z":
			target = Vector3(along, y, float(f["fix"]))
		else:
			target = Vector3(float(f["fix"]), y, along)
		_seat_star(target, n, _pick_star())

## The pontoon underside — the ceiling of the space under the rig. Stars hang from it,
## which is both true to the animal and the single best place to notice one.
func _scatter_underside() -> void:
	var n := Vector3(0, -1, 0)
	for i in range(39):
		var x: float = _rng.randf_range(-27.0, 27.0)
		var sz: float = [-1.0, 1.0][_rng.randi_range(0, 1)]
		var z: float = sz * _rng.randf_range(SKIRT_Z_IN + 0.6, SKIRT_Z_OUT - 0.6)
		_seat_star(Vector3(x, SKIRT_BOTTOM, z), n, _pick_star())

## A few on the caisson faces between the skirt and the top of the coral band.
func _scatter_leg_shallows() -> void:
	for leg in LEGS:
		for i in range(4):
			var n: Vector3 = [Vector3(1, 0, 0), Vector3(-1, 0, 0),
				Vector3(0, 0, 1), Vector3(0, 0, -1)][_rng.randi_range(0, 3)]
			var tangent := Vector3(n.z, 0.0, -n.x)
			var y: float = _rng.randf_range(SKIRT_BOTTOM - 0.6, _band_top + 0.4)
			var target := Vector3(leg.x, y, leg.y) + n * LEG_HALF \
				+ tangent * _rng.randf_range(-2.4, 2.4)
			_seat_star(target, n, _pick_star())

## The seven-arm giant, HUGE_COUNT of them, on the faces a swimmer actually meets: the
## south pontoon's outer wall (the side you enter the water from), the underside on the
## way in to the wet deck, and one out on the far north wall for whoever swims the whole
## foundation. Positions are candidate targets — the raycast still decides the seat.
func _place_giants() -> void:
	var picks := [
		[Vector3(-6.0, -1.7, -SKIRT_Z_OUT), Vector3(0, 0, -1)],
		[Vector3(9.5, SKIRT_BOTTOM, -12.6), Vector3(0, -1, 0)],
		[Vector3(-15.5, -1.5, SKIRT_Z_OUT), Vector3(0, 0, 1)],
	]
	for i in range(mini(HUGE_COUNT, picks.size())):
		_seat_star(picks[i][0], picks[i][1], STAR_HUGE, true)

func _pick_star() -> Dictionary:
	var total: float = 0.0
	for s in STARS:
		total += float(s["w"])
	var roll: float = _rng.randf() * total
	for s in STARS:
		roll -= float(s["w"])
		if roll <= 0.0:
			return s
	return STARS[0]

## Seat one starfish flat against a probed surface. A star lies ON the rock — no tilt
## off the normal, just a random roll about it and a little wobble so a wall of them
## does not read as a decal sheet.
func _seat_star(target: Vector3, n: Vector3, sp: Dictionary, force: bool = false) -> void:
	var hit: Dictionary = _probe(target, n)
	if hit.is_empty():
		return
	var surface: Vector3 = hit["position"]
	if _blocked(surface):
		return
	var size: float = _rng.randf_range(float(sp["lo"]), float(sp["hi"]))
	# A star claims LESS room than a coral of the same size, because it is a flat animal that
	# lies ON the reef rather than a colony competing for space in it — 0.62 was rejecting big
	# stars against coral they would in reality be sitting on top of.
	if not _claim(surface, size * (0.85 if force else 0.44)) and not force:
		return
	var grow: Vector3 = _grow_axis(hit["normal"], deg_to_rad(_rng.randf_range(0.0, 11.0)))
	_add(sp, surface, hit["normal"], grow, size)

# ------------------------------------------------------------ batching

## The batch a species goes into. Normally its slug — but the WEEDS build several distinct
## FORMS out of one mesh (a strap blade and a whip are the same glTF at different stretches),
## and those need their own MultiMesh and their own tint pair, so a species may name its own
## key. Keeping the two separate is also what lets `path`/`slug` stay purely about the file.
static func _key(sp: Dictionary) -> String:
	return String(sp.get("key", sp.get("slug", "")))

## The mesh's own height as a fraction of its longest axis, i.e. what `size` metres of a
## species actually stands up off the wall. Loads the batch if it has not been touched yet,
## because the tip clamps need this BEFORE anything is placed. 1.0 for a species that failed
## to load, which is the conservative direction: it makes the clamp seat things deeper.
func _hnorm(sp: Dictionary) -> float:
	var b: Dictionary = _batch(sp)
	return 1.0 if b.is_empty() else float(b["hnorm"])

## The mesh's own GIRTH as a fraction of its longest axis — the widest of its two cross-axis
## extents. Only the stalk test uses it (see STALK_ASPECT), and it comes off the same AABB
## `hnorm` does, so a re-cut that changes a species' proportions moves both together.
func _gnorm(sp: Dictionary) -> float:
	var b: Dictionary = _batch(sp)
	return 1.0 if b.is_empty() else float(b["gnorm"])

func _batch(sp: Dictionary) -> Dictionary:
	var key: String = _key(sp)
	if not _batches.has(key):
		var loaded: Dictionary = _load(sp)
		if loaded.is_empty():
			return {}
		_batches[key] = loaded
	return _batches[key]

## HOW HIGH THE DRAWN PIECE REACHES ABOVE ITS SEAT, in metres.
##
## The s35 clamp used `size * hnorm * sin(lean)` — the growth axis and nothing else. That was
## already an underestimate and it becomes a worse one for a ROOTED plant, because a rooted
## instance's cross sections lie in the WALL PLANE, and the wall plane contains world up: half
## the plant's width is also half its reach upward. Measured off the mesh's own radius-by-
## height profile instead,
##     rise = size * max over bands of ( sy * grow.y * y_band + sxz * r_band )
## which is an upper bound over the random roll AND a tight one, because the two wall-plane
## columns are orthonormal and span a plane containing up, so some roll achieves it.
##
## Worth the arithmetic: on a 1.8 m sea grass at 45 deg it is 1.601 m against the old formula's
## 1.273 m, i.e. the old clamp had 328 mm of slack it did not know about, under a pontoon whose
## underside is only 550 mm above PLANT_TOP.
func _tip_rise(sp: Dictionary, size: float, gy: float, stretch: Vector3) -> float:
	var b: Dictionary = _batch(sp)
	if b.is_empty() or not b.has("prof_y"):
		return size * _hnorm(sp) * stretch.y * maxf(gy, 0.0)
	var ys: PackedFloat32Array = b["prof_y"]
	var rs: PackedFloat32Array = b["prof_r"]
	var top: float = 0.0
	for i in range(ys.size()):
		top = maxf(top, stretch.y * maxf(gy, 0.0) * ys[i] + stretch.x * rs[i])
	return size * top

## THE MESH'S OWN SHAPE, measured once per species at load and used by two different things
## that must not disagree: the tip clamp (how wide is it at each height) and the build-time
## base-contact check (which vertices ARE the holdfast).
##
## The holdfast ring is kept as REAL VERTICES, not as the radius the seating uses. That is the
## whole point — the seat is one scalar along the wall normal, and a check that re-derived the
## contact from that scalar could not fail however wrong the transform was (the s34 seal
## tautology). Walking the actual vertices through the actual instance basis can.
const BASE_BANDS: int = 20
const BASE_RING: int = 48

func _mesh_profile(mesh: Mesh, aabb: AABB, longest: float) -> Dictionary:
	var h: float = maxf(aabb.size.y, 1.0e-4)
	var ys := PackedFloat32Array()
	var rs := PackedFloat32Array()
	ys.resize(BASE_BANDS)
	rs.resize(BASE_BANDS)
	for i in range(BASE_BANDS):
		# the TOP of band i, so the bound above is taken at the highest point of each band
		ys[i] = (aabb.position.y + h * float(i + 1) / float(BASE_BANDS)) / longest
		rs[i] = 0.0
	var ring_v: Array[Vector3] = []
	var ring_r := PackedFloat32Array()
	ring_v.resize(BASE_RING)
	ring_r.resize(BASE_RING)
	for i in range(BASE_RING):
		ring_r[i] = -1.0
	var cut: float = aabb.position.y + h / float(BASE_BANDS)
	for v in mesh.get_faces():
		var band: int = clampi(int((v.y - aabb.position.y) / h * float(BASE_BANDS)),
			0, BASE_BANDS - 1)
		var r: float = Vector2(v.x, v.z).length()
		rs[band] = maxf(rs[band], r / longest)
		if v.y <= cut:
			# the widest vertex in each of 48 directions round the stem: those are the ones
			# that lift first under any basis error, so they are the ones worth checking
			var bin: int = clampi(int((atan2(v.z, v.x) + PI) / TAU * float(BASE_RING)),
				0, BASE_RING - 1)
			if r > ring_r[bin]:
				ring_r[bin] = r
				ring_v[bin] = v
	var ring := PackedVector3Array()
	for i in range(BASE_RING):
		if ring_r[i] >= 0.0:
			ring.append(ring_v[i])
	return {"prof_y": ys, "prof_r": rs, "base_ring": ring}

## Queue one instance. Nothing is built until _flush, so a leg's whole colony becomes
## one MultiMesh per species.
##
## `stretch` is a NON-UNIFORM scale in the piece's OWN frame (x/z across, y along the growth
## axis). It is what makes a kelp bed out of two meshes and a pillar out of a barrel sponge;
## the sway shader undoes the normal skew it causes (see materials/reef_sway.gdshader).
func _add(sp: Dictionary, surface: Vector3, normal: Vector3, grow: Vector3, size: float,
		stretch: Vector3 = Vector3.ONE) -> void:
	var key: String = _key(sp)
	if not _batches.has(key):
		var loaded: Dictionary = _load(sp)
		if loaded.is_empty():
			return
		_batches[key] = loaded
	var b: Dictionary = _batches[key]
	# RECESS — bite the base into the concrete so no flat cut edge shows against the
	# wall, and so a piece leaning off the normal does not lift one side of its base
	# off it. Scaled by how far it leans (that is what opens the gap) and capped at a
	# third of the piece's OWN height along its growth axis, which is the measurement
	# that matters: a 1.7 m table coral is only half a metre tall, and a recess sized
	# off its longest axis buried it.
	var height: float = size * float(b["hnorm"]) * stretch.y
	var lean: float = sqrt(maxf(0.0, 1.0 - pow(grow.dot(normal), 2.0)))
	# The absolute ceiling matters as much as the proportional one. What the recess has
	# to hide is the lift of the BASE edge, which is at most half a holdfast wide — a
	# few centimetres. Scaling by lean alone drove the planar species (which lean 40-70
	# deg on purpose) to 385 mm and started swallowing whole sea fans.
	var recess: float = minf(0.035 + size * 0.26 * lean, minf(height * 0.32, RECESS_MAX))
	# A ROOTED SPECIES IS SEATED DIFFERENTLY, and this is the s36 owner item.
	#
	# WHAT WAS WRONG. Every other piece here is placed with a RIGID rotation whose +Y is the
	# growth axis, so its base plate turns with it: tilt the plant and one edge of the base
	# digs into the concrete while the opposite edge lifts off it, by base_radius * sin(lean).
	# Off the glTF, for a 1.80 m bloom_sea_grass at the old table's 56 deg that is 348 mm of
	# lift against a recess the cap holds at 220 mm — 128 mm of daylight under the plant, which
	# is "standing proud of it" exactly. A 4.40 m kelp_blade at 42 deg was 96 mm. Recessing far
	# enough to close it is not the answer either: burying the up-slope edge means the wall
	# plane cuts the mesh diagonally, and on that same sea grass it emerges 56.5% of the way up
	# its own stem — which is also where the sway shader is already moving it 63.7 mm.
	#
	# WHAT REPLACES IT. A holdfast is FLAT ON THE ROCK and the stem leans away from it, so the
	# instance is built with its local XZ plane IN THE WALL PLANE and only its +Y column on the
	# diagonal. That is a shear, not a rotation, and it is the one that matches the biology:
	#   * the base ring lies exactly in the probed plane, at every lean, for every size — the
	#     gap is zero by construction rather than by tuning;
	#   * because both cross-axis columns are perpendicular to the wall normal, a local point's
	#     distance out of the concrete depends on its local Y ALONE. The wall therefore cuts
	#     every rooted plant at ONE height, and that height is just the bite (below);
	#   * the plant's cross sections stay parallel to the concrete as it rises, which is what a
	#     clump of blades leaning off a wall actually looks like.
	# The determinant stays POSITIVE (see the column order) — a negative one inverts triangle
	# winding and renders the model inside out, which cost s23 a run. It would not bite the
	# three flora meshes today, because reef_sway.gdshader is `cull_disabled`; the branch is
	# general and _check_root watches it for one dot product a plant.
	var basis: Basis
	if bool(sp.get("root", false)) and absf(normal.dot(Vector3.UP)) < 0.8:
		# the bite: sink the flat cut base by the height of the mesh's OWN holdfast band, so
		# the cut edge is under the concrete and never shows. Measured, not chosen — it is one
		# band of the profile _mesh_profile already walks, and RECESS_MAX still caps it so a
		# 7.7 m kelp strand does not swallow half a metre of itself.
		recess = minf(height / float(BASE_BANDS), RECESS_MAX)
		var side: Vector3 = Vector3.UP.cross(normal)
		if side.length() < 0.05:
			side = Vector3.RIGHT.cross(normal)
		side = side.normalized()
		# side.cross(normal), NOT normal.cross(side): that order is what makes the determinant
		# +cos(lean) instead of -cos(lean).
		basis = Basis(side, grow, side.cross(normal))
		# the roll is applied about the piece's OWN +Y (a right multiply), so it mixes the two
		# columns that are already in the wall plane and leaves them there. Rolling about the
		# growth axis the way the other branches do would tip the base plate off the concrete.
		basis = basis * Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
		basis = basis.scaled_local(stretch * size * float(b["norm"]))
		_check_root(b, basis, surface - normal * recess, surface, normal, sp, height, recess)
		b["xf"].append(Transform3D(basis, surface - normal * recess))
		b["col"].append(Color(sp["a"]).lerp(Color(sp["b"]), _rng.randf()))
		return
	var origin: Vector3 = surface - normal * recess
	# A right-handed basis with +Y on the growth axis. The ROLL about that axis is what
	# decides whether a sea fan stands out from the wall or lies flat on it — a random
	# roll gave a wall of purple smears, because a fan seen edge-on IS a smear. Planar
	# species (fan, whip: blade plane = local XY, blade normal = local +Z) get their
	# blade normal aligned to the wall's horizontal tangent, so the blade plane contains
	# the wall normal and the fan presents its face to the flow, the way a gorgonian
	# actually grows. Everything else rolls freely.
	if bool(sp.get("planar", false)):
		# blade normal (local +Z) points away from the wall, so the blade plane lies
		# roughly PARALLEL to the concrete and a swimmer meets its face, not its edge
		var z_ax: Vector3 = (normal - grow * normal.dot(grow)).normalized()
		if z_ax.length() < 0.5:
			z_ax = Vector3.FORWARD
		basis = Basis(grow.cross(z_ax), grow, z_ax)
		basis = basis.rotated(grow, _rng.randf_range(-0.38, 0.38))
	else:
		var ref := Vector3.UP if absf(grow.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var x_ax: Vector3 = ref.cross(grow).normalized()
		basis = Basis(x_ax, grow, x_ax.cross(grow))
		basis = basis.rotated(grow, _rng.randf_range(0.0, TAU))
	# The mesh is normalised to a 1 m longest axis by _load, so scale IS the size.
	# scaled_LOCAL, not scaled(). Basis.scaled() left-multiplies — it scales along the PARENT
	# axes — which is identical for the uniform case this line used to be and silently wrong
	# the moment `stretch` is anything else: a kelp strand would have been stretched along
	# world Y instead of along its own growth axis, so a plant leaning 40 deg off the wall
	# would have sheared rather than grown. Same class of bug as the decimator's GLTF_UP note.
	basis = basis.scaled_local(stretch * size * float(b["norm"]))
	b["xf"].append(Transform3D(basis, origin))
	b["col"].append(Color(sp["a"]).lerp(Color(sp["b"]), _rng.randf()))

## THE BASE-CONTACT MEASUREMENT — run on every rooted instance as it is queued, because "the
## base is on the concrete" is the thing the s36 change is FOR and a claim is not a number.
##
## IT MEASURES THE TWO PREMISES OF A PROOF rather than sampling for a symptom, because
## sampling is what let a floating seal stay green for two sessions:
##   FLUSH — every holdfast vertex is exactly where a base plate lying IN the wall plane would
##     put it, i.e. its distance out of the concrete is a function of its own local height and
##     nothing else. That is the claim the sheared basis makes.
##   BITE  — the mesh's lowest geometry, its cut base edge, is inside the concrete.
## Distance-out is then monotone in local height, so the plant's surface crosses the wall plane
## exactly once and everything below that crossing is buried: there is no configuration of
## size, lean or roll that can leave daylight under a plant. That is stronger than "no gap was
## observed", and it is what the two numbers buy.
##
## NEITHER IS A TAUTOLOGY. The seating is a single scalar along the wall normal; this walks the
## mesh's REAL holdfast vertices through the REAL scaled instance basis against the plane the
## raycast actually returned. FLUSH goes non-zero if the cross-axis columns are not in the wall
## plane (a Basis row/column mix-up, `scaled` instead of `scaled_local`, the roll applied about
## the growth axis instead of local +Y, a rigid tilt creeping back in — that last one puts
## base_radius * sin(lean), up to 420 mm, straight into this number). BITE goes negative if the
## bite went the wrong way or the probe handed back a plane the caller did not expect. The
## determinant is watched too: negative flips triangle winding and renders the mesh inside out.
func _check_root(b: Dictionary, basis: Basis, origin: Vector3, surface: Vector3,
		normal: Vector3, sp: Dictionary, height: float, recess: float) -> void:
	if not b.has("base_ring"):
		return
	_root_n += 1
	# how far out of the wall the piece's own +Y column carries one local unit of height. The
	# WHOLE claim is that this is the only term: nothing in the cross-axis columns leaves the
	# wall plane, so a vertex's depth cannot depend on where it sits round the stem.
	var k_out: float = basis.y.dot(normal)
	var flush: float = 0.0
	var bite: float = -1.0e9
	for v in (b["base_ring"] as PackedVector3Array):
		var d: float = (origin + basis * v - surface).dot(normal)
		flush = maxf(flush, absf(d - (v.y * k_out - recess)))
		bite = maxf(bite, -d)            # deepest = lowest, because d is monotone in v.y
	var det: float = basis.determinant()
	if flush > 0.0005 or bite <= 0.0 or det <= 0.0:
		_root_fail += 1
	_root_flush_max = maxf(_root_flush_max, flush)
	_root_bite_min = minf(_root_bite_min, bite)
	_root_bite_max = maxf(_root_bite_max, bite)
	_root_det_min = minf(_root_det_min, det)
	# WHERE THE CONCRETE CUTS THE STEM, which is the sway shader's half of this. The shader
	# anchors at the mesh's local y = 0 and grows as h^2, so the question the owner asked is not
	# "is the anchor at the base" (it is, by the decimator's contract, and an instance transform
	# cannot move it) but "how far up the stem is the plant when it leaves the wall". By the
	# same monotonicity as above that is a SINGLE height for every rooted plant:
	# recess / (drawn height * cos(lean)). The displacement there is the shader's own algebra —
	# (lean + w * sway_amp) * <drawn height> * h^2, with lean = 0.6 * amp and w peaking at
	# 1.42 — i.e. the peak travel of the plant AT the point it meets the concrete.
	var cos_lean: float = maxf(basis.y.normalized().dot(normal), 0.05)
	var cut: float = clampf(recess / maxf(height * cos_lean, 1.0e-4), 0.0, 1.0)
	_root_cut_max = maxf(_root_cut_max, cut)
	_root_sway_max = maxf(_root_sway_max,
		2.02 * float(sp.get("sway", 0.0)) * height * cut * cut)

## Load a reef piece once: its mesh, and a material that takes the per-instance colour.
## Returns {} when the .glb is missing, which drops that species instead of crashing —
## the same degradation every other generated asset in this project has.
func _load(sp: Dictionary) -> Dictionary:
	var slug: String = sp["slug"]
	# Most species live in the reef set; the WALL PLANTS reuse the flora already generated
	# for underwater_world's growth band, which sits one directory up. Per-species so the
	# two sets can share every other line of this loader.
	var path: String = String(sp.get("path", REEF_PATH)) % [slug, slug]
	if not ResourceLoader.exists(path):
		push_warning("[leg_reef] missing %s" % path)
		return {}
	var packed := load(path) as PackedScene
	if packed == null:
		return {}
	var inst := packed.instantiate()
	var found: MeshInstance3D = null
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		found = node
		break
	if found == null or found.mesh == null:
		inst.queue_free()
		return {}
	var mesh: Mesh = found.mesh
	var aabb: AABB = mesh.get_aabb()
	var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var src: Material = found.get_active_material(0)
	inst.queue_free()
	var mat: StandardMaterial3D = null
	if src is StandardMaterial3D:
		mat = (src as StandardMaterial3D).duplicate()
	else:
		mat = StandardMaterial3D.new()
	# per-instance MultiMesh colour multiplies albedo — this is where the scale/rotation
	# variation gets its colour partner, at no extra material and no extra draw call
	mat.vertex_color_use_as_albedo = true
	# The generators return a glassy skin by default (docs/AGENT_TRAPS.md) and on some
	# pieces the specular reads as plastic under the floodlight cones. Per-species, opt-in.
	if sp.has("rough"):
		mat.roughness = float(sp["rough"])
		mat.metallic = 0.0
	# BLOOM GLOW — see GLOW. Keyed off the albedo map so it lights the living tissue rather
	# than glowing uniformly like a lamp, and scaled per species: chalk barnacles are not
	# bioluminescent and take a fraction of what a living coral does.
	if mat.albedo_texture != null:
		mat.emission_enabled = true
		mat.emission_texture = mat.albedo_texture
		mat.emission = GLOW_TINT
		mat.emission_energy_multiplier = GLOW * float(sp.get("glow", 1.0))
	var out: Material = mat
	if sp.has("sway"):
		out = _sway_material(mat, aabb, float(sp["sway"]), float(sp.get("glow", 1.0)))
	var b: Dictionary = {"mesh": mesh, "mat": out, "norm": 1.0 / maxf(longest, 0.001),
		"hnorm": aabb.size.y / maxf(longest, 0.001),
		"gnorm": maxf(aabb.size.x, aabb.size.z) / maxf(longest, 0.001),
		"xf": [] as Array, "col": [] as Array}
	# Only the ROOTED species pay for the vertex walk — three meshes, five batch keys, ~24k
	# vertices each. Nothing else needs the profile, and _report already shows that walking
	# every species' faces at build time is not free.
	if bool(sp.get("root", false)):
		b.merge(_mesh_profile(mesh, aabb, maxf(longest, 0.001)))
	return b

## THE SWAY MATERIAL. Nothing on this reef has ever moved — not a frond, not a fan — and the
## owner has now asked for it twice. This is the same trick every animal in the game uses
## (vertex displacement, no bones: see materials/creature_swim.gdshader) rebuilt for the one
## case that shader cannot serve, a MultiMesh where one material has to drive hundreds of
## plants with different phases. The per-instance phase is derived in the shader.
##
## Costs nothing per frame in GDScript, which matters: KNOWN_ISSUES puts bloom_fauna's
## per-frame script at 19-32% of the frame already, and a reef that animated from _process
## would be the same mistake at three times the instance count.
##
## The PBR side is rebuilt off the StandardMaterial3D that was just configured, rather than
## off the raw glTF, so a sway species keeps every decision the non-sway path makes — the
## `rough` override, the glow scale, and the metallicRoughness MAP that thirteen species in
## this project went black without (s23).
func _sway_material(src: StandardMaterial3D, aabb: AABB, amp: float, glow: float) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://materials/reef_sway.gdshader")
	if src.albedo_texture != null:
		sm.set_shader_parameter("albedo_tex", src.albedo_texture)
	sm.set_shader_parameter("tint", src.albedo_color)
	sm.set_shader_parameter("roughness_v", src.roughness)
	sm.set_shader_parameter("metallic_v", src.metallic)
	# Both halves or neither — glTF packs ONE metallicRoughness image and the importer binds
	# it to both slots, so a material carrying only one of them is not this convention.
	if src.metallic_texture != null and src.roughness_texture != null:
		sm.set_shader_parameter("orm_tex", src.metallic_texture)
		sm.set_shader_parameter("use_orm", true)
		sm.set_shader_parameter("orm_rough_mask", _channel_mask(src.roughness_texture_channel))
		sm.set_shader_parameter("orm_metal_mask", _channel_mask(src.metallic_texture_channel))
	if src.normal_enabled and src.normal_texture != null:
		sm.set_shader_parameter("normal_tex", src.normal_texture)
		sm.set_shader_parameter("use_normal", true)
	sm.set_shader_parameter("glow_tint", GLOW_TINT)
	sm.set_shader_parameter("glow_energy", GLOW * glow if src.albedo_texture != null else 0.0)
	# The mesh's own height in LOCAL units — the shader's height fraction, and the reason a
	# plant is anchored at its holdfast. Read off the live AABB, never assumed to be 1.0: the
	# decimator normalises the BASE to y = 0, not the height to 1.
	sm.set_shader_parameter("mesh_h", aabb.size.y)
	# `sway` is peak tip travel as a FRACTION OF THE PLANT'S OWN DRAWN HEIGHT (the shader's
	# header does the algebra: the stretch cancels, so one number means the same thing on a
	# 0.7 m tuft and a 7.7 m strand). 0.09 on kelp is ~1.8 m of peak-to-peak travel at the
	# tip of a 7 m frond; 0.022 on the anemone is a column breathing, not a blade waving.
	sm.set_shader_parameter("sway_amp", amp)
	# The steady bend, 0.6 of the wander. A plant in a current is bent and wanders about the
	# bend; without this it stands vertical and oscillates, which reads as a metronome rather
	# than as water going past.
	sm.set_shader_parameter("lean", amp * 0.6)
	sm.set_shader_parameter("current", CURRENT)
	return sm

## Which channel of an ORM texture a BaseMaterial3D says a value lives in, as a dot mask.
## Same rule (and same reason) as CreatureAnim._channel_mask: glTF is always G = roughness,
## B = metallic, but the enum is ASKED rather than the convention assumed.
static func _channel_mask(channel: int) -> Color:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_RED:
			return Color(1.0, 0.0, 0.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Color(0.0, 1.0, 0.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Color(0.0, 0.0, 1.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Color(0.0, 0.0, 0.0, 1.0)
	return Color(1.0, 0.0, 0.0, 0.0)

## Build the queued instances into one MultiMeshInstance3D per species and reset.
## How far a reef batch is drawn, and the fade that hides its edge. See the note in _flush.
const REEF_DRAW_M: float = 55.0
const REEF_FADE_M: float = 18.0

func _flush(tag: String) -> void:
	for slug in _batches.keys():
		var b: Dictionary = _batches[slug]
		var xf: Array = b["xf"]
		if xf.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = b["mesh"]
		mm.instance_count = xf.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "LegReef_%s_%s" % [tag, slug]
		mmi.multimesh = mm
		mmi.material_override = b["mat"]
		# decoration: it must not add to the shadow cost of a rig that was measured at
		# 9.3 fps, and it is under water where the sun does not reach anyway
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# DISTANCE-CULLED, which it never was. render_budget.gd gives every dressing mesh a
		# visibility range, but it walks MeshInstance3D — and MultiMeshInstance3D does NOT
		# derive from it, so all 62 of the reef's batches fell straight through that pass and
		# have been drawn at every range since they were built. This is the reef that
		# KNOWN_ISSUES names as the heaviest thing in the dive band (~1 M tris per leg), on a
		# game measured at 26-35 fps, and it is a two-line fix.
		#
		# The band is set by what a coral head actually resolves to: these are 0.35-1.95 m
		# pieces seen through a fog grade that runs 0.028-0.2 per metre, so past ~55 m a
		# colony is a few pixels of the same colour as the water behind it. The 18 m fade
		# means nothing pops — it dissolves into the murk it was already dissolving into.
		mmi.visibility_range_end = REEF_DRAW_M
		mmi.visibility_range_end_margin = REEF_FADE_M
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
		# instance transforms were built in world space; the MultiMesh wants them in
		# the instance's own space
		var inv: Transform3D = mmi.global_transform.affine_inverse()
		for i in range(xf.size()):
			# NB if you are here because get_instance_transform() read back identity:
			# MultiMesh instance data lives in the RenderingServer, and under --headless
			# the dummy renderer drops every write and returns identity to every read.
			# The data is fine; the harness reading it has to run WINDOWED. Measured both
			# ways in one sitting — see docs/AGENT_TRAPS.md.
			var t: Transform3D = xf[i]
			mm.set_instance_transform(i, inv * t)
			mm.set_instance_color(i, b["col"][i])
		b["xf"] = [] as Array
		b["col"] = [] as Array

# ------------------------------------------------------------ snails on the concrete

## THE CLIMBERS (owner brief, s20: "pyramid/glow snails climbing there").
##
## Both species already exist and already know how to be on a wall — BloomFauna.LampSnail
## and BloomFauna.PyramidSnail run FaunaMove.SurfaceCrawler, whose whole design is that
## geometry is the thing an animal travels ON, and whose `basis()` puts the body's +Y on the
## face normal so a snail on the caisson reads as a snail stuck to the caisson. What they
## have never had is anywhere underwater to do it: BloomFauna seeds the lamp snails on the
## pontoon TOPS and the pyramid snails on the topside plate, both on level plating.
##
## bloom_fauna.gd is shared with another live session, so nothing there is touched. Both
## species are spawned from here and the three things a wall crawler needs that a deck
## crawler does not are set on the crawler afterwards — which is safe because _ready() runs
## inside add_child(), so the crawler exists by the time add_child returns.
const BF := preload("res://scripts/world/bloom_fauna.gd")

## Indices are offset well past BloomFauna's own (lamp 0-5, pyramid 0-2). Snail save/restore
## keys the `fed` flag by species+idx, so a collision would silently share state between two
## animals on opposite sides of the rig.
const SNAIL_IDX_LAMP: int = 300
const SNAIL_IDX_PYR: int = 340

## How far a climber may wander above and below the depth it settled at, and how long it
## holds one heading. The crawler's own leash only steers on LEVEL plating (a climbing snail
## is deliberately not dragged sideways halfway up a bulkhead), so on a vertical face there
## is nothing keeping it in its band — this is that.
const SNAIL_RANGE: float = 4.5
const SNAIL_TURN: Array = [8.0, 20.0]

## Where they go. `d` is the fraction down the reachable leg (0 = just under the pontoon
## skirt, 1 = the bottom of the coral band), so the actual Y is derived from the MEASURED
## band rather than typed.
##
## THE DEPTHS ARE WHERE THE REEF IS, and that was corrected by looking. The first pass spread
## these from d 0.16 to 0.72, i.e. y -6.4 to -16.8, and photographed the shallow half as solid
## green: y -6 to -12 on a caisson is the middle of underwater_world's kelp stand (44 tagged
## strands, floor measured at y -12.09), so those snails were real, seated, crawling, and
## completely invisible behind fronds. They now run d 0.44-0.86 — under the kelp floor, in
## among the coral, which is both where a reef grazer belongs and the only band you can
## actually see one in. The lamp snails take the deeper spots (a moon is worth more in the
## dark) and the pyramid snails the shallower.
const SNAIL_SPOTS := [
	# leg index, face normal, offset across the face, depth fraction, species
	[1, Vector3(1, 0, 0), -1.3, 0.46, "pyr"],    # SE leg, outboard: first thing you meet
	[1, Vector3(1, 0, 0), 1.1, 0.62, "lamp"],
	[1, Vector3(0, 0, -1), 0.6, 0.52, "lamp"],
	[1, Vector3(0, 0, -1), -1.7, 0.74, "pyr"],
	[3, Vector3(1, 0, 0), 0.9, 0.48, "pyr"],     # NE leg
	[3, Vector3(1, 0, 0), -1.5, 0.68, "lamp"],
	[3, Vector3(0, 0, 1), 1.4, 0.58, "lamp"],
	[0, Vector3(-1, 0, 0), -0.8, 0.50, "pyr"],   # SW leg
	[0, Vector3(-1, 0, 0), 1.6, 0.80, "lamp"],
	[0, Vector3(0, 0, -1), -1.2, 0.64, "lamp"],
	[2, Vector3(-1, 0, 0), 1.2, 0.44, "pyr"],    # NW leg
	[2, Vector3(0, 0, 1), -0.9, 0.72, "lamp"],
	[2, Vector3(0, 0, 1), 1.5, 0.86, "pyr"],
]

## [{s, lo, hi, t}] — the climbers this file steers. See _process.
var _climbers: Array = []
var _snails_refused: int = 0

## ------------------------------------------------------------ the surface cull
##
## THE REEF IS NOT VISIBLE FROM ABOVE THE WATER, AND IT WAS THE MOST EXPENSIVE THING IN THE
## FRAME THERE. Measured with tests/VantagePerf.tscn (A/B/A, each row against its own noise
## floor and the vantage's null pair): hiding these MultiMeshes recovered **8.97 ms — 27.4% of
## the frame — and 264 draw calls at the `wet_deck` vantage**, which is a standing eye 3.6 m up
## on plating the player fishes from. It is also 2.02 ms at `submerged_deep`, where it is
## legitimately being looked at and stays.
##
## underwater_world's topside cull already covers the decks, but its margin has to stay at 4 m
## because fish just under the surface genuinely do show through (measured — see TOPSIDE_MARGIN
## there). The reef does not: its topmost piece is CRUST_TOP, y -3.4, under an opaque
## `depth_draw_opaque` sea. tests/vantage_perf.gd `--cullproof` measures exactly that, with a
## per-pixel motion mask so a moving swell cannot fake it — at eye heights 2.05, 3.0, 3.6, 4.5
## and 6.0 m over open water, hiding the reef changed 6, 5, 3, 1 and 6 sampled pixels against a
## motion floor of 4, 1, 3, 1 and 2. It is at the noise floor at every height, including the
## lowest one where the whole subtree is measurably NOT.
##
## So the reef gets its own, tighter cull, and the band between them (eye 2.0..4.0 m — the wet
## deck, the pontoon walkway, the tidal ladder) stops paying 4.26 M triangles for coral behind
## opaque water.
##
## Two terms, because either alone is wrong. The FIXED floor is what the proof covers and what
## makes the test stable at a standing eye height. The SWELL term is what stops the reef being
## hidden while the player's head is actually under a crest — in a storm the surface reaches
## y +1.5 or better, so a camera at y 2.4 can be submerged, and a fixed threshold alone would
## blank the reef from inside the water.
const CULL_FLOOR: float = 2.0      ## eye y below this: always drawn (proof's lowest height)
const CULL_OVER_SWELL: float = 0.5 ## ...and always drawn until the eye clears the local swell
const CULL_HYST: float = 0.5       ## deadband, so a camera on the line cannot flip-flop
var _reef_shown: bool = true
## Set false by tests/VantagePerf.tscn to measure what this cull is worth, ON/OFF/ON inside one
## session — the only comparison this machine's thermal drift cannot swamp. Always true in game.
var cull_above_water: bool = true

## Hide the coral (and, as its children, the reef fish and the climbing snails) whenever the
## camera is clear of the water. Costs one Gerstner sample and one compare a frame.
##
## reef_fish.gd early-returns on `is_visible_in_tree()` and its stations are a function of
## their own clocks, so this freezes the fish rather than slowing them — the same contract its
## header already relies on for the topside cull. The snails keep being steered by _process
## below, which visibility does not stop, so a climber cannot drift while it is hidden.
func _cull_above_water() -> void:
	if not cull_above_water:
		if not _reef_shown:
			_reef_shown = true
			visible = true
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp: Vector3 = cam.global_position
	var surf: float = Gyre.swim_line(Vector2(cp.x, cp.z), Gyre.water_time())
	var edge: float = maxf(CULL_FLOOR, surf + CULL_OVER_SWELL)
	var want: bool = cp.y < edge + (CULL_HYST if _reef_shown else 0.0)
	if want == _reef_shown:
		return
	_reef_shown = want
	# The whole node, which is the exact configuration --cullproof measured: coral, the 252 reef
	# fish and the 13 climbing snails together.
	visible = want

func _grow_snails() -> void:
	var lamp_i: int = 0
	var pyr_i: int = 0
	for spec in SNAIL_SPOTS:
		var leg: Vector2 = LEGS[int(spec[0])]
		var n: Vector3 = spec[1]
		var tangent := Vector3(n.z, 0.0, -n.x)
		var y: float = lerpf(CRUST_TOP, BAND_BOTTOM, float(spec[3]))
		var target := Vector3(leg.x, y, leg.y) + n * LEG_HALF + tangent * float(spec[2])
		var hit: Dictionary = _probe(target, n)
		# REFUSED, not faked. _probe falls back to the sonar-measured face when the raycast
		# finds nothing, which is right for a MultiMesh instance (it is only drawn) and wrong
		# for a crawler: a SurfaceCrawler with no collider under its foot has nothing to stick
		# to and would hang in the water re-probing for ever. So a snail is only seeded where
		# a real collider answered.
		if not bool(hit.get("measured", true)) or _blocked(hit["position"]):
			_snails_refused += 1
			continue
		var seat: Vector3 = hit["position"]
		var face: Vector3 = (hit["normal"] as Vector3).normalized()
		var snail: Node3D
		if String(spec[4]) == "lamp":
			snail = BF.LampSnail.new(SNAIL_IDX_LAMP + lamp_i, seat + face * 0.06)
			lamp_i += 1
		else:
			snail = BF.PyramidSnail.new(SNAIL_IDX_PYR + pyr_i, seat + face * 0.06)
			pyr_i += 1
		add_child(snail)                       # _ready() runs INSIDE this call
		snail.global_position = seat + face * 0.06
		_attach_to_wall(snail, face, seat.y)
		_climbers.append({"s": snail, "lo": maxf(seat.y - SNAIL_RANGE, BAND_BOTTOM + 0.4),
			"hi": minf(seat.y + SNAIL_RANGE, CRUST_TOP - 0.2),
			"t": _rng.randf_range(0.5, float(SNAIL_TURN[1]))})
	# Unconditionally ON now: _process also runs the surface cull (see _cull_above_water), which
	# is the reef's largest single saving and must not depend on whether any snail was seated.
	set_process(true)

## Hand the crawler the frame it needs to be ON a vertical face instead of standing on the
## floor: `up` is the concrete's normal, the heading is a tangent IN that face, and the climb
## ceiling is measured from where it started rather than from y = 0 (CLIMB_MAX is "six metres
## above the foothold", and a crawler seeded at y -14 with climb_base still 0 would think it
## had twenty metres of credit).
func _attach_to_wall(snail: Node3D, face: Vector3, y: float) -> void:
	var cr: Object = snail.get("_crawler")
	if cr == null:
		return
	cr.set("up", face)
	cr.set("home", snail.global_position)
	cr.set("y_fallback", y)
	cr.set("climb_base", y)
	cr.set("climbing", true)
	# PyramidSnail re-picks a heading in world XZ every 16-42 s, which projects to PURE
	# SIDEWAYS on a vertical wall — a wall snail would sidle back and forth for ever and
	# never climb. Pushing its timer out of reach hands direction to _process below, which
	# picks in the FACE plane. (LampSnail has no such timer.)
	if snail.has_method("_pick_heading"):
		snail.set("_turn_cd", 1.0e9)
	_aim_climb(snail, cr, _rng.randf_range(0.45, 0.9) * (1.0 if _rng.randf() < 0.6 else -1.0))

## Point the crawler along a heading that lies in its current face and has a real VERTICAL
## component — `vy` is that component, +1 straight up the wall, -1 straight down.
func _aim_climb(snail: Node3D, cr: Object, vy: float) -> void:
	var up_n: Vector3 = cr.get("up")
	if not up_n.is_finite() or up_n.length() < 0.5:
		return
	up_n = up_n.normalized()
	# world up, projected into the face — on a vertical caisson this is just Vector3.UP
	var vert: Vector3 = Vector3.UP - up_n * up_n.y
	if vert.length() < 0.05:
		return
	vert = vert.normalized()
	var side: Vector3 = up_n.cross(vert).normalized()
	vy = clampf(vy, -0.96, 0.96)
	var across: float = sqrt(maxf(0.0, 1.0 - vy * vy)) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var h: Vector3 = (vert * vy + side * across)
	if h.length() < 0.01:
		return
	cr.set("heading", h.normalized())
	if vy > 0.0:
		cr.set("climb_base", snail.global_position.y)

## Steer the climbers. Deliberately tiny — it does two things the crawler cannot do for
## itself on a vertical face, and nothing else: keep each snail inside the depth band it
## settled in, and hand it a fresh heading that actually goes up or down the wall every ten
## seconds or so instead of only across it.
func _process(delta: float) -> void:
	_cull_above_water()
	var alive: Array = []
	for c in _climbers:
		var s: Node3D = c["s"]
		if not is_instance_valid(s):
			continue
		alive.append(c)
		var cr: Object = s.get("_crawler")
		# Being carried by the player, or set down somewhere else entirely: hands off. The
		# species' own snail_carry/reseat owns the animal then.
		if cr == null or s.get("_carried_by") != null:
			continue
		var up_n: Vector3 = cr.get("up")
		if not up_n.is_finite() or absf(up_n.y) > 0.7:
			continue                            # it has crawled onto level plating: its own
		c["t"] = float(c["t"]) - delta
		var y: float = s.global_position.y
		var h: Vector3 = cr.get("heading")
		if y > float(c["hi"]) and h.y > 0.0:
			_aim_climb(s, cr, -_rng.randf_range(0.5, 0.95))
			c["t"] = _rng.randf_range(SNAIL_TURN[0], SNAIL_TURN[1])
		elif y < float(c["lo"]) and h.y < 0.0:
			_aim_climb(s, cr, _rng.randf_range(0.5, 0.95))
			c["t"] = _rng.randf_range(SNAIL_TURN[0], SNAIL_TURN[1])
		elif float(c["t"]) <= 0.0:
			_aim_climb(s, cr, _rng.randf_range(-0.9, 0.9))
			c["t"] = _rng.randf_range(SNAIL_TURN[0], SNAIL_TURN[1])
	_climbers = alive
