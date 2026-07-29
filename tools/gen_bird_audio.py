#!/usr/bin/env python3
"""Synthesize the gull WINGBEAT one-shot — the only sound a bird makes taking off.

Flushing a bird used to fire gull.wav (a squawk) on top of the ambient distant
gull cries, so every startled bird announced itself twice over. This is what
replaces it: pure air, no voice.

A wingbeat is broadband air displacement shaped by a hard amplitude envelope —
a whoomph per stroke, NOT a tone. So there is no oscillator anywhere in here:
every stroke is band-limited noise (high-passed to kill rumble, low-passed to
kill hiss) under a fast-attack / exponential-decay envelope, with a brighter
feather-rustle transient on the onset. The strokes ACCELERATE and FADE across
the burst, which is what sells "the bird is leaving" rather than "a bird is
hovering here". Style follows tools/gen_audio.py (22.05 kHz mono 16-bit).

  python3 tools/gen_bird_audio.py     # writes audio/wingbeat.wav
"""
import math
import random
import struct
import wave

SR = 22050
random.seed(31)


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


def highpass(samples, alpha):
    """One-pole complement of lowpass. Strips the sub-100 Hz rumble that filtered
    noise otherwise carries, so the stroke reads as air and not as a thud."""
    out, prev = [], 0.0
    for s in samples:
        prev += alpha * (s - prev)
        out.append(s - prev)
    return out


def env_fade(samples, fade=0.02):
    n = len(samples)
    f = max(1, int(n * fade))
    for i in range(f):
        g = i / f
        samples[i] *= g
        samples[n - 1 - i] *= g
    return samples


def norm_peak(samples, target=0.88):
    """Build for timbre, place at a known non-peaking level (as gen_audio.py does)."""
    pk = max((abs(s) for s in samples), default=0.0)
    if pk <= 1e-9:
        return list(samples)
    return [s * (target / pk) for s in samples]


def stroke(dur, lp_alpha, attack, decay, rustle):
    """One downbeat: a shove of air. `attack` is the fraction of the stroke spent
    swelling; everything after it decays, which is the asymmetry that makes it a
    whoomph. `rustle` layers a brighter, faster-dying feather hiss on the onset."""
    n = int(SR * dur)
    body = lowpass(highpass([random.uniform(-1, 1) for _ in range(n)], 0.020), lp_alpha)
    body = lowpass(body, lp_alpha)          # second pole: steeper, less hiss on top
    top = highpass([random.uniform(-1, 1) for _ in range(n)], 0.16)
    out = []
    a = max(1, int(n * attack))
    for i in range(n):
        if i < a:
            env = (i / a) ** 1.4            # quick swell into the stroke
        else:
            env = math.exp(-(i - a) / SR * decay)
        out.append((body[i] * 3.2 + top[i] * rustle * math.exp(-i / SR * 90.0)) * env)
    return out


# Six strokes. The gap tightens (panic cadence) while the level drops (the bird is
# getting away), and each stroke gets shorter and slightly duller with distance.
buf = []
gap = 0.052
level = 1.0
for k in range(6):
    dur = 0.135 - 0.008 * k                         # ~135 ms down to ~95 ms
    s = stroke(dur, 0.30 - 0.02 * k, 0.30, 34.0 + 3.0 * k, 0.5)
    s = [v * level for v in s]
    buf += s
    buf += [0.0] * int(SR * gap)
    gap = max(0.022, gap * 0.82)                    # accelerating
    level *= 0.74                                   # receding

write_wav("wingbeat", env_fade(norm_peak(buf), 0.01))
print("done")
