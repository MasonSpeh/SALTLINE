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
}
const FISH_SIZE := {
	"fish_barrel_grouper": 1.4, "fish_fathom_halibut": 1.6, "fish_copper_sprat": 0.6,
	"fish_ribbon_eel": 1.2,
}
## Real generated fish meshes (assets/models/fauna/<id>) when present; procedural
## silhouette when not. Preloaded — the class cache lags for this new file.
const FISH_MODEL := preload("res://scripts/world/fish_model_lib.gd")

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
		_:
			_box(root, Vector3(0.28, 0.3, 0.28), Interactable.COLOR_TAKEABLE, Vector3(0, 0.15, 0))
	return root

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
