# Planner

A small macOS planning app built around Apple Calendar.

**Status:** v0.9.0 preview

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

- Shows Apple Calendar events in a responsive seven-day week timeline with half-hour slots.
- Lets you show any combination of Apple calendars at once. Calendar visibility is persistent, available from the Calendar toolbar and Settings, and uses each calendar's native colour.
- Gives unrelated events their full column width and only splits blocks that actually overlap.
- Uses a quieter grid, compact headers, a current-time marker and an event inspector so dense schedules remain readable.
- The right side switches between the selected-day agenda and the New block form instead of showing both at once.
- Month previews follow the same visible-calendar selection; Dashboard goals keep a separate configurable source calendar.
- Click a slot to prepare a block, adjust its duration and check overlaps before adding it.
- Reads and edits Apple Calendar events.
- Shows upcoming blocks and goals.
- Starts scheduled work in Focus.
- Shows recent Focus work.
- Compares planned time with completed Focus sessions.
- Detects Deadlock when it is installed.

## 0.9.0 calendar redesign

The Calendar screen was rebuilt around multi-calendar planning rather than a single preview calendar. Use **Calendars** in the top-right of the week view to toggle calendars independently. The coloured chips directly below the toolbar show exactly what is visible; remove a chip to hide that calendar or use its context menu to show only that one.

Event cards retain YouTube-style compact density but now display the Apple Calendar colour and, when there is enough vertical room, the calendar name. Overlapping events share only the space required by their local overlap cluster instead of shrinking unrelated events elsewhere in the day.

Settings now has a proper multi-select calendar section. The default calendar for newly-created blocks, the calendar used by the Time Blocks screen, and the Dashboard goals calendar remain separate choices.

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

On your Mac, from the cloned Planner repository:


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
