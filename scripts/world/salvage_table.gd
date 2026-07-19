class_name SalvageTable extends RefCounted
## What every dead thing on this rig is worth, and what it takes to open it.
##
## Keyed by PropLib model id, so a rule written once covers every instance of that
## prop wherever the dressing pass put it — all four multimeters, both toolboxes,
## every barrel. interior_props.gd consults this while streaming props in: an id
## with an entry here becomes a Salvage station instead of a grabbable MovableProp.
##
## Deliberately NOT listed: personal keepsakes (spectacles, lighters, postcards,
## cameras, letters, the bunk-head photographs), food and drink props (those are
## already Takeables via FOOD_MAP), potted living plants, and anything a player
## would rather rearrange than destroy — the galley chairs stay draggable, because
## pulling a chair somewhere you like IS the game. Salvage is for dead equipment.

## Category defaults. Per-prop entries supply only the yields (and occasionally a
## name), so the tool gate and the prose stay consistent across the whole rig.
const CATS := {
	"electrical": {
		"tools": ["screwdriver"], "verb": "STRIP", "work": 3.2, "sound": "clang",
		"hint": "the case is screwed shut. A screwdriver would open it.",
		"start": "You back the first screw out.",
		"done": "The case comes off and the guts come out.",
	},
	"plumbing": {
		"tools": ["wrench", "spanner"], "verb": "UNBOLT", "work": 3.6, "sound": "clang",
		"hint": "the unions are seized. A wrench would break them.",
		"start": "You lean on the union until it gives.",
		"done": "It comes apart at the joints.",
	},
	"steel": {
		"tools": ["hacksaw"], "verb": "CUT", "work": 4.2, "sound": "clang",
		"hint": "it's sheet steel. A hacksaw would open it up.",
		"start": "The blade bites and starts to sing.",
		"done": "You cut it down to flat stock.",
	},
	"timber": {
		"tools": ["prybar", "hammer_tool"], "verb": "PRY", "work": 3.0, "sound": "clang",
		"hint": "the joints are nailed. A prybar or a hammer would open them.",
		"start": "You get the bar under a joint.",
		"done": "The joints let go with a crack.",
	},
	"soft": {
		"tools": [], "speed": ["crude_knife"], "verb": "TEAR", "work": 2.4, "sound": "hiss",
		"hint": "",
		"start": "You get a grip on a seam.",
		"done": "The seam gives and the stuffing comes out.",
	},
	"glass": {
		"tools": [], "speed": ["hammer_tool"], "verb": "BREAK", "work": 1.8, "sound": "clang",
		"risk": 0.03,
		"hint": "",
		"start": "You work a thumb under the edge of the pane.",
		"done": "It comes out of the frame in one piece, mostly.",
	},
	"ceramic": {
		"tools": [], "verb": "BREAK", "work": 1.6, "sound": "clang",
		"risk": 0.02,
		"hint": "",
		"start": "",
		"done": "It goes to pieces in your hands.",
	},
}

## prop_id -> [category, yields] (+ optional display name override).
## Instance counts follow the dressing pass in interior_props.gd, so one line here
## can be worth four salvage points across four decks.
const PROPS := {
	# ---- electrical: screwdriver -> wire, copper, the odd lens ----
	"power_box_01": ["electrical", {"wire_spool": 1, "copper_coil": 1}, "Power Distribution Box"],
	"television_02": ["electrical", {"wire_spool": 1, "glass_pane": 1}],
	"vintage_radio_transceiver": ["electrical", {"wire_spool": 1, "copper_coil": 1}, "Radio Transceiver"],
	"boombox": ["electrical", {"copper_coil": 1, "wire_spool": 1}],
	"portable_generator": ["electrical", {"copper_coil": 1, "rubber_hose": 1}],
	"gaming_console": ["electrical", {"wire_spool": 1}],
	"classic_laptop": ["electrical", {"copper_coil": 1}],
	"retro_multimeter": ["electrical", {"wire_spool": 1}],
	"filmstrip_projector_8mm": ["electrical", {"copper_coil": 1, "glass_pane": 1}, "Film Projector"],
	"desk_lamp_arm_01": ["electrical", {"wire_spool": 1}, "Desk Lamp"],
	"industrial_wall_lamp": ["electrical", {"wire_spool": 1, "glass_pane": 1}, "Wall Lamp"],
	"industrial_pipe_lamp": ["electrical", {"wire_spool": 1}, "Pipe Lamp"],
	"caged_hanging_light": ["electrical", {"wire_spool": 1, "glass_pane": 1}, "Caged Worklight"],
	"portable_searchlight": ["electrical", {"copper_coil": 1, "glass_pane": 1}, "Searchlight"],
	"metal_detector": ["electrical", {"copper_coil": 1, "wire_spool": 1}],
	"Megaphone_01": ["electrical", {"copper_coil": 1}, "Megaphone"],
	"alarm_clock_01": ["electrical", {"copper_coil": 1}, "Alarm Clock"],
	"wall_clock": ["electrical", {"copper_coil": 1, "glass_pane": 1}],
	"mantel_clock_01": ["electrical", {"copper_coil": 1}, "Mantel Clock"],

	# ---- plumbing: wrench or spanner -> pipe, hose ----
	"korean_fire_extinguisher_01": ["plumbing", {"steel_plate": 1, "rubber_hose": 1}, "Fire Extinguisher"],
	"propane_tank": ["plumbing", {"pipe_length": 1, "steel_plate": 1}],
	"small_lpg_tank": ["plumbing", {"pipe_length": 1}, "LPG Bottle"],
	"portable_welding_cart": ["plumbing", {"rubber_hose": 1, "copper_coil": 1}, "Welding Cart"],
	"hand_truck": ["plumbing", {"pipe_length": 1, "rubber_hose": 1}, "Hand Truck"],
	"bench_vice_01": ["plumbing", {"steel_plate": 1, "bolt_handful": 1}, "Bench Vice"],
	"watering_can_metal_01": ["plumbing", {"steel_plate": 1}, "Watering Can"],

	# ---- steel: hacksaw -> plate, bolts ----
	"metal_tool_chest": ["steel", {"steel_plate": 1, "bolt_handful": 1}, "Tool Chest"],
	"drawer_cabinet": ["steel", {"steel_plate": 1, "bolt_handful": 1}, "Drawer Cabinet"],
	"tool_cart": ["steel", {"steel_plate": 1, "bolt_handful": 1}, "Tool Cart"],
	"metal_office_desk": ["steel", {"steel_plate": 1, "bolt_handful": 1}, "Office Desk"],
	"steel_frame_shelves_01": ["steel", {"steel_plate": 1, "bolt_handful": 1}, "Steel Shelving"],
	"steel_frame_shelves_02": ["steel", {"steel_plate": 1, "bolt_handful": 1}, "Steel Shelving"],
	"worn_metal_rack": ["steel", {"steel_plate": 1, "bolt_handful": 1}, "Metal Rack"],
	"Shelf_01": ["steel", {"steel_plate": 1, "bolt_handful": 1}, "Shelf Unit"],
	"Barrel_01": ["steel", {"steel_plate": 1}, "Steel Drum"],
	"Barrel_02": ["steel", {"steel_plate": 1}, "Steel Drum"],
	"barrel_03": ["steel", {"steel_plate": 1}, "Steel Drum"],
	"metal_trash_can": ["steel", {"steel_plate": 1}, "Trash Can"],
	"metal_jerrycan": ["steel", {"steel_plate": 1}, "Jerrycan"],
	"metal_jerrycan_green": ["steel", {"steel_plate": 1}, "Jerrycan"],
	"metal_toolbox": ["steel", {"steel_plate": 1, "bolt_handful": 1}, "Toolbox"],
	"metal_stool_01": ["steel", {"steel_plate": 1, "bolt_handful": 1}, "Metal Stool"],
	"metal_stool_02": ["steel", {"steel_plate": 1, "bolt_handful": 1}, "Metal Stool"],

	# ---- timber: prybar or hammer -> driftwood, bolts ----
	"small_wooden_table_01": ["timber", {"driftwood": 1, "bolt_handful": 1}, "Wooden Table"],
	"painted_wooden_chair_01": ["timber", {"driftwood": 1}, "Painted Chair"],
	"folding_wooden_stool": ["timber", {"driftwood": 1}, "Folding Stool"],
	"ClassicNightstand_01": ["timber", {"driftwood": 1, "bolt_handful": 1}, "Nightstand"],
	"chinese_stool": ["timber", {"driftwood": 1}, "Wooden Stool"],
	"bar_chair_round_01": ["timber", {"driftwood": 1, "bolt_handful": 1}, "Bar Stool"],
	"wooden_bucket_01": ["timber", {"driftwood": 1}, "Wooden Bucket"],

	# ---- soft: bare hands (a knife is faster) -> foam, canvas ----
	"Sofa_01": ["soft", {"foam_block": 1, "canvas_scrap": 1}, "Sofa"],
	"ArmChair_01": ["soft", {"foam_block": 1, "canvas_scrap": 1}, "Armchair"],
	"Ottoman_01": ["soft", {"foam_block": 1}, "Ottoman"],
	"throw_pillows_01": ["soft", {"foam_block": 1}, "Cushions"],
	"life_jacket": ["soft", {"foam_block": 1, "canvas_scrap": 1}, "Life Jacket"],

	# ---- glass: bare hands, and it will cost you a little ----
	"fancy_picture_frame_01": ["glass", {"glass_pane": 1}, "Framed Picture"],
	"fancy_picture_frame_02": ["glass", {"glass_pane": 1}, "Framed Picture"],
	"standing_picture_frame_01": ["glass", {"glass_pane": 1}, "Standing Frame"],
	"magnifying_glass_01": ["glass", {"glass_pane": 1}, "Magnifying Glass"],

	# ---- ceramic / brassware: bare hands ----
	"pot_enamel_01": ["ceramic", {"ceramic_shard": 1}, "Enamel Pot"],
	"jug_01": ["ceramic", {"ceramic_shard": 1}, "Stone Jug"],
	"ceramic_vase_01": ["ceramic", {"ceramic_shard": 1}, "Ceramic Vase"],
	"ceramic_vase_02": ["ceramic", {"ceramic_shard": 1}, "Ceramic Vase"],
	"brass_vase_01": ["ceramic", {"ceramic_shard": 1}, "Brass Vase"],
	"brass_vase_02": ["ceramic", {"ceramic_shard": 1}, "Brass Vase"],
	"tea_set_01": ["ceramic", {"ceramic_shard": 1}, "Tea Set"],
	"brass_pot_01": ["ceramic", {"ceramic_shard": 1}, "Brass Pot"],
	"brass_pan_01": ["ceramic", {"ceramic_shard": 1}, "Brass Pan"],
}

static func has_def(prop_id: String) -> bool:
	return PROPS.has(prop_id)

## Category defaults merged with the prop's own yields — the dictionary Salvage
## ._configure() expects. Empty if the prop isn't salvageable.
static func def(prop_id: String) -> Dictionary:
	if not PROPS.has(prop_id):
		return {}
	var row: Array = PROPS[prop_id]
	var out: Dictionary = (CATS[String(row[0])] as Dictionary).duplicate(true)
	out["yields"] = row[1]
	if row.size() > 2:
		out["name"] = row[2]
	# Bare-hands categories have no tool to name, so build the hint from the prop.
	if String(out.get("hint", "")) == "":
		out["hint"] = "you could pull it apart with your hands."
	return out
