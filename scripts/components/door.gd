class_name InteractDoor extends Interactable
## A real hinged door. Its ORIGIN sits at the hinge edge; the leaf hangs off it,
## running out along local +X, thickness along local Z, so rotating the whole node
## about Y swings the leaf like a door on its jamb.
##
## OPEN/CLOSE on E. Opening always swings the leaf AWAY from the player (the free
## edge travels to whichever side the player is NOT standing on) so a door can never
## sweep through you or pin you in the frame. The leaf collides while closed and
## drops that collision while open so the swung panel never blocks the doorway.
##
## Two ways to give it a body:
##   - call build_door(w, h): builds a plank (wooden) or plate (metal) leaf, hinge
##     barrels, a handle, and the single toggling collision slab. Used by the rig
##     retrofit (see rig_builder/_fit_door).
##   - build the leaf yourself and add a CollisionShape3D as a DIRECT child (the SPHL
##     hatch via build_box_visual; the craftable door in structures.gd). _set_collision
##     only ever touches direct CollisionShape3D children, so either path works.
## locked doors show no prompt until unlock() is called (kept for the sub hatch etc.).

@export var locked: bool = false
@export var wooden: bool = true          ## plank leaf (interior rooms) vs. steel plate (hatches)

var is_open: bool = false
var _busy: bool = false
## Swing direction, resolved at open time to push the leaf away from the player.
## Held so CLOSE returns along the same arc it opened on.
var _open_sign: float = -1.0

func _init() -> void:
	verbs = ["OPEN"] as Array[String]

func available_verbs() -> Array[String]:
	var out: Array[String] = []
	if locked or _busy:
		return out
	out.append("CLOSE" if is_open else "OPEN")
	return out

func unlock() -> void:
	locked = false

func interact(verb: String, player: Node3D) -> void:
	super(verb, player)
	if _busy or locked:
		return
	_busy = true
	if not is_open:
		# Resolve the swing so the free edge sweeps to the side the player is NOT on.
		_open_sign = _swing_away_sign(player)
		is_open = true
		# Drop collision immediately: an opening door must never catch the player.
		_set_collision(false)
		var tw: Tween = create_tween()
		tw.tween_property(self, "rotation:y", _open_sign * deg_to_rad(100.0), 0.55) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func() -> void: _busy = false)
	else:
		is_open = false
		var tw: Tween = create_tween()
		tw.tween_property(self, "rotation:y", 0.0, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			_set_collision(true)
			_busy = false)
	AudioDirector.play_one_shot("hatch", global_position, -6.0)

## +1 rotates the +X free edge toward -Z; -1 toward +Z. Pick whichever carries the
## leaf away from the player. Evaluated from the CLOSED pose (rotation.y == 0 here),
## so to_local reads the player's true side of the door plane.
func _swing_away_sign(player: Node3D) -> float:
	if player == null:
		return _open_sign
	var lp: Vector3 = to_local(player.global_position)
	return 1.0 if lp.z >= 0.0 else -1.0

func _set_collision(enabled: bool) -> void:
	for c in get_children():
		if c is CollisionShape3D:
			c.disabled = not enabled

# --------------------------------------------------------------------- leaf build

## Build a complete leaf (hinge at origin, running out in +X) plus its collision slab.
func build_door(w: float, h: float) -> void:
	if wooden:
		_plank_leaf(w, h)
	else:
		_plate_leaf(w, h)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, h, 0.08)
	cs.shape = box
	add_child(cs)
	cs.position = Vector3(w * 0.5, 0.05 + h * 0.5, 0.0)

func _dbox(pos: Vector3, size: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	mi.mesh = m
	add_child(mi)
	mi.position = pos
	mi.rotation = rot

func _dcyl(pos: Vector3, radius: float, height: float, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.material = mat
	mi.mesh = m
	add_child(mi)
	mi.position = pos
	mi.rotation = rot

## Vertical plank boards with back battens, a diagonal brace, hinge barrels and a
## handle — the craftable-from-planks look the owner asked for.
func _plank_leaf(w: float, h: float) -> void:
	var wood: Material = MatLib.weathered_wood()
	var dark: Material = MatLib.dark_metal()
	var gy: float = 0.05                 # deck gap under the leaf
	var cy: float = gy + h * 0.5
	var bw: float = (w - 0.06) / 4.0
	for i in range(4):
		var bx: float = 0.06 + bw * (float(i) + 0.5)
		_dbox(Vector3(bx, cy, 0), Vector3(bw * 0.9, h, 0.05), wood)
	for by in [cy - h * 0.32, cy + h * 0.32]:
		_dbox(Vector3(w * 0.5, by, -0.045), Vector3(w * 0.9, 0.11, 0.03), dark)
	_dbox(Vector3(w * 0.5, cy, -0.05), Vector3(w * 1.02, 0.09, 0.025), dark,
		Vector3(0, 0, deg_to_rad(-52.0)))
	for hy in [cy - h * 0.34, cy + h * 0.34]:
		_dcyl(Vector3(0.04, hy, 0.03), 0.03, 0.16, dark)
	_dcyl(Vector3(w - 0.08, cy, 0.06), 0.02, 0.14, MatLib.galvanized(), Vector3(deg_to_rad(90), 0, 0))

## A dogged steel plate — for the metal doors (sub hatch style) that want the hinged
## behaviour without the plank look.
func _plate_leaf(w: float, h: float) -> void:
	var steel: Material = MatLib.rust_steel()
	var gy: float = 0.05
	var cy: float = gy + h * 0.5
	_dbox(Vector3(w * 0.5, cy, 0), Vector3(w, h, 0.07), steel)
	for by in [cy - h * 0.3, cy, cy + h * 0.3]:
		_dbox(Vector3(w * 0.5, by, -0.05), Vector3(w * 0.92, 0.08, 0.03), MatLib.galvanized())
	for hy in [cy - h * 0.34, cy + h * 0.34]:
		_dcyl(Vector3(0.05, hy, 0.04), 0.035, 0.18, MatLib.galvanized())
	_dcyl(Vector3(w - 0.12, cy, 0.05), 0.05, 0.12, MatLib.galvanized(), Vector3(deg_to_rad(90), 0, 0))
