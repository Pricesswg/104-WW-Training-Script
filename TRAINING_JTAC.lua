-- =========================================================
--  TRAINING_JTAC.lua  (JTAC / UAV spotter for the range)
--  v1.0, feature-script style, native DCS scripting engine only
-- ---------------------------------------------------------
--  Spawns a friendly (BLUE) spotter from an F10 menu and makes it invisible to
--  enemy AI (SetInvisible), so it can sit on the range and lase RED targets
--  without being shot. Two flavours, your choice from the menu:
--    UAV spotter  : an MQ-9 Reaper orbiting the TR_JTAC zone (best line of
--                   sight, autonomous FAC, lases from above).
--    Ground JTAC  : a vehicle at the TR_JTAC zone centre (more realistic, but
--                   needs clear line of sight to the targets).
--  Both work autonomously: they detect and lase RED units in view. The laser
--  code and the radio frequency come from CFG and are announced on spawn.
--
--  REQUIRED ME ZONE (type: Circle):
--    TR_JTAC   placed on/over the range; the ground JTAC sits at its centre,
--              the UAV orbits it.
--
--  CAVEAT (verify in-game, like the TACAN beacons): the exact FAC task params
--  and the autonomous auto-lase behaviour vary a little between DCS versions.
--  The default laser code 1688 is the DCS autonomous default and the most
--  reliable. If a non-default code is needed and does not take, say so and the
--  module can switch to FAC_EngageGroup per target.
-- =========================================================

-- ============== Fail-fast API guard ==============
if not (trigger and trigger.action and trigger.action.outText
        and coalition and coalition.addGroup
        and timer and timer.scheduleFunction
        and missionCommands and missionCommands.addSubMenu and missionCommands.addCommand
        and trigger.misc and trigger.misc.getZone) then
    if trigger and trigger.action and trigger.action.outText then
        trigger.action.outText("[JTAC] Required DCS API missing. Script aborted.", 20)
    end
    return
end

-- ============== Config ==============
local CFG = {
    debug           = false,
    friendlyCountry = country.id.USA,   -- the spotter is BLUE (spots for the BLUE player)
    zone            = "TR_JTAC",         -- ME zone: ground JTAC sits here, UAV orbits it
    groundType      = "Hummer",          -- ground JTAC vehicle (exact DCS type)
    uavType         = "MQ-9 Reaper",     -- airborne FAC drone (exact DCS type)
    uavAlt          = 6000,              -- UAV orbit altitude (m)
    uavSpeed        = 120,               -- UAV orbit speed (m/s)
    laserCode       = 1688,              -- default laser code (set your pod/bomb to match)
    freq            = 251.0,             -- radio frequency (MHz)
    modulation      = 0,                 -- 0 = AM, 1 = FM
}

-- ============== State ==============
local STATE = { active = nil, kind = nil } -- active group name + "uav"/"ground"

-- ============== Helpers ==============
local GROUP_NAME = "TR_JTAC_UNIT"

local function _out(msg, t) trigger.action.outText(tostring(msg), t or 10) end
local function _dbg(msg, t) if CFG.debug then _out("[JTAC][dbg] " .. tostring(msg), t or 6) end end
local function _modName() return (CFG.modulation == 1) and "FM" or "AM" end

local function _zone(name)
    local z = trigger.misc.getZone(name)
    if z then return { cx = z.point.x, cz = z.point.z, r = z.radius } end
    _out("[JTAC] Zone not found: " .. tostring(name), 15)
    return nil
end

local function _removeActive()
    if STATE.active then
        local g = Group.getByName(STATE.active)
        if g then g:destroy() end
        STATE.active, STATE.kind = nil, nil
    end
end

-- Invisible to enemy AI so the spotter is not engaged. Applied on the post-spawn
-- delay and re-looked-up by name (controller commands share the bind race).
local function _applyInvisible(name)
    timer.scheduleFunction(function()
        local g = Group.getByName(name); if not g then return nil end
        pcall(function() g:getController():setCommand({ id = "SetInvisible", params = { value = true } }) end)
        return nil
    end, nil, timer.getTime() + 1.0)
end

-- Make a ground unit an autonomous FAC (detect + lase RED in LOS). Best-effort,
-- pcall-guarded; the UAV uses the AFAC group task instead.
local function _applyGroundFAC(name)
    timer.scheduleFunction(function()
        local g = Group.getByName(name); if not g then return nil end
        pcall(function()
            g:getController():setTask({ id = "FAC", params = {
                frequency  = CFG.freq * 1000000,
                modulation = CFG.modulation,
            } })
        end)
        return nil
    end, nil, timer.getTime() + 1.5)
end

local function _announce(label)
    _out(string.format("[JTAC] %s active | Freq %.1f %s | Laser code %d.",
        label, CFG.freq, _modName(), CFG.laserCode), 15)
end

-- ============== Spawns ==============
local function _spawnUAV()
    local zr = _zone(CFG.zone); if not zr then return end
    _removeActive()
    local wp = {
        ["x"] = zr.cx, ["y"] = zr.cz, ["alt"] = CFG.uavAlt, ["alt_type"] = "BARO",
        ["type"] = "Turning Point", ["action"] = "Turning Point", ["speed"] = CFG.uavSpeed,
        ["task"] = { id = "ComboTask", params = { tasks = {
            [1] = { id = "Orbit", params = { pattern = "Circle", speed = CFG.uavSpeed, altitude = CFG.uavAlt } },
            [2] = { id = "FAC",   params = { frequency = CFG.freq * 1000000, modulation = CFG.modulation } },
        } } },
    }
    local gd = {
        ["name"] = GROUP_NAME, ["task"] = "AFAC", ["uncontrolled"] = false, ["start_time"] = 0,
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
    _announce("UAV spotter (MQ-9)")
end

local function _spawnGround()
    local zr = _zone(CFG.zone); if not zr then return end
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
    _applyGroundFAC(GROUP_NAME)
    _announce("Ground JTAC")
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
    _out(string.format("[JTAC] %s | Freq %.1f %s | Laser code %d.",
        status, CFG.freq, _modName(), CFG.laserCode), 15)
end

-- ============== Menu ==============
local function _buildMenu()
    local root = missionCommands.addSubMenu("JTAC / Spotter")
    missionCommands.addCommand("Spawn UAV spotter (MQ-9)", root, function() _spawnUAV() end)
    missionCommands.addCommand("Spawn ground JTAC",        root, function() _spawnGround() end)
    missionCommands.addCommand("Report (freq / code)",     root, function() _report() end)
    missionCommands.addCommand("Remove spotter",           root, function() _remove() end)
end

-- ============== Init ==============
if not JTAC_Initialized then
    JTAC_Initialized = true
    if not trigger.misc.getZone(CFG.zone) then
        _out("[JTAC] MISSING ZONE: " .. CFG.zone .. ". Create it in the Mission Editor.", 25)
    end
    _buildMenu()
    _out(string.format("[JTAC] Spotter ready (F10 menu). Default freq %.1f %s, laser code %d.",
        CFG.freq, _modName(), CFG.laserCode), 12)
end
