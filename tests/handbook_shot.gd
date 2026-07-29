extends Node
## The Fisherman's Handbook, photographed through its whole life as an object: standing on
## the wet deck where a rigger left it, sitting in the pack as an item with real geometry,
## set down somewhere else entirely, and open with its text on screen.
##
## Run WINDOWED with --always-on-top — this captures the MAIN viewport (the real game
## camera, the real HUD), and an occluded window presents nothing and saves a black frame.
##
##   godot --path . --resolution 1280x720 --always-on-top res://tests/HandbookShot.tscn -- <out_dir>
##
## TWO THINGS THIS HARNESS HAS TO FIGHT, both learned the hard way:
##
##   THE PAUSE MENU. PauseMenu._notification opens itself on WINDOW_FOCUS_OUT — which is
##   correct for a player and fatal for a screenshot, because any other window stealing
##   focus (another probe's Godot instance, say) puts a grey PAUSED panel over the middle
##   of every frame. _unpause() is called immediately before every capture.
##
##   EYE HEIGHT. The player's camera sits 1.6 m above its global_position (Player.tscn), so
##   a naive "stand here, look there" aims a metre and a half high and photographs the wall
##   above the subject. _look_from() takes a FEET position and aims from the eye.

const HANDBOOK := preload("res://scripts/components/handbook.gd")
const EYE_H: float = 1.6

## Where the book is, and where to stand to see it. Both camera spots are chosen INSIDE the
## space the book is in — the wet-deck copy sits in the store room (x 10..16, z -22..-16),
## and a spot north of z -16 is outside it looking at its outer wall.
const WET_DECK_SPOT := Vector3(11.7, 2.62, -16.6)
const WET_DECK_FEET := Vector3(12.5, 2.0, -18.4)
## Up on the topside plate by the rail — an entirely different part of the rig, which is
## the whole point of the "place it anywhere" shot.
const ELSEWHERE_SPOT := Vector3(-5.0, 18.06, 12.5)
const ELSEWHERE_FEET := Vector3(-3.6, 18.0, 13.8)

var main: Node3D
var out_dir: String = "/tmp"

func _ready() -> void:
	# Our own timers must keep ticking even if the game pauses under us.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	# The world streams its dressing in over many seconds and the intro holds a black fade
	# over everything; wait it out, then clear both by hand.
	await get_tree().create_timer(26.0).timeout
	main._countdown = 0.0
	main.hud.fade_rect.color.a = 0.0
	# Broad daylight and the floodlights up, so the wet deck is actually legible. Both are
	# ordinary game states a player can be in, not a photographic cheat.
	GameClock.force_phase(GameClock.Phase.DAY)
	PowerGrid.power_circuit("topside_floodlights")
	var player: Node3D = main.player
	if not player._fly:
		player._toggle_fly()
	player.set_collision_layer_value(1, false)
	player.set_collision_mask_value(1, false)

	# ------------------------------------------------------------------ 1. on the wet deck
	_look_from(player, WET_DECK_FEET, WET_DECK_SPOT)
	await get_tree().create_timer(1.5).timeout
	await _snap("1_wet_deck")

	# ------------------------------------------------------------------ 2. in the pack
	# Take it the way a player does: read it, then [F].
	var book: Node = _find_handbook()
	if book != null:
		(book as Interactable).interact("READ", player)
		HANDBOOK.f_pressed(player)
	else:
		print("[handbook] WARNING: no handbook found on the wet deck")
		PlayerState.add_item(HANDBOOK.ITEM_ID)
	# A little else in the pack so the handbook's slot reads in context rather than alone.
	for id in ["fishing_rod", "deep_rig_pole", "crab_leg", "snail_live", "glow_worm"]:
		PlayerState.add_item(id)
	PlayerState.inventory_changed.emit()
	main.hud.toggle_panel("inventory")
	# Icons bake one item per frame.
	await get_tree().create_timer(5.0).timeout
	var slot: int = _unified_slot(HANDBOOK.ITEM_ID)
	if slot >= 0:
		main.hud._inv_slot_hovered(slot)   # its name/description card in the same frame
	await _snap("2_in_the_pack")
	main.hud.toggle_panel("inventory")
	await get_tree().process_frame

	# ------------------------------------------------------------------ 3. set down elsewhere
	SaveManager.drop_into_world(HANDBOOK.ITEM_ID, ELSEWHERE_SPOT)
	PlayerState.remove_item(HANDBOOK.ITEM_ID)
	_look_from(player, ELSEWHERE_FEET, ELSEWHERE_SPOT)
	await get_tree().create_timer(1.5).timeout   # let the set-down toss finish
	await _snap("3_placed_elsewhere")

	# ------------------------------------------------------------------ 4. open and readable
	var placed: Node = _find_handbook()
	if placed == null:
		print("[handbook] WARNING: nothing to read at the placed spot")
	else:
		(placed as Interactable).interact("READ", player)
	await get_tree().create_timer(0.8).timeout
	await _snap("4_open_page_1")
	# Further down the book: the condition cheat-sheet and the species tables, so the shots
	# prove the whole thing is reachable and not just its first screen.
	var bar: VScrollBar = main.hud.reading_body.get_v_scroll_bar()
	bar.value = bar.max_value * 0.16
	await get_tree().create_timer(0.5).timeout
	await _snap("5_open_conditions")
	bar.value = bar.max_value * 0.62
	await get_tree().create_timer(0.5).timeout
	await _snap("6_open_deep_ladder")
	print("[handbook] done -> %s" % out_dir)
	get_tree().quit()

## Stand the player with their FEET at `feet`, looking at `target` from eye height.
func _look_from(player: Node3D, feet: Vector3, target: Vector3) -> void:
	player.global_position = feet
	player.velocity = Vector3.ZERO
	var to: Vector3 = target - (feet + Vector3(0, EYE_H, 0))
	player.rotation.y = atan2(-to.x, -to.z)
	player.head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())

## PauseMenu opens itself whenever the window loses focus, which puts a PAUSED panel over
## the middle of the frame. Shut it and unpause, every time, right before the shutter.
func _unpause() -> void:
	get_tree().paused = false
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is PauseMenu and is_instance_valid(n.panel):
			n.panel.visible = false

func _snap(name_: String) -> void:
	_unpause()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/handbook_%s.png" % [out_dir, name_]
	print("[handbook] %s err=%d" % [path, img.save_png(path)])

func _find_handbook() -> Node:
	# From the tree root, not from `main`: a dropped item is parented to current_scene,
	# which in this harness is the probe node and not the game scene under it.
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Readable and String(n.get("readable_id")) == HANDBOOK.READABLE_ID:
			return n
	return null

## Index into the HUD's unified hotbar+pack grid, which is what _inv_slot_hovered expects.
func _unified_slot(item_id: String) -> int:
	var i: int = PlayerState.hotbar.find(item_id)
	if i >= 0:
		return i
	var j: int = PlayerState.inventory.find(item_id)
	return -1 if j < 0 else PlayerState.HOTBAR_SIZE + j
