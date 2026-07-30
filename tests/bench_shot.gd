extends Node
## THE RIGGING BENCH, panel and table top, photographed.
##
## Owner, 2026-07-30: "Update the rigging bench, that should also have UI updated like the
## inventory. The items should also display on the table surface as the player selects/lays
## them down to craft, player should also know how many of each material they have left."
##
## Three frames per case: the panel (slots, icons, material counts), the bench top with the
## panel hidden (the real ItemVisual meshes standing on the real surface), and a close-up of
## the top. The bench is FOUND in the live tree, and its surface is read back out of
## BenchPanel._bench_surface() and printed next to the seating error measured off the parts
## themselves — because "they are on the bench" is a number, not an impression.
##
## Run WINDOWED:  godot --path . res://tests/BenchShot.tscn -- <out_dir>

var main: Node3D
var _out: String = "/tmp/bench_shot"
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
	if main.hud != null and main.hud.fade_rect != null:
		main.hud.fade_rect.color.a = 0.0
	GameClock.force_phase(GameClock.Phase.DAY)
	for i in range(10):
		await get_tree().process_frame
	var p: Node3D = main.player
	p.set("_fly", true)
	# Stock the pack so the material lines have something to count. Deliberately UNEVEN —
	# five driftwood against a recipe that wants two is what makes "2 + 3 / 2" legible.
	for spec in [["driftwood", 5], ["tarp", 1], ["rope", 2], ["scrap_metal", 3],
			["canvas_scrap", 2], ["kelp_bundle", 2]]:
		for i in range(int(spec[1])):
			PlayerState.add_item(String(spec[0]))
	var bench: Node3D = _find_bench(main)
	if bench == null:
		print("[bench] no CraftBench in the live tree")
		get_tree().quit()
		return
	print("[bench] bench found at %s" % str(bench.global_position.snappedf(0.01)))
	# Stand where a player using it stands: in front of the long face, looking down at the top.
	await _park(bench.global_position + Vector3(0.0, -0.45, 1.35), 0.0, -34.0)
	var hud: Node = main.hud
	hud.call("open_bench", bench)
	await _settle()
	var panel: Node = hud.get("bench_panel")
	# CASE 1 — a PARTIAL: tarp + one driftwood, with the lean-to still a driftwood short. This
	# is the case the material lines exist for.
	panel.call("lay_item", "tarp")
	panel.call("lay_item", "driftwood")
	await _icons_settled(panel)
	_save("bench_panel_partial")
	# CASE 2 — the COMPLETE match: the second driftwood goes on and the work button lights.
	panel.call("lay_item", "driftwood")
	await _icons_settled(panel)
	_save("bench_panel_complete")
	_report(panel, bench)
	# ...and the table top itself. The panel is hidden DIRECTLY rather than through
	# toggle_panel(), which would sweep the laid parts back into the pack on the way out.
	panel.set("visible", false)
	hud.set("visible", false)
	await _settle()
	_save("bench_top_standing")
	# The bench's own caged worklight stands on a gooseneck straight up from the middle of the
	# front edge, so a shot taken square-on photographs the post. Both close vantages come in
	# over a corner instead.
	# AIMED AT THE SUBJECT, not hand-yawed: the first cut of these two frames guessed the yaw
	# signs and photographed the deck behind the bench in both.
	await _aim(bench.global_position + Vector3(-0.95, -0.05, 0.80), bench.global_position + Vector3(0, 0.5, 0))
	_save("bench_top_close")
	await _aim(bench.global_position + Vector3(1.05, 0.00, 0.85), bench.global_position + Vector3(0, 0.5, 0))
	_save("bench_top_oblique")
	print("\n[bench] done -> %s" % _out)
	get_tree().quit()

## What the panel thinks the surface is, against where the parts actually ended up. The old
## code laid them at a hand-typed local y = 1.08 over a carcass whose top is +0.45.
func _report(panel: Node, bench: Node3D) -> void:
	# Timed: the surface probe walks the welded dressing's triangles (see _welded_top), and a
	# UI action that stalls the frame is a bug even when the number it prints is right.
	panel.set("_surface_cache", {})
	var t0: int = Time.get_ticks_usec()
	var top: Dictionary = panel.call("_bench_surface")
	print("[bench] surface probe took %.1f ms (cold)" % ((Time.get_ticks_usec() - t0) / 1000.0))
	print("[bench] measured surface: local y=%.3f  half_x=%.3f  half_z=%.3f (world y=%.3f)"
		% [float(top["y"]), float(top["half_x"]), float(top["half_z"]),
			bench.global_position.y + float(top["y"])])
	var vis: Array = panel.get("_part_visuals")
	for i in range(vis.size()):
		var v: Node3D = vis[i]
		if not is_instance_valid(v):
			continue
		var box: AABB = panel.call("_tree_aabb", v, v)
		var base_local: float = v.position.y + box.position.y * v.scale.y
		print("[bench]   part %d %-14s base local y=%.4f  gap to surface=%+.1f mm  size=%.3f m"
			% [i, str((panel.get("laid") as Array)[i]), base_local,
				(base_local - float(top["y"])) * 1000.0,
				maxf(box.size.x, maxf(box.size.y, box.size.z)) * v.scale.x])

## An icon is one SubViewport render per frame, so a panel photographed immediately shows
## empty sockets. Wait for the pictures the shot is about, with a frame cap.
func _icons_settled(panel: Node) -> void:
	panel.call("refresh")
	for i in range(140):
		await get_tree().process_frame
	await _settle()

func _find_bench(n: Node) -> Node3D:
	if n is CraftBench:
		return n as Node3D
	for c in n.get_children():
		var got: Node3D = _find_bench(c)
		if got != null:
			return got
	return null

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	for i in range(3):
		await RenderingServer.frame_post_draw

func _park(pos: Vector3, yaw: float, pitch: float) -> void:
	var p: Node3D = main.player
	p.global_position = pos
	p.rotation.y = deg_to_rad(yaw)
	p.get_node("Head").rotation.x = deg_to_rad(pitch)
	p.velocity = Vector3.ZERO
	PlayerState.oxygen = 1.0
	PlayerState.life = 1.0
	PlayerState.warmth = 1.0
	await _settle()

## Park at `pos` and LOOK AT `target`, eye height included — the camera sits 1.6 m over the
## player's origin, so a vantage aimed from the node photographs the deck (docs/AGENT_TRAPS.md).
func _aim(pos: Vector3, target: Vector3) -> void:
	var eye: Vector3 = pos + Vector3(0, 1.6, 0)
	var d: Vector3 = target - eye
	var yaw: float = rad_to_deg(atan2(-d.x, -d.z))
	var pitch: float = rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	await _park(pos, yaw, pitch)
	print("[bench] lens at %s looking at %s (%.2f m)"
		% [str(eye.snappedf(0.01)), str(target.snappedf(0.01)), d.length()])

func _save(tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, tag])
