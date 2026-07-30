extends Node
## Headless acceptance probe for the deep-drop rig's bait rework (owner spec 2026-07-27):
## explicit [B]-to-bait, size/scrap-based eligibility, no snail mention in the abort text,
## and bait only spent when a fish actually takes it (not on cast, not on an empty reel-in).
##
## Run: godot --headless --path . res://tests/BaitProbe.tscn

const FISHING_ROD := preload("res://scripts/components/fishing_rod.gd")

var failures: int = 0

func _ready() -> void:
	await _run()
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  " + label)
	else:
		failures += 1
		print("FAIL  " + label)

func _run() -> void:
	var main: Node3D = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node3D = main.player

	# Clear the pack of anything that would qualify as bait, so the probe controls exactly
	# what's available at each step.
	for id in ["snail_live", "fish_rotten", "crab_leg", "fish_herring", "raw_fillet"]:
		while PlayerState.remove_item(id):
			pass
	FISHING_ROD._baited_id = ""

	# Select the deep rig.
	var slot: int = PlayerState.hotbar.find(null)
	if slot == -1:
		slot = 0
	PlayerState.hotbar[slot] = "deep_rig_pole"
	PlayerState.selected_hotbar = slot

	_check(FISHING_ROD.deep_rig_idle(player), "deep_rig_idle() true while the rig is wielded and idle")
	_check(FISHING_ROD.bait_prompt_text(player).contains("Nothing to bait"),
		"empty pack: bait chip says there's nothing to bait with")
	_check(not FISHING_ROD.try_bait_now(player), "[B] with no bait in the pack does not arm the hook")

	# Rule #1: any fish under 2m qualifies as bait — herring (0.5m, item_visual.gd FISH_SIZE).
	PlayerState.add_item("fish_herring")
	var prompt: String = FISHING_ROD.bait_prompt_text(player)
	_check(prompt.contains("[B]") and not prompt.to_lower().contains("snail"),
		"a small fish in the pack offers to bait, with no snail mention in the prompt (got: %s)" % prompt)
	_check(FISHING_ROD.try_bait_now(player), "[B] arms the hook from the small fish")
	_check(FISHING_ROD.bait_prompt_text(player).begins_with("Hook baited"),
		"once armed, the chip reads 'Hook baited' instead of asking for [B] again")
	var herring_count_after_bait: int = PlayerState.count_item("fish_herring")
	_check(herring_count_after_bait == 1,
		"arming the hook does NOT remove the item from the pack yet (still in inventory)")

	# Casting with the hook already baited should succeed (no abort).
	var rod: Node3D = preload("res://scripts/components/fishing_rod.gd").new()
	main.add_child(rod)
	rod.setup(player, player.camera)
	_check(rod._abort_msg == "", "casting a baited deep rig does not abort")
	_check(rod._bait_id == "fish_herring", "the rod's cast picked up the armed bait")
	_check(FISHING_ROD._baited_id == "", "arming state is consumed into the live cast")
	# Splash it manually (skip flight) and confirm bait is NOT yet removed from the pack.
	rod._state = rod.State.SINK
	rod._depth = 40.0
	_check(PlayerState.count_item("fish_herring") == 1,
		"bait is still in the pack right after the splash (not spent on cast)")

	# Reel up with no bite at all: bait must still be there afterwards (owner correction).
	rod._finish("")
	_check(PlayerState.count_item("fish_herring") == 1,
		"reeling in with no bite leaves the bait item in the pack")

	# Now: a real bite actually spends the bait. Re-bait and re-cast.
	FISHING_ROD._baited_id = "fish_herring"
	var rod2: Node3D = preload("res://scripts/components/fishing_rod.gd").new()
	main.add_child(rod2)
	rod2.setup(player, player.camera)
	_check(rod2._abort_msg == "", "second cast with the re-armed hook does not abort")
	rod2._state = rod2.State.SINK
	rod2._depth = 40.0
	rod2._nibbles = 0
	rod2._bite_timer = 0.0
	rod2._physics_process(0.016)
	_check(rod2._state == rod2.State.BITE, "a real bite fires from SINK once the timer runs out")
	_check(PlayerState.count_item("fish_herring") == 0,
		"the bait is gone from the pack the instant something actually takes it")
	rod2._finish("")

	# Casting unbaited: abort message names [B], not a snail.
	FISHING_ROD._baited_id = ""
	var rod3: Node3D = preload("res://scripts/components/fishing_rod.gd").new()
	main.add_child(rod3)
	rod3.setup(player, player.camera)
	_check(rod3._abort_msg.contains("[B]") and not rod3._abort_msg.to_lower().contains("snail"),
		"casting an unbaited hook refuses and points at [B], with no snail mention (got: %s)" % rod3._abort_msg)

	# A food scrap that is clearly not flesh must not qualify; one that is flesh must.
	_check(not FISHING_ROD._is_bait_item("canned_peaches"), "canned peaches are not legal bait")
	_check(not FISHING_ROD._is_bait_item("chocolate_cake"), "a birthday cake is not legal bait")
	_check(FISHING_ROD._is_bait_item("raw_fillet"), "a raw fillet (flesh scrap) is legal bait")
	_check(FISHING_ROD._is_bait_item("crab_leg"), "a crab leg is still legal bait (named special)")
	_check(not FISHING_ROD._is_bait_item("fish_fathom_sturgeon"),
		"the fathom sturgeon (2.0m, item_visual.gd FISH_SIZE) is too big to be legal bait")
