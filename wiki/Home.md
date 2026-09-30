# 104 WW Training Script

This is a small pack of training scripts I wrote for our DCS missions. It runs on the
native DCS scripting engine only, no MOOSE / MIST / CTLD, so you just drop the files in
and add a trigger. There are six scripts and they are completely independent: load all
of them or only the one you need.

| Script | What you get |
|---|---|
| `TrainingRange.lua` | An F10 range: bombing targets with impact scores, a strafe pit, a dogfight arena, SEAD threats that hide from HARMs, carrier ops with LSO landing grades and air-to-air tankers, all drawn on the F10 map |
| `TRAINING_Intercept.lua` | A scramble-intercept trainer with its own radio menu and a Bogey dope (BRAA) call |
| `TRAINING_GCA.lua` | A text Ground Controlled Approach that talks you down to a runway |
| `TRAINING_AirCombat.lua` | Air-to-air arenas against RED: dogfight, BVR, and a mixed group that scales to the number of players |
| `JTAC.lua` | A spotter you call from the menu (MQ-9 UAV or ground JTAC), invisible to the enemy, that lases RED targets with a code you can change |
| `TRAINING_Comms.lua` | A "Comms card" in the F10 menu: radio, TACAN, ICLS and laser code of everything on your side |

---

## Install

1. Put the `.lua` files in your mission (or keep them on disk).
2. Build the Mission Editor zones listed below. The names must match exactly, they are case-sensitive.
3. Add one trigger per script: **MISSION START, DO SCRIPT FILE, `<file>.lua`**. Order doesn't matter.

Almost everything is driven by zones, so there is very little to type by hand, and every radio, TACAN and
ICLS channel is set for you with sensible defaults.

DCS copies each script into the `.miz` when you save the mission. After updating a `.lua`, pick it again in
its DO SCRIPT FILE trigger and save, or the mission keeps running the old copy.

---

## How to create a zone in the Mission Editor

1. Open the **Triggers Zones** tool and drop a new zone on the map.
2. Set **Type = Circle**, or **Quad** if you want a shape: a Quad is used exactly as you draw it.
3. Name it exactly as written in the tables below.
4. Set the size (my suggestions are just a starting point, size them to fit your map). Careful with units:
   if the editor is set to feet, typing 15000 gives you 15000 ft (4.6 km), not 15 km. A Quad can be
   rotated and stretched as you like, just keep it convex (no corner pushed inward).
5. Place it where you want that activity to happen.

If a zone is missing, the script tells you on screen instead of spawning, so a wrong name is easy to spot.

---

## TrainingRange.lua

Every spawn point is a zone. Create these (Circle or Quad):

| Zone name | Suggested size | What it's tied to |
|---|---|---|
| `TR_BOMBING` | ~3000 m | Unarmoured targets (Ural trucks) and the convoy spawn at random points inside this zone, and smoke marks each one. Pick flat ground away from bases. |
| `TR_ARMOR_LIGHT` | ~3000 m | Light armour (BTR-80) spawns at random points inside this zone. |
| `TR_ARMOR_HEAVY` | ~3000 m | Heavy armour (T-90) spawns at random points inside this zone. |
| `TR_DOGFIGHT` | ~15000 m | Dogfight arena. BLUE players inside, above the minimum AGL, score on each other and their missiles are removed before impact. Keep it clear of AI routes. |
| `TR_SEAD_RADAR` | ~8000 m | Radar SAM area. The radar SAM you pick from the menu spawns at a random point inside this zone. |
| `TR_SEAD_IR` | ~5000 m | IR / AAA area. Same idea, the IR/AAA preset spawns at a random point inside. Keep it next to `TR_SEAD_RADAR` but not overlapping. |
| `TR_CARRIER` | any | Carrier strike group. The carrier plus its escort screen spawns at the centre at mission start. Put it on open water with sea room around it. |
| `TR_REFUEL_BASKET` | Quad ~60 x 15 km | Basket (probe-and-drogue) tanker. Draw the Quad along the track you want: the racetrack follows its long side. A Circle works too (the track heading is then in `TR_Config`). |
| `TR_REFUEL_BOOM` | Quad ~60 x 15 km | Boom tanker. Same. |
| `TR_STRAFE` | ~200 m | Strafe pit. The targets stand in a row at its centre; you run in on the heading in `TR_Config.strafe` (360 by default, from the south), or along the long side if you draw a Quad. Pick flat ground with a clear approach. |

A few notes:

* The **carrier** is on station from mission start, no need to spawn it. It comes up as a full group
  (the carrier plus a cruiser, two destroyers and a plane-guard frigate) and keeps steaming out and back
  through its zone for the whole mission, turning short of any coast. Its TACAN (`74X STN`), ICLS (`11`),
  Link 4 (`336.000`) with ACLS and radio (`127.500 AM`) are on from the start. From the **Carrier Ops** menu:
  **Call recovery** turns the group into the wind with the angled deck lined up and picks the speed for
  about 27 kt of wind over the deck; **Deck status** tells you the CASE (from daylight, ceiling and
  visibility) and the whole comms line; you can also set the speed and the ROE (Engage, or Defend only so it
  does not open fire on ground units it sails past). **Respawn carrier** is refused while someone is parked
  on the deck.
* The **tankers** fly their racetrack inside their zone, as long as the zone allows. Radio and TACAN are set
  on the aircraft: Basket `251.000 AM / 51Y TKR`, Boom `252.000 AM / 52Y TKB`. You can change each tanker's
  speed from the **Refueling** menu, in indicated airspeed (220, 250, 280, 310 KIAS).
* The **S-3B recovery tanker** (`253.000 AM / 53Y RCV`) flies a racetrack 2 NM off the carrier's port side at
  6000 ft and moves with the boat as it steams.
* **LSO grades:** every time you fly the groove to the carrier, the script grades it like a landing signal
  officer. It watches your glideslope, line-up and angle of attack at the start (3/4 mile), in the middle, in
  close and at the ramp, gives you the live calls ("Roger ball", "Power", "Right for lineup", "You're slow",
  and "Wave off" if you are too far off in close), and at the end you get something like *"Eagle1: (OK),
  3-wire. (LO)X LOIM LULIC"*. The shorthand is the LSO's: `(LO)` a little low, `LO` low, `_LO_` well low,
  and the same for `H` (high), `LUL`/`LUR` (lined up left/right), `F`/`SLO` (fast/slow), at `X` (start), `IM`
  (in the middle), `IC` (in close), `AR` (at the ramp). `OK` if you only had small deviations, `(OK)` with a
  normal one, `--` with a big one, plus `-- (BOLTER)`, `WO` (waved off), `OWO` (your own wave-off) and `CUT`
  (landed after a wave-off). **LSO grades (greenie board)** in Carrier Ops shows everyone's grades and
  average points; the live calls can be switched off. With a Supercarrier, DCS's own LSO grade shows up
  too. The angle of attack is checked for the F/A-18C and the F-14.
* **SEAD and dogfight protection:** missiles fired by the range's SAMs, and missiles fired between players
  in the dogfight arena, are removed just before they reach you, and you get a "hit" message instead. This
  works in multiplayer, where the Immortal command does not protect client aircraft. Bullets can't be
  intercepted, so the range AAA keeps its radar on but holds fire unless you switch **AAA live fire** on.
* The bombing targets (Ural, BTR-80, T-90) and the convoy are all weapon-hold, so they never shoot back.
  The convoy keeps driving its loop for the whole mission.
* **Strafe pit:** three T-90s wait in a row at `TR_STRAFE` from mission start. Fly into the box in front of
  them (3 km long, 300 m wide, below 3000 ft, heading for the targets) and you get *"rolling in, cleared
  hot"*; when you leave the box you get your hits over the rounds you fired, like *"23 hits of 61 rounds,
  38%, INEFFECTIVE PASS"*. Don't fire from inside the foul line (2000 ft): a hit or a burst from there
  makes the pass invalid. A target that gets destroyed comes back after 10 seconds. **Scores** shows the
  pit next to the bombs.
* **Bombing scores:** drop a bomb, fire rockets or an air-to-ground missile near the range and the script
  follows it to the ground. You get something like *"Mk-82: 18 m at 5 o'clock from T-90, GOOD"*: the
  distance from the nearest target, the clock position seen along your attack heading (12 o'clock is
  long, 6 o'clock is short) and a grade (SHACK, EXCELLENT, GOOD, INEFFECTIVE, POOR). A ripple or a rocket
  salvo comes back as one line with the best hit and the average. **Scores** in the Bombing Range menu
  shows everyone's average and best, **Clear scores** starts over.
* **HARM reaction:** fire an anti-radiation missile at the range SAM and after a few seconds the site
  switches its radar off, like a real crew would, and comes back on a while after the missile is gone. You
  see it drop off your RWR and you get a message. Switch it off from the SEAD menu (**HARM reaction
  on/off**) if you just want to practise the shot.
* **F10 map:** the range zones, the strafe pit's box and foul line, each tanker's track with its radio,
  TACAN, flight level and speed, the S-3B track and the carrier with its comms are drawn on the map, and
  they follow the assets. **Map drawings on/off** in the range menu hides them.

---

## TRAINING_Intercept.lua

Create these (Circle or Quad):

| Zone name | What it's tied to |
|---|---|
| `INTERCEPT_PLAYER_ZONE` | The arming area. The **Intercept** F10 menu only appears while you're inside this zone (one menu per flight). |
| `INTERCEPT_LIMIT_ZONE` | The play box. A scrambled target spawns inside it, on the opposite side from its objective (75% of the way to the edge). If it leaves the box after a 30-second grace, the intercept has failed. Make it big. |
| `INTERCEPT_OBJ_1` | An objective. The target flies toward the centre of one of these, chosen at random; if it gets there, the intercept has failed. |
| `INTERCEPT_OBJ_2` | An objective. |
| `INTERCEPT_OBJ_3` | An objective. |

Tip: place the objectives so a target heading for one has to cross `INTERCEPT_LIMIT_ZONE`.
That crossing is the window you have to intercept it.

Nothing to type in. Scramble delay, spawn geometry, grace period and the target-size presets all
live in the script's `CFG` if you want to tweak them.

Once a target is up, every flight gets a **Bogey dope (intercept)** entry in the F10 menu, wherever it is.
Call it and each pilot of the flight gets the target in BRAA from their own aircraft, closest first:
*"Springfield 1-1, group BRAA 355/18, 20 thousand, HOT, HOSTILE."* Bearing magnetic, range in miles,
altitude, and the aspect (HOT, FLANK, BEAM or DRAG with the direction it's heading). The zones are drawn on
the F10 map so you can see the box and the objectives.

---

## TRAINING_GCA.lua

Create one zone (Circle or Quad), placed over the airfield you want to recover to:

| Zone name | What it's tied to |
|---|---|
| `GCA_ACTIVE_ZONE` | Picks the airfield: the GCA serves the airfield nearest to its centre. |

That's all you do. The script reads the airfield's runways and talks you down when you're airborne on final:
within 10 NM of the threshold, inside 30 degrees of the extended centreline, below 6000 ft and heading for the
runway. The active runway is the one most into the wind; with calm wind, it's the one you're lined up for. If
you come in on the other end while the wind favours the opposite one, it tells you which runway is in use.

If you'd rather set the runway by hand, put `CFG.auto = false` and fill in:

| Field | What it is | Default |
|---|---|---|
| `runway_heading` | Landing heading of the runway, degrees magnetic | `290` |
| `threshold_point` | World x/z of the landing threshold | `{ x = 0, z = 0 }` |
| `runway_length` | Runway length in metres | `2500` |
| `glideslope_angle` | The glideslope it talks you onto, degrees | `3.0` (used in both modes) |

You'll get *"Eagle1, radar contact, 6.2 miles from touchdown. This will be a PAR approach to runway 29, wind
calm. Fly heading 285, perform landing check."*, then a call every second such as *"Eagle1, slightly left of
course, on glidepath, 4.8 miles from touchdown"* (each call replaces the previous one on screen), *"check
wheels down"* at 3 miles, and *"over landing threshold"* at the end. Headings are magnetic.

---

## TRAINING_AirCombat.lua

Three arenas against RED, each with its own zone (Circle or Quad). The F10 menu for an arena appears only
while you're inside its zone, one menu per flight.

| Zone name | What it's tied to |
|---|---|
| `TR_DOGFIGHT_RED` | Dogfight arena. Pick a type from the menu and one bandit comes up ahead of you, at the far edge of the zone, same altitude. |
| `TR_BVR_RED` | BVR arena, same idea with a radar-missile loadout. |
| `TR_BVR_MIXED` | Mixed group arena. A whole package comes up, sized to the number of players in the zone. |

How it works:

* **Dogfight and BVR** keep one bandit up at a time. Pick a type (L-39ZA, MiG-21, MiG-23, MiG-29, Su-27,
  F-16, F-18), and it spawns in front of you across the zone and flies straight at you. Ask for more and
  they queue. **Auto** brings up a fresh bandit a few seconds after each kill, so you can run reps without
  touching the menu.
* **Mixed** scales to the room: the threat budget is `players x difficulty` (Easy, Even, Hard), so two
  players on Even get roughly a Su-27 plus a MiG-21. Kills are not replaced (the wave ends when you've shot
  it down), but if more players join, it tops up for them.
* Leaving a zone despawns its bandits, a bandit that wanders out of its arena for a minute is removed, and
  you get a "Splash" on every kill.
* The three arenas are drawn on the F10 map with their names.

**Loadouts:** the bandits fly **guns only out of the box** (the dogfight is fully playable like that). To
arm them with missiles, open the `LOADOUTS` table at the top of the script and paste in the weapon CLSIDs
for your DCS version (they change between versions, so I don't hardcode them).

---

## JTAC.lua

Standalone, you can drop it into any mission. Two zones (Circle or Quad), so the ground JTAC and the drone
each get their own spot (create whichever you use):

| Zone name | What it's tied to |
|---|---|
| `JTAC_GROUND_ZONE` | The ground JTAC sits at its centre. Give it line of sight to the targets. |
| `JTAC_UAV_ZONE` | The drone orbits its centre. |

From the F10 menu you call up a spotter, your choice:

* **UAV spotter** (MQ-9 Reaper): orbits the zone from altitude, so it sees everything. The most reliable.
* **Ground JTAC** (a vehicle at the zone centre): more realistic, but it needs clear line of sight or the
  terrain hides the targets.

The spotter is friendly and **invisible to enemy AI**, so it can sit and lase without getting shot. It finds
the nearest visible RED target and **stays on it** until it's destroyed, hidden or out of range, then moves to
the next one, so a laser-guided bomb already in the air doesn't lose its spot. You can change things live
from the menu:

* **Laser code** (default `1688`): pick a preset and it re-lases the same target on the new code. Set your
  pod or bomb to match.
* **Frequency** (default `262.0 AM`): the spotter's radio, shown on the comms card. The spotter doesn't talk:
  its calls are the text messages.

Only one spotter is up at a time, "Report" reads back the current code, frequency and target, and "Remove
spotter" clears it. If the spotter gets killed, the laser goes off and you're told.

---

## TRAINING_Comms.lua

No zones to create. It adds one F10 entry, **Comms card (radio / TACAN / ICLS)**, that shows everything your
side has set: the carrier, tankers, S-3B and JTAC spawned by the other scripts, plus the tankers, AWACS,
ships and player flights placed in the Mission Editor with their radio and any TACAN / ICLS / Link 4 set in
their route.

---

## In the air

Everything is driven from the **F10, Other** radio menu (the Intercept and air combat menus only show up
inside their zones). Spawn what you want, fly the profile, and use the per-module **Reset** entries, or
**Reset all** on the range, to clean up between runs.

---

## For mission makers: tests

The repository has a test bench in `tests/`: it runs every script against a fake of the DCS scripting API,
with the real mission from the `.miz`, and checks what the scripts do (spawns, menus, messages, radio and
TACAN commands, scores, map drawings). You need Python and one package:

```
pip install lupa
python tests/run_tests.py
```

It can't tell you what the AI does with a command, so a flight in the game is still the final check. After
editing a script, `python tools/embed_scripts.py` puts the new copy into the `.miz` for you.
