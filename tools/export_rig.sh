#!/bin/zsh
## One command: rebuild the live rig from code → re-scan it in sonar.
## Edit RigBuilder (or any dressing script), run this, refresh the viewer.
set -e
cd "$(dirname "$0")/.."
## Pass --field to capture THE FIELD as well (rigs 2-4 and the bridges, s54). Left OFF by
## default so an existing scan and every coordinate in docs/RIG_ATLAS.md still reproduce.
## NOTE: the field capture path has been exercised in Godot but the sonar re-ingest has NOT
## been run against it — until it is, the spatial oracle knows about SALTLINE-0 only.
CAPTURE_ARGS=""
if [[ "$1" == "--field" ]]; then CAPTURE_ARGS="-- --field"; fi
echo "→ capturing live rig from Godot (headless)… $CAPTURE_ARGS"
godot --headless --path . res://tools/RigCapture.tscn $CAPTURE_ARGS
SONAR=/Users/mjspeh/Desktop/VoxelSonarPlan/sonar-mcp
echo "→ ingesting into sonar…"
"$SONAR/.venv/bin/python" "$SONAR/tools/ingest_rig.py" "$PWD/rig_capture.glb"
echo "✓ rig re-scanned — viewer: http://localhost:8971"
