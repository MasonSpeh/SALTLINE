#!/usr/bin/env python3
"""Generate a realistic, (optionally) rigged + animated animal GLB with Meshy AI and
download it into the SALTLINE asset tree.

Pipeline: text/image -> preview mesh -> refine (PBR textures) -> [rig -> animate] -> GLB.

The animal is written to  <out>/<name>/<name>.glb  ready for Godot to import.

Requires:  MESHY_API_KEY in the environment or in ./.env   (pip install requests)

Examples
--------
  python3 gen_animal.py --name lamplight_crab \
      --prompt "large deep-sea crab, mottled dark chitin, long jointed legs, raised
                pincer claws, one bioluminescent lure on a stalk, photoreal, T/neutral
                pose, full body, plain background" \
      --animate walk idle --out assets/models/fauna

  python3 gen_animal.py --name harbor_seal --image ref/seal.png --animate swim idle

Notes
-----
* Endpoints target Meshy's public OpenAPI. If Meshy changes a path (rigging/animation
  are the newest features and move most), the script reports it and STILL leaves you the
  refined static GLB — finish rig+animate in the web UI and re-export to the same path.
* Tripo3D is an easy swap: same shape (submit -> poll -> download a GLB with skeleton).
  Set --provider tripo and TRIPO_API_KEY to use it (endpoints noted in code).
"""
from __future__ import annotations
import argparse
import os
import sys
import time
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("Missing dependency: pip install requests")

MESHY = "https://api.meshy.ai/openapi"
POLL_EVERY = 5      # seconds
POLL_MAX = 60 * 20  # give big refine/animate jobs up to 20 min


def load_key(provider: str) -> str:
    var = "TRIPO_API_KEY" if provider == "tripo" else "MESHY_API_KEY"
    key = os.environ.get(var)
    if not key:
        # tolerate a simple KEY=VALUE .env in the repo root
        env = Path(".env")
        if env.exists():
            for line in env.read_text().splitlines():
                if line.strip().startswith(var + "="):
                    key = line.split("=", 1)[1].strip().strip('"').strip("'")
                    break
    if not key:
        sys.exit(f"No {var}. Add it to your environment or ./.env (see the skill's Step 2).")
    return key


def _headers(key: str) -> dict:
    return {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}


def _poll(url: str, key: str, label: str) -> dict:
    """Poll a Meshy task id URL until it succeeds; return the final task JSON."""
    waited = 0
    while True:
        r = requests.get(url, headers=_headers(key), timeout=60)
        r.raise_for_status()
        task = r.json()
        status = task.get("status")
        prog = task.get("progress", 0)
        sys.stdout.write(f"\r  {label}: {status} {prog:>3}%   ")
        sys.stdout.flush()
        if status == "SUCCEEDED":
            print()
            return task
        if status in ("FAILED", "CANCELED", "EXPIRED"):
            print()
            raise RuntimeError(f"{label} {status}: {task.get('task_error') or task}")
        time.sleep(POLL_EVERY)
        waited += POLL_EVERY
        if waited > POLL_MAX:
            raise TimeoutError(f"{label} timed out after {POLL_MAX}s (id still running).")


def meshy_text_to_3d(key: str, prompt: str, refine: bool = True,
                     ai_model: str = "") -> dict:
    """preview -> refine, returns the refined task (with model_urls).

    Measured against the live account 2026-07-26 (`consumed_credits` on each finished
    task): a PREVIEW costs 20 credits and the REFINE pass 10 — the geometry is the
    expensive half, the opposite of what the published pricing table implies.

    `refine=False` stops after the preview and returns the untextured mesh: a third off,
    and the schools tint their surfaces from the fish table anyway, so the albedo map
    only really shows on a fish held in the hand. The returned task's `id` is the
    preview id, so a later credit top-up can refine the SAME mesh instead of paying
    full price for a new one that would also change a shape the player already knows.

    `ai_model` pins the generator ("meshy-5" / "meshy-6"); empty = the account default.
    Keep the prompt under 600 chars — Meshy truncates silently past that.
    """
    print("[1/3] preview mesh from text ...")
    body = {"mode": "preview", "prompt": prompt,
            "art_style": "realistic", "should_remesh": True}
    if ai_model:
        body["ai_model"] = ai_model
    r = requests.post(f"{MESHY}/v2/text-to-3d", headers=_headers(key), json=body, timeout=60)
    r.raise_for_status()
    preview_id = r.json()["result"]
    prev = _poll(f"{MESHY}/v2/text-to-3d/{preview_id}", key, "preview")
    if not refine:
        return prev

    print("[2/3] refine (PBR textures) ...")
    r = requests.post(f"{MESHY}/v2/text-to-3d", headers=_headers(key), json={
        "mode": "refine", "preview_task_id": preview_id,
    }, timeout=60)
    r.raise_for_status()
    refine_id = r.json()["result"]
    return _poll(f"{MESHY}/v2/text-to-3d/{refine_id}", key, "refine")


def meshy_image_to_3d(key: str, image_path: str) -> dict:
    print("[1/2] mesh from image ...")
    import base64, mimetypes
    data = Path(image_path).read_bytes()
    mime = mimetypes.guess_type(image_path)[0] or "image/png"
    data_uri = f"data:{mime};base64,{base64.b64encode(data).decode()}"
    r = requests.post(f"{MESHY}/v1/image-to-3d", headers=_headers(key), json={
        "image_url": data_uri, "should_remesh": True, "should_texture": True,
        "enable_pbr": True,
    }, timeout=120)
    r.raise_for_status()
    task_id = r.json()["result"]
    return _poll(f"{MESHY}/v1/image-to-3d/{task_id}", key, "image-to-3d")


def meshy_rig_and_animate(key: str, base_task_id: str, clips: list[str]) -> dict | None:
    """Best-effort auto-rig + animation. Returns a task with an animated model_urls, or
    None if the endpoints have moved (caller falls back to the static mesh)."""
    try:
        print(f"[3/3] rig + animate {clips} ...")
        r = requests.post(f"{MESHY}/v1/rigging", headers=_headers(key),
                          json={"input_task_id": base_task_id, "character_height": 1.0},
                          timeout=60)
        r.raise_for_status()
        rig_id = r.json()["result"]
        rig = _poll(f"{MESHY}/v1/rigging/{rig_id}", key, "rigging")
        r = requests.post(f"{MESHY}/v1/animations", headers=_headers(key),
                          json={"rigging_task_id": rig_id, "animations": clips},
                          timeout=60)
        r.raise_for_status()
        anim_id = r.json()["result"]
        return _poll(f"{MESHY}/v1/animations/{anim_id}", key, "animation")
    except (requests.HTTPError, KeyError) as e:
        print(f"  ! rig/animate step unavailable via API ({e}). Keeping the static mesh — "
              f"rig + animate it in the web UI and export the GLB to the same path.")
        return None


def download_glb(task: dict, dest: Path) -> None:
    urls = task.get("model_urls") or {}
    glb = urls.get("glb")
    if not glb:
        raise RuntimeError(f"No GLB in model_urls: {list(urls)}")
    print(f"  downloading GLB -> {dest}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    with requests.get(glb, stream=True, timeout=300) as r:
        r.raise_for_status()
        with open(dest, "wb") as f:
            for chunk in r.iter_content(1 << 16):
                f.write(chunk)


def main() -> None:
    ap = argparse.ArgumentParser(description="AI animal model -> SALTLINE asset")
    ap.add_argument("--name", required=True, help="species slug, e.g. lamplight_crab")
    ap.add_argument("--prompt", help="text description (neutral full-body pose)")
    ap.add_argument("--image", help="reference image for image-to-3D (better likeness)")
    ap.add_argument("--animate", nargs="*", default=[], help="clips: walk idle swim run ...")
    ap.add_argument("--out", default="assets/models/fauna", help="output root dir")
    ap.add_argument("--provider", default="meshy", choices=["meshy", "tripo"])
    args = ap.parse_args()

    if not args.prompt and not args.image:
        sys.exit("Give --prompt or --image.")
    if args.provider == "tripo":
        sys.exit("Tripo path: mirror this flow against https://platform.tripo3d.ai "
                 "(POST /v2/openapi/task type=text_to_model|image_to_model, poll, then "
                 "type=animate_rig / animate_retarget; download output.model GLB).")

    key = load_key(args.provider)
    base = meshy_image_to_3d(key, args.image) if args.image else meshy_text_to_3d(key, args.prompt)

    final = base
    if args.animate:
        animated = meshy_rig_and_animate(key, base["id"], args.animate)
        if animated:
            final = animated

    dest = Path(args.out) / args.name / f"{args.name}.glb"
    download_glb(final, dest)
    print(f"\nDone -> {dest}")
    print("Next:  godot --headless --path . --import   then swap into the creature "
          "script's _build_body() (see the skill, Step 5).")
    if args.animate and final is base:
        print("Note:  only the STATIC mesh downloaded; add the rig+clips in the web UI.")


if __name__ == "__main__":
    main()
