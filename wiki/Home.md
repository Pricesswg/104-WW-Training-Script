![104 WW Training Script](https://raw.githubusercontent.com/Pricesswg/104-WW-Training-Script/main/images/cover.jpg)

# 104 WW Training Script

This is a small pack of training scripts I wrote for our DCS missions. It runs on the
native DCS scripting engine only — no MOOSE, MIST or CTLD — so you just drop the files
in and add a trigger. There are three scripts and they are completely independent: load
all of them or only the one you need.

| Script | What you get |
|---|---|
| `TrainingRange.lua` | An F10 range: bombing targets, a dogfight arena, SEAD threats, carrier ops and air-to-air tankers |
| `TRAINING_Intercept.lua` | A scramble-intercept trainer with its own radio menu |
| `TRAINING_GCA.lua` | A text Ground Controlled Approach that talks you down to a runway |

---

## Install

1. Put the `.lua` files in your mission (or keep them on disk).
2. Build the Mission Editor zones listed below — **the names must match exactly** (they are case-sensitive).
3. Fill in the handful of coordinates / runway values marked **FILL IN** at the top of each script.
4. Add one trigger per script: **MISSION START → DO SCRIPT FILE → `<file>.lua`**. Order doesn't matter.

Each script checks its zones when it loads and shows a message on screen if any are missing, so you'll know immediately if a name is wrong.

---

## How to create a zone in the Mission Editor

1. Open the **Triggers Zones** tool and drop a new zone on the map.
2. Set **Type = Circle**.
3. **Name it exactly** as written in the tables below.
4. Set the **radius** (the values I suggest are just a starting point — make them fit your map).
5. Place it where you want that activity to happen.

A few things are **not** zones but absolute coordinates in the script config (the carrier, the
tankers, the SAM spawn points, the GCA runway). For those, see *Reading coordinates* at the bottom.

---

## TrainingRange.lua

### Zones (Circle)

| Zone name | Suggested radius | What it's tied to |
|---|---|---|
| `TR_BOMBING` | ~3000 m | Bombing range. Static targets and the convoy spawn at random points **inside this zone**; smoke marks each target. Pick flat ground away from bases. |
| `TR_DOGFIGHT` | ~15000 m | Dogfight arena. BLUE players inside (and above the minimum AGL) become immortal and score hits on each other. Keep it clear of AI routes. |
| `TR_SEAD_RADAR` | ~8000 m | Radar-SAM area. Players inside are immortal; the radar SAM you pick from the menu spawns at the coordinate `sead.radarSpawnPoint`. Put that point near the centre of this zone. |
| `TR_SEAD_IR` | ~5000 m | IR / AAA area. Same idea, the IR/AAA preset spawns at `sead.irSpawnPoint`. Keep it next to `TR_SEAD_RADAR` but **not overlapping**. |

### Coordinates in `TR_Config` (not zones — world x/z)

| Field | Tied to | Note |
|---|---|---|
| `sead.radarSpawnPoint` | `TR_SEAD_RADAR` | Where the radar SAM appears — put it inside that zone |
| `sead.irSpawnPoint` | `TR_SEAD_IR` | Where the IR/AAA appears — put it inside that zone |
| `carrier.spawnPoint` | — | Carrier start position, open water |
| `refueling.basket.spawnPoint` | — | Anchor of the basket (probe-and-drogue) tanker orbit |
| `refueling.boom.spawnPoint` | — | Anchor of the boom tanker orbit |

Carrier and tankers don't use ME zones at all — they live entirely on these coordinates plus the
speed/altitude/TACAN values in `TR_Config`.

---

## TRAINING_Intercept.lua

### Zones (Circle)

| Zone name | What it's tied to |
|---|---|
| `INTERCEPT_PLAYER_ZONE` | The arming area. The **Intercept** F10 menu only appears while you're inside this zone. |
| `INTERCEPT_LIMIT_ZONE` | The play box. A scrambled target spawns near the edge (75% of the radius) on the **opposite side from its objective**, and is despawned if it leaves this zone (after a 30-second grace). Make it big. |
| `INTERCEPT_OBJ_1` | An objective. The target flies toward the **centre** of one of these, chosen at random. |
| `INTERCEPT_OBJ_2` | An objective. |
| `INTERCEPT_OBJ_3` | An objective. |

Tip: place the three objectives so a target heading for one has to cross `INTERCEPT_LIMIT_ZONE` —
that's the window you have to intercept it before it slips out the far side and despawns.

No coordinates to fill in — everything keys off these zones. Scramble delay, spawn geometry, grace
period and the target-size presets are all in the script's `CFG` if you want to tweak them.

---

## TRAINING_GCA.lua

### Zone (Circle)

| Zone name | What it's tied to |
|---|---|
| `GCA_ACTIVE_ZONE` | Coverage area. The talkdown runs while you're inside this zone — make it cover the approach corridor to your runway. |

### Runway in `CFG` (not a zone)

| Field | What it is | Default |
|---|---|---|
| `runway_heading` | The landing heading of the runway, degrees true | `250` — set it to your runway |
| `threshold_point` | World x/z of the landing threshold (where you aim to touch down) | `{ x = 0, z = 0 }` — **FILL IN** |
| `glideslope_angle` | The glideslope it talks you onto, degrees | `3.0` |

The GCA zone is just the on/off switch; the actual talkdown geometry comes from the runway values
above. You'll hear calls like *"Eagle1, slightly left, 5.0 miles, well above glidepath"* once a
second, and it stops when you land or leave the zone.

---

## Reading coordinates for the FILL-IN points

The carrier/tanker/SAM spawn points and the GCA threshold are world **x/z** values, not zones.
To get them: place the spot on the map in the Mission Editor and read its coordinates from the
coordinate readout, then enter them in the script as `{ x = <x>, z = <z> }`. (In DCS, x and z are
the two horizontal axes; altitude is separate and handled by the script.)

If you leave one of these at `{ x = 0, z = 0 }`, the script still loads but warns you on screen and
spawns at the map origin — so it's obvious when something hasn't been set yet.

---

## In the air

Everything is driven from the **F10 → Other** radio menu (the Intercept menu only shows up inside
its player zone). Spawn what you want, fly the profile, and use the per-module **Reset** entries —
or **Reset all** on the range — to clean up between runs.
