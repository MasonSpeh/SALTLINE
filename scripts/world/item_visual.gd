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

static func build(item_id: String) -> Node3D:
	var root := Node3D.new()
	# Fish family — raw fish AND per-species cooked meals ("cooked_fish_herring").
	# Try the real generated species mesh first (a caught fish reads as that fish),
	# fall back to the procedural silhouette. Cooked ids darken to a seared char.
	if _is_species_fish(item_id):
		var cooked: bool = item_id.begins_with("cooked_")
		var species: String = FISH_MODEL.species_of(item_id)
		var size_mul: float = FISH_SIZE.get(species, 1.0)
		var model: Node3D = FISH_MODEL.build(species, cooked, 0.42 * size_mul)
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
			# Owner call, 2026-07-27: this was a 3.5 cm box shaft, a cork-coloured handle box
			# and a 7 cm cylinder for a reel — a pond whip. Nobody hauls 40 kg up 80 m of
			# North Sea alongside a rig leg with that. What this is now is STAND-UP OFFSHORE
			# GEAR: a stout tapering graphite blank, a lever-drag multiplier sat on top of the
			# seat where an overhead reel goes, roller guides stepping down to the tip, and a
			# notched gimbal butt cap that seats into a fighting belt. Working kit off a
			# rusting rig — machined and salt-hazed, not a chromed sport-fishing showpiece.
			#
			# The whole rig hangs off ONE pivot rather than the root, so every part shares a
			# single lean and the "hand_tip" marker at the end inherits it for free (see the
			# marker note at the bottom of this case). Stations are measured in metres up the
			# pivot's +Y from the butt cap at y = 0, so the layout reads as a real rod:
			#   0.00 gimbal | 0.05-0.42 butt grip | 0.42-0.60 seat+reel | 0.60-0.90 foregrip
			#   | 0.90-1.90 blank + six guides | 1.90 roller tip.
			var fr := Node3D.new()
			root.add_child(fr)
			fr.rotation.z = deg_to_rad(14)
			# The grips must NOT be the same near-black as the blank or the foregrip vanishes
			# into it and the rod reads as seat-then-stick: they are a browner, flatter rubber.
			var fr_blank := Color(0.17, 0.18, 0.21)    # dark graphite, salt-hazed
			var fr_grip := Color(0.13, 0.12, 0.11)     # dark shrink-wrapped rubber grip
			var fr_metal := Color(0.33, 0.35, 0.38)    # gunmetal reel castings
			var fr_alloy := Color(0.42, 0.44, 0.47)    # machined seat and lock rings
			var fr_brass := Color(0.44, 0.35, 0.21)    # dull anodised drag lever
			var fr_wrap := Color(0.32, 0.17, 0.14)     # oxblood thread wraps at the guide feet
			var fr_line := Color(0.50, 0.48, 0.42)     # dirty braid wound on the spool
			# Gimbal butt cap: the notched cup that drops into a fighting belt, two lugs
			# standing proud of the cap so the notch reads from any angle.
			_cyl(fr, 0.055, 0.05, fr_metal, Vector3(0, 0.025, 0))
			for fr_n in [-1.0, 1.0]:
				_box(fr, Vector3(0.026, 0.032, 0.05), fr_metal.darkened(0.15), Vector3(fr_n * 0.036, -0.012, 0))
			_cyl(fr, 0.05, 0.028, Color(0.5, 0.5, 0.47), Vector3(0, 0.062, 0))                  # salt crust above the cap
			# Rear butt grip — the length you brace against the hip, ribbed for a wet glove.
			_cyl(fr, 0.043, 0.37, fr_grip, Vector3(0, 0.235, 0))
			for fr_i in range(4):
				var fr_rib := _torus(fr, 0.041, 0.048, fr_grip.lightened(0.07),
					Vector3(0, 0.115 + fr_i * 0.075, 0), 16, 6)
				fr_rib.rotation.x = 0.0                                                          # rings AROUND the butt
			# Machined reel seat with a knurled lock ring at each end.
			_cyl(fr, 0.047, 0.18, fr_alloy.darkened(0.18), Vector3(0, 0.51, 0))
			for fr_l in [0.432, 0.588]:
				var fr_lock := _torus(fr, 0.046, 0.057, fr_alloy.darkened(0.25), Vector3(0, fr_l, 0), 16, 8)
				fr_lock.rotation.x = 0.0
			# The REEL: a lever-drag multiplier clamped ON TOP of the seat. This is the single
			# thing that says "offshore" at a glance, so it is built as a real one — two
			# machined side plates, a wide spool of braid between them, frame pillars, a thumb
			# lever and a crank standing off the handle side. Its axis runs ACROSS the rod
			# (local Z), so every round part of it is laid over with rotation.x = 90°.
			_box(fr, Vector3(0.05, 0.034, 0.09), fr_metal, Vector3(0.065, 0.505, 0))             # foot clamped to the seat
			var fr_rc := Vector3(0.142, 0.535, 0)
			var fr_spool := _cyl(fr, 0.052, 0.145, fr_line, fr_rc)                               # wound braid on the arbor
			fr_spool.rotation.x = deg_to_rad(90)
			for fr_s in [-1.0, 1.0]:
				var fr_plate := _cyl(fr, 0.082, 0.018, fr_metal, fr_rc + Vector3(0, 0, fr_s * 0.084))
				fr_plate.rotation.x = deg_to_rad(90)                                             # side plates
				# _torus already lies across the rod (rotation.x = 90°), which IS the reel's
				# own axis — these rims are the one place in this case the default is right.
				_torus(fr, 0.072, 0.085, fr_metal.darkened(0.25), fr_rc + Vector3(0, 0, fr_s * 0.094), 20, 8)
			for fr_p in range(3):
				var fr_pa: float = fr_p * TAU / 3.0 + 0.6
				_box(fr, Vector3(0.02, 0.02, 0.16), fr_metal.darkened(0.12),
					fr_rc + Vector3(cos(fr_pa) * 0.07, sin(fr_pa) * 0.07, 0))                    # frame pillars
			var fr_cam := _cyl(fr, 0.024, 0.018, fr_brass.darkened(0.2), fr_rc + Vector3(0, 0, 0.1))
			fr_cam.rotation.x = deg_to_rad(90)                                                   # drag cam boss
			var fr_lever := _box(fr, Vector3(0.095, 0.02, 0.015), fr_brass, fr_rc + Vector3(0.034, 0.036, 0.108))
			fr_lever.rotation.z = deg_to_rad(42)                                                 # thumb lever, drag off
			var fr_stub := _cyl(fr, 0.014, 0.055, fr_alloy, fr_rc + Vector3(0, 0, 0.125))
			fr_stub.rotation.x = deg_to_rad(90)                                                  # crank shaft
			# The arm is the lighter alloy, not the plate's gunmetal: a dark bar on a dark
			# plate disappears from every angle that matters.
			var fr_arm := _box(fr, Vector3(0.14, 0.026, 0.016), fr_alloy, fr_rc + Vector3(0.043, -0.043, 0.155))
			fr_arm.rotation.z = deg_to_rad(-42)                                                  # offset crank arm
			var fr_knob := _cyl(fr, 0.019, 0.05, fr_grip.lightened(0.08), fr_rc + Vector3(0.088, -0.088, 0.155))
			fr_knob.rotation.x = deg_to_rad(90)                                                  # fist-sized knob
			# Long foregrip you pull against, then the blank proper: four stacked tapering
			# segments, 3.6 cm at the butt down to 7 mm at the tip, so the taper actually
			# reads instead of being one uniform stick.
			_cone(fr, 0.045, 0.038, 0.30, fr_grip, Vector3(0, 0.75, 0))
			for fr_f in range(3):
				var fr_fr := _torus(fr, 0.039 - fr_f * 0.001, 0.047 - fr_f * 0.001,
					fr_grip.lightened(0.07), Vector3(0, 0.655 + fr_f * 0.085, 0), 16, 6)
				fr_fr.rotation.x = 0.0                                                           # foregrip ribs
			_cyl(fr, 0.040, 0.02, fr_alloy, Vector3(0, 0.90, 0))                                 # ferrule collar
			_cone(fr, 0.036, 0.028, 0.30, fr_blank, Vector3(0, 1.05, 0))
			_cone(fr, 0.028, 0.021, 0.28, fr_blank, Vector3(0, 1.34, 0))
			_cone(fr, 0.021, 0.014, 0.24, fr_blank, Vector3(0, 1.60, 0))
			_cone(fr, 0.014, 0.007, 0.18, fr_blank, Vector3(0, 1.81, 0))
			# Guides stepping down the blank, big at the butt to small at the tip — the thing
			# that makes a rod read as a rod at a glance. Each is a ring on a short standoff
			# post over a wrapped thread binding, on the SAME side as the reel, because that
			# is where an overhead reel's line runs. Ring segment counts are cut hard (see
			# _torus): six rings at the TorusMesh default would be 25k triangles in a 96 px
			# inventory icon.
			for fr_g in [[1.00, 0.054], [1.20, 0.043], [1.39, 0.033], [1.56, 0.025], [1.71, 0.019], [1.83, 0.014]]:
				var fr_gy: float = fr_g[0]
				var fr_gr: float = fr_g[1]
				var fr_br: float = 0.036 - 0.029 * (fr_gy - 0.90)                                # blank radius at this station
				var fr_post: float = 0.006 + fr_gr * 0.25
				_cyl(fr, fr_br + 0.004, 0.032, fr_wrap, Vector3(0, fr_gy, 0))                    # thread wrap
				_box(fr, Vector3(fr_post, 0.013, 0.014), fr_metal,
					Vector3(fr_br + fr_post * 0.5, fr_gy, 0))                                    # standoff post
				var fr_ring := _torus(fr, fr_gr, fr_gr + 0.006, fr_alloy,
					Vector3(fr_br + fr_post + fr_gr, fr_gy, 0), 16, 8)
				fr_ring.rotation.x = 0.0                                                         # hole up the blank
			# Roller tip: the last bearing the line touches before it goes over the side.
			_sph(fr, 0.008, fr_metal, Vector3(0, 1.90, 0))                                       # blank end cap
			_box(fr, Vector3(0.024, 0.012, 0.013), fr_metal, Vector3(0.012, 1.888, 0))           # tip frame
			var fr_tipring := _torus(fr, 0.010, 0.017, fr_alloy, Vector3(0.024, 1.902, 0), 16, 8)
			fr_tipring.rotation.x = 0.0
			var fr_roller := _cyl(fr, 0.009, 0.009, fr_alloy.lightened(0.12), Vector3(0.024, 1.888, 0))
			fr_roller.rotation.x = deg_to_rad(90)                                                # the wheel itself
			# An exact marker at the working end (the roller tip — where the line actually
			# leaves the rig), a child of the rod pivot so it inherits the rig's own tilt and
			# position automatically. player_controller.hand_tip_world() looks this up by
			# name so the fishing line anchors to the ROD'S REAL RENDERED TIP instead of a
			# generic "longest AABB axis" guess, which put the anchor near the grip for any
			# item (like this rod) whose mesh is built along +Y rather than -Z.
			var tip := Node3D.new()
			tip.name = "hand_tip"
			fr.add_child(tip)
			tip.position = Vector3(0.024, 1.90, 0)   # the roller's own centre: the far end
		"deep_rig_pole":
			# Owner call, 2026-07-29: this was eight crude primitives — a box for the pole, a
			# box for the grip, two cylinders called a drum, a lead and a rotated box hook. The
			# deep rig is the thing you climb 32 m of ladder for, so it earns the build the
			# fishing_rod case above it got.
			#
			# WHAT IT IS, and why it must not become a second rod: a HEAVY DEEP-DROP HAND-LINE
			# for putting a lead 45 m STRAIGHT DOWN off the crane's machinery deck (see
			# fishing_rod.gd's deep branch — no float, no drift, no cast; the readout counts the
			# metres as the lead falls). So there is no casting blank, no taper and no ring
			# guides. There is a short braced FRAME fabricated out of rig scrap, a hand WINCH
			# with a ratchet, pawl and brake shoe, a fairlead and a sheave to lead the line, and
			# heavy terminal tackle hove up short under the block ready to go over the side.
			# Commercial gear off a rusting rig: graphite box section, gunmetal weldments,
			# machined alloy, salt haze. No chrome anywhere on this rig.
			#
			# Like the rod, the whole thing hangs off ONE pivot instead of the root, so every
			# part shares a single lean and the "hand_tip" marker at the sheave inherits it for
			# free. Stations are metres up the pivot's +Y from the foot plate at y = 0:
			#   0.00 foot | 0.13-0.30 taped grip | 0.32-0.62 drum, crank, ratchet, brake
			#   | 0.30-1.12 mast + its diagonal brace | 0.75 fairlead | 1.13 sheave block
			#   | 1.09-0.86 terminal tackle hanging under it.
			var dr := Node3D.new()
			root.add_child(dr)
			# A small lean, not the rod's 14°: every degree of it also throws the top of a 1.15 m
			# frame sideways, and the wider the model's X the smaller the hand normalisation
			# (largest dimension -> 0.9 m) draws the whole tool.
			dr.rotation.z = deg_to_rad(-4)             # leaning out the way the davit arm points
			# Same material language as the rod, but PITCHED DARKER than the rod's own numbers,
			# measured off a render rather than copied: the rod is all thin tubes, while this has
			# a 0.30 m disc and a 0.22 m plate turned at the sun, and the rod's fr_metal (0.33)
			# on areas that size photographed as pale galvanised sheet — a light plastic toy, the
			# exact failure the traps file names for generated assets.
			var dp_frame := Color(0.215, 0.230, 0.255)   # gunmetal weldments — foot, brackets, drum
			var dp_mast := Color(0.155, 0.165, 0.190)    # graphite box section, the darkest thing here
			var dp_alloy := Color(0.365, 0.385, 0.415)   # machined alloy: axle, ratchet, sheave
			var dp_grip := Color(0.13, 0.12, 0.11)       # rubber sleeve, as on the rod's grips
			var dp_tape := Color(0.17, 0.16, 0.14)       # friction tape lapped over the sleeve
			var dp_lead := Color(0.235, 0.245, 0.265)    # dull cast lead — flatter than the alloy
			# The rod's own braid colour (0.50) is a small spool; 45 m of it wound on a 0.27 m
			# drum is the largest single area on this tool, and at that size it photographed as a
			# bright white ring. Salt-stiffened working line, two thirds of the rod's value.
			var dp_line := Color(0.355, 0.340, 0.300)    # 45 m of dirty, salt-stiffened braid
			var dp_brass := Color(0.40, 0.31, 0.185)     # dull anodised pawl and brake, as the rod's lever
			var dp_wrap := Color(0.30, 0.16, 0.13)       # oxblood, straight off the rod's thread wraps
			var dp_rust := Color(0.36, 0.25, 0.17)       # rust in the weld seams and down the paint
			var dp_salt := Color(0.50, 0.51, 0.48)       # salt crust / bare steel where it has been dragged
			var dp_canvas := Color(0.42, 0.40, 0.34)     # the rag every working rig carries
			# FOOT — this thing is set DOWN on a deck between drops, so it has a foot to stand
			# on: a tread plate, two deck bolts, and one bare-steel edge where it gets dragged.
			_box(dr, Vector3(0.225, 0.026, 0.19), dp_frame, Vector3(0.005, 0.013, 0))
			_box(dr, Vector3(0.235, 0.007, 0.20), dp_rust, Vector3(0.005, 0.004, 0))
			for dp_b in [-1.0, 1.0]:
				_cyl(dr, 0.017, 0.020, dp_alloy, Vector3(-0.072, 0.032, dp_b * 0.062), false, 1.0, 10)
			_box(dr, Vector3(0.045, 0.012, 0.20), dp_salt, Vector3(0.100, 0.030, 0))
			_box(dr, Vector3(0.078, 0.100, 0.115), dp_frame, Vector3(-0.004, 0.075, 0))   # heel boss
			# MAST — two stepped box sections spliced at a bolted flange, because a fabricated
			# post reads as fabricated and a single smooth tube reads as a rod's blank.
			_box(dr, Vector3(0.064, 0.605, 0.064), dp_mast, Vector3(0, 0.357, 0))
			_box(dr, Vector3(0.104, 0.014, 0.104), dp_alloy, Vector3(0, 0.660, 0))
			var dp_weld := _torus(dr, 0.034, 0.043, dp_rust, Vector3(0, 0.673, 0), 16, 6)
			dp_weld.rotation.x = 0.0                                                       # ring AROUND the mast
			_box(dr, Vector3(0.050, 0.425, 0.050), dp_mast, Vector3(0, 0.880, 0))
			_box(dr, Vector3(0.052, 0.340, 0.010), dp_rust, Vector3(0, 0.440, -0.033))     # rust streak
			var dp_crust := _torus(dr, 0.036, 0.058, dp_salt, Vector3(0, 0.132, 0), 16, 6)
			dp_crust.rotation.x = 0.0                                                      # salt pooled on the boss
			# GRIP — where you brace it against a hip or a rail, taped over rubber for a wet
			# glove. The tape is a browner black than the mast or the grip vanishes into it.
			_cyl(dr, 0.049, 0.170, dp_grip, Vector3(0, 0.215, 0), false, 1.0, 16)
			for dp_w in range(4):
				var dp_lap := _torus(dr, 0.047, 0.056, dp_tape,
					Vector3(0, 0.150 + dp_w * 0.043, 0), 16, 6)
				dp_lap.rotation.x = 0.0
			_box(dr, Vector3(0.012, 0.028, 0.050), dp_tape.lightened(0.09), Vector3(0.050, 0.300, 0))
			# THE DRUM — the one part that says "hand-line winch" at a glance, so it is built as
			# a real one: an arbor wound with braid between two flanged cheeks, on a bracket
			# standing off the mast. Its axis runs ACROSS the rig (local Z), so every round part
			# is laid over with rotation.x = 90°.
			var dp_dc := Vector3(-0.165, 0.470, 0)
			for dp_p in [-1.0, 1.0]:
				_box(dr, Vector3(0.215, 0.070, 0.016), dp_frame,
					Vector3(-0.077, 0.470, dp_p * 0.152))                                  # bracket cheeks
			var dp_barrel := _cyl(dr, 0.086, 0.210, dp_frame.darkened(0.18), dp_dc, false, 1.0, 18)
			dp_barrel.rotation.x = deg_to_rad(90)                                          # arbor
			var dp_wound := _cyl(dr, 0.137, 0.184, dp_line, dp_dc, false, 1.0, 18)
			dp_wound.rotation.x = deg_to_rad(90)                                           # the 45 m of braid
			# Three dark rings AROUND the braid at different points along the drum — the lay of
			# the wind. A 5 mm tube (outer minus inner) at a 137 mm ring radius, so these are
			# groove lines on the surface of the line, not hoops standing off it.
			for dp_g in [-0.055, 0.010, 0.062]:
				_torus(dr, 0.134, 0.139, dp_line.darkened(0.26), dp_dc + Vector3(0, 0, dp_g), 18, 6)
			# THE TWO CHEEKS ARE DIFFERENT SIZES, and that is what finally made this read as a
			# drum. Held in hand the tool's own +Z points within 27° of the camera, so the near
			# cheek is seen almost dead flat: at equal radii it hid the braid completely and
			# photographed as a smooth disc with a hub and spokes — a bicycle wheel, twice, in
			# two different colours. The DRIVE cheek (crank side, +Z) is 112 mm against the far
			# cheek's 142, so the braid at 137 stands 25 mm proud of it and there is always a
			# pale ring of line around a bolted plate. Undersized drive cheeks are how real
			# hand-winches are built anyway — the gear train has to clear the flange.
			for dp_s in [-1.0, 1.0]:
				var dp_cr: float = 0.112 if dp_s > 0.0 else 0.142
				var dp_cheek := _cyl(dr, dp_cr, 0.016, dp_frame.darkened(0.16),
					dp_dc + Vector3(0, 0, dp_s * 0.100), false, 1.0, 22)
				dp_cheek.rotation.x = deg_to_rad(90)
				# _torus already lies across the rig, which IS the drum's own axis — the same
				# one place the default is right that the rod's reel rims rely on.
				_torus(dr, dp_cr - 0.004, dp_cr + 0.008, dp_frame.darkened(0.36),
					dp_dc + Vector3(0, 0, dp_s * 0.110), 22, 8)                            # flange lip
				var dp_ax := _cyl(dr, 0.019, 0.085, dp_alloy,
					dp_dc + Vector3(0, 0, dp_s * 0.140), false, 1.0, 12)
				dp_ax.rotation.x = deg_to_rad(90)                                          # axle stub
				var dp_hub := _cyl(dr, 0.032, 0.012, dp_alloy.darkened(0.12),
					dp_dc + Vector3(0, 0, dp_s * 0.112), false, 1.0, 16)
				dp_hub.rotation.x = deg_to_rad(90)                                         # machined hub boss
				# A painted band on each cheek, in the rod's own OXBLOOD. An earlier cut painted
				# it faded ochre and the drum came back a bright yellow disc — the wrong accent
				# entirely on a rig that had just had a blank yellow block taken off its wet deck.
				var dp_ring := _cyl(dr, dp_cr * 0.62, 0.004, dp_wrap,
					dp_dc + Vector3(0, 0, dp_s * 0.109), false, 1.0, 20)
				dp_ring.rotation.x = deg_to_rad(90)
			# Bolt circle through the drive cheek: the detail that turns a disc into a plate that
			# was fitted by somebody, which is the whole difference between machinery and a wheel.
			for dp_bo in range(6):
				var dp_boa: float = dp_bo * TAU / 6.0 + 0.30
				var dp_blt := _cyl(dr, 0.0075, 0.010, dp_alloy,
					dp_dc + Vector3(cos(dp_boa) * 0.088, sin(dp_boa) * 0.088, 0.112), false, 1.0, 8)
				dp_blt.rotation.x = deg_to_rad(90)
			# Four radial gussets on the FAR cheek, where there is plate to put them on.
			for dp_r in range(4):
				var dp_ra: float = dp_r * TAU / 4.0 + 0.40
				var dp_rib := _box(dr, Vector3(0.017, 0.062, 0.011), dp_frame.lightened(0.05),
					dp_dc + Vector3(cos(dp_ra) * 0.104, sin(dp_ra) * 0.104, -0.113))
				# A box's long side is its local +Y, and rotation.z sends +Y to (-sin, cos) — so
				# a RADIAL rib is ra - 90°, not 90° - ra (which mirrors it to 180° - ra and puts
				# every rib across its own radius instead of along it).
				dp_rib.rotation.z = dp_ra - PI * 0.5
			# RATCHET AND PAWL — 45 m of wet line pulling on a drum has to be HELD, and this is
			# the mechanism data/items.json means by "LMB thumbs the drum to hold a depth".
			var dp_gear := _cyl(dr, 0.058, 0.012, dp_alloy.darkened(0.14),
				dp_dc + Vector3(0, 0, 0.172), false, 1.0, 18)
			dp_gear.rotation.x = deg_to_rad(90)
			for dp_t in range(6):
				var dp_ta: float = dp_t * TAU / 6.0
				_box(dr, Vector3(0.016, 0.017, 0.011), dp_alloy.darkened(0.24),
					dp_dc + Vector3(cos(dp_ta) * 0.062, sin(dp_ta) * 0.062, 0.172))        # teeth
			var dp_pawl := _box(dr, Vector3(0.090, 0.014, 0.011), dp_brass,
				dp_dc + Vector3(0.058, 0.051, 0.172))
			dp_pawl.rotation.z = deg_to_rad(-17.6)                                         # dropped into the gear
			var dp_ppin := _cyl(dr, 0.010, 0.024, dp_alloy,
				dp_dc + Vector3(0.098, 0.038, 0.172), false, 1.0, 10)
			dp_ppin.rotation.x = deg_to_rad(90)
			# CRANK — offset arm and a fist knob. The only way line comes back up 45 m.
			var dp_boss := _cyl(dr, 0.024, 0.030, dp_alloy,
				dp_dc + Vector3(0, 0, 0.198), false, 1.0, 14)
			dp_boss.rotation.x = deg_to_rad(90)
			# The arm is the lighter alloy, not the frame's gunmetal: a dark bar on a dark drum
			# disappears from every angle that matters (the rod's crank learned this first).
			var dp_arm := _box(dr, Vector3(0.165, 0.030, 0.017), dp_alloy,
				dp_dc + Vector3(0.055, -0.055, 0.220))
			dp_arm.rotation.z = deg_to_rad(-45)
			var dp_knob := _cyl(dr, 0.022, 0.060, dp_grip.lightened(0.09),
				dp_dc + Vector3(0.110, -0.110, 0.220), false, 1.0, 14)
			dp_knob.rotation.x = deg_to_rad(90)
			_torus(dr, 0.020, 0.027, dp_alloy, dp_dc + Vector3(0.110, -0.110, 0.190), 14, 6)
			# BRAKE — a shoe on a lever pressed down onto the drum rim: the thing that stops a
			# 1.5 kg lead running away with the whole spool on the way down.
			var dp_shoe := _box(dr, Vector3(0.115, 0.022, 0.196), dp_brass.darkened(0.42),
				Vector3(-0.176, 0.629, 0))
			dp_shoe.rotation.z = deg_to_rad(9)
			var dp_blev := _box(dr, Vector3(0.215, 0.024, 0.022), dp_brass.darkened(0.14),
				Vector3(-0.079, 0.664, 0.070))
			dp_blev.rotation.z = deg_to_rad(14.5)
			var dp_bpin := _cyl(dr, 0.011, 0.030, dp_alloy, Vector3(0.022, 0.690, 0.070), false, 1.0, 10)
			dp_bpin.rotation.x = deg_to_rad(90)                                            # lever pivot on the mast
			var dp_thumb := _cyl(dr, 0.017, 0.028, dp_grip, Vector3(-0.168, 0.652, 0.070), false, 1.0, 12)
			dp_thumb.rotation.x = deg_to_rad(90)                                           # thumb pad
			# THE DIAGONAL — one strut from the mast foot to the underside of the davit arm.
			# This is what makes the silhouette a frame instead of a stick with a reel on it.
			var dp_strut := _box(dr, Vector3(0.028, 0.830, 0.026), dp_frame, Vector3(0.1025, 0.704, 0))
			dp_strut.rotation.z = deg_to_rad(-10.2)
			_box(dr, Vector3(0.058, 0.075, 0.030), dp_frame.darkened(0.12), Vector3(0.046, 0.318, 0))
			for dp_sb in [Vector3(0.038, 0.306, 0), Vector3(0.175, 1.105, 0)]:
				var dp_bolt := _cyl(dr, 0.011, 0.032, dp_alloy, dp_sb, false, 1.0, 10)
				dp_bolt.rotation.x = deg_to_rad(90)                                        # strut end bolts
			# HEAD — a casting on the mast top, a short davit arm angled up and out over the
			# water, and a gusset filling the corner between them.
			_box(dr, Vector3(0.072, 0.066, 0.072), dp_frame, Vector3(0.004, 1.075, 0))
			var dp_boom := _box(dr, Vector3(0.220, 0.034, 0.040), dp_frame, Vector3(0.1075, 1.100, 0))
			dp_boom.rotation.z = deg_to_rad(12.1)
			_prism(dr, Vector3(0.150, 0.085, 0.032), dp_frame.darkened(0.10), Vector3(0.070, 1.010, 0))
			# FAIRLEAD — the roller just above the drum that turns the line from the spool up
			# the face of the mast. Line runs on the +Z side of the mast all the way up, which
			# is why the standing line below never has to cross the strut.
			_box(dr, Vector3(0.045, 0.020, 0.055), dp_frame, Vector3(0, 0.718, 0.045))
			for dp_fc in [0.012, 0.068]:
				_box(dr, Vector3(0.055, 0.055, 0.008), dp_frame, Vector3(0, 0.752, dp_fc))
			var dp_roll := _cyl(dr, 0.020, 0.052, dp_alloy, Vector3(0, 0.752, 0.040), false, 1.0, 14)
			dp_roll.rotation.x = deg_to_rad(90)
			var dp_fpin := _cyl(dr, 0.006, 0.076, dp_alloy, Vector3(0, 0.752, 0.040), false, 1.0, 8)
			dp_fpin.rotation.x = deg_to_rad(90)
			# THE STANDING LINE, drum -> fairlead -> up the mast -> out the arm -> over the
			# sheave. It is what the rod's six guides are: the part that makes the tool legible
			# as a machine for moving line rather than an assembly of parts.
			var dp_off := _cyl(dr, 0.005, 0.221, dp_line, Vector3(-0.083, 0.672, 0.040), false, 1.0, 8)
			dp_off.rotation.z = deg_to_rad(-48.3)
			_cyl(dr, 0.005, 0.315, dp_line, Vector3(0, 0.925, 0.040), false, 1.0, 8)
			_box(dr, Vector3(0.010, 0.012, 0.030), dp_alloy, Vector3(0, 0.925, 0.021))
			var dp_keep := _torus(dr, 0.009, 0.016, dp_alloy, Vector3(0, 0.925, 0.040), 14, 6)
			dp_keep.rotation.x = 0.0                                                       # keeper the line runs through
			var dp_run := _cyl(dr, 0.005, 0.205, dp_line, Vector3(0.1015, 1.097, 0.040), false, 1.0, 8)
			dp_run.rotation.z = deg_to_rad(-81.6)
			# SHEAVE BLOCK — the last bearing the line touches before it goes over the side,
			# and the point the whole tool is aimed at.
			for dp_sp in [0.016, 0.064]:
				_box(dr, Vector3(0.046, 0.068, 0.007), dp_frame, Vector3(0.210, 1.122, dp_sp))
			var dp_wheel := _cyl(dr, 0.026, 0.024, dp_alloy.lightened(0.10),
				Vector3(0.210, 1.122, 0.040), false, 1.0, 16)
			dp_wheel.rotation.x = deg_to_rad(90)
			_torus(dr, 0.023, 0.029, dp_alloy.darkened(0.18), Vector3(0.210, 1.122, 0.040), 16, 8)
			var dp_spin := _cyl(dr, 0.007, 0.070, dp_alloy, Vector3(0.210, 1.122, 0.040), false, 1.0, 8)
			dp_spin.rotation.x = deg_to_rad(90)
			_torus(dr, 0.010, 0.017, dp_alloy, Vector3(0.210, 1.086, 0.040), 14, 6)        # becket
			# TERMINAL TACKLE, hove short up under the block the way a hand-line is carried:
			# a three-way swivel, a snooded hook on a short trace, and the LEAD — 1.4 kg of
			# cast torpedo (60 mm through, 133 mm long), the heaviest single thing on the tool
			# and the reason every other part of it is built the way it is.
			_cyl(dr, 0.005, 0.034, dp_line, Vector3(0.210, 1.064, 0.040), false, 1.0, 8)
			var dp_sw := _torus(dr, 0.007, 0.013, dp_alloy, Vector3(0.210, 1.054, 0.040), 12, 6)
			dp_sw.rotation.x = 0.0
			_box(dr, Vector3(0.030, 0.016, 0.011), dp_alloy.darkened(0.12), Vector3(0.210, 1.040, 0.040))
			_cyl(dr, 0.005, 0.054, dp_line, Vector3(0.210, 1.007, 0.040), false, 1.0, 8)
			_cone(dr, 0.030, 0.014, 0.038, dp_lead, Vector3(0.210, 0.963, 0.040))          # lead shoulder
			_cyl(dr, 0.030, 0.056, dp_lead, Vector3(0.210, 0.916, 0.040), false, 1.0, 16)  # lead body
			_cone(dr, 0.010, 0.030, 0.040, dp_lead.darkened(0.10), Vector3(0.210, 0.869, 0.040))
			# The snood: rotation.z sends a cylinder's +Y to (-sin, cos), so an angle of 55.8°
			# puts its axis along (-0.827, 0.562) — the trace from the three-way out to the hook
			# eye. The first pass used 125°, which is not that line or its negation at all, and
			# hung the hook off the end of a snood pointing somewhere else.
			var dp_snood := _cyl(dr, 0.004, 0.091, dp_line, Vector3(0.2475, 1.0145, 0.040), false, 1.0, 8)
			dp_snood.rotation.z = deg_to_rad(55.8)
			var dp_he := _torus(dr, 0.006, 0.011, dp_alloy, Vector3(0.287, 0.986, 0.040), 12, 6)
			dp_he.rotation.x = 0.0
			_cyl(dr, 0.005, 0.048, dp_alloy, Vector3(0.291, 0.960, 0.040), false, 1.0, 8)  # hook shank
			var dp_bd1 := _box(dr, Vector3(0.010, 0.022, 0.009), dp_alloy, Vector3(0.293, 0.928, 0.040))
			dp_bd1.rotation.z = deg_to_rad(30)
			var dp_bd2 := _box(dr, Vector3(0.010, 0.022, 0.009), dp_alloy, Vector3(0.278, 0.915, 0.040))
			dp_bd2.rotation.z = deg_to_rad(72)                                             # the bend of the hook
			var dp_pt := _cyl(dr, 0.004, 0.026, dp_alloy.lightened(0.10),
				Vector3(0.263, 0.927, 0.040), false, 1.0, 8)
			dp_pt.rotation.z = deg_to_rad(-16)                                             # point, rising back up
			var dp_barb := _box(dr, Vector3(0.005, 0.014, 0.006), dp_alloy, Vector3(0.261, 0.942, 0.040))
			dp_barb.rotation.z = deg_to_rad(38)
			# A lumo bead above the hook — real deep-drop rigs run one, and in this ocean it is
			# a live Bloom cell. Emissive at 1.8, well over main.gd's 0.8 glow threshold.
			_sph(dr, 0.009, Color(0.22, 0.92, 0.86), Vector3(0.263, 1.002, 0.040),
				Vector3.ONE, true, 1.8)
			# STENCILLED DEPTH PLATE and a rag knotted under the head — the two details that say
			# somebody worked with this rather than found it in a box.
			_box(dr, Vector3(0.050, 0.070, 0.006), Color(0.44, 0.39, 0.20), Vector3(0, 0.550, 0.036))
			_box(dr, Vector3(0.034, 0.008, 0.004), dp_mast, Vector3(0, 0.566, 0.040))
			var dp_lan := _torus(dr, 0.022, 0.033, Color(0.44, 0.40, 0.32), Vector3(0, 0.855, 0), 14, 6)
			dp_lan.rotation.x = 0.0
			var dp_rag := _box(dr, Vector3(0.028, 0.085, 0.020), dp_canvas, Vector3(0.028, 0.815, -0.032))
			dp_rag.rotation.z = deg_to_rad(12)
			# The marker at the SHEAVE — where the line actually leaves the tool. A child of the
			# rig pivot so it inherits the lean and position for free.
			# player_controller.hand_tip_world() looks this up BY NAME; lose it and the silent
			# _hand_reach_axis fallback anchors the line inside the player's fist instead
			# (tests/RodHandProbe.tscn asserts the two answers differ, which is what catches it).
			var dtip := Node3D.new()
			dtip.name = "hand_tip"
			dr.add_child(dtip)
			dtip.position = Vector3(0.210, 1.122, 0.040)   # the sheave's own centre
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
