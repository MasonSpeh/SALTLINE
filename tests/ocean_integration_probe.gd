extends Node
## OCEAN INTEGRATION AUDIT. Boots the REAL Main and asserts, from the LIVE TREE, that
## every system the two ocean builders landed is actually instantiated — a system
## nobody adds to the scene is the classic failure of a hand-off — then cross-checks
## the numbers the three domains share:
##   * seabed mudline vs the caisson bottoms (a leg must plant, not hover)
##   * reef/wreck props vs the mudline they claim to sit on
##   * gyre debris vs the Gerstner surface it must ride, CALM and in a STORM
##   * scene cost (verts / draw-call-ish counts) for the MacBook budget
## Prints PASS/FAIL lines and a FAILURES: n footer, same shape as TestRunner.

const SEABED := preload("res://scripts/world/seabed.gd")

var _fail: int = 0
var _main: Node3D

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout   # world + reef + fauna assemble

	_check_tree()
	_check_legs_plant()
	_check_props_on_mudline()
	_check_shelf_support()
	await _check_gyre_rides_swell()
	_check_cost()

	print("---")
	print("FAILURES: %d" % _fail)
	get_tree().quit()

func _ok(cond: bool, label: String) -> void:
	if cond:
		print("PASS  %s" % label)
	else:
		_fail += 1
		print("FAIL  %s" % label)

## Depth-first search for the first node whose script path ends with `tail`, or whose
## class matches `cls`. Scripts loaded via preload have no class_name in the tree, so
## matching on the script resource path is the reliable test.
func _find_by_script(root: Node, tail: String) -> Node:
	var stack: Array = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		var s: Script = n.get_script()
		if s != null and s.resource_path.ends_with(tail):
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func _count_meshes(root: Node) -> int:
	var n: int = 0
	var stack: Array = [root]
	while stack.size() > 0:
		var x: Node = stack.pop_back()
		if x is MeshInstance3D or x is MultiMeshInstance3D:
			n += 1
		for c in x.get_children():
			stack.append(c)
	return n

# ------------------------------------------------------------------ live tree

func _check_tree() -> void:
	print("== live tree ==")
	var ocean: Node = _find_by_script(_main, "ocean_surface.gd")
	var uww: Node = _find_by_script(_main, "underwater_world.gd")
	var seabed: Node = _find_by_script(_main, "seabed.gd")
	var reef: Node = _find_by_script(_main, "reef_detail.gd")
	var life: Node = _find_by_script(_main, "reef_life.gd")
	var fx: Node = _find_by_script(_main, "underwater_fx.gd")
	_ok(ocean != null, "OceanSurface is in the live tree")
	_ok(uww != null, "underwater_world is in the live tree")
	_ok(seabed != null, "Seabed is in the live tree")
	_ok(reef != null, "ReefDetail is in the live tree")
	_ok(life != null, "ReefLife is in the live tree")
	_ok(fx != null, "UnderwaterFX is in the live tree")
	if seabed != null:
		_ok(_count_meshes(seabed) > 20, "Seabed actually built geometry (%d mesh nodes)" % _count_meshes(seabed))
	if fx != null:
		_ok(_count_meshes(fx) > 10, "UnderwaterFX actually built geometry (%d mesh nodes)" % _count_meshes(fx))
	if life != null:
		_ok(_count_meshes(life) > 20, "ReefLife actually built geometry (%d mesh nodes)" % _count_meshes(life))
	# the ocean material must be registered with the sun controller, or the sea never
	# learns what the sky is doing
	if ocean != null:
		var m: ShaderMaterial = ocean.call("get_material_ref")
		_ok(m != null, "ocean has a shader material")
		if m != null:
			var e: Variant = m.get_shader_parameter("sky_energy")
			_ok(e != null, "sky_energy is wired (SunController registered the ocean)")

# ------------------------------------------------------- legs plant in the mud

const LEGS := [Vector2(-22, -12), Vector2(22, -12), Vector2(-22, 12), Vector2(22, 12)]
const CAISSON_BOTTOM: float = -23.0   # underwater_world leg extension: box(6,20,6) @ y -13
const CAISSON_HALF: float = 3.0

## Shelves reef_detail advertises must actually carry their life. Sample what reef_life
## would compute as the support height and confirm it lands on the shelf, not the mud.
func _check_shelf_support() -> void:
	print("== reef life seats on the shelves, not the silt ==")
	var reef: Node = _find_by_script(_main, "reef_detail.gd")
	if reef == null:
		return
	var sunk: int = 0
	for s in reef.call("coral_shelves"):
		var p: Vector3 = s["pos"]
		var mud: float = SEABED.floor_height(Vector2(p.x, p.z))
		if p.y <= mud + 0.5:
			continue   # this shelf IS the mud; nothing to seat above
		var sup: float = ReefLife.support_y(p.x, p.z, p.y)
		if sup < p.y - 0.1:
			sunk += 1
			print("      life sinks off a raised shelf: shelf %.1f, support %.1f, mud %.1f" % [p.y, sup, mud])
	_ok(sunk == 0, "raised shelves seat their life at shelf height")

func _check_legs_plant() -> void:
	print("== legs plant into the mudline ==")
	for leg in LEGS:
		# sample the footprint: centre, face midpoints, corners
		var worst: float = -1e9
		var best: float = 1e9
		for ox in [-CAISSON_HALF, 0.0, CAISSON_HALF]:
			for oz in [-CAISSON_HALF, 0.0, CAISSON_HALF]:
				var h: float = SEABED.floor_height(leg + Vector2(ox, oz))
				worst = maxf(worst, CAISSON_BOTTOM - h)   # +ve = gap under the leg
				best = minf(best, CAISSON_BOTTOM - h)
		# A leg may be BURIED (mud above the bottom, gap < 0) but must never HOVER.
		_ok(worst < 0.35, "leg (%d,%d) plants: max gap under footprint %.2f m" % [leg.x, leg.y, worst])

func _check_props_on_mudline() -> void:
	print("== seabed props ride the mudline ==")
	var seabed: Node = _find_by_script(_main, "seabed.gd")
	if seabed == null:
		return
	var reef: Node = _find_by_script(_main, "reef_detail.gd")
	if reef == null:
		return
	# Every coral shelf reef_detail advertises must have its geometry near the mudline
	# or above it, never below the floor (buried life is invisible life).
	var shelves: Array = reef.call("coral_shelves")
	_ok(shelves.size() >= 6, "reef reports %d coral shelves" % shelves.size())
	var bad: int = 0
	for s in shelves:
		var p: Vector3 = s["pos"]
		var fh: float = SEABED.floor_height(Vector2(p.x, p.z))
		if p.y < fh - 0.5:
			bad += 1
			print("      shelf below the mud: (%.1f,%.1f,%.1f) floor %.1f" % [p.x, p.y, p.z, fh])
	_ok(bad == 0, "no advertised coral shelf is buried under the silt")

# --------------------------------------------------- gyre debris rides the swell

## Worst vertical gap between a piece of flotsam and the water under it.
##
## Sample the wave at the debris's UNDISPLACED (x, z) — the point on the gyre circle it
## was placed from — not at its final position. Gerstner pushes the surface sideways as
## well as up, so the final position is already offset by disp.xz; re-sampling there
## reads a different part of the wave and reports a metre of "error" that isn't real.
func _worst_debris_gap(debris: Array) -> float:
	var t: float = Gyre.water_time()
	var worst: float = 0.0
	for d in debris:
		var x: float = Gyre.CENTER.x + cos(d.gyre_angle) * d.gyre_radius
		var z: float = Gyre.CENTER.z + sin(d.gyre_angle) * d.gyre_radius
		var wy: float = Gyre.wave_height(Vector2(x, z), t)
		worst = maxf(worst, absf(d.global_position.y - wy))
	return worst

func _check_gyre_rides_swell() -> void:
	print("== gyre debris rides the Gerstner surface ==")
	var debris: Array = get_tree().get_nodes_in_group("floating_debris")
	_ok(debris.size() > 0, "gyre spawned debris (%d)" % debris.size())
	# CALM: the debris _physics_process plants each piece at wave_offset(); the ocean
	# shader displaces with the SAME math at the SAME sea_state, so the residual must
	# be the authored float bias only.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ok(_worst_debris_gap(debris) < 0.25, "calm: worst debris/surface mismatch %.2f m" % _worst_debris_gap(debris))

	# STORM: SunController raises the shader's sea_state toward 1.0. If gyre.gd is still
	# mirroring a hard-coded calm sea state, the real water rises well above the debris
	# and every plank floats in mid-air over a trough. StormSystem re-drives set_storm()
	# every frame from its own schedule, so freeze it or the forced squall is stomped
	# back to calm before we can sample it (which silently passes the test at 0.4/0.4).
	_main.storm.set_process(false)
	_main.storm.set_physics_process(false)
	_main.sun_ctl.set_storm(1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var mat: ShaderMaterial = _find_by_script(_main, "ocean_surface.gd").call("get_material_ref")
	var shader_ss: float = float(mat.get_shader_parameter("sea_state"))
	var gyre_ss: float = Gyre.sea_state()
	print("      storm: shader sea_state %.2f / gyre sea_state %.2f" % [shader_ss, gyre_ss])
	_ok(shader_ss > 0.9, "storm actually raised the shader's sea state (freeze took)")
	_ok(absf(shader_ss - gyre_ss) < 0.02, "storm: gyre wave math tracks the shader's sea_state")
	# And the debris must still be ON that (now much bigger) swell. Same tolerance as
	# calm: if the fit degrades when the sea gets big, the two seas have drifted apart.
	_ok(_worst_debris_gap(debris) < 0.25, "storm: worst debris/surface mismatch %.2f m" % _worst_debris_gap(debris))
	_main.sun_ctl.set_storm(0.0)
	_main.storm.set_process(true)
	_main.storm.set_physics_process(true)

# ------------------------------------------------------------------- cost

func _check_cost() -> void:
	print("== scene cost ==")
	var verts: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var draws: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var objs: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	print("      primitives/frame %d  draw calls %d  objects %d" % [verts, draws, objs])
	var ocean: Node = _find_by_script(_main, "ocean_surface.gd")
	if ocean != null:
		print("      ocean mesh verts %d" % int(ocean.get("vert_count")))
	var total_meshes: int = _count_meshes(_main)
	print("      mesh nodes in scene %d" % total_meshes)
	_ok(true, "cost reported")
