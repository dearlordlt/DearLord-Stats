-- DearLord Stats : bars
-- What the damage meter and the threat window are drawn with: a window body with hairlines, a list
-- of animated bars, a resize grip, small text buttons, a pop-up menu and a box to copy text from.
-- Numbers this client hides in a fight never pass through Lua arithmetic here: they go straight to
-- the game's own setters (a status bar, a font string), which accept them.
local ADDON, ns = ...
local N, S, B = ns.N, ns.S, ns.B

local WHITE = "Interface\\Buttons\\WHITE8X8"
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local INTERP = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local CLASS_TC = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.5, 0, 0.25 }, ROGUE = { 0.5, 0.75, 0, 0.25 }, DRUID = { 0.75, 1, 0, 0.25 },
    HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.5, 0.25, 0.5 }, PRIEST = { 0.5, 0.75, 0.25, 0.5 }, WARLOCK = { 0.75, 1, 0.25, 0.5 },
    PALADIN = { 0, 0.25, 0.5, 0.75 },
}
ns.BAR_ACCENT = { 0.5, 0.7, 1 }

----------------------------------------------------------------------
-- small helpers
----------------------------------------------------------------------
function ns.BarFont(fs, delta)
    local db = ns.db or {}
    local size, flags = math.max(8, (db.fontSize or 13) + (delta or 0)), db.outline or "OUTLINE"
    if not fs:SetFont(ns.FontPath(), size, flags) then fs:SetFont(STANDARD_TEXT_FONT, size, flags) end
end
local function newText(parent, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH(justify or "LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
end
ns.BarText = newText
-- a text that may be hidden: the font string takes it, Lua never looks at it
-- (a hidden value is never compared or tested for truth, not even against nil: ns.exists asks the game first)
local function setText(fs, v)
    if not ns.exists(v) then fs:SetText(""); return end
    if not pcall(fs.SetText, fs, v) then fs:SetText("") end
end
ns.BarSetText = setText

-- class crest for a player, a question mark otherwise
function ns.ClassIcon(tex, class)
    local t = class and CLASS_TC[class]
    if t then
        tex:SetTexture(CLASS_ICONS); tex:SetTexCoord(t[1] + 0.02, t[2] - 0.02, t[3] + 0.02, t[4] - 0.02)
        return true
    end
    return false
end

----------------------------------------------------------------------
-- window body: dark and translucent, hairline border, a title strip with an accent rule
----------------------------------------------------------------------
function ns.Chrome(f, headHeight)
    local old = f.bg                                         -- the plain HUD backdrop is replaced by the body
    if old then old:Hide(); old:ClearAllPoints() end
    f.bg = f:CreateTexture(nil, "BACKGROUND")                -- never anchored: the shared HUD code may show it, nothing is drawn
    f.bg:Hide()
    f.body = f:CreateTexture(nil, "BACKGROUND")
    f.body:SetAllPoints()
    f.head = f:CreateTexture(nil, "BORDER")
    f.head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); f.head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.rule = f:CreateTexture(nil, "ARTWORK")
    f.rule:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT", 0, 0); f.rule:SetPoint("TOPRIGHT", f.head, "BOTTOMRIGHT", 0, 0)
    f.rule:SetHeight(1)
    f.edges = {}
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", false }, { "BOTTOMLEFT", "BOTTOMRIGHT", false }, { "TOPLEFT", "BOTTOMLEFT", true }, { "TOPRIGHT", "BOTTOMRIGHT", true } }) do
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetPoint(side[1], f, side[1], 0, 0); t:SetPoint(side[2], f, side[2], 0, 0)
        if side[3] then t:SetWidth(1) else t:SetHeight(1) end
        t:SetColorTexture(1, 1, 1, 0.09)
        f.edges[#f.edges + 1] = t
    end
    function f:ApplyChrome(h)
        local a = (ns.db and ns.db.meterAlpha) or 0.8
        self.body:SetColorTexture(0.04, 0.05, 0.07, a)
        self.head:SetColorTexture(1, 1, 1, 0.05)
        self.head:SetHeight(h or headHeight or 20)
        self.rule:SetColorTexture(ns.BAR_ACCENT[1], ns.BAR_ACCENT[2], ns.BAR_ACCENT[3], 0.35)
    end
    f:ApplyChrome(headHeight)
end

----------------------------------------------------------------------
-- a small text button, dim until the pointer is on it
----------------------------------------------------------------------
function ns.TextButton(parent, label, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b.text = newText(b, "CENTER")
    b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.text:SetText(label)
    b.dim, b.lit = { 0.62, 0.66, 0.72 }, { 1, 1, 1 }
    b.text:SetTextColor(b.dim[1], b.dim[2], b.dim[3])
    b.tip = tip
    b:SetScript("OnEnter", function(self)
        self.text:SetTextColor(self.lit[1], self.lit[2], self.lit[3])
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(type(self.tip) == "function" and self.tip() or self.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        local c = self.on and self.lit or self.dim
        self.text:SetTextColor(c[1], c[2], c[3])
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self, button) ns.safe("button", function() onClick(self, button) end) end)
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    function b:SetLabel(text) self.text:SetText(text) end
    function b:SetOn(on)                                     -- an active tab stays lit
        self.on = on and true or false
        local c = self.on and self.lit or self.dim
        self.text:SetTextColor(c[1], c[2], c[3])
    end
    function b:Fit(delta, height)
        ns.BarFont(self.text, delta or -2)
        self:SetSize((N(self.text:GetStringWidth()) or 30) + 8, height or 16)
        return self:GetWidth()
    end
    return b
end

----------------------------------------------------------------------
-- pop-up menu: items are { text, fn }, { text, fn, checked = function }, { title = }, { divider = true }
----------------------------------------------------------------------
local legacyMenu
function ns.PopMenu(owner, title, items)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root)
            if title then root:CreateTitle(title) end
            for _, it in ipairs(items) do
                if it.divider then
                    if root.CreateDivider then root:CreateDivider() end
                elseif it.title then root:CreateTitle(it.title)
                elseif it.checked then root:CreateCheckbox(it.text, it.checked, function() ns.safe("menu", it.fn) end)
                else root:CreateButton(it.text, function() ns.safe("menu", it.fn) end) end
            end
        end)
        return true
    end
    if not (UIDropDownMenu_Initialize and ToggleDropDownMenu and UIDropDownMenu_CreateInfo) then return false end
    legacyMenu = legacyMenu or CreateFrame("Frame", "DearLordStatsPopMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(legacyMenu, function()
        for _, it in ipairs(items) do
            if not it.divider then
                local info = UIDropDownMenu_CreateInfo()
                info.text = it.text or it.title
                if it.title then info.isTitle, info.notCheckable = true, true
                elseif it.checked then info.checked, info.isNotRadio, info.func = it.checked(), true, function() ns.safe("menu", it.fn) end
                else info.notCheckable, info.func = true, function() ns.safe("menu", it.fn) end end
                UIDropDownMenu_AddButton(info)
            end
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, legacyMenu, "cursor", 0, 0)
    return true
end

----------------------------------------------------------------------
-- a box to copy text out of the game: the text is selected, Ctrl+C takes it
----------------------------------------------------------------------
local copyBox
function ns.CopyBox(text, title)
    if not copyBox then
        local f = CreateFrame("Frame", "DearLordStatsCopy", UIParent)
        f:SetSize(460, 220)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        ns.Chrome(f, 22)
        f.body:SetColorTexture(0.04, 0.05, 0.07, 0.96)
        f.title = newText(f)
        f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -5)
        f.hint = newText(f)
        f.hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 6)
        f.hint:SetTextColor(0.62, 0.66, 0.72)
        f.hint:SetText("Ctrl+C copies it. Esc closes.")
        f.close = ns.TextButton(f, "×", function() f:Hide() end)
        f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -3)
        local box = CreateFrame("EditBox", nil, f)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFont(STANDARD_TEXT_FONT, 12, "")
        box:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30)
        box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 24)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        box:SetScript("OnTextChanged", function(self, user)
            if user then self:SetText(self.original or ""); self:HighlightText() end      -- read-only
        end)
        f.box = box
        copyBox = f
    end
    local f = copyBox
    ns.BarFont(f.title, -1); ns.BarFont(f.hint, -2); f.close:Fit(2, 18)
    f.title:SetText(ns.WHITE .. (title or "Copy") .. "|r")
    local lines = select(2, text:gsub("\n", "\n")) + 1
    f:SetHeight(math.min(520, math.max(120, 60 + lines * 14)))
    f.box.original = text
    f.box:SetText(text)
    f:Show()
    f.box:SetFocus()
    f.box:HighlightText()
    ns.copyBox = f
    return f
end

----------------------------------------------------------------------
-- resize: a grip in the bottom right corner; the size is kept as two plain numbers
----------------------------------------------------------------------
function ns.MakeResizable(f, wKey, hKey, minW, minH, onSize)
    if f.SetResizable then f:SetResizable(true) end
    local function bounds()
        local maxW, maxH = 1400, 1000
        if f.SetResizeBounds then f:SetResizeBounds(minW, minH, maxW, maxH)
        elseif f.SetMinResize then f:SetMinResize(minW, minH); if f.SetMaxResize then f:SetMaxResize(maxW, maxH) end end
    end
    pcall(bounds)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
    grip.marks = {}
    for i = 1, 3 do
        local m = grip:CreateTexture(nil, "OVERLAY")
        m:SetSize(i * 3 + 1, 1)
        m:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -2, 1 + (3 - i) * 3)
        grip.marks[i] = m
    end
    local function shade(a) for _, m in ipairs(grip.marks) do m:SetColorTexture(1, 1, 1, a) end end
    shade(0.25)
    local function save()
        local db = ns.db
        local w, h = N(f:GetWidth()), N(f:GetHeight())
        if w and h then db[wKey], db[hKey] = math.floor(math.max(minW, w) + 0.5), math.floor(math.max(minH, h) + 0.5) end
        local point, _, _, x, y = f:GetPoint(1)                -- sizing re-anchors the window: keep where it ended up
        local pos = f.key and db[f.key]
        if pos and point then pos.point, pos.x, pos.y = point, x, y end
    end
    grip:SetScript("OnEnter", function(self)
        shade(0.7)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.db.locked and "Windows are locked (right-click: Lock windows)." or "Drag to resize.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() shade(0.25); GameTooltip:Hide() end)
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and not ns.db.locked then f.sizing = true; f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        if not f.sizing then return end
        f.sizing = nil
        f:StopMovingOrSizing()
        save()
        if onSize then ns.safe("resize", onSize) end
    end)
    f:SetScript("OnSizeChanged", function() if f.sizing and onSize then ns.safe("resize", onSize) end end)
    f.grip = grip
    function f:ApplySize(defW, defH)
        local db = ns.db
        self:SetSize(math.max(minW, N(db[wKey]) or defW), math.max(minH, N(db[hKey]) or defH))
    end
    return grip
end

----------------------------------------------------------------------
-- the bar list
-- item: { key, rank, name | nameFmt + nameArgs, class, icon, r, g, b, value, max, cells = { {text=} | {fmt=, arg=} },
--         own, edge = {r,g,b}, dim }      value, max and the texts may be hidden values
----------------------------------------------------------------------
local function setValue(sb, v, max, instant)
    if not ns.exists(v) then v = 0 end
    if not ns.exists(max) then max = 1 end
    local plain = N(max)
    if plain and plain <= 0 then max = 1 end
    if INTERP and not instant then
        if pcall(sb.SetMinMaxValues, sb, 0, max, INTERP) and pcall(sb.SetValue, sb, v, INTERP) then return true end
    end
    return pcall(sb.SetMinMaxValues, sb, 0, max) and pcall(sb.SetValue, sb, v)
end

function ns.BarList(parent, hud)
    local L = { rows = {}, free = {}, byKey = {}, order = {}, barH = 18, gap = 2, width = 120, cellW = {}, rankW = 0,
        showIcon = true, live = false, count = 0 }
    local frame = CreateFrame("Frame", nil, parent)
    if frame.SetClipsChildren then frame:SetClipsChildren(true) end
    L.frame = frame

    local function place(r)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -r.y)
    end

    local function geometry(r)
        local h, w = L.barH, L.width
        local iconW = L.showIcon and (h + 2) or 0
        r:SetSize(w, h)
        r.icon:ClearAllPoints(); r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0); r.icon:SetSize(h, h)
        r.icon:SetShown(L.showIcon)
        r.bar:ClearAllPoints(); r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", iconW, 0); r.bar:SetSize(math.max(10, w - iconW), h)
        r.edge:ClearAllPoints(); r.edge:SetPoint("TOPLEFT", r.bar, "TOPLEFT", 0, 0); r.edge:SetSize(3, h)
        r.spark:SetSize(h * 0.9, h * 2.1)
        local x = 6
        r.rank:ClearAllPoints(); r.rank:SetPoint("LEFT", r.bar, "LEFT", x, 0)
        r.rank:SetWidth(math.max(1, L.rankW)); r.rank:SetShown(L.rankW > 0)
        if L.rankW > 0 then x = x + L.rankW + 2 end
        local right = 5
        for c = #r.cells, 1, -1 do
            local cw = L.cellW[c]
            local fs = r.cells[c]
            fs:ClearAllPoints()
            if cw then
                fs:SetPoint("RIGHT", r.bar, "RIGHT", -right, 0)
                fs:SetWidth(cw)
                right = right + cw + 4
            end
            fs.used = cw ~= nil
        end
        r.name:ClearAllPoints(); r.name:SetPoint("LEFT", r.bar, "LEFT", x, 0)
        r.name:SetWidth(math.max(20, w - iconW - x - right - 2))
        for _, fs in ipairs({ r.rank, r.name, r.cells[1], r.cells[2], r.cells[3] }) do ns.BarFont(fs, L.fontDelta or -1) end
    end

    local function newRow()
        local r = CreateFrame("Button", nil, frame)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        local sb = CreateFrame("StatusBar", nil, r)
        sb:SetStatusBarTexture(WHITE)
        sb:SetMinMaxValues(0, 1)
        sb:SetValue(0)
        r.back = sb:CreateTexture(nil, "BACKGROUND")
        r.back:SetAllPoints()
        r.back:SetColorTexture(1, 1, 1, 0.055)
        local fill = sb:GetStatusBarTexture()
        r.gloss = sb:CreateTexture(nil, "ARTWORK")            -- lighter above, darker below: the bar reads as a surface
        r.gloss:SetTexture(WHITE)
        if fill then r.gloss:SetAllPoints(fill) else r.gloss:SetAllPoints() end
        local shaded = CreateColor and r.gloss.SetGradient and pcall(r.gloss.SetGradient, r.gloss, "VERTICAL", CreateColor(0, 0, 0, 0.30), CreateColor(1, 1, 1, 0.10))
        if not shaded then r.gloss:SetVertexColor(0, 0, 0, 0.12) end
        r.spark = sb:CreateTexture(nil, "OVERLAY")
        r.spark:SetTexture(SPARK)
        if r.spark.SetBlendMode then r.spark:SetBlendMode("ADD") end
        if fill then r.spark:SetPoint("CENTER", fill, "RIGHT", 0, 0) else r.spark:SetPoint("CENTER", sb, "LEFT", 0, 0) end
        r.spark:Hide()
        r.edge = sb:CreateTexture(nil, "OVERLAY")
        r.edge:SetTexture(WHITE)
        r.edge:Hide()
        r.mark = sb:CreateTexture(nil, "OVERLAY")              -- your own row
        r.mark:SetTexture(WHITE)
        r.mark:SetAllPoints()
        r.mark:SetVertexColor(1, 1, 1, 0.09)
        r.mark:Hide()
        r.hover = sb:CreateTexture(nil, "OVERLAY")
        r.hover:SetTexture(WHITE)
        r.hover:SetAllPoints()
        r.hover:SetVertexColor(1, 1, 1, 0.10)
        r.hover:Hide()
        r.rank = newText(sb, "RIGHT")
        r.rank:SetTextColor(0.78, 0.8, 0.84)
        r.name = newText(sb)
        r.cells = { newText(sb, "RIGHT"), newText(sb, "RIGHT"), newText(sb, "RIGHT") }
        r.cells[2]:SetTextColor(0.86, 0.88, 0.92); r.cells[3]:SetTextColor(0.72, 0.76, 0.82)
        r.bar = sb
        r.y, r.ty, r.a, r.ta = 0, 0, 0, 1
        r:SetScript("OnEnter", function(self)
            self.hover:Show()
            if L.onEnter and self.item then ns.safe("bar:enter", function() L.onEnter(self.item, self) end) end
        end)
        r:SetScript("OnLeave", function(self)
            self.hover:Hide()
            if L.onLeave then ns.safe("bar:leave", function() L.onLeave(self.item, self) end) end
        end)
        if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
        r:SetScript("OnClick", function(self, button)
            if L.onClick and self.item then ns.safe("bar:click", function() L.onClick(self.item, button, self) end) end
        end)
        if hud then                                           -- the window still moves when grabbed by a bar
            r:RegisterForDrag("LeftButton")
            r:SetScript("OnDragStart", function() local fn = hud:GetScript("OnDragStart"); if fn then fn(hud) end end)
            r:SetScript("OnDragStop", function() local fn = hud:GetScript("OnDragStop"); if fn then fn(hud) end end)
        end
        L.rows[#L.rows + 1] = r
        geometry(r)
        return r
    end

    local function fill(r, it, fresh)
        r.item = it
        -- the icon is only touched when it changes (a hidden one cannot be compared, so it is always set)
        local hasIcon = ns.exists(it.icon)
        local ik
        if hasIcon then ik = S(it.icon) or N(it.icon) else ik = it.portraitKey or it.portrait or it.class or it.fallbackIcon or "?" end
        if L.showIcon and (ik == nil or r.iconKey ~= ik) then
            r.iconKey = ik
            if hasIcon then
                r.portraitOf = nil
                if not pcall(r.icon.SetTexture, r.icon, it.icon) then r.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
                r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            elseif it.portrait and SetPortraitTexture then
                if r.portraitOf ~= (it.portraitKey or it.portrait) then SetPortraitTexture(r.icon, it.portrait); r.portraitOf = it.portraitKey or it.portrait end
                r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            elseif not ns.ClassIcon(r.icon, it.class) then
                r.portraitOf = nil
                r.icon:SetTexture(it.fallbackIcon or "Interface\\Icons\\INV_Misc_QuestionMark"); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else r.portraitOf = nil end
        end
        local cr, cg, cb = it.r, it.g, it.b                       -- may be hidden numbers, straight from the game's class colour
        if not (ns.exists(cr) and ns.exists(cg) and ns.exists(cb)) then cr, cg, cb = 0.45, 0.6, 0.85 end
        if not pcall(r.bar.SetStatusBarColor, r.bar, cr, cg, cb) then r.bar:SetStatusBarColor(0.45, 0.6, 0.85) end
        if fresh then setValue(r.bar, 0, 1, true) end           -- a new bar grows from nothing
        setValue(r.bar, it.value, it.max)
        r.rank:SetText(it.rank and (it.rank .. ".") or "")
        if it.nameFmt and it.nameArgs then
            if not pcall(r.name.SetFormattedText, r.name, it.nameFmt, unpack(it.nameArgs)) then setText(r.name, it.name) end
        else setText(r.name, it.name) end
        for c = 1, #r.cells do
            local fs, cell = r.cells[c], it.cells and it.cells[c]
            if cell and fs.used then
                if cell.fmt then
                    if not pcall(fs.SetFormattedText, fs, cell.fmt, cell.arg) then fs:SetText("") end
                else setText(fs, cell.text) end
                fs:Show()
            else fs:SetText(""); fs:Hide() end
        end
        if it.edge then r.edge:SetVertexColor(it.edge[1], it.edge[2], it.edge[3], 1); r.edge:Show() else r.edge:Hide() end
        r.mark:SetShown(it.own and true or false)
        r.dim = it.dim and 0.5 or 1
    end

    local function animate(_, elapsed)
        local busy = false
        local dt = math.min(0.1, elapsed or 0.016)
        for _, r in ipairs(L.rows) do
            if r.active then
                if r.y ~= r.ty then
                    local step = (r.ty - r.y) * math.min(1, dt * 14)
                    if math.abs(r.ty - r.y) < 0.4 then r.y = r.ty else r.y = r.y + step; busy = true end
                    place(r)
                end
                local ta = r.ta * (r.dim or 1)
                if r.a ~= ta then
                    if math.abs(ta - r.a) < 0.03 then r.a = ta else r.a = r.a + (ta - r.a) * math.min(1, dt * 10); busy = true end
                    r:SetAlpha(r.a)
                end
                if r.leaving and r.a <= 0.03 then
                    r.active, r.leaving, r.item = false, nil, nil
                    r:Hide()
                    L.free[#L.free + 1] = r
                end
                if L.live and not r.leaving then
                    r.spark:SetAlpha(0.45 + 0.3 * math.abs(math.sin((GetTime() or 0) * 4 + r.ty * 0.05)))
                end
            end
        end
        if not busy and not L.live then frame:SetScript("OnUpdate", nil); L.animating = false end
    end
    local function wake()
        if not L.animating then L.animating = true; frame:SetScript("OnUpdate", animate) end
    end

    -- live: a fight is running. The leading edge of every bar glows.
    function L:SetLive(on)
        on = on and true or false
        if self.live == on then return end
        self.live = on
        for _, r in ipairs(self.rows) do r.spark:SetShown(on and r.active and not r.leaving) end
        wake()
    end

    -- the last fight's bars, kept but faded
    function L:SetDim(on)
        for _, r in ipairs(self.rows) do if r.active then r.dim = on and 0.5 or 1 end end
        wake()
    end

    function L:SetData(items)
        local want = {}
        for i, it in ipairs(items) do it.key = it.key or ("#" .. i); want[it.key] = true end
        local step = self.barH + self.gap
        local order = {}
        for i, it in ipairs(items) do
            local r = self.byKey[it.key]
            local fresh = false
            if not r then
                -- names just became readable (or hidden): the bar in this place carries on under its new key
                local prev = self.order[i]
                if prev and prev.active and not prev.leaving and not want[prev.key] and not prev.taken then
                    r = prev
                    self.byKey[prev.key] = nil
                else
                    r = table.remove(self.free) or newRow()
                    fresh = true
                    r.y, r.a = (i - 1) * step, 0
                    place(r)
                    r:SetAlpha(0)
                    r:Show()
                end
                r.key = it.key
                self.byKey[it.key] = r
            end
            r.taken = true
            r.active, r.leaving, r.ta = true, nil, 1
            r.ty = (i - 1) * step
            if self.instant then r.y, r.a = r.ty, (it.dim and 0.5 or 1); place(r); r:SetAlpha(r.a) end
            r:SetFrameLevel((frame:GetFrameLevel() or 1) + 2 + (#items - i))   -- a bar moving up slides over the ones below
            fill(r, it, fresh)
            r.spark:SetShown(self.live)
            order[i] = r
        end
        for _, r in ipairs(self.rows) do
            if r.active and not r.taken and not r.leaving then
                r.leaving, r.ta = true, 0
                if self.byKey[r.key] == r then self.byKey[r.key] = nil end
                r.spark:Hide()
                if self.instant then r.a = 0 end
            end
            r.taken = nil
        end
        self.order, self.count = order, #items
        wake()
    end

    function L:Layout(width, barH, gap, cellW, rankW)
        self.width, self.barH, self.gap = width, barH, gap or self.gap
        self.cellW, self.rankW = cellW or {}, rankW or 0
        local step = self.barH + self.gap
        for _, r in ipairs(self.rows) do geometry(r) end
        for i, r in ipairs(self.order) do
            r.ty = (i - 1) * step
            r.y = r.ty
            place(r)
        end
    end
    function L:Height(n)
        n = n or self.count
        if n <= 0 then return 1 end
        return n * (self.barH + self.gap) - self.gap
    end
    function L:Row(i) return self.order[i] end
    function L:Clear() self:SetData({}) end
    return L
end
ns.BarSetValue = setValue
