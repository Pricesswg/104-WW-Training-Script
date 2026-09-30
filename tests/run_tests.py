"""Scenario tests for the six training scripts, run against mock_dcs.lua with
the mission of the repository's .miz.

    pip install lupa
    python tests/run_tests.py            # every test
    python tests/run_tests.py -v         # ... printing the scripts' log
    python tests/run_tests.py harm bomb  # only the tests whose name contains a word
    python tests/run_tests.py --seed=7   # the scripts draw a different random sequence

Exit code 0 when everything passes, 1 otherwise.
"""
import math
import os
import re
import sys
import traceback
import zipfile

import harness
from harness import SCRIPTS, Sim, check

TESTS = []


def test(f):
    TESTS.append(f)
    return f


NM = 1852.0
KT = 0.514444


def pip(x, z, poly):
    """Point in polygon, poly = [(x, z), ...]."""
    inside, j = False, len(poly) - 1
    for i in range(len(poly)):
        (ax, az), (bx, bz) = poly[i], poly[j]
        if (az > z) != (bz > z) and x < (bx - ax) * (z - az) / (bz - az) + ax:
            inside = not inside
        j = i
    return inside


def quad(sim, name):
    """The outline of a Quad zone. The editor stores the corners in "Z" order
    (1-2 one side, 3-4 the opposite side in the same direction), so the
    outline is 1-2-4-3; all_quads_are_stored_in_z_order checks it."""
    verts = sim.ev(f'''for _, z in ipairs(env.mission.triggers.zones) do
        if z.name == "{name}" then return z.verticies end end''')
    v = [(p.x, p.y) for p in verts.values()]
    return [v[0], v[1], v[3], v[2]]


def num(pattern, text):
    m = re.search(pattern, text)
    return float(m.group(1)) if m else None


# ===========================================================================
# Loading
# ===========================================================================
@test
def all_scripts_load_with_every_zone():
    sim = Sim().load(*SCRIPTS)
    sim.advance(3)
    check(not sim.find('MISSING|not found|Required DCS API'), f'zone or API complaint: {sim.find("MISSING|not found")}')
    check(not sim.find('error'), f'errors: {sim.find("error")}')
    blue, red = sim.top_menus(side=2), sim.top_menus(side=1)
    for m in ('Training Range', 'JTAC / Spotter', 'Comms card (radio / TACAN / ICLS)'):
        check(m in blue, f'BLUE menu lacks {m}: {blue}')
    check('Training Range' not in red, f'RED sees the range menu: {red}')
    check('Comms card (radio / TACAN / ICLS)' in red, 'RED has no comms card')


@test
def mission_file_carries_the_current_scripts():
    with zipfile.ZipFile(harness.MIZ) as z:
        names = set(z.namelist())
        res = z.read('l10n/DEFAULT/mapResource').decode('utf-8')
        for s in SCRIPTS:
            member = 'l10n/DEFAULT/' + s
            check(member in names, f'{s} is not in the .miz')
            with open(os.path.join(harness.REPO, s), 'rb') as f:
                check(z.read(member) == f.read(), f'the .miz carries an old copy of {s}: run python tools/embed_scripts.py')
    sim = Sim()
    sim.run(res)  # mapResource = { key = file name }
    keys = {v: k for k, v in sim.g.mapResource.items()}
    acts = '\n'.join(str(a) for a in sim.g.env.mission.trig.actions.values())
    for s in SCRIPTS:
        check(s in keys and f'a_do_script_file(getValueResourceByKey("{keys[s]}"))' in acts,
              f'no trigger loads {s}')


def _crosses(p1, p2, p3, p4):
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    return cross(p3, p4, p1) * cross(p3, p4, p2) < 0 and cross(p1, p2, p3) * cross(p1, p2, p4) < 0


@test
def all_quads_are_stored_in_z_order():
    sim = Sim()
    for z in sim.g.env.mission.triggers.zones.values():
        if z.type == 2:
            v = [(p.x, p.y) for p in z.verticies.values()]
            check(_crosses(v[0], v[1], v[2], v[3]) or _crosses(v[1], v[2], v[3], v[0]),
                  f'{z.name}: corners 1-2-3-4 make an outline, the "Z" order assumption is wrong')


@test
def quad_zones_count_their_whole_area():
    # The side triangles of a Quad are what a bow-tie test leaves out.
    sim = Sim()
    q = quad(sim, 'TR_DOGFIGHT_RED')
    cx, cz = sum(p[0] for p in q) / 4, sum(p[1] for p in q) / 4
    # a point 80% of the way from the centre to the middle of each side
    for i in range(4):
        (ax, az), (bx, bz) = q[i], q[(i + 1) % 4]
        mx, mz = (ax + bx) / 2, (az + bz) / 2
        px, pz = cx + 0.8 * (mx - cx), cz + 0.8 * (mz - cz)
        s = Sim()
        s.clients('F18', 1, [{'name': 'Aerial-1-1', 'x': px, 'y': 5000, 'z': pz}])
        s.load('TRAINING_AirCombat.lua')
        s.advance(3)
        check('Dogfight vs RED' in s.top_menus(gid=1), f'player inside TR_DOGFIGHT_RED near side {i + 1} got no arena menu')
    # The tanker track runs along the long side of its Quad.
    s = Sim().load('TrainingRange.lua')
    s.advance(2)
    s.click('Training Range/Refueling/Spawn Basket tanker')
    s.advance(2)
    pts = s.ev('return MOCK.groups["TR_TANKER_BASKET"].data.route.points')
    q = quad(s, 'TR_REFUEL_BASKET')
    sides = sorted(((math.hypot(q[(i + 1) % 4][0] - q[i][0], q[(i + 1) % 4][1] - q[i][1]),
                     math.degrees(math.atan2(q[(i + 1) % 4][1] - q[i][1], q[(i + 1) % 4][0] - q[i][0])) % 180) for i in range(4)),
                   reverse=True)
    trk = math.degrees(math.atan2(pts[2].y - pts[1].y, pts[2].x - pts[1].x)) % 180
    check(abs((trk - sides[0][1] + 90) % 180 - 90) < 1, f'basket track {trk:.1f} is not along the long side {sides[0][1]:.1f}')


# ===========================================================================
# TrainingRange: carrier, tankers, bombing targets, missile protection
# ===========================================================================
@test
def carrier_group_comms_and_recovery():
    sim = Sim().load('TrainingRange.lua')
    sim.advance(3)
    check(sim.ev('return #MOCK.groups["TR_CSG"].data.units') == 5, 'strike group is not carrier + 4 escorts')
    cmds = sim.ev('local o = {} for _, c in ipairs(MOCK.groups["TR_CSG"].ctrl.cmds) do o[#o+1] = c.id end return table.concat(o, ",")')
    for c in ('ActivateBeacon', 'ActivateICLS', 'ActivateLink4', 'ActivateACLS'):
        check(c in cmds, f'{c} not sent to the carrier ({cmds})')
    tac = sim.ev('for _, c in ipairs(MOCK.groups["TR_CSG"].ctrl.cmds) do if c.id == "ActivateBeacon" then return c.params end end')
    check(tac.channel == 74 and tac.modeChannel == 'X' and tac.system == 3 and tac.frequency == (1151 + 74 - 64) * 1e6,
          'carrier TACAN is not 74X on the ship system')
    loop = sim.ev('local a = MOCK.groups["TR_CSG"].data.route.points[3].task.params.tasks[1].params.action.params '
                  'return a.fromWaypointIndex .. ">" .. a.goToWaypointIndex')
    check(loop == '3>2', f'route does not loop ({loop})')

    sim.set_wind(270, 12)
    sim.click('Training Range/Carrier Ops/Call recovery (into wind)')
    sim.advance(1)
    brg, spd = sim.ev('local g = MOCK.groups["TR_CSG"]; local p = g.ctrl.tasks[#g.ctrl.tasks].params.route.points '
                      'return MOCK.bearing(p[1].x, p[1].y, p[2].x, p[2].y), p[2].speed')
    check(abs(brg - 279) < 0.5, f'recovery BRC {brg:.1f}, expected 279 (wind 270 + 9)')
    check(abs(spd - 15 * KT) < 0.05, f'recovery speed {spd / KT:.1f} kt, expected 15 (27 - 12)')

    sim.run('MOCK.surface = function(x, z) return (x > -56000) and 1 or 3 end')  # land right ahead
    since = sim.mark()
    sim.click('Training Range/Carrier Ops/Call recovery (into wind)')
    check(sim.find('No sea room', since), 'no sea room was not reported')
    sim.run('MOCK.surface = nil')

    sim.run('local c = MOCK.units["TR_CARRIER"]; MOCK.addClientGroup("F18", 1, '
            '{ { name = "Deck-1", x = c.p.x + 50, y = 20, z = c.p.z, air = false } })')
    gid = sim.ev('return MOCK.groups["TR_CSG"].id')
    since = sim.mark()
    sim.click('Training Range/Carrier Ops/Respawn carrier')
    check(sim.find('Respawn refused: 1 aircraft on deck', since), 'respawn with a player on deck was not refused')
    sim.click('Training Range/Reset all (every module)')
    check(sim.ev('return MOCK.groups["TR_CSG"].id') == gid, '"Reset all" respawned the carrier')


@test
def tankers_in_their_quads_with_radio_and_tacan():
    sim = Sim().load('TrainingRange.lua')
    sim.advance(2)
    for which, name, zone, mhz, ch in (('Basket', 'TR_TANKER_BASKET', 'TR_REFUEL_BASKET', 251.0, 51),
                                       ('Boom', 'TR_TANKER_BOOM', 'TR_REFUEL_BOOM', 252.0, 52)):
        sim.click(f'Training Range/Refueling/Spawn {which} tanker')
        sim.advance(2)
        pts = sim.ev(f'return MOCK.groups["{name}"].data.route.points')
        poly = quad(sim, zone)
        for p in (pts[1], pts[2]):
            check(pip(p.x, p.y, poly), f'{which} racetrack point outside {zone}')
        check(sim.ev(f'return MOCK.groups["{name}"].data.frequency') == mhz, f'{which} group radio is not {mhz}')
        cmds = sim.ev(f'return MOCK.groups["{name}"].ctrl.cmds')
        ids = [c.id for c in cmds.values()]
        check('SetFrequency' in ids and 'ActivateBeacon' in ids, f'{which}: radio/TACAN commands missing ({ids})')
        b = [c.params for c in cmds.values() if c.id == 'ActivateBeacon'][0]
        check(b.channel == ch and b.modeChannel == 'Y' and b.system == 5 and b.frequency == (1088 + ch - 1) * 1e6,
              f'{which} TACAN is not {ch}Y airborne')

    since = sim.mark()
    sim.click('Training Range/Refueling/Basket speed/280 KIAS')
    sim.advance(1)
    spd = sim.ev('local g = MOCK.groups["TR_TANKER_BASKET"]; return g.ctrl.tasks[#g.ctrl.tasks].params.route.points[1].speed')
    sigma = (1 - 2.25577e-5 * 6000) ** 4.25588
    check(abs(spd - 280 * KT / math.sqrt(sigma)) < 0.5, f'280 KIAS at 6000 m should be {280 * KT / math.sqrt(sigma):.1f} m/s TAS, got {spd:.1f}')
    check(sim.find('speed set to 280 KIAS', since), 'speed change not announced')

    sim.click('Training Range/Carrier Ops/Spawn S-3B Recovery Tanker')
    sim.advance(2)
    sim.run('local c = MOCK.units["TR_CARRIER"]; c.p.z = c.p.z - 7000')
    sim.advance(61)
    d = sim.ev('local g = MOCK.groups["TR_S3_TANKER"]; local t = g.ctrl.tasks[#g.ctrl.tasks]; if not t then return -1 end '
               'local p = t.params.route.points; local c = MOCK.units["TR_CARRIER"] '
               'return MOCK.dist(c.p.x, c.p.z, (p[1].x + p[2].x) / 2, (p[1].y + p[2].y) / 2)')
    check(abs(d - 3700) < 50, f'S-3B racetrack not re-centred 2 NM off the carrier after it moved (d = {d:.0f} m)')


@test
def bombing_targets_convoy_and_kill_count():
    sim = Sim().load('TrainingRange.lua')
    sim.advance(2)
    sim.click('Training Range/Bombing Range/Static (Ural)/Spawn 10')
    check(sim.find('Spawned 10 unarmoured target'), 'the 1 km quad does not hold 10 targets')
    poly = quad(sim, 'TR_BOMBING')
    for i in range(1, 11):
        p = sim.ev(f'return MOCK.units["TR_STATIC_{i}_1"].p')
        check(pip(p.x, p.z, poly), f'target {i} outside TR_BOMBING')
    sim.click('Training Range/Bombing Range/Spawn convoy')
    loop = sim.ev('local a = MOCK.groups["TR_CONVOY"].data.route.points[4].task.params.tasks[1].params.action.params '
                  'return a.fromWaypointIndex .. ">" .. a.goToWaypointIndex')
    check(loop == '4>1', f'convoy does not loop ({loop})')
    sim.run('local u = MOCK.units["TR_STATIC_1_1"]; u.alive = false '
            'MOCK.fire({ id = world.event.S_EVENT_UNIT_LOST, initiator = u }) '
            'MOCK.fire({ id = world.event.S_EVENT_DEAD, initiator = u })')
    check(len(sim.find('Target destroyed')) == 1, 'a kill with UNIT_LOST and DEAD was counted twice')
    sim.click('Training Range/Bombing Range/Reset Bombing Range')
    check(sim.ev('return Group.getByName("TR_CONVOY") == nil and Group.getByName("TR_STATIC_2") == nil'), 'reset left targets')
    check(len(sim.find('Target destroyed')) == 1, 'the reset was counted as kills')


SAM_MISSILE = '{ category = 1, missileCategory = 2, displayName = "3M9 (SA-6)", typeName = "SA3M9M", warhead = { explosiveMass = 59 } }'
AIM9 = '{ category = 1, missileCategory = 1, displayName = "AIM-9M", typeName = "AIM_9", warhead = { explosiveMass = 9.4 } }'


def shoot(sim, shooter, desc, target=None, v=None):
    """Fire S_EVENT_SHOT for a weapon leaving `shooter`; the weapon is W in Lua."""
    tgt = f'MOCK.units["{target}"]' if target else 'nil'
    vel = '{ x = %f, y = %f, z = %f }' % tuple(v) if v else 'nil'
    sim.run(f'''local s = MOCK.units["{shooter}"]; local p = s:getPoint()
        W = MOCK.newWeapon({desc}, {{ x = p.x, y = p.y + 5, z = p.z }}, {tgt}, {vel})
        MOCK.fire({{ id = world.event.S_EVENT_SHOT, initiator = s, weapon = W }})''')


@test
def missile_protection_sead_and_dogfight():
    sim = Sim()
    z = sim.zone('TR_SEAD_RADAR')
    sim.clients('F18', 1, [{'name': 'Aerial-1-1', 'player': 'Eagle1', 'x': z['x'] + 15000, 'y': 6000, 'z': z['z']},
                           {'name': 'Aerial-1-2', 'player': 'Eagle2', 'x': z['x'] + 30000, 'y': 6000, 'z': z['z']}])
    sim.load('TrainingRange.lua')
    sim.advance(2)
    sim.click('Training Range/SEAD Range/Radar Zone/Spawn SA-6')
    sim.click('Training Range/SEAD Range/IR/AAA Zone/Spawn Integrated Defense')
    sim.advance(2)
    check(sim.ev('return MOCK.groups["TR_INTEGRATED_GUNS"].ctrl.options[0]') == 4, 'AAA does not hold fire by default')
    sim.click('Training Range/SEAD Range/IR/AAA Zone/AAA live fire on/off')
    sim.advance(2)
    check(sim.ev('return MOCK.groups["TR_INTEGRATED_GUNS"].ctrl.options[0]') == 2, 'AAA live fire did not open fire')

    shoot(sim, 'TR_SAM_SA6_2', SAM_MISSILE, 'Aerial-1-1')
    sim.run('MOCK.homeOn(W, MOCK.units["Aerial-1-1"], 700)')
    hit = sim.find(r'\[SEAD\] HIT: 3M9 \(SA-6\).*removed at (\d+) m')
    check(hit, 'SA-6 missile not removed before impact')
    d = int(hit[0].split('removed at ')[1].split(' m')[0])
    check(d <= 500, f'big-warhead missile removed at {d} m, limit is 500')

    shoot(sim, 'TR_SAM_SA6_3', SAM_MISSILE, 'Aerial-1-2')
    sim.run('MOCK.homeOn(W, MOCK.units["Aerial-1-2"], 700, 1800)')  # decoyed at 1.8 km
    sim.advance(1)
    check(sim.find(r'defeated, closest'), 'a decoyed missile was not reported as defeated')

    sim = Sim()
    z = sim.zone('TR_DOGFIGHT')
    sim.clients('F18', 1, [{'name': 'Aerial-1-1', 'player': 'Eagle1', 'x': z['x'], 'y': 3000, 'z': z['z']},
                           {'name': 'Aerial-1-2', 'player': 'Eagle2', 'x': z['x'] + 2500, 'y': 3000, 'z': z['z']}])
    sim.load('TrainingRange.lua')
    sim.advance(3)
    shoot(sim, 'Aerial-1-1', AIM9, 'Aerial-1-2')
    sim.run('MOCK.homeOn(W, MOCK.units["Aerial-1-2"], 800)')
    check(sim.find(r'\[Dogfight\] AIM-9M kill on Eagle2'), 'dogfight missile kill not scored')
    check(sim.ev('return TR_Dogfight.players["Aerial-1-1"].score') == 1, 'shooter score is not 1')


# ===========================================================================
# TrainingRange: bombing scores
# ===========================================================================
MK82 = '{ category = 3, displayName = "Mk-82", typeName = "MK_82" }'
CBU = '{ category = 3, displayName = "CBU-87", typeName = "CBU_87" }'


def bombing_msgs(sim, since):
    return [m for m in sim.log(since) if '[Bombing Range]' in m]


def bomb_run(sim, target, long_m=0.0, right_m=0.0, alt=1000.0, speed=200.0, desc=MK82, burst=None, spacing=None):
    """A level release heading north at `speed` from `alt`, timed so the bomb
    lands long_m past the target and right_m to its east (vacuum ballistics,
    as in the mock). With spacing = [..], one bomb per lateral offset."""
    tx, tz = sim.ev(f'local p = MOCK.units["{target}"].p; return p.x, p.z')
    fall = math.sqrt(2 * alt / 9.81)
    x0 = tx - speed * fall + long_m
    sim.run(f'local u = MOCK.units["Aerial-1-1"]; u.p = {{ x = {x0}, y = {alt}, z = {tz + right_m} }}; '
            f'u.v = {{ x = {speed}, y = 0, z = 0 }}; u.hdg = 0')
    offsets = spacing or [0.0]
    sim.run('BOMBS = {}')
    for off in offsets:
        sim.run(f'''local s = MOCK.units["Aerial-1-1"]
            local w = MOCK.newWeapon({desc}, {{ x = {x0}, y = {alt}, z = {tz + right_m + off} }}, nil, {{ x = {speed}, y = 0, z = 0 }})
            BOMBS[#BOMBS + 1] = w
            MOCK.fire({{ id = world.event.S_EVENT_SHOT, initiator = s, weapon = w }})''')
    sim.run('MOCK.fall(BOMBS, %s)' % (burst if burst else 'nil'))


@test
def bomb_scores_distance_clock_and_grade():
    sim = Sim()
    sim.clients('F18', 1, [{'name': 'Aerial-1-1', 'player': 'Eagle1', 'x': 0, 'y': 1000, 'z': 0}])
    sim.load('TrainingRange.lua')
    sim.advance(2)
    sim.click('Training Range/Bombing Range/Heavy armour (T-90)/Spawn 1')
    sim.advance(2)

    # (the mock integrates the fall in 10 ms steps: a metre of slack)
    since = sim.mark()
    bomb_run(sim, 'TR_ARMOR_H_1_1', long_m=20)
    sim.advance(2)
    msg = sim.to_unit('Aerial-1-1', since)
    check(len(msg) == 1, f'expected one score message, got {msg}')
    d = num(r"Mk-82: (\d+) m at 12 o'clock from T-90, GOOD", msg[0])
    check(d is not None and abs(d - 20) <= 2, f'bomb 20 m long: {msg[0]}')

    since = sim.mark()
    bomb_run(sim, 'TR_ARMOR_H_1_1', right_m=10)
    sim.advance(2)
    msg = sim.to_unit('Aerial-1-1', since)
    d = num(r"Mk-82: (\d+) m at 3 o'clock from T-90, EXCELLENT", msg[0] if msg else '')
    check(d is not None and abs(d - 10) <= 2, f'bomb 10 m to the right: {msg}')

    # A direct hit that kills the target: its position was kept from the fall.
    since = sim.mark()
    bomb_run(sim, 'TR_ARMOR_H_1_1')
    sim.run('local u = MOCK.units["TR_ARMOR_H_1_1"]; u.alive = false; '
            'MOCK.fire({ id = world.event.S_EVENT_DEAD, initiator = u })')
    sim.advance(2)
    msg = sim.to_unit('Aerial-1-1', since)
    check(msg and 'from T-90, SHACK' in msg[0], f'direct hit on a target it destroyed: {msg}')
    check('3 scored, average' in msg[0], f'running average missing: {msg[0]}')

    board = sim.mark()
    sim.click('Training Range/Bombing Range/Scores')
    rows = sim.find(r'Bombs, average distance', board)
    check(rows and re.search(r'1\. Eagle1: 3 weapon\(s\), average (9|10) m, best [01] m \(SHACK\), 1 shack\(s\)', rows[0]),
          f'scoreboard: {rows}')


@test
def bomb_scores_salvo_airburst_and_what_is_not_scored():
    sim = Sim()
    sim.clients('F18', 1, [{'name': 'Aerial-1-1', 'player': 'Eagle1', 'x': 0, 'y': 1000, 'z': 0}])
    sim.load('TrainingRange.lua')
    sim.advance(2)
    sim.click('Training Range/Bombing Range/Light armour (BTR-80)/Spawn 1')
    sim.advance(2)

    since = sim.mark()
    bomb_run(sim, 'TR_ARMOR_L_1_1', spacing=[0.0, 30.0, 60.0])
    sim.advance(2)
    msg = sim.to_unit('Aerial-1-1', since)
    check(len(msg) == 1, f'a salvo of 3 gave {len(msg)} messages')
    avg = num(r'average (\d+) m \(3 of 3 scored\)', msg[0])
    check('3 x Mk-82: best' in msg[0] and avg is not None and abs(avg - 30) <= 2, f'salvo: {msg[0]}')

    since = sim.mark()
    bomb_run(sim, 'TR_ARMOR_L_1_1', long_m=15, desc=CBU, burst=300)
    sim.advance(2)
    msg = sim.to_unit('Aerial-1-1', since)
    d = num(r"CBU-87 \(opened in the air\): (\d+) m at 12 o'clock", msg[0] if msg else '')
    check(d is not None and abs(d - 15) <= 3, f'dispenser opening at 300 m, projected to the ground: {msg}')

    # Far off the range (and more than 30 km from it): not followed at all.
    since = sim.mark()
    z = sim.zone('TR_SEAD_RADAR')
    sim.run(f'local u = MOCK.units["Aerial-1-1"]; u.p = {{ x = {z["x"]}, y = 1000, z = {z["z"]} }}')
    sim.run(f'''BOMBS = {{ MOCK.newWeapon({MK82}, {{ x = {z["x"]}, y = 1000, z = {z["z"]} }}, nil, {{ x = 200, y = 0, z = 0 }}) }}
        MOCK.fire({{ id = world.event.S_EVENT_SHOT, initiator = MOCK.units["Aerial-1-1"], weapon = BOMBS[1] }})
        MOCK.fall(BOMBS)''')
    sim.advance(2)
    check(not bombing_msgs(sim, since), 'a bomb far from the range was scored')

    # Near the range but landing 3 km from every target and outside the zones: silent.
    since = sim.mark()
    bomb_run(sim, 'TR_ARMOR_L_1_1', long_m=-3000)
    sim.advance(2)
    check(not bombing_msgs(sim, since), 'an impact off the range was reported')

    # AI weapons are not scored.
    since = sim.mark()
    sim.run('MOCK.units["Aerial-1-1"].player = nil')
    bomb_run(sim, 'TR_ARMOR_L_1_1')
    sim.advance(2)
    check(not bombing_msgs(sim, since), 'an AI bomb was scored')


# ===========================================================================
# TrainingRange: strafe pit
# ===========================================================================
GUN = [{'count': 578, 'desc': {'category': 0, 'typeName': 'weapons.shells.M61_20_HE'}}]


def strafe_sim():
    sim = Sim()
    z = sim.zone('TR_STRAFE')
    sim.clients('F18', 1, [{'name': 'Aerial-1-1', 'player': 'Eagle1', 'x': z['x'] - 5000, 'y': 300, 'z': z['z'],
                            'hdg': 0, 'v': {'x': 200, 'y': 0, 'z': 0}, 'ammo': GUN}])
    sim.load('TrainingRange.lua')
    sim.advance(2)
    return sim, z


def fly_north(sim, to_x, step=0.1):
    sim.run(f'local u = MOCK.units["Aerial-1-1"]; while u.p.x < {to_x} do u.p.x = u.p.x + 200 * {step}; MOCK.advance({step}) end')


def burst(sim, rounds, hits, weapon='nil', target='TR_STRAFE_2_1'):
    sim.run(f'''local u = MOCK.units["Aerial-1-1"]; u.ammo[1].count = u.ammo[1].count - {rounds}
        local t = MOCK.units["{target}"]
        MOCK.fire({{ id = world.event.S_EVENT_SHOOTING_START, initiator = u }})
        for i = 1, {hits} do MOCK.fire({{ id = world.event.S_EVENT_HIT, initiator = u, target = t, weapon = {weapon} }}) end
        MOCK.fire({{ id = world.event.S_EVENT_SHOOTING_END, initiator = u }})''')


def pull_off(sim):
    sim.run('local u = MOCK.units["Aerial-1-1"]; u.p.z = u.p.z + 1000')
    sim.advance(3)


@test
def strafe_pit_pass_foul_and_scores():
    sim, z = strafe_sim()
    xs = sorted(sim.ev(f'return MOCK.units["TR_STRAFE_{i}_1"].p.z') for i in (1, 2, 3))
    check(abs(xs[1] - z['z']) < 1 and abs(xs[2] - xs[1] - 30) < 1 and abs(xs[1] - xs[0] - 30) < 1,
          f'targets not in a row across a northbound run-in: {xs}')

    since = sim.mark()
    fly_north(sim, z['x'] - 1500)
    check(sim.to_unit('Aerial-1-1', since) and 'rolling in' in sim.to_unit('Aerial-1-1', since)[0], 'no rolling-in call')
    burst(sim, 60, 20)
    burst(sim, 0, 3, weapon='MOCK.newWeapon({ category = 3, displayName = "Mk-82" }, { x = 0, y = 0, z = 0 })')
    fly_north(sim, z['x'] - 800)
    pull_off(sim)
    res = sim.find(r'\[Strafe pit\] Eagle1: ', since)
    check(res and '20 hits of 60 rounds, 33%, INEFFECTIVE PASS' in res[-1], f'pass result (bombs must not count): {res}')

    since = sim.mark()
    sim.run(f'local u = MOCK.units["Aerial-1-1"]; u.p.x, u.p.z = {z["x"] - 3500}, {z["z"]}')
    fly_north(sim, z['x'] - 400)  # inside the 610 m foul line
    burst(sim, 30, 10)
    pull_off(sim)
    check(sim.find('FOUL LINE', since), 'no foul line call')
    check(sim.find(r'0 hits of 30 rounds, 0%, \* INVALID', since), f'hits from inside the foul line counted: {sim.log(since)[-3:]}')

    since = sim.mark()
    sim.run(f'local u = MOCK.units["Aerial-1-1"]; u.p.x, u.p.z = {z["x"] - 2800}, {z["z"]}')
    fly_north(sim, z['x'] - 2700)
    burst(sim, 60, 55)
    sim.advance(1)
    sim.run(f'local u = MOCK.units["Aerial-1-1"]; u.p.x = {z["x"] - 2000}')
    sim.advance(0.5)
    fly_north(sim, z['x'] - 1000)
    pull_off(sim)
    check(sim.find(r'55 hits of 60 rounds, 92%, DEADEYE PASS', since), f'deadeye pass: {sim.find("Strafe pit", since)}')

    since = sim.mark()
    sim.run(f'local u = MOCK.units["Aerial-1-1"]; u.p.x, u.p.z = {z["x"] - 1200}, {z["z"]}')
    sim.advance(1)
    pull_off(sim)
    check(sim.find('left the box too quickly', since), 'a one-second pass was scored')

    board = sim.mark()
    sim.click('Training Range/Bombing Range/Scores')
    b = '\n'.join(sim.log(board))
    check('Eagle1: 2 pass(es), 75 hits of 120 rounds (63%), best pass 92%, 1 foul(s)' in b, f'scoreboard: {b}')

    sim.run('local u = MOCK.units["TR_STRAFE_1_1"]; u.alive = false; MOCK.fire({ id = world.event.S_EVENT_DEAD, initiator = u })')
    sim.advance(11)
    check(sim.ev('return Group.getByName("TR_STRAFE_1") ~= nil'), 'a destroyed strafe target did not come back')
    check(counts(sim)['line'] >= 1 and 'Strafe pit: run-in 360, foul line 2000 ft' in list(sim.g.MOCK.markTexts().values()),
          'strafe pit not drawn on the map')


# ===========================================================================
# TrainingRange: LSO
# ===========================================================================
LSO_LUA = '''
function LSO_GEOM()
    local ship = MOCK.units["TR_CARRIER"]
    local h = ship.hdg
    local fb = h - math.rad(9.1359)
    local sx = ship.p.x + math.cos(h) * -153 + math.cos(fb + math.pi / 2) * 7
    local sz = ship.p.z + math.sin(h) * -153 + math.sin(fb + math.pi / 2) * 7
    return { fb = fb, sx = sx, sz = sz, lx = sx + math.cos(fb) * 70, lz = sz + math.sin(fb) * 70 }
end
-- Down the landing area from d0 to d1 metres before the 3-wire point, gse degrees
-- off the 3.5 degree glide path, lue degrees lined up left, at an angle of attack.
function APPROACH(name, d0, d1, gse, lue, aoa, speed, air)
    local G = LSO_GEOM()
    local u = MOCK.units[name]
    local gam, s = math.rad(3.5 + gse), speed or 70
    local lx, lz = -math.cos(G.fb + math.pi / 2), -math.sin(G.fb + math.pi / 2)
    local d = d0
    while d > d1 do
        local side = math.max(d, 50) * math.tan(math.rad(lue))
        u.p.x = G.lx - math.cos(G.fb) * d + lx * side
        u.p.z = G.lz - math.sin(G.fb) * d + lz * side
        u.p.y = 20.3 + math.max(d, 0) * math.tan(gam)
        u.v = { x = math.cos(G.fb) * s, y = -s * math.tan(gam), z = math.sin(G.fb) * s }
        u.hdg, u.pitch, u.air = G.fb, math.rad(aoa) - gam, (air ~= false)
        MOCK.advance(0.1)
        d = d - s * 0.1
    end
end
-- Straight on along the landing area, climbing, for dist metres.
function CLIMBOUT(name, dist)
    local G = LSO_GEOM()
    local u = MOCK.units[name]
    for _ = 1, math.floor(dist / 7) do
        u.p.x, u.p.z, u.p.y = u.p.x + math.cos(G.fb) * 7, u.p.z + math.sin(G.fb) * 7, u.p.y + 3
        u.v = { x = math.cos(G.fb) * 70, y = 30, z = math.sin(G.fb) * 70 }
        MOCK.advance(0.1)
    end
end
-- Roll out on the deck and stop `stop` metres up the landing area from the ramp.
function TRAP(name, stop)
    local G = LSO_GEOM()
    local u = MOCK.units[name]
    u.air = false
    for k = 1, 20 do
        local d = 70 + (stop - 70) * k / 20
        u.p.x, u.p.z, u.p.y = G.sx + math.cos(G.fb) * d, G.sz + math.sin(G.fb) * d, 18.3
        local s = 70 * (1 - k / 20)
        u.v = { x = math.cos(G.fb) * s, y = 0, z = math.sin(G.fb) * s }
        MOCK.advance(0.1)
    end
    MOCK.advance(1)
end
'''


def lso_sim(type_name='FA-18C_hornet', cat=None):
    sim = Sim()
    z = sim.zone('TR_CARRIER')
    sim.clients('F18', 1, [{'name': 'Aerial-1-1', 'player': 'Eagle1', 'type': type_name,
                            'x': z['x'] + 20000, 'y': 500, 'z': z['z']}], cat)
    sim.load('TrainingRange.lua')
    sim.run(LSO_LUA)
    sim.advance(3)
    return sim


def lso_result(sim, since):
    return [m for m in sim.to_unit('Aerial-1-1', since) if '[LSO] Eagle1:' in m]


NM1 = 1.1 * NM


@test
def lso_ok_pass_trap_and_wire():
    sim = lso_sim()
    since = sim.mark()
    sim.run(f'APPROACH("Aerial-1-1", {NM1}, 0, 0, 0, 8.1)')
    sim.run('TRAP("Aerial-1-1", 164)')  # about 100 m past the 3-wire
    res = lso_result(sim, since)
    check(len(res) == 1, f'expected one grade, got {res}')
    check(res[0].endswith('Eagle1: OK, 3-wire. no deviations'), f'perfect pass: {res[0]}')
    check(any('roger ball' in m for m in sim.to_unit('Aerial-1-1', since)), 'no roger ball')
    since = sim.mark()
    sim.run('MOCK.fire({ id = world.event.S_EVENT_LANDING_QUALITY_MARK, initiator = MOCK.units["Aerial-1-1"], '
            'comment = "LSO: GRADE:_OK_ : WIRE# 3" })')
    check(any('[LSO] DCS: LSO: GRADE:_OK_ : WIRE# 3' in m for m in sim.to_unit('Aerial-1-1', since)),
          'the native LSO grade was not passed on')


@test
def lso_deviations_grades_and_calls():
    # A little low all the way, on speed: small deviations do not cost the grade.
    sim = lso_sim()
    since = sim.mark()
    sim.run(f'APPROACH("Aerial-1-1", {NM1}, 0, -0.4, 0, 8.1)')
    sim.run('TRAP("Aerial-1-1", 150)')
    res = lso_result(sim, since)
    check(res and 'OK, 2-wire. (LO)X (LO)IM (LO)IC (LO)AR' in res[0], f'slightly low pass: {res}')

    # Low (normal deviation) and slow: a fair pass, with "Power" calls.
    since = sim.mark()
    sim.run(f'APPROACH("Aerial-1-1", {NM1}, 0, -0.7, 0, 9.5)')
    sim.run('TRAP("Aerial-1-1", 164)')
    res = lso_result(sim, since)
    check(res and '(OK), 3-wire. SLOLOX SLOLOIM SLOLOIC SLOLOAR' in res[0], f'low and slow pass: {res}')
    calls = [m for m in sim.to_unit('Aerial-1-1', since) if 'clear]' in m]
    check(any('Power.' in m and "You're slow." in m for m in calls), f'no live calls: {calls[:3]}')

    # Lined up left 2.9 degrees (under the 3 degree wave-off limit): a fair pass.
    since = sim.mark()
    sim.run(f'APPROACH("Aerial-1-1", {NM1}, 0, 0, 2.9, 8.1)')
    sim.run('TRAP("Aerial-1-1", 175)')
    res = lso_result(sim, since)
    check(res and '(OK), 4-wire. LULX LULIM LULIC LULAR' in res[0], f'lined up left 2.9 deg: {res}')
    calls = [m for m in sim.to_unit('Aerial-1-1', since) if 'clear]' in m]
    check(any('Right for lineup.' in m for m in calls), 'no "Right for lineup"')

    # Well low but above the wave-off limit: large deviations, no grade.
    since = sim.mark()
    sim.run(f'APPROACH("Aerial-1-1", {NM1}, 0, -1.0, 0, 8.1)')
    sim.run('TRAP("Aerial-1-1", 150)')
    res = lso_result(sim, since)
    check(res and '--, 2-wire. _LO_X _LO_IM _LO_IC _LO_AR' in res[0], f'1 degree low: {res}')

    # The Tomcat has its own on-speed angle of attack (15 units = 10.36 deg).
    sim = lso_sim('F-14B')
    since = sim.mark()
    sim.run(f'APPROACH("Aerial-1-1", {NM1}, 0, 0, 0, 10.4)')
    sim.run('TRAP("Aerial-1-1", 164)')
    res = lso_result(sim, since)
    check(res and 'OK, 3-wire. no deviations' in res[0], f'Tomcat on speed: {res}')

    board = sim.mark()
    sim.click('Training Range/Carrier Ops/LSO grades (greenie board)')
    b = '\n'.join(sim.log(board))
    check('1. Eagle1: 4.00 over 1 pass(es) | OK' in b, f'greenie board: {b}')


@test
def lso_waveoff_bolter_owo_and_who_is_graded():
    # Low in close: waved off, and flies past the bow.
    sim = lso_sim()
    since = sim.mark()
    sim.run(f'APPROACH("Aerial-1-1", {NM1}, -400, -1.5, 0, 8.1)')
    msgs = sim.to_unit('Aerial-1-1', since)
    check(any('WAVE OFF, WAVE OFF!' in m for m in msgs), 'no wave-off call at 1.5 deg low in close')
    res = lso_result(sim, since)
    check(res and 'WO (waved off)' in res[0] and 'waved off: too low' in res[0], f'wave-off: {res}')

    # Touch and go: bolter.
    since = sim.mark()
    sim.run(f'APPROACH("Aerial-1-1", {NM1}, 0, 0, 0, 8.1)')
    sim.run('APPROACH("Aerial-1-1", 0, -40, 0, 0, 8.1, 70, false)')   # on the deck for half a second
    sim.run('APPROACH("Aerial-1-1", -40, -500, 0, 0, 8.1)')           # and off again
    res = lso_result(sim, since)
    check(res and '-- (BOLTER)' in res[0], f'bolter: {res}')

    # Climbs away at the ramp without being waved off: own wave-off.
    since = sim.mark()
    sim.run(f'APPROACH("Aerial-1-1", {NM1}, 110, 0, 0, 8.1)')
    sim.run('CLIMBOUT("Aerial-1-1", 700)')
    res = lso_result(sim, since)
    check(res and 'OWO (own wave-off)' in res[0], f'own wave-off: {res}')

    # Calls off: still graded, no live calls.
    since = sim.mark()
    sim.click('Training Range/Carrier Ops/LSO live calls on/off')
    sim.run(f'APPROACH("Aerial-1-1", {NM1}, 0, -0.7, 0, 8.1)')
    sim.run('TRAP("Aerial-1-1", 164)')
    check(not [m for m in sim.to_unit('Aerial-1-1', since) if 'clear]' in m], 'live calls with the calls off')
    check(lso_result(sim, since), 'no grade with the calls off')

    # A helicopter on the same path is not graded.
    sim = lso_sim('SH-60B', cat=1)
    since = sim.mark()
    sim.run(f'APPROACH("Aerial-1-1", {NM1}, 0, 0, 0, 8.1)')
    sim.run('TRAP("Aerial-1-1", 164)')
    check(not lso_result(sim, since), 'a helicopter was graded')


# ===========================================================================
# TrainingRange: HARM reaction
# ===========================================================================
ARM = '{ category = 1, missileCategory = 6, guidance = 5, displayName = "AGM-88C", typeName = "AGM_88" }'


def sead_sim(preset='SA-6'):
    sim = Sim()
    z = sim.zone('TR_SEAD_RADAR')
    sim.clients('F18', 1, [{'name': 'Aerial-1-1', 'player': 'Eagle1', 'x': z['x'] - 40000, 'y': 6000, 'z': z['z']}])
    sim.load('TrainingRange.lua')
    sim.advance(2)
    sim.click(f'Training Range/SEAD Range/Radar Zone/Spawn {preset}')
    sim.advance(2)
    return sim


def radar_state(sim, group):
    return sim.ev(f'local g = MOCK.groups["{group}"]; return tostring(g.emission), g.ctrl.options[9], g.ctrl.options[0]')


def toward(sim, frm, to, speed=600.0, off_deg=0.0):
    a = sim.ev(f'local p, q = MOCK.units["{frm}"].p, MOCK.units["{to}"].p; return math.atan2(q.z - p.z, q.x - p.x)')
    a += math.radians(off_deg)
    return (speed * math.cos(a), 0.0, speed * math.sin(a))


@test
def harm_reaction_radar_off_then_back_on():
    sim = sead_sim()
    since = sim.mark()
    shoot(sim, 'Aerial-1-1', ARM, 'TR_SAM_SA6_1', toward(sim, 'Aerial-1-1', 'TR_SAM_SA6_1'))
    sim.advance(1)
    check(radar_state(sim, 'TR_SAM_SA6')[0] == 'nil', 'radar went off before the crew reaction time')
    sim.advance(10)
    em, alarm, _ = radar_state(sim, 'TR_SAM_SA6')
    check(em == 'false' and alarm == 1, f'radar not off 11 s after the launch (emission {em}, alarm {alarm})')
    check(sim.find(r'SA-6 radar OFF: anti-radiation missile inbound', since), 'shooter not told the radar went off')
    sim.run('MOCK.homeOn(W, MOCK.units["TR_SAM_SA6_1"], 600)')
    sim.advance(15)
    check(radar_state(sim, 'TR_SAM_SA6')[0] == 'false', 'radar back on less than 20 s after the missile')
    sim.advance(35)
    em, alarm, roe = radar_state(sim, 'TR_SAM_SA6')
    check(em == 'true' and alarm == 2 and roe == 2, f'radar not back on and engaging (emission {em}, alarm {alarm}, ROE {roe})')
    check(sim.find(r'SA-6 radar back ON', since), 'radar back on not announced')


@test
def harm_reaction_two_missiles_and_shots_without_target():
    sim = sead_sim()
    v = toward(sim, 'Aerial-1-1', 'TR_SAM_SA6_1')
    shoot(sim, 'Aerial-1-1', ARM, 'TR_SAM_SA6_1', v)
    sim.run('W1 = W')
    shoot(sim, 'Aerial-1-1', ARM, 'TR_SAM_SA6_1', v)
    sim.run('W2 = W')
    sim.advance(11)
    sim.run('W1.alive = false')
    sim.advance(50)
    check(radar_state(sim, 'TR_SAM_SA6')[0] == 'false', 'radar came back on with a second missile still inbound')
    sim.run('W2.alive = false')
    sim.advance(47)
    check(radar_state(sim, 'TR_SAM_SA6')[0] == 'true', 'radar not back on after the last missile')

    # Pre-briefed shot, no target: flying at the site counts, 90 degrees off does not.
    sim = sead_sim()
    shoot(sim, 'Aerial-1-1', ARM, None, toward(sim, 'Aerial-1-1', 'TR_SAM_SA6_1', off_deg=5))
    sim.advance(11)
    check(radar_state(sim, 'TR_SAM_SA6')[0] == 'false', 'a missile flying at the site without a target was ignored')
    sim = sead_sim()
    shoot(sim, 'Aerial-1-1', ARM, None, toward(sim, 'Aerial-1-1', 'TR_SAM_SA6_1', off_deg=90))
    sim.advance(11)
    check(radar_state(sim, 'TR_SAM_SA6')[0] == 'nil', 'a missile flying elsewhere shut the radar down')

    # Switched off from the menu: no reaction.
    sim = sead_sim()
    sim.click('Training Range/SEAD Range/Radar Zone/HARM reaction on/off')
    shoot(sim, 'Aerial-1-1', ARM, 'TR_SAM_SA6_1', toward(sim, 'Aerial-1-1', 'TR_SAM_SA6_1'))
    sim.advance(11)
    check(radar_state(sim, 'TR_SAM_SA6')[0] == 'nil', 'the radar reacted with the HARM reaction off')

    # Rapier is optical: an ARM has nothing to home on and it keeps going.
    sim = sead_sim('Rapier (optical)')
    shoot(sim, 'Aerial-1-1', ARM, 'TR_SAM_RAPIER_1', toward(sim, 'Aerial-1-1', 'TR_SAM_RAPIER_1'))
    sim.advance(11)
    check(radar_state(sim, 'TR_SAM_RAPIER')[0] == 'nil', 'the optical Rapier reacted to an ARM')


# ===========================================================================
# TrainingRange: F10 map drawings
# ===========================================================================
def counts(sim):
    return {k: int(sim.ev(f'return MOCK.countMarks("{k}")')) for k in ('quad', 'circle', 'line', 'text')}


@test
def map_drawings_zones_tankers_carrier():
    sim = Sim().load('TrainingRange.lua')
    sim.advance(2)
    c = counts(sim)
    check(c == {'quad': 4, 'circle': 4, 'line': 1, 'text': 8},
          f'initial drawings: {c} (3 zone quads + strafe box, 3 zone circles + carrier, foul line)')
    texts = list(sim.g.MOCK.markTexts().values())
    check(any('TR_CARRIER (Stennis) | 127.500 AM | TACAN 74X STN | ICLS 11' in t for t in texts), f'carrier label: {texts}')
    check(sim.ev('for _, m in pairs(MOCK.marks) do if m.side ~= 2 then return false end end return true'),
          'a drawing is visible to a coalition other than BLUE')

    sim.click('Training Range/Refueling/Spawn Basket tanker')
    c = counts(sim)
    check(c['line'] == 2 and c['circle'] == 6 and c['text'] == 9, f'basket track: {c}')
    texts = list(sim.g.MOCK.markTexts().values())
    check(any('Basket tanker (KC135MPRS) | 251.000 AM | TACAN 51Y TKR' in t and '250 KIAS' in t for t in texts), f'{texts}')
    sim.click('Training Range/Refueling/Basket speed/310 KIAS')
    texts = list(sim.g.MOCK.markTexts().values())
    check(counts(sim)['line'] == 2 and any('310 KIAS' in t for t in texts), 'speed change not redrawn in place')
    sim.click('Training Range/Refueling/Remove Basket tanker')
    check(counts(sim)['line'] == 1, 'tanker track left on the map')

    sim.click('Training Range/Carrier Ops/Spawn S-3B Recovery Tanker')
    check(counts(sim)['line'] == 2, 'S-3B track not drawn')
    sim.run('MOCK.groups["TR_S3_TANKER"]:destroy()')  # shot down
    sim.run('local c = MOCK.units["TR_CARRIER"]; c.p.x = c.p.x + 3000')
    sim.advance(31)
    check(counts(sim)['line'] == 1, 'track of a tanker that is gone still on the map')
    d = sim.ev('local c = MOCK.units["TR_CARRIER"]; for _, m in pairs(MOCK.marks) do '
               'if m.kind == "circle" and m.radius == 1852 then return MOCK.dist(m.center.x, m.center.z, c.p.x, c.p.z) end end')
    check(d is not None and d < 1, f'carrier ring did not follow the ship (off by {d})')

    sim.click('Training Range/Map drawings on/off')
    check(counts(sim) == {'quad': 0, 'circle': 0, 'line': 0, 'text': 0}, 'drawings left after switching them off')
    sim.click('Training Range/Refueling/Spawn Boom tanker')
    check(counts(sim)['line'] == 0, 'a tanker was drawn with the drawings off')
    sim.click('Training Range/Map drawings on/off')
    c = counts(sim)
    check(c == {'quad': 4, 'circle': 6, 'line': 2, 'text': 9}, f'drawings after switching back on: {c}')
    check(not sim.find('DUPLICATE ID'), 'two drawings shared an id')


@test
def every_training_zone_is_on_the_map():
    sim = Sim().load(*SCRIPTS)
    sim.advance(2)
    c = counts(sim)
    # range: 3 quads + the strafe box, 3 circles + the carrier ring, the foul
    # line; intercept: 1 quad, 4 circles; air combat: 3 quads; one name for each
    check(c == {'quad': 8, 'circle': 8, 'line': 1, 'text': 16}, f'drawings with every script loaded: {c}')
    texts = list(sim.g.MOCK.markTexts().values())
    for t in ('Intercept: play box', 'Intercept: objective 3', 'Air combat: BVR mixed group', 'SEAD range: radar SAM'):
        check(t in texts, f'no "{t}" on the map')
    check(not sim.find('DUPLICATE ID'), 'two scripts drew with the same id')


# ===========================================================================
# TRAINING_Intercept.lua
# ===========================================================================
def intercept_sim(extra_groups=()):
    sim = Sim()
    z = sim.zone('INTERCEPT_PLAYER_ZONE')
    sim.clients('F18', 1, [{'name': f'Aerial-1-{i}', 'x': z['x'] + 20 * i, 'y': 3000, 'z': z['z']} for i in range(1, 5)])
    for g in extra_groups:
        sim.clients(*g)
    sim.load('TRAINING_Intercept.lua')
    sim.advance(2)
    return sim


@test
def intercept_menu_scramble_and_failure():
    sim = intercept_sim()
    check(sim.top_menus(gid=1).count('Intercept') == 1, f'4 clients of one group got {sim.top_menus(gid=1)}')
    sim.click('Intercept/Scramble', gid=1)
    sim.run('''for _ = 1, 400 do
        for n, g in pairs(MOCK.groups) do
          if n:find("INT_TGT") and g.units[1].alive then
            local u, wp = g.units[1], g.data.route.points[2]
            local dx, dz = wp.x - u.p.x, wp.y - u.p.z
            local d = math.sqrt(dx * dx + dz * dz)
            if d > 1 then u.p.x = u.p.x + dx / d * wp.speed; u.p.z = u.p.z + dz / d * wp.speed end
          end
        end
        MOCK.advance(1)
      end''')
    check(sim.find('Target airborne'), 'no target after the scramble')
    check(sim.find('Intercept failed'), 'a target that reached its objective did not fail the intercept')

    sim = intercept_sim()
    sim.click('Intercept/Scramble', gid=1)
    sim.advance(185)
    sim.run('local u = MOCK.units["INT_TGT_1_1"]; u.alive = false '
            'MOCK.fire({ id = world.event.S_EVENT_UNIT_LOST, initiator = u }) '
            'MOCK.fire({ id = world.event.S_EVENT_DEAD, initiator = u })')
    check(len(sim.find('Splash!')) == 1, 'a kill was not announced exactly once')


@test
def intercept_bogey_dope_braa():
    # A second flight far from the arming zone: the command reaches it too.
    sim = intercept_sim()
    lat, lon = sim.ev('local p = MOCK.units["Aerial-1-1"].p; local la, lo = coord.LOtoLL({ x = p.x - 30000, y = 0, z = p.z }); '
                      'return la, lo')
    fx, fz = sim.ev(f'local q = coord.LLtoLO({lat}, {lon}, 0); return q.x, q.z')
    sim.clients('F14', 2, [{'name': 'F14-1', 'callsign': 'Springfield11', 'x': fx, 'y': 7000, 'z': fz},
                           {'name': 'F14-2', 'callsign': 'Springfield12', 'x': fx - 5000, 'y': 7000, 'z': fz}])
    check('Bogey dope (intercept)' not in sim.top_menus(gid=2), 'bogey dope offered with no target up')
    sim.click('Intercept/Scramble', gid=1)
    sim.advance(185)
    check('Bogey dope (intercept)' in sim.top_menus(gid=2), 'no bogey dope for a flight outside the arming zone')
    check('Bogey dope (intercept)' in sim.top_menus(gid=1), 'no bogey dope for the scrambling flight')

    # Put the target 0.3 degrees of latitude TRUE north of F14-1, at 20,000 ft, flying south.
    tx, tz = sim.ev(f'local q = coord.LLtoLO({lat} + 0.3, {lon}, 0); return q.x, q.z')
    sim.run(f'local u = MOCK.units["INT_TGT_1_1"]; u.p = {{ x = {tx}, y = 6096, z = {tz} }}; u.v = {{ x = -250, y = 0, z = 0 }}')
    rng = round(math.hypot(tx - fx, tz - fz) / NM)
    since = sim.mark()
    sim.click('Bogey dope (intercept)', gid=2)
    m1 = sim.to_unit('F14-1', since)
    m2 = sim.to_unit('F14-2', since)
    check(m1 and m2, 'not every pilot of the flight got the picture')
    exp = f'[Intercept] Springfield 1-1, group BRAA 355/{rng}, 20 thousand, HOT, HOSTILE.'
    check(m1[0].endswith(exp), f'BRAA: {m1[0]!r}, expected {exp!r} (true north = 360, variation 5 E)')
    check('Springfield 1-2' in m2[0] and m2[0] != m1[0], f'wingman got the lead picture: {m2}')

    sim.run('MOCK.units["INT_TGT_1_1"].v = { x = 0, y = 0, z = 250 }')
    since = sim.mark()
    sim.click('Bogey dope (intercept)', gid=2)
    check(', BEAM EAST, HOSTILE.' in sim.to_unit('F14-1', since)[0], 'a target crossing east is not BEAM EAST')

    sim.run('local u = MOCK.units["INT_TGT_1_1"]; u.alive = false; MOCK.fire({ id = world.event.S_EVENT_DEAD, initiator = u })')
    sim.advance(3)
    check('Bogey dope (intercept)' not in sim.top_menus(gid=2), 'bogey dope left in the menu with no target')


# ===========================================================================
# TRAINING_AirCombat.lua
# ===========================================================================
@test
def aircombat_mixed_wave_scales_and_is_not_refilled():
    sim = Sim()
    zm = sim.zone('TR_BVR_MIXED')
    sim.clients('F18', 1, [{'name': f'Aerial-1-{i}', 'x': zm['x'] + 20 * i, 'y': 7000, 'z': zm['z']} for i in (1, 2)])
    sim.load('TRAINING_AirCombat.lua')
    sim.advance(2)
    check('BVR mixed (group)' in sim.top_menus(gid=1), 'mixed menu missing in the zone')
    sim.click('BVR mixed (group)/Start wave', gid=1)
    alive = 'local n = 0; for k in pairs(MOCK.groups) do if k:find("AC_MIX") and Group.getByName(k) then n = n + 1 end end; return n'
    n0 = sim.ev(alive)
    check(n0 >= 1, 'no mixed wave')
    sim.run('for n, g in pairs(MOCK.groups) do if n:find("AC_MIX") then g.units[1].alive = false; '
            'MOCK.fire({ id = world.event.S_EVENT_DEAD, initiator = g.units[1] }); break end end')
    sim.advance(4)
    check(sim.ev(alive) == n0 - 1, 'a killed bandit was replaced')
    sim.run(f'MOCK.addClientGroup("F14", 2, {{ {{ name = "F14-1", x = {zm["x"]}, y = 7000, z = {zm["z"]} }} }})')
    sim.advance(4)
    check(sim.ev(alive) > n0 - 1, 'the wave did not grow for a new player')


@test
def aircombat_dogfight_bandit_ahead_auto_and_leash():
    sim = Sim()
    zd = sim.zone('TR_DOGFIGHT_RED')
    sim.clients('F18', 1, [{'name': 'Aerial-1-1', 'x': zd['x'], 'y': 5000, 'z': zd['z'] - 5000, 'hdg': math.radians(90)}])
    sim.load('TRAINING_AirCombat.lua')
    sim.advance(2)
    sim.click('Dogfight vs RED/Spawn bandit/Su-27', gid=1)
    brg = sim.ev('local u, p = MOCK.units["AC_DOGFIGHT_1_1"], MOCK.units["Aerial-1-1"]; return MOCK.bearing(p.p.x, p.p.z, u.p.x, u.p.z)')
    check(abs(brg - 90) < 1, f'bandit not ahead of the player (bearing {brg:.1f})')
    sim.click('Dogfight vs RED/Auto on/off', gid=1)
    sim.run('local u = MOCK.units["AC_DOGFIGHT_1_1"]; u.p.x = u.p.x + 40000')
    sim.advance(64)
    check(sim.find('left the arena and was removed'), 'a bandit out of the arena for a minute was not removed')


# ===========================================================================
# TRAINING_GCA.lua (Paphos 11/29 as the airbase under the zone)
# ===========================================================================
PAPHOS = (-18713, -314121)


def gca_sim(course_deg=-114.1, name='11', wind=None, spec=None, secs=8):
    cx, cz = PAPHOS
    sim = Sim(*(wind or (None, 0)))
    sim.run(f'''local ab = {{}}
        function ab:getPoint() return {{ x = {cx}, y = 10, z = {cz} }} end
        function ab:getDesc() return {{ category = 0 }} end
        function ab:getName() return "Paphos" end
        function ab:getRunways() return {{ {{ course = math.rad({course_deg}), Name = "{name}", length = 2718, width = 45,
            position = {{ x = {cx}, y = 10, z = {cz} }} }} }} end
        MOCK.airbases = {{ ab }}''')
    if spec:
        sim.clients('F18', 1, [spec])
    sim.load('TRAINING_GCA.lua')
    sim.advance(secs)
    return sim


def on_final(nm, lateral=0.0, height=None):
    h29 = math.radians(294.1)
    cx, cz = PAPHOS
    tx, tz = cx - math.cos(h29) * 1359, cz - math.sin(h29) * 1359
    d = nm * NM
    x = tx - math.cos(h29) * d - math.sin(h29) * lateral
    z = tz - math.sin(h29) * d + math.cos(h29) * lateral
    if height is None:
        height = 15.24 + d * math.tan(math.radians(3))
    return {'name': 'Aerial-1-1', 'player': 'Eagle1', 'x': x, 'y': height, 'z': z, 'hdg': h29}


@test
def gca_contact_talkdown_and_runway_in_use():
    for course, name in ((-114.1, '11'), (294.1, '29')):  # the course sign has changed between DCS versions
        sim = gca_sim(course, name, spec=on_final(3))
        c = sim.find('radar contact')
        check(c and 'PAR approach to runway 29' in c[0] and 'Fly heading 28' in c[0],
              f'contact call with course {course}: {c}')
        check(sim.find(r'on course, on glidepath'), f'no talkdown with course {course}')
    sim = gca_sim(spec=on_final(3, 200, 15.24 + 3 * NM * math.tan(math.radians(3)) - 60), secs=12)
    t = sim.find(r'left of course|right of course')
    check(t and 'right of course' in t[-1] and 'below glidepath' in t[-1], f'200 m right, 60 m low: {t[-1:]}')
    sim = gca_sim(wind=(110, 12), spec=on_final(3), secs=3)
    check(sim.find('runway 11 in use'), 'wind 110/12: the active runway was not given')
    sim = gca_sim(spec={'name': 'Aerial-1-1', 'player': 'Eagle1', 'x': PAPHOS[0], 'y': 10, 'z': PAPHOS[1], 'air': False}, secs=4)
    check(not sim.find('radar contact'), 'a parked aircraft got radar contact')


# ===========================================================================
# JTAC.lua and TRAINING_Comms.lua
# ===========================================================================
@test
def jtac_sticky_target_code_change_and_loss():
    sim = Sim().load('TrainingRange.lua', 'JTAC.lua')
    sim.advance(2)
    sim.click('Training Range/Bombing Range/Heavy armour (T-90)/Spawn 3')
    sim.click('Training Range/Bombing Range/Spawn convoy')
    sim.click('JTAC / Spotter/Spawn UAV spotter (MQ-9)')
    sim.advance(3)
    note = lambda: sim.ev('return TRAINING_COMMS.assets.JTAC and TRAINING_COMMS.assets.JTAC.note')
    first = note()
    check(first and first.startswith('lasing '), f'not lasing: {first}')
    sim.run('local j = MOCK.units["JTAC_UNIT_1"] for i = 1, 3 do local c = MOCK.units["TR_CONVOY_" .. i]; '
            'c.p.x, c.p.z = j.p.x + 10 * i, j.p.z end')
    sim.advance(3)
    check(note() == first, 'a closer target stole the spot')
    sim.click('JTAC / Spotter/Laser code/1511')
    sim.advance(2)
    check(note() == first and sim.ev('return TRAINING_COMMS.assets.JTAC.laser') == 1511, 'code change dropped the target')
    sim.run('MOCK.units[TRAINING_COMMS.assets.JTAC.note:match("lasing (.+)")].alive = false')
    sim.advance(2)
    check(note() != first, 'did not move on after the target died')
    sim.run('MOCK.units["JTAC_UNIT_1"].alive = false')
    sim.advance(2)
    check(sim.find('lost, laser off'), 'spotter loss not announced')


@test
def comms_card_lists_every_blue_asset():
    sim = Sim().load(*SCRIPTS)
    sim.advance(3)
    for path in ('Training Range/Refueling/Spawn Basket tanker', 'Training Range/Refueling/Spawn Boom tanker',
                 'Training Range/Carrier Ops/Spawn S-3B Recovery Tanker', 'JTAC / Spotter/Spawn UAV spotter (MQ-9)'):
        sim.click(path)
    sim.advance(2)
    since = sim.mark()
    sim.click('Comms card (radio / TACAN / ICLS)', side=2)
    card = '\n'.join(sim.log(since))
    for want in ('74X STN', 'ICLS 11', '251.000 AM', '51Y TKR', '252.000 AM', '253.000 AM', '53Y RCV', '1688'):
        check(want in card, f'comms card lacks {want}')
    since = sim.mark()
    sim.click('Comms card (radio / TACAN / ICLS)', side=1)
    red = '\n'.join(sim.log(since))
    check('74X' not in red and 'TKR' not in red, 'RED card shows BLUE assets')


# ===========================================================================
# Everything at once: every BLUE command, twice
# ===========================================================================
@test
def smoke_every_command_twice_no_errors_no_new_globals():
    sim = Sim()
    for gid, (gname, zn) in enumerate((('F18', 'TR_DOGFIGHT'), ('F14', 'INTERCEPT_PLAYER_ZONE'), ('A', 'TR_DOGFIGHT_RED'),
                                       ('B', 'TR_BVR_RED'), ('C', 'TR_BVR_MIXED'), ('D', 'TR_SEAD_RADAR')), start=1):
        z = sim.zone(zn)
        sim.clients(gname, gid, [{'name': f'{gname}-1', 'x': z['x'], 'y': 3000, 'z': z['z']}])
    sim.run('''NEWG = {}
        setmetatable(_G, { __newindex = function(t, k, v) NEWG[#NEWG + 1] = tostring(k); rawset(t, k, v) end })''')
    sim.load(*SCRIPTS)
    sim.advance(190)  # a scramble fires inside this window
    sim.run('''CLICKED = 0
        for pass = 1, 2 do
            local cmds = {}
            for _, m in ipairs(MOCK.menus) do if m.kind == "cmd" and (m.side == nil or m.side == 2) then cmds[#cmds + 1] = m end end
            for _, m in ipairs(cmds) do
                local ok, e = pcall(m.fn)
                CLICKED = CLICKED + 1
                if not ok then LOG[#LOG + 1] = "[click error] " .. m.path .. ": " .. tostring(e) end
                MOCK.advance(0.5)
            end
        end''')
    sim.advance(400)
    check(sim.ev('return CLICKED') > 200, 'fewer commands than expected')
    errs = sim.find('error')
    check(not errs, f'errors: {errs[:5]}')
    allowed = {'TR_Config', 'TR_Initialized', 'TR_Bombing', 'TR_Dogfight', 'TR_SEAD', 'TR_Carrier', 'TR_Refueling',
               'TR_Markers', 'TR_Strafe', 'TR_LSO', 'TRAINING_COMMS', 'INTERCEPT_Initialized', 'GCA_Initialized', 'AIRCOMBAT_Initialized',
               'JTAC_Initialized', 'COMMS_Initialized', 'CLICKED'}
    new = set(sim.ev('return NEWG').values()) - allowed
    check(not new, f'scripts created unexpected globals: {sorted(new)}')


# ===========================================================================
def main(argv):
    words = [a for a in argv if not a.startswith('-')]
    harness.ECHO = '-v' in argv
    for a in argv:
        if a.startswith('--seed='):
            harness.SEED = int(a.split('=', 1)[1])
    chosen = [t for t in TESTS if not words or any(w in t.__name__ for w in words)]
    failed = 0
    for t in chosen:
        try:
            t()
            print(f'PASS  {t.__name__}')
        except AssertionError as e:
            failed += 1
            print(f'FAIL  {t.__name__}: {e}')
        except Exception:  # noqa: BLE001
            failed += 1
            print(f'ERROR {t.__name__}:')
            traceback.print_exc()
    print(f'\n{len(chosen) - failed} passed, {failed} failed')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
