-- DearLord Stats : Auction prices
-- The addon's own auction-house scan: when the auction house is open it asks the server for the full
-- list of auctions (C_AuctionHouse.ReplicateItems, allowed once every 15 minutes), keeps the lowest
-- buyout per item, and shows it in item tooltips and on the Loot tab. Prices are kept per realm AND
-- faction, because Horde and Alliance have separate auction houses on this server.
--
-- Saved in its own variable, DearLordAuctionDB, plain numbers and strings only:
--   { version = 1, lastRequest = <epoch>, lastByKey = { ["Realm-Horde"] = <epoch> }, throttle = "key" | "account" | nil,
--     realms = { ["Realm-Horde"] = { scanned = <epoch>, day = 2456, auctions = 4812, count = 1846,
--                items = { [id] = { p = <min unit buyout>, n = <units seen>, d = <scan day>, name = "Light Hide",
--                                   k = <most common stack size, when not 1>,
--                                   t = <epoch the price was last seen>,
--                                   h = "day:min:median day:min:median" (newest first) } } } } }
-- Between full scans the entry of an item is brought up to date whenever a search shows its listings.
-- (2.6 and older kept a third number, the highest buyout: outlier listings made it useless, and it
--  only took up room, so it is dropped)
local ADDON, ns = ...
local N, S, T, B = ns.N, ns.S, ns.T, ns.B

ns.AH_CUT = 0.05                                             -- the auction house keeps 5% of a sale
local DAY0 = 1577836800                                      -- 2020-01-01: day numbers count from here
local CHUNK, HISTORY_MAX, HISTORY_DAYS, KEEP_DAYS, THROTTLE = 500, 8, 28, 30, 900
local SIGHT_ROWS, USUAL_DAYS = 500, 7                          -- listings read from one search; days behind the usual price

local ahOpen = false
local armed = false                                          -- an automatic scan is due: sent on the next key press
local ahKey                                                  -- database key of the auction house that is open
local scan = { state = "idle" }
local openedAt = 0                                           -- when the auction house was opened
local key                                                    -- "Realm-Faction" of this character

ns.AH_MODIFIERS = { { key = "alt", name = "Alt" }, { key = "shift", name = "Shift" }, { key = "ctrl", name = "Ctrl" },
    { key = "always", name = "Always" }, { key = "never", name = "Never" } }

local function db() return DearLordAuctionDB end
local function diag()
    local d = ns.db and ns.db.diag
    if not d then return {} end
    d.ah = d.ah or {}
    return d.ah
end

function ns.AuctionDay(t) return math.floor(((t or time()) - DAY0) / 86400) end
function ns.AuctionNet(price, count) return math.floor(price * (1 - ns.AH_CUT)) * (count or 1) end

function ns.AuctionKey()
    if key then return key end
    local realm = GetNormalizedRealmName and S(GetNormalizedRealmName())
    if not realm and GetRealmName then realm = S(GetRealmName()); realm = realm and realm:gsub("%s", "") end
    local faction = UnitFactionGroup and S(UnitFactionGroup("player"))
    if realm and faction and faction ~= "Neutral" then key = realm .. "-" .. faction end
    return key
end

function ns.AuctionRealmName() local k = ns.AuctionKey(); return k and k:match("^(.-)%-") end
function ns.AuctionOtherKey()                                -- the other faction's auction house on this realm
    local k = ns.AuctionKey()
    if not k then return nil end
    local realm, faction = k:match("^(.-)%-(%a+)$")
    return realm and (realm .. "-" .. (faction == "Horde" and "Alliance" or "Horde"))
end
function ns.AuctionNeutralKey() local r = ns.AuctionRealmName(); return r and (r .. "-Neutral") end

local function realmData(create, k)
    local d = db(); k = k or ns.AuctionKey()
    if not (d and k) then return nil end
    if not d.realms[k] and create then d.realms[k] = { items = {}, count = 0 } end
    return d.realms[k]
end

-- a goblin auctioneer belongs to no faction; the window then talks to the neutral auction house
local NEUTRAL_ZONES = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true }
local function openKey()
    if UnitExists and UnitExists("npc") and UnitFactionGroup then
        local f = S(UnitFactionGroup("npc"))
        if f == nil or f == "Neutral" then return ns.AuctionNeutralKey() end
        return ns.AuctionKey()
    end
    local sub = GetSubZoneText and S(GetSubZoneText())
    if sub and NEUTRAL_ZONES[sub] then return ns.AuctionNeutralKey() end
    return ns.AuctionKey()
end

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    if type(DearLordAuctionDB) ~= "table" then DearLordAuctionDB = { version = 1, realms = {} } end
    DearLordAuctionDB.realms = DearLordAuctionDB.realms or {}
    DearLordAuctionDB.version = DearLordAuctionDB.version or 1
    if DearLordAuctionDB.version < 2 then                     -- 2.7: history without the highest buyout
        for _, r in pairs(DearLordAuctionDB.realms) do
            for _, e in pairs(r.items or {}) do
                if e.h then e.h = e.h:gsub("(%d+:%d+:%d+):%d+", "%1") end
            end
        end
        DearLordAuctionDB.version = 2
    end
end, "ah:loaded")
ns.OnLogin(function() ns.AuctionKey() end, "ah:key")

----------------------------------------------------------------------
-- prices
----------------------------------------------------------------------
function ns.HasAuctionPrices()
    local r = realmData()
    return r ~= nil and (r.count or 0) > 0
end

-- price per unit in copper, age in days, units seen then, age in seconds (nil for entries older than 2.17)
function ns.AuctionPriceByID(id, k)
    local r = id and realmData(false, k)
    local e = r and r.items[id]
    if not e or not e.p or e.p <= 0 then return nil end
    return e.p, math.max(0, ns.AuctionDay() - (e.d or ns.AuctionDay())), e.n or 0, e.t and math.max(0, time() - e.t) or nil
end
function ns.AuctionPrice(link)
    local id = link and tonumber(tostring(link):match("Hitem:(%d+)"))
    return ns.AuctionPriceByID(id)
end
function ns.AuctionAgeText(days, secs)
    if secs and secs < 86400 then                            -- seen within a day: say how long ago
        if secs < 90 then return "just now" end
        if secs < 3600 then return math.floor(secs / 60 + 0.5) .. " min ago" end
        return math.floor(secs / 3600 + 0.5) .. " h ago"
    end
    if not days or days <= 0 then return "today" end
    if days == 1 then return "yesterday" end
    return days .. " days ago"
end

function ns.AuctionItemName(id, e)
    local name = e and e.name
    if not name and C_Item and C_Item.GetItemNameByID then name = S(C_Item.GetItemNameByID(id)) end
    return name
end

-- items of any house on this realm whose name contains the query; at most `limit`, sorted by name.
-- p/n/d/med/max/trend/usual describe your own house, neutral/other the lowest buyout at the two others.
function ns.AuctionSearch(query, limit)
    local keys = { ns.AuctionKey(), ns.AuctionNeutralKey(), ns.AuctionOtherKey() }
    local out, seen = {}, {}
    query = (query or ""):lower()
    for _, k in ipairs(keys) do
        local r = k and realmData(false, k)
        if r then
            for id, e in pairs(r.items) do
                if not seen[id] then
                    local name = ns.AuctionItemName(id, e)
                    if name and (query == "" or name:lower():find(query, 1, true)) then
                        seen[id] = true
                        local own = realmData(false, keys[1]); local oe = own and own.items[id]
                        local h = ns.AuctionHistory(id)
                        out[#out + 1] = { id = id, name = name, p = oe and oe.p, n = oe and oe.n, d = oe and oe.d,
                            med = h[1] and h[1].med or (oe and oe.p), max = h[1] and h[1].max or (oe and oe.p),
                            trend = oe and ns.AuctionTrend(id) or nil, usual = oe and ns.AuctionUsual(id) or nil, days = #h,
                            neutral = (ns.AuctionPriceByID(id, keys[2])), other = (ns.AuctionPriceByID(id, keys[3])) }
                        if #out >= (limit or 60) * 4 then break end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    while #out > (limit or 60) do out[#out] = nil end
    return out
end

----------------------------------------------------------------------
-- the scan
----------------------------------------------------------------------
local function api() return C_AuctionHouse and type(C_AuctionHouse.ReplicateItems) == "function"
    and type(C_AuctionHouse.GetNumReplicateItems) == "function" and type(C_AuctionHouse.GetReplicateItemInfo) == "function" end

-- the game allows one full scan per 15 minutes for the whole account, whichever addon asks: at launch a
-- request two minutes after Auctionator's Full Scan went unanswered. Auctionator's last scan counts too.
local function auctionatorLast()
    local A = Auctionator
    local st = type(A) == "table" and type(A.SavedState) == "table" and A.SavedState or nil
    return st and N(st.TimeOfLastReplicateScan) or 0
end
local function waitFor()
    local d = db()
    if not d then return 0 end
    return math.max(0, THROTTLE - (time() - math.max(d.lastRequest or 0, auctionatorLast())))
end

-- The auction house takes one request at a time. One sent while it is still busy (it is, for a moment after
-- the window opens and after every search) is put in a single waiting slot, and thrown away when the next
-- request comes: the full list was asked for and never arrived. So a scan waits for the house to be free.
local function ready()
    local f = C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady
    if type(f) ~= "function" then return true end
    local ok, r = pcall(f)
    return not ok or B(r) ~= false
end

-- the last requests, newest first: how each was asked, what the auction house answered, how it ended
local LOG_MAX = 12
local function logRequest(how)
    local d = diag()
    d.log = d.log or {}
    local e = { at = time(), how = how or "?", open = time() - openedAt, ready = ready() and "yes" or "no", ev = "" }
    table.insert(d.log, 1, e)
    while #d.log > LOG_MAX do d.log[#d.log] = nil end
    return e
end
local function logOut(out)
    local e = scan.log
    if not e or e.out then return end
    e.out, e.secs = out, time() - e.at
end

local function abort(why)
    logOut(why or "stopped")
    scan = { state = "idle" }
    if why then ns.Feed(ns.LABEL .. "Auction scan|r  " .. why, { tab = "prices", key = "ahscan", hold = 8 }) end
    if ns.PanelDirty then ns.PanelDirty() end
end

-- "day:min:median:max ...", newest first, one entry per day, capped (older entries may be "day:min" only)
function ns.AuctionHistory(id, k)
    local r = id and realmData(false, k)
    local e = r and r.items[id]
    local out = {}
    for token in (e and e.h or ""):gmatch("%S+") do
        local d, mn, md, mx = token:match("^(%d+):(%d+):?(%d*):?(%d*)$")
        if d then out[#out + 1] = { day = tonumber(d), min = tonumber(mn), med = tonumber(md) or tonumber(mn), max = tonumber(mx) or tonumber(mn) } end
    end
    return out, e
end
local function pushHistory(e, today, mn, md)
    local out, seen = { today .. ":" .. mn .. ":" .. md }, { [today] = true }
    for token in (e.h or ""):gmatch("%S+") do
        local d = tonumber(token:match("^(%d+):"))
        if d and not seen[d] and today - d <= HISTORY_DAYS and #out < HISTORY_MAX then out[#out + 1] = token; seen[d] = true end
    end
    e.h = table.concat(out, " ")
end

-- change of the lowest buyout since the previous scan day, in percent (nil without two days of data)
function ns.AuctionTrend(id, k)
    local h = ns.AuctionHistory(id, k)
    if #h < 2 or not h[2].min or h[2].min <= 0 then return nil end
    return math.floor((h[1].min - h[2].min) / h[2].min * 100 + 0.5), h[1].min, h[2].min
end
function ns.AuctionTrendText(pct)
    if not pct or math.abs(pct) < 1 then return nil end
    return (pct > 0 and ns.GREEN .. "+" or ns.RED) .. pct .. "%|r"
end
-- the usual price: the middle one of the last week's daily lows (nil with fewer than three days known).
-- One day's low can be a single odd listing; this says what the item normally goes for.
function ns.AuctionUsual(id, k)
    local h, lows = ns.AuctionHistory(id, k), {}
    for i = 1, math.min(#h, USUAL_DAYS) do
        if h[i].min and h[i].min > 0 then lows[#lows + 1] = h[i].min end
    end
    if #lows < 3 then return nil end
    table.sort(lows)
    return lows[math.ceil(#lows / 2)], #lows
end
-- what one unit can be counted on to bring: the lowest buyout, but no more than the usual price, so a
-- single odd listing does not promise a profit. Returns that, the lowest, and the usual (when known).
function ns.AuctionFairPrice(id, k)
    local p = ns.AuctionPriceByID(id, k)
    if not p then return nil end
    local usual = ns.AuctionUsual(id, k)
    return (usual and usual < p) and usual or p, p, usual
end
-- the lowest buyout against the usual price, in percent (nil until the usual price is known)
function ns.AuctionVsUsual(id, k)
    local p = ns.AuctionPriceByID(id, k)
    local usual, days = ns.AuctionUsual(id, k)
    if not (p and usual and usual > 0) then return nil end
    return math.floor((p - usual) / usual * 100 + 0.5), usual, days
end

local function commit()
    local r = realmData(true, scan.key)
    if not r then abort("no realm or faction known"); return end
    local today, items, n = ns.AuctionDay(), r.items, 0
    for id, a in pairs(scan.agg) do
        local e = items[id] or {}
        if not e.h and e.p and e.d and e.d < today then e.h = e.d .. ":" .. e.p end   -- an entry from before history was kept
        table.sort(a.list)
        local med = a.list[math.ceil(#a.list / 2)] or a.p
        e.p, e.n, e.d, e.t = a.p, a.n, today, time()
        if a.name then e.name = a.name end
        local k, best = nil, 0                                   -- the stack size most sellers use
        for size, times in pairs(a.k or {}) do if times > best or (times == best and size > (k or 0)) then k, best = size, times end end
        e.k = (k and k > 1) and k or nil
        pushHistory(e, today, a.p, med)
        items[id] = e
    end
    for id, e in pairs(items) do
        if (e.d or 0) < today - KEEP_DAYS then items[id] = nil else n = n + 1 end
    end
    r.scanned, r.day, r.auctions, r.count = time(), today, scan.n, n
    if scan.log then scan.log.rows = scan.n end
    logOut(scan.foreign and "read (another addon's list)" or "read")
    if db() then db().lastRead = db().lastRequest end          -- whoever asked, a list arrived: our request is answered or spent
    local d = diag(); d.lastScan = { at = time(), rows = scan.n, items = n, secs = time() - (scan.requestedAt or time()) }
    ns.Feed(ns.LABEL .. "Auction scan|r  " .. ns.WHITE .. n .. " items|r" .. ns.LABEL .. "  ·  " .. scan.n .. " auctions|r", { tab = "prices", key = "ahscan", hold = 10 })
    scan = { state = "idle" }
    if ns.AdviceDirty then ns.AdviceDirty(true) end
    if ns.PanelDirty then ns.PanelDirty() end
end

-- one row of the replicated list: only count, buyout and item id are guaranteed to be there at once
local function readRow(i)
    local r = { C_AuctionHouse.GetReplicateItemInfo(i) }
    if type(r[1]) == "table" then return N(r[1].count), N(r[1].buyoutPrice), N(r[1].itemID), r, S(r[1].name) end
    return N(r[3]), N(r[10]), N(r[17]), r, S(r[1])
end

local function collectChunk()
    if scan.state ~= "collecting" then return end
    local n = N(C_AuctionHouse.GetNumReplicateItems()) or 0
    if n == 0 then abort("the list vanished (auction house closed?)"); return end
    local last = math.min(scan.i + CHUNK - 1, scan.n - 1)
    for i = scan.i, last do
        local count, buyout, id, raw, name = readRow(i)
        if i == 0 then
            ns.diagOnce("ahRow", function()
                local v = raw[10]
                return { arity = select("#", C_AuctionHouse.GetReplicateItemInfo(0)), first = type(raw[1]), buyoutType = type(v),
                    buyoutSecret = (v ~= nil and issecretvalue and issecretvalue(v)) and "yes" or "no", sample = ns.dump(raw) }
            end)
        end
        if count and id and buyout and buyout > 0 and count > 0 then
            local unit = math.floor(buyout / count)
            local a = scan.agg[id]
            if not a then a = { p = unit, n = count, list = {}, k = {} }; scan.agg[id] = a; scan.priced = scan.priced + 1
            else a.n = a.n + count; if unit < a.p then a.p = unit end end
            a.list[#a.list + 1] = unit
            a.k[count] = (a.k[count] or 0) + 1
            if name and name ~= "" and not a.name then a.name = name end
        elseif i < 50 then scan.blank = scan.blank + 1 end
    end
    scan.i = last + 1
    if scan.i >= 50 and scan.priced == 0 and scan.blank >= 50 then
        abort("prices are hidden from addons on this client"); return
    end
    if scan.i >= scan.n then commit(); return end
    if scan.i % 2000 == 0 then
        ns.Feed(ns.LABEL .. "Auction scan|r  " .. ns.WHITE .. scan.i .. " / " .. scan.n .. "|r", { tab = "prices", key = "ahscan", hold = 4 })
    end
    ns.After(0, collectChunk, "ah:chunk")
end

ns.On("REPLICATE_ITEM_LIST_UPDATE", function()
    local d = diag(); d.updates = (d.updates or 0) + 1
    local n = N(C_AuctionHouse.GetNumReplicateItems()) or 0
    -- a list nobody here is waiting for: the late answer to a request this addon gave up on, or another addon's
    -- full scan (Auctionator). Take it unless this house was read in the last 15 minutes: the list stays in the
    -- client and the event fires again whenever item data loads, and must not be read over and over.
    if scan.state == "idle" and ahOpen and ahKey and n > 0 and db() then
        local house = realmData(false, ahKey)
        local recent = house and house.scanned and time() - house.scanned < THROTTLE
        local unread = time() - (db().lastRequest or 0) < THROTTLE and db().lastRead ~= db().lastRequest
        if unread or not recent then
            scan = { state = "requested", requestedAt = unread and db().lastRequest or time(), key = ahKey, late = unread, foreign = not unread }
            if unread then
                d.late = (d.late or 0) + 1
                if d.log and d.log[1] then d.log[1].late = time() - d.log[1].at end
            else d.foreign = (d.foreign or 0) + 1 end
        end
    end
    if scan.state ~= "requested" then return end
    d.firstUpdate = { rows = n, secs = time() - (scan.requestedAt or time()) }
    if n == 0 then return end                                 -- it fires again when the list has arrived
    scan.state, scan.n, scan.i, scan.agg, scan.priced, scan.blank = "collecting", n, 0, {}, 0, 0
    collectChunk()
end, "ah:replicate")

----------------------------------------------------------------------
-- prices seen on screen
----------------------------------------------------------------------
-- Every search in the auction house shows current listings, and the price kept from the last full
-- scan is brought up to date from them. A complete listing replaces the entry. A partial one (more
-- rows not loaded yet, or one variant of an item that has several) can only lower it, because
-- cheaper auctions may be out of sight.
local function redrawTooltip(id)
    local tt = GameTooltip
    if not (tt and tt.IsShown and tt:IsShown()) then return end
    if id and tt.dlsAhItem ~= id then return end
    if not id and not tt.dlsAhShown then return end
    local owner = tt.GetOwner and tt:GetOwner()
    local enter = owner and owner.GetScript and owner:GetScript("OnEnter")
    if enter then tt.dlsAhInstance = nil; pcall(enter, owner) end
end

local function observe(id, unit, units, med, complete, name, how)
    id, unit = N(id), N(unit)
    if not (ahOpen and ahKey and id and unit and unit > 0) then return false end
    local r = realmData(true, ahKey)
    if not r then return false end
    local today, e = ns.AuctionDay(), r.items[id]
    units = math.max(1, N(units) or 1)
    if e and e.p and e.p > 0 and not complete and unit >= e.p then return false end
    local changed = not (e and e.p == unit and (not complete or e.n == units))
    if not e then e = {}; r.items[id] = e; r.count = (r.count or 0) + 1 end
    if not e.h and e.p and e.d and e.d < today then e.h = e.d .. ":" .. e.p end       -- an entry from before history was kept
    if not complete and e.d == today then units = math.max(units, e.n or 0) end
    e.p, e.n, e.d, e.t = unit, units, today, time()
    if name and name ~= "" and not e.name then e.name = name end
    pushHistory(e, today, unit, math.max(unit, N(med) or unit))
    local d = diag(); d.sights = (d.sights or 0) + 1
    ns.diagOnce("ahSight", function() return how .. " item=" .. id .. " unit=" .. unit .. " units=" .. units .. " complete=" .. tostring(complete) end)
    if changed then
        if ns.PanelDirty then ns.PanelDirty() end
        redrawTooltip(id)
    end
    return changed
end

local function middle(list) table.sort(list); return list[math.ceil(#list / 2)] end

-- the listings of one item sold piece by piece
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    local AH = C_AuctionHouse
    itemKey = T(itemKey)
    if not (ahOpen and itemKey and AH and AH.GetNumItemSearchResults and AH.GetItemSearchResultInfo) then return end
    local id, n = N(itemKey.itemID), N(AH.GetNumItemSearchResults(itemKey)) or 0
    if not id or n == 0 then return end
    local low, units, list = nil, 0, {}
    for i = 1, math.min(n, SIGHT_ROWS) do
        local info = T(AH.GetItemSearchResultInfo(itemKey, i))
        local buyout, qty = info and N(info.buyoutAmount), math.max(1, info and N(info.quantity) or 1)
        if buyout and buyout > 0 then                          -- auctions with a bid only have no price to compare
            local unit = math.floor(buyout / qty)
            if not low or unit < low then low = unit end
            units = units + qty
            list[#list + 1] = unit
        end
    end
    if not low then return end
    local full = n <= SIGHT_ROWS and AH.HasFullItemSearchResults and B(AH.HasFullItemSearchResults(itemKey)) == true
    local variant = (N(itemKey.itemSuffix) or 0) ~= 0          -- "of the Bear": other suffixes share the item id
    observe(id, low, units, middle(list), full and not variant, nil, "item")
end, "ah:itemResults")

-- the listings of a stackable item, one row per price
ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    local AH = C_AuctionHouse
    local id = N(itemID)
    if not (ahOpen and id and AH and AH.GetNumCommoditySearchResults and AH.GetCommoditySearchResultInfo) then return end
    local n = N(AH.GetNumCommoditySearchResults(id)) or 0
    local low, units, list = nil, 0, {}
    for i = 1, math.min(n, SIGHT_ROWS) do
        local info = T(AH.GetCommoditySearchResultInfo(id, i))
        local unit, qty = info and N(info.unitPrice), math.max(1, info and N(info.quantity) or 1)
        if unit and unit > 0 then
            if not low or unit < low then low = unit end
            units = units + qty
            list[#list + 1] = unit
        end
    end
    if not low then return end
    local full = n <= SIGHT_ROWS and AH.HasFullCommoditySearchResults and B(AH.HasFullCommoditySearchResults(id)) == true
    observe(id, low, units, middle(list), full, nil, "commodity")
end, "ah:commodityResults")

-- the search list itself: one row per item with its lowest price and how many are up
local function browsed(results)
    results = T(results)
    if not (ahOpen and results) then return end
    local agg = {}
    for i = 1, math.min(#results, SIGHT_ROWS * 4) do
        local row = T(results[i])
        local k = row and T(row.itemKey)
        local id, price = k and N(k.itemID), row and N(row.minPrice)
        if id and price and price > 0 then
            local a = agg[id]
            if not a then a = { p = price, n = 0 }; agg[id] = a end
            if price < a.p then a.p = price end
            a.n = a.n + math.max(1, N(row.totalQuantity) or 1)
            if (N(k.itemSuffix) or 0) ~= 0 then a.variant = true end
        end
    end
    for id, a in pairs(agg) do observe(id, a.p, a.n, nil, not a.variant, nil, "browse") end
end
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    if C_AuctionHouse and C_AuctionHouse.GetBrowseResults then browsed(C_AuctionHouse.GetBrowseResults()) end
end, "ah:browse")
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(added) browsed(added) end, "ah:browseAdded")

-- clients with the old auction house: one page of auctions, complete when it is the only page
ns.On("AUCTION_ITEM_LIST_UPDATE", function()
    if not (ahOpen and GetNumAuctionItems and GetAuctionItemInfo) then return end
    local batch, total = GetNumAuctionItems("list")
    batch, total = N(batch) or 0, N(total) or 0
    if batch == 0 or batch > SIGHT_ROWS then return end       -- nothing, or a whole-house list: that is the full scan's job
    local agg = {}
    for i = 1, batch do
        local r = { GetAuctionItemInfo("list", i) }
        local count, buyout, id = N(r[3]), N(r[10]), N(r[17])
        if count and count > 0 and buyout and buyout > 0 and id then
            local unit = math.floor(buyout / count)
            local a = agg[id]
            if not a then a = { p = unit, n = 0, list = {}, name = S(r[1]) }; agg[id] = a end
            if unit < a.p then a.p = unit end
            a.n = a.n + count
            a.list[#a.list + 1] = unit
        end
    end
    for id, a in pairs(agg) do observe(id, a.p, a.n, middle(a.list), batch >= total, a.name, "page") end
end, "ah:page")

local RESENDS = 2                                            -- times a request the auction house threw away is sent again
local function start()
    local d = db(); if not d then return end
    local k = ahKey or ns.AuctionKey()
    d.lastRequest, d.lastRequestKey = time(), k               -- the throttle is spent whether or not the answer comes
    d.lastByKey = d.lastByKey or {}
    d.lastByKey[k] = time()
    local entry, resent = scan.log, scan.resent or 0
    if entry then
        entry.waited = scan.queuedAt and (time() - scan.queuedAt) or 0
        entry.sentReady = ready() and "yes" or "no"
        entry.ev = entry.ev .. ">"                              -- what follows was answered after the request went out
    end
    scan = { state = "requested", requestedAt = time(), key = k, log = entry, resent = resent }
    local ok, err = pcall(C_AuctionHouse.ReplicateItems)
    if not ok then diag().error = tostring(err); abort("refused: " .. tostring(err)); return end
    -- no answer in 30 s: say so, but keep listening. The 15-minute throttle is spent either way, and the list
    -- has been seen to arrive late; the wait ends when the auction house closes.
    ns.After(30, function()
        if scan.state ~= "requested" then return end
        local dg = diag(); dg.slow = (dg.slow or 0) + 1; dg.slowAt = time()
        ns.Feed(ns.LABEL .. "Auction scan|r  no answer from the server yet, still waiting", { tab = "prices", key = "ahscan", hold = 8 })
    end, "ah:timeout")
    -- a minute of silence: stop showing "waiting" and offer a new try. A list that still comes is taken anyway
    -- (REPLICATE_ITEM_LIST_UPDATE accepts a late answer while the request is unread).
    local asked = time()
    ns.After(60, function()
        if scan.state ~= "requested" or scan.requestedAt ~= asked then return end
        local dg = diag(); dg.silent = (dg.silent or 0) + 1; dg.silentAt = time()
        logOut("no answer")
        scan = { state = "idle", silent = asked }
        ns.Feed(ns.LABEL .. "Auction scan|r  the server did not send the list; try again in a while", { tab = "prices", key = "ahscan", hold = 10 })
        if ns.PanelDirty then ns.PanelDirty() end
    end, "ah:silent")
    if ns.PanelDirty then ns.PanelDirty() end
end

-- a request that waits for the auction house to be free: sent on the house's own "ready" signal, looked at
-- twice a second in case that signal does not come, and sent anyway after QUEUE_MAX seconds
local QUEUE_MAX = 10
local function sendQueued()
    if scan.state ~= "queued" or not ahOpen then return end
    if ready() or time() - (scan.queuedAt or 0) >= QUEUE_MAX then start(); return end
    ns.After(0.5, sendQueued, "ah:queue")
end
local function queue(entry, resent)
    scan = { state = "queued", queuedAt = time(), key = ahKey or ns.AuctionKey(), log = entry, resent = resent }
    ns.After(0.5, sendQueued, "ah:queue")
    if ns.PanelDirty then ns.PanelDirty() end
end
-- what the auction house says about its one-at-a-time queue; the letters go into the request log
local THROTTLE_EVENTS = { AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED = "Q", AUCTION_HOUSE_THROTTLED_MESSAGE_SENT = "S",
    AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED = "R", AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED = "D",
    AUCTION_HOUSE_THROTTLED_SYSTEM_READY = "y" }
for event, letter in pairs(THROTTLE_EVENTS) do
    ns.On(event, function()
        local e = scan.log
        if e and (scan.state == "queued" or scan.state == "requested") and #e.ev < 24 then e.ev = e.ev .. letter end
        if letter == "y" then sendQueued()
        elseif letter == "D" and scan.state == "requested" and (scan.resent or 0) < RESENDS and time() - (scan.requestedAt or 0) <= 20 then
            -- a request was thrown away while ours was out: ask again as soon as the house is free
            local dg = diag(); dg.dropped = (dg.dropped or 0) + 1; dg.droppedAt = time()
            queue(e, (scan.resent or 0) + 1)
            if e then e.resent = scan.resent end
        end
    end, "ah:throttle")
end

-- returns ok, reason ("noapi" | "closed" | "busy" | "throttled"), seconds to wait
function ns.AuctionScan(force, how)
    if not api() then return false, "noapi" end
    if not ahOpen then return false, "closed" end
    if scan.state ~= "idle" then return false, "busy" end
    local wait = waitFor()
    if wait > 0 and not force then return false, "throttled", wait end
    local entry = logRequest(how)
    local dg = diag(); dg.startReady = entry.ready
    armed = false
    if entry.ready == "yes" then scan = { state = "idle", log = entry }; start()   -- free: straight away
    else dg.queued = (dg.queued or 0) + 1; queue(entry, 0) end
    return true
end

-- the automatic scan: due when the auction house opens, sent on the player's next key press (Escape closes
-- the auction house, so not that one) or a click on the button on the auction house window
function ns.AuctionOnKey(key)
    if not armed or not ahOpen or scan.state ~= "idle" then return end
    key = S(key)
    if key == "ESCAPE" then return end
    ns.safe("ah:auto", function() ns.AuctionScan(nil, "key") end)
end

function ns.AuctionStatus()
    local d = db()
    local wait = waitFor()
    local realms = {}
    local mine = ns.AuctionKey()
    local realmName = ns.AuctionRealmName()
    if d and realmName then
        for k, r in pairs(d.realms) do
            local realm, faction = k:match("^(.-)%-(%a+)$")
            if realm == realmName then realms[#realms + 1] = { key = k, faction = faction, count = r.count or 0, scanned = r.scanned, mine = k == mine, open = k == ahKey } end
        end
        table.sort(realms, function(a, b) return a.faction < b.faction end)
    end
    return { state = scan.state, done = scan.i or 0, total = scan.n or 0, ahOpen = ahOpen, api = api(), openKey = ahKey,
        nextIn = math.max(0, wait), realms = realms, faction = mine and mine:match("%-(%a+)$"), auctionator = auctionatorLast() > 0, armed = armed and ahOpen,
        silent = scan.silent ~= nil and d ~= nil and d.lastRead ~= d.lastRequest }
end

ns.On("AUCTION_HOUSE_SHOW", function()
    ahOpen = true
    openedAt = time()
    ahKey = openKey()
    diag().api = diag().api or { replicate = api() and "yes" or "no", ready = type(C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady) == "function" and "yes" or "no" }
    armed = (ns.db and ns.db.ahAutoScan and api() and waitFor() <= 0) or false
    ns.AuctionButton()
    if ns.PanelDirty then ns.PanelDirty() end
end, "ah:show")

-- a button on the auction house window itself, like Auctionator's Full Scan: a click is the surest way to ask
local ahButton
function ns.AuctionButton()
    local host = AuctionHouseFrame or AuctionFrame
    if not (host and api()) then return end
    if not ahButton then
        ahButton = CreateFrame("Button", "DearLordStatsScanButton", host, "UIPanelButtonTemplate")
        ahButton:SetSize(150, 22)
        ahButton:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", -8, -2)
        ahButton:SetScript("OnClick", function()
            ns.safe("ah:button", function()
                local ok, why = ns.AuctionScan(true, "button")
                if not ok and why == "busy" then ns.say("a scan is already running") end
                ns.AuctionButton()
            end)
        end)
        ahButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("DearLord Stats: scan prices")
            GameTooltip:AddLine("Reads every auction once. The game allows one scan per 15 minutes for the account; a click before that is sent anyway and may get no answer.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        ahButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ns.Every(1, function() if ahButton:IsShown() then ns.AuctionButton() end end, "ah:button")
    end
    local wait = waitFor()
    local label = (scan.state == "queued" and "Auction house busy...")
        or (scan.state == "requested" and "Waiting for list...")
        or (scan.state == "collecting" and string.format("Reading %d%%", math.floor((scan.i or 0) / math.max(1, scan.n or 1) * 100)))
        or (wait > 0 and ("Scan (" .. ns.shortTime(wait) .. ")")) or "Scan prices"
    if ahButton.SetText then ahButton:SetText(label) end
    ahButton.label = label
end
ns.On("AUCTION_HOUSE_CLOSED", function()
    ahOpen = false; ahKey = nil
    if scan.state == "requested" or scan.state == "queued" then
        abort("auction house closed before the list arrived")
    end
    if ns.PanelDirty then ns.PanelDirty() end
end, "ah:closed")
ns.On("UI_ERROR_MESSAGE", function(_, msg)
    msg = S(msg)
    if not msg or scan.state ~= "requested" or time() - (scan.requestedAt or 0) > 5 then return end
    if msg:lower():find("auction") then
        diag().error = msg
        abort("refused: " .. msg)
    end
end, "ah:error")

----------------------------------------------------------------------
-- tooltip rows: "Horde AH lowest  9s 31c     19 seen · 5 min ago" and "Horde AH usual  8s 0c     last 7 scan days",
-- plus the stack total when hovering a stack; on the modifier also "Horde AH smelted  1s 60c     Copper Bar · 512 seen · 4 h ago"
----------------------------------------------------------------------
local function modifierHeld()
    local m = ns.db and ns.db.ahCompare or "shift"
    if m == "always" then return true elseif m == "never" then return false end
    if m == "alt" then return IsAltKeyDown and B(IsAltKeyDown()) or false end
    if m == "shift" then return IsShiftKeyDown and B(IsShiftKeyDown()) or false end
    if m == "ctrl" then return IsControlKeyDown and B(IsControlKeyDown()) or false end
    return false
end

-- the tooltip has no columns of its own, so the rows are padded with spaces measured in the
-- tooltip's font: label | unit price | ×stack | stack total, each column lined up
local meter
local function measure(text)
    if not meter then
        local holder = CreateFrame("Frame")
        meter = holder:CreateFontString(nil, "OVERLAY")
        if meter.SetFontObject and GameTooltipText then meter:SetFontObject(GameTooltipText)
        else meter:SetFont(STANDARD_TEXT_FONT, 12, "") end
        if not meter.GetFont or not meter:GetFont() then meter:SetFont(STANDARD_TEXT_FONT, 12, "") end
    end
    meter:SetText(text)
    return N(meter:GetStringWidth()) or (#text * 6)
end
local function padTo(text, width, left)                      -- add spaces until the text is at least `width` wide
    local space = math.max(1, measure("a a") - measure("aa"))
    local missing = width - measure(text)
    if missing <= 0 then return text end
    local pad = string.rep(" ", math.ceil(missing / space))
    return left and (pad .. text) or (text .. pad)
end

-- ore -> bar, ores per bar: what a stack is worth once smelted. The character's own Mining recipes (kept
-- when the profession window was opened) come first, this list covers everyone else.
local SMELT = {
    [2770] = { 2840, 1, "Copper Bar" }, [2771] = { 3576, 1, "Tin Bar" }, [2775] = { 2842, 1, "Silver Bar" },
    [2772] = { 3575, 1, "Iron Bar" }, [2776] = { 3577, 1, "Gold Bar" }, [3858] = { 3860, 1, "Mithril Bar" },
    [7911] = { 6037, 1, "Truesilver Bar" }, [10620] = { 12359, 1, "Thorium Bar" }, [11370] = { 11371, 8, "Dark Iron Bar" },
}
-- returns bar id, ores per smelt, bars per smelt, bar name (may be nil)
local function smeltOf(id)
    local cache = ns.char and ns.char.recipes and ns.char.recipes.Mining
    for _, r in ipairs(cache and cache.list or {}) do
        local g = r.reagents
        if r.out and g and #g == 1 and g[1].id == id and (g[1].qty or 0) > 0 then
            return r.out, g[1].qty, r.qmin or 1, SMELT[id] and SMELT[id][1] == r.out and SMELT[id][3] or nil
        end
    end
    local s = SMELT[id]
    if s then return s[1], s[2], 1, s[3] end
end

local function addLines(tooltip, id)
    tooltip.dlsAhItem = id                                     -- a price seen while this is up redraws it
    if not (ns.db and ns.db.ahTooltip) then return end
    local stack = tooltip.dlsAhStack
    local count = (stack and stack.id == id and stack.count) or 1
    local rows = {}
    local price, age, seen, secs = ns.AuctionPriceByID(id)
    local vendor = C_Item and C_Item.GetItemInfo and N((select(11, C_Item.GetItemInfo("item:" .. id))))
    if price and vendor and vendor > 0 then
        rows[#rows + 1] = { label = "Vendor", unit = vendor, win = ns.AuctionNet(price) <= vendor }
    end
    -- per auction house two labelled prices: the lowest buyout when it was last seen (how many, how long ago),
    -- and under it what the item usually goes for, once three days are known
    local function house(k, name, own)
        local p, a, n, sec = ns.AuctionPriceByID(id, k)
        if not p then return end
        local row = { label = name .. " lowest", unit = p, win = own and (not vendor or vendor <= 0 or ns.AuctionNet(p) > vendor),
            note = n .. " seen  ·  " .. ns.AuctionAgeText(a, sec) }
        rows[#rows + 1] = row
        local usual, days = ns.AuctionUsual(id, k)
        if usual then rows[#rows + 1] = { label = name .. " usual", unit = usual, note = "last " .. days .. " scan days" } end
        return row
    end
    local ownName = ((ns.AuctionKey() or ""):match("%-(%a+)$") or "Your") .. " AH"
    local ownRow = house(nil, ownName, true)
    local held = modifierHeld()
    local bar, per, makes, barName = smeltOf(id)
    if bar and held then                                       -- an ore: what it sells for as bars, per ore
        local bp, ba, bn, bsec = ns.AuctionPriceByID(bar)
        local each = bp and bp * makes / per
        if each and each >= 1 then
            barName = (C_Item and C_Item.GetItemInfo and S((C_Item.GetItemInfo("item:" .. bar)))) or barName or "bars"
            local better = (not price or each > price) and (not vendor or vendor <= 0 or ns.AuctionNet(each) > vendor)
            if better and ownRow then ownRow.win = false end   -- one green row: the best way to sell
            rows[#rows + 1] = { label = ownName .. " smelted", unit = math.floor(each), total = math.floor(each * count), win = better,
                note = barName .. "  ·  " .. bn .. " seen  ·  " .. ns.AuctionAgeText(ba, bsec) }
        end
    end
    if held then                                               -- the other houses: on a modifier (Shift by default), always, or never
        if ns.db.ahTooltipNeutral ~= false then house(ns.AuctionNeutralKey(), "Neutral AH") end   -- the goblin house serves both factions
        local ok = ns.AuctionOtherKey()
        house(ok, ((ok or ""):match("%-(%a+)$") or "Other") .. " AH")
    end
    tooltip.dlsAhShown = (#rows > 0 or bar) and id or nil       -- an ore with no price of its own still gains a row on the modifier
    if #rows == 0 then return end
    local labelW, unitW, totalW = 0, 0, 0
    for _, r in ipairs(rows) do
        r.unitText, r.totalText = ns.strip(ns.money(r.unit)), count > 1 and ns.strip(ns.money(r.total or r.unit * count)) or nil
        labelW, unitW = math.max(labelW, measure(r.label)), math.max(unitW, measure(r.unitText))
        if r.totalText then totalW = math.max(totalW, measure(r.totalText)) end
    end
    for _, r in ipairs(rows) do
        local col = r.win and ns.GREEN or ns.WHITE
        local left = ns.LABEL .. padTo(r.label, labelW) .. "|r   " .. col .. padTo(r.unitText, unitW, true) .. "|r"
        if r.totalText then left = left .. ns.LABEL .. "   ·   ×" .. count .. "   |r" .. col .. padTo(r.totalText, totalW, true) .. "|r" end
        tooltip:AddDoubleLine(left, r.note and (ns.LABEL .. r.note .. "|r") or " ")
    end
    tooltip:Show()
end

-- pressing the modifier while hovering: redraw the tooltip so the comparison line appears at once
ns.On("MODIFIER_STATE_CHANGED", function()
    local m = ns.db and ns.db.ahCompare
    if not m or m == "always" or m == "never" then return end
    redrawTooltip()
end, "ah:modifier")

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item ~= nil then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        ns.safe("ah:tooltip", function()
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
            if tooltip.IsForbidden and tooltip:IsForbidden() then return end
            local id = data and N(data.id)
            if not id then return end
            local inst = data and N(data.dataInstanceID)
            if inst and tooltip.dlsAhInstance == inst then return end          -- the same data set twice: one line is enough
            tooltip.dlsAhInstance = inst
            addLines(tooltip, id)
        end)
    end)
    -- the stack size is not part of the tooltip data; remember it when a bag slot is shown
    if hooksecurefunc and GameTooltip and GameTooltip.SetBagItem and C_Container and C_Container.GetContainerItemInfo then
        hooksecurefunc(GameTooltip, "SetBagItem", function(tt, bag, slot)
            local info = T(C_Container.GetContainerItemInfo(bag, slot))
            tt.dlsAhStack = info and { id = N(info.itemID), count = N(info.stackCount) or 1 } or nil
            tt.dlsAhInstance = nil
        end)
    end
end
