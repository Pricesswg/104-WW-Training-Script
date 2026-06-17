-- =========================================================
--  TRAINING_GCA.lua  (Ground Controlled Approach, text talkdown)
--  v1.0, feature-script style, native DCS scripting engine only
-- ---------------------------------------------------------
--  Activates when a BLUE player enters GCA_ACTIVE_ZONE and then,
--  once per second, talks the pilot down to a runway defined in
--  CFG (heading + threshold point + glideslope angle). Azimuth and
--  glideslope deviations are both reported as angles. Deactivates
--  on landing (S_EVENT_LAND) or on leaving the zone. Independent
--  state per player, so several approaches can run at once.
--
--  REQUIRED ME ZONE (type: Circle):
--    GCA_ACTIVE_ZONE   coverage area where the talkdown runs
--
--  The continuous talkdown calls use real GCA phraseology (callsign
--  first, no bracket); only system/status lines carry the [GCA] tag.
-- =========================================================

-- ============== Fail-fast API guard ==============
if not (trigger and trigger.action and trigger.action.outText and trigger.action.outTextForUnit
        and coalition and coalition.getPlayers
        and timer and timer.scheduleFunction
        and world and world.addEventHandler
        and land and land.getHeight
        and Unit and Unit.getByName
        and trigger.misc and trigger.misc.getZone) then
    if trigger and trigger.action and trigger.action.outText then
        trigger.action.outText("[GCA] Required DCS API missing. Script aborted.", 20)
    end
    return
end

-- ============== Config ==============
local CFG = {
    debug            = false,
    zone             = "GCA_ACTIVE_ZONE",
    runway_heading   = 250,             -- degrees true (FILL IN for your runway)
    threshold_point  = { x = 0, z = 0 }, -- world x/z of the landing threshold (FILL IN)
    glideslope_angle = 3.0,             -- degrees
    gear_check_nm    = 3.0,             -- range (nm) at which "check gear" is appended once
    minRange_m       = 185,             -- ~0.1 nm: stop talking inside this (essentially landing)
    tickSec          = 1,
    onDeg            = 0.2,             -- |error| < this  -> "on"
    slightlyDeg      = 1.0,            -- on..this -> "slightly"; above -> "well"
    side             = coalition.side.BLUE,
}

-- ============== State (file-local) ==============
local STATE = { players = {} } -- [unitName] = { gearCalled = bool }

-- ============== Helpers ==============
local NM_M = 1852

local function _out(msg, t) trigger.action.outText(tostring(msg), t or 10) end
local function _dbg(msg, t) if CFG.debug then _out("[GCA][dbg] " .. tostring(msg), t or 6) end end

local function _inZone(point, zone)
    local dx, dz = point.x - zone.point.x, point.z - zone.point.z
    return (dx * dx + dz * dz) <= (zone.radius * zone.radius)
end

local function _callsign(u)
    local cs = u.getPlayerName and u:getPlayerName()
    return (cs ~= nil and cs ~= "") and cs or "Approach"
end

-- Resolve the geometry of the aircraft relative to the configured runway.
-- Returns: dme_m (straight-line range to threshold), azDeg (+ = right of
-- centerline), gsDeg (+ = above glidepath), toThr (along-track distance to
-- threshold; > 0 means on the approach side).
local function _approach(u)
    local p  = u:getPoint()
    local tx, tz = CFG.threshold_point.x, CFG.threshold_point.z
    local relx, relz = p.x - tx, p.z - tz

    local h = math.rad(CFG.runway_heading)
    local fx, fz = math.sin(h), math.cos(h)       -- forward (landing) direction
    local rx, rz = fz, -fx                         -- right-hand perpendicular

    local along = relx * fx + relz * fz            -- + = beyond the threshold
    local cross = relx * rx + relz * rz            -- + = right of centerline
    local toThr = -along                           -- + = before the threshold (on approach)
    local dme_m = math.sqrt(relx * relx + relz * relz)

    local thrElev = land.getHeight({ x = tx, y = tz }) or 0  -- Vec2 {x, y=z}
    local height  = p.y - thrElev

    local base   = math.max(toThr, 1)              -- guard the angle denominators
    local azDeg  = math.deg(math.atan2(cross, base))
    local gsDeg  = math.deg(math.atan2(height, base)) - CFG.glideslope_angle
    return dme_m, azDeg, gsDeg, toThr
end

local function _qual(absDeg)
    if absDeg < CFG.onDeg then return "on"
    elseif absDeg <= CFG.slightlyDeg then return "slightly"
    else return "well" end
end

local function _latPhrase(azDeg)
    local q = _qual(math.abs(azDeg))
    if q == "on" then return "on centerline" end
    return q .. " " .. (azDeg > 0 and "right" or "left")
end

local function _vertPhrase(gsDeg)
    local q = _qual(math.abs(gsDeg))
    if q == "on" then return "on glidepath" end
    return q .. " " .. (gsDeg > 0 and "above" or "below") .. " glidepath"
end

-- ============== Per-second talkdown ==============
local function _talkdown(u, st)
    local dme_m, azDeg, gsDeg, toThr = _approach(u)
    if toThr <= 0 or dme_m < CFG.minRange_m then return end -- over/past the threshold

    local dist = dme_m / NM_M
    local msg  = string.format("%s, %s, %.1f miles, %s",
        _callsign(u), _latPhrase(azDeg), dist, _vertPhrase(gsDeg))
    -- "check gear" once, the first time inside gear-check range.
    if (not st.gearCalled) and dist <= CFG.gear_check_nm then
        msg = msg .. ", check gear"
        st.gearCalled = true
    end
    trigger.action.outTextForUnit(u:getID(), msg, CFG.tickSec + 1)
end

-- ============== Main tick ==============
local function _tick(_, t)
    local zone = trigger.misc.getZone(CFG.zone)
    if zone then
        local players = coalition.getPlayers(CFG.side) or {}
        local seen = {}
        for _, u in pairs(players) do
            if u and u:isExist() then
                local nm = u:getName()
                if _inZone(u:getPoint(), zone) then
                    seen[nm] = true
                    if not STATE.players[nm] then
                        STATE.players[nm] = { gearCalled = false }
                        trigger.action.outTextForUnit(u:getID(),
                            string.format("[GCA] %s, radar contact, fly heading %03d, call the ball.",
                                _callsign(u), math.floor(CFG.runway_heading)), 12)
                    end
                    _talkdown(u, STATE.players[nm])
                end
            end
        end
        -- Players that left the zone (or despawned): terminate service.
        for nm in pairs(STATE.players) do
            if not seen[nm] then
                local u = Unit.getByName(nm)
                if u then
                    trigger.action.outTextForUnit(u:getID(),
                        "[GCA] " .. _callsign(u) .. ", leaving coverage, radar service terminated.", 10)
                end
                STATE.players[nm] = nil
            end
        end
    end
    return t + CFG.tickSec
end

-- ============== Landing terminates the approach ==============
local _handler = {}
function _handler:onEvent(event)
    local ok, err = pcall(function()
        if not event or event.id ~= world.event.S_EVENT_LAND then return end
        local u = event.initiator
        if not u or not u.getName then return end
        local nm = u:getName()
        if STATE.players[nm] then
            pcall(function()
                trigger.action.outTextForUnit(u:getID(), "[GCA] " .. _callsign(u) .. ", touchdown, radar service terminated.", 12)
            end)
            STATE.players[nm] = nil
        end
    end)
    if not ok and env and env.info then env.info("[GCA] onEvent error: " .. tostring(err)) end
end

-- ============== Init ==============
if not GCA_Initialized then
    GCA_Initialized = true

    if not trigger.misc.getZone(CFG.zone) then
        _out("[GCA] MISSING ZONE: " .. CFG.zone .. ". Create it in the Mission Editor. Script aborted.", 30)
        return
    end
    if CFG.threshold_point.x == 0 and CFG.threshold_point.z == 0 then
        _out("[GCA] WARNING: threshold_point is still {x=0,z=0} (FILL IN the runway threshold).", 20)
    end

    world.addEventHandler(_handler)
    local period = math.max(1, CFG.tickSec)
    timer.scheduleFunction(function(a, time)
        local ok, e = pcall(_tick, a, time)
        if not ok and env and env.info then env.info("[GCA] tick error: " .. tostring(e)) end
        return time + period
    end, nil, timer.getTime() + period)
    _out("[GCA] Ground Controlled Approach loaded for runway heading " .. math.floor(CFG.runway_heading) .. ".", 12)
end
