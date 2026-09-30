# 104 WW Training Script

Standalone training scripts for DCS World, built on the native scripting engine
only (no MOOSE / MIST / CTLD). Six **independent** feature scripts, load any
or all of them, in any order.

| Script | What it does |
|---|---|
| [`TrainingRange.lua`](TrainingRange.lua) | F10 range: bombing, dogfight (missile protection + scoring), SEAD (radar + IR/AAA presets, missile protection), carrier ops, air-to-air refuelling |
| [`TRAINING_Intercept.lua`](TRAINING_Intercept.lua) | Scramble-intercept trainer with a radio menu, random target launch, failure when the target reaches its objective or leaves the box |
| [`TRAINING_GCA.lua`](TRAINING_GCA.lua) | Text Ground Controlled Approach (PAR talkdown), runway read from the airfield under the zone |
| [`TRAINING_AirCombat.lua`](TRAINING_AirCombat.lua) | Air-to-air arenas vs RED: dogfight, BVR, and a mixed group that scales to player count |
| [`JTAC.lua`](JTAC.lua) | Menu-spawned invisible spotter (MQ-9 UAV or ground JTAC) that lases RED targets; laser code and radio frequency changeable from the menu |
| [`TRAINING_Comms.lua`](TRAINING_Comms.lua) | F10 "Comms card": radio, TACAN, ICLS, Link 4 and laser code of every asset of your coalition |

In-game text and code comments are in English.

## Installation

1. Copy the `.lua` files you want into your mission folder (or keep them on disk).
2. In the Mission Editor create the zones listed below, using the exact names. A zone can be a
   **Circle** or a **Quad**: a Quad is used with the shape you draw.
3. Add one trigger per script: **MISSION START, DO SCRIPT FILE, `<file>.lua`**.
   The scripts are independent, so the load order does not matter.

Almost everything keys off zones, so there is very little to type by hand. Each script checks its
zones at load and shows a visible message if any are missing.

**Zone sizes:** the Mission Editor shows the radius in the unit set in its options. With the
editor in feet, typing `15000` makes a 15000 ft zone (4.6 km), not 15 km: the sizes below are metres.

**Defaults:** every radio, TACAN, ICLS and Link 4 value is set on the asset when it spawns, with no
extra step. `TRAINING_Comms.lua` lists them all in flight.

> The mission in this repository (`Op. White Wyverns Training.miz`) carries the current version of
> every script and loads all six. After editing a `.lua`, re-select it in its DO SCRIPT FILE trigger
> and save the mission: DCS embeds a copy of the file in the `.miz` at save time.

---

## Mission Editor reference

### TrainingRange.lua

| Zone name | Module | Suggested size |
|---|---|---|
| `TR_BOMBING` | Unarmoured targets (Ural) and the convoy spawn inside | ~3000 m |
| `TR_ARMOR_LIGHT` | Light armour (BTR-80) spawns inside | ~3000 m |
| `TR_ARMOR_HEAVY` | Heavy armour (T-90) spawns inside | ~3000 m |
| `TR_DOGFIGHT` | Dogfight arena | ~15000 m |
| `TR_SEAD_RADAR` | Radar SAM (spawns at a random point inside) | ~8000 m |
| `TR_SEAD_IR` | IR / AAA (spawns at a random point inside) | ~5000 m |
| `TR_CARRIER` | Carrier strike group spawns at its centre at mission start | any |
| `TR_REFUEL_BASKET` | Basket tanker track (a Quad's long side sets the racetrack) | Quad ~60 x 15 km |
| `TR_REFUEL_BOOM` | Boom tanker track, same | Quad ~60 x 15 km |

* **Carrier:** on station from mission start as a full group (carrier plus a cruiser, two
  destroyers and a plane-guard frigate) steaming out and back through its zone, sea room
  permitting, for the whole mission. TACAN `74X STN`, ICLS `11`, Link 4 `336.000` with ACLS and
  radio `127.500 AM` are on by default. **Call recovery** turns into the wind with the angled deck
  lined up (BRC = wind + 9) at a speed for about 27 kt of wind over the deck; **Deck status**
  gives the CASE from daylight, ceiling and visibility. **Respawn carrier** is refused while
  aircraft sit on the deck; **Reset all** does not touch the carrier.
* **Tankers:** Basket `251.000 AM / 51Y TKR`, Boom `252.000 AM / 52Y TKB`, radio and TACAN set on the
  aircraft. In a Quad zone the racetrack runs along its long side and is as long as the zone
  allows. Speed is selectable in indicated airspeed (220 to 310 KIAS) from the Refueling menu.
* **S-3B recovery tanker:** `253.000 AM / 53Y RCV`, 6000 ft, a racetrack 2 NM on the carrier's
  port side that moves with the carrier.
* **Missile protection (SEAD and dogfight):** missiles fired by the range's SAMs, and missiles
  fired between players in the dogfight arena, are destroyed just before impact and reported as a
  hit (200 m, 500 m for big warheads). It does not rely on the Immortal command, which does not
  protect client aircraft in multiplayer. Gun fire cannot be intercepted, so the range AAA keeps
  its radar on but **holds fire** by default (`AAA live fire on/off` in the menu).
* Bombing targets and the convoy are weapon-hold, so they never shoot back. The convoy loops its
  route for the whole mission.
* The F10 menu is for the BLUE coalition only.

### TRAINING_Intercept.lua

| Zone name | Purpose |
|---|---|
| `INTERCEPT_PLAYER_ZONE` | Arming area, the F10 menu appears only while a player is inside |
| `INTERCEPT_LIMIT_ZONE` | Play box: targets spawn here and the intercept fails if they leave it |
| `INTERCEPT_OBJ_1` | Objective (the target flies to the zone centre; reaching it fails the intercept) |
| `INTERCEPT_OBJ_2` | Objective |
| `INTERCEPT_OBJ_3` | Objective |

No coordinates to fill in. The menu is per flight: several clients in one group share one menu.
Tunables (scramble delay, spawn geometry, grace period, target-size presets) live in the script's `CFG`.

### TRAINING_GCA.lua

| Zone name | Purpose |
|---|---|
| `GCA_ACTIVE_ZONE` | Placed over the airfield: it picks which airfield the GCA serves |

The talkdown starts when you are airborne on final: within 10 NM of the threshold, inside 30 degrees
of the extended centreline, below 6000 ft and heading for the runway. The active end is the one most
into the wind; in calm wind, the one you are lined up for. The runway comes from the airfield
(`CFG.auto = true`); to set it by hand use `CFG.auto = false` with `runway_heading` (magnetic),
`threshold_point` and `runway_length`. Headings in the calls are magnetic.

### TRAINING_AirCombat.lua

| Zone name | Purpose |
|---|---|
| `TR_DOGFIGHT_RED` | Dogfight arena, the menu and the bandit appear while a player is inside |
| `TR_BVR_RED` | BVR arena, same engine with a radar-missile loadout |
| `TR_BVR_MIXED` | Mixed group arena, a package scaled to the number of players inside |

In the dogfight and BVR arenas you pick a type (L-39ZA, MiG-21, MiG-23, MiG-29, Su-27, F-16, F-18) and one
bandit spawns ahead of you at the far edge of the zone, same altitude, and flies at you. Only one is up at a
time, extra requests queue, and **Auto** brings up a fresh one a few seconds after each kill. The mixed arena
spawns a package whose threat budget is `players x difficulty` (Easy/Even/Hard); kills are not replaced, the
wave only grows when more players join. Leaving a zone despawns its bandits, and a bandit that stays out of
its arena for a minute is removed.

Loadouts are **guns only by default** so the dogfight works out of the box. To arm the bandits with missiles,
fill the `LOADOUTS` table at the top of the script with the weapon CLSIDs from your DCS version (they are
version-specific, so they are not hardcoded).

### JTAC.lua

Standalone (usable in any mission). Zones (Circle or Quad, create whichever you use):

| Zone name | Purpose |
|---|---|
| `JTAC_GROUND_ZONE` | The ground JTAC sits at its centre (give it line of sight to the targets) |
| `JTAC_UAV_ZONE` | The UAV orbits its centre |

From the F10 menu you spawn a **UAV spotter** (MQ-9 Reaper orbiting the zone, best line of sight) or a
**ground JTAC** (a vehicle at the zone centre). The spotter is friendly (BLUE) and made **invisible to enemy
AI** so it is not engaged. It lases the nearest visible RED target and **keeps it** until it is destroyed,
hidden or out of range, so a guided bomb in flight does not lose its spot. The lasing is driven by the script
(`Spot.createLaser`), so the **laser code** is changeable live from the menu (default `1688`). The spotter's
**radio frequency** (default `262.0 AM`) is set on the unit and shown on the comms card; the spotter does not
talk, its calls are the text messages. One spotter is up at a time.

### TRAINING_Comms.lua

No zones. One F10 entry, **Comms card (radio / TACAN / ICLS)**, that prints what your coalition's assets
have set: the ones spawned by the training scripts (carrier, tankers, S-3B, JTAC) while they exist, and the
units placed in the Mission Editor (group radio and the TACAN / ICLS / Link 4 / ACLS actions in their route:
support assets and player flights).

---

## Notes

* The scripts share no state, except the `TRAINING_COMMS` table where TrainingRange and JTAC list their
  radios for the comms card.
* The Immortal command (still sent in the dogfight and SEAD zones) protects only the host and single
  player; the missile protection is what works for clients in multiplayer.
* Requires a reasonably recent DCS build. A couple of unit type strings can vary by version, so check the
  in-game messages if a spawn fails: a failed spawn is reported, never announced as done.
