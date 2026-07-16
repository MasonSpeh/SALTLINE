# Model Library — Licensing & Sources

All glTF models in this directory are from **Poly Haven** (https://polyhaven.com),
licensed **CC0 1.0 Universal** (public domain — no attribution required, commercial
use OK). Downloaded 2026-07-16 as 1K-texture glTF (`.gltf` + `.bin` + `textures/`),
mobile-friendly per GDD §21.

Each folder = one Poly Haven asset_id (view at https://polyhaven.com/a/<id>).
Loaded at runtime through `scripts/world/prop_lib.gd` — `PropLib.spawn(id, ...)`
auto-normalizes each model's scale to a real-world size (see SIZE_HINT there).

## Re-download / add more
```
python3 <<'PY'
import urllib.request, json, os
aid = "metal_toolbox"           # any Poly Haven model asset_id
j = json.loads(urllib.request.urlopen(f"https://api.polyhaven.com/files/{aid}").read())
g = j["gltf"]["1k"]["gltf"]
folder = f"assets/models/{aid}"; os.makedirs(folder+"/textures", exist_ok=True)
def save(u,p):
    open(os.path.join(folder,p),"wb").write(urllib.request.urlopen(u).read())
save(g["url"], f"{aid}.gltf")
for rel,info in g["include"].items(): save(info["url"], rel)
PY
```

## Inventory (86 assets)
barrels: Barrel_01, Barrel_02, barrel_03, barrel_stove ·
crates/boxes: wooden_crate_01/02, wooden_military_crate, old_military_crate,
plastic_crate_01/02, ammo_box, medical_box, utility_box_01/02 ·
fuel/gas: metal_jerrycan(+_green), plastic_jerrycan, propane_tank, small_lpg_tank,
propane_torch · cans/tins: oil_tin, small_oil_can_01, cleaner_tin_01, can_rusted,
russian_food_cans_01, long_life_food · tools: metal_toolbox, metal_tool_chest,
tool_cart, industrial_storage_cart, hand_truck, portable_welding_cart, pipe_wrench ·
safety: korean_fire_extinguisher_01, fire_alarm, lifebuoy, life_jacket, ocean_buoy,
old_gas_mask, WetFloorSign_01 · buckets/bins: wooden_bucket_01/02, metal_trash_can,
cement_bag · lighting: Lantern_01, hanging_industrial_lamp, industrial_wall_lamp,
industrial_pipe_lamp, caged_hanging_light, mounted_fluorescent_lights, security_light,
vintage_flashlight, portable_searchlight · seating: metal_stool_01/02,
plastic_monobloc_chair_01, folding_wooden_stool, wooden_stool_01, painted_wooden_chair_01 ·
tables: metal_office_desk, dining_table, small_wooden_table_01 · beds: old_bed_frame,
vintage_day_bed · storage: steel_frame_shelves_01/02, worn_metal_rack,
wooden_bookshelf_worn, drawer_cabinet · kitchen: modified_thermos, plastic_thermos,
vintage_electric_kettle · paperwork: binder_notebook, office_notepads · electronics:
vintage_radio_transceiver, boombox, retro_multimeter, television_02, power_box_01 ·
machinery: portable_generator · pipes: modular_industrial_pipes_01, modular_pipes ·
misc: old_tyre
