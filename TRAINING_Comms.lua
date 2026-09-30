-- =========================================================
--  TRAINING_Comms.lua  (F10 comms card: radio, TACAN, ICLS)
--  v1.0, feature-script style, native DCS scripting engine only
-- ---------------------------------------------------------
--  One F10 entry, "Comms card (radio / TACAN / ICLS)", that prints what the
--  assets of your coalition have set: radio frequency, TACAN, ICLS, Link 4,
--  ACLS, laser code. Two sources:
--    * assets spawned by the training scripts (TrainingRange.lua, JTAC.lua):
--      they write themselves into the shared TRAINING_COMMS table when they
--      spawn, and the card shows them while their group exists;
--    * units placed in the Mission Editor, read from the mission at load:
--      the radio of the group (aircraft: group frequency in MHz; ships: unit
--      frequency in Hz) and the ActivateBeacon / ActivateICLS /
--      ActivateLink4 / ActivateACLS actions in their route. Support assets
--      (tankers, AWACS, ships, anything with a beacon) and player flights are
--      listed; other AI flights are not.
--  Each coalition sees only its own assets. Load order does not matter and
--  there are no zones to create: MISSION START -> DO SCRIPT FILE.
-- =========================================================

-- ============== Fail-fast API guard ==============
if not (trigger and trigger.action and trigger.action.outTextForCoalition
        and missionCommands and missionCommands.addCommandForCoalition
        and timer and timer.getAbsTime) then
    if trigger and trigger.action and trigger.action.outText then
        trigger.action.outText("[Comms] Required DCS API missing. Script aborted.", 20)
    end
    return
end

-- ============== Config ==============
local CFG = {
    sides       = { coalition.side.BLUE, coalition.side.RED }, -- coalitions that get the F10 entry
    showSeconds = 40,     -- how long the card stays on screen
    maxMission  = 25,     -- Mission Editor lines at most (support assets first)
    menuName    = "Comms card (radio / TACAN / ICLS)",
}

-- Shared with the other training scripts.
TRAINING_COMMS = TRAINING_COMMS or { assets = {} }

-- ============== Helpers ==============
local SIDE_KEY  = { [coalition.side.RED] = "red", [coalition.side.BLUE] = "blue" }
local SIDE_NAME = { [coalition.side.RED] = "RED", [coalition.side.BLUE] = "BLUE" }

-- Frequencies come in MHz or in Hz depending on who wrote them.
local function _mhz(f)
    if type(f) ~= "number" or f <= 0 then return nil end
    return (f > 10000) and (f / 1000000) or f
end

local function _line(e)
    local parts = { e.title or e.group or "?" }
    if e.radio and e.radio.mhz then
        parts[#parts + 1] = string.format("%.3f %s", e.radio.mhz, (e.radio.mod == 1) and "FM" or "AM")
    end
    if e.tacan then
        parts[#parts + 1] = string.format("TACAN %s%s %s", tostring(e.tacan.channel), e.tacan.mode or "", e.tacan.callsign or "")
    end
    if e.icls then parts[#parts + 1] = "ICLS " .. tostring(e.icls.channel) end
    if e.link4 then parts[#parts + 1] = string.format("Link 4 %.3f", e.link4.mhz) end
    if e.acls then parts[#parts + 1] = "ACLS" end
    if e.laser then parts[#parts + 1] = "laser " .. tostring(e.laser) end
    if e.note and e.note ~= "" then parts[#parts + 1] = e.note end
    return table.concat(parts, " | ")
end

-- ============== Mission Editor assets (read once at load) ==============
local ME = {} -- [side] = list of entries

local WANTED = { ActivateBeacon = true, ActivateICLS = true, ActivateLink4 = true, ActivateACLS = true }

-- The actions may sit at the first level of a waypoint's ComboTask or deeper
-- (WrappedAction, nested ComboTask): look everywhere in the route.
local function _findActions(node, out, depth)
    if type(node) ~= "table" or depth > 30 then return end
    if WANTED[node.id] and type(node.params) == "table" then out[#out + 1] = node end
    for _, v in pairs(node) do
        if type(v) == "table" then _findActions(v, out, depth + 1) end
    end
end

local function _fromGroup(g, cat)
    local units = g.units or {}
    local u1 = units[1]
    if not u1 then return nil end
    local e = { group = g.name }
    if cat == "ship" then
        local f = _mhz(u1.frequency)
        if f then e.radio = { mhz = f, mod = u1.modulation or 0 } end
    else
        local f = _mhz(g.frequency)
        if f then e.radio = { mhz = f, mod = g.modulation or 0 } end
    end
    local acts = {}
    _findActions(g.route, acts, 0)
    for _, a in ipairs(acts) do
        local p = a.params
        if a.id == "ActivateBeacon" and p.channel then
            e.tacan = { channel = p.channel, mode = p.modeChannel or "", callsign = p.callsign or "" }
        elseif a.id == "ActivateICLS" and p.channel then
            e.icls = { channel = p.channel }
        elseif a.id == "ActivateLink4" and p.frequency then
            e.link4 = { mhz = _mhz(p.frequency) or 0 }
        elseif a.id == "ActivateACLS" then
            e.acls = true
        end
    end
    local client = false
    for _, u in ipairs(units) do
        if u.skill == "Client" or u.skill == "Player" then client = true end
    end
    local support = (e.tacan or e.icls or e.link4 or g.task == "Refueling" or g.task == "AWACS" or cat == "ship") and true or false
    if not (support or client) then return nil end
    if not (e.radio or e.tacan or e.icls or e.link4) then return nil end
    local cs = (type(u1.callsign) == "table" and type(u1.callsign.name) == "string") and u1.callsign.name:gsub("%d+$", "") or nil
    e.title = string.format("%s (%s%s%s)", tostring(g.name), (#units > 1) and (#units .. "x ") or "",
                            tostring(u1.type), cs and cs ~= "" and (", " .. cs) or "")
    e.client, e.support = client, support
    return e
end

local function _scanMission()
    local m = env and env.mission
    for side, key in pairs(SIDE_KEY) do
        local list = {}
        local coal = m and m.coalition and m.coalition[key]
        for _, ctry in ipairs((coal and coal.country) or {}) do
            for _, cat in ipairs({ "ship", "plane", "helicopter", "vehicle" }) do
                for _, g in ipairs((ctry[cat] and ctry[cat].group) or {}) do
                    local ok, e = pcall(_fromGroup, g, cat)
                    if ok and e then list[#list + 1] = e end
                end
            end
        end
        -- Support assets first, then player flights, each in mission order.
        local sorted = {}
        for _, e in ipairs(list) do if e.support then sorted[#sorted + 1] = e end end
        for _, e in ipairs(list) do if not e.support then sorted[#sorted + 1] = e end end
        ME[side] = sorted
    end
end

-- ============== The card ==============
local function _card(side)
    local lines = {}
    local t = timer.getAbsTime() % 86400
    lines[1] = string.format("COMMS CARD %s  %02d:%02d local", SIDE_NAME[side] or "", math.floor(t / 3600), math.floor(t % 3600 / 60))

    local live = {}
    for _, e in pairs(TRAINING_COMMS.assets) do
        if (e.side or coalition.side.BLUE) == side and (not e.group or Group.getByName(e.group)) then
            live[#live + 1] = e
        end
    end
    table.sort(live, function(a, b) return (a.order or 99) < (b.order or 99) end)
    if #live > 0 then
        lines[#lines + 1] = "- Training assets -"
        for _, e in ipairs(live) do lines[#lines + 1] = _line(e) end
    end

    local shown = 0
    for _, e in ipairs(ME[side] or {}) do
        -- AI support placed with late activation shows once it is in the air.
        if e.client or Group.getByName(e.group) then
            if shown == 0 then lines[#lines + 1] = "- Mission -" end
            if shown < CFG.maxMission then lines[#lines + 1] = _line(e) end
            shown = shown + 1
        end
    end
    if shown > CFG.maxMission then lines[#lines + 1] = "(" .. (shown - CFG.maxMission) .. " more not shown)" end

    if #lines == 1 then lines[2] = "No radio, TACAN or ICLS set by the scripts or in the mission." end
    return table.concat(lines, "\n")
end

-- ============== Init ==============
if not COMMS_Initialized then
    COMMS_Initialized = true
    local ok, err = pcall(_scanMission)
    if not ok and env and env.info then env.info("[Comms] mission scan error: " .. tostring(err)) end
    for _, side in ipairs(CFG.sides) do
        missionCommands.addCommandForCoalition(side, CFG.menuName, nil, function()
            local okc, text = pcall(_card, side)
            trigger.action.outTextForCoalition(side, okc and text or ("[Comms] error: " .. tostring(text)), CFG.showSeconds)
        end)
    end
end
