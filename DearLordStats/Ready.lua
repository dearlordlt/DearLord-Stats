-- DearLord Stats : ready check
-- When you join a group, or walk into a dungeon or raid with one, a short list of what you are
-- missing: food, water, ammunition, bag room, worn gear, and what your class burns or wears
-- (reagents, soul shards, poisons, a pet). Everything in order: nothing shows.
--
-- A thing is only asked for when this character can be expected to have it, judged from what the
-- client itself says, never from the level:
--   a reagent     only when a spell that burns it is known (Ankh with Reincarnation, seeds with Rebirth)
--   poisons       only when the rogue has learned Poisons or carries some
--   ammunition    only once this character has been seen carrying some
--   a pet         only when the spell that calls one is known
--   food, water   only when the client tells which items are food and drink
local ADDON, ns = ...
local N, S, B, T = ns.N, ns.S, ns.B, ns.T

local FOOD_MIN, WATER_MIN, AMMO_MIN, SLOTS_MIN, DURABILITY_MIN, POISON_SOON = 4, 4, 200, 4, 30, 300
local MANA = { DRUID = true, HUNTER = true, MAGE = true, PALADIN = true, PRIEST = true, SHAMAN = true, WARLOCK = true }
local FOOD_SPELL, DRINK_SPELL = 433, 430                   -- the buffs every food and every drink give
local PROJECTILE = 6                                       -- item class of arrows and bullets
local OK_ICON, NO_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t ", "|TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t "

-- what each class burns: asked for when one of the spells is known; `tiers` lists the best rank first
local REAGENTS = {
    SHAMAN = { { use = "Reincarnation", tiers = { { 17030, "Ankh", { 20608 } } } } },
    PALADIN = { { use = "Divine Intervention", tiers = { { 17033, "Symbol of Divinity", { 19752 } } } },
        { use = "Greater Blessings", min = 5, tiers = { { 21177, "Symbol of Kings", { 25782, 25916, 25894, 25918, 25898, 25895, 25890, 25899 } } } } },
    PRIEST = { { use = "group prayers", tiers = { { 17029, "Sacred Candle", { 21564, 27681, 27683 } }, { 17028, "Holy Candle", { 21562 } } } } },
    MAGE = { { use = "Arcane Brilliance", tiers = { { 17020, "Arcane Powder", { 23028 } } } } },
    DRUID = { { use = "Rebirth", tiers = { { 17038, "Ironwood Seed", { 20748 } }, { 17037, "Hornbeam Seed", { 20747 } }, { 17036, "Ashwood Seed", { 20742 } },
            { 17035, "Stranglethorn Seed", { 20739 } }, { 17034, "Maple Seed", { 20484 } } } },
        { use = "Gift of the Wild", tiers = { { 17026, "Wild Thornroot", { 21850 } }, { 17021, "Wild Berries", { 21849 } } } } },
    ROGUE = { { use = "Vanish", tiers = { { 5140, "Flash Powder", { 1856, 1857 } } } }, { use = "Blind", tiers = { { 5530, "Blinding Powder", { 2094 } } } } },
    WARLOCK = { { use = "summons and stones", min = 2, tiers = { { 6265, "Soul Shard", { 697, 712, 691, 6201, 693 } } } } },
}
local POISONS_SPELL = 2842
local POISON_ITEMS = { 6947, 6949, 6950, 8926, 8927, 8928, 2892, 2893, 8984, 8985, 20844, 3775, 3776, 5237, 6951, 9186, 10918, 10920, 10921, 10922 }
local PET_SPELLS = { HUNTER = { 883, 1515 }, WARLOCK = { 688, 697, 712, 691 } }       -- Call Pet, Tame Beast; the demons

local state = { active = false, dismissed = false, fullUntil = 0, grouped = false, inside = false }
ns.ready = state

local function known(id)
    if IsPlayerSpell and B(IsPlayerSpell(id)) then return true end
    if IsSpellKnown and B(IsSpellKnown(id)) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnown and B(C_SpellBook.IsSpellKnown(id)) then return true end
    return false
end
local function anyKnown(ids) for _, id in ipairs(ids) do if known(id) then return true end end return false end

-- what an item is: "food", "drink", "both", "ammo" or false; asked once per item
local kinds = {}
local function itemSpellName(id)
    local fn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not fn then return nil end
    local ok, name = pcall(fn, id)
    return ok and S(name) or nil
end
local function kindOf(id)
    local k = kinds[id]
    if k ~= nil then return k end
    k = false
    local instant = C_Item and C_Item.GetItemInfoInstant
    local class = instant and N((select(6, instant(id))))
    if class == PROJECTILE then k = "ammo"
    else
        local spell = itemSpellName(id)
        if spell then
            -- the name in the client's language, and the English one
            local food = C_Spell and C_Spell.GetSpellName and S(C_Spell.GetSpellName(FOOD_SPELL))
            local drink = C_Spell and C_Spell.GetSpellName and S(C_Spell.GetSpellName(DRINK_SPELL))
            if spell == food or spell == "Food" then k = "food" elseif spell == drink or spell == "Drink" then k = "drink" elseif spell == "Refreshment" then k = "both" end
        end
        if class == nil and not spell and instant then return false end      -- not loaded yet: ask again next time
    end
    kinds[id] = k
    return k
end

-- one pass over the bags: counts per item, food, drink, ammunition, free slots
local function bags()
    local CC = C_Container
    local out = { items = {}, food = 0, drink = 0, ammo = 0, free = nil }
    if not (CC and CC.GetContainerNumSlots and CC.GetContainerItemInfo) then return out end
    for bag = 0, 4 do
        for slot = 1, N(CC.GetContainerNumSlots(bag)) or 0 do
            local info = T(CC.GetContainerItemInfo(bag, slot))
            local id = info and N(info.itemID)
            if id then
                local n = N(info.stackCount) or 1
                out.items[id] = (out.items[id] or 0) + n
                local k = kindOf(id)
                if k == "food" or k == "both" then out.food = out.food + n end
                if k == "drink" or k == "both" then out.drink = out.drink + n end
                if k == "ammo" then out.ammo = out.ammo + n end
            end
        end
        if CC.GetContainerNumFreeSlots then
            local free, family = CC.GetContainerNumFreeSlots(bag)
            free, family = N(free), N(family) or 0
            if free and family == 0 then out.free = (out.free or 0) + free end       -- quivers and herb bags hold no loot
        end
    end
    return out
end

local function lowestDurability()
    if not GetInventoryItemDurability then return nil end
    local low
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        cur, max = N(cur), N(max)
        if cur and max and max > 0 then
            local pct = math.floor(cur / max * 100)
            if not low or pct < low then low = pct end
        end
    end
    return low
end

local function className() return UnitClass and S((select(2, UnitClass("player")))) or nil end

-- every check that applies to this character: { key, ok, text }
function ns.ReadyList()
    local class, list, b = className(), {}, bags()
    local function add(key, ok, text) list[#list + 1] = { key = key, ok = ok and true or false, text = text } end

    -- for everyone
    if b.free then add("bags", b.free >= SLOTS_MIN, b.free == 0 and "Bags are full" or ("Bags: " .. b.free .. " free slot" .. (b.free == 1 and "" or "s"))) end
    local dur = lowestDurability()
    if dur then add("gear", dur >= DURABILITY_MIN, dur == 0 and "A piece of gear is broken" or ("Gear: lowest piece at " .. dur .. "%")) end
    local tellsFood = ((C_Item and C_Item.GetItemSpell) or GetItemSpell) ~= nil
    if tellsFood then
        add("food", b.food >= FOOD_MIN, b.food == 0 and "No food" or ("Food: " .. b.food))
        if class and MANA[class] then add("water", b.drink >= WATER_MIN, b.drink == 0 and "No water" or ("Water: " .. b.drink)) end
    end

    -- ammunition, once this character has carried some
    local char = ns.char
    if b.ammo > 0 and char then char.usesAmmo = true end
    if class == "HUNTER" and char and char.usesAmmo then
        add("ammo", b.ammo >= AMMO_MIN, b.ammo == 0 and "Out of ammunition" or ("Ammunition: " .. b.ammo))
    end

    -- a pet, when the spell that calls one is known
    local petSpells = class and PET_SPELLS[class]
    if petSpells and anyKnown(petSpells) then
        local out = UnitExists and B(UnitExists("pet"))
        local dead = out and UnitIsDead and B(UnitIsDead("pet"))
        local what = class == "WARLOCK" and "demon" or "pet"
        if not out then add("pet", false, "No " .. what .. " out")
        elseif dead then add("pet", false, "Your " .. what .. " is dead")
        else
            local mood = class == "HUNTER" and ns.PetMood and select(4, ns.PetMood()) or nil
            add("pet", mood ~= 1, mood == 1 and "Your pet is unhappy: feed it" or (what:gsub("^%l", string.upper) .. " is out"))
        end
    end

    -- reagents of the spells this character knows
    for _, r in ipairs(class and REAGENTS[class] or {}) do
        for _, tier in ipairs(r.tiers) do
            if anyKnown(tier[3]) then
                local have, need = b.items[tier[1]] or 0, r.min or 1
                local name = (C_Item and C_Item.GetItemNameByID and S(C_Item.GetItemNameByID(tier[1]))) or tier[2]
                add("reagent:" .. tier[1], have >= need, (have == 0 and ("No " .. name) or (name .. ": " .. have)) .. " (" .. r.use .. ")")
                break                                           -- the best known rank decides
            end
        end
    end

    -- poisons: for a rogue who has learned them or carries some
    if class == "ROGUE" then
        local carried = 0
        for _, id in ipairs(POISON_ITEMS) do carried = carried + (b.items[id] or 0) end
        if carried == 0 then
            if known(POISONS_SPELL) then add("poison", false, "No poisons in your bags") end
        elseif GetWeaponEnchantInfo then
            local mh, mhLeft, _, _, oh, ohLeft = GetWeaponEnchantInfo()
            local function hand(key, label, on, left)
                left = N(left)
                if not B(on) then add(key, false, "No poison on your " .. label)
                elseif left and left / 1000 < POISON_SOON then add(key, false, "Poison on your " .. label .. " runs out in " .. math.max(1, math.floor(left / 60000 + 0.5)) .. " min")
                else add(key, true, "Poison on your " .. label) end
            end
            hand("poison", "main hand", mh, mhLeft)
            local offID = GetInventoryItemID and N(GetInventoryItemID("player", 17))
            local offClass = offID and C_Item and C_Item.GetItemInfoInstant and N((select(6, C_Item.GetItemInfoInstant(offID))))
            if offClass == 2 then hand("poison2", "off hand", oh, ohLeft) end       -- a weapon there, not a held item
        end
    end

    ns.diagOnce("readyProbe", function()
        local parts = { "class=" .. tostring(class), "itemSpell=" .. tostring(tellsFood), "free=" .. tostring(b.free), "durability=" .. tostring(dur),
            "food=" .. b.food, "drink=" .. b.drink, "ammo=" .. b.ammo, "enchantInfo=" .. tostring(GetWeaponEnchantInfo ~= nil),
            "known=" .. tostring((IsPlayerSpell or IsSpellKnown or (C_SpellBook and C_SpellBook.IsSpellKnown)) ~= nil), "checks=" .. #list }
        return table.concat(parts, " ")
    end)
    return list
end

----------------------------------------------------------------------
-- the banner
----------------------------------------------------------------------
local frame = CreateFrame("Button", "DearLordStats_Ready", UIParent)
frame:SetFrameStrata("MEDIUM")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
frame:Hide()
state.frame = frame
local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.7)
local stripe = frame:CreateTexture(nil, "BORDER")
stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
local lines = {}
frame.lines = lines

local function line(i)
    local fs = lines[i]
    if fs then return fs end
    fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH("LEFT")
    lines[i] = fs
    return fs
end

local function place()
    if state.dragging then return end
    local db = ns.db
    local pos = db.ready
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    frame:SetScale(db.scale)
    frame:SetAlpha(db.alpha)
end

local function draw(texts, allFine)
    local db = ns.db
    local fsz, flags, pad = db.fontSize, db.outline or "OUTLINE", 7
    local w = 0
    for i, t in ipairs(texts) do
        local fs = line(i)
        local size = i == 1 and fsz or math.max(8, fsz - 1)
        if not fs:SetFont(ns.FontPath(), size, flags) then fs:SetFont(STANDARD_TEXT_FONT, size, flags) end
        fs:SetText(t)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 4 + pad, -pad - (i - 1) * (fsz + 4))
        fs:Show()
        w = math.max(w, N(fs:GetStringWidth()) or 0)
    end
    for i = #texts + 1, #lines do lines[i]:Hide() end
    frame.count = #texts
    frame:SetSize(4 + pad * 2 + w, pad * 2 + #texts * (fsz + 4) - 4)
    stripe:ClearAllPoints(); stripe:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); stripe:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); stripe:SetWidth(4)
    if allFine then stripe:SetVertexColor(0.45, 0.85, 0.45, 1) else stripe:SetVertexColor(1, 0.35, 0.35, 1) end
    place()
    frame:Show()
end

local function update()
    local db = ns.db
    if not db then return end
    local full = state.fullUntil > GetTime()
    local combat = InCombatLockdown and InCombatLockdown()
    if combat or not (full or (db.readyCheck ~= false and state.active and not state.dismissed)) then frame:Hide(); return end
    local list = ns.ReadyList()
    local missing = 0
    for _, c in ipairs(list) do if not c.ok then missing = missing + 1 end end
    state.missing = missing
    if not full and missing == 0 then
        state.active = false                                    -- everything in order: done until the next group or dungeon
        frame:Hide()
        return
    end
    local texts = { ns.WHITE .. (missing == 0 and "Ready|r" or "Before you go|r") .. ns.LABEL .. "   click to close|r" }
    for _, c in ipairs(list) do
        if not c.ok then texts[#texts + 1] = NO_ICON .. ns.RED .. c.text .. "|r" end
    end
    if full then
        for _, c in ipairs(list) do
            if c.ok then texts[#texts + 1] = OK_ICON .. ns.LABEL .. c.text .. "|r" end
        end
    end
    draw(texts, missing == 0)
end
ns.RefreshReady = update

-- /dls ready: the whole list, what is fine too, for half a minute
function ns.ReadyShow(seconds)
    state.fullUntil = GetTime() + (seconds or 30)
    update()
    return state.missing or 0
end

local function context()
    local grouped = (IsInGroup and B(IsInGroup())) or (IsInRaid and B(IsInRaid())) or false
    local inside, kind = false, nil
    if IsInInstance then local a, k = IsInInstance(); inside, kind = B(a) == true, S(k) end
    return grouped, grouped and inside and (kind == "party" or kind == "raid")
end
-- a new group, or a dungeon walked into with one, starts a check
local function trigger()
    local grouped, inside = context()
    if (grouped and not state.grouped) or (inside and not state.inside) then state.active, state.dismissed = true, false end
    if not grouped then state.active = false end
    state.grouped, state.inside = grouped, inside
    update()
end

frame:SetScript("OnClick", function()
    state.dismissed, state.fullUntil = true, 0
    update()
end)
frame:SetScript("OnDragStart", function(self)
    if not ns.db.locked then state.dragging = true; self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
    if not state.dragging then return end
    state.dragging = nil
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint(1)
    local pos = ns.db.ready
    pos.point, pos.x, pos.y = point, x, y
end)
frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("DearLord Stats: ready check")
    GameTooltip:AddLine("What you are missing for the group you joined. It goes away once everything is in order.", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("Only things this character can have are asked for: a reagent when its spell is known, poisons once learned or carried.", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("Click: close until the next group or dungeon.  Drag: move.  /dls ready: the whole list.", 0.6, 0.8, 1, true)
    GameTooltip:Show()
end)
frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

for _, ev in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
    ns.On(ev, function() trigger() end, "ready:" .. ev)
end
for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "UPDATE_INVENTORY_DURABILITY", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_INVENTORY_CHANGED" }) do
    ns.On(ev, function() if frame:IsShown() or state.active then update() end end, "ready:" .. ev)
end
ns.On("UNIT_PET", function(unit) if (unit == nil or S(unit) == "player") and (frame:IsShown() or state.active) then update() end end, "ready:pet")
ns.Every(2, function() if frame:IsShown() or (state.active and not state.dismissed) then update() end end, "ready:tick")
ns.OnLogin(function()
    if ns.db.diag then ns.db.diag.readyProbe = nil end
    state.grouped, state.inside = context()                     -- a reload inside a group is not a new group
end, "ready:login")
