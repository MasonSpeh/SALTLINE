# Known Issues

Open items only. Fixed entries are deleted, not struck through — git remembers.
Verify before adding: several entries here were stale for weeks because the fix
landed and nobody updated the file.

## Bugs

- **`SurfaceSnap` fires before CSG collision exists.** A store-room storage
  crate ends up at y −0.9, about 3 m below the wet deck. The snap runs on the
  first physics tick, but the deck slab is CSG and has no collider yet, so the
  prop drops through. Same root cause as the deferred `_snap_to_deck()` /
  `_snap_to_perch()` helpers in `bloom_fauna.gd` — those defer out of `_ready()`
  for exactly this reason. Fix `SurfaceSnap` the same way. *Found s18.*

- **`Sealed Crate` (16.5, −8.0) nicks a folding stool** by 0.0157 m³. Small, but
  it is a real intersection. *Found s18.*

- **`Wet Deck Ladder — East` mid-climb clearance is 0.35 m** against a 0.37 m
  capsule. Collision is disabled during a climb and both exits resolve
  correctly, so it is not player-visible today — but it is 2 cm from being the
  same class of bug that made three other ladders impassable. *Found s18.*

- **Un-crouching has no headroom check** — standing up under low geometry can
  grow the capsule into it. Add an upward shape-cast gate in `_update_crouch`
  when a crawl-space area exists.

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
