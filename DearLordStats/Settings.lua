-- DearLord Stats : Settings page (lives inside the report as its own tab)
-- Flat, text-first controls in the same style as the rest of the report: a tick box, a thin slider,
-- a "‹ choice ›" picker and plain text buttons. Every change applies immediately.
local ADDON, ns = ...
local FONT = STANDARD_TEXT_FONT
local ROW = 24

local CONTROLS = {
    { header = "HUD text" },
    { type = "choice", key = "font", label = "Font", options = function() return ns.FONTS end },
    { type = "slider", key = "fontSize", label = "Size", min = 9, max = 24, step = 1 },
    { type = "choice", key = "outline", label = "Edge", options = function() return ns.OUTLINES end },
    { type = "slider", key = "alpha", label = "Opacity", min = 0.2, max = 1, step = 0.05, percent = true },
    { type = "slider", key = "scale", label = "Scale", min = 0.5, max = 2.5, step = 0.05, percent = true },
    { type = "check", key = "background", label = "Dark background behind the text" },
    { type = "slider", key = "bgAlpha", label = "Background darkness", min = 0.1, max = 0.9, step = 0.05, percent = true },
    { type = "check", key = "locked", label = "Lock the windows in place" },

    { header = "What is shown" },
    { type = "check", key = "showStats", label = "Latency, lag and FPS line" },
    { type = "check", key = "showXP", label = "XP window" },
    { type = "check", key = "showGold", label = "Gold line in the XP window" },
    { type = "check", key = "showProf", label = "Profession line while gathering or crafting" },

    { header = "Messages under the HUD" },
    { type = "check", key = "showRecap", label = "Fight recap after combat" },
    { type = "slider", key = "recapHold", label = "Recap stays for", min = 3, max = 20, step = 1, suffix = " s" },
    { type = "check", key = "nudges", label = "Gentle reminders" },
    { type = "slider", key = "nudgeHold", label = "Reminders stay for", min = 8, max = 60, step = 1, suffix = " s" },
    { type = "check", key = "lootAnnounce", label = "Announce uncommon or better drops" },

    { header = "Auction house" },
    { type = "check", key = "ahTooltip", label = "Auction price in item tooltips" },
    { type = "check", key = "ahAutoScan", label = "Scan prices when the auction house opens" },

    { header = "This report" },
    { type = "slider", key = "panelAlpha", label = "Background opacity", min = 0.5, max = 1, step = 0.02, percent = true },
    { type = "slider", key = "panelFontSize", label = "Text size", min = 10, max = 16, step = 1 },

    { header = "Reset" },
    { type = "button", label = "Reset window positions and sizes", action = function() ns.ResetLayout() end },
    { type = "button", label = "Reset every setting to its default", action = function() ns.ResetSettings() end },
}

local function applyAll()
    ns.ApplyHudSettings()
    if ns.RefreshXP then ns.RefreshXP() end
    if ns.ApplyPanelStyle then ns.ApplyPanelStyle() end
    if ns.PanelDirty then ns.PanelDirty() end
end

function ns.ResetLayout()
    local db, d = ns.db, ns.defaults
    for _, k in ipairs({ "stats", "xp", "panel" }) do db[k] = { point = d[k].point, x = d[k].x, y = d[k].y } end
    db.panelSize = nil
    applyAll()
    ns.say("window positions and sizes reset")
end
function ns.ResetSettings()
    local db, d = ns.db, ns.defaults
    for k, v in pairs(d) do if type(v) ~= "table" then db[k] = v end end
    applyAll()
    ns.say("settings reset to defaults")
end

local function label(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size or 12, "")
    fs:SetTextColor(r or 0.77, g or 0.77, b or 0.77)
    return fs
end

local function formatValue(c, v)
    if c.percent then return string.format("%d%%", math.floor(v * 100 + 0.5)) end
    return tostring(v) .. (c.suffix or "")
end

local function snap(c, v)
    v = math.max(c.min, math.min(c.max, v))
    v = c.min + math.floor((v - c.min) / c.step + 0.5) * c.step
    return math.floor(v * 1000 + 0.5) / 1000
end

local function buildRow(page, c)
    local row = CreateFrame("Button", nil, page)
    row.control = c
    row:SetHeight(c.header and 22 or ROW)
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints(); row.hl:SetColorTexture(1, 1, 1, 0.05); row.hl:Hide()

    if c.header then
        row.text = label(row, 10, 0.56, 0.64, 0.72)
        row.text:SetPoint("BOTTOMLEFT", 0, 4)
        row.text:SetText(c.header:upper())
        local rule = row:CreateTexture(nil, "BORDER")
        rule:SetColorTexture(1, 1, 1, 0.08); rule:SetHeight(1)
        rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")
        return row
    end

    row.text = label(row, 12)
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetText(c.label)
    row:SetScript("OnEnter", function(self) self.hl:Show() end)
    row:SetScript("OnLeave", function(self) self.hl:Hide() end)

    if c.type == "check" then
        local box = row:CreateTexture(nil, "ARTWORK")
        box:SetSize(12, 12); box:SetPoint("RIGHT", -6, 0); box:SetColorTexture(1, 1, 1, 0.14)
        local fill = row:CreateTexture(nil, "OVERLAY")
        fill:SetSize(8, 8); fill:SetPoint("CENTER", box, "CENTER"); fill:SetColorTexture(0.5, 0.7, 1, 1)
        row.fill = fill
        row:SetScript("OnClick", function() ns.db[c.key] = not ns.db[c.key]; applyAll(); page:Refresh() end)

    elseif c.type == "button" then
        row.text:SetTextColor(0.5, 0.7, 1)
        row:SetScript("OnClick", function() ns.safe("settings:button", c.action); page:Refresh() end)

    elseif c.type == "choice" then
        row.value = label(row, 12, 1, 1, 1)
        row.value:SetPoint("RIGHT", -22, 0)
        local prev, nxt = label(row, 13, 0.6, 0.6, 0.6), label(row, 13, 0.6, 0.6, 0.6)
        nxt:SetPoint("RIGHT", -6, 0); nxt:SetText("›")
        prev:SetPoint("RIGHT", row.value, "LEFT", -8, 0); prev:SetText("‹")
        local function step(delta)
            local options = c.options()
            local idx = 1
            for i, o in ipairs(options) do if o.key == ns.db[c.key] then idx = i end end
            ns.db[c.key] = options[(idx - 1 + delta) % #options + 1].key
            applyAll(); page:Refresh()
        end
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(_, button) step(button == "RightButton" and -1 or 1) end)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta) step(delta > 0 and -1 or 1) end)

    elseif c.type == "slider" then
        local track = CreateFrame("Frame", nil, row)
        track:SetSize(150, 14); track:SetPoint("RIGHT", -6, 0)
        local line = track:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.16); line:SetHeight(2)
        line:SetPoint("LEFT"); line:SetPoint("RIGHT")
        local fill = track:CreateTexture(nil, "ARTWORK")
        fill:SetColorTexture(0.5, 0.7, 1, 0.9); fill:SetHeight(2); fill:SetPoint("LEFT")
        local thumb = track:CreateTexture(nil, "OVERLAY")
        thumb:SetColorTexture(1, 1, 1, 0.95); thumb:SetSize(4, 12)
        row.track, row.fillBar, row.thumb = track, fill, thumb
        row.value = label(row, 12, 1, 1, 1)
        row.value:SetPoint("RIGHT", track, "LEFT", -10, 0)

        local function set(v)
            v = snap(c, v)
            if v ~= ns.db[c.key] then ns.db[c.key] = v; applyAll() end
            page:Refresh()
        end
        local function fromCursor()
            local x = GetCursorPosition()
            local scale = track:GetEffectiveScale() or 1
            local left, width = track:GetLeft() or 0, track:GetWidth() or 150
            set(c.min + (c.max - c.min) * math.max(0, math.min(1, (x / scale - left) / width)))
        end
        track:EnableMouse(true)
        track:SetScript("OnMouseDown", function() page.dragging = row; fromCursor() end)
        track:SetScript("OnMouseUp", function() page.dragging = nil end)
        track:SetScript("OnUpdate", function() if page.dragging == row then fromCursor() end end)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta) set((ns.db[c.key] or c.min) + delta * c.step) end)
        row:SetScript("OnClick", nil)
    end
    return row
end

function ns.SettingsPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page.rows = {}
    for i, c in ipairs(CONTROLS) do page.rows[i] = buildRow(page, c) end

    function page:Refresh()
        local db = ns.db
        for _, row in ipairs(self.rows) do
            local c = row.control
            if c.type == "check" then row.fill:SetShown(db[c.key] and true or false)
            elseif c.type == "choice" then
                local name = "?"
                for _, o in ipairs(c.options()) do if o.key == db[c.key] then name = o.name end end
                row.value:SetText(name)
            elseif c.type == "slider" then
                local v = db[c.key] or c.min
                local frac = math.max(0, math.min(1, (v - c.min) / (c.max - c.min)))
                local width = row.track:GetWidth() or 150
                row.value:SetText(formatValue(c, v))
                row.fillBar:SetWidth(math.max(1, width * frac))
                row.thumb:ClearAllPoints()
                row.thumb:SetPoint("CENTER", row.track, "LEFT", width * frac, 0)
            end
        end
    end

    -- stacks the rows to the given width and returns the total height
    function page:Layout(width)
        local y = 0
        for _, row in ipairs(self.rows) do
            if row.control.header and y > 0 then y = y + 12 end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
            row:SetWidth(width)
            y = y + row:GetHeight() + (row.control.header and 4 or 0)
        end
        self:SetSize(width, y)
        self:Refresh()
        return y
    end
    return page
end
