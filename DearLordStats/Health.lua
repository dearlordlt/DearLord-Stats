-- DearLord Stats : client checks
-- Much of this addon leans on things a game patch can change or hide: threat numbers, the pet
-- bar, the cooldown manager, the auction house lists. Each part notes once what the client gave
-- it; this turns those notes into one list, shown under Summary > Client checks and by /dls check,
-- so what works, what is limited and what has not been tried yet can be seen at a glance.
local ADDON, ns = ...
local N, S = ns.N, ns.S

local function ago(t)
    if not t then return "" end
    local secs = math.max(0, time() - t)
    return ns.AuctionAgeText(math.floor(secs / 86400), secs)
end

-- { name, state = "ok" | "limited" | "bad" | "wait", detail }
function ns.HealthRows()
    local db, rows = ns.db, {}
    local d = db and db.diag or {}
    local class = UnitClass and S((select(2, UnitClass("player"))))
    local function add(name, state, detail) rows[#rows + 1] = { name = name, state = state, detail = detail } end

    local errs = db and db.errors or {}
    if #errs == 0 then add("Addon errors", "ok", "none logged")
    else add("Addon errors", "bad", #errs .. " logged; /dls errors lists the newest") end

    -- protected actions the game refused (frames it guards, mostly in combat)
    local refusedN, refusedLast, refusedAt = 0, nil, 0
    for fn, e in pairs(type(d.blocked) == "table" and d.blocked or {}) do
        if type(e) == "table" then
            refusedN = refusedN + (e.n or 0)
            if (e.at or 0) >= refusedAt then refusedAt, refusedLast = e.at or 0, fn .. ((e.combat and " in combat") or "") end
        end
    end
    if refusedN == 0 then add("Refused actions", "ok", "the game has refused the addon nothing")
    else add("Refused actions", "limited", refusedN .. " refused so far, the last " .. ago(refusedAt) .. ": " .. tostring(refusedLast)) end

    local slowN, slowMax, slowWhere = 0, 0, nil
    for label, e in pairs(type(d.slow) == "table" and d.slow or {}) do
        slowN = slowN + (e.n or 0)
        if (e.max or 0) > slowMax then slowMax, slowWhere = e.max, label end
    end
    if slowN == 0 then add("Smoothness", "ok", "no call has taken longer than 50 ms")
    else add("Smoothness", slowMax >= 150 and "limited" or "ok", slowN .. " call" .. (slowN == 1 and "" or "s") .. " over 50 ms so far, the longest " .. slowMax .. " ms (" .. tostring(slowWhere) .. ")") end

    if d.damageMeter == nil then add("Fights", "wait", "no fight recorded this session yet")
    elseif d.damageMeter then add("Fights", "ok", "read from the game's damage meter (" .. (d.fightsFromMeter or 0) .. " of " .. (d.fights or 0) .. " fights)")
    else add("Fights", "limited", "the game's damage meter is not there: counted from hit events alone") end

    local tp = S(d.threatProbe)
    if not tp then add("Threat numbers", "wait", "fight once with a pet out or in a group")
    else
        local scaled = tp:match("player:[^/]*/[^/]*/([^/]*)/")
        if tonumber(scaled) then add("Threat numbers", "ok", "readable in a fight: sorted bars, percentages and the pull warning")
        else add("Threat numbers", "limited", "hidden in a fight: the bars fill, but there is no sorting and no pull warning") end
    end

    if class == "HUNTER" or d.growlProbe then
        local gp, click = S(d.growlProbe), S(d.growlClick)
        if not gp then add("Growl reminder", "wait", "call your pet once")
        elseif click == "no effect" then add("Growl reminder", "bad", "autocast is read, but the click did not switch it: use the pet bar")
        elseif click == "worked" then add("Growl reminder", "ok", "autocast is read and a click on the banner switches it")
        else add("Growl reminder", "ok", "autocast is read; the banner's click has not been tried yet") end
    end

    local kp = S(d.keysProbe)
    if not kp then add("Keys on the cooldown manager", "wait", "no cooldown manager icon seen this session")
    else
        local icons, bound = kp:match("icons=(%d+) boundSpells=(%d+)")
        local matched = select(2, kp:gsub(">[^n ][^ ]*", ""))        -- probes ending in a key, not in ">nil"
        add("Keys on the cooldown manager", (tonumber(bound) or 0) > 0 and "ok" or "limited",
            (icons or "?") .. " icons, " .. (bound or "?") .. " spells with a key on your bars" .. (matched > 0 and "" or "; none of the first icons matched"))
    end

    local ah = type(d.ah) == "table" and d.ah or {}
    local last = type(ah.lastScan) == "table" and ah.lastScan or nil
    -- the newest request, when it ended without a list and nothing was read since
    local req = ah.log and ah.log[1]
    if req and req.out and not req.out:find("^read") and not req.late and (not last or (last.at or 0) < req.at) then
        add("Auction scan", "limited", "the last request (" .. ago(req.at) .. ") ended with: " .. req.out
            .. (last and ("; prices are from " .. ago(last.at)) or ""))
    elseif last then add("Auction scan", "ok", (last.items or "?") .. " items from " .. (last.rows or "?") .. " auctions, " .. ago(last.at))
    else add("Auction scan", "wait", "not scanned yet: Scan prices at an auction house") end
    if (ah.sights or 0) > 0 then add("Prices from searches", "ok", ah.sights .. " update" .. (ah.sights == 1 and "" or "s") .. " from auction house searches")
    else add("Prices from searches", "wait", "search for an item at the auction house, or put one in the sell tab") end

    if d.merchantRow ~= nil then add("Vendor prices", "ok", "read when you visit a vendor")
    else add("Vendor prices", "wait", "visit a vendor once") end

    if d.recipeScan ~= nil then
        add("Recipes", d.recipeScan == "ok" and "ok" or "limited", d.recipeScan == "ok" and "read from your profession windows" or tostring(d.recipeScan))
    else add("Recipes", "wait", "open a profession window once") end

    if class == "HUNTER" or d.petProbe then
        local pp = S(d.petProbe)
        if not pp then add("Pet details", "wait", "call your pet once")
        else add("Pet details", pp:find("GetPetHappiness=%d") and "ok" or "limited", pp:find("GetPetHappiness=%d") and "happiness, loyalty and training points are read" or "the pet calls answer, but without a happiness number") end
    end

    local cs = type(d.census) == "table" and d.census or {}
    if (cs.sent or 0) > 0 then
        local share = (cs.answers or 0) / cs.sent
        add("Census", share >= 0.8 and "ok" or "limited", (cs.answers or 0) .. " of " .. cs.sent .. " /who queries answered")
    else add("Census", "wait", "no /who query sent yet") end

    local rp = S(d.readyProbe)
    if not rp then add("Ready check", "wait", "runs when you join a group, or with /dls ready")
    else
        local parts = {}
        parts[#parts + 1] = rp:find("itemSpell=true", 1, true) and "food and drink are told apart" or "food and drink cannot be told apart (not checked)"
        parts[#parts + 1] = rp:find("free=nil", 1, true) and "bag room unknown" or "bag room read"
        parts[#parts + 1] = rp:find("durability=nil", 1, true) and "no durability read" or "durability read"
        parts[#parts + 1] = rp:find("known=true", 1, true) and "known spells read" or "known spells cannot be read (no class checks)"
        local limited = not rp:find("itemSpell=true", 1, true) or not rp:find("known=true", 1, true)
        add("Ready check", limited and "limited" or "ok", table.concat(parts, ", "))
    end

    local pt = S(d.partyTargetProbe)
    if not pt then add("Party targets", "wait", "join a party with its frames on screen")
    else
        local secure, driver = pt:find("secure=true", 1, true) ~= nil, pt:find("mode=manual", 1, true) == nil
        add("Party targets", (secure and driver) and "ok" or "limited", "placed beside the game's party frames (" .. (pt:match("first=(%S+)") or "?") .. ")"
            .. (secure and "" or "; no secure button here, so a click cannot target") .. (driver and "" or "; shown and hidden by hand, out of fights only"))
    end

    if db and db.partySolo then
        local solo = ns.partyTargets and ns.partyTargets.solo or {}
        if solo.missing then add("Party frame when alone", "bad", "this client has no raid-style party frame by the usual name")
        elseif S(d.partySoloProbe) and d.partySoloProbe:find("^applied") then
            local visible = d.partySoloProbe:match("frame=y(%a)") == "y"
            add("Party frame when alone", visible and "ok" or "limited", visible and "shown while you are in no group, out of combat" or "asked to show, but the client keeps it off screen")
        else add("Party frame when alone", "wait", "leave your group, out of combat, with raid-style party frames on") end
    end

    if not db or db.shieldBar ~= false then
        local sh = type(d.shield) == "table" and d.shield or {}
        local seen = S(sh.combat) or S(sh.calm)
        local where = S(sh.combat) and "in a fight" or "out of a fight"
        local mode = seen and seen:match("mode=(%a+)")
        if not seen then
            add("Shield bar", "wait", "no shield seen on you yet (/dls shield previews the bar)"
                .. (sh.api == "no" and "; this client has no absorb amount, the bar will show the time left" or ""))
        elseif mode == "amount" then add("Shield bar", "ok", "the amount left is read as a number, " .. where)
        elseif mode == "hidden" then
            local kind = seen:match("max=[^(]*%((%a+)%)")
            add("Shield bar", kind == "health" and "limited" or "ok", "the amount is hidden from addons " .. where .. ": the bar and number follow it anyway"
                .. (kind == "health" and ", measured against your health (the shield's full size is not known yet)" or ", against the shield's full size"))
        else add("Shield bar", "limited", "this client gives no amount " .. where .. ": the bar shows the time left") end
    end

    if GetBuildInfo then
        local version, build, _, interface = GetBuildInfo()
        add("Game client", "ok", "version " .. tostring(S(version) or "?") .. ", build " .. tostring(S(build) or "?") .. ", interface " .. tostring(N(interface) or "?"))
    end
    return rows
end

local WORD = { ok = "works", limited = "limited", bad = "not working", wait = "not tried yet" }
function ns.HealthWord(state) return WORD[state] or state end
function ns.HealthColor(state)
    return state == "ok" and ns.GREEN or state == "limited" and ns.AMBER or state == "bad" and ns.RED or ns.LABEL
end

-- /dls check: the count in chat, the list in the panel
function ns.HealthSummary()
    local n = { ok = 0, limited = 0, bad = 0, wait = 0 }
    for _, r in ipairs(ns.HealthRows()) do n[r.state] = (n[r.state] or 0) + 1 end
    return n.ok .. " work, " .. n.limited .. " limited, " .. n.bad .. " not working, " .. n.wait .. " not tried yet", n
end
