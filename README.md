# Planner

A native macOS planning interface that keeps Apple Calendar as the source of truth and connects scheduled work to Focus execution and Deadlock protection.

**Current version:** v0.8.1 preview  
**Platform:** macOS 14+  
**Stack:** Swift, SwiftUI, AppKit, EventKit, Swift Package Manager

> Planner is preview software. Calendar access and the current GUI should be verified on your Mac before you rely on it for important scheduling.

## Install

You need the macOS Command Line Tools / Swift toolchain.

```bash
git clone --depth 1 https://github.com/ren-jop/planner.git
cd planner
./install.sh
```

The installer builds from source, ad-hoc signs the app, installs it as `/Applications/Planner.app`, and configures its login agent. macOS may ask for Calendar access on first launch.

### Update

```bash
git pull --ff-only
./install.sh
```

### Uninstall

```bash
./uninstall.sh
```

The installer also cleans up older preview builds that were published under the internal `calmenu` app name.

## What it does

- Uses Apple Calendar / EventKit instead of maintaining a second calendar database
- Surfaces upcoming blocks, goals and recent Focus work
- Creates and edits calendar events
- Starts scheduled work in Focus
- Compares planned time with actual Focus history
- Detects optional Deadlock integration for distraction protection

## Architecture

```text
Apple Calendar / EventKit
          ↓
       Planner
          ↓
        Focus
          ↓
      Deadlock
```

Each layer has a narrow responsibility: Calendar owns scheduling, Planner owns orchestration, Focus owns work sessions, and Deadlock owns enforcement.

## Development

```bash
swift build -c release
./build.sh
./smoke.sh
```

CI compiles the Swift package on macOS for every push and pull request.

## Project links

- Project page: https://ren-jop.github.io/planner/
- Portfolio: https://ren-jop.github.io/
- Author: Ren Jopson

## License

No open-source license has been selected yet. The repository is public for source visibility and review; copyright remains with the author unless a license is added later.
