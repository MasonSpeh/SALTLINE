# Known Issues

Open items only. Fixed entries are deleted, not struck through — git remembers.
Verify before adding: several entries here were stale for weeks because the fix
landed and nobody updated the file.

## Bugs

- **`Sealed Crate` (16.5, −8.0) nicks a folding stool** by 0.0157 m³. Small, but
  it is a real intersection. *Found s18.*

- **`Wet Deck Ladder — East` mid-climb clearance is 0.35 m** against a 0.37 m
  capsule. Collision is disabled during a climb and both exits resolve
  correctly, so it is not player-visible today — but it is 2 cm from being the
  same class of bug that made three other ladders impassable. *Found s18.*

- **Build placement has no overlap check** — structures can be placed
  intersecting props or each other. Grid snap keeps it mostly sane; needs a
  shape sweep.

## Watch items

- **Concrete micro-banding at grazing view — the MOVING report is closed; a small static
  residue stays on watch.** The owner's twice-reported "moving vertical lines on the main
  support" had a second cause beyond s42's aniso fix: the caisson rust-weep DECALS were
  placed by a hand-typed half-width (3.14 vs LEG_SIZE's 3.0) and hung 0.155 m proud of the
  concrete — thin 4.5 m vertical quads that slid against the wall with every step the
  viewer took, stood still when they stood still, and so read as "fixed" or "back again"
  depending on whether the owner was walking. Fixed in s44 (derived from LEG_SIZE;
  rig_builder.gd) and proven by instrument: tests/PoleShot.tscn films the pole at 0.8 m
  with hold / clock / strafe discriminator segments — hold (viewer still, sun pinned,
  5.0 s) measures 0.000-0.170% pixels changed across three faces and two sun angles, i.e.
  NOTHING on the pole moves by itself, while the x40-clock control proves the instrument
  sees real motion (78.9%). Caustics excluded by three gates (printed live per segment).
  What remains open is only s43b's fine STATIC banding at brutal grazing (stripe RMS
  ~4.4/255, FFT-pinned to mip 4-5 texel structure); its lever list stands: (a) read the
  aniso level back off the live backend, (b) per-mip-level blur regeneration, (c) the
  new-asset route. The tower now runs materials/concrete_antitile.gdshader (per-cell
  hashed isometries + 1/8-frequency macro layer, 6 taps vs the old 12; A/B switch
  `MatLib.TOWER_ANTITILE`), which also changes its mip statistics — re-measure (a)/(b)
  against the CAISSON's `concrete()`, which still ships the pre-s42 recipe at 2x the
  tower's texel density.

## Open after s38 — the cat

- **`ship_cat._walk_skip()` still does not skip other fauna, and the obvious fix is wrong.**
  The branch reads `fauna_bodies`, a STATIC FUNCTION on bloom_fauna, through `Object.get()`,
  which returns null for a method name — so it has added nothing since s36. Consequence:
  another animal's grab collider counts as a wall to the cat (why the pounce needs an explicit
  prey exclusion). Walking the bloom_fauna subtree and skipping every CollisionObject3D in it
  was tried and REMOVED: that subtree carries the Bloom GROWTH as well as the animals —
  creeper pipes, kelp, anemone clumps — and those are world geometry. With it in, CatHuntProbe's
  burial sweep went 2 mm -> 65 mm. A/B'd both ways. The real fix is a group tag on creature
  colliders so animals can be told from scenery, which is a bloom_fauna change, not a cat one.

- **The stair bump is NOT reproduced, and the geometry change I tried was reverted.** Owner:
  "have to jump over an invisible bump each landing." Two new instruments say the junctions
  are clean — `StairBumpProbe` sweeps the player's own capsule (0.2-0.8 mm of hump, at a
  0.16 mm resolution) and `StairHitchProbe` drives the SHIPPING player with synthesised input
  up and down three flights with zero stalls at any junction; every stall it records begins
  2.3-18.4 m past the lip, which is the far bulkhead. What has NOT been tested is the
  SWITCHBACK — arrive on a mid-landing, turn 180, take the next flight — which is what "each
  landing" most likely means on a nine-flight tower. The probe has a diagnostic pass for it
  whose legs are frame-timed rather than waypoint-driven, so it does not vote; make them
  waypoint-driven first. `floor_block_on_wall` was finally SET (false) in s42 along with a
  13 cm micro-step tier that fires on losing 8% of a frame's travel — retest the
  switchback against those before more geometry work.

- ~~**The cat's ear-scratch grooming style was written and cut.**~~ **CLOSED s54, and it had
  been half-closed for some time without anyone updating this file.** The authored pose the
  entry asks for exists — `cat_rig._build_poses` builds `groom_scratch` with the LEFT HIND
  handed to `_bake` as a `free_leg` (measured choice: that chain is 0.447 m against a
  0.424 m socket-to-ear, and is the only one of the four whose reach envelope contains the
  head at all), and `_GROOM_POSE` maps wash style 3 onto it. What was still missing was any
  way to REACH style 3: it was one face of a seven-sided die rolled inside `_maybe_wash`'s
  three-second window (see the entry below), so in most sessions it never played once. It is
  a first-class weighted action in the instinct layer now, and CatProbe asserts the whole
  chain — action -> style 3 -> State.GROOM -> the rig's own `groom_scratch` target — rather
  than trusting that `set_pose` found the name (it no-ops silently when it does not).

- **The cat's LEAP has still never been filmed, and there is a reason it may be close to
  unreachable.** `tests/CatFilm`'s `jump` reel now probes for a ledge in the 0.66-1.20 m band
  and stages the cat at a PROBED foot with a run-up (it found real 0.76 m and 1.10 m ledges).
  The cat walks up to them and stops: telemetry says y never leaves 18.00 across 270 sampled
  frames.

  The likely cause was found and is worth the next session's time. `_walk_toward`'s deck probe
  starts at `STEP_UP + 0.3` = **0.75 m** above the cat's feet, while `JUMP_UP` is **1.25 m** —
  so any ledge between those heights is INVISIBLE to the very probe the jump gate reads. The
  ray passes under the lip, finds the lower deck, reports a rise of zero, and the animal walks
  into the face. The jump can therefore only ever fire in the narrow 0.62-0.75 m band.

  A fix was attempted and REVERTED, which is the part worth knowing. Casting a second, higher
  ray ahead of the footfall when the cat is already blocked does make ledges visible — and
  CatHuntProbe immediately caught the cat at **y 20.26, 2.26 m above the deck**, having climbed
  a staircase of ledges and stranded itself. That is the exact failure `JUMP_UP`'s comment
  warns about ("an animal that leaps onto things the level design assumed were out of reach").
  Whatever the real fix is, it needs a reachability rule, not just a longer ray. The attempt is
  in the s38 session history if it helps.

- **The hind pair keeps a bone-driven asymmetry, now in LIFT rather than reach.** s40's
  phase-locked pelvis bob (exactly the "hip-height bob coupled to the stance phase" the
  old entry predicted) plus the hip-frame fix took the gallop hind reach ratio from 0.67
  to 0.89 — but the left hind, DEAD STRAIGHT in its bind pose (`L_Thigh -> L_Calf`
  0.336 m against R at 0.086), now shows its limit as extra paw LIFT instead (ratio ~1.4
  at a walk, ~1.36 at a run): at full stretch the solve raises the paw rather than
  shortening the stride, and only that leg needs to. This is the rig's true shape — the
  s38 "symmetric to 1%" numbers were measured while a fore-aft hip-translation bug
  (see s40 DEVLOG) blurred all four legs. Judge visibility on film; removal needs the
  re-rig (docs/CAT_RIG_CEILING.md §3). CatYawDiag PART 4 prints both gaits.

- **The cat's tail is driven through `R_ThighTwist01`, which also owns the rump.** Still
  the reason `cat_rig.TAIL_MAX` is 0.30 rad. s40 upgraded the drive — an underdamped
  spring (lag, ~15% overshoot on stops, turn counter-swing, walk-coupled sway) posed
  absolutely against the live parent chain, which removes the once-per-stride hind-leg
  twitch exactly — but one bone is one bone: a curl, a travelling wave, a real tip flick
  need a caudal chain and a re-skin (docs/CAT_RIG_CEILING.md §1). Re-run
  `tests/CatTailDiag` after any re-rig: the bone name is a measured constant, and a
  rename silently disables the layer.

## Open after s35 — unverified, not unknown

- **The reef SWAY has never been seen moving.** `materials/reef_sway.gdshader` is new and
  the close-out pass photographs STILL frames, so "the plants move" is an argument from the
  shader source, not an observation. Two frames ~2 s apart at a leg face (the frequencies
  are 0.63 and 1.51 Hz) settles it. The specific risk is the per-instance phase: without a
  working INSTANCE_ID term a whole MultiMesh field sways in lockstep like one flag, and a
  single frame cannot tell that apart from correct.

- **The fish rebalance is MODELLED, not measured.** No probe was run against it — six
  agents shared one working tree and windowed runs were barred. FishSpreadProbe's two new
  bars (TOP_HEAVY_MIN 1.40, SHELL_MIN 125) were deliberately set nearer the OLD values than
  the new ones, so a live run landing under the model still passes. Run it: if it fails,
  the probe is right and the model is wrong.

- **The fishing rod fix is a real bug that may not be the owner's bug.** The pack-panel
  route (hud.gd's move_slot re-pointing `selected_hotbar` without an inventory change) is
  measurably broken and matches the report exactly. If the owner was using number keys
  throughout, the cause is something else. Unexercised: a LIVE CAST (`fishing != null`,
  the cast-pose branch of `_apply_hand_pose`) and prone.

- **`submerged_deep` has still not been re-profiled**, now at a modelled 12.67 M triangles
  (s34 left it at 12.55 M and said the same thing). The reef gained structures, a weed band
  and a sway shader this session and paid for them by thinning the barnacle crust, so the
  net is ~1% — but that is arithmetic, not a frame time.

- **The deep reef band (-28 to -40) reads DARK, and it is the grade rather than the reef.**
  s34 took the coral down to -40 and cleared the water above it, but `reef_depth_m` is 24: past
  that depth the colour and ambient curves are both at their end stops, so the new lower band
  is legible coral against near-black water. It photographs as depth and it is not wrong, but
  it is not the invitation the top of the band now is. The fix is an ambient/colour pass over
  the -24..-40 range, swept the same way step 2 swept the top (tests/FogShot.tscn).

- **The seal hover is fixed at the 102 mm the seated state actually had, not at the "about a
  metre" the owner estimated.** The steady seated error is measured, understood and gone, and
  the frames look right. If more remains, the two branches no probe exercises are the CLIMB-OUT
  (`_hauled` true but still over water) and the OTHER seal — `spawn_index` 1 never hauls out
  and patrols the swell right beside the pontoon, which from the deck is easy to mistake for
  the resident.

- **NaN source upstream of `fauna_move.gd` is unidentified.** s18 added
  `is_finite()` guards and self-healing frames, so a bad value is now harmless
  instead of producing a 4.4 GB stderr storm. But the guards make the condition
  *quiet*, not absent. If a creature is ever seen freezing or teleporting, start
  here.

- **Fish cost at the waterline — FIXED s19.** `Gyre.water_time()` is hoisted out
  of the per-fish loop, the surface clamp is skipped for pods provably below
  `Gyre.trough_floor()`, `wave_height` no longer computes the horizontal
  displacement it never used (1.44x, `tests/WaveBench.tscn`), and the 48 pods are
  distance-decimated. Population untouched, as the s18 measurement said it should
  be. Waterline went 22.22 -> 16.67 ms/frame.

- **Where the remaining headroom is (re-measured s21).** The heaviest vantage in
  the game is **`wet_deck_stand` — a standing eye on the Wet Deck, 30.56 ms /
  32.7 fps, 2861 draws, 3.42 M primitives** — and no profile before s21 had ever
  measured it, because `VantagePerf`'s historical `wet_deck` vantage is at eye
  y 4.0 and a standing eye there is y 3.6. `underwater_world.TOPSIDE_MARGIN` is
  4.0, so the old vantage sat on the HIDDEN side of the topside cull and the
  player stands on the VISIBLE side: opposite frames. The harness now has both
  rows. This is where the player fishes and it is the frame to work on next.
  **`bloom_fauna`'s per-frame GDScript is the wall at every vantage** — 4.5-6.1 ms,
  19-32% of frame, WITH `AiBudget` already decimating (the `fauna_sim` row).
  Any NEW per-frame creature should take the four-line `AiBudget` prologue (see
  `scripts/world/ai_budget.gd`).

- **`wet_deck`'s 7-9 ms "noise" was never noise — FIXED s21.** Its repeat-visit
  spread was 9.52 ms and its primitive count swung 2.1-3.6 M because the swell-
  relative topside cull flipped the whole underwater subtree on and off 1-2 times
  a second at that height (see `TOPSIDE_MARGIN`). Referencing still water instead:
  spread 9.52 -> 0.67 ms, flips 2 -> 0, peak prims 3.63 M -> 2.13 M. The vantage is
  measurable now.

- **The 13 caisson snails put 13 solid spheres in the dive band (s20).** Every
  creature's `FaunaTouch` is an `Interactable`, i.e. a `StaticBody3D` on the
  default layer — that is how the interaction ray finds it, and it is the same on
  deck. But these ones (0.6 m pyramid, 0.85 m lamp) stand proud of the caisson
  faces between y −11.6 and −19.4, so a diving player can bump one. Intended
  behaviour, not obviously *good* behaviour underwater; worth a look with a
  controller in hand. Note what it already broke: it silently corrupted
  `ReefProbe`'s raycasts until they excluded fauna (see `docs/AGENT_TRAPS.md`), so
  any new probe aimed at leg geometry needs the same skip list.

- **The reef costs 12.55 M triangles across 2,747 instances (s34), up from 4.26 M / 1,129.**
  The band went from 9.3 m tall to 27.3 m (BAND_BOTTOM -22 -> -40) with the counts scaled to
  match, plus 363 wall plants. What makes it affordable is s32's distance cull (REEF_DRAW_M 55,
  18 m fade) on every one of the 70 MultiMeshes, so a diver pays for the slice around them and
  not the column — but that is an ARGUMENT, not a measurement, and `submerged_deep` has not
  been re-profiled since. Do that before adding more. The cheapest levers in order are still
  `barnacle_cluster_a` (4,000 tris, cannot go lower without shattering — cut its weight
  instead), `coral_fan_a` at 268 x 6,000, and `_crust_face`'s count. The historical note this
  replaces: ~0.95-1.03 M per leg at s20, from 0.62-0.72 M at s19.
  1,170 instances in 62 MultiMesh draws, ~15 of them for whichever leg you are
  looking at. s19 measured the 560-instance version at 1.98 ms (8.5%) at
  `submerged_deep`; this is roughly 1.45x the per-leg triangle count and 2.1x the
  instances, and has **not** been re-profiled. If `submerged_deep` regresses, the
  cheapest levers in order are `barnacle_cluster_a`'s 4,000-tri budget (it cannot
  go lower without shattering — cut its weight instead), `coral_brain` at 100 x
  5,000, and `_crust_face`'s instance count.

## Accepted / by design

- **The first dive of a session stalls ~285 ms — ACCEPTED BY THE OWNER, s34.** Characterised
  in full in s26 and closed here on the owner's explicit call: "takes a second the first
  time, then fine." Do NOT build the warm-on-approach system. The characterisation is kept
  because three intuitive fixes were built, MEASURED and reverted and should not be
  re-attempted: drawing all 1,120 of the subtree's materials at load through a SubViewport
  sharing the real World3D (verified rasterising 37.76 M prims/frame — dive still 239.5 ms);
  hanging the underwater Environment on the real camera topside (that frame alone cost
  275.5 ms, dive still 239.6 ms — two separate bills); and gating a rehearsal on
  `rig_batcher`'s weld (still 264.2 ms). None can work, because the warm state DECAYS with
  time hidden — 3 s → 67 ms, 30 s → 127 ms, 36 s → 264 ms, never → 285 ms, monotonic — so a
  one-time prewarm cannot fix it by construction. `tests/DiveProbe.tscn` measures it;
  `main.gd::_prewarm_underwater_env` is a real but PARTIAL fix (the Environment only). s33
  also refuted the obvious next idea: `_cull_topside` leaves the subtree `visible = false`
  and `instance_set_visible` is GLOBAL, so a hidden instance is undrawable in every viewport
  — which also means s26's experiment 1 never drew those instances at all.

- **Interior props stream in over ~1 s.** Instancing ~200 glTF props at once
  blocked the main thread for ~7 s, so `interior_props.gd` queues placements and
  instances a few per frame. The visible settle is intentional.

- **Single-material boxes texture all faces alike** — the topside deck slab shows
  treadplate on its underside (world-triplanar applies everywhere). Split
  top/side materials in the art polish pass.

- **Interior lighting is faked** with sun-scaled "spill" omni lights, not real
  light shafts through doors and windows. Fine for greybox; replace in the art
  pass.

- **The sun's shadow edge is not PCF-filtered on `gl_compatibility`** in any
  configuration reachable from project settings. Resolution is the only lever,
  which is why s18's fix was resolution. A ±1 px edge jitter remains and cannot
  be smoothed away on this backend.

- **SPHL doesn't bob** — cradle-moored and static. Buoyancy belongs to the boats
  phase.

- **Ladder mantle is a position snap**, not an animated mantle. Reliable;
  budgeted fiddliness per the brief.

- **Crab is kinematic** (no physics/navmesh) per the brief — it can clip greybox
  props on the ascend path. Waypoints are in `rig_builder.gd`.

- **macOS:** the project lives at `~/SALTLINE`, not `~/Desktop/SALTLINE`, because
  a macOS privacy (TCC) denial blocks shell access to Desktop. Any orphaned
  Desktop copy can be deleted manually.

## Open after s36

- **The pelagic schools are the biggest triangle population in the game, and eleven of them
  are undecimated.** Found by accident while sizing the s36 +50% rise. The s20-era school
  species import at 25,026-31,247 tris each; the ELEVEN s31 species import at
  109,714-198,902 — leopard grouper 198,902, bluelined grouper 180,534, swallowtail 169,828
  for a 0.5 m fish. The s31 DEVLOG withdrew "they need decimating" on FILE SIZE (4-6 MB,
  the same as the rest) and never counted geometry. `FishSpreadProbe` now names them OVER
  BUDGET in its stocking report. Re-cutting the eleven to ~31k removes millions of spawned
  triangles. Unverified: whether the import-time LOD (`meshes/generate_lods=true`) reduces
  what is actually submitted on gl_compatibility — s34 costed the same GLBs at raw counts
  and re-cut them, which suggests not. MEASURE BEFORE ADDING MORE FISH.

- **The s36 reef, rain and crab changes are unphotographed in the respects that matter.**
  The re-angled plants and the shortened stalk were computed off GLB vertices, not seen;
  MultiMesh transforms read back as identity headless so no probe can see them either. The
  sway shader has never been COMPILED (`--check-only` is GDScript only). The rain is
  arithmetic — x0.75 size, x1.20 count — and rain only draws in a squall, which the shot
  harness deliberately pins OFF, so it needs a harness that forces one.

- **The caisson interior collider is REASONED, not reproduced.** s36 gave every casting a
  box collider inset 20 mm inside its CSG, because the CSG-baked ConcavePolygonShape3D has
  no interior and the owner glitched into a pillar. Nobody reproduced the glitch, so this
  is "the casting demonstrably had no interior", not "this was the cause".

- **The dive-depth removal leaves several downstream constants stale.** `DIVE_DEATH_Y` in
  underwater_world.gd is now fish maths only but still documents itself as a death line;
  leg_reef's plant taper is weighted off "the reachable slice is 0.258 of the band" when
  the whole band is now reachable; and mussel_beds' two-rate oxygen integration is
  degenerate (both rates equal) with `_dive_floor()` moving past `DIVE_FLOOR_MIN`, which
  will clamp and push_warning on every world build.

## Open after s46

- **The gull's overlay wings are GEOMETRICALLY CLEARED — the alarming frame was a
  correctly-raised takeoff wing, and the scare is worth keeping for its method.**
  A 4x magnification of the only frames that existed (a FLUSH, tests/out/cat_review/hunt/)
  showed what read as a flat triangular sail standing off the bird's back, and a still
  cannot tell "wing raised 57 degrees at takeoff, which is correct" from "wrong axis".
  `tests/WingScratch.tscn` settles it without rendering anything: it builds the real wings
  on the real model and reads each panel's extent back IN THE BIRD'S OWN AXES, at all three
  flight states. Measured (body half-width 0.187, span 0.50, chord 0.35):

      takeoff   lateral 0.287   vertical 0.410   fore-aft 0.350   dihedral +55.0 deg
      cruise    lateral 0.448   vertical 0.224   fore-aft 0.350   dihedral +26.5 deg
      glide     lateral 0.497   vertical 0.055   fore-aft 0.350   dihedral  +6.3 deg

  The span's two components square-sum to exactly 0.500 at every state, i.e. the panel
  lies in the lateral-vertical plane throughout and only its DIHEDRAL changes — which is
  what a wing is. At cruise and glide the largest extent is lateral, as a wing's must be.
  The takeoff row IS the frightening frame, and it is the pose the owner asked for
  ("wings up when they fly away").
  TWO TRAPS RECORDED. The first scratch called `drive(0.016, false, false)` and `false`
  coerces to airtime 0.0 — inside `HOLD_S`, so it measured the RAISE and nothing else,
  re-photographing the exact pose already in doubt. And a single `drive` call reads 15% of
  an eased dihedral; the states above are settled over 180 ticks. What remains genuinely
  unjudged is only AESTHETIC — whether a PrismMesh triangle reads as plumage at gameplay
  distance — and that wants a level-cruise reel, which no harness films today (CatFilm's
  hunt reel only ever catches the flush). If it does want replacing, the fix is a better
  planform (a 3-4 segment tapered strip with a wrist bend), not a different rotation.

## Open after s49 — CatReviewProbe was calibrated against a constant, and now measures

- **CatReviewProbe's gates have never been meaningful, and 13 now fail honestly for the first
  time.** Two instrument faults, both found by the same tell this repo keeps re-learning — a
  number that will not move is not a measurement:
  * it re-enabled the cat's engine `_process` after calibration and ALSO hand-fed it a fixed
    dt, so every scenario DOUBLE-TICKED (the identical bug s44 found in CatJointProbe, fixed
    there and not in its sibling);
  * `_calibrate` posed the skeleton with `reset_bone_poses()`, which restores the SKELETON's
    rest — but cat_rig corrects the stand mesh's turned head in its OWN `_rest` dict and never
    writes it back, so the forward axis was wrong by exactly HEAD_MESH_YAW. `head_yaw_rms_deg`
    printed 19.0534 / 19.0534 / 19.0537 across three runs with materially different gait,
    glance and clock settings. Fixed: 19.05 -> 0.03 deg, and the run row 0.17.
  With the instrument honest, these remain and are REAL, not artefacts of the old inflation —
  they were simply invisible underneath it:
      [walk] slide_frame 15.3 mm/frame (gate 10)      [walk] joint_step 0.68 rad (gate 0.35)
      [run] joint_step 0.96                            [stalk] slide_frame 10.4, window 20.8
      [stalk] joint_step 1.47                          [carry] joint_step 0.79
      [lookwalk] slide_frame 16.6, joint_step 0.65     [transitions] joint_step 0.67
      [bigdt] summed joint_step 1.09, turn equivalence 6.0 deg
      [lookwalk] head_yaw_toward_target 0.00 (the glance no longer fires while walking by
        design — this gate encodes the OLD full-weight stare and needs rewriting, not the
        animal changing)
  The joint_step cluster is one cause, not eight: the s49 paw curl and deeper swing fold add
  fast terms to the distal joints, and the slew limiter that bounds `_solve_leg` does not see
  layers applied after it. The slide cluster is the stub right hind at the edge of its
  reachable set. DO NOT widen these thresholds — they were set against the inflated numbers
  and are if anything too generous. Next session starts here, with the paw-curl rate and the
  limiter's coverage.

## Open after s52 — the walk's stride, and an instrument that stops seeing

- **CatReviewProbe's foot-slide gates go VACUOUS as the stance arc grows, and they already
  have.** The probe finds stance by paw HEIGHT — "within 6 mm of this paw's own minimum" —
  which is only a stance detector while the paw is flat. It is not. Measured at s52's stride,
  the drawn paws ride 38-59 mm above their lowest point during contact (they rode 26-41 mm
  before it), because a chain of reach c0 covering s of ground traces an arc and this rig's
  binding limb is 0.192 m long. So the window empties: `stance_pairs` at the walk went 20 ->
  6, and run / stalk / carry now report **0 pairs and a perfect 0.0000 mm/frame** — a number
  that cannot fail. The run gate was ALREADY vacuous at s51 (0 pairs, 0.0000) and nobody
  noticed, because a passing gate looks like a passing gate.
  What it hides is real. `tests/GaitScratch` block 4 gates stance off the GAIT'S OWN PHASE
  (`fposmod(phase + WALK_OFF[k], 1) < duty`), which cannot empty, and scores drift over the
  middle 70% of each contact. At the walk it measures:
      lf 4.5   rf 14.5   lh 32.1   rh 5.3   mm/frame
  against the same run's height-band figure of 6.5. The **left hind slides 32 mm/frame and
  always has** (33.7 at the pre-s52 baseline, A/B'd on the same instrument) — it is invisible
  to the shipped gate because that leg lifts 41 mm during its own stance. Cause is measured
  and known: lh's fore-aft lever is 0.214 m/rad against rh's 0.189 and a c0 of 0.402, i.e.
  the stretched-backwards chain of docs/CAT_RIG_CEILING.md §3, so ROM_PROX clamps its hip
  before it has covered the ground and it delivers 0.146 m of a commanded 0.232. DO NOT widen
  ROM_PROX. The fix is the re-rig; the fix for the INSTRUMENT is to port the phase gate into
  cat_review_probe.gd and let it fail honestly first.

- **The speed bands are stale by two sessions and the TROT is now the worst-behaved gait.**
  `WALK_V 1.8 / TROT_V 3.4` were "chosen against WALK_SPEED 1.55 / TROT 2.6 / RUN 4.4" and
  those constants are now 1.10 / 1.9 / 4.4. At TROT_SPEED the mix is 0.06 — the "trot" is a
  walk cycle driven at 1.9 m/s, 4.16 strides/s, and the phase-gated slide there measures
  rf 33.7 and lh 47.2 mm/frame (baseline 29.4 / 47.8, i.e. no worse per stride but the worst
  band in the animal). Re-siting the bands on the shipped speeds is a small change with a
  large payoff and it was deliberately left out of s52 to keep the run untouched.

- **CatHuntProbe failed 2 runs in 8 on the s52 build and 0 in 7 on the baseline, and the
  cause was not found.** Both failures are the same shape: `closed on the bird (nearest
  4.5 m)` plus `zoomies furthest 7.3-7.5 m`. Fisher exact on 2/8 against 0/7 is p ~ 0.47, so
  this is suggestive and NOT significant, and no path was found by which cat_rig feeds back
  into ship_cat's navigation (ship_cat never reads `settle()`, the phase or any bone). It is
  recorded rather than dismissed because the baseline's 7/7 was clean. Re-run it a dozen
  times before and after any further gait change.

## Open after s54 — the cat cannot climb its own "step" band

- **THE CAT GETS ONTO NOTHING BETWEEN 0.20 m AND CLIMB_UP (0.62). The entire step band is
  unclimbable against a vertical face, and it always has been.** Found by the s54 perch
  action stalling 0.9 m short of a 0.45 m crate; measured properly by a new instrument,
  `tests/CatStepScratch.tscn`, which builds a box, stands the player ON it 2.6 m from the cat,
  watches for 13 s and sweeps the height:

      height   0.20   0.35   0.45   0.55   0.62  |  0.70   0.85   1.00   1.15
      got up    no     no     no     no     no   |  YES    YES    YES    YES
      max rise 0.000  0.000  0.000  0.000  0.000 | 0.801  0.949  1.097  1.246   (m off the deck)

  It never leaves the deck by a millimetre below CLIMB_UP, and it gets onto everything above
  it by LEAPING. So `CLIMB_UP`'s comment — "a rig stair tread is well inside this, so it climbs
  one tread at a time" — is true only for ground that RISES GRADUALLY; against any vertical
  face the step band does not exist and the leap band is doing all the work.

  CAUSE, and it is two probes disagreeing about where they look rather than a tuning error.
  `_walk_toward`'s footfall ray probes `want`, ONE STEP ahead — 18 mm at a walk — so it can
  only report a rise once the cat's ORIGIN is within a step of the obstacle's footprint. But
  `_step_clear`'s nose sphere refuses any origin whose nose is inside the face, and the nose
  reaches `_body_len()/2` = 0.33 m ahead. The origin therefore can never get close enough for
  the footfall ray to see a vertical face at all. The only probe that looks a body-length
  ahead is the LEDGE probe, and it is gated `lift > CLIMB_UP` — i.e. it declines precisely the
  band the animal is allowed to step onto. It is the exact mirror of the s38 leap bug recorded
  above, one band down.

  CANDIDATE FIX, deliberately NOT taken in s54 (that was a behaviour session, the gait was
  being changed in the same hour by another builder, and opening the step band changes how the
  animal follows you past every coaming on the rig): let the ledge probe claim a lookahead top
  whose `lift` is inside CLIMB_UP as a STEP — set `want`/`ground`/`rise` from it and fall
  through to the ordinary step path — and apply `_reachable_up` to it as well. The
  reachability rule is the thing s38's reverted attempt lacked, and note the band being opened
  (0.3-0.62 m) is strictly BELOW what the leap already reaches, so it cannot put the cat
  anywhere it could not already get. Re-run `tests/CatStepScratch` and CatProbe's burial sweep
  after.

  WHAT SHIPPED INSTEAD: `ship_cat.PERCH_MIN` is derived as `CLIMB_UP + 0.08`, so the perch
  behaviour only ever wants a vantage the animal is measurably able to reach.

- **CatProbe check 5d ("it ends up ON the crate") went intermittent when WALK_SPEED went
  1.10 -> 1.36 and TROT 1.9 -> 2.38, and the cause is not found.** Tally on this machine:
  at the OLD speeds, 4 runs / 4 passes (one baseline plus three with the s54 instinct layer
  in). At the new speeds, **2 failures in 5 runs** — and three of those five had the instinct
  layer pinned off (`_idle_cd` / `_roam_cd` at 999) for the whole 5d window, so it is not the
  new behaviour. The shape is always the same: the leap fires and `leap_top` records the full
  1.10 m rise, then the animal is back at y 18.00 by the end of the 600-frame window, and the
  descent check that follows reports "18.00 -> 18.00" with a flight having fired. So it gets
  up and comes back down inside the window. Recorded rather than dismissed; re-run it a dozen
  times before and after any further speed change.

## Open after s52 — the red lines, half-answered

- **The pod's two red lines: the hi-vis nosings are fixed, the two READABLES are the same physics
  and are still there.** Owner report, third time. Cause is not bloom and not the paint choice — it
  is that the SPHL's only light is `Color(0.9, 0.15, 0.1)` (rig_builder `_build_sphl`), and
  reflected colour is albedo x light, so ANY pale or warm surface in that room returns a saturated
  red brighter than its neighbours. Measured, against the grey shell's (0.558, 0.099, 0.070):
      hi-vis nosing  albedo (0.440, 0.165, 0.028) -> (0.396, 0.025, 0.003)  sat 0.99   FIXED s52
      readable page  albedo (0.870, 0.850, 0.770) -> (0.783, 0.128, 0.077)  sat 0.90   OPEN
  The nosings now use `dark_metal()` -> (0.198, 0.034, 0.026), darker than the shell, and read as
  moulding. The two `_readable` page blocks (`rig_builder.gd:2482-2483`, Survival Manual at
  (15.15, WET_Y+1.35, cz+0.9) and Pressure Log at cz-0.9) are now the BRIGHTEST objects in the pod
  and are exactly two, symmetric, and line-shaped at viewing distance — the best remaining match for
  the report. They are functional story items and were NOT removed unilaterally; awaiting the
  owner's call. If they are the ones: the fix is not to recolour them (no warm albedo survives that
  lamp) but either to give the pod a small neutral fill light, or to accept them and darken the page
  stock. `tests/Beta1Shot --only=sphl_interior` now actually photographs the pod and settles it.

- **The seven untextured fish are covered, not fixed.** `materials/fish_skin.gdshader` synthesises a
  countershaded, mottled skin from `school.tint` so they no longer read as one flat colour, and it
  is keyed on "has no albedo texture" so it silently stops applying the moment real textures land.
  The real fix is still to regenerate the seven through Tripo; dropping a textured `<id>.glb` into
  `assets/models/fauna/<id>/` needs NO code change anywhere. Measured while judging the render: the
  mackerel and garfish read washed out (`belly_pale` 0.85 lifts already-pale tints hard), and the
  kelp pipefish is nearly invisible in hand because six of the small species clamp to the 0.18 m
  hand floor (`hand = max(0.18, body * 0.5)`), so a pipefish and a copper sprat are the same size
  in the pack.

## Open after s53 — three instruments that were passing on nothing

- **CatReviewProbe's slide gates were VACUOUS at HEAD and are now honest — the 30 mm/frame left
  hind is REAL and PRE-EXISTING, not an s53 regression.** Measured by stashing the whole session
  and re-running at 609fc0c:
      [run]   stance_pairs = 0  ->  slide_frame_mm = 0.0000  ->  PASS
      [stalk] stance_pairs = 0  ->  slide_frame_mm = 0.0000  ->  PASS
      [carry] stance_pairs = 0  ->  slide_frame_mm = 0.0000  ->  PASS
  Three gates were green because the height-band stance detector emptied its own window. With
  the detector fixed the probe reads FAILURES 3 -> 10, and the seven new rows are EXPOSURE, not
  breakage. The underlying defect is the one docs/CAT_RIG_CEILING.md §3 describes: the left hind
  is dead straight in bind (L_Thigh->L_Calf 0.336 m against R at 0.086), its lever is 0.214 m/rad
  so ROM_PROX clamps its hip, and the slide hides under its own 41 mm of stance lift. It needs
  the re-rig. DO NOT widen these gates and DO NOT "fix" them by restoring the vacuum.

- **No pose in the library had EVER been solved inside the animal's joint limits.**
  `_build_poses()` ran before `_prep_ik()`, and `_prep_ik` is where `_rom` is built — so `_rom`
  was an empty dictionary for the whole bake and `_clamp_joint` was a silent no-op. `tick` clamps
  every frame, so the authored library and the drawn animal were two different cats: on a still
  sit the runtime clamp took 12.31 deg off L_Forearm, 8.14 off R_Calf, 3.09 off L_Calf. Fixed by
  swapping the call order (`_prep_ik` reads only the rest skeleton, never `_poses`). Every pose in
  the library shifted slightly when this landed; that is the fix, not a regression.

- **`paw_below_deck_max_mm` could not see half the defect it was named for.** The owner reported
  the seated cat pitched backwards — forepaws floating ~1 inch, hind paws sunk ~1 inch — and this
  gate had been failing 2 runs in 3 at 39-66 mm for two sessions, dismissed both times as a wash
  bout landing in the sit window. It was right all along. Three blind spots, all now documented in
  the probe: it is a MAX OF ONE SIGN (a floating paw makes the number SMALLER, so the fore half of
  the report was invisible by construction); it is UN-BASELINED (one flat 25 mm allowance against
  four paw bones that rest 14.6 mm apart, so the hind pair started with half the budget spent);
  and it is a MAX OVER A MIXED WINDOW (the sit scenario never restages, so its 7 s contain a walk,
  sit_pre, sit_deep and sit, and which one the max lands on depends on machine load). A permanent
  defect reported intermittently. Replaced by `[sit_paws]`, which measures each paw against its
  own rest height, gates float / sink / pitch separately, and carries an anti-vacuity sample gate.

- **A settled friendly cat calls `_face` nowhere at all**, so the first version of the seated
  no-spin test passed VACUOUSLY (body yaw 0.0 deg, head 0.0 deg — nothing was driving either).
  Only three seated callers exist: the pre-friend greeting, `_on_touched`, and the PET branch. The
  test now drives the PETTED sit, which is the path that actually spun. Worth remembering the next
  time a behaviour test passes first try.

- **Still not decimated, with numbers.** `wooden_candlestick` 212,992 tris x 1 and `fir_sapling`
  433,021 x 1 are the most absurd densities in the repo (213 k for a 22 cm object) but are `.gltf`
  with EXTERNAL BUFFERS, and `tools/decimate_inplace.py` writes GLB to the given path, which would
  corrupt the dependency graph — needs a different exporter path, ~0.65 M combined. The cat pose
  GLBs are 501,378 tris each and are read as pose SOURCES by `tools/extract_cat_poses.py`, so
  re-cutting them could invalidate pose extraction silently — do the rig work first.
  `ultra_hammerhead` 151,098 x 3 declined on fidelity: 0.6% of the world for real risk to a
  set-piece whose facing already reads UNCERTAIN.

## THE FIELD (s54b) — the second pass, and what is still absent

s54b answered the owner's "beef this all up": THE ANCHORAGE was rebuilt at 84 x 60 m with a
circular atrium drum and a 16.9 m column aquarium, and MARROW and DEEPWELL each gained a
full extra occupied deck plus an outboard catwalk ring. Field totals went 5,852 -> 12,544
primitives and 80 k -> 199 k triangles for 108 -> 153 draw chunks. The list below is what
that pass did NOT do, and it is still accurate.

- **The lights work but the switch is shared.** Every emissive fixture is in RigKit's "lamp"
  group and starts hidden; `rig_field._wire_power()` flips all 40 lamp chunks and all 43
  OmniLights off rig 1's existing `topside_floodlights` circuit. There are no per-rig
  breakers, so the field cannot be lit rig by rig and nothing on rigs 2-4 can be switched
  independently.
- **Wing tower interiors are empty shells** (the ground-level program is real now: suites,
  dining, kitchen, salon are walled and furnished as of s54c). The towers above the terrace
  and the spa block still have no interior fit-out, and no doors that open anywhere.
- **(superseded s54c)** Rooms are volumes, not rooms. The ANCHORAGE's wings, lobby, spa hall and leisure deck
  have real walls, floors, window bands, doorways and partitions — and no furniture, no
  props, no readables, no doors that open.
- **The aquarium's rockwork and kelp are boxes.** Deliberate massing; the hero-prop pass
  (Tripo) replaces it, and `tools/survey_tris.py` must run on every candidate first.

## THE FIELD (s54) — what is structure only, and what is not there yet

The three new rigs are a STRUCTURAL pass: masses, elevations, decks, stairs, rails, bridges,
and the hero-feature shells. Everything below is known-absent, not broken.

- **Interiors are empty shells.** MARROW's mess/plant/hydroponics blocks, the ANCHORAGE's
  hotel and annexe, DEEPWELL's lab and control room all have walls, floors, windows, doorways
  and roofs — and nothing inside. No `interior_props`, no readables, no items, no lighting
  beyond the deck floods.
- **Nine fishing spots are MARKERS ONLY.** They are `Node3D`s in group `field_fishing_spot`
  carrying `spot_id` / `water` / `rig_id` metadata, at probed heights spanning y 1.8 to 22.0.
  Nothing in `fish_table.gd` reads them yet, so fishing at a new rig behaves as open water.
  `docs/FISHING_BALANCE.md` is unchanged; DEEPWELL's own deep species set is not written.
- **Soil tending is not built.** MARROW's twelve raised beds exist as geometry on a constant
  grid (`RigTwo.BED_COLS/BED_ROWS/BED/BED_GAP`) so the state machine has something honest to
  bind to. There is no till/water state and no persistence.
- **(fixed s56)** Aquarium stock persists — SaveManager "aquarium" key, proven by
  AquariumSaveProbe against the slot file re-read off disk. Found while proving it: 36
  species carry no size_kg, so their instance length read 0.0 and the 5/50 ft limits
  were VACUOUS for most of the roster; aquarium_stock._len_of falls back to the authored
  species length. Still open from this area: the cat's doggy-paddle swim home is unbuilt
  (the rescue teleport covers it).
- **(superseded s55)** The aquarium holds no fish. As of s54b it is a CYLINDER: the node in group `aquarium`
  carries `shape` "cylinder", `radius` 5.25, `height` 16.60 (1,437 m³) and `circuit`
  "anchorage_aquarium". There is no PowerGrid circuit of that name, no filter consumable, no
  stocking and no container storage wired. A stocking pass must read `shape` — the old
  `water_size` box is still published but it now INSCRIBES the cylinder rather than equalling
  it, so a spawner that trusts the box alone will put fish in the corners, outside the glass.
- **Bridges are cosmetically damaged only.** All three ship CONNECTED and walkable (owner's
  call, so the field is explorable now). `RigField.SPAN_DAMAGE` drops web members near the far
  end, worst on the final span. There is no repair cost, no gate and no progression lock.
- **The sonar oracle does not know the field exists.** `tools/rig_capture.gd` takes a new
  `--field` flag and `tools/export_rig.sh --field` passes it, and the Godot side has been run —
  but the sonar re-ingest has NOT, so `scene_brief` / `props_find` / `spatial_probe` still
  describe SALTLINE-0 alone. Any spatial query about rigs 2-4 will silently return nothing.
- **No underwater world at the new rigs.** `leg_reef`, `mussel_beds` and the pelagic schools are
  all keyed to `Seabed.LEGS` (rig 1). `rig_field._field_seabed()` extends the floor over the
  corridor as one coarse mesh so a diver does not find the world's edge, but there is no reef,
  no kelp and no fauna on the new caissons.
- **The draw-call figure has not been measured against a live frame.** The field costs 108 draw
  chunks (77 of them submitted from SALTLINE-0's deck) by construction, and 80,052 triangles.
  That is a count of what is BUILT. `godot --path . tests/VantagePerf.tscn -- --nofield` builds
  the identical session without the field for a single-session A/B; it has not been run.
- **Rockwork in the aquarium is boxes.** Deliberate — hero props (the rockwork, a wrecked
  helicopter for the ANCHORAGE's pad, the crown block, garden beds, captain's furniture) are
  the Tripo pass, and `tools/survey_tris.py` must run on every candidate first.

## Open after s56 — the luxury pass

- **The ANCHORAGE loungers and planters are massing, not furniture.** The leisure-deck
  loungers are single tilted canvas boxes and the palms are two stacked cones; they read
  at room scale but not up close. They are the natural Tripo hero-prop batch (loungers,
  potted palms, the billiard table, spa benches) — run tools/survey_tris.py on every
  candidate first.
- **The salon chart's route line reads faint at room distance.** The four rig markers
  carry the piece; the connecting line is 24 mm glowing members that wash out under the
  downlight. If the owner wants the route legible, thicken to ~40 mm or raise its energy
  — but check it against the night pass first, where every lamp reads hotter.
- **The upper tower storeys (west k1/k2, east k1) are still empty shells.** s56 fitted
  the two GROUND lounges (library, games room). The balcony-band storeys above have
  floors, windows and doors and nothing inside.
- **The sonar oracle still knows only SALTLINE-0.** Unchanged from s54; every
  props_find/spatial_probe about rigs 2-4 silently returns nothing. tools/export_rig.sh
  --field exists; the re-ingest has still not been run.

## THE FIELD (s64) — what the dressing pass closed, and what it opened

**CLOSED by s64:**
- *"Interiors are empty shells"* (filed s54, for the whole field). DEEPWELL's shaker house,
  core-sample lab, control room and decon airlock are built and dressed; THE ANCHORAGE's nine
  suites and every public room are dressed. `scripts/world/field_dress.gd` carries the tables.
- *"The ANCHORAGE loungers and planters are massing, not furniture"* (s54b). Real GLB furniture
  throughout, and the four terrace planters that were **hanging over the atrium light well**
  now stand on deck.

**OPEN, and new:**

- **SUITE W1's CELL OVERLAPS THE SOUTH HALL CORRIDOR.** `rig_three._suites()` opens its west
  flank at z -13, but `_ceilings()` runs the south hall across z -12.9..-9.1 at the same x. So
  W1's cell [-13, -6.3] overlaps the corridor and `_suite()` stands W1's BED at z -9.65, in the
  hall. `field_dress._suite_rows()` deliberately skips W1 rather than adding a nightstand and a
  reading chair to a public corridor. THE FIX IS A FLOORPLAN CALL — shorten the west column to
  start at z -9.0 (and accept eight suites, or re-cut the six cells over the shorter run), or
  move the south hall north. Both change room sizes, so it wants the owner's eye, not a patch.

- **The hotel rooms are still too BIG.** A west suite is 16 m deep and a guest room is not.
  Every suite now reads as furnished but sparse, because a bed, two nightstands, a chair, a
  trunk and a plant do not fill 100 m². The honest fix is architectural (split the depth into
  a room plus a bathroom pod / dressing lobby, which the s54c floorplan comment already
  promises: "a bathroom pod"), not more props.

- **`max_lights_per_object` costs 1.5-2 ms.** Raised 8 -> 24 in project.godot for the reason in
  docs/AGENT_TRAPS.md, measured on VantagePerf. It is the right trade — it is the difference
  between a lit hotel and a black one — but it is a real cost on a project already under its
  own 60 fps bar at several vantages, and it is the first thing to reconsider if the frame
  budget gets tight. 16 was tried and rejected on the picture.

- **The moon pool does not read as a fissure** (s64 audit, DEEPWELL). By day the BOP disc plugs
  the aperture and the water reflects sky; by night it is a black hole. The teal sheet at
  y 1.15 never reads in either. Wants the glow sheet raised to ~y 6 and shrunk inside
  MOON.grow(-1.0) so it sits between the eye and the water.

- **DEEPWELL's production deck floor is black.** 18 emissive lenses and only three real
  OmniLights across a whole occupied level; the floor measures (1,11,10) under a ceiling at
  (9,50,46). Same root cause as the interiors this session fixed — a lens is not a light.

- **The driller's cabin is a solid block with a glass sticker**, not a room
  (`rig_four._drill_substructure`). Should be a `KIT.lookout()` on the same footprint so it can
  be entered and dressed like the control room now is.
