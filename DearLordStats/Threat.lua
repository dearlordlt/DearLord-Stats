-- DearLord Stats : threat window
-- One bar per member of your group on the mob you are fighting: you and your pet when solo,
-- the party and their pets in a dungeon, the top of the list in a raid. 100% means that unit
-- pulls aggro (the game's scaled threat); the unit holding aggro is marked.
-- When your own bar passes the warning level (90% by default) while someone else holds aggro, the
-- window's border pulses red, its title says so and a sound plays once: time to ease off.
-- Not while you are the tank.
-- On this client threat values may be secret in combat. Bars still fill (a status bar takes a
-- secret value), but then there is no sorting and no percentage text, only the threat state.
-- Drawn with the same bars as the damage meter (Bars.lua); the corner resizes it.
local ADDON, ns = ...
local N, S, B = ns.N, ns.S, ns.B

local tw = ns.CreateHud("threat", 0, "LEFT")
tw.panelTab = "combat"
tw:Hide()
ns.Chrome(tw, 20)

-- 0 lower than the tank, 1 higher than the tank (about to pull), 2 has aggro but someone is close, 3 has aggro
local STATE_HEX = { [0] = "9fd89f", [1] = "ffd166", [2] = "ff9a3c", [3] = "ff5a5a" }
local RAID_ROWS = 10
-- the window opens itself when a fight starts (only with a pet out or in a group), keeps the
-- last fight's bars dimmed afterwards, and stays until you close it with its x

local state = { open = false, hasData = false, stale = false, demoUntil = 0, entries = {} }
ns.threat = state

-- the bars are the same animated list the damage meter uses
local list = ns.BarList(tw, tw)
tw.list = list
tw.rows = list.order
tw.title = ns.BarText(tw)
tw.sub = ns.BarText(tw, "RIGHT")
tw.sub:SetTextColor(0.75, 0.75, 0.75)

local close = ns.TextButton(tw, "×", function() ns.CloseThreat() end, "Close it until the next fight.")
tw.close = close

-- the warning: a red border that pulses while you are about to pull
local warn = CreateFrame("Frame", nil, tw)
warn:SetAllPoints(tw)
warn:Hide()
for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 }, { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
    local t = warn:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(1, 0.25, 0.25, 1)
    t:SetPoint(side[1], warn, side[1], 0, 0); t:SetPoint(side[2], warn, side[2], 0, 0)
    if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
end
warn:SetScript("OnUpdate", function(self) self:SetAlpha(0.3 + 0.7 * math.abs(math.sin(GetTime() * 5))) end)
tw.warn = warn

local function attackable(unit)
    if not (UnitExists and B(UnitExists(unit))) then return false end
    if UnitIsDead and B(UnitIsDead(unit)) then return false end
    if UnitCanAttack then return B(UnitCanAttack("player", unit)) == true end
    return true
end

-- the mob whose threat list we show: your target, then focus, then your pet's target,
-- then whatever a party member is hitting
local function findMob()
    for _, u in ipairs({ "target", "focus", "pettarget" }) do if attackable(u) then return u end end
    local raid = IsInRaid and B(IsInRaid())
    local n = (GetNumGroupMembers and N(GetNumGroupMembers())) or 0
    for i = 1, raid and math.min(n, 40) or math.min(n, 4) do
        local u = (raid and "raid" or "party") .. i .. "target"
        if attackable(u) then return u end
    end
end

local function units()
    local list = {}
    local function add(u, owner) if UnitExists and B(UnitExists(u)) then list[#list + 1] = { unit = u, owner = owner } end end
    local raid = IsInRaid and B(IsInRaid())
    local n = (GetNumGroupMembers and N(GetNumGroupMembers())) or 0
    if raid then
        for i = 1, math.min(n, 40) do add("raid" .. i); add("raidpet" .. i, "raid" .. i) end
    else
        add("player"); add("pet", "player")
        if IsInGroup and B(IsInGroup()) then
            for i = 1, 4 do add("party" .. i); add("partypet" .. i, "party" .. i) end
        end
    end
    return list
end

local function classOf(unit)
    if not UnitClass then return nil end
    local _, token = UnitClass(unit)
    return S(token)
end

local function readEntry(u, mob)
    if not UnitDetailedThreatSituation then return nil end
    local ok, tanking, status, scaled, raw, value = pcall(UnitDetailedThreatSituation, u.unit, mob)
    if not ok or not ns.exists(status) then return nil end         -- not on this mob's threat list
    local e = { unit = u.unit, owner = u.owner, tanking = tanking, status = status, scaled = scaled, raw = raw, value = value }
    e.plain = N(scaled) ~= nil and N(status) ~= nil
    e.isPlayer = B(UnitIsUnit and UnitIsUnit(u.unit, "player")) or u.unit == "player"
    return e
end

-- probed once per session, so what this client hides can be read from the saved variables
local function probe(mob, entries)
    ns.diagOnce("threatProbe", function()
        local out = {}
        if C_Secrets then
            for _, k in ipairs({ "ShouldUnitThreatValuesBeSecret", "ShouldUnitThreatStateBeSecret" }) do
                local f = C_Secrets[k]
                if f then local ok, v = pcall(f, mob); out[#out + 1] = k .. "=" .. (ok and ns.dump(v) or "error") end
            end
        end
        out[#out + 1] = "combat=" .. tostring(B(UnitAffectingCombat and UnitAffectingCombat("player")))
        for i = 1, math.min(3, #entries) do
            local e = entries[i]
            out[#out + 1] = e.unit .. ":" .. ns.dump(e.tanking) .. "/" .. ns.dump(e.status) .. "/" .. ns.dump(e.scaled) .. "/" .. ns.dump(e.raw) .. "/" .. ns.dump(e.value)
        end
        return table.concat(out, " ")
    end)
end

local function sortEntries(list)
    local allPlain = true
    for _, e in ipairs(list) do if not e.plain then allPlain = false end end
    if allPlain then
        table.sort(list, function(a, b)
            if (a.status >= 2) ~= (b.status >= 2) then return a.status >= 2 end
            if a.scaled ~= b.scaled then return a.scaled > b.scaled end
            return a.unit < b.unit
        end)
    end
    return allPlain
end

local DEMO = {
    { name = "Tankard", class = "WARRIOR", status = 3, scaled = 100, value = 18400, tanking = true },
    { name = "You", class = "HUNTER", status = 1, scaled = 92, value = 16900, isPlayer = true },
    { name = "Pet", class = "HUNTER", status = 0, scaled = 61, value = 11200, pet = true },
    { name = "Healbot", class = "PRIEST", status = 0, scaled = 34, value = 6200 },
    { name = "Frosty", class = "MAGE", status = 0, scaled = 78, value = 14300 },
}

local function colorFor(class, pet)
    local r, g, b = 0.6, 0.6, 0.6
    if class and ns.CensusClassColor then r, g, b = ns.CensusClassColor(class) end
    if pet then r, g, b = r * 0.6, g * 0.6, b * 0.6 end
    return r, g, b
end

-- one bar: class colour and crest (a portrait for a pet), the scaled threat as its length, the raw
-- amount and the percentage on the right, a strip in the threat-state colour on the left
local function itemOf(e, demo)
    local unit = e.unit
    local class = demo and e.class or classOf(e.owner or unit)
    local pet = demo and e.pet or e.owner ~= nil
    local it = { class = class, own = e.isPlayer and true or false, value = 0, max = 100, cells = {} }
    if ns.exists(e.scaled) then it.value = e.scaled end                 -- 0-100, may be a hidden number
    it.r, it.g, it.b = colorFor(class, pet)
    if pet then
        it.class = nil
        if demo then it.icon = "Interface\\Icons\\Ability_Hunter_Pet_Wolf"
        else it.portrait, it.portraitKey = unit, S(UnitGUID and UnitGUID(unit)) or unit end
    end
    if demo then it.name, it.key = e.name, "demo:" .. e.name
    else
        local name = UnitName and UnitName(unit)
        if ns.exists(name) then it.name = name else it.name = unit end   -- the name goes straight to the font string: it may be hidden
        it.key = S(UnitGUID and UnitGUID(unit)) or unit
    end
    local st = N(e.status)
    local hex = st and STATE_HEX[st]
    if hex then it.edge = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 } end
    local scaled = N(e.scaled)
    if B(e.tanking) then
        it.cells[2] = { text = "|cff" .. (hex or STATE_HEX[3]) .. "aggro|r" }
    elseif scaled then
        local v = N(e.value)
        if v and v > 0 then it.cells[1] = { text = ns.LABEL .. ns.shortNumber(math.floor(v / 100)) .. "|r" } end
        it.cells[2] = { text = "|cff" .. (hex or "ffffff") .. math.floor(scaled + 0.5) .. "%|r" }
    else
        it.cells[2] = { fmt = "%.0f%%", arg = e.scaled }               -- hidden: the game writes the number if it can
    end
    return it
end

-- the corner sets the width and how tall the window may grow; it is only as tall as its bars
local PAD, GAP = 5, 2
local function metrics()
    local db = ns.db
    local fsz = db.fontSize or 13
    local headH, barH = fsz + 8, math.max(10, db.meterBarHeight or 18)
    local W, maxH = math.max(150, N(db.threatW) or 250), math.max(60, N(db.threatH) or 150)
    if tw.sizing then W, maxH = N(tw:GetWidth()) or W, N(tw:GetHeight()) or maxH end
    local fit = math.max(1, math.floor((maxH - headH - 2 - PAD + GAP) / (barH + GAP)))
    return fsz, headH, barH, W, fit
end

function tw:Layout()
    if not ns.db then return end
    local fsz, headH, barH, W = metrics()
    self:ApplyChrome(headH)
    ns.BarFont(self.title, -1); ns.BarFont(self.sub, -2)
    local cw = close:Fit(2, headH)
    close:ClearAllPoints(); close:SetPoint("TOPRIGHT", self, "TOPRIGHT", -2, 0)
    self.title:ClearAllPoints(); self.title:SetPoint("TOPLEFT", self, "TOPLEFT", PAD + 1, -(headH - fsz) / 2 + 1)
    local titleW = (N(self.title:GetStringWidth()) or 50) + 6
    self.title:SetWidth(titleW)
    self.sub:ClearAllPoints(); self.sub:SetPoint("TOPRIGHT", self, "TOPRIGHT", -cw - 4, -(headH - fsz) / 2)
    self.sub:SetWidth(math.max(1, W - titleW - cw - PAD - 10))
    -- the bars are only laid out again when something they depend on changed, so they keep sliding
    local sig = table.concat({ W, barH, fsz, tostring(ns.db.font), tostring(ns.db.outline) }, ":")
    if sig ~= self.barSig then
        self.barSig = sig
        list.fontDelta = -1
        list:Layout(W - PAD * 2, barH, GAP, { math.floor(fsz * 3), math.floor(fsz * 3.2) }, 0)
    end
    list.frame:ClearAllPoints(); list.frame:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -headH - 2)
    local n = math.max(1, self.count or 0)
    list.frame:SetSize(W - PAD * 2, list:Height(n))
    if not self.sizing then self:SetSize(W, headH + 2 + list:Height(n) + PAD) end
end
function tw:Fit() self:Layout() end
ns.MakeResizable(tw, "threatW", "threatH", 150, 60, function() tw:Layout(); if ns.RefreshThreat then ns.RefreshThreat() end end)

-- a tank is meant to be on top: no warning for one. Tanking shows as the tank role, or as what a tank
-- wears: a warrior in Defensive Stance, a druid in bear form, a paladin with Righteous Fury on.
local TANK_FORMS = { WARRIOR = { [71] = true }, DRUID = { [5487] = true, [9634] = true } }
local RIGHTEOUS_FURY = 25780
local function isTank()
    if UnitGroupRolesAssigned and S(UnitGroupRolesAssigned("player")) == "TANK" then return true end
    local class = UnitClass and S((select(2, UnitClass("player"))))
    local forms = class and TANK_FORMS[class]
    if forms and GetShapeshiftForm then
        local form = N(GetShapeshiftForm()) or 0
        if form > 0 then
            local id = GetShapeshiftFormInfo and N((select(4, GetShapeshiftFormInfo(form))))
            if id then return forms[id] == true end
            return (class == "WARRIOR" and form == 2) or (class == "DRUID" and form == 1)      -- the usual places on the stance bar
        end
    elseif class == "PALADIN" then
        if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, RIGHTEOUS_FURY)
            if ok and aura ~= nil then return true end
        end
        local name = ns.spellName(RIGHTEOUS_FURY)
        if name and AuraUtil and AuraUtil.FindAuraByName then
            local ok, found = pcall(AuraUtil.FindAuraByName, name, "player")
            if ok and found ~= nil then return true end
        end
    end
    return false
end
ns.ThreatIsTank = isTank

-- about to pull: your bar at the warning level while someone else has the mob
local function pulling(list, demo)
    local db = ns.db
    if db.threatWarn == false then return false end
    local me, holder
    for _, e in ipairs(list) do
        if e.isPlayer then me = e elseif B(e.tanking) then holder = e end
    end
    local scaled = me and N(me.scaled)
    if not (scaled and holder) or B(me.tanking) then return false, scaled end
    if not demo and isTank() then return false, scaled end
    return scaled >= (db.threatWarnAt or 90), scaled
end

local function setWarning(on, scaled, demo)
    local at = ns.db.threatWarnAt or 90
    if not on and state.warnPlayed and (not scaled or scaled < at - 10) then state.warnPlayed = false end   -- dropped well below: armed again
    if on and not state.warnPlayed and not demo then
        state.warnPlayed = true
        state.warnings = (state.warnings or 0) + 1
        if ns.db.threatSound ~= false and PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master") end
    end
    state.warn = on and true or false
    warn:SetShown(state.warn)
end

local function show(entries, demo, mobName)
    -- more units than the window may hold: the top ones, and always your own
    local _, _, _, _, fit = metrics()
    if #entries > fit then
        local keep, mine = {}, nil
        for i, e in ipairs(entries) do
            if i <= fit - 1 then keep[#keep + 1] = e elseif e.isPlayer then mine = e end
        end
        keep[#keep + 1] = mine or entries[fit]
        entries = keep
    end
    local items = {}
    for i, e in ipairs(entries) do items[i] = itemOf(e, demo) end
    list:SetLive(not demo and not state.stale and B(UnitAffectingCombat and UnitAffectingCombat("player")) == true)
    list:SetData(items)
    tw.rows, tw.count = list.order, #items
    local on, scaled = pulling(entries, demo)
    setWarning(on, scaled, demo)
    tw.title:SetText(on and (ns.RED .. "Ease off|r") or (ns.WHITE .. "Threat|r"))
    -- the mob's name goes straight to its own font string: it may be a secret string
    ns.BarSetText(tw.sub, mobName)
    tw:Layout()
    tw:Show()
end

-- worth showing: a pet out, or a party or raid around you
local function eligible()
    if UnitExists and B(UnitExists("pet")) then return true end
    return (IsInGroup and B(IsInGroup())) or (IsInRaid and B(IsInRaid())) or false
end

-- the fight is over or the mob is gone: keep the last bars, dimmed
local function goStale()
    if state.stale then return end
    state.stale = true
    setWarning(false)
    state.warnPlayed = false
    tw.title:SetText(ns.WHITE .. "Threat|r")
    list:SetLive(false)
    list:SetDim(true)
end

local function refresh()
    local db = ns.db
    if not db then return end
    if db.showThreat == false then tw:Hide(); return end
    local now = GetTime()
    if state.demoUntil > now then
        show(DEMO, true, "preview")
        state.demo = true
        return
    end
    if state.demo then state.demo, state.hasData = false, false end     -- the preview replaced the last bars
    if not state.open or not eligible() then tw:Hide(); return end
    local mob = findMob()
    local list = {}
    if mob then
        for _, u in ipairs(units()) do
            local e = readEntry(u, mob)
            if e then list[#list + 1] = e end
        end
    end
    if #list == 0 then
        if state.hasData then goStale(); tw:Show() else tw:Hide() end
        return
    end
    probe(mob, list)
    state.hasData, state.stale = true, false
    local sorted = sortEntries(list)
    local raid = IsInRaid and B(IsInRaid())
    if raid and #list > RAID_ROWS then
        -- keep the top rows, and always your own
        local keep, mine = {}, nil
        for i, e in ipairs(list) do
            if i <= RAID_ROWS - 1 then keep[#keep + 1] = e elseif e.isPlayer then mine = e end
        end
        if mine then keep[#keep + 1] = mine elseif list[RAID_ROWS] then keep[#keep + 1] = list[RAID_ROWS] end
        list = keep
    end
    state.entries, state.sorted = list, sorted
    show(list, false, UnitName and UnitName(mob))
end
ns.RefreshThreat = refresh

function ns.CloseThreat()
    state.open, state.demoUntil = false, 0
    tw:Hide()
end
-- /dls threat: open it now (with the last fight's bars) or close it
function ns.ToggleThreat()
    if tw:IsShown() then ns.CloseThreat(); return false end
    state.open = true
    refresh()
    return tw:IsShown()
end

function ns.ThreatPreview(seconds)
    state.demoUntil = GetTime() + (seconds or 20)
    refresh()
end

local function explain()
    GameTooltip:SetOwner(tw, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("DearLord Stats: threat")
    GameTooltip:AddLine("100% = that unit pulls aggro from whoever has it.", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("Edge colour: green safe, yellow above the tank, orange has aggro barely, red has aggro.", 0.8, 0.8, 0.8, true)
    if ns.db.threatWarn ~= false then
        GameTooltip:AddLine(isTank() and "You are tanking (role, stance, bear form or Righteous Fury): no pull warning."
            or ("The border pulses red when you pass " .. (ns.db.threatWarnAt or 90) .. "% while someone else has aggro."), 0.8, 0.8, 0.8, true)
    end
    if state.sorted == false then
        GameTooltip:AddLine("This client hides threat numbers in this fight, so the bars are not sorted.", 1, 0.82, 0.4, true)
    end
    for _, e in ipairs(state.entries or {}) do
        local v, raw = N(e.value), N(e.raw)
        if v then
            local name = S(UnitName and UnitName(e.unit)) or e.unit
            GameTooltip:AddDoubleLine(name, ns.shortNumber(math.floor(v / 100)) .. (raw and string.format("  (%.0f%% raw)", raw) or ""), 0.8, 0.8, 0.8, 1, 1, 1)
        end
    end
    if state.stale then GameTooltip:AddLine("Dimmed: the last fight. Opens again with the next one; the x closes it.", 0.6, 0.6, 0.6, true) end
    GameTooltip:AddLine("Drag: move.  Corner: width and how tall it may grow.  Right-click: options.  /dls threat: show or hide.  /dls threat test: preview.", 0.6, 0.8, 1, true)
    GameTooltip:Show()
end
tw:SetScript("OnEnter", explain)
list.onEnter = explain
list.onLeave = function() GameTooltip:Hide() end
list.onClick = function(_, button)
    if button == "RightButton" then ns.ShowMenu(tw) else ns.TogglePanel(tw.panelTab) end
end

-- every fight opens it again, even after a close
ns.On("PLAYER_REGEN_DISABLED", function() if eligible() then state.open = true end; refresh() end, "threat:combat")
-- threat events can fire dozens of times a second in a raid; the bars redraw five times a second
ns.On("PLAYER_TARGET_CHANGED", function() refresh() end, "threat:target")
ns.Every(0.2, refresh, "threat:tick")
ns.OnLogin(refresh, "threat:login")
