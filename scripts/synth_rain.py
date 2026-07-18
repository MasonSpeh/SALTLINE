#!/usr/bin/env python3
"""Synthesize SALTLINE's rain beds — a heavy, RELAXING downpour, not TV static.

Replaces the old harsh differentiated-white-noise rain (blue-noise fizz + no
droplet transients) with three seamless, click-free loops the game crossfades by
how sheltered the player is:

  rain_open.wav   full rich downpour: layered pink/brown noise (one-pole filtered
                  white), rolled off above ~5 kHz so there is no harsh sizzle,
                  with a slow gust undulation.
  rain_metal.wav  the open bed plus randomized short decaying metallic pings
                  (damped inharmonic sine bursts, 1.5-4 kHz) — rain drumming on a
                  close thin-steel roof.
  rain_far.wav    heavily low-passed (<=~450 Hz) distant rumble wash — the muffled
                  rain heard from deep under the huge deck platform.

Also rewrites rain_loop.wav (the old harsh AudioDirector bed) as short silence so
that bed stops contributing; rain_audio.gd owns all rain now.

Pure stdlib (numpy unavailable): wave / struct / math / random. 44.1 kHz mono
16-bit. Loops are made click-free by crossfading a 2 s tail back into the head.
"""
import math
import os
import random
import struct
import wave

SR = 44100
DUR = 12.0                 # audible loop length (seconds)
XF = int(SR * 2.0)         # crossfade length folded back into the head
N = int(SR * DUR) + XF     # samples synthesized before the fold
AUDIO_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "audio"))

random.seed(73)
_rand = random.random


def alpha_for(fc: float) -> float:
	"""One-pole low-pass coefficient for a -3 dB corner at fc Hz."""
	return 1.0 - math.exp(-2.0 * math.pi * fc / SR)


def white(n: int) -> list:
	return [_rand() * 2.0 - 1.0 for _ in range(n)]


def lowpass(sig: list, alpha: float) -> list:
	out = [0.0] * len(sig)
	p = 0.0
	for i, s in enumerate(sig):
		p += alpha * (s - p)
		out[i] = p
	return out


def slow_env(n: int, fc: float, lo: float, hi: float) -> list:
	"""A gentle sub-Hz amplitude undulation normalised into [lo, hi]."""
	g = lowpass(white(n), alpha_for(fc))
	m = max(1e-9, max(abs(x) for x in g))
	return [lo + (hi - lo) * (0.5 + 0.5 * (x / m)) for x in g]


def seamless(sig: list) -> list:
	"""Fold the trailing XF samples into the head so the loop is click-free."""
	n = len(sig) - XF
	out = sig[:n]
	for i in range(XF):
		f = i / XF
		out[i] = sig[i] * f + sig[n + i] * (1.0 - f)
	return out


def normalize(sig: list, peak: float) -> list:
	m = max(1e-9, max(abs(s) for s in sig))
	g = peak / m
	return [s * g for s in sig]


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
	print(f"{name}.wav  ({len(sig) / SR:.1f}s, {len(sig)} frames)")


def rain_bed(bright: float) -> list:
	"""A downpour bed: airy top rolled off ~5 kHz + mid 'shhh' + low wash, all from
	filtered white noise so there is no harsh differentiated high end. `bright`
	nudges how much of the airy top survives (metal roof reads a touch brighter)."""
	top = lowpass(white(N), alpha_for(5200.0))    # gentle roll-off, relaxing
	body = lowpass(white(N), alpha_for(1400.0))   # the broadband hiss of the fall
	wash = lowpass(white(N), alpha_for(300.0))    # low body so it feels heavy
	env = slow_env(N, 0.35, 0.62, 1.08)
	a_top = 0.42 + 0.18 * bright
	return [
		(a_top * top[i] + 0.42 * body[i] + 0.50 * wash[i]) * env[i]
		for i in range(N)
	]


# --- rain_open: full rich downpour ------------------------------------------
open_bed = rain_bed(0.0)
write_wav("rain_open", normalize(seamless(open_bed), 0.86))

# --- rain_metal: bed + individual metallic pings on the steel ---------------
metal = rain_bed(1.0)
t = 0.0
end_t = DUR + XF / SR
while t < end_t:
	idx = int(t * SR)
	if idx < N - 4:
		f = random.uniform(1500.0, 3800.0)      # ping fundamental
		f2 = f * random.uniform(2.3, 2.95)      # inharmonic overtone = "metallic"
		decay = random.uniform(90.0, 240.0)
		amp = random.uniform(0.12, 0.42)
		length = min(int(SR * 0.06), N - idx)
		for j in range(length):
			tt = j / SR
			e = math.exp(-tt * decay)
			metal[idx + j] += amp * e * (
				math.sin(2.0 * math.pi * f * tt)
				+ 0.4 * math.sin(2.0 * math.pi * f2 * tt)
			)
	t += random.uniform(0.05, 0.20)             # sparse enough to hear as pings
write_wav("rain_metal", normalize(seamless(metal), 0.9))

# --- rain_far: heavily muffled distant wash (<=~450 Hz) ---------------------
far = [0.6 * a + 0.95 * b for a, b in zip(
	lowpass(white(N), alpha_for(230.0)),
	lowpass(white(N), alpha_for(95.0)),
)]
far = lowpass(far, alpha_for(430.0))            # make sure nothing bright survives
far_env = slow_env(N, 0.28, 0.68, 1.1)
far = [far[i] * far_env[i] for i in range(N)]
write_wav("rain_far", normalize(seamless(far), 0.82))

# --- rain_loop: decommission the old harsh AudioDirector bed (now silent) ---
write_wav("rain_loop", [0.0] * int(SR * 2.0))

print("done")
