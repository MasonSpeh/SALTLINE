"""Count REAL triangles in every GLB under assets/models, off the glTF index
accessors (not file bytes — s31 made that mistake and withdrew a correct
decimation call on file size).

Also reports, per asset: material count, image count, whether the mesh is
skinned (JOINTS_0 present / skins array non-empty), the AABB from POSITION
accessor min/max, and the vertex attributes present. Those are the things a
decimation pass must not change.

    python3 tools/survey_tris.py [--json out.json] [root]

Triangle counting follows glTF primitive modes: 4=TRIANGLES, 5=TRIANGLE_STRIP,
6=TRIANGLE_FAN. Non-triangle modes contribute 0.
"""
import json
import os
import struct
import sys

MODE_TRIANGLES, MODE_STRIP, MODE_FAN = 4, 5, 6


def parse_glb(path):
    """Return (gltf_json, bin_chunk) for a binary GLB, or (json, None) for .gltf."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:4] != b"glTF":
        return json.loads(data.decode("utf-8")), None
    _magic, _ver, _length = struct.unpack_from("<III", data, 0)
    off = 12
    js, binc = None, None
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + clen]
        off += clen
        if ctype == 0x4E4F534A:      # JSON
            js = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:    # BIN
            binc = chunk
    return js, binc


def survey(path):
    g, _bin = parse_glb(path)
    accessors = g.get("accessors", [])
    meshes = g.get("meshes", [])

    tris = 0
    verts = 0
    attrs = set()
    prim_count = 0
    used_materials = set()

    for m in meshes:
        for p in m.get("primitives", []):
            prim_count += 1
            mode = p.get("mode", MODE_TRIANGLES)
            attrs.update(p.get("attributes", {}).keys())
            if "material" in p:
                used_materials.add(p["material"])
            idx = p.get("indices")
            if idx is not None:
                count = accessors[idx]["count"]
            else:
                pos = p["attributes"].get("POSITION")
                count = accessors[pos]["count"] if pos is not None else 0
            if mode == MODE_TRIANGLES:
                tris += count // 3
            elif mode in (MODE_STRIP, MODE_FAN):
                tris += max(0, count - 2)
            pos = p["attributes"].get("POSITION")
            if pos is not None:
                verts += accessors[pos]["count"]

    # AABB across every POSITION accessor's declared min/max (glTF requires
    # min/max on POSITION), in the mesh's own local frame.
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    for m in meshes:
        for p in m.get("primitives", []):
            pos = p["attributes"].get("POSITION")
            if pos is None:
                continue
            a = accessors[pos]
            if "min" in a and "max" in a:
                for i in range(3):
                    lo[i] = min(lo[i], a["min"][i])
                    hi[i] = max(hi[i], a["max"][i])
    if lo[0] == float("inf"):
        lo = hi = [0.0, 0.0, 0.0]
    size = [hi[i] - lo[i] for i in range(3)]

    return {
        "path": path,
        "tris": tris,
        "verts": verts,
        "prims": prim_count,
        "meshes": len(meshes),
        "materials": len(g.get("materials", [])),
        "materials_used": len(used_materials),
        "images": len(g.get("images", [])),
        "textures": len(g.get("textures", [])),
        "skins": len(g.get("skins", [])),
        "animations": len(g.get("animations", [])),
        "skinned": "JOINTS_0" in attrs,
        "attrs": sorted(attrs),
        "aabb_min": lo,
        "aabb_max": hi,
        "aabb_size": size,
        "longest_axis": ["x", "y", "z"][size.index(max(size))],
        "longest_len": max(size),
        "bytes": os.path.getsize(path),
    }


def main():
    args = [a for a in sys.argv[1:]]
    out_json = None
    if "--json" in args:
        i = args.index("--json")
        out_json = args[i + 1]
        del args[i:i + 2]
    root = args[0] if args else "assets/models"

    rows = []
    for dirpath, _dirs, files in os.walk(root):
        for f in sorted(files):
            if f.lower().endswith((".glb", ".gltf")):
                p = os.path.join(dirpath, f)
                try:
                    rows.append(survey(p))
                except Exception as exc:  # noqa: BLE001 - report, don't crash the sweep
                    rows.append({"path": p, "tris": -1, "error": str(exc)})

    rows.sort(key=lambda r: -r.get("tris", 0))
    total = sum(r.get("tris", 0) for r in rows if r.get("tris", 0) > 0)
    print("%-9s %-8s %-4s %-4s %-4s %-6s %s" % (
        "TRIS", "VERTS", "MAT", "IMG", "SKIN", "LONG", "PATH"))
    for r in rows:
        if "error" in r:
            print("ERROR %s: %s" % (r["path"], r["error"]))
            continue
        print("%-9d %-8d %-4d %-4d %-4s %-6s %s" % (
            r["tris"], r["verts"], r["materials"], r["images"],
            "yes" if r["skinned"] else "-",
            "%s%.2f" % (r["longest_axis"], r["longest_len"]),
            r["path"]))
    print("\nTOTAL %d GLBs, %d triangles" % (len(rows), total))

    if out_json:
        with open(out_json, "w") as fh:
            json.dump(rows, fh, indent=1)
        print("wrote %s" % out_json)


if __name__ == "__main__":
    main()
