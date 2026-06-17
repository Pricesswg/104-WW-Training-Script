-- =========================================================
--  TRAINING_Intercept.lua — Scramble intercept trainer
--  v1.0 — feature-script style, native DCS scripting engine only
-- ---------------------------------------------------------
--  Arms when a BLUE player enters INTERCEPT_PLAYER_ZONE and
--  exposes an F10 menu (only while in the zone). A scramble
--  launches a passive target after a random delay; the target
--  transits INTERCEPT_LIMIT_ZONE toward a random objective and
--  despawns if it leaves the limit zone after a grace period.
--
--  REQUIRED ME ZONES (type: Circle):
--    INTERCEPT_PLAYER_ZONE   arming / menu area
--    INTERCEPT_LIMIT_ZONE    play box (spawn + boundary despawn)
--    INTERCEPT_OBJ_1/2/3     objective waypoints (zone centre)
--
--  Comments and in-game text in English (published on GitHub).
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
        trigger.action.outText("[Intercept] Required DCS API missing. Script aborted.", 20)
    end
    return
end

-- ============== Config ==============
local CFG = {
    debug             = false,
    playerZone        = "INTERCEPT_PLAYER_ZONE",
    limitZone         = "INTERCEPT_LIMIT_ZONE",
    objectives        = { "INTERCEPT_OBJ_1", "INTERCEPT_OBJ_2", "INTERCEPT_OBJ_3" },
    scrambleMin       = 60,    -- random scramble delay, seconds
    scrambleMax       = 180,
    spawnRadiusFactor = 0.75,  -- spawn at radius * this from the limit-zone centre
    jitterDeg         = 30,    -- +/- angular jitter on the spawn bearing
    graceSec          = 30,    -- boundary despawn inactive for this long after spawn
    tickSec           = 2,     -- master loop period (do not go below 1)
    enemyCountry      = country.id.RUSSIA, -- targets are RED so they oppose BLUE
    side              = coalition.side.BLUE,
    defaultSize       = "Medium",
    -- altitude tiers in FEET (converted to metres at spawn)
    altTiers = {
        { name = "LOW",  lo = 2000,  hi = 5000  },
        { name = "MED",  lo = 6000,  hi = 20000 },
        { name = "HIGH", lo = 25000, hi = 30000 },
    },
}

-- Target size presets. speed in m/s; fuel kept under each type's internal max
-- so nothing spawns over-fuelled. Payload is empty (ROE is WEAPON HOLD anyway).
local SIZE_PRESETS = {
    Small  = { type = "L-39C",   speed = 160, fuel = "980",   label = "Small (L-39C)" },
    Medium = { type = "MiG-29S", speed = 270, fuel = "3500",  label = "Medium (MiG-29S)" },
    Large  = { type = "Tu-95MS", speed = 210, fuel = "40000", label = "Large (Tu-95MS)" },
}

-- ============== State (file-local) ==============
local STATE = {
    armed           = {},   -- [unitName] = { groupId, menuRoot }
    scramblePending = false,
    scrambleToken   = 0,    -- bumped to invalidate a pending scramble (Abort)
    multiTrack      = false,
    targetSize      = CFG.defaultSize,
    targets         = {},   -- [groupName] = { spawnTime }
    seq             = 0,
}

-- ============== Helpers ==============
local FT_TO_M = 0.3048

local function _out(msg, t) trigger.action.outText(tostring(msg), t or 10) end
local function _dbg(msg, t) if CFG.debug then _out("[Intercept][dbg] " .. tostring(msg), t or 6) end end

local function _inZone(point, zone)
    local dx, dz = point.x - zone.point.x, point.z - zone.point.z
    return (dx * dx + dz * dz) <= (zone.radius * zone.radius)
end

-- ============== Spawn ==============
-- Air waypoint. x/y are the two horizontal axes (y = world z); alt is vertical.
local function _airWP(x, z, altM, speed)
    return {
        ["x"] = x, ["y"] = z, ["alt"] = altM, ["alt_type"] = "BARO",
        ["type"] = "Turning Point", ["action"] = "Turning Point",
        ["speed"] = speed, ["ETA"] = 0, ["ETA_locked"] = false, ["speed_locked"] = true,
        ["task"] = { id = "ComboTask", params = { tasks = {} } },
    }
end

-- Targets must stay passive: WEAPON HOLD, radar NEVER, NO REACTION. Apply on a
-- short delay and re-lookup by name — controller options share the post-spawn
-- binding race that bites setTask.
local function _applyPassive(name)
    timer.scheduleFunction(function()
        local g = Group.getByName(name)
        if not g then return nil end
        local c = g:getController()
        pcall(function() c:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_HOLD) end)
        pcall(function() c:setOption(AI.Option.Air.id.RADAR_USING, AI.Option.Air.val.RADAR_USING.NEVER) end)
        pcall(function() c:setOption(AI.Option.Air.id.REACTION_ON_THREAT, AI.Option.Air.val.REACTION_ON_THREAT.NO_REACTION) end)
        return nil
    end, nil, timer.getTime() + 1.0)
end

local function _spawnTarget()
    local limit = trigger.misc.getZone(CFG.limitZone)
    if not limit then _out("[Intercept] Limit zone missing — cannot spawn.", 12); return end

    -- Random objective; spawn on the OPPOSITE bearing so the target transits the box.
    local objName = CFG.objectives[math.random(#CFG.objectives)]
    local obj = trigger.misc.getZone(objName)
    if not obj then _out("[Intercept] Objective zone missing: " .. objName, 12); return end

    local objBearing  = math.atan2(obj.point.x - limit.point.x, obj.point.z - limit.point.z)
    local jitter      = math.rad(math.random(-CFG.jitterDeg, CFG.jitterDeg))
    local spawnBearing = objBearing + math.pi + jitter
    local dist        = limit.radius * CFG.spawnRadiusFactor
    local sx          = limit.point.x + math.sin(spawnBearing) * dist
    local sz          = limit.point.z + math.cos(spawnBearing) * dist

    local tier  = CFG.altTiers[math.random(#CFG.altTiers)]
    local altM  = math.random(tier.lo, tier.hi) * FT_TO_M
    local preset = SIZE_PRESETS[STATE.targetSize] or SIZE_PRESETS[CFG.defaultSize]
    local hdg   = math.atan2(obj.point.x - sx, obj.point.z - sz) -- face the objective

    STATE.seq = STATE.seq + 1
    local name = "INT_TGT_" .. STATE.seq
    local groupData = {
        ["name"] = name, ["task"] = "Nothing", ["uncontrolled"] = false, ["start_time"] = 0,
        ["units"] = { [1] = {
            ["type"] = preset.type, ["name"] = name .. "_1",
            ["x"] = sx, ["y"] = sz, ["alt"] = altM, ["alt_type"] = "BARO",
            ["speed"] = preset.speed, ["heading"] = hdg, ["skill"] = "High",
            ["payload"] = { ["pylons"] = {}, ["fuel"] = preset.fuel, ["flare"] = 0, ["chaff"] = 0, ["gun"] = 0 },
        } },
        ["route"] = { ["points"] = {
            [1] = _airWP(sx, sz, altM, preset.speed),
            [2] = _airWP(obj.point.x, obj.point.z, altM, preset.speed),
        } },
    }

    local grp
    local ok, perr = pcall(function() grp = coalition.addGroup(CFG.enemyCountry, Group.Category.AIRPLANE, groupData) end)
    if not ok or not grp then
        _out("[Intercept] Spawn failed for " .. name .. " (check unit type string).", 12)
        if env and env.info then env.info("[Intercept] addGroup error: " .. tostring(perr)) end
        return
    end
    STATE.targets[name] = { spawnTime = timer.getTime() }
    _applyPassive(name)
    _out(string.format("[Intercept] Target airborne: %s, %s tier (~%d ft). Vector and intercept.",
        preset.label, tier.name, math.floor(altM / FT_TO_M + 0.5)), 12)
end

-- ============== Menu actions ==============
local function _scramble()
    if STATE.scramblePending then _out("[Intercept] Scramble already in progress.", 8); return end
    STATE.scramblePending = true
    STATE.scrambleToken   = STATE.scrambleToken + 1
    local token = STATE.scrambleToken
    local delay = math.random(CFG.scrambleMin, CFG.scrambleMax)
    _out("[Intercept] Scramble order acknowledged. Target inbound in ~" .. delay .. "s.", 10)
    timer.scheduleFunction(function()
        if token ~= STATE.scrambleToken then return nil end -- aborted while pending
        STATE.scramblePending = false
        local n = STATE.multiTrack and 2 or 1
        for _ = 1, n do _spawnTarget() end
        return nil
    end, nil, timer.getTime() + delay)
end

local function _abort()
    if not STATE.scramblePending then _out("[Intercept] No pending scramble to abort.", 8); return end
    STATE.scrambleToken = STATE.scrambleToken + 1 -- invalidate the queued spawn
    STATE.scramblePending = false
    _out("[Intercept] Scramble aborted.", 8)
end

local function _toggleMulti()
    STATE.multiTrack = not STATE.multiTrack
    _out("[Intercept] Multi-track " .. (STATE.multiTrack and "ON (2 targets per scramble)." or "OFF (1 target per scramble)."), 8)
end

local function _setSize(size)
    if not SIZE_PRESETS[size] then return end
    STATE.targetSize = size
    _out("[Intercept] Target size set to " .. SIZE_PRESETS[size].label .. ".", 8)
end

local function _despawnAll()
    local n = 0
    for name in pairs(STATE.targets) do
        local g = Group.getByName(name)
        if g then g:destroy() end
        STATE.targets[name] = nil
        n = n + 1
    end
    _out("[Intercept] Despawned " .. n .. " target(s).", 8)
end

-- ============== Per-group F10 menu (only while in the player zone) ==============
local function _buildMenuForGroup(groupId)
    local root = missionCommands.addSubMenuForGroup(groupId, "Intercept")
    missionCommands.addCommandForGroup(groupId, "Scramble",           root, function() _scramble() end)
    missionCommands.addCommandForGroup(groupId, "Abort",              root, function() _abort() end)
    missionCommands.addCommandForGroup(groupId, "Toggle multi-track", root, function() _toggleMulti() end)
    local mz = missionCommands.addSubMenuForGroup(groupId, "Target size", root)
    missionCommands.addCommandForGroup(groupId, "Small (L-39C)",    mz, function() _setSize("Small") end)
    missionCommands.addCommandForGroup(groupId, "Medium (MiG-29S)", mz, function() _setSize("Medium") end)
    missionCommands.addCommandForGroup(groupId, "Large (Tu-95MS)",  mz, function() _setSize("Large") end)
    missionCommands.addCommandForGroup(groupId, "Despawn all",        root, function() _despawnAll() end)
    return root
end

-- ============== Master tick: menu arming + boundary despawn ==============
local function _tick(_, t)
    -- Arm/disarm the per-group menu based on presence in the player zone.
    local pzone = trigger.misc.getZone(CFG.playerZone)
    if pzone then
        local players = coalition.getPlayers(CFG.side) or {}
        local seen = {}
        for _, u in pairs(players) do
            if u and u:isExist() then
                local nm = u:getName()
                if _inZone(u:getPoint(), pzone) then
                    seen[nm] = true
                    if not STATE.armed[nm] then
                        local g = u:getGroup()
                        local gid = g and g:getID()
                        if gid then
                            STATE.armed[nm] = { groupId = gid, menuRoot = _buildMenuForGroup(gid) }
                            trigger.action.outTextForUnit(u:getID(), "[Intercept] Scramble control available — F10 radio menu.", 10)
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
    end

    -- Boundary despawn: drop targets that left the limit zone after the grace period.
    local lzone = trigger.misc.getZone(CFG.limitZone)
    if lzone then
        local now = timer.getTime()
        for name, info in pairs(STATE.targets) do
            local g = Group.getByName(name)
            if not g then
                STATE.targets[name] = nil -- killed or already gone
            else
                local us = g:getUnits()
                local u  = us and us[1]
                if u and (now - info.spawnTime) > CFG.graceSec and not _inZone(u:getPoint(), lzone) then
                    g:destroy()
                    STATE.targets[name] = nil
                    _out("[Intercept] Target left the area — despawned.", 8)
                end
            end
        end
    end

    return t + CFG.tickSec
end

-- ============== Splash feedback (real kills only) ==============
-- Only weapon kills fire S_EVENT_DEAD; destroy() (boundary despawn / Despawn
-- all) does not, so "Splash" is never announced for a despawn.
local _handler = {}
function _handler:onEvent(event)
    local ok, err = pcall(function()
        if not event or event.id ~= world.event.S_EVENT_DEAD then return end
        local u = event.initiator
        if not u or not u.getGroup then return end -- StaticObjects have no getGroup
        local g = u:getGroup()
        local gname = g and g:getName()
        if not gname or not STATE.targets[gname] then return end
        STATE.targets[gname] = nil
        local utype = (u.getTypeName and u:getTypeName()) or "target"
        _out("[Intercept] Splash! " .. utype .. " down.", 10)
    end)
    if not ok and env and env.info then env.info("[Intercept] onEvent error: " .. tostring(err)) end
end

-- ============== Init ==============
local function _checkZones()
    local missing = {}
    local required = { CFG.playerZone, CFG.limitZone }
    for _, z in ipairs(CFG.objectives) do required[#required + 1] = z end
    for _, zn in ipairs(required) do
        if not trigger.misc.getZone(zn) then missing[#missing + 1] = zn end
    end
    if #missing > 0 then
        _out("[Intercept] MISSING ZONES: " .. table.concat(missing, ", ") .. ". Create them in the Mission Editor.", 30)
    end
    return #missing == 0
end

if not INTERCEPT_Initialized then
    INTERCEPT_Initialized = true
    pcall(function() math.randomseed(os.time()) end)
    _checkZones() -- visible error if any are missing; the tick no-ops safely meanwhile
    world.addEventHandler(_handler)
    local period = math.max(1, CFG.tickSec)
    timer.scheduleFunction(function(a, time) local ok, e = pcall(_tick, a, time)
        if not ok and env and env.info then env.info("[Intercept] tick error: " .. tostring(e)) end
        return time + period
    end, nil, timer.getTime() + period)
    _out("[Intercept] Scramble intercept trainer loaded.", 10)
end
