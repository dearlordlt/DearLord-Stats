-- DearLord Stats 2.0 : XP window (xp/h, last gain, rested-aware kills to level,
-- quests to level, time to level, gold/h) and the per-character level log.
local ADDON, ns = ...
local LABEL, WHITE = ns.LABEL, ns.WHITE
local shortNumber, shortTime, money = ns.shortNumber, ns.shortTime, ns.money

local xpwin = ns.CreateHud("xp", 5, "LEFT")
xpwin.panelTab = "combat"

local lastXP, lastMax, levelAtLastXP, lastMoney
local restedBefore = 0
local questFlag, killFlag, otherFlag = 0, 0, 0
ns.curLevel = nil

function ns.levelRec(level)
    local char = ns.char
    if not char or not level then return nil end
    local r = char.levels[level]
    if not r then
        r = { seconds = 0, xp = 0, kills = 0, quests = 0, money = 0, started = time() }
        if level == ns.N(UnitLevel("player")) and (ns.N(UnitXP("player")) or 0) > 0 then r.partial = true end
        char.levels[level] = r
    end
    return r
end

function ns.levelSummary(level, r, plain)
    local rate = r.seconds >= 30 and shortNumber(r.xp / r.seconds * 3600) or "-"
    return string.format("L%d%s  %s  %s xp/h  %d kills  %d quests  %s",
        level, r.partial and "*" or "", shortTime(r.seconds), rate, r.kills, r.quests, money(r.money, true, plain))
end

function ns.PrintLevelLog()
    local char = ns.char
    if not char then return end
    local levels = {}
    for lvl in pairs(char.levels) do levels[#levels + 1] = lvl end
    table.sort(levels)
    if #levels == 0 then ns.say("no levels logged yet") return end
    ns.say("level log (time played with the addon running; * = partial level)")
    for _, lvl in ipairs(levels) do print("   " .. ns.levelSummary(lvl, char.levels[lvl])) end
end

-- "You gain %d experience." with no creature name means quest / exploration XP
local unnamedPattern
do
    local s = COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED
    if type(s) == "string" then
        s = s:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%d", "%%d+")
        unnamedPattern = "^" .. s
    end
end

local function restedPool() return (GetXPExhaustion and ns.N(GetXPExhaustion())) or 0 end
local function baseKillXP(gain, pool)
    if pool >= gain then return gain / 2
    elseif pool > 0 then return gain - pool / 2
    else return gain end
end
local function killsNeeded(remaining, base, pool)
    if not base or base <= 0 then return nil end
    local restedPart = math.min(pool, remaining)
    return math.ceil(restedPart / (base * 2) + (remaining - restedPart) / base)
end

local function classifyGain(gain, poolBefore, gainLevel)
    local session = ns.session
    local now, kind = GetTime(), "other"
    if now - questFlag < 2 then kind = "quest"
    elseif now - killFlag < 2 and killFlag >= otherFlag then kind = "kill" end
    session.lastGain, session.lastKind = gain, kind
    local rec = ns.levelRec(gainLevel)
    if kind == "kill" then
        session.lastKill, session.kills = gain, session.kills + 1
        session.baseKill = baseKillXP(gain, poolBefore or 0)
        if rec then rec.kills = rec.kills + 1 end
        if ns.OnXPKill then ns.OnXPKill() end
    elseif kind == "quest" then
        session.lastQuest, session.quests = gain, session.quests + 1
        if rec then rec.quests = rec.quests + 1 end
    end
end

local function onXPUpdate()
    local cur, max = ns.N(UnitXP("player")), ns.N(UnitXPMax("player"))
    if not cur or not max then return end
    if lastXP then
        local gain
        local oldLevel = levelAtLastXP or ns.curLevel
        if cur < lastXP then
            local oldPart = lastMax - lastXP
            gain = oldPart + cur
            local newLevel = math.max(ns.N(UnitLevel("player")) or 0, (oldLevel or 0) + 1)
            local a, b = ns.levelRec(oldLevel), ns.levelRec(newLevel)
            if a then a.xp = a.xp + oldPart end
            if b then b.xp = b.xp + cur; b.partial = nil end
            ns.curLevel = newLevel
        else
            gain = cur - lastXP
            local a = ns.levelRec(oldLevel)
            if a then a.xp = a.xp + gain end
        end
        if gain > 0 then
            ns.session.xp = ns.session.xp + gain
            local poolBefore = restedBefore
            ns.After(0.3, function() classifyGain(gain, poolBefore, oldLevel) end, "xp:classify")
        end
    end
    lastXP, lastMax, levelAtLastXP = cur, max, ns.curLevel
    restedBefore = restedPool()
end

local function onMoney()
    local now = ns.N(GetMoney())
    if not now then return end
    if lastMoney then
        local delta = now - lastMoney
        if delta > 0 then ns.session.earned = (ns.session.earned or 0) + delta
        elseif delta < 0 then ns.session.spent = (ns.session.spent or 0) - delta end
        local rec = ns.levelRec(ns.curLevel)
        if rec then rec.money = rec.money + delta end
    end
    lastMoney = now
end

function ns.ResetSession()
    ns.newSession()
    lastMoney = ns.N(GetMoney())
    ns.say("session reset")
end

local KIND = { kill = "kill", quest = "quest", other = "other" }

local function refresh()
    local db, session = ns.db, ns.session
    if not db or not session or not ns.char then return end
    local level, maxLevel = ns.N(UnitLevel("player")) or 0, (GetMaxPlayerLevel and ns.N(GetMaxPlayerLevel())) or 60
    if not db.showXP then xpwin:Hide(); if ns.LayoutFeed then ns.LayoutFeed() end return end
    xpwin:Show()
    local atCap = level >= maxLevel
    local cur, max = ns.N(UnitXP("player")) or 0, ns.N(UnitXPMax("player")) or 0
    local remaining = math.max(0, max - cur)
    local elapsed = math.max(1, time() - session.start)
    local perHour = (session.xp > 0 and elapsed >= 30) and (session.xp / elapsed * 3600) or nil
    local L = xpwin.lines

    for i = 1, 3 do L[i]:SetShown(not atCap) end
    if not atCap then
        local last = session.lastGain and
            string.format("%s+%s|r %s%s|r", WHITE, shortNumber(session.lastGain), LABEL, KIND[session.lastKind] or "")
            or (LABEL .. "-|r")
        L[1]:SetFormattedText("%sxp/h|r %s%s|r    %slast|r %s", LABEL, WHITE, perHour and shortNumber(perHour) or "-", LABEL, last)

        local pool = restedPool()
        local kills = killsNeeded(remaining, session.baseKill or session.lastKill, pool)
        local quests = session.lastQuest and math.ceil(remaining / session.lastQuest)
        local line2 = string.format("%sto level|r %s%s|r %s%s|r  %s%s|r %s%s|r",
            LABEL, WHITE, kills or "-", LABEL, kills == 1 and "kill" or "kills",
            WHITE, quests or "-", LABEL, quests == 1 and "quest" or "quests")
        if pool > 0 then line2 = line2 .. string.format("   %srested %s|r", ns.BLUE, shortNumber(pool)) end
        L[2]:SetText(line2)

        local eta = perHour and (remaining / (perHour / 3600)) or nil
        L[3]:SetFormattedText("%slevel in|r %s%s|r   %s%d%%  %s left|r",
            LABEL, WHITE, shortTime(eta), LABEL, max > 0 and math.floor(cur / max * 100) or 0, shortNumber(remaining))
    end

    local earned, spent = session.earned or 0, session.spent or 0
    local goldRate = (earned > 0 and elapsed >= 30) and money(earned / elapsed * 3600) or (LABEL .. "-|r")
    L[4]:SetShown(db.showGold ~= false)
    L[4]:SetFormattedText("%sgold/h|r %s%s|r   %snet|r %s%s|r", LABEL, WHITE, goldRate, LABEL, WHITE, money(earned - spent, true))

    -- fifth line: only while a profession is being worked on
    local profLine = db.showProf ~= false and ns.ProfessionHudLine and ns.ProfessionHudLine() or nil
    L[5]:SetShown(profLine ~= nil)
    if profLine then L[5]:SetText(profLine) end

    -- re-stack visible lines so hidden ones leave no gap
    local step, n = db.fontSize + 2, 0
    for i = 1, #L do
        if L[i]:IsShown() then
            L[i]:ClearAllPoints()
            L[i]:SetPoint("TOPLEFT", xpwin, "TOPLEFT", 8, -4 - n * step)
            n = n + 1
        end
    end
    xpwin:Fit()
end
ns.RefreshXP = refresh

xpwin:SetScript("OnEnter", function(self)
    local session, char = ns.session, ns.char
    if not session then return end
    self.bg:Show()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("DearLord Stats: session")
    GameTooltip:AddDoubleLine("Session length", shortTime(time() - session.start), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("XP gained", shortNumber(session.xp), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Kills / quests", session.kills .. " / " .. session.quests, 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Gold earned / spent", money(session.earned or 0) .. " / " .. money(session.spent or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    local rec = char and char.levels[ns.curLevel]
    if rec then GameTooltip:AddDoubleLine("This level so far", shortTime(rec.seconds) .. (rec.partial and " *" or ""), 0.8, 0.8, 0.8, 1, 1, 1) end
    GameTooltip:AddLine("Kills to level count double only while rested XP lasts.", 0.5, 0.7, 1, true)
    GameTooltip:AddLine("Click: open report.  Drag: move.  Right-click: options.", 0.6, 0.8, 1)
    GameTooltip:Show()
end)

ns.OnLogin(function()
    ns.curLevel = ns.N(UnitLevel("player"))
    lastXP, lastMax, levelAtLastXP = ns.N(UnitXP("player")), ns.N(UnitXPMax("player")), ns.curLevel
    lastMoney = ns.N(GetMoney())
    restedBefore = restedPool()
    ns.levelRec(ns.curLevel)
    refresh()
end, "xp:login")

ns.On("PLAYER_XP_UPDATE", function(unit) if unit == nil or unit == "player" then onXPUpdate() end end, "xp:update")
ns.On("CHAT_MSG_COMBAT_XP_GAIN", function(msg)
    msg = ns.S(msg)
    if unnamedPattern and msg and msg:find(unnamedPattern) then otherFlag = GetTime() else killFlag = GetTime() end
end, "xp:chat")
ns.On("QUEST_TURNED_IN", function() questFlag = GetTime() end, "xp:quest")
ns.On("PLAYER_MONEY", onMoney, "xp:money")
ns.On("UPDATE_EXHAUSTION", function()
    local pool = restedPool()
    if pool > restedBefore then restedBefore = pool end
end, "xp:rested")
ns.On("PLAYER_LEVEL_UP", function(newLevel)
    newLevel = tonumber(ns.N(newLevel))
    if not newLevel then return end
    local done = newLevel - 1
    ns.curLevel = math.max(ns.curLevel or newLevel, newLevel)
    if ns.char then ns.char.level = newLevel end
    ns.After(1.5, function()
        local r = ns.char and ns.char.levels[done]
        if r then r.finished = time(); ns.say("finished " .. ns.levelSummary(done, r)) end
        ns.levelRec(newLevel)
    end, "xp:levelup")
end, "xp:levelup")

ns.Every(1, function(dt)
    if not ns.char then return end
    local rec = ns.levelRec(ns.curLevel)
    if rec and not (UnitIsAFK and ns.B(UnitIsAFK("player"))) then rec.seconds = rec.seconds + dt end
    refresh()
end, "xp:tick")
