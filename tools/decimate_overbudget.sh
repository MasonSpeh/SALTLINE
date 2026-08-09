#!/bin/bash
# Re-cut the fauna meshes that import far above the budget the rest of the roster ships.
#
# WHY THESE, AND WHY THESE NUMBERS. Every target here is measured, not guessed —
# `python3 tools/survey_tris.py` counts triangles off the glTF index accessors and
# `res://tests/WorldTriCensus.tscn` multiplies that by the instances the live world
# actually spawns. The budget for each line below is the number its OWN PEERS already
# ship at in the same world:
#
#   * the eleven s31 school species -> 31,000. The other twenty-three school species
#     import at 25,026-31,247 (fish_mirrorjack 25,026, fish_inkwell_squid 31,247), so
#     31k is the roster's own median, not a target invented for this pass. These are
#     0.4-2 m animals seen at several metres through fog and water.
#   * herring_gull -> 60,000. sea_gull, the same animal in the same sky, imports at
#     30,087 and nobody has complained about it. The gull is given DOUBLE its peer's
#     budget anyway, because a bird's thin legs and beak are exactly the features a
#     collapse decimator eats first, and because at 7 instances the difference between
#     31k and 60k is only 0.2 M world triangles — cheap insurance.
#
# WHAT IS DELIBERATELY NOT HERE. See the session report: the cat poses (another agent
# owns that rig and only one pose is instanced at a time), the .gltf props such as
# wooden_candlestick and fir_sapling (external-buffer glTF — the in-place tool writes
# GLB and would corrupt the .gltf's dependency graph), and the showpiece animals seen
# close at one to three instances.
#
# The heavy lifting is tools/decimate_inplace.py, which is the ONLY one of the three
# decimate_* scripts that does not re-bake orientation — critical, because these species'
# facing is pinned in CreatureAnim.FACING_OVERRIDES and re-centring would silently
# invalidate it.
#
# TEX_PX is set high on purpose: this pass changes TRIANGLES ONLY. Every target's
# textures are 2048 or smaller, so the cap is a verified no-op and the albedo the
# artist shipped is the albedo that stays.
#
#     bash tools/decimate_overbudget.sh
#
# Re-runnable, but NOT idempotent in the useful sense: it decimates in place, so running
# it twice cuts twice. Restore from git (or a backup) before a second run.

set -euo pipefail

BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
TEX_PX="${TEX_PX:-8192}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -x "$BLENDER" ]; then
  echo "no Blender at $BLENDER — set BLENDER=/path/to/Blender" >&2
  exit 1
fi

# slug:budget — the eleven s31 school species, then the gull.
TARGETS="
fish_leopard_grouper:31000
fish_bluelined_grouper:31000
fish_swallowtail:31000
fish_peacock_grouper:31000
fish_humpback_grouper:31000
fish_skipjack_tuna:31000
fish_albacore_tuna:31000
fish_yellowfin_tuna:31000
fish_mahi_mahi:31000
fish_bigeye_tuna:31000
fish_bluefin_tuna:31000
herring_gull:60000
"

for entry in $TARGETS; do
  slug="${entry%%:*}"
  budget="${entry##*:}"
  glb="assets/models/fauna/$slug/$slug.glb"
  if [ ! -f "$glb" ]; then
    echo "MISSING $glb" >&2
    exit 1
  fi
  echo "=== $slug -> $budget"
  "$BLENDER" --background --python tools/decimate_inplace.py -- "$glb" "$budget" "$TEX_PX" \
    2>&1 | grep '\[decimate_inplace\]'
done

echo
echo "done. Now re-measure, in this order:"
echo "  python3 tools/survey_tris.py | head -30"
echo "  python3 tools/measure_facing.py --calibrate     # must stay 19 correct / 0 wrong"
echo "  godot --headless --path . res://tests/WorldTriCensus.tscn"
echo "  godot --headless --path . res://tests/FishSpreadProbe.tscn"
