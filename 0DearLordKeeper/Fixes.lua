-- 0DearLordKeeper : small fixes for other addons on this client
-- Each entry runs once, right after the named addon's files have loaded and before that addon's own
-- ADDON_LOADED handler runs (this addon registered for the event first). Keep them tiny; a fix
-- returns a string to say why it did nothing, nil when it was applied.
local ADDON = ...

DearLordKeeper_Fixes = {
    { addon = "Auctionator", name = "Auctionator: one price database per faction",
      -- Forever has separate Horde and Alliance auction houses (checked in the beta: an auction posted
      -- on one side is not found on the other). Auctionator treats the client like retail and keeps
      -- one price database per realm, so a scan on either side overwrites the other side's prices.
      -- This appends the faction to the database key, the way Auctionator itself does on Classic.
      apply = function(say)
          local V = Auctionator and Auctionator.Variables
          local C = Auctionator and Auctionator.Constants
          if not (V and type(V.GetConnectedRealmRoot) == "function") then return "Auctionator API not found" end
          if C and C.IsForever == false then return "not the Forever client" end
          if V.dearlordFactionKey then return end
          local original = V.GetConnectedRealmRoot
          V.GetConnectedRealmRoot = function(...)
              local root = original(...)
              local faction = UnitFactionGroup and UnitFactionGroup("player")
              if type(root) ~= "string" or (faction ~= "Horde" and faction ~= "Alliance") then return root end
              local key = root .. " " .. faction
              local db = AUCTIONATOR_PRICE_DATABASE
              if type(db) == "table" and db[key] == nil and db[root] ~= nil then
                  db[key], db[root] = db[root], nil        -- prices from before the fix: the first faction to log in keeps them
                  say("Auctionator prices scanned before the faction fix now belong to the " .. faction .. ".")
              end
              return key
          end
          V.dearlordFactionKey = true
      end },
}
