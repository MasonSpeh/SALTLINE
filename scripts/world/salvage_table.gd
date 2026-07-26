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
## already Takeables via FOOD_MAP), potted living plants, HAND TOOLS (a crowbar or a
## pipe wrench is something you want to pick up, not shear in half), the galley
## barrel_stove (rig_builder makes that one the cooking station), and anything a player
## would rather rearrange than destroy — the galley chairs stay draggable, because
## pulling a chair somewhere you like IS the game. Salvage is for dead equipment.

## The item-effects domain (heal / cures / returns — see item_effects.gd) owns no
## autoload entry and must not edit player_state.gd, so it mounts itself off the first
## data table the world touches. interior_props asks THIS table about every prop it
## streams in, every session, which makes has_def() the earliest guaranteed hook there
## is; ensure() is one static bool test once the node is up.
const ITEM_EFFECTS := preload("res://scripts/components/item_effects.gd")

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
	# Thin tinplate — oil tins, cleaner tins, the rusted cans in every corner. Bare
	# hands, fast, and between them the single biggest source of raw scrap on the rig:
	# the early game needed somewhere to GET scrap_metal that wasn't the gyre.
	"tinware": {
		"tools": [], "speed": ["hammer_tool"], "verb": "CRUSH", "work": 1.4, "sound": "clang",
		"hint": "",
		"start": "You put a boot on the seam.",
		"done": "It folds flat and the seam lets go.",
	},
	# Flasks, jugs, lidded tubs. You are not breaking these up — you are picking them up
	# with what is still in them.
	#
	# Owner call, 2026-07-25b: this used to be verb EMPTY, and it POURED THE WATER OUT —
	# on a rig where thirst is the fastest-draining stat, the only thing you could do with
	# a full crew flask was tip it over the side and keep the tin. That is backwards. TAKE
	# now hands you the FULL vessel: one drink (items.json bottle_water / thermos_water),
	# and because those carry `returns`, the empty comes back to your pack afterwards for
	# the Rain Catcher to refill. Found water is the opening of the water loop, not a
	# thing you throw away to enter it.
	"vessel": {
		"tools": [], "verb": "TAKE", "work": 1.2, "sound": "hiss",
		"hint": "",
		"start": "",
		"done": "Still got most of a shift's water in it. That comes with you.",
	},
	# First-aid stock. Sealed, dry, and the only thing on this rig that was ever meant
	# to help you.
	"medical": {
		"tools": [], "verb": "OPEN", "work": 1.6, "sound": "hiss",
		"hint": "",
		"start": "",
		"done": "Still sealed, still dry. Somebody kept this properly.",
	},
}

## prop_id -> [category, yields] (+ optional display name override).
## Instance counts follow the dressing pass in interior_props.gd, so one line here
## can be worth four salvage points across four decks.
const PROPS := {
	# ---- electrical: screwdriver -> wire, copper, the odd lens ----
	"power_box_01": ["electrical", {"wire_spool": 1, "copper_coil": 1, "bolt_handful": 1}, "Power Distribution Box"],
	"television_02": ["electrical", {"wire_spool": 1, "glass_pane": 1, "copper_coil": 1}],
	"vintage_radio_transceiver": ["electrical", {"wire_spool": 1, "copper_coil": 1}, "Radio Transceiver"],
	"boombox": ["electrical", {"copper_coil": 1, "wire_spool": 1}],
	"portable_generator": ["electrical", {"copper_coil": 1, "rubber_hose": 1, "wire_spool": 1}],
	"cassette_player": ["electrical", {"copper_coil": 1, "wire_spool": 1}, "Cassette Player"],
	# A kettle is a copper element wrapped around the one part worth keeping: something
	# that already holds water without leaking.
	"vintage_electric_kettle": ["electrical", {"copper_coil": 1, "bottle_empty": 1}, "Electric Kettle"],
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
	"portable_welding_cart": ["plumbing", {"rubber_hose": 1, "copper_coil": 1, "steel_plate": 1}, "Welding Cart"],
	"hand_truck": ["plumbing", {"pipe_length": 1, "rubber_hose": 1}, "Hand Truck"],
	"bench_vice_01": ["plumbing", {"steel_plate": 1, "bolt_handful": 1}, "Bench Vice"],
	"watering_can_metal_01": ["plumbing", {"steel_plate": 1, "bottle_empty": 1}, "Watering Can"],
	"modular_industrial_pipes_01": ["plumbing", {"pipe_length": 2}, "Pipe Run"],

	# ---- steel: hacksaw -> plate, bolts ----
	# (metal_tool_chest / drawer_cabinet / metal_toolbox / metal_trash_can are NOT here:
	# anything with a lid, doors or drawers is player STORAGE now — world_storage.gd
	# adopts them as stashes, and a prop can't be both a stash and a salvage station.)
	"tool_cart": ["steel", {"steel_plate": 1, "bolt_handful": 2}, "Tool Cart"],
	"metal_office_desk": ["steel", {"steel_plate": 2, "bolt_handful": 1}, "Office Desk"],
	"steel_frame_shelves_01": ["steel", {"steel_plate": 2, "bolt_handful": 1}, "Steel Shelving"],
	"steel_frame_shelves_02": ["steel", {"steel_plate": 2, "bolt_handful": 1}, "Steel Shelving"],
	"worn_metal_rack": ["steel", {"steel_plate": 2, "bolt_handful": 1}, "Metal Rack"],
	"Shelf_01": ["steel", {"steel_plate": 1, "bolt_handful": 1}, "Shelf Unit"],
	# A 200-litre drum is two plates of flat stock, not one. The old single-plate yield
	# made the most common large steel object on the rig the worst value on it.
	"Barrel_01": ["steel", {"steel_plate": 2}, "Steel Drum"],
	"Barrel_02": ["steel", {"steel_plate": 2}, "Steel Drum"],
	"barrel_03": ["steel", {"steel_plate": 2}, "Steel Drum"],
	# Cut the top off a jerrycan and you have a plate AND something that carries water.
	"metal_jerrycan": ["steel", {"steel_plate": 1, "bottle_empty": 1}, "Jerrycan"],
	"metal_jerrycan_green": ["steel", {"steel_plate": 1, "bottle_empty": 1}, "Jerrycan"],
	"metal_stool_01": ["steel", {"steel_plate": 1, "bolt_handful": 1}, "Metal Stool"],
	"metal_stool_02": ["steel", {"steel_plate": 1, "bolt_handful": 1}, "Metal Stool"],
	"industrial_storage_cart": ["steel", {"steel_plate": 2, "bolt_handful": 1}, "Storage Cart"],

	# ---- timber: prybar or hammer -> driftwood, bolts ----
	"small_wooden_table_01": ["timber", {"driftwood": 1, "bolt_handful": 1}, "Wooden Table"],
	"painted_wooden_chair_01": ["timber", {"driftwood": 1}, "Painted Chair"],
	"folding_wooden_stool": ["timber", {"driftwood": 1}, "Folding Stool"],
	"chinese_stool": ["timber", {"driftwood": 1}, "Wooden Stool"],
	"bar_chair_round_01": ["timber", {"driftwood": 1, "bolt_handful": 1}, "Bar Stool"],
	"wooden_bucket_01": ["timber", {"driftwood": 1}, "Wooden Bucket"],
	# Galley woodware: too small for a plank, exactly right for slats.
	"wooden_bowl_01": ["timber", {"wood_slat": 1}, "Wooden Bowl"],
	"wooden_bowl_02": ["timber", {"wood_slat": 1}, "Wooden Bowl"],
	"carved_wooden_plate": ["timber", {"wood_slat": 1}, "Wooden Plate"],
	"wooden_cutting_board": ["timber", {"wood_slat": 1}, "Cutting Board"],
	"wooden_candlestick": ["timber", {"wood_slat": 1}, "Candlestick"],

	# ---- soft: bare hands (a knife is faster) -> foam, canvas, fibre ----
	"Sofa_01": ["soft", {"foam_block": 2, "canvas_scrap": 2}, "Sofa"],
	"ArmChair_01": ["soft", {"foam_block": 1, "canvas_scrap": 2}, "Armchair"],
	"Ottoman_01": ["soft", {"foam_block": 1, "canvas_scrap": 1}, "Ottoman"],
	"throw_pillows_01": ["soft", {"foam_block": 1}, "Cushions"],
	"life_jacket": ["soft", {"foam_block": 1, "canvas_scrap": 1}, "Life Jacket"],
	# "Nobody is coming. Cut the ring." — the foam_block recipe's own hint, made literal.
	"lifebuoy": ["soft", {"foam_block": 2}, "Lifebuoy"],
	"old_gas_mask": ["soft", {"rubber_hose": 1, "canvas_scrap": 1}, "Gas Mask"],
	"garden_gloves_01": ["soft", {"canvas_scrap": 1}, "Work Gloves"],
	"fishermans_hat": ["soft", {"canvas_scrap": 1}, "Oilskin Hat"],
	# A woven basket unravels into exactly what it was woven from.
	"wicker_basket_01": ["soft", {"kelp_fiber": 2}, "Wicker Basket"],
	"wicker_basket_02": ["soft", {"kelp_fiber": 2}, "Wicker Basket"],
	"plunger": ["soft", {"rubber_hose": 1, "driftwood": 1}, "Plunger"],

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
	"brass_candleholders": ["ceramic", {"ceramic_shard": 1}, "Candleholders"],

	# ---- tinware: bare hands (a hammer is faster) -> raw scrap ----
	# Twenty-odd of these are scattered across the decks. They are the reason the early
	# game no longer has to wait on the gyre for its first piece of scrap metal.
	"oil_tin": ["tinware", {"scrap_metal": 1}, "Oil Tin"],
	"small_oil_can_01": ["tinware", {"scrap_metal": 1}, "Oil Can"],
	"cleaner_tin_01": ["tinware", {"scrap_metal": 1}, "Cleaner Tin"],
	"can_rusted": ["tinware", {"scrap_metal": 1}, "Rusted Can"],

	# ---- vessel: bare hands -> something that holds water ----
	# Thirteen crew flasks and tubs sit on the desks and benches of this rig, every one
	# of them still holding somebody's last shift. Tip it out, keep the flask.
	"modified_thermos": ["vessel", {"thermos_empty": 1}, "Crew Thermos"],
	"plastic_thermos": ["vessel", {"thermos_empty": 1}, "Crew Flask"],
	"plastic_container": ["vessel", {"bottle_empty": 1}, "Lidded Container"],
	"metal_jug": ["vessel", {"bottle_empty": 1}, "Metal Jug"],

	# ---- medical: bare hands -> dressings and kits ----
	"medical_tape": ["medical", {"bandage": 2}, "Roll of Medical Tape"],
	# The asset is in the library and the table is keyed by PropLib id, so this lights up
	# the moment a dressing pass puts a first-aid box in the sick bay. The medkit is
	# CRAFTABLE today (recipes.json) — this is the found one.
	"medical_box": ["medical", {"medkit": 1, "bandage": 1}, "First-Aid Box"],
}

static func has_def(prop_id: String) -> bool:
	ITEM_EFFECTS.ensure()   # belt-and-braces only: main.gd is what actually mounts it
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
