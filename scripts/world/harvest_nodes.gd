extends Node3D
## The wet deck's natural stock: what the sea leaves on the rig rather than what
## the crew did. Tar weeping out of the deck seams, barnacle crust up the caisson
## and along the lip where the swell washes over, floats snagged in the dock
## fenders, kelp growing on the plates, and the old fish-cleaning board under the
## drying lines.
##
## All of these are Salvage nodes with a regrow time: unlike a gutted locker they
## come back if you leave them alone, so the rig keeps feeding you slowly instead
## of being mined out on day one. The floats are the exception — a float is an
## object, and once you've cut it free it's yours.
##
## Everything sits on the wet deck (floor y = 2.0, x 8..30, z -22..2) and on the
## SE caisson's west face (x = 19, z -15..-9), which is the only leg that comes up
## through this deck.
##
## GLOW WORM CLUSTERS (2026-07-27) are the newest of these and the one that feeds another
## system rather than the crafting bench: they are the deep rig's best bait. See
## _glowworm_clusters() for where they sit and why, and fish_table.gd's BAIT_TABLE for what
## a glowing bait does on a hook.

const SALVAGE := preload("res://scripts/components/salvage.gd")
const WET_Y: float = 2.0

## MatLib.flat() hands back a CACHED material — tuning roughness or emission on one
## would retune it everywhere that colour is used. These are ours alone.
var _m_tar: StandardMaterial3D
var _m_shell: StandardMaterial3D
var _m_kelp: StandardMaterial3D
var _m_bone: StandardMaterial3D

func _ready() -> void:
	# Tar stays wet-looking years cold — but "wet black" is a SPECULAR read, not a dark
	# albedo. At 0.045 albedo with middling roughness and no direct light under the deck
	# a seam photographed as a pure black ellipse: a hole in the plating, not tar.
	# The colour lifts just off black and the gloss goes right up, so it catches the sky.
	_m_tar = _mat(Color(0.085, 0.078, 0.072), 0.16)
	_m_tar.metallic_specular = 0.85
	_m_shell = _mat(Color(0.72, 0.7, 0.63), 0.9)
	_m_kelp = _mat(Color(0.12, 0.3, 0.24), 0.75)
	_m_kelp.emission_enabled = true
	_m_kelp.emission = Color(0.1, 0.55, 0.45)
	_m_kelp.emission_energy_multiplier = 0.25          # the Bloom is in everything down here
	_m_bone = _mat(Color(0.86, 0.84, 0.76), 0.8)
	_tar_seams()
	_barnacle_crust()
	_snagged_floats()
	_kelp_growth()
	_cleaning_board()
	_glowworm_clusters()

func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

# ---- tar: the deck seams have been weeping since before the evacuation ----

func _tar_seams() -> void:
	var def := {
		"tools": [], "speed": ["prybar", "hand_file"], "verb": "SCRAPE", "work": 2.6,
		"sound": "hiss", "regrow": 240.0, "name": "Tar Seam",
		"yields": {"tar_lump": 1},
		"hint": "", "start": "You lever up an edge of the tar.",
		"done": "It peels off the seam in a cold black lump.",
	}
	for spot in [Vector3(20.6, WET_Y, -6.2), Vector3(14.2, WET_Y, -4.4),
			Vector3(26.2, WET_Y, -9.6), Vector3(9.8, WET_Y, -2.6),
			Vector3(18.4, WET_Y, -14.4)]:
		SALVAGE.from_visual(self, _tar_visual(), spot, fmod(spot.x * 37.0, 360.0), def, 0.5)

func _tar_visual() -> Node3D:
	var root := Node3D.new()
	for i in range(3):
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.16 + i * 0.09
		cm.bottom_radius = cm.top_radius
		cm.height = 0.018 + i * 0.004
		cm.material = _m_tar
		mi.mesh = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.position = Vector3(cos(i * 2.4) * 0.11 * i, 0.012 + i * 0.004, sin(i * 2.4) * 0.11 * i)
	return root

# ---- barnacle and limpet crust: spray zone, so it never quite dries out ----

func _barnacle_crust() -> void:
	var def := {
		"tools": [], "speed": ["hammer_tool", "prybar"], "verb": "SCRAPE", "work": 2.2,
		"sound": "scuttle_c", "regrow": 300.0, "risk": 0.02, "name": "Barnacle Crust",
		"yields": {"shell_grit": 1},
		"hint": "", "start": "You get an edge under the crust.",
		"done": "A palmful of broken shell comes away with it.",
	}
	# Up the SE caisson's west face (leg spans x 19..25, z -15..-9).
	for spot in [Vector3(18.93, WET_Y + 0.35, -13.4), Vector3(18.93, WET_Y + 0.6, -12.0),
			Vector3(18.93, WET_Y + 0.2, -10.6)]:
		SALVAGE.from_visual(self, _crust_visual(true), spot, 0.0, def, 0.4)
	# And along the seaward lip by the dock, where the swell comes over.
	for spot in [Vector3(23.6, WET_Y + 0.06, -21.8), Vector3(10.6, WET_Y + 0.06, -21.8)]:
		SALVAGE.from_visual(self, _crust_visual(false), spot, 0.0, def, 0.4)

func _crust_visual(wall: bool) -> Node3D:
	var root := Node3D.new()
	for i in range(9):
		var mi := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.008 + fmod(i * 0.013, 0.012)
		cone.bottom_radius = 0.024 + fmod(i * 0.019, 0.018)
		cone.height = 0.03 + fmod(i * 0.011, 0.025)
		cone.material = _m_shell
		mi.mesh = cone
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var a: float = i * 2.399963
		var r: float = 0.035 + 0.02 * (i % 4)
		if wall:
			# Growing OUT of a vertical face: barnacles lie on their sides.
			mi.position = Vector3(0.012, cos(a) * r, sin(a) * r)
			mi.rotation.z = deg_to_rad(90.0)
		else:
			mi.position = Vector3(cos(a) * r, 0.015, sin(a) * r)
	return root

# ---- floats torn off someone else's gear and caught in our fenders ----

func _snagged_floats() -> void:
	var def := {
		"tools": [], "speed": ["crude_knife"], "verb": "CUT FREE", "work": 1.8,
		"sound": "hiss", "name": "Snagged Float",
		# The done-text has always said it comes away "still trailing a foot of someone
		# else's rope" — so it hands you the rope too. Untying a float on the wet deck is
		# one of the first things a player does; it should stock the first craft.
		"yields": {"float_buoy": 1, "rope": 1},
		"hint": "", "start": "You start working the line off the cleat.",
		"done": "The float comes free, still trailing a foot of someone else's rope.",
	}
	var tints := [Color(0.85, 0.32, 0.16), Color(0.9, 0.78, 0.2), Color(0.2, 0.45, 0.7)]
	var spots := [Vector3(16.6, WET_Y + 0.35, -21.9), Vector3(22.6, WET_Y + 0.35, -21.9),
			Vector3(24.8, WET_Y + 0.2, -21.6)]
	for i in range(spots.size()):
		SALVAGE.from_visual(self, _float_visual(tints[i]), spots[i], i * 55.0, def, 0.35)

func _float_visual(tint: Color) -> Node3D:
	var root := Node3D.new()
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.17
	sm.height = 0.36
	sm.material = MatLib.flat(tint)
	ball.mesh = sm
	root.add_child(ball)
	ball.position = Vector3(0, 0.17, 0)
	# The tail of line it came in on, coiled where it fell.
	var line := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.07
	tm.outer_radius = 0.11
	tm.material = MatLib.rope_mat()
	line.mesh = tm
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(line)
	line.position = Vector3(0.14, 0.02, 0.06)
	return root

# ---- kelp on the plates: the Bloom grows on anything that stays wet ----

func _kelp_growth() -> void:
	var def := {
		"tools": [], "speed": ["crude_knife"], "verb": "GATHER", "work": 1.6,
		"sound": "hiss", "regrow": 200.0, "name": "Kelp Growth",
		"yields": {"kelp_bundle": 1},
		"hint": "", "start": "",
		"done": "You strip an armful off the plate; it's cold and it faintly glows.",
	}
	# Kelp belongs in the SPLASH ZONE, not on the walking deck. These four sat at WET_Y
	# (the wet-deck floor, y2), so glowing fronds sprouted between the barrels underfoot
	# and read as teal slabs poking out from under the dressing. Moved down onto the
	# pontoon top (~y0.95) and the leg plates the sea actually wets, where they are still
	# reachable from the water's edge but look like growth instead of litter.
	for spot in [Vector3(28.8, 0.95, -20.4), Vector3(8.5, 0.95, -14.2),
			Vector3(28.9, 0.55, -1.4), Vector3(8.5, 0.55, -5.6)]:
		SALVAGE.from_visual(self, _kelp_visual(), spot, fmod(spot.z * 23.0, 360.0), def, 0.45)

func _kelp_visual() -> Node3D:
	var root := Node3D.new()
	for i in range(7):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05 + fmod(i * 0.017, 0.03), 0.02, 0.34 + fmod(i * 0.09, 0.26))
		bm.material = _m_kelp
		mi.mesh = bm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var a: float = i * 2.399963
		mi.position = Vector3(cos(a) * 0.07, 0.06 + (i % 3) * 0.05, sin(a) * 0.07)
		mi.rotation.y = a
		# Blades LEAN UP off the plate (55-80 deg) instead of lying flat: a frond reads
		# as growth, a flat slab reads as a dropped panel.
		mi.rotation.x = deg_to_rad(-55.0 - fmod(i * 17.0, 25.0))
	return root

# ---- the fish-cleaning board under the drying lines ----

func _cleaning_board() -> void:
	# Sits between the two hang lines strung at (13.0,-18.2) and (12.0,-20.5), on the
	# clear patch inside the drying-line posts at x 11.6 / 14.4.
	var def := {
		"tools": ["crude_knife"], "verb": "CLEAN", "work": 2.6,
		"sound": "hiss", "regrow": 300.0, "name": "Fish-Cleaning Board",
		"yields": {"fish_bone": 1},
		"hint": "the scraps are frozen to the board. A knife would lift them.",
		"start": "You set to work on what the last crew left.",
		"done": "You lift the frame clear of the board, picked clean.",
	}
	SALVAGE.from_visual(self, _board_visual(), Vector3(13.2, WET_Y, -19.4), 18.0, def, 0.6)

# ---- glow worm clusters: the Bloom's own light, and the deep rig's best bait ----
#
# NOT the same animal as bloom_fauna.GlowWorm. That one is a single skittish night-dweller
# that feels you coming and sinks into its den — you sneak up on it and GRAB it, one worm,
# once a night. This is the other half of the same species: the packed brood colonies that
# never leave the plate, in the permanently wet dark where nothing dries. You gather those
# by the handful, and the patch comes back.
#
# WHERE. Two habitats, both already proven clear of geometry by what is planted on them:
# the SE caisson's west face (the barnacle crust's own plane, x 18.93, at z values the
# crust does not use) and the wet-deck floor a metre off three of the colony's den mouths
# (bloom_fauna.GlowWormColony.DENS) — beside the dens, never on them, so the interaction
# ray is never choosing between a cluster and a live worm at the same point.
const GLOW_REGROW: float = 220.0   ## roughly a night-phase: the brood repopulates the patch

func _glowworm_clusters() -> void:
	var def := {
		"tools": [], "speed": [], "verb": "GATHER", "work": 1.4,
		"sound": "hiss", "regrow": GLOW_REGROW, "name": "Glow Worm Cluster",
		"yields": {"glow_worm": 1},   # re-rolled to 1-3 per growth — see GlowCluster below
		"hint": "", "start": "You cup a hand around the light.",
		"done": "They come away cold, curling, and still lit.",
	}
	# [position, is it growing out of a vertical face]
	var spots := [
		[Vector3(18.93, WET_Y + 0.45, -14.4), true],   # SE caisson west face, below the crust
		[Vector3(18.93, WET_Y + 0.8, -9.6), true],     # same face, up under the deck lip
		[Vector3(26.3, WET_Y, -5.0), false],           # stair-ramp shadow, off the den mouth
		[Vector3(17.7, WET_Y, -10.6), false],          # SE leg base, west of the steel
		[Vector3(11.5, WET_Y, -20.5), false],          # loot-room inner corner
	]
	for spot in spots:
		var vis := _glow_visual(bool(spot[1]), fmod(absf((spot[0] as Vector3).z) * 1.7, TAU))
		var node: Salvage = SALVAGE.from_visual(self, vis, spot[0],
			fmod((spot[0] as Vector3).x * 41.0, 360.0), def, 0.4)
		vis.bind(node)
		# Gathering a patch is also how a player who never crept up on a lone worm at night
		# learns what these are.
		node.interacted.connect(func(_v: String) -> void: Journal.discover("creature_glow_worm"))

## One patch: a dark wet smear of den mouths with the brood packed into it. Each cluster
## OWNS its material — MatLib.flat() and a shared local material would dim every patch on
## the rig the moment one of them was gathered.
func _glow_visual(wall: bool, phase: float) -> GlowCluster:
	var root := GlowCluster.new()
	root.phase = phase
	root.mat = StandardMaterial3D.new()
	root.mat.albedo_color = Color(0.16, 0.42, 0.4)
	root.mat.roughness = 0.55
	root.mat.emission_enabled = true
	root.mat.emission = Color(0.25, 0.95, 0.85)
	root.mat.emission_energy_multiplier = GlowCluster.LIT
	var damp := _mat(Color(0.06, 0.08, 0.08), 0.35)
	damp.metallic_specular = 0.8              # the wet patch they live in, catching light
	var patch := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.22
	pm.bottom_radius = 0.22
	pm.height = 0.015
	pm.material = damp
	patch.mesh = pm
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(patch)
	# The worms themselves: eleven short lit bodies at every angle out of the patch, so a
	# third of them coming off (Salvage._strip pulls meshes) still leaves a colony behind.
	for i in range(11):
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.018 + fmod(i * 0.007, 0.012)
		cm.height = 0.09 + fmod(i * 0.023, 0.08)
		cm.material = root.mat
		mi.mesh = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var a: float = i * 2.399963
		var r: float = 0.045 + 0.028 * (i % 4)
		mi.position = Vector3(cos(a) * r, 0.035 + fmod(i * 0.019, 0.05), sin(a) * r)
		# Curled over on the plate, not standing up like candles.
		mi.rotation = Vector3(deg_to_rad(52.0 + fmod(i * 21.0, 40.0)), a, 0.0)
	if wall:
		# Growing out of a vertical face: the whole patch lies on its side.
		root.rotation.z = deg_to_rad(90.0)
	return root

## The live half of a cluster. Salvage already hides parts, soots what is left and heals it
## all again on regrow, but soot cannot take the LIGHT out of an emissive body — a gathered
## patch would have kept glowing exactly as brightly with a third of its worms missing. So
## this eases the emission down to embers while the node is spent and brings it back up as
## the brood regrows, and it is also where the 1-3 yield lives: the count is re-rolled on
## every regrowth, which keeps the grant inside Salvage's all-or-nothing pack check instead
## of bolting extra add_item() calls onto the end of it.
class GlowCluster extends Node3D:
	const LIT: float = 1.15
	const EMBERS: float = 0.1
	const FADE: float = 0.55        ## how fast the light follows the state, energy/sec

	var mat: StandardMaterial3D
	var phase: float = 0.0
	var _node: Salvage
	var _level: float = LIT
	var _was_spent: bool = false
	## Salvage._strip() knocks a small prop askew and _restore() does not put it back, so a
	## renewable node would lean a little further every cycle. The patch remembers how it was
	## planted and sits back down when it grows in.
	var _base_rot: Vector3
	var _t: float = 0.0
	var _rng := RandomNumberGenerator.new()

	func bind(node: Salvage) -> void:
		_node = node
		_base_rot = rotation
		_rng.randomize()
		_reroll()

	func _reroll() -> void:
		if _node and is_instance_valid(_node):
			_node.yields = {"glow_worm": _rng.randi_range(1, 3)}

	func _process(delta: float) -> void:
		if mat == null:
			return
		_t += delta
		var spent: bool = _node != null and is_instance_valid(_node) and _node.spent
		if spent != _was_spent:
			_was_spent = spent
			if not spent:
				_reroll()   # the patch has grown back: a fresh handful is in it
				rotation = _base_rot
		_level = move_toward(_level, EMBERS if spent else LIT, delta * FADE)
		# The colony breathes even at rest — that slow swell is how you spot one in the dark.
		mat.emission_energy_multiplier = _level * (1.0 + 0.22 * sin(_t * 1.3 + phase))

func _board_visual() -> Node3D:
	var root := Node3D.new()
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.78, 0.05, 0.4)
	bm.material = MatLib.weathered_wood()
	board.mesh = bm
	root.add_child(board)
	board.position = Vector3(0, 0.06, 0)
	# Two trestle blocks under it, and the picked-over remains on top.
	for bx in [-0.28, 0.28]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.08, 0.08, 0.34)
		lm.material = MatLib.weathered_wood()
		leg.mesh = lm
		root.add_child(leg)
		leg.position = Vector3(bx, 0.02, 0)
	for i in range(5):
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.006
		cm.bottom_radius = 0.009
		cm.height = 0.13 + fmod(i * 0.031, 0.07)
		cm.material = _m_bone
		mi.mesh = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.position = Vector3(-0.18 + i * 0.09, 0.095, fmod(i * 0.07, 0.11) - 0.05)
		mi.rotation.z = deg_to_rad(90.0)
		mi.rotation.y = deg_to_rad(i * 24.0)
	return root
