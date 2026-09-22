#!/usr/bin/env bash
# Test, back up, then install both addons into the game's AddOns folder.
# The game path comes from $WOW_FOREVER_DIR or ~/.config/wow-keeper/wow-dir.
set -euo pipefail
cd "$(dirname "$0")"
WOW=${WOW_FOREVER_DIR:-$(head -1 ~/.config/wow-keeper/wow-dir)}
ADDONS="$WOW/Interface/AddOns"
[ -d "$ADDONS" ] || { echo "AddOns folder not found under: $WOW"; exit 1; }
for f in DearLordStats/*.lua 0DearLordKeeper/Keeper.lua 0DearLordKeeper/Fixes.lua; do luajit -bl "$f" >/dev/null; done
lua5.1 test/harness.lua DearLordStats >/dev/null && echo "test: full client ok"
MODE=bare lua5.1 test/harness.lua DearLordStats >/dev/null && echo "test: hostile client ok"
STAMP=$(date +%Y%m%d-%H%M%S); mkdir -p "private/backups/$STAMP"
cp -a "$ADDONS/DearLordStats" "private/backups/$STAMP/addon-before" 2>/dev/null || true
for sv in "$WOW"/WTF/Account/*/SavedVariables/DearLordStats.lua; do [ -f "$sv" ] && cp -a "$sv" "private/backups/$STAMP/"; done
mkdir -p "$ADDONS/DearLordStats" "$ADDONS/0DearLordKeeper"
find "$ADDONS/DearLordStats" -maxdepth 1 -type f \( -name '*.lua' -o -name '*.toc' \) -delete
cp DearLordStats/*.lua DearLordStats/DearLordStats.toc "$ADDONS/DearLordStats/"
cp 0DearLordKeeper/Keeper.lua 0DearLordKeeper/Fixes.lua 0DearLordKeeper/0DearLordKeeper.toc "$ADDONS/0DearLordKeeper/"
tools/wow-keeper-sync --quiet && echo "keeper: generated files refreshed"
lua5.1 test/keeper_test.lua 0DearLordKeeper >/dev/null && echo "test: keeper ok"
echo "installed $(grep -oE 'Version: .*' DearLordStats/DearLordStats.toc), backup in private/backups/$STAMP"
