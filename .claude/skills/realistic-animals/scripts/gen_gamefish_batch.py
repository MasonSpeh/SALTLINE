#!/usr/bin/env python3
"""s30: the owner's named REAL species — the five principal tunas, four groupers, the
mahi-mahi and the swallowtail. Tripo, six concurrent, resumable (skips existing .glb).

WHY THESE PROMPTS LOOK LIKE THIS. Every rule below is scar tissue from
docs/AGENT_TRAPS.md, and the owner asked for these to land first time:

  * NAME THE BINOMIAL AND FRAME IT AS SPECIMEN PHOTOGRAPHY. That anchors the generator's
    priors harder than any pile of adjectives — it is the single highest-leverage line in
    the whole prompt, and it is why these are the real species names rather than moods.
  * SHAPE AS A NUMERIC RATIO PLUS A PHYSICAL SIMILE. "Long and thin" is a mood, not a
    constraint; six oarfish rolls came back as ordinary fish before that was learned.
  * DESCRIBE ANATOMY THE ANIMAL ALREADY HAS, never a modification to make. Asking for a
    feature to be added deforms the whole model (it repeatedly destroyed the hammerhead).
  * STRAIGHT AND LEVEL. creature_swim.gdshader's UNDULATE body wave and the movement
    code's look_at both assume the mesh was authored as one straight line nose-to-tail.
    A model frozen mid-curve swims like a banana for ever.
  * NEGATE THE TOY LOOK AND THE PLINTH EXPLICITLY. Glassy/plastic is the default failure
    mode, and generators bed fish onto rocks and display stands that then travel with the
    mesh into the player's hand.
  * UNDER 600 CHARACTERS. Meshy truncates silently past it and eats the negatives at the
    tail; Tripo is not known to, but the ceiling is kept so a prompt can be re-run on
    either provider without quietly losing the part that keeps the fish good. Asserted.

ON THEME: these are REAL species, so the Bloom shows as a light touch — the game's
standing art direction is that mutation is adaptive and beautiful (bioluminescence,
nacre, iridescence), never gore or body horror. The tail pushes toward that and away
from deep-sea-horror tropes the model will otherwise supply on its own.
"""
from __future__ import annotations
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from gen_animal import load_key, generate_mesh, download_model  # noqa: E402

OUT = Path("assets/models/fauna")

# Straight, level, nose-to-tail — see the shader note above.
POSE = ", stretched straight and level in a neutral horizontal swimming pose"

# The shared tail. Real animal first, Bloom second, plinth never.
TAIL = (", photoreal marine specimen reference photograph, wet skin, whole body, side "
        "profile, faint iridescent nacre sheen, single subject, plain background, "
        "no base, no plinth, no ground, no rock, no coral, no hands, no text, "
        "not cartoon, not plastic, not toy, no gore")

PROMPTS: dict[str, str] = {
    # ---- the five principal tunas. Built like torpedoes: the shape IS the animal, so
    # every one of them gets the ratio and the finlet row, which is what stops a
    # generator handing back a generic fish with tuna colouring.
    "fish_bluefin_tuna":
        "Thunnus thynnus, Atlantic bluefin tuna. A massive muscular torpedo three times "
        "longer than deep, deep metallic blue-black back, silver-white belly, small "
        "yellow finlets in a row along the tail stock, stiff crescent-moon tail, tiny "
        "scales, short pectoral fins" + POSE,
    "fish_yellowfin_tuna":
        "Thunnus albacares, yellowfin tuna. A streamlined torpedo, dark metallic blue "
        "back, brilliant golden-yellow flank stripe, very long sickle-shaped bright "
        "yellow second dorsal and anal fins sweeping back, a row of yellow finlets, "
        "crescent tail" + POSE,
    "fish_bigeye_tuna":
        "Thunnus obesus, bigeye tuna. A deep-bodied heavy torpedo, dark metallic blue "
        "back, pale belly, notably HUGE round black eye for its head, moderately long "
        "pectoral fins, yellow-edged finlets along the tail stock, stiff crescent tail" + POSE,
    "fish_albacore_tuna":
        "Thunnus alalunga, albacore tuna. A compact steel-blue torpedo with an "
        "extraordinarily LONG scythe-like pectoral fin reaching most of the way down the "
        "body, dark blue back, silver belly, small finlets, crescent tail with a thin "
        "white trailing edge" + POSE,
    "fish_skipjack_tuna":
        "Katsuwonus pelamis, skipjack tuna. A small smooth scaleless torpedo, dark "
        "purple-blue back, silver belly marked with four to six bold dark horizontal "
        "stripes running the length of the lower flank, short pectoral fins, crescent "
        "tail" + POSE,

    # ---- the groupers. Heavy-bodied ambush fish: big head, huge mouth, thick tail.
    # Each one carries the marking that is its actual field mark, named exactly.
    "fish_humpback_grouper":
        "Cromileptes altivelis, humpback grouper. An odd elegant fish with a steeply "
        "humped back and a small pointed head on a long snout, pale cream-white body "
        "covered evenly in small round black polka dots, rounded fins also spotted, "
        "slender for a grouper" + POSE,
    "fish_bluelined_grouper":
        "Cephalopholis formosa, bluelined grouper. A stocky reef grouper, olive-brown "
        "body ruled with fine electric-blue horizontal pinstripes running head to tail, "
        "blue-edged rounded fins, large mouth, big dark eye" + POSE,
    "fish_leopard_grouper":
        "Plectropomus leopardus, leopard coral grouper. A powerful coral trout, vivid "
        "coral-red body scattered all over with small bright electric-blue rimmed spots, "
        "large mouth with a jutting lower jaw, forked-edged tail, sturdy fins" + POSE,
    "fish_peacock_grouper":
        "Cephalopholis argus, peacock grouper. A dark chocolate-brown body covered "
        "completely in small iridescent peacock-blue eyespots each ringed in black, five "
        "or six pale vertical bars on the rear flank, rounded fan-like tail" + POSE,

    # ---- the two showpieces.
    "fish_mahi_mahi":
        "Coryphaena hippurus, mahi-mahi dolphinfish. A tall blunt vertical forehead "
        "crest, one long dorsal fin running the entire back head to tail, electric "
        "green-gold flanks speckled blue, golden belly, deeply forked tail, twice as "
        "long as deep" + POSE,
    "fish_swallowtail":
        "Genicanthus melanospilos, swallowtail angelfish. A slender graceful angelfish "
        "with a deeply forked LYRE-shaped tail whose two long filaments trail far behind "
        "like a swallow's, pale silver-yellow body ruled with fine dark vertical bars, "
        "delicate translucent-edged fins" + POSE,
}

PROMPTS = {k: v + TAIL for k, v in PROMPTS.items()}

_OVER = {s: len(p) for s, p in PROMPTS.items() if len(p) > 600}
assert not _OVER, f"prompt(s) over the 600-char truncation ceiling: {_OVER}"


def one(slug: str, prompt: str, key: str, provider: str) -> tuple[str, str]:
    dest = OUT / slug / f"{slug}.glb"
    if dest.exists():
        return slug, f"skip (exists, {dest.stat().st_size // 1024} KB)"
    dest.parent.mkdir(parents=True, exist_ok=True)
    result = generate_mesh(provider, key, prompt=prompt)
    # LOG THE TASK ID BEFORE THE DOWNLOAD. Polling drops connections constantly in this
    # environment and a "FAILED" download is usually a task that succeeded server-side —
    # with the id you recover it with one curl instead of paying for it twice.
    print(f"[{slug}] task {result.get('id')}", flush=True)
    download_model(result, dest)
    return slug, f"OK ({dest.stat().st_size // 1024} KB)"


def main() -> None:
    provider = "tripo"
    if "--provider" in sys.argv:
        provider = sys.argv[sys.argv.index("--provider") + 1]
    only = [a for a in sys.argv[1:] if not a.startswith("--") and a in PROMPTS]
    work = {k: PROMPTS[k] for k in (only or PROMPTS)}
    key = load_key(provider)
    print(f"{len(work)} species via {provider}, 6 concurrent", flush=True)
    fails = 0
    with ThreadPoolExecutor(max_workers=6) as pool:
        futs = {pool.submit(one, s, p, key, provider): s for s, p in work.items()}
        for f in as_completed(futs):
            slug = futs[f]
            try:
                s, msg = f.result()
                print(f"  {s:<26} {msg}", flush=True)
            except Exception as e:  # noqa: BLE001
                fails += 1
                # Credit exhaustion is HTTP 403 with code:2010 in the BODY, not 402, and
                # raise_for_status() throws the body away — so print the whole thing or
                # every remaining species grinds into the same wall unexplained.
                print(f"  {slug:<26} FAILED: {e}", flush=True)
    print(f"done — {len(work) - fails}/{len(work)} ok", flush=True)


if __name__ == "__main__":
    main()
