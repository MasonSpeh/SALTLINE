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

## Watch items

- **NaN source upstream of `fauna_move.gd` is unidentified.** s18 added
  `is_finite()` guards and self-healing frames, so a bad value is now harmless
  instead of producing a 4.4 GB stderr storm. But the guards make the condition
  *quiet*, not absent. If a creature is ever seen freezing or teleporting, start
  here.

- **Fish cost ~3.7 ms at the waterline** — pure CPU, not draw calls. Every fish
  sums 11 Gerstner waves in GDScript every frame (~3300 iterations). Zero cost
  on deck (the topside cull freezes the subtree). The lever, if it is ever
  needed, is hoisting `Gyre.water_time()` out of the per-fish loop and skipping
  `wave_height` for pods provably below any trough — *not* cutting population,
  which was measured and buys nothing. *Measured s18.*

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
