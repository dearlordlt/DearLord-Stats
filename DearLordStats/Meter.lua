-- DearLord Stats : damage meter
-- One window, two columns (the second can be switched off), each showing one view: damage, healing,
-- damage taken, interrupts and so on. Fight shows the fight running now (or the last one), Total
-- everything since the last reset. The numbers come from the game's own meter, C_DamageMeter: the
-- combat log is forbidden to addons on this client.
-- During a fight the game hides those numbers from addons. They still reach the screen, because the
-- game's own status bars and font strings accept them, and the game hands the players over already
-- sorted. What needs arithmetic (share in percent, our own sorting, the text for chat) appears when
-- the fight ends and the numbers become readable.
local ADDON, ns = ...
local N, S, T, B = ns.N, ns.S, ns.T, ns.B

local DM = C_DamageMeter
local TYPE = (Enum and Enum.DamageMeterType) or {}
local STYPE = (Enum and Enum.DamageMeterSessionType) or {}
local OVERALL, CURRENT = STYPE.Overall or 0, STYPE.Current or 1

local VIEWS = {
    { key = "damage", name = "Damage", kind = "DamageDone" },
    { key = "healing", name = "Healing", kind = "HealingDone" },
    { key = "taken", name = "Damage taken", kind = "DamageTaken" },
    { key = "absorbs", name = "Absorbs", kind = "Absorbs" },
    { key = "interrupts", name = "Interrupts", kind = "Interrupts", count = true },
    { key = "dispels", name = "Dispels", kind = "Dispels", count = true },
    { key = "deaths", name = "Deaths", kind = "Deaths", count = true },
    { key = "enemies", name = "Enemies", kind = "EnemyDamageTaken", enemies = true },
}
local VIEW = {}
for _, v in ipairs(VIEWS) do VIEW[v.key] = v end
ns.METER_VIEWS = VIEWS
ns.METER_NUMBERS = { { key = "all", name = "amount, per second, share" }, { key = "amount", name = "amount and per second" }, { key = "rate", name = "per second only" } }

local state = { seg = "fight", scroll = 0, demoUntil = 0, visible = 5, events = 0, settleUntil = 0, idleAt = 0, dirty = true }
ns.meter = state

local function inCombat() return B(UnitAffectingCombat and UnitAffectingCombat("player")) or false end
local function available()
    return DM ~= nil and TYPE.DamageDone ~= nil and (DM.GetCombatSessionFromType ~= nil or DM.GetCombatSessionFromID ~= nil)
end
ns.MeterAvailable = available
local function viewOn(v) return TYPE[v.kind] ~= nil end

local function diag()
    local d = ns.db and ns.db.diag
    if not d then return {} end
    if type(d.meter) ~= "table" or d.meter.version ~= ns.version then
        d.meter = { version = ns.version, events = 0, liveDraws = 0, readDraws = 0 }
    end
    return d.meter
end

local function clock(sec)
    sec = math.floor(sec + 0.5)
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end
local function rateText(n)
    if n >= 10000 then return ns.shortNumber(n) .. "/s" end
    return string.format("%.1f/s", n)
end

----------------------------------------------------------------------
-- reading the game's meter
----------------------------------------------------------------------
local function sessions()
    if not (DM and DM.GetAvailableCombatSessions) then return {} end
    local ok, list = pcall(DM.GetAvailableCombatSessions)
    return ok and T(list) or {}
end
local function lastEntry()
    local list = sessions()
    return list[#list], list
end

-- Fight means the fight running now, or the last one. If the game's "current" session is empty once
-- a fight is over, the last finished fight is read by its id instead.
local function resolve()
    state.use = state.seg
    if state.seg ~= "fight" or inCombat() or not (DM and DM.GetCombatSessionFromType and DM.GetCombatSessionFromID) then return end
    local ok, s = pcall(DM.GetCombatSessionFromType, CURRENT, TYPE.DamageDone)
    local src = ok and T(s) and T(s.combatSources)
    if src and #src > 0 then return end
    local e = lastEntry()
    local id = e and N(e.sessionID)
    if id then state.use = id; diag().fightById = true end
end

local function fetchSession(kind, seg)
    if not DM or kind == nil then return nil end
    seg = seg or state.use or state.seg
    local ok, s
    if type(seg) == "number" then
        if DM.GetCombatSessionFromID then ok, s = pcall(DM.GetCombatSessionFromID, seg, kind) end
    elseif DM.GetCombatSessionFromType then
        ok, s = pcall(DM.GetCombatSessionFromType, seg == "total" and OVERALL or CURRENT, kind)
    elseif seg == "fight" and DM.GetCombatSessionFromID then
        local e = lastEntry()
        local id = e and N(e.sessionID)
        if id then ok, s = pcall(DM.GetCombatSessionFromID, id, kind) end
    end
    return ok and T(s) or nil
end
local function fetchSource(kind, guid, creatureID, seg)
    if not DM or kind == nil then return nil end
    seg = seg or state.use or state.seg
    local ok, s
    if type(seg) == "number" then
        if DM.GetCombatSessionSourceFromID then ok, s = pcall(DM.GetCombatSessionSourceFromID, seg, kind, guid, creatureID) end
    elseif DM.GetCombatSessionSourceFromType then
        ok, s = pcall(DM.GetCombatSessionSourceFromType, seg == "total" and OVERALL or CURRENT, kind, guid, creatureID)
    elseif seg == "fight" and DM.GetCombatSessionSourceFromID then
        local e = lastEntry()
        local id = e and N(e.sessionID)
        if id then ok, s = pcall(DM.GetCombatSessionSourceFromID, id, kind, guid, creatureID) end
    end
    return ok and T(s) or nil, ok
end

local function durationOf(seg, sess)
    seg = seg or state.use or state.seg
    if type(seg) ~= "number" and DM and DM.GetSessionDurationSeconds then
        local ok, d = pcall(DM.GetSessionDurationSeconds, seg == "total" and OVERALL or CURRENT)
        if ok and ns.exists(d) then return d end
    end
    if sess and ns.exists(sess.durationSeconds) then return sess.durationSeconds end
    if seg ~= "total" then
        local e, list = lastEntry()
        if type(seg) == "number" then
            e = nil
            for _, x in ipairs(list) do if N(x.sessionID) == seg then e = x end end
        end
        if e and ns.exists(e.durationSeconds) then return e.durationSeconds end
    end
end

-- colour of a source: its class when that is readable; a hidden class name is handed to the game's own colour table
local function colorOf(src, enemies)
    if enemies then return 0.78, 0.36, 0.30 end
    local class = S(src.classFilename)
    if class and class ~= "" then return ns.CensusClassColor(class) end
    if class == nil and ns.exists(src.classFilename) and C_ClassColor and C_ClassColor.GetClassColor then
        local ok, c = pcall(C_ClassColor.GetClassColor, src.classFilename)
        c = ok and T(c)
        if c and c.GetRGB then
            local ok2, r, g, b = pcall(c.GetRGB, c)
            if ok2 and ns.exists(r) then diag().classColor = "hidden class coloured by the game"; return r, g, b end
        end
        diag().classColor = "hidden class: no colour"
    end
    if class == "" then return 0.62, 0.58, 0.50 end              -- a pet, a totem, a creature
    return 0.45, 0.6, 0.85
end

-- what a fight lets an addon see, noted once alone and once in a group
local function probeLive(sources)
    local d = diag()
    local key = ((IsInGroup and B(IsInGroup())) or (IsInRaid and B(IsInRaid()))) and "liveGroup" or "liveSolo"
    if d[key] then return end
    local src = sources[1]
    if not src then return end
    local function how(v) if v == nil then return "nil" end if type(issecretvalue) == "function" and issecretvalue(v) then return "hidden" end return "plain" end
    d[key] = string.format("sources=%d name=%s class=%s own=%s guid=%s amount=%s rate=%s creature=%s", #sources, how(src.name), how(src.classFilename),
        how(src.isLocalPlayer), how(src.sourceGUID), how(src.totalAmount), how(src.amountPerSecond), how(src.sourceCreatureID))
end

-- one column's data: items in the order to show them, readable or not
local function readColumn(view, seg)
    local kind = TYPE[view.kind]
    local out = { view = view, items = {}, readable = true }
    local sess = fetchSession(kind, seg)
    if not sess then out.none = true; return out end
    local sources = T(sess.combatSources)
    if not sources then
        if ns.exists(sess.combatSources) then out.locked = true; diag().sourcesHidden = true end
        return out
    end
    out.duration = durationOf(seg, sess)
    local total, top, seen = 0, 0, {}
    for i, src in ipairs(sources) do
        src = T(src)
        if src then
            local it = { index = i, name = src.name, guid = src.sourceGUID, creatureID = src.sourceCreatureID, class = S(src.classFilename),
                own = B(src.isLocalPlayer) == true, value = src.totalAmount, rate = src.amountPerSecond,
                amount = N(src.totalAmount), perSec = N(src.amountPerSecond), plainName = S(src.name) }
            it.r, it.g, it.b = colorOf(src, view.enemies)
            it.creature = view.enemies or (it.class == "" and N(src.sourceCreatureID) ~= nil and N(src.sourceCreatureID) ~= 0)
            local key = S(src.sourceGUID) or (N(src.sourceCreatureID) and it.plainName and (it.plainName .. ":" .. src.sourceCreatureID)) or it.plainName
            if key then
                if seen[key] then key = key .. "#" .. i end
                seen[key] = true
                it.key = key
            end
            if it.amount then
                total = total + it.amount
                if it.amount > top then top = it.amount end
            elseif ns.exists(src.totalAmount) then out.readable = false end
            out.items[#out.items + 1] = it
        end
    end
    if out.readable then
        table.sort(out.items, function(a, b)
            if (a.amount or 0) ~= (b.amount or 0) then return (a.amount or 0) > (b.amount or 0) end
            return a.index < b.index
        end)
        out.total, out.max = total, top
        local dur = N(out.duration)
        if dur and dur > 0 then out.rate = total / dur end
        for i, it in ipairs(out.items) do
            it.rank = i
            it.share = total > 0 and (it.amount or 0) / total or nil
        end
    else
        -- hidden: keep the game's order, scale against the game's own largest value
        out.total = sess.totalAmount
        if ns.exists(sess.maxAmount) then out.max = sess.maxAmount elseif out.items[1] then out.max = out.items[1].value end
        for i, it in ipairs(out.items) do it.rank = i; it.key = nil end
        probeLive(sources)
    end
    return out
end

----------------------------------------------------------------------
-- a preview with made-up players, to place the window and see it move
----------------------------------------------------------------------
local DEMO = {
    damage = { { "Raven", "HUNTER", 46, true }, { "Borkh", "WARRIOR", 39 }, { "Frosty", "MAGE", 52 }, { "Stabs", "ROGUE", 44 }, { "Moonleaf", "DRUID", 12 }, { "Joy", "", 17 } },
    healing = { { "Moonleaf", "DRUID", 31 }, { "Lightwell", "PRIEST", 24 }, { "Raven", "HUNTER", 3, true } },
    other = { { "Borkh", "WARRIOR", 30 }, { "Raven", "HUNTER", 9, true }, { "Stabs", "ROGUE", 6 } },
}
local demo = { t0 = 0, sums = {} }
local function demoColumn(view)
    local set = DEMO[view.key] or DEMO.other
    local out = { view = view, items = {}, readable = true, demo = true }
    local elapsed = math.max(1, GetTime() - demo.t0)
    local sums = demo.sums[view.key] or {}
    demo.sums[view.key] = sums
    local total, top = 0, 0
    for i, p in ipairs(set) do
        -- uneven bursts, so the bars overtake each other
        local burst = 0.6 + 0.8 * math.abs(math.sin(elapsed * (0.35 + i * 0.13) + i))
        sums[i] = (sums[i] or 0) + p[3] * burst * 0.25 * (view.count and 0.02 or 1)
        local amount = view.count and math.floor(sums[i] + 1) or math.floor(sums[i])
        local it = { index = i, name = p[1], plainName = p[1], class = p[2], own = p[4] == true, value = amount, amount = amount,
            rate = amount / elapsed, perSec = amount / elapsed, key = "demo:" .. p[1] }
        if p[2] == "" then it.r, it.g, it.b = 0.62, 0.58, 0.50 else it.r, it.g, it.b = ns.CensusClassColor(p[2]) end
        if view.enemies then it.r, it.g, it.b = 0.78, 0.36, 0.30 end
        total = total + amount
        if amount > top then top = amount end
        out.items[#out.items + 1] = it
    end
    table.sort(out.items, function(a, b) if a.amount ~= b.amount then return a.amount > b.amount end return a.index < b.index end)
    for i, it in ipairs(out.items) do it.rank = i; it.share = total > 0 and it.amount / total or nil end
    out.total, out.max, out.duration, out.rate = total, top, elapsed, total / elapsed
    return out
end

----------------------------------------------------------------------
-- the window
----------------------------------------------------------------------
local mw = ns.CreateHud("meter", 0, "LEFT")
mw.panelTab = "combat"
mw:Hide()
ns.Chrome(mw, 20)
if mw.EnableMouseWheel then mw:EnableMouseWheel(true) end

local cols = {}
local refresh, showTip, hideTip

local function setSeg(seg)
    state.seg, state.scroll, state.dirty = seg, 0, true
    refresh()
end

local function fightsMenu(owner)
    local items = {}
    local list = sessions()
    for i = #list, math.max(1, #list - 14), -1 do
        local e = T(list[i])
        local id = e and N(e.sessionID)
        if id then
            local name, dur = S(e.name), N(e.durationSeconds)
            local label = ((name and name ~= "") and name or ("fight " .. id)) .. (dur and ("  " .. clock(dur)) or "")
            items[#items + 1] = { text = label, fn = function() setSeg(id) end }
        end
    end
    if #items == 0 then items[1] = { title = inCombat() and "the list opens when the fight ends" or "no fight recorded yet" } end
    ns.PopMenu(owner, "Earlier fights", items)
end

local tabFight = ns.TextButton(mw, "Fight", function(self, button)
    if button == "RightButton" then fightsMenu(self) else setSeg("fight") end
end, "The fight running now, or the last one. Right-click: earlier fights.")
local tabTotal = ns.TextButton(mw, "Total", function() setSeg("total") end,
    function() return (ns.db.meterResetLogin ~= false) and "Everything since you logged in, or since the last reset." or "Everything since the last reset." end)
local titleName = ns.BarText(mw)
local titleTime = ns.BarText(mw, "RIGHT")
titleName:SetTextColor(0.80, 0.83, 0.88); titleTime:SetTextColor(0.62, 0.66, 0.72)

local btnClose = ns.TextButton(mw, "×", function()
    ns.db.showMeter = false
    refresh()
    ns.say("damage meter hidden. /dls meter brings it back.")
end, "Hide the meter (/dls meter brings it back).")
local btnCols = ns.TextButton(mw, "cols", function()
    ns.db.meterSecond = not (ns.db.meterSecond ~= false)
    mw:Layout()
end, "Show or hide the second column.")
local btnReset = ns.TextButton(mw, "reset", function() ns.MeterReset() end, "Clear the game's damage meter: Total and the earlier fights start over.")
local btnCopy = ns.TextButton(mw, "copy", function(self) ns.MeterCopyMenu(self) end, "Send what the meter shows to chat, or open it as text to copy.")

local divider = mw:CreateTexture(nil, "ARTWORK")
divider:SetColorTexture(1, 1, 1, 0.07)

local function viewMenu(c)
    local items = {}
    for _, v in ipairs(VIEWS) do
        if viewOn(v) or state.demoUntil > GetTime() then
            items[#items + 1] = { text = v.name, checked = function() return c.view == v end, fn = function()
                c.view = v
                ns.db[c.index == 1 and "meterViewL" or "meterViewR"] = v.key
                state.scroll = 0
                mw:Layout()
            end }
        end
    end
    ns.PopMenu(c.head, "This column shows", items)
end

local function newColumn(index)
    local c = { index = index }
    c.head = ns.TextButton(mw, "Damage", function() viewMenu(c) end, "Click: choose what this column shows.")
    c.head.dim = { 0.74, 0.82, 0.96 }
    c.head:SetOn(false)
    c.sum = ns.BarText(mw, "RIGHT")
    c.sum:SetTextColor(0.72, 0.76, 0.82)
    c.list = ns.BarList(mw, mw)
    c.empty = ns.BarText(mw, "CENTER")
    c.empty:SetTextColor(0.55, 0.58, 0.64)
    c.list.onEnter = function(it, row) showTip(c, it, row) end
    c.list.onLeave = function() hideTip() end
    c.list.onClick = function(_, button) if button == "RightButton" then ns.safe("menu", function() ns.ShowMenu(mw) end) end end
    cols[index] = c
    return c
end
newColumn(1); newColumn(2)

mw:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then ns.safe("menu", function() ns.ShowMenu(self) end) end
    self.dragged = nil
end)
mw:SetScript("OnMouseWheel", function(_, delta)
    local most = 0
    for _, c in ipairs(cols) do if c.shown and c.data then most = math.max(most, #c.data.items) end end
    state.scroll = math.max(0, math.min(math.max(0, most - state.visible), state.scroll - (N(delta) or 0)))
    state.dirty = true
    refresh()
end)

-- which numbers a bar carries, and how wide each one is
local function cellSpec(view, colW, fsz)
    local mode = ns.db.meterNumbers or "all"
    local spec = {}
    if view.count then spec = { "amount" }
    elseif mode == "rate" then spec = { "rate" }
    elseif mode == "amount" then spec = { "amount", "rate" }
    else spec = { "amount", "rate", "pct" } end
    local widths = { amount = fsz * 3.0, rate = fsz * 3.9, pct = fsz * 2.4 }
    -- a narrow column drops numbers rather than the name: the share first, then the amount
    local function need() local w = fsz * 6; for _, k in ipairs(spec) do w = w + widths[k] + 4 end return w end
    while #spec > 1 and need() > colW do
        local drop = 1
        for i, k in ipairs(spec) do if k == "pct" then drop = i end end
        table.remove(spec, drop)
    end
    local cw = {}
    for i, k in ipairs(spec) do cw[i] = math.floor(widths[k]) end
    return spec, cw
end

function mw:Layout()
    local db = ns.db
    if not db then return end
    local fsz = db.fontSize or 13
    local pad, gap = 5, 2
    local headH, colHeadH = fsz + 8, fsz + 5
    local barH = math.max(10, db.meterBarHeight or 18)
    self:ApplyChrome(headH)
    if not self.sizing then self:ApplySize(520, 158) end
    local W, H = N(self:GetWidth()) or 520, N(self:GetHeight()) or 158
    local second = db.meterSecond ~= false

    -- title strip: tabs on the left, buttons on the right, the fight's name between them
    local x = pad
    for _, b in ipairs({ tabFight, tabTotal }) do
        local w = b:Fit(-1, headH)
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", self, "TOPLEFT", x, 0)
        x = x + w + 2
    end
    local right = pad - 2
    btnCols:SetLabel(second and "1 col" or "2 col")
    for _, b in ipairs({ btnClose, btnCols, btnReset, btnCopy }) do
        local w = b:Fit(b == btnClose and 2 or -2, headH)
        b:ClearAllPoints(); b:SetPoint("TOPRIGHT", self, "TOPRIGHT", -right, 0)
        right = right + w + 1
    end
    ns.BarFont(titleName, -1); ns.BarFont(titleTime, -2)
    local room = W - x - right - 8
    local timeW = fsz * 3
    titleTime:ClearAllPoints(); titleTime:SetPoint("TOPRIGHT", self, "TOPRIGHT", -right - 4, -(headH - fsz) / 2)
    titleTime:SetWidth(timeW); titleTime:SetShown(room > timeW + 30)
    titleName:ClearAllPoints(); titleName:SetPoint("TOPLEFT", self, "TOPLEFT", x + 6, -(headH - fsz) / 2 + 1)
    titleName:SetWidth(math.max(1, room - (titleTime:IsShown() and timeW + 6 or 0))); titleName:SetShown(room > 40)

    local colW = second and math.floor((W - pad * 2 - 7) / 2) or (W - pad * 2)
    local top = headH + 2
    local areaH = math.max(barH, H - top - colHeadH - pad)
    state.visible = math.max(1, math.floor((areaH + gap) / (barH + gap)))
    divider:ClearAllPoints()
    divider:SetPoint("TOPLEFT", self, "TOPLEFT", pad + colW + 3, -top - 2); divider:SetSize(1, math.max(1, H - top - pad - 2))
    divider:SetShown(second)
    for i, c in ipairs(cols) do
        local on = i == 1 or second
        c.shown = on
        c.view = VIEW[db[i == 1 and "meterViewL" or "meterViewR"]] or VIEW[i == 1 and "damage" or "healing"]
        local cx = pad + (i - 1) * (colW + 7)
        c.head:SetShown(on); c.sum:SetShown(on); c.list.frame:SetShown(on); c.empty:SetShown(false)
        if on then
            c.head:SetLabel(c.view.name)
            c.head:Fit(-1, colHeadH)
            c.head:ClearAllPoints(); c.head:SetPoint("TOPLEFT", self, "TOPLEFT", cx, -top)
            ns.BarFont(c.sum, -2)
            c.sum:ClearAllPoints(); c.sum:SetPoint("TOPRIGHT", self, "TOPLEFT", cx + colW - 2, -top - (colHeadH - fsz) / 2)
            c.sum:SetWidth(math.max(1, colW - (N(c.head:GetWidth()) or 60) - 6))
            c.list.frame:ClearAllPoints(); c.list.frame:SetPoint("TOPLEFT", self, "TOPLEFT", cx, -top - colHeadH)
            c.list.frame:SetSize(colW, areaH)
            ns.BarFont(c.empty, -2)
            c.empty:ClearAllPoints(); c.empty:SetPoint("TOP", c.list.frame, "TOP", 0, -6); c.empty:SetWidth(colW - 8)
            c.spec, c.cellW = cellSpec(c.view, colW, fsz)
            c.list:Layout(colW, barH, gap, c.cellW, fsz * 1.5)
        end
    end
    state.dirty = true
    if refresh then refresh() end
end
function mw:Fit() self:Layout() end

ns.MakeResizable(mw, "meterW", "meterH", 150, 64, function() mw:Layout() end)
mw.cols, mw.tabFight, mw.tabTotal, mw.titleName, mw.titleTime = cols, tabFight, tabTotal, titleName, titleTime
mw.buttons = { copy = btnCopy, reset = btnReset, cols = btnCols, close = btnClose }

----------------------------------------------------------------------
-- drawing
----------------------------------------------------------------------
-- the game's own number shortening, told to write numbers the way ns.shortNumber does (12.3k, 1.2m),
-- so a bar reads the same during a fight (hidden, shortened by the game) and after it
local abbrev
local function abbrevOptions()
    if abbrev == nil then
        abbrev = false
        if CreateAbbreviateConfig then
            local ok, cfg = pcall(CreateAbbreviateConfig, {
                { breakpoint = 1000000, abbreviation = "m", significandDivisor = 100000, fractionDivisor = 10, abbreviationIsGlobal = false },
                { breakpoint = 10000, abbreviation = "k", significandDivisor = 100, fractionDivisor = 10, abbreviationIsGlobal = false },
                { breakpoint = 0.000001, abbreviation = "", significandDivisor = 1, fractionDivisor = 1, abbreviationIsGlobal = false },
            })
            if ok and cfg ~= nil then abbrev = { config = cfg } end
        end
    end
    return abbrev or nil
end
local function shorten(v)
    if not AbbreviateNumbers then return nil end
    local ok, s = pcall(AbbreviateNumbers, v, abbrevOptions())
    if ok and ns.exists(s) then return s end
    ok, s = pcall(AbbreviateNumbers, v)
    if ok and ns.exists(s) then return s end
    return nil
end
local function amountCell(v)
    local n = N(v)
    if n then return { text = ns.shortNumber(n) } end
    if not ns.exists(v) then return { text = "" } end
    local s = shorten(v)
    if ns.exists(s) then return { text = s } end
    return { fmt = "%.0f", arg = v }
end
local function rateCell(v)
    local n = N(v)
    if n then return { text = rateText(n) } end
    if not ns.exists(v) then return { text = "" } end
    return { fmt = "%.1f/s", arg = v }
end

local function barOf(c, it, data)
    local bar = { src = it, key = it.key, rank = it.rank, name = it.name, class = it.class, r = it.r, g = it.g, b = it.b,
        value = it.value, max = data.max, own = it.own, cells = {} }
    if it.creature or it.class == "" then
        bar.fallbackIcon = c.view.enemies and "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" or "Interface\\Icons\\Ability_Hunter_Pet_Wolf"
        bar.class = nil
    end
    for i, k in ipairs(c.spec or {}) do
        if k == "amount" then bar.cells[i] = amountCell(it.value)
        elseif k == "rate" then bar.cells[i] = rateCell(it.rate)
        elseif k == "pct" then bar.cells[i] = { text = it.share and string.format("%d%%", math.floor(it.share * 100 + 0.5)) or "" } end
    end
    return bar
end

local function drawColumn(c, isDemo)
    local ok, data = pcall(isDemo and demoColumn or readColumn, c.view)
    if not ok then                                              -- something in the game's table could not be touched
        diag().readError = tostring(data):sub(1, 160)
        data = { view = c.view, items = {}, readable = true, locked = true }
    end
    c.data = data
    local items = data.items
    local visible, from = state.visible, math.min(state.scroll, math.max(0, #items - state.visible))
    local bars = {}
    for i = from + 1, math.min(#items, from + visible) do bars[#bars + 1] = barOf(c, items[i], data) end
    if data.readable and #items > from + visible then              -- your own row stays in view
        for i = from + visible + 1, #items do
            if items[i].own then bars[#bars] = barOf(c, items[i], data); break end
        end
    end
    c.list:SetLive((isDemo or inCombat()) and #bars > 0)
    c.list:SetData(bars)
    local msg
    if #bars == 0 then
        if data.locked then msg = "hidden by the game during this fight"
        elseif state.seg == "fight" and not inCombat() and data.none then msg = "no fight yet"
        else msg = "nothing " .. (state.seg == "total" and "yet" or "in this fight") end
    end
    if msg then c.empty:SetText(msg); c.empty:Show() else c.empty:Hide() end
    -- the column's sum: amount and per second for the whole group
    local total = N(data.total)
    if #bars == 0 then c.sum:SetText("")
    elseif total then
        c.sum:SetText(ns.shortNumber(total) .. ((data.rate and not c.view.count) and ("   " .. rateText(data.rate)) or ""))
    elseif ns.exists(data.total) then ns.BarSetText(c.sum, shorten(data.total))
    else c.sum:SetText("") end
    local d = diag()
    if #bars > 0 and not isDemo then
        if data.readable then d.readDraws = (d.readDraws or 0) + 1 else d.liveDraws = (d.liveDraws or 0) + 1 end
    end
end

local function segLabel(isDemo)
    if isDemo then return "preview", GetTime() - demo.t0 end
    local seg = state.seg
    if seg == "total" then
        return (ns.db.meterResetLogin ~= false) and "this session" or "since reset", durationOf("total")
    end
    local e, list = lastEntry()
    if type(seg) == "number" then
        e = nil
        for _, x in ipairs(list) do if T(x) and N(x.sessionID) == seg then e = x end end
        if e and ns.exists(e.name) then return e.name, durationOf(seg) end
        return "fight " .. seg, durationOf(seg)
    end
    e = T(e)
    if e and ns.exists(e.name) then return e.name, durationOf(state.use or "fight") end
    return nil, durationOf(state.use or "fight")
end

local function drawTitle(isDemo)
    tabFight:SetOn(state.seg ~= "total"); tabTotal:SetOn(state.seg == "total")
    tabFight:SetLabel(type(state.seg) == "number" and "Fight*" or "Fight")
    local name, dur = segLabel(isDemo)
    state.segName, state.segDuration = S(name), N(dur)
    -- the fight's name may be hidden: it is only looked at when it is readable
    if not ns.exists(name) or state.segName == "" then titleName:SetText(inCombat() and "in a fight" or "") else ns.BarSetText(titleName, name) end
    local d = N(dur)
    if d then titleTime:SetText(clock(d))
    elseif ns.exists(dur) then
        if not pcall(titleTime.SetFormattedText, titleTime, "%.0fs", dur) then titleTime:SetText("") end
    else titleTime:SetText("") end
end

refresh = function()
    local db = ns.db
    if not db then return end
    local now = GetTime()
    local isDemo = state.demoUntil > now
    if state.wasDemo and not isDemo then state.wasDemo = false; state.dirty = true end
    if db.showMeter == false and not isDemo then mw:Hide(); if hideTip then hideTip() end; return end
    if not isDemo and not available() then mw:Hide(); return end
    local fighting = inCombat()
    if fighting then state.idleAt = now + 20 end
    if db.meterHideIdle and not isDemo and not fighting and now > state.idleAt then mw:Hide(); if hideTip then hideTip() end; return end
    if not mw:IsShown() then mw:Show() end
    resolve()
    for _, c in ipairs(cols) do if c.shown then drawColumn(c, isDemo) end end
    drawTitle(isDemo)
    state.dirty, state.lastDraw, state.wasDemo = false, now, isDemo
end
ns.RefreshMeter = refresh

----------------------------------------------------------------------
-- the breakdown: every ability of the player under the pointer
----------------------------------------------------------------------
local tip
local TIP_ROWS = 14
local function buildTip()
    local f = CreateFrame("Frame", "DearLordStatsMeterTip", UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    ns.Chrome(f, 20)
    f.title = ns.BarText(f)
    f.sub = ns.BarText(f, "RIGHT")
    f.sub:SetTextColor(0.62, 0.66, 0.72)
    f.list = ns.BarList(f)
    f.list.instant = false
    f.note = ns.BarText(f)
    f.note:SetTextColor(0.72, 0.76, 0.82)
    if f.note.SetWordWrap then f.note:SetWordWrap(true) end
    f.targetsHead = ns.BarText(f)
    f.targetsHead:SetTextColor(0.74, 0.82, 0.96)
    f.targets = {}
    for i = 1, 5 do
        f.targets[i] = { name = ns.BarText(f), value = ns.BarText(f, "RIGHT") }
        f.targets[i].value:SetTextColor(0.86, 0.88, 0.92)
    end
    f:Hide()
    return f
end

local function spellIcon(id)
    if not (ns.exists(id) and C_Spell and C_Spell.GetSpellTexture) then return nil end
    local ok, tex = pcall(C_Spell.GetSpellTexture, id)
    if ok and ns.exists(tex) then return tex end
end
local function spellLabel(id)
    local name = ns.spellName(id)
    if name then return name, true end
    if ns.exists(id) and C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and ns.exists(n) then return n, false end
    end
    return nil, false
end

-- the abilities behind one bar: the player's (with pets and totems), or everything that hit an enemy
local function readSpells(c, it)
    local view = c.view
    local kind = TYPE[view.kind]
    local guid, cid = it.guid, nil
    local hiddenGuid = false
    if it.creature then guid, cid = nil, N(it.creatureID)
    elseif it.own and UnitGUID then guid = UnitGUID("player")
    elseif not S(guid) then hiddenGuid = ns.exists(guid) end
    if not ns.exists(guid) and cid == nil then return nil, "none" end
    local detail = fetchSource(kind, guid, cid)
    local spells = detail and T(detail.combatSpells)
    if hiddenGuid then diag().hiddenGuid = (spells and #spells > 0) and "accepted" or (detail and "empty" or "refused") end
    if not spells then return nil, hiddenGuid and "hidden" or "none" end
    local out = { items = {}, readable = true }
    local total, top = 0, 0
    for i, sp in ipairs(spells) do
        sp = T(sp)
        if sp then
            local name, plain = spellLabel(sp.spellID)
            if not ns.exists(name) then name, plain = "?", true end
            local details = T(sp.combatSpellDetails)
            local creature = sp.creatureName
            local who = S(creature)
            local unitName = details and S(details.unitName)
            local item = { index = i, name = name, icon = spellIcon(sp.spellID), value = sp.totalAmount, rate = sp.amountPerSecond,
                amount = N(sp.totalAmount), perSec = N(sp.amountPerSecond) }
            local pet = (details and B(details.isPet)) or (who ~= nil and who ~= "")
            if who and who ~= "" and plain and who == name then       -- a totem's own spell carries the totem's name twice
            elseif who and who ~= "" then
                if plain then item.name = name .. " (" .. who .. ")" else item.nameFmt, item.nameArgs = "%s (%s)", { name, who } end
            elseif who == nil and ns.exists(creature) then
                item.nameFmt, item.nameArgs = "%s  |cffb0b8c4%s|r", { name, creature }            -- a hidden pet or totem name, written by the game
            elseif (view.enemies or it.creature) and unitName and unitName ~= "" then
                if plain then item.name = name .. " (" .. unitName .. ")" else item.nameFmt, item.nameArgs = "%s (%s)", { name, unitName } end
            end
            if pet then item.r, item.g, item.b = 0.62, 0.58, 0.50 else item.r, item.g, item.b = it.r, it.g, it.b end
            item.key = (plain and item.name or nil)
            if item.amount then
                total = total + item.amount
                if item.amount > top then top = item.amount end
            elseif ns.exists(sp.totalAmount) then out.readable = false end
            out.items[#out.items + 1] = item
        end
    end
    if out.readable then
        table.sort(out.items, function(a, b) if a.amount ~= b.amount then return (a.amount or 0) > (b.amount or 0) end return a.index < b.index end)
        out.total, out.max = total, top
        local seen = {}
        for i, item in ipairs(out.items) do
            item.share = total > 0 and (item.amount or 0) / total or nil
            if item.key then if seen[item.key] then item.key = item.key .. "#" .. i end; seen[item.key] = true end
        end
    else
        if ns.exists(detail.maxAmount) then out.max = detail.maxAmount elseif out.items[1] then out.max = out.items[1].value end
        for _, item in ipairs(out.items) do item.key = nil end
    end
    return out
end

-- who a player hit: the enemies' damage taken, counted where the game names that player as the one who dealt it
local targetCache = {}
local function readTargets(it)
    local name = it.plainName
    if not name or TYPE.EnemyDamageTaken == nil then return nil end
    local key = tostring(state.seg) .. ":" .. name
    local hit = targetCache[key]
    if hit and GetTime() - hit.at < 1.5 then return hit.list end
    local list = {}
    local es = fetchSession(TYPE.EnemyDamageTaken)
    local sources = es and T(es.combatSources) or {}
    for i = 1, math.min(#sources, 12) do
        local src = T(sources[i])
        local cid, mob = src and N(src.sourceCreatureID), src and S(src.name)
        if cid and mob then
            local d = fetchSource(TYPE.EnemyDamageTaken, nil, cid)
            local sum = 0
            for _, sp in ipairs(d and T(d.combatSpells) or {}) do
                local details = T(sp) and T(sp.combatSpellDetails)
                local amount = N(sp.totalAmount)
                if details and amount and S(details.unitName) == name then sum = sum + amount end
            end
            if sum > 0 then list[#list + 1] = { name = mob, amount = sum } end
        end
    end
    table.sort(list, function(a, b) return a.amount > b.amount end)
    targetCache[key] = { at = GetTime(), list = list }
    return list
end

local function drawTip()
    if not (tip and tip.col and tip.item) then return end
    local c, it = tip.col, tip.item
    local fsz = ns.db.fontSize or 13
    local pad, W = 6, math.max(240, fsz * 22)
    local headH = fsz + 8
    tip:ApplyChrome(headH)
    ns.BarFont(tip.title, -1); ns.BarFont(tip.sub, -2); ns.BarFont(tip.note, -2); ns.BarFont(tip.targetsHead, -2)
    tip.title:ClearAllPoints(); tip.title:SetPoint("TOPLEFT", tip, "TOPLEFT", pad, -(headH - fsz) / 2 + 1); tip.title:SetWidth(W * 0.55)
    tip.sub:ClearAllPoints(); tip.sub:SetPoint("TOPRIGHT", tip, "TOPRIGHT", -pad, -(headH - fsz) / 2); tip.sub:SetWidth(W * 0.4)
    ns.BarSetText(tip.title, it.name)
    if not (ns.exists(it.r) and pcall(tip.title.SetTextColor, tip.title, it.r, it.g, it.b)) then tip.title:SetTextColor(1, 1, 1) end
    tip.sub:SetText(c.view.name .. (state.seg == "total" and ", total" or ""))

    local data, why
    if c.data and c.data.demo then
        data = { items = {}, readable = true, total = it.amount, max = it.amount * 0.5 }
        for i, sp in ipairs({ { "Auto Shot", 0.5 }, { "Aimed Shot", 0.22 }, { "Attack (Joy)", 0.18 }, { "Arcane Shot", 0.10 } }) do
            local a = math.floor(it.amount * sp[2])
            data.items[i] = { key = sp[1], name = sp[1], value = a, amount = a, rate = a / math.max(1, GetTime() - demo.t0), perSec = a / math.max(1, GetTime() - demo.t0),
                share = sp[2], r = i == 3 and 0.62 or it.r, g = i == 3 and 0.58 or it.g, b = i == 3 and 0.50 or it.b }
        end
    else
        local ok
        ok, data, why = pcall(readSpells, c, it)
        if not ok then diag().tipError = tostring(data):sub(1, 160); data, why = nil, "none" end
    end

    local barH = math.max(10, (ns.db.meterBarHeight or 18) - 2)
    local y = headH + 3
    local bars = {}
    if data then
        local spec = c.view.count and { "amount" } or { "amount", "rate", "pct" }
        local cw = { math.floor(fsz * 3.0), math.floor(fsz * 3.9), math.floor(fsz * 2.4) }
        if c.view.count then cw = { cw[1] } end
        tip.list.showIcon = true
        tip.list:Layout(W - pad * 2, barH, 2, cw, 0)
        for i = 1, math.min(#data.items, TIP_ROWS) do
            local sp = data.items[i]
            local bar = { key = sp.key, name = sp.name, nameFmt = sp.nameFmt, nameArgs = sp.nameArgs, icon = sp.icon, fallbackIcon = "Interface\\Icons\\INV_Misc_QuestionMark",
                r = sp.r, g = sp.g, b = sp.b, value = sp.value, max = data.max, cells = {} }
            for k, what in ipairs(spec) do
                if what == "amount" then bar.cells[k] = amountCell(sp.value)
                elseif what == "rate" then bar.cells[k] = rateCell(sp.rate)
                else bar.cells[k] = { text = sp.share and string.format("%d%%", math.floor(sp.share * 100 + 0.5)) or "" } end
            end
            bars[#bars + 1] = bar
        end
    end
    tip.list.instant = tip.fresh
    tip.list:SetData(bars)
    tip.fresh = nil
    tip.list.frame:ClearAllPoints(); tip.list.frame:SetPoint("TOPLEFT", tip, "TOPLEFT", pad, -y)
    tip.list.frame:SetSize(W - pad * 2, tip.list:Height(#bars))
    y = y + (#bars > 0 and (tip.list:Height(#bars) + 4) or 0)

    local note
    if not data then
        if why == "hidden" then note = "The game keeps this player's abilities back until the fight ends."
        else note = "No abilities listed for this one." end
    elseif #data.items > TIP_ROWS then note = "and " .. (#data.items - TIP_ROWS) .. " more"
    elseif #bars == 0 then note = "No abilities listed for this one." end
    if data and not data.readable then note = (note and (note .. "  ") or "") .. "Shares appear when the fight ends." end
    tip.note:ClearAllPoints(); tip.note:SetPoint("TOPLEFT", tip, "TOPLEFT", pad, -y); tip.note:SetWidth(W - pad * 2)
    if note then tip.note:SetText(note); tip.note:Show(); y = y + fsz + 4 else tip.note:Hide() end

    -- who they hit
    local targets = (c.view.key == "damage" and data and data.readable and not (c.data and c.data.demo)) and readTargets(it) or nil
    if c.data and c.data.demo and c.view.key == "damage" then targets = { { name = "Training Dummy", amount = it.amount } } end
    local shown = 0
    if targets and #targets > 0 then
        local sum = 0
        for _, t in ipairs(targets) do sum = sum + t.amount end
        tip.targetsHead:ClearAllPoints(); tip.targetsHead:SetPoint("TOPLEFT", tip, "TOPLEFT", pad, -y - 2)
        tip.targetsHead:SetText("Targets"); tip.targetsHead:Show()
        y = y + fsz + 4
        for i = 1, math.min(#targets, #tip.targets) do
            local row, t = tip.targets[i], targets[i]
            ns.BarFont(row.name, -2); ns.BarFont(row.value, -2)
            row.name:ClearAllPoints(); row.name:SetPoint("TOPLEFT", tip, "TOPLEFT", pad + 4, -y); row.name:SetWidth(W * 0.55)
            row.value:ClearAllPoints(); row.value:SetPoint("TOPRIGHT", tip, "TOPRIGHT", -pad - 4, -y); row.value:SetWidth(W * 0.38)
            row.name:SetText(t.name)
            row.value:SetText(ns.shortNumber(t.amount) .. "   " .. ns.pct(t.amount, sum))
            row.name:Show(); row.value:Show()
            y = y + fsz + 1
            shown = i
        end
    else tip.targetsHead:Hide() end
    for i = shown + 1, #tip.targets do tip.targets[i].name:Hide(); tip.targets[i].value:Hide() end

    tip:SetSize(W, y + pad - 1)
    tip.count = #bars
end

showTip = function(c, bar, row)
    if not (bar and bar.src) then return end
    tip = tip or buildTip()
    ns.meterTip = tip
    tip.col, tip.item, tip.fresh = c, bar.src, true
    tip:SetScale(ns.db.scale or 1)
    -- beside the window, on the side with more room
    tip:ClearAllPoints()
    local cx = N(mw.GetCenter and (mw:GetCenter()))
    local sw = N(UIParent.GetWidth and UIParent:GetWidth())
    local left = cx and sw and cx > sw / 2
    if left then tip:SetPoint("BOTTOMRIGHT", mw, "BOTTOMLEFT", -4, 0) else tip:SetPoint("BOTTOMLEFT", mw, "BOTTOMRIGHT", 4, 0) end
    drawTip()
    tip:Show()
end
hideTip = function()
    if tip then tip:Hide(); tip.col, tip.item = nil, nil end
end

----------------------------------------------------------------------
-- copy: what the window shows, as text for chat or for anywhere else
----------------------------------------------------------------------
-- lines of plain text, or nil and why not
function ns.MeterReport(limit)
    local lines = {}
    local any = false
    for _, c in ipairs(cols) do
        if c.shown and c.data and #c.data.items > 0 then
            local data = c.data
            if not data.readable then return nil, "hidden" end
            any = true
            local where = state.seg == "total" and "total" or (state.segName and state.segName ~= "" and state.segName or "last fight")
            local dur = N(data.duration) or state.segDuration
            lines[#lines + 1] = "DearLord Stats: " .. c.view.name .. ", " .. where .. (dur and (" (" .. clock(dur) .. ")") or "")
            for i = 1, math.min(#data.items, limit or #data.items) do
                local it = data.items[i]
                local parts = {}
                if it.perSec and not c.view.count then parts[#parts + 1] = rateText(it.perSec) end
                if it.share then parts[#parts + 1] = string.format("%d%%", math.floor(it.share * 100 + 0.5)) end
                lines[#lines + 1] = string.format("%d. %s  %s%s", i, it.plainName or "?", ns.shortNumber(it.amount or 0),
                    #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or "")
            end
        end
    end
    if not any then return nil, "empty" end
    return lines
end

local function reportProblem(why)
    if why == "hidden" then ns.say("the game hides the numbers during a fight: the copy is ready when it ends")
    else ns.say("nothing on the meter to copy yet") end
end

local sendChat = SendChatMessage or (C_ChatInfo and C_ChatInfo.SendChatMessage)
function ns.MeterSend(channel, target)
    local lines, why = ns.MeterReport(ns.db.meterReportLines or 5)
    if not lines then reportProblem(why); return false end
    local d = diag()
    if not sendChat then
        d.chat = "no send function"
        ns.CopyBox(table.concat(lines, "\n"), "Meter")
        return false
    end
    -- all lines at once, inside the click: Say and Yell are only allowed straight from a key or mouse press
    for _, line in ipairs(lines) do
        local ok = pcall(sendChat, line:sub(1, 250), channel, nil, target)
        if not ok then
            d.chat = "refused (" .. channel .. ")"
            ns.say("the game refused the chat message: here it is as text instead")
            ns.CopyBox(table.concat(lines, "\n"), "Meter")
            return false
        end
    end
    d.chat = "sent (" .. channel .. ")"
    return true
end

function ns.MeterCopyBox()
    local lines, why = ns.MeterReport()
    if not lines then reportProblem(why); return false end
    ns.CopyBox(table.concat(lines, "\n"), "Meter")
    return true
end

function ns.MeterCopyMenu(owner)
    local items = { { text = "Say", fn = function() ns.MeterSend("SAY") end } }
    local raid = IsInRaid and B(IsInRaid())
    if raid then items[#items + 1] = { text = "Raid", fn = function() ns.MeterSend("RAID") end } end
    if raid or (IsInGroup and B(IsInGroup())) then items[#items + 1] = { text = "Party", fn = function() ns.MeterSend("PARTY") end } end
    if IsInGuild and B(IsInGuild()) then items[#items + 1] = { text = "Guild", fn = function() ns.MeterSend("GUILD") end } end
    local who = UnitIsPlayer and B(UnitIsPlayer("target")) and UnitIsFriend and B(UnitIsFriend("player", "target")) and S(UnitName("target"))
    if who and not (UnitIsUnit and B(UnitIsUnit("target", "player"))) then
        items[#items + 1] = { text = "Whisper " .. who, fn = function() ns.MeterSend("WHISPER", who) end }
    end
    items[#items + 1] = { divider = true }
    items[#items + 1] = { text = "Open as text to copy", fn = function() ns.MeterCopyBox() end }
    ns.PopMenu(owner, "Send what the meter shows", items)
end

----------------------------------------------------------------------
-- reset, preview, show and hide
----------------------------------------------------------------------
function ns.MeterReset(quiet)
    local d = diag()
    if not (DM and DM.ResetAllCombatSessions) then
        d.reset = "no reset function"
        if not quiet then ns.say("this client has no way to clear its damage meter") end
        return false
    end
    local ok = pcall(DM.ResetAllCombatSessions)
    d.reset = ok and "ok" or "refused"
    if ok and ns.CombatMeterReset then ns.CombatMeterReset() end
    if type(state.seg) == "number" then state.seg = "fight" end
    state.scroll, state.dirty = 0, true
    targetCache = {}
    refresh()
    if not quiet then ns.say(ok and "damage meter cleared" or "the game refused to clear its damage meter (in a fight?)") end
    return ok
end

function ns.MeterPreview(seconds)
    demo.t0, demo.sums = GetTime(), {}
    state.demoUntil = GetTime() + (seconds or 20)
    refresh()
end

function ns.ToggleMeter()
    ns.db.showMeter = not (ns.db.showMeter ~= false)
    if ns.db.showMeter then state.idleAt = GetTime() + 20 end
    refresh()
    return ns.db.showMeter
end

-- for the client checks
function ns.MeterStatus()
    local d = diag()
    local cvar
    if GetCVar then
        local ok, v = pcall(GetCVar, "damageMeterEnabled")
        if ok then cvar = S(v) end
    end
    return { available = available(), cvar = cvar, liveDraws = d.liveDraws or 0, readDraws = d.readDraws or 0, events = d.events or 0,
        hiddenGuid = d.hiddenGuid, chat = d.chat, liveSolo = d.liveSolo, liveGroup = d.liveGroup }
end

----------------------------------------------------------------------
-- when to redraw
----------------------------------------------------------------------
local function mark() state.dirty = true; state.events = state.events + 1; local d = diag(); d.events = (d.events or 0) + 1 end
ns.On("DAMAGE_METER_COMBAT_SESSION_UPDATED", mark, "meter:updated")
ns.On("DAMAGE_METER_CURRENT_SESSION_UPDATED", mark, "meter:current")
ns.On("DAMAGE_METER_RESET", function() state.dirty = true; targetCache = {} end, "meter:reset")
ns.On("PLAYER_REGEN_DISABLED", function()
    if type(state.seg) == "number" then state.seg = "fight" end     -- a new fight: back from an earlier one to this one
    state.scroll, state.dirty = 0, true
    refresh()
end, "meter:fight")
ns.On("PLAYER_REGEN_ENABLED", function()
    state.settleUntil = GetTime() + 6                              -- the numbers become readable a moment after the fight
    state.dirty = true
end, "meter:after")

local slow = 0
ns.Every(0.2, function(dt)
    if not ns.db then return end
    local now = GetTime()
    local isDemo = state.demoUntil > now
    local shown = mw:IsShown()
    slow = slow + (dt or 0.2)
    -- shown: every tick while something moves (a fight, the moment after it, the preview), else every 2 s.
    -- hidden: once a second, in case a setting or a fight brings it back
    if isDemo or state.wasDemo or (shown and (state.dirty or inCombat() or now < state.settleUntil)) or slow >= (shown and 2 or 1) then
        slow = 0
        refresh()
    end
    if tip and tip:IsShown() then drawTip() end
end, "meter:tick")

ns.OnLogin(function(isInitialLogin)
    local d = diag()
    d.api = (DM and DM.GetCombatSessionFromType and "by type") or (DM and DM.GetCombatSessionFromID and "by id") or "none"
    d.interp = (Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut ~= nil) or false
    d.abbrev = (AbbreviateNumbers ~= nil and (abbrevOptions() and "own format" or "game default")) or "none"
    d.sessions = #sessions()
    -- Total means this play session: it starts over when you log in (not on /reload)
    if isInitialLogin and ns.db.meterResetLogin ~= false and available() and not inCombat() then ns.MeterReset(true) end
    state.idleAt = GetTime() + 20
    mw:Layout()
end, "meter:login")
