#!/usr/bin/env python3
"""
SALTLINE ambience synthesizer — pure stdlib (numpy is NOT available on this machine).

Writes 44.1 kHz / 16-bit / mono WAVs into res://audio/. Two families:

  BEDS (seamless loops)   wind_open, wind_howl, sea_swell, hull_groan, interior_hum
  ONE-SHOTS               deep_groan, sheet_bang, drip,
                          step_{grate,plate,concrete,wood,water,wet}_{a,b}

SEAMLESS LOOPING — the two rules every bed here obeys:
  1. Every modulator (gust LFOs, swell periods, hum beating) completes an INTEGER
     number of cycles across DUR, so the envelope at t == the envelope at t+DUR.
  2. The generator renders DUR + XFADE seconds, then equal-power crossfades the
     tail back over the head. Because of rule 1 the two sides share an identical
     envelope, so the splice only ever blends two decorrelated *noise* realizations
     — which is inaudible. Violating rule 1 makes rule 2 produce a level pump.

Run from the repo root:  python3 tools/synth_ambience.py
Existing files are overwritten; gull_distant is deliberately NOT generated because
res://audio/gull.wav already exists.
"""

import math
import os
import random
import struct
import wave

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio")


# ----------------------------------------------------------------- primitives

def n_of(seconds):
    return int(round(seconds * SR))


def white(n, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def lowpass(buf, alpha):
    """One-pole. alpha near 0 = very dark, near 1 = open."""
    out = [0.0] * len(buf)
    z = 0.0
    for i, s in enumerate(buf):
        z += alpha * (s - z)
        out[i] = z
    return out


def highpass(buf, alpha):
    """Complement of the one-pole lowpass — removes DC and rumble."""
    out = [0.0] * len(buf)
    z = 0.0
    for i, s in enumerate(buf):
        z += alpha * (s - z)
        out[i] = s - z
    return out


def svf_bandpass(buf, freq_at, q):
    """Chamberlin state-variable filter, bandpass tap, with a per-sample centre
    frequency callback so a whistle can drift. `q` is resonance: smaller = ringier."""
    low = 0.0
    band = 0.0
    out = [0.0] * len(buf)
    for i, s in enumerate(buf):
        f = 2.0 * math.sin(math.pi * min(freq_at(i), SR * 0.24) / SR)
        low += f * band
        high = s - low - q * band
        band += f * high
        out[i] = band
    return out


def mix_into(dst, src, start, gain=1.0):
    n = len(dst)
    for i, s in enumerate(src):
        j = start + i
        if 0 <= j < n:
            dst[j] += s * gain


def normalize(buf, peak=0.9):
    m = max((abs(s) for s in buf), default=0.0)
    if m < 1e-9:
        return buf
    k = peak / m
    return [s * k for s in buf]


def fade_edges(buf, seconds=0.01):
    """Kills the click at the very start/end of a one-shot."""
    f = min(n_of(seconds), len(buf) // 2)
    for i in range(f):
        g = i / f
        buf[i] *= g
        buf[-1 - i] *= g
    return buf


def loop_splice(buf, dur_s, xfade_s):
    """Equal-power crossfade of the rendered tail back over the head, then trim to
    exactly dur_s. Requires buf to be dur_s + xfade_s long."""
    n = n_of(dur_s)
    x = n_of(xfade_s)
    out = buf[:n]
    for i in range(x):
        t = i / x
        a = math.cos(t * math.pi * 0.5)   # head rises in
        b = math.sin(t * math.pi * 0.5)   # tail falls out
        out[i] = out[i] * b + buf[n + i] * a
    return out


def write_wav(name, samples):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".wav")
    frames = bytearray()
    for s in samples:
        v = int(max(-1.0, min(1.0, s)) * 32767.0)
        frames += struct.pack("<h", v)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    print("  %-22s %6.2fs  %7.1f kB" % (name + ".wav", len(samples) / SR, len(frames) / 1024.0))


def lfo(i, cycles, dur_n, phase=0.0):
    """Unit sine that completes exactly `cycles` cycles over the loop length —
    this is what keeps loop_splice from pumping. Returns 0..1."""
    return 0.5 + 0.5 * math.sin(2.0 * math.pi * (cycles * i / dur_n + phase))


# ------------------------------------------------------------------- the beds

def wind_open(dur=22.0, xfade=2.5):
    """Exposed deck: broadband, band-limited, breathing in slow gusting swells."""
    rng = random.Random(41)
    total = n_of(dur + xfade)
    dn = n_of(dur)
    src = white(total, rng)
    body = lowpass(src, 0.16)          # the mass of the wind
    body = highpass(body, 0.0016)      # strip the mud
    air = lowpass(src, 0.55)           # the hiss riding on top
    air = highpass(air, 0.03)
    out = [0.0] * total
    for i in range(total):
        # Three gust layers at coprime cycle counts: long swells, mid pulses, flutter.
        g = (0.52 * lfo(i, 3, dn)
             + 0.30 * lfo(i, 7, dn, 0.31)
             + 0.18 * lfo(i, 13, dn, 0.67))
        g = 0.22 + 0.78 * (g ** 1.6)   # gusts spend more time low than high
        out[i] = body[i] * g + air[i] * 0.16 * (g ** 2.4)
    return loop_splice(normalize(out, 0.72), dur, xfade)


def wind_howl(dur=22.0, xfade=2.5):
    """Wind THROUGH the structure: the open bed plus resonant whistles that drift.
    For stairwells, railing runs, the gaps between modules."""
    rng = random.Random(83)
    total = n_of(dur + xfade)
    dn = n_of(dur)
    src = white(total, rng)
    body = highpass(lowpass(src, 0.20), 0.002)
    # TWO BROAD peaks, low and slow.
    #
    # This used to be three NARROW peaks (q 0.055/0.045/0.070) at 330/610/1180 Hz, each
    # sliding over its own period. In this filter smaller q = ringier, so that is three
    # near-pure tones drifting in pitch — which is, exactly, how you synthesize a WIND
    # CHIME. The owner called it out as the worst sound in the game and he was right.
    # Wind through a gap is broadband and breathy, not tonal: q is now an order of
    # magnitude larger (barely resonant), the 1180 Hz peak that did most of the chiming
    # is gone entirely, and what is left sits well under the broadband body.
    peaks = []
    for base, span, cyc, q, gain in (
            (300.0, 60.0, 7, 0.62, 0.34),
            (540.0, 90.0, 5, 0.78, 0.18)):
        f = lambda i, b=base, s=span, c=cyc: b + s * (lfo(i, c, dn) - 0.5) * 2.0
        peaks.append((svf_bandpass(src, f, q), gain))
    out = [0.0] * total
    for i in range(total):
        g = 0.30 + 0.70 * ((0.6 * lfo(i, 4, dn) + 0.4 * lfo(i, 9, dn, 0.4)) ** 1.8)
        w = 0.0
        for buf, gain in peaks:
            w += buf[i] * gain
        # Whistles only speak when the gust is actually up — that is the whole effect.
        out[i] = body[i] * g * 0.75 + w * 0.30 * (g ** 3.0)
    return loop_splice(normalize(out, 0.70), dur, xfade)


def sea_swell(dur=26.0, xfade=3.0):
    """Deep slow water working against the legs. Near the waterline this is the world."""
    rng = random.Random(1907)
    total = n_of(dur + xfade)
    dn = n_of(dur)
    src = white(total, rng)
    deep = lowpass(lowpass(src, 0.030), 0.030)   # the mass of moving water
    foam = highpass(lowpass(src, 0.28), 0.02)    # the crest hiss
    slap = highpass(lowpass(src, 0.09), 0.006)   # water hitting concrete
    out = [0.0] * total
    for i in range(total):
        # 7 swells across the loop (~3.7 s apart) plus a slower tide breathing under.
        s = lfo(i, 7, dn) ** 2.2
        tide = 0.55 + 0.45 * lfo(i, 2, dn, 0.2)
        out[i] = (deep[i] * 6.0 * (0.35 + 0.65 * s) * tide
                  + slap[i] * 0.55 * s * tide
                  + foam[i] * 0.10 * (s ** 3.0))
    return loop_splice(normalize(out, 0.78), dur, xfade)


def _groan_event(length_s, rng, low_hz=None, bright=1.0):
    """One slow metallic complaint: inharmonic partials that bend as the steel loads
    up, plus a creak band. This is the loneliness sound — keep it LOW."""
    n = n_of(length_s)
    if low_hz is None:
        low_hz = rng.uniform(38.0, 74.0)
    partials = [1.0, 2.37, 3.94, 5.61, 7.13]
    gains = [1.0, 0.42, 0.24, 0.12, 0.07]
    bend = rng.uniform(0.05, 0.16)          # it rises as it takes the load
    out = [0.0] * n
    phases = [rng.uniform(0, math.tau) for _ in partials]
    for i in range(n):
        t = i / n
        # Slow asymmetric swell: creeps in, holds, lets go.
        env = math.sin(math.pi * (t ** 0.62)) ** 1.7
        f_mul = 1.0 + bend * t
        s = 0.0
        for k, (p, g) in enumerate(zip(partials, gains)):
            f = low_hz * p * f_mul
            phases[k] += 2.0 * math.pi * f / SR
            s += math.sin(phases[k]) * g
        out[i] = s * env * 0.2
    # Creak: resonant noise stuttering on top of the sustain.
    cn = white(n, rng)
    creak_f = rng.uniform(400.0, 900.0) * bright
    cb = svf_bandpass(cn, lambda i: creak_f * (1.0 + 0.25 * math.sin(i * 0.00013)), 0.09)
    for i in range(n):
        t = i / n
        env = math.sin(math.pi * (t ** 0.62)) ** 2.4
        # Stick-slip: the creak chatters rather than sustaining.
        chatter = 0.5 + 0.5 * math.sin(i * 2.0 * math.pi * rng.uniform(7.0, 15.0) / SR)
        out[i] += cb[i] * env * 0.30 * chatter
    return fade_edges(out, 0.03)


def hull_groan(dur=28.0, xfade=2.0):
    """Sparse. Long silences between events — the rig flexing, once in a while."""
    rng = random.Random(555)
    n = n_of(dur)
    out = [0.0] * n_of(dur + xfade)
    # Four events, all fully inside the loop body so none straddles the splice.
    slots = [1.6, 8.4, 15.0, 21.2]
    for s in slots:
        ln = rng.uniform(2.6, 4.4)
        if n_of(s + ln) > n - n_of(xfade + 0.4):
            ln = (n - n_of(xfade + 0.4)) / SR - s
        if ln <= 0.5:
            continue
        mix_into(out, _groan_event(ln, rng), n_of(s), rng.uniform(0.6, 1.0))
    # A near-inaudible floor so the bed is not digital silence between groans.
    floor = lowpass(white(len(out), rng), 0.012)
    for i in range(len(out)):
        out[i] += floor[i] * 1.2
    return loop_splice(normalize(out, 0.66), dur, xfade)


def interior_hum(dur=16.0, xfade=2.0):
    """Room tone for enclosed spaces. Almost subliminal — you notice it when it stops."""
    rng = random.Random(77)
    total = n_of(dur + xfade)
    dn = n_of(dur)
    # Mains-ish stack, detuned so it beats slowly instead of sitting dead still.
    tones = [(49.6, 1.00), (99.7, 0.45), (150.1, 0.16), (201.3, 0.07)]
    out = [0.0] * total
    for f, g in tones:
        ph = rng.uniform(0, math.tau)
        for i in range(total):
            ph += 2.0 * math.pi * f / SR
            out[i] += math.sin(ph) * g
    air = lowpass(white(total, rng), 0.09)
    for i in range(total):
        beat = 0.88 + 0.12 * lfo(i, 3, dn)      # slow breathing in the room tone
        out[i] = out[i] * 0.06 * beat + air[i] * 0.9
    return loop_splice(normalize(out, 0.42), dur, xfade)


# -------------------------------------------------------------- the one-shots

def deep_groan():
    """A single long low groan for the randomized event scheduler."""
    rng = random.Random(9001)
    return normalize(_groan_event(3.8, rng, low_hz=41.0, bright=0.8), 0.85)


def sheet_bang():
    """A loose sheet of corrugated metal caught by a gust: one slam, then a rattle
    tail as it settles back against its fixing."""
    rng = random.Random(4242)
    n = n_of(1.5)
    out = [0.0] * n
    # The slam itself: thin inharmonic plate modes over a broadband whack.
    modes = [(96.0, 1.0, 0.9), (183.0, 0.7, 1.3), (274.0, 0.5, 1.7),
             (441.0, 0.34, 2.4), (708.0, 0.2, 3.2), (1130.0, 0.1, 4.6)]
    for f, g, decay in modes:
        ph = rng.uniform(0, math.tau)
        for i in range(n):
            ph += 2.0 * math.pi * f / SR
            out[i] += math.sin(ph) * g * math.exp(-decay * i / SR)
    whack = highpass(white(n, rng), 0.08)
    for i in range(n):
        out[i] += whack[i] * 1.6 * math.exp(-38.0 * i / SR)
    # Rattle tail: three softer re-contacts as the sheet settles.
    for t, g in ((0.19, 0.34), (0.32, 0.20), (0.46, 0.11)):
        s = n_of(t)
        for i in range(min(n_of(0.25), n - s)):
            e = math.exp(-26.0 * i / SR)
            out[s + i] += (rng.uniform(-1, 1) * 0.6 + math.sin(2 * math.pi * 210 * i / SR)) * g * e
    return normalize(fade_edges(out, 0.004), 0.9)


def drip():
    """Water off the underside of the wet deck into standing water. The classic
    drip is a fast UPWARD pitch sweep — the bubble cavity shrinking."""
    rng = random.Random(31337)
    n = n_of(0.55)
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = 620.0 * math.exp(6.5 * t)      # sweeps up hard and fast
        ph += 2.0 * math.pi * f / SR
        out[i] = math.sin(ph) * math.exp(-30.0 * t)
    # The little wet splat that precedes the tone.
    splat = highpass(lowpass(white(n, rng), 0.5), 0.05)
    for i in range(n):
        out[i] += splat[i] * 0.5 * math.exp(-120.0 * i / SR)
    return normalize(fade_edges(out, 0.003), 0.8)


# ------------------------------------------------------------------ footsteps

def _impact_noise(n, rng, lp, hp, decay):
    b = highpass(lowpass(white(n, rng), lp), hp)
    return [b[i] * math.exp(-decay * i / SR) for i in range(n)]


def _resonances(n, rng, modes):
    """modes = [(hz, gain, decay_per_sec), ...]"""
    out = [0.0] * n
    for f, g, d in modes:
        ph = rng.uniform(0, math.tau)
        jitter = rng.uniform(0.97, 1.03)     # each variant lands slightly differently
        for i in range(n):
            ph += 2.0 * math.pi * f * jitter / SR
            out[i] += math.sin(ph) * g * math.exp(-d * i / SR)
    return out


def step_grate(seed):
    """Open walkway grating: a bright metallic ring over a hollow thud, because
    there is nothing under the bars but air."""
    rng = random.Random(seed)
    n = n_of(0.34)
    out = _impact_noise(n, rng, 0.62, 0.10, 55.0)
    # The ring used to be three tuned HIGH partials (1180/2360/3510 Hz) decaying slowly.
    # A boot lands ON a bar and DAMPS it; leaving them to sing turned every footstep into
    # pipes clanging together. Now: the hollow low mode carries it (there is only air
    # under the bars), one short mid buzz for the metal, the high partials gone, and all
    # of it damped several times faster and mixed well under the impact noise.
    ring = _resonances(n, rng, [(168.0, 0.26, 52.0), (430.0, 0.10, 90.0)])
    for i in range(n):
        out[i] = out[i] * 1.0 + ring[i] * 0.45
    return normalize(fade_edges(out, 0.003), 0.85)


def step_plate(seed):
    """Solid deck plate over structure: a firm thud with a short mid ring, damped
    fast because there is steel and then more steel underneath."""
    rng = random.Random(seed)
    n = n_of(0.24)
    out = _impact_noise(n, rng, 0.34, 0.05, 80.0)
    # Solid steel over structure barely rings — keep the body, kill the ping.
    ring = _resonances(n, rng, [(132.0, 0.42, 62.0), (318.0, 0.18, 78.0)])
    for i in range(n):
        out[i] = out[i] * 1.0 + ring[i] * 0.55
    return normalize(fade_edges(out, 0.003), 0.85)


def step_concrete(seed):
    """Dry, dull, no ring at all — the leg cellars and the pump room floor."""
    rng = random.Random(seed)
    n = n_of(0.17)
    out = _impact_noise(n, rng, 0.30, 0.045, 120.0)
    grit = _impact_noise(n, rng, 0.85, 0.30, 200.0)
    for i in range(n):
        out[i] = out[i] + grit[i] * 0.22
    return normalize(fade_edges(out, 0.003), 0.8)


def step_wood(seed):
    """Hollow plank knock — pallets, the galley table run, anything decked in timber."""
    rng = random.Random(seed)
    n = n_of(0.26)
    out = _impact_noise(n, rng, 0.24, 0.035, 95.0)
    ring = _resonances(n, rng, [(174.0, 0.62, 26.0), (415.0, 0.28, 33.0), (852.0, 0.10, 44.0)])
    for i in range(n):
        out[i] = out[i] * 0.75 + ring[i]
    return normalize(fade_edges(out, 0.003), 0.82)


def step_water(seed):
    """Standing water / the shallow edge: a real splash with a long wet tail and a
    downward-sweeping band as the cavity collapses."""
    rng = random.Random(seed)
    n = n_of(0.5)
    src = white(n, rng)
    body = svf_bandpass(src, lambda i: 2600.0 * math.exp(-5.0 * i / SR) + 260.0, 0.5)
    spray = highpass(lowpass(src, 0.75), 0.25)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        out[i] = body[i] * 1.4 * math.exp(-11.0 * t) + spray[i] * 0.45 * math.exp(-26.0 * t)
    return normalize(fade_edges(out, 0.004), 0.85)


def step_wet(seed):
    """Deck plate with a film of rain on it — the plate thud plus a thin peel of
    water. This is what the whole rig sounds like during a squall."""
    rng = random.Random(seed)
    n = n_of(0.3)
    out = step_plate(seed + 991)[:n]
    out += [0.0] * (n - len(out))
    film = highpass(lowpass(white(n, rng), 0.8), 0.32)
    for i in range(n):
        out[i] = out[i] * 0.85 + film[i] * 0.38 * math.exp(-40.0 * i / SR)
    return normalize(fade_edges(out, 0.003), 0.85)


# ------------------------------------------------------------------------ run

BEDS = [
    ("wind_open", wind_open),
    ("wind_howl", wind_howl),
    ("sea_swell", sea_swell),
    ("hull_groan", hull_groan),
    ("interior_hum", interior_hum),
]

SHOTS = [
    ("deep_groan", deep_groan),
    ("sheet_bang", sheet_bang),
    ("drip", drip),
]

STEPS = [
    ("grate", step_grate), ("plate", step_plate), ("concrete", step_concrete),
    ("wood", step_wood), ("water", step_water), ("wet", step_wet),
]


def main():
    print("SALTLINE ambience -> %s" % OUT_DIR)
    print("beds:")
    for name, fn in BEDS:
        write_wav(name, fn())
    print("one-shots:")
    for name, fn in SHOTS:
        write_wav(name, fn())
    print("footsteps:")
    for s_idx, (surface, fn) in enumerate(STEPS):
        for idx, variant in enumerate("ab"):
            # Deterministic seed: Python's str hash is salted per-process, so using
            # hash(surface) here would resynthesize different samples every run.
            write_wav("step_%s_%s" % (surface, variant), fn(7000 + s_idx * 311 + idx * 137))
    # gull_distant is intentionally skipped: res://audio/gull.wav already exists and
    # AudioDirector already schedules it. Do not duplicate it.
    print("done. (gull_distant skipped -- gull.wav already exists)")


if __name__ == "__main__":
    main()
