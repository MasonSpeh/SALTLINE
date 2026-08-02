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
## The target the name popup last fired for. Distinct from `_shown` (the chip's grace-held
## text): this drops the instant the ray stops hitting anything, so looking away and back to
## the SAME item is a fresh "notice", even though the persistent chip is still holding its
## grace window on the old text.
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
## NO WORLD-SPACE HOVER BOX. A wireframe AABB used to be drawn around whatever the ray was
## aimed at; the owner pulled it (2026-07-27c) — the only box they ever wanted is the
## selection outline on the HOTBAR slot (see hud.gd). Everything the ray says about a target
## is now 2D: the "[E] TAKE ..." chip, the crosshair ring, and the occasional name popup.
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
		return
	if player and player.get("fishing") != null and player.fishing != null:
		# A cast is out — the rod owns the prompt and the mouse. No grabbing
		# props mid-fight, no prompt chip fighting over the strike banner.
		_current = null
		_forget_prompt()
		return
	if player and player.has_method("spear_prompt_text"):
		# A spear in hand, underwater, with a fish in the thrust cone — the player owns the chip
		# for as long as that is true, same deal as carrying and building above. Nothing the ray
		# can hit down there (the shoals have no colliders) would ever produce this line.
		var spear_line: String = String(player.call("spear_prompt_text"))
		if spear_line != "":
			_current = null
			if hud:
				hud.show_prompt_raw(spear_line)
				hud.set_targeting(true)
			_forget_prompt()
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
	# Name popup (owner request, 2026-07-27): fires off _announced, not _shown — it's a
	# "you're now looking at X" notice, so it resets the instant the target changes OR is
	# lost, unlike the chip's grace-held text. Deliberately independent of prompt_locked
	# below: a scripted hint owning the chip's TEXT is not a reason to stay silent about
	# what the player is visibly looking at.
	if next != _announced:
		_announced = next
		# Cooldown-gated (owner request, 2026-07-27b): a new target while still on cooldown
		# says nothing at all, so flicking across several items doesn't spam a notice for each.
		if next != null and hud and _popup_cd <= 0.0:
			hud.show_item_name(String(next.get("display_name")))
			_popup_cd = randf_range(POPUP_COOLDOWN_MIN, POPUP_COOLDOWN_MAX)
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
	# NOTHING UNDER THE CROSSHAIR: E falls through to "use what is in your hand". The ray gets
	# first refusal — a stove, a crate or a ladder always wins over eating — so this cannot
	# steal a world interaction, it only fills in the case where E previously did nothing at
	# all. That is the explicit consume the owner asked for after the number keys stopped
	# doubling as an eat button.
	if event.is_action_pressed("interact") and _current == null:
		var pl: Node3D = _player()
		if pl != null and pl.has_method("_try_use_held") and bool(pl.call("_try_use_held")):
			get_viewport().set_input_as_handled()
			return
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
