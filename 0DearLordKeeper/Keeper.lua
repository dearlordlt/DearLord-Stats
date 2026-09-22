-- 0DearLordKeeper 2.0
-- The WoW: Forever beta client (build 69913) writes every addon's saved variables at logout and
-- hands nothing back at load. Two things DO survive, and this addon uses both:
--   1. console variables registered by an addon live in the game's memory across /reload
--      -> at logout every declared saved variable is serialised into them; at login it is put back
--   2. addon CODE files are loaded normally, and the saved files on disk are written correctly
--      -> the companion script `wow-keeper-sync` (outside the game) turns those saved files into
--         Restore.lua, which puts the values back after a full game restart
-- It loads before every other addon (the folder name starts with a digit; "!" does not sort first
-- on this client), so other addons find their variables already in place. Once Blizzard fixes the
-- client, its own loading happens afterwards and simply wins.
local ADDON = ...
local VERSION = "2.1.0"
local CHUNK, MAX_TOTAL, MAX_VAR = 15000, 900000, 400000
local PREFIX = "dearlordKeeperChunk"
local INDEX = "dearlordKeeperIndex"

local C = C_CVar or {}
local Register, Get, Set = C.RegisterCVar or RegisterCVar, C.GetCVar or GetCVar, C.SetCVar or SetCVar
local issecret = type(issecretvalue) == "function" and issecretvalue or function() return false end
local declared = DearLordKeeper_Declared or { account = {}, perchar = {} }
local status = { version = VERSION, fromDisk = {}, fromMemory = {}, skipped = {}, errors = {}, fixes = {}, fixesSkipped = {} }

local function say(msg) print("|cff9ecbffDearLord Keeper:|r " .. msg) end
local function charKey() return ((UnitName and UnitName("player")) or "?"):gsub(" ", "-") end

----------------------------------------------------------------------
-- serialiser: plain Lua source, read back with loadstring in an empty environment
----------------------------------------------------------------------
local function serialise(value, out, seen, depth)
    local t = type(value)
    if issecret(value) then out[#out + 1] = "nil"
    elseif t == "table" then
        if seen[value] or depth > 60 then out[#out + 1] = "nil"; return end      -- cycles and absurd depth are dropped
        seen[value] = true
        out[#out + 1] = "{"
        for k, v in pairs(value) do
            local kt, vt = type(k), type(v)
            if (kt == "string" or kt == "number" or kt == "boolean") and (vt == "table" or vt == "string" or vt == "number" or vt == "boolean") and not issecret(k) then
                if kt == "string" then out[#out + 1] = "[" .. string.format("%q", k) .. "]="
                else out[#out + 1] = "[" .. tostring(k) .. "]=" end
                serialise(v, out, seen, depth + 1)
                out[#out + 1] = ","
            end
        end
        out[#out + 1] = "}"
        seen[value] = nil
    elseif t == "string" then out[#out + 1] = (string.format("%q", value):gsub("[\128-\255]", function(c) return "\\" .. c:byte() end))   -- binary-safe: bytes >= 0x80 as \ddd
    elseif t == "number" then
        if value ~= value or value == math.huge or value == -math.huge then out[#out + 1] = "0"
        elseif value == math.floor(value) and math.abs(value) < 1e15 then out[#out + 1] = string.format("%d", value)
        else out[#out + 1] = string.format("%.17g", value) end
    elseif t == "boolean" then out[#out + 1] = tostring(value)
    else out[#out + 1] = "nil" end
end
local function toSource(value) local out = {}; serialise(value, out, {}, 0); return table.concat(out) end
local function fromSource(text)
    local fn = loadstring("return " .. text)
    if not fn then return nil end
    setfenv(fn, {})
    local ok, value = pcall(fn)
    return ok and value or nil
end

----------------------------------------------------------------------
-- memory layer (survives /reload)
----------------------------------------------------------------------
local function cvar(name) if Register then pcall(Register, name, "") end end
local function readMemory()
    if not (Get and Set) then return nil end
    cvar(INDEX)
    local ok, index = pcall(Get, INDEX)
    local count = ok and tonumber((tostring(index or ""):match("^v1;(%d+)")))
    if not count or count == 0 then return nil end
    local parts = {}
    for i = 1, count do
        local name = PREFIX .. i
        cvar(name)
        local ok2, part = pcall(Get, name)
        if not ok2 or type(part) ~= "string" then return nil end
        parts[i] = part
    end
    return fromSource(table.concat(parts))
end
local function writeMemory(data)
    if not (Get and Set) then return 0 end
    local text = toSource(data)
    local count = math.ceil(#text / CHUNK)
    cvar(INDEX)
    local okOld, old = pcall(Get, INDEX)
    local oldCount = okOld and tonumber((tostring(old or ""):match("^v1;(%d+)"))) or 0
    for i = 1, count do
        local name = PREFIX .. i
        cvar(name); pcall(Set, name, text:sub((i - 1) * CHUNK + 1, i * CHUNK))
    end
    for i = count + 1, oldCount do cvar(PREFIX .. i); pcall(Set, PREFIX .. i, "") end     -- clear leftovers
    pcall(Set, INDEX, "v1;" .. count .. ";" .. time())
    return #text
end

----------------------------------------------------------------------
-- restore at login, snapshot at logout
----------------------------------------------------------------------
local function restore()
    local me = charKey()
    -- layer 2 first: values generated from the saved files on disk (fresh after a game restart)
    local R = DearLordKeeper_Restore
    if type(R) == "table" then
        status.diskGenerated = R.generated
        for addon, fn in pairs(R.account or {}) do
            if pcall(fn) then status.fromDisk[#status.fromDisk + 1] = addon else status.errors[#status.errors + 1] = "disk:" .. addon end
        end
        for addon, fn in pairs((R.perchar or {})[me] or {}) do
            if pcall(fn) then status.fromDisk[#status.fromDisk + 1] = addon .. "(char)" else status.errors[#status.errors + 1] = "diskchar:" .. addon end
        end
    end
    -- layer 1 on top: the in-memory copy from the logout a moment ago (always at least as fresh)
    local mem = readMemory()
    if type(mem) == "table" then
        status.memorySavedAt = mem.savedAt
        for var, value in pairs(mem.account or {}) do _G[var] = value; status.fromMemory[#status.fromMemory + 1] = var end
        for var, value in pairs((mem.perchar or {})[me] or {}) do _G[var] = value; status.fromMemory[#status.fromMemory + 1] = var .. "(char)" end
    end
end

local function snapshot()
    local me = charKey()
    local previous = readMemory()
    local data = { savedAt = time(), account = {}, perchar = (type(previous) == "table" and previous.perchar) or {} }
    data.perchar[me] = {}
    local total = 0
    local function keep(bucket, var)
        local value = _G[var]
        if value == nil or var:find("^DearLordKeeper") then return end
        local size = #toSource(value)
        if size > MAX_VAR or total + size > MAX_TOTAL then status.skipped[#status.skipped + 1] = var .. " (" .. size .. " bytes)"; return end
        total = total + size
        bucket[var] = value
    end
    for var in pairs(declared.account or {}) do keep(data.account, var) end
    for var in pairs(declared.perchar or {}) do keep(data.perchar[me], var) end
    status.memoryBytes = writeMemory(data)
    status.savedAt = data.savedAt
    DearLordKeeperCharDB = { status = status }        -- the client writes this file, so it can be inspected from disk
end

-- fixes for other addons (Fixes.lua): applied when that addon's files have loaded
local function applyFixes(addon)
    for _, fix in ipairs(DearLordKeeper_Fixes or {}) do
        if fix.addon == addon and not fix.done then
            fix.done = true
            local ok, why = pcall(fix.apply, say)
            if not ok then status.errors[#status.errors + 1] = "fix " .. fix.name .. ": " .. tostring(why)
            elseif why then status.fixesSkipped[#status.fixesSkipped + 1] = fix.name .. " (" .. tostring(why) .. ")"
            else status.fixes[#status.fixes + 1] = fix.name end
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON then
            local ok, err = pcall(restore)
            if not ok then status.errors[#status.errors + 1] = "restore: " .. tostring(err) end
        end
        applyFixes(name)
    else
        local ok, err = pcall(snapshot)
        if not ok then DearLordKeeperCharDB = { status = status, error = tostring(err) } end
    end
end)

SLASH_DEARLORDKEEPER1 = "/keeper"
SlashCmdList["DEARLORDKEEPER"] = function()
    local nDeclared = 0
    for _ in pairs(declared.account or {}) do nDeclared = nDeclared + 1 end
    for _ in pairs(declared.perchar or {}) do nDeclared = nDeclared + 1 end
    say(string.format("v%s, watching %d saved variables of your addons", VERSION, nDeclared))
    say(string.format("handed back at this login: %d from memory (reload copy), %d addons from the disk copy", #status.fromMemory, #status.fromDisk))
    if #status.fixes > 0 then say("fixes applied: " .. table.concat(status.fixes, "; ")) end
    if #status.fixesSkipped > 0 then say("fixes not applied: " .. table.concat(status.fixesSkipped, "; ")) end
    if #status.errors > 0 then say("problems: " .. table.concat(status.errors, ", ")) end
    if #status.skipped > 0 then say("too large for the reload copy (still covered after a game restart): " .. table.concat(status.skipped, ", ")) end
end
