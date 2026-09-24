# Planner

A native macOS planning layer that keeps **Apple Calendar as the source of truth** and connects scheduled work to Focus execution and Deadlock protection.

> **Status:** v0.8.1 preview. The current GUI still needs broader runtime verification.

## Install

Requirements: macOS 14+ and Apple's Command Line Tools.

```bash
git clone https://github.com/ren-jop/planner.git
cd planner
./install.sh
```

The installer reconstructs and verifies the vendored v0.8.1 source snapshot, builds it with Swift Package Manager, and installs the app.

The preview currently retains the internal target/app name **calmenu** for compatibility while the public project name is Planner.

Remove it with:

```bash
./uninstall.sh
```

## Engineering

- Apple Calendar / EventKit remains the scheduling database
- upcoming blocks and events are surfaced without duplicating calendar state
- calendar context can start a Focus session
- recent Focus history supports planned-vs-actual review
- Deadlock remains downstream of Focus rather than being triggered independently
- Swift + Swift Package Manager with native macOS frameworks

## Ownership model

```text
Apple Calendar / EventKit
          │
       Planner
          │ context
          ▼
        Focus
       /     \
 history    Deadlock
```

Planner owns planning context, Focus owns the active session, and Deadlock owns enforcement.

## Source snapshot

The v0.8.1 preview snapshot is vendored under `source/` as ordered base64 chunks. `install.sh` concatenates, decodes and validates the ZIP before building. A notarized binary distribution is not published yet.

## Links

- Project page: https://ren-jop.github.io/planner/
- Focus: https://github.com/ren-jop/focus
- Deadlock: https://github.com/ren-jop/deadlock

## License

No open-source license has been selected. The repository is public for source visibility and release distribution; copyright remains with the author unless a license is added later.
