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
