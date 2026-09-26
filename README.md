# Planner

A small macOS planning app built around Apple Calendar.

**Status:** v0.11.0 preview

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
- Includes a local AI Planner that can optimize today or the visible week around existing Calendar events, upcoming goals and Focus history.
- Uses Apple's on-device Foundation Models / Apple Intelligence when available, with an offline deterministic optimizer as fallback.
- AI suggestions are proposal-only: nothing is added to Apple Calendar until you explicitly review or add it.

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

### AI integration

Approved AI suggestions categorized as study or deep work become Focus Blocks automatically. Other suggestions remain ordinary calendar events unless you choose to mark them.

## 0.10.0 local AI planner

Planner now has an **AI Planner** workspace for local schedule optimization.

It can:

- optimize today or the visible week around existing Apple Calendar events;
- use upcoming goal/deadline events and assigned time blocks as context;
- learn a useful focus-block length and preferred time of day from recent completed Focus sessions;
- understand a natural-language request such as “3 hours of chemistry and 2 hours of Rust this week, keep evenings light”;
- preserve transition buffers around fixed events;
- suggest exact blocks with a short reason and category;
- review a suggestion as a normal editable draft before saving it;
- add individual approved suggestions to Apple Calendar.

On supported macOS versions with Apple Intelligence available, Planner uses Apple's **Foundation Models** framework and the on-device system language model. Calendar/Focus context is not sent to an external API. When the system model is unavailable, Planner falls back to its own offline scheduling optimizer.

The AI never receives permission to invent calendar availability. Planner computes valid free windows first and validates every generated suggestion against those windows and the current EventKit schedule before it can be added.

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
