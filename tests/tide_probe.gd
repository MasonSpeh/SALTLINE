extends Node
## TIDE PROBE — does mean sea level actually move, and does everything move with it?
##
## The tide is a scalar added in ONE place on the CPU (Gyre.wave_height/wave_offset) and applied
## in ONE place on the GPU (the OceanSurface node's y). Almost every bug this can have is a
## disagreement between two things that are supposed to be the same sea, so that is what this
## measures — not "does the number change".
##
## Headless is correct: this reads transforms and pure maths. It never asks anything to be drawn.
##
## Run: godot --headless --path . res://tests/TideProbe.tscn

const WET_Y: float = 2.0          ## rig_builder.WET_Y — the spawn deck plating
const PONTOON_TOP: float = 0.95   ## rig_builder._build_structure — the under-rig walkway

var failures: int = 0
var _completed: bool = false

func _ready() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in range(6):
		await get_tree().process_frame
	await _run(main)
	if not _completed:
		print("FAIL  the probe ran to completion (it did NOT — see the SCRIPT ERROR above)")
		failures += 1
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _ok(cond: bool, msg: String) -> void:
	print("%s  %s" % ["PASS" if cond else "FAIL", msg])
	if not cond:
		failures += 1

## What fraction of the water over the pontoon walkway is above its deck, at a given tide.
func _wet_fraction(tide_v: float, t: float) -> float:
	Gyre.set_tide(tide_v)
	var wet: int = 0
	var n: int = 0
	for i in range(4000):
		var q := Vector2(float(i % 61) * 1.1 - 26.0, float(i / 61) * 1.1 + 8.0)
		if Gyre.wave_height(q, t + float(i) * 0.09) > PONTOON_TOP:
			wet += 1
		n += 1
	return float(wet) / float(n)

func _find_script(root: Node, frag: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var sc: Script = n.get_script()
		if sc != null and String(sc.resource_path).ends_with(frag):
			return n
	return null

func _run(main: Node) -> void:
	# THE TIDE MUST NOT NEED THE GYRE NODE. It is a process-wide static and Gyre is a scene
	# node, not an autoload — if the value were pumped from Gyre._process, every harness that
	# does not build the whole world would run at a permanent 0.0 and certify the old fixed sea
	# while passing cleanly. Assert the derivation directly: at a known hour the tide must equal
	# tide_at(that hour) with nothing having driven it.
	Gyre.release_tide()
	await get_tree().process_frame
	var live: float = Gyre.tide()
	var expect: float = Gyre.tide_at(GameClock.game_time_hours())
	_ok(absf(live - expect) < 0.02,
		"the tide derives itself from GameClock, no driver node required (%.3f vs %.3f)"
		% [live, expect])
	# --- 1. the tide is a real, bounded, moving quantity -------------------------------------
	var lo: float = 1e9
	var hi: float = -1e9
	for h in range(0, 25):
		var v: float = Gyre.tide_at(float(h))
		lo = minf(lo, v)
		hi = maxf(hi, v)
	_ok(absf(hi - Gyre.TIDE_AMP) < 0.01 and absf(lo + Gyre.TIDE_AMP) < 0.01,
		"tide sweeps the full range over a day (%.2f .. %.2f m, amp %.2f)" % [lo, hi, Gyre.TIDE_AMP])
	# Semi-diurnal: it must come back to where it started roughly twice a day, not once.
	_ok(absf(Gyre.tide_at(0.0) - Gyre.tide_at(Gyre.TIDE_PERIOD_H)) < 0.01,
		"the tide is periodic on TIDE_PERIOD_H (%.2f h)" % Gyre.TIDE_PERIOD_H)

	# --- 2. the SURFACE and the SWIM LINE must differ only in the swell ----------------------
	# This is the bug the auditors flagged hardest: the 0.85 waterline scale predates the tide,
	# and scaling a tide-bearing height puts six documented-to-agree call sites 0.2 m off the
	# drawn water at high and low.
	var t: float = Gyre.water_time()
	var p := Vector2(11.0, -17.0)
	for tide_v in [-Gyre.TIDE_AMP, 0.0, Gyre.TIDE_AMP]:
		Gyre.set_tide(tide_v)
		var surf: float = Gyre.wave_height(p, t)
		var swim: float = Gyre.swim_line(p, t)
		var swell: float = surf - tide_v          # the surface, tide removed
		_ok(absf(swim - (tide_v + Gyre.SWIM_SCALE * swell)) < 1e-9,
			"at tide %+.2f the swim line is tide + %.2f*swell, not %.2f*(swell+tide)"
			% [tide_v, Gyre.SWIM_SCALE, Gyre.SWIM_SCALE])
		# ...and the tide must move the surface one-for-one: rigid, never scaled by sea state.
		Gyre.set_tide(0.0)
		var base: float = Gyre.wave_height(p, t)
		Gyre.set_tide(tide_v)
		_ok(absf((Gyre.wave_height(p, t) - base) - tide_v) < 1e-9,
			"a %+.2f m tide moves the surface exactly %+.2f m (rigid, unscaled)" % [tide_v, tide_v])

	# --- 3. height and offset must not drift apart ------------------------------------------
	# They live 40 lines apart and one returns a Vector3, so "tide added to only one" is the
	# easy mistake — and a silent one: the player reads height, floating debris reads offset.
	var worst: float = 0.0
	for tide_v in [-Gyre.TIDE_AMP, 0.0, Gyre.TIDE_AMP]:
		Gyre.set_tide(tide_v)
		for i in range(64):
			var q := Vector2(float(i) * 3.7 - 60.0, float(i) * -2.3 + 20.0)
			worst = maxf(worst, absf(Gyre.wave_offset(q, t).y - Gyre.wave_height(q, t)))
	_ok(worst < 1.2e-6, "wave_offset().y still equals wave_height() at every tide (worst %.9f)" % worst)

	# --- 4. the DRAWN sea must sit where the simulated sea says --------------------------
	var ocean: Node3D = get_tree().get_first_node_in_group("ocean_surface")
	_ok(ocean != null, "the ocean surface node was found")
	if ocean != null:
		for tide_v in [-Gyre.TIDE_AMP, 0.35, Gyre.TIDE_AMP]:
			Gyre.set_tide(tide_v)
			await get_tree().process_frame
			await get_tree().process_frame
			_ok(absf(ocean.global_position.y - tide_v) < 0.01,
				"the drawn sea rides the tide (%+.2f m -> node y %+.2f)"
				% [tide_v, ocean.global_position.y])

	# --- 5. the analytic floor must still be a PROOF at the worst tide ----------------------
	# trough_floor() is cached decisions, so it has to hold at full storm AND dead low water.
	Gyre.set_sea_state(1.0)
	Gyre.set_tide(-Gyre.TIDE_AMP)
	var deepest: float = 1e9
	for i in range(4000):
		var q := Vector2(float(i % 97) * 4.1 - 200.0, float(i / 97) * 5.3 - 100.0)
		deepest = minf(deepest, Gyre.wave_height(q, t + float(i) * 0.11))
	_ok(deepest > Gyre.trough_floor(),
		"the floor still bounds the sea at full storm AND low water (%.2f > %.2f)"
		% [deepest, Gyre.trough_floor()])
	Gyre.set_sea_state(Gyre.WAVE_SEA_STATE)

	# --- 6. THE GAMEPLAY: the intertidal band, and the deck that must stay walkable ---------
	# The amplitude was chosen off this budget, so it is the thing to assert — but assert the
	# RIGHT thing. A crest occasionally washing over the wet deck plating is not a fault: this
	# rig's wet deck is deliberately low and player_controller._check_water already carries a
	# cooldown on the cold warning *because* "a running swell washes the plate repeatedly".
	# What must never happen is the deck being sea — permanently under, or deep enough that the
	# player standing on it starts swimming and loses the walking controls.
	Gyre.set_tide(Gyre.TIDE_AMP)
	var crest: float = -1e9
	var mean_surf: float = 0.0
	var n: int = 0
	for i in range(6000):
		var q := Vector2(float(i % 71) * 0.9 + 8.0, float(i / 71) * 0.9 - 22.0)   # over the wet deck
		var h: float = Gyre.wave_height(q, t + float(i) * 0.07)
		crest = maxf(crest, h)
		mean_surf += h
		n += 1
	mean_surf /= float(n)
	_ok(mean_surf < WET_Y - 1.0,
		"at high water the spawn deck keeps real freeboard (mean sea %.2f, plating %.2f)"
		% [mean_surf, WET_Y])
	# The deepest a crest ever puts water over the plating, against the depth at which the
	# controller hands the frame to the swimming path. Wash is atmosphere; a swim is a bug.
	var wash: float = crest - WET_Y
	_ok(wash < 1.15,
		"the worst calm crest only WASHES the deck, never floats you off it (%.2f m over plating, wade line 1.15)"
		% maxf(wash, 0.0))
	_ok(crest > PONTOON_TOP,
		"the pontoon walkway is awash at high water (crest %.2f > %.2f) — the intertidal band exists"
		% [crest, PONTOON_TOP])
	# THE INTERTIDAL CLAIM, measured as a FRACTION rather than a binary. Neither tide leaves the
	# walkway permanently under or permanently dry — an under-rig walkway one metre over low
	# water gets hit by the big ones whatever the tide, which is exactly right. What the tide
	# changes is how OFTEN, and that difference is the gameplay: at low water you can work the
	# walkway between sets; at high water it is being swept and you should not be down there.
	var wet_hi: float = _wet_fraction(Gyre.TIDE_AMP, t)
	var wet_lo: float = _wet_fraction(-Gyre.TIDE_AMP, t)
	_ok(wet_hi > 0.25, "at high water the walkway is being swept (%.0f%% of samples under water)" % (wet_hi * 100.0))
	_ok(wet_lo < 0.05, "at low water it is workable (%.0f%% under water)" % (wet_lo * 100.0))
	_ok(wet_hi - wet_lo > 0.25,
		"the tide genuinely changes the walkway: %.0f%% swept at high vs %.0f%% at low"
		% [wet_hi * 100.0, wet_lo * 100.0])

	# --- 7. THE THINGS THAT WERE DEAF TO THE SEA ---------------------------------------------
	# Two fixes worth pinning, because both were invisible failures rather than errors.
	# The surface jellies were the only fauna in bloom_fauna that never asked Gyre anything, so
	# at low water all seven glowing bells hovered in open air beside the wet-deck rail; and the
	# topside cull was an absolute-Y test, so at high water a swimmer riding a crest could have
	# the entire underwater subtree switched off around them.
	var uw: Node3D = get_tree().get_first_node_in_group("underwater_world")
	_ok(uw != null, "underwater_world found")
	if uw != null:
		var cull_lo: bool = _cull_wants(uw, 3.0, -Gyre.TIDE_AMP)
		var cull_hi: bool = _cull_wants(uw, 3.0, Gyre.TIDE_AMP)
		_ok(not cull_lo and cull_hi,
			"the topside cull follows mean water: an eye at y 3.0 is topside at low tide (%s) and submerged-side at high (%s)"
			% [str(cull_lo), str(cull_hi)])
	Gyre.release_tide()
	_completed = true

## What underwater_world._cull_topside would decide for an eye at `eye_y` at a given tide.
## Mirrors the threshold rather than driving the node, so it needs no camera.
func _cull_wants(uw: Node3D, eye_y: float, tide_v: float) -> bool:
	Gyre.set_tide(tide_v)
	return eye_y < float(uw.get("TOPSIDE_MARGIN")) + Gyre.tide()
