"""Decimate the generated tropical reef fish for bulk instancing.

Tripo returns ~500,000 triangles per mesh with 2048^2 PBR maps. These fish are
instanced 1-16 times per station across ~42 stations (187 animals), so the raw
meshes would cost ~93M triangles against a reef that costs 3.1M. This is the
same COLLAPSE pass tools/decimate_reef.py runs on the coral, with two deliberate
differences:

1. FAR SMALLER BUDGETS. A coral head is 0.35-1.95 m and fills the frame when you
   swim up to it; a staghorn IS its geometry, which is why it earns 8,000
   triangles. A reef fish is 0.12-0.46 m seen from 1-10 m through a fog grade
   that runs 0.028-0.2/m, and its identity is a COLOUR and an OVAL — both carried
   entirely by the albedo map and the outline, neither of which a collapse
   decimation touches. Budgets below are set by what the silhouette needs:
   1,200 for the small round bodies that are placed in the largest numbers,
   1,600 for the disc-shaped tangs and butterflyfish, 2,200 for the three big
   species whose trailing fins and beak/snout profile ARE the recognition cue.

2. NO ORIENTATION NORMALISATION. decimate_reef.py drops each piece's base onto
   y = 0 because a coral is SEATED on a wall. A swimmer is not: CreatureAnim
   scales, rotates and drives every generated animal about the CENTRE of its own
   bounding box (see CreatureAnim.ground / belly — the whole reason those helpers
   exist is that generated meshes arrive centred and walkers have to be lifted).
   Seating a fish's base on zero would put its pivot at its belly, so every
   look_at would swing it about its underside. So this pass centres on all three
   axes and leaves facing to CreatureAnim's FACING table, which is measured per
   model rather than baked.

Raw downloads stay in _cand9/ untouched, so a different ratio can be redone free.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/decimate_fish.py -- <src_root> <dst_root>
"""
import os
import sys

import bpy
import mathutils

# slug -> triangle budget. See the module docstring for how these were chosen.
SMALL = 1200      # placed in the largest numbers; a fleck of colour at any real distance
DISC = 1600       # tall flat bodies — the outline is a disc, cheap to hold
BIG = 2200        # trailing fins, beaks and snouts: the silhouette carries the species
BUDGET = {
    "trop_clown": SMALL,
    "trop_damsel": SMALL,
    "trop_anthias": SMALL,
    "trop_wrasse": SMALL,
    "trop_yellow_tang": DISC,
    "trop_blue_tang": DISC,
    "trop_butterfly": DISC,
    "trop_angel": BIG,
    "trop_parrot": BIG,
    "trop_triggerfish": BIG,
}
# The colour IS the fish here — every one of these species is identified by its
# pattern, not its shape — so the albedo map keeps more resolution than the coral
# pass gave its pieces relative to the geometry it survives on.
MAX_TEX = 1024

# Blender's glTF importer converts Y-up to Z-up, so inside Blender
#     blender = (gltf.x, -gltf.z, gltf.y)
# Named once here; nothing below is allowed to hard-code an axis index again.
# (A first pass of the coral tool normalised Blender's Y believing it was glTF's,
# and printed entirely plausible numbers while doing it — docs/AGENT_TRAPS.md.)
GLTF_UP = 2       # glTF +Y == Blender +Z


def wipe():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def one(slug, target, src_root, dst_root):
    src = os.path.join(src_root, slug, slug + ".glb")
    if not os.path.exists(src):
        print("[fish] MISSING %s" % src)
        return None
    wipe()
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        print("[fish] %s: no mesh" % slug)
        return None

    bpy.ops.object.select_all(action="DESELECT")
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active

    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    before = len(ob.data.polygons)

    mod = ob.modifiers.new("dec", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.use_collapse_triangulate = True
    mod.ratio = min(1.0, float(target) / max(1, before))
    bpy.ops.object.modifier_apply(modifier=mod.name)
    after = len(ob.data.polygons)

    # Centre on ALL THREE axes — see the docstring. Written straight onto the mesh
    # data: bpy.ops.object.transform_apply is a silent no-op when the context is
    # not what it expects, and modifier_apply has just disturbed that context.
    vs = [v.co for v in ob.data.vertices]
    lo = [min(v[i] for v in vs) for i in range(3)]
    hi = [max(v[i] for v in vs) for i in range(3)]
    off = [-(lo[i] + hi[i]) * 0.5 for i in range(3)]
    ob.data.transform(mathutils.Matrix.Translation(off))
    vs = [v.co for v in ob.data.vertices]
    lo = [min(v[i] for v in vs) for i in range(3)]
    hi = [max(v[i] for v in vs) for i in range(3)]
    for i in range(3):
        assert abs(lo[i] + hi[i]) < 1e-5, "%s: axis %d not centred" % (slug, i)

    tex = []
    for img in bpy.data.images:
        if img.size[0] > MAX_TEX or img.size[1] > MAX_TEX:
            w, h = img.size
            s = MAX_TEX / float(max(w, h))
            img.scale(max(1, int(w * s)), max(1, int(h * s)))
        if img.size[0]:
            tex.append("%dx%d" % (img.size[0], img.size[1]))

    outdir = os.path.join(dst_root, slug)
    os.makedirs(outdir, exist_ok=True)
    dst = os.path.join(outdir, slug + ".glb")
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB",
                              use_selection=False, export_yup=True,
                              export_apply=True)
    size = [hi[i] - lo[i] for i in range(3)]
    # Aspect is printed because it is the cheapest check that a fish is a fish:
    # a reef fish is roughly 2-3x longer than deep and thin across.
    print("[fish] %-18s %6d -> %5d tris  ext(x %.2f  y %.2f  z %.2f)  tex %s  %.0f KB"
          % (slug, before, after, size[0], size[GLTF_UP], size[1],
             ",".join(sorted(set(tex))), os.path.getsize(dst) / 1024.0))
    return after


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    src_root = argv[0]
    dst_root = argv[1]
    only = set(argv[2:])
    total = 0
    n = 0
    for slug, target in BUDGET.items():
        if only and slug not in only:
            continue
        got = one(slug, target, src_root, dst_root)
        if got:
            total += got
            n += 1
    print("[fish] TOTAL %d tris across %d species" % (total, n))


main()
