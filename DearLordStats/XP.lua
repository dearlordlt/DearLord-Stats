-- DearLord Stats 2.0 : XP window (xp/h, last gain, rested-aware kills to level,
-- quests to level, time to level, gold/h) and the per-character level log.
local ADDON, ns = ...
local LABEL, WHITE = ns.LABEL, ns.WHITE
local shortNumber, shortTime, money = ns.shortNumber, ns.shortTime, ns.money

local xpwin = ns.CreateHud("xp", 0, "LEFT")
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

-- Forever moved the classic pet calls into C_PetInfo; older clients have them as globals.
-- Either way they may answer with plain values or with one table, so both are read.
local function petCall(name)
    local fn = (type(C_PetInfo) == "table" and C_PetInfo[name]) or _G[name]
    if type(fn) ~= "function" then return nil end
    local function after(ok, ...) if ok then return ... end end
    return after(pcall(fn))
end

local function field(t, ...)
    for i = 1, select("#", ...) do
        local v = t[select(i, ...)]
        if v ~= nil then return v end
    end
end

local function petMood()
    local happiness, damage, rate = petCall("GetPetHappiness")
    if type(happiness) == "table" then
        local t = happiness
        happiness = field(t, "happiness", "happinessLevel", "level", 1)
        damage = field(t, "damagePercentage", "damagePercent", "damage", 2)
        rate = field(t, "loyaltyRate", "loyalty", 3)
    end
    happiness = ns.N(happiness)
    if happiness then
        pet.mood = { HAPPY[happiness], ns.N(damage), ns.N(rate), happiness }
    elseif pet.mood and pet.name == ns.S(UnitName("pet")) then
        return unpack(pet.mood)             -- hidden in combat: keep the last reading
    end
    return HAPPY[happiness or 0], ns.N(damage), ns.N(rate), happiness
end

local LOYALTY = { "Rebellious", "Unruly", "Submissive", "Dependable", "Faithful", "Best Friend" }

-- "Loyalty Level 3 (Submissive)" -> 3, "Submissive"; a bare number gets its name; other wording shown as it comes
local function petLoyalty()
    local v, second = petCall("GetPetLoyalty")
    if type(v) == "table" then v, second = field(v, "loyaltyLevel", "level", "text", "name", 1), field(v, "name", "text", 2) end
    local n = ns.N(v)
    if n then
        local name = ns.S(second)
        if not name or name:find("^%d") then name = LOYALTY[n] end
        return tostring(n), name
    end
    local text = ns.S(v)
    if not text then return nil end
    local level, name = text:match("(%d+)"), text:match("%((.-)%)")
    return level, name or (level and LOYALTY[tonumber(level)]), text
end

local function petTraining()
    local total, spent = petCall("GetPetTrainingPoints")
    if type(total) == "table" then
        local t = total
        total = field(t, "totalPoints", "total", "points", 1)
        spent = field(t, "spent", "spentPoints", "used", 2)
    end
    total, spent = ns.N(total), ns.N(spent)
    if not total then return nil end
    return math.max(0, total - (spent or 0))
end

local function petFoods()
    local foods = {}
    local list = { petCall("GetPetFoodTypes") }
    if type(list[1]) == "table" then list = list[1] end
    for _, f in pairs(list) do f = ns.S(f); if f then foods[#foods + 1] = f end end
    return foods
end

-- what this client gives for the pet calls: missing, secret or plain values (read once per session)
function ns.PetProbe()
    local function show(...)
        local out = {}
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            out[i] = (issecretvalue and issecretvalue(v)) and "secret" or tostring(v)
        end
        return #out > 0 and table.concat(out, ",") or "none"
    end
    local function dump(v)
        if type(v) ~= "table" or (issecretvalue and issecretvalue(v)) then return nil end
        local out = {}
        for k, x in pairs(v) do out[#out + 1] = tostring(k) .. ":" .. ((issecretvalue and issecretvalue(x)) and "secret" or tostring(x)) end
        table.sort(out)
        return "{" .. table.concat(out, ";") .. "}"
    end
    local function try(name)
        local where, fn = "C_PetInfo.", type(C_PetInfo) == "table" and C_PetInfo[name]
        if type(fn) ~= "function" then where, fn = "", _G[name] end
        if type(fn) ~= "function" then return name .. "=missing" end
        local ok, a, b, c, d = pcall(fn)
        if not ok then return where .. name .. "=error " .. tostring(a) end
        return where .. name .. "=" .. (dump(a) or show(a, b, c, d))
    end
    local parts = {}
    for _, n in ipairs({ "GetPetHappiness", "GetPetLoyalty", "GetPetTrainingPoints", "GetPetExperience", "GetPetFoodTypes" }) do
        parts[#parts + 1] = try(n)
    end
    -- the names only (some pet calls act, e.g. abandon), never called
    local function keys(t, pattern)
        local out = {}
        if type(t) ~= "table" then return "none" end
        for k in pairs(t) do if type(k) == "string" and (not pattern or k:find(pattern)) then out[#out + 1] = k end end
        table.sort(out)
        return #out > 0 and table.concat(out, "/") or "none"
    end
    parts[#parts + 1] = "C_PetInfo=" .. keys(C_PetInfo)
    local found = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and (type(v) == "function" or type(v) == "table")
            and (k:find("Happ") or k:find("Loyal") or k:find("Training") or k:find("Diet") or k:find("PetFood")
                or (k:find("^C_") and k:find("Pet"))) then
            found[#found + 1] = k .. ":" .. type(v)
        end
    end
    table.sort(found)
    parts[#parts + 1] = "globals=" .. (#found > 0 and table.concat(found, "/") or "none")
    local PT = Enum and Enum.PowerType
    parts[#parts + 1] = "PowerType=" .. keys(PT, "Happ")
    local hp = PT and PT.Happiness or 4
    parts[#parts + 1] = "UnitPower(pet," .. tostring(hp) .. ")=" .. show(UnitPower("pet", hp)) .. "/" .. show(UnitPowerMax("pet", hp))
        .. " type=" .. show(UnitPowerType("pet"))
    for _, n in ipairs({ "PetLevelText", "PetLoyaltyText", "PetTrainingPointText", "PetTrainingPointLabel", "PetPaperDollFrameExpBar" }) do
        local f = _G[n]
        parts[#parts + 1] = n .. "=" .. (type(f) == "table" and f.GetText and show(f:GetText()) or type(f))
    end
    local hf = _G.PetFrameHappiness
    parts[#parts + 1] = "PetFrameHappiness=" .. type(hf) .. (type(hf) == "table" and hf.IsShown and (" shown=" .. tostring(hf:IsShown())) or "")
    return table.concat(parts, " ")
end

local LOYALTY_LEVEL = {}
for i, n in ipairs(LOYALTY) do LOYALTY_LEVEL[n] = i end

-- everything the pet block shows, or nil without a hunter pet out
local function petInfo()
    if ns.db.showPet == false or not hunterPet() then return nil end
    readPet()
    if not pet.level then return nil end
    if ns.db.diag and not ns.db.diag.petProbe then ns.db.diag.petProbe = ns.PetProbe() end
    local h, damage, rate, mood = petMood()
    local lvl, lname, raw = petLoyalty()
    lname = lname or raw
    lvl = tonumber(lvl) or (lname and LOYALTY_LEVEL[lname])
    return { h = h, damage = damage, rate = rate, mood = mood, loyalty = lname, loyaltyLevel = lvl, tp = petTraining(),
        kills = (pet.lastGain and pet.max and pet.max > 0) and math.ceil(math.max(0, pet.max - pet.xp) / pet.lastGain) or nil }
end

local KIND = { kill = "kill", quest = "quest", other = "other" }

----------------------------------------------------------------------
-- the window: blocks of icon + bar + small lines. XP (player portrait),
-- pet (portrait, bar coloured by happiness), gold (coin), profession (its icon).
----------------------------------------------------------------------
local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"     -- flat fill
local HAPPY_FACE = "|TInterface\\PetPaperDollFrame\\UI-PetHappiness:%d:%d:0:0:128:64:%d:%d:0:23|t"
local FACE_X = { 48, 24, 0 }                  -- unhappy, content, happy
local MOOD_COLOR = { { 0.80, 0.22, 0.20 }, { 0.85, 0.68, 0.18 }, { 0.30, 0.72, 0.30 } }
local PROF_ICON = {
    Skinning = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", Mining = "Interface\\Icons\\Trade_Mining",
    Herbalism = "Interface\\Icons\\Trade_Herbalism", Fishing = "Interface\\Icons\\Trade_Fishing",
    Cooking = "Interface\\Icons\\INV_Misc_Food_15", ["First Aid"] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    Alchemy = "Interface\\Icons\\Trade_Alchemy", Blacksmithing = "Interface\\Icons\\Trade_BlackSmithing",
    Enchanting = "Interface\\Icons\\Trade_Engraving", Engineering = "Interface\\Icons\\Trade_Engineering",
    Leatherworking = "Interface\\Icons\\Trade_LeatherWorking", Tailoring = "Interface\\Icons\\Trade_Tailoring",
}
local SEP = "|cff8a8a8a  ·  |r"

local blocks = {}
xpwin.blocks = blocks

local function text(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")          -- real font comes from the settings in Layout
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH("LEFT")
    xpwin.lines[#xpwin.lines + 1] = fs
    return fs
end

local function newBlock(key, bar, subs, color)
    local f = CreateFrame("Frame", nil, xpwin)
    local b = { key = key, frame = f, subs = {}, shownSubs = 0 }
    b.icon = f:CreateTexture(nil, "ARTWORK")
    if bar then
        local sb = CreateFrame("StatusBar", nil, f)
        sb:SetStatusBarTexture(BAR_TEXTURE)
        sb:SetStatusBarColor(color[1], color[2], color[3])
        sb:SetMinMaxValues(0, 1)
        local bg = sb:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.55)
        b.extra = sb:CreateTexture(nil, "BORDER")          -- rested part, under the fill
        b.extra:SetTexture(BAR_TEXTURE)
        b.extra:Hide()
        b.left = text(sb)
        b.right = text(sb)
        b.right:SetJustifyH("RIGHT")
        b.bar = sb
    end
    for i = 1, subs do
        b.subs[i] = text(f)
    end
    blocks[#blocks + 1] = b
    blocks[key] = b
    return b
end

newBlock("xp", true, 2, { 0.58, 0.20, 0.78 })
newBlock("pet", true, 1, MOOD_COLOR[2])
newBlock("gold", false, 1)
newBlock("prof", true, 1, { 0.20, 0.48, 0.86 })
blocks.gold.icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")

local function setBlock(b, on)
    b.on = on and true or false
    b.frame:SetShown(b.on)
    if b.left then b.left:SetShown(b.on); b.right:SetShown(b.on) end
    for i, fs in ipairs(b.subs) do fs:SetShown(b.on and i <= b.shownSubs) end
end

local function setSubs(b, ...)
    local n = 0
    for i = 1, #b.subs do
        local t = select(i, ...)
        if t and t ~= "" then n = n + 1; b.subs[n]:SetText(t) end
    end
    b.shownSubs = n
end

local function font(fs, delta)
    local db = ns.db
    local size, flags = math.max(8, db.fontSize + delta), db.outline or "OUTLINE"
    if not fs:SetFont(ns.FontPath(), size, flags) then fs:SetFont(STANDARD_TEXT_FONT, size, flags) end
end

-- sizes follow the font size setting; bars stretch to the widest line, never narrower than ~18 characters
function xpwin:Layout()
    local fsz = ns.db.fontSize
    local pad, gap = 6, 5
    local barH, step = fsz + 6, fsz + 3
    local big = barH + step
    local textX = big + 6
    local W = fsz * 18
    for _, b in ipairs(blocks) do
        if b.left then font(b.left, -1); font(b.right, -1) end
        for _, fs in ipairs(b.subs) do font(fs, -1) end
        if b.on then
            if b.bar then W = math.max(W, b.left:GetStringWidth() + b.right:GetStringWidth() + 20) end
            for i = 1, b.shownSubs do W = math.max(W, b.subs[i]:GetStringWidth() + 2) end
        end
    end
    local y = pad
    for _, b in ipairs(blocks) do
        if b.on then
            local f = b.frame
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -y)
            local h
            if b.bar then
                b.icon:ClearAllPoints()
                b.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
                b.icon:SetSize(big, big)
                b.bar:ClearAllPoints()
                b.bar:SetPoint("TOPLEFT", f, "TOPLEFT", textX, 0)
                b.bar:SetSize(W, barH)
                b.left:ClearAllPoints(); b.left:SetPoint("LEFT", b.bar, "LEFT", 5, 0)
                b.right:ClearAllPoints(); b.right:SetPoint("RIGHT", b.bar, "RIGHT", -5, 0)
                for i = 1, b.shownSubs do
                    b.subs[i]:ClearAllPoints()
                    b.subs[i]:SetPoint("TOPLEFT", f, "TOPLEFT", textX + 1, -(barH + 3) - (i - 1) * step)
                end
                if b.extraPart and b.extraPart[2] > 0 then
                    b.extra:ClearAllPoints()
                    b.extra:SetPoint("TOPLEFT", b.bar, "TOPLEFT", W * b.extraPart[1], 0)
                    b.extra:SetSize(math.max(1, W * b.extraPart[2]), barH)
                    b.extra:Show()
                else
                    b.extra:Hide()
                end
                h = math.max(big, barH + 3 + b.shownSubs * step)
            else
                local isz = fsz + 2
                b.icon:ClearAllPoints()
                b.icon:SetPoint("TOPLEFT", f, "TOPLEFT", big - isz, 0)
                b.icon:SetSize(isz, isz)
                for i = 1, b.shownSubs do
                    b.subs[i]:ClearAllPoints()
                    b.subs[i]:SetPoint("TOPLEFT", f, "TOPLEFT", textX + 1, -1 - (i - 1) * step)
                end
                h = math.max(isz, b.shownSubs * step)
            end
            f:SetSize(textX + W, h)
            y = y + h + gap
        end
    end
    self:SetWidth(pad * 2 + textX + W)
    self:SetHeight(math.max(20, y - gap + pad))
    if ns.LayoutFeed then ns.LayoutFeed() end
end
function xpwin:Fit() self:Layout() end

local portraitOf = {}
local function portrait(b, unit, who)
    if portraitOf[unit] ~= who and SetPortraitTexture then
        SetPortraitTexture(b.icon, unit)
        portraitOf[unit] = who
    end
end
ns.On("UNIT_PORTRAIT_UPDATE", function(unit) unit = ns.S(unit); if unit then portraitOf[unit] = nil end end, "xp:portrait")

local function V(x) return WHITE .. x .. "|r" end
local function Lb(x) return LABEL .. x .. "|r" end

local function profIcon(name)
    local tex
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, name)
        if ok then tex = t end
    end
    if tex == nil or (issecretvalue and issecretvalue(tex)) then tex = PROF_ICON[name] end
    return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

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

    -- player XP
    local b = blocks.xp
    setBlock(b, not atCap)
    if not atCap then
        portrait(b, "player", "player")
        local frac = max > 0 and cur / max or 0
        b.bar:SetValue(frac)
        local pool = restedPool()
        b.extraPart = { frac, max > 0 and math.min(pool, remaining) / max or 0 }
        b.extra:SetVertexColor(0.25, 0.55, 1, 0.45)
        b.left:SetText(V("Level " .. level))
        b.right:SetText(V(math.floor(frac * 100) .. "%") .. Lb("  " .. shortNumber(remaining) .. " to go"))
        local last = session.lastGain and (V("+" .. shortNumber(session.lastGain)) .. " " .. Lb((KIND[session.lastKind] or "") .. ""))
        local kills = killsNeeded(remaining, session.baseKill or session.lastKill, pool)
        local quests = session.lastQuest and math.ceil(remaining / session.lastQuest)
        local eta = perHour and (remaining / (perHour / 3600)) or nil
        local one = { V(perHour and shortNumber(perHour) or "-") .. " " .. Lb("xp/h") }
        if last then one[#one + 1] = Lb("last ") .. last end
        if eta then one[#one + 1] = Lb("level in ") .. V(shortTime(eta)) end
        local two = {}
        if kills then two[#two + 1] = V(kills) .. " " .. Lb(kills == 1 and "kill" or "kills") end
        if quests then two[#two + 1] = V(quests) .. " " .. Lb(quests == 1 and "quest" or "quests") end
        if #two > 0 then two[1] = Lb("to level ") .. two[1] end
        if pool > 0 then two[#two + 1] = ns.BLUE .. shortNumber(pool) .. " rested|r" end
        setSubs(b, table.concat(one, SEP), table.concat(two, SEP))
        setBlock(b, true)
    end

    -- hunter pet
    b = blocks.pet
    local pi = petInfo()
    if pi then
        portrait(b, "pet", pet.name)
        local frac = (pet.max and pet.max > 0) and pet.xp / pet.max or 0
        b.bar:SetValue(frac)
        local c = MOOD_COLOR[pi.mood or 0] or { 0.75, 0.55, 0.25 }
        b.bar:SetStatusBarColor(c[1], c[2], c[3])
        b.left:SetText(V((pet.name or "Pet") .. "  " .. pet.level))
        b.right:SetText(V(math.floor(frac * 100) .. "%") .. (pi.kills and Lb("  " .. pi.kills .. (pi.kills == 1 and " kill" or " kills")) or ""))
        local parts = {}
        if pi.h then
            local sz = db.fontSize + 1
            local face = string.format(HAPPY_FACE, sz, sz, FACE_X[pi.mood], FACE_X[pi.mood] + 24)
            local t = face .. " " .. pi.h[2] .. pi.h[1] .. "|r"
            if pi.damage then t = t .. Lb(" " .. pi.damage .. "%") end
            if pi.mood == 1 then t = t .. ns.RED .. "  feed it|r" end
            parts[#parts + 1] = t
        end
        if pi.loyalty then
            local t = V(pi.loyalty) .. (pi.loyaltyLevel and Lb(" " .. pi.loyaltyLevel .. "/6") or "")
            if pi.rate and pi.rate < 0 then t = t .. ns.RED .. " falling|r" end
            parts[#parts + 1] = t
        end
        if pi.tp then parts[#parts + 1] = (pi.tp > 0 and (ns.AMBER .. pi.tp .. " TP to spend|r") or (V("0") .. Lb(" TP"))) end
        setSubs(b, table.concat(parts, SEP))
    end
    setBlock(b, pi ~= nil)

    -- gold
    b = blocks.gold
    local earned, spent = session.earned or 0, session.spent or 0
    local gold = { Lb("net ") .. V(money(earned - spent, true)) }
    if earned > 0 and elapsed >= 30 then gold[#gold + 1] = V(money(earned / elapsed * 3600)) .. Lb(" per hour") end
    setSubs(b, table.concat(gold, SEP))
    setBlock(b, db.showGold ~= false)

    -- the profession being worked on
    b = blocks.prof
    local pr = db.showProf ~= false and ns.ProfessionHudInfo and ns.ProfessionHudInfo() or nil
    if pr then
        b.icon:SetTexture(profIcon(pr.name))
        b.bar:SetValue((pr.rank and pr.max and pr.max > 0) and pr.rank / pr.max or 0)
        b.left:SetText(V(pr.name))
        b.right:SetText(pr.rank and (V(pr.rank) .. Lb(" / " .. pr.max)) or "")
        local parts = {}
        if pr.ups > 0 then parts[#parts + 1] = ns.GREEN .. "+" .. pr.ups .. "|r" .. (pr.rate and Lb(string.format(" %.0f/h", pr.rate)) or "") end
        if pr.gathers > 0 then parts[#parts + 1] = V(pr.gathers) .. Lb(pr.gathers == 1 and " gather" or " gathers") end
        setSubs(b, table.concat(parts, SEP))
    end
    setBlock(b, pr ~= nil)

    xpwin:Layout()
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
        GameTooltip:AddDoubleLine("Level", tostring(pet.level), G, G, G, 1, 1, 1)
        local lvl, lname, raw = petLoyalty()
        lname = lname or raw
        lvl = tonumber(lvl) or (lname and LOYALTY_LEVEL[lname])
        if lname or lvl then
            GameTooltip:AddDoubleLine("Loyalty level", (lname or "") .. (lvl and ("  " .. lvl .. "/6") or ""), G, G, G, 1, 1, 1)
        end
        local tp = petTraining()
        if tp then GameTooltip:AddDoubleLine("Training points unspent", tostring(tp), G, G, G, 1, 1, 1) end
        if pet.max and pet.max > 0 then
            GameTooltip:AddDoubleLine("Pet XP", shortNumber(pet.xp) .. " / " .. shortNumber(pet.max), G, G, G, 1, 1, 1)
        end
        if pet.lastGain then GameTooltip:AddDoubleLine("Last pet gain", "+" .. shortNumber(pet.lastGain), G, G, G, 1, 1, 1) end
        if (session.petXP or 0) > 0 then GameTooltip:AddDoubleLine("Pet XP this session", shortNumber(session.petXP), G, G, G, 1, 1, 1) end
        local h, damage, rate = petMood()
        if h then
            GameTooltip:AddDoubleLine("Happiness", h[2] .. h[1] .. "|r" .. (damage and ("  " .. damage .. "% damage") or ""), G, G, G, 1, 1, 1)
        end
        local foods = petFoods()
        if #foods > 0 then GameTooltip:AddDoubleLine("Eats", table.concat(foods, ", "), G, G, G, 1, 1, 1) end
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
    if ns.db.diag then ns.db.diag.petProbe = nil end       -- probed again each session
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
