# WoW: Forever beta, notes for addon authors

Observed on build 1.60.1.69913 (interface 16001), September 2026, with a probe addon and an
`strace` of the client during `/reload`. Things may change between beta builds.

## It is the modern engine

`WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`, game type `mainline`, with vanilla data. Present:
`C_SpellBook`, `C_TradeSkillUI`, `C_Item`, `C_Container`, `C_AddOns`, `MenuUtil`, `C_DamageMeter`,
`C_Secrets`. Absent: `GetSpellInfo`, `GetItemInfo`, `GetItemCount`, `GetSpellCooldown`,
`GetNumSkillLines`/`GetSkillLineInfo`, `GetTradeSkillInfo`, `GetCraftInfo`, `GetNumSpellTabs`,
`CombatLogGetCurrentEventInfo`. `GetProfessions`/`GetProfessionInfo` exist.

## The combat log is forbidden

`frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` (and `COMBAT_LOG_EVENT`) raises
`ADDON_ACTION_FORBIDDEN` and shows the "blocked from an action only available to the Blizzard UI"
popup, even inside `pcall`.

## Secret values

`issecretvalue` / `canaccessvalue` exist. For the player, `UnitHealth` and `UnitPower` were secret at
every moment sampled, in and out of combat. Spell cooldown fields and every number from
`C_DamageMeter` are secret while in combat. Any comparison or arithmetic on a secret raises
`attempt to compare ... (a secret number value, while execution tainted by ...)`, so test with
`issecretvalue` first. Readable throughout: `UnitHealthMax`, `UnitGUID`, `UnitName`,
`UnitThreatSituation`, `UNIT_COMBAT` amounts, chat messages, `UI_ERROR_MESSAGE`.

## The built-in damage meter is the way to get combat numbers

About a second after combat ends:

- `C_DamageMeter.GetAvailableCombatSessions()` -> `{ {sessionID, name (mob), durationSeconds}, ... }`
- `GetCombatSessionFromID(id, Enum.DamageMeterType.X)` -> `totalAmount`, `combatSources[]` with
  `isLocalPlayer`, `totalAmount`, `amountPerSecond`, `sourceGUID`; for `EnemyDamageTaken` the sources
  are the enemies (`sourceCreatureID`, `classification`)
- `GetCombatSessionSourceFromID(id, type, guid)` -> `combatSpells[]` with `spellID`, `totalAmount`,
  and `combatSpellDetails.isPet`

Types seen: `DamageDone 0, Dps 1, HealingDone 2, Hps 3, Absorbs 4, Interrupts 5, Dispels 6,
DamageTaken 7, AvoidableDamageTaken 8, Deaths 9, EnemyDamageTaken 10`. Session ids keep counting
across `/reload`.

## Smaller things that bit

- `FontString:SetText()` errors with "Font not set" unless `SetFont` was called first.
- The global-cooldown spell is `29515`; `61304` does not exist.
- `GetAddOnMetadata(addon, "SavedVariables")` returns nil, so an addon cannot discover what other
  addons declare.
- Addon load order ignores a leading `!`; a leading digit sorts first.
- Characters have names with a space ("First Family"). Per-character files are written under
  `WTF/Account/<account>/<realm id>/<First-Family>/`, while `AddOns.txt` lands under
  `<realm name>/<First>/`.

## Saved variables are written and never loaded (build 69913)

At logout the client writes account-wide and per-character saved variables correctly. At load it
gives addons nothing: the global is nil from `ADDON_LOADED` through `PLAYER_LOGOUT`.
`SavedVariablesMachine` files are not even written. The client does `stat` the per-character and
machine-wide files during loading, which is easy to mistake for loading them.

What does persist:

- values of console variables created with `C_CVar.RegisterCVar`, across `/reload` (process memory;
  16 KB per value worked; they are not written to `Config.wtf`)
- macros (server side), which is what the community addon WickKeeper uses
- addon code files, which is why generating a Lua file from the saved files works for restarts

## The auction house is per faction, and Auctionator does not know

An auction posted on the Horde AH is not found on the Alliance AH (checked in the beta on Sep 22,
2026; stock and prices differ too). Auctionator (build 339) detects Forever as its own game type and
uses its modern-AH code, which keeps one price database per realm, keyed
`GetNormalizedRealmName()` with no faction. A scan on either side overwrites the other side's
prices. The Keeper's `Fixes.lua` wraps `Auctionator.Variables.GetConnectedRealmRoot` at
Auctionator's `ADDON_LOADED` (the Keeper registered for the event first, so its handler runs before
Auctionator's own initialisation) and appends the faction, the way Auctionator does on Classic.
Prices scanned before the fix go to the first faction that logs in afterwards.
