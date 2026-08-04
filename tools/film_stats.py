#!/usr/bin/env python3
"""Read tests/CatFilm's film.csv back as NUMBERS — the half of the instrument that the PNGs
cannot carry.

The owner's two open complaints about the cat are both quantities, not impressions:

  "still choppy"  -> the paws must not stop and restart inside a swing. Cosine-easing every
                     key of a 6-key cycle table zeroes the paw's velocity at EVERY key, so a
                     160 ms swing chopped into three keyed segments comes to a dead halt
                     three times. That shows up here as `stops/cycle`.
  "looks to the side when walking" -> the drawn face must sit on the authored travel bearing.
                     `face_rel` is signed degrees off it, and because CatFilm calibrates the
                     head's forward axis against the REST pose, any non-zero value is the
                     animation's own doing.

Also reports left/right symmetry, because this Tripo rig's hind legs are not the same length
(L_Thigh->L_Calf 0.336 m vs R_Thigh->R_Calf 0.086 m, tests/BoneDump) and the runtime gait
applies the same angles to both — an asymmetric swing reads as a limp, and a limp reads as
choppy.

    python3 tools/film_stats.py /tmp/f38a/film.csv
"""
import csv
import math
import sys
from collections import defaultdict

PAWS = ["lf", "rf", "lh", "rh"]


def load(path):
    rows = []
    with open(path) as f:
        for r in csv.DictReader(f):
            rows.append(r)
    return rows


def fl(r, k):
    try:
        return float(r[k])
    except (TypeError, ValueError, KeyError):
        return 0.0


def series(rows, key):
    return [fl(r, key) for r in rows]


def stats(v):
    if not v:
        return (0.0, 0.0, 0.0)
    m = sum(v) / len(v)
    return (m, max(v), min(v))


def rms(v):
    if not v:
        return 0.0
    return math.sqrt(sum(x * x for x in v) / len(v))


def paw_track(rows, paw, space):
    sfx = "s" if space == "skel" else "w"
    return [
        (fl(r, f"{paw}_{sfx}x"), fl(r, f"{paw}_{sfx}y"), fl(r, f"{paw}_{sfx}z"))
        for r in rows
    ]


def speeds(track, dt):
    out = []
    for i in range(1, len(track)):
        a, b = track[i - 1], track[i]
        d = math.dist(a, b)
        out.append(d / dt if dt > 0 else 0.0)
    return out


def count_stops(sp, floor_frac=0.18):
    """How many times per reel the paw's speed dips into a near-stop and comes back.

    A real swinging limb accelerates once, carries, and decelerates once into the plant: ONE
    stop per cycle. A cosine ease on every key stops it at every key. The threshold is a
    fraction of the track's own peak so it is scale-free.
    """
    if not sp:
        return 0, 0.0
    peak = max(sp)
    if peak <= 1e-9:
        return 0, 0.0
    floor = peak * floor_frac
    stops = 0
    below = False
    for s in sp:
        if s < floor and not below:
            below = True
            stops += 1
        elif s >= floor:
            below = False
    return stops, peak


def jerk_index(sp, dt):
    """Mean |d(speed)/dt| normalised by mean speed — dimensionless "how ragged is the motion".

    Smooth sinusoidal motion at cycle rate f gives roughly 2*pi*f. Anything far above that is
    the interpolator, not the gait.
    """
    if len(sp) < 3:
        return 0.0
    acc = [abs(sp[i] - sp[i - 1]) / dt for i in range(1, len(sp))]
    mean_sp = sum(sp) / len(sp)
    if mean_sp <= 1e-9:
        return 0.0
    return (sum(acc) / len(acc)) / mean_sp


def cycles(rows):
    """How many gait cycles the reel covers, from the phase column's wraps."""
    ph = series(rows, "phase")
    n = 0
    for i in range(1, len(ph)):
        if ph[i] < ph[i - 1] - 0.5:
            n += 1
    return max(n, 1)


def report(path):
    rows = load(path)
    if not rows:
        print("no rows in %s" % path)
        return
    by_reel = defaultdict(list)
    for r in rows:
        by_reel[r["reel"]].append(r)

    dts = series(rows, "dt")
    dmin, dmax = min(dts), max(dts)
    print("=" * 78)
    print("FILM %s — %d sim rows, %d reels" % (path, len(rows), len(by_reel)))
    print("dt %.5f..%.5f s" % (dmin, dmax), end="  ")
    if dmax - dmin > 0.002:
        print("*** NOT PINNED — re-run with --fixed-fps; these numbers are contaminated ***")
    else:
        print("PINNED — the shutter cannot reach the simulation")
    print("=" * 78)

    for reel, rr in by_reel.items():
        # Skip the staging teleport that opens every reel.
        rr = [r for r in rr if fl(r, "moved") < 1.0]
        if len(rr) < 8:
            continue
        dt = sum(series(rr, "dt")) / len(rr)
        ncyc = cycles(rr)
        print("\n--- reel %-9s  %4d frames  %.2f s  %d gait cycles  pose=%s"
              % (reel, len(rr), len(rr) * dt, ncyc, rr[-1]["pose"]))

        # ---- the owner's head-straightness question
        fr = series(rr, "face_rel")
        nr = series(rr, "neck_rel")
        srl = series(rr, "spine_rel")
        br = series(rr, "body_rel")
        print("  HEAD OFF TRAVEL LINE   face %+6.2f deg mean, %+6.2f worst, %5.2f rms"
              % (sum(fr) / len(fr), max(fr, key=abs), rms(fr)))
        print("    attributed:          neck %+6.2f mean / %+6.2f worst   spine %+6.2f / %+6.2f"
              % (sum(nr) / len(nr), max(nr, key=abs), sum(srl) / len(srl), max(srl, key=abs)))
        print("    node (body) yaw:     %+6.2f mean, %+6.2f worst   pitch %+6.2f mean  up_y %.3f"
              % (sum(br) / len(br), max(br, key=abs),
                 sum(series(rr, "pitch")) / len(rr), min(series(rr, "up_y"))))

        # ---- body travel smoothness
        mv = [m for m in series(rr, "moved")]
        mm, mx, mn = stats(mv)
        print("  BODY STEP              %.1f mm mean, %.1f max, %.1f min  (%.0f%% spread)"
              % (mm * 1000, mx * 1000, mn * 1000,
                 100.0 * (mx - mn) / mm if mm > 1e-9 else 0.0))

        # ---- the choppiness itself
        print("  PAW MOTION (skeleton space — the animation alone)")
        print("    %-4s %8s %8s %8s %9s %8s" %
              ("paw", "peak m/s", "mean", "stops/cyc", "jerk idx", "swing m"))
        stop_tot = []
        for p in PAWS:
            tr = paw_track(rr, p, "skel")
            sp = speeds(tr, dt)
            stops, peak = count_stops(sp)
            per_cyc = stops / ncyc
            stop_tot.append(per_cyc)
            xs = [t[0] for t in tr]
            swing = max(xs) - min(xs)
            print("    %-4s %8.3f %8.3f %8.2f %9.1f %8.3f"
                  % (p, peak, sum(sp) / len(sp), per_cyc, jerk_index(sp, dt), swing))
        print("    -> a clean swing is ~1 stop/cycle (the plant). %.1f means the"
              % (sum(stop_tot) / len(stop_tot)))
        print("       interpolator is stopping the paw at every key, not the gait.")

        # ---- left/right symmetry: the bone-length asymmetry, as drawn
        for a, b, label in [("lf", "rf", "fore"), ("lh", "rh", "hind")]:
            ta, tb = paw_track(rr, a, "skel"), paw_track(rr, b, "skel")
            ra = max(t[0] for t in ta) - min(t[0] for t in ta)
            rb = max(t[0] for t in tb) - min(t[0] for t in tb)
            ya = max(t[1] for t in ta) - min(t[1] for t in ta)
            yb = max(t[1] for t in tb) - min(t[1] for t in tb)
            ratio = (ra / rb) if rb > 1e-6 else 0.0
            flag = "  <== LIMP" if (ratio > 1.35 or ratio < 0.74) else ""
            print("  SYMMETRY %-5s  fore/aft swing L %.3f R %.3f  ratio %.2f%s"
                  % (label, ra, rb, ratio, flag))
            print("                 lift        L %.3f R %.3f  ratio %.2f"
                  % (ya, yb, (ya / yb) if yb > 1e-6 else 0.0))

        # ---- world-space paw: does a stance paw slide? (foot-lock / skating)
        print("  PAW SKATE (world space, lowest 40%% of the lift range = stance)")
        for p in PAWS:
            tw = paw_track(rr, p, "world")
            ts = paw_track(rr, p, "skel")
            ys = [t[1] for t in ts]
            lo, hi = min(ys), max(ys)
            gate = lo + (hi - lo) * 0.4
            slide, n = 0.0, 0
            for i in range(1, len(tw)):
                if ys[i] <= gate and ys[i - 1] <= gate:
                    slide += math.dist(tw[i - 1], tw[i])
                    n += 1
            if n:
                print("    %-4s stance frames %4d, mean slide %.1f mm/frame (%.2f m/s)"
                      % (p, n, slide / n * 1000, slide / n / dt))


if __name__ == "__main__":
    for a in sys.argv[1:] or ["/tmp/f38a/film.csv"]:
        report(a)
