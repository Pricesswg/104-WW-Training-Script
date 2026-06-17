-- ===========================================================================
-- TRAINING RANGE — TrainingRange.lua
-- ===========================================================================
-- Author:     Alessandro Simonitto
-- Repository: https://github.com/Pricesswg/   (update with the real URL)
-- License:    MIT
--
-- Single-file feature script, native DCS scripting engine only (no MOOSE /
-- MIST / CTLD). Load it once via a trigger:  MISSION START -> DO SCRIPT FILE.
--
-- INSTALLATION:
--   1. Open the mission in the Mission Editor.
--   2. Create the zones listed below (type: Circle) with the EXACT names.
--   3. Fill in the spawnPoint coordinates in the TR_Config block.
--   4. Add a trigger:  MISSION START -> DO SCRIPT FILE -> TrainingRange.lua
--   5. Full documentation and wiki: see the GitHub repository.
--
-- REQUIRED ZONES IN THE MISSION EDITOR (type: Circle):
--   TR_BOMBING      radius ~3000m    bombing range
--   TR_DOGFIGHT     radius ~15000m   dogfight arena
--   TR_SEAD_RADAR   radius ~8000m    radar SAM zone
--   TR_SEAD_IR      radius ~5000m    IR / AAA zone
--
-- COORDINATES: to read x/z in DCS, place the cursor on the desired point on
-- the ME map and read the values from the Coordinate tab. Carrier and tankers
-- do NOT use ME zones; their absolute x/z go in TR_Config.
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
        zone       = "TR_BOMBING",           -- ME zone name, must match exactly
        minSpacing = 500,                    -- minimum metres between static targets
        smokeColor = trigger.smokeColor.Red, -- Red / Green / White / Orange / Blue
        staticUnit = "Infantry AK",          -- target unit type (exact DCS string)
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
        radarZone    = "TR_SEAD_RADAR",     -- ME zone name, radar SAM
        irZone       = "TR_SEAD_IR",        -- ME zone name, IR/AAA
        pollInterval = 2,                   -- seconds between player-immortality checks
        radarSpawnPoint = { x = 0, z = 0 }, -- FILL IN: radar SAM spawn centre
        irSpawnPoint    = { x = 0, z = 0 }, -- FILL IN: IR/AAA spawn centre
    },
    -- -----------------------------------------------------------------------
    -- CARRIER OPS
    -- -----------------------------------------------------------------------
    carrier = {
        unitName             = "TR_CARRIER",      -- carrier unit AND group name
        type                 = "Stennis",         -- carrier type (added: spec omitted it).
                                                  -- "Stennis" needs no DLC. Swap for
                                                  -- "CVN_73"/"CVN_71" if you own Supercarrier.
        spawnPoint           = { x = 0, z = 0 },  -- FILL IN: carrier spawn coordinates
        speed                = 15,                -- carrier speed in knots
        recoveryTankerAlt    = 1500,              -- S-3B altitude in metres
        recoveryTankerSpeed  = 280,               -- S-3B speed in km/h
        recoveryTankerOffset = { x = 20000, z = 0 }, -- S-3B offset from the carrier (x/z metres)
        recoveryTankerFreq   = 253.0,             -- added: S-3B radio freq (MHz, AM) for the message
        recoveryTankerTacan  = { channel = 53, mode = "Y", callsign = "RCV" }, -- added: S-3B TACAN
    },
    -- -----------------------------------------------------------------------
    -- REFUELING SERVICE
    -- -----------------------------------------------------------------------
    refueling = {
        basket = {
            type       = "KC135MPRS",          -- probe-and-drogue tanker (exact DCS type)
            alt        = 6000,                 -- altitude in metres
            speed      = 480,                  -- speed in km/h
            heading    = 090,                  -- track heading in degrees
            spawnPoint = { x = 0, z = 0 },     -- FILL IN
            tacan      = { channel = 51, mode = "Y", callsign = "TKR" },
            freq       = 251.0,                -- AM frequency in MHz
        },
        boom = {
            type       = "KC-135",             -- boom tanker. NOTE: exact DCS type is
                                               -- "KC-135" (hyphen). The spec's "KC_135"
                                               -- would not spawn.
            alt        = 7000,
            speed      = 500,
            heading    = 090,
            spawnPoint = { x = 0, z = 0 },     -- FILL IN
            tacan      = { channel = 52, mode = "Y", callsign = "TKB" },
            freq       = 252.0,
        },
    },
    -- -----------------------------------------------------------------------
    -- GENERAL
    -- -----------------------------------------------------------------------
    coalition = coalition.side.BLUE, -- monitored player coalition
}

-- ===========================================================================
-- COORDINATES TO FILL IN  (placeholders left as { x = 0, z = 0 } on purpose)
-- ---------------------------------------------------------------------------
-- The following points are NOT derived from ME zones and must be entered by
-- hand. Until you set them the affected feature spawns at the map origin and
-- prints a warning.
--
--   TR_Config.sead.radarSpawnPoint     -- centre of the radar SAM site
--   TR_Config.sead.irSpawnPoint        -- centre of the IR/AAA site
--   TR_Config.carrier.spawnPoint       -- carrier start position
--   TR_Config.refueling.basket.spawnPoint
--   TR_Config.refueling.boom.spawnPoint
--
-- How to read x/z in the ME: hover the point, read the Coordinate tab. In DCS
-- runtime coordinates x is one horizontal axis and z the other (y is altitude).
-- ===========================================================================

-- ===========================================================================
-- FINE PARAMETRI EDITABILI — do not edit below this line unless you know the code
-- ===========================================================================

-- ===========================================================================
-- API AVAILABILITY GUARD (fail fast with a visible message)
-- ===========================================================================
if not (trigger and trigger.action and trigger.action.outText
        and coalition and coalition.addGroup and coalition.getPlayers
        and timer and timer.scheduleFunction
        and world and world.addEventHandler
        and missionCommands and missionCommands.addSubMenu
        and trigger.misc and trigger.misc.getZone) then
    if trigger and trigger.action and trigger.action.outText then
        trigger.action.outText("[Training Range] Required DCS API missing. Script aborted.", 20)
    end
    return
end

-- ===========================================================================
-- MODULE STATE  (globals per spec; guarded with `or` so a reload keeps state)
-- ===========================================================================
TR_Bombing   = TR_Bombing   or { staticGroups = {}, convoyGroup = nil, targets = {} }
TR_Dogfight  = TR_Dogfight  or { players = {} }                       -- [unitName] = { score, entryTime }
TR_SEAD      = TR_SEAD      or { radarActive = nil, irActive = nil, players = {} }
TR_Carrier   = TR_Carrier   or { spawned = false, recoveryTanker = nil }
TR_Refueling = TR_Refueling or { basket = nil, boom = nil }

-- ===========================================================================
-- CONSTANTS
-- ===========================================================================
local KT_TO_MS  = 0.514444   -- knots  -> m/s
local KMH_TO_MS = 1 / 3.6    -- km/h   -> m/s
local MS_TO_KT  = 1.94384    -- m/s    -> knots

local CONVOY_SPEED = 5.56    -- m/s (~20 km/h); convoy is a slow moving target

-- Enemy ground targets (bombing + SEAD) spawn RED so they oppose the BLUE
-- player; carrier and tankers spawn under the USA (BLUE). Coalition in DCS is
-- decided by the country you spawn under, not by the unit's native nation, so
-- a US unit placed in the "Integrated Defense" preset still ends up RED.
local ENEMY_COUNTRY    = country.id.RUSSIA
local FRIENDLY_COUNTRY = country.id.USA

-- Radar SAM presets. SA-3 carries its Low Blow track radar ("snr s-125 tr")
-- on purpose: the spec listed only search + launchers, but without the track
-- radar the SA-3 cannot guide a missile and is useless as a SEAD target.
local SEAD_RADAR_PRESETS = {
    SA2    = { group = "TR_SAM_SA2",    units = { "SNR_75V", "S_75M_Volhov", "S_75M_Volhov" } },
    SA3    = { group = "TR_SAM_SA3",    units = { "p-19 s-125 sr", "snr s-125 tr", "5p73 s-125 ln", "5p73 s-125 ln" } },
    SA6    = { group = "TR_SAM_SA6",    units = { "Kub 1S91 str", "Kub 2P25 ln", "Kub 2P25 ln" } },
    SA8    = { group = "TR_SAM_SA8",    units = { "Osa 9A33 ln", "Osa 9A33 ln" } },
    SA11   = { group = "TR_SAM_SA11",   units = { "SA-11 Buk SR 9S18M1", "SA-11 Buk LN 9A310M1", "SA-11 Buk LN 9A310M1" } },
    HAWK   = { group = "TR_SAM_HAWK",   units = { "Hawk sr", "Hawk tr", "Hawk ln", "Hawk ln" } },
    -- Rapier uses the optical tracker as specified: it engages but does NOT
    -- emit radar, so it will not paint a player's RWR (visual threat only).
    RAPIER = { group = "TR_SAM_RAPIER", units = { "rapier_fsa_optical_tracker_unit", "rapier_fsa_launcher", "rapier_fsa_launcher" } },
}

-- IR / AAA presets. These are short-range IR and gun threats by design and do
-- not show on RWR.
local SEAD_IR_PRESETS = {
    IR_LIGHT   = { group = "TR_IR_LIGHT",   units = { "SA-18 Igla manpad", "SA-18 Igla manpad", "Soldier stinger", "Soldier stinger" } },
    AAA        = { group = "TR_AAA",        units = { "ZSU-23-4 Shilka", "ZSU-23-4 Shilka", "ZU-23 Emplacement", "ZU-23 Emplacement" } },
    INTEGRATED = { group = "TR_INTEGRATED", units = { "Strela-10M3", "SA-18 Igla manpad", "ZSU-23-4 Shilka", "Vulcan" } },
}

-- ===========================================================================
-- HELPERS
-- ===========================================================================
local function _out(msg, t)
    trigger.action.outText(tostring(msg), t or 10)
end

local function _msgToUnit(unit, msg, t)
    -- outTextForGroup needs the numeric group ID, not the name (pitfall #16).
    local ok = pcall(function()
        local g = unit:getGroup()
        if g then trigger.action.outTextForGroup(g:getID(), tostring(msg), t or 10) end
    end)
    if not ok then _out(msg, t) end
end

local function _round(n) return math.floor(n + 0.5) end

-- Ground/terrain height. DCS land.getHeight takes a Vec2 {x, y} where y is the
-- world Z axis (NOT a 3D point). Getting this wrong puts smoke underground or
-- reads AGL against the wrong axis.
local function _groundY(x, z)
    return land.getHeight({ x = x, y = z }) or 0
end

local function _surfaceOk(x, z)
    local st = land.getSurfaceType({ x = x, y = z })
    return st ~= land.SurfaceType.WATER and st ~= land.SurfaceType.SHALLOW_WATER
end

local function _dist2D(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

-- trigger.misc.getZone returns { point = {x, y = 0, z}, radius } for circle zones.
local function _getZone(name)
    local z = trigger.misc.getZone(name)
    if not z then _out("[Training Range] Zone not found: " .. tostring(name), 15) end
    return z
end

local function _inZone(point, zone)
    local dx, dz = point.x - zone.point.x, point.z - zone.point.z
    return (dx * dx + dz * dz) <= (zone.radius * zone.radius)
end

-- Uniform random point inside a circular zone (sqrt keeps it area-uniform).
local function _randomPointInZone(zone, margin)
    local r = math.max(0, zone.radius - (margin or 0)) * math.sqrt(math.random())
    local a = math.random() * 2 * math.pi
    return { x = zone.point.x + r * math.cos(a), z = zone.point.z + r * math.sin(a) }
end

local function _randomLandPointInZone(zone, margin, tries)
    for _ = 1, (tries or 30) do
        local p = _randomPointInZone(zone, margin)
        if _surfaceOk(p.x, p.z) then return p end
    end
    return _randomPointInZone(zone, margin) -- give up on land, return anything in zone
end

local function _warnIfUnset(pt, label)
    if pt and pt.x == 0 and pt.z == 0 then
        _out("[Training Range] WARNING: " .. label .. " is still {x=0,z=0} (FILL IN). Spawning at map origin.", 15)
    end
end

local function _destroyGroupByName(name)
    if not name then return end
    -- Always re-lookup; a cached Group object goes stale once its last unit
    -- dies and DCS purges the group (pitfall #9).
    local g = Group.getByName(name)
    if g then g:destroy() end
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
    -- pcall the spawn: a single wrong unit type string (they vary across DCS
    -- versions) would otherwise throw straight out of the menu handler.
    local grp
    local ok, perr = pcall(function() grp = coalition.addGroup(countryId, Group.Category.GROUND, groupData) end)
    if not ok then
        _out("[Training Range] Spawn failed for " .. name .. " (check unit type strings).", 15)
        env.info("[Training Range] addGroup " .. name .. " error: " .. tostring(perr))
    end
    return grp
end

-- SAMs need to be radiating to be useful SEAD targets. RED alarm state keeps
-- their radars on so the player's RWR lights up immediately. Options share the
-- post-spawn binding race, so apply them on a short delay and re-lookup by name.
local function _setGroundCombatReady(groupName)
    timer.scheduleFunction(function()
        local g = Group.getByName(groupName)
        if not g then return nil end
        local ctrl = g:getController()
        pcall(function() ctrl:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED) end)
        pcall(function() ctrl:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE) end)
        return nil
    end, nil, timer.getTime() + 1.0)
end

-- ---------------------------------------------------------------------------
-- Tanker spawn (shared by Basket, Boom and the carrier S-3B).
-- A working tanker needs THREE things, which is why "task = Refueling" alone
-- (as the spec phrased it) is not enough:
--   1) group task "Refueling"  -> marks the group as a tanker role
--   2) enroute "Tanker" task    -> actually extends the boom/basket
--   3) an Orbit (Race-Track)    -> keeps it on a predictable track
-- ---------------------------------------------------------------------------
local function _spawnTanker(opts)
    local rad = math.rad(opts.headingDeg or 90)
    local leg = opts.legLength or 30000
    local p1  = { x = opts.center.x, z = opts.center.z }
    local p2  = { x = opts.center.x + math.sin(rad) * leg, z = opts.center.z + math.cos(rad) * leg }

    local wp1tasks = {
        [1] = { id = "Tanker", params = {} },
        [2] = { id = "Orbit",  params = { pattern = "Race-Track", speed = opts.speedMS, altitude = opts.alt } },
    }
    if opts.tacan then
        -- ActivateBeacon params are DCS-version sensitive; the whole spawn is
        -- pcall-guarded below, and the channel is printed to the player as a
        -- fallback regardless of whether the beacon takes.
        wp1tasks[3] = { id = "WrappedAction", params = { action = { id = "ActivateBeacon", params = {
            ["type"]        = 4,  -- TACAN
            ["system"]      = 5,  -- TACAN airborne
            ["callsign"]    = opts.tacan.callsign,
            ["frequency"]   = _tacanFreq(opts.tacan.channel, opts.tacan.mode),
            ["channel"]     = opts.tacan.channel,
            ["modeChannel"] = opts.tacan.mode,
            ["bearing"]     = true,
            ["AA"]          = true,
        } } } }
    end

    local function _airWP(p)
        return {
            ["x"] = p.x, ["y"] = p.z,
            ["alt"] = opts.alt, ["alt_type"] = "BARO",
            ["type"] = "Turning Point", ["action"] = "Turning Point",
            ["speed"] = opts.speedMS, ["ETA"] = 0, ["ETA_locked"] = false, ["speed_locked"] = true,
            ["task"] = { id = "ComboTask", params = { tasks = {} } },
        }
    end
    local wp1 = _airWP(p1); wp1.task = { id = "ComboTask", params = { tasks = wp1tasks } }

    local groupData = {
        ["name"]         = opts.name,
        ["task"]         = "Refueling",
        ["uncontrolled"] = false,
        ["start_time"]   = 0,
        ["units"] = { [1] = {
            ["type"]     = opts.type,
            ["name"]     = opts.name .. "_1",
            ["x"]        = p1.x, ["y"] = p1.z,
            ["alt"]      = opts.alt, ["alt_type"] = "BARO",
            ["speed"]    = opts.speedMS,
            ["heading"]  = rad,
            ["skill"]    = "High",
            ["payload"]  = { ["pylons"] = {}, ["fuel"] = "100000", ["flare"] = 0, ["chaff"] = 0, ["gun"] = 100 },
        } },
        ["route"] = { ["points"] = { [1] = wp1, [2] = _airWP(p2) } },
    }

    local grp
    pcall(function() grp = coalition.addGroup(FRIENDLY_COUNTRY, Group.Category.AIRPLANE, groupData) end)
    return grp
end

-- ===========================================================================
-- MODULE: BOMBING RANGE
-- ===========================================================================
local function _bombingClearStatics()
    for _, name in ipairs(TR_Bombing.staticGroups) do
        _destroyGroupByName(name)
        TR_Bombing.targets[name] = nil
    end
    TR_Bombing.staticGroups = {}
end

-- Rejection sampling for N points at least minSpacing apart inside the zone.
local function _generateSpacedPoints(zone, count, minSpacing, margin)
    local pts, attempts, maxAttempts = {}, 0, count * 50
    while #pts < count and attempts < maxAttempts do
        attempts = attempts + 1
        local p, ok = _randomPointInZone(zone, margin), true
        for _, q in ipairs(pts) do
            if _dist2D(p, q) < minSpacing then ok = false break end
        end
        if ok then pts[#pts + 1] = p end
    end
    return pts
end

local function _bombingSpawnStatics(count)
    local zone = _getZone(TR_Config.bombing.zone); if not zone then return end
    _bombingClearStatics()
    local pts = _generateSpacedPoints(zone, count, TR_Config.bombing.minSpacing, 100)
    if #pts < count then
        _out("[Bombing Range] Only placed " .. #pts .. " of " .. count .. " targets (spacing/zone limit).", 12)
    end
    for i, p in ipairs(pts) do
        local name = "TR_STATIC_" .. i
        _spawnGround(name, { TR_Config.bombing.staticUnit }, p, ENEMY_COUNTRY)
        TR_Bombing.staticGroups[#TR_Bombing.staticGroups + 1] = name
        TR_Bombing.targets[name] = 1
        local sx, sz = p.x + 50, p.z -- smoke 50 m to the side so it marks each target
        trigger.action.smoke({ x = sx, y = _groundY(sx, sz), z = sz }, TR_Config.bombing.smokeColor)
    end
    if #pts > 0 then _out("[Bombing Range] Spawned " .. #pts .. " target(s).", 10) end
end

local function _bombingSpawnConvoy()
    local zone = _getZone(TR_Config.bombing.zone); if not zone then return end
    if TR_Bombing.convoyGroup then
        _destroyGroupByName(TR_Bombing.convoyGroup)
        TR_Bombing.targets[TR_Bombing.convoyGroup] = nil
        TR_Bombing.convoyGroup = nil
    end

    local wps = {}
    for i = 1, 4 do wps[i] = _randomLandPointInZone(zone, 200, 40) end

    -- Lead heading toward WP2; trail units sit behind it in column.
    local hdg = math.atan2(wps[2].x - wps[1].x, wps[2].z - wps[1].z)
    local units = {}
    for i = 1, 3 do
        local back = (i - 1) * 25
        units[i] = {
            ["type"]    = "BRDM-2",
            ["name"]    = "TR_CONVOY_" .. i,
            ["x"]       = wps[1].x - math.sin(hdg) * back,
            ["y"]       = wps[1].z - math.cos(hdg) * back,
            ["heading"] = hdg,
            ["skill"]   = "High",
        }
    end

    -- DCS ground routes do not auto-cycle, so we materialise several laps and
    -- end back at WP1 ("torna al primo").
    local points, idx, laps = {}, 1, 4
    for _ = 1, laps do
        for i = 1, 4 do
            points[idx] = {
                ["x"] = wps[i].x, ["y"] = wps[i].z,
                ["type"] = "Turning Point", ["action"] = "Off Road", ["speed"] = CONVOY_SPEED,
                ["task"] = { id = "ComboTask", params = { tasks = {} } },
            }
            idx = idx + 1
        end
    end
    points[idx] = {
        ["x"] = wps[1].x, ["y"] = wps[1].z,
        ["type"] = "Turning Point", ["action"] = "Off Road", ["speed"] = CONVOY_SPEED,
        ["task"] = { id = "ComboTask", params = { tasks = {} } },
    }

    -- Convoy builds its own multi-waypoint route, so it does not go through _spawnGround.
    local groupData = {
        ["name"]  = "TR_CONVOY",
        ["task"]  = "Ground Nothing",
        ["units"] = units,
        ["route"] = { ["points"] = points },
    }
    pcall(function() coalition.addGroup(ENEMY_COUNTRY, Group.Category.GROUND, groupData) end)
    TR_Bombing.convoyGroup = "TR_CONVOY"
    TR_Bombing.targets["TR_CONVOY"] = 3
    _out("[Bombing Range] Convoy of 3 BRDM-2 rolling.", 10)
end

local function _bombingReset()
    _bombingClearStatics()
    if TR_Bombing.convoyGroup then
        _destroyGroupByName(TR_Bombing.convoyGroup)
        TR_Bombing.convoyGroup = nil
    end
    TR_Bombing.targets = {}
    _out("[Bombing Range] Reset done.")
end

-- ===========================================================================
-- MODULE: DOGFIGHT ZONE  (automatic, no menu — players just fly in)
-- ===========================================================================
local function _dogfightTick()
    local zone = _getZone(TR_Config.dogfight.zone); if not zone then return end
    local players = coalition.getPlayers(TR_Config.coalition) or {}
    local seen = {}
    for _, u in pairs(players) do
        if u and u.isExist and u:isExist() then
            local name = u:getName()
            seen[name] = true
            local p = u:getPoint()
            local agl = p.y - _groundY(p.x, p.z)
            local active = _inZone(p, zone) and (agl >= TR_Config.dogfight.minAGL)
            if active and not TR_Dogfight.players[name] then
                _setImmortal(u, true)
                TR_Dogfight.players[name] = { score = 0, entryTime = timer.getTime() }
                _msgToUnit(u, "[Dogfight] Immortal ON. Engage other players in the arena. +1 per hit. " ..
                              "Leave the zone or drop below " .. TR_Config.dogfight.minAGL .. "m AGL to exit.", 15)
            elseif (not active) and TR_Dogfight.players[name] then
                local s = TR_Dogfight.players[name].score
                _setImmortal(u, false)
                TR_Dogfight.players[name] = nil
                _msgToUnit(u, "[Dogfight] Left the arena. Immortal OFF. Final score: " .. s .. ".", 12)
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
    _out("[Dogfight] Reset. Scores cleared, immortality removed.")
end

-- ===========================================================================
-- MODULE: SEAD RANGE
-- ===========================================================================
-- Immortality polling across BOTH zones (radar + IR).
local function _seadTick()
    local zr = trigger.misc.getZone(TR_Config.sead.radarZone)
    local zi = trigger.misc.getZone(TR_Config.sead.irZone)
    if not zr and not zi then return end
    local players = coalition.getPlayers(TR_Config.coalition) or {}
    local seen = {}
    for _, u in pairs(players) do
        if u and u.isExist and u:isExist() then
            local name = u:getName()
            seen[name] = true
            local p = u:getPoint()
            local inside = (zr and _inZone(p, zr)) or (zi and _inZone(p, zi))
            if inside and not TR_SEAD.players[name] then
                _setImmortal(u, true)
                TR_SEAD.players[name] = true
                _msgToUnit(u, "[SEAD] Immortal ON. Hunt the active emitters — you cannot be killed inside the range.", 15)
            elseif (not inside) and TR_SEAD.players[name] then
                _setImmortal(u, false)
                TR_SEAD.players[name] = nil
                _msgToUnit(u, "[SEAD] Left the range. Immortal OFF.", 12)
            end
        end
    end
    for name in pairs(TR_SEAD.players) do
        if not seen[name] then TR_SEAD.players[name] = nil end
    end
end

local function _seadSpawnRadar(key)
    local preset = SEAD_RADAR_PRESETS[key]; if not preset then return end
    _warnIfUnset(TR_Config.sead.radarSpawnPoint, "SEAD radar spawn point")
    if TR_SEAD.radarActive then _destroyGroupByName(TR_SEAD.radarActive) end -- one radar preset at a time
    _spawnGround(preset.group, preset.units, TR_Config.sead.radarSpawnPoint, ENEMY_COUNTRY)
    _setGroundCombatReady(preset.group)
    TR_SEAD.radarActive = preset.group
    _out("[SEAD] Radar SAM active: " .. key .. " (" .. preset.group .. ").", 10)
end

local function _seadSpawnIR(key)
    local preset = SEAD_IR_PRESETS[key]; if not preset then return end
    _warnIfUnset(TR_Config.sead.irSpawnPoint, "SEAD IR/AAA spawn point")
    if TR_SEAD.irActive then _destroyGroupByName(TR_SEAD.irActive) end -- one IR preset at a time
    _spawnGround(preset.group, preset.units, TR_Config.sead.irSpawnPoint, ENEMY_COUNTRY)
    _setGroundCombatReady(preset.group)
    TR_SEAD.irActive = preset.group
    _out("[SEAD] IR/AAA active: " .. key .. " (" .. preset.group .. ").", 10)
end

local function _seadRemoveRadar()
    if TR_SEAD.radarActive then
        _destroyGroupByName(TR_SEAD.radarActive)
        TR_SEAD.radarActive = nil
        _out("[SEAD] Radar SAM removed.")
    else
        _out("[SEAD] No active radar SAM.")
    end
end

local function _seadRemoveIR()
    if TR_SEAD.irActive then
        _destroyGroupByName(TR_SEAD.irActive)
        TR_SEAD.irActive = nil
        _out("[SEAD] IR/AAA removed.")
    else
        _out("[SEAD] No active IR/AAA.")
    end
end

local function _seadReset()
    _destroyGroupByName(TR_SEAD.radarActive); TR_SEAD.radarActive = nil
    _destroyGroupByName(TR_SEAD.irActive);    TR_SEAD.irActive = nil
    for name in pairs(TR_SEAD.players) do
        local u = Unit.getByName(name)
        if u then _setImmortal(u, false) end
    end
    TR_SEAD.players = {}
    _out("[SEAD] Reset done.")
end

-- ===========================================================================
-- MODULE: CARRIER OPS
-- ===========================================================================
-- Wind-corrected recovery course. atmosphere.getWind returns a velocity vector
-- (the direction the wind blows TOWARD); the carrier steams into the wind, so
-- the recovery course is that bearing + 180, which is also the meteorological
-- "wind from" bearing.
local function _carrierWind(cp)
    local w = atmosphere.getWind({ x = cp.x, y = cp.y + 15, z = cp.z })
    local toDeg  = math.deg(math.atan2(w.x, w.z))
    local course = (toDeg + 180) % 360
    local kt     = math.sqrt(w.x * w.x + w.z * w.z) * MS_TO_KT
    return course, kt
end

local function _carrierSpawn()
    if TR_Carrier.spawned and Unit.getByName(TR_Config.carrier.unitName) then
        _out("[Carrier] Already on station."); return
    end
    local sp = TR_Config.carrier.spawnPoint
    _warnIfUnset(sp, "carrier spawn point")
    local speedMS = TR_Config.carrier.speed * KT_TO_MS
    local rad = math.rad(270) -- initial heading 270
    local far = { x = sp.x + math.sin(rad) * 40000, z = sp.z + math.cos(rad) * 40000 }
    local function _shipWP(x, z)
        return { ["x"] = x, ["y"] = z, ["type"] = "Turning Point", ["action"] = "Turning Point",
                 ["speed"] = speedMS, ["ETA"] = 0, ["ETA_locked"] = false,
                 ["task"] = { id = "ComboTask", params = { tasks = {} } } }
    end
    local groupData = {
        ["name"]  = TR_Config.carrier.unitName,
        ["task"]  = "Nothing",
        ["units"] = { [1] = {
            ["type"] = TR_Config.carrier.type, ["name"] = TR_Config.carrier.unitName,
            ["x"] = sp.x, ["y"] = sp.z, ["heading"] = rad, ["skill"] = "High",
        } },
        ["route"] = { ["points"] = { [1] = _shipWP(sp.x, sp.z), [2] = _shipWP(far.x, far.z) } },
    }
    local grp
    pcall(function() grp = coalition.addGroup(FRIENDLY_COUNTRY, Group.Category.SHIP, groupData) end)
    TR_Carrier.spawned = (grp ~= nil)
    _out("[Carrier] On station, steaming 270 at " .. TR_Config.carrier.speed .. " kt. Unit: " ..
         TR_Config.carrier.unitName .. ".", 12)
end

local function _carrierRecovery()
    local u = Unit.getByName(TR_Config.carrier.unitName)
    if not u then _out("[Carrier] Carrier not on station."); return end
    local cp = u:getPoint()
    local course, kt = _carrierWind(cp)
    local rad = math.rad(course)
    local far = { x = cp.x + math.sin(rad) * 55560, z = cp.z + math.cos(rad) * 55560 } -- ~30 NM
    local speedMS = TR_Config.carrier.speed * KT_TO_MS
    local function _shipWP(x, z)
        return { ["x"] = x, ["y"] = z, ["type"] = "Turning Point", ["action"] = "Turning Point",
                 ["speed"] = speedMS, ["task"] = { id = "ComboTask", params = { tasks = {} } } }
    end
    local task = { id = "Mission", params = { route = { points = {
        [1] = _shipWP(cp.x, cp.z), [2] = _shipWP(far.x, far.z),
    } } } }
    _applyTaskStaggered(u:getGroup():getController(), task)
    _out(string.format("[Carrier] Recovery course %03d (into wind) | Wind %d kt from %03d.",
         _round(course) % 360, _round(kt), _round(course) % 360), 15)
end

local function _carrierDeckStatus()
    local u = Unit.getByName(TR_Config.carrier.unitName)
    if not u then _out("[Carrier] Carrier not on station."); return end
    local course, kt = _carrierWind(u:getPoint())
    local case = (kt > 10) and "CASE I" or "CASE III"
    _out(string.format("[Carrier] Deck status — recovery course %03d, wind %d kt from %03d. Suggested: %s.",
         _round(course) % 360, _round(kt), _round(course) % 360, case), 15)
end

local function _carrierTanker()
    if TR_Carrier.recoveryTanker and Group.getByName(TR_Carrier.recoveryTanker) then
        _out("[Carrier] Recovery tanker already airborne."); return
    end
    local u = Unit.getByName(TR_Config.carrier.unitName)
    local base = u and u:getPoint() or { x = TR_Config.carrier.spawnPoint.x, z = TR_Config.carrier.spawnPoint.z }
    local off = TR_Config.carrier.recoveryTankerOffset
    local grp = _spawnTanker({
        name = "TR_S3_TANKER", type = "S-3B Tanker",
        alt = TR_Config.carrier.recoveryTankerAlt, speedMS = TR_Config.carrier.recoveryTankerSpeed * KMH_TO_MS,
        headingDeg = 90, center = { x = base.x + off.x, z = base.z + off.z },
        freq = TR_Config.carrier.recoveryTankerFreq, tacan = TR_Config.carrier.recoveryTankerTacan,
    })
    TR_Carrier.recoveryTanker = grp and "TR_S3_TANKER" or nil
    local tc = TR_Config.carrier.recoveryTankerTacan
    _out(string.format("[Carrier] S-3B recovery tanker airborne | Freq: %.1f AM | TACAN: %d%s %s.",
         TR_Config.carrier.recoveryTankerFreq, tc.channel, tc.mode, tc.callsign), 15)
end

local function _carrierRemoveTanker()
    if TR_Carrier.recoveryTanker then
        _destroyGroupByName(TR_Carrier.recoveryTanker)
        TR_Carrier.recoveryTanker = nil
        _out("[Carrier] S-3B recovery tanker removed.")
    else
        _out("[Carrier] No recovery tanker airborne.")
    end
end

local function _carrierReset()
    _destroyGroupByName(TR_Config.carrier.unitName)
    _destroyGroupByName(TR_Carrier.recoveryTanker)
    TR_Carrier.spawned = false
    TR_Carrier.recoveryTanker = nil
    _out("[Carrier] Reset done.")
end

-- ===========================================================================
-- MODULE: REFUELING SERVICE
-- ===========================================================================
local _refuelNames = { basket = "TR_TANKER_BASKET", boom = "TR_TANKER_BOOM" }

local function _refuelSpawn(which)
    local c = TR_Config.refueling[which]
    local label = (which == "basket") and "Basket" or "Boom"
    if TR_Refueling[which] and Group.getByName(TR_Refueling[which]) then
        _out("[Refueling] " .. label .. " tanker already in service."); return
    end
    _warnIfUnset(c.spawnPoint, "refueling " .. which .. " spawn point")
    local name = _refuelNames[which]
    local grp = _spawnTanker({
        name = name, type = c.type,
        alt = c.alt, speedMS = c.speed * KMH_TO_MS, headingDeg = c.heading,
        center = { x = c.spawnPoint.x, z = c.spawnPoint.z },
        freq = c.freq, tacan = c.tacan,
    })
    TR_Refueling[which] = grp and name or nil
    _out(string.format("[Refueling] Tanker %s | Freq: %.1f AM | TACAN: %d%s %s.",
         label, c.freq, c.tacan.channel, c.tacan.mode, c.tacan.callsign), 15)
end

local function _refuelRemove(which)
    local label = (which == "basket") and "Basket" or "Boom"
    if TR_Refueling[which] then
        _destroyGroupByName(TR_Refueling[which])
        TR_Refueling[which] = nil
        _out("[Refueling] " .. label .. " tanker removed.")
    else
        _out("[Refueling] No " .. label .. " tanker in service.")
    end
end

local function _refuelReset()
    _destroyGroupByName(TR_Refueling.basket); TR_Refueling.basket = nil
    _destroyGroupByName(TR_Refueling.boom);   TR_Refueling.boom = nil
    _out("[Refueling] Reset done.")
end

-- ===========================================================================
-- GLOBAL RESET
-- ===========================================================================
local function _resetAll()
    _bombingReset()
    _seadReset()
    _dogfightReset()
    _carrierReset()
    _refuelReset()
    _out("[Training Range] All modules reset.", 12)
end

-- ===========================================================================
-- EVENT HANDLER  (single handler, dispatch by event.id, pcall-guarded)
-- ===========================================================================
local function _onDead(event)
    local u = event.initiator
    if not u or not u.getGroup then return end -- StaticObjects have no getGroup
    local gname
    local ok = pcall(function() local g = u:getGroup(); gname = g and g:getName() end)
    if not ok or not gname then return end
    if not TR_Bombing.targets[gname] then return end -- only bombing targets report

    local utype = (u.getTypeName and u:getTypeName()) or "target"
    _out("[Bombing Range] Target destroyed: " .. utype, 10)
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
        _msgToUnit(ini, "[Dogfight] Hit on " .. tName .. "! Score: " .. rec.score, 8)
    end
end

local _eventHandler = {}
function _eventHandler:onEvent(event)
    -- DCS silently eats errors thrown inside event handlers (pitfall #7).
    local ok, err = pcall(function()
        if not event then return end
        if event.id == world.event.S_EVENT_DEAD then
            _onDead(event)
        elseif event.id == world.event.S_EVENT_HIT then
            _onHit(event)
        end
    end)
    if not ok then env.info("[Training Range] onEvent error: " .. tostring(err)) end
end

-- ===========================================================================
-- RADIO MENU (F10)
-- ===========================================================================
local function _buildMenu()
    local root = missionCommands.addSubMenu("Training Range")

    -- Bombing Range
    local mB = missionCommands.addSubMenu("Bombing Range", root)
    missionCommands.addCommand("Spawn 1 target",   mB, function() _bombingSpawnStatics(1) end)
    missionCommands.addCommand("Spawn 3 targets",  mB, function() _bombingSpawnStatics(3) end)
    missionCommands.addCommand("Spawn 5 targets",  mB, function() _bombingSpawnStatics(5) end)
    missionCommands.addCommand("Spawn 10 targets", mB, function() _bombingSpawnStatics(10) end)
    missionCommands.addCommand("Spawn convoy",     mB, function() _bombingSpawnConvoy() end)
    missionCommands.addCommand("Reset Bombing Range", mB, function() _bombingReset() end)

    -- SEAD Range
    local mS  = missionCommands.addSubMenu("SEAD Range", root)
    local mSr = missionCommands.addSubMenu("Radar Zone", mS)
    missionCommands.addCommand("Spawn SA-2",          mSr, function() _seadSpawnRadar("SA2") end)
    missionCommands.addCommand("Spawn SA-3",          mSr, function() _seadSpawnRadar("SA3") end)
    missionCommands.addCommand("Spawn SA-6",          mSr, function() _seadSpawnRadar("SA6") end)
    missionCommands.addCommand("Spawn SA-8",          mSr, function() _seadSpawnRadar("SA8") end)
    missionCommands.addCommand("Spawn SA-11",         mSr, function() _seadSpawnRadar("SA11") end)
    missionCommands.addCommand("Spawn Hawk",          mSr, function() _seadSpawnRadar("HAWK") end)
    missionCommands.addCommand("Spawn Tracked Rapier", mSr, function() _seadSpawnRadar("RAPIER") end)
    missionCommands.addCommand("Remove radar SAM",    mSr, function() _seadRemoveRadar() end)
    local mSi = missionCommands.addSubMenu("IR/AAA Zone", mS)
    missionCommands.addCommand("Spawn IR (light)",        mSi, function() _seadSpawnIR("IR_LIGHT") end)
    missionCommands.addCommand("Spawn AAA",               mSi, function() _seadSpawnIR("AAA") end)
    missionCommands.addCommand("Spawn Integrated Defense", mSi, function() _seadSpawnIR("INTEGRATED") end)
    missionCommands.addCommand("Remove IR/AAA",           mSi, function() _seadRemoveIR() end)
    missionCommands.addCommand("Reset SEAD Range", mS, function() _seadReset() end)

    -- Carrier Ops
    local mC = missionCommands.addSubMenu("Carrier Ops", root)
    missionCommands.addCommand("Spawn Carrier",              mC, function() _carrierSpawn() end)
    missionCommands.addCommand("Call recovery",             mC, function() _carrierRecovery() end)
    missionCommands.addCommand("Deck status",               mC, function() _carrierDeckStatus() end)
    missionCommands.addCommand("Spawn S-3B Recovery Tanker", mC, function() _carrierTanker() end)
    missionCommands.addCommand("Remove S-3B",               mC, function() _carrierRemoveTanker() end)
    missionCommands.addCommand("Reset Carrier Ops",         mC, function() _carrierReset() end)

    -- Refueling
    local mR = missionCommands.addSubMenu("Refueling", root)
    missionCommands.addCommand("Spawn Basket tanker",  mR, function() _refuelSpawn("basket") end)
    missionCommands.addCommand("Spawn Boom tanker",    mR, function() _refuelSpawn("boom") end)
    missionCommands.addCommand("Remove Basket tanker", mR, function() _refuelRemove("basket") end)
    missionCommands.addCommand("Remove Boom tanker",   mR, function() _refuelRemove("boom") end)
    missionCommands.addCommand("Reset Refueling",      mR, function() _refuelReset() end)

    -- Global reset
    missionCommands.addCommand("Reset all (every module)", root, function() _resetAll() end)
end

-- ===========================================================================
-- INIT  (guarded so a double DO SCRIPT does not register the menu twice)
-- ===========================================================================
if not TR_Initialized then
    TR_Initialized = true

    pcall(function() math.randomseed(os.time()) end) -- vary target placement run-to-run

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

    _out("[Training Range] Ready. Open the F10 radio menu -> Training Range.", 15)
end
