#!/usr/bin/env python3
"""Regenerate the three rain-ambience loops as NATURAL rain — no tonal 'pings'.

The old rain_metal.wav was synthesized as "bright patter with individual pings",
and under a roof (stairwell, any covered deck) those pings read as a constant
metallic JINGLE — the sound the player kept hearing and blaming on the crabs.
Real rain on a solid steel/concrete deck heard from below is a DULL, broadband
roar, not a ring. So:

  rain_open  — full-spectrum downpour: broadband hiss + soft drop patter (open sky)
  rain_metal — MUFFLED roar under a close roof: low-passed, bass-weighted, NO pings
  rain_far   — distant muffled wash: heavily low-passed, quiet

All three are steady filtered noise (plus, for open only, soft non-tonal patter),
peak-normalised and wrapped with an equal-power crossfade so they loop seamlessly.
22.05 kHz mono 16-bit, matching tools/gen_audio.py.
"""
import numpy as np
from scipy.signal import butter, sosfilt
import wave
import struct

SR = 22050
DUR = 8.0
N = int(SR * DUR)
XF = int(SR * 0.35)          # crossfade length for the seamless loop
RNG = np.random.default_rng(7)


def bp(sig, lo, hi):
    sos = butter(2, [lo / (SR / 2), hi / (SR / 2)], btype="band", output="sos")
    return sosfilt(sos, sig)


def lp(sig, cut, order=4):
    sos = butter(order, cut / (SR / 2), btype="low", output="sos")
    return sosfilt(sos, sig)


def hp(sig, cut, order=2):
    sos = butter(order, cut / (SR / 2), btype="high", output="sos")
    return sosfilt(sos, sig)


def gusts(n, rate=0.35, depth=0.5):
    """Slow amplitude wander so the rain breathes instead of sitting flat."""
    g = lp(RNG.standard_normal(n), rate)
    g /= np.max(np.abs(g)) + 1e-9
    return 1.0 - depth + depth * (0.5 + 0.5 * g)


def patter(n, density, decay):
    """Sparse SOFT drop taps — short decaying noise bursts, NOT tonal (no ringing).
    density = taps/sec; decay = seconds. Used only for the open-sky layer."""
    out = np.zeros(n)
    count = int(n / SR * density)
    idx = RNG.integers(0, n, size=count)
    env_len = int(SR * decay)
    env = np.exp(-np.linspace(0, 6, env_len))
    burst = RNG.standard_normal(env_len) * env
    for i in idx:
        end = min(n, i + env_len)
        out[i:end] += burst[: end - i]
    return out


def seamless(sig):
    """Wrap the tail into the head with an equal-power crossfade so it loops clean."""
    sig = sig[: N + XF]
    out = sig[:N].copy()
    t = np.linspace(0.0, np.pi / 2.0, XF)
    fade_in, fade_out = np.sin(t), np.cos(t)
    out[:XF] = out[:XF] * fade_in + sig[N : N + XF] * fade_out
    return out


def norm(sig, peak=0.5):
    return sig / (np.max(np.abs(sig)) + 1e-9) * peak


def write(name, sig):
    sig = norm(seamless(sig))
    frames = b"".join(
        struct.pack("<h", int(max(-32767, min(32767, s * 32767)))) for s in sig
    )
    with wave.open(f"audio/{name}.wav", "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(frames)
    print(f"audio/{name}.wav  ({len(sig)/SR:.1f}s)")


def build():
    n = N + XF
    g = gusts(n)
    white = RNG.standard_normal(n)

    # OPEN: bright broadband hiss (the sheet of rain) + soft drop patter, gusting.
    hiss = bp(white, 700, 8000) * 0.9
    body = lp(RNG.standard_normal(n), 900) * 0.5
    taps = patter(n, density=140, decay=0.028) * 0.5
    write("rain_open", (hiss + body + taps) * g)

    # METAL (under a close roof): a MUFFLED ROAR. Heavy low-pass kills the bright
    # sparkle that used to ring; bass body dominates; a whisper of mid so it still
    # reads as rain, not wind. Deliberately NO patter/transients — nothing to jingle.
    roar = lp(RNG.standard_normal(n), 550, order=6) * 1.0
    mid = bp(RNG.standard_normal(n), 400, 1400) * 0.22
    write("rain_metal", (roar + mid) * g)

    # FAR: distant muffled wash — even softer low-pass, quieter, slower gusts.
    far = lp(RNG.standard_normal(n), 320, order=6) * 0.8
    write("rain_far", far * gusts(n, rate=0.22, depth=0.6))


if __name__ == "__main__":
    build()
    print("done — 3 natural rain loops, no pings")
