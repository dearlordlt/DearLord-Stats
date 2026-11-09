-- DearLord Stats 2.0 : XP window (xp/h, last gain, rested-aware kills to level,
-- quests to level, time to level, gold/h) and the per-character level log.
local ADDON, ns = ...
local LABEL, WHITE = ns.LABEL, ns.WHITE
local shortNumber, shortTime, money = ns.shortNumber, ns.shortTime, ns.money

local xpwin = ns.CreateHud("xp", 7, "LEFT")
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


-- hunter pet: level, progress, kills to its next level (from its last XP gain), happiness
local pet = {}
local HAPPY = { { "unhappy", ns.RED }, { "content", ns.AMBER }, { "happy", ns.GREEN } }

local function hunterPet()
    if not (HasPetUI and GetPetExperience and ns.B(UnitExists("pet"))) then return false end
    local hasUI, isHunter = HasPetUI()
    return ns.B(hasUI) and ns.B(isHunter) or false
end

local function readPet()
    local cur, max = GetPetExperience()
    cur, max = ns.N(cur), ns.N(max)
    local level, name = ns.N(UnitLevel("pet")), ns.S(UnitName("pet"))
    if not cur or not max or not level then return end
    if name ~= pet.name then
        pet.name, pet.lastGain = name, nil
    elseif pet.xp then
        local gain
        if level > pet.level then gain = math.max(0, pet.max - pet.xp) + cur
        elseif level == pet.level and cur > pet.xp then gain = cur - pet.xp end
        if gain and gain > 0 then
            pet.lastGain = gain
            if ns.session then ns.session.petXP = (ns.session.petXP or 0) + gain end
        end
    end
    pet.xp, pet.max, pet.level = cur, max, level
end

local function petMood()
    if not GetPetHappiness then return nil end
    local happiness, damage, loyaltyRate = GetPetHappiness()
    local h = HAPPY[ns.N(happiness) or 0]
    return h, ns.N(damage), ns.N(loyaltyRate), ns.N(happiness)
end

-- "Loyalty Level 3 (Submissive)" -> 3, "Submissive"; any other wording is shown as it comes
local function petLoyalty()
    local text = GetPetLoyalty and ns.S(GetPetLoyalty())
    if not text then return nil end
    local level, name = text:match("(%d+)"), text:match("%((.-)%)")
    return level, name, text
end

local function petTraining()
    if not GetPetTrainingPoints then return nil end
    local total, spent = GetPetTrainingPoints()
    total, spent = ns.N(total), ns.N(spent)
    if not total then return nil end
    return math.max(0, total - (spent or 0))
end

local function petLines()
    if ns.db.showPet == false or not hunterPet() then return nil end
    readPet()
    if not pet.level then return nil end
    local line = string.format("%spet|r %sL%d|r", LABEL, WHITE, pet.level)
    if pet.max and pet.max > 0 then
        local kills = pet.lastGain and math.ceil(math.max(0, pet.max - pet.xp) / pet.lastGain)
        line = line .. string.format("  %s%d%%|r  %s%s|r %s%s|r", LABEL, math.floor(pet.xp / pet.max * 100),
            WHITE, kills or "-", LABEL, kills == 1 and "kill" or "kills")
    end
    local h, damage, rate, mood = petMood()
    if h then
        line = line .. "   " .. h[2] .. h[1] .. "|r"
        if damage then line = line .. string.format(" %s%d%% damage|r", mood == 1 and ns.RED or LABEL, damage) end
        if mood == 1 then line = line .. ns.RED .. ", feed it|r" end
    end

    local parts = {}
    local lvl, name, raw = petLoyalty()
    if lvl or raw then
        local trend = (rate and rate < 0) and (ns.RED .. " falling|r") or ""
        parts[#parts + 1] = lvl and string.format("%sloyalty|r %s%s%s|r%s", LABEL, WHITE, lvl, name and (" " .. name) or "", trend)
            or (WHITE .. raw .. "|r" .. trend)
    end
    local tp = petTraining()
    if tp then
        parts[#parts + 1] = string.format("%s%d|r %straining points|r", tp > 0 and ns.AMBER or WHITE, tp, LABEL)
    end
    if ns.db.diag then
        ns.db.diag.petApi = string.format("happy=%s loyalty=%s tp=%s", tostring(mood), tostring(raw), tostring(tp))
    end
    return line, #parts > 0 and ("    " .. table.concat(parts, "   ")) or nil
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
    -- pet line: only with a hunter pet out
    local petText, petText2 = petLines()
    L[4]:SetShown(petText ~= nil)
    if petText then L[4]:SetText(petText) end
    L[5]:SetShown(petText2 ~= nil)
    if petText2 then L[5]:SetText(petText2) end

    L[6]:SetShown(db.showGold ~= false)
    L[6]:SetFormattedText("%sgold/h|r %s%s|r   %snet|r %s%s|r", LABEL, WHITE, goldRate, LABEL, WHITE, money(earned - spent, true))

    -- last line: only while a profession is being worked on
    local profLine = db.showProf ~= false and ns.ProfessionHudLine and ns.ProfessionHudLine() or nil
    L[7]:SetShown(profLine ~= nil)
    if profLine then L[7]:SetText(profLine) end

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
    if hunterPet() and pet.level then
        local G = 0.8
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Pet: " .. (pet.name or "?"))
        local loyalty = GetPetLoyalty and ns.S(GetPetLoyalty())
        GameTooltip:AddDoubleLine("Level", pet.level .. (loyalty and ("  " .. loyalty) or ""), G, G, G, 1, 1, 1)
        if pet.max and pet.max > 0 then
            GameTooltip:AddDoubleLine("Pet XP", shortNumber(pet.xp) .. " / " .. shortNumber(pet.max), G, G, G, 1, 1, 1)
        end
        if pet.lastGain then GameTooltip:AddDoubleLine("Last pet gain", "+" .. shortNumber(pet.lastGain), G, G, G, 1, 1, 1) end
        if (session.petXP or 0) > 0 then GameTooltip:AddDoubleLine("Pet XP this session", shortNumber(session.petXP), G, G, G, 1, 1, 1) end
        local h, damage, rate = petMood()
        if h then
            GameTooltip:AddDoubleLine("Happiness", h[2] .. h[1] .. "|r" .. (damage and ("  " .. damage .. "% damage") or ""), G, G, G, 1, 1, 1)
        end
        if GetPetFoodTypes then
            local foods = {}
            for _, f in ipairs({ GetPetFoodTypes() }) do f = ns.S(f); if f then foods[#foods + 1] = f end end
            if #foods > 0 then GameTooltip:AddDoubleLine("Eats", table.concat(foods, ", "), G, G, G, 1, 1, 1) end
        end
        if rate and rate ~= 0 then
            GameTooltip:AddDoubleLine("Loyalty", rate > 0 and (ns.GREEN .. "growing|r") or (ns.RED .. "falling, feed your pet|r"), G, G, G, 1, 1, 1)
        end
        if pet.level >= (ns.N(UnitLevel("player")) or 0) then
            GameTooltip:AddLine("A pet cannot level past you.", 0.5, 0.7, 1, true)
        end
    end
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
ns.On("UNIT_PET_EXPERIENCE", function() if hunterPet() then readPet() end end, "xp:pet")
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
