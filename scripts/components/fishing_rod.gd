class_name FishingRod extends Node3D
## Two tools, one line object, and they do NOT play the same game.
##
## THE SURFACE ROD (item "fishing_rod"): LMB casts a float onto open water. Wait through
## the drift (nibbles lie), STRIKE on the plunge, then fight the fish on the line — hold
## LMB to reel while the tension bar allows, ease off when it screams. Species run by time
## of day; the deep night holds the strange ones.
##
## THE DEEP-DROP RIG (item "deep_rig_pole"): no float, no drift. Bait goes on the hook
## BEFORE anything leaves the drum — no bait, no drop — then a lead is heaved over the side
## from anywhere that overlooks water and PLUMBS. Depth is the whole mechanic: the lead
## sinks, the readout counts the metres, and each species in fish.json only looks at a bait
## that has reached its own drop_m, so the deeper the lead the deeper (and bigger) the pool.
## LMB thumbs the drum to hold a depth — that is the player choosing their fish — and a
## second LMB reels in. The fight then hauls the catch back up through all of that water.
##
## BAITING IS ITS OWN ACTION (owner spec 2026-07-27): press [B] while the rig is the wielded
## tool to arm the hook — a text prompt says so and names what it'll use — and casting an
## unbaited hook just refuses, same as before. See _baited_id, bait_prompt_text() and
## try_bait_now() below for why that state has to live outside any one FishingRod instance.
##
## The rod object lives only while a cast is out; the player owns one per session.

enum State { CASTING, DRIFT, SINK, BITE, FIGHT, DONE }

const CAST_SPEED: float = 13.0
const CAST_LIFT: float = 4.0
const GRAVITY: float = 9.8
const MAX_RANGE: float = 45.0
const BITE_WINDOW: float = 1.3
const CANCEL_DISTANCE: float = 6.0     # walk away and the line comes in
const REEL_RATE: float = 0.14         # progress/sec while reeling
const TENSION_DECAY: float = 0.8

# ---------------------------------------------------------------- the deep-drop rig
# A DIFFERENT TOOL, not the surface rod with different numbers. No float, no drift on the
# swell: a baited lead goes over the side, plumbs straight down, and the deeper it gets the
# deeper the pool it is fishing (data/fish.json drop_m). Every constant below and every
# branch guarded by `_deep` applies to the deep rig ALONE — the surface rod is untouched.
#
# WHY IT IS A HEAVE AND NOT A CAST. You do not aim a hand-line up or down; you pick a side
# and let the lead do the rest. So the deep launch reads only the FLATTENED look direction —
# never the pitch — and always leaves with the same modest lob. That is what makes "anywhere
# that overlooks water" true: every deck rim on this rig is fenced with an INVISIBLE
# full-height guard slab standing 1.25 m off the plate (rig_builder._rail_slab), and looking
# down at the water you mean to fish — the natural thing to do at a rail — put the old
# pitch-aimed cast straight into that slab. Hence "crane-only in practice".
# The eye is 1.6 m up (Player.tscn), so the lead leaves 0.35 m above rail-top, tops out
# ~0.18 m higher, and is still above rail-top half a second later — by which time
# DEEP_CAST_SPEED has carried it ~3 m out, clear of any rail you can stand at. Aim at solid
# decking across the way and the in-flight foul ray still fouls it, exactly as before.
const DEEP_CAST_LIFT: float = 1.9     # a lob over the rail — the lead takes it from there
const DEEP_CAST_SPEED: float = 6.0    # a heave over the side, not a whip out to sea
const DEEP_MAX_RANGE: float = 95.0    # the whole spool: the drop to the water AND the sink
const DEEP_SINK_RATE: float = 3.2     # m/s the lead pulls the line down through the dark
const DEEP_MAX_DEPTH: float = 48.0    # end of the spool, measured from the waterline
const DEEP_BITE_FACTOR: float = 1.1   # the deep is patient, but the sink is the real wait
const DEEP_FIGHT_SURGE: float = 1.6   # metres the lead is dragged about during the fight

# ---------------------------------------------------------------- the big-bite jolt
# What a monster taking the bait feels like in the hands. Fires ONCE, at the take — not at
# the strike and not at the landing — because the moment worth selling is the one where you
# still don't know if you have it. Only for a trophy species (FishTable.is_trophy: the
# weight tier or the fight tier, both read off data/fish.json); a sprat gets nothing.
const JOLT_WEAK: float = 0.7          ## low-frequency motor, gamepad
const JOLT_STRONG: float = 0.9        ## high-frequency motor
const JOLT_SEC: float = 0.35          ## short and hard — a hit, not a rumble
const FLASH_COLOR := Color(0.93, 0.97, 1.0)   ## cold pale sea-white, not a camera bulb
const FLASH_PEAK: float = 0.5         ## alpha at the snap
const FLASH_IN: float = 0.04          ## it arrives instantly...
const FLASH_OUT: float = 0.19         ## ...and is gone before you can look at it

## Any fish species read as legal deep-rig bait: "smaller than 2m" (owner spec 2026-07-27),
## not the old hardcoded five-species list. fish.json has no body-length field (size_kg is
## a landed WEIGHT, rolled per catch, nothing to do with the species' own size) — the best
## stand-in is item_visual.gd's FISH_SIZE, the multiplier ItemVisual already treats as a
## body-length figure in metres when it scales a held/dropped fish model. See
## _is_small_bait_fish() below.
const BAIT_FISH_MAX_M: float = 2.0

## General food scraps that count as bait alongside cut fish and the named specials in
## _is_bait_item() — flesh/protein a hand-line would actually use, not produce or tinned
## rations. Owner spec 2026-07-26/27: "a small fish... or whatever available food scrap
## wise" — judgement call on what's plausible (raw or cooked meat/fish) versus what
## obviously isn't (a canned peach, a birthday cake).
const BAIT_SCRAPS: Array[String] = [
	"raw_fillet", "raw_sea_bird", "cooked_sea_bird", "dried_fish",
	"crab_leg_seared", "escargot", "glow_worm", "glow_worm_cooked",
	"cooked_fish", "cooked_fish_prime",
]

# Species, conditions, and weights all live in data/fish.json via FishTable —
# the same table the drop net, the stove, and the Angler's Notes read.
const FISH := preload("res://scripts/world/fish_table.gd")

var _player: Node3D
var _state: State = State.CASTING
var _velocity: Vector3
var _bite_timer: float = 0.0
var _bite_window: float = 0.0
var _nibbles: int = 0
var _fish: Dictionary = {}
## WHAT TOOK THE BAIT, decided at the take rather than at the strike. The species used to be
## rolled inside _hook(), on the strike — which meant that at the one instant the rod has to
## say "this is a big one" (the take, and the 1.3 s of bite window after it) nothing in the
## world yet knew what was on the hook. It is rolled at the take now and _hook() spends it,
## so the fight character still comes from what took the bait: the same roll, from the same
## live conditions, moved earlier by at most BITE_WINDOW. Cleared if the fish lets go.
var _pending: Dictionary = {}
var _tension: float = 0.3
var _progress: float = 0.35
var _fight_t: float = 0.0
var _reeling: bool = false
var _bob: Node3D
var _dip: float = 0.0                 # visual dip: the float ducks, the lead is snatched
var _line: MeshInstance3D
var _line_mesh: CylinderMesh
var _cast_origin: Vector3
var _rng := RandomNumberGenerator.new()
var _deep: bool = false          # this cast is the deep-drop rig, not the surface rod
var _bait_id: String = ""        # bait on the hook this drop ("" = none, and no drop)
## The deep rig's hook, OUTSIDE any one cast: which bait (if any) is armed on it right now.
## Static because the rig has to remember this BETWEEN casts, and between drops the
## FishingRod node doesn't exist at all — setup()/queue_free() only bracket a single cast
## (see the _abort_msg doc below). Owner spec 2026-07-27: baiting is its own explicit action
## ([B] — see bait_prompt_text()/try_bait_now()), not something that used to happen
## implicitly the instant a cast was attempted.
static var _baited_id: String = ""
var _depth: float = 0.0          # deep rig: metres the lead has sunk below the waterline
var _spool_end: bool = false     # deep rig: all the line there is, is out
var _shown_m: int = -1           # last whole metre put on the HUD (don't rebuild per frame)
## A refusal to be toasted, after which the line comes in — parked here and spent at the
## top of the next physics frame. The bait gate is the reason it has to work this way:
## setup() CANNOT reel the line in from where it stands, because _start_fishing() assigns
## `player.fishing = rod` on the line AFTER setup() returns. A rod that freed itself inside
## setup() would leave the controller holding a freed object, and its `fishing == null` cast
## gate would then be false forever — no more fishing, ever, for the rest of the session.
var _abort_msg: String = ""

func setup(player: Node3D, camera: Camera3D) -> void:
	_player = player
	_cast_origin = player.global_position
	_rng.randomize()
	# Which tool cast this line? The deep rig is live only when it's the selected hotbar
	# item; anything else (the plain rod) fishes the surface exactly as before.
	_deep = _is_deep_selected()
	if not _deep:
		global_position = camera.global_position - camera.global_transform.basis.z * 0.5
		_build_float()
		_velocity = -camera.global_transform.basis.z * CAST_SPEED + Vector3(0, CAST_LIFT, 0)
		return
	# BAIT FIRST, THEN DROP. The hook has to already be armed — press [B] beforehand (see
	# try_bait_now()) — nothing in the dark comes up to a bare hook, so a bare deep line is
	# not a cast that fails after a wait, it is a cast that never leaves the drum. Refuse it
	# here, say why, and let the first physics frame reel it back in.
	if _baited_id == "" or not PlayerState.has_item(_baited_id):
		# The has_item() half of that check catches bait that got eaten/dropped/spent some
		# other way in the gap between arming the hook and pulling the trigger — a gap that
		# didn't used to exist when baiting and casting were the same instant. Without it the
		# hook would still read "baited" and cast on a fish that's no longer in the pack.
		_baited_id = ""
		_abort_msg = "Bait the hook first — press [B]. Nothing in the dark rises to a bare hook."
		visible = false
		return
	_bait_id = _baited_id
	_baited_id = ""   # spent into this drop; a fresh [B] arms the next one
	_build_lead()
	# The heave: flattened facing only (see the constants above for why the pitch is thrown
	# away). The lead also STARTS level with the eye and out at arm's length along that flat
	# line, so looking down cannot begin the drop already inside the rail slab.
	var out: Vector3 = -camera.global_transform.basis.z
	out.y = 0.0
	out = out.normalized() if out.length() > 0.001 else Vector3.FORWARD
	global_position = camera.global_position + out * 0.5
	_velocity = out * DEEP_CAST_SPEED + Vector3(0, DEEP_CAST_LIFT, 0)
	_schedule_bite()   # re-roll at deep pace now that _deep is known (_ready ran surface-paced)

func _ready() -> void:
	# Terminal tackle hangs off this, and which tackle it is depends on which rig cast the
	# line — a decision setup() makes, and _ready() runs BEFORE setup(). So the holder is
	# built here and _build_float() / _build_lead() fill it there.
	_bob = Node3D.new()
	add_child(_bob)
	# Line: one thin cylinder from the rod hand to the tackle, restretched per frame.
	_line_mesh = CylinderMesh.new()
	_line_mesh.top_radius = 0.006
	_line_mesh.bottom_radius = 0.006
	_line_mesh.height = 1.0
	_line_mesh.material = MatLib.flat(Color(0.85, 0.88, 0.9))
	_line = MeshInstance3D.new()
	_line.mesh = _line_mesh
	_line.top_level = true
	add_child(_line)
	_schedule_bite()

## Surface tackle: the float, red cap over white body — the classic, visible at range.
func _build_float() -> void:
	var top := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.09
	tm.height = 0.18
	tm.material = MatLib.flat(Color(0.85, 0.15, 0.1))
	top.mesh = tm
	top.position.y = 0.08
	_bob.add_child(top)
	var bot := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.08
	bm.height = 0.16
	bm.material = MatLib.flat(Color(0.9, 0.9, 0.86))
	bot.mesh = bm
	bot.position.y = -0.05
	_bob.add_child(bot)

## Deep tackle: NO FLOAT. A pear of grey lead with the baited hook slung under it, dull
## and heavy — the thing that does the work on this rig is gravity, and the tackle should
## say so at a glance. (A float on the deep rig was the single most wrong thing about it:
## a bobber holds bait AT the surface, which is the exact opposite of the job.)
func _build_lead() -> void:
	var lead := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.075
	lm.height = 0.26                       # drawn out into a pear, the way a sinker is cast
	lm.material = MatLib.flat(Color(0.34, 0.35, 0.38))
	lead.mesh = lm
	_bob.add_child(lead)
	var hook := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.012
	hm.bottom_radius = 0.004
	hm.height = 0.16
	hm.material = MatLib.flat(Color(0.62, 0.64, 0.68))
	hook.mesh = hm
	hook.position = Vector3(0.045, -0.2, 0)
	hook.rotation.z = deg_to_rad(-22)
	_bob.add_child(hook)
	# The bait itself, on the hook. Small, but it is the thing the drop is gated on, so it
	# should be visible on the line — the player paid for it.
	var bait := MeshInstance3D.new()
	var bt := SphereMesh.new()
	bt.radius = 0.05
	bt.height = 0.09
	# Bait colour reads what is actually on the hook: a snail's pale foot, a crab leg's
	# orange chitin, or the dull red of cut/rotten fish.
	var bait_col := Color(0.55, 0.34, 0.3)
	if _bait_id == "snail_live":
		bait_col = Color(0.6, 0.5, 0.38)
	elif _bait_id == "crab_leg":
		bait_col = Color(0.78, 0.36, 0.16)
	# A glow worm is the one bait that is its own lure, and it has to LOOK like one on the
	# way down: emissive, so the last thing you see of the tackle as it sinks past the light
	# is the bait itself. That is the whole reason it fishes the way it does at depth.
	if _bait_id == "glow_worm":
		bt.material = MatLib.glowing(Color(0.35, 0.95, 0.85), 2.2)
	else:
		bt.material = MatLib.flat(bait_col)
	bait.mesh = bt
	bait.position = Vector3(0.05, -0.26, 0)
	_bob.add_child(bait)

func _hand_pos() -> Vector3:
	# The tip of the actually-held rod visual, wherever the camera is looking — not
	# a fixed world-space offset from the player's feet. That fixed offset never
	# moved with the camera at all, so turning to look around left the line's start
	# point behind while the rod on screen swung with the view: the "glitched away"
	# line. hand_tip_world() reads the held item's live transform instead.
	if _player.has_method("hand_tip_world"):
		return _player.hand_tip_world()
	return _player.global_position + Vector3(0, 1.25, 0)

## The deep-drop rig is live only when its OWN item is the selected hotbar tool. The
## plain fishing_rod is never deep — the surface game stays exactly as it was.
func _is_deep_selected() -> bool:
	var sel: int = PlayerState.selected_hotbar
	if sel < 0 or sel >= PlayerState.HOTBAR_SIZE:
		return false
	var it: Variant = PlayerState.hotbar[sel]
	return it != null and String(it) == "deep_rig_pole"

## Find one bait in the pack for the deep rig, hotbar first in slot order then the pack
## overflow — "closest to the first item slot" (owner spec 2026-07-27), the same order
## HangLine picks a fish in (hang_line.gd _find_bait). This SUPERSEDES the old
## cheapest-first ordering (snail/chum/crab-leg checked ahead of everything else): with
## bait now its own explicit [B] action instead of something spent silently on every cast,
## slot order is the legible rule — whatever the player put closest to hand is what gets
## used. Returns the item id, or "" when there's none.
static func _find_bait() -> String:
	for entry in PlayerState.hotbar + PlayerState.inventory:
		if entry != null and _is_bait_item(String(entry)):
			return String(entry)
	return ""

## Whether id is legal deep-rig bait: the three named specials (a live snail, rotten chum,
## a crab leg — owner spec 2026-07-26 on the crab leg specifically), a general flesh scrap
## (BAIT_SCRAPS), or any fish species under BAIT_FISH_MAX_M.
static func _is_bait_item(id: String) -> bool:
	if id in ["snail_live", "fish_rotten", "crab_leg"]:
		return true
	if id in BAIT_SCRAPS:
		return true
	return _is_small_bait_fish(id)

## Any fish species read as small enough to use as cut bait on the deep rig — see
## BAIT_FISH_MAX_M above. Large fish waste their protein on a drop: nothing chases the bait
## at depth if there's plenty of meat on the hook already.
static func _is_small_bait_fish(id: String) -> bool:
	if not id.begins_with("fish_"):
		return false
	return float(ItemVisual.FISH_SIZE.get(id, 1.0)) < BAIT_FISH_MAX_M

## Plain-words bait name for player-facing reads (the "X on the hook" toast, the bait
## prompt). The three named specials keep their own hand-written reads; anything else — a
## small fish, a food scrap — falls back to its own item name (data/items.json), since
## enumerating every qualifying id by hand stopped being practical once the rule went
## size/flesh-based instead of five hardcoded species (owner spec 2026-07-27).
static func _bait_name(id: String) -> String:
	if id == "snail_live":
		return "a live snail"
	if id == "fish_rotten":
		return "rotten chum"
	if id == "crab_leg":
		return "a crab leg"
	if id == "":
		return "cut bait"
	return String(PlayerState.items.get(id, {}).get("name", id))

## True while the deep rig is the selected hotbar tool and nothing else (a carried prop,
## build mode, a climb, an existing cast) has the player's hands full — the same guards
## _start_fishing() and player_controller's own input handling already gate a cast behind,
## mirrored here so the bait prompt/[B] handling never offers something those would swallow
## anyway. Also the reason [B] is safe to hand entirely to bait while this is true: Build
## Mode's own [B] binding only ever meant anything when some OTHER item was selected.
static func deep_rig_idle(player: Node) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if player.get("fishing") != null:
		return false
	if player.get("carried") != null:
		return false
	if bool(player.get("hook_out")):
		return false
	var build: Object = player.get("build")
	if build != null and bool(build.get("active")):
		return false
	var sel: int = PlayerState.selected_hotbar
	if sel < 0 or sel >= PlayerState.HOTBAR_SIZE:
		return false
	var it: Variant = PlayerState.hotbar[sel]
	return it != null and String(it) == "deep_rig_pole"

## What the bait chip should say right now, or "" to hide it. Read every frame from HUD
## (see hud.gd's dedicated bait chip) — the rig has to be able to prompt for bait BEFORE
## any cast exists, and no FishingRod node exists between casts (see _baited_id above), so
## this lives here as a plain static read instead of on a node that isn't there yet.
static func bait_prompt_text(player: Node) -> String:
	if not deep_rig_idle(player):
		return ""
	if _baited_id != "" and PlayerState.has_item(_baited_id):
		return "Hook baited: %s — [LMB] heave it over the side" % _bait_name(_baited_id)
	_baited_id = ""   # bait vanished (eaten/dropped/used) since it was armed — say so honestly
	var found: String = _find_bait()
	if found == "":
		return "Nothing to bait the hook with — a fish under 2 m, or a scrap of flesh."
	return "[B]  Bait the hook with %s" % _bait_name(found)

## Press [B] while the deep rig is idle: arm the hook with whatever _find_bait() turns up
## (closest to the first item slot — owner spec 2026-07-27). Returns true if it did
## anything (armed the hook, or the hook was already armed), false if [B] should still fall
## through to whatever else it does (Build Mode) — see player_controller.gd's B handler.
static func try_bait_now(player: Node) -> bool:
	if not deep_rig_idle(player):
		return false
	if _baited_id != "" and PlayerState.has_item(_baited_id):
		return true   # already armed — swallow the press, don't also open Build Mode
	var found: String = _find_bait()
	if found == "":
		return false   # nothing to bait with: this press isn't ours, let Build Mode have it
	_baited_id = found
	var hud: Node = player.get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast("Baited: %s" % _bait_name(found))
	return true

func _schedule_bite() -> void:
	# The water read drives the wait: storms are a frenzy, feeding hours are
	# brisk, dead calm afternoons make you earn it. Nibbles lie first.
	var ctx: Dictionary = FISH.context(self, global_position, _bait_id)
	var mean: float = 12.0 * FISH.bite_pace(ctx)
	if _deep:
		mean *= DEEP_BITE_FACTOR   # the deep is patient
	_bite_timer = _rng.randf_range(mean * 0.45, mean * 1.5)
	_nibbles = _rng.randi_range(0, 2)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		queue_free()
		return
	if _abort_msg != "":
		_finish(_abort_msg)   # the bait gate, spent one frame after setup() refused the drop
		return
	if _player.ui_locked or _player.input_locked or (_player.get("build") and _player.build.active):
		_finish("")   # panels, blackouts, and build mode all reel the line in
		return
	var t: float = Gyre.water_time()
	match _state:
		State.CASTING:
			var prev: Vector3 = global_position
			_velocity.y -= GRAVITY * delta
			global_position += _velocity * delta
			# Hitting deck/structure mid-flight is a fouled cast — clatter and done.
			var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(prev, global_position)
			q.exclude = [_player.get_rid()]
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty():
				AudioDirector.play_one_shot("clang", global_position, -20.0)
				_finish("The lead clatters off the steel — stand at the rail and drop it over the side." \
					if _deep else "No open water there.")
				return
			var water_y: float = Gyre.wave_height(Vector2(global_position.x, global_position.z), t) * 0.85
			if global_position.y <= water_y + 0.02:
				global_position.y = water_y + 0.02
				AudioDirector.play_one_shot("splash", global_position, -14.0)
				if _deep:
					# The bait is NOT spent here (owner correction, 2026-07-27: a drop that
					# reels back up with no bite has to still have its bait on the hook —
					# it used to be charged the instant the lead hit the water, which meant
					# reeling in early on a dead read cost you bait for nothing). The hook
					# only actually loses what's on it in State.SINK below, at the moment
					# something really takes it — see the bite branch there.
					#
					# Start the depth count where the lead actually is, so the first frame of
					# sinking doesn't pop it by however high the crest was.
					_depth = -global_position.y
					_state = State.SINK
					# A toast, not a prompt: the prompt line belongs to the live depth readout
					# from here on, and a one-frame prompt would simply never be read.
					_toast("The lead takes it down — %s on the hook." % _bait_name(_bait_id))
				else:
					_state = State.DRIFT
					# The water read: teach the variables by naming them every cast.
					_prompt("Line's out — %s" % FISH.summary(FISH.context(self, global_position)))
			elif global_position.distance_to(_hand_pos()) > (DEEP_MAX_RANGE if _deep else MAX_RANGE):
				# Say something rather than letting the line evaporate: a silent _finish("")
				# here is exactly what made the deep rig look like it did nothing at all.
				_finish("Out of line — drop it over the side, into open water." if _deep else "")
				return
		State.DRIFT:
			_ride_water(t, delta)
			_bite_timer -= delta
			if _bite_timer <= 0.0:
				if _nibbles > 0:
					_nibbles -= 1
					_dip = 0.16   # a lying little tug
					AudioDirector.play_one_shot("splash", global_position, -26.0)
					_bite_timer = _rng.randf_range(1.8, 5.0)
				else:
					_state = State.BITE
					_bite_window = BITE_WINDOW
					_dip = 0.45
					AudioDirector.play_one_shot("splash", global_position, -8.0)
					_take()
					_prompt("!!!  THAT IS A BIG ONE   [LMB] STRIKE" if _pending_is_trophy() \
						else "!!!  [LMB] STRIKE")
		State.SINK:
			# THE DEEP RIG'S OWN STATE, and the whole point of the tool: the lead sinks and
			# keeps sinking, and what can bite grows deeper the further down the bait gets.
			# Nothing here touches the wave surface — it is under it.
			_sink(delta)
			# The bait has to be in SOMEBODY's water before it can be taken; above the
			# shallowest drop depth in the table the line is only falling through the light.
			if _depth >= FISH.min_drop_depth():
				# A glowing bait in black water brings the bite on sooner, a dull one takes
				# longer — read LIVE off the current depth (FishTable.bait_rate) rather than
				# baked into the wait back at the cast, when the lead was still in the air.
				_bite_timer -= delta * FISH.bait_rate(_bait_id, _depth)
				if _bite_timer <= 0.0:
					if _nibbles > 0:
						_nibbles -= 1
						_dip = 0.5   # something down there knocked the lead
						AudioDirector.play_one_shot("scuttle_a", _hand_pos(), -26.0)
						_bite_timer = _rng.randf_range(1.8, 5.0)
					else:
						_state = State.BITE
						_bite_window = BITE_WINDOW
						_dip = 1.4   # the line RUNS — no float to duck, the rod loads instead
						# THE BAIT IS SPENT HERE, not at the splash and not on the strike
						# (owner spec 2026-07-27): a nibble is a lie and costs nothing, a
						# reel-in with no bite at all costs nothing, but something real
						# taking the hook — whether or not the player then lands it — is
						# the one moment that actually uses the bait up.
						if _bait_id != "":
							PlayerState.remove_item(_bait_id)
						AudioDirector.play_one_shot("clang", _hand_pos(), -22.0)
						_take()
						_prompt(("!!!  SOMETHING BIG HAS IT AT %d m   [LMB] STRIKE" \
							if _pending_is_trophy() \
							else "!!!  SOMETHING HAS IT AT %d m   [LMB] STRIKE") % int(_depth))
		State.BITE:
			if _deep:
				_hold_depth()
			else:
				_ride_water(t, delta)
			_bite_window -= delta
			if _bite_window <= 0.0:
				_state = State.SINK if _deep else State.DRIFT
				_pending = {}   # whatever had it, it is not on the hook any more
				if _deep:
					_toast("It let go. The line goes slack.")
					_shown_m = -1   # bring the depth readout (and the reel-in hint) back
				else:
					_prompt("It let go. The float settles.")
				_schedule_bite()
		State.FIGHT:
			_fight(delta, t)
		State.DONE:
			return
	# Walked off mid-cast: the line comes in on its own.
	if _state != State.DONE and _player.global_position.distance_to(_cast_origin) > CANCEL_DISTANCE:
		_finish("")
		return
	_dip = move_toward(_dip, 0.0, delta * 0.8)
	_update_line()

func _ride_water(t: float, _delta: float) -> void:
	global_position.y = Gyre.wave_height(Vector2(global_position.x, global_position.z), t) * 0.85 + 0.02 - _dip

## The deep rig's line-out. The lead pulls the spool down at its own rate and the prompt
## reads the depth back, because depth is the mechanic: every metre opens more of the
## table (fish.json drop_m) and the pool skews deeper the longer you let it run.
##
## Two things stop it and the tighter one wins. DEEP_MAX_DEPTH is the real one: 48 m of
## water, deeper than the deepest drop_m in the table, so EVERY spot that overlooks water
## can reach every species — which is the whole point of the brief and the reason the drop
## height is deliberately NOT made to cost you depth. DEEP_MAX_RANGE (total line out from
## the hand) only ever bites from an absurd height, and is kept as the backstop that stops
## the line growing without limit; the highest drop on the rig spends ~42 m of it.
func _sink(delta: float) -> void:
	if not _spool_end:
		_depth = minf(_depth + DEEP_SINK_RATE * delta, DEEP_MAX_DEPTH)
	_hold_depth()
	if not _spool_end and (_depth >= DEEP_MAX_DEPTH \
			or global_position.distance_to(_hand_pos()) >= DEEP_MAX_RANGE):
		_hold_the_spool(false)
		return
	var m: int = int(_depth)
	if m != _shown_m:
		_shown_m = m
		if _spool_end:
			_prompt("Holding at %d m · %s   [LMB] reel in" % [m, FISH.depth_read(_depth)])
		else:
			_prompt("Line down %d m · %s   [LMB] hold the spool" % [m, FISH.depth_read(_depth)])

## Stop paying line out and fish whatever depth the lead has reached. Called both when the
## spool physically runs out and when the player thumbs the drum — the same condition, and
## the reason DEPTH IS A CHOICE rather than a timer: hold it shallow for the grouper, let it
## all the way out for what lives at the end of the line.
func _hold_the_spool(thumbed: bool) -> void:
	# Is there anything in this water at all? If the PLAYER asked for the hold, refuse the
	# hold and keep paying out: the bait is already spent, and "that is too shallow" teaches
	# better with the line still running than with the drop thrown away. If the SPOOL ran
	# out there is no deeper to go, so the line comes in and says why.
	if FISH.pool_weight("deep", FISH.context(self, global_position, _bait_id), _depth) <= 0.0:
		if thumbed:
			_toast("Nothing lives as shallow as %d m — let the spool run." % int(_depth))
		else:
			_abort_msg = "Spool's end at %d m, above the lot of them. Drop it from lower down." % int(_depth)
		return
	_spool_end = true
	_shown_m = -1   # force the readout to redraw and say the line has stopped
	if thumbed:
		AudioDirector.play_one_shot("clang", _hand_pos(), -28.0)   # the drum stops turning
		_toast("Thumb on the drum — %d m, %s." % [int(_depth), FISH.depth_read(_depth)])

## Where the deep lead hangs: plumb below where it splashed, at its current depth, minus
## whatever the last knock on the line snatched it by. The swell is above it and has
## nothing to do with it — this is why the deep rig never calls _ride_water().
func _hold_depth() -> void:
	global_position.y = -_depth - _dip

## SOMETHING TAKES THE BAIT. Rolls what it is — from the live conditions at THIS tackle,
## THIS moment, off the pool the tool is fishing (the deep rig draws deep-flagged species
## gated on how far the lead has sunk and on what is on the hook; the surface rod rolls
## "rod" with no depth and no bait, exactly as before) — and, if it is a monster, throws the
## jolt and the flash right now, while the player still has to decide whether to strike.
func _take() -> void:
	_pending = FISH.roll("deep" if _deep else "rod",
		FISH.context(self, global_position, _bait_id), _rng, _depth if _deep else -1.0)
	if _pending_is_trophy():
		_big_bite_feedback()

func _pending_is_trophy() -> bool:
	return not _pending.is_empty() and FISH.is_trophy(String(_pending.get("id", "")))

## The punch. A short hard rumble on the pad and a pale flash across the whole screen, both
## gone inside a fifth of a second — you feel it before you have read anything.
##
## The overlay is OURS: its own CanvasLayer parented to the scene (not to this rod, which
## frees itself the moment the line comes in) so it always survives long enough to fade,
## and it never needs a line of hud.gd. MOUSE_FILTER_IGNORE so a flash can never eat the
## click the player is about to make with it.
func _big_bite_feedback() -> void:
	# No pad plugged in, no vibration — start_joy_vibration on a device that isn't there is
	# harmless, but asking first keeps it honest and costs one array length.
	if not Input.get_connected_joypads().is_empty():
		Input.start_joy_vibration(0, JOLT_WEAK, JOLT_STRONG, JOLT_SEC)
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 5
	var rect := ColorRect.new()
	rect.color = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	scene.add_child(layer)
	var tw: Tween = rect.create_tween()
	tw.tween_property(rect, "color:a", FLASH_PEAK, FLASH_IN)
	tw.tween_property(rect, "color:a", 0.0, FLASH_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(layer.queue_free)

func _hook() -> void:
	# Spend the roll made at the take (see _pending). Falling back to a fresh roll keeps the
	# strike honest if the pre-roll was ever skipped.
	_fish = _pending if not _pending.is_empty() else FISH.roll("deep" if _deep else "rod",
		FISH.context(self, global_position, _bait_id), _rng, _depth if _deep else -1.0)
	_pending = {}
	if _fish.is_empty():
		_finish("Whatever it was, it's gone.")
		return
	_state = State.FIGHT
	_tension = 0.3
	_progress = 0.35
	_fight_t = 0.0
	Journal.discover("system_fishing")

func _fight(delta: float, t: float) -> void:
	_fight_t += delta
	var pull: float = _fish["pull"]
	# The fish surges in waves — reel the lulls, respect the surges.
	var surge: float = 0.5 + 0.5 * sin(_fight_t * (1.1 + pull * 0.5))
	if _reeling:
		_progress += (REEL_RATE / _fish["fight"]) * delta
		_tension += (0.28 + surge * pull * 0.55) * delta
	else:
		_tension -= TENSION_DECAY * delta
		_progress -= surge * pull * 0.035 * delta
	_tension = clampf(_tension, 0.0, 1.2)
	_progress = clampf(_progress, 0.0, 1.0)
	if _deep:
		# There is no float to watch, so the FIGHT is the line: winning it lifts the lead —
		# and whatever is on it — up out of the dark toward you, and every surge you have to
		# give it takes some of that back. You can see how far you have left to bring it.
		global_position.y = -(_depth + DEEP_FIGHT_SURGE * surge) * (1.0 - _progress)
	else:
		# The float drags toward the fish's runs.
		global_position.y = Gyre.wave_height(Vector2(global_position.x, global_position.z), t) * 0.85 - 0.2 * surge
	if _tension >= 1.0:
		AudioDirector.play_one_shot("scuttle_a", _hand_pos(), -16.0)   # dry snap of parting line
		_finish("The line parts. Gone.")
		return
	if _progress <= 0.0:
		_finish("It spat the hook and ran.")
		return
	if _progress >= 1.0:
		_land()
		return
	if _deep:
		_prompt("FIGHT  %d m to bring up   [hold LMB] reel   line %s   strain %s" \
			% [int(_depth * (1.0 - _progress)), _bar(_progress), _bar(_tension)])
	else:
		_prompt("FIGHT  [hold LMB] reel   line %s   strain %s" % [_bar(_progress), _bar(_tension)])

static func _bar(v: float) -> String:
	var n: int = clampi(int(v * 8.0), 0, 8)
	return "▮".repeat(n) + "▯".repeat(8 - n)

func _land() -> void:
	AudioDirector.play_one_shot("splash", global_position, -6.0)
	if _fish.get("release", false):
		# Canon: it is never kept. The catch is the moment.
		Journal.discover("fish_the_looker")
		_finish("It surfaces — and looks back at you. Your hands open on their own.")
		return
	var id: String = String(_fish["id"])
	Journal.discover(id)
	if not PlayerState.add_item(id):
		_finish("Pack's full — the %s slips back." % _fish["name"])
		return
	_fly_catch_to_player()
	# THE SIZE OF THE FISH, rolled here, at the rail, on the one fish that was actually
	# landed — and remembered on the table (FishTable.record_size) so the stove and the
	# drying line can fillet THIS fish rather than an average one. Species with no size
	# range in fish.json roll 0.0 and read exactly as they always did.
	var kg: float = FISH.roll_size(id, _rng)
	_log_catch(id, kg)
	if kg <= 0.0:
		_finish("Caught: %s" % _fish["name"])
		return
	FISH.record_size(id, kg)
	var n: int = FISH.fillets_for(id, kg)
	if n <= 1:
		_finish("Caught: %s — %.1f kg" % [_fish["name"], kg])
		return
	# Name the payoff at the moment it is earned: the whole reason to fight a fish this
	# big is what it fillets out into on the stove or the line.
	_finish("Caught: %s — %.1f kg. That'll fillet out %d times over." % [_fish["name"], kg, n])

## The visual payoff: the fish arcs out of the water into your hands, flashing
## and flipping, then vanishes into the pack. Owned by the scene, so it plays
## out even though the rod frees itself immediately after.
func _fly_catch_to_player() -> void:
	var fish_visual: Node3D = ItemVisual.build(_fish["id"])
	get_tree().current_scene.add_child(fish_visual)
	fish_visual.global_position = global_position
	var dest: Vector3 = _player.global_position + Vector3(0, 1.1, 0)
	var apex: Vector3 = (global_position + dest) * 0.5 + Vector3(0, 2.6, 0)
	var tw: Tween = fish_visual.create_tween()
	tw.tween_property(fish_visual, "global_position", apex, 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(fish_visual, "global_position", dest, 0.26) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(fish_visual, "rotation:x", TAU * 1.5, 0.26)
	tw.tween_callback(fish_visual.queue_free)

## THE JOURNAL ENTRY. Everything the rail knows about this particular fish, handed to
## Journal.record_catch — which writes it into the species' own {cat,title,body,hint} entry
## on the FIRST catch and, after that, only updates the best-specimen line if this one beat
## it. Nothing here is invented: the weight comes from fish.json's size_kg, the depth and
## its plain-words band from the deep rig's own readout, phase/weather from the same catch
## context the roll used, the bait from what was actually on the hook, and the flavour line
## from the species' note in fish.json.
func _log_catch(id: String, kg: float) -> void:
	var ctx: Dictionary = FISH.context(self, global_position, _bait_id)
	var conditions: Array[String] = []
	if ctx["storming"]:
		conditions.append("Storm sea")
	if ctx["lit"]:
		conditions.append("worklights burning")
	if conditions.is_empty():
		conditions.append("Quiet water")
	conditions.append("open water" if ctx["open"] else "in the rig's shadow")
	Journal.record_catch(id, {
		"name": String(_fish.get("name", id)),
		"flavour": String(_fish.get("note", "")),
		"kg": kg,
		"depth_m": _depth if _deep else -1.0,
		"band": FISH.depth_read(_depth) if _deep else "",
		"phase": String(ctx["phase"]),
		"weather": ", ".join(conditions),
		"bait": _bait_name(_bait_id) if _bait_id != "" else "",
	})

func _prompt(text: String) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_prompt_raw(text)

## A message that lingers on its own, for the beats where the prompt line is already
## carrying something live (the deep rig's depth readout).
func _toast(text: String) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toast(text)

func _finish(msg: String) -> void:
	_state = State.DONE
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_prompt("")
		if msg != "":
			hud.toast(msg)
	if _player and _player.has_method("fishing_done"):
		_player.fishing_done()
	queue_free()

## Stretch the line mesh exactly from the rod tip (a) to the float (b). MUST land on
## BOTH points exactly, every frame, wherever the bob drifts to — that was the bug:
## the old version shifted the cylinder's PIVOT down for a slack "sag" look, then called
## look_at(b) FROM that shifted pivot. look_at only orients toward b; it does not correct
## for the pivot having moved, so the far half of the cylinder (extending the opposite way
## from the same shifted point) missed the true `a` by roughly twice the sag offset — a
## fixed, cosmetic, unrelated-to-anchoring line that read as "the line just lies near the
## water", never actually reaching the rod. This builds the segment directly from a
## transform basis (StructureLib.line()'s technique): dist is the true a-b span, mid is the
## true a-b midpoint, and the basis's Y axis (a CylinderMesh's own length axis) is set to
## point exactly along a->b, so the two ends of the cylinder are ALWAYS exactly a and b —
## no reorientation step that can drift off either endpoint.
func _update_line() -> void:
	var a: Vector3 = _hand_pos()
	var b: Vector3 = global_position + Vector3(0, 0.05, 0)
	var delta: Vector3 = b - a
	var dist: float = delta.length()
	_line_mesh.height = dist
	_line.global_position = (a + b) * 0.5
	if dist > 0.001:
		var dir: Vector3 = delta / dist
		var ref: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		var xa: Vector3 = ref.cross(dir).normalized()
		var za: Vector3 = dir.cross(xa).normalized()
		_line.global_transform = Transform3D(Basis(xa, dir, za), _line.global_position)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	match _state:
		State.BITE:
			if event.pressed:
				_hook()
				# THE STRIKE-AND-HOLD GLITCH: the press that triggers _hook() is still down
				# at this exact instant, but _reeling (read by State.FIGHT below) only ever
				# used to get set from a LATER, separate mouse event. A player who struck by
				# pressing LMB and just kept holding it — the natural motion, and the same
				# gesture FIGHT itself asks for — saw the line do nothing until they let go
				# and clicked again. _hook() only ever transitions BITE -> FIGHT, so reading
				# _state right after it is enough to know the strike landed.
				_reeling = _state == State.FIGHT
				get_viewport().set_input_as_handled()
		State.FIGHT:
			_reeling = event.pressed
			get_viewport().set_input_as_handled()
		State.DRIFT:
			if event.pressed:
				_finish("")   # reel in early
				get_viewport().set_input_as_handled()
		State.SINK:
			if event.pressed:
				# One button, two jobs, in the order a hand-line actually uses them: the
				# first press stops the drum and fishes THIS depth (which is how the player
				# chooses their species), the second hauls the lead back up.
				if _spool_end:
					_finish("")
				else:
					_hold_the_spool(true)
				get_viewport().set_input_as_handled()
