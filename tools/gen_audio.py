#!/usr/bin/env python3
"""Synthesize placeholder audio for SALTLINE v0.1 (CC0-equivalent: generated).
Beds: wind, sea, hum. One-shots: groan, gull, pa_crackle, hiss, clang,
breaker, hatch, splash, eat. 22.05 kHz mono 16-bit WAV."""
import math
import random
import struct
import wave

SR = 22050
random.seed(11)


def write_wav(name, samples):
    with wave.open(f"audio/{name}.wav", "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(
            struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples
        )
        w.writeframes(frames)
    print(f"audio/{name}.wav  ({len(samples)/SR:.1f}s)")


def lowpass(samples, alpha):
    out, prev = [], 0.0
    for s in samples:
        prev += alpha * (s - prev)
        out.append(prev)
    return out


def noise(n):
    return [random.uniform(-1, 1) for _ in range(n)]


def env_fade(samples, fade=0.05):
    n = len(samples)
    f = int(n * fade)
    for i in range(f):
        g = i / f
        samples[i] *= g
        samples[n - 1 - i] *= g
    return samples


def norm_peak(samples, target=0.9):
    """Scale a buffer so its loudest sample sits at `target` (0..1 full-scale).
    Lets a synthesized one-shot be built for TIMBRE and then placed at a known,
    non-peaking level regardless of how the layers happened to sum."""
    pk = max((abs(s) for s in samples), default=0.0)
    if pk <= 1e-9:
        return list(samples)
    g = target / pk
    return [s * g for s in samples]


# --- beds (loopable-ish; AudioDirector restarts on finish) ---
n = SR * 8
wind = lowpass(noise(n), 0.04)
slow = lowpass(noise(n), 0.0004)  # gust envelope
wind = [w * (0.5 + 1.4 * abs(s)) * 0.55 for w, s in zip(wind, slow)]
write_wav("wind_loop", env_fade(wind, 0.02))

sea = lowpass(noise(n), 0.015)
swell = [0.5 + 0.5 * math.sin(2 * math.pi * i / (SR * 5.3)) for i in range(n)]
sea = [s * (0.35 + 0.65 * sw) * 0.7 for s, sw in zip(sea, swell)]
write_wav("sea_loop", env_fade(sea, 0.02))

n = SR * 4
hum = [
    0.35 * math.sin(2 * math.pi * 60 * i / SR)
    + 0.22 * math.sin(2 * math.pi * 120 * i / SR)
    + 0.08 * math.sin(2 * math.pi * 240 * i / SR)
    for i in range(n)
]
write_wav("hum_loop", env_fade([h * 0.5 for h in hum], 0.02))

# --- one-shots ---
n = SR * 3
groan = []
f0 = random.uniform(70, 110)
for i in range(n):
    t = i / SR
    f = f0 * (1.0 - 0.3 * t / 3)
    amp = math.exp(-t * 1.2)
    groan.append(
        (math.sin(2 * math.pi * f * t) * 0.6 + math.sin(2 * math.pi * f * 1.5 * t) * 0.3)
        * amp
        * 0.7
    )
groan = [g + w * 0.1 for g, w in zip(groan, lowpass(noise(n), 0.03))]
write_wav("groan", env_fade(groan))

n = int(SR * 0.9)
gull = []
for i in range(n):
    t = i / SR
    chirp = math.sin(2 * math.pi * (1400 + 700 * math.sin(t * 22)) * t)
    amp = math.exp(-t * 3.5) * (1 if (t % 0.28) < 0.14 else 0.15)
    gull.append(chirp * amp * 0.5)
write_wav("gull", env_fade(gull))

# claw.wav removed (s11): the giant crab's scuttle taps live in gen_crab_audio.py.

n = SR * 4
pa = lowpass(noise(n), 0.25)
voice = [math.sin(2 * math.pi * (180 + 60 * math.sin(i / SR * 7)) * i / SR) for i in range(n)]
gate = [1.0 if 0.4 < (i / SR) < 3.1 and random.random() > 0.25 else 0.2 for i in range(n)]
pa = [
    (p * 0.5 + v * 0.25 * g) * (1.0 if 0.15 < i / SR < 3.6 else 0.0) * 0.8
    for i, (p, v, g) in enumerate(zip(pa, voice, gate))
]
write_wav("pa_crackle", env_fade(pa, 0.03))

n = SR * 2
hiss = lowpass(noise(n), 0.5)
hiss = [h * math.exp(-i / SR * 1.4) * 0.6 for i, h in enumerate(hiss)]
write_wav("hiss", env_fade(hiss, 0.02))

# clang -> METAL-BREAK: prying/breaking open a locked box, a hasp giving way. The old
# clang was a BRIGHT RINGING clang (523/841 Hz partials, slow e^-2.8t decay, amp 0.8) —
# the "too loud, too bright" sound the mix hated. This is a short, dull, weighty CLUNK:
# a low body thud, a hint of metal killed fast so nothing rings, and a dry TEAR as the
# hasp lets go, then two quiet debris ticks. Peak-normalized low so it never spikes.
crng = random.Random(9021)   # LOCAL rng: leaves the global sequence (breaker..thunder) intact
n = int(SR * 0.55)
tear_lo = lowpass([crng.uniform(-1, 1) for _ in range(n)], 0.10)   # dull body of the tear
tear_hi = lowpass([crng.uniform(-1, 1) for _ in range(n)], 0.38)   # drier grit of parting metal
clang = []
for i in range(n):
    t = i / SR
    body = (
        0.90 * math.sin(2 * math.pi * 76 * t)
        + 0.50 * math.sin(2 * math.pi * 115 * t)
        + 0.28 * math.sin(2 * math.pi * 152 * t)
    ) * math.exp(-t * 23.0)                     # the weight of the lid letting go
    metal = (
        0.26 * math.sin(2 * math.pi * 236 * t)
        + 0.16 * math.sin(2 * math.pi * 329 * t)
    ) * math.exp(-t * 19.0)                     # a HINT of metal — decays too fast to ring
    tremor = 0.55 + 0.45 * math.sin(2 * math.pi * 80 * t)   # reads as tearing, not hiss
    grit = tear_hi[i] * math.exp(-t * 46.0)     # the hasp parts — brief and dry
    thud_noise = tear_lo[i] * math.exp(-t * 30.0)
    snap = (0.70 * grit + 0.50 * thud_noise) * tremor
    clang.append(body + metal + snap)
for tick_t, amp in [(0.17, 0.20), (0.30, 0.12)]:   # two quiet debris ticks settling after
    ci = int(tick_t * SR)
    for j in range(int(SR * 0.04)):
        if ci + j < n:
            clang[ci + j] += tear_hi[(ci + j) % n] * math.exp(-(j / SR) * 120.0) * amp
clang = norm_peak(clang, 0.4)                   # ~-8 dB pre-fade -> ~-9.4 dB after the attack ramp
write_wav("clang", env_fade(clang, 0.005))

n = int(SR * 0.5)
brk = [random.uniform(-1, 1) * math.exp(-i / SR * 30) for i in range(n)]
brk = [b * 0.5 + 0.6 * math.sin(2 * math.pi * 110 * i / SR) * math.exp(-i / SR * 18) for i, b in enumerate(brk)]
write_wav("breaker", env_fade(brk, 0.02))

n = int(SR * 0.8)
hatch = lowpass([random.uniform(-1, 1) * math.exp(-i / SR * 8) for i in range(n)], 0.12)
hatch = [h * 0.8 + 0.3 * math.sin(2 * math.pi * 65 * i / SR) * math.exp(-i / SR * 10) for i, h in enumerate(hatch)]
write_wav("hatch", env_fade(hatch, 0.02))

n = int(SR * 1.4)
splash = lowpass(noise(n), 0.3)
splash = [s * math.exp(-i / SR * 3.2) * 0.9 for i, s in enumerate(splash)]
write_wav("splash", env_fade(splash, 0.02))

n = int(SR * 0.5)
eat = lowpass(noise(n), 0.08)
eat = [e * (0.8 if (i / SR % 0.16) < 0.07 else 0.15) * math.exp(-i / SR * 2) * 0.6 for i, e in enumerate(eat)]
write_wav("eat", env_fade(eat, 0.05))

n = int(SR * 0.12)
step = lowpass([random.uniform(-1, 1) * math.exp(-i / SR * 70) for i in range(n)], 0.09)
step = [s * 0.8 + 0.35 * math.sin(2 * math.pi * 85 * i / SR) * math.exp(-i / SR * 55) for i, s in enumerate(step)]
write_wav("step", env_fade(step, 0.03))

# --- storm ---
# thunder: a sharp broadband crack, then a long rolling low rumble that decays.
n = int(SR * 4.2)
crack = [random.uniform(-1, 1) * math.exp(-i / SR * 7.0) for i in range(n)]
rumble = lowpass(noise(n), 0.006)
thunder = []
for i in range(n):
    t = i / SR
    body = rumble[i] * (0.35 + 0.65 * abs(math.sin(t * 1.15 + 0.6)))   # rolling waves
    c = crack[i] if t < 0.22 else 0.0
    thunder.append((c * 0.7 + body * 1.3) * math.exp(-t * 0.62) * 0.9)
write_wav("thunder", env_fade(thunder, 0.02))

# rain bed: INTENTIONALLY SILENT. Rain is now owned by scripts/world/rain_audio.gd, which
# crossfades cover-aware loops (rain_open / rain_metal / rain_far, from gen_rain_audio.py).
# AudioDirector still holds a "rain" bed id and StormSystem still calls set_storm(), but this
# flat bed must contribute NOTHING or it doubles up as a harsh wash over the cover-aware rain
# (exactly the old bed rain_audio.gd replaced). Keep it a short silent buffer; AudioDirector
# also hands "rain" to -80 dB in _fade as a second safeguard. (Must stay the LAST sound written
# so removing its noise draws does not perturb the deterministic global RNG for earlier wavs.)
write_wav("rain_loop", [0.0] * int(SR * 2))

print("done")
