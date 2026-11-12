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
--
-- In a fight this client hides the amount and the buffs. So that the bar neither loses a shield nor shows
-- one that is gone, everything drawn sits in a box cut to the filled part of a second, invisible bar that
-- runs from 0 to 1 and is given the same hidden amount: one point of shield or more fills it and the bar
-- is there, none empties it and the bar is not. The game does that; the addon never learns the number.
-- Which shield it is comes from the buff when that can be read, else from your own cast, else from what
-- was up when the fight began.
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
local BY_ID, BY_NAME, BY_KEY = {}, {}, {}
for _, fam in ipairs(FAMILIES) do
    BY_KEY[fam.key] = fam
    for id in pairs(fam.ids) do BY_ID[id] = fam end
end
-- the shield a spell id stands for: by the table, else by its name (a client may number a known shield its own way)
local function familyOf(id)
    if not id then return nil end
    local fam = BY_ID[id]
    if fam then return fam end
    local name = C_Spell and C_Spell.GetSpellName and S((select(2, pcall(C_Spell.GetSpellName, id))))
    fam = name and BY_NAME[name] or nil
    if fam then BY_ID[id] = fam end
    return fam
end

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

-- the invisible 0-to-1 bar, and the box cut to its filled part that everything else is drawn in
f.presence = statusBar(f, 1)
f.presence:SetPoint("TOPLEFT", f, "TOPLEFT", -6, 6)
f.presence:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 6, -6)
f.presence:SetStatusBarColor(0, 0, 0, 0)
f.presence:SetValue(1)
f.content = CreateFrame("Frame", nil, f)
do
    local fill = f.presence.GetStatusBarTexture and f.presence:GetStatusBarTexture()
    if fill and f.content.SetClipsChildren then
        f.content:SetClipsChildren(true)
        f.content:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
        f.content:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
        state.presenceOk = true
    else
        f.content:SetAllPoints(f.presence)
        state.presenceOk = false
    end
end

-- a soft glow outside the border: four edges, pulsing while a shield is up
f.glow = {}
for i = 1, 4 do
    local g = tex(f.content, "BACKGROUND")
    if g.SetBlendMode then g:SetBlendMode("ADD") end
    f.glow[i] = g
end
f.edge = tex(f.content, "BACKGROUND", 0, 0, 0, 0.85)                  -- the dark border
f.edge:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
f.edge:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)

f.iconBox = CreateFrame("Frame", nil, f.content)
f.icon = f.iconBox:CreateTexture(nil, "ARTWORK")
f.icon:SetAllPoints()
if f.icon.SetTexCoord then f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

f.body = CreateFrame("Frame", nil, f.content)                        -- everything that fills: clipped to the bar's shape
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

-- true while the client keeps buffs from addons (it says so itself; else: in a fight)
local function buffsKeptBack()
    local ask = type(C_Secrets) == "table" and C_Secrets.ShouldAurasBeSecret
    if type(ask) == "function" then
        local ok, v = pcall(ask)
        if ok and B(v) ~= nil then return B(v) end
    end
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

local function auraInfo(a, fam, id, how)
    a = a or {}
    local points = T(a.points)
    return { fam = fam, id = id or N(a.spellId), name = S(a.name), icon = N(a.icon) or S(a.icon), expires = N(a.expirationTime),
        duration = N(a.duration), left = points and N(points[1]) or nil, instance = N(a.auraInstanceID), how = how }
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
                if fam then
                    if id and not BY_ID[id] then BY_ID[id] = fam end
                    return auraInfo(a, fam, id, "list"), "list"
                end
            end
        end
    end
    if (hidden or not UA.GetAuraDataByIndex) and UA.GetPlayerAuraBySpellID then
        for id, fam in pairs(BY_ID) do
            local ok, raw = pcall(UA.GetPlayerAuraBySpellID, id)
            if ok and raw ~= nil then return auraInfo(T(raw), fam, id, "byid"), "byid" end
        end
    end
    -- no buffs at all: either there are none, or (in a fight) the client is keeping them back
    return nil, hidden and "hidden" or ((seen > 0 or not buffsKeptBack()) and "list" or "empty")
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

-- the amount every time; the buffs when something changed, and twice a second besides
local function sample(now, fresh)
    if editing() then return demoSample(now) end
    local amount, how = readAmount()
    if fresh or not state.scanAt or now - state.scanAt >= 0.5 or now < state.scanAt then
        state.scanAura, state.scanHow = findAura()
        state.scanAt = now
    end
    return amount, how, state.scanAura, state.scanHow
end

-- a short record of what the client says during fights, for the saved data: what can be read there
-- decides how well the bar can follow a shield
local TRACE_MAX = 80
local function flag(v)
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return "hidden" end
    return tostring(v)
end
local function trace(text)
    local d = diag()
    d.trace = type(d.trace) == "table" and d.trace or {}
    if #d.trace >= TRACE_MAX then return end
    d.trace[#d.trace + 1] = string.format("%.1f %s%s", GetTime() % 1000, (InCombatLockdown and InCombatLockdown()) and "F " or "- ", text)
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

local function note(amountHow, known, auraHow)
    if editing() then return end
    local d = diag()
    local key = (InCombatLockdown and InCombatLockdown()) and "combat" or "calm"
    if d[key] then return end
    d[key] = string.format("mode=%s amount=%s buffs=%s shield=%s id=%s left=%s expires=%s instance=%s max=%s(%s) smooth=%s spark=%s box=%s",
        tostring(state.mode), tostring(amountHow), tostring(auraHow), tostring(known and known.how), tostring(known and known.id),
        known and known.left and "plain" or "no", known and known.expires and "plain" or "no", known and known.instance and "yes" or "no",
        tostring(state.max), tostring(state.maxKind), INTERP and "yes" or "no", state.sparkOk and "yes" or "no", state.presenceOk and "yes" or "no")
end

-- what a shield of this kind holds when full, as far as is known: read at a fresh cast, else the rank's, else
-- what this character's last shield held
local function fullSize(known, lk)
    if not known then return nil end
    local learn = learned()
    return (lk and learn[lk]) or (known.id and known.fam.ids[known.id]) or known.full or nil
end

local function refresh(fresh)
    local db = ns.db
    if not db then return end
    local now = GetTime()
    local amount, how, aura, auraHow = sample(now, fresh)
    local demo = editing()
    local on = db.shieldBar ~= false or demo
    local was, before = state.present, state.mode
    local secret = how == "secret"
    -- The amount itself is hidden on this client even out of a fight, but the buff carries what is left as a
    -- plain number whenever buffs can be read, and that serves as well.
    local left = (how ~= "plain" and not demo and aura and aura.left) or nil
    local readable = how == "plain" or auraHow == "list"      -- buffs (or the amount) can be read: what is seen is the truth
    if not secret or readable then state.standby = nil end
    -- your own cast is only a stand-in for the buff: dropped once things can be read, or its time is over
    local cast = state.cast
    if cast and (how == "plain" or demo or now >= cast.expires or (auraHow == "list" and now - cast.castAt > 1)) then state.cast, cast = nil, nil end
    -- which shield: the buff when it can be read, else your own cast, else the one that was up a moment ago,
    -- else (something landed, nothing says what) the kind this character had last
    local known = aura
    if not known and how ~= "plain" and not demo then
        if cast then known = cast
        elseif was and state.aura and state.expires and now < state.expires and not state.instanceGone and auraHow ~= "list" then
            known = state.aura
            if not state.blind then state.blind = true; diag().blind = "followed by its clock (buffs=" .. tostring(auraHow) .. ")" end
        elseif state.standby and state.presenceOk and ns.char and T(ns.char.lastShield) then
            local last = ns.char.lastShield
            local fam = BY_KEY[S(last.key) or ""]
            if fam then known = { fam = fam, id = N(last.id), full = N(last.full), how = "guess" } end
        end
    end
    local present = false
    if on then
        if how == "plain" then present = amount > 0 or aura ~= nil
        elseif secret then present = known ~= nil or (state.standby == true and state.presenceOk == true)
        else present = known ~= nil end
    end
    if present then
        local plain = (how == "plain" and amount) or left or nil
        -- a new shield over the old one: another buff, a later end, another cast, or more than there was
        local renewed = was and ((known and ((state.instance and known.instance and known.instance ~= state.instance)
            or (known.expires and state.expires and known.expires > state.expires + 1)
            or (known.castAt and known.castAt ~= state.castAt)))
            or (plain and state.amount and plain > state.amount + 0.5)) or false
        if not was or renewed then
            state.goneAt, state.goneKind, state.sawAmount, state.instanceGone, state.lastHit = nil, nil, false, nil, nil
            if known ~= nil or (plain and plain > 0) then              -- not for the empty wait at the start of a fight
                state.appearAt = now
                if db.shieldAnim ~= false then state.shineAt = now; state.flash = was and 0.5 or 0.9 end
            end
        end
        if plain and plain > 0 then state.sawAmount = true end
        state.mode = (plain and (plain > 0 or state.sawAmount)) and "amount" or (secret and "hidden") or "timer"
        local duration = known and known.how ~= "guess" and (known.duration or known.fam.duration) or nil   -- a guess has no clock
        state.duration = duration
        state.expires = known and (known.expires or (duration and (((not was or renewed or not state.expires) and (now + duration)) or state.expires))) or nil
        state.aura, state.instance, state.castAt = known, known and known.instance, known and known.castAt
        local lk = known and known.how ~= "demo" and (known.id or known.fam.key) or nil      -- what the full size is remembered under
        if state.mode == "amount" then
            local freshCast = known and known.expires and duration and (known.expires - now) >= duration - 1.5
            if not was or renewed then
                if freshCast or not known then
                    state.max = plain
                    if freshCast and lk then learned()[lk] = plain end
                else state.max = math.max(plain, fullSize(known, lk) or 0) end          -- met half used: after a fight, or at login
                if known and known.how ~= "demo" and ns.char then ns.char.lastShield = { key = known.fam.key, id = known.id, full = state.max } end
            elseif before ~= "amount" then                           -- the fight is over and the number can be read again
                state.max = math.max(plain, (state.maxKind ~= "health" and state.maxKind ~= "none" and state.max) or fullSize(known, lk) or 0)
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
            -- the full size: what it was while readable, else what is known of this kind of shield, else your health
            local max, kind = (was and not renewed and state.maxKind == "seen") and state.max or nil, "seen"
            if not max then max, kind = lk and learned()[lk], "learned" end
            if not max then max, kind = known and known.id and known.fam.ids[known.id], "rank" end
            if not max then max, kind = known and known.full, "last" end
            if not max then max, kind = N(UnitHealthMax and UnitHealthMax("player")), "health" end
            state.max, state.maxKind = max or 1, max and kind or "none"
            state.amount, state.raw = nil, amount
            range(state.max)
            pcall(f.bar.SetValue, f.bar, amount)
            -- the trail: the same value, eased by the client itself
            state.ghostOk = INTERP ~= nil and db.shieldAnim ~= false and pcall(f.ghost.SetValue, f.ghost, amount, INTERP) or false
        else
            state.max, state.maxKind = fullSize(known, lk), "rank"
            state.amount, state.raw = nil, nil
            range(1)
        end
        state.present = true
        local look = (known and (known.fam.key .. ":" .. tostring(known.id)) or "?") .. ":" .. tostring(db.shieldColor)
        if look ~= state.look then state.look = look; paint() end
        if not was or renewed then note(how, known, auraHow) end
    elseif was then
        -- the fight is over and nothing is left: it ended some time ago, unseen. No farewell for that.
        local silent = before == "hidden" and readable
        -- gone before its time (or right after a hit): broken; otherwise it ran out
        local broke = (state.expires and now < state.expires - 0.5) or (state.lastHit and now - state.lastHit < 1) or false
        state.present = false
        state.goneAt, state.goneKind = (not silent) and now or nil, (not silent) and (broke and "broken" or "faded") or nil
        state.amount, state.raw = before == "amount" and 0 or nil, nil
        if not silent then
            if broke and db.shieldAnim ~= false then state.flash = 1 end
            if broke and db.shieldSound and PlaySound and not demo then
                pcall(PlaySound, (SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_2) or 12867, "Master")
            end
        end
        state.lastHit, state.blind, state.look = nil, nil, nil
    end
    -- the box everything is drawn in: open, or (hidden amount) as open as the game makes it
    if state.present and state.mode == "hidden" then
        if not pcall(f.presence.SetValue, f.presence, amount) then f.presence:SetValue(1) end
    else f.presence:SetValue(1) end
    local sig = tostring(state.present) .. "/" .. tostring(state.mode) .. "/" .. tostring(how) .. "/" .. tostring(auraHow) .. "/" .. tostring(state.aura and state.aura.how)
    if sig ~= state.sig and not demo then
        state.sig = sig
        trace("STATE present=" .. tostring(state.present) .. " mode=" .. tostring(state.mode) .. " amount=" .. tostring(how) .. " buffs=" .. tostring(auraHow)
            .. " shield=" .. tostring(state.aura and state.present and state.aura.how) .. " max=" .. tostring(state.max) .. "(" .. tostring(state.maxKind) .. ")"
            .. (state.goneKind and (" gone=" .. state.goneKind) or ""))
    end
    writeTexts(now)
    local visible = present or demo or (on and state.goneAt ~= nil and now - state.goneAt < 0.8 and db.shieldAnim ~= false)
    if visible and not f:IsShown() then f:Show() elseif not visible and f:IsShown() then f:Hide() end
    if state.moving ~= demo then
        state.moving = demo
        f.mover:SetShown(demo)
        f:EnableMouse(demo)
        if not demo then place() end
    end
end
ns.RefreshShield = refresh

-- a hit on the shield when its amount cannot be compared: the game still says you were struck
ns.On("UNIT_COMBAT", function(unit, action)
    if not state.present or state.mode == "amount" or S(unit) ~= "player" then return end
    action = S(action)
    if action == "WOUND" or action == "ABSORB" or action == "BLOCK" then
        state.lastHit = GetTime()
        if state.mode == "timer" and ns.db.shieldAnim ~= false then state.flash = math.max(state.flash, 0.5) end
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
        -- the cut-to-fit box, checked once while it should be fully open: if it has no width the client does
        -- not size it from the bar, and everything is drawn the plain way instead
        if state.presenceOk and not state.boxChecked and state.present and state.mode ~= "hidden" then
            state.boxAge = (state.boxAge or 0) + dt
            if state.boxAge > 0.5 then
                state.boxChecked = true
                local w = N(f.content.GetWidth and f.content:GetWidth())
                if w and w < 2 then
                    state.presenceOk = false
                    f.content:ClearAllPoints()
                    f.content:SetAllPoints(f.presence)
                    if f.content.SetClipsChildren then f.content:SetClipsChildren(false) end
                end
                diag().box = (state.presenceOk and "ok" or "fallback") .. " width=" .. tostring(w)
            end
        end
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
    info = T(info)
    local removed = info and T(info.removedAuraInstanceIDs)
    if removed and state.instance then
        for _, id in ipairs(removed) do if N(id) == state.instance then state.instanceGone = true end end
    end
    if info and InCombatLockdown and InCombatLockdown() then
        local added = T(info.addedAuras)
        local first = added and T(added[1])
        if (added and #added > 0) or (removed and #removed > 0) then
            trace("AURA added=" .. (added and #added or 0) .. (first and (" first[id=" .. flag(first.spellId) .. " inst=" .. flag(first.auraInstanceID)
                .. " help=" .. flag(first.isHelpful) .. " ends=" .. flag(first.expirationTime) .. "]") or "")
                .. " removed=" .. (removed and #removed or 0) .. (removed and removed[1] ~= nil and ("[" .. flag(removed[1]) .. "]") or "")
                .. " ours=" .. tostring(state.instance) .. (state.instanceGone and " GONE" or ""))
        end
    end
    refresh(true)
end, "shield:UNIT_AURA")

-- the amount on you changed. While it is hidden that is all there is to know: a shield landed or took a hit.
-- From then until the numbers are readable again the bar is kept ready, and the game draws it or not.
ns.On("UNIT_ABSORB_AMOUNT_CHANGED", function(unit)
    if unit ~= nil and S(unit) ~= "player" then return end
    local _, how = readAmount()
    if how == "secret" then
        if not state.standby then trace("ABSORB amount=hidden: kept ready from here") end
        state.standby = true
        if state.present and state.mode == "hidden" and ns.db.shieldAnim ~= false and GetTime() - (state.appearAt or 0) > 0.4 then
            state.flash = math.max(state.flash, 0.5)
        end
        state.lastHit = GetTime()
    end
    refresh(true)
end, "shield:absorb")

-- your own shield casts (and the Voidwalker's Sacrifice): in a fight the buff may be unreadable, the cast is not
ns.On("UNIT_SPELLCAST_SENT", function(unit, target, _, spellID)
    if S(unit) ~= "player" then return end
    local id = N(spellID)
    if id and familyOf(id) then state.sent = { id = id, target = S(target), at = GetTime() } end
end, "shield:sent")
local SELF_ONLY = { barrier = true, mana = true, fireward = true, frostward = true, shadowward = true }
-- "Name" against "Name-Realm", or a first name against a full one (names here may have a space)
local function sameName(a, b)
    a, b = a:match("^[^-]+") or a, b:match("^[^-]+") or b
    return a == b or a:find(b, 1, true) == 1 or b:find(a, 1, true) == 1
end
local hiddenCasts = 0
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    unit = S(unit)
    if unit ~= "player" and unit ~= "pet" then return end
    local id = N(spellID)
    if not id then                                            -- the spell itself is hidden: noted a few times, nothing to go by
        hiddenCasts = hiddenCasts + 1
        if hiddenCasts <= 3 then trace("CAST by=" .. unit .. " id=" .. flag(spellID)) end
        return
    end
    local fam = familyOf(id)
    if not fam then return end
    local now, onMe = GetTime(), false
    if unit == "pet" then onMe = fam.key == "sacrifice"
    elseif SELF_ONLY[fam.key] then onMe = true
    elseif fam.key == "pws" then
        local sent = state.sent
        local target = sent and sent.id == id and now - sent.at < 4 and sent.target or nil
        local me = S(UnitName and UnitName("player"))
        if target and target ~= "" then onMe = me ~= nil and sameName(target, me)
        else                                                 -- no name given: yours, unless you have someone else selected to help
            local other = UnitExists and B(UnitExists("target")) and UnitIsFriend and B(UnitIsFriend("player", "target"))
                and UnitIsUnit and B(UnitIsUnit("target", "player")) == false
            onMe = not other
        end
    end
    trace("CAST id=" .. id .. " by=" .. unit .. " target=" .. tostring(state.sent and state.sent.id == id and state.sent.target) .. " on me=" .. tostring(onMe))
    if not onMe then return end
    state.cast = { fam = fam, id = id, duration = fam.duration, expires = now + fam.duration, castAt = now, how = "cast" }
    refresh(true)
end, "shield:cast")

ns.On("PLAYER_ENTERING_WORLD", function() refresh(true) end, "shield:world")
ns.Every(0.5, function() if not f:IsShown() then refresh() end end, "shield:tick")   -- a net under the events

-- what the client lets an addon read once a fight is on: noted at the start of the first few fights
local fights = 0
ns.On("PLAYER_REGEN_DISABLED", function()
    refresh(true)
    fights = fights + 1
    if fights > 3 then return end
    ns.After(1, function()
        local d = diag()
        local _, how = readAmount()
        local aura, auraHow = findAura()
        local UA, count, ids, names, insts = C_UnitAuras, 0, 0, 0, 0
        if UA and UA.GetAuraDataByIndex then
            for i = 1, 40 do
                local ok, raw = pcall(UA.GetAuraDataByIndex, "player", i, "HELPFUL")
                if not ok or raw == nil then break end
                count = count + 1
                local a = T(raw)
                if a then
                    if N(a.spellId) then ids = ids + 1 end
                    if S(a.name) then names = names + 1 end
                    if N(a.auraInstanceID) then insts = insts + 1 end
                end
            end
        end
        local apis = {}
        for _, name in ipairs({ "GetAuraDataByIndex", "GetPlayerAuraBySpellID", "GetAuraDataByAuraInstanceID", "GetAuraDuration", "GetUnitAuraBySpellID", "GetBuffDataByIndex" }) do
            if UA and type(UA[name]) == "function" then apis[#apis + 1] = name end
        end
        local secrets = {}
        for k, v in pairs(type(C_Secrets) == "table" and C_Secrets or {}) do
            if type(k) == "string" and type(v) == "function" and (k:find("Aura") or k:find("Absorb")) then
                local ok, r = pcall(v)
                secrets[#secrets + 1] = k .. "=" .. (ok and flag(r) or "args")
            end
        end
        table.sort(secrets)
        local text = "amount=" .. tostring(how) .. " buffs=" .. tostring(auraHow) .. " seen=" .. count .. " ids=" .. ids .. " names=" .. names .. " instances=" .. insts
            .. " shield=" .. tostring(aura and aura.how) .. " box=" .. tostring(state.presenceOk) .. " apis=" .. table.concat(apis, ",") .. " secrets=" .. table.concat(secrets, ",")
        d.fight = d.fight or text
        trace("FIGHT " .. text)
    end, "shield:probe")
end, "shield:fight")
ns.On("PLAYER_REGEN_ENABLED", function() ns.After(0.3, function() refresh(true) end, "shield:calm") end, "shield:calm")

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
    d.trace = nil                                             -- each session its own record
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
