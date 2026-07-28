#!/usr/bin/env bash
# Build the Windows release and wrap it in a player-friendly zip for itch.io.
# Usage: tools/package_windows.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

STAGE="builds/SALTLINE-Windows"
OUT="builds/SALTLINE-Windows.zip"

echo "==> Exporting Windows release"
mkdir -p builds/windows
godot --headless --export-release "Windows Desktop"

echo "==> Staging player package"
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE"
cp builds/windows/SALTLINE.exe "$STAGE/SALTLINE.exe"
cp "dist/START HERE - How to Play.txt" "$STAGE/"

echo "==> Zipping"
# -X strips macOS extended attributes so Windows users get a clean archive.
(cd builds && zip -r -X "$(basename "$OUT")" "$(basename "$STAGE")" >/dev/null)

echo "==> Done"
ls -lh "$OUT"
