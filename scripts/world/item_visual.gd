class_name ItemVisual extends RefCounted
## Distinctive greybox meshes per item, so a glance tells you what's on the ground.
## Returns a Node3D you parent to a Takeable (or anything). Shapes echo the gyre-debris
## silhouettes for consistency: cans are cylinders, rope is a coil, planks are planks.

## Species tints for the raw-fish family — one silhouette, per-fish colors.
const FISH_TINT := {
	"fish_herring": Color(0.7, 0.85, 0.85), "fish_slate_cod": Color(0.42, 0.45, 0.5),
	"fish_mirrorjack": Color(0.85, 0.88, 0.92), "fish_chimefish": Color(0.75, 0.8, 0.6),
	"fish_sable_hake": Color(0.25, 0.27, 0.32), "fish_barrel_grouper": Color(0.5, 0.38, 0.3),
	"fish_ribbon_eel": Color(0.4, 0.6, 0.62), "fish_copper_sprat": Color(0.75, 0.5, 0.3),
	"fish_silver_ladder": Color(0.8, 0.84, 0.9), "fish_ember_snapper": Color(0.8, 0.4, 0.25),
	"fish_ghost_sole": Color(0.8, 0.82, 0.88), "fish_glasspike": Color(0.7, 0.8, 0.82),
	"fish_lodestone_bream": Color(0.5, 0.52, 0.6), "fish_drum_croaker": Color(0.55, 0.45, 0.4),
	"fish_miller_flounder": Color(0.55, 0.5, 0.42), "fish_fathom_halibut": Color(0.4, 0.42, 0.45),
	# Deep-drop rig species — the big ones from the dark.
	"fish_gulper_eel": Color(0.28, 0.22, 0.3), "fish_bloom_dragon": Color(0.15, 0.35, 0.4),
	"fish_fathom_sturgeon": Color(0.34, 0.36, 0.32), "fish_abyss_grenadier": Color(0.4, 0.38, 0.34),
	"fish_coelacanth": Color(0.32, 0.34, 0.38),
	"fish_swordfish": Color(0.33, 0.42, 0.52),       # slate-blue back, s24
	# Owner call, 2026-07-27: these two had no glb, no tint and no size, so they came out of
	# build() as the DEFAULT un-tinted grey capsule — the same anonymous shape for a hagfish
	# and for a fish that has gone off. Un-modelled is fine; un-identifiable is not.
	"fish_trench_hagfish": Color(0.34, 0.3, 0.33),   # blind, slate-mauve, ropey
	"fish_rotten": Color(0.46, 0.5, 0.36),           # gone green at the gills
}
## Owner call, 2026-07-25b: every species now has its own entry. Before this, only 8 of
## the ~20 species were listed and everything else silently fell back to the default 1.0
## multiplier in build() below — so a barrel grouper (1.4) and an un-listed ember snapper
## (1.0) differed by only 40%, and most of the roster (herring, slate cod, mirrorjack,
## chimefish, sable hake, ghost sole, glasspike, lodestone bream, drum croaker, miller
## flounder) was fully un-differentiated at the same size. These are a real spread, small
## baitfish up to the huge deep-drop catches — a caught grouper should read as HUGE in the
## hand next to a herring, not a fifth again as big.
const FISH_SIZE := {
	"fish_herring": 0.5, "fish_copper_sprat": 0.45,           # small baitfish schools
	"fish_chimefish": 0.55, "fish_silver_ladder": 0.65,
	"fish_mirrorjack": 0.7, "fish_ghost_sole": 0.6, "fish_miller_flounder": 0.7,
	"fish_lodestone_bream": 0.85,
	"fish_slate_cod": 1.0, "fish_glasspike": 0.9,
	"fish_ember_snapper": 1.3, "fish_drum_croaker": 1.1, "fish_sable_hake": 1.1,
	"fish_ribbon_eel": 1.3,
	"fish_barrel_grouper": 1.8, "fish_fathom_halibut": 1.7,   # the big topside-water catches
	# Deep-drop rig species read heavy in the hand.
	"fish_gulper_eel": 1.6, "fish_bloom_dragon": 1.4,
	"fish_fathom_sturgeon": 2.0, "fish_abyss_grenadier": 1.3,
	"fish_coelacanth": 0.9,                                    # half the grouper
	# s24: the rain fish at 22 m. Authored at 3.0 m of body — the bill is a third of it, and
	# only the sturgeon (3.5) is longer. Its size_kg tops out at 120, which the cube law reads
	# as 2.57 m, so this authored length is the one fish_length_m() keeps (see the max() there).
	"fish_swordfish": 3.0,
	# The 2026-07-26 Meshy batch. Without these the whole new intake defaulted to 1.0 and a
	# bilge blenny weighed the same in the hand as a dogfish — the exact flattening this
	# table was written to stop.
	"fish_bilge_blenny": 0.45, "fish_kelp_pipefish": 0.5,      # bait-grade, a handful each
	"fish_gannet_mackerel": 0.7, "fish_rust_wrasse": 0.8,
	"fish_tallow_pollock": 1.1, "fish_squall_garfish": 1.2,
	"fish_lantern_dogfish": 1.5, "fish_anchor_ray": 1.6,       # both a two-handed lift
	"fish_trench_hagfish": 0.9, "fish_rotten": 0.9,           # see the FISH_TINT note above
}
## Real generated fish meshes (assets/models/fauna/<id>) when present; procedural
## silhouette when not. Preloaded — the class cache lags for this new file.
const FISH_MODEL := preload("res://scripts/world/fish_model_lib.gd")

## HOW BIG A SPECIES REALLY IS, in metres of body length. Used by the pack's fish preview
## (ui/item_icons.gd) to frame a caught fish at its own size instead of a uniform thumbnail.
##
## data/fish.json's schema carries exactly one size field: `size_kg:[min,max]` — "landed
## weight rolled per catch". It is a WEIGHT, not a length, and it is only authored on the
## seven deep/trophy species, which is why fishing_rod.gd already reaches for FISH_SIZE
## when it needs a body length. Both facts are honoured here rather than papered over:
##
##   * where fish.json HAS size_kg, the heaviest a species lands converts to a length by
##     the isometric relation every length-weight table in fisheries uses (mass grows with
##     the cube of length). KG_TO_M is calibrated on the barrel grouper — its generated
##     mesh measures 1.90 m nose to tail (see underwater_world.gd's DeepGiant) and its
##     heaviest roll is 48 kg — so the constant is read off the game's own geometry.
##   * where it does not (28 of 35 species), FISH_SIZE above is the length, exactly as
##     fishing_rod.gd's 2 m bait rule already treats it.
##
## The two are combined with max(), never averaged: a species is at least as long as the
## body its own mesh is built at, and size_kg can only ever reveal that it lands BIGGER.
## That matters for the long-bodied sturgeon, which is long out of all proportion to its
## weight — the cube law under-reads it at 2.3 m and its authored 3.5 m stands instead.
const KG_TO_M: float = 0.523        ## 1.90 m / 48 kg^(1/3), the barrel grouper
## Nothing to preview: crab, prawn and squid are species ids but not fish shapes, and
## `fish_rotten` is a state rather than an animal. They still get icons; they just do not
## claim a body length.
const NO_LENGTH := {"fish_stone_crab": true, "fish_gutter_prawn": true,
	"fish_inkwell_squid": true, "fish_rotten": true}

## True for an id the pack should offer a real-size preview of.
static func is_species_fish(item_id: String) -> bool:
	return _is_species_fish(item_id) and not NO_LENGTH.has(FISH_MODEL.species_of(item_id))

## Body length in metres for a species (or a cooked fillet of one); 0.0 if it is not a fish.
static func fish_length_m(item_id: String) -> float:
	if not _is_species_fish(item_id):
		return 0.0
	var species: String = FISH_MODEL.species_of(item_id)
	var authored: float = float(FISH_SIZE.get(species, 1.0))
	var kg: Array = FishTable.all().get(species, {}).get("size_kg", [])
	if kg.size() < 2:
		return authored
	return maxf(authored, KG_TO_M * pow(maxf(float(kg[1]), 0.0), 1.0 / 3.0))

## The heaviest this species lands, in kg; 0.0 when fish.json gives it no size_kg. The
## preview caption says so out loud, so the framing can be checked against the data.
static func fish_max_kg(item_id: String) -> float:
	var kg: Array = FishTable.all().get(FISH_MODEL.species_of(item_id), {}).get("size_kg", [])
	return float(kg[1]) if kg.size() >= 2 else 0.0

## Body length in metres of ONE PARTICULAR FISH — the length its landed weight implies,
## not the species ceiling fish_length_m() reports. Same isometric relation as KG_TO_M
## (mass grows with the cube of length), anchored at the species' own documented length
## rather than at the global constant: a fish at its heaviest IS fish_length_m() long,
## and everything lighter shrinks by the cube root of the weight ratio. That keeps the
## authored lengths in charge — a 95 kg sturgeon is the full 3.5 m the FISH_SIZE note
## argues for, where the raw KG_TO_M law would under-read it at 2.4.
##
## 0.0 for anything that is not a raw fish with a size_kg range (cooked ids included —
## a fillet borrowing the whole species mesh must not borrow the whole species LENGTH),
## so callers can fall back to the fixed species-scale draw with a plain `> 0.0` test.
static func fish_instance_length_m(item_id: String, kg: float) -> float:
	if kg <= 0.0 or item_id.begins_with("cooked_") or not is_species_fish(item_id):
		return 0.0
	var top: float = fish_max_kg(item_id)
	if top <= 0.0:
		return 0.0
	# The floor keeps a degenerate weight (a hand-written save, a future 0-min range)
	# from rendering a fish as a crumb: nothing draws under ~37% of the species length.
	var t: float = clampf(kg / top, 0.05, 1.0)
	return fish_length_m(item_id) * pow(t, 1.0 / 3.0)

## ---------------------------------------------------------------- HOW BIG IT IS IN HAND
## Owner, 2026-07-31: "when i hold the barrel grouper it is tiny — it should look massive,
## like the inventory picture."
##
## The pack preview already frames a fish at its real size (item_icons._render_preview, off
## fish_length_m below), so a caught grouper's PORTRAIT is a two-handed monster. The HAND
## was the one place that threw the size away: player_controller._normalize_hand_visual
## measures whatever ItemVisual.build() returned and uniform-scales it so its longest
## dimension is HAND_ITEM_MAX_DIM — 0.18 m, the same 18 cm for a can of peaches, a copper
## sprat and a 48 kg grouper. Only three ids were ever excused from it, by a hand-written
## match on the two fishing poles and the prybar.
##
## This is the fish family's answer to that question, and it is DERIVED from the same body
## length the portrait uses rather than being a second hand-written table that can disagree
## with the first: a fish is shown in the hand at HAND_FRACTION of its true length, floored
## at the ordinary pocket size (so nothing gets SMALLER than it is today) and capped so the
## biggest animals in the table are a trophy rather than a wall.
##
##   copper sprat   0.45 m body -> 0.22 m in hand   (a handful, as now)
##   lantern herring 0.50 m      -> 0.25 m
##   barrel grouper 1.90 m       -> 0.95 m in hand  — wider than the fishing rod reads
##   fathom sturgeon 3.50 m      -> 1.10 m (capped)
##
## COOKED IDS ARE DELIBERATELY EXCLUDED. "cooked_fish_barrel_grouper" is a FILLET — one of
## six to twelve off the animal — and it already borrows the whole fish's mesh; blowing that
## up to a metre of charred grouper would make an existing oddity into a loud one.
const HAND_FRACTION: float = 0.50
## Mirrors PlayerController.HAND_ITEM_MAX_DIM. Kept as a local number rather than a
## cross-class reference so this leaf visual lib does not drag the player into its load
## graph (same reason _tint_of parses fish.json directly instead of going through FishTable).
const HAND_BASE_M: float = 0.18
## A held fish stops growing here. 1.10 m is about as much animal as fits across the view
## at the hand mount without becoming a screen-filling wall.
const HAND_MAX_M: float = 1.10

## Longest-axis size, in metres, that this item should be drawn at IN THE PLAYER'S HAND.
## Returns HAND_BASE_M for everything that is not a raw species fish, i.e. the whole rest of
## the roster keeps the pocket scale it has always had.
static func hand_size_m(item_id: String) -> float:
	if item_id.begins_with("cooked_") or not is_species_fish(item_id):
		return HAND_BASE_M
	return clampf(fish_length_m(item_id) * HAND_FRACTION, HAND_BASE_M, HAND_MAX_M)

static var _longest_m: float = 0.0
## The longest species in the roster, which is what the pack preview scales everything
## against. DERIVED, not written down: add a species to fish.json or to FISH_SIZE and the
## whole preview ladder re-bases itself instead of quietly measuring against a stale record.
static func longest_fish_m() -> float:
	if _longest_m <= 0.0:
		for species in FISH_SIZE:
			_longest_m = maxf(_longest_m, fish_length_m(String(species)))
		for species in FishTable.all():
			_longest_m = maxf(_longest_m, fish_length_m(String(species)))
	return _longest_m
## Structure parts, for the vessel builders below: they are the rain catcher's own
## geometry and are built out of the same vocabulary every player-built thing uses.
const SL := preload("res://scripts/world/structure_lib.gd")

## `kg` is the one particular fish's landed weight, and 0.0 (every existing caller) means
## "no particular fish": icons, hand visuals and generic drops keep the fixed species
## scale they have always had. A dropped SIZED fish passes its recorded weight through
## here (save_manager._make_drop) and the body is drawn at the real length that weight
## implies — a 46 kg grouper on the deck is the 1.9 m animal the catch line listed, not
## the 0.76 m keepsake every grouper used to shrink to on the floor.
static func build(item_id: String, kg: float = 0.0) -> Node3D:
	var root := Node3D.new()
	# Fish family — raw fish AND per-species cooked meals ("cooked_fish_herring").
	# Try the real generated species mesh first (a caught fish reads as that fish),
	# fall back to the procedural silhouette. Cooked ids darken to a seared char.
	if _is_species_fish(item_id):
		var cooked: bool = item_id.begins_with("cooked_")
		var species: String = FISH_MODEL.species_of(item_id)
		var size_mul: float = FISH_SIZE.get(species, 1.0)
		# Real length wins when a weight rode in with the item; the fixed 0.42-of-a-metre
		# ladder stands for everything else. The procedural fallback keeps the same
		# contract by converting the target back into its own multiplier.
		var target_m: float = 0.42 * size_mul
		var real_m: float = fish_instance_length_m(item_id, kg)
		if real_m > 0.0:
			target_m = real_m
			size_mul = target_m / 0.42
		var model: Node3D = FISH_MODEL.build(species, cooked, target_m)
		if model != null:
			# Real fish meshes are authored nose-along-+Z (Meshy is viewer-facing) and
			# creature_anim.load_model() does NOT apply the swim-facing yaw that live
			# creatures get — so a held/dropped fish points END-ON at the camera and you
			# see the nose, not the body. Yaw it -90° so the long axis lies across the
			# view and a FLANK reads side-on (nose to -X, matching the procedural _fish()
			# fallback). Y-only: a fish hung or laid flat stays level, just turned to show
			# its side. The procedural fallback below is already built side-on, so this
			# correction lives ONLY on the real-mesh branch.
			model.rotation.y = deg_to_rad(-90)
			root.add_child(model)
			return root
		_fish_body(root, species, cooked, size_mul)
		return root
	# Real geometry for everything else — a generated mesh under assets/models/items/, or
	# a mapped prop from the CC0 library (PropLib.item_model tries them in that order).
	# Null is the normal answer for most of the roster and simply falls through to the
	# procedural silhouette below, so this can only ever add: deleting a PropLib entry
	# restores the old look with no edit here.
	var real: Node3D = PropLib.item_model(item_id)
	if real != null:
		root.add_child(real)
		return root
	match item_id:
		"canned_food":
			_can(root, Color(0.7, 0.72, 0.75), Color(0.6, 0.3, 0.2))
		"canned_peaches":
			_can(root, Color(0.8, 0.78, 0.7), Color(0.95, 0.65, 0.2))
		"sealed_tin":
			var body := _cyl(root, 0.15, 0.16, Color(0.55, 0.6, 0.62), Vector3(0, 0.08, 0))
			body.rotation.x = 0.0
		"water_ration":
			# Foil pouch: a thin, slightly domed flat box.
			_box(root, Vector3(0.22, 0.28, 0.06), Color(0.7, 0.74, 0.78), Vector3(0, 0.14, 0))
			_box(root, Vector3(0.22, 0.05, 0.06), Color(0.4, 0.55, 0.7), Vector3(0, 0.26, 0))
		"cable_spool":
			# Two end discs on a hub.
			for zy in [-0.16, 0.16]:
				var disc := _cyl(root, 0.26, 0.05, Color(0.25, 0.22, 0.2), Vector3(0, 0.26, zy))
				disc.rotation.x = deg_to_rad(90)
			var hub := _cyl(root, 0.14, 0.3, Color(0.35, 0.3, 0.2), Vector3(0, 0.26, 0))
			hub.rotation.x = deg_to_rad(90)
		"prybar":
			# Long iron shaft with a bent claw end.
			_box(root, Vector3(0.05, 0.05, 0.85), Color(0.28, 0.29, 0.32), Vector3(0, 0.1, 0))
			var claw := _box(root, Vector3(0.05, 0.16, 0.05), Color(0.28, 0.29, 0.32), Vector3(0, 0.14, -0.42))
			claw.rotation.x = deg_to_rad(35)
		"rope":
			_torus(root, 0.13, 0.3, Color(0.74, 0.67, 0.5), Vector3(0, 0.14, 0))
		"throwing_hook":
			_torus(root, 0.1, 0.24, Color(0.72, 0.64, 0.46), Vector3(0, 0.12, 0))
			var shank := _box(root, Vector3(0.04, 0.28, 0.04), Color(0.25, 0.26, 0.29), Vector3(0.18, 0.2, 0))
			shank.rotation.z = deg_to_rad(18)
			var barb := _box(root, Vector3(0.04, 0.12, 0.04), Color(0.25, 0.26, 0.29), Vector3(0.26, 0.1, 0))
			barb.rotation.z = deg_to_rad(-55)
		"flare":
			_cyl(root, 0.045, 0.34, Color(0.85, 0.2, 0.16), Vector3(0, 0.17, 0))
			_cyl(root, 0.05, 0.05, Color(0.2, 0.2, 0.22), Vector3(0, 0.35, 0))
		"life_ring":
			var ring := _torus(root, 0.1, 0.32, Color(0.92, 0.55, 0.2), Vector3(0, 0.34, 0))
			ring.rotation.x = deg_to_rad(90)
		"driftwood":
			_box(root, Vector3(0.9, 0.12, 0.28), Color(0.5, 0.4, 0.28), Vector3(0, 0.08, 0))
		"scrap_metal":
			var plate := _box(root, Vector3(0.55, 0.16, 0.42), Color(0.36, 0.37, 0.4), Vector3(0, 0.12, 0))
			plate.rotation.z = 0.25
		"crude_knife":
			# Wrapped grip below a ground-down shard blade.
			_box(root, Vector3(0.05, 0.18, 0.05), Color(0.32, 0.24, 0.16), Vector3(0, 0.09, 0))          # grip
			_box(root, Vector3(0.03, 0.04, 0.11), Color(0.2, 0.15, 0.1), Vector3(0, 0.19, 0))            # guard
			var blade := _box(root, Vector3(0.02, 0.34, 0.08), Color(0.62, 0.64, 0.68), Vector3(0, 0.4, 0.02))
			blade.rotation.x = deg_to_rad(-6)
		"crude_spear":
			# Long driftwood pole, rope lashing, a shard point lashed at the tip.
			var shaft := _box(root, Vector3(0.045, 1.35, 0.045), Color(0.5, 0.4, 0.28), Vector3(0, 0.6, 0))
			shaft.rotation.z = deg_to_rad(10)
			_box(root, Vector3(0.07, 0.09, 0.07), Color(0.72, 0.64, 0.46), Vector3(0.16, 1.05, 0))       # lashing
			var head := _box(root, Vector3(0.03, 0.28, 0.1), Color(0.6, 0.62, 0.66), Vector3(0.2, 1.32, 0))
			head.rotation.z = deg_to_rad(10)
		"mini_anchor":
			# Stock, ring, shank, two curved flukes — a fist-sized hook anchor.
			_box(root, Vector3(0.05, 0.34, 0.05), Color(0.3, 0.31, 0.34), Vector3(0, 0.2, 0))          # shank
			_torus(root, 0.02, 0.055, Color(0.32, 0.33, 0.36), Vector3(0, 0.4, 0))                     # ring
			_box(root, Vector3(0.24, 0.04, 0.04), Color(0.32, 0.33, 0.36), Vector3(0, 0.33, 0))        # stock
			var flu_l := _box(root, Vector3(0.03, 0.17, 0.05), Color(0.3, 0.31, 0.34), Vector3(-0.1, 0.08, 0))
			flu_l.rotation.z = deg_to_rad(38)
			var flu_r := _box(root, Vector3(0.03, 0.17, 0.05), Color(0.3, 0.31, 0.34), Vector3(0.1, 0.08, 0))
			flu_r.rotation.z = deg_to_rad(-38)
			_box(root, Vector3(0.09, 0.05, 0.05), Color(0.34, 0.35, 0.38), Vector3(-0.17, 0.04, 0))    # fluke tip
			_box(root, Vector3(0.09, 0.05, 0.05), Color(0.34, 0.35, 0.38), Vector3(0.17, 0.04, 0))
		"wrench":
			# Steel bar with an open C-jaw at the head.
			_box(root, Vector3(0.05, 0.5, 0.035), Color(0.55, 0.57, 0.6), Vector3(0, 0.25, 0))         # handle
			_box(root, Vector3(0.16, 0.05, 0.035), Color(0.6, 0.62, 0.65), Vector3(0, 0.51, 0))        # jaw base
			_box(root, Vector3(0.05, 0.1, 0.035), Color(0.6, 0.62, 0.65), Vector3(-0.075, 0.55, 0))    # jaw prong
			_box(root, Vector3(0.05, 0.1, 0.035), Color(0.6, 0.62, 0.65), Vector3(0.075, 0.55, 0))
		"spanner":
			# Ring end at the top, box end at the foot.
			_box(root, Vector3(0.045, 0.46, 0.03), Color(0.5, 0.52, 0.55), Vector3(0, 0.24, 0))        # handle
			_torus(root, 0.03, 0.075, Color(0.55, 0.57, 0.6), Vector3(0, 0.48, 0))                     # ring end
			_box(root, Vector3(0.12, 0.06, 0.03), Color(0.55, 0.57, 0.6), Vector3(0, 0.03, 0))         # box end
		"screwdriver":
			_cyl(root, 0.035, 0.22, Color(0.78, 0.45, 0.2), Vector3(0, 0.11, 0))                       # amber grip
			_cyl(root, 0.012, 0.34, Color(0.6, 0.62, 0.66), Vector3(0, 0.39, 0))                       # shaft
			_box(root, Vector3(0.03, 0.03, 0.008), Color(0.55, 0.57, 0.6), Vector3(0, 0.57, 0))        # flat tip
		"hammer_tool":
			_box(root, Vector3(0.04, 0.5, 0.05), Color(0.45, 0.32, 0.2), Vector3(0, 0.25, 0))          # wood handle
			_box(root, Vector3(0.2, 0.07, 0.07), Color(0.3, 0.31, 0.34), Vector3(0, 0.52, 0))          # head
			var claw := _box(root, Vector3(0.05, 0.1, 0.05), Color(0.28, 0.29, 0.32), Vector3(-0.11, 0.52, 0))
			claw.rotation.z = deg_to_rad(22)                                                           # claw
		"hand_file":
			_box(root, Vector3(0.028, 0.4, 0.016), Color(0.5, 0.52, 0.55), Vector3(0, 0.3, 0))         # flat blade
			_cyl(root, 0.032, 0.14, Color(0.5, 0.33, 0.2), Vector3(0, 0.08, 0))                        # wood tang handle
		"hacksaw":
			_box(root, Vector3(0.42, 0.04, 0.03), Color(0.3, 0.31, 0.34), Vector3(0, 0.34, 0))         # top frame bar
			_box(root, Vector3(0.03, 0.18, 0.03), Color(0.3, 0.31, 0.34), Vector3(0.21, 0.25, 0))      # front upright
			_box(root, Vector3(0.42, 0.015, 0.02), Color(0.72, 0.74, 0.77), Vector3(0, 0.18, 0))       # blade
			var grip := _cyl(root, 0.035, 0.16, Color(0.4, 0.28, 0.18), Vector3(-0.21, 0.2, 0))        # pistol grip
			grip.rotation.z = deg_to_rad(18)
		"raw_sea_bird":
			# A plucked, dressed sea-bird — pink raw flesh, two leg stubs.
			_box(root, Vector3(0.22, 0.12, 0.14), Color(0.82, 0.55, 0.5), Vector3(0, 0.09, 0))
			_box(root, Vector3(0.03, 0.1, 0.03), Color(0.8, 0.72, 0.6), Vector3(-0.05, 0.02, 0.05))
			_box(root, Vector3(0.03, 0.1, 0.03), Color(0.8, 0.72, 0.6), Vector3(0.05, 0.02, 0.05))
		"cooked_sea_bird":
			# Roasted sea-bird — browned skin, crisped legs.
			_box(root, Vector3(0.22, 0.12, 0.14), Color(0.55, 0.35, 0.18), Vector3(0, 0.09, 0))
			_box(root, Vector3(0.03, 0.1, 0.03), Color(0.4, 0.26, 0.14), Vector3(-0.05, 0.02, 0.05))
			_box(root, Vector3(0.03, 0.1, 0.03), Color(0.4, 0.26, 0.14), Vector3(0.05, 0.02, 0.05))
		"tarp":
			_box(root, Vector3(0.5, 0.16, 0.4), Color(0.62, 0.66, 0.6), Vector3(0, 0.1, 0))
			_box(root, Vector3(0.52, 0.06, 0.18), Color(0.55, 0.6, 0.55), Vector3(0, 0.2, 0))
		"kelp_bundle":
			for i in range(4):
				var frond := _box(root, Vector3(0.06, 0.42, 0.03),
					Color(0.3, 0.75, 0.5), Vector3(-0.12 + i * 0.08, 0.22, 0.0), true, 1.4)
				frond.rotation.z = deg_to_rad(-14 + i * 9)
		"snail_live":
			# A small coiled shell over a stub foot — glows faintly even out of the water.
			_cyl(root, 0.1, 0.09, Color(0.12, 0.14, 0.16), Vector3(0, 0.05, 0))
			_cyl(root, 0.05, 0.05, Color(0.2, 0.9, 0.85), Vector3(0.02, 0.11, 0), true, 1.2)
			_box(root, Vector3(0.14, 0.03, 0.06), Color(0.18, 0.2, 0.22), Vector3(0, 0.015, 0.05))
		"escargot":
			# A shallow plate with three seared shells in their own butter-warm light.
			_cyl(root, 0.14, 0.02, Color(0.75, 0.76, 0.72), Vector3(0, 0.01, 0))
			for i in range(3):
				var a4: float = i * TAU / 3.0
				_cyl(root, 0.045, 0.045, Color(0.35, 0.24, 0.14),
					Vector3(cos(a4) * 0.07, 0.045, sin(a4) * 0.07), true, 0.8)
		"bloom_lamp_kit":
			# Owner call, 2026-07-27: was a 0.3 m grey cube with a 0.16 m emissive cube sat on
			# it — two untextured boxes, i.e. a placeholder. What structures.bloom_lamp
			# actually erects is a base plate, a post and a glowing head, so the KIT is those
			# three parts flat-packed: the plate down, the post broken into two lengths and
			# strapped beside it, and the live bloom cell caged on top (the cell is the part
			# that has to survive the carry, so it travels sitting up in its guard).
			_box(root, Vector3(0.34, 0.035, 0.34), Color(0.34, 0.35, 0.38), Vector3(0, 0.018, 0))   # base plate
			for bl_c in [-0.13, 0.13]:                                                              # bolt holes
				_cyl(root, 0.022, 0.012, Color(0.22, 0.23, 0.25), Vector3(bl_c, 0.04, -0.13))
			for bl_i in range(2):
				var bl_post := _cyl(root, 0.035, 0.32, Color(0.3, 0.31, 0.34),
					Vector3(0.0, 0.075 + bl_i * 0.062, -0.09 + bl_i * 0.02))
				bl_post.rotation.z = deg_to_rad(90)
				bl_post.rotation.y = deg_to_rad(-6 + bl_i * 12)                                     # post halves
			_box(root, Vector3(0.05, 0.13, 0.09), Color(0.74, 0.67, 0.5), Vector3(0.05, 0.1, -0.09))  # strap
			# The bloom cell: a stoppered jar of live light standing in a four-bar guard.
			_cyl(root, 0.062, 0.13, Color(0.2, 0.9, 0.85), Vector3(0, 0.105, 0.09), true, 2.2)
			_cyl(root, 0.066, 0.018, Color(0.4, 0.42, 0.45), Vector3(0, 0.045, 0.09))               # cell foot
			_cyl(root, 0.05, 0.03, Color(0.45, 0.34, 0.2), Vector3(0, 0.182, 0.09))                 # cork
			for bl_g in range(4):
				var bl_a: float = bl_g * TAU / 4.0 + 0.4
				_box(root, Vector3(0.014, 0.16, 0.014), Color(0.42, 0.43, 0.46),
					Vector3(cos(bl_a) * 0.072, 0.105, 0.09 + sin(bl_a) * 0.072))                    # guard bars
			# A THIN ring tying the four bars off at the top. TorusMesh's inner_radius is the
			# hole, so it has to be held just under the outer or the "hoop" is a solid disc
			# capping the guard and hiding the one lit part of the kit.
			var bl_hoop := _torus(root, 0.066, 0.08, Color(0.42, 0.43, 0.46), Vector3(0, 0.19, 0.09))
			bl_hoop.rotation.x = 0.0                                                                # guard hoop, laid flat
		"leanto_kit":
			var roll := _cyl(root, 0.13, 0.5, Color(0.6, 0.64, 0.58), Vector3(0, 0.13, 0))
			roll.rotation.z = deg_to_rad(90)
		"walkway_kit":
			for i in range(3):
				_box(root, Vector3(0.6, 0.06, 0.5), Color(0.5, 0.4, 0.28), Vector3(0, 0.06 + i * 0.08, 0))
		"barricade_kit":
			_box(root, Vector3(0.5, 0.32, 0.12), Color(0.4, 0.36, 0.34), Vector3(0, 0.18, 0))
			_box(root, Vector3(0.08, 0.36, 0.08), Color(0.45, 0.35, 0.22), Vector3(-0.18, 0.18, 0))
			_box(root, Vector3(0.08, 0.36, 0.08), Color(0.45, 0.35, 0.22), Vector3(0.18, 0.18, 0))
		"fishing_rod":
			# Owner pick, 2026-07-29 — option 3 "WAND" off the tests/tool_options.gd contact
			# sheet. The brief was one word, "skinnier/more", so the four options were four
			# points on one slenderness ladder rather than four redesigns, and the owner took
			# the extreme end of it. What changed against the rod this replaces is SECTIONS,
			# not architecture: a 19 mm blank tapering to 3 mm (was 36 -> 7), 2.10 m instead of
			# 1.90, EIGHT guides instead of six and every one of them smaller (30 -> 8 mm rings
			# against the old 54 -> 14), and the grips, seat and reel trimmed with the blank so
			# the whole tool is finer rather than a thin stick carrying fat furniture. For scale:
			# a real stand-up offshore blank is 22-26 mm at the ferrule and 4-5 mm at the tip,
			# which is why this reads as so much finer while still being the same class of tool.
			#
			# Architecture kept from the rebuild before it: notched gimbal butt cap that seats
			# into a fighting belt, ribbed butt grip, machined seat with knurled lock rings, a
			# lever-drag multiplier sat ON TOP of the seat where an overhead reel goes, foregrip,
			# four stacked tapering blank sections, stepped guides, roller tip. Working kit off a
			# rusting rig — machined and salt-hazed, no chrome anywhere.
			#
			# The whole rig hangs off ONE pivot rather than the root, so every part shares a
			# single lean and the "hand_tip" marker at the roller tip inherits it for free.
			_rod_build(root, ROD_WAND)
		"deep_rig_pole":
			# Owner pick, 2026-07-29 — option B "DECK WINCH" off the same contact sheet, chosen
			# out of four with the note that it is "not a rod at all". That is the whole point:
			# the deep rig is a HEAVY DEEP-DROP HAND-LINE for putting a lead 45 m STRAIGHT DOWN
			# off the crane's machinery deck (see fishing_rod.gd's deep branch — no float, no
			# drift, no cast; the readout counts the metres as the lead falls), so it has no
			# casting blank, no taper and no ring guides. It is a machine you set down on a deck
			# and crank: a foot, a mast, one big flanged drum wound with braid, a crank, a
			# ratchet and pawl, a brake shoe on the rim, one diagonal strut, and the line leaving
			# over a bent HOOP FAIRLEAD at the head with the terminal tackle hove up short.
			#
			# DELIBERATELY SIMPLER than the 104-mesh version the owner rejected: no davit arm, no
			# sheave block, no standing-line run up the face of the mast, fewer and bigger shapes.
			# The line leaves over ONE loop of round bar, which is also what makes "which way is
			# forward" answerable — see the hand_tip note in _deep_winch().
			_deep_winch(root)
		"cooked_fish":
			_box(root, Vector3(0.3, 0.06, 0.16), Color(0.62, 0.45, 0.26), Vector3(0, 0.05, 0))
			_box(root, Vector3(0.24, 0.02, 0.12), Color(0.35, 0.22, 0.12), Vector3(0, 0.09, 0))
		"cooked_fish_prime":
			_box(root, Vector3(0.42, 0.08, 0.2), Color(0.68, 0.48, 0.28), Vector3(0, 0.06, 0))
			_box(root, Vector3(0.34, 0.02, 0.15), Color(0.4, 0.24, 0.12), Vector3(0, 0.11, 0))
		"drop_net_kit":
			# A folded mesh bundle with two weights showing.
			_box(root, Vector3(0.4, 0.2, 0.32), Color(0.68, 0.62, 0.46), Vector3(0, 0.12, 0))
			_box(root, Vector3(0.1, 0.08, 0.1), Color(0.3, 0.31, 0.34), Vector3(-0.12, 0.26, 0.05))
			_box(root, Vector3(0.1, 0.08, 0.1), Color(0.3, 0.31, 0.34), Vector3(0.1, 0.26, -0.06))
		"glow_worm":
			# Owner call, 2026-07-27: this WAS a single 0.25 m emissive teal BoxMesh — a bare
			# untextured cube, the one thing in the pack that read as an un-authored
			# placeholder (the `glow_mucus` comment below already called it "the glow worm's
			# cube"). It is a live animal you sneak up on in the dark and it is a crafting
			# input for the bloom lamp, so it earns a real body: a fat segmented grub curled
			# on itself, the lit gut showing through thinner skin between the rings.
			_glow_worm(root, false)
		"glow_worm_cooked":
			# Same grub off the pan. The old case shared ONE cube with the raw worm — the
			# comment promised "slightly different glow in hand" and the code was identical.
			# Cooking a Bloom animal puts the light out: browned, shrunken, curled tighter.
			_glow_worm(root, true)

		# ---- SALVAGED MATERIALS: what the rig gives up when you take it apart ----
		"steel_plate":
			# Flat rusted rectangle, one edge bright where the saw went through.
			var sp := _box(root, Vector3(0.62, 0.035, 0.44), Color(0.44, 0.34, 0.26), Vector3(0, 0.02, 0))
			sp.rotation.y = deg_to_rad(8)
			_box(root, Vector3(0.62, 0.012, 0.05), Color(0.66, 0.68, 0.7), Vector3(0, 0.042, 0.2))
		"pipe_length":
			# A metre of tube lying on its side, threaded collar at one end.
			var pipe := _cyl(root, 0.055, 1.05, Color(0.36, 0.37, 0.4), Vector3(0, 0.055, 0))
			pipe.rotation.z = deg_to_rad(90)
			var collar := _cyl(root, 0.072, 0.09, Color(0.3, 0.28, 0.26), Vector3(-0.46, 0.055, 0))
			collar.rotation.z = deg_to_rad(90)
		"wire_spool":
			# Coil wound on a drum: hub, two end cheeks, copper turns between them.
			var hub_w := _cyl(root, 0.07, 0.24, Color(0.35, 0.3, 0.22), Vector3(0, 0.13, 0))
			hub_w.rotation.z = deg_to_rad(90)
			for ex in [-0.12, 0.12]:
				var cheek := _cyl(root, 0.15, 0.025, Color(0.3, 0.26, 0.2), Vector3(ex, 0.13, 0))
				cheek.rotation.z = deg_to_rad(90)
			for t in range(3):
				var turn := _cyl(root, 0.115, 0.06, Color(0.68, 0.44, 0.22), Vector3(-0.07 + t * 0.07, 0.13, 0))
				turn.rotation.z = deg_to_rad(90)
		"bolt_handful":
			# A scatter of cut shanks — never a neat pile.
			for i in range(5):
				var bolt := _cyl(root, 0.016, 0.11, Color(0.5, 0.45, 0.38),
					Vector3(-0.08 + i * 0.04, 0.02, sin(i * 2.1) * 0.05))
				bolt.rotation.z = deg_to_rad(90)
				bolt.rotation.y = i * 0.7
				_box(root, Vector3(0.035, 0.02, 0.035), Color(0.56, 0.5, 0.42),
					Vector3(-0.13 + i * 0.04, 0.02, sin(i * 2.1) * 0.05))
		"glass_pane":
			# Standing pane, one corner gone. Pale, not clear — the sea fogs it.
			_box(root, Vector3(0.44, 0.5, 0.014), Color(0.7, 0.8, 0.82), Vector3(0, 0.25, 0))
			_box(root, Vector3(0.46, 0.03, 0.03), Color(0.4, 0.42, 0.44), Vector3(0, 0.01, 0))
			var chip := _box(root, Vector3(0.1, 0.1, 0.016), Color(0.62, 0.72, 0.74), Vector3(0.19, 0.46, 0))
			chip.rotation.z = deg_to_rad(38)
		"canvas_scrap":
			# Cut-down tarp, folded twice, corners not lining up.
			var fold_a := _box(root, Vector3(0.4, 0.03, 0.3), Color(0.6, 0.63, 0.57), Vector3(0, 0.02, 0))
			fold_a.rotation.y = deg_to_rad(-9)
			var fold_b := _box(root, Vector3(0.36, 0.03, 0.26), Color(0.66, 0.69, 0.62), Vector3(0.02, 0.05, 0.02))
			fold_b.rotation.y = deg_to_rad(12)
			_box(root, Vector3(0.3, 0.025, 0.2), Color(0.56, 0.6, 0.55), Vector3(-0.01, 0.076, -0.01))
		"foam_block":
			# Closed-cell foam, yellowed, one face cut open.
			_box(root, Vector3(0.34, 0.2, 0.26), Color(0.82, 0.8, 0.68), Vector3(0, 0.1, 0))
			_box(root, Vector3(0.33, 0.03, 0.25), Color(0.88, 0.87, 0.78), Vector3(0, 0.2, 0))
		"ceramic_shard":
			# Broken firebrick: two angled pieces, chalky and pale.
			var sh_a := _box(root, Vector3(0.26, 0.05, 0.18), Color(0.78, 0.74, 0.66), Vector3(0, 0.03, 0))
			sh_a.rotation.z = deg_to_rad(-7)
			var sh_b := _box(root, Vector3(0.16, 0.05, 0.13), Color(0.7, 0.66, 0.58), Vector3(0.11, 0.08, 0.05))
			sh_b.rotation.z = deg_to_rad(24)
			sh_b.rotation.y = deg_to_rad(30)
		"copper_coil":
			# Three bright turns still holding the shape of the drum.
			for i in range(3):
				_torus(root, 0.045, 0.17, Color(0.74, 0.45, 0.2), Vector3(0, 0.05 + i * 0.045, 0))
		"rubber_hose":
			# Perished hose, coiled, one cut end showing its bore.
			_torus(root, 0.035, 0.24, Color(0.16, 0.16, 0.17), Vector3(0, 0.04, 0))
			_torus(root, 0.035, 0.2, Color(0.2, 0.2, 0.21), Vector3(0, 0.1, 0))
			var cut := _cyl(root, 0.037, 0.1, Color(0.24, 0.23, 0.22), Vector3(0.2, 0.13, 0.06))
			cut.rotation.z = deg_to_rad(70)

		# ---- HARVESTED: what the water gives, once you work it ----
		"kelp_fiber":
			# Stripped fronds dried into hanks, tied at the waist.
			for i in range(5):
				var strand := _box(root, Vector3(0.03, 0.4, 0.02),
					Color(0.52, 0.6, 0.36), Vector3(-0.08 + i * 0.04, 0.2, 0.0))
				strand.rotation.z = deg_to_rad(-10 + i * 5)
			_box(root, Vector3(0.22, 0.05, 0.06), Color(0.72, 0.66, 0.5), Vector3(0, 0.22, 0))
		"fish_bone":
			# A picked spine: skull, backbone, ribs going thin toward the tail.
			_box(root, Vector3(0.34, 0.012, 0.012), Color(0.86, 0.84, 0.76), Vector3(0, 0.02, 0))
			_box(root, Vector3(0.07, 0.05, 0.045), Color(0.82, 0.8, 0.72), Vector3(-0.18, 0.03, 0))
			for i in range(5):
				var rib := _box(root, Vector3(0.008, 0.07 - i * 0.011, 0.008),
					Color(0.84, 0.82, 0.74), Vector3(-0.1 + i * 0.055, 0.02, 0))
				rib.rotation.x = deg_to_rad(24)
		"shell_grit":
			# A low drift of crushed shell with a few pieces the hammer missed.
			_cyl(root, 0.16, 0.05, Color(0.86, 0.84, 0.78), Vector3(0, 0.025, 0))
			_cyl(root, 0.09, 0.04, Color(0.9, 0.88, 0.82), Vector3(0.01, 0.06, 0.0))
			_box(root, Vector3(0.05, 0.02, 0.04), Color(0.78, 0.74, 0.68), Vector3(-0.1, 0.06, 0.06))
			_box(root, Vector3(0.04, 0.02, 0.03), Color(0.8, 0.77, 0.7), Vector3(0.11, 0.06, -0.05))
		"tar_lump":
			# Black, soft-edged, picks up every light in the room.
			_box(root, Vector3(0.2, 0.12, 0.17), Color(0.09, 0.09, 0.1), Vector3(0, 0.06, 0))
			var blob := _box(root, Vector3(0.12, 0.08, 0.11), Color(0.13, 0.12, 0.12), Vector3(0.05, 0.13, 0.02))
			blob.rotation.y = deg_to_rad(28)
		"float_buoy":
			# Orange foam float, painted band, becket rope on top.
			_cyl(root, 0.16, 0.3, Color(0.86, 0.42, 0.16), Vector3(0, 0.15, 0))
			_cyl(root, 0.165, 0.07, Color(0.75, 0.74, 0.7), Vector3(0, 0.19, 0))
			_torus(root, 0.02, 0.07, Color(0.74, 0.67, 0.5), Vector3(0, 0.32, 0))
		"wood_slat":
			# Three ripped slats, stacked and not quite square to each other.
			for i in range(3):
				var slat := _box(root, Vector3(0.8, 0.035, 0.11),
					Color(0.52, 0.42, 0.3), Vector3(0, 0.02 + i * 0.04, i * 0.02))
				slat.rotation.y = deg_to_rad(-6 + i * 6)
		"raw_fillet":
			# Two pale sides off the frame, skin down.
			var fil := _box(root, Vector3(0.3, 0.045, 0.14), Color(0.85, 0.72, 0.68), Vector3(0, 0.025, 0))
			fil.rotation.y = deg_to_rad(-8)
			var fil2 := _box(root, Vector3(0.28, 0.04, 0.13), Color(0.8, 0.66, 0.62), Vector3(0.02, 0.07, 0.05))
			fil2.rotation.y = deg_to_rad(14)
			_box(root, Vector3(0.29, 0.012, 0.13), Color(0.55, 0.58, 0.6), Vector3(0, 0.005, 0))

		# ---- STRUCTURE KITS: a bundle you carry and unroll somewhere ----
		"bedroll_kit":
			# Canvas rolled around foam, strapped twice.
			var roll_b := _cyl(root, 0.15, 0.62, Color(0.6, 0.63, 0.57), Vector3(0, 0.15, 0))
			roll_b.rotation.z = deg_to_rad(90)
			var core := _cyl(root, 0.09, 0.64, Color(0.82, 0.8, 0.68), Vector3(0.0, 0.15, 0))
			core.rotation.z = deg_to_rad(90)
			for sx in [-0.17, 0.17]:
				var strap := _box(root, Vector3(0.04, 0.32, 0.32), Color(0.74, 0.67, 0.5), Vector3(sx, 0.15, 0))
				strap.rotation.x = deg_to_rad(4)
		"locker_kit":
			# Two folded plates face to face with the bolt bag wedged between.
			var pl_a := _box(root, Vector3(0.5, 0.06, 0.36), Color(0.42, 0.36, 0.3), Vector3(0, 0.03, 0))
			pl_a.rotation.y = deg_to_rad(5)
			_box(root, Vector3(0.5, 0.06, 0.36), Color(0.36, 0.37, 0.4), Vector3(0.02, 0.1, 0.02))
			_box(root, Vector3(0.14, 0.09, 0.12), Color(0.55, 0.5, 0.42), Vector3(-0.14, 0.17, -0.05))
			_box(root, Vector3(0.08, 0.03, 0.03), Color(0.5, 0.52, 0.55), Vector3(0.2, 0.16, 0.1))
		"rain_catcher_kit":
			# Folded tarp with the downpipe laid across it and guys coiled on top.
			_box(root, Vector3(0.42, 0.1, 0.34), Color(0.6, 0.64, 0.58), Vector3(0, 0.05, 0))
			var dp := _cyl(root, 0.045, 0.6, Color(0.36, 0.37, 0.4), Vector3(0, 0.14, 0.06))
			dp.rotation.z = deg_to_rad(90)
			_torus(root, 0.03, 0.11, Color(0.74, 0.67, 0.5), Vector3(0.05, 0.21, -0.08))
		"brazier_kit":
			# A cut drum with vent slots punched round the foot, firebrick inside.
			_cyl(root, 0.2, 0.34, Color(0.42, 0.32, 0.24), Vector3(0, 0.17, 0))
			_cyl(root, 0.17, 0.06, Color(0.72, 0.68, 0.6), Vector3(0, 0.32, 0))
			for i in range(6):
				var a: float = i * TAU / 6.0
				_box(root, Vector3(0.05, 0.07, 0.05), Color(0.1, 0.09, 0.09),
					Vector3(cos(a) * 0.19, 0.07, sin(a) * 0.19))
			_torus(root, 0.015, 0.055, Color(0.34, 0.35, 0.38), Vector3(0.2, 0.28, 0))
		"chair_kit":
			# Slats folded flat with the sling canvas laid over them.
			for i in range(2):
				var leg := _box(root, Vector3(0.72, 0.04, 0.09),
					Color(0.52, 0.42, 0.3), Vector3(0, 0.03 + i * 0.045, -0.06 + i * 0.12))
				leg.rotation.y = deg_to_rad(-11 + i * 22)
			_box(root, Vector3(0.34, 0.035, 0.26), Color(0.6, 0.63, 0.57), Vector3(0, 0.14, 0))
			_box(root, Vector3(0.09, 0.05, 0.07), Color(0.55, 0.5, 0.42), Vector3(0.24, 0.14, 0.05))
		"workbench_kit":
			# Plank top bundled with the steel end-skin and the leg stock.
			for i in range(3):
				_box(root, Vector3(0.85, 0.05, 0.24), Color(0.5, 0.4, 0.28), Vector3(0, 0.03 + i * 0.055, 0))
			_box(root, Vector3(0.3, 0.03, 0.26), Color(0.4, 0.42, 0.45), Vector3(-0.26, 0.21, 0))
			var vise := _box(root, Vector3(0.1, 0.09, 0.09), Color(0.34, 0.35, 0.38), Vector3(0.3, 0.24, 0))
			vise.rotation.z = deg_to_rad(9)
		"drying_rack_kit":
			# Two poles crossed at the head with the line coiled where they meet.
			var pole_a := _box(root, Vector3(0.06, 0.95, 0.06), Color(0.5, 0.4, 0.28), Vector3(-0.04, 0.42, 0))
			pole_a.rotation.z = deg_to_rad(11)
			var pole_b := _box(root, Vector3(0.06, 0.95, 0.06), Color(0.46, 0.37, 0.26), Vector3(0.04, 0.42, 0.07))
			pole_b.rotation.z = deg_to_rad(-11)
			_torus(root, 0.035, 0.13, Color(0.74, 0.67, 0.5), Vector3(0, 0.78, 0.03))
		"planter_kit":
			# Folded steel tray, seams black with tar, packed with fiber.
			_box(root, Vector3(0.46, 0.16, 0.3), Color(0.4, 0.42, 0.45), Vector3(0, 0.08, 0))
			_box(root, Vector3(0.4, 0.05, 0.24), Color(0.24, 0.2, 0.14), Vector3(0, 0.17, 0))
			for ex in [-0.23, 0.23]:
				_box(root, Vector3(0.02, 0.17, 0.31), Color(0.1, 0.1, 0.1), Vector3(ex, 0.08, 0))
			_box(root, Vector3(0.05, 0.12, 0.03), Color(0.45, 0.62, 0.35), Vector3(0.06, 0.24, 0.02), true, 0.5)
		"shelf_kit":
			# One slat and two folded brackets, wrapped together.
			_box(root, Vector3(0.7, 0.05, 0.2), Color(0.52, 0.42, 0.3), Vector3(0, 0.03, 0))
			for ex2 in [-0.22, 0.22]:
				_box(root, Vector3(0.04, 0.14, 0.04), Color(0.4, 0.42, 0.45), Vector3(ex2, 0.12, -0.06))
				_box(root, Vector3(0.04, 0.04, 0.14), Color(0.4, 0.42, 0.45), Vector3(ex2, 0.07, 0.0))
			_box(root, Vector3(0.1, 0.05, 0.08), Color(0.55, 0.5, 0.42), Vector3(0, 0.09, 0.09))
		"wall_panel_kit":
			# Two plates leaning against the frame pipe.
			var pan_a := _box(root, Vector3(0.55, 0.55, 0.03), Color(0.4, 0.42, 0.45), Vector3(0, 0.28, 0))
			pan_a.rotation.z = deg_to_rad(-8)
			var pan_b := _box(root, Vector3(0.52, 0.52, 0.03), Color(0.44, 0.34, 0.26), Vector3(0.05, 0.26, 0.07))
			pan_b.rotation.z = deg_to_rad(-13)
			var frame := _cyl(root, 0.04, 0.6, Color(0.36, 0.37, 0.4), Vector3(-0.24, 0.3, 0.1))
			frame.rotation.z = deg_to_rad(6)
		"lamp_post_kit":
			# The post lying down with its bloom head already glowing.
			var post := _cyl(root, 0.05, 1.0, Color(0.36, 0.37, 0.4), Vector3(0, 0.06, 0))
			post.rotation.z = deg_to_rad(90)
			_box(root, Vector3(0.16, 0.16, 0.16), Color(0.2, 0.9, 0.85), Vector3(0.5, 0.09, 0), true, 1.8)
			_torus(root, 0.02, 0.07, Color(0.68, 0.44, 0.22), Vector3(0.3, 0.1, 0))
		"windbreak_kit":
			# Tarp rolled around two stake pipes.
			var wr := _cyl(root, 0.13, 0.7, Color(0.58, 0.62, 0.56), Vector3(0, 0.13, 0))
			wr.rotation.z = deg_to_rad(90)
			for zx in [-0.09, 0.09]:
				var stake := _cyl(root, 0.035, 0.86, Color(0.36, 0.37, 0.4), Vector3(0, 0.28, zx))
				stake.rotation.z = deg_to_rad(90)
			_box(root, Vector3(0.05, 0.3, 0.3), Color(0.74, 0.67, 0.5), Vector3(0.16, 0.16, 0))
		"rug_kit":
			# A hooked mat rolled tight, fiber showing at the ends.
			var rug := _cyl(root, 0.14, 0.66, Color(0.56, 0.5, 0.4), Vector3(0, 0.14, 0))
			rug.rotation.z = deg_to_rad(90)
			for ex3 in [-0.33, 0.33]:
				var endc := _cyl(root, 0.13, 0.05, Color(0.5, 0.58, 0.36), Vector3(ex3, 0.14, 0))
				endc.rotation.z = deg_to_rad(90)
			_box(root, Vector3(0.04, 0.3, 0.3), Color(0.72, 0.66, 0.5), Vector3(0.1, 0.14, 0))

		# ---- UPGRADED GEAR: the same tools, finished properly ----
		"honed_knife":
			# Crude knife re-worked: longer bright blade, trued spine, wrapped grip.
			_box(root, Vector3(0.05, 0.19, 0.05), Color(0.36, 0.26, 0.17), Vector3(0, 0.09, 0))
			for i in range(3):
				_box(root, Vector3(0.055, 0.02, 0.055), Color(0.7, 0.63, 0.46), Vector3(0, 0.04 + i * 0.05, 0))
			_box(root, Vector3(0.035, 0.04, 0.12), Color(0.3, 0.31, 0.34), Vector3(0, 0.2, 0))
			var hb := _box(root, Vector3(0.022, 0.4, 0.085), Color(0.78, 0.8, 0.84), Vector3(0, 0.43, 0.02))
			hb.rotation.x = deg_to_rad(-5)
			_box(root, Vector3(0.006, 0.4, 0.02), Color(0.92, 0.94, 0.96), Vector3(0.011, 0.43, 0.06))
		"honed_spear":
			# Filed point with a bone barb set behind it.
			var hs := _box(root, Vector3(0.045, 1.4, 0.045), Color(0.46, 0.37, 0.26), Vector3(0, 0.62, 0))
			hs.rotation.z = deg_to_rad(10)
			_box(root, Vector3(0.07, 0.1, 0.07), Color(0.72, 0.64, 0.46), Vector3(0.17, 1.08, 0))
			var hh := _box(root, Vector3(0.028, 0.34, 0.09), Color(0.8, 0.82, 0.86), Vector3(0.22, 1.38, 0))
			hh.rotation.z = deg_to_rad(10)
			var barb := _box(root, Vector3(0.015, 0.13, 0.03), Color(0.86, 0.84, 0.76), Vector3(0.2, 1.26, 0.03))
			barb.rotation.z = deg_to_rad(-32)
		"tool_belt":
			# A rope waist with canvas pouches hanging off it.
			_torus(root, 0.035, 0.24, Color(0.74, 0.67, 0.5), Vector3(0, 0.06, 0))
			for i in range(3):
				var a2: float = -0.7 + i * 0.7
				_box(root, Vector3(0.12, 0.14, 0.07), Color(0.6, 0.63, 0.57),
					Vector3(cos(a2) * 0.2, 0.09, sin(a2) * 0.2))
			_box(root, Vector3(0.07, 0.05, 0.03), Color(0.5, 0.52, 0.55), Vector3(-0.22, 0.07, 0))
		"flashlight":
			# A rubber-armoured hand torch lying on its side: barrel, knurled grip band, a
			# wider head, and a pale lens on the head end. Long axis laid along X.
			var body: MeshInstance3D = _cyl(root, 0.028, 0.2, Color(0.16, 0.17, 0.19), Vector3(0, 0.028, 0))
			body.rotation.z = deg_to_rad(90)
			var grip: MeshInstance3D = _cyl(root, 0.031, 0.03, Color(0.5, 0.42, 0.12), Vector3(-0.02, 0.028, 0))
			grip.rotation.z = deg_to_rad(90)
			var head: MeshInstance3D = _cyl(root, 0.045, 0.05, Color(0.2, 0.21, 0.23), Vector3(0.11, 0.028, 0))
			head.rotation.z = deg_to_rad(90)
			var lens: MeshInstance3D = _cyl(root, 0.04, 0.012, Color(0.9, 0.92, 0.85), Vector3(0.14, 0.028, 0), true, 0.6)
			lens.rotation.z = deg_to_rad(90)
		"storm_lantern":
			# Bloom light behind glass in a screwed steel cage. Weather can't touch it.
			_cyl(root, 0.11, 0.05, Color(0.36, 0.37, 0.4), Vector3(0, 0.025, 0))
			_cyl(root, 0.085, 0.22, Color(0.2, 0.9, 0.85), Vector3(0, 0.16, 0), true, 1.6)
			for i in range(4):
				var a3: float = i * TAU / 4.0
				_box(root, Vector3(0.018, 0.24, 0.018), Color(0.42, 0.43, 0.46),
					Vector3(cos(a3) * 0.095, 0.16, sin(a3) * 0.095))
			_cyl(root, 0.1, 0.05, Color(0.36, 0.37, 0.4), Vector3(0, 0.29, 0))
			_torus(root, 0.014, 0.06, Color(0.5, 0.52, 0.55), Vector3(0, 0.35, 0))
		"patched_boots":
			# Two boots, hose soles, canvas uppers, every seam paid with tar.
			for i in range(2):
				var bx: float = -0.1 + i * 0.2
				_box(root, Vector3(0.15, 0.05, 0.32), Color(0.16, 0.16, 0.17), Vector3(bx, 0.025, 0))
				_box(root, Vector3(0.14, 0.16, 0.2), Color(0.6, 0.63, 0.57), Vector3(bx, 0.13, -0.05))
				_box(root, Vector3(0.145, 0.03, 0.21), Color(0.1, 0.1, 0.1), Vector3(bx, 0.055, -0.05))
				_box(root, Vector3(0.05, 0.04, 0.05), Color(0.72, 0.66, 0.5), Vector3(bx, 0.2, -0.05))
		# ---- GALLEY STORES: the crew's own food, all of it well past its date ----
		# Owner call, 2026-07-26: every one of these went in the pack as the same anonymous
		# yellow cube. Icons are rendered from these meshes now, so SILHOUETTE is the whole
		# job — a crescent, a bunch, a wedge, a round with a candle. Colour alone does not
		# survive a 74 px slot.
		"dried_fish":
			# Split, gutted and hung until it went stiff, cord still through its head. Built on
			# a tapered LOZENGE, not a plank: the first pass was a flat box with a spine strip
			# on it and photographed as a length of timber with a rail down the middle.
			_sph(root, 0.07, Color(0.56, 0.43, 0.29), Vector3(0, 0.045, 0), Vector3(2.1, 0.42, 1.0))
			_sph(root, 0.05, Color(0.5, 0.38, 0.26), Vector3(-0.14, 0.045, 0), Vector3(1.1, 0.5, 0.95))   # head
			_sph(root, 0.012, Color(0.08, 0.07, 0.06), Vector3(-0.17, 0.055, 0.03), Vector3(1.0, 1.0, 0.6))  # eye
			# Tail fan tipped up out of the flat: edge-on it was a dark card stuck to the end.
			var df_tail := _prism(root, Vector3(0.12, 0.02, 0.11), Color(0.44, 0.33, 0.22), Vector3(0.18, 0.055, 0))
			df_tail.rotation.z = deg_to_rad(90)
			df_tail.rotation.x = deg_to_rad(28)
			for df_i in range(3):
				var df_r := _box(root, Vector3(0.008, 0.012, 0.075), Color(0.36, 0.27, 0.18),
					Vector3(-0.02 + df_i * 0.05, 0.07, 0))
				df_r.rotation.y = deg_to_rad(9)                                                          # split ribs
			var df_cord := _torus(root, 0.007, 0.03, Color(0.74, 0.67, 0.5), Vector3(-0.185, 0.085, 0))
			df_cord.rotation.x = 0.0                                                                     # line cord
		"croissant":
			# A bent tube, not a row of balls. Beads on an arc — however carefully spaced —
			# photograph as a handful of dough; six overlapping segments laid ALONG the curve
			# (each yawed to the tangent) hold together as one body, and the open middle is
			# what makes it a croissant rather than a bun.
			for cr_i in range(6):
				var cr_a: float = deg_to_rad(-112.0 + cr_i * 45.0)
				var cr_seg := _cyl(root, 0.044 - absf(cr_i - 2.5) * 0.006, 0.1,
					Color(0.84, 0.63, 0.32).darkened(absf(cr_i - 2.5) * 0.03),
					Vector3(cos(cr_a) * 0.115, 0.042, sin(cr_a) * 0.115))
				cr_seg.rotation = Vector3(deg_to_rad(90), -cr_a, 0)
			for cr_h in [-134.0, 113.0]:
				_sph(root, 0.022, Color(0.7, 0.5, 0.24),
					Vector3(cos(deg_to_rad(cr_h)) * 0.115, 0.04, sin(deg_to_rad(cr_h)) * 0.115),
					Vector3(1.0, 0.8, 1.0))                                                          # the horns
		"carrot_cake":
			# A cut slab off a tray bake: crumb, a thick lid of cream frosting, one piped
			# carrot. Kept rectangular so the round birthday cake stays its own thing.
			_box(root, Vector3(0.18, 0.085, 0.13), Color(0.55, 0.37, 0.2), Vector3(0, 0.043, 0))
			_box(root, Vector3(0.181, 0.012, 0.131), Color(0.72, 0.6, 0.4), Vector3(0, 0.055, 0))      # crumb seam
			_box(root, Vector3(0.185, 0.03, 0.135), Color(0.93, 0.91, 0.85), Vector3(0, 0.1, 0))       # frosting
			var cc_car := _cone(root, 0.016, 0.002, 0.05, Color(0.88, 0.5, 0.16), Vector3(0.02, 0.118, 0))
			cc_car.rotation.z = deg_to_rad(90)
			_box(root, Vector3(0.03, 0.006, 0.012), Color(0.36, 0.55, 0.26), Vector3(-0.02, 0.122, 0))
		"bananas":
			# A hand of four still joined at the crown, spotted the way fruit is by the time it
			# reaches a rig. Two segments per finger so each one carries a curve.
			for bn_i in range(4):
				var bn_z: float = -0.048 + bn_i * 0.032
				var bn_y: float = 0.032 + bn_i * 0.006
				var bn_a := _cyl(root, 0.023, 0.14, Color(0.88, 0.78, 0.24), Vector3(-0.055, bn_y, bn_z))
				bn_a.rotation.z = deg_to_rad(72)
				var bn_b := _cyl(root, 0.023, 0.14, Color(0.9, 0.8, 0.26), Vector3(0.055, bn_y, bn_z))
				bn_b.rotation.z = deg_to_rad(108)
			_box(root, Vector3(0.04, 0.05, 0.1), Color(0.42, 0.32, 0.18), Vector3(-0.115, 0.05, 0))    # crown
			for bn_s in range(3):
				_sph(root, 0.013, Color(0.36, 0.26, 0.14),
					Vector3(-0.05 + bn_s * 0.06, 0.06 + bn_s * 0.008, -0.02 + bn_s * 0.03),
					Vector3(1.0, 0.4, 1.0))                                                           # bruise spots
		"apple":
			_sph(root, 0.075, Color(0.68, 0.16, 0.13), Vector3(0, 0.072, 0), Vector3(1.0, 0.92, 1.0))
			_sph(root, 0.035, Color(0.44, 0.3, 0.18), Vector3(0.05, 0.085, 0.045), Vector3(1.0, 0.8, 0.35))
			var ap_stem := _box(root, Vector3(0.012, 0.055, 0.012), Color(0.35, 0.26, 0.16), Vector3(0, 0.155, 0))
			ap_stem.rotation.z = deg_to_rad(-12)
			var ap_leaf := _box(root, Vector3(0.055, 0.008, 0.028), Color(0.36, 0.55, 0.26), Vector3(0.04, 0.16, 0.01))
			ap_leaf.rotation.y = deg_to_rad(22)
			ap_leaf.rotation.z = deg_to_rad(-14)
		"avocado":
			# A whole one with a cut half beside it: the big brown stone is the only thing that
			# says avocado instantly, and the pear silhouette keeps it clear of the apple.
			_sph(root, 0.062, Color(0.2, 0.28, 0.14), Vector3(-0.07, 0.062, 0), Vector3(1.0, 1.1, 1.0))
			_sph(root, 0.042, Color(0.22, 0.3, 0.15), Vector3(-0.07, 0.14, 0), Vector3(1.0, 1.0, 1.0))
			_cyl(root, 0.012, 0.03, Color(0.4, 0.32, 0.2), Vector3(-0.07, 0.185, 0))                   # stem nub
			_sph(root, 0.058, Color(0.2, 0.28, 0.14), Vector3(0.09, 0.03, 0), Vector3(1.0, 0.55, 1.0))
			_cyl(root, 0.052, 0.012, Color(0.78, 0.82, 0.45), Vector3(0.09, 0.06, 0))                  # cut flesh
			_sph(root, 0.026, Color(0.46, 0.3, 0.15), Vector3(0.09, 0.068, 0), Vector3(1.0, 0.8, 1.0))  # stone
		"burger_buns":
			# Two halves stacked, the crown domed and seeded, a dark cut line between them so
			# the stack reads as TWO buns rather than one pale drum. Nothing in between.
			_cyl(root, 0.085, 0.035, Color(0.76, 0.58, 0.34), Vector3(0, 0.018, 0))
			_cyl(root, 0.083, 0.01, Color(0.46, 0.33, 0.18), Vector3(0, 0.04, 0))                       # cut line
			_cyl(root, 0.086, 0.03, Color(0.86, 0.72, 0.5), Vector3(0, 0.058, 0))
			# Z-FIGHT FIX, 2026-07-27: the dome used to be radius 0.086 centred at y 0.07 —
			# EXACTLY the crown cylinder's radius, and its equator sits inside the cylinder's
			# 0.043..0.073 span, so the two curved surfaces were coincident over a full band
			# and the crown shimmered/flickered as the camera moved (the "glitching" item).
			# Nothing else in the file shares a radius between a _cyl and a _sph. Pulled 4 mm
			# inside the crown and lifted 2 mm, which also gives the bun a real shoulder.
			_sph(root, 0.082, Color(0.84, 0.63, 0.32), Vector3(0, 0.072, 0), Vector3(1.0, 0.5, 1.0))
			for bb_i in range(3):
				var bb_a: float = bb_i * TAU / 3.0
				_sph(root, 0.008, Color(0.94, 0.9, 0.76),
					Vector3(cos(bb_a) * 0.04, 0.106, sin(bb_a) * 0.04), Vector3(1.6, 0.6, 1.0))
		"lemon":
			# Long axis and a nipple at each end — the shape does the work here, the yellow
			# only confirms it.
			_sph(root, 0.05, Color(0.92, 0.83, 0.16), Vector3(0, 0.05, 0), Vector3(1.55, 1.0, 1.0))
			var lm_a := _cone(root, 0.02, 0.003, 0.032, Color(0.88, 0.79, 0.15), Vector3(0.085, 0.05, 0))
			lm_a.rotation.z = deg_to_rad(-90)
			var lm_b := _cone(root, 0.02, 0.003, 0.032, Color(0.88, 0.79, 0.15), Vector3(-0.085, 0.05, 0))
			lm_b.rotation.z = deg_to_rad(90)
			_sph(root, 0.01, Color(0.42, 0.5, 0.22), Vector3(-0.098, 0.05, 0), Vector3(1.0, 1.0, 1.0))
		"chocolate_cake":
			# Somebody's birthday, still under the galley cloche. The candle is the whole read:
			# a dark round without it is a tin.
			_cyl(root, 0.13, 0.085, Color(0.29, 0.17, 0.11), Vector3(0, 0.043, 0))
			_cyl(root, 0.135, 0.025, Color(0.36, 0.21, 0.13), Vector3(0, 0.097, 0))                    # frosting
			for ck_i in range(4):
				var ck_a: float = ck_i * TAU / 4.0
				_sph(root, 0.02, Color(0.52, 0.34, 0.2),
					Vector3(cos(ck_a) * 0.095, 0.112, sin(ck_a) * 0.095), Vector3(1.0, 0.7, 1.0))      # rosettes
			_cyl(root, 0.009, 0.09, Color(0.9, 0.88, 0.8), Vector3(0, 0.155, 0))                       # candle
			_sph(root, 0.016, Color(1.0, 0.74, 0.28), Vector3(0, 0.212, 0), Vector3(0.7, 1.5, 0.7), true, 1.8)
		"cheese_wedge":
			# A triangle laid flat on its side, rind on the wide back, two eyes in the paste.
			var ch_w := _prism(root, Vector3(0.26, 0.2, 0.07), Color(0.9, 0.76, 0.34), Vector3(0, 0.035, 0))
			ch_w.rotation.x = deg_to_rad(-90)
			_box(root, Vector3(0.26, 0.07, 0.016), Color(0.82, 0.56, 0.22), Vector3(0, 0.035, 0.105))  # rind
			_sph(root, 0.018, Color(0.72, 0.58, 0.22), Vector3(0.02, 0.066, 0.02), Vector3(1.0, 0.5, 1.0))
			_sph(root, 0.013, Color(0.72, 0.58, 0.22), Vector3(-0.06, 0.066, 0.05), Vector3(1.0, 0.5, 1.0))
		"ration_tin":
			# Flat, wide, opened by the ring — the pull tab is what separates it from the tall
			# galley cans. The lid sits INSIDE the crimp: three discs of the same radius
			# photographed as a stack of plates.
			_cyl(root, 0.115, 0.055, Color(0.6, 0.62, 0.64), Vector3(0, 0.028, 0))
			_cyl(root, 0.118, 0.028, Color(0.42, 0.4, 0.32), Vector3(0, 0.026, 0))                     # label band
			_cyl(root, 0.098, 0.014, Color(0.72, 0.74, 0.76), Vector3(0, 0.062, 0))                    # lid, recessed
			_torus(root, 0.008, 0.038, Color(0.76, 0.78, 0.8), Vector3(0.03, 0.074, 0))                # pull ring
			_box(root, Vector3(0.02, 0.006, 0.012), Color(0.76, 0.78, 0.8), Vector3(-0.01, 0.072, 0))  # tab
		"long_life_ration":
			# A vacuum brick in olive foil, crimped at both ends, one printed stripe.
			_box(root, Vector3(0.2, 0.075, 0.14), Color(0.42, 0.44, 0.3), Vector3(0, 0.04, 0))
			for lr_x in [-0.105, 0.105]:
				_box(root, Vector3(0.022, 0.055, 0.15), Color(0.55, 0.56, 0.44), Vector3(lr_x, 0.04, 0))
			_box(root, Vector3(0.202, 0.018, 0.142), Color(0.6, 0.2, 0.14), Vector3(0, 0.052, 0))       # print stripe
			_box(root, Vector3(0.07, 0.006, 0.05), Color(0.78, 0.79, 0.7), Vector3(-0.04, 0.079, 0))    # stencil block
		"wine_bottle":
			# Tall, dark green, foil at the neck: nothing like the pale salvaged bottle it
			# shares a shelf with.
			_cyl(root, 0.055, 0.22, Color(0.09, 0.19, 0.12), Vector3(0, 0.11, 0))
			_cone(root, 0.055, 0.022, 0.07, Color(0.09, 0.19, 0.12), Vector3(0, 0.255, 0))              # shoulder
			_cyl(root, 0.022, 0.09, Color(0.09, 0.19, 0.12), Vector3(0, 0.335, 0))                      # neck
			_cyl(root, 0.026, 0.05, Color(0.38, 0.09, 0.11), Vector3(0, 0.36, 0))                        # foil capsule
			_cyl(root, 0.057, 0.09, Color(0.84, 0.8, 0.7), Vector3(0, 0.1, 0))                           # label
		"water_jug":
			# The galley's gallon: a moulded jug with a waisted grip, a loop handle and a blue
			# screw cap, full enough that the fill line shows up near the shoulder.
			_box(root, Vector3(0.2, 0.24, 0.16), Color(0.72, 0.82, 0.85), Vector3(0, 0.12, 0))
			_box(root, Vector3(0.205, 0.03, 0.165), Color(0.62, 0.74, 0.78), Vector3(0, 0.11, 0))        # waist groove
			_box(root, Vector3(0.202, 0.012, 0.162), Color(0.5, 0.68, 0.72), Vector3(0, 0.21, 0))        # fill line
			_box(root, Vector3(0.11, 0.05, 0.1), Color(0.74, 0.84, 0.86), Vector3(0, 0.265, 0))          # shoulder
			_cyl(root, 0.035, 0.04, Color(0.72, 0.82, 0.85), Vector3(0, 0.305, 0))                       # neck
			_cyl(root, 0.042, 0.035, Color(0.2, 0.42, 0.62), Vector3(0, 0.33, 0))                        # cap
			var wj_h := _torus(root, 0.012, 0.055, Color(0.74, 0.84, 0.86), Vector3(0.13, 0.21, 0))
			wj_h.rotation.x = 0.0                                                                        # loop handle

		# ---- FLAT-PACK KITS: pre-fab parts, strapped, waiting for a deck ----
		# Same language as the kits above (bundled plates and a rope strap), told apart by the
		# one part that shows what unfolds: a bin lid, a door leaf, tread plate, glass.
		"storage_bin_kit":
			# The bin's spare walls folded flat, with the tote itself sitting on top OPEN. A
			# lidded stack of plates is what every other kit in this list looks like; four low
			# walls and a floor you can see into is the one thing that says "container".
			var sb_a := _box(root, Vector3(0.44, 0.05, 0.34), Color(0.4, 0.45, 0.48), Vector3(0, 0.025, 0))
			sb_a.rotation.y = deg_to_rad(6)
			var sb_b := _box(root, Vector3(0.42, 0.05, 0.32), Color(0.44, 0.48, 0.5), Vector3(0.01, 0.075, 0.01))
			sb_b.rotation.y = deg_to_rad(-7)
			_box(root, Vector3(0.36, 0.025, 0.26), Color(0.3, 0.34, 0.38), Vector3(0, 0.113, 0))          # bin floor
			for sb_z in [-0.125, 0.125]:
				_box(root, Vector3(0.36, 0.09, 0.022), Color(0.36, 0.4, 0.44), Vector3(0, 0.16, sb_z))
			for sb_x in [-0.175, 0.175]:
				_box(root, Vector3(0.022, 0.09, 0.26), Color(0.36, 0.4, 0.44), Vector3(sb_x, 0.16, 0))
			for sb_l in [-0.19, 0.19]:
				_box(root, Vector3(0.05, 0.025, 0.07), Color(0.5, 0.52, 0.55), Vector3(sb_l, 0.19, 0))    # handle lugs
			_box(root, Vector3(0.05, 0.18, 0.36), Color(0.74, 0.67, 0.5), Vector3(0.06, 0.08, 0))         # strap
		"door_kit":
			# The leaf itself, face up, panels routed, handle already hung on it.
			var dk_leaf := _box(root, Vector3(0.5, 0.055, 0.3), Color(0.5, 0.4, 0.28), Vector3(0, 0.028, 0))
			dk_leaf.rotation.y = deg_to_rad(4)
			for dk_x in [-0.12, 0.12]:
				_box(root, Vector3(0.2, 0.016, 0.2), Color(0.42, 0.33, 0.22), Vector3(dk_x, 0.062, 0))
			_sph(root, 0.022, Color(0.7, 0.56, 0.26), Vector3(0.2, 0.072, 0.09), Vector3(1.0, 0.8, 1.0))
			for dk_z in [-0.11, 0.11]:
				_box(root, Vector3(0.06, 0.02, 0.035), Color(0.34, 0.35, 0.38), Vector3(-0.23, 0.065, dk_z))
			_box(root, Vector3(0.05, 0.12, 0.32), Color(0.74, 0.67, 0.5), Vector3(-0.05, 0.03, 0))        # strap
		"floor_panel_kit":
			# Two lengths of tread plate, one already rusting. The top face wears the diamond
			# pattern rather than straight ribs: parallel ribs on a brown-ish plate read as
			# planks, and the walkway kit three entries up is already planks.
			var fp_a := _box(root, Vector3(0.5, 0.035, 0.4), Color(0.4, 0.42, 0.45), Vector3(0, 0.018, 0))
			fp_a.rotation.y = deg_to_rad(5)
			var fp_b := _box(root, Vector3(0.48, 0.035, 0.38), Color(0.46, 0.4, 0.34), Vector3(0.01, 0.056, 0.01))
			fp_b.rotation.y = deg_to_rad(-6)
			for fp_i in range(6):
				var fp_d := _box(root, Vector3(0.13, 0.012, 0.02), Color(0.56, 0.58, 0.6),
					Vector3(-0.12 + (fp_i % 3) * 0.13, 0.079, -0.07 + floori(fp_i / 3) * 0.14))
				fp_d.rotation.y = deg_to_rad(38 if fp_i % 2 == 0 else -38)                                # diamond tread
			for fp_x in [-0.21, 0.21]:
				_box(root, Vector3(0.035, 0.02, 0.035), Color(0.3, 0.31, 0.34), Vector3(fp_x, 0.086, 0.14))
			_box(root, Vector3(0.05, 0.11, 0.42), Color(0.74, 0.67, 0.5), Vector3(-0.08, 0.045, 0))        # strap
		"window_panel_kit":
			# Frame and glazing travelling together: the pane laid inside its own steel surround
			# with a coil of rubber seal on the corner.
			_box(root, Vector3(0.42, 0.03, 0.3), Color(0.36, 0.37, 0.4), Vector3(0, 0.015, 0))             # backing plate
			_box(root, Vector3(0.36, 0.014, 0.24), Color(0.7, 0.8, 0.82), Vector3(0, 0.055, 0))            # pane
			for wp_z in [-0.135, 0.135]:
				_box(root, Vector3(0.42, 0.032, 0.03), Color(0.44, 0.45, 0.48), Vector3(0, 0.05, wp_z))
			for wp_x in [-0.195, 0.195]:
				_box(root, Vector3(0.03, 0.032, 0.24), Color(0.44, 0.45, 0.48), Vector3(wp_x, 0.05, 0))
			_torus(root, 0.012, 0.05, Color(0.16, 0.16, 0.17), Vector3(0.13, 0.078, 0.05))                 # seal coil
			_box(root, Vector3(0.045, 0.11, 0.34), Color(0.74, 0.67, 0.5), Vector3(-0.09, 0.05, 0))        # strap

		# ---- VESSELS: the same bottle and flask the rain catcher stands in its cradle ----
		"bottle_empty":
			vessel_bottle(root, false)
		"bottle_water":
			vessel_bottle(root, true)
		"thermos_empty":
			vessel_flask(root, false)
		"thermos_water":
			vessel_flask(root, true)

		# ---- MEDICAL & BREWS: what you take when the rig has taken something ----
		"bandage":
			# A rolled dressing on its side with the tail hanging off it, paper band still on.
			var bd_roll := _cyl(root, 0.06, 0.08, Color(0.9, 0.88, 0.82), Vector3(0, 0.06, 0))
			bd_roll.rotation.z = deg_to_rad(90)
			var bd_core := _cyl(root, 0.018, 0.082, Color(0.6, 0.58, 0.53), Vector3(0, 0.06, 0))
			bd_core.rotation.z = deg_to_rad(90)
			var bd_band := _cyl(root, 0.062, 0.024, Color(0.62, 0.68, 0.7), Vector3(0.01, 0.06, 0))
			bd_band.rotation.z = deg_to_rad(90)
			var bd_tail := _box(root, Vector3(0.13, 0.01, 0.075), Color(0.88, 0.86, 0.8), Vector3(0.11, 0.035, 0))
			bd_tail.rotation.z = deg_to_rad(-24)
			_box(root, Vector3(0.06, 0.01, 0.07), Color(0.84, 0.82, 0.76), Vector3(0.19, 0.008, 0.01))
		"medkit":
			# A hard case with a carry handle and the one marking nobody has to read.
			_box(root, Vector3(0.24, 0.14, 0.16), Color(0.84, 0.85, 0.81), Vector3(0, 0.07, 0))
			_box(root, Vector3(0.245, 0.012, 0.165), Color(0.3, 0.31, 0.34), Vector3(0, 0.108, 0))         # lid seam
			for mk_x in [-0.07, 0.07]:
				_box(root, Vector3(0.03, 0.024, 0.014), Color(0.5, 0.52, 0.55), Vector3(mk_x, 0.104, 0.082))
			var mk_h := _torus(root, 0.01, 0.048, Color(0.24, 0.25, 0.27), Vector3(0, 0.155, 0))
			mk_h.rotation.x = 0.0                                                                          # carry handle
			_box(root, Vector3(0.09, 0.026, 0.006), Color(0.74, 0.16, 0.13), Vector3(0, 0.06, 0.082))
			_box(root, Vector3(0.026, 0.09, 0.006), Color(0.74, 0.16, 0.13), Vector3(0, 0.06, 0.082))
		"bloom_tonic":
			# A small stoppered vial with the Bloom still lit inside it — the glow IS the label,
			# the same teal every bloom-lit thing on this rig wears.
			_cyl(root, 0.034, 0.1, Color(0.2, 0.9, 0.85), Vector3(0, 0.055, 0), true, 1.4)
			_cyl(root, 0.036, 0.012, Color(0.66, 0.72, 0.7), Vector3(0, 0.006, 0))                         # base
			_cone(root, 0.034, 0.017, 0.03, Color(0.66, 0.72, 0.7), Vector3(0, 0.12, 0))                   # shoulder
			_cyl(root, 0.017, 0.03, Color(0.66, 0.72, 0.7), Vector3(0, 0.15, 0))                           # neck
			_cyl(root, 0.019, 0.032, Color(0.45, 0.34, 0.2), Vector3(0, 0.178, 0))                         # cork
			_torus(root, 0.005, 0.026, Color(0.5, 0.14, 0.12), Vector3(0, 0.163, 0))                       # wax seal
			_box(root, Vector3(0.03, 0.024, 0.004), Color(0.8, 0.76, 0.66), Vector3(0.045, 0.135, 0))      # paper tag
		"kelp_brew":
			# A crew mug of it, hot: green enough to be suspicious, luminous enough to be kelp,
			# two thin wisps coming off the top.
			_cyl(root, 0.075, 0.11, Color(0.6, 0.63, 0.65), Vector3(0, 0.055, 0))
			_cyl(root, 0.078, 0.012, Color(0.42, 0.44, 0.46), Vector3(0, 0.005, 0))                        # foot
			_cyl(root, 0.08, 0.012, Color(0.72, 0.74, 0.76), Vector3(0, 0.1, 0))                           # rim
			# The brew sits PROUD of the rim. Level with it, the rim disc hid the one green
			# thing in the item and the mug photographed empty.
			_cyl(root, 0.072, 0.016, Color(0.3, 0.74, 0.38), Vector3(0, 0.112, 0), true, 0.9)
			var kb_h := _torus(root, 0.011, 0.045, Color(0.6, 0.63, 0.65), Vector3(0.095, 0.055, 0))
			kb_h.rotation.x = 0.0                                                                          # mug handle
			# Steam, kept thin and short: at box thickness the two wisps read as drinking
			# straws standing in the mug.
			for kb_i in range(2):
				var kb_w := _cyl(root, 0.005, 0.055, Color(0.84, 0.9, 0.88),
					Vector3(-0.022 + kb_i * 0.044, 0.15, 0.005))
				kb_w.rotation.z = deg_to_rad(-22 + kb_i * 44)
		"galley_stew":
			# The best meal on the rig: a flared bowl, thick with it, fish and kelp standing
			# proud of the surface, and the spoon left in.
			_cone(root, 0.075, 0.14, 0.09, Color(0.7, 0.68, 0.62), Vector3(0, 0.048, 0))
			_cyl(root, 0.055, 0.014, Color(0.56, 0.54, 0.48), Vector3(0, 0.007, 0))                        # foot
			_cyl(root, 0.125, 0.016, Color(0.5, 0.3, 0.14), Vector3(0, 0.086, 0))                          # stew
			var gs_f := _box(root, Vector3(0.055, 0.022, 0.038), Color(0.86, 0.76, 0.62), Vector3(0.03, 0.098, 0.01))
			gs_f.rotation.y = deg_to_rad(22)
			var gs_k := _box(root, Vector3(0.07, 0.012, 0.022), Color(0.32, 0.55, 0.3), Vector3(-0.04, 0.096, 0.03))
			gs_k.rotation.y = deg_to_rad(-38)
			_sph(root, 0.016, Color(0.66, 0.42, 0.2), Vector3(-0.01, 0.096, -0.05), Vector3(1.0, 0.6, 1.0))
			var gs_sh := _box(root, Vector3(0.16, 0.012, 0.018), Color(0.7, 0.72, 0.75), Vector3(0.085, 0.15, -0.02))
			gs_sh.rotation.z = deg_to_rad(28)
			_sph(root, 0.022, Color(0.7, 0.72, 0.75), Vector3(0.015, 0.11, -0.02), Vector3(1.2, 0.4, 1.0))  # spoon bowl

		# ---- WHAT THE WATER GIVES UP TO A KNIFE ----
		"crab_leg", "crab_leg_seared":
			# Owner call, 2026-07-27: rebuilt as plain BLOCKS/TRIANGLES (box + prism, no
			# cylinders/spheres/cones) — cheaper to render at icon size and it reads just as
			# clearly as a leg, since a real crab leg IS a tapered, faceted, jointed rod.
			# Same shape for both; the pan reddens the shell and blacks the joints, matching
			# the crab's own carapace in _crab_shape.
			var cl_hot: bool = item_id.ends_with("_seared")
			var cl_sh: Color = Color(0.78, 0.3, 0.16) if cl_hot else Color(0.62, 0.38, 0.28)
			var cl_jt: Color = Color(0.3, 0.16, 0.1) if cl_hot else Color(0.5, 0.3, 0.22)
			# Two straight segments meeting at a knuckle, bent like a real walking leg —
			# femur out and down, tibia back in and down to a point.
			var cl_a := _box(root, Vector3(0.19, 0.05, 0.045), cl_sh, Vector3(-0.09, 0.065, 0))
			cl_a.rotation.z = deg_to_rad(24)
			_box(root, Vector3(0.05, 0.05, 0.05), cl_jt, Vector3(-0.005, 0.09, 0))          # knuckle
			var cl_b := _box(root, Vector3(0.17, 0.04, 0.035), cl_sh, Vector3(0.08, 0.055, 0))
			cl_b.rotation.z = deg_to_rad(-58)
			# The pointed dactyl tip — a prism tapering to an edge, not a smooth cone.
			var cl_t := _prism(root, Vector3(0.09, 0.03, 0.024), cl_sh.darkened(0.15), Vector3(0.175, 0.005, 0))
			cl_t.rotation.z = deg_to_rad(-58)
			for cl_i in range(2):
				var cl_bd := _box(root, Vector3(0.03, 0.052, 0.05), cl_jt, Vector3(-0.13 + cl_i * 0.06, 0.075 + cl_i * 0.01, 0))
				cl_bd.rotation.z = deg_to_rad(24)                                            # shell bands
		"glow_mucus":
			# A handful of live slime, still lit. Low and spreading — nothing else in the pack
			# is a puddle, which is the whole point next to the glow worm's cube.
			_cyl(root, 0.13, 0.012, Color(0.16, 0.6, 0.58), Vector3(0, 0.006, 0), true, 0.5)
			_sph(root, 0.085, Color(0.3, 0.95, 0.85), Vector3(0, 0.035, 0), Vector3(1.0, 0.5, 1.0), true, 1.0)
			_sph(root, 0.05, Color(0.35, 0.98, 0.88), Vector3(0.07, 0.03, 0.04), Vector3(1.0, 0.55, 1.0), true, 1.0)
			for gm_i in range(3):
				var gm_a: float = gm_i * TAU / 3.0 + 0.4
				var gm_s := _cyl(root, 0.008, 0.07, Color(0.3, 0.95, 0.85),
					Vector3(cos(gm_a) * 0.06, 0.055, sin(gm_a) * 0.06), true, 0.8)
				gm_s.rotation.z = deg_to_rad(-18 + gm_i * 18)                                              # ropy strands
		"limpet_shell":
			# The cone off a prised limpet: ribbed outside, dark nacre under the rim.
			_cone(root, 0.11, 0.014, 0.1, Color(0.74, 0.7, 0.62), Vector3(0, 0.05, 0))
			_torus(root, 0.006, 0.1, Color(0.66, 0.62, 0.55), Vector3(0, 0.022, 0))                        # growth ridge
			_torus(root, 0.005, 0.07, Color(0.7, 0.66, 0.58), Vector3(0, 0.055, 0))
			_cyl(root, 0.1, 0.012, Color(0.3, 0.32, 0.34), Vector3(0, 0.008, 0))                           # nacre floor
			_box(root, Vector3(0.05, 0.012, 0.04), Color(0.82, 0.8, 0.74), Vector3(0.06, 0.028, 0.04))     # chipped rim
		_:
			# Owner call, 2026-07-27: this used to build a flat yellow 0.28 m BoxMesh —
			# a blank untextured cube with no mesh and no texture, sitting on a deck full
			# of authored props. An id with no entry in the table above is an AUTHORING
			# BUG, and a placeholder cube hides that bug behind something that merely
			# looks bad; drawing nothing surfaces it and guarantees no blank square can
			# reach the world from a code path nobody audited.
			#
			# Verified safe before the change: every one of the 167 ids in data/items.json
			# has a case above (or is a species fish handled by the early-out), every
			# recipes.json `makes`/`needs`/`tool` id resolves to one of those, and no
			# literal id spawned anywhere in scripts/ falls outside items.json — so no
			# obtainable, craftable or quest item can land here. ui/item_icons.gd already
			# documents and handles the empty-node case ("an unknown id yields an empty
			# node ... which the AABB check turns into 'no art'"), and
			# player_controller._normalize_hand_visual bails on `not found`.
			_warn_unregistered(item_id)
	return root

## One push_warning per unknown id per run — an item with no registered mesh is a data
## or authoring error worth seeing in the log, but a Takeable rebuilt every time it is
## picked up, dropped and re-rendered for its icon must not spam it.
static var _unregistered: Dictionary = {}

static func _warn_unregistered(item_id: String) -> void:
	if _unregistered.has(item_id):
		return
	_unregistered[item_id] = true
	push_warning("ItemVisual: no mesh registered for item id '%s' — drawing nothing. "
		% item_id + "Add a case to ItemVisual.build().")

# ---- vessels, shared with the rain catcher ----

## The salvaged glass bottle: shoulder, tapered neck, driftwood bung, a rope collar where a
## hand goes, and — when it holds anything — a water column on its OWN pivot, because
## scaling the pivot raises the surface off the bottle floor while scaling the mesh would
## stretch it about its middle and sink it through the base. Returns that pivot (null when
## the bottle is dry) so the catcher can drive the fill with it.
##
## Owner call, 2026-07-26: this geometry used to live only in rain_catcher.gd, so the four
## vessel items were anonymous cubes in the pack while the identical bottle stood in a
## cradle three metres away. It lives here and the catcher calls it, because the bottle you
## photograph for an icon and the bottle you watch fill on deck must not drift apart.
static func vessel_bottle(root: Node3D, filled: bool) -> Node3D:
	var glass: Material = MatLib.glass(Color(0.60, 0.68, 0.62))
	var bung: Material = MatLib.weathered_wood()
	var collar: Material = MatLib.rope_mat()
	SL.cyl(root, Vector3(0, 0.11, 0), 0.045, 0.22, glass)
	SL.cyl(root, Vector3(0, 0.245, 0), 0.045, 0.05, glass, false, Vector3.ZERO, 0.020)
	SL.cyl(root, Vector3(0, 0.285, 0), 0.020, 0.04, glass)
	SL.cyl(root, Vector3(0, 0.315, 0), 0.022, 0.035, bung)
	SL.cyl(root, Vector3(0, 0.20, 0), 0.048, 0.02, collar)
	if not filled:
		return null
	var pivot := Node3D.new()
	pivot.name = "WaterPivot"
	root.add_child(pivot)
	pivot.position = Vector3(0, 0.012, 0)
	SL.cyl(pivot, Vector3(0, 0.098, 0), 0.038, 0.196, SL.mat("water", false, 0.25))
	return pivot

## The crew vacuum flask: dented galvanised shell, dark screw cap, canvas carry straps.
## Opaque on purpose — a steel flask with a visible water line would be a lie about what a
## thermos is — so a FULL one says so the way a crew member would: cap off and upturned
## beside it as a cup, both brimming. The catcher draws its docked flask dry (filled=false)
## and lets the prompt carry the level, exactly as it did before this moved here.
static func vessel_flask(root: Node3D, filled: bool) -> void:
	var shell: Material = MatLib.galvanized()
	var cap: Material = MatLib.dark_metal()
	var strap: Material = MatLib.canvas(Color(0.44, 0.42, 0.37))
	SL.cyl(root, Vector3(0, 0.13, 0), 0.050, 0.26, shell)
	SL.cyl(root, Vector3(0, 0.245, 0), 0.054, 0.02, cap)
	SL.box(root, Vector3(0, 0.19, 0.055), Vector3(0.09, 0.02, 0.012), strap)
	SL.box(root, Vector3(0, 0.09, 0.055), Vector3(0.09, 0.02, 0.012), strap)
	if not filled:
		SL.cyl(root, Vector3(0, 0.283, 0), 0.052, 0.05, cap)
		return
	var water: Material = SL.mat("water", false, 0.25)
	SL.cyl(root, Vector3(0, 0.262, 0), 0.044, 0.012, water)      # brimming at the mouth
	SL.cyl(root, Vector3(0.095, 0.028, 0), 0.050, 0.055, cap)    # the cap, upturned as a cup
	SL.cyl(root, Vector3(0.095, 0.052, 0), 0.044, 0.012, water)

## True for raw fish ("fish_*") and per-species cooked meals ("cooked_fish_*"),
## but NOT the legacy generic "cooked_fish"/"cooked_fish_prime" (their own fillet cases).
##
## Owner call, 2026-07-27: NOT_SPECIES exists because this prefix test runs BEFORE the
## match statement and returns from build() on its own, so any id it claims can never
## reach its own case. `fish_bone` was claimed by the `fish_` prefix — which made the
## fully authored spine-and-ribs case below dead code and rendered a picked fish bone as
## a whole grey FISH (no glb and no FISH_TINT entry, so the plain default capsule). It is
## a crafting TOOL, not a species; it is excluded here so its real mesh is reached.
const NOT_SPECIES := {"fish_bone": true, "cooked_fish_prime": true}

static func _is_species_fish(id: String) -> bool:
	if NOT_SPECIES.has(id):
		return false
	return id.begins_with("fish_") or id.begins_with("cooked_fish_")

## Procedural fallback body for a fish species when no generated mesh is present.
## Crab / squid / prawn keep their distinctive shapes; everything else is the fish
## silhouette. Cooked reddens/browns the flesh the way a hot pan actually would.
static func _fish_body(root: Node3D, species: String, cooked: bool, size_mul: float) -> void:
	match species:
		"fish_stone_crab":
			_crab_shape(root, cooked)
			return
		"fish_inkwell_squid":
			_squid_shape(root, cooked)
			return
		"fish_gutter_prawn":
			_prawn_shape(root, cooked)
			return
	var tint: Color = FISH_TINT.get(species, Color(0.6, 0.65, 0.68))
	if cooked:
		tint = _seared(tint)
	_fish(root, tint, size_mul)

## Crush a species colour to a seared char grey-brown.
static func _seared(c: Color) -> Color:
	return Color(c.r * 0.45, c.g * 0.34, c.b * 0.24)

static func _crab_shape(root: Node3D, cooked: bool) -> void:
	var sh: Color = Color(0.7, 0.28, 0.16) if cooked else Color(0.6, 0.35, 0.25)   # boiled shell reddens
	var cl: Color = Color(0.74, 0.3, 0.18) if cooked else Color(0.65, 0.4, 0.28)
	_box(root, Vector3(0.3, 0.1, 0.24), sh, Vector3(0, 0.08, 0))                    # carapace
	_box(root, Vector3(0.1, 0.06, 0.14), cl, Vector3(-0.2, 0.07, 0.1))             # claws
	_box(root, Vector3(0.1, 0.06, 0.14), cl, Vector3(0.2, 0.07, 0.1))

static func _squid_shape(root: Node3D, cooked: bool) -> void:
	var mantle: Color = Color(0.6, 0.5, 0.42) if cooked else Color(0.45, 0.55, 0.6)  # grilled squid browns
	var tent: Color = Color(0.5, 0.4, 0.33) if cooked else Color(0.4, 0.5, 0.55)
	# A tapered mantle. Was a _cyl built with top_radius 0.001 and its bottom_radius patched
	# afterwards — a near-degenerate ring whose normals are undefined at the apex, which
	# shades as a flickering point under a moving light. _cone builds the same silhouette
	# with a real 6 mm top face and no post-hoc mesh surgery.
	_cone(root, 0.09, 0.006, 0.3, mantle, Vector3(0, 0.24, 0))
	for i in range(4):
		_box(root, Vector3(0.03, 0.14, 0.03), tent,
			Vector3(cos(i * TAU / 4) * 0.05, 0.05, sin(i * TAU / 4) * 0.05))
	if not cooked:
		_box(root, Vector3(0.06, 0.06, 0.06), Color(0.2, 0.9, 0.85), Vector3(0, 0.3, 0), true, 0.8)  # bio-glow

## A Bloom grub, raw or off the pan. Six body segments swept along a C-curve (each yawed
## to the tangent so they read as ONE animal rather than a row of beads — the same trick
## the croissant uses), a blunt head with two feeler stubs, and the lit gut showing as a
## thinner, brighter core between the rings. Cooking a Bloom animal puts the light out:
## the shell browns, the glow drops to a dull ember and the body curls tighter.
static func _glow_worm(root: Node3D, cooked: bool) -> void:
	var skin: Color = Color(0.42, 0.32, 0.2) if cooked else Color(0.36, 0.86, 0.8)
	var gut: Color = Color(0.62, 0.34, 0.14) if cooked else Color(0.2, 0.95, 0.88)
	var glow: float = 0.35 if cooked else 1.6
	var arc: float = 118.0 if cooked else 152.0     # the pan curls it tighter
	var rad: float = 0.085
	for i in range(6):
		var a: float = deg_to_rad(-arc * 0.5 + arc * (float(i) / 5.0))
		var taper: float = 0.036 - absf(float(i) - 1.6) * 0.0042
		var seg := _cyl(root, maxf(taper, 0.014), 0.05, skin,
			Vector3(cos(a) * rad, 0.038, sin(a) * rad), not cooked, glow * 0.35)
		seg.rotation = Vector3(deg_to_rad(90), -a, 0)
		# The gut: a narrower, brighter core riding inside the same segment.
		var core := _cyl(root, maxf(taper - 0.012, 0.006), 0.056, gut,
			Vector3(cos(a) * rad, 0.038, sin(a) * rad), true, glow)
		core.rotation = Vector3(deg_to_rad(90), -a, 0)
	# Head end: blunter than the tail, with a dark mouth and two short feelers.
	var ha: float = deg_to_rad(-arc * 0.5 - 16.0)
	var head_pos := Vector3(cos(ha) * rad, 0.04, sin(ha) * rad)
	_sph(root, 0.032, skin, head_pos, Vector3(1.0, 0.85, 1.0), not cooked, glow * 0.3)
	_sph(root, 0.012, Color(0.08, 0.09, 0.1), head_pos + Vector3(cos(ha) * 0.024, 0.004, sin(ha) * 0.024),
		Vector3(1.0, 0.7, 1.0))
	for f in [-1.0, 1.0]:
		var feel := _cyl(root, 0.005, 0.045, gut,
			head_pos + Vector3(cos(ha) * 0.03, 0.012, sin(ha) * 0.03 + f * 0.014), true, glow * 0.6)
		feel.rotation = Vector3(deg_to_rad(74), -ha, deg_to_rad(f * 22.0))
	# Tail: a short taper closing the curve off.
	var ta: float = deg_to_rad(arc * 0.5 + 13.0)
	var tail := _cone(root, 0.021, 0.004, 0.05, skin,
		Vector3(cos(ta) * rad, 0.036, sin(ta) * rad), not cooked, glow * 0.3)
	tail.rotation = Vector3(deg_to_rad(90), -ta, 0)

static func _prawn_shape(root: Node3D, cooked: bool) -> void:
	var a: Color = Color(0.85, 0.4, 0.3) if cooked else Color(0.75, 0.6, 0.55)      # prawns pink up
	var b: Color = Color(0.8, 0.35, 0.26) if cooked else Color(0.7, 0.55, 0.5)
	var seg := _box(root, Vector3(0.16, 0.05, 0.06), a, Vector3(0, 0.05, 0))
	seg.rotation.z = 0.3
	_box(root, Vector3(0.1, 0.04, 0.05), b, Vector3(0.1, 0.03, 0))

## One fish silhouette: tapered capsule body, prism tail, a dot of eye.
static func _fish(root: Node3D, tint: Color, size_mul: float = 1.0) -> void:
	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = _ext(0.06 * size_mul)
	# CapsuleMesh needs height >= 2 * radius or it silently degenerates to a sphere with a
	# pinched, flickering waist. The authored ratio (0.4 vs 0.12) is safe; the clamp is here
	# so a future FISH_SIZE entry can't quietly break every un-modelled species at once.
	bm.height = maxf(_ext(0.4 * size_mul), bm.radius * 2.0)
	bm.material = MatLib.flat(tint)
	body.mesh = bm
	body.rotation.z = deg_to_rad(90)
	root.add_child(body)
	body.position = Vector3(0, 0.08 * size_mul, 0)
	var tail := MeshInstance3D.new()
	var tm := PrismMesh.new()
	tm.size = Vector3(0.14, 0.02, 0.12) * size_mul
	tm.material = MatLib.flat(tint.darkened(0.25))
	tail.mesh = tm
	tail.rotation.z = deg_to_rad(90)
	root.add_child(tail)
	tail.position = Vector3(0.24 * size_mul, 0.08 * size_mul, 0)
	var eye := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = _ext(0.015 * size_mul)
	em.height = em.radius * 2.0
	em.material = MatLib.flat(Color(0.05, 0.05, 0.06))
	eye.mesh = em
	root.add_child(eye)
	eye.position = Vector3(-0.15 * size_mul, 0.1 * size_mul, 0.045 * size_mul)

# ============================ THE TWO FISHING TOOLS ============================
# Both cases in build() are here rather than inline, because they share four
# sub-assemblies (gimbal, grip, lever-drag reel, terminal tackle) and 12 colours: the
# rod and the deep rig have to read as ONE MAN'S KIT, and the only way that survives an
# edit to either is for the shared parts to be shared code. Ported verbatim from the
# owner-chosen options in tests/tool_options.gd (deep_winch = B, rod_wand = 3) so the
# geometry in the game is the geometry on the contact sheet the owner picked from.
#
# Triangle discipline: every _torus passes rings/ring_segments and every _cyl passes
# segments. Godot's defaults are 64x32 and 64, i.e. 4096 triangles for one guide ring —
# eight guides plus reel rims at the default tessellation is ~25k triangles inside a
# 74 px inventory slot, which is what those arguments exist to prevent.

## Shared palette. Pitched a little darker than a bare "gunmetal" would suggest for the
## big flat areas: a 0.30 m disc turned at the sun renders far lighter than a 30 mm tube
## does (measured off a render, not assumed), and a pale disc reads as plastic — the
## exact failure docs/AGENT_TRAPS.md names for generated assets.
const C_BLANK := Color(0.165, 0.175, 0.205)   ## graphite blank / box section
const C_GRIP := Color(0.13, 0.12, 0.11)       ## shrink-wrap rubber grip
const C_TAPE := Color(0.17, 0.16, 0.14)       ## friction tape
const C_METAL := Color(0.30, 0.32, 0.35)      ## gunmetal castings and weldments
const C_ALLOY := Color(0.40, 0.42, 0.45)      ## machined alloy, seats, guides
const C_BRASS := Color(0.42, 0.33, 0.20)      ## dull anodised levers
const C_WRAP := Color(0.32, 0.17, 0.14)       ## oxblood thread wraps
const C_LINE := Color(0.36, 0.34, 0.30)       ## salt-stiffened braid
const C_LEAD := Color(0.235, 0.245, 0.265)    ## dull cast lead
const C_SALT := Color(0.50, 0.51, 0.48)       ## salt crust / bare dragged steel
const C_RUST := Color(0.36, 0.25, 0.17)       ## rust in the seams
const C_BLOOM := Color(0.22, 0.92, 0.86)      ## a live Bloom cell as a lumo bead

## Plant the marker player_controller.hand_tip_world() looks up BY NAME. Lose it, or
## parent it to something that does not carry the tool's own lean, and the controller
## falls back SILENTLY to a guess along _hand_reach_axis — which anchors the fishing line
## inside the player's fist. tests/RodHandProbe.tscn asserts the two answers differ,
## which is the only thing that catches it, because nothing about it errors.
static func _hand_tip(host: Node3D, at: Vector3) -> void:
	var t := Node3D.new()
	t.name = "hand_tip"
	host.add_child(t)
	t.position = _pos(at)

## The notched cup that drops into a fighting belt — the part that says "this is braced
## against a body and cranked".
static func _tool_gimbal(h: Node3D, y: float, r: float) -> void:
	_cyl(h, r, 0.05, C_METAL, Vector3(0, y + 0.025, 0), false, 1.0, 16)
	for n in [-1.0, 1.0]:
		_box(h, Vector3(r * 0.48, 0.032, r * 0.9), C_METAL.darkened(0.18),
			Vector3(n * r * 0.66, y - 0.012, 0))
	_cyl(h, r * 0.9, 0.028, C_SALT, Vector3(0, y + 0.062, 0), false, 1.0, 16)

## A ribbed rubber grip you can hold in a wet glove: `ribs` tape laps AROUND a vertical
## shaft. The tape is a browner black than the blank, or the grip vanishes into it.
static func _tool_grip(h: Node3D, y0: float, len: float, r: float, ribs: int) -> void:
	_cyl(h, r, len, C_GRIP, Vector3(0, y0 + len * 0.5, 0), false, 1.0, 16)
	for i in range(ribs):
		var g := _torus(h, r - 0.002, r + 0.007, C_TAPE,
			Vector3(0, y0 + len * (float(i) + 0.5) / float(ribs), 0), 16, 6)
		g.rotation.x = 0.0

## Terminal tackle hove up short the way a hand-line is carried: swivel, three-way,
## torpedo lead, snooded hook, lumo bead. Hangs DOWN from `at`, in the plane z = at.z,
## scaled by `s`.
static func _tool_tackle(h: Node3D, at: Vector3, s: float) -> void:
	var x: float = at.x
	var z: float = at.z
	_cyl(h, 0.005 * s, 0.034 * s, C_LINE, Vector3(x, at.y - 0.018 * s, z), false, 1.0, 8)
	var sw := _torus(h, 0.007 * s, 0.013 * s, C_ALLOY, Vector3(x, at.y - 0.040 * s, z), 12, 6)
	sw.rotation.x = 0.0
	_box(h, Vector3(0.030, 0.016, 0.011) * s, C_ALLOY.darkened(0.12),
		Vector3(x, at.y - 0.056 * s, z))
	_cyl(h, 0.005 * s, 0.054 * s, C_LINE, Vector3(x, at.y - 0.090 * s, z), false, 1.0, 8)
	# 1.4 kg of cast torpedo — the heaviest single thing on the tool and the reason every
	# other part of it is built the way it is.
	_cone(h, 0.030 * s, 0.014 * s, 0.038 * s, C_LEAD, Vector3(x, at.y - 0.134 * s, z))
	_cyl(h, 0.030 * s, 0.056 * s, C_LEAD, Vector3(x, at.y - 0.181 * s, z), false, 1.0, 16)
	_cone(h, 0.010 * s, 0.030 * s, 0.040 * s, C_LEAD.darkened(0.10),
		Vector3(x, at.y - 0.228 * s, z))
	# Snood out to one side, then the hook. rotation.z sends a cylinder's +Y to
	# (-sin, cos), so 55.8° lays its axis along (-0.827, 0.562) — the trace from the
	# three-way out to the hook eye. (An earlier cut used 125°, which is not that line
	# nor its negation, and hung the hook off a snood pointing somewhere else.)
	var sn := _cyl(h, 0.004 * s, 0.091 * s, C_LINE,
		Vector3(x + 0.038 * s, at.y - 0.083 * s, z), false, 1.0, 8)
	sn.rotation.z = deg_to_rad(55.8)
	var he := _torus(h, 0.006 * s, 0.011 * s, C_ALLOY,
		Vector3(x + 0.077 * s, at.y - 0.111 * s, z), 12, 6)
	he.rotation.x = 0.0
	_cyl(h, 0.005 * s, 0.048 * s, C_ALLOY, Vector3(x + 0.081 * s, at.y - 0.137 * s, z),
		false, 1.0, 8)
	var b1 := _box(h, Vector3(0.010, 0.022, 0.009) * s, C_ALLOY,
		Vector3(x + 0.083 * s, at.y - 0.169 * s, z))
	b1.rotation.z = deg_to_rad(30)
	var b2 := _box(h, Vector3(0.010, 0.022, 0.009) * s, C_ALLOY,
		Vector3(x + 0.068 * s, at.y - 0.182 * s, z))
	b2.rotation.z = deg_to_rad(72)
	var pt := _cyl(h, 0.004 * s, 0.026 * s, C_ALLOY.lightened(0.10),
		Vector3(x + 0.053 * s, at.y - 0.170 * s, z), false, 1.0, 8)
	pt.rotation.z = deg_to_rad(-16)
	# A lumo bead above the hook — real deep-drop rigs run one, and in this ocean it is a
	# live Bloom cell. Emissive at 1.8, well over main.gd's 0.8 glow threshold.
	_sph(h, 0.009 * s, C_BLOOM, Vector3(x + 0.053 * s, at.y - 0.095 * s, z),
		Vector3.ONE, true, 1.8)

# ------------------------------- the deep rig: a deck winch -------------------------------

## OWNER PICK, option B. Not a rod: a winch you set down and crank, with the line leading
## over a hoop fairlead at the head.
##
## WHICH WAY IS FORWARD, and why this build answers it. Every other option is rod-shaped,
## so "the working end" is just the far end of a stick. This one is a machine, so the line
## exit is a specific part in a specific place: the HOOP at (0.168, 1.012), out on the
## boom, at the top. The drum's axis runs ACROSS the tool (local Z) with the crank on +Z,
## which is the face turned toward the camera when it is held — so the drum is seen nearly
## flat-on and the crank, the ratchet and the bolt circle all read. Everything round on
## that axis is laid over with rotation.x = 90°. Stations are metres up the pivot's +Y
## from the foot plate at y = 0:
##   0.00 foot | 0.15-0.35 taped grip | 0.38-0.62 drum, crank, ratchet | 0.67-0.73 brake
##   | 0.07-0.97 mast + its diagonal | 0.98-1.02 head and boom | 1.012 HOOP FAIRLEAD
##   | 1.00-0.77 terminal tackle hanging under it.
static func _deep_winch(root: Node3D) -> void:
	var p := Node3D.new()
	root.add_child(p)
	# A small lean, not the rod's 14°: every degree also throws the top of a 1.13 m frame
	# sideways, and the wider the model's X the smaller player_controller's hand
	# normalisation (largest dimension -> 0.9 m) draws the whole tool.
	p.rotation.z = deg_to_rad(-4)
	# FOOT it stands on: tread plate, deck bolts, and one bare-steel edge where it is dragged.
	_box(p, Vector3(0.230, 0.028, 0.200), C_METAL, Vector3(0.005, 0.014, 0))
	_box(p, Vector3(0.240, 0.008, 0.210), C_RUST, Vector3(0.005, 0.004, 0))
	for b in [-1.0, 1.0]:
		_cyl(p, 0.018, 0.022, C_ALLOY, Vector3(-0.072, 0.034, b * 0.066), false, 1.0, 10)
	_box(p, Vector3(0.046, 0.014, 0.200), C_SALT, Vector3(0.100, 0.032, 0))
	_box(p, Vector3(0.086, 0.100, 0.120), C_METAL, Vector3(-0.004, 0.078, 0))   # heel boss
	# MAST and the grip you brace against a hip or a rail.
	_box(p, Vector3(0.070, 0.900, 0.070), C_BLANK, Vector3(0, 0.520, 0))
	_box(p, Vector3(0.056, 0.320, 0.010), C_RUST, Vector3(0, 0.480, -0.036))   # rust streak
	_tool_grip(p, 0.150, 0.200, 0.052, 4)
	# THE DRUM — one big one, lower on the frame than a rod's reel, so the crank falls where
	# a hand naturally goes when the foot is on a deck. Arbor wound with braid between two
	# flanged cheeks, on a bracket standing off the mast.
	var dc := Vector3(-0.180, 0.500, 0)
	for s in [-1.0, 1.0]:
		_box(p, Vector3(0.230, 0.078, 0.018), C_METAL, Vector3(-0.082, 0.500, s * 0.160))
	var barrel := _cyl(p, 0.096, 0.230, C_METAL.darkened(0.20), dc, false, 1.0, 18)
	barrel.rotation.x = deg_to_rad(90)
	var wound := _cyl(p, 0.152, 0.200, C_LINE, dc, false, 1.0, 18)
	wound.rotation.x = deg_to_rad(90)
	# Three dark rings AROUND the braid — the lay of the wind. A 5 mm tube at a 152 mm ring
	# radius, so these are groove lines on the surface of the line, not hoops standing off it.
	for g in [-0.060, 0.010, 0.068]:
		_torus(p, 0.149, 0.154, C_LINE.darkened(0.26), dc + Vector3(0, 0, g), 18, 6)
	# THE TWO CHEEKS ARE DIFFERENT SIZES, and that is what makes this read as a drum rather
	# than a bicycle wheel. Held in hand the tool's own +Z points within 27° of the camera,
	# so the near cheek is seen almost dead flat: at equal radii it hid the braid completely.
	# The DRIVE cheek (crank side, +Z) is 122 mm against the far cheek's 158, so the braid at
	# 152 always stands proud of it as a pale ring. Undersized drive cheeks are how real
	# hand-winches are built anyway — the gear train has to clear the flange.
	for s in [-1.0, 1.0]:
		var cr: float = 0.122 if s > 0.0 else 0.158
		var cheek := _cyl(p, cr, 0.018, C_METAL.darkened(0.16), dc + Vector3(0, 0, s * 0.108),
			false, 1.0, 22)
		cheek.rotation.x = deg_to_rad(90)
		# _torus already lies across the tool (rotation.x = 90°), which IS the drum's own
		# axis — the one place in this build where the default is the right one.
		_torus(p, cr - 0.005, cr + 0.009, C_METAL.darkened(0.36), dc + Vector3(0, 0, s * 0.119), 22, 8)
		var hub := _cyl(p, 0.036, 0.013, C_ALLOY.darkened(0.12), dc + Vector3(0, 0, s * 0.122),
			false, 1.0, 16)
		hub.rotation.x = deg_to_rad(90)
		# A painted band on each cheek, in the rod's own OXBLOOD. An earlier cut painted it
		# faded ochre and the drum came back a bright yellow disc — the wrong accent entirely
		# on a rig that has had blank yellow blocks taken off it twice.
		var band := _cyl(p, cr * 0.60, 0.004, C_WRAP, dc + Vector3(0, 0, s * 0.119), false, 1.0, 20)
		band.rotation.x = deg_to_rad(90)
		var ax := _cyl(p, 0.020, 0.090, C_ALLOY, dc + Vector3(0, 0, s * 0.150), false, 1.0, 12)
		ax.rotation.x = deg_to_rad(90)
	# Bolt circle through the drive cheek: the detail that turns a disc into a plate somebody
	# fitted, which is the whole difference between machinery and a wheel.
	for bo in range(6):
		var ba: float = bo * TAU / 6.0 + 0.3
		var blt := _cyl(p, 0.008, 0.010, C_ALLOY,
			dc + Vector3(cos(ba) * 0.094, sin(ba) * 0.094, 0.122), false, 1.0, 8)
		blt.rotation.x = deg_to_rad(90)
	# RATCHET AND PAWL — 45 m of wet line pulling on a drum has to be HELD, and this is the
	# mechanism data/items.json means by "LMB thumbs the drum to hold a depth".
	var gear := _cyl(p, 0.062, 0.013, C_ALLOY.darkened(0.14), dc + Vector3(0, 0, 0.186),
		false, 1.0, 18)
	gear.rotation.x = deg_to_rad(90)
	for t in range(6):
		var ta: float = t * TAU / 6.0
		_box(p, Vector3(0.017, 0.018, 0.012), C_ALLOY.darkened(0.24),
			dc + Vector3(cos(ta) * 0.066, sin(ta) * 0.066, 0.186))
	var pawl := _box(p, Vector3(0.092, 0.014, 0.011), C_BRASS, dc + Vector3(0.058, 0.052, 0.186))
	pawl.rotation.z = deg_to_rad(-18)
	# CRANK — offset arm and a fist knob. The only way line comes back up 45 m. The arm is
	# the lighter alloy, not the frame's gunmetal: a dark bar on a dark drum disappears from
	# every angle that matters.
	var boss := _cyl(p, 0.025, 0.030, C_ALLOY, dc + Vector3(0, 0, 0.212), false, 1.0, 14)
	boss.rotation.x = deg_to_rad(90)
	var arm := _box(p, Vector3(0.175, 0.030, 0.017), C_ALLOY, dc + Vector3(0.058, -0.058, 0.234))
	arm.rotation.z = deg_to_rad(-45)
	var knob := _cyl(p, 0.023, 0.062, C_GRIP.lightened(0.09),
		dc + Vector3(0.116, -0.116, 0.234), false, 1.0, 14)
	knob.rotation.x = deg_to_rad(90)
	# BRAKE — a shoe on a lever pressed down onto the drum rim: what stops a 1.4 kg lead
	# running away with the whole spool on the way down.
	var shoe := _box(p, Vector3(0.120, 0.022, 0.210), C_BRASS.darkened(0.42),
		Vector3(-0.192, 0.672, 0))
	shoe.rotation.z = deg_to_rad(9)
	var blev := _box(p, Vector3(0.215, 0.024, 0.022), C_BRASS.darkened(0.14),
		Vector3(-0.088, 0.706, 0.070))
	blev.rotation.z = deg_to_rad(15)
	var bpin := _cyl(p, 0.011, 0.030, C_ALLOY, Vector3(0.018, 0.734, 0.070), false, 1.0, 10)
	bpin.rotation.x = deg_to_rad(90)
	# ONE DIAGONAL, and a bent HOOP fairlead at the head instead of a block. That hoop is
	# the whole simplification the owner picked this option for: the line leaves the tool
	# over one loop of round bar, and there is exactly one place it can leave from.
	var st := _box(p, Vector3(0.026, 0.640, 0.024), C_METAL, Vector3(0.090, 0.640, 0))
	st.rotation.z = deg_to_rad(-11)
	_box(p, Vector3(0.052, 0.070, 0.028), C_METAL.darkened(0.12), Vector3(0.038, 0.336, 0))
	_box(p, Vector3(0.078, 0.062, 0.078), C_METAL, Vector3(0.004, 0.980, 0))
	var boom := _box(p, Vector3(0.170, 0.032, 0.038), C_METAL, Vector3(0.082, 1.000, 0))
	boom.rotation.z = deg_to_rad(11)
	var hoop := _torus(p, 0.026, 0.036, C_ALLOY, Vector3(0.168, 1.012, 0), 18, 8)
	hoop.rotation.x = 0.0                                   # laid flat: the line drops through it
	# THE TACKLE GOES IN A NAMED, HIDEABLE NODE. It is hove up short under the fairlead because
	# that is how a hand-line is carried between drops — but fishing_rod.gd spawns its OWN lead
	# for a cast, so while a line is out this copy would be the SECOND lead on screen (owner,
	# 2026-07-29: "there is a hook and bobber in the 3-d model too already"). The name is the
	# contract: player_controller._show_stowed_tackle() finds it by name and hides it for the
	# duration of a cast, the same way hand_tip_world() finds "hand_tip".
	var stowed := Node3D.new()
	stowed.name = "stowed_tackle"
	p.add_child(stowed)
	# THE NODE SITS AT THE HANG POINT, not at the winch's foot, and the tackle is built at its
	# local origin. player_controller._hang_stowed_tackle() rotates this node to world down
	# every frame so the lead and the hook always fall straight (owner: "the weight/hook points
	# down"); with the geometry offset a metre up inside it, that rotation would have swung the
	# tackle around the foot plate instead of standing it up.
	stowed.position = Vector3(0.168, 1.000, 0)
	_tool_tackle(stowed, Vector3.ZERO, 0.95)
	# THE LINE LEAVES HERE, at the hoop — not at the fist. A child of the winch pivot so it
	# inherits the lean and position for free.
	_hand_tip(p, Vector3(0.168, 1.008, 0))
	# ...AND THEN THE WHOLE MACHINE IS MIRRORED. See _mirror_x. Everything above is written in
	# the ORIGINAL hand (drum on -X, boom and hoop on +X) because that is the layout the
	# station table in the doc comment describes and the one four rendered candidates were
	# judged in; the flip is one line at the end rather than 40 negated literals.
	_mirror_x(p)

## MIRROR A BUILT SUB-TREE ABOUT ITS OWN X = 0 PLANE — the deck winch's handedness.
##
## Owner report, three times, 2026-07-29/30: "the deep sea rod still has the same problem…
## the 3-d model has the rig with the reel on the LEFT and rod curving away to the right, and
## that never changes. It should default hold/lean to the OTHER side."
##
## That is not a pose bug and no pose could fix it. With the mast on +Y and the drum bracket
## standing off on -X, the crank side (+Z) is fixed by the right-hand rule: hold the mast up
## and put the drum on the player's RIGHT and the crank necessarily swings AWAY from the
## camera, so the player sees the blank far cheek and the tool reads back-to-front. Asking for
## drum-right AND crank-toward-the-player AND mast-up needs a basis of determinant -1 — i.e.
## a MIRROR, which s22 recorded as impossible and which the owner has now explicitly asked for.
##
## Mirroring in X (rather than in Z, the other reflection that fixes the handedness) is the one
## that keeps the ICON: item_icons' camera looks in along (0.62, 0.55, 0.78), so a Z-mirror
## would hide the crank arm behind the drum and cost the silhouette the s22 contact sheet was
## judged on. An X-mirror moves the drum TOWARD that camera and leaves the crank where it is.
##
## It is done node-by-node instead of with `scale.x = -1` because a negative-determinant
## transform inverts triangle winding and back-face culling renders the model inside out.
## M·T1·T2·…·Tn == (M·T1·M)(M·T2·M)…(M·Tn·M)·M with M = diag(-1,1,1) and M² = I, so negating
## each node's local x-offset and its Y and Z Euler terms is an exact reflection at every
## level — every node keeps determinant +1 — and the trailing M lands on the LEAF MESH, where
## it is a no-op: every primitive this file builds (box, cylinder/cone about Y, torus about Y,
## sphere) is symmetric about its own x = 0.
static func _mirror_x(node: Node3D) -> void:
	node.position = Vector3(-node.position.x, node.position.y, node.position.z)
	var r: Vector3 = node.rotation
	node.rotation = Vector3(r.x, -r.y, -r.z)
	for c in node.get_children():
		if c is Node3D:
			_mirror_x(c as Node3D)

# --------------------------- the surface rod: option 3, the wand ---------------------------

## The rod's sections. Kept as a table rather than 20 literals because the four options on
## the contact sheet WERE this table with different numbers, and the owner picked one row:
## the finest. `len` is the whole rod; stations below are written in the original 1.90 m
## layout and scaled by len/1.90 so the proportions are the rod's, not the length's.
const ROD_WAND := {
	"len": 2.10, "butt": 0.019, "tip": 0.003, "grip": 0.031, "fore": 0.032, "seat": 0.037,
	"guides": 8, "gbig": 0.030, "gsml": 0.008, "reel_s": 0.84,
}

static func _rod_build(root: Node3D, q: Dictionary) -> void:
	var p := Node3D.new()
	root.add_child(p)
	p.rotation.z = deg_to_rad(14)
	var L: float = float(q["len"])
	var s: float = L / 1.90                       # station scale off the original layout
	var bt: float = float(q["butt"])
	var tp: float = float(q["tip"])
	var gr0: float = float(q["grip"])
	var sea: float = float(q["seat"])
	var rs: float = float(q["reel_s"])
	# Gimbal, butt grip, machined seat — all trimmed WITH the blank, so the whole rod is
	# finer rather than a thin stick carrying fat furniture. That was the owner's note.
	_tool_gimbal(p, 0.0, gr0 + 0.010)
	_cyl(p, gr0, 0.37 * s, C_GRIP, Vector3(0, 0.235 * s, 0), false, 1.0, 16)
	for i in range(4):
		var rib := _torus(p, gr0 - 0.002, gr0 + 0.006, C_TAPE,
			Vector3(0, (0.115 + i * 0.075) * s, 0), 16, 6)
		rib.rotation.x = 0.0                                            # rings AROUND the butt
	_cyl(p, sea, 0.18 * s, C_ALLOY.darkened(0.18), Vector3(0, 0.51 * s, 0), false, 1.0, 20)
	for l in [0.432, 0.588]:
		var lock := _torus(p, sea - 0.001, sea + 0.010, C_ALLOY.darkened(0.25),
			Vector3(0, l * s, 0), 16, 8)
		lock.rotation.x = 0.0                                           # knurled lock rings
	_rod_reel(p, Vector3(0.142 * rs / 0.95, 0.535 * s, 0), rs)
	# Foregrip you pull against, ferrule, then four stacked tapering blank sections, so the
	# taper actually reads instead of being one uniform stick.
	_cone(p, float(q["fore"]) + 0.004, float(q["fore"]) - 0.004, 0.30 * s, C_GRIP,
		Vector3(0, 0.75 * s, 0))
	for f in range(3):
		var fr := _torus(p, float(q["fore"]) - 0.005, float(q["fore"]) + 0.003, C_TAPE,
			Vector3(0, (0.655 + f * 0.085) * s, 0), 16, 6)
		fr.rotation.x = 0.0                                             # foregrip ribs
	_cyl(p, bt + 0.005, 0.02 * s, C_ALLOY, Vector3(0, 0.90 * s, 0), false, 1.0, 18)
	for seg in [[0.90, 1.20], [1.20, 1.48], [1.48, 1.72], [1.72, 1.90]]:
		var y0: float = float(seg[0])
		var y1: float = float(seg[1])
		_cone(p, _rod_blank_r(y0, bt, tp), _rod_blank_r(y1, bt, tp), (y1 - y0) * s,
			C_BLANK, Vector3(0, (y0 + y1) * 0.5 * s, 0))
	# Guides stepping down the blank — the thing that makes a rod read as a rod at a glance.
	# Each is a ring on a short standoff post over a wrapped thread binding, on the SAME side
	# as the reel, because that is where an overhead reel's line runs. Posts and wraps scale
	# with the ring so nothing is chunky on a fine blank.
	var n: int = int(q["guides"])
	for i in range(n):
		var t: float = float(i) / float(maxi(n - 1, 1))
		var gy: float = lerpf(1.00, 1.83, pow(t, 0.86))
		var gring: float = lerpf(float(q["gbig"]), float(q["gsml"]), pow(t, 0.75))
		var br: float = _rod_blank_r(gy, bt, tp)
		var post: float = 0.004 + gring * 0.22
		_cyl(p, br + 0.0025, 0.026 * s, C_WRAP, Vector3(0, gy * s, 0), false, 1.0, 14)
		_box(p, Vector3(post, 0.010, 0.010), C_METAL, Vector3(br + post * 0.5, gy * s, 0))
		var ring := _torus(p, gring, gring + 0.0045, C_ALLOY,
			Vector3(br + post + gring, gy * s, 0), 16, 8)
		ring.rotation.x = 0.0                                           # hole up the blank
	# Roller tip: the last bearing the line touches before it goes over the side.
	var tipy: float = 1.90 * s
	_sph(p, tp + 0.002, C_METAL, Vector3(0, tipy, 0))
	_box(p, Vector3(0.020, 0.010, 0.011), C_METAL, Vector3(0.010, tipy - 0.012 * s, 0))
	var tr := _torus(p, 0.008, 0.014, C_ALLOY, Vector3(0.020, tipy + 0.002, 0), 16, 8)
	tr.rotation.x = 0.0
	var rol := _cyl(p, 0.007, 0.008, C_ALLOY.lightened(0.12),
		Vector3(0.020, tipy - 0.012 * s, 0), false, 1.0, 10)
	rol.rotation.x = deg_to_rad(90)
	_hand_tip(p, Vector3(0.020, tipy, 0))

## Blank radius at station `y`, in the rod's own 0.90-1.90 station coordinates, linear from
## the ferrule to the tip. ONE function so a guide foot cannot drift off the blank the way
## hand-written per-guide radii did.
static func _rod_blank_r(y: float, bt: float, tp: float) -> float:
	return lerpf(bt, tp, clampf((y - 0.90) / 1.00, 0.0, 1.0))

## A lever-drag multiplier clamped ON TOP of the seat, where an overhead reel goes — the
## single part that says "offshore" at a glance, so it is built as a real one: two machined
## side plates, a wide braid spool between them, frame pillars, a thumb lever and an offset
## crank. Its axis runs ACROSS the rod (local Z), so every round part is laid over with
## rotation.x = 90°. `k` scales the whole reel so it can be trimmed with the blank while
## staying legible at 74 px, which is the one thing that must not shrink away.
static func _rod_reel(h: Node3D, at: Vector3, k: float) -> void:
	_box(h, Vector3(0.048, 0.032, 0.086) * k, C_METAL, at + Vector3(-0.075, -0.030, 0) * k)
	var spool := _cyl(h, 0.050 * k, 0.140 * k, C_LINE, at, false, 1.0, 18)
	spool.rotation.x = deg_to_rad(90)
	for s in [-1.0, 1.0]:
		var plate := _cyl(h, 0.078 * k, 0.017 * k, C_METAL, at + Vector3(0, 0, s * 0.081 * k),
			false, 1.0, 22)
		plate.rotation.x = deg_to_rad(90)
		_torus(h, 0.069 * k, 0.082 * k, C_METAL.darkened(0.25),
			at + Vector3(0, 0, s * 0.091 * k), 20, 8)
	for pl in range(3):
		var pa: float = pl * TAU / 3.0 + 0.6
		_box(h, Vector3(0.019, 0.019, 0.155) * k, C_METAL.darkened(0.12),
			at + Vector3(cos(pa) * 0.067, sin(pa) * 0.067, 0) * k)
	var cam := _cyl(h, 0.023 * k, 0.017 * k, C_BRASS.darkened(0.2),
		at + Vector3(0, 0, 0.096 * k), false, 1.0, 14)
	cam.rotation.x = deg_to_rad(90)
	var lever := _box(h, Vector3(0.090, 0.019, 0.014) * k, C_BRASS,
		at + Vector3(0.032, 0.034, 0.104) * k)
	lever.rotation.z = deg_to_rad(42)                                   # thumb lever, drag off
	var stub := _cyl(h, 0.013 * k, 0.052 * k, C_ALLOY, at + Vector3(0, 0, 0.120 * k),
		false, 1.0, 12)
	stub.rotation.x = deg_to_rad(90)
	var arm := _box(h, Vector3(0.134, 0.025, 0.015) * k, C_ALLOY,
		at + Vector3(0.041, -0.041, 0.149) * k)
	arm.rotation.z = deg_to_rad(-42)
	var knob := _cyl(h, 0.018 * k, 0.048 * k, C_GRIP.lightened(0.08),
		at + Vector3(0.084, -0.084, 0.149) * k, false, 1.0, 14)
	knob.rotation.x = deg_to_rad(90)


# ---- primitives ----

## Smallest dimension any part is allowed to have. A zero, negative or non-finite extent
## produces a mesh with a degenerate (or NaN) AABB, and a NaN AABB propagates: it poisons
## the merged bounds in player_controller._normalize_hand_visual and in ui/item_icons'
## framing camera, so ONE bad number makes the whole held item or its icon jump, invert or
## disappear. Every dimension goes through here so a typo can only ever cost a sliver of
## geometry instead of glitching the object it belongs to.
const MIN_EXTENT: float = 0.0005

static func _ext(v: float) -> float:
	if not is_finite(v):
		return MIN_EXTENT
	return maxf(v, MIN_EXTENT)

static func _ext3(v: Vector3) -> Vector3:
	return Vector3(_ext(v.x), _ext(v.y), _ext(v.z))

## A part's position must be finite too — a NaN position is a NaN world AABB even when the
## mesh itself is sound.
static func _pos(v: Vector3) -> Vector3:
	if is_finite(v.x) and is_finite(v.y) and is_finite(v.z):
		return v
	return Vector3.ZERO

static func _box(root: Node3D, size: Vector3, color: Color, pos: Vector3,
		emissive: bool = false, energy: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = _ext3(size)
	m.material = MatLib.flat(color, emissive, energy)
	mi.mesh = m
	root.add_child(mi)
	mi.position = _pos(pos)
	return mi

## Tube part — a grip, a drum, an axle, a length of line. `segments` defaults to
## CylinderMesh's own 64, which is ~640 triangles for ONE tube: fine for the odd can or
## bottle, ruinous once a build wants thirty of them inside a 96 px inventory icon (the
## same trap `_torus`'s `rings`/`ring_segments` exist for — see the note there). The deep
## rig's 33 tubes pass 10-24 and are indistinguishable from 64 in the hand OR the slot, at
## a fifth of the cost. Existing callers are untouched by the default.
static func _cyl(root: Node3D, radius: float, h: float, color: Color, pos: Vector3,
		emissive: bool = false, energy: float = 1.0, segments: int = 64) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = _ext(radius)
	m.bottom_radius = _ext(radius)
	m.height = _ext(h)
	# A tube needs at least a triangle's worth of circumference — same degenerate-mesh
	# hazard MIN_EXTENT guards against on the dimensions.
	m.radial_segments = maxi(segments, 3)
	m.material = MatLib.flat(color, emissive, energy)
	mi.mesh = m
	root.add_child(mi)
	mi.position = _pos(pos)
	return mi

static func _can(root: Node3D, metal: Color, label: Color) -> void:
	_cyl(root, 0.11, 0.28, metal, Vector3(0, 0.14, 0))
	_cyl(root, 0.115, 0.14, label, Vector3(0, 0.14, 0))   # label band around the middle

## Ring part — a rope coil, a growth ridge, a guard hoop, a rod guide. `rings` and
## `ring_segments` default to TorusMesh's own 64x32, which is 4096 triangles for ONE ring:
## affordable for the single hoops most cases build, ruinous for the fishing rod's six
## guides plus reel rims, which is why those pass counts down at 16x8. A 2 cm ring is
## indistinguishable at either count in the hand or in a 96 px icon.
static func _torus(root: Node3D, inner: float, outer: float, color: Color, pos: Vector3,
		rings: int = 64, ring_segments: int = 32) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := TorusMesh.new()
	# TorusMesh renders inside-out (or not at all) if the inner radius reaches the outer;
	# the outer is held at least one MIN_EXTENT clear of it rather than merely positive.
	m.inner_radius = _ext(inner)
	m.outer_radius = maxf(_ext(outer), m.inner_radius + MIN_EXTENT)
	# A ring needs at least a triangle's worth of each: a 0 or negative count is the same
	# degenerate-mesh hazard MIN_EXTENT guards against on the dimensions.
	m.rings = maxi(rings, 3)
	m.ring_segments = maxi(ring_segments, 3)
	m.material = MatLib.flat(color)
	mi.mesh = m
	root.add_child(mi)
	mi.position = _pos(pos)
	mi.rotation.x = deg_to_rad(90)
	return mi

## Sphere part — fruit, blobs, knobs, a spoon bowl. Segment counts are cut hard from the
## SphereMesh defaults (64x32): these are 8 cm props that also render into a 96 px icon, so
## a 12x6 ball is indistinguishable and costs a twentieth of the triangles. Non-uniform
## `stretch` is what turns one ball into a lemon, a dome or a flattened bruise.
static func _sph(root: Node3D, radius: float, color: Color, pos: Vector3,
		stretch: Vector3 = Vector3.ONE, emissive: bool = false, energy: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = _ext(radius)
	m.height = m.radius * 2.0
	m.radial_segments = 12
	m.rings = 6
	m.material = MatLib.flat(color, emissive, energy)
	mi.mesh = m
	root.add_child(mi)
	mi.position = _pos(pos)
	# A zero or NaN component here collapses/inverts the node's basis, which is the other
	# way a part turns into a flickering sliver. Uniform stretch stays exactly as authored.
	mi.scale = Vector3(_ext(stretch.x), _ext(stretch.y), _ext(stretch.z))
	return mi

## Tapered part — a bottle shoulder, a bowl flaring out, a shell cone. Same cylinder the
## squid mantle already builds by hand, given a name because half the galley needs it.
static func _cone(root: Node3D, bottom_r: float, top_r: float, h: float, color: Color,
		pos: Vector3, emissive: bool = false, energy: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.bottom_radius = _ext(bottom_r)
	m.top_radius = _ext(top_r)
	m.height = _ext(h)
	m.radial_segments = 12
	m.material = MatLib.flat(color, emissive, energy)
	mi.mesh = m
	root.add_child(mi)
	mi.position = _pos(pos)
	return mi

## Wedge part — a cheese wedge, a dried tail fan. Apex along +Y, extruded through Z; lay it
## on its side with rotation.x to get a triangle you look down on.
static func _prism(root: Node3D, size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := PrismMesh.new()
	m.size = _ext3(size)
	m.material = MatLib.flat(color)
	mi.mesh = m
	root.add_child(mi)
	mi.position = _pos(pos)
	return mi
