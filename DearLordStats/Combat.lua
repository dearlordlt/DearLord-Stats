-- DearLord Stats 2.0 : Combat
-- Fight tracking, fight recap, abilities breakdown, danger and pull-size stats, deaths.
-- The combat log is forbidden to addons on this client and most numbers are hidden while
-- in combat, so fights are measured like this:
--   * start / end            PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED
--   * damage, taken, heals,  the game's built-in damage meter (C_DamageMeter), read about a
--     per-spell breakdown    second after the fight, when its numbers become readable
--   * pull size              distinct mobs that had us (or the pet) on their threat list
--   * fallback               live UNIT_COMBAT hit events, when the meter has nothing for a fight
local ADDON, ns = ...
local N, S, T, B = ns.N, ns.S, ns.T, ns.B

local DM = C_DamageMeter
local TYPE = (Enum and Enum.DamageMeterType) or {}
local fight                       -- fight in progress
local pending = {}                -- finished fights waiting for damage meter data
local lastSessionID = 0
local lastFightEnd
local lastHP, lastMana            -- { pct, t } from the latest readable sample
local OOM = {}
for _, g in ipairs({ "ERR_OUT_OF_MANA", "ERR_OUT_OF_RAGE", "ERR_OUT_OF_ENERGY", "ERR_OUT_OF_FOCUS" }) do
    if type(_G[g]) == "string" then OOM[_G[g]] = true end
end

local function dmReady() return DM and DM.GetAvailableCombatSessions and DM.GetCombatSessionFromID and TYPE.DamageDone ~= nil end
local function inCombat() return B(UnitAffectingCombat and UnitAffectingCombat("player")) or false end
local function petName() return S(UnitName and UnitName("pet")) end

----------------------------------------------------------------------
-- reading one finished fight from the built-in damage meter
----------------------------------------------------------------------
local function localSource(session)
    local sources = session and T(session.combatSources)
    if not sources then return nil end
    for _, src in ipairs(sources) do
        if B(src.isLocalPlayer) then return src end
    end
end

local function readSession(id)
    local dmgS = T(DM.GetCombatSessionFromID(id, TYPE.DamageDone))
    if not dmgS then return nil end
    local total = N(dmgS.totalAmount)
    if not total then return nil end                         -- still hidden: we are in combat again
    local data = { dmg = 0, petDmg = 0, spells = {}, taken = 0, healed = 0, enemies = 0 }
    local petSeparate = 0                                    -- pet damage listed outside the player's own total
    local me, pet = localSource(dmgS), petName()
    local myGUID = me and S(me.sourceGUID)
    data.dmg = me and N(me.totalAmount) or 0
    for _, src in ipairs(T(dmgS.combatSources) or {}) do
        local name = S(src.name)
        if not B(src.isLocalPlayer) and pet and name == pet then      -- pet listed as its own source
            petSeparate = petSeparate + (N(src.totalAmount) or 0)
            local pg = S(src.sourceGUID)
            local ps = pg and DM.GetCombatSessionSourceFromID and T(DM.GetCombatSessionSourceFromID(id, TYPE.DamageDone, pg))
            for _, sp in ipairs(ps and T(ps.combatSpells) or {}) do
                local amount = N(sp.totalAmount)
                if amount and amount > 0 then table.insert(data.spells, { name = "Pet: " .. (ns.spellName(sp.spellID) or "?"), dmg = amount }) end
            end
        end
    end
    if #(T(dmgS.combatSources) or {}) > 1 then
        ns.diagOnce("dmMultiSource", function() return ns.dump(dmgS.combatSources) end)
    end
    if myGUID and DM.GetCombatSessionSourceFromID then
        local detail = T(DM.GetCombatSessionSourceFromID(id, TYPE.DamageDone, myGUID))
        for _, sp in ipairs(detail and T(detail.combatSpells) or {}) do
            local amount, creature = N(sp.totalAmount), S(sp.creatureName)
            local details = T(sp.combatSpellDetails)
            local isPet = (details and B(details.isPet)) or (creature ~= nil and creature ~= "")
            if amount and amount > 0 then
                local name = ns.spellName(sp.spellID) or "?"
                if isPet then                                         -- pet folded into the player's list
                    name = "Pet: " .. name
                    data.petDmg = data.petDmg + amount
                end
                table.insert(data.spells, { name = name, dmg = amount })
            end
        end
        ns.diagOnce("dmSpellSample", function() return ns.dump(detail and detail.combatSpells and detail.combatSpells[1]) end)
    end
    if TYPE.DamageTaken ~= nil then
        local src = localSource(T(DM.GetCombatSessionFromID(id, TYPE.DamageTaken)))
        data.taken = src and N(src.totalAmount) or 0
    end
    if TYPE.HealingDone ~= nil then
        local src = localSource(T(DM.GetCombatSessionFromID(id, TYPE.HealingDone)))
        data.healed = src and N(src.totalAmount) or 0
    end
    if TYPE.EnemyDamageTaken ~= nil then
        local es = T(DM.GetCombatSessionFromID(id, TYPE.EnemyDamageTaken))
        data.enemies = es and #(T(es.combatSources) or {}) or 0
        ns.diagOnce("dmEnemySample", function() return ns.dump(es) end)
    end
    data.dmg = data.dmg + petSeparate
    data.petDmg = data.petDmg + petSeparate
    return data
end

local function newSessionIDs()
    local list, out = T(DM.GetAvailableCombatSessions()) or {}, {}
    local maxSeen = 0
    for _, s in ipairs(list) do
        local id = N(s.sessionID)
        if id then
            if id > maxSeen then maxSeen = id end
            if id > lastSessionID then out[#out + 1] = { id = id, name = S(s.name) } end
        end
    end
    if maxSeen < lastSessionID then lastSessionID = 0 end    -- the meter was reset
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

----------------------------------------------------------------------
-- folding a finished fight into the running totals
----------------------------------------------------------------------
-- light = true keeps only the headline numbers (used for the per-zone, per-mob and
-- relative-level slices, where an abilities breakdown would just be bulk)
local function addTo(agg, f, light)
    agg.size, agg.abil = agg.size or {}, agg.abil or {}
    agg.fights, agg.time = agg.fights + 1, agg.time + f.duration
    agg.dmg, agg.taken, agg.healed = agg.dmg + f.dmg, agg.taken + f.taken, agg.healed + f.healed
    agg.petDmg = (agg.petDmg or 0) + f.petDmg
    agg.kills = agg.kills + f.kills
    if f.kills > 0 then agg.killTime = agg.killTime + f.duration end
    if f.endHP then agg.endHP, agg.endHPn = agg.endHP + f.endHP, agg.endHPn + 1 end
    if f.endMana then agg.endMana, agg.endManaN = agg.endMana + f.endMana, agg.endManaN + 1 end
    if f.takenPct then agg.takenPct, agg.takenPctN = agg.takenPct + f.takenPct, agg.takenPctN + 1 end
    if f.healedPct and f.healedPct > 0 then agg.healedPct = (agg.healedPct or 0) + f.healedPct end
    if f.close then agg.close = agg.close + 1 end
    if f.oom > 0 then agg.oom, agg.oomFights = agg.oom + f.oom, agg.oomFights + 1 end
    if f.died then agg.deaths = agg.deaths + 1 end
    if f.rest then agg.rest, agg.restN = agg.rest + f.rest, agg.restN + 1 end
    if light then return end
    local b = math.min(3, math.max(1, f.mobs))
    agg.size[b] = agg.size[b] or { fights = 0, time = 0, kills = 0, endHP = 0, endHPn = 0, deaths = 0, takenPct = 0, takenPctN = 0 }
    local z = agg.size[b]
    z.fights, z.time, z.kills = z.fights + 1, z.time + f.duration, z.kills + f.kills
    if f.endHP then z.endHP, z.endHPn = z.endHP + f.endHP, z.endHPn + 1 end
    if f.takenPct then z.takenPct, z.takenPctN = z.takenPct + f.takenPct, z.takenPctN + 1 end
    if f.died then z.deaths = z.deaths + 1 end
    for _, sp in ipairs(f.spells) do
        local a = agg.abil[sp.name] or { dmg = 0, fights = 0 }
        a.dmg, a.fights = a.dmg + sp.dmg, a.fights + 1
        agg.abil[sp.name] = a
    end
end

local function recap(f)
    local L, W = ns.LABEL, ns.WHITE
    local parts = { string.format("%s%s|r", W, ns.seconds(f.duration)) }
    if f.dmg > 0 then parts[#parts + 1] = string.format("%s%.1f|r %sdps|r", W, f.dmg / math.max(1, f.duration), L) end
    if f.taken > 0 then
        local share = f.takenPct and string.format(" %s(%d%%)|r", L, math.floor(f.takenPct * 100 + 0.5)) or ""
        parts[#parts + 1] = string.format("%stook|r %s%s|r%s", L, W, ns.shortNumber(f.taken), share)
    end
    if f.endHP then
        local col = f.endHP < 0.35 and ns.RED or (f.endHP < 0.6 and ns.AMBER or W)
        parts[#parts + 1] = string.format("%shp|r %s%d%%|r", L, col, math.floor(f.endHP * 100 + 0.5))
    end
    if f.endMana then parts[#parts + 1] = string.format("%smana|r %s%d%%|r", L, W, math.floor(f.endMana * 100 + 0.5)) end
    if f.mobs > 1 then parts[#parts + 1] = string.format("%s%d|r %smobs|r", W, f.mobs, L) end
    if f.died then parts[#parts + 1] = ns.RED .. "died|r" end
    return table.concat(parts, L .. "  ·  |r")
end

local function finalize(f, data)
    f.dmg = data and data.dmg or f.liveDmg
    f.petDmg = data and data.petDmg or 0
    f.taken = (data and data.taken and data.taken > 0) and data.taken or f.liveTaken
    f.healed = (data and data.healed and data.healed > 0) and data.healed or f.liveHealed
    f.spells = data and data.spells or {}
    f.approx = data == nil
    if f.dmg <= 0 and f.taken <= 0 and f.duration < 2 then return end      -- not a real fight
    f.mobs = math.max(f.mobCount, data and data.enemies or 0, f.xpKills, 1)
    f.kills = f.xpKills > 0 and f.xpKills or ((not f.died) and f.mobs or 0)
    if f.maxHP and f.maxHP > 0 then f.takenPct = f.taken / f.maxHP end
    if not f.endHP and f.hpStart and f.maxHP then                          -- health stayed hidden: estimate
        f.endHP = math.max(0, math.min(1, f.hpStart - (f.taken - f.healed) / f.maxHP))
        f.endHPEstimated = true
    end
    if f.died then f.endHP = nil end                          -- a death is counted as a death, not as "0% health"
    local low = f.minHP or (f.hpStart and f.maxHP and (f.hpStart - f.liveWorst / f.maxHP)) or nil
    f.close = (low ~= nil and low < 0.2) or f.lowWarning
        or (low == nil and f.takenPct ~= nil and (f.taken - f.healed) / f.maxHP >= 0.8) or f.died or false
    if f.maxHP and f.maxHP > 0 then f.healedPct = f.healed / f.maxHP end

    addTo(ns.session.combat, f)
    addTo(ns.char.combat, f)
    local char = ns.char
    if f.level then
        char.byLevel[f.level] = char.byLevel[f.level] or ns.newAggregate()
        addTo(char.byLevel[f.level], f)
    end
    if f.zone then
        char.byZone[f.zone] = char.byZone[f.zone] or ns.newAggregate()
        addTo(char.byZone[f.zone], f, true)
    end
    if f.mobLevel and f.level and f.mobLevel > 0 then
        local diff = f.mobLevel - f.level
        local bucket = diff <= -3 and "lower" or (diff >= 2 and "higher" or "even")
        char.byDiff[bucket] = char.byDiff[bucket] or ns.newAggregate()
        addTo(char.byDiff[bucket], f, true)
    end
    local mob = f.mobName or f.targetName
    if mob and f.mobs == 1 then                                 -- single pulls only, so the mob is unambiguous
        char.mobs[mob] = char.mobs[mob] or ns.newAggregate()
        addTo(char.mobs[mob], f, true)
        char.mobs[mob].level = f.mobLevel or char.mobs[mob].level
        local count = 0
        for _ in pairs(char.mobs) do count = count + 1 end
        if count > 160 then                                     -- keep the list bounded: drop a one-off
            for name, m in pairs(char.mobs) do if m.fights <= 1 and name ~= mob then char.mobs[name] = nil; break end end
        end
    end
    local rec = ns.levelRec and ns.levelRec(f.level)
    if rec then
        rec.fights, rec.fightTime = (rec.fights or 0) + 1, (rec.fightTime or 0) + f.duration
        rec.dmg = (rec.dmg or 0) + f.dmg
        if f.died then rec.deaths = (rec.deaths or 0) + 1 end
    end
    local d = ns.db.diag
    d.fights, d.fightsFromMeter = (d.fights or 0) + 1, (d.fightsFromMeter or 0) + (data and 1 or 0)
    ns.lastFight = f
    if ns.db.showRecap then ns.Feed(recap(f), { tab = "combat", key = "recap", hold = ns.db.recapHold or 8 }) end
    if ns.PanelDirty then ns.PanelDirty() end
end

local function processPending()
    if #pending == 0 or inCombat() then return end
    if dmReady() then
        for _, s in ipairs(newSessionIDs()) do
            local data = readSession(s.id)
            if not data then return end                       -- hidden again; try later
            lastSessionID = s.id
            local f = table.remove(pending, 1)
            if f then f.mobName = s.name; finalize(f, data) end
        end
    end
    local now = GetTime()
    while pending[1] and now - pending[1].endedAt > 8 do       -- the meter has nothing for it
        finalize(table.remove(pending, 1), nil)
    end
end

----------------------------------------------------------------------
-- live tracking
----------------------------------------------------------------------
local function readPct(getter, getterMax, ...)
    local cur, max = N(getter("player", ...)), N(getterMax("player", ...))
    if cur and max and max > 0 then return cur / max, max end
end

local function noteMob(unit)
    if not fight or not unit then return end
    local threat = UnitThreatSituation and UnitThreatSituation("player", unit)
    if not ns.exists(threat) and UnitThreatSituation and UnitExists and B(UnitExists("pet")) then
        threat = UnitThreatSituation("pet", unit)
    end
    if not ns.exists(threat) then return end
    local guid = S(UnitGUID(unit))
    if guid and not fight.mobs[guid] then
        fight.mobs[guid] = true
        fight.mobCount = fight.mobCount + 1
    end
end

ns.On("PLAYER_REGEN_DISABLED", function()
    local now = GetTime()
    fight = { start = now, mobs = {}, mobCount = 0, xpKills = 0, oom = 0,
        liveDmg = 0, liveTaken = 0, liveHealed = 0, liveWorst = 0, level = ns.curLevel,
        maxHP = N(UnitHealthMax("player")) }
    if lastHP and now - lastHP.t < 5 then fight.hpStart = lastHP.pct end
    if lastFightEnd and now - lastFightEnd <= 90 then fight.rest = now - lastFightEnd end
    fight.zone = ns.zone()
    fight.mobLevel, fight.targetName = N(UnitLevel("target")), S(UnitName("target"))
    noteMob("target")
end, "combat:start")

ns.On("PLAYER_REGEN_ENABLED", function()
    if not fight then return end
    local f = fight
    fight = nil
    f.endedAt = GetTime()
    f.duration = f.endedAt - f.start
    lastFightEnd = f.endedAt
    f.awaitingHP, f.awaitingMana = true, true
    table.insert(pending, f)
    ns.After(1.0, processPending, "combat:process")
    ns.After(3.0, processPending, "combat:process2")
end, "combat:end")

ns.On("UNIT_COMBAT", function(unit, action, _, amount)
    if not fight then return end
    unit, action, amount = S(unit), S(action), N(amount)
    if not unit or not amount then return end
    if unit == "player" then
        if action == "WOUND" then
            fight.liveTaken = fight.liveTaken + amount
            fight.liveWorst = math.max(fight.liveWorst, fight.liveTaken - fight.liveHealed)
        elseif action == "HEAL" then fight.liveHealed = fight.liveHealed + amount end
    elseif unit == "target" and action == "WOUND" then
        fight.liveDmg = fight.liveDmg + amount
    end
end, "combat:hits")

ns.On("UNIT_THREAT_LIST_UPDATE", function(unit) noteMob(S(unit)) end, "combat:threat")
ns.On("PLAYER_TARGET_CHANGED", function()
    noteMob("target")
    if fight and not fight.mobLevel then
        fight.mobLevel, fight.targetName = N(UnitLevel("target")), fight.targetName or S(UnitName("target"))
    end
end, "combat:target")

ns.On("UI_ERROR_MESSAGE", function(_, msg)
    msg = S(msg)
    if fight and msg and OOM[msg] then fight.oom = fight.oom + 1 end
end, "combat:oom")

ns.On("PLAYER_DEAD", function()
    local char = ns.char
    if not char then return end
    table.insert(char.deathLog, { t = time(), level = ns.curLevel, zone = ns.zone(), sub = S(GetSubZoneText and GetSubZoneText()) })
    if #char.deathLog > 40 then table.remove(char.deathLog, 1) end
    if fight then fight.died = true
    else
        ns.session.combat.deaths = ns.session.combat.deaths + 1
        char.combat.deaths = char.combat.deaths + 1
    end
end, "combat:death")

function ns.OnXPKill()
    if fight then fight.xpKills = fight.xpKills + 1
    elseif pending[#pending] then pending[#pending].xpKills = pending[#pending].xpKills + 1 end
end

-- ability usage counts (what you actually press), for the abilities view and the forgotten-spells check
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    unit = S(unit)
    if unit ~= "player" and unit ~= "pet" then return end
    local name = ns.spellName(spellID)
    if not name or not ns.session or not ns.char then return end
    if unit == "pet" then name = "Pet: " .. name end
    ns.session.casts[name] = (ns.session.casts[name] or 0) + 1
    ns.char.casts[name] = (ns.char.casts[name] or 0) + 1
end, "combat:casts")

-- health and mana are hidden in combat on this client; sample them whenever they are readable
ns.Every(0.25, function()
    if not ns.db then return end
    local now, d = GetTime(), ns.db.diag
    -- current health is hidden on this client, but the game's own low-health screen warning is a
    -- plain frame whose visibility can be seen: a real "that was close" signal
    if fight and not fight.lowWarning and LowHealthFrame and LowHealthFrame.IsShown then
        local ok, shown = pcall(LowHealthFrame.IsShown, LowHealthFrame)
        if ok and ns.B(shown) then fight.lowWarning = true; d.lowHealthWarningSeen = true end
    end
    local hp = readPct(UnitHealth, UnitHealthMax)
    if hp then
        lastHP = { pct = hp, t = now }
        if fight then fight.minHP = math.min(fight.minHP or 1, hp); d.hpInCombat = true else d.hpOutOfCombat = true end
    end
    local mana
    if UnitPowerType and N((UnitPowerType("player"))) == 0 then
        mana = readPct(UnitPower, UnitPowerMax, 0)
        if mana then lastMana = { pct = mana, t = now } end
    end
    for _, f in ipairs(pending) do                             -- first readable sample after a fight
        if now - f.endedAt <= 3 then
            if f.awaitingHP and hp then f.endHP, f.awaitingHP = hp, nil end
            if f.awaitingMana and mana then f.endMana, f.awaitingMana = mana, nil end
        end
    end
    local lf = ns.lastFight                                     -- fight already folded in: patch late samples
    if lf and lf.endedAt and now - lf.endedAt <= 3 and not lf.endHP and hp and not lf.died and not lf.patched then
        lf.patched = true
        lf.endHP = hp
        for _, agg in ipairs({ ns.session.combat, ns.char.combat }) do agg.endHP, agg.endHPn = agg.endHP + hp, agg.endHPn + 1 end
    end
end, "combat:vitals")

ns.Every(5, processPending, "combat:sweep")

-- one level's fights, with its played time taken from the level log so that
-- "in combat % of played time" is measured against the whole level, not just since its first fight
function ns.LevelAggregate(char, level)
    local agg = char.byLevel and char.byLevel[level]
    if not agg then return nil end
    local rec = char.levels and char.levels[level]
    agg.active = rec and rec.seconds or 0
    return agg
end

ns.OnLogin(function()
    if dmReady() then
        local list = T(DM.GetAvailableCombatSessions()) or {}
        for _, s in ipairs(list) do
            local id = N(s.sessionID)
            if id and id > lastSessionID then lastSessionID = id end      -- ignore fights from before login
        end
    end
    ns.db.diag.damageMeter = dmReady() and true or false
end, "combat:login")

----------------------------------------------------------------------
-- derived numbers for the report and the summary
----------------------------------------------------------------------
function ns.CombatView(agg)
    local v = { fights = agg.fights, kills = agg.kills, deaths = agg.deaths, close = agg.close }
    if agg.fights == 0 then return v end
    v.ttk = agg.kills > 0 and agg.killTime / agg.kills or nil
    v.avgFight = agg.time / agg.fights
    v.dps = agg.time > 0 and agg.dmg / agg.time or nil
    v.petShare = (agg.dmg > 0 and (agg.petDmg or 0) > 0) and agg.petDmg / agg.dmg or nil
    v.combatShare = (agg.active or 0) > 0 and math.min(1, agg.time / agg.active) or nil
    v.rest = agg.restN > 0 and agg.rest / agg.restN or nil
    v.endHP = agg.endHPn > 0 and agg.endHP / agg.endHPn or nil
    v.endMana = agg.endManaN > 0 and agg.endMana / agg.endManaN or nil
    v.takenPct = agg.takenPctN > 0 and agg.takenPct / agg.takenPctN or nil
    v.healedPct = ((agg.healedPct or 0) > 0 and agg.fights > 0) and agg.healedPct / agg.fights or nil
    v.oomFights, v.oom = agg.oomFights, agg.oom
    v.deathsPerHour = (agg.active or 0) > 600 and agg.deaths / (agg.active / 3600) or nil
    v.size = {}
    for b = 1, 3 do
        local z = agg.size[b]
        if z and z.fights > 0 then
            v.size[b] = { fights = z.fights, ttk = z.kills > 0 and z.time / z.kills or nil,
                endHP = z.endHPn > 0 and z.endHP / z.endHPn or nil,
                takenPct = z.takenPctN > 0 and z.takenPct / z.takenPctN or nil, deaths = z.deaths }
        end
    end
    return v
end

-- mobs that cost the most health per fight (at least two fights against them)
function ns.ToughestMobs(limit)
    local list = {}
    for name, m in pairs(ns.char.mobs or {}) do
        if m.fights >= 2 and m.takenPctN > 0 then
            list[#list + 1] = { name = name, level = m.level, fights = m.fights, cost = m.takenPct / m.takenPctN,
                ttk = m.kills > 0 and m.killTime / m.kills or nil, deaths = m.deaths }
        end
    end
    table.sort(list, function(a, b) return a.cost > b.cost end)
    while #list > (limit or 5) do table.remove(list) end
    return list
end

function ns.AbilityView(agg, casts)
    local list, total = {}, 0
    for name, a in pairs(agg.abil) do total = total + a.dmg end
    for name, a in pairs(agg.abil) do
        list[#list + 1] = { name = name, dmg = a.dmg, share = total > 0 and a.dmg / total or 0, casts = casts and casts[name] }
    end
    table.sort(list, function(a, b) return a.dmg > b.dmg end)
    return list, total
end
