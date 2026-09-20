-- DearLord Stats 2.0 : Professions
-- Skill-ups per hour, gathering per zone, trainer reminders, "craft now", a shopping list to
-- the next milestone, gentle nudges for forgotten professions, and a too-low-skill log.
local ADDON, ns = ...
local N, S, T, B = ns.N, ns.S, ns.T, ns.B
local TS = C_TradeSkillUI

local GATHER_CAST = { ["Mining"] = "Mining", ["Herb Gathering"] = "Herbalism", ["Skinning"] = "Skinning", ["Fishing"] = "Fishing" }
local CLOTH = { { id = 2589, name = "Linen Cloth", upTo = 80 }, { id = 2592, name = "Wool Cloth", upTo = 150 },
    { id = 4306, name = "Silk Cloth", upTo = 210 }, { id = 4338, name = "Mageweave Cloth", upTo = 260 },
    { id = 14047, name = "Runecloth", upTo = 300 } }
local RANK_CAP = 300

local ranks = {}                   -- name -> { rank, max, primary }
local pendingGather
local lastActive                   -- { name, t } most recent profession activity

----------------------------------------------------------------------
-- current professions and skill-ups
----------------------------------------------------------------------
local function scanProfessions()
    local out = {}
    if not (GetProfessions and GetProfessionInfo) then return out end
    local idx = { GetProfessions() }
    for pos = 1, 6 do
        local i = N(idx[pos])
        if i then
            local name, _, rank, max = GetProfessionInfo(i)
            name, rank, max = S(name), N(rank), N(max)
            if name and rank and max then out[name] = { rank = rank, max = max, primary = pos <= 2 } end
        end
    end
    return out
end

local function sessionProf(name)
    local p = ns.session.prof[name]
    if not p then
        p = { ups = 0, gathers = 0, first = time() }
        ns.session.prof[name] = p
    end
    return p
end

local function checkMilestones(name, info)
    local char = ns.char
    if info.rank >= info.max and info.max < RANK_CAP then
        ns.Nudge("cap:" .. name .. info.max, string.format("%s%s|r %sis capped at %d. Skill-ups are lost until you train the next rank.|r",
            ns.AMBER, name, ns.LABEL, info.max), "professions")
    elseif info.max - info.rank <= 10 and info.max < RANK_CAP then
        ns.Nudge("near:" .. name .. info.max, string.format("%s%s %d/%d|r %s. Train the next rank soon so you don't cap.|r",
            ns.WHITE, name, info.rank, info.max, ns.LABEL), "professions")
    end
    local unlocks = char.unlocks[name]
    if unlocks then
        for service, req in pairs(unlocks) do
            local flag = "unlock:" .. name .. ":" .. service
            if info.rank >= req and not char.flags[flag] then
                if ns.Nudge(flag, string.format("%s%s %d|r%s:|r %s%s|r %scan be trained now|r",
                    ns.WHITE, name, info.rank, ns.LABEL, ns.BLUE, service, ns.LABEL), "professions") then
                    char.flags[flag] = true
                end
            end
        end
    end
end

local function refreshRanks(quiet)
    if not ns.char or not ns.session then return end
    local now = scanProfessions()
    for name, info in pairs(now) do
        local before = ranks[name]
        if before and info.rank > before.rank then
            local p = sessionProf(name)
            p.ups, p.last = p.ups + (info.rank - before.rank), time()
            lastActive = { name = name, t = GetTime() }
        end
        ns.char.prof[name] = { rank = info.rank, max = info.max, primary = info.primary }
        if not quiet then checkMilestones(name, info) end
    end
    for name in pairs(ns.char.prof) do if not now[name] then ns.char.prof[name] = nil end end   -- unlearned
    ranks = now
    if ns.PanelDirty then ns.PanelDirty() end
end

function ns.ProfessionHudLine()
    if not lastActive or GetTime() - lastActive.t > 300 then return nil end
    local name = lastActive.name
    local info, p = ranks[name], ns.session.prof[name]
    if not p then return nil end
    local L, W = ns.LABEL, ns.WHITE
    local parts = {}
    if info then parts[#parts + 1] = string.format("%s%s|r %s%d/%d|r", L, name, W, info.rank, info.max)
    else parts[#parts + 1] = L .. name .. "|r" end
    if p.ups > 0 then
        local elapsed = time() - p.first
        local rate = elapsed >= 300 and string.format("  %s%.0f/h|r", L, p.ups / elapsed * 3600) or ""
        parts[#parts + 1] = string.format("%s+%d|r%s", ns.GREEN, p.ups, rate)
    end
    if p.gathers > 0 then parts[#parts + 1] = string.format("%s%d|r %sgathers|r", W, p.gathers, L) end
    return table.concat(parts, "   ")
end

----------------------------------------------------------------------
-- gathering and the too-low-skill log
----------------------------------------------------------------------
local lootPrefix = type(LOOT_ITEM_SELF) == "string" and LOOT_ITEM_SELF:match("^(.-)%%s") or "You receive loot"

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if S(unit) ~= "player" then return end
    local prof = GATHER_CAST[ns.spellName(spellID) or ""]
    if not prof or not ns.char then return end
    local zone = ns.zone()
    pendingGather = { prof = prof, zone = zone, t = GetTime() }
    local p = sessionProf(prof)
    p.gathers, p.last = p.gathers + 1, time()
    lastActive = { name = prof, t = GetTime() }
    local z = ns.char.gather[zone] or {}
    ns.char.gather[zone] = z
    z[prof] = z[prof] or { gathers = 0, items = {} }
    z[prof].gathers = z[prof].gathers + 1
end, "prof:gather")

ns.On("CHAT_MSG_LOOT", function(msg)
    msg = S(msg)
    if not msg or not pendingGather or GetTime() - pendingGather.t > 5 then return end
    if lootPrefix and msg:sub(1, #lootPrefix) ~= lootPrefix then return end
    local item = msg:match("%[(.-)%]")
    if not item then return end
    local count = tonumber(msg:match("x(%d+)%.?%s*$")) or 1
    local rec = ns.char.gather[pendingGather.zone] and ns.char.gather[pendingGather.zone][pendingGather.prof]
    if rec then rec.items[item] = (rec.items[item] or 0) + count end
end, "prof:loot")

local lowSkillPattern
do
    local s = ERR_USE_LOCKED_WITH_SPELL_KNOWN_SI
    if type(s) == "string" then
        s = s:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
        lowSkillPattern = "^" .. s .. "$"
    end
end

ns.On("UI_ERROR_MESSAGE", function(_, msg)
    msg = S(msg)
    if not msg or not lowSkillPattern or not ns.char then return end
    local skill, req = msg:match(lowSkillPattern)
    req = tonumber(req)
    if not skill or not req then return end
    local node
    if GameTooltip and GameTooltip:IsShown() and GameTooltipTextLeft1 then node = S(GameTooltipTextLeft1:GetText()) end
    local zone = ns.zone()
    local key = zone .. "|" .. (node or "?") .. "|" .. req
    for _, e in ipairs(ns.char.lowskill) do if e.key == key then e.t = time(); return end end
    table.insert(ns.char.lowskill, { key = key, zone = zone, node = node, skill = skill, req = req, t = time(),
        had = ranks[skill] and ranks[skill].rank })
    if #ns.char.lowskill > 40 then table.remove(ns.char.lowskill, 1) end
    if ns.PanelDirty then ns.PanelDirty() end
end, "prof:lowskill")

----------------------------------------------------------------------
-- trainer memory: visit a profession trainer once and the addon remembers what unlocks when
----------------------------------------------------------------------
local CATEGORY = { available = true, unavailable = true, used = true }
local function scanTrainer()
    if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceSkillReq) or not ns.char then return end
    if IsTradeskillTrainer and B(IsTradeskillTrainer()) == false then return end
    local n = N(GetNumTrainerServices()) or 0
    ns.diagOnce("trainerSample", function()
        local out = {}
        for i = 1, math.min(n, 6) do out[i] = ns.dump({ GetTrainerServiceInfo(i) }) .. " req=" .. ns.dump({ GetTrainerServiceSkillReq(i) }) end
        return table.concat(out, " ;; ")
    end)
    for i = 1, n do
        local info = { GetTrainerServiceInfo(i) }
        local name, category = S(info[1]), nil
        for j = 2, 4 do local v = S(info[j]); if v and CATEGORY[v] then category = v; break end end
        local skill, req = GetTrainerServiceSkillReq(i)
        skill, req = S(skill), N(req)
        if name and category and skill and req and req > 0 then
            ns.char.unlocks[skill] = ns.char.unlocks[skill] or {}
            if category == "used" then ns.char.unlocks[skill][name] = nil
            else ns.char.unlocks[skill][name] = req end
        end
    end
    if ns.PanelDirty then ns.PanelDirty() end
end

----------------------------------------------------------------------
-- recipe memory: open a profession window and the addon remembers your recipes
----------------------------------------------------------------------
-- returns nil when done, or a short reason when the window was not ready yet (the caller retries)
local function scanRecipes()
    TS = TS or C_TradeSkillUI
    if not (TS and TS.GetAllRecipeIDs and TS.GetRecipeInfo and TS.GetBaseProfessionInfo) then return "api missing", true end
    if not ns.char then return "no character yet" end
    for _, fn in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild" }) do
        if TS[fn] and B((TS[fn]())) then return fn, true end        -- someone else's recipes: do not retry
    end
    local base = T(TS.GetBaseProfessionInfo())
    local prof = base and S(base.professionName)
    if not prof or prof == "" then return "no profession name" end
    local ids = T(TS.GetAllRecipeIDs())
    if not ids or #ids == 0 then return "no recipe ids" end
    local list = {}
    for _, id in ipairs(ids) do
        local info = T(TS.GetRecipeInfo(id))
        if info and B(info.learned) and not B(info.isGatheringRecipe) and not B(info.isDummyRecipe) then
            local reagents = {}
            local sch = TS.GetRecipeSchematic and T(TS.GetRecipeSchematic(id, false))
            for _, slot in ipairs(sch and T(sch.reagentSlotSchematics) or {}) do
                local first = T(slot.reagents) and T(slot.reagents[1])
                local itemID, qty = first and N(first.itemID), N(slot.quantityRequired)
                if itemID and qty and qty > 0 and B(slot.required) ~= false and (N(slot.reagentType) or 1) == 1 then
                    reagents[#reagents + 1] = { id = itemID, qty = qty }
                end
            end
            list[#list + 1] = { id = id, name = S(info.name) or "?", diff = N(info.relativeDifficulty) or 3,
                trivial = N(info.maxTrivialLevel), reagents = reagents }
        end
    end
    ns.diagOnce("recipeSample", function() return ns.dump(T(TS.GetRecipeSchematic and TS.GetRecipeSchematic(ids[1], false))) end)
    ns.char.recipes[prof] = { scanned = time(), rank = N(base.skillLevel), max = N(base.maxSkillLevel), list = list }
    if ns.PanelDirty then ns.PanelDirty() end
end

-- what can be crafted for skill-ups right now from the bags: orange always gives a point,
-- yellow usually does, green only sometimes (still worth it when the materials are just sitting there)
function ns.CraftNow(prof)
    local cache = ns.char and ns.char.recipes[prof]
    if not cache then return nil end
    local have, order = {}, {}
    for _, r in ipairs(cache.list) do
        if r.diff <= 2 and #r.reagents > 0 then order[#order + 1] = r end
    end
    table.sort(order, function(a, b)
        if a.diff ~= b.diff then return a.diff < b.diff end
        local qa, qb = 0, 0
        for _, x in ipairs(a.reagents) do qa = qa + x.qty end
        for _, x in ipairs(b.reagents) do qb = qb + x.qty end
        return qa < qb
    end)
    local out = { orange = 0, yellow = 0, green = 0, list = {}, scanned = cache.scanned, rank = cache.rank }
    for _, r in ipairs(order) do
        local times = math.huge
        for _, x in ipairs(r.reagents) do
            if have[x.id] == nil then have[x.id] = ns.itemCount(x.id) end
            times = math.min(times, math.floor(have[x.id] / x.qty))
        end
        if times ~= math.huge and times > 0 then
            for _, x in ipairs(r.reagents) do have[x.id] = have[x.id] - x.qty * times end
            if r.diff == 0 then out.orange = out.orange + times
            elseif r.diff == 1 then out.yellow = out.yellow + times
            else out.green = out.green + times end
            out.list[#out.list + 1] = { name = r.name, times = times, diff = r.diff }
        end
    end
    out.expected = out.orange + out.yellow * 0.75 + out.green * 0.3      -- rough number of points to expect
    return out
end

-- materials to reach the next milestone (rank cap or a remembered trainer unlock)
function ns.ShoppingList(prof)
    local cache, info = ns.char and ns.char.recipes[prof], ranks[prof]
    if not cache or not info or info.rank >= info.max then return nil end
    local target, reason = info.max, "rank cap"
    for service, req in pairs(ns.char.unlocks[prof] or {}) do
        if req > info.rank and req < target then target, reason = req, service end
    end
    local need = target - info.rank
    local best, bestCost
    for pass = 0, 1 do
        for _, r in ipairs(cache.list) do
            if r.diff == pass and #r.reagents > 0 and (not r.trivial or r.trivial >= target) then
                local cost = 0
                for _, x in ipairs(r.reagents) do cost = cost + x.qty end
                if not best or cost < bestCost then best, bestCost = r, cost end
            end
        end
        if best then break end
    end
    if not best then return { target = target, reason = reason, need = need } end
    local crafts = best.diff == 0 and need or math.ceil(need * 1.5)
    local mats = {}
    for _, x in ipairs(best.reagents) do
        local total, have = x.qty * crafts, ns.itemCount(x.id)
        mats[#mats + 1] = { name = ns.itemName(x.id), total = total, have = have, short = math.max(0, total - have) }
    end
    return { target = target, reason = reason, need = need, recipe = best.name, crafts = crafts, yellow = best.diff ~= 0, mats = mats }
end

----------------------------------------------------------------------
-- gentle nudges, checked once a minute out of combat, at most one at a time
----------------------------------------------------------------------
local function checkNudges()
    local char = ns.char
    if not char or not ns.db.nudges then return end
    for name, info in pairs(ranks) do
        if info.rank < info.max then
            local cn = ns.CraftNow(name)
            if cn and cn.orange >= 5 then
                if ns.Nudge("craft:" .. name, string.format("%s%s|r%s:|r %s%d|r %sskill-ups craftable from your bags|r",
                    ns.WHITE, name, ns.LABEL, ns.GREEN, cn.orange, ns.LABEL), "professions") then return end
            end
        end
    end
    local fa = ranks["First Aid"]
    if fa and fa.rank < fa.max and not char.recipes["First Aid"] then
        for _, c in ipairs(CLOTH) do
            if fa.rank < c.upTo then
                local count = ns.itemCount(c.id)
                if count >= 10 then
                    if ns.Nudge("cloth:" .. c.id, string.format("%s%d %s|r %sin bags: about %d First Aid bandages|r",
                        ns.WHITE, count, c.name, ns.LABEL, math.floor(count / 2)), "professions") then return end
                end
                break
            end
        end
    end
    local level = N(UnitLevel("player")) or 0
    if level >= 10 and next(ranks) ~= nil then
        for _, sec in ipairs({ "First Aid", "Cooking" }) do
            local flag = "nosecondary:" .. sec
            if not ranks[sec] and not char.flags[flag] then
                if ns.Nudge(flag, string.format("%sNo %s yet on this character. Any trainer in a starting town teaches it.|r", ns.LABEL, sec), "professions") then
                    char.flags[flag] = true
                    return
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- a view for the report and the summary
----------------------------------------------------------------------
function ns.ProfessionsView()
    local out = {}
    for name, info in pairs(ranks) do
        local p = ns.session.prof[name]
        local unlocks = {}
        for service, req in pairs(ns.char.unlocks[name] or {}) do unlocks[#unlocks + 1] = { service = service, req = req, ready = info.rank >= req } end
        table.sort(unlocks, function(a, b) return a.req < b.req end)
        out[#out + 1] = { name = name, rank = info.rank, max = info.max, primary = info.primary,
            ups = p and p.ups or 0, gathers = p and p.gathers or 0,
            rate = (p and p.ups > 0 and time() - p.first >= 300) and p.ups / (time() - p.first) * 3600 or nil,
            craft = ns.CraftNow(name), shopping = ns.ShoppingList(name), unlocks = unlocks }
    end
    table.sort(out, function(a, b)
        if a.primary ~= b.primary then return a.primary end
        return a.name < b.name
    end)
    return out
end

local queuedRecipes, queuedTrainer = false, false
local function tryRecipes(attempt)
    local reason, final = scanRecipes()
    ns.db.diag.recipeScan = reason or "ok"
    if reason and not final and attempt < 6 then
        ns.After(0.7, function() tryRecipes(attempt + 1) end, "prof:recipes")
    else
        queuedRecipes = false
    end
end
local function queueRecipes()
    if queuedRecipes then return end
    queuedRecipes = true
    ns.After(0.5, function() tryRecipes(1) end, "prof:recipes")
end
ns.On("TRADE_SKILL_SHOW", queueRecipes, "prof:show")
ns.On("TRADE_SKILL_LIST_UPDATE", queueRecipes, "prof:list")
ns.On("NEW_RECIPE_LEARNED", queueRecipes, "prof:learned")
local function queueTrainer()
    if queuedTrainer then return end
    queuedTrainer = true
    ns.After(0.5, function() queuedTrainer = false; scanTrainer() end, "prof:trainer")
end
ns.On("TRAINER_SHOW", queueTrainer, "prof:trainershow")
ns.On("TRAINER_UPDATE", queueTrainer, "prof:trainerupdate")
ns.On("SKILL_LINES_CHANGED", function() refreshRanks(false) end, "prof:skilllines")
ns.On("CHAT_MSG_SKILL", function() ns.After(0.2, function() refreshRanks(false) end, "prof:skillmsg") end, "prof:skillmsg")
ns.OnLogin(function() ranks = {}; refreshRanks(true); ranks = scanProfessions() end, "prof:login")
ns.Every(60, function() if not (InCombatLockdown and InCombatLockdown()) then checkNudges() end end, "prof:nudges")
