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

On screen, always: one small window you can drag anywhere.

- **XP window:** a slim top row with FPS, home and world latency, and the measured spell lag (the
  game's latency number refreshes every ~30 s; `lag` is measured on your own casts and updates live);
  a level bar with rested XP drawn on it, XP per hour, last gain, kills and quests to level
  (rested-aware), time to level; a pet block (portrait, XP bar coloured by happiness, loyalty,
  training points); net gold and gold per hour; a skill bar for the profession you are working on.

With a pet out or in a group: a **threat window** that opens with each fight and stays until you
close it with its x (the last fight's bars stay, dimmed). One bar per unit on the mob's threat
list: you and your pet when solo, the party and their pets in a dungeon, the top ten in a raid (always including you).
Bars are in class colours with class crests (pet portraits for pets), 100% means that unit pulls
aggro, the holder is marked `aggro`, and a coloured edge shows the state (green safe, yellow above
the tank, orange or red holding aggro). `/dls threat` shows or hides it, `/dls threat test` shows a
20-second preview to move it, `/dls threat off` turns it off. If the client hides threat numbers in a fight, the bars still
fill but are not sorted. When your own bar passes 90% while someone else holds aggro, the window's border pulses red, the
title reads "Ease off" and a warning sound plays once (level and sound in Settings). There is no warning while you are
the tank: the tank role, a warrior in Defensive Stance, a druid in bear form, or a paladin with
Righteous Fury on.

**Growl reminder** (hunters): grouped inside a dungeon or raid with Growl on autocast, or alone
in the world with it off, the pet line says so and a small banner offers the switch. Click its
text to run `/petautocastoff Growl` (or `on`), right-click to leave things as they are, drag its
icon to move it. The banner uses a secure button, so it appears and disappears only out of combat.

**Party targets**: beside each party member's frame, a small target frame for what that member is
targeting: name, health bar with percentage and a thin power bar (red for something you can attack,
class colour for a player, a white edge when it is your target too). A click targets it. Your own
frame and your pet's frame in the party frame get one too: your target, and what your pet is on (its
own switch in Settings). In a fight a badge at the frame's end shows your own threat on that target:
the percentage in the threat colours, or `aggro`. They follow the game's party frames, raid-style or
classic; Settings picks the side (right, left, below, above), the width and the height. Placing
happens out of combat, so after a change mid-fight they catch up when the fight ends.

**Party frame when alone** (Settings, off by default, experimental): with raid-style party frames,
keeps the party frame, and so your own frame in it, on screen when you are in no group. The game
hides that frame whenever you are alone; the addon shows it again, out of combat only.

**Ready check**: when you join a group, or walk into a dungeon or raid with one, a small banner lists
what you are missing: free bag slots, worn gear, food, water (classes with mana), ammunition, a pet
that is away, dead or unhappy (or a warlock's Voidwalker, which taunts off the tank), and what your class burns or wears: an Ankh, seeds for Rebirth,
candles, Arcane Powder, Symbols, Flash and Blinding Powder, soul shards, poisons on your weapons
(also when they are about to run out). A thing is only asked for when the character can have it: a
reagent when a spell that burns it is known, poisons once the rogue has learned Poisons or carries
some, ammunition once the character has carried any. The banner goes away when everything is in
order, or with a click; it never shows in a fight. `/dls ready` shows the whole list at any time.

**Shield bar**: a small bar of its own for the absorb shield on you, for any class and whoever cast
it: Power Word: Shield, Ice Barrier, Mana Shield, a ward, a Voidwalker's Sacrifice. It appears with
the shield and leaves with it, and shows what is left, of how much, with the shield's icon and the
seconds it still lasts. A shine runs across when a shield lands, each hit blinks and leaves a trail
that drains behind the fill, the border glows (red and quick under a quarter), and a shield that
breaks before its time shakes and flashes red, while one that runs out just fades. Move it in the
game's Edit Mode, where it shows itself with a running preview, or during `/dls shield`; elsewhere
clicks pass through it. Width, height, colour (by shield, or one of five), the numbers (left and
full, left, percent, none), icon, time, animations and a break sound are settings.

This client hides the absorb amount from addons at every moment, and all your buffs in a fight. Out
of a fight the buff itself says what is left, and the bar works from that. In a fight the bar and
its number follow the hidden amount (a status bar and a text may take one), and the whole bar is
drawn inside a box that the game itself opens while there is a point of shield and closes when
there is none, so a shield is neither lost nor shown after it is gone. Which shield it is comes
from the buff when readable, else from your own cast, else from what was up when the fight began,
else it is taken for the kind this character had last (then without the seconds); a character that
never had one sees the bar measured against its health. The full size is what was read at a fresh
cast out of a fight (else the spell rank's), so a shield met half used reads 30 / 44, not 30 / 30.
With no amount at all from the client the bar shows the time left.

**Client checks** (Summary > Client checks, or `/dls check`): one row per part of the addon that leans
on something a game patch can change (threat numbers, the Growl switch, keys on the cooldown manager,
auction scans and searches, vendor prices, recipes, pet details, the census, the ready check, the
shield bar), each marked works, limited, not working or not tried yet, with what the client actually
gave. It also lists protected actions the game refused the addon, by name.

**Keys on the cooldown manager:** the game's own cooldown manager shows your spells without their
keys. Each icon gets the key of the action bar slot that holds the spell (or a macro casting it),
shortened the way action buttons do: `R`, `c-5`, `s-WU`, `M4`.

On screen, only when relevant: a one-line **fight recap** after combat, a profession line while you
gather or craft, **hunter pet lines** (level, progress, kills to its next level, happiness, loyalty, unspent training points) while
your pet is out, and gentle one-line reminders (a new spell that is not on your bars, skill-ups you
could craft from your bags, a trainer unlock you reached). They fade out by themselves; left-click
opens the matching report tab, right-click dismisses.

**Windfury (shaman):** every proc of Windfury Weapon puts a line where the fight recap shows, in
larger letters, lit up as it lands and glowing for as long as it stays (15 s; size and time are
settings), ranked against every proc the character has had: `Windfury TOP 1 812 damage!` for the
top three, `Windfury top 14 412 damage` for the rest (the hundred biggest are kept), with the hits, crits and misses of that proc
beside it. The fight recap then counts them (`windfury ×2 best 612 (top 4)`), the Combat tab keeps the number
of procs, the biggest one and the biggest single hit, and `/dls windfury` lists the five biggest
(`/dls windfury test` shows three made-up ones). The combat log is closed to addons, so a proc is read
from the hits: the swing that set it off and the extra attacks land together, and three or more melee
results on your target within 0.3 s while Windfury is on the weapon count as one. The damage shown is
all of those hits added up. In a group someone else's swing landing in the same instant can be counted
in. After each fight the game's own damage meter says whether Windfury did damage, and the client
checks show how often the two agree.

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
      auction and a vendor you met. The product counts at its lowest buyout, but never above its usual
      price, so one odd listing does not promise a profit (vendor flips are valued the same way).
      Shows how many you can make from your bags and flags skill-ups.
      Open each profession window once after updating, so the addon learns what every recipe makes.
    - *Gather*: what your gathering skills collect (and anything you have gathered), ranked by the value
      of a stack, with the move against the item's usual price.
    - *Vendor flips*: items a vendor you met sells for well under what the auction house pays.
    - *Bargains*: auctions listed below what a vendor pays for the item (today's or yesterday's scan).
    Hover a hint for the numbers behind it, click it for the item's price history, right-click to hide
    it (Settings brings hidden hints back).
  - **Session**: looted coin, vendor value (and how much of it is junk), worth with the auction house,
    per hour, drops by quality, the most valuable stacks, notable drops. Has its own reset.
  - **History**: one line per earlier loot session, with the total and the average per hour.
- **Auction prices**: the addon scans the auction house itself: click **Scan prices** under the
  auction house window (it shows the progress; keep the window open until it is done, about 10
  seconds), or type `/dls scan`. A scan asked for while the auction house is busy (just opened, or in
  the middle of a search) waits until the house is free, so the request is not lost. Settings can make it start on your first key press at the auction
  house instead (once every 15 minutes for the whole account, the game's limit, shared with other
  addons: an Auctionator Full Scan counts, and the list it brings in is read here too) and remembers the lowest and median buyout per item and the
  stack size most sellers use, per realm and faction (Horde and Alliance auction houses are separate on
  Forever; goblin houses are neutral). Between scans the price of an item is brought up to date
  whenever the auction house shows its listings: placing it in the sell tab, clicking it in a search, or
  the search list itself. A complete listing replaces the stored price; a partial one can only lower it.
  Item tooltips show two labelled prices per house: `Horde AH lowest 9s 31c` with `19 seen · 5 min ago`
  beside it (the lowest buyout when the item was last scanned or seen), and under it
  `Horde AH usual 8s 0c`, the middle one of the last week's daily lows, so you can tell a normal day
  from a cheap or an expensive one; the usual row appears once three days are known. A stack shows its
  total, and a tooltip that is open while listings arrive is redrawn. Your own house is always
  shown; the neutral one and the other faction's appear while you hold Shift (Settings: Alt, Ctrl,
  always or never). On an ore the same key adds `Horde AH smelted 1s 60c` with the bar's name at the
  end of the row: what each ore sells for as bars (your own smelting recipe sets the ratio, otherwise
  the usual one), green when that beats selling the ore. The rows are set in real columns, and a
  stack gets a heading row (`each`, `all 6`) so it is plain which price is for one and which for the
  lot. Where a tooltip cannot hold real columns the rows are lined up with spaces instead, and the
  client checks say so. The **Prices** tab starts with one line for the scans (each house's age, and Scan
  now), then a browser: search by name across every house, one labelled column per house, click an item
  for a table of every house (lowest, median, units up, usual price, age, and what a vendor pays) and a line
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

Commands: `/dls`, `/dls settings`, `/dls economy`, `/dls loot`, `/dls census`, `/dls prices [name]`, `/dls scan [force]`, `/dls shield`, `/dls windfury [test]`, `/dls ready`, `/dls check`, `/dls resetloot`, `/dls note <text>`, `/dls levels`, `/dls summary`, `/dls resetxp`, `/dls lock`,
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
