# 104 WW Training Script

Standalone training scripts for DCS World, built on the native scripting engine
only (no MOOSE / MIST / CTLD). Six **independent** feature scripts, load any
or all of them, in any order.

| Script | What it does |
|---|---|
| [`TrainingRange.lua`](TrainingRange.lua) | F10 range: bombing (with impact scores), strafe pit, dogfight (missile protection + scoring), SEAD (radar + IR/AAA presets, missile protection, SAMs that go dark for a HARM), carrier ops with LSO landing grades, air-to-air refuelling, range drawn on the F10 map |
| [`TRAINING_Intercept.lua`](TRAINING_Intercept.lua) | Scramble-intercept trainer with a radio menu, random target launch, failure when the target reaches its objective or leaves the box, Bogey dope (BRAA) on request |
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
A Quad can be rotated and stretched freely; keep it convex (no corner pushed inward).

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
| `TR_STRAFE` | Strafe pit: the targets stand at its centre, the run-in heading is in `TR_Config.strafe` (a Quad's long side sets it) | ~200 m |

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
* **LSO landing grades:** every player approach to the carrier is graded as a landing signal officer
  does. Glideslope (3.5 degrees to the 3-wire), line-up and angle of attack are checked at the start
  (3/4 NM), in the middle, in close and at the ramp, in the LSO shorthand: `(LO)` a little low, `LO`
  low, `_LO_` well low, likewise `H`, `LUL`/`LUR`, `F`/`SLO`. The grade follows the MOOSE Airboss rule:
  `OK` with at most small deviations, `(OK)` with a normal one, `--` with a large one; `-- (BOLTER)`,
  `WO` (waved off: more than 1.8 degrees high, 1.2 low or 3 off the centreline in close), `OWO` (own
  wave-off), `CUT` (landed after a wave-off). The wire comes from where the aircraft stops. Live calls
  in the groove ("Roger ball", "Power", "Right for lineup", "You're slow", "Wave off") can be switched
  off; **LSO grades (greenie board)** lists everyone with their average points. With a Supercarrier
  (`CVN_71`..`CVN_75`) DCS grades the landing too, and its grade is passed on as it is. Deck
  measurements (stern, wires, deck height, angle) are the ones the Airboss authors took in DCS for the
  Stennis, the Supercarrier Nimitz class and the Forrestal; AoA bands are for the F/A-18C and the F-14.
* **Missile protection (SEAD and dogfight):** missiles fired by the range's SAMs, and missiles
  fired between players in the dogfight arena, are destroyed just before impact and reported as a
  hit (200 m, 500 m for big warheads). It does not rely on the Immortal command, which does not
  protect client aircraft in multiplayer. Gun fire cannot be intercepted, so the range AAA keeps
  its radar on but **holds fire** by default (`AAA live fire on/off` in the menu).
* Bombing targets and the convoy are weapon-hold, so they never shoot back. The convoy loops its
  route for the whole mission.
* **Strafe pit:** three T-90s in a row at the centre of `TR_STRAFE`, up from mission start (a dead one
  comes back after 10 s). A pass starts when you are in the 3000 x 300 m box in front of them, below
  3000 ft and flying toward them, and ends when you leave it: *"Eagle1: 23 hits of 61 rounds, 38%,
  INEFFECTIVE PASS"*. Hits are the gun rounds that hit a target, rounds fired the drop in your ammo
  count. A hit or a burst from inside the foul line (2000 ft) makes the pass invalid. Grades from 90%
  (DEADEYE), 75 (EXCELLENT), 50 (GOOD), 25 (INEFFECTIVE), as the MOOSE range. **Scores** lists the pit
  next to the bombs.
* **Bombing scores:** every bomb, rocket and air-to-ground missile a player releases within 30 km of
  the bombing zones is followed to the ground. The pilot gets the distance from the nearest range
  target, the clock position seen along the attack heading (12 o'clock = long, 6 o'clock = short)
  and a grade (SHACK within 1.5 m, EXCELLENT 12.5 m, GOOD 25 m, INEFFECTIVE 50 m, else POOR, the
  MOOSE range defaults); a ripple or a rocket salvo comes as one line with the best and the average.
  Cluster dispensers are projected to the ground from where they open. **Scores** in the Bombing
  Range menu lists every player; impacts more than 1000 m from any target are not scored.
* **HARM reaction:** a range SAM an anti-radiation missile comes at switches its radar off after 3 to
  10 s (the crew reacting) and back on 20 to 45 s after the missile has gone, so the shooter sees it
  drop off the RWR. The site is the missile's target when the launch had one, otherwise the emitter
  it flies at. The Rapier (optical) and the IR missiles have no radar and do not react. On by
  default, `HARM reaction on/off` in the Radar Zone menu.
* **F10 map:** the range zones with their names, the strafe pit's box and foul line, each tanker's track
  with its radio, TACAN, level and speed, the S-3B track and the carrier with its comms and BRC are
  drawn for BLUE, and follow the
  assets (removed with them, redrawn when a speed or a course changes). `Map drawings on/off` in the
  range menu.
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

**Bogey dope:** while a target is airborne, every BLUE flight has an F10 command `Bogey dope
(intercept)`, wherever it is. Each pilot of the flight gets the targets in BRAA from their own
aircraft, closest first: *"Springfield 1-1, group BRAA 355/18, 20 thousand, HOT, HOSTILE."* Bearings
are magnetic (map grid corrected to true north, then the theatre's variation); the aspect follows the
ACC thresholds (HOT to 30 degrees, FLANK to 60, BEAM to 120, then DRAG) with the target's direction.
The zones are drawn on the F10 map.

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
its arena for a minute is removed. The three arenas are drawn on the F10 map.

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
  in-game messages if a spawn fails: a failed spawn is reported, never announced as done. The F10 map
  drawings and the radar switch of the HARM reaction need DCS 2.7 or later (on older builds the drawings
  are skipped and the HARM reaction uses the alarm state alone).
* Map drawings use ids from a block per script (7104000 range, 7105000 intercept, 7106000 air combat),
  away from the small numbers the players' own map marks get.

## Tests

`tests/` runs every script against a fake of the DCS scripting API (`tests/mock_dcs.lua`) in Lua 5.1,
the version DCS embeds, with the real mission table of the `.miz`: zones, date, weather, groups.

```
pip install lupa
python tests/run_tests.py          # all the tests
python tests/run_tests.py -v harm  # the tests with "harm" in the name, printing the scripts' log
```

They cover the logic of the scripts (geometry, menus, messages, commands sent, timers), not what DCS
does with those commands: AI behaviour, radar and weapons still need a flight in the game. See
[`tests/README.md`](tests/README.md).

`python tools/embed_scripts.py` copies the repository's scripts into the `.miz` (what re-selecting each
file in its trigger does in the editor); a test checks that the mission carries the current copies.
