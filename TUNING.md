# Tuning

Feel-values and where they live. Update when values move.

## data/tuning.json (loaded by PlayerState + crab)
- `hunger_per_sec` 0.00055 — "Hungry" (<50%) in ~15 min from full
- `warmth_per_sec_cold` -0.004 — flooded pump room drain
- `warmth_per_sec_night` -0.0015 — exposed decks after dark
- `warmth_per_sec_heated` +0.02 — powered space heater zone
- `crab_patrol_speed` 1.6 / `crab_pursue_speed` 3.8 (player walk 3.2 — it wins if you walk)
- `crab_detect_radius` 6.0 m (darkness only) / `crab_contact_radius` 1.2 m

## scripts/components/player_controller.gd
- Walk 3.2 / sprint 5.0 m/s; climb 1.8 m/s; stamina drain 0.2/s, regen 0.15/s
- FOV 75; head-bob amplitude 0.03; water line (fall = respawn) y=0.4

## scripts/autoload/game_clock.gd
- Dawn 3 / Day 22 / Dusk 5 / Night 8 real minutes (GDD 5.4)

## scripts/world/sun_controller.gd
- Per-phase sun/sky palettes in `_keys`; ambient clamp 0.2–0.7; spill lights ×0.55 sun

## scripts/autoload/audio_director.gd
- Bed volumes: wind -14 dB (-10 night), sea -16, hum -18 when powered
- Groan cadence: mean 50 s day / 20 s night; night one-shot range ×2

## scripts/world/rig_builder.gd
- All level geometry + interactable/waypoint positions (the level design lives here)
- Floodlights: energy 10, range 18 m, warm 2700K-ish; LightZone extents 38×9×20

## Debug keys (debug builds)
F1 next phase · F2 toggle power · F3 infinite stats · F4 teleport topside · F5 wet deck
