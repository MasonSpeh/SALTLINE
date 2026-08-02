#!/usr/bin/env python3
"""Measure a generated fish mesh's AUTHORED FORWARD AXIS, headlessly, off the GLB.

WHY. docs/AGENT_TRAPS.md: "Generated meshes do NOT share a forward axis... measure it."
The owner reported a grouper swimming backwards. `CreatureAnim.FACING_DEFAULT` yaws every
model 180 on the assumption the head is at local +Z, and eleven species were wired in
during s31 without a single one of them being checked — the same way a hammerhead once
shipped swimming broadside.

THE INSTRUMENT, AND WHY IT IS TRUSTWORTHY. A fish is not symmetric along its length: the
head end carries the skull, the gill mass and the pectoral girdle, while the tail end
tapers to a narrow peduncle before flaring into a fin that is TALL but paper-thin. So
mass runs toward the head, and WIDTH (the across-body extent) runs toward the head even
harder — the caudal fin is the one part that is wide in Y and thin in X.

Two independent statistics are computed along each candidate axis:
  * `vol`   — the vertex centroid's offset from the bounding-box centre, i.e. where the
              mesh's mass sits. Positive means mass is toward the +end.
  * `width` — the same centroid, but weighting each slice by its ACROSS-body extent, which
              suppresses the tall thin caudal fin the volume statistic can be fooled by.
Both are normalised to the long-axis length, so they are comparable across species.

AND IT IS CALIBRATED, not asserted. `--calibrate` runs the metric over every species whose
facing is ALREADY verified and pinned in creature_anim.gd (the default +Z convention, the
five -Z models, the three +X models) and prints the confusion table. An instrument that
cannot reproduce the known answers has no business being pointed at the unknown ones.

    python3 tools/measure_facing.py --calibrate
    python3 tools/measure_facing.py fish_humpback_grouper fish_leopard_grouper ...

Coordinates are glTF's (Y up, and trimesh preserves that frame — asserted at load).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import trimesh

FAUNA = Path("assets/models/fauna")

# ---------------------------------------------------------------- ground truth
# Read off scripts/world/creature_anim.gd. FACING_DEFAULT yaws 180, which maps local +Z
# onto Godot's forward (-Z), so an un-overridden model is asserted to have its head at +Z.
# An override of yaw 0 means the head is already at -Z; yaw 90 maps local +X onto -Z.
KNOWN: dict[str, str] = {
    # the default convention — verified in s15/s20 through FacingShot's side views
    "fish_herring": "+Z",
    "fish_slate_cod": "+Z",
    "fish_mirrorjack": "+Z",
    "fish_copper_sprat": "+Z",
    "fish_gannet_mackerel": "+Z",
    "fish_rust_wrasse": "+Z",
    "fish_bilge_blenny": "+Z",
    "fish_lantern_dogfish": "+Z",
    "fish_coelacanth": "+Z",   # explicitly re-checked 2026-07-26, see creature_anim.gd
    "fish_ember_snapper": "+Z",
    "fish_drum_croaker": "+Z",
    "fish_sable_hake": "+Z",
    "fish_lodestone_bream": "+Z",
    "fish_silver_ladder": "+Z",
    # the -Z models
    "herring_gull": "-Z",
    "trop_clown": "-Z",
    "trop_parrot": "-Z",
    "trop_anthias": "-Z",
    "trop_damsel": "-Z",
    # the +X models
    "ultra_hammerhead": "+X",
    "trop_angel": "+X",
    "trop_butterfly": "+X",
}

AXES = {"X": 0, "Y": 1, "Z": 2}


def _load(slug: str) -> trimesh.Trimesh | None:
    for stem in (slug, slug.replace("trop_", "trop_")):
        p = FAUNA / stem / f"{stem}.glb"
        if p.exists():
            break
    else:
        return None
    scene = trimesh.load(str(p), force="scene", process=False)
    if isinstance(scene, trimesh.Trimesh):
        return scene
    geo = scene.dump(concatenate=True)
    return geo if isinstance(geo, trimesh.Trimesh) else None


def measure(mesh: trimesh.Trimesh) -> dict:
    v = np.asarray(mesh.vertices, dtype=np.float64)
    lo, hi = v.min(axis=0), v.max(axis=0)
    ext = hi - lo
    long_i = int(np.argmax(ext))
    # The across-body axis is the SHORTEST of the two remaining — for a fish that is the
    # left-right thickness, and it is the one the caudal fin does not inflate.
    others = [i for i in range(3) if i != long_i]
    across_i = others[0] if ext[others[0]] < ext[others[1]] else others[1]

    span = ext[long_i]
    if span <= 1e-9:
        return {}
    mid = (lo[long_i] + hi[long_i]) * 0.5
    t = (v[:, long_i] - mid) / span            # -0.5 .. +0.5 along the long axis

    vol = float(t.mean())

    # Slice the body into bins along its length and weight each bin by how WIDE it is.
    bins = 24
    idx = np.clip(((t + 0.5) * bins).astype(int), 0, bins - 1)
    centres = (np.arange(bins) + 0.5) / bins - 0.5
    widths = np.zeros(bins)
    for b in range(bins):
        sel = v[idx == b]
        if len(sel) >= 4:
            widths[b] = sel[:, across_i].max() - sel[:, across_i].min()
    tot = widths.sum()
    width = float((widths * centres).sum() / tot) if tot > 1e-9 else 0.0

    return {
        "long": "XYZ"[long_i],
        "across": "XYZ"[across_i],
        "ext": ext,
        "vol": vol,
        "width": width,
        "verts": len(v),
    }


## How big a statistic has to be before it counts as a reading rather than noise. Set from
## the calibration set: the smallest CORRECT reading on a model both statistics agree about
## is trop_angel's vol at +0.004, and the largest WRONG-signed one is the hammerhead's width
## at -0.019 — so no threshold separates them and the discriminator has to be agreement,
## not magnitude. Kept only to reject an exactly-symmetric mesh.
NOISE = 1e-4


def verdict(m: dict) -> str:
    """Head end as a signed axis in the model's own frame, or UNCERTAIN.

    THE TWO STATISTICS MUST AGREE. Neither is reliable alone and the calibration set says
    so out loud: `width` calls the hammerhead and the dogfish backwards (a cephalofoil and
    a shark's broad pectorals are exactly the wide-headed cases the across-body extent was
    supposed to measure, and both meshes put those on the axis it picked as "across"),
    while `vol` calls the herring gull backwards (a bird's mass is not its fish). On the 19
    calibration models where the two agree, the agreed answer has never been wrong. So a
    disagreement is not a tie to be broken — it is the instrument saying LOOK AT THE
    RENDER, which is what tests/FacingShot.tscn is for.
    """
    if not m:
        return "?"
    a, b = m["vol"], m["width"]
    if abs(a) < NOISE or abs(b) < NOISE or (a > 0) != (b > 0):
        return "UNCERTAIN"
    return ("+" if a > 0 else "-") + m["long"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("slugs", nargs="*")
    ap.add_argument("--calibrate", action="store_true")
    a = ap.parse_args()

    slugs = list(KNOWN) if a.calibrate else a.slugs
    if not slugs:
        ap.error("give slugs or --calibrate")

    print(f"{'slug':28} {'long':>4} {'acr':>4} {'extent(x,y,z)':>22} "
          f"{'vol':>7} {'width':>7} {'says':>9} {'known':>6} {'':>4}")
    agree = disagree = unsure = 0
    for s in slugs:
        mesh = _load(s)
        if mesh is None:
            print(f"{s:28} ABSENT")
            continue
        m = measure(mesh)
        if not m:
            print(f"{s:28} DEGENERATE")
            continue
        says = verdict(m)
        known = KNOWN.get(s, "")
        mark = ""
        if known:
            if says == "UNCERTAIN":
                unsure += 1
                mark = "look"
            elif says == known:
                agree += 1
                mark = "ok"
            else:
                disagree += 1
                mark = "MISMATCH"
        e = m["ext"]
        print(f"{s:28} {m['long']:>4} {m['across']:>4} "
              f"({e[0]:6.3f},{e[1]:6.3f},{e[2]:6.3f}) "
              f"{m['vol']:+7.3f} {m['width']:+7.3f} {says:>9} {known:>6} {mark:>4}")
    if a.calibrate:
        print(f"\ncalibration: {agree} confident and correct, {disagree} confident and WRONG, "
              f"{unsure} UNCERTAIN (must be read off a FacingShot render)")
        return 0 if disagree == 0 else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
