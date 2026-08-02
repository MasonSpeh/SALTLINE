#!/usr/bin/env python3
"""Synthesize the ship's cat: a PURR and a short chirrup (s34 cat states).

The cat had no voice of its own — every sound it made was `groan`, the deep-hull one-shot,
played quiet and called "the closest thing to a purr" in a comment. It is not one. A purr
is not a groan pitched down: it is an amplitude-modulated buzz at roughly 25 Hz (the real
animal's laryngeal cycle sits between 20 and 30), on a low, breathy carrier, with a slow
swell in and out rather than a hit and a decay.

  purr      2.4 s, loops in feel — 25 Hz AM on filtered noise plus a soft 65 Hz body,
            with a gentle in/out swell so it can be triggered repeatedly on petting
            without sounding like a machine starting.
  cat_chirp 0.35 s — the interrogative trill a cat makes at a person it likes, which is
            what the fish-interest and greeting states want. Rising formant, short.

Style follows tools/gen_audio.py and gen_crab_audio.py: 22.05 kHz mono 16-bit, faded edges
so nothing clicks.

  python3 tools/gen_cat_audio.py     # writes audio/purr.wav, audio/cat_chirp.wav
"""
import math
import random
import struct
import wave

SR = 22050
random.seed(3417)


def write_wav(name, samples):
    with wave.open(f"audio/{name}.wav", "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32000)) for s in samples))
    print(f"  audio/{name}.wav  {len(samples) / SR:.2f}s")


def env_fade(samples, ms=25):
    """Fade both ends so a one-shot never clicks."""
    n = int(SR * ms / 1000)
    for i in range(min(n, len(samples))):
        k = i / n
        samples[i] *= k
        samples[-1 - i] *= k
    return samples


def one_pole(samples, cut_hz):
    """Cheap low-pass — the purr's carrier is breath, not hiss."""
    a = math.exp(-2.0 * math.pi * cut_hz / SR)
    out, prev = [], 0.0
    for s in samples:
        prev = s * (1.0 - a) + prev * a
        out.append(prev)
    return out


def purr(dur=2.4):
    n = int(SR * dur)
    noise = one_pole([random.uniform(-1.0, 1.0) for _ in range(n)], 480.0)
    out = []
    for i in range(n):
        t = i / SR
        # The laryngeal cycle. Not a clean sine — a real purr is closer to a soft pulse,
        # so the modulator is skewed toward the "closed" half.
        m = 0.5 + 0.5 * math.sin(2.0 * math.pi * 25.0 * t)
        m = m ** 1.6
        # A little body under the buzz, or it reads as filtered static.
        body = 0.30 * math.sin(2.0 * math.pi * 65.0 * t)
        # Slow swell in and out across the whole shot, so repeated triggers overlap kindly.
        swell = math.sin(math.pi * min(1.0, t / dur)) ** 0.7
        out.append((noise[i] * 3.2 + body) * m * swell * 0.42)
    return env_fade(out, 60)


def chirp(dur=0.35):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        k = t / dur
        # Rising pitch, two formants, plus a breath of noise for the trill's roughness.
        f = 520.0 + 340.0 * k
        v = math.sin(2.0 * math.pi * f * t) * 0.55
        v += math.sin(2.0 * math.pi * f * 2.02 * t) * 0.22
        v += random.uniform(-1.0, 1.0) * 0.06
        # a trill, not a tone
        v *= 0.75 + 0.25 * math.sin(2.0 * math.pi * 34.0 * t)
        out.append(v * (1.0 - k) ** 0.5 * 0.65)
    return env_fade(out, 12)


if __name__ == "__main__":
    print("cat audio ->")
    write_wav("purr", purr())
    write_wav("cat_chirp", chirp())
