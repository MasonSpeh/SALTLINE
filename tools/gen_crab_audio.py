#!/usr/bin/env python3
"""Synthesize the giant crab's SOFT chitin scuttle taps + pincer snap (s11 crab remake).

The old claw.wav carried a 900 Hz sine ring that read as metallic "jingling" and was
fired on a timer loop. These replace it: three short DULL taps — low-passed noise
bursts with a faint knock body, no sinusoidal ring — played as one-shots from the
crab's footfall cadence, and only when the crab is moving, near, AND visible.
Style follows tools/gen_audio.py (22.05 kHz mono 16-bit, env_fade edges).

  python3 tools/gen_crab_audio.py     # writes audio/scuttle_a|b|c.wav, crab_snap.wav
"""
import math
import random
import struct
import wave

SR = 22050
random.seed(54)


def write_wav(name, samples):
    with wave.open(f"audio/{name}.wav", "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(
            struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples))
    print(f"audio/{name}.wav  ({len(samples)/SR:.2f}s)")


def lowpass(samples, alpha):
    out, prev = [], 0.0
    for s in samples:
        prev += alpha * (s - prev)
        out.append(prev)
    return out


def env_fade(samples, fade=0.05):
    n = len(samples)
    f = max(1, int(n * fade))
    for i in range(f):
        g = i / f
        samples[i] *= g
        samples[n - 1 - i] *= g
    return samples


def tap(dur, decay, lp_alpha, knock_hz, knock_amp, knock_decay, gain):
    """One dull chitin contact: filtered noise thump + a low knock body.
    knock_hz stays under ~250 Hz and decays fast, so nothing rings."""
    n = int(SR * dur)
    burst = [random.uniform(-1, 1) * math.exp(-i / SR * decay) for i in range(n)]
    burst = lowpass(burst, lp_alpha)
    out = []
    for i, b in enumerate(burst):
        t = i / SR
        knock = knock_amp * math.sin(2 * math.pi * knock_hz * t) * math.exp(-t * knock_decay)
        out.append((b + knock) * gain)
    return out


def double(first, gap, second):
    """Crab feet land in quick pairs: tap, ~30-50 ms, lighter tap."""
    out = list(first)
    out += [0.0] * int(SR * gap)
    out += second
    return out


# Three variants so the cadence never machine-guns the same sample.
write_wav("scuttle_a", env_fade(double(
    tap(0.09, 70, 0.10, 165, 0.30, 45, 1.65),
    0.038,
    tap(0.07, 90, 0.09, 140, 0.22, 55, 1.15)), 0.03))

write_wav("scuttle_b", env_fade(double(
    tap(0.08, 80, 0.08, 190, 0.26, 50, 1.50),
    0.050,
    tap(0.06, 100, 0.10, 150, 0.20, 60, 1.05)), 0.03))

write_wav("scuttle_c", env_fade(double(
    tap(0.10, 60, 0.12, 130, 0.32, 40, 1.55),
    0.030,
    tap(0.07, 85, 0.09, 175, 0.20, 52, 1.20)), 0.03))

# The bite: one hard pincer snap — a sharp broadband click into a low wet thunk.
n = int(SR * 0.30)
click = [random.uniform(-1, 1) * math.exp(-i / SR * 160) for i in range(n)]
click = lowpass(click, 0.35)
snap = []
for i, c in enumerate(click):
    t = i / SR
    thunk = 0.5 * math.sin(2 * math.pi * 95 * t) * math.exp(-t * 22)
    snap.append((c * 0.9 + thunk) * 0.85)
write_wav("crab_snap", env_fade(snap, 0.02))

print("done")
