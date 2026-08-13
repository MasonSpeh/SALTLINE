class_name RigKit extends RefCounted
## THE MODULE KIT — the shared vocabulary the three new rigs of THE FIELD are built from.
##
## `rig_builder.gd` builds SALTLINE-0 as ~6,800 loose MeshInstance3D/CSG primitives and then
## pays `rig_batcher.gd` to weld them back together at runtime. That is the right authoring
## model for the rig the player lives on and the wrong one for three MORE platforms that are
## on screen from 160-415 m away: gl_compatibility draws one call per surface, the measured
## worst topside vantage is already 2,861 draws, and four rigs of loose primitives is ~11,000.
##
## So this kit BATCHES BY CONSTRUCTION. Every module writes triangles into a `Bake`, keyed by
## (material, group, 48 m world cell), and one `flush()` emits a handful of ArrayMeshes. A
## whole rig — legs, decks, blocks, derrick, rails, catwalks — costs on the order of 20-30
## draw calls instead of 2,000, with no post-hoc weld pass, no timing dependency, and no
## chance of the batcher skipping something. Colliders are separate and untouched by any of
## it: one StaticBody3D per rig carrying plain BoxShape3Ds, so the player, the raycasts and
## the probes all see honest solids.
##
## Why this and not an LOD impostor tier: an impostor is a way to stop paying for detail you
## authored. Not authoring the detail as 2,000 separate draw calls in the first place is
## strictly better and cannot desynchronise from the real thing. What survives of the tier
## idea is one honest knob — `group` "detail" chunks carry an engine-side
## `visibility_range_end`, so beyond DETAIL_DRAW_M a rig collapses to its silhouette with no
## per-frame GDScript at all (the same mechanism as `leg_reef.REEF_DRAW_M`).
##
## AUTHORING CONTRACT
##   * Everything is authored in LOCAL rig coordinates: +Y up, the rig origin at (0,0,0) on
##     mean water, +Z "north" along the field. `Bake.xform` places and rotates it. That is
##     what lets a rig be moved, re-bearinged and scanned independently.
##   * The rig ORIGIN is a fixed constant in `rig_field.gd`, never runtime-placed —
##     `save_manager._harvest_key()` keys harvest state by absolute position.
##   * Y is never guessed twice. Each rig script declares its deck elevations as named
##     constants at the top and derives every module from them; nothing downstream re-types
##     a number that a constant already holds.

# ---------------------------------------------------------------------------- primitives

## Cached unit-primitive vertex arrays. Building a BoxMesh per box (rig_builder's model)
## allocates ~3,000 Mesh resources per rig; these are pulled once and transformed.
static var _prim_cache: Dictionary = {}

static func _prim(key: String, mesh: Mesh) -> Array:
	if _prim_cache.has(key):
		return _prim_cache[key]
	var arr: Array = mesh.surface_get_arrays(0)
	var out: Array = [arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_NORMAL], arr[Mesh.ARRAY_INDEX]]
	_prim_cache[key] = out
	return out

static func _unit_box() -> Array:
	if _prim_cache.has("box"):
		return _prim_cache["box"]
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	return _prim("box", bm)

## Unit cylinder: radius 1 (bottom), height 1, running along local +Y. `taper` is
## top_radius / bottom_radius, so a cone is taper 0 and a pipe is taper 1.
static func _unit_cyl(segs: int, taper: float) -> Array:
	var key: String = "cyl_%d_%.3f" % [segs, taper]
	if _prim_cache.has(key):
		return _prim_cache[key]
	var cm := CylinderMesh.new()
	cm.bottom_radius = 1.0
	cm.top_radius = maxf(taper, 0.0)
	cm.height = 1.0
	cm.radial_segments = segs
	cm.rings = 1
	return _prim(key, cm)

# --------------------------------------------------------------------------------- Bake

## The accumulator. One per rig (or per bridge). Author into it, then `flush(parent)`.
class Bake extends RefCounted:
	## Chunk cell edge, in PLAN and in the BAKE'S OWN LOCAL FRAME.
	##
	## Three things were got wrong here in one sitting and all three are worth recording,
	## because each looked like a smaller number and was not:
	##   1. Keying on y as well as x/z tripled the chunk count for a culling win that never
	##      happens — nothing ever sees a rig's deck without its legs. 272 chunks.
	##   2. Keying on the WORLD position put the cell grid wherever the rig happened to land,
	##      so a platform centred on a boundary split into four for no reason. 217 chunks.
	##   3. So: LOCAL, offset by half a cell, at 160 m. Every rig is inside one cell and
	##      becomes one mesh per (material, group) — while the bridge bake, which is 400 m
	##      long and genuinely wants chunking, still splits into three.
	## A whole-rig mesh is not a shadow problem: the biggest of these is ~30 k triangles
	## against rig 1's 855 k, and the caissons that reach y -92 carry their own material and
	## are therefore already their own chunk.
	const CELL: float = 160.0
	## Beyond this, "detail" chunks stop drawing and the rig reads as silhouette. Engine-side
	## (`visibility_range_end`), so it costs no per-frame script — same mechanism as
	## leg_reef.REEF_DRAW_M. 210 m clears the longest bridge (166 m centre-to-centre) so a
	## player standing on rig 2 always has rig 3 at full detail before they set out.
	const DETAIL_DRAW_M: float = 210.0
	const DETAIL_FADE_M: float = 45.0

	var xform: Transform3D = Transform3D.IDENTITY   ## local -> world
	var label: String = "rig"

	var _acc: Dictionary = {}      ## key -> {mat, group, v, n, i}
	var _shapes: Array = []        ## [{xf: Transform3D (LOCAL), size: Vector3}]
	## Every stair flight built through this bake, as WORLD-space [foot, head] pairs.
	## The probe walks this list and refuses any flight whose ends are not on real floor
	## or whose line of climb is obstructed — a stair is a CLAIM, and claims get measured.
	var stairs: Array = []
	var _tri_count: int = 0
	var _prim_count: int = 0

	func _init(p_xform: Transform3D = Transform3D.IDENTITY, p_label: String = "rig") -> void:
		xform = p_xform
		label = p_label

	func tris() -> int:
		return _tri_count

	func prims() -> int:
		return _prim_count

	func chunks() -> int:
		return _acc.size()

	## Transform a local point into world space (probes and marker placement use this).
	func to_world(p: Vector3) -> Vector3:
		return xform * p

	# ------------------------------------------------------------------ emitters

	## A box. `rot` is local euler radians. `collide` adds a matching BoxShape3D.
	##
	## NOTE `scaled_local`, NOT `scaled`. Godot's `Basis.scaled()` pre-multiplies — it scales
	## along the PARENT's axes — so a rotated box came out stretched along world Y instead of
	## along its own length. Every diagonal in the field was affected and the frames showed it
	## exactly: the collapsed polytunnel's arches rendered as a forest of vertical poles, and
	## the derrick's X-bracing as sticks. Colliders were unaffected (a BoxShape3D carries its
	## own size and only needs a pure rotation), which is why the probe passed a world that
	## LOOKED wrong. Judged on the render, not on the log.
	func box(pos: Vector3, size: Vector3, mat: Material, group: String = "hull",
			rot: Vector3 = Vector3.ZERO, collide: bool = false) -> void:
		var b: Basis = Basis.from_euler(rot)
		_write(RigKit._unit_box(), Transform3D(b.scaled_local(size), pos), mat, group)
		if collide:
			_shapes.append({"xf": Transform3D(b, pos), "size": size})

	## A cylinder standing on local +Y unless rotated. `top_r` < 0 means "same as radius".
	func cyl(pos: Vector3, radius: float, height: float, mat: Material, group: String = "hull",
			rot: Vector3 = Vector3.ZERO, top_r: float = -1.0, segs: int = 12,
			collide: bool = false) -> void:
		var taper: float = 1.0 if top_r < 0.0 else clampf(top_r / maxf(radius, 0.0001), 0.0, 8.0)
		var b: Basis = Basis.from_euler(rot)
		_write(RigKit._unit_cyl(segs, taper), Transform3D(b.scaled_local(Vector3(radius, height, radius)), pos), mat, group)
		if collide:
			# Box proxy: cylinder colliders are rare here and a square proxy on a round leg
			# is invisible at the 6 m scale these are used at.
			var w: float = radius * 2.0 * maxf(taper, 1.0)
			_shapes.append({"xf": Transform3D(b, pos), "size": Vector3(w, height, w)})

	## A structural member between two local points — girder, brace, chord, guy.
	func member(a: Vector3, c: Vector3, thick: float, mat: Material, group: String = "detail") -> void:
		var d: Vector3 = c - a
		var span: float = d.length()
		if span < 0.01:
			return
		var dir: Vector3 = d / span
		var ref: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		var xa: Vector3 = ref.cross(dir).normalized()
		var za: Vector3 = dir.cross(xa).normalized()
		var basis := Basis(xa, dir, za).scaled_local(Vector3(thick, span, thick))
		_write(RigKit._unit_box(), Transform3D(basis, (a + c) * 0.5), mat, group)

	## A pure collider with no geometry — the smooth walking slab under a stepped stair, the
	## full-height guard behind a visual railing. This is the repo's own rail grammar
	## (rig_exterior._rail_slab): the steel you SEE is visual-only, the thing you TOUCH is one
	## smooth slab, so a capsule can never catch at the waist while its feet slide under.
	func collider(pos: Vector3, size: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
		_shapes.append({"xf": Transform3D(Basis.from_euler(rot), pos), "size": size})

	## Register one flight (LOCAL coords; stored in world space) for the stair probe.
	func stair_link(foot: Vector3, head: Vector3) -> void:
		stairs.append([xform * foot, xform * head])

	func _write(prim: Array, local_xf: Transform3D, mat: Material, group: String) -> void:
		var xf: Transform3D = xform * local_xf
		var src_v: PackedVector3Array = prim[0]
		var src_n: PackedVector3Array = prim[1]
		var src_i: PackedInt32Array = prim[2]
		var key: String = "%d|%s|%s" % [mat.get_instance_id(), group, _cell_of(local_xf.origin)]
		var e: Dictionary = _acc.get(key, {})
		if e.is_empty():
			e = {"mat": mat, "group": group,
				"v": PackedVector3Array(), "n": PackedVector3Array(), "i": PackedInt32Array()}
			_acc[key] = e
		var base: int = (e["v"] as PackedVector3Array).size()
		# Non-uniform scale means normals need the inverse-transpose, not the basis.
		var nb: Basis = xf.basis.inverse().transposed()
		var vv: PackedVector3Array = e["v"]
		var nn: PackedVector3Array = e["n"]
		var ii: PackedInt32Array = e["i"]
		for k in range(src_v.size()):
			vv.append(xf * src_v[k])
			nn.append((nb * src_n[k]).normalized())
		for k in range(src_i.size()):
			ii.append(base + src_i[k])
		e["v"] = vv
		e["n"] = nn
		e["i"] = ii
		_tri_count += src_i.size() / 3
		_prim_count += 1

	func _cell_of(local_p: Vector3) -> String:
		# Half-cell offset so the bake's own origin sits in the MIDDLE of a cell rather than
		# on a corner of four.
		return "%d_%d" % [floori((local_p.x + CELL * 0.5) / CELL), floori((local_p.z + CELL * 0.5) / CELL)]

	# --------------------------------------------------------------------- flush

	## Emit the accumulated geometry as one MeshInstance3D per (material, group, cell), plus
	## one StaticBody3D carrying every collider. Returns the number of draw-call chunks.
	func flush(parent: Node3D) -> int:
		for key in _acc:
			var e: Dictionary = _acc[key]
			var arr: Array = []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = e["v"]
			arr[Mesh.ARRAY_NORMAL] = e["n"]
			arr[Mesh.ARRAY_INDEX] = e["i"]
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			mesh.surface_set_material(0, e["mat"])
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.name = "%s_%s" % [label, str(key).replace("|", "_")]
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			var group: String = e["group"]
			# HULL carries the silhouette and the shadow. DETAIL does neither past its range:
			# a handrail 200 m away is one pixel and its shadow is shadow-map noise.
			if group == "hull":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			else:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if group == "lamp":
				# Emissive fixtures live in their own chunks so the power grid has exactly one
				# boolean per chunk to flip. They are never range-culled: from a neighbouring
				# rig the lit lenses ARE the building. See rig_field._wire_power().
				mi.set_meta("field_lamp", true)
				mi.visible = false
			if group == "detail":
				mi.visibility_range_end = DETAIL_DRAW_M
				mi.visibility_range_end_margin = DETAIL_FADE_M
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			# Structural batches are already merged; render_budget must not also range them.
			mi.set_meta("budgeted", true)
			mi.set_meta("rigkit_group", group)
			parent.add_child(mi)
		if not _shapes.is_empty():
			var body := StaticBody3D.new()
			body.name = "%s_Collision" % label
			parent.add_child(body)
			for s in _shapes:
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = s["size"]
				cs.shape = bs
				body.add_child(cs)
				cs.transform = xform * (s["xf"] as Transform3D)
		return _acc.size()

# ------------------------------------------------------------------------ substructure

## One caisson leg: a single casting from `top_y` down to `bottom_y`, plus the tide band
## where the swell breathes on it. ONE MESH ALL THE WAY DOWN, deliberately — rig_builder
## records at length that splitting a leg into two meshes drew a razor-sharp tone seam a few
## metres under the surface. Same rule here.
static func caisson(b: Bake, cx: float, cz: float, half: float, top_y: float,
		bottom_y: float = -92.0) -> void:
	var h: float = top_y - bottom_y
	var mid: float = (top_y + bottom_y) * 0.5
	b.box(Vector3(cx, mid, cz), Vector3(half * 2.0, h, half * 2.0), MatLib.concrete(), "hull",
		Vector3.ZERO, true)
	# The weed line. A 2.4 m band centred on mean water, stood 3 cm proud so it never z-fights.
	b.box(Vector3(cx, 0.1, cz), Vector3(half * 2.0 + 0.06, 2.4, half * 2.0 + 0.06),
		MatLib.tide_band(), "hull")

## The pontoon / gravity base beam that ties a row of legs together, riding just above the
## v2 swell (crests reach ~0.9 — see rig_builder's own pontoons at y -1.05).
static func pontoon(b: Bake, center: Vector3, size: Vector3) -> void:
	b.box(center, size, MatLib.concrete_floor(), "hull", Vector3.ZERO, true)
	b.box(Vector3(center.x, center.y + size.y * 0.5 - 0.1, center.z),
		Vector3(size.x + 0.05, 2.0, size.z + 0.05), MatLib.tide_band(), "hull")

## A plain deck slab. `y` is the WALKING SURFACE; the slab hangs below it.
static func deck(b: Bake, rect: Rect2, y: float, thick: float = 1.0,
		mat: Material = null, group: String = "hull") -> void:
	var m: Material = mat if mat != null else MatLib.deck_plate()
	var c: Vector2 = rect.get_center()
	b.box(Vector3(c.x, y - thick * 0.5, c.y), Vector3(rect.size.x, thick, rect.size.y), m,
		group, Vector3.ZERO, true)

## A deck slab with a rectangular hole (stair well, moon pool, aquarium void). Built as four
## rim boxes rather than a CSG subtraction: CSG costs a rebuild and a collision mesh, and
## four boxes give tighter colliders around the opening the player can fall through.
static func deck_hole(b: Bake, rect: Rect2, hole: Rect2, y: float, thick: float = 1.0,
		mat: Material = null, group: String = "hull") -> void:
	var m: Material = mat if mat != null else MatLib.deck_plate()
	var x0: float = rect.position.x
	var x1: float = rect.end.x
	var z0: float = rect.position.y
	var z1: float = rect.end.y
	var hx0: float = maxf(hole.position.x, x0)
	var hx1: float = minf(hole.end.x, x1)
	var hz0: float = maxf(hole.position.y, z0)
	var hz1: float = minf(hole.end.y, z1)
	var yc: float = y - thick * 0.5
	# South and north bands run the full width; east and west bands fill between them.
	if hz0 > z0:
		b.box(Vector3((x0 + x1) * 0.5, yc, (z0 + hz0) * 0.5), Vector3(x1 - x0, thick, hz0 - z0), m, group, Vector3.ZERO, true)
	if z1 > hz1:
		b.box(Vector3((x0 + x1) * 0.5, yc, (hz1 + z1) * 0.5), Vector3(x1 - x0, thick, z1 - hz1), m, group, Vector3.ZERO, true)
	if hx0 > x0:
		b.box(Vector3((x0 + hx0) * 0.5, yc, (hz0 + hz1) * 0.5), Vector3(hx0 - x0, thick, hz1 - hz0), m, group, Vector3.ZERO, true)
	if x1 > hx1:
		b.box(Vector3((hx1 + x1) * 0.5, yc, (hz0 + hz1) * 0.5), Vector3(x1 - hx1, thick, hz1 - hz0), m, group, Vector3.ZERO, true)

# ------------------------------------------------------------------------------- railing

const RAIL_H: float = 1.12          ## top rail height above the walking surface
const RAIL_BAR: float = 0.07

## HOW FAR A RAIL RUN'S COLLISION STOPS SHORT OF ITS VISUAL STEEL AT EACH END.
##
## This is the corner-forgiveness shave, and it is the fix rig 1 has had since s20 while the
## kit that builds MARROW, THE ANCHORAGE and DEEPWELL never received it — `grep -c SHAVE` on
## this file returned 0 until s65. It was filed as the top follow-up of s59 ("the rail-post
## chamfer at source"), deferred, and never entered into KNOWN_ISSUES, which is why the owner
## has reported "permanently stuck on the corners of railing" in every session since.
##
## The mechanism, quoting rig_builder.gd's own note: a rail run ends in a square cap, and
## where two runs meet those caps are two flat faces at right angles with an outside corner
## between them. A capsule cutting the corner diagonally arrives on BOTH faces in the same
## frame, gets a slide direction from each, and they cancel — the player stops dead on thin
## air a hand's width from the rail. Pulling the invisible barrier back from the visual end
## turns that hard corner into a rounded one: you slide off the end of the slab instead of
## hitting its cap.
##
## It cannot open a hole. 0.18 m off each end only ever widens a gap that is already an
## intended opening, and the narrowest a player capsule (radius 0.37) can pass through is
## 0.74 m — four times this.
const RAIL_END_SHAVE: float = 0.18

## A rail's collision slab, shaved at both ends. `length` is the run's visual length; the
## collider returned is shorter. Runs too short to shave keep their full length, because
## taking 0.36 m off a 0.5 m stub would leave almost nothing to lean on.
##
## NOT used by `ring_rail`: that builds a continuous curve out of many short chained segments,
## and shaving each one would perforate an unbroken barrier into a dashed line. The trap this
## fixes is the RIGHT-ANGLE junction, which a smooth ring does not have.
static func _rail_collider(b: Bake, pos: Vector3, cross: float, height: float,
		length: float, rot: Vector3) -> void:
	var l: float = length
	if l > RAIL_END_SHAVE * 3.0:
		l -= RAIL_END_SHAVE * 2.0
	b.collider(pos, Vector3(cross, height, l), rot)

## One straight run of railing between two local XZ points, at walking height `y`.
## Visual: two horizontal bars + posts. Physical: ONE smooth full-height slab, so a capsule
## pressed against it cannot catch at the waist (rig_exterior._rail_slab's lesson).
static func rail_run(b: Bake, a: Vector2, c: Vector2, y: float, collide: bool = true) -> void:
	var d: Vector2 = c - a
	var span: float = d.length()
	if span < 0.2:
		return
	var yaw: float = atan2(d.x, d.y)
	var mid := Vector3((a.x + c.x) * 0.5, y, (a.y + c.y) * 0.5)
	var steel: Material = MatLib.galvanized()
	for hh in [RAIL_H, RAIL_H * 0.52]:
		b.box(mid + Vector3(0, hh, 0), Vector3(RAIL_BAR, RAIL_BAR, span), steel, "detail",
			Vector3(0, yaw, 0))
	var posts: int = maxi(2, int(span / 1.9))
	for i in range(posts + 1):
		var t: float = float(i) / float(posts)
		var p: Vector2 = a.lerp(c, t)
		b.box(Vector3(p.x, y + RAIL_H * 0.5, p.y), Vector3(0.075, RAIL_H, 0.075), steel, "detail")
	# Kick plate along the deck edge — reads right and stops dropped props sliding off.
	b.box(mid + Vector3(0, 0.09, 0), Vector3(0.05, 0.18, span), MatLib.rust_steel(), "detail",
		Vector3(0, yaw, 0))
	if collide:
		_rail_collider(b, mid + Vector3(0, RAIL_H * 0.5 + 0.05, 0), 0.14, RAIL_H + 0.1, span,
			Vector3(0, yaw, 0))

## Perimeter railing around a rect, with named side gaps. `gaps` is an array of
## [side, from, to] where side is "n"|"s"|"e"|"w" and from/to are along that side's axis —
## the sea stays deliberately reachable, exactly as rig 1's corners are.
static func rail_rect(b: Bake, rect: Rect2, y: float, gaps: Array = [], inset: float = 0.2) -> void:
	var x0: float = rect.position.x + inset
	var x1: float = rect.end.x - inset
	var z0: float = rect.position.y + inset
	var z1: float = rect.end.y - inset
	var sides := {
		"s": [Vector2(x0, z0), Vector2(x1, z0), true],
		"n": [Vector2(x0, z1), Vector2(x1, z1), true],
		"w": [Vector2(x0, z0), Vector2(x0, z1), false],
		"e": [Vector2(x1, z0), Vector2(x1, z1), false],
	}
	for side in sides:
		var s: Array = sides[side]
		var a: Vector2 = s[0]
		var c: Vector2 = s[1]
		var horiz: bool = s[2]
		var cuts: Array = []
		for g in gaps:
			if str(g[0]) == side:
				cuts.append([minf(float(g[1]), float(g[2])), maxf(float(g[1]), float(g[2]))])
		cuts.sort_custom(func(p, q): return p[0] < q[0])
		var lo: float = a.x if horiz else a.y
		var hi: float = c.x if horiz else c.y
		var cursor: float = lo
		for cut in cuts:
			var c0: float = clampf(cut[0], lo, hi)
			var c1: float = clampf(cut[1], lo, hi)
			if c0 > cursor:
				_rail_seg(b, horiz, a, cursor, c0, y)
			cursor = maxf(cursor, c1)
		if cursor < hi:
			_rail_seg(b, horiz, a, cursor, hi, y)

static func _rail_seg(b: Bake, horiz: bool, anchor: Vector2, from_v: float, to_v: float, y: float) -> void:
	if to_v - from_v < 0.4:
		return
	if horiz:
		rail_run(b, Vector2(from_v, anchor.y), Vector2(to_v, anchor.y), y)
	else:
		rail_run(b, Vector2(anchor.x, from_v), Vector2(anchor.x, to_v), y)

# --------------------------------------------------------------------------------- stairs

## One stair flight, from walk-on floor point to walk-off floor point, baked.
##
## The walking surface is a single smooth INVISIBLE ramp under the stepped visuals, and the
## ramp is made FLUSH IN CLOSED FORM exactly as stair_kit.gd derives it: a box of half-
## thickness h pitched by `angle` has its top face at centre + h/cos(angle), not centre + h.
## Getting that wrong leaves the ramp millimetres below its landing, the landing edge stands
## proud, and a capsule loses a physics tick on it — the "stairs slow you down" bug.
const RISER_TARGET: float = 0.19
const RAMP_HALF: float = 0.06

static func stair(b: Bake, from_p: Vector3, to_p: Vector3, width: float,
		rail_left: bool = true, rail_right: bool = true,
		tread_mat: Material = null, steel_mat: Material = null) -> void:
	if to_p.y < from_p.y:
		var t: Vector3 = from_p
		from_p = to_p
		to_p = t
		var s: bool = rail_left
		rail_left = rail_right
		rail_right = s
	var d: Vector3 = to_p - from_p
	var rise: float = d.y
	var run: float = Vector2(d.x, d.z).length()
	if rise < 0.05 or run < 0.1:
		return
	b.stair_link(from_p, to_p)
	var steps: int = maxi(2, roundi(rise / RISER_TARGET))
	var riser: float = rise / steps
	var tread_d: float = run / steps
	var angle: float = atan2(rise, run)
	var yaw: float = atan2(d.x, d.z)
	# Rust is the default; a luxury interior passes its own finishes (the s54b lesson —
	# rusted steel inside a white drum condemns the whole room).
	var tread: Material = tread_mat if tread_mat != null else MatLib.checker_plate()
	var steel: Material = steel_mat if steel_mat != null else MatLib.rust_steel()
	# Local frame of the flight: +Z is the direction of climb.
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var rotv := Vector3(0, yaw, 0)
	for i in range(steps):
		var c: Vector3 = from_p + fwd * ((i + 0.5) * tread_d) + Vector3(0, (i + 1) * riser - 0.03, 0)
		b.box(c, Vector3(width, 0.06, tread_d + 0.04), tread, "detail", rotv)
		b.box(from_p + fwd * (i * tread_d + 0.02) + Vector3(0, (i + 0.72) * riser, 0),
			Vector3(width - 0.04, riser * 0.55, 0.03), steel, "detail", rotv)
	var slope_len: float = sqrt(rise * rise + run * run)
	for sgn in [-1.0, 1.0]:
		var st: Vector3 = from_p + fwd * (run * 0.5) + side * (sgn * (width * 0.5 + 0.03)) \
			+ Vector3(0, rise * 0.5 - 0.08, 0)
		b.box(st, Vector3(0.07, 0.30, slope_len + 0.3), steel, "detail", Vector3(-angle, yaw, 0))
	# The real walking surface. Flush at both ends by construction.
	b.collider(from_p + fwd * (run * 0.5) + Vector3(0, rise * 0.5 - RAMP_HALF / cos(angle), 0),
		Vector3(width, RAMP_HALF * 2.0, slope_len + 0.1), Vector3(-angle, yaw, 0))
	# Foot lip only, sunk, pulled UNDER the run — a floor of last resort at the bottom seam.
	b.collider(from_p + fwd * 0.2 + Vector3(0, -RAMP_HALF - 0.006, 0),
		Vector3(width, 0.12, 0.4), rotv)
	for pair in [[rail_left, -1.0], [rail_right, 1.0]]:
		if not bool(pair[0]):
			continue
		var sg: float = float(pair[1])
		var off: Vector3 = side * (sg * (width * 0.5 + 0.05))
		b.box(from_p + off + fwd * (run * 0.5) + Vector3(0, rise * 0.5 + 0.95, 0),
			Vector3(0.07, 0.07, slope_len + 0.2), steel, "detail", Vector3(-angle, yaw, 0))
		_rail_collider(b, from_p + off + fwd * (run * 0.5) + Vector3(0, rise * 0.5 + 0.55, 0),
			0.12, 1.3, slope_len + 0.2, Vector3(-angle, yaw, 0))
		var n_posts: int = maxi(2, int(run / 1.5))
		for i in range(n_posts + 1):
			var t2: float = float(i) / float(n_posts)
			b.box(from_p + off + fwd * (t2 * run) + Vector3(0, t2 * rise + 0.5, 0),
				Vector3(0.05, 1.0, 0.05), steel, "detail", rotv)

## A switchback stair TOWER: alternating flights inside a footprint, with landings, from
## `base_y` to `top_y`. Returns the landing Y values it produced, so a caller can hang doors
## and side decks off real numbers instead of re-deriving them.
static func stair_tower(b: Bake, rect: Rect2, base_y: float, top_y: float,
		flight_rise: float = 3.6, shell: bool = true) -> Array:
	var levels: Array = []
	var n: int = maxi(1, int(round((top_y - base_y) / flight_rise)))
	var rise: float = (top_y - base_y) / float(n)
	var x0: float = rect.position.x
	var x1: float = rect.end.x
	var zc: float = rect.get_center().y
	# TWO LANES, NOT ONE. A single-lane switchback stacks flight i+1 directly over flight i,
	# and the clearance between them is 2*rise*(1-t): approaching any landing a climber has
	# less than a metre of headroom, and the flight above's ramp collider physically stops
	# the capsule. Alternating flights between a north and a south lane means no flight is
	# ever directly over the one below it — the same reason rig 1's tower has STAIR_ZS and
	# STAIR_ZN lanes. Landings span both lanes, so the turn at each end is a real turn.
	var lane_w: float = clampf((rect.size.y - 1.0) * 0.5, 1.2, 2.2)
	var lane_off: float = lane_w * 0.5 + 0.12
	var landing_d: float = 2.0
	# BASE SLAB, always, top 15 mm below base_y: three towers stood their first flight on
	# open air (the tower rect is not part of any deck), and on towers that DO sit on a deck
	# the sunken slab hides under the plating instead of z-fighting it.
	b.box(Vector3(rect.get_center().x, base_y - 0.105, zc),
		Vector3(rect.size.x, 0.18, rect.size.y), MatLib.grating(), "hull", Vector3.ZERO, true)
	for i in range(n):
		var y0: float = base_y + rise * i
		var y1: float = y0 + rise
		var west_up: bool = (i % 2) == 0
		var lz: float = zc + (lane_off if i % 2 == 0 else -lane_off)
		var a := Vector3(x0 + landing_d if west_up else x1 - landing_d, y0, lz)
		var c := Vector3(x1 - landing_d if west_up else x0 + landing_d, y1, lz)
		stair(b, a, c, lane_w, true, true)
		# Landing slab at the top of each flight.
		var lx: float = c.x + (landing_d * 0.5 if west_up else -landing_d * 0.5)
		b.box(Vector3(lx, y1 - 0.09, zc), Vector3(landing_d + 0.4, 0.18, rect.size.y - 0.4),
			MatLib.grating(), "hull", Vector3.ZERO, true)
		levels.append(y1)
	if shell:
		# Open frame: four corner columns and a rail skirt at each landing. Not a closed
		# box — a stair tower you cannot see out of reads as a lift shaft.
		var steel: Material = MatLib.rust_steel()
		for sx in [x0, x1]:
			for sz in [rect.position.y, rect.end.y]:
				b.box(Vector3(sx, (base_y + top_y) * 0.5, sz),
					Vector3(0.34, top_y - base_y, 0.34), steel, "hull", Vector3.ZERO, true)
		# N and S sides only. The old w/e gap specs passed X-ranges where rail_rect expects
		# Z-ranges, so they never matched and both TURN/EXIT ends were silently fenced at
		# every level. The ends stay fully open: they are where the landings turn and where
		# the head walks off.
		for y in levels:
			rail_rect(b, rect, y, [["w", rect.position.y, rect.end.y], ["e", rect.position.y, rect.end.y]], 0.05)
	return levels

# ------------------------------------------------------------------------------- catwalk

## A walkway between two local points at (possibly different) heights: grating deck, edge
## beams, rails both sides, and hangers up to whatever is above. This is the "overpass" the
## brief asks for — the thing that makes a rig read as irregular.
static func catwalk(b: Bake, a: Vector3, c: Vector3, width: float = 1.8,
		rails: bool = true, hangers_to: float = -1000.0,
		deck_mat: Material = null, beam_mat: Material = null) -> void:
	var d: Vector3 = c - a
	var span: float = d.length()
	if span < 0.5:
		return
	var flat: Vector2 = Vector2(d.x, d.z)
	var yaw: float = atan2(flat.x, flat.y)
	var pitch: float = -atan2(d.y, flat.length())
	var mid: Vector3 = (a + c) * 0.5
	var rot := Vector3(pitch, yaw, 0)
	var dm: Material = deck_mat if deck_mat != null else MatLib.grating()
	var bm: Material = beam_mat if beam_mat != null else MatLib.rust_steel()
	b.box(mid + Vector3(0, -0.09, 0), Vector3(width, 0.14, span), dm, "hull", rot)
	b.collider(mid + Vector3(0, -0.09, 0), Vector3(width, 0.16, span), rot)
	for sgn in [-1.0, 1.0]:
		var off: Vector3 = Vector3(cos(yaw), 0, -sin(yaw)) * (sgn * width * 0.5)
		b.box(mid + off + Vector3(0, -0.24, 0), Vector3(0.09, 0.32, span), bm, "detail", rot)
		if rails:
			b.box(mid + off + Vector3(0, RAIL_H, 0), Vector3(0.06, 0.06, span), MatLib.galvanized(), "detail", rot)
			b.box(mid + off + Vector3(0, RAIL_H * 0.55, 0), Vector3(0.06, 0.06, span), MatLib.galvanized(), "detail", rot)
			_rail_collider(b, mid + off + Vector3(0, RAIL_H * 0.55, 0), 0.12, RAIL_H + 0.2, span, rot)
			var posts: int = maxi(2, int(span / 2.2))
			for i in range(posts + 1):
				var t: float = float(i) / float(posts)
				var p: Vector3 = a.lerp(c, t) + off
				b.box(p + Vector3(0, RAIL_H * 0.5, 0), Vector3(0.05, RAIL_H, 0.05), MatLib.galvanized(), "detail")
	if hangers_to > -999.0:
		var n: int = maxi(1, int(span / 6.0))
		for i in range(n + 1):
			var t: float = float(i) / float(n)
			var p: Vector3 = a.lerp(c, t)
			b.member(p + Vector3(0, -0.1, 0), Vector3(p.x, hangers_to, p.z), 0.09, MatLib.rust_steel())

## A CATWALK WITH RAIL GAPS: same deck and edge beams as catwalk(), but the rails on each
## side are laid in segments, skipping [d0, d1] distance ranges (metres from `a`). This is
## how a stair head arrives at a walkway without a balustrade across its top step.
static func railed_walk(b: Bake, a: Vector3, c: Vector3, width: float,
		gaps_left: Array = [], gaps_right: Array = []) -> void:
	catwalk(b, a, c, width, false)
	var d: Vector3 = c - a
	var span: float = d.length()
	if span < 0.5:
		return
	var yaw: float = atan2(d.x, d.z)
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	for pair in [[-1.0, gaps_left], [1.0, gaps_right]]:
		var sgn: float = pair[0]
		var gaps: Array = (pair[1] as Array).duplicate()
		gaps.sort_custom(func(p, q): return p[0] < q[0])
		var off: Vector3 = side * (sgn * width * 0.5)
		var cursor: float = 0.0
		for g in gaps:
			if g[0] - cursor > 0.5:
				_walk_rail_seg(b, a + off, c + off, span, cursor, g[0])
			cursor = maxf(cursor, g[1])
		if span - cursor > 0.5:
			_walk_rail_seg(b, a + off, c + off, span, cursor, span)

## THE CORNER OF AN OUTBOARD RING, which four `railed_walk` runs leave as a HOLE (s65).
##
## The rings on MARROW and DEEPWELL are four runs sharing their corner points. A run's deck
## spans exactly `a`->`c` (see `catwalk`), so where the south run starts at x0 and the west
## run starts at z0, the quadrant OUTBOARD of both — x < x0 and z < z0 — is covered by
## neither: a `half` x `half` gap in the walking surface at every corner, 20 m over the sea,
## with both outer rails ending at its edges rather than turning it. Neither the field probe
## nor the 412-sample accessibility log samples these rings, which is why it survived.
##
## `cx`/`cz` are the shared corner point; `sx`/`sz` say which way the missing quadrant lies.
static func mezz_corner(b: Bake, cx: float, cz: float, y: float, half: float,
		sx: float, sz: float) -> void:
	var ox: float = cx + sx * half * 0.5
	var oz: float = cz + sz * half * 0.5
	# Fill the quadrant exactly — no overlap with either run's deck, because two coplanar
	# decks at the same y z-fight (the s64 dining-floor lesson).
	catwalk(b, Vector3(cx + sx * half, y, oz), Vector3(cx, y, oz), half, false)
	# And turn the two outboard edges, which currently end in mid-air.
	rail_run(b, Vector2(cx + sx * half, cz + sz * half), Vector2(cx + sx * half, cz), y)
	rail_run(b, Vector2(cx + sx * half, cz + sz * half), Vector2(cx, cz + sz * half), y)

static func _walk_rail_seg(b: Bake, a: Vector3, c: Vector3, span: float, d0: float, d1: float) -> void:
	var p0: Vector3 = a.lerp(c, d0 / span)
	var p1: Vector3 = a.lerp(c, d1 / span)
	rail_run(b, Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), (p0.y + p1.y) * 0.5)

# ---------------------------------------------------------------------------- superstructure

## A block: the accommodation / process / plant buildings. `storeys` floor slabs from
## `floor_y` at `storey_h` apart, walls with a window band per storey, a roof slab, and a
## walk-on roof if `roof_deck`. Interiors are deliberately EMPTY — this session builds the
## structural shell and the measurements; fitting out is the next pass.
static func block(b: Bake, rect: Rect2, floor_y: float, storeys: int, storey_h: float,
		wall_mat: Material, opts: Dictionary = {}) -> Array:
	var wall_t: float = float(opts.get("wall_t", 0.28))
	var window_mat: Material = MatLib.glass(opts.get("glass_tint", Color(0.62, 0.72, 0.74)))
	var floor_mat: Material = opts.get("floor_mat", MatLib.deck_plate())
	var roof_deck: bool = bool(opts.get("roof_deck", true))
	var window_band: bool = bool(opts.get("windows", true))
	var open_sides: Array = opts.get("open", [])       ## sides with no wall at all (plant halls)
	var doors: Array = opts.get("doors", [])           ## [side, along, storey_index]
	var levels: Array = []
	var c: Vector2 = rect.get_center()
	for s in range(storeys):
		var y: float = floor_y + storey_h * s
		levels.append(y)
		if s > 0:
			deck(b, rect, y, 0.22, floor_mat)
		for side in ["s", "n", "w", "e"]:
			if open_sides.has(side):
				continue
			_block_wall(b, rect, side, y, storey_h, wall_t, wall_mat, window_mat,
				window_band, doors, s)
	var roof_y: float = floor_y + storey_h * storeys
	deck(b, rect, roof_y, 0.3, MatLib.deck_plate() if roof_deck else MatLib.corrugated())
	# `roof_rails` is separate from `roof_deck` on purpose: an intermediate double-height
	# ceiling IS a walk-on slab for the storey above it, and railing it would put a
	# handrail through the middle of a room.
	if roof_deck and bool(opts.get("roof_rails", true)):
		rail_rect(b, rect, roof_y, opts.get("roof_gaps", []), 0.25)
	# Parapet upstand — a roof without one reads as a floating slab.
	if not roof_deck:
		for side in ["s", "n", "w", "e"]:
			_parapet(b, rect, side, roof_y, wall_mat)
	levels.append(roof_y)
	return levels

static func _parapet(b: Bake, rect: Rect2, side: String, y: float, mat: Material) -> void:
	var c: Vector2 = rect.get_center()
	match side:
		"s": b.box(Vector3(c.x, y + 0.3, rect.position.y + 0.14), Vector3(rect.size.x, 0.6, 0.28), mat, "hull")
		"n": b.box(Vector3(c.x, y + 0.3, rect.end.y - 0.14), Vector3(rect.size.x, 0.6, 0.28), mat, "hull")
		"w": b.box(Vector3(rect.position.x + 0.14, y + 0.3, c.y), Vector3(0.28, 0.6, rect.size.y), mat, "hull")
		"e": b.box(Vector3(rect.end.x - 0.14, y + 0.3, c.y), Vector3(0.28, 0.6, rect.size.y), mat, "hull")

const DOOR_W: float = 1.5
const DOOR_H: float = 2.25

static func _block_wall(b: Bake, rect: Rect2, side: String, y: float, h: float, t: float,
		mat: Material, glass_mat: Material, windows: bool, doors: Array, storey: int) -> void:
	# Wall runs along `axis`; `pos` is the fixed coordinate; `normal_z` says which axis.
	var horiz: bool = side == "s" or side == "n"
	var length: float = rect.size.x if horiz else rect.size.y
	var c: Vector2 = rect.get_center()
	var fixed: float = 0.0
	match side:
		"s": fixed = rect.position.y + t * 0.5
		"n": fixed = rect.end.y - t * 0.5
		"w": fixed = rect.position.x + t * 0.5
		"e": fixed = rect.end.x - t * 0.5
	var along_c: float = c.x if horiz else c.y
	var lo: float = along_c - length * 0.5
	var hi: float = along_c + length * 0.5

	# Openings on this wall at this storey: doorways.
	var cuts: Array = []
	for d in doors:
		if str(d[0]) == side and int(d[2]) == storey:
			var a: float = float(d[1])
			cuts.append([a - DOOR_W * 0.5, a + DOOR_W * 0.5])
	cuts.sort_custom(func(p, q): return p[0] < q[0])

	# Wall is built in three horizontal bands: sill (0 -> 1.0), window band (1.0 -> 2.3),
	# header (2.3 -> h). Doorways cut the sill and window bands only.
	var bands: Array = []
	if windows:
		bands = [[0.0, 1.0, mat], [1.0, 2.30, glass_mat], [2.30, h, mat]]
	else:
		bands = [[0.0, h, mat]]
	for band in bands:
		var b0: float = float(band[0])
		var b1: float = float(band[1])
		var bm: Material = band[2]
		if b1 - b0 < 0.02:
			continue
		var cut_this: bool = b0 < DOOR_H
		var segs: Array = []
		if cut_this and not cuts.is_empty():
			var cursor: float = lo
			for cut in cuts:
				if cut[0] > cursor:
					segs.append([cursor, cut[0]])
				cursor = maxf(cursor, cut[1])
			if cursor < hi:
				segs.append([cursor, hi])
			# Lintel over each doorway, if the band reaches above the door head.
			if b1 > DOOR_H:
				for cut in cuts:
					_wall_seg(b, horiz, fixed, cut[0], cut[1], y + DOOR_H, b1 - DOOR_H, t, bm)
		else:
			segs = [[lo, hi]]
		for s in segs:
			_wall_seg(b, horiz, fixed, s[0], s[1], y + b0, b1 - b0, t, bm)

static func _wall_seg(b: Bake, horiz: bool, fixed: float, a0: float, a1: float,
		y0: float, h: float, t: float, mat: Material) -> void:
	if a1 - a0 < 0.02 or h < 0.02:
		return
	var mid: float = (a0 + a1) * 0.5
	var solid: bool = not (mat is StandardMaterial3D and (mat as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
	var group: String = "hull" if solid else "glass"
	if horiz:
		b.box(Vector3(mid, y0 + h * 0.5, fixed), Vector3(a1 - a0, h, t), mat, group, Vector3.ZERO, solid)
		if not solid:
			b.collider(Vector3(mid, y0 + h * 0.5, fixed), Vector3(a1 - a0, h, t))
	else:
		b.box(Vector3(fixed, y0 + h * 0.5, mid), Vector3(t, h, a1 - a0), mat, group, Vector3.ZERO, solid)
		if not solid:
			b.collider(Vector3(fixed, y0 + h * 0.5, mid), Vector3(t, h, a1 - a0))

# ------------------------------------------------------------------------------ high iron

## A tapered lattice tower — derrick, drill mast, crane pedestal, flare tower. `bays` bands
## of X-bracing between four corner legs, tapering from `base` to `top` footprint.
static func lattice(b: Bake, cx: float, cz: float, base_y: float, top_y: float,
		base_half: float, top_half: float, bays: int, leg_t: float = 0.42,
		mat: Material = null, group: String = "hull") -> void:
	var m: Material = mat if mat != null else MatLib.rust_steel()
	var h: float = top_y - base_y
	if h <= 0.0 or bays < 1:
		return
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for i in range(4):
		var a2: Vector2 = corners[i]
		var a := Vector3(cx + a2.x * base_half, base_y, cz + a2.y * base_half)
		var c := Vector3(cx + a2.x * top_half, top_y, cz + a2.y * top_half)
		b.member(a, c, leg_t, m, group)
	for k in range(bays + 1):
		var t: float = float(k) / float(bays)
		var y: float = lerpf(base_y, top_y, t)
		var half: float = lerpf(base_half, top_half, t)
		# Horizontal girt ring.
		for i in range(4):
			var p: Vector2 = corners[i]
			var q: Vector2 = corners[(i + 1) % 4]
			# The girts and braces carry the CALLER'S group. They used to be hard-coded
			# "detail", which meant that past DETAIL_DRAW_M a derrick lost everything except
			# its four corner legs — DEEPWELL read as four thin sticks from SALTLINE-0, which
			# is the exact opposite of "the tallest thing in the world by a clear margin".
			b.member(Vector3(cx + p.x * half, y, cz + p.y * half),
				Vector3(cx + q.x * half, y, cz + q.y * half), leg_t * 0.62, m, group)
		if k == bays:
			continue
		# X-brace each face of this bay.
		var t2: float = float(k + 1) / float(bays)
		var y2: float = lerpf(base_y, top_y, t2)
		var half2: float = lerpf(base_half, top_half, t2)
		for i in range(4):
			var p2: Vector2 = corners[i]
			var q2: Vector2 = corners[(i + 1) % 4]
			b.member(Vector3(cx + p2.x * half, y, cz + p2.y * half),
				Vector3(cx + q2.x * half2, y2, cz + q2.y * half2), leg_t * 0.5, m, group)
			b.member(Vector3(cx + q2.x * half, y, cz + q2.y * half),
				Vector3(cx + p2.x * half2, y2, cz + p2.y * half2), leg_t * 0.5, m, group)

## A pedestal crane: column, house, and a lattice boom laid out at `boom_yaw` / `boom_pitch`.
static func crane(b: Bake, base: Vector3, column_h: float, boom_len: float,
		boom_yaw_deg: float, boom_pitch_deg: float = 26.0) -> void:
	var steel: Material = MatLib.rust_steel()
	b.cyl(base + Vector3(0, column_h * 0.5, 0), 1.35, column_h, steel, "hull", Vector3.ZERO, 1.05, 12, true)
	var house_y: float = base.y + column_h + 1.5
	b.box(Vector3(base.x, house_y, base.z), Vector3(4.2, 3.0, 3.4), MatLib.hazard_stripe(), "hull",
		Vector3(0, deg_to_rad(boom_yaw_deg), 0), true)
	# Cab glass on the boom side.
	var yaw: float = deg_to_rad(boom_yaw_deg)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	b.box(Vector3(base.x, house_y + 0.3, base.z) + fwd * 2.15, Vector3(2.6, 1.6, 0.12),
		MatLib.glass(Color(0.5, 0.6, 0.62)), "glass", Vector3(0, yaw, 0))
	var pitch: float = deg_to_rad(boom_pitch_deg)
	var root := Vector3(base.x, house_y, base.z) + fwd * 1.8
	var tip: Vector3 = root + fwd * (boom_len * cos(pitch)) + Vector3(0, boom_len * sin(pitch), 0)
	# Four-chord boom, tapering.
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var up := Vector3(0, 1, 0)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			# Chords are "hull": a crane boom is a silhouette element from a neighbouring rig.
			b.member(root + side * (sx * 0.8) + up * (sy * 0.7),
				tip + side * (sx * 0.32) + up * (sy * 0.3), 0.2, steel, "hull")
	var bays: int = maxi(3, int(boom_len / 4.0))
	for i in range(bays + 1):
		var t: float = float(i) / float(bays)
		var p: Vector3 = root.lerp(tip, t)
		var hw: float = lerpf(0.8, 0.32, t)
		var hh: float = lerpf(0.7, 0.3, t)
		for sy in [-1.0, 1.0]:
			b.member(p + side * -hw + up * (sy * hh), p + side * hw + up * (sy * hh), 0.1, steel, "detail")
		for sx in [-1.0, 1.0]:
			b.member(p + side * (sx * hw) + up * -hh, p + side * (sx * hw) + up * hh, 0.1, steel, "detail")
	# Hook block on a slack fall.
	b.member(tip, tip - Vector3(0, 5.5, 0), 0.05, MatLib.dark_metal(), "detail")
	b.box(tip - Vector3(0, 6.0, 0), Vector3(0.7, 0.9, 0.5), MatLib.dark_metal(), "detail")

## Flare boom: a lattice arm cantilevered out over the sea with a tip burner.
static func flare_boom(b: Bake, base: Vector3, yaw_deg: float, length: float,
		pitch_deg: float = 17.0) -> void:
	var yaw: float = deg_to_rad(yaw_deg)
	var pitch: float = deg_to_rad(pitch_deg)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var tip: Vector3 = base + fwd * (length * cos(pitch)) + Vector3(0, length * sin(pitch), 0)
	var steel: Material = MatLib.rust_steel()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			b.member(base + side * (sx * 1.4) + Vector3(0, sy * 1.2, 0),
				tip + side * (sx * 0.5) + Vector3(0, sy * 0.45, 0), 0.24, steel, "hull")
	var bays: int = maxi(4, int(length / 4.5))
	for i in range(bays + 1):
		var t: float = float(i) / float(bays)
		var p: Vector3 = base.lerp(tip, t)
		var hw: float = lerpf(1.4, 0.5, t)
		var hh: float = lerpf(1.2, 0.45, t)
		for sy in [-1.0, 1.0]:
			b.member(p + side * -hw + Vector3(0, sy * hh, 0), p + side * hw + Vector3(0, sy * hh, 0), 0.11, steel, "detail")
		for sx in [-1.0, 1.0]:
			b.member(p + side * (sx * hw) + Vector3(0, -hh, 0), p + side * (sx * hw) + Vector3(0, hh, 0), 0.11, steel, "detail")
	# Gas line along the top chord, and the burner tip.
	b.member(base + Vector3(0, 1.3, 0), tip + Vector3(0, 0.5, 0), 0.38, MatLib.galvanized(), "detail")
	b.cyl(tip + Vector3(0, 1.1, 0), 0.75, 2.4, MatLib.dark_metal(), "detail", Vector3.ZERO, 0.95)

## Helipad: an octagonal deck on a truss frame, painted circle, perimeter safety net.
## `radius` is the deck's circumradius — 12 m is a genuinely large pad (24 m across; a real
## S-92 pad is 22.2 m). Returns the walking surface Y.
static func helipad(b: Bake, center: Vector3, radius: float, support_from_y: float) -> float:
	var deck_mat: Material = MatLib.deck_plate()
	var steel: Material = MatLib.rust_steel()
	var y: float = center.y
	var seg: int = 8
	# Deck: one 8-sided plate built as a shallow cylinder, plus a box collider grid so the
	# player walks on a real surface rather than a cylinder proxy.
	b.cyl(Vector3(center.x, y - 0.16, center.z), radius, 0.32, deck_mat, "hull", Vector3.ZERO, -1.0, seg)
	var cell: float = radius * 2.0 / 5.0
	for ix in range(5):
		for iz in range(5):
			var px: float = center.x - radius + cell * (ix + 0.5)
			var pz: float = center.z - radius + cell * (iz + 0.5)
			if Vector2(px - center.x, pz - center.z).length() > radius - 0.1:
				continue
			b.collider(Vector3(px, y - 0.16, pz), Vector3(cell, 0.32, cell))
	# The painted circle and the H — flat plates 2 cm proud so they never z-fight.
	b.cyl(Vector3(center.x, y + 0.02, center.z), radius * 0.62, 0.04,
		MatLib.flat(Color(0.86, 0.86, 0.83)), "detail", Vector3.ZERO, -1.0, 24)
	b.cyl(Vector3(center.x, y + 0.03, center.z), radius * 0.56, 0.04,
		MatLib.flat(Color(0.16, 0.18, 0.19)), "detail", Vector3.ZERO, -1.0, 24)
	var hb: Material = MatLib.flat(Color(0.88, 0.88, 0.85))
	b.box(Vector3(center.x - radius * 0.22, y + 0.05, center.z), Vector3(0.9, 0.05, radius * 0.72), hb, "detail")
	b.box(Vector3(center.x + radius * 0.22, y + 0.05, center.z), Vector3(0.9, 0.05, radius * 0.72), hb, "detail")
	b.box(Vector3(center.x, y + 0.05, center.z), Vector3(radius * 0.44, 0.05, 0.9), hb, "detail")
	# Perimeter safety net: the pad's rim drops away, so this is a skirt, not a rail —
	# it must NOT collide, or it becomes an invisible fence around a landing deck.
	for i in range(seg * 3):
		var a0: float = TAU * float(i) / float(seg * 3)
		var a1: float = TAU * float(i + 1) / float(seg * 3)
		var p0 := Vector3(center.x + cos(a0) * radius, y - 0.2, center.z + sin(a0) * radius)
		var p1 := Vector3(center.x + cos(a1) * (radius + 1.5), y - 0.85, center.z + sin(a1) * (radius + 1.5))
		b.member(p0, p1, 0.07, MatLib.galvanized(), "detail")
		b.member(p1, Vector3(center.x + cos(a1) * radius, y - 0.2, center.z + sin(a1) * radius), 0.05, MatLib.galvanized(), "detail")
	# Support frame down to the deck below.
	for i in range(seg):
		var a: float = TAU * float(i) / float(seg) + PI / float(seg)
		var foot := Vector3(center.x + cos(a) * radius * 0.55, support_from_y, center.z + sin(a) * radius * 0.55)
		b.member(Vector3(center.x + cos(a) * radius * 0.92, y - 0.35, center.z + sin(a) * radius * 0.92), foot, 0.34, steel, "hull")
	b.cyl(Vector3(center.x, (y + support_from_y) * 0.5, center.z), 1.5, y - support_from_y,
		steel, "hull", Vector3.ZERO, -1.0, 10, true)
	return y

## Boat landing: a stepped platform down at the swell with fenders and a ladder up.
## `top_y` is the deck it hangs from. Returns the landing's walking surface Y.
static func boat_landing(b: Bake, center: Vector3, face_yaw_deg: float, top_y: float,
		landing_y: float = 1.6, width: float = 8.0, depth: float = 4.0) -> float:
	var yaw: float = deg_to_rad(face_yaw_deg)
	var rot := Vector3(0, yaw, 0)
	var steel: Material = MatLib.rust_steel()
	b.box(Vector3(center.x, landing_y - 0.11, center.z), Vector3(width, 0.22, depth),
		MatLib.grating(), "hull", rot, true)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	# Fender tubes down the outboard face, into the water.
	for i in range(5):
		var t: float = -0.5 + float(i) / 4.0
		var p: Vector3 = center + side * (t * (width - 0.8)) + fwd * (depth * 0.5)
		b.cyl(Vector3(p.x, landing_y - 2.2, p.z), 0.24, 5.0, MatLib.dark_metal(), "detail")
	# Hangers back up to the deck above.
	for sgn in [-1.0, 1.0]:
		var p2: Vector3 = center + side * (sgn * (width * 0.5 - 0.3))
		b.member(p2 + Vector3(0, landing_y, 0), Vector3(p2.x, top_y, p2.z), 0.2, steel, "detail")
		b.member(p2 + fwd * (depth * 0.5) + Vector3(0, landing_y, 0),
			Vector3(p2.x, top_y, p2.z), 0.16, steel, "detail")
	rail_rect(b, Rect2(center.x - width * 0.5, center.z - depth * 0.5, width, depth), landing_y,
		[["n", center.x - 1.2, center.x + 1.2]], 0.12)
	return landing_y

## A ladder cage — the vertical link between two decks where a stair will not fit.
static func ladder(b: Bake, foot: Vector3, top_y: float, face_yaw_deg: float = 0.0) -> void:
	var yaw: float = deg_to_rad(face_yaw_deg)
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var galv: Material = MatLib.galvanized()
	var h: float = top_y - foot.y
	if h < 0.5:
		return
	for sgn in [-1.0, 1.0]:
		b.box(foot + side * (sgn * 0.28) + Vector3(0, h * 0.5, 0), Vector3(0.07, h, 0.07), galv, "detail")
	var rungs: int = int(h / 0.3)
	for i in range(rungs):
		b.box(foot + Vector3(0, 0.3 * (i + 1), 0), Vector3(0.62, 0.045, 0.045), galv, "detail",
			Vector3(0, yaw, 0))
	# Hoop cage from 2.2 m up.
	var hoops: int = maxi(0, int((h - 2.2) / 0.9))
	for i in range(hoops):
		b.cyl(foot + Vector3(0, 2.2 + 0.9 * i, 0), 0.42, 0.06, galv, "detail",
			Vector3(deg_to_rad(90), 0, 0), -1.0, 10)
	# Climbing is not simulated: the player takes the stairs. This is a shape, and the
	# collider keeps them from walking through it.
	b.collider(foot + Vector3(0, h * 0.5, 0), Vector3(0.7, h, 0.18), Vector3(0, yaw, 0))

# --------------------------------------------------------------------------------- pipework

## An external pipe run — the thing that makes a rig read as a machine rather than a
## building. `path` is a list of local points; elbows are implied.
static func pipe_run(b: Bake, path: Array, radius: float = 0.28, mat: Material = null) -> void:
	var m: Material = mat if mat != null else MatLib.galvanized()
	for i in range(path.size() - 1):
		b.member(path[i], path[i + 1], radius * 2.0, m, "detail")
		if i > 0:
			b.cyl(path[i], radius * 1.15, radius * 2.3, m, "detail", Vector3.ZERO, -1.0, 8)

## A rack of parallel pipes on trestles — pipe deck, process alley, the cantilever run.
static func pipe_rack(b: Bake, a: Vector3, c: Vector3, pipes: int = 5, spread: float = 2.6) -> void:
	var d: Vector3 = c - a
	var yaw: float = atan2(d.x, d.z)
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var span: float = d.length()
	for i in range(pipes):
		var t: float = -0.5 + (float(i) + 0.5) / float(pipes)
		var off: Vector3 = side * (t * spread)
		var m: Material = MatLib.galvanized() if i % 2 == 0 else MatLib.rust_steel()
		b.member(a + off, c + off, 0.34 if i % 3 else 0.5, m, "detail")
	var trestles: int = maxi(2, int(span / 5.0))
	for i in range(trestles + 1):
		var t2: float = float(i) / float(trestles)
		var p: Vector3 = a.lerp(c, t2)
		b.box(p + Vector3(0, -0.55, 0), Vector3(spread + 0.8, 0.24, 0.3), MatLib.rust_steel(), "detail",
			Vector3(0, yaw, 0))
		for sgn in [-1.0, 1.0]:
			b.member(p + side * (sgn * (spread * 0.5 + 0.3)) + Vector3(0, -0.55, 0),
				p + side * (sgn * (spread * 0.5 + 0.3)) + Vector3(0, -2.2, 0), 0.14, MatLib.rust_steel(), "detail")

## Stacked shipping containers — instant industrial mass and a legible sense of scale.
static func containers(b: Bake, base: Vector3, cols: int, rows: int, yaw_deg: float = 0.0,
		tints: Array = []) -> void:
	# THREE tints, not five. MatLib.container() caches per colour, so every extra tint is a
	# separate material and therefore a separate draw chunk for the sake of one crate.
	var palette: Array = tints if not tints.is_empty() else [
		Color(0.55, 0.24, 0.18), Color(0.24, 0.36, 0.42), Color(0.48, 0.46, 0.30)]
	var yaw: float = deg_to_rad(yaw_deg)
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var cw: float = 6.1
	var ch: float = 2.6
	var cd: float = 2.44
	for r in range(rows):
		for c in range(cols):
			# Deliberately irregular: the top row is short and offset, so a stack never
			# reads as a solid extruded block.
			if r > 0 and (c + r) % 3 == 0:
				continue
			var off: Vector3 = side * ((float(c) - float(cols - 1) * 0.5) * (cd + 0.14))
			var jitter: float = 0.0 if r == 0 else (0.16 if (c % 2) == 0 else -0.12)
			var p: Vector3 = base + off + Vector3(0, ch * (r + 0.5), 0) + side * jitter
			var tint: Color = palette[(c * 3 + r * 5) % palette.size()]
			b.box(p, Vector3(cw, ch, cd), MatLib.container(tint), "hull",
				Vector3(0, yaw + (0.0 if r == 0 else deg_to_rad(2.5 * (1 if c % 2 else -1))), 0), true)

## A LIT FIXTURE THAT READS FROM THE NEXT RIG. An OmniLight3D at 22 m range lights nothing a
## neighbour can see — at 160-415 m what reads is EMISSIVE GEOMETRY, and the first night
## skyline came back with three completely dark platforms because there was none. So every
## lamp gets a small unshaded emissive lens in the "hull" group, which is never range-culled.
## The light itself still does the local work; this is the part the horizon sees.
static func lamp_lens(b: Bake, pos: Vector3, colour: Color, size: float = 0.55,
		energy: float = 5.0) -> void:
	b.box(pos, Vector3(size * 2.2, size * 0.7, size), MatLib.glowing(colour, energy), "lamp")

## A CONTINUOUS LED COVE — the strip lighting that does most of the work in a modern
## interior and costs nothing per frame, because it is geometry and not a Light3D. Runs
## between two local points at `thick` square. Use these liberally; use OmniLight3D sparingly.
static func led_cove(b: Bake, a: Vector3, c: Vector3, colour: Color = Color(0.55, 0.82, 1.0),
		thick: float = 0.09, energy: float = 3.2) -> void:
	b.member(a, c, thick, MatLib.glowing(colour, energy), "lamp")

## A ring of LED cove — the halo under a balcony edge or around a column.
static func led_ring(b: Bake, centre: Vector3, radius: float, colour: Color = Color(0.55, 0.82, 1.0),
		segs: int = 32, thick: float = 0.09, energy: float = 3.2,
		arc_from: float = 0.0, arc_to: float = TAU) -> void:
	var arc_span: float = arc_to - arc_from
	var arc_n: int = maxi(2, int(round(float(segs) * arc_span / TAU)))
	for i in range(arc_n):
		var a0: float = arc_from + arc_span * float(i) / float(arc_n)
		var a1: float = arc_from + arc_span * float(i + 1) / float(arc_n)
		b.member(centre + Vector3(cos(a0) * radius, 0, sin(a0) * radius),
			centre + Vector3(cos(a1) * radius, 0, sin(a1) * radius), thick,
			MatLib.glowing(colour, energy), "lamp")

# ------------------------------------------------------------------------- round geometry

## AN ANNULAR DECK — the mezzanine ring that wraps an atrium. Built from wedge boxes so it
## has real box colliders rather than a cylinder proxy the player would slide off.
static func ring_deck(b: Bake, centre: Vector3, r_in: float, r_out: float, thick: float = 0.28,
		mat: Material = null, segs: int = 32, arc_from: float = 0.0, arc_to: float = TAU) -> void:
	var m: Material = mat if mat != null else MatLib.checker_plate()
	var span: float = arc_to - arc_from
	var n: int = maxi(3, int(round(float(segs) * span / TAU)))
	var mid_r: float = (r_in + r_out) * 0.5
	var width: float = r_out - r_in
	# SIZED FOR THE OUTER RADIUS, NOT THE MIDDLE. A wedge cut to the mid-radius chord is too
	# SHORT everywhere outside mid_r, so the ring develops triangular gaps toward its rim —
	# and the probe found exactly that by dropping a ray through the G3 gallery at r 13 and
	# hitting nothing. Sizing for r_out closes them and instead OVERLAPS toward r_in, where
	# two coplanar tops would z-fight; alternate wedges are dropped 4 mm so one always wins.
	# 4 mm is a quarter of a shoe sole and the capsule never notices it.
	for i in range(n):
		var a: float = arc_from + span * (float(i) + 0.5) / float(n)
		var seg_len: float = 2.0 * r_out * tan(span / float(n) * 0.5) + 0.08
		var sink: float = 0.0 if i % 2 == 0 else 0.004
		var p: Vector3 = centre + Vector3(cos(a) * mid_r, -thick * 0.5 - sink, sin(a) * mid_r)
		b.box(p, Vector3(width, thick, seg_len), m, "hull", Vector3(0, -a, 0), true)

## A RING RAIL — glass balustrade with a capped top rail, the balcony edge of an atrium.
static func ring_rail(b: Bake, centre: Vector3, radius: float, segs: int = 32,
		glassy: bool = true, arc_from: float = 0.0, arc_to: float = TAU) -> void:
	var span: float = arc_to - arc_from
	var n: int = maxi(3, int(round(float(segs) * span / TAU)))
	var cap: Material = MatLib.galvanized()
	var pane: Material = MatLib.glass(Color(0.66, 0.82, 0.88))
	for i in range(n):
		var a0: float = arc_from + span * float(i) / float(n)
		var a1: float = arc_from + span * float(i + 1) / float(n)
		var p0: Vector3 = centre + Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var p1: Vector3 = centre + Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var mid: Vector3 = (p0 + p1) * 0.5
		var seg_len: float = (p1 - p0).length() + 0.03
		var yaw: float = atan2(p1.x - p0.x, p1.z - p0.z)
		if glassy:
			b.box(mid + Vector3(0, RAIL_H * 0.5, 0), Vector3(0.05, RAIL_H - 0.08, seg_len),
				pane, "glass", Vector3(0, yaw, 0))
		b.box(mid + Vector3(0, RAIL_H, 0), Vector3(0.12, 0.09, seg_len), cap, "detail", Vector3(0, yaw, 0))
		b.box(mid + Vector3(0, 0.06, 0), Vector3(0.14, 0.12, seg_len), cap, "detail", Vector3(0, yaw, 0))
		b.collider(mid + Vector3(0, RAIL_H * 0.5 + 0.05, 0), Vector3(0.16, RAIL_H + 0.1, seg_len),
			Vector3(0, yaw, 0))

## A ring of box colliders standing in for a cylinder the player must not walk through.
static func ring_collider(b: Bake, centre: Vector3, radius: float, y0: float, y1: float,
		segs: int = 16) -> void:
	var h: float = y1 - y0
	for i in range(segs):
		var a: float = TAU * (float(i) + 0.5) / float(segs)
		var seg_len: float = 2.0 * radius * tan(PI / float(segs)) + 0.05
		b.collider(centre + Vector3(cos(a) * radius, y0 + h * 0.5 - centre.y, sin(a) * radius),
			Vector3(0.4, h, seg_len), Vector3(0, -a, 0))

## THE COLUMN AQUARIUM. A glass cylinder of `radius` running from y0 to y1 — floor-to-roof
## through every gallery of an atrium — with still water inside, a reef bed on the floor, a
## kelp column, a steel base ring and a crown ring. This is a HERO piece: 40 radial segments,
## because a 12-sided "cylinder" 10 m across reads as a hexagonal prism from the balcony.
static func column_tank(b: Bake, centre_xz: Vector2, radius: float, y0: float, y1: float,
		segs: int = 40) -> void:
	var cx: float = centre_xz.x
	var cz: float = centre_xz.y
	var h: float = y1 - y0
	var mid: float = (y0 + y1) * 0.5
	var glass: Material = MatLib.glass(Color(0.74, 0.88, 0.92))
	# Water first (inside), then the glass shell over it.
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.18, 0.55, 0.62, 0.52)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.1
	water.metallic = 0.05
	water.emission_enabled = true
	water.emission = Color(0.16, 0.52, 0.58)
	water.emission_energy_multiplier = 0.5
	water.cull_mode = BaseMaterial3D.CULL_DISABLED
	b.cyl(Vector3(cx, mid, cz), radius - 0.13, h - 0.3, water, "glass", Vector3.ZERO, -1.0, segs)
	b.cyl(Vector3(cx, mid, cz), radius, h, glass, "glass", Vector3.ZERO, -1.0, segs)
	ring_collider(b, Vector3(cx, 0, cz), radius + 0.05, y0, y1, 20)
	# Base plinth and crown ring — the steel that says this holds a thousand tonnes of water.
	b.cyl(Vector3(cx, y0 - 0.35, cz), radius + 0.55, 0.9, MatLib.dark_metal(), "hull", Vector3.ZERO, -1.0, segs, true)
	b.cyl(Vector3(cx, y0 + 0.3, cz), radius + 0.18, 0.5, MatLib.galvanized(), "hull", Vector3.ZERO, -1.0, segs)
	b.cyl(Vector3(cx, y1 - 0.25, cz), radius + 0.4, 0.7, MatLib.dark_metal(), "hull", Vector3.ZERO, -1.0, segs)
	# THE CORAL CORE. A single organic rock column rises the height of the tank — stacked,
	# offset, rotated drums so no two silhouettes repeat — and the coral grows OFF it in
	# clusters: fans, fingers and dome heads in reef colours, denser near the lit top. The
	# owner's call, replacing the loose rod forest: one strong vertical the eye can follow
	# from any gallery. Sand bed below, three kelp strands at the rim for movement.
	b.cyl(Vector3(cx, y0 + 0.6, cz), radius - 0.5, 1.0, MatLib.flat(Color(0.52, 0.50, 0.42)), "hull", Vector3.ZERO, -1.0, segs)
	var rock: Material = MatLib.flat(Color(0.30, 0.28, 0.25))
	var seg_n: int = 8
	var core_h: float = h - 1.8
	for i in range(seg_n):
		var t0: float = float(i) / float(seg_n)
		var sh: float = core_h / float(seg_n) + 0.25
		var sr: float = lerpf(1.55, 0.75, t0) * (1.0 + 0.14 * float(i % 2))
		var off := Vector3(cos(float(i) * 2.1) * 0.28, 0, sin(float(i) * 2.1) * 0.28)
		b.cyl(Vector3(cx, y0 + 1.0 + core_h * t0 + sh * 0.5, cz) + off, sr, sh, rock, "hull",
			Vector3(deg_to_rad(4.0 * float(i % 3) - 4.0), float(i) * 0.8, 0), sr * lerpf(0.8, 1.1, fmod(float(i) * 0.61, 1.0)), 10)
	# (s60c: the s55 procedural core clusters and floor pucks are GONE — their i*2.4
	# placement was itself the helix the owner photographed ("don't just make it a
	# spiral"), and they sat proud of the rock hiding the real library colonies behind
	# them. tank_reef.gd owns every colony now; the palette stays for the bed + beds.)
	var corals: Array = [
		MatLib.flat(Color(0.92, 0.44, 0.50)), MatLib.flat(Color(0.95, 0.58, 0.25)),
		MatLib.glowing(Color(0.30, 0.85, 0.78), 0.9), MatLib.flat(Color(0.62, 0.42, 0.82)),
		MatLib.glowing(Color(0.85, 0.55, 0.75), 0.7)]
	# (s60c: the kelp "strands" — straight members bed-to-crown — read as vertical POLES
	# from every gallery and are gone on the owner's call. The tank's verticality now
	# belongs to the coral-covered core alone.)
	# THE PLANTED BED (s59) — the floor reads as a living reef, not a sand disc with six
	# pucks on it. ~34 pieces scattered by golden-angle jitter (never a grid), denser
	# toward the core, mixed forms and colours; plus encrusting patches up the rock so the
	# core reads grown-over, not stacked; plus interior light — a warm ring under the
	# crown that flatters the coral and a faint teal bed glow. ~120 primitives, baked
	# into the same chunks as the rest of the tank.
	var crust: Array = [MatLib.flat(Color(0.62, 0.55, 0.40)), MatLib.flat(Color(0.48, 0.52, 0.44)),
		MatLib.flat(Color(0.70, 0.48, 0.42))]
	for i4 in range(34):
		var fa4: float = float(i4) * 2.39996
		var t4: float = pow(fmod(float(i4) * 0.618, 1.0), 0.6)
		var fr4: float = lerpf(1.95, radius - 1.0, t4)
		var bp := Vector3(cx + cos(fa4) * fr4, y0 + 1.12, cz + sin(fa4) * fr4)
		var m4: Material = corals[i4 % corals.size()] if i4 % 4 != 3 else crust[i4 % crust.size()]
		match i4 % 4:
			0:
				b.cyl(bp, 0.16 + 0.14 * fmod(float(i4) * 0.41, 1.0), 0.34 + 0.3 * fmod(float(i4) * 0.77, 1.0),
					m4, "hull", Vector3(0, fa4, deg_to_rad(8.0)), 0.05, 6)
			1:
				b.box(bp + Vector3(0, 0.28, 0), Vector3(0.5 + 0.3 * float(i4 % 2), 0.55, 0.07), m4, "hull",
					Vector3(deg_to_rad(14.0), fa4 * 1.7, deg_to_rad(-9.0)))
			2:
				b.cyl(bp, 0.24 + 0.12 * float(i4 % 3), 0.22, m4, "hull", Vector3.ZERO, 0.16, 8)
			3:
				b.box(bp + Vector3(0, 0.10, 0), Vector3(0.42, 0.22, 0.36), m4, "hull",
					Vector3(deg_to_rad(6.0), fa4, 0))
	for i5 in range(9):
		var ea: float = float(i5) * 2.8 + 0.4
		var et: float = 0.1 + 0.8 * fmod(float(i5) * 0.71, 1.0)
		var er: float = lerpf(1.6, 0.85, et) + 0.05
		b.box(Vector3(cx + cos(ea) * er, y0 + 1.0 + (h - 1.8) * et, cz + sin(ea) * er),
			Vector3(0.55, 0.34, 0.14), crust[i5 % crust.size()], "hull",
			Vector3(deg_to_rad(20.0 * float(i5 % 2)), ea, deg_to_rad(75.0)))
	for i6 in range(6):
		var la: float = TAU * float(i6) / 6.0
		lamp_lens(b, Vector3(cx + cos(la) * (radius - 0.9), y1 - 1.3, cz + sin(la) * (radius - 0.9)),
			Color(1.0, 0.92, 0.78), 0.14, 2.4)
	led_ring(b, Vector3(cx, y0 + 0.95, cz), radius - 0.6, Color(0.30, 0.85, 0.78), 28, 0.06, 1.4)
	# THE HERO TIER (s59b). The first planted pass was honest and INVISIBLE: 0.2-0.5 m
	# pieces at the base of a 17 m water column vanish from ten metres away — the owner's
	# "looks like nothing changed", verbatim. Everything below is sized to read from the
	# dining bay and the galleries: branching coral TREES to 2.2 m, sea fans to 1.8 m,
	# barrel heads to a metre, a full-height kelp curtain, barnacle collars on the core,
	# glowing anemone beds. ~190 primitives, same bake chunks.
	# REUSE the palettes already in this tank — `corals` and `crust` above, `weed` below.
	# Materials are cache-keyed by exact colour/energy and chunks by material, and the
	# field's far budget sat at exactly 150/150: every novel colour here was +1 far chunk
	# (measured — the first hero cut landed at 159/150).
	# (s60: the procedural stick-trees and box-fans that stood here were REPLACED by the
	# real reef GLB species — tank_reef.gd plants coral_branch/brain/fan/plate/bubble,
	# reefmass, sponges, anemones and barnacle clusters through the bed and up the core.
	# The rock massing, kelp curtain, barnacle collars and glowing anemone beds below stay:
	# they are the substrate the real coral roots into.)
	# Barnacle collars — four crusted bands around the core, studded.
	var barn: Material = crust[0]
	for ci in range(4):
		var cy2: float = y0 + 2.2 + (h - 4.6) * float(ci) / 3.0
		var crr: float = lerpf(1.62, 0.92, float(ci) / 3.0)
		b.cyl(Vector3(cx, cy2, cz), crr + 0.10, 0.5, barn, "hull", Vector3.ZERO, -0.06, 12)
		for si in range(7):
			var sa2: float = TAU * float(si) / 7.0 + float(ci)
			b.cyl(Vector3(cx + cos(sa2) * (crr + 0.16), cy2 + 0.1 * float(si % 3 - 1), cz + sin(sa2) * (crr + 0.16)),
				0.07, 0.12, crust[1], "hull",
				Vector3(deg_to_rad(90.0) * cos(sa2), 0, deg_to_rad(90.0) * sin(sa2)), 0.02, 5)
	# Glowing anemone beds on the floor — the reference image's cyan accents, underwater.
	for ai in range(6):
		var aa2: float = float(ai) * 1.9 + 0.9
		var ar2: float = lerpf(2.4, radius - 1.4, fmod(float(ai) * 0.55, 1.0))
		var ap := Vector3(cx + cos(aa2) * ar2, y0 + 1.16, cz + sin(aa2) * ar2)
		b.cyl(ap, 0.34, 0.18, corals[2], "hull", Vector3.ZERO, 0.2, 8)
		for ni in range(5):
			var na2: float = TAU * float(ni) / 5.0 + aa2
			b.cyl(ap + Vector3(cos(na2) * 0.16, 0.2, sin(na2) * 0.16), 0.035, 0.3,
				corals[4], "hull",
				Vector3(deg_to_rad(16.0) * cos(na2), 0, deg_to_rad(16.0) * sin(na2)), 0.01, 5)

## A GLAZED LOOKOUT CABIN — the room you climb to. Solid sill, glass band, capped roof.
## opts:
##   "door":  side ("s"/"n"/"w"/"e") that gets a 1.2 m opening — without one the cabin is a
##            sealed glass box, which is exactly what the first three of these were.
##   "door_at": absolute coordinate of the door centre along that side (defaults to centre).
##   "floor": false when the cabin sits OVER a stair head — a floor slab there caps the
##            climb (MARROW's tower cab did precisely this).
static func lookout(b: Bake, rect: Rect2, y: float, h: float = 3.0, opts: Dictionary = {}) -> void:
	if bool(opts.get("floor", true)):
		deck(b, rect, y, 0.24, MatLib.checker_plate())
	var shell: Material = MatLib.painted_steel()
	var pane: Material = MatLib.glass(Color(0.58, 0.70, 0.74))
	var door: String = str(opts.get("door", ""))
	for side in ["s", "n", "w", "e"]:
		if side == door:
			var horiz: bool = side == "s" or side == "n"
			var c: float = float(opts.get("door_at", rect.get_center().x if horiz else rect.get_center().y))
			var lo: float = (rect.position.x if horiz else rect.position.y)
			var hi: float = (rect.end.x if horiz else rect.end.y)
			for seg in [[lo, c - 0.6], [c + 0.6, hi]]:
				if seg[1] - seg[0] < 0.05:
					continue
				var sub: Rect2 = Rect2(seg[0], rect.position.y, seg[1] - seg[0], rect.size.y) if horiz \
					else Rect2(rect.position.x, seg[0], rect.size.x, seg[1] - seg[0])
				_wall_band(b, sub, side, y, 0.0, 0.85, 0.2, shell)
				_wall_band(b, sub, side, y, 0.85, h - 0.35, 0.1, pane)
			# Header over the doorway, so the opening reads cut rather than missing.
			var hd: Rect2 = Rect2(c - 0.6, rect.position.y, 1.2, rect.size.y) if horiz \
				else Rect2(rect.position.x, c - 0.6, rect.size.x, 1.2)
			_wall_band(b, hd, side, y, 2.25, h - 0.35, 0.14, shell)
			_wall_band(b, rect, side, y, h - 0.35, h, 0.24, shell)
			continue
		_wall_band(b, rect, side, y, 0.0, 0.85, 0.2, shell)
		_wall_band(b, rect, side, y, 0.85, h - 0.35, 0.1, pane)
		_wall_band(b, rect, side, y, h - 0.35, h, 0.24, shell)
	deck(b, rect.grow(0.35), y + h + 0.16, 0.32, MatLib.deck_plate())
	led_cove(b, Vector3(rect.position.x + 0.2, y + h - 0.45, rect.position.y + 0.2),
		Vector3(rect.end.x - 0.2, y + h - 0.45, rect.position.y + 0.2), Color(0.60, 0.85, 1.0))
	led_cove(b, Vector3(rect.position.x + 0.2, y + h - 0.45, rect.end.y - 0.2),
		Vector3(rect.end.x - 0.2, y + h - 0.45, rect.end.y - 0.2), Color(0.60, 0.85, 1.0))

static func _wall_band(b: Bake, rect: Rect2, side: String, y: float, b0: float, b1: float,
		t: float, mat: Material) -> void:
	var solid: bool = not (mat is StandardMaterial3D and (mat as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
	var c: Vector2 = rect.get_center()
	var hh: float = b1 - b0
	var yc: float = y + (b0 + b1) * 0.5
	var grp: String = "hull" if solid else "glass"
	match side:
		"s": b.box(Vector3(c.x, yc, rect.position.y + t * 0.5), Vector3(rect.size.x, hh, t), mat, grp, Vector3.ZERO, solid)
		"n": b.box(Vector3(c.x, yc, rect.end.y - t * 0.5), Vector3(rect.size.x, hh, t), mat, grp, Vector3.ZERO, solid)
		"w": b.box(Vector3(rect.position.x + t * 0.5, yc, c.y), Vector3(t, hh, rect.size.y), mat, grp, Vector3.ZERO, solid)
		"e": b.box(Vector3(rect.end.x - t * 0.5, yc, c.y), Vector3(t, hh, rect.size.y), mat, grp, Vector3.ZERO, solid)
	if not solid:
		match side:
			"s": b.collider(Vector3(c.x, yc, rect.position.y + t * 0.5), Vector3(rect.size.x, hh, t))
			"n": b.collider(Vector3(c.x, yc, rect.end.y - t * 0.5), Vector3(rect.size.x, hh, t))
			"w": b.collider(Vector3(rect.position.x + t * 0.5, yc, c.y), Vector3(t, hh, rect.size.y))
			"e": b.collider(Vector3(rect.end.x - t * 0.5, yc, c.y), Vector3(t, hh, rect.size.y))

# ------------------------------------------------------------------------ process plant

## A PRESSURE VESSEL — separator, scrubber, surge drum. Dished ends, a skirt or saddles, a
## ladder up the side and a nozzle set. These are the objects that make a deck read as
## PROCESS rather than as a warehouse, and a rig needs a lot of them.
static func vessel(b: Bake, base: Vector3, radius: float, length: float,
		vertical: bool = true, yaw_deg: float = 0.0) -> void:
	var shell: Material = MatLib.galvanized()
	var steel: Material = MatLib.rust_steel()
	var yaw: float = deg_to_rad(yaw_deg)
	if vertical:
		b.cyl(base + Vector3(0, length * 0.5 + 0.9, 0), radius, length, shell, "hull", Vector3.ZERO, -1.0, 16, true)
		b.cyl(base + Vector3(0, length + 0.9 + radius * 0.35, 0), radius, radius * 0.7, shell, "hull", Vector3.ZERO, radius * 0.45, 16)
		# Skirt.
		b.cyl(base + Vector3(0, 0.45, 0), radius * 0.92, 0.9, steel, "hull", Vector3.ZERO, -1.0, 16, true)
		for i in range(4):
			var a: float = TAU * float(i) / 4.0 + yaw
			b.cyl(base + Vector3(cos(a) * (radius + 0.15), length * 0.35 + 0.9, sin(a) * (radius + 0.15)),
				0.16, 0.9, steel, "detail", Vector3(0, 0, deg_to_rad(90.0)))
		ladder(b, base + Vector3(radius + 0.35, 0.9, 0), base.y + length + 0.9, 90.0)
		b.cyl(base + Vector3(0, length + 0.9 + radius * 0.9, 0), 0.14, 1.4, steel, "detail")
	else:
		var side := Vector3(cos(yaw), 0, -sin(yaw))
		b.cyl(base + Vector3(0, radius + 0.9, 0), radius, length, shell, "hull",
			Vector3(0, yaw, deg_to_rad(90.0)), -1.0, 16, true)
		for sgn in [-1.0, 1.0]:
			var p: Vector3 = base + side * (sgn * length * 0.42) + Vector3(0, 0.45, 0)
			b.box(p, Vector3(radius * 1.6, 0.9, radius * 0.9), steel, "hull", Vector3(0, yaw, 0), true)
		for i in range(3):
			b.cyl(base + side * ((float(i) - 1.0) * length * 0.28) + Vector3(0, radius * 2.0 + 0.9, 0),
				0.14, 0.7, steel, "detail")

## A MACHINERY SKID — pump/compressor set on a base frame with a motor, guard and pipework.
static func skid(b: Bake, base: Vector3, size: Vector3, yaw_deg: float = 0.0) -> void:
	var yaw: float = deg_to_rad(yaw_deg)
	var rot := Vector3(0, yaw, 0)
	var steel: Material = MatLib.rust_steel()
	b.box(base + Vector3(0, 0.16, 0), Vector3(size.x, 0.32, size.z), MatLib.checker_plate(), "hull", rot, true)
	b.box(base + Vector3(0, 0.32 + size.y * 0.45, 0), Vector3(size.x * 0.6, size.y * 0.9, size.z * 0.7),
		MatLib.dark_metal(), "hull", rot, true)
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	b.cyl(base + side * (size.x * 0.33) + Vector3(0, 0.32 + size.y * 0.42, 0), size.y * 0.34, size.x * 0.34,
		MatLib.galvanized(), "hull", Vector3(0, yaw, deg_to_rad(90.0)), -1.0, 14)
	b.cyl(base + side * (-size.x * 0.36) + Vector3(0, 0.32 + size.y * 0.5, 0), size.y * 0.26, size.z * 0.5,
		steel, "detail", Vector3(deg_to_rad(90.0), yaw, 0))
	for sgn in [-1.0, 1.0]:
		b.member(base + side * (sgn * size.x * 0.5) + Vector3(0, 0.32, 0),
			base + side * (sgn * size.x * 0.5) + Vector3(0, size.y + 0.6, 0), 0.08, MatLib.galvanized(), "detail")

## A HEAT EXCHANGER BANK — stacked tube bundles with headers. Cheap, and instantly legible.
static func exchanger_bank(b: Bake, base: Vector3, count: int, length: float, yaw_deg: float = 0.0) -> void:
	var yaw: float = deg_to_rad(yaw_deg)
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	for i in range(count):
		var y: float = base.y + 0.9 + i * 1.35
		b.cyl(Vector3(base.x, y, base.z), 0.55, length, MatLib.galvanized(), "hull",
			Vector3(0, yaw, deg_to_rad(90.0)), -1.0, 14, true)
		for sgn in [-1.0, 1.0]:
			b.cyl(Vector3(base.x, y, base.z) + side * (sgn * length * 0.5), 0.68, 0.5, MatLib.dark_metal(), "detail",
				Vector3(0, yaw, deg_to_rad(90.0)), -1.0, 14)
	for sgn in [-1.0, 1.0]:
		b.member(Vector3(base.x, base.y, base.z) + side * (sgn * length * 0.42),
			Vector3(base.x, base.y + 0.9 + count * 1.35, base.z) + side * (sgn * length * 0.42),
			0.24, MatLib.rust_steel(), "hull")

## A VALVE MANIFOLD wall — the christmas tree of handwheels and gauges every rig has.
static func manifold(b: Bake, base: Vector3, width: float, height: float, yaw_deg: float = 0.0) -> void:
	var yaw: float = deg_to_rad(yaw_deg)
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var steel: Material = MatLib.galvanized()
	b.box(base + Vector3(0, height * 0.5, 0), Vector3(width, height, 0.3), MatLib.dark_metal(), "hull",
		Vector3(0, yaw, 0), true)
	var cols: int = maxi(2, int(width / 1.1))
	var rows: int = maxi(2, int(height / 1.2))
	for i in range(cols):
		for j in range(rows):
			var p: Vector3 = base + side * ((float(i) - float(cols - 1) * 0.5) * (width / float(cols))) \
				+ Vector3(0, 0.7 + j * (height - 1.0) / float(maxi(rows - 1, 1)), 0)
			b.cyl(p, 0.26, 0.16, MatLib.red_paint(), "detail", Vector3(deg_to_rad(90.0), yaw, 0), -1.0, 10)
			b.cyl(p, 0.06, 0.4, steel, "detail", Vector3(deg_to_rad(90.0), yaw, 0))
			if (i + j) % 3 == 0:
				b.cyl(p + Vector3(0, 0.45, 0), 0.17, 0.1, MatLib.flat(Color(0.86, 0.86, 0.8)), "detail",
					Vector3(deg_to_rad(90.0), yaw, 0), -1.0, 10)

## CABLE TRAY / conduit bank along a wall or under a deck — five parallel runs plus hangers.
static func cable_tray(b: Bake, a: Vector3, c: Vector3, hangers_to: float = -1000.0) -> void:
	var d: Vector3 = c - a
	var yaw: float = atan2(d.x, d.z)
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var m: Material = MatLib.galvanized()
	b.member(a, c, 0.5, MatLib.dark_metal(), "detail")
	for i in range(4):
		var off: Vector3 = side * (-0.16 + i * 0.105) + Vector3(0, 0.16, 0)
		b.member(a + off, c + off, 0.07, m, "detail")
	if hangers_to > -999.0:
		var n: int = maxi(1, int(d.length() / 4.0))
		for i in range(n + 1):
			var p: Vector3 = a.lerp(c, float(i) / float(n))
			b.member(p, Vector3(p.x, hangers_to, p.z), 0.06, m, "detail")

# --------------------------------------------------------------------------------- bridge

# --------------------------------------------------------------------------------- bridge

## THE BRIDGE SPAN. A Warren-truss link between two rig decks, in WORLD coordinates —
## it belongs to neither rig, so it is baked into its own `Bake` with an identity xform.
##
## Real rig bridges of this length (Valhall's is ~110 m) are deep, unsupported trusses with
## a walking deck slung inside the bottom chord. Ours run 120-150 m clear, so the truss is
## 4.6 m deep and the deck sits on the bottom chord.
static func bridge_span(b: Bake, a: Vector3, c: Vector3, width: float = 5.0,
		depth: float = 4.6, damage: float = 0.0) -> void:
	var d: Vector3 = c - a
	var flat := Vector2(d.x, d.z)
	var span: float = flat.length()
	if span < 4.0:
		return
	var yaw: float = atan2(flat.x, flat.y)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var steel: Material = MatLib.rust_steel()
	var galv: Material = MatLib.galvanized()
	var bays: int = maxi(6, int(span / 7.5))
	var hw: float = width * 0.5

	# Deck: segmented so it follows the (slight) grade and so colliders stay tight.
	for i in range(bays):
		var t0: float = float(i) / float(bays)
		var t1: float = float(i + 1) / float(bays)
		var p0: Vector3 = a.lerp(c, t0)
		var p1: Vector3 = a.lerp(c, t1)
		var mid: Vector3 = (p0 + p1) * 0.5
		var seg_len: float = (p1 - p0).length()
		var pitch: float = -atan2(p1.y - p0.y, (Vector2(p1.x, p1.z) - Vector2(p0.x, p0.z)).length())
		var rot := Vector3(pitch, yaw, 0)
		b.box(mid + Vector3(0, -0.11, 0), Vector3(width, 0.18, seg_len + 0.05), MatLib.grating(), "hull", rot)
		b.collider(mid + Vector3(0, -0.12, 0), Vector3(width, 0.22, seg_len + 0.1), rot)

	# Two side trusses: bottom chord at deck level, top chord `depth` above, verticals and
	# alternating diagonals. Plus a top lateral bracing ladder, which is what stops a long
	# span reading as two disconnected fences.
	for sgn in [-1.0, 1.0]:
		var off: Vector3 = side * (sgn * hw)
		b.member(a + off + Vector3(0, -0.25, 0), c + off + Vector3(0, -0.25, 0), 0.34, steel, "hull")
		b.member(a + off + Vector3(0, depth, 0), c + off + Vector3(0, depth, 0), 0.34, steel, "hull")
		for i in range(bays + 1):
			var t: float = float(i) / float(bays)
			var p: Vector3 = a.lerp(c, t) + off
			# Damage: near the far end, drop some web members so the span reads wounded.
			var wounded: bool = damage > 0.0 and t > 1.0 - damage and (i % 3) == 1
			if not wounded:
				b.member(p + Vector3(0, -0.25, 0), p + Vector3(0, depth, 0), 0.2, steel, "detail")
			if i == bays:
				continue
			var q: Vector3 = a.lerp(c, float(i + 1) / float(bays)) + off
			var diag_wounded: bool = damage > 0.0 and t > 1.0 - damage and (i % 4) == 2
			if not diag_wounded:
				if i % 2 == 0:
					b.member(p + Vector3(0, -0.25, 0), q + Vector3(0, depth, 0), 0.16, steel, "detail")
				else:
					b.member(p + Vector3(0, depth, 0), q + Vector3(0, -0.25, 0), 0.16, steel, "detail")
		# Handrail inside the truss, at hand height, and the guard slab behind it.
		b.member(a + off + Vector3(0, RAIL_H, 0), c + off + Vector3(0, RAIL_H, 0), 0.07, galv, "detail")
		var mid_all: Vector3 = (a + c) * 0.5 + off
		var pitch_all: float = -atan2(d.y, span)
		b.collider(mid_all + Vector3(0, depth * 0.5, 0),
			Vector3(0.16, depth + 0.6, span), Vector3(pitch_all, yaw, 0))
	# Top lateral bracing.
	for i in range(bays):
		var t0b: float = float(i) / float(bays)
		var t1b: float = float(i + 1) / float(bays)
		var p0b: Vector3 = a.lerp(c, t0b) + Vector3(0, depth, 0)
		var p1b: Vector3 = a.lerp(c, t1b) + Vector3(0, depth, 0)
		b.member(p0b - side * hw, p1b + side * hw, 0.13, steel, "detail")
		b.member(p0b + side * hw, p1b - side * hw, 0.13, steel, "detail")
		b.member(p0b - side * hw, p0b + side * hw, 0.15, steel, "detail")
	# Portal frames at each end — the visual "gateway" that tells you a bridge starts here.
	for endp in [a, c]:
		b.member(endp - side * (hw + 0.25) + Vector3(0, -0.4, 0), endp - side * (hw + 0.25) + Vector3(0, depth + 0.8, 0), 0.45, steel, "hull")
		b.member(endp + side * (hw + 0.25) + Vector3(0, -0.4, 0), endp + side * (hw + 0.25) + Vector3(0, depth + 0.8, 0), 0.45, steel, "hull")
		b.member(endp - side * (hw + 0.25) + Vector3(0, depth + 0.8, 0), endp + side * (hw + 0.25) + Vector3(0, depth + 0.8, 0), 0.45, steel, "hull")

## A landing apron: the short deck that carries a bridge's end onto a rig, so the player
## never has to step over a gap between two independently-authored structures.
static func bridge_apron(b: Bake, at: Vector3, yaw_deg: float, width: float, reach: float) -> void:
	var yaw: float = deg_to_rad(yaw_deg)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	# The apron OVERLAPS the deck by 1.5 m and sits 8 mm BELOW its surface: the owner-visible
	# "gap at the rim + flicker where it meets" was this plate ending exactly at the rim line
	# (any placement error reads as a slot) while running exactly coplanar with whatever it
	# did touch. 8 mm below deck, 12 mm above the truss deck: continuous underfoot, coplanar
	# with nothing.
	var mid: Vector3 = at + fwd * ((reach - 1.5) * 0.5)
	b.box(mid + Vector3(0, -0.128, 0), Vector3(width, 0.24, reach + 1.5), MatLib.checker_plate(), "hull",
		Vector3(0, yaw, 0), true)
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	for sgn in [-1.0, 1.0]:
		var off: Vector3 = side * (sgn * width * 0.5)
		b.member(at + off + Vector3(0, RAIL_H, 0), at + fwd * reach + off + Vector3(0, RAIL_H, 0),
			0.07, MatLib.galvanized(), "detail")
		b.collider(mid + off + Vector3(0, RAIL_H * 0.5, 0), Vector3(0.14, RAIL_H + 0.2, reach),
			Vector3(0, yaw, 0))
