#!/usr/bin/env python3
"""Extract each rigged cat pose as PER-BONE LOCAL ROTATIONS, for the blend system.

WHY THIS WORKS. Every rigged cat GLB was auto-rigged by Tripo with the SAME 41-bone
humanoid template — identical bone NAMES, near-identical joint conventions, different
rest poses (each mesh is the cat in a different stance, and the rig is fitted to it).
A bone's local rest rotation IS the pose: apply the sit mesh's local rotations to the
standing mesh's skeleton and the standing cat sits, to the accuracy that the two
auto-rig fits agree. That accuracy is an empirical question and is settled by RENDERING
(tests/CatBlendShot.tscn), not assumed here.

The Hip's local TRANSLATION is also captured, relative to the donor's own Root->Hip
offset, because a sitting cat's pelvis is lower than a standing one's and rotation alone
cannot express that.

Output: assets/models/fauna/_rigged/cat_poses.json
  { "poses": { "<name>": { "bones": { "<bone>": [x,y,z,w] }, "hip_t": [x,y,z] } },
    "bone_names": [...], "base": "cat_stand_idle" }

Coordinate note: glTF quaternions are (x,y,z,w) and so is Godot's Quaternion
constructor. glTF and Godot are both right-handed Y-up; the importer does not re-express
node-local TRS, so these transfer verbatim.

    python3 tools/extract_cat_poses.py
"""
from __future__ import annotations
import json
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RIGGED = REPO / "assets/models/fauna/_rigged"
OUT = RIGGED / "cat_poses.json"

# pose name the game uses -> the rigged GLB that DONATES it. The base (stand) is listed
# too: extracting it proves the bone-name sets match and gives the blender its rest.
DONORS = {
    "stand": "cat_stand_idle.glb",
    "sit": "cat_sit_idle.glb",
    "groom": "cat_groom_idle.glb",
    "walk": "cat_walk_walk.glb",
    "run": "cat_run2_run.glb",
    "jump": "cat_jump_jump.glb",
    "sleep": "cat_sleep_idle.glb",
}


def glb_json(path: Path) -> dict:
    with open(path, "rb") as fh:
        magic, ver, length = struct.unpack("<III", fh.read(12))
        assert magic == 0x46546C67, f"{path} is not a GLB"
        clen, ctype = struct.unpack("<II", fh.read(8))
        return json.loads(fh.read(clen).decode("utf-8"))


def extract(path: Path) -> tuple[dict, list, list]:
    j = glb_json(path)
    skin = j["skins"][0]
    nodes = j["nodes"]
    names = [nodes[i].get("name", f"bone{i}") for i in skin["joints"]]
    bones: dict[str, list] = {}
    hip_t = [0.0, 0.0, 0.0]
    for i in skin["joints"]:
        n = nodes[i]
        name = n.get("name", f"bone{i}")
        # A missing rotation is identity — glTF omits default TRS components.
        bones[name] = n.get("rotation", [0.0, 0.0, 0.0, 1.0])
        if name == "Hip":
            hip_t = n.get("translation", [0.0, 0.0, 0.0])
    return bones, names, hip_t


def main() -> int:
    poses = {}
    name_sets = {}
    for pose, fname in DONORS.items():
        p = RIGGED / fname
        if not p.exists():
            print(f"MISSING {pose}: {fname} — skipped (the blender falls back to FK)")
            continue
        bones, names, hip_t = extract(p)
        poses[pose] = {"bones": bones, "hip_t": hip_t}
        name_sets[pose] = names
        print(f"{pose:8s} {fname:26s} {len(bones)} bones")

    # THE TRANSFER ONLY WORKS IF THE SKELETONS MATCH. Assert it rather than hope: every
    # donor must carry exactly the base's bone set, or the differing bones are silently
    # left at rest and the pose arrives half-applied.
    if "stand" in name_sets:
        base = set(name_sets["stand"])
        ok = True
        for pose, names in name_sets.items():
            missing = base - set(names)
            extra = set(names) - base
            if missing or extra:
                print(f"MISMATCH {pose}: missing={sorted(missing)} extra={sorted(extra)}")
                ok = False
        if not ok:
            return 1
        print(f"bone sets identical across {len(name_sets)} poses ({len(base)} bones)")

    OUT.write_text(json.dumps({
        "base": "cat_stand_idle",
        "bone_names": name_sets.get("stand", []),
        "poses": poses,
    }, indent=1))
    print(f"-> {OUT.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
