-- =========================================================
--  JTAC.lua  (invisible JTAC / UAV spotter, autolase)
--  v2.1, feature-script style, native DCS scripting engine only
-- ---------------------------------------------------------
--  Standalone (usable in any mission, not just the training range). From an F10
--  menu you call up a friendly (BLUE) spotter and it is made invisible to enemy
--  AI (SetInvisible), so it can sit and lase RED targets without being shot.
--    UAV spotter : an MQ-9 Reaper orbiting the JTAC zone (best line of sight).
--    Ground JTAC : a vehicle at the zone centre (needs clear line of sight).
--
--  The lasing is driven by the script with Spot.createLaser, so the LASER CODE
--  can be ANY value and changed live from the menu (the native autonomous FAC
--  is stuck on 1688, which is why we do it ourselves). The spotter keeps the
--  same target until it is destroyed, hidden or out of range, so a guided bomb
--  in flight does not lose its spot to a nearer vehicle.
--  The spotter's RADIO FREQUENCY is set on the unit and shown on the comms
--  card; the spotter itself does not talk (its calls are the text messages).
--
--  REQUIRED ME ZONES (Circle or Quad, create whichever one(s) you use):
--    JTAC_GROUND_ZONE  the ground JTAC sits at its centre (needs line of sight)
--    JTAC_UAV_ZONE     the UAV orbits its centre
-- =========================================================

-- ============== Fail-fast API guard ==============
if not (trigger and trigger.action and trigger.action.outText
        and coalition and coalition.addGroup and coalition.getGroups
        and timer and timer.scheduleFunction
        and missionCommands and missionCommands.addSubMenuForCoalition and missionCommands.addCommandForCoalition
        and trigger.misc and trigger.misc.getZone and land and land.isVisible) then
    if trigger and trigger.action and trigger.action.outText then
        trigger.action.outText("[JTAC] Required DCS API missing. Script aborted.", 20)
    end
    return
end

-- ============== Config ==============
local CFG = {
    debug           = false,
    side            = coalition.side.BLUE, -- the spotter's coalition: it gets the menu and the messages
    friendlyCountry = country.id.USA,      -- the spotter is BLUE
    enemySide       = coalition.side.RED,  -- it lases targets of this side
    groundZone      = "JTAC_GROUND_ZONE",  -- ME zone: the ground JTAC sits at its centre
    uavZone         = "JTAC_UAV_ZONE",     -- ME zone: the UAV orbits its centre
    groundType      = "Hummer",            -- ground JTAC vehicle (exact DCS type)
    uavType         = "MQ-9 Reaper",       -- airborne spotter (exact DCS type)
    uavAlt          = 6000,                -- UAV orbit altitude (m)
    uavSpeed        = 120,                 -- UAV orbit speed (m/s)
    maxRange        = 15000,               -- only lase targets within this range (m, ~8 nm)
    tickSec         = 1,                   -- lase update period
    laserCode       = 1688,                -- default laser code
    freq            = 262.0,               -- default radio frequency (MHz); clear of the range tankers (251-253)
    modulation      = 0,                   -- 0 = AM, 1 = FM
    -- Menu presets:
    codePresets = { 1688, 1511, 1234, 1111 },
    freqPresets = {
        { f = 262.0, m = 0, label = "262.0 AM" },
        { f = 263.0, m = 0, label = "263.0 AM" },
        { f = 30.0,  m = 1, label = "30.0 FM" },
        { f = 31.0,  m = 1, label = "31.0 FM" },
    },
}

-- ============== State ==============
local STATE = {
    active = nil, kind = nil,            -- group name + "uav"/"ground"
    laserCode = CFG.laserCode,
    freq = CFG.freq, modulation = CFG.modulation,
    spot = nil, spotTarget = nil,        -- active laser Spot + the unit name it is on
}

local GROUP_NAME = "JTAC_UNIT"

-- Shared with the other training scripts: TRAINING_Comms.lua prints it.
TRAINING_COMMS = TRAINING_COMMS or { assets = {} }

-- ============== Helpers ==============
local function _out(msg, t) trigger.action.outTextForCoalition(CFG.side, tostring(msg), t or 10) end
local function _dbg(msg, t) if CFG.debug then _out("[JTAC][dbg] " .. tostring(msg), t or 6) end end
local function _modName(m) return ((m or STATE.modulation) == 1) and "FM" or "AM" end

local function _zone(name)
    local z = trigger.misc.getZone(name) -- centre only: right for a Circle and for a Quad
    if z then return { cx = z.point.x, cz = z.point.z, r = z.radius } end
    _out("[JTAC] Zone not found: " .. tostring(name), 15)
    return nil
end

local function _register()
    if not STATE.active then TRAINING_COMMS.assets["JTAC"] = nil; return end
    TRAINING_COMMS.assets["JTAC"] = {
        side = CFG.side, order = 30, group = STATE.active,
        title = (STATE.kind == "uav") and ("JTAC UAV (" .. CFG.uavType .. ")") or ("JTAC ground (" .. CFG.groundType .. ")"),
        radio = { mhz = STATE.freq, mod = STATE.modulation },
        laser = STATE.laserCode,
        note = STATE.spotTarget and ("lasing " .. STATE.spotTarget) or "searching",
    }
end

local function _destroySpot()
    if STATE.spot then pcall(function() STATE.spot:destroy() end); STATE.spot = nil end
    STATE.spotTarget = nil
end

local function _removeActive()
    _destroySpot()
    if STATE.active then
        local g = Group.getByName(STATE.active)
        STATE.active, STATE.kind = nil, nil
        if g then g:destroy() end
    end
    _register()
end

-- Invisible to enemy AI, applied on the post-spawn delay (controller commands
-- share the bind race), re-looked-up by name.
local function _applyInvisible(name)
    timer.scheduleFunction(function()
        local g = Group.getByName(name); if not g then return nil end
        pcall(function() g:getController():setCommand({ id = "SetInvisible", params = { value = true } }) end)
        return nil
    end, nil, timer.getTime() + 1.0)
end

-- Set the unit radio frequency at runtime (shown on the comms card).
local function _applyFreq(name)
    local g = name and Group.getByName(name); if not g then return end
    pcall(function()
        g:getController():setCommand({ id = "SetFrequency",
            params = { frequency = STATE.freq * 1000000, modulation = STATE.modulation, power = 10 } })
    end)
end

local function _announce(label)
    _out(string.format("[JTAC] %s active | Freq %.1f %s | Laser code %d.",
        label, STATE.freq, _modName(), STATE.laserCode), 15)
end

-- ============== Target selection + lasing ==============
local function _aimOf(u)
    local p = u:getPoint()
    return { x = p.x, y = p.y + 2, z = p.z }
end

-- Can the spotter still lase this unit: alive, in range, in line of sight?
local function _usable(jp, u)
    if not (u and u:isExist()) then return false end
    local tp = u:getPoint()
    local dx, dz = tp.x - jp.x, tp.z - jp.z
    if dx * dx + dz * dz > CFG.maxRange * CFG.maxRange then return false end
    return land.isVisible({ x = jp.x, y = jp.y + 2, z = jp.z }, { x = tp.x, y = tp.y + 2, z = tp.z })
end

-- Nearest RED ground unit within range that the spotter can see (every unit
-- of every group, not only the group leads).
local function _bestTarget(jp)
    local best, bestD
    for _, grp in pairs(coalition.getGroups(CFG.enemySide, Group.Category.GROUND) or {}) do
        for _, u in ipairs((grp.getUnits and grp:getUnits()) or {}) do
            if u and u:isExist() then
                local tp = u:getPoint()
                local dx, dz = tp.x - jp.x, tp.z - jp.z
                local d = dx * dx + dz * dz
                if d <= CFG.maxRange * CFG.maxRange and (not bestD or d < bestD) and _usable(jp, u) then
                    bestD, best = d, u
                end
            end
        end
    end
    return best
end

local function _tick(_, t)
    if STATE.active then
        local g = Group.getByName(STATE.active)
        local jU = g and g:getUnits()[1]
        if not (jU and jU:isExist()) then
            -- The spotter is gone (shot down, crashed, removed by hand): stop lasing.
            local label = (STATE.kind == "uav") and "UAV spotter" or "Ground JTAC"
            _destroySpot()
            STATE.active, STATE.kind = nil, nil
            _register()
            _out("[JTAC] " .. label .. " lost, laser off.", 12)
            return t + CFG.tickSec
        end
        local jp = jU:getPoint()
        -- Keep the current target while it is usable; look for another only
        -- when it is not (destroyed, hidden, out of range).
        local cur = STATE.spotTarget and Unit.getByName(STATE.spotTarget)
        local curOk = cur and _usable(jp, cur)
        if curOk and STATE.spot then
            pcall(function() STATE.spot:setPoint(_aimOf(cur)) end)
        else
            local lost = STATE.spotTarget
            _destroySpot()
            local tgt = curOk and cur or _bestTarget(jp) -- a new code keeps the same target
            if tgt then
                local ok = pcall(function() STATE.spot = Spot.createLaser(jU, { x = 0, y = 2, z = 0 }, _aimOf(tgt), STATE.laserCode) end)
                if ok and STATE.spot then
                    STATE.spotTarget = tgt:getName()
                    _out("[JTAC] Lasing " .. ((tgt.getTypeName and tgt:getTypeName()) or "target") ..
                        " on code " .. STATE.laserCode .. ".", 8)
                end
            elseif lost then
                _out("[JTAC] Target lost, searching.", 8)
            end
            _register()
        end
    end
    return t + CFG.tickSec
end

-- ============== Spawns ==============
local function _spawnUAV()
    local zr = _zone(CFG.uavZone); if not zr then return end
    _removeActive()
    local wp = {
        ["x"] = zr.cx, ["y"] = zr.cz, ["alt"] = CFG.uavAlt, ["alt_type"] = "BARO",
        ["type"] = "Turning Point", ["action"] = "Turning Point", ["speed"] = CFG.uavSpeed,
        ["task"] = { id = "ComboTask", params = { tasks = {
            [1] = { id = "Orbit", params = { pattern = "Circle", speed = CFG.uavSpeed, altitude = CFG.uavAlt } },
        } } },
    }
    local gd = {
        ["name"] = GROUP_NAME, ["task"] = "Nothing", ["uncontrolled"] = false, ["start_time"] = 0,
        ["frequency"] = STATE.freq, ["modulation"] = STATE.modulation, ["communication"] = true,
        ["units"] = { [1] = {
            ["type"] = CFG.uavType, ["name"] = GROUP_NAME .. "_1",
            ["x"] = zr.cx, ["y"] = zr.cz, ["alt"] = CFG.uavAlt, ["alt_type"] = "BARO",
            ["speed"] = CFG.uavSpeed, ["heading"] = 0, ["skill"] = "High",
            ["payload"] = { ["pylons"] = {}, ["fuel"] = "1300", ["flare"] = 0, ["chaff"] = 0, ["gun"] = 0 },
        } },
        ["route"] = { ["points"] = { [1] = wp } },
    }
    local grp
    pcall(function() grp = coalition.addGroup(CFG.friendlyCountry, Group.Category.AIRPLANE, gd) end)
    if not grp then _out("[JTAC] UAV spawn failed (check type '" .. CFG.uavType .. "').", 12); return end
    STATE.active, STATE.kind = GROUP_NAME, "uav"
    _applyInvisible(GROUP_NAME)
    timer.scheduleFunction(function() _applyFreq(GROUP_NAME); return nil end, nil, timer.getTime() + 1.0)
    _register()
    _announce("UAV spotter (MQ-9)")
end

local function _spawnGround()
    local zr = _zone(CFG.groundZone); if not zr then return end
    _removeActive()
    local gd = {
        ["name"] = GROUP_NAME, ["task"] = "Ground Nothing",
        ["units"] = { [1] = {
            ["type"] = CFG.groundType, ["name"] = GROUP_NAME .. "_1",
            ["x"] = zr.cx, ["y"] = zr.cz, ["heading"] = 0, ["skill"] = "High",
        } },
        ["route"] = { ["points"] = { [1] = {
            ["x"] = zr.cx, ["y"] = zr.cz, ["type"] = "Turning Point", ["action"] = "Off Road",
            ["speed"] = 0, ["task"] = { id = "ComboTask", params = { tasks = {} } },
        } } },
    }
    local grp
    pcall(function() grp = coalition.addGroup(CFG.friendlyCountry, Group.Category.GROUND, gd) end)
    if not grp then _out("[JTAC] Ground JTAC spawn failed (check type '" .. CFG.groundType .. "').", 12); return end
    STATE.active, STATE.kind = GROUP_NAME, "ground"
    _applyInvisible(GROUP_NAME)
    timer.scheduleFunction(function() _applyFreq(GROUP_NAME); return nil end, nil, timer.getTime() + 1.0)
    _register()
    _announce("Ground JTAC")
end

-- ============== Menu actions ==============
local function _setCode(code)
    STATE.laserCode = code
    -- Drop only the spot: the next tick lases the same target on the new code.
    if STATE.spot then pcall(function() STATE.spot:destroy() end); STATE.spot = nil end
    _register()
    _out("[JTAC] Laser code set to " .. code .. (STATE.active and " (re-lasing)." or "."), 10)
end

local function _setFreq(f, m)
    STATE.freq, STATE.modulation = f, m
    if STATE.active then _applyFreq(STATE.active) end
    _register()
    _out(string.format("[JTAC] Frequency set to %.1f %s.", f, _modName(m)), 10)
end

local function _remove()
    if not STATE.active then _out("[JTAC] No spotter active."); return end
    _removeActive()
    _out("[JTAC] Spotter removed.", 8)
end

local function _report()
    local status = STATE.active
        and ((STATE.kind == "uav") and "UAV spotter up" or "Ground JTAC up")
        or "no spotter active"
    local lasing = ""
    local u = STATE.spotTarget and Unit.getByName(STATE.spotTarget)
    if u then lasing = " | lasing " .. ((u.getTypeName and u:getTypeName()) or "target") end
    _out(string.format("[JTAC] %s | Freq %.1f %s | Laser code %d%s.",
        status, STATE.freq, _modName(), STATE.laserCode, lasing), 15)
end

-- ============== Menu (the spotter's coalition only) ==============
local function _buildMenu()
    local function sub(name, parent) return missionCommands.addSubMenuForCoalition(CFG.side, name, parent) end
    local function cmd(name, parent, fn) return missionCommands.addCommandForCoalition(CFG.side, name, parent, fn) end
    local root = sub("JTAC / Spotter")
    cmd("Spawn UAV spotter (MQ-9)", root, function() _spawnUAV() end)
    cmd("Spawn ground JTAC",        root, function() _spawnGround() end)
    local mc = sub("Laser code", root)
    for _, code in ipairs(CFG.codePresets) do
        cmd(tostring(code), mc, function() _setCode(code) end)
    end
    local mf = sub("Frequency", root)
    for _, fp in ipairs(CFG.freqPresets) do
        cmd(fp.label, mf, function() _setFreq(fp.f, fp.m) end)
    end
    cmd("Report (freq / code)", root, function() _report() end)
    cmd("Remove spotter",       root, function() _remove() end)
end

-- ============== Init ==============
if not JTAC_Initialized then
    JTAC_Initialized = true
    if not (trigger.misc.getZone(CFG.groundZone) or trigger.misc.getZone(CFG.uavZone)) then
        _out("[JTAC] Create at least one zone: " .. CFG.groundZone .. " (ground) or " .. CFG.uavZone .. " (UAV).", 25)
    end
    if not Spot then
        _out("[JTAC] WARNING: Spot API missing, the spotter will not lase in this build.", 20)
    end
    _buildMenu()
    local period = math.max(1, CFG.tickSec)
    timer.scheduleFunction(function(a, time)
        local ok, e = pcall(_tick, a, time)
        if not ok and env and env.info then env.info("[JTAC] tick error: " .. tostring(e)) end
        return time + period
    end, nil, timer.getTime() + period)
    _out(string.format("[JTAC] Spotter ready (F10 menu). Default freq %.1f %s, laser code %d.",
        CFG.freq, _modName(), CFG.laserCode), 12)
end
