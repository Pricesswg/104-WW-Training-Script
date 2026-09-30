-- =========================================================
--  TRAINING_AirCombat.lua  (air-to-air arenas vs RED)
--  v1.2, feature-script style, native DCS scripting engine only
-- ---------------------------------------------------------
--  Three zone-gated arenas, each with an F10 menu that appears only while a
--  player is inside the matching zone:
--    Dogfight (TR_DOGFIGHT_RED) : pick a type, one bandit spawns ahead of you
--                                 at the far edge of the zone, same altitude.
--    BVR      (TR_BVR_RED)      : same, with a radar-missile loadout.
--    Mixed    (TR_BVR_MIXED)    : a package scaled to the number of players in
--                                 the zone (threat-budget x difficulty).
--  Dogfight/BVR keep ONE bandit up at a time and queue extra requests; with
--  Auto on, a fresh bandit comes up a few seconds after each kill. Leaving the
--  zone despawns the live bandit(s), and so does a bandit that stays out of
--  its arena for a minute.
--
--  REQUIRED ME ZONES (Circle or Quad):
--    TR_DOGFIGHT_RED, TR_BVR_RED, TR_BVR_MIXED
--  The three arenas are drawn on the F10 map with their names (CFG.markers).
--
--  LOADOUTS: empty by default = guns only (the dogfight is fully playable on
--  guns). To arm the bandits, fill LOADOUTS below with the weapon CLSIDs from
--  YOUR DCS version (the GUIDs are version-specific, so they are not hardcoded).
--  A wrong CLSID leaves that pylon empty; the spawn itself falls back to guns
--  only if DCS rejects the group.
-- =========================================================

-- ============== Fail-fast API guard ==============
if not (trigger and trigger.action and trigger.action.outText and trigger.action.outTextForUnit
        and coalition and coalition.addGroup and coalition.getPlayers
        and timer and timer.scheduleFunction
        and world and world.addEventHandler
        and missionCommands and missionCommands.addSubMenuForGroup and missionCommands.addCommandForGroup
        and missionCommands.removeItemForGroup
        and trigger.misc and trigger.misc.getZone) then
    if trigger and trigger.action and trigger.action.outText then
        trigger.action.outText("[Air Combat] Required DCS API missing. Script aborted.", 20)
    end
    return
end

-- ============== Config ==============
local CFG = {
    debug        = false,
    side         = coalition.side.BLUE,
    enemyCountry = country.id.RUSSIA,
    tickSec      = 2,
    respawnDelay = 15,    -- Auto: seconds after a kill before the next bandit
    gunsOnly     = false, -- force guns even if LOADOUTS are filled
    spawnSpeed   = 250,   -- m/s
    mixedAlt     = 7000,  -- m, spawn altitude for the mixed package
    minAGL       = 300,   -- m, a bandit never spawns lower than this above the ground
    outSec       = 60,    -- a bandit out of its arena this long is despawned
    zones = {
        dogfight = "TR_DOGFIGHT_RED",
        bvr      = "TR_BVR_RED",
        mixed    = "TR_BVR_MIXED",
    },
    difficultyFactor  = { Easy = 1.5, Even = 2.0, Hard = 2.5 }, -- budget = players x factor
    defaultDifficulty = "Even",
    markers           = true, -- draw the three arenas on the F10 map for BLUE
}

-- Selectable types (the 7 from the menu). type = exact DCS unit type string.
local TYPES = {
    { key = "L39",   label = "L-39ZA", type = "L-39ZA" },
    { key = "MIG21", label = "MiG-21", type = "MiG-21Bis" },
    { key = "MIG23", label = "MiG-23", type = "MiG-23MLD" },
    { key = "MIG29", label = "MiG-29", type = "MiG-29S" },
    { key = "SU27",  label = "Su-27",  type = "Su-27" },
    { key = "F16",   label = "F-16",   type = "F-16C_50" },
    { key = "F18",   label = "F-18",   type = "FA-18C_hornet" },
}
local TYPE_BY_KEY = {}
for _, t in ipairs(TYPES) do TYPE_BY_KEY[t.key] = t end

-- Threat value per type, used by the mixed-arena budget.
local THREAT = { L39 = 0.5, MIG21 = 1, MIG23 = 1.5, MIG29 = 2, SU27 = 3, F16 = 2.5, F18 = 2.5 }
-- Pool the mixed arena draws from (RED jets), highest value first.
local MIX_POOL = { "SU27", "MIG29", "MIG23", "MIG21" }

-- Per-type loadouts. Empty = guns only. Fill with the CLSIDs from your DCS
-- version (export a loadout in the ME to read them). Format:
--   LOADOUTS.SU27 = { wvr = { [station]="{CLSID}", ... }, bvr = { [station]="{CLSID}", ... } }
local LOADOUTS = {}

-- ============== State ==============
local STATE = {
    armed = {}, -- [groupId] = { menuRoot, arena, members = { [unitName] = true } }
    duel = {
        dogfight = { zone = CFG.zones.dogfight, mode = "wvr", active = nil, queue = {}, auto = false, lastType = nil, lastReq = nil, respawnAt = nil, outSince = nil, seq = 0 },
        bvr      = { zone = CFG.zones.bvr,      mode = "bvr", active = nil, queue = {}, auto = false, lastType = nil, lastReq = nil, respawnAt = nil, outSince = nil, seq = 0 },
    },
    -- spent = threat already sent in this wave (kills do not give it back, so
    -- the wave ends; it only grows when more players join the zone).
    mixed = { zone = CFG.zones.mixed, active = {}, outSince = {}, spent = 0, difficulty = CFG.defaultDifficulty, seq = 0 },
}

-- ============== Helpers ==============
local function _out(msg, t) trigger.action.outText(tostring(msg), t or 10) end
local function _dbg(msg, t) if CFG.debug then _out("[Air Combat][dbg] " .. tostring(msg), t or 6) end end

-- Zones, Circle or Quad. trigger.misc.getZone gives a Quad only its centre and
-- stored radius, so the drawn corners are read from env.mission ("verticies",
-- the DCS spelling; y there means world z). The editor stores them in "Z"
-- order (1-2 one side, 3-4 the opposite side in the same direction), not
-- around the outline: taken as they come, the test sees a bow-tie and half
-- the zone falls outside. Sorted by angle around the centre they make the
-- outline whatever the order.
local _quadCache = {}
local function _zone(name)
    local q = _quadCache[name]
    if q == nil then
        q = false
        local list = env and env.mission and env.mission.triggers and env.mission.triggers.zones
        for _, z in ipairs(list or {}) do
            if z.name == name then
                local verts = z.verticies or z.vertices
                if z.type == 2 and verts and #verts >= 3 then
                    local poly, cx, cz = {}, 0, 0
                    for i, v in ipairs(verts) do
                        poly[i] = { x = v.x, z = v.y }
                        cx, cz = cx + v.x, cz + v.y
                    end
                    cx, cz = cx / #poly, cz / #poly
                    table.sort(poly, function(a, b) return math.atan2(a.z - cz, a.x - cx) < math.atan2(b.z - cz, b.x - cx) end)
                    q = { poly = poly, cx = cx, cz = cz, r = 0 }
                    for _, p in ipairs(poly) do q.r = math.max(q.r, math.sqrt((p.x - q.cx) ^ 2 + (p.z - q.cz) ^ 2)) end
                end
                break
            end
        end
        _quadCache[name] = q
    end
    if q then return q end
    local c = trigger.misc.getZone(name)
    if c then return { cx = c.point.x, cz = c.point.z, r = c.radius } end
    return nil
end

local function _inZoneXZ(p, s)
    if not s then return false end
    if s.poly then
        local inside, j, poly = false, #s.poly, s.poly
        for i = 1, #poly do
            local a, b = poly[i], poly[j]
            if ((a.z > p.z) ~= (b.z > p.z)) and (p.x < (b.x - a.x) * (p.z - a.z) / (b.z - a.z) + a.x) then
                inside = not inside
            end
            j = i
        end
        return inside
    end
    local dx, dz = p.x - s.cx, p.z - s.cz
    return (dx * dx + dz * dz) <= (s.r * s.r)
end

local function _inAny(u, zoneName) return _inZoneXZ(u:getPoint(), _zone(zoneName)) end

local function _anyPlayerInZone(zoneName)
    local zr = _zone(zoneName); if not zr then return nil end
    for _, u in pairs(coalition.getPlayers(CFG.side) or {}) do
        if u and u:isExist() and _inZoneXZ(u:getPoint(), zr) then return u end
    end
end

local function _destroy(name)
    local g = name and Group.getByName(name)
    if g then g:destroy() end
end

-- Horizontal forward direction of the aircraft (nose). getPosition().x is the
-- forward unit vector; fall back to velocity. DCS world: +x North, +z East.
local function _playerForward(u)
    local ok, pos = pcall(function() return u:getPosition() end)
    if ok and pos and pos.x then
        local fx, fz = pos.x.x, pos.x.z
        local len = math.sqrt(fx * fx + fz * fz)
        if len > 0.01 then return { x = fx / len, z = fz / len } end
    end
    local v = u:getVelocity()
    local len = v and math.sqrt(v.x * v.x + v.z * v.z) or 0
    if len > 1 then return { x = v.x / len, z = v.z / len } end
    return { x = 1, z = 0 }
end

-- Distance from P along the unit vector d to the zone edge (first exit).
local function _maxDistInZone(P, d, s)
    if not s.poly then
        local fx, fz = P.x - s.cx, P.z - s.cz
        local b = fx * d.x + fz * d.z
        local disc = b * b - (fx * fx + fz * fz - s.r * s.r)
        if disc < 0 then return 0 end
        return math.max(0, -b + math.sqrt(disc))
    end
    local best
    for i = 1, #s.poly do
        local a, b = s.poly[i], s.poly[i % #s.poly + 1]
        local ex, ez = b.x - a.x, b.z - a.z
        local den = d.x * ez - d.z * ex
        if math.abs(den) > 1e-9 then
            local t = ((a.x - P.x) * ez - (a.z - P.z) * ex) / den
            local u = ((a.x - P.x) * d.z - (a.z - P.z) * d.x) / den
            if t > 0 and u >= 0 and u <= 1 and (not best or t < best) then best = t end
        end
    end
    return best or 0
end

local function _groundY(x, z) return land.getHeight({ x = x, y = z }) or 0 end

local function _gunsPayload()
    return { ["pylons"] = {}, ["fuel"] = "3000", ["flare"] = 30, ["chaff"] = 60, ["gun"] = 100 }
end

local function _buildPayload(typeKey, mode)
    local pl = _gunsPayload()
    if CFG.gunsOnly then return pl end
    local lo = LOADOUTS[typeKey] and LOADOUTS[typeKey][mode]
    if lo then
        for station, clsid in pairs(lo) do pl.pylons[station] = { ["CLSID"] = clsid } end
    end
    return pl
end

-- Heading (rad, DCS standard 0 = North = +x) from spawn point to target point.
local function _headingTo(sx, sz, tx, tz) return math.atan2(tz - sz, tx - sx) end

-- Route: spawn point, the point the bandit is sent to (the player, or the
-- arena centre), and as far again beyond it, so the route is still running
-- while the fight is on. EngageTargets at the first point covers the route.
local function _banditGroupData(name, typeStr, sx, sz, alt, hdg, payload, tx, tz)
    local function wp(x, z, tasks)
        return { ["x"] = x, ["y"] = z, ["alt"] = alt, ["alt_type"] = "BARO",
                 ["type"] = "Turning Point", ["action"] = "Turning Point", ["speed"] = CFG.spawnSpeed,
                 ["task"] = { id = "ComboTask", params = { tasks = tasks or {} } } }
    end
    local points = {
        [1] = wp(sx, sz, { [1] = { id = "EngageTargets", params = { targetTypes = { "Air" }, priority = 0 } } }),
        [2] = wp(tx, tz),
        [3] = wp(tx + (tx - sx), tz + (tz - sz)),
    }
    return {
        ["name"] = name, ["task"] = "CAP", ["uncontrolled"] = false, ["start_time"] = 0,
        ["units"] = { [1] = {
            ["type"] = typeStr, ["name"] = name .. "_1",
            ["x"] = sx, ["y"] = sz, ["alt"] = alt, ["alt_type"] = "BARO",
            ["speed"] = CFG.spawnSpeed, ["heading"] = hdg, ["skill"] = "High",
            ["payload"] = payload,
        } },
        ["route"] = { ["points"] = points },
    }
end

-- Spawn one RED bandit; on a rejected loadout, retry guns-only. Returns name or nil.
local function _spawnBandit(name, typeKey, mode, sx, sz, alt, tx, tz)
    local ty = TYPE_BY_KEY[typeKey]; if not ty then return nil end
    alt = math.max(alt, _groundY(sx, sz) + CFG.minAGL, _groundY(tx, tz) + CFG.minAGL)
    local hdg = _headingTo(sx, sz, tx, tz) -- face the target point
    local grp
    local ok = pcall(function()
        grp = coalition.addGroup(CFG.enemyCountry, Group.Category.AIRPLANE,
            _banditGroupData(name, ty.type, sx, sz, alt, hdg, _buildPayload(typeKey, mode), tx, tz))
    end)
    if (not ok or not grp) and not CFG.gunsOnly then
        pcall(function()
            grp = coalition.addGroup(CFG.enemyCountry, Group.Category.AIRPLANE,
                _banditGroupData(name, ty.type, sx, sz, alt, hdg, _gunsPayload(), tx, tz))
        end)
    end
    if not grp then
        _out("[Air Combat] Spawn failed for " .. ty.label .. " (check the type string).", 12)
        return nil
    end
    -- Weapons free + maneuver, applied on the post-spawn delay.
    timer.scheduleFunction(function()
        local g = Group.getByName(name); if not g then return nil end
        local c = g:getController()
        pcall(function() c:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_FREE) end)
        pcall(function() c:setOption(AI.Option.Air.id.REACTION_ON_THREAT, AI.Option.Air.val.REACTION_ON_THREAT.EVADE_FIRE) end)
        return nil
    end, nil, timer.getTime() + 1.0)
    return name
end

-- A bandit out of its arena for CFG.outSec seconds: true when it must go.
local function _outTooLong(tbl, key, name, zoneName)
    local g = Group.getByName(name)
    local u = g and g:getUnits()[1]
    if not u then tbl[key] = nil; return false end
    if _inAny(u, zoneName) then tbl[key] = nil; return false end
    tbl[key] = tbl[key] or timer.getTime()
    return timer.getTime() - tbl[key] >= CFG.outSec
end

-- ============== Duel arenas (dogfight / BVR) ==============
local function _duelSpawnInFront(arenaKey, typeKey, u)
    local D = STATE.duel[arenaKey]
    local zr = _zone(D.zone); if not zr then return nil end
    local P = u:getPoint()
    local d = _playerForward(u)
    local t = math.max(2000, _maxDistInZone({ x = P.x, z = P.z }, d, zr) - 1000) -- just inside the edge
    local sx, sz = P.x + d.x * t, P.z + d.z * t
    D.seq = D.seq + 1
    local name = "AC_" .. string.upper(arenaKey) .. "_" .. D.seq
    return _spawnBandit(name, typeKey, D.mode, sx, sz, math.max(300, P.y), P.x, P.z)
end

-- A player of the requesting group who is in the arena, else anyone in it.
local function _requester(D, gid)
    for _, u in pairs(coalition.getPlayers(CFG.side) or {}) do
        if u and u:isExist() and _inAny(u, D.zone) then
            local g = u:getGroup()
            if not gid or (g and g:getID() == gid) then return u end
        end
    end
    return gid and _anyPlayerInZone(D.zone) or nil
end

local function _duelTrySpawn(arenaKey)
    local D = STATE.duel[arenaKey]
    if D.active and Group.getByName(D.active) then return end -- one at a time
    if D.active then
        -- Gone without a death event (crashed, landed, despawned): Auto still rolls on.
        D.active = nil
        if D.auto and not D.respawnAt then D.respawnAt = timer.getTime() + CFG.respawnDelay end
    end
    if D.respawnAt then
        if timer.getTime() < D.respawnAt then return end       -- waiting on the Auto delay
        D.respawnAt = nil
        if D.auto and D.lastType then D.queue[#D.queue + 1] = { key = D.lastType, req = D.lastReq } end
    end
    if #D.queue == 0 then return end
    local item = D.queue[1]
    local u = _requester(D, item.req)
    if not u then return end                                    -- no one in the zone yet, keep queued
    table.remove(D.queue, 1)
    local name = _duelSpawnInFront(arenaKey, item.key, u)
    if name then
        D.active, D.lastType, D.lastReq, D.outSince = name, item.key, item.req, nil
        local ty = TYPE_BY_KEY[item.key]
        _out("[Air Combat] " .. (arenaKey == "dogfight" and "Dogfight" or "BVR") .. " bandit airborne: " .. ty.label .. ".", 10)
    end
end

local function _duelRequest(arenaKey, typeKey, groupId)
    local D = STATE.duel[arenaKey]
    D.queue[#D.queue + 1] = { key = typeKey, req = groupId }
    if D.active and Group.getByName(D.active) then
        _out("[Air Combat] " .. TYPE_BY_KEY[typeKey].label .. " queued (a bandit is already up).", 8)
    end
    _duelTrySpawn(arenaKey)
end

local function _duelToggleAuto(arenaKey)
    local D = STATE.duel[arenaKey]
    D.auto = not D.auto
    _out("[Air Combat] " .. (arenaKey == "dogfight" and "Dogfight" or "BVR") .. " Auto " ..
        (D.auto and ("ON (new bandit " .. CFG.respawnDelay .. "s after each kill).") or "OFF."), 8)
end

local function _duelStop(arenaKey)
    local D = STATE.duel[arenaKey]
    local name = D.active
    D.auto, D.respawnAt, D.queue, D.active, D.outSince = false, nil, {}, nil, nil -- forget first, then destroy
    if name then _destroy(name) end
    _out("[Air Combat] " .. (arenaKey == "dogfight" and "Dogfight" or "BVR") .. " cleared.", 8)
end

local function _duelOnKill(arenaKey)
    local D = STATE.duel[arenaKey]
    D.active, D.outSince = nil, nil
    _out("[Air Combat] Splash! Bandit down.", 10)
    if D.auto then D.respawnAt = timer.getTime() + CFG.respawnDelay
    else _duelTrySpawn(arenaKey) end
end

-- ============== Mixed arena (threat-budget) ==============
local function _mixedCount()
    local zr = _zone(STATE.mixed.zone); if not zr then return 0, 0 end
    local n = 0
    for _, u in pairs(coalition.getPlayers(CFG.side) or {}) do
        if u and u:isExist() and _inZoneXZ(u:getPoint(), zr) then n = n + 1 end
    end
    return n * (CFG.difficultyFactor[STATE.mixed.difficulty] or 2.0), n
end

local function _mixedAlive()
    local n = 0
    for name in pairs(STATE.mixed.active) do
        if Group.getByName(name) then n = n + 1 else STATE.mixed.active[name] = nil end
    end
    return n
end

-- Pick the highest-value type from the pool that still fits the remaining budget.
local function _mixedPick(remaining)
    for _, key in ipairs(MIX_POOL) do
        if THREAT[key] <= remaining + 0.001 then return key end
    end
    return nil
end

local function _mixedSpawnOne(key)
    local zr = _zone(STATE.mixed.zone); if not zr then return end
    local ang = math.random() * 2 * math.pi
    local dir = { x = math.cos(ang), z = math.sin(ang) }
    local rad = _maxDistInZone({ x = zr.cx, z = zr.cz }, dir, zr) * (0.6 + math.random() * 0.25)
    local sx, sz = zr.cx + dir.x * rad, zr.cz + dir.z * rad
    STATE.mixed.seq = STATE.mixed.seq + 1
    local name = "AC_MIX_" .. STATE.mixed.seq
    if _spawnBandit(name, key, "bvr", sx, sz, CFG.mixedAlt, zr.cx, zr.cz) then -- towards the centre / the players
        STATE.mixed.active[name] = key
        STATE.mixed.spent = STATE.mixed.spent + THREAT[key]
    end
end

local function _mixedStop()
    local names = STATE.mixed.active
    STATE.mixed.active, STATE.mixed.outSince, STATE.mixed.spent = {}, {}, 0 -- forget first, then destroy
    for name in pairs(names) do _destroy(name) end
end

local function _mixedStart()
    local budget, n = _mixedCount()
    if n == 0 then _out("[Air Combat] Enter the mixed zone first."); return end
    _mixedStop()
    local count = 0
    while budget - STATE.mixed.spent >= 1 do
        local key = _mixedPick(budget - STATE.mixed.spent); if not key then break end
        local before = STATE.mixed.spent
        _mixedSpawnOne(key); count = count + 1
        if STATE.mixed.spent == before then break end -- spawn failed, do not loop forever
    end
    _out(string.format("[Air Combat] Mixed wave up: %d bandits for %d player(s) (%s).",
        count, n, STATE.mixed.difficulty), 12)
end

local function _mixedSetDiff(level)
    if not CFG.difficultyFactor[level] then return end
    STATE.mixed.difficulty = level
    _out("[Air Combat] Mixed difficulty: " .. level .. ".", 8)
end

-- Tick: drop the wave if the zone empties; top it up only when the budget
-- grows (more players joined), never to replace a kill.
local function _mixedTick()
    if next(STATE.mixed.active) == nil then return end
    if not _anyPlayerInZone(STATE.mixed.zone) then _mixedStop(); return end
    for name in pairs(STATE.mixed.active) do
        if _outTooLong(STATE.mixed.outSince, name, name, STATE.mixed.zone) then
            STATE.mixed.active[name], STATE.mixed.outSince[name] = nil, nil
            _destroy(name)
            _out("[Air Combat] A mixed bandit left the arena and was removed.", 8)
        end
    end
    if _mixedAlive() == 0 then -- gone without a death event (crashed, left the arena)
        STATE.mixed.spent = 0
        _out("[Air Combat] Mixed wave over.", 12)
        return
    end
    local room = _mixedCount() - STATE.mixed.spent
    if room >= 1 then
        local key = _mixedPick(room)
        if key then _mixedSpawnOne(key) end
    end
end

-- ============== Per-group menus ==============
local function _buildDuelMenu(groupId, arenaKey)
    local title = (arenaKey == "dogfight") and "Dogfight vs RED" or "BVR vs RED"
    local root = missionCommands.addSubMenuForGroup(groupId, title)
    local sp = missionCommands.addSubMenuForGroup(groupId, "Spawn bandit", root)
    for _, t in ipairs(TYPES) do
        missionCommands.addCommandForGroup(groupId, t.label, sp, function() _duelRequest(arenaKey, t.key, groupId) end)
    end
    missionCommands.addCommandForGroup(groupId, "Auto on/off",    root, function() _duelToggleAuto(arenaKey) end)
    missionCommands.addCommandForGroup(groupId, "Despawn / stop", root, function() _duelStop(arenaKey) end)
    return root
end

local function _buildMixedMenu(groupId)
    local root = missionCommands.addSubMenuForGroup(groupId, "BVR mixed (group)")
    missionCommands.addCommandForGroup(groupId, "Start wave", root, function() _mixedStart() end)
    local df = missionCommands.addSubMenuForGroup(groupId, "Difficulty", root)
    missionCommands.addCommandForGroup(groupId, "Easy", df, function() _mixedSetDiff("Easy") end)
    missionCommands.addCommandForGroup(groupId, "Even", df, function() _mixedSetDiff("Even") end)
    missionCommands.addCommandForGroup(groupId, "Hard", df, function() _mixedSetDiff("Hard") end)
    missionCommands.addCommandForGroup(groupId, "Despawn / stop", root, function() _mixedStop() end)
    return root
end

-- ============== Master tick ==============
local function _arenaFor(u)
    if _inAny(u, CFG.zones.dogfight) then return "dogfight" end
    if _inAny(u, CFG.zones.bvr) then return "bvr" end
    if _inAny(u, CFG.zones.mixed) then return "mixed" end
    return nil
end

local function _tick(_, t)
    -- Menu arming per GROUP (F10 menus belong to groups): the menu of the
    -- arena the group's players are in, built once, removed when they leave.
    local want = {} -- [groupId] = { arena, members = { [unitName] = unit } }
    for _, u in pairs(coalition.getPlayers(CFG.side) or {}) do
        if u and u:isExist() then
            local arena = _arenaFor(u)
            local g = arena and u:getGroup()
            local gid = g and g:getID()
            if gid then
                local w = want[gid]
                if not w then w = { arena = arena, members = {} }; want[gid] = w end
                w.members[u:getName()] = u
            end
        end
    end
    for gid, w in pairs(want) do
        local cur = STATE.armed[gid]
        if cur and cur.arena ~= w.arena then
            pcall(function() missionCommands.removeItemForGroup(gid, cur.menuRoot) end)
            cur = nil
        end
        if not cur then
            local root = (w.arena == "mixed") and _buildMixedMenu(gid) or _buildDuelMenu(gid, w.arena)
            cur = { menuRoot = root, arena = w.arena, members = {} }
            STATE.armed[gid] = cur
        end
        for nm, u in pairs(w.members) do
            if not cur.members[nm] then
                trigger.action.outTextForUnit(u:getID(), "[Air Combat] " .. w.arena .. " menu available (F10).", 8)
            end
        end
        cur.members = w.members
    end
    for gid, info in pairs(STATE.armed) do
        if not want[gid] then
            pcall(function() missionCommands.removeItemForGroup(gid, info.menuRoot) end)
            STATE.armed[gid] = nil
        end
    end

    -- Duel arenas: despawn on empty zone or on a bandit that left the arena,
    -- then service the queue / Auto respawn.
    for _, ak in ipairs({ "dogfight", "bvr" }) do
        local D = STATE.duel[ak]
        if D.active and Group.getByName(D.active) then
            if not _anyPlayerInZone(D.zone) then
                local name = D.active
                D.active, D.queue, D.auto, D.respawnAt, D.outSince = nil, {}, false, nil, nil
                _destroy(name)
            elseif _outTooLong(D, "outSince", D.active, D.zone) then
                local name = D.active
                D.active, D.outSince = nil, nil
                _destroy(name)
                _out("[Air Combat] The bandit left the arena and was removed.", 8)
                if D.auto then D.respawnAt = timer.getTime() + CFG.respawnDelay end
            end
        end
        _duelTrySpawn(ak)
    end

    _mixedTick()
    return t + CFG.tickSec
end

-- ============== Kill feedback ==============
-- S_EVENT_DEAD does not always come for an aircraft that is not destroyed at
-- once, so S_EVENT_UNIT_LOST counts too. Each bandit is forgotten on its
-- first event, so a kill is reported once.
local _handler = {}
function _handler:onEvent(event)
    local ok, err = pcall(function()
        if not event then return end
        local lost = world.event.S_EVENT_UNIT_LOST and event.id == world.event.S_EVENT_UNIT_LOST
        if event.id ~= world.event.S_EVENT_DEAD and not lost then return end
        local u = event.initiator
        if not u or not u.getName then return end
        local uname = u:getName()
        local gname = uname and uname:match("^(AC_[%u]+_%d+)_%d+$")
        if not gname then return end
        if STATE.duel.dogfight.active == gname then _duelOnKill("dogfight")
        elseif STATE.duel.bvr.active == gname then _duelOnKill("bvr")
        elseif STATE.mixed.active[gname] then
            STATE.mixed.active[gname] = nil
            if next(STATE.mixed.active) == nil then
                STATE.mixed.spent = 0
                _out("[Air Combat] Mixed wave cleared. Good work.", 12)
            else
                _out("[Air Combat] Splash! Bandit down.", 8)
            end
        end
    end)
    if not ok and env and env.info then env.info("[Air Combat] onEvent error: " .. tostring(err)) end
end

-- ============== Init ==============
local function _checkZones()
    local missing = {}
    for _, zn in ipairs({ CFG.zones.dogfight, CFG.zones.bvr, CFG.zones.mixed }) do
        if not _zone(zn) then missing[#missing + 1] = zn end
    end
    if #missing > 0 then
        _out("[Air Combat] MISSING ZONES: " .. table.concat(missing, ", ") .. ". Create them in the Mission Editor.", 30)
    end
end

-- The arenas on the F10 map (DCS 2.7+), read-only, for BLUE. The ids come
-- from a block of this script's own, apart from the other training scripts
-- and from the players' map marks.
local function _drawZones()
    if not (CFG.markers and trigger.action.circleToAll and trigger.action.quadToAll and trigger.action.textToAll) then return end
    local n, red = 7106000, { 1, 0.25, 0.25, 1 }
    local function v3(x, z) return { x = x, y = 0, z = z } end
    for _, a in ipairs({ { CFG.zones.dogfight, "Air combat: dogfight vs RED" }, { CFG.zones.bvr, "Air combat: BVR vs RED" },
                         { CFG.zones.mixed, "Air combat: BVR mixed group" } }) do
        local s = _zone(a[1])
        if s then
            local top = s.cx + s.r
            n = n + 1
            if s.poly and #s.poly == 4 then
                local p = s.poly
                top = math.max(p[1].x, p[2].x, p[3].x, p[4].x)
                pcall(trigger.action.quadToAll, CFG.side, n, v3(p[1].x, p[1].z), v3(p[2].x, p[2].z), v3(p[3].x, p[3].z),
                      v3(p[4].x, p[4].z), red, { 1, 0.25, 0.25, 0.06 }, 1, true, "")
            elseif not s.poly then
                pcall(trigger.action.circleToAll, CFG.side, n, v3(s.cx, s.cz), s.r, red, { 1, 0.25, 0.25, 0.06 }, 1, true, "")
            end
            n = n + 1
            pcall(trigger.action.textToAll, CFG.side, n, v3(top + 800, s.cz), red, { 0, 0, 0, 0.35 }, 12, true, a[2])
        end
    end
end

if not AIRCOMBAT_Initialized then
    AIRCOMBAT_Initialized = true
    _checkZones()
    _drawZones()
    world.addEventHandler(_handler)
    local period = math.max(1, CFG.tickSec)
    timer.scheduleFunction(function(a, time)
        local ok, e = pcall(_tick, a, time)
        if not ok and env and env.info then env.info("[Air Combat] tick error: " .. tostring(e)) end
        return time + period
    end, nil, timer.getTime() + period)
    _out("[Air Combat] Air-to-air arenas loaded (dogfight / BVR / mixed).", 10)
end
