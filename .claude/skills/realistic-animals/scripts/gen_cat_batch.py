#!/usr/bin/env python3
"""s34: the ship's cat's POSE SET — one mesh per animation state.

The cat shipped in s32 as ONE static mesh. The owner wants real states (sit, groom,
run, sleep, walk) with a model per state, driven by `ANIM.replace` swaps rather than
skeletal clips (Tripo's rigger is unverified for quadrupeds — see the skill doc).

WHY THE PROMPTS LOOK LIKE THIS — every line is scar tissue from docs/AGENT_TRAPS.md:

  * THE COAT PARAGRAPH IS BYTE-IDENTICAL ACROSS ALL FIVE. Only the POSE clause changes.
    Five separate text-to-3D rolls will not agree on a cat's markings unless the words
    describing those markings are literally the same string, and a follow-cat whose fur
    changes when it sits down is worse than no state machine at all. `COAT` is shared.
  * NAME THE BINOMIAL AND FRAME IT AS SPECIMEN / REFERENCE PHOTOGRAPHY. Highest-leverage
    line in the prompt; anchors harder than any pile of adjectives.
  * DESCRIBE THE POSE AS ANATOMY THE ANIMAL IS ALREADY IN, never as an instruction to
    change something. "Asking for a feature" deforms the model (it destroyed the
    hammerhead repeatedly).
  * NEGATE THE PLINTH AND THE TOY LOOK. Generators bed animals on rocks, and glossy
    plastic is the default failure mode.
  * UNDER 600 CHARACTERS each (asserted below) — Meshy truncates silently past it and
    eats the trailing negatives, and these want to stay re-runnable on either provider.

Task ids are logged to tests/out/cat_poses/task_ids.json AT SUBMIT TIME, because a
"FAILED" download here is usually a succeeded task whose connection dropped (traps file);
recovery is GET /v2/openapi/task/<id> and pulling data.output.pbr_model.
"""
from __future__ import annotations
import json
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from gen_animal import load_key, generate_mesh, download_model  # noqa: E402

OUT = Path("assets/models/fauna")
IDLOG = Path("tests/out/cat_poses/task_ids.json")

# ---------------------------------------------------------------- the shared cat
# Identical in every prompt. Do not "improve" it for one pose.
COAT = (
    "Felis catus, adult short-haired silver classic tabby ship's cat. Pale silver-grey "
    "fur, dark charcoal tabby swirls on the flanks, ringed tail, white chest bib, four "
    "white paws, amber-yellow eyes, pink nose, upright pointed ears"
)

TAIL = (
    ", photoreal cat reference photograph, real fur, whole body, plain background, "
    "no base, no plinth, no ground, no collar, not cartoon, not plastic, not a toy"
)

# The pose clause is the ONLY thing that varies. Each is written as a state the animal is
# already in, and each names where the weight is, because that is what the generator gets
# wrong when it is left to invent a pose.
POSES: dict[str, str] = {
    "cat_sit": (
        ", sitting upright squarely on its haunches, hind legs folded under, both front "
        "legs straight and vertical, front paws together on the ground, back straight, "
        "tail curled round the front paws, head level"
    ),
    "cat_groom": (
        ", sitting on its haunches washing itself, one hind leg raised high, body curved "
        "so the lowered head meets the lifted front paw, tongue out touching that paw, "
        "tail flat along the ground"
    ),
    "cat_run": (
        ", at full gallop mid-stride, all four legs off the ground and extended, front "
        "legs reaching forward together, hind legs driving back together, back arched, "
        "body level, tail streaming straight behind"
    ),
    "cat_sleep": (
        ", asleep curled in a tight circle lying on its side, nose tucked under the "
        "tail, all four legs folded against the belly, eyes closed, ears relaxed, a low "
        "rounded shape wider than it is tall"
    ),
    "cat_walk": (
        ", walking at a slow steady pace, body level, one front leg reaching forward and "
        "the diagonal hind leg mid-step, the other two paws flat on the ground, head up, "
        "tail held up in a relaxed curve"
    ),
}


def _prompt(key: str) -> str:
    p = COAT + POSES[key] + TAIL
    assert len(p) < 600, f"{key}: {len(p)} chars — trim it (see module docstring)"
    return p


def main() -> int:
    key = load_key("tripo")
    IDLOG.parent.mkdir(parents=True, exist_ok=True)
    ids: dict[str, str] = {}
    if IDLOG.exists():
        ids = json.loads(IDLOG.read_text())

    todo = [n for n in POSES if not (OUT / n / f"{n}.glb").exists()]
    if not todo:
        print("all cat poses already on disk")
        return 0
    print(f"submitting {len(todo)}: {', '.join(todo)}")

    def one(name: str) -> tuple[str, dict]:
        res = generate_mesh("tripo", key, prompt=_prompt(name))
        return name, res

    ok, bad = [], []
    with ThreadPoolExecutor(max_workers=5) as ex:
        futs = {ex.submit(one, n): n for n in todo}
        for f in as_completed(futs):
            name = futs[f]
            try:
                n, res = f.result()
                # Log the id BEFORE the download — a dropped connection here is the
                # single most common failure and the task itself has already succeeded.
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
