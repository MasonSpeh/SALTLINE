#!/bin/zsh
## One command: rebuild the live rig from code → re-scan it in sonar.
## Edit RigBuilder (or any dressing script), run this, refresh the viewer.
set -e
cd "$(dirname "$0")/.."
echo "→ capturing live rig from Godot (headless)…"
godot --headless --path . res://tools/RigCapture.tscn
SONAR=/Users/mjspeh/Desktop/VoxelSonarPlan/sonar-mcp
echo "→ ingesting into sonar…"
"$SONAR/.venv/bin/python" "$SONAR/tools/ingest_rig.py" "$PWD/rig_capture.glb"
echo "✓ rig re-scanned — viewer: http://localhost:8971"
