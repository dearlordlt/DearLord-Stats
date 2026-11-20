-- DearLord Stats : key bindings on the game's cooldown manager
-- The built-in cooldown manager shows the spells but not the key each one sits on. This looks up
-- the action bar slot holding each spell (or a macro that casts it) and writes that slot's key
-- in the corner of the icon, the way action buttons do.
-- Nothing of the game's own is changed: each label is a small frame of ours laid over an icon.
local ADDON, ns = ...
local N, S, B, T = ns.N, ns.S, ns.B, ns.T

local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer" }
-- first action slot and binding name of each extra bar, in the order their keys are preferred
local BARS = {
    { 61, "MULTIACTIONBAR1BUTTON" }, { 49, "MULTIACTIONBAR2BUTTON" }, { 25, "MULTIACTIONBAR3BUTTON" }, { 37, "MULTIACTIONBAR4BUTTON" },
    { 145, "MULTIACTIONBAR5BUTTON" }, { 157, "MULTIACTIONBAR6BUTTON" }, { 169, "MULTIACTIONBAR7BUTTON" },
}
local MODS = { { "ALT-", "a" }, { "CTRL-", "c" }, { "SHIFT-", "s" }, { "META-", "m" } }
local NAMES = {
    MOUSEWHEELUP = "WU", MOUSEWHEELDOWN = "WD", SPACE = "Sp", BACKSPACE = "BS", DELETE = "Del", INSERT = "Ins", PAGEUP = "PU",
    PAGEDOWN = "PD", CAPSLOCK = "Caps", ESCAPE = "Esc", ENTER = "Ent", NUMPADPLUS = "N+", NUMPADMINUS = "N-", NUMPADMULTIPLY = "N*",
    NUMPADDIVIDE = "N/", NUMPADDECIMAL = "N.", MIDDLEMOUSE = "M3",
}

local keys = { byID = {}, byName = {}, dirty = true, built = false }
ns.keys = keys
local labels = setmetatable({}, { __mode = "k" })       -- cooldown manager icon -> our label
keys.labels = labels

-- "CTRL-5" -> "c-5", "BUTTON4" -> "M4", "SHIFT-MOUSEWHEELUP" -> "s-WU"
local function short(key)
    key = key:upper()
    local mods = ""
    for _, m in ipairs(MODS) do
        local at = key:find(m[1], 1, true)
        if at then mods = mods .. m[2]; key = key:sub(1, at - 1) .. key:sub(at + #m[1]) end
    end
    key = NAMES[key] or key:gsub("^BUTTON(%d+)$", "M%1"):gsub("^NUMPAD(%d)$", "N%1")
    if #key > 4 then key = key:sub(1, 1) .. key:sub(2, 4):lower() end
    return mods ~= "" and (mods .. "-" .. key) or key
end
ns.ShortKey = short

local function spellName(id)
    return id and C_Spell and C_Spell.GetSpellName and S(C_Spell.GetSpellName(id)) or nil
end

-- the spell an action slot casts, straight or through a macro
local function spellOfSlot(slot)
    if not GetActionInfo then return nil end
    local ok, kind, id, sub = pcall(GetActionInfo, slot)
    if not ok then return nil end
    kind, id = S(kind), N(id)
    if not kind or not id then return nil end
    if kind == "spell" then return id end
    if kind == "macro" then
        if S(sub) == "spell" then return id end
        if GetMacroSpell then
            local ok2, sid = pcall(GetMacroSpell, id)
            return ok2 and N(sid) or nil
        end
    end
end

local function note(slot, command)
    local id = spellOfSlot(slot)
    if not id then return end
    local key = GetBindingKey and S((GetBindingKey(command)))
    if not key then return end
    key = short(key)
    if not keys.byID[id] then keys.byID[id] = key end
    local name = spellName(id)               -- ranks share a name: the manager may name another rank
    if name and not keys.byName[name] then keys.byName[name] = key end
end

local function build()
    keys.byID, keys.byName = {}, {}
    -- the main bar shows one page at a time: a stance bar while in a stance, else the page picked
    local page = (GetActionBarPage and N(GetActionBarPage())) or 1
    local bonus = (GetBonusBarOffset and N(GetBonusBarOffset())) or 0
    if page == 1 and bonus > 0 then page = 6 + bonus end
    for i = 1, 12 do note((page - 1) * 12 + i, "ACTIONBUTTON" .. i) end
    for _, bar in ipairs(BARS) do
        for i = 1, 12 do note(bar[1] + i - 1, bar[2] .. i) end
    end
    keys.dirty, keys.built = false, true
end

local function itemsOf(viewer)
    local list
    if viewer.GetItemFrames then
        local ok, t = pcall(viewer.GetItemFrames, viewer)
        if ok and type(t) == "table" then list = t end
    end
    if not list and viewer.GetChildren then list = { viewer:GetChildren() } end
    return list or {}
end

-- every spell id the icon may stand for, most specific first
local function candidates(item)
    local out = {}
    local function add(v) v = N(v); if v and v > 0 then out[#out + 1] = v end end
    if item.GetSpellID then local ok, v = pcall(item.GetSpellID, item); if ok then add(v) end end
    local cid
    if item.GetCooldownID then local ok, v = pcall(item.GetCooldownID, item); if ok then cid = N(v) end end
    cid = cid or N(item.cooldownID)
    if cid and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cid)
        info = ok and T(info) or nil
        if info then
            add(info.overrideSpellID); add(info.spellID)
            local linked = T(info.linkedSpellIDs)
            if linked then for _, v in ipairs(linked) do add(v) end end
        end
    end
    return out, cid
end

local function keyFor(ids)
    for _, id in ipairs(ids) do
        if keys.byID[id] then return keys.byID[id] end
    end
    for _, id in ipairs(ids) do
        local name = spellName(id)
        if name and keys.byName[name] then return keys.byName[name] end
    end
end

local function label(item)
    local l = labels[item]
    if l then return l end
    local holder = CreateFrame("Frame", nil, item)
    holder:SetAllPoints(item)
    holder:SetFrameLevel((N(item:GetFrameLevel()) or 1) + 10)       -- above the cooldown sweep
    local fs = holder:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH("RIGHT")
    fs:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -1, -2)
    fs:SetTextColor(0.95, 0.95, 0.95)
    l = { holder = holder, fs = fs }
    labels[item] = l
    return l
end

local function refresh()
    local db = ns.db
    if not db then return end
    local combat = InCombatLockdown and InCombatLockdown()
    if keys.dirty and (not combat or not keys.built) then build() end
    local on = db.showKeys ~= false
    local seen = 0
    for _, viewerName in ipairs(VIEWERS) do
        local viewer = _G[viewerName]
        if viewer then
            for _, item in ipairs(itemsOf(viewer)) do
                if type(item) == "table" and (item.GetCooldownID or item.cooldownID ~= nil) then
                    seen = seen + 1
                    local ids, cid = candidates(item)
                    local l = labels[item]
                    if not on then
                        if l then l.holder:Hide() end
                    elseif #ids > 0 then
                        local key = keyFor(ids)
                        if key then
                            l = l or label(item)
                            local w = N(item:GetWidth()) or 36
                            local size = math.max(9, math.min(15, math.floor(w * 0.3 + 0.5)))
                            if l.key ~= key or l.size ~= size then
                                l.fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
                                l.fs:SetText(key)
                                l.key, l.size = key, size
                            end
                            l.holder:Show()
                        elseif l then
                            l.holder:Hide(); l.key = nil
                        end
                    end                                     -- no ids (hidden in a fight): leave the label as it is
                    if cid and not keys.probed and db.diag then
                        keys.probe = keys.probe or {}
                        if #keys.probe < 6 then
                            keys.probe[#keys.probe + 1] = viewerName:sub(1, 3) .. ":" .. cid .. "=" .. table.concat(ids, "/") .. ">" .. tostring((keyFor(ids)))
                        end
                    end
                end
            end
        end
    end
    -- what the client gave us, once per session, for checking from the saved variables
    if not keys.probed and db.diag and seen > 0 and keys.built then
        keys.probed = true
        local n = 0
        for _ in pairs(keys.byID) do n = n + 1 end
        db.diag.keysProbe = "icons=" .. seen .. " boundSpells=" .. n .. " " .. table.concat(keys.probe or {}, " ")
    end
end
ns.RefreshKeys = refresh

for _, ev in ipairs({ "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "SPELLS_CHANGED",
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UPDATE_MACROS" }) do
    ns.On(ev, function() keys.dirty = true end, "keys:" .. ev)
end
ns.Every(0.5, refresh, "keys:tick")
ns.OnLogin(function()
    if ns.db.diag then ns.db.diag.keysProbe = nil end
    keys.dirty, keys.probed, keys.probe = true, false, nil
end, "keys:login")
