-- DearLord Stats 2.0 : right-click menu and slash commands
local ADDON, ns = ...

local function toggle(key, after)
    return function()
        ns.db[key] = not ns.db[key]
        if after then after() end
    end
end
local function resetLayout()
    local db, d = ns.db, ns.defaults
    for _, k in ipairs({ "stats", "xp", "panel" }) do db[k] = { point = d[k].point, x = d[k].x, y = d[k].y } end
    db.scale, db.alpha, db.fontSize = d.scale, d.alpha, d.fontSize
    db.panelSize = nil
    ns.ApplyHudSettings()
    ns.say("positions and look reset")
end
local function applyAndRefresh() ns.ApplyHudSettings(); if ns.RefreshXP then ns.RefreshXP() end end

local ITEMS = {
    { text = "Open report", fn = function() ns.OpenPanel() end },
    { text = "Add a note…", fn = function() ns.OpenPanel("journal") end },
    { text = "Reset session", fn = function() ns.ResetSession() end },
    { text = "Print level log", fn = function() ns.PrintLevelLog() end },
    { divider = true },
    { text = "Show XP window", key = "showXP", after = applyAndRefresh },
    { text = "Fight recap after combat", key = "showRecap" },
    { text = "Gentle reminders", key = "nudges" },
    { text = "Dark background", key = "background", after = applyAndRefresh },
    { text = "Lock windows", key = "locked" },
    { divider = true },
    { text = "Reset positions", fn = resetLayout },
}

local legacy
function ns.ShowMenu(owner)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root)
            root:CreateTitle("DearLord Stats")
            for _, item in ipairs(ITEMS) do
                if item.divider then
                    if root.CreateDivider then root:CreateDivider() end
                elseif item.key then
                    root:CreateCheckbox(item.text, function() return ns.db[item.key] end, toggle(item.key, item.after))
                else
                    root:CreateButton(item.text, item.fn)
                end
            end
        end)
        return
    end
    if not (UIDropDownMenu_Initialize and ToggleDropDownMenu) then return end
    if not legacy then
        legacy = CreateFrame("Frame", "DearLordStatsMenu", UIParent, "UIDropDownMenuTemplate")
        UIDropDownMenu_Initialize(legacy, function()
            for _, item in ipairs(ITEMS) do
                if not item.divider then
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = item.text
                    if item.key then info.checked, info.isNotRadio, info.func = ns.db[item.key], true, toggle(item.key, item.after)
                    else info.notCheckable, info.func = true, item.fn end
                    UIDropDownMenu_AddButton(info)
                end
            end
        end, "MENU")
    end
    ToggleDropDownMenu(1, nil, legacy, "cursor", 0, 0)
end

local HELP = "/dls (report) | note <text> | levels | summary | resetxp | lock | xp | recap | nudges | bg | size <9-24> | scale <0.5-3> | alpha <0.2-1> | reset | errors"

SLASH_DEARLORDSTATS1 = "/dls"
SLASH_DEARLORDSTATS2 = "/dearlordstats"
SlashCmdList["DEARLORDSTATS"] = function(msg)
    ns.safe("slash", function()
        local raw = msg or ""
        local cmd, arg = raw:match("^(%S*)%s*(.-)$")
        cmd = (cmd or ""):lower()
        local db = ns.db
        if cmd == "" then ns.TogglePanel()
        elseif cmd == "note" then
            if ns.AddNote(arg) then ns.say("noted") else ns.OpenPanel("journal") end
        elseif cmd == "levels" or cmd == "log" then ns.PrintLevelLog()
        elseif cmd == "summary" then ns.OpenPanel("summary")
        elseif cmd == "resetxp" or cmd == "session" then ns.ResetSession()
        elseif cmd == "lock" then db.locked = not db.locked; ns.say(db.locked and "locked" or "unlocked")
        elseif cmd == "xp" then db.showXP = not db.showXP; applyAndRefresh()
        elseif cmd == "recap" then db.showRecap = not db.showRecap; ns.say("fight recap " .. (db.showRecap and "on" or "off"))
        elseif cmd == "nudges" then db.nudges = not db.nudges; ns.say("reminders " .. (db.nudges and "on" or "off"))
        elseif cmd == "bg" then db.background = not db.background; applyAndRefresh()
        elseif cmd == "reset" then resetLayout()
        elseif cmd == "size" and tonumber(arg) then db.fontSize = math.min(24, math.max(9, math.floor(tonumber(arg)))); applyAndRefresh()
        elseif cmd == "scale" and tonumber(arg) then db.scale = math.min(3, math.max(0.5, tonumber(arg))); applyAndRefresh()
        elseif cmd == "alpha" and tonumber(arg) then db.alpha = math.min(1, math.max(0.2, tonumber(arg))); applyAndRefresh()
        elseif cmd == "errors" then
            local errs = db.errors or {}
            if #errs == 0 then ns.say("no errors logged") return end
            ns.say(#errs .. " logged error(s), newest last:")
            for i = math.max(1, #errs - 4), #errs do print("   x" .. errs[i].count .. " [" .. errs[i].where .. "] " .. (errs[i].msg:match("^[^\n]*") or "")) end
        else ns.say(HELP) end
    end)
end
