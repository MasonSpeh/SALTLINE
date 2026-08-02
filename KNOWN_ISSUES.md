# Known Issues

Open items only. Fixed entries are deleted, not struck through — git remembers.
Verify before adding: several entries here were stale for weeks because the fix
landed and nobody updated the file.

## Bugs

- **The first dive of a session stalls ~285 ms, and the warm state DECAYS — OPEN, characterised
  s26.** Owner-reported as "it freezes for a good second before you can see underwater". Measured
  with `tests/DiveProbe.tscn` (windowed, foreground); the discriminating experiment is to dive
  twice, because a cost only the FIRST dive pays is a one-off and a cost every dive pays is the
  visibility walk:

      dive 1  peak 285.1 ms, ~365 ms of frames over the line    dive 2  peak 46.5 ms, none

  So the ~4,100-node `visible` flip in `underwater_world._cull_topside` is **innocent** and needs
  no staggering. **Three fixes were built, measured and reverted** — do not re-attempt them:
  drawing all 1,120 of the subtree's materials at load through a SubViewport sharing the real
  World3D (verified rasterising 37.76 M prims/frame — dive still 239.5 ms); hanging the
  underwater Environment on the real camera topside (that frame alone cost 275.5 ms, dive still
  239.6 ms — two separate bills); and gating a full rehearsal on `rig_batcher`'s weld so the
  warmed configuration matched the welded one (dive still 264.2 ms).

  **The reason none of them work is that it decays with time hidden.** Rehearse the transition,
  then sit topside before diving: gap ~3 s → 67 ms, 30 s → 127 ms, ~36 s → 264 ms, never →
  285 ms. Monotonic. Something is released for not having been drawn recently, which on this
  machine's GL-over-Metal path reads as GPU residency. **A one-time prewarm therefore cannot
  fix this.** The untried candidate is to keep the subtree warm *near the water* — start
  rendering it into a small SubViewport once the player's eye drops toward the waterline, or
  ping it periodically — trading a small recurring cost against the 285 ms cliff. Note the
  ceiling on that: drawing the subtree costs ~35–55 ms/frame, so a naive ping is not free.
  `main.gd::_prewarm_underwater_env` is a real but PARTIAL fix (the Environment only); its
  comment used to read as though it had solved the freeze, and it had not.

- **`Sealed Crate` (16.5, −8.0) nicks a folding stool** by 0.0157 m³. Small, but
  it is a real intersection. *Found s18.*

- **`Wet Deck Ladder — East` mid-climb clearance is 0.35 m** against a 0.37 m
  capsule. Collision is disabled during a climb and both exits resolve
  correctly, so it is not player-visible today — but it is 2 cm from being the
  same class of bug that made three other ladders impassable. *Found s18.*

- **Build placement has no overlap check** — structures can be placed
  intersecting props or each other. Grid snap keeps it mostly sane; needs a
  shape sweep.

- **`TestRunner`'s "raw fish rots after 4 game hours hung" is intermittently
  flaky, and it is a test bug rather than a game bug.** `hang_line._hang()` takes
  the first *hangable* item in the player's pack, which is not necessarily the
  herring that check just added — anything an earlier fishing/net check left
  behind can be hung instead, and a BIG fish cures to `dried_fish` instead of
  rotting. What is in the pack there depends on RNG draws and on how many engine
  frames elapse inside the suite's `await` timers, so machine load changes the
  outcome. Reported failing once by a coordinator; **not reproduced in 5
  consecutive local runs**, including with the leg reef present. The assertion now
  prints what it hung and what it became, so the next occurrence names the
  culprit. The real fix is to clear the pack before hanging, which first needs a
  check that the following assertions do not depend on those items. *Found s19.*

## Watch items

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

- **The reef costs ~0.95–1.03 M triangles per leg (s20), up from 0.62–0.72 M.**
  1,170 instances in 62 MultiMesh draws, ~15 of them for whichever leg you are
  looking at. s19 measured the 560-instance version at 1.98 ms (8.5%) at
  `submerged_deep`; this is roughly 1.45x the per-leg triangle count and 2.1x the
  instances, and has **not** been re-profiled. If `submerged_deep` regresses, the
  cheapest levers in order are `barnacle_cluster_a`'s 4,000-tri budget (it cannot
  go lower without shattering — cut its weight instead), `coral_brain` at 100 x
  5,000, and `_crust_face`'s instance count.

## Accepted / by design

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
