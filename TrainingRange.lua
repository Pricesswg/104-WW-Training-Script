-- ===========================================================================
-- TRAINING RANGE  (TrainingRange.lua)  v2.1
-- ===========================================================================
-- Author:     Alessandro Simonitto
-- Repository: https://github.com/Pricesswg/104-WW-Training-Script
-- License:    MIT
--
-- Single-file feature script, native DCS scripting engine only (no MOOSE /
-- MIST / CTLD). Load it once via a trigger:  MISSION START -> DO SCRIPT FILE.
--
-- INSTALLATION:
--   1. Open the mission in the Mission Editor.
--   2. Create the zones listed below with the EXACT names.
--   3. Add a trigger:  MISSION START -> DO SCRIPT FILE -> TrainingRange.lua
--   4. Full documentation and wiki: see the GitHub repository.
--
-- REQUIRED ZONES IN THE MISSION EDITOR (Circle or Quad, sizes are suggestions):
--   TR_BOMBING        ~3 km       unarmoured targets (Ural) and the convoy spawn inside
--   TR_ARMOR_LIGHT    ~3 km       light armour (BTR-80) spawns inside
--   TR_ARMOR_HEAVY    ~3 km       heavy armour (T-90) spawns inside
--   TR_DOGFIGHT       ~15 km      dogfight arena
--   TR_SEAD_RADAR     ~8 km       radar SAM zone (SAM spawns at a random point inside)
--   TR_SEAD_IR        ~5 km       IR / AAA zone (threat spawns at a random point inside)
--   TR_CARRIER        any         carrier strike group spawns at its centre at mission start
--   TR_REFUEL_BASKET  ~60x15 km   basket tanker track (a Quad's long side sets the racetrack)
--   TR_REFUEL_BOOM    ~60x15 km   boom tanker track, same
--
-- A Quad is used with the shape drawn in the editor (its corners are read
-- from the mission), a Circle with its radius. Every spawn location is a
-- zone, so there are no x/z coordinates to enter by hand.
--
-- DEFAULTS: the radio, TACAN, ICLS, Link 4 and ACLS values in TR_Config are
-- set on every asset when it spawns, with no extra step. TRAINING_Comms.lua,
-- if loaded, lists them all from F10 -> "Comms card".
--
-- MISSILE PROTECTION: missiles fired by the range's SAMs, and missiles fired
-- between players in the dogfight arena, are destroyed just before impact and
-- reported as a hit (the technique of the "missile trainer" scripts). It does
-- not rely on the Immortal command, which does not protect client aircraft in
-- multiplayer. Gun fire cannot be intercepted, so range AAA holds fire by
-- default (TR_Config.sead.aaaLiveFire, also switchable from the menu).
--
-- BOMBING SCORES: bombs, rockets and air-to-ground missiles released by
-- players near the range are followed to the ground; the pilot gets the
-- distance from the nearest target, the clock position along the attack
-- heading and a grade, and "Scores" in the menu lists everyone.
--
-- HARM REACTION: a range SAM an anti-radiation missile comes at switches its
-- radar off after a few seconds and back on after the missile has gone.
--
-- F10 MAP: range zones, tanker tracks with their radio and TACAN, the carrier
-- and the S-3B track are drawn on the map for the player coalition.
--
-- EDITABLE PARAMETERS:
-- Everything you are meant to tune lives in the TR_Config block below.
-- Do not change anything outside TR_Config unless you know the code.
--
-- All in-game text and code comments are in English on purpose: the file is
-- published with an international wiki.
-- ===========================================================================

TR_Config = {
    -- -----------------------------------------------------------------------
    -- BOMBING RANGE
    -- -----------------------------------------------------------------------
    bombing = {
        zone       = "TR_BOMBING",           -- ME zone, unarmoured targets and the convoy spawn inside
        lightZone  = "TR_ARMOR_LIGHT",       -- ME zone, light armour (BTR-80) spawns inside
        heavyZone  = "TR_ARMOR_HEAVY",       -- ME zone, heavy armour (T-90) spawns inside
        minSpacing = 500,                    -- minimum metres between targets
        smokeColor = trigger.smokeColor.Red, -- Red / Green / White / Orange / Blue
        staticUnit = "Ural-375",             -- unarmoured target (visible truck)
        lightUnit  = "BTR-80",               -- light armour target
        heavyUnit  = "T-90",                 -- heavy armour target
    },
    -- -----------------------------------------------------------------------
    -- BOMBING SCORES: every bomb, rocket and air-to-ground missile a player
    -- releases near the range is followed to the ground and scored against
    -- the nearest range target (MOOSE range defaults for the grades)
    -- -----------------------------------------------------------------------
    scoring = {
        enabled  = true,
        radius   = 1000, -- impacts farther than this from every target are not scored (metres)
        goodM    = 25,   -- GOOD within this, EXCELLENT within half of it, SHACK within 1.5 m
        trackKm  = 30,   -- only weapons released within this distance of a bombing zone are followed
        rockets  = true,
        missiles = true, -- air-to-ground missiles (Maverick, Hellfire...), anti-radiation ones excluded
    },
    -- -----------------------------------------------------------------------
    -- DOGFIGHT ZONE
    -- -----------------------------------------------------------------------
    dogfight = {
        zone         = "TR_DOGFIGHT", -- ME zone name
        minAGL       = 100,           -- minimum AGL (m) to activate dogfight mode
        pollInterval = 2,             -- seconds between checks (do not go below 1)
    },
    -- -----------------------------------------------------------------------
    -- SEAD RANGE
    -- -----------------------------------------------------------------------
    sead = {
        radarZone    = "TR_SEAD_RADAR", -- ME zone, radar SAM (spawns at a random point inside)
        irZone       = "TR_SEAD_IR",    -- ME zone, IR/AAA (spawns at a random point inside)
        pollInterval = 2,               -- seconds between player checks
        aaaLiveFire  = false,           -- AAA guns: false = radar on but hold fire (guns cannot be intercepted)
        -- HARM reaction: a site an anti-radiation missile comes at switches its
        -- radar off after the crew's reaction time, and back on a while after
        -- the missile has gone. Also switchable from the menu.
        harmReaction = true,
        harmDelay    = { 3, 10 },       -- seconds from the launch to the shutdown (random in between)
        harmOff      = { 20, 45 },      -- seconds the radar stays off after the missile is gone
        harmConeDeg  = 15,              -- a missile with no target counts when it flies at a site within this cone
        harmReachKm  = 150,             -- ... and is closer than this
    },
    -- -----------------------------------------------------------------------
    -- MISSILE PROTECTION (SEAD range and dogfight arena)
    -- -----------------------------------------------------------------------
    protection = {
        enabled     = true,
        destroyM    = 200, -- destroy a missile this close to a protected player (metres)
        destroyBigM = 500, -- ... or this close when its warhead is big (SA-2, SA-3, SA-6, Hawk)
        bigKg       = 50,  -- warhead explosive mass (kg) above which a missile counts as big
    },
    -- -----------------------------------------------------------------------
    -- CARRIER OPS
    -- -----------------------------------------------------------------------
    carrier = {
        zone          = "TR_CARRIER", -- ME zone, the strike group spawns at its centre
        groupName     = "TR_CSG",     -- ship group name (carrier + escorts)
        unitName      = "TR_CARRIER", -- carrier ship unit name (recovery reference)
        type          = "Stennis",    -- carrier type. "Stennis" needs no DLC; swap for
                                      -- "CVN_73"/"CVN_71" if you own Supercarrier.
        heading       = 270,          -- initial course, degrees (map grid)
        speed         = 15,           -- cruise speed, knots
        boxLegNm      = 25,           -- the group steams this far out and back, sea room permitting
        recoveryWodKt = 27,           -- "Call recovery": ship speed = this minus the headwind
        maxSpeedKt    = 30,
        deckAngle     = 9,            -- angled deck, degrees to port: recovery BRC = wind + this
        radio = { mhz = 127.5, mod = 0 },                    -- carrier radio (mod 0 = AM, 1 = FM)
        tacan = { channel = 74, mode = "X", callsign = "STN" },
        icls  = { channel = 11, callsign = "STN" },
        link4 = { mhz = 336.0, callsign = "STN" },           -- F-14 / F/A-18 datalink
        acls  = true,                                         -- needs Link 4
        -- Escort screen, spawned in formation with the carrier and held as the
        -- group steams (they turn with it into the wind). fwd/stbd are metres in
        -- the carrier frame (fwd along the heading, stbd to the right). Edit the
        -- positions to taste, swap the types if a name differs in your DCS build.
        escorts = {
            { type = "TICONDEROG",            fwd =  9260, stbd =     0 }, -- AAW cruiser, leading
            { type = "USS_Arleigh_Burke_IIa", fwd =  5500, stbd = -5500 }, -- DDG, port bow
            { type = "USS_Arleigh_Burke_IIa", fwd =  5500, stbd =  5500 }, -- DDG, starboard bow
            { type = "PERRY",                 fwd = -3700, stbd =   900 }, -- frigate, plane guard astern
        },
        -- S-3B recovery tanker: its racetrack is laid in the carrier frame and
        -- moved again whenever the carrier has steamed away or turned.
        recoveryTanker = {
            type      = "S-3B Tanker",
            alt       = 1830,          -- metres (6000 ft)
            kias      = 250,           -- indicated airspeed, knots
            fwd       = 0,             -- racetrack centre in the carrier frame (metres),
            stbd      = -3700,         --   2 NM to port
            legNm     = 10,
            refreshKm = 5,             -- re-centre when the carrier has moved this far (or turned 20 deg)
            radio     = { mhz = 253.0, mod = 0 },
            tacan     = { channel = 53, mode = "Y", callsign = "RCV" },
        },
    },
    -- -----------------------------------------------------------------------
    -- REFUELING SERVICE
    -- -----------------------------------------------------------------------
    refueling = {
        basket = {
            type    = "KC135MPRS",        -- probe-and-drogue tanker (exact DCS type)
            zone    = "TR_REFUEL_BASKET", -- ME zone (Circle or Quad): a Quad's long side sets the track
            alt     = 6000,               -- altitude in metres
            kias    = 250,                -- indicated airspeed (knots), changeable from the menu
            heading = 090,                -- racetrack heading for a Circle zone
            radio   = { mhz = 251.0, mod = 0 },
            tacan   = { channel = 51, mode = "Y", callsign = "TKR" },
        },
        boom = {
            type    = "KC-135",           -- boom tanker (exact DCS type, keep the hyphen)
            zone    = "TR_REFUEL_BOOM",
            alt     = 7000,
            kias    = 280,
            heading = 090,
            radio   = { mhz = 252.0, mod = 0 },
            tacan   = { channel = 52, mode = "Y", callsign = "TKB" },
        },
        speeds = { 220, 250, 280, 310 },  -- indicated airspeeds (knots) offered in the menu
    },
    -- -----------------------------------------------------------------------
    -- F10 MAP MARKERS: range zones, tanker tracks with their comms, the carrier
    -- and the S-3B track, drawn for the player coalition (switchable from the menu)
    -- -----------------------------------------------------------------------
    markers = {
        enabled = true,
        zones   = true,  -- outlines and names of the range zones
    },
    -- -----------------------------------------------------------------------
    -- GENERAL
    -- -----------------------------------------------------------------------
    coalition = coalition.side.BLUE, -- player coalition: it gets the F10 menu and the assets
}

-- ===========================================================================
-- FINE PARAMETRI EDITABILI: do not edit below this line unless you know the code
-- ===========================================================================

-- ===========================================================================
-- API AVAILABILITY GUARD (fail fast with a visible message)
-- ===========================================================================
if not (trigger and trigger.action and trigger.action.outText
        and coalition and coalition.addGroup and coalition.getPlayers
        and timer and timer.scheduleFunction
        and world and world.addEventHandler
        and missionCommands and missionCommands.addSubMenuForCoalition
        and missionCommands.addCommandForCoalition
        and trigger.misc and trigger.misc.getZone) then
    if trigger and trigger.action and trigger.action.outText then
        trigger.action.outText("[Training Range] Required DCS API missing. Script aborted.", 20)
    end
    return
end

-- ===========================================================================
-- MODULE STATE  (globals per spec; guarded with `or` so a reload keeps state)
-- ===========================================================================
TR_Bombing   = TR_Bombing   or { staticGroups = {}, lightGroups = {}, heavyGroups = {}, convoyGroup = nil,
                                 targets = {}, unitGroup = {}, counted = {},
                                 scores = {} }                         -- [player] = { n, sum, best, bestQ, shacks }
TR_Dogfight  = TR_Dogfight  or { players = {} }                       -- [unitName] = { score, entryTime }
TR_SEAD      = TR_SEAD      or { radarActive = nil, irActive = nil, irGroups = {}, rangeGroups = {},
                                 players = {}, aaaLive = nil,
                                 emitters = {},   -- [groupName] = label, the groups with a radar
                                 spawnSeq = {},   -- [groupName] = n, bumped at every spawn
                                 harm = {},       -- [groupName] = HARM reaction state of that spawn
                                 harmOn = nil }
TR_Carrier   = TR_Carrier   or { spawned = false, recoveryTanker = nil, heading = nil, speed = nil,
                                 roe = "defend", s3Anchor = nil, s3Track = nil }
TR_Refueling = TR_Refueling or { basket = nil, boom = nil, basketKias = nil, boomKias = nil,
                                 tracks = {} }    -- [which] = { wp1, wp2, label } of the tanker in service
TR_Markers   = TR_Markers   or { on = nil, seq = 0, ids = {}, carrierAt = nil }

-- Shared with the other training scripts: every asset that sets a radio,
-- TACAN or ICLS writes itself here, and TRAINING_Comms.lua prints the list.
TRAINING_COMMS = TRAINING_COMMS or { assets = {} }

-- ===========================================================================
-- CONSTANTS
-- ===========================================================================
local KT_TO_MS = 0.514444    -- knots  -> m/s
local MS_TO_KT = 1.94384     -- m/s    -> knots
local NM_M     = 1852

local CONVOY_SPEED = 5.56    -- m/s (~20 km/h); convoy is a slow moving target

-- Enemy ground targets (bombing + SEAD) spawn RED so they oppose the BLUE
-- player; carrier and tankers spawn under the USA (BLUE). Coalition in DCS is
-- decided by the country you spawn under, not by the unit's native nation, so
-- a US unit placed in the "Integrated Defense" preset still ends up RED.
local ENEMY_COUNTRY    = country.id.RUSSIA
local FRIENDLY_COUNTRY = country.id.USA

-- Radar SAM presets. SA-2 and SA-3 carry the P-19 search radar next to their
-- track radar, as the DCS site templates do: the track radar alone has to find
-- targets through its own narrow beam.
local SEAD_RADAR_PRESETS = {
    SA2    = { label = "SA-2",  group = "TR_SAM_SA2",    units = { "SNR_75V", "p-19 s-125 sr", "S_75M_Volhov", "S_75M_Volhov" } },
    SA3    = { label = "SA-3",  group = "TR_SAM_SA3",    units = { "p-19 s-125 sr", "snr s-125 tr", "5p73 s-125 ln", "5p73 s-125 ln" } },
    SA6    = { label = "SA-6",  group = "TR_SAM_SA6",    units = { "Kub 1S91 str", "Kub 2P25 ln", "Kub 2P25 ln" } },
    SA8    = { label = "SA-8",  group = "TR_SAM_SA8",    units = { "Osa 9A33 ln", "Osa 9A33 ln" } },
    SA11   = { label = "SA-11", group = "TR_SAM_SA11",   units = { "SA-11 Buk SR 9S18M1", "SA-11 Buk LN 9A310M1", "SA-11 Buk LN 9A310M1" } },
    HAWK   = { label = "Hawk",  group = "TR_SAM_HAWK",   units = { "Hawk sr", "Hawk tr", "Hawk ln", "Hawk ln" } },
    -- Rapier uses the optical tracker as specified: it engages but does NOT
    -- emit radar, so it will not paint a player's RWR (visual threat only),
    -- and an anti-radiation missile has nothing to home on.
    RAPIER = { label = "Rapier", group = "TR_SAM_RAPIER", optical = true,
               units = { "rapier_fsa_optical_tracker_unit", "rapier_fsa_launcher", "rapier_fsa_launcher" } },
}

-- IR / AAA presets. Missile units and guns spawn as two groups ("<group>" and
-- "<group>_GUNS"), because rules of engagement are per group and the guns are
-- the only thing the missile protection cannot stop. The guns include a
-- radar-laid Shilka, so the guns group counts as an emitter for the HARM
-- reaction; the IR missiles do not.
local SEAD_IR_PRESETS = {
    IR_LIGHT   = { label = "IR (light)",         group = "TR_IR_LIGHT",   units = { "SA-18 Igla manpad", "SA-18 Igla manpad", "Soldier stinger", "Soldier stinger" } },
    AAA        = { label = "AAA",                group = "TR_AAA",        guns  = { "ZSU-23-4 Shilka", "ZSU-23-4 Shilka", "ZU-23 Emplacement", "ZU-23 Emplacement" } },
    INTEGRATED = { label = "Integrated Defense", group = "TR_INTEGRATED", units = { "Strela-10M3", "SA-18 Igla manpad" },
                                                                          guns  = { "ZSU-23-4 Shilka", "Vulcan" } },
}

-- ===========================================================================
-- HELPERS
-- ===========================================================================
local function _out(msg, t)
    trigger.action.outText(tostring(msg), t or 10)
end

local function _msgToUnit(unit, msg, t)
    local ok = pcall(function()
        if trigger.action.outTextForUnit then
            trigger.action.outTextForUnit(unit:getID(), tostring(msg), t or 10)
        else
            -- outTextForGroup needs the numeric group ID, not the name (pitfall #16).
            trigger.action.outTextForGroup(unit:getGroup():getID(), tostring(msg), t or 10)
        end
    end)
    if not ok then _out(msg, t) end
end

local function _round(n) return math.floor(n + 0.5) end

local function _who(u)
    local ok, n = pcall(function() return u:getPlayerName() end)
    if ok and n and n ~= "" then return n end
    return u:getName()
end

-- Ground/terrain height. DCS land.getHeight takes a Vec2 {x, y} where y is the
-- world Z axis (NOT a 3D point). Getting this wrong puts smoke underground or
-- reads AGL against the wrong axis.
local function _groundY(x, z)
    return land.getHeight({ x = x, y = z }) or 0
end

-- true where the ground is not water (targets, the convoy and SAMs need land).
local function _surfaceOk(x, z)
    local st = land.getSurfaceType({ x = x, y = z })
    return st ~= land.SurfaceType.WATER and st ~= land.SurfaceType.SHALLOW_WATER
end

local function _dist2D(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

local function _destroyGroupByName(name)
    if not name then return end
    -- Always re-lookup; a cached Group object goes stale once its last unit
    -- dies and DCS purges the group (pitfall #9).
    local g = Group.getByName(name)
    if g then g:destroy() end
end

-- coalition.addGroup with the error kept: a wrong unit type string (they vary
-- across DCS versions) throws, and the player must see that it failed.
local function _addGroup(countryId, category, groupData, label)
    local grp
    local ok, err = pcall(function() grp = coalition.addGroup(countryId, category, groupData) end)
    if not ok or not grp then
        _out("[Training Range] Spawn failed for " .. (label or groupData.name) .. " (check the unit type strings).", 15)
        env.info("[Training Range] addGroup " .. tostring(groupData.name) .. " error: " .. tostring(err))
        return nil
    end
    return grp
end

-- Apply a task with staggered retries: a single setTask on the same frame as
-- the spawn is frequently dropped (pitfall #1).
local function _applyTaskStaggered(controller, task)
    for _, d in ipairs({ 0.2, 0.7 }) do
        timer.scheduleFunction(function(args)
            pcall(function() args.c:setTask(args.t) end)
            return nil
        end, { c = controller, t = task }, timer.getTime() + d)
    end
end

local function _setImmortal(unit, value)
    pcall(function()
        unit:getController():setCommand({ id = "SetImmortal", params = { value = value } })
    end)
end

-- Standard DCS TACAN channel -> Hz mapping (community-standard formula).
local function _tacanFreq(channel, mode)
    local freq
    if mode == "X" then
        if channel < 64 then freq = (962 + channel - 1) else freq = (1151 + channel - 64) end
    else -- "Y"
        if channel < 64 then freq = (1088 + channel - 1) else freq = (1025 + channel - 64) end
    end
    return freq * 1000000
end

-- Indicated airspeed -> true airspeed (m/s) at an altitude, ISA troposphere.
-- DCS route speeds are true airspeeds; pilots fly indicated.
local function _tasFromKias(kias, altM)
    local sigma = (1 - 2.25577e-5 * altM) ^ 4.25588
    return kias * KT_TO_MS / math.sqrt(sigma)
end

local function _radioText(r)
    if not r then return "-" end
    return string.format("%.3f %s", r.mhz, (r.mod == 1) and "FM" or "AM")
end

local function _tacanText(t)
    if not t then return "-" end
    return string.format("%d%s %s", t.channel, t.mode, t.callsign or "")
end

local function _commsSet(key, entry)
    entry.side = entry.side or TR_Config.coalition
    TRAINING_COMMS.assets[key] = entry
end

-- ---------------------------------------------------------------------------
-- Zones, Circle or Quad. trigger.misc.getZone gives a Quad only its centre and
-- stored radius, as if it were a circle, so the drawn corners are read from
-- env.mission (key "verticies", the DCS spelling; y there means world z).
-- The editor stores them in "Z" order (1-2 one side, 3-4 the opposite side in
-- the same direction), not around the outline: taken as they come, the test
-- sees a bow-tie and half the zone falls outside, and the "longest side" is a
-- diagonal. Sorted by angle around the centre they make the outline whatever
-- the order.
-- A shape is { cx, cz, r } for a circle, plus { poly, minx, maxx, minz, maxz }
-- for a quad (r is then the distance of the farthest corner).
-- ---------------------------------------------------------------------------
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
                    cx, cz = cx / #poly, cz / #poly
                    table.sort(poly, function(a, b) return math.atan2(a.z - cz, a.x - cx) < math.atan2(b.z - cz, b.x - cx) end)
                    q = { poly = poly, cx = cx, cz = cz, r = 0,
                          minx = math.huge, maxx = -math.huge, minz = math.huge, maxz = -math.huge }
                    for _, p in ipairs(poly) do
                        q.r = math.max(q.r, math.sqrt((p.x - cx) ^ 2 + (p.z - cz) ^ 2))
                        q.minx, q.maxx = math.min(q.minx, p.x), math.max(q.maxx, p.x)
                        q.minz, q.maxz = math.min(q.minz, p.z), math.max(q.maxz, p.z)
                    end
                end
                break
            end
        end
        _quadCache[name] = q
    end
    if q then return q end
    -- Circles are not cached: a circle can be attached to a moving unit.
    local c = trigger.misc.getZone(name)
    if c then return { cx = c.point.x, cz = c.point.z, r = c.radius } end
    return nil
end

local function _zone(name)
    local s = _zoneShape(name)
    if not s then _out("[Training Range] Zone not found: " .. tostring(name), 15) end
    return s
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

local function _edgeDist(p, poly)
    local best = math.huge
    for i = 1, #poly do
        local a, b = poly[i], poly[i % #poly + 1]
        local dx, dz = b.x - a.x, b.z - a.z
        local l2 = dx * dx + dz * dz
        local t = (l2 > 0) and math.max(0, math.min(1, ((p.x - a.x) * dx + (p.z - a.z) * dz) / l2)) or 0
        local ex, ez = a.x + t * dx - p.x, a.z + t * dz - p.z
        best = math.min(best, math.sqrt(ex * ex + ez * ez))
    end
    return best
end

-- Uniform random point inside a zone, at least `margin` metres from its edge.
local function _randomPointInShape(s, margin)
    margin = margin or 0
    if not s.poly then
        local r = math.max(0, s.r - margin) * math.sqrt(math.random()) -- sqrt keeps it area-uniform
        local a = math.random() * 2 * math.pi
        return { x = s.cx + r * math.cos(a), z = s.cz + r * math.sin(a) }
    end
    for _ = 1, 200 do
        local p = { x = s.minx + math.random() * (s.maxx - s.minx), z = s.minz + math.random() * (s.maxz - s.minz) }
        if _inShape(p, s) and _edgeDist(p, s.poly) >= margin then return p end
    end
    return { x = s.cx, z = s.cz }
end

local function _randomLandPointInShape(s, margin, tries)
    for _ = 1, (tries or 30) do
        local p = _randomPointInShape(s, margin)
        if _surfaceOk(p.x, p.z) then return p end
    end
    return _randomPointInShape(s, margin) -- give up on land, return anything in zone
end

-- Long axis of a zone: a Quad's longest side (degrees 0-180, map grid) and how
-- far the zone reaches along it on each side of the centre; a Circle uses the
-- fallback heading and its diameter.
local function _shapeAxis(s, fallbackDeg)
    if not s.poly then return fallbackDeg % 180, -s.r, s.r end
    local axis, longest
    for i = 1, #s.poly do
        local a, b = s.poly[i], s.poly[i % #s.poly + 1]
        local l = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
        if not longest or l > longest then
            longest, axis = l, math.deg(math.atan2(b.z - a.z, b.x - a.x)) % 180
        end
    end
    local r = math.rad(axis)
    local fx, fz = math.cos(r), math.sin(r)
    local lo, hi = 0, 0
    for _, p in ipairs(s.poly) do
        local d = (p.x - s.cx) * fx + (p.z - s.cz) * fz
        lo, hi = math.min(lo, d), math.max(hi, d)
    end
    return axis, lo, hi
end

-- ---------------------------------------------------------------------------
-- Ground group spawn: first unit at the centre, the rest on a small ring.
-- Ground spawn tables use x and y as the two HORIZONTAL axes (y = world Z).
-- ---------------------------------------------------------------------------
local function _spawnGround(name, unitTypes, center, countryId)
    local units = {}
    local ring = 90 -- metres
    for i, t in ipairs(unitTypes) do
        local ox, oz = 0, 0
        if i > 1 and #unitTypes > 1 then
            local ang = (i - 1) * (2 * math.pi / (#unitTypes - 1))
            ox, oz = math.cos(ang) * ring, math.sin(ang) * ring
        end
        units[i] = {
            ["type"]    = t,
            ["name"]    = name .. "_" .. i,
            ["x"]       = center.x + ox,
            ["y"]       = center.z + oz, -- spawn y = world z
            ["heading"] = 0,
            ["skill"]   = "High",
        }
    end
    local groupData = {
        ["name"]  = name,
        ["task"]  = "Ground Nothing",
        ["units"] = units,
        ["route"] = { ["points"] = { [1] = {
            ["x"]    = center.x,
            ["y"]    = center.z,
            ["type"] = "Turning Point",
            ["action"] = "Off Road",
            ["speed"]  = 0,
            ["task"]   = { id = "ComboTask", params = { tasks = {} } },
        } } },
    }
    return _addGroup(countryId, Group.Category.GROUND, groupData, name)
end

-- Ground options share the post-spawn binding race, so apply them on a short
-- delay and re-lookup by name. RED alarm keeps SAM radars on so the player's
-- RWR lights up immediately; ROE decides whether they shoot.
local function _setGroundOptions(groupName, roe, alarm)
    timer.scheduleFunction(function()
        local g = Group.getByName(groupName)
        if not g then return nil end
        local ctrl = g:getController()
        pcall(function() ctrl:setOption(AI.Option.Ground.id.ALARM_STATE, alarm) end)
        pcall(function() ctrl:setOption(AI.Option.Ground.id.ROE, roe) end)
        return nil
    end, nil, timer.getTime() + 1.0)
end

local function _setGroundCombatReady(groupName)
    _setGroundOptions(groupName, AI.Option.Ground.val.ROE.OPEN_FIRE, AI.Option.Ground.val.ALARM_STATE.RED)
end

-- Bombing targets must not shoot back (BTR/T-90 carry guns). Weapon hold plus
-- green alarm keeps them passive.
local function _setGroundWeaponHold(groupName)
    _setGroundOptions(groupName, AI.Option.Ground.val.ROE.WEAPON_HOLD, AI.Option.Ground.val.ALARM_STATE.GREEN)
end

-- ---------------------------------------------------------------------------
-- Tankers (Basket, Boom and the carrier S-3B).
-- A working tanker needs THREE things: group task "Refueling" (the tanker
-- role), the enroute "Tanker" task (extends the boom/basket) and an Orbit
-- (Race-Track) that keeps it on a predictable track. Radio and TACAN are set
-- by command after the spawn, when the unit id is known.
-- ---------------------------------------------------------------------------
local function _tankerPoints(wp1, wp2, alt, tas)
    local function wp(p, tasks)
        return {
            ["x"] = p.x, ["y"] = p.z,
            ["alt"] = alt, ["alt_type"] = "BARO",
            ["type"] = "Turning Point", ["action"] = "Turning Point",
            ["speed"] = tas, ["ETA"] = 0, ["ETA_locked"] = false, ["speed_locked"] = true,
            ["task"] = { id = "ComboTask", params = { tasks = tasks or {} } },
        }
    end
    return {
        [1] = wp(wp1, { [1] = { id = "Tanker", params = {} },
                        [2] = { id = "Orbit", params = { pattern = "Race-Track", speed = tas, altitude = alt } } }),
        [2] = wp(wp2),
    }
end

-- Radio and TACAN of an aircraft group, applied after the bind delay.
local function _airComms(groupName, radio, tacan)
    timer.scheduleFunction(function()
        local g = Group.getByName(groupName)
        local u = g and g:getUnits()[1]
        if not u then return nil end
        local ctrl = g:getController()
        if radio then
            pcall(function() ctrl:setCommand({ id = "SetFrequency", params = {
                frequency = radio.mhz * 1000000, modulation = radio.mod or 0, power = 10 } }) end)
        end
        if tacan then
            pcall(function() ctrl:setCommand({ id = "ActivateBeacon", params = {
                ["type"]        = 4,                                -- TACAN
                ["system"]      = (tacan.mode == "X") and 4 or 5,   -- airborne TACAN, X or Y band
                ["callsign"]    = tacan.callsign,
                ["frequency"]   = _tacanFreq(tacan.channel, tacan.mode),
                ["channel"]     = tacan.channel,
                ["modeChannel"] = tacan.mode,
                ["unitId"]      = u:getID(),
                ["bearing"]     = true,
                ["AA"]          = true,
            } }) end)
        end
        return nil
    end, nil, timer.getTime() + 1.5)
end

local function _spawnTanker(opts)
    local p1, p2 = opts.wp1, opts.wp2
    local hdg = math.atan2(p2.z - p1.z, p2.x - p1.x) -- face the far end of the racetrack (x = north, z = east)
    local groupData = {
        ["name"]          = opts.name,
        ["task"]          = "Refueling",
        ["uncontrolled"]  = false,
        ["start_time"]    = 0,
        ["frequency"]     = opts.radio and opts.radio.mhz, -- aircraft groups keep their radio in MHz
        ["modulation"]    = opts.radio and opts.radio.mod,
        ["communication"] = true,
        ["units"] = { [1] = {
            ["type"]     = opts.type,
            ["name"]     = opts.name .. "_1",
            ["x"]        = p1.x, ["y"] = p1.z,
            ["alt"]      = opts.alt, ["alt_type"] = "BARO",
            ["speed"]    = opts.tas,
            ["heading"]  = hdg,
            ["skill"]    = "High",
            ["payload"]  = { ["pylons"] = {}, ["fuel"] = "100000", ["flare"] = 0, ["chaff"] = 0, ["gun"] = 100 },
        } },
        ["route"] = { ["points"] = _tankerPoints(p1, p2, opts.alt, opts.tas) },
    }
    local grp = _addGroup(FRIENDLY_COUNTRY, Group.Category.AIRPLANE, groupData, opts.label or opts.name)
    if grp then _airComms(opts.name, opts.radio, opts.tacan) end
    return grp
end

-- New racetrack or speed for a tanker already flying.
local function _retaskTanker(groupName, wp1, wp2, alt, tas)
    local g = Group.getByName(groupName)
    if not g then return false end
    _applyTaskStaggered(g:getController(), { id = "Mission", params = { route = {
        points = _tankerPoints(wp1, wp2, alt, tas) } } })
    return true
end

-- ---------------------------------------------------------------------------
-- F10 map drawings (trigger.action.*ToAll, DCS 2.7+), for the player
-- coalition, read-only. Each drawing has an id from a block of our own, far
-- from the small numbers the players' own map marks get, and belongs to a
-- key (an asset) so it is removed or redrawn with that asset.
-- ---------------------------------------------------------------------------
local MARK_BASE = 7104000
local MARK_COLORS = {
    bombing  = { 1, 0.55, 0, 1 },
    dogfight = { 1, 0.25, 0.25, 1 },
    sead     = { 0.85, 0.3, 0.85, 1 },
    carrier  = { 0.2, 0.7, 1, 1 },
    tanker   = { 0.2, 0.85, 0.55, 1 },
}

local function _markOn()
    return TR_Markers.on and trigger.action.markupToAll ~= nil and trigger.action.removeMark ~= nil
end

local function _markNew(key)
    TR_Markers.seq = TR_Markers.seq + 1
    local id = MARK_BASE + TR_Markers.seq
    TR_Markers.ids[key] = TR_Markers.ids[key] or {}
    table.insert(TR_Markers.ids[key], id)
    return id
end

local function _markClear(key)
    for _, id in ipairs(TR_Markers.ids[key] or {}) do
        pcall(function() trigger.action.removeMark(id) end)
    end
    TR_Markers.ids[key] = nil
end

local function _v3(x, z) return { x = x, y = 0, z = z } end
local function _alpha(c, a) return { c[1], c[2], c[3], a } end

local function _markText(key, x, z, text, color)
    local id = _markNew(key)
    pcall(function() trigger.action.textToAll(TR_Config.coalition, id, _v3(x, z), color, { 0, 0, 0, 0.35 }, 12, true, text) end)
end

-- A zone as drawn in the editor, with its name above the northern edge.
local function _markZone(key, zoneName, label, color)
    local s = _zoneShape(zoneName); if not s then return end
    local id, side, fill = _markNew(key), TR_Config.coalition, _alpha(color, 0.08)
    if s.poly and #s.poly == 4 then
        local p = s.poly
        pcall(function() trigger.action.quadToAll(side, id, _v3(p[1].x, p[1].z), _v3(p[2].x, p[2].z),
            _v3(p[3].x, p[3].z), _v3(p[4].x, p[4].z), color, fill, 1, true, "") end)
    elseif s.poly then
        local args = { 7, side, id } -- freeform polygon
        for _, q in ipairs(s.poly) do args[#args + 1] = _v3(q.x, q.z) end
        for _, a in ipairs({ color, fill, 1, true, "" }) do args[#args + 1] = a end
        pcall(function() trigger.action.markupToAll(unpack(args)) end)
    else
        pcall(function() trigger.action.circleToAll(side, id, _v3(s.cx, s.cz), s.r, color, fill, 1, true, "") end)
    end
    _markText(key, (s.poly and s.maxx or (s.cx + s.r)) + 800, s.cz, label, color)
end

-- A racetrack: the leg the aircraft flies, its two turn points and a label
-- beside the middle of the leg.
local function _markTrack(key, wp1, wp2, color, label)
    _markClear(key)
    if not _markOn() then return end
    local side = TR_Config.coalition
    local id = _markNew(key)
    pcall(function() trigger.action.lineToAll(side, id, _v3(wp1.x, wp1.z), _v3(wp2.x, wp2.z), color, 2, true, "") end)
    for _, p in ipairs({ wp1, wp2 }) do
        local cid = _markNew(key)
        pcall(function() trigger.action.circleToAll(side, cid, _v3(p.x, p.z), 600, color, _alpha(color, 0.25), 1, true, "") end)
    end
    local dx, dz = wp2.x - wp1.x, wp2.z - wp1.z
    local l = math.max(1, math.sqrt(dx * dx + dz * dz))
    _markText(key, (wp1.x + wp2.x) / 2 - dz / l * 2500, (wp1.z + wp2.z) / 2 + dx / l * 2500, label, color)
end

-- The carrier: a 1 NM ring on the ship and its comms line.
local function _markCarrier()
    _markClear("carrier")
    TR_Markers.carrierAt = nil
    if not _markOn() then return end
    local c = TR_Config.carrier
    local u = Unit.getByName(c.unitName); if not u then return end
    local p = u:getPoint()
    local id = _markNew("carrier")
    pcall(function() trigger.action.circleToAll(TR_Config.coalition, id, _v3(p.x, p.z), NM_M, MARK_COLORS.carrier,
        _alpha(MARK_COLORS.carrier, 0.15), 1, true, "") end)
    local parts = { c.unitName .. " (" .. c.type .. ")", _radioText(c.radio) }
    if c.tacan then parts[#parts + 1] = "TACAN " .. _tacanText(c.tacan) end
    if c.icls then parts[#parts + 1] = "ICLS " .. c.icls.channel end
    parts[#parts + 1] = string.format("BRC %03d", _round(TR_Carrier.heading or c.heading) % 360)
    _markText("carrier", p.x + NM_M + 800, p.z, table.concat(parts, " | "), MARK_COLORS.carrier)
    TR_Markers.carrierAt = { x = p.x, z = p.z, h = TR_Carrier.heading or c.heading }
end

-- ===========================================================================
-- MODULE: BOMBING RANGE
-- ===========================================================================
-- Three target kinds, each with its own ME zone, unit type, name prefix and
-- tracking list in TR_Bombing.
local BOMB_KINDS = {
    static = { zoneKey = "zone",      unitKey = "staticUnit", prefix = "TR_STATIC_",  listKey = "staticGroups", label = "unarmoured" },
    light  = { zoneKey = "lightZone", unitKey = "lightUnit",  prefix = "TR_ARMOR_L_", listKey = "lightGroups",  label = "light armour" },
    heavy  = { zoneKey = "heavyZone", unitKey = "heavyUnit",  prefix = "TR_ARMOR_H_", listKey = "heavyGroups",  label = "heavy armour" },
}

-- A target group is forgotten BEFORE it is destroyed, so a despawn never
-- counts as a kill whatever event the destroy may raise.
local function _bombingForget(gname)
    TR_Bombing.targets[gname] = nil
    for uname, g in pairs(TR_Bombing.unitGroup) do
        if g == gname then TR_Bombing.unitGroup[uname] = nil; TR_Bombing.counted[uname] = nil end
    end
end

local function _bombingTrack(gname, unitNames)
    TR_Bombing.targets[gname] = #unitNames
    for _, uname in ipairs(unitNames) do
        TR_Bombing.unitGroup[uname] = gname
        TR_Bombing.counted[uname] = nil
    end
end

local function _bombingClearKind(kind)
    local k = BOMB_KINDS[kind]
    for _, name in ipairs(TR_Bombing[k.listKey]) do
        _bombingForget(name)
        _destroyGroupByName(name)
    end
    TR_Bombing[k.listKey] = {}
end

-- Rejection sampling for N land points at least minSpacing apart inside the zone.
local function _generateSpacedPoints(shape, count, minSpacing, margin)
    local pts, attempts, maxAttempts = {}, 0, count * 60
    while #pts < count and attempts < maxAttempts do
        attempts = attempts + 1
        local p = _randomPointInShape(shape, margin)
        local ok = _surfaceOk(p.x, p.z)
        if ok then
            for _, q in ipairs(pts) do
                if _dist2D(p, q) < minSpacing then ok = false break end
            end
        end
        if ok then pts[#pts + 1] = p end
    end
    return pts
end

local function _shapeArea(s)
    if not s.poly then return math.pi * s.r * s.r end
    local a = 0
    for i = 1, #s.poly do
        local p, q = s.poly[i], s.poly[i % #s.poly + 1]
        a = a + p.x * q.z - q.x * p.z
    end
    return math.abs(a) / 2
end

local function _bombingSpawn(kind, count)
    local k = BOMB_KINDS[kind]; if not k then return end
    local zone = _zone(TR_Config.bombing[k.zoneKey]); if not zone then return end
    _bombingClearKind(kind)
    -- A small zone cannot hold many targets 500 m apart: the spacing shrinks to
    -- what the zone's area allows (never below 100 m) instead of placing fewer.
    local spacing = TR_Config.bombing.minSpacing
    local fit = 0.7 * math.sqrt(_shapeArea(zone) / count)
    if fit < spacing then spacing = math.max(100, fit) end
    local pts = _generateSpacedPoints(zone, count, spacing, 100)
    -- Random placement near the packing limit misses the last point now and
    -- then: try again a little tighter rather than place fewer.
    while #pts < count and spacing > 100 do
        spacing = math.max(100, spacing * 0.85)
        pts = _generateSpacedPoints(zone, count, spacing, 100)
    end
    if #pts < count then
        _out("[Bombing Range] Only placed " .. #pts .. " of " .. count .. " (spacing/zone limit).", 12)
    elseif spacing < TR_Config.bombing.minSpacing then
        _out(string.format("[Bombing Range] Targets %d m apart to fit the zone.", _round(spacing)), 8)
    end
    local unit, placed = TR_Config.bombing[k.unitKey], 0
    for i, p in ipairs(pts) do
        local name = k.prefix .. i
        if _spawnGround(name, { unit }, p, ENEMY_COUNTRY) then
            _setGroundWeaponHold(name) -- targets never shoot back
            TR_Bombing[k.listKey][#TR_Bombing[k.listKey] + 1] = name
            _bombingTrack(name, { name .. "_1" })
            local sx, sz = p.x + 50, p.z -- smoke 50 m to the side so it marks each target
            trigger.action.smoke({ x = sx, y = _groundY(sx, sz), z = sz }, TR_Config.bombing.smokeColor)
            placed = placed + 1
        end
    end
    if placed > 0 then _out("[Bombing Range] Spawned " .. placed .. " " .. k.label .. " target(s).", 10) end
end

local function _bombingSpawnConvoy()
    local zone = _zone(TR_Config.bombing.zone); if not zone then return end
    if TR_Bombing.convoyGroup then
        _bombingForget(TR_Bombing.convoyGroup)
        _destroyGroupByName(TR_Bombing.convoyGroup)
        TR_Bombing.convoyGroup = nil
    end

    local wps = {}
    for i = 1, 4 do wps[i] = _randomLandPointInShape(zone, 200, 40) end

    -- Lead heading toward WP2 (x = north, z = east); trail units sit behind it in column.
    local hdg = math.atan2(wps[2].z - wps[1].z, wps[2].x - wps[1].x)
    local units = {}
    for i = 1, 3 do
        local back = (i - 1) * 25
        units[i] = {
            ["type"]    = "BRDM-2",
            ["name"]    = "TR_CONVOY_" .. i,
            ["x"]       = wps[1].x - math.cos(hdg) * back,
            ["y"]       = wps[1].z - math.sin(hdg) * back,
            ["heading"] = hdg,
            ["skill"]   = "High",
        }
    end

    -- Four points and back to the first, for the whole mission: the last point
    -- switches the route to point 1 again.
    local points = {}
    for i = 1, 4 do
        points[i] = {
            ["x"] = wps[i].x, ["y"] = wps[i].z,
            ["type"] = "Turning Point", ["action"] = "Off Road", ["speed"] = CONVOY_SPEED,
            ["task"] = { id = "ComboTask", params = { tasks = {} } },
        }
    end
    points[4].task.params.tasks[1] = { id = "WrappedAction", params = { action = {
        id = "SwitchWaypoint", params = { fromWaypointIndex = 4, goToWaypointIndex = 1 } } } }

    local groupData = {
        ["name"]  = "TR_CONVOY",
        ["task"]  = "Ground Nothing",
        ["units"] = units,
        ["route"] = { ["points"] = points },
    }
    if not _addGroup(ENEMY_COUNTRY, Group.Category.GROUND, groupData, "convoy") then return end
    _setGroundWeaponHold("TR_CONVOY") -- BRDM-2 has a gun, keep it passive
    TR_Bombing.convoyGroup = "TR_CONVOY"
    _bombingTrack("TR_CONVOY", { "TR_CONVOY_1", "TR_CONVOY_2", "TR_CONVOY_3" })
    _out("[Bombing Range] Convoy of 3 BRDM-2 rolling.", 10)
end

local function _bombingReset()
    _bombingClearKind("static")
    _bombingClearKind("light")
    _bombingClearKind("heavy")
    if TR_Bombing.convoyGroup then
        _bombingForget(TR_Bombing.convoyGroup)
        _destroyGroupByName(TR_Bombing.convoyGroup)
        TR_Bombing.convoyGroup = nil
    end
    TR_Bombing.targets, TR_Bombing.unitGroup, TR_Bombing.counted = {}, {}, {}
    _out("[Bombing Range] Reset done.")
end

-- ===========================================================================
-- MODULE: DOGFIGHT ZONE  (automatic, no menu, players just fly in)
-- ===========================================================================
local function _dogfightTick()
    local zone = _zoneShape(TR_Config.dogfight.zone); if not zone then return end
    local players = coalition.getPlayers(TR_Config.coalition) or {}
    local seen = {}
    for _, u in pairs(players) do
        if u and u.isExist and u:isExist() then
            local name = u:getName()
            seen[name] = true
            local p = u:getPoint()
            local agl = p.y - _groundY(p.x, p.z)
            local active = _inShape(p, zone) and (agl >= TR_Config.dogfight.minAGL)
            if active and not TR_Dogfight.players[name] then
                _setImmortal(u, true) -- effective for the host and in single player
                TR_Dogfight.players[name] = { score = 0, entryTime = timer.getTime() }
                _msgToUnit(u, "[Dogfight] Arena ON. Missiles between arena players are removed before impact " ..
                              "and count as a kill; guns score +1 per hit (in multiplayer guns do real damage). " ..
                              "Leave the zone or drop below " .. TR_Config.dogfight.minAGL .. " m AGL to exit.", 15)
            elseif (not active) and TR_Dogfight.players[name] then
                local s = TR_Dogfight.players[name].score
                _setImmortal(u, false)
                TR_Dogfight.players[name] = nil
                _msgToUnit(u, "[Dogfight] Left the arena. Final score: " .. s .. ".", 12)
            end
        end
    end
    -- Drop players that despawned entirely.
    for name in pairs(TR_Dogfight.players) do
        if not seen[name] then TR_Dogfight.players[name] = nil end
    end
end

local function _dogfightReset()
    for name in pairs(TR_Dogfight.players) do
        local u = Unit.getByName(name)
        if u then _setImmortal(u, false) end
    end
    TR_Dogfight.players = {}
    _out("[Dogfight] Reset. Scores cleared.")
end

-- ===========================================================================
-- MODULE: SEAD RANGE
-- ===========================================================================
-- Players inside either zone get the Immortal command (it works for the host
-- and in single player); the missile protection below works for everyone.
local function _seadTick()
    local zr = _zoneShape(TR_Config.sead.radarZone)
    local zi = _zoneShape(TR_Config.sead.irZone)
    if not zr and not zi then return end
    local players = coalition.getPlayers(TR_Config.coalition) or {}
    local seen = {}
    for _, u in pairs(players) do
        if u and u.isExist and u:isExist() then
            local name = u:getName()
            seen[name] = true
            local p = u:getPoint()
            local inside = _inShape(p, zr) or _inShape(p, zi)
            if inside and not TR_SEAD.players[name] then
                _setImmortal(u, true)
                TR_SEAD.players[name] = true
                _msgToUnit(u, "[SEAD] In the range. SAM and MANPADS missiles from the range are removed before " ..
                              "impact. AAA: " .. (TR_SEAD.aaaLive and "LIVE FIRE." or "radar on, holding fire."), 15)
            elseif (not inside) and TR_SEAD.players[name] then
                _setImmortal(u, false)
                TR_SEAD.players[name] = nil
                _msgToUnit(u, "[SEAD] Left the range.", 12)
            end
        end
    end
    for name in pairs(TR_SEAD.players) do
        if not seen[name] then TR_SEAD.players[name] = nil end
    end
end

local function _seadGunsROE()
    return TR_SEAD.aaaLive and AI.Option.Ground.val.ROE.OPEN_FIRE or AI.Option.Ground.val.ROE.WEAPON_HOLD
end

-- A range group is added and removed through these two, so the missile
-- protection, the HARM reaction and any timer still pending for an older
-- spawn of the same name all agree on what is on the range.
local function _seadAdd(gname, label)
    TR_SEAD.rangeGroups[gname] = true
    TR_SEAD.emitters[gname] = label -- nil for groups with no radar
    TR_SEAD.spawnSeq[gname] = (TR_SEAD.spawnSeq[gname] or 0) + 1
    TR_SEAD.harm[gname] = nil
end

local function _seadDrop(gname)
    TR_SEAD.rangeGroups[gname], TR_SEAD.emitters[gname], TR_SEAD.harm[gname] = nil, nil, nil
    TR_SEAD.spawnSeq[gname] = (TR_SEAD.spawnSeq[gname] or 0) + 1
    _destroyGroupByName(gname)
end

local function _harmNote()
    return TR_SEAD.harmOn and " Radars shut down when an anti-radiation missile comes at them." or ""
end

local function _seadRemoveIRGroups()
    for _, g in ipairs(TR_SEAD.irGroups) do _seadDrop(g) end
    TR_SEAD.irGroups, TR_SEAD.irActive = {}, nil
end

local function _seadSpawnRadar(key)
    local preset = SEAD_RADAR_PRESETS[key]; if not preset then return end
    local zone = _zone(TR_Config.sead.radarZone); if not zone then return end
    if TR_SEAD.radarActive then -- one radar preset at a time
        _seadDrop(TR_SEAD.radarActive)
        TR_SEAD.radarActive = nil
    end
    local center = _randomLandPointInShape(zone, 500) -- keep the cluster off the edge
    if not _spawnGround(preset.group, preset.units, center, ENEMY_COUNTRY) then return end
    _setGroundCombatReady(preset.group)
    TR_SEAD.radarActive = preset.group
    _seadAdd(preset.group, (not preset.optical) and preset.label or nil)
    _out("[SEAD] Radar SAM active: " .. preset.label .. " (" .. preset.group .. ")." ..
         ((not preset.optical) and _harmNote() or ""), 10)
end

local function _seadSpawnIR(key)
    local preset = SEAD_IR_PRESETS[key]; if not preset then return end
    local zone = _zone(TR_Config.sead.irZone); if not zone then return end
    _seadRemoveIRGroups() -- one IR preset at a time
    local center = _randomLandPointInShape(zone, 500)
    local spawned = false
    if preset.units and _spawnGround(preset.group, preset.units, center, ENEMY_COUNTRY) then
        _setGroundCombatReady(preset.group)
        TR_SEAD.irGroups[#TR_SEAD.irGroups + 1] = preset.group
        _seadAdd(preset.group, nil)
        spawned = true
    end
    if preset.guns then
        local gname = preset.group .. "_GUNS"
        local gc = { x = center.x + 150, z = center.z } -- guns next to the missiles, not on top
        if _spawnGround(gname, preset.guns, gc, ENEMY_COUNTRY) then
            _setGroundOptions(gname, _seadGunsROE(), AI.Option.Ground.val.ALARM_STATE.RED)
            TR_SEAD.irGroups[#TR_SEAD.irGroups + 1] = gname
            _seadAdd(gname, preset.label .. " guns")
            spawned = true
        end
    end
    if not spawned then return end
    TR_SEAD.irActive = key
    _out("[SEAD] IR/AAA active: " .. preset.label .. (preset.guns and (TR_SEAD.aaaLive and " (AAA live fire)." or
         " (AAA radar on, holding fire).") or "."), 10)
end

local function _seadToggleAAA()
    TR_SEAD.aaaLive = not TR_SEAD.aaaLive
    for _, g in ipairs(TR_SEAD.irGroups) do
        local h = TR_SEAD.harm[g]
        if g:sub(-5) == "_GUNS" and not (h and h.off) then -- a site hiding from a HARM stays dark
            _setGroundOptions(g, _seadGunsROE(), AI.Option.Ground.val.ALARM_STATE.RED)
        end
    end
    _out("[SEAD] AAA " .. (TR_SEAD.aaaLive and "LIVE FIRE: guns can hit you, they cannot be intercepted." or
         "holding fire (radar still on)."), 12)
end

local function _seadRemoveRadar()
    if TR_SEAD.radarActive then
        _seadDrop(TR_SEAD.radarActive)
        TR_SEAD.radarActive = nil
        _out("[SEAD] Radar SAM removed.")
    else
        _out("[SEAD] No active radar SAM.")
    end
end

local function _seadRemoveIR()
    if TR_SEAD.irActive then
        _seadRemoveIRGroups()
        _out("[SEAD] IR/AAA removed.")
    else
        _out("[SEAD] No active IR/AAA.")
    end
end

local function _seadReset()
    if TR_SEAD.radarActive then
        _seadDrop(TR_SEAD.radarActive)
        TR_SEAD.radarActive = nil
    end
    _seadRemoveIRGroups()
    for name in pairs(TR_SEAD.players) do
        local u = Unit.getByName(name)
        if u then _setImmortal(u, false) end
    end
    TR_SEAD.players = {}
    _out("[SEAD] Reset done.")
end

-- ===========================================================================
-- MISSILE PROTECTION
-- ---------------------------------------------------------------------------
-- On S_EVENT_SHOT the missile is followed; the distance to the protected
-- players is checked more often as it closes (5 s far out, every frame in the
-- last kilometre) and the missile is destroyed before it can reach them. A
-- missile fired by the range's SAMs protects every player; a missile fired by
-- a dogfight player protects the other arena players and scores the shooter.
-- ===========================================================================
local function _protectCandidates(m)
    local out = {}
    if m.kind == "dogfight" then
        for name in pairs(TR_Dogfight.players) do
            if name ~= m.shooterName then
                local u = Unit.getByName(name)
                if u and u:isExist() then out[#out + 1] = u end
            end
        end
    else
        for _, side in ipairs({ coalition.side.BLUE, coalition.side.RED }) do
            for _, u in pairs(coalition.getPlayers(side) or {}) do
                if u and u:isExist() then out[#out + 1] = u end
            end
        end
    end
    return out
end

local function _onProtectedHit(m, u, d)
    if m.kind == "dogfight" then
        local rec = TR_Dogfight.players[m.shooterName]
        if rec then rec.score = rec.score + 1 end
        local s = Unit.getByName(m.shooterName)
        if s then _msgToUnit(s, string.format("[Dogfight] %s kill on %s. Score: %d", m.name, _who(u), rec and rec.score or 0), 10) end
        _msgToUnit(u, string.format("[Dogfight] %s from %s would have hit you. Missile removed.", m.name, m.shooterWho), 10)
    else
        _msgToUnit(u, string.format("[SEAD] HIT: %s (%s) would have hit you, removed at %d m.", m.name, m.launcher, _round(d)), 12)
    end
end

local function _trackMissile(m)
    local P = TR_Config.protection
    local limit = m.big and P.destroyBigM or P.destroyM
    timer.scheduleFunction(function(_, t)
        local ok, nxt = pcall(function()
            local w = m.weapon
            if not w:isExist() then
                -- Gone without us: decoyed, out of energy or into the ground.
                if m.nearName and m.nearD < 5000 then
                    local u = Unit.getByName(m.nearName)
                    if u then _msgToUnit(u, string.format("[%s] %s defeated, closest %d m.",
                        (m.kind == "dogfight") and "Dogfight" or "SEAD", m.name, _round(m.nearD)), 10) end
                end
                return nil
            end
            local wp = w:getPoint()
            local best, bd
            for _, u in ipairs(_protectCandidates(m)) do
                local up = u:getPoint()
                local d = math.sqrt((up.x - wp.x) ^ 2 + (up.y - wp.y) ^ 2 + (up.z - wp.z) ^ 2)
                if not bd or d < bd then best, bd = u, d end
            end
            if not best then return t + 1 end
            if not m.nearD or bd < m.nearD then m.nearD, m.nearName = bd, best:getName() end
            if bd <= limit then
                pcall(function() w:destroy() end)
                pcall(function() trigger.action.explosion(wp, 0.1) end) -- a puff to show where it was
                _onProtectedHit(m, best, bd)
                return nil
            end
            local dt = (bd > 50000 and 5) or (bd > 10000 and 1) or (bd > 5000 and 0.5) or (bd > 1500 and 0.1) or 0.01
            return t + dt
        end)
        if not ok then
            env.info("[Training Range] missile tracking error: " .. tostring(nxt))
            return nil
        end
        return nxt
    end, nil, timer.getTime() + 0.05)
end

local function _protectShot(event, w, s, desc)
    if not TR_Config.protection.enabled then return end
    if desc.category ~= Weapon.Category.MISSILE then return end
    local mc = desc.missileCategory
    if mc and Weapon.MissileCategory and mc ~= Weapon.MissileCategory.AAM and mc ~= Weapon.MissileCategory.SAM then return end
    local sName = s:getName()
    local gname
    pcall(function() local g = s:getGroup(); gname = g and g:getName() end)
    local kind
    if gname and TR_SEAD.rangeGroups[gname] then kind = "sead"
    elseif TR_Dogfight.players[sName] then kind = "dogfight" end
    if not kind then return end
    local mass = (desc.warhead and desc.warhead.explosiveMass) or 0
    _trackMissile({
        weapon = w, kind = kind, shooterName = sName, shooterWho = _who(s),
        launcher = (s.getTypeName and s:getTypeName()) or "SAM",
        name = desc.displayName or (w.getTypeName and w:getTypeName()) or "missile",
        big = mass > TR_Config.protection.bigKg,
    })
end

-- ===========================================================================
-- HARM REACTION
-- ---------------------------------------------------------------------------
-- An anti-radiation missile (passive radar guidance) fired at a range SAM
-- makes the site switch its radar off after the crew's reaction time, and
-- back on a while after the missile has gone, as a real site does to survive:
-- the shooter sees it drop off the RWR, and the missile has to manage without
-- the emitter. The site is the missile's target when the launch had one,
-- otherwise the emitter the missile is flying at. The radar goes dark with
-- the emission switch (DCS 2.7+) and the green alarm state, which also works
-- on older versions.
-- ===========================================================================
local ARM_NAMES = { "AGM_88", "AGM_122", "AGM_45", "ALARM", "LD%-10", "X_58", "X_28", "X_25MP", "X_31P" }

-- Passive radar guidance says it; the type name says it for the known ARMs
-- when a build gives no guidance field.
local function _isARM(w, desc)
    if desc.category ~= Weapon.Category.MISSILE then return false end
    local rp = Weapon.GuidanceType and Weapon.GuidanceType.RADAR_PASSIVE
    if rp and desc.guidance == rp then return true end
    local tn = (w.getTypeName and w:getTypeName()) or ""
    for _, pat in ipairs(ARM_NAMES) do
        if tn:find(pat) then return true end
    end
    return false
end

local function _harmSite(w)
    local tgt
    pcall(function() tgt = w:getTarget() end)
    if tgt and tgt.getGroup then
        local ok, gname = pcall(function() return tgt:getGroup():getName() end)
        if ok and gname then return TR_SEAD.emitters[gname] and gname or nil end
    end
    local okp, pos = pcall(function() return w:getPosition() end)
    if not okp or not pos then return nil end
    local C = TR_Config.sead
    local hdg = math.deg(math.atan2(pos.x.z, pos.x.x))
    local best, ba
    for gname in pairs(TR_SEAD.emitters) do
        local g = Group.getByName(gname)
        local u = g and g:getUnits()[1]
        if u then
            local sp = u:getPoint()
            local d = _dist2D(sp, pos.p)
            local a = math.abs((math.deg(math.atan2(sp.z - pos.p.z, sp.x - pos.p.x)) - hdg + 540) % 360 - 180)
            if d <= C.harmReachKm * 1000 and a <= C.harmConeDeg and (not ba or a < ba) then best, ba = gname, a end
        end
    end
    return best
end

-- Radar on or off. Back on, the site takes the rules it was spawned with.
local function _seadEmit(gname, on)
    local g = Group.getByName(gname); if not g then return end
    if g.enableEmission then pcall(function() g:enableEmission(on) end) end
    local ctrl = g:getController()
    local A = AI.Option.Ground
    pcall(function() ctrl:setOption(A.id.ALARM_STATE, on and A.val.ALARM_STATE.RED or A.val.ALARM_STATE.GREEN) end)
    if on then
        local roe = (gname:sub(-5) == "_GUNS") and _seadGunsROE() or A.val.ROE.OPEN_FIRE
        pcall(function() ctrl:setOption(A.id.ROE, roe) end)
    end
end

-- Players who care: the shooters and everyone in the SEAD range.
local function _harmTell(shooters, msg)
    local told = {}
    for _, list in ipairs({ TR_SEAD.players, shooters }) do
        for name in pairs(list) do
            local u = not told[name] and Unit.getByName(name)
            if u then _msgToUnit(u, msg, 10); told[name] = true end
        end
    end
end

local function _harmShot(event, w, s, desc)
    if not TR_SEAD.harmOn or not _isARM(w, desc) then return end
    local gname = _harmSite(w); if not gname then return end
    local C = TR_Config.sead
    local seq = TR_SEAD.spawnSeq[gname]
    local st = TR_SEAD.harm[gname]
    if not st or st.seq ~= seq then
        st = { seq = seq, inbound = 0, off = false, pendingOff = false, shooters = {} }
        TR_SEAD.harm[gname] = st
    end
    st.inbound = st.inbound + 1
    st.back = nil -- a new missile cancels a pending switch-on
    local label = TR_SEAD.emitters[gname]
    if s and s.getName then st.shooters[s:getName()] = true end
    local function current() return TR_SEAD.spawnSeq[gname] == seq and TR_SEAD.harm[gname] == st end

    if not st.off and not st.pendingOff then
        st.pendingOff = true
        timer.scheduleFunction(function()
            if not current() then return nil end
            st.pendingOff = false
            if st.inbound <= 0 then return nil end -- the missile is already down
            st.off = true
            _seadEmit(gname, false)
            _harmTell(st.shooters, "[SEAD] " .. label .. " radar OFF: anti-radiation missile inbound.")
            return nil
        end, nil, timer.getTime() + math.random(C.harmDelay[1], C.harmDelay[2]))
    end

    -- Follow the missile; when the last one is gone, back on after a while.
    timer.scheduleFunction(function(_, t)
        local alive = false
        pcall(function() alive = w:isExist() end)
        if alive then return t + 1 end
        if not current() then return nil end
        st.inbound = st.inbound - 1
        if st.inbound > 0 then return nil end
        local token = {}
        st.back = token
        timer.scheduleFunction(function()
            if not current() or st.back ~= token then return nil end
            if st.off then
                st.off = false
                _seadEmit(gname, true)
                _harmTell(st.shooters, "[SEAD] " .. label .. " radar back ON.")
            end
            return nil
        end, nil, timer.getTime() + math.random(C.harmOff[1], C.harmOff[2]))
        return nil
    end, nil, timer.getTime() + 1)
end

local function _seadToggleHarm()
    TR_SEAD.harmOn = not TR_SEAD.harmOn
    if not TR_SEAD.harmOn then -- sites still hiding come back up now
        for gname, st in pairs(TR_SEAD.harm) do
            if st.off then _seadEmit(gname, true) end
        end
        TR_SEAD.harm = {}
    end
    _out("[SEAD] HARM reaction " .. (TR_SEAD.harmOn and
         "ON: radar SAMs switch off when an anti-radiation missile comes at them." or
         "OFF: radar SAMs keep emitting whatever comes at them."), 12)
end

-- ===========================================================================
-- BOMBING SCORES
-- ---------------------------------------------------------------------------
-- Every bomb, rocket and air-to-ground missile a player releases near the
-- range is followed to the ground, polled more often as it gets close. The
-- impact point is where its last position and direction meet the terrain
-- (land.getIP); a weapon that vanishes in the air (a cluster dispenser
-- opening) is carried on in free fall to the ground. The score is the distance
-- from the nearest range target, with the clock position seen along the
-- attack heading (12 o'clock = long, 6 o'clock = short). Target positions
-- are kept from the last seconds of the fall, so a target the weapon has
-- just destroyed still counts. A salvo (ripple, rocket pod) is one message.
-- ===========================================================================
local _scorePending = {} -- [shooter unit name] = { who, list, token }

local function _scoreTargets()
    local out = {}
    for uname in pairs(TR_Bombing.unitGroup) do
        local u = Unit.getByName(uname)
        if u and u:isExist() then
            local p = u:getPoint()
            out[#out + 1] = { x = p.x, z = p.z, type = u:getTypeName() }
        end
    end
    return out
end

local function _bombZones()
    local b, out = TR_Config.bombing, {}
    for _, zn in ipairs({ b.zone, b.lightZone, b.heavyZone }) do
        local s = _zoneShape(zn)
        if s then out[#out + 1] = s end
    end
    return out
end

local function _grade(d)
    local g = TR_Config.scoring.goodM
    if d <= 1.53 then return "SHACK" end
    if d <= g / 2 then return "EXCELLENT" end
    if d <= g then return "GOOD" end
    if d <= 2 * g then return "INEFFECTIVE" end
    return "POOR"
end

local function _clock(relDeg)
    local c = math.floor((relDeg % 360) / 30 + 0.5) % 12
    return ((c == 0) and 12 or c) .. " o'clock"
end

local function _scoreText(r)
    if r.miss then return "no target within " .. TR_Config.scoring.radius .. " m" end
    return string.format("%d m at %s from %s, %s", _round(r.d), r.clock, r.target, r.q)
end

local function _scoreFlush(key)
    local p = _scorePending[key]
    _scorePending[key] = nil
    if not p or #p.list == 0 then return end
    local list, name = p.list, p.list[1].name
    for _, r in ipairs(list) do
        if r.name ~= name then name = "weapons" break end
    end
    local text
    if #list == 1 then
        text = name .. (list[1].burst and " (opened in the air)" or "") .. ": " .. _scoreText(list[1])
    else
        local best, sum, n = nil, 0, 0
        for _, r in ipairs(list) do
            if not r.miss then
                n, sum = n + 1, sum + r.d
                if not best or r.d < best.d then best = r end
            end
        end
        if best then
            text = string.format("%d x %s: best %s, average %d m (%d of %d scored)", #list, name, _scoreText(best),
                                 _round(sum / n), n, #list)
        else
            text = string.format("%d x %s: %s", #list, name, _scoreText(list[1]))
        end
    end
    local s = TR_Bombing.scores[p.who]
    local tail = s and string.format(" | %s: %d scored, average %d m.", p.who, s.n, _round(s.sum / s.n)) or "."
    local u = Unit.getByName(key)
    if u then _msgToUnit(u, "[Bombing Range] " .. text .. tail, 15) end
end

local function _scoreImpact(m, ip)
    local S = TR_Config.scoring
    local best, bd
    for _, t in ipairs(m.snap or {}) do
        local d = math.sqrt((t.x - ip.x) ^ 2 + (t.z - ip.z) ^ 2)
        if not bd or d < bd then best, bd = t, d end
    end
    local r = { name = m.name, burst = m.burst }
    if best and bd <= S.radius then
        r.d, r.target, r.q = bd, best.type, _grade(bd)
        r.clock = _clock(math.deg(math.atan2(ip.z - best.z, ip.x - best.x)) - m.attackHdg)
        local rec = TR_Bombing.scores[m.who] or { n = 0, sum = 0, shacks = 0 }
        rec.n, rec.sum = rec.n + 1, rec.sum + bd
        if not rec.best or bd < rec.best then rec.best, rec.bestQ = bd, r.q end
        if r.q == "SHACK" then rec.shacks = rec.shacks + 1 end
        TR_Bombing.scores[m.who] = rec
    else
        local onRange = false
        for _, z in ipairs(_bombZones()) do
            if _inShape(ip, z) then onRange = true break end
        end
        if not onRange then return end -- not on the range: nothing to say
        r.miss = true
    end
    local p = _scorePending[m.shooter] or { who = m.who, list = {} }
    _scorePending[m.shooter] = p
    p.list[#p.list + 1] = r
    local token = {}
    p.token = token
    timer.scheduleFunction(function()
        if _scorePending[m.shooter] == p and p.token == token then _scoreFlush(m.shooter) end
        return nil
    end, nil, timer.getTime() + 1.5)
end

local function _scoreTrack(m)
    timer.scheduleFunction(function(_, t)
        local ok, nxt = pcall(function()
            local w = m.weapon
            if w:isExist() then
                local pos, v = w:getPosition(), w:getVelocity()
                local p = pos.p
                local agl = p.y - _groundY(p.x, p.z)
                local speed = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
                local tti = (v.y < -1) and (agl / -v.y) or 60
                if tti < 3 then m.snap = _scoreTargets() end
                m.pos, m.vel, m.agl, m.speed = pos, v, agl, speed
                if t - m.t0 > 300 then return nil end
                -- poll faster as the ground gets close, and never let the weapon
                -- move more than 150 m between two looks
                m.dt = math.max(0.02, math.min(1, tti / 4, 150 / math.max(speed, 1)))
                return t + m.dt
            end
            if not m.pos then return nil end
            local p, v = m.pos.p, m.vel
            local ip
            pcall(function() ip = land.getIP(p, m.pos.x, math.max(50, m.speed * m.dt * 2)) end)
            if not ip then
                -- Gone in the air (a dispenser opening, a fuze): on in free fall
                -- from the last position and velocity down to the ground.
                local d = -v.y
                local tt = (m.agl > 0) and (-d + math.sqrt(d * d + 2 * 9.81 * m.agl)) / 9.81 or 0
                ip = { x = p.x + v.x * tt, y = 0, z = p.z + v.z * tt }
                m.burst = m.agl > 30
            end
            _scoreImpact(m, ip)
            return nil
        end)
        if not ok then
            env.info("[Training Range] weapon scoring error: " .. tostring(nxt))
            return nil
        end
        return nxt
    end, nil, timer.getTime() + 0.1)
end

local function _scoreShot(event, w, s, desc)
    local S = TR_Config.scoring
    if not S.enabled then return end
    local okp, who = pcall(function() return s:getPlayerName() end)
    if not okp or not who or who == "" then return end -- players only
    local c = desc.category
    local wanted = (c == Weapon.Category.BOMB) or (S.rockets and c == Weapon.Category.ROCKET)
    if not wanted and S.missiles and c == Weapon.Category.MISSILE then
        wanted = Weapon.MissileCategory and desc.missileCategory == Weapon.MissileCategory.OTHER and not _isARM(w, desc)
    end
    if not wanted then return end
    local sp = s:getPoint()
    local near = false
    for _, z in ipairs(_bombZones()) do
        if _dist2D(sp, { x = z.cx, z = z.cz }) <= S.trackKm * 1000 + z.r then near = true break end
    end
    if not near then return end
    local v = s:getVelocity()
    local hdg
    if math.sqrt(v.x * v.x + v.z * v.z) > 5 then
        hdg = math.deg(math.atan2(v.z, v.x))
    else
        local o = s:getPosition().x
        hdg = math.deg(math.atan2(o.z, o.x))
    end
    _scoreTrack({
        weapon = w, shooter = s:getName(), who = who, attackHdg = hdg, t0 = timer.getTime(),
        name = desc.displayName or (w.getTypeName and w:getTypeName()) or "weapon",
        snap = _scoreTargets(),
    })
end

local function _scoreBoard()
    local rows = {}
    for who, s in pairs(TR_Bombing.scores) do rows[#rows + 1] = { who = who, s = s, avg = s.sum / s.n } end
    if #rows == 0 then _out("[Bombing Range] No scored impacts yet.", 10); return end
    table.sort(rows, function(a, b) return a.avg < b.avg end)
    local lines = { "[Bombing Range] Scores, average distance from the target:" }
    for i, r in ipairs(rows) do
        lines[#lines + 1] = string.format("%d. %s: %d weapon(s), average %d m, best %d m (%s)%s", i, r.who, r.s.n,
            _round(r.avg), _round(r.s.best), r.s.bestQ, (r.s.shacks > 0) and (", " .. r.s.shacks .. " shack(s)") or "")
    end
    _out(table.concat(lines, "\n"), 25)
end

local function _scoreClear()
    TR_Bombing.scores = {}
    _out("[Bombing Range] Scores cleared.", 8)
end

-- One S_EVENT_SHOT, three independent users: an error in one does not stop
-- the others.
local function _onShot(event)
    if not (Weapon and Weapon.Category) then return end
    local w, s = event.weapon, event.initiator
    if not (w and s and s.getName and w.getDesc) then return end
    local desc = w:getDesc() or {}
    for _, f in ipairs({ _protectShot, _harmShot, _scoreShot }) do
        local ok, err = pcall(f, event, w, s, desc)
        if not ok then env.info("[Training Range] shot handler error: " .. tostring(err)) end
    end
end

-- ===========================================================================
-- MODULE: CARRIER OPS
-- ===========================================================================
local ROE_NAVAL    = (AI.Option.Naval and AI.Option.Naval.val.ROE) or AI.Option.Ground.val.ROE
local ROE_NAVAL_ID = (AI.Option.Naval and AI.Option.Naval.id.ROE) or AI.Option.Ground.id.ROE

-- Wind at the deck. atmosphere.getWind returns the vector the wind blows
-- TOWARD (x = north, z = east); the meteorological "from" is that + 180.
local function _carrierWind(cp)
    local w = atmosphere.getWind({ x = cp.x, y = cp.y + 20, z = cp.z })
    local to = math.deg(math.atan2(w.z, w.x))
    return (to + 180) % 360, math.sqrt(w.x * w.x + w.z * w.z) * MS_TO_KT
end

-- How far a ship can steam from p on a heading before land: sampled every
-- kilometre, stopping 3 km short of the first land.
local function _seaRoom(p, headingDeg, maxM)
    local r = math.rad(headingDeg)
    local fx, fz = math.cos(r), math.sin(r)
    for d = 1000, maxM, 1000 do
        if _surfaceOk(p.x + fx * d, p.z + fz * d) then return math.max(0, d - 3000) end
    end
    return maxM
end

-- Shuttle route: out `leg` metres on the heading, back to `home`, and round
-- again (the last point switches to the second), so the group stays near its
-- zone for the whole mission instead of stopping after one leg.
local function _shipRoute(from, headingDeg, leg, speedMS, home)
    local r = math.rad(headingDeg)
    local out = { x = from.x + math.cos(r) * leg, z = from.z + math.sin(r) * leg }
    local function wp(p, tasks)
        return { ["x"] = p.x, ["y"] = p.z, ["type"] = "Turning Point", ["action"] = "Turning Point",
                 ["speed"] = speedMS, ["ETA"] = 0, ["ETA_locked"] = false,
                 ["task"] = { id = "ComboTask", params = { tasks = tasks or {} } } }
    end
    local loop = { [1] = { id = "WrappedAction", params = { action = {
        id = "SwitchWaypoint", params = { fromWaypointIndex = 3, goToWaypointIndex = 2 } } } } }
    return { [1] = wp(from), [2] = wp(out), [3] = wp(home, loop) }
end

-- Apply the group ROE: ENGAGE = weapons free, DEFEND = return fire only (so the
-- group does not open up on ground units it sails past).
local function _carrierApplyROE()
    local g = Group.getByName(TR_Config.carrier.groupName)
    if not g then return end
    local val = (TR_Carrier.roe == "engage") and ROE_NAVAL.OPEN_FIRE or ROE_NAVAL.RETURN_FIRE
    pcall(function() g:getController():setOption(ROE_NAVAL_ID, val) end)
end

-- TACAN, ICLS, Link 4 and ACLS on the carrier, by command (unit id needed).
local function _carrierComms()
    local c = TR_Config.carrier
    local u = Unit.getByName(c.unitName); if not u then return end
    local ctrl = u:getGroup():getController()
    local id = u:getID()
    local function cmd(t) pcall(function() ctrl:setCommand(t) end) end
    if c.tacan then
        cmd({ id = "ActivateBeacon", params = {
            ["type"] = 4, ["system"] = 3, -- TACAN, ship/ground system
            ["callsign"] = c.tacan.callsign, ["frequency"] = _tacanFreq(c.tacan.channel, c.tacan.mode),
            ["channel"] = c.tacan.channel, ["modeChannel"] = c.tacan.mode,
            ["unitId"] = id, ["bearing"] = true, ["AA"] = false } })
    end
    if c.icls then
        cmd({ id = "ActivateICLS", params = { ["type"] = 131584, ["channel"] = c.icls.channel, ["unitId"] = id,
                                              ["callsign"] = c.icls.callsign, ["name"] = c.icls.callsign } })
    end
    if c.link4 then
        cmd({ id = "ActivateLink4", params = { ["frequency"] = c.link4.mhz * 1000000, ["unitId"] = id,
                                               ["name"] = c.link4.callsign } })
        if c.acls then cmd({ id = "ActivateACLS", params = { ["unitId"] = id, ["name"] = c.link4.callsign } }) end
    end
end

local function _carrierCommsLine()
    local c = TR_Config.carrier
    local parts = { "Radio " .. _radioText(c.radio) }
    if c.tacan then parts[#parts + 1] = "TACAN " .. _tacanText(c.tacan) end
    if c.icls then parts[#parts + 1] = "ICLS " .. c.icls.channel end
    if c.link4 then parts[#parts + 1] = string.format("Link 4 %.3f", c.link4.mhz) end
    if c.link4 and c.acls then parts[#parts + 1] = "ACLS" end
    return table.concat(parts, " | ")
end

local function _carrierRegister()
    local c = TR_Config.carrier
    _commsSet("TR.carrier", {
        order = 10, title = "Carrier " .. c.unitName .. " (" .. c.type .. ")", group = c.groupName,
        radio = c.radio, tacan = c.tacan, icls = c.icls, link4 = c.link4, acls = c.link4 and c.acls,
        note = string.format("BRC %03d, %d kt", _round(TR_Carrier.heading or c.heading) % 360,
                             _round(TR_Carrier.speed or c.speed)),
    })
end

-- Re-route the formation on a heading at a speed, as a shuttle through its
-- zone. Returns the sea room in metres on that heading (0 = no room, not steered).
local function _carrierSteer(headingDeg, speedKt)
    local c = TR_Config.carrier
    local u = Unit.getByName(c.unitName)
    if not u then return nil end
    local cp = u:getPoint()
    local leg = _seaRoom(cp, headingDeg, c.boxLegNm * NM_M)
    if leg < 3000 then return 0 end
    local zone = _zoneShape(c.zone)
    local home = zone and { x = zone.cx, z = zone.cz } or { x = cp.x, z = cp.z }
    _applyTaskStaggered(u:getGroup():getController(), { id = "Mission", params = { route = {
        points = _shipRoute(cp, headingDeg, leg, speedKt * KT_TO_MS, home) } } })
    return leg
end

local function _carrierSpawn()
    local c = TR_Config.carrier
    if Unit.getByName(c.unitName) then
        _out("[Carrier] Already on station."); return
    end
    local zone = _zone(c.zone); if not zone then return end
    TR_Carrier.speed   = TR_Carrier.speed or c.speed
    TR_Carrier.heading = TR_Carrier.heading or c.heading
    local cx, cz = zone.cx, zone.cz
    local h = math.rad(TR_Carrier.heading)       -- commanded heading (0 = north, clockwise)
    local fwdx, fwdz = math.cos(h), math.sin(h)  -- carrier-frame forward (x = north, z = east)
    local stbx, stbz = -math.sin(h), math.cos(h) -- carrier-frame starboard (to the right)

    -- Unit 1 is the carrier (the recovery reference); ships keep their radio
    -- per unit, in Hz. The escorts follow in the screen defined in TR_Config.
    local units = { [1] = {
        ["type"] = c.type, ["name"] = c.unitName,
        ["x"] = cx, ["y"] = cz, ["heading"] = h, ["skill"] = "High",
        ["frequency"] = c.radio and c.radio.mhz * 1000000, ["modulation"] = c.radio and c.radio.mod,
    } }
    for i, e in ipairs(c.escorts or {}) do
        local ox = e.fwd * fwdx + e.stbd * stbx
        local oz = e.fwd * fwdz + e.stbd * stbz
        units[#units + 1] = {
            ["type"] = e.type, ["name"] = c.groupName .. "_ESC" .. i,
            ["x"] = cx + ox, ["y"] = cz + oz, ["heading"] = h, ["skill"] = "High",
        }
    end

    local home = { x = cx, z = cz }
    local leg = math.max(_seaRoom(home, TR_Carrier.heading, c.boxLegNm * NM_M), 2000)
    local groupData = {
        ["name"]  = c.groupName,
        ["task"]  = "Nothing",
        ["units"] = units,
        ["route"] = { ["points"] = _shipRoute(home, TR_Carrier.heading, leg, TR_Carrier.speed * KT_TO_MS, home) },
    }
    local grp = _addGroup(FRIENDLY_COUNTRY, Group.Category.SHIP, groupData, "carrier strike group")
    TR_Carrier.spawned = (grp ~= nil)
    if not grp then return end
    timer.scheduleFunction(function() _carrierApplyROE(); _carrierComms(); return nil end, nil, timer.getTime() + 1.5)
    _carrierRegister()
    _markCarrier()
    _out(string.format("[Carrier] Strike group on station, steaming %03d at %d kt (carrier plus %d escorts).\n%s",
         _round(TR_Carrier.heading) % 360, _round(TR_Carrier.speed), #units - 1, _carrierCommsLine()), 15)
end

-- Is the sun up? Mission date and clock (local time; the theatre's UTC offset
-- below), NOAA solar position. Good to a few minutes: it only picks the CASE.
local UTC_OFFSET = { Caucasus = 4, Syria = 3, PersianGulf = 4, Nevada = -8, MarianaIslands = 10,
                     SinaiMap = 2, Sinai = 2, Kola = 3, Afghanistan = 4.5, Falklands = -3,
                     Normandy = 1, TheChannel = 1, Iraq = 3, GermanyCW = 1 }

local function _sunElevation(p)
    local ok, lat, lon = pcall(function() return coord.LOtoLL({ x = p.x, y = 0, z = p.z }) end)
    if not ok or not lat then return 45 end
    local d = (env.mission and env.mission.date) or {}
    local mdays = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    local doy = d.Day or 1
    for m = 1, (d.Month or 1) - 1 do doy = doy + mdays[m] end
    local utc = (timer.getAbsTime() % 86400) / 3600 - (UTC_OFFSET[env.mission and env.mission.theatre] or 0)
    local g = 2 * math.pi / 365 * (doy - 1 + (utc - 12) / 24)
    local decl = 0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g) - 0.006758 * math.cos(2 * g)
               + 0.000907 * math.sin(2 * g) - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g)
    local eqt = 229.18 * (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g)
               - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g))
    local ha = math.rad((utc * 60 + eqt + 4 * lon) / 4 - 180)
    local la = math.rad(lat)
    return math.deg(math.asin(math.sin(la) * math.sin(decl) + math.cos(la) * math.cos(decl) * math.cos(ha)))
end

-- CASE from daylight, ceiling and visibility (CASE I: day, ceiling 3000 ft and
-- 5 NM; CASE II: day, ceiling 1000 ft and 5 NM; else CASE III). A ceiling is a
-- broken or overcast layer: old-style density 5+ or cloud presets 13+ / rainy.
local function _caseAdvice(cp)
    local w = (env.mission and env.mission.weather) or {}
    local ceilingFt
    local cl = w.clouds
    if cl then
        local n = tonumber(tostring(cl.preset or ""):match("(%d+)$"))
        local rainy = tostring(cl.preset or ""):find("Rain") ~= nil
        if (cl.preset and cl.preset ~= "" and ((n and n >= 13) or rainy)) or ((not cl.preset or cl.preset == "") and (cl.density or 0) >= 5) then
            ceilingFt = (cl.base or 0) * 3.28084
        end
    end
    local visNm = ((w.visibility and w.visibility.distance) or 80000) / NM_M
    if w.enable_fog and w.fog and (w.fog.visibility or 0) > 0 then visNm = math.min(visNm, w.fog.visibility / NM_M) end
    if _sunElevation(cp) < -6 then return "CASE III", "night" end
    local ceil = ceilingFt and string.format("ceiling %d ft", _round(ceilingFt / 100) * 100) or "no ceiling"
    local why = string.format("day, %s, visibility %d NM", ceil, _round(visNm))
    if (not ceilingFt or ceilingFt >= 3000) and visNm >= 5 then return "CASE I", why end
    if (not ceilingFt or ceilingFt >= 1000) and visNm >= 5 then return "CASE II", why end
    return "CASE III", why
end

local function _carrierRecovery()
    local c = TR_Config.carrier
    local u = Unit.getByName(c.unitName)
    if not u then _out("[Carrier] Carrier not on station."); return end
    local from, kt = _carrierWind(u:getPoint())
    local calm = kt < 3
    -- Into the wind with the angled deck in line: BRC = wind + deck angle.
    local brc = calm and (TR_Carrier.heading or c.heading) or ((from + c.deckAngle) % 360)
    local speed = _round(math.max(5, math.min(c.maxSpeedKt, c.recoveryWodKt - (calm and 0 or kt))))
    local leg = _carrierSteer(brc, speed)
    if not leg then _out("[Carrier] Carrier not on station."); return end
    if leg == 0 then
        _out(string.format("[Carrier] No sea room on BRC %03d: recovery course not set.", _round(brc) % 360), 15)
        return
    end
    TR_Carrier.heading, TR_Carrier.speed = brc, speed
    _carrierRegister()
    _markCarrier()
    _out(string.format("[Carrier] Recovery: BRC %03d at %d kt | wind %s | WOD ~%d kt | %.0f NM of sea room.",
         _round(brc) % 360, speed, calm and "calm" or string.format("%d kt from %03d", _round(kt), _round(from) % 360),
         _round(speed + (calm and 0 or kt)), leg / NM_M), 15)
end

local function _carrierDeckStatus()
    local c = TR_Config.carrier
    local u = Unit.getByName(c.unitName)
    if not u then _out("[Carrier] Carrier not on station."); return end
    local cp = u:getPoint()
    local from, kt = _carrierWind(cp)
    local brc = TR_Carrier.heading or c.heading
    local speed = TR_Carrier.speed or c.speed
    local wod = speed + kt * math.cos(math.rad(from - brc)) -- ship speed + headwind component
    local case, why = _caseAdvice(cp)
    _out(string.format("[Carrier] Deck status: %s (%s) | BRC %03d at %d kt | wind %s | WOD %d kt\n%s",
         case, why, _round(brc) % 360, _round(speed),
         (kt < 3) and "calm" or string.format("%d kt from %03d", _round(kt), _round(from) % 360),
         _round(wod), _carrierCommsLine()), 20)
end

local function _carrierSetSpeed(kt)
    local leg = _carrierSteer(TR_Carrier.heading or TR_Config.carrier.heading, kt)
    if not leg then _out("[Carrier] Carrier not on station."); return end
    if leg == 0 then _out("[Carrier] No sea room on the current course: speed not changed. Call recovery to turn.", 12); return end
    TR_Carrier.speed = kt
    _carrierRegister()
    _out("[Carrier] Speed set to " .. kt .. " kt.", 10)
end

local function _carrierSetROE(mode)
    TR_Carrier.roe = (mode == "engage") and "engage" or "defend"
    timer.scheduleFunction(function() _carrierApplyROE(); return nil end, nil, timer.getTime() + 0.3)
    _out("[Carrier] Group ROE: " ..
         (TR_Carrier.roe == "engage" and "ENGAGE (weapons free)." or "DEFEND only (return fire)."), 10)
end

-- Recovery tanker racetrack in the carrier frame: centre at (fwd, stbd) from
-- the carrier, legs along its course.
local function _s3Track()
    local c = TR_Config.carrier
    local rt = c.recoveryTanker
    local u = Unit.getByName(c.unitName)
    local cp = u and u:getPoint()
    if not cp then
        local z = _zoneShape(c.zone)
        if not z then return nil end
        cp = { x = z.cx, y = 0, z = z.cz }
    end
    local hdg = TR_Carrier.heading or c.heading
    local h = math.rad(hdg)
    local fx, fz = math.cos(h), math.sin(h)
    local sx, sz = -math.sin(h), math.cos(h)
    local mx = cp.x + fx * rt.fwd + sx * rt.stbd
    local mz = cp.z + fz * rt.fwd + sz * rt.stbd
    local half = rt.legNm * NM_M / 2
    return { x = mx - fx * half, z = mz - fz * half }, { x = mx + fx * half, z = mz + fz * half },
           { x = cp.x, z = cp.z, h = hdg }
end

local function _s3Mark(wp1, wp2)
    local rt = TR_Config.carrier.recoveryTanker
    local label = string.format("S-3B recovery tanker | %s | TACAN %s | %d ft, %d KIAS", _radioText(rt.radio),
                                _tacanText(rt.tacan), _round(rt.alt * 3.28084 / 100) * 100, rt.kias)
    TR_Carrier.s3Track = { wp1 = wp1, wp2 = wp2, label = label }
    _markTrack("s3", wp1, wp2, MARK_COLORS.tanker, label)
end

local function _s3Unmark()
    TR_Carrier.s3Track = nil
    _markClear("s3")
end

local function _carrierTanker()
    if TR_Carrier.recoveryTanker and Group.getByName(TR_Carrier.recoveryTanker) then
        _out("[Carrier] Recovery tanker already airborne."); return
    end
    local rt = TR_Config.carrier.recoveryTanker
    local wp1, wp2, anchor = _s3Track()
    if not wp1 then _out("[Carrier] Carrier not on station and zone not found."); return end
    local grp = _spawnTanker({
        name = "TR_S3_TANKER", label = "S-3B recovery tanker", type = rt.type,
        alt = rt.alt, tas = _tasFromKias(rt.kias, rt.alt), wp1 = wp1, wp2 = wp2,
        radio = rt.radio, tacan = rt.tacan,
    })
    if not grp then return end
    TR_Carrier.recoveryTanker, TR_Carrier.s3Anchor = "TR_S3_TANKER", anchor
    _commsSet("TR.s3", {
        order = 11, title = "Recovery tanker (" .. rt.type .. ")", group = "TR_S3_TANKER",
        radio = rt.radio, tacan = rt.tacan,
        note = string.format("%d ft, %d KIAS, over the carrier", _round(rt.alt * 3.28084 / 100) * 100, rt.kias),
    })
    _s3Mark(wp1, wp2)
    _out(string.format("[Carrier] S-3B recovery tanker airborne | %s | TACAN %s | %d KIAS.",
         _radioText(rt.radio), _tacanText(rt.tacan), rt.kias), 15)
end

-- Keeps the S-3B racetrack over the carrier as it steams away or turns.
local function _s3Tick()
    local name = TR_Carrier.recoveryTanker
    if not (name and Group.getByName(name)) then return end
    local rt = TR_Config.carrier.recoveryTanker
    local wp1, wp2, anchor = _s3Track()
    if not wp1 then return end
    local a = TR_Carrier.s3Anchor
    local moved = a and _dist2D(a, anchor) or math.huge
    local turned = a and math.abs((anchor.h - a.h + 540) % 360 - 180) or 180
    if moved > rt.refreshKm * 1000 or turned > 20 then
        if _retaskTanker(name, wp1, wp2, rt.alt, _tasFromKias(rt.kias, rt.alt)) then
            TR_Carrier.s3Anchor = anchor
            _s3Mark(wp1, wp2)
        end
    end
end

local function _carrierRemoveTanker()
    if TR_Carrier.recoveryTanker then
        _destroyGroupByName(TR_Carrier.recoveryTanker)
        TR_Carrier.recoveryTanker, TR_Carrier.s3Anchor = nil, nil
        _s3Unmark()
        _out("[Carrier] S-3B recovery tanker removed.")
    else
        _out("[Carrier] No recovery tanker airborne.")
    end
end

-- Players sitting on the deck (on the ground within 400 m of the carrier):
-- respawning the ship under them drops them in the sea.
local function _deckPlayers()
    local u = Unit.getByName(TR_Config.carrier.unitName)
    if not u then return 0 end
    local cp, n = u:getPoint(), 0
    for _, side in ipairs({ coalition.side.BLUE, coalition.side.RED }) do
        for _, p in pairs(coalition.getPlayers(side) or {}) do
            if p and p:isExist() and not p:inAir() and _dist2D(p:getPoint(), cp) < 400 then n = n + 1 end
        end
    end
    return n
end

local function _carrierRespawn()
    local n = _deckPlayers()
    if n > 0 then
        _out("[Carrier] Respawn refused: " .. n .. " aircraft on deck.", 12)
        return
    end
    _destroyGroupByName(TR_Config.carrier.groupName)
    _destroyGroupByName(TR_Carrier.recoveryTanker)
    TR_Carrier.spawned, TR_Carrier.recoveryTanker, TR_Carrier.s3Anchor = false, nil, nil
    _s3Unmark()
    TR_Carrier.heading = TR_Config.carrier.heading
    _carrierSpawn() -- back on station at the zone (and on the map)
end

-- ===========================================================================
-- MODULE: REFUELING SERVICE
-- ===========================================================================
local _refuelNames = { basket = "TR_TANKER_BASKET", boom = "TR_TANKER_BOOM" }

local function _refuelLabel(which) return (which == "basket") and "Basket" or "Boom" end

-- Racetrack inside the zone: along a Quad's long side (or the configured
-- heading for a Circle), as long as the zone allows once the turns are in
-- (an AI tanker turns at about 25 degrees of bank).
local function _refuelTrack(which)
    local c = TR_Config.refueling[which]
    local shape = _zone(c.zone); if not shape then return nil end
    local kias = TR_Refueling[which .. "Kias"] or c.kias
    local tas = _tasFromKias(kias, c.alt)
    local axis, lo, hi = _shapeAxis(shape, c.heading)
    local turnR = tas * tas / (9.81 * math.tan(math.rad(25)))
    local half = math.max(5000, ((hi - lo) - 2 * turnR) / 2)
    local mid = (hi + lo) / 2
    local r = math.rad(axis)
    local fx, fz = math.cos(r), math.sin(r)
    local mx, mz = shape.cx + fx * mid, shape.cz + fz * mid
    return { x = mx - fx * half, z = mz - fz * half }, { x = mx + fx * half, z = mz + fz * half }, kias, tas, axis
end

local function _refuelRegister(which, kias, axis, wp1, wp2)
    local c = TR_Config.refueling[which]
    _commsSet("TR." .. which, {
        order = (which == "basket") and 20 or 21,
        title = "Tanker " .. _refuelLabel(which) .. " (" .. c.type .. ")", group = _refuelNames[which],
        radio = c.radio, tacan = c.tacan,
        note = string.format("FL%03d, %d KIAS, track %03d/%03d, %d NM legs", _round(c.alt * 3.28084 / 100), kias,
                             _round(axis) % 360, (_round(axis) + 180) % 360, _round(_dist2D(wp1, wp2) / NM_M)),
    })
    -- and on the F10 map: the track with the comms beside it
    local label = string.format("%s tanker (%s) | %s | TACAN %s | FL%03d, %d KIAS", _refuelLabel(which), c.type,
                                _radioText(c.radio), _tacanText(c.tacan), _round(c.alt * 3.28084 / 100), kias)
    TR_Refueling.tracks[which] = { wp1 = wp1, wp2 = wp2, label = label }
    _markTrack("tanker." .. which, wp1, wp2, MARK_COLORS.tanker, label)
end

local function _refuelSpawn(which)
    local c = TR_Config.refueling[which]
    local label = _refuelLabel(which)
    if TR_Refueling[which] and Group.getByName(TR_Refueling[which]) then
        _out("[Refueling] " .. label .. " tanker already in service."); return
    end
    local wp1, wp2, kias, tas, axis = _refuelTrack(which); if not wp1 then return end
    TR_Refueling[which .. "Kias"] = kias
    local name = _refuelNames[which]
    local grp = _spawnTanker({
        name = name, label = label .. " tanker", type = c.type, alt = c.alt, tas = tas,
        wp1 = wp1, wp2 = wp2, radio = c.radio, tacan = c.tacan,
    })
    if not grp then return end
    TR_Refueling[which] = name
    _refuelRegister(which, kias, axis, wp1, wp2)
    _out(string.format("[Refueling] Tanker %s | %s | TACAN %s | FL%03d, %d KIAS | track %03d/%03d, %d NM legs.",
         label, _radioText(c.radio), _tacanText(c.tacan), _round(c.alt * 3.28084 / 100), kias,
         _round(axis) % 360, (_round(axis) + 180) % 360, _round(_dist2D(wp1, wp2) / NM_M)), 15)
end

-- Change a live tanker's speed (re-task its racetrack at the new airspeed).
local function _refuelSetSpeed(which, kias)
    TR_Refueling[which .. "Kias"] = kias
    local name = TR_Refueling[which]
    if not (name and Group.getByName(name)) then
        _out("[Refueling] " .. _refuelLabel(which) .. " tanker not in service (" .. kias .. " KIAS kept for the next one).")
        return
    end
    local c = TR_Config.refueling[which]
    local wp1, wp2, _, tas, axis = _refuelTrack(which); if not wp1 then return end
    _retaskTanker(name, wp1, wp2, c.alt, tas)
    _refuelRegister(which, kias, axis, wp1, wp2)
    _out(string.format("[Refueling] %s tanker speed set to %d KIAS.", _refuelLabel(which), kias), 10)
end

local function _refuelUnmark(which)
    TR_Refueling.tracks[which] = nil
    _markClear("tanker." .. which)
end

local function _refuelRemove(which)
    local label = _refuelLabel(which)
    if TR_Refueling[which] then
        _destroyGroupByName(TR_Refueling[which])
        TR_Refueling[which] = nil
        _refuelUnmark(which)
        _out("[Refueling] " .. label .. " tanker removed.")
    else
        _out("[Refueling] No " .. label .. " tanker in service.")
    end
end

local function _refuelReset()
    _destroyGroupByName(TR_Refueling.basket); TR_Refueling.basket = nil
    _destroyGroupByName(TR_Refueling.boom);   TR_Refueling.boom = nil
    _refuelUnmark("basket"); _refuelUnmark("boom")
    _out("[Refueling] Reset done.")
end

-- ===========================================================================
-- F10 MAP: zones, refresh, toggle
-- ===========================================================================
local function _markZones()
    _markClear("zones")
    if not (_markOn() and TR_Config.markers.zones) then return end
    local b, s, C = TR_Config.bombing, TR_Config.sead, MARK_COLORS
    _markZone("zones", b.zone,      "Bombing range: trucks and convoy", C.bombing)
    _markZone("zones", b.lightZone, "Bombing range: light armour",      C.bombing)
    _markZone("zones", b.heavyZone, "Bombing range: heavy armour",      C.bombing)
    _markZone("zones", TR_Config.dogfight.zone, "Dogfight arena (players)", C.dogfight)
    _markZone("zones", s.radarZone, "SEAD range: radar SAM", C.sead)
    _markZone("zones", s.irZone,    "SEAD range: IR / AAA",  C.sead)
end

local function _markAll()
    _markZones()
    for which, name in pairs(_refuelNames) do
        local t = TR_Refueling.tracks[which]
        if t and Group.getByName(name) then _markTrack("tanker." .. which, t.wp1, t.wp2, MARK_COLORS.tanker, t.label)
        else _markClear("tanker." .. which) end
    end
    local s3 = TR_Carrier.s3Track
    if s3 and TR_Carrier.recoveryTanker and Group.getByName(TR_Carrier.recoveryTanker) then
        _markTrack("s3", s3.wp1, s3.wp2, MARK_COLORS.tanker, s3.label)
    else
        _markClear("s3")
    end
    _markCarrier()
end

-- Every 30 s: the carrier ring follows the ship, and the tracks of tankers
-- that are gone on their own (shot down, out of fuel) are taken off.
local function _markTick()
    if not _markOn() then return end
    local c = TR_Config.carrier
    local u = Unit.getByName(c.unitName)
    local a = TR_Markers.carrierAt
    if u then
        local h = TR_Carrier.heading or c.heading
        if not a or _dist2D(a, u:getPoint()) > NM_M or math.abs((h - a.h + 540) % 360 - 180) > 1 then _markCarrier() end
    elseif a then
        _markClear("carrier")
        TR_Markers.carrierAt = nil
    end
    for which, name in pairs(_refuelNames) do
        if TR_Markers.ids["tanker." .. which] and not Group.getByName(name) then _refuelUnmark(which) end
    end
    if TR_Markers.ids.s3 and not (TR_Carrier.recoveryTanker and Group.getByName(TR_Carrier.recoveryTanker)) then
        _s3Unmark()
    end
end

local function _markToggle()
    if not trigger.action.markupToAll then
        _out("[Training Range] Map drawings need DCS 2.7 or later.", 10)
        return
    end
    TR_Markers.on = not TR_Markers.on
    if TR_Markers.on then
        _markAll()
    else
        for key in pairs(TR_Markers.ids) do _markClear(key) end
        TR_Markers.carrierAt = nil
    end
    _out("[Training Range] F10 map drawings " .. (TR_Markers.on and "ON." or "OFF."), 8)
end

-- ===========================================================================
-- GLOBAL RESET
-- ===========================================================================
-- The carrier is not respawned here (players may be on its deck): it is only
-- put back if it is missing. "Respawn carrier" in Carrier Ops does the rest.
local function _resetAll()
    _bombingReset()
    _seadReset()
    _dogfightReset()
    _refuelReset()
    if not Unit.getByName(TR_Config.carrier.unitName) then _carrierSpawn() end
    _out("[Training Range] All modules reset (carrier left on station).", 12)
end

-- ===========================================================================
-- EVENT HANDLER  (single handler, dispatch by event.id, pcall-guarded)
-- ===========================================================================
-- Bombing kills. S_EVENT_DEAD does not always come (a vehicle that burns out
-- later may never raise it), so S_EVENT_UNIT_LOST counts too; each unit is
-- counted once, looked up by the name it was spawned with.
local function _onUnitGone(event)
    local u = event.initiator
    if not u or not u.getName then return end
    local okn, uname = pcall(function() return u:getName() end)
    if not okn or not uname then return end
    local gname = TR_Bombing.unitGroup[uname]
    if not gname or TR_Bombing.counted[uname] or not TR_Bombing.targets[gname] then return end
    TR_Bombing.counted[uname] = true

    local okt, utype = pcall(function() return u:getTypeName() end)
    _out("[Bombing Range] Target destroyed: " .. ((okt and utype) or "target"), 10)
    TR_Bombing.targets[gname] = TR_Bombing.targets[gname] - 1
    if TR_Bombing.targets[gname] <= 0 then TR_Bombing.targets[gname] = nil end
    if next(TR_Bombing.targets) == nil then
        _out("[Bombing Range] All targets eliminated.", 12)
    end
end

local function _onHit(event)
    local ini, tgt = event.initiator, event.target
    if not ini or not tgt or not ini.getName or not tgt.getName then return end
    local iName, tName = ini:getName(), tgt:getName()
    local rec = TR_Dogfight.players[iName]
    if rec and TR_Dogfight.players[tName] then
        rec.score = rec.score + 1
        _msgToUnit(ini, "[Dogfight] Hit on " .. _who(tgt) .. "! Score: " .. rec.score, 8)
    end
end

local _eventHandler = {}
function _eventHandler:onEvent(event)
    -- DCS silently eats errors thrown inside event handlers (pitfall #7).
    local ok, err = pcall(function()
        if not event then return end
        local id = event.id
        if id == world.event.S_EVENT_DEAD or (world.event.S_EVENT_UNIT_LOST and id == world.event.S_EVENT_UNIT_LOST) then
            _onUnitGone(event)
        elseif id == world.event.S_EVENT_HIT then
            _onHit(event)
        elseif id == world.event.S_EVENT_SHOT then
            _onShot(event)
        end
    end)
    if not ok then env.info("[Training Range] onEvent error: " .. tostring(err)) end
end

-- ===========================================================================
-- RADIO MENU (F10), for the player coalition only
-- ===========================================================================
local function _menu(name, parent) return missionCommands.addSubMenuForCoalition(TR_Config.coalition, name, parent) end
local function _cmd(name, parent, fn) return missionCommands.addCommandForCoalition(TR_Config.coalition, name, parent, fn) end

local function _buildMenu()
    local root = _menu("Training Range")

    -- Bombing Range
    local mB = _menu("Bombing Range", root)
    for _, kind in ipairs({ { "static", "Static (Ural)" }, { "light", "Light armour (BTR-80)" }, { "heavy", "Heavy armour (T-90)" } }) do
        local m = _menu(kind[2], mB)
        for _, n in ipairs({ 1, 3, 5, 10 }) do
            _cmd("Spawn " .. n, m, function() _bombingSpawn(kind[1], n) end)
        end
    end
    _cmd("Spawn convoy",        mB, function() _bombingSpawnConvoy() end)
    _cmd("Scores",              mB, function() _scoreBoard() end)
    _cmd("Clear scores",        mB, function() _scoreClear() end)
    _cmd("Reset Bombing Range", mB, function() _bombingReset() end)

    -- SEAD Range
    local mS  = _menu("SEAD Range", root)
    local mSr = _menu("Radar Zone", mS)
    _cmd("Spawn SA-2",          mSr, function() _seadSpawnRadar("SA2") end)
    _cmd("Spawn SA-3",          mSr, function() _seadSpawnRadar("SA3") end)
    _cmd("Spawn SA-6",          mSr, function() _seadSpawnRadar("SA6") end)
    _cmd("Spawn SA-8",          mSr, function() _seadSpawnRadar("SA8") end)
    _cmd("Spawn SA-11",         mSr, function() _seadSpawnRadar("SA11") end)
    _cmd("Spawn Hawk",          mSr, function() _seadSpawnRadar("HAWK") end)
    _cmd("Spawn Rapier (optical)", mSr, function() _seadSpawnRadar("RAPIER") end)
    _cmd("HARM reaction on/off", mSr, function() _seadToggleHarm() end)
    _cmd("Remove radar SAM",    mSr, function() _seadRemoveRadar() end)
    local mSi = _menu("IR/AAA Zone", mS)
    _cmd("Spawn IR (light)",         mSi, function() _seadSpawnIR("IR_LIGHT") end)
    _cmd("Spawn AAA",                mSi, function() _seadSpawnIR("AAA") end)
    _cmd("Spawn Integrated Defense", mSi, function() _seadSpawnIR("INTEGRATED") end)
    _cmd("AAA live fire on/off",     mSi, function() _seadToggleAAA() end)
    _cmd("Remove IR/AAA",            mSi, function() _seadRemoveIR() end)
    _cmd("Reset SEAD Range", mS, function() _seadReset() end)

    -- Carrier Ops (the strike group is already on station from mission start)
    local mC = _menu("Carrier Ops", root)
    local mCs = _menu("Set speed", mC)
    for _, kt in ipairs({ 10, 15, 20, 25, 30 }) do
        _cmd(kt .. " kt", mCs, function() _carrierSetSpeed(kt) end)
    end
    local mCr = _menu("Group ROE", mC)
    _cmd("Engage (weapons free)",     mCr, function() _carrierSetROE("engage") end)
    _cmd("Defend only (return fire)", mCr, function() _carrierSetROE("defend") end)
    _cmd("Call recovery (into wind)",  mC, function() _carrierRecovery() end)
    _cmd("Deck status",                mC, function() _carrierDeckStatus() end)
    _cmd("Spawn S-3B Recovery Tanker", mC, function() _carrierTanker() end)
    _cmd("Remove S-3B",                mC, function() _carrierRemoveTanker() end)
    _cmd("Respawn carrier",            mC, function() _carrierRespawn() end)

    -- Refueling
    local mR = _menu("Refueling", root)
    _cmd("Spawn Basket tanker", mR, function() _refuelSpawn("basket") end)
    _cmd("Spawn Boom tanker",   mR, function() _refuelSpawn("boom") end)
    for _, which in ipairs({ "basket", "boom" }) do
        local m = _menu(_refuelLabel(which) .. " speed", mR)
        for _, kias in ipairs(TR_Config.refueling.speeds) do
            _cmd(kias .. " KIAS", m, function() _refuelSetSpeed(which, kias) end)
        end
    end
    _cmd("Remove Basket tanker", mR, function() _refuelRemove("basket") end)
    _cmd("Remove Boom tanker",   mR, function() _refuelRemove("boom") end)
    _cmd("Reset Refueling",      mR, function() _refuelReset() end)

    -- Map drawings and global reset
    _cmd("Map drawings on/off",      root, function() _markToggle() end)
    _cmd("Reset all (every module)", root, function() _resetAll() end)
end

-- ===========================================================================
-- INIT  (guarded so a double DO SCRIPT does not register the menu twice)
-- ===========================================================================
local function _checkZones()
    local b, s, c, r = TR_Config.bombing, TR_Config.sead, TR_Config.carrier, TR_Config.refueling
    local missing = {}
    for _, zn in ipairs({ b.zone, b.lightZone, b.heavyZone, TR_Config.dogfight.zone, s.radarZone, s.irZone,
                          c.zone, r.basket.zone, r.boom.zone }) do
        if not _zoneShape(zn) then missing[#missing + 1] = zn end
    end
    if #missing > 0 then
        _out("[Training Range] MISSING ZONES: " .. table.concat(missing, ", ") .. ". Create them in the Mission Editor.", 30)
    end
end

if not TR_Initialized then
    TR_Initialized = true
    TR_SEAD.aaaLive = TR_Config.sead.aaaLiveFire
    TR_SEAD.harmOn  = TR_Config.sead.harmReaction
    TR_Markers.on   = TR_Config.markers.enabled

    _checkZones()
    _buildMenu()
    world.addEventHandler(_eventHandler)

    -- Periodic ticks. Return (time + delay) for drift-free scheduling; clamp the
    -- interval to >= 1 s (pitfall #11).
    local dgi = math.max(1, TR_Config.dogfight.pollInterval)
    timer.scheduleFunction(function(_, time) pcall(_dogfightTick); return time + dgi end,
        nil, timer.getTime() + dgi)
    local sdi = math.max(1, TR_Config.sead.pollInterval)
    timer.scheduleFunction(function(_, time) pcall(_seadTick); return time + sdi end,
        nil, timer.getTime() + sdi)
    timer.scheduleFunction(function(_, time) pcall(_s3Tick); return time + 60 end,
        nil, timer.getTime() + 60)
    timer.scheduleFunction(function(_, time) pcall(_markTick); return time + 30 end,
        nil, timer.getTime() + 30)

    -- The carrier strike group is on station from mission start. Small delay so
    -- the mission is fully loaded before the ship group spawns; the range zones
    -- go on the map with it.
    timer.scheduleFunction(function() pcall(_carrierSpawn); pcall(_markZones); return nil end, nil, timer.getTime() + 1.0)

    _out("[Training Range] Ready. Open the F10 radio menu -> Training Range.", 15)
end
