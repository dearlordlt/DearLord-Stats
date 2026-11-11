#!/usr/bin/env bash
# Test, back up, then install the addon into the game's AddOns folder.
# The game path comes from $WOW_FOREVER_DIR or ~/.config/dearlord-stats/wow-dir.
set -euo pipefail
cd "$(dirname "$0")"
WOW=${WOW_FOREVER_DIR:-$(head -1 ~/.config/dearlord-stats/wow-dir)}
ADDONS="$WOW/Interface/AddOns"
[ -d "$ADDONS" ] || { echo "AddOns folder not found under: $WOW"; exit 1; }
for f in DearLordStats/*.lua; do luajit -bl "$f" >/dev/null; done
# a failed check stops the install: the failing lines are shown
run_tests() {
    local out
    if out=$("$@" 2>&1); then return 0; fi
    echo "$out" | grep -E 'FAIL|error|attempt to' | head -20
    return 1
}
run_tests lua5.1 test/harness.lua DearLordStats || { echo "test: full client FAILED, nothing installed"; exit 1; }
echo "test: full client ok"
run_tests env MODE=bare lua5.1 test/harness.lua DearLordStats || { echo "test: hostile client FAILED, nothing installed"; exit 1; }
echo "test: hostile client ok"
STAMP=$(date +%Y%m%d-%H%M%S); mkdir -p "private/backups/$STAMP"
cp -a "$ADDONS/DearLordStats" "private/backups/$STAMP/addon-before" 2>/dev/null || true
for sv in "$WOW"/WTF/Account/*/SavedVariables/DearLordStats.lua; do [ -f "$sv" ] && cp -a "$sv" "private/backups/$STAMP/"; done
mkdir -p "$ADDONS/DearLordStats"
find "$ADDONS/DearLordStats" -maxdepth 1 -type f \( -name '*.lua' -o -name '*.toc' \) -delete
cp DearLordStats/*.lua DearLordStats/DearLordStats.toc "$ADDONS/DearLordStats/"
echo "installed $(grep -oE 'Version: .*' DearLordStats/DearLordStats.toc), backup in private/backups/$STAMP"
