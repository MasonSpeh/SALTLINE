#!/usr/bin/env python3
"""s36: a STRAIGHT running cat, and a jumping one.

The owner on the s35 cat: "Replace the full running stance with a better, straight
forward gait, the cat is looking/turning to the left, so the 'running straight' Is
currently crooked because cat is looking left. Also add a jumping version/animation."

That is a MESH fault, not a code fault. `cat_run`'s s34 prompt named the legs, the back
and the tail but said nothing about the HEAD or the spine's line, so the generator was
free to invent a glance — and it turned the skull and the shoulders left. No amount of
yaw on the node fixes it: rotating the body to straighten the head would then aim the
body off the line of travel. The pose has to be re-generated with the head pinned.

WHAT THIS SCRIPT INHERITS RATHER THAN RETYPES. `COAT` and `TAIL` are imported from
gen_cat_batch.py and used unmodified. The s34 docstring is emphatic about why and it is
still the rule: five separate text-to-3D rolls will not agree on a cat's markings unless
the words describing those markings are literally the same string, and a follow-cat whose
fur changes when it breaks into a run is worse than no state machine at all.

The new pose clauses follow the same house rules: the pose is described as anatomy the
animal is ALREADY IN (never as an instruction to change something — that is what
destroyed the hammerhead repeatedly), the weight is named, and the head is now named
explicitly in both, because the head is the thing that went wrong.

    python3 tools/gen_cat_s36.py [--dry-run]
"""
from __future__ import annotations
import argparse
import json
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / ".claude/skills/realistic-animals/scripts"))

from gen_animal import load_key, generate_mesh, download_model  # noqa: E402
from gen_cat_batch import COAT, TAIL  # noqa: E402  — byte-identical on purpose

OUT = REPO / "assets/models/fauna"
IDLOG = REPO / "tests/out/cat_poses/task_ids_s36.json"

# The head clause is the whole point of this batch. It is stated as where the animal IS
# looking (anatomy) rather than as "do not turn the head" (an instruction), and it names
# the spine as well — a cat that turns its shoulders is crooked even with a level skull.
STRAIGHT = (
    ", head facing straight ahead in line with the body, looking directly forward along "
    "the line of travel, neck straight, skull level, spine and shoulders square to the "
    "direction of movement, perfectly symmetrical left and right"
)

POSES: dict[str, str] = {
    # Replaces cat_run. Same gallop as s34, plus the head and the symmetry pinned.
    "cat_run2": (
        ", at full gallop mid-stride, all four legs off the ground and extended, front "
        "legs reaching forward together, hind legs driving back together, back arched, "
        "body level, tail streaming straight behind" + STRAIGHT
    ),
    # New. A cat at the top of a leap: the shape a player reads as "it jumped".
    "cat_jump": (
        ", at the peak of a leap, front legs stretched forward and together reaching for "
        "the landing, hind legs still extended back from the push-off, body stretched "
        "long and level in the air, tail streaming straight out behind for balance"
        + STRAIGHT
    ),
}


def _prompt(key: str) -> str:
    p = COAT + POSES[key] + TAIL
    # s34's own gate. Meshy truncates past ~600 and eats the trailing negatives, and
    # Tripo truncates SILENTLY at 1000 — either way the clause that dies is the one
    # fighting the plastic-toy default, because it sits at the tail.
    assert len(p) < 1000, f"{key}: {len(p)} chars"
    return p


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    for n in POSES:
        print(f"{n}: {len(_prompt(n))} chars")
    if args.dry_run:
        for n in POSES:
            print(f"\n=== {n} ===\n{_prompt(n)}")
        return 0

    key = load_key("tripo")
    IDLOG.parent.mkdir(parents=True, exist_ok=True)
    ids: dict[str, str] = json.loads(IDLOG.read_text()) if IDLOG.exists() else {}

    def one(name: str):
        return name, generate_mesh("tripo", key, prompt=_prompt(name))

    ok, bad = [], []
    with ThreadPoolExecutor(max_workers=2) as ex:
        futs = {ex.submit(one, n): n for n in POSES}
        for f in as_completed(futs):
            name = futs[f]
            try:
                n, res = f.result()
                # Log the id BEFORE the download: a dropped connection here is the single
                # most common failure in this environment and the task itself has already
                # succeeded server-side. Recover with GET /v2/openapi/task/<id>.
                ids[n] = str(res.get("id"))
                IDLOG.write_text(json.dumps(ids, indent=2))
                download_model(res, OUT / n / f"{n}.glb")
                print(f"OK   {n}")
                ok.append(n)
            except Exception as e:  # noqa: BLE001
                print(f"FAIL {name}: {e}")
                bad.append(name)
    print(f"\ndone: {len(ok)} ok, {len(bad)} failed  ({', '.join(bad) if bad else '-'})")
    print(f"task ids: {IDLOG}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
