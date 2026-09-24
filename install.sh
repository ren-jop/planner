#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

[[ "$(uname -s)" == "Darwin" ]] || {
  echo "Planner installs only on macOS." >&2
  exit 1
}

command -v swift >/dev/null 2>&1 || {
  echo "Swift was not found." >&2
  echo "Install Apple's Command Line Tools with: xcode-select --install" >&2
  exit 1
}

./build.sh

APP="/Applications/Planner.app"
AGENT="$HOME/Library/LaunchAgents/local.ren.planner.plist"
LEGACY_AGENT="$HOME/Library/LaunchAgents/local.ren.calmenu.plist"
UID_NOW="$(id -u)"

echo "== install Planner =="

launchctl bootout "gui/$UID_NOW/local.ren.calmenu" 2>/dev/null || true
rm -f "$LEGACY_AGENT"
sudo rm -rf /Applications/calmenu.app

launchctl bootout "gui/$UID_NOW/local.ren.planner" 2>/dev/null || true
sudo rm -rf "$APP"
sudo /usr/bin/ditto dist/Planner.app "$APP"
sudo xattr -d com.apple.quarantine "$APP" 2>/dev/null || true
sudo find "$APP" -exec xattr -d com.apple.quarantine {} \; 2>/dev/null || true

[[ -x "$APP/Contents/MacOS/calmenu" ]] || {
  echo "ERROR: installed Planner executable is missing." >&2
  exit 1
}

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>local.ren.planner</string>
    <key>ProgramArguments</key>
    <array><string>/Applications/Planner.app/Contents/MacOS/calmenu</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ProcessType</key><string>Interactive</string>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>StandardOutPath</key><string>/tmp/planner.out.log</string>
    <key>StandardErrorPath</key><string>/tmp/planner.err.log</string>
</dict>
</plist>
PLIST

plutil -lint "$AGENT"
chmod 644 "$AGENT"

launchctl bootstrap "gui/$UID_NOW" "$AGENT"
launchctl kickstart -k "gui/$UID_NOW/local.ren.planner"

sleep 1
launchctl print "gui/$UID_NOW/local.ren.planner" >/dev/null 2>&1 || {
  echo "ERROR: Planner LaunchAgent did not load." >&2
  tail -50 /tmp/planner.err.log 2>/dev/null >&2 || true
  exit 1
}
pgrep -f '/Applications/Planner.app/Contents/MacOS/calmenu' >/dev/null 2>&1 || {
  echo "ERROR: Planner launched but exited." >&2
  tail -50 /tmp/planner.err.log 2>/dev/null >&2 || true
  exit 1
}

echo
echo "Installed and running: $APP"
echo "If macOS asks for Calendar access, choose Allow Full Access."
