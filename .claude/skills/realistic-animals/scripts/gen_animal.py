#!/usr/bin/env python3
"""Generate a realistic, (optionally) rigged + animated animal GLB with an AI 3D
generator and download it into the SALTLINE asset tree. Defaults to Tripo3D; Meshy AI
stays fully supported via --provider meshy.

Pipeline: text/image -> mesh (+PBR textures) -> [rig -> animate] -> GLB.

The animal is written to  <out>/<name>/<name>.glb  ready for Godot to import.

Requires:  TRIPO_API_KEY (or MESHY_API_KEY for --provider meshy) in the environment
           or in ./.env   (pip install requests)

Examples
--------
  python3 gen_animal.py --name lamplight_crab \
      --prompt "large deep-sea crab, mottled dark chitin, long jointed legs, raised
                pincer claws, one bioluminescent lure on a stalk, photoreal, T/neutral
                pose, full body, plain background" \
      --animate walk idle --out assets/models/fauna

  python3 gen_animal.py --name harbor_seal --image ref/seal.png --animate swim idle

  python3 gen_animal.py --name old_crab --provider meshy --prompt "..."

Notes
-----
* Tripo (default): POST /v2/openapi/task {type: text_to_model|image_to_model}, poll,
  then {type: animate_rig} -> {type: animate_retarget, animation: "preset:<clip>"} for
  each requested clip. Preset names are Tripo's, not ours — known presets include
  walk, run, idle, jump, climb, swim, fly, dive; an unrecognised name is still sent
  through and Tripo will reject it, same graceful-fallback behaviour as the Meshy path.
  UNLIKE Meshy, Tripo bakes each retargeted clip into its OWN glb, so with --animate
  you'll get <name>.glb (the static/base mesh SALTLINE actually uses — see the skill's
  Step 5 vertex-shader animation path) plus one <name>_<clip>.glb per clip that
  successfully rigged.
* Meshy (--provider meshy): preview -> refine -> [rig -> animate], all clips bundled
  into one glb. Meshy's auto-rig is CONFIRMED humanoid-only (422 on any animal) — see
  the skill doc. Kept for parity with the existing bestiary, which was generated on it.
* Endpoint paths are the newest, most likely to move part of either API. Both providers'
  rig/animate calls are wrapped so a moved or rejected endpoint reports the error and
  still leaves you the static GLB — finish rig+animate in the provider's web UI and
  re-export to the same path.
"""
from __future__ import annotations
import argparse
import json
import os
import sys
import time
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("Missing dependency: pip install requests")

MESHY = "https://api.meshy.ai/openapi"
TRIPO = "https://api.tripo3d.ai/v2/openapi"
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


# ==================================================================== Meshy AI

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
    print("[1/3] preview mesh from text (Meshy) ...")
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
    print("[1/2] mesh from image (Meshy) ...")
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
    None if the endpoints have moved / reject the model (caller falls back to the
    static mesh). CONFIRMED humanoid-only as of 2026-07-18 — this will 422 on any
    non-bipedal creature. Kept for parity; don't expect it to succeed on a crab."""
    try:
        print(f"[3/3] rig + animate {clips} (Meshy) ...")
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


def _meshy_glb_url(task: dict) -> str | None:
    return (task.get("model_urls") or {}).get("glb")


# ==================================================================== Tripo3D

def _tripo_headers(key: str) -> dict:
    return {"Authorization": f"Bearer {key}"}


def _tripo_json_headers(key: str) -> dict:
    return {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}


def _tripo_raise(r: "requests.Response", label: str) -> None:
    """raise_for_status() that KEEPS THE BODY. Tripo reports an exhausted account as a
    bare HTTP 403 whose only useful content is the JSON body
    (`{"code":2010,"message":"You don't have enough credit to create this task"}`).
    requests' own message is just "403 Client Error: Forbidden for url: ...", which
    carries no hint of the cause — so gen_fish_batch's credit detector can't see it and
    a whole batch grinds through every species failing identically instead of stopping
    on the first. Fold the body into the message so the caller can classify it."""
    if r.status_code < 400:
        return
    body = r.text[:300]
    raise requests.HTTPError(f"{label}: HTTP {r.status_code} — {body}", response=r)


## WHERE SUBMITTED TASK IDS ARE RECORDED, AND WHY IT IS HERE RATHER THAN IN THE CALLER.
## docs/AGENT_TRAPS.md: "A 'FAILED' download is usually a succeeded task — Tripo polling
## drops connections constantly in this environment, the task keeps running server-side,
## so LOG EVERY TASK ID AT SUBMIT TIME." s34 wrote a batch script that logged the id from
## the value `generate_mesh` RETURNS, which is a submit-time id recorded at completion
## time — and all five connections then dropped mid-poll, taking the ids with them. They
## were only recovered by grepping UUIDs out of the traceback text. The id has to be
## written the instant the server hands it over, which is here, before any polling.
## Recovery: GET /v2/openapi/task/<id>, pull data.output.pbr_model.
SUBMIT_LOG = Path("tests/out/tripo_submitted.jsonl")


def _record_submit(task_id: str, kind: str, note: str = "") -> None:
    try:
        SUBMIT_LOG.parent.mkdir(parents=True, exist_ok=True)
        with open(SUBMIT_LOG, "a") as f:
            f.write(json.dumps({"t": time.strftime("%Y-%m-%dT%H:%M:%S"),
                                "id": task_id, "kind": kind, "note": note[:180]}) + "\n")
    except OSError as e:      # never let bookkeeping kill a generation
        print(f"  (could not write {SUBMIT_LOG}: {e})")
    print(f"  submitted {kind} task {task_id}")


def _tripo_task_id(resp: dict) -> str:
    data = resp.get("data") or resp
    task_id = data.get("task_id")
    if not task_id:
        raise RuntimeError(f"Tripo did not return a task_id: {resp}")
    return task_id


def _tripo_poll(task_id: str, key: str, label: str) -> dict:
    """Poll a Tripo task id until it succeeds; return the unwrapped task dict (the
    `data` object — Tripo wraps every response as {code, data, message})."""
    waited = 0
    while True:
        r = requests.get(f"{TRIPO}/task/{task_id}", headers=_tripo_json_headers(key), timeout=60)
        _tripo_raise(r, f"poll:{label}")
        payload = r.json()
        task = payload.get("data", payload)
        status = task.get("status")
        prog = task.get("progress", 0)
        sys.stdout.write(f"\r  {label}: {status} {prog:>3}%   ")
        sys.stdout.flush()
        if status == "success":
            print()
            return task
        if status in ("failed", "cancelled", "unknown"):
            print()
            raise RuntimeError(f"{label} {status}: {task}")
        time.sleep(POLL_EVERY)
        waited += POLL_EVERY
        if waited > POLL_MAX:
            raise TimeoutError(f"{label} timed out after {POLL_MAX}s (id still running).")


def tripo_text_to_3d(key: str, prompt: str, model_version: str = "") -> dict:
    """Text -> textured PBR mesh in one task (Tripo doesn't split preview/refine).
    Keep the prompt under ~1000 chars; longer is silently truncated server-side."""
    print("[1/2] text -> 3D mesh (Tripo) ...")
    body = {"type": "text_to_model", "prompt": prompt[:1000], "texture": True, "pbr": True}
    if model_version:
        body["model_version"] = model_version
    r = requests.post(f"{TRIPO}/task", headers=_tripo_json_headers(key), json=body, timeout=60)
    _tripo_raise(r, "text_to_model")
    task_id = _tripo_task_id(r.json())
    _record_submit(task_id, "text_to_model", prompt)
    return _tripo_poll(task_id, key, "text-to-model")


def tripo_image_to_3d(key: str, image_path: str) -> dict:
    """Upload the reference image, then submit an image_to_model task against it."""
    print("[1/2] mesh from image (Tripo) ...")
    import mimetypes
    mime = mimetypes.guess_type(image_path)[0] or "image/png"
    with open(image_path, "rb") as f:
        r = requests.post(f"{TRIPO}/upload", headers=_tripo_headers(key),
                          files={"file": (Path(image_path).name, f, mime)}, timeout=120)
    _tripo_raise(r, "upload")
    upload = r.json()
    token = (upload.get("data") or upload).get("image_token")
    if not token:
        raise RuntimeError(f"Tripo upload did not return an image_token: {upload}")
    ext = (Path(image_path).suffix.lstrip(".") or "png").lower()
    r = requests.post(f"{TRIPO}/task", headers=_tripo_json_headers(key), json={
        "type": "image_to_model", "file": {"type": ext, "file_token": token},
        "texture": True, "pbr": True,
    }, timeout=60)
    _tripo_raise(r, "image_to_model")
    task_id = _tripo_task_id(r.json())
    _record_submit(task_id, "image_to_model", image_path)
    return _tripo_poll(task_id, key, "image-to-model")


def tripo_rig_and_animate(key: str, base_task_id: str, clips: list[str]) -> dict[str, dict]:
    """Best-effort rig + retarget, one clip at a time (Tripo's animate_retarget takes a
    single preset per call, unlike Meshy which bundles a clip list into one job).
    Returns {clip_name: task} for every clip that succeeded — may be a subset of what
    was requested, and may be empty. Never raises; a failed/unsupported clip is
    reported and skipped so the rest of the batch (and the static mesh) still land."""
    results: dict[str, dict] = {}
    try:
        print("[2/2] rig (Tripo) ...")
        r = requests.post(f"{TRIPO}/task", headers=_tripo_json_headers(key), json={
            "type": "animate_rig", "original_model_task_id": base_task_id, "out_format": "glb",
        }, timeout=60)
        _tripo_raise(r, "animate_rig")
        rig_task_id = _tripo_task_id(r.json())
        _tripo_poll(rig_task_id, key, "rig")
    except (requests.HTTPError, RuntimeError, KeyError) as e:
        print(f"  ! rigging unavailable via Tripo API ({e}). Keeping the static mesh — "
              f"rig + animate it in the Tripo web UI and export the GLB alongside it.")
        return results

    for clip in clips:
        preset = clip if clip.startswith("preset:") else f"preset:{clip}"
        try:
            r = requests.post(f"{TRIPO}/task", headers=_tripo_json_headers(key), json={
                "type": "animate_retarget", "original_model_task_id": rig_task_id,
                "out_format": "glb", "animation": preset,
            }, timeout=60)
            _tripo_raise(r, "animate_retarget")
            anim_task_id = _tripo_task_id(r.json())
            results[clip] = _tripo_poll(anim_task_id, key, f"animate:{clip}")
        except (requests.HTTPError, RuntimeError, KeyError) as e:
            print(f"  ! clip '{clip}' failed ({e}) — skipping it, continuing with the rest.")
    return results


def _tripo_glb_url(task: dict) -> str | None:
    out = task.get("output") or {}
    return out.get("pbr_model") or out.get("model") or out.get("base_model")


# ==================================================================== shared

def generate_mesh(provider: str, key: str, *, prompt: str | None = None,
                   image: str | None = None, refine: bool = True,
                   ai_model: str = "") -> dict:
    """Provider-agnostic entry point for the base (unrigged) mesh. Returns a normalised
    dict {id, glb_url, raw} — `raw` is the provider's own task shape, kept for anything
    caller-specific (e.g. Meshy's rig step needs raw["id"])."""
    if provider == "tripo":
        task = tripo_image_to_3d(key, image) if image else tripo_text_to_3d(key, prompt)
        return {"id": task.get("task_id"), "glb_url": _tripo_glb_url(task), "raw": task}
    task = meshy_image_to_3d(key, image) if image else meshy_text_to_3d(key, prompt, refine, ai_model)
    return {"id": task.get("id"), "glb_url": _meshy_glb_url(task), "raw": task}


def download_model(result: dict, dest: Path) -> None:
    """Download the normalised `generate_mesh()` result to dest."""
    url = result.get("glb_url")
    if not url:
        raise RuntimeError(f"No GLB URL in result: {result}")
    download_url(url, dest)


def download_url(url: str, dest: Path) -> None:
    print(f"  downloading GLB -> {dest}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    with requests.get(url, stream=True, timeout=300) as r:
        r.raise_for_status()
        with open(dest, "wb") as f:
            for chunk in r.iter_content(1 << 16):
                f.write(chunk)


def download_glb(task: dict, dest: Path) -> None:
    """Legacy alias kept for callers that already hold a raw Meshy task dict."""
    url = _meshy_glb_url(task)
    if not url:
        raise RuntimeError(f"No GLB in model_urls: {list((task.get('model_urls') or {}))}")
    download_url(url, dest)


def main() -> None:
    ap = argparse.ArgumentParser(description="AI animal model -> SALTLINE asset")
    ap.add_argument("--name", required=True, help="species slug, e.g. lamplight_crab")
    ap.add_argument("--prompt", help="text description (neutral full-body pose)")
    ap.add_argument("--image", help="reference image for image-to-3D (better likeness)")
    ap.add_argument("--animate", nargs="*", default=[], help="clips: walk idle swim run ...")
    ap.add_argument("--out", default="assets/models/fauna", help="output root dir")
    ap.add_argument("--provider", default="tripo", choices=["tripo", "meshy"])
    args = ap.parse_args()

    if not args.prompt and not args.image:
        sys.exit("Give --prompt or --image.")

    key = load_key(args.provider)
    dest = Path(args.out) / args.name / f"{args.name}.glb"

    result = generate_mesh(args.provider, key, prompt=args.prompt, image=args.image)
    download_model(result, dest)
    print(f"\nDone -> {dest}")

    if args.animate:
        if not result.get("id"):
            print("Note: no task id on the base mesh — skipping rig/animate.")
        elif args.provider == "tripo":
            clips = tripo_rig_and_animate(key, result["id"], args.animate)
            for clip, task in clips.items():
                clip_dest = dest.parent / f"{args.name}_{clip}.glb"
                url = _tripo_glb_url(task)
                if url:
                    download_url(url, clip_dest)
                    print(f"  clip '{clip}' -> {clip_dest}")
            missing = [c for c in args.animate if c not in clips]
            if missing:
                print(f"  clips not obtained: {', '.join(missing)} "
                      "(rig/animate it in the Tripo web UI if you need them)")
        else:
            animated = meshy_rig_and_animate(key, result["id"], args.animate)
            if animated:
                download_glb(animated, dest)
                print(f"  animated (all clips bundled) -> {dest}")
            else:
                print("Note: only the STATIC mesh downloaded; add the rig+clips in the web UI.")

    print("Next:  godot --headless --path . --import   then swap into the creature "
          "script's _build_body() (see the skill, Step 5).")


if __name__ == "__main__":
    main()
