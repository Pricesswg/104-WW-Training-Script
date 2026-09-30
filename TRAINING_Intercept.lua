-- =========================================================
--  TRAINING_Intercept.lua  (scramble intercept trainer)
--  v1.1, feature-script style, native DCS scripting engine only
-- ---------------------------------------------------------
--  Arms when a BLUE player enters INTERCEPT_PLAYER_ZONE and
--  exposes an F10 menu (only while in the zone). A scramble
--  launches a passive target after a random delay; the target
--  crosses INTERCEPT_LIMIT_ZONE toward a random objective. The
--  intercept fails if the target reaches its objective or leaves
--  the limit zone after a grace period.
--
--  REQUIRED ME ZONES (Circle or Quad):
--    INTERCEPT_PLAYER_ZONE   arming / menu area
--    INTERCEPT_LIMIT_ZONE    play box (spawn + boundary despawn)
--    INTERCEPT_OBJ_1/2/3     objectives (the target flies to the centre)
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
    spawnRadiusFactor = 0.75,  -- spawn at this fraction of the way from the centre to the zone edge
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
    armed           = {},   -- [groupId] = { menuRoot, members = { [unitName] = true } }
    scramblePending = false,
    scrambleToken   = 0,    -- bumped to invalidate a pending scramble (Abort)
    multiTrack      = false,
    targetSize      = CFG.defaultSize,
    targets         = {},   -- [groupName] = { spawnTime, obj }
    seq             = 0,
}

-- ============== Helpers ==============
local FT_TO_M = 0.3048

local function _out(msg, t) trigger.action.outText(tostring(msg), t or 10) end
local function _dbg(msg, t) if CFG.debug then _out("[Intercept][dbg] " .. tostring(msg), t or 6) end end

-- Zones, Circle or Quad. trigger.misc.getZone gives a Quad only its centre and
-- stored radius, so the drawn corners are read from env.mission ("verticies",
-- the DCS spelling; y there means world z).
local _quadCache = {}
local function _zoneShape(name)
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
                    q = { poly = poly, cx = cx / #poly, cz = cz / #poly, r = 0 }
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

local function _inShape(p, s)
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

-- Distance from p along the unit vector d to the zone edge (first exit).
local function _rayExit(p, d, s)
    if not s.poly then
        local fx, fz = p.x - s.cx, p.z - s.cz
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
            local t = ((a.x - p.x) * ez - (a.z - p.z) * ex) / den
            local u = ((a.x - p.x) * d.z - (a.z - p.z) * d.x) / den
            if t > 0 and u >= 0 and u <= 1 and (not best or t < best) then best = t end
        end
    end
    return best or 0
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
-- short delay and re-lookup by name, controller options share the post-spawn
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
    local limit = _zoneShape(CFG.limitZone)
    if not limit then _out("[Intercept] Limit zone missing, cannot spawn.", 12); return end

    -- Random objective; spawn on the OPPOSITE side so the target crosses the box.
    local objName = CFG.objectives[math.random(#CFG.objectives)]
    local obj = _zoneShape(objName)
    if not obj then _out("[Intercept] Objective zone missing: " .. objName, 12); return end

    -- DCS world: x = north, z = east; a bearing b points (cos b, sin b).
    local objBearing   = math.atan2(obj.cz - limit.cz, obj.cx - limit.cx)
    local jitter       = math.rad(math.random(-CFG.jitterDeg, CFG.jitterDeg))
    local spawnBearing = objBearing + math.pi + jitter
    local dir          = { x = math.cos(spawnBearing), z = math.sin(spawnBearing) }
    local dist         = _rayExit({ x = limit.cx, z = limit.cz }, dir, limit) * CFG.spawnRadiusFactor
    local sx           = limit.cx + dir.x * dist
    local sz           = limit.cz + dir.z * dist

    local tier  = CFG.altTiers[math.random(#CFG.altTiers)]
    local altM  = math.random(tier.lo, tier.hi) * FT_TO_M
    local preset = SIZE_PRESETS[STATE.targetSize] or SIZE_PRESETS[CFG.defaultSize]
    local hdg   = math.atan2(obj.cz - sz, obj.cx - sx) -- face the objective

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
            [2] = _airWP(obj.cx, obj.cz, altM, preset.speed),
        } },
    }

    local grp
    local ok, perr = pcall(function() grp = coalition.addGroup(CFG.enemyCountry, Group.Category.AIRPLANE, groupData) end)
    if not ok or not grp then
        _out("[Intercept] Spawn failed for " .. name .. " (check unit type string).", 12)
        if env and env.info then env.info("[Intercept] addGroup error: " .. tostring(perr)) end
        return
    end
    STATE.targets[name] = { spawnTime = timer.getTime(), obj = objName }
    _applyPassive(name)
    _out(string.format("[Intercept] Target airborne: %s, %s tier (~%d ft), heading for %s. Vector and intercept.",
        preset.label, tier.name, math.floor(altM / FT_TO_M + 0.5), objName), 12)
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

-- A target is forgotten BEFORE it is destroyed, so a despawn is never
-- reported as a kill whatever event the destroy may raise.
local function _despawn(name)
    STATE.targets[name] = nil
    local g = Group.getByName(name)
    if g then g:destroy() end
end

local function _despawnAll()
    local n = 0
    for name in pairs(STATE.targets) do
        _despawn(name)
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
    -- Arm/disarm the menu per GROUP (F10 menus belong to groups): it is built
    -- once when the first member enters the player zone and removed when the
    -- last one has left. Several clients in one group share one menu.
    local pzone = _zoneShape(CFG.playerZone)
    if pzone then
        local inside = {} -- [groupId] = { unitName = unit }
        for _, u in pairs(coalition.getPlayers(CFG.side) or {}) do
            if u and u:isExist() and _inShape(u:getPoint(), pzone) then
                local g = u:getGroup()
                local gid = g and g:getID()
                if gid then
                    inside[gid] = inside[gid] or {}
                    inside[gid][u:getName()] = u
                end
            end
        end
        for gid, members in pairs(inside) do
            local a = STATE.armed[gid]
            if not a then
                a = { menuRoot = _buildMenuForGroup(gid), members = {} }
                STATE.armed[gid] = a
            end
            for nm, u in pairs(members) do
                if not a.members[nm] then
                    trigger.action.outTextForUnit(u:getID(), "[Intercept] Scramble control available, F10 radio menu.", 10)
                end
            end
            a.members = members
        end
        for gid, a in pairs(STATE.armed) do
            if not inside[gid] then
                pcall(function() missionCommands.removeItemForGroup(gid, a.menuRoot) end)
                STATE.armed[gid] = nil
            end
        end
    end

    -- Failure: the target reached its objective, or left the limit zone after
    -- the grace period.
    local lzone = _zoneShape(CFG.limitZone)
    local now = timer.getTime()
    for name, info in pairs(STATE.targets) do
        local g = Group.getByName(name)
        local u = g and g:getUnits()[1]
        if not u then
            STATE.targets[name] = nil -- killed or already gone
        else
            local p = u:getPoint()
            local utype = (u.getTypeName and u:getTypeName()) or "target"
            if _inShape(p, _zoneShape(info.obj)) then
                _despawn(name)
                _out("[Intercept] " .. utype .. " reached " .. info.obj .. ". Intercept failed.", 12)
            elseif lzone and (now - info.spawnTime) > CFG.graceSec and not _inShape(p, lzone) then
                _despawn(name)
                _out("[Intercept] " .. utype .. " reached the boundary and escaped. Intercept failed.", 12)
            end
        end
    end

    return t + CFG.tickSec
end

-- ============== Splash feedback (real kills only) ==============
-- S_EVENT_DEAD does not always come for an aircraft that is not destroyed at
-- once, so S_EVENT_UNIT_LOST counts too. The target entry is removed on the
-- first event, so a kill is announced once; despawns clear it beforehand.
local _handler = {}
function _handler:onEvent(event)
    local ok, err = pcall(function()
        if not event then return end
        local lost = world.event.S_EVENT_UNIT_LOST and event.id == world.event.S_EVENT_UNIT_LOST
        if event.id ~= world.event.S_EVENT_DEAD and not lost then return end
        local u = event.initiator
        if not u or not u.getName then return end
        local uname = u:getName()
        local gname = uname and uname:match("^(INT_TGT_%d+)_%d+$")
        if not gname or not STATE.targets[gname] then return end
        STATE.targets[gname] = nil
        local okt, utype = pcall(function() return u:getTypeName() end)
        _out("[Intercept] Splash! " .. ((okt and utype) or "target") .. " down. Intercept successful.", 12)
    end)
    if not ok and env and env.info then env.info("[Intercept] onEvent error: " .. tostring(err)) end
end

-- ============== Init ==============
local function _checkZones()
    local missing = {}
    local required = { CFG.playerZone, CFG.limitZone }
    for _, z in ipairs(CFG.objectives) do required[#required + 1] = z end
    for _, zn in ipairs(required) do
        if not _zoneShape(zn) then missing[#missing + 1] = zn end
    end
    if #missing > 0 then
        _out("[Intercept] MISSING ZONES: " .. table.concat(missing, ", ") .. ". Create them in the Mission Editor.", 30)
    end
    return #missing == 0
end

if not INTERCEPT_Initialized then
    INTERCEPT_Initialized = true
    _checkZones() -- visible error if any are missing; the tick no-ops safely meanwhile
    world.addEventHandler(_handler)
    local period = math.max(1, CFG.tickSec)
    timer.scheduleFunction(function(a, time) local ok, e = pcall(_tick, a, time)
        if not ok and env and env.info then env.info("[Intercept] tick error: " .. tostring(e)) end
        return time + period
    end, nil, timer.getTime() + period)
    _out("[Intercept] Scramble intercept trainer loaded.", 10)
end
