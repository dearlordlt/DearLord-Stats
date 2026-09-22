-- DearLord Stats 2.0 : Core
-- Shared plumbing: secret-value guards, formatting, saved data, events, ticker,
-- error capture, the on-screen HUD windows, and the quiet message feed.
local ADDON, ns = ...
ns.version = "2.3.1"

----------------------------------------------------------------------
-- secret values: this client hides some combat numbers from addons.
-- Touching a hidden value (compare, add, format) raises an error, so every
-- value that might be hidden goes through one of these first.
----------------------------------------------------------------------
local issecret = type(issecretvalue) == "function" and issecretvalue or function() return false end
function ns.N(v) if v == nil or issecret(v) or type(v) ~= "number" then return nil end return v end
function ns.S(v) if v == nil or issecret(v) or type(v) ~= "string" then return nil end return v end
function ns.T(v) if v == nil or issecret(v) or type(v) ~= "table" then return nil end return v end
function ns.B(v) if v == nil or issecret(v) then return nil end return v and true or false end
-- true when a value is present, including a hidden one (hidden still means "there is something")
function ns.exists(v) if issecret(v) then return true end return v ~= nil end

----------------------------------------------------------------------
-- look and formatting
----------------------------------------------------------------------
ns.LABEL, ns.WHITE, ns.BLUE, ns.AMBER, ns.RED, ns.GREEN =
    "|cffc4c4c4", "|cffffffff", "|cff7fb2ff", "|cffffd166", "|cffff6b6b", "|cff8ce99a"

function ns.shortNumber(n)
    if not n then return "-" end
    if n >= 1000000 then return string.format("%.1fm", n / 1000000)
    elseif n >= 10000 then return string.format("%.1fk", n / 1000)
    else return tostring(math.floor(n + 0.5)) end
end
function ns.shortTime(sec)
    if not sec or sec ~= sec or sec == math.huge then return "-" end
    if sec < 60 then return "<1m" end
    local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
    if h > 0 then return string.format("%dh %02dm", h, m) end
    return string.format("%dm", m)
end
function ns.seconds(sec)
    if not sec then return "-" end
    if sec < 60 then return string.format("%.0fs", sec) end
    return string.format("%dm %02ds", math.floor(sec / 60), math.floor(sec % 60))
end
function ns.pct(part, whole)
    if not part or not whole or whole <= 0 then return "-" end
    return string.format("%d%%", math.floor(part / whole * 100 + 0.5))
end
function ns.money(copper, signed, plain)
    local neg = copper < 0
    local c = math.floor(math.abs(copper) + 0.5)
    local g, s, k = math.floor(c / 10000), math.floor(c % 10000 / 100), c % 100
    local G, S, K = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"
    if plain then G, S, K = "g", "s", "c" end
    local out
    if g > 0 then out = string.format("%d%s %d%s", g, G, s, S)
    elseif s > 0 then out = string.format("%d%s %d%s", s, S, k, K)
    else out = string.format("%d%s", k, K) end
    if neg then return "-" .. out elseif signed then return "+" .. out end
    return out
end
function ns.say(msg) print("|cff9ecbffDearLord Stats:|r " .. msg) end
function ns.strip(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

function ns.spellName(id)
    id = ns.N(id)
    if not id then return nil end
    local name
    if C_Spell and C_Spell.GetSpellName then name = ns.S(C_Spell.GetSpellName(id)) end
    if not name and C_Spell and C_Spell.GetSpellInfo then
        local info = ns.T(C_Spell.GetSpellInfo(id))
        name = info and ns.S(info.name)
    end
    if id == 6603 and (not name or name == "Attack") then name = "Melee" end
    return name or ("spell " .. id)
end
function ns.itemName(id)
    local name
    if C_Item and C_Item.GetItemNameByID then name = ns.S(C_Item.GetItemNameByID(id)) end
    return name or ("item " .. tostring(id))
end
function ns.itemCount(id)
    if C_Item and C_Item.GetItemCount then return ns.N(C_Item.GetItemCount(id)) or 0 end
    return 0
end
function ns.zone()
    local z = ns.S(GetZoneText and GetZoneText()) or "?"
    return z ~= "" and z or "?"
end

----------------------------------------------------------------------
-- error capture: one broken feature must never spam popups or stop the rest.
-- Errors land in DearLordStatsDB.errors (readable from disk) and /dls errors.
----------------------------------------------------------------------
local announced = false
local function logError(label, err)
    local db = ns.db
    if not db then return end
    db.errors = db.errors or {}
    local msg = tostring(err)
    for _, e in ipairs(db.errors) do
        if e.msg == msg then e.count = e.count + 1; e.last = time(); return end
    end
    if #db.errors >= 30 then table.remove(db.errors, 1) end
    table.insert(db.errors, { msg = msg, where = label, count = 1, first = time(), last = time(), version = ns.version })
    if not announced then
        announced = true
        ns.say("an internal error was logged and that feature skipped a beat (/dls errors)")
    end
end
local function handler(err) return (debugstack and (tostring(err) .. "\n" .. debugstack(2, 6, 0))) or tostring(err) end
function ns.safe(label, fn, ...)
    local ok, err = xpcall(fn, handler, ...)
    if not ok then logError(label, err) end
    return ok
end
-- xpcall in Lua 5.1 does not forward arguments; wrap when arguments are needed
function ns.call(label, fn, ...)
    local args, n = { ... }, select("#", ...)
    return ns.safe(label, function() return fn(unpack(args, 1, n)) end)
end

----------------------------------------------------------------------
-- events, ticker, timers
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers, refused = {}, {}
function ns.On(event, fn, label)
    if not handlers[event] then
        handlers[event] = {}
        if not pcall(frame.RegisterEvent, frame, event) then refused[event] = true end
    end
    table.insert(handlers[event], { fn = fn, label = label or event })
end
frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do ns.call(list[i].label, list[i].fn, ...) end
end)

local tickers = {}
function ns.Every(seconds, fn, label) table.insert(tickers, { every = seconds, acc = 0, fn = fn, label = label or "ticker" }) end
frame:SetScript("OnUpdate", function(_, elapsed)
    for i = 1, #tickers do
        local t = tickers[i]
        t.acc = t.acc + elapsed
        if t.acc >= t.every then
            local dt = t.acc
            t.acc = 0
            ns.call(t.label, t.fn, dt)
        end
    end
end)
function ns.After(seconds, fn, label)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, function() ns.safe(label or "timer", fn) end) end
end

----------------------------------------------------------------------
-- saved data
----------------------------------------------------------------------
local defaults = {
    locked = false, scale = 1, alpha = 1, showXP = true, fontSize = 13, background = false,
    showRecap = true, nudges = true,
    font = "friz", outline = "OUTLINE", bgAlpha = 0.4, showStats = true, showGold = true, showProf = true,
    recapHold = 8, nudgeHold = 25, panelAlpha = 0.92, panelFontSize = 12, lootAnnounce = true,
    stats = { point = "TOP", x = 0, y = -12 },
    xp    = { point = "TOP", x = 0, y = -34 },
    panel = { point = "CENTER", x = 0, y = 40 },
}
ns.defaults = defaults

function ns.newAggregate()
    return { fights = 0, time = 0, dmg = 0, taken = 0, healed = 0, kills = 0, killTime = 0,
        endHP = 0, endHPn = 0, endMana = 0, endManaN = 0, takenPct = 0, takenPctN = 0,
        close = 0, oom = 0, oomFights = 0, deaths = 0, rest = 0, restN = 0, active = 0,
        petDmg = 0, size = {}, abil = {} }
end

local loginHooks = {}
function ns.OnLogin(fn, label) table.insert(loginHooks, { fn = fn, label = label or "login" }) end

function ns.newSession()
    if ns.ArchiveLoot and ns.db.session then ns.ArchiveLoot(ns.db.session) end      -- keep a one-line summary of the old one
    ns.db.session = { start = time(), xp = 0, kills = 0, quests = 0, earned = 0, spent = 0,
        combat = ns.newAggregate(), casts = {}, prof = {}, active = 0 }
    ns.session = ns.db.session
end

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    DearLordStatsDB = DearLordStatsDB or {}
    local db = DearLordStatsDB
    ns.db = db
    db.probe = nil                                   -- left over from the 1.4.x API probe
    if db.point and not db.stats then db.stats = { point = db.point, x = db.x, y = db.y } end
    db.point, db.x, db.y = nil, nil, nil
    for k, v in pairs(defaults) do
        if db[k] == nil then
            db[k] = type(v) == "table" and { point = v.point, x = v.x, y = v.y } or v
        end
    end
    if (db.version or 1) < 2 then db.alpha = 1; db.version = 2 end
    db.chars = db.chars or {}
    db.diag = db.diag or {}
    if db.errorsVersion ~= ns.version then db.errors, db.errorsVersion = {}, ns.version end   -- old versions' errors are stale
    if type(db.session) ~= "table" then ns.newSession() else ns.session = db.session end
    local s = ns.session
    s.combat = s.combat or ns.newAggregate()
    s.casts, s.prof, s.active = s.casts or {}, s.prof or {}, s.active or 0
    s.earned, s.spent = s.earned or 0, s.spent or 0
    ns.ApplyHudSettings()
end, "core:loaded")

ns.On("PLAYER_ENTERING_WORLD", function(isInitialLogin)
    if not ns.db then return end
    if isInitialLogin then ns.newSession() end
    local db = ns.db
    local key = (ns.S(UnitName("player")) or "?") .. "-" .. (GetRealmName and ns.S(GetRealmName()) or "?")
    db.chars[key] = db.chars[key] or {}
    local c = db.chars[key]
    ns.char, ns.charKey = c, key
    c.levels, c.journal, c.prof = c.levels or {}, c.journal or {}, c.prof or {}
    c.recipes, c.gather, c.lowskill = c.recipes or {}, c.gather or {}, c.lowskill or {}
    c.unlocks, c.ignoreSpells, c.deathLog, c.flags = c.unlocks or {}, c.ignoreSpells or {}, c.deathLog or {}, c.flags or {}
    c.combat = c.combat or ns.newAggregate()
    c.byLevel, c.byZone, c.byDiff, c.mobs = c.byLevel or {}, c.byZone or {}, c.byDiff or {}, c.mobs or {}
    c.combat.size, c.combat.abil = c.combat.size or {}, c.combat.abil or {}
    c.casts = c.casts or {}
    local className, classFile = UnitClass("player")
    c.class, c.classFile = ns.S(className) or c.class, ns.S(classFile) or c.classFile
    c.race = ns.S((UnitRace("player"))) or c.race
    c.level, c.lastSeen = ns.N(UnitLevel("player")) or c.level, time()
    for i = 1, #loginHooks do ns.call(loginHooks[i].label, loginHooks[i].fn, isInitialLogin) end
end, "core:world")

----------------------------------------------------------------------
-- fonts (the four typefaces every client ships) and the HUD text style
----------------------------------------------------------------------
ns.FONTS = {
    { key = "friz", name = "Friz Quadrata", path = STANDARD_TEXT_FONT },
    { key = "arial", name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { key = "morpheus", name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { key = "skurri", name = "Skurri", path = "Fonts\\SKURRI.TTF" },
}
ns.OUTLINES = { { key = "", name = "Shadow only" }, { key = "OUTLINE", name = "Outline" }, { key = "THICKOUTLINE", name = "Thick outline" } }
function ns.FontPath()
    local want = ns.db and ns.db.font
    for _, f in ipairs(ns.FONTS) do if f.key == want then return f.path end end
    return STANDARD_TEXT_FONT
end
function ns.SetHudFont(fs)
    local db = ns.db
    local size, flags = (db and db.fontSize) or 13, (db and db.outline) or "OUTLINE"
    if not fs:SetFont(ns.FontPath(), size, flags) then fs:SetFont(STANDARD_TEXT_FONT, size, flags) end   -- unknown font file: fall back
end

----------------------------------------------------------------------
-- HUD windows: transparent, draggable text blocks
----------------------------------------------------------------------
ns.huds = {}

function ns.CreateHud(key, lines, justify)
    local f = CreateFrame("Frame", "DearLordStats_" .. key, UIParent)
    f.key, f.justify = key, justify
    f:SetSize(170, 8 + 15 * lines)
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.4)
    bg:Hide()
    f.bg = bg

    f.lines = {}
    for i = 1, lines do
        local fs = f:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
        fs:SetJustifyH(justify)
        f.lines[i] = fs
    end

    function f:Fit()
        local w, shown = 0, 0
        for _, fs in ipairs(self.lines) do
            if fs:IsShown() and (fs:GetText() or "") ~= "" then
                w = math.max(w, fs:GetStringWidth()); shown = shown + 1
            end
        end
        self:SetWidth(w + 16)
        self:SetHeight(8 + (ns.db.fontSize + 2) * math.max(1, shown))
    end

    f:SetScript("OnDragStart", function(self)
        if not ns.db.locked then self.dragged = true; self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        local pos = ns.db[self.key]
        pos.point, pos.x, pos.y = point, x, y
    end)
    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            ns.safe("menu", function() ns.ShowMenu(self) end)
        elseif button == "LeftButton" then
            if self.dragged then self.dragged = nil
            else ns.safe("panel", function() ns.TogglePanel(self.panelTab) end) end
        end
    end)
    f:SetScript("OnLeave", function(self) self.bg:SetShown(ns.db.background); GameTooltip:Hide() end)

    ns.huds[key] = f
    return f
end

function ns.ApplyHudSettings()
    local db = ns.db
    for key, f in pairs(ns.huds) do
        local pos = db[key]
        f:ClearAllPoints()
        f:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
        f:SetScale(db.scale)
        f:SetAlpha(db.alpha)
        local step = db.fontSize + 2
        for i, fs in ipairs(f.lines) do
            ns.SetHudFont(fs)
            fs:ClearAllPoints()
            if f.justify == "LEFT" then fs:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -4 - (i - 1) * step)
            else fs:SetPoint("TOP", f, "TOP", 0, -4 - (i - 1) * step) end
        end
        f.bg:SetColorTexture(0, 0, 0, db.bgAlpha or 0.4)
        f.bg:SetShown(db.background)
    end
    if ns.LayoutFeed then ns.LayoutFeed() end
end

----------------------------------------------------------------------
-- the feed: short lines that fade in under the HUD, stay a few seconds, and
-- fade out. Used for the fight recap and gentle reminders. Never chat spam.
----------------------------------------------------------------------
local FEED_MAX = 3
local feed = { rows = {}, queue = {} }
ns.feed = feed

local function feedAnchor()
    local xp = ns.huds.xp
    if xp and xp:IsShown() then return xp end
    return ns.huds.stats
end

function ns.LayoutFeed()
    local anchor = feedAnchor()
    if not anchor then return end
    local prev
    for i = 1, #feed.rows do
        local row = feed.rows[i]
        row:ClearAllPoints()
        row:SetScale(ns.db.scale)
        ns.SetHudFont(row.text)
        row:SetAlpha(row:IsShown() and row:GetAlpha() or 0)
        if prev then row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -1)
        else row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2) end
        prev = row
    end
end

local function feedRow(i)
    if feed.rows[i] then return feed.rows[i] end
    local row = CreateFrame("Button", nil, UIParent)
    row:SetFrameStrata("LOW")
    row:SetSize(200, 16)
    row:SetAlpha(0)
    row:Hide()
    local text = row:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    text:SetPoint("LEFT", row, "LEFT", 8, 0)
    text:SetJustifyH("LEFT")
    row.text = text
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        -- left click: open the matching report tab; right click: just dismiss
        if button ~= "RightButton" and self.tab then ns.safe("panel", function() ns.OpenPanel(self.tab) end) end
        self.state, self.age = "out", 0
    end)
    feed.rows[i] = row
    ns.LayoutFeed()
    return row
end

local function feedShow(row, entry)
    row.text:SetText(entry.text)
    row:SetWidth(row.text:GetStringWidth() + 16)
    row:SetHeight(ns.db.fontSize + 4)
    row.tab, row.key = entry.tab, entry.key
    row.age, row.hold, row.state = 0, entry.hold or 7, "in"
    row:SetAlpha(0)
    row:Show()
end

-- opts: tab (panel tab opened on click), key (same key replaces the visible line), hold (seconds)
function ns.Feed(text, opts)
    opts = opts or {}
    local entry = { text = text, tab = opts.tab, key = opts.key, hold = opts.hold }
    if entry.key then
        for i = 1, #feed.rows do
            local row = feed.rows[i]
            if row:IsShown() and row.key == entry.key then feedShow(row, entry); row.state = "hold"; row:SetAlpha(1); return end
        end
    end
    for i = 1, FEED_MAX do
        local row = feedRow(i)
        if not row:IsShown() then feedShow(row, entry); return end
    end
    if #feed.queue < 6 then table.insert(feed.queue, entry) end
end

ns.Every(0.05, function(dt)
    for i = 1, #feed.rows do
        local row = feed.rows[i]
        if row:IsShown() then
            row.age = row.age + dt
            if row.state == "in" then
                row:SetAlpha(math.min(1, row.age / 0.35))
                if row.age >= 0.35 then row.state, row.age = "hold", 0 end
            elseif row.state == "hold" then
                if row.age >= row.hold and not row:IsMouseOver() then row.state, row.age = "out", 0 end
            else
                row:SetAlpha(math.max(0, 1 - row.age / 0.8))
                if row.age >= 0.8 then
                    row:Hide()
                    local nextEntry = table.remove(feed.queue, 1)
                    if nextEntry then feedShow(row, nextEntry) end
                end
            end
        end
    end
end, "feed")

-- reminders are rate limited so they stay a whisper: one at a time, spaced out,
-- never in combat, and each key at most once per session unless told otherwise
local lastNudge, nudged = 0, {}
ns.recentNudges = {}               -- kept for the report, so a missed reminder is never lost
function ns.Nudge(key, text, tab, force)
    if not ns.db.nudges and not force then return false end
    if nudged[key] then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local now = GetTime()
    if now - lastNudge < 45 and not force then return false end
    lastNudge, nudged[key] = now, true
    table.insert(ns.recentNudges, { text = text, tab = tab, t = time() })
    if #ns.recentNudges > 12 then table.remove(ns.recentNudges, 1) end
    ns.Feed(text, { tab = tab, key = key, hold = ns.db.nudgeHold or 25 })
    if ns.PanelDirty then ns.PanelDirty() end
    return true
end

----------------------------------------------------------------------
-- time bookkeeping shared by modules (not counted while AFK)
----------------------------------------------------------------------
ns.Every(1, function(dt)
    if not ns.session or not ns.char then return end
    if UnitIsAFK and ns.B(UnitIsAFK("player")) then return end
    ns.session.active = (ns.session.active or 0) + dt
    ns.session.combat.active = (ns.session.combat.active or 0) + dt
    ns.char.combat.active = (ns.char.combat.active or 0) + dt
    ns.char.active = (ns.char.active or 0) + dt
end, "core:active")

----------------------------------------------------------------------
-- diagnostics: compact dumps of real API answers, kept in DearLordStatsDB.diag so
-- behaviour on this beta client can be checked from disk without another probe
----------------------------------------------------------------------
function ns.dump(v, depth, budget)
    depth, budget = depth or 0, budget or { n = 0 }
    if v ~= nil and issecret(v) then return "<secret>" end
    local t = type(v)
    if t == "table" then
        if depth >= 4 then return "{...}" end
        local out, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1; budget.n = budget.n + 1
            if n > 30 or budget.n > 260 then out[#out + 1] = "..."; break end
            out[#out + 1] = tostring(k) .. "=" .. ns.dump(val, depth + 1, budget)
        end
        return "{" .. table.concat(out, ", ") .. "}"
    elseif t == "string" then return '"' .. v:sub(1, 60) .. '"'
    elseif t == "function" then return "<fn>"
    else return tostring(v) end
end
function ns.diagOnce(key, producer)
    local d = ns.db and ns.db.diag
    if not d or d[key] ~= nil then return end
    local ok, res = pcall(producer)
    d[key] = ok and res or ("error: " .. tostring(res))
end
