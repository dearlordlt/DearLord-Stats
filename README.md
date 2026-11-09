# DearLord Stats

A quiet HUD and report addon for **World of Warcraft: Forever** (interface 16001).

Built for trying out classes and professions while levelling: it answers "how does this class
actually feel" rather than "how fast can I go".

## What is in here

| Folder | What it is |
| --- | --- |
| `DearLordStats/` | The addon. Copy it to `World of Warcraft/_forever_/Interface/AddOns/`, then start the game. |
| `test/` | A simulated Forever client, so the addon can be tested with plain `lua5.1`. |
| `docs/` | Notes on what the Forever client does and does not allow addons to do. |

## DearLord Stats

On screen, always: two small transparent text blocks you can drag anywhere.

- **Latency, measured spell lag, FPS.** The game's latency number refreshes every ~30 s; the `lag`
  value is measured on your own casts and updates live.
- **XP per hour, last gain, kills and quests to level (rested-aware), time to level, gold per hour.**

On screen, only when relevant: a one-line **fight recap** after combat, a profession line while you
gather or craft, a **hunter pet line** (pet level, progress, kills to its next level, happiness) while
your pet is out, and gentle one-line reminders (a new spell that is not on your bars, skill-ups you
could craft from your bags, a trainer unlock you reached). They fade out by themselves; left-click
opens the matching report tab, right-click dismisses.

The report (`/dls`, or click either text block; resizable, Escape closes):

- **Combat**: time per kill, dps with pet share, time in combat, rest between pulls, health pool lost
  per fight, close calls, out-of-resource fights, deaths. By session, by level (a button for every level: the current one, the last one, any older one), or in total,
  and split by pull size, by level, by mob level relative to yours, by zone, plus toughest opponents.
- **Abilities**: where your damage comes from (pet abilities listed separately), spells you learned
  that are on no action bar.
- **Professions**: skill-ups this session, what you can craft *right now* from your bags for points
  (orange / yellow / green), a rough shopping list to the next milestone, remembered trainer unlocks,
  gathering by zone, nodes your skill was too low for.
- **Economy** (was Loot), three views:
  - **Advice**: ways to earn gold, built only from real numbers: your auction scans, this character's
    recipes and gathering skills, your bags, what vendors pay, and the prices of vendors you have talked
    to. Anything without a price is left out rather than guessed. The top strip shows gold per hour,
    session net, and what your bags are worth at a vendor and at their best.
    - *Sell from your bags*: stacks that earn at least 50c and 15% more on the auction house than at a
      vendor, with the stack split most sellers use (`Light Leather ×23 as 2×10 + 3`), plus one line for
      everything a vendor should get.
    - *Craft for profit*: recipes whose product sells for more than its materials cost, sold to the
      auction house **or a vendor**, whichever pays more. Materials count at the cheaper of their lowest
      auction and a vendor you met. Shows how many you can make from your bags and flags skill-ups.
      Open each profession window once after updating, so the addon learns what every recipe makes.
    - *Gather*: what your gathering skills collect (and anything you have gathered), ranked by the value
      of a stack, with the move against the median of earlier scan days.
    - *Vendor flips*: items a vendor you met sells for well under what the auction house pays.
    - *Bargains*: auctions listed below what a vendor pays for the item (today's or yesterday's scan).
    Hover a hint for the numbers behind it, click it for the item's price history, right-click to hide
    it (Settings brings hidden hints back).
  - **Session**: looted coin, vendor value (and how much of it is junk), worth with the auction house,
    per hour, drops by quality, the most valuable stacks, notable drops. Has its own reset.
  - **History**: one line per earlier loot session, with the total and the average per hour.
- **Auction prices**: the addon scans the auction house itself: click **Scan prices** under the
  auction house window (it shows the progress; keep the window open until it is done, about 10
  seconds), or type `/dls scan`. Settings can make it start on your first key press at the auction
  house instead (once every 15 minutes for the whole account, the game's limit, shared with other
  addons: an Auctionator Full Scan counts, and the list it brings in is read here too) and remembers the lowest and median buyout per item and the
  stack size most sellers use, per realm and faction (Horde and Alliance auction houses are separate on
  Forever; goblin houses are neutral). The price shows in item tooltips as `Horde AH 9s 31c` plus
  `Horde: 19 seen · 2 days ago`, with the stack total when you hover a stack. Every house you have
  scanned is listed: yours, the other faction's (by default always; Settings can tie it to Alt, Shift or
  Ctrl) and the neutral one. A trend (`+12%` / `-8%`) shows how the lowest buyout moved since the
  previous scan day. The **Prices** tab starts with one line for the scans (each house's age, and Scan
  now), then a browser: search by name across every house, one labelled column per house, click an item
  for a table of every house (lowest, median, units up, trend, age, and what a vendor pays) and a line
  chart per house, green where the price rose and red where it fell. Both the tooltip line and the
  automatic scan can be switched off in Settings.
- The report follows its window: drag the corner wider and sections sit side by side in two or three
  columns (Economy, Combat, Abilities, Professions, price histories), so more fits without scrolling.
  Lists that grow over time (price histories, loot sessions, levels, zones, deaths, notes, reminders,
  hints) start collapsed to their first entries; "show all" on the header shows everything.
- **Census**: counts the players of your realm, each character once, and shows class shares, a race ×
  class grid, the level spread, the biggest guilds and the busiest zones, filtered by faction, level
  range and how recently they were seen. It fills in by itself: every player you see (mouseover,
  target, nameplates, your group) is counted, and now and then a `/who` goes out while you are pressing
  keys anyway (the game only allows `/who` from a key press or click). Never in combat, never while you
  use the Who window, hidden from chat. The queries go one level at a time; a level that comes back
  with 50 names (the most `/who` returns) is split by class, then race, then zone, and whatever was
  checked longest ago goes next. A character seen again moves to its new level, guild and zone. If the
  game ever blocks the background `/who`, the addon says so once and keeps counting the players you
  see. Both parts can be switched off in Settings.
- **Journal**: `/dls note some thought`, stamped with level and zone.
- **Summary**: one page per character: name and class, tiles for played time, xp/hour, kills, quests,
  deaths and gold, time per level as bars, combat and safety, per-level and pull-size tables, where the
  damage comes from, professions, money and loot, highlights (toughest opponent, busiest zone, last
  death). All characters: totals and a roster. Copy text: the same as paste-ready plain text.
- **Settings**: HUD font, size, edge, opacity, scale and background; which lines are shown; how long the
  recap and reminders stay; drop announcements; report opacity and text size; resets.

Commands: `/dls`, `/dls settings`, `/dls economy`, `/dls loot`, `/dls census`, `/dls prices [name]`, `/dls scan [force]`, `/dls resetloot`, `/dls note <text>`, `/dls levels`, `/dls summary`, `/dls resetxp`, `/dls lock`,
`/dls size <9-24>`, `/dls scale`, `/dls alpha`, `/dls bg`, `/dls recap`, `/dls nudges`, `/dls reset`,
`/dls errors`. Right-click either text block for a menu.

Combat numbers come from the game's built-in damage meter (`C_DamageMeter`), read about a second
after each fight, because the combat log is forbidden to addons on this client. See
`docs/forever-client-notes.md`.

## Development

```bash
lua5.1 test/harness.lua DearLordStats             # simulated play-through, full client
MODE=bare lua5.1 test/harness.lua DearLordStats   # hostile client: helpful APIs missing, health never readable
./deploy.sh                                       # test, back up, install
```

The harness models the real client's rules (secret values that raise on any comparison, the forbidden
combat log, labels that refuse text before a font is set), because each of those caused a real bug
before the harness knew about it. The addon logs its own errors to `DearLordStatsDB.errors` and API
observations to `.diag`, so problems can be read from the saved-variables file on disk.
