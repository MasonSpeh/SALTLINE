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

static var _data: Dictionary = {}

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

## Weight of one species under a context, for "rod" or "net". Zero = can't catch.
static func weight_for(id: String, kind: String, ctx: Dictionary) -> float:
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
	return w

## Weighted roll over the table. Returns {id: ..., plus the species def} or {}.
static func roll(kind: String, ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = []
	var total: float = 0.0
	for id in all():
		var w: float = weight_for(id, kind, ctx)
		if w > 0.0:
			pool.append([id, w])
			total += w
	if pool.is_empty():
		return {}
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
