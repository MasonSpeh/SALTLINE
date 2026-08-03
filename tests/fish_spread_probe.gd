extends Node3D
## WHERE THE SHOALS ACTUALLY ARE, AND WHICH WAY THEY ARE POINTING.
##
## Two owner complaints, one harness, because both are about the same 40 species and
## relaunching Godot lags the owner's machine:
##
##   1. "The fish generation got messed up under the rig with the new fish species."
##      s31 added eleven species and every one of them was stocked into the same
##      ±24 x ±28 m box the other twenty-nine work, because `water` in data/fish.json
##      steered the CATCH ROLL and nothing else. This probe counts members by water class
##      and measures how many bodies are in the volume a player looks down into from the
##      wet deck, so "less crowded under the rig" is a number rather than an impression.
##
##   1b. s35: "fish distribution still bad ... fish should take up a larger visual density
##      closer to the surface", and "make goliath grouper rarer, deeper only, and only
##      appear as huge." Sweep 1 above measures the PLAN — how far out the shoals are — and
##      it cannot see either of these, because both are statements about the water COLUMN.
##      So this probe now also measures the vertical distribution: a per-2-m depth profile
##      of every fish on shift, the count and the density in the top SHALLOW_M metres, and
##      the number of bodies sitting INSIDE the two pontoon castings (which draw nothing and
##      had never been counted). See `_report_surface_density`. The goliath's own three
##      words get their own report — `_report_goliath`.
##
##   1c. s36: "overall, increase fish budget by 50%", "decrease small tropical fish by 25%",
##      "add more fish around the surface ... to fit more normal fish to visually fill space."
##      The first two are a CENSUS and nothing counted either population — see
##      `_report_stocking`, which also prints the triangle bill, because the schools turn out
##      to be the largest triangle population in the game and the eleven s31 species import
##      at four to six times every other species' budget. The third is a MIX, not a count:
##      the shallow shell was two thirds small fish, so `_report_surface_density` now splits
##      it on the species' own body length and asserts the normal share.
##
##   2. "At least one of the new grouper models is swimming backwards."
##      The facing table is measured off the raw mesh (tools/measure_facing.py) and read
##      off a render (tests/CandShot). Neither of those watches the animal SWIM, so
##      neither can catch a species that is correct in the table and reversed in the
##      world. This one correlates each species' live travel direction against its own
##      mesh geometry — no reference to CreatureAnim.FACING_OVERRIDES at all, so it is an
##      independent check of that table rather than a restatement of it.
##
## HOW THE HEAD END IS FOUND WITHOUT ASKING THE FACING TABLE. A fish's mass runs forward:
## the head carries the skull, the gill mass and the pectoral girdle while the tail tapers
## to a peduncle. So along the mesh's longest axis, the VERTEX CENTROID sits on the head
## side of the bounding-box centre. tools/measure_facing.py calibrated exactly this
## statistic against the fourteen fish whose facing is already pinned in creature_anim.gd
## and got 14/14 — it is only unreliable on non-fish (it calls the herring gull backwards),
## and every species here is a fish.
##
## HEADLESS IS HONEST HERE. The shoals are real Node3Ds, not a MultiMesh, so their
## transforms read back correctly under --headless (the MultiMesh identity trap does not
## apply). What DOES apply is that underwater_world only swims a school while its subtree
## is visible, and _cull_topside keys that off camera height — so the camera is put under
## the water before anything is measured, and the probe asserts the pods left the origin.
##
##     godot --headless --path . res://tests/FishSpreadProbe.tscn

const ANIM := preload("res://scripts/world/creature_anim.gd")

## The volume the owner is complaining about: what you see looking down off the wet deck.
## The rig's own footprint plus the walkways — legs at |x| 22 / |z| 12, pontoon out to
## x ±28, so a body inside this box is "under the rig" in the sense that was meant.
const RIG_BOX := Vector2(30.0, 34.0)
const LEGS := [Vector2(-22, -12), Vector2(22, -12), Vector2(-22, 12), Vector2(22, 12)]

## ---------------------------------------------------------------- the surface band (s35)
## "Closer to the surface" is measured against the LIVE DRAWN SEA at each fish's own xz, not
## against y = 0: mean water moves with the tide (~1.4 m over 25 real minutes) and the swell
## puts ±2 m on top of that, so a fixed plane would measure the tide as often as the fish.
## The instrument's own floor is ~0.15 m — the shader displaces the surface horizontally as
## well as vertically, so the drawn waterline at a given world xz differs from the number the
## CPU steers by (see tests/SealFloatProbe.tscn, which inverts that displacement). On a 4 m
## band that is under 4% and it does not need inverting here.
const SHALLOW_M: float = 4.0
const PROFILE_BIN: float = 2.0
const PROFILE_BINS: int = 12          ## 24 m of column, which is past the deepest pod plane
## Top-heavy, stated as a RATIO so it is a fact about the shape of the column rather than
## about how many fish happen to be stocked — and so the swell, which moves both terms the
## same way, cannot decide it. Predicted on the analytic pod model over day/night/dawn/dusk,
## BEFORE the s35 change: 0.79 / 1.01 / 0.95 / 0.97. The top four metres held LESS than the
## four metres under it, worst of all in daylight. That is the owner's complaint as a number.
## AFTER s35: 1.82 / 2.43 / 2.42 / 2.87 (a second, independently written model of the same
## algebra got 1.63 / 2.22 / 2.29 / 2.80 — the two agree on the shape and disagree by ~10% on
## the number, which is about what a model of a wandering shoal is worth).
## AFTER s36 — third surface pod plus the restocked counts: 2.52 / 4.10 / 4.20 / 4.45, taken
## on the same model off the shipped data/fish.json.
## The bar is set in the gap and nearer the OLD side, so a live run landing well below the
## model still passes and a regression to either previous shape cannot.
const TOP_HEAVY_MIN: float = 2.00
## Bodies in the shallow shell over the rig, meaned across the four clock phases. Model says
## 140 before s36 and 253 after (the s35 model called the same pre-s36 figure 148). Same
## reasoning as the ratio: the bar sits between them rather than under the new figure, because
## this probe's job is to catch the shape coming back, not to score the tuning. The PROOF of
## the change is the before/after table it prints.
const SHELL_MIN: float = 190.0

## ---------------------------------------------------------------- the MIX (s36)
## "Add more fish around the surface ... to fit more NORMAL fish to visually fill space."
##
## Neither bar above can see that, and this is the ask that was actually hardest to satisfy:
## the water the player swims in was two thirds SMALL fish and the two most populous shoals in
## the game (34 copper sprat, 28 bilge blenny) are 0.6 m animals. A stocking rise that scaled
## everything would have kept that ratio exactly and the complaint with it. So the shallow
## shell's bodies are split on the species' own `school.size` and the NORMAL share asserted.
##
## 0.85 m is the gap in the table, not a round number: the school sizes run 0.5 / 0.6 / 0.65 /
## 0.7 / 0.8 then 0.9 / 0.95 / 1.0 / 1.1 / 1.2 / 1.3 / 1.6, so nothing sits within 0.05 of it
## and the split cannot flip on a rounding.
const NORMAL_M: float = 0.85
## Model, in the shallow shell, meaned over the four clock phases: 33% normal before s36,
## 61% after. The bar is in the gap and nearer the old side, same convention as the two above.
const SHELL_NORMAL_MIN: float = 0.45

## ---------------------------------------------------------------- the budget (s36)
## "Overall, increase fish budget by 50%", and the population it is 50% OF is the whole fish
## population of the world — the pelagic schools here PLUS the tropical reef community on the
## caisson legs (scripts/world/reef_fish.gd), which is where the other owner ask, "decrease
## small tropical fish by 25%", lands. Counting only one of the two would let a rise in one
## pay for the ask about the other, so both are measured off the live tree and the bar is
## stated against the census taken before the change.
const OCEAN_BEFORE: int = 562        ## school bodies, s35: 281 per pod x 2 pods
const REEF_BEFORE: int = 252         ## reef_fish.gd SPECIES, sum of st x n
## 5% under (562 + 252) * 1.5 = 1221. The slack is for a species whose .glb is still
## generating, not for a shortfall in stocking — the census is a node count and is exact.
const WORLD_MIN: int = 1160
## The 25% cut, as a ceiling on the reef community. 252 * 0.75 = 189.
const REEF_MAX: int = 195

## A school species' mesh budget, triangles. NOT asserted — reported, loudly, because it is
## the number that decides whether a population rise is affordable and nothing in this repo
## has ever printed it. The s20-era catchable species all import at 25,026-31,247 triangles;
## the eleven s31 species import at 109,714-198,902, i.e. four to six times as much, because
## the s31 note that they "need decimating" was withdrawn on FILE SIZE (4-6 MB, same as the
## rest) and nobody counted the triangles. s36 steered its whole stocking rise onto the cheap
## meshes and held the expensive species' body count flat because of what this report says.
const MESH_BUDGET_TRIS: int = 40000
## The pontoons: rig_builder.gd:698-699 casts two `_box(Vector3(0, -1.05, ±12),
## Vector3(56, 4, 8))` CSG boxes — x ±28, y -3.05..0.95, |z| 8..16. These are the AUTHORED
## numbers and they are only the fallback: `_find_pontoons` measures the real boxes off the
## live tree first, so this check does not restate the constant the game steers by.
const PONTOON_FALLBACK := [
	[Vector3(0.0, -1.05, -12.0), Vector3(56.0, 4.0, 8.0)],
	[Vector3(0.0, -1.05, 12.0), Vector3(56.0, 4.0, 8.0)],
]
## The deepest water a player can reach (leg_reef.gd derives its plant taper from the same
## number; the handbook tells the player "past ~13 m down, not yours").
const DIVE_DEATH_Y: float = -13.0
## What "only appear as huge" has to mean for a body in the water. The two ambient goliaths
## are authored at 3.6 m and 4.4 m and their size jitter now runs 1.00..1.15, so the smallest
## one the world can build is 3.60 m; the leviathan is 12.8-15.2. The bar is set under the
## smallest AUTHORED animal, not under the smallest measured one, so a future spec row that
## sneaks a small one back in fails here.
const GOLIATH_MIN_M: float = 3.2

## The eleven species s31 added. Broken out on its own line in the report because THIS is
## the number the owner's complaint is actually about — "a few extra appearances" — and
## the all-species total hides it: pulling the pelagics out to the open ring while pulling
## the groupers in onto the legs leaves the gross under-rig count nearly flat while
## completely changing whose bodies those are.
const S31_SPECIES := [
	"fish_bluefin_tuna", "fish_yellowfin_tuna", "fish_bigeye_tuna", "fish_albacore_tuna",
	"fish_skipjack_tuna", "fish_bluelined_grouper", "fish_peacock_grouper",
	"fish_humpback_grouper", "fish_leopard_grouper", "fish_mahi_mahi", "fish_swallowtail",
]

## EVERY PHASE GETS A WINDOW, because a species that keeps hours is HIDDEN outside them and
## a hidden pod does not move at all (`root.visible = want`, then `continue`). A first cut
## of this probe measured in DAY only and reported 26 pods "still on the world origin" and
## thirteen species with "not enough travel to judge" — all of them the night shift, all of
## them working exactly as designed. Measuring one phase cannot see two thirds of the table.
const PHASES := ["DAY", "NIGHT", "DAWN", "DUSK"]   ## ...plus a forced squall, see _run()
## Per phase. The slowest circuit (the open ring at 58 m) runs at 1.15 m/s.
const SWIM_SECONDS: float = 26.0
const TIME_SCALE: float = 4.0
## Where the camera sits while it all happens. Below TOPSIDE_MARGIN so the subtree is
## visible and the schools tick, and deep enough to be in the band rather than on it.
const EYE := Vector3(0.0, -8.0, 0.0)

## A species passes the facing check when its mesh's head end leads its travel. The bar is
## deliberately low: this is looking for a model that is REVERSED (dot near -1) or BROADSIDE
## (dot near 0), not for a few degrees of yaw lag through a turn, and a shoal fish is
## banking constantly. Every correctly-facing species measures +0.93 or better.
const FACING_MIN: float = 0.25

## WHERE THIS INSTRUMENT CANNOT JUDGE, AND WHAT WAS DONE INSTEAD.
##
## The head-end statistic assumes a fish's mass runs forward along its longest axis. FIVE
## species in this table break that assumption, and every one of them is the same two body
## plans: a bill/needle snout that carries no mass in front of a heavy tail, or a ray whose
## WINGS are longer than its body. The probe called four of them backwards on its first run
## and all four were false alarms. They are named here rather than silently tolerated, with
## what a render actually showed, because an assertion that is quietly skipped is how a
## real defect hides:
##
##   fish_glasspike     — a needle snout carries almost no mass while the forked tail
##                        carries a lot, so the centroid lands aft. CandShot side view
##                        s34: beak screen-LEFT = local +Z = the default, CORRECT.
##   fish_kelp_pipefish — same shape problem, worse: the tail is a broad paddle. CandShot
##                        three-quarter view s34 shows the pectoral fin and the eye at the
##                        needle end, screen-LEFT = local +Z = the default, CORRECT.
##   fish_squall_garfish— a billfish: 1.99 m of body with a bill on the front and a heavy
##                        forked tail behind. Only ever on shift during a squall, so the
##                        forced-storm window below is the only thing that has ever watched
##                        it swim. CandShot side view s34: bill screen-LEFT = local +Z =
##                        the default, CORRECT.
##   fish_anchor_ray    — a ray's WINGSPAN is its longest axis (2.000 X against 1.919 Z),
##                        so "along the body" picks the wrong axis outright and the answer
##                        is meaningless rather than merely noisy. CandShot front view s34
##                        photographs it head-on with the wings spanning the frame, i.e.
##                        nose on +Z = the default, CORRECT.
##   fish_ribbon_eel    — authored along X and CURVED, so the centroid is weak (vol -0.029,
##                        width -0.007). This one was NOT a false alarm: the probe read
##                        +0.011, i.e. perpendicular, and the render confirmed a body lying
##                        across Godot's forward. Fixed s34 with a FACING_OVERRIDES entry.
##                        It stays listed because the STATISTIC still cannot judge it — the
##                        fix was verified by eye, and a future regression here would have
##                        to be caught the same way.
const MESH_UNJUDGEABLE := {
	"fish_glasspike": "needle snout, mass aft — render s34: +Z, default correct",
	"fish_kelp_pipefish": "needle snout + paddle tail — render s34: +Z, default correct",
	"fish_squall_garfish": "billfish, mass aft — render s34: +Z, default correct",
	"fish_anchor_ray": "wingspan is the long axis — render s34: +Z, default correct",
	"fish_ribbon_eel": "curved, X-authored — render s34: head at -X, override added",
}

var _main: Node3D
var _uw: Node3D
var _fail: int = 0
## THE COMPLETION SENTINEL. A script error inside an awaited coroutine abandons it and
## returns quietly to the caller, which then reports FAILURES: 0 over a run that stopped a
## third of the way through (docs/AGENT_TRAPS.md, s27). Set on the last line of the body.
var _done: bool = false

func _process(_d: float) -> void:
	if get_tree().paused:
		get_tree().paused = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = load("res://scenes/Main.tscn").instantiate()
	# A parse error anywhere in the world graph hands back a bare Node with its script
	# dropped, which builds nothing and passes every assertion below vacuously.
	if _main.get_script() == null:
		print("[fishspread] Main.tscn instantiated WITHOUT its script — aborting")
		get_tree().quit(1)
		return
	add_child(_main)
	await _run()
	# THE SENTINEL, CHECKED. `_run` sets `_done` on its own last line; if a script error
	# inside it abandoned the coroutine, control returns here with `_done` still false and
	# the report says so instead of printing a clean pass over a run that stopped early.
	if not _done:
		print("[fishspread] the probe body did not reach its end — a script error inside an "
			+ "awaited coroutine abandoned it. Everything above is a PARTIAL run.")
		_fail += 1
	print("\n[fishspread] FAILURES: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

func _run() -> void:
	await get_tree().create_timer(20.0).timeout
	GameClock.force_phase(GameClock.Phase.DAY)

	_uw = _by_script(_main, "underwater_world.gd")
	if _uw == null:
		print("[fishspread] FAIL: no UnderwaterWorld in the tree")
		_fail += 1
		_done = true
		return

	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player != null:
		player.set_physics_process(false)
		player.set_process(false)
		player.remove_from_group("player")     # or the fauna hunts the lens
		player.global_position = EYE
	# _cull_topside reads the CAMERA, not the player, so the camera is what has to be down
	# here — and it is re-asserted every frame of the swim window below, because the
	# controller keeps integrating across an await (the s21 "a vantage has to be HELD" trap).
	var cam: Camera3D = _camera(player)
	# Measured off the live tree before any snapshot is taken — see _find_pontoons.
	_pontoons = _find_pontoons()
	# THE TIDE IS PINNED TO MEAN WATER FOR THE WHOLE MEASUREMENT. Every depth below is taken
	# against the live drawn sea, and mean water moves 1.4 m over a 12.42 h tidal period — so
	# an unpinned run measures the hour it happened to start at as well as the fish, and two
	# runs of the same build disagree by more than the change being looked for. `Gyre.set_tide`
	# is the hook that exists for this; it is released at the end of _run.
	# (The SWELL is not pinned and does not need to be: `below` is measured against the
	# surface at each fish's OWN xz, and a few hundred fish spread over 100 m of ocean sample
	# the eleven Gerstner bands evenly. What a tide does that a swell does not is bias every
	# sample the same way.)
	Gyre.set_tide(0.0)

	for ph in PHASES:
		GameClock.force_phase(GameClock.Phase[ph])
		await _swim(player, cam)
		await _snapshot_burst(ph)
	# ...AND ONE SQUALL. Two species (the drum croaker chorus and the squall garfish) carry
	# an EMPTY `active` list, which underwater_world reads as "on shift when it is storming"
	# rather than "never" — so a probe that only walks the four daylight phases leaves 20
	# fish per pod unjudged and prints a clean pass over them. `_phase` is pinned alongside
	# `_intensity` because the storm's own _process would ramp it straight back down.
	var st: Node = _main.get("storm")
	if st != null:
		st.set_process(false)
		st.set("_intensity", 1.0)
		st.set("_phase", 2)
		await _swim(player, cam)
		await _snapshot_burst("STORM")
		st.set("_intensity", 0.0)
	Gyre.release_tide()
	_report_stocking()
	_report_spread()
	_report_surface_density()
	_report_goliath()
	_report_facing()
	_done = true

func _camera(player: Node3D) -> Camera3D:
	if player != null and player.has_node("Head/Camera3D"):
		var c: Camera3D = player.get_node("Head/Camera3D")
		c.current = true
		return c
	return null

## THE ALIGNMENT IS ACCUMULATED PER FRAME, NOT AS A NET DISPLACEMENT. The first cut summed
## each pod's displacement over the whole window and took the direction of the sum, which
## reported the herring, the cod, the pipefish and three groupers as BACKWARDS — and every
## one of those was an artifact: a pod wanders a CLOSED circuit, so over a full lap the
## displacements cancel and the residual points wherever the lap happened to stop. What is
## wanted is the correlation the traps file asks for — "correlate travel direction against
## the model's own local axes over a few hundred frames" — so each frame contributes
## dot(mesh head, that frame's velocity) and the answer is the mean of those.
var _dot_sum: Dictionary = {}     # species id -> sum of per-frame alignment
var _samples: Dictionary = {}     # species id -> how many frames went into it
var _dist: Dictionary = {}        # species id -> path length actually swum
## The mesh's head axis in its OWN local frame, per species. A property of the geometry, so
## it is computed once and reused — and computing it once is what makes the per-frame dot
## affordable.
var _head_local: Dictionary = {}

func _swim(player: Node3D, cam: Camera3D) -> void:
	Engine.time_scale = TIME_SCALE
	var prev: Dictionary = {}
	var elapsed: float = 0.0
	while elapsed < SWIM_SECONDS:
		# Re-assert the pose every frame — see the note at the call site.
		if player != null:
			player.global_position = EYE
		if cam != null:
			cam.global_position = EYE
		await get_tree().process_frame
		elapsed += get_process_delta_time() * TIME_SCALE
		for s in _schools():
			var root: Node3D = s["root"]
			if not root.visible:
				continue          # off-shift: hidden, and deliberately not simulated
			var id: String = String(s["id"])
			var fish: Array = s["fish"]
			if fish.is_empty():
				continue
			# One representative member per pod is enough and keeps this O(pods): every
			# member of a shoal shares the pod's heading to within its own orbit wobble.
			var f: Node3D = fish[0]
			if not is_instance_valid(f):
				continue
			var p: Vector3 = f.global_position
			var key: String = "%s#%d" % [id, int(s["pod"])]
			if prev.has(key):
				var d: Vector3 = p - (prev[key] as Vector3)
				# Skip the seat frame and any teleport: a pod's first live frame moves its
				# fish from the world origin, which is not travel.
				if d.length() > 0.002 and d.length() < 3.0:
					var head: Vector3 = _head_dir_world(f, id)
					if head != Vector3.ZERO:
						var a := Vector3(head.x, 0.0, head.z)
						var b := Vector3(d.x, 0.0, d.z)
						if a.length() > 0.01 and b.length() > 0.0001:
							_dot_sum[id] = float(_dot_sum.get(id, 0.0)) \
								+ a.normalized().dot(b.normalized())
							_samples[id] = int(_samples.get(id, 0)) + 1
							_dist[id] = float(_dist.get(id, 0.0)) + d.length()
			prev[key] = p
	Engine.time_scale = 1.0

## One position snapshot per phase, of the pods that are ACTUALLY ON SHIFT — a hidden pod
## is parked at its anchor and counting it would report the night shift as a crowd under
## the rig that no player can ever see.
var _snap: Array = []             # [{id, water, pos, centre, phase, below, buried, band}]
## The two pontoon castings, as world AABBs. Measured off the live tree (_find_pontoons).
var _pontoons: Array[AABB] = []
var _pontoon_measured: bool = false

## THREE SNAPSHOTS A PHASE, SPACED IN REAL TIME. `Gyre.water_time()` runs off the wall clock,
## so a single instant photographs one moment of an eleven-band swell — fine for a plan-view
## statistic (sweep 1 never cared) and not fine for a depth one, where the crest a pod happens
## to be under is worth ±2 m. Spaced by a real-time timer rather than a frame count, because a
## headless main loop runs unbounded and 9 frames there is not 0.15 s (docs/AGENT_TRAPS.md).
const SNAPS_PER_PHASE: int = 3
const SNAP_GAP_SEC: float = 0.4

func _snapshot_burst(phase: String) -> void:
	for i in range(SNAPS_PER_PHASE):
		if i > 0:
			await get_tree().create_timer(SNAP_GAP_SEC).timeout
		_snapshot(phase, i == 0)

func _snapshot(phase: String, verbose: bool = true) -> void:
	var shown: int = 0
	var hidden: int = 0
	# ONE SAMPLE OF THE SWELL CLOCK FOR THE WHOLE SNAPSHOT, the same way underwater_world
	# hoists it out of its own per-fish loop: two fish in one shoal must not be measured
	# against seas a fraction of a millisecond apart.
	var wave_t: float = Gyre.water_time()
	for s in _schools():
		var root: Node3D = s["root"]
		if not root.visible:
			hidden += 1
			continue
		shown += 1
		var water: String = String((s["def"] as Dictionary).get("water", "any"))
		var band: String = String((s["def"] as Dictionary).get("depth", "mid"))
		# The species' own body length, carried into the snapshot so the shallow shell can be
		# split normal/small without a second walk of the table.
		var size: float = float(s["size"])
		for f in s["fish"]:
			if is_instance_valid(f):
				var p: Vector3 = (f as Node3D).global_position
				var surf: float = Gyre.wave_height(Vector2(p.x, p.z), wave_t)
				_snap.append({"id": s["id"], "water": water, "pos": p,
					"centre": s["centre"], "phase": phase, "band": band, "size": size,
					"below": surf - p.y, "buried": _in_pontoon(p)})
	if verbose:
		print("  [%s] %d pods on shift, %d off" % [phase, shown, hidden])

## Is this point inside one of the pontoon castings? A fish in there draws NOTHING, so it
## has to be subtracted from any claim about visible density.
func _in_pontoon(p: Vector3) -> bool:
	for b in _pontoons:
		if b.has_point(p):
			return true
	return false

## THE SLABS ARE MEASURED, NOT RESTATED. The game now keeps shallow fish out from under the
## pontoons with an analytic ceiling built from PONTOON_UNDER / PONTOON_X / PONTOON_Z_*. If
## this probe tested against those same constants it would be the s34 tautology again — it
## would report a clean pass however wrong the constants were. So the boxes come off the live
## tree: rig_builder casts each pontoon as one CSGBox3D, and a CSGBox3D's `size` and
## `global_transform` are honest under --headless (unlike MultiMesh instance data). The
## authored numbers are the FALLBACK only, and the report says which path it took.
func _find_pontoons() -> Array[AABB]:
	var out: Array[AABB] = []
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var b := n as CSGBox3D
		if b == null:
			continue
		# The pontoons are the only 56 x 4 x 8 castings in the rig. Matched on the shape
		# rather than on a name, because the world is built in code and node names are
		# autogenerated.
		if absf(b.size.x - 56.0) > 0.5 or absf(b.size.y - 4.0) > 0.5 or absf(b.size.z - 8.0) > 0.5:
			continue
		var o: Vector3 = b.global_position
		out.append(AABB(o - b.size * 0.5, b.size))
	if out.size() == 2:
		_pontoon_measured = true
		return out
	out.clear()
	for spec in PONTOON_FALLBACK:
		var pos: Vector3 = spec[0]
		var sz: Vector3 = spec[1]
		out.append(AABB(pos - sz * 0.5, sz))
	return out

func _schools() -> Array:
	var v: Variant = _uw.get("_schools")
	return (v as Array) if v != null else []

# ----------------------------------------------------- 0. the census and the bill (s36)

## HOW MANY FISH ARE THERE, WHERE ARE THEY STOCKED, AND WHAT DO THEY COST TO DRAW?
##
## The owner's first two asks are pure census — "increase the fish budget by 50%", "decrease
## small tropical fish by 25%" — and until s36 nothing counted either population. Three
## things are taken here, all off the LIVE tree rather than off data/fish.json, so a species
## that fails to spawn (a missing .glb, a band that lost a pod) shows up as a shortfall
## instead of being restated from the table that was supposed to produce it:
##
##   THE POD LADDER — pods and bodies per depth band. This is what a band-keyed stocking
##   change moves, and it is the one line that makes "the rise went to the surface" legible.
##
##   THE TWO POPULATIONS — pelagic school bodies and reef_fish.gd's tropical community, which
##   are separate systems with separate owners and are the two halves of "overall".
##
##   THE TRIANGLE BILL. New, and it is the finding that shaped s36's allocation: the shipped
##   fish meshes are NOT one budget. The s20-era species import at 25-31k triangles each and
##   the eleven s31 species at 110-199k, because the s31 "they do not need decimating" note
##   was settled on file size and never on geometry. Reported per species and summed, because
##   the schools are now the largest triangle population in the game — larger than the reef —
##   and no probe or profile in this repo has ever said so.
func _report_stocking() -> void:
	print("\n=== the census, and what it costs to draw (s36) ===")
	var by_band: Dictionary = {}          # band -> [pods, bodies]
	var by_species: Dictionary = {}       # id -> [bodies, size, band]
	var bodies: int = 0
	for s in _schools():
		var band: String = String((s["def"] as Dictionary).get("depth", "mid"))
		var row: Array = by_band.get(band, [0, 0])
		var n: int = (s["fish"] as Array).size()
		row[0] = int(row[0]) + 1
		row[1] = int(row[1]) + n
		by_band[band] = row
		var id: String = String(s["id"])
		var sp: Array = by_species.get(id, [0, float(s["size"]), band])
		sp[0] = int(sp[0]) + n
		by_species[id] = sp
		bodies += n
	for b in ["surface", "mid", "deep"]:
		if by_band.has(b):
			var r: Array = by_band[b]
			print("  %-8s %2d pods, %4d bodies" % [b, int(r[0]), int(r[1])])
	# The reef community, counted through reef_fish.gd's own census() — a public query over
	# its live stations, so this is a measurement of that system and not a copy of its table.
	var reef_n: int = _reef_population()
	print("  pelagic schools %4d bodies (s35: %d)   tropical reef %4d (s35: %d)   WORLD %d"
		% [bodies, OCEAN_BEFORE, reef_n, REEF_BEFORE, bodies + reef_n])

	# ---- the triangle bill, per species, off the imported mesh
	print("\n  --- triangles per species (imported mesh x bodies) ---")
	var rows: Array = []
	var total_tris: int = 0
	var over: int = 0
	for id_v in by_species:
		var id2: String = String(id_v)
		var sp2: Array = by_species[id2]
		var t: int = _species_tris(id2)
		total_tris += t * int(sp2[0])
		if t > MESH_BUDGET_TRIS:
			over += 1
		rows.append([id2, t, int(sp2[0]), t * int(sp2[0]), String(sp2[2])])
	rows.sort_custom(func(a, b): return int(a[3]) > int(b[3]))
	for r_v in rows:
		var r2: Array = r_v
		print("  %-26s %-8s %7d tris x %4d bodies = %6.2f M%s"
			% [String(r2[0]), String(r2[4]), int(r2[1]), int(r2[2]), float(r2[3]) / 1.0e6,
				"   <- OVER BUDGET" if int(r2[1]) > MESH_BUDGET_TRIS else ""])
	print("  TOTAL %.2f M triangles of school geometry spawned (the leg reef is 12.55 M);"
		% [float(total_tris) / 1.0e6]
		+ " %d of %d species import above the %dk the rest of the table ships"
		% [over, rows.size(), MESH_BUDGET_TRIS / 1000])

	# ---- the assertions
	_ok(bodies + reef_n >= WORLD_MIN,
		"the world's fish population is up ~50%% — %d bodies (%d schools + %d reef), bar %d, "
			% [bodies + reef_n, bodies, reef_n, WORLD_MIN]
			+ "against %d before s36" % [OCEAN_BEFORE + REEF_BEFORE])
	# THIS BAR IS RED UNTIL THE REEF EDIT LANDS, AND THAT IS THE POINT. The 25% cut is a
	# change to reef_fish.gd's SPECIES table, which s36's fish agent did not own; a probe that
	# went green over an owner ask nobody had implemented is the failure mode this repo keeps
	# writing down. If this fails, the fix is in reef_fish.gd, not here.
	_ok(reef_n <= REEF_MAX,
		"the small tropical population is CUT 25%% — %d reef fish, ceiling %d (was %d). "
			% [reef_n, REEF_MAX, REEF_BEFORE]
			+ "If this fails: the cut is reef_fish.gd's SPECIES `n` column, not this file.")

## Every fish alive under reef_fish.gd, through its own public census(). Returns 0 (and says
## so) if the node is not in the tree, rather than passing an unmeasured world.
func _reef_population() -> int:
	var rf: Node = _by_script(_main, "reef_fish.gd")
	if rf == null:
		print("  !! no reef_fish.gd in the tree — the tropical population was NOT measured")
		return 0
	var c: Variant = rf.call("census")
	if not (c is Array):
		return 0
	var n: int = 0
	for st_v in (c as Array):
		n += ((st_v as Dictionary).get("fish", []) as Array).size()
	return n

## Triangles in one species' imported mesh. Read off the ArrayMesh's index buffer, which is
## resource data and therefore honest under --headless (unlike MultiMesh instance transforms).
## Cached: the same mesh resource is shared by every member of every pod of the species.
var _tri_cache: Dictionary = {}

func _species_tris(id: String) -> int:
	if _tri_cache.has(id):
		return int(_tri_cache[id])
	var n: int = 0
	for s in _schools():
		if String(s["id"]) != id:
			continue
		var fish: Array = s["fish"]
		if fish.is_empty():
			break
		for m_v in (fish[0] as Node3D).find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = m_v
			var am := mi.mesh as ArrayMesh
			if am == null:
				continue
			for si in range(am.get_surface_count()):
				var idx: int = am.surface_get_array_index_len(si)
				# A surface with no index buffer is a plain vertex list.
				n += (idx if idx > 0 else am.surface_get_array_len(si)) / 3
		break
	_tri_cache[id] = n
	return n

# ------------------------------------------------------------------ 1. spread

func _report_spread() -> void:
	print("\n=== where the shoals are (pods on shift, averaged over all four phases) ===")
	var by_water: Dictionary = {}       # water class -> [members, in_box, dist_sum]
	var total: int = 0
	var in_box: int = 0
	var origin_pods: int = 0
	for row_v in _snap:
		var e: Dictionary = row_v
		var water: String = String(e["water"])
		var row: Array = by_water.get(water, [0, 0, 0.0])
		var p: Vector3 = e["pos"]
		var centre: Vector3 = e["centre"]
		# THE TRAP: a pod that never got a live frame is still stacked on its anchor, and
		# every measurement taken off it is fiction that looks like a pass. Checked here
		# rather than over all pods, because an OFF-SHIFT pod is parked on purpose.
		if Vector2(centre.x, centre.z).length() < 0.001:
			origin_pods += 1
		total += 1
		row[0] = int(row[0]) + 1
		row[2] = float(row[2]) + Vector2(p.x, p.z).length()
		if absf(p.x) <= RIG_BOX.x and absf(p.z) <= RIG_BOX.y:
			in_box += 1
			row[1] = int(row[1]) + 1
		by_water[water] = row
	print("  %d fish-samples over %d phases" % [total, PHASES.size()])
	for w in ["near", "any", "open"]:
		if not by_water.has(w):
			continue
		var r: Array = by_water[w]
		var n: int = int(r[0])
		print("  %-5s %4d fish, %4d of them under the rig, mean %.1f m from centre"
			% [w, n, int(r[1]), float(r[2]) / maxf(float(n), 1.0)])
	print("  UNDER THE RIG (|x|<=%.0f, |z|<=%.0f): %d of %d fish (%.1f%%)"
		% [RIG_BOX.x, RIG_BOX.y, in_box, total, 100.0 * float(in_box) / maxf(float(total), 1.0)])

	# The owner's actual question: how much of the water is the NEW eleven?
	var s31_total: int = 0
	var s31_box: int = 0
	for row_v3 in _snap:
		var e3: Dictionary = row_v3
		if not S31_SPECIES.has(String(e3["id"])):
			continue
		s31_total += 1
		var p3: Vector3 = e3["pos"]
		if absf(p3.x) <= RIG_BOX.x and absf(p3.z) <= RIG_BOX.y:
			s31_box += 1
	print("  of which the ELEVEN s31 SPECIES: %d fish (%.1f%% of the ocean), %d under the rig "
		% [s31_total, 100.0 * float(s31_total) / maxf(float(total), 1.0), s31_box]
		+ "(%.1f%% of what is under there)" % [100.0 * float(s31_box) / maxf(float(in_box), 1.0)])

	_ok(total > 400, "the ocean is stocked (%d samples)" % total)
	_ok(origin_pods == 0,
		"every ON-SHIFT pod left its spawn point (%d still on it — those measure nothing)"
			% origin_pods)

	# The near species hold a caisson. Measured against the LEG RING, not against a box,
	# because "tight groups near the legs" is a statement about the structure.
	var near_far: float = 0.0
	var near_pods: int = 0
	for row_v2 in _snap:
		var e2: Dictionary = row_v2
		if String(e2["water"]) != "near":
			continue
		near_pods += 1
		var c: Vector3 = e2["centre"]
		var best: float = 1e9
		for l in LEGS:
			best = minf(best, Vector2(c.x, c.z).distance_to(l))
		near_far = maxf(near_far, best)
	if near_pods > 0:
		print("  worst `near` pod centre is %.1f m from its nearest caisson" % near_far)
		# DERIVED, NOT GUESSED — and the first version of this bound was wrong because it
		# forgot pod 1. A `near` species runs TWO pods about its legs: ±6.5 x ±7.5 and
		# ±9.0 x ±10.5, each with the wander's 16% second octave on top. The furthest a
		# centre can legitimately reach is therefore hypot(9.0, 10.5) * 1.16 = 16.04 m, so
		# anything under 17 is the design working and 24+ would mean a pod escaped its leg.
		_ok(near_far < 17.0,
			"every `near` pod is holding a caisson (worst %.1f m, ceiling 16.0)" % near_far)

	# And the pelagics are OUT. An `open` species averaging less than the rig's own
	# half-width from the centre line is swimming under the rig, whatever the table says.
	if by_water.has("open"):
		var r2: Array = by_water["open"]
		var mean_d: float = float(r2[2]) / maxf(float(int(r2[0])), 1.0)
		_ok(mean_d > 30.0,
			"`open` species average %.1f m out, past the rig footprint" % mean_d)

# --------------------------------------------------- 1b. density near the waterline (s35)

## HOW MUCH FISH IS THERE IN THE WATER THE PLAYER SWIMS AND FISHES IN?
##
## Sweep 1 above answers "how far out are the shoals". It cannot answer this: a pod pushed
## from -1.2 to -4.6 does not move a single metre in plan, so every number `_report_spread`
## prints is identical either way, and the owner's complaint is entirely about that axis.
##
## Figures, and each one exists because a cheaper version of it lies:
##
##   THE PROFILE — bodies per 2 m of depth, on shift. A summary statistic hides the shape,
##   and the shape is the whole finding: before s35 the column read 71 / 52 / 122 across
##   0-2 / 2-4 / 4-6 m — a hole exactly where the player swims and a jam under it, because
##   two of the three most populous pod planes had collided at -4.5.
##
##   THE HEADLINE COUNT — bodies in the top SHALLOW_M metres, inside the rig box. This is
##   what the owner is looking at over the rail.
##
##   THE DENSITY — that count per 1000 m³ of OPEN water in the same shell. The volume has
##   the pontoon castings subtracted, because 896 m² of that plan is solid concrete from the
##   waterline down to -3.05 and counting it as water flatters every reading by ~20%.
##
##   BURIED — bodies inside a pontoon casting. Those draw nothing at all, so they are struck
##   from every count above rather than quietly inflating them. This is the number that was
##   never taken: the model puts it at 27 in daylight before the lid clamp went in.
##
## TWO DEPTHS ARE REPORTED AND ONLY ONE IS ASSERTED ON. `y` against MEAN WATER is the
## reproducible one — the tide is pinned at 0 for the whole run, so it carries no noise at
## all and two runs of the same build agree. `below` against the LIVE DRAWN SEA is what a
## swimmer actually experiences, and it is the honest picture, but a pod at -2.85 is inside
## the top four metres in a trough and outside it on a crest, so a single number off it
## swings with whichever part of an eleven-band swell the snapshot caught. Both are printed;
## the assertions use mean water, which is also what the analytic model behind the bars
## computes, so the bar and the measurement are the same quantity.
func _report_surface_density() -> void:
	print("\n=== density near the waterline (s35) ===")
	print("  pontoons: %s  (%d boxes)"
		% ["MEASURED off the live tree" if _pontoon_measured
			else "AUTHORED fallback — no 56x4x8 CSG boxes found", _pontoons.size()])
	var phases: Array[String] = []
	for row_v in _snap:
		var ph: String = String((row_v as Dictionary)["phase"])
		if not phases.has(ph):
			phases.append(ph)
	# The shell's OPEN-WATER volume: the rig-box slab from the waterline down to SHALLOW_M,
	# less whatever of the pontoon castings falls inside it. Derived from the boxes actually
	# found, so it tracks the geometry rather than a remembered number.
	var shell: float = (RIG_BOX.x * 2.0) * (RIG_BOX.y * 2.0) * SHALLOW_M
	var solid: float = 0.0
	for b in _pontoons:
		var lap_y: float = maxf(minf(b.position.y + b.size.y, 0.0) - maxf(b.position.y, -SHALLOW_M), 0.0)
		var lap_x: float = maxf(minf(b.position.x + b.size.x, RIG_BOX.x) - maxf(b.position.x, -RIG_BOX.x), 0.0)
		var lap_z: float = maxf(minf(b.position.z + b.size.z, RIG_BOX.y) - maxf(b.position.z, -RIG_BOX.y), 0.0)
		solid += lap_x * lap_y * lap_z
	var water_vol: float = maxf(shell - solid, 1.0)
	print("  shell = rig box %.0f x %.0f x top %.1f m = %.0f m3, less %.0f m3 of pontoon = %.0f m3 of water"
		% [RIG_BOX.x * 2.0, RIG_BOX.y * 2.0, SHALLOW_M, shell, solid, water_vol])
	print("  columns are BODIES AT ONE INSTANT. top/next are measured against MEAN WATER;"
		+ " `sea` repeats the top figure against the LIVE swell.")
	print("  %-6s %6s %6s %7s %6s %6s %7s %6s %6s   %s"
		% ["phase", "top4", "4-8m", "ratio", "sea", "inbox", "buried", "normal", "small",
			"profile from mean water, bodies per 2 m"])
	var ratios: Array[float] = []
	var box_counts: Array[float] = []
	var normal_shares: Array[float] = []
	var buried_total: int = 0
	var snaps: float = float(maxi(SNAPS_PER_PHASE, 1))
	for ph_v in phases:
		var ph2: String = String(ph_v)
		var top: int = 0
		var nxt: int = 0
		var live_top: int = 0
		var inbox: int = 0
		var buried: int = 0
		# The MIX in the shallow shell — see NORMAL_M. Split inside the same walk that counts
		# the shell, so the two can never disagree about which bodies are in it.
		var normal: int = 0
		var small: int = 0
		var prof: PackedInt32Array = PackedInt32Array()
		prof.resize(PROFILE_BINS)
		for row_v2 in _snap:
			var e: Dictionary = row_v2
			if String(e["phase"]) != ph2:
				continue
			if bool(e["buried"]):
				buried += 1
				buried_total += 1
				continue           # inside concrete: invisible, so it counts for nothing
			var p: Vector3 = e["pos"]
			var d: float = -p.y                    # metres under MEAN water (tide pinned to 0)
			if d < SHALLOW_M:
				top += 1
				if absf(p.x) <= RIG_BOX.x and absf(p.z) <= RIG_BOX.y:
					inbox += 1
					if float(e.get("size", 0.0)) >= NORMAL_M:
						normal += 1
					else:
						small += 1
			elif d < SHALLOW_M * 2.0:
				nxt += 1
			if float(e["below"]) < SHALLOW_M:      # ...and against the sea as drawn
				live_top += 1
			var bin_i: int = int(maxf(d, 0.0) / PROFILE_BIN)
			if bin_i >= 0 and bin_i < PROFILE_BINS:
				prof[bin_i] += 1
		# Every count above is SNAPS_PER_PHASE samples of the same ocean, so divide back to
		# bodies-at-one-instant. The ratio is unaffected either way.
		var ratio: float = float(top) / maxf(float(nxt), 1.0)
		var bars: String = ""
		for k in range(PROFILE_BINS):
			bars += " %.0f" % (float(prof[k]) / snaps)
		var share: float = float(normal) / maxf(float(normal + small), 1.0)
		print("  %-6s %6.0f %6.0f %7.2f %6.0f %6.0f %7.0f %6.0f %6.0f  %s"
			% [ph2, float(top) / snaps, float(nxt) / snaps, ratio, float(live_top) / snaps,
				float(inbox) / snaps, float(buried) / snaps, float(normal) / snaps,
				float(small) / snaps, bars])
		# The forced squall stocks only the two storm species (40 bodies), so it cannot be
		# held to the same shape as a full shift and is reported but not asserted.
		if ph2 != "STORM":
			ratios.append(ratio)
			box_counts.append(float(inbox) / snaps)
			normal_shares.append(share)
	var mean_box: float = 0.0
	for c in box_counts:
		mean_box += c
	mean_box /= maxf(float(box_counts.size()), 1.0)
	var mean_share: float = 0.0
	for c2 in normal_shares:
		mean_share += c2
	mean_share /= maxf(float(normal_shares.size()), 1.0)
	print("  MEAN over the four clock phases: %.0f bodies in the shell = %.1f per 1000 m3 of water,"
		% [mean_box, 1000.0 * mean_box / water_vol]
		+ " %.0f%% of them >= %.2f m long" % [100.0 * mean_share, NORMAL_M])
	print("  (model, same statistic: 105 bodies / 7.7 per 1000 m3 before s35; 148 / 10.9 after."
		+ " s36 model: 140 / 10.3 before, 253 / 18.6 after; worst-phase ratio 1.63 -> 2.52;"
		+ " normal share 33%% -> 61%%.)")
	# ---- the assertions
	_ok(buried_total == 0,
		"no fish is swimming inside a pontoon casting (%d body-samples were)" % buried_total)
	var worst: float = 1.0e9
	for r in ratios:
		worst = minf(worst, r)
	if not ratios.is_empty():
		_ok(worst >= TOP_HEAVY_MIN,
			"the column is top-heavy in every clock phase — worst phase holds %.2fx as much "
				% worst + "in its top %.0f m as in the %.0f m under it (bar %.2f)"
				% [SHALLOW_M, SHALLOW_M, TOP_HEAVY_MIN])
	_ok(mean_box >= SHELL_MIN,
		"the shallow shell is stocked — %.0f bodies in the top %.0f m over the rig (bar %.0f)"
			% [mean_box, SHALLOW_M, SHELL_MIN])
	# THE ASK THE OTHER TWO BARS CANNOT SEE (s36). "More NORMAL fish to visually fill space":
	# a stocking rise that scaled every species would satisfy both bars above while leaving the
	# shallow water two thirds small fish, which is the state the owner was looking at.
	_ok(mean_share >= SHELL_NORMAL_MIN,
		"the shallow shell is mostly NORMAL-sized fish now — %.0f%% of its bodies are >= %.2f m "
			% [100.0 * mean_share, NORMAL_M]
			+ "(bar %.0f%%, model 33%% before s36 and 61%% after)" % [100.0 * SHELL_NORMAL_MIN])

# ------------------------------------------------------- 1c. the goliath grouper (s35)

## "Make goliath grouper rarer, deeper only, and only appear as huge." Two of those three are
## facts about the WORLD and this is where they are checked; the third — rarity on the line —
## lives in the catch tables and is CatchProbe's to measure.
##
## The species is `fish_barrel_grouper`, whatever the other five *_grouper keys are called.
## It reaches the water two ways and both are counted here: `underwater_world._deep_giants`
## builds DeepGiant/PillarPatrol hosts carrying `slug`, and `_spawn_schools` would build pods
## from fish.json's `school` block (count 0 since s35, so there should be none).
##
## SIZE IS MEASURED OFF THE MESH, NOT READ OFF `_size`. Reading the spec back would be the
## s34 tautology — it would print the number the spawner was given however big the animal
## actually is. The world AABB of the giant's own MeshInstance3Ds is an independent path to
## the same quantity, and it is honest under --headless (these are real MeshInstance3Ds, not
## a MultiMesh).
func _report_goliath() -> void:
	print("\n=== the goliath grouper: rarer, deeper, huge ===")
	var giants: Array = []
	var stack: Array = [_uw]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var slug: Variant = n.get("slug")
		if slug != null and String(slug) == "fish_barrel_grouper":
			giants.append(n)
	var shallow: int = 0
	var small: int = 0
	for g_v in giants:
		var g: Node3D = g_v
		# Merged in the HOST's own frame, not in world space. `global_transform * aabb` is the
		# box of the ROTATED box and it over-reads by however much the animal is pitched — the
		# s34 seal lesson, and here it would bias the measurement toward passing. Taking the
		# host's inverse first strips the look_at and leaves the model's own extent (the same
		# construction tests/catch_size_probe.gd uses on a held fish).
		var inv: Transform3D = g.global_transform.affine_inverse()
		var box: AABB = AABB()
		var found: bool = false
		for m_v in g.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = m_v
			if mi.mesh == null:
				continue
			var lb: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
			box = lb if not found else box.merge(lb)
			found = true
		var length: float = 0.0
		if found:
			length = maxf(box.size.x, maxf(box.size.y, box.size.z))
		var y: float = g.global_position.y
		var verdict: String = "ok"
		if y > DIVE_DEATH_Y:
			verdict = "ABOVE THE DEATH LINE"
			shallow += 1
		if not found:
			verdict = "NO MESH — not judged (still generating?)"
		elif length < GOLIATH_MIN_M:
			verdict = "NOT HUGE (%.2f m)" % length
			small += 1
		print("  goliath  y %+7.2f   %5.2f m long   %s" % [y, length, verdict])
	# The visible schools: fish.json now stocks none, so any pod here is a regression.
	var pods: int = 0
	var pod_fish: int = 0
	for s in _schools():
		if String(s["id"]) == "fish_barrel_grouper":
			pods += 1
			pod_fish += (s["fish"] as Array).size()
	print("  %d ambient/patrol bodies, %d school pods (%d fish)"
		% [giants.size(), pods, pod_fish])
	_ok(giants.size() > 0, "the goliath is still in the world at all (%d bodies)" % giants.size())
	# Before s35 the species put NINE bodies in the water: five slug-carrying patrols (four
	# DeepGiants plus the leviathan, which is a ~45% roll on its own seeded stream) and four
	# school fish across two pods. It is three now — the -17, the -26 resident, and the
	# leviathan. The bar counts only the slug-carrying ones, which is what this walk finds;
	# the school half is asserted separately below.
	_ok(giants.size() <= 4,
		"...and it is RARE — %d patrol bodies, against 5 before s35" % giants.size())
	_ok(shallow == 0,
		"every goliath is below the %.0f m death line (%d were not)" % [-DIVE_DEATH_Y, shallow])
	_ok(small == 0,
		"every goliath is at least %.1f m long (%d were not)" % [GOLIATH_MIN_M, small])
	_ok(pod_fish == 0,
		"no goliath swims in a school — it is a solitary giant (%d school fish)" % pod_fish)

# ------------------------------------------------------------------ 2. facing

func _report_facing() -> void:
	print("\n=== is every species swimming forwards? ===")
	print("  %-26s %8s %7s %7s  %s" % ["species", "mean dot", "frames", "swum", ""])
	var ids: Array = []
	for s in _schools():
		if not ids.has(s["id"]):
			ids.append(s["id"])
	ids.sort()
	for id_v in ids:
		var id: String = String(id_v)
		var n: int = int(_samples.get(id, 0))
		if n < 60:
			print("  %-26s        —       —       —  too few frames to judge (%d)" % [id, n])
			continue
		var d: float = float(_dot_sum.get(id, 0.0)) / float(n)
		if MESH_UNJUDGEABLE.has(id):
			print("  %-26s %+8.3f %7d %7.1f  not judged — %s"
				% [id, d, n, float(_dist.get(id, 0.0)), MESH_UNJUDGEABLE[id]])
			continue
		var verdict: String = "ok" if d >= FACING_MIN else \
			("BROADSIDE" if d > -FACING_MIN else "BACKWARDS")
		print("  %-26s %+8.3f %7d %7.1f  %s" % [id, d, n, float(_dist.get(id, 0.0)), verdict])
		_ok(d >= FACING_MIN, "%s swims head-first (mean mesh-head . velocity = %+.3f)" % [id, d])

## Where this fish's MESH says its head is, in world space. Derived from the geometry the
## generator produced — the vertex centroid sits on the head side of the bounding-box
## centre along the body's longest axis — so it owes nothing to the facing table it is
## checking. Returns ZERO when there is no generated mesh under this node.
##
## The LOCAL axis is a property of the species' mesh, so it is resolved once and cached;
## only the basis multiply is paid per frame.
func _head_dir_world(f: Node3D, id: String) -> Vector3:
	var mi: MeshInstance3D = null
	for n in f.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = n
		if m.mesh != null and m.mesh.get_surface_count() > 0:
			mi = m
			break
	if mi == null:
		return Vector3.ZERO
	if not _head_local.has(id):
		_head_local[id] = _head_axis_local(mi)
	var local: Vector3 = _head_local[id]
	if local == Vector3.ZERO:
		return Vector3.ZERO
	# Into world space through the mesh instance's own basis, which carries every rotation
	# CreatureAnim applied — the model node's yaw AND the host's look_at.
	return (mi.global_transform.basis * local).normalized()

func _head_axis_local(mi: MeshInstance3D) -> Vector3:
	var box: AABB = mi.get_aabb()
	var ext: Vector3 = box.size
	var axis: int = 0
	if ext.y > ext.x and ext.y >= ext.z:
		axis = 1
	elif ext.z > ext.x and ext.z >= ext.y:
		axis = 2
	# Vertex centroid, one surface is plenty — these are single-surface generated meshes and
	# a second surface is a fin cluster that would only sharpen the same answer.
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		return Vector3.ZERO
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return Vector3.ZERO
	var sum: float = 0.0
	for v in verts:
		sum += v[axis]
	var mean: float = sum / float(verts.size())
	var mid: float = box.position[axis] + box.size[axis] * 0.5
	var local := Vector3.ZERO
	local[axis] = 1.0 if mean > mid else -1.0
	return local

# ------------------------------------------------------------------ plumbing

func _ok(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		_fail += 1

func _by_script(root: Node, file: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var sc: Script = n.get_script()
		if sc != null and sc.resource_path.get_file() == file:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
