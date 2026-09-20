-- DearLord Stats 2.0 : Journal and summaries
-- Notes you jot down while playing (stamped with level, zone and time), and paste-ready
-- plain-text summaries of one character or of every character you have tried.
local ADDON, ns = ...

function ns.AddNote(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" or not ns.char then return false end
    table.insert(ns.char.journal, { t = time(), level = ns.curLevel, zone = ns.zone(), text = text })
    if ns.PanelDirty then ns.PanelDirty() end
    return true
end

function ns.RemoveNote(index)
    if ns.char and ns.char.journal[index] then
        table.remove(ns.char.journal, index)
        if ns.PanelDirty then ns.PanelDirty() end
    end
end

local function pctText(v) return v and string.format("%d%%", math.floor(v * 100 + 0.5)) or nil end
-- joins whatever is present; a missing value in the middle must not cut the rest off
local function J(sep, ...)
    local out = {}
    for i = 1, select("#", ...) do
        local p = select(i, ...)
        if p and p ~= "" then out[#out + 1] = p end
    end
    return table.concat(out, sep)
end

-- plain text, no colour codes, so it pastes cleanly anywhere
function ns.SummaryFor(key, c)
    local lines = {}
    local name, realm = key:match("^(.-)%-(.*)$")
    lines[#lines + 1] = string.format("%s: %s %s, level %s (%s)", name or key, c.race or "?", c.class or "?", tostring(c.level or "?"), realm or "?")

    local seconds, xp, kills, quests = 0, 0, 0, 0
    for _, r in pairs(c.levels or {}) do
        seconds, xp, kills, quests = seconds + (r.seconds or 0), xp + (r.xp or 0), kills + (r.kills or 0), quests + (r.quests or 0)
    end
    if seconds > 0 then
        lines[#lines + 1] = J(" · ", "Played " .. ns.shortTime(seconds) .. " with the addon",
            seconds >= 60 and (ns.shortNumber(xp / seconds * 3600) .. " xp/h") or nil,
            kills .. (kills == 1 and " kill" or " kills"), quests .. (quests == 1 and " quest" or " quests"))
    end

    local agg = c.combat
    if agg and agg.fights > 0 then
        local v = ns.CombatView(agg)
        lines[#lines + 1] = "Combat: " .. J(" · ", v.fights .. (v.fights == 1 and " fight" or " fights"),
            v.ttk and (ns.seconds(v.ttk) .. " per kill") or nil,
            v.dps and string.format("%.1f dps", v.dps) or nil,
            v.petShare and ("pet does " .. pctText(v.petShare)) or nil,
            v.combatShare and ("in combat " .. pctText(v.combatShare) .. " of the time") or nil,
            v.rest and ("rests " .. ns.seconds(v.rest) .. " between pulls") or nil)
        lines[#lines + 1] = "Safety: " .. J(" · ",
            v.takenPct and ("a fight costs " .. pctText(v.takenPct) .. " of its health") or nil,
            v.endHP and ("ends fights at " .. pctText(v.endHP) .. " health") or nil,
            v.endMana and (pctText(v.endMana) .. " mana") or nil,
            v.close .. (v.close == 1 and " close call" or " close calls"),
            v.oomFights > 0 and ("ran dry in " .. v.oomFights .. (v.oomFights == 1 and " fight" or " fights")) or nil,
            v.deaths .. (v.deaths == 1 and " death" or " deaths") .. (v.deathsPerHour and string.format(" (%.1f/h)", v.deathsPerHour) or ""))
        local sizes, label = {}, { "1 mob", "2 mobs", "3+ mobs" }
        for b = 1, 3 do
            local z = v.size[b]
            if z then
                sizes[#sizes + 1] = label[b] .. ": " .. J(", ", z.fights .. (z.fights == 1 and " fight" or " fights"),
                    z.endHP and ("health " .. pctText(z.endHP)) or (z.takenPct and ("costs " .. pctText(z.takenPct) .. " health")) or nil,
                    z.ttk and (ns.seconds(z.ttk) .. "/kill") or nil, z.deaths > 0 and (z.deaths .. (z.deaths == 1 and " death" or " deaths")) or nil)
            end
        end
        if #sizes > 1 then lines[#lines + 1] = "Pull size: " .. table.concat(sizes, " · ") end
        local levels = {}
        for lvl, a in pairs(c.byLevel or {}) do if a.fights >= 3 then levels[#levels + 1] = lvl end end
        table.sort(levels)
        if #levels > 0 then
            local recent = {}
            for i = math.max(1, #levels - 3), #levels do
                local lv = ns.CombatView(ns.LevelAggregate(c, levels[i]))
                recent[#recent + 1] = "L" .. levels[i] .. " " .. J(", ", lv.ttk and (ns.seconds(lv.ttk) .. "/kill") or nil,
                    lv.dps and string.format("%.1f dps", lv.dps) or nil, lv.takenPct and ("costs " .. pctText(lv.takenPct)) or nil)
            end
            lines[#lines + 1] = "By level: " .. table.concat(recent, " · ")
        end
        local abilities = ns.AbilityView(agg)
        if #abilities > 0 then
            local top = {}
            for i = 1, math.min(5, #abilities) do top[#top + 1] = abilities[i].name .. " " .. pctText(abilities[i].share) end
            lines[#lines + 1] = "Damage: " .. table.concat(top, " · ")
        end
    end

    local profs = {}
    for pname, p in pairs(c.prof or {}) do profs[#profs + 1] = string.format("%s %d/%d", pname, p.rank or 0, p.max or 0) end
    table.sort(profs)
    if #profs > 0 then lines[#lines + 1] = "Professions: " .. table.concat(profs, " · ") end

    if c.journal and #c.journal > 0 then
        lines[#lines + 1] = "Notes:"
        for _, n in ipairs(c.journal) do
            lines[#lines + 1] = string.format("  - L%s %s: %s", tostring(n.level or "?"), n.zone or "?", n.text)
        end
    end
    return table.concat(lines, "\n")
end

function ns.SummaryText(all)
    if not ns.db then return "" end
    if not all then
        local text = ns.SummaryFor(ns.charKey, ns.char)
        local loot = ns.session and ns.session.loot
        if loot and (loot.items > 0 or loot.coin > 0) then
            local drops = {}
            for q = 2, 5 do if loot.byQ[q] then drops[#drops + 1] = loot.byQ[q].n .. " " .. (ns.QUALITY_NAME[q] or ""):lower() end end
            text = text .. "\nLoot this session: " .. J(" · ", "coin " .. ns.money(loot.coin, false, true), "vendor value " .. ns.money(loot.vendor, false, true),
                loot.junk > 0 and ("junk " .. ns.money(loot.junk, false, true)) or nil, #drops > 0 and table.concat(drops, ", ") or nil)
        end
        return text
    end
    local keys = {}
    for key, c in pairs(ns.db.chars) do if c.class then keys[#keys + 1] = key end end
    table.sort(keys, function(a, b) return (ns.db.chars[a].lastSeen or 0) > (ns.db.chars[b].lastSeen or 0) end)
    local blocks = {}
    for _, key in ipairs(keys) do blocks[#blocks + 1] = ns.SummaryFor(key, ns.db.chars[key]) end
    return table.concat(blocks, "\n\n")
end
