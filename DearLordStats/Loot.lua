-- DearLord Stats : Loot
-- What this session's looting was worth: coin, vendor value (and how much of it is junk), drops by
-- quality, notable drops, the most valuable stacks, junk currently in the bags, and a one-line
-- summary of earlier sessions.
local ADDON, ns = ...
local N, S, T, B = ns.N, ns.S, ns.T, ns.B

local QUALITY_NAME = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }
local QUALITY_HEX = { [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000" }
ns.QUALITY_NAME = QUALITY_NAME
function ns.QualityColor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    local hex = c and ns.S(c.hex)
    if hex then return hex end
    return "|c" .. (QUALITY_HEX[q] or QUALITY_HEX[1])
end

-- "You receive loot: %s" / "...%sx%d" only. Quest rewards, purchases and crafted items use other texts.
local function prefixOf(global, fallback)
    local s = _G[global]
    return (type(s) == "string" and s:match("^(.-)%%s")) or fallback
end
local LOOT_PREFIX = prefixOf("LOOT_ITEM_SELF", "You receive loot: ")

-- "You loot 3 Silver, 20 Copper": build number patterns from the client's own words
local function amountPattern(global, fallback)
    local s = type(_G[global]) == "string" and _G[global] or fallback
    return (s:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%d", "(%%d+)"))
end
local GOLD, SILVER, COPPER = amountPattern("GOLD_AMOUNT", "%d Gold"), amountPattern("SILVER_AMOUNT", "%d Silver"), amountPattern("COPPER_AMOUNT", "%d Copper")

local function lootOf(session, fresh)
    session.loot = session.loot or { coin = 0, vendor = 0, junk = 0, items = 0, byQ = {}, list = {}, drops = {},
        started = fresh and time() or session.start or time() }
    return session.loot
end

-- quality and vendor price: from the item data when it is cached, otherwise from the link itself
local function itemFacts(link)
    local id = tonumber(link:match("Hitem:(%d+)"))
    local quality, price
    if C_Item and C_Item.GetItemInfo then
        local info = { C_Item.GetItemInfo(link) }
        quality, price = N(info[3]), N(info[11])
    end
    if not quality then quality = tonumber(link:match("|cnIQ(%d+)")) end       -- this client colours links as |cnIQ<quality>:
    return id, quality or 1, price
end

local function record(link, count, attempt)
    local session = ns.session
    if not session then return end
    local id, quality, price = itemFacts(link)
    if price == nil and (attempt or 0) < 3 then                                -- item data not cached yet: look again shortly
        ns.After(1.0, function() record(link, count, (attempt or 0) + 1) end, "loot:retry")
        return
    end
    price = price or 0
    local name = link:match("%[(.-)%]") or "?"
    local loot = lootOf(session)
    local value = price * count
    loot.items, loot.vendor = loot.items + count, loot.vendor + value
    if quality == 0 then loot.junk = loot.junk + value end
    loot.byQ[quality] = loot.byQ[quality] or { n = 0, value = 0 }
    loot.byQ[quality].n, loot.byQ[quality].value = loot.byQ[quality].n + count, loot.byQ[quality].value + value
    local key = id or name
    local entry = loot.list[key] or { name = name, link = link, q = quality, n = 0, value = 0 }
    entry.n, entry.value = entry.n + count, entry.value + value
    loot.list[key] = entry
    loot.charKey = ns.charKey
    if quality >= 2 then
        table.insert(loot.drops, { name = name, link = link, q = quality, n = count, value = value, t = time() })
        if #loot.drops > 60 then table.remove(loot.drops, 1) end
        if ns.db.lootAnnounce then
            ns.Feed(string.format("%sLooted|r %s%s|r%s", ns.LABEL, ns.QualityColor(quality), name,
                value > 0 and ("  " .. ns.LABEL .. ns.strip(ns.money(value)) .. "|r") or ""), { tab = "loot", hold = 8 })
        end
    end
    if ns.PanelDirty then ns.PanelDirty() end
end

ns.On("CHAT_MSG_LOOT", function(msg)
    msg = S(msg)
    if not msg or msg:sub(1, #LOOT_PREFIX) ~= LOOT_PREFIX then return end
    local link = msg:match("(|c.-|h%[.-%]|h|?r?)") or msg:match("(|H.-|h%[.-%]|h)")
    if not link then return end
    local count = tonumber(msg:match("|h|?r?x(%d+)")) or tonumber(msg:match("x(%d+)%.?%s*$")) or 1
    record(link, count)
end, "loot:item")

ns.On("CHAT_MSG_MONEY", function(msg)
    msg = S(msg)
    if not msg or not ns.session then return end
    local g, s, c = tonumber(msg:match(GOLD)) or 0, tonumber(msg:match(SILVER)) or 0, tonumber(msg:match(COPPER)) or 0
    local total = g * 10000 + s * 100 + c
    if total <= 0 then return end
    local loot = lootOf(ns.session)
    loot.coin, loot.charKey = loot.coin + total, ns.charKey
    if ns.PanelDirty then ns.PanelDirty() end
end, "loot:coin")

----------------------------------------------------------------------
-- earlier sessions: a one-line summary each
----------------------------------------------------------------------
function ns.ArchiveLoot(session)
    local loot = session and session.loot
    if not loot or (loot.items == 0 and loot.coin == 0) or not ns.db then return end
    ns.db.lootHistory = ns.db.lootHistory or {}
    local q = {}
    for quality, b in pairs(loot.byQ) do q[quality] = b.n end
    local best
    for _, d in ipairs(loot.drops) do if not best or d.q > best.q or (d.q == best.q and d.value > best.value) then best = d end end
    table.insert(ns.db.lootHistory, { started = loot.started, ended = time(), char = loot.charKey, coin = loot.coin, vendor = loot.vendor,
        junk = loot.junk, items = loot.items, byQ = q, best = best and { name = best.name, q = best.q } or nil })
    while #ns.db.lootHistory > 30 do table.remove(ns.db.lootHistory, 1) end
end

function ns.ResetLoot()
    if not ns.session then return end
    ns.ArchiveLoot(ns.session)
    ns.session.loot = nil
    lootOf(ns.session, true)
    if ns.PanelDirty then ns.PanelDirty() end
    ns.say("loot session reset")
end

----------------------------------------------------------------------
-- what is in the bags right now that only a vendor wants
----------------------------------------------------------------------
function ns.JunkInBags()
    local CC = C_Container
    if not (CC and CC.GetContainerNumSlots and CC.GetContainerItemInfo) then return nil end
    local value, stacks = 0, 0
    for bag = 0, 4 do
        local slots = N(CC.GetContainerNumSlots(bag)) or 0
        for slot = 1, slots do
            local info = T(CC.GetContainerItemInfo(bag, slot))
            if info and N(info.quality) == 0 and not B(info.hasNoValue) then
                local link, count = S(info.hyperlink), N(info.stackCount) or 1
                local price = link and C_Item and C_Item.GetItemInfo and N((select(11, C_Item.GetItemInfo(link))))
                if price and price > 0 then value, stacks = value + price * count, stacks + 1 end
            end
        end
    end
    return value, stacks
end

function ns.LootView()
    local loot = ns.session and ns.session.loot
    if not loot then return nil end
    local stacks = {}
    for _, e in pairs(loot.list) do if e.value > 0 then stacks[#stacks + 1] = e end end
    table.sort(stacks, function(a, b) return a.value > b.value end)
    local elapsed = math.max(1, time() - (loot.started or ns.session.start))
    return { loot = loot, stacks = stacks, perHour = elapsed >= 120 and (loot.coin + loot.vendor) / elapsed * 3600 or nil }
end
