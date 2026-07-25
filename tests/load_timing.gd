extends Node
## How long does BUILDING THE RIG IN CODE actually cost at load? Answers "should we bake the
## architecture to a scene file and ship that instead?" with a number rather than a feeling.
## The rig is ~7,000 primitives authored in GDScript; this splits the synchronous build from
## the asynchronous settle/stream/batch passes that follow it.
var _t0 := 0
var _frames := 0
var _first_frame_ms := -1
func _ready() -> void:
	var boot := Time.get_ticks_msec()
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var load_ms := Time.get_ticks_msec() - boot
	var t1 := Time.get_ticks_msec()
	var main: Node = packed.instantiate()
	var inst_ms := Time.get_ticks_msec() - t1
	var t2 := Time.get_ticks_msec()
	add_child(main)                      # _ready() runs here: the whole rig is built
	var build_ms := Time.get_ticks_msec() - t2
	print("\n=== LOAD TIMING ===")
	print("  load Main.tscn resource : %5d ms" % load_ms)
	print("  instantiate scene       : %5d ms" % inst_ms)
	print("  add_child (RIG BUILD)   : %5d ms   <- what baking would remove" % build_ms)
	_t0 = Time.get_ticks_msec()
func _process(_d: float) -> void:
	_frames += 1
	if _first_frame_ms < 0:
		_first_frame_ms = Time.get_ticks_msec() - _t0
		print("  first frame after build : %5d ms" % _first_frame_ms)
	if Time.get_ticks_msec() - _t0 > 30000:
		print("  (settle + prop stream + 8 render_budget sweeps all land inside the first ~25 s)")
		print("===================\n")
		get_tree().quit()
