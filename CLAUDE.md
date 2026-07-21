# SALTLINE — agent notes

Godot 4 game (gl_compatibility) — an oil-rig survival slice. The rig is
built **in code** by `scripts/world/rig_builder.gd` (+ dressing scripts it
spawns); positions in those scripts ARE the level design.

## Spatial ground truth (sonar)

This project has a live spatial oracle: the **sonar MCP server** is wired
via `.mcp.json` and points at the scanned rig in `.sonar-rig/`.

- **Call `scene_brief` first** — it returns RIG_ATLAS.md: coordinate
  mapping, deck elevations, zones, tool cookbook.
- Don't guess geometry or coordinates — probe them: `spatial_probe`,
  `spatial_slice`, `spatial_raycast`, `spatial_measure`.
- Item locations: `props_find {query|zone|near}`. Rooms: `scene_zones`.
- Coordinate contract (verified): godot(x,y,z) m ↔ sonar(1000x, −1000z,
  1000y) mm.
- After editing rig/dressing code, refresh the scan:
  `tools/export_rig.sh` (headless capture → re-ingest → new atlas/plans).
  The scan is a snapshot — check the atlas timestamp before trusting it.

Zone volumes are authored in `tools/rig_zones.json` (godot meters) — keep
them in sync when rooms move. Floor plans: `.sonar-rig/deck_plans.txt`;
item manifest: `.sonar-rig/rig_manifest.txt`. Live viewer:
`python /Users/mjspeh/Desktop/VoxelSonarPlan/sonar-mcp/viewer/serve.py
--scene-dir ~/SALTLINE/.sonar-rig` → http://localhost:8971.
