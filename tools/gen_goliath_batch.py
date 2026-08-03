#!/usr/bin/env python3
"""Three goliath grouper candidates, generated into the _reroll staging tree.

The shipping `fish_barrel_grouper` is a pre-PBR asset: one 4.2 MB colour jpg and
no normal or ORM map, which is why it reads flat next to the s31/s32 species.
The owner asked for "a perfect realistic goliath grouper texture", so all three
prompts here are TEXTURE-led and differ only in how they frame the skin:

  a_specimen  — museum specimen reference photography, the framing AGENT_TRAPS
                records as anchoring harder than any number of adjectives
  b_insitu    — an underwater wildlife photograph of a living fish, which tends
                to bring wet mucus sheen and ambient colour with it
  c_anatomy   — the pattern described as anatomy the animal already has, per the
                trap about feature-as-modification deforming the whole model

Shared, because they are the levers that have actually moved results here:
  * the binomial, first
  * shape as numeric RATIOS plus a physical simile (an oil drum)
  * the toy look negated EXPLICITLY — glassy/plastic/smooth is the default
  * "no base, no plinth, no ground" — generators bed things on rocks
  * an EXACT part count for the pattern rather than "lots of spots"

Prompts are capped at 1000 chars by Tripo, SILENTLY. Each is asserted below.

Usage:  python3 tools/gen_goliath_batch.py [--dry-run]
"""
from __future__ import annotations
import argparse
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GEN = REPO / ".claude/skills/realistic-animals/scripts/gen_animal.py"
OUT = REPO / "assets/models/fauna/_reroll"

# --- the shared shape block -------------------------------------------------
# Ratios come from the real animal and from this repo's own reading of it:
# underwater_world.gd:767 records 0.65 as "about as deep through the shoulder
# as a goliath grouper reads". Head and depth are both ~1/3 of total length.
SHAPE = (
    "A colossal barrel-bodied grouper 2.5 m long. The blunt boxy head is ONE THIRD "
    "of the total length; the body is ONE THIRD as deep as it is long and two "
    "thirds as wide through the shoulder as deep - an oil drum with fins. Small "
    "eyes set high and far forward on a broad flat forehead. Wide downturned "
    "mouth, thick lips, lower jaw jutting past the upper. Rounded fan tail, "
    "rounded paddle pectorals, one low dorsal fin. "
)

# The toy look is the DEFAULT failure mode and returns unless it is named. This
# block sits LAST on purpose and must survive the cap - hence the assert.
NEGATE = (
    "Wet living skin dulled by mucus, matte, NOT glossy, NOT plastic, NOT smooth, "
    "NOT a toy, no glassy highlights. Photoreal PBR, neutral straight swimming "
    "pose, single fish, plain background, no base, no plinth, no ground, no rock."
)

CANDIDATES = {
    "goliath_a_specimen": (
        "Epinephelus itajara, the Atlantic goliath grouper — museum ichthyology "
        "specimen reference photography, full lateral view, even studio light. "
        + SHAPE +
        "Skin tawny olive-brown, mottled, carrying EXACTLY five faint irregular "
        "dark vertical bars down the flank and a dense scatter of small dark-brown "
        "spots across head, body and every fin. " + NEGATE
    ),
    "goliath_b_insitu": (
        "Epinephelus itajara, Atlantic goliath grouper — underwater wildlife "
        "photograph of one enormous living fish, side on, natural daylight. "
        + SHAPE +
        "Mottled tawny brown and olive-green skin over a paler belly, EXACTLY five "
        "soft dark bars on the flank, small dark-brown freckling over the head, "
        "body and fins, fine rough scale grain catching the light. " + NEGATE
    ),
    "goliath_c_anatomy": (
        "Epinephelus itajara, the Atlantic goliath grouper, photoreal field-guide "
        "specimen, full lateral view. " + SHAPE +
        "As in every goliath grouper, the animal ALREADY CARRIES dense small "
        "dark-brown spots over its head, body and fins, and EXACTLY five faint "
        "dark bars stand on its tawny olive-brown flank; the skin is rough-grained "
        "and thick, paler under the jaw and belly. " + NEGATE
    ),
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)

    over = {k: len(p) for k, p in CANDIDATES.items() if len(p) > 1000}
    for name, prompt in CANDIDATES.items():
        print(f"{name}: {len(prompt)} chars" + ("  <-- OVER 1000, WILL TRUNCATE" if len(prompt) > 1000 else ""))
    if over:
        print(f"\nABORT: {len(over)} prompt(s) over Tripo's silent 1000-char cap: {over}", file=sys.stderr)
        return 2

    if args.dry_run:
        print("\n--- dry run, prompts only ---")
        for name, prompt in CANDIDATES.items():
            print(f"\n=== {name} ===\n{prompt}")
        return 0

    procs = []
    for name, prompt in CANDIDATES.items():
        log = OUT / f"{name}.log"
        cmd = [sys.executable, str(GEN), "--name", name, "--prompt", prompt, "--out", str(OUT)]
        print(f"submitting {name} -> {log}")
        with open(log, "w") as fh:
            procs.append((name, subprocess.Popen(cmd, cwd=REPO, stdout=fh, stderr=subprocess.STDOUT)))

    rc = 0
    for name, p in procs:
        code = p.wait()
        print(f"{name}: exit {code}")
        if code != 0:
            rc = 1
    # A non-zero exit is usually a DROPPED POLL, not a failed task — the trap file
    # is explicit that the task keeps running server-side. Recover by task id from
    # the log rather than regenerating, which pays twice.
    print("\nIf any exited non-zero, recover the task id from its .log and pull "
          "data.output.pbr_model via GET /v2/openapi/task/<id> — do NOT regenerate.")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
