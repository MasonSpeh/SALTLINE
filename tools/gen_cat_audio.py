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


def purr(dur=3.6):
    """Two-phase purr: exhale (stronger, ~24 Hz) and inhale (softer, ~27 Hz, slightly
    brighter) alternating on a ~1.5 s breath cycle. That alternation is what a real purr
    has and a motor loop does not."""
    n = int(SR * dur)
    noise = one_pole([random.uniform(-1.0, 1.0) for _ in range(n)], 420.0)
    out = []
    breath_s = 1.5
    for i in range(n):
        t = i / SR
        ph = (t % breath_s) / breath_s
        exhale = ph < 0.58
        rate = 24.0 if exhale else 27.5
        amp = 1.0 if exhale else 0.62
        # Phase-continuous enough at these rates; the pulse is skewed toward "closed".
        m = 0.5 + 0.5 * math.sin(2.0 * math.pi * rate * t)
        m = m ** 1.9
        # Chest under the buzz: 52 Hz fundamental + a fifth, both very soft.
        body = 0.26 * math.sin(2.0 * math.pi * 52.0 * t) + 0.10 * math.sin(2.0 * math.pi * 78.0 * t)
        # Micro-turbulence between pulses so the floor is breath, never silence.
        floor_amt = 0.06 * noise[i]
        # Swell across the shot + a small dip at each breath turnover.
        swell = math.sin(math.pi * min(1.0, t / dur)) ** 0.6
        turn = 0.75 + 0.25 * math.sin(math.pi * ph)
        out.append(((noise[i] * 3.0 + body) * m * amp + floor_amt) * swell * turn * 0.44)
    return env_fade(out, 80)


def meow(dur=0.85):
    """A real meow: pitch rises 340->640 Hz then falls to 300, mouth opening and closing
    tracked by two formants (the vowel slides ee-ah-oo), light vibrato, breath under it."""
    n = int(SR * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        u = t / dur
        # Pitch contour with vibrato.
        if u < 0.35:
            f0 = 340.0 + (640.0 - 340.0) * (u / 0.35) ** 0.8
        else:
            f0 = 640.0 - (640.0 - 300.0) * ((u - 0.35) / 0.65) ** 1.3
        f0 *= 1.0 + 0.018 * math.sin(2.0 * math.pi * 6.2 * t)
        phase += 2.0 * math.pi * f0 / SR
        # Glottal-ish source: fundamental + shaped harmonics.
        src = (math.sin(phase) + 0.55 * math.sin(2 * phase) + 0.30 * math.sin(3 * phase)
               + 0.16 * math.sin(4 * phase) + 0.08 * math.sin(5 * phase))
        # Mouth: formants slide ee(2600) -> ah(1100) -> oo(500); approximate by tilting
        # harmonic weights with a resonant emphasis via ring on the source.
        mouth = math.sin(math.pi * min(1.0, u * 1.35)) ** 1.2   # opens then closes
        formant = 500.0 + 2100.0 * (1.0 - abs(2.0 * u - 0.7)) * mouth
        res = 0.35 * math.sin(phase * max(1.0, formant / max(f0, 1.0)))
        # Amplitude: fast attack, held, tapering tail; slight roughness at the peak.
        env = min(1.0, u / 0.08) * (1.0 - max(0.0, (u - 0.62)) / 0.38) ** 1.4
        rough = 1.0 + 0.05 * math.sin(2.0 * math.pi * 31.0 * t) * (mouth)
        out.append((src * 0.62 + res) * env * rough * mouth * 0.34)
    return env_fade(out, 18)


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
    write_wav("meow", meow())
    write_wav("cat_chirp", chirp())
