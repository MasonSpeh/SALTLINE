#!/usr/bin/env python3
"""Generate a 3-D model for EVERY catchable fish in data/fish.json, plus the upgraded
hammerhead — in PARALLEL (6 concurrent Meshy jobs) because 21 sequential generations
would take ~3 hours.

Prompts are hand-written per species from the fish table's name + note, all in the
Bloom's mutated Avatar aesthetic. Resumable: skips slugs whose .glb already exists.
"""
from __future__ import annotations
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from gen_animal import load_key, meshy_text_to_3d, download_glb  # noqa: E402

OUT = Path("assets/models/fauna")

STYLE = (", photoreal cinematic creature design, Avatar Pandora bioluminescent "
         "aesthetic, single subject, full body, plain background, no base, no plinth, "
         "no ground plane")
POSE = ", straight neutral swimming pose"

FISH: dict[str, str] = {
    "fish_copper_sprat":
        "a tiny slender alien sprat fish, burnished copper scales, a line of faint "
        "teal spark dots along the flank, delicate translucent fins" + POSE,
    "fish_herring":
        "a slender silver alien herring, a row of small glowing teal lantern orbs "
        "along its lateral line, translucent fins, luminous eye" + POSE,
    "fish_slate_cod":
        "a heavy-bodied alien cod, slate-grey stone-mottled hide like wet rock, a pale "
        "chin barbel with a softly glowing teal tip, big honest mouth, thick fins" + POSE,
    "fish_mirrorjack":
        "a sleek fast alien jack fish, chrome MIRROR scales like polished metal "
        "reflecting rainbow iridescence, deeply forked tail, long trailing fin "
        "filaments" + POSE,
    "fish_chimefish":
        "a delicate translucent alien fish with a bell-shaped glassy body, fins shaped "
        "like hanging glass chimes, a glowing pearl core visible inside, ethereal" + POSE,
    "fish_silver_ladder":
        "an elongated silver alien fish patterned with glowing ladder-rung stripes of "
        "faint teal down its whole length, slim ribbon fins" + POSE,
    "fish_ember_snapper":
        "a stocky alien snapper, dark charcoal back, warm EMBER-ORANGE glow smoldering "
        "from its gill plates and belly like coals inside, sturdy fins" + POSE,
    "fish_sable_hake":
        "a long velvet-black alien hake, sable sheen, faint teal underglow along the "
        "belly, oversized moth-like reflective eyes" + POSE,
    "fish_ghost_sole":
        "a flat alien sole fish, near-transparent ghostly body with faint pearl "
        "outlines of its organs showing through, both eyes on one side, pale" + POSE,
    "fish_glasspike":
        "a long alien pike with a completely transparent glass body, its glowing teal "
        "spine and organs clearly visible inside, needle teeth, predatory profile" + POSE,
    "fish_lodestone_bream":
        "a deep-bodied alien bream, iron-dark scales with small magnetite crystal "
        "growths, faint blue arc-light glimmers between the crystals" + POSE,
    "fish_drum_croaker":
        "a barrel-chested alien croaker fish, storm-grey with lightning-pale bands, a "
        "drum-taut glowing throat sac, blunt powerful head" + POSE,
    "fish_inkwell_squid":
        "an alien squid, ink-black mantle with a luminous teal sheen like wet ink, "
        "large intelligent eye, trailing webbed arms, mantle fins" + POSE,
    "fish_ribbon_eel":
        "a long alien ribbon eel, dark body with crackling static-blue filaments "
        "running its length, flowing ribbon dorsal fin, stretched straight" + POSE,
    "fish_barrel_grouper":
        "a huge heavy alien grouper, barrel body, massive underslung maw, mottled "
        "bronze-green hide, thick ragged fins, ancient and strong" + POSE,
    "fish_stone_crab":
        "a heavy alien crab with a ceramic-hard granite-textured shell like carved "
        "stone, thick blunt claws, short stony legs, neutral standing pose",
    "fish_gutter_prawn":
        "a pearly translucent alien prawn, glowing orange roe visible through its "
        "shell, long antennae, delicate swimming legs, curled neutral pose",
    "fish_miller_flounder":
        "a flat alien flounder camouflaged in a RUSTED STEEL DIAMOND-PLATE tread "
        "pattern like an oil rig deck, both eyes up, ragged fin fringe, lying flat "
        "neutral pose",
    "fish_fathom_halibut":
        "a door-sized colossal alien halibut, abyssal dark topside, pale glowing "
        "underside, ancient scarred hide, huge and flat and slow" + POSE,
    "the_looker":
        "a pale smooth deep-sea alien fish with ONE enormous forward-facing "
        "human-like eye filling most of its head, faint white glow, unsettling and "
        "serene, small trailing fins" + POSE,
    # The hammerhead, evolved: the Bloom kept working on it.
    "ultra_hammerhead":
        "a massive mutated alien hammerhead shark, wide flat cephalofoil with FOUR "
        "glowing eyes, two on each end of the hammer, TALL twin dorsal fins, extra "
        "oversized sweeping pectoral fins with trailing luminous filaments, deep "
        "indigo-violet body laced with branching teal vein glow, pearl belly, "
        "iridescent edge light" + POSE,
}


def one(slug: str, prompt: str, key: str) -> tuple[str, str]:
    dest = OUT / slug / f"{slug}.glb"
    if dest.exists():
        return slug, "skip (exists)"
    try:
        task = meshy_text_to_3d(key, prompt + STYLE)
        download_glb(task, dest)
        return slug, f"ok ({dest.stat().st_size / 1e6:.1f} MB)"
    except Exception as e:  # keep the batch going
        return slug, f"FAILED: {e}"


def main() -> None:
    key = load_key("meshy")
    only = set(sys.argv[1:])
    jobs = {s: p for s, p in FISH.items() if not only or s in only}
    print(f"{len(jobs)} generations, 6 concurrent")
    ok, bad = [], []
    with ThreadPoolExecutor(max_workers=6) as pool:
        futs = {pool.submit(one, s, p, key): s for s, p in jobs.items()}
        for fut in as_completed(futs):
            slug, status = fut.result()
            print(f"  {slug}: {status}", flush=True)
            (bad if "FAILED" in status else ok).append(slug)
    print(f"\nDONE  {len(ok)} ok, {len(bad)} failed")
    if bad:
        print("  failed: " + ", ".join(bad) + "   (re-run to retry)")


if __name__ == "__main__":
    main()
