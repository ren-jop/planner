#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

[[ "$(uname -s)" == "Darwin" ]] || {
  echo "Planner builds only on macOS." >&2
  exit 1
}

command -v swift >/dev/null 2>&1 || {
  echo "Swift was not found. Install Apple's Command Line Tools with: xcode-select --install" >&2
  exit 1
}

echo "== Planner release build =="
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/calmenu"

[[ -x "$BIN" ]] || {
  echo "ERROR: SwiftPM reported success but the Planner executable was not found at:" >&2
  echo "  $BIN" >&2
  exit 1
}

APP="$PWD/dist/Planner.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/calmenu"
cp Info.plist "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/calmenu"

/usr/bin/codesign --force --deep --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"

echo
echo "Built: $APP"
