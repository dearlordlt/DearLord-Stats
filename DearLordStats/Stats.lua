-- DearLord Stats 2.0 : Stats line (home/world latency, measured spell lag, FPS)
local ADDON, ns = ...
local LABEL = ns.LABEL

local function latencyColor(ms)
    if ms >= 500 then return "ff6b6b" elseif ms >= 250 then return "ffd166" else return "ffffff" end
end
local function fpsColor(fps)
    if fps < 30 then return "ff6b6b" elseif fps < 60 then return "ffd166" else return "ffffff" end
end

-- Measured spell lag: time from sending a cast to the server's first answer.
-- The game's own latency figure only refreshes every ~30 s; this updates on every cast.
local lag = { pending = {}, samples = {} }
ns.lag = lag
local lastCastAnswered = 0
local GCD_SPELLS = { 29515, 61304 }        -- vanilla data first, modern data second

local function gcdRunning()
    local now = GetTime()
    for _, id in ipairs(GCD_SPELLS) do
        local info = C_Spell and C_Spell.GetSpellCooldown and ns.T(C_Spell.GetSpellCooldown(id))
        if info then
            local start, duration = ns.N(info.startTime), ns.N(info.duration)
            -- in combat these are hidden from addons; then only the timing rule below applies
            if start and duration and duration > 0 and (now - start) > 0.1 and (start + duration - now) > 0.05 then
                return true
            end
            break
        end
    end
    -- a cast sent within 1.6 s of the previous one may have been queued behind the global
    -- cooldown, which would measure the wait rather than the lag
    return (now - lastCastAnswered) < 1.6
end

local function busyCasting()
    if UnitCastingInfo and ns.exists((UnitCastingInfo("player"))) then return true end
    if UnitChannelInfo and ns.exists((UnitChannelInfo("player"))) then return true end
    return false
end

-- a spell with a cast time: its "cast started" answer is the lag; its "succeeded" comes a whole cast later
local function castTime(spellID)
    local info = spellID and C_Spell and C_Spell.GetSpellInfo and ns.T(C_Spell.GetSpellInfo(spellID))
    return info and ns.N(info.castTime) or 0
end
local function lagDiag(key)
    local d = ns.db and ns.db.diag
    if not d then return end
    d.lag = d.lag or {}
    d.lag[key] = (d.lag[key] or 0) + 1
end

ns.On("UNIT_SPELLCAST_SENT", function(unit, _, castGUID, spellID)
    if unit ~= "player" then return end
    castGUID = ns.S(castGUID)
    if not castGUID or busyCasting() or gcdRunning() then return end
    local now = GetTime()
    for guid, p in pairs(lag.pending) do if now - p.t > 5 then lag.pending[guid] = nil end end
    lag.pending[castGUID] = { t = now, cast = castTime(ns.N(spellID)) > 0 }
end, "lag:sent")

local function answer(kind)
    return function(unit, castGUID)
        if unit ~= "player" then return end
        castGUID = ns.S(castGUID)
        local p = castGUID and lag.pending[castGUID]
        lastCastAnswered = GetTime()
        if not p then return end
        lag.pending[castGUID] = nil
        if kind == "succeeded" and p.cast then lagDiag("castSkipped"); return end   -- its start answer was missed
        lagDiag(kind)
        local ms = math.floor((GetTime() - p.t) * 1000 + 0.5)
        if ms < 1 or ms > 5000 then return end
        table.insert(lag.samples, { ms = ms, at = GetTime() })
        if #lag.samples > 40 then table.remove(lag.samples, 1) end
    end
end
ns.On("UNIT_SPELLCAST_START", answer("start"), "lag:start")
ns.On("UNIT_SPELLCAST_CHANNEL_START", answer("channel"), "lag:channel")
ns.On("UNIT_SPELLCAST_SUCCEEDED", answer("succeeded"), "lag:succeeded")

-- median of up to `count` newest samples no older than `maxAge` seconds
local function lagMedian(count, maxAge)
    local now, picked = GetTime(), {}
    for i = #lag.samples, 1, -1 do
        local s = lag.samples[i]
        if now - s.at <= maxAge then picked[#picked + 1] = s.ms end
        if #picked >= count then break end
    end
    if #picked == 0 then return nil end
    table.sort(picked)
    return picked[math.ceil(#picked / 2)]
end
ns.lagMedian = lagMedian

-- the line itself lives at the top of the XP window (XP.lua asks for it every second)
function ns.StatsTooltip(tt)
    local G = 0.8
    tt:AddLine("Connection")
    tt:AddLine("H = home latency, W = world latency (the game refreshes these every ~30 s); lag = measured live on your own casts.", 0.6, 0.6, 0.6, true)
    if #lag.samples > 0 then
        local med, worst, now = lagMedian(10, 300), 0, GetTime()
        for _, s in ipairs(lag.samples) do if now - s.at <= 300 and s.ms > worst then worst = s.ms end end
        tt:AddDoubleLine("Last cast", lag.samples[#lag.samples].ms .. " ms", G, G, G, 1, 1, 1)
        if med then tt:AddDoubleLine("Typical (5 min)", med .. " ms", G, G, G, 1, 1, 1) end
        tt:AddDoubleLine("Worst (5 min)", worst .. " ms", G, G, G, 1, 1, 1)
    else
        tt:AddLine("Cast something after a short pause to get a lag reading.", 0.6, 0.6, 0.6)
    end
end

local SEP = "|cff8a8a8a  ·  |r"
function ns.StatsLine()
    local _, _, home, world = GetNetStats()
    home, world = ns.N(home) or 0, ns.N(world) or 0
    local fps = math.floor((ns.N(GetFramerate()) or 0) + 0.5)
    local recent = lagMedian(5, 60)
    local lagText
    if recent then lagText = string.format("|cff%s%d|r", latencyColor(recent), recent)
    elseif #lag.samples > 0 then lagText = string.format("%s%d|r", LABEL, lag.samples[#lag.samples].ms)
    else lagText = LABEL .. "-|r" end
    return string.format("|cff%s%d|r %sfps|r%s%sH|r |cff%s%d|r  %sW|r |cff%s%d|r %sms|r%s%slag|r %s %sms|r",
        fpsColor(fps), fps, LABEL, SEP,
        LABEL, latencyColor(home), home, LABEL, latencyColor(world), world, LABEL, SEP,
        LABEL, lagText, LABEL)
end
