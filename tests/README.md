# Tests

The scripts run here against `mock_dcs.lua`, a fake of the DCS mission-scripting API, inside a real
Lua 5.1 (the version DCS embeds) given by the Python package `lupa`. The mission table comes from the
repository's `.miz`, so the scripts see the real zones, date, weather and groups.

```
pip install lupa
python tests/run_tests.py            # every test
python tests/run_tests.py -v         # ... printing everything the scripts do, with the mission time
python tests/run_tests.py bomb harm  # only the tests whose name contains one of the words
```

Exit code 0 when everything passes, 1 otherwise.

## What is checked, and what is not

The tests check the scripts' own logic: zone geometry (Circle and Quad), what is spawned and where,
the commands sent to the units (radio, TACAN, ICLS, Link 4, routes, options), the F10 menus and who sees
them, the messages, the timers, the scores, the map drawings, and that nothing throws or leaks a global.

They do not check what DCS does with those commands: the fake has no AI, no physics, no radar and no
weapon behaviour. The tests move units and weapons by hand (`MOCK.fall` drops a bomb under gravity,
`MOCK.homeOn` flies a missile at a unit) and fire the events DCS would fire. Whether an AI tanker
really flies the racetrack, or a SAM really goes dark, still needs a flight in the game.

## Files

| File | What it is |
|---|---|
| `mock_dcs.lua` | The fake API. Every call that matters goes to `LOG`; `MOCK` has the helpers (time, menus, units, weapons, map drawings) |
| `harness.py` | `Sim`: one mission run (a fresh Lua state with the fake and the mission), with helpers to load scripts, advance time, click menus and read the log |
| `run_tests.py` | The tests, one function each |

## Writing a test

```python
@test
def my_test():
    sim = Sim()                                          # fake + mission, time 0
    z = sim.zone('TR_SEAD_RADAR')                        # a zone from the .miz: x, z, r, type
    sim.clients('F18', 1, [{'name': 'Aerial-1-1', 'player': 'Eagle1', 'x': z['x'], 'y': 6000, 'z': z['z']}])
    sim.load('TrainingRange.lua')                        # fails the test on a syntax or load error
    sim.advance(2)                                       # run the scripts' timers for 2 s
    since = sim.mark()
    sim.click('Training Range/SEAD Range/Radar Zone/Spawn SA-6')
    check(sim.find('Radar SAM active: SA-6', since), 'SA-6 not spawned')
```

`sim.ev('... return x')` runs Lua and gives back the value; `sim.to_unit(name, since)` lists the messages
sent to one unit. Coordinates follow DCS: x north, z east, y up.

To add a DCS function the fake lacks, add it to `mock_dcs.lua` with the signature of the real one
(the Hoggit wiki documents them), and log the call if a test needs to see it.
