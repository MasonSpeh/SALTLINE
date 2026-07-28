#!/usr/bin/env python3
"""Generate the OCEAN LIFE + underwater set-dressing pass, 6 jobs in parallel.
Defaults to Tripo3D; pass --provider meshy to use Meshy AI instead.

Fills out the reef around the rig legs: the sessile colonies that make a reef read as
a reef, the slow invertebrates that reward looking closely, and a couple of deep
visitors. Everything in the Bloom's mutated-Avatar aesthetic (teal bioluminescence,
translucency, alien-but-plausible anatomy).

Resumable: skips slugs whose .glb already exists.
"""
from __future__ import annotations
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from gen_animal import load_key, generate_mesh, download_model  # noqa: E402

OUT = Path("assets/models/fauna")

STYLE = (", photoreal cinematic creature design, Avatar Pandora bioluminescent "
         "aesthetic, single subject, full body, plain background, no base, no plinth, "
         "no ground plane, nothing underneath")

OCEAN: dict[str, str] = {
    # --- the slow invertebrates: reward looking closely ---
    "bloom_nudibranch":
        "a large alien nudibranch sea slug, soft translucent pearl body with elaborate "
        "ruffled frills along its back, glowing teal and violet gradient tips on every "
        "frill, two feathery rhinophore horns, wet and jewel-like, crawling neutral pose",
    "bloom_seastar":
        "a mutated alien starfish with SEVEN thick tapering arms, deep indigo upper "
        "surface covered in raised knobs that glow teal at their tips, pale tube-foot "
        "underside, flat neutral pose",
    "bloom_urchin":
        "an alien sea urchin, dark spherical test crowded with long slender spines, each "
        "spine banded and tipped with a small teal light, faint glow between the spines, "
        "neutral pose",
    "bloom_sea_cucumber":
        "an alien sea cucumber, long soft warty body in mottled slate and rust, a crown "
        "of branching feeding tentacles at one end, faint glowing pores in rows along "
        "its flanks, resting neutral pose",
    "bloom_basket_star":
        "an alien basket star, a central disc with five arms that branch and re-branch "
        "into hundreds of fine curling tendrils, pale bone-white with teal glow "
        "concentrated at the tendril tips, spread open neutral pose",
    "bloom_feather_star":
        "an alien crinoid feather star, a small central cup with ten long feathered arms "
        "fanning upward, each arm fringed with fine pinnules, deep maroon banded with "
        "glowing teal, delicate, spread neutral pose",
    "bloom_isopod":
        "a giant alien deep-sea isopod, heavily segmented armoured plates in pale bone "
        "colour, many jointed legs, large reflective compound eyes, faint teal glow "
        "between the segment joints, standing neutral pose",
    "bloom_sea_spider":
        "a giant alien sea spider, tiny body and eight extremely long slender jointed "
        "legs, translucent pale limbs with visible glowing teal internals running "
        "through them, delicate and unsettling, standing neutral pose",
    # --- swimmers ---
    "bloom_octopus":
        "an alien octopus, bulbous mantle in shifting iridescent copper and violet, huge "
        "intelligent horizontal-pupil eyes, eight long suckered arms curling, glowing "
        "teal chromatophore spots pulsing across the skin, neutral pose",
    "bloom_anglerfish":
        "a deep-sea alien anglerfish, huge hinged jaw of glassy needle teeth, dark "
        "velvet-black skin, a long dorsal stalk arcing over its head ending in a bright "
        "glowing teal lure orb, tiny eyes, straight neutral swimming pose",
    "bloom_salp_chain":
        "a chain of alien salps, a dozen transparent barrel-shaped gelatinous bodies "
        "linked end to end into a long curving string, each barrel showing a glowing "
        "teal gut nucleus inside, glassy and translucent, neutral pose",
    # --- sessile colonies: the reef itself ---
    "bloom_coral_fan":
        "a large alien sea fan gorgonian, a flat lattice of branching arms forming a "
        "wide fan, deep violet skeleton with glowing teal polyps studded along every "
        "branch, upright neutral pose. Just the fan alone, no rock, no base",
    "bloom_brain_coral":
        "an alien brain coral boulder, dense maze-like convoluted ridges over a rounded "
        "mass, chalky pale ridges with glowing teal light down in every groove, wet and "
        "encrusted. Just the coral alone, no rock, no base",
    "bloom_sponge_cluster":
        "a cluster of alien tube sponges, several tall hollow tubes of varying height "
        "fused at the base, porous rough walls in rust and ochre, soft teal glow from "
        "deep inside each tube mouth. Just the sponges alone, no rock, no base",
    # NOTE: the first prompt ("many long tubes crowded together, each with a plume")
    # failed with image_too_complex — Meshy's preview stage chokes on a dense repeated
    # forest. Describing a SMALL number of tubes as one simple clump generates fine.
    "bloom_tube_worms":
        "five tall white tube worms standing in a simple clump, smooth leathery stalks, "
        "a soft scarlet feathery plume on top of each stalk, faint teal glow at the "
        "bases, simple clean shapes. Just the clump alone, no rock, no base",
    "bloom_sea_grass":
        "a dense clump of alien seagrass, long flat ribbon blades rising and curving, "
        "translucent green-teal with luminous veins running their length, a few blades "
        "tipped with small glowing seed pods. Just the grass alone, no soil, no base",
}


def one(slug: str, prompt: str, key: str, provider: str) -> tuple[str, str]:
    dest = OUT / slug / f"{slug}.glb"
    if dest.exists():
        return slug, "skip (exists)"
    try:
        result = generate_mesh(provider, key, prompt=prompt + STYLE)
        download_model(result, dest)
        return slug, f"ok ({dest.stat().st_size / 1e6:.1f} MB)"
    except Exception as e:
        return slug, f"FAILED: {e}"


def main() -> None:
    args = sys.argv[1:]
    provider = "tripo"
    if "--provider" in args:
        i = args.index("--provider")
        provider = args[i + 1]
        del args[i:i + 2]
    key = load_key(provider)
    only = set(args)
    jobs = {s: p for s, p in OCEAN.items() if not only or s in only}
    print(f"{len(jobs)} ocean-life generations, 6 concurrent ({provider})")
    ok, bad = [], []
    with ThreadPoolExecutor(max_workers=6) as pool:
        futs = {pool.submit(one, s, p, key, provider): s for s, p in jobs.items()}
        for fut in as_completed(futs):
            slug, status = fut.result()
            print(f"  {slug}: {status}", flush=True)
            (bad if "FAILED" in status else ok).append(slug)
    print(f"\nDONE  {len(ok)} ok, {len(bad)} failed")
    if bad:
        print("  failed: " + ", ".join(bad) + "   (re-run to retry)")


if __name__ == "__main__":
    main()
