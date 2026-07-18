#!/usr/bin/env python3
"""Batch-generate the SALTLINE bestiary with Meshy AI, in priority order.

Avatar/Pandora-style bioluminescent creature design — which is already SALTLINE canon
(the Bloom: teal/pearl glow, curious not hostile).

NOTE: Meshy's auto-rig is HUMANOID-ONLY (it runs bipedal pose estimation and returns
"Pose estimation failed" for any animal). So we generate the MESH only and animate it
in Godot with a vertex-displacement shader + procedural node motion. See
references/animating-static-meshes.md.

Resumable: skips any species whose .glb already exists. Run again to fill gaps.

  python3 gen_fauna_batch.py                 # all, priority order
  python3 gen_fauna_batch.py hammerhead seal # just these
"""
from __future__ import annotations
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from gen_animal import load_key, meshy_text_to_3d, download_glb  # noqa: E402

OUT = Path("assets/models/fauna")

STYLE = ("photoreal cinematic creature design, Avatar Pandora bioluminescent aesthetic, "
         "neutral symmetrical pose, full body, single subject, plain background, "
         "no base, no ground plane")

# (slug, prompt) in priority order — most screen time / gameplay weight first.
BESTIARY: list[tuple[str, str]] = [
    ("ultra_hammerhead",
     "a massive alien hammerhead shark, wide flat cephalofoil head with glowing teal "
     "sensory ridges along its edge, sleek muscular slate-blue body, iridescent scales, "
     "tall dorsal fin, trailing luminous fin edges, straight neutral swimming pose, " + STYLE),

    ("epic_four_eyed_whale",
     "a colossal alien whale with FOUR glowing eyes in two stacked pairs, vast smooth "
     "deep-blue body, glowing teal vein patterns tracing its flanks, long trailing "
     "pectoral fins, broad fluked tail, serene and immense, straight neutral swimming "
     "pose, " + STYLE),

    ("harbor_seal",
     "an alien seal creature, sleek wet iridescent pearl-grey fur, faint glowing teal "
     "spots across its back, large luminous curious eyes, whiskered face, streamlined "
     "body with front and rear flippers, gentle expression, neutral resting pose, " + STYLE),

    ("mantle_ray",
     "a giant alien manta ray, enormous graceful triangular wings with glowing teal "
     "edge patterns, translucent membrane showing faint internal structure, long "
     "trailing whip tail, gliding with wings spread flat and level, " + STYLE),

    ("corvid_gull",
     "an alien corvid-gull hybrid seabird, sleek dark iridescent plumage with glowing "
     "teal filaments through the wing feathers, sharp intelligent pale eyes, heavy "
     "beak, wings folded, standing upright perched neutral pose, " + STYLE),

    ("lamp_eel",
     "a long alien eel, serpentine ribbon body, a chain of glowing teal lantern organs "
     "running its full length, translucent trailing dorsal fin, small luminous eyes, "
     "stretched straight neutral pose, " + STYLE),

    ("jelly_drifter",
     "an alien jellyfish, translucent glowing teal bell with intricate luminous internal "
     "structure, long trailing glowing tentacles and frilled oral arms, drifting neutral "
     "pose bell upright, " + STYLE),
]


def main() -> None:
    key = load_key("meshy")
    wanted = set(sys.argv[1:])
    todo = [(s, p) for s, p in BESTIARY if not wanted or s in wanted]
    if not todo:
        sys.exit(f"No match. Known: {', '.join(s for s, _ in BESTIARY)}")

    done, failed = [], []
    for i, (slug, prompt) in enumerate(todo, 1):
        dest = OUT / slug / f"{slug}.glb"
        if dest.exists():
            print(f"\n[{i}/{len(todo)}] {slug}: already have it, skipping.")
            done.append(slug)
            continue
        print(f"\n{'=' * 62}\n[{i}/{len(todo)}] {slug}\n{'=' * 62}")
        try:
            task = meshy_text_to_3d(key, prompt)
            download_glb(task, dest)
            size = dest.stat().st_size / 1e6
            print(f"  ✓ {slug}  ({size:.1f} MB)")
            done.append(slug)
        except Exception as e:                      # keep the batch going
            print(f"  ✗ {slug} FAILED: {e}")
            failed.append(slug)

    print(f"\n{'=' * 62}\nDONE  {len(done)} ok, {len(failed)} failed")
    if done:
        print("  ok:     " + ", ".join(done))
    if failed:
        print("  failed: " + ", ".join(failed) + "   (re-run to retry)")
    print("\nNext: godot --headless --path . --import")


if __name__ == "__main__":
    main()
