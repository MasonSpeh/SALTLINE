extends Node3D
## The ten tropical species that LIVE on the reef growing down the caisson legs.
##
## NO `class_name`, deliberately: nothing needs the global name (leg_reef preloads this by
## path and the probe finds it by script path), and registering one on a brand-new file is
## how you get "Class X hides a global script class" out of the very import that is creating
## the entry — which is the file-cache lag docs/AGENT_TRAPS.md warns about, seen here.
##
## leg_reef.gd grows the coral; this puts the fish on it. The distinction that matters is
## home range: the shoals in underwater_world._spawn_schools are PELAGIC — a pod wanders a
## ±24-46 m box of open water and its members ride a slot on a moving ring. A reef fish does
## not do that. It has an address. It hangs over one colony, drifts a metre or two off the
## concrete, and when something big comes past it goes back INTO the coral and waits. Ten
## more wandering rings anchored nowhere would have been the existing system ten more times,
## which is not what "fish that play around the coral" means.
##
## So every fish here belongs to a STATION — one shoal, one colony, for the whole game. Its
## position is its station's seat on the wall plus a small multi-octave offset (the jelly's
## trick, at reef-fish scale), which means the animal is always where it lives and never
## needs a waypoint list, a path, or a place to swim back from.
##
## WHAT IS MEASURED RATHER THAN TYPED
##   * the deep stations are the REAL coral colonies — leg_reef records where it actually
##     seated each patch and hands the list over, so a shoal cannot hover over bare concrete
##   * the shallow stations are raycast onto the caisson faces the same way leg_reef seats a
##     coral, in the band underwater_world._leg_reef_growth encrusts (y -2.5..-10.5), which
##     is the only reef inside the player's dive limit
##   * every station's standoff is measured out from the surface the ray hit, so no fish
##     position anywhere in this file is a hand-typed coordinate
##
## PERFORMANCE — the hard constraint, and the reason several things here look odd.
## The pelagic shoals were profiled at ~3.7 ms at the waterline, and the dominant term was
## every fish calling Gyre.wave_height() — an 11-wave Gerstner sum in GDScript — once a
## frame, to run a surface clamp. Reef fish live 4-22 m down where that clamp could never
## bind, so THIS FILE NEVER TOUCHES Gyre AT ALL. Beyond that:
##   * one _process on the root over an array of stations, not 55 nodes with their own
##   * a station past its own cull radius is hidden AND not simulated — and because its
##     position is a function of its own clock, which stops with it, it resumes exactly
##     where it left off instead of teleporting (the same contract underwater_world's
##     topside cull relies on)
##   * inside that, the ai_budget.gd distance stride, keyed to the station
##   * ShaderMaterials are shared per station in PHASE_VARIANTS sets rather than one per
##     fish, so driving the swim rate is ~3 parameter writes a station instead of one per
##     animal — 119 materials for 228 fish, and only the handful of near stations get driven
##   * the whole subtree hangs under underwater_world, so the topside cull freezes it to
##     zero on deck, which is where the game is mostly played

const ANIM := preload("res://scripts/world/creature_anim.gd")
## Preloaded by PATH, not by class_name — the global class cache lags for a new file and the
## failure surfaces as an unrelated "Could not resolve class" somewhere else entirely.
const AIB := preload("res://scripts/world/ai_budget.gd")

const MODEL_PATH := "res://assets/models/fauna/%s/%s.glb"
## creature_swim's mode-0 body wave plus albedo-keyed BODY emission — see the shader's own
## header for why the reef fish cannot use the shared one unmodified, and why this is a
## separate file instead of a change to it.
const FISH_SHADER := preload("res://materials/reef_fish.gdshader")
## How hard the fish's own colours light themselves. leg_reef drives its coral at 1.35 through
## the same mechanism; the fish sit just under that, because a fish that out-glows the reef
## reads as a lamp rather than as an animal. Judged by looking, at four depths.
const BODY_GLOW: float = 1.25

## TEN SPECIES, TEN BEHAVIOURS. The brief was explicit that ten identical shoals is one
## shoal repeated ten times, so the table below varies six things independently and no two
## rows share a profile:
##   len     body length, metres. NOT the field-guide number, and the difference is
##           deliberate: photographed at real size (a 13 cm anthias, a 12 cm damsel) these
##           fish measured SEVEN PIXELS across at 7 m through the player's 107-degree
##           horizontal view, i.e. correct and invisible, which is exactly the mistake that
##           got coral_whip cut in s19. Scaled to read against the reef they live on rather
##           than against a field guide: the small species take ~1.8x, the big ones ~1.3x, so
##           0.22-0.62 m here against corals of 0.35-1.95 m. The size ORDER and the ratios
##           between species are the real ones, which is what makes the reef read as zoned.
##   y       preferred depth. Spread deliberately from -5.5 to -19 so the vertical column
##           reads as zoned: the shallow half is on the leg growth a diving player can
##           actually reach, the deep half is on leg_reef's coral.
##   st/n    stations x fish per station. A tight shoal, a loose pair and a solitary
##           territory holder are three different animals before any code runs.
##   stand   how far off the concrete the shoal hangs, metres — "how tightly it hugs
##           the structure". A clownfish never leaves the coral; an anthias cloud feeds
##           out in the flow.
##   rad/vrt how far it ranges along the wall and up/down it.
##   skit    flee radius in metres: how close the player gets before the shoal ducks.
##           0 = does not flee at all.
##   pace    body-wave rate multiplier; also how fast it eases to its target.
##   sleep   how much of the animal shuts down at night (0 = works nights).
##   bold    inverts the alarm: this one comes AT you instead of hiding.
##   alb     optional albedo multiply, for a mesh whose generated colour does not separate
##           from the reef behind it.
##   glow    fresnel rim energy, and `rim` the colour it comes off in. The band is 5-20 m
##           down a fog grade that eats saturation
##           (see the s19 reef screenshots — correct colour, invisible), so each fish
##           carries a little rim light in its OWN signature colour. The small species that
##           only ever read as a fleck of colour get the most.
const SPECIES := [
	# --- shallow: the growth band a diving player reaches --------------------------------
	{"slug": "trop_clown", "len": 0.24, "y": -5.5, "st": 4, "n": 3,
		"stand": 0.42, "rad": 0.50, "vrt": 0.38, "skit": 4.5, "pace": 1.15, "sleep": 0.85,
		"glow": 0.30, "rim": Color(1.00, 0.58, 0.24),
		"note": "host-bound: three fish that never leave one coral head, bobbing in place"},
	{"slug": "trop_yellow_tang", "len": 0.34, "y": -6.5, "st": 5, "n": 4,
		"stand": 0.80, "rad": 1.55, "vrt": 0.95, "skit": 3.2, "pace": 0.85, "sleep": 0.70,
		"glow": 0.26, "rim": Color(1.00, 0.88, 0.24),
		"note": "grazers: small groups working the wall, slow, not easily bothered"},
	{"slug": "trop_damsel", "len": 0.22, "y": -8.0, "st": 5, "n": 7,
		"stand": 0.55, "rad": 0.70, "vrt": 0.62, "skit": 5.5, "pace": 1.30, "sleep": 0.80,
		"glow": 0.32, "rim": Color(0.25, 0.80, 1.00),
		"note": "a tight shoal glued to one head — the most skittish thing on the reef"},
	# Moved from y -10 to the top of the coral band after looking at the frames: the shallow
	# band is INSIDE underwater_world's kelp stand (11 strands a leg on a 3.2-6.0 m ring, and
	# the caisson face is at 3.0 — the innermost strands are 200 mm off the concrete), so a
	# fish hugging the wall up there lives in green blade. Three species already work that band
	# and read well in it; the cleaner is the one that gains from open water around it, and a
	# cleaning station at the top of the reef is where the animal belongs anyway.
	{"slug": "trop_wrasse", "len": 0.28, "y": -12.4, "st": 8, "n": 1,
		"stand": 0.55, "rad": 0.95, "vrt": 0.55, "skit": 0.0, "pace": 1.55, "sleep": 0.90,
		"glow": 0.28, "rim": Color(0.62, 0.90, 1.00),
		"note": "a solitary cleaner working its station: quick, jittery, and unafraid"},
	# --- the coral band -------------------------------------------------------------------
	{"slug": "trop_butterfly", "len": 0.34, "y": -11.5, "st": 6, "n": 2,
		"stand": 0.85, "rad": 1.15, "vrt": 0.72, "skit": 3.8, "pace": 0.90, "sleep": 0.75,
		"glow": 0.26, "rim": Color(1.00, 0.94, 0.62),
		"note": "bonded PAIRS that stay within a body length of each other all game"},
	{"slug": "trop_blue_tang", "len": 0.40, "y": -13.5, "st": 4, "n": 7,
		"stand": 1.35, "rad": 2.30, "vrt": 1.05, "skit": 4.2, "pace": 1.00, "sleep": 0.65,
		"glow": 0.22, "rim": Color(0.24, 0.36, 1.00),
		"note": "a loose roving shoal that drifts across the whole colony rather than over it"},
	{"slug": "trop_anthias", "len": 0.24, "y": -15.0, "st": 5, "n": 11,
		"stand": 1.70, "rad": 1.50, "vrt": 1.10, "skit": 5.0, "pace": 1.40, "sleep": 0.85,
		"glow": 0.34, "rim": Color(1.00, 0.44, 0.72),
		# Pushed MAGENTA. Tripo returned a coral-orange fish, and leg_reef's reef is peach,
		# salmon and cream — photographed on it, sixteen orange anthias vanished into the
		# colony they were sitting on. A real Pseudanthias squamipinnis is magenta-pink, so
		# this is both the more accurate colour and the one that separates from the wall.
		"alb": Color(1.00, 0.58, 0.86),
		"note": "the cloud: a big loose swarm feeding out in the flow, that pours back into "
			+ "the coral all at once"},
	{"slug": "trop_triggerfish", "len": 0.44, "y": -16.0, "st": 4, "n": 1,
		"stand": 1.90, "rad": 2.90, "vrt": 1.20, "skit": 6.0, "pace": 1.05, "sleep": 0.45,
		"bold": true, "glow": 0.20, "rim": Color(1.00, 0.90, 0.55),
		"note": "territorial: the ONE species that closes on you instead of hiding"},
	{"slug": "trop_angel", "len": 0.50, "y": -17.5, "st": 5, "n": 1,
		"stand": 1.45, "rad": 2.60, "vrt": 1.10, "skit": 2.6, "pace": 0.62, "sleep": 0.60,
		"glow": 0.20, "rim": Color(0.55, 0.78, 1.00),
		"note": "solitary and slow: a wide unhurried circuit of its own patch"},
	{"slug": "trop_parrot", "len": 0.62, "y": -19.0, "st": 5, "n": 2,
		"stand": 0.70, "rad": 2.10, "vrt": 0.85, "skit": 2.2, "pace": 0.72, "sleep": 0.55,
		"graze": true, "glow": 0.18, "rim": Color(0.40, 1.00, 0.78),
		"note": "big grazers nosing along the concrete, head down, barely reacting to you"},
]

## How many distinct swim phases a station carries. One material set per station would beat
## the whole shoal in lockstep (a marching band, the exact failure the pelagic schools were
## fixed for in s18); one per FISH is 187 materials whose rate has to be written every frame.
## Three is where a shoal stops reading as synchronised, measured by looking.
const PHASE_VARIANTS: int = 3

## Nothing may get closer than this to the concrete, metres. Fish DO vanish into the coral
## when startled — that is the whole point of the duck — but a fish inside the caisson is a
## bug, and the corals themselves stand 0.2-1.0 m proud of the wall.
const MIN_STAND: float = 0.45

## How hard a fish is drawn toward its drifting target (1/s), and how fast its remembered
## heading eases onto its direction of travel. Same construction as the pelagic shoals:
## `1 - exp(-k * dt)` closes the same fraction of the gap per SECOND however the seconds
## arrive, which is what makes the station-level decimation below invisible.
## Minimum comfortable water between station-mates, metres — a soft target-space push,
## not a hard wall, so a startled shoal can still compress as it pours into the coral.
## ~1.5 body lengths on the mid-size species.
const SEP_M: float = 0.34
## The butterfly pair's tether: past this the partners drift back toward each other.
## Their species note promises a body length; this is that with a little slack.
const PAIR_M: float = 0.55
const FOLLOW: float = 1.9
const TURN: float = 2.6
const PITCH: float = 0.40        ## how much of its own vertical speed a fish noses into
## Below this speed a fish keeps its last heading instead of re-deriving one, m/s. A hovering
## cleaner wrasse's step is mostly numerical noise and atan2 of noise is a spin.
const HEAD_MIN_SPEED: float = 0.06

## Alarm rises fast and falls slow — a startled shoal pours into the coral in a moment and
## takes several seconds to trickle back out. Symmetric easing read as a shoal on a spring.
const ALARM_RISE: float = 6.0
const ALARM_FALL: float = 0.55

## The body-wave amplitude a fish is built at, and the ceiling the alarm drives it to.
##
## THIS IS WHERE THE FLEE RESPONSE GOES, AND `rate` IS WHERE IT MUST NOT (owner, s23: "the
## tropical fish move really weird when the player comes near… that area needs work and is
## currently glitchy"). creature_swim/reef_fish compute `t = TIME * rate + phase`, so `rate`
## is a TIME MULTIPLIER, not a speed dial: rewriting it at second T teleports the wave phase
## by T * delta_rate. This file used to push `pace * 2 * lerp(1, 2.2, alarm)` through drive()
## every time it moved by 0.02 — i.e. on every frame the player was walking toward a shoal —
## so at TIME 100 s a 0.02 step jumped TWO WHOLE CYCLES and every fish's body snapped to a
## random pose, every frame, for exactly as long as the player was near it. underwater_world's
## GliderRay carries the same lesson in its own comment and this file did not have it.
## So the beat is now SET ONCE at build and never written again; the alarm is spent on
## AMPLITUDE, which is a plain multiplier outside the sine and therefore continuous.
const BASE_AMP: float = 0.085
const ALARM_AMP: float = 1.75    ## a startled fish flicks harder, not at a teleported phase
const REST_AMP: float = 0.22     ## asleep in the coral: almost still
const NIGHT_EASE: float = 0.20   ## dusk-to-dark is minutes, not frames

## Distance budget. render_budget.gd's generic rule (size * 110 m) is for things in air; the
## same argument underwater_world makes for its shoals applies harder here, because these are
## 12-46 cm animals in water that is fogged at 0.028-0.2/m. Anything past this range is a
## smudge of fog-coloured fog. render_budget skips a mesh that already carries a range.
const RANGE_PER_M: float = 70.0
const RANGE_MIN: float = 14.0
const RANGE_MAX: float = 30.0
## A station stops being simulated at all this far past the range of the fish in it.
const STATION_CULL_PAD: float = 5.0

## The shallow band, on the leg growth underwater_world encrusts at y -2.5..-10.5. Sampled,
## not typed: the depths below are where the RAYS are fired, and the seat comes back from
## whatever the ray hits.
const SHALLOW_TOP: float = -4.4
const SHALLOW_BOTTOM: float = -11.4
const SHALLOW_ROWS: int = 6
## Verified by sonar and re-checked by leg_reef every run: every caisson face is exactly
## 3.0 m from its centre line at every depth in the band.
const LEG_HALF: float = 3.0
const LEGS: Array[Vector2] = [Vector2(-22, -12), Vector2(22, -12),
		Vector2(-22, 12), Vector2(22, 12)]
const FACES: Array[Vector3] = [Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1)]

var _colonies: Array = []
var _band_top: float = -12.6
var _band_bottom: float = -22.0
var _keep_out: Array = []
var _rng := RandomNumberGenerator.new()
var _space: PhysicsDirectSpaceState3D
var _stations: Array = []
var _night: float = 0.0
## Reported, not asserted — see _report.
var _built: Dictionary = {}
var _missing: Array = []
var _slug_tris: Dictionary = {}
var _tris: int = 0
var _rays: int = 0
var _fallbacks: int = 0

## `colonies` is leg_reef's own record of where it actually seated coral: [{pos, n}, ...] in
## world space. Empty is tolerated (the reef assets can be missing) — the shallow raycast
## pool alone still gives every species somewhere real to live.
func _init(colonies: Array = [], band_top: float = -12.6, band_bottom: float = -22.0,
		keep_out: Array = []) -> void:
	_colonies = colonies
	_band_top = band_top
	_band_bottom = band_bottom
	_keep_out = keep_out

func _ready() -> void:
	_rng.seed = 517303
	# Physics is not queryable until a physics frame has run. leg_reef already waits for
	# two before it builds and this is spawned after that, but a caller that builds ReefFish
	# on its own (tests/ReefFishProbe) has not — and a space state that is not ready measures
	# an empty world and seats every shallow station on the fallback.
	await get_tree().physics_frame
	_space = get_world_3d().direct_space_state
	var pool: Array = _pool()
	if pool.is_empty():
		push_warning("[reef_fish] no reef stations found — no tropical fish built")
		return
	_assign(pool)
	_report()

# ------------------------------------------------------------ where the fish live

## Every candidate address on the rig, deep and shallow, as {pos, n, y}.
##
## `pos` is a point ON the concrete and `n` the outward face normal, so a station is built by
## walking out along n — which is the only way to place a shoal off a wall without knowing
## which wall it is.
func _pool() -> Array:
	var pool: Array = []
	# 1. THE REAL CORAL. leg_reef appends one entry per colony it actually seated, so a
	#    shoal cannot be anchored to a patch the spacing rejected — i.e. to bare concrete.
	for c in _colonies:
		var p: Vector3 = c["pos"]
		if _blocked(p):
			continue
		pool.append({"pos": p, "n": c["n"], "y": p.y, "deep": true})
	# 2. THE SHALLOW GROWTH BAND. underwater_world._leg_reef_growth encrusts y -2.5..-10.5
	#    with anemones, sponges, fans and grass — 20 pieces a leg — and that band is the only
	#    reef inside the player's dive limit, so leaving it empty would have put every fish
	#    in this file below the deepest water anybody can swim to. Seated by raycast onto the
	#    real face exactly the way leg_reef seats a coral.
	for leg in LEGS:
		for n in FACES:
			var tangent := Vector3(n.z, 0.0, -n.x)
			for row in range(SHALLOW_ROWS):
				var y: float = lerpf(SHALLOW_TOP, SHALLOW_BOTTOM,
					(float(row) + _rng.randf_range(0.15, 0.85)) / float(SHALLOW_ROWS))
				var along: float = _rng.randf_range(-2.2, 2.2)
				var target: Vector3 = Vector3(leg.x, y, leg.y) + n * LEG_HALF + tangent * along
				var hit: Dictionary = _probe(target, n)
				var seat: Vector3 = hit["position"]
				if _blocked(seat):
					continue
				pool.append({"pos": seat, "n": hit["normal"], "y": seat.y, "deep": false})
	return pool

## Fire a ray at the caisson from open water and take the exact seat. Same fallback contract
## as leg_reef._probe: the rig's colliders do not necessarily run the full depth of the
## casting, so a miss falls back to the face SONAR measured (3.000 m from the centre line at
## eight depths) rather than to a guess, and every fallback is counted and reported.
func _probe(target: Vector3, normal: Vector3) -> Dictionary:
	_rays += 1
	if _space != null:
		var q := PhysicsRayQueryParameters3D.create(target + normal * 1.8, target - normal * 0.6)
		q.collision_mask = 1
		var hit: Dictionary = _space.intersect_ray(q)
		if not hit.is_empty():
			return hit
	_fallbacks += 1
	return {"position": target, "normal": normal}

## leg_reef's keep-out list, handed over rather than copied — the dock ladder's climb column
## and the wet-deck swim approach. A shoal parked in the ladder is a shoal in the player's face
## every time they get out of the water.
func _blocked(p: Vector3) -> bool:
	for k in _keep_out:
		if p.distance_to(k["c"]) < float(k["r"]) + 1.2:
			return true
	return false

# ------------------------------------------------------------ assignment

## Hand each species its stations. Three pressures, in order of weight: sit at the depth this
## animal belongs at, do not stack on a colony somebody else already took, and spread the life
## over all four legs so no leg is a desert. A small deterministic jitter breaks ties, because
## a pure argmin puts every species of a similar depth on the same four best colonies.
func _assign(pool: Array) -> void:
	var use: Array[int] = []
	use.resize(pool.size())
	var leg_load: Dictionary = {}
	for sp in SPECIES:
		var mesh_ok: bool = ResourceLoader.exists(MODEL_PATH % [sp["slug"], sp["slug"]])
		if not mesh_ok:
			_missing.append(sp["slug"])
			continue
		var picked: Array = []
		for k in range(int(sp["st"])):
			var best: int = -1
			var best_score: float = 1.0e9
			for i in range(pool.size()):
				var c: Dictionary = pool[i]
				var score: float = absf(float(c["y"]) - float(sp["y"])) * 0.55
				score += float(use[i]) * 1.1
				score += float(leg_load.get(_leg_key(c["pos"]), 0)) * 0.30
				# keep one species' own stations apart, or a "shoal" is really one shoal
				for q in picked:
					if c["pos"].distance_to(q["pos"]) < float(sp["rad"]) * 4.0 + 3.0:
						score += 4.0
						break
				score += _rng.randf() * 0.35
				if score < best_score:
					best_score = score
					best = i
			if best < 0:
				break
			use[best] += 1
			leg_load[_leg_key(pool[best]["pos"])] = int(leg_load.get(_leg_key(pool[best]["pos"]), 0)) + 1
			picked.append(pool[best])
			_build_station(sp, pool[best])

func _leg_key(p: Vector3) -> String:
	var best: Vector2 = LEGS[0]
	var bd: float = 1.0e9
	for leg in LEGS:
		var d: float = absf(p.x - leg.x) + absf(p.z - leg.y)
		if d < bd:
			bd = d
			best = leg
	return "%d_%d" % [int(best.x), int(best.y)]

# ------------------------------------------------------------ building a station

func _build_station(sp: Dictionary, seat: Dictionary) -> void:
	var slug: String = sp["slug"]
	var path: String = MODEL_PATH % [slug, slug]
	var wall: Vector3 = seat["pos"]
	var out_ax: Vector3 = (seat["n"] as Vector3).normalized()
	if absf(out_ax.y) > 0.9:
		out_ax = Vector3(1, 0, 0)
	# Along the face, horizontal. A reef shoal spreads sideways far more than it climbs,
	# which is also true of the coral it lives on (see leg_reef._colony).
	var tan_ax: Vector3 = out_ax.cross(Vector3.UP).normalized()
	var root := Node3D.new()
	root.name = "ReefFish_%s_%d" % [slug, _stations.size()]
	add_child(root)
	root.global_position = wall + out_ax * float(sp["stand"])
	# WHAT IS OVER THIS STATION'S HEAD, measured rather than assumed. The pontoon skirt
	# sleeves all four footings — its underside is at y -3.05 and it spans |z| 8..16, which is
	# exactly where the legs stand — so a shallow station is under a concrete ceiling. A fish's
	# vertical wander reaches 1.8x its species' `vrt`, which is enough to put a yellow tang
	# inside four metres of slab. One ray up per station gets the real ceiling where there is
	# one and the whole water column where there is not, so this stays right if the pontoon
	# ever moves.
	var ceiling: float = 1.0e9
	if _space != null:
		var up_q := PhysicsRayQueryParameters3D.create(root.global_position,
			root.global_position + Vector3.UP * 14.0)
		up_q.collision_mask = 1
		var up_hit: Dictionary = _space.intersect_ray(up_q)
		if not up_hit.is_empty():
			ceiling = float((up_hit["position"] as Vector3).y) - 0.35 - float(sp["len"])

	var count: int = int(sp["n"])
	var members: Array = []
	var phases: Array = []
	var speeds: Array = []
	var heads: Array = []
	var climbs: Array = []
	var slots: Array = []
	var variants: Array = []
	variants.resize(PHASE_VARIANTS)
	var reach: float = clampf(float(sp["len"]) * RANGE_PER_M, RANGE_MIN, RANGE_MAX)
	for i in range(count):
		# A shoal is juveniles-to-adults, not one stamped size repeated N times.
		var scale_v: float = _rng.randf_range(0.78, 1.22)
		var f := Node3D.new()
		root.add_child(f)
		var variant: int = i % PHASE_VARIANTS
		var mats: Array = variants[variant] if variants[variant] != null else []
		if mats.is_empty():
			# First fish on this phase: let CreatureAnim build the materials, then keep them.
			var gen: Dictionary = ANIM.attach(f, path, float(sp["len"]) * scale_v,
				ANIM.Mode.UNDULATE, BASE_AMP, float(sp["pace"]) * 2.0, sp["rim"],
				TAU * float(variant) / float(PHASE_VARIANTS))
			if gen.is_empty():
				f.queue_free()
				continue
			mats = gen["mats"]
			variants[variant] = mats
			for m in mats:
				var sm: ShaderMaterial = m
				# Swap in the reef-fish shader. Every uniform name it needs is one CreatureAnim
				# has already written (a ShaderMaterial holds its parameters by NAME, so they
				# survive the swap), and it adds the one thing the shared shader has no way to
				# do: emission keyed to the fish's own albedo.
				sm.shader = FISH_SHADER
				sm.set_shader_parameter("body_glow", BODY_GLOW)
				sm.set_shader_parameter("glow_color", sp["rim"])
				# `alb` multiplies the imported albedo. Only used where a generated mesh came
				# back the wrong colour for the reef it has to be seen against — see trop_anthias.
				if sp.has("alb"):
					sm.set_shader_parameter("tint", sp["alb"])
		else:
			# Every subsequent fish on this phase re-uses those materials outright. The mesh
			# is the same resource with the same local bounds and the scale lives on the node,
			# so nothing in the shader's per-material state depends on which fish it is.
			if _skin(f, path, float(sp["len"]) * scale_v, mats) == null:
				f.queue_free()
				continue
		_dress(f, reach, slug)
		members.append(f)
		phases.append(_rng.randf() * TAU)
		speeds.append(_rng.randf_range(0.80, 1.30))
		heads.append(_rng.randf() * TAU)
		climbs.append(0.0)
		# A stable seat inside the shoal so the members are spread out to begin with and stay
		# spread — the drift below rides ON this rather than replacing it. Pairs get put on
		# opposite sides of a very small box, which is what makes a butterflyfish pair read as
		# a pair rather than as two fish that happen to share a rock.
		if count == 2:
			slots.append(Vector3(-0.55 + 1.1 * float(i), _rng.randf_range(-0.2, 0.2), _rng.randf()))
		else:
			slots.append(Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0),
				_rng.randf()))
		_built[slug] = int(_built.get(slug, 0)) + 1
	if members.is_empty():
		root.queue_free()
		return
	# Fish start ON their seats. _ready runs inside add_child, so anything that reads a
	# global position at build time gets the world origin (docs/AGENT_TRAPS.md) — these are
	# LOCAL offsets under a root whose global position is already set, which is immune.
	for i in range(members.size()):
		var s: Vector3 = slots[i]
		(members[i] as Node3D).position = tan_ax * s.x * float(sp["rad"]) \
			+ Vector3.UP * s.y * float(sp["vrt"])
	_stations.append({
		"sp": sp, "root": root, "wall": wall, "centre": root.global_position,
		"out": out_ax, "tan": tan_ax,
		"fish": members, "ph": phases, "spd": speeds, "head": heads, "climb": climbs,
		"slot": slots, "mats": variants, "ceil": ceiling,
		"t": _rng.randf_range(0.0, 400.0), "acc": 0.0, "alarm": 0.0, "warm": false,
		"cull2": pow(reach + float(sp["rad"]) + STATION_CULL_PAD, 2.0),
		# A stable per-station number to offset the decimation phase by, so the stations do
		# not all land on the same frame. Taken once, here, rather than looked up per frame.
		"phase": _stations.size() * 7,
		# The wave rate is BUILD STATE, not per-frame state: kept so _tick can re-assert the
		# same number without ever changing it (see BASE_AMP's note on the phase teleport).
		"rate": float(sp["pace"]) * 2.0, "amp": -1.0, "glow": -1.0,
	})

## Build a fish that re-uses an existing station's materials. This is what CreatureAnim.attach
## does minus the material construction: load + scale + parent + apply the authored facing.
## The surface walk order is deterministic for one .glb, so `mats[k]` lands on the surface it
## was made for.
func _skin(host: Node3D, path: String, target_m: float, mats: Array) -> Node3D:
	var model: Node3D = ANIM.load_model(path, target_m)
	if model == null:
		return null
	host.add_child(model)
	var fac: Dictionary = ANIM.facing_for(path)
	model.rotation = Vector3(deg_to_rad(fac["pitch"]), deg_to_rad(fac["yaw"]), 0.0)
	var k: int = 0
	# CreatureAnim's OWN walk, deliberately, rather than a find_children of my own: mats[k]
	# has to land on the surface apply() built it for, and the two orders only stay identical
	# if they are literally the same traversal. (find_children skips the root node, which a
	# .glb whose scene root IS the mesh would have made an off-by-one for.)
	for node in ANIM._mesh_instances(model):
		var mi: MeshInstance3D = node
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			if k < mats.size():
				mi.set_surface_override_material(s, mats[k])
			k += 1
	return model

## Shadows off, GI off, and its own distance budget. Nothing down here casts a useful
## directional shadow — it is 5-20 m under water the sun does not reach — and underwater_world's
## blanket _no_shadows sweep runs in its _ready, long before leg_reef has finished awaiting
## physics frames, so it never reaches this subtree.
func _dress(f: Node3D, reach: float, slug: String) -> void:
	# get_faces() materialises every triangle in the mesh, so the count is paid ONCE per
	# species and multiplied out, not 187 times at build.
	var counted: bool = _slug_tris.has(slug)
	var tris: int = 0
	for node in f.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		if mi.mesh == null:
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.visibility_range_end = reach
		mi.visibility_range_end_margin = reach * 0.18
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if not counted:
			tris += int(mi.mesh.get_faces().size() / 3.0)
	if not counted:
		_slug_tris[slug] = tris
	_tris += int(_slug_tris[slug])

# ------------------------------------------------------------ the swim

func _process(delta: float) -> void:
	# The whole underwater world is hidden whenever the camera is topside, which is most of
	# the game. Hidden means not drawn; it does not mean not simulated, so this is the check
	# that actually makes the topside cost zero.
	if _stations.is_empty() or not is_visible_in_tree():
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	var has_eye: bool = cam != null
	var eye: Vector3 = cam.global_position if has_eye else Vector3.ZERO
	# Reef fish sleep. They tuck into the coral after dark and go still, which is both what
	# the animal does and, conveniently, the cheapest the system ever gets.
	_night = lerpf(_night, 1.0 if BloomFauna.is_dark_phase() else 0.0,
		1.0 - exp(-NIGHT_EASE * delta))
	var frames: int = Engine.get_process_frames()
	for st in _stations:
		var root: Node3D = st["root"]
		var d2: float = eye.distance_squared_to(st["centre"]) if has_eye else 0.0
		var want: bool = d2 <= float(st["cull2"])
		if root.visible != want:
			root.visible = want
		if not want:
			# Frozen, not slowed: the station's clock stops with it and every position here is
			# a function of that clock, so it resumes on exactly the pose it left.
			continue
		st["acc"] += delta
		var acc: float = st["acc"]
		if has_eye and acc < AIB.MAX_STEP and AIB.enabled:
			var stride: int = 1
			if d2 > AIB.MID_M * AIB.MID_M:
				stride = AIB.FAR_STRIDE
			elif d2 > AIB.NEAR_M * AIB.NEAR_M:
				stride = 2
			if stride > 1 and (frames + int(st["phase"])) % stride != 0:
				continue
		st["acc"] = 0.0
		_tick(st, acc, eye, has_eye)

func _tick(st: Dictionary, dt: float, eye: Vector3, has_eye: bool) -> void:
	var sp: Dictionary = st["sp"]
	var bold: bool = bool(sp.get("bold", false))

	# --- DISTURBANCE. Rises fast, falls slow.
	var skit: float = float(sp["skit"])
	var near: float = 0.0
	if has_eye and skit > 0.01:
		near = clampf(1.0 - eye.distance_to(st["centre"]) / skit, 0.0, 1.0)
	var alarm: float = float(st["alarm"])
	alarm = lerpf(alarm, near, 1.0 - exp(-(ALARM_RISE if near > alarm else ALARM_FALL) * dt))
	st["alarm"] = alarm
	var rest: float = _night * float(sp["sleep"])
	# The triggerfish spends its alarm coming OUT at you; everything else spends it going in.
	var duck: float = maxf(0.0 if bold else alarm, rest)

	var stand: float = lerpf(float(sp["stand"]), MIN_STAND, duck * 0.9)
	if bold:
		stand += alarm * 1.2
	var rad: float = float(sp["rad"]) * lerpf(1.0, 0.42, duck)
	var vrt: float = float(sp["vrt"]) * lerpf(1.0, 0.40, duck)
	# Pace: a fleeing shoal is quick, a sleeping one barely moves, and a grazing parrotfish
	# never hurries whatever happens.
	var pace: float = float(sp["pace"]) * lerpf(1.0, 2.1, alarm) * lerpf(1.0, 0.25, rest)
	# THE STATION'S CLOCK IS PACED, NOT MULTIPLIED — the other half of the phase-teleport bug
	# BASE_AMP documents, and this half was in GDScript rather than in a shader. The offsets
	# below used to be sampled at `t * pace` off a raw accumulating clock, so changing `pace`
	# moved the argument of every sine by t * delta_pace: a station is seeded at t up to 400 s
	# and only grows, so the 10% pace change the first hint of alarm produces jumped the wave
	# ~58 radians — a fresh random target every frame while the player walked in, which is
	# white noise, not a flee. Measured before the fix (tests/FaunaBugsProbe, 10-fish damsel
	# shoal, player closing from 12 m to 1.2 m): mean speed 0.13 m/s at alarm 0 -> 1.13 m/s at
	# alarm 0.105, mean |acceleration| 0.2 -> 45 m/s^2, i.e. the shoal detonated at the FIRST
	# TOUCH of alarm rather than accelerating with it. Integrating the paced time instead means
	# pace sets how fast the phase advances and can be changed continuously.
	st["t"] += dt * pace
	var wt: float = st["t"]
	# The standoff is a floor plus a swing that cannot reach it, so wall clearance is
	# STRUCTURAL rather than a clamp. `maxf(out, MIN_STAND)` rectified the sinusoid: with a
	# ducking `stand` at or near MIN_STAND most of a shoal sat on exactly 0.450 m — the probe
	# measured precisely 0.450 at every sample of a 420-frame approach, at every alarm level —
	# with a corner in its velocity every time it arrived on the clamp and left it again.
	var base_out: float = maxf(stand, MIN_STAND + 0.10)
	var span: float = base_out - MIN_STAND

	var wall: Vector3 = st["wall"]
	var out_ax: Vector3 = st["out"]
	var tan_ax: Vector3 = st["tan"]
	var warm: bool = st["warm"]
	var follow: float = 1.0 if not warm else 1.0 - exp(-(FOLLOW * (1.0 + alarm * 1.6)) * dt)
	var turn: float = 1.0 - exp(-TURN * dt)
	st["warm"] = true
	var fish: Array = st["fish"]
	var mph: Array = st["ph"]
	var mspd: Array = st["spd"]
	var mhead: Array = st["head"]
	var mclimb: Array = st["climb"]
	var mslot: Array = st["slot"]
	# A grazing parrotfish rides the wall, nose to the concrete, and the whole pair drifts
	# along it — so its out-offset is small and its vertical wander is a slow scrub.
	var graze: bool = bool(sp.get("graze", false))
	var ceiling: float = float(st["ceil"])
	for i in range(fish.size()):
		var f: Node3D = fish[i]
		var ph: float = mph[i]
		var spd: float = mspd[i]
		var slot: Vector3 = mslot[i]
		# TWO INCOMMENSURATE OCTAVES PER AXIS, riding a fixed seat in the shoal. The seat is
		# what keeps the school spread out and anchored; the octaves are what stop it reading
		# as a formation. Neither is a waypoint, so there is no path to get lost off.
		var along: float = slot.x * rad \
			+ (sin(wt * 0.31 * spd + ph) * 0.55 + sin(wt * 0.13 + ph * 1.7) * 0.35) * rad
		var up: float = slot.y * vrt \
			+ (sin(wt * 0.23 * spd + ph * 1.3) * 0.50 + sin(wt * 0.09 + ph) * 0.30) * vrt
		# MIN_STAND is the floor and `span` is all the room there is above it, so no fish can
		# be inside the concrete however hard it ducks and nothing has to be clamped: the
		# multiplier below runs 0.25..1.20, never negative. The overhead pontoon slab is still
		# a clamp, but that one is a fixed number per station rather than a moving target.
		var out: float = MIN_STAND + span * (0.45 + slot.z * 0.55
			+ sin(wt * (0.11 if graze else 0.19) * spd + ph * 2.1) * 0.20)
		var target: Vector3 = wall + tan_ax * along + Vector3.UP * up + out_ax * out
		target.y = minf(target.y, ceiling)
		# --- SPACING, station-mates only — the term this system never had. Each fish's
		# along/up/out are independent noise off its own seed, so nothing ever stopped two
		# shoal-mates drifting into the same water and swimming inside each other, which is
		# most of why a shoal read as a render bug rather than a living thing up close.
		# A soft short-range push on the TARGET (never the position — the ease below stays
		# the only mover): inside SEP_M of a station-mate, the target slides apart with a
		# falloff. n is at most 11 (anthias), so this is <= 55 distance checks per station
		# per thinking-frame, only for stations already inside the cull and AI budget.
		# The butterfly PAIR gets the opposite term as well — its species note promises
		# "within a body length of each other all game", the seed put them there and
		# nothing ever held them: past PAIR_M the partners are pulled gently back in.
		for j in range(fish.size()):
			if j == i:
				continue
			var od: Vector3 = target - (fish[j] as Node3D).global_position
			var d: float = od.length()
			if d < 0.001:
				target += tan_ax * (0.05 if i > j else -0.05)
			elif d < SEP_M:
				target += od * ((SEP_M - d) / SEP_M) * 0.6
		if fish.size() == 2:
			var pd: Vector3 = (fish[1 - i] as Node3D).global_position - target
			if pd.length() > PAIR_M:
				target += pd.normalized() * (pd.length() - PAIR_M) * 0.5
		target.y = minf(target.y, ceiling)
		var cur: Vector3 = f.global_position
		var nxt: Vector3 = cur.lerp(target, follow)
		var step: Vector3 = nxt - cur
		f.global_position = nxt
		if not warm:
			continue
		# THE HEADING IS REMEMBERED, NOT RE-DERIVED — pointing a fish straight down its last
		# step is what made the pelagic shoals snap their heads around before s18. A hovering
		# fish keeps the heading it had rather than chasing numerical noise.
		var speed: float = step.length() / maxf(dt, 0.0001)
		if speed > HEAD_MIN_SPEED:
			mhead[i] = lerp_angle(mhead[i], atan2(step.x, step.z), turn)
		mclimb[i] = lerpf(mclimb[i], clampf(step.y / maxf(dt, 0.0001) * PITCH, -0.5, 0.5), turn)
		var hd: float = mhead[i]
		f.look_at(nxt + Vector3(sin(hd), mclimb[i], cos(hd)), Vector3.UP)

	# --- THE SHARED MATERIALS, driven per STATION rather than per fish. This is ~3 writes for
	# a 16-fish anthias cloud, and only for the stations that are actually near enough to be
	# ticking at all. The rim glow flares as the shoal scatters — the flash of colour a real
	# reef gives you when something big swims through it — and dims right down at night.
	# `rate` is re-asserted at its BUILD value and is never allowed to change (BASE_AMP's note
	# has the arithmetic). What the alarm actually moves is the throw of the tail and the rim
	# glow, both plain multipliers outside the sine, so the shoal can flare continuously.
	var want_amp: float = BASE_AMP * lerpf(1.0, ALARM_AMP, alarm) * lerpf(1.0, REST_AMP, rest)
	var want_glow: float = float(sp["glow"]) * lerpf(1.0, 1.9, alarm) * lerpf(1.0, 0.35, rest)
	if absf(want_amp - float(st["amp"])) > 0.0008 or absf(want_glow - float(st["glow"])) > 0.01:
		st["amp"] = want_amp
		st["glow"] = want_glow
		for v in st["mats"]:
			if v != null:
				ANIM.drive(v, float(st["rate"]), want_glow, want_amp)

# ------------------------------------------------------------ report

## Numbers, not impressions — this is what the session reports and what ReefFishProbe
## re-derives independently from the built tree.
func _report() -> void:
	var fish: int = 0
	for slug in _built.keys():
		fish += int(_built[slug])
	var mats: int = 0
	for st in _stations:
		for v in st["mats"]:
			if v != null:
				mats += (v as Array).size()
	print("[reef_fish] %d fish · %d stations · %d species · %d tris · %d ShaderMaterials"
		% [fish, _stations.size(), _built.size(), _tris, mats])
	for sp in SPECIES:
		var slug: String = sp["slug"]
		if not _built.has(slug):
			continue
		var st_n: int = 0
		var depth_lo: float = 1.0e9
		var depth_hi: float = -1.0e9
		for st in _stations:
			if st["sp"]["slug"] != slug:
				continue
			st_n += 1
			depth_lo = minf(depth_lo, float(st["centre"].y))
			depth_hi = maxf(depth_hi, float(st["centre"].y))
		print("[reef_fish]   %-17s %3d fish in %d stations, y %.1f..%.1f — %s"
			% [slug, int(_built[slug]), st_n, depth_hi, depth_lo, sp["note"]])
	if not _missing.is_empty():
		push_warning("[reef_fish] no mesh for: %s" % ", ".join(_missing))
		print("[reef_fish] MISSING MESHES (species dropped): %s" % ", ".join(_missing))
	print("[reef_fish] shallow seating rays %d, of which %d fell back to the sonar face"
		% [_rays, _fallbacks])

## What ReefFishProbe reads. Live state, not a copy of the build-time plan.
func census() -> Array:
	var out: Array = []
	for st in _stations:
		var pos: Array = []
		for f in st["fish"]:
			pos.append((f as Node3D).global_position)
		out.append({"slug": st["sp"]["slug"], "wall": st["wall"], "out": st["out"],
			"centre": st["centre"], "rad": float(st["sp"]["rad"]),
			"vrt": float(st["sp"]["vrt"]), "ceil": float(st["ceil"]),
			"stand": float(st["sp"]["stand"]), "len": float(st["sp"]["len"]), "fish": pos})
	return out
