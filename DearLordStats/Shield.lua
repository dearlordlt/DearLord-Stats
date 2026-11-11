-- DearLord Stats : shield bar
-- A small bar of its own for the absorb shield on you: Power Word: Shield, Ice Barrier, Mana Shield, a
-- ward, a Voidwalker's Sacrifice, whoever cast it. It shows how much is left, of how much, and for how
-- long. It appears with the shield and goes with it; it is moved in the game's Edit Mode, or during
-- /dls shield.
--
-- Where the numbers come from, best first:
--   * amount   UnitGetTotalAbsorbs("player") as a plain number: everything works (the bar empties as the
--              shield takes damage, with a trail behind each hit, and a percentage is possible)
--   * hidden   the same value, but hidden from addons (in combat on this client most numbers are): the
--              bar and the number still follow it, since a status bar and a text take a hidden value, and
--              the full size comes from what was learned while it was readable, or from the spell's rank
--   * timer    no amount at all from the client: the bar shows the time left instead
-- Which one the client gave is noted for the client checks page.
local ADDON, ns = ...
local N, S, T, B = ns.N, ns.S, ns.T, ns.B

local TEX = "Interface\\Buttons\\WHITE8X8"
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local FALLBACK_ICON = "Interface\\Icons\\Spell_Holy_PowerWordShield"
local INTERP = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

ns.SHIELD_COLORS = { { key = "spell", name = "By shield" }, { key = "gold", name = "Gold" }, { key = "blue", name = "Blue" },
    { key = "green", name = "Green" }, { key = "purple", name = "Purple" }, { key = "white", name = "White" } }
ns.SHIELD_TEXTS = { { key = "both", name = "Left and full" }, { key = "amount", name = "Left" }, { key = "percent", name = "Percent" }, { key = "none", name = "Nothing" } }
local STYLE = { gold = { 1, 0.82, 0.35 }, blue = { 0.40, 0.75, 1 }, green = { 0.45, 0.90, 0.55 }, purple = { 0.72, 0.50, 1 }, white = { 0.92, 0.95, 1 } }
local LOW_RGB = { 1, 0.30, 0.25 }

-- The shields of the classic classes: spell id of each rank and what it absorbs untalented. The amounts are
-- only a starting point for the bar's full size when the real one cannot be read; what is read is kept.
local FAMILIES = {
    { key = "pws", color = { 1, 0.86, 0.45 }, duration = 30,
        ids = { [17] = 44, [592] = 88, [600] = 158, [3747] = 234, [6065] = 301, [6066] = 381, [10898] = 484, [10899] = 605, [10900] = 763, [10901] = 942 } },
    { key = "barrier", color = { 0.45, 0.80, 1 }, duration = 60, ids = { [11426] = 438, [13031] = 549, [13032] = 678, [13033] = 818 } },
    { key = "mana", color = { 0.62, 0.50, 1 }, duration = 60, ids = { [1463] = 120, [8494] = 210, [8495] = 300, [10191] = 390, [10192] = 480, [10193] = 570 } },
    { key = "fireward", color = { 1, 0.55, 0.20 }, duration = 30, ids = { [543] = 165, [8457] = 290, [8458] = 470, [10223] = 675, [10225] = 920 } },
    { key = "frostward", color = { 0.55, 0.85, 1 }, duration = 30, ids = { [6143] = 165, [8461] = 290, [8462] = 470, [10177] = 675, [28609] = 920 } },
    { key = "shadowward", color = { 0.70, 0.45, 0.95 }, duration = 30, ids = { [6229] = 290, [11739] = 470, [11740] = 675, [28610] = 920 } },
    { key = "sacrifice", color = { 0.75, 0.40, 0.95 }, duration = 30,
        ids = { [7812] = 305, [19438] = 510, [19440] = 770, [19441] = 1095, [19442] = 1470, [19443] = 1905 } },
}
local BY_ID, BY_NAME = {}, {}
for _, fam in ipairs(FAMILIES) do for id in pairs(fam.ids) do BY_ID[id] = fam end end

local state = { present = false, disp = 0, ghostV = 0, ghostHold = 0, flash = 0, demoUntil = 0, edit = false }
ns.shield = state

local function diag()
    local d = ns.db and ns.db.diag
    if not d then return {} end
    d.shield = type(d.shield) == "table" and d.shield or {}
    return d.shield
end
local function learned()
    local db = ns.db
    db.shieldLearned = type(db.shieldLearned) == "table" and db.shieldLearned or {}
    return db.shieldLearned
end

----------------------------------------------------------------------
-- the frame
----------------------------------------------------------------------
local f = CreateFrame("Frame", "DearLordStats_Shield", UIParent)
f:SetFrameStrata("MEDIUM")
f:SetMovable(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:EnableMouse(false)
f:Hide()
state.frame = f

local function tex(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(TEX)
    t:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
    return t
end
local function statusBar(parent, level)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetStatusBarTexture(TEX)
    b:SetMinMaxValues(0, 1)
    b:SetValue(0)
    b:SetFrameLevel(level)
    return b
end

-- a soft glow outside the border: four edges, pulsing while a shield is up
f.glow = {}
for i = 1, 4 do
    local g = tex(f, "BACKGROUND")
    if g.SetBlendMode then g:SetBlendMode("ADD") end
    f.glow[i] = g
end
f.edge = tex(f, "BACKGROUND", 0, 0, 0, 0.85)                  -- the dark border
f.edge:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
f.edge:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)

f.iconBox = CreateFrame("Frame", nil, f)
f.icon = f.iconBox:CreateTexture(nil, "ARTWORK")
f.icon:SetAllPoints()
if f.icon.SetTexCoord then f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

f.body = CreateFrame("Frame", nil, f)                        -- everything that fills: clipped to the bar's shape
if f.body.SetClipsChildren then f.body:SetClipsChildren(true) end
f.back = tex(f.body, "BACKGROUND", 0.05, 0.06, 0.09, 0.80)
f.back:SetAllPoints()
local base = (f.body.GetFrameLevel and f.body:GetFrameLevel()) or 2
f.ghost = statusBar(f.body, base + 1)                        -- what the last hits took, draining behind the bar
f.ghost:SetAllPoints()
f.ghost:SetStatusBarColor(1, 1, 1)
f.ghost:SetAlpha(0.55)
f.bar = statusBar(f.body, base + 2)
f.bar:SetAllPoints()
f.over = CreateFrame("Frame", nil, f.body)                   -- gloss, shine, flash, spark and texts above the fill
f.over:SetAllPoints()
f.over:SetFrameLevel(base + 3)
f.gloss = tex(f.over, "ARTWORK")
f.gloss:SetPoint("TOPLEFT"); f.gloss:SetPoint("TOPRIGHT")
if f.gloss.SetGradient and CreateColor then
    pcall(f.gloss.SetGradient, f.gloss, "VERTICAL", CreateColor(1, 1, 1, 0.02), CreateColor(1, 1, 1, 0.22))
else f.gloss:SetVertexColor(1, 1, 1, 0.10) end
f.shade = tex(f.over, "ARTWORK")
f.shade:SetPoint("BOTTOMLEFT"); f.shade:SetPoint("BOTTOMRIGHT")
if f.shade.SetGradient and CreateColor then
    pcall(f.shade.SetGradient, f.shade, "VERTICAL", CreateColor(0, 0, 0, 0.30), CreateColor(0, 0, 0, 0))
else f.shade:SetVertexColor(0, 0, 0, 0.12) end
f.shine = tex(f.over, "OVERLAY", 1, 1, 1, 0.55)              -- a bright band that runs across when a shield lands
if f.shine.SetBlendMode then f.shine:SetBlendMode("ADD") end
if f.shine.SetGradient and CreateColor then pcall(f.shine.SetGradient, f.shine, "HORIZONTAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.75)) end
f.shine:Hide()
f.flash = tex(f.over, "OVERLAY", 1, 1, 1, 1)                 -- a blink on every hit taken by the shield
if f.flash.SetBlendMode then f.flash:SetBlendMode("ADD") end
f.flash:SetAllPoints()
f.flash:SetAlpha(0)
f.spark = f.over:CreateTexture(nil, "OVERLAY")
f.spark:SetTexture(SPARK)
if f.spark.SetBlendMode then f.spark:SetBlendMode("ADD") end
f.spark:Hide()
f.timer = statusBar(f.body, base + 4)                        -- a thin line along the bottom: the time left
f.timer:SetStatusBarColor(1, 1, 1)
f.timer:SetAlpha(0.85)
f.textBox = CreateFrame("Frame", nil, f.body)
f.textBox:SetAllPoints()
f.textBox:SetFrameLevel(base + 5)
local function text(justify)
    local fs = f.textBox:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH(justify)
    return fs
end
f.amount = text("LEFT")
f.full = text("LEFT")
f.time = text("RIGHT")

-- shown while the bar can be moved (Edit Mode, or the preview)
f.mover = CreateFrame("Frame", nil, f)
f.mover:SetAllPoints()
f.mover:SetFrameLevel(base + 8)
f.mover.tint = tex(f.mover, "OVERLAY", 0.15, 0.55, 1, 0.22)
f.mover.tint:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
f.mover.tint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
f.mover.label = f.mover:CreateFontString(nil, "OVERLAY")
f.mover.label:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
f.mover.label:SetPoint("BOTTOM", f, "TOP", 0, 5)
f.mover.label:SetTextColor(0.55, 0.80, 1)
f.mover.label:SetText("Shield bar  ·  drag to move")
f.mover:Hide()

local function place(dx)
    local pos = ns.db.shieldPos
    f:ClearAllPoints()
    f:SetPoint(pos.point, UIParent, pos.point, pos.x + (dx or 0), pos.y)
end

local function layout()
    local db = ns.db
    local w, h = db.shieldWidth or 220, db.shieldHeight or 22
    f:SetSize(w, h)
    place()
    local icon = db.shieldIcon ~= false
    f.iconBox:SetShown(icon)
    f.iconBox:ClearAllPoints()
    f.iconBox:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.iconBox:SetSize(h, h)
    f.body:ClearAllPoints()
    f.body:SetPoint("TOPLEFT", f, "TOPLEFT", icon and (h + 2) or 0, 0)
    f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    state.bodyW = w - (icon and (h + 2) or 0)
    f.gloss:SetHeight(h * 0.5)
    f.shade:SetHeight(h * 0.45)
    f.shine:SetSize(math.max(24, state.bodyW * 0.28), h)
    f.spark:SetSize(math.max(10, h * 0.9), h * 2.1)
    local line = math.max(2, math.floor(h * 0.12 + 0.5))
    f.timer:ClearAllPoints()
    f.timer:SetPoint("BOTTOMLEFT", f.body, "BOTTOMLEFT", 0, 0)
    f.timer:SetPoint("BOTTOMRIGHT", f.body, "BOTTOMRIGHT", 0, 0)
    f.timer:SetHeight(line)
    f.timer:SetShown(db.shieldTimer ~= false)
    local size, flags = math.max(8, math.min(22, math.floor(h * 0.58 + 0.5))), db.outline or "OUTLINE"
    for _, fs in ipairs({ f.amount, f.full, f.time }) do
        local s = fs == f.full and math.max(7, size - 3) or size
        if not fs:SetFont(ns.FontPath(), s, flags) then fs:SetFont(STANDARD_TEXT_FONT, s, flags) end
    end
    f.amount:ClearAllPoints(); f.amount:SetPoint("LEFT", f.body, "LEFT", 6, 1)
    f.full:ClearAllPoints(); f.full:SetPoint("BOTTOMLEFT", f.amount, "BOTTOMRIGHT", 3, 0)
    f.time:ClearAllPoints(); f.time:SetPoint("RIGHT", f.body, "RIGHT", -6, 1)
    f.full:SetTextColor(0.80, 0.82, 0.88)
    -- the glow: 2 px outside the border on each side
    local g = f.glow
    g[1]:ClearAllPoints(); g[1]:SetPoint("BOTTOMLEFT", f, "TOPLEFT", -3, 1); g[1]:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 3, 1); g[1]:SetHeight(2)
    g[2]:ClearAllPoints(); g[2]:SetPoint("TOPLEFT", f, "BOTTOMLEFT", -3, -1); g[2]:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 3, -1); g[2]:SetHeight(2)
    g[3]:ClearAllPoints(); g[3]:SetPoint("TOPRIGHT", f, "TOPLEFT", -1, 1); g[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", -1, -1); g[3]:SetWidth(2)
    g[4]:ClearAllPoints(); g[4]:SetPoint("TOPLEFT", f, "TOPRIGHT", 1, 1); g[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 1, -1); g[4]:SetWidth(2)
    -- the spark rides the edge of the fill; the client moves it, so it follows a hidden value too
    local fill = f.bar.GetStatusBarTexture and f.bar:GetStatusBarTexture()
    f.spark:ClearAllPoints()
    if fill then f.spark:SetPoint("CENTER", fill, "RIGHT", 0, 0); state.sparkOk = true else state.sparkOk = false end
end

----------------------------------------------------------------------
-- reading the game
----------------------------------------------------------------------
local function readAmount()
    if type(UnitGetTotalAbsorbs) ~= "function" then return nil, "none" end
    local ok, v = pcall(UnitGetTotalAbsorbs, "player")
    if not ok or v == nil then return nil, "none" end
    local n = N(v)
    if n then return n, "plain" end
    return v, "secret"                                       -- there, but hidden: only widgets may take it
end

local function auraInfo(a, fam, id, how)
    a = a or {}
    local points = T(a.points)
    return { fam = fam, id = id or N(a.spellId), name = S(a.name), icon = N(a.icon) or S(a.icon), expires = N(a.expirationTime),
        duration = N(a.duration), nominal = points and N(points[1]) or nil, instance = N(a.auraInstanceID), how = how }
end
-- the shield among your buffs: by spell id or name when buffs can be read, else by asking for each known
-- shield spell in turn (that answers even when the details are hidden)
local function findAura()
    local UA = C_UnitAuras
    if not UA then return nil, "noapi" end
    local hidden, seen = false, 0
    if UA.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, raw = pcall(UA.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or raw == nil then break end
            seen = seen + 1
            local a = T(raw)
            local id, name = a and N(a.spellId), a and S(a.name)
            if not id and not name then hidden = true
            else
                local fam = (id and BY_ID[id]) or (name and BY_NAME[name])
                if fam then return auraInfo(a, fam, id, "list"), "list" end
            end
        end
    end
    if (hidden or not UA.GetAuraDataByIndex) and UA.GetPlayerAuraBySpellID then
        for id, fam in pairs(BY_ID) do
            local ok, raw = pcall(UA.GetPlayerAuraBySpellID, id)
            if ok and raw ~= nil then return auraInfo(T(raw), fam, id, "byid"), "byid" end
        end
    end
    return nil, hidden and "hidden" or (seen > 0 and "list" or "empty")
end

-- the preview: a 480 shield that takes five hits, breaks, and comes back, over and over
local DEMO_HITS = { { 1.0, 90 }, { 1.8, 60 }, { 2.6, 140 }, { 3.5, 70 }, { 4.3, 120 } }
local DEMO_LOOP, DEMO_FULL = 6, 480
local function editing() return state.edit or GetTime() < state.demoUntil end
local function demoSample(now)
    local t = (now - (state.demoStart or now)) % DEMO_LOOP
    local left = DEMO_FULL
    for _, hit in ipairs(DEMO_HITS) do if t >= hit[1] then left = left - hit[2] end end
    if left <= 0 then return 0, "plain", nil end
    local start = now - t
    return left, "plain", { fam = FAMILIES[1], id = nil, icon = nil, expires = start + 30, duration = 30, instance = math.floor((now - (state.demoStart or now)) / DEMO_LOOP), how = "demo" }
end

local function sample(now)
    if editing() then return demoSample(now) end
    local amount, how = readAmount()
    local aura, auraHow = findAura()
    return amount, how, aura, auraHow
end

----------------------------------------------------------------------
-- look
----------------------------------------------------------------------
local function rgb(aura)
    local c = STYLE[ns.db.shieldColor or "spell"]
    if c then return c end
    return (aura and aura.fam and aura.fam.color) or STYLE.gold
end
local function paint()
    local c = rgb(state.aura)
    f.bar:SetStatusBarColor(c[1], c[2], c[3])
    f.spark:SetVertexColor(1, 1, 1, 0.9)
    f.timer:SetStatusBarColor(math.min(1, c[1] + 0.25), math.min(1, c[2] + 0.25), math.min(1, c[3] + 0.25))
    state.rgb = c
    local aura = state.aura
    local icon = aura and aura.icon
    if not icon and aura and aura.id and C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, aura.id)
        icon = ok and (N(t) or S(t)) or nil
    end
    f.icon:SetTexture(icon or FALLBACK_ICON)
end

local function timeLeft(now)
    if not state.expires then return nil end
    return math.max(0, state.expires - now)
end

local function writeTexts(now)
    local style = ns.db.shieldText or "both"
    local mode, max = state.mode, state.max
    f.amount:SetTextColor(1, 1, 1)
    f.full:SetText("")
    if style == "none" or not state.present then f.amount:SetText("")
    elseif mode == "amount" then
        local a = state.amount or 0
        local low = max and max > 0 and a / max < 0.25
        if low then f.amount:SetTextColor(1, 0.45, 0.40) end
        if style == "percent" and max and max > 0 then f.amount:SetText(math.floor(a / max * 100 + 0.5) .. "%")
        else
            f.amount:SetText(tostring(math.floor(a + 0.5)))
            if style == "both" and max and max > 0 then f.full:SetText("/ " .. math.floor(max + 0.5)) end
        end
    elseif mode == "hidden" then
        -- a hidden number: only the text itself may format it
        if not pcall(f.amount.SetFormattedText, f.amount, "%.0f", state.raw) then f.amount:SetText("") end
        if style ~= "amount" and max and state.maxKind ~= "health" then f.full:SetText("/ " .. math.floor(max + 0.5)) end
    else                                                     -- timer: no amount from the client, only what the rank gives
        f.amount:SetText(max and ("~" .. math.floor(max + 0.5)) or "")
    end
    local left = ns.db.shieldTimer ~= false and state.present and timeLeft(now) or nil
    if left then
        f.time:SetText(left >= 10 and string.format("%d", math.ceil(left)) or string.format("%.1f", left))
        if left < 5 then f.time:SetTextColor(1, 0.82, 0.40) else f.time:SetTextColor(0.90, 0.92, 0.96) end
    else f.time:SetText("") end
end

----------------------------------------------------------------------
-- state: appear, change, break
----------------------------------------------------------------------
local function range(max)
    pcall(f.bar.SetMinMaxValues, f.bar, 0, max)
    pcall(f.ghost.SetMinMaxValues, f.ghost, 0, max)
end

local function note(amountHow, aura, auraHow)
    if editing() then return end
    local d = diag()
    local key = (InCombatLockdown and InCombatLockdown()) and "combat" or "calm"
    if d[key] then return end
    d[key] = string.format("mode=%s amount=%s aura=%s id=%s nominal=%s expires=%s instance=%s max=%s(%s) smooth=%s spark=%s",
        tostring(state.mode), tostring(amountHow), tostring(auraHow), tostring(aura and aura.id), aura and aura.nominal and "plain" or "no",
        aura and aura.expires and "plain" or "no", aura and aura.instance and "yes" or "no", tostring(state.max), tostring(state.maxKind),
        INTERP and "yes" or "no", state.sparkOk and "yes" or "no")
end
-- noted when a fight hid the buffs so well that the shield was only followed by its clock
local function noteBlind()
    local d = diag()
    if state.blind and not d.blind then d.blind = "yes: followed by time and by the removed-buff signal (instance " .. tostring(state.instance) .. ")" end
end

local function appear(now, fresh)
    state.appearAt = now
    state.goneAt, state.goneKind = nil, nil
    state.sawAmount, state.instanceGone = false, nil
    if ns.db.shieldAnim ~= false then
        state.shineAt = now
        state.flash = fresh and 0.9 or 0.5
    end
end

local function refresh()
    local db = ns.db
    if not db then return end
    local now = GetTime()
    local amount, how, aura, auraHow = sample(now)
    local on = db.shieldBar ~= false or editing()
    local present = false
    if on then
        if how == "plain" then present = amount > 0 or aura ~= nil else present = aura ~= nil end
    end
    local was = state.present
    -- Buffs unreadable and no answer by spell id either, while a shield was up a moment ago: it is taken to
    -- be still there until its time is over, or until the game says that buff was removed.
    if on and not present and was and how ~= "plain" and not editing() and (auraHow == "hidden" or auraHow == "noapi")
        and state.aura and state.expires and now < state.expires and not state.instanceGone then
        present, aura = true, state.aura
        state.blind = true
    end
    if present then
        local plain = how == "plain" and amount or nil
        -- a new shield over the old one: another buff, a later end, or more than there was
        local renewed = was and ((aura and state.instance and aura.instance and aura.instance ~= state.instance)
            or (aura and aura.expires and state.expires and aura.expires > state.expires + 1)
            or (plain and state.amount and plain > state.amount + 0.5))
        if not was or renewed then appear(now, not was) end
        if plain and plain > 0 then state.sawAmount = true end
        local before = state.mode
        state.mode = (plain and (plain > 0 or state.sawAmount)) and "amount" or (how == "secret" and "hidden") or "timer"
        state.aura, state.instance = aura, aura and aura.instance
        local duration = aura and (aura.duration or (aura.fam and aura.fam.duration))
        state.duration = duration
        state.expires = aura and (aura.expires or (duration and ((not was or renewed) and (now + duration) or state.expires))) or nil
        local learn = learned()
        local lk = aura and aura.how ~= "demo" and (aura.id or aura.fam.key) or nil      -- what the full size is remembered under
        if state.mode == "amount" then
            if not was or renewed then
                state.max = plain
                if lk then
                    local freshCast = aura.expires and duration and (aura.expires - now) >= duration - 1.5
                    learn[lk] = freshCast and plain or math.max(learn[lk] or 0, plain)
                end
            else state.max = math.max(state.max or 0, plain) end
            state.maxKind = "seen"
            if state.amount and plain < state.amount - 0.5 and was and not renewed then  -- a hit: blink, and leave a trail
                state.lastHit = now
                if db.shieldAnim ~= false then state.flash = math.max(state.flash, 0.55); state.ghostHold = now + 0.28 end
            end
            state.amount, state.raw = plain, nil
            if not was or renewed or before ~= "amount" then state.disp, state.ghostV = plain, plain end
            range(math.max(1, state.max))
        elseif state.mode == "hidden" then
            local id = aura and aura.id
            -- the shield was readable a moment ago (a fight began): its full size is known
            local max, kind = (was and not renewed and before == "amount") and state.max or nil, "seen"
            if not max then max, kind = lk and learn[lk], "learned" end
            if not max then max, kind = aura and aura.nominal, "buff" end
            if not max then max, kind = id and aura.fam.ids[id], "rank" end
            if not max then max, kind = N(UnitHealthMax and UnitHealthMax("player")), "health" end
            state.max, state.maxKind = max or 1, max and kind or "none"
            state.amount, state.raw = nil, amount
            range(state.max)
            pcall(f.bar.SetValue, f.bar, amount)
            -- the trail: the same value, eased by the client itself
            state.ghostOk = INTERP ~= nil and db.shieldAnim ~= false and pcall(f.ghost.SetValue, f.ghost, amount, INTERP) or false
        else
            local id = aura and aura.id
            state.max = aura and ((lk and learn[lk]) or aura.nominal or (id and aura.fam.ids[id])) or nil
            state.maxKind = "rank"
            state.amount, state.raw = nil, nil
            range(1)
        end
        state.present = true
        if not was or renewed then paint(); note(how, aura, auraHow) end
    elseif was then
        -- gone before its time (or right after a hit): broken; otherwise it ran out
        local broke = (state.expires and now < state.expires - 0.5) or (state.lastHit and now - state.lastHit < 1) or false
        state.present, state.goneAt, state.goneKind = false, now, broke and "broken" or "faded"
        state.amount, state.raw = state.mode == "amount" and 0 or nil, nil
        if broke and db.shieldAnim ~= false then state.flash = 1 end
        if broke and db.shieldSound and PlaySound and not editing() then
            pcall(PlaySound, (SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_2) or 12867, "Master")
        end
        state.lastHit = nil
    end
    noteBlind()
    writeTexts(now)
    local visible = present or editing() or (on and state.goneAt ~= nil and now - state.goneAt < 0.8 and db.shieldAnim ~= false)
    if visible and not f:IsShown() then f:Show() elseif not visible and f:IsShown() then f:Hide() end
    local move = editing()
    if state.moving ~= move then
        state.moving = move
        f.mover:SetShown(move)
        f:EnableMouse(move)
        if not move then place() end
    end
end
ns.RefreshShield = refresh

-- a hit on the shield when its amount cannot be compared: the game still says you were struck
ns.On("UNIT_COMBAT", function(unit, action)
    if not state.present or state.mode == "amount" or S(unit) ~= "player" then return end
    action = S(action)
    if action == "WOUND" or action == "ABSORB" or action == "BLOCK" then
        state.lastHit = GetTime()
        if ns.db.shieldAnim ~= false then state.flash = math.max(state.flash, 0.5) end
    end
end, "shield:hit")

----------------------------------------------------------------------
-- every frame while shown
----------------------------------------------------------------------
local acc = 0
f:SetScript("OnUpdate", function(_, dt)
    ns.safe("shield:frame", function()
        dt = dt or 0
        acc = acc + dt
        if acc >= 0.1 then acc = 0; refresh() end
        local db, now = ns.db, GetTime()
        local anim = db.shieldAnim ~= false
        local c = state.rgb or STYLE.gold
        -- the fill
        if state.mode == "amount" then
            local target = state.present and (state.amount or 0) or 0
            state.disp = anim and (state.disp + (target - state.disp) * math.min(1, dt * 18)) or target
            if state.ghostV < state.disp then state.ghostV = state.disp end
            if not anim then state.ghostV = state.disp
            elseif now >= state.ghostHold then state.ghostV = math.max(state.disp, state.ghostV - math.max(1, state.max or 1) * dt * 0.9) end
            f.bar:SetValue(state.disp)
            f.ghost:SetValue(state.ghostV)
            f.ghost:SetShown(anim)
        elseif state.mode == "hidden" then
            f.ghost:SetShown(state.ghostOk == true)
            if not state.present then pcall(f.bar.SetValue, f.bar, 0); pcall(f.ghost.SetValue, f.ghost, 0) end
        else
            local left, d = timeLeft(now), state.duration
            f.bar:SetValue((state.present and left and d and d > 0) and math.min(1, left / d) or 0)
            f.ghost:SetShown(false)
        end
        -- the time line
        if db.shieldTimer ~= false then
            local left, d = timeLeft(now), state.duration
            f.timer:SetValue((state.present and left and d and d > 0) and math.min(1, left / d) or 0)
        end
        -- spark, blink, shine
        f.spark:SetShown(anim and state.sparkOk == true and state.present and state.mode ~= "timer")
        state.flash = math.max(0, state.flash - dt * 3.5)
        f.flash:SetAlpha(anim and state.flash * 0.6 or 0)
        if state.goneKind == "broken" then f.flash:SetVertexColor(1, 0.25, 0.20) else f.flash:SetVertexColor(1, 1, 1) end
        if anim and state.shineAt then
            local p = (now - state.shineAt) / 0.55
            if p >= 1 then state.shineAt = nil; f.shine:Hide()
            else
                local sw = math.max(24, (state.bodyW or 200) * 0.28)
                f.shine:ClearAllPoints()
                f.shine:SetPoint("LEFT", f.body, "LEFT", -sw + ((state.bodyW or 200) + sw) * p, 0)
                f.shine:Show()
            end
        else f.shine:Hide() end
        -- the glow: calm in the shield's colour, quick and red when little is left
        local low = state.mode == "amount" and state.present and state.max and state.max > 0 and (state.amount or 0) / state.max < 0.25
        local gc = low and LOW_RGB or c
        local pulse = low and (0.55 + 0.35 * math.sin(now * 9)) or (0.30 + 0.14 * math.sin(now * 2.6))
        if state.appearAt and now - state.appearAt < 0.5 then pulse = math.max(pulse, 1 - (now - state.appearAt) * 1.4) end
        if not state.present then pulse = 0 end
        for i = 1, 4 do f.glow[i]:SetVertexColor(gc[1], gc[2], gc[3], anim and pulse or (state.present and 0.3 or 0)) end
        -- coming and going
        local alpha, dx = 1, 0
        if state.present and state.appearAt and anim then alpha = math.min(1, 0.25 + (now - state.appearAt) / 0.15)
        elseif not state.present and state.goneAt and not editing() then
            local age = now - state.goneAt
            if state.goneKind == "broken" then
                if age < 0.35 then dx = math.sin(age * 70) * 4 * (1 - age / 0.35) end       -- a short shake
                alpha = age < 0.35 and 1 or math.max(0, 1 - (age - 0.35) / 0.4)
            else alpha = math.max(0, 1 - age / 0.4) end
        elseif not state.present and state.goneAt and state.goneKind == "broken" and anim then   -- the preview breaks too, but stays
            local age = now - state.goneAt
            if age < 0.35 then dx = math.sin(age * 70) * 4 * (1 - age / 0.35) end
        end
        f:SetAlpha(alpha)
        if not state.dragging and (dx ~= 0 or state.shook) then place(dx); state.shook = dx ~= 0 end
    end)
end)

----------------------------------------------------------------------
-- moving it: the game's Edit Mode, or the preview
----------------------------------------------------------------------
f:SetScript("OnDragStart", function(self)
    if not editing() then return end
    state.dragging = true
    self:StartMoving()
end)
f:SetScript("OnDragStop", function(self)
    if not state.dragging then return end
    state.dragging = nil
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint(1)
    local pos = ns.db.shieldPos
    pos.point, pos.x, pos.y = point, x, y
    place()
end)

local function setEdit(on)
    on = on and true or false
    if state.edit == on then return end
    state.edit = on
    if on then state.demoStart = GetTime() end
    state.present = false                                    -- start clean on either side: no break played for the preview
    state.goneAt, state.goneKind, state.amount, state.lastHit = nil, nil, nil, nil
    refresh()
end
ns.ShieldEdit = setEdit

function ns.ShieldPreview(seconds)
    state.demoStart = GetTime()
    state.demoUntil = GetTime() + (seconds or 20)
    state.present, state.goneAt, state.goneKind, state.amount, state.lastHit = false, nil, nil, nil, nil
    refresh()
    ns.After((seconds or 20) + 0.1, function()
        if editing() then return end
        state.present, state.goneAt, state.goneKind, state.amount, state.lastHit = false, nil, nil, nil, nil
        refresh()
    end, "shield:preview")
end

function ns.ApplyShield()
    if not ns.db then return end
    layout()
    paint()
    refresh()
end

ns.On("UNIT_AURA", function(unit, info)
    if unit ~= nil and S(unit) ~= "player" then return end
    local removed = T(info) and T(info.removedAuraInstanceIDs)
    if removed and state.instance then
        for _, id in ipairs(removed) do if N(id) == state.instance then state.instanceGone = true end end
    end
    refresh()
end, "shield:UNIT_AURA")
ns.On("UNIT_ABSORB_AMOUNT_CHANGED", function(unit) if unit == nil or S(unit) == "player" then refresh() end end, "shield:absorb")
ns.On("PLAYER_ENTERING_WORLD", function() refresh() end, "shield:world")
ns.Every(0.5, function() if not f:IsShown() then refresh() end end, "shield:tick")   -- a net under the events

-- what the client shows about buffs once a fight is on, with no shield needed: noted once
ns.On("PLAYER_REGEN_DISABLED", function()
    ns.After(1, function()
        local d = diag()
        if d.fight then return end
        local _, how = readAmount()
        local aura, auraHow = findAura()
        local names = {}
        for k, v in pairs(type(C_Secrets) == "table" and C_Secrets or {}) do
            if type(k) == "string" and type(v) == "function" and k:find("Aura") then names[#names + 1] = k end
        end
        table.sort(names)
        d.fight = "amount=" .. tostring(how) .. " buffs=" .. tostring(auraHow) .. " shield=" .. (aura and "yes" or "no")
            .. " secrets=" .. table.concat(names, ",")
    end, "shield:probe")
end, "shield:fight")

ns.OnLogin(function()
    -- the shields' names in the game's language, for buffs that give a name but no spell id
    for _, fam in ipairs(FAMILIES) do
        for id in pairs(fam.ids) do
            local name = C_Spell and C_Spell.GetSpellName and S((select(2, pcall(C_Spell.GetSpellName, id))))
            if name then BY_NAME[name] = fam end
        end
    end
    local d = diag()
    if d.version ~= ns.version then                           -- what an older version noted says nothing about this one
        for k in pairs(d) do d[k] = nil end
        d.version = ns.version
    end
    d.api = type(UnitGetTotalAbsorbs) == "function" and "yes" or "no"
    -- Edit Mode: the bar shows itself there, with its preview running, and can be dragged
    if EventRegistry and EventRegistry.RegisterCallback then
        pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Enter", function() ns.safe("shield:edit", function() setEdit(true) end) end, f)
        pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", function() ns.safe("shield:edit", function() setEdit(false) end) end, f)
        d.editMode = "events"
    end
    local em = _G.EditModeManagerFrame
    if em and em.HookScript then
        pcall(em.HookScript, em, "OnShow", function() ns.safe("shield:edit", function() setEdit(true) end) end)
        pcall(em.HookScript, em, "OnHide", function() ns.safe("shield:edit", function() setEdit(false) end) end)
        d.editMode = (d.editMode and (d.editMode .. "+") or "") .. "frame"
    end
    if not d.editMode then d.editMode = "none" end
    ns.ApplyShield()
end, "shield:login")
