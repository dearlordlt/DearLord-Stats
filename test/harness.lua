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
local function secret() return setmetatable({}, SECRET_MT) end
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
    function M:SetText(t) needFont(self); self.text = tostring(t or "") end
    function M:GetText() return self.text end
    function M:SetFormattedText(fmt, ...) needFont(self); self.text = string.format(fmt, ...) end
    function M:GetStringWidth() return #((self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * 6 end
    function M:GetStringHeight() return 14 * (1 + math.floor(self:GetStringWidth() / 420)) end
    function M:Show() self.shown = true end
    function M:Hide() self.shown = false end
    function M:SetShown(v) self.shown = v and true or false end
    function M:IsShown() return self.shown end
    function M:IsMouseOver() return false end
    function M:SetSize(w, h) self.w, self.h = w, h end
    function M:SetWidth(w) self.w = w end
    function M:SetHeight(h) self.h = h end
    function M:GetWidth() return self.w end
    function M:GetHeight() return self.h end
    function M:SetAlpha(a) self.alpha = a end
    function M:GetTop() return 900 end
    function M:GetLeft() return 300 end
    function M:GetPoint() return "TOP", nil, "TOP", 0, -12 end
    function M:HasFocus() return false end
    function M:CreateTexture() return widget("Texture") end
    function M:CreateFontString() return widget("FontString") end
    -- unknown METHODS (capitalised) are harmless no-ops; unknown fields are nil, as on real frames
    return setmetatable(w, { __index = function(t, k) return M[k] or (type(k) == "string" and k:match("^%u") and function() end) or nil end })
end
function CreateFrame(kind, name, parent)
    local f = widget(kind, name); frames[#frames + 1] = f
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
function GameTooltip:AddDoubleLine(l, r) self.lines[#self.lines + 1] = plain(l) .. " | " .. plain(r) end
function GameTooltip:AddLine(l) self.lines[#self.lines + 1] = plain(l) end
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
function UnitName(u) if u == "player" then return "Tess Ter" elseif u == "pet" then return world.pet elseif u == "target" then return world.targetName end end
function GetRealmName() return "Classic Beta PvE 2" end
function UnitClass() return "Hunter", "HUNTER", 3 end
function UnitRace() return "Troll", "Troll", 8 end
function UnitLevel(u) if u == "target" then return world.targetLevel end return world.level end
function GetMaxPlayerLevel() return 60 end
function UnitXP() return world.xp end
function UnitXPMax() return world.xpMax end
function GetXPExhaustion() return world.rested > 0 and world.rested or nil end
function GetMoney() return world.money end
function UnitIsAFK() return world.afk end
function UnitAffectingCombat() return world.combat end
function InCombatLockdown() return world.combat end
function UnitExists(u) return (u == "pet" and world.pet ~= nil) or (u == "npc" and world.npc == true) end
function UnitHealth(u) if u == "player" then return hide(world.hp) end return secret() end
function UnitHealthMax() return world.hpMax end
function UnitPower() return hide(world.mana) end
function UnitPowerMax() return world.manaMax end
function UnitPowerType() return 0, "MANA" end
function UnitGUID(u) if u == "player" then return "Player-1-0000ABCD" elseif u == "pet" then return world.pet and "Pet-0-1" elseif world.threat[u] then return world.threat[u] end end
function UnitThreatSituation(who, unit) if world.threat[unit] and who == "player" then return 3 end end
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
C_Spell = {
    GetSpellName = function(id) return SPELLS[id] end,
    GetSpellInfo = function(id) return SPELLS[id] and { name = SPELLS[id] } or nil end,
    GetSpellCooldown = function(id)
        if id ~= 29515 then return nil end
        return { startTime = hide(0), duration = hide(0), isEnabled = true, modRate = 1 }
    end,
}
local ITEMS = { [4867] = { "Broken Scorpid Leg", 0, 12 }, [2140] = { "Carving Knife", 2, 350 }, [783] = { "Light Hide", 1, 50 },
    [2770] = { "Copper Ore", 1, 5 }, [2835] = { "Rough Stone", 1, 2 }, [9999] = { "Blade of the Test", 3, 4200 } }
GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT = "%d Gold", "%d Silver", "%d Copper"
-- the addon's own auction price database, as the Keeper hands it back: a scan from two days ago
local AH_DAY = math.floor((wall - 1577836800) / 86400)
DearLordAuctionDB = { version = 1, realms = { ["ClassicBetaPvE2-Horde"] = { scanned = wall - 2 * 86400, day = AH_DAY - 2, count = 3, auctions = 9,
    items = { [783] = { p = 250, n = 19, d = AH_DAY - 2, h = (AH_DAY - 2) .. ":250" }, [2140] = { p = 200, n = 1, d = AH_DAY - 2 }, [2770] = { p = 30, n = 40, d = AH_DAY - 2 } } },
    ["ClassicBetaPvE2-Alliance"] = { scanned = wall - 86400, day = AH_DAY - 1, count = 1, items = { [783] = { p = 300, n = 7, d = AH_DAY - 1 } } } } }
function GetNormalizedRealmName() return "ClassicBetaPvE2" end
function GetRealmName() return "Classic Beta PvE 2" end
function UnitFactionGroup(u) if u == "npc" then return world.npcFaction end return "Horde", "Horde" end
function IsAltKeyDown() return world.alt end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function hooksecurefunc(obj, name, fn) local orig = obj[name]; obj[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end end
-- the modern auction house: a replicated list of every auction (itemID, count, buyout), 0-based
local REPLICATE = { { 783, 2, 500 }, { 783, 1, 400 }, { 2140, 1, 200 }, { 2770, 20, 600 }, { 2770, 5, 0 }, { 2835, 10, 30 } }
C_AuctionHouse = { requests = 0,
    ReplicateItems = function() C_AuctionHouse.requests = C_AuctionHouse.requests + 1; world.replicated = true end,
    GetNumReplicateItems = function() return world.replicated and #REPLICATE or 0 end,
    GetReplicateItemInfo = function(i) local r = REPLICATE[i + 1]; if not r then return nil end
        return "Thing", 1, r[2], 1, true, 1, "", r[3], 1, r[3], 0, nil, nil, "Someone", nil, 0, r[1], true end,
    GetReplicateItemLink = function(i) return REPLICATE[i + 1] and ("|Hitem:" .. REPLICATE[i + 1][1] .. "::|h[Thing]|h") end,
    IsThrottledMessageSystemReady = function() return true end }
TooltipDataProcessor = { calls = {}, AddTooltipPostCall = function(kind, fn) TooltipDataProcessor.calls[kind] = fn end }
function GetCursorPosition() return 380, 200 end
C_Container = { GetContainerNumSlots = function(bag) return bag == 0 and 3 or 0 end,
    GetContainerItemInfo = function(bag, slot)
        if slot == 1 then return { itemID = 4867, stackCount = 4, quality = 0, hyperlink = "|cnIQ0:|Hitem:4867::|h[Broken Scorpid Leg]|h|r", hasNoValue = false } end
        if slot == 2 then return { itemID = 783, stackCount = 2, quality = 1, hyperlink = "|cnIQ1:|Hitem:783::|h[Light Hide]|h|r" } end
    end }
C_Item = { GetItemInfo = function(link)
        local id = tonumber(tostring(link):match("[Hh]?item:(%d+)")); local it = ITEMS[id]
        if not it then return nil end
        return it[1], link, it[2], 1, 1, "Misc", "Junk", 20, "", 0, it[3]
    end,
    GetItemCount = function(id) return world.bags[id] or 0 end,
    GetItemNameByID = function(id) return ({ [2589] = "Linen Cloth", [2835] = "Rough Stone", [2840] = "Copper Bar", [2836] = "Coarse Stone" })[id] end }
Enum = { DamageMeterType = { DamageDone = 0, Dps = 1, HealingDone = 2, DamageTaken = 7, Deaths = 9, EnemyDamageTaken = 10 },
    DamageMeterSessionType = { Overall = 0, Current = 1, Expired = 2 },
    SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
    SpellBookSpellBank = { Player = 0, Pet = 1 }, TooltipDataType = { Item = 0, Unit = 2 } }

-- built-in damage meter ------------------------------------------------------------
local dmSessions = { { sessionID = 83, name = "Old Boar", durationSeconds = 20, dmg = 100, taken = 10, spells = { { 75, 100 } } } }
local function dmFind(id) for _, s in ipairs(dmSessions) do if s.sessionID == id then return s end end end
C_DamageMeter = {
    IsDamageMeterAvailable = function() return true end,
    GetAvailableCombatSessions = function()
        local out = {}
        for i, s in ipairs(dmSessions) do out[i] = { sessionID = hide(s.sessionID), name = hide(s.name), durationSeconds = hide(s.durationSeconds) } end
        return out
    end,
    GetCombatSessionFromID = function(id, kind)
        local s = dmFind(id); if not s then return nil end
        local me = { isLocalPlayer = true, name = hide("Tess Ter"), sourceGUID = hide("Player-1-0000ABCD"), classFilename = "HUNTER" }
        if kind == 0 then
            me.totalAmount = hide(s.dmg)
            local sources = { me }
            if s.petDmg then sources[2] = { isLocalPlayer = false, name = hide(world.pet or "Humar"), sourceGUID = hide("Pet-0-1"), totalAmount = hide(s.petDmg) } end
            return { durationSeconds = hide(s.durationSeconds), totalAmount = hide(s.dmg + (s.petDmg or 0)), combatSources = sources }
        elseif kind == 7 then me.totalAmount = hide(s.taken); return { totalAmount = hide(s.taken), combatSources = { me } }
        elseif kind == 2 then me.totalAmount = hide(s.healed or 0); return { totalAmount = hide(s.healed or 0), combatSources = (s.healed or 0) > 0 and { me } or {} }
        elseif kind == 10 then
            local src = {}; for i = 1, s.enemies or 1 do src[i] = { name = hide(s.name), totalAmount = hide(10) } end
            return { totalAmount = hide(s.dmg), combatSources = src }
        end
    end,
    GetCombatSessionSourceFromID = function(id, kind, guid)
        local s = dmFind(id); if not s or kind ~= 0 then return nil end
        local list = {}
        local src = guid == "Pet-0-1" and (s.petSpells or {}) or s.spells
        for i, sp in ipairs(src) do list[i] = { spellID = hide(sp[1]), totalAmount = hide(sp[2]), creatureName = hide("") } end
        return { combatSpells = list }
    end,
}

-- professions, recipes, trainer, spellbook, bars ---------------------------------------
local PROFS = { [7] = { "Mining", 136248, 50, 75 }, [8] = { "Engineering", 136243, 34, 75 }, [5] = { "First Aid", 135966, 15, 75 }, [6] = { "Cooking", 133971, 1, 75 } }
function GetProfessions() return 7, 8, 5, nil, 6 end
function GetProfessionInfo(i) local p = PROFS[i]; if p then return p[1], p[2], p[3], p[4], 2, 21, 186, 0 end end
local RECIPES = {
    [3918] = { name = "Rough Blasting Powder", diff = 0, trivial = 60, reagents = { { 2835, 1 } } },
    [3919] = { name = "Rough Dynamite", diff = 1, trivial = 90, reagents = { { 2835, 2 }, { 2589, 1 } } },
    [3920] = { name = "Crafted Light Shot", diff = 3, trivial = 30, reagents = { { 2840, 1 } } },
    [3921] = { name = "Handful of Copper Bolts", diff = 2, trivial = 45, reagents = { { 2840, 1 } } },
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
        return { recipeID = id, reagentSlotSchematics = slots }
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
function GetActionText(slot) if BARS[slot] and BARS[slot][1] == "macro" then return "Opener" end end
function GetMacroBody(name) return "#showtooltip\n/cast Hunter's Mark" end
MenuUtil = { CreateContextMenu = function(owner, gen)
    local root = { CreateTitle = function() end, CreateDivider = function() end,
        CreateButton = function(_, text, fn) MenuUtil.buttons[text] = fn end,
        CreateCheckbox = function(_, text, get, set) get(); MenuUtil.checks[text] = set end }
    gen(owner, root)
end, buttons = {}, checks = {} }

-- MODE=bare: a hostile client where the helpful APIs are missing and health never becomes readable
local MODE = os.getenv("MODE") or "full"
if MODE == "bare" then
    C_DamageMeter, C_TradeSkillUI, C_SpellBook, GetProfessions, GetProfessionInfo, MenuUtil = nil, nil, nil, nil, nil, nil
    GetActionInfo, GetNumTrainerServices, C_Item, issecretvalue_real = nil, nil, nil, issecretvalue
    C_AuctionHouse, TooltipDataProcessor, hooksecurefunc, GetNormalizedRealmName, DearLordAuctionDB = nil, nil, nil, nil, nil
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
    for _, key in ipairs({ "stats", "xp" }) do
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
            io.write("   " .. strip(f.left.text) .. right .. "\n")
        end
    end
end

local nextSession = 100
local function runFight(o)
    world.targetLevel, world.targetName = o.mobLevel or world.level, o.name
    world.combat = true
    world.threat = {}
    for i = 1, o.mobs or 1 do world.threat["nameplate" .. i] = "Creature-0-" .. nextSession .. "-" .. i end
    world.threat.target = world.threat.nameplate1
    fire("PLAYER_REGEN_DISABLED")
    for i = 1, o.mobs or 1 do fire("UNIT_THREAT_LIST_UPDATE", "nameplate" .. i) end
    for _, c in ipairs(o.casts or {}) do
        fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-" .. now .. c, c)
        advance(0.25)
        fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. (now - 0.25) .. c, c)
        advance(1.5)
    end
    fire("UNIT_COMBAT", "player", "WOUND", "", o.taken, 1)
    fire("UNIT_COMBAT", "target", "WOUND", "", o.dmg, 1)
    for _ = 1, o.oom or 0 do fire("UI_ERROR_MESSAGE", 50, "Not enough mana") end
    advance(o.duration or 12)
    world.hp = math.max(0, world.hp - o.taken); world.mana = math.max(0, world.mana - (o.manaUsed or 40))
    if o.die then world.hp = 0; fire("PLAYER_DEAD") end
    nextSession = nextSession + 1
    dmSessions[#dmSessions + 1] = { sessionID = nextSession, name = o.name or "Mob", durationSeconds = o.duration or 12, dmg = o.dmg, taken = o.taken,
        healed = o.healed, enemies = o.mobs or 1, spells = o.spells or { { 75, o.dmg } }, petDmg = o.petDmg, petSpells = o.petSpells }
    world.combat = false; world.threat = {}
    fire("PLAYER_REGEN_ENABLED")
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
runFight({ name = "Kolkar Outrunner", mobs = 2, kills = 2, dmg = 300, taken = 150, duration = 31, oom = 2, casts = { 3044 }, spells = { { 75, 180 }, { 3044, 120 } } })
hud("after fight 2 (two mobs, ran out of mana, close call)")
world.hp = 175; world.mana = 120; world.pet = "Humar"; fire("UNIT_PET", "player")
advance(15)
runFight({ name = "Dire Mottled Boar", dmg = 120, petDmg = 90, petSpells = { { 17253, 60 }, { 16827, 30 } }, taken = 20, duration = 14, spells = { { 75, 120 } } })
hud("after fight 3 (with a pet)")
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
runFight({ name = "Razormane Hunter", mobLevel = 10, dmg = 200, taken = 120, duration = 20 }); world.hp = 175
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
    GameTooltip.lines = {}; hook(GameTooltip, { id = 783, dataInstanceID = 11 }); tipLines = { unpack(GameTooltip.lines) }
    hook(GameTooltip, { id = 783, dataInstanceID = 11 }); tipDup = #GameTooltip.lines
    GameTooltip.lines = {}; hook(GameTooltip, { id = 9999, dataInstanceID = 12 }); local tipUnknown = #GameTooltip.lines
    GameTooltip.forbidden = true; hook(GameTooltip, { id = 783, dataInstanceID = 13 }); local tipForbidden = #GameTooltip.lines; GameTooltip.forbidden = false
    ns.db.ahTooltip = false; hook(GameTooltip, { id = 783, dataInstanceID = 14 }); tipOff = #GameTooltip.lines; ns.db.ahTooltip = true
    GameTooltip:SetBagItem(0, 2); hook(GameTooltip, { id = 783, dataInstanceID = 15 }); tipStack = { unpack(GameTooltip.lines) }
    world.alt = true; GameTooltip.lines = {}; GameTooltip.dlsAhStack = nil; hook(GameTooltip, { id = 783, dataInstanceID = 16 }); scanResult.tipAlt = { unpack(GameTooltip.lines) }; world.alt = false
    fire("MODIFIER_STATE_CHANGED", "LALT", 1)
    scanResult.unknownAndForbidden = tipUnknown == 0 and tipForbidden == 0
    fire("AUCTION_HOUSE_SHOW"); advance(3)                       -- the server answers a moment later
    fire("REPLICATE_ITEM_LIST_UPDATE"); advance(2)
    scanResult.requests = C_AuctionHouse.requests
    scanResult.stone = ns.AuctionPrice("|Hitem:2835::|h[Rough Stone]|h")
    scanResult.realm = DearLordAuctionDB.realms["ClassicBetaPvE2-Horde"]
    fire("AUCTION_HOUSE_CLOSED"); fire("AUCTION_HOUSE_SHOW"); advance(3)
    scanResult.requestsAfterSecondOpen = C_AuctionHouse.requests
    printed = {}; SlashCmdList["DEARLORDSTATS"]("scan"); scanResult.throttleMsg = printed[1] or ""
    SlashCmdList["DEARLORDSTATS"]("scan force"); advance(1); fire("REPLICATE_ITEM_LIST_UPDATE"); advance(2); scanResult.requestsAfterForce = C_AuctionHouse.requests
    fire("AUCTION_HOUSE_CLOSED")
    -- a goblin auction house: neutral, shared by both factions, scanned into its own key
    world.npc, world.npcFaction = true, nil
    fire("AUCTION_HOUSE_SHOW"); SlashCmdList["DEARLORDSTATS"]("scan force"); advance(1); fire("REPLICATE_ITEM_LIST_UPDATE"); advance(2)
    scanResult.neutral = DearLordAuctionDB.realms["ClassicBetaPvE2-Neutral"]
    GameTooltip.lines = {}; hook(GameTooltip, { id = 2835, dataInstanceID = 17 }); scanResult.tipNeutral = { unpack(GameTooltip.lines) }
    fire("AUCTION_HOUSE_CLOSED"); world.npc = nil
end

-- every tab and scope of the report, plus menu, tooltips, clicks
for _, key in ipairs({ "stats", "xp" }) do
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
for _, f in ipairs(frames) do if rawget(f, "onClick") and f.shown then f.onClick(); break end end
panelText("Combat / level after stepping back")
ns.OpenPanel("abilities"); panelText("Abilities (level view carried over)")
ns.OpenPanel("professions"); panelText("Professions")
ns.OpenPanel("loot"); panelText("Loot")
ns.ResetLoot(); ns.OpenPanel("loot"); panelText("Loot after reset")
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
ns.OpenPanel("summary"); advance(3)
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
    if f.scripts.OnEnter and f ~= ns.huds.stats and f ~= ns.huds.xp then pcall(f.scripts.OnEnter, f); if f.scripts.OnLeave then pcall(f.scripts.OnLeave, f) end end
end
for _, cmd in ipairs({ "", "", "levels", "summary", "recap", "recap", "nudges", "nudges", "size 14", "scale 1", "alpha 1", "bg", "bg", "lock", "lock", "errors", "help" }) do
    SlashCmdList["DEARLORDSTATS"](cmd)
end
io.write("\n-- summary (this character)\n" .. ns.SummaryText(false) .. "\n")

-- reload keeps the session, a fresh login starts a new one
fire("PLAYER_ENTERING_WORLD", false, true); advance(2)
local kept = ns.session.combat.fights
fire("PLAYER_ENTERING_WORLD", true, false); advance(2)

io.write("\n-- chat output\n")
for _, l in ipairs(printed) do io.write("   " .. strip(l) .. "\n") end
io.write("\n-- everything the feed showed, in order\n")
for _, l in ipairs(feedLog) do io.write("   " .. strip(l) .. "\n") end
io.write("\n-- checks\n")
local function check(name, ok) io.write(string.format("   [%s] %s\n", ok and "ok" or "FAIL", name)); if not ok then os.exit_code = 1 end end
local c = ns.char.combat
if MODE == "bare" then
    check("no internal errors logged", #(ns.db.errors or {}) == 0)
    check("6 fights recorded from live hit events alone", c.fights == 6 and ns.db.diag.fightsFromMeter == 0)
    check("damage taken still known (64+150+20+175+120+130)", c.taken == 659)
    check("note saved", #ns.char.journal == 1)
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
check("pet damage counted (90)", c.petDmg == 90)
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
    check("tooltip: vendor row then AH row with seen/age (" .. norm(tipLines[2]) .. ")", #tipLines == 3 and norm(tipLines[1]) == "Vendor 50c |" and norm(tipLines[2]) == "AH 2s 50c |" and norm(tipLines[3]) == "19 seen · 2 days ago")
    check("tooltip: same data twice adds no second line; unknown item, forbidden tooltip and setting off add none", tipDup == 3 and scanResult.unknownAndForbidden and tipOff == 0)
    check("tooltip: a stack of 2 shows the totals on both rows (" .. tostring(tipStack[2]) .. ")", #tipStack == 3 and norm(tipStack[1]) == "Vendor 50c · ×2 1s 0c |" and norm(tipStack[2]) == "AH 2s 50c · ×2 5s 0c |")
    local r = scanResult.realm
    check("scan: auto scan on AH open commits 4 items from 6 auctions, Rough Stone at 3c", scanResult.requests == 1 and scanResult.stone == 3 and r and r.count == 4 and r.auctions == 6 and r.scanned)
    check("scan: seen counts and history (Light Hide 3 units, 250 kept as min, history has two days)", r and r.items[783].n == 3 and r.items[783].p == 250 and select(2, r.items[783].h:gsub(":", "")) == 2)
    check("scan: second AH open within 15 min does not request again; /dls scan explains; force scans", scanResult.requestsAfterSecondOpen == 1 and scanResult.throttleMsg:find("next scan possible") and scanResult.requestsAfterForce == 2)
    local feedHit = false; for _, l in ipairs(feedLog) do if strip(l):find("Auction scan  4 items", 1, true) then feedHit = true end end
    check("scan: feed line announces the result", feedHit)
    check("tooltip: holding Alt adds the other faction's line (" .. tostring(scanResult.tipAlt[3]) .. ")", #scanResult.tipAlt == 5 and norm(scanResult.tipAlt[3]) == "Alliance AH 3s 0c |" and norm(scanResult.tipAlt[5]) == "Alliance: 7 seen · yesterday")
    check("neutral AH: scan at a goblin auctioneer lands under the Neutral key and shows in tooltips (" .. tostring(scanResult.tipNeutral[2]) .. ")",
        scanResult.neutral and scanResult.neutral.count == 4 and #scanResult.tipNeutral == 5 and norm(scanResult.tipNeutral[3]) == "Neutral AH 3c |" and norm(scanResult.tipNeutral[5]) == "Neutral: 10 seen · today")
else
    check("loot: no auction data in a bare client, view still works", lootView and not lootView.hasAH and lootView.ahGain == 0 and ns.BagsForAuction() == nil)
end
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
if #(ns.db.errors or {}) > 0 then
    io.write("\n-- INTERNAL ERRORS\n")
    for _, e in ipairs(ns.db.errors) do io.write("   x" .. e.count .. " [" .. e.where .. "] " .. e.msg .. "\n") end
end
os.exit(os.exit_code or 0)
