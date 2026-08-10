extends Node3D
## THE FIELD — SALTLINE-0's three neighbours, the bridges that chain them, and the one place
## that owns where any of it is in the world.
##
## The field is a LINE, not a cluster. The player crosses it in strict order:
##
##     SALTLINE-0  ──B1──▶  MARROW  ──B2──▶  THE ANCHORAGE  ──B3──▶  DEEPWELL
##     (0, 0, 0)            (-62, 148)       (58, 262)              (0, 415)
##       unchanged          industrial/farm  residential/luxury     the Bloom drill
##       161 m               166 m             164 m
##
## RIG ORIGINS ARE FIXED CONSTANTS AND MUST STAY THAT WAY. `save_manager._harvest_key()`
## keys harvest state by "%.2f,%.2f,%.2f" of a node's absolute global_position, so a rig
## placed by anything runtime-dependent — a seed, a load order, a random bearing — silently
## loses its own save state the next time it moves by a centimetre.
##
## BEARINGS. Each rig carries its own yaw so the skyline is not four squares in a row. They
## also decide which edge each bridge meets, which is why the attach points in rig_two /
## rig_three / rig_four are chosen against these numbers and not independently.
##
## DRAW-CALL POSTURE. Everything here is built through KIT.Bake, which batches by
## (material, group, 48 m cell) at build time. Three whole rigs plus three bridges land in
## the low tens of draw calls, against ~2,000 if they were authored the way rig 1 is. See
## the header of rig_kit.gd; `tests/rig_field_probe.gd` measures the actual number and fails
## if it drifts.

const KIT := preload("res://scripts/world/rig_kit.gd")
const RIG_TWO := preload("res://scripts/world/rig_two.gd")
const RIG_THREE := preload("res://scripts/world/rig_three.gd")
const RIG_FOUR := preload("res://scripts/world/rig_four.gd")

## Origin and bearing per rig. Distances between consecutive origins: 161.2 / 166.4 / 163.6 m
## — inside the 140-170 m the brief specifies, so every rig reads at full detail from its
## neighbours and the whole line fits in one frame from SALTLINE-0's high iron.
const MARROW_ORIGIN := Vector3(-62.0, 0.0, 148.0)
const MARROW_YAW: float = -16.0
const ANCHORAGE_ORIGIN := Vector3(58.0, 0.0, 262.0)
const ANCHORAGE_YAW: float = 10.0
const DEEPWELL_ORIGIN := Vector3(0.0, 0.0, 415.0)
const DEEPWELL_YAW: float = -6.0

## Where bridge 1 leaves SALTLINE-0. This is the NORTH-WEST CORNER GAP in rig 1's deck rail:
## rig_builder's north rail runs x -26..26 at z 19.8, so x -30..-26 is open by design ("gaps
## at corners — the sea is reachable, deliberately"). Landing there means RIG 1 IS NOT
## TOUCHED — no rail is cut, no deck is edited, rig_builder.gd is not opened.
const RIG_ONE_EXIT := Vector3(-28.0, 18.0, 20.0)

## How far out from each deck rim the truss starts. The apron covers the gap, and its top
## face is exactly flush with the deck it springs from.
const APRON_REACH: float = 3.0
const BRIDGE_WIDTH: float = 5.0
const BRIDGE_DEPTH: float = 4.6

## Bridges are CONNECTED at start, on the owner's call, so the whole field is explorable
## from the first session. Progression gating (each span damaged and repairable) is the next
## pass; `damage` here is cosmetic only — dropped web members near the far end, worst on the
## final span, so the story reads even while every span is walkable.
const SPAN_DAMAGE := [0.10, 0.16, 0.34]

var stats: Dictionary = {}

## THE FIELD IS DARK UNTIL THE RIG HAS POWER. Every emissive fixture across the three new
## platforms — cove strips, lamp lenses, mast beacons, the aquarium's tank light — is built
## into RigKit's "lamp" group, which flush() emits as its own chunks and starts hidden. This
## node flips them, all at once, off rig 1's existing main breaker.
##
## That is deliberate wiring, not a shortcut: `topside_floodlights` is the circuit Breaker
## 4-A closes at the end of the cold open, so the moment the player restores power to
## SALTLINE-0 the whole field comes up on the horizon. Per-rig breakers are a later pass —
## filed in KNOWN_ISSUES rather than faked here.
const LIGHT_CIRCUIT: String = "topside_floodlights"

var _lamp_meshes: Array[MeshInstance3D] = []
var _field_lights: Array[OmniLight3D] = []
var _lit: bool = false

func _wire_power() -> void:
	_collect_lamps(self)
	# Bloom lights are NOT in this set: the fissure is a phenomenon, not a fixture, and it
	# glows whether or not anybody has thrown a breaker.
	for l in _field_lights:
		l.set_meta("field_energy", l.light_energy)
	_set_lit(PowerGrid.is_powered(LIGHT_CIRCUIT))
	PowerGrid.circuit_powered.connect(func(id: String) -> void:
		if id == LIGHT_CIRCUIT:
			_set_lit(true))
	PowerGrid.circuit_lost.connect(func(id: String) -> void:
		if id == LIGHT_CIRCUIT:
			_set_lit(false))

func _collect_lamps(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and c.has_meta("field_lamp"):
			_lamp_meshes.append(c)
		elif c is OmniLight3D and c.is_in_group("rig_field_floods"):
			_field_lights.append(c)
		_collect_lamps(c)

func _set_lit(on: bool) -> void:
	_lit = on
	for m in _lamp_meshes:
		m.visible = on
	for l in _field_lights:
		l.light_energy = float(l.get_meta("field_energy", 1.8)) if on else 0.0

## True when the field's lighting circuit is live. Read by the probe.
func is_lit() -> bool:
	return _lit

## A/B SWITCH, for the draw-call gate. `godot --path . tests/VantagePerf.tscn -- --nofield`
## builds the identical session without the field, so before/after is ONE session's numbers
## rather than two runs on a machine that drifts several fps between them (the same reason
## vantage_perf.gd flips shadow_dist inside a single run instead of across two).
static func disabled() -> bool:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a == "--nofield":
			return true
	return false

func _ready() -> void:
	if disabled():
		print("[field] --nofield: the three new rigs and their bridges are NOT built")
		stats = {"rigs": 0, "chunks": 0, "tris": 0, "prims": 0, "ms": 0}
		return
	var t0: int = Time.get_ticks_msec()
	var rigs: Array = [
		["marrow", MARROW_ORIGIN, MARROW_YAW],
		["anchorage", ANCHORAGE_ORIGIN, ANCHORAGE_YAW],
		["deepwell", DEEPWELL_ORIGIN, DEEPWELL_YAW],
	]
	var built: Array = []
	var total_chunks: int = 0
	var total_tris: int = 0
	var total_prims: int = 0
	for spec in rigs:
		var id: String = spec[0]
		var host := Node3D.new()
		host.name = id.to_pascal_case()
		# IDENTITY, deliberately: the Bake writes WORLD-space vertices, and the lights and
		# markers each rig hangs off `host` are positioned with Bake.to_world(). A transform
		# here would apply the rig's placement twice.
		add_child(host)
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(spec[2]))), spec[1])
		var bake := KIT.Bake.new(xf, id)
		# Dispatched explicitly against the preloaded scripts: a static function reached off
		# a Script held in an untyped Array is not a reliable `call()` target, and the
		# failure mode is a silent empty rig.
		var meta: Dictionary = {}
		match id:
			"marrow": meta = RIG_TWO.build(bake, host)
			"anchorage": meta = RIG_THREE.build(bake, host)
			"deepwell": meta = RIG_FOUR.build(bake, host)
		meta["origin"] = spec[1]
		meta["yaw"] = spec[2]
		meta["xform"] = xf
		meta["id"] = id
		total_tris += bake.tris()
		total_prims += bake.prims()
		total_chunks += bake.flush(host)
		built.append(meta)
		# Publish each rig so probes, the sonar export and the fishing pass can find it
		# without re-deriving a single coordinate.
		var mk := Node3D.new()
		mk.name = "Anchor"
		host.add_child(mk)
		mk.transform = xf
		mk.add_to_group("field_rig")
		mk.set_meta("rig_id", id)
		mk.set_meta("rig_name", meta.get("name", id))
		mk.set_meta("deck_y", meta.get("deck_y", 0.0))
		mk.set_meta("spawn", xf * (meta.get("spawn", Vector3.ZERO) as Vector3))
		mk.set_meta("overview", xf * (meta.get("overview", Vector3.ZERO) as Vector3))
		for f in meta.get("fishing", []):
			var fm := Node3D.new()
			fm.name = "Fish_" + str(f.get("id", "spot"))
			host.add_child(fm)
			fm.position = xf * (f["at"] as Vector3)
			fm.add_to_group("field_fishing_spot")
			fm.set_meta("spot_id", f.get("id", ""))
			fm.set_meta("water", f.get("water", "open"))
			fm.set_meta("rig_id", id)

	var bridge_chunks: int = _build_bridges(built)
	_field_seabed()
	_wire_power()

	var by_group: Dictionary = _count_groups(self)
	stats = {
		"rigs": built.size(),
		"chunks": total_chunks + bridge_chunks,
		"hull": int(by_group.get("hull", 0)),
		"detail": int(by_group.get("detail", 0)),
		"lamp": int(by_group.get("lamp", 0)),
		"lamps": _lamp_meshes.size(),
		"lights": _field_lights.size(),
		"glass": int(by_group.get("glass", 0)),
		"tris": total_tris,
		"prims": total_prims,
		"ms": Time.get_ticks_msec() - t0,
	}
	# The number that decides whether this chapter is affordable is not the total: "detail"
	# chunks carry visibility_range_end, so from SALTLINE-0's deck — 161 to 415 m away — only
	# hull and glass are submitted at all. Both are printed so neither can hide.
	print("[field] %d rigs + 3 bridges | %d draw chunks (hull %d / glass %d / lamp %d always, detail %d under %.0f m) | %d tris from %d primitives | %d lamp chunks + %d lights on '%s' | %d ms" %
		[built.size(), stats["chunks"], stats["hull"], stats["glass"], stats["lamp"], stats["detail"],
		KIT.Bake.DETAIL_DRAW_M, total_tris, total_prims, _lamp_meshes.size(), _field_lights.size(),
		LIGHT_CIRCUIT, stats["ms"]])

## Count the emitted chunks by RigKit group. Walks the built tree rather than trusting a
## running total: if flush ever stopped emitting something, a counter would not notice.
func _count_groups(n: Node) -> Dictionary:
	var out: Dictionary = {}
	for c in n.get_children():
		if c is MeshInstance3D and c.has_meta("rigkit_group"):
			var g: String = str(c.get_meta("rigkit_group"))
			out[g] = int(out.get(g, 0)) + 1
		var sub: Dictionary = _count_groups(c)
		for k in sub:
			out[k] = int(out.get(k, 0)) + int(sub[k])
	return out

# ------------------------------------------------------------------------------- bridges

## World-space endpoints of the chain, in order, from each rig's declared attach point.
func chain_points(built: Array) -> Array:
	var pts: Array = [RIG_ONE_EXIT]
	for i in range(built.size()):
		var m: Dictionary = built[i]
		var xf: Transform3D = m["xform"]
		pts.append(xf * (m["bridge_in"] as Vector3))
		if i < built.size() - 1:
			pts.append(xf * (m["bridge_out"] as Vector3))
	return pts

func _build_bridges(built: Array) -> int:
	var host := Node3D.new()
	host.name = "Bridges"
	add_child(host)
	# Bridges belong to neither rig, so they are baked in WORLD space with an identity
	# transform — no rig's bearing applies to them.
	var bake := KIT.Bake.new(Transform3D.IDENTITY, "bridge")
	var pts: Array = chain_points(built)
	var spans: Array = []
	for i in range(0, pts.size() - 1, 2):
		spans.append([pts[i], pts[i + 1]])
	for i in range(spans.size()):
		var a: Vector3 = spans[i][0]
		var c: Vector3 = spans[i][1]
		var flat := Vector2(c.x - a.x, c.z - a.z)
		var dir: Vector2 = flat.normalized()
		var yaw_a: float = rad_to_deg(atan2(dir.x, dir.y))
		var d3 := Vector3(dir.x, 0.0, dir.y)
		# Aprons first: each rig's deck rim to the truss, top face flush with the deck.
		KIT.bridge_apron(bake, a, yaw_a, BRIDGE_WIDTH, APRON_REACH)
		KIT.bridge_apron(bake, c, yaw_a + 180.0, BRIDGE_WIDTH, APRON_REACH)
		# Then the truss, starting just inside the aprons so the two overlap rather than
		# leaving the player a gap to fall through at the junction.
		var a2: Vector3 = a + d3 * (APRON_REACH - 0.4)
		var c2: Vector3 = c - d3 * (APRON_REACH - 0.4)
		KIT.bridge_span(bake, a2, c2, BRIDGE_WIDTH, BRIDGE_DEPTH, SPAN_DAMAGE[i])
		var mk := Node3D.new()
		mk.name = "Span%d" % (i + 1)
		host.add_child(mk)
		mk.position = (a + c) * 0.5
		mk.add_to_group("field_bridge")
		mk.set_meta("index", i)
		mk.set_meta("from", a)
		mk.set_meta("to", c)
		mk.set_meta("clear_span", (c2 - a2).length())
		print("[field] bridge %d: %.1f m clear, %+.1f m grade, from (%.1f, %.1f, %.1f)" %
			[i + 1, (c2 - a2).length(), c.y - a.y, a.x, a.y, a.z])
	return bake.flush(host)

# ------------------------------------------------------------------------- seabed extension

## seabed.gd builds a 180 x 180 m floor around SALTLINE-0 (`Seabed.EXT` 90) — the field runs
## to z 415, so three quarters of it stands over nothing. This is a COARSE continuation at
## 9 m spacing (against the main floor's 2.25), one mesh, one draw call, skipping every quad
## that the real floor already covers. At -92 m under this much murk it is never read as
## detail; it exists so a diver at a new rig does not find the world's edge.
const FIELD_STEP: float = 9.0
const FIELD_X0: float = -190.0
const FIELD_X1: float = 190.0
const FIELD_Z0: float = -70.0
const FIELD_Z1: float = 480.0

func _field_seabed() -> void:
	var nx: int = int((FIELD_X1 - FIELD_X0) / FIELD_STEP)
	var nz: int = int((FIELD_Z1 - FIELD_Z0) / FIELD_STEP)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize((nx + 1) * (nz + 1))
	norms.resize((nx + 1) * (nz + 1))
	for j in range(nz + 1):
		for i in range(nx + 1):
			var x: float = FIELD_X0 + i * FIELD_STEP
			var z: float = FIELD_Z0 + j * FIELD_STEP
			var vi: int = j * (nx + 1) + i
			verts[vi] = Vector3(x, Seabed.floor_height(Vector2(x, z)), z)
			norms[vi] = Seabed.floor_normal(Vector2(x, z))
	var inner: float = Seabed.EXT - FIELD_STEP   # leave one cell of overlap, no visible seam
	for j in range(nz):
		for i in range(nx):
			var cx: float = FIELD_X0 + (i + 0.5) * FIELD_STEP
			var cz: float = FIELD_Z0 + (j + 0.5) * FIELD_STEP
			if absf(cx) < inner and absf(cz) < inner:
				continue                          # the real floor already owns this ground
			var a: int = j * (nx + 1) + i
			idx.append_array([a, a + (nx + 1), a + 1, a + 1, a + (nx + 1), a + (nx + 1) + 1])
	if idx.is_empty():
		return
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# Deliberately NOT seabed.gdshader: that material carries a bloom_glow uniform the real
	# seabed node drives every frame, and a second silent copy of it would be a value nobody
	# updates. Flat silt is honest at this range.
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.20, 0.21, 0.19)
	m.roughness = 1.0
	mesh.surface_set_material(0, m)
	var mi := MeshInstance3D.new()
	mi.name = "FieldSeabed"
	mi.mesh = mesh
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("budgeted", true)
	add_child(mi)
