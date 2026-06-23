# 104 WW Training Script

Standalone training scripts for DCS World, built on the native scripting engine
only (no MOOSE / MIST / CTLD). Five **independent** feature scripts, load any
or all of them, in any order.

| Script | What it does |
|---|---|
| [`TrainingRange.lua`](TrainingRange.lua) | F10 range: bombing, dogfight (immortal + scoring), SEAD (radar + IR/AAA presets), carrier ops, air-to-air refuelling |
| [`TRAINING_Intercept.lua`](TRAINING_Intercept.lua) | Scramble-intercept trainer with a radio menu, random target launch and boundary despawn |
| [`TRAINING_GCA.lua`](TRAINING_GCA.lua) | Text Ground Controlled Approach, auto-detects the runway under the zone |
| [`TRAINING_AirCombat.lua`](TRAINING_AirCombat.lua) | Air-to-air arenas vs RED: dogfight, BVR, and a mixed group that scales to player count |
| [`TRAINING_JTAC.lua`](TRAINING_JTAC.lua) | Menu-spawned invisible spotter (MQ-9 UAV or ground JTAC) that lases RED targets on a set code/frequency |

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

Zones are Circle, except the two tanker zones which may also be Quad.

| Zone name | Module | Suggested radius |
|---|---|---|
| `TR_BOMBING` | Unarmoured targets (Ural) spawn inside | ~3000 m |
| `TR_ARMOR_LIGHT` | Light armour (BTR-80) spawns inside | ~3000 m |
| `TR_ARMOR_HEAVY` | Heavy armour (T-90) spawns inside | ~3000 m |
| `TR_DOGFIGHT` | Dogfight arena | ~15000 m |
| `TR_SEAD_RADAR` | Radar SAM (spawns at a random point inside) | ~8000 m |
| `TR_SEAD_IR` | IR / AAA (spawns at a random point inside) | ~5000 m |
| `TR_CARRIER` | Carrier strike group spawns here at mission start | ~2000 m |
| `TR_REFUEL_BASKET` | Basket tanker racetrack (fits inside, circle or quad) | ~10000 m |
| `TR_REFUEL_BOOM` | Boom tanker racetrack (fits inside, circle or quad) | ~10000 m |

The carrier is on station from mission start as a full group (carrier plus a cruiser, two destroyers
and a plane-guard frigate) in formation. From the Carrier Ops menu you set the group speed and its
ROE (Engage, or Defend only so it does not fire on ground units it passes). Tanker speed is selectable
(Mach 0.3 to 0.6) from the Refueling menu. Bombing targets are weapon-hold. Escorts are configurable
in `TR_Config.carrier.escorts`. No coordinates to fill in for any of these.

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
| `GCA_ACTIVE_ZONE` | Coverage area, placed over the airfield. The talkdown runs while a player is inside |

By default (`CFG.auto = true`) the script finds the airfield under the zone, reads its runways and
picks the active one (most into the wind, longest as a tiebreaker), deriving the heading and threshold
automatically when you start the approach. To set the runway by hand instead, use `CFG.auto = false`
and fill in `runway_heading` and `threshold_point`. `glideslope_angle` (default `3.0`) is used in both
modes.

### TRAINING_AirCombat.lua

Zones (type: Circle):

| Zone name | Purpose |
|---|---|
| `TR_DOGFIGHT_RED` | Dogfight arena, the menu and the bandit appear while a player is inside |
| `TR_BVR_RED` | BVR arena, same engine with a radar-missile loadout |
| `TR_BVR_MIXED` | Mixed group arena, a package scaled to the number of players inside |

In the dogfight and BVR arenas you pick a type (L-39ZA, MiG-21, MiG-23, MiG-29, Su-27, F-16, F-18) and one
bandit spawns ahead of you at the far edge of the zone, same altitude. Only one is up at a time, extra
requests queue, and **Auto** brings up a fresh one a few seconds after each kill. The mixed arena spawns a
package whose threat budget is `players x difficulty` (Easy/Even/Hard). Leaving a zone despawns its bandits.

Loadouts are **guns only by default** so the dogfight works out of the box. To arm the bandits with missiles,
fill the `LOADOUTS` table at the top of the script with the weapon CLSIDs from your DCS version (they are
version-specific, so they are not hardcoded). A bad CLSID falls back to guns automatically.

### TRAINING_JTAC.lua

Zone (type: Circle):

| Zone name | Purpose |
|---|---|
| `TR_JTAC` | Where the ground JTAC sits / the UAV orbits. Place it on the range with line of sight to the targets. |

From the F10 menu you spawn a **UAV spotter** (MQ-9 Reaper orbiting the zone, best line of sight) or a
**ground JTAC** (a vehicle at the zone centre). The spotter is friendly (BLUE) and made **invisible to enemy
AI** so it is not engaged, and it autonomously lases RED targets in view. The laser code (default `1688`) and
radio frequency (default `251.0 AM`) are set in `CFG` and announced on spawn; set your pod/bomb to the same
code. One spotter is up at a time. (The exact FAC behaviour can vary by DCS version; `1688` is the reliable
default.)

---

## Notes

* The five scripts share no state and can be used à la carte.
* Dogfight and SEAD zones in `TrainingRange.lua` make players immortal while inside (training, no real losses).
* Requires a reasonably recent DCS build. A couple of unit type strings and the TACAN beacon
  parameters can vary by version, so check the in-game messages if a spawn fails.
