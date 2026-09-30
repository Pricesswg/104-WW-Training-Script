-- ===========================================================================
-- mock_dcs.lua: a fake of the DCS mission-scripting API, enough to load the
-- training scripts and watch what they do (spawns, commands, menus, messages,
-- map drawings). It is NOT the simulator: AI, physics, radar and networking
-- are not modelled; the tests move units and weapons by hand.
--
-- Coordinates follow DCS: x = north, z = east, y = up; a unit heading is a
-- compass angle (0 = north, clockwise) in radians. The ground is flat at 0 m;
-- everything north of x = -42000 is land and south of it sea, which puts the
-- coast of Cyprus roughly where the Syria map has it for the test mission.
--
-- Every script call that matters is written to LOG, which the tests read.
-- ===========================================================================

LOG = {}
local function log(...)
    local t = {}
    for i = 1, select('#', ...) do t[#t + 1] = tostring(select(i, ...)) end
    local s = table.concat(t, ' ')
    LOG[#LOG + 1] = s
    if MOCK and MOCK.echo then print(string.format('[t=%6.1f] %s', MOCK.now, s)) end
end

MOCK = {
    now = 0, queue = {}, groups = {}, units = {}, players = {}, handlers = {},
    nextGid = 100, nextUid = 1000, menus = {}, nextMenu = 1, menuPath = {},
    wind = { x = 0, y = 0, z = 0 }, airbases = {}, marks = {},
    echo = false, log = log,
}

os = nil -- the default MissionScripting.lua sanitizes os, io, lfs and require

env = { mission = { triggers = { zones = {} } } }
function env.info(s) log('[env.info]', s) end

-- ---------------------------------------------------------------- trigger
trigger = { smokeColor = { Green = 0, Red = 1, White = 2, Orange = 3, Blue = 4 }, action = {}, misc = {} }
function trigger.action.outText(t, d, c) log('[outText]', t) end
function trigger.action.outTextForUnit(id, t, d, c) log('[outTextForUnit ' .. tostring(id) .. (c and ' clear' or '') .. ']', t) end
function trigger.action.outTextForGroup(id, t, d, c) log('[outTextForGroup ' .. tostring(id) .. ']', t) end
function trigger.action.outTextForCoalition(s, t, d, c) log('[outTextForCoalition ' .. tostring(s) .. ']', t) end
function trigger.action.smoke(p, c) end
function trigger.action.explosion(p, power) log('[explosion]', power) end
function trigger.misc.getZone(name)
    for _, z in ipairs(env.mission.triggers.zones) do
        if z.name == name then
            -- a Quad comes back as centre + stored radius, "like a circular zone"
            return { point = { x = z.x, y = 0, z = z.y }, radius = z.radius }
        end
    end
    return nil
end

-- Map drawings: each one is kept in MOCK.marks[id] until removed.
local function draw(kind, side, id, extra)
    if MOCK.marks[id] then log('[draw] DUPLICATE ID', id) end
    extra.kind, extra.side, extra.id = kind, side, id
    MOCK.marks[id] = extra
end
function trigger.action.markupToAll(shape, side, id, ...)
    local a = { ... }
    local pts = {}
    for i = 1, #a - 5 do pts[i] = a[i] end
    draw('markup' .. shape, side, id, { points = pts, color = a[#a - 4], fill = a[#a - 3] })
end
function trigger.action.quadToAll(side, id, p1, p2, p3, p4, color, fill, lt, ro, msg)
    draw('quad', side, id, { points = { p1, p2, p3, p4 }, color = color, fill = fill })
end
function trigger.action.circleToAll(side, id, c, r, color, fill, lt, ro, msg)
    draw('circle', side, id, { center = c, radius = r, color = color, fill = fill })
end
function trigger.action.lineToAll(side, id, a, b, color, lt, ro, msg)
    draw('line', side, id, { points = { a, b }, color = color })
end
function trigger.action.textToAll(side, id, p, color, fill, size, ro, text)
    draw('text', side, id, { point = p, text = text, color = color })
end
function trigger.action.removeMark(id) MOCK.marks[id] = nil end

-- ---------------------------------------------------------------- objects
coalition = { side = { NEUTRAL = 0, RED = 1, BLUE = 2 } }
country = { id = { RUSSIA = 0, USA = 2 } }
local COUNTRY_SIDE = { [0] = 1, [2] = 2 }
Group = { Category = { AIRPLANE = 0, HELICOPTER = 1, GROUND = 2, SHIP = 3, TRAIN = 4 } }
Unit = {}

local CtrlMT = {}; CtrlMT.__index = CtrlMT
function CtrlMT:setTask(t) self.tasks[#self.tasks + 1] = t; log('[setTask]', self.owner, t.id) end
function CtrlMT:setOption(id, v) self.options[id] = v end
function CtrlMT:setCommand(c) self.cmds[#self.cmds + 1] = c; log('[setCommand]', self.owner, c.id) end
local function newCtrl(owner) return setmetatable({ owner = owner, options = {}, cmds = {}, tasks = {} }, CtrlMT) end

local GroupMT = {}; GroupMT.__index = GroupMT
function GroupMT:getName() return self.name end
function GroupMT:getID() return self.id end
function GroupMT:getUnits()
    local out = {}
    for _, u in ipairs(self.units) do if u.alive then out[#out + 1] = u end end
    return out
end
function GroupMT:getController() return self.ctrl end
function GroupMT:getCoalition() return self.side end
function GroupMT:enableEmission(on) self.emission = on; log('[enableEmission]', self.name, tostring(on)) end
function GroupMT:destroy()
    MOCK.groups[self.name] = nil
    for _, u in ipairs(self.units) do u.alive = false; MOCK.units[u.name] = nil end
    log('[destroy]', self.name)
end
function Group.getByName(n)
    local g = MOCK.groups[n]
    if g and #g:getUnits() > 0 then return g end
    return nil
end

local UnitMT = {}; UnitMT.__index = UnitMT
function UnitMT:getName() return self.name end
function UnitMT:getID() return self.id end
function UnitMT:isExist() return self.alive end
function UnitMT:getPoint() return { x = self.p.x, y = self.p.y, z = self.p.z } end
function UnitMT:getPosition()
    local h = self.hdg or 0
    return { p = self:getPoint(), x = { x = math.cos(h), y = 0, z = math.sin(h) },
             y = { x = 0, y = 1, z = 0 }, z = { x = -math.sin(h), y = 0, z = math.cos(h) } }
end
function UnitMT:getVelocity()
    local v = self.v or { x = 0, y = 0, z = 0 }
    return { x = v.x, y = v.y or 0, z = v.z }
end
function UnitMT:getGroup() return self.group end
function UnitMT:getTypeName() return self.type end
function UnitMT:getPlayerName() return self.player end
function UnitMT:getCallsign() return self.callsign or self.name end
function UnitMT:getController() return self.ctrl or self.group.ctrl end
function UnitMT:inAir() return self.air end
function UnitMT:getCoalition() return self.group.side end
function Unit.getByName(n) local u = MOCK.units[n]; if u and u.alive then return u end end

function coalition.addGroup(cid, cat, data)
    local side = COUNTRY_SIDE[cid] or 0
    if MOCK.groups[data.name] then MOCK.groups[data.name]:destroy() end
    local g = setmetatable({ name = data.name, id = MOCK.nextGid, category = cat, side = side, units = {}, data = data }, GroupMT)
    MOCK.nextGid = MOCK.nextGid + 1
    g.ctrl = newCtrl(data.name)
    for i, ud in ipairs(data.units) do
        local u = setmetatable({ name = ud.name, id = MOCK.nextUid, type = ud.type, group = g, alive = true,
            p = { x = ud.x, y = ud.alt or 0, z = ud.y }, hdg = ud.heading or 0,
            air = (cat == 0 or cat == 1) }, UnitMT)
        MOCK.nextUid = MOCK.nextUid + 1
        g.units[i] = u
        MOCK.units[u.name] = u
    end
    MOCK.groups[g.name] = g
    log('[addGroup]', data.name, 'cat=' .. cat, 'side=' .. side, '#units=' .. #data.units)
    return g
end

-- A client group placed in the Mission Editor (players): BLUE, one controller
-- per unit. Each spec: name, x, y (altitude), z, hdg (radians), air, player,
-- callsign, v = { x, y, z } (m/s).
function MOCK.addClientGroup(gname, gid, list)
    local g = setmetatable({ name = gname, id = gid, category = 0, side = 2, units = {} }, GroupMT)
    g.ctrl = newCtrl(gname)
    for i, d in ipairs(list) do
        local u = setmetatable({ name = d.name, id = MOCK.nextUid, type = d.type or 'FA-18C_hornet', group = g,
            alive = true, p = { x = d.x, y = d.y, z = d.z }, hdg = d.hdg or 0, air = (d.air ~= false),
            player = d.player or d.name, callsign = d.callsign, v = d.v }, UnitMT)
        u.ctrl = newCtrl(d.name)
        MOCK.nextUid = MOCK.nextUid + 1
        g.units[i] = u
        MOCK.units[u.name] = u
        MOCK.players[#MOCK.players + 1] = u
    end
    MOCK.groups[gname] = g
    return g
end

function coalition.getPlayers(side)
    local out = {}
    for _, u in ipairs(MOCK.players) do if u.alive and u.group.side == side then out[#out + 1] = u end end
    return out
end
function coalition.getGroups(side, cat)
    local out = {}
    for _, g in pairs(MOCK.groups) do
        if g.side == side and (cat == nil or g.category == cat) then out[#out + 1] = g end
    end
    return out
end

-- ---------------------------------------------------------------- timer
timer = {}
function timer.getTime() return MOCK.now end
function timer.getAbsTime() return 28800 + MOCK.now end
function timer.scheduleFunction(fn, args, t)
    MOCK.queue[#MOCK.queue + 1] = { fn = fn, args = args, t = t }
    return #MOCK.queue
end
-- Run every scheduled function due before now + dt, in time order; a function
-- returning a number is scheduled again for that time, as in DCS.
function MOCK.advance(dt)
    local target = MOCK.now + dt
    while true do
        local bi, bt
        for i, q in ipairs(MOCK.queue) do
            if q.t <= target and (not bt or q.t < bt) then bi, bt = i, q.t end
        end
        if not bi then break end
        local q = table.remove(MOCK.queue, bi)
        MOCK.now = q.t
        local ok, r = pcall(q.fn, q.args, q.t)
        if not ok then log('[timer error]', r)
        elseif type(r) == 'number' then q.t = r; MOCK.queue[#MOCK.queue + 1] = q end
    end
    MOCK.now = target
end

-- ---------------------------------------------------------------- world
world = { event = { S_EVENT_SHOT = 1, S_EVENT_HIT = 2, S_EVENT_TAKEOFF = 3, S_EVENT_LAND = 4,
                    S_EVENT_CRASH = 5, S_EVENT_DEAD = 8, S_EVENT_BIRTH = 15, S_EVENT_KILL = 28,
                    S_EVENT_UNIT_LOST = 30 } }
function world.addEventHandler(h) MOCK.handlers[#MOCK.handlers + 1] = h end
function world.getAirbases() return MOCK.airbases end
function MOCK.fire(ev) for _, h in ipairs(MOCK.handlers) do h:onEvent(ev) end end

-- ---------------------------------------------------------------- menus
missionCommands = {}
local function addItem(kind, gid, name, parent, fn, side)
    local id = MOCK.nextMenu; MOCK.nextMenu = MOCK.nextMenu + 1
    local path = parent and (MOCK.menuPath[parent] .. '/' .. name) or name
    MOCK.menuPath[id] = path
    MOCK.menus[#MOCK.menus + 1] = { id = id, gid = gid, side = side, path = path, fn = fn, kind = kind, parent = parent }
    return id
end
function missionCommands.addSubMenuForCoalition(side, name, parent) return addItem('sub', nil, name, parent, nil, side) end
function missionCommands.addCommandForCoalition(side, name, parent, fn) return addItem('cmd', nil, name, parent, fn, side) end
function missionCommands.addSubMenu(name, parent) return addItem('sub', nil, name, parent) end
function missionCommands.addCommand(name, parent, fn) return addItem('cmd', nil, name, parent, fn) end
function missionCommands.addSubMenuForGroup(gid, name, parent) return addItem('sub', gid, name, parent) end
function missionCommands.addCommandForGroup(gid, name, parent, fn) return addItem('cmd', gid, name, parent, fn) end
function missionCommands.removeItemForGroup(gid, item)
    local doomed = { [item] = true }
    local changed = true
    while changed do
        changed = false
        for _, m in ipairs(MOCK.menus) do
            if m.parent and doomed[m.parent] and not doomed[m.id] then doomed[m.id] = true; changed = true end
        end
    end
    for i = #MOCK.menus, 1, -1 do if doomed[MOCK.menus[i].id] then table.remove(MOCK.menus, i) end end
end
local function visible(m, gid, side)
    if m.gid then return m.gid == gid end
    if m.side then return m.side == (side or 2) end
    return true
end
-- Top-level F10 entries seen by a group (gid) of a coalition (side).
function MOCK.topMenus(gid, side)
    local out = {}
    for _, m in ipairs(MOCK.menus) do
        if m.parent == nil and visible(m, gid, side) then out[#out + 1] = m.path end
    end
    return out
end
function MOCK.click(path, gid, side)
    for _, m in ipairs(MOCK.menus) do
        if m.kind == 'cmd' and m.path == path and visible(m, gid, side) then
            log('[click]', path); m.fn(); return true
        end
    end
    log('[click] NOT FOUND', path)
    return false
end

-- ---------------------------------------------------------------- land, air
land = { SurfaceType = { LAND = 1, SHALLOW_WATER = 2, WATER = 3, ROAD = 4, RUNWAY = 5 } }
function land.getHeight(p) return 0 end
function land.getSurfaceType(p)
    if MOCK.surface then return MOCK.surface(p.x, p.y) end
    return (p.x < -42000) and 3 or 1
end
function land.isVisible(a, b) return true end
-- Ray from origin along a unit direction, up to dist metres, against the flat
-- ground: the point where it meets y = 0, or nil.
function land.getIP(o, d, dist)
    if d.y >= 0 then return nil end
    local t = -o.y / d.y
    if t < 0 or t > dist then return nil end
    return { x = o.x + d.x * t, y = 0, z = o.z + d.z * t }
end
atmosphere = {}
function atmosphere.getWind(p) return { x = MOCK.wind.x, y = 0, z = MOCK.wind.z } end
AI = { Option = {
    Air = { id = { ROE = 0, REACTION_ON_THREAT = 1, RADAR_USING = 3 },
            val = { ROE = { WEAPON_FREE = 0, OPEN_FIRE_WEAPON_FREE = 1, OPEN_FIRE = 2, RETURN_FIRE = 3, WEAPON_HOLD = 4 },
                    REACTION_ON_THREAT = { NO_REACTION = 0, PASSIVE_DEFENCE = 1, EVADE_FIRE = 2, BYPASS_AND_ESCAPE = 3, ALLOW_ABORT_MISSION = 4 },
                    RADAR_USING = { NEVER = 0, FOR_ATTACK_ONLY = 1, FOR_SEARCH_IF_REQUIRED = 2, FOR_CONTINUOUS_SEARCH = 3 } } },
    Ground = { id = { ROE = 0, ALARM_STATE = 9 },
               val = { ROE = { OPEN_FIRE = 2, RETURN_FIRE = 3, WEAPON_HOLD = 4 }, ALARM_STATE = { AUTO = 0, GREEN = 1, RED = 2 } } },
    Naval = { id = { ROE = 0 }, val = { ROE = { OPEN_FIRE = 2, RETURN_FIRE = 3, WEAPON_HOLD = 4 } } },
} }
Spot = {}
function Spot.createLaser(src, ref, pt, code)
    local s = { code = code, pt = pt }
    function s:destroy() end
    function s:setPoint(p) self.pt = p end
    log('[Spot.createLaser]', src:getName(), code)
    return s
end
radio = { modulation = { AM = 0, FM = 1 } }
Airbase = { Category = { AIRDROME = 0, HELIPAD = 1, SHIP = 2 } }

-- ---------------------------------------------------------------- weapons
Weapon = { Category = { SHELL = 0, MISSILE = 1, ROCKET = 2, BOMB = 3, TORPEDO = 4 },
           MissileCategory = { AAM = 1, SAM = 2, BM = 3, ANTI_SHIP = 4, CRUISE = 5, OTHER = 6 },
           GuidanceType = { INS = 1, IR = 2, RADAR_ACTIVE = 3, RADAR_SEMI_ACTIVE = 4, RADAR_PASSIVE = 5,
                            TV = 6, LASER = 7, TELE = 8 } }
local WeaponMT = {}; WeaponMT.__index = WeaponMT
function WeaponMT:getDesc() return self.desc end
function WeaponMT:getPoint() return { x = self.p.x, y = self.p.y, z = self.p.z } end
function WeaponMT:getVelocity() return { x = self.v.x, y = self.v.y, z = self.v.z } end
function WeaponMT:getPosition()
    local v = self.v
    local s = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    local d = (s > 0) and { x = v.x / s, y = v.y / s, z = v.z / s } or { x = 1, y = 0, z = 0 }
    return { p = self:getPoint(), x = d }
end
function WeaponMT:isExist() return self.alive end
function WeaponMT:destroy() self.alive = false; log('[weapon destroyed]', self.desc.displayName) end
function WeaponMT:getTypeName() return self.desc.typeName end
function WeaponMT:getTarget() return self.target end
function MOCK.newWeapon(desc, p, target, v)
    return setmetatable({ desc = desc, p = { x = p.x, y = p.y, z = p.z }, alive = true, target = target,
                          v = v or { x = 0, y = 0, z = 0 } }, WeaponMT)
end

-- Falling weapons (one, or a list released together): gravity only, until
-- each reaches the ground (or burstAgl, where a dispenser opens). Time
-- advances with them; it stops at the last impact without advancing past it,
-- so a test can kill the target "by the blast" before the scripts look.
function MOCK.fall(ws, burstAgl, dt)
    dt = dt or 0.01
    if ws.desc then ws = { ws } end
    for _ = 1, 100000 do
        local flying = 0
        for _, w in ipairs(ws) do
            if w.alive then
                w.v.y = w.v.y - 9.81 * dt
                w.p.x, w.p.y, w.p.z = w.p.x + w.v.x * dt, w.p.y + w.v.y * dt, w.p.z + w.v.z * dt
                if w.p.y <= (burstAgl or 0) then
                    if not burstAgl then w.p.y = 0 end
                    w.alive = false
                else
                    flying = flying + 1
                end
            end
        end
        if flying == 0 then return end
        MOCK.advance(dt)
    end
end

-- A missile flying straight at a unit at a constant speed, until it is
-- destroyed or (vanishAt) it vanishes that close to the unit, as a decoyed
-- missile does.
function MOCK.homeOn(w, unit, speed, vanishAt, dt)
    dt = dt or 0.05
    for _ = 1, 100000 do
        if not w.alive then return end
        local dx, dy, dz = unit.p.x - w.p.x, unit.p.y - w.p.y, unit.p.z - w.p.z
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        if vanishAt and d < vanishAt then w.alive = false; return end
        if d < 1 then w.alive = false; return end
        local step = math.min(d, speed * dt)
        w.v = { x = dx / d * speed, y = dy / d * speed, z = dz / d * speed }
        w.p.x, w.p.y, w.p.z = w.p.x + dx / d * step, w.p.y + dy / d * step, w.p.z + dz / d * step
        MOCK.advance(dt)
    end
end

-- ---------------------------------------------------------------- helpers
function MOCK.bearing(ax, az, bx, bz) return (math.deg(math.atan2(bz - az, bx - ax)) + 360) % 360 end
function MOCK.dist(ax, az, bx, bz) return math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2) end
function MOCK.countMarks(kind)
    local n = 0
    for _, m in pairs(MOCK.marks) do if kind == nil or m.kind == kind then n = n + 1 end end
    return n
end
function MOCK.markTexts()
    local out = {}
    for _, m in pairs(MOCK.marks) do if m.kind == 'text' then out[#out + 1] = m.text end end
    table.sort(out)
    return out
end

-- ---------------------------------------------------------------- coord
-- Transverse Mercator of the Syria map (the constants SECTOR uses for it).
local A, F = 6378137.0, 1 / 298.257223563
local E2 = F * (2 - F); local EP2 = E2 / (1 - E2); local K0 = 0.9996
local LON0, FN, FE = 39, -3879866.0, 282801.0
local function tmFwd(lat, lon)
    local phi = math.rad(lat); local lam = math.rad(lon - LON0)
    local N = A / math.sqrt(1 - E2 * math.sin(phi) ^ 2); local T = math.tan(phi) ^ 2
    local C = EP2 * math.cos(phi) ^ 2; local Aa = lam * math.cos(phi)
    local M = A * ((1 - E2 / 4 - 3 * E2 ^ 2 / 64 - 5 * E2 ^ 3 / 256) * phi - (3 * E2 / 8 + 3 * E2 ^ 2 / 32 + 45 * E2 ^ 3 / 1024) * math.sin(2 * phi)
        + (15 * E2 ^ 2 / 256 + 45 * E2 ^ 3 / 1024) * math.sin(4 * phi) - (35 * E2 ^ 3 / 3072) * math.sin(6 * phi))
    local x = K0 * N * (Aa + (1 - T + C) * Aa ^ 3 / 6 + (5 - 18 * T + T ^ 2 + 72 * C - 58 * EP2) * Aa ^ 5 / 120)
    local y = K0 * (M + N * math.tan(phi) * (Aa ^ 2 / 2 + (5 - T + 9 * C + 4 * C ^ 2) * Aa ^ 4 / 24
        + (61 - 58 * T + T ^ 2 + 600 * C - 330 * EP2) * Aa ^ 6 / 720))
    return y + FN, x + FE
end
local function tmInv(n, e)
    n, e = n - FN, e - FE
    local M = n / K0
    local mu = M / (A * (1 - E2 / 4 - 3 * E2 ^ 2 / 64 - 5 * E2 ^ 3 / 256))
    local e1 = (1 - math.sqrt(1 - E2)) / (1 + math.sqrt(1 - E2))
    local phi1 = mu + (3 * e1 / 2 - 27 * e1 ^ 3 / 32) * math.sin(2 * mu) + (21 * e1 ^ 2 / 16 - 55 * e1 ^ 4 / 32) * math.sin(4 * mu)
        + (151 * e1 ^ 3 / 96) * math.sin(6 * mu) + (1097 * e1 ^ 4 / 512) * math.sin(8 * mu)
    local sp, cp, tp = math.sin(phi1), math.cos(phi1), math.tan(phi1)
    local C1 = EP2 * cp ^ 2; local T1 = tp ^ 2
    local N1 = A / math.sqrt(1 - E2 * sp ^ 2); local R1 = A * (1 - E2) / (1 - E2 * sp ^ 2) ^ 1.5
    local D = e / (N1 * K0)
    local lat = phi1 - (N1 * tp / R1) * (D ^ 2 / 2 - (5 + 3 * T1 + 10 * C1 - 4 * C1 ^ 2 - 9 * EP2) * D ^ 4 / 24
        + (61 + 90 * T1 + 298 * C1 + 45 * T1 ^ 2 - 252 * EP2 - 3 * C1 ^ 2) * D ^ 6 / 720)
    local lon = (D - (1 + 2 * T1 + C1) * D ^ 3 / 6 + (5 - 2 * C1 + 28 * T1 - 3 * C1 ^ 2 + 8 * EP2 + 24 * T1 ^ 2) * D ^ 5 / 120) / cp
    return math.deg(lat), LON0 + math.deg(lon)
end
coord = {}
function coord.LOtoLL(p) local la, lo = tmInv(p.x, p.z); return la, lo, p.y or 0 end
function coord.LLtoLO(la, lo, alt) local x, z = tmFwd(la, lo); return { x = x, y = alt or 0, z = z } end
