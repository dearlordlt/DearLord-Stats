-- DearLord Stats : Economy advisor
-- Turns what the addon already knows into ways to earn gold: the last auction scans (per realm and
-- faction), this character's recipes and gathering skills, the bags, what vendors pay for items, and the
-- prices of vendors you have talked to. Every hint is built from real numbers; nothing is guessed:
-- an item without a price is left out rather than estimated.
--   sell     : stacks in the bags that earn more on the auction house (with a stack split), and what to vendor
--   craft    : recipes whose product sells for more than its materials cost, to the auction house or a vendor
--   gather   : what your gathering skills can collect, ranked by the value of a stack, with the price trend
--   flips    : items a vendor you met sells for less than the auction house pays
--   bargains : auctions listed below what a vendor pays for the item
local ADDON, ns = ...
local N, S, T, B = ns.N, ns.S, ns.T, ns.B

local MIN_GAIN, MIN_SHARE = 50, 0.15             -- a hint must earn at least 50c and 15% over the alternative

----------------------------------------------------------------------
-- vendor sell prices. What the client says this session always wins; a saved copy stands in while items are
-- still loading after a /reload, so bargains do not vanish. Patches do change vendor prices (enchanted wands
-- dropped to 1c), so the saved copy is thrown away whenever the game build changes.
----------------------------------------------------------------------
local sellMemo, pending = {}, {}
local function saved()
    local db = ns.db
    if not db then return nil end
    local build = GetBuildInfo and S((select(2, GetBuildInfo()))) or "?"
    if db.sellPricesBuild ~= build then db.sellPrices, db.sellPricesBuild = {}, build end
    db.sellPrices = db.sellPrices or {}
    return db.sellPrices
end
local function remember(id, price)
    sellMemo[id] = price
    local sv = saved()
    if sv then sv[id] = price end
end
local function knownSell(id) local sv = saved(); return sellMemo[id] or (sv and sv[id]) end
function ns.SellPrice(id)
    if not id then return nil end
    if sellMemo[id] then return sellMemo[id] end                   -- read from the client this session
    local price = C_Item and C_Item.GetItemInfo and N((select(11, C_Item.GetItemInfo("item:" .. id))))
    if price then remember(id, price); return price end
    local sv = saved()
    if sv and sv[id] then
        if C_Item and C_Item.RequestLoadItemDataByID and not pending[id] then pending[id] = true; pcall(C_Item.RequestLoadItemDataByID, id) end
        return sv[id]
    end
    if not (C_Item and C_Item.GetItemInfo) then return nil end
    if C_Item.RequestLoadItemDataByID and not pending[id] then     -- not cached yet: the client loads it and says so
        pending[id] = true
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
    return nil
end
local cache, cacheAt, dirty = nil, 0, true
-- an item asked for has loaded: read its price now (the event alone used to be noted and the price never read)
local function loaded(id)
    id = N(id)
    if not (id and pending[id]) then return end
    pending[id] = nil
    if ns.SellPrice(id) then dirty = true end
end
ns.On("GET_ITEM_INFO_RECEIVED", loaded, "adv:iteminfo")
ns.On("ITEM_DATA_LOAD_RESULT", loaded, "adv:iteminfo")

-- after a scan (and at login) ask for the vendor price of every item of your own house, a few hundred at a time
local warming = false
local function warm()
    if warming then return end
    local d = DearLordAuctionDB
    local r = d and d.realms and ns.AuctionKey() and d.realms[ns.AuctionKey()]
    if not r then return end
    local ids = {}
    for id in pairs(r.items) do ids[#ids + 1] = id end
    for id in pairs(ns.db and ns.db.vendors or {}) do ids[#ids + 1] = id end
    warming = true
    local i = 1
    local function step()
        for _ = 1, 100 do                                     -- gently: item data requests go to the server
            if i > #ids then warming = false; dirty = true; return end
            ns.SellPrice(ids[i]); i = i + 1
        end
        ns.After(0.1, step, "adv:warm")
    end
    step()
end
function ns.AdviceDirty(scanned)
    dirty = true
    if scanned then warm() end
end
ns.OnLogin(function() saved(); ns.After(5, warm, "adv:warm") end, "adv:warm")

----------------------------------------------------------------------
-- vendors: what a merchant sells and for how much, remembered account-wide
----------------------------------------------------------------------
local function merchantRow(i)
    local MF = C_MerchantFrame
    if MF and type(MF.GetItemInfo) == "function" then
        local info = T(MF.GetItemInfo(i))
        if info then return N(info.price), N(info.stackCount) or 1, N(info.numAvailable), B(info.hasExtendedCost), S(info.name) end
    end
    if GetMerchantItemInfo then
        local name, _, price, stack, avail, _, _, ext = GetMerchantItemInfo(i)
        return N(price), N(stack) or 1, N(avail), B(ext), S(name)
    end
end
local function merchantItemID(i)
    local id = GetMerchantItemID and N(GetMerchantItemID(i))
    if id then return id end
    local link = GetMerchantItemLink and S(GetMerchantItemLink(i))
    return link and tonumber(link:match("item:(%d+)"))
end
local function recordMerchant()
    local count = (GetMerchantNumItems and N(GetMerchantNumItems())) or (C_MerchantFrame and C_MerchantFrame.GetNumItems and N(C_MerchantFrame.GetNumItems())) or 0
    if count == 0 or not ns.db then return end
    ns.db.vendors = ns.db.vendors or {}
    local who = UnitName and S(UnitName("npc"))
    local zone = ns.zone()
    ns.diagOnce("merchantRow", function()
        return { count = count, modern = (C_MerchantFrame and type(C_MerchantFrame.GetItemInfo) == "function") and "yes" or "no",
            legacy = GetMerchantItemInfo and "yes" or "no", id = merchantItemID(1), sample = ns.dump({ merchantRow(1) }) }
    end)
    local changed = false
    for i = 1, count do
        local price, stack, avail, ext, name = merchantRow(i)
        local id = merchantItemID(i)
        if id and price and price > 0 and not ext then
            local unit = math.floor(price / math.max(1, stack or 1) + 0.5)
            local v = ns.db.vendors[id]
            if not v or v.c ~= unit or v.z ~= zone then changed = true end
            ns.db.vendors[id] = { c = unit, lim = (avail and avail >= 0) or nil, z = zone, npc = who, t = time(), name = name }
        end
    end
    if changed then dirty = true; if ns.PanelDirty then ns.PanelDirty() end end
end
ns.On("MERCHANT_SHOW", function() ns.After(0.5, recordMerchant, "adv:merchant") end, "adv:merchant")
ns.On("MERCHANT_UPDATE", function() recordMerchant() end, "adv:merchant")

----------------------------------------------------------------------
-- the bags, read once and kept until they change
----------------------------------------------------------------------
local bags, bagsAt = nil, 0
local function invalidateBags() bags = nil; dirty = true end
ns.On("BAG_UPDATE_DELAYED", invalidateBags, "adv:bags")
ns.On("PLAYER_MONEY", invalidateBags, "adv:bags")
function ns.BagSnapshot()
    if bags and GetTime() - bagsAt < 10 then return bags end
    local CC = C_Container
    if not (CC and CC.GetContainerNumSlots and CC.GetContainerItemInfo) then return nil end
    local list, byId = {}, {}
    for bag = 0, 4 do
        local slots = N(CC.GetContainerNumSlots(bag)) or 0
        for slot = 1, slots do
            local info = T(CC.GetContainerItemInfo(bag, slot))
            local link = info and S(info.hyperlink)
            local id = info and (N(info.itemID) or (link and tonumber(link:match("item:(%d+)"))))
            if id and not B(info.hasNoValue) then
                local e = byId[id]
                if not e then
                    e = { id = id, link = link, q = N(info.quality) or 1, n = 0, name = link and link:match("%[(.-)%]") or ns.itemName(id) }
                    byId[id] = e; list[#list + 1] = e
                end
                e.n = e.n + (N(info.stackCount) or 1)
            end
        end
    end
    bags, bagsAt = { list = list, byId = byId }, GetTime()
    return bags
end

----------------------------------------------------------------------
-- prices
----------------------------------------------------------------------
local function net(p) return math.floor(p * (1 - ns.AH_CUT)) end
local function entryOf(id, k)
    local d = DearLordAuctionDB
    local r = d and d.realms and (k or ns.AuctionKey()) and d.realms[k or ns.AuctionKey()]
    return r and r.items[id]
end
local function median(id) local h = ns.AuctionHistory(id); return h[1] and h[1].med end
-- the cheapest way to get one: the lowest auction or a vendor you met
local function buyCost(id)
    local p = ns.AuctionPriceByID(id)
    local v = ns.db.vendors and ns.db.vendors[id] and ns.db.vendors[id].c
    if p and v then if v <= p then return v, "vendor" end return p, "auction" end
    if p then return p, "auction" end
    if v then return v, "vendor" end
end
local function m(c) return (ns.strip(ns.money(c)):gsub(" 0[sc]$", "")) end     -- "1s", "48s 61c", "2g"
local function hidden(kind, id) return ns.db.adviceHidden and ns.db.adviceHidden[kind .. ":" .. id] end
function ns.HideAdvice(kind, id)
    ns.db.adviceHidden = ns.db.adviceHidden or {}
    ns.db.adviceHidden[kind .. ":" .. id] = true
    dirty = true
end
local function nameOf(id)
    local name = ns.AuctionItemName(id, entryOf(id)) or (ns.db.vendors and ns.db.vendors[id] and ns.db.vendors[id].name)
    if not name and C_Item and C_Item.GetItemInfo then name = S((C_Item.GetItemInfo("item:" .. id))) end
    return name or ns.itemName(id)
end
-- the newest lowest price against the median of the older days' lowest, in percent
local function trendVsHistory(id)
    local h = ns.AuctionHistory(id)
    if #h < 2 then return nil end
    local older = {}
    for i = 2, #h do if h[i].min and h[i].min > 0 then older[#older + 1] = h[i].min end end
    if #older == 0 then return nil end
    table.sort(older)
    local mid = older[math.ceil(#older / 2)]
    return math.floor((h[1].min - mid) / mid * 100 + 0.5), #h
end

----------------------------------------------------------------------
-- the five kinds of advice
----------------------------------------------------------------------
local function adviseSell(out)
    local snap = ns.BagSnapshot()
    if not snap then return end
    local vendorValue, vendorStacks, vendorNames = 0, 0, {}
    local worthVendor, worthBest = 0, 0
    for _, b in ipairs(snap.list) do
        local p, _, seen = ns.AuctionPriceByID(b.id)
        local sv = ns.SellPrice(b.id) or 0
        local vTotal = sv * b.n
        local aTotal = (p and b.q >= 1) and net(p) * b.n or 0
        worthVendor, worthBest = worthVendor + vTotal, worthBest + math.max(vTotal, aTotal)
        if aTotal - vTotal >= MIN_GAIN and aTotal >= vTotal * (1 + MIN_SHARE) then
            if not hidden("sell", b.id) then
                local e = entryOf(b.id)
                local k = e and e.k or 1
                local plan, split
                if b.n > 1 and k > 1 and b.n > k then
                    local full, rest = math.floor(b.n / k), b.n % k
                    split = full .. "×" .. k .. (rest > 0 and (" + " .. rest) or "")
                    plan = "as " .. split
                elseif b.n > 1 and k > 1 then plan = "as one stack of " .. b.n
                elseif b.n > 1 then plan = "one at a time (most sellers post singles)"
                else plan = "it" end
                local med = median(b.id)
                out.sell[#out.sell + 1] = { kind = "sell", id = b.id, link = b.link, q = b.q, name = b.name, n = b.n, value = aTotal - vTotal,
                    left = ns.QualityColor(b.q) .. b.name .. "|r" .. ns.LABEL .. "  ×" .. b.n .. (split and ("  as " .. split) or "") .. "|r",
                    right = ns.GREEN .. "+" .. m(aTotal - vTotal) .. "|r" .. ns.LABEL .. "  at " .. m(p) .. "|r",
                    tip = "List " .. plan .. " at " .. m(p) .. " each, the lowest buyout at your last scan" .. (med and med ~= p and (" (median " .. m(med) .. ")") or "") .. ".\n"
                        .. "After the 5% cut: " .. m(aTotal) .. ". A vendor pays " .. m(vTotal) .. ".\n"
                        .. (seen or 0) .. " on the auction house" .. (k > 1 and (", most sellers post stacks of " .. k) or "") .. ". Deposit not counted.\n"
                        .. "Click for the price history, right-click to hide this hint." }
            end
        elseif vTotal > 0 and (b.q == 0 or aTotal <= vTotal) then
            vendorValue, vendorStacks = vendorValue + vTotal, vendorStacks + 1
            if #vendorNames < 12 then vendorNames[#vendorNames + 1] = b.name .. " ×" .. b.n .. "  " .. m(vTotal) end
        end
    end
    table.sort(out.sell, function(a, b) return a.value > b.value end)
    out.vendor = vendorStacks > 0 and { value = vendorValue, stacks = vendorStacks, names = vendorNames } or nil
    out.bagsVendor, out.bagsBest = worthVendor, worthBest
end

local GATHERING = { Mining = true, Herbalism = true, Skinning = true, Fishing = true }
local function adviseCraft(out)
    local seenOut = {}
    local skipped, missing = 0, {}
    for prof, cache in pairs(ns.char.recipes or {}) do
        if not cache.outputs then
            out.notes[#out.notes + 1] = { kind = "craft", text = "Open your " .. prof .. " window once so the advisor learns what each recipe makes." }
        else
            for _, r in ipairs(cache.list or {}) do
                if r.out and not seenOut[r.out] and not hidden("craft", r.out) then
                    local qty = ((r.qmin or 1) + (r.qmax or r.qmin or 1)) / 2
                    local cost, parts, lack, make = 0, {}, nil, math.huge
                    for _, g in ipairs(r.reagents or {}) do
                        local unit, from = buyCost(g.id)
                        if not unit then lack = nameOf(g.id); break end
                        cost = cost + unit * g.qty
                        parts[#parts + 1] = g.qty .. " " .. nameOf(g.id) .. "  " .. m(unit * g.qty) .. (from == "vendor" and " (vendor)" or "")
                        make = math.min(make, math.floor(ns.itemCount(g.id) / g.qty))
                    end
                    if #(r.reagents or {}) == 0 then lack = "no materials known" end
                    if lack then
                        skipped = skipped + 1
                        if #missing < 5 then missing[#missing + 1] = lack end
                    else
                        local p = ns.AuctionPriceByID(r.out)
                        local sv = ns.SellPrice(r.out) or 0
                        local ahRev = p and math.floor(net(p) * qty) or 0
                        local vRev = math.floor(sv * qty)
                        local rev, where = ahRev, "AH"
                        if vRev > ahRev then rev, where = vRev, "vendor" end
                        local profit = rev - cost
                        if profit >= MIN_GAIN and profit >= cost * MIN_SHARE then
                            seenOut[r.out] = true
                            local skillUp = r.diff == 0 or r.diff == 1
                            local name = nameOf(r.out)
                            if not name or name:match("^item %d+$") then name = r.name end
                            out.craft[#out.craft + 1] = { kind = "craft", id = r.out, link = "item:" .. r.out, name = name, value = profit,
                                left = ns.WHITE .. name .. "|r" .. (make > 0 and make < math.huge and (ns.LABEL .. "  make " .. make .. "|r") or "")
                                    .. (skillUp and ("  " .. (r.diff == 0 and "|cffff8040" or "|cffffff00") .. "skill-up|r") or ""),
                                right = ns.GREEN .. "+" .. m(profit) .. "|r" .. ns.LABEL .. "  to " .. where .. "|r",
                                tip = prof .. ": " .. r.name .. (qty ~= 1 and (" (makes " .. qty .. ")") or "") .. "\n"
                                    .. "Materials " .. m(cost) .. ":\n   " .. table.concat(parts, "\n   ") .. "\n"
                                    .. (p and ("Auction house: " .. m(p) .. " each, " .. m(ahRev) .. " after the cut\n") or "Not on the auction house at your last scan\n")
                                    .. (vRev > 0 and ("A vendor pays " .. m(vRev) .. ". ") or "") .. "Best: " .. where .. ", " .. ns.strip(ns.money(profit, true)) .. " per craft.\n"
                                    .. (make > 0 and make < math.huge and ("Your bags hold materials for " .. make .. ".\n") or "")
                                    .. "Click for the price history, right-click to hide this hint." }
                        end
                    end
                end
            end
        end
    end
    table.sort(out.craft, function(a, b) return a.value > b.value end)
    if skipped > 0 then out.craftSkipped = { n = skipped, names = missing } end
end

-- what each gathering skill collects, and from which skill (ores, stones, herbs, leathers)
local GATHER = {
    Mining = { { 2770, 1 }, { 2835, 1 }, { 2771, 65 }, { 2836, 65 }, { 2775, 75 }, { 2772, 125 }, { 2838, 125 }, { 2776, 155 },
        { 3858, 175 }, { 7912, 175 }, { 7911, 230 }, { 10620, 245 }, { 12365, 245 } },
    Herbalism = { { 2447, 1 }, { 765, 1 }, { 2449, 15 }, { 785, 50 }, { 2450, 70 }, { 3820, 85 }, { 2453, 100 }, { 3355, 115 },
        { 3369, 120 }, { 3356, 125 }, { 3357, 150 }, { 3818, 160 }, { 3821, 170 }, { 3358, 185 }, { 3819, 195 }, { 4625, 205 },
        { 8831, 210 }, { 8838, 230 }, { 8839, 235 }, { 8846, 250 }, { 13464, 260 }, { 13463, 270 }, { 13465, 280 } },
    Skinning = { { 2934, 1 }, { 2318, 1 }, { 783, 1 }, { 2319, 75 }, { 4232, 100 }, { 4234, 125 }, { 4235, 150 }, { 4304, 175 },
        { 8169, 200 }, { 8170, 225 } },
}
ns.GATHER_ITEMS = GATHER
local function adviseGather(out)
    local profs = {}
    for name, info in pairs(ns.char.prof or {}) do if GATHERING[name] then profs[name] = info.rank or 0 end end
    if not next(profs) then return end
    local cands = {}
    for prof, rank in pairs(profs) do
        for _, g in ipairs(GATHER[prof] or {}) do
            if g[2] <= rank + 25 then cands[g[1]] = { prof = prof, need = g[2] > rank and g[2] or nil } end
        end
    end
    -- plus whatever this character has actually gathered (fish, rare herbs...), matched by name
    local byName
    for _, zones in pairs(ns.char.gather or {}) do
        for prof, rec in pairs(zones) do
            if profs[prof] then
                for itemName, count in pairs(rec.items or {}) do
                    if not byName then
                        byName = {}
                        local d = DearLordAuctionDB
                        local r = d and d.realms and ns.AuctionKey() and d.realms[ns.AuctionKey()]
                        for id, e in pairs(r and r.items or {}) do if e.name then byName[e.name] = id end end
                    end
                    local id = byName[itemName]
                    if id then
                        cands[id] = cands[id] or { prof = prof }
                        cands[id].got = (cands[id].got or 0) + count
                    end
                end
            end
        end
    end
    for id, c in pairs(cands) do
        local p, _, seen = ns.AuctionPriceByID(id)
        if p and p > 0 and net(p) * ((entryOf(id) and entryOf(id).k) or 20) >= MIN_GAIN and not hidden("gather", id) then
            local e = entryOf(id)
            local k = (e and e.k) or 20
            local pct, days = trendVsHistory(id)
            local stack = net(p) * k
            local name = nameOf(id) or ("item " .. id)
            local trend = pct and math.abs(pct) >= 5 and ((pct > 0 and ns.GREEN .. "+" or ns.RED) .. pct .. "%|r") or nil
            out.gather[#out.gather + 1] = { kind = "gather", id = id, link = "item:" .. id, name = name, value = stack, rising = pct and pct >= 10,
                left = ns.WHITE .. name .. "|r" .. ns.LABEL .. "  " .. c.prof:lower() .. (c.need and (" " .. c.need) or "") .. "|r",
                right = ns.WHITE .. m(stack) .. "|r" .. ns.LABEL .. " /" .. k .. "|r" .. (trend and ("  " .. trend) or ""),
                tip = name .. ": lowest buyout " .. m(p) .. " each" .. (median(id) and (", median " .. m(median(id))) or "") .. ", " .. (seen or 0) .. " on the auction house.\n"
                    .. "A stack of " .. k .. " brings " .. m(stack) .. " after the cut.\n"
                    .. (pct and ("Now " .. (pct >= 0 and "+" or "") .. pct .. "% against the median of the " .. (days - 1) .. " earlier scan day" .. (days > 2 and "s" or "") .. ".\n") or "")
                    .. (c.need and ("Needs " .. c.prof .. " " .. c.need .. ".\n") or "")
                    .. (c.got and ("You have gathered " .. c.got .. " so far.\n") or "")
                    .. "Click for the price history, right-click to hide this hint." }
        end
    end
    table.sort(out.gather, function(a, b) return a.value > b.value end)
end

local function adviseFlips(out)
    for id, v in pairs(ns.db.vendors or {}) do
        local p, _, seen = ns.AuctionPriceByID(id)
        if p and not hidden("flip", id) then
            local gain = net(p) - v.c
            if gain >= MIN_GAIN and net(p) >= v.c * 1.3 then
                local name = nameOf(id) or ("item " .. id)
                out.flips[#out.flips + 1] = { kind = "flip", id = id, link = "item:" .. id, name = name, value = gain,
                    left = ns.WHITE .. name .. "|r" .. ns.LABEL .. "  " .. (v.z or "") .. "|r",
                    right = ns.GREEN .. "+" .. m(gain) .. "|r" .. ns.LABEL .. "  buy " .. m(v.c) .. ", AH " .. m(p) .. "|r",
                    tip = name .. ": " .. (v.npc and (v.npc .. " in ") or "a vendor in ") .. (v.z or "?") .. " sells it for " .. m(v.c) .. (v.lim and " (limited stock)" or "") .. ".\n"
                        .. "Lowest auction " .. m(p) .. ", " .. m(net(p)) .. " after the cut; " .. (seen or 0) .. " on the auction house.\n"
                        .. "Deposit not counted. Right-click to hide this hint." }
            end
        end
    end
    table.sort(out.flips, function(a, b) return a.value > b.value end)
end

local function adviseBargains(out, age)
    if not age or age > 1 then return end                   -- an old scan's cheap listing is long gone
    local d = DearLordAuctionDB
    local r = d and d.realms and ns.AuctionKey() and d.realms[ns.AuctionKey()]
    for id, e in pairs(r and r.items or {}) do
        local sv = knownSell(id)
        if sv and e.p and e.p > 0 and sv - e.p >= 10 and not hidden("bargain", id) then
            local name = nameOf(id) or ("item " .. id)
            out.bargains[#out.bargains + 1] = { kind = "bargain", id = id, link = "item:" .. id, name = name, value = sv - e.p,
                left = ns.WHITE .. name .. "|r",
                right = ns.GREEN .. "+" .. m(sv - e.p) .. "|r" .. ns.LABEL .. "  buy " .. m(e.p) .. ", vendor " .. m(sv) .. "|r",
                tip = "The cheapest listing was " .. m(e.p) .. " each at your last scan; a vendor pays " .. m(sv) .. ".\n"
                    .. "Buy it and sell it to a vendor. Only that cheapest listing is sure to be below the vendor price, and it may be gone already.\n"
                    .. "Right-click to hide this hint." }
        end
    end
    table.sort(out.bargains, function(a, b) return a.value > b.value end)
end

function ns.Advice()
    local nowT = GetTime()
    if cache and (nowT - cacheAt < 2 or (not dirty and nowT - cacheAt < 30)) then return cache end
    local out = { sell = {}, craft = {}, gather = {}, flips = {}, bargains = {}, notes = {} }
    local d = DearLordAuctionDB
    local r = d and d.realms and ns.AuctionKey() and d.realms[ns.AuctionKey()]
    out.hasPrices = r ~= nil and (r.count or 0) > 0
    out.age = out.hasPrices and r.day and math.max(0, ns.AuctionDay() - r.day) or nil
    out.scanned = r and r.scanned
    if ns.char and ns.db then
        ns.db.vendors = ns.db.vendors or {}
        ns.call("adv:sell", adviseSell, out)
        if out.hasPrices then
            ns.call("adv:craft", adviseCraft, out)
            ns.call("adv:gather", adviseGather, out)
            ns.call("adv:flips", adviseFlips, out)
            ns.call("adv:bargains", adviseBargains, out, out.age)
        end
        if not next(ns.db.vendors) then out.noVendors = true end
    end
    cache, cacheAt, dirty = out, nowT, false
    return out
end
