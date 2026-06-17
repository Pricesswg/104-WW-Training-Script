# 104 WW Training Script

Standalone training scripts for DCS World, built on the native scripting engine
only (no MOOSE / MIST / CTLD). Three **independent** feature scripts, load any
or all of them, in any order.

| Script | What it does |
|---|---|
| [`TrainingRange.lua`](TrainingRange.lua) | F10 range: bombing, dogfight (immortal + scoring), SEAD (radar + IR/AAA presets), carrier ops, air-to-air refuelling |
| [`TRAINING_Intercept.lua`](TRAINING_Intercept.lua) | Scramble-intercept trainer with a radio menu, random target launch and boundary despawn |
| [`TRAINING_GCA.lua`](TRAINING_GCA.lua) | Text Ground Controlled Approach (talkdown to a configured runway) |

In-game text and code comments are in English.

## Installation

1. Copy the `.lua` files you want into your mission folder (or keep them on disk).
2. In the Mission Editor create the **Circle** zones listed below, using the exact names.
3. Fill in the coordinates / config values marked **FILL IN** at the top of each script.
4. Add one trigger per script: **MISSION START → DO SCRIPT FILE → `<file>.lua`**.
   The scripts are independent, so the load order does not matter.

> Each script verifies its zones at load and shows a visible error if any are missing.

---

## Mission Editor reference

### TrainingRange.lua

Zones (type: Circle — radius is a suggestion):

| Zone name | Module | Suggested radius |
|---|---|---|
| `TR_BOMBING` | Bombing range | ~3000 m |
| `TR_DOGFIGHT` | Dogfight arena | ~15000 m |
| `TR_SEAD_RADAR` | Radar SAM zone | ~8000 m |
| `TR_SEAD_IR` | IR / AAA zone | ~5000 m |

Coordinates to fill in (`TR_Config`, world x/z — carrier and tankers do **not** use ME zones):

| Field | Purpose |
|---|---|
| `sead.radarSpawnPoint` | Radar SAM site centre |
| `sead.irSpawnPoint` | IR / AAA site centre |
| `carrier.spawnPoint` | Carrier start position |
| `refueling.basket.spawnPoint` | Basket (probe-and-drogue) tanker track |
| `refueling.boom.spawnPoint` | Boom tanker track |

Other commonly-tuned `TR_Config` values: `carrier.type` (default `"Stennis"`), tanker
TACAN/frequency blocks, `coalition` (monitored player side, default BLUE).

### TRAINING_Intercept.lua

Zones (type: Circle):

| Zone name | Purpose |
|---|---|
| `INTERCEPT_PLAYER_ZONE` | Arming area — the F10 menu appears only while a player is inside |
| `INTERCEPT_LIMIT_ZONE` | Play box: targets spawn here and despawn if they leave it |
| `INTERCEPT_OBJ_1` | Objective waypoint (target flies toward the zone centre) |
| `INTERCEPT_OBJ_2` | Objective waypoint |
| `INTERCEPT_OBJ_3` | Objective waypoint |

No coordinates to fill in — everything keys off the zones above. Tunables live in
`CFG`: scramble delay (`60–180 s`), spawn geometry, grace period, target size presets.

### TRAINING_GCA.lua

Zone (type: Circle):

| Zone name | Purpose |
|---|---|
| `GCA_ACTIVE_ZONE` | Coverage area — the talkdown runs while a player is inside |

Runway is defined in `CFG` (not by a zone):

| Field | Purpose | Default |
|---|---|---|
| `runway_heading` | Landing runway heading, degrees true | `250` — **set for your runway** |
| `threshold_point` | World x/z of the landing threshold | `{x=0, z=0}` — **FILL IN** |
| `glideslope_angle` | Target glideslope, degrees | `3.0` |

---

## Notes

- The three scripts share no state and can be used à la carte.
- Dogfight and SEAD zones make players immortal while inside (training, no real losses).
- Requires a reasonably recent DCS build; a couple of unit type strings and the TACAN
  beacon parameters can vary by version — check the in-game messages if a spawn fails.
