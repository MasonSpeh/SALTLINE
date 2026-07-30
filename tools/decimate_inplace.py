"""Decimate a generated mesh WITHOUT touching its transform contract.

Why this exists alongside decimate_reef.py and decimate_fish.py: both of those
NORMALISE orientation as well as reducing triangles — reef pieces get +Y-growth
with the base at y=0, fish get centred on all three axes. That is right for
decoration and for swimmers, and wrong for anything whose facing has already been
measured and pinned in CreatureAnim.FACING_OVERRIDES: re-baking the axes silently
invalidates the override and the animal walks backwards again.

So this pass only ever does two things — collapse-decimate to a triangle budget
with UVs preserved, and cap texture size. Vertex positions keep their original
frame, so the mesh drops straight into a slot whose facing and seating are already
verified.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/decimate_inplace.py -- <glb> <tri_budget> [<tex_px>]
"""
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
path = argv[0]
budget = int(argv[1])
tex_px = int(argv[2]) if len(argv) > 2 else 1024

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)

meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
before = sum(len(o.data.polygons) for o in meshes)

for o in meshes:
    tris = len(o.data.polygons)
    if tris <= 0:
        continue
    # Share the budget by the object's own share of the scene, so a multi-part
    # model does not spend it all on whichever mesh happens to be first.
    want = max(64, int(budget * (tris / float(before))))
    if tris <= want:
        continue
    m = o.modifiers.new(name="dec", type="DECIMATE")
    m.decimate_type = "COLLAPSE"
    m.ratio = want / float(tris)
    m.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=m.name)

for img in bpy.data.images:
    if img.size[0] > tex_px or img.size[1] > tex_px:
        img.scale(min(img.size[0], tex_px), min(img.size[1], tex_px))

after = sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type == "MESH")

bpy.ops.export_scene.gltf(
    filepath=path,
    export_format="GLB",
    export_apply=True,
    export_yup=True,
)
print("[decimate_inplace] %s  %d -> %d tris" % (path, before, after))
