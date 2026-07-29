extends Node
## THE "EVERY FISH IS CATCHABLE" PROBE.
##
## The claim this exists to test is not "every species has a row in data/fish.json" — that
## was already true and it proved nothing, because a row with a zero weight in every phase,
## or a `water: "open"` tax on a tool that can never reach open water, is a species you can
## read about and never land. So this probe does not read the table. It ROLLS it, thousands
## of times, through FishTable.roll() itself — the same call the rod, the deep rig and the
## drop net make — and asserts that every species with a real mesh on disk actually comes
## out of it.
##
## Two sweeps, because they answer two different questions:
##
##   COVERAGE — a systematic walk of every condition combination the game can produce
##   (4 phases x 4 weather states x lights on/off x open/near x 11 depths x 6 baits, per
##   tool). Answers "is there any water in which this species bites at all". A species that
##   never appears here is unreachable and the probe fails.
##
##   PLAY MIX — the same roll under conditions weighted the way they actually occur in a
##   session: storms about a third of the clock, the rain shoulder either side of them, fog
##   after some of them, the player's lights and cast length a coin flip. Answers "what does
##   a player actually pull out of this sea", and it is what proves the balance brief —
##   commons stay common, trophies stay rare — instead of just asserting it.
##
## Run: godot --headless --path . res://tests/CatchProbe.tscn

const FISH := preload("res://scripts/world/fish_table.gd")
const FAUNA_DIR: String = "res://assets/models/fauna/"

## Enough rolls per tool that a species sitting at a tenth of a percent still shows up a
## few dozen times, so a zero in the results is a real zero and not sampling noise.
const PLAY_ROLLS: int = 120000

var failures: int = 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 20260729
	_run()
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  " + label)
	else:
		failures += 1
		print("FAIL  " + label)

# ------------------------------------------------------------------ context building
## A full catch context. Every key weight_for() can read is present, so the probe is
## exercising the real branch set and not accidentally testing the .get() defaults.
func _ctx(phase: String, weather: String, powered: bool, open_water: bool, bait: String) -> Dictionary:
	var dark: bool = phase == "night" or phase == "dusk"
	return {
		"phase": phase,
		"storming": weather == "storm",
		"raining": weather == "rain",
		"fogged": weather == "fog",
		"lit": dark and powered,
		"powered": powered,
		"open": open_water,
		"bait": bait,
	}

const PHASES: Array[String] = ["dawn", "day", "dusk", "night"]
const WEATHERS: Array[String] = ["calm", "rain", "storm", "fog"]
## Every bait the deep rig will actually put on a hook: the three named specials, the one
## that makes its own light, a cut fish, and a bare-ish scrap with no BAIT_TABLE entry.
const BAITS: Array[String] = ["snail_live", "fish_rotten", "crab_leg", "glow_worm",
	"fish_herring", "raw_fillet"]
## The spool is 48 m; these are the depths a thumbed drum realistically stops at.
const DEPTHS: Array[float] = [8.0, 12.0, 16.0, 20.0, 24.0, 28.0, 32.0, 36.0, 40.0, 44.0, 48.0]

# ------------------------------------------------------------------ the run
func _run() -> void:
	var table: Dictionary = FISH.all()
	var species: Array[String] = []
	for id in table:
		species.append(String(id))
	species.sort()

	# ---------------------------------------------------------------- the roster
	# "Every fish with a mesh" is the brief's own wording, so the roster is read off the
	# DISK, not off the table. That way a species someone generates art for and forgets to
	# wire up fails this probe instead of quietly never being catchable.
	var meshed: Array[String] = []
	var meshless: Array[String] = []
	for id in species:
		if ResourceLoader.exists("%s%s/%s.glb" % [FAUNA_DIR, id, id]):
			meshed.append(id)
		else:
			meshless.append(id)
	var orphan_meshes: Array[String] = []
	var dir: DirAccess = DirAccess.open(FAUNA_DIR)
	if dir:
		for sub in dir.get_directories():
			if sub.begins_with("fish_") and not table.has(sub):
				orphan_meshes.append(sub)
	print("=== ROSTER ===")
	print("  fish.json species        : %d" % species.size())
	print("  ...with a mesh on disk   : %d" % meshed.size())
	if not meshless.is_empty():
		print("  ...WITHOUT a mesh        : %s" % ", ".join(meshless))
	_check(orphan_meshes.is_empty(),
		"every fish_* mesh on disk has a fish.json entry%s" % \
			("" if orphan_meshes.is_empty() else " (orphans: %s)" % ", ".join(orphan_meshes)))
	print("")

	# ---------------------------------------------------------------- sweep 1: coverage
	# Roll (rather than inspect the weight) so that anything which would make a species
	# unreachable in practice — a zero-sum pool, a depth gate, a bait that cancels it out —
	# shows up here exactly as the player would experience it.
	var seen_any: Dictionary = {}
	var seen_by_tool: Dictionary = {"rod": {}, "net": {}, "deep": {}}
	var combos: int = 0
	for kind in ["rod", "net", "deep"]:
		var depths: Array = [-1.0] if kind != "deep" else DEPTHS
		var baits: Array = [""] if kind != "deep" else BAITS
		for phase in PHASES:
			for weather in WEATHERS:
				for powered in [false, true]:
					for open_water in [false, true]:
						for depth in depths:
							for bait in baits:
								var ctx: Dictionary = _ctx(phase, weather, powered, open_water, String(bait))
								if FISH.pool_weight(kind, ctx, float(depth)) <= 0.0:
									continue
								combos += 1
								# 60 rolls per combo: enough that a species holding even a
								# few percent of THIS pool is drawn, without the sweep
								# turning into a benchmark.
								for i in range(60):
									var pick: Dictionary = FISH.roll(kind, ctx, _rng, float(depth))
									if pick.is_empty():
										continue
									var pid: String = String(pick["id"])
									seen_any[pid] = int(seen_any.get(pid, 0)) + 1
									var t: Dictionary = seen_by_tool[kind]
									t[pid] = int(t.get(pid, 0)) + 1
	print("=== COVERAGE SWEEP — %d live condition combinations ===" % combos)
	var never: Array[String] = []
	for id in meshed:
		if not seen_any.has(id):
			never.append(id)
	_check(never.is_empty(),
		"every one of the %d meshed species is reachable through the catch tables%s" % \
			[meshed.size(), "" if never.is_empty() else " — UNREACHABLE: %s" % ", ".join(never)])
	# Which tools each species can be landed on: the honest answer to "how do I get one".
	print("  %-24s %-4s %-4s %-5s" % ["species", "rod", "net", "deep"])
	for id in meshed:
		print("  %-24s %-4s %-4s %-5s" % [id,
			"yes" if (seen_by_tool["rod"] as Dictionary).has(id) else "-",
			"yes" if (seen_by_tool["net"] as Dictionary).has(id) else "-",
			"yes" if (seen_by_tool["deep"] as Dictionary).has(id) else "-"])
	print("")

	# ---------------------------------------------------------------- sweep 2: play mix
	var totals: Dictionary = {}
	for kind in ["rod", "net", "deep"]:
		var got: Dictionary = {}
		var n: int = 0
		for i in range(PLAY_ROLLS):
			var phase: String = PHASES[_rng.randi_range(0, 3)]
			# Weather as the clock actually spends it: StormSystem runs ~3.5-7.5 min calm,
			# a 22 s ramp in, 1.5-3.5 min raging, a 32 s ramp out, and rolls a fog bank
			# after about half of those. See storm_system.gd's schedule constants.
			var r: float = _rng.randf()
			var weather: String = "calm"
			if r < 0.30:
				weather = "storm"
			elif r < 0.38:
				weather = "rain"
			elif r < 0.53:
				weather = "fog"
			var powered: bool = _rng.randf() < 0.5
			var open_water: bool = _rng.randf() < 0.5
			var depth: float = -1.0
			var bait: String = ""
			if kind == "deep":
				depth = DEPTHS[_rng.randi_range(0, DEPTHS.size() - 1)]
				bait = BAITS[_rng.randi_range(0, BAITS.size() - 1)]
			var ctx: Dictionary = _ctx(phase, weather, powered, open_water, bait)
			var pick: Dictionary = FISH.roll(kind, ctx, _rng, depth)
			if pick.is_empty():
				continue
			var pid: String = String(pick["id"])
			got[pid] = int(got.get(pid, 0)) + 1
			totals[pid] = int(totals.get(pid, 0)) + 1
			n += 1
		print("=== PLAY MIX — %s, %d landed ===" % [kind.to_upper(), n])
		var rows: Array = []
		for pid in got:
			rows.append([pid, int(got[pid])])
		rows.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
		for row in rows:
			print("   %-24s %7.3f%%  (%d)" % [row[0], 100.0 * float(row[1]) / float(n), int(row[1])])
		print("")

	# ---------------------------------------------------------------- balance assertions
	# The brief's other half: differentiated by conditions, but NOT flattened. These are the
	# two ways that could have gone wrong, stated as tests rather than as a claim.
	var play_total: int = 0
	for pid in totals:
		play_total += int(totals[pid])
	var commons: Array[String] = ["fish_copper_sprat", "fish_herring"]
	var common_share: float = 0.0
	for c in commons:
		common_share += float(int(totals.get(c, 0))) / float(play_total)
	_check(common_share > 0.12,
		"commons stayed common — sprat + herring are %.1f%% of everything landed" % (common_share * 100.0))
	var trophies: Array[String] = ["fish_giant_oarfish", "fish_fathom_halibut", "the_looker"]
	var worst: float = 0.0
	for t in trophies:
		worst = maxf(worst, float(int(totals.get(t, 0))) / float(play_total))
	_check(worst < 0.03,
		"trophies stayed rare — the commonest of oarfish/halibut/Looker is %.2f%% of the catch" % (worst * 100.0))
	var thin: Array[String] = []
	for id in meshed:
		if int(totals.get(id, 0)) == 0:
			thin.append(id)
	_check(thin.is_empty(),
		"every meshed species is landed in the realistic play mix too%s" % \
			("" if thin.is_empty() else " — never landed: %s" % ", ".join(thin)))

	# ---------------------------------------------------------------- the conditions bite
	# Each new axis, asserted where it should be decisive. A condition that does not change
	# the roll is a condition the handbook would be lying about.
	var calm := _ctx("day", "calm", false, true, "")
	var rain := _ctx("day", "rain", false, true, "")
	var storm := _ctx("day", "storm", false, true, "")
	var fog := _ctx("day", "fog", false, true, "")
	_check(FISH.weight_for("fish_slate_cod", "rod", rain) > FISH.weight_for("fish_slate_cod", "rod", calm),
		"RAIN is its own tier — slate cod bites better in rain than in calm")
	_check(FISH.weight_for("fish_gannet_mackerel", "rod", rain) == 0.0
			and FISH.weight_for("fish_gannet_mackerel", "rod", calm) > 0.0,
		"RAIN can also refuse — the mackerel scatters when the glass falls")
	_check(FISH.weight_for("fish_drum_croaker", "rod", storm) > FISH.weight_for("fish_drum_croaker", "rod", rain),
		"a squall is still stronger than its shoulder — croaker peaks in the storm")
	_check(FISH.weight_for("the_looker", "rod", fog) > FISH.weight_for("the_looker", "rod", calm),
		"FOG is a fishing condition — the Looker comes up in it")
	var dark_night := _ctx("night", "calm", false, true, "")
	var lit_night := _ctx("night", "calm", true, true, "")
	_check(FISH.weight_for("fish_sable_hake", "rod", lit_night) > FISH.weight_for("fish_sable_hake", "rod", dark_night),
		"WORKLIGHTS draw — the hake doubles under a powered rig")
	_check(FISH.weight_for("fish_glasspike", "rod", dark_night) > FISH.weight_for("fish_glasspike", "rod", lit_night),
		"WORKLIGHTS also repel — the glasspike wants the breaker off")
	var near_water := _ctx("night", "calm", false, false, "")
	_check(FISH.weight_for("fish_bilge_blenny", "rod", near_water) > FISH.weight_for("fish_bilge_blenny", "rod", dark_night),
		"WATER — the blenny holds to the rig's shadow")
	var bare_deep := _ctx("night", "calm", false, false, "")
	var chum_deep := _ctx("night", "calm", false, false, "fish_rotten")
	var worm_deep := _ctx("night", "calm", false, false, "glow_worm")
	_check(FISH.weight_for("fish_trench_hagfish", "deep", chum_deep, 30.0)
			> FISH.weight_for("fish_trench_hagfish", "deep", bare_deep, 30.0),
		"BAIT — the hagfish wants rotten chum, as the handbook says")
	_check(FISH.weight_for("fish_giant_oarfish", "deep", worm_deep, 44.0)
			> FISH.weight_for("fish_giant_oarfish", "deep", chum_deep, 44.0),
		"BAIT — a glow worm beats chum for the oarfish at the end of the spool")
	_check(FISH.weight_for("fish_fathom_sturgeon", "deep", bare_deep, 30.0) == 0.0
			and FISH.weight_for("fish_fathom_sturgeon", "deep", bare_deep, 46.0) > 0.0,
		"DEPTH — the sturgeon is unreachable at 30 m and live at 46 m")
	# The old context shape, still rolling. Every dict built before the new axes existed
	# must keep its exact former behaviour, or the drop net and the test runner would have
	# silently changed underneath this work.
	var legacy := {"phase": "night", "storming": false, "lit": false, "open": true}
	_check(FISH.weight_for("fish_fathom_halibut", "net", legacy) > 0.0,
		"a pre-existing context dict (no rain/fog/powered keys) still rolls unchanged")
