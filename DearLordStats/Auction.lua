-- DearLord Stats : Auction prices
-- The addon's own auction-house scan: when the auction house is open it asks the server for the full
-- list of auctions (C_AuctionHouse.ReplicateItems, allowed once every 15 minutes), keeps the lowest
-- buyout per item, and shows it in item tooltips and on the Loot tab. Prices are kept per realm AND
-- faction, because Horde and Alliance have separate auction houses on this server.
--
-- Saved in its own variable, DearLordAuctionDB, plain numbers and strings only:
--   { version = 1, lastRequest = <epoch>,
--     realms = { ["Realm-Horde"] = { scanned = <epoch>, day = 2456, auctions = 4812, count = 1846,
--                items = { [id] = { p = <min unit buyout>, n = <units seen>, d = <scan day>, h = "day:price day:price" } } } } }
local ADDON, ns = ...
local N, S, T, B = ns.N, ns.S, ns.T, ns.B

ns.AH_CUT = 0.05                                             -- the auction house keeps 5% of a sale
local DAY0 = 1577836800                                      -- 2020-01-01: day numbers count from here
local CHUNK, HISTORY_MAX, HISTORY_DAYS, KEEP_DAYS, THROTTLE = 500, 8, 28, 60, 900

local ahOpen = false
local ahKey                                                  -- database key of the auction house that is open
local scan = { state = "idle" }
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
end, "ah:loaded")
ns.OnLogin(function() ns.AuctionKey() end, "ah:key")

----------------------------------------------------------------------
-- prices
----------------------------------------------------------------------
function ns.HasAuctionPrices()
    local r = realmData()
    return r ~= nil and (r.count or 0) > 0
end

-- price per unit in copper, age in days, units seen at that scan
function ns.AuctionPriceByID(id, k)
    local r = id and realmData(false, k)
    local e = r and r.items[id]
    if not e or not e.p or e.p <= 0 then return nil end
    return e.p, math.max(0, ns.AuctionDay() - (e.d or ns.AuctionDay())), e.n or 0
end
function ns.AuctionPrice(link)
    local id = link and tonumber(tostring(link):match("Hitem:(%d+)"))
    return ns.AuctionPriceByID(id)
end
function ns.AuctionAgeText(days)
    if not days or days <= 0 then return "today" end
    if days == 1 then return "yesterday" end
    return days .. " days ago"
end

----------------------------------------------------------------------
-- the scan
----------------------------------------------------------------------
local function api() return C_AuctionHouse and type(C_AuctionHouse.ReplicateItems) == "function"
    and type(C_AuctionHouse.GetNumReplicateItems) == "function" and type(C_AuctionHouse.GetReplicateItemInfo) == "function" end

local function abort(why)
    scan = { state = "idle" }
    if why then ns.Feed(ns.LABEL .. "Auction scan|r  " .. why, { tab = "loot", key = "ahscan", hold = 8 }) end
    if ns.PanelDirty then ns.PanelDirty() end
end

-- "day:price day:price", newest first, one entry per day, capped
local function pushHistory(e, today, price)
    local out, seen = { today .. ":" .. price }, { [today] = true }
    for d, p in (e.h or ""):gmatch("(%d+):(%d+)") do
        d = tonumber(d)
        if not seen[d] and today - d <= HISTORY_DAYS and #out < HISTORY_MAX then out[#out + 1] = d .. ":" .. p; seen[d] = true end
    end
    e.h = table.concat(out, " ")
end

local function commit()
    local r = realmData(true, scan.key)
    if not r then abort("no realm or faction known"); return end
    local today, items, n = ns.AuctionDay(), r.items, 0
    for id, a in pairs(scan.agg) do
        local e = items[id] or {}
        e.p, e.n, e.d = a.p, a.n, today
        pushHistory(e, today, a.p)
        items[id] = e
    end
    for id, e in pairs(items) do
        if (e.d or 0) < today - KEEP_DAYS then items[id] = nil else n = n + 1 end
    end
    r.scanned, r.day, r.auctions, r.count = time(), today, scan.n, n
    local d = diag(); d.lastScan = { at = time(), rows = scan.n, items = n, secs = time() - (scan.requestedAt or time()) }
    ns.Feed(ns.LABEL .. "Auction scan|r  " .. ns.WHITE .. n .. " items|r" .. ns.LABEL .. "  ·  " .. scan.n .. " auctions|r", { tab = "loot", key = "ahscan", hold = 10 })
    scan = { state = "idle" }
    if ns.PanelDirty then ns.PanelDirty() end
end

-- one row of the replicated list: only count, buyout and item id are guaranteed to be there at once
local function readRow(i)
    local r = { C_AuctionHouse.GetReplicateItemInfo(i) }
    if type(r[1]) == "table" then return N(r[1].count), N(r[1].buyoutPrice), N(r[1].itemID), r end
    return N(r[3]), N(r[10]), N(r[17]), r
end

local function collectChunk()
    if scan.state ~= "collecting" then return end
    local n = N(C_AuctionHouse.GetNumReplicateItems()) or 0
    if n == 0 then abort("the list vanished (auction house closed?)"); return end
    local last = math.min(scan.i + CHUNK - 1, scan.n - 1)
    for i = scan.i, last do
        local count, buyout, id, raw = readRow(i)
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
            if not a then scan.agg[id] = { p = unit, n = count }; scan.priced = scan.priced + 1
            else a.n = a.n + count; if unit < a.p then a.p = unit end end
        elseif i < 50 then scan.blank = scan.blank + 1 end
    end
    scan.i = last + 1
    if scan.i >= 50 and scan.priced == 0 and scan.blank >= 50 then
        abort("prices are hidden from addons on this client"); return
    end
    if scan.i >= scan.n then commit(); return end
    if scan.i % 2000 == 0 then
        ns.Feed(ns.LABEL .. "Auction scan|r  " .. ns.WHITE .. scan.i .. " / " .. scan.n .. "|r", { tab = "loot", key = "ahscan", hold = 4 })
    end
    ns.After(0, collectChunk, "ah:chunk")
end

ns.On("REPLICATE_ITEM_LIST_UPDATE", function()
    local d = diag(); d.updates = (d.updates or 0) + 1
    if scan.state ~= "requested" then return end
    local n = N(C_AuctionHouse.GetNumReplicateItems()) or 0
    d.firstUpdate = { rows = n, secs = time() - (scan.requestedAt or time()) }
    if n == 0 then return end                                 -- it fires again when the list has arrived
    scan.state, scan.n, scan.i, scan.agg, scan.priced, scan.blank = "collecting", n, 0, {}, 0, 0
    collectChunk()
end, "ah:replicate")

local function start()
    local d = db(); if not d then return end
    d.lastRequest = time()                                    -- the throttle is spent whether or not the answer comes
    scan = { state = "requested", requestedAt = time(), key = ahKey or ns.AuctionKey() }
    local ok, err = pcall(C_AuctionHouse.ReplicateItems)
    if not ok then diag().error = tostring(err); abort("refused: " .. tostring(err)); return end
    ns.After(30, function() if scan.state == "requested" then abort("no answer from the server in 30 s") end end, "ah:timeout")
    if ns.PanelDirty then ns.PanelDirty() end
end

-- returns ok, reason ("noapi" | "closed" | "busy" | "throttled"), seconds to wait
function ns.AuctionScan(force)
    if not api() then return false, "noapi" end
    if not ahOpen then return false, "closed" end
    if scan.state ~= "idle" then return false, "busy" end
    local wait = THROTTLE - (time() - ((db() and db().lastRequest) or 0))
    if wait > 0 and not force then return false, "throttled", wait end
    local ready = C_AuctionHouse.IsThrottledMessageSystemReady
    if type(ready) == "function" and B(ready()) == false then
        scan.retries = (scan.retries or 0) + 1
        if scan.retries <= 5 then ns.After(1, function() ns.AuctionScan(force) end, "ah:retry"); return true end
        scan.retries = nil
        return false, "busy"
    end
    start()
    return true
end

function ns.AuctionStatus()
    local d = db()
    local wait = THROTTLE - (time() - ((d and d.lastRequest) or 0))
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
        nextIn = math.max(0, wait), realms = realms, faction = mine and mine:match("%-(%a+)$") }
end

ns.On("AUCTION_HOUSE_SHOW", function()
    ahOpen = true
    ahKey = openKey()
    diag().api = diag().api or { replicate = api() and "yes" or "no", ready = type(C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady) == "function" and "yes" or "no" }
    if ns.db and ns.db.ahAutoScan then ns.After(1, function() ns.AuctionScan() end, "ah:auto") end
    if ns.PanelDirty then ns.PanelDirty() end
end, "ah:show")
ns.On("AUCTION_HOUSE_CLOSED", function()
    ahOpen = false; ahKey = nil
    if scan.state == "requested" then abort("auction house closed before the list arrived") end
    if ns.PanelDirty then ns.PanelDirty() end
end, "ah:closed")
ns.On("UI_ERROR_MESSAGE", function(_, msg)
    msg = S(msg)
    if not msg or scan.state ~= "requested" or time() - (scan.requestedAt or 0) > 5 then return end
    if msg:lower():find("auction") then diag().error = msg; abort("refused: " .. msg) end
end, "ah:error")

----------------------------------------------------------------------
-- tooltip line: "AH  9s 31c            19 seen · 2 days ago", plus the stack total when hovering a stack
----------------------------------------------------------------------
local function modifierHeld()
    local m = ns.db and ns.db.ahCompare or "alt"
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

local function addLines(tooltip, id)
    if not (ns.db and ns.db.ahTooltip) then return end
    local stack = tooltip.dlsAhStack
    local count = (stack and stack.id == id and stack.count) or 1
    local rows = {}
    local price, age, seen = ns.AuctionPriceByID(id)
    local vendor = C_Item and C_Item.GetItemInfo and N((select(11, C_Item.GetItemInfo("item:" .. id))))
    if price and vendor and vendor > 0 then
        rows[#rows + 1] = { label = "Vendor", unit = vendor, win = ns.AuctionNet(price) <= vendor }
    end
    if price then rows[#rows + 1] = { label = "AH", unit = price, win = not vendor or vendor <= 0 or ns.AuctionNet(price) > vendor, seen = seen, age = age } end
    if ns.db.ahTooltipNeutral ~= false then                    -- the goblin auction house serves both factions: always worth a look
        local np, nage, nseen = ns.AuctionPriceByID(id, ns.AuctionNeutralKey())
        if np then rows[#rows + 1] = { label = "Neutral AH", unit = np, seen = nseen, age = nage } end
    end
    if modifierHeld() then
        local ok = ns.AuctionOtherKey()
        local op, oage, oseen = ns.AuctionPriceByID(id, ok)
        if op then rows[#rows + 1] = { label = (ok:match("%-(%a+)$") or "Other") .. " AH", unit = op, seen = oseen, age = oage } end
    end
    tooltip.dlsAhShown = #rows > 0 and id or nil
    if #rows == 0 then return end
    local labelW, unitW, totalW = 0, 0, 0
    for _, r in ipairs(rows) do
        r.unitText, r.totalText = ns.strip(ns.money(r.unit)), count > 1 and ns.strip(ns.money(r.unit * count)) or nil
        labelW, unitW = math.max(labelW, measure(r.label)), math.max(unitW, measure(r.unitText))
        if r.totalText then totalW = math.max(totalW, measure(r.totalText)) end
    end
    for _, r in ipairs(rows) do
        local col = r.win and ns.GREEN or ns.WHITE
        local left = ns.LABEL .. padTo(r.label, labelW) .. "|r   " .. col .. padTo(r.unitText, unitW, true) .. "|r"
        if r.totalText then left = left .. ns.LABEL .. "   ·   ×" .. count .. "   |r" .. col .. padTo(r.totalText, totalW, true) .. "|r" end
        tooltip:AddDoubleLine(left, " ")
    end
    for _, r in ipairs(rows) do                                -- how fresh each auction price is, on its own dim line
        if r.seen then
            local who = r.label == "AH" and "" or (r.label:gsub(" AH$", "") .. ":  ")
            tooltip:AddLine(ns.LABEL .. who .. r.seen .. " seen  ·  " .. ns.AuctionAgeText(r.age) .. "|r")
        end
    end
    tooltip:Show()
end

-- pressing the modifier while hovering: redraw the tooltip so the comparison line appears at once
ns.On("MODIFIER_STATE_CHANGED", function()
    local m = ns.db and ns.db.ahCompare
    if not m or m == "always" or m == "never" then return end
    if not (GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() and GameTooltip.dlsAhShown) then return end
    local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
    local enter = owner and owner.GetScript and owner:GetScript("OnEnter")
    if enter then GameTooltip.dlsAhInstance = nil; pcall(enter, owner) end
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
