#!/usr/bin/env python3
"""Round 10b — the REEF BED, after round 10 lost all four bed candidates on the render.

WHAT ROUND 10 GOT WRONG, measured off the CandShot frames at the shipping ratio:
  * TOO MANY SHELLS. Asking for 22-30 mussels puts ~30 separate closed hard bumps in one
    piece; at 4,200 tris that is ~140 triangles a shell, and a shell needs a few hundred
    to stay closed. Every bed came back as the "pile of broken glass" the traps file
    describes. So: EIGHT to TWELVE big shells, not thirty small ones.
  * NOT ACTUALLY FLAT. mussel_bed_a measured 1.03/1.01/1.03 on its three axes and
    mussel_clump_d 0.97/0.97/0.99 — the same radially-symmetric-ball signature that got
    barnacle_goose rejected in s20. "Ten times wider than deep" did not survive; the
    ratio is now attached to the individual shells' POSE (all lying on their sides in one
    layer) rather than to the patch as an abstraction.
  * COBALT GEMSTONE. Every candidate came back saturated royal blue with a glassy
    specular — the documented plastic-toy default. Named and negated explicitly.

    python3 scratchpad/gen_round10b_beds.py [slug ...]
"""
from __future__ import annotations
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_round10_mussels import OUT, main as _main  # noqa: E402,F401
import gen_round10_mussels as r10  # noqa: E402

NO_BASE = (" Just the mussels themselves and nothing else: no rock, no stone, no base, "
           "no plinth, no ground plane, no pedestal, nothing underneath. Shells are MATTE "
           "and DARK — blue-black, olive-black, weathered, chalky where worn. Not shiny "
           "royal blue, not glassy, not translucent, not a polished gemstone, not plastic.")
SPECIMEN = ("Marine biology specimen reference photography of "
            "Mytilus edulis, the common blue mussel. ")

BEDS: dict[str, str] = {
    "mussel_bed_e":
        SPECIMEN + "EXACTLY NINE large adult mussels, each one a big closed teardrop wedge "
        "shell about as long as a thumb, all NINE lying down flat on their SIDES in a "
        "single overlapping layer like fallen dominoes, pointing outward in different "
        "directions from a loose centre. Only nine shells, each one large and clearly "
        "separate with a visible gap of shadow between it and its neighbours. The layer is "
        "ONE SHELL THICK — as thin as a stack of two coins is to a saucer." + NO_BASE,
    "mussel_bed_f":
        SPECIMEN + "EXACTLY TWELVE large adult mussels crowded shoulder to shoulder into a "
        "low bank, every shell standing on its narrow hinge end and leaning outward, broad "
        "rounded lips uppermost, like a dozen cobbles set on edge in a single row two "
        "shells deep. Only twelve shells, each large and individually readable, with "
        "shadowed gaps between them. The bank is three times wider than it is tall — a "
        "kerb, not a mound." + NO_BASE,
}

if __name__ == "__main__":
    r10.JOBS = BEDS
    r10.IDS = Path("scratchpad/round10b_task_ids.json")
    sys.argv = [sys.argv[0]] + sys.argv[1:]
    r10.main()
