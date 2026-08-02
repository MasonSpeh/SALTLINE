extends Node
## SUNK PROBE — handleable props that fell THROUGH the world instead of resting on it.
##
## PlacementProbe measures the opposite failure: a prop hanging in the air over its support.
## A prop that dropped through a deck is not floating, it is gone — so that probe reported
## FLOATING: 0 for several sessions while a store-room crate sat at y -0.90, about 3 m under
## the wet deck (KNOWN_ISSUES, found s18). This is the check that would have caught it.
##
## The cause was SurfaceSnap taking its single corrective raycast on the first physics tick,
## before the CSG decks have baked their colliders — so the snap found nothing, gave up
## silently, and a rigid prop then fell through the floor that did not exist yet. Fixed s28
## by retrying until real collision answers and holding rigid parents still while it waits.
##
## Headless is correct: this is physics and transforms, which --headless simulates honestly.
## (It is RENDERING that headless does not do — and MultiMesh instance transforms, which this
## probe does not read.)
##
## Run: godot --headless --path . res://tests/SunkProbe.tscn

## Deck heights: the wet deck is y2.0 and the boat landing runs -3..1, so a handleable prop
## below this is either in the sea or through a deck.
const SUNK_Y: float = -0.5

## ...with ONE legitimate exception. leg_reef seats its harvestable mussel/barnacle colonies
## on the caissons between roughly y -12.7 and -22.0, and those are meant to be dived for —
## they are the reef's food content, not fallen deck dressing. Anything of that kind ABOVE
## the band is still reported, so a salvage node that fell off the deck is not excused.
const REEF_BAND_TOP: float = -8.0

const HANDLEABLE: Array[String] = ["takeable.gd", "loot_container.gd", "phys_prop.gd",
	"movable_prop.gd", "world_storage.gd", "interactable.gd"]

var failures: int = 0
var _completed: bool = false

func _ready() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	# The world takes ~25 s to build (seabed, reef, exterior dressing) and the dressing
	# streams a few props a frame; then physics ticks so SurfaceSnap has resolved and rigid
	# props have come to rest. Same budget PlacementProbe uses, for the same reasons.
	await get_tree().create_timer(30.0).timeout
	for i in range(20):
		await get_tree().physics_frame
	_run(main)
	# A script error inside an awaited coroutine returns here quietly and the report would
	# read "0 sunk" over a run that stopped early — see docs/AGENT_TRAPS.md.
	if not _completed:
		print("FAIL  the probe ran to completion (it did NOT — see the SCRIPT ERROR above)")
		failures += 1
	print("---")
	print("FAILURES: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _run(main: Node) -> void:
	var sunk: Array = []
	var reef: int = 0
	var counted: int = 0
	var stack: Array = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var n3 := n as Node3D
		if n3 == null or not n3.is_inside_tree():
			continue
		var scr: Script = n.get_script()
		if scr == null:
			continue
		var sname: String = String(scr.resource_path).get_file()
		if sname == "salvage.gd":
			# Reef harvestables live in the dive band on purpose; one that has climbed ABOVE
			# it has come loose from the deck and is still a fault.
			if n3.global_position.y <= REEF_BAND_TOP:
				reef += 1
				continue
			sname = "salvage.gd (off-reef)"
		elif not HANDLEABLE.has(sname):
			continue
		counted += 1
		if n3.global_position.y < SUNK_Y:
			sunk.append("%-20s %-22s y=%.2f  at %s"
				% [n.name, sname, n3.global_position.y, str(n3.global_position)])
	print("--- sunk probe ---")
	print("handleable props checked: %d   reef harvestables exempted: %d" % [counted, reef])
	for s in sunk:
		print("  SUNK  %s" % s)
	# ASSERT A PLAUSIBLE POPULATION, not just an empty failure list. A probe that walked a
	# half-built world would otherwise report a confident clean pass over nothing at all.
	_ok(counted >= 40, "found a plausible number of handleable props to check (%d)" % counted)
	_ok(reef >= 20, "found the reef harvestables where they belong (%d in the dive band)" % reef)
	_ok(sunk.is_empty(), "no handleable prop is below y %.1f (%d sunk)" % [SUNK_Y, sunk.size()])
	_completed = true

func _ok(cond: bool, msg: String) -> void:
	print("%s  %s" % ["PASS" if cond else "FAIL", msg])
	if not cond:
		failures += 1
