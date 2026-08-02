extends Node
## TIDE SHOT — the same frame at low water and at high water, so the change is a picture and
## not a number. Aimed at the pontoon walkway (top y 0.95), which is the intertidal band the
## amplitude was chosen to create.
##
## WINDOWED ONLY (--headless never draws). Force-unpause and hide the pause panel every frame.
##
## Run: godot --path . tests/TideShot.tscn

const OUT_DIR: String = "res://tests/out"
const WARMUP_SEC: float = 8.0
## Eye on the wet deck looking down and out over the south pontoon, so the walkway, the
## waterline on the caisson and the open sea are all in frame at once.
const EYE := Vector3(14.0, 3.4, -2.0)
const AIM := Vector3(6.0, 0.4, 12.0)

var _pause_panel: CanvasItem = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await get_tree().create_timer(WARMUP_SEC).timeout
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		push_error("[tideshot] no player"); get_tree().quit(); return
	player.set_physics_process(false)
	player.set_process(false)
	var cam: Camera3D = player.get_node("Head/Camera3D")
	cam.current = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set("visible", false)
	for shot in [["low", -Gyre.TIDE_AMP], ["mean", 0.0], ["high", Gyre.TIDE_AMP]]:
		Gyre.set_tide(float(shot[1]))
		# The ocean node reads Gyre.tide() in its own _process, and the fauna/reef need a beat
		# to settle against the moved water, so give it several frames before the shutter.
		for i in range(12):
			await get_tree().process_frame
		cam.global_position = EYE
		cam.look_at(AIM, Vector3.UP)
		cam.fov = 70.0
		await get_tree().create_timer(0.4).timeout
		var ocean: Node3D = get_tree().get_first_node_in_group("ocean_surface")
		var f: String = "%s/tide_%s.png" % [OUT_DIR, String(shot[0])]
		get_viewport().get_texture().get_image().save_png(f)
		print("shot: %s   tide %+.2f m   ocean node y %+.2f"
			% [f, float(shot[1]), ocean.global_position.y if ocean else 0.0])
	Gyre.release_tide()
	get_tree().quit()

func _process(_delta: float) -> void:
	if get_tree().paused:
		get_tree().paused = false
		if _pause_panel == null:
			var stack: Array = [get_tree().root]
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				for c in n.get_children():
					stack.append(c)
				var sc: Script = n.get_script()
				if sc != null and String(sc.resource_path).ends_with("pause_menu.gd"):
					_pause_panel = n.get("panel") as CanvasItem
					break
		if _pause_panel != null:
			_pause_panel.visible = false
