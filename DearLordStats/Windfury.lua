-- DearLord Stats : Windfury (shaman)
-- A line under the main window each time Windfury Weapon procs, ranked against every proc this character
-- has had: "TOP 1  812 damage!" for the top three, "top 14  412 damage" for the rest. The fight summary
-- after combat counts the procs of that fight, and the biggest ones are kept.
--
-- How a proc is seen. The combat log is closed to addons and the proc casts no spell the client reports,
-- so it is read from the hits themselves: a proc is the swing that set it off plus two extra attacks, all
-- landing at the same moment. Three or more melee results on the target within 0.3 s, while Windfury is
-- on the weapon, is a proc. The damage shown is all of those hits together.
-- In a group somebody else's swing can land in the same instant and be counted in.
--
-- After every fight the game's own damage meter says whether Windfury did damage; that is compared with
-- what was seen here and kept in the client checks, and it teaches which weapon enchants are Windfury.
local ADDON, ns = ...
local N, S, B = ns.N, ns.S, ns.B

local WINDOW, HITS = 0.3, 3
local KEEP, TOP = 100, 5
local MELEE = { MISS = true, DODGE = true, PARRY = true, BLOCK = true }
local GOLD, SKY = "|cffffd24a", "|cff5fb4ff"
-- temporary weapon enchants a shaman puts on: true is Windfury Weapon, false another imbue.
-- An enchant not listed counts as Windfury until a cast or the damage meter says otherwise.
local SEED = {
    [283] = true, [284] = true, [525] = true, [1669] = true, [2636] = true,
    [29] = false, [6] = false, [1] = false, [503] = false, [1663] = false, [683] = false, [1664] = false,     -- Rockbiter
    [5] = false, [4] = false, [3] = false, [523] = false, [1665] = false, [1666] = false,                      -- Flametongue
    [2] = false, [12] = false, [524] = false, [1667] = false, [1668] = false,                                  -- Frostbrand
}
local IMBUES = { ["Windfury Weapon"] = true, ["Rockbiter Weapon"] = false, ["Flametongue Weapon"] = false, ["Frostbrand Weapon"] = false }

local weapon = {}                       -- the last readable look: mh, oh (enchant ids, false for none), api
local burst                             -- melee results landing together
local demoUntil = 0

-- the spell's own icon when the client hands it out, the classic one otherwise
local iconText
local function icon()
    if iconText then return iconText end
    local id = C_Spell and C_Spell.GetSpellTexture and N((C_Spell.GetSpellTexture(8232)))
    iconText = "|T" .. (id or "Interface\\Icons\\Spell_Nature_Cyclone") .. ":0|t"
    return iconText
end

local function newTally() return { procs = 0, total = 0, best = 0 } end
local tally = newTally()                -- this fight

local function diag()
    local d = ns.db and ns.db.diag
    if not d then return {} end
    if type(d.windfury) ~= "table" or d.windfury.version ~= ns.version then
        local was = type(d.windfury) == "table" and d.windfury or {}
        d.windfury = { version = ns.version, samples = {}, fights = was.fights }
    end
    return d.windfury
end
local function known()
    local db = ns.db
    if not db then return {} end
    db.wfEnchants = db.wfEnchants or {}
    return db.wfEnchants
end
local function verdict(id)
    if not id then return nil end
    local v = known()[id]
    if v == nil then v = SEED[id] end
    return v
end

local function isShaman() return ns.char ~= nil and ns.char.classFile == "SHAMAN" end
local function enabled() return ns.db ~= nil and ns.db.windfury ~= false end

local function lookWeapon()
    if not GetWeaponEnchantInfo then weapon.api = false; return end
    local hasMH, _, _, mhID, hasOH, _, _, ohID = GetWeaponEnchantInfo()
    weapon.api = true
    local m, o = B(hasMH), B(hasOH)
    if m ~= nil then weapon.mh = m and (N(mhID) or 0) or false end       -- 0: enchanted, but the client keeps the id back
    if o ~= nil then weapon.oh = o and (N(ohID) or 0) or false end
end
local function handOn(id)
    if id == nil or id == false then return false end
    if id == 0 then return true end
    return verdict(id) ~= false
end
-- is Windfury on a weapon, as far as can be told
local function active()
    if GetTime() < demoUntil then return true end
    if not (isShaman() and enabled()) then return false end
    if weapon.api == false then return true end
    return handOn(weapon.mh) or handOn(weapon.oh)
end
ns.WindfuryActive = active

----------------------------------------------------------------------
-- records
----------------------------------------------------------------------
local function store()
    local c = ns.char
    if not c then return nil end
    if type(c.windfury) ~= "table" then c.windfury = { procs = 0, ranks = {}, top = {} } end
    local w = c.windfury
    w.procs, w.ranks, w.top = w.procs or 0, w.ranks or {}, w.top or {}
    return w
end
local function sessionStore()
    local s = ns.session
    if not s then return nil end
    if type(s.windfury) ~= "table" then s.windfury = { procs = 0, best = 0, hit = 0 } end
    return s.windfury
end

-- place among everything kept: 1 is the biggest ever. nil when it falls outside the list.
local function rankOf(ranks, total)
    local place = 1
    for i = 1, #ranks do
        if ranks[i] > total then place = i + 1 else break end
    end
    if place > KEEP then return nil end
    return place
end

local function record(b, demo)
    local w, s = store(), sessionStore()
    if demo or not w then return b.demoRank end
    w.procs = w.procs + 1
    if s then
        s.procs = s.procs + 1
        if b.total > s.best then s.best = b.total end
        if b.max > s.hit then s.hit = b.max end
    end
    if b.max > 0 and (not w.hit or b.max > w.hit.amount) then
        w.hit = { amount = b.max, crit = b.maxCrit or nil, at = time(), mob = b.mob }
    end
    if b.total <= 0 then return nil end                       -- the numbers were kept back: a proc, but nothing to rank
    local place = rankOf(w.ranks, b.total)
    if place then
        table.insert(w.ranks, place, b.total)
        while #w.ranks > KEEP do table.remove(w.ranks) end
        if place <= TOP then
            table.insert(w.top, place, { total = b.total, hits = b.hits, crits = b.crits, at = time(), mob = b.mob, level = ns.curLevel })
            while #w.top > TOP do table.remove(w.top) end
        end
    end
    return place
end

----------------------------------------------------------------------
-- the line
----------------------------------------------------------------------
local function detail(b)
    local parts = { b.hits .. (b.hits == 1 and " hit" or " hits") }
    if b.crits > 0 then parts[#parts + 1] = b.crits .. (b.crits == 1 and " crit" or " crits") end
    local missed = b.n - b.hits
    if missed > 0 then parts[#parts + 1] = missed .. " missed" end
    return table.concat(parts, ", ")
end

local function announce(b, place)
    local L, W = ns.LABEL, ns.WHITE
    local text, flash
    local sep = L .. "  ·  |r"
    if b.total <= 0 then                                         -- the numbers were kept back: a proc, but nothing to rate
        text = icon() .. " " .. SKY .. "Windfury|r" .. sep .. L .. detail(b) .. "|r"
        flash = { 0.25, 0.6, 1 }
    elseif place and place <= 3 then
        text = icon() .. " " .. GOLD .. "Windfury  TOP " .. place .. "|r  " .. W .. b.total .. "|r " .. GOLD .. "damage!|r" .. sep .. L .. detail(b) .. "|r"
        flash = { 1, 0.8, 0.2 }
    elseif place then
        text = icon() .. " " .. SKY .. "Windfury|r  " .. W .. "top " .. place .. "|r  " .. W .. b.total .. "|r " .. L .. "damage|r" .. sep .. L .. detail(b) .. "|r"
        flash = { 0.25, 0.6, 1 }
    else
        text = icon() .. " " .. SKY .. "Windfury|r  " .. W .. b.total .. "|r " .. L .. "damage|r" .. sep .. L .. detail(b) .. "  ·  below your top " .. KEEP .. "|r"
        flash = { 0.25, 0.6, 1 }
    end
    local top = b.total > 0 and place ~= nil and place <= 3
    local db = ns.db or {}
    ns.Feed(text, { tab = "combat", key = "windfury", hold = db.windfuryHold or 15, big = db.windfuryBig or 6,
        flash = flash, glow = top and 0.34 or 0.22, pulse = top })
end

local function closeBurst()
    local b = burst
    burst = nil
    if not b then return end
    local d = diag()
    if b.n >= 2 and d.samples and #d.samples < 16 then            -- what hits landing together look like here
        d.samples[#d.samples + 1] = string.format("n=%d span=%.2f hits=%s school=%s proc=%s group=%s mh=%s", b.n, (b.last or b.t0) - b.t0,
            table.concat(b.amounts, ","), table.concat(b.schools, ","), tostring(b.proc or false),
            tostring(B(IsInGroup and IsInGroup()) or false), tostring(weapon.mh))
    end
    if not b.proc then return end
    local t = b.tally
    t.procs, t.total = t.procs + 1, t.total + b.total
    t.mh, t.oh = weapon.mh, weapon.oh
    local place = record(b, b.demo)
    if b.total > t.best then t.best, t.place = b.total, place end
    announce(b, place)
    if ns.PanelDirty then ns.PanelDirty() end
end

local function onResult(action, indicator, amount, school)
    local now = GetTime()
    if burst and now - burst.t0 > WINDOW then closeBurst() end
    if not burst then
        burst = { t0 = now, n = 0, hits = 0, crits = 0, total = 0, max = 0, amounts = {}, schools = {}, tally = tally,
            mob = S(UnitName and UnitName("target")) }
        local mine = burst
        ns.After(WINDOW + 0.05, function() if burst == mine then closeBurst() end end, "windfury:close")
    end
    local b = burst
    b.n, b.last = b.n + 1, now
    b.schools[#b.schools + 1] = tostring(school or "?")
    if action == "WOUND" then
        b.hits = b.hits + 1
        b.amounts[#b.amounts + 1] = tostring(amount or "?")
        if amount then
            b.total = b.total + amount
            if amount > b.max then b.max, b.maxCrit = amount, indicator == "CRITICAL" end
        end
        if indicator == "CRITICAL" then b.crits = b.crits + 1 end
    else
        b.amounts[#b.amounts + 1] = action:lower()
    end
    if b.n >= HITS and b.hits >= 1 then b.proc = true end
end

ns.On("UNIT_COMBAT", function(unit, action, indicator, amount, school)
    if S(unit) ~= "target" then return end
    action = S(action)
    if not action then return end
    school = N(school)
    local melee = (action == "WOUND" and (school == nil or school == 1)) or MELEE[action]
    if not melee or not active() then return end
    onResult(action, S(indicator), N(amount), school)
end, "windfury:hits")

----------------------------------------------------------------------
-- which enchant is Windfury: seen from the shaman's own imbue casts, and from the damage meter
----------------------------------------------------------------------
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if S(unit) ~= "player" or not isShaman() then return end
    local name = ns.spellName(spellID)
    local kind = name and IMBUES[name]
    if kind == nil then return end
    local beforeMH, beforeOH = weapon.mh, weapon.oh
    ns.After(0.7, function()
        lookWeapon()
        local k = known()
        local changed
        if weapon.mh and weapon.mh ~= 0 and weapon.mh ~= beforeMH then k[weapon.mh] = kind; changed = true end
        if weapon.oh and weapon.oh ~= 0 and weapon.oh ~= beforeOH then k[weapon.oh] = kind; changed = true end
        if not changed and weapon.mh and weapon.mh ~= 0 and not weapon.oh then k[weapon.mh] = kind end   -- the same imbue again
        diag().cast = name .. " -> mh=" .. tostring(weapon.mh) .. " oh=" .. tostring(weapon.oh)
    end, "windfury:cast")
end, "windfury:cast")

ns.Every(2, function() if isShaman() then lookWeapon() end end, "windfury:weapon")
ns.On("PLAYER_REGEN_DISABLED", function() if isShaman() then lookWeapon() end end, "windfury:fight")
ns.OnLogin(function()
    if not isShaman() then return end
    lookWeapon()
    diag().weapon = "api=" .. tostring(weapon.api) .. " mh=" .. tostring(weapon.mh) .. " oh=" .. tostring(weapon.oh)
end, "windfury:login")

-- the fight is over: hand its count to the fight summary (a proc still landing writes into the same table)
function ns.WindfuryTake()
    local t = tally
    tally = newTally()
    return t
end

-- the damage meter's list for that fight has arrived: does it agree with what was seen?
function ns.WindfuryCheck(f, fromMeter)
    if not (fromMeter and isShaman() and enabled()) then return end
    local meter = 0
    for _, sp in ipairs(f.spells or {}) do
        if type(sp.name) == "string" and sp.name:find("^Windfury") then meter = meter + (sp.dmg or 0) end
    end
    local t = f.wf
    local seen = t and t.procs or 0
    if meter <= 0 and seen <= 0 then return end
    local d = diag()
    d.fights = d.fights or { agree = 0, missed = 0, extra = 0 }
    local fd = d.fights
    local group = B(IsInGroup and IsInGroup()) or false
    if meter > 0 and seen > 0 then fd.agree = fd.agree + 1
    elseif meter > 0 then fd.missed = fd.missed + 1
    else fd.extra = fd.extra + 1 end
    fd.last = string.format("meter=%d seen=%d total=%d group=%s mh=%s oh=%s", meter, seen, t and t.total or 0, tostring(group), tostring(weapon.mh), tostring(weapon.oh))
    -- an enchant nothing is known about yet: the meter settles it
    local k = known()
    for _, id in ipairs({ t and t.mh or weapon.mh, t and t.oh or weapon.oh }) do
        if id and id ~= 0 and verdict(id) == nil then
            if meter > 0 then k[id] = true elseif not group then k[id] = false end
        end
    end
end

----------------------------------------------------------------------
-- for the report, the slash command and the preview
----------------------------------------------------------------------
function ns.WindfuryView()
    local c = ns.char
    local w = c and type(c.windfury) == "table" and c.windfury or nil
    if not w and not isShaman() then return nil end
    local s = ns.session and type(ns.session.windfury) == "table" and ns.session.windfury or nil
    return { procs = w and w.procs or 0, top = w and w.top or {}, hit = w and w.hit or nil, kept = w and #(w.ranks or {}) or 0,
        sessionProcs = s and s.procs or 0, sessionBest = s and s.best or 0, sessionHit = s and s.hit or 0,
        shaman = isShaman(), on = enabled(), active = isShaman() and enabled() and active() or false,
        fightProcs = tally.procs }
end

function ns.WindfurySay()
    local v = ns.WindfuryView()
    if not v then ns.say("Windfury is tracked on shamans. /dls windfury test shows what a proc looks like."); return end
    if not v.on then ns.say("Windfury tracking is off (Settings)."); return end
    ns.say("Windfury: " .. v.procs .. " procs in all, " .. v.sessionProcs .. " this session"
        .. (v.hit and (", biggest single hit " .. v.hit.amount .. (v.hit.crit and " (crit)" or "")) or ""))
    for i, r in ipairs(v.top) do
        ns.say("  #" .. i .. "  " .. r.total .. " damage, " .. r.hits .. " hits" .. ((r.crits or 0) > 0 and (", " .. r.crits .. " crit") or "")
            .. (r.mob and (" on " .. r.mob) or "") .. (r.level and (" at level " .. r.level) or ""))
    end
    if v.procs == 0 then ns.say("  nothing yet: put Windfury Weapon on and hit something. /dls windfury test shows the line.") end
end

-- three made-up procs, nothing kept
function ns.WindfuryPreview()
    demoUntil = GetTime() + 12
    local shots = { { 0.1, 14, { 212, 198, 240 }, 0 }, { 4, 2, { 305, 498, 331 }, 1 }, { 8, 1, { 520, 610, 0 }, 2 } }
    for _, shot in ipairs(shots) do
        ns.After(shot[1], function()
            local b = { t0 = GetTime(), n = 3, hits = 0, crits = shot[4], total = 0, max = 0, amounts = {}, schools = {}, tally = newTally(),
                proc = true, demo = true, demoRank = shot[2] }
            for _, a in ipairs(shot[3]) do
                if a > 0 then b.hits, b.total = b.hits + 1, b.total + a end
            end
            announce(b, b.demoRank)
        end, "windfury:preview")
    end
end
