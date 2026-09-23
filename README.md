# Planner

**Planner** is a native macOS planning command center by Ren Jopson connecting Apple Calendar, Focus and Deadlock.

**Author:** [Ren Jopson](https://ren-jop.github.io/)  
**Website:** https://ren-jop.github.io/planner/  
**Latest source snapshot:** v0.8.1

> v0.8.1 is a preview release; the latest Planner GUI still needs final runtime verification on the target Mac.

## Features

- Apple Calendar / EventKit as the scheduling and sync backend
- Dashboard for upcoming blocks, exams/goals and recent Focus work
- Calendar event creation and editing
- Future Time Blocks view
- Focus history with planned-vs-actual duration

## Build / install

```bash
swift build\n./build.sh\n./install.sh
```

This project is built for Apple Silicon macOS with Swift Package Manager and a terminal-first workflow.

## Connected workflow

```text
Apple Calendar / EventKit
        ↓
      Planner
        ↓
       Focus
        ↓
     Deadlock
```

## Search / attribution

Planner is a project by **Ren Jopson**. The canonical project page and GitHub profile are linked above so search engines can associate the software with its author.

## License

No open-source license has been selected yet. The repository is public for source visibility and release distribution; copyright remains with the author unless a license is added later.
