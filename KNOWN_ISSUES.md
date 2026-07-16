# Known Issues

- **Un-crouching has no headroom check** — standing up under low geometry can
  grow the capsule into it (review finding; pre-existing). Add an upward
  shape-cast gate in `_update_crouch` when a crawl-space area exists.

- **Interior props stream in over ~1s after the scene loads.** Instancing ~200
  glTF props at once blocked the main thread for ~7s (froze the window on Play),
  so `interior_props.gd` now queues placements and instances a few per frame.
  Furniture/decor visibly settles in during the first second — intentional.

- **Single-material boxes texture all faces alike** — e.g. the topside deck slab
  shows treadplate on its underside too (world-triplanar applies everywhere).
  Split top/side materials on the big slabs in the art polish pass.

- **Built structures and journal don't persist** — SaveManager saves stats/inventory/
  power, not placed structures or journal discoveries. Wire into save_game() for v0.2.
- **Build placement has no overlap check** — you can place structures intersecting
  props or each other. Grid snap keeps it mostly sane; add a shape sweep in v0.2.

- **Windows export preset not generated.** Export templates aren't installed on this
  machine. In the editor: Project → Export → Add → Windows Desktop, install templates.
- **Interior lighting is faked** with sun-scaled "spill" omni lights, not real light
  shafts through doors/windows. Fine for greybox; replace in the art pass.
- **SPHL doesn't bob** — it's cradle-moored, static. Buoyancy is v0.2 (boats phase).
- **No continue flow.** SaveManager autosaves at dawn/dusk, but Main always starts a
  fresh run. Wire a title/continue prompt when there's a title screen.
- **Ladder mantle is teleport-ish.** Works reliably, but the top-of-ladder exit is a
  position snap, not an animated mantle. Budgeted fiddliness per the brief.
- **Crab is kinematic** (no physics/navmesh) per the brief — it can clip greybox props
  on the ascend path. Waypoints in `rig_builder.gd` if it misbehaves.
- **macOS note:** project relocated from `~/Desktop/SALTLINE` to `~/SALTLINE` after a
  macOS privacy (TCC) denial blocked shell access to Desktop. The old Desktop copy is
  orphaned and can be deleted manually.
