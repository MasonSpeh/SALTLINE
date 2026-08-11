extends Interactable
## THE ANCHORAGE AQUARIUM — the stocking hatch on the tank-top platform.
##
## The player stands at the feeding hatch with a fish selected on the hotbar and presses
## the verb; the fish goes into the tank and starts circling the coral core at its real
## landed size. Two owner rules, enforced here and said out loud:
##   * no single fish longer than 5 ft  -> "This Un's too big to fit."
##   * no more than 50 ft of fish total -> the tank is full.
##
## Lengths come from ItemVisual.fish_instance_length_m — the same weight->length relation
## the dropped-fish renderer uses, so the fish in the tank is exactly the fish you caught.
##
## Stock PERSISTS: SaveManager carries an "aquarium" key (stock_payload / restore_stock,
## the cat's save contract). The marker node in group "aquarium" carries the geometry;
## this node carries the rules.

const FISH_MODEL := preload("res://scripts/world/fish_model_lib.gd")
const IV := preload("res://scripts/world/item_visual.gd")

## 8 ft, up from 5 (owner: "increase max size"). Chosen against the water, not taste:
## the swim annulus between coral core (r ~2.0) and glass margin (r 4.7) is 2.7 m wide,
## and an 8 ft fish still gets better than one body length of lane width and a 21 m
## mid-lane circumference — believable cruising; a 10 ft fish would fill its own lane.
const MAX_ONE_M: float = 2.4384   ## 8 ft
const MAX_TOTAL_M: float = 30.48   ## 100 ft (owner, s59)

## Set by the builder before add_child — the WATER volume, world space.
var tank_centre: Vector3 = Vector3.ZERO
var tank_r: float = 4.5
var water_y0: float = 0.0
var water_y1: float = 1.0

var _stock: Array = []      ## [{"id": String, "kg": float, "len": float}]
var _swimmers: Array = []   ## [{"node": Node3D, "r": float, "h": float, "w": float, "ang": float, "bob": float}]
var _total_m: float = 0.0
var _t: float = 0.0          ## shared swim clock — schooling species wander on it together

func _ready() -> void:
	display_name = "Aquarium Hatch"
	verbs = ["ADD FISH"] as Array[String]
	add_to_group("aquarium_hatch")
	build_box_visual(Vector3(0.9, 0.5, 0.9), COLOR_OPERABLE, false, false, MatLib.dark_metal())

## ---- save round-trip (SaveManager's "aquarium" key) -------------------------------

func stock_payload() -> Array:
	return _stock.duplicate(true)

## Idempotent full replace: clears the live tank, then re-adds every remembered fish
## through the same bookkeeping the hatch uses, so limits, totals and swimmer lanes are
## re-derived rather than trusted from the file.
func restore_stock(arr: Array) -> void:
	for s in _swimmers:
		var n: Node3D = s.get("node")
		if is_instance_valid(n):
			n.queue_free()
	_swimmers.clear()
	_stock.clear()
	_total_m = 0.0
	for e in arr:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id: String = String((e as Dictionary).get("id", ""))
		if not id.begins_with("fish_"):
			continue
		var kg: float = float((e as Dictionary).get("kg", 0.0))
		var len_m: float = _len_of(id, kg)
		if len_m > MAX_ONE_M or _total_m + len_m > MAX_TOTAL_M:
			continue
		_stock.append({"id": id, "kg": kg, "len": len_m})
		_total_m += len_m
		_spawn_swimmer(id, len_m)

func get_prompt() -> String:
	return "ADD FISH  Aquarium  (%.0f/%.0f ft stocked)" % [_total_m * 3.281, MAX_TOTAL_M * 3.281]

func interact(_verb: String, _player: Node3D) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var idx: int = PlayerState.selected_hotbar
	if idx < 0 or idx >= PlayerState.hotbar.size() or PlayerState.hotbar[idx] == null:
		if hud != null:
			hud.toast("Hold a fish on the hotbar to add it.")
		return
	var id: String = String(PlayerState.hotbar[idx])
	if not id.begins_with("fish_"):
		if hud != null:
			hud.toast("Only fish go in the tank.")
		return
	var kg: float = float(PlayerState.as_meta(PlayerState.hotbar_meta[idx]).get("kg", 0.0))
	var len_m: float = _len_of(id, kg)
	if len_m > MAX_ONE_M:
		if hud != null:
			hud.toast("This Un's too big to fit.")
		return
	if _total_m + len_m > MAX_TOTAL_M:
		if hud != null:
			hud.toast("The tank's full up — %.0f ft of fish already home." % (_total_m * 3.281))
		return
	var got: Dictionary = PlayerState.take_one_at(idx)
	if not bool(got.get("ok", false)):
		return
	_stock.append({"id": id, "kg": kg, "len": len_m})
	_total_m += len_m
	_spawn_swimmer(id, len_m)
	if hud != null:
		hud.toast("She slips in and circles the coral. (%.0f/%.0f ft)" % [_total_m * 3.281, MAX_TOTAL_M * 3.281])
	interacted.emit("ADD FISH")

## The length a fish OCCUPIES in the tank. fish_instance_length_m needs a size_kg range
## and 36 of the roster's species do not carry one — for those it returns 0.0, which made
## the 5 ft / 50 ft limits VACUOUS for most of the roster: a zero-length fish always fits
## and never spends budget (found by the s56 save probe writing "len": 0.0 to disk).
## Fall back to the authored species length, which every species has.
func _len_of(id: String, kg: float) -> float:
	var l: float = IV.fish_instance_length_m(id, kg)
	return l if l > 0.0 else IV.fish_length_m(id)

func _spawn_swimmer(item_id: String, len_m: float) -> void:
	var species: String = FISH_MODEL.species_of(item_id)
	if not FISH_MODEL.has_model(species):
		return
	var body: Node3D = FISH_MODEL.build(species, false, maxf(len_m, 0.15))
	get_parent().add_child(body)
	var n: int = _swimmers.size()
	# An AGENT, not a lane (s59): position + velocity + a per-fish wander phase. The old
	# swimmers rode fixed cos/sin rings — the owner's "circles" — and look_at aimed -Z at
	# the travel direction while the models face +Z, so every fish also swam TAIL-FIRST.
	var a0: float = fmod(float(n) * 2.4, TAU)
	var r0: float = clampf(2.6 + fmod(float(n) * 0.83, 1.0) * (tank_r - 3.4), 2.3, tank_r - 0.8)
	var p0 := Vector3(tank_centre.x + cos(a0) * r0,
		lerpf(water_y0 + 1.2, water_y1 - 1.2, fmod(float(n) * 0.37 + 0.15, 1.0)),
		tank_centre.z + sin(a0) * r0)
	body.global_position = p0
	_swimmers.append({"node": body, "species": species, "len": maxf(len_m, 0.15),
		"vel": Vector3(-sin(a0), 0, cos(a0)) * 0.3, "ph": float(n) * 1.7})

func _process(delta: float) -> void:
	# REAL SWIMMING (s59). Wander + species schooling + structure preference, steered with
	# bounded accelerations — no fixed rings. Cheap on purpose: O(n^2) over tank counts
	# (<= ~40 fish at the 100 ft cap), one pass, no physics queries — the glass and the
	# coral core are analytic cylinders.
	var n_fish: int = _swimmers.size()
	if n_fish == 0:
		return
	var dt: float = minf(delta, 0.05)
	_t += dt
	var r_glass: float = tank_r - 0.75      # soft margin inside the glass
	var r_core: float = 2.05                # coral core clearance (max rock r 1.7 + margin)
	var y_lo: float = water_y0 + 0.9
	var y_hi: float = water_y1 - 0.9
	for i in range(n_fish):
		var s_i: Dictionary = _swimmers[i]
		var node: Node3D = s_i["node"]
		if not is_instance_valid(node):
			continue
		var pos: Vector3 = node.global_position
		var vel: Vector3 = s_i["vel"]
		var L: float = float(s_i["len"])
		var big: bool = L > 0.8
		s_i["ph"] = float(s_i["ph"]) + dt
		var ph: float = float(s_i["ph"])
		var acc := Vector3.ZERO
		# WANDER. A solitary/big fish wanders on its own clock; a schooling-size fish
		# wanders mostly on its SPECIES' shared clock with a small personal jitter — the
		# shoal then drifts as one body (the alignment force only has to correct the
		# jitter, not four divergent solo paths; measured 0.40 -> gate 0.5+ mean pairwise).
		var sph: float = _t + float(String(s_i["species"]).hash() % 97)
		if big:
			acc += Vector3(sin(ph * 0.53), sin(ph * 0.37 + 2.1), cos(ph * 0.47)) * 0.22
		else:
			acc += Vector3(sin(sph * 0.43), sin(sph * 0.31 + 2.1), cos(sph * 0.39)) * 0.34
			acc += Vector3(sin(ph * 0.9), sin(ph * 0.7 + 1.0), cos(ph * 0.8)) * 0.10
		# STRUCTURE PREFERENCE — big fish cruise the open mid-lane in slow arcs; small
		# fish hug the core and the reef bed.
		var rad: Vector3 = pos - tank_centre
		rad.y = 0.0
		var r_now: float = rad.length()
		var r_dir: Vector3 = rad / maxf(r_now, 0.001)
		var r_want: float = lerpf(r_core + 0.5, r_glass - 0.4, 0.7 if big else 0.25)
		acc += r_dir * clampf(r_want - r_now, -1.0, 1.0) * 0.5
		var y_want: float = lerpf(y_lo, y_hi, 0.55 if big else 0.3)
		acc.y += clampf(y_want - pos.y, -1.0, 1.0) * (0.2 if big else 0.35)
		# SCHOOLING — same species only: align + cohere + separate.
		var mates: int = 0
		var c_sum := Vector3.ZERO
		var v_sum := Vector3.ZERO
		for j in range(n_fish):
			if j == i:
				continue
			var s_j: Dictionary = _swimmers[j]
			var node_j: Node3D = s_j["node"]
			if not is_instance_valid(node_j):
				continue
			var d_ij: Vector3 = node_j.global_position - pos
			var dist: float = d_ij.length()
			if dist < maxf(L, float(s_j["len"])) * 0.9 + 0.12 and dist > 0.001:
				acc -= d_ij / dist * (1.6 / maxf(dist, 0.15))       # separation, any species
			if String(s_j["species"]) == String(s_i["species"]) and dist < 2.2:
				mates += 1
				c_sum += d_ij
				v_sum += s_j["vel"]
		if mates > 0 and not big:
			acc += (c_sum / float(mates)) * 0.4                     # cohesion
			acc += ((v_sum / float(mates)) - vel) * 1.5             # alignment
		# HARD BOUNDS — the glass, the core, the surface and the bed, as analytic pushes
		# that grow smoothly so nothing ever pings off a wall.
		if r_now > r_glass:
			acc -= r_dir * (r_now - r_glass) * 6.0
		elif r_now < r_core:
			acc += r_dir * (r_core - r_now) * 6.0
		if pos.y > y_hi:
			acc.y -= (pos.y - y_hi) * 5.0
		elif pos.y < y_lo:
			acc.y += (y_lo - pos.y) * 5.0
		# INTEGRATE, speed shaped by size: small fish dart, big fish cruise.
		vel += acc * dt * 1.6
		var v_max: float = clampf(0.9 - L * 0.18, 0.35, 0.85)
		var v_min: float = 0.12
		var sp: float = vel.length()
		if sp > v_max:
			vel = vel * (v_max / sp)
		elif sp < v_min:
			vel = (vel / maxf(sp, 0.001)) * v_min
		s_i["vel"] = vel
		pos += vel * dt
		# Absolute clamp — the gates measure the drawn fish, so the drawn fish obeys.
		var rad2: Vector3 = pos - tank_centre
		rad2.y = 0.0
		var rn2: float = rad2.length()
		if rn2 > tank_r - 0.55:
			pos = tank_centre + rad2 * ((tank_r - 0.55) / rn2) + Vector3(0, pos.y - tank_centre.y, 0) * 0.0
			pos.y = node.global_position.y + vel.y * dt
		pos.y = clampf(pos.y, water_y0 + 0.6, water_y1 - 0.6)
		node.global_position = pos
		# FACE THE TRAVEL, head first: models face +Z (FishModelLib), Basis.looking_at
		# aims -Z at its target, so look at the REVERSE of the velocity — the old look_at
		# along +tangent is exactly why every stocked fish swam tail-first. Eased, with a
		# touch of bank in the turn.
		if vel.length() > 0.05:
			var fwd: Vector3 = vel.normalized()
			var want: Basis = Basis.looking_at(-fwd, Vector3.UP)
			node.global_transform.basis = node.global_transform.basis.slerp(want, 1.0 - exp(-6.0 * dt)).orthonormalized()
