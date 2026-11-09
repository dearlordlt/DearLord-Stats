-- DearLord Stats : threat window
-- One bar per member of your group on the mob you are fighting: you and your pet when solo,
-- the party and their pets in a dungeon, the top of the list in a raid. 100% means that unit
-- pulls aggro (the game's scaled threat); the unit holding aggro is marked.
-- On this client threat values may be secret in combat. Bars still fill (a status bar takes a
-- secret value), but then there is no sorting and no percentage text, only the threat state.
local ADDON, ns = ...
local N, S, B = ns.N, ns.S, ns.B

local tw = ns.CreateHud("threat", 0, "LEFT")
tw.panelTab = "combat"
tw:Hide()

local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local CLASS_TC = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.5, 0, 0.25 }, ROGUE = { 0.5, 0.75, 0, 0.25 }, DRUID = { 0.75, 1, 0, 0.25 },
    HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.5, 0.25, 0.5 }, PRIEST = { 0.5, 0.75, 0.25, 0.5 }, WARLOCK = { 0.75, 1, 0.25, 0.5 },
    PALADIN = { 0, 0.25, 0.5, 0.75 },
}
-- 0 lower than the tank, 1 higher than the tank (about to pull), 2 has aggro but someone is close, 3 has aggro
local STATE_HEX = { [0] = "9fd89f", [1] = "ffd166", [2] = "ff9a3c", [3] = "ff5a5a" }
local RAID_ROWS = 10
-- the window opens itself when a fight starts (only with a pet out or in a group), keeps the
-- last fight's bars dimmed afterwards, and stays until you close it with its x

local rows = {}
tw.rows = rows
local state = { open = false, hasData = false, stale = false, demoUntil = 0, entries = {} }
ns.threat = state

local function text(parent, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH(justify or "LEFT")
    tw.lines[#tw.lines + 1] = fs
    return fs
end
local function font(fs, delta)
    local db = ns.db
    local size, flags = math.max(8, db.fontSize + delta), db.outline or "OUTLINE"
    if not fs:SetFont(ns.FontPath(), size, flags) then fs:SetFont(STANDARD_TEXT_FONT, size, flags) end
end

tw.title = text(tw)
tw.sub = text(tw, "RIGHT")

local close = CreateFrame("Button", nil, tw)
close.tex = close:CreateTexture(nil, "ARTWORK")
close.tex:SetAllPoints()
close.tex:SetTexture("Interface\\Buttons\\UI-StopButton")
close.tex:SetVertexColor(0.65, 0.65, 0.65)
close:SetScript("OnEnter", function(self) self.tex:SetVertexColor(1, 0.35, 0.35) end)
close:SetScript("OnLeave", function(self) self.tex:SetVertexColor(0.65, 0.65, 0.65) end)
close:SetScript("OnClick", function() ns.CloseThreat() end)
tw.close = close

local function row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, tw)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    local sb = CreateFrame("StatusBar", nil, r)
    sb:SetStatusBarTexture(BAR_TEXTURE)
    sb:SetMinMaxValues(0, 100)
    local bg = sb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    r.edge = sb:CreateTexture(nil, "OVERLAY")          -- a thin strip in the threat-state colour
    r.edge:SetTexture(BAR_TEXTURE)
    r.mark = sb:CreateTexture(nil, "OVERLAY")          -- outline for your own row
    r.mark:SetTexture(BAR_TEXTURE)
    r.mark:SetVertexColor(1, 1, 1, 0.10)
    r.name = text(sb)
    r.value = text(sb, "RIGHT")
    r.bar = sb
    r:Hide()
    rows[i] = r
    return r
end

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

local function fill(r, e, demo)
    local unit = e.unit
    local class = demo and e.class or classOf(e.owner or unit)
    local pet = demo and e.pet or e.owner ~= nil
    -- icon: class crest for players, portrait for pets
    if pet then
        if demo then r.portraitOf = nil; r.icon:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Wolf"); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        elseif SetPortraitTexture then
            local guid = S(UnitGUID and UnitGUID(unit)) or unit
            if r.portraitOf ~= guid then SetPortraitTexture(r.icon, unit); r.portraitOf = guid end
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    elseif class and CLASS_TC[class] then
        local t = CLASS_TC[class]
        r.portraitOf = nil
        r.icon:SetTexture(CLASS_ICONS); r.icon:SetTexCoord(t[1] + 0.02, t[2] - 0.02, t[3] + 0.02, t[4] - 0.02)
    else
        r.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark"); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local cr, cg, cb = colorFor(class, pet)
    r.bar:SetStatusBarColor(cr, cg, cb)
    r.bar:SetValue(e.scaled or 0)                  -- 0-100, may be a secret number
    if demo then r.name:SetText(e.name)
    else
        local name = UnitName and UnitName(unit)
        if name ~= nil then r.name:SetText(name) else r.name:SetText(unit) end
    end
    local st = N(e.status)
    local hex = st and STATE_HEX[st]
    if hex then r.edge:SetVertexColor(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1); r.edge:Show()
    else r.edge:Hide() end
    local scaled = N(e.scaled)
    local tanking = B(e.tanking)
    if tanking then
        r.value:SetText("|cff" .. (hex or STATE_HEX[3]) .. "aggro|r")
    elseif scaled then
        local v = N(e.value)
        local amount = v and v > 0 and (ns.LABEL .. ns.shortNumber(math.floor(v / 100)) .. "|r  ") or ""
        r.value:SetText(amount .. "|cff" .. (hex or "ffffff") .. math.floor(scaled + 0.5) .. "%|r")
    else
        -- secret: let the game write the number if it can, otherwise only the state colour shows
        if not pcall(r.value.SetFormattedText, r.value, "%.0f%%", e.scaled) then r.value:SetText("") end
    end
    r.mark:SetShown(e.isPlayer and true or false)
end

function tw:Layout()
    local fsz = ns.db.fontSize
    local pad, gap = 6, 3
    local barH = fsz + 7
    local W = fsz * 16
    font(self.title, -1); font(self.sub, -2)
    for _, r in ipairs(rows) do font(r.name, -1); font(r.value, -1) end
    for i = 1, self.count or 0 do
        local r = rows[i]
        -- a secret name gives a secret width; such a row just takes the default width
        W = math.max(W, (N(r.name:GetStringWidth()) or 0) + (N(r.value:GetStringWidth()) or 0) + 24)
    end
    W = math.max(W, (N(self.title:GetStringWidth()) or 0) + (N(self.sub:GetStringWidth()) or 0) + fsz + 16 - barH - 4)
    self.title:ClearAllPoints(); self.title:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -pad)
    local csz = fsz
    close:ClearAllPoints(); close:SetPoint("TOPRIGHT", self, "TOPRIGHT", -pad + 1, -pad + 1); close:SetSize(csz, csz)
    self.sub:ClearAllPoints(); self.sub:SetPoint("TOPRIGHT", self, "TOPRIGHT", -pad - csz - 4, -pad - 1)
    local y = pad + fsz + 4
    for i = 1, self.count or 0 do
        local r = rows[i]
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -y)
        r:SetSize(barH + 4 + W, barH)
        r.icon:ClearAllPoints(); r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0); r.icon:SetSize(barH, barH)
        r.bar:ClearAllPoints(); r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", barH + 4, 0); r.bar:SetSize(W, barH)
        r.edge:ClearAllPoints(); r.edge:SetPoint("TOPLEFT", r.bar, "TOPLEFT", 0, 0); r.edge:SetSize(3, barH)
        r.mark:ClearAllPoints(); r.mark:SetAllPoints(r.bar)
        r.name:ClearAllPoints(); r.name:SetPoint("LEFT", r.bar, "LEFT", 8, 0)
        r.value:ClearAllPoints(); r.value:SetPoint("RIGHT", r.bar, "RIGHT", -5, 0)
        y = y + barH + gap
    end
    self:SetWidth(pad * 2 + barH + 4 + W)
    self:SetHeight(y - gap + pad)
end
function tw:Fit() self:Layout() end

local function show(list, demo, mobName)
    local n = 0
    for i, e in ipairs(list) do
        n = i
        local r = row(i)
        fill(r, e, demo)
        r:SetAlpha(1)
        r:Show()
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    tw.count = n
    tw.title:SetText(ns.WHITE .. "Threat|r")
    -- the mob's name goes straight to its own font string: it may be a secret string
    tw.sub:SetTextColor(0.75, 0.75, 0.75)
    if mobName ~= nil then tw.sub:SetText(mobName) else tw.sub:SetText("") end
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
    for i = 1, tw.count or 0 do rows[i]:SetAlpha(0.5) end
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

tw:SetScript("OnEnter", function(self)
    self.bg:Show()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("DearLord Stats: threat")
    GameTooltip:AddLine("100% = that unit pulls aggro from whoever has it.", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("Edge colour: green safe, yellow above the tank, orange has aggro barely, red has aggro.", 0.8, 0.8, 0.8, true)
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
    GameTooltip:AddLine("Drag: move.  Right-click: options.  /dls threat: show or hide.  /dls threat test: preview.", 0.6, 0.8, 1)
    GameTooltip:Show()
end)

-- every fight opens it again, even after a close
ns.On("PLAYER_REGEN_DISABLED", function() if eligible() then state.open = true end; refresh() end, "threat:combat")
-- threat events can fire dozens of times a second in a raid; the bars redraw five times a second
ns.On("PLAYER_TARGET_CHANGED", function() refresh() end, "threat:target")
ns.Every(0.2, refresh, "threat:tick")
ns.OnLogin(refresh, "threat:login")
