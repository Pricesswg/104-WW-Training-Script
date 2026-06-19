-- =========================================================
--  TRAINING_AirCombat.lua  (air-to-air arenas vs RED)
--  v1.0, feature-script style, native DCS scripting engine only
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
--  zone despawns the live bandit(s).
--
--  REQUIRED ME ZONES (type: Circle):
--    TR_DOGFIGHT_RED, TR_BVR_RED, TR_BVR_MIXED
--
--  LOADOUTS: empty by default = guns only (the dogfight is fully playable on
--  guns). To arm the bandits, fill LOADOUTS below with the weapon CLSIDs from
--  YOUR DCS version (the GUIDs are version-specific, so they are not hardcoded).
--  Bad loadouts fall back to guns automatically, so a wrong CLSID never breaks
--  a spawn.
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
    zones = {
        dogfight = "TR_DOGFIGHT_RED",
        bvr      = "TR_BVR_RED",
        mixed    = "TR_BVR_MIXED",
    },
    difficultyFactor  = { Easy = 1.5, Even = 2.0, Hard = 2.5 }, -- budget = players x factor
    defaultDifficulty = "Even",
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
    armed = {}, -- [unitName] = { groupId, menuRoot, arena }
    duel = {
        dogfight = { zone = CFG.zones.dogfight, mode = "wvr", active = nil, queue = {}, auto = false, lastType = nil, lastReq = nil, respawnAt = nil, seq = 0 },
        bvr      = { zone = CFG.zones.bvr,      mode = "bvr", active = nil, queue = {}, auto = false, lastType = nil, lastReq = nil, respawnAt = nil, seq = 0 },
    },
    mixed = { zone = CFG.zones.mixed, active = {}, difficulty = CFG.defaultDifficulty, seq = 0 },
}

-- ============== Helpers ==============
local function _out(msg, t) trigger.action.outText(tostring(msg), t or 10) end
local function _dbg(msg, t) if CFG.debug then _out("[Air Combat][dbg] " .. tostring(msg), t or 6) end end

local function _zone(name)
    local z = trigger.misc.getZone(name)
    if z then return { cx = z.point.x, cz = z.point.z, r = z.radius } end
    return nil
end

local function _inZoneXZ(p, zr)
    if not zr then return false end
    local dx, dz = p.x - zr.cx, p.z - zr.cz
    return (dx * dx + dz * dz) <= (zr.r * zr.r)
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

-- Largest t with P + t*d inside the circle zone (ray/circle intersection).
local function _maxDistInZone(P, d, zr)
    local fx, fz = P.x - zr.cx, P.z - zr.cz
    local b = fx * d.x + fz * d.z
    local disc = b * b - (fx * fx + fz * fz - zr.r * zr.r)
    if disc < 0 then return 0 end
    return math.max(0, -b + math.sqrt(disc))
end

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

local function _banditGroupData(name, typeStr, sx, sz, alt, hdg, payload)
    local wp = {
        ["x"] = sx, ["y"] = sz, ["alt"] = alt, ["alt_type"] = "BARO",
        ["type"] = "Turning Point", ["action"] = "Turning Point", ["speed"] = CFG.spawnSpeed,
        ["task"] = { id = "ComboTask", params = { tasks = {
            [1] = { id = "EngageTargets", params = { targetTypes = { "Air" }, priority = 0 } },
        } } },
    }
    return {
        ["name"] = name, ["task"] = "CAP", ["uncontrolled"] = false, ["start_time"] = 0,
        ["units"] = { [1] = {
            ["type"] = typeStr, ["name"] = name .. "_1",
            ["x"] = sx, ["y"] = sz, ["alt"] = alt, ["alt_type"] = "BARO",
            ["speed"] = CFG.spawnSpeed, ["heading"] = hdg, ["skill"] = "High",
            ["payload"] = payload,
        } },
        ["route"] = { ["points"] = { [1] = wp } },
    }
end

-- Spawn one RED bandit; on a loadout failure, retry guns-only. Returns name or nil.
local function _spawnBandit(name, typeKey, mode, sx, sz, alt, hdg)
    local ty = TYPE_BY_KEY[typeKey]; if not ty then return nil end
    local grp
    local ok = pcall(function()
        grp = coalition.addGroup(CFG.enemyCountry, Group.Category.AIRPLANE,
            _banditGroupData(name, ty.type, sx, sz, alt, hdg, _buildPayload(typeKey, mode)))
    end)
    if (not ok or not grp) and not CFG.gunsOnly then
        pcall(function()
            grp = coalition.addGroup(CFG.enemyCountry, Group.Category.AIRPLANE,
                _banditGroupData(name, ty.type, sx, sz, alt, hdg, _gunsPayload()))
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

-- ============== Duel arenas (dogfight / BVR) ==============
local function _duelSpawnInFront(arenaKey, typeKey, u)
    local D = STATE.duel[arenaKey]
    local zr = _zone(D.zone); if not zr then return nil end
    local P = u:getPoint()
    local d = _playerForward(u)
    local t = math.max(2000, _maxDistInZone({ x = P.x, z = P.z }, d, zr) - 1000) -- just inside the edge
    local sx, sz = P.x + d.x * t, P.z + d.z * t
    local alt = math.max(300, P.y)                  -- same altitude as the player
    local hdg = _headingTo(sx, sz, P.x, P.z)        -- face the player
    D.seq = D.seq + 1
    local name = "AC_" .. string.upper(arenaKey) .. "_" .. D.seq
    return _spawnBandit(name, typeKey, D.mode, sx, sz, alt, hdg)
end

local function _duelTrySpawn(arenaKey)
    local D = STATE.duel[arenaKey]
    if D.active and Group.getByName(D.active) then return end -- one at a time
    D.active = nil
    if D.respawnAt then
        if timer.getTime() < D.respawnAt then return end       -- waiting on the Auto delay
        D.respawnAt = nil
        if D.auto and D.lastType then D.queue[#D.queue + 1] = { key = D.lastType, req = D.lastReq } end
    end
    if #D.queue == 0 then return end
    local item = D.queue[1]
    local u = (item.req and Unit.getByName(item.req)) or nil
    if not (u and u:isExist() and _inAny(u, D.zone)) then u = _anyPlayerInZone(D.zone) end
    if not u then return end                                    -- no one in the zone yet, keep queued
    table.remove(D.queue, 1)
    local name = _duelSpawnInFront(arenaKey, item.key, u)
    if name then
        D.active, D.lastType, D.lastReq = name, item.key, item.req
        local ty = TYPE_BY_KEY[item.key]
        _out("[Air Combat] " .. (arenaKey == "dogfight" and "Dogfight" or "BVR") .. " bandit airborne: " .. ty.label .. ".", 10)
    end
end

local function _duelRequest(arenaKey, typeKey, requester)
    local D = STATE.duel[arenaKey]
    D.queue[#D.queue + 1] = { key = typeKey, req = requester }
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
    D.auto, D.respawnAt, D.queue = false, nil, {}
    if D.active then _destroy(D.active); D.active = nil end
    _out("[Air Combat] " .. (arenaKey == "dogfight" and "Dogfight" or "BVR") .. " cleared.", 8)
end

local function _duelOnKill(arenaKey)
    local D = STATE.duel[arenaKey]
    D.active = nil
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

local function _mixedThreat()
    local s = 0
    for name, key in pairs(STATE.mixed.active) do
        if Group.getByName(name) then s = s + (THREAT[key] or 1) else STATE.mixed.active[name] = nil end
    end
    return s
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
    local rad = zr.r * (0.6 + math.random() * 0.25)
    local sx, sz = zr.cx + math.cos(ang) * rad, zr.cz + math.sin(ang) * rad
    local hdg = _headingTo(sx, sz, zr.cx, zr.cz) -- face the centre / the players
    STATE.mixed.seq = STATE.mixed.seq + 1
    local name = "AC_MIX_" .. STATE.mixed.seq
    if _spawnBandit(name, key, "bvr", sx, sz, CFG.mixedAlt, hdg) then
        STATE.mixed.active[name] = key
    end
end

local function _mixedStop()
    for name in pairs(STATE.mixed.active) do _destroy(name) end
    STATE.mixed.active = {}
end

local function _mixedStart()
    local budget, n = _mixedCount()
    if n == 0 then _out("[Air Combat] Enter the mixed zone first."); return end
    _mixedStop()
    local remaining, count = budget, 0
    while remaining >= 1 do
        local key = _mixedPick(remaining); if not key then break end
        _mixedSpawnOne(key); remaining = remaining - THREAT[key]; count = count + 1
    end
    _out(string.format("[Air Combat] Mixed wave up: %d bandits for %d player(s) (%s).",
        count, n, STATE.mixed.difficulty), 12)
end

local function _mixedSetDiff(level)
    if not CFG.difficultyFactor[level] then return end
    STATE.mixed.difficulty = level
    _out("[Air Combat] Mixed difficulty: " .. level .. ".", 8)
end

-- Tick: drop the wave if the zone empties, otherwise top up toward the budget
-- (so it scales up when more players join). It does not shrink mid-fight.
local function _mixedTick()
    if next(STATE.mixed.active) == nil then return end
    if not _anyPlayerInZone(STATE.mixed.zone) then _mixedStop(); return end
    local budget = _mixedCount()
    local room = budget - _mixedThreat()
    if room >= 1 then
        local key = _mixedPick(room)
        if key then _mixedSpawnOne(key) end
    end
end

-- ============== Per-group menus ==============
local function _buildDuelMenu(groupId, arenaKey, requester)
    local title = (arenaKey == "dogfight") and "Dogfight vs RED" or "BVR vs RED"
    local root = missionCommands.addSubMenuForGroup(groupId, title)
    local sp = missionCommands.addSubMenuForGroup(groupId, "Spawn bandit", root)
    for _, t in ipairs(TYPES) do
        missionCommands.addCommandForGroup(groupId, t.label, sp, function() _duelRequest(arenaKey, t.key, requester) end)
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
    -- Menu arming: give each player the menu for the arena zone they are in.
    local seen = {}
    for _, u in pairs(coalition.getPlayers(CFG.side) or {}) do
        if u and u:isExist() then
            local nm = u:getName()
            local arena = _arenaFor(u)
            if arena then
                seen[nm] = true
                local cur = STATE.armed[nm]
                if not cur or cur.arena ~= arena then
                    if cur then pcall(function() missionCommands.removeItemForGroup(cur.groupId, cur.menuRoot) end) end
                    local g = u:getGroup()
                    local gid = g and g:getID()
                    if gid then
                        local root = (arena == "mixed") and _buildMixedMenu(gid) or _buildDuelMenu(gid, arena, nm)
                        STATE.armed[nm] = { groupId = gid, menuRoot = root, arena = arena }
                        trigger.action.outTextForUnit(u:getID(), "[Air Combat] " .. arena .. " menu available (F10).", 8)
                    end
                end
            end
        end
    end
    for nm, info in pairs(STATE.armed) do
        if not seen[nm] then
            pcall(function() missionCommands.removeItemForGroup(info.groupId, info.menuRoot) end)
            STATE.armed[nm] = nil
        end
    end

    -- Duel arenas: despawn on empty zone, then service the queue / Auto respawn.
    for _, ak in ipairs({ "dogfight", "bvr" }) do
        local D = STATE.duel[ak]
        if D.active and Group.getByName(D.active) and not _anyPlayerInZone(D.zone) then
            _destroy(D.active); D.active, D.queue, D.auto, D.respawnAt = nil, {}, false, nil
        end
        _duelTrySpawn(ak)
    end

    _mixedTick()
    return t + CFG.tickSec
end

-- ============== Kill feedback ==============
local _handler = {}
function _handler:onEvent(event)
    local ok, err = pcall(function()
        if not event or event.id ~= world.event.S_EVENT_DEAD then return end
        local u = event.initiator
        if not u or not u.getGroup then return end
        local g = u:getGroup()
        local gname = g and g:getName()
        if not gname then return end
        if STATE.duel.dogfight.active == gname then _duelOnKill("dogfight")
        elseif STATE.duel.bvr.active == gname then _duelOnKill("bvr")
        elseif STATE.mixed.active[gname] then
            STATE.mixed.active[gname] = nil
            if next(STATE.mixed.active) == nil then _out("[Air Combat] Mixed wave cleared. Good work.", 12)
            else _out("[Air Combat] Splash! Bandit down.", 8) end
        end
    end)
    if not ok and env and env.info then env.info("[Air Combat] onEvent error: " .. tostring(err)) end
end

-- ============== Init ==============
local function _checkZones()
    local missing = {}
    for _, zn in ipairs({ CFG.zones.dogfight, CFG.zones.bvr, CFG.zones.mixed }) do
        if not trigger.misc.getZone(zn) then missing[#missing + 1] = zn end
    end
    if #missing > 0 then
        _out("[Air Combat] MISSING ZONES: " .. table.concat(missing, ", ") .. ". Create them in the Mission Editor.", 30)
    end
end

if not AIRCOMBAT_Initialized then
    AIRCOMBAT_Initialized = true
    pcall(function() math.randomseed(os.time()) end)
    _checkZones()
    world.addEventHandler(_handler)
    local period = math.max(1, CFG.tickSec)
    timer.scheduleFunction(function(a, time)
        local ok, e = pcall(_tick, a, time)
        if not ok and env and env.info then env.info("[Air Combat] tick error: " .. tostring(e)) end
        return time + period
    end, nil, timer.getTime() + period)
    _out("[Air Combat] Air-to-air arenas loaded (dogfight / BVR / mixed).", 10)
end
