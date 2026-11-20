-- DearLord Stats : the hawk key
-- Summon Hawk drops a hawk on your target, but the hawk stays on it only when a pet attack order
-- follows. An order sent in the same instant as the cast comes too early: the hawk is not there yet,
-- and it flies back to you. A macro cannot wait, and an addon may not order a pet attack at all.
-- So the key does it. While this is on, every key bound to an action slot that holds Summon Hawk
-- is pointed at a secure button of ours: it casts on the press and runs /petattack on the release,
-- the moment later the hawk needs.
-- The pointing is an override binding: your own key bindings are not changed, and it is gone with
-- the addon. Overrides and the button's attributes can only be set out of combat.
local ADDON, ns = ...
local N, S, B = ns.N, ns.S, ns.B

local HAWK_IDS = { 1293525, 1293526 }       -- two of its ranks; every rank carries the same name
local BUTTON = "DearLordStats_HawkButton"

local state = { keys = {}, dirty = true, presses = 0, releases = 0 }
ns.hawk = state

local function hawkName()
    if C_Spell and C_Spell.GetSpellName then
        for _, id in ipairs(HAWK_IDS) do
            local n = S(C_Spell.GetSpellName(id))
            if n then return n end
        end
    end
    return "Summon Hawk"
end

local okBtn, btn = pcall(CreateFrame, "Button", BUTTON, UIParent, "SecureActionButtonTemplate")
if not okBtn or not btn or not btn.SetAttribute then btn = nil; state.noSecure = true end
if btn then
    state.button = btn
    btn:RegisterForClicks("AnyDown", "AnyUp")
    -- The game's secure button, with pressAndHoldAction set, acts twice: on the press it runs "type"
    -- under the button name given in "downbutton", on the release it runs "typerelease"
    -- (SecureTemplates.lua, SecureActionButton_OnClick). Both are macros here; the press finds its
    -- text under its own button name, the release falls back to the plain one.
    btn:SetAttribute("pressAndHoldAction", true)
    btn:SetAttribute("downbutton", "press")
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("typerelease", "macro")
    btn:SetAttribute("macrotext", "/petattack")
    -- did both halves arrive? counted for /dls check
    btn:HookScript("PostClick", function(_, _, down)
        if down then state.presses = state.presses + 1 else state.releases = state.releases + 1 end
        local d = ns.db and ns.db.diag
        if d then d.hawkClicks = state.presses .. "/" .. state.releases end
    end)
end

local function isHunter()
    if not UnitClass then return false end
    local _, class = UnitClass("player")
    return S(class) == "HUNTER"
end

-- the keys that reach Summon Hawk on the bars, as a set
local function wantedKeys(name)
    local out = {}
    if not btn or not ns.db or ns.db.hawkAttack == false or not isHunter() then return out end
    if not (ns.EachBoundSlot and GetBindingKey and C_Spell and C_Spell.GetSpellName) then return out end
    ns.EachBoundSlot(function(slot, command)
        local id = ns.SpellOfSlot(slot)
        if not id or S(C_Spell.GetSpellName(id)) ~= name then return end
        local found = { GetBindingKey(command) }
        for i = 1, #found do
            local key = S(found[i])
            if key and key ~= "" then out[key] = true end
        end
    end)
    return out
end

local function sameSet(a, b)
    for k in pairs(a) do if not b[k] then return false end end
    for k in pairs(b) do if not a[k] then return false end end
    return true
end

local function apply()
    if not btn or not ns.db then return end
    if InCombatLockdown and InCombatLockdown() then return end         -- stays dirty until the fight ends
    state.dirty, state.setting = false, ns.db.hawkAttack
    if not (SetOverrideBindingClick and ClearOverrideBindings) then state.noBinding = true; return end
    local name = hawkName()
    local keys = wantedKeys(name)
    if state.name ~= name then
        btn:SetAttribute("*macrotext-press", "/cast " .. name)          -- the star: with any modifier held
        state.name = name
    end
    if not sameSet(keys, state.keys) then
        ClearOverrideBindings(btn)
        for key in pairs(keys) do SetOverrideBindingClick(btn, false, key, BUTTON, "LeftButton") end
        state.keys = keys
    end
    local list = {}
    for key in pairs(keys) do list[#list + 1] = key end
    table.sort(list)
    if ns.db.diag then ns.db.diag.hawkKeys = table.concat(list, ", ") end
end
ns.RefreshHawk = function() state.dirty = true; apply() end

for _, ev in ipairs({ "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "SPELLS_CHANGED",
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UPDATE_MACROS" }) do
    ns.On(ev, function() state.dirty = true end, "hawk:" .. ev)
end
ns.Every(0.5, function()
    if state.dirty or (ns.db and state.setting ~= ns.db.hawkAttack) then apply() end
end, "hawk:tick")
ns.OnLogin(function()
    local d = ns.db.diag
    if d then d.hawkKeys, d.hawkClicks = nil, nil end
    state.dirty = true
end, "hawk:login")
