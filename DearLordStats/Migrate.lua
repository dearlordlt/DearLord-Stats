-- DearLord Stats : one-time data repairs and short-lived probes
-- Reserved for small, versioned fix-ups of saved data after a breaking change, and for probes
-- that record how this client answers an API question. The file stays in the load list so that
-- adding something here never needs a full client restart (new .toc files do).
local ADDON, ns = ...
local N, S, T, B = ns.N, ns.S, ns.T, ns.B

----------------------------------------------------------------------
-- probe: hunter pet knowledge. What does the client hand us for a beast's tooltip (Beast Lore
-- lines), its creature family, and the pet's own spellbook? Answers land in DearLordStatsDB.diag.pets
----------------------------------------------------------------------
local function has(fn) return type(fn) == "function" and "yes" or "no" end
local function petDiag()
    local d = ns.db and ns.db.diag
    if not d then return nil end
    d.pets = d.pets or { beasts = {}, book = {} }
    return d.pets
end

ns.On("PLAYER_LOGIN", function()
    local p = petDiag(); if not p then return end
    p.api = {
        tooltipInfoGetUnit = has(C_TooltipInfo and C_TooltipInfo.GetUnit),
        tooltipProcessor = has(TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall),
        tooltipDataTypeUnit = tostring(Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit),
        onTooltipSetUnit = tostring(GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit")),
        gameTooltipGetUnit = has(GameTooltip and GameTooltip.GetUnit),
        unitCreatureFamily = has(UnitCreatureFamily), unitCreatureType = has(UnitCreatureType),
        hasPetSpells = has(HasPetSpells), sbHasPetSpells = has(C_SpellBook and C_SpellBook.HasPetSpells),
        petBank = tostring(Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet),
        petHappiness = has(C_PetInfo and C_PetInfo.GetPetHappiness), getPetHappiness = has(GetPetHappiness),
        getPetActionInfo = has(GetPetActionInfo), petSlots = tostring(NUM_PET_ACTION_SLOTS),
        isSpellKnown = has(IsSpellKnown), sbIsSpellKnown = has(C_SpellBook and C_SpellBook.IsSpellKnown),
        beastLoreKnown = IsSpellKnown and tostring(IsSpellKnown(1462)) or "?",
        beastLoreName = tostring(ns.spellName(1462)),
        unitAuras = has(C_UnitAuras and C_UnitAuras.GetAuraDataByIndex),
    }
end, "probe:pets:api")

local function tooltipLines(unit)
    local out = {}
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local data = T(C_TooltipInfo.GetUnit(unit))
        local lines = data and T(data.lines)
        if lines then
            for i = 1, math.min(#lines, 14) do
                local l = T(lines[i])
                local left = l and (S(l.leftText) or "?")
                local right = l and S(l.rightText)
                out[#out + 1] = "I:" .. left .. (right and (" | " .. right) or "")
            end
        end
    end
    if GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() then
        for i = 1, 14 do
            local fs = _G["GameTooltipTextLeft" .. i]
            local txt = fs and fs.GetText and S(fs:GetText())
            if txt and txt ~= "" then out[#out + 1] = "G:" .. txt end
        end
    end
    return out
end

ns.On("UPDATE_MOUSEOVER_UNIT", function()
    local p = petDiag(); if not p then return end
    if not (UnitExists and UnitExists("mouseover")) or (UnitIsPlayer and UnitIsPlayer("mouseover")) then return end
    local ctype = UnitCreatureType and S(UnitCreatureType("mouseover"))
    if ctype and ctype ~= "Beast" then return end
    local name = S(UnitName("mouseover")) or "?"
    local lines = tooltipLines("mouseover")
    local prev = p.beasts[name]
    local count = 0; for _ in pairs(p.beasts) do count = count + 1 end
    if (not prev and count < 12) or (prev and #lines > (prev.nLines or 0)) then
        p.beasts[name] = {
            family = UnitCreatureFamily and tostring(S(UnitCreatureFamily("mouseover"))) or "?",
            ctype = tostring(ctype), level = tostring(N(UnitLevel("mouseover"))),
            class = UnitClassification and tostring(S(UnitClassification("mouseover"))) or "?",
            nLines = #lines, lines = lines, t = time(),
        }
    end
end, "probe:pets:mouseover")

local function scanPetBook()
    local p = petDiag(); if not p then return end
    if not (UnitExists and UnitExists("pet")) then return end
    local book = { name = tostring(S(UnitName("pet"))), level = tostring(N(UnitLevel("pet"))),
        family = UnitCreatureFamily and tostring(S(UnitCreatureFamily("pet"))) or "?", spells = {}, actions = {}, t = time() }
    local PET = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
    local num, token
    if C_SpellBook and C_SpellBook.HasPetSpells then num, token = C_SpellBook.HasPetSpells()
    elseif HasPetSpells then num, token = HasPetSpells() end
    book.numPetSpells, book.token = tostring(N(num)), tostring(S(token))
    if PET ~= nil and C_SpellBook and C_SpellBook.GetSpellBookItemInfo and N(num) then
        for i = 1, math.min(N(num), 40) do
            local item = T(C_SpellBook.GetSpellBookItemInfo(i, PET))
            if item then
                book.spells[#book.spells + 1] = string.format("%s#%s/%s%s%s", tostring(S(item.name)), tostring(N(item.spellID)),
                    tostring(S(item.subName)), B(item.isPassive) and " passive" or "", B(item.isOffSpec) and " offspec" or "")
            end
        end
    end
    if GetPetActionInfo then
        for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
            local nm, tex, isToken, isActive, autoOn, autoAllowed = GetPetActionInfo(i)
            nm = S(nm)
            if nm then book.actions[#book.actions + 1] = string.format("%s%s%s", nm, B(autoOn) and " auto" or "", B(autoAllowed) and " autoOK" or "") end
        end
    end
    if C_PetInfo and C_PetInfo.GetPetHappiness then
        local h, dmg, loy = C_PetInfo.GetPetHappiness()
        book.happiness = tostring(N(h)) .. "/" .. tostring(N(dmg)) .. "/" .. tostring(N(loy))
    elseif GetPetHappiness then
        local h, dmg, loy = GetPetHappiness()
        book.happiness = tostring(N(h)) .. "/" .. tostring(N(dmg)) .. "/" .. tostring(N(loy))
    end
    p.book[book.name] = book
end
ns.On("UNIT_PET", function(unit) if unit == "player" then ns.After(2, scanPetBook, "probe:pets:book") end end, "probe:pets:pet")
ns.On("PET_BAR_UPDATE", function() ns.After(1, scanPetBook, "probe:pets:book") end, "probe:pets:bar")
ns.On("PLAYER_LOGIN", function() ns.After(5, scanPetBook, "probe:pets:book") end, "probe:pets:login")
