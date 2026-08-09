extends Node
## THE INSTINCT LAYER, MEASURED — what the cat actually does with itself, counted.
##
## CatProbe asserts that the wiring exists (PERCH is entered, the ear scratch reaches its own
## pose, the selector is reproducible). This one answers the question a boolean cannot: is the
## distribution VARIED, or is one behaviour eating the animal? "It picks at random" is a claim
## about counts, and this file has shipped behaviours that were argued rather than measured
## before — the three-second wash window ran for five sessions and every gate was green.
##
##   godot --headless --fixed-fps 30 --path . res://tests/CatBehaviourProbe.tscn
##   ...optionally --secs=NNN (sim seconds per live scenario; default 200)
##
## --fixed-fps IS NOT OPTIONAL FOR THE LIVE HALF. Without it `delta` is real elapsed time, so
## 200 sim seconds costs 200 wall seconds per scenario; with it every frame is exactly 1/30 s
## of sim whatever the frame really took, which is the same reason tests/cat_film.gd uses it.
## The probe prints the achieved sim seconds either way, so a run without it is still honest —
## just short.
##
## TWO HALVES, AND THE FIRST ONE IS THE ONE THAT CANNOT BE FLAKY:
##   PART 1 measures the SELECTOR as a pure function — freeze the drives, reseed the decision
##          stream, take N decisions. Exactly reproducible, so the distribution can be asserted
##          on rather than eyeballed, and it isolates "what would it choose" from "did the
##          situation ever let it choose".
##   PART 2 runs the real animal in the real world and counts what actually fired, which is the
##          only thing that can catch an action that is chosen and then refused by geometry
##          (a perch with nothing to perch on) or starved by a rung above it.

var failures: int = 0
var _completed: bool = false
var _cat: Node3D
var _player: Node3D
## Sim seconds per live scenario.
var _secs: float = 200.0

func _ok(c: bool, m: String) -> void:
	print("%s  %s" % ["PASS" if c else "FAIL", m])
	if not c:
		failures += 1

func _ready() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--secs="):
			_secs = maxf(float(a.substr(7)), 10.0)
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	# A PARSE ERROR HANDS `instantiate()` A BARE NODE (docs/AGENT_TRAPS.md) — the root arrives
	# with its script dropped, builds nothing, and every probe walking it passes vacuously.
	_ok(main.get_script() != null, "Main.tscn instantiated WITH its script")
	await get_tree().create_timer(6.0).timeout
	for i in range(10):
		await get_tree().physics_frame
	_cat = get_tree().get_first_node_in_group("ship_cat")
	_player = get_tree().get_first_node_in_group("player")
	_ok(_cat != null and _player != null, "there is a cat and a player")
	if _cat == null or _player == null:
		print("FAILURES: %d" % failures)
		get_tree().quit(1)
		return
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.set("_lying", false)
	_player.set("_lying_sleeping", false)
	PlayerState.selected_hotbar = -1
	for c in _cat.get_children():
		if c is Interactable:
			(c as Interactable).interact("SAY HELLO", _player)
	await get_tree().physics_frame

	_part1_selector()
	await _part2_live()

	if not _completed:
		print("FAIL  the probe ran to completion (it did NOT — see the SCRIPT ERROR above)")
		failures += 1
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------ PART 1: the pure selector

## Freeze every drive the menu reads, so a draw measures the WEIGHTS and nothing else.
func _drive(energy: float, still: float, phase: int) -> void:
	GameClock.force_phase(phase)
	_cat.set("_energy", energy)
	_cat.set("_still", still)
	_cat.set("_wash_cd", 0.0)
	_cat.set("_wash_t", 0.0)
	_cat.set("_shake_cd", 0.0)
	_cat.set("_meow_cd", 0.0)
	_cat.set("_roam_cd", 0.0)
	_cat.call("_enter", 3)          # State.SIT — anything but SLEEP, whose menu is rouse-only

## N decisions from one frozen weight vector, from a named seed.
func _draws(n: int, sd: int, allow_roam: bool) -> Dictionary:
	_cat.call("set_behaviour_seed", sd)
	var w: Dictionary = _cat.call("_action_weights", allow_roam)
	var h: Dictionary = {}
	for i in range(n):
		var a: String = String(_cat.call("_pick_action", w))
		h[a] = int(h.get(a, 0)) + 1
	return h

func _print_hist(label: String, h: Dictionary, n: int) -> void:
	var keys: Array = h.keys()
	keys.sort()
	var line: String = ""
	for k in keys:
		line += "%s %d (%.1f%%)  " % [k, int(h[k]), 100.0 * float(h[k]) / float(n)]
	print("    %-26s %s" % [label, line])

func _top_share(h: Dictionary, n: int) -> Array:
	var best: String = ""
	var best_n: int = -1
	for k in h:
		if int(h[k]) > best_n:
			best_n = int(h[k])
			best = String(k)
	return [best, float(best_n) / maxf(float(n), 1.0)]

func _share(h: Dictionary, k: String, n: int) -> float:
	return float(int(h.get(k, 0))) / maxf(float(n), 1.0)

func _part1_selector() -> void:
	print("\n=== PART 1 — the selector as a pure function (frozen drives, seeded stream) ===")
	const N: int = 2000
	# THREE DRIVE STATES, one variable moved at a time: the tank, then the clock.
	_drive(0.08, 20.0, GameClock.Phase.DAY)
	var tired: Dictionary = _draws(N, 11, true)
	_print_hist("tired  (E 0.08, day)", tired, N)
	_drive(0.55, 20.0, GameClock.Phase.DAY)
	var mid: Dictionary = _draws(N, 11, true)
	_print_hist("middling (E 0.55, day)", mid, N)
	_drive(0.95, 20.0, GameClock.Phase.DAY)
	var lively: Dictionary = _draws(N, 11, true)
	_print_hist("lively (E 0.95, day)", lively, N)
	_drive(0.95, 20.0, GameClock.Phase.DUSK)
	var dusk: Dictionary = _draws(N, 11, true)
	_print_hist("lively (E 0.95, DUSK)", dusk, N)
	_drive(0.55, 60.0, GameClock.Phase.DAY)
	var longsat: Dictionary = _draws(N, 11, true)
	_print_hist("sat 60 s (E 0.55, day)", longsat, N)
	_drive(0.55, 20.0, GameClock.Phase.DAY)
	_cat.set("_wash_cd", 30.0)             # a bout just ended
	var nowash: Dictionary = _draws(N, 11, true)
	_print_hist("wash on cooldown", nowash, N)
	_drive(0.55, 20.0, GameClock.Phase.DAY)
	var stranger: Dictionary = _draws(N, 11, false)
	_print_hist("pre-friend (no roaming)", stranger, N)

	# --- DETERMINISM. The whole point of giving the chooser its own stream.
	_drive(0.55, 20.0, GameClock.Phase.DAY)
	var a1: Dictionary = _draws(600, 4242, true)
	var a2: Dictionary = _draws(600, 4242, true)
	var same: bool = a1.size() == a2.size()
	for k in a1:
		if int(a1[k]) != int(a2.get(k, -1)):
			same = false
	_ok(same, "the same seed gives the same 600 decisions, exactly (%d kinds)" % a1.size())
	var b1: Dictionary = _draws(600, 777, true)
	var differs: bool = false
	for k in a1:
		if int(a1[k]) != int(b1.get(k, -1)):
			differs = true
	_ok(differs, "...and a DIFFERENT seed gives a different run (it is not a constant)")

	# --- VARIETY. A selector that always answers the same thing is a loop with dice on it.
	var ts: Array = _top_share(mid, N)
	_ok(mid.size() >= 8,
		"a middling cat has at least 8 things it might do (%d)" % mid.size())
	_ok(float(ts[1]) < 0.30,
		"...and no single one of them dominates (commonest is %s at %.1f%%)"
			% [String(ts[0]), 100.0 * float(ts[1])])

	# --- THE DRIVES ACTUALLY DRIVE IT. Each of these is one weight term, read back as a share.
	_ok(_share(tired, "loaf", N) > _share(lively, "loaf", N) * 2.0,
		"a tired cat naps far more than a lively one (%.1f%% vs %.1f%%)"
			% [100.0 * _share(tired, "loaf", N), 100.0 * _share(lively, "loaf", N)])
	_ok(_share(lively, "survey", N) > _share(tired, "survey", N),
		"a lively cat watches things more (%.1f%% vs %.1f%%)"
			% [100.0 * _share(lively, "survey", N), 100.0 * _share(tired, "survey", N)])
	_ok(_share(dusk, "loaf", N) == 0.0 and _share(lively, "loaf", N) > 0.0,
		"at DUSK it does not lie down at all (%.1f%% vs %.1f%% by day) — crepuscular"
			% [100.0 * _share(dusk, "loaf", N), 100.0 * _share(lively, "loaf", N)])
	_ok(_share(longsat, "stretch", N) > _share(mid, "stretch", N) * 1.5,
		"a cat that has sat for a minute stretches more than one that just sat down (%.1f%% vs %.1f%%)"
			% [100.0 * _share(longsat, "stretch", N), 100.0 * _share(mid, "stretch", N)])
	_ok(_share(nowash, "wash_paw", N) == 0.0 and _share(nowash, "scratch_ear", N) == 0.0,
		"a wash on cooldown takes all four washes off the menu (%.1f%%)"
			% [100.0 * (_share(nowash, "wash_paw", N) + _share(nowash, "scratch_ear", N))])
	_ok(_share(stranger, "mosey", N) == 0.0 and _share(stranger, "perch", N) == 0.0,
		"a cat that has not decided about you never gets up and goes anywhere (%.1f%%)"
			% [100.0 * (_share(stranger, "mosey", N) + _share(stranger, "perch", N))])

	# --- THE WINDOW THAT WAS THE BUG. The wash used to be reachable only while
	# 3 < _still <= SETTLE_SEC (6). Assert it directly, at a `_still` that used to be fatal.
	_drive(0.55, 300.0, GameClock.Phase.DAY)
	var w300: Dictionary = _cat.call("_action_weights", true)
	_ok(float(w300.get("wash_paw", 0.0)) > 0.0,
		"a cat settled for FIVE MINUTES can still start a wash (weight %.2f) — the old code could not"
			% float(w300.get("wash_paw", 0.0)))
	_cat.call("_enter", 4)                  # State.SLEEP
	var wsleep: Dictionary = _cat.call("_action_weights", true)
	_ok(wsleep.size() == 1 and wsleep.has("rouse"),
		"a sleeping cat's only option is waking up (%s)" % str(wsleep.keys()))
	_cat.call("_enter", 3)

# ------------------------------------------------------------------ PART 2: the live animal

func _rows(h: Dictionary) -> void:
	var keys: Array = h.keys()
	keys.sort()
	if keys.is_empty():
		print("      (nothing fired)")
		return
	for k in keys:
		var r: Dictionary = h[k]
		print("      %-14s n %3d   share %5.1f%%   mean gap %6.1f s"
			% [String(k), int(r["n"]), 100.0 * float(r["share"]), float(r["mean_gap_s"])])

## Park cat and player somewhere flat and quiet, hold the OTHER self-directed rungs off, and
## count. The hunt, the zoomies and object play are pinned at 999 for the same reason every
## cat harness in this repo pins them: they are separate rungs above this one and a burst of
## zoomies in the middle of the window measures them, not the instinct layer.
##
## `shift_s` makes the player SHUFFLE — a few centimetres every so often. It is not garnish: a
## perfectly motionless player is not a state real play produces, and it is the one state that
## drives `_still` straight up the doze ladder, so a probe that only ever measures it is
## measuring the sleep. Both are run.
func _live(label: String, energy: float, phase: int, at: Vector3,
		shift_s: float = 0.0) -> Dictionary:
	_cat.global_position = at
	_cat.call("_reseat")
	var home: Vector3 = at + Vector3(1.4, 0.1, 0.0)
	_player.global_position = home
	_cat.set("_stayed", false)
	_cat.set("_wash_t", 0.0)
	_cat.set("_after_t", 0.0)
	_cat.set("_carry", "")
	_cat.set("_idle_cd", 0.0)
	_cat.set("_roam_cd", 0.0)
	GameClock.force_phase(phase)
	for i in range(20):
		# PINNED DURING THE SETTLE FRAMES TOO, not only inside the measured window. The first
		# cut pinned them below and a ZOOMIE started here, in the twenty frames before counting
		# began, and then ran on inside the window (`_zoom_t` keeps a burst alive whatever the
		# cooldown says) — which is how RUN, state 2, turned up in a scenario where the cat was
		# supposed to be sitting beside a motionless player.
		_cat.set("_hunt_cd", 999.0)
		_cat.set("_zoom_cd", 999.0)
		_cat.set("_play_cd", 999.0)
		_cat.set("_zoom_t", 0.0)
		_cat.set("_play_t", 0.0)
		await get_tree().physics_frame
	_cat.call("behaviour_reset_log")
	var t0: float = float(_cat.get("_t"))
	var wall0: int = Time.get_ticks_msec()
	var frames: int = int(_secs * 30.0)
	var seen_states: Dictionary = {}
	var shift_n: int = int(shift_s * 30.0)
	for i in range(frames):
		_cat.set("_energy", energy)      # pinned, so the scenario means what its label says
		_cat.set("_hunt_cd", 999.0)
		_cat.set("_zoom_cd", 999.0)
		_cat.set("_play_cd", 999.0)
		if shift_n > 0 and i % shift_n == 0:
			var a: float = TAU * float(i / maxi(shift_n, 1)) * 0.37
			_player.global_position = home + Vector3(cos(a), 0.0, sin(a)) * 0.35
		await get_tree().physics_frame
		seen_states[int(_cat.get("_state"))] = true
	var secs: float = float(_cat.get("_t")) - t0
	var h: Dictionary = _cat.call("behaviour_histogram")
	var n: int = 0
	for k in h:
		n += int((h[k] as Dictionary)["n"])
	var ks: Array = seen_states.keys()
	ks.sort()
	print("\n  --- %s  (%.0f s sim in %.0f s wall, %d actions, %.1f s between actions)"
		% [label, secs, 0.001 * float(Time.get_ticks_msec() - wall0), n,
			secs / maxf(float(n), 1.0)])
	print("      states visited: %s   (0 GROOM 1 FOLLOW 3 SIT 4 SLEEP 12 PERCH 13 STRETCH)"
		% str(ks))
	_rows(h)
	return {"h": h, "n": n, "secs": secs, "states": seen_states}

func _part2_live() -> void:
	print("\n=== PART 2 — the live animal, counted (%.0f s of sim per scenario) ===" % _secs)
	# The bunkhouse floor: flat, enclosed, and the room the cat actually lives in.
	var home := Vector3(-22.0, 18.05, 11.0)
	# A CRATE TO GET ONTO, built rather than hunted for — the same reasoning CatProbe's leap
	# check uses, and for the same reason: probing the rig for "something 0.3-1.25 m tall"
	# returns a different prop every run and then the test measures the level design. Present
	# for every scenario, so `perch` is on the menu with somewhere real to go.
	var crate := StaticBody3D.new()
	var ccs := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(1.3, 0.9, 1.3)
	ccs.shape = cbox
	crate.add_child(ccs)
	get_tree().current_scene.add_child(crate)
	# Top at 18.90 — inside the LEAP band. tests/CatStepScratch measured the cat getting onto
	# nothing at all below CLIMB_UP against a vertical face, so a shorter crate would measure
	# that bug rather than the behaviour.
	crate.global_position = Vector3(-20.6, 18.45, 11.0)
	var mid: Dictionary = await _live("middling cat, day, player shuffling", 0.55,
		GameClock.Phase.DAY, home, 9.0)
	var tired: Dictionary = await _live("tired cat, day, player shuffling", 0.10,
		GameClock.Phase.DAY, home, 9.0)
	var dusk: Dictionary = await _live("lively cat, DUSK, player shuffling", 0.95,
		GameClock.Phase.DUSK, home, 9.0)
	var frozen: Dictionary = await _live("middling cat, day, player DEAD STILL", 0.55,
		GameClock.Phase.DAY, home, 0.0)
	crate.queue_free()
	await get_tree().physics_frame

	# --- WHAT THE LIVE RUN HAS TO SHOW. Deliberately loose bounds, and none of them is on a
	# specific rare action: this is a stochastic process watched for a few minutes, and a tight
	# bound on a count is how a probe becomes a coin flip. PART 1 is where the exact numbers
	# live. What is asserted here is only what a live run can settle and a pure one cannot —
	# that the layer is REACHED, that the world lets its actions complete, and that the animal
	# is not one behaviour wearing a hat.
	_ok(float(mid["secs"]) > _secs * 0.9,
		"the instrument really ran (%.0f s of sim asked, %.0f delivered)"
			% [_secs, float(mid["secs"])])
	_ok(int(mid["n"]) >= 8,
		"a middling cat does a fair number of things in %.0f s (%d actions, one every %.1f s)"
			% [float(mid["secs"]), int(mid["n"]),
				float(mid["secs"]) / maxf(float(int(mid["n"])), 1.0)])
	_ok((mid["h"] as Dictionary).size() >= 5,
		"...and of at least five different kinds (%d kinds: %s)"
			% [(mid["h"] as Dictionary).size(), str((mid["h"] as Dictionary).keys())])
	var ts: Array = _top_share_live(mid["h"] as Dictionary, int(mid["n"]))
	_ok(float(ts[1]) <= 0.60,
		"...and none of them is the whole animal (commonest %s at %.0f%%)"
			% [String(ts[0]), 100.0 * float(ts[1])])
	_ok((mid["states"] as Dictionary).has(0) and (mid["states"] as Dictionary).has(3),
		"...and the actions reach real states, not just timers (GROOM and SIT both seen: %s)"
			% str((mid["states"] as Dictionary).keys()))
	# THE ONE EXACT LIVE CLAIM. `loaf`'s weight is literally absent from the menu at dawn and
	# dusk, so this cannot be a lucky run — it is an invariant, and a non-zero count here would
	# mean the crepuscular branch is not doing what `_action_weights` says it does.
	_ok(not (dusk["h"] as Dictionary).has("loaf"),
		"a cat at dusk never lies down of its own accord (loaf n=%d) — crepuscular"
			% int(((dusk["h"] as Dictionary).get("loaf", {"n": 0}) as Dictionary)["n"]))
	# THE DOZE LADDER, WHICH IS WHAT THE FIRST RUN OF THIS PROBE CAUGHT. Before the instinct
	# layer pushed `_still` back, a dead-still player put the cat to sleep at 28 s and it stayed
	# there: 60 s produced four actions and three states. This is the regression bar for that.
	_ok(int(frozen["n"]) >= 5,
		"a cat beside a player who never moves at all still has a life (%d actions in %.0f s)"
			% [int(frozen["n"]), float(frozen["secs"])])
	print("\n  tired vs lively, as counted live (PART 1 asserts the distribution exactly):")
	print("      loaf   tired n=%d   dusk n=%d"
		% [int(((tired["h"] as Dictionary).get("loaf", {"n": 0}) as Dictionary)["n"]),
			int(((dusk["h"] as Dictionary).get("loaf", {"n": 0}) as Dictionary)["n"])])
	print("      perch  taken n=%d   refused-for-want-of-anything-to-climb n=%d"
		% [int(((mid["h"] as Dictionary).get("perch", {"n": 0}) as Dictionary)["n"]),
			int(((mid["h"] as Dictionary).get("perch_none", {"n": 0}) as Dictionary)["n"])])
	_completed = true

func _top_share_live(h: Dictionary, n: int) -> Array:
	var best: String = ""
	var best_n: int = -1
	for k in h:
		var c: int = int((h[k] as Dictionary)["n"])
		if c > best_n:
			best_n = c
			best = String(k)
	return [best, float(best_n) / maxf(float(n), 1.0)]
