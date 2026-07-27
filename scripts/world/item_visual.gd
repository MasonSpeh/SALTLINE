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
	"fish_coelacanth": Color(0.32, 0.34, 0.38), "fish_giant_oarfish": Color(0.6, 0.65, 0.58),
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
	"fish_giant_oarfish": 3.5,                                 # largest in the game, a ribbon of meat
	# The 2026-07-26 Meshy batch. Without these the whole new intake defaulted to 1.0 and a
	# bilge blenny weighed the same in the hand as a dogfish — the exact flattening this
	# table was written to stop.
	"fish_bilge_blenny": 0.45, "fish_kelp_pipefish": 0.5,      # bait-grade, a handful each
	"fish_gannet_mackerel": 0.7, "fish_rust_wrasse": 0.8,
	"fish_tallow_pollock": 1.1, "fish_squall_garfish": 1.2,
	"fish_lantern_dogfish": 1.5, "fish_anchor_ray": 1.6,       # both a two-handed lift
}
## Real generated fish meshes (assets/models/fauna/<id>) when present; procedural
## silhouette when not. Preloaded — the class cache lags for this new file.
const FISH_MODEL := preload("res://scripts/world/fish_model_lib.gd")
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
			_box(root, Vector3(0.3, 0.3, 0.3), Color(0.3, 0.34, 0.36), Vector3(0, 0.16, 0))
			_box(root, Vector3(0.16, 0.16, 0.16), Color(0.2, 0.9, 0.85), Vector3(0, 0.34, 0), true, 2.2)
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
			# Long tapering rod, cork grip, a small reel drum under the seat.
			var shaft := _box(root, Vector3(0.035, 1.5, 0.035), Color(0.45, 0.33, 0.2), Vector3(0, 0.55, 0))
			shaft.rotation.z = deg_to_rad(14)
			_box(root, Vector3(0.06, 0.3, 0.06), Color(0.65, 0.52, 0.35), Vector3(-0.14, 0.12, 0))
			var reel := _cyl(root, 0.07, 0.06, Color(0.25, 0.27, 0.3), Vector3(-0.1, 0.26, 0.05))
			reel.rotation.x = deg_to_rad(90)
			# An exact marker at the working end of the shaft (the end away from the grip/
			# reel), a child of the shaft itself so it inherits the shaft's own tilt and
			# position automatically. player_controller.hand_tip_world() looks this up by
			# name so the fishing line anchors to the ROD'S REAL RENDERED TIP instead of a
			# generic "longest AABB axis" guess, which put the anchor near the grip for any
			# item (like this rod) whose mesh is built along +Y rather than -Z.
			var tip := Node3D.new()
			tip.name = "hand_tip"
			shaft.add_child(tip)
			tip.position = Vector3(0, 0.75, 0)   # the shaft's own half-height: its far end
		"deep_rig_pole":
			# A heavy deep-drop hand-line, not a delicate rod: a short braced pole, a big
			# lead-weighted line drum, and terminal tackle slung under the tip. Built up its
			# own +Y like the rod so the "hand_tip" marker rides the working end and the
			# fishing line anchors there (player_controller.hand_tip_world finds it by name).
			var pole := _box(root, Vector3(0.055, 0.9, 0.055), Color(0.2, 0.22, 0.25), Vector3(0, 0.42, 0))
			pole.rotation.z = deg_to_rad(8)
			_box(root, Vector3(0.075, 0.3, 0.075), Color(0.3, 0.24, 0.16), Vector3(-0.06, 0.13, 0))    # taped grip
			var drum := _cyl(root, 0.12, 0.14, Color(0.32, 0.34, 0.37), Vector3(-0.03, 0.32, 0.07))    # line drum
			drum.rotation.x = deg_to_rad(90)
			var wind := _cyl(root, 0.125, 0.07, Color(0.55, 0.4, 0.2), Vector3(-0.03, 0.32, 0.07))     # wound line
			wind.rotation.x = deg_to_rad(90)
			_cyl(root, 0.05, 0.13, Color(0.22, 0.23, 0.26), Vector3(0.08, 0.74, 0))                    # lead weight
			var hk := _box(root, Vector3(0.03, 0.13, 0.03), Color(0.6, 0.62, 0.66), Vector3(0.11, 0.63, 0))
			hk.rotation.z = deg_to_rad(-42)                                                            # hook
			var dtip := Node3D.new()
			dtip.name = "hand_tip"
			pole.add_child(dtip)
			dtip.position = Vector3(0, 0.47, 0)   # the pole's own far (working) end — line drops from here
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
		"glow_worm", "glow_worm_cooked":
			# Glowing sphere for raw/cooked worm (slightly different glow in hand)
			_box(root, Vector3(0.25, 0.25, 0.25), Color(0.2, 0.9, 0.85), Vector3(0, 0.125, 0), true, 1.0)

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
			_sph(root, 0.086, Color(0.84, 0.63, 0.32), Vector3(0, 0.07, 0), Vector3(1.0, 0.5, 1.0))
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
			# Landed in items.json while this pass was running (2026-07-26) and went straight
			# onto the generic box, so it gets a look here with the rest. Same knuckled leg
			# for both; the pan reddens the shell and blacks the joints, exactly as the crab's
			# own carapace does in _crab_shape.
			var cl_hot: bool = item_id.ends_with("_seared")
			var cl_sh: Color = Color(0.78, 0.3, 0.16) if cl_hot else Color(0.62, 0.38, 0.28)
			var cl_jt: Color = Color(0.3, 0.16, 0.1) if cl_hot else Color(0.5, 0.3, 0.22)
			var cl_a := _cyl(root, 0.035, 0.18, cl_sh, Vector3(-0.09, 0.06, 0))
			cl_a.rotation.z = deg_to_rad(66)
			_sph(root, 0.037, cl_jt, Vector3(-0.015, 0.095, 0), Vector3(1.0, 0.9, 1.0))          # knuckle
			var cl_b := _cyl(root, 0.028, 0.17, cl_sh, Vector3(0.055, 0.075, 0))
			cl_b.rotation.z = deg_to_rad(115)
			_sph(root, 0.029, cl_jt, Vector3(0.125, 0.045, 0), Vector3(1.0, 0.9, 1.0))
			var cl_t := _cone(root, 0.026, 0.004, 0.1, cl_sh.darkened(0.15), Vector3(0.175, 0.025, 0))
			cl_t.rotation.z = deg_to_rad(-108)                                                   # pointed dactyl
			for cl_i in range(2):
				var cl_bd := _cyl(root, 0.037, 0.014, cl_jt, Vector3(-0.13 + cl_i * 0.06, 0.078 + cl_i * 0.014, 0))
				cl_bd.rotation.z = deg_to_rad(66)                                                # shell bands
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
			_box(root, Vector3(0.28, 0.3, 0.28), Interactable.COLOR_TAKEABLE, Vector3(0, 0.15, 0))
	return root

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
static func _is_species_fish(id: String) -> bool:
	if id == "cooked_fish_prime":
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
	var cone := _cyl(root, 0.001, 0.3, mantle, Vector3(0, 0.24, 0))
	(cone.mesh as CylinderMesh).bottom_radius = 0.09
	for i in range(4):
		_box(root, Vector3(0.03, 0.14, 0.03), tent,
			Vector3(cos(i * TAU / 4) * 0.05, 0.05, sin(i * TAU / 4) * 0.05))
	if not cooked:
		_box(root, Vector3(0.06, 0.06, 0.06), Color(0.2, 0.9, 0.85), Vector3(0, 0.3, 0), true, 0.8)  # bio-glow

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
	bm.radius = 0.06 * size_mul
	bm.height = 0.4 * size_mul
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
	em.radius = 0.015 * size_mul
	em.height = 0.03 * size_mul
	em.material = MatLib.flat(Color(0.05, 0.05, 0.06))
	eye.mesh = em
	root.add_child(eye)
	eye.position = Vector3(-0.15 * size_mul, 0.1 * size_mul, 0.045 * size_mul)

# ---- primitives ----

static func _box(root: Node3D, size: Vector3, color: Color, pos: Vector3,
		emissive: bool = false, energy: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	m.material = MatLib.flat(color, emissive, energy)
	mi.mesh = m
	root.add_child(mi)
	mi.position = pos
	return mi

static func _cyl(root: Node3D, radius: float, h: float, color: Color, pos: Vector3,
		emissive: bool = false, energy: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = h
	m.material = MatLib.flat(color, emissive, energy)
	mi.mesh = m
	root.add_child(mi)
	mi.position = pos
	return mi

static func _can(root: Node3D, metal: Color, label: Color) -> void:
	_cyl(root, 0.11, 0.28, metal, Vector3(0, 0.14, 0))
	_cyl(root, 0.115, 0.14, label, Vector3(0, 0.14, 0))   # label band around the middle

static func _torus(root: Node3D, inner: float, outer: float, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.material = MatLib.flat(color)
	mi.mesh = m
	root.add_child(mi)
	mi.position = pos
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
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 12
	m.rings = 6
	m.material = MatLib.flat(color, emissive, energy)
	mi.mesh = m
	root.add_child(mi)
	mi.position = pos
	mi.scale = stretch
	return mi

## Tapered part — a bottle shoulder, a bowl flaring out, a shell cone. Same cylinder the
## squid mantle already builds by hand, given a name because half the galley needs it.
static func _cone(root: Node3D, bottom_r: float, top_r: float, h: float, color: Color,
		pos: Vector3, emissive: bool = false, energy: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.bottom_radius = bottom_r
	m.top_radius = top_r
	m.height = h
	m.radial_segments = 12
	m.material = MatLib.flat(color, emissive, energy)
	mi.mesh = m
	root.add_child(mi)
	mi.position = pos
	return mi

## Wedge part — a cheese wedge, a dried tail fan. Apex along +Y, extruded through Z; lay it
## on its side with rotation.x to get a triangle you look down on.
static func _prism(root: Node3D, size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := PrismMesh.new()
	m.size = size
	m.material = MatLib.flat(color)
	mi.mesh = m
	root.add_child(mi)
	mi.position = pos
	return mi
