"""Test harness: runs the training scripts against mock_dcs.lua, a fake of the
DCS scripting API, inside a real Lua 5.1 (the version DCS embeds) provided by
the `lupa` package. The mission table comes from the repository's .miz, so
the scripts see the real zones, date, weather and groups.

Nothing here needs DCS. It checks the scripts' own logic (geometry, menus,
messages, commands, timers); what the simulator does with those commands
(AI behaviour, radar, weapons) still has to be tried in the game.
"""
import os
import re
import sys
import zipfile

try:
    import lupa.lua51 as _lua  # lupa 2.x ships Lua 5.1, as in DCS
except ImportError:  # pragma: no cover
    try:
        import lupa as _lua  # older lupa: LuaJIT, 5.1 compatible
    except ImportError:
        sys.exit('The tests need the "lupa" package: pip install lupa')

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
MIZ = os.path.join(REPO, 'Op. White Wyverns Training.miz')
SCRIPTS = ['TrainingRange.lua', 'TRAINING_Intercept.lua', 'TRAINING_GCA.lua',
           'TRAINING_AirCombat.lua', 'JTAC.lua', 'TRAINING_Comms.lua']

ECHO = False  # set by run_tests.py -v: print the script log as it happens
SEED = None   # set by run_tests.py --seed=N: a different random sequence for the scripts

with zipfile.ZipFile(MIZ) as _z:
    MISSION_SRC = _z.read('mission').decode('utf-8')
with open(os.path.join(HERE, 'mock_dcs.lua'), encoding='utf-8') as _f:
    MOCK_SRC = _f.read()


class Sim:
    """One mission run: a fresh Lua state with the mock and the mission."""

    def __init__(self, wind_from=None, wind_kt=0.0):
        self.lua = _lua.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK_SRC)
        self.lua.execute(MISSION_SRC)
        self.lua.execute('env.mission = mission; mission = nil')
        self.g = self.lua.globals()
        self.g.MOCK.echo = ECHO
        if SEED is not None:
            self.run(f'math.randomseed({int(SEED)})')
        if wind_from is not None:
            self.set_wind(wind_from, wind_kt)
        self._zones = {}
        for z in self.g.env.mission.triggers.zones.values():
            self._zones[z.name] = {'x': z.x, 'z': z.y, 'r': z.radius, 'type': z.type}

    # -- scripts and time ---------------------------------------------------
    def load(self, *names):
        run = self.lua.eval('''function(src, name)
            local f, err = loadstring(src, "@" .. name)
            if not f then return "syntax error: " .. tostring(err) end
            local ok, e = pcall(f)
            if not ok then return "runtime error: " .. tostring(e) end
            return "ok" end''')
        for name in names:
            with open(os.path.join(REPO, name), encoding='utf-8') as f:
                res = run(f.read(), name)
            if res != 'ok':
                raise AssertionError(f'{name}: {res}')
        return self

    def advance(self, seconds):
        self.g.MOCK.advance(seconds)

    def run(self, code):
        """Execute Lua statements."""
        self.lua.execute(code)

    def ev(self, code):
        """Run a Lua block that ends with `return ...` and give the value."""
        return self.lua.eval('(function() ' + code + ' end)()')

    # -- world ----------------------------------------------------------------
    def zone(self, name):
        return self._zones[name]

    def set_wind(self, from_deg, kt):
        """Wind blowing FROM a direction (degrees, map grid) at kt knots."""
        import math
        to = math.radians(from_deg + 180)
        ms = kt * 0.514444
        self.run(f'MOCK.wind = {{ x = {ms * math.cos(to)}, y = 0, z = {ms * math.sin(to)} }}')

    def clients(self, gname, gid, specs):
        """A client group with players: specs are dicts with name, x, y (alt), z,
        optional hdg (radians), air, player, callsign, v = {x, y, z}."""
        t = self.lua.table_from([self.lua.table_from(s, recursive=True) for s in specs])
        self.g.MOCK.addClientGroup(gname, gid, t)

    def unit_id(self, name):
        return self.ev(f'return MOCK.units["{name}"].id')

    # -- menus ----------------------------------------------------------------
    def click(self, path, gid=None, side=2):
        return bool(self.g.MOCK.click(path, gid, side))

    def top_menus(self, gid=None, side=2):
        return list(self.g.MOCK.topMenus(gid, side).values())

    def commands(self, side=2):
        """Every command item visible to a coalition, and every group item."""
        return [m for m in self.g.MOCK.menus.values() if m.kind == 'cmd' and (m.side is None or m.side == side)]

    # -- log ------------------------------------------------------------------
    def log(self, since=0):
        entries = list(self.g.LOG.values())
        return entries[since:]

    def mark(self):
        """Position in the log, to look only at what comes after."""
        return len(self.g.LOG)

    def find(self, pattern, since=0):
        rx = re.compile(pattern)
        return [s for s in self.log(since) if rx.search(s)]

    def to_unit(self, unit_name, since=0):
        """Messages sent to one unit (outTextForUnit)."""
        tag = f'[outTextForUnit {self.unit_id(unit_name)}'
        return [s for s in self.log(since) if s.startswith(tag)]


class Failed(AssertionError):
    pass


def check(cond, msg):
    if not cond:
        raise Failed(msg)
