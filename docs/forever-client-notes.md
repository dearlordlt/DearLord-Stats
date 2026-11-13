# WoW: Forever, notes for addon authors

Observed on the beta, builds 1.60.1.69913 to 70245 (interface 16001), September and October 2026,
with a probe addon and an `strace` of the client during `/reload`. The launch client is build 70790,
same interface number; these notes have not all been checked again on it.

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

## Absorb shields and buffs (launch client, November 2026)

`UnitGetTotalAbsorbs("player")` exists and was a secret value at every moment sampled, out of a fight
too. A status bar and `SetFormattedText` take it. Out of a fight `C_UnitAuras.GetAuraDataByIndex`
returns readable buffs, and a shield buff's `points[1]` followed what was left of the shield (44, then
30 after a hit), so it is the plain amount; this is inferred from what the shield bar showed, not
probed directly. In a fight `GetAuraDataByIndex("player", 1, "HELPFUL")` returned nothing at all and
`C_Secrets.ShouldAurasBeSecret()` returned true. `C_UnitAuras` also has `GetPlayerAuraBySpellID`,
`GetAuraDataByAuraInstanceID`, `GetAuraDuration`, `GetUnitAuraBySpellID` and `GetBuffDataByIndex`;
`C_Secrets` has `GetSpellAuraSecrecy`, `ShouldSpellAuraBeSecret`, `ShouldUnitAuraIndexBeSecret`,
`ShouldUnitAuraInstanceBeSecret` and `ShouldUnitAuraSlotBeSecret` (they take arguments; not tried).

## Windfury procs and hit amounts (launch client, November 2026)

A shaman's saved cast counts hold thousands of `UNIT_SPELLCAST_SUCCEEDED` casts and no Windfury attack
among them, while the damage meter lists the proc's damage under the spell `Windfury Weapon`. So a
proc sends no spellcast event, and during a fight the only trace is `UNIT_COMBAT` on the target.

`UNIT_COMBAT` for the target, sampled in a party (16 groups of hits, weapon enchant id 283 for
Windfury Weapon rank 1): the action (`WOUND`, `MISS`, `PARRY`) and the school (1) were readable, the
amount of every hit was not. This contradicts the beta note above for the target in a party; solo has
not been sampled since launch. Hits that came together were 0.01 to 0.29 s apart, which fits extra
attacks landing 0.15 to 0.3 s after the swing that set them off (inferred, the events name no source).
In those party fights, guessing procs from three melee results within 0.3 s agreed with the meter in
2 fights, missed Windfury damage in 11 and saw a proc without any in 3.

A second save (12 November 2026, addon 2.29.0, window widened to 0.45 s): 16 more groups of hits, all
in a party again, every amount hidden; hits together were up to 0.44 s apart. Over all fights so far
the proc guess agreed with the meter in 74, missed in 27 and was extra in 32. The meter's per-spell
total for `Windfury Weapon` was readable after every fight (117 fights), so the per-fight rating
works. Not one of 375 procs seen had a readable amount. Solo is still unsampled: the 16 sample slots
filled in the party first. From 2.29.1 hits alone and in a group are counted apart
(`diag.windfury.amounts`, `diag.windfury.solo`, `diag.windfury.fights.solo`), and `diag.feedFmt`
records whether `SetFormattedText` took the hidden amounts.

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

### Live values during a fight (from Details' code, build 20261109, not yet probed by us)

Details draws its bars on this client from `C_DamageMeter` alone and never registers the combat log
(`Details/Libs/DF/fw.lua` treats interface 16001 like 12.x). What its code relies on, and what the
DearLord Stats meter (2.30.0) therefore uses:

- `GetCombatSessionFromType(Enum.DamageMeterSessionType.Overall | Current, type)` and
  `GetCombatSessionSourceFromType(sessionType, type, guid, creatureID)`, beside the `...FromID` pair;
  `GetSessionDurationSeconds(sessionType)`; `ResetAllCombatSessions()`; event
  `DAMAGE_METER_COMBAT_SESSION_UPDATED(type, sessionID)` (and `DAMAGE_METER_RESET`).
- In a fight the session table is there, `combatSources[i]` comes sorted by the game, and
  `totalAmount`, `amountPerSecond`, `maxAmount`, `name`, `sourceGUID` are hidden. They can be shown:
  `StatusBar:SetMinMaxValues(0, max, Enum.StatusBarInterpolation.ExponentialEaseOut)` and
  `SetValue(v, interpolation)` take hidden numbers (and ease the bar), `AbbreviateNumbers(v)` returns a
  hidden text, `FontString:SetText` takes it. No sorting, summing or percent in Lua until the fight ends.
- Session fields: `maxAmount`, `durationSeconds`; source fields also `classFilename`, `specIconID`,
  `sourceCreatureID`, `classification`, `deathRecapID`, `deathTimeSeconds`; spell fields also
  `amountPerSecond`, `creatureName` (the pet or totem), `combatSpellDetails.unitName`.
- A creature source (an enemy, a pet listed on its own) is asked for with `guid = nil` and its
  `sourceCreatureID`. Targets of a player come from `EnemyDamageTaken`: each enemy's spell list, kept
  where `combatSpellDetails.unitName` is that player.
- Details shows another player's spells only once their GUID is readable. Whether the API accepts the
  hidden GUID handed straight back is not known; the addon tries it and records the answer in
  `diag.meter.hiddenGuid`.
- No hit counts, crits or overhealing exist in this API (Details switches those columns off).
- The meter code never tests a possibly hidden value for truth or compares it, not even with `nil`
  (`if v then`, `v or x`, `v == nil`): it asks `ns.exists(v)`, which calls `issecretvalue` first. The
  harness cannot catch such a slip (Lua 5.1 has no hook for a truth test), so this is kept by reading.

### Fight time: the game's clock runs longer than the combat flag (first look, 13 November 2026)

Details times a fight itself, from `PLAYER_REGEN_DISABLED` to `PLAYER_REGEN_ENABLED`
(`core/parser_nocleu1.lua`), and after the fight shows total / that time. The game's session stays
open a little longer, so numbers taken from the game's clock come out lower; the owner saw this as
"a few more ticks after the mob died" against Details. One fight from a screenshot (solo hunter,
479 damage, both meters at 0:08): the source's `amountPerSecond` was 59.9 (479 / 8.0), while the
spells' `amountPerSecond` were 20.9 for 180, 18.7 for 161 and 8.9 for 77, which is each amount / 8.61.
So within one finished session the per-source and per-spell rates use different times (inferred from
that one fight; which fields carry 8.0 and 8.61 has not been read directly).

From 2.32.0 the meter keeps its own fight clock by the combat flag, like Details: bars, sum,
breakdown, title and copy text all use amount / own time once the numbers are readable, and Total
subtracts the measured extra seconds. If own time and the game's differ by more than +2 / -6 s the
game's is used (joined late, or the session ran on). For about 3 s after combat, while the numbers
are still hidden, the bars are not redrawn, so they do not sink. `diag.meter.clock` keeps the last
12 fights as `id own=… game=…`, and `clockOverall` the game's overall time against the sum of its
session list.

What the addon records for the next read of the saved variables: `diag.meter` with `api`, `interp`,
`abbrev`, `events`, `liveDraws` / `readDraws`, `liveSolo` / `liveGroup` (which fields of the first
source were hidden), `hiddenGuid`, `classColor`, `fightById` (the Current session was empty after a
fight), `readError` / `tipError`, `chat`, `reset`.

## Smaller things that bit

- `FontString:SetText()` errors with "Font not set" unless `SetFont` was called first.
- The global-cooldown spell is `29515`; `61304` does not exist.
- `GetAddOnMetadata(addon, "SavedVariables")` returns nil, so an addon cannot discover what other
  addons declare.
- Addon load order ignores a leading `!`; a leading digit sorts first.
- Characters have names with a space ("First Family"). Per-character files are written under
  `WTF/Account/<account>/<realm id>/<First-Family>/`, while `AddOns.txt` lands under
  `<realm name>/<First>/`.

## Saved variables were not loaded on the beta

Beta build 69913 wrote saved variables at logout and gave addons nothing back at load. The launch
client is reported to have fixed this, so the workaround addon (0DearLordKeeper) was removed from
this repository; it is in the git history.

## The auction house is per faction, and Auctionator does not know

An auction posted on the Horde AH is not found on the Alliance AH (checked in the beta on Sep 22,
2026; stock and prices differ too). Auctionator (build 339) detects Forever as its own game type and
uses its modern-AH code, which keeps one price database per realm, keyed
`GetNormalizedRealmName()` with no faction. A scan on either side overwrites the other side's
prices. DearLord Stats keeps its own scan per realm and faction.

## Auction house API (as DearLord Stats uses it)

`C_AuctionHouse.ReplicateItems()` works while the auction house window is open, once every 15
minutes for the whole account, shared by every addon: a request two minutes after Auctionator's Full
Scan got no answer. The list that arrives is visible to every addon, whoever asked. On the launch client (build 70790) a request sent from a timer a few seconds
after the window opened went unanswered again and again, while Auctionator's, sent straight from its
button click, was answered; so DearLord Stats only asks from a key press or click, like `/who`. Not
proven to be a hardware-event rule, but that is what it looks like. The answer comes as `REPLICATE_ITEM_LIST_UPDATE`; the list has been seen to
arrive well after 30 seconds, so the addon keeps listening until the window closes.
`GetReplicateItemInfo(i)` is 0-based and returns 18 values: count at 3, buyout at 10 and item id at
17. Buyouts are plain numbers, not secret values. A full Horde scan was about 60,000 auctions, read
in 11 seconds in chunks of 500 rows per frame. Goblin auctioneers, and the Skyborne one on Zephras
Isle, report no faction (or Neutral), so they are kept under `<Realm>-Neutral`.

`C_TradeSkillUI.GetRecipeSchematic(id, false)` includes `outputItemID`, `quantityMin` and
`quantityMax`. `GetAllRecipeIDs` also returns modern recipes the character has not learned, so the
`learned` flag has to be checked. The item vendor price is position 11 of `C_Item.GetItemInfo`, and
is nil until the item is cached.

## /who

`C_FriendList.SendWho` only works from a key press or click, and a hook on a player's own key press
counts. An answer holds at most 50 names. The client shows answers in its own `LFGWhoListFrame`, as
well as `FriendsFrame`, and opens it unless the frame stops listening to `WHO_LIST_UPDATE` while the
query runs. On the beta about 2,750 queries, one per 15 seconds, went through without being blocked.
