-- End-to-end test of 0DearLordKeeper. Builds its own small Declared.lua / Restore.lua fixture, so it
-- needs no real game data:  lua5.1 test/keeper_test.lua 0DearLordKeeper
local dir = arg[1]
local DECLARED = [[DearLordKeeper_Declared = { account = { ["BagDB"] = "Bags", ["StatsDB"] = "Stats" }, perchar = { ["ChatCharDB"] = "Chat" } }]]
local RESTORE = [[
local R = { account = {}, perchar = {} }
R.generated = 1
R.account["Bags"] = function()
BagDB = { view = "category", nested = { a = 1, list = { 1, 2, 3 } } }
end
R.account["Stats"] = function()
StatsDB = { fights = 7 }
end
R.perchar["Tess-Ter"] = {}
R.perchar["Tess-Ter"]["Chat"] = function()
ChatCharDB = { channel = "trade" }
end
R.perchar["Someone-Else"] = { Chat = function() ChatCharDB = { channel = "WRONG CHARACTER" } end }
DearLordKeeper_Restore = R
]]
local CVARS = {}                                   -- the game's memory: survives "reload", cleared by "restart"
local function boot(tag, opts)
    BagDB, StatsDB, ChatCharDB = nil, nil, nil      -- a fresh Lua state
    DearLordKeeper_Declared, DearLordKeeper_Restore, DearLordKeeperCharDB = nil, nil, nil
    if opts.restart then CVARS = {} end
    local frames, out = {}, {}
    function CreateFrame() local fr = { scripts = {} }; function fr:RegisterEvent() end; function fr:UnregisterEvent() end
        function fr:SetScript(n, fn) self.scripts[n] = fn end; frames[#frames + 1] = fr; return fr end
    C_CVar = { RegisterCVar = function(n, d) if CVARS[n] == nil then CVARS[n] = d end end,
        GetCVar = function(n) return CVARS[n] end, SetCVar = function(n, v) CVARS[n] = v; return true end }
    SlashCmdList = {}; print = function(s) out[#out + 1] = s end; time = os.time
    UnitName = function() return "Tess Ter" end
    assert(loadstring(DECLARED))()
    if not opts.noDisk then assert(loadstring(RESTORE))() end
    assert(loadfile(dir .. "/Fixes.lua"))("0DearLordKeeper")
    assert(loadfile(dir .. "/Keeper.lua"))("0DearLordKeeper")
    frames[1].scripts.OnEvent(frames[1], "ADDON_LOADED", "0DearLordKeeper")
    if opts.otherAddons then opts.otherAddons(frames[1]) end
    if opts.clientFixed then StatsDB = { marker = "loaded-by-client" } end       -- the real loader runs later and wins
    local ok = opts.check()
    if opts.play then opts.play() end
    frames[1].scripts.OnEvent(frames[1], "PLAYER_LOGOUT")
    SlashCmdList["DEARLORDKEEPER"]("")
    io.write(("[%s] %s\n"):format(ok and "ok" or "FAIL", tag))
    for _, l in ipairs(out) do io.write("       " .. l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "\n") end
    if not ok then os.exit(1) end
end
boot("game restart: values come from the disk copy, only this character's per-character data", { restart = true,
    check = function() return BagDB and BagDB.nested.list[3] == 3 and StatsDB.fights == 7 and ChatCharDB.channel == "trade" end,
    play = function() StatsDB.fights = 42; BagDB.view = "one bag"; ChatCharDB.channel = "lfg"; BagDB.text = 'quotes " and\nnewlines' end })
boot("/reload: the in-memory copy carries what changed during play", {
    check = function() return StatsDB.fights == 42 and BagDB.view == "one bag" and ChatCharDB.channel == "lfg" and BagDB.text == 'quotes " and\nnewlines' end })
boot("/reload with no disk copy at all (memory layer alone)", { noDisk = true,
    check = function() return StatsDB and StatsDB.fights == 42 and ChatCharDB.channel == "lfg" end })
boot("fixed client: its own loading wins", { clientFixed = true, check = function() return StatsDB.marker == "loaded-by-client" end })
-- Auctionator fix: the price database key gets the faction, and data from before the fix goes to the first faction seen
local faction = "Horde"
boot("Auctionator: one price database per faction", {
    otherAddons = function(f)
        Auctionator = { Variables = { GetConnectedRealmRoot = function() return "Realm" end }, Constants = { IsForever = true } }
        AUCTIONATOR_PRICE_DATABASE = { __dbversion = 8, Realm = { ["3872"] = { m = 7500 } } }
        UnitFactionGroup = function() return faction end
        f.scripts.OnEvent(f, "ADDON_LOADED", "Auctionator")
    end,
    check = function()
        local db = AUCTIONATOR_PRICE_DATABASE
        local horde = Auctionator.Variables.GetConnectedRealmRoot()
        local claimed = horde == "Realm Horde" and db["Realm Horde"]["3872"].m == 7500 and db.Realm == nil
        faction = "Alliance"
        local alliance = Auctionator.Variables.GetConnectedRealmRoot()
        local separate = alliance == "Realm Alliance" and db["Realm Alliance"] == nil and db["Realm Horde"]["3872"].m == 7500
        faction = "Horde"
        return claimed and separate and Auctionator.Variables.GetConnectedRealmRoot() == "Realm Horde"
    end })
io.write("OK\n")
