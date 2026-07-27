class_name InteractionRay extends RayCast3D
## Player's single interaction driver (GDD A4): raycast from camera, one context prompt,
## primary-verb dispatch on the interact action. Created by the player controller in code.

const REACH: float = 2.6
## How long a lost target keeps its prompt up before the chip is taken down. Long enough
## that flicking the view past the edge of a crate (or a prop that frees itself the frame
## it is taken) does not strobe the chip, short enough that walking away reads as "nothing
## here" rather than as a prompt stuck to the screen.
const PROMPT_GRACE: float = 1.0

var _current: Node3D = null   # Interactable or PhysProp
## The target the name popup and outline box last fired for. Distinct from `_shown` (the
## chip's grace-held text): both of these drop the instant the ray stops hitting anything,
## so looking away and back to the SAME item is a fresh "notice" and a fresh outline, even
## though the persistent chip is still holding its grace window on the old text.
var _announced: Node3D = null
## Owner request, 2026-07-27b: the name popup was firing on every new target, which read as
## a chip re-triggering rather than the occasional ambient notice they wanted — "like the
## waves, only every 1-2 mins". A flat cooldown between popup FIRINGS (not per-item) is the
## simplest faithful reading of that: whatever you're looking at when the timer runs out gets
## the next notice, and everything glanced at in between gets the outline only. The random
## span (rather than a fixed one) is what keeps it feeling like a tide rather than a metronome.
const POPUP_COOLDOWN_MIN: float = 60.0
const POPUP_COOLDOWN_MAX: float = 120.0
var _popup_cd: float = 0.0    ## seconds until the next name popup may fire (0 = ready now)
## Reused every frame — a wireframe box, PRIMITIVE_LINES, built once in _ready and just
## repositioned/rescaled on a target change (owner request, 2026-07-27: keep it cheap, no
## per-frame allocation, this project just went through a frame-cost pass — see
## render_budget.gd). top_level so its transform is independent of the ray's own rotation;
## parented here so it is freed automatically with the player.
var _outline: MeshInstance3D = null
## What the ray last handed the HUD ("" = the chip is clear as far as the ray knows).
##
## THE STALE PROMPT BUG. The dispatch used to diff `next != _current` alone and push only on
## a change. That silently broke every time _current was force-cleared without telling the
## HUD — which is exactly what happens after an interact (_unhandled_input ends with
## `_current = null` so the verb can be re-read next frame) and on the carried/panel/fishing
## hand-offs. Take an item and walk away: the item frees itself, `next` is null, `_current`
## is ALREADY null, so the diff never fires and the last "[E] TAKE ..." sat on screen until
## something else was aimed at. Diffing against what the CHIP shows instead of against the
## ray's own cache is the fix — a cleared target is no longer indistinguishable from a
## target we already reported.
var _shown: String = ""
var _clear_t: float = 0.0     ## seconds aimed at nothing with one of our prompts still up

func _ready() -> void:
	target_position = Vector3(0, 0, -REACH)
	collide_with_areas = false
	collide_with_bodies = true
	_outline = _build_outline_mesh()
	add_child(_outline)

func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	# Ticks down regardless of carry/build/fishing/ui_locked suppression below — the cooldown
	# is about pacing the NOTICE, not about whether a target happens to be available right
	# now, so it shouldn't stall (or get a free extension) just because a panel was open.
	if _popup_cd > 0.0:
		_popup_cd -= delta
	var player: Node3D = _player()
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if player and (player.carried or (player.build and player.build.active)):
		# Carrying or building — that system WRITES the chip itself (show_prompt_raw) and
		# clears it when it ends, so we only drop our own bookkeeping. Forgetting what we
		# showed forces a fresh push the moment the ray owns the chip again.
		_current = null
		_forget_prompt()
		_clear_outline()
		return
	if player and player.get("fishing") != null and player.fishing != null:
		# A cast is out — the rod owns the prompt and the mouse. No grabbing
		# props mid-fight, no prompt chip fighting over the strike banner.
		_current = null
		_forget_prompt()
		_clear_outline()
		return
	if player and player.ui_locked:
		# A panel (inventory / journal / help / bench / crate), a sit, or a lie-down. Nobody
		# else writes the chip here, so a world prompt from the last frame would just hang
		# there behind the panel — take it down ourselves. show_prompt() still honours
		# prompt_locked, so the sit/bed hints keep the chip exactly as they set it.
		_current = null
		if _shown != "" and hud:
			hud.show_prompt("")
		_forget_prompt()
		_clear_outline()
		return
	var hit: Object = get_collider() if is_colliding() else null
	var next: Node3D = null
	if hit is Interactable and not (hit as Interactable).available_verbs().is_empty():
		next = hit
	elif hit is PhysProp and (hit as PhysProp).held_by == null:
		next = hit
	# A target taken/freed out from under us is not a target. The ray still reports the
	# collider for the frame it is queue_free()d, and get_prompt() on a dead node crashes.
	if next != null and not is_instance_valid(next):
		next = null
	_current = next
	# Name popup + outline box (owner request, 2026-07-27): both fire off _announced, not
	# _shown — they're a "you're now looking at X" notice, so they reset the instant the
	# target changes OR is lost, unlike the chip's grace-held text. Deliberately independent
	# of prompt_locked below: a scripted hint owning the chip's TEXT is not a reason to hide
	# what the player is visibly looking at.
	if next != _announced:
		_announced = next
		if next != null:
			_show_outline(next)   # instant, every change — no cooldown on the highlight itself
			# The text announcement alone is cooldown-gated (owner request, 2026-07-27b): a
			# new target while still on cooldown gets the outline but no popup, so flicking
			# across several items doesn't spam a notice for each one.
			if hud and _popup_cd <= 0.0:
				hud.show_item_name(String(next.get("display_name")))
				_popup_cd = randf_range(POPUP_COOLDOWN_MIN, POPUP_COOLDOWN_MAX)
		else:
			_clear_outline()
	# A scripted hint owns the chip: keep tracking the target (E must still dispatch) but
	# record nothing, because show_prompt() is a no-op while locked — pretending our text
	# landed would leave the chip blank when the hint releases and we're still aimed here.
	if hud != null and bool(hud.get("prompt_locked")):
		_forget_prompt()
		return
	if next != null:
		var text: String = next.get_prompt()
		# Record only what actually reached a HUD — _shown is a mirror of the chip, not a wish.
		# Re-acquiring INSIDE the grace window re-pushes even an unchanged line, because the
		# crosshair ring was dropped the moment the target was lost and show_prompt owns it.
		if hud and (text != _shown or _clear_t > 0.0):
			_shown = text
			hud.show_prompt(text)
		_clear_t = 0.0
		return
	# Aimed at nothing. The crosshair leaves its targeting ring at once — that dot is live
	# feedback and must not lag the view — but the LINE holds for PROMPT_GRACE, so a flick
	# past the edge of a crate (or a prop that frees itself the instant it is taken) doesn't
	# strobe the chip. Then it goes.
	if _shown == "":
		_clear_t = 0.0
		return
	if is_zero_approx(_clear_t) and hud:
		hud.set_targeting(false)
	_clear_t += delta
	if _clear_t >= PROMPT_GRACE:
		_forget_prompt()
		if hud:
			hud.show_prompt("")

## Drop the ray's record of the chip: nothing of ours is up, and the grace clock is idle.
func _forget_prompt() -> void:
	_shown = ""
	_clear_t = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or _current == null:
		return
	# A target freed between the last physics tick and this press (a prop that despawned, an
	# item another system took) is a dead pointer, and `is`/interact() on it would throw.
	if not is_instance_valid(_current):
		_current = null
		return
	var player: Node3D = _player()
	if player and (player.carried or player.ui_locked or (player.build and player.build.active)
			or (player.get("fishing") != null and player.fishing != null)):
		return
	if _current is Interactable:
		var v: Array[String] = (_current as Interactable).available_verbs()
		if not v.is_empty():
			(_current as Interactable).interact(v[0], player)
	elif _current is PhysProp and player:
		player.try_grab(_current)
	# Consume this interact press. Otherwise the SAME event propagates to
	# player_controller._unhandled_input, whose "carrying: [E] sets down" branch
	# fires on the prop we just grabbed (carried is now set) — grab + instant drop,
	# so nothing appears to happen. While carrying, _physics_process forces _current
	# null, so this never eats the intended set-down press.
	get_viewport().set_input_as_handled()
	# State may have changed (a verb consumed, the item taken and freed); re-read the target
	# next frame. Dropping _current no longer strands the chip: _physics_process diffs against
	# _shown, so if nothing comes back the grace clear takes the prompt down.
	_current = null

## A thin, low-opacity wireframe cube (unit size, centred on origin) built ONCE and reused —
## restrained on purpose (owner call, 2026-07-27): this is a survival game, not a loot-shooter,
## so a bright glowing box would fight the atmosphere. top_level so repositioning it doesn't
## have to fight the ray's own rotation; hidden until the first target arrives.
func _build_outline_mesh() -> MeshInstance3D:
	var verts := PackedVector3Array()
	var c: Array[Vector3] = []
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				c.append(Vector3(x, y, z))
	# Corner order above is (x y z) with x slowest: 0=--- 1=--+ 2=-+- 3=-++ 4=+-- 5=+-+ 6=++- 7=+++
	var edges: Array = [
		[0, 1], [0, 2], [0, 4], [1, 3], [1, 5], [2, 3],
		[2, 6], [3, 7], [4, 5], [4, 6], [5, 7], [6, 7],
	]
	for e in edges:
		verts.append(c[e[0]])
		verts.append(c[e[1]])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.92, 0.92, 0.88, 0.4)   # same restrained cream as the chip's text
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = false
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.top_level = true
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## World-space AABB of every mesh under `root`, in WORLD space (unlike item_icons._bounds,
## which measures in the model's own local space — this box has to sit still in the world,
## not spin with a tumbling carried prop, so it is deliberately axis-aligned in world space
## rather than oriented to the target's own basis).
func _world_bounds(root: Node3D) -> AABB:
	var out := AABB()
	var got: bool = false
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var local_aabb: AABB = mi.mesh.get_aabb()
		# Merge all 8 transformed corners — a rotated part's local AABB corners are no
		# longer the extremes once transformed, so each corner has to be tested individually.
		for i in range(8):
			var corner := Vector3(
				local_aabb.position.x + local_aabb.size.x * float(i & 1),
				local_aabb.position.y + local_aabb.size.y * float((i >> 1) & 1),
				local_aabb.position.z + local_aabb.size.z * float((i >> 2) & 1))
			var world_pt: Vector3 = mi.global_transform * corner
			if not got:
				out = AABB(world_pt, Vector3.ZERO)
				got = true
			else:
				out = out.expand(world_pt)
	return out

## Show the outline around `target`'s world geometry, or fall back to a small box on its
## own origin if it has no mesh yet (a prop whose visual loads a frame late shouldn't leave
## the box stuck on the last item, or worse, invisible with nothing to say why).
func _show_outline(target: Node3D) -> void:
	if _outline == null:
		return
	var box: AABB = _world_bounds(target)
	if box.size.length() <= 0.0001:
		box = AABB(target.global_position - Vector3(0.15, 0.15, 0.15), Vector3(0.3, 0.3, 0.3))
	var pad: float = 0.02   # a hair of clearance so the lines don't z-fight the surface
	_outline.global_position = box.position + box.size * 0.5
	_outline.scale = box.size + Vector3.ONE * pad * 2.0
	_outline.visible = true

func _clear_outline() -> void:
	if _outline != null:
		_outline.visible = false
