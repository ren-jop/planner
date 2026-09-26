# Planner

A small macOS planning app built around Apple Calendar.

**Status:** v0.12.0 preview

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
- Uses a quieter grid, compact headers, muted calendar colours and a current-time marker so dense schedules remain readable.
- Gives the week view nearly the whole window. The right inspector is hidden until you select a day or create a block.
- Keeps calendar selection in one compact toolbar menu instead of permanently showing a row of calendar chips.
- Includes a Focus-only calendar toggle for seeing just distraction-free work.
- Month previews follow the same visible-calendar selection; Dashboard goals keep a separate configurable source calendar.
- Click a half-hour slot to create a Focus Block draft at that time.
- Reads and edits Apple Calendar events.
- Shows upcoming Focus Blocks and goals.
- Focus Blocks are ordinary Apple Calendar events with private Planner metadata, so there is no duplicate scheduling database.
- Automatically starts scheduled Focus Blocks in Focus when their time arrives; Focus then activates Deadlock for the remaining block duration.
- If Planner launches in the middle of a Focus Block, it can start the remaining time instead of silently missing it.
- A block is recorded as triggered per event occurrence, so stopping Focus early does not make Planner repeatedly restart it.
- Shows recent Focus work.
- Compares planned time with completed Focus sessions.
- Detects Deadlock when it is installed.
- Includes a local Suggestions workspace that notices useful free windows from Apple Calendar, upcoming goals and recent Focus history.
- Suggestions are deterministic and local; there is no model prompt or Apple Intelligence dependency.
- Suggestions never write directly to Apple Calendar. Using one only opens the normal editable draft, which you still choose whether to save.

## 0.12.0 Calendar parity

Planner now writes richer events directly through EventKit so changes sync through the same Apple Calendar accounts instead of living in a separate database.

New event support includes:

- recurring events: daily, weekdays, weekly, monthly and yearly;
- custom recurrence intervals plus never/date/count recurrence endings;
- editing one occurrence or this-and-future occurrences of a recurring series;
- deleting one occurrence or this-and-future occurrences;
- all-day events;
- event location, notes and URL;
- floating or named IANA time zones;
- Busy / Free / Tentative / Unavailable availability;
- two relative alerts;
- preserving existing custom recurrence rules and alarms unless their controls are changed;
- live external-change refresh through `EKEventStoreChanged`;
- recurring Focus Blocks keyed by the server-provided external event identifier so they survive occurrence expansion and are more resilient to calendar sync.

Apple's public EventKit API does not allow Planner to be literally identical to Calendar. In particular, invitee/organizer editing, account setup/subscriptions, and some Calendar-only meeting/travel features remain owned by Apple's Calendar UI. Planner preserves those fields when it edits other event data.

## 0.11.0 Focus Blocks

Planner now treats distraction-free scheduled work as a first-class **Focus Block** rather than a separate generic Time Blocks system.

A Focus Block remains a normal Apple Calendar event. Planner stores only a small local metadata record in:

```text
~/Library/Application Support/Planner/focus-blocks.json
```

That metadata says whether the calendar event should automatically start Focus. It is not written into event titles or sent to an external service.

### Automatic focus enforcement

Planner is installed as a login LaunchAgent and remains available in the background. Every 20 seconds it checks whether a marked Focus Block has begun.

When one begins:

1. Planner sends the event title, event ID and remaining scheduled duration to Focus.
2. Focus starts the session.
3. Focus requests Deadlock distraction blocking for that focus duration.
4. Planner records that occurrence as triggered so ending the session early does not cause an automatic restart loop.

Only events explicitly marked as Focus Blocks are enforced. Dinner, walks, school timetable entries, birthdays and other normal calendar events remain normal events.

Existing events can be marked or unmarked from the event editor or the calendar context menu. New blocks default to Focus Blocks in the Focus Blocks screen and when created from an empty calendar slot.

### Cleaner calendar

The Calendar workspace now prioritizes the actual week:

- the permanent right-hand form is gone;
- the inspector appears only when needed;
- the large visible-calendar chip strip is gone;
- calendar selection is a compact menu in the toolbar;
- event colours are heavily desaturated;
- normal events are visually quieter than Focus Blocks;
- Focus Blocks use a small lock marker and slightly stronger edge rather than a bright fill;
- a **Focus only** switch filters the week to marked Focus Blocks;
- the time gutter and minimum day widths are smaller so the seven-day grid gets more space.

### Suggestions

Planner's helper now behaves more like code-editor completion than an autonomous planner. It quietly proposes optional Focus Blocks from genuine free windows. You can use a suggestion to open it as an editable draft or dismiss it; Planner never inserts the event on its own.

## 0.9.0 calendar redesign

The Calendar screen was rebuilt around multi-calendar planning rather than a single preview calendar. Use the compact **Calendars** control in the toolbar to toggle calendars independently. Planner 0.11 removes the old permanent coloured-chip strip so the schedule keeps the available width.

Event cards retain YouTube-style compact density but now display the Apple Calendar colour and, when there is enough vertical room, the calendar name. Overlapping events share only the space required by their local overlap cluster instead of shrinking unrelated events elsewhere in the day.

Settings has a proper multi-select calendar section. The default calendar for new Focus Blocks and the Dashboard goals calendar remain separate choices.

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
