class_name Bed extends Interactable
## A crew bunk you can actually turn in on. By night (or dusk) it offers SLEEP:
## the screen fades, the clock skips to dawn, and you wake warmed through and a
## little mended — but a night's sleep still costs some hunger and thirst, so it's
## a trade, not a free heal. Each bed also builds its own lived-in bedding: a
## pillow, and a blanket that's either squared away or thrown back mid-rise.

const KIT := preload("res://scripts/world/mat_lib.gd")

var _busy: bool = false
var made: bool = true                 ## tidy vs. thrown-back bedding
var blanket_col: Color = Color(0.55, 0.58, 0.62)
var build_bedding: bool = true        ## false = collision-only over an existing bunk mesh
var col_size: Vector3 = Vector3(1.0, 0.56, 2.1)

func _init() -> void:
	display_name = "Bunk"
	verbs = ["SLEEP"] as Array[String]

func _ready() -> void:
	if build_bedding:
		_build()
	else:
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new(); box.size = col_size
		col.shape = box
		add_child(col)

## Only offer sleep once the light's gone — you don't nap through a working day.
func available_verbs() -> Array[String]:
	if _busy:
		return [] as Array[String]
	var ph: int = GameClock.current_phase
	if ph == GameClock.Phase.NIGHT or ph == GameClock.Phase.DUSK:
		return ["SLEEP"] as Array[String]
	return [] as Array[String]

func _build() -> void:
	# Frame + mattress (the mattress carries the interaction collider).
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new(); fm.size = Vector3(1.0, 0.4, 2.1); fm.material = KIT.wood()
	frame.mesh = fm
	add_child(frame); frame.position = Vector3(0, 0.2, 0)
	var mat := MeshInstance3D.new()
	var mm := BoxMesh.new(); mm.size = Vector3(0.92, 0.16, 1.95); mm.material = KIT.canvas(Color(0.7, 0.72, 0.72))
	mat.mesh = mm
	add_child(mat); mat.position = Vector3(0, 0.48, 0)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(1.0, 0.56, 2.1)
	col.shape = box
	add_child(col); col.position = Vector3(0, 0.28, 0)
	# Pillow at the head (−Z end).
	var pillow := MeshInstance3D.new()
	var pm := BoxMesh.new(); pm.size = Vector3(0.7, 0.12, 0.42); pm.material = KIT.canvas(Color(0.82, 0.84, 0.83))
	pillow.mesh = pm
	add_child(pillow); pillow.position = Vector3(0, 0.6, -0.72)
	# Blanket: squared to the foot when made, thrown back and rumpled when not.
	var blanket := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.material = KIT.canvas(blanket_col)
	blanket.mesh = bm
	add_child(blanket)
	if made:
		bm.size = Vector3(0.94, 0.1, 1.25)
		blanket.position = Vector3(0, 0.58, 0.3)
	else:
		bm.size = Vector3(0.8, 0.18, 0.85)
		blanket.position = Vector3(0.08, 0.62, 0.45)
		blanket.rotation.y = 0.35   # kicked askew

func interact(verb: String, player: Node3D) -> void:
	if verb != "SLEEP" or _busy:
		return
	_busy = true
	super.interact(verb, player)
	if player:
		player.input_locked = true
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("fade_to_black"):
		var tw: Tween = hud.fade_to_black(1.0)
		tw.tween_callback(_on_dark.bind(player, hud))
	else:
		_on_dark(player, hud)   # no HUD (headless test) — skip straight through

func _on_dark(player: Node3D, hud: Node) -> void:
	AudioDirector.play_one_shot("hiss", global_position, -14.0)
	GameClock.skip_to_next_dawn()
	PlayerState.warmth = 1.0
	PlayerState.life = minf(1.0, PlayerState.life + 0.15)
	PlayerState.sickness = 0.0
	PlayerState.hunger = maxf(0.0, PlayerState.hunger - 0.08)   # a night still burns fuel
	PlayerState.thirst = maxf(0.0, PlayerState.thirst - 0.10)
	if hud and hud.has_method("fade_from_black"):
		var tw: Tween = hud.fade_from_black(1.0)
		tw.tween_callback(_on_wake.bind(player, hud))
	else:
		_on_wake(player, hud)

func _on_wake(player: Node3D, hud: Node) -> void:
	if player:
		player.input_locked = false
	_busy = false
	if hud and hud.has_method("toast"):
		hud.toast("You slept until dawn — warm and mended, but hungry.")
