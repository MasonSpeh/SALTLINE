# Known Issues

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
