extends Node
## PERF PROBE — answers "what is actually costing us per tick?" with numbers instead of
## guesses. Boots the real Main scene, lets the dressing finish streaming, then samples
## Godot's own Performance monitors for a few seconds and prints the averages.
##
## Run WINDOWED (rendering monitors read 0 with --headless, since nothing is drawn):
##   godot --path . res://tests/perf_probe.tscn
## It self-quits. Physics/process times are in milliseconds PER FRAME.

## The props stream in, then the settle and batcher passes run — all one-time, all very
## expensive, and all of it lands inside the first several seconds. Sampling through that
## produced a nonsensical "206 ms/frame of _process at 16 fps" (a script cannot spend more
## time per frame than the frame lasts): a handful of multi-second startup stalls dragged
## the mean above the frame time. Warm up well past those, and report the WORST frame
## alongside the mean so a spike can never masquerade as steady-state cost again.
## render_budget.gd re-walks the whole tree SWEEP_COUNT(8) times, every SWEEP_EVERY(3) s, to
## catch dressing as it streams — so tree-walk spikes keep landing until t=24 s. Warm up past
## that or the average is measuring level load, not play.
const WARMUP_SEC: float = 30.0
const SAMPLE_SEC: float = 10.0

var _t: float = 0.0
var _n: int = 0
var _phys: float = 0.0
var _proc: float = 0.0
var _draw: float = 0.0
var _objs: float = 0.0
var _prims: float = 0.0
var _fps: float = 0.0
var _worst_frame: float = 0.0
var _worst_proc: float = 0.0
var _done: bool = false

func _ready() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = packed.instantiate()
	add_child(main)
	print("[perf] booting Main, warmup %.0fs then sampling %.0fs…" % [WARMUP_SEC, SAMPLE_SEC])

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t < WARMUP_SEC:
		return
	_n += 1
	_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_fps += Performance.get_monitor(Performance.TIME_FPS)
	_worst_frame = maxf(_worst_frame, delta * 1000.0)
	_worst_proc = maxf(_worst_proc, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	if _t >= WARMUP_SEC + SAMPLE_SEC:
		_report()

func _report() -> void:
	_done = true
	var n: float = maxf(float(_n), 1.0)
	var phys: float = _phys / n
	var proc: float = _proc / n
	print("\n===== PERF (avg over %d frames) =====" % _n)
	print("  physics tick rate      : %d Hz" % Engine.physics_ticks_per_second)
	print("  TIME_PHYSICS_PROCESS   : %.3f ms/frame" % phys)
	print("  TIME_PROCESS (scripts) : %.3f ms/frame" % proc)
	print("  fps                    : %.1f" % (_fps / n))
	print("  draw calls / frame     : %.0f" % (_draw / n))
	print("  objects / frame        : %.0f" % (_objs / n))
	print("  primitives / frame     : %.0f" % (_prims / n))
	var total: float = maxf(phys + proc, 0.0001)
	print("  worst frame            : %.1f ms  (worst _process %.1f ms)" % [_worst_frame, _worst_proc])
	print("  --> physics is %.1f%% of scripted+physics CPU; script _process is %.1f%%"
		% [100.0 * phys / total, 100.0 * proc / total])
	print("  collision shapes in world: %d" % _count_shapes(get_tree().root))
	print("=====================================\n")
	get_tree().quit()

func _count_shapes(n: Node) -> int:
	var c: int = 1 if n is CollisionShape3D else 0
	for ch in n.get_children():
		c += _count_shapes(ch)
	return c
