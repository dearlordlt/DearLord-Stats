-- DearLord Stats : party targets
-- Beside each party member's frame, a small frame for what that member is targeting: its name
-- and health, coloured red for something you can attack, by class for a player. A click targets
-- it, so you can pick up the tank's mob or the healer's patient.
-- Each frame is a secure unit button for "partyNtarget": the game shows and hides it by itself,
-- also in a fight, and takes the click. Placing and sizing it can only be done out of combat, so
-- it follows the party frames again after the fight if they moved during one.
-- No event fires for somebody else's target, so name and health are read five times a second.
local ADDON, ns = ...
local N, S, B = ns.N, ns.S, ns.B

local MAX, GAP = 4, 2
ns.PARTY_TARGET_SIDES = { { key = "right", name = "Right" }, { key = "left", name = "Left" }, { key = "below", name = "Below" }, { key = "above", name = "Above" } }

local buttons = {}
local state = { signature = nil, attached = 0, mode = nil }
ns.partyTargets = state
state.buttons = buttons

local function inCombat() return InCombatLockdown and InCombatLockdown() and true or false end

local function create(n)
    local unit = "party" .. n .. "target"
    local ok, b = pcall(CreateFrame, "Button", "DearLordStats_PartyTarget" .. n, UIParent, "SecureUnitButtonTemplate")
    if not ok or not b then b = CreateFrame("Button", "DearLordStats_PartyTarget" .. n, UIParent); state.noSecure = true end
    b.unit, b.owner = unit, "party" .. n
    b:SetAttribute("unit", unit)
    b:SetAttribute("type1", "target")                           -- left click: target what they target
    b:RegisterForClicks("AnyUp", "AnyDown")                     -- the client acts on press or release, by a setting
    b:SetFrameStrata("LOW")
    b:Hide()
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.75)
    b.bar = CreateFrame("StatusBar", nil, b)
    b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1); b.bar:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    b.bar:SetMinMaxValues(0, 100)
    b.bar:EnableMouse(false)                                    -- the click belongs to the button under it
    b.name = b.bar:CreateFontString(nil, "OVERLAY")
    b.name:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.pct = b.bar:CreateFontString(nil, "OVERLAY")
    b.pct:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    b.pct:SetJustifyH("RIGHT")
    -- a white edge when it is also your own target
    b.edge = {}
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetPoint(side[1], b, side[1], 0, 0); t:SetPoint(side[2], b, side[2], 0, 0)
        if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
        t:Hide()
        b.edge[#b.edge + 1] = t
    end
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetUnit then GameTooltip:SetUnit(self.unit) end
        GameTooltip:AddLine("Click: target it", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    buttons[n] = b
    return b
end
for n = 1, MAX do create(n) end

-- the game's own frame of each party member that is on screen: raid-style first, then the classic ones
local function memberFrames()
    local out, found = {}, 0
    local function take(f, unit)
        local n = unit and tonumber(unit:match("^party(%d)$"))
        if n and n <= MAX and not out[n] and f.IsVisible and f:IsVisible() then out[n] = f; found = found + 1 end
    end
    for i = 1, 5 do
        local f = _G["CompactPartyFrameMember" .. i]
        if type(f) == "table" then take(f, S(f.displayedUnit) or S(f.unit)) end
    end
    local pf = _G.PartyFrame
    if type(pf) == "table" then
        for i = 1, MAX do
            local f = pf["MemberFrame" .. i]
            if type(f) == "table" then take(f, S(f.unit) or S(f.unitToken) or ("party" .. i)) end
        end
    end
    return out, found
end

local POINTS = {
    right = { "LEFT", "RIGHT", GAP, 0 }, left = { "RIGHT", "LEFT", -GAP, 0 },
    below = { "TOP", "BOTTOM", 0, -GAP }, above = { "BOTTOM", "TOP", 0, GAP },
}

-- show and hide: the game does it from the unit, also in a fight; never in a raid, where party frames are away
local function watch(b, on)
    if state.noSecure then return end
    if RegisterStateDriver and UnregisterStateDriver then
        if on then RegisterStateDriver(b, "visibility", "[group:raid] hide; [@" .. b.unit .. ",exists] show; hide")
        else UnregisterStateDriver(b, "visibility"); b:Hide() end
        state.mode = "driver"
    elseif RegisterUnitWatch and UnregisterUnitWatch then
        if on then RegisterUnitWatch(b) else UnregisterUnitWatch(b); b:Hide() end
        state.mode = "watch"
    else
        state.mode = "manual"
    end
end

-- place every frame beside its party member; out of combat only
local function attach(force)
    local db = ns.db
    if not db or inCombat() then return end
    local on = db.partyTargets ~= false
    local side = POINTS[db.partyTargetSide] and db.partyTargetSide or "right"
    local frames, found = memberFrames()
    local parts = { tostring(on), side, tostring(db.partyTargetWidth) }
    for n = 1, MAX do
        local f = frames[n]
        parts[#parts + 1] = f and (tostring(f) .. ":" .. tostring(N(f:GetHeight())) .. ":" .. tostring(N(f:GetWidth())) .. ":" .. tostring(f.GetEffectiveScale and N(f:GetEffectiveScale()))) or "-"
    end
    local signature = table.concat(parts, "|")
    if signature == state.signature and not force then return end
    state.signature, state.attached = signature, found
    local p = POINTS[side]
    local sideways = side == "right" or side == "left"
    for n = 1, MAX do
        local b, f = buttons[n], frames[n]
        if state.on ~= on then watch(b, on) end
        if not on then b:Hide() end
        if on then
            if f then
                -- the party frames have their own size setting: take their scale, so the numbers below are in their units
                local fs, us = f.GetEffectiveScale and N(f:GetEffectiveScale()), UIParent.GetEffectiveScale and N(UIParent:GetEffectiveScale())
                b:SetScale((fs and us and us > 0) and fs / us or 1)
                local fh, fw = N(f:GetHeight()) or 36, N(f:GetWidth()) or 72
                if sideways then b:SetSize(db.partyTargetWidth or 96, fh) else b:SetSize(fw, math.max(14, math.floor(fh * 0.4))) end
                b:ClearAllPoints()
                b:SetPoint(p[1], f, p[2], p[3], p[4])
                b.placed = "frame"
            elseif found == 0 and not b.placed then
                -- none of the game's party frames found: a plain column at the left of the screen
                b:SetScale(1)
                b:SetSize(db.partyTargetWidth or 96, 22)
                b:ClearAllPoints()
                b:SetPoint("LEFT", UIParent, "LEFT", 220, 60 - (n - 1) * 24)
                b.placed = "column"
            end
            local h = N(b:GetHeight()) or 22
            local size = math.max(8, math.min(12, math.floor(h * 0.42)))
            b.name:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE"); b.pct:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
            b.pct:ClearAllPoints(); b.pct:SetPoint("RIGHT", b.bar, "RIGHT", -3, 0)
            b.name:ClearAllPoints(); b.name:SetPoint("LEFT", b.bar, "LEFT", 3, 0); b.name:SetPoint("RIGHT", b.pct, "LEFT", -2, 0)
        end
    end
    state.on = on
    if found > 0 then
        ns.diagOnce("partyTargetProbe", function()
            local f = frames[1] or frames[2] or frames[3] or frames[4]
            return "frames=" .. found .. " first=" .. tostring(f.GetName and f:GetName()) .. " mode=" .. tostring(state.mode) .. " secure=" .. tostring(not state.noSecure)
        end)
    end
end
ns.PlacePartyTargets = function() attach(true) end

local function paint(b)
    local unit = b.unit
    local name = UnitName and UnitName(unit)
    if name ~= nil then b.name:SetText(name) else b.name:SetText("") end      -- may be a hidden string: it goes straight in
    local hp, max = UnitHealth and UnitHealth(unit), UnitHealthMax and UnitHealthMax(unit)
    if hp ~= nil and max ~= nil then
        pcall(b.bar.SetMinMaxValues, b.bar, 0, max)             -- a status bar takes hidden numbers
        pcall(b.bar.SetValue, b.bar, hp)
    end
    local h, m = N(hp), N(max)
    b.pct:SetText((h and m and m > 0) and (math.floor(h / m * 100 + 0.5) .. "%") or "")
    local r, g, bl = 0.35, 0.75, 0.35                           -- friendly
    if UnitIsDead and B(UnitIsDead(unit)) then r, g, bl = 0.45, 0.45, 0.45
    elseif UnitIsPlayer and B(UnitIsPlayer(unit)) then
        local class = UnitClass and S((select(2, UnitClass(unit))))
        if class and ns.CensusClassColor then r, g, bl = ns.CensusClassColor(class) end
    elseif UnitCanAttack and B(UnitCanAttack("player", unit)) then r, g, bl = 0.8, 0.25, 0.22 end
    b.bar:SetStatusBarColor(r, g, bl)
    local mine = UnitIsUnit and B(UnitIsUnit(unit, "target")) or false
    if b.mine ~= mine then
        b.mine = mine
        for _, t in ipairs(b.edge) do t:SetShown(mine) end
    end
end

local function refresh()
    local db = ns.db
    if not db or db.partyTargets == false then return end
    for n = 1, MAX do
        local b = buttons[n]
        if state.mode == "manual" or state.noSecure then          -- nothing shows it for us: do it by hand, out of combat
            if not inCombat() then b:SetShown(UnitExists ~= nil and B(UnitExists(b.unit)) == true and not (IsInRaid and B(IsInRaid()))) end
        end
        if b:IsShown() then paint(b) end
    end
end
ns.RefreshPartyTargets = refresh

----------------------------------------------------------------------
-- the party frame while you are alone (a setting, off by default)
----------------------------------------------------------------------
-- With raid-style party frames the game draws your own frame among the party's, and hides the
-- whole party frame when you are in no group. This keeps it up: whenever the game hides it, it
-- is shown again. Only out of combat, because an addon may not show that frame in a fight, and
-- only by showing it: nothing of the frame's own is called or changed.
local solo = { hooked = false, shownByUs = false }
state.solo = solo

local function raidStyle()
    local em = _G.EditModeManagerFrame
    if type(em) == "table" and em.UseRaidStylePartyFrames then
        local ok, v = pcall(em.UseRaidStylePartyFrames, em)
        if ok then return B(v) == true end
    end
    return true                                                 -- cannot ask: the raid-style frame is the one with a place for you
end

local function applySolo()
    local db, f = ns.db, _G.CompactPartyFrame
    if not db or type(f) ~= "table" or not f.Show then solo.missing = true; return end
    solo.missing = false
    if db.partySolo and not solo.hooked and hooksecurefunc and f.UpdateVisibility then
        solo.hooked = true
        hooksecurefunc(f, "UpdateVisibility", function() ns.ApplyPartySolo() end)     -- the game hid or showed it: look again
    end
    if inCombat() then return end                               -- after the fight
    local grouped = (IsInGroup and B(IsInGroup())) or (IsInRaid and B(IsInRaid())) or false
    if grouped then solo.shownByUs = false; return end          -- in a group it is the game's own business
    if db.partySolo and raidStyle() then
        if not f:IsShown() then f:Show(); solo.shows = (solo.shows or 0) + 1 end
        solo.shownByUs = true
        ns.diagOnce("partySoloProbe", function() return "shown=" .. tostring(f:IsShown() and true or false) .. " hooked=" .. tostring(solo.hooked) end)
    elseif solo.shownByUs then
        f:Hide()
        solo.shownByUs = false
    end
end
ns.ApplyPartySolo = applySolo

for _, ev in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
    ns.On(ev, function() attach(); applySolo() end, "partyTargets:" .. ev)
end
ns.Every(1, function() if ns.db and (ns.db.partySolo or solo.shownByUs) then applySolo() end end, "partySolo:tick")
ns.On("PLAYER_TARGET_CHANGED", refresh, "partyTargets:target")
ns.Every(0.2, refresh, "partyTargets:tick")
-- the party frames can be moved or resized in Edit Mode at any time: look again once a second
ns.Every(1, function() if (IsInGroup and B(IsInGroup())) or state.on ~= (ns.db and ns.db.partyTargets ~= false) then attach() end end, "partyTargets:place")
ns.OnLogin(function()
    if ns.db.diag then ns.db.diag.partyTargetProbe, ns.db.diag.partySoloProbe = nil, nil end
    attach(true)
    applySolo()
end, "partyTargets:login")
