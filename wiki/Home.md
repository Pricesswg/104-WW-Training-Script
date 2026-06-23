![104 WW Training Script](https://raw.githubusercontent.com/Pricesswg/104-WW-Training-Script/main/images/cover.jpg)

# 104 WW Training Script

This is a small pack of training scripts I wrote for our DCS missions. It runs on the
native DCS scripting engine only, no MOOSE / MIST / CTLD, so you just drop the files in
and add a trigger. There are three scripts and they are completely independent: load all
of them or only the one you need.

| Script | What you get |
|---|---|
| `TrainingRange.lua` | An F10 range: bombing targets, a dogfight arena, SEAD threats, carrier ops and air-to-air tankers |
| `TRAINING_Intercept.lua` | A scramble-intercept trainer with its own radio menu |
| `TRAINING_GCA.lua` | A text Ground Controlled Approach that talks you down to a runway |
| `TRAINING_AirCombat.lua` | Air-to-air arenas against RED: dogfight, BVR, and a mixed group that scales to the number of players |
| `JTAC.lua` | A spotter you call from the menu (MQ-9 UAV or ground JTAC), invisible to the enemy, that lases RED targets with a code and frequency you can change |

---

## Install

1. Put the `.lua` files in your mission (or keep them on disk).
2. Build the Mission Editor zones listed below. The names must match exactly, they are case-sensitive.
3. Add one trigger per script: **MISSION START, DO SCRIPT FILE, `<file>.lua`**. Order doesn't matter.

Almost everything is driven by zones now, so there is very little to type by hand. The only
manual values left are the GCA runway (heading and threshold), covered in its section.

---

## How to create a zone in the Mission Editor

1. Open the **Triggers Zones** tool and drop a new zone on the map.
2. Set **Type = Circle**.
3. Name it exactly as written in the tables below.
4. Set the radius (my suggestions are just a starting point, size them to fit your map).
5. Place it where you want that activity to happen.

If a zone is missing, the script tells you on screen instead of spawning, so a wrong name is easy to spot.

---

## TrainingRange.lua

Every spawn point is a zone. Create these (all Circle):

| Zone name | Suggested radius | What it's tied to |
|---|---|---|
| `TR_BOMBING` | ~3000 m | Unarmoured targets (Ural trucks) and the convoy spawn at random points inside this zone, and smoke marks each one. Pick flat ground away from bases. |
| `TR_ARMOR_LIGHT` | ~3000 m | Light armour (BTR-80) spawns at random points inside this zone. |
| `TR_ARMOR_HEAVY` | ~3000 m | Heavy armour (T-90) spawns at random points inside this zone. |
| `TR_DOGFIGHT` | ~15000 m | Dogfight arena. BLUE players inside, above the minimum AGL, become immortal and score hits on each other. Keep it clear of AI routes. |
| `TR_SEAD_RADAR` | ~8000 m | Radar SAM area. Players inside are immortal, and the radar SAM you pick from the menu spawns at a random point inside this zone. |
| `TR_SEAD_IR` | ~5000 m | IR / AAA area. Same idea, the IR/AAA preset spawns at a random point inside. Keep it next to `TR_SEAD_RADAR` but not overlapping. |
| `TR_CARRIER` | ~2000 m | Carrier strike group. The carrier plus its escort screen spawns at the centre at mission start and steams on heading 270. Put it on open water with sea room ahead. |
| `TR_REFUEL_BASKET` | ~10000 m | Basket (probe-and-drogue) tanker. Its racetrack is laid out inside this zone. May be a Circle or a Quad. |
| `TR_REFUEL_BOOM` | ~10000 m | Boom tanker. Same, racetrack fitted inside the zone. Circle or Quad. |

A few notes:

* The **carrier** is on station from mission start, no need to spawn it. It comes up as a full group:
  the carrier as the lead, plus escorts (a cruiser, two destroyers and a plane-guard frigate) in
  formation, steaming and turning together so the screen stays a useful reference when you fly the
  pattern. From the **Carrier Ops** menu you set the group speed and its ROE (Engage, or Defend only
  so it does not open fire on ground units it sails past). Escort types and formation live in
  `TR_Config.carrier.escorts`.
* The **tankers** lay their racetrack inside the assigned zone, so they stay in their area. You can
  change each tanker's speed (Mach 0.3 to 0.6) from the **Refueling** menu to match what you fly.
* The bombing targets (Ural, BTR-80, T-90) and the convoy are all weapon-hold, so they never shoot back.
* The recovery S-3B tanker flies relative to the carrier (offset in `TR_Config`), so it follows the
  boat wherever you place the zone.

---

## TRAINING_Intercept.lua

Create these (all Circle):

| Zone name | What it's tied to |
|---|---|
| `INTERCEPT_PLAYER_ZONE` | The arming area. The **Intercept** F10 menu only appears while you're inside this zone. |
| `INTERCEPT_LIMIT_ZONE` | The play box. A scrambled target spawns near the edge (75% of the radius) on the opposite side from its objective, and is despawned if it leaves this zone after a 30-second grace. Make it big. |
| `INTERCEPT_OBJ_1` | An objective. The target flies toward the centre of one of these, chosen at random. |
| `INTERCEPT_OBJ_2` | An objective. |
| `INTERCEPT_OBJ_3` | An objective. |

Tip: place the three objectives so a target heading for one has to cross `INTERCEPT_LIMIT_ZONE`.
That crossing is the window you have to intercept it before it slips out the far side and despawns.

Nothing to type in. Scramble delay, spawn geometry, grace period and the target-size presets all
live in the script's `CFG` if you want to tweak them.

---

## TRAINING_GCA.lua

Create one zone (Circle), placed over the airfield you want to recover to:

| Zone name | What it's tied to |
|---|---|
| `GCA_ACTIVE_ZONE` | Coverage area. The talkdown runs while you're inside this zone. Put it over the airfield and its approach corridor. |

By default (`CFG.auto = true`) that's all you do. When you enter the zone the script finds the airfield
under it, reads its runways and picks the active one (the runway most into the current wind, longest as
a tiebreaker), then works out the heading and threshold on its own. The runway is chosen at the moment
you start the approach, so it follows the wind.

If you'd rather set the runway by hand, put `CFG.auto = false` and fill in:

| Field | What it is | Default |
|---|---|---|
| `runway_heading` | Landing heading of the runway, degrees true | `250` |
| `threshold_point` | World x/z of the landing threshold | `{ x = 0, z = 0 }` |
| `glideslope_angle` | The glideslope it talks you onto, degrees | `3.0` (used in both modes) |

You'll hear calls like *"Eagle1, slightly left, 5.0 miles, well above glidepath"* once a second, and it
stops when you land or leave the zone.

---

## TRAINING_AirCombat.lua

Three arenas against RED, each with its own zone (all Circle). The F10 menu for an arena appears only
while you're inside its zone.

| Zone name | What it's tied to |
|---|---|
| `TR_DOGFIGHT_RED` | Dogfight arena. Pick a type from the menu and one bandit comes up ahead of you, at the far edge of the zone, same altitude. |
| `TR_BVR_RED` | BVR arena, same idea with a radar-missile loadout. |
| `TR_BVR_MIXED` | Mixed group arena. A whole package comes up, sized to the number of players in the zone. |

How it works:

* **Dogfight and BVR** keep one bandit up at a time. Pick a type (L-39ZA, MiG-21, MiG-23, MiG-29, Su-27,
  F-16, F-18), and it spawns in front of you across the zone. Ask for more and they queue. **Auto** brings
  up a fresh bandit a few seconds after each kill, so you can run reps without touching the menu.
* **Mixed** scales to the room: the threat budget is `players x difficulty` (Easy, Even, Hard), so two
  players on Even get roughly a Su-27 plus a MiG-21, four on Hard get a heavier package, and it tops up if
  more players join. It uses a radar loadout for a proper group BVR fight.
* Leaving a zone despawns its bandits, and you get a "Splash" on every kill.

**Loadouts:** the bandits fly **guns only out of the box** (the dogfight is fully playable like that). To
arm them with missiles, open the `LOADOUTS` table at the top of the script and paste in the weapon CLSIDs
for your DCS version (they change between versions, so I don't hardcode them). If a CLSID is wrong the
bandit just falls back to guns, so nothing breaks.

---

## JTAC.lua

Standalone, you can drop it into any mission. Two zones (Circle), so the ground JTAC and the drone each get
their own spot (create whichever you use):

| Zone name | What it's tied to |
|---|---|
| `JTAC_GROUND_ZONE` | The ground JTAC sits at its centre. Give it line of sight to the targets. |
| `JTAC_UAV_ZONE` | The drone orbits its centre. |

From the F10 menu you call up a spotter, your choice:

* **UAV spotter** (MQ-9 Reaper): orbits the zone from altitude, so it sees everything. The most reliable.
* **Ground JTAC** (a vehicle at the zone centre): more realistic, but it needs clear line of sight or the
  terrain hides the targets.

The spotter is friendly and **invisible to enemy AI**, so it can sit and lase without getting shot. It finds
and lases the nearest visible RED target on its own. The lasing is driven by the script itself
(`Spot.createLaser`), so you can change things live from the menu:

* **Laser code** (default `1688`): pick a preset and it re-lases on the new code straight away. Set your pod
  or bomb to match.
* **Frequency** (default `251.0 AM`): pick a preset to move the spotter's radio, handy to deconflict with
  another asset on the same frequency.

Only one spotter is up at a time, "Report" reads back the current code and frequency, and "Remove spotter"
clears it.

---

## In the air

Everything is driven from the **F10, Other** radio menu (the Intercept menu only shows up inside its
player zone). Spawn what you want, fly the profile, and use the per-module **Reset** entries, or
**Reset all** on the range, to clean up between runs.
