#!/usr/bin/env python3
"""s37: the NEUTRAL STANDING cat — the base pose the blend architecture needs.

The pose-per-mesh design is being replaced by ONE skeleton with every pose and gait
blended on it, and that architecture needs a neutral base: a cat standing square on all
four feet, level, head forward. The s32 ship_cat mesh IS that pose but predates the
submit log, so it has no task id and cannot be rigged. This regenerates the same stance
with the byte-identical COAT (imported, not retyped — a cat whose fur changes when it
stands up is worse than no blend system) and the head/symmetry clause that fixed the
crooked run.

    python3 tools/gen_cat_stand.py [--dry-run]
"""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / ".claude/skills/realistic-animals/scripts"))

from gen_animal import load_key, generate_mesh, download_model  # noqa: E402
from gen_cat_batch import COAT, TAIL  # noqa: E402
from gen_cat_s36 import STRAIGHT  # noqa: E402

OUT = REPO / "assets/models/fauna"
IDLOG = REPO / "tests/out/cat_poses/task_ids_s36.json"

POSE = (
    ", standing squarely on all four feet in a neutral resting stance, all four legs "
    "straight and vertical under the body, weight even on all four paws, back level and "
    "horizontal, tail held in a relaxed low curve behind" + STRAIGHT
)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    prompt = COAT + POSE + TAIL
    print(f"cat_stand: {len(prompt)} chars")
    assert len(prompt) < 1000
    if args.dry_run:
        print(prompt)
        return 0

    key = load_key("tripo")
    ids = json.loads(IDLOG.read_text()) if IDLOG.exists() else {}
    res = generate_mesh("tripo", key, prompt=prompt)
    ids["cat_stand"] = str(res.get("id"))
    IDLOG.write_text(json.dumps(ids, indent=2))
    download_model(res, OUT / "cat_stand" / "cat_stand.glb")
    print("OK cat_stand — now rig it: python3 tools/rig_cat.py --want "
          "'{\"cat_stand\":[\"idle\"]}'")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
