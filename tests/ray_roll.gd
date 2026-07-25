extends Node
## Proves the manta rays CRUISE LEVEL and bank only while turning — the behaviour the
## constant-lean version could not have, and that a single screenshot cannot show.
## Samples every ray's model roll and filtered turn rate over half a minute.
var _t := 0.0
var _next := 0.0
var _rays: Array = []
var _min := 99.0
var _max := -99.0
var _n := 0
var _lvl := 0
func _ready() -> void:
	add_child((load("res://scenes/Main.tscn") as PackedScene).instantiate())
func _process(d: float) -> void:
	_t += d
	if _t < 6.0: return
	if _rays.is_empty():
		for n in get_tree().root.find_children("*", "Node3D", true, false):
			if n.get("_roll") != null and n.get("_turn_smooth") != null and n.get("_band_y") != null:
				_rays.append(n)
		print("[ray] tracking %d glider rays" % _rays.size())
	if _t < _next: return
	_next = _t + 0.75
	var line := ""
	for r in _rays:
		if not is_instance_valid(r): continue
		var roll: float = float(r.get("_roll"))
		var turn: float = float(r.get("_turn_smooth"))
		_min = minf(_min, roll); _max = maxf(_max, roll); _n += 1
		if absf(roll) < 0.12: _lvl += 1
		line += "  roll %+6.2f (%+5.1f deg) turn %+5.2f |" % [roll, rad_to_deg(roll), turn]
	print("t=%5.1f %s" % [_t, line])
	if _t > 36.0:
		print("\n[ray] roll range over the run: %+.2f .. %+.2f rad  (%.0f deg .. %.0f deg)"
			% [_min, _max, rad_to_deg(_min), rad_to_deg(_max)])
		print("[ray] samples within +-7 deg of LEVEL: %d/%d (%.0f%%)" % [_lvl, _n, 100.0*_lvl/maxf(_n,1)])
		print("[ray] old behaviour for comparison: pinned at -0.40 rad (-23 deg), always, forever.")
		get_tree().quit()
