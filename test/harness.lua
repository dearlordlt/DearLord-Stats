-- Simulated WoW "Forever" client for DearLord Stats. Run with lua5.1 (the game's Lua version):
--   lua5.1 test/harness.lua DearLordStats
-- Models what the API probe found on the real client: the combat log is forbidden, the
-- built-in damage meter is readable only out of combat, and health/power/cooldowns are
-- "secret" values in combat that raise an error when touched.
local addonDir = arg[1] or "addon"
local now, wall = 1000, 1700000000
local world = { combat = false, hp = 175, hpMax = 175, mana = 120, manaMax = 120, level = 7, xp = 300, xpMax = 1000,
    money = 5000, pet = nil, target = nil, zone = "Durotar", afk = false, casting = false, rested = 0,
    bags = { [2589] = 24, [2835] = 14, [2840] = 3 }, threat = {}, tooltip = nil, tradeskillOpen = nil }

-- secret values ---------------------------------------------------------------
local SECRET_MT = {}
local function boom() error("attempt to perform arithmetic/compare on a secret value (tainted)", 2) end
for _, m in ipairs({ "__add", "__sub", "__mul", "__div", "__lt", "__le", "__concat", "__unm", "__mod" }) do SECRET_MT[m] = boom end
SECRET_MT.__eq = boom
SECRET_MT.__tostring = function() return "<secret>" end
-- a hidden value may carry what it stands for: only the game's own text formatting can get at it
local SECRET_OF = setmetatable({}, { __mode = "k" })
local function secret(v) local s = setmetatable({}, SECRET_MT); SECRET_OF[s] = v; return s end
function issecretvalue(v) return type(v) == "table" and getmetatable(v) == SECRET_MT end
local function hide(v) if world.combat then return secret() end return v end

-- widgets -----------------------------------------------------------------------
local frames, timers, printed = {}, {}, {}
local function widget(kind, name)
    local w = { kind = kind, name = name, shown = true, scripts = {}, text = "", w = 100, h = 16, alpha = 1, children = {} }
    local M = {}
    function M:SetScript(n, fn) self.scripts[n] = fn end
    function M:GetScript(n) return self.scripts[n] end
    function M:RegisterEvent(e)
        if e == "COMBAT_LOG_EVENT_UNFILTERED" then error("forbidden") end
        self.events = self.events or {}; self.events[e] = true
    end
    local function needFont(self) if self.kind == "FontString" and not self.fontSet then error("FontString:SetText(): Font not set", 3) end end
    function M:SetFont() self.fontSet = true end
    function M:SetFontObject() self.fontSet = true end
    function M:SetText(t)
        needFont(self)
        if issecretvalue(t) then self.text, self.secretText = tostring(SECRET_OF[t] or ""), true; return end   -- a hidden text: drawn, never readable
        self.text = tostring(t or ""); self.secretText = nil
    end
    function M:GetText() return self.text end
    function M:SetFormattedText(fmt, ...)                       -- the game fills hidden numbers in itself; the text is then hidden too
        needFont(self)
        local args, hidden = { ... }, nil
        for i = 1, select("#", ...) do
            if issecretvalue(args[i]) then hidden = true; args[i] = SECRET_OF[args[i]] or 0 end
        end
        self.text = string.format(fmt, unpack(args, 1, select("#", ...)))
        self.secretText = hidden
    end
    function M:GetStringWidth()
        if self.secretText then return secret() end              -- a width that would give the hidden number away
        return #((self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * 6
    end
    function M:GetStringHeight() return 14 * (1 + math.floor(self:GetStringWidth() / 420)) end
    function M:Show()
        local was = self.shown
        self.shown = true
        if self.kind == "EditBox" and not was and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end   -- as the client does
    end
    function M:Hide() self.shown = false end
    function M:SetShown(v) if v then self:Show() else self.shown = false end end
    function M:IsShown() return self.shown end
    function M:IsMouseOver() return false end
    function M:SetSize(w, h) self.w, self.h = w, h end
    function M:SetWidth(w) self.w = w end
    function M:SetHeight(h) self.h = h end
    function M:GetWidth() return self.w end
    function M:GetHeight() return self.h end
    function M:SetAlpha(a) self.alpha = a end
    function M:SetStatusBarColor(r, g, b) self.color = { r, g, b } end
    function M:GetStatusBarTexture() if self.kind ~= "StatusBar" then return nil end; self.fill = self.fill or widget("Texture"); return self.fill end
    function M:SetValue(v, how) self.value = v; self.eased = how ~= nil end
    function M:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
    function M:GetCenter() return (self.cx or 400), 300 end
    function M:SetFrameLevel(l) self.level = l end
    function M:GetFrameLevel() return self.level or 1 end
    function M:GetTop() return 900 end
    function M:GetLeft() return 300 end
    function M:GetPoint() return "TOP", nil, "TOP", 0, -12 end
    function M:HasFocus() return false end
    function M:CreateTexture() return widget("Texture") end
    function M:CreateLine() return widget("Line") end
    function M:CreateFontString() local s = widget("FontString"); self.strings = self.strings or {}; self.strings[#self.strings + 1] = s; return s end
    function M:SetPoint(...) self.point = { ... } end
    function M:GetName() return self.name end
    -- unknown METHODS (capitalised) are harmless no-ops; unknown fields are nil, as on real frames
    return setmetatable(w, { __index = function(t, k) return M[k] or (type(k) == "string" and k:match("^%u") and function() end) or nil end })
end
function CreateFrame(kind, name, parent)
    local f = widget(kind, name); frames[#frames + 1] = f; f.parent = parent
    if name then _G[name] = f end
    return f
end
UIParent = widget("Frame", "UIParent"); UISpecialFrames = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
GameTooltip = widget("GameTooltip", "GameTooltip"); GameTooltip.shown = false
GameTooltipTextLeft1 = widget("FontString"); GameTooltipTextLeft1.fontSet = true
LowHealthFrame = widget("Frame", "LowHealthFrame"); LowHealthFrame.shown = false
function GameTooltip:IsShown() return world.tooltip ~= nil end
GameTooltipTextLeft1.GetText = function() return world.tooltip end
GameTooltip.lines = {}; GameTooltip.forbidden = false
local function plain(t) return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- the tooltip's own lines: line 1 is the item's name (not kept in .lines), so .lines[i] is GameTooltipTextLeft(i+1)
local function tipLine(self, text)
    self.lines[#self.lines + 1] = plain(text)
    self.raw = self.raw or {}; self.raw[#self.lines] = text       -- with its colour codes, for checks on which row is green
    local key = "GameTooltipTextLeft" .. (#self.lines + 1)
    if not _G[key] then _G[key] = widget("FontString"); _G[key].fontSet = true end
    _G[key].text = text
end
function GameTooltip:AddDoubleLine(l, r) tipLine(self, l .. " | " .. r); self.raw[#self.lines] = l end
function GameTooltip:AddLine(l) tipLine(self, l) end
function GameTooltip:NumLines() return #self.lines + 1 end
function GameTooltip:GetMinimumWidth() return self.minW or 0 end
function GameTooltip:SetMinimumWidth(v) self.minW = v; self.minSets = (self.minSets or 0) + 1; self.w = world.tipNarrow and 100 or math.max(100, v) end
-- rows drawn as pinned font strings over blank lines: put each text at its place (6 wide a byte) so a check reads the row
local function composeTip(tt)
    for i, line in ipairs(tt.lines) do
        local anchor = _G["GameTooltipTextLeft" .. (i + 1)]
        local cells = {}
        if line == " " then
            for _, f in ipairs(frames) do
                if f.parent == tt and f.shown then
                    for _, s in ipairs(f.strings or {}) do
                        if s.shown and s.point and s.point[2] == anchor then cells[#cells + 1] = s end
                    end
                end
            end
        end
        if #cells > 0 then
            local buf, raw = "", ""
            table.sort(cells, function(a, b) return a.point[4] < b.point[4] end)
            for _, s in ipairs(cells) do
                local text = plain(s.text)
                local at = s.point[4] / 6 - (s.point[1] == "RIGHT" and #text or 0)
                assert(at == math.floor(at) and at >= #buf, "tooltip cell overlaps or sits off the grid: " .. text)
                buf = buf .. string.rep(" ", at - #buf) .. text
                raw = raw .. s.text
            end
            tt.lines[i], tt.raw[i] = buf, raw
        end
    end
end
function GameTooltip:IsForbidden() return self.forbidden end
function GameTooltip:SetBagItem(bag, slot) self.lines = {} end
ItemRefTooltip = widget("GameTooltip", "ItemRefTooltip")
SlashCmdList = {}
function print(...) local t = {}; for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end; printed[#printed + 1] = table.concat(t, " ") end
debugstack = function() return "" end

-- plain API ---------------------------------------------------------------------
function GetTime() return now end
function time() return wall end
date = os.date
C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = now + d, fn = fn } end }
function GetNetStats() return 0, 0, 127, 128 end
function GetFramerate() return 99.6 end
function GetBuildInfo() return "1.60.1", "69913", "Sep 17 2026", 16001 end
function UnitName(u) if u == "mouseover" and world.mo then return world.mo.name end if u == "player" then return "Tess Ter" elseif u == "pet" then return world.pet elseif u == "target" then return world.targetName elseif world.party and world.party[u] then return world.party[u].name end end
function UnitIsPlayer(u) return u == "mouseover" and world.mo ~= nil end
function GetGuildInfo(u) if u == "mouseover" and world.mo then return world.mo.guild end end
function GetRealmName() return "Classic Beta PvE 2" end
function UnitClass(u) if u == "mouseover" and world.mo then return world.mo.className, world.mo.class end
    if world.party and world.party[u] then return world.party[u].class, world.party[u].class:upper(), 1 end
    if u == "player" and world.class then return world.class, world.class:upper(), 1 end return "Hunter", "HUNTER", 3 end
function GetShapeshiftForm() return world.stance or 0 end
function UnitGroupRolesAssigned() return world.role or "NONE" end
function UnitRace(u) if u == "mouseover" and world.mo then return world.mo.race, world.mo.race end return "Troll", "Troll", 8 end
function UnitLevel(u) if u == "mouseover" and world.mo then return world.mo.level end if u == "target" then return world.targetLevel end if u == "pet" then return world.pet and world.petLevel end return world.level end
function HasPetUI() if world.pet then return true, true end return false, false end
function GetPetExperience() if not world.pet then return 0, 0 end return hide(world.petXP or 0), world.petXPMax or 900 end
function GetPetHappiness() if world.pet then return world.petHappy or 3, ({ 75, 100, 125 })[world.petHappy or 3], (world.petHappy or 3) == 1 and -10 or 20 end end
function GetPetLoyalty() if world.pet then return "Loyalty Level 1 (Rebellious)" end end
-- Forever: the pet calls live in C_PetInfo (this one answers with a table, the way some new calls do)
C_PetInfo = { GetPetTrainingPoints = function() if world.pet then return { totalPoints = 120, spent = 95 } end end,
    GetPetLoyalty = function() if world.pet then return 1 end end }
function GetPetTrainingPoints() if world.pet then return 120, 95 end return 0, 0 end
function GetPetFoodTypes() if world.pet then return "Meat", "Fish" end end
function GetMaxPlayerLevel() return 60 end
function UnitXP() return world.xp end
function UnitXPMax() return world.xpMax end
function GetXPExhaustion() return world.rested > 0 and world.rested or nil end
function GetMoney() return world.money end
function UnitIsAFK() return world.afk end
function UnitAffectingCombat() return world.combat end
function InCombatLockdown() return world.combat end
function UnitExists(u) return u == "player" or (u == "pet" and world.pet ~= nil) or (u == "npc" and world.npc == true) or (u == "target" and world.threat.target ~= nil)
    or (world.party ~= nil and world.party[u] ~= nil) end
function UnitHealth(u) if u == "player" then return hide(world.hp) end return secret() end
function UnitHealthMax() return world.hpMax end
function UnitPower() return hide(world.mana) end
function UnitPowerMax() return world.manaMax end
function UnitPowerType() return 0, "MANA" end
function UnitGUID(u) if u == "player" then return "Player-1-0000ABCD" elseif u == "pet" then return world.pet and "Pet-0-1" elseif world.threat[u] then return world.threat[u] end end
function UnitThreatSituation(who, unit) if world.threat[unit] and who == "player" then return 3 end end
-- world.tlist[unit] = { tanking, status, scaled, raw, value } on the current target; world.threatSecret hides the numbers
function UnitDetailedThreatSituation(unit, mob)
    if not world.threat[mob] or not world.tlist then return nil end
    local t = world.tlist[unit]
    if not t then return nil end
    if world.threatSecret then return secret(), secret(), secret(), secret(), secret() end
    return t[1], t[2], t[3], t[4], t[5]
end
function UnitCanAttack(_, u) return world.threat[u] ~= nil end
function UnitIsUnit(a, b) return a == b end
function IsInGroup() return world.party ~= nil end
function IsInInstance() if world.instance then return true, world.instance end return false, "none" end
-- the pet bar: Growl sits in slot 4, on autocast unless world.growl is false
function GetPetActionInfo(i) if i == 4 and world.pet then return "Growl", "tex", false, false, true, world.growl ~= false, 2649 end end
function IsInRaid() return false end
function GetNumGroupMembers() local n = 0; for _ in pairs(world.party or {}) do n = n + 1 end; return n > 0 and n + 1 or 0 end
function UnitCastingInfo() if world.casting then return hide("Aimed Shot") end end
function UnitChannelInfo() return nil end
function GetZoneText() return world.zone end
function GetSubZoneText() return "Razor Hill" end
COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = "You gain %d experience."
ERR_OUT_OF_MANA = "Not enough mana"; ERR_OUT_OF_RAGE = "Not enough rage"; ERR_OUT_OF_ENERGY = "Not enough energy"
ERR_USE_LOCKED_WITH_SPELL_KNOWN_SI = "Requires %s %d"
LOOT_ITEM_SELF = "You receive loot: %s"

local SPELLS = { [6603] = "Attack", [75] = "Auto Shot", [3044] = "Arcane Shot", [1978] = "Serpent Sting", [2973] = "Raptor Strike",
    [13163] = "Aspect of the Monkey", [1494] = "Track Beasts", [5116] = "Concussive Shot", [2575] = "Mining", [17253] = "Bite", [16827] = "Claw" }
local CAST_TIME = { [19434] = 3000 }        -- Aimed Shot: a real cast; everything else is instant
SPELLS[19434] = "Aimed Shot"
C_Spell = {
    GetSpellName = function(id) if issecretvalue(id) then return secret(SPELLS[SECRET_OF[id]]) end return SPELLS[id] end,   -- a hidden id gives a hidden name
    GetSpellTexture = function(id) if issecretvalue(id) then return secret("icon") end return "icon" .. tostring(id) end,
    GetSpellInfo = function(id) return SPELLS[id] and { name = SPELLS[id], castTime = CAST_TIME[id] or 0 } or nil end,
    GetSpellCooldown = function(id)
        if id ~= 29515 then return nil end
        return { startTime = hide(0), duration = hide(0), isEnabled = true, modRate = 1 }
    end,
}
local ITEMS = { [4867] = { "Broken Scorpid Leg", 0, 12 }, [2140] = { "Carving Knife", 2, 350 }, [783] = { "Light Hide", 1, 50 },
    [2770] = { "Copper Ore", 1, 5 }, [2835] = { "Rough Stone", 1, 2 }, [9999] = { "Blade of the Test", 3, 4200 },
    [4357] = { "Rough Blasting Powder", 1, 4 }, [4359] = { "Handful of Copper Bolts", 1, 300 }, [2840] = { "Copper Bar", 1, 10 },
    [2506] = { "Hornwood Recurve Bow", 1, 400 }, [2589] = { "Linen Cloth", 1, 13 }, [5000] = { "Test Pearl", 1, 77 }, [5001] = { "Patched Wand", 2, 1 }, [5002] = { "Test Gem", 1, 5 } }
GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT = "%d Gold", "%d Silver", "%d Copper"
-- the addon's own auction price database, as the Keeper hands it back: a scan from two days ago
local AH_DAY = math.floor((wall - 1577836800) / 86400)
DearLordAuctionDB = { version = 1, realms = { ["ClassicBetaPvE2-Horde"] = { scanned = wall - 2 * 86400, day = AH_DAY - 2, count = 3, auctions = 9,
    items = { [783] = { p = 250, n = 19, d = AH_DAY - 2, h = (AH_DAY - 2) .. ":250" }, [2140] = { p = 200, n = 1, d = AH_DAY - 2 }, [2770] = { p = 30, n = 40, d = AH_DAY - 2 } } },
    ["ClassicBetaPvE2-Alliance"] = { scanned = wall - 86400, day = AH_DAY - 1, count = 1, items = { [783] = { p = 300, n = 7, d = AH_DAY - 1 } } } } }
function GetNormalizedRealmName() return "ClassicBetaPvE2" end
function GetRealmName() return "Classic Beta PvE 2" end
function UnitFactionGroup(u) if u == "npc" then return world.npcFaction end if u == "mouseover" and world.mo then return world.mo.faction end return "Horde", "Horde" end
function IsAltKeyDown() return world.alt end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
soundsPlayed = {}
function PlaySound(id) soundsPlayed[#soundsPlayed + 1] = id end
function hooksecurefunc(obj, name, fn) local orig = obj[name]; obj[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end end
-- the modern auction house: a replicated list of every auction (itemID, count, buyout), 0-based
local REPLICATE = { { 783, 2, 500 }, { 783, 1, 400 }, { 2140, 1, 150 }, { 2770, 20, 600 }, { 2770, 5, 0 }, { 2835, 10, 30 } }
C_AuctionHouse = { requests = 0,
    ReplicateItems = function() C_AuctionHouse.requests = C_AuctionHouse.requests + 1; world.replicated = true end,
    GetNumReplicateItems = function() return world.replicated and #REPLICATE or 0 end,
    GetReplicateItemInfo = function(i) local r = REPLICATE[i + 1]; if not r then return nil end
        return ITEMS[r[1]] and ITEMS[r[1]][1] or nil, 1, r[2], 1, true, 1, "", r[3], 1, r[3], 0, nil, nil, "Someone", nil, 0, r[1], true end,
    GetReplicateItemLink = function(i) return REPLICATE[i + 1] and ("|Hitem:" .. REPLICATE[i + 1][1] .. "::|h[Thing]|h") end,
    IsThrottledMessageSystemReady = function() return world.ahBusy ~= true end,
    -- searches: the listings of one item, of one stackable item, and the search list itself
    GetNumItemSearchResults = function() return #(world.itemRows or {}) end,
    GetItemSearchResultInfo = function(_, i) return (world.itemRows or {})[i] end,
    HasFullItemSearchResults = function() return world.full ~= false end,
    GetNumCommoditySearchResults = function() return #(world.commodityRows or {}) end,
    GetCommoditySearchResultInfo = function(_, i) return (world.commodityRows or {})[i] end,
    HasFullCommoditySearchResults = function() return world.full ~= false end,
    GetBrowseResults = function() return world.browse or {} end }
-- the old auction house: one page of auctions (itemID, count, buyout) out of world.pageTotal
function GetNumAuctionItems() return #(world.page or {}), world.pageTotal or #(world.page or {}) end
function GetAuctionItemInfo(_, i) local r = world.page[i]; return "Thing " .. r[1], 1, r[2], 1, true, 1, "", r[3], 1, r[3], 0, nil, nil, "Someone", nil, 0, r[1], true end
TooltipDataProcessor = { calls = {}, AddTooltipPostCall = function(kind, fn) TooltipDataProcessor.calls[kind] = function(tt, data) fn(tt, data); composeTip(tt) end end }
function GetCursorPosition() return 380, 200 end
C_Container = { GetContainerNumSlots = function(bag) return bag == 0 and 3 or 0 end,
    GetContainerItemInfo = function(bag, slot)
        if slot == 1 then return { itemID = 4867, stackCount = 4, quality = 0, hyperlink = "|cnIQ0:|Hitem:4867::|h[Broken Scorpid Leg]|h|r", hasNoValue = false } end
        if slot == 2 then return { itemID = 783, stackCount = 2, quality = 1, hyperlink = "|cnIQ1:|Hitem:783::|h[Light Hide]|h|r" } end
    end }
C_Item = { GetItemInfo = function(link)
        local id = tonumber(tostring(link):match("[Hh]?item:(%d+)")); local it = ITEMS[id]
        if not it or (world.uncached and world.uncached[id]) then return nil end
        return it[1], link, it[2], 1, 1, "Misc", "Junk", 20, "", 0, it[3]
    end,
    GetItemCount = function(id) return world.bags[id] or 0 end,
    RequestLoadItemDataByID = function(id) world.requested = world.requested or {}; world.requested[id] = true end,
    GetItemNameByID = function(id) return ({ [2589] = "Linen Cloth", [2835] = "Rough Stone", [2840] = "Copper Bar", [2836] = "Coarse Stone" })[id] end }
Enum = { DamageMeterType = { DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5, Dispels = 6, DamageTaken = 7,
        AvoidableDamageTaken = 8, Deaths = 9, EnemyDamageTaken = 10 },
    StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 },
    DamageMeterSessionType = { Overall = 0, Current = 1, Expired = 2 },
    SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
    SpellBookSpellBank = { Player = 0, Pet = 1 }, TooltipDataType = { Item = 0, Unit = 2 } }

-- built-in damage meter ------------------------------------------------------------
local dmSessions = { { sessionID = 83, name = "Old Boar", durationSeconds = 20, dmg = 100, taken = 10, spells = { { 75, 100 } } } }
local function dmFind(id) for _, s in ipairs(dmSessions) do if s.sessionID == id then return s end end end
-- in a fight the meter's values are hidden, but they still carry what the game will draw
local function hideV(v) if world.combat or world.linger then return secret(v) end return v end
-- one session's sources for one kind of number: you, your pet, the others in the group (s.others), the enemies
local function dmSources(s, kind)
    local out = {}
    local function add(name, guid, class, own, amount, spells, extra)
        if amount and amount > 0 then
            local e = { name = name, guid = guid, class = class, own = own, amount = amount, spells = spells or {} }
            for k, v in pairs(extra or {}) do e[k] = v end
            out[#out + 1] = e
        end
    end
    local key = ({ [0] = "dmg", [2] = "healed", [5] = "interrupts", [7] = "taken" })[kind]
    if kind == 10 then
        for i = 1, s.enemies or 1 do add(s.name, nil, "", false, i == 1 and (s.dmg + (s.petDmg or 0)) or 10, s.enemySpells, { creatureID = 3000 + i, classification = "normal" }) end
        return out
    end
    if not key then return out end
    add("Tess Ter", "Player-1-0000ABCD", "HUNTER", true, s[key], kind == 0 and s.spells or s[key .. "Spells"])
    if kind == 0 and s.petDmg then add(world.pet or "Humar", "Pet-0-1", nil, false, s.petDmg, s.petSpells) end
    for _, o in ipairs(s.others or {}) do add(o.name, o.guid, o.class, false, o[key], o[key .. "Spells"]) end
    return out
end
local function dmSession(s, kind)
    local list = dmSources(s, kind)
    table.sort(list, function(a, b) return a.amount > b.amount end)       -- the game hands them over sorted
    local total, top, sources = 0, 0, {}
    local dur = s.durationSeconds or 12
    for i, e in ipairs(list) do
        total = total + e.amount
        if e.amount > top then top = e.amount end
        sources[i] = { isLocalPlayer = e.own, name = hideV(e.name), sourceGUID = hideV(e.guid), classFilename = e.class ~= nil and hideV(e.class) or nil,
            totalAmount = hideV(e.amount), amountPerSecond = hideV(e.amount / dur), sourceCreatureID = e.creatureID, classification = e.classification }
        if kind == 10 then sources[i].name = hide(e.name) end
    end
    -- the legacy shape the fight recorder reads: the total of a damage session is yours plus your pet's
    return { durationSeconds = hideV(dur), totalAmount = hideV(total), maxAmount = hideV(top), combatSources = sources }
end
local function dmSpells(s, kind, guid, creatureID)
    local found
    for _, e in ipairs(dmSources(s, kind)) do
        if (guid ~= nil and e.guid == guid) or (guid == nil and creatureID ~= nil and e.creatureID == creatureID) then found = e end
    end
    if not found then return nil end
    local list, top = {}, 0
    local dur = s.durationSeconds or 12
    for i, sp in ipairs(found.spells) do
        if sp[2] > top then top = sp[2] end
        list[i] = { spellID = hideV(sp[1]), totalAmount = hideV(sp[2]), amountPerSecond = hideV(sp[2] / dur), creatureName = hideV(sp[3] or ""),
            combatSpellDetails = { isPet = sp[3] ~= nil, unitName = hideV(sp[4] or "") } }
    end
    return { combatSpells = list, totalAmount = hideV(found.amount), maxAmount = hideV(top) }
end
-- everything since the last reset, folded into one session
local function dmOverall()
    local all = { sessionID = 0, name = "Overall", durationSeconds = 0, dmg = 0, taken = 0, healed = 0, interrupts = 0, spells = {}, others = {}, enemies = 1 }
    local byGuid = {}
    local function fold(into, from) for _, sp in ipairs(from or {}) do into[#into + 1] = sp end end
    local list = {}
    for _, s in ipairs(dmSessions) do list[#list + 1] = s end
    if world.combat and world.liveSession then list[#list + 1] = world.liveSession end
    for _, s in ipairs(list) do
        all.durationSeconds = all.durationSeconds + (s.durationSeconds or 12)
        for _, k in ipairs({ "dmg", "taken", "healed", "interrupts" }) do all[k] = all[k] + (s[k] or 0) end
        fold(all.spells, s.spells)
        if s.petDmg then all.petDmg = (all.petDmg or 0) + s.petDmg; all.petSpells = all.petSpells or {}; fold(all.petSpells, s.petSpells) end
        for _, o in ipairs(s.others or {}) do
            local t = byGuid[o.guid]
            if not t then t = { name = o.name, guid = o.guid, class = o.class, dmg = 0, taken = 0, healed = 0, interrupts = 0, dmgSpells = {}, healedSpells = {} }; byGuid[o.guid] = t; all.others[#all.others + 1] = t end
            for _, k in ipairs({ "dmg", "taken", "healed", "interrupts" }) do t[k] = t[k] + (o[k] or 0) end
            fold(t.dmgSpells, o.dmgSpells); fold(t.healedSpells, o.healedSpells)
        end
    end
    return all
end
local function dmByType(stype)
    if stype == 1 and world.currentEmpty and not world.combat then return { sessionID = 0, name = "", durationSeconds = 0 } end   -- "current" empties when the fight ends
    if stype == 0 then if #dmSessions == 0 and not (world.combat and world.liveSession) then return nil end return dmOverall() end
    if world.combat and world.liveSession then return world.liveSession end
    return dmSessions[#dmSessions]
end
dmResets, chatSent = 0, {}
C_DamageMeter = {
    IsDamageMeterAvailable = function() return true end,
    GetAvailableCombatSessions = function()
        local out = {}
        for i, s in ipairs(dmSessions) do out[i] = { sessionID = hide(s.sessionID), name = hide(s.name), durationSeconds = hide(s.durationSeconds) } end
        return out
    end,
    GetCombatSessionFromID = function(id, kind)
        local s = dmFind(id); if not s then return nil end
        return dmSession(s, kind)
    end,
    GetCombatSessionSourceFromID = function(id, kind, guid, creatureID)
        local s = dmFind(id); if not s then return nil end
        if issecretvalue(guid) then if world.hiddenGuidOk then guid = SECRET_OF[guid] else return nil end end
        return dmSpells(s, kind, guid, creatureID)
    end,
    GetCombatSessionFromType = function(stype, kind)
        local s = dmByType(stype); if not s then return nil end
        return dmSession(s, kind)
    end,
    GetCombatSessionSourceFromType = function(stype, kind, guid, creatureID)
        local s = dmByType(stype); if not s then return nil end
        if issecretvalue(guid) then if world.hiddenGuidOk then guid = SECRET_OF[guid] else return nil end end
        return dmSpells(s, kind, guid, creatureID)
    end,
    GetSessionDurationSeconds = function(stype) local s = dmByType(stype); return s and hideV(s.durationSeconds or 12) or nil end,
    ResetAllCombatSessions = function()
        if world.combat then error("cannot reset in combat") end
        for i = #dmSessions, 1, -1 do dmSessions[i] = nil end
        dmResets = dmResets + 1
        if dmFire then dmFire("DAMAGE_METER_RESET") end
    end,
}
-- the game's own number shortening: takes a hidden number and gives a hidden text
function AbbreviateNumbers(v)
    if issecretvalue(v) then return secret(tostring(math.floor((SECRET_OF[v] or 0) + 0.5))) end
    return tostring(math.floor(v + 0.5))
end
function SendChatMessage(msg, channel, _, target)
    if world.chatRefuse then error("chat is not available") end
    chatSent[#chatSent + 1] = { msg = msg, channel = channel, target = target }
end
function IsInGuild() return world.guild == true end
function UnitIsFriend() return world.friendTarget == true end
function GetCVar(name) if name == "damageMeterEnabled" then return world.meterCVar or "1" end end

-- professions, recipes, trainer, spellbook, bars ---------------------------------------
local PROFS = { [7] = { "Mining", 136248, 50, 75 }, [8] = { "Engineering", 136243, 34, 75 }, [5] = { "First Aid", 135966, 15, 75 }, [6] = { "Cooking", 133971, 1, 75 } }
function GetProfessions() return 7, 8, 5, nil, 6 end
function GetProfessionInfo(i) local p = PROFS[i]; if p then return p[1], p[2], p[3], p[4], 2, 21, 186, 0 end end
local RECIPES = {
    [3918] = { name = "Rough Blasting Powder", diff = 0, trivial = 60, reagents = { { 2835, 1 } }, out = 4357 },
    [3919] = { name = "Rough Dynamite", diff = 1, trivial = 90, reagents = { { 2835, 2 }, { 2589, 1 } }, out = 4358, qmin = 2, qmax = 2 },
    [3920] = { name = "Crafted Light Shot", diff = 3, trivial = 30, reagents = { { 2840, 1 } }, out = 2516 },
    [3921] = { name = "Handful of Copper Bolts", diff = 2, trivial = 45, reagents = { { 2840, 1 } }, out = 4359 },
    [9999] = { name = "Unlearned Thing", diff = 0, learned = false, reagents = {} },
}
C_TradeSkillUI = {
    IsTradeSkillReady = function() return world.tradeskillOpen ~= nil end,
    IsTradeSkillLinked = function() return false end,
    GetBaseProfessionInfo = function() return { professionName = world.tradeskillOpen or "", skillLevel = 34, maxSkillLevel = 75 } end,
    GetAllRecipeIDs = function() return { 3918, 3919, 3920, 3921, 9999 } end,
    GetRecipeInfo = function(id) local r = RECIPES[id]; return { recipeID = id, name = r.name, learned = r.learned ~= false, relativeDifficulty = r.diff, maxTrivialLevel = r.trivial, isGatheringRecipe = false, isDummyRecipe = false } end,
    GetRecipeSchematic = function(id)
        local slots = {}
        for i, x in ipairs(RECIPES[id].reagents) do slots[i] = { required = true, reagentType = 1, quantityRequired = x[2], reagents = { { itemID = x[1] } } } end
        local r = RECIPES[id]
        return { recipeID = id, reagentSlotSchematics = slots, outputItemID = r.out, quantityMin = r.qmin or 1, quantityMax = r.qmax or 1 }
    end,
}
local TRAINER = { { "Coarse Blasting Powder", "unavailable", "Engineering", 75 }, { "Rough Copper Bomb", "unavailable", "Engineering", 36 }, { "Rough Dynamite", "used", "Engineering", 1 } }
function IsTradeskillTrainer() return true end
function GetNumTrainerServices() return #TRAINER end
function GetTrainerServiceInfo(i) return TRAINER[i][1], TRAINER[i][2], 136243, 0 end
function GetTrainerServiceSkillReq(i) return TRAINER[i][3], TRAINER[i][4], true end
local BOOK = { lines = { { name = "General", offset = 0, n = 2 }, { name = "Beast Mastery", offset = 2, n = 1 }, { name = "Marksmanship", offset = 3, n = 4 } },
    items = { { "Attack", 6603 }, { "Berserking", 20554 }, { "Aspect of the Monkey", 13163 }, { "Arcane Shot", 3044 }, { "Serpent Sting", 1978 },
        { "Track Beasts", 1494 }, { "Auto Shot", 75 } } }
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return #BOOK.lines end,
    GetSpellBookSkillLineInfo = function(i) local l = BOOK.lines[i]; return { name = l.name, itemIndexOffset = l.offset, numSpellBookItems = l.n, shouldHide = false, isGuild = false } end,
    GetSpellBookItemInfo = function(i) local it = BOOK.items[i]; if not it then return nil end; return { name = it[1], spellID = it[2], itemType = 1, isPassive = false, isOffSpec = false } end,
}
local BARS = { [1] = { "spell", 1978 }, [2] = { "spell", 3044 }, [3] = { "spell", 75 }, [9] = { "macro", 1 } }
function GetActionInfo(slot) local a = BARS[slot]; if a then return a[1], a[2], a[1] end end
BARS[61] = { "spell", 781 }
SPELLS[781] = "Disengage"
SPELLS[14281] = "Arcane Shot"                  -- a higher rank: same name, another id
local BINDINGS = { ACTIONBUTTON1 = "CTRL-5", ACTIONBUTTON2 = "R", MULTIACTIONBAR1BUTTON1 = "BUTTON4" }
function GetBindingKey(cmd) return BINDINGS[cmd] end
-- the game's cooldown manager: icons that know only a cooldown id
local CDM = { [11] = { spellID = 14281 }, [12] = { spellID = 1978 }, [13] = { spellID = 19434 }, [14] = { spellID = 781, overrideSpellID = 781 } }
C_CooldownViewer = { GetCooldownViewerCooldownInfo = function(id) return CDM[id] end }
local function cdmItem(id) local w = widget("Frame"); w.cooldownID = id; w.w = 40; function w:GetCooldownID() return self.cooldownID end; return w end
local cdmItems = { cdmItem(11), cdmItem(12), cdmItem(13) }
EssentialCooldownViewer = widget("Frame"); function EssentialCooldownViewer:GetItemFrames() return cdmItems end
local cdmUtility = { cdmItem(14) }
UtilityCooldownViewer = widget("Frame"); function UtilityCooldownViewer:GetChildren() return unpack(cdmUtility) end
function GetActionText(slot) if BARS[slot] and BARS[slot][1] == "macro" then return "Opener" end end
function GetMacroBody(name) return "#showtooltip\n/cast Hunter's Mark" end
MenuUtil = { CreateContextMenu = function(owner, gen)
    local root = { CreateTitle = function() end, CreateDivider = function() end,
        CreateButton = function(_, text, fn) MenuUtil.buttons[text] = fn end,
        CreateCheckbox = function(_, text, get, set) get(); MenuUtil.checks[text] = set end }
    gen(owner, root)
end, buttons = {}, checks = {} }

-- a vendor: a bow it sells for 20s (the auction house pays more), and a price with an extended cost (skipped)
local MERCHANT = { { 2506, "Hornwood Recurve Bow", 2000, 1, -1 }, { 2589, "Linen Cloth", 0, 1, -1 } }
function GetMerchantNumItems() return world.merchant and #MERCHANT or 0 end
function GetMerchantItemInfo(i) local m = MERCHANT[i]; return m[2], 1, m[3], m[4], m[5], true, true, m[3] == 0 end
function GetMerchantItemID(i) return MERCHANT[i][1] end


-- /who: a small population; the server answers at most 50 names, and says how many matched
local WHO_POP = {}
for i = 1, 60 do WHO_POP[#WHO_POP + 1] = { fullName = "Pally" .. i, level = 20, classStr = "Paladin", filename = "PALADIN", raceStr = i <= 40 and "Tauren" or "Orc",
    fullGuildName = i <= 12 and "Lifers" or "", area = i <= 30 and "Orgrimmar" or "The Barrens" } end
for i = 1, 5 do WHO_POP[#WHO_POP + 1] = { fullName = "Hunty" .. i, level = 12, classStr = "Hunter", filename = "HUNTER", raceStr = "Orc", fullGuildName = "", area = "Durotar" } end
local function whoMatch(filter)
    local lo, hi = filter:match("^(%d+)%-(%d+)")
    local c, r, z = filter:match('c%-"(.-)"'), filter:match('r%-"(.-)"'), filter:match('z%-"(.-)"')
    local out = {}
    for _, p in ipairs(WHO_POP) do
        if p.level >= (tonumber(lo) or 1) and p.level <= (tonumber(hi) or 999) and (not c or p.classStr == c) and (not r or p.raceStr == r) and (not z or p.area == z) then out[#out + 1] = p end
    end
    return out
end
C_FriendList = {
    SendWho = function(filter) world.whoSent = (world.whoSent or 0) + 1; world.lastWho = filter; world.whoResults = whoMatch(filter) end,
    GetNumWhoResults = function() local r = world.whoResults or {}; return math.min(50, #r), #r end,
    GetWhoInfo = function(i) return (world.whoResults or {})[i] end,
    SetWhoToUi = function() end }
FriendsFrame = CreateFrame("Frame", "FriendsFrame")
AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame")
-- this client's own /who list ("Looking For Group"): it pops up on every answer it hears
LFGWhoFrame = CreateFrame("Frame", "LFGWhoFrame"); LFGWhoFrame.shown = false
LFGWhoFrame:RegisterEvent("WHO_LIST_UPDATE")
LFGWhoFrame:SetScript("OnEvent", function(self) self.shown = true end)
function LFGWhoFrame:UnregisterEvent(e) self.events[e] = nil end
function GetFramesRegisteredForEvent(e) local out = {}; for _, f in ipairs(frames) do if f.events and f.events[e] then out[#out + 1] = f end end; return unpack(out) end
WorldFrame = CreateFrame("Frame", "WorldFrame")

-- the ready check: a second bag, free slots, durability, what items are, known spells, weapon poisons
do
    local slots, info = C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo
    C_Container.GetContainerNumSlots = function(bag) if bag == 1 then return #(world.bag1 or {}) end return slots(bag) end
    C_Container.GetContainerItemInfo = function(bag, slot) if bag == 1 then return (world.bag1 or {})[slot] end return info(bag, slot) end
    C_Container.GetContainerNumFreeSlots = function(bag) if bag == 0 then return world.free or 10, 0 end return 0, 0 end
end
function GetInventoryItemDurability(slot) if slot == 5 and world.dur then return world.dur[1], world.dur[2] end end
C_Item.GetItemSpell = function(id) return world.itemSpells and world.itemSpells[id] end
C_Item.GetItemInfoInstant = function(id) return id, "Misc", "Junk", "", 1, world.itemClass and world.itemClass[id] or 15, 0 end
function IsPlayerSpell(id) return world.spells ~= nil and world.spells[id] == true end
function GetWeaponEnchantInfo() return unpack(world.enchant or { false, 0, 0, 0, false, 0, 0, 0 }) end
function GetInventoryItemID() return nil end
function UnitCreatureFamily(u) return u == "pet" and world.petFamily or nil end
strsplit = strsplit or function(sep, s) local out = {}; for part in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end; return unpack(out) end
-- absorb shields: the total left on a unit (hidden in combat, like other numbers) and the buff behind it
function UnitGetTotalAbsorbs() if world.absorbApi == false then return nil end if world.absorbHidden then return secret() end return hide(world.absorb or 0) end
C_UnitAuras = {
    GetAuraDataByIndex = function(_, i)
        local a = (world.auras or {})[i]
        if not a or world.aurasBlank then return nil end
        if world.aurasHidden then return { spellId = secret(), name = secret(), icon = secret(), expirationTime = secret(), duration = secret(), auraInstanceID = a.auraInstanceID } end
        return a
    end,
    GetPlayerAuraBySpellID = function(id)
        if world.aurasBlank then return nil end
        for _, a in ipairs(world.auras or {}) do
            if a.spellId == id then return world.aurasHidden and { auraInstanceID = a.auraInstanceID } or a end
        end
    end,
}
EventRegistry = { callbacks = {},
    RegisterCallback = function(self, event, fn, owner) self.callbacks[event] = self.callbacks[event] or {}; table.insert(self.callbacks[event], { fn, owner }) end,
    TriggerEvent = function(self, event, ...) for _, c in ipairs(self.callbacks[event] or {}) do c[1](c[2], ...) end end }
-- MODE=bare: a hostile client where the helpful APIs are missing and health never becomes readable
local MODE = os.getenv("MODE") or "full"
if MODE == "bare" then
    UnitGetTotalAbsorbs, C_UnitAuras, EventRegistry = nil, nil, nil
    C_DamageMeter, C_TradeSkillUI, C_SpellBook, GetProfessions, GetProfessionInfo, MenuUtil = nil, nil, nil, nil, nil, nil
    GetActionInfo, GetNumTrainerServices, C_Item, issecretvalue_real = nil, nil, nil, issecretvalue
    C_AuctionHouse, TooltipDataProcessor, hooksecurefunc, GetNormalizedRealmName, DearLordAuctionDB = nil, nil, nil, nil, nil
    GetMerchantNumItems, GetMerchantItemInfo, GetMerchantItemID = nil, nil, nil
    C_FriendList, UnitIsPlayer = nil, nil
    UnitHealth = function() return secret() end
    UnitPower = function() return secret() end
    C_Spell.GetSpellCooldown = nil
    UIDropDownMenu_Initialize = function(_, fn) fn() end; UIDropDownMenu_CreateInfo = function() return {} end
    UIDropDownMenu_AddButton = function() end; ToggleDropDownMenu = function() end
end
-- load the addon the way the client does ------------------------------------------------
local ns, files = {}, {}
for line in io.lines(addonDir .. "/DearLordStats.toc") do
    line = line:gsub("\r", "")
    if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = line end
end
for _, file in ipairs(files) do assert(loadfile(addonDir .. "/" .. file))("DearLordStats", ns) end
local feedLog = {}
do local orig = ns.Feed; ns.Feed = function(text, opts) feedLog[#feedLog + 1] = text; return orig(text, opts) end end

-- SV=path: start from a real SavedVariables file to test upgrades from older versions
if os.getenv("SV") then dofile(os.getenv("SV")) end
-- driving the simulation ----------------------------------------------------------------
local function fire(event, ...)
    for _, f in ipairs(frames) do
        if f.events and f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end
dmFire = fire
local function advance(seconds)
    local step = 0.25
    for _ = 1, math.floor(seconds / step + 0.5) do
        now, wall = now + step, wall + step
        local due = {}
        for i = #timers, 1, -1 do if timers[i].at <= now then table.insert(due, 1, table.remove(timers, i)) end end
        for _, t in ipairs(due) do t.fn() end
        for _, f in ipairs(frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f, step) end end
    end
end
local function strip(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function hud(title)
    io.write("\n== " .. title .. "\n")
    for _, key in ipairs({ "xp", "threat" }) do
        local f = ns.huds[key]
        if f.shown then for _, l in ipairs(f.lines) do if l.shown and l.text ~= "" then io.write("   " .. strip(l.text) .. "\n") end end end
    end
    for _, row in ipairs(ns.feed.rows) do if row.shown then io.write("   feed> " .. strip(row.text.text) .. "\n") end end
end
local function panelText(title)
    io.write("\n-- panel: " .. title .. "\n")
    for _, f in ipairs(frames) do
        local c = rawget(f, "control")
        if c and f.shown and title:find("Settings") then
            io.write("   " .. (c.header and c.header:upper() or ("  " .. c.label .. (rawget(f, "value") and ("    | " .. f.value.text) or ""))) .. "\n")
        elseif f.kind == "Frame" and f.shown and f.left and f.left.text ~= "" then
            local right = (f.right and f.right.text ~= "") and ("    | " .. strip(f.right.text)) or ""
            local cells = rawget(f, "cells")
            if cells then
                local t = {}
                for _, c in ipairs(cells) do if c.shown then t[#t + 1] = strip(c.text) end end
                if #t > 0 then right = right .. "    | " .. table.concat(t, " | ") end
            end
            io.write("   " .. strip(f.left.text) .. right .. "\n")
        end
    end
end

local nextSession = 100
local function runFight(o)
    world.targetLevel, world.targetName = o.mobLevel or world.level, o.name
    world.combat = true
    -- the fight as the game's meter has it while it runs (hidden from addons until it ends)
    world.liveSession = { sessionID = nextSession + 1, name = o.name or "Mob", durationSeconds = o.duration or 12, dmg = o.dmg, taken = o.taken,
        healed = o.healed, enemies = o.mobs or 1, spells = o.spells or { { 75, o.dmg } }, petDmg = o.petDmg, petSpells = o.petSpells,
        others = o.others, interrupts = o.interrupts, healedSpells = o.healedSpells, takenSpells = o.takenSpells, enemySpells = o.enemySpells,
        interruptsSpells = o.interruptsSpells }
    world.threat = {}
    for i = 1, o.mobs or 1 do world.threat["nameplate" .. i] = "Creature-0-" .. nextSession .. "-" .. i end
    world.threat.target = world.threat.nameplate1
    local t0 = now
    fire("PLAYER_REGEN_DISABLED")
    for i = 1, o.mobs or 1 do fire("UNIT_THREAT_LIST_UPDATE", "nameplate" .. i) end
    for _, c in ipairs(o.casts or {}) do
        fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-" .. now .. c, c)
        advance(0.25)
        fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. (now - 0.25) .. c, c)
        advance(1.5)
    end
    fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, nextSession + 1)
    if o.during then advance(0.5); o.during() end
    fire("UNIT_COMBAT", "player", "WOUND", "", o.taken, 1)
    fire("UNIT_COMBAT", "target", "WOUND", "", o.dmg, 1)
    for _ = 1, o.oom or 0 do fire("UI_ERROR_MESSAGE", 50, "Not enough mana") end
    advance((o.duration or 12) - (o.exact and (now - t0) or 0))        -- exact: the combat flag is up for just the duration
    if o.tail then world.liveSession.durationSeconds = (o.duration or 12) + o.tail end   -- the game's clock runs on after the fight
    world.hp = math.max(0, world.hp - o.taken); world.mana = math.max(0, world.mana - (o.manaUsed or 40))
    if o.die then world.hp = 0; fire("PLAYER_DEAD") end
    nextSession = nextSession + 1
    dmSessions[#dmSessions + 1] = world.liveSession
    world.liveSession.sessionID = nextSession
    world.combat = false; world.threat = {}; world.liveSession = nil
    if o.linger then world.linger = true end                       -- left combat, the game still hides the numbers
    fire("PLAYER_REGEN_ENABLED")
    if o.linger then o.linger(); world.linger = nil end
    for _ = 1, o.kills or (o.die and 0 or 1) do
        fire("CHAT_MSG_COMBAT_XP_GAIN", (o.name or "Mob") .. " dies, you gain 80 experience.")
        world.xp = world.xp + 80; fire("PLAYER_XP_UPDATE", "player")
    end
    advance(4)
end

-- the play-through -------------------------------------------------------------------------
fire("ADDON_LOADED", "DearLordStats")
fire("PLAYER_ENTERING_WORLD", true, false)
advance(8)
hud("fresh login")

runFight({ name = "Kolkar Drudge", dmg = 161, taken = 64, duration = 23, casts = { 1978, 3044 }, spells = { { 75, 58 }, { 3044, 41 }, { 1978, 32 }, { 6603, 30 } } })
hud("after fight 1 (one mob)")
world.hp = 175; world.mana = 120
advance(20)
local threatNoPet
world.tlist = { player = { true, 3, 100, 100, 5000 } }
runFight({ during = function() threatNoPet = ns.huds.threat.shown end, name = "Kolkar Outrunner", mobs = 2, kills = 2, dmg = 300, taken = 150, duration = 31, oom = 2, casts = { 3044 }, spells = { { 75, 180 }, { 3044, 120 } } })
hud("after fight 2 (two mobs, ran out of mana, close call)")
world.hp = 175; world.mana = 120; world.pet = "Humar"; fire("UNIT_PET", "player")
advance(15)
local function threatRows()
    local tw, out = ns.huds.threat, {}
    if not tw.shown then return nil end
    for i = 1, tw.count or 0 do
        local r, v = tw.rows[i], {}
        for k = 1, 2 do if r.cells[k].shown and r.cells[k].text ~= "" then v[#v + 1] = strip(r.cells[k].text) end end
        out[#out + 1] = strip(r.name.text) .. "=" .. table.concat(v, "  ")
    end
    return table.concat(out, ", ")
end
local threatSolo, threatSoloEdge, threatAfter, threatParty, threatPreview, threatDim, threatClosed
world.tlist = { player = { false, 1, 92, 110, 16900 }, pet = { true, 3, 100, 100, 18400 } }
local threatWarned, threatWarnSounds, threatWarnTitle, threatWarnCount, threatWarnAfter
local threatTankRole, threatTankStance, threatBattleStance, threatBackOn
runFight({ during = function()
    threatSolo = threatRows()
    threatWarned, threatWarnSounds, threatWarnTitle, threatWarnCount = ns.threat.warn, #soundsPlayed, strip(ns.huds.threat.title.text or ""), ns.threat.warnings
    local r = ns.huds.threat.rows[2]
    threatSoloEdge = r ~= nil and r.edge.shown
    -- a tank gets no pull warning: by role, or by Defensive Stance
    world.role = "TANK"; ns.RefreshThreat(); threatTankRole = ns.threat.warn == false and strip(ns.huds.threat.title.text or "") == "Threat"
    world.role = nil; world.class, world.stance = "Warrior", 2; ns.RefreshThreat(); threatTankStance = ns.threat.warn == false and ns.ThreatIsTank() == true
    world.stance = 1; threatBattleStance = ns.ThreatIsTank() == false
    world.class, world.stance = nil, nil; ns.RefreshThreat(); threatBackOn = ns.threat.warn == true and #soundsPlayed
end, name = "Dire Mottled Boar", dmg = 120, petDmg = 90, petSpells = { { 17253, 60 }, { 16827, 30 } }, taken = 20, duration = 14, spells = { { 75, 120 } } })
hud("after fight 3 (with a pet)")
world.petLevel, world.petXP, world.petXPMax = 6, 0, 900
advance(1)
world.petXP = 45; fire("UNIT_PET_EXPERIENCE", "pet"); advance(1)
hud("pet out, one pet kill")
local function blockText(key)
    local b = ns.huds.xp.blocks[key]
    if not b.on then return nil end
    local t = {}
    if b.left then t[#t + 1] = strip(b.left.text); t[#t + 1] = strip(b.right.text) end
    for i = 1, b.shownSubs do t[#t + 1] = strip(b.subs[i].text) end
    return (table.concat(t, " | "):gsub("|T.-|t ?", ""))
end
local function petHudLine() return blockText("pet") end
local petLineHappy = petHudLine()
local petFace = ns.huds.xp.blocks.pet.subs[1].text:find("UI-PetHappiness:14:14:0:0:128:64:0:24", 1, true) ~= nil
local xpBlock = blockText("xp")
local xpRested = ns.huds.xp.blocks.xp.extra
world.petXP = 890; fire("UNIT_PET_EXPERIENCE", "pet"); advance(1)
world.petLevel, world.petXP = 7, 20; fire("UNIT_PET_EXPERIENCE", "pet"); world.petHappy = 1; advance(1)
local petLineUnhappy = petHudLine()
local petBarColor = ns.huds.xp.blocks.pet.bar.color
local petBarRed = petBarColor ~= nil and petBarColor[1] > 0.7 and petBarColor[2] < 0.3
world.rested = 200; advance(1)
local restedShown = ns.huds.xp.blocks.xp.extra.shown and ns.huds.xp.blocks.xp.extra.w > 1 and (blockText("xp") or ""):find("200 rested", 1, true) ~= nil
world.rested = 0; advance(1)
local petSessionXP = ns.session.petXP
ns.db.background = true; ns.ApplyHudSettings(); ns.Feed("short", { key = "bgtest" }); advance(0.5)
local feedJoined = false
for _, row in ipairs(ns.feed.rows) do if row.shown and row.key == "bgtest" then feedJoined = row.bg.shown and row:GetWidth() >= ns.huds.xp:GetWidth() end end
ns.db.background = false; ns.ApplyHudSettings()
local petProbe = ns.db.diag.petProbe
ns.huds.xp.scripts.OnEnter(ns.huds.xp)
world.petHappy = nil
world.hp = 175
advance(10)
runFight({ name = "Armored Scorpid", mobs = 3, dmg = 80, taken = 175, duration = 9, die = true })
hud("after fight 4 (three mobs, died)")
world.hp = 175; world.mana = 120

-- professions
PROFS[7][3] = 51; fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 51."); fire("SKILL_LINES_CHANGED")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-x", 2575); fire("CHAT_MSG_LOOT", "You receive loot: |cnIQ1:|Hitem:2770::|h[Copper Ore]|h|rx2.")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-y", 2575); fire("CHAT_MSG_LOOT", "You receive loot: |cnIQ1:|Hitem:2835::|h[Rough Stone]|h|r.")
world.tooltip = "Tin Vein"; fire("UI_ERROR_MESSAGE", 50, "Requires Mining 65"); world.tooltip = nil
world.tradeskillOpen = "Engineering"; fire("TRADE_SKILL_SHOW"); fire("TRADE_SKILL_LIST_UPDATE"); advance(1); world.tradeskillOpen = nil
fire("TRAINER_SHOW"); advance(1)
advance(2)
hud("after mining, opening Engineering and visiting the trainer")
PROFS[8][3] = 36; fire("SKILL_LINES_CHANGED"); advance(50)
hud("Engineering reached 36 (a remembered trainer unlock)")
advance(70)
hud("a minute later (craft-now / cloth nudges may appear)")

-- a new spell appears in the spellbook and is not on the bars
BOOK.lines[3].n = 5; table.insert(BOOK.items, 7, { "Concussive Shot", 5116 }); fire("SPELLS_CHANGED"); advance(140)
hud("learned Concussive Shot")

-- journal, levelling, money
SlashCmdList["DEARLORDSTATS"]("note Hunter feels slow before the pet, great after")
world.money = world.money + 1234; fire("PLAYER_MONEY")
fire("QUEST_TURNED_IN", 1, 450, 0); fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 450 experience."); world.level = 8; fire("PLAYER_LEVEL_UP", 8)
world.xp = (world.xp + 450) - world.xpMax; world.xpMax = 1400; fire("PLAYER_XP_UPDATE", "player"); advance(3)

-- two fights at the new level against the same higher-level mob
threatAfter = threatRows()
threatWarnAfter = ns.threat.warn == false and ns.huds.threat.warn.shown == false and strip(ns.huds.threat.title.text or "") == "Threat"
threatDim = ns.huds.threat.rows[1] and ns.huds.threat.rows[1].alpha
ns.huds.threat.close.scripts.OnClick(ns.huds.threat.close); advance(1)
threatClosed = ns.huds.threat.shown
world.party = { party1 = { name = "Tankard", class = "Warrior" }, party2 = { name = "Healbot", class = "Priest" } }
world.tlist = { player = { false, 0, 60, 66, 9000 }, party1 = { true, 3, 100, 100, 15000 }, party2 = { false, 0, 20, 22, 3000 } }
world.threatSecret = true
runFight({ during = function() threatParty = threatRows() end, name = "Razormane Hunter", mobLevel = 10, dmg = 200, taken = 120, duration = 20 }); world.hp = 175
world.party, world.threatSecret, world.tlist = nil, nil, nil
ns.ThreatPreview(5); threatPreview = threatRows(); advance(6)
-- Growl reminder: alone with Growl on is fine; a dungeon group is not; alone with it off is not
local G = ns.growl
local growlSolo = G.holder.shown == false and ns.GrowlWarning() == nil
world.party, world.instance = { party1 = { name = "Tankard", class = "Warrior" } }, "party"
fire("GROUP_ROSTER_UPDATE"); advance(1)
local growlDungeon = G.holder.shown and ns.GrowlWarning() == "on" and G.macro == "/petautocastoff Growl"
local growlPetLine = blockText("pet")
world.growl = false; G.button.scripts.PostClick(G.button, "LeftButton", true); G.button.scripts.PostClick(G.button, "LeftButton", false); advance(1)
local growlFixed = G.holder.shown == false and ns.GrowlWarning() == nil and ns.db.diag.growlClick == "worked"
world.party, world.instance = nil, nil
fire("GROUP_ROSTER_UPDATE"); advance(1)
local growlOffSolo = G.holder.shown and ns.GrowlWarning() == "off" and G.macro == "/petautocaston Growl"
G.button.scripts.PostClick(G.button, "RightButton", false); advance(3)
local growlDismissed = G.holder.shown == false and ns.GrowlWarning() == "off"
world.growl = nil; advance(3)
local growlBack = G.holder.shown == false and ns.GrowlWarning() == nil
-- ready check: joining a group lists what is missing; class things only when the character has them
local R, ready = ns.ready, {}
local function readyTexts()
    local t = {}
    for i = 1, R.frame.count or 0 do t[#t + 1] = (strip(R.frame.lines[i].text or ""):gsub("|T.-|t ", "")) end
    return R.frame.shown and table.concat(t, " / ") or "hidden"
end
local function readyItem(key) for _, c in ipairs(ns.ReadyList()) do if c.key == key then return (c.ok and "ok: " or "missing: ") .. c.text end end return "none" end
world.itemSpells, world.itemClass = { [4601] = "Food", [1179] = "Drink" }, { [2512] = 6 }
world.bag1 = { { itemID = 4601, stackCount = 2 }, { itemID = 2512, stackCount = 50 } }
world.free, world.dur, world.spells = 1, { 12, 60 }, { [883] = true }
ready.alone = readyTexts()
world.party = { party1 = { name = "Tankard", class = "Warrior" } }
fire("GROUP_ROSTER_UPDATE"); advance(1); ready.joined = readyTexts()
world.combat = true; fire("BAG_UPDATE_DELAYED"); ready.inFight = readyTexts()
world.combat = false; fire("BAG_UPDATE_DELAYED"); ready.afterFight = readyTexts() ~= "hidden"
world.petHappy = 1; fire("BAG_UPDATE_DELAYED"); ready.unhappy = readyItem("pet"); world.petHappy = nil
world.bag1 = { { itemID = 4601, stackCount = 10 }, { itemID = 1179, stackCount = 10 }, { itemID = 2512, stackCount = 1200 } }
world.free, world.dur = 10, { 60, 60 }
fire("BAG_UPDATE_DELAYED"); advance(1); ready.fixed = readyTexts() == "hidden" and R.active == false
world.free = 0; fire("BAG_UPDATE_DELAYED"); advance(3); ready.quietAfter = readyTexts() == "hidden"
world.party = nil; fire("GROUP_ROSTER_UPDATE"); advance(1)
world.party = { party1 = { name = "Tankard", class = "Warrior" } }; fire("GROUP_ROSTER_UPDATE"); advance(1); ready.rejoined = readyTexts()
R.frame.scripts.OnClick(R.frame, "LeftButton"); advance(3); ready.closed = readyTexts() == "hidden"
printed = {}; SlashCmdList["DEARLORDSTATS"]("ready"); ready.slash, ready.full = printed[1] or "", readyTexts()
R.frame.scripts.OnClick(R.frame, "LeftButton")
world.party = nil; fire("GROUP_ROSTER_UPDATE"); advance(1); world.free = nil
-- a rogue: nothing about poisons until they are learned or carried; Vanish powder only with Vanish
world.class, world.bag1, world.spells = "Rogue", {}, {}
ready.rogueNew = readyItem("poison") .. ", " .. readyItem("reagent:5140") .. ", " .. readyItem("water")
world.spells = { [2842] = true, [1856] = true }
ready.rogueLearned = readyItem("poison") .. ", " .. readyItem("reagent:5140")
world.bag1 = { { itemID = 6947, stackCount = 5 }, { itemID = 5140, stackCount = 3 } }
ready.rogueCarried = readyItem("poison") .. ", " .. readyItem("reagent:5140")
world.enchant = { true, 1800000, 0, 1 }; ready.rogueApplied = readyItem("poison")
world.enchant = { true, 120000, 0, 1 }; ready.rogueRunsOut = readyItem("poison")
world.enchant = nil
-- a shaman: the Ankh only once Reincarnation is known
world.class, world.bag1, world.spells = "Shaman", {}, {}
ready.shamanNew = readyItem("reagent:17030")
world.spells = { [20608] = true }; ready.shamanAnkh = readyItem("reagent:17030")
-- party targets: a small frame beside a party member's frame for what that member is targeting
local PT, partyT = ns.partyTargets, {}
CompactPartyFrameMember2 = CreateFrame("Button", "CompactPartyFrameMember2")
CompactPartyFrameMember2.unit = "party1"; CompactPartyFrameMember2:SetSize(72, 36); CompactPartyFrameMember2:Show()
CompactPartyFrameMember2.IsVisible = function(self) return self.shown end
world.party = { party1 = { name = "Tankard", class = "Warrior" }, party1target = { name = "Kolkar Stormer", class = "Warrior" } }
world.threat.party1target = "Creature-0-1-2-3-4-5"
fire("GROUP_ROSTER_UPDATE"); advance(1)
local pb = PT.buttons.party1
partyT.shown, partyT.unit, partyT.name, partyT.pct = pb.shown, pb.unit, pb.name.text, pb.pct.text
partyT.size, partyT.placed, partyT.others = tostring(pb.w) .. "x" .. tostring(pb.h), pb.placed, PT.buttons.party2.shown
partyT.notMine = pb.edge[1].shown
world.party.party1target = nil; advance(1); partyT.gone = pb.shown == false
world.party.party1target = { name = "Kolkar Stormer", class = "Warrior" }; advance(1)
world.combat = true; ns.db.partyTargetWidth = 140; ns.PlacePartyTargets(); partyT.inFight = pb.w
world.combat = false; ns.PlacePartyTargets(); partyT.afterFight = pb.w
ns.db.partyTargetWidth = 110
-- your threat on that target: a badge with the percentage, or "aggro"; a power bar under the health
local keepList = world.tlist
partyT.noThreat = pb.badge.shown == false and pb.power.shown == true
world.tlist = { player = { false, 1, 92, 95, 9000 } }; advance(1); partyT.threat = tostring(pb.badge.shown) .. " " .. tostring(pb.threat.text) .. " " .. tostring(pb.strip.shown)
world.tlist = { player = { true, 3, 100, 100, 12000 } }; advance(1); partyT.aggro = pb.threat.text
world.tlist = keepList; advance(1); partyT.threatGone = pb.badge.shown == false
ns.db.partyTargets = false; ns.PlacePartyTargets(); advance(1); partyT.off = pb.shown == false
ns.db.partyTargets = true; ns.PlacePartyTargets(); advance(1); partyT.onAgain = pb.shown
world.party, world.threat.party1target = nil, nil; fire("GROUP_ROSTER_UPDATE"); advance(1); partyT.solo = pb.shown == false
CompactPartyFrameMember2:Hide()
-- your own frame in the party frame gets your target beside it; the pet's needs a pet frame to sit by
CompactPartyFrameMember1 = CreateFrame("Button", "CompactPartyFrameMember1")
CompactPartyFrameMember1.unit = "player"; CompactPartyFrameMember1:SetSize(72, 36); CompactPartyFrameMember1:Show()
CompactPartyFrameMember1.IsVisible = function(self) return self.shown end
local keepTarget, keepName = world.threat.target, world.targetName
world.threat.target, world.targetName = "Creature-0-1-2-3-9-9", "Thunderhawk Hatchling"
advance(2)
local mineB, petB = PT.buttons.player, PT.buttons.pet
partyT.own = tostring(mineB.shown) .. " " .. tostring(mineB.unit) .. " " .. tostring(mineB.name.text) .. " " .. tostring(mineB.placed)
partyT.ownEdge, partyT.petUnplaced = mineB.edge[1].shown, petB.unit == "pettarget" and not petB.shown
ns.db.partyTargetsSelf = false; ns.PlacePartyTargets(); advance(1); partyT.ownOff = mineB.shown == false
ns.db.partyTargetsSelf = true; ns.PlacePartyTargets()
world.threat.target, world.targetName = keepTarget, keepName
CompactPartyFrameMember1:Hide(); advance(2)
-- the party frame while alone: off by default; on, it is shown again whenever the game hides it, never in a fight
local soloT = {}
CompactPartyFrame = CreateFrame("Frame", "CompactPartyFrame"); CompactPartyFrame:Hide()
CompactPartyFrame.UpdateVisibility = function(self) self:SetShown(world.party ~= nil) end
ns.ApplyPartySolo(); soloT.offByDefault = ns.db.partySolo == false and CompactPartyFrame.shown == false
ns.db.partySolo = true; ns.ApplyPartySolo(); soloT.on = CompactPartyFrame.shown
CompactPartyFrame:UpdateVisibility(); soloT.afterGameHid = CompactPartyFrame.shown
world.combat = true; CompactPartyFrame:UpdateVisibility(); soloT.inFight = CompactPartyFrame.shown
world.combat = false; advance(2); soloT.afterFight = CompactPartyFrame.shown
world.party = { party1 = { name = "Tankard", class = "Warrior" } }; CompactPartyFrame:UpdateVisibility(); fire("GROUP_ROSTER_UPDATE"); soloT.grouped = CompactPartyFrame.shown
world.party = nil; CompactPartyFrame:UpdateVisibility(); fire("GROUP_ROSTER_UPDATE"); soloT.leftGroup = CompactPartyFrame.shown
ns.db.partySolo = false; ns.ApplyPartySolo(); soloT.offAgain = CompactPartyFrame.shown == false
-- a warlock: a Voidwalker is fine alone and flagged in a group; another demon is fine there
world.class, world.spells, world.petFamily = "Warlock", { [688] = true }, "Voidwalker"
ready.voidSolo = readyItem("pet")
world.party = { party1 = { name = "Tankard", class = "Warrior" } }; ready.voidGroup = readyItem("pet")
world.petFamily = "Imp"; ready.impGroup = readyItem("pet")
world.party, world.petFamily = nil, nil
world.class, world.bag1, world.spells, world.itemSpells, world.itemClass, world.dur = nil, nil, nil, nil, nil, nil
runFight({ name = "Razormane Hunter", mobLevel = 10, dmg = 210, taken = 130, duration = 22 }); world.hp = 175

-- looting: junk, a stack, a green, a blue, some coin; then a loot reset files it under history
local function lootMsg(id, q, name, n) fire("CHAT_MSG_LOOT", "You receive loot: |cnIQ" .. q .. ":|Hitem:" .. id .. "::|h[" .. name .. "]|h|r" .. (n and ("x" .. n) or "") .. ".") end
lootMsg(4867, 0, "Broken Scorpid Leg"); lootMsg(783, 1, "Light Hide", 3); lootMsg(2140, 2, "Carving Knife"); lootMsg(9999, 3, "Blade of the Test")
fire("CHAT_MSG_LOOT", "You receive item: |cnIQ1:|Hitem:783::|h[Light Hide]|h|r.")           -- a quest reward: must NOT count
fire("CHAT_MSG_MONEY", "You loot 3 Silver, 20 Copper"); fire("CHAT_MSG_MONEY", "You loot 1 Gold, 5 Copper")
advance(130)
local lootBefore = ns.session.loot
local lootView = ns.LootView()

-- auction prices: the tooltip line, then a scan while the auction house is open
local tipLines, scanResult, tipStack, tipDup, tipOff = {}, {}, nil, nil, nil
if MODE ~= "bare" then
    local hook = TooltipDataProcessor.calls[0]
    scanResult.manualByDefault = ns.db.ahAutoScan == false
    ns.db.ahAutoScan = true                                      -- the automatic mode is tested below
    scanResult.compareDefault = ns.db.ahCompare
    ns.db.ahCompare = "alt"
    GameTooltip.lines = {}; hook(GameTooltip, { id = 783, dataInstanceID = 11 }); tipLines = { unpack(GameTooltip.lines) }
    hook(GameTooltip, { id = 783, dataInstanceID = 11 }); tipDup = #GameTooltip.lines
    GameTooltip.lines = {}; hook(GameTooltip, { id = 9999, dataInstanceID = 12 }); local tipUnknown = #GameTooltip.lines
    GameTooltip.forbidden = true; hook(GameTooltip, { id = 783, dataInstanceID = 13 }); local tipForbidden = #GameTooltip.lines; GameTooltip.forbidden = false
    ns.db.ahTooltip = false; hook(GameTooltip, { id = 783, dataInstanceID = 14 }); tipOff = #GameTooltip.lines; ns.db.ahTooltip = true
    GameTooltip:SetBagItem(0, 2); hook(GameTooltip, { id = 783, dataInstanceID = 15 }); tipStack = { unpack(GameTooltip.lines) }
    world.alt = true; GameTooltip.lines = {}; GameTooltip.dlsAhStack = nil; hook(GameTooltip, { id = 783, dataInstanceID = 16 }); scanResult.tipAlt = { unpack(GameTooltip.lines) }; world.alt = false
    ns.db.ahCompare = "always"; GameTooltip.lines = {}; GameTooltip.dlsAhStack = nil; hook(GameTooltip, { id = 783, dataInstanceID = 23 }); scanResult.tipAlways = { unpack(GameTooltip.lines) }; ns.db.ahCompare = "alt"
    -- an ore: the modifier adds what it is worth smelted (bars at 45c, ore at 30c)
    do
        local items = DearLordAuctionDB.realms["ClassicBetaPvE2-Horde"].items
        local function tip(inst, stack)
            GameTooltip.lines = {}; GameTooltip.raw = {}; GameTooltip.dlsAhStack = stack; hook(GameTooltip, { id = 2770, dataInstanceID = inst })
            local out = { unpack(GameTooltip.lines) }
            out.green = {}
            for i, l in ipairs(GameTooltip.raw) do out.green[i] = l:find(ns.GREEN, 1, true) ~= nil end
            return out
        end
        items[2840] = { p = 45, n = 12, d = AH_DAY - 2 }
        scanResult.smeltPlain = tip(301)
        world.alt = true
        scanResult.smelt = tip(302)
        local sets = GameTooltip.minSets or 0
        scanResult.smeltStack = tip(303, { id = 2770, count = 4 })
        scanResult.smeltPinned = (GameTooltip.minSets or 0) > sets and GameTooltip.minW >= 6 * #scanResult.smeltStack[4]   -- pinned columns, tooltip widened to fit
        -- the check a frame later: wide enough, so it stays in columns
        local function tick() for _, f in ipairs(frames) do if f.parent == GameTooltip and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.02) end end end
        tick(); scanResult.okMode = ns.db.diag.ah.tip and ns.db.diag.ah.tip.mode
        -- a tooltip with no minimum width: the same rows, padded with spaces
        local setMin = GameTooltip.SetMinimumWidth
        GameTooltip.SetMinimumWidth = false; sets = GameTooltip.minSets
        scanResult.smeltText = tip(307, { id = 2770, count = 4 })
        GameTooltip.SetMinimumWidth = setMin
        scanResult.smeltTextPlain = GameTooltip.minSets == sets and scanResult.smeltText[4]:find("^Horde AH smelted") ~= nil
        -- a tooltip that takes the minimum width but stays narrow: noticed a frame later, spaces from then on
        world.tipNarrow = true; tip(308, { id = 2770, count = 4 }); tick(); world.tipNarrow = nil
        scanResult.narrowMode, scanResult.narrowWhy = ns.db.diag.ah.tip.mode, ns.db.diag.ah.tip.why
        sets = GameTooltip.minSets
        scanResult.narrowNext = tip(309, { id = 2770, count = 4 }); scanResult.narrowNextPlain = GameTooltip.minSets == sets
        ns.AuctionTipColumns(true)                                                 -- back to real columns for the rest
        items[2840].p = 20; scanResult.smeltWorse = tip(304)                       -- bars cheaper than the ore
        items[2840].p = 45
        local keep = ns.char.recipes.Mining                                         -- the character's own recipe wins: 2 ore a bar
        ns.char.recipes.Mining = { list = { { name = "Smelt Copper", out = 2840, reagents = { { id = 2770, qty = 2 } } } } }
        scanResult.smeltOwn = tip(305)
        ns.char.recipes.Mining = keep
        items[2840] = nil; scanResult.smeltNoBar = tip(306)
        world.alt = false; GameTooltip.dlsAhStack = nil; GameTooltip.lines = {}
    end
    fire("MODIFIER_STATE_CHANGED", "LALT", 1)
    scanResult.unknownAndForbidden = tipUnknown == 0 and tipForbidden == 0
    -- the automatic scan is sent on the next key press (the game ignores a full-list request from a timer), not Escape
    local keys = DearLordStatsCensusKeys
    fire("AUCTION_HOUSE_SHOW"); advance(6)
    keys.scripts.OnKeyDown(keys, "ESCAPE")
    scanResult.heldBack = C_AuctionHouse.requests == 0 and ns.AuctionStatus().armed == true
    keys.scripts.OnKeyDown(keys, "W"); advance(1)
    fire("REPLICATE_ITEM_LIST_UPDATE"); advance(2)
    scanResult.requests = C_AuctionHouse.requests
    scanResult.stone = ns.AuctionPrice("|Hitem:2835::|h[Rough Stone]|h")
    scanResult.realm = DearLordAuctionDB.realms["ClassicBetaPvE2-Horde"]
    -- the client fires the event again as item data loads: the list already read must not be read again
    local feedBefore, lateBefore = #feedLog, ns.db.diag.ah.late or 0
    for _ = 1, 3 do fire("REPLICATE_ITEM_LIST_UPDATE"); advance(2) end
    scanResult.rereads = (#feedLog - feedBefore) + ((ns.db.diag.ah.late or 0) - lateBefore)
    fire("AUCTION_HOUSE_CLOSED"); fire("AUCTION_HOUSE_SHOW"); advance(7); keys.scripts.OnKeyDown(keys, "W")
    scanResult.requestsAfterSecondOpen = C_AuctionHouse.requests
    printed = {}; SlashCmdList["DEARLORDSTATS"]("scan"); scanResult.throttleMsg = printed[1] or ""
    SlashCmdList["DEARLORDSTATS"]("scan force"); advance(1); fire("REPLICATE_ITEM_LIST_UPDATE"); advance(2); scanResult.requestsAfterForce = C_AuctionHouse.requests
    fire("AUCTION_HOUSE_CLOSED")
    -- a goblin auction house: neutral, shared by both factions, scanned into its own key
    world.npc, world.npcFaction = true, nil
    -- minutes after the Horde scan: the account's 15 minutes are not over, so nothing is asked; another addon's
    -- full scan (Auctionator) brings a list anyway, and it is read for this never-scanned house
    local reqBefore = C_AuctionHouse.requests
    fire("AUCTION_HOUSE_SHOW"); advance(6); keys.scripts.OnKeyDown(keys, "W")
    scanResult.neutralAsked = C_AuctionHouse.requests - reqBefore
    fire("REPLICATE_ITEM_LIST_UPDATE"); advance(2)
    scanResult.foreign = ns.db.diag.ah.foreign
    scanResult.neutral = DearLordAuctionDB.realms["ClassicBetaPvE2-Neutral"]
    -- the status row's button: "Try now" while the 15 minutes run, and it does try
    ns.OpenPanel("prices")
    local tryBtn; for _, f in ipairs(frames) do if f.kind == "Button" and f.shown and f.fs and f.fs.text == "Try now" then tryBtn = f end end
    reqBefore = C_AuctionHouse.requests
    if tryBtn then tryBtn.scripts.OnClick(tryBtn) end
    scanResult.tryNow = tryBtn ~= nil and C_AuctionHouse.requests - reqBefore == 1
    scanResult.tryAbove = tryBtn ~= nil and (tryBtn.level or 0) > 2
    -- the button on the auction house window itself
    fire("REPLICATE_ITEM_LIST_UPDATE"); advance(2)
    local ahBtn = DearLordStatsScanButton
    reqBefore = C_AuctionHouse.requests
    if ahBtn then ahBtn.scripts.OnClick(ahBtn) end
    scanResult.ahButton = ahBtn ~= nil and C_AuctionHouse.requests - reqBefore == 1
    local keepReq = DearLordAuctionDB.lastRequest
    DearLordAuctionDB.lastRequest = 0; Auctionator = { SavedState = { TimeOfLastReplicateScan = wall - 120 } }
    scanResult.auctionatorWait = ns.AuctionStatus().nextIn
    Auctionator = nil; DearLordAuctionDB.lastRequest = keepReq
    fire("REPLICATE_ITEM_LIST_UPDATE"); advance(2)
    GameTooltip.lines = {}; hook(GameTooltip, { id = 2835, dataInstanceID = 17 }); scanResult.tipNeutralPlain = { unpack(GameTooltip.lines) }
    world.alt = true; GameTooltip.lines = {}; hook(GameTooltip, { id = 2835, dataInstanceID = 24 }); scanResult.tipNeutral = { unpack(GameTooltip.lines) }; world.alt = false
    fire("AUCTION_HOUSE_CLOSED"); world.npc = nil
    world.npc, world.npcFaction = true, nil; fire("AUCTION_HOUSE_SHOW"); advance(2)
    -- a request the server never answers: after a minute the row stops saying "waiting", and a list that
    -- arrives later is still taken
    SlashCmdList["DEARLORDSTATS"]("scan force"); advance(1)
    local wasWaiting = ns.AuctionStatus().state == "requested"
    advance(62)
    local st = ns.AuctionStatus()
    scanResult.gaveUp = wasWaiting and st.state == "idle" and st.silent == true
    local before = DearLordAuctionDB.lastRead
    fire("REPLICATE_ITEM_LIST_UPDATE"); advance(2)
    scanResult.lateTaken = DearLordAuctionDB.lastRead ~= before and DearLordAuctionDB.lastRead == DearLordAuctionDB.lastRequest
    scanResult.silentLogged = ns.db.diag.ah.log[1].out == "no answer" and ns.db.diag.ah.log[1].how == "slash" and ns.db.diag.ah.log[1].late ~= nil
    fire("AUCTION_HOUSE_CLOSED"); world.npc = nil
    -- the price browser: trend, search, history
    scanResult.trend = ns.AuctionTrend(2140)
    scanResult.search = ns.AuctionSearch("carv")
    GameTooltip.lines = {}; GameTooltip.dlsAhStack = nil; hook(GameTooltip, { id = 2140, dataInstanceID = 18 }); scanResult.tipTrend = { unpack(GameTooltip.lines) }
    world.npc, world.npcFaction = true, nil; fire("AUCTION_HOUSE_SHOW"); advance(2)
    -- a click while the auction house is busy (just opened, or a search running): nothing is sent until the
    -- house says it is free; a request the house throws away is sent again
    world.ahBusy = true
    reqBefore = C_AuctionHouse.requests
    DearLordStatsScanButton.scripts.OnClick(DearLordStatsScanButton); advance(1)
    local held = C_AuctionHouse.requests - reqBefore == 0 and ns.AuctionStatus().state == "queued" and DearLordStatsScanButton.label == "Auction house busy..."
    world.ahBusy = nil; fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    scanResult.queued = held and C_AuctionHouse.requests - reqBefore == 1 and ns.AuctionStatus().state == "requested"
    fire("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED"); advance(1)
    scanResult.resent = C_AuctionHouse.requests - reqBefore == 2 and ns.AuctionStatus().state == "requested"
    fire("REPLICATE_ITEM_LIST_UPDATE"); advance(2)
    local entry = ns.db.diag.ah.log[1]
    scanResult.logged = entry.how == "button" and entry.ready == "no" and entry.out == "read" and entry.ev:find("D") ~= nil and entry.resent == 1
    scanResult.logEntry = entry.how .. " ready=" .. entry.ready .. " ev=" .. entry.ev .. " out=" .. tostring(entry.out)
    -- the signal never comes: sent anyway after ten seconds
    world.ahBusy = true; reqBefore = C_AuctionHouse.requests
    SlashCmdList["DEARLORDSTATS"]("scan force"); advance(5)
    local stillHeld = C_AuctionHouse.requests - reqBefore == 0
    advance(7)
    scanResult.queueCap = stillHeld and C_AuctionHouse.requests - reqBefore == 1
    world.ahBusy = nil; fire("REPLICATE_ITEM_LIST_UPDATE"); advance(2)
    fire("AUCTION_HOUSE_CLOSED"); world.npc = nil
    ns.OpenPanel("prices", "carv"); panelText("Prices / search")
    for _, f in ipairs(frames) do if rawget(f, "onClick") and f.shown and f.link == "item:2140" then f.onClick(); break end end
    -- the history list starts collapsed to the newest day; a click on its header shows both days
    local function dayRows() local n = 0; for _, f in ipairs(frames) do if f.kind == "Frame" and f.shown and f.left and f.left.text:find("%d+ %a%a%a") and f.right and f.right.text:find("c") then n = n + 1 end end; return n end
    scanResult.collapsedRows = dayRows()
    for _, f in ipairs(frames) do if rawget(f, "onClick") and f.shown and f.left and f.left.text:find("HISTORY") then f.onClick(); break end end
    scanResult.expandedRows = dayRows()
    panelText("Prices / Carving Knife history")
    scanResult.historyRows = ns.AuctionHistory(2140)
    -- prices seen on screen between scans: a search brings one item up to date
    local house = DearLordAuctionDB.realms["ClassicBetaPvE2-Horde"]
    local countBefore, sight = house.count, {}
    local function at(id) local e = house.items[id]; return e and (e.p .. "/" .. e.n) or "none" end
    world.npc = nil; fire("AUCTION_HOUSE_SHOW")
    local crate = { itemID = 9101 }
    world.full, world.itemRows = true, { { buyoutAmount = 350, quantity = 1 }, { buyoutAmount = 300, quantity = 1 }, { bidAmount = 5, quantity = 1 } }
    fire("ITEM_SEARCH_RESULTS_UPDATED", crate); sight.first = at(9101)
    GameTooltip.lines = {}; GameTooltip.dlsAhStack = nil; hook(GameTooltip, { id = 9101, dataInstanceID = 31 }); sight.tip = { unpack(GameTooltip.lines) }
    -- a tooltip that is up while the listings arrive is drawn again
    local redrawn = 0
    local owner = { GetScript = function() return function() redrawn = redrawn + 1 end end }
    local tipWas = world.tooltip; world.tooltip = "Crate"; GameTooltip.GetOwner = function() return owner end
    world.full, world.itemRows = false, { { buyoutAmount = 500, quantity = 1 } }
    fire("ITEM_SEARCH_RESULTS_UPDATED", crate); sight.partialHigher, sight.redrawnUnchanged = at(9101), redrawn
    world.itemRows = { { buyoutAmount = 250, quantity = 1 } }
    fire("ITEM_SEARCH_RESULTS_UPDATED", crate); sight.partialLower, sight.redrawn = at(9101), redrawn
    world.full, world.itemRows = true, { { buyoutAmount = 400, quantity = 1 } }
    fire("ITEM_SEARCH_RESULTS_UPDATED", crate); sight.completeHigher = at(9101)
    world.tooltip = tipWas; GameTooltip.GetOwner = nil
    world.commodityRows = { { unitPrice = 20, quantity = 50 }, { unitPrice = 25, quantity = 10 } }
    fire("COMMODITY_SEARCH_RESULTS_UPDATED", 9102); sight.commodity = at(9102)
    world.browse = { { itemKey = { itemID = 9103 }, minPrice = 7, totalQuantity = 4 }, { itemKey = { itemID = 9104, itemSuffix = 12 }, minPrice = 90, totalQuantity = 1 } }
    fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"); sight.browse = at(9103) .. " " .. at(9104)
    fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { { itemKey = { itemID = 9104, itemSuffix = 13 }, minPrice = 120, totalQuantity = 1 } }); sight.variant = at(9104)
    world.page = { { 9105, 5, 500 }, { 9105, 1, 80 } }
    fire("AUCTION_ITEM_LIST_UPDATE"); sight.page = at(9105)
    world.page, world.pageTotal = { { 9105, 1, 300 } }, 120
    fire("AUCTION_ITEM_LIST_UPDATE"); sight.pagePartial = at(9105)
    world.page, world.pageTotal = nil, nil
    -- the usual price: the middle of the daily lows, shown beside the price
    house.items[9101].h = AH_DAY .. ":400:400 " .. (AH_DAY - 1) .. ":354:400 " .. (AH_DAY - 2) .. ":1818:1900 " .. (AH_DAY - 3) .. ":452:500 " .. (AH_DAY - 4) .. ":2399:2500"
    sight.usual = ns.AuctionUsual(9101)
    GameTooltip.lines = {}; GameTooltip.dlsAhStack = nil; hook(GameTooltip, { id = 9101, dataInstanceID = 32 }); sight.tipUsual = { unpack(GameTooltip.lines) }
    sight.ages = ns.AuctionAgeText(0, 30) .. ", " .. ns.AuctionAgeText(0, 300) .. ", " .. ns.AuctionAgeText(1, 7200) .. ", " .. ns.AuctionAgeText(3, 3 * 86400) .. ", " .. ns.AuctionAgeText(0)
    fire("AUCTION_HOUSE_CLOSED")
    world.itemRows = { { buyoutAmount = 1, quantity = 1 } }
    fire("ITEM_SEARCH_RESULTS_UPDATED", crate); sight.closed = at(9101)
    sight.probe = ns.db.diag.ahSight
    for id = 9101, 9105 do house.items[id] = nil end; house.count = countBefore       -- leave the house as the checks below expect it
    scanResult.sight = sight
end

-- the economy advisor: prices for craft products and materials, a vendor visit, then the Advice view
local adv, advAfterHide, advWide, advTip, advOpened, advKept, advLoaded, advPatched, advNewBuild = nil, nil, nil, nil, false, false, false, false, false
local usualResult = {}
if MODE ~= "bare" then
    local items = DearLordAuctionDB.realms["ClassicBetaPvE2-Horde"].items
    items[4357] = { p = 200, n = 12, d = AH_DAY, name = "Rough Blasting Powder", k = 5, h = AH_DAY .. ":200:220" }
    items[2840] = { p = 60, n = 30, d = AH_DAY, name = "Copper Bar", k = 10, h = AH_DAY .. ":60:65" }
    items[2506] = { p = 10000, n = 2, d = AH_DAY, name = "Hornwood Recurve Bow", h = AH_DAY .. ":10000:12000" }
    world.npc, world.npcFaction, world.merchant = true, "Horde", true
    fire("MERCHANT_SHOW"); advance(1); world.merchant = nil; world.npc = nil
    ns.AdviceDirty(true); advance(1); advance(3)
    adv = ns.Advice()
    advKept = ns.db.sellPrices and ns.db.sellPrices[2140] == 350
    -- an item the client has not loaded yet: asked for, and its price read when it arrives
    world.uncached = { [5000] = true }
    local before = ns.SellPrice(5000)
    world.uncached = nil; fire("ITEM_DATA_LOAD_RESULT", 5000, true)
    advLoaded = before == nil and world.requested and world.requested[5000] and ns.db.sellPrices[5000] == 77
    -- a patch dropped an item's vendor price: the client's own number beats the saved one
    ns.db.sellPrices[5001] = 1535
    advPatched = ns.SellPrice(5001) == 1 and ns.db.sellPrices[5001] == 1
    -- a new game build: the saved prices start over
    ns.db.sellPricesBuild = "12345"; ns.SellPrice(5002)
    advNewBuild = ns.db.sellPricesBuild == "69913" and ns.db.sellPrices[2140] == nil and ns.db.sellPrices[5002] == 5
    ns.OpenPanel("economy"); panelText("Economy / advice")
    for _, f in ipairs(frames) do
        if f.kind == "Frame" and f.shown and rawget(f, "link") == "item:4357" and rawget(f, "tip") then
            GameTooltip.lines = {}; f.scripts.OnEnter(f); advTip = table.concat(GameTooltip.lines, "\n"); f.scripts.OnLeave(f)
        end
    end
    -- a click on a hint opens that item's price page
    for _, f in ipairs(frames) do if f.kind == "Frame" and f.shown and rawget(f, "link") == "item:2506" and rawget(f, "onClick") then f.onClick(); break end end
    for _, f in ipairs(frames) do if f.kind == "Frame" and f.shown and f.left and f.left.text:find("HORNWOOD RECURVE BOW") then advOpened = true end end
    ns.OpenPanel("economy")
    for _, f in ipairs(frames) do if f.kind == "Frame" and f.shown and rawget(f, "link") == "item:2506" and rawget(f, "onRight") then f.onRight(); break end end
    advance(3); advAfterHide = ns.Advice(); advAfterHide.flag = (ns.db.adviceHidden or {})["flip:2506"]
    local uw, uh = UIParent.w, UIParent.h
    UIParent.w, UIParent.h = 2000, 1000; ns.db.panelSize = { w = 1000, h = 700 }; ns.OpenPanel("economy")
    advWide = 0
    for _, f in ipairs(frames) do if f.kind == "Frame" and f.shown and (rawget(f, "colX") or 0) > 0 then advWide = advWide + 1 end end
    panelText("Economy / advice, wide")
    UIParent.w, UIParent.h = uw, uh; ns.db.panelSize = nil
    -- the usual price everywhere: an odd high listing must not promise a craft profit
    local keepH = items[4357].h
    items[4357].h = AH_DAY .. ":200:220 " .. (AH_DAY - 1) .. ":40:45 " .. (AH_DAY - 2) .. ":42:45"
    usualResult = { fair = table.concat({ ns.AuctionFairPrice(4357) }, "/"), vs = (ns.AuctionVsUsual(4357)) }
    ns.AdviceDirty(true); advance(3)
    usualResult.craftGone = true
    for _, e in ipairs(ns.Advice().craft) do if e.id == 4357 then usualResult.craftGone = false end end
    for _, e in ipairs(ns.AuctionSearch("blasting")) do if e.id == 4357 then usualResult.search = e.usual end end
    items[4357].h = keepH; ns.AdviceDirty(true); advance(3)
end

-- census: a player seen twice (levelled in between), then /who riding on key presses
local census = {}
do
    world.mo = { name = "Chuck", className = "Paladin", class = "PALADIN", race = "Tauren", level = 10, guild = "Beans", faction = "Horde" }
    fire("UPDATE_MOUSEOVER_UNIT"); advance(61)
    world.mo.level = 20; fire("UPDATE_MOUSEOVER_UNIT"); world.mo = nil
    local r = DearLordCensusDB.realms[GetNormalizedRealmName and "ClassicBetaPvE2" or "ClassicBetaPvE2"]
    census.chuck = r and r.c.Chuck
    census.countAfterMouseover = r and r.count
    local keys = DearLordStatsCensusKeys
    if C_FriendList then
        local asked = {}
        for _ = 1, 90 do                                  -- press keys while playing; every answer arrives a moment later
            local before = world.whoSent or 0
            keys.scripts.OnKeyDown(keys, "W")
            if (world.whoSent or 0) > before then asked[#asked + 1] = world.lastWho; advance(1); fire("WHO_LIST_UPDATE") end
            advance(16)
        end
        census.asked = asked
        census.lfgShown = LFGWhoFrame.shown
        census.lfgListening = LFGWhoFrame.events.WHO_LIST_UPDATE
        local sent = world.whoSent
        keys.scripts.OnKeyDown(keys, "W"); keys.scripts.OnKeyDown(keys, "W"); keys.scripts.OnKeyDown(keys, "W")
        census.burst = (world.whoSent - sent)                         -- three presses in a row: one query
        sent = world.whoSent
        advance(40); world.combat = true; keys.scripts.OnKeyDown(keys, "W"); census.combat = world.whoSent - sent; world.combat = false
        C_FriendList.SendWho("tauren"); local mine = world.whoSent; advance(20); keys.scripts.OnKeyDown(keys, "W"); census.afterUser = world.whoSent - mine
        census.plan = r.plan["20-20"]
        census.count = r.count
        census.r = r
        fire("ADDON_ACTION_BLOCKED", "DearLordStats", "C_FriendList.SendWho()"); advance(200)
        local b = world.whoSent; keys.scripts.OnKeyDown(keys, "W"); census.afterBlock = world.whoSent - b
    end
    ns.OpenPanel("census"); panelText("Census / classes")
    for _, f in ipairs(frames) do if f.kind == "Button" and f.scopeKey == "races" and f.scripts.OnClick then f.scripts.OnClick(f) end end
    panelText("Census / races")
    for _, f in ipairs(frames) do if f.kind == "Button" and f.scopeKey == "places" and f.scripts.OnClick then f.scripts.OnClick(f) end end
    panelText("Census / guilds and zones")
    for _, f in ipairs(frames) do if f.kind == "Button" and rawget(f, "chipKey") == "Alliance" and f.shown then f.scripts.OnClick(f) end end
    census.allianceText = {}
    for _, f in ipairs(frames) do if f.kind == "Frame" and f.shown and f.left and f.left.text:find("characters") then census.allianceText[#census.allianceText + 1] = strip(f.left.text) end end
    ns.db.censusFilter = nil
end

-- spell lag: an instant spell answers in 250 ms (one clock step); a 3 s cast whose "started" answer never comes must not read as 3 s of lag
local lagBefore = #ns.lag.samples
advance(5)
fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Lag-1", 3044); advance(0.25); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Lag-1", 3044)
advance(5)
fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Lag-2", 19434); advance(3); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Lag-2", 19434)
advance(5)
fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Lag-3", 19434); advance(0.25); fire("UNIT_SPELLCAST_START", "player", "Lag-3", 19434); advance(3); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Lag-3", 19434)
local lagNew = {}
for i = lagBefore + 1, #ns.lag.samples do lagNew[#lagNew + 1] = ns.lag.samples[i].ms end

-- every tab and scope of the report, plus menu, tooltips, clicks
for _, key in ipairs({ "xp", "threat" }) do
    local f = ns.huds[key]
    for _, s in ipairs({ "OnEnter", "OnLeave", "OnDragStart", "OnDragStop" }) do f.scripts[s](f) end
    f.dragged = nil; f.scripts.OnMouseUp(f, "RightButton")
end
if MenuUtil then for _, fn in pairs(MenuUtil.checks) do fn(); fn() end end
ns.OpenPanel("combat"); panelText("Combat / session")
for _, f in ipairs(frames) do if f.kind == "Button" and f.scopeKey == "character" and f.scripts.OnClick then f.scripts.OnClick(f) end end
panelText("Combat / character")
for _, f in ipairs(frames) do if f.kind == "Button" and f.scopeKey == "level" and f.scripts.OnClick then f.scripts.OnClick(f) end end
panelText("Combat / level")
local chips = {}
for _, f in ipairs(frames) do if f.kind == "Button" and f.shown and rawget(f, "chipKey") then chips[#chips + 1] = strip(f.fs.text) end end
for _, f in ipairs(frames) do if f.kind == "Button" and f.shown and rawget(f, "chipKey") == 7 then f.scripts.OnClick(f); break end end
panelText("Combat / level after picking the previous level")
local levelLabel; for _, f in ipairs(frames) do if f.kind == "Button" and f.shown and f.scopeKey == "level" then levelLabel = strip(f.fs.text) end end
ns.OpenPanel("abilities"); panelText("Abilities (level view carried over)")
ns.OpenPanel("professions"); panelText("Professions")
ns.OpenPanel("economy"); panelText("Economy / advice (every mode)")
ns.OpenPanel("loot"); panelText("Loot")
ns.ResetLoot(); ns.OpenPanel("loot"); panelText("Loot after reset")
for _, f in ipairs(frames) do if f.kind == "Button" and f.scopeKey == "history" and f.scripts.OnClick then f.scripts.OnClick(f) end end
panelText("Economy / history")
ns.OpenPanel("settings"); advance(1)
local touched, fontBefore = 0, ns.db.fontSize
for _, f in ipairs(frames) do
    local c = rawget(f, "control")
    if c and not c.header and c.label ~= "Reset every setting to its default" then
        touched = touched + 1
        if f.scripts.OnEnter then f.scripts.OnEnter(f); f.scripts.OnLeave(f) end
        if c.type == "slider" then
            f.scripts.OnMouseWheel(f, 1)
            local tr = rawget(f, "track"); tr.scripts.OnMouseDown(tr); tr.scripts.OnUpdate(tr); tr.scripts.OnMouseUp(tr)
        elseif c.type == "choice" then f.scripts.OnClick(f, "LeftButton"); f.scripts.OnMouseWheel(f, -1)
        else f.scripts.OnClick(f, "LeftButton") end
    end
end
local settingsChanged = ns.db.font ~= "friz" or ns.db.fontSize ~= fontBefore
advance(3); panelText("Settings (labels only)")
for _, f in ipairs(frames) do local c = rawget(f, "control"); if c and c.label == "Reset every setting to its default" then f.scripts.OnClick(f, "LeftButton") end end
local afterReset = ns.db.font == "friz" and ns.db.fontSize == 13 and ns.db.showXP == true and ns.db.alpha == 1
ns.OpenPanel("journal"); panelText("Journal")
ns.OpenPanel("summary"); advance(3); panelText("Summary / current")
local summaryTitle, summaryTiles = false, 0
for _, f in ipairs(frames) do
    if f.kind == "Frame" and f.shown and f.left and strip(f.left.text) == "Tess Ter" then summaryTitle = true end
    local ch = rawget(f, "chart")
    if f.kind == "Frame" and f.shown and ch then for _, l in ipairs(ch.labels) do if l.shown and strip(l.text) == "kills" then summaryTiles = summaryTiles + 1 end end end
end
for _, f in ipairs(frames) do if f.kind == "Button" and f.scopeKey == "all" and f.scripts.OnClick then f.scripts.OnClick(f) end end
panelText("Summary / all characters")
for _, f in ipairs(frames) do if f.kind == "Button" and f.scopeKey == "text" and f.scripts.OnClick then f.scripts.OnClick(f) end end
local summaryBoxText = ""
for _, f in ipairs(frames) do if f.kind == "EditBox" and f.shown and rawget(f, "original") then summaryBoxText = f.original end end
-- resize the report: drag the corner wider/taller, then double-click to fit the content
ns.OpenPanel("professions")
local pf = DearLordStatsPanel
pf.grip.scripts.OnEnter(pf.grip); pf.grip.scripts.OnLeave(pf.grip)
pf.grip.scripts.OnMouseDown(pf.grip, "LeftButton"); pf:SetSize(760, 620); pf.scripts.OnSizeChanged(pf); advance(0.1); pf.scripts.OnSizeChanged(pf)
pf.grip.scripts.OnMouseUp(pf.grip)
local resized = ns.db.panelSize
pf.grip.scripts.OnDoubleClick(pf.grip)
local fitted = ns.db.panelSize
-- a window taller than the screen comes back clamped, and the title-bar button offers fit / default
UIParent.w, UIParent.h = 2000, 1000
ns.db.panelSize = { w = 760, h = 5000 }; ns.OpenPanel("loot")
local clamped = ns.db.panelSize
local fitBtn; for _, f in ipairs(frames) do if f.kind == "Button" and f.fs and f.fs.text == "fit" then fitBtn = f end end
if fitBtn then fitBtn.scripts.OnEnter(fitBtn); fitBtn.scripts.OnLeave(fitBtn); fitBtn.scripts.OnClick(fitBtn, "LeftButton"); fitBtn.scripts.OnClick(fitBtn, "RightButton") end
local afterDefault = ns.db.panelSize
for _, f in ipairs(frames) do      -- exercise every row's hover and right-click, and every button
    if f.scripts.OnEnter and f ~= ns.huds.threat and f ~= ns.huds.xp then pcall(f.scripts.OnEnter, f); if f.scripts.OnLeave then pcall(f.scripts.OnLeave, f) end end
end
for _, cmd in ipairs({ "", "", "levels", "summary", "recap", "recap", "nudges", "nudges", "size 14", "scale 1", "alpha 1", "bg", "bg", "lock", "lock", "errors", "help" }) do
    SlashCmdList["DEARLORDSTATS"](cmd)
end
io.write("\n-- summary (this character)\n" .. ns.SummaryText(false) .. "\n")

-- slow work is reported, with a chat line when it is long enough to feel
printed = {}; ns.noteSlow("test:slow", 312); SlashCmdList["DEARLORDSTATS"]("perf")
local perfSaid, perfListed = false, false
for _, l in ipairs(printed) do if l:find("slow: test:slow took 312 ms", 1, true) then perfSaid = true end; if l:find("test:slow: 1 times", 1, true) then perfListed = true end end
-- a census past its cap is trimmed in one go, at login
local cr = DearLordCensusDB.realms.ClassicBetaPvE2
if cr then for i = 1, 12001 do cr.c["Filler" .. i] = "5,1,1,0,0,2,1400," .. (1400 + i % 10) .. ",1" end; cr.count = 12001 + (cr.count or 0) end

-- reload keeps the session, a fresh login starts a new one
fire("PLAYER_ENTERING_WORLD", false, true); advance(2)
local censusAfterTrim = cr and cr.count
local kept = ns.session.combat.fights
fire("PLAYER_ENTERING_WORLD", true, false); advance(2)

io.write("\n-- chat output\n")
for _, l in ipairs(printed) do io.write("   " .. strip(l) .. "\n") end
io.write("\n-- everything the feed showed, in order\n")
for _, l in ipairs(feedLog) do io.write("   " .. strip(l) .. "\n") end
io.write("\n-- checks\n")
-- client checks: the notes every part left, as one list
local health = {}
if MODE ~= "bare" then
    ns.ReadyList()                                               -- a reload cleared its note: let it look once more
    for _, r in ipairs(ns.HealthRows()) do health[r.name] = r.state .. ": " .. tostring(r.detail) end
    health.summary = ns.HealthSummary()
    printed = {}; SlashCmdList["DEARLORDSTATS"]("check"); health.said = printed[1] or ""
    panelText("Summary / client checks")
    health.rows = 0
    for _, f in ipairs(frames) do if f.kind == "Frame" and f.shown and f.left and f.left.text and f.left.text:find("Threat numbers", 1, true) then health.rows = health.rows + 1 end end
    ns.db.errors = ns.db.errors or {}; table.insert(ns.db.errors, { count = 1, where = "test", msg = "boom" })
    for _, r in ipairs(ns.HealthRows()) do if r.name == "Addon errors" then health.errors = r.state end end
    table.remove(ns.db.errors)
    ns.OpenPanel("combat")
end
-- the shield bar: a readable shield, hits, a break, a hidden amount, hidden buffs, no amount at all, moving it
local shield = {}
if MODE ~= "bare" and not os.getenv("SV") then
    local sf, st = DearLordStats_Shield, ns.shield
    local function pws(instance, left) return { spellId = 17, name = "Power Word: Shield", icon = 135940, expirationTime = GetTime() + 30, duration = 30, points = left and { left } or nil, auraInstanceID = instance } end
    world.combat = false; world.absorb, world.auras = 0, {}
    st.demoUntil = 0; ns.ApplyShield()                           -- the settings page's preview button was clicked earlier
    advance(1); shield.idle = not sf.shown
    world.auras, world.absorb = { pws(501) }, 44
    fire("UNIT_AURA", "player"); advance(0.5)
    shield.up = sf.shown and st.mode == "amount" and st.max == 44 and sf.amount.text == "44" and sf.full.text == "/ 44"
    shield.time = sf.time.text
    world.absorb = 20; fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    shield.hit = st.amount == 20 and st.flash > 0 and sf.amount.text == "20" and st.max == 44
    ns.db.shieldText = "percent"; ns.ApplyShield(); shield.percent = sf.amount.text
    ns.db.shieldText = "both"; ns.ApplyShield()
    world.absorb, world.auras = 0, {}; fire("UNIT_AURA", "player")
    shield.broken = st.goneKind == "broken" and sf.shown
    advance(2); shield.gone = not sf.shown
    shield.learned = ns.db.shieldLearned[17]
    -- in a fight the amount is hidden: the bar still shows, against the 44 learned above
    world.combat = true; world.auras, world.absorb = { pws(502) }, 44
    fire("UNIT_AURA", "player"); advance(0.5)
    shield.hidden = sf.shown and st.mode == "hidden" and st.max == 44 and st.maxKind == "learned" and sf.full.text == "/ 44"
    world.aurasHidden = true; fire("UNIT_AURA", "player"); advance(0.5)
    shield.byId = sf.shown and st.aura ~= nil and st.aura.how == "byid" and st.aura.id == 17
    -- no answer by spell id either: the shield is followed by its clock until the game says the buff is gone
    local byId = C_UnitAuras.GetPlayerAuraBySpellID
    C_UnitAuras.GetPlayerAuraBySpellID = function() return nil end
    fire("UNIT_AURA", "player"); advance(0.5)
    local blindShown = sf.shown and st.present
    fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 502 } }); advance(0.25)
    shield.blind = blindShown and not st.present and st.goneKind == "broken"
    C_UnitAuras.GetPlayerAuraBySpellID = byId
    world.aurasHidden = nil; world.combat = false
    world.auras = { pws(504) }; fire("UNIT_AURA", "player"); advance(0.5)
    advance(31); world.auras, world.absorb = {}, 0; fire("UNIT_AURA", "player")
    shield.faded = st.goneKind == "faded"
    advance(2)
    -- met half used (the bar was not there when it landed): measured against what such a shield holds, not what is left
    local half = pws(505); half.expirationTime = GetTime() + 12
    world.auras, world.absorb = { half }, 30; fire("UNIT_AURA", "player"); advance(0.5)
    shield.half = sf.amount.text == "30" and sf.full.text == "/ 44"
    world.auras, world.absorb = {}, 0; fire("UNIT_AURA", "player"); advance(2)
    -- a fight that hides the amount and every buff: a shield from before is kept, and reads 30 / 44 again afterwards
    local askById = C_UnitAuras.GetPlayerAuraBySpellID
    C_UnitAuras.GetPlayerAuraBySpellID = function() return nil end
    world.auras, world.absorb = { pws(506) }, 44; fire("UNIT_AURA", "player"); advance(0.5)
    world.combat, world.aurasHidden, world.absorb = true, true, 30; fire("UNIT_ABSORB_AMOUNT_CHANGED", "player"); advance(0.5)
    shield.kept = sf.shown and st.mode == "hidden" and st.max == 44 and st.maxKind == "seen" and issecretvalue(sf.presence.value)
    world.combat, world.aurasHidden = false, nil; fire("UNIT_AURA", "player"); advance(0.5)
    shield.after = st.mode == "amount" and sf.amount.text == "30" and sf.full.text == "/ 44"
    world.auras, world.absorb = {}, 0; fire("UNIT_AURA", "player"); advance(2)
    -- cast in the fight itself: your own cast says which shield it is (not one cast on somebody else)
    world.combat, world.aurasHidden = true, true; world.auras, world.absorb = { pws(507) }, 44
    fire("UNIT_AURA", "player"); advance(0.5)
    local unseen = not sf.shown
    fire("UNIT_SPELLCAST_SENT", "player", "Other One", "cast-1", 17); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 17); advance(0.5)
    local other = not sf.shown
    fire("UNIT_SPELLCAST_SENT", "player", UnitName("player"), "cast-2", 17); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 17); advance(0.5)
    shield.cast = unseen and other and sf.shown and st.mode == "hidden" and st.aura.how == "cast" and st.max == 44 and st.maxKind == "learned" and sf.time.text ~= ""
    -- the fight ends with nothing left: the bar goes without a farewell
    world.combat, world.aurasHidden = false, nil; world.auras, world.absorb = {}, 0; fire("UNIT_AURA", "player")
    shield.silent = not sf.shown and st.goneKind == nil
    advance(1)
    -- somebody else's shield in a fight: all that is known is that the amount changed. The bar is kept ready,
    -- measured against your health, and the game draws it or not from the hidden amount.
    ns.char.lastShield = nil                                    -- a character that never had a shield
    world.combat, world.aurasHidden = true, true; world.auras, world.absorb = { pws(508) }, 44
    fire("UNIT_ABSORB_AMOUNT_CHANGED", "player"); advance(0.5)
    shield.standby = sf.shown and st.mode == "hidden" and st.maxKind == "health" and st.max == 175 and issecretvalue(sf.presence.value) and sf.full.text == ""
    world.combat, world.aurasHidden = false, nil; world.auras, world.absorb = {}, 0; fire("UNIT_AURA", "player"); advance(1)
    C_UnitAuras.GetPlayerAuraBySpellID = askById
    shield.trace = #(ns.db.diag.shield.trace or {})
    -- this client as it is: the amount hidden at every moment, the buff saying what is left while buffs can be
    -- read, and no buffs at all in a fight
    world.absorbHidden = true
    world.auras = { pws(520, 44) }; fire("UNIT_AURA", "player"); advance(0.5)
    local full = st.mode == "amount" and sf.amount.text == "44" and sf.full.text == "/ 44"
    world.auras[1].points = { 36 }; fire("UNIT_AURA", "player"); advance(0.25)
    shield.fromBuff = full and st.mode == "amount" and sf.amount.text == "36" and sf.full.text == "/ 44" and st.max == 44
    world.combat, world.aurasBlank = true, true; fire("UNIT_ABSORB_AMOUNT_CHANGED", "player"); advance(0.5)
    shield.intoFight = sf.shown and st.mode == "hidden" and st.max == 44 and st.maxKind == "seen" and sf.full.text == "/ 44" and sf.time.text ~= ""
    world.combat, world.aurasBlank = false, nil; world.auras = {}; fire("UNIT_AURA", "player"); advance(1)
    local calm = not sf.shown
    -- a shield landing in the next fight, its cast unreadable: taken for the kind this character had last
    world.combat, world.aurasBlank = true, true; world.auras = { pws(521, 44) }; fire("UNIT_AURA", "player"); advance(0.5)
    local waiting = not sf.shown
    fire("UNIT_ABSORB_AMOUNT_CHANGED", "player"); advance(0.5)
    shield.guess = calm and waiting and sf.shown and st.mode == "hidden" and st.aura.how == "guess" and st.max == 44 and sf.full.text == "/ 44" and sf.time.text == ""
    world.combat, world.aurasBlank = false, nil; world.auras = {}; fire("UNIT_AURA", "player"); advance(1)
    world.absorbHidden = nil
    -- a client that gives no amount: the bar shows the time left
    world.auras = { pws(503) }; fire("UNIT_AURA", "player"); advance(0.5)
    shield.timer = sf.shown and st.mode == "timer" and sf.amount.text == "~44"
    ns.db.shieldBar = false; ns.ApplyShield(); shield.off = not sf.shown
    ns.db.shieldBar = true; world.auras = {}; ns.ApplyShield(); advance(2)
    -- Edit Mode: the bar shows itself with its preview, can be dragged, and remembers where
    EventRegistry:TriggerEvent("EditMode.Enter"); advance(0.5)
    shield.edit = sf.shown and sf.mover.shown and st.mode == "amount" and st.max == 480
    sf.scripts.OnDragStart(sf); sf.scripts.OnDragStop(sf)
    shield.moved = ns.db.shieldPos.point == "TOP" and ns.db.shieldPos.y == -12
    advance(4.5); shield.editBroken = st.goneKind == "broken" and sf.shown
    EventRegistry:TriggerEvent("EditMode.Exit"); advance(0.5)
    shield.editOff = not sf.shown and not sf.mover.shown
    sf.scripts.OnDragStart(sf); shield.fixed = st.dragging == nil
    SlashCmdList["DEARLORDSTATS"]("shield"); advance(1); shield.preview = sf.shown and sf.mover.shown
    advance(21); shield.previewOver = not sf.shown
    for _, r in ipairs(ns.HealthRows()) do if r.name == "Shield bar" then shield.health = r.state .. ": " .. r.detail end end
    shield.note = ns.db.diag.shield.calm
    -- a refused action that is not /who is logged, and leaves the census alone
    local keep = ns.db.diag.census.blocked
    ns.db.diag.census.blocked = nil
    fire("ADDON_ACTION_BLOCKED", "DearLordStats", "CompactPartyFrame:Show()")
    shield.refused = ns.db.diag.blocked["CompactPartyFrame:Show()"] ~= nil and ns.db.diag.blocked["CompactPartyFrame:Show()"].n == 1 and ns.db.diag.census.blocked == nil
    for _, r in ipairs(ns.HealthRows()) do if r.name == "Refused actions" then shield.refusedRow = r.state end end
    ns.db.diag.census.blocked = keep
end

-- Windfury (shaman): procs read from hits landing together, ranked, counted in the fight summary
local wfT = {}
if MODE ~= "bare" then
    local function feedLine(key) for _, row in ipairs(ns.feed.rows) do if row.shown and row.key == key then return strip(row.text.text), row end end end
    local function together(list)
        for _, h in ipairs(list) do fire("UNIT_COMBAT", "target", h[1], h[2] or "", h[3], h[4] or 1) end
        advance(0.5)
    end
    local function procs() return ns.char.windfury and ns.char.windfury.procs or 0 end
    local three = { { "WOUND", "", 40 }, { "WOUND", "", 40 }, { "WOUND", "", 40 } }
    local keepClass, keepRecap = ns.char.classFile, ns.db.showRecap
    -- the fights below are only for Windfury: everything the earlier fights added up is put back afterwards
    local function copy(v) if type(v) ~= "table" then return v end; local o = {}; for k, x in pairs(v) do o[k] = copy(x) end; return o end
    local function putBack(into, from) for k in pairs(into) do into[k] = nil end; for k, x in pairs(from) do into[k] = copy(x) end end
    local keepChar, keepSession, keepLast = copy(ns.char), copy(ns.session), ns.lastFight
    local keepFights, keepMeter, keepWorld = ns.db.diag.fights, ns.db.diag.fightsFromMeter, { world.hp, world.mana, world.targetLevel, world.targetName }
    SPELLS[8232], SPELLS[8017] = "Windfury Weapon", "Rockbiter Weapon"
    ns.db.showRecap = true
    advance(10)                                                  -- earlier lines fade
    -- not a shaman: nothing, whatever lands
    world.enchant = { true, 1000, 0, 283, false, 0, 0, 0 }; advance(2.5)
    together(three); wfT.hunter = feedLine("windfury") == nil and procs() == 0 and ns.WindfuryView() == nil
    ns.char.classFile = "SHAMAN"; ns.char.windfury, ns.session.windfury = nil, nil; advance(2.5)
    -- two hits together are a swing and a strike: no proc
    together({ { "WOUND", "", 100 }, { "WOUND", "", 120 } }); wfT.two = feedLine("windfury") == nil and procs() == 0
    -- three together: a proc; the first ever is #1
    together({ { "WOUND", "", 100 }, { "WOUND", "CRITICAL", 220 }, { "WOUND", "", 130 } })
    local line, row = feedLine("windfury"); wfT.first, wfT.flash = line or "-", row ~= nil and row.flashLeft ~= nil and row.flash.alpha > 0.34
    wfT.seen = row ~= nil and row.hold == 15 and row.big == 6 and row.h == ns.db.fontSize + 10 and row.pulse == true
    advance(3); wfT.glow = row ~= nil and row.shown and row.flashLeft == nil and row.flash.alpha > 0.15 and row.flash.alpha <= 0.34
    together({ { "WOUND", "", 90 }, { "MISS", "", nil }, { "WOUND", "", 110 } }); wfT.second = feedLine("windfury") or "-"
    together({ { "WOUND", "", 50 }, { "WOUND", "", 50 }, { "WOUND", "", 50 } }); wfT.third = feedLine("windfury") or "-"
    together({ { "WOUND", "", 40 }, { "WOUND", "", 40 }, { "WOUND", "", 40 } }); wfT.fourth = feedLine("windfury") or "-"
    wfT.calm = select(2, feedLine("windfury")).pulse ~= true
    ns.db.windfuryHold, ns.db.windfuryBig = 30, 0
    together({ { "WOUND", "", 100 }, { "WOUND", "", 100 }, { "WOUND", "", 100 } }); wfT.fifth = feedLine("windfury") or "-"
    do local r = select(2, feedLine("windfury")); wfT.sized = r.hold == 30 and r.big == 0 and r.h == ns.db.fontSize + 4 end
    ns.db.windfuryHold, ns.db.windfuryBig = 15, 6
    local w = ns.char.windfury
    wfT.kept = w.procs == 5 and #w.ranks == 5 and w.ranks[1] == 450 and w.ranks[2] == 300 and w.ranks[5] == 120
        and w.top[1].total == 450 and w.top[1].crits == 1 and w.hit.amount == 220 and w.hit.crit == true and ns.session.windfury.procs == 5
    -- the launch client hides every hit's amount: the game writes the numbers into the line, nothing is rated
    do
        local ranksBefore = #w.ranks
        together({ { "WOUND", "", secret(212) }, { "WOUND", "CRITICAL", secret(498) }, { "WOUND", "", secret(240) } })
        local hl, hrow = feedLine("windfury")
        wfT.hidden = hl or "-"
        wfT.hiddenKept = w.procs == 6 and #w.ranks == ranksBefore and hrow ~= nil and hrow.text.secretText == true and hrow:GetWidth() >= 340
        advance(1); wfT.hiddenQuiet = #(ns.db.errors or {})
        w.procs, ns.session.windfury.procs = 5, 5
    end
    -- a shock landing with the swing is not melee: no proc
    together({ { "WOUND", "", 100 }, { "WOUND", "", 60, 8 }, { "WOUND", "", 60, 8 } }); wfT.spell = procs() == 5
    -- hits spread over a second are swings, not a proc
    for _ = 1, 3 do fire("UNIT_COMBAT", "target", "WOUND", "", 80, 1); advance(0.75) end
    wfT.spread = procs() == 5
    -- Rockbiter on the weapon, or nothing on it: no proc
    world.enchant = { true, 1000, 0, 29, false, 0, 0, 0 }; advance(2.5); together(three); wfT.rockbiter = procs() == 5
    world.enchant = { false, 0, 0, 0, false, 0, 0, 0 }; advance(2.5); together(three); wfT.bare = procs() == 5
    -- an enchant nothing is known about counts; the damage meter then says there was no Windfury, and it is learned
    world.enchant = { true, 1000, 0, 9001, false, 0, 0, 0 }; advance(2.5)
    runFight({ name = "Test Boar", kills = 0, dmg = 300, taken = 10, duration = 6, spells = { { 6603, 300 } }, during = function() together(three) end })
    wfT.unknownCounted, wfT.learnedNot = procs() == 6, ns.db.wfEnchants[9001] == false
    together(three); wfT.unknownQuiet = procs() == 6
    -- another unknown enchant, and this time the meter lists Windfury: learned, and the fight summary counts the procs
    world.enchant = { true, 1000, 0, 9002, false, 0, 0, 0 }; advance(2.5)
    runFight({ name = "Test Boar", kills = 0, dmg = 500, taken = 10, duration = 6, spells = { { 6603, 200 }, { 8232, 300 } },
        during = function() together({ { "WOUND", "", 100 }, { "WOUND", "", 150 }, { "WOUND", "", 150 } }) end })
    wfT.learned, wfT.recap, wfT.fightLine = ns.db.wfEnchants[9002] == true, feedLine("recap") or "-", feedLine("windfury") or "-"
    wfT.fightKept = ns.char.windfury.fights.n == 1 and ns.char.windfury.fights.ranks[1] == 300 and ns.char.windfury.fights.top[1].procs == 1
    -- a fight with Windfury damage in the meter and no proc seen is counted as missed
    runFight({ name = "Test Boar", kills = 0, dmg = 500, taken = 10, duration = 6, spells = { { 6603, 200 }, { 8232, 300 } } })
    wfT.fightLine2 = feedLine("windfury") or "-"                 -- no proc seen, and the meter still gives the damage: rated all the same
    -- a smaller fight in a group: rated below, and the proc count (a guess there) is left out
    local keepParty = world.party; world.party = world.party or {}
    runFight({ name = "Test Boar", kills = 0, dmg = 500, taken = 10, duration = 6, spells = { { 6603, 400 }, { 8232, 100 } }, during = function() together(three) end })
    world.party = keepParty
    wfT.fightLine3 = feedLine("windfury") or "-"
    local fd = ns.db.diag.windfury.fights
    wfT.fights = fd.agree == 2 and fd.missed == 1 and fd.extra == 1
    -- alone and in a group are counted apart: the solo fights, the hits whose amount could be read, the lines the game wrote
    do
        local wd, a = ns.db.diag.windfury, ns.db.diag.windfury.amounts or {}
        wfT.apart = fd.solo ~= nil and fd.solo.agree == 1 and fd.solo.missed == 1 and fd.solo.extra == 1 and type(fd.lastSolo) == "string"
            and (a.soloRead or 0) > 0 and (a.soloHidden or 0) == 3 and (a.groupRead or 0) >= 3 and (a.groupHidden or 0) == 0 and #wd.solo > 0 and #wd.solo <= 12
            and #wd.samples == 1 and wd.samples[1]:find("group=true", 1, true) ~= nil and wd.solo[1]:find("group=false", 1, true) ~= nil
            and (ns.db.diag.feedFmt or {}).written == 1
        wfT.apartSay = "solo read " .. tostring(a.soloRead) .. " hidden " .. tostring(a.soloHidden) .. ", group read " .. tostring(a.groupRead)
            .. ", solo fights " .. tostring(fd.solo and (fd.solo.agree .. "/" .. fd.solo.missed .. "/" .. fd.solo.extra)) .. ", samples " .. #wd.solo .. "+" .. #wd.samples
            .. ", written " .. tostring((ns.db.diag.feedFmt or {}).written)
        world.class = "Shaman"
        for _, r in ipairs(ns.HealthRows()) do if r.name == "Windfury hit amounts" then wfT.amountsRow = r.state .. ": " .. r.detail end end
        world.class = nil
    end
    world.class = "Shaman"
    for _, r in ipairs(ns.HealthRows()) do if r.name == "Windfury procs" then wfT.health = r.state end end
    world.class = nil
    -- the shaman's own imbue cast teaches the enchant it puts on
    world.enchant = { true, 1000, 0, 9003, false, 0, 0, 0 }
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-wf", 8017); advance(1.5)
    wfT.castNot = ns.db.wfEnchants[9003] == false
    world.enchant = { true, 1000, 0, 9004, false, 0, 0, 0 }
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-wf", 8232); advance(1.5)
    wfT.castIs = ns.db.wfEnchants[9004] == true
    -- the setting switches it off
    local before = procs()
    ns.db.windfury = false; together(three); wfT.off = procs() == before; ns.db.windfury = true
    -- the slash command lists the biggest, and the preview shows made-up procs without keeping them
    printed = {}; SlashCmdList["DEARLORDSTATS"]("windfury"); wfT.say = printed[1] or ""; wfT.sayAll = table.concat(printed, " / ")
    before = procs()
    advance(8); SlashCmdList["DEARLORDSTATS"]("windfury test"); advance(1); wfT.preview1 = feedLine("windfury") or "-"
    advance(4); wfT.preview2 = feedLine("windfury") or "-"
    advance(4); wfT.preview3 = feedLine("windfury") or "-"
    advance(12); wfT.previewKept = procs() == before and ns.char.windfury.fights.n == 3
    world.enchant = nil
    putBack(ns.char, keepChar); putBack(ns.session, keepSession)
    ns.lastFight, ns.db.diag.fights, ns.db.diag.fightsFromMeter, ns.db.showRecap = keepLast, keepFights, keepMeter, keepRecap
    world.hp, world.mana, world.targetLevel, world.targetName = keepWorld[1], keepWorld[2], keepWorld[3], keepWorld[4]
    ns.char.classFile = keepClass
end
-- the damage meter ----------------------------------------------------------------------
local mT = {}
if MODE ~= "bare" then
    local mw = ns.huds.meter
    local function copy(v) if type(v) ~= "table" then return v end; local o = {}; for k, x in pairs(v) do o[k] = copy(x) end; return o end
    local function putBack(into, from) for k in pairs(into) do into[k] = nil end; for k, x in pairs(from) do into[k] = copy(x) end end
    local keepChar, keepSession, keepLast = copy(ns.char), copy(ns.session), ns.lastFight
    local keepFights, keepMeter, keepWorld = ns.db.diag.fights, ns.db.diag.fightsFromMeter, { world.hp, world.mana, world.targetLevel, world.targetName }
    local keepParty, keepRecap = world.party, ns.db.showRecap
    ns.db.showRecap = false
    local function rows(ci)
        local c, out = mw.cols[ci], {}
        if not (mw.shown and c.shown) then return "-" end
        for i = 1, c.list.count do
            local r = c.list:Row(i)
            local cells = {}
            for k = 1, 3 do if r.cells[k].shown and r.cells[k].text ~= "" then cells[#cells + 1] = strip(r.cells[k].text) end end
            out[#out + 1] = strip(r.rank.text) .. " " .. strip(r.name.text) .. " " .. table.concat(cells, " ")
        end
        return table.concat(out, " | ")
    end
    local function rowOf(ci, name)
        local c = mw.cols[ci]
        for i = 1, c.list.count do local r = c.list:Row(i); if strip(r.name.text) == name then return r end end
    end
    local function tipRows()
        local t, out = ns.meterTip, {}
        if not (t and t.shown) then return "-" end
        for i = 1, t.list.count do
            local r = t.list:Row(i)
            local cells = {}
            for k = 1, 3 do if r.cells[k].shown and r.cells[k].text ~= "" then cells[#cells + 1] = strip(r.cells[k].text) end end
            out[#out + 1] = strip(r.name.text) .. " " .. table.concat(cells, " ")
        end
        return table.concat(out, " | ") .. (t.note.shown and (" // " .. t.note.text) or "")
    end
    mT.loginResets = dmResets
    fire("PLAYER_ENTERING_WORLD", false, true); advance(1); mT.reloadNoReset = dmResets == mT.loginResets     -- a /reload keeps Total
    mT.startShown = mw.shown

    -- the preview: made-up players, sorted, both columns
    SlashCmdList["DEARLORDSTATS"]("meter test"); advance(3)
    mT.preview1, mT.preview2 = rows(1), rows(2)
    do
        local a, b = mw.cols[1].list:Row(1), mw.cols[1].list:Row(2)
        mT.previewSorted = a ~= nil and b ~= nil and a.bar.value >= b.bar.value and a.bar.eased == true
        mw.cols[1].list.onEnter(a.item, a); mT.previewTip = tipRows(); mw.cols[1].list.onLeave()
    end
    advance(21); mT.previewOver = ns.meter.demoUntil < now

    -- a fight in a party of three: during it every number is hidden, the bars still fill and the game's order is kept
    world.party = { party1 = { name = "Tankard", class = "Warrior" }, party2 = { name = "Healbot", class = "Priest" } }
    local others = {
        { name = "Tankard", guid = "Player-1-TANK", class = "WARRIOR", dmg = 300, taken = 400, interrupts = 2, dmgSpells = { { 6603, 200 }, { 2973, 100 } } },
        { name = "Healbot", guid = "Player-1-HEAL", class = "PRIEST", dmg = 40, healed = 520, taken = 30, dmgSpells = { { 6603, 40 } }, healedSpells = { { 2050, 520 } } },
    }
    SPELLS[2050], SPELLS[8190], SPELLS[2139] = "Lesser Heal", "Magma Totem", "Counterspell"
    local fightOpts = { exact = true, name = "Test Ogre", kills = 0, dmg = 600, taken = 80, healed = 60, duration = 20, others = others, interrupts = 1,
        spells = { { 75, 350 }, { 3044, 150 }, { 17253, 70, "Joy" }, { 8190, 30, "Magma Totem" } }, healedSpells = { { 2050, 60 } },
        takenSpells = { { 6603, 80, "Test Ogre" } }, interruptsSpells = { { 2139, 1 } }, enemySpells = { { 75, 350, nil, "Tess Ter" }, { 6603, 200, nil, "Tankard" } } }
    fightOpts.during = function()
        advance(0.5)
        mT.live1, mT.live2 = rows(1), rows(2)
        local r1 = mw.cols[1].list:Row(1)
        mT.liveHidden = r1 ~= nil and issecretvalue(r1.bar.value) and issecretvalue(r1.bar.max) and r1.name.secretText == true and r1.cells[1].secretText == true
            and r1.cells[2].secretText == true and r1.spark.shown == true
        mT.liveTitle = strip(mw.titleTime.text)
        -- the breakdown: your own row works in a fight; another player's only if the game takes the hidden id
        local mine, other
        for i = 1, mw.cols[1].list.count do local r = mw.cols[1].list:Row(i); if r.item.own then mine = r else other = other or r end end
        if mine then mw.cols[1].list.onEnter(mine.item, mine); mT.liveTipOwn = tipRows() end
        if other then mw.cols[1].list.onEnter(other.item, other); mT.liveTipOther = tipRows() end
        world.hiddenGuidOk = true
        if other then mw.cols[1].list.onEnter(other.item, other); mT.liveTipOtherOk = tipRows() end
        world.hiddenGuidOk = nil
        mw.cols[1].list.onLeave()
        mT.liveReport = select(2, ns.MeterReport())
    end
    runFight(fightOpts)
    mT.after1, mT.after2 = rows(1), rows(2)
    mT.afterTitle = strip(mw.titleName.text) .. " " .. strip(mw.titleTime.text)
    mT.afterSum = strip(mw.cols[1].sum.text)
    mT.afterPlain = mw.cols[1].list:Row(1) ~= nil and mw.cols[1].list:Row(1).name.secretText == nil and mw.cols[1].list:Row(1).spark.shown == false
    do
        local r = rowOf(1, "Tess Ter"); mw.cols[1].list.onEnter(r.item, r); mT.tipOwn = tipRows()
        local t = ns.meterTip
        mT.tipTargets = t.targetsHead.shown and (strip(t.targets[1].name.text) .. " " .. strip(t.targets[1].value.text)) or "-"
        r = rowOf(1, "Tankard"); mw.cols[1].list.onEnter(r.item, r); mT.tipOther = tipRows()
        r = rowOf(2, "Healbot"); mw.cols[2].list.onEnter(r.item, r); mT.tipHeal = tipRows()
        mw.cols[1].list.onLeave(); mT.tipGone = ns.meterTip.shown == false
    end

    -- copy: lines for chat, all inside the click; a refusal opens the text box instead
    mT.report = table.concat(ns.MeterReport(2) or {}, " / ")
    chatSent = {}
    mw.buttons.copy.scripts.OnClick(mw.buttons.copy, "LeftButton")
    mT.menu = (MenuUtil.buttons["Say"] and "say " or "") .. (MenuUtil.buttons["Party"] and "party " or "") .. (MenuUtil.buttons["Open as text to copy"] and "box" or "")
    MenuUtil.buttons["Party"](); advance(4)
    mT.chat = #chatSent .. " lines to " .. tostring(chatSent[1] and chatSent[1].channel) .. ": " .. tostring(chatSent[1] and chatSent[1].msg) .. " / " .. tostring(chatSent[2] and chatSent[2].msg)
    world.chatRefuse = true; chatSent = {}
    ns.MeterSend("PARTY"); advance(4)
    world.chatRefuse = nil
    mT.refused = #chatSent == 0 and ns.copyBox ~= nil and ns.copyBox.shown and ns.copyBox.box.text:find("1. Tess Ter  600", 1, true) ~= nil
    if ns.copyBox then ns.copyBox:Hide() end
    MenuUtil.buttons["Open as text to copy"](); mT.box = ns.copyBox.shown and ns.copyBox.box.text or "-"
    ns.copyBox:Hide()

    -- a second fight, then Total adds the two up; Fight stays on the last one
    runFight({ name = "Test Wolf", kills = 0, dmg = 100, taken = 10, duration = 10, others = { { name = "Tankard", guid = "Player-1-TANK", class = "WARRIOR", dmg = 500 } } })
    mT.fight2 = rows(1)
    mw.tabTotal.scripts.OnClick(mw.tabTotal, "LeftButton"); mT.total = rows(1); mT.totalTitle = strip(mw.titleName.text) .. " " .. strip(mw.titleTime.text)
    -- earlier fights: right-click on Fight lists them, a new fight comes back to the running one
    mw.tabFight.scripts.OnClick(mw.tabFight, "RightButton")
    local pick; for text, fn in pairs(MenuUtil.buttons) do if text:find("^Test Ogre") then pick = fn; mT.earlierLabel = text end end
    if pick then pick() end
    mT.earlier, mT.earlierTab = rows(1), strip(mw.tabFight.text.text)
    runFight({ name = "Test Rat", kills = 0, dmg = 50, taken = 5, duration = 5 })
    mT.backToFight = ns.meter.seg == "fight" and rows(1) or "-"
    mw.tabFight.scripts.OnClick(mw.tabFight, "RightButton")
    for text, fn in pairs(MenuUtil.buttons) do if text:find("^Test Ogre") then fn() end end

    -- a client whose "current" session is empty after the fight: the last fight is read by its id
    mw.tabFight.scripts.OnClick(mw.tabFight, "LeftButton")
    world.currentEmpty = true; advance(3)
    mT.byId = rows(1) .. " // " .. strip(mw.titleName.text) .. " " .. strip(mw.titleTime.text) .. " // " .. tostring(ns.meter.seg) .. " " .. type(ns.meter.use)
    world.currentEmpty = nil; advance(3)

    -- the meter's own fight clock: the game keeps this fight open 3 s after combat ends. The per-second
    -- numbers use the 17 s in combat, and the bars wait while the game still hides the final numbers
    local function totalOver()                                     -- Total's time in the title, against the game's own
        mw.tabTotal.scripts.OnClick(mw.tabTotal, "LeftButton")
        local m, sec = strip(mw.titleTime.text):match("(%d+):(%d+)")
        mw.tabFight.scripts.OnClick(mw.tabFight, "LeftButton")
        return (m * 60 + sec) - C_DamageMeter.GetSessionDurationSeconds(0)
    end
    local over0 = totalOver()
    runFight({ name = "Test Tail", kills = 0, dmg = 170, taken = 5, duration = 17, tail = 3, spells = { { 75, 170 } },
        linger = function()
            advance(1)
            mT.clockFrozen = rows(1) .. " // " .. strip(mw.titleTime.text)
        end })
    mT.clockRow = rows(1) .. " // " .. strip(mw.titleName.text) .. " " .. strip(mw.titleTime.text) .. " // " .. strip(mw.cols[1].sum.text)
    do local r = rowOf(1, "Tess Ter"); mw.cols[1].list.onEnter(r.item, r); mT.clockTip = tipRows(); mw.cols[1].list.onLeave() end
    mT.clockReport = table.concat(ns.MeterReport(1) or {}, " / ")
    mw.tabFight.scripts.OnClick(mw.tabFight, "RightButton")
    for text in pairs(MenuUtil.buttons) do if text:find("^Test Tail") then mT.clockMenu = text end end
    mT.clockTotal = totalOver() - over0
    -- a fight the game timed very differently (joined late, or it ran on): the game's clock is used
    runFight({ name = "Test Long", kills = 0, dmg = 100, taken = 5, duration = 10, tail = 30, spells = { { 75, 100 } } })
    mT.clockFar = rows(1) .. " // " .. strip(mw.titleTime.text)
    mT.clockDiag = table.concat(ns.db.diag.meter.clock or {}, " | ")

    mw.tabFight.scripts.OnClick(mw.tabFight, "RightButton")
    for text, fn in pairs(MenuUtil.buttons) do if text:find("^Test Ogre") then fn() end end

    -- other views, and the second column switched off
    ns.db.meterViewL, ns.db.meterViewR = "taken", "interrupts"; mw:Layout()
    mT.taken, mT.interrupts = rows(1), rows(2)
    do local r = rowOf(1, "Tess Ter"); mw.cols[1].list.onEnter(r.item, r); mT.tipTaken = tipRows(); mw.cols[1].list.onLeave() end
    ns.db.meterViewL = "enemies"; mw:Layout(); mT.enemies = rows(1)
    do local r = mw.cols[1].list:Row(1); mw.cols[1].list.onEnter(r.item, r); mT.tipEnemy = tipRows(); mw.cols[1].list.onLeave() end
    ns.db.meterViewL, ns.db.meterViewR = "damage", "healing"
    local wide = mw.cols[1].list.width
    mw.buttons.cols.scripts.OnClick(mw.buttons.cols, "LeftButton")
    mT.oneCol = ns.db.meterSecond == false and mw.cols[2].shown == false and mw.cols[2].list.frame.shown == false and mw.cols[1].list.width > wide * 1.8
    mT.oneColRows = rows(1)
    mw.buttons.cols.scripts.OnClick(mw.buttons.cols, "LeftButton")
    mT.twoCol = ns.db.meterSecond == true and mw.cols[2].shown == true
    ns.db.meterNumbers = "rate"; mw:Layout(); mT.rateOnly = rows(1)
    ns.db.meterNumbers = "all"; mw:Layout()
    -- a column too narrow for everything: the per-second number loses its "/s" before the share goes
    do
        local w = ns.db.meterW
        ns.db.meterW = 530; ns.ApplyHudSettings(); mT.narrow = rows(1)
        ns.db.meterW = 480; ns.ApplyHudSettings(); mT.narrower = rows(1)
        ns.db.meterW = w; ns.ApplyHudSettings()
    end

    -- resize by the corner: kept, and more rows fit; locked windows do not size
    local before = ns.meter.visible
    mw.grip.scripts.OnMouseDown(mw.grip, "LeftButton"); mw:SetSize(600, 300); mw.grip.scripts.OnMouseUp(mw.grip)
    mT.resized = ns.db.meterW == 600 and ns.db.meterH == 300 and ns.meter.visible > before
    ns.ApplyHudSettings(); mT.resizeKept = mw.w == 600 and mw.h == 300
    ns.db.locked = true
    mw.grip.scripts.OnMouseDown(mw.grip, "LeftButton"); mw:SetSize(700, 400); mw.grip.scripts.OnMouseUp(mw.grip)
    mT.lockedSize = ns.db.meterW == 600
    ns.db.locked = false
    ns.ResetLayout(); mT.resetSize = ns.db.meterW == ns.defaults.meterW and mw.w == ns.defaults.meterW

    -- scrolling, with your own row kept in view
    ns.db.meterBarHeight = 30; mw:SetSize(520, 110); mw.grip.scripts.OnMouseDown(mw.grip, "LeftButton"); mw.grip.scripts.OnMouseUp(mw.grip)
    mw.tabTotal.scripts.OnClick(mw.tabTotal, "LeftButton")
    mT.fewVisible, mT.fewRows = ns.meter.visible, rows(1)
    mw.scripts.OnMouseWheel(mw, -1); mT.scrolled = rows(1)
    mw.scripts.OnMouseWheel(mw, 1)
    ns.db.meterBarHeight = 18; ns.ResetLayout()

    -- client checks, the close button, hiding when idle, reset
    world.class = nil
    for _, r in ipairs(ns.HealthRows()) do if r.name == "Damage meter" then mT.health = r.state .. ": " .. r.detail end end
    world.meterCVar = "0"
    for _, r in ipairs(ns.HealthRows()) do if r.name == "Damage meter" then mT.healthOff = r.state end end
    world.meterCVar = nil
    mw.buttons.close.scripts.OnClick(mw.buttons.close, "LeftButton"); mT.closed = mw.shown == false and ns.db.showMeter == false
    SlashCmdList["DEARLORDSTATS"]("meter"); mT.reopened = mw.shown == true and ns.db.showMeter == true
    ns.db.meterHideIdle = true; advance(25); mT.idleHidden = mw.shown == false
    ns.db.meterHideIdle = false; advance(1); mT.idleBack = mw.shown == true
    local resetsBefore = dmResets
    mw.buttons.reset.scripts.OnClick(mw.buttons.reset, "LeftButton"); advance(1)
    mT.reset = dmResets == resetsBefore + 1 and mw.cols[1].list.count == 0 and mw.cols[1].empty.shown and strip(mw.cols[1].empty.text) or "-"
    mT.clockWiped = ns.db.meterClock == nil or next(ns.db.meterClock.own) == nil
    mT.diag = ns.db.diag.meter
    mT.errors = #(ns.db.errors or {})

    -- the threat window is drawn with the same bars: sized by its corner, only as tall as its bars,
    -- and when it cannot hold everyone your own bar stays
    do
        local tw = ns.huds.threat
        local function names() local o = {}; for i = 1, tw.count or 0 do o[#o + 1] = strip(tw.rows[i].name.text) end; return table.concat(o, ",") end
        ns.ThreatPreview(30); advance(1)
        mT.threatFull = names() .. " " .. tw.w .. "x" .. tw.h
        mT.threatEased = tw.rows[1] ~= nil and tw.rows[1].bar.eased == true and tw.rows[2].mark.shown == true and tw.grip ~= nil
        tw.grip.scripts.OnMouseDown(tw.grip, "LeftButton"); tw:SetSize(320, 80); tw.grip.scripts.OnMouseUp(tw.grip); advance(1)
        mT.threatSmall = names() .. " " .. tw.w .. "x" .. tw.h .. " kept " .. tostring(ns.db.threatW) .. "x" .. tostring(ns.db.threatH)
        ns.ResetLayout(); advance(1)
        mT.threatBack = names() .. " " .. tw.w .. "x" .. tw.h
        ns.CloseThreat(); advance(1)
    end

    world.party = keepParty
    putBack(ns.char, keepChar); putBack(ns.session, keepSession)
    ns.lastFight, ns.db.diag.fights, ns.db.diag.fightsFromMeter, ns.db.showRecap = keepLast, keepFights, keepMeter, keepRecap
    world.hp, world.mana, world.targetLevel, world.targetName = keepWorld[1], keepWorld[2], keepWorld[3], keepWorld[4]
end
local function check(name, ok) io.write(string.format("   [%s] %s\n", ok and "ok" or "FAIL", name)); if not ok then os.exit_code = 1 end end
local c = ns.char.combat
if MODE == "bare" then
    check("no internal errors logged", #(ns.db.errors or {}) == 0)
    check("6 fights recorded from live hit events alone", c.fights == 6 and ns.db.diag.fightsFromMeter == 0)
    check("damage taken still known (64+150+20+175+120+130)", c.taken == 659)
    check("note saved", #ns.char.journal == 1)
    do
        local state
        ns.meter.demoUntil = 0; ns.RefreshMeter()                 -- the settings page's preview button was pressed on the way here
        for _, r in ipairs(ns.HealthRows()) do if r.name == "Damage meter" then state = r.state end end
        check("meter: without the game's damage meter the window stays away and the client checks say so", ns.huds.meter.shown == false and state == "bad")
    end
    check("summary keeps the safety line when health is never readable", ns.SummaryText(false):find("Safety: a fight costs %d+%% of its health") ~= nil)
    io.write("\n" .. ns.SummaryText(false) .. "\n")
    if #(ns.db.errors or {}) > 0 then for _, e in ipairs(ns.db.errors) do io.write("   x" .. e.count .. " [" .. e.where .. "] " .. e.msg .. "\n") end end
    os.exit(os.exit_code or 0)
end
check("no internal errors logged", #(ns.db.errors or {}) == 0)
if os.getenv("SV") then                       -- started from a real saved-variables file: it must simply survive
    check("old data loaded and the report rendered", ns.char ~= nil)
    os.exit(os.exit_code or 0)
end
check("6 fights on the character", c.fights == 6)
check("all 6 fights came from the damage meter", ns.db.diag.fightsFromMeter == 6)
check("pet block: name and level, progress, kills from the last pet gain, happiness, loyalty, TP (" .. tostring(petLineHappy) .. ")",
    petLineHappy == "Humar  6 | 5%  19 kills | happy 125%  ·  Rebellious 1/6  ·  25 TP to spend")
check("happy face icon from the pet frame texture", petFace)
check("pet level-up gain counted across the wrap, unhappy pet warned (" .. tostring(petLineUnhappy) .. ")",
    petLineUnhappy == "Humar  7 | 2%  30 kills | unhappy 75%  feed it  ·  Rebellious 1/6 falling  ·  25 TP to spend")
check("pet bar turns red when unhappy", petBarRed)
check("rested XP drawn on the bar and named", restedShown)
check("XP block: level bar, rates, kills to level (" .. tostring(xpBlock) .. ")", xpBlock ~= nil and xpBlock:find("^Level 7 | %d+%%  [%d.k]+ to go | [%d.k]+ xp/h") ~= nil)
check("bars stretch to the widest line", ns.huds.xp.blocks.xp.bar:GetWidth() >= 13 * 18 and ns.huds.xp:GetWidth() > ns.huds.xp.blocks.xp.bar:GetWidth())
check("pet XP this session 45+845+30", petSessionXP == 920)
check("with the background on, a feed line is as wide as the XP window and has its background", feedJoined)
check("pet calls probed once (" .. tostring(petProbe) .. ")", type(petProbe) == "string" and petProbe:find("C_PetInfo.GetPetTrainingPoints={spent:95;totalPoints:120}", 1, true) ~= nil)
check("pet damage counted (90)", c.petDmg == 90)
check("threat solo: pet holding aggro first, then you at 92% (" .. tostring(threatSolo) .. ")", threatSolo == "Humar=aggro, Tess Ter=169  92%")
check("threat edge shows your state colour", threatSoloEdge == true)
check("threat warning: at 92% behind the pet the border shows, the title says ease off, one sound (" .. tostring(threatWarnTitle) .. ", " .. tostring(threatWarnSounds) .. ")",
    threatWarned == true and threatWarnTitle == "Ease off" and threatWarnSounds == 1 and threatWarnCount == 1)
check("threat warning: gone once the fight is over", threatWarnAfter == true)
check("threat warning: none for a tank (role, or a warrior in Defensive Stance), back for a hunter without a second sound (" .. tostring(threatBackOn) .. ")",
    threatTankRole == true and threatTankStance == true and threatBattleStance == true and threatBackOn == 1)
check("no threat window solo without a pet", threatNoPet == false)
check("threat window stays after the fight, dimmed (" .. tostring(threatAfter) .. ")", threatAfter == "Humar=aggro, Tess Ter=169  92%" and threatDim == 0.5)
check("the x closes it", threatClosed == false)
check("after a close, the next fight (now in a party) opens it again", threatParty ~= nil)
check("threat in a party with secret numbers: three bars, no crash (" .. tostring(threatParty) .. ")", threatParty ~= nil and select(2, threatParty:gsub("=", "")) == 3)
check("threat preview shows five bars", threatPreview ~= nil and select(2, threatPreview:gsub("=", "")) == 5)
check("threat probe recorded", type(ns.db.diag.threatProbe) == "string" and ns.db.diag.threatProbe:find("player:false/1/92", 1, true) ~= nil)
check("ready check: nothing while alone; joining a group lists what is missing (" .. tostring(ready.joined) .. ")", ready.alone == "hidden"
    and ready.joined == "Before you go   click to close / Bags: 1 free slot / Gear: lowest piece at 20% / Food: 2 / No water / Ammunition: 50")
check("ready check: hidden in a fight, back after it; an unhappy pet is named (" .. tostring(ready.unhappy) .. ")", ready.inFight == "hidden" and ready.afterFight and ready.unhappy == "missing: Your pet is unhappy: feed it")
check("ready check: gone once everything is in order, and quiet until the next group", ready.fixed and ready.quietAfter)
check("ready check: a new group asks again (" .. tostring(ready.rejoined) .. "); a click closes it", ready.rejoined == "Before you go   click to close / Bags are full" and ready.closed)
check("ready check: /dls ready shows the whole list (" .. tostring(ready.full) .. ")", ready.slash:find("1 thing missing", 1, true) ~= nil
    and ready.full == "Before you go   click to close / Bags are full / Gear: lowest piece at 100% / Food: 10 / Water: 10 / Ammunition: 1200 / Pet is out")
check("ready check: a rogue without poisons learned is asked for none, nor for Vanish powder or water (" .. tostring(ready.rogueNew) .. ")", ready.rogueNew == "none, none, none")
check("ready check: once learned (" .. tostring(ready.rogueLearned) .. "), carried (" .. tostring(ready.rogueCarried) .. ")",
    ready.rogueLearned == "missing: No poisons in your bags, missing: No Flash Powder (Vanish)" and ready.rogueCarried == "missing: No poison on your main hand, ok: Flash Powder: 3 (Vanish)")
check("ready check: poison applied, and about to run out (" .. tostring(ready.rogueRunsOut) .. ")", ready.rogueApplied == "ok: Poison on your main hand" and ready.rogueRunsOut == "missing: Poison on your main hand runs out in 2 min")
check("ready check: a shaman is asked for an Ankh only with Reincarnation (" .. tostring(ready.shamanAnkh) .. ")", ready.shamanNew == "none" and ready.shamanAnkh == "missing: No Ankh (Reincarnation)")
if MODE ~= "bare" then
    check("client checks: threat readable, Growl click worked, searches seen (" .. tostring(health["Threat numbers"]) .. ")",
        tostring(health["Threat numbers"]):find("^ok: readable") ~= nil and tostring(health["Growl reminder"]):find("^ok: .*click on the banner switches it") ~= nil
        and tostring(health["Prices from searches"]):find("^ok: %d+ updates") ~= nil and tostring(health["Auction scan"]):find("^ok: %d+ items from %d+ auctions") ~= nil)
    check("client checks: ready check and keys report what the client gave (" .. tostring(health["Ready check"]) .. ")",
        tostring(health["Ready check"]):find("^ok: food and drink are told apart") ~= nil and tostring(health["Keys on the cooldown manager"]):find("^ok: %d+ icons") ~= nil)
    check("client checks: /dls check says the count and opens the list (" .. health.said .. ")", health.said:find("client checks: %d+ work, %d+ limited, 0 not working") ~= nil and health.rows == 1)
    check("client checks: a logged error turns its row red", health["Addon errors"] == "ok: none logged" and health.errors == "bad")
end
check("ready check: a warlock's Voidwalker is fine alone and flagged in a group (" .. tostring(ready.voidGroup) .. ")",
    ready.voidSolo == "ok: Demon is out" and ready.voidGroup == "missing: Voidwalker out: it taunts mobs off the tank" and ready.impGroup == "ok: Demon is out")
check("party targets: beside party1's frame, named, sized to it, for party1target (" .. tostring(partyT.name) .. ", " .. tostring(partyT.size) .. ")",
    partyT.shown == true and partyT.unit == "party1target" and partyT.name == "Kolkar Stormer" and partyT.size == "110x19" and partyT.placed == "frame" and not partyT.others)
check("party targets: hidden health gives a bar and no percentage; no edge unless it is your target; gone with the target", partyT.pct == "" and not partyT.notMine and partyT.gone)
check("party targets: not resized in a fight, resized after it (" .. tostring(partyT.inFight) .. " -> " .. tostring(partyT.afterFight) .. ")", partyT.inFight == 110 and partyT.afterFight == 140)
check("party targets: the setting turns them off and on, and nothing shows alone", partyT.off and partyT.onAgain == true and partyT.solo)
check("party targets: your threat on it shows in a badge (" .. tostring(partyT.threat) .. ", " .. tostring(partyT.aggro) .. "), gone without threat; power bar under the health",
    partyT.noThreat and partyT.threat == "true 92% true" and partyT.aggro == "aggro" and partyT.threatGone)
check("party targets: your own frame gets your target beside it (" .. tostring(partyT.own) .. "), without the same-target edge; its own switch hides it",
    partyT.own == "true target Thunderhawk Hatchling frame" and not partyT.ownEdge and partyT.petUnplaced and partyT.ownOff)
check("party frame alone: off by default; switched on it shows, and comes back when the game hides it", soloT.offByDefault and soloT.on == true and soloT.afterGameHid == true)
check("party frame alone: left hidden in a fight, shown after it; untouched in a group; hidden again when switched off",
    soloT.inFight == false and soloT.afterFight == true and soloT.grouped == true and soloT.leftGroup == true and soloT.offAgain)
check("Growl on while alone: no reminder", growlSolo)
check("Growl on in a dungeon group: banner with the off macro", growlDungeon)
check("and the pet line says so (" .. tostring(growlPetLine) .. ")", (growlPetLine or ""):find("| Growl ON  ·  ", 1, true) ~= nil)
check("after the click the banner goes", growlFixed)
check("Growl off while alone: banner with the on macro", growlOffSolo)
check("right-click leaves it and hides the banner", growlDismissed)
check("turned back on: nothing left to say", growlBack)
local function keyOf(item) local l = ns.keys.labels[item]; return l and l.holder.shown and l.fs.text or nil end
check("cooldown manager: Arcane Shot shows R through another rank's name, Serpent Sting c-5, unbound Aimed Shot nothing",
    keyOf(cdmItems[1]) == "R" and keyOf(cdmItems[2]) == "c-5" and keyOf(cdmItems[3]) == nil)
check("cooldown manager: a mouse button on the second bar reads M4", keyOf(cdmUtility[1]) == "M4")
check("key names shortened", ns.ShortKey("SHIFT-MOUSEWHEELUP") == "s-WU" and ns.ShortKey("ALT-CTRL-F") == "ac-F" and ns.ShortKey("NUMPAD7") == "N7")
BINDINGS.ACTIONBUTTON2 = "T"; fire("UPDATE_BINDINGS"); advance(1)
check("a changed binding follows", keyOf(cdmItems[1]) == "T")
ns.db.showKeys = false; advance(1)
check("and the setting takes the labels away", keyOf(cdmItems[1]) == nil)
ns.db.showKeys = true
check("cooldown manager probe recorded (" .. tostring(ns.db.diag.keysProbe) .. ")", type(ns.db.diag.keysProbe) == "string" and ns.db.diag.keysProbe:find("icons=4", 1, true) ~= nil)
check("fps row sits at the top of the XP window", (blockText("stats") or ""):find("^100 fps  ·  H 127  W 128 ms  ·  lag") ~= nil)
check("total damage 161+300+210+80+200+210", c.dmg == 1161)
check("pull sizes 1/2/3 recorded", c.size[1] and c.size[1].fights == 4 and c.size[2].fights == 1 and c.size[3].fights == 1)
check("split by level: 4 fights at 7, 2 at 8", ns.char.byLevel[7].fights == 4 and ns.char.byLevel[8].fights == 2)
check("higher-level mobs tracked separately", ns.char.byDiff.higher and ns.char.byDiff.higher.fights == 2 and ns.char.byDiff.even.fights == 4)
check("zone slice recorded", ns.char.byZone["Durotar"].fights == 6)
check("toughest opponent is the Razormane Hunter", ns.ToughestMobs(3)[1] and ns.ToughestMobs(3)[1].name == "Razormane Hunter")
check("one death, one out-of-mana fight", c.deaths == 1 and c.oomFights == 1)
check("health after fight was sampled", c.endHPn >= 3)
check("session kept across reload", kept == 6)
check("new session after fresh login", ns.session.combat.fights == 0)
check("Mining skill-up and 2 gathers tracked", ns.char.gather["Durotar"].Mining.gathers == 2 and ns.char.gather["Durotar"].Mining.items["Copper Ore"] == 2)
check("trainer unlocks remembered", ns.char.unlocks.Engineering and ns.char.unlocks.Engineering["Coarse Blasting Powder"] == 75)
check("recipes remembered (4 learned)", #ns.char.recipes.Engineering.list == 4)
check("green recipes count as maybe (3 from 3 Copper Bars)", ns.CraftNow("Engineering").green == 3 and ns.CraftNow("Engineering").orange == 14)
check("too-low-skill log has Tin Vein", ns.char.lowskill[1] and ns.char.lowskill[1].node == "Tin Vein")
check("note saved", #ns.char.journal == 1)
check("loot: 9 items incl. the mined ore, vendor value 47s 24c, junk 12c, quest reward ignored", lootBefore and lootBefore.items == 9 and lootBefore.vendor == 12 + 150 + 350 + 4200 + 10 + 2 and lootBefore.junk == 12)
check("loot: coin 3s20c + 1g5c = 10325", lootBefore.coin == 10325)
check("loot: one green and one blue recorded as notable drops", #lootBefore.drops == 2 and lootBefore.byQ[3].n == 1)
if MODE ~= "bare" then
    -- Light Hide 3 x (237 net vs 50 vendor) = +561, Copper Ore 2 x (28 vs 5) = +46, Carving Knife 190 net < 350 vendor, Blade unpriced
    check("loot: auction view prefers the AH for hides and ore, the vendor for the knife, gain 607",
        lootView and lootView.hasAH and lootView.ahGain == 607 and lootView.priced == 3 and lootView.unpriced == 2 and lootView.ahAge == 2
        and lootView.stacks[1].name == "Blade of the Test" and lootView.stacks[2].name == "Light Hide" and lootView.stacks[2].sellAt == "ah"
        and lootView.stacks[3].sellAt == "vendor")
    local forAH, gain = ns.BagsForAuction()
    check("bags: the Light Hide stack is worth +3s74c on the AH", forAH and #forAH == 1 and gain == 374 and forAH[1].name == "Light Hide")
    local function norm(t) return (tostring(t):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end
    check("tooltip: vendor row then AH row with seen/age (" .. norm(tipLines[2]) .. ")", #tipLines == 2 and norm(tipLines[1]) == "Vendor 50c" and norm(tipLines[2]) == "Horde AH lowest 2s 50c 19 seen · 2 days ago")
    check("tooltip: same data twice adds no second line; unknown item, forbidden tooltip and setting off add none", tipDup == 2 and scanResult.unknownAndForbidden and tipOff == 0)
    check("tooltip: a stack of 2 gets a heading row and the totals on both rows (" .. tostring(tipStack[3]) .. ")", #tipStack == 3 and norm(tipStack[1]) == "each all 2" and norm(tipStack[2]) == "Vendor 50c 1s 0c" and norm(tipStack[3]) == "Horde AH lowest 2s 50c 5s 0c 19 seen · 2 days ago")
    local r = scanResult.realm
    check("scan: auto scan on AH open commits 4 items from 6 auctions, Rough Stone at 3c", scanResult.requests == 1 and scanResult.stone == 3 and r and r.count == 4 and r.auctions == 6 and r.scanned)
    check("scan: seen counts and history (Light Hide 3 units, 250 kept as min, history has two days)", r and r.items[783].n == 3 and r.items[783].p == 250 and select(2, r.items[783].h:gsub(" ", "")) == 1)
    check("scan: second AH open within 15 min does not request again; /dls scan explains; force scans", scanResult.requestsAfterSecondOpen == 1 and scanResult.throttleMsg:find("next scan possible") and scanResult.requestsAfterForce == 2)
    check("scan: repeated list events after a finished scan do not start it again (" .. tostring(scanResult.rereads) .. ")", scanResult.rereads == 0)
    local feedHit = false; for _, l in ipairs(feedLog) do if strip(l):find("Auction scan  4 items", 1, true) then feedHit = true end end
    check("scan: feed line announces the result", feedHit)
    check("scan: within the account's 15 minutes a second house asks nothing, but reads another addon's list", scanResult.neutralAsked == 0 and scanResult.foreign == 1)
    check("scan: Auctionator's last Full Scan counts toward the 15 minutes (" .. tostring(scanResult.auctionatorWait) .. " s)", scanResult.auctionatorWait and scanResult.auctionatorWait >= 770 and scanResult.auctionatorWait <= 790)
    check("scan: the status row offers Try now while throttled, and it sends a request", scanResult.tryNow)
    check("scan: manual by default (a click on Scan prices)", scanResult.manualByDefault)
    check("scan: the automatic scan, when switched on, waits for a key press (not Escape) instead of a timer", scanResult.heldBack)
    check("scan: the button on the auction house window sends a request", scanResult.ahButton)
    check("scan: a minute without the list stops the wait, and a list arriving later is still taken", scanResult.gaveUp and scanResult.lateTaken)
    check("scan: asked while the auction house is busy, the request waits for the house to be free", scanResult.queued)
    check("scan: a request the auction house throws away is sent again", scanResult.resent)
    check("scan: with no ready signal the request goes out after ten seconds", scanResult.queueCap)
    check("scan: each request is logged with how it was asked and how it ended (" .. tostring(scanResult.logEntry) .. ")", scanResult.logged and scanResult.silentLogged)
    check("panel: buttons on rows sit above the rows, so the row cannot swallow their click", scanResult.tryAbove)
    check("trend: Carving Knife fell from 2s to 1s 50c since the seed scan (-25%)", scanResult.trend == -25)
    check("tooltip: with two days known there is no usual row yet (" .. norm(scanResult.tipTrend[2]) .. ")", (function() for _, l in ipairs(scanResult.tipTrend) do if l:find("usual") then return false end end; return true end)() and norm(scanResult.tipTrend[2]) == "Horde AH lowest 1s 50c 1 seen · just now")
    check("search: 'carv' finds the knife with median and max", #scanResult.search == 1 and scanResult.search[1].name == "Carving Knife" and scanResult.search[1].med == 150 and scanResult.search[1].max == 150)
    check("history: two days for the knife, newest first", #scanResult.historyRows == 2 and scanResult.historyRows[1].min == 150 and scanResult.historyRows[2].min == 200)
    check("tooltip: holding Alt adds the other faction's line (" .. tostring(scanResult.tipAlt[3]) .. ")", #scanResult.tipAlt == 3 and norm(scanResult.tipAlt[3]) == "Alliance AH lowest 3s 0c 7 seen · yesterday")
    check("tooltip: 'always' shows the other faction without a modifier (" .. tostring(scanResult.tipAlways[3]) .. ")", #scanResult.tipAlways == 3 and norm(scanResult.tipAlways[3]) == "Alliance AH lowest 3s 0c 7 seen · yesterday")
    do
        local sm, st, sw, so = scanResult.smelt, scanResult.smeltStack, scanResult.smeltWorse, scanResult.smeltOwn
        check("smelted: the modifier adds the bar price per ore under the ore's own (" .. norm(sm[3] or "-") .. ")",
            #scanResult.smeltPlain == 2 and #sm == 3 and norm(sm[2]) == "Horde AH lowest 30c 40 seen · 2 days ago" and norm(sm[3]) == "Horde AH smelted 45c 12 seen · 2 days ago · Copper Bar")
        check("smelted: a stack shows its total, and the better way to sell is the one green row (" .. norm(st[4] or "-") .. ")",
            norm(st[4]) == "Horde AH smelted 45c 1s 80c 12 seen · 2 days ago · Copper Bar"
            and sm.green[3] and not sm.green[2] and sw.green[2] and not sw.green[3])
        -- every column starts or ends at the same place on every row (the test font is 6 wide a byte)
        local function ends(l, word) local _, e = l:find(word, 1, true); return e end
        local function at(l, word) return (l:find(word, 1, true)) end
        local function lined(rows)
            return #rows == 4 and ends(rows[1], "each") == ends(rows[2], "5c") and ends(rows[2], "5c") == ends(rows[3], "30c") and ends(rows[3], "30c") == ends(rows[4], "45c")
                and ends(rows[1], "all 4") == ends(rows[2], "20c") and ends(rows[2], "20c") == ends(rows[3], "1s 20c") and ends(rows[3], "1s 20c") == ends(rows[4], "1s 80c")
                and at(rows[3], "seen") == at(rows[4], "seen") and ends(rows[3], "40 seen") == ends(rows[4], "12 seen") and at(rows[3], "2 days ago") == at(rows[4], "2 days ago")
                and rows[4]:find("2 days ago  ·  Copper Bar", 1, true) ~= nil
        end
        check("columns: a heading says which price is for one and which for all; prices, totals, seen counts and ages line up (" .. norm(st[1]) .. ")",
            norm(st[1]) == "each all 4" and lined(st) and scanResult.smeltPinned)
        local tx = scanResult.smeltText
        check("columns: a tooltip without a minimum width gets the same rows padded with spaces (" .. norm(tx[4] or "-") .. ")",
            lined(tx) and scanResult.smeltTextPlain and norm(tx[4]) == norm(st[4]))
        check("columns: a tooltip that stays too narrow is noticed, logged and padded with spaces from then on (" .. tostring(scanResult.narrowMode) .. ", " .. tostring(scanResult.narrowWhy) .. ")",
            scanResult.okMode == "columns" and scanResult.narrowMode == "text" and scanResult.narrowWhy == "tooltip stayed narrow" and scanResult.narrowNextPlain and lined(scanResult.narrowNext))
        check("smelted: the character's own recipe sets the ratio, and no bar price means no row (" .. norm(so[3] or "-") .. ")",
            norm(so[3]) == "Horde AH smelted 22c 12 seen · 2 days ago · Copper Bar" and #scanResult.smeltNoBar == 2)
    end
    check("history header: collapsed shows the newest day, a click shows both (" .. tostring(scanResult.collapsedRows) .. " -> " .. tostring(scanResult.expandedRows) .. ")", scanResult.collapsedRows == 2 and scanResult.expandedRows == 3)   -- the neutral house adds one row
    check("neutral AH: scan at a goblin auctioneer lands under the Neutral key and shows in tooltips while the modifier is held (" .. tostring(scanResult.tipNeutral[3]) .. ")",
        scanResult.neutral and scanResult.neutral.count == 4 and #scanResult.tipNeutral == 3 and norm(scanResult.tipNeutral[3]) == "Neutral AH lowest 3c 10 seen · just now")
    check("other houses: hidden without the modifier, and Shift is the default (" .. #scanResult.tipNeutralPlain .. " rows, " .. tostring(scanResult.compareDefault) .. ")",
        #scanResult.tipNeutralPlain == 2 and scanResult.compareDefault == "shift")
    local sg = scanResult.sight
    check("seen on screen: a full listing sets lowest and count, ignoring bid-only auctions (" .. tostring(sg.first) .. ")", sg.first == "300/2")
    check("seen on screen: the tooltip shows it at once with a fresh age (" .. norm(sg.tip[#sg.tip]) .. ")", #sg.tip == 1 and norm(sg.tip[1]) == "Horde AH lowest 3s 0c 2 seen · just now")
    check("seen on screen: a partial listing only lowers the price (" .. sg.partialHigher .. " -> " .. sg.partialLower .. ")", sg.partialHigher == "300/2" and sg.partialLower == "250/2")
    check("seen on screen: a full listing may raise it once the cheap ones are gone (" .. sg.completeHigher .. ")", sg.completeHigher == "400/1")
    check("seen on screen: an open tooltip of that item is redrawn only when the price moved", sg.redrawnUnchanged == 0 and sg.redrawn == 1)
    check("seen on screen: stackable items, one row per price (" .. sg.commodity .. ")", sg.commodity == "20/60")
    check("seen on screen: the search list itself (" .. sg.browse .. "), a second suffix cannot raise the first (" .. sg.variant .. ")", sg.browse == "7/4 90/1" and sg.variant == "90/1")
    check("seen on screen: old auction house, a single page is complete, one page of many only lowers (" .. sg.page .. ", " .. sg.pagePartial .. ")", sg.page == "80/6" and sg.pagePartial == "80/6")
    check("seen on screen: nothing is taken with the auction house closed", sg.closed == "400/1")
    check("seen on screen: first sighting recorded (" .. tostring(sg.probe) .. ")", sg.probe == "item item=9101 unit=300 units=2 complete=true")
    check("usual price: middle of five daily lows is 4s 52c, on its own row under the lowest (" .. norm(sg.tipUsual[2]) .. ")",
        sg.usual == 452 and #sg.tipUsual == 2 and norm(sg.tipUsual[1]) == "Horde AH lowest 4s 0c 1 seen · just now" and norm(sg.tipUsual[2]) == "Horde AH usual 4s 52c last 5 scan days")
    check("age text (" .. sg.ages .. ")", sg.ages == "just now, 5 min ago, 2 h ago, 3 days ago, today")
    local function find(list, id) for _, e in ipairs(list or {}) do if e.id == id then return e end end end
    local powder, bolts = adv and find(adv.craft, 4357), adv and find(adv.craft, 4359)
    check("advisor: Rough Blasting Powder +1s 87c to AH, 14 craftable (" .. tostring(powder and strip(powder.right)) .. ")",
        powder and powder.value == 187 and strip(powder.right):find("to AH") and strip(powder.left):find("make 14"))
    check("usual price: an odd high listing counts at its usual price (" .. tostring(usualResult.fair) .. ", " .. tostring(usualResult.vs) .. "%)", usualResult.fair == "42/200/42" and usualResult.vs == 376)
    check("usual price: the craft that only paid at the odd price is no longer advised, and the price search lists the usual price", usualResult.craftGone == true and usualResult.search == 42)
    check("advisor: Copper Bolts pay more at a vendor, +2s 40c (" .. tostring(bolts and strip(bolts.right)) .. ")", bolts and bolts.value == 240 and strip(bolts.right):find("to vendor"))
    check("advisor: Rough Dynamite skipped, Linen Cloth has no price", adv and adv.craftSkipped and adv.craftSkipped.n >= 1 and table.concat(adv.craftSkipped.names, ","):find("Linen Cloth"))
    local bow = adv and find(adv.flips, 2506)
    check("advisor: the vendor's bow flips for +75s (" .. tostring(bow and strip(bow.right)) .. ")", bow and bow.value == 7500 and ns.db.vendors[2506].c == 2000 and not ns.db.vendors[2589])
    local knife = adv and find(adv.bargains, 2140)
    check("advisor: the knife listed at 1s 50c is a bargain, a vendor pays 3s 50c", knife and knife.value == 200)
    local ore = adv and find(adv.gather, 2770)
    check("advisor: Mining suggests Copper Ore by the stack of 20 (" .. tostring(ore and strip(ore.right)) .. ")", ore and strip(ore.right):find("/20") and ore.value == 28 * 20)
    local hide = adv and find(adv.sell, 783)
    check("advisor: sell the Light Hide on the AH, +3s 74c (" .. tostring(hide and strip(hide.right)) .. ")", hide and hide.value == 374 and adv.vendor and adv.vendor.stacks == 1)
    check("advisor: item row tooltip shows the item and the reasoning", advTip and advTip:find("Materials") ~= nil)
    check("advisor: a click on a hint opens the item's price page", advOpened)
    check("advisor: vendor prices are kept in the saved data (bargains survive a /reload)", advKept)
    check("advisor: an item not loaded yet is asked for and its price read when it arrives", advLoaded)
    check("advisor: a patched vendor price (1c now, 15s 35c saved) uses the client's number", advPatched)
    check("advisor: saved vendor prices start over with a new game build", advNewBuild)
    check("advisor: right-click hides a hint", advAfterHide and not find(advAfterHide.flips, 2506) and advAfterHide.flag)
    check("layout: a 1000px window puts sections side by side (" .. tostring(advWide) .. " rows in later columns)", advWide and advWide > 0)
    check("auction history keeps day:min:median only", not DearLordAuctionDB.realms["ClassicBetaPvE2-Horde"].items[2140].h:find("%d+:%d+:%d+:%d+") and DearLordAuctionDB.version == 2)
else
    check("loot: no auction data in a bare client, view still works", lootView and not lootView.hasAH and lootView.ahGain == 0 and ns.BagsForAuction() == nil)
end
check("census: a player seen at 10 then 20 is one character at level 20 (" .. tostring(census.chuck) .. ")", census.chuck and census.chuck:match("^20,") and census.countAfterMouseover == 1)
if MODE ~= "bare" then
    local function has(list, x) for _, v in ipairs(list or {}) do if v == x then return true end end end
    check("census: /who walks the levels one at a time (" .. tostring(census.asked and #census.asked) .. " queries)", census.asked and census.asked[1] == "1-1" and has(census.asked, "20-20"))
    check("census: a full answer at level 20 is split by class, then race", census.plan and census.plan.n == 60 and census.plan.kids and has(census.plan.kids, '20-20 c-"Paladin"')
        and census.r.plan['20-20 c-"Paladin"'] and census.r.plan['20-20 c-"Paladin"'].kids and has(census.asked, '20-20 c-"Paladin" r-"Tauren"'))
    check("census: every character once (60 paladins + 5 hunters + Chuck = " .. tostring(census.count) .. ")", census.count == 66)
    check("census: the game's own /who window stays shut and listens again afterwards", census.lfgShown == false and census.lfgListening == true)
    check("census: no query right after one, none in combat, none while the player uses /who", census.burst == 1 and census.combat == 0 and census.afterUser == 0)
    check("census: a blocked /who switches it off", census.afterBlock == 0 and ns.db.diag.census.blocked)
    check("census: the Alliance filter hides the Horde characters (" .. tostring(census.allianceText[1]) .. ")", census.allianceText[1] and census.allianceText[1]:find("^0 characters"))
end
check("lag: instant spell 250 ms, a cast counted at its start, a cast without its start skipped (" .. table.concat(lagNew, ",") .. ")",
    #lagNew == 2 and lagNew[1] == 250 and lagNew[2] == 250 and ns.db.diag.lag.castSkipped == 1)
check("summary: the current view has a title and stat tiles; Copy text still gives the plain text", summaryTitle and summaryTiles >= 1 and summaryBoxText:find("Combat:") ~= nil)
check("level view: buttons for each level, newest first, now/last marked (" .. table.concat(chips, ", ") .. "); a click shows that level (" .. tostring(levelLabel) .. ")",
    chips[1] == "8 now" and chips[2] == "7 last" and levelLabel == "Level 7")
check("perf: a 312 ms piece of work is said in chat and listed by /dls perf", perfSaid and perfListed)
check("census: past 12,000 characters it trims to 11,000 in one go (" .. tostring(censusAfterTrim) .. ")", censusAfterTrim == 11000)
check("loot reset filed the session under history", ns.db.lootHistory and #ns.db.lootHistory >= 1 and ns.db.lootHistory[1].items == 9)
check("junk in bags: 4 x 12c", (select(1, ns.JunkInBags())) == 48)
check("settings page: every control exercised (" .. touched .. ") and values changed", touched >= 23 and settingsChanged)
check("settings reset restores defaults", afterReset)
check("report resize remembered (760x620) and rows re-flowed to the new width", resized and resized.w == 760 and resized.h == 620)
check("double-click fits the height to the content (" .. tostring(fitted and fitted.h) .. ")", fitted and fitted.h ~= 620 and fitted.h >= 260)
check("a saved height taller than the screen is clamped to it (" .. tostring(clamped and clamped.h) .. ")", clamped and clamped.h == 980 and clamped.w == 760)
check("title-bar fit button exists; right-click restores the default size", fitBtn ~= nil and afterDefault == nil)
local function escListed() for _, n in ipairs(UISpecialFrames) do if n == "DearLordStatsPanel" then return true end end return false end
local escOn = escListed(); ns.db.panelEsc = false; ns.ApplyPanelStyle(); local escOff = escListed(); ns.db.panelEsc = true; ns.ApplyPanelStyle()
check("Escape closes the report by default; the setting takes it off the list and back", escOn and not escOff and escListed())
check("Concussive Shot flagged as not on bars", (function() for _, n in ipairs(ns.spells.missing) do if n == "Concussive Shot" then return true end end end)())
check("shield bar: hidden with no shield, shown with one: 44 / 44 and the time left (" .. tostring(shield.time) .. ")", shield.idle and shield.up and shield.time == "30")
check("shield bar: a hit lowers it, blinks and keeps the full size; percent on request (" .. tostring(shield.percent) .. ")", shield.hit and shield.percent == "45%")
check("shield bar: gone before its time is a break, and the bar leaves; its full size is remembered (" .. tostring(shield.learned) .. ")", shield.broken and shield.gone and shield.learned == 44)
check("shield bar: a hidden amount in a fight still shows, against the remembered size", shield.hidden)
check("shield bar: with buffs hidden too the shield is found by its spell id", shield.byId)
check("shield bar: a shield that runs its time fades instead of breaking", shield.faded)
check("shield bar: with nothing readable in a fight it is followed by its clock, and leaves when the buff is removed", shield.blind)
check("shield bar: met half used, it is measured against what such a shield holds (30 / 44, not 30 / 30)", shield.half)
check("shield bar: a fight that hides everything keeps the shield, and afterwards it still reads 30 / 44", shield.kept and shield.after)
check("shield bar: cast in a fight with nothing readable, your own cast brings the bar up; a cast on someone else does not", shield.cast)
check("shield bar: a fight ending with nothing left takes the bar away without a break", shield.silent)
check("shield bar: an unknown shield in a fight is kept ready and drawn from the hidden amount; the fight is traced (" .. tostring(shield.trace) .. " lines)", shield.standby and (shield.trace or 0) > 3)
check("shield bar: with the amount always hidden, the buff's own number gives 36 / 44, and the fight keeps the 44", shield.fromBuff and shield.intoFight)
check("shield bar: a shield landing in a fight with its cast unreadable is taken for the kind you had last (/ 44, no clock)", shield.guess)
check("shield bar: with no amount from the client the bar shows the time left; the setting switches it off", shield.timer and shield.off)
check("shield bar: Edit Mode shows it with a running preview and it can be dragged there, not outside", shield.edit and shield.moved and shield.editBroken and shield.editOff and shield.fixed)
check("shield bar: /dls shield previews it for 20 s", shield.preview and shield.previewOver)
check("shield bar: client checks say what the client gave (" .. tostring(shield.health) .. ")", shield.health ~= nil and shield.health:find("^ok") ~= nil and shield.note ~= nil)
check("refused actions: one that is not /who is logged and leaves the census on (" .. tostring(shield.refusedRow) .. ")", shield.refused and shield.refusedRow == "limited")
if MODE ~= "bare" then
    check("windfury: three melee results landing together are a proc, rated TOP 1 with a flash (" .. tostring(wfT.first) .. ")",
        wfT.first:find("Windfury  TOP 1  450 damage!  ·  3 hits, 1 crit", 1, true) ~= nil and wfT.flash)
    check("windfury: the top three shout, a miss is counted, the rest say top N (" .. tostring(wfT.fourth) .. ")",
        wfT.second:find("Windfury  TOP 2  200 damage!  ·  2 hits, 1 missed", 1, true) ~= nil and wfT.third:find("Windfury  TOP 3  150 damage!", 1, true) ~= nil
        and wfT.fourth:find("Windfury  top 4  120 damage  ·  3 hits", 1, true) ~= nil and wfT.fifth:find("Windfury  TOP 2  300 damage!", 1, true) ~= nil)
    check("windfury: the line is larger, stays 15 s and keeps a glow that breathes for the top three; both are settings", wfT.seen and wfT.glow and wfT.calm and wfT.sized)
    check("windfury: procs, the ranked list, the five biggest and the biggest single hit are kept", wfT.kept)
    check("windfury: not a proc: two hits, a shock with the swing, swings apart, Rockbiter, a bare weapon, another class, the setting off",
        wfT.two and wfT.spell and wfT.spread and wfT.rockbiter and wfT.bare and wfT.hunter and wfT.off)
    check("windfury: hidden hit amounts are written into the line by the game, side by side, unrated (" .. tostring(wfT.hidden) .. ")",
        wfT.hidden:find("Windfury  212 + 498 + 240  ·  1 crit", 1, true) ~= nil and wfT.hiddenKept and wfT.hiddenQuiet == 0)
    check("windfury: after the fight the meter's Windfury damage is rated among your fights (" .. tostring(wfT.fightLine) .. ")",
        wfT.fightLine:find("Windfury this fight  TOP 1  300 damage!  ·  1 proc", 1, true) ~= nil and wfT.fightKept
        and wfT.fightLine2:find("Windfury this fight  TOP 2  300 damage!", 1, true) ~= nil and wfT.fightLine2:find("proc", 1, true) == nil
        and wfT.fightLine3:find("Windfury this fight  TOP 3  100 damage!", 1, true) ~= nil and wfT.fightLine3:find("proc", 1, true) == nil)
    check("windfury: the fight recap carries that damage and its rating (" .. tostring(wfT.recap) .. ")", wfT.recap:find("windfury 300 (top 1)", 1, true) ~= nil)
    check("windfury: an unknown weapon enchant counts until the damage meter or the shaman's own cast says what it is",
        wfT.unknownCounted and wfT.learnedNot and wfT.unknownQuiet and wfT.learned and wfT.castNot and wfT.castIs)
    check("windfury: fights are compared with the damage meter and the client checks say so (" .. tostring(wfT.health) .. ")", wfT.fights and wfT.health == "limited")
    check("windfury: hits alone and in a group are counted apart, with their own samples (" .. tostring(wfT.apartSay) .. ")", wfT.apart)
    check("windfury: the client checks say where hit amounts can be read (" .. tostring(wfT.amountsRow) .. ")",
        type(wfT.amountsRow) == "string" and wfT.amountsRow:find("alone", 1, true) ~= nil and wfT.amountsRow:find("in a group", 1, true) ~= nil)
    check("windfury: /dls windfury lists the biggest (" .. tostring(wfT.sayAll) .. ")", wfT.say:find("procs seen in all", 1, true) ~= nil and wfT.sayAll:find("#1  300 damage, 1 proc on Test Boar", 1, true) ~= nil and wfT.sayAll:find("#1  450 damage, 3 hits, 1 crit", 1, true) ~= nil)
    check("windfury: the preview shows made-up procs and keeps nothing (" .. tostring(wfT.preview1) .. " / " .. tostring(wfT.preview2) .. ")",
        wfT.preview1:find("Windfury  212 + 198 + 240", 1, true) ~= nil and wfT.preview2:find("Windfury  TOP 2  1134 damage!", 1, true) ~= nil
        and wfT.preview3:find("Windfury this fight  top 14  682 damage  ·  2 procs", 1, true) ~= nil and wfT.previewKept)
end
if #(ns.db.errors or {}) > 0 then
    io.write("\n-- INTERNAL ERRORS\n")
    for _, e in ipairs(ns.db.errors) do io.write("   x" .. e.count .. " [" .. e.where .. "] " .. e.msg .. "\n") end
end
-- the damage meter
check("meter: the preview shows made-up players in both columns, sorted, with eased bars (" .. tostring(mT.preview1) .. ")",
    mT.startShown and mT.previewSorted and mT.preview1:find("^1%. %a+ %d+ [%d%.]+/s %d+%%") ~= nil and mT.preview2:find("Moonleaf", 1, true) ~= nil and mT.previewOver)
check("meter: pointing at a bar lists the abilities, pets in brackets (" .. tostring(mT.previewTip) .. ")", mT.previewTip:find("Attack (Joy)", 1, true) ~= nil)
check("meter: during a fight the hidden numbers are drawn by the game, in the game's order, without a share (" .. tostring(mT.live1) .. ")",
    mT.liveHidden and mT.live1 == "1. Tess Ter 600 30.0/s | 2. Tankard 300 15.0/s | 3. Healbot 40 2.0/s" and mT.live2 == "1. Healbot 520 26.0/s | 2. Tess Ter 60 3.0/s")
check("meter: in a fight your own abilities show, with pet and totem (" .. tostring(mT.liveTipOwn) .. ")",
    mT.liveTipOwn:find("Auto Shot", 1, true) ~= nil and mT.liveTipOwn:find("Bite  Joy 70", 1, true) ~= nil and mT.liveTipOwn:find("Shares appear when the fight ends", 1, true) ~= nil)
check("meter: another player's abilities in a fight only if the game takes the hidden id (" .. tostring(mT.liveTipOtherOk) .. ")",
    mT.liveTipOther:find("until the fight ends", 1, true) ~= nil and mT.liveTipOtherOk:find("Raptor Strike", 1, true) ~= nil and mT.diag.hiddenGuid == "accepted")
check("meter: after the fight the bars are sorted with their share, the title names the fight (" .. tostring(mT.after1) .. " // " .. tostring(mT.afterTitle) .. ")",
    mT.after1 == "1. Tess Ter 600 30.0/s 64% | 2. Tankard 300 15.0/s 32% | 3. Healbot 40 2.0/s 4%" and mT.after2 == "1. Healbot 520 26.0/s 90% | 2. Tess Ter 60 3.0/s 10%"
    and mT.afterTitle == "Test Ogre 0:20" and mT.afterSum == "940   47.0/s" and mT.afterPlain)
check("meter: the breakdown after a fight: abilities, pet, totem, shares, targets (" .. tostring(mT.tipOwn) .. " // " .. tostring(mT.tipTargets) .. ")",
    mT.tipOwn == "Auto Shot 350 17.5/s 58% | Arcane Shot 150 7.5/s 25% | Bite (Joy) 70 3.5/s 12% | Magma Totem 30 1.5/s 5%" and mT.tipTargets == "Test Ogre 350   100%"
    and mT.tipOther == "Melee 200 10.0/s 67% | Raptor Strike 100 5.0/s 33%" and mT.tipHeal == "Lesser Heal 520 26.0/s 100%" and mT.tipGone)
check("meter: the copy text has both columns (" .. tostring(mT.report) .. ")",
    mT.report == "DearLord Stats: Damage, Test Ogre (0:20) / 1. Tess Ter  600 (30.0/s, 64%) / 2. Tankard  300 (15.0/s, 32%) / DearLord Stats: Healing, Test Ogre (0:20) / 1. Healbot  520 (26.0/s, 90%) / 2. Tess Ter  60 (3.0/s, 10%)"
    and mT.liveReport == "hidden")
check("meter: the copy button's menu sends the lines to chat, or opens them as text (" .. tostring(mT.chat) .. ")",
    mT.menu == "say party box" and mT.chat == "7 lines to PARTY: DearLord Stats: Damage, Test Ogre (0:20) / 1. Tess Ter  600 (30.0/s, 64%)"
    and mT.box:find("2. Tankard  300 (15.0/s, 32%)", 1, true) ~= nil)
check("meter: a refused chat message opens the text box instead", mT.refused and mT.diag.chat == "refused (PARTY)")
check("meter: Fight shows the last fight, Total adds them up (" .. tostring(mT.fight2) .. " // " .. tostring(mT.total) .. ")",
    mT.fight2 == "1. Tankard 500 50.0/s 83% | 2. Tess Ter 100 10.0/s 17%" and mT.total:find("^1%. Tess Ter %d+ [%d%.]+/s %d+%% | 2%. Tankard 800") ~= nil
    and mT.totalTitle:find("^this session %d+:%d%d$") ~= nil)
check("meter: an earlier fight can be picked, and the next fight comes back to the running one (" .. tostring(mT.earlierLabel) .. ")",
    mT.earlierLabel == "Test Ogre  0:20" and mT.earlierTab == "Fight*" and mT.earlier == mT.after1 and mT.backToFight == "1. Tess Ter 50 10.0/s 100%")
check("meter: if the game's current session is empty after a fight, the last one is read by its id (" .. tostring(mT.byId) .. ")",
    mT.byId == "1. Tess Ter 50 10.0/s 100% // Test Rat 0:05 // fight number")
check("meter: damage taken, interrupts and enemies views (" .. tostring(mT.taken) .. " // " .. tostring(mT.interrupts) .. " // " .. tostring(mT.enemies) .. ")",
    mT.taken == "1. Tankard 400 20.0/s 78% | 2. Tess Ter 80 4.0/s 16% | 3. Healbot 30 1.5/s 6%" and mT.interrupts == "1. Tankard 2 | 2. Tess Ter 1"
    and mT.enemies == "1. Test Ogre 600 30.0/s 100%" and mT.tipTaken == "Melee (Test Ogre) 80 4.0/s 100%"
    and mT.tipEnemy == "Auto Shot (Tess Ter) 350 17.5/s 64% | Melee (Tankard) 200 10.0/s 36%")
check("meter: the second column switches off and on, a bar can carry the rate alone (" .. tostring(mT.rateOnly) .. ")",
    mT.oneCol and mT.twoCol and mT.oneColRows == mT.after1 and mT.rateOnly == "1. Tess Ter 30.0/s | 2. Tankard 15.0/s | 3. Healbot 2.0/s")
check("meter: a fight is timed by the combat flag, not by the game's longer clock (" .. tostring(mT.clockRow) .. ")",
    mT.clockRow == "1. Tess Ter 170 10.0/s 100% // Test Tail 0:17 // 170   10.0/s" and mT.clockTip == "Auto Shot 170 10.0/s 100%"
    and mT.clockReport == "DearLord Stats: Damage, Test Tail (0:17) / 1. Tess Ter  170 (10.0/s, 100%)" and mT.clockMenu == "Test Tail  0:17")
check("meter: after combat the bars wait for the final numbers instead of sinking (" .. tostring(mT.clockFrozen) .. ")",
    mT.clockFrozen == "1. Tess Ter 170 10.0/s // 0:17")
check("meter: Total leaves the game's extra seconds out too (" .. tostring(mT.clockTotal) .. " s)", mT.clockTotal == -3)
check("meter: a fight the game timed very differently keeps the game's clock (" .. tostring(mT.clockFar) .. " // " .. tostring(mT.clockDiag) .. ")",
    mT.clockFar == "1. Tess Ter 100 2.5/s 100% // 0:40" and mT.clockDiag:find("own=17.0 game=20.0", 1, true) ~= nil
    and mT.clockDiag:find("own=10.0 game=40.0 (game's used)", 1, true) ~= nil and mT.clockWiped)
check("meter: a narrow column shortens the per-second number, then drops the share (" .. tostring(mT.narrow) .. " // " .. tostring(mT.narrower) .. ")",
    mT.narrow:find("^1%. Tess Ter 600 30%.0 64%%") ~= nil and mT.narrower:find("^1%. Tess Ter 600 30%.0 |") ~= nil)
check("meter: resized by the corner, kept, not while locked, back to default on reset", mT.resized and mT.resizeKept and mT.lockedSize and mT.resetSize)
check("meter: more players than rows: the wheel scrolls (" .. tostring(mT.fewRows) .. " -> " .. tostring(mT.scrolled) .. ")",
    mT.fewVisible == 2 and mT.fewRows:find("^1%. Tess Ter") ~= nil and mT.scrolled:find("^2%. Tankard .* | 3%. Healbot") ~= nil)
check("meter: Total starts over at login, not on a reload; the reset button clears it (" .. tostring(mT.reset) .. ")",
    mT.loginResets >= 1 and mT.reloadNoReset and mT.reset == "nothing yet" and mT.diag.reset == "ok")
check("meter: closed with its x, back with /dls meter, hidden when idle if asked", mT.closed and mT.reopened and mT.idleHidden and mT.idleBack)
check("meter: the client checks report it (" .. tostring(mT.health) .. ")", mT.health:find("^ok: bars drawn %d+ times during fights") ~= nil and mT.healthOff == "limited")
check("meter: nothing in it raised an error", mT.errors == 0)
check("threat: drawn with the meter's bars, as tall as its five bars (" .. tostring(mT.threatFull) .. ")",
    mT.threatFull == "Tankard,You,Pet,Healbot,Frosty 250x127" and mT.threatEased)
check("threat: sized by its corner; too small for everyone, the top bar and your own stay (" .. tostring(mT.threatSmall) .. ")",
    mT.threatSmall == "Tankard,You 320x67 kept 320x80" and mT.threatBack == mT.threatFull)
if os.getenv("MDUMP") then
    io.write("\n== meter capture\n")
    local keys = {}
    for k in pairs(mT) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = mT[k]
        if type(v) == "table" then local t = {}; for a, b in pairs(v) do t[#t + 1] = a .. "=" .. tostring(b) end; table.sort(t); v = table.concat(t, " ") end
        io.write("   " .. k .. " = " .. tostring(v) .. "\n")
    end
    for _, e in ipairs(ns.db.errors or {}) do io.write("   x" .. e.count .. " [" .. e.where .. "] " .. e.msg .. "\n") end
end
os.exit(os.exit_code or 0)
