-- DearLord Stats 2.0 : Spells
-- "Forgotten spells": things you have learned that are not on any action bar, and things
-- on your bars you have not pressed this session. Handy when hopping between classes.
local ADDON, ns = ...
local N, S, T, B = ns.N, ns.S, ns.T, ns.B

local SKIP_PREFIX = { "Track ", "Find ", "Sense " }          -- tracking toggles live on the minimap
local SPELL_ITEM = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1
local PLAYER_BANK = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0

local known, onBars = {}, {}        -- name -> true
local baseline                      -- names that were already missing at login (no reminder for those)
ns.spells = { missing = {}, unused = {} }

local function skipName(name)
    for _, p in ipairs(SKIP_PREFIX) do if name:sub(1, #p) == p then return true end end
    return false
end

local function scanSpellbook()
    local out = {}
    local SB = C_SpellBook
    if not (SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo) then return out end
    local lines = N(SB.GetNumSpellBookSkillLines()) or 0
    for line = 2, lines do                                   -- line 1 is "General": racials, professions, Attack
        local info = T(SB.GetSpellBookSkillLineInfo(line))
        if info and not B(info.shouldHide) and not B(info.isGuild) then
            local offset, count = N(info.itemIndexOffset) or 0, N(info.numSpellBookItems) or 0
            for i = offset + 1, offset + count do
                local item = T(SB.GetSpellBookItemInfo(i, PLAYER_BANK))
                local name = item and S(item.name)
                if name and N(item.itemType) == SPELL_ITEM and not B(item.isPassive) and not B(item.isOffSpec) and not skipName(name) then
                    out[name] = true
                end
            end
        end
    end
    return out
end

local function scanBars()
    local out, macroText = {}, {}
    if not GetActionInfo then return out, "" end
    for slot = 1, 180 do
        local kind, id = GetActionInfo(slot)
        kind = S(kind)
        if kind == "spell" then
            local name = ns.spellName(id)
            if name then out[name] = true end
        elseif kind == "macro" and GetActionText and GetMacroBody then
            local label = S(GetActionText(slot))
            local body = label and S(GetMacroBody(label))
            if body then macroText[#macroText + 1] = body:lower() end
        end
    end
    return out, table.concat(macroText, "\n")
end

local function recompute(announce)
    local char, session = ns.char, ns.session
    if not char or not session then return end
    known = scanSpellbook()
    local macros
    onBars, macros = scanBars()
    local missing, unused = {}, {}
    for name in pairs(known) do
        if not char.ignoreSpells[name] then
            local placed = onBars[name] or (macros ~= "" and macros:find(name:lower(), 1, true) ~= nil)
            if not placed then missing[#missing + 1] = name
            elseif not session.casts[name] then unused[#unused + 1] = name end
        end
    end
    table.sort(missing); table.sort(unused)
    ns.spells.missing, ns.spells.unused = missing, unused
    if not baseline then
        baseline = {}
        for _, name in ipairs(missing) do baseline[name] = true end
    elseif announce then
        for _, name in ipairs(missing) do
            if not baseline[name] then
                -- only tick it off once the reminder was really shown; otherwise try again later
                if ns.Nudge("spell:" .. name, string.format("%sNew:|r %s%s|r %sis not on your bars|r", ns.BLUE, ns.WHITE, name, ns.LABEL), "abilities") then
                    baseline[name] = true
                end
            end
        end
    end
    if ns.PanelDirty then ns.PanelDirty() end
end
ns.RecomputeSpells = recompute

function ns.IgnoreSpell(name)
    if ns.char then ns.char.ignoreSpells[name] = true; recompute(false) end
end

-- "unused" only means something after you have actually played for a while
function ns.UnusedIsMeaningful()
    local s = ns.session
    return s and (s.active or 0) >= 900 and s.combat.fights >= 8
end

local queued = false
local function schedule()
    if queued then return end
    queued = true
    ns.After(4, function() queued = false; recompute(true) end, "spells:recompute")
end
for _, e in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS" }) do
    ns.On(e, schedule, "spells:" .. e)
end
ns.Every(90, function() if baseline and not (InCombatLockdown and InCombatLockdown()) then recompute(true) end end, "spells:sweep")
ns.OnLogin(function() baseline = nil; ns.After(6, function() recompute(false) end, "spells:login") end, "spells:login")
