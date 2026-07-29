class_name FishTable extends RefCounted
## Single source of truth for everything fish: loads data/fish.json and answers
## the same questions for the rod, the drop net, the stove, and the visible
## underwater schools — so what swims, what bites, and what the Angler's Notes
## say can never disagree.
##
## Catch context variables (built by context()):
##   phase    — dawn | day | dusk | night          (GameClock)
##   storming — a squall is on                     (StormSystem.is_storming)
##   raining  — weather in the water but NOT a squall: the ramp in and the long ramp out
##              either side of every storm (StormSystem.rain_level, below the squall
##              threshold). A real THIRD weather state, not a synonym for storming — a
##              species can want the drizzle and refuse the gale, or the reverse.
##   fogged   — the sea fog a squall leaves behind (StormSystem.fog_level). Rolls after
##              ~55% of squalls and hangs for two to four minutes: the rarest weather on
##              this water, and where the rarest things in it surface.
##   lit      — night/dusk + floodlights powered   (PowerGrid: worklight water)
##   powered  — floodlights on AT ALL, hour irrelevant. Kept separate from `lit` because
##              `lit` is "there is a glow ON THE WATER", which needs the dark; a light-shy
##              species is spooked by the rig burning whether or not it is night.
##   open     — the spot is >10m off the rig rim   (cast distance matters)
##
## Three fields exist only for the DEEP-DROP RIG and the size→yield economy, and all
## three live in data/fish.json with everything else:
##   drop_m  — how far the lead has to sink before this species will look at the bait
##   size_kg — [min, max] landed weight; one weight is rolled per catch
##   fillets — [min, max] portions the stove / drying line get out of ONE fish, by size

## Past its own drop depth a species thins out as the bait sinks below its water: a
## species is at full weight the moment the lead reaches it and at half weight ~29 m
## below. This — not a hand-written table of depth bands — is what makes a long drop
## skew the pool deep, so the ladder of drop_m values in fish.json is the only tuning
## surface for "how deep do I have to go for a grouper".
const DROP_FADE_PER_M: float = 0.035

## ---------------------------------------------------------------- weather, in three tiers
## StormSystem carries ONE continuous number (_intensity, 0..1) and used to expose exactly
## one boolean off it — is_storming(), >0.25. Everything between "the glass is falling" and
## "it is a squall" was therefore invisible to the table, which is why every species could
## only ever be a calm fish or a storm fish. RAIN_MIN is the other end of that band: at or
## above it there is weather in the water, and below the squall flag that weather is RAIN.
##   calm  — intensity < RAIN_MIN
##   rain  — RAIN_MIN <= intensity, is_storming() false   (the ramp in, the long ramp out)
##   storm — is_storming()
## The three are mutually exclusive by construction, so `storm` keeps its exact old meaning
## and nothing already tuned against it moves.
const RAIN_MIN: float = 0.06
## Sea fog reads as "there is a bank on the water" at the same sort of threshold.
const FOG_MIN: float = 0.25

## Weight multipliers for the two weather tiers a species can want or refuse. The storm
## numbers are UNCHANGED (they are inline in weight_for and always were); these are the
## rain tier's, deliberately gentler — rain shifts the odds, a squall rearranges them.
const RAIN_BONUS: float = 2.0
const RAIN_ONLY_FLOOR: float = 4.0
const RAIN_ONLY_MULT: float = 2.5
const FOG_BONUS: float = 3.0
const FOG_ONLY_FLOOR: float = 4.0
const FOG_ONLY_MULT: float = 3.0

## What the floodlights do to a species that does not want them. `light: "drawn"` has
## always doubled a catch in lit water; SHY is its mirror — a fish that will not come up
## into a rig burning its worklights, so killing the power at the breaker is a fishing
## decision and not only a fuel one. Judged on `powered`, not `lit`: the lights being on
## is the fact, and it is a fact at noon too.
const LIGHT_SHY_MULT: float = 0.15

## ---------------------------------------------------------------- what counts as BIG
## The rod needs to know, at the instant something takes the bait, whether this is a
## nothing-fish or the one you will remember — that is what the controller jolt and the
## screen flash are for (fishing_rod._big_bite_feedback). No new field was invented for it:
## the table already carries two independent statements of "this animal is big", and a
## species only has to make one of them.
##   size_kg[1] >= TROPHY_KG — the landed WEIGHT tier. 20 kg picks up the grouper (48),
##       the halibut (70), the coelacanth (35), the oarfish (85) and the sturgeon (95) and
##       leaves the abyss grenadier (16 kg top) out with the ordinary catches, which is
##       where a 5-16 kg rattail belongs.
##   pull >= TROPHY_PULL — the FIGHT tier, for the deep species that carry no weight range
##       at all (the gulper eel pulls 1.7 and would otherwise read as a sprat to this test).
## Everything shallow and small — sprat 0.4, blenny 0.35, herring 0.65 — is far under both.
const TROPHY_KG: float = 20.0
const TROPHY_PULL: float = 1.6

## ---------------------------------------------------------------- bait
## WHAT IS ON THE HOOK CHANGES WHAT LOOKS AT IT. Bait is the deep rig's alone (the surface
## rod fishes bare — see fishing_rod.gd), and until now every legal bait fished identically:
## the hook was either armed or it wasn't. This is the one table that says otherwise, and it
## is deliberately a table of EXCEPTIONS — a bait with no entry here is BAIT_NEUTRAL and
## behaves exactly as it always did, so nothing about the existing baits is retuned.
##
## Per entry:
##   deep_from — the species drop_m at or past which this bait is in its element
##   deep      — weight multiplier for species that live at/below deep_from
##   shallow   — weight multiplier for species shallower than that
##   drawn     — extra multiplier for species with light "drawn", i.e. the ones fish.json
##               already marks as coming to a light. A glowing worm is a lure as much as a
##               meal, so this is where the bioluminescence actually pays.
##   rate      — bite-clock multiplier once the lead is past deep_from (>1 = bites sooner);
##               rate_shallow applies above it. Read live off the current depth by
##               bait_rate(), so a glow worm starts working as the lead sinks INTO the dark.
const BAIT_NEUTRAL := {"deep_from": 0.0, "deep": 1.0, "shallow": 1.0, "drawn": 1.0,
	"rate": 1.0, "rate_shallow": 1.0}
const BAIT_TABLE := {
	# GLOW WORM. Harvested off the dens in the rig's dark corners (bloom_fauna.gd) and, on a
	# hook, the only bait that supplies its own light. Its niche is the black water past
	# 24 m — the drop_m band where the rare deep species start (grenadier 24, hagfish 28,
	# gulper 34, dragonfish 38, oarfish 42, sturgeon 44) — where it nearly doubles their
	# share of the roll and brings the bite on a third sooner. Above that it is a small
	# soft-bodied worm competing with cut fish, and it fishes worse than one.
	"glow_worm": {"deep_from": 24.0, "deep": 1.9, "shallow": 0.7, "drawn": 1.6,
		"rate": 1.35, "rate_shallow": 0.75},
	# Seared, it stops glowing. Still edible, still legal bait, no lure left in it.
	"glow_worm_cooked": {"deep_from": 24.0, "deep": 1.15, "shallow": 0.85, "drawn": 1.0,
		"rate": 1.0, "rate_shallow": 1.0},
	# CRAB LEG. A knuckle of shell and tendon: it does not wash off the hook and it does not
	# interest anything that can't crush it. That makes it the heavy end of the bait ladder —
	# poor on the shelf, where every small mouth ignores it, and the thing the armoured
	# bottom feeders come to. Slow: a bait nothing nibbles takes longer to be found.
	"crab_leg": {"deep_from": 16.0, "deep": 1.7, "shallow": 0.55, "drawn": 0.9,
		"rate": 0.85, "rate_shallow": 0.7},
	# ROTTEN CHUM. Scent, not substance. It works the WHOLE column — a smell spreads — so its
	# pool skew is mild and its real payment is the CLOCK: things find a rotten bait fast at
	# any depth. The one bait that shortens the wait everywhere.
	"fish_rotten": {"deep_from": 0.0, "deep": 1.15, "shallow": 1.15, "drawn": 0.85,
		"rate": 1.45, "rate_shallow": 1.45},
	# LIVE SNAIL. Small, soft, and it moves — the shallow shelf's best bait and a waste of a
	# drop below the cold. Mirror image of the crab leg.
	# LIVE SNAIL. Small, soft, and it moves — the shelf's best bait and a waste of a drop
	# below the cold. Mirror image of the crab leg, and deep_from is set one rung BELOW the
	# crab leg's so the two never both count as "shallow" for the same species: everything
	# down to the coelacanth's 20 m is snail water, everything at 24 m and past it is not.
	"snail_live": {"deep_from": 24.0, "deep": 0.6, "shallow": 1.55, "drawn": 1.0,
		"rate": 0.95, "rate_shallow": 1.2},
}

## A SPECIES' OWN opinion of what is on the hook: data/fish.json `bait` map, {bait_id: mult}.
## BAIT_TABLE above says what a bait is like in general (deep or shallow, fast or slow);
## this says who specifically wants it, and it is the layer that makes a bait choice
## LEARNABLE — "the hagfish wants rotten meat" is a fact a player can be told, test, and
## keep. Absent entry = 1.0, so every species without an opinion fishes as it always did.
static func bait_pref(bait_id: String, def: Dictionary) -> float:
	if bait_id == "":
		return 1.0
	var prefs: Variant = def.get("bait")
	if not (prefs is Dictionary):
		return 1.0
	return float((prefs as Dictionary).get(bait_id, 1.0))

static func bait_def(bait_id: String) -> Dictionary:
	return BAIT_TABLE.get(bait_id, BAIT_NEUTRAL)

## How this bait skews ONE species' share of the roll. Keyed off the species' own drop_m —
## not off how far the lead happens to have sunk — because a uniform multiplier over the
## whole pool would cancel out in the weighted draw and change nothing at all. This is what
## makes a glow worm a DEEP bait rather than just a good one.
static func bait_mult(bait_id: String, def: Dictionary) -> float:
	if bait_id == "" or not BAIT_TABLE.has(bait_id):
		return 1.0
	var b: Dictionary = BAIT_TABLE[bait_id]
	var m: float = float(b["deep"]) if float(def.get("drop_m", 0.0)) >= float(b["deep_from"]) \
		else float(b["shallow"])
	if def.get("light", "any") == "drawn":
		m *= float(b["drawn"])
	return m

## Bite-clock multiplier for the bait currently on the hook at the depth the lead is at
## right now. 1.0 for no bait and for every bait without a table entry.
static func bait_rate(bait_id: String, depth_m: float) -> float:
	if bait_id == "" or not BAIT_TABLE.has(bait_id):
		return 1.0
	var b: Dictionary = BAIT_TABLE[bait_id]
	return float(b["rate"]) if depth_m >= float(b["deep_from"]) else float(b["rate_shallow"])

static var _data: Dictionary = {}
## Shallowest drop_m in the deep pool, computed once — see min_drop_depth().
static var _min_drop: float = -1.0

static func all() -> Dictionary:
	if _data.is_empty():
		var f: FileAccess = FileAccess.open("res://data/fish.json", FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed
				_data.erase("_schema")
	return _data

## Build the catch context for a fishing spot (world position of float/net).
##
## `bait` is the item id on the hook, and only the deep rig ever passes one — the surface
## rod and the drop net leave it "" and roll exactly as they always have. It rides in the
## context dict rather than in a fourth argument to weight_for() because it is a fact about
## the SPOT, the same as the phase and the weather.
static func context(node: Node, spot: Vector3, bait: String = "") -> Dictionary:
	var phase: String = "day"
	match GameClock.current_phase:
		GameClock.Phase.DAWN: phase = "dawn"
		GameClock.Phase.DUSK: phase = "dusk"
		GameClock.Phase.NIGHT: phase = "night"
	var storming: bool = false
	var raining: bool = false
	var fogged: bool = false
	var scene: Node = node.get_tree().current_scene
	if scene and scene.get("storm") != null and scene.storm != null:
		var storm: Object = scene.storm
		storming = storm.is_storming()
		# rain_level()/fog_level() are recent additions to StormSystem; has_method() keeps a
		# stale scene (or a test double standing in for the storm) from taking the roll down.
		if not storming and storm.has_method("rain_level"):
			raining = float(storm.rain_level()) >= RAIN_MIN
		if storm.has_method("fog_level"):
			fogged = float(storm.fog_level()) >= FOG_MIN
	var dark: bool = phase == "night" or phase == "dusk"
	var powered: bool = PowerGrid.is_powered("topside_floodlights")
	var lit: bool = dark and powered
	# Distance from the rig's deck rectangle (x -32..32, z -24..24) in the XZ plane.
	var dx: float = maxf(absf(spot.x) - 32.0, 0.0)
	var dz: float = maxf(absf(spot.z) - 24.0, 0.0)
	var rim_dist: float = Vector2(dx, dz).length()
	return {"phase": phase, "storming": storming, "raining": raining, "fogged": fogged,
		"lit": lit, "powered": powered, "open": rim_dist > 10.0, "bait": bait}

## Weight of one species under a context, for "rod", "net" or "deep". Zero = can't catch.
##
## depth_m is how far the deep rig's lead has sunk, in metres below the surface; leave it
## negative (the default) and depth is not consulted at all, so the surface rod and the
## drop net roll exactly as they always have.
static func weight_for(id: String, kind: String, ctx: Dictionary, depth_m: float = -1.0) -> float:
	var def: Dictionary = all().get(id, {})
	if def.is_empty() or not def.get(kind, false):
		return 0.0
	var w: float = float(def["w"].get(ctx["phase"], 0))
	match def.get("storm", "ok"):
		"only":
			w = maxf(w, 4.0) * 3.0 if ctx["storming"] else 0.0
		"never":
			if ctx["storming"]:
				w = 0.0
		"bonus":
			if ctx["storming"]:
				w *= 2.0
	# RAIN, the tier between calm and squall. Every ctx read below uses .get() with the old
	# behaviour as the default, so a context built before these axes existed — the drop net's,
	# the test runner's hand-written dicts — rolls exactly as it always has.
	var raining: bool = bool(ctx.get("raining", false))
	match def.get("rain", "ok"):
		"only":
			w = maxf(w, RAIN_ONLY_FLOOR) * RAIN_ONLY_MULT if raining else 0.0
		"never":
			if raining:
				w = 0.0
		"bonus":
			if raining:
				w *= RAIN_BONUS
	# SEA FOG, the rarest weather this water makes.
	var fogged: bool = bool(ctx.get("fogged", false))
	match def.get("fog", "ok"):
		"only":
			w = maxf(w, FOG_ONLY_FLOOR) * FOG_ONLY_MULT if fogged else 0.0
		"never":
			if fogged:
				w = 0.0
		"bonus":
			if fogged:
				w *= FOG_BONUS
	match def.get("water", "any"):
		"near":
			if ctx["open"]:
				w *= 0.15
		"open":
			if not ctx["open"]:
				w *= 0.15
	match def.get("light", "any"):
		"drawn":
			if ctx["lit"]:
				w *= 2.0
		"shy":
			# The mirror of drawn: kill the floodlights and this one comes up. Falls back to
			# `lit` for a context that predates the `powered` key, so nothing reads as
			# unlit-and-therefore-safe just because the dict is old.
			if bool(ctx.get("powered", ctx.get("lit", false))):
				w *= LIGHT_SHY_MULT
	# Depth, for the deep-drop rig only: a fish that lives at 44 m never sees a bait
	# dangling at 12, and one that lives at 8 loses interest as the bait sinks past it.
	if depth_m >= 0.0:
		var drop: float = float(def.get("drop_m", 0.0))
		if depth_m < drop:
			return 0.0
		w /= 1.0 + (depth_m - drop) * DROP_FADE_PER_M
	# ...and last, what is actually on the hook: what KIND of bait it is (BAIT_TABLE), then
	# whether this particular animal wants it (the species' own `bait` map). .get() with a
	# default so a context built before bait existed (or by the net, which has none) is
	# untouched.
	var bait_id: String = String(ctx.get("bait", ""))
	w *= bait_mult(bait_id, def)
	w *= bait_pref(bait_id, def)
	return w

## Every species that can be caught right now, as [[id, weight], ...]. Shared by roll()
## and pool_weight() so "what would bite" and "is anything down there at all" can never
## answer differently.
static func _pool(kind: String, ctx: Dictionary, depth_m: float) -> Array:
	var pool: Array = []
	for id in all():
		var w: float = weight_for(id, kind, ctx, depth_m)
		if w > 0.0:
			pool.append([id, w])
	return pool

## Weighted roll over the table. Returns {id: ..., plus the species def} or {}.
static func roll(kind: String, ctx: Dictionary, rng: RandomNumberGenerator, depth_m: float = -1.0) -> Dictionary:
	var pool: Array = _pool(kind, ctx, depth_m)
	if pool.is_empty():
		return {}
	var total: float = 0.0
	for entry in pool:
		total += float(entry[1])
	var r: float = rng.randf_range(0.0, total)
	for entry in pool:
		r -= entry[1]
		if r <= 0.0:
			var out: Dictionary = all()[entry[0]].duplicate()
			out["id"] = entry[0]
			return out
	var last: Dictionary = all()[pool[-1][0]].duplicate()
	last["id"] = pool[-1][0]
	return last

## Is anything at all catchable here? The deep rig asks this at the end of its spool: a
## lead that ran out of line above every species' water is fishing an empty ocean, and
## the player deserves to be told that rather than left waiting on a bite that cannot come.
static func pool_weight(kind: String, ctx: Dictionary, depth_m: float = -1.0) -> float:
	var total: float = 0.0
	for entry in _pool(kind, ctx, depth_m):
		total += float(entry[1])
	return total

## Shallowest depth (m below the surface) at which ANYTHING in the deep pool will look at
## a bait — how far the lead must fall before the line is fishing at all. Read off the
## table (once, then cached) so the ladder of drop depths stays data, not a rod constant.
static func min_drop_depth() -> float:
	if _min_drop < 0.0:
		var lowest: float = 1.0e9
		for id in all():
			var def: Dictionary = all()[id]
			if def.get("deep", false):
				lowest = minf(lowest, float(def.get("drop_m", 0.0)))
		_min_drop = 0.0 if lowest > 1.0e8 else lowest
	return _min_drop

## Plain-words name for the water the lead has reached, so the depth readout on the deep
## line teaches the ladder instead of just counting metres.
static func depth_read(depth_m: float) -> String:
	if depth_m < 8.0:
		return "still in the light"
	if depth_m < 16.0:
		return "the green"
	if depth_m < 28.0:
		return "the cold shelf"
	if depth_m < 40.0:
		return "the black"
	return "the trench"

# ------------------------------------------------------------------ size and yield
## A landed fish has a WEIGHT, and a big fish fillets out into many portions — that is
## the whole payoff of the deep rig. The inventory is item ids and stack counts and
## NOTHING else (PlayerState has no per-item payload, and the save file stores none), so
## the weight rolled at the rail is kept here, in the table that already owns every other
## fish fact: one FIFO queue of landed weights per species. The stove and the drying line
## pop one when they preserve that species.
##
## A missing entry — a reloaded save, a fish out of a locker, a netted halibut — simply
## rolls a fresh weight from the same range, so the fillet spread always holds. The only
## thing a reload can lose is WHICH particular fish in the pack was the 40 kg one.
static var _sizes: Dictionary = {}

## A fresh landed weight in kg for one fish of this species; 0.0 = species has no size.
static func roll_size(id: String, rng: RandomNumberGenerator) -> float:
	var s: Array = all().get(id, {}).get("size_kg", [])
	if s.size() < 2:
		return 0.0
	# Skewed toward the small end: a monster is meant to be a story, not a Tuesday.
	var t: float = rng.randf() * rng.randf()
	return lerpf(float(s[0]), float(s[1]), t)

## Remember a weight just landed, so the stove and the line can find it later.
static func record_size(id: String, kg: float) -> void:
	if kg <= 0.0:
		return
	if not _sizes.has(id):
		_sizes[id] = []
	(_sizes[id] as Array).append(kg)

## Take the oldest remembered weight for this species, or roll a fresh one if we never
## saw it landed. 0.0 for a species with no size range.
static func take_size(id: String, rng: RandomNumberGenerator) -> float:
	var q: Array = _sizes.get(id, [])
	if not q.is_empty():
		var kg: float = float(q[0])
		q.remove_at(0)
		if q.is_empty():
			_sizes.erase(id)
		return kg
	return roll_size(id, rng)

## Portions one fish of this weight gives up: the species' fillet range, walked across
## its own weight range. 1 for everything that has no fillet data — which is every
## ordinary fish, so the stove and the line keep converting one raw into one cooked.
static func fillets_for(id: String, kg: float) -> int:
	var def: Dictionary = all().get(id, {})
	var f: Array = def.get("fillets", [])
	if f.size() < 2:
		return 1
	var lo: int = maxi(int(f[0]), 1)
	var hi: int = maxi(int(f[1]), lo)
	var s: Array = def.get("size_kg", [])
	if kg <= 0.0 or s.size() < 2 or float(s[1]) <= float(s[0]):
		return lo
	var t: float = clampf((kg - float(s[0])) / (float(s[1]) - float(s[0])), 0.0, 1.0)
	return clampi(roundi(lerpf(float(lo), float(hi), t)), lo, hi)

## True for a species big enough to be worth the salt: it fillets out into more than one
## portion, and on a drying line it CURES straight from raw instead of turning. Everything
## without a fillets range in fish.json is an ordinary fish and behaves as it always did.
static func is_big(id: String) -> bool:
	var f: Array = all().get(id, {}).get("fillets", [])
	return f.size() >= 2 and int(f[1]) > 1

## True for a species worth JUMPING at — the weight tier or the fight tier, see TROPHY_KG /
## TROPHY_PULL above. Distinct from is_big(), which asks a kitchen question (does it fillet
## out?); this asks a rail question (is the thing on the end of my line a monster?).
static func is_trophy(id: String) -> bool:
	var def: Dictionary = all().get(id, {})
	if def.is_empty():
		return false
	var s: Array = def.get("size_kg", [])
	if s.size() >= 2 and float(s[1]) >= TROPHY_KG:
		return true
	return float(def.get("pull", 0.0)) >= TROPHY_PULL

## One call for the preserving paths (stove, drying line): what this fish weighed and
## how many portions it makes. {"kg": float (0.0 = unsized species), "n": int >= 1}.
static func take_yield(id: String, rng: RandomNumberGenerator) -> Dictionary:
	var kg: float = take_size(id, rng)
	return {"kg": kg, "n": fillets_for(id, kg)}

## What a raw catch sears into ("" = not cookable / never kept).
static func cooked_for(id: String) -> String:
	return all().get(id, {}).get("cooked_to", "")

## One-line water read shown when the line goes out — the conditions, in plain
## words, so the player learns the variables by fishing them.
static func summary(ctx: Dictionary) -> String:
	var bits: Array[String] = [ctx["phase"], "open water" if ctx["open"] else "rig shadow"]
	if ctx["storming"]:
		bits.append("storm sea — something's feeding")
	elif bool(ctx.get("raining", false)):
		bits.append("rain on the water")
	if bool(ctx.get("fogged", false)):
		bits.append("fog bank")
	if ctx["lit"]:
		bits.append("worklight glow")
	elif bool(ctx.get("powered", false)):
		bits.append("floodlights up")
	return " · ".join(bits)

## Bite cadence multiplier: storms are a frenzy, rain is brisk, dawn/dusk are feeding hours.
static func bite_pace(ctx: Dictionary) -> float:
	var pace: float = 1.0
	if ctx["storming"]:
		pace *= 0.55
	elif bool(ctx.get("raining", false)):
		pace *= 0.8
	if ctx["phase"] == "dawn" or ctx["phase"] == "dusk":
		pace *= 0.75
	return pace
