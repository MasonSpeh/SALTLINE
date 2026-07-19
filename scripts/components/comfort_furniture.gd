class_name ComfortFurniture extends Node
## The comfort layer: what turns a pile of placed kits into somewhere you live.
##
## Structures built by the player expose child marker nodes in the group
## "comfort_furniture", each carrying a meta "kind" — bed / seat / fire / storage /
## bench / drying / water / planter. This manager watches for those markers and bolts the right
## Interactable onto each one, so the structures domain never has to know how sitting,
## sleeping or burning works, and this file never has to know what a chair looks like.
##
## It also does the quiet accounting: it reads the world every few frames (seated? warm?
## under cover? inside your own camp? out in a squall?) and writes PlayerState.comfort_target.
## Comfort is not a score the player plays toward. It is the game noticing.
##
## Lives as a child of the PlayerState autoload (see PlayerState._ready) so it survives
## scene reloads and needs no project.godot entry.

const LOOT := preload("res://scripts/components/loot_container.gd")
const BENCH := preload("res://scripts/components/craft_bench.gd")
const HANG := preload("res://scripts/components/hang_line.gd")

const GROUP := "comfort_furniture"
const KINDS: Array[String] = ["bed", "seat", "fire", "storage", "bench", "drying", "water", "planter"]

## Default interaction volumes per kind, when a marker doesn't specify meta "size".
## Kept small and tucked inside the structure's own geometry so these never become
## invisible walls the player bumps into.
const DEFAULT_SIZE: Dictionary = {
	"bed": Vector3(1.9, 0.45, 0.8),
	"seat": Vector3(0.6, 0.5, 0.6),
	"fire": Vector3(0.7, 0.8, 0.7),
	"storage": Vector3(0.8, 1.0, 0.5),
	"bench": Vector3(1.4, 0.9, 0.7),
	"water": Vector3(0.7, 0.9, 0.7),
	"planter": Vector3(1.0, 0.3, 0.6),
}

const RESCAN_SEC: float = 1.5      ## belt-and-braces sweep, in case a marker joined its group late
const TICK_SEC: float = 0.35       ## how often the comfort reading is recomputed
const CAMP_RADIUS: float = 8.0     ## "within about eight metres of each other"
const CAMP_MIN_PIECES: int = 3     ## three of your own things, standing together
const FIRE_COMFORT_RANGE: float = 4.5
const SHELTER_COVER: float = 0.35  ## StormSystem cover fraction that counts as "a roof"

# Comfort weights — each a thing the player did on purpose.
const W_SEATED: float = 0.35
const W_WARM: float = 0.15
const W_SHELTER: float = 0.15
const W_CAMP: float = 0.35
const W_FIRE: float = 0.15
const P_EXPOSED_STORM: float = 0.5

# Comfort read-out bands, with hysteresis so the line never flickers.
const BAND_UP: Array[float] = [0.0, 0.30, 0.62]
const BAND_DOWN: Array[float] = [0.0, 0.20, 0.50]
const NOTE_COOLDOWN_SEC: float = 60.0

var _attached: Dictionary = {}      ## marker instance id -> proxy node
var _rescan_t: float = 0.0
var _tick_t: float = 0.0

# Sitting is a scripted park, not a posture: the player controller is left completely
# alone (another domain owns it). We lock movement, swap in our own eye, and let the
# controller's existing mouse-look drive the aim so standing up is seamless.
var _sit_marker: Node3D = null
var _sit_player: Node3D = null
var _sit_cam: Camera3D = null
var _sit_from: Vector3 = Vector3.ZERO
var _sit_blend: float = 0.0
var _sit_guard: float = 0.0
var _sit_prev_input_locked: bool = false
var _sit_prev_ui_locked: bool = false

var _comfort_band: int = 0
var _note_cd: float = 0.0
var _camp_center: Vector3 = Vector3.ZERO
var _camp_active: bool = false

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	PlayerState.player_died.connect(_on_player_died)
	call_deferred("_scan")

func _on_node_added(n: Node) -> void:
	# Fast path: the rig spawns thousands of nodes, so only markers that already
	# carry the group pay anything here. A structure that groups its children after
	# the fact is picked up by the RESCAN_SEC sweep instead.
	if n is Node3D and n.is_in_group(GROUP):
		call_deferred("_attach", n)

func _on_player_died() -> void:
	if _sit_marker != null:
		stand()

func _scan() -> void:
	# Forget proxies whose furniture has been dismantled, or the dictionary grows a
	# tail of freed objects that every later sweep has to step over.
	for id: int in _attached.keys():
		if not is_instance_valid(_attached[id]):
			_attached.erase(id)
	for n in get_tree().get_nodes_in_group(GROUP):
		_attach(n)

## Give one marker its interactable. Idempotent — safe to call every sweep.
## `marker` is deliberately untyped: this arrives via call_deferred, and a marker
## freed before the call lands fails the Object->Node conversion at the call
## boundary — before any guard in here could catch it.
func _attach(marker: Variant) -> void:
	if not is_instance_valid(marker) or not marker is Node3D or not marker.is_in_group(GROUP):
		return
	var id: int = marker.get_instance_id()
	if _attached.has(id) and is_instance_valid(_attached[id]):
		return
	var kind: String = String(marker.get_meta("kind", ""))
	if not KINDS.has(kind):
		return
	var proxy: Interactable = _make_proxy(kind, marker)
	if proxy == null:
		return
	marker.add_child(proxy)
	proxy.position = Vector3.ZERO
	_attached[id] = proxy

func _make_proxy(kind: String, marker: Node3D) -> Interactable:
	match kind:
		"bed":
			var bed := CampBed.new()
			bed.manager = self
			_fit(bed, _size_for(kind, marker))
			return bed
		"seat":
			var seat := Seat.new()
			seat.manager = self
			_fit(seat, _size_for(kind, marker))
			return seat
		"fire":
			var fire := Hearth.new()
			_fit(fire, _size_for(kind, marker))
			return fire
		"storage":
			# A locker is a crate with a different silhouette — reuse the crate ⇄ pack
			# exchange panel the HUD already owns rather than inventing a second one.
			var box: LootContainer = LOOT.new()
			box.display_name = String(marker.get_meta("label", "Locker"))
			_fit(box, _size_for(kind, marker))
			return box
		"bench":
			# Crafting away from the wet deck: the same CraftBench flow, verbatim.
			var bench: CraftBench = BENCH.new()
			_fit(bench, _size_for(kind, marker))
			return bench
		"drying":
			# The drying line already knows how cooked fish cures into dried_fish and
			# how raw fish turns. It builds its own rope and collider.
			var line: HangLine = HANG.new()
			line.length_m = float(marker.get_meta("span", 2.4))
			return line
		"water":
			var butt := RainButt.new()
			_fit(butt, _size_for(kind, marker))
			return butt
		"planter":
			var bed := Planter.new()
			_fit(bed, _size_for(kind, marker))
			return bed
	return null

func _size_for(kind: String, marker: Node3D) -> Vector3:
	var m: Variant = marker.get_meta("size", null)
	if m is Vector3:
		return m
	return DEFAULT_SIZE.get(kind, Vector3(0.8, 0.8, 0.8))

## Interaction volume only. The structure's own geometry is what the player walks into;
## this box sits inside it so it adds a target, not an obstacle.
static func _fit(body: Interactable, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

# ============================== sitting =====================================

## THE comforting moment: a deck chair, the rain on the tarp, the sea doing its work.
func sit(marker: Node3D, player: Node3D) -> void:
	if _sit_marker != null or player == null or not is_instance_valid(marker):
		return
	var cam: Camera3D = player.get("camera") as Camera3D
	if cam == null:
		return
	_sit_marker = marker
	_sit_player = player
	_sit_prev_input_locked = bool(player.input_locked)
	_sit_prev_ui_locked = bool(player.ui_locked)
	player.input_locked = true   # look, don't walk
	player.ui_locked = true      # and the interaction ray stands down; we own [E] now
	player.velocity = Vector3.ZERO
	_sit_from = cam.global_position
	_sit_blend = 0.0
	_sit_guard = 0.3
	_sit_cam = Camera3D.new()
	_sit_cam.fov = cam.fov
	marker.add_child(_sit_cam)
	_sit_cam.global_transform = cam.global_transform
	_sit_cam.make_current()
	PlayerState.resting = true
	AudioDirector.play_one_shot("hiss", marker.global_position, -26.0)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set_hint("[E]   get up")
		hud.toast("You sit. Nothing needs you for a moment.")

func stand() -> void:
	var player: Node3D = _sit_player
	_sit_marker = null
	_sit_player = null
	if is_instance_valid(_sit_cam):
		_sit_cam.queue_free()
	_sit_cam = null
	PlayerState.resting = false
	if is_instance_valid(player):
		player.input_locked = _sit_prev_input_locked
		player.ui_locked = _sit_prev_ui_locked
		var cam: Camera3D = player.get("camera") as Camera3D
		if cam:
			cam.make_current()
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set_hint("")

func is_seated() -> bool:
	return _sit_marker != null

func _unhandled_input(event: InputEvent) -> void:
	if _sit_marker == null or _sit_guard > 0.0:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel") \
			or event.is_action_pressed("jump"):
		stand()
		get_viewport().set_input_as_handled()

func _update_seat(delta: float) -> void:
	if _sit_marker == null:
		return
	_sit_guard = maxf(0.0, _sit_guard - delta)
	if not is_instance_valid(_sit_marker) or not is_instance_valid(_sit_player) \
			or not is_instance_valid(_sit_cam):
		stand()
		return
	var player_cam: Camera3D = _sit_player.get("camera") as Camera3D
	if player_cam == null:
		stand()
		return
	# Re-assert the locks every frame: opening and closing a HUD panel while seated
	# would otherwise hand movement back without ever standing you up.
	_sit_player.input_locked = true
	_sit_player.ui_locked = true
	# Eye settles down and back into the seat over about half a second. Aim is copied
	# straight off the player's own camera, so the controller's mouse-look still steers
	# and standing up doesn't snap the view anywhere.
	_sit_blend = minf(1.0, _sit_blend + delta * 2.0)
	var t: float = 1.0 - pow(1.0 - _sit_blend, 3.0)
	var eye_h: float = float(_sit_marker.get_meta("eye", 0.62))
	var seated: Vector3 = _sit_marker.global_transform * Vector3(0.0, eye_h, 0.10)
	_sit_cam.global_transform = Transform3D(player_cam.global_transform.basis,
		_sit_from.lerp(seated, t))

# ============================== the reading =================================

func _process(delta: float) -> void:
	_update_seat(delta)
	_note_cd = maxf(0.0, _note_cd - delta)
	_rescan_t += delta
	if _rescan_t >= RESCAN_SEC:
		_rescan_t = 0.0
		_scan()
	_tick_t += delta
	if _tick_t < TICK_SEC:
		return
	_tick_t = 0.0
	_update_comfort()

func _update_comfort() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		PlayerState.comfort_target = 0.0
		return
	var pos: Vector3 = player.global_position
	var storming: bool = false
	var cover: float = 0.0
	var storm: Object = _storm()
	if storm:
		storming = bool(storm.call("is_storming"))
		var c: Variant = storm.get("_cover_frac")
		if c != null:
			cover = float(c)
	var sheltered: bool = cover >= SHELTER_COVER
	_update_camp(pos)

	var target: float = 0.0
	if PlayerState.resting:
		target += W_SEATED
	if PlayerState.warmth > 0.6:
		target += W_WARM
	if sheltered:
		target += W_SHELTER
	if _camp_active and pos.distance_to(_camp_center) <= CAMP_RADIUS:
		target += W_CAMP
	if _near_lit_fire(pos):
		target += W_FIRE
	if storming and not sheltered:
		target -= P_EXPOSED_STORM   # a squall on open deck undoes a lot of coziness
	PlayerState.comfort_target = clampf(target, 0.0, 1.0)
	_update_band()

func _storm() -> Object:
	var scene: Node = get_tree().current_scene
	if scene and scene.get("storm") != null:
		return scene.get("storm")
	return null

func _near_lit_fire(pos: Vector3) -> bool:
	for id in _attached:
		var proxy: Variant = _attached[id]
		# Validity first: `is` against a freed instance is itself an error, and this
		# runs every 0.35s forever because _attached never forgot its dead proxies.
		if is_instance_valid(proxy) and proxy is Hearth and (proxy as Hearth).lit:
			if (proxy as Hearth).global_position.distance_to(pos) <= FIRE_COMFORT_RANGE:
				return true
	return false

## A camp is three or more of your own structures standing within eight metres of a
## bed or a fire. Not a build menu unlock — just the game noticing you settled somewhere.
func _update_camp(_pos: Vector3) -> void:
	_camp_active = false
	var built: Array = get_tree().get_nodes_in_group("built_structures")
	if built.size() < CAMP_MIN_PIECES:
		return
	for id in _attached:
		var proxy: Variant = _attached[id]
		if not is_instance_valid(proxy):
			continue
		if not (proxy is Hearth or proxy is CampBed):
			continue
		var anchor: Vector3 = (proxy as Node3D).global_position
		var count: int = 0
		for s in built:
			if s is Node3D and is_instance_valid(s) \
					and (s as Node3D).global_position.distance_to(anchor) <= CAMP_RADIUS:
				count += 1
		if count >= CAMP_MIN_PIECES:
			_camp_active = true
			_camp_center = anchor
			if not PlayerState.camp_found:
				PlayerState.camp_found = true
				Journal.discover("place_camp")   # no-ops if the entry doesn't exist yet
				var hud: Node = get_tree().get_first_node_in_group("hud")
				if hud:
					# NOT a statement of the rule. The old line ("Three things you
					# made, standing together. That's a camp.") read the detection
					# threshold back to the player — the one place the writing
					# dropped out of the fiction and into the mechanic. This is the
					# same beat without the counting.
					hud.comfort_note("You look up, and it's a place now. Not a spot.")
					# Claim the note channel: a comfort band change crossing in the
					# same breath would otherwise overwrite the one line in the game
					# that only ever gets said once.
					_note_cd = NOTE_COOLDOWN_SEC
			return

## The comfort read-out: a short line, only when the state actually changes, never twice
## inside a minute. Comfort itself is never drawn as a number.
func _update_band() -> void:
	var c: float = PlayerState.comfort
	var band: int = _comfort_band
	if band < 2 and c >= BAND_UP[2]:
		band = 2
	elif band < 1 and c >= BAND_UP[1]:
		band = 1
	elif band == 2 and c < BAND_DOWN[2]:
		band = 1
	if band >= 1 and c < BAND_DOWN[1]:
		band = 0
	if band == _comfort_band:
		return
	var rising: bool = band > _comfort_band
	var was: int = _comfort_band
	_comfort_band = band
	if _note_cd > 0.0:
		return
	var line: String = ""
	if rising and band == 1:
		line = "The wind is off you here."
	elif rising and band == 2:
		line = "This feels like somewhere to come back to."
	elif not rising and band == 0 and was >= 1:
		line = "Out in it again."
	if line == "":
		return
	_note_cd = NOTE_COOLDOWN_SEC
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("comfort_note"):
		hud.comfort_note(line)

# ============================== proxies =====================================

## SLEEP on a bedroll you laid yourself. Same shape as the rig's bunks (bed.gd) —
## night or dusk only, fade out, wake at dawn — but this one is yours.
class CampBed extends Interactable:
	var manager: Node = null
	var _busy: bool = false

	func _init() -> void:
		display_name = "Bedroll"
		verbs = ["SLEEP"] as Array[String]

	func available_verbs() -> Array[String]:
		if _busy:
			return [] as Array[String]
		if GameClock.current_phase == GameClock.Phase.NIGHT \
				or GameClock.current_phase == GameClock.Phase.DUSK:
			return ["SLEEP"] as Array[String]
		return [] as Array[String]

	func interact(verb: String, player: Node3D) -> void:
		if _busy:
			return
		_busy = true
		super.interact(verb, player)
		if player:
			player.input_locked = true
		PlayerState.resting = true
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			var t: Tween = hud.fade_to_black(1.0)
			if t:
				t.tween_callback(_on_dark.bind(player))
				return
		_on_dark(player)

	func _on_dark(player: Node3D) -> void:
		AudioDirector.play_one_shot("hiss", global_position, -16.0)
		GameClock.skip_to_next_dawn()
		PlayerState.sleep_recovery()
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			var t: Tween = hud.fade_from_black(1.0)
			if t:
				t.tween_callback(_on_wake.bind(player))
				return
		_on_wake(player)

	func _on_wake(player: Node3D) -> void:
		if is_instance_valid(player):
			player.input_locked = false
		PlayerState.resting = false
		_busy = false
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("Your own bed, in your own place. You wake rested, and hungry for it.")


## SIT. All the work happens in the manager — the proxy is just the thing you look at.
class Seat extends Interactable:
	var manager: Node = null

	func _init() -> void:
		display_name = "Chair"
		verbs = ["SIT"] as Array[String]

	func available_verbs() -> Array[String]:
		if manager and manager.call("is_seated"):
			return [] as Array[String]
		return ["SIT"] as Array[String]

	func interact(verb: String, player: Node3D) -> void:
		super.interact(verb, player)
		if manager and player:
			manager.call("sit", get_parent() as Node3D, player)


## A brazier: LIGHT it with driftwood, it throws heat and light while the wood lasts,
## BANK it to save what's left. Heat is a real WarmthZone — the same volume the fire
## barrel on the wet deck uses — so the cold respects it exactly like everything else.
class Hearth extends Interactable:
	const HOURS_PER_LOG: float = 2.0
	const FUEL_CAP: float = 8.0
	const FUEL_ID: String = "driftwood"

	var lit: bool = false
	var fuel_h: float = 0.0            ## game hours of burn left
	var _zone: WarmthZone = null
	var _light: OmniLight3D = null
	var _flame: MeshInstance3D = null
	var _hour_per_sec: float = 0.0
	var _flicker: float = 0.0

	func _init() -> void:
		display_name = "Brazier"
		verbs = ["LIGHT"] as Array[String]

	func _ready() -> void:
		var day_sec: float = 0.0
		for phase in GameClock.phase_durations_minutes:
			day_sec += GameClock.phase_durations_minutes[phase] * 60.0
		_hour_per_sec = 24.0 / maxf(day_sec, 1.0)

	func available_verbs() -> Array[String]:
		if lit:
			# A fire that wants feeding asks for it first; otherwise you can bank it.
			if fuel_h < HOURS_PER_LOG and PlayerState.has_item(FUEL_ID):
				return ["FEED", "BANK"] as Array[String]
			return ["BANK"] as Array[String]
		if fuel_h > 0.0 or PlayerState.has_item(FUEL_ID):
			return ["LIGHT"] as Array[String]
		return [] as Array[String]

	func get_prompt() -> String:
		var v: Array[String] = available_verbs()
		if v.is_empty():
			return ""
		if not lit and fuel_h <= 0.0:
			return "LIGHT  %s (driftwood)" % display_name
		return "%s  %s" % [v[0], display_name]

	func interact(verb: String, player: Node3D) -> void:
		super.interact(verb, player)
		match verb:
			"LIGHT":
				if fuel_h <= 0.0 and not _take_log():
					return
				_set_lit(true)
				AudioDirector.play_one_shot("hiss", global_position, -10.0)
				_say("The driftwood catches. Salt in it — the flame goes green at the edges.")
			"FEED":
				if _take_log():
					AudioDirector.play_one_shot("clang", global_position, -24.0)
					_say("You feed the fire. It settles back into its work.")
			"BANK":
				_set_lit(false)
				AudioDirector.play_one_shot("hatch", global_position, -22.0)
				_say("You bank the coals. They'll keep till you want them.")

	func _take_log() -> bool:
		if not PlayerState.has_item(FUEL_ID):
			return false
		PlayerState.remove_item(FUEL_ID)
		fuel_h = minf(FUEL_CAP, fuel_h + HOURS_PER_LOG)
		return true

	func _say(text: String) -> void:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast(text)

	func _set_lit(on: bool) -> void:
		if on == lit:
			return
		lit = on
		if on:
			_zone = WarmthZone.new()
			_zone.mode = 1
			_zone.setup(Vector3(5.0, 3.0, 5.0))
			add_child(_zone)
			_zone.position = Vector3(0.0, 0.6, 0.0)
			_light = OmniLight3D.new()
			_light.light_color = Color(1.0, 0.62, 0.3)
			_light.omni_range = 8.0
			_light.light_energy = 2.1
			_light.light_volumetric_fog_energy = 1.2
			_light.shadow_enabled = true
			add_child(_light)
			_light.position = Vector3(0.0, 0.5, 0.0)
			# A tapered cone, not a cube. gl_compatibility has no glow pass, so an
			# emission multiplier of 3 does not bloom — it just clips every channel to
			# white and the fire photographs as a lightbulb in a drum. Keep the energy
			# near 1, let the albedo carry the colour, and let the OmniLight do the
			# work of making the deck look lit.
			_flame = MeshInstance3D.new()
			var fmsh := CylinderMesh.new()
			fmsh.top_radius = 0.02
			fmsh.bottom_radius = 0.17
			fmsh.height = 0.42
			fmsh.radial_segments = 8
			# Additive, not opaque. gl_compatibility has no glow pass, so an unshaded solid
			# cone is exactly that on screen — a traffic cone standing in the fire basket.
			# Additive blending with no depth write is what reads as flame here: it brightens
			# whatever is behind it, fades at the silhouette, and needs no post-processing.
			var fm := StandardMaterial3D.new()
			fm.albedo_color = Color(1.0, 0.62, 0.22, 0.55)
			fm.emission_enabled = true
			fm.emission = Color(1.0, 0.46, 0.12)
			fm.emission_energy_multiplier = 1.15
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			fm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			fm.cull_mode = BaseMaterial3D.CULL_DISABLED
			fmsh.material = fm
			_flame.mesh = fmsh
			_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(_flame)
			_flame.position = Vector3(0.0, 0.30, 0.0)
		else:
			_kill_heat()
			if is_instance_valid(_light):
				_light.queue_free()
			if is_instance_valid(_flame):
				_flame.queue_free()
			_light = null
			_flame = null

	## PlayerState.warmth_zone is an ADDITIVE counter: a zone that is freed while the
	## player stands inside it would never give its +1 back. Walk it out of the volume
	## and let its own balanced release run before the node goes away.
	func _kill_heat() -> void:
		if not is_instance_valid(_zone):
			_zone = null
			return
		_zone._player_inside = false
		_zone._process(0.0)
		_zone.queue_free()
		_zone = null

	func _exit_tree() -> void:
		_kill_heat()

	func _process(delta: float) -> void:
		if not lit:
			return
		fuel_h -= delta * GameClock.time_scale * _hour_per_sec
		if fuel_h <= 0.0:
			fuel_h = 0.0
			_set_lit(false)
			_say("The brazier gutters out. Cold comes back in around the edges.")
			return
		# Flicker: the light breathes, and the flame with it. Cheap, and the whole
		# reason a fire reads as alive on gl_compatibility.
		_flicker += delta
		var f: float = 1.0 + 0.16 * sin(_flicker * 7.3) + 0.09 * sin(_flicker * 17.1)
		if is_instance_valid(_light):
			_light.light_energy = 2.1 * f
		if is_instance_valid(_flame):
			_flame.scale = Vector3(1.0, 0.85 + 0.25 * f, 1.0)


## A rain catcher that actually catches rain. DRINK when there is water in the drum;
## it fills while a squall is on and creeps up on its own the rest of the time (the
## North Sea is never truly dry), and the water line in the drum rises and falls with
## it so you can read the level across the deck without a number anywhere.
##
## Why it lives here and not in structures.gd: structures.gd builds the drum, and this
## file owns what a piece of furniture DOES. The kit hangs a marker of kind "water"
## and neither file has to know the other's business.
class RainButt extends Interactable:
	const CAP_L: float = 12.0            ## litres the drum holds
	const DRINK_L: float = 1.5           ## a good long drink
	const THIRST_PER_DRINK: float = 0.42
	const STORM_L_PER_H: float = 5.0     ## a proper squall fills it in a couple of hours
	const DRIZZLE_L_PER_H: float = 0.35  ## spray, condensation, the general wet

	var litres: float = 0.0
	var _hour_per_sec: float = 0.0
	var _storm: Node = null
	var _water: MeshInstance3D = null
	var _sought: bool = false

	func _init() -> void:
		display_name = "Rain Catcher"
		verbs = ["DRINK"] as Array[String]

	func _ready() -> void:
		var day_sec: float = 0.0
		for phase in GameClock.phase_durations_minutes:
			day_sec += GameClock.phase_durations_minutes[phase] * 60.0
		_hour_per_sec = 24.0 / maxf(day_sec, 1.0)
		# The drum's own water disc, built by structures.gd, is the level indicator.
		var drum: Node = get_parent()
		if drum:
			_water = _find_water(drum.get_parent() if drum.get_parent() else drum)

	func _find_water(root: Node) -> MeshInstance3D:
		var stack: Array = [root]
		while stack.size() > 0:
			var n = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if n is MeshInstance3D and String(n.name).to_lower().contains("water"):
				return n
		return null

	func available_verbs() -> Array[String]:
		if litres >= DRINK_L:
			return ["DRINK"] as Array[String]
		return [] as Array[String]

	func get_prompt() -> String:
		if litres < DRINK_L:
			return ""
		return "DRINK  Rain Catcher (%d%% full)" % int(round(100.0 * litres / CAP_L))

	func interact(verb: String, player: Node3D) -> void:
		super.interact(verb, player)
		if verb != "DRINK" or litres < DRINK_L:
			return
		litres -= DRINK_L
		PlayerState.thirst = minf(1.0, PlayerState.thirst + THIRST_PER_DRINK)
		AudioDirector.play_one_shot("hiss", global_position, -18.0)
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("Rainwater, cold and flat and faintly of canvas. It's yours, and it's clean.")

	func _process(delta: float) -> void:
		if not _sought:
			_sought = true
			_storm = _find_storm()
		var rate: float = DRIZZLE_L_PER_H
		if is_instance_valid(_storm):
			rate += STORM_L_PER_H * clampf(float(_storm.get("_intensity")), 0.0, 1.0)
		litres = minf(CAP_L, litres + rate * delta * GameClock.time_scale * _hour_per_sec)
		if is_instance_valid(_water):
			var f: float = clampf(litres / CAP_L, 0.02, 1.0)
			_water.scale = Vector3(1.0, f, 1.0)

	## StormSystem is a child of Main, which is not our ancestor once the kit is placed
	## under a structures root — so search from the tree root, the way ambience.gd does.
	func _find_storm() -> Node:
		var stack: Array = [get_tree().root]
		while stack.size() > 0:
			var n = stack.pop_back()
			if n is StormSystem:
				return n
			for c in n.get_children():
				stack.append(c)
		return null


## A kelp planter: press a kelp bundle into the mush and it grows another over a day
## or so. Slow, small, and entirely optional — which is the point. It is the first
## thing on this rig that is alive because you decided it should be.
class Planter extends Interactable:
	const GROW_HOURS: float = 20.0
	const SEED_ID: String = "kelp_bundle"

	var planted: bool = false
	var grown_h: float = 0.0
	var _hour_per_sec: float = 0.0
	var _blades: Array[Node3D] = []

	func _init() -> void:
		display_name = "Kelp Planter"
		verbs = ["PLANT"] as Array[String]

	func _ready() -> void:
		var day_sec: float = 0.0
		for phase in GameClock.phase_durations_minutes:
			day_sec += GameClock.phase_durations_minutes[phase] * 60.0
		_hour_per_sec = 24.0 / maxf(day_sec, 1.0)
		var tray: Node = get_parent()
		if tray and tray.get_parent():
			_collect_blades(tray.get_parent())
		_show_growth()

	func _collect_blades(root: Node) -> void:
		var stack: Array = [root]
		while stack.size() > 0:
			var n = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if n is Node3D and String(n.name).to_lower().contains("blade"):
				_blades.append(n as Node3D)

	func available_verbs() -> Array[String]:
		if not planted:
			return (["PLANT"] as Array[String]) if PlayerState.has_item(SEED_ID) else ([] as Array[String])
		if grown_h >= GROW_HOURS:
			return ["HARVEST"] as Array[String]
		return [] as Array[String]

	func get_prompt() -> String:
		if not planted:
			if not PlayerState.has_item(SEED_ID):
				return ""
			return "PLANT  Kelp Planter (kelp bundle)"
		if grown_h >= GROW_HOURS:
			return "HARVEST  Kelp Planter"
		return ""

	func interact(verb: String, player: Node3D) -> void:
		super.interact(verb, player)
		var hud: Node = get_tree().get_first_node_in_group("hud")
		match verb:
			"PLANT":
				if not PlayerState.has_item(SEED_ID):
					return
				PlayerState.remove_item(SEED_ID)
				planted = true
				grown_h = 0.0
				_show_growth()
				AudioDirector.play_one_shot("hiss", global_position, -22.0)
				if hud:
					hud.toast("You press the kelp into the mush. It'll take a day or so. You'll be here.")
			"HARVEST":
				if grown_h < GROW_HOURS:
					return
				if not PlayerState.add_item(SEED_ID):
					if hud:
						hud.toast("Hands full — the kelp keeps growing.")
					return
				# Harvesting leaves the holdfast: it regrows without another seed.
				grown_h = 0.0
				_show_growth()
				AudioDirector.play_one_shot("hiss", global_position, -20.0)
				if hud:
					hud.toast("You cut the kelp back to the holdfast. It will come again.")

	## The blades stand up as it grows — the only progress bar this game gets.
	func _show_growth() -> void:
		var f: float = 0.12
		if planted:
			f = lerpf(0.12, 1.0, clampf(grown_h / GROW_HOURS, 0.0, 1.0))
		for b in _blades:
			if is_instance_valid(b):
				b.scale = Vector3(1.0, f, 1.0)

	func _process(delta: float) -> void:
		if not planted or grown_h >= GROW_HOURS:
			return
		grown_h += delta * GameClock.time_scale * _hour_per_sec
		_show_growth()
