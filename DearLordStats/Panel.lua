-- DearLord Stats 2.0 : Report panel
-- One quiet window for everything that does not belong on screen all the time.
-- Flat dark surface, thin hairline border, text only. Opens with a click on the HUD,
-- closes with Escape, remembers its place, scrolls with the mouse wheel.
local ADDON, ns = ...
local L, W = ns.LABEL, ns.WHITE

local WIDTH, HEIGHT, PAD = 540, 460, 14          -- default size; the panel can be resized by its corner
local MIN_W, MIN_H, MAX_W, MAX_H = 500, 260, 1100, 1300
local function innerWidth() return ((panel and panel:GetWidth()) or WIDTH) - PAD * 2 - 8 end
local FONT = STANDARD_TEXT_FONT
local TABS = { { key = "combat", text = "Combat" }, { key = "abilities", text = "Abilities" },
    { key = "professions", text = "Professions" }, { key = "loot", text = "Loot" }, { key = "journal", text = "Journal" },
    { key = "summary", text = "Summary" }, { key = "settings", text = "Settings" } }
local SCOPES = {
    combat = { { key = "session", text = "Session" }, { key = "level", text = "Level" }, { key = "character", text = "Character" } },
    abilities = { { key = "session", text = "Session" }, { key = "level", text = "Level" }, { key = "character", text = "Character" } },
    summary = { { key = "one", text = "Current" }, { key = "all", text = "All characters" } },
}

local panel, scroll, child, footer, noteBox, summaryBox, selectAll
local tabButtons, scopeButtons = {}, {}
local rows, used = {}, 0
local state = { tab = "combat", scope = { combat = "session", abilities = "session", summary = "one" }, dirty = true, offset = 0 }
local cursor = 0
local renderNow
local settingsPage
local function fsize(delta) return ((ns.db and ns.db.panelFontSize) or 12) + (delta or 0) end

local function ago(t)
    local d = time() - (t or 0)
    if d < 90 then return "just now" end
    if d < 3600 then return math.floor(d / 60) .. " min ago" end
    if d < 86400 then return math.floor(d / 3600) .. " h ago" end
    return math.floor(d / 86400) .. " d ago"
end
local function pctText(v) return v and string.format("%d%%", math.floor(v * 100 + 0.5)) or "-" end

----------------------------------------------------------------------
-- small building blocks
----------------------------------------------------------------------
local function textButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size or 12, "")
    fs:SetPoint("CENTER")
    b.fs = fs
    local line = b:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.5, 0.7, 1, 0.9)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, -3)
    line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, -3)
    line:Hide()
    b.line = line
    function b:SetLabel(text) self.fs:SetText(text); self:SetSize(self.fs:GetStringWidth() + 2, 16) end
    function b:SetActive(on)
        self.active = on
        self.fs:SetTextColor(on and 1 or 0.62, on and 1 or 0.62, on and 1 or 0.62)
        self.line:SetShown(on)
    end
    b:SetScript("OnEnter", function(self) if not self.active then self.fs:SetTextColor(0.9, 0.9, 0.9) end end)
    b:SetScript("OnLeave", function(self) self:SetActive(self.active) end)
    return b
end

local function getRow()
    used = used + 1
    local r = rows[used]
    if not r then
        r = CreateFrame("Frame", nil, child)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.05); r.hl:Hide()
        r.bar = r:CreateTexture(nil, "BORDER")
        r.bar:SetColorTexture(0.5, 0.7, 1, 0.16)
        r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT")
        r.rule = r:CreateTexture(nil, "BORDER")
        r.rule:SetColorTexture(1, 1, 1, 0.08); r.rule:SetHeight(1)
        r.rule:SetPoint("BOTTOMLEFT"); r.rule:SetPoint("BOTTOMRIGHT")
        r.left = r:CreateFontString(nil, "OVERLAY")
        r.left:SetFont(FONT, fsize(), "")            -- the client refuses SetText on a label without a font
        r.left:SetJustifyH("LEFT"); r.left:SetJustifyV("TOP")
        r.right = r:CreateFontString(nil, "OVERLAY")
        r.right:SetFont(FONT, fsize(), "")
        r.right:SetJustifyH("RIGHT")
        r:SetScript("OnEnter", function(self)
            if self.tip or self.onRight or self.onClick or self.link then self.hl:Show() end
            if self.link then                                    -- an item: show the game's own tooltip for it
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                if not pcall(GameTooltip.SetHyperlink, GameTooltip, self.link) then GameTooltip:Hide() end
            elseif self.tip then
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:AddLine(self.tip, 0.9, 0.9, 0.9, true)
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
        r:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" and self.onRight then ns.safe("panel:row", self.onRight)
            elseif button == "LeftButton" and self.onClick then ns.safe("panel:row", self.onClick) end
        end)
        rows[used] = r
    end
    r.tip, r.onRight, r.onClick, r.link = nil, nil, nil, nil
    r.bar:Hide(); r.rule:Hide(); r.hl:Hide()
    r.left:SetText(""); r.right:SetText("")
    r.left:ClearAllPoints(); r.right:ClearAllPoints()
    r.left:SetWordWrap(false)
    r:EnableMouse(false)
    r:Show()
    return r
end

local function place(r, height, indent)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", child, "TOPLEFT", indent or 0, -cursor)
    r:SetSize(innerWidth() - (indent or 0), height)
    cursor = cursor + height
end

local function GAP(h) cursor = cursor + (h or 8) end

local function H(text)
    if cursor > 0 then GAP(12) end
    local r = getRow()
    r.left:SetFont(FONT, fsize(-2), "")
    r.left:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 4)
    r.left:SetText("|cff8fa3b8" .. text:upper() .. "|r")
    r.rule:Show()
    place(r, fsize(-2) + 8)
    GAP(4)
end

-- opts: tip, onRight, indent, bar (0..1)
local function KV(left, right, opts)
    opts = opts or {}
    local r = getRow()
    r.left:SetFont(FONT, fsize(), ""); r.right:SetFont(FONT, fsize(), "")
    r.right:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.left:SetText(left or ""); r.right:SetText(right or "")
    r.left:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.left:SetPoint("RIGHT", r.right, "LEFT", -12, 0)      -- a long label is cut off cleanly instead of overlapping
    r.tip, r.onRight, r.onClick, r.link = opts.tip, opts.onRight, opts.onClick, opts.link
    if opts.tip or opts.onRight or opts.onClick or opts.link then r:EnableMouse(true) end
    place(r, fsize() + 6, opts.indent)
    if opts.bar then
        r.bar:SetWidth(math.max(1, (r:GetWidth()) * math.min(1, opts.bar)))
        r.bar:Show()
    end
    return r
end

local function P(text, indent)
    local r = getRow()
    local width = innerWidth() - 8 - (indent or 0)
    r.left:SetFont(FONT, fsize(), "")
    r.left:SetWordWrap(true)
    r.left:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -2)
    r.left:SetWidth(width)
    r.left:SetText(text)
    local h = math.max(16, (r.left:GetStringHeight() or 14) + 4)
    place(r, h, indent)
    return r
end

----------------------------------------------------------------------
-- tab contents
----------------------------------------------------------------------
local render = {}

local function recentReminders(tab)
    local list = {}
    for i = #ns.recentNudges, 1, -1 do
        if ns.recentNudges[i].tab == tab then list[#list + 1] = ns.recentNudges[i] end
    end
    if #list == 0 then return end
    H("Recent reminders")
    for i = 1, math.min(5, #list) do KV(list[i].text, L .. ago(list[i].t) .. "|r") end
end


-- the level being looked at in the "Level" view; nil means the current one
local function viewLevel() return state.level or ns.curLevel or 1 end
local function aggregateFor(scope)
    if scope == "character" then return ns.char.combat
    elseif scope == "level" then return ns.LevelAggregate(ns.char, viewLevel()) or ns.newAggregate() end
    return ns.session.combat
end
local function stepLevel(delta)
    local levels = {}
    for lvl in pairs(ns.char.byLevel) do levels[#levels + 1] = lvl end
    table.sort(levels)
    if #levels == 0 then return end
    local cur, idx = viewLevel(), #levels
    for i, lvl in ipairs(levels) do if lvl == cur then idx = i end end
    state.level = levels[math.max(1, math.min(#levels, idx + delta))]
    state.offset = 0
    renderNow()
end
local function levelStepper()
    KV(L .. "Looking at|r  " .. W .. "level " .. viewLevel() .. "|r", L .. "click: earlier level   right-click: later|r",
        { onClick = function() stepLevel(-1) end, onRight = function() stepLevel(1) end,
          tip = "Only fights fought at this level. Levels fill in from now on; older fights are only in the Character view." })
end
local function sliceLine(z)
    local parts = { z.fights .. (z.fights == 1 and " fight" or " fights") }
    if z.ttk then parts[#parts + 1] = ns.seconds(z.ttk) .. " per kill" end
    if z.dps then parts[#parts + 1] = string.format("%.1f dps", z.dps) end
    if z.takenPct then parts[#parts + 1] = "costs " .. pctText(z.takenPct) .. " health" end
    if (z.deaths or 0) > 0 then parts[#parts + 1] = ns.RED .. z.deaths .. (z.deaths == 1 and " death" or " deaths") .. "|r" end
    return W .. table.concat(parts, L .. "  ·  |r" .. W) .. "|r"
end

function render.combat(scope)
    local agg = aggregateFor(scope)
    local v = ns.CombatView(agg)
    if scope == "level" then levelStepper() end
    if v.fights == 0 then
        local where = scope == "session" and " this session" or (scope == "level" and (" at level " .. viewLevel()) or "")
        P(L .. "No fights recorded yet" .. where .. ". Go and hit something.|r")
        return
    end
    H("Overview")
    KV(L .. "Fights|r", W .. v.fights .. "|r  " .. L .. "(" .. v.kills .. (v.kills == 1 and " kill)|r" or " kills)|r"))
    KV(L .. "Time per kill|r", W .. ns.seconds(v.ttk) .. "|r", { tip = "Fight time divided by mobs killed. The plain feel of how fast things die." })
    KV(L .. "Damage per second|r", v.dps and (W .. string.format("%.1f", v.dps) .. "|r" .. (v.petShare and ("  " .. L .. "pet " .. pctText(v.petShare) .. "|r") or "")) or "-",
        { tip = "From the game's built-in damage meter, read after each fight." })
    KV(L .. "In combat|r", W .. pctText(v.combatShare) .. "|r " .. L .. "of played time|r")
    KV(L .. "Rest between pulls|r", W .. ns.seconds(v.rest) .. "|r", { tip = "Average pause between one fight and the next, counting only pauses under 90 s. High numbers mean eating, drinking or bandaging a lot." })

    H("Safety")
    KV(L .. "Damage taken per fight|r", W .. pctText(v.takenPct) .. "|r " .. L .. "of your health pool|r",
        { tip = "This client hides your current health from addons, so danger is measured as how much of your total health an average fight costs you." })
    if v.healedPct then KV(L .. "Healed back during fights|r", W .. pctText(v.healedPct) .. "|r " .. L .. "of your health pool|r") end
    if v.endHP then KV(L .. "Health after a fight|r", W .. pctText(v.endHP) .. "|r") end
    if v.endMana then KV(L .. "Mana after a fight|r", W .. pctText(v.endMana) .. "|r") end
    KV(L .. "Close calls|r", (v.close > 0 and ns.AMBER or W) .. v.close .. "|r", { tip = "Fights where the low-health warning came up, or where you took most of your health pool in damage." })
    KV(L .. "Ran out of mana, rage or energy|r", W .. v.oomFights .. "|r " .. L .. (v.oomFights == 1 and "fight|r" or "fights|r"))
    KV(L .. "Deaths|r", (v.deaths > 0 and ns.RED or W) .. v.deaths .. "|r" .. (v.deathsPerHour and ("  " .. L .. string.format("%.1f per hour", v.deathsPerHour) .. "|r") or ""))

    local label = { "One mob", "Two mobs", "Three or more" }
    local any = false
    for b = 1, 3 do if v.size[b] then any = true end end
    if any then
        H("By pull size")
        for b = 1, 3 do
            local z = v.size[b]
            if z then
                local parts = { z.fights .. (z.fights == 1 and " fight" or " fights") }
                if z.ttk then parts[#parts + 1] = ns.seconds(z.ttk) .. " per kill" end
                if z.endHP then parts[#parts + 1] = "health " .. pctText(z.endHP)
                elseif z.takenPct then parts[#parts + 1] = "costs " .. pctText(z.takenPct) .. " health" end
                if z.deaths > 0 then parts[#parts + 1] = ns.RED .. z.deaths .. (z.deaths == 1 and " death" or " deaths") .. "|r" end
                KV(L .. label[b] .. "|r", W .. table.concat(parts, L .. "  ·  |r" .. W) .. "|r")
            end
        end
    end

    if scope == "character" then
        local levels = {}
        for lvl, a in pairs(ns.char.byLevel) do if a.fights > 0 then levels[#levels + 1] = lvl end end
        table.sort(levels, function(a, b) return a > b end)
        if #levels > 0 then
            H("By level")
            for _, lvl in ipairs(levels) do
                KV(L .. "Level " .. lvl .. "|r", sliceLine(ns.CombatView(ns.LevelAggregate(ns.char, lvl))),
                    { onClick = function() state.scope.combat, state.level, state.offset = "level", lvl, 0; renderNow() end,
                      tip = "Click to look at this level on its own." })
            end
        end
        local order, names = { "lower", "even", "higher" }, { lower = "Lower level", even = "About your level", higher = "Higher level" }
        local tips = { lower = "Mobs three or more levels below you.", even = "Mobs from two levels below you to one above.", higher = "Mobs two or more levels above you." }
        local anyDiff = false
        for _, k in ipairs(order) do if ns.char.byDiff[k] and ns.char.byDiff[k].fights > 0 then anyDiff = true end end
        if anyDiff then
            H("By mob level")
            for _, k in ipairs(order) do
                local a = ns.char.byDiff[k]
                if a and a.fights > 0 then KV(L .. names[k] .. "|r", sliceLine(ns.CombatView(a)), { tip = tips[k] }) end
            end
        end
        local zones = {}
        for zone, a in pairs(ns.char.byZone) do if a.fights > 0 then zones[#zones + 1] = zone end end
        table.sort(zones, function(a, b) return ns.char.byZone[a].fights > ns.char.byZone[b].fights end)
        if #zones > 0 then
            H("By zone")
            for i = 1, math.min(8, #zones) do KV(L .. zones[i] .. "|r", sliceLine(ns.CombatView(ns.char.byZone[zones[i]]))) end
        end
        local tough = ns.ToughestMobs(5)
        if #tough > 0 then
            H("Toughest opponents")
            for _, m in ipairs(tough) do
                KV(W .. m.name .. "|r" .. (m.level and ("  " .. L .. "level " .. m.level .. "|r") or ""),
                    W .. "costs " .. pctText(m.cost) .. " health|r" .. L .. "  ·  " .. m.fights .. " fights" .. (m.ttk and ("  ·  " .. ns.seconds(m.ttk)) or "") .. "|r",
                    { tip = "Average share of your health pool lost per fight against this mob, single pulls only, at least two fights." })
            end
        end
    end

    if scope == "character" and #ns.char.deathLog > 0 then
        H("Recent deaths")
        for i = #ns.char.deathLog, math.max(1, #ns.char.deathLog - 4), -1 do
            local d = ns.char.deathLog[i]
            KV(L .. "Level " .. tostring(d.level or "?") .. "|r  " .. W .. (d.zone or "?") .. ((d.sub and d.sub ~= "") and (", " .. d.sub) or "") .. "|r", L .. ago(d.t) .. "|r")
        end
    end
end

function render.abilities(scope)
    local agg = aggregateFor(scope)
    local casts = scope == "character" and ns.char.casts or (scope == "session" and ns.session.casts or nil)
    if scope == "level" then levelStepper() end
    local list, total = ns.AbilityView(agg, casts)
    H("Where your damage comes from")
    if #list == 0 then
        P(L .. "Nothing yet. The breakdown fills in after each fight.|r")
    else
        for i = 1, math.min(14, #list) do
            local a = list[i]
            local right = W .. pctText(a.share) .. "|r  " .. L .. ns.shortNumber(a.dmg) .. "|r" .. (a.casts and ("  " .. L .. "×" .. a.casts .. "|r") or "")
            KV(W .. a.name .. "|r", right, { bar = a.share, tip = "Share of your total damage, total damage, and how many times you used it." })
        end
        GAP(2)
        KV(L .. "Total|r", W .. ns.shortNumber(total) .. "|r")
    end

    local missing, unused = ns.spells.missing, ns.spells.unused
    if #missing > 0 then
        H("Learned, but not on your bars")
        for _, name in ipairs(missing) do
            KV(W .. name .. "|r", L .. "right-click to ignore|r", { onRight = function() ns.IgnoreSpell(name) end,
                tip = "This spell is in your spellbook but on no action bar or macro." })
        end
    end
    recentReminders("abilities")
    if #unused > 0 and ns.UnusedIsMeaningful() then
        H("On your bars, never pressed this session")
        for _, name in ipairs(unused) do
            KV(W .. name .. "|r", L .. "right-click to ignore|r", { onRight = function() ns.IgnoreSpell(name) end })
        end
    end
end

function render.professions()
    local profs = ns.ProfessionsView()
    if #profs == 0 then
        P(L .. "No professions on this character yet.|r")
    end
    for _, p in ipairs(profs) do
        H(p.name .. "   " .. p.rank .. " / " .. p.max)
        if p.ups > 0 or p.gathers > 0 then
            local parts = {}
            if p.ups > 0 then parts[#parts + 1] = ns.GREEN .. "+" .. p.ups .. "|r" .. W .. (p.ups == 1 and " point" or " points") end
            if p.rate then parts[#parts + 1] = string.format("%.0f per hour", p.rate) end
            if p.gathers > 0 then parts[#parts + 1] = p.gathers .. " gathers" end
            KV(L .. "This session|r", W .. table.concat(parts, L .. "  ·  |r" .. W) .. "|r")
        end
        if p.craft then
            local c = p.craft
            local DIFF = { [0] = "|cffff8040", [1] = "|cffffff00", [2] = "|cff40c040" }      -- the game's own recipe colours
            if c.orange + c.yellow + c.green > 0 then
                local parts = {}
                if c.orange > 0 then parts[#parts + 1] = DIFF[0] .. c.orange .. " sure|r" end
                if c.yellow > 0 then parts[#parts + 1] = DIFF[1] .. c.yellow .. " likely|r" end
                if c.green > 0 then parts[#parts + 1] = DIFF[2] .. c.green .. " maybe|r" end
                KV(L .. "Craft now from your bags|r", table.concat(parts, L .. "  ·  |r") .. L .. string.format("   about %.0f points|r", math.max(1, c.expected)),
                    { tip = "Orange recipes always give a point, yellow ones usually do, green ones only now and then. Based on the recipes seen when you last opened this profession window." })
                for i = 1, math.min(5, #c.list) do
                    local item = c.list[i]
                    KV((DIFF[item.diff] or W) .. item.times .. " ×|r  " .. W .. item.name .. "|r", "", { indent = 12 })
                end
            else
                KV(L .. "Craft now from your bags|r", L .. "nothing that gives points|r")
            end
        elseif p.name ~= "Mining" and p.name ~= "Herbalism" and p.name ~= "Skinning" and p.name ~= "Fishing" then
            P(L .. "Open the " .. p.name .. " window once and your recipes will be remembered.|r")
        end
        local s = p.shopping
        if s and s.recipe then
            KV(L .. "To reach " .. s.target .. "|r  " .. L .. "(" .. s.reason .. ")|r", W .. s.crafts .. " × " .. s.recipe .. "|r",
                { tip = "An estimate using the cheapest recipe you know that still gives points. Recipes turn yellow and green as you go, so treat it as a guide." })
            for _, m in ipairs(s.mats) do
                local right = m.short > 0 and (ns.AMBER .. "need " .. m.short .. " more|r  " .. L .. "have " .. m.have .. "|r") or (ns.GREEN .. "have enough|r")
                KV(W .. m.total .. " ×|r  " .. W .. m.name .. "|r", right, { indent = 12 })
            end
        end
        for _, u in ipairs(p.unlocks) do
            KV((u.ready and ns.GREEN or L) .. "at " .. u.req .. "|r  " .. W .. u.service .. "|r", u.ready and (ns.GREEN .. "trainable|r") or "", { indent = 12 })
        end
    end

    local zones = {}
    for zone, byProf in pairs(ns.char.gather) do zones[#zones + 1] = zone end
    table.sort(zones)
    if #zones > 0 then
        H("Gathered by zone")
        for _, zone in ipairs(zones) do
            for prof, rec in pairs(ns.char.gather[zone]) do
                local items = {}
                for name, count in pairs(rec.items) do items[#items + 1] = { name = name, count = count } end
                table.sort(items, function(a, b) return a.count > b.count end)
                local text = {}
                for i = 1, math.min(3, #items) do text[#text + 1] = items[i].count .. " " .. items[i].name end
                KV(W .. zone .. "|r  " .. L .. prof .. ", " .. rec.gathers .. " gathers|r", L .. table.concat(text, ", ") .. "|r")
            end
        end
    end

    recentReminders("professions")

    if #ns.char.lowskill > 0 then
        H("Skill was too low for")
        for i = #ns.char.lowskill, math.max(1, #ns.char.lowskill - 7), -1 do
            local e = ns.char.lowskill[i]
            KV(W .. (e.node or "something") .. "|r  " .. L .. e.zone .. "|r",
                ns.AMBER .. e.skill .. " " .. e.req .. "|r" .. (e.had and ("  " .. L .. "you had " .. e.had .. "|r") or ""),
                { onRight = function() table.remove(ns.char.lowskill, i); ns.PanelDirty() end, tip = "Right-click to remove this entry." })
        end
    end
end

function render.loot()
    local view = ns.LootView()
    local loot = view and view.loot
    if not loot or (loot.items == 0 and loot.coin == 0) then
        P(L .. "Nothing looted yet this session.|r")
    else
        H("This session")
        KV(L .. "Looted coin|r", W .. ns.money(loot.coin) .. "|r")
        KV(L .. "Vendor value of looted items|r", W .. ns.money(loot.vendor) .. "|r" .. (loot.junk > 0 and ("  " .. L .. "of which junk " .. ns.strip(ns.money(loot.junk)) .. "|r") or ""),
            { tip = "What a vendor would pay for everything you looted, whether or not you kept it." })
        KV(L .. "Items looted|r", W .. loot.items .. "|r")
        KV(L .. "Coin and vendor value per hour|r", view.perHour and (W .. ns.money(view.perHour) .. "|r") or (L .. "-|r"))
        KV(ns.BLUE .. "Reset the loot session|r", L .. "click|r", { onClick = function() ns.ResetLoot(); renderNow() end,
            tip = "Files this session under Previous sessions and starts counting again. XP and combat are not touched." })

        H("By quality")
        for q = 0, 5 do
            local b = loot.byQ[q]
            if b then
                KV(ns.QualityColor(q) .. (ns.QUALITY_NAME[q] or "?") .. "|r", W .. b.n .. "|r " .. L .. (b.n == 1 and "item" or "items") .. "  ·  |r" .. W .. ns.money(b.value) .. "|r")
            end
        end

        if #loot.drops > 0 then
            H("Notable drops")
            for i = #loot.drops, math.max(1, #loot.drops - 11), -1 do
                local d = loot.drops[i]
                KV(ns.QualityColor(d.q) .. d.name .. "|r" .. (d.n > 1 and (L .. "  ×" .. d.n .. "|r") or ""),
                    (d.value > 0 and (W .. ns.money(d.value) .. "|r  ") or "") .. L .. ago(d.t) .. "|r", { link = d.link })
            end
        end

        if #view.stacks > 0 then
            H("Most valuable to a vendor")
            for i = 1, math.min(8, #view.stacks) do
                local e = view.stacks[i]
                KV(ns.QualityColor(e.q) .. e.name .. "|r" .. L .. "  ×" .. e.n .. "|r", W .. ns.money(e.value) .. "|r", { link = e.link })
            end
        end
    end

    local junk, stacks = ns.JunkInBags()
    if junk then
        H("In your bags right now")
        KV(L .. "Junk a vendor will buy|r", junk > 0 and (W .. ns.money(junk) .. "|r  " .. L .. stacks .. (stacks == 1 and " stack|r" or " stacks|r")) or (L .. "none|r"))
    end

    local history = ns.db.lootHistory or {}
    if #history > 0 then
        H("Previous sessions")
        for i = #history, math.max(1, #history - 9), -1 do
            local s = history[i]
            local parts = {}
            for q = 2, 5 do if s.byQ and s.byQ[q] then parts[#parts + 1] = ns.QualityColor(q) .. s.byQ[q] .. " " .. (ns.QUALITY_NAME[q] or ""):lower() .. "|r" end end
            local who = s.char and s.char:match("^(.-)%-") or "?"
            KV(L .. date("%d %b %H:%M", s.started or s.ended) .. "  ·  " .. ns.shortTime((s.ended or 0) - (s.started or 0)) .. "  ·  " .. who .. "|r",
                W .. ns.money((s.coin or 0) + (s.vendor or 0)) .. "|r" .. (#parts > 0 and ("  " .. table.concat(parts, L .. ", |r")) or ""),
                { tip = "Coin plus vendor value. " .. (s.items or 0) .. " items looted" .. (s.best and (", best drop: " .. s.best.name) or "") .. "." })
        end
    end
end

function render.settings() end     -- a page of controls, handled in renderNow

function render.journal()
    local notes = ns.char.journal
    if #notes == 0 then
        P(L .. "Thoughts go here. Type below, or use |r" .. W .. "/dls note your text|r" .. L .. " while playing. Each note is stamped with your level and zone, and lands in the summary.|r")
        return
    end
    for i = #notes, 1, -1 do
        local n = notes[i]
        KV(L .. "Level " .. tostring(n.level or "?") .. "  ·  " .. (n.zone or "?") .. "|r", L .. ago(n.t) .. "|r",
            { onRight = function() ns.RemoveNote(i) end, tip = "Right-click to delete this note." })
        P(W .. n.text .. "|r", 8)
        GAP(6)
    end
end

function render.summary() end      -- handled by the edit box below

----------------------------------------------------------------------
-- frame construction
----------------------------------------------------------------------
local function hairline(parent, p1, p2, horizontal)
    local t = parent:CreateTexture(nil, "BORDER")
    t:SetColorTexture(1, 1, 1, 0.10)
    t:SetPoint(p1); t:SetPoint(p2)
    if horizontal then t:SetHeight(1) else t:SetWidth(1) end
    return t
end

local function applyScroll()
    local view = scroll:GetHeight() or 0
    local maxOffset = math.max(0, cursor - view)
    state.offset = math.max(0, math.min(state.offset, maxOffset))
    scroll:SetVerticalScroll(state.offset)
    if maxOffset > 0 then
        local track = view
        local size = math.max(24, track * view / cursor)
        panel.thumb:SetHeight(size)
        panel.thumb:ClearAllPoints()
        panel.thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 6, -(track - size) * (state.offset / maxOffset))
        panel.thumb:Show()
    else
        panel.thumb:Hide()
    end
end

local function build()
    panel = CreateFrame("Frame", "DearLordStatsPanel", UIParent)
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetFrameStrata("MEDIUM")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        ns.db.panel = { point = point, x = x, y = y }
    end)
    panel:SetResizable(true)
    if panel.SetResizeBounds then panel:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    elseif panel.SetMinResize then panel:SetMinResize(MIN_W, MIN_H); panel:SetMaxResize(MAX_W, MAX_H) end
    panel:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "DearLordStatsPanel") end      -- Escape closes it

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.04, 0.05, 0.07, (ns.db and ns.db.panelAlpha) or 0.92)
    panel.bgTex = bg
    hairline(panel, "TOPLEFT", "TOPRIGHT", true); hairline(panel, "BOTTOMLEFT", "BOTTOMRIGHT", true)
    hairline(panel, "TOPLEFT", "BOTTOMLEFT", false); hairline(panel, "TOPRIGHT", "BOTTOMRIGHT", false)

    local title = panel:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 13, ""); title:SetPoint("TOPLEFT", PAD, -12)
    title:SetText(W .. "DearLord Stats|r")
    panel.who = panel:CreateFontString(nil, "OVERLAY")
    panel.who:SetFont(FONT, 11, ""); panel.who:SetJustifyH("LEFT"); panel.who:SetWordWrap(false)
    panel.title = title

    local close = textButton(panel, 16)
    close:SetLabel("×"); close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetActive(false); close.line:Hide()
    close:SetScript("OnClick", function() panel:Hide() end)
    panel.close = close

    local x = PAD
    for i, tab in ipairs(TABS) do
        local b = textButton(panel, 12)
        b:SetLabel(tab.text)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -38)
        x = x + b:GetWidth() + 14
        b:SetScript("OnClick", function() ns.OpenPanel(tab.key) end)
        tabButtons[tab.key] = b
    end
    for i = 1, 3 do
        local b = textButton(panel, 11)
        b:SetScript("OnClick", function(self)
            state.scope[state.tab] = self.scopeKey
            state.offset = 0
            renderNow()
        end)
        scopeButtons[i] = b
    end
    local rule = panel:CreateTexture(nil, "BORDER")
    rule:SetColorTexture(1, 1, 1, 0.08); rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", PAD, -62); rule:SetPoint("TOPRIGHT", -PAD, -62)

    scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", PAD, -70)
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 4, 34)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        state.offset = state.offset - delta * 36
        applyScroll()
    end)
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(innerWidth(), 10)
    scroll:SetScrollChild(child)
    panel.thumb = panel:CreateTexture(nil, "ARTWORK")
    panel.thumb:SetColorTexture(1, 1, 1, 0.18); panel.thumb:SetWidth(2)
    panel.thumb:Hide()

    footer = panel:CreateFontString(nil, "OVERLAY")
    footer:SetFont(FONT, 10, ""); footer:SetPoint("BOTTOMLEFT", PAD, 12)
    footer:SetTextColor(0.5, 0.55, 0.6)

    -- journal input
    noteBox = CreateFrame("EditBox", nil, panel)
    noteBox:SetFont(FONT, 12, ""); noteBox:SetAutoFocus(false)
    noteBox:SetPoint("BOTTOMLEFT", PAD + 4, 8); noteBox:SetPoint("BOTTOMRIGHT", -PAD - 4, 8)
    noteBox:SetHeight(20); noteBox:SetMaxLetters(240)
    noteBox.bg = noteBox:CreateTexture(nil, "BACKGROUND")
    noteBox.bg:SetPoint("TOPLEFT", -4, 2); noteBox.bg:SetPoint("BOTTOMRIGHT", 4, -2)
    noteBox.bg:SetColorTexture(1, 1, 1, 0.06)
    noteBox.hint = noteBox:CreateFontString(nil, "OVERLAY")
    noteBox.hint:SetFont(FONT, 12, ""); noteBox.hint:SetPoint("LEFT", 0, 0)
    noteBox.hint:SetTextColor(0.5, 0.55, 0.6); noteBox.hint:SetText("Write a note and press Enter")
    noteBox:SetScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == "") end)
    noteBox:SetScript("OnEnterPressed", function(self)
        if ns.AddNote(self:GetText()) then self:SetText("") end
        state.offset = 0
        renderNow()
    end)
    noteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    noteBox:Hide()

    -- summary text (read-only, selectable)
    summaryBox = CreateFrame("EditBox", nil, child)
    summaryBox:SetMultiLine(true); summaryBox:SetAutoFocus(false)
    summaryBox:SetFont(FONT, 12, "")
    summaryBox:SetPoint("TOPLEFT", 4, -2)
    summaryBox:SetWidth(innerWidth() - 12)
    summaryBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    summaryBox:SetScript("OnTextChanged", function(self, user)
        if user then self:SetText(self.original or ""); self:HighlightText() end       -- read-only
    end)
    summaryBox:Hide()
    selectAll = textButton(panel, 11)
    selectAll:SetLabel("Select all"); selectAll:SetActive(false)
    selectAll:SetPoint("BOTTOMRIGHT", -PAD - 16, 10)
    selectAll:SetScript("OnClick", function() summaryBox:SetFocus(); summaryBox:HighlightText() end)
    selectAll:Hide()

    -- resize handle: drag to resize, double-click to fit the height to the content
    local grip = CreateFrame("Button", nil, panel)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip.marks = {}
    for i = 1, 3 do                                   -- three short diagonal-looking ticks, brighter on hover
        local m = grip:CreateTexture(nil, "OVERLAY")
        m:SetColorTexture(1, 1, 1, 0.28)
        m:SetSize(2 + i * 3, 1)
        m:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -2, 1 + (3 - i) * 3)
        grip.marks[i] = m
    end
    local function shade(a) for _, m in ipairs(grip.marks) do m:SetColorTexture(1, 1, 1, a) end end
    local function saveGeometry()
        local point, _, _, x, y = panel:GetPoint(1)
        ns.db.panel = { point = point, x = x, y = y }
        ns.db.panelSize = { w = math.floor(panel:GetWidth() + 0.5), h = math.floor(panel:GetHeight() + 0.5) }
    end
    grip:SetScript("OnEnter", function(self)
        shade(0.7)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Drag to resize", 1, 1, 1)
        GameTooltip:AddLine("Double-click to fit the height to the content", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() shade(0.28); GameTooltip:Hide() end)
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then panel.sizing = true; panel:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        if not panel.sizing then return end
        panel.sizing = nil
        panel:StopMovingOrSizing()
        saveGeometry()
        renderNow()
    end)
    grip:SetScript("OnDoubleClick", function()
        local chrome = 70 + 34                         -- title, tabs and footer around the scroll area
        local top = panel:GetTop() or 0
        local room = math.max(MIN_H, top - 8)          -- never grow past the bottom of the screen
        local h = math.max(MIN_H, math.min(MAX_H, room, cursor + chrome + 6))
        local left = panel:GetLeft() or 0
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        panel:SetHeight(h)
        state.offset = 0
        saveGeometry()
        renderNow()
    end)
    panel.grip = grip
    local sizeTick = 0
    panel:SetScript("OnSizeChanged", function()
        local now = GetTime()                          -- re-flow the text whenever the size changes, however it changed
        if now - sizeTick > 0.04 then sizeTick = now; renderNow() else state.dirty = true end
    end)
end

local FOOT = {
    combat = "Numbers come from the game's own damage meter, read after each fight.",
    abilities = "Right-click a spell in the lists below the chart to stop being reminded of it.",
    professions = "Open a profession window or talk to a trainer once and the details fill in.",
    journal = "",
    loot = "Hover an item for its tooltip. Only real loot counts; quest rewards, purchases and crafts do not.",
    settings = "Changes apply immediately. Drag a slider or use the mouse wheel on any row.",
    summary = "Select all, then Ctrl+C. Plain text, ready for Discord or beta feedback.",
}

renderNow = function()
    if not panel or not ns.char or not ns.session then return end
    state.dirty = false
    used, cursor = 0, 0
    child:SetWidth(innerWidth())
    summaryBox:SetWidth(innerWidth() - 12)
    for key, b in pairs(tabButtons) do b:SetActive(key == state.tab) end
    local scopes = SCOPES[state.tab]
    for i, b in ipairs(scopeButtons) do
        local sc = scopes and scopes[i]
        b:SetShown(sc ~= nil)
        if sc then
            b.scopeKey = sc.key
            b:SetLabel(sc.text)
            b:SetActive(state.scope[state.tab] == sc.key)
        end
    end
    if scopes then                                             -- laid out right to left on the title row
        local anchor
        for i = #scopes, 1, -1 do
            local b = scopeButtons[i]
            if scopes[i].key == "level" then b:SetLabel("Level " .. viewLevel()) end
            b:ClearAllPoints()
            if anchor then b:SetPoint("RIGHT", anchor, "LEFT", -12, 0)
            else b:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD - 26, -13) end
            anchor = b
        end
    end
    -- the character label takes whatever room is left on the title row and truncates instead of overlapping
    panel.who:ClearAllPoints()
    panel.who:SetPoint("LEFT", panel.title, "RIGHT", 10, 0)
    panel.who:SetPoint("RIGHT", scopes and scopeButtons[1] or panel.close, "LEFT", -14, 0)
    panel.who:SetText(L .. (ns.charKey and ns.charKey:match("^(.-)%-") or "") .. "  ·  level " .. tostring(ns.curLevel or "?") .. "  ·  " .. (ns.char.class or "") .. "|r")

    local isSummary, isJournal, isSettings = state.tab == "summary", state.tab == "journal", state.tab == "settings"
    summaryBox:SetShown(isSummary); selectAll:SetShown(isSummary)
    summaryBox:SetFont(FONT, fsize(), "")
    if isSettings and not settingsPage then
        settingsPage = ns.SettingsPage(child)
        settingsPage:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    end
    if settingsPage then settingsPage:SetShown(isSettings) end
    noteBox:SetShown(isJournal)
    footer:SetText(FOOT[state.tab] or "")
    if isSettings then
        cursor = settingsPage:Layout(innerWidth()) + 8
    elseif isSummary then
        local text = ns.SummaryText(state.scope.summary == "all")
        summaryBox.original = text
        summaryBox:SetText(text)
        cursor = (summaryBox:GetHeight() or 200) + 8
    else
        ns.safe("panel:" .. state.tab, function() render[state.tab](state.scope[state.tab]) end)
    end
    for i = used + 1, #rows do rows[i]:Hide() end
    child:SetHeight(math.max(10, cursor))
    applyScroll()
    panel.renderedWidth = panel:GetWidth()
end

function ns.ApplyPanelStyle()
    if panel and panel.bgTex then panel.bgTex:SetColorTexture(0.04, 0.05, 0.07, ns.db.panelAlpha or 0.92) end
end

function ns.PanelDirty() state.dirty = true end

function ns.OpenPanel(tab)
    if not panel then build() end
    if tab and tab ~= state.tab then state.tab, state.offset = tab, 0 end
    local pos = ns.db.panel or ns.defaults.panel
    local size = ns.db.panelSize
    panel:SetSize(math.max(MIN_W, math.min(MAX_W, size and size.w or WIDTH)), math.max(MIN_H, math.min(MAX_H, size and size.h or HEIGHT)))
    panel:ClearAllPoints()
    panel:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    panel:Show()
    renderNow()
end

function ns.TogglePanel(tab)
    if panel and panel:IsShown() and (not tab or tab == state.tab) then panel:Hide() else ns.OpenPanel(tab) end
end

local sinceRender = 0
ns.Every(0.5, function(dt)
    if not panel or not panel:IsShown() then return end
    sinceRender = sinceRender + dt
    if state.tab == "summary" and summaryBox:HasFocus() then return end       -- do not disturb a selection
    if settingsPage and settingsPage.dragging then return end                  -- nor a slider being dragged
    local stale = panel.renderedWidth and math.abs(panel.renderedWidth - panel:GetWidth()) > 0.5
    if state.dirty or stale or sinceRender >= 2 then sinceRender = 0; renderNow() end
end, "panel:refresh")
