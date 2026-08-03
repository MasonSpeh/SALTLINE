"""Decimate + normalise the generated reef meshes for bulk placement.

Tripo returns ~500,000 triangles per mesh with 2048^2 PBR maps. These pieces are
DECORATION instanced hundreds of times down the caisson legs, so raw meshes would
cost more than the whole rig. This matches the pass s17 used on the 34 item meshes:
COLLAPSE-decimate to 8,000 tris with UVs preserved, cap every texture at 1024.

It also NORMALISES orientation, which the item pass did not need. Generated meshes
do not share an axis convention (docs/AGENT_TRAPS.md) — measured here, star_small
and star_huge arrive with their disc normal on +X and coral_fan_a's blade plane on
+X. Baking the correction into the GLB gives every reef piece one contract:

    +Y is the growth / outward direction, the base sits at y = 0, XZ is centred.

so the placement code can point a host's +Y along a probed surface normal and be
done, instead of carrying eleven special cases in GDScript.

Raw downloads stay in _cand8/ and _cand9/ untouched, so a different ratio can be redone
free — which s20 did, re-cutting every s19 coral one notch leaner to pay for twice as
many instances.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/decimate_reef.py -- <src_root>[,<src_root>...] <dst_root> \
        [<slug>,<slug>,...]

src_root is a search path (first root holding the slug wins), so one run can pull the
s19 pieces from _cand8 and the s20 ones from _cand9. The trailing slug list overrides
KEEP, for re-cutting one piece without redoing the set.
"""
import math
import os
import sys

import bpy
import mathutils

# Budget is instances x tris, not tris — these are placed in bulk, so the count that
# matters is what a leg's whole colony costs. Corals get the s17 item budget (8k); the
# starfish get less because they are flat discs 0.3-0.9 m across whose entire surface
# detail is tubercles carried by the normal map, and 60-odd of them at 8k would cost
# more than the coral does.
TARGET_TRIS = 8000
# Spent where it shows. A brain or bubble coral is a blob whose entire surface detail
# is carried by the normal map, so triangles buy almost nothing on it; a staghorn or a
# sea fan IS its silhouette, and triangles buy all of it. Judged from the CandShot
# renders at 8k, not assumed.
#
# s20 RE-CUT. The reef roughly doubled in instance count (sponges, barnacles, reef
# masses, four big starfish, and more coral), so the per-piece budgets that were right
# for 560 instances are not right for 1,100. Every coral came down one notch and was
# re-judged at the new ratio in tests/CandShot.tscn before it shipped; a 1 m coral seen
# through the fog grade at y -15 does not spend 8,000 triangles usefully. The pieces
# that went UP are the reef MASSES, which are four growth forms fused into one host and
# carry a whole colony's silhouette on their own.
TARGET_OVERRIDE = {
    "star_small": 2000, "star_mid": 2000, "star_huge": 2600,
    "coral_brain": 5000, "coral_bubble": 4000, "coral_plate": 5000,
    "coral_branch_a": 5000, "coral_branch_b": 4000, "coral_fan_a": 6000,
    # s20 — the structural anchors. Several growth forms in one piece, placed at the
    # heart of a colony with singles scattered around them: real reef is a continuous
    # crust, not ornaments hung on a wall.
    "reefmass_a": 7000, "reefmass_b": 7000, "reefmass_c": 7000, "reefmass_d": 7000,
    # Sponges are smooth-walled tubes and sheets — silhouette matters, surface does not.
    "sponge_barrel": 3000, "sponge_tube_cluster": 3600, "sponge_rope": 3600,
    "sponge_fan": 3000,
    # Barnacle crusts are the highest-count, lowest-read pieces in the set: a patch of
    # chalky cones 15-40 cm across, used to fill bare concrete. Cheapest budget here.
    "barnacle_cluster_a": 4000, "barnacle_goose": 2000, "barnacle_giant": 1400,
    # The big starfish are meant to be PROMINENT (owner call) — 0.8-1.7 m, and the arm
    # silhouette is the whole animal, so they get more than the small ones.
    "star_big_red": 3000, "star_big_blue": 2600, "star_big_spiny": 3400,
    "star_big_sunflower": 3600,
    # s21 — MUSSEL BEDS. These are the one thing on the reef the player takes APART, so
    # unlike the barnacle crust they get walked right up to and looked at from 1 m.
    # A mussel bed is also exactly the surface type the traps file warns about (a dense
    # field of small hard bumps — thirty separate shells), so it does NOT get the crust's
    # 1.4-4k: below ~4k the individual shells stop closing and the bed reads as gravel.
    # The clump is the small accent scattered around a bed and can take half of that.
    "mussel_bed_a": 4200, "mussel_bed_b": 4200, "mussel_bed_c": 4200,
    "mussel_clump_d": 2200,
    "mussel_clump": 3000, "mussel_bed_e": 4200, "mussel_bed_f": 4200,
    # s34 — THE WALL FLORA, re-cut out of assets/models/fauna (28,844 / 29,778 / 30,745 tris
    # raw). They arrive from the FAUNA set, where a mesh is one animal drawn once and 30k is
    # fine; on the wall they are placed in the hundreds. See the traps file, "GENERATED FLORA
    # IS NOT REEF-BUDGET FLORA".
    #
    # s35 — THEY ARE THE MOST EXPENSIVE PIECES IN THE REEF AND THE LEAST SEEN, AND THIS IS
    # THE OPEN LEVER. At 8,000 they are joint-dearest with the reef masses, and the s34 build
    # placed 363 of them: 2.90 M triangles, 23% of the whole 12.55 M reef, on 0.3-1.05 m
    # plants of which three quarters were below the 13 m death line. s35 cut the count and
    # moved them up the band, which is most of the answer — but a re-cut to 4,000 would take
    # another ~1.1 M off what remains, and these are the right SHAPE for it: smooth blades and
    # vines, not the dense field of small hard bumps that made the mussel beds shatter below
    # 4k. It is deliberately NOT taken here, because it cannot be judged without a render:
    #     /Applications/Blender.app/Contents/MacOS/Blender --background \
    #         --python tools/decimate_reef.py -- assets/models/fauna \
    #         assets/models/fauna/reef bloom_sea_grass,glow_creeper,bloom_anemone
    # then re-import and look at it in tests/CandShot.tscn at the shipping ratio before
    # believing it. The .import sidecars for these three already exist and already carry
    # compress/mode=2 + size_limit=1024, so re-writing the JPGs does NOT re-fire the headless
    # texture trap — that one only bites files Godot has never seen.
    "bloom_sea_grass": 8000, "glow_creeper": 8000, "bloom_anemone": 8000,
}
MAX_TEX = 1024

# AXES — the one thing that has to be right in this file.
# Blender's glTF importer converts Y-up to Z-up, so everything inside Blender is
#     blender = (gltf.x, -gltf.z, gltf.y)      gltf = (blender.x, blender.z, -blender.y)
# i.e. the growth axis we want to normalise (glTF +Y) is Blender +Z. A first pass
# here measured and translated in Blender's Y and silently normalised the wrong axis
# — the export looked plausible and was wrong, which is this repo's usual failure
# mode. GLTF_UP is the index of the growth axis in Blender terms; nothing below is
# allowed to hard-code 1 or 2 again.
GLTF_UP = 2       # glTF +Y  == Blender +Z
GLTF_SIDE = 0     # glTF +X  == Blender +X
GLTF_FWD = 1      # glTF +Z  == Blender -Y

# slug -> (blender axis, degrees) applied before export. Measured off the raw mesh
# bounds (thinnest axis = disc/blade normal) and confirmed against the CandShot
# renders: star_small and star_huge arrive disc-normal on glTF +X, coral_fan_a
# blade-normal on glTF +X. Everything absent already grows along glTF +Y.
ROTATE = {
    # glTF +X -> +Y  ==  blender +X -> +Z  ==  -90 deg about blender Y
    "star_small": ("Y", -90.0),
    "star_huge": ("Y", -90.0),
    # glTF +X -> +Z  ==  blender +X -> -Y  ==  -90 deg about blender Z
    "coral_fan_a": ("Z", -90.0),
}

# s20 — the same measurement, made instead of hand-tabled. The three ROTATE entries above
# were each found by eyeballing a raw mesh's bounds and then writing the answer down; with
# eleven more generated pieces arriving that does not scale, and a wrong guess is silent
# (a starfish exported edge-on still seats and still looks "placed" from the wrong angle).
# So the rule is stated once and the axis is measured per piece:
#
#   FLAT  — a disc lying ON the rock: its THINNEST bounding axis is its up. Rotate that
#           axis onto glTF +Y, the growth axis every reef piece contracts to.
#   BLADE — a sheet standing OFF the rock (a gorgonian, an elephant-ear sponge): its
#           thinnest axis is the blade NORMAL, which the placement code wants on glTF +Z
#           (leg_reef's `planar` species align local +Z to the wall's tangent).
#
# Both print the measured extents so the choice is auditable in the log rather than
# asserted here.
AUTO_FLAT = {"star_big_red", "star_big_blue", "star_big_spiny", "star_big_sunflower",
             "barnacle_cluster_a",
             # s21 — a mussel bed is the flattest thing on the reef (the brief calls for a
             # low encrusting mat, near-zero tilt, flush to the face), so FLAT is the right
             # rule for all four: thinnest axis is the bed's up, rotated onto glTF +Y.
             "mussel_bed_a", "mussel_bed_b", "mussel_bed_c", "mussel_clump_d",
             "mussel_clump", "mussel_bed_e", "mussel_bed_f"}
AUTO_BLADE = {"sponge_fan"}

# thin blender axis -> rotation that puts it on blender +Z (glTF +Y)
_TO_FLAT = {0: ("Y", -90.0), 1: ("X", 90.0), 2: None}
# thin blender axis -> rotation that puts it on blender -Y (glTF +Z)
_TO_BLADE = {0: ("Z", -90.0), 1: None, 2: ("X", 90.0)}

# The pieces that survived judging. coral_tube and coral_fan_b are deliberately
# absent: both arrived bedded on a baked-in rock, which cannot seat flush, and
# coral_fan_b duplicated coral_fan_a's silhouette. coral_encrust is out too: its base
# is a smooth pale stalk that reads as a plinth, and it took decimation worse than
# anything else in the set (its lace fronds came back as flat facets). coral_whip
# survived judging and decimation and was cut later, on the wall — see leg_reef.gd.
#
# s20 rejections, same rule, same method (rendered by tests/CandShot.tscn at the shipping
# ratio and looked at): sponge_fan is two thirds smooth pale trumpet foot — coral_encrust's
# plinth failure again; star_big_blue came back glassy cobalt with bent arms, the plastic-toy
# default the traps file names; barnacle_goose is a radially symmetric spiky ball rather than
# a bunch of stalked shells.
KEEP = [
    "star_small", "star_mid", "star_huge",
    "coral_branch_a", "coral_branch_b", "coral_plate", "coral_brain",
    "coral_fan_a", "coral_bubble",
    # s20 — judged in tests/CandShot.tscn at the shipping ratio. Rejections are recorded
    # in DEVLOG.md; nothing that arrived on a baked-in rock or plinth is in this list,
    # because a piece bedded on its own rock cannot seat flush against concrete.
    "reefmass_a", "reefmass_b", "reefmass_c", "reefmass_d",
    "sponge_barrel", "sponge_tube_cluster", "sponge_rope",
    "barnacle_cluster_a", "barnacle_giant",
    "star_big_red", "star_big_spiny", "star_big_sunflower",
    # s35 — THE WALL FLORA WAS MISSING FROM THIS LIST, which is a latent bug rather than a
    # decision: s34 re-cut the three by passing them as the trailing slug argument, so they
    # exist in the reef set but a plain `--python tools/decimate_reef.py -- <src> <dst>` run
    # would silently NOT regenerate them and the set would come back three pieces short. They
    # are placed in bulk on the caisson faces (leg_reef PLANTS and WEEDS) exactly like the
    # coral, so they belong here. Their source root is assets/models/fauna, not a _cand dir —
    # find_src takes several roots, so pass both.
    "bloom_sea_grass", "glow_creeper", "bloom_anemone",
]


def wipe():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def find_src(slug, roots):
    """First root that has this slug. Lets one run pull the s19 pieces out of _cand8 and
    the s20 ones out of _cand9 without copying anything around."""
    for root in roots:
        p = os.path.join(root, slug, slug + ".glb")
        if os.path.exists(p):
            return p
    return None


def one(slug, src_roots, dst_root):
    src = find_src(slug, src_roots)
    if src is None:
        print("[decimate] MISSING %s in %s" % (slug, ",".join(src_roots)))
        return None
    wipe()
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        print("[decimate] %s: no mesh" % slug)
        return None

    # join into one object so the decimate ratio is over the whole piece
    bpy.ops.object.select_all(action="DESELECT")
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active

    # bake the import transform down so the measurements below are in mesh space
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    before = len(ob.data.polygons)

    mod = ob.modifiers.new("dec", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.use_collapse_triangulate = True
    target = TARGET_OVERRIDE.get(slug, TARGET_TRIS)
    mod.ratio = min(1.0, float(target) / max(1, before))
    bpy.ops.object.modifier_apply(modifier=mod.name)
    after = len(ob.data.polygons)

    # Orientation: rotate, then drop the base onto the growth axis' zero and centre
    # the other two. Done by transforming the MESH DATA rather than posing the object
    # and calling transform_apply — the operator silently did nothing here (it depends
    # on selection/context that modifier_apply had already disturbed) and the export
    # came out unrotated but plausible-looking. Mesh.transform() takes no context.
    rot = ROTATE.get(slug)
    note = ""
    if rot is None and (slug in AUTO_FLAT or slug in AUTO_BLADE):
        vs = [v.co for v in ob.data.vertices]
        ext = [max(v[i] for v in vs) - min(v[i] for v in vs) for i in range(3)]
        thin = min(range(3), key=lambda i: ext[i])
        rot = (_TO_FLAT if slug in AUTO_FLAT else _TO_BLADE)[thin]
        note = "  auto(thin=blender%s ext %.2f/%.2f/%.2f -> %s)" % (
            "XYZ"[thin], ext[0], ext[1], ext[2], rot or "already right")
    if rot:
        axis, deg = rot
        ob.data.transform(mathutils.Matrix.Rotation(math.radians(deg), 4, axis))

    vs = [v.co for v in ob.data.vertices]
    lo = [min(v[i] for v in vs) for i in range(3)]
    hi = [max(v[i] for v in vs) for i in range(3)]
    off = [-(lo[i] + hi[i]) * 0.5 for i in range(3)]
    off[GLTF_UP] = -lo[GLTF_UP]
    ob.data.transform(mathutils.Matrix.Translation(off))
    vs = [v.co for v in ob.data.vertices]
    lo = [min(v[i] for v in vs) for i in range(3)]
    hi = [max(v[i] for v in vs) for i in range(3)]
    assert abs(lo[GLTF_UP]) < 1e-5, "%s: base not on zero (%.4f)" % (slug, lo[GLTF_UP])

    # textures: cap at MAX_TEX, keep UVs (COLLAPSE preserves them)
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
    print("[decimate] %-19s %6d -> %5d tris  gltf ext(x %.2f  y/grow %.2f  z %.2f)"
          "  tex %s  %.0f KB%s"
          % (slug, before, after, size[GLTF_SIDE], size[GLTF_UP], size[GLTF_FWD],
             ",".join(sorted(set(tex))), os.path.getsize(dst) / 1024.0, note))
    return after


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    src_roots = argv[0].split(",")
    dst_root = argv[1]
    only = [s for s in argv[2].split(",") if s] if len(argv) > 2 else []
    slugs = only or KEEP
    total = 0
    done = 0
    for slug in slugs:
        n = one(slug, src_roots, dst_root)
        if n:
            total += n
            done += 1
    print("[decimate] TOTAL %d tris across %d pieces" % (total, done))


main()
