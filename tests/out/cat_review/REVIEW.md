# Ship-cat animation rebuild — review pack (s40)

**Status: awaiting human review.** Nothing here claims the cat is fixed. This file says
what changed, what the numbers say, what to watch in each clip, and what was deferred.

## How to read this directory

- `metrics_baseline.log` — the PRE-fix run of tests/CatReviewProbe: the shipped cat
  failing 18 numeric gates. This is the "all green" gap, measured.
- `metrics.json` / `metrics.md` — the POST-fix run, same gates, raw numbers.
- `*.png` — the capture reels (world-fixed cameras, `--fixed-fps`, sim-pinned deltas).

## What was wrong (all measured pre-fix; see metrics_baseline.log)

1. **The moonwalk (P1).** Gait weight was gated on a name list that excluded `stalk` and
   `carry` while the behaviour translated the body through both: stalk moved 2.68 m at
   gait weight 0.000, paws drifting 10.5 mm/frame — exactly body speed. Fixed with a
   per-pose `loco` flag; the stalk gets a folded creep gait (duty 0.78, short low steps).
2. **The look (P2).** Raw local axes: a commanded 34° pure yaw drew +4.8° yaw and 44.5°
   of ROLL; a commanded pitch-up pitched DOWN. Re-expressed in body axes through the
   frame's LIVE bases (the rest-basis map is itself ~33° wrong on a sitting cat).
3. **The head saw (P2b, unlisted in the brief).** `look()` applied new targets unsmoothed
   and two watchers alternated the focus point every frame: 0.8 rad single-frame neck
   steps. Now: strongest-claim arbitration plus a saccade-rate ease.
4. **Three clocks (P3).** The body lilt ran on its own accumulator (STRIDE_M 0.62) against
   legs planted off a bone-derived 0.356 m stride; every secondary sine ran on the wall
   clock; `clampf(k*delta)` eases snapped under AiBudget's summed 0.15 s think (the two dt
   paths disagreed by 19.7° over the same half-second). Now: one phase, one sim clock,
   `1-exp` everywhere — the dt paths agree to 0.0°.
5. **The slope (P4).** `+=` against an ease reaches rate-ratio equilibrium: −94.5° of body
   pitch at a held 0.30 slope, worn forever once the cat stopped walking. Now assigned,
   and decayed when stationary: 0.001° residual.
6. **The sideways hip (discovered).** A bone's pose position lives in its PARENT's frame,
   and this rig's Root maps local Y along the BODY axis — so every "vertical" hip write
   since s37 (sit/sleep crouches, the bob) slid the pelvis fore-aft instead. Measured:
   +0.2 Y in, (−0.2, 0, 0) out (tests/hip_bob_scratch.gd). Fixed with a frame conversion;
   the leg solver also now reads its parent from the frame's own composed pose instead of
   the Skeleton3D (which mid-tick still holds last frame — a stale socket slid every
   stance paw by the pelvis's per-frame motion).
7. **The tail (P5).** One bone, child of the right hind leg, driven as a dial. Now an
   underdamped spring (lags, ~15% overshoot on stops, counter-swings turns, walk-coupled
   sway) posed absolutely against the live parent chain — the once-per-stride hind-leg
   twitch is cancelled exactly, not approximately.
8. **No transition grammar (P6).** Now: stand→sit routes weight-back → deeper-than-target
   → target; sit→moving rises rear-first; stand→walk takes a forward lean; the jump is
   crouch (held 0.34 s on the deck) → flight (limbs on measured hinges, not the raw local
   X that was ~90° off on R_Upperarm) → fore-paws-first land → settle. The blend itself
   leads with the pelvis and trails the head, per bone.
9. **Weight (P7).** One contact-phased vertical on the same phase the paws plant from:
   minima 0.125 after each hind plant, ±5 mm walk → ±22 mm gallop with a trot-band
   bounce. Pelvis phase lock (circular std): 1.0 → 0.011 cycles.

## Numeric gates — final state

38 of 48 gates PASS (the pre-fix baseline passed 22 on the same instrument; see
metrics_baseline.log). metrics.md carries the full table. The ten rows left FAILING, each
with its mechanism — thresholds are NOT loosened per the brief's anti-gaming rules:

- `walk/slide_frame_mm 77.5` + `walk/slide_window_mm` (one pair), `lookwalk/slide 58.8`,
  `carry/slide 17.1` — a SINGLE stance pair per ~4.6 s scenario: the two-bone solve's
  singularity event. Two of this rig's chains REST on the model's degenerate boundary
  (`[cat_rig]` triangle report: rf at 99.7% of clamped reach, rh BEYOND it — the
  dead-straight bind), where d(knee)/d(target) is unbounded; the slew limiter converts the
  1.8 rad knee pop into a brief ~75 mm paw excursion instead. Steady-state stance drift
  outside that event is ~0 (139 measured pairs at a walk). Removing the event needs the
  re-rig (docs/CAT_RIG_CEILING.md §3); judge its visibility in the walk/tail reels.
- `run/joint_step 0.87`, `carry/joint_step 0.60`, `stalk/joint_step 0.42`,
  `transitions/joint_step 0.70` — the 0.35 rad/frame gate is calibrated to WALK cadence;
  a healthy gallop knee legitimately covers ~0.5-0.6 rad/frame (8.5-frame cycles), the
  trot band proportionally less, and the sit/stand grammar now blends REAL fold depths.
  Measured legit walk knees run 0.31 against the 0.333 slew ceiling — walk and lookwalk
  joint rows PASS; the faster-cadence rows read the same mechanics at their own speeds.
- `bigdt/summed_joint_step 1.30` — a 1.0 rad/think ceiling under-budgets LEGITIMATE
  motion: a walking calf genuinely covers ~1.3 rad in 0.15 s of gait. The discriminating
  facts are the equivalence gates (slope ease 0.0 deg between dt paths) and the fixed-dt
  continuity gates.
- `bigdt/turn_equivalence 6.03` vs 6.0 — the 6.0 was set to fail the shipped snap ease
  (9.4) with margin for an exponential ease; the residual is TRAJECTORY DISCRETISATION (a
  turning walk integrated at 0.15 s steps bends a different arc than at 1/60), not an
  ease fault. The threshold under-budgeted the curvature term by 0.03 deg.

## Honest residuals

- **Hind lift asymmetry (walk ~1.4, run ~1.36).** The left hind is bone-straight in bind
  pose (docs/CAT_RIG_CEILING.md §3): at its reach limit it lifts (by design — a stretched
  leg lifts its paw rather than shortening its stride) where the folded right hind does
  not. The previous "symmetric" measurements were taken while the fore-aft hip bug
  blurred all four legs; this asymmetry is the rig's true shape. Judge visibility in
  `tail_*.png` / `walk_*.png`; a re-rig with mirrored bones removes it at the source.
- **The walk-jump band.** Unchanged from KNOWN_ISSUES: rises between 0.75 and 1.25 m are
  invisible to the deck probe, so spontaneous walk-jumps are rare; the POUNCE exercises
  the full jump timeline (wind-up crouch → flight → land) reliably.
- **Ears / eyelids / real tail chain** — asset ceiling, documented with payoffs in
  docs/CAT_RIG_CEILING.md. Not faked.

## The clips — what "correct" looks like

- `walk_*.png` (side-on) / `headon_*.png`: feet plant with zero ground drift; the pelvis
  arcs OVER the planted foot (lowest just after a hind plant); the face holds the travel
  line without wander; trunk carries a small S-bend the head does not inherit.
- `hunt_*.png` (stalk approach): the creep STEPS — short, low, high-duty strides with the
  belly dropped — and freezes mid-stride; the tail is flat and flicking. The moonwalk is
  the failure mode this reel exists to disprove.
- `gift_*.png` (carry): normal walk cycle under a lifted head, tail up; legs must
  visibly step at trot pace while it closes on the player.
- `lookwalk_*.png`: the head turns ~40° to the mark and stays LEVEL (no roll-tilt) while
  the body walks on straight; on target changes the head sweeps — never teleports.
- `beh_*.png` (walk/sit/gallop/settle beats): sit goes down back-first with a visible
  weight rock and a small overshoot; standing rises rear-first; no state melts into
  another as one rigid unit.
- `wash_*.png`: strokes ride the sitting pose on body axes — the muzzle nods, the head
  does not tilt sideways; three distinguishable styles.
- `jump_*.png` (if a ledge was found; else the pounce in `hunt_*`): crouch held on the
  deck, flight stretch with symmetric limbs, fore-paws-first landing, settle.
- `idle_*.png`: breath plus occasional glances and a rare seated weight-shift; the loop
  should not read as a loop. (No ear flicks or blinks — mesh has neither; see ceiling.)
- `tail_*.png`: the tail moves as its own limb — lagged, counter-swinging, overshooting
  on the stop — with NO once-per-stride twitch synced to the right hind leg.

## Suites

- TestRunner: FAILURES: 0
- CatProbe: FAILURES: 0 (including the 150 mm/frame live-paw continuity bound and the
  burial sweep)
- CatHuntProbe: FAILURES: 0 (the full predatory sequence, now over the jump timeline)
- CatReviewProbe: 38/48 gates pass; the ten residuals above, each with a mechanism
