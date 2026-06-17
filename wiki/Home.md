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
| `TR_BOMBING` | ~3000 m | Bombing range. Static targets and the convoy spawn at random points inside this zone, and smoke marks each target. Pick flat ground away from bases. |
| `TR_DOGFIGHT` | ~15000 m | Dogfight arena. BLUE players inside, above the minimum AGL, become immortal and score hits on each other. Keep it clear of AI routes. |
| `TR_SEAD_RADAR` | ~8000 m | Radar SAM area. Players inside are immortal, and the radar SAM you pick from the menu spawns at a random point inside this zone. |
| `TR_SEAD_IR` | ~5000 m | IR / AAA area. Same idea, the IR/AAA preset spawns at a random point inside. Keep it next to `TR_SEAD_RADAR` but not overlapping. |
| `TR_CARRIER` | ~2000 m | Carrier strike group. The carrier plus its escort screen spawns at the centre of this zone, then steams on heading 270. Put it on open water with sea room ahead. |
| `TR_REFUEL_BASKET` | ~10000 m | Basket (probe-and-drogue) tanker. Its orbit is anchored at a random point inside this zone. |
| `TR_REFUEL_BOOM` | ~10000 m | Boom tanker. Same, anchored at a random point inside this zone. |

A few notes:

* The **carrier** spawns as a full group: the carrier as the lead, plus escorts (a cruiser, two
  destroyers and a plane-guard frigate) in formation. They steam and turn together, so the screen
  stays a useful visual reference when you fly the pattern. You can change the escort types and
  their formation in `TR_Config.carrier.escorts`.
* The **carrier and the tankers** don't need any coordinates. They live entirely on their zones plus
  the speed, altitude and TACAN values in `TR_Config`.
* The recovery S-3B tanker still flies relative to the carrier (offset in `TR_Config`), so it follows
  the boat wherever you place the zone.

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

Create one zone (Circle):

| Zone name | What it's tied to |
|---|---|
| `GCA_ACTIVE_ZONE` | Coverage area. The talkdown runs while you're inside this zone, so make it cover the approach corridor to your runway. |

The runway itself is defined in `CFG`, not by a zone:

| Field | What it is | Default |
|---|---|---|
| `runway_heading` | The landing heading of the runway, degrees true | `250`, set it to your runway |
| `threshold_point` | World x/z of the landing threshold, where you aim to touch down | `{ x = 0, z = 0 }`, **fill this in** |
| `glideslope_angle` | The glideslope it talks you onto, degrees | `3.0` |

To get the threshold x/z, place the spot on the map in the Mission Editor and read its coordinates
from the coordinate readout, then enter them as `{ x = <x>, z = <z> }`. In DCS, x and z are the two
horizontal axes, altitude is separate and the script handles it. If you leave it at `{ x = 0, z = 0 }`
the script still loads but warns you on screen.

The zone is just the on/off switch, the talkdown geometry comes from the runway values above. You'll
hear calls like *"Eagle1, slightly left, 5.0 miles, well above glidepath"* once a second, and it
stops when you land or leave the zone.

---

## In the air

Everything is driven from the **F10, Other** radio menu (the Intercept menu only shows up inside its
player zone). Spawn what you want, fly the profile, and use the per-module **Reset** entries, or
**Reset all** on the range, to clean up between runs.
