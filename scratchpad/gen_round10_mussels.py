#!/usr/bin/env python3
"""Round 10 — MUSSELS (owner brief s21): harvestable mussel clusters on the leg coral.

TWO DIFFERENT ASSETS, deliberately:
  * mussel_bed_* / mussel_clump_*  -> the REEF cluster. Wide, low, encrusting. Placed in
    bulk on a caisson face through leg_reef's MultiMesh, decimated with
    tools/decimate_reef.py (base seated at y=0, +Y = growth).
  * mussels_hand_* / mussels_boiled -> the INVENTORY item, seen at 96 px in the pack.
    Compact, one clear silhouette, decimated with tools/decimate_fish.py (pivot centred
    on all three axes, which is what a held/previewed item wants).

Task ids are LOGGED AT SUBMIT (docs/AGENT_TRAPS.md: a "FAILED" download is usually a
task that succeeded server-side; recover with GET /v2/openapi/task/<id> and pull
data.output.pbr_model rather than paying twice).

    python3 scratchpad/gen_round10_mussels.py [slug ...]
"""
from __future__ import annotations
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parents[1]
                      / ".claude/skills/realistic-animals/scripts"))
from gen_animal import load_key, _tripo_json_headers, _tripo_raise, _tripo_task_id, \
    _tripo_poll, _tripo_glb_url, download_url  # noqa: E402

TRIPO = "https://api.tripo3d.ai/v2/openapi"
OUT = Path("assets/models/fauna/_cand10")
IDS = Path("scratchpad/round10_task_ids.json")

# Shared negations. Every one of these is a documented failure mode of this pipeline.
NO_BASE = (" Just the mussels themselves and nothing else: no rock, no stone, no base, "
           "no plinth, no ground plane, no pedestal, nothing underneath. "
           "Matte wet biological shell, not glossy plastic, not a smooth glassy toy.")
SPECIMEN = ("Marine biology specimen reference photography of "
            "Mytilus edulis, the common blue mussel. ")

JOBS: dict[str, str] = {
    # ------------------------------------------------------------------ reef clusters
    # A mussel bed is the flattest thing on a reef: the brief calls for "a low encrusting
    # mat, near-zero tilt, flush to the face". So the ratio is stated numerically and
    # given a physical simile, per docs/AGENT_TRAPS.md.
    "mussel_bed_a":
        SPECIMEN + "A dense wild MUSSEL BED: about thirty adult blue mussels wedged "
        "together edge to edge into one continuous encrusting crust. Each shell is a "
        "closed teardrop wedge, blue-black shading to violet with fine concentric growth "
        "rings, the narrow hinge end buried in the bed and the broad end angled up. The "
        "whole patch is a MAT ten times wider than it is deep, like a single cobblestone "
        "paving slab, with no mound in the middle." + NO_BASE,
    "mussel_bed_b":
        SPECIMEN + "A MUSSEL CLUMP of about fourteen adult blue mussels packed into a "
        "rosette, every shell's pointed hinge end meeting at the centre and the broad "
        "rounded ends fanning outward and slightly upward like the petals of an artichoke. "
        "Glossy blue-black shells with brown-gold growth banding near the lips, a few "
        "gaping a millimetre open. Four times wider than tall, a low dome." + NO_BASE,
    "mussel_bed_c":
        SPECIMEN + "A ragged patch of about twenty-two blue mussels of MIXED SIZES — a "
        "dozen large adults with six or seven tiny juveniles crowded in the gaps between "
        "them — matted together with fine brown byssal threads. Irregular outline with "
        "bays and gaps rather than a neat disc; shells encrusted and worn, blue-black with "
        "chalky white barnacle scars. Flat, eight times wider than deep." + NO_BASE,
    "mussel_clump_d":
        SPECIMEN + "A tight BUNCH of about sixteen blue mussels bound together in a "
        "knuckle-shaped clump, shells all lying roughly parallel and overlapping like "
        "roof slates, the whole bunch as long as three shells and as thick as two. Deep "
        "indigo-black shells with pearly worn patches at the tips, visible tangle of "
        "byssus threads binding them." + NO_BASE,
    # ------------------------------------------------------------------ the pack item
    # Seen at 96 px: ONE clear silhouette, not filigree.
    "mussels_hand_a":
        SPECIMEN + "A HANDFUL of five closed adult blue mussels heaped loosely together, "
        "as if just picked. Each is an unmistakable teardrop wedge shell, blue-black with "
        "violet sheen and clear concentric growth rings; they rest against each other at "
        "different angles so the outline of the heap reads as five separate shells. "
        "Simple, bold, uncluttered shapes." + NO_BASE,
    "mussels_hand_b":
        SPECIMEN + "A small BUNCH of four closed adult blue mussels, hinge ends together "
        "and broad ends splayed apart in a fan, one short strand of brown byssal thread "
        "trailing. Shells wet blue-black with a pale wear scar on each. One clear compact "
        "silhouette, bold simple shapes, no fine detail." + NO_BASE,
    "mussels_boiled":
        SPECIMEN + "Four COOKED mussels, each shell hinged wide OPEN like a butterfly, "
        "the two halves flat apart to show pale nacreous mother-of-pearl inside and a "
        "plump cooked orange-cream mussel meat sitting in one half of each. Outer shells "
        "blue-black, steaming hot, wet. Heaped loosely together, one clear compact "
        "silhouette." + NO_BASE,
}


def submit(slug: str, prompt: str, key: str) -> str:
    body = {"type": "text_to_model", "prompt": prompt[:1000], "texture": True, "pbr": True}
    r = requests.post(f"{TRIPO}/task", headers=_tripo_json_headers(key), json=body, timeout=60)
    _tripo_raise(r, f"text_to_model:{slug}")
    tid = _tripo_task_id(r.json())
    # LOG BEFORE POLLING — this line is the whole point of the file.
    print(f"  SUBMIT {slug} -> task {tid}", flush=True)
    ids = json.loads(IDS.read_text()) if IDS.exists() else {}
    ids[slug] = tid
    IDS.parent.mkdir(parents=True, exist_ok=True)
    IDS.write_text(json.dumps(ids, indent=2))
    return tid


def one(slug: str, prompt: str, key: str) -> tuple[str, str]:
    dest = OUT / slug / f"{slug}.glb"
    if dest.exists():
        return slug, "skip (exists)"
    try:
        tid = submit(slug, prompt, key)
    except Exception as e:  # noqa: BLE001
        return slug, f"FAILED at submit: {e}"
    for attempt in range(4):
        try:
            task = _tripo_poll(tid, key, slug)
            url = _tripo_glb_url(task)
            if not url:
                return slug, f"FAILED: no pbr_model on task {tid}"
            download_url(url, dest)
            return slug, f"ok ({dest.stat().st_size / 1e6:.1f} MB) task {tid}"
        except Exception as e:  # noqa: BLE001
            print(f"  {slug}: poll/download dropped ({e}) — retrying task {tid}", flush=True)
            time.sleep(10)
    return slug, f"FAILED after retries — task {tid} may have SUCCEEDED, recover it"


def main() -> None:
    key = load_key("tripo")
    only = set(sys.argv[1:])
    jobs = {s: p for s, p in JOBS.items() if not only or s in only}
    print(f"{len(jobs)} mussel generations ({len(jobs) * 20} credits), 4 concurrent")
    ok, bad = [], []
    with ThreadPoolExecutor(max_workers=4) as pool:
        futs = {pool.submit(one, s, p, key): s for s, p in jobs.items()}
        for fut in as_completed(futs):
            slug, status = fut.result()
            print(f"  {slug}: {status}", flush=True)
            (bad if "FAILED" in status else ok).append(slug)
    print(f"\nDONE  {len(ok)} ok, {len(bad)} failed")
    print(f"task ids -> {IDS}")


if __name__ == "__main__":
    main()
