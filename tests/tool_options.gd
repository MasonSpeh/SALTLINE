extends RefCounted
## FISHING-TOOL DESIGN OPTIONS, for the owner to choose from.
##
## Owner, 2026-07-29: "the deep sea rod looks weird, regenerate options" and "regenerate
## options for the main fishing rod, it should be skinnier/more". So neither tool gets another
## unilateral iteration — each gets a spread of genuinely different builds, rendered side by
## side (tests/OptionShot.tscn), and the owner picks. NOTHING here is installed.
##
## Everything is built with ItemVisual's own primitives and comment idiom, so the winner ports
## into that file's match statement verbatim. Every option plants the "hand_tip" marker at its
## real working end — player_controller.hand_tip_world() finds it BY NAME, and without it a
## silent _hand_reach_axis fallback anchors the fishing line in the player's fist.
##
## Triangle discipline is inherited too: _torus takes rings/ring_segments and _cyl takes
## segments, because six rings at Godot's default tessellation is 25k triangles inside a 96 px
## inventory icon.

const IV := preload("res://scripts/world/item_visual.gd")

## Every option, in the order the contact sheet lays them out.
const DEEP := ["deep_braced", "deep_winch", "deep_boatrod", "deep_spool"]
const RODS := ["rod_slim", "rod_fine", "rod_wand", "rod_trim"]

static func build(id: String) -> Node3D:
	var root := Node3D.new()
	match id:
		"deep_braced": _deep_braced(root)
		"deep_winch": _deep_winch(root)
		"deep_boatrod": _deep_boatrod(root)
		"deep_spool": _deep_spool(root)
		"rod_slim": _rod(root, _P_SLIM)
		"rod_fine": _rod(root, _P_FINE)
		"rod_wand": _rod(root, _P_WAND)
		"rod_trim": _rod(root, _P_TRIM)
	return root

## One-line description for the sheet's caption.
static func blurb(id: String) -> String:
	match id:
		"deep_braced": return "A: braced stand-up pole, drum on its side"
		"deep_winch": return "B: frame + crank winch, not a rod at all"
		"deep_boatrod": return "C: heavy tapered boat rod, lever-drag reel"
		"deep_spool": return "D: bare hand-line spool on a gimbal post"
		"rod_slim": return "1: 28>6 mm blank - one notch slimmer"
		"rod_fine": return "2: 23>4.5 mm blank, 7 fine guides"
		"rod_wand": return "3: 19>3 mm, 2.10 m, 8 guides - extreme"
		"rod_trim": return "4: 23>4.5 mm + low-profile reel, trimmed"
	return id

# ============================ the shared palette ============================
# Taken off the installed fishing_rod so every option reads as one man's kit, and pitched a
# little darker for the big flat areas (a 0.30 m disc at the sun renders far lighter than a
# 30 mm tube does — measured, not assumed).
const C_BLANK := Color(0.165, 0.175, 0.205)   # graphite blank / box section
const C_GRIP := Color(0.13, 0.12, 0.11)       # shrink-wrap rubber grip
const C_TAPE := Color(0.17, 0.16, 0.14)       # friction tape
const C_METAL := Color(0.30, 0.32, 0.35)      # gunmetal castings and weldments
const C_ALLOY := Color(0.40, 0.42, 0.45)      # machined alloy, seats, guides
const C_BRASS := Color(0.42, 0.33, 0.20)      # dull anodised levers
const C_WRAP := Color(0.32, 0.17, 0.14)       # oxblood thread wraps
const C_LINE := Color(0.36, 0.34, 0.30)       # salt-stiffened braid
const C_LEAD := Color(0.235, 0.245, 0.265)    # dull cast lead
const C_SALT := Color(0.50, 0.51, 0.48)       # salt crust / bare dragged steel
const C_RUST := Color(0.36, 0.25, 0.17)       # rust in the seams
const C_BLOOM := Color(0.22, 0.92, 0.86)      # a live Bloom cell as a lumo bead

static func _tip(host: Node3D, at: Vector3) -> void:
	var t := Node3D.new()
	t.name = "hand_tip"
	host.add_child(t)
	t.position = at

# ===================== shared sub-assemblies =====================

## The notched cup that drops into a fighting belt. Every deep option has one: it is the part
## that says "this is braced against a body and cranked", which is what 45 m of drop needs.
static func _gimbal(h: Node3D, y: float, r: float) -> void:
	IV._cyl(h, r, 0.05, C_METAL, Vector3(0, y + 0.025, 0), false, 1.0, 16)
	for n in [-1.0, 1.0]:
		IV._box(h, Vector3(r * 0.48, 0.032, r * 0.9), C_METAL.darkened(0.18),
			Vector3(n * r * 0.66, y - 0.012, 0))
	IV._cyl(h, r * 0.9, 0.028, C_SALT, Vector3(0, y + 0.062, 0), false, 1.0, 16)

## A ribbed rubber grip you can hold in a wet glove. `ribs` rings AROUND a vertical shaft.
static func _grip(h: Node3D, y0: float, len: float, r: float, ribs: int) -> void:
	IV._cyl(h, r, len, C_GRIP, Vector3(0, y0 + len * 0.5, 0), false, 1.0, 16)
	for i in range(ribs):
		var g := IV._torus(h, r - 0.002, r + 0.007, C_TAPE,
			Vector3(0, y0 + len * (float(i) + 0.5) / float(ribs), 0), 16, 6)
		g.rotation.x = 0.0

## Terminal tackle hove up short: swivel, torpedo lead, snooded hook, lumo bead. Hangs DOWN
## from `at`, in the plane z = at.z. Scaled by `s` so a small tool gets small tackle.
static func _tackle(h: Node3D, at: Vector3, s: float) -> void:
	var x: float = at.x
	var z: float = at.z
	IV._cyl(h, 0.005 * s, 0.034 * s, C_LINE, Vector3(x, at.y - 0.018 * s, z), false, 1.0, 8)
	var sw := IV._torus(h, 0.007 * s, 0.013 * s, C_ALLOY, Vector3(x, at.y - 0.040 * s, z), 12, 6)
	sw.rotation.x = 0.0
	IV._box(h, Vector3(0.030, 0.016, 0.011) * s, C_ALLOY.darkened(0.12),
		Vector3(x, at.y - 0.056 * s, z))
	IV._cyl(h, 0.005 * s, 0.054 * s, C_LINE, Vector3(x, at.y - 0.090 * s, z), false, 1.0, 8)
	IV._cone(h, 0.030 * s, 0.014 * s, 0.038 * s, C_LEAD, Vector3(x, at.y - 0.134 * s, z))
	IV._cyl(h, 0.030 * s, 0.056 * s, C_LEAD, Vector3(x, at.y - 0.181 * s, z), false, 1.0, 16)
	IV._cone(h, 0.010 * s, 0.030 * s, 0.040 * s, C_LEAD.darkened(0.10),
		Vector3(x, at.y - 0.228 * s, z))
	# Snood out to one side, then the hook. rotation.z sends a cylinder's +Y to (-sin, cos),
	# so 55.8° lays its axis along (-0.827, 0.562) — the trace from swivel out to hook eye.
	var sn := IV._cyl(h, 0.004 * s, 0.091 * s, C_LINE,
		Vector3(x + 0.038 * s, at.y - 0.083 * s, z), false, 1.0, 8)
	sn.rotation.z = deg_to_rad(55.8)
	var he := IV._torus(h, 0.006 * s, 0.011 * s, C_ALLOY,
		Vector3(x + 0.077 * s, at.y - 0.111 * s, z), 12, 6)
	he.rotation.x = 0.0
	IV._cyl(h, 0.005 * s, 0.048 * s, C_ALLOY, Vector3(x + 0.081 * s, at.y - 0.137 * s, z), false, 1.0, 8)
	var b1 := IV._box(h, Vector3(0.010, 0.022, 0.009) * s, C_ALLOY,
		Vector3(x + 0.083 * s, at.y - 0.169 * s, z))
	b1.rotation.z = deg_to_rad(30)
	var b2 := IV._box(h, Vector3(0.010, 0.022, 0.009) * s, C_ALLOY,
		Vector3(x + 0.068 * s, at.y - 0.182 * s, z))
	b2.rotation.z = deg_to_rad(72)
	var pt := IV._cyl(h, 0.004 * s, 0.026 * s, C_ALLOY.lightened(0.10),
		Vector3(x + 0.053 * s, at.y - 0.170 * s, z), false, 1.0, 8)
	pt.rotation.z = deg_to_rad(-16)
	IV._sph(h, 0.009 * s, C_BLOOM, Vector3(x + 0.053 * s, at.y - 0.095 * s, z),
		Vector3.ONE, true, 1.8)

# ================== DEEP OPTION A — braced stand-up pole ==================
## The middle of the road: a POLE you hold like a rod, short and stout, with a big drum bolted
## to its SIDE and one diagonal brace off the butt so the drum's load goes into the frame
## instead of into your wrists. Reads as fishing gear first and machinery second.
static func _deep_braced(h: Node3D) -> void:
	var p := Node3D.new()
	h.add_child(p)
	p.rotation.z = deg_to_rad(9)
	_gimbal(p, 0.0, 0.052)
	_grip(p, 0.10, 0.26, 0.046, 4)
	# The pole: a stout tapering shaft, not a casting blank — 44 mm to 20 mm over 1.1 m.
	IV._cone(p, 0.044, 0.034, 0.34, C_BLANK, Vector3(0, 0.55, 0))
	IV._cone(p, 0.034, 0.026, 0.30, C_BLANK, Vector3(0, 0.87, 0))
	IV._cone(p, 0.026, 0.020, 0.24, C_BLANK, Vector3(0, 1.14, 0))
	IV._cyl(p, 0.046, 0.022, C_ALLOY, Vector3(0, 0.375, 0), false, 1.0, 18)   # ferrule collar
	# The drum, axis ACROSS the pole, on a bracket standing off it. Undersized drive cheek so
	# the braid always shows as a pale ring instead of hiding behind a smooth disc.
	var dc := Vector3(-0.150, 0.545, 0)
	for s in [-1.0, 1.0]:
		IV._box(p, Vector3(0.190, 0.062, 0.015), C_METAL, Vector3(-0.070, 0.545, s * 0.140))
	var barrel := IV._cyl(p, 0.078, 0.190, C_METAL.darkened(0.20), dc, false, 1.0, 18)
	barrel.rotation.x = deg_to_rad(90)
	var wound := IV._cyl(p, 0.122, 0.168, C_LINE, dc, false, 1.0, 18)
	wound.rotation.x = deg_to_rad(90)
	for g in [-0.048, 0.012, 0.055]:
		IV._torus(p, 0.119, 0.124, C_LINE.darkened(0.26), dc + Vector3(0, 0, g), 18, 6)
	for s in [-1.0, 1.0]:
		var cr: float = 0.100 if s > 0.0 else 0.128
		var cheek := IV._cyl(p, cr, 0.015, C_METAL.darkened(0.16), dc + Vector3(0, 0, s * 0.090),
			false, 1.0, 22)
		cheek.rotation.x = deg_to_rad(90)
		IV._torus(p, cr - 0.004, cr + 0.008, C_METAL.darkened(0.36), dc + Vector3(0, 0, s * 0.099), 22, 8)
		var hub := IV._cyl(p, 0.030, 0.012, C_ALLOY.darkened(0.12), dc + Vector3(0, 0, s * 0.101),
			false, 1.0, 16)
		hub.rotation.x = deg_to_rad(90)
		var band := IV._cyl(p, cr * 0.60, 0.004, C_WRAP, dc + Vector3(0, 0, s * 0.098), false, 1.0, 20)
		band.rotation.x = deg_to_rad(90)
	for bo in range(6):
		var ba: float = bo * TAU / 6.0 + 0.3
		var blt := IV._cyl(p, 0.007, 0.010, C_ALLOY,
			dc + Vector3(cos(ba) * 0.078, sin(ba) * 0.078, 0.101), false, 1.0, 8)
		blt.rotation.x = deg_to_rad(90)
	# Crank, ratchet pawl, and a brake shoe on the rim.
	var boss := IV._cyl(p, 0.023, 0.028, C_ALLOY, dc + Vector3(0, 0, 0.128), false, 1.0, 14)
	boss.rotation.x = deg_to_rad(90)
	var arm := IV._box(p, Vector3(0.150, 0.028, 0.016), C_ALLOY, dc + Vector3(0.050, -0.050, 0.150))
	arm.rotation.z = deg_to_rad(-45)
	var knob := IV._cyl(p, 0.021, 0.055, C_GRIP.lightened(0.09),
		dc + Vector3(0.100, -0.100, 0.150), false, 1.0, 14)
	knob.rotation.x = deg_to_rad(90)
	var pawl := IV._box(p, Vector3(0.080, 0.013, 0.010), C_BRASS, dc + Vector3(0.052, 0.046, 0.108))
	pawl.rotation.z = deg_to_rad(-18)
	var shoe := IV._box(p, Vector3(0.100, 0.020, 0.180), C_BRASS.darkened(0.42),
		Vector3(-0.162, 0.688, 0))
	shoe.rotation.z = deg_to_rad(9)
	var blev := IV._box(p, Vector3(0.190, 0.022, 0.020), C_BRASS.darkened(0.14),
		Vector3(-0.072, 0.716, 0.062))
	blev.rotation.z = deg_to_rad(15)
	# The brace: butt collar out to the pole's mid-length. Nothing else in the four options
	# says "braced" as directly as one honest diagonal.
	var st := IV._box(p, Vector3(0.024, 0.560, 0.022), C_METAL, Vector3(0.083, 0.660, 0))
	st.rotation.z = deg_to_rad(-13.5)
	IV._box(p, Vector3(0.048, 0.060, 0.026), C_METAL.darkened(0.12), Vector3(0.030, 0.398, 0))
	# Three heavy roller guides + a roller tip. Big frames, small count: this is line under
	# 20 kg of drag, not a casting rod's delicate stack.
	for g2 in [[0.62, 0.036], [0.92, 0.026], [1.16, 0.019]]:
		var gy: float = g2[0]
		var gr: float = g2[1]
		var br: float = 0.044 - 0.024 * (gy - 0.38) / 0.98
		IV._cyl(p, br + 0.004, 0.030, C_WRAP, Vector3(0, gy, 0), false, 1.0, 16)
		IV._box(p, Vector3(0.010 + gr * 0.3, 0.012, 0.013), C_METAL,
			Vector3(br + (0.010 + gr * 0.3) * 0.5, gy, 0))
		var ring := IV._torus(p, gr, gr + 0.006, C_ALLOY,
			Vector3(br + 0.010 + gr * 0.3 + gr, gy, 0), 16, 8)
		ring.rotation.x = 0.0
		var rl := IV._cyl(p, gr * 0.7, 0.010, C_ALLOY.lightened(0.10),
			Vector3(br + 0.010 + gr * 0.3 + gr, gy, 0), false, 1.0, 10)
		rl.rotation.x = deg_to_rad(90)
	IV._sph(p, 0.011, C_METAL, Vector3(0, 1.26, 0))
	IV._box(p, Vector3(0.026, 0.014, 0.014), C_METAL, Vector3(0.013, 1.248, 0))
	var tr := IV._torus(p, 0.012, 0.020, C_ALLOY, Vector3(0.027, 1.262, 0), 16, 8)
	tr.rotation.x = 0.0
	var rol := IV._cyl(p, 0.010, 0.010, C_ALLOY.lightened(0.12), Vector3(0.027, 1.248, 0), false, 1.0, 10)
	rol.rotation.x = deg_to_rad(90)
	_tip(p, Vector3(0.027, 1.262, 0))

# ================== DEEP OPTION B — frame and crank winch ==================
## Not a rod at all: a deck winch you set down and crank, with the line leading over a hoop
## fairlead at the head. Deliberately SIMPLER than the version the owner saw — no davit arm,
## no sheave block, no standing-line run, fewer and bigger shapes.
static func _deep_winch(h: Node3D) -> void:
	var p := Node3D.new()
	h.add_child(p)
	p.rotation.z = deg_to_rad(-4)
	# Foot it stands on, and the mast.
	IV._box(p, Vector3(0.230, 0.028, 0.200), C_METAL, Vector3(0.005, 0.014, 0))
	IV._box(p, Vector3(0.240, 0.008, 0.210), C_RUST, Vector3(0.005, 0.004, 0))
	for b in [-1.0, 1.0]:
		IV._cyl(p, 0.018, 0.022, C_ALLOY, Vector3(-0.072, 0.034, b * 0.066), false, 1.0, 10)
	IV._box(p, Vector3(0.046, 0.014, 0.200), C_SALT, Vector3(0.100, 0.032, 0))
	IV._box(p, Vector3(0.086, 0.100, 0.120), C_METAL, Vector3(-0.004, 0.078, 0))
	IV._box(p, Vector3(0.070, 0.900, 0.070), C_BLANK, Vector3(0, 0.520, 0))
	IV._box(p, Vector3(0.056, 0.320, 0.010), C_RUST, Vector3(0, 0.480, -0.036))
	_grip(p, 0.150, 0.200, 0.052, 4)
	# One big drum. Bigger than option A's and lower on the frame, so the crank falls where a
	# hand naturally goes when the foot is on a deck.
	var dc := Vector3(-0.180, 0.500, 0)
	for s in [-1.0, 1.0]:
		IV._box(p, Vector3(0.230, 0.078, 0.018), C_METAL, Vector3(-0.082, 0.500, s * 0.160))
	var barrel := IV._cyl(p, 0.096, 0.230, C_METAL.darkened(0.20), dc, false, 1.0, 18)
	barrel.rotation.x = deg_to_rad(90)
	var wound := IV._cyl(p, 0.152, 0.200, C_LINE, dc, false, 1.0, 18)
	wound.rotation.x = deg_to_rad(90)
	for g in [-0.060, 0.010, 0.068]:
		IV._torus(p, 0.149, 0.154, C_LINE.darkened(0.26), dc + Vector3(0, 0, g), 18, 6)
	for s in [-1.0, 1.0]:
		var cr: float = 0.122 if s > 0.0 else 0.158
		var cheek := IV._cyl(p, cr, 0.018, C_METAL.darkened(0.16), dc + Vector3(0, 0, s * 0.108),
			false, 1.0, 22)
		cheek.rotation.x = deg_to_rad(90)
		IV._torus(p, cr - 0.005, cr + 0.009, C_METAL.darkened(0.36), dc + Vector3(0, 0, s * 0.119), 22, 8)
		var hub := IV._cyl(p, 0.036, 0.013, C_ALLOY.darkened(0.12), dc + Vector3(0, 0, s * 0.122),
			false, 1.0, 16)
		hub.rotation.x = deg_to_rad(90)
		var band := IV._cyl(p, cr * 0.60, 0.004, C_WRAP, dc + Vector3(0, 0, s * 0.119), false, 1.0, 20)
		band.rotation.x = deg_to_rad(90)
		var ax := IV._cyl(p, 0.020, 0.090, C_ALLOY, dc + Vector3(0, 0, s * 0.150), false, 1.0, 12)
		ax.rotation.x = deg_to_rad(90)
	for bo in range(6):
		var ba: float = bo * TAU / 6.0 + 0.3
		var blt := IV._cyl(p, 0.008, 0.010, C_ALLOY,
			dc + Vector3(cos(ba) * 0.094, sin(ba) * 0.094, 0.122), false, 1.0, 8)
		blt.rotation.x = deg_to_rad(90)
	var gear := IV._cyl(p, 0.062, 0.013, C_ALLOY.darkened(0.14), dc + Vector3(0, 0, 0.186),
		false, 1.0, 18)
	gear.rotation.x = deg_to_rad(90)
	for t in range(6):
		var ta: float = t * TAU / 6.0
		IV._box(p, Vector3(0.017, 0.018, 0.012), C_ALLOY.darkened(0.24),
			dc + Vector3(cos(ta) * 0.066, sin(ta) * 0.066, 0.186))
	var pawl := IV._box(p, Vector3(0.092, 0.014, 0.011), C_BRASS, dc + Vector3(0.058, 0.052, 0.186))
	pawl.rotation.z = deg_to_rad(-18)
	var boss := IV._cyl(p, 0.025, 0.030, C_ALLOY, dc + Vector3(0, 0, 0.212), false, 1.0, 14)
	boss.rotation.x = deg_to_rad(90)
	var arm := IV._box(p, Vector3(0.175, 0.030, 0.017), C_ALLOY, dc + Vector3(0.058, -0.058, 0.234))
	arm.rotation.z = deg_to_rad(-45)
	var knob := IV._cyl(p, 0.023, 0.062, C_GRIP.lightened(0.09),
		dc + Vector3(0.116, -0.116, 0.234), false, 1.0, 14)
	knob.rotation.x = deg_to_rad(90)
	var shoe := IV._box(p, Vector3(0.120, 0.022, 0.210), C_BRASS.darkened(0.42),
		Vector3(-0.192, 0.672, 0))
	shoe.rotation.z = deg_to_rad(9)
	var blev := IV._box(p, Vector3(0.215, 0.024, 0.022), C_BRASS.darkened(0.14),
		Vector3(-0.088, 0.706, 0.070))
	blev.rotation.z = deg_to_rad(15)
	var bpin := IV._cyl(p, 0.011, 0.030, C_ALLOY, Vector3(0.018, 0.734, 0.070), false, 1.0, 10)
	bpin.rotation.x = deg_to_rad(90)
	# One diagonal, and a bent HOOP fairlead at the head instead of a block — this is the whole
	# simplification: the line leaves over one loop of round bar.
	var st := IV._box(p, Vector3(0.026, 0.640, 0.024), C_METAL, Vector3(0.090, 0.640, 0))
	st.rotation.z = deg_to_rad(-11)
	IV._box(p, Vector3(0.052, 0.070, 0.028), C_METAL.darkened(0.12), Vector3(0.038, 0.336, 0))
	IV._box(p, Vector3(0.078, 0.062, 0.078), C_METAL, Vector3(0.004, 0.980, 0))
	var boom := IV._box(p, Vector3(0.170, 0.032, 0.038), C_METAL, Vector3(0.082, 1.000, 0))
	boom.rotation.z = deg_to_rad(11)
	var hoop := IV._torus(p, 0.026, 0.036, C_ALLOY, Vector3(0.168, 1.012, 0), 18, 8)
	hoop.rotation.x = 0.0                                        # the line drops through it
	_tackle(p, Vector3(0.168, 1.000, 0), 0.95)
	_tip(p, Vector3(0.168, 1.008, 0))

# ================== DEEP OPTION C — heavy tapered boat rod ==================
## The conventional answer, and the one that will read fastest: a real 1.65 m stand-up boat
## rod. Thick at the butt, five roller guides, and a lever-drag multiplier the size of a fist
## sat on top of the seat. Distinguished from the main rod by being SHORTER, much STOUTER and
## far more sparsely guided — a winching tool, not a casting one.
static func _deep_boatrod(h: Node3D) -> void:
	var p := Node3D.new()
	h.add_child(p)
	p.rotation.z = deg_to_rad(13)
	_gimbal(p, 0.0, 0.056)
	_grip(p, 0.10, 0.30, 0.048, 4)
	# Machined seat with knurled lock rings, then the reel on top of it.
	IV._cyl(p, 0.052, 0.180, C_ALLOY.darkened(0.18), Vector3(0, 0.500, 0), false, 1.0, 20)
	for l in [0.418, 0.582]:
		var lk := IV._torus(p, 0.051, 0.063, C_ALLOY.darkened(0.25), Vector3(0, l, 0), 16, 8)
		lk.rotation.x = 0.0
	IV._box(p, Vector3(0.052, 0.036, 0.096), C_METAL, Vector3(0.070, 0.494, 0))
	var rc := Vector3(0.156, 0.532, 0)
	var spool := IV._cyl(p, 0.058, 0.152, C_LINE, rc, false, 1.0, 20)
	spool.rotation.x = deg_to_rad(90)
	for s in [-1.0, 1.0]:
		var plate := IV._cyl(p, 0.090, 0.019, C_METAL, rc + Vector3(0, 0, s * 0.088), false, 1.0, 24)
		plate.rotation.x = deg_to_rad(90)
		IV._torus(p, 0.079, 0.093, C_METAL.darkened(0.28), rc + Vector3(0, 0, s * 0.098), 22, 8)
	for pl in range(3):
		var pa: float = pl * TAU / 3.0 + 0.6
		IV._box(p, Vector3(0.021, 0.021, 0.170), C_METAL.darkened(0.12),
			rc + Vector3(cos(pa) * 0.076, sin(pa) * 0.076, 0))
	var cam := IV._cyl(p, 0.026, 0.019, C_BRASS.darkened(0.2), rc + Vector3(0, 0, 0.108), false, 1.0, 14)
	cam.rotation.x = deg_to_rad(90)
	var lever := IV._box(p, Vector3(0.100, 0.021, 0.016), C_BRASS, rc + Vector3(0.036, 0.038, 0.116))
	lever.rotation.z = deg_to_rad(42)
	var stub := IV._cyl(p, 0.015, 0.058, C_ALLOY, rc + Vector3(0, 0, 0.134), false, 1.0, 12)
	stub.rotation.x = deg_to_rad(90)
	var arm := IV._box(p, Vector3(0.150, 0.027, 0.017), C_ALLOY, rc + Vector3(0.046, -0.046, 0.166))
	arm.rotation.z = deg_to_rad(-42)
	var knob := IV._cyl(p, 0.020, 0.052, C_GRIP.lightened(0.08), rc + Vector3(0.094, -0.094, 0.166),
		false, 1.0, 14)
	knob.rotation.x = deg_to_rad(90)
	# Long foregrip, then a genuinely thick blank: 40 mm at the ferrule down to 11 mm.
	IV._cone(p, 0.050, 0.042, 0.30, C_GRIP, Vector3(0, 0.740, 0))
	for f in range(3):
		var fr := IV._torus(p, 0.043 - f * 0.001, 0.052 - f * 0.001, C_TAPE,
			Vector3(0, 0.650 + f * 0.085, 0), 16, 6)
		fr.rotation.x = 0.0
	IV._cyl(p, 0.044, 0.022, C_ALLOY, Vector3(0, 0.895, 0), false, 1.0, 18)
	IV._cone(p, 0.040, 0.032, 0.26, C_BLANK, Vector3(0, 1.035, 0))
	IV._cone(p, 0.032, 0.024, 0.24, C_BLANK, Vector3(0, 1.285, 0))
	IV._cone(p, 0.024, 0.016, 0.20, C_BLANK, Vector3(0, 1.505, 0))
	IV._cone(p, 0.016, 0.011, 0.05, C_BLANK, Vector3(0, 1.630, 0))
	# Five roller guides, big to small, each a ring on a standoff over an oxblood wrap.
	for g in [[0.98, 0.048], [1.16, 0.038], [1.33, 0.030], [1.48, 0.023], [1.60, 0.017]]:
		var gy: float = g[0]
		var gr: float = g[1]
		var br: float = 0.040 - 0.029 * (gy - 0.90) / 0.75
		var post: float = 0.008 + gr * 0.26
		IV._cyl(p, br + 0.004, 0.032, C_WRAP, Vector3(0, gy, 0), false, 1.0, 16)
		IV._box(p, Vector3(post, 0.014, 0.015), C_METAL, Vector3(br + post * 0.5, gy, 0))
		var ring := IV._torus(p, gr, gr + 0.007, C_ALLOY, Vector3(br + post + gr, gy, 0), 16, 8)
		ring.rotation.x = 0.0
		var rl := IV._cyl(p, gr * 0.68, 0.011, C_ALLOY.lightened(0.10),
			Vector3(br + post + gr, gy, 0), false, 1.0, 10)
		rl.rotation.x = deg_to_rad(90)
	IV._sph(p, 0.011, C_METAL, Vector3(0, 1.655, 0))
	IV._box(p, Vector3(0.028, 0.014, 0.015), C_METAL, Vector3(0.014, 1.643, 0))
	var tr := IV._torus(p, 0.013, 0.021, C_ALLOY, Vector3(0.028, 1.658, 0), 16, 8)
	tr.rotation.x = 0.0
	var rol := IV._cyl(p, 0.011, 0.011, C_ALLOY.lightened(0.12), Vector3(0.028, 1.643, 0), false, 1.0, 10)
	rol.rotation.x = deg_to_rad(90)
	_tip(p, Vector3(0.028, 1.658, 0))

# ================== DEEP OPTION D — hand-line spool on a gimbal post ==================
## The minimal answer, and the most honest one for a hand-line: no reel seat, no guides, no
## gears. A gimbal post, one very large free-spinning spool across it that you strip line off
## by hand, a bell ring at the tip, and the tackle. Nine parts do the work of forty — the whole
## silhouette is POST plus BIG DISC, which is unmistakable at 74 px.
static func _deep_spool(h: Node3D) -> void:
	var p := Node3D.new()
	h.add_child(p)
	p.rotation.z = deg_to_rad(7)
	_gimbal(p, 0.0, 0.050)
	_grip(p, 0.10, 0.24, 0.044, 4)
	IV._cyl(p, 0.030, 0.640, C_BLANK, Vector3(0, 0.620, 0), false, 1.0, 18)     # the post
	IV._cyl(p, 0.036, 0.020, C_ALLOY, Vector3(0, 0.352, 0), false, 1.0, 18)
	IV._box(p, Vector3(0.024, 0.240, 0.008), C_RUST, Vector3(0, 0.560, -0.031))
	# The spool: two big cheeks on a hub, wound to nearly their edge. Axis ACROSS the post.
	var sc := Vector3(0, 0.560, 0)
	var hub := IV._cyl(p, 0.072, 0.156, C_METAL.darkened(0.20), sc, false, 1.0, 20)
	hub.rotation.x = deg_to_rad(90)
	var wound := IV._cyl(p, 0.148, 0.140, C_LINE, sc, false, 1.0, 20)
	wound.rotation.x = deg_to_rad(90)
	for g in [-0.044, 0.014, 0.050]:
		IV._torus(p, 0.145, 0.150, C_LINE.darkened(0.26), sc + Vector3(0, 0, g), 18, 6)
	for s in [-1.0, 1.0]:
		var cr: float = 0.126 if s > 0.0 else 0.164
		var cheek := IV._cyl(p, cr, 0.014, C_METAL.darkened(0.14), sc + Vector3(0, 0, s * 0.078),
			false, 1.0, 24)
		cheek.rotation.x = deg_to_rad(90)
		IV._torus(p, cr - 0.005, cr + 0.008, C_METAL.darkened(0.34), sc + Vector3(0, 0, s * 0.087), 24, 8)
		var band := IV._cyl(p, cr * 0.58, 0.004, C_WRAP, sc + Vector3(0, 0, s * 0.086), false, 1.0, 20)
		band.rotation.x = deg_to_rad(90)
		var boss := IV._cyl(p, 0.030, 0.014, C_ALLOY.darkened(0.10), sc + Vector3(0, 0, s * 0.090),
			false, 1.0, 16)
		boss.rotation.x = deg_to_rad(90)
	var axle := IV._cyl(p, 0.016, 0.230, C_ALLOY, sc, false, 1.0, 12)
	axle.rotation.x = deg_to_rad(90)
	# Two peg handles on the outer cheek — you spin it with a palm, not a crank.
	for pg in [-1.0, 1.0]:
		var peg := IV._cyl(p, 0.014, 0.048, C_GRIP.lightened(0.09),
			sc + Vector3(pg * 0.082, pg * 0.052, 0.106), false, 1.0, 12)
		peg.rotation.x = deg_to_rad(90)
	# A thumb bar across the cheeks is all the brake there is.
	var bar := IV._box(p, Vector3(0.150, 0.018, 0.190), C_BRASS.darkened(0.30), Vector3(-0.100, 0.708, 0))
	bar.rotation.z = deg_to_rad(-16)
	# Bell ring at the tip: the one fitting the line touches on its way over the side.
	IV._cyl(p, 0.032, 0.016, C_ALLOY, Vector3(0, 0.930, 0), false, 1.0, 18)
	var bell := IV._torus(p, 0.019, 0.032, C_ALLOY.lightened(0.08), Vector3(0, 0.952, 0), 20, 8)
	bell.rotation.x = 0.0
	IV._cyl(p, 0.005, 0.360, C_LINE, Vector3(0, 0.760, 0.034), false, 1.0, 8)   # standing line
	_tackle(p, Vector3(0, 0.944, 0), 1.0)
	_tip(p, Vector3(0, 0.948, 0))

# ============================ THE ROD FAMILY ============================
## Four points on one slenderness ladder, because "skinnier/more" is a dimension, not a
## redesign: the installed rod's architecture is kept (gimbal, butt grip, machined seat,
## lever-drag multiplier on top, foregrip, tapered blank, stepped roller guides, roller tip)
## and only the SECTIONS change — blank diameters, guide sizes, grip diameters, guide count,
## length, and on option 4 the reel itself.
##
## For scale: the installed rod is a 36 mm blank tapering to 7 mm over 1.90 m. A real stand-up
## offshore blank is 22-26 mm at the ferrule and 4-5 mm at the tip, which is what makes these
## look so much finer while still being the same tool.
const _P_SLIM := {
	"len": 1.90, "butt": 0.028, "tip": 0.006, "grip": 0.038, "fore": 0.040, "seat": 0.044,
	"guides": 6, "gbig": 0.044, "gsml": 0.012, "reel": "lever", "reel_s": 0.95,
}
const _P_FINE := {
	"len": 1.95, "butt": 0.023, "tip": 0.0045, "grip": 0.034, "fore": 0.035, "seat": 0.040,
	"guides": 7, "gbig": 0.036, "gsml": 0.010, "reel": "lever", "reel_s": 0.88,
}
const _P_WAND := {
	"len": 2.10, "butt": 0.019, "tip": 0.003, "grip": 0.031, "fore": 0.032, "seat": 0.037,
	"guides": 8, "gbig": 0.030, "gsml": 0.008, "reel": "lever", "reel_s": 0.84,
}
const _P_TRIM := {
	"len": 1.95, "butt": 0.023, "tip": 0.0045, "grip": 0.033, "fore": 0.034, "seat": 0.039,
	"guides": 7, "gbig": 0.032, "gsml": 0.009, "reel": "low", "reel_s": 0.86,
}

static func _rod(h: Node3D, q: Dictionary) -> void:
	var p := Node3D.new()
	h.add_child(p)
	p.rotation.z = deg_to_rad(14)
	var L: float = float(q["len"])
	var s: float = L / 1.90                       # station scale off the installed layout
	var bt: float = float(q["butt"])
	var tp: float = float(q["tip"])
	var gr0: float = float(q["grip"])
	var sea: float = float(q["seat"])
	var rs: float = float(q["reel_s"])
	# Gimbal, butt grip, machined seat — all trimmed with the blank so the whole rod is finer
	# rather than a thin stick with fat furniture on it.
	_gimbal(p, 0.0, gr0 + 0.010)
	IV._cyl(p, gr0, 0.37 * s, C_GRIP, Vector3(0, 0.235 * s, 0), false, 1.0, 16)
	for i in range(4):
		var rib := IV._torus(p, gr0 - 0.002, gr0 + 0.006, C_TAPE,
			Vector3(0, (0.115 + i * 0.075) * s, 0), 16, 6)
		rib.rotation.x = 0.0
	IV._cyl(p, sea, 0.18 * s, C_ALLOY.darkened(0.18), Vector3(0, 0.51 * s, 0), false, 1.0, 20)
	for l in [0.432, 0.588]:
		var lock := IV._torus(p, sea - 0.001, sea + 0.010, C_ALLOY.darkened(0.25),
			Vector3(0, l * s, 0), 16, 8)
		lock.rotation.x = 0.0
	if String(q["reel"]) == "low":
		_reel_low(p, Vector3(0.118 * rs / 0.86, 0.520 * s, 0), rs)
	else:
		_reel_lever(p, Vector3(0.142 * rs / 0.95, 0.535 * s, 0), rs)
	# Foregrip, ferrule, then four stacked tapering blank sections.
	IV._cone(p, float(q["fore"]) + 0.004, float(q["fore"]) - 0.004, 0.30 * s, C_GRIP,
		Vector3(0, 0.75 * s, 0))
	for f in range(3):
		var fr := IV._torus(p, float(q["fore"]) - 0.005, float(q["fore"]) + 0.003, C_TAPE,
			Vector3(0, (0.655 + f * 0.085) * s, 0), 16, 6)
		fr.rotation.x = 0.0
	IV._cyl(p, bt + 0.005, 0.02 * s, C_ALLOY, Vector3(0, 0.90 * s, 0), false, 1.0, 18)
	var segs := [[0.90, 1.20], [1.20, 1.48], [1.48, 1.72], [1.72, 1.90]]
	for i in range(4):
		var y0: float = float(segs[i][0])
		var y1: float = float(segs[i][1])
		IV._cone(p, _blank_r(y0, bt, tp), _blank_r(y1, bt, tp), (y1 - y0) * s,
			C_BLANK, Vector3(0, (y0 + y1) * 0.5 * s, 0))
	# Guides stepping down the blank. `gbig` to `gsml` over `guides` stations between 0.90 and
	# the tip; the posts and wraps scale with the ring so nothing is chunky on a fine blank.
	var n: int = int(q["guides"])
	for i in range(n):
		var t: float = float(i) / float(maxi(n - 1, 1))
		var gy: float = lerpf(1.00, 1.83, pow(t, 0.86))
		var gring: float = lerpf(float(q["gbig"]), float(q["gsml"]), pow(t, 0.75))
		var br: float = _blank_r(gy, bt, tp)
		var post: float = 0.004 + gring * 0.22
		IV._cyl(p, br + 0.0025, 0.026 * s, C_WRAP, Vector3(0, gy * s, 0), false, 1.0, 14)
		IV._box(p, Vector3(post, 0.010, 0.010), C_METAL, Vector3(br + post * 0.5, gy * s, 0))
		var ring := IV._torus(p, gring, gring + 0.0045, C_ALLOY,
			Vector3(br + post + gring, gy * s, 0), 16, 8)
		ring.rotation.x = 0.0
	# Roller tip.
	var tipy: float = 1.90 * s
	IV._sph(p, tp + 0.002, C_METAL, Vector3(0, tipy, 0))
	IV._box(p, Vector3(0.020, 0.010, 0.011), C_METAL, Vector3(0.010, tipy - 0.012 * s, 0))
	var tr := IV._torus(p, 0.008, 0.014, C_ALLOY, Vector3(0.020, tipy + 0.002, 0), 16, 8)
	tr.rotation.x = 0.0
	var rol := IV._cyl(p, 0.007, 0.008, C_ALLOY.lightened(0.12), Vector3(0.020, tipy - 0.012 * s, 0),
		false, 1.0, 10)
	rol.rotation.x = deg_to_rad(90)
	_tip(p, Vector3(0.020, tipy, 0))

## Blank radius at station `y` (in the installed rod's own 0.90-1.90 coordinates), linear from
## the ferrule to the tip. One function so the guide feet cannot drift off the blank the way
## hand-written per-guide radii did.
static func _blank_r(y: float, bt: float, tp: float) -> float:
	return lerpf(bt, tp, clampf((y - 0.90) / 1.00, 0.0, 1.0))

## A lever-drag multiplier: two machined side plates, a wide braid spool, frame pillars, thumb
## lever and an offset crank. `k` scales the whole reel so it can be trimmed with the blank
## while staying legible at 74 px, which is the one thing that must not shrink away.
static func _reel_lever(h: Node3D, at: Vector3, k: float) -> void:
	IV._box(h, Vector3(0.048, 0.032, 0.086) * k, C_METAL, at + Vector3(-0.075, -0.030, 0) * k)
	var spool := IV._cyl(h, 0.050 * k, 0.140 * k, C_LINE, at, false, 1.0, 18)
	spool.rotation.x = deg_to_rad(90)
	for s in [-1.0, 1.0]:
		var plate := IV._cyl(h, 0.078 * k, 0.017 * k, C_METAL, at + Vector3(0, 0, s * 0.081 * k),
			false, 1.0, 22)
		plate.rotation.x = deg_to_rad(90)
		IV._torus(h, 0.069 * k, 0.082 * k, C_METAL.darkened(0.25), at + Vector3(0, 0, s * 0.091 * k), 20, 8)
	for pl in range(3):
		var pa: float = pl * TAU / 3.0 + 0.6
		IV._box(h, Vector3(0.019, 0.019, 0.155) * k,
			C_METAL.darkened(0.12), at + Vector3(cos(pa) * 0.067, sin(pa) * 0.067, 0) * k)
	var cam := IV._cyl(h, 0.023 * k, 0.017 * k, C_BRASS.darkened(0.2),
		at + Vector3(0, 0, 0.096 * k), false, 1.0, 14)
	cam.rotation.x = deg_to_rad(90)
	var lever := IV._box(h, Vector3(0.090, 0.019, 0.014) * k, C_BRASS,
		at + Vector3(0.032, 0.034, 0.104) * k)
	lever.rotation.z = deg_to_rad(42)
	var stub := IV._cyl(h, 0.013 * k, 0.052 * k, C_ALLOY, at + Vector3(0, 0, 0.120 * k), false, 1.0, 12)
	stub.rotation.x = deg_to_rad(90)
	var arm := IV._box(h, Vector3(0.134, 0.025, 0.015) * k, C_ALLOY,
		at + Vector3(0.041, -0.041, 0.149) * k)
	arm.rotation.z = deg_to_rad(-42)
	var knob := IV._cyl(h, 0.018 * k, 0.048 * k, C_GRIP.lightened(0.08),
		at + Vector3(0.084, -0.084, 0.149) * k, false, 1.0, 14)
	knob.rotation.x = deg_to_rad(90)

## A LOW-PROFILE lever drag instead: the same mechanism in a narrow, wide-set frame that sits
## down on the seat rather than standing off it. Option 4's whole point — a rod that is fine
## everywhere, including its hardware.
static func _reel_low(h: Node3D, at: Vector3, k: float) -> void:
	IV._box(h, Vector3(0.044, 0.026, 0.078) * k, C_METAL, at + Vector3(-0.058, -0.026, 0) * k)
	var spool := IV._cyl(h, 0.040 * k, 0.126 * k, C_LINE, at, false, 1.0, 18)
	spool.rotation.x = deg_to_rad(90)
	for s in [-1.0, 1.0]:
		var plate := IV._cyl(h, 0.056 * k, 0.013 * k, C_METAL, at + Vector3(0, 0, s * 0.072 * k),
			false, 1.0, 22)
		plate.rotation.x = deg_to_rad(90)
		IV._torus(h, 0.048 * k, 0.059 * k, C_METAL.darkened(0.25), at + Vector3(0, 0, s * 0.080 * k), 20, 8)
	IV._box(h, Vector3(0.086, 0.020, 0.150) * k, C_METAL.darkened(0.10),
		at + Vector3(0.006, 0.050, 0) * k)                       # flat frame bridge over the spool
	var lever := IV._box(h, Vector3(0.074, 0.016, 0.013) * k, C_BRASS,
		at + Vector3(0.030, 0.026, 0.088) * k)
	lever.rotation.z = deg_to_rad(38)
	var stub := IV._cyl(h, 0.011 * k, 0.044 * k, C_ALLOY, at + Vector3(0, 0, 0.100 * k), false, 1.0, 12)
	stub.rotation.x = deg_to_rad(90)
	var arm := IV._box(h, Vector3(0.116, 0.021, 0.013) * k, C_ALLOY,
		at + Vector3(0.035, -0.035, 0.124) * k)
	arm.rotation.z = deg_to_rad(-42)
	var knob := IV._cyl(h, 0.015 * k, 0.040 * k, C_GRIP.lightened(0.08),
		at + Vector3(0.072, -0.072, 0.124) * k, false, 1.0, 14)
	knob.rotation.x = deg_to_rad(90)
