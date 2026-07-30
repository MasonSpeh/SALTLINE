extends Node
## SPAWN-DECK YELLOW HUNT — find the thing the owner actually SEES, not the thing a
## material filter thinks is yellow.
##
## The first attempt at this walked the wet deck's geometry and filtered on
## `albedo_color`. That misses two whole classes of culprit: anything whose yellow comes
## from a TEXTURE (every `MatLib.hazard_stripe()` object has a WHITE albedo_color), and
## anything the search box or the size cap excluded. The owner still sees a yellow box.
##
## So this works backwards from the picture instead. Stand exactly where the player stands,
## sweep the view, and for every frame find the pixels that are ACTUALLY YELLOW ON SCREEN.
## Cluster them, then shoot the camera's own ray through each cluster's centroid and walk the
## DRAWN geometry the way player_controller._identify_looked_at() (F9) does — physics rays
## miss dressing, which has no collider. What comes back is the node chain, the owning
## script, and the rendered colour, for every yellow blob big enough to be "a block".
##
## Run WINDOWED (--headless never draws, and this reads pixels):
##   godot --path . res://tests/SpawnYellow.tscn -- <out_dir>

## Where the player actually is. player_spawn is the cold open at the SPHL hatch;
## wet_deck_respawn is where they come back to. Both are "the spawn deck".
##
## OWNER REPORT, 2026-07-29, after the boat-landing fender posts were fixed: "The pole was
## good, but did you get the box, near the crate? Its within a few Meters of it." The crate is
## wet_deck_detail's Dock Locker at (28.6, ~2.0, -18.6) — moved 1 m inboard from z -19.6 — so
## the four `crate_*` spots below ring it at 2.4-3.2 m, which is the range the owner actually
## walks past it at. The two original spawn-deck spots are kept because they are what found
## the fender posts and cost only a few seconds.
const SPOTS := [
	["crate_w", Vector3(25.6, 2.2, -18.6)],
	["crate_n", Vector3(28.6, 2.2, -15.8)],
	["crate_sw", Vector3(26.4, 2.2, -20.8)],
	["crate_e", Vector3(31.0, 2.2, -18.6)],
	["spawn", Vector3(20.0, 2.2, -24.7)],
	["respawn", Vector3(20.0, 2.6, -19.0)],
]
const YAWS := [0, 45, 90, 135, 180, 225, 270, 315]
## TWO EYE HEIGHTS, not one. A 0.5 m box on the deck plate 3 m away subtends about 9° and
## sits ~15° below a level eye, so at the original single -6° pitch it lands in the bottom
## strip of the frame or off it entirely — the same near-miss that makes a low prop invisible
## to a walk-past. -6° is what the player sees standing; -26° is what they see looking at
## their feet, which is where a deck box lives.
const PITCHES := [-6.0, -26.0]
## How far out `_near_dump` looks. The owner said "within a few Meters", so this is a few
## metres and not the 14 m the fender-post hunt used: on a dressed wet deck a wide radius
## buries the answer in twenty textured props that are nowhere near the crate.
const REACH: float = 8.0
const CELL: int = 24          ## coarse-grid cell for clustering, in pixels
const MIN_CELLS: int = 2      ## a blob smaller than this is a highlight, not a block

var main: Node3D
var _out: String = "/tmp/spawn_yellow"
var _pause: CanvasLayer = null

func _process(_d: float) -> void:
	get_tree().paused = false
	if _pause == null:
		_pause = _find_pause(get_tree().root)
	if _pause != null:
		var panel: Variant = _pause.get("panel")
		if panel is CanvasItem:
			(panel as CanvasItem).visible = false

func _find_pause(n: Node) -> CanvasLayer:
	var s: Script = n.get_script()
	if s != null and String(s.resource_path).ends_with("pause_menu.gd"):
		return n as CanvasLayer
	for c in n.get_children():
		var got: CanvasLayer = _find_pause(c)
		if got != null:
			return got
	return null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(14.0).timeout
	main._countdown = 0.0
	if main.hud != null:
		if main.hud.fade_rect != null:
			main.hud.fade_rect.color.a = 0.0
		main.hud.visible = false          # a yellow HUD element would be a false positive
	GameClock.force_phase(GameClock.Phase.DAY)
	var p: Node3D = main.player
	p.set("_fly", true)
	p.set("input_locked", true)
	# Nothing in the hand: a held item is drawn over the view and would be hunted too.
	PlayerState.selected_hotbar = -1
	p.call("_update_held_item")
	for i in range(10):
		await get_tree().process_frame

	var seen: Dictionary = {}
	for spot in SPOTS:
		print("\n[yellow] ======== standing at %s %s ========" % [spot[0], str(spot[1])])
		_near_dump(spot[1], REACH)
		for pitch in PITCHES:
			for yaw in YAWS:
				await _look(p, spot[1], float(yaw), float(pitch))
				var tag: String = "%s_p%d_yaw%d" % [spot[0], int(pitch), yaw]
				var img: Image = get_viewport().get_texture().get_image()
				img.save_png("%s/%s.png" % [_out, tag])
				for b in _yellow_blobs(img):
					var hits: Array = _identify(p, b["px"], img.get_size())
					var line: String = "%-20s %5.2f%% of frame, px%s..%s centroid%s rendered=%s" % [
						tag, b["share"] * 100.0, str(b["lo"]), str(b["hi"]), str(b["px"]),
						(b["col"] as Color).to_html(false)]
					for i in range(hits.size()):
						var d: Dictionary = hits[i]
						line += "\n                #%d %.1fm [%s] %s  script=%s mesh=%s albedo=%s tex=%s size=%s centre=%s collides=%s" % [
							i, d.get("dist", -1.0), d.get("how", "?"),
							d.get("chain", "?"), d.get("script", "?"),
							d.get("mesh", "?"), (d.get("albedo", Color.BLACK) as Color).to_html(false),
							str(d.get("tex", false)),
							str((d.get("size", Vector3.ZERO) as Vector3).snappedf(0.01)),
							str((d.get("centre", Vector3.ZERO) as Vector3).snappedf(0.01)),
							d.get("solid", "?")]
					print("[yellow] " + line)
					var key: String = str(hits[0].get("chain", "?"))
					if not seen.has(key) or float(seen[key]["share"]) < float(b["share"]):
						seen[key] = {"share": b["share"], "line": line}
	print("\n[yellow] ================ BIGGEST YELLOW BLOB PER NEAREST OBJECT ================")
	var keys: Array = seen.keys()
	keys.sort_custom(func(a, b): return float(seen[a]["share"]) > float(seen[b]["share"]))
	for k in keys:
		print("[yellow] " + str(seen[k]["line"]))
	print("\n[yellow] done -> %s" % _out)
	get_tree().quit()

func _look(p: Node3D, pos: Vector3, yaw: float, pitch: float) -> void:
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw)
	p.get_node("Head").rotation.x = deg_to_rad(pitch)
	p.velocity = Vector3.ZERO
	await get_tree().create_timer(0.5).timeout
	for i in range(3):
		await RenderingServer.frame_post_draw

## Every yellow blob on screen, as [{px: Vector2i, share: float, col: Color}], biggest first.
## Yellow is judged in HSV on the RENDERED pixel, so a hazard-striped texture and a flat fill
## are found the same way — which is the whole point of doing this from the picture.
func _yellow_blobs(img: Image) -> Array:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var cw: int = int(ceil(float(w) / CELL))
	var ch: int = int(ceil(float(h) / CELL))
	var grid: PackedInt32Array = PackedInt32Array()
	grid.resize(cw * ch)
	var sums: Array = []
	sums.resize(cw * ch)
	var total: int = 0
	for y in range(0, h, 3):
		for x in range(0, w, 3):
			var c: Color = img.get_pixel(x, y)
			var hue: float = c.h * 360.0
			if hue < 34.0 or hue > 72.0 or c.s < 0.30 or c.v < 0.22:
				continue
			var i: int = (y / CELL) * cw + (x / CELL)
			grid[i] += 1
			if sums[i] == null:
				sums[i] = [Vector3.ZERO, 0]
			sums[i][0] += Vector3(c.r, c.g, c.b)
			sums[i][1] += 1
			total += 1
	if total < 20:
		return []
	# A cell counts as lit if a decent share of its sampled pixels were yellow.
	var per_cell: int = maxi(int((CELL / 3) * (CELL / 3) * 0.28), 4)
	var lit: PackedByteArray = PackedByteArray()
	lit.resize(cw * ch)
	for i in range(cw * ch):
		lit[i] = 1 if grid[i] >= per_cell else 0
	# Flood-fill the lit cells into blobs.
	var blobs: Array = []
	var done: PackedByteArray = PackedByteArray()
	done.resize(cw * ch)
	for i0 in range(cw * ch):
		if lit[i0] == 0 or done[i0] == 1:
			continue
		var stack: Array = [i0]
		done[i0] = 1
		var cells: Array = []
		while not stack.is_empty():
			var i: int = stack.pop_back()
			cells.append(i)
			var cx: int = i % cw
			var cy: int = i / cw
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx: int = cx + d[0]
				var ny: int = cy + d[1]
				if nx < 0 or ny < 0 or nx >= cw or ny >= ch:
					continue
				var ni: int = ny * cw + nx
				if lit[ni] == 1 and done[ni] == 0:
					done[ni] = 1
					stack.append(ni)
		if cells.size() < MIN_CELLS:
			continue
		var px: int = 0
		var py: int = 0
		var n: int = 0
		var rgb := Vector3.ZERO
		var samples: int = 0
		var lo := Vector2i(w, h)
		var hi := Vector2i(0, 0)
		for i in cells:
			var cx2: int = i % cw
			var cy2: int = i / cw
			px += cx2 * CELL + CELL / 2
			py += cy2 * CELL + CELL / 2
			n += 1
			lo = Vector2i(mini(lo.x, cx2 * CELL), mini(lo.y, cy2 * CELL))
			hi = Vector2i(maxi(hi.x, cx2 * CELL + CELL), maxi(hi.y, cy2 * CELL + CELL))
			if sums[i] != null:
				rgb += sums[i][0]
				samples += sums[i][1]
		var mean: Vector3 = rgb / maxf(float(samples), 1.0)
		blobs.append({
			"px": Vector2i(px / n, py / n),
			"lo": lo, "hi": hi,
			"share": float(cells.size() * CELL * CELL) / float(w * h),
			"col": Color(mean.x, mean.y, mean.z),
		})
	blobs.sort_custom(func(a, b): return float(a["share"]) > float(b["share"]))
	return blobs.slice(0, 4)

## What the camera's ray through `px` crosses. Same walk as F9 — DRAWN geometry, nearest AABB
## the ray enters, hull-scale slabs skipped — with two corrections F9 does not make and which
## made the first run of this probe useless: it returns the nearest THREE hits rather than one
## (an AABB test is coarse, and the true culprit is often the second entry), and it skips
## anything that is not a GeometryInstance3D or that hangs off the player. The player's own
## flashlight is a SpotLight3D under Head/Camera3D with a 23 x 25 x 24 m AABB centred on the
## camera: it swallows EVERY ray, and F9's own `is_in_group("player")` test only looks at the
## node itself, so a child of the player node is not caught by it.
func _identify(p: Node3D, px: Vector2i, view: Vector2i) -> Array:
	var cam: Camera3D = p.get("camera")
	if cam == null:
		return []
	# The viewport the camera projects through may not be the size of the image read back.
	var vs: Vector2 = cam.get_viewport().get_visible_rect().size
	var at := Vector2(float(px.x) / float(view.x) * vs.x, float(px.y) / float(view.y) * vs.y)
	var origin: Vector3 = cam.project_ray_origin(at)
	var dir: Vector3 = cam.project_ray_normal(at)
	var hits: Array = []
	var stack: Array[Node] = [get_tree().current_scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var vi := n as GeometryInstance3D
		if vi == null or not vi.is_inside_tree() or _under_player(vi):
			continue
		var raw: AABB = vi.get_aabb()
		if raw.size == Vector3.ZERO:
			continue
		var box: AABB = vi.global_transform * raw
		if box.size.x > 40.0 or box.size.z > 40.0:
			continue
		# STANDING INSIDE A MERGED CHUNK MAKES IT THE ANSWER TO EVERY PIXEL. The wet deck's
		# dressing welds into ArrayMeshes up to 13 m across, and the player is inside one of
		# them: `intersects_ray` then returns the origin itself, distance 0.00 m, for every
		# blob on screen. That is what the first crate run reported, at every yaw, and it is
		# worthless. A box that contains the eye cannot be what the eye is looking at.
		if box.has_point(origin):
			continue
		var hit: Variant = box.intersects_ray(origin, dir)
		if hit == null:
			continue
		var d: float = origin.distance_to(hit as Vector3)
		if d < 40.0:
			hits.append({"vi": vi, "d": d, "box": box, "how": "aabb-ray"})
	# AND the exact question, which the AABB ray only approximates: whose PROJECTED outline
	# actually contains this pixel? Unlike the ray test this is immune to a big loose AABB
	# swallowing a small prop's pixels, and unlike a physics ray it sees dressing (which has
	# no collider at all). Small things only — a chunk's outline covers half the screen.
	for h in hits:
		h["how"] = "aabb-ray"
	for n2 in _flat_walk():
		var box2: AABB = n2.global_transform * n2.get_aabb()
		if box2.size.length() > 4.0 or box2.has_point(origin):
			continue
		if not _screen_box(cam, box2).has_point(at):
			continue
		var d2: float = origin.distance_to(box2.get_center())
		if d2 < 40.0:
			hits.append({"vi": n2, "d": d2, "box": box2, "how": "on-pixel"})
	hits.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	var out: Array = []
	for i in range(mini(hits.size(), 4)):
		var d3: Dictionary = _describe(hits[i]["vi"], hits[i]["box"], float(hits[i]["d"]))
		d3["how"] = hits[i]["how"]
		out.append(d3)
	if out.is_empty():
		out.append({"chain": "(no geometry within 40 m on that ray)"})
	return out

## Every drawn node in the scene that is not part of the player.
func _flat_walk() -> Array:
	var out: Array = []
	var stack: Array[Node] = [get_tree().current_scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var vi := n as GeometryInstance3D
		if vi == null or not vi.is_inside_tree() or _under_player(vi):
			continue
		if vi.get_aabb().size == Vector3.ZERO:
			continue
		out.append(vi)
	return out

## The 2D screen rectangle a world box occupies, from its eight projected corners. Returns an
## empty rect if any corner is behind the lens — unproject_position is meaningless there.
func _screen_box(cam: Camera3D, box: AABB) -> Rect2:
	var r := Rect2()
	for i in range(8):
		var c: Vector3 = box.get_endpoint(i)
		if cam.is_position_behind(c):
			return Rect2()
		var s: Vector2 = cam.unproject_position(c)
		r = Rect2(s, Vector2.ZERO) if i == 0 else r.expand(s)
	return r

func _under_player(n: Node) -> bool:
	var p: Node = n
	while p != null:
		if p.is_in_group("player"):
			return true
		p = p.get_parent()
	return false

func _describe(vi: GeometryInstance3D, box: AABB, d: float) -> Dictionary:
	var col := Color(0, 0, 0, 0)
	var tex: bool = false
	var mesh_class: String = "CSG/" + vi.get_class()
	var mi := vi as MeshInstance3D
	if mi != null and mi.mesh != null:
		mesh_class = mi.mesh.get_class()
	for m in _materials(vi):
		var sm := m as BaseMaterial3D
		if sm == null:
			continue
		col = sm.albedo_color
		tex = sm.albedo_texture != null
		break
	return {"chain": _chain(vi), "script": _owner_script(vi), "mesh": mesh_class,
		"albedo": col, "tex": tex, "size": box.size, "centre": box.get_center(),
		"solid": _collides(vi), "dist": d}

## EVERY drawn thing near the spawn whose material could look yellow, with NO search box and NO
## size cap — the two things that let the first attempt at this miss the answer. Textured
## materials are included because `hazard_stripe()` and friends carry a WHITE albedo_color and
## get their yellow from the texture, so an albedo filter alone cannot see them at all.
func _near_dump(from: Vector3, reach: float) -> void:
	var rows: Array = []
	var stack: Array[Node] = [get_tree().current_scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var vi := n as GeometryInstance3D
		if vi == null or not vi.is_inside_tree() or _under_player(vi):
			continue
		var raw: AABB = vi.get_aabb()
		if raw.size == Vector3.ZERO:
			continue
		var box: AABB = vi.global_transform * raw
		if box.get_center().distance_to(from) > reach:
			continue
		var d: Dictionary = _describe(vi, box, box.get_center().distance_to(from))
		var c: Color = d["albedo"]
		var hue: float = c.h * 360.0
		var flat_yellow: bool = c.a > 0.0 and hue >= 30.0 and hue <= 78.0 and c.s >= 0.30
		if not (flat_yellow or bool(d["tex"])):
			continue
		d["vol"] = box.size.x * box.size.y * box.size.z
		d["flat_yellow"] = flat_yellow
		rows.append(d)
	rows.sort_custom(func(a, b): return float(a["vol"]) > float(b["vol"]))
	print("\n[yellow] ---- every candidate within %.0f m of %s, biggest first (%d) ----"
		% [reach, str(from), rows.size()])
	for i in range(mini(rows.size(), 20)):
		var d: Dictionary = rows[i]
		print("[yellow]  %2d vol=%.3f %s\n            script=%s mesh=%s albedo=%s tex=%s flatyellow=%s\n            size=%s centre=%s %.1fm collides=%s"
			% [i, d["vol"], d["chain"], d["script"], d["mesh"],
				(d["albedo"] as Color).to_html(false), str(d["tex"]), str(d["flat_yellow"]),
				str((d["size"] as Vector3).snappedf(0.01)),
				str((d["centre"] as Vector3).snappedf(0.01)), d["dist"], d["solid"]])

func _materials(vi: VisualInstance3D) -> Array:
	var out: Array = []
	if vi.get("material_override") is Material:
		out.append(vi.get("material_override"))
	var mi := vi as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i in range(mi.mesh.get_surface_count()):
			var m: Material = mi.get_active_material(i)
			if m != null:
				out.append(m)
		if mi.mesh.get("material") is Material:
			out.append(mi.mesh.get("material"))
	elif vi.get("material") is Material:
		out.append(vi.get("material"))
	return out

func _collides(vi: VisualInstance3D) -> String:
	if vi.get("use_collision") == true:
		return "CSG use_collision=true"
	var p: Node = vi
	for i in range(4):
		if p == null:
			break
		if p is CollisionObject3D:
			return "%s(%s)" % [p.get_class(), p.name]
		p = p.get_parent()
	return "no"

func _chain(n: Node) -> String:
	var s: String = String(n.name)
	var p: Node = n.get_parent()
	for i in range(4):
		if p == null or p == get_tree().current_scene:
			break
		s = "%s/%s" % [p.name, s]
		p = p.get_parent()
	return s

func _owner_script(n: Node) -> String:
	var p: Node = n
	while p != null:
		var s: Script = p.get_script()
		if s != null:
			return String(s.resource_path).get_file()
		p = p.get_parent()
	return "(no script ancestor)"
