#!/usr/bin/env python3
"""Try to get a REAL skeleton onto the ship's cat.

Measured fact this exists to change: of the 165 GLBs in this project, ZERO
contain an animation or a skin. The whole bestiary is static meshes posed by
`creature_anim.gd`, and the cat is five static poses swapped between — which is
exactly the owner's "unanimated ... legs moving at a MINIMUM".

Meshy's auto-rig is confirmed humanoid-only (422 on any animal). Tripo's has
never been tried here. This script tries it, on the ALREADY-SHIPPING cat meshes
rather than on fresh generations, by reusing the task ids s34 logged in
tests/out/cat_poses/task_ids.json — so a success animates the cat the owner
already has instead of replacing it with a different-looking one.

Outcome is one of:
  * rigged + retargeted GLBs land in assets/models/fauna/_rigged/ -> the cat can
    have genuine skeletal legs, and this becomes the first rigged asset here
  * the API refuses (as Meshy does) -> we know, in one cheap async run, that the
    procedural route in creature_anim.gd is the only way, and no time was spent
    guessing

Usage:  python3 tools/rig_cat.py
"""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / ".claude/skills/realistic-animals/scripts"))

import gen_animal as G  # noqa: E402

IDS = REPO / "tests/out/cat_poses/task_ids.json"
OUT = REPO / "assets/models/fauna/_rigged"

# Which pose mesh to ask for which clips. cat_walk and cat_run are the two the
# owner will actually see moving; idle goes on the sit pose so a resting cat can
# breathe rather than freeze.
WANT = {
    "cat_walk": ["walk"],
    "cat_run": ["run"],
    "cat_sit": ["idle"],
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--want", help='JSON like {"cat_groom":["idle"]} — overrides WANT, so a '
                                   'second batch does not re-rig what already landed')
    args = ap.parse_args()
    want = json.loads(args.want) if args.want else WANT

    key = G.load_key("tripo")
    ids = json.loads(IDS.read_text())
    OUT.mkdir(parents=True, exist_ok=True)

    report: dict[str, dict] = {}
    for pose, clips in want.items():
        entry = ids.get(pose)
        if not entry or not entry.get("id"):
            print(f"{pose}: NO TASK ID RECORDED — skipping")
            report[pose] = {"ok": False, "why": "no task id"}
            continue
        base = entry["id"]
        print(f"\n=== {pose}  (base task {base}) -> clips {clips} ===")
        try:
            got = G.tripo_rig_and_animate(key, base, clips)
        except Exception as e:  # never let one pose kill the batch
            print(f"{pose}: rig+animate raised {type(e).__name__}: {e}")
            report[pose] = {"ok": False, "why": f"{type(e).__name__}: {e}"}
            continue

        if not got:
            print(f"{pose}: no clips came back — Tripo declined to rig this mesh.")
            report[pose] = {"ok": False, "why": "no clips returned (rig declined)"}
            continue

        landed = {}
        for clip, task in got.items():
            url = G._tripo_glb_url(task)
            if not url:
                print(f"{pose}/{clip}: task succeeded but carried no GLB url")
                continue
            dest = OUT / f"{pose}_{clip}.glb"
            try:
                G.download_url(url, dest)
                landed[clip] = str(dest.relative_to(REPO))
            except Exception as e:
                print(f"{pose}/{clip}: download failed {e}")
        report[pose] = {"ok": bool(landed), "clips": landed}

    # Merge rather than clobber: a second batch must not erase the first batch's record.
    rp = OUT / "rig_report.json"
    prior = json.loads(rp.read_text()) if rp.exists() else {}
    prior.update(report)
    rp.write_text(json.dumps(prior, indent=2))
    print("\n=== SUMMARY ===")
    for k, v in report.items():
        print(f"  {k}: {'OK ' + ', '.join(v.get('clips', {})) if v.get('ok') else 'FAILED — ' + str(v.get('why'))}")
    any_ok = any(v.get("ok") for v in report.values())
    print("\nRIGGING IS " + ("AVAILABLE — verify the GLBs actually carry skins/animations."
                             if any_ok else
                             "NOT AVAILABLE for this mesh via the API. Use the procedural path."))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
