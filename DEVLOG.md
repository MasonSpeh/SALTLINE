# SALTLINE — development log

**Read this first in a new session.** It is the current state of the project and
what is in flight. `docs/AGENT_TRAPS.md` is the other required read — it is the
list of things that have already cost hours here.

Newest first. One entry per working session. Keep entries short: what changed,
what it revealed, what is still open. Detail belongs in the commit message; this
is the index.

---

## Current state

- **Branch:** `main`, HEAD at the s34 close-out.
- **Engine:** Godot 4.7, `gl_compatibility`. macOS.
- **Tests:** `godot --headless --path . res://tests/TestRunner.tscn` → 242 pass,
  `FAILURES: 0`. Keep it there — and run the FULL suite after every change, not the probe
  that targets what you think you touched (a s31 regression shipped that way; see s33).
  Windowed-only, because they read MultiMesh instance transforms or take pictures:
  `tests/ReefProbe.tscn`, `tests/ReefFishProbe.tscn`, `tests/FogShot.tscn`,
  `tests/S34Shot.tscn`. Headless probes worth running as a set: CatchProbe, SpearProbe,
  TideProbe, SunkProbe, SealApproachProbe, FaunaBugsProbe, FishSpreadProbe, DeclutterProbe,
  CatProbe.
- **Shipping target:** itch.io. Windows packaging is `tools/package_windows.sh`;
  player-facing instructions live in `dist/START HERE - How to Play.txt`.

### What the game is
First-person survival on an abandoned North Sea oil rig, in an ocean the Bloom
has mutated into cold teal light. The rig is built **in code** by
`scripts/world/rig_builder.gd` and the dressing scripts it spawns — the
positions in those scripts *are* the level design. There is no scene file to
open and drag things around in.

### Tools that exist (use them)
- **sonar MCP** — a live spatial oracle over a real scan of the rig. Wired via
  `.mcp.json`, scan in `.sonar-rig/`. **Call `scene_brief` first**; it returns
  `RIG_ATLAS.md` with the coordinate mapping and zone list. Use `props_find`,
  `spatial_probe`, `spatial_raycast`, `spatial_measure` instead of guessing
  coordinates. Refresh after rig edits with `tools/export_rig.sh`.
  *This is the single most under-used tool in the project — most of the
  "floating prop" bugs found in s17/s18 would have been caught by probing.*
- **`.claude/skills/realistic-animals/`** — text→3D asset pipeline (Tripo
  default, Meshy fallback). Key in `.env`, which is gitignored.
- **Screenshot harnesses** — `tests/*Shot.tscn`. Must run **windowed**.
  `tests/CandShot.tscn` photographs a raw GLB straight off disk, which is how
  generated candidates get judged before anything is wired in.
- **Probes** — `ContentProbe`, `PlacementProbe`, `LabelAnchorProbe`,
  `LightAnchorProbe`, `CatchProbe`, `CrabLifeProbe`, `HandbookProbe`,
  `FaunaDegenerate`. Prefer adding a probe over asserting in prose.

---

## Working agreements

These exist because the project is a long-running, multi-session build and the
same mistakes kept recurring.

1. **Probe, don't guess.** Never hand-type a Y coordinate. Every floating-prop
   bug in this repo traces to an authored constant that drifted from the real
   geometry.
2. **Verify by looking.** The owner judges by screenshot. Render it, *read the
   PNG back*, iterate until it is right — then show it. Never claim a visual
   result that has not been looked at.
3. **Measure, don't assert.** "Feels faster", "should be fixed" and "the shadows
   are better now" are not results. Numbers are.
4. **Commit verified work promptly.** Sessions have been lost to crashes and API
   stalls. Anything green and finished goes in a commit, immediately.
5. **Report honestly.** If a thing is blocked, partial, or was skipped, say so in
   the same message. Do not let a completion summary imply more than was done.
6. **Record what bit you.** New trap → `docs/AGENT_TRAPS.md`, same session.

---

## Sessions

### s23 — 2026-07-30 (the winch's hold, the bench, and four owner items)

**THE DRUM WAS ON THE LEFT BECAUSE THE POSE AIMED THE WRONG AXIS — and then because the model
could not do it.** Third report. s22's `HAND_TOOL_POSE` named the winch's `face` as the drum's
AXLE (+Z, the crank side), which the solve satisfied exactly while leaving *which side the drum
stands off* completely unconstrained: measured on the composed basis, the bracket came out
(-0.81 left, +0.10 up, -0.57 away). `face` is now the BRACKET, stated the way the rod's is. That
alone could not deliver the owner's ask, because mast-up + drum-right forces the crank away from
the camera by the right-hand rule — the determinant -1 s22 recorded as impossible. **So the model
is mirrored** (`item_visual._mirror_x`), which is what "it should default hold/lean to the OTHER
side" asks for in as many words. Mirrored in X, not Z, to keep the icon (ItemIcons looks in along
+X+Y+Z), and node-by-node rather than `scale.x = -1`, which would render the machine inside out.

**Idle 0.88 right / 0.33 up / 0.33 toward the player, crank 0.90 back at the player. Cast 0.78
up.** Two poses, both photographed at two yaws and framed off the render: the first cut put the
fairlead at (626, 212) of 1280x720 with the lead hanging under it finishing ON the crosshair, so
the head is canted further away and the tool lifted and pushed right (fairlead now 668, 215; the
drum reaches x~1185 of 1280). **The weight and hook are gravity-aligned every frame**
(`_hang_stowed_tackle`, tackle down·(0,-1,0) = 1.000) rather than carried by the pose — it is the
one part of the machine gravity owns, so it is the one part that is not aimed. `RodHandProbe`
20 → 34 assertions, FAILURES 0, and the winch's cast pose is asserted for the first time.

**The rest of the owner's list.** The spawn rod is gone (`wet_deck_detail._scatter_items`, the
one at (16.5, -16.75) on open plate outside the store-room east wall — the storeroom and rec-room
rods stay, so fishing is now behind a door). **A full pack no longer eats the catch**:
`fishing_rod._land()` drops it at the player's feet as a real savable Takeable, the same
`SaveManager.drop_into_world` spill path `cook_stove._finish` uses, and says so in the toast; the
journal entry, the size roll and the fillet count all still run. The cold warning had **no
cooldown at all** and the Wet Deck sits low enough that a running swell puts the player under the
wave line repeatedly — now 120 s (`COLD_WARN_COOLDOWN`). **Warmth runs 1.30x at a flame**:
`WarmthZone.fire` (default true, opted out by the lean-to, bedroll and windbreak), counted in
`PlayerState.warmth_fire`, multiplier in `data/tuning.json` — and the galley range, the one
appliance a player stands at for minutes, had no WarmthZone at all until now.

**The rigging bench is the pack's UI now, and its parts are on the table.** Slot grid with the
same riveted styleboxes, the same 4/8-wide squares, real item renders through the shared
`ItemIcons`, name+count strips, hover names, hazard rule, locker-steel panel. New MATERIALS
block: every ingredient as `<on the bench> + <in the pack> / <needed>`, green when the bench
covers it, amber when the pack can, red when the rig cannot — shown for the finished match AND
for the nearest partial. And the laid parts are **`ItemVisual.build()` meshes on the real
surface**: the old code drew four pastel boxes at a hand-typed local y = 1.08 over a carcass
whose top is +0.45, i.e. floating 0.63 m. The top is now MEASURED (0.500 local, world 2.950,
seating error +0.0 mm on all parts, probe 1.2 ms cold and cached) — and it had to be measured off
the WELDED dressing's triangles, because the 1.7 x 0.06 x 0.8 work top both benches wear is built
onto rig_builder, not onto the bench, and `rig_batcher` has already eaten the node.

Tests: `TestRunner` 241 pass, **FAILURES: 0**. `RodHandProbe` **FAILURES: 0**. New harnesses:
`tests/WinchPoseShot.tscn` (idle + cast + a candidate sweep, ~1 min against ToolFinal's several)
and `tests/BenchShot.tscn`. Screenshots: `/tmp/winch_s23/`, `/tmp/bench_final/`. Six new traps in
`docs/AGENT_TRAPS.md`. **Not committed** — the owner asked for the work uncommitted.

### s23 — 2026-07-30 (five owner-reported fauna bugs)

**1. The pyramid snails were crawling BACKWARDS, and it was the mesh, not the code.** A
`pyramid_snail.glb` landed in s20 for a class explicitly written expecting `ANIM.replace` to
return `{}`, so its authored facing had never been checked. `tests/FaunaBugsProbe` correlated
**2,691 frames of real crawl** on three live deck snails against the model node's six local
axes: **model +Z . travel = +0.9991** (+X +0.005, +Y 0.000), and CandShot's side view puts the
eye stalks and both oral tentacles at the **min-Z** end while the front view photographs the
back of the shell with no head in it. Head at local −Z, i.e. the default's 180 yaw was putting
the tail on Godot's forward. `FACING_OVERRIDES["pyramid_snail"] = yaw 0, flip 0` — the
herring_gull case. Re-measured after: **−0.9989**, and photographed from the animal's own live
heading (`snail*_ahead_MUST_SHOW_HEAD.png`) so a reversed mesh could not pass.

**2. THIRTEEN species have been rendering as black mirrors.** The owner's "they seem extra dark
in game, moreso than their model" is not a snail problem: Godot's glTF importer writes
metallicFactor/roughnessFactor into the material SCALARS and the real values into a texture,
and every Tripo-era asset here ships **metallic = roughness = 1.0** with the map in
`metallic_texture`. `creature_swim` read only the scalars, so `pyramid_snail`, `herring_gull`,
`ultra_hammerhead`, all ten `trop_*` and five deep fish were fully metallic with no reflection
probe under them. The three shaders now sample the map through a channel mask read off the
material. That alone brings the three DECK snails up to the model render; the six on the
caisson faces 11–19 m down still photographed as pure black silhouettes (the s21 "a lit surface
at depth is black whatever its albedo" trap), so the species carries an albedo-keyed
`body_glow` — **0.95 submerged, 0.12 on deck**, deliberately under leg_reef's 1.35 and
reef_fish's 1.25 so it never out-glows the coral it sits on.

**3. The reef fish glitch was `rate` being a TIME MULTIPLIER, twice — once in the shader and
once in GDScript.** `reef_fish.gd` pushed `pace * 2 * lerp(1, 2.2, alarm)` through `drive()`
every frame the player walked toward a shoal (at TIME 100 s a 0.02 step is two whole cycles of
phase teleport) AND sampled its own octaves at `st["t"] * pace` off a clock seeded up to 400 s.
Measured on a 10-fish damsel shoal, player closing 12 m → 1.2 m: mean speed **0.13 m/s at
alarm 0 → 1.13 m/s at alarm 0.105**, mean |acceleration| **0.2 → 45 m/s²**. The shoal detonated
at the first touch of alarm and then jittered. Fixed by integrating the PACED time
(`t += dt * pace`) and spending the alarm on AMPLITUDE, which lives outside the sine; the wave
rate is now build state and is never written to a different value. Third fault in the same
loop: `maxf(out, MIN_STAND)` was rectifying the standoff — the probe measured **exactly
0.450 m** at every sample of a 420-frame approach at every alarm level — so clearance is now
structural (`MIN_STAND + span * a_non_negative`) and the clamp is gone. After:
0.148 → 0.227 m/s across the approach, |acceleration| **0.2 m/s²** throughout, min wall gap
0.476 m. `ReefFishProbe` 7/7, startle intact (shoal still pulls 0.86 → 0.62 m off the wall).

**4. Ray heights staggered, and the ceiling is not what it looks like.** Owner: "stagger ray
height… up to 15ft higher depending on randomness". The three band_y values are now the FLOOR
of each animal's range. Worth writing down: the obvious cap is the caisson feet and there
aren't any — `rig_builder` makes each leg ONE 6 × 109 m casting from y +17 to −92, so the
horizontal orbit is the only thing that has ever kept a ray clear. What a lift can actually hit
is the reef overhead (coral band bottom −22.00, deepest tropical station −21.4), so the cap is
band + lift + wander + a banked half-span ≤ **−24.0**. Three independent uniform draws
collapsed the bands from a 4.0 m spread onto **2.1 m** on the first seed tried — less staggered
than before — so the draw is stratified by depth rank: shallowest animal, top third of the
range. Shipped: floors −36.0/−33.5/−32.0 + lifts **0.34 / 2.99 / 2.60 m** → bands
−35.66 / −30.51 / −29.40, a **6.26 m** spread, wingtip tops −29.46 / −24.76 / −24.00.

**5. The grubs were tide worms, and `replace()` had orphaned their whole behaviour.**
`TideWorm` drives emergence, retraction, sway and visibility on `_body` — four procedural
spheres — but `CreatureAnim.replace()` hides those and parents the generated mesh to the HOST.
Measured at all five spots: 6 meshes of which exactly **1 visible**, `_emerge` 0.000 and
`_body.visible` false, i.e. the code believed the animal was underground while a 0.32 m worm
sat on the plating. And its per-frame drive was `rate = 1.1 * _emerge`, so at rest the vertex
wave was multiplied to **zero** — a frozen grub, all day, every day. The generated mesh now
rides `_body` and SINKS through the plate (it is one closed mesh; squashing it would pancake
it), the beat is constant with amplitude carrying the emergence, the den mouth is built AFTER
the replace so it is not hidden, and crouching halves the animal's spook radius so it can be
watched. Measured at dawn with the player 8 m off: `_emerge` 1.000, the body's low point
travels **y 1.772 → 2.009** (the plate top is 2.000), and at 0.9 m it is back to 0.000.
**Not made collectable, deliberately** — a new bait item needs a mesh registered in
`item_visual.gd`, which another session owns; filed as a follow-up.

**6. The seal's haul-out was already right; the SWIMMING seal was the one hovering.** The
pontoon seat measures a **0.0 mm** gap (independent floor probe, fauna colliders excluded), so
`_snap_haul`/`low_point` are fine. The patrol wrote a fixed `y = −0.15 + porpoise` into an
ocean whose surface is an 11-band Gerstner sum: measured over 600 frames, the belly was clear
of the water on **134 of them (22.3%)**, by up to 379 mm. Depth is now taken from
`Gyre.wave_height()` at the animal's own xz — **0 of 600** frames above the surface, worst
belly-to-sea −0.502 m, so the arc still lifts its back and head clear to breathe.

Tests: `TestRunner` **FAILURES: 0**, `ReefFishProbe` **7/7**, `PyramidWanderProbe` 0 failures.
`ReefProbe` reports **FAILURES: 2** — both PRE-EXISTING and proved so by an A/B with the new
facing entry removed (identical failures, identical counts): one climbing snail's crawler frame
has gone degenerate (tilt exactly 0.00 is `SurfaceCrawler.basis()` returning identity) and the
same animal leaves its face. Filed, not fixed.

**Also found, not fixed:** `pyramid_snail.glb` shipped **undecimated at 482,018 triangles**,
nine instances = 4.34 M tris, about the whole leg reef again. Filed.

Screenshots: `/tmp/fauna_s23/` (snails ahead/behind/side, seal hauled + swimming, damsel and
anthias approach ladders) and `/tmp/fauna_s23c/` (snails after the body_glow, incl. three on
the caisson faces). New harnesses: `tests/FaunaBugsProbe.tscn` (headless, all five bugs
measured off one world build) and `tests/FaunaBugsShot.tscn` (windowed, the three visual ones).

### s22 — 2026-07-29 (the owner's two fishing tools, installed and aimed)

**The owner picked from the contact sheet and both picks are in.** `deep_rig_pole` is now
option B, the **DECK WINCH** — 69 meshes / 7,916 tris, "not a rod at all": foot, mast, one big
flanged drum wound with braid, crank, ratchet and pawl, brake shoe, one diagonal, and the line
leaving over a bent **hoop fairlead**. `fishing_rod` is option 3, the **WAND** — 63 meshes /
9,612 tris, a 19→3 mm blank over 2.10 m with 8 guides stepping 30→8 mm. Ported out of
`tests/tool_options.gd` into `scripts/world/item_visual.gd` with the shared sub-assemblies
(gimbal, taped grip, lever-drag reel, terminal tackle) and the 12-colour palette lifted with
them, so the two tools still read as one man's kit. The `MIN_EXTENT` guards and the low
`rings`/`ring_segments`/`segments` counts came across unchanged.

**ICON_FOCUS, judged at 74 px and nowhere else.** Four candidate frames per tool were rendered
on ItemIcons' own stage and read side by side at the real slot size: the winch takes **0.62 m**
(tighter crops reduce the outline to "a wheel and a bar"; at 0.62 it is a wheel on a post with an
arm over the top — unmistakably not the rod beside it) and the wand takes **0.40 m**, tighter
than the rod it replaces, because 2.10 m of a 19 mm blank is a **111:1** sliver and its reel is
scaled 0.84 against the old 0.95. `ICON_FOCUS` is a `const` Dictionary and therefore read-only,
so the sweep re-implements eight lines of framing and then PROVES the copy: candidate 0 renders
byte-identical to the shipping `get_icon()` (diff 0.0000).

**THE HELD ROLL WAS NOBODY'S ANGLE.** Owner, twice: "fishing poles still oriented on side… when
casting it goes reel/bail up… flip default side to the right… give slight tilt". Measured on the
composed basis, the rod's blank came out 0.94 UP (near vertical) and its reel stuck out
(+0.85 right, +0.20 up) — the reel BESIDE the blank, as the product of six stacked Euler angles
across three nodes that nobody wrote as a roll. So `HAND_TOOL_POSE` no longer holds angles: it
names the model's long axis and the axis its reel/drum stands off, names where each must point in
CAMERA space, and `_apply_hand_pose()` solves it and divides the mount angles and the model's own
lean back out. **TWO poses per tool** — the rod idles up-and-out to the RIGHT with the reel on
top and canted back (reel-up 0.57 against 0.16 sideways) and swings to reel **squarely up** for a
cast (0.89) while the blank drops toward the water. `tests/RodHandProbe.tscn` grew 20 → 31
assertions and asserts exactly that, including that the two poses differ.

**Two leads on one line, fixed.** The winch carries its terminal tackle hove up short under the
fairlead, and `fishing_rod.gd` spawns its own lead for a cast — so a live cast drew the lead
twice. The model's copy now lives in a node named `stowed_tackle` and the controller hides it for
the duration of a cast (asserted).

**The cast is photographed, not asserted.** Off the crane machinery deck (y 34.15), heaved NORTH
because that is the only quarter with sea under it — the topside deck runs z[−20,20] and the wet
deck starts at x 6, so from the crane's x 3.6 the lead clears the footprint and lands at
(3.6, 0, −34.7), 40.0 m of line at the splash and 53.7 m at 15 m down. The line leaves the
**hoop**, not the fist: on screen the fairlead is 389–451 px from the fist and the crop centred
on the projected marker shows the line running through the hoop.

**The SECOND yellow box was the LINE-THROWING SET** — `wet_deck_detail._boat_landing()`, one
`MatLib.flat(Color(0.85, 0.45, 0.1))` BoxMesh, 0.5 × 0.3 × 0.3, at (26.7, 2.16, −20.5), **2.69 m
from the Dock Locker**, on open deck plate in the walk from the gangplank to the stair tower. No
node walk can see it (welded into `MergedDressing`, and its own material appears on no chunk), so
it came off the PIXELS: the blob at (830, 310) of the frame taken 2.4 m east of the crate, and the
box's own projection lands at (848, 319). **Kept and re-materialled** — every landing carries one
and it is labelled — as `sphl_orange()` GRP with a proud lid, a seam, two galvanised clasps and a
rubber carry handle. Also found in the same sweep and given a mould seam and a hauling eye: the
yellow **Snagged Float** (`harvest_nodes._snagged_floats`, 0.34 m of `MatLib.flat`, 6.9 m off the
crate) — real interactable salvage, so it keeps its colour; a trawl float IS one flat plastic
colour, it was the lack of any evidence of manufacture that read as placeholder.

Tests: `TestRunner` **FAILURES: 0**, `RodHandProbe` **31/31**. Screenshots:
`/tmp/tool_final8/` (icons at 74 px, idle + cast for both tools, the cast off the crane, the
fairlead crops) and `/tmp/yellow_before/` vs `/tmp/yellow_after/` (96 frames each, same spots).

**Still open, deliberately:** the fishing line is 12 mm thick, so at 40 m it is a quarter of a
pixel — legible against dark water and side-on, nearly invisible looking straight down it. And
the rod's reel reads as LEFT-hand wind: the model's triad makes reel-up + crank-right +
tip-away geometrically impossible without mirroring the reel, which would move the crank off the
side the icon camera sees.

### s21 — 2026-07-29 (harvestable mussels)
**The reef became food.** Owner brief: mussels scattered through the coral, boiled in a pot
on the stove to be worth eating, regrowing five days after picking. Until now the whole
1,170-instance leg reef was look-at only; this is the first thing down there a player can take.

**Assets — two, not one, and the reason is the pipeline.** The reef cluster is cut by
`tools/decimate_reef.py` (base seated at y=0, +Y = growth, so its up goes onto a probed
normal); the pack item is cut by `tools/decimate_fish.py` (centred on all three axes, which
is what `PropLib._fit` and the icon camera want). Same subject, incompatible contracts.
Shipped: `mussel_bed_e` (4,200 tris — nine big shells flat in one layer, ext 0.92/**0.18**/1.00,
the low encrusting mat the brief asked for), `mussel_clump` (3,000 — six shells in a rosette,
the accent), `items/mussels` (3,000) and `items/mussels_boiled` (4,500 — hinged open with
orange meat, which is why it earns half again over the raw one).

**Rejected on the render at the shipping ratio — all four first-round beds.** `mussel_bed_a`
(1.03/1.01/1.03 on its axes: a radially symmetric BALL, the barnacle_goose signature, and a
total shatter), `mussel_bed_b` and `mussel_bed_c` (best silhouettes of the four but shattering
at the shell tips), `mussel_clump_d` (0.97/0.97/0.99 — another ball). One cause: all four
prompts asked for 22-30 shells, which at 4,200 tris is ~140 triangles a shell against the few
hundred a shell needs to stay closed. Round 10b asked for NINE and TWELVE big shells and both
held; `mussel_bed_f` still shattered and was cut, `mussel_bed_e` shipped. Also rejected
`mussels_hand_a` (a lumpier heap whose shells stop reading as separate shells) in favour of
`mussels_hand_b`, which was then re-cut through the *reef* decimator as `mussel_clump` — the
one asset that earned a place in both sets. 9 generations, 180 credits, 840 left.

**Placement** (`scripts/world/mussel_beds.gd`, new; two lines in `leg_reef.gd` spawn it, the
same contract `reef_fish.gd` already had). **24 beds, 6 a leg, 95 meshes, 241,800 tris**, each
bed one mat plus two accent clumps seated by their own raycasts. Seeded from leg_reef's
`colony_seats`, so a bed can never land on concrete the reef's own spacing rejection left
bare. **Seating measured: 71 patches, 0 without a collider under them, mean gap −28.0 mm
(i.e. exactly the authored recess, on the inside), worst up-axis-vs-face-normal 3.81°.**

**How deep a bed may be is DERIVED FROM THE PLAYER'S LUNGS, not chosen.** The coral band runs
to y −22 and a breath-hold dive cannot return from there, so `_dive_floor()` integrates the
controller's own drain (`OXYGEN_DRAIN` above `DEEP_UNEASE_M`, `OXYGEN_DRAIN_DEEP` below it)
over a round trip at `SWIM_SPEED` plus the work seconds, and takes the deepest depth that
leaves a quarter of the breath unspent: **y −18.30**. Beds sit −12.92 to −17.70; the deepest
costs **71% of one breath**. Food the player cannot reach is not food.

**FIVE DAYS is on the calendar, not on a countdown.** `GameClock.game_time_hours()` (new) is
absolute game time, monotonic across both a phase advance and a sleep, and `Salvage` gained
`regrow_game_hours` / a `regrow_days` def field that keys off it. This matters because
`skip_to_next_dawn()` advances the calendar without spending any real seconds: a five-day bed
counted in `delta` would sit bare through five slept nights and then regrow after five real
hours of standing next to it. **5 game days = 120 game hours = 18,000 real s (5.00 real h) at
`time_scale` 1.0, or five sleeps.**

**Salvage now persists — all of it.** Nothing about `Salvage` was ever saved, so a player
could gut every locker and scrape every tar seam, save, reload and find the rig whole. There
is a `harvest` payload keyed by position, and because the reef is built two physics frames
after `load_game()` runs, each node claims its own state on arrival through
`SaveManager.claim_harvest` — the deferred hand-off `LootContainer` already used.

**Cooking: the range keeps the interaction, the pot became the range's.** A second
interactable pot was rejected — the interaction ray only sees the first collider it hits, so
it would have fought the range for the prompt at the exact distance a player stands to use
either, and it would have had to re-implement the power gate, the mid-cook power loss that
hands the food back raw, the pack-full spill and the timer. Instead `cook_stove.gd` builds the
pot on the left hob in its own local space and a boil looks nothing like a sear: the hob ring
lights, the water goes frothy and rolls, steam climbs off it, and the oven window stays cold.
The verb reads **BOIL**. One line came out of `rig_builder` (the inert CSG cylinder that used
to stand there) and one out of `interior_props` (`brass_pan_01`, which occupied the same 40 cm
ring — `brass_pot_01` stays on the right hob).

`tests/MusselProbe.tscn` **24/24 PASS**, headless-safe (these are real nodes, not MultiMesh,
so the identity-transform trap does not apply). `tests/MusselShot.tscn` renders the whole
feature from one world build. `TestRunner`: **245 pass, FAILURES: 0** — measured before and
after this work, unchanged by it (the DEVLOG's old 238 predates a concurrent session's tests).

**Four silent failures, all now in `docs/AGENT_TRAPS.md`:** a bed and all three of its patches
seated on a passing snail's `FaunaTouch` sphere (the s20 trap again, this time in placement
rather than in a probe — the tell was three "wall normals" of (0.32, 0.16, −0.93) on a wall
whose real normal is (0,0,−1)); the probe's day-advance SET the intra-day position instead of
adding to it, so 4.5 days + 0.6 days advanced 4.6 days and reported the feature broken; the
harvest never completed because `Salvage._work` counts REAL seconds and a headless main loop
runs unbounded, and the diver drowned mid-job so `_work` correctly abandoned it; and the
picked-bed scar rendered near-black at three different albedos because it was LIT on an
unlit wall — the coral around it is not lit either, it is emissive.

Screenshots: `/tmp/mussels_s21_final/` (17 frames — six bed close-ups, two among-coral, a leg
wide, the GATHER prompt, a picked bed, the pack, and four galley frames).

**Note for whoever re-cuts these.** The raw `_cand10` downloads were removed by this session's
own "purge superseded generation staging" commit, so a different decimation ratio is no longer
free off disk — but every task id was logged at submit time and lives in
`scratchpad/round10_task_ids.json` and `round10b_task_ids.json`, so it is one
`GET /v2/openapi/task/<id>` → `data.output.pbr_model` away rather than a re-generation.
`mussel_clump` and `items/mussels` are both cut from the same download (`mussels_hand_b`,
task `8f82ee2a…`), through the reef and item decimators respectively.

### s20 — 2026-07-29 (tropical reef fish)
**Ten small reef species living on the leg coral**, anchored to real colony
positions rather than patrolling waypoints. Each fish belongs to a **station**
for the whole game — position is that station's seat on the coral plus a
multi-octave offset — so schooling behaviour cannot get lost off, and it varies
independently by school size, depth band, wall-hugging tightness, skittishness,
pace and night shutdown: clownfish trios that never leave one coral head,
50-strong damsel shoals (the most skittish thing on the reef), a solitary
triggerfish that closes on the player instead of fleeing, bonded butterflyfish
pairs. **252 fish, 55 stations, 352k tris**, meshes decimated 2.08M → 16.2k
(`tools/decimate_fish.py` — centres the pivot on all three axes rather than
seating the base at y=0 like the reef decimator, because a swimmer's `look_at`
has to pivot about its centre, not its belly).

**Measured cost: zero on deck** (0/55 stations live, +0 tris, +0 draws — inside
the existing topside cull), **+0.5–0.9 ms underwater**, at or near this
machine's own noise floor. The file never calls `Gyre` — the exact per-frame
pattern that cost the existing schools 3.7 ms at the waterline was deliberately
avoided from the start.

`tests/ReefFishProbe.tscn`, 7/7 PASS: caisson clearance 0.450 m minimum, 0
fish-samples inside the pontoon slab, every species inside its own home range,
all 55 seats on a real caisson face, startle measured (damsels pulled the shoal
0.83→0.58 m off the wall), and **all 252 models carry the authored rotation** —
worth calling out because facing came back in **three different conventions
from one prompt template** (some face +Z, some −Z, two are authored along local
X), all measured off `CandShot` rather than assumed, in `FACING_OVERRIDES`.

**Design call flagged for review, not decided unilaterally:** the shallow band
(clownfish, yellow tang, damsel) sits inside the kelp forest — the innermost
kelp strands are 200 mm off the concrete at that depth. Reads as fish
discovered among kelp, which seems right, but it's the owner's call to
overrule.

### s20 — 2026-07-29 (lush leg reef)
**The caisson reef became an ecosystem** (owner brief: brighter bloom, more coral,
sponges and barnacles, sculpted reef *masses*, bigger starfish all down the legs,
and snails climbing them). Tripo round 9 (`_cand9`), 15 reef candidates.

**Rejected by render, at the shipping decimation ratio** (`tests/CandShot.tscn`):
`sponge_fan` — two thirds of it is a smooth pale trumpet foot, the same
reads-as-a-plinth failure that cut `coral_encrust`; `star_big_blue` — glassy cobalt
with bent arms and a warped side profile, the plastic-toy default; `barnacle_goose`
— a radially symmetric spiky ball (0.97/0.99/0.93 on its three axes), not a bunch
of stalked shells, and its spines decimated into loose shards. It also 502'd
mid-poll on the first attempt and was regenerated, which paid twice — the task id
was not logged at submit time. **Kept 12**: 4 reef masses, 3 sponges, 2 barnacle
crusts, 3 big starfish.

**Decimation** (`tools/decimate_reef.py`, now with a slug-list argument, a search
path over both `_cand` roots, and a measured auto-orient rule for flat/blade pieces
instead of a hand-written rotation table). Every s19 coral was re-cut one notch
leaner to pay for twice the instances — and **three of them had to go straight back
up**: brain, bubble and the barnacle crust shatter into loose facets below ~4k
because their detail is a dense field of small bumps. Branching and fan silhouettes
are fine at 5–6k, flat starfish at 2k. The floor is set by surface type, not size.

**Numbers.** 560 → **1,170 instances, 62 MultiMesh draws, 4.34 M tris** across 21
species. Per leg ~0.94–1.03 M (was 0.62–0.72 M), foundation 0.43 M — one MultiMesh
per species per leg still means looking at one leg culls the other three, at ~15
draws for that leg. Seating: **0 floating, 0 buried, median +64 mm recessed**, and
**0 of ~2,400 seating rays fell back** to the sonar face. Big starfish: 11 attempts
a leg produced only 41 in the whole ocean once the spacing rejection had had its
say, so the attempt count went to 18 and a star's claim radius came down from 0.62
to 0.44 of its size (a flat animal lies ON the reef rather than competing with it) —
**79 big starfish**, on the legs as well as the foundation.

Not re-profiled: s19 measured the 560-instance reef at 1.98 ms (8.5%) at
`submerged_deep`. This is ~1.45x the per-leg triangles and 2.1x the instances and
the cost has NOT been measured. Filed in `KNOWN_ISSUES.md` with the cheapest levers
in order, since a concurrent session owns the frame budget.

**Emission: 0.15 → 0.50.** `main.gd` blooms above `glow_hdr_threshold = 0.8`, so the
s19 value produced no bloom whatsoever — it was a slightly brighter texture. The
first attempt at 1.35 rendered the reef as featureless white (MultiMesh vertex
colour multiplies albedo, *not* emission, so past ~0.7 emission swamps every tint).
`ReefShot.tscn --glow=a,b,c` was added to sweep it off one world build; 0.50 read
off the ladder as the top of the range that keeps the reef's own colours.

**Snails.** 13 on the caisson faces — 7 lamp (moon-white, own light) + 6 pyramid —
spawned from `leg_reef.gd`, not from the shared `bloom_fauna.gd`. Three things a
wall crawler needs that a deck crawler does not are set on its `SurfaceCrawler`
after `add_child`: `up` = the probed face normal, a heading with a real vertical
component, and `climb_base` = the spawn Y (or `CLIMB_MAX`'s "six metres above the
foothold" is measured from y = 0). `PyramidSnail` re-picks its heading in world XZ,
which on a vertical wall projects to *pure sideways* — its timer is pushed out of
reach and `LegReef._process` hands it a heading in the FACE plane instead. Seeded
only where a raycast found real collider (`_probe` reports its fallbacks; 0 refused).
Verified in `ReefProbe`: foot on the face within +20 mm, body-up vs face-normal
1.00, 13 of 13 crawling, 13 of 13 still on a face after 3 s.

**Three silent failures, all now in `docs/AGENT_TRAPS.md`:** every creature carries
a solid 0.6–0.85 m `FaunaTouch` sphere on the default layer, so putting snails on
the caisson made `ReefProbe` report the caisson had moved **606 mm** and 19 flush
corals as buried by up to **926 mm** — confident, stable, fiction; unpausing does
not remove the PAUSED *panel* (its own CanvasLayer), and `_process` cannot unpause
at all unless the harness is `PROCESS_MODE_ALWAYS`, which cost a render pass and a
"0 of 13 snails moved" false failure; and a harness whose script fails to parse
hangs a windowed Godot for ever, because the root comes back script-less and
nothing ever calls `quit()`.

**Also:** the first snail placement was correct and invisible — d 0.16–0.72 put half
of them inside the kelp stand (measured floor y −12.09). Moved to d 0.44–0.86, under
the kelp and among the coral. `ReefProbe` gained a snails section and its
kelp assertion was split (the coral band must start below the kelp; the barnacle
crust and starfish deliberately run up to the pontoon skirt). Two `TestRunner`
lamp-snail assertions hard-coded "6" and now count what is there.

Screenshots: `/tmp/reef_s20/` (day + night, incl. one frame per live snail).

### s19 — 2026-07-29 (performance)
**"Runs without lag" pass, measurement-first.** Re-profiled before touching
anything: 35.65 ms/frame (28.1 fps), 3392 draw calls at the spawn vantage —
confirming the earlier profile still held. Ended at **30.23 ms (33.1 fps), 3293
draws at the same vantage, with the 560-instance leg reef added in between**.

**Where the frame actually went, and what was done about it:**
- **The wave math** (`gyre.gd`). `wave_height` was `wave_offset().y` — it paid for
  the horizontal Gerstner displacement, and therefore ELEVEN `cos()` calls, that
  nobody reading a surface height ever uses. It is now its own loop, and `k` and
  `omega` are precomputed per band instead of being re-derived (11 divisions and
  11 square roots) on every one of the several hundred calls a frame.
  **1.44x measured** (`tests/WaveBench.tscn`, 40k samples). One behaviour change,
  documented and asserted: the old path rounded through a `Vector3`, whose
  components are single-precision, so the height is now ~1.2e-7 m *more* accurate.
- **The per-fish swell sample** (`underwater_world.gd`). `Gyre.water_time()` was
  called once per fish per frame — 512 engine calls for a number that cannot
  change within a frame. Hoisted. The surface clamp is also skipped outright for
  any pod whose ceiling is provably below `Gyre.trough_floor()`, the analytic
  deepest the sea can reach at any sea state (-6.44 m). **Every fish kept.**
- **AI decimation** (`scripts/world/ai_budget.gd`, new). The wall was per-frame
  GDScript on animals nobody is looking at. Distant and undrawn creatures now
  think every 2nd or 4th frame and are handed the delta they missed. 27 species
  across `bloom_fauna`, `reef_life` and `underwater_world`, plus per-pod
  decimation for the 48 fish shoals. **Nothing inside 18 m is ever decimated**,
  and nothing was deleted or thinned.

**Worth 2.5-5.4 ms at five of six vantages** (A/B/A in one session, each row
against its own noise floor — `tests/VantagePerf.tscn`), i.e. 12-27% of frame.

**Proving the animals did not slow down** is most of the work here, because the
obvious version of this optimisation silently runs everything at 1/N speed
(Godot passes the FRAME delta, not the accumulated one). Three independent
checks: `tests/AiBudgetProbe.tscn` measures d(_t)/d(wall) A/B/A on the live world
and gets **1.000 for all 27 species**; the suite asserts delta conservation
arithmetically; and it asserts that a creature stepped 300x at 1/30 s and one
stepped 75x at 4/30 s finish **0.000000 m apart**.

**The new leg reef costs 1.98 ms (8.5%) at the deep underwater vantage and is at
or below the noise floor at all five others** — it is affordable, it is not the
wall, and it should stay.

Tests: 238 pass, `FAILURES: 0`.

### s19 — 2026-07-29 (reef)
**Coral reef down the caisson legs + starfish on the foundation.** Tripo round 8
judged by render: **rejected `coral_tube` and `coral_fan_b`** (both bedded on a
baked-in rock, so neither can seat flush; fan_b also duplicated fan_a's
silhouette), **`coral_encrust`** (smooth pale stalk reads as a plinth, and it took
decimation worst of the set), and **`coral_whip`** — that one survived judging and
decimation and was cut later, *on the wall*: a 2 cm wand colony renders as red
scratches on concrete at any distance you actually see a caisson from. Shipped 6
corals + 3 starfish.

**Decimation** (`tools/decimate_reef.py`, headless Blender, matches the s17 item
pass): 500k → per-slug budgets spent where they show — 8k for the pieces that ARE
their silhouette (staghorn, sea fan), 5–7k for the massive blobs whose detail is
normal-mapped, 3k for the flat starfish. 3.36M raw → 53k across 10 pieces, UVs
kept, textures 2048 → 1024. It also **normalises orientation** into one contract
(+Y = growth, base at y=0, XZ centred), which is what lets the placement code
point a host's +Y down a probed normal instead of carrying ten special cases.

**Placement** (`scripts/world/leg_reef.gd`, spawned by reef_life): patchy colonies
— a dominant species plus an accent, clustered on a seed, thinning with depth,
favouring the outboard and up-current faces. **560 instances, 27 MultiMesh draws,
3.14M tris**, one MultiMesh per species PER LEG so looking at one leg culls the
other three (~0.62–0.72M per leg, 0.48M foundation).

**Sonar earned its keep twice.** The caisson faces came from `spatial_raycast`
(every face exactly 3.000 m from its centre line, at eight depths) and
`spatial_slice` confirmed the pontoon plan independently; `ReefProbe` then
re-derives both from the live colliders every run (0.000 m deviation over 64
rays). The band top is **measured, not typed**: 44 tagged kelp strands, floor
y −12.09, reef starts 0.6 m under it.

**Three silent failures worth the entry** (all now in `docs/AGENT_TRAPS.md`):
MultiMesh instance data is dropped by the headless renderer and reads back as
IDENTITY, so a headless probe cheerfully certified 292 corals sitting on the world
origin; Blender's glTF importer is Z-up, so a decimation pass "normalising up"
normalised sideways and printed plausible numbers; and the first vegetation walk
measured y −20.98 because the deepest things near a footing are floodlight cones,
god-ray quads and *passing fish* — it would have shipped a 1 m reef.

**Blocked at hand-off:** `scripts/world/underwater_world.gd` does not parse in the
working tree — a concurrent session added `var _eye` alongside the existing
`func _eye()`. Every visual and probe number above was taken in a disposable
copy-on-write clone with that variable renamed locally (behaviour-neutral); the
working tree was not touched. `TestRunner` there reports **FAILURES: 1**,
`wave_height is exactly wave_offset().y`, which is **not from this work** — it
reproduces with LegReef disabled and lives in the same session's `gyre.gd`.
Screenshots: `/tmp/reef_shots/` (15 day + 4 night).

### s18 — 2026-07-29
Hammerhead (owner-picked `hh_a`) installed and found to be swimming **broadside**
— generated meshes do not share a forward axis; fixed with a measured
`FACING_OVERRIDES` entry and 5→7 m scale. Killed a per-frame `Vector3 cannot be
normalized` storm in `fauna_move.gd` (cause was **NaN**, which defeats every
existing guard; one harness run wrote 4.4 GB of stderr). Crabs: fixed the
origin-drift bug, moved the day band out of the inside of the foundation
casting, and gave the night emergence a real ramp (was flat 3/8 all night).
Shadows: most previous shadow work measured as **inert on gl_compatibility**;
the real cause was `SHADOW_PARALLEL_2_SPLITS` halving the atlas — orthogonal at
8192 gives 3.4× texel density for +0.5 ms. Fishing: all 35 species now reachable
across weather/fog/light/bait/depth conditions (the oarfish was effectively
uncatchable); the Fisherman's Handbook is now a carryable, placeable readable
whose text documents those conditions. Lamp snail pattern now slowly morphs.
Fish schools profiled and deliberately **not** cut — they cost 0 on deck.

### s17 — 2026-07-28/29
Deck birds: replaced the stork-like `corvid_gull` with a real herring gull;
takeoff squawk replaced by a synthesized wingbeat. 58 inventory items given real
graphics (24 mapped free from the existing CC0 library, 34 generated + decimated
to 8k). Rod icon fixed — the 57-mesh rod was building fine but the icon camera
sized off the world diagonal, so a 1.90 m rod drew as ~1 px. Fish inventory
previews now scale to real length. Fauna seating: three gull perches at exactly
+750 mm, seal intersecting five colliders and a patrol clipping the pontoon.
World geometry: ceiling beacon, DANGER sign, splice label, crate/barrel overlap.
Ladders: three shipped with an inverted `face_dir()` making them impassable.

### s16 and earlier
See git log. Highlights: deep-sea rod graphic (57 meshes), snail marble shell
shader, Pyramid Snail species, Tripo swapped in as the default generator.

---

## Open / next

**Oarfish — text-to-3D has failed. Stop spending credits on it without a new
approach.** Nine rounds, 33+ generations across s16–s20, all rejected: early
rounds returned an ordinary round-bodied fish (the model has a strong prior
toward normal fish anatomy), later rounds got the ribbon body and the crest of
rays right but distorted the head every time — chunky/froggy, catfish barbels
and horns, one attempt produced what reads as two heads. The owner supplied a
reference photo mid-session; it clarified what to ask for (serpentine S-curve
pose, continuous low dorsal fringe rising into a separate crest, dark vertical
bar markings) but round 9, prompted directly from it, still failed on the face.
**Two paths forward, not attempted:** (1) image-to-3D from the reference photo
— blocked because the photo exists only in the chat session and nothing here
can read a chat image as a file; ask the owner to drop it in `~/SALTLINE/refs/`
and retry immediately. (2) Build it procedurally — this project already builds
far more complex procedural geometry than an oarfish needs (the fishing rod is
57 meshes) and it gives exact control over the three things generation keeps
failing: length, thinness, and the tail. Recommend (2) if (1) doesn't land.

- **Pyramid snail mesh** — `_cand5/pyr_{a,b,c}` generated but never judged; the
  species currently runs on procedural geometry.

**Known open bugs** — see `KNOWN_ISSUES.md`.

**Watch items:**
- The NaN guards in `fauna_move.gd` make a bad state *harmless and self-healing*
  rather than loud. If a creature is ever seen freezing or teleporting, that is
  the thread to pull — something upstream may still be producing NaN.
- Candidate meshes are accumulating under `assets/models/fauna/_cand*/`. Prune
  the rejected ones once the winners are installed.

## s25 — the save system actually saves

**Reported as "the save system does not work at all".** It was not absent — `save_manager.gd`
is a complete, well-built v2 slot system — it was *self-destructing*, in two ways that
together read to a player as "nothing persists".

1. **Every load gutted the save it had just read.** `load_game()` restores the time of day
   with `GameClock.force_phase()`; `force_phase` emits `dawn`/`dusk`; those are connected to
   `save_game()`. Since a save was only ever *written* at dawn or dusk, every file on disk
   carried one of those phases, so every load re-entered `save_game()` partway through —
   before structures, containers, dropped items and the player position had been restored —
   and wrote the half-empty world over the file. Session looked right, next boot did not.
   Fixed with a `_loading` re-entrancy guard (`save_manager.gd`), plus a deferred clear so a
   restore step that errors cannot leave saving switched off for the session.
2. **There was no way to ask the game to save.** Dawn/dusk autosave was the only writer, and
   the phase plan is a ~60-minute cycle — a player who built a camp mid-morning and quit had
   written nothing and had no way to know. Added **SAVE GAME** to the pause menu with an
   honest result line (`pause_menu.gd`); `save_game()` now returns `bool` so a failed write
   is reported as a failure rather than a cheerful lie.

Also hardened: saves write to `<slot>.json.part` and `rename` into place, so the previous good
save is only ever replaced by a complete new one; a corrupt/truncated slot warns and starts
fresh instead of half-applying.

Autosave is deliberately KEPT as a backstop, and the pause line says so ("Writes slot N · also
autosaves at dawn and dusk") — one `_ready()` line to remove if manual-only is wanted.

**Verified** (not asserted):
- `tests/SaveProbe.tscn` — 23 checks. Saves at DUSK (the real autosave path the suite's
  `force_phase(DAY)` was dodging), reloads, then **re-reads the file off disk**: camp,
  container contents and phase all still there. Also covers manual save mid-DAY, stack
  counts, player transform, and a deliberately corrupted slot.
- `tests/BootSaveProbe.tscn` — 19 checks, the whole player-facing loop: boot Main, build,
  stash into a world container, fill the pack, move, save; wipe the autoloads as a fresh
  launch would; come back through `begin_continue()` into a second real Main boot. Items,
  container contents, placed structure, day count and last location all return, and the file
  is still intact afterwards.
- `tests/PauseShot.tscn` — windowed capture of the new control, idle and post-save.
- Full suite: **241 pass, 0 failures.**

**Note for whoever reads the suite next:** `test_runner.gd`'s save block still calls
`force_phase(DAY)` before saving, which is exactly what hid this bug for a whole batch. The two
new probes cover the real phases; consider dropping that line from the suite too.

---

## s26 — 2026-08-01 (the dive hitch, measured; three fixes built and rejected)

**Session goal was to plan the next phase and then fix the owner's top-named bug: "any way to
make less glitchy transition moving from surface to underwater? It freezes for a good second."**
The bug is real, it is now quantified, and it is **not fixed** — what shipped is the instrument
and the evidence, plus three eliminated hypotheses so the next attempt starts from the right
place.

**Built `tests/DiveProbe.tscn`** (windowed, foreground). Its discriminating experiment is diving
TWICE: a cost only the first dive pays is a one-off, a cost every dive pays is the per-transition
visibility walk. First result:

    dive 1  peak 285.1 ms, ~365 ms of frames over the line
    dive 2  peak  46.5 ms, zero frames over the line — identical move

6.1x. So `_cull_topside`'s ~4,100-node `visible` flip — the obvious suspect, and the thing a
"stagger the reveal" fix would have targeted — is **innocent**.

**Three fixes built, measured, reverted.** Each was plausible and each was wrong:
1. Draw all 1,120 of the subtree's materials at load through a SubViewport sharing the real
   World3D. Instrumented to prove it actually rasterised: 37.76 M prims/frame. Dive: 239.5 ms.
2. Hang the underwater Environment on the real camera topside. That frame alone cost **275.5 ms**
   — and the dive still cost 239.6 ms. Two separate ~250 ms bills, not one.
3. Gate a full transition rehearsal on `rig_batcher.finished`, so the warmed configuration is the
   welded one rather than the pre-weld one. Dive: 264.2 ms.

**What it actually is: the warm state DECAYS with time hidden.** Rehearse, then sit topside:

    gap ~3 s -> 67 ms     gap 30 s -> 127 ms     gap ~36 s -> 264 ms     never -> 285 ms

Monotonic. Something is released for not having been drawn recently — consistent with GPU
residency on this machine's GL-over-Metal path. **This is why no one-time prewarm can work**, and
it is the constraint the next attempt has to beat.

**Next candidate (untried):** keep the subtree warm *near the water* rather than at load — begin
rendering it into a small SubViewport once the player's eye drops toward the waterline, or ping it
periodically. The ceiling to respect: drawing the subtree costs ~35–55 ms/frame, so a naive
periodic ping trades one 285 ms cliff for a lot of 40 ms ones. Predictive-on-approach is the
better shape.

**Reverted:** `scripts/main.gd` and `scripts/world/rig_batcher.gd` are back at HEAD. The rehearsal
bought a 2–4 s black load screen and no measured improvement, so it did not ship.

**Also measured, incidentally:** topside 28.6–29.6 ms / 6.3–6.8 M prims / ~2595 draws; underwater
38.1–39.4 ms / 14.1–14.3 M prims / ~2790 draws. Subtree: 4,144 nodes, 1,650 VisualInstance3D,
1,120 unique materials, 8 shaders (`tests/MatCensus.tscn`, headless — material counting needs no
drawing).

**Suite: 241 pass, 0 failures** (unchanged — no game code shipped this session).

**Assessment for the roadmap** (owner asked for 5 prioritised improvements; multi-rig deferred by
owner decision, focus stays on rig 1's depth):
1. the dive door — above; blocks everything underwater
2. spearfishing + underwater foraging — the spear is melee-only today, `grep` confirms zero
   underwater use, and the reef has no interactive verbs at all
3. tides — `Gyre` already solves height analytically, so a tide is a slow offset; the risk is the
   audit of every hand-typed waterline constant
4. crab speciation — `crab.gd` is 2,062 lines for ONE species; refactor to a species table, then
   Tripo (820 credits, healthy; Meshy is at 4 and is not a usable provider)
5. the calm-night Bloom — bioluminescence keyed off low sea state + NIGHT

---

## s27 — 2026-08-01 (spearfishing, and why the shoals were black)

**The plan's item 2, and the biggest content-per-line win available:** the game already had a
fully built ocean — 48 pods, 512 fish on real depth bands out of `fish.json` — that the player
had no verb for. The spear had existed since the crafting pass as a crab-repelling club and
`grep` confirmed zero underwater use. This connects them.

**Spearfishing.** `underwater_world` gained three queries over the live shoal members:
`spear_target()` (nearest fish in a ~31 deg aim cone, body length folded into the hit radius, and
it refuses fish the cull is not drawing), `take_speared()` (RECYCLES the node to the pod centre
rather than freeing it — the per-member arrays `ph`/`spd`/`head`/`climb` are indexed in lockstep
with `fish`, so removing an entry would silently put one fish on another's swim personality), and
`scatter_fish()` (a thrust startles the water whether it hits or not; a miss spooks harder,
because nothing died to calm it).

No new binding: `_melee_attack` routes to a thrust when the weapon is flagged `spearfishing` and
the EYE is under the swell. On deck it is the swing it always was. Landing reuses
`fishing_rod._land`'s path exactly — journal, pack-or-spill, size roll, record book, fillet count
— or a fish would mean different things depending on how it was caught.

**Discoverability**, since the verb has no binding of its own to advertise: look at a fish with a
spear underwater and the chip says `[LMB]   Spear the Ember Snapper`. `interaction_ray` yields the
chip the same way it already yields to carrying, building and a live cast — it has to be the ray
that stands down, because the shoals have no colliders and nothing the ray can hit would produce
that line. Polled at 10 Hz, not per frame: `bloom_fauna`'s GDScript is already the wall.

**THE CATCHABLE SHOALS WERE RENDERING AS BLACK CUT-OUTS**, found by photographing the feature
rather than trusting the probe. The obvious suspect was s24's metallic bug; it was measured and
it is NOT that — every catchable species imports honest scalars (metallic 0.000, roughness 0.800,
no ORM), and it is the trop_* fish that carry the metallic case, already handled. The cause was
light: ambient grades to ~(0.088, 0.203, 0.223) at 0.5 energy by 8 m and the sun floors at 0.06,
so an unlit (0.80, 0.40, 0.25) flank lands near (0.035, 0.040, 0.028). The reef and the trop fish
read at that depth because they carry emission; the shoals carried none, because `glow_energy`
defaults to 0 and the herring was the ONLY species that ever called `ANIM.drive`. Fixed with a
faint rim + flank lift in the species' own tint, **swept off one world build** (0.20/0.10 still
black, 0.45/0.22 flank but no edge, 0.75/0.38 draws the dorsal line and reads as a fish). Both
stay under the 0.8 glow threshold, so this is legibility, not bloom.

**Verified:** `tests/SpearProbe.tscn` 23 checks / 0 failures — including that the prompt is EMPTY
on deck and that the same spear above water still swings rather than fishing. Suite 241 pass / 0
failures. `tests/SpearShot.tscn` photographs the moment at three pods and sweeps the rim.

Two things the probe caught about itself, both now in `AGENT_TRAPS.md`: a script error inside an
awaited coroutine abandons it while the report still reads `FAILURES: 0` (it has a completion
sentinel now), and `underwater_world` only swims its schools while visible, so a harness that
starts topside queries fish that are all still stacked at the world origin.

**Still open:** the dive hitch from s26 (285 ms, decays with time hidden — no one-time prewarm can
fix it; the untried candidate is warming on approach to the water). Per-member size correlation
for a speared fish needs a PERCENTILE call on FishTable rather than a roll, so the fish.json
weight range stays the contract the stove and drying line read.

**Next:** tides (item 3) — `Gyre` already solves height analytically so the tide is a slow offset;
the session is the audit of every hand-typed waterline constant.

---

## s29 — 2026-08-01 (tides; plus two KNOWN_ISSUES bugs cleared)

**The plan's item 3.** Mean sea level is no longer the world origin plane. Preceded by a
ten-subsystem waterline audit (136 findings, 20 blockers) because a moving sea touches every
constant anyone ever hand-typed near the water — and it found things reading the code would not.

**The shape of it: one number, two injections, one clock.**
- CPU — the 11-band Gerstner sum is factored into `Gyre._swell()`, and `wave_height()` is
  `_swell + tide()`. Rigid: outside the loop, never scaled by amp_scale/gust/envelope. A tide is
  not a wave; it does not get bigger in a storm.
- GPU — `ocean_surface.gd`'s `Vector3(cp.x, 0.0, cp.z)` becomes `Vector3(cp.x, Gyre.tide(), cp.z)`.
  **`ocean_water.gdshader` is not touched at all.** Folding the tide into the shader's `disp`
  would put it through `disp *= damp` (the 180–620 m far-field flattening), erasing it at the
  horizon and leaving a ledge across the sea; and it would shift `v_height = disp.y`, which
  drives the foam ramp, whitening the water at high tide and blackening it at low.
- Clock — `tide_at(game_hours) = TIDE_AMP * sin(TAU*h/12.42)`, semi-diurnal. Off `GameClock`,
  never shader `TIME` (wall clock, unpausable), and off the HOUR rather than integrated from
  delta so a sleep — which skips a night without spending real seconds — moves the water the
  right amount instead of none.

**`Gyre.swim_line()` — the `* 0.85` idiom was about to become a bug.** Fourteen sites across
seven files tested against 85% of the wave height. That scale predates the tide, and scaling a
tide-bearing height puts the swim line, the head-underwater test (which now also gates
spearfishing), the buoyant float, the breath drain and the fall-into-water test 0.2 m off the
drawn water at both extremes. `swim_line = tide + 0.85 * swell` — the tide at full weight, only
the swell scaled — and all fourteen sites now call it.

**AMPLITUDE IS SET BY THE SPAWN DECK, NOT BY TASTE.** Asked for ±1.5 m. Two independent
replications of this file's own Gerstner sum (one auditor's, one 300k-sample) put the calm p99
crest at ~1.28 m, and `WET_Y` is 2.0, so the budget is 2.0 − 1.28 = **0.72 m**. Shipped 0.70.
At ±1.5 the wet deck is sea for hours at a time, which is what detonates six player-controller
blockers, three sea ladders and the respawn; at ±0.70 all of them vanish untouched.

**The payoff is at the LOW end, and it is real:** the pontoon walkway tops out at y 0.95, so
measured, **33% of it is under water at high tide and 0% at low**. That band is the intertidal
zone — and the pontoon's side already carries a painted `MatLib.tide_band()` algae stain that is
now exposed at low water and submerged at high, which is what it was always drawing.

**Four things that were deaf to the sea, now fixed:**
- `underwater_world`'s topside cull was an absolute-Y test — at high water a swimmer on a crest
  had the whole underwater subtree switched off around them. Now `TOPSIDE_MARGIN + Gyre.tide()`.
  This does NOT undo s21's fix (which was to stop referencing the *swell*): the tide moves 1.4 m
  over ~25 real minutes and cannot produce that flip-flop.
- `JellyDrifter` was the file's only declared surface animal and the only fauna that never asked
  Gyre anything — at low water all seven glowing bells hovered a metre up in open air beside the
  wet-deck rail. They ride `wave_height` now.
- `TideWorm` — the one species the game NAMES after the tide was the one animal deaf to it,
  emerging on a DAWN/DUSK clock. It now comes out on the ebb and through low water, which makes
  it the game's free tide indicator: the worms are out, so the walkway is exposed.
- `_check_water` latched `swimming` on depth alone, so a crest washing the plating would take
  the walking controls away from someone standing on solid steel. Now requires no floor
  underfoot, or water past `WADE_DEPTH` (1.15 m). You can wade.

**THE HIGHEST-VALUE CATCH, and it came from the audit rather than from writing the code:**
`Gyre` is NOT an autoload. Driving `_tide` from `Gyre._process` would have made a process-wide
static depend on a scene NODE existing, so every harness that does not build the whole world
would run at a permanent tide of 0.0 and go on certifying the old fixed sea while passing
cleanly. `tide()` derives itself from `GameClock` (which IS an autoload) with a self-invalidating
per-frame cache. `set_tide()` is now an explicit test pin released by `release_tide()`.

**`WaveBench` failed loudly and was right.** It carries a frozen pre-optimisation reference of
the wave sum; the reference had no tide, so it scored the whole offset as a 0.593 m error — which
was exactly the live tide. Reference updated to read `Gyre.tide()` rather than restate the curve.
Now `|wave_offset − reference| = 0.0` exactly.

**Verified:** `tests/TideProbe.tscn` — 22 checks. It pins the rigid-scalar property, that
`wave_offset().y` still equals `wave_height()` at every tide (they live 40 lines apart and one
returns a Vector3 — "added to only one" is the easy silent mistake), that the drawn sea node
tracks `tide()`, that `trough_floor()` is still a proof at full storm AND dead low water, the
intertidal fractions, and the cull fix. `tests/TideShot.tscn` photographs low/mean/high.
TestRunner 241 pass, SpearProbe, SunkProbe, WaveBench all clean.

### Also this session — two KNOWN_ISSUES entries retired

- **The store-room crate 3 m under the wet deck** was `SurfaceSnap` itself. It does not "drop
  through" as the entry said (a `LootContainer` is a StaticBody and never falls): its ray passed
  through a wet deck whose CSG collider had not baked yet, hit the structure 3 m below, and
  seated it there, succeeding every time. Bounding the drop cannot separate that from the real
  corrections — measured all 36 snaps: 2.954 (the bug), 1.800 and 0.900 (both props authored
  above a deck being correctly seated onto it), everything else ≤ 0.32. The discriminator is
  time, not distance: wait 8 physics ticks for the colliders. `tests/SunkProbe.tscn` ships with
  it; `PlacementProbe` measures the opposite failure and had reported FLOATING: 0 throughout.
- **Un-crouching** had a gate after all — but it probed only where the new HEAD lands
  (1.55–2.15), and the standing capsule spans 0.00–1.80, so a beam at chest height passed the
  check and the capsule grew into it. It now sweeps the whole band as a slim capsule. It
  survived because `playtest.gd` only ever stood up in open air, where a present gate and an
  absent one look identical.

**Deferred with reasons** (from the audit's own list): storm surge, the fish-depth datum
question, raising `WET_Y`, the `_tide_bands()` stain rework (welded into `MergedDressing`, so it
cannot be repositioned at runtime), and re-deriving the perf vantages — those should be PINNED to
a fixed tide first so historical rows stay comparable, not re-based.

**Next:** the intertidal band has the geometry and the clock but no FOOD yet — nothing
harvestable lives in the band the tide sweeps (the mussel beds sit 11 m below the lowest water).
That is the mussel course and the tide pools, and it is now a content task rather than a systems
one.

---

## s31 — 2026-08-02 (owner bug sweep, round two; eleven new species wired in)

Nine-cluster parallel diagnosis with every confirmed cause adversarially re-checked before
anything was edited — 33 agents, 9 of the claims REFUTED at the verify stage, which is the
point of having one. Two of the refutations were the verifier finding a fix already committed.

**THE SCROLLING PILLARS.** `materials/caustics.gdshader:64` branched on `NORMAL` inside
`fragment()`, and Godot's fragment-stage `NORMAL` is in VIEW space — so the projection plane
was chosen by where the CAMERA was, not by which way the face pointed. Pitch down past ~45°
at a caisson (from the walkway, the ladder, or in the water) and the `v_world.xz` branch wins
on a VERTICAL face, where one world axis is constant across the whole quad: the 2-D caustic
net collapses to iso-lines of a single axis, i.e. vertical stripes, and `caustic()` translates
its noise by `t * 0.12` so they crawl sideways at 0.06–0.09 m/s for ever. The shader's own
comment documents this exact artifact as something it was written to fix; the fix never worked
because the selector read the wrong space. `seabed_rock.gdshader:16/48/52` had the correct
idiom all along. Three lines: a `v_wn` world-normal varying, and branch on that.

**THE GLOWING FLAT SQUARES** were `jelly_glow.gd` — 26 untextured emissive teal QuadMeshes up
to 2.2 m square, held HORIZONTAL at a fixed 0.5 m draft. A rigid plate's half-diagonal is up
to 1.56 m, so every wave face steeper than 24° pushed a corner through the surface, and being
untextured they surfaced as hard axis-aligned squares over the glow threshold. Three faults
compounded: draft under half-diagonal, no radial falloff (the `MatLib.soft_mote` trap, never
applied here), and no Gerstner HORIZONTAL offset — `gyre.gd` says outright that anything
floating needs it, and the foam streaks and debris both apply it. Now sunk 1.8 m, radial
gradient on albedo AND emission, cull disabled, and riding the full `wave_offset`. The
gradient is built inline rather than via `MatLib.soft_mote()` because that helper returns a
CACHED material shared with the snow and bubbles, and this one's emission is pulsed per frame.

**THE TWO KING CRABS SAT TOGETHER BECAUSE THEY WERE AUTHORED TOGETHER.** Both dens were on the
SE caisson foot, differing only in z by 3.00 m, and `KingCrab`'s DAY state is an explicit
hold-position — it walks to its one point and stops. It has no territory system; the s21
"give each crab its own territory" pass was the GIANT crabs. One king per foot now, SE and SW,
54 m apart, each with its own transit lane so their night routes do not converge either.

**THE HANDBOOK** was the one Readable in the world both auto-correctors decline: no
`SurfaceSnap` (so s28's CSG warm-up was irrelevant — it never used it) and not in `settle_me`.
Hand-typed `y + 0.62` over nothing. Now `y + 0.21`, which is what `SupportIndex.settle()`
independently measured for that XZ.

**LIVE SNAILS AS BAIT — the premise was false in code and true in play.** The engine path works
end to end; what is broken is the only route to `snail_live`, a crouch-gated harvest verb the
game never shows, names or teaches. The guide promised it in six places and, worse, the RIBBON
EEL and COELACANTH listed it as their ONLY bait — both were effectively uncatchable. Guide
text repointed to the crab leg, both fish repointed at the same weight, and dropped from the
swordfish's five preferences.

**ELEVEN SPECIES WIRED IN.** The five principal tunas, four groupers, mahi-mahi and swallowtail
angelfish: `fish.json` entries with real depth bands, weather tiers, bait opinions, size/fillet
ranges and schools, plus raw and cooked `items.json` entries and journal entries. CatchProbe
(120,000 rolls per tool) confirms every one is reachable through the real roll path.

Two things worth recording about the meshes. They were generated by TRIPO, 11/11 first try —
**Meshy has 4 credits and cannot do this work** whatever a request says. And they are NOT
decimated, which is CORRECT and not an oversight: the shipped catchable fish are 4–6 MB too.
`tools/decimate_fish.py` was for the tropical reef fish, which are instanced 187 times; the
catchable pods share one cached mesh resource per species and are distance-budgeted.

Stocking was trimmed on the way in (335 → 313 members per pod across all species) so eleven new
species is ~+11% ocean population rather than +30%. KNOWN_ISSUES names the fish sim as the
frame wall at 26–35 fps, so this needs a real measurement before the counts go up.

**Also:** the rig scanner was re-run (8,201 objects, 2,591 with a ≥0.25 m gap beneath, 715
props). Barrel Grouper renamed to Goliath Grouper (display name only — the item id is what
saves key on). A tide staff now stands in the sea off the pontoon's seaward edge, graduated in
quarter metres; three placements were tried against the real geometry first and the reasoning
is in the code.

**SpearProbe needed correcting, not the spear.** "A thrust aimed away misses" quietly depended
on the water BEHIND the camera being empty; eleven new species put a pod there. The property
is that the cone rejects the fish behind you, and it now asserts that instead.

**Confirmed but NOT fixed** (diagnosed with file:line, ran out of session):
- 3 of the 4 underwater light shafts spawn INSIDE the solid caisson concrete and are
  depth-occluded from everywhere. The owner wants them replaced by a diffused cone at the
  under-deck fixtures.
- There is genuinely NO player-facing toggle for the under-deck lights — independently
  re-verified. They are also children of the culled underwater subtree, so they are invisible
  from the deck by construction.
- Rain on water has no impact structure: the ocean shader's rain branch is a pure isotropic
  stipple with no ring/annulus term. The "fat ugly circles" the owner saw were a DIFFERENT
  thing (the swell spray, now fixed); the real ripple simulation is still absent, and the
  verify pass refuted the proposed fix as inadequate.

**Not started:** the seal hover, coral tripling, deeper seabed, kelp diversity, plant rooting
angles, wet-deck decluttering, northern lights.

---

## s32 — 2026-08-02 (the ship's cat; reef distance-cull; the 11 species judged)

**THE SHIP'S CAT** (`scripts/world/ship_cat.gd`), the first animal on this rig that is company
rather than weather. Found — not spawned at you — sitting on the bunkhouse deck washing a paw
from the first minute of a run, with nothing pointing at it. Say hello once and that is the
whole befriending: no trust meter, no minigame. Then it follows at its own pace and distance,
sits when you stop, lies down and slows its breathing if you stay stopped, and closes right in
when you have a fish in your hands. Kinematic and un-navmeshed per the crab's brief: it probes
the deck under each footfall and simply declines a step that would walk it off an edge or up a
stair, because a cat that cannot follow you down a ladder is a cat and one that clips through a
bunk frame is a bug. It takes the four-line `AiBudget` prologue like every other per-frame
creature. Mesh by Tripo, first roll.

Two bugs found by writing the probe first, both silent:
- `Interactable.interacted` carries ONE argument (the verb). A two-argument handler does not
  error — it simply never connects, so the cat could not be befriended at all.
- `available_verbs()` has to live on the INTERACTABLE, not on the creature node: the ray reads
  the collider it hit, so a same-named method on the parent is never consulted and the prompt
  read the base class's default "USE".
`tests/CatProbe.tscn` — 15 checks, including that it followed 10.3 m, closed to 2.3 m, stayed
on the deck while doing it, and settles rather than circling when the player rests.

**THE REEF IS NOW DISTANCE-CULLED, and never was.** `render_budget` gives every dressing mesh a
visibility range but it walks `MeshInstance3D`, and `MultiMeshInstance3D` does not derive from
it — so all 62 of the reef's batches fell straight through that pass and have been drawn at
every range since they were built. This is the thing KNOWN_ISSUES names as the heaviest in the
dive band (~1 M tris per leg) on a game measured at 26-35 fps, and it was two lines: 55 m draw
with an 18 m fade, set by what a 0.35-1.95 m coral head resolves to through a fog grade that
runs 0.028-0.2 per metre.

**ON "LINK THE CORAL INTO ONE OBJECT PER PILLAR TO REDUCE SIZE" — measured, and it would do the
opposite.** The coral is already `MultiMesh`: 21 shared mesh resources plus 1,129 transforms,
which is the most compact form it can take. Baking it per leg would turn that into 4.26 M
triangles of UNIQUE geometry, roughly 47x more data. The actual size driver is elsewhere and
was measured: `assets/` is 1.2 GB, `assets/models/fauna` is 637 MB, and only 228 MB of that is
loose textures — the rest is 2048-square PBR maps embedded inside the GLBs at 4-17 MB each.
Geometry is nearly free by comparison. The lever is texture resolution on the fauna GLBs, not
batching, and it is the single biggest build-size win available.

**Correction recorded:** the s31 note that the new fish "need decimating" was wrong. The shipped
catchable fish are 4-6 MB too; `tools/decimate_fish.py` was for the tropical reef fish, which are
instanced 187 times. The catchable pods share one cached mesh resource per species and are
distance-budgeted, so the new eleven are consistent with the existing twenty-nine.

All eleven new species were photographed off disk with `tests/CandShot.tscn` and sent for
judgement. Proportions check out against the real animals (bigeye reads deeper-bodied at 0.37
than bluefin at 0.25, which is correct). The swallowtail is the weakest — lyre tail and vertical
bars right, face mushy, the usual generator failure on small heads.

TestRunner 241, CatchProbe, SpearProbe, TideProbe, SunkProbe, CatProbe — all 0 failures.

---

## s33 — 2026-08-02 (Phase A: two real fixes, and ten plans that failed review)

**A LIVE REGRESSION, found fact-checking my own last session.** `JellyGlow._base` was declared
and consumed in `_process` but never populated in the spawn loop — `Out of bounds get index '0'`
on EVERY frame, in every scene that builds Main, since s31. It survived because that change was
verified with four targeted probes and `TestRunner` was never re-run afterward. The standing
rule is now written into the code: after any edit, run the FULL suite, not the probe that
targets what you think you touched.

**39 FAUNA TEXTURES WERE SHIPPING UNCOMPRESSED — 872 MB OF VRAM.** Every asset generated in
s31/s32 (the eleven species, the ship's cat, the re-roll candidate) imported at
`compress/mode=0` with `size_limit=0`; all 184 pre-existing fauna textures are `mode=2` /
`size_limit=1024`. A new texture stays Lossless until the EDITOR renders it in 3D and
`detect_3d` fires — these were generated headlessly, so it never did, and nothing warns. They
shipped as PNG and uploaded as uncompressed RGBA8 (22.4 MB per 2048 map). Now 223/223 at
`mode=2`/`1024`; each `.s3tc.ctex` is exactly 699,116 B = 1024^2*0.5*4/3+66; VRAM for those maps
872 MB -> 27 MB. Verified visually unchanged at the shipping ratio via CandShot.

**CORRECTION TO s32'S RECORDED DIAGNOSIS.** s32 says the build-size lever is "2048-square PBR
maps EMBEDDED inside the GLBs". Wrong about the mechanism: `gltf/embedded_image_handling=1`
EXTRACTS every embedded map to a sibling at import and the `.scn` binds to those, so source GLBs
contribute ZERO bytes to the shipped pack. The lever is `process/size_limit` and `compress/mode`
in the `.import` sidecars — which is also far safer, touching no binary art and reversible by
editing text. (My own 155.4 MB figure for the fauna s3tc set is ~5% above an independent count
of 148.2 MB across 223 files; the difference is which files each side counted, and the
direction is not in doubt.)

**THE SEAL'S 1-2 m HOVER WAS A LOW-PASS FILTER ON A WAVE.** I reported earlier in the session
that I could not reproduce it — and the reason was that BOTH existing probes miss the branch
that carries it: `SealFloatProbe` forces `_hauled = false` and `FaunaBugsProbe` teleports the
animal onto the shelf, so the haul-out APPROACH had never been measured. Neither obvious
hypothesis was the cause (the tide did not break the s24 fix — the seal holds no sea-level
literal; the seat is not hand-typed — `_snap_haul` still reports GAP +0.0 mm). The approach
branch LERPED y toward the sea with `k = delta * 1.5`, a first-order filter with tau 0.667 s,
while the eleven Gerstner bands run at omega 0.83-6.02 rad/s: the animal could not track the sea
it was steering by. Measured, same probe both sides: **0.464 m mean / 0.935 m worst -> 0.083 /
0.093 m** (the residual is the probe's own sampling floor). The climb-out is now driven by
DISTANCE rather than time, which also fixes a predicted second defect — sharing `k` between the
y and xz lerps let the horizontal approach outrun the vertical one and the seal transited ~3 m
of concrete before surfacing. `tests/SealApproachProbe.tscn` ships with it.

### The design pass — ten plans, ten rejected at review

A ten-item design workflow produced file:line implementation plans for the rest of Phase A, each
then reviewed adversarially by a second agent. **All ten came back `sound: false`.** That is the
result, and it is worth more than ten half-built features:

- **dive-hitch** — "ping the subtree" cannot work as literally written: `_cull_topside` leaves it
  `visible = false` and `instance_set_visible` is GLOBAL, so a hidden instance is undrawable in
  every viewport including one sharing the real World3D. (This also means s26's experiment 1 never
  drew those instances at all.) The proposed proxy rack then keys by mesh RID, which leaves most
  of the 1,120 materials unwarmed, and its census assertion is unsatisfiable by construction.
- **light-cone** — the density constant's stated derivation from the glow threshold is ~20% wrong,
  and an accounting comment edit would have hidden a real gate regression.
- **tide-payoff** — the one constant everything rests on is nondeterministic (seeded RNG but
  unseeded phase origin), and the probe's own tolerances contradict each other.
- **reef-seabed** — the central regression assertion cannot pass, and kelp rooted at y -5 punches
  through the pontoon and breaches the waterline.
- **rain-ripple** — BLOCKER: `SunController.set_storm()` does not push `rain_wet` to the GPU at
  all, so the whole verification plan is dead on arrival.
- **seal-hover** — flagged a positive-feedback loop between the animal's POSE and its POSITION in
  a step I had NOT implemented, and correctly noted the two steps I HAD implemented were already
  in the tree.
- **perf-vantages / declutter / aurora / known-issues** — each with at least one fatal or
  hand-typed-Y defect; declutter would have dropped a relocated chain heap on top of a DeckGull.

None of them should be implemented as written. They are durable in the workflow journal and want
a revision pass, not execution.

**Verified this session:** TestRunner 241 pass / 0 failures and 0 script errors on a full boot
(the "245" quoted by one reviewer is a stale DEVLOG line, not the current suite); CatProbe,
SpearProbe, TideProbe, SunkProbe, SealApproachProbe all 0.

---

## s34 — 2026-08-02 (the owner's focus session: fish, water, seal, walkway, reef, cat)

Seven items from `docs/SESSION_BRIEF_s34.md`, each committed on its own. The through-line
of the session is that **five separate things were green because nothing was measuring
them** — a probe that measured itself, a harness that had switched off the feature under
test, an assertion that could not fail, a per-node search that could not see welded
geometry, and a whole-frame statistic that could not see the subject.

**FOUR SPECIES WERE SWIMMING WRONG, and the owner reported one.** "At least one of the new
grouper models is swimming backwards." Every one of the eleven s31 species was measured two
independent ways — `tools/measure_facing.py` headless off the raw GLB, and CandShot views by
eye — which agree on all eleven: `fish_skipjack_tuna`, `fish_peacock_grouper` and
`fish_bluelined_grouper` are authored head-at-local-−Z, so the default's 180° yaw was
swimming them tail-first. The other eight were already right. The new probe then found a
FIFTH nobody had ever looked at: **`fish_ribbon_eel` measured +0.011 against its own travel
— not backwards, PERPENDICULAR.** Its body is authored along local X and it has been
swimming BROADSIDE since it was wired in, which is the ultra_hammerhead bug still shipping.
Live after the fix: +0.968.

**`water` NOW STEERS THE SPAWN, NOT JUST THE CATCH ROLL.** The structural half of "the fish
generation got messed up under the rig": the field had been in fish.json since the table was
written and decided exactly one thing — whether a cast from the rim was in the right place —
while `_spawn_pod` put every species in the same ±24×28 m box round the legs. Seventeen
species the table calls open-water pelagics, including all five s31 tunas, were swimming in
the water you look down into from the wet deck. Three classes now: `near` pods HOLD A
CAISSON, `any` is exactly the historical pair (so the sixteen species carrying it do not
move at all), `open` is pushed past the moorings. Measured on one harness, before and after:

    the eleven's share of the ocean    21.8%  ->  11.8%
    the eleven's bodies under the rig    269  ->    141      -48%
    `open` species mean distance out  32.3 m  ->  42.1 m
    worst `near` pod from its caisson 32.3 m  ->  15.5 m

**THE GOD-RAY SHAFTS ARE DELETED.** `_build_light_shafts` jittered each spot ±3.5 m from a
leg centre against a caisson whose faces are at ±3.0, so it put a shaft inside solid
concrete (6/7)² = 73.5% of the time per leg — "3 of 4 buried" is exactly what that geometry
predicts. Gone with the shader, the `_rng` that existed only to jitter them, the stale
per-frame accounting and the BETA.md line promising them.

**THE WATER: 0.198/m AT THE CORAL BAND, TRANSMITTING 5% AT 15 m.** Not haze — a wall. Three
faults: the grade resolved over 13 m while the reef is 22 m tall, so its lower two thirds
clamped at MAX_DENS; 0.19 is a 12 m visibility ceiling; and the abyss ramp, whose only job
is hiding the −92 floor, started at 13 m, half way up the coral. Now 0.061/m at the same
spot. **Seven candidates swept on one build with the shipped curve as the control** — and
the sweep is what showed that clarity alone does not answer it: fog-only candidates resolved
the far leg at 25 m and were still dark pictures, because "can you see it" has two terms.
The ambient curve went up too, and a seventh candidate separated the COLOUR ramp from the
density ramp so the lower reef is not sitting in black water you can see 20 m through.

**AND THE SWEEP MEASURED THE WRONG GRADE FOR AN HOUR FIRST.** `underwater_fx._process` finds
the player through the `"player"` GROUP and returns immediately without one — and every shot
harness here drops the lens out of that group so the fauna stop hunting it. So the entire
depth grade had switched itself off, `main.gd`'s much simpler fallback curve was the only
writer left, and the harness logged five different candidate values it had written into a
node that was no longer listening. Every frame came back `density=0.1700`: main.gd's lerp at
its ceiling. Caught by reading `cam.environment` back at shutter time instead of trusting
the value written. main.gd's grade now stands down when underwater_fx is present, rather
than two independent depth grades writing one Environment and resolving by process order.

**THE SEAL WAS SEATED ON A BOUNDING BOX, AND THE PROBE WAS MEASURING ITSELF.** The owner saw
a metre of air; FaunaBugsProbe said GAP +0.0 mm. Both were reporting honestly about
different quantities. `_seat()` runs `y += _haul_floor − low_point(_model)` — it DEFINES
low_point == _haul_floor — and the probe compared `low_point` against a ray with the same
origin, direction, mask and exclusions. The difference could not have been anything but
zero **however far the drawn animal was off the concrete**. And `low_point` is a BOUND: the
axis-aligned box of the ROTATED box, which on this mesh at its −0.12 rad rest pitch sits
**102.0 mm** below the lowest real vertex (computed off the GLB; the live world agrees to
0.5 mm). Note the direction of the history — that function was introduced to fix a 105 mm
BURIAL, so a bound that was too high was swapped for one that is too low and the mesh was
never measured either time. `CreatureAnim.low_vertex()` is exact and cheap (a support query
over a cached convex hull: 29,064 vertices become a couple of hundred dot products), and the
probe now measures it by an INDEPENDENT method — brute-force over every vertex — so the new
check is not the old tautology wearing a new number. They agree to 0.03 mm.

**THE WALKWAY: FOUR PROPS, ONE AT A TIME, MEASURED.** The drum north of the SPHL hatch was
the only one that collides and a player-sized capsule on the walk line had **0.00 m** of
free lane there — the route was blocked outright. Deleted (there is nowhere to move it: a
1.09 m lane needs its centre east of 20.99 and the next drum starts at 21.65). The other
three are things you walked THROUGH: a tyre fender standing inside the gangplank's span, a
bollard chain crossing the lane at shin height, three mooring links half-buried in the
plating across the caisson turn. Clear width on the walk line went 0.00 → 5.94 m at the
drum and 2.99 → 3.84 m at the plank; geometry in the corridor went 6,811 triangles → 0.
**The first relocation candidate for the chain heap measured −0.00 m from a live DeckGull
home** — the identical defect the s33 plan was rejected for, arrived at the identical way,
and caught because the probe asks the world instead of reasoning. The shipped spot is
+4.11 m from the nearest fauna home.

**THE REEF RUNS TO −40 NOW, AND THE BRIEF'S SEABED PREMISE WAS STALE.** It asked for "−23 →
−30"; `seabed.gd` has read −92 since an earlier session deepened it 4×. What there was
instead was 70 m of bare concrete below the reef. Band −12.68 → −40 (2.29× taller),
instances 1129 → 2747, triangles 4.26 M → 12.55 M, and the counts scale with the band
(derived, so moving BAND_BOTTOM moves the stocking) tapered 0.78 because a real reef thins
with depth. **363 wall plants** rooted by raycast and angled out 20–56°, with both the root
AND the grown tip clamped under the pontoon. Kelp went to three forms at three depths — and
the existing stand turned out to be **growing up through the pontoon**: tips reached −0.93
against a slab underside of −3.05, and above `trough_floor` −7.14 where a low tide can
expose it to air. Every tip is clamped now.

**THE CAT HAS SEVEN STATES AND A MESH FOR EACH.** It was four states and one mesh, so
"sitting" was a standing cat and "asleep" was a standing cat rolled 0.55 rad onto its side.
Five poses generated by Tripo from one byte-identical coat paragraph, attached once and
toggled (NOT `ANIM.replace` per transition — it rebuilds every ShaderMaterial on the frame
the cat changes its mind). SLEEP walks to a PROBED spot near the player when they turn in;
feeding is counted in game HOURS because sleeping advances the calendar while no real time
passes. It has a real purr instead of borrowing the deep-hull `groan`.

**Verified:** TestRunner 242 / FAILURES 0, and CatchProbe, SpearProbe, TideProbe, SunkProbe,
SealApproachProbe, FaunaBugsProbe, FishSpreadProbe, DeclutterProbe, CatProbe, ReefProbe all
0. Screenshots `/tmp/s34_final/` — every one read back, including the frame that caught the
last defect of the session: the reef at −28 fading into the abyss ramp, because step 2 put
that ramp at −26 against a reef that then stopped at −22, and step 5 took the coral to −40.
Each was right on its own and they were jointly wrong. Ramp moved to −42.

**New probes:** `FishSpreadProbe` (where the shoals are + an INDEPENDENT facing check),
`DeclutterProbe` (lane width + what you walk through), `FogShot` (the grade sweep),
`S34Shot` (the close-out pass). `FaunaBugsProbe` gained a FAILURES report and a completion
sentinel — it was a pure measurement dump, which is how a hovering seal stayed green.

**Not done / deferred:** the dive hitch is CLOSED as owner-accepted, per the brief. The
deep reef band (−28 to −40) reads dark; the coral is legible against it and it looks like
depth, but it would take an ambient pass to make that band as inviting as the top. The
owner's "about a metre" of seal hover is FIXED at the 102 mm the steady state actually
had — if more remains, the untested branches are the climb-out and the OTHER seal, which
never hauls out and patrols the swell nearby.
