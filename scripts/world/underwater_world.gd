extends Node3D
## The ocean below the wave line: the rig's legs keep going down, kelp sways on
## the moorings, marine snow drifts, bubbles rise off the steel — and the fish
## you can actually catch swim their real depth bands (schools are spawned from
## data/fish.json, so what you SEE under the surface is what's biting above it).
## Best appreciated in fly mode or falling in; diving proper is a later phase.

const FISH := preload("res://scripts/world/fish_table.gd")
const ANIM := preload("res://scripts/world/creature_anim.gd")
const SEABED := preload("res://scripts/world/seabed.gd")
const FX := preload("res://scripts/world/underwater_fx.gd")
const MOVE := preload("res://scripts/world/fauna_move.gd")
## Preloaded by PATH, not by its class_name — the global class cache lags for a new file.
const AIB := preload("res://scripts/world/ai_budget.gd")

const LEGS := [Vector3(-22, 0, -12), Vector3(22, 0, -12), Vector3(-22, 0, 12), Vector3(22, 0, 12)]
const DEPTH_BAND := {"surface": -1.2, "mid": -4.5, "deep": -9.5}

## TWO PODS PER SPECIES (2026-07-26, owner: "there should be around double the total
## amount of fish shown, more in the open water around"). The ocean used to be stocked
## with exactly one shoal per species, wandering a ±24 x ±28 m box — the rig's own
## footprint plus a little. Swim out past the moorings and the sea was empty.
##
## Inflating the single shoal would only have made a denser BALL in the same water, which
## is not what was asked for, so every species now runs a SECOND pod on a wider, slower,
## deeper circuit. That doubles the population and puts the whole of the added half in the
## open water the owner was pointing at. The counts themselves stay in data/fish.json: how
## many fish are in a shoal is a fact about the species; how much ocean we stock is not.
const SCHOOL_PODS: int = 2
## Per pod: how far its slow centre-wander carries it in x/z, how fast that wander runs,
## and how far below the species' own depth band it sits. Pod 0 IS the historical near-rig
## shoal, numbers unchanged. Pod 1 is the new open-water half — wider, slower (a shoal that
## far out should read as barely moving when you watch it from the rim) and a few metres
## down, so the added fish fill the water COLUMN as well as the plan view.
const POD_SPREAD: Array[Vector2] = [Vector2(24.0, 28.0), Vector2(41.0, 46.0)]
const POD_RATES: Array[Vector2] = [Vector2(0.050, 0.041), Vector2(0.029, 0.023)]
const POD_DROP: Array[float] = [0.0, 3.4]

## HOW FAR A SHOAL FISH IS WORTH DRAWING.
##
## render_budget.gd derives a visibility range from an object's size for everything it
## sweeps, and school fish were taking the generic one: size * 110 m, so a 0.4 m sprat was
## still being submitted at 46 m and a 1.1 m cod at 121. Above water that rule is right.
## Below it, it is not — the MEDIUM has already eaten the fish long before then.
## underwater_fx grades fog from 0.028/m in the shallows to past 0.2/m in the deep, and at
## 0.028 a body 60 m off is down to under a fifth of its contrast; a hand-sized fish at
## that range is a smudge on fog-coloured fog. These meshes are the most expensive thing
## in the water (the generated species .glbs run tens of thousands of triangles each), so
## doubling the stocking without touching this would have doubled the far-field cost for
## shapes nobody can resolve. Every fish now carries its OWN range, set at spawn at roughly
## 0.55x the generic rule. render_budget skips any mesh that already has a range, so this
## wins and the size-derived rule never overwrites it.
const FISH_RANGE_PER_M: float = 62.0
const FISH_RANGE_MIN: float = 20.0
const FISH_RANGE_MAX: float = 62.0
const FISH_RANGE_FADE: float = 0.18

## HOW A SHOAL FISH MOVES (2026-07-26, owner: fish should move "how the jellyfish move").
##
## The jelly (bloom_fauna.JellyDrifter) reads well for three reasons, and the bell pulse is
## none of them: its position is a slow MULTI-OCTAVE function of time so it never travels
## in a straight line, every individual carries its own phase offset so no two are ever in
## step, and nothing about it happens instantly. The old shoal had none of that. Every
## member was pinned to an evenly spaced slot on one shared ring, all turning at the same
## angular rate, with its facing recomputed from scratch out of the last frame's
## displacement — so a school read as a carousel of identical fish snapping their heads
## around, and a radius that breathed on a sine made the whole ring pump in lockstep.
##
## The fish now get the jelly's QUALITIES without its pulse, because a fish is not a bell:
## the ring is a TARGET the fish eases toward rather than a rail it is welded to, the
## target itself weaves on its own octaves, each member carries a random phase AND a random
## speed, and the heading is a REMEMBERED value eased onto the direction of travel instead
## of a fresh look_at every frame. A fish also noses into its own climb, the way the
## glider ray does. Body-wave phase is randomised per member too (it used to be i * 0.5,
## which is a marching band).
const FISH_EASE: float = 2.2     ## how hard a fish is drawn toward its wander target (1/s)
const FISH_TURN: float = 2.4     ## how fast the remembered heading eases onto the new one (1/s)
const FISH_PITCH: float = 0.42   ## how much of its own vertical speed a fish noses into

var _kelp: Array[Node3D] = []
## Parallel to _kelp, so the per-frame sway is two array reads instead of two get_meta().
var _kelp_sway: PackedFloat32Array = PackedFloat32Array()
var _kelp_phase: PackedFloat32Array = PackedFloat32Array()
## One entry per POD, not per species — see SCHOOL_PODS.
## [{root, fish[], def, id, pod, band_y, size, spread, rates, radius, ph[], spd[], head[],
##   climb[], warm, t}]. The four parallel arrays are the per-member swim state; `warm` is
## false until the pod's first live frame has seated its fish.
var _schools: Array = []
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _snow: GPUParticles3D          # marine snow, storm/depth-reactive in _process
var _storm: Node = null
## The camera position, taken once a frame by _cull_topside and reused by _pod_due.
## NOT `_eye` — that name is already the fish silhouette's eye-material helper below.
var _cam_eye: Vector3 = Vector3.ZERO
var _cam_eye_ok: bool = false

func _ready() -> void:
	_rng.seed = 7411
	_kelp_forest()
	_leg_reef_growth()
	_marine_snow()
	_bubble_vents()
	_mooring_chains()
	_spawn_schools()
	_rig_underlights()
	_deep_giants()
	_open_water_rays()
	# The sculpted sea floor + wreck field + reef communities, and the visibility /
	# light FX (Snell window, shafts, caustics, depth-graded fog). Both self-contain,
	# so wiring them here keeps main.gd (owned by the waves/sky builder) untouched.
	add_child(SEABED.new())
	add_child(FX.new())
	# Nothing below the wave line casts a directional shadow: it is all under 20+ m of
	# water the sunlight never reaches usefully, but Godot was still drawing every one of
	# these meshes (seabed, riprap, wreck field, reef, kelp, chains) into each shadow
	# split. Switching the whole subtree off is the single cheapest thing in this file.
	_no_shadows(self)

## Recursively stop a subtree casting shadows.
func _no_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		var g: GeometryInstance3D = n
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for c in n.get_children():
		_no_shadows(c)

# ---------------------------------------------------------------- structure

## The caissons are ONE casting each, authored in rig_builder._build_structure() and run
## from the deck rim down to y -23 in a single box. There used to be a second set of boxes
## here extending them below -3.8; see the comment on that _box call for why merging them
## was the only thing that removed the hard horizontal seam under every leg.

func _kelp_forest() -> void:
	var kelp_mat := StandardMaterial3D.new()
	kelp_mat.albedo_color = Color(0.14, 0.38, 0.28)
	kelp_mat.roughness = 0.9
	var tip_mat := StandardMaterial3D.new()
	tip_mat.albedo_color = Color(0.2, 0.6, 0.45)
	tip_mat.emission_enabled = true
	tip_mat.emission = Color(0.2, 0.9, 0.85)
	tip_mat.emission_energy_multiplier = 0.25
	for leg in LEGS:
		# Denser stand — 6 procedural strands read thin against a 6 m caisson; a real kelp
		# forest is a wall you swim through, not a scatter you swim past.
		for i in range(11):
			var a: float = _rng.randf_range(0, TAU)
			var r: float = _rng.randf_range(3.2, 6.0)
			var base := Vector3(leg.x + cos(a) * r, -12.0, leg.z + sin(a) * r)
			var strand := Node3D.new()
			add_child(strand)
			strand.position = base
			var h: float = _rng.randf_range(7.0, 11.0)
			var segs: int = 4
			for s in range(segs):
				var blade := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.22 - s * 0.03, h / segs + 0.15, 0.05)
				bm.material = tip_mat if s == segs - 1 else kelp_mat
				blade.mesh = bm
				strand.add_child(blade)
				blade.position = Vector3(0, (s + 0.5) * h / segs, 0)
				blade.rotation.y = _rng.randf_range(0, TAU)
			# The metas stay: leg_reef._vegetation_floor() identifies a kelp strand by
			# `has_meta("sway")` and measures the reef band top off it. But the SWAY LOOP
			# must not read them — two get_meta() string lookups per strand per frame is 88
			# dictionary probes a frame to fetch two numbers that never change after build.
			var sway_k: float = _rng.randf_range(0.8, 1.4)
			var phase_k: float = _rng.randf_range(0, TAU)
			strand.set_meta("sway", sway_k)
			strand.set_meta("phase", phase_k)
			_kelp.append(strand)
			_kelp_sway.append(sway_k)
			_kelp_phase.append(phase_k)
		# A few real GENERATED kelp fronds (glow_kelp.glb) mixed in among the procedural
		# strands — same holdfast ring, a richer silhouette than boxes alone can give.
		for i in range(4):
			var a2: float = _rng.randf_range(0, TAU)
			var r2: float = _rng.randf_range(3.5, 6.2)
			var pos := Vector3(leg.x + cos(a2) * r2, -12.0, leg.z + sin(a2) * r2)
			var host := Node3D.new()
			add_child(host)
			host.position = pos
			host.rotation.y = _rng.randf_range(0, TAU)
			var gen: Dictionary = ANIM.attach(host, "res://assets/models/fauna/glow_kelp/glow_kelp.glb",
				_rng.randf_range(6.0, 9.5), ANIM.Mode.SWAY, 0.1, _rng.randf_range(0.4, 0.7),
				Color(0.22, 0.85, 0.7), _rng.randf() * TAU)
			if gen.is_empty():
				host.queue_free()
				continue
			ANIM.drive(gen["mats"], 0.55, 0.3)
			BloomFauna.ground_model(host, gen["model"])

## Reef growth encrusting the four legs themselves — anemones, sponge clusters, tube
## worms, urchins — the years of Bloom colonisation the rig would actually carry, right
## where a diving player spends most of their time. The wreck field / reef ridge
## (reef_detail.gd, reef_life.gd) put the deep, elaborate reef community far south of the
## rig at z -30..-60; this is the CLOSE, immediate life on the steel itself, in the
## reachable band (roughly y -2..-11, well inside the 13 m death line).
func _leg_reef_growth() -> void:
	# The growth clinging to the caisson legs is most of what a player actually swims past
	# up close, so it earns the widest species spread of anything underwater. Five more
	# reef species join the original four — all decorative sessile fauna already modelled
	# for the (unreachable) seabed reef in reef_life.gd, reused here where the player can
	# actually see them. CIRRI suits the feather star's feeding sweep the same way it
	# suited the tube worms; the coral fan and sea grass sway like the anemone; the brain
	# coral and seastar get the same slow BREATHE swell as the sponge.
	const SPECIES := [
		["bloom_anemone", 0.4, 0.9, ANIM.Mode.SWAY, 0.08, Color(0.95, 0.45, 0.7)],
		["bloom_sponge_cluster", 0.5, 1.1, ANIM.Mode.BREATHE, 0.03, Color(1.0, 0.62, 0.22)],
		["bloom_tube_worms", 0.5, 0.9, ANIM.Mode.CIRRI, 0.05, Color(0.25, 0.95, 0.88)],
		["bloom_urchin", 0.3, 0.55, ANIM.Mode.BREATHE, 0.04, Color(0.75, 0.55, 1.0)],
		["bloom_coral_fan", 0.6, 1.3, ANIM.Mode.SWAY, 0.05, Color(1.0, 0.5, 0.55)],
		["bloom_sea_grass", 0.5, 1.0, ANIM.Mode.SWAY, 0.10, Color(0.35, 0.85, 0.4)],
		["bloom_feather_star", 0.35, 0.7, ANIM.Mode.CIRRI, 0.06, Color(0.9, 0.35, 0.6)],
		["bloom_seastar", 0.3, 0.6, ANIM.Mode.BREATHE, 0.02, Color(0.95, 0.55, 0.2)],
		["bloom_brain_coral", 0.5, 1.0, ANIM.Mode.BREATHE, 0.02, Color(0.6, 0.75, 0.4)],
	]
	for leg in LEGS:
		for i in range(20):
			var spec: Array = SPECIES[_rng.randi() % SPECIES.size()]
			var slug: String = spec[0]
			var size: float = _rng.randf_range(spec[1], spec[2])
			var mode: int = spec[3]
			var amp: float = spec[4]
			var glow: Color = spec[5]
			# Pick a face of the 6 m square caisson and a reachable depth, then stand the
			# growth just proud of that face (a small standoff so it doesn't clip the concrete).
			var side: float = [-1.0, 1.0][_rng.randi_range(0, 1)]
			var along_x: bool = _rng.randf() < 0.5
			var along: float = _rng.randf_range(-2.6, 2.6)
			var depth_y: float = _rng.randf_range(-2.5, -10.5)
			var standoff: float = 3.05 + size * 0.15
			var pos: Vector3
			if along_x:
				pos = Vector3(leg.x + along, depth_y, leg.z + side * standoff)
			else:
				pos = Vector3(leg.x + side * standoff, depth_y, leg.z + along)
			var host := Node3D.new()
			add_child(host)
			host.global_position = pos
			host.rotation.y = _rng.randf_range(0.0, TAU)
			var gen: Dictionary = ANIM.attach(host, "res://assets/models/fauna/%s/%s.glb" % [slug, slug],
				size, mode, amp, _rng.randf_range(0.3, 0.6), glow, _rng.randf() * TAU)
			if gen.is_empty():
				host.queue_free()
				continue
			ANIM.drive(gen["mats"], 0.5, _rng.randf_range(0.2, 0.4))
			BloomFauna.ground_model(host, gen["model"])

## Work floodlights bolted under the pontoons, aimed straight down into the deep — the
## rig's own light story continuing below the waterline. Each is a small emissive fixture
## plus a wide shadowless SpotLight3D (cheap on gl_compatibility). They carve cones a few
## tens of metres down into water that now fades to black long before the -92 floor, and
## the deep giants (below) cruise through exactly these cones, so from the surface you see
## huge lit silhouettes slide in and out of the dark.
func _rig_underlights() -> void:
	# Pontoons: boxes at (0, -1.05, ±12), 56 x 4 x 8 — undersides at y -3.05.
	for spec in [Vector2(-14.0, -12.0), Vector2(14.0, -12.0),
			Vector2(-14.0, 12.0), Vector2(14.0, 12.0)]:
		var lamp := SpotLight3D.new()
		lamp.light_color = Color(0.62, 0.85, 0.95)
		lamp.light_energy = 3.4
		lamp.spot_range = 42.0
		lamp.spot_angle = 38.0
		lamp.spot_attenuation = 1.1
		lamp.shadow_enabled = false
		add_child(lamp)
		lamp.position = Vector3(spec.x, -3.15, spec.y)
		lamp.rotation.x = -PI / 2.0   # a SpotLight fires along -Z; pitch it straight down
		# The housing: a small dark can with a glowing lens face, so the beam has a source.
		var can := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.24
		cm.bottom_radius = 0.3
		cm.height = 0.35
		cm.material = MatLib.dark_metal()
		can.mesh = cm
		add_child(can)
		can.position = Vector3(spec.x, -2.95, spec.y)
		var lens := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.22
		lm.bottom_radius = 0.22
		lm.height = 0.04
		lm.material = MatLib.glowing(Color(0.75, 0.92, 1.0), 2.4)
		lens.mesh = lm
		add_child(lens)
		lens.position = Vector3(spec.x, -3.14, spec.y)

## The BIG ones. Barrel groupers the size of doors and a fathom halibut like a lost
## tabletop, patrolling slow circuits 15-30 m down — deep enough that the water has
## already gone dark around them, shallow enough that the pontoon floodlights rake
## across their backs as they pass under the rig. From the deck or the shallows you
## mostly get moving silhouettes at the edge of the light, which is the point.
## THE BIG GROUPER'S HOME (2026-07-26, owner: "the huge grouper should be a bit deeper,
## and home base closer to the leg of the rig"). Every deep giant used to orbit the rig's
## dead CENTRE, because DeepGiant's circle was hardcoded around the world origin — so the
## one animal a player goes looking for had no address at all, just a lap of open water
## somewhere under the middle of the structure. A grouper does not live like that: it holds
## a territory against structure and keeps coming back to it.
##
## The SE caisson is the leg to hold. It is the one the tidal ladder and the deep-drop rig
## are on, so "go down the SE leg and look for the big one" becomes something a player can
## actually act on. This sits just off its east face — the leg is a 6 m square about
## (22, 12), so its face is at x 25 — and the two giants anchored here swim well below the
## steel: the caisson bottoms out at y -23 (rig_builder), and these are at -26 and -36, so
## even a tight orbit around the leg's own footprint can never put a 4 m fish inside it.
const LEG_HOME := Vector3(24.0, 0.0, 12.0)

## THE HUGE GROUPER (2026-07-27, owner: "20% smaller, 40 m deeper, and give it a proper
## slow lap of the leg it lives on"). This is the LEVIATHAN — the game's one landmark
## specimen, the colossal grouper every other fish down here is measured against — not the
## 4.4 m resident, which is only "the huge one" to a player who never met this.
##
##   AXIS, not a neighbour point. LEG_HOME is a point just off the SE caisson's east face
##   and it was fine for a drifting circuit, but "orbit the pillar" means orbiting the
##   PILLAR: the centre below is the caisson's own axis (LEGS[3]), so the animal actually
##   laps the steel instead of laps a point beside it. Written out rather than indexed off
##   LEGS so it reads at the call site.
##   RADIUS. The caisson is a 6 m square (CAISSON_HALF 3 in seabed.gd), so its corners
##   stand 4.25 m off the axis. A ~14 m fish held tangent to a 12 m circle bows its
##   mid-body in to r*cos(asin(L/2r)) ~ 9.4 m — still 5 m clear of the corner — while a
##   9 m orbit would put the belly inside the steel on every pass.
##   DEPTH. -36 - 40 = -76. The caissons run in one casting to -92 (seabed.CAISSON_BOTTOM),
##   so the pillar is still there to orbit at this depth, and the mudline out at r 12 sits
##   around -91..-95, so a 1.1 m bob never touches bottom. Far below the 13 m death line
##   and far below the lit band underwater_fx grades (-17..-29): this is a shape you find
##   with a light, or never.
const LEG_PILLAR := Vector3(22.0, 0.0, 12.0)   # SE caisson axis == LEGS[3]
const LEVIATHAN_SCALE: float = 0.8      # 20% smaller: 16-19 m becomes 12.8-15.2 m
const LEVIATHAN_Y: float = -76.0        # was -36.0
const LEVIATHAN_R: float = 12.0         # orbit radius about the pillar axis
const LEVIATHAN_LAP_SEC: float = 58.0   # one full circuit, ~1.3 m/s: 0.09 body-lengths/s

func _deep_giants() -> void:
	# The always-present residents on slow circuits under the rig: three original plus a
	# second halibut and a lesser grouper on the shallow edge, so there is a spread of BIG
	# shapes at different depths to catch at the edge of the light. (mantle_ray is kept OUT
	# of this ambient roster on purpose — it is the special glowing night-bloom visitor
	# elsewhere in the game, discovered as a one-off event; making it a routine deep
	# patroller here would cheapen that encounter.)
	var specs := [
		# [slug, size_m, band_y, orbit_r, rate, phase, home]
		["fish_barrel_grouper", 3.6, -17.0, 13.0, 0.05, 0.0, Vector3.ZERO],
		# THE BIG RESIDENT GROUPER — the one a player without a Leviathan roll thinks of as
		# "the huge one". Anchored on the SE leg (see LEG_HOME) and dropped from -24 to -26:
		# a bit deeper, but still inside the pontoon floodlights' 42 m throw, so it is deeper
		# WATER and not simply gone.
		["fish_barrel_grouper", 4.4, -26.0, 9.0, 0.038, 2.4, LEG_HOME],
		["fish_fathom_halibut", 3.2, -29.0, 11.0, 0.045, 4.2, Vector3.ZERO],
		["fish_fathom_halibut", 4.1, -20.0, 15.0, 0.033, 1.1, Vector3.ZERO],  # a second, larger halibut
		["fish_barrel_grouper", 2.8, -14.0, 9.0, 0.060, 5.0, Vector3.ZERO],   # a lesser one on the shallow edge
		["fish_barrel_grouper", 3.2, -12.0, 19.0, 0.042, 3.3, Vector3.ZERO],  # shallow enough to read clearly
		["fish_fathom_halibut", 3.6, -16.0, 21.0, 0.030, 0.7, Vector3.ZERO],  # wide slow lap, semi-visible
		# THE COELACANTH (owner-supplied mesh, 2026-07-26). Deeper than every resident but
		# the -29 halibut, and the one deep animal here that is NOT a slab: 1.8 m, half the
		# grouper, sculling on its lobed fins (creature_anim Mode.SCULL, applied through
		# MOTION_OVERRIDES so this spec needs no new column). -21 puts it 8 m below the
		# death line — genuinely out of reach — inside the -17..-29 band underwater_fx lights
		# as shapes at the edge of the dark, and on the deep rig's own 20 m drop line
		# (fish.json drop_m 20): you fish it at 20 m and you can see it at 21.
		# Centre-anchored, NOT on the leg: at -21 it rides ABOVE the caissons' -23 bottom, so
		# a LEG_HOME here would swim it through steel. Radius 12 keeps 7 m clear of the legs.
		# 0.028 rad/s is ~0.2 body-lengths a second — a hover, slower than anything else down
		# there, which is what a coelacanth actually does.
		["fish_coelacanth", 1.8, -21.0, 12.0, 0.028, 1.6, Vector3.ZERO],
	]
	for s in specs:
		# Size jitter so no two runs stamp the identical fish.
		var sz: float = float(s[1]) * _rng.randf_range(0.9, 1.15)
		var host := DeepGiant.new(sz, s[2], s[3], s[4], s[5], s[6])
		host.slug = s[0]
		add_child(host)
	# THE LEVIATHAN. A rare colossal grouper — the biggest animal in the sea, a slow shape
	# the size of the escape pod itself — patrolling the deep dark below the death line. It
	# is NOT on every dive: seeing one is meant to be an event, so ~45% of playthroughs get
	# one. Since 2026-07-27 it is 20% smaller, 40 m deeper (-76) and running a true circular
	# patrol about the SE caisson's own axis rather than a drifting circuit — see LEG_PILLAR
	# and the PillarPatrol class for the numbers and why each one is what it is.
	#
	# THE ROLL GETS ITS OWN RANDOM STREAM (2026-07-26). It used to be drawn from the shared
	# _rng, which meant the biggest animal in the game was decided by however many draws
	# every spawner ABOVE it in _ready happened to consume. Doubling the schools added
	# ~1,500 draws to _spawn_schools, that shifted this one draw from 0.16 to past 0.45,
	# and an 18 m grouper silently vanished from the world without a line of leviathan code
	# being touched — found only because the giant was counted before and after. Seeded off
	# the same world seed, so the roll is still the fixed, reproducible one this build has
	# always had; it just cannot be flipped from a distance any more.
	var lev_rng := RandomNumberGenerator.new()
	lev_rng.seed = 7411
	if lev_rng.randf() < 0.45:
		# The two draws below are kept in their original ORDER and count — the size roll then
		# the phase roll — so this build's fixed leviathan is still the same fish it always
		# was, only smaller, deeper and on a tighter lap.
		var leviathan := PillarPatrol.new(lev_rng.randf_range(16.0, 19.0) * LEVIATHAN_SCALE,
			LEVIATHAN_Y, LEVIATHAN_R, TAU / LEVIATHAN_LAP_SEC, lev_rng.randf() * TAU, LEG_PILLAR)
		leviathan.slug = "fish_barrel_grouper"
		add_child(leviathan)

## OPEN-WATER RAYS. Until now the only ray in the game was the rare aerial night flyover
## (bloom_fauna.MantleRay, y38-50) — a player diving or leaning over the rim never met
## one. These are real underwater rays: broad slow gliders banking around the rig.
## Three of them, spread and phased so one is almost always somewhere in view. Kept off
## the ambient DEEP roster on purpose — the deep dark stays the groupers' domain.
##
## OWNER CALL 2026-07-29: dropped 25 m from the original -7..-11 shallow band. They are
## now a thing you dive FOR rather than something you notice from the deck edge, sitting
## below the coral band (BAND_BOTTOM -22) in open water well clear of the -92 seabed and
## of the caisson footings.
##
## OWNER CALL 2026-07-30: "stagger ray height in a range to how deep they are now, up to 15ft
## higher depending on randomness". The three band_y values below are therefore the FLOOR of
## each animal's range rather than the plane it cruises: every ray draws its own lift in
## [0, RAY_LIFT_MAX] once, at spawn, and keeps it for the session, on top of the +-3 m depth
## wander it already carries.
##
## THE DRAW IS STRATIFIED BY DEPTH RANK, and that is not decoration. Three independent uniform
## draws collapsed the three bands from a 4.0 m spread onto 2.1 m on the first seed tried
## (-32.49 / -31.59 / -30.40) — less staggered than before the change, which is the opposite
## of the ask. So the SHALLOWEST animal draws from the top third of the range and the deepest
## from the bottom third, randomised inside its own third: the stagger is guaranteed and the
## randomness is real. Fixed seed, so a session is reproducible and the numbers reportable.
##
## THE CEILING IS DERIVED AND IT IS NOT THE CAISSONS. Worth writing down because the obvious
## assumption is wrong: rig_builder makes each leg ONE 6 x 109 m casting from y +17 to
## Seabed.CAISSON_BOTTOM (-92), so there is no depth at which a ray gets "under" the concrete
## and the horizontal orbit is the only thing that has ever kept it clear. What a lift can
## actually run into is the REEF COMMUNITY overhead: leg_reef's coral band bottoms at y -22
## and the deepest tropical station sits at -21.4. So the cap is that band, with room for the
## wander and for the wingtip a hard bank throws above the centre line (a ray rolls to
## BANK_MAX ~69 degrees, i.e. up to half a span).
const RAY_LIFT_MAX: float = 4.572   ## 15 ft
## Ceiling for the TOP of a ray's swept volume: 2 m under leg_reef's measured coral band
## bottom (y -22.00) and 2.6 m under the deepest tropical fish station (-21.4).
const RAY_TOP_LIMIT: float = -24.0
## The depth wander each ray already carries about its band, metres (GliderRay._process).
const RAY_WANDER: float = 3.0

func _open_water_rays() -> void:
	var specs := [
		# [span_m, band_y, orbit_r, rate, phase]
		[5.5, -33.5, 20.0, 0.055, 0.0],
		[6.4, -36.0, 25.0, 0.040, 2.1],
		[4.8, -32.0, 16.0, 0.070, 4.3],
	]
	# Depth rank: 0 = deepest floor, so `rank` indexes the stratum of the lift range.
	var order: Array[int] = []
	for i in range(specs.size()):
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return float(specs[a][1]) < float(specs[b][1]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for rank in range(order.size()):
		var spec: Array = specs[order[rank]]
		var span: float = float(spec[0])
		var floor_y: float = float(spec[1])
		var lo: float = RAY_LIFT_MAX * float(rank) / float(specs.size())
		var hi: float = RAY_LIFT_MAX * float(rank + 1) / float(specs.size())
		# Derived cap: band + lift + wander + a banked half-span may not reach RAY_TOP_LIMIT.
		var headroom: float = RAY_TOP_LIMIT - (floor_y + RAY_WANDER + span * 0.5)
		var lift: float = clampf(rng.randf_range(lo, hi), 0.0, maxf(headroom, 0.0))
		var ray := GliderRay.new(span, floor_y + lift, float(spec[2]),
			float(spec[3]), float(spec[4]))
		add_child(ray)
		print("[ray] floor %.1f + lift %.2f -> band %.2f  (span %.1f, stratum %.2f..%.2f, "
			% [floor_y, lift, floor_y + lift, span, lo, hi]
			+ "wander top %.2f, wingtip top %.2f, headroom %.2f)"
			% [floor_y + lift + RAY_WANDER, floor_y + lift + RAY_WANDER + span * 0.5, headroom])

## A mantle ray gliding open water around the rig. Wing-beat animation (Mode.WING), the
## same glb the aerial night-visitor uses, living down where it can be watched.
##
## MOVEMENT MODEL (2026-07-25: THE BANK NOW FLIES THE ANIMAL). Two rewrites ago the ray
## tracked a flat circle at a fixed 23° lean — it never swam level. The last pass fixed
## that by measuring how hard the heading was changing and rolling to match, which read
## better but still had the causation backwards: the path was decided first and the wings
## were a lagging readout of it, so a banked ray was as likely to be sliding sideways
## through a straight as carving. A real batoid — like an aircraft — does the opposite.
## It ROLLS, and the roll is what bends the path.
##
## So the bank is now the STATE and the heading is the consequence: a lazy multi-octave
## weave plus a soft orbit tether ask for a bank, the wings take their own time coming over
## (BANK_RESP), and the heading is then integrated straight out of the roll through the
## coordinated-turn law, turn = TURN_PER_BANK * tan(roll). Attitude and path cannot
## disagree any more — level IS straight, banked IS an arc, by construction, and the harder
## it is over the tighter the arc. Pitch follows its own gentle climb/dive. Holding a 20 m
## orbit needs only ~15° of lean, so the weave is what puts the drama in. The tether and a
## hard radial clamp keep the span clear of the caissons (legs at ±22 / ±12); orbit radii
## 16-25 as before.
class GliderRay extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	const MODEL := "res://assets/models/fauna/mantle_ray/mantle_ray.glb"
	# --- swim tuning (dial the drama here) --------------------------------------------
	const TURN_RATE_MAX: float = 0.55   ## rad/s ceiling on heading change — caps how tight
	## The coordinated turn. rad/s of heading change per unit of tan(roll): at BANK_MAX it
	## comes out at the TURN_RATE_MAX ceiling, and at the ~15° the orbit itself asks for it
	## gives the 0.055 rad/s that holds a 20 m circle. This one number IS the coupling.
	const TURN_PER_BANK: float = 0.21
	const BANK_MAX: float = 1.2         ## ~69°: wings well past vertical on the deep banks
	const BANK_RESP: float = 2.0        ## how fast the roll eases toward its target
	## How much bank the orbit tether asks for per radian of heading error, and the ceiling
	## on that ask — the tether may lean the animal back toward its circle, but it may never
	## pin it over: the weave has to stay the thing you notice.
	const TETHER_BANK: float = 0.9
	const TETHER_BANK_MAX: float = 0.6
	const WING_HZ: float = 0.42         ## wing-beat frequency, SET ONCE — never per frame
	const PITCH_LOOK: float = 0.55      ## how much it noses toward its climb/dive
	const RADIAL_HOLD: float = 0.06     ## gentle pull back toward the orbit radius
	const RADIAL_CLAMP: float = 2.6     ## hard cap on how far off the orbit it may stray (m)
	var _span: float
	var _band_y: float
	var _r: float
	var _rate: float
	var _ph: float
	var _t: float = 0.0
	var _mats: Array = []
	var _heading: float = 0.0    ## yaw of travel, integrated (not derived from a fixed circle)
	var _speed: float = 1.0      ## lazy glide speed, m/s
	var _dir: float = 1.0        ## orbit sense: +1 CCW, -1 CW
	var _depth: float = 0.0
	var _prev_depth: float = 0.0
	var _roll: float = 0.0           ## THE bank. +ve = starboard wing up = leaning into a left turn
	## The turn the current bank is generating, rad/s. No longer a filtered measurement of
	## the path (there is nothing left to measure — the roll dictates it), but it keeps the
	## name because tests/ray_roll.gd finds the rays by it.
	var _turn_smooth: float = 0.0
	var _ai_acc: float = 0.0

	func _init(span: float, band_y: float, r: float, rate: float, ph: float) -> void:
		_span = span
		_band_y = band_y
		_r = r
		_rate = rate
		_ph = ph

	func _ready() -> void:
		var gen: Dictionary = ANIM.attach(self, MODEL, _span, ANIM.Mode.WING,
			0.14, WING_HZ, Color(0.3, 0.55, 0.6), _ph)
		if gen.is_empty():
			queue_free()
			return
		_mats = gen["mats"]
		# SET THE WING-BEAT ONCE AND NEVER TOUCH IT AGAIN. The motion shader computes
		# `t = TIME * rate + phase`, so rate is a TIME MULTIPLIER, not a speed dial: writing
		# a new rate at second T teleports the wave phase by T * delta_rate. At T=100s even a
		# 0.01 change jumps a full cycle, so re-driving `rate` every frame (which an earlier
		# pass did, to beat harder through banks) made the wings snap to a random position
		# every single frame — read in-game as violent glitching and frantic over-fast
		# flapping. The wing-beat is now constant and the shader runs free off TIME, which is
		# also why it costs nothing per frame. Only ever call drive() on a STATE CHANGE.
		ANIM.drive(_mats, WING_HZ, 0.05)   # slow wing-beat, faint sheen — not a lantern
		_t = _ph * 20.0
		# Keep the original pacing (tangential speed ~= rate*radius), floored so a big slow
		# orbit still glides at a believable clip rather than crawling.
		_speed = maxf(_rate * _r, 0.9)
		_dir = 1.0 if fmod(_ph, TAU) < PI else -1.0   # spread the three rays both ways round
		_heading = _ph
		_depth = _band_y
		_prev_depth = _band_y
		global_position = Vector3(cos(_ph) * _r, _band_y, sin(_ph) * _r)

	func _process(delta: float) -> void:
		# DECIMATED (scripts/world/ai_budget.gd). This is the most expensive per-frame body in
		# the file — a coordinated-turn integration, a look_at and a local roll — and for most
		# of a session it runs behind a hidden flag, because the whole underwater world is
		# culled while the camera is topside. AiBudget hands back every skipped frame's delta,
		# so the bank integration, the heading and the glide speed are unchanged; the roll is
		# eased with `clampf(delta * BANK_RESP, 0, 1)` already, which is stable at any step.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_t += delta
		var pos: Vector3 = global_position
		# --- depth: a slow independent vertical wander within the band ---------------------
		_prev_depth = _depth
		var target_depth: float = _band_y + sin(_t * 0.06 + _ph) * 2.0 + sin(_t * 0.021 + _ph * 1.7) * 1.0
		_depth = lerpf(_depth, target_depth, clampf(delta * 0.6, 0.0, 1.0))
		# --- steering: the two things that ask for a BANK ----------------------------------
		# 1. THE WEAVE. A lazy multi-octave roll wander — the ray leans left, comes back
		#    through level, leans right. This is the animal's own idea and it is what turns a
		#    dead circle into roaming; because it is three incommensurate octaves it never
		#    repeats and it spends real time near level between the sweeps.
		# 2. THE TETHER. The orbit tangent (plus a soft radial pull) says which way it OUGHT
		#    to be heading; the difference is answered the only way a swimming animal can
		#    answer it — by leaning that way — never by yawing flat.
		var flat := Vector2(pos.x, pos.z)
		var dist: float = maxf(flat.length(), 0.001)
		var radial := flat / dist                       # unit vector pointing outward
		var tangent := Vector2(-radial.y, radial.x) * _dir
		var err: float = dist - _r                       # +ve = drifted too far out
		var steer := (tangent - radial * clampf(err * RADIAL_HOLD, -0.9, 0.9)).normalized()
		var base_heading: float = atan2(steer.x, steer.y)
		var weave: float = sin(_t * 0.16 + _ph) * 0.30 \
			+ sin(_t * 0.05 + _ph * 2.3) * 0.22 \
			+ sin(_t * 0.027 + _ph * 3.7) * 0.34
		var tether: float = clampf(wrapf(base_heading - _heading, -PI, PI) * TETHER_BANK,
			-TETHER_BANK_MAX, TETHER_BANK_MAX)
		var bank_target: float = clampf(weave + tether, -BANK_MAX, BANK_MAX)
		# The wings take their own time coming over — a five-metre span has inertia, and the
		# lag is what makes the entry to a turn read as a roll rather than a snap.
		_roll = lerp_angle(_roll, bank_target, clampf(delta * BANK_RESP, 0.0, 1.0))
		# THE COUPLING. The heading changes because the animal is banked, and by exactly as
		# much as the bank says: level = dead straight, hard over = the tightest arc it has.
		# (|_roll| <= BANK_MAX < PI/2, so the tangent can never run away.)
		var turn_rate: float = clampf(TURN_PER_BANK * tan(_roll),
			-TURN_RATE_MAX, TURN_RATE_MAX)
		_turn_smooth = turn_rate
		_heading += turn_rate * delta
		# --- advance along the heading, then clamp the orbit so the span clears the legs ---
		var fwd := Vector3(sin(_heading), 0.0, cos(_heading))
		var np: Vector3 = pos + fwd * (_speed * delta)
		var nd: float = Vector2(np.x, np.z).length()
		var cd: float = clampf(nd, _r - RADIAL_CLAMP, _r + RADIAL_CLAMP)
		if not is_equal_approx(cd, nd) and nd > 0.001:
			var rn := Vector2(np.x, np.z) / nd * cd
			np.x = rn.x
			np.z = rn.y
		np.y = _depth
		global_position = np
		# --- orientation: yaw + a gentle pitch toward the climb, then the bank ------------
		var climb: float = (_depth - _prev_depth) / maxf(delta, 0.0001)
		var look_tgt: Vector3 = np + fwd + Vector3(0.0, clampf(climb * PITCH_LOOK, -0.5, 0.5), 0.0)
		if (look_tgt - np).length_squared() > 0.000001:
			look_at(look_tgt, Vector3.UP)
		# THE BANK GOES ON THE HOST, about its own forward axis — the only axis a bank can be
		# about. look_at has just levelled the body along the direction of travel, so rolling
		# around local Z tips the starboard wing up for a positive _roll, which is a lean to
		# port, which is the direction a positive turn_rate is taking it: attitude and path
		# agree because they are the same number. It used to be written to the MODEL's local
		# rotation.z instead, which after the facing correction is not the forward axis at
		# all — the model node now carries the authored-facing fix and nothing else.
		rotate_object_local(Vector3.BACK, _roll)
		# (No drive() here on purpose — see the note in _ready(). The wing-beat is constant.)

## One slow giant on a drifting circuit under the rig. Raw circular path around its own
## `home` — either the rig's midpoint (the default, for the roaming residents) or a
## specific caisson (LEG_HOME, for the big groupers that hold a territory against the
## steel). It lives 15+ m down, below every deck, net and swimmer, and the leg-anchored
## ones sit below the caissons' own -23 bottom, so no wall test is needed either way.
class DeepGiant extends Node3D:
	const ANIM := preload("res://scripts/world/creature_anim.gd")
	## BODY DEPTH, dorsal to belly. The generated grouper measures 1.90 long by 0.80 deep —
	## a 0.42 ratio, which is a cod's proportion, not a grouper's, and at this size the
	## animal read slab-sided: a long shape at the edge of the floodlight with no mass to it.
	## A real grouper is a DEEP fish, half again as tall through the shoulder as it is thick.
	## Stretching the model's own Y (the mesh is authored lying down, so Y is dorsal-ventral)
	## leaves length and width — which the scale normalisation set from the species size —
	## untouched.
	##
	## 2026-07-26: 1.3 took it to a 0.55 depth ratio and the owner asked for more, so 1.55,
	## which is a 0.65 ratio: about as deep through the shoulder as a goliath grouper reads
	## in the water once you count the dorsal. That is the ceiling for this trick — a fish
	## past ~0.7 stops being a grouper and starts being a discus, and the stretch is applied
	## to the WHOLE model, fins and jaw included, so it distorts as fast as it deepens.
	## Groupers only: the halibut on this same class is a FLATFISH and must stay flat.
	const GROUPER_DEPTH: float = 1.55
	var slug: String = "fish_barrel_grouper"
	var _size: float
	var _band_y: float
	var _r: float
	var _rate: float
	var _ph: float
	var _home: Vector3
	var _t: float = 0.0
	var _mats: Array = []
	var _ai_acc: float = 0.0

	func _init(size: float = 3.5, band_y: float = -20.0, r: float = 12.0,
			rate: float = 0.05, ph: float = 0.0, home: Vector3 = Vector3.ZERO) -> void:
		_size = size
		_band_y = band_y
		_r = r
		_rate = rate
		_ph = ph
		_home = home

	func _ready() -> void:
		var gen: Dictionary = ANIM.attach(self, "res://assets/models/fauna/%s/%s.glb" % [slug, slug],
			_size, ANIM.Mode.UNDULATE, 0.07, 0.5, Color(0.2, 0.5, 0.55), _ph)
		if gen.is_empty():
			queue_free()
			return
		_mats = gen["mats"]
		if slug == "fish_barrel_grouper":
			var model: Node3D = gen["model"]
			model.scale.y *= GROUPER_DEPTH
		# Barely lit — these read as shapes in the murk, not lanterns. The pontoon
		# floodlights supply whatever highlight they get.
		ANIM.drive(_mats, 0.45, 0.05)
		_t = _ph * 20.0

	func _process(delta: float) -> void:
		# DECIMATED (see GliderRay). Position is a pure function of the accumulated clock, so
		# handing over the skipped time reproduces the circuit exactly — a lap still takes
		# TAU/_rate seconds. These nine giants live 12-76 m down and are hidden outright
		# whenever the camera is above the wave line.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_t += delta
		var a: float = _t * _rate + _ph
		var next := Vector3(_home.x + cos(a) * _r,
			_band_y + sin(_t * 0.11 + _ph) * 1.6,
			_home.z + sin(a) * _r * 0.8)
		var vel: Vector3 = next - global_position
		global_position = next
		var flat := Vector3(vel.x, 0.0, vel.z)
		if flat.length_squared() > 0.00001:
			look_at(next + flat, Vector3.UP)

## THE HUGE GROUPER'S PATROL. A DeepGiant that holds one TRUE circle about a pillar's axis
## instead of the parent's drifting ellipse — see LEG_PILLAR above for the placement.
##
## Three things this does that the parent does not, all of them the point of the brief:
##
##  1. A CIRCLE, not an ellipse. The parent squashes z by 0.8, which is a lap that speeds up
##     and slows down twice a turn and reads as drift. Here x and z share one radius, so the
##     animal holds a constant distance off the steel and a constant speed all the way round.
##  2. THE HEADING IS THE TANGENT, taken analytically (d/da of the circle is (-sin a, 0,
##     cos a)) rather than measured from last frame's displacement. The parent's
##     frame-difference method is undefined on the first frame and jitters whenever the step
##     is tiny — and at a 58 s lap the steps ARE tiny — so a slow fish computed its facing
##     out of near-zero noise. From the tangent the nose is exactly on the direction of
##     travel every frame, at any speed, including frame one.
##     FACING: CreatureAnim.attach() has already yawed the model 180 (Meshy authors +Z, Godot
##     is -Z) and set flow_axis/flow_flip to match, so look_at() — which aims the host's -Z at
##     the target — puts this animal head-first. Nothing here may re-correct that; doing the
##     180 twice is exactly how a fish ends up swimming backwards.
##  3. A GENTLE BOB. One slow sine, ~22 s a cycle, ±1.1 m: enough that it is never a
##     cardboard cut-out sliding on a plane, small enough that it never reads as a dive.
##
## Bounded by construction — position is a function of the home, the radius and the clock, so
## there is no integrated state that can wander off and no tether needed to stop it.
class PillarPatrol extends DeepGiant:
	const BOB_M: float = 1.1     ## amplitude of the vertical bob, metres
	const BOB_HZ: float = 0.045  ## ~22 s a cycle, independent of the lap

	func _process(delta: float) -> void:
		# DECIMATED (see DeepGiant). Bounded by construction — position is a function of the
		# clock, the home and the radius — so a skipped frame plus its delta is arithmetically
		# the same circuit. The leviathan patrols at -76 m; nothing about this is ever seen
		# at a range where an 8 Hz update could read as anything.
		_ai_acc += delta
		if not AIB.due(self, _ai_acc):
			return
		delta = _ai_acc
		_ai_acc = 0.0
		_t += delta
		var a: float = _t * _rate + _ph
		var pos := Vector3(_home.x + cos(a) * _r,
			_band_y + sin(_t * TAU * BOB_HZ + _ph) * BOB_M,
			_home.z + sin(a) * _r)
		global_position = pos
		look_at(pos + Vector3(-sin(a), 0.0, cos(a)), Vector3.UP)

## Marine snow: slow drifting particulate that sells the water as a medium.
func _marine_snow() -> void:
	var snow := GPUParticles3D.new()
	snow.amount = 1550               # headroom; amount_ratio scales the live count cheaply
	snow.amount_ratio = 0.62         # calm baseline; storm ramps it toward 1.0 — a touch
	# richer than before so the water reads as a genuinely suspended medium you are inside
	# of, the single biggest "I am underwater" cue after the Snell window. Still light
	# enough that it drifts as particulate and never fogs the near view into soup.
	snow.lifetime = 14.0
	snow.preprocess = 14.0
	snow.local_coords = false
	snow.visibility_aabb = AABB(Vector3(-45, -18, -45), Vector3(90, 18, 90))
	_snow = snow
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Keep the top of the emission box well BELOW the deepest wave trough. Spawning to
	# y -1 put unshaded white billboards above the waterline every time a trough passed,
	# and they read from the deck as hard white squares littering the night sea. The
	# swell reaches ~2.8 m of amplitude at full sea state, so -4 is the shallowest safe
	# ceiling; snow still greets you as soon as you are a couple of metres under.
	mat.emission_box_extents = Vector3(40, 6, 40)   # node sits at y -10 -> spans -16..-4
	mat.gravity = Vector3(0.25, -0.12, 0.18)   # the gyre's slow underwater set
	mat.initial_velocity_min = 0.02
	mat.initial_velocity_max = 0.1
	# Marine snow is aggregate: flakes range from barely-there specks to visible tufts.
	# Every mote being the SAME size was half of why the field read as scattered confetti
	# rather than suspended particulate — identical size plus billboarding means identical
	# on-screen shape for every single one.
	mat.scale_min = 0.45
	mat.scale_max = 2.3
	snow.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	quad.material = MatLib.soft_mote(Color(0.75, 0.85, 0.85, 0.5))
	snow.draw_pass_1 = quad
	add_child(snow)
	snow.position = Vector3(0, -10, 0)

func _bubble_vents() -> void:
	for leg in [LEGS[1], LEGS[2]]:
		var bub := GPUParticles3D.new()
		bub.amount = 60
		bub.lifetime = 5.0    # with the gravity below, a plume tops out around y -6
		bub.preprocess = 5.0
		bub.local_coords = false
		bub.visibility_aabb = AABB(Vector3(-3, 0, -3), Vector3(6, 14, 6))
		var mat := ParticleProcessMaterial.new()
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		mat.emission_sphere_radius = 0.6
		# Buoyancy, not a rocket. At 1.9 m/s^2 over a 6 s life a bubble climbed
		# 0.5*1.9*36 = 34 m from its -13.5 m vent, i.e. it burst out of the sea and kept
		# going 20 m into the air. Dialled to a rise that tops out several metres under
		# the swell, which is also what a real vent plume looks like from below.
		mat.gravity = Vector3(0, 0.42, 0)
		mat.initial_velocity_min = 0.2
		mat.initial_velocity_max = 0.5
		bub.process_material = mat
		var quad := QuadMesh.new()
		quad.size = Vector2(0.06, 0.06)
		quad.material = MatLib.soft_mote(Color(0.85, 0.95, 0.95, 0.6))
		bub.draw_pass_1 = quad
		add_child(bub)
		bub.position = Vector3(leg.x + 2.2, -13.5, leg.z - 1.5)

func _mooring_chains() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.19, 0.17)
	mat.roughness = 0.9
	for leg in LEGS:
		var dir := Vector3(signf(leg.x), 0, signf(leg.z)).normalized()
		var from := Vector3(leg.x, -2.5, leg.z) + dir * 3.2
		# Mooring lines run down and out until they vanish into the deep murk — with the
		# 4x floor they no longer reach bottom on screen; the fog swallows them, which is
		# exactly what a real mooring looks like from the surface zone.
		var to := from + dir * 44.0 + Vector3(0, -46.0, 0)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.09
		cm.bottom_radius = 0.09
		cm.height = from.distance_to(to)
		cm.material = mat
		mi.mesh = cm
		add_child(mi)
		mi.global_position = (from + to) * 0.5
		mi.look_at_from_position(mi.global_position, to, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)

func _storm_node() -> Node:
	if _storm != null and is_instance_valid(_storm):
		return _storm
	var stack: Array = [get_tree().root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is StormSystem:
			_storm = n
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func _storm_intensity() -> float:
	var st: Node = _storm_node()
	if st == null:
		return 0.0
	var v: Variant = st.get("_intensity")
	return clampf(float(v), 0.0, 1.0) if v != null else 0.0

# ---------------------------------------------------------------- schools

## Spawn the visible shoals for every species that declares one — same table the
## rod rolls. Depth band, size, count, tint, and active hours all come along. Each
## species is stocked SCHOOL_PODS times: see the constant for why.
func _spawn_schools() -> void:
	for id in FISH.all():
		var def: Dictionary = FISH.all()[id]
		var school: Dictionary = def.get("school", {})
		if int(school.get("count", 0)) <= 0:
			continue
		var tint_arr: Array = school["tint"]
		var tint := Color(tint_arr[0], tint_arr[1], tint_arr[2])
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mat.roughness = 0.6
		if id == "fish_herring":   # the lantern shoal glows, canon
			mat.emission_enabled = true
			mat.emission = Color(0.2, 0.9, 0.85)
			mat.emission_energy_multiplier = 0.5
		var band_y: float = DEPTH_BAND.get(def.get("depth", "mid"), -4.5)
		# One material per species, shared by both pods — the tint is a fact about the
		# fish, not about which patch of water this particular shoal is working.
		for pod in range(SCHOOL_PODS):
			_spawn_pod(id, def, school, tint, mat, band_y, pod)

## One pod of one species: its own node, its own members, its own circuit. Pod 0 works the
## water immediately around the rig; pod 1 and up work the open water (POD_SPREAD).
func _spawn_pod(id: String, def: Dictionary, school: Dictionary, tint: Color,
		mat: StandardMaterial3D, band_y: float, pod: int) -> void:
	var root := Node3D.new()
	add_child(root)
	var size: float = float(school["size"])
	var shape: String = String(school.get("shape", "slender"))
	# The species' real generated skin: the SAME mesh the caught/held fish and the
	# reef shoals use. Godot caches the .glb, so every member of a school shares the
	# one mesh resource — only the node instances repeat. Tinted per the school entry,
	# swimming on the UNDULATE body wave, each fish on its own phase so the school
	# doesn't beat in lockstep. Missing asset -> the tinted primitive silhouette, so a
	# fish still generating in the background never leaves a hole in the water.
	var glow: Color = Color(0.2, 0.9, 0.85) if id == "fish_herring" else tint
	var model_len: float = maxf(size, 0.3) * 0.7
	var model_path: String = "res://assets/models/fauna/%s/%s.glb" % [id, id]
	var members: Array = []
	# Per-member swim personality — see the FISH_EASE block. Parallel plain Arrays, not
	# PackedFloat32Arrays: these are written every frame through the school Dictionary, and
	# a Packed array is copy-on-write, so `s["head"][i] = x` would copy the whole array.
	var phases: Array = []
	var speeds: Array = []
	var heads: Array = []
	var climbs: Array = []
	for i in range(int(school["count"])):
		var f := Node3D.new()
		root.add_child(f)
		# Per-member size spread: a real shoal is juveniles-to-adults, not one stamped
		# size repeated N times. Most cluster around the school size; a few run notably
		# bigger (the old breeders) or smaller (this year's fry). Skewed so the big ones
		# are the minority they should be.
		var roll: float = _rng.randf()
		var sv: float = (0.62 + 0.5 * roll) if roll < 0.82 else (1.12 + 1.05 * (roll - 0.82) / 0.18)
		var member_len: float = model_len * sv
		var ph: float = _rng.randf() * TAU
		var gen: Dictionary = ANIM.attach(f, model_path, member_len, ANIM.Mode.UNDULATE,
			0.1, 2.2, glow, ph)
		if gen.is_empty():
			_build_fish(f, shape, size * sv, mat)   # no generated mesh yet — keep the silhouette
		else:
			for m in gen["mats"]:
				(m as ShaderMaterial).set_shader_parameter("tint", tint)
			if id == "fish_herring":
				ANIM.drive(gen["mats"], 2.2, 0.5)   # the lantern shoal keeps its glow
		# This fish's own distance budget, generated mesh or silhouette alike.
		_budget_fish(f, clampf(member_len * FISH_RANGE_PER_M, FISH_RANGE_MIN, FISH_RANGE_MAX))
		members.append(f)
		phases.append(ph)
		speeds.append(_rng.randf_range(0.78, 1.28))
		heads.append(_rng.randf() * TAU)
		climbs.append(0.0)
	# How wide the pod itself is. It used to be a flat (0.8..1.3) * (1 + size/2), i.e. a
	# ~1.4 m ball whether the shoal held two groupers or thirty-four sprats — which is why
	# a big school read as a knot rather than a shoal. Scaling on sqrt(count) keeps the
	# density roughly constant instead: more fish, more water.
	var spread_r: float = (0.9 + size * 0.55) * sqrt(float(maxi(members.size(), 1))) * 0.42
	_schools.append({
		"root": root, "fish": members, "def": def, "id": id, "pod": pod,
		"band_y": band_y - POD_DROP[pod], "size": size,
		"spread": POD_SPREAD[pod], "rates": POD_RATES[pod], "radius": spread_r,
		"ph": phases, "spd": speeds, "head": heads, "climb": climbs,
		"warm": false,
		"t": _rng.randf_range(0, 100.0),
		# Per-pod AI decimation state — see the block in _process. `acc` is the delta this pod
		# has accumulated but not yet spent; `centre` is where it was last seen, which is what
		# the distance ranking uses (the root node never leaves the origin).
		"acc": 0.0,
		"centre": Vector3(0.0, band_y - POD_DROP[pod], 0.0),
		# A stable per-pod number to offset the tick phase by, so the 48 pods spread across the
		# stride instead of all updating on the same frame. Taken at spawn — looking the pod's
		# own index up per frame would be a linear scan comparing dictionaries.
		"phase": _schools.size(),
	})

## Give one fish — generated mesh or fallback silhouette — its own distance budget; see
## FISH_RANGE_PER_M for why it does not take render_budget.gd's generic size-derived one.
## Walks the whole instance because a .glb can carry several surfaces and the silhouette
## fallback is half a dozen primitives.
func _budget_fish(f: Node, reach: float) -> void:
	var stack: Array = [f]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		mi.visibility_range_end = reach
		mi.visibility_range_end_margin = reach * FISH_RANGE_FADE
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

## Build one fish's body under `f`. Convention: head faces -Z, tail at +Z (the
## school code look_at()s -Z toward the swim target). Each `shape` reads as a
## different silhouette in the water so a squid, a sole and a pike never blur
## into "generic fish". `mat` is the species tint (shared per school).
func _build_fish(f: Node3D, shape: String, size: float, mat: Material) -> void:
	match shape:
		"flat":            # flatfish: wide, paper-thin oval gliding horizontally
			_ellipsoid(f, mat, Vector3.ZERO, Vector3(0.30, 0.04, 0.24) * size)
			_tail(f, mat, size, 0.34 * size, 0.9, 0.5)
			for sx in [-1.0, 1.0]:   # both eyes topside — the flatfish giveaway
				_ellipsoid(f, _eye(), Vector3(sx * 0.05 * size, 0.045 * size, -0.13 * size), Vector3.ONE * 0.02 * size)
		"eel":             # long ribbon, a dorsal frill running the body, tiny head
			_capsuleZ(f, mat, Vector3(0, 0, 0.28 * size), 0.035 * size, 1.05 * size)
			_dorsal(f, mat, Vector3(0, 0.05 * size, 0.28 * size), 0.11 * size, 1.0 * size)
			_ellipsoid(f, _eye(), Vector3(0.03 * size, 0.02 * size, -0.26 * size), Vector3.ONE * 0.02 * size)
		"pike":            # torpedo with a pointed snout — the ambush shape
			_capsuleZ(f, mat, Vector3(0, 0, 0.06 * size), 0.045 * size, 0.46 * size)
			var snout := _cone(mat)
			var mi := MeshInstance3D.new(); mi.mesh = snout; f.add_child(mi)
			mi.scale = Vector3(0.09, 0.22, 0.09) * size   # slim spike
			mi.position = Vector3(0, 0, -0.3 * size)
			mi.rotation.x = deg_to_rad(-90)               # point forward (-Z)
			_tail(f, mat, size, 0.11 * size, 0.9, 0.34)
		"squid":           # mantle + fin flaps + a bundle of trailing arms
			var mantle := _cone(mat)
			var mm := MeshInstance3D.new(); mm.mesh = mantle; f.add_child(mm)
			mm.scale = Vector3(0.10, 0.42, 0.10) * size
			mm.position = Vector3(0, 0, 0.18 * size)
			mm.rotation.x = deg_to_rad(90)                # taper trails (+Z)
			for sx2 in [-1.0, 1.0]:
				_dorsalFlat(f, mat, Vector3(sx2 * 0.08 * size, 0, 0.28 * size), Vector3(0.16, 0.01, 0.12) * size)
			for k in range(6):    # arms fanning off the head (-Z)
				_capsuleZ(f, mat, Vector3((k - 2.5) * 0.014 * size, 0, -0.18 * size), 0.008 * size, 0.2 * size)
			_ellipsoid(f, _eye(), Vector3(0.055 * size, 0, -0.02 * size), Vector3.ONE * 0.03 * size)
		"barrel":          # fat rounded grouper, big head, stubby tail
			_ellipsoid(f, mat, Vector3.ZERO, Vector3(0.16, 0.17, 0.23) * size)
			_tail(f, mat, size, 0.11 * size, 0.9, 0.26)
			_dorsal(f, mat, Vector3(0, 0.14 * size, 0.02 * size), 0.09 * size, 0.34 * size)
		"deep":            # slab-sided bream/jack: tall, thin, forked tail
			_ellipsoid(f, mat, Vector3.ZERO, Vector3(0.075, 0.24, 0.18) * size)
			_tail(f, mat, size, 0.16 * size, 1.3, 0.26)
			_dorsal(f, mat, Vector3(0, 0.22 * size, 0.0), 0.16 * size, 0.4 * size)
		"fusiform":        # honest fish with a dorsal fin and a forked tail
			_capsuleZ(f, mat, Vector3.ZERO, 0.055 * size, 0.3 * size, 1.3)
			_tail(f, mat, size, 0.12 * size, 1.1, 0.21)
			_dorsal(f, mat, Vector3(0, 0.085 * size, 0.0), 0.08 * size, 0.28 * size)
		_:                 # "slender" — the schooling sprat/herring default
			_capsuleZ(f, mat, Vector3.ZERO, 0.045 * size, 0.34 * size)
			_tail(f, mat, size, 0.1 * size, 1.0, 0.22)

# --- silhouette primitives (head -Z, tail +Z) ---
func _capsuleZ(f: Node3D, mat: Material, pos: Vector3, r: float, h: float, y_scale: float = 1.0) -> void:
	var mi := MeshInstance3D.new()
	var c := CapsuleMesh.new(); c.radius = r; c.height = h; c.material = mat
	mi.mesh = c; f.add_child(mi)
	mi.position = pos; mi.rotation.x = deg_to_rad(90); mi.scale.y = y_scale   # long axis -> Z

func _ellipsoid(f: Node3D, mat: Material, pos: Vector3, half: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new(); s.radius = 1.0; s.height = 2.0; s.material = mat
	mi.mesh = s; f.add_child(mi)
	mi.position = pos; mi.scale = half

func _tail(f: Node3D, mat: Material, size: float, w: float, h_mul: float, z: float) -> void:
	var mi := MeshInstance3D.new()
	var p := PrismMesh.new(); p.size = Vector3(w, 0.01 * size, 0.1 * size * h_mul); p.material = mat
	mi.mesh = p; f.add_child(mi)
	mi.position = Vector3(0, 0, z * size); mi.rotation.x = deg_to_rad(90)   # vertical caudal fin

func _dorsal(f: Node3D, mat: Material, pos: Vector3, height: float, length: float) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = Vector3(0.015, height, length); b.material = mat
	mi.mesh = b; f.add_child(mi); mi.position = pos

func _dorsalFlat(f: Node3D, mat: Material, pos: Vector3, sz: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = sz; b.material = mat
	mi.mesh = b; f.add_child(mi); mi.position = pos

func _cone(mat: Material) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = 0.0; c.bottom_radius = 1.0; c.height = 1.0; c.material = mat; return c
func _eye() -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.02, 0.02, 0.03); m.roughness = 0.3; return m

## Above the surface, none of this is visible — and none of it should be SUBMITTED.
##
## ocean_water.gdshader is depth_draw_opaque, so from a deck 24 m up you cannot see the
## seabed, the wreck field, the reef, the kelp or the marine snow through the water: they
## are all behind an opaque surface. Godot's Compatibility renderer has no occlusion
## culling, though, so every one of those meshes was still being drawn and then discarded
## by the depth test on every frame the player spent topside — which is nearly all of them.
## Measured from sea level it was ~4.9 M triangles and ~4,100 draw calls of pure waste.
##
## The margin keeps everything alive well before the camera reaches the water, so nothing
## pops in as you climb down the tidal ladder or a fish breaks the surface beside you.
##
## THE MARGIN IS MEASURED FROM STILL WATER, AND IT USED TO BE MEASURED FROM THE SWELL. The
## margin itself is unchanged at 4 m; what changed is the reference, and that one word was
## costing the wet deck a third of its frame.
##
## The Wet Deck floor is y 2.0 (rig_builder.WET_Y), so a standing player's eye is at y ~3.6 —
## and a swell-relative 4 m margin puts the threshold at `wave_height(here) > -0.4`, i.e.
## essentially THE SIGN OF THE WAVE UNDER THE RIG. The swell is always running
## (SunController.BASE_SEA_STATE 0.4), so standing still on the wet deck showed and hid this
## entire subtree once or twice a SECOND, for as long as the player stood there. Each flip
## walks several thousand nodes calling instance_set_visible, and on the visible frames the
## deck submitted the whole ocean: 2.0 M primitives on one visit and 3.6 M on the next, a
## 24 ms median with a 33 ms outlier. It is also why KNOWN_ISSUES said nothing could be
## *proved* at the wet deck — that 7-9 ms "noise" was not noise, it was this.
##
## Referencing still water makes the test independent of the sea state, which is the whole
## point, and drops a Gerstner sum from every frame as a side effect. Nothing is given up: the
## crest of a full storm swell is ~1.5 m, so the still-water clearance still has the world
## standing well before the camera can reach the surface. What is NOT claimed here is that the
## water is see-through-proof — measured, it is not quite: at an eye height of 2.05 m leaning
## over open water, hiding this subtree changes 17 sampled pixels against a 6-pixel motion
## floor (fish just under the surface). See tests/vantage_perf.gd --cullproof.
##
## s24: 4.0 was costing the WET DECK the whole underwater world for nothing. A standing eye
## there is 3.6 m (floor 2.0 + 1.6 eye) and the visible-state threshold was 4.0 + 1.0 = 5.0,
## so the player stood permanently on the visible side — 206-214 draw calls (~7.5%) and ~1.3 M
## primitives drawn every frame at the vantage that is already the heaviest in the game, and
## the same --cullproof measurement says that at 3.60 m hiding it changes **2 sampled pixels
## against a 0-pixel null floor**. It is invisible there and it was being drawn.
##
## 2.8 hides above 3.4 and shows below 2.8, which keeps BOTH measurements honest: the standing
## wet-deck eye (3.6) clears the hide threshold by 0.2 m, and the lean-over-water case (2.05)
## and the pontoon walkway (2.55) both still sit on the visible side, so the 17-pixel case above
## is unaffected.
const TOPSIDE_MARGIN: float = 2.8
## Deadband, so a camera parked exactly on the threshold cannot flip-flop. Only ever widens
## the VISIBLE state, so the transition into the water is the reliable direction.
##
## MUST come down with the margin. s21 found this subtree flipping 1-2 times a SECOND at the
## wet deck, which is what made that vantage unmeasurable (9.52 ms spread). At 2.8 + 1.0 the
## hide threshold would land on 3.8 and the show threshold on 2.8 — putting a boundary within
## 0.2 m of the standing eye, i.e. re-creating exactly that flip-flop. 0.6 keeps the nearest
## boundary 0.2 m away on both sides.
const TOPSIDE_HYST: float = 0.6

func _cull_topside() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		_cam_eye_ok = false
		return
	var cp: Vector3 = cam.global_position
	# Cached for _pod_due: 48 pods asking the viewport for its camera every frame is 48 tree
	# lookups for one value that is already in hand here.
	_cam_eye = cp
	_cam_eye_ok = true
	var want: bool = cp.y < TOPSIDE_MARGIN + (TOPSIDE_HYST if visible else 0.0)
	if visible != want:
		visible = want

func _process(delta: float) -> void:
	_cull_topside()
	_t += delta
	# Marine snow thickens and drives harder when a storm stirs the water column —
	# the same sediment that fogs the near-surface visibility (see underwater_fx).
	if _snow != null:
		var storm: float = _storm_intensity()
		_snow.amount_ratio = clampf(0.55 + storm * 0.45, 0.0, 1.0)
		_snow.speed_scale = 1.0 + storm * 0.7
	# EVERYTHING BELOW THE WAVE LINE IS HIDDEN WHENEVER THE CAMERA IS TOPSIDE
	# (_cull_topside, above) — and until now it was all still being SIMULATED behind that
	# hidden flag: 44 kelp strands and every fish in the ocean, each fish sampling the
	# Gerstner swell and running a look_at, on every frame of a game that is mostly played
	# on deck. Doubling the stocking (2026-07-26) would have doubled that bill for water
	# nobody is looking at, so the swim now stops with the drawing. The phase bookkeeping
	# below deliberately keeps running — it is a handful of dictionary reads, and it is
	# what decides which shoals EXIST, which the screenshot harnesses read. And because a
	# pod's own clock `t` stops with it, every fish resumes exactly where it left off
	# instead of teleporting a minute further down its circuit the moment you go under.
	var swim: bool = visible
	# Kelp sways in the set of the current.
	if swim:
		var t_x: float = _t * 0.4
		var t_z: float = _t * 0.33
		for i in range(_kelp.size()):
			var sway: float = _kelp_sway[i]
			var phase: float = _kelp_phase[i]
			var strand: Node3D = _kelp[i]
			strand.rotation = Vector3(sin(t_x * sway + phase) * 0.1, strand.rotation.y,
				cos(t_z * sway + phase) * 0.1)
	# Schools: wander their band, members ease around the moving centre. Species keep
	# their active hours — the night shift appears as the day shoals thin out.
	var phase_key: String = "day"
	match GameClock.current_phase:
		GameClock.Phase.DAWN: phase_key = "dawn"
		GameClock.Phase.DUSK: phase_key = "dusk"
		GameClock.Phase.NIGHT: phase_key = "night"
	var storming: bool = _storm_intensity() > 0.15
	# THE SWELL CLOCK, SAMPLED ONCE A FRAME. It used to be read inside the per-fish loop, so
	# `Time.get_ticks_msec()` was being called once per fish per frame — 512 engine calls to
	# fetch a number that cannot change within a frame. It is also the only honest way to
	# read it: two fish in the same shoal were clamping against seas a fraction of a
	# millisecond apart.
	var wave_t: float = Gyre.water_time()
	# Below this line the surface cannot reach, at ANY sea state (Gyre.trough_floor is
	# analytic — see there). A pod whose highest reachable fish still sits below it can skip
	# the Gerstner sum outright, because the clamp it feeds could never bind.
	var floor_y: float = Gyre.trough_floor()
	for s in _schools:
		var active: Array = s["def"]["school"].get("active", [])
		# An EMPTY active list is not "never". It is how data/fish.json says this shoal
		# keeps no clock hours, and in that table it means exactly one thing: a
		# `storm: "only"` species — the drum croaker chorus and the squall garfish, which
		# between them declare 20 fish per pod. Read literally as "active in no phase",
		# those schools spawned their fish and then stayed hidden for the entire game.
		# They now show up for the one condition they are FOR, which is also the moment
		# the player is most likely to be looking at the water.
		var want: bool = active.has(phase_key) if not active.is_empty() else storming
		var root: Node3D = s["root"]
		root.visible = want
		if not want or not swim:
			continue
		# --- PER-POD DECIMATION -----------------------------------------------------------
		# 512 fish across 48 pods, every one of them re-solving its slot on the ring, sampling
		# the swell and running a look_at, every frame. The pods are 24-60 m across the water
		# from the camera at any moment, and a shoal at that range moving in 5 cm steps at 8 Hz
		# is indistinguishable from one moving in 1 cm steps at 30. So a pod that is far away
		# thinks less often — and is handed the time it missed, which is the ONLY way to do this
		# without slowing the shoal down (see scripts/world/ai_budget.gd for the trap).
		#
		# It lands especially cleanly here because the pod's update is already frame-rate
		# independent BY CONSTRUCTION: position is a function of the pod's own clock `t`, and
		# both easings are `1 - exp(-k * delta)`, which closes the same fraction of the gap per
		# SECOND however the seconds arrive — and, unlike `delta * k`, can never overshoot at a
		# long step. Advancing `t` by the accumulated delta puts the shoal exactly where it
		# would have arrived tick by tick.
		#
		# The accumulator lives on the POD's dictionary, not on a node: the pod root sits at the
		# world origin and never moves, so it cannot be asked how far away it is.
		s["acc"] += delta
		var pod_delta: float = s["acc"]
		if not _pod_due(s, pod_delta):
			continue
		s["acc"] = 0.0
		s["t"] += pod_delta
		var t: float = s["t"]
		# THE POD'S OWN WANDER. Two incommensurate octaves per axis instead of one, so the
		# centre never retraces the same lap — the jelly's trick, at shoal scale.
		var spread: Vector2 = s["spread"]
		var rates: Vector2 = s["rates"]
		var cx: float = cos(t * rates.x) * spread.x + sin(t * rates.x * 0.37 + 1.3) * spread.x * 0.16
		var cz: float = sin(t * rates.y) * spread.y + cos(t * rates.y * 0.43 + 2.1) * spread.y * 0.16
		var center := Vector3(cx, s["band_y"] + sin(t * 0.11) * 0.8 + sin(t * 0.037) * 0.5, cz)
		s["centre"] = center
		var members: Array = s["fish"]
		var n: int = members.size()
		var mph: Array = s["ph"]
		var mspd: Array = s["spd"]
		var mhead: Array = s["head"]
		var mclimb: Array = s["climb"]
		var r_base: float = s["radius"]
		# Slow enough that the eased follow below can actually keep up with it: a target
		# moving faster than FISH_EASE can track just drags the whole ring inward.
		var orbit: float = clampf(0.55 / maxf(s["size"], 0.6), 0.12, 0.8)
		# Frame-rate-independent easing — the same fraction of the gap closed per SECOND,
		# not per frame, so a 15 fps dip and a 60 fps stretch swim identically. On a pod's
		# very first live frame the fish are still stacked at the origin, so that one frame
		# seats them outright instead of letting them swoop in from the middle of the world.
		var warm: bool = s["warm"]
		var follow: float = (1.0 - exp(-FISH_EASE * pod_delta)) if warm else 1.0
		var turn: float = 1.0 - exp(-FISH_TURN * pod_delta)
		s["warm"] = true
		# CAN THE SURFACE CLAMP EVER BIND FOR THIS POD? The clamp below is a safety rail —
		# it stops a shallow shoal breaching through the swell — and for the deep pods it has
		# never once fired. Their ceiling is bounded by construction: the pod centre rides at
		# most band_y + 1.3 (its two vertical octaves, 0.8 + 0.5) and a member adds at most
		# another 0.60 of bob (0.34 + 0.26); `follow` only ever lerps toward that target, so
		# no fish can be above it once seated. If that ceiling still clears the deepest
		# trough the sea can produce plus the clamp's own margin, the sample is dead work and
		# the whole 11-band sum is skipped. Computed per pod, per frame, from the pod's own
		# numbers rather than a hand-typed depth, so retuning POD_DROP or a species' depth
		# band cannot leave a stale exemption behind. Every fish still swims — this drops the
		# arithmetic, never the animal.
		var pod_ceiling: float = s["band_y"] + 1.3 + 0.60
		var needs_surface: bool = pod_ceiling > floor_y - 0.5 - s["size"] * 0.5
		for i in range(n):
			var f: Node3D = members[i]
			var ph: float = mph[i]
			var spd: float = mspd[i]
			# A TARGET, not a rail. The evenly spaced slot is what still makes it read as
			# one school; the per-member weave, radius octave and speed are what stop it
			# reading as a carousel of clones.
			var a: float = t * orbit * spd + float(i) * (TAU / maxi(n, 1)) \
				+ sin(t * 0.23 * spd + ph) * 0.55
			var rad: float = r_base * (0.72 + 0.34 * sin(t * 0.27 * spd + ph * 1.3))
			var bob: float = sin(t * 0.41 * spd + ph) * 0.34 + sin(t * 0.15 + ph * 2.1) * 0.26
			var target: Vector3 = center + Vector3(cos(a) * rad, bob, sin(a) * rad * 0.72)
			var cur: Vector3 = f.global_position
			var next: Vector3 = cur.lerp(target, follow)
			# Never let a school breach. The "surface" band sits at -1.2, which was under
			# water when the sea was a flat plane; against the Gerstner swell (±2 m calm,
			# more in a squall) it put whole shoals of fish flapping above the waterline.
			# Clamp to the live surface, so a squall pushes the shallow bands down with it.
			# Full wave height: the 0.85 camera-test factor lifts a point above the true
			# surface in troughs, which is exactly where a shallow school would breach.
			if needs_surface:
				var surf: float = Gyre.wave_height(Vector2(next.x, next.z), wave_t)
				next.y = minf(next.y, surf - 0.5 - s["size"] * 0.5)
			# A school's drift band overlaps the rig legs — don't let fish swim through a
			# caisson. Only pay for the raycast near a leg (the schools spend most of their
			# orbit in open water), and if the step would enter the steel, stop the fish at
			# the surface so it grazes the leg and its orbit carries it back out.
			if _near_leg(next):
				var res: Dictionary = MOVE.swim_clear(f, cur, next, 0.3)
				next = res["pos"]
				if bool(res["blocked"]):
					next = _slide_leg(next, target, pod_delta)
			var step: Vector3 = next - cur
			f.global_position = next
			if not warm:
				continue
			# THE HEADING IS REMEMBERED, NOT RE-DERIVED. Pointing a fish straight down its
			# last frame's displacement is what made the old shoal snap: one jittery step
			# and the whole body yaws to it instantly. Carrying the heading and easing it
			# onto the new one gives the animal a turn RATE, so it banks through a change of
			# direction over a few tenths of a second like the glider ray does.
			if absf(step.x) + absf(step.z) > 0.0002:
				mhead[i] = lerp_angle(mhead[i], atan2(step.x, step.z), turn)
			# ...and it noses into its own climb rather than swimming flat while rising.
			# Eased on the same constant, and clamped well short of vertical so the look_at
			# below can never be handed a direction parallel to UP (that error-spams hard
			# enough to choke the editor debugger).
			mclimb[i] = lerpf(mclimb[i],
				clampf(step.y / maxf(pod_delta, 0.0001) * FISH_PITCH, -0.5, 0.5), turn)
			var hd: float = mhead[i]
			f.look_at(next + Vector3(sin(hd), mclimb[i], cos(hd)), Vector3.UP)

## Does this pod get to think this frame? The node-level rule (ai_budget.gd) keyed to a
## POD, which is a dictionary rather than a node.
##
## Ranked on the pod's last known centre, which is honest for a shoal: `radius` is a couple
## of metres, so the whole school is effectively at one distance. A pod inside AiBudget's
## NEAR_M runs every frame — the shoal you are actually swimming through is never decimated.
## The instance-free phase comes from the pod's own index so the 48 pods do not all land on
## the same frame, and the MAX_STEP guarantee is honoured for the same reason it exists
## there: nothing may go longer than that without an update.
func _pod_due(s: Dictionary, acc: float) -> bool:
	if not AIB.enabled or acc >= AIB.MAX_STEP or not _cam_eye_ok:
		return true
	var d2: float = _cam_eye.distance_squared_to(s["centre"])
	var stride: int = 1
	if d2 > AIB.MID_M * AIB.MID_M:
		stride = AIB.FAR_STRIDE
	elif d2 > AIB.NEAR_M * AIB.NEAR_M:
		stride = 2
	if stride <= 1:
		return true
	return (Engine.get_process_frames() + int(s["phase"])) % stride == 0

## Is `p` close enough to a rig leg (in plan) that a wall test is worth casting? The legs
## are 6 m square; 4.5 m from a centre clears the caisson plus a fish's turn radius.
func _near_leg(p: Vector3) -> bool:
	for leg in LEGS:
		if absf(p.x - leg.x) < 4.5 and absf(p.z - leg.z) < 4.5:
			return true
	return false

func _nearest_leg(p: Vector3) -> Vector3:
	var best: Vector3 = LEGS[0]
	var bd: float = 1.0e9
	for leg in LEGS:
		var d: float = absf(p.x - leg.x) + absf(p.z - leg.z)
		if d < bd:
			bd = d
			best = leg
	return best

## A fish the caisson raycast stopped DEAD is a fish the shoal swims away from. Its slot on
## the ring is on the far side of six metres of concrete, so the ray blocks it again on the
## next frame, and the next, while the pod drifts on without it — which is exactly how a
## lone fish ends up shivering flat against a leg twenty metres from its school. Probed for
## 2026-07-26: five bream and eight pollock were sitting on the SE caisson's z-face at a
## dead-identical z 8.8, stranded, while their shoals worked open water off to the north.
##
## A real fish goes AROUND. So a blocked fish is pushed ALONG the face — in whichever of
## the two tangential directions closes on the slot it wants — plus a small standoff out
## from the leg so the slide never grinds into the corner it is rounding. It works its own
## way past the steel and rejoins under its own steam, and because it is a nudge per frame
## rather than a re-seat, nothing about it is a teleport.
func _slide_leg(pos: Vector3, target: Vector3, delta: float) -> Vector3:
	var leg: Vector3 = _nearest_leg(pos)
	var out := Vector3(pos.x - leg.x, 0.0, pos.z - leg.z)
	if out.length_squared() < 0.0001:
		return pos
	out = out.normalized()
	var tangent := Vector3(-out.z, 0.0, out.x)
	if tangent.dot(target - pos) < 0.0:
		tangent = -tangent
	return pos + (tangent * 2.2 + out * 0.6) * delta
