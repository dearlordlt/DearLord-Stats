-- DearLord Stats : Growl reminder
-- In a dungeon or raid group a pet with Growl on autocast pulls mobs off the tank; solo, a pet
-- with Growl off holds nothing. When the setting does not fit where you are, the pet line in the
-- XP window says so and a small banner offers the switch: one click runs /petautocastoff (or on).
-- The click goes through a secure macro button, the only way an addon may change pet autocast;
-- that button can only be shown, hidden or moved out of combat.
local ADDON, ns = ...
local N, S, B = ns.N, ns.S, ns.B

local GROWL_IDS = { [2649] = true, [14916] = true, [14917] = true, [14918] = true, [14919] = true, [14920] = true, [14921] = true, [27047] = true }
local ICON = "Interface\\Icons\\Ability_Physical_Taunt"

local state = { on = nil, want = nil, warn = nil, dismissed = false }
ns.growl = state

local function growlName()
    return (C_Spell and C_Spell.GetSpellName and S(C_Spell.GetSpellName(2649))) or "Growl"
end

-- true / false, or nil when the pet has no Growl or the client will not say
local function readAutocast()
    local name = growlName()
    if GetPetActionInfo then
        for i = 1, N(NUM_PET_ACTION_SLOTS) or 10 do
            local ok, n, _, _, _, _, enabled, spellID = pcall(GetPetActionInfo, i)
            spellID = ok and N(spellID) or nil
            if ok and (S(n) == name or (spellID and GROWL_IDS[spellID])) then
                local e = B(enabled)
                if e ~= nil then return e, "bar" end
            end
        end
    end
    if C_Spell and C_Spell.GetSpellAutoCast then
        local ok, allowed, enabled = pcall(C_Spell.GetSpellAutoCast, name)
        if ok and B(allowed) then
            local e = B(enabled)
            if e ~= nil then return e, "spell" end
        end
    end
    return nil
end

-- false: Growl should be off (grouped inside a dungeon or raid); true: on (alone in the world);
-- nil: no opinion (no pet, grouped outside, battlegrounds)
local function wanted()
    if not (UnitExists and B(UnitExists("pet"))) then return nil end
    local inside, kind = false, nil
    if IsInInstance then local a, b = IsInInstance(); inside, kind = B(a) == true, S(b) end
    local grouped = (IsInGroup and B(IsInGroup())) or (IsInRaid and B(IsInRaid())) or false
    if grouped and inside and (kind == "party" or kind == "raid") then return false end
    if not grouped and not inside then return true end
    return nil
end

-- "on" = it is on and should be off, "off" = it is off and should be on
function ns.GrowlWarning() return state.warn end

----------------------------------------------------------------------
-- the banner
----------------------------------------------------------------------
local holder = CreateFrame("Frame", "DearLordStats_Growl", UIParent)
holder:SetFrameStrata("MEDIUM")
holder:SetClampedToScreen(true)
holder:SetMovable(true)
holder:EnableMouse(true)
holder:RegisterForDrag("LeftButton")
holder:Hide()
state.holder = holder

local bg = holder:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.7)
local stripe = holder:CreateTexture(nil, "BORDER")
stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
local icon = holder:CreateTexture(nil, "ARTWORK")
icon:SetTexture(ICON)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local function fontString(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH("LEFT")
    return fs
end

-- a missing template must not take the reminder down with it: the banner then only informs
local okBtn, btn = pcall(CreateFrame, "Button", "DearLordStats_GrowlButton", holder, "SecureActionButtonTemplate")
if not okBtn or not btn then btn = CreateFrame("Button", nil, holder); state.noSecure = true end
btn:RegisterForClicks("AnyUp", "AnyDown")           -- the client acts on press or release, by a setting
state.button = btn
local title = fontString(btn)
local hint = fontString(btn)

local function inCombat() return InCombatLockdown and InCombatLockdown() and true or false end

local function place()
    if inCombat() or state.dragging then return end
    local db = ns.db
    local pos = db.growl
    holder:ClearAllPoints()
    holder:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    holder:SetScale(db.scale)
end
ns.PlaceGrowl = place

local function layout()
    local db = ns.db
    local fsz = db.fontSize
    local flags = db.outline or "OUTLINE"
    if not title:SetFont(ns.FontPath(), fsz, flags) then title:SetFont(STANDARD_TEXT_FONT, fsz, flags) end
    if not hint:SetFont(ns.FontPath(), math.max(8, fsz - 2), flags) then hint:SetFont(STANDARD_TEXT_FONT, math.max(8, fsz - 2), flags) end
    local pad = 6
    local isz = fsz * 2 + 6
    local w = math.max(title:GetStringWidth(), hint:GetStringWidth())
    holder:SetSize(4 + pad + isz + 8 + w + pad, isz + pad * 2)
    stripe:ClearAllPoints(); stripe:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0); stripe:SetSize(4, isz + pad * 2)
    icon:ClearAllPoints(); icon:SetPoint("LEFT", holder, "LEFT", 4 + pad, 0); icon:SetSize(isz, isz)
    -- the icon is the drag handle; the text is the button
    btn:ClearAllPoints(); btn:SetPoint("TOPLEFT", holder, "TOPLEFT", 4 + pad + isz, 0); btn:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    title:ClearAllPoints(); title:SetPoint("TOPLEFT", btn, "TOPLEFT", 8, -pad - 1)
    hint:ClearAllPoints(); hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
end

local function configure(warn)
    local name = growlName()
    local macro
    if warn == "on" then
        title:SetText(ns.RED .. name .. " is ON|r")
        hint:SetText(ns.LABEL .. "your pet will taunt off the tank|r  " .. ns.WHITE .. "click to turn it off|r")
        stripe:SetVertexColor(1, 0.35, 0.35, 1)
        macro = "/petautocastoff " .. name
    else
        title:SetText(ns.AMBER .. name .. " is OFF|r")
        hint:SetText(ns.LABEL .. "your pet will not hold aggro|r  " .. ns.WHITE .. "click to turn it on|r")
        stripe:SetVertexColor(1, 0.82, 0.3, 1)
        macro = "/petautocaston " .. name
    end
    if state.macro ~= macro then
        btn:SetAttribute("type1", "macro")
        btn:SetAttribute("macrotext1", macro)
        state.macro = macro
    end
    layout()
end

local function update()
    local db = ns.db
    if not db then return end
    local combat = inCombat()
    local on, how = readAutocast()
    local want = wanted()
    if on == nil and want ~= nil and combat then return end        -- hidden for the moment: keep what was known
    state.on, state.want = on, want
    local warn = db.growlWarn ~= false and want ~= nil and on ~= nil and on ~= want
    state.warn = warn and (on and "on" or "off") or nil
    if on ~= nil then
        ns.diagOnce("growlProbe", function() return "autocast=" .. tostring(on) .. " via " .. tostring(how) .. " secure=" .. tostring(not state.noSecure) end)
    end
    if not warn then state.dismissed = false end
    local show = warn and not state.dismissed
    if combat then
        -- a secure frame cannot be shown or hidden in a fight; it can only fade
        if holder:IsShown() then holder:SetAlpha(show and db.alpha or 0) end
        return
    end
    if show then
        configure(state.warn)
        place()
        holder:SetAlpha(db.alpha)
        holder:Show()
    else
        holder:Hide()
    end
end
ns.RefreshGrowl = update

holder:SetScript("OnDragStart", function(self)
    if not ns.db.locked and not inCombat() then state.dragging = true; self:StartMoving() end
end)
holder:SetScript("OnDragStop", function(self)
    if not state.dragging then return end
    state.dragging = nil
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint(1)
    local pos = ns.db.growl
    pos.point, pos.x, pos.y = point, x, y
end)

local function tooltip(self)
    GameTooltip:SetOwner(holder, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("DearLord Stats: " .. growlName())
    if state.warn == "on" then
        GameTooltip:AddLine("You are grouped in a dungeon or raid and Growl is on autocast.", 0.8, 0.8, 0.8, true)
    else
        GameTooltip:AddLine("You are on your own and Growl is not on autocast.", 0.8, 0.8, 0.8, true)
    end
    GameTooltip:AddLine("Click the text: switch it.  Right-click: leave it as it is.  Drag the icon: move.", 0.6, 0.8, 1, true)
    GameTooltip:Show()
end
holder:SetScript("OnEnter", tooltip)
holder:SetScript("OnLeave", function() GameTooltip:Hide() end)
btn:SetScript("OnEnter", tooltip)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- after a click: did the game take it? (press and release both arrive here)
local lastClick = 0
btn:SetScript("PostClick", function(_, button)
    if button == "RightButton" then
        state.dismissed = true
        update()
        return
    end
    local now = GetTime()
    if now - lastClick < 1 then return end
    lastClick = now
    local before = state.warn
    ns.After(0.7, function()
        update()
        local d = ns.db.diag
        if state.warn == before and before ~= nil then
            if d then d.growlClick = "no effect" end
            ns.say("could not switch " .. growlName() .. " from here: right-click it on your pet bar")
        elseif d then
            d.growlClick = "worked"
        end
    end, "growl:check")
end)

for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PET_BAR_UPDATE", "PLAYER_REGEN_ENABLED" }) do
    ns.On(ev, function() update() end, "growl:" .. ev)
end
ns.On("UNIT_PET", function(unit) if unit == nil or S(unit) == "player" then update() end end, "growl:pet")
ns.Every(2, update, "growl:tick")
ns.OnLogin(function()
    if ns.db.diag then ns.db.diag.growlProbe = nil end
    update()
end, "growl:login")
