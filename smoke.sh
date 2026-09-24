#!/bin/bash
set -u
fail=0
pass(){ echo "PASS  $1"; }
bad(){ echo "FAIL  $1"; fail=$((fail+1)); }

APP="/Applications/Planner.app"
FOCUS="$HOME/Applications/Focus.app/Contents/MacOS/Focus"
DEADLOCK="/Applications/deadlock.app/Contents/MacOS/deadlock"
UID_NOW="$(id -u)"

[[ -d "$APP" ]] && pass "Planner.app installed" || bad "Planner.app installed"
[[ -x "$APP/Contents/MacOS/calmenu" ]] && pass "Planner executable installed" || bad "Planner executable installed"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[[ "$VERSION" == "0.8.1" ]] && pass "Planner version 0.8.1" || bad "Planner version 0.8.1"
plutil -lint "$APP/Contents/Info.plist" >/dev/null 2>&1 && pass "Info.plist valid" || bad "Info.plist valid"
[[ -f "$HOME/Library/LaunchAgents/local.ren.planner.plist" ]] && pass "login item installed" || bad "login item installed"
launchctl print "gui/$UID_NOW/local.ren.planner" >/dev/null 2>&1 && pass "login item loaded" || bad "login item loaded"
pgrep -f '/Applications/Planner.app/Contents/MacOS/calmenu' >/dev/null 2>&1 && pass "Planner process running" || bad "Planner process running"

[[ -x "$FOCUS" ]] && pass "Focus integration installed" || echo "INFO  Focus is not installed"
if [[ -x "$DEADLOCK" ]]; then
  "$DEADLOCK" --ipc status >/dev/null 2>&1 && pass "Deadlock daemon reachable" || echo "INFO  Deadlock is installed but its daemon is unavailable"
else
  echo "INFO  Deadlock is not installed"
fi

echo
exit "$fail"
