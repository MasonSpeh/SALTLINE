#!/usr/bin/env python3
"""Synthesize SALTLINE's rain beds — a heavy, RELAXING downpour, not TV static.

Three seamless, click-free loops the game crossfades by how sheltered the player
is (see scripts/world/rain_audio.gd):

  rain_open.wav   full rich downpour: layered pink/brown noise (one-pole filtered
                  white), rolled off above ~5 kHz so there is no harsh sizzle,
                  with a slow gust undulation.
  rain_metal.wav  a CLOSE THIN-STEEL ROOF: a bright, thin, low-cut spray bed with
                  real damped-resonant PING transients on top — individual drops
                  you can pick out by ear, each an inharmonic 2-6 partial strike
                  (1.2-5 kHz, 15-80 ms decay) fired at a Poisson ~14 strikes/s.
  rain_far.wav    heavily low-passed (<=~450 Hz) distant rumble wash — the muffled
                  rain heard from deep under the huge deck platform.

Also rewrites rain_loop.wav (the old harsh AudioDirector bed) as short silence so
that bed stops contributing; rain_audio.gd owns all rain now.

Pure stdlib (numpy unavailable): wave / struct / math / random / cmath. 44.1 kHz
mono 16-bit. Loops are click-free by crossfading a 2 s tail back into the head.

USAGE — writes ONLY the targets you name; the default is `metal`:

    python3 scripts/synth_rain.py               # rain_metal.wav only
    python3 scripts/synth_rain.py metal open    # explicit targets
    python3 scripts/synth_rain.py --all         # everything (see warning below)
    python3 scripts/synth_rain.py --verify      # measure the wavs on disk

WARNING: rain_open.wav and rain_far.wav on disk are VERIFIED artifacts. `open` is
reproducible bit-for-bit (it owns Random(73) and is the first consumer of it), but
`far` now draws from its own generator, so regenerating it yields a different —
statistically identical, still valid — noise realization than the verified file.
Don't regenerate `far` unless you intend to re-verify it.
"""
import cmath
import math
import os
import random
import struct
import sys
import wave

SR = 44100
XF = int(SR * 2.0)         # crossfade length folded back into the head
AUDIO_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "audio"))

# rain_open's measured RMS; rain_metal is matched to it so the crossfade in
# rain_audio.gd doesn't pump. Read from the real file when it's present.
OPEN_RMS_FALLBACK = 0.2093


# --- primitives --------------------------------------------------------------

def alpha_for(fc: float) -> float:
	"""One-pole low-pass coefficient for a -3 dB corner at fc Hz."""
	return 1.0 - math.exp(-2.0 * math.pi * fc / SR)


def white(rng: random.Random, n: int) -> list:
	r = rng.random
	return [r() * 2.0 - 1.0 for _ in range(n)]


def lowpass(sig: list, alpha: float) -> list:
	out = [0.0] * len(sig)
	p = 0.0
	for i, s in enumerate(sig):
		p += alpha * (s - p)
		out[i] = p
	return out


def highpass(sig: list, fc: float, poles: int = 1) -> list:
	"""Complement of the one-pole low-pass, cascaded for a steeper skirt."""
	out = sig
	for _ in range(poles):
		lo = lowpass(out, alpha_for(fc))
		out = [a - b for a, b in zip(out, lo)]
	return out


def lowpass_n(sig: list, fc: float, poles: int = 1) -> list:
	out = sig
	for _ in range(poles):
		out = lowpass(out, alpha_for(fc))
	return out


def slow_env(rng: random.Random, n: int, fc: float, lo: float, hi: float) -> list:
	"""A gentle sub-Hz amplitude undulation normalised into [lo, hi]."""
	g = lowpass(white(rng, n), alpha_for(fc))
	m = max(1e-9, max(abs(x) for x in g))
	return [lo + (hi - lo) * (0.5 + 0.5 * (x / m)) for x in g]


def seamless(sig: list) -> list:
	"""Fold the trailing XF samples into the head so the loop is click-free.

	out[0] == sig[n], so the wrap from out[n-1] to out[0] is sample-continuous,
	and the very end of the tail carries ~zero weight — a strike truncated at the
	buffer end can't click.
	"""
	n = len(sig) - XF
	out = sig[:n]
	for i in range(XF):
		f = i / XF
		out[i] = sig[i] * f + sig[n + i] * (1.0 - f)
	return out


def rms(sig: list) -> float:
	return math.sqrt(sum(s * s for s in sig) / max(1, len(sig)))


def normalize(sig: list, peak: float) -> list:
	m = max(1e-9, max(abs(s) for s in sig))
	g = peak / m
	return [s * g for s in sig]


def soft_clip(x: float, ceil: float) -> float:
	"""Smooth, monotone, hard-bounded by `ceil`. Only the loudest ping tips reach
	it, so it rounds those rather than letting them square off into 16-bit."""
	knee = 0.72 * ceil
	a = abs(x)
	if a <= knee:
		return x
	return math.copysign(knee + (ceil - knee) * math.tanh((a - knee) / (ceil - knee)), x)


def match_rms(sig: list, target: float, ceil: float = 0.985) -> list:
	"""Scale to `target` RMS through the soft clipper (iterated, since clipping
	pulls the RMS back down)."""
	g = target / max(1e-9, rms(sig))
	out = sig
	for _ in range(8):
		out = [soft_clip(g * s, ceil) for s in sig]
		r = rms(out)
		if abs(20.0 * math.log10(max(1e-9, r) / target)) < 0.05:
			break
		g *= target / max(1e-9, r)
	return out


def read_wav(path: str):
	with wave.open(path, "rb") as w:
		n, sr, ch, sw = w.getnframes(), w.getframerate(), w.getnchannels(), w.getsampwidth()
		raw = w.readframes(n)
	vals = struct.unpack("<%dh" % (len(raw) // 2), raw)
	if ch == 2:
		vals = vals[0::2]
	return [v / 32768.0 for v in vals], sr, ch, sw


def write_wav(name: str, sig: list) -> None:
	path = os.path.join(AUDIO_DIR, name + ".wav")
	with wave.open(path, "w") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(SR)
		w.writeframes(
			b"".join(
				struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in sig
			)
		)
	print("%s.wav  (%.1fs, %d frames, rms %.4f, peak %.3f)"
	      % (name, len(sig) / SR, len(sig), rms(sig), max(abs(s) for s in sig)))


def open_rms() -> float:
	"""rain_open's real RMS if the file is there, else the recorded constant."""
	path = os.path.join(AUDIO_DIR, "rain_open.wav")
	if os.path.exists(path):
		try:
			sig, sr, _, sw = read_wav(path)
			if sr == SR and sw == 2:
				return rms(sig)
		except Exception as exc:                      # pragma: no cover
			print("  (could not read rain_open.wav: %s)" % exc)
	return OPEN_RMS_FALLBACK


# --- rain_open ---------------------------------------------------------------

def rain_bed(rng: random.Random, n: int, bright: float) -> list:
	"""A downpour bed: airy top rolled off ~5 kHz + mid 'shhh' + low wash, all from
	filtered white noise so there is no harsh differentiated high end."""
	top = lowpass(white(rng, n), alpha_for(5200.0))    # gentle roll-off, relaxing
	body = lowpass(white(rng, n), alpha_for(1400.0))   # the broadband hiss of the fall
	wash = lowpass(white(rng, n), alpha_for(300.0))    # low body so it feels heavy
	env = slow_env(rng, n, 0.35, 0.62, 1.08)
	a_top = 0.42 + 0.18 * bright
	return [
		(a_top * top[i] + 0.42 * body[i] + 0.50 * wash[i]) * env[i]
		for i in range(n)
	]


def make_open() -> list:
	# Seeded and ordered exactly as the original script so this stays bit-identical
	# to the verified rain_open.wav on disk. Don't reorder the draws.
	rng = random.Random(73)
	n = int(SR * 12.0) + XF
	return normalize(seamless(rain_bed(rng, n, 0.0)), 0.86)


# --- rain_metal --------------------------------------------------------------

METAL_DUR = 15.0            # longer than the others: distinct pings make a short
                            # loop's repetition easy to hear
METAL_RATE = 14.0           # strikes per second (Poisson)

# Plate modes of the roof panel. Every strike is drawn from these (with jitter) so
# the whole loop reads as ONE sheet of steel being hit in different places.
PANEL_MODES = (1280.0, 1690.0, 2150.0, 2760.0, 3450.0, 4300.0)
# Inharmonic partial ratios — deliberately not integers; that's what makes a
# struck plate read as metal rather than as a pitched tone.
PARTIAL_RATIOS = (1.0, 1.71, 2.43, 3.16, 4.05, 5.12)


def metal_bed(rng: random.Random, n: int) -> list:
	"""The noise bed UNDER the pings: bright spray, thin body, low cut.

	A thin steel roof has no weight to it — the deep wash that makes rain_open feel
	heavy is gone, replaced by high-frequency splatter. Deliberately restrained in
	1.5-4 kHz so the pings own that band and stay individually audible.
	"""
	# Splatter: band-limited ~3.5-11 kHz. This is the bulk of the sound. Rolled off
	# hard up top — dumping energy into the top octave would buy spectral centroid
	# with content nobody can hear, and reads as brittle hiss on real speakers.
	spray = highpass(lowpass_n(white(rng, n), 12000.0, 3), 4600.0, 3)
	# Air above the spray — the fine hiss of drops shattering on steel.
	air = highpass(lowpass_n(white(rng, n), 13000.0, 3), 7500.0, 2)
	# The sheet's own mid voice. Kept quiet and narrow: this is the band the pings
	# live in, and it has to stay clear enough for them to punch through it.
	sheet = highpass(lowpass_n(white(rng, n), 2400.0, 3), 1150.0, 2)
	# The panel's low voice — a steel sheet does drum, so it isn't weightless. Kept
	# NARROW rather than merely quiet: a tight 350-850 Hz band is audible as roof
	# drumming while occupying few enough bins that it doesn't drag the whole sound
	# dark. A thin roof has no real bottom to it either way.
	body = highpass(lowpass_n(white(rng, n), 850.0, 3), 350.0, 2)
	thud = lowpass_n(white(rng, n), 240.0, 2)
	env = slow_env(rng, n, 0.35, 0.66, 1.10)
	return [
		(2.40 * spray[i] + 2.05 * air[i] + 0.30 * sheet[i]
		 + 0.62 * body[i] + 0.30 * thud[i]) * env[i]
		for i in range(n)
	]


def add_strike(buf: list, idx: int, rng: random.Random, amp: float,
               f0: float, decay_s: float, partials: int) -> None:
	"""One damped inharmonic resonant strike, rendered with a decaying phasor
	(r^k * sin(wk)) so there's no per-sample sin() call."""
	n = len(buf)
	# 0.35 ms raised-cosine attack: kills the onset DC step (a click) while keeping
	# the snap. Anything longer smears the transient.
	atk = max(2, int(SR * 0.00035))
	for p in range(partials):
		ratio = PARTIAL_RATIOS[p] * rng.uniform(0.985, 1.015)   # slight inharmonicity
		f = f0 * ratio
		if f >= SR * 0.47:
			continue
		# Upper partials shed energy faster, as they do on a real plate.
		tau = decay_s / (1.0 + 0.42 * p)
		a = amp / (1.0 + p) ** 0.85 * rng.uniform(0.7, 1.3)
		length = min(int(SR * tau * 6.5), int(SR * 0.25), n - idx)
		if length <= 0:
			continue
		r = math.exp(-1.0 / (SR * tau))
		z = cmath.rect(r, 2.0 * math.pi * f / SR)
		ph = complex(a, 0.0)
		for j in range(length):
			g = ph.imag
			if j < atk:
				g *= 0.5 - 0.5 * math.cos(math.pi * j / atk)
			buf[idx + j] += g
			ph *= z


def make_metal() -> list:
	rng = random.Random(4801)
	n = int(SR * METAL_DUR) + XF
	buf = metal_bed(rng, n)
	end_t = METAL_DUR + XF / SR

	strikes = 0
	t = 0.0
	while t < end_t:
		# Poisson arrivals: exponential gaps around METAL_RATE per second.
		t += -math.log(max(1e-9, rng.random())) / METAL_RATE
		idx = int(t * SR)
		if idx >= n - 8:
			break
		fat = rng.random() < 0.12                       # occasional heavy drop
		if fat:
			f0 = rng.choice(PANEL_MODES[:3]) * rng.uniform(0.88, 1.06)
			decay_s = rng.uniform(0.045, 0.080)
			amp = rng.uniform(0.55, 1.00)
			partials = rng.randint(4, 6)
		else:
			f0 = rng.choice(PANEL_MODES) * rng.uniform(0.90, 1.12)
			decay_s = rng.uniform(0.015, 0.050)
			# Wide amplitude spread (log-ish): a few crack, most tick.
			amp = 0.16 * (10.0 ** rng.uniform(0.0, 0.72))
			partials = rng.randint(2, 5)
		f0 = min(max(f0, 1200.0), 5000.0)
		add_strike(buf, idx, rng, amp, f0, decay_s, partials)
		strikes += 1

	print("  metal: %d strikes over %.1fs (%.1f/s)" % (strikes, end_t, strikes / end_t))
	return match_rms(seamless(buf), open_rms())


# --- rain_far ----------------------------------------------------------------

def make_far() -> list:
	rng = random.Random(1907)
	n = int(SR * 12.0) + XF
	far = [0.6 * a + 0.95 * b for a, b in zip(
		lowpass(white(rng, n), alpha_for(230.0)),
		lowpass(white(rng, n), alpha_for(95.0)),
	)]
	far = lowpass(far, alpha_for(430.0))            # make sure nothing bright survives
	far_env = slow_env(rng, n, 0.28, 0.68, 1.1)
	return normalize(seamless([far[i] * far_env[i] for i in range(n)]), 0.82)


# --- measurement / acceptance test -------------------------------------------

def _fft(x: list) -> list:
	n = len(x)
	x = list(x)
	j = 0
	for i in range(1, n):
		bit = n >> 1
		while j & bit:
			j ^= bit
			bit >>= 1
		j |= bit
		if i < j:
			x[i], x[j] = x[j], x[i]
	ln = 2
	while ln <= n:
		wl = cmath.exp(complex(0.0, -2.0 * math.pi / ln))
		half = ln // 2
		for i in range(0, n, ln):
			w = complex(1.0)
			for k in range(half):
				u = x[i + k]
				v = x[i + k + half] * w
				x[i + k] = u + v
				x[i + k + half] = u - v
				w *= wl
		ln <<= 1
	return x


def mean_spectrum(sig: list, nfft: int = 1024, frames: int = 200) -> list:
	win = [0.5 - 0.5 * math.cos(2.0 * math.pi * i / nfft) for i in range(nfft)]
	hop = max(nfft, len(sig) // frames)
	acc = [0.0] * (nfft // 2)
	cnt = 0
	pos = 0
	while pos + nfft <= len(sig):
		sp = _fft([complex(sig[pos + i] * win[i], 0.0) for i in range(nfft)])
		for i in range(nfft // 2):
			acc[i] += abs(sp[i])
		cnt += 1
		pos += hop
	return [a / max(1, cnt) for a in acc]


def spectral_centroid(mag: list, nfft: int = 1024) -> float:
	num = den = 0.0
	for i in range(1, len(mag)):
		f = i * SR / nfft
		num += f * mag[i]
		den += mag[i]
	return num / max(1e-12, den)


def count_transients(sig: list, win_ms: float = 4.0, ratio: float = 2.5,
                     local_s: float = 0.25):
	"""The verifier's scan: bandpass 1.5-4 kHz, 4 ms windows, count windows whose
	energy exceeds `ratio` x the local mean energy around them."""
	band = highpass(lowpass_n(sig, 4000.0, 2), 1500.0, 2)
	w = int(SR * win_ms / 1000.0)
	nw = len(band) // w
	en = []
	for i in range(nw):
		acc = 0.0
		for s in band[i * w:(i + 1) * w]:
			acc += s * s
		en.append(acc / w)
	pre = [0.0]
	for e in en:
		pre.append(pre[-1] + e)
	k = max(1, int(local_s / (win_ms / 1000.0)))
	hits = 0
	for i in range(nw):
		a, b = max(0, i - k), min(nw, i + k + 1)
		local = (pre[b] - pre[a]) / (b - a)
		if local > 0.0 and en[i] > ratio * local:
			hits += 1
	return hits, nw


BANDS = ((60, 250), (250, 800), (800, 1500), (1500, 4000),
         (4000, 8000), (8000, 16000), (16000, 22050))


def band_energy(mag: list, lo: float, hi: float, nfft: int = 1024) -> float:
	tot = 0.0
	for i in range(1, len(mag)):
		f = i * SR / nfft
		if lo <= f < hi:
			tot += mag[i] * mag[i]
	return tot


def measure(name: str) -> dict:
	sig, sr, ch, sw = read_wav(os.path.join(AUDIO_DIR, name + ".wav"))
	dur = len(sig) / sr
	hits, nw = count_transients(sig)
	mag = mean_spectrum(sig)
	m = {
		"name": name, "dur": dur, "sr": sr, "ch": ch, "bits": sw * 8,
		"rms": rms(sig), "peak": max(abs(s) for s in sig),
		"hits": hits, "windows": nw, "per15": hits * 15.0 / dur,
		"centroid": spectral_centroid(mag),
		"bands": [band_energy(mag, a, b) for a, b in BANDS],
	}
	print("%-11s %5.2fs %dHz %dch %dbit  rms=%.4f (%.1f dBFS) peak=%.3f"
	      % (name, dur, sr, ch, sw * 8, m["rms"], 20 * math.log10(m["rms"]), m["peak"]))
	print("            transients=%d/%d windows (%.0f per 15s)   centroid=%.0f Hz"
	      % (hits, nw, m["per15"], m["centroid"]))
	tot = sum(m["bands"])
	print("            bands: " + " ".join(
		"%d-%d:%.1f%%" % (a, b, 100.0 * e / tot) for (a, b), e in zip(BANDS, m["bands"])))
	return m


def verify() -> int:
	"""ACCEPTANCE TEST. Exit code 0 only if rain_metal reads as a metal roof."""
	o = measure("rain_open")
	m = measure("rain_metal")
	print()
	cent_gain = 100.0 * (m["centroid"] - o["centroid"]) / o["centroid"]
	rms_delta = 20.0 * math.log10(m["rms"] / o["rms"])
	checks = [
		("transients > 60 per 15 s", m["per15"], "%.0f", m["per15"] > 60.0),
		("centroid > +25% vs open", cent_gain, "%+.1f%%", cent_gain > 25.0),
		("rms within 1.5 dB of open", rms_delta, "%+.2f dB", abs(rms_delta) < 1.5),
		("peak < 1.0 (no clipping)", m["peak"], "%.3f", m["peak"] < 1.0),
		("44.1 kHz mono 16-bit", m["sr"], "%d", m["sr"] == SR and m["ch"] == 1 and m["bits"] == 16),
	]
	ok = True
	for label, val, fmt, passed in checks:
		ok &= passed
		print("  [%s] %-28s %s" % ("PASS" if passed else "FAIL", label, fmt % val))
	print()
	print("  per-band metal vs open (dB):")
	for (a, b), x, y in zip(BANDS, o["bands"], m["bands"]):
		print("    %5d-%5d Hz  %+6.1f dB" % (a, b, 10.0 * math.log10(max(1e-12, y) / max(1e-12, x))))
	print()
	print("ACCEPTANCE: %s" % ("PASS" if ok else "FAIL"))
	return 0 if ok else 1


# --- entry point -------------------------------------------------------------

TARGETS = {
	"open": ("rain_open", make_open),
	"metal": ("rain_metal", make_metal),
	"far": ("rain_far", make_far),
	"loop": ("rain_loop", lambda: [0.0] * int(SR * 2.0)),
}


def main(argv: list) -> int:
	if "--verify" in argv:
		return verify()
	if "--all" in argv:
		names = list(TARGETS)
		print("WARNING: regenerating rain_far.wav gives a different (still valid) "
		      "realization than the verified file on disk.")
	else:
		names = [a for a in argv if not a.startswith("-")] or ["metal"]
	for nm in names:
		if nm not in TARGETS:
			print("unknown target %r; choose from %s" % (nm, ", ".join(TARGETS)))
			return 2
		fname, fn = TARGETS[nm]
		write_wav(fname, fn())
	print("done")
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
