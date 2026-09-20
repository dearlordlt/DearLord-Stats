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

ns.On("UNIT_SPELLCAST_SENT", function(unit, _, castGUID)
    if unit ~= "player" then return end
    castGUID = ns.S(castGUID)
    if not castGUID or busyCasting() or gcdRunning() then return end
    local now = GetTime()
    for guid, t in pairs(lag.pending) do if now - t > 5 then lag.pending[guid] = nil end end
    lag.pending[castGUID] = now
end, "lag:sent")

local function answered(unit, castGUID)
    if unit ~= "player" then return end
    castGUID = ns.S(castGUID)
    local t = castGUID and lag.pending[castGUID]
    lastCastAnswered = GetTime()
    if not t then return end
    lag.pending[castGUID] = nil
    local ms = math.floor((GetTime() - t) * 1000 + 0.5)
    if ms < 1 or ms > 5000 then return end
    table.insert(lag.samples, { ms = ms, at = GetTime() })
    if #lag.samples > 40 then table.remove(lag.samples, 1) end
end
ns.On("UNIT_SPELLCAST_START", answered, "lag:start")
ns.On("UNIT_SPELLCAST_SUCCEEDED", answered, "lag:succeeded")

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

local stats = ns.CreateHud("stats", 1, "CENTER")

stats:SetScript("OnEnter", function(self)
    self.bg:Show()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("DearLord Stats")
    GameTooltip:AddLine("H = home latency, W = world latency (the game refreshes these every ~30 s).", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("lag = measured live on your own casts.", 0.8, 0.8, 0.8)
    if #lag.samples > 0 then
        local med, worst, now = lagMedian(10, 300), 0, GetTime()
        for _, s in ipairs(lag.samples) do if now - s.at <= 300 and s.ms > worst then worst = s.ms end end
        GameTooltip:AddDoubleLine("Last cast", lag.samples[#lag.samples].ms .. " ms", 0.8, 0.8, 0.8, 1, 1, 1)
        if med then GameTooltip:AddDoubleLine("Typical (5 min)", med .. " ms", 0.8, 0.8, 0.8, 1, 1, 1) end
        GameTooltip:AddDoubleLine("Worst (5 min)", worst .. " ms", 0.8, 0.8, 0.8, 1, 1, 1)
    else
        GameTooltip:AddLine("Cast something after a short pause to get a reading.", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine("Click: open report.  Drag: move.  Right-click: options.", 0.6, 0.8, 1)
    GameTooltip:Show()
end)

local function refresh()
    if not ns.db then return end
    local _, _, home, world = GetNetStats()
    home, world = ns.N(home) or 0, ns.N(world) or 0
    local fps = math.floor((ns.N(GetFramerate()) or 0) + 0.5)
    local recent = lagMedian(5, 60)
    local lagText
    if recent then lagText = string.format("|cff%s%d|r", latencyColor(recent), recent)
    elseif #lag.samples > 0 then lagText = string.format("%s%d|r", LABEL, lag.samples[#lag.samples].ms)
    else lagText = LABEL .. "-|r" end
    stats.lines[1]:SetFormattedText("%sH|r |cff%s%d|r  %sW|r |cff%s%d|r %sms|r    %slag|r %s %sms|r    |cff%s%d|r %sfps|r",
        LABEL, latencyColor(home), home, LABEL, latencyColor(world), world, LABEL,
        LABEL, lagText, LABEL, fpsColor(fps), fps, LABEL)
    stats:Fit()
end
ns.Every(1, refresh, "stats:refresh")
ns.OnLogin(refresh, "stats:login")
