class_name Salvage extends Interactable
## A decorative prop you can take APART. The rig is full of dead equipment; this is
## how it stops being scenery and becomes stock. Point at a drawer cabinet with a
## hacksaw on you and it offers CUT; you work at it for a few seconds of ringing
## steel, and it hands you plate and bolts — then it STAYS opened up. Panels gone,
## sooted, knocked askew. The rig should read as progressively stripped wherever
## you have been working. Nothing ever just vanishes.
##
## Two shapes, one component:
##   permanent  (regrow_sec <= 0) — salvage. Spent forever, wearing the damage.
##   renewable  (regrow_sec >  0) — harvest. Tar seams, barnacle crust, kelp: the
##                                  sea puts it back if you leave it alone a while.
##
## Built through the two static factories at the bottom, never by hand:
##   Salvage.from_prop(parent, "drawer_cabinet", pos, yaw, scale, def)
##   Salvage.from_visual(parent, my_visual_node, pos, yaw, def)
##
## Verb gating follows the Lamp Snail rule (bloom_fauna.gd): an EMPTY verb list
## means no prompt at all, so a spent prop is silent. A prop you lack the tool for
## still speaks — it tells you what would open it, because a salvage economy the
## player cannot discover is not an economy.

const NEAR_M: float = 4.0          ## walk further than this mid-job and the work lapses
const TICK_SEC: float = 0.55       ## tool-blow cadence while working

# ---- configuration (set by the factories from salvage_table.gd) ----
var required_tools: Array = []     ## any ONE of these opens it; empty = bare hands
var speed_tools: Array = []        ## optional; halves the work and spares your hands
var yields: Dictionary = {}        ## item_id -> count, granted whole or not at all
var work_sec: float = 3.0
var verb: String = "SALVAGE"
var hint_line: String = "It would come apart with the right tool."
var start_line: String = ""
var done_line: String = "You work it loose."
var bare_hand_risk: float = 0.0    ## life cost for doing it bare-handed (glass, shell)
var regrow_sec: float = 0.0        ## > 0 makes this a renewable harvest node
var sound: String = "clang"

# ---- state ----
var spent: bool = false
var _working: bool = false
var _left: float = 0.0
var _tick: float = 0.0
var _regrow_left: float = 0.0
var _model: Node3D = null          ## the visual we tilt / gut / darken
var _hidden: Array = []            ## MeshInstance3D we stripped off, for regrow
var _overlaid: Array = []          ## MeshInstance3D we sooted, for regrow

# ============================================================ interaction

func available_verbs() -> Array[String]:
	var out: Array[String] = []
	if spent or _working:
		return out          # silent: nothing left, or already at it
	if _has_tool():
		out.append(verb)
	else:
		out.append("LOOK")  # non-empty so the prompt shows; get_prompt() speaks the hint
	return out

func get_prompt() -> String:
	if spent or _working:
		return ""
	if _has_tool():
		return "%s  %s" % [verb, display_name]
	return "%s — %s" % [display_name, hint_line]

func interact(_verb: String, player: Node3D) -> void:
	if spent or _working:
		return
	if not _has_tool():
		_toast(hint_line)
		return
	if _free_slots() < _yield_total():
		_toast("No room in your pack for what's in there.")
		return
	_working = true
	_left = work_sec * (0.5 if _has_any(speed_tools) else 1.0)
	_tick = 0.0
	set_process(true)
	if start_line != "":
		_toast(start_line)
	if player:
		set_meta("worker", player)

func _process(delta: float) -> void:
	if _working:
		_work(delta)
	elif spent and regrow_sec > 0.0:
		_regrow_left -= delta
		if _regrow_left <= 0.0:
			_restore()
	else:
		set_process(false)

func _work(delta: float) -> void:
	var worker: Node3D = get_meta("worker", null)
	if worker and is_instance_valid(worker) and worker.global_position.distance_to(global_position) > NEAR_M:
		_working = false
		set_process(false)
		_toast("You step away from it, half done.")
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK_SEC
		AudioDirector.play_one_shot(sound, global_position, -7.0)
	_left -= delta
	if _left <= 0.0:
		_finish()

func _finish() -> void:
	_working = false
	# Last check — the pack can fill up while you work (it can't, today, but a
	# partial grant would silently destroy materials and that is unforgivable).
	if _free_slots() < _yield_total():
		set_process(false)
		_toast("No room in your pack for what's in there.")
		return
	var got: Array = []
	for item_id in yields:
		for _i in range(int(yields[item_id])):
			if PlayerState.add_item(item_id):
				got.append(_item_name(item_id))
	spent = true
	_regrow_left = regrow_sec
	set_process(regrow_sec > 0.0)
	AudioDirector.play_one_shot(sound, global_position, -2.0)
	_strip()
	if bare_hand_risk > 0.0 and not _has_any(speed_tools):
		PlayerState.life = maxf(0.0, PlayerState.life - bare_hand_risk)
		_toast("%s %s You cut your hand doing it." % [done_line, _list(got)])
	else:
		_toast("%s %s" % [done_line, _list(got)])
	Journal.discover("first_salvage")
	interacted.emit(verb)

# ============================================================ gating helpers

func _has_tool() -> bool:
	return required_tools.is_empty() or _has_any(required_tools)

func _has_any(tools: Array) -> bool:
	for t in tools:
		if PlayerState.has_item(String(t)):
			return true
	return false

func _yield_total() -> int:
	var n: int = 0
	for item_id in yields:
		n += int(yields[item_id])
	return maxi(n, 1)

## Free carry slots RIGHT NOW. Salvage is all-or-nothing: a prop is never gutted
## for materials that then bounce off a full pack (the Takeable convention).
func _free_slots() -> int:
	var n: int = 0
	for s in PlayerState.hotbar:
		if s == null:
			n += 1
	n += maxi(0, PlayerState.MAX_BACKPACK - PlayerState.inventory.size())
	return n

func _item_name(item_id: String) -> String:
	return String(PlayerState.items.get(item_id, {}).get("name", item_id))

func _list(names: Array) -> String:
	if names.is_empty():
		return ""
	if names.size() == 1:
		return "(%s)" % names[0]
	return "(%s)" % ", ".join(names)

func _toast(msg: String) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast(msg)

# ============================================================ the visible wound

## Gut it in place. Panels come off, what's left goes sooty and dull, and small
## things get knocked out of true. Never freed, never hidden whole — you should be
## able to walk your own route through the rig by the wreckage you left.
func _strip() -> void:
	add_to_group("salvaged")
	display_name = "Stripped " + display_name
	if _model == null or not is_instance_valid(_model):
		return
	var meshes: Array = _meshes(_model)
	# Pull off up to a third of the parts, biggest one always left standing so a
	# single-mesh prop can never disappear and a shelf keeps holding its tins.
	meshes.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
		return a.get_aabb().get_volume() > b.get_aabb().get_volume())
	if meshes.size() >= 3:
		var pull: int = mini(meshes.size() / 3, 4)
		for i in range(pull):
			var mi: MeshInstance3D = meshes[1 + i * 2] if 1 + i * 2 < meshes.size() else null
			if mi:
				mi.visible = false
				_hidden.append(mi)
	# Soot the rest. An OVERLAY, not an override — glTF materials are shared across
	# every duplicate of a prop, so touching them would darken the whole rig.
	var soot := StandardMaterial3D.new()
	soot.albedo_color = Color(0.04, 0.045, 0.05, 0.38)
	soot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	soot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	soot.cull_mode = BaseMaterial3D.CULL_BACK
	for mi in meshes:
		if not (mi as MeshInstance3D).visible:
			continue
		(mi as MeshInstance3D).material_overlay = soot
		_overlaid.append(mi)
	# Knock small things askew. Big furniture stays square — a tilted shelf would
	# throw everything resting on it, and the gutted look already reads.
	var span: float = _longest(_model)
	if span > 0.001 and span < 0.75:
		_model.rotation.z += deg_to_rad(6.0 + fmod(absf(global_position.x) * 7.0, 8.0))
		_model.rotation.x += deg_to_rad(fmod(absf(global_position.z) * 5.0, 6.0) - 3.0)

## Renewable nodes only: the sea puts it back.
func _restore() -> void:
	spent = false
	set_process(false)
	remove_from_group("salvaged")
	display_name = display_name.trim_prefix("Stripped ")
	for mi in _hidden:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).visible = true
	for mi in _overlaid:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_overlay = null
	_hidden.clear()
	_overlaid.clear()

# ============================================================ geometry helpers

static func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out

## Local-space AABB over every mesh under `node` — used for the collider and to
## decide whether a prop is small enough to knock crooked.
static func _bounds(node: Node3D) -> AABB:
	var acc := AABB()
	var first: bool = true
	for mi in _meshes(node):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != node:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var box: AABB = xf * (mi as MeshInstance3D).get_aabb()
		if first:
			acc = box
			first = false
		else:
			acc = acc.merge(box)
	if first:
		return AABB(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 0.4, 0.4))
	return acc

static func _longest(node: Node3D) -> float:
	var s: Vector3 = _bounds(node).size * node.scale
	return maxf(s.x, maxf(s.y, s.z))

# ============================================================ factories

## Salvage station wrapping a PropLib glTF model. The prop becomes a static body
## instead of a grabbable MovableProp — a drawer cabinet you can take a saw to is
## worth more than one you can carry, and the interaction ray only ever sees the
## first collider it hits (interaction_ray.gd:29), so the two cannot coexist
## without touching shared files.
static func from_prop(parent: Node3D, prop_id: String, pos: Vector3, yaw_deg: float,
		scale_mul: float, def: Dictionary) -> Salvage:
	var s := Salvage.new()
	s._configure(def)
	if s.display_name == "Object":
		s.display_name = _pretty(prop_id)
	parent.add_child(s)
	s.global_position = pos
	s.rotation.y = deg_to_rad(yaw_deg)
	s._model = PropLib.spawn(prop_id, s, pos, 0.0, scale_mul)
	s._fit_collider()
	s.add_to_group("salvageable")
	return s

## Salvage/harvest station over a visual you built yourself (tar seams, barnacle
## crust, kelp fronds — things with no model in the library).
static func from_visual(parent: Node3D, visual: Node3D, pos: Vector3, yaw_deg: float,
		def: Dictionary, reach: float = 0.5) -> Salvage:
	var s := Salvage.new()
	s._configure(def)
	parent.add_child(s)
	s.global_position = pos
	s.rotation.y = deg_to_rad(yaw_deg)
	s.add_child(visual)
	visual.position = Vector3.ZERO
	s._model = visual
	s._fit_collider(reach)
	s.add_to_group("salvageable")
	return s

func _configure(def: Dictionary) -> void:
	required_tools = def.get("tools", [])
	speed_tools = def.get("speed", [])
	yields = def.get("yields", {})
	work_sec = float(def.get("work", 3.0))
	verb = String(def.get("verb", "SALVAGE"))
	hint_line = String(def.get("hint", hint_line))
	start_line = String(def.get("start", ""))
	done_line = String(def.get("done", done_line))
	bare_hand_risk = float(def.get("risk", 0.0))
	regrow_sec = float(def.get("regrow", 0.0))
	sound = String(def.get("sound", "clang"))
	if def.has("name"):
		display_name = String(def["name"])
	set_process(false)

## Box collider hugging the model, shrunk a hair so a stripped ceiling lamp or a
## wall panel never becomes a thing you bump into on the way past.
func _fit_collider(min_size: float = 0.3) -> void:
	var box := BoxShape3D.new()
	var b: AABB = _bounds(_model) if _model else AABB(Vector3.ZERO, Vector3.ONE * 0.4)
	var sc: Vector3 = _model.scale if _model else Vector3.ONE
	var size: Vector3 = b.size * sc * 0.92
	box.size = Vector3(maxf(size.x, min_size), maxf(size.y, min_size), maxf(size.z, min_size))
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = (b.position + b.size * 0.5) * sc
	add_child(cs)

static func _pretty(id: String) -> String:
	var base: String = id.trim_suffix("_01").trim_suffix("_02").trim_suffix("_03")
	var out: PackedStringArray = []
	for w in base.replace("_", " ").split(" ", false):
		if w.length() > 0:
			out.append(w[0].to_upper() + w.substr(1))
	return " ".join(out)
