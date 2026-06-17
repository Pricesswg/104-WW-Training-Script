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
3. Add one trigger per script: **MISSION START, DO SCRIPT FILE, `<file>.lua`**.
   The scripts are independent, so the load order does not matter.

Almost everything keys off zones, so there is very little to type by hand. The only manual
values are the GCA runway (heading and threshold). Each script checks its zones at load and
shows a visible message if any are missing.

---

## Mission Editor reference

### TrainingRange.lua

Zones (type: Circle, radius is a suggestion):

| Zone name | Module | Suggested radius |
|---|---|---|
| `TR_BOMBING` | Bombing range (targets spawn inside) | ~3000 m |
| `TR_DOGFIGHT` | Dogfight arena | ~15000 m |
| `TR_SEAD_RADAR` | Radar SAM (spawns at a random point inside) | ~8000 m |
| `TR_SEAD_IR` | IR / AAA (spawns at a random point inside) | ~5000 m |
| `TR_CARRIER` | Carrier strike group spawns at the centre | ~2000 m |
| `TR_REFUEL_BASKET` | Basket tanker orbit anchor (random inside) | ~10000 m |
| `TR_REFUEL_BOOM` | Boom tanker orbit anchor (random inside) | ~10000 m |

The carrier spawns as a full group (carrier plus a cruiser, two destroyers and a plane-guard
frigate) in formation, steaming together as a reference for recovery. Edit the escort types and
positions in `TR_Config.carrier.escorts`. No coordinates to fill in for any of these.

### TRAINING_Intercept.lua

Zones (type: Circle):

| Zone name | Purpose |
|---|---|
| `INTERCEPT_PLAYER_ZONE` | Arming area, the F10 menu appears only while a player is inside |
| `INTERCEPT_LIMIT_ZONE` | Play box: targets spawn here and despawn if they leave it |
| `INTERCEPT_OBJ_1` | Objective waypoint (target flies toward the zone centre) |
| `INTERCEPT_OBJ_2` | Objective waypoint |
| `INTERCEPT_OBJ_3` | Objective waypoint |

No coordinates to fill in. Tunables (scramble delay, spawn geometry, grace period, target-size
presets) live in the script's `CFG`.

### TRAINING_GCA.lua

Zone (type: Circle):

| Zone name | Purpose |
|---|---|
| `GCA_ACTIVE_ZONE` | Coverage area, the talkdown runs while a player is inside |

Runway is defined in `CFG` (not a zone):

| Field | Purpose | Default |
|---|---|---|
| `runway_heading` | Landing runway heading, degrees true | `250`, set for your runway |
| `threshold_point` | World x/z of the landing threshold | `{x=0, z=0}`, fill this in |
| `glideslope_angle` | Target glideslope, degrees | `3.0` |

---

## Notes

* The three scripts share no state and can be used à la carte.
* Dogfight and SEAD zones make players immortal while inside (training, no real losses).
* Requires a reasonably recent DCS build. A couple of unit type strings and the TACAN beacon
  parameters can vary by version, so check the in-game messages if a spawn fails.
