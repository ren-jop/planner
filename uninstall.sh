#!/bin/bash
set -euo pipefail

[[ "$(uname -s)" == "Darwin" ]] || { echo "error: macOS only." >&2; exit 1; }

UID_NOW="$(id -u)"
launchctl bootout "gui/$UID_NOW/local.ren.calmenu" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/local.ren.calmenu.plist"
sudo rm -rf /Applications/calmenu.app

echo "Planner preview removed."
