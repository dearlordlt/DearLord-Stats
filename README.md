# DearLord Stats

A quiet HUD and report addon for the **World of Warcraft: Forever** beta (interface 16001), plus
**0DearLordKeeper**, a workaround for the beta bug where addon saved variables are written but never
loaded.

Built for trying out classes and professions while levelling: it answers "how does this class
actually feel" rather than "how fast can I go".

## What is in here

| Folder | What it is |
| --- | --- |
| `DearLordStats/` | The addon. Drop into `Interface/AddOns/`. |
| `0DearLordKeeper/` | Makes addon settings survive `/reload` and game restarts on beta build 69913. Works for every addon, not only this one. |
| `tools/` | Companion scripts for the Keeper (Linux). |
| `test/` | A simulated Forever client, so the addons can be tested with plain `lua5.1`. |
| `docs/` | Notes on what the Forever client does and does not allow addons to do. |

## DearLord Stats

On screen, always: two small transparent text blocks you can drag anywhere.

- **Latency, measured spell lag, FPS.** The game's latency number refreshes every ~30 s; the `lag`
  value is measured on your own casts and updates live.
- **XP per hour, last gain, kills and quests to level (rested-aware), time to level, gold per hour.**

On screen, only when relevant: a one-line **fight recap** after combat, a profession line while you
gather or craft, and gentle one-line reminders (a new spell that is not on your bars, skill-ups you
could craft from your bags, a trainer unlock you reached). They fade out by themselves; left-click
opens the matching report tab, right-click dismisses.

The report (`/dls`, or click either text block; resizable, Escape closes):

- **Combat**: time per kill, dps with pet share, time in combat, rest between pulls, health pool lost
  per fight, close calls, out-of-resource fights, deaths. By session, by level, or for the character,
  and split by pull size, by level, by mob level relative to yours, by zone, plus toughest opponents.
- **Abilities**: where your damage comes from (pet abilities listed separately), spells you learned
  that are on no action bar.
- **Professions**: skill-ups this session, what you can craft *right now* from your bags for points
  (orange / yellow / green), a rough shopping list to the next milestone, remembered trainer unlocks,
  gathering by zone, nodes your skill was too low for.
- **Journal**: `/dls note some thought`, stamped with level and zone.
- **Summary**: paste-ready plain text for one character or all of them.

Commands: `/dls`, `/dls note <text>`, `/dls levels`, `/dls summary`, `/dls resetxp`, `/dls lock`,
`/dls size <9-24>`, `/dls scale`, `/dls alpha`, `/dls bg`, `/dls recap`, `/dls nudges`, `/dls reset`,
`/dls errors`. Right-click either text block for a menu.

Combat numbers come from the game's built-in damage meter (`C_DamageMeter`), read about a second
after each fight, because the combat log is forbidden to addons on this client. See
`docs/forever-client-notes.md`.

## 0DearLordKeeper: settings that survive on the beta

Beta build 69913 writes every addon's saved variables at logout and hands nothing back at load
(community report: ClassicWoWCommunity/forever-bugs#34). Two things do survive, and the Keeper uses
both:

1. **Console variables registered by an addon stay in the game's memory across `/reload`.** At logout
   the Keeper serialises every declared saved variable into them; at login it puts them back before
   any other addon starts.
2. **Addon code files load normally, and the saved files on disk are written correctly.** The script
   `tools/wow-keeper-sync` turns those saved files into `0DearLordKeeper/Restore.lua`, which restores
   everything after a full game restart. It also writes `Declared.lua`, the list of variables each
   installed addon declares (the client does not expose that to addons).

When Blizzard fixes the client, its own loading runs later and simply wins; then delete the Keeper.

The folder starts with a digit on purpose: on this client a leading `!` does **not** sort first, and
the Keeper must load before everything else.

### Setup (Linux)

```bash
mkdir -p ~/.config/wow-keeper
echo "/path/to/World of Warcraft/_classic_beta_" > ~/.config/wow-keeper/wow-dir
cp -r 0DearLordKeeper DearLordStats "/path/to/World of Warcraft/_classic_beta_/Interface/AddOns/"
tools/wow-keeper-sync          # generates Declared.lua and Restore.lua inside the installed Keeper
tools/install-watcher.sh       # optional: re-run the sync automatically whenever the game saves
```

Start the game (a full start, since these are new addon folders). `/keeper` shows what was handed
back. The sync script keeps rolling snapshots of your saved files in
`~/.local/share/wow-keeper/history/` in case a bad session ever saves defaults over good data.

On Windows the in-memory layer works as is (settings survive `/reload`); the restart layer needs the
sync script run by hand or a port of the watcher.

## Development

```bash
lua5.1 test/harness.lua DearLordStats             # simulated play-through, full client
MODE=bare lua5.1 test/harness.lua DearLordStats   # hostile client: helpful APIs missing, health never readable
lua5.1 test/keeper_test.lua 0DearLordKeeper       # restart, reload, memory-only and fixed-client scenarios
./deploy.sh                                       # test, back up, install
```

The harness models the real client's rules (secret values that raise on any comparison, the forbidden
combat log, labels that refuse text before a font is set), because each of those caused a real bug
before the harness knew about it. The addon logs its own errors to `DearLordStatsDB.errors` and API
observations to `.diag`, so problems can be read from the saved-variables file on disk.
