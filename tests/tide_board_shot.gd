extends Node
## Photograph the tide board at low and high water — it exists to make the tide readable,
## so a screenshot is the only test that matters. WINDOWED ONLY.
const OUT: String = "res://tests/out"
var _pp: CanvasItem = null
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await get_tree().create_timer(8.0).timeout
	var pl: Node3D = get_tree().get_first_node_in_group("player")
	pl.set_physics_process(false); pl.set_process(false)
	var cam: Camera3D = pl.get_node("Head/Camera3D"); cam.current = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud: hud.set("visible", false)
	for shot in [["low", -Gyre.TIDE_AMP], ["high", Gyre.TIDE_AMP]]:
		Gyre.set_tide(float(shot[1]))
		for i in range(10):
			await get_tree().process_frame
		# Stood on the dock apron looking at the SE caisson's south face.
		# Stood on the south pontoon walkway (top y 0.95) beside the caisson, eye 1.6 up.
		# On the OPEN part of the south pontoon (west of the wet-deck slab at x8), where the
		# ladder lands and the sky is overhead.
		# At the pontoon's south edge looking down at the staff standing in the sea.
		cam.global_position = Vector3(6.4, 2.4, -13.6)
		cam.look_at(Vector3(6.4, 0.35, -16.35), Vector3.UP)
		cam.fov = 56.0
		await get_tree().create_timer(0.4).timeout
		var f: String = "%s/tideboard_%s.png" % [OUT, String(shot[0])]
		get_viewport().get_texture().get_image().save_png(f)
		print("shot: %s  tide %+.2f" % [f, float(shot[1])])
	Gyre.release_tide()
	get_tree().quit()
func _process(_d: float) -> void:
	if get_tree().paused:
		get_tree().paused = false
		if _pp == null:
			var st: Array = [get_tree().root]
			while not st.is_empty():
				var n: Node = st.pop_back()
				for c in n.get_children(): st.append(c)
				var sc: Script = n.get_script()
				if sc != null and String(sc.resource_path).ends_with("pause_menu.gd"):
					_pp = n.get("panel") as CanvasItem; break
		if _pp != null: _pp.visible = false
