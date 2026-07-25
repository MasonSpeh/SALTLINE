class_name FishTable extends RefCounted
## Single source of truth for everything fish: loads data/fish.json and answers
## the same questions for the rod, the drop net, the stove, and the visible
## underwater schools — so what swims, what bites, and what the Angler's Notes
## say can never disagree.
##
## Catch context variables (built by context()):
##   phase    — dawn | day | dusk | night          (GameClock)
##   storming — a squall is on                     (StormSystem)
##   lit      — night/dusk + floodlights powered   (PowerGrid: worklight water)
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
static func context(node: Node, spot: Vector3) -> Dictionary:
	var phase: String = "day"
	match GameClock.current_phase:
		GameClock.Phase.DAWN: phase = "dawn"
		GameClock.Phase.DUSK: phase = "dusk"
		GameClock.Phase.NIGHT: phase = "night"
	var storming: bool = false
	var scene: Node = node.get_tree().current_scene
	if scene and scene.get("storm") != null and scene.storm != null:
		storming = scene.storm.is_storming()
	var dark: bool = phase == "night" or phase == "dusk"
	var lit: bool = dark and PowerGrid.is_powered("topside_floodlights")
	# Distance from the rig's deck rectangle (x -32..32, z -24..24) in the XZ plane.
	var dx: float = maxf(absf(spot.x) - 32.0, 0.0)
	var dz: float = maxf(absf(spot.z) - 24.0, 0.0)
	var rim_dist: float = Vector2(dx, dz).length()
	return {"phase": phase, "storming": storming, "lit": lit, "open": rim_dist > 10.0}

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
	match def.get("water", "any"):
		"near":
			if ctx["open"]:
				w *= 0.15
		"open":
			if not ctx["open"]:
				w *= 0.15
	if def.get("light", "any") == "drawn" and ctx["lit"]:
		w *= 2.0
	# Depth, for the deep-drop rig only: a fish that lives at 44 m never sees a bait
	# dangling at 12, and one that lives at 8 loses interest as the bait sinks past it.
	if depth_m >= 0.0:
		var drop: float = float(def.get("drop_m", 0.0))
		if depth_m < drop:
			return 0.0
		w /= 1.0 + (depth_m - drop) * DROP_FADE_PER_M
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
	if ctx["lit"]:
		bits.append("worklight glow")
	return " · ".join(bits)

## Bite cadence multiplier: storms are a frenzy, dawn/dusk are feeding hours.
static func bite_pace(ctx: Dictionary) -> float:
	var pace: float = 1.0
	if ctx["storming"]:
		pace *= 0.55
	if ctx["phase"] == "dawn" or ctx["phase"] == "dusk":
		pace *= 0.75
	return pace
