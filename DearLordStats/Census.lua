-- DearLord Stats : Census
-- Counts the players of this realm, each character once, to show class, race, level, guild and zone
-- shares. Two sources:
--   passive : every player you see (mouseover, target, nameplates, your group); no queries at all
--   /who    : one query now and then, sent while you are pressing keys or clicking anyway (the game
--             only allows /who from a key press or click), never in combat, never while you use the
--             Who window yourself, and hidden from chat and the Who window. The queries follow a plan:
--             one level at a time; a level with 50 answers (the most /who returns) is split by class,
--             then by race, then by zone, and whatever was checked longest ago goes next.
-- A character seen again moves up to its new level; its guild and zone follow the latest sighting.
--
-- Saved in its own variable, compact (about 25 bytes a character) so the Keeper can carry it:
--   DearLordCensusDB = { version = 1, realms = { ["Realm"] = {
--       c = { ["Name"] = "level,class,race,guild,zone,faction,firstDay,lastDay,src" },   -- numbers index the lists
--       k = { "PALADIN", ... }, r = { "Human", ... }, g = { "Lifers", ... }, z = { "Elwynn Forest", ... },
--       plan = { ['20-20 c-"Paladin"'] = { t = <epoch>, n = <answers> } }, whoOk = <epoch>, count = 812 } } }
local ADDON, ns = ...
local N, S, T, B = ns.N, ns.S, ns.T, ns.B

local MAX_CHARS, PRUNE_TO = 12000, 11000  -- beyond 12,000 the characters seen longest ago make room, down to 11,000
                                          -- in one go (sorting them all on every /who answer was a hitch)
local WHO_EVERY, WHO_MAX_WAIT, WHO_FULL = 15, 10, 50
local FACTIONS = { "Alliance", "Horde", "Neutral" }
local FACTION_ID = { Alliance = 1, Horde = 2, Neutral = 3 }

local function db() return DearLordCensusDB end
local function diag()
    local d = ns.db and ns.db.diag
    if not d then return {} end
    d.census = d.census or {}
    return d.census
end
local function today() return ns.AuctionDay and ns.AuctionDay() or math.floor(time() / 86400) end
local function realmName()
    local r = GetNormalizedRealmName and S(GetNormalizedRealmName())
    if not r and GetRealmName then r = S(GetRealmName()); r = r and r:gsub("%s", "") end
    return r
end
local function realm(create)
    local d = db()
    local name = realmName()
    if not (d and name) then return nil end
    if not d.realms[name] and create then d.realms[name] = { c = {}, k = {}, r = {}, g = {}, z = {}, plan = {}, count = 0 } end
    return d.realms[name]
end

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    if type(DearLordCensusDB) ~= "table" then DearLordCensusDB = { version = 1, realms = {} } end
    DearLordCensusDB.realms = DearLordCensusDB.realms or {}
end, "census:loaded")

----------------------------------------------------------------------
-- one character: stored as a short line of numbers, names kept once per list
----------------------------------------------------------------------
local index = {}                           -- list -> value -> position, rebuilt lazily
local function intern(r, list, value)
    if not value or value == "" then return 0 end
    local key = r[list]
    index[key] = index[key] or {}
    local map = index[key]
    if not next(map) then for i, v in ipairs(key) do map[v] = i end end
    if map[value] then return map[value] end
    key[#key + 1] = value
    map[value] = #key
    return #key
end
local function decode(s)
    local lv, k, rc, g, z, f, first, last, src = s:match("^(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),?(%d*)$")
    if not lv then return nil end
    return tonumber(lv), tonumber(k), tonumber(rc), tonumber(g), tonumber(z), tonumber(f), tonumber(first), tonumber(last), tonumber(src) or 1
end

local function capLevel() return (GetMaxPlayerLevel and N(GetMaxPlayerLevel())) or 60 end
local highest = 0                          -- highest level seen so far (see maxLevel)
local version = 0                          -- bumped on every change, so the view knows when to count again
local added = 0
-- who: name (optionally Name-Realm), level, class token, race, guild, zone, faction; src 1 = seen, 2 = /who
local function record(who, src)
    local r = realm(true)
    if not r or not who.name or who.name == "" then return end
    local name = who.name
    local mine = realmName()
    if mine and name:find("-", 1, true) then
        local n, rl = name:match("^(.-)%-(.+)$")
        if rl == mine then name = n end
    end
    local d = today()
    local old = r.c[name]
    local lv, k, rc, g, z, f, first, last, oldSrc = 0, 0, 0, 0, 0, 0, d, d, src
    if old then lv, k, rc, g, z, f, first, last, oldSrc = decode(old) end
    if not lv then lv, k, rc, g, z, f, first = 0, 0, 0, 0, 0, 0, d end
    if who.level and who.level > 0 and who.level > lv then lv = who.level end        -- levels only go up
    if lv > highest and lv <= capLevel() then highest = lv end
    if who.class then k = intern(r, "k", who.class) end
    if who.race then rc = intern(r, "r", who.race) end
    if who.guild ~= nil then g = intern(r, "g", who.guild) end                         -- "" = left the guild
    if who.zone then z = intern(r, "z", who.zone) end
    if who.faction and FACTION_ID[who.faction] then f = FACTION_ID[who.faction] end
    local line = table.concat({ lv, k, rc, g, z, f, first, d, math.max(src, oldSrc or src) }, ",")
    if line ~= old then
        if not old then r.count = (r.count or 0) + 1; added = added + 1 end
        r.c[name] = line
        version = version + 1
    end
end

-- over the cap: forget the characters seen longest ago
local function prune(r)
    if (r.count or 0) <= MAX_CHARS then return end
    local list = {}
    for name, s in pairs(r.c) do local _, _, _, _, _, _, _, last = decode(s); list[#list + 1] = { name, last or 0 } end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    for i = 1, #list - PRUNE_TO do r.c[list[i][1]] = nil end
    r.count = math.min(#list, PRUNE_TO)
    version = version + 1
end

----------------------------------------------------------------------
-- passive: the players you see
----------------------------------------------------------------------
local lastUnit = {}
local function fromUnit(unit)
    if not (ns.db and ns.db.censusPassive ~= false) then return end
    if not (UnitIsPlayer and B(UnitIsPlayer(unit))) then return end
    local name, rl = UnitName(unit)
    name, rl = S(name), S(rl)
    if not name or name == "" or name == UNKNOWNOBJECT then return end
    local full = (rl and rl ~= "") and (name .. "-" .. rl) or name
    local now = GetTime()
    if lastUnit[full] and now - lastUnit[full] < 60 then return end                   -- a crowd on nameplates: once a minute each
    lastUnit[full] = now
    local _, classToken = UnitClass(unit)
    local race = UnitRace and S((UnitRace(unit)))
    local guild = GetGuildInfo and S((GetGuildInfo(unit)))
    local faction = UnitFactionGroup and S((UnitFactionGroup(unit)))
    local level = N(UnitLevel(unit))
    record({ name = full, level = (level and level > 0) and level or nil, class = S(classToken), race = race,
        guild = guild or "", zone = ns.zone(), faction = faction }, 1)
end
ns.On("UPDATE_MOUSEOVER_UNIT", function() fromUnit("mouseover") end, "census:mouseover")
ns.On("PLAYER_TARGET_CHANGED", function() fromUnit("target") end, "census:target")
ns.On("NAME_PLATE_UNIT_ADDED", function(unit) unit = S(unit); if unit then fromUnit(unit) end end, "census:plate")
ns.On("GROUP_ROSTER_UPDATE", function()
    for i = 1, 4 do fromUnit("party" .. i) end
    for i = 1, 40 do if UnitExists and UnitExists("raid" .. i) then fromUnit("raid" .. i) end end
end, "census:group")

----------------------------------------------------------------------
-- /who: the plan
----------------------------------------------------------------------
local FL = C_FriendList
local function whoApi() return FL and type(FL.SendWho) == "function" and type(FL.GetNumWhoResults) == "function" and type(FL.GetWhoInfo) == "function" end
local pending, lastSent, interval, userWho, sending = nil, 0, WHO_EVERY, 0, false
local className = {}                       -- class token -> the localized name /who filters need
-- the highest level anyone has been seen at: the game's cap may say 60 while this beta stops at 20
local function maxLevel()
    local cap = capLevel()
    if highest == 0 then
        local r = realm()
        for _, s in pairs(r and r.c or {}) do local lv = tonumber(s:match("^(%d+)")); if lv and lv > highest and lv <= cap then highest = lv end end
        local mine = UnitLevel and N(UnitLevel("player")) or 1
        if mine > highest then highest = mine end
    end
    return math.min(cap, math.max(highest, 1))
end
ns.CensusTopLevel = maxLevel

-- the children of a query that came back full: split by class, then race, then zone
local function children(r, filter)
    local out = {}
    local depth = select(2, filter:gsub(" ", ""))
    local lv = tonumber(filter:match("^(%d+)"))
    local cls = filter:match('c%-"(.-)"')
    local rc = filter:match('r%-"(.-)"')
    if depth == 0 then
        local seen = {}
        for token, name in pairs(className) do seen[name] = true end
        for name in pairs(seen) do out[#out + 1] = filter .. ' c-"' .. name .. '"' end
    elseif depth == 1 then
        local races = {}
        for _, s in pairs(r.c) do
            local l, k, race = decode(s)
            if l == lv and race and race > 0 and k and className[r.k[k] or ""] == cls then races[r.r[race]] = true end
        end
        for name in pairs(races) do out[#out + 1] = filter .. ' r-"' .. name .. '"' end
    elseif depth == 2 then
        local zones = {}
        for _, s in pairs(r.c) do
            local l, k, race, _, z = decode(s)
            if l == lv and z and z > 0 and className[r.k[k] or ""] == cls and r.r[race] == rc then zones[r.z[z]] = true end
        end
        for name in pairs(zones) do out[#out + 1] = filter .. ' z-"' .. name .. '"' end
    end
    table.sort(out)
    return out
end

-- the leaf queries of the plan: every level, replaced by its children where it came back full
local function leaves(r)
    local out = {}
    local function walk(filter)
        local p = r.plan[filter]
        if p and p.n and p.n >= WHO_FULL and p.kids then
            for _, child in ipairs(p.kids) do walk(child) end
        else
            out[#out + 1] = filter
        end
    end
    for lv = 1, math.min(capLevel(), maxLevel() + 3) do walk(lv .. "-" .. lv) end      -- a little past the highest seen, to find more
    return out
end
local function nextQuery(r)
    local best, bestT
    for _, filter in ipairs(leaves(r)) do
        local t = (r.plan[filter] and r.plan[filter].t) or 0
        if not bestT or t < bestT then best, bestT = filter, t end
    end
    return best
end
function ns.CensusFreshness()
    local r = realm()
    if not r then return 0, 0 end
    local fresh, total = 0, 0
    for _, filter in ipairs(leaves(r)) do
        total = total + 1
        local p = r.plan[filter]
        if p and p.t and time() - p.t < 86400 then fresh = fresh + 1 end
    end
    return fresh, total
end

local function whoWindowOpen() return (WhoFrame and WhoFrame.IsShown and WhoFrame:IsShown()) or false end
local function canWho()
    if not (ns.db and ns.db.censusWho ~= false and whoApi()) then return false end
    if diag().blocked then return false end
    if pending or InCombatLockdown() or whoWindowOpen() then return false end
    if time() - userWho < 90 then return false end                   -- the player is using /who: stay out of the way
    return time() - lastSent >= interval
end

-- hide our own answers: whatever window shows /who results (the Who window, or this client's own
-- "Looking For Group" list) stops listening while our query runs, and chat stays clean
local muted = {}
local function quiet(on)
    if on then
        local list = {}
        if GetFramesRegisteredForEvent then list = { GetFramesRegisteredForEvent("WHO_LIST_UPDATE") } end
        if FriendsFrame then list[#list + 1] = FriendsFrame end
        local names = {}
        for _, f in ipairs(list) do
            if type(f) == "table" and f ~= ns.eventFrame and not muted[f] and f.UnregisterEvent and pcall(f.UnregisterEvent, f, "WHO_LIST_UPDATE") then
                muted[f] = true
                names[#names + 1] = (f.GetName and S(f:GetName())) or "?"
            end
        end
        ns.diagOnce("whoListeners", function() return table.concat(names, ", ") end)
    else
        for f in pairs(muted) do pcall(f.RegisterEvent, f, "WHO_LIST_UPDATE") end
        muted = {}
    end
end
local WHO_TOTAL = type(WHO_NUM_RESULTS) == "string" and WHO_NUM_RESULTS:match("^(.-)%%d") or nil
if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
        if not pending and time() - lastSent > 3 then return false end
        msg = S(msg)
        if msg and (msg:find("|Hplayer:", 1, true) or (WHO_TOTAL and WHO_TOTAL ~= "" and msg:find(WHO_TOTAL, 1, true))) then return true end
        return false
    end)
end

local function send()
    local r = realm(true)
    if not r then return end
    local filter = nextQuery(r)
    if not filter then return end
    pending, lastSent = { filter = filter, t = time() }, time()
    quiet(true)
    if FL.SetWhoToUi then pcall(FL.SetWhoToUi, true) end
    sending = true
    local ok, err = pcall(FL.SendWho, filter, Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Unknown or nil)
    sending = false
    local d = diag(); d.sent = (d.sent or 0) + 1
    if not ok then
        d.error = tostring(err); pending = nil; quiet(false)
        interval = math.min(300, interval * 2)
        return
    end
    ns.After(WHO_MAX_WAIT, function()
        if pending and pending.filter == filter then                 -- no answer: the server's cooldown, slow down
            pending = nil; quiet(false)
            interval = math.min(300, interval * 2)
            local dd = diag(); dd.noAnswer = (dd.noAnswer or 0) + 1
        end
    end, "census:timeout")
end
function ns.CensusTry() if canWho() then ns.safe("census:who", send) end end

ns.On("WHO_LIST_UPDATE", function()
    if not pending then return end
    local r = realm(true)
    local filter = pending.filter
    pending = nil
    local n, total = FL.GetNumWhoResults()
    n, total = N(n) or 0, N(total) or N(n) or 0
    for i = 1, n do
        local info = T(FL.GetWhoInfo(i))
        if info then
            local token, cname = S(info.filename), S(info.classStr)
            if token and cname then className[token] = cname end
            record({ name = S(info.fullName), level = N(info.level), class = token, race = S(info.raceStr),
                guild = S(info.fullGuildName) or "", zone = S(info.area), faction = UnitFactionGroup and S((UnitFactionGroup("player"))) }, 2)
        end
    end
    local p = r.plan[filter] or {}
    p.t, p.n = time(), math.max(n, total)
    if p.n >= WHO_FULL and not p.kids then
        local kids = children(r, filter)
        if #kids > 0 then p.kids = kids end
    end
    r.plan[filter] = p
    r.whoOk = time()
    interval = WHO_EVERY
    prune(r)
    ns.After(0.2, function() quiet(false) end, "census:quiet")
    local d = diag(); d.answers = (d.answers or 0) + 1; d.last = { filter = filter, n = n, total = total }
    if ns.PanelDirty then ns.PanelDirty() end
end, "census:who")

-- the player's own /who (chat or the Who window) pauses the census for a while
if hooksecurefunc and FL and FL.SendWho then
    hooksecurefunc(FL, "SendWho", function() if not sending then userWho = time() end end)
end
-- the game refused: stop asking and say so once
local function blocked(addon, fn)
    if S(addon) ~= ADDON then return end
    diag().blocked = S(fn) or "?"
    pending = nil; quiet(false)
    ns.Feed(ns.LABEL .. "Census: the game blocked background /who, counting the players you see instead|r", { tab = "census", hold = 10 })
end
ns.On("ADDON_ACTION_BLOCKED", blocked, "census:blocked")
ns.On("ADDON_ACTION_FORBIDDEN", blocked, "census:blocked")

-- ride along on the player's own key presses and clicks (the only moments /who is allowed)
local keys = CreateFrame("Frame", "DearLordStatsCensusKeys", UIParent)
keys:SetSize(1, 1); keys:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
keys:SetScript("OnKeyDown", function() ns.CensusTry() end)
ns.OnLogin(function()
    if keys.EnableKeyboard and not InCombatLockdown() then
        keys:EnableKeyboard(true)
        if keys.SetPropagateKeyboardInput then keys:SetPropagateKeyboardInput(true) end      -- every key still reaches the game
    end
    if WorldFrame and WorldFrame.HookScript then WorldFrame:HookScript("OnMouseDown", function() ns.CensusTry() end) end
    for i = 1, 13 do                                                  -- the localized class names /who filters need
        local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and T(C_CreatureInfo.GetClassInfo(i))
        if info and S(info.classFile) and S(info.className) then className[info.classFile] = info.className end
    end
    local r = realm()
    if r then prune(r) end
end, "census:login")

----------------------------------------------------------------------
-- the numbers for the Census tab
----------------------------------------------------------------------
local viewCache, viewKey, viewVersion, viewAt = nil, nil, -1, 0
-- filter: faction ("both" | "Alliance" | "Horde"), lo, hi (levels), days (seen within, 0 = any time)
function ns.CensusView(f)
    local key = table.concat({ f.faction or "both", f.lo or 0, f.hi or 999, f.days or 0 }, ":")
    if viewCache and viewKey == key and (viewVersion == version or GetTime() - viewAt < 10) then return viewCache end
    local r = realm()
    local out = { total = 0, all = r and r.count or 0, classes = {}, races = {}, raceList = {}, levels = {}, guilds = {}, zones = {},
        maxLevel = maxLevel(), whoOk = r and r.whoOk, newToday = 0 }
    if r then
        local d = today()
        local fid = FACTION_ID[f.faction or ""]
        local byClass, byRace, byGuild, byZone = {}, {}, {}, {}
        for _, s in pairs(r.c) do
            local lv, k, rc, g, z, fac, first, last = decode(s)
            if lv and lv >= (f.lo or 0) and lv <= (f.hi or 999) and lv > 0 and (not fid or fac == fid) and ((f.days or 0) == 0 or d - last < f.days) then
                out.total = out.total + 1
                if first == d then out.newToday = out.newToday + 1 end
                local token = r.k[k] or "?"
                byClass[token] = (byClass[token] or 0) + 1
                local race = r.r[rc] or "?"
                byRace[race] = byRace[race] or { n = 0 }
                byRace[race].n = byRace[race].n + 1
                byRace[race][token] = (byRace[race][token] or 0) + 1
                out.levels[lv] = (out.levels[lv] or 0) + 1
                local gname = r.g[g]
                if gname and gname ~= "" then
                    local e = byGuild[gname] or { name = gname, n = 0, lv = 0, top = 0 }
                    e.n, e.lv = e.n + 1, e.lv + lv
                    if lv >= out.maxLevel then e.top = e.top + 1 end
                    byGuild[gname] = e
                end
                local zname = r.z[z]
                if zname then
                    local e = byZone[zname] or { name = zname, n = 0, lv = 0 }
                    e.n, e.lv = e.n + 1, e.lv + lv
                    byZone[zname] = e
                end
            end
        end
        for token, n in pairs(byClass) do out.classes[#out.classes + 1] = { token = token, n = n } end
        table.sort(out.classes, function(a, b) return a.n > b.n end)
        for name, e in pairs(byRace) do e.name = name; out.raceList[#out.raceList + 1] = e end
        table.sort(out.raceList, function(a, b) return a.n > b.n end)
        out.races = byRace
        for _, e in pairs(byGuild) do out.guilds[#out.guilds + 1] = e end
        table.sort(out.guilds, function(a, b) return a.n > b.n end)
        for _, e in pairs(byZone) do out.zones[#out.zones + 1] = e end
        table.sort(out.zones, function(a, b) return a.n > b.n end)
    end
    viewCache, viewKey, viewVersion, viewAt = out, key, version, GetTime()
    return out
end
function ns.CensusClassName(token)
    return className[token] or (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or (token:sub(1, 1) .. token:sub(2):lower())
end
function ns.CensusClassColor(token)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c and N(c.r) then return c.r, c.g, c.b end
    local fallback = { WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 }, ROGUE = { 1, 0.96, 0.41 },
        PRIEST = { 1, 1, 1 }, SHAMAN = { 0, 0.44, 0.87 }, MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 }, DRUID = { 1, 0.49, 0.04 } }
    local f = fallback[token] or { 0.8, 0.8, 0.8 }
    return f[1], f[2], f[3]
end
function ns.CensusStatus()
    local fresh, total = ns.CensusFreshness()
    local d = diag()
    return { api = whoApi(), on = ns.db and ns.db.censusWho ~= false, blocked = d.blocked, pending = pending and pending.filter,
        next = math.max(0, interval - (time() - lastSent)), fresh = fresh, leaves = total, last = d.last, added = added }
end
