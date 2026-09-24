# Planner

A small macOS planning app built around Apple Calendar.

**Status:** v0.8.1 preview  
**Platform:** macOS 14+  
**Stack:** Swift, SwiftUI, AppKit, EventKit, SwiftPM

## Why

I already use Apple Calendar. I did not want a second planning database containing the same schedule, so Planner uses EventKit directly.

## Install

```bash
git clone --depth 1 https://github.com/ren-jop/planner.git
cd planner
./install.sh
```

The installer builds and installs:

```text
/Applications/Planner.app
```

macOS will ask for Calendar access on first use.

## What it does

- Reads and edits Apple Calendar events.
- Shows upcoming blocks and goals.
- Starts scheduled work in Focus.
- Shows recent Focus work.
- Compares planned time with completed Focus sessions.
- Detects Deadlock when it is installed.

## How the apps fit together

```text
Apple Calendar
     ↓
  Planner
     ↓
   Focus
     ↓
 Deadlock
```

Planner handles planning. Focus handles the active session. Deadlock handles blocking.

## Update

```bash
git pull --ff-only
./install.sh
```

## Uninstall

```bash
./uninstall.sh
```

## Development

```bash
swift build -c release
./build.sh
./smoke.sh
```

The internal executable still uses the older `calmenu` name in a few places for compatibility.

## License

No open-source license has been selected yet.
