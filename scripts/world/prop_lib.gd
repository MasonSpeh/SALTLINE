class_name PropLib extends RefCounted
## Loader for the CC0 glTF prop library in res://assets/models (Poly Haven, all
## CC0 — see assets/models/LICENSES.md). Call PropLib.spawn("metal_toolbox", ...)
## to get an instanced, scaled, optionally-collidable prop. Scenes are cached and
## duplicated per spawn. Missing models fall back to a labelled crate so a bad id
## never breaks a room.

const ROOT := "res://assets/models/"

static var _cache: Dictionary = {}     # id -> PackedScene (or null if absent)

## Real-world longest-axis size (m) per prop, so we can normalize wildly varying
## source scales to something that reads right on the deck. Tuned by eye.
const SIZE_HINT := {
	"Barrel_01": 0.9, "Barrel_02": 0.9, "barrel_03": 0.9, "barrel_stove": 1.0,
	"wooden_crate_01": 0.7, "wooden_crate_02": 0.7, "wooden_military_crate": 1.1,
	"old_military_crate": 0.9, "plastic_crate_01": 0.6, "plastic_crate_02": 0.5,
	"ammo_box": 0.5, "medical_box": 0.4, "utility_box_01": 0.4, "utility_box_02": 0.4,
	"metal_jerrycan": 0.5, "metal_jerrycan_green": 0.5, "plastic_jerrycan": 0.5,
	"propane_tank": 0.9, "small_lpg_tank": 0.7, "propane_torch": 0.5,
	"oil_tin": 0.3, "small_oil_can_01": 0.2, "cleaner_tin_01": 0.25, "can_rusted": 0.15,
	"russian_food_cans_01": 0.12, "long_life_food": 0.3,
	"metal_toolbox": 0.5, "metal_tool_chest": 0.9, "tool_cart": 0.9,
	"industrial_storage_cart": 1.1, "hand_truck": 1.3, "portable_welding_cart": 1.1, "pipe_wrench": 0.4,
	"korean_fire_extinguisher_01": 0.6, "fire_alarm": 0.2, "lifebuoy": 0.75,
	"life_jacket": 0.6, "ocean_buoy": 1.4, "old_gas_mask": 0.3, "WetFloorSign_01": 0.6,
	"wooden_bucket_01": 0.35, "wooden_bucket_02": 0.35, "metal_trash_can": 0.7, "cement_bag": 0.6,
	"Lantern_01": 0.35, "hanging_industrial_lamp": 0.4, "industrial_wall_lamp": 0.35,
	"industrial_pipe_lamp": 0.4, "caged_hanging_light": 0.4, "mounted_fluorescent_lights": 1.2,
	"security_light": 0.35, "vintage_flashlight": 0.25, "portable_searchlight": 0.5,
	"metal_stool_01": 0.6, "metal_stool_02": 0.6, "plastic_monobloc_chair_01": 0.85,
	"folding_wooden_stool": 0.5, "wooden_stool_01": 0.5, "painted_wooden_chair_01": 0.9,
	"metal_office_desk": 1.3, "dining_table": 1.6, "small_wooden_table_01": 0.9,
	"old_bed_frame": 2.0, "vintage_day_bed": 1.9,
	"steel_frame_shelves_01": 1.0, "steel_frame_shelves_02": 1.0, "worn_metal_rack": 1.0,
	"wooden_bookshelf_worn": 1.0, "drawer_cabinet": 0.9,
	"modified_thermos": 0.3, "plastic_thermos": 0.3, "vintage_electric_kettle": 0.3,
	"binder_notebook": 0.3, "office_notepads": 0.25,
	"vintage_radio_transceiver": 0.5, "boombox": 0.5, "retro_multimeter": 0.2,
	"television_02": 0.6, "power_box_01": 0.6, "portable_generator": 0.9,
	"modular_industrial_pipes_01": 2.0, "modular_pipes": 2.0,
	"wooden_ladder": 2.5, "ladder_sectioned_01": 3.0, "old_tyre": 0.7,
	# --- wave 2/3 furniture & decor ---
	"ArmChair_01": 0.95, "Sofa_01": 2.0, "WoodenChair_01": 0.9, "GreenChair_01": 0.9,
	"Ottoman_01": 0.7, "chinese_stool": 0.5, "bar_chair_round_01": 0.9, "dining_chair_02": 0.9,
	"Rockingchair_01": 1.0, "CoffeeTable_01": 1.1, "WoodenTable_01": 1.4, "WoodenTable_02": 1.4,
	"WoodenTable_03": 1.4, "chinese_tea_table": 1.2, "SchoolDesk_01": 1.1, "Shelf_01": 1.0,
	"GothicCabinet_01": 1.8, "ClassicNightstand_01": 0.6, "chinese_cabinet": 1.6,
	"anthurium_botany_01": 0.5, "calathea_orbifolia_01": 0.6, "fern_02": 0.5, "celandine_01": 0.3,
	"ceramic_pot": 0.4, "fir_sapling": 0.9, "brass_pan_01": 0.35, "brass_pot_01": 0.3,
	"brass_pot_02": 0.3, "ceramic_vase_01": 0.35, "ceramic_vase_02": 0.35, "ceramic_vase_03": 0.35,
	"brass_goblets": 0.15, "brass_vase_01": 0.4, "carrot_cake": 0.25, "croissant": 0.15,
	"bananas": 0.2, "food_apple_01": 0.1, "food_avocado_01": 0.12,
	"fancy_picture_frame_01": 0.5, "fancy_picture_frame_02": 0.5, "alarm_clock_01": 0.15,
	"decorative_book_set_01": 0.3, "book_encyclopedia_set_01": 0.35, "chess_set": 0.45,
	"dartboard": 0.5, "adjustable_wrench": 0.3, "bolt_cutters_01": 0.6, "crowbar_01": 0.7,
	"cross_pein_hammer": 0.35, "bench_vice_01": 0.35, "combination_wrench": 0.3,
	"cassette_player": 0.3, "classic_laptop": 0.35, "Camera_01": 0.15, "binoculars": 0.2,
	"bronze_whale_statue": 0.6, "bronze_shark_statue": 0.6, "bronze_ray_statue": 0.5,
	"Chandelier_01": 0.7, "ceiling_fan": 1.0, "clipboard": 0.3, "screwdriver": 0.25, "dustpan": 0.35,
	# --- wave 4: small household / personal / crew clutter (session 8) ---
	"tea_set_01": 0.35, "wooden_bowl_01": 0.2, "wooden_bowl_02": 0.2, "wooden_spoon": 0.3,
	"wooden_cutting_board": 0.4, "carved_wooden_plate": 0.25, "jug_01": 0.25, "metal_jug": 0.25,
	"pot_enamel_01": 0.28, "CheeseBox_01": 0.2, "wine_bottles_01": 0.32, "wicker_basket_01": 0.4,
	"wicker_basket_02": 0.35, "hamburger_buns": 0.12, "strawberry_chocolate_cake": 0.25, "lemon": 0.08,
	"yellow_onion": 0.09, "sweet_potato": 0.15, "food_pomegranate_01": 0.1, "food_ginger_01": 0.12,
	"all_purpose_cleaner": 0.28, "bleach_bottle": 0.3, "multi_cleaner_bottle": 0.28, "drain_cleaner": 0.25,
	"lubricant_spray": 0.2, "spray_paint_bottles": 0.2, "plastic_broom": 1.3, "plunger": 0.45,
	"rubber_duck_toy": 0.09, "plastic_bottle_gallon": 0.32, "plastic_container": 0.3, "watering_can_metal_01": 0.35,
	"cigarette_pack": 0.09, "cigarette_case": 0.1, "vintage_lighter": 0.06, "round_spectacles": 0.14,
	"fishermans_hat": 0.3, "rubber_boots": 0.35, "garden_gloves_01": 0.28, "postcard_set_01": 0.15,
	"magnifying_glass_01": 0.15, "seadogs_compass": 0.08, "stationery_supplies": 0.2, "vintage_stapler": 0.15,
	"gamepad": 0.16, "gaming_console": 0.35, "sungka_board": 0.6, "mousetrap": 0.1,
	"baseball_01": 0.07, "baseball_bat": 0.85, "vintage_video_camera": 0.28, "filmstrip_projector_8mm": 0.3,
	"metal_detector": 1.2, "Megaphone_01": 0.3, "mantel_clock_01": 0.3, "wall_clock": 0.3,
	"desk_lamp_arm_01": 0.5, "vintage_oil_lamp": 0.3, "wooden_candlestick": 0.25, "brass_candleholders": 0.25,
	"brass_vase_02": 0.3, "ceramic_vase_04": 0.3, "antique_ceramic_vase_01": 0.35, "hanging_picture_frame_01": 0.5,
	"standing_picture_frame_01": 0.2, "throw_pillows_01": 0.5, "marble_bust_01": 0.5, "concrete_cat_statue": 0.3,
	"flathead_screwdriver": 0.25, "pliers": 0.2, "measuring_tape_01": 0.08, "medical_tape": 0.07,
}

static func has(id: String) -> bool:
	return ResourceLoader.exists(_path(id))

static func _path(id: String) -> String:
	return "%s%s/%s.gltf" % [ROOT, id, id]

# =============================================================================
#  ITEM MODELS — real meshes for the things the player carries
# =============================================================================
## ItemVisual assembles every inventory item out of boxes, cylinders and tori. That
## reads, but a coil of rope is one torus and a plank of driftwood is one box, and the
## player looks at those two constantly: they come out of the gyre, out of every salvage
## teardown, and into ten recipes each.
##
## Two sources of real geometry feed this table, and item_model() tries them in this
## order:
##
##   1. A GENERATED mesh at res://assets/models/items/<item_id>/<item_id>.glb. Discovered
##      by path — an item needs NO entry here to use one, so a mesh generated in the
##      background lights up the moment it lands and its absence costs nothing.
##   2. A LIBRARY prop from the CC0 pack, via ITEM_MODEL below. ~200 real props already
##      ship in this repo and a good few of them ARE the item: crowbar_01 is the prybar,
##      lifebuoy is the life ring, medical_box is the medkit. Those were free.
##
## Anything with neither keeps ItemVisual's procedural build, so this can only ever add.
const ITEM_ROOT := "res://assets/models/items/"

## item_id -> { id, m, pick, glow }
##   id   — library prop directory under res://assets/models/
##   m    — longest-axis size in metres for the world-dropped item. The pack icon and the
##          held-in-hand visual both re-normalise (ItemIcons frames the AABB;
##          player_controller._normalize_hand_visual rescales to HAND_ITEM_MAX_DIM), so
##          this number only governs the thing lying on the deck.
##   pick — OPTIONAL substring. Several library props are a SET — wine_bottles_01 is four
##          bottles, rubber_boots is a clean pair plus a muddy pair — and an inventory
##          item is one object. Keeping only the sub-meshes whose node name contains this
##          token turns a shop display into a single item. Verified against the glTF node
##          names, not guessed.
##   glow — OPTIONAL substring naming the sub-mesh to light (with glow_color/glow_energy),
##          for a prop whose SHAPE is right but whose light source is wrong for this world.
##
## EVERY entry here was rendered through tests/CandShot.tscn and looked at before it was
## written down. A wrong-looking match is worse than the primitive it replaces, so the
## near-misses were dropped rather than shipped: vintage_oil_lamp is an ornate Victorian
## parlour lamp (Lantern_01 is the actual storm lantern), jug_01 is a floral porcelain
## pitcher, ocean_buoy is a 2.7 m navigation tower and not a float you carry, CheeseBox_01
## is a box and cheese_wedge is a wedge.
const ITEM_MODEL := {
	# ---- hand tools: the library pack is full of exactly these ----
	# The four bench tools take the SAME model rig_builder._takeable_model already lays on
	# the workbench (pipe_wrench / cross_pein_hammer / combination_wrench / screwdriver).
	# That bench spawns the glTF prop directly and bypasses ItemVisual, so before this the
	# pipe wrench you picked up off the bench turned into a grey box in the pack. Changing
	# either list without the other re-opens that seam.
	"prybar": {"id": "crowbar_01", "m": 0.72},
	"wrench": {"id": "pipe_wrench", "m": 0.4},
	"spanner": {"id": "combination_wrench", "m": 0.3},
	"screwdriver": {"id": "screwdriver", "m": 0.24},
	"hammer_tool": {"id": "cross_pein_hammer", "m": 0.34},
	# ---- lights and marine gear ----
	"flashlight": {"id": "vintage_flashlight", "m": 0.26},
	# Lantern_01 is a real hurricane lantern, which is the right SHAPE and the wrong
	# light: nothing on this rig burns oil, the lanterns are bloom cells behind glass.
	# `glow` lights the model's own glass node the same teal every bloom-lit thing here
	# wears, so the swap keeps the silhouette upgrade without dropping the lore cue the
	# procedural build carried. (The actual illumination is the equip code's light node;
	# this only makes the glass read as lit.)
	"storm_lantern": {"id": "Lantern_01", "m": 0.32, "glow": "glass",
		"glow_color": Color(0.2, 0.9, 0.85), "glow_energy": 1.6},
	"life_ring": {"id": "lifebuoy", "m": 0.72},
	# ---- medical ----
	"medkit": {"id": "medical_box", "m": 0.38},
	"bandage": {"id": "medical_tape", "m": 0.08},
	# ---- worn gear. `dirt` keeps the WORN pair: the item is patched boots, and the
	#      clean pair in the same file would read as new stock off a chandler's shelf.
	"patched_boots": {"id": "rubber_boots", "m": 0.34, "pick": "dirt"},
	# ---- galley stores. These were the batch that shipped as "the same anonymous yellow
	#      cube" and got hand-built into silhouettes; the pack already had the real thing.
	"apple": {"id": "food_apple_01", "m": 0.1},
	"avocado": {"id": "food_avocado_01", "m": 0.13},
	"lemon": {"id": "lemon", "m": 0.09},
	"bananas": {"id": "bananas", "m": 0.24},
	"croissant": {"id": "croissant", "m": 0.16},
	"carrot_cake": {"id": "carrot_cake", "m": 0.22},
	"burger_buns": {"id": "hamburger_buns", "m": 0.22},
	"chocolate_cake": {"id": "strawberry_chocolate_cake", "m": 0.24},
	"canned_food": {"id": "russian_food_cans_01", "m": 0.16},
	"long_life_ration": {"id": "long_life_food", "m": 0.24},
	"sealed_tin": {"id": "can_rusted", "m": 0.17},
	# One bottle, not the shelf: `bordeaux` is the dark high-shouldered one.
	"wine_bottle": {"id": "wine_bottles_01", "m": 0.32, "pick": "bordeaux"},
	"water_jug": {"id": "plastic_bottle_gallon", "m": 0.3},
}

## Longest-axis size in metres for GENERATED item meshes (res://assets/models/items/).
## A generated mesh arrives normalised to its own bounding box with no idea how big the
## thing is in the world, so a coil of rope and a metre of pipe would land the same size.
## Anything absent falls back to GEN_DEFAULT_M.
const GEN_DEFAULT_M: float = 0.35
const ITEM_SIZE := {
	# raw materials
	"rope": 0.34, "driftwood": 0.95, "steel_plate": 0.64, "scrap_metal": 0.55,
	"canvas_scrap": 0.42, "tarp": 0.6, "kelp_bundle": 0.5, "kelp_fiber": 0.42,
	"pipe_length": 1.05, "wood_slat": 0.85, "foam_block": 0.36, "glass_pane": 0.55,
	"tar_lump": 0.22, "wire_spool": 0.3, "copper_coil": 0.36, "cable_spool": 0.5,
	"rubber_hose": 0.5, "bolt_handful": 0.2,
	# tools and gear
	"crude_knife": 0.32, "honed_knife": 0.36, "crude_spear": 1.5, "honed_spear": 1.55,
	"hacksaw": 0.45, "hand_file": 0.38, "mini_anchor": 0.42, "throwing_hook": 0.4,
	"flare": 0.32, "float_buoy": 0.34,
	# food
	"cooked_fish": 0.3, "cooked_fish_prime": 0.42, "raw_fillet": 0.32,
	"raw_sea_bird": 0.28, "cooked_sea_bird": 0.28, "water_ration": 0.24,
}

## Path a generated item mesh would live at. Public so a test harness can photograph one
## without duplicating the layout convention.
static func item_gen_path(item_id: String) -> String:
	return "%s%s/%s.glb" % [ITEM_ROOT, item_id, item_id]

## True when this item id has real geometry available — generated or mapped.
static func has_item_model(item_id: String) -> bool:
	if ResourceLoader.exists(item_gen_path(item_id)):
		return true
	var e: Variant = ITEM_MODEL.get(item_id)
	return e is Dictionary and ResourceLoader.exists(_path(str((e as Dictionary)["id"])))

## Build the real mesh for an inventory item, or null when there isn't one.
##
## Returns a node laid out the way ItemVisual's own cases are: X/Z centred on the origin
## and STANDING ON the y = 0 plane, so a Takeable can parent it without the item floating
## or sinking. Callers that want a different size pass target_m.
##
## Null is a first-class answer — it is how a caller keeps its procedural silhouette for
## everything that has no model, which is most of the roster.
static func item_model(item_id: String, target_m: float = -1.0) -> Node3D:
	var gen: String = item_gen_path(item_id)
	if ResourceLoader.exists(gen):
		var m: Node3D = _load_scene(gen)
		if m != null:
			var want_gen: float = target_m if target_m > 0.0 else float(ITEM_SIZE.get(item_id, GEN_DEFAULT_M))
			_fit(m, want_gen)
			return m
	var entry: Variant = ITEM_MODEL.get(item_id)
	if not (entry is Dictionary):
		return null
	var def: Dictionary = entry
	var model: Node3D = _load_scene(_path(str(def["id"])))
	if model == null:
		return null
	if def.has("pick"):
		_pick(model, str(def["pick"]))
	if def.has("glow"):
		_glow(model, str(def["glow"]), def.get("glow_color", Color(0.2, 0.9, 0.85)),
			float(def.get("glow_energy", 1.5)))
	var want: float = target_m if target_m > 0.0 else float(def.get("m", 0.4))
	_fit(model, want)
	return model

## Instance a glTF/GLB by path, or null when it isn't imported yet. A model still
## importing (or one whose .import record went stale) must not take an item's art down
## with it — the caller falls back to primitives.
static func _load_scene(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D

## Drop every mesh whose own name — or any ancestor's — doesn't contain `token`.
## This is what turns a four-bottle library prop into the one bottle the item is. Frees
## the rejects rather than hiding them: an invisible MeshInstance3D still counts toward
## the AABB that the icon camera and the hand normaliser both frame from, so a hidden
## bottle would push the kept one into a corner of its own icon.
static func _pick(root: Node3D, token: String) -> void:
	var doomed: Array = []
	for mi in _all_meshes(root):
		var keep := false
		var n: Node = mi
		while n != null:
			if String(n.name).findn(token) >= 0:
				keep = true
				break
			if n == root:
				break
			n = n.get_parent()
		if not keep:
			doomed.append(mi)
	# Never strip a model to nothing: a token that matches no node is an authoring typo,
	# and an empty node is indistinguishable from "no art" downstream.
	if doomed.size() >= _all_meshes(root).size():
		push_warning("PropLib: pick token '%s' matched no mesh in %s — keeping all." % [token, root.name])
		return
	for d in doomed:
		(d as Node).get_parent().remove_child(d)
		(d as Node).queue_free()

## Light up the sub-meshes whose name contains `token` — a lantern's glass, a lens.
## Works on a SURFACE OVERRIDE off a duplicate of the imported material, so the prop's
## own PBR maps survive and the shared cached material is never mutated: PropLib caches
## PackedScenes and every spawn of the same prop hands out the same Material resource, so
## writing to it in place would set fire to every other lantern in the world.
static func _glow(root: Node3D, token: String, color: Color, energy: float) -> void:
	for n in _all_meshes(root):
		var inst: MeshInstance3D = n
		if String(inst.name).findn(token) < 0 or inst.mesh == null:
			continue
		for s in range(inst.mesh.get_surface_count()):
			var src := inst.mesh.surface_get_material(s) as BaseMaterial3D
			var m: BaseMaterial3D = src.duplicate() if src else StandardMaterial3D.new()
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = energy
			inst.set_surface_override_material(s, m)

## Scale to a real-world size and seat the result: X/Z centred, base on y = 0.
##
## Done on a WRAPPER-free basis — the scale goes on the model root and the offset with
## it — so the node handed back has no surprise nesting. Both numbers come from the
## measured post-scale bounds, so it stays correct for any source model regardless of
## where its author put the origin (library props sit on their base, generated meshes
## come out centred on their own bounding box, and neither has to be special-cased).
static func _fit(model: Node3D, target_m: float) -> void:
	var box: AABB = _aabb(model)
	var longest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest <= 0.0001 or not is_finite(longest):
		return
	var s: float = target_m / longest
	model.scale = Vector3(s, s, s)
	var centre: Vector3 = box.get_center() * s
	model.position = Vector3(-centre.x, -box.position.y * s, -centre.z)

static func _scene(id: String) -> PackedScene:
	if _cache.has(id):
		return _cache[id]
	var p := _path(id)
	var scene: PackedScene = null
	if ResourceLoader.exists(p):
		scene = load(p)
	_cache[id] = scene
	return scene

# Props that stay put no matter what — bolted-down machinery, mounted fixtures,
# heavy shelving. Everything NOT in here is human-moveable by default.
const FIXED := {
	"portable_generator": true, "portable_welding_cart": true, "drawer_cabinet": true,
	"tool_cart": true, "hand_truck": true, "industrial_storage_cart": true,
	"worn_metal_rack": true, "steel_frame_shelves_01": true, "steel_frame_shelves_02": true,
	"Shelf_01": true, "GothicCabinet_01": true, "chinese_cabinet": true, "ceiling_fan": true,
	"Chandelier_01": true, "mounted_fluorescent_lights": true, "caged_hanging_light": true,
	"industrial_wall_lamp": true, "industrial_pipe_lamp": true, "modular_pipes": true,
	"modular_industrial_pipes_01": true, "power_box_01": true, "metal_office_desk": true,
	"vintage_radio_transceiver": true, "SchoolDesk_01": true,
	# Storage furniture stays PUT. Anything world_storage.gd adopts as a stash must be a
	# fixed StaticBody prop — a RigidBody you can carry off can't host a LootContainer
	# (physics-body nesting), and a locker that wanders is a locker whose saved contents
	# key (rounded world position) breaks. Chests, drawer units and bins are bolted down.
	"metal_tool_chest": true, "metal_toolbox": true, "metal_trash_can": true,
	"ClassicNightstand_01": true,
}
# Moveable but too big/heavy to lift — dragged along the floor instead.
const HEAVY := {
	"Sofa_01": true, "old_bed_frame": true, "vintage_day_bed": true, "ArmChair_01": true,
	"dining_table": true, "WoodenTable_01": true, "WoodenTable_02": true, "WoodenTable_03": true,
	"CoffeeTable_01": true, "chinese_tea_table": true, "Barrel_01": true, "Barrel_02": true,
	"barrel_03": true, "barrel_stove": true, "propane_tank": true,
	"television_02": true, "small_lpg_tank": true,
	"wooden_military_crate": true, "old_military_crate": true,
}

static func is_moveable(id: String) -> bool:
	return not FIXED.has(id)

static func _pretty(id: String) -> String:
	var base: String = id
	# Drop a trailing _01 style index, turn underscores into spaces, title-case.
	base = base.trim_suffix("_01").trim_suffix("_02").trim_suffix("_03")
	var words: PackedStringArray = base.replace("_", " ").split(" ", false)
	var out: PackedStringArray = []
	for w in words:
		if w.length() > 0:
			out.append(w[0].to_upper() + w.substr(1))
	return " ".join(out)

## Spawn a prop under `parent` at global `pos`.
##  yaw_deg   — rotation about Y
##  scale_mul — multiply the auto-normalized size (1.0 = size hint)
##  collide   — wrap in a StaticBody3D with an auto AABB box collider
##  target_m  — override the longest-axis size in meters (else SIZE_HINT / 1.0)
##  movable   — wrap in a grab/carry/drag MovableProp instead (overrides collide)
## Returns the spawned root Node3D (a fallback crate if the id is missing).
static func spawn(id: String, parent: Node3D, pos: Vector3, yaw_deg: float = 0.0,
		scale_mul: float = 1.0, collide: bool = false, target_m: float = -1.0,
		movable: bool = false) -> Node3D:
	var scene := _scene(id)
	if scene == null:
		return _fallback(id, parent, pos, yaw_deg)
	var inst: Node3D = scene.instantiate()
	# Normalize source scale to the target real-world size.
	var aabb := _aabb(inst)
	var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var want: float = target_m if target_m > 0.0 else float(SIZE_HINT.get(id, 0.6))
	var s: float = (want / longest) * scale_mul if longest > 0.0001 else scale_mul
	inst.scale = Vector3(s, s, s)
	var holder: Node3D = inst
	if movable:
		var mv := MovableProp.new()
		mv.display_name = _pretty(id)
		mv.heavy = HEAVY.has(id)
		var vol: Vector3 = aabb.size * s
		mv.mass = clampf(vol.x * vol.y * vol.z * 120.0, 0.5, 40.0)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = vol
		shape.shape = box
		shape.position = (aabb.position + aabb.size * 0.5) * s
		mv.add_child(shape)
		mv.add_child(inst)   # model + collider stay local; the body carries the yaw
		holder = mv
	elif collide:
		inst.rotation.y = deg_to_rad(yaw_deg)
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size * s
		shape.shape = box
		shape.position = (aabb.position + aabb.size * 0.5) * s
		body.add_child(shape)
		body.add_child(inst)
		holder = body
	else:
		inst.rotation.y = deg_to_rad(yaw_deg)
	parent.add_child(holder)
	holder.global_position = pos
	if holder is MovableProp:
		holder.rotation.y = deg_to_rad(yaw_deg)   # rotate the body; model + collider follow
	return holder

## Convenience: scatter several ids near a point with slight jitter (deterministic
## by index so saves stay stable — no Math.random in this engine build anyway).
static func clutter(parent: Node3D, center: Vector3, ids: Array, spread: float = 0.5) -> void:
	for i in range(ids.size()):
		var a: float = i * 2.399963   # golden-angle spread
		var off := Vector3(cos(a), 0, sin(a)) * (spread * (0.4 + 0.6 * (float(i) / maxf(1.0, ids.size()))))
		spawn(str(ids[i]), parent, center + off, rad_to_deg(a) * 3.0)

static func _aabb(node: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for mi in _all_meshes(node):
		var mesh_aabb: AABB = mi.get_aabb()
		# Transform into the instance-root space.
		var xf: Transform3D = _relative_xform(node, mi)
		var t_aabb := xf * mesh_aabb
		if first:
			acc = t_aabb
			first = false
		else:
			acc = acc.merge(t_aabb)
	if first:
		return AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 0.6, 0.6))
	return acc

static func _relative_xform(root: Node3D, child: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = child
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

static func _all_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_meshes(c))
	return out

static func _fallback(id: String, parent: Node3D, pos: Vector3, yaw_deg: float) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var sz: float = float(SIZE_HINT.get(id, 0.5))
	bm.size = Vector3(sz, sz * 0.8, sz)
	bm.material = MatLib.weathered_wood()
	mi.mesh = bm
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, sz * 0.4, 0)
	mi.rotation.y = deg_to_rad(yaw_deg)
	return mi
