extends Node
## Runs the REAL placement audit (tests/placement_probe.gd, unmodified) against the real
## Main. exterior_dress.gd is now wired into rig_builder.gd in production, so this harness
## no longer injects it — the dressing is already in the scene Main.tscn builds. The
## harness is kept as a convenience that can also run the label/light audits by arg.
##
## Run: godot --headless --path . res://tests/ExteriorDressProbe.tscn [-- label|light]
## (no arg = the placement audit).

const PROBES := {
	"placement": "res://tests/placement_probe.gd",
	"label": "res://tests/label_anchor_probe.gd",
	"light": "res://tests/light_anchor_probe.gd",
}

func _ready() -> void:
	var which: String = "placement"
	for arg in OS.get_cmdline_user_args():
		if PROBES.has(arg):
			which = arg
	print("[exterior dress] running %s probe (exterior_dress.gd now in production Main)" % which)
	add_child(load(PROBES[which]).new())
