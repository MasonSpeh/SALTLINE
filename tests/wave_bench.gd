extends Node
## WAVE MATH BENCH — is the Gerstner sum actually cheaper, and is it still the same sea?
##
## Gyre.wave_height() is the most-called function in the game: every school fish clamps
## against the surface once a frame (512 fish at present), plus the player, the rod, the
## hook, the debris, the storm and main.gd's underwater test. Optimising it is worth doing
## and is exactly the kind of change that can be silently wrong — a wave that is 1e-3 off
## still looks like a wave, and the CPU sea drifting away from the shader's sea is how
## floating debris ends up hanging over a trough.
##
## So this harness does BOTH halves, and refuses to report a timing it has not first proved
## correct: `_ref_offset` is the pre-optimisation implementation, kept verbatim, and every
## sample point is checked against it before any clock starts.
##
## Headless is correct here — this is arithmetic, nothing is drawn:
##   godot --headless --path . res://tests/WaveBench.tscn

const SAMPLES: int = 40000
const G_WAVE: float = 9.81

# --- the pre-optimisation implementation, kept verbatim as the reference ----------------
func _ref_offset(raw_p: Vector2, t: float, ss: float) -> Vector3:
	var w: Vector2 = Gyre._warp(raw_p, t)
	var amp_scale: float = 0.18 + 0.92 * ss
	var steep_scale: float = 0.35 + 0.65 * ss
	var gust: float = Gyre._patchiness(raw_p, t)
	var dx: float = 0.0
	var dz: float = 0.0
	var h: float = 0.0
	for i in range(11):
		var dir: Vector2 = Gyre.W_DIR[i]
		var k: float = TAU / Gyre.W_LEN[i]
		var omega: float = sqrt(G_WAVE * k)
		var a: float = Gyre.W_AMP[i] * amp_scale
		if i < 3:
			var sd: Vector2 = Gyre.SET_DIR_B if i == 1 else Gyre.SET_DIR_A
			var env: float = sd.dot(raw_p) * 0.010 - t * (0.045 + 0.02 * float(i))
			a *= 0.55 + 0.45 * sin(env)
		else:
			a *= gust
		var steep_eff: float = Gyre.W_STEEP[i] * steep_scale
		var qa: float = steep_eff / (k * 11.0)
		var phase: float = k * dir.dot(w) - omega * t
		var c: float = cos(phase)
		dx += qa * dir.x * c
		dz += qa * dir.y * c
		h += a * sin(phase)
	return Vector3(dx, h, dz)

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var pts: Array[Vector2] = []
	var ts: Array[float] = []
	for i in range(SAMPLES):
		pts.append(Vector2(rng.randf_range(-90.0, 90.0), rng.randf_range(-90.0, 90.0)))
		# Real elapsed clocks, not 0..1 — omega*t is where a precision regression would show.
		ts.append(rng.randf_range(0.0, 7200.0))

	# ---- correctness FIRST. A faster wrong sea is not a result. -------------------------
	var worst_h: float = 0.0
	var worst_o: float = 0.0
	for ss in [0.0, 0.4, 0.75, 1.0]:
		Gyre.set_sea_state(ss)
		for i in range(0, SAMPLES, 37):
			var ref: Vector3 = _ref_offset(pts[i], ts[i], ss)
			var got_o: Vector3 = Gyre.wave_offset(pts[i], ts[i])
			var got_h: float = Gyre.wave_height(pts[i], ts[i])
			worst_h = maxf(worst_h, absf(got_h - ref.y))
			worst_o = maxf(worst_o, (got_o - ref).length())
	# wave_offset must be EXACT — it returns a Vector3 either way, so nothing about its
	# precision changed. wave_height is allowed one float32 ULP and no more: it now returns
	# the accumulated double instead of the reference's Vector3-rounded component, and that
	# bound is what pins the difference to exactly that rounding rather than a real drift.
	var ulp: float = 2.0e-6
	print("[wave] max |wave_height - reference.y| = %.17f m  (float32 ULP bound %.17f)"
		% [worst_h, ulp])
	print("[wave] max |wave_offset - reference|   = %.17f m  (must be exactly 0)" % worst_o)
	if worst_h > ulp or worst_o > 0.0:
		print("[wave] FAIL — the optimised sea is not the reference sea. Timing withheld.")
		get_tree().quit(1)
		return

	# ---- and only then, the clock -------------------------------------------------------
	Gyre.set_sea_state(0.4)
	var sink: float = 0.0
	var t0: int = Time.get_ticks_usec()
	for i in range(SAMPLES):
		sink += _ref_offset(pts[i], ts[i], 0.4).y
	var ref_us: int = Time.get_ticks_usec() - t0

	t0 = Time.get_ticks_usec()
	for i in range(SAMPLES):
		sink += Gyre.wave_height(pts[i], ts[i])
	var new_us: int = Time.get_ticks_usec() - t0

	t0 = Time.get_ticks_usec()
	for i in range(SAMPLES):
		sink += Gyre.wave_offset(pts[i], ts[i]).y
	var off_us: int = Time.get_ticks_usec() - t0

	print("\n=========== WAVE MATH BENCH (%d samples) ===========" % SAMPLES)
	print("  before  (wave_offset().y, old body) : %7.3f us/call" % (float(ref_us) / SAMPLES))
	print("  after   (wave_height, height-only)  : %7.3f us/call   %.2fx" % [
		float(new_us) / SAMPLES, float(ref_us) / maxf(float(new_us), 1.0)])
	print("  after   (wave_offset, precomputed)  : %7.3f us/call   %.2fx" % [
		float(off_us) / SAMPLES, float(ref_us) / maxf(float(off_us), 1.0)])
	print("  trough floor (analytic, any sea state): %.3f m" % Gyre.trough_floor())
	print("  (sink %.3f — keeps the loops from being optimised away)" % sink)
	print("===================================================\n")
	get_tree().quit()
