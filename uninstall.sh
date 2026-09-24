#!/bin/bash
set -euo pipefail

UID_NOW="$(id -u)"
AGENT="$HOME/Library/LaunchAgents/local.ren.planner.plist"
LEGACY_AGENT="$HOME/Library/LaunchAgents/local.ren.calmenu.plist"

launchctl bootout "gui/$UID_NOW/local.ren.planner" 2>/dev/null || true
launchctl bootout "gui/$UID_NOW/local.ren.calmenu" 2>/dev/null || true
rm -f "$AGENT" "$LEGACY_AGENT"
sudo rm -rf /Applications/Planner.app /Applications/calmenu.app

echo "Planner removed."
