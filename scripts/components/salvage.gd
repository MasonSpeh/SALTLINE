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
## THE OTHER KIND OF REGROWTH, in GAME HOURS off GameClock instead of real seconds.
##
## `regrow_sec` is right for a patch that comes back inside one visit — the tar seams and
## the glow-worm broods are 200-300 s, i.e. "later this session". It is the wrong shape for
## anything measured in DAYS (the mussel beds are five), because a real-seconds countdown
## cannot see a night the player slept through: skip_to_next_dawn() advances the calendar
## without spending any real time, so a five-day bed would sit bare through five slept
## nights and then regrow after five real hours of standing next to it. Set from a def's
## `regrow_days`; when > 0 it takes precedence over regrow_sec.
var regrow_game_hours: float = 0.0
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
var _added: Array = []             ## wound geometry we spawned, for regrow
## GameClock.game_time_hours() at the moment it was last harvested; < 0 = never.
var _picked_at_h: float = -1.0

func _ready() -> void:
	# A harvested node has to STAY harvested across a save. The node may not exist yet when
	# load_game() runs (the reef waits two physics frames, and Main defers the load by one),
	# so it claims its own saved state on arrival — the same deferred hand-off LootContainer
	# uses for its contents. Deferred, because the factories set global_position AFTER
	# add_child() and the save is keyed by where the node stands.
	SaveManager.claim_harvest.call_deferred(self)

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

## True for a harvest node (comes back) rather than a salvage node (spent forever).
func renewable() -> bool:
	return regrow_sec > 0.0 or regrow_game_hours > 0.0

func _process(delta: float) -> void:
	if _working:
		_work(delta)
	elif spent and regrow_game_hours > 0.0:
		# Measured on the calendar, not on delta — see regrow_game_hours.
		if GameClock.game_time_hours() - _picked_at_h >= regrow_game_hours:
			_restore()
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
	_picked_at_h = GameClock.game_time_hours()
	set_process(renewable())
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

## has_tool, not has_item: a honed knife opens everything a crude knife opened.
func _has_any(tools: Array) -> bool:
	for t in tools:
		if PlayerState.has_tool(String(t)):
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
	n += maxi(0, PlayerState.backpack_capacity() - PlayerState.pack_used())
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
	elif not meshes.is_empty():
		# A large share of the CC0 library is one or two meshes. Hiding a part of a
		# one-part prop would delete it, so those used to get soot and nothing else —
		# and soot alone reads as a shader fault, not as something taken apart.
		_improvise_wound(meshes[0])
	# Soot the rest. An OVERLAY, not an override — glTF materials are shared across
	# every duplicate of a prop, so touching them would darken the whole rig.
	# LIT, not unshaded: at SHADING_MODE_UNSHADED this flattened the prop's lighting
	# to a uniform dark film — the thing stopped responding to lamps and daylight and
	# read as a rendering bug rather than as grime. Per-pixel keeps the form and the
	# highlights, just dirtier, and the killed specular does the "gutted" work.
	var soot := StandardMaterial3D.new()
	soot.albedo_color = Color(0.05, 0.055, 0.06, 0.46)
	soot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	soot.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	soot.roughness = 0.96
	soot.metallic = 0.0
	soot.specular = 0.05
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

## The wound for props too simple to lose a part: punch a dark cavity through one
## face and leave torn edges standing off the rim. Built from primitives against the
## mesh's own AABB, so it lands correctly on anything — a toolbox, a drum, a crate —
## without knowing what the prop is. Tracked in _added so a renewable node can heal.
func _improvise_wound(target: MeshInstance3D) -> void:
	if target == null or not is_instance_valid(target) or target.mesh == null:
		return
	var parent: Node = target.get_parent()
	if parent == null:
		return
	var box: AABB = target.mesh.get_aabb()
	var s: Vector3 = box.size
	if s.x < 0.001 or s.y < 0.001 or s.z < 0.001:
		return
	# Deterministic per-prop, so the same crate is not wounded differently each load.
	var seed_f: float = absf(global_position.x) * 3.7 + absf(global_position.z) * 5.1
	var face_x: bool = fmod(seed_f, 2.0) < 1.0
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.025, 0.03)
	dark.roughness = 1.0
	dark.metallic = 0.0
	# The cavity: a box sunk through one face, deep enough to read as an opening.
	var hole := MeshInstance3D.new()
	var hm := BoxMesh.new()
	var w: float = s.x * (0.30 if face_x else 0.44)
	var h: float = s.y * 0.38
	var d: float = s.z * (0.44 if face_x else 0.30)
	hm.size = Vector3(w, h, d)
	hm.material = dark
	hole.mesh = hm
	parent.add_child(hole)
	hole.position = target.position + box.get_center() + (
		Vector3(s.x * 0.30, -s.y * 0.10, 0.0) if face_x else Vector3(0.0, -s.y * 0.10, s.z * 0.30))
	_added.append(hole)
	# Torn edges: thin strips bent off the rim of the opening.
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.28, 0.27, 0.25)
	metal.roughness = 0.85
	metal.metallic = 0.4
	for i in range(3):
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		var long_side: float = maxf(s.y * 0.30, 0.04)
		sm.size = Vector3(0.012, long_side, maxf(minf(s.x, s.z) * 0.16, 0.03))
		sm.material = metal
		strip.mesh = sm
		parent.add_child(strip)
		var t: float = float(i) - 1.0
		strip.position = hole.position + (
			Vector3(s.x * 0.14, h * 0.42, t * d * 0.36) if face_x
			else Vector3(t * w * 0.36, h * 0.42, s.z * 0.14))
		strip.rotation = Vector3(
			deg_to_rad(12.0 + 9.0 * t), 0.0, deg_to_rad(-38.0 - 14.0 * t))
		_added.append(strip)

# ============================================================ save / load
# A rig the player has stripped has to STILL be stripped after a night's sleep — and a
# five-day mussel bed that reset to full on every reload would make its whole regrowth
# meaningless. SaveManager keys these by where the node stands (positions are deterministic:
# every harvest node is built by world construction, not by the player) and hands the state
# back through claim_harvest, which _ready above asks for.
#
# NB the key cannot include display_name: _strip() renames the node to "Stripped X".

## What this node needs to come back the way the player left it.
func harvest_state() -> Dictionary:
	return {"spent": spent, "at_h": _picked_at_h, "left": _regrow_left}

## Put it back into that state. Idempotent, and safe to call on an untouched node with a
## payload that says untouched (which is what a fresh slot hands every node).
func harvest_restore(state: Dictionary) -> void:
	var want: bool = bool(state.get("spent", false))
	if want and not spent:
		spent = true
		_picked_at_h = float(state.get("at_h", GameClock.game_time_hours()))
		_regrow_left = float(state.get("left", regrow_sec))
		_strip()
		# If the calendar has already passed the regrow point (a save loaded days later),
		# _process restores it on the next frame rather than here — one code path for
		# regrowth, not two.
		set_process(renewable())
	elif not want and spent:
		_restore()
	elif want and spent:
		# Same state, different clocks: a reload must not restart the countdown.
		_picked_at_h = float(state.get("at_h", _picked_at_h))
		_regrow_left = float(state.get("left", _regrow_left))

## Renewable nodes only: the sea puts it back.
func _restore() -> void:
	spent = false
	_picked_at_h = -1.0
	set_process(false)
	remove_from_group("salvaged")
	display_name = display_name.trim_prefix("Stripped ")
	for mi in _hidden:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).visible = true
	for mi in _overlaid:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_overlay = null
	for n in _added:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_hidden.clear()
	_overlaid.clear()
	_added.clear()

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
