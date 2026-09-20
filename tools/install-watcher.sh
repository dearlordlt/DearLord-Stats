#!/usr/bin/env bash
# Installs a systemd user unit that re-runs wow-keeper-sync whenever the game writes its saved
# variables. Linux only. Needs the game path in ~/.config/wow-keeper/wow-dir (see README).
set -euo pipefail
WOW=${WOW_FOREVER_DIR:-$(head -1 ~/.config/wow-keeper/wow-dir)}
ACC=$(find "$WOW/WTF/Account" -maxdepth 1 -mindepth 1 -type d ! -name SavedVariables | head -1)
[ -d "$ACC/SavedVariables" ] || { echo "No saved-variables folder under $WOW/WTF/Account yet. Log in to the game once first."; exit 1; }
install -Dm755 "$(dirname "$0")/wow-keeper-sync" ~/.local/bin/wow-keeper-sync
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/wow-keeper-sync.service <<UNIT
[Unit]
Description=Regenerate the 0DearLordKeeper restore files from WoW saved variables

[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 3
ExecStart=%h/.local/bin/wow-keeper-sync --quiet
UNIT
cat > ~/.config/systemd/user/wow-keeper-sync.path <<UNIT
[Unit]
Description=Watch WoW Forever beta saved variables

[Path]
PathChanged=$ACC/SavedVariables
TriggerLimitIntervalSec=10
TriggerLimitBurst=3

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now wow-keeper-sync.path
echo "Watcher active for: $ACC/SavedVariables"
