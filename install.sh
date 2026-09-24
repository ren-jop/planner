#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PART_GLOB="$ROOT/source/planner-v0.8.1.zip.b64.part-"

fail() { echo "error: $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "Planner supports macOS only."
command -v xcrun >/dev/null 2>&1 || fail "Install Apple's Command Line Tools first: xcode-select --install"
xcrun --find swift >/dev/null 2>&1 || fail "Swift was not found. Install Apple's Command Line Tools: xcode-select --install"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/planner-install.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

shopt -s nullglob
PARTS=("${PART_GLOB}"*)
(( ${#PARTS[@]} > 0 )) || fail "Bundled source snapshot is missing."

echo "== Planner v0.8.1 preview =="
cat "${PARTS[@]}" > "$WORK/planner.zip.b64"
/usr/bin/base64 -D < "$WORK/planner.zip.b64" > "$WORK/planner.zip"
/usr/bin/unzip -tq "$WORK/planner.zip" >/dev/null || fail "Bundled source snapshot failed its integrity check."
/usr/bin/ditto -x -k "$WORK/planner.zip" "$WORK"

SRC="$WORK/calmenu-v0.8.1"
[[ -f "$SRC/Package.swift" ]] || fail "Bundled source snapshot is invalid."
chmod +x "$SRC/install.sh"

echo "Building and installing..."
cd "$SRC"
./install.sh

echo
echo "Planner is installed. The current preview keeps the internal app target name 'calmenu' for compatibility."
