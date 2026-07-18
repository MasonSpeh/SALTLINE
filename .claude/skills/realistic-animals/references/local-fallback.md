# Offline generation on Apple Silicon (no API, no credits)

Use when the user has no API key/credits and wants to generate locally. The M1/16GB Mac
can run lightweight **image-to-3D** models via PyTorch MPS. These produce a **static**
mesh only — you rig + animate afterward in Blender.

## TripoSR (lightest, best fit for M1)

Single-image → mesh, runs in ~1–2 min on MPS.

```bash
python3 -m venv .venv-3d && source .venv-3d/bin/activate
pip install torch torchvision   # MPS build
git clone https://github.com/VAST-AI-Research/TripoSR && cd TripoSR
pip install -r requirements.txt
python run.py ../ref/crab.png --output-dir out/ --device mps --model-save-format obj
```

Feed it a clean side/3-4 photo of the animal on a plain background (remove the background
first — `rembg` helps). Output is an untextured/vertex-coloured OBJ.

Heavier alternatives if the GPU allows: **InstantMesh**, **Hunyuan3D-2** (better quality,
much slower / more memory on M1 — expect minutes and swapping).

## Rig + animate in Blender (free)

Local generators don't rig. Blender does it free:

1. Import the OBJ/GLB, clean up (decimate to ~10–20k tris, recompute normals, scale to
   real size in metres).
2. **Rigify** or a manual armature: for a quadruped/crab, add bones for spine + each leg,
   parent with automatic weights.
3. Key 2–3 loops: `idle` (subtle) and `walk`/`swim`. Even 12–20 frames reads fine in-game.
4. Export **glTF 2.0 (.glb)**, "Include → Selected Objects", "Animation → Export
   Deformation Bones only", to `assets/models/fauna/<species>/<species>.glb`.

Then follow the skill from **Step 4** (Godot import) onward — identical from there.

## Reality check

Local + Blender is a real time cost (an hour+ per animal for a good rig). For a solo dev
who wants several animals fast, the hosted services (Meshy/Tripo) that output a rigged,
animated GLB in one shot are usually worth the free-tier credits. Reserve local for when
there's no network/budget or you need full control over the mesh.
