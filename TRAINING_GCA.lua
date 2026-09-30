-- =========================================================
--  TRAINING_GCA.lua  (Ground Controlled Approach, text talkdown)
--  v2.0, feature-script style, native DCS scripting engine only
-- ---------------------------------------------------------
--  GCA_ACTIVE_ZONE picks the airfield: the nearest airdrome to its centre.
--  A BLUE player gets the talkdown when airborne on final: within
--  CFG.rangeNm of the threshold, inside CFG.coneDeg of the extended
--  centreline, below CFG.maxHeightFt and heading for the runway. With
--  CFG.auto (default) the runways come from the airfield and the active end
--  is the one most into the wind; in calm wind it is the end the aircraft is
--  lined up for. CFG.auto = false uses the manual runway in CFG.
--  Course and glidepath deviations are both reported as angles (course
--  measured from the far end of the runway, like a localizer; glidepath to
--  the touchdown point past the threshold). Headings in the calls are
--  magnetic. The talkdown ends over the threshold, on landing, or when the
--  aircraft leaves the approach. Independent state per player.
--
--  REQUIRED ME ZONE (Circle or Quad):
--    GCA_ACTIVE_ZONE   placed over the airfield
--
--  The continuous talkdown calls use PAR phraseology (callsign first, no
--  bracket) and replace each other on screen; only system/status lines
--  carry the [GCA] tag.
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
    auto             = true,             -- runways from the airfield under the zone
    runway_heading   = 290,              -- manual runway (auto = false): landing heading, degrees MAGNETIC
    threshold_point  = { x = 0, z = 0 }, -- manual runway: world x/z of the landing threshold
    runway_length    = 2500,             -- manual runway length (m)
    glideslope_angle = 3.0,              -- degrees
    tch_ft           = 50,               -- threshold crossing height: the path aims ~290 m past the threshold
    rangeNm          = 10,               -- talkdown starts inside this distance from the threshold
    coneDeg          = 30,               -- ... within this angle of the extended centreline
    maxHeightFt      = 6000,             -- ... below this height above the threshold
    trackDeg         = 60,               -- ... and flying within this angle of the runway heading
    gear_check_nm    = 3.0,              -- range (nm) at which "check wheels down" is appended once
    tickSec          = 1,
    quietSec         = 5,                -- after radar contact, seconds before the first talkdown call
    onDeg            = 0.2,              -- |error| < this  -> "on"
    slightlyDeg      = 1.0,              -- on..this -> "slightly"; above -> "well"
    side             = coalition.side.BLUE,
    magvar           = nil,              -- magnetic variation, degrees east; nil = from the theatre
}

-- Magnetic variation by theatre (degrees east), same values as SECTOR.
local MAGVAR = { Caucasus = 6.0, Syria = 5.0, PersianGulf = 2.5, Nevada = 11.5, MarianaIslands = 1.0,
                 SinaiMap = 4.5, Sinai = 4.5, Kola = 12.0, Afghanistan = 3.0, Falklands = 3.0,
                 Normandy = -1.0, TheChannel = 0.0, Iraq = 4.5, GermanyCW = 3.0 }

-- ============== State (file-local) ==============
local STATE = {
    players  = {},  -- [unitName] = { e (runway end), gearCalled, quietUntil }
    notified = {},  -- [unitName] = time of the last "runway in use" notice
    af       = nil, -- airfield: false = looked up and none found
}

-- ============== Helpers ==============
local NM_M, FT_M = 1852, 0.3048

local function _out(msg, t) trigger.action.outText(tostring(msg), t or 10) end
local function _dbg(msg, t) if CFG.debug then _out("[GCA][dbg] " .. tostring(msg), t or 6) end end

local function _callsign(u)
    local ok, cs = pcall(function() return u:getPlayerName() end)
    return (ok and cs ~= nil and cs ~= "") and cs or "Approach"
end

local function _toUnit(u, msg, t, replace)
    pcall(function() trigger.action.outTextForUnit(u:getID(), msg, t, replace) end)
end

local function _angle(a, b) return math.abs((a - b + 540) % 360 - 180) end

local function _magvar()
    if CFG.magvar then return CFG.magvar end
    local th = env and env.mission and env.mission.theatre
    return MAGVAR[th] or 0
end

-- Grid bearing of true north at p. The DCS map grid is not true north (on
-- Syria it is 3-4 degrees off at Cyprus), and the cockpit reads magnetic.
local function _gridNorth(p)
    local ok, n = pcall(function()
        local lat, lon = coord.LOtoLL({ x = p.x, y = 0, z = p.z })
        local q = coord.LLtoLO(lat + 0.1, lon, 0)
        return math.deg(math.atan2(q.z - p.z, q.x - p.x))
    end)
    return ok and n or 0
end

local function _toMag(gridDeg, p) return (gridDeg - _gridNorth(p) - _magvar()) % 360 end
local function _fromMag(magDeg, p) return (magDeg + _magvar() + _gridNorth(p)) % 360 end

local function _hdgText(deg)
    local h = math.floor(deg + 0.5) % 360
    return string.format("%03d", (h == 0) and 360 or h)
end

local function _rwyNumber(magDeg)
    local n = math.floor(magDeg / 10 + 0.5) % 36
    return string.format("%02d", (n == 0) and 36 or n)
end

-- ============== Runways ==============
-- Airbase:getRunways() gives `course` as MINUS the heading, in radians (MOOSE
-- reads it as -course too), and the sign has changed between DCS versions:
-- the axis is taken as -course unless the designator ("11" ~ 110 magnetic)
-- clearly says the other one. Only the axis matters here; the landing end is
-- chosen later, by wind or by the aircraft.
local function _axis(r, p)
    local c = math.deg(r.course or 0)
    local primary, other = (-c) % 360, c % 360
    local n = tonumber(tostring(r.Name or ""):match("^(%d%d?)"))
    if n then
        local want = _fromMag(n * 10, p)
        local function off(h)
            local d = _angle(h, want)
            return math.min(d, 180 - d)
        end
        if off(other) + 20 < off(primary) then primary = other end
    end
    return primary
end

local function _end(hdgGrid, cen, len, elev)
    local h = math.rad(hdgGrid)
    local fx, fz = math.cos(h), math.sin(h)
    local thr = { x = cen.x - fx * len / 2, z = cen.z - fz * len / 2 }
    local mag = _toMag(hdgGrid, thr)
    return { hdg = hdgGrid, mag = mag, rwy = _rwyNumber(mag), thr = thr, len = len,
             elev = elev or (land.getHeight({ x = thr.x, y = thr.z }) or 0) }
end

-- The airfield under the zone, with both ends of every runway. Looked up once;
-- if nothing is found it tries again every 30 s (the world may still be loading).
local function _airfield()
    if STATE.af then return STATE.af end
    if STATE.af == false and timer.getTime() - (STATE.afTried or 0) < 30 then return nil end
    STATE.af, STATE.afTried = false, timer.getTime()
    local z = trigger.misc.getZone(CFG.zone)
    if not (z and world.getAirbases) then return nil end
    local best, bestD
    for _, ab in pairs(world.getAirbases() or {}) do
        local okc, cat = pcall(function() return ab:getDesc().category end)
        local isAirdrome = not (okc and cat ~= nil and Airbase and Airbase.Category) or cat == Airbase.Category.AIRDROME
        if isAirdrome then
            local p = ab:getPoint()
            local d = (p.x - z.point.x) ^ 2 + (p.z - z.point.z) ^ 2
            if not bestD or d < bestD then bestD, best = d, ab end
        end
    end
    if not best then return nil end
    local okr, rwys = pcall(function() return best:getRunways() end)
    if not okr or not rwys or #rwys == 0 then return nil end
    local ap = best:getPoint()
    local ends = {}
    for _, r in ipairs(rwys) do
        local cen = r.position or ap
        local axis = _axis(r, cen)
        local len = r.length or 2500
        ends[#ends + 1] = _end(axis, cen, len)
        ends[#ends + 1] = _end((axis + 180) % 360, cen, len)
    end
    local okn, name = pcall(function() return best:getName() end)
    STATE.af = { name = okn and name or "the airfield", p = ap, ends = ends }
    _dbg("airfield " .. STATE.af.name .. ", " .. #rwys .. " runway(s)")
    return STATE.af
end

local function _ends()
    if CFG.auto then
        local af = _airfield()
        if af then return af.ends, af end
    end
    local t = CFG.threshold_point
    if t.x == 0 and t.z == 0 then return {}, nil end
    local cen = { x = t.x, z = t.z }
    local e = _end(_fromMag(CFG.runway_heading, cen), cen, 0) -- threshold given directly
    e.len = CFG.runway_length
    return { e }, nil
end

-- Wind at the field (atmosphere.getWind: the vector it blows TOWARD).
local function _wind(p)
    local w = { x = 0, z = 0 }
    pcall(function()
        local ww = atmosphere.getWind({ x = p.x, y = (p.y or 0) + 10, z = p.z })
        if ww then w = ww end
    end)
    return w
end

local function _windText(w, p)
    local kt = math.sqrt(w.x * w.x + w.z * w.z) * 1.94384
    if kt < 3 then return "wind calm" end
    local from = (math.deg(math.atan2(w.z, w.x)) + 180) % 360
    return string.format("wind %s at %d", _hdgText(_toMag(from, p)), math.floor(kt + 0.5))
end

-- ============== Geometry ==============
-- Returns toThr (m, > 0 before the threshold), course deviation (deg, + =
-- right), glidepath deviation (deg, + = above), angle off the extended
-- centreline seen from the threshold, and height above the threshold.
local function _geom(e, p)
    local h = math.rad(e.hdg)
    local fx, fz = math.cos(h), math.sin(h)            -- x = north, z = east
    local rx, rz = p.x - e.thr.x, p.z - e.thr.z
    local toThr = -(rx * fx + rz * fz)
    local cross = -rx * fz + rz * fx                   -- right of the landing direction is (-sin, cos)
    local height = p.y - e.elev
    local gpi = CFG.tch_ft * FT_M / math.tan(math.rad(CFG.glideslope_angle))
    local azDeg = math.deg(math.atan2(cross, math.max(toThr + e.len, 1)))
    local gsDeg = math.deg(math.atan2(height, math.max(toThr + gpi, 1))) - CFG.glideslope_angle
    local offDeg = math.deg(math.atan2(math.abs(cross), math.max(toThr, 1)))
    return toThr, azDeg, gsDeg, offDeg, height, toThr + gpi
end

local function _track(u)
    local v = u:getVelocity()
    if v and (v.x * v.x + v.z * v.z) > 100 then return math.deg(math.atan2(v.z, v.x)) % 360 end
    local pos = u:getPosition()
    return math.deg(math.atan2(pos.x.z, pos.x.x)) % 360
end

local function _inWindow(e, u, p)
    local toThr, _, _, offDeg, height = _geom(e, p)
    return toThr > 0 and toThr <= CFG.rangeNm * NM_M and offDeg <= CFG.coneDeg
       and height <= CFG.maxHeightFt * FT_M and _angle(_track(u), e.hdg) <= CFG.trackDeg, offDeg
end

-- ============== Phraseology ==============
local function _qual(absDeg)
    if absDeg < CFG.onDeg then return "on"
    elseif absDeg <= CFG.slightlyDeg then return "slightly"
    else return "well" end
end

local function _coursePhrase(azDeg)
    local q = _qual(math.abs(azDeg))
    if q == "on" then return "on course" end
    return q .. " " .. (azDeg > 0 and "right" or "left") .. " of course"
end

local function _pathPhrase(gsDeg)
    local q = _qual(math.abs(gsDeg))
    if q == "on" then return "on glidepath" end
    return q .. " " .. (gsDeg > 0 and "above" or "below") .. " glidepath"
end

-- ============== Service ==============
local function _terminate(u, nm, why)
    STATE.players[nm] = nil
    if u then _toUnit(u, "[GCA] " .. _callsign(u) .. ", " .. why .. ", radar service terminated.", 10, false) end
end

local function _start(u, nm, e, af)
    local p = u:getPoint()
    local _, _, _, _, _, toTd = _geom(e, p)
    STATE.players[nm] = { e = e, gearCalled = false, quietUntil = timer.getTime() + CFG.quietSec }
    _toUnit(u, string.format("[GCA] %s, radar contact, %.1f miles from touchdown. This will be a PAR approach " ..
        "to runway %s, %s. Fly heading %s, perform landing check.",
        _callsign(u), toTd / NM_M, e.rwy, _windText(_wind(af and af.p or e.thr), e.thr), _hdgText(e.mag)),
        CFG.quietSec + 5, false)
end

-- Picks the end for a player not yet under service. Wind of 5 kt or more
-- decides the active end; in calm wind any end the aircraft is lined up for.
local function _pickEnd(u, p, ends, af)
    local w = _wind(af and af.p or p)
    local calm = (w.x * w.x + w.z * w.z) < 2.6 * 2.6
    local active, bestHead
    if not calm then
        for _, e in ipairs(ends) do
            local h = math.rad(e.hdg)
            local head = -(w.x * math.cos(h) + w.z * math.sin(h)) + e.len * 1e-6
            if not bestHead or head > bestHead then bestHead, active = head, e end
        end
    end
    local pick, pickOff, other
    for _, e in ipairs(ends) do
        local ok, off = _inWindow(e, u, p)
        if ok then
            if calm or e == active then
                if not pickOff or off < pickOff then pick, pickOff = e, off end
            else
                other = e
            end
        end
    end
    return pick, (not pick and other) and active or nil
end

local function _talkdown(u, st)
    local p = u:getPoint()
    local toThr, azDeg, gsDeg, _, _, toTd = _geom(st.e, p)
    if toThr <= 0 then
        _toUnit(u, _callsign(u) .. ", over landing threshold.", 6, true)
        STATE.players[u:getName()] = nil
        return
    end
    if timer.getTime() < st.quietUntil then return end
    local dist = toTd / NM_M
    local msg = string.format("%s, %s, %s, %.1f miles from touchdown",
        _callsign(u), _coursePhrase(azDeg), _pathPhrase(gsDeg), dist)
    if (not st.gearCalled) and dist <= CFG.gear_check_nm then
        msg = msg .. ", check wheels down"
        st.gearCalled = true
    end
    trigger.action.outTextForUnit(u:getID(), msg, CFG.tickSec + 1, true) -- replaces the previous call
end

-- ============== Main tick ==============
local function _tick(_, t)
    local ends, af = _ends()
    local seen = {}
    for _, u in pairs(coalition.getPlayers(CFG.side) or {}) do
        if u and u:isExist() then
            local nm = u:getName()
            seen[nm] = true
            local st = STATE.players[nm]
            if not u:inAir() then
                if st then STATE.players[nm] = nil end -- on the ground: S_EVENT_LAND says the rest
            elseif st then
                local p = u:getPoint()
                local toThr, _, _, offDeg, height = _geom(st.e, p)
                if toThr > (CFG.rangeNm + 2) * NM_M or offDeg > CFG.coneDeg + 15
                   or height > (CFG.maxHeightFt + 2000) * FT_M then
                    _terminate(u, nm, "leaving the approach")
                else
                    _talkdown(u, st)
                end
            elseif #ends > 0 then
                local p = u:getPoint()
                local e, inUse = _pickEnd(u, p, ends, af)
                if e then
                    _start(u, nm, e, af)
                elseif inUse and (not STATE.notified[nm] or t - STATE.notified[nm] > 120) then
                    STATE.notified[nm] = t
                    _toUnit(u, string.format("[GCA] %s, runway %s in use, %s. Radar service on final to %s.",
                        _callsign(u), inUse.rwy, _windText(_wind(af and af.p or p), inUse.thr), inUse.rwy), 12, false)
                end
            end
        end
    end
    -- Players that despawned: forget them.
    for nm in pairs(STATE.players) do
        if not seen[nm] then STATE.players[nm] = nil end
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
            STATE.players[nm] = nil
            _toUnit(u, "[GCA] " .. _callsign(u) .. ", touchdown, radar service terminated.", 12, false)
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

    world.addEventHandler(_handler)
    local period = math.max(1, CFG.tickSec)
    timer.scheduleFunction(function(a, time)
        local ok, e = pcall(_tick, a, time)
        if not ok and env and env.info then env.info("[GCA] tick error: " .. tostring(e)) end
        return time + period
    end, nil, timer.getTime() + period)

    -- Say which runways the service will use, or why there is none.
    timer.scheduleFunction(function()
        local ends, af = _ends()
        if #ends == 0 then
            _out("[GCA] No runway: the zone has no airfield with runways and the manual threshold is {x=0,z=0}. " ..
                 "Set CFG.threshold_point and CFG.runway_heading, or move the zone over an airfield.", 25)
            return nil
        end
        local rw = {}
        for _, e in ipairs(ends) do rw[#rw + 1] = e.rwy end
        _out("[GCA] Ground Controlled Approach ready at " .. (af and af.name or "the manual runway") ..
             ", runways " .. table.concat(rw, "/") .. ".", 12)
        return nil
    end, nil, timer.getTime() + 2)
end
