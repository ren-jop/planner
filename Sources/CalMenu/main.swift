import SwiftUI
import AppKit
import EventKit
import Combine

private struct CalcliConfig: Decodable {
    let defaultCalendar: String?
}

struct MonthCell: Identifiable {
    let id: Int
    let date: Date?
}

struct FocusHistoryEntry: Codable, Identifiable {
    let date: Date
    let kind: String
    let minutes: Int
    let why: String?
    let rating: Int?
    let improve: String?
    let label: String?
    let calendarEventID: String?
    let plannedMinutes: Int?

    var id: String {
        "\(date.timeIntervalSince1970)-\(kind)-\(minutes)-\(label ?? "")"
    }
}

private enum MonthGridDensity {
    case menu
    case planner

    var cellHeight: CGFloat {
        switch self {
        case .menu: return 58
        case .planner: return 94
        }
    }

    var maxPreviewLines: Int {
        switch self {
        case .menu: return 2
        case .planner: return 4
        }
    }

    var titleFontSize: CGFloat {
        switch self {
        case .menu: return 8.3
        case .planner: return 10.5
        }
    }

    var dayFontSize: CGFloat {
        switch self {
        case .menu: return 11.5
        case .planner: return 13
        }
    }
}

@MainActor
final class EventEditorModel: ObservableObject {
    let event: EKEvent

    @Published var title: String
    @Published var start: Date
    @Published var end: Date
    @Published var allDay: Bool
    @Published var calendarID: String

    init(event: EKEvent) {
        self.event = event
        self.title = event.title ?? ""
        self.start = event.startDate
        self.end = event.endDate
        self.allDay = event.isAllDay
        self.calendarID = event.calendar.calendarIdentifier
    }
}

@MainActor
final class CalendarMenuState: NSObject, ObservableObject {
    private let store = EKEventStore()
    private let calendar = Calendar.current
    private let previewCalendarDefaultsKey = "calmenu.monthPreviewCalendarID"
    private let defaultCalendarDefaultsKey = "calmenu.defaultCreateCalendarID"
    private let futureCalendarDefaultsKey = "calmenu.futureCalendarID"

    @Published var accessGranted = false
    @Published var accessDenied = false
    @Published var visibleMonth: Date
    @Published var selectedDate: Date
    @Published var calendars: [EKCalendar] = []
    @Published var selectedCalendarID = ""
    @Published var monthPreviewCalendarID = ""
    @Published var futureCalendarID = ""
    @Published var plannerPanel = "dashboard"

    @Published private(set) var monthCellsCache: [MonthCell] = []
    @Published private(set) var previewEventCountByDay: [Date: Int] = [:]
    @Published private(set) var previewTitlesByDay: [Date: [String]] = [:]
    @Published var selectedEvents: [EKEvent] = []
    @Published private(set) var upcomingBlocks: [EKEvent] = []
    @Published private(set) var goalEvents: [EKEvent] = []
    @Published private(set) var focusHistory: [FocusHistoryEntry] = []

    @Published var draftTitle = ""
    @Published var draftStart: Date
    @Published var draftEnd: Date
    @Published var statusMessage = ""

    @Published var focusLinked = false
    @Published var focusActive = false
    @Published var focusLabel: String?
    @Published var focusDeadline: Date?
    @Published var focusCountUp = false
    @Published var focusStartedAt: Date?
    @Published var deadlockLinked = false

    private var eventStoreObserver: NSObjectProtocol?
    private var reloadWorkItem: DispatchWorkItem?
    private var allEventsByDay: [Date: [EKEvent]] = [:]
    private var plannerWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var editorWindowController: NSWindowController?

    private let focusExecutable = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/Focus.app/Contents/MacOS/Focus").path
    private let focusHistoryURL = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0].appendingPathComponent("Focus/log.jsonl")
    private let deadlockExecutable = "/Applications/deadlock.app/Contents/MacOS/deadlock"

    override init() {
        let now = Date()
        visibleMonth = CalendarMenuState.firstDayOfMonth(now, calendar: calendar)
        selectedDate = calendar.startOfDay(for: now)

        let rounded = CalendarMenuState.nextHalfHour(now, calendar: calendar)
        draftStart = rounded
        draftEnd = calendar.date(byAdding: .minute, value: 60, to: rounded) ?? rounded

        super.init()

        rebuildMonthCells()

        eventStoreObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleEventStoreReload()
            }
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(focusStateChanged(_:)),
            name: Notification.Name("local.focus.stateChanged"),
            object: nil
        )

        Task { await requestAccessAndLoad() }
        refreshIntegrationStatus()
    }

    deinit {
        reloadWorkItem?.cancel()
        if let eventStoreObserver {
            NotificationCenter.default.removeObserver(eventStoreObserver)
        }
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func focusStateChanged(_ note: Notification) {
        refreshIntegrationStatus()
        loadFocusHistory()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.loadFocusHistory()
        }
    }

    private func scheduleEventStoreReload() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reloadCalendars()
            self.reloadVisibleData()
            self.reloadUpcomingBlocks()
            self.reloadGoalEvents()
        }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: item)
    }

    static func firstDayOfMonth(_ date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
    }

    static func nextHalfHour(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        let minute = calendar.component(.minute, from: date)
        let offset = minute < 30 ? 30 : 60
        return calendar.date(byAdding: .minute, value: offset, to: start) ?? date
    }

    func requestAccessAndLoad() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            accessGranted = granted
            accessDenied = !granted
            guard granted else { return }
            reloadCalendars()
            reloadVisibleData()
            reloadUpcomingBlocks()
            reloadGoalEvents()
            loadFocusHistory()
        } catch {
            accessDenied = true
            statusMessage = error.localizedDescription
        }
    }

    var writableCalendars: [EKCalendar] {
        calendars.filter(\.allowsContentModifications)
    }

    var monthPreviewCalendarName: String {
        calendars.first(where: {
            $0.calendarIdentifier == monthPreviewCalendarID
        })?.title ?? "Month entries"
    }

    var futureCalendarName: String {
        calendars.first(where: {
            $0.calendarIdentifier == futureCalendarID
        })?.title ?? "Time blocks"
    }

    var nextUpcomingBlock: EKEvent? {
        upcomingBlocks.first
    }

    var todayUpcomingBlocks: [EKEvent] {
        let now = Date()
        return upcomingBlocks.filter {
            Calendar.current.isDate($0.startDate, inSameDayAs: now)
        }
    }

    var nextSevenDayBlocks: [EKEvent] {
        let now = Date()
        guard let end = Calendar.current.date(
            byAdding: .day,
            value: 7,
            to: now
        ) else { return [] }

        return upcomingBlocks.filter {
            $0.startDate >= now && $0.startDate < end
        }
    }

    var recentHistory: [FocusHistoryEntry] {
        Array(focusHistory.prefix(6))
    }

    var nextGoalEvents: [EKEvent] {
        Array(goalEvents.prefix(8))
    }

    private func loadCalcliDefaultCalendarName() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/calendar/config.json")
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(CalcliConfig.self, from: data)
        else { return nil }
        return config.defaultCalendar
    }

    func reloadCalendars() {
        let available = store.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        calendars = available

        let defaults = UserDefaults.standard
        let savedCreateID = defaults.string(forKey: defaultCalendarDefaultsKey)
        let savedPreviewID = defaults.string(forKey: previewCalendarDefaultsKey)
        let savedFutureID = defaults.string(forKey: futureCalendarDefaultsKey)

        if selectedCalendarID.isEmpty ||
            !available.contains(where: { $0.calendarIdentifier == selectedCalendarID }) {
            if let savedCreateID,
               let match = writableCalendars.first(where: {
                   $0.calendarIdentifier == savedCreateID
               }) {
                selectedCalendarID = match.calendarIdentifier
            } else if let configuredName = loadCalcliDefaultCalendarName(),
                      let match = writableCalendars.first(where: {
                          $0.title == configuredName
                      }) {
                selectedCalendarID = match.calendarIdentifier
            } else if let defaultCalendar = store.defaultCalendarForNewEvents,
                      defaultCalendar.allowsContentModifications {
                selectedCalendarID = defaultCalendar.calendarIdentifier
            } else if let first = writableCalendars.first {
                selectedCalendarID = first.calendarIdentifier
            }
        }

        if monthPreviewCalendarID.isEmpty ||
            !available.contains(where: { $0.calendarIdentifier == monthPreviewCalendarID }) {
            if let savedPreviewID,
               available.contains(where: { $0.calendarIdentifier == savedPreviewID }) {
                monthPreviewCalendarID = savedPreviewID
            } else if !selectedCalendarID.isEmpty {
                monthPreviewCalendarID = selectedCalendarID
            } else if let first = available.first {
                monthPreviewCalendarID = first.calendarIdentifier
            }
        }

        if futureCalendarID.isEmpty ||
            !available.contains(where: { $0.calendarIdentifier == futureCalendarID }) {
            if let savedFutureID,
               available.contains(where: { $0.calendarIdentifier == savedFutureID }) {
                futureCalendarID = savedFutureID
            } else if !selectedCalendarID.isEmpty {
                futureCalendarID = selectedCalendarID
            } else if let first = writableCalendars.first {
                futureCalendarID = first.calendarIdentifier
            }
        }
    }

    func setMonthPreviewCalendarID(_ id: String) {
        guard monthPreviewCalendarID != id else { return }
        monthPreviewCalendarID = id
        UserDefaults.standard.set(id, forKey: previewCalendarDefaultsKey)
        reloadVisibleData()
        reloadGoalEvents()
    }

    func setDefaultCreateCalendarID(_ id: String) {
        guard selectedCalendarID != id else { return }
        selectedCalendarID = id
        UserDefaults.standard.set(id, forKey: defaultCalendarDefaultsKey)
    }

    func setFutureCalendarID(_ id: String) {
        guard futureCalendarID != id else { return }
        futureCalendarID = id
        UserDefaults.standard.set(id, forKey: futureCalendarDefaultsKey)
        reloadUpcomingBlocks()
    }

    func setPlannerPanel(_ panel: String) {
        plannerPanel = panel

        switch panel {
        case "history":
            loadFocusHistory()
        case "blocks":
            reloadUpcomingBlocks()
        case "calendar":
            reloadVisibleData()
        case "dashboard":
            reloadOverviewData()
        default:
            break
        }
    }

    func reloadOverviewData() {
        reloadUpcomingBlocks()
        reloadGoalEvents()
        loadFocusHistory()
        refreshIntegrationStatus()
    }

    func reloadGoalEvents() {
        guard accessGranted,
              let sourceCalendar = calendars.first(where: {
                  $0.calendarIdentifier == monthPreviewCalendarID
              })
        else {
            goalEvents = []
            return
        }

        let now = Date()
        guard let end = calendar.date(byAdding: .day, value: 90, to: now)
        else {
            goalEvents = []
            return
        }

        let predicate = store.predicateForEvents(
            withStart: now,
            end: end,
            calendars: [sourceCalendar]
        )

        goalEvents = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted {
                if $0.startDate != $1.startDate {
                    return $0.startDate < $1.startDate
                }
                return ($0.title ?? "") < ($1.title ?? "")
            }
            .prefix(100)
            .map { $0 }
    }

    func reloadUpcomingBlocks() {
        guard accessGranted,
              let sourceCalendar = calendars.first(where: {
                  $0.calendarIdentifier == futureCalendarID
              })
        else {
            upcomingBlocks = []
            return
        }

        let now = Date()
        let start = now.addingTimeInterval(-12 * 60 * 60)
        guard let end = calendar.date(byAdding: .day, value: 180, to: now)
        else {
            upcomingBlocks = []
            return
        }

        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: [sourceCalendar]
        )

        upcomingBlocks = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted {
                if $0.startDate != $1.startDate {
                    return $0.startDate < $1.startDate
                }
                return ($0.title ?? "") < ($1.title ?? "")
            }
            .prefix(250)
            .map { $0 }
    }

    func loadFocusHistory() {
        guard FileManager.default.fileExists(atPath: focusHistoryURL.path),
              let handle = try? FileHandle(forReadingFrom: focusHistoryURL)
        else {
            focusHistory = []
            return
        }

        defer { try? handle.close() }

        let end = (try? handle.seekToEnd()) ?? 0
        let maxBytes: UInt64 = 2 * 1024 * 1024
        let offset = end > maxBytes ? end - maxBytes : 0

        try? handle.seek(toOffset: offset)
        var data = handle.readDataToEndOfFile()

        if offset > 0,
           let newline = data.firstIndex(of: 0x0A) {
            data.removeSubrange(data.startIndex...newline)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var entries: [FocusHistoryEntry] = []
        entries.reserveCapacity(300)

        for line in data.split(separator: 0x0A).suffix(500) {
            if let entry = try? decoder.decode(
                FocusHistoryEntry.self,
                from: Data(line)
            ) {
                entries.append(entry)
            }
        }

        focusHistory = entries
            .sorted { $0.date > $1.date }
    }

    func reloadVisibleData() {
        guard accessGranted else { return }

        let monthStart = visibleMonth
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)
        else { return }

        let predicate = store.predicateForEvents(
            withStart: monthStart,
            end: monthEnd,
            calendars: nil
        )

        let events = store.events(matching: predicate)
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay && !rhs.isAllDay }
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return (lhs.title ?? "") < (rhs.title ?? "")
            }

        var allGrouped: [Date: [EKEvent]] = [:]
        var previewGrouped: [Date: [EKEvent]] = [:]

        for event in events {
            let clippedStart = max(event.startDate, monthStart)
            let clippedEnd = min(event.endDate, monthEnd)
            guard clippedEnd > clippedStart else { continue }

            var day = calendar.startOfDay(for: clippedStart)
            let finalDay = calendar.startOfDay(
                for: clippedEnd.addingTimeInterval(-0.001)
            )

            while day <= finalDay {
                allGrouped[day, default: []].append(event)
                if event.calendar.calendarIdentifier == monthPreviewCalendarID {
                    previewGrouped[day, default: []].append(event)
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day)
                else { break }
                day = next
            }
        }

        var counts: [Date: Int] = [:]
        var previews: [Date: [String]] = [:]

        for (day, entries) in previewGrouped {
            counts[day] = entries.count

            var lines: [String] = []
            var seen = Set<String>()

            for event in entries {
                let rawTitle = (event.title ?? "Untitled")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawTitle.isEmpty else { continue }

                let line: String
                if event.isAllDay {
                    line = rawTitle
                } else {
                    let time = event.startDate.formatted(
                        date: .omitted,
                        time: .shortened
                    )
                    line = "\(time) \(rawTitle)"
                }

                if seen.insert(line).inserted {
                    lines.append(line)
                }
                if lines.count == 4 { break }
            }
            previews[day] = lines
        }

        allEventsByDay = allGrouped
        previewEventCountByDay = counts
        previewTitlesByDay = previews
        reloadSelectedDay()
    }

    func reloadSelectedDay() {
        selectedEvents = allEventsByDay[
            calendar.startOfDay(for: selectedDate)
        ] ?? []
    }

    private func rebuildMonthCells() {
        guard let range = calendar.range(
            of: .day,
            in: .month,
            for: visibleMonth
        ),
        let monthInterval = calendar.dateInterval(
            of: .month,
            for: visibleMonth
        )
        else {
            monthCellsCache = []
            return
        }

        let firstWeekday = calendar.component(
            .weekday,
            from: monthInterval.start
        )
        let leading = (
            firstWeekday - calendar.firstWeekday + 7
        ) % 7

        monthCellsCache = (0..<42).map { index in
            let dayOffset = index - leading
            guard dayOffset >= 0,
                  dayOffset < range.count,
                  let date = calendar.date(
                    byAdding: .day,
                    value: dayOffset,
                    to: monthInterval.start
                  )
            else {
                return MonthCell(id: index, date: nil)
            }
            return MonthCell(id: index, date: date)
        }
    }

    func previewEventCount(on date: Date) -> Int {
        previewEventCountByDay[
            calendar.startOfDay(for: date)
        ] ?? 0
    }

    func previewTitles(on date: Date) -> [String] {
        previewTitlesByDay[
            calendar.startOfDay(for: date)
        ] ?? []
    }

    func selectDate(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)

        let oldStart = draftStart
        let oldEnd = draftEnd
        let duration = max(
            15 * 60,
            oldEnd.timeIntervalSince(oldStart)
        )

        let time = calendar.dateComponents(
            [.hour, .minute],
            from: oldStart
        )
        var components = calendar.dateComponents(
            [.year, .month, .day],
            from: selectedDate
        )
        components.hour = time.hour
        components.minute = time.minute

        if let newStart = calendar.date(from: components) {
            draftStart = newStart
            draftEnd = newStart.addingTimeInterval(duration)
        }

        reloadSelectedDay()
    }

    func previousMonth() {
        guard let next = calendar.date(
            byAdding: .month,
            value: -1,
            to: visibleMonth
        ) else { return }

        visibleMonth = Self.firstDayOfMonth(
            next,
            calendar: calendar
        )
        rebuildMonthCells()
        reloadVisibleData()
    }

    func nextMonth() {
        guard let next = calendar.date(
            byAdding: .month,
            value: 1,
            to: visibleMonth
        ) else { return }

        visibleMonth = Self.firstDayOfMonth(
            next,
            calendar: calendar
        )
        rebuildMonthCells()
        reloadVisibleData()
    }

    func goToToday() {
        let now = Date()
        visibleMonth = Self.firstDayOfMonth(
            now,
            calendar: calendar
        )
        rebuildMonthCells()
        selectDate(now)
        reloadVisibleData()
    }

    func createBlock(startFocusAfterSave: Bool = false) {
        let trimmed = draftTitle.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmed.isEmpty else {
            statusMessage = "Give the block a title."
            return
        }

        guard draftEnd > draftStart else {
            statusMessage = "End time must be after start time."
            return
        }

        guard let target = writableCalendars.first(where: {
            $0.calendarIdentifier == selectedCalendarID
        }) else {
            statusMessage = "Choose a writable calendar."
            return
        }

        let event = EKEvent(eventStore: store)
        event.title = trimmed
        event.calendar = target
        event.startDate = draftStart
        event.endDate = draftEnd

        do {
            try store.save(event, span: .thisEvent, commit: true)
            draftTitle = ""
            statusMessage = startFocusAfterSave
                ? "Added · starting Focus…"
                : "Added."

            reloadVisibleData()
            reloadUpcomingBlocks()

            let duration = draftEnd.timeIntervalSince(draftStart)
            draftStart = draftEnd
            draftEnd = draftStart.addingTimeInterval(
                max(duration, 30 * 60)
            )

            if startFocusAfterSave {
                startFocus(for: event)
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateEvent(
        _ event: EKEvent,
        title: String,
        start: Date,
        end: Date,
        allDay: Bool,
        calendarID: String
    ) -> Bool {
        let trimmed = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            statusMessage = "Event title cannot be empty."
            return false
        }

        guard let target = calendars.first(where: {
            $0.calendarIdentifier == calendarID &&
            $0.allowsContentModifications
        }) else {
            statusMessage = "Choose a writable calendar."
            return false
        }

        let normalizedStart: Date
        let normalizedEnd: Date

        if allDay {
            normalizedStart = calendar.startOfDay(for: start)
            let candidateEnd = calendar.startOfDay(for: end)
            normalizedEnd = candidateEnd > normalizedStart
                ? candidateEnd
                : (calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: normalizedStart
                ) ?? normalizedStart.addingTimeInterval(86400))
        } else {
            guard end > start else {
                statusMessage = "End time must be after start time."
                return false
            }
            normalizedStart = start
            normalizedEnd = end
        }

        event.title = trimmed
        event.startDate = normalizedStart
        event.endDate = normalizedEnd
        event.isAllDay = allDay
        event.calendar = target

        do {
            try store.save(event, span: .thisEvent, commit: true)
            statusMessage = "Updated."
            reloadVisibleData()
            reloadUpcomingBlocks()
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func deleteEvent(_ event: EKEvent) {
        guard event.calendar.allowsContentModifications else {
            statusMessage = "That calendar is read-only."
            return
        }

        do {
            try store.remove(event, span: .thisEvent, commit: true)
            statusMessage = "Deleted."
            reloadVisibleData()
            reloadUpcomingBlocks()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshIntegrationStatus() {
        focusLinked = FileManager.default.isExecutableFile(
            atPath: focusExecutable
        )

        deadlockLinked =
            FileManager.default.isExecutableFile(
                atPath: deadlockExecutable
            ) &&
            FileManager.default.fileExists(
                atPath: "/var/run/deadlock.sock"
            )

        let focusDefaults = UserDefaults(suiteName: "local.focus")
        let phase = focusDefaults?.string(forKey: "phase")
        let deadline = focusDefaults?.object(
            forKey: "deadline"
        ) as? Date
        let activeMode = focusDefaults?.string(
            forKey: "activeTimerMode"
        )
        let startedAt = focusDefaults?.object(
            forKey: "focusStartedAt"
        ) as? Date

        focusCountUp = activeMode == "countUp"

        focusActive =
            focusLinked &&
            phase == "focus" &&
            (
                focusCountUp ||
                (deadline?.timeIntervalSinceNow ?? -1) > 0
            )

        focusDeadline =
            focusActive && !focusCountUp
            ? deadline
            : nil
        focusStartedAt =
            focusActive && focusCountUp
            ? startedAt
            : nil

        if focusActive {
            let label = focusDefaults?.string(
                forKey: "focusLabel"
            )?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            focusLabel = (label?.isEmpty == false)
                ? label
                : "Focus"
        } else {
            focusLabel = nil
            focusDeadline = nil
            focusStartedAt = nil
            focusCountUp = false
        }
    }

    func onPopoverAppear() {
        refreshIntegrationStatus()
        reloadUpcomingBlocks()
    }

    func onPlannerAppear() {
        reloadOverviewData()
    }

    func startFocus(for event: EKEvent) {
        guard !event.isAllDay else {
            statusMessage =
                "All-day events do not have a focus duration."
            return
        }

        guard event.endDate > Date() else {
            statusMessage = "That event has already ended."
            return
        }

        guard FileManager.default.isExecutableFile(
            atPath: focusExecutable
        ) else {
            focusLinked = false
            statusMessage =
                "Focus is not installed in ~/Applications/Focus.app."
            return
        }

        let now = Date()
        let rawSeconds: Int

        if event.startDate <= now {
            rawSeconds = Int(
                event.endDate.timeIntervalSince(now).rounded(.up)
            )
        } else {
            rawSeconds = Int(
                event.endDate
                    .timeIntervalSince(event.startDate)
                    .rounded(.up)
            )
        }

        let seconds = max(15 * 60, rawSeconds)
        let title = (event.title ?? "Calendar block")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        statusMessage = "Starting Focus…"

        let focusPath = focusExecutable
        let focusTitle = title.isEmpty
            ? "Calendar block"
            : title

        DispatchQueue.global(
            qos: .userInitiated
        ).async { [weak self, focusPath, focusTitle, seconds] in
            let process = Process()
            process.executableURL = URL(
                fileURLWithPath: focusPath
            )
            let plannedSeconds = max(
                60,
                Int(
                    event.endDate
                        .timeIntervalSince(event.startDate)
                        .rounded(.up)
                )
            )

            process.arguments = [
                "--start-seconds",
                String(seconds),
                "--title",
                focusTitle,
                "--event-id",
                event.calendarItemIdentifier,
                "--planned-seconds",
                String(plannedSeconds),
            ]

            let errors = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors

            do {
                try process.run()
                process.waitUntilExit()

                let status = process.terminationStatus
                let stderr = String(
                    data: errors.fileHandleForReading
                        .readDataToEndOfFile(),
                    encoding: .utf8
                )?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }

                    if status == 0 {
                        let suffix = self.deadlockLinked
                            ? " · distractions locked"
                            : " · deadlock unavailable"
                        self.statusMessage =
                            "Focus started\(suffix)"
                    } else {
                        self.statusMessage =
                            stderr?.isEmpty == false
                            ? stderr!
                            : "Focus could not start."
                    }

                    self.refreshIntegrationStatus()
                }
            } catch {
                let message = error.localizedDescription

                DispatchQueue.main.async { [weak self] in
                    self?.statusMessage = message
                    self?.refreshIntegrationStatus()
                }
            }
        }
    }

    func showEventEditor(_ event: EKEvent) {
        if let editorWindowController {
            editorWindowController.close()
        }

        let model = EventEditorModel(event: event)

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 430,
                height: 360
            ),
            styleMask: [
                .titled,
                .closable
            ],
            backing: .buffered,
            defer: false
        )

        let controller = NSHostingController(
            rootView: EventEditorView(
                state: self,
                model: model,
                onClose: { [weak window] in
                    window?.close()
                }
            )
            .preferredColorScheme(.dark)
        )

        window.title = "Edit Event"
        window.contentViewController = controller
        window.isReleasedWhenClosed = false
        window.center()

        let windowController = NSWindowController(window: window)
        editorWindowController = windowController
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showPlannerWindow() {
        reloadOverviewData()

        if let plannerWindowController,
           let window = plannerWindowController.window {
            plannerWindowController.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(
            rootView: CalendarPlannerView(state: self)
                .preferredColorScheme(.dark)
        )

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 1220,
                height: 780
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable
            ],
            backing: .buffered,
            defer: false
        )

        window.title = "Planner"
        window.contentViewController = controller
        window.minSize = NSSize(width: 1000, height: 660)
        window.isReleasedWhenClosed = false
        window.center()

        let windowController = NSWindowController(window: window)
        plannerWindowController = windowController
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettingsWindow() {
        if let settingsWindowController,
           let window = settingsWindowController.window {
            settingsWindowController.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(
            rootView: CalendarSettingsView(state: self)
                .preferredColorScheme(.dark)
        )

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 440,
                height: 360
            ),
            styleMask: [
                .titled,
                .closable
            ],
            backing: .buffered,
            defer: false
        )

        window.title = "Calendar Settings"
        window.contentViewController = controller
        window.isReleasedWhenClosed = false
        window.center()

        let windowController = NSWindowController(window: window)
        settingsWindowController = windowController
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openAppleCalendar() {
        let url = URL(
            fileURLWithPath: "/System/Applications/Calendar.app"
        )

        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                Task { @MainActor in
                    self.statusMessage =
                        error.localizedDescription
                }
            }
        }
    }

    func openCalcliTUI() {
        let candidates = [
            "/opt/homebrew/bin/calcli",
            "/usr/local/bin/calcli"
        ]

        guard let binary = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            statusMessage =
                "calcli not found in /opt/homebrew/bin or /usr/local/bin."
            return
        }

        let escaped = binary
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """

        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: "/usr/bin/osascript"
        )
        process.arguments = ["-e", script]

        do {
            try process.run()
            statusMessage = ""
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct CalendarMonthGrid: View {
    @ObservedObject var state: CalendarMenuState
    let density: MonthGridDensity

    private let weekdaySymbols =
        Calendar.current.veryShortStandaloneWeekdaySymbols

    var body: some View {
        VStack(spacing: density == .menu ? 4 : 7) {
            HStack(spacing: 0) {
                ForEach(
                    Array(weekdaySymbols.enumerated()),
                    id: \.offset
                ) { _, symbol in
                    Text(symbol)
                        .font(
                            density == .menu
                            ? .caption2
                            : .caption
                        )
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(
                        .flexible(),
                        spacing: density == .menu ? 2 : 4
                    ),
                    count: 7
                ),
                spacing: density == .menu ? 2 : 4
            ) {
                ForEach(state.monthCellsCache) { cell in
                    if let date = cell.date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(
                            height: density.cellHeight
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ date: Date) -> some View {
        let selected = Calendar.current.isDate(
            date,
            inSameDayAs: state.selectedDate
        )
        let today = Calendar.current.isDateInToday(date)
        let previews = state.previewTitles(on: date)
        let eventCount = state.previewEventCount(on: date)
        let visibleCount = min(
            previews.count,
            density.maxPreviewLines
        )
        let overflow = max(0, eventCount - visibleCount)

        Button {
            state.selectDate(date)
        } label: {
            VStack(
                alignment: .leading,
                spacing: density == .menu ? 2 : 4
            ) {
                HStack(
                    alignment: .firstTextBaseline,
                    spacing: 4
                ) {
                    Text(
                        "\(Calendar.current.component(.day, from: date))"
                    )
                    .font(
                        .system(
                            size: density.dayFontSize,
                            weight: selected
                                ? .semibold
                                : .regular,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        selected ? Color.white : Color.primary
                    )

                    Spacer(minLength: 2)

                    if eventCount > 0 {
                        Text("\(eventCount)")
                            .font(
                                .system(
                                    size: density == .menu ? 8 : 9,
                                    weight: .medium,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(
                                selected
                                ? Color.white.opacity(0.80)
                                : Color.secondary
                            )
                    }
                }

                VStack(
                    alignment: .leading,
                    spacing: density == .menu ? 1 : 3
                ) {
                    ForEach(
                        Array(
                            previews
                                .prefix(density.maxPreviewLines)
                                .enumerated()
                        ),
                        id: \.offset
                    ) { _, line in
                        Text(line)
                            .font(
                                .system(
                                    size: density.titleFontSize,
                                    weight: .regular,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(
                                selected
                                ? Color.white.opacity(0.95)
                                : Color.primary.opacity(0.88)
                            )
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                    }

                    if overflow > 0 {
                        Text("+\(overflow) more")
                            .font(
                                .system(
                                    size: density == .menu ? 7.5 : 9,
                                    weight: .medium,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(
                                selected
                                ? Color.white.opacity(0.72)
                                : Color.secondary
                            )
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(
                .horizontal,
                density == .menu ? 4 : 6
            )
            .padding(
                .vertical,
                density == .menu ? 3 : 5
            )
            .frame(
                maxWidth: .infinity,
                minHeight: density.cellHeight,
                maxHeight: density.cellHeight,
                alignment: .topLeading
            )
            .background(
                RoundedRectangle(
                    cornerRadius: density == .menu ? 7 : 9
                )
                .fill(
                    selected
                    ? Color.accentColor
                    : (
                        today
                        ? Color.primary.opacity(0.07)
                        : Color.clear
                    )
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: density == .menu ? 7 : 9
                )
                .stroke(
                    today && !selected
                    ? Color.primary.opacity(0.10)
                    : Color.clear,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CalendarAgendaView: View {
    @ObservedObject var state: CalendarMenuState
    let plannerMode: Bool
    var onEdit: ((EKEvent) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(
                    state.selectedDate.formatted(
                        .dateTime
                            .weekday(.wide)
                            .day()
                            .month(.abbreviated)
                    )
                )
                .font(
                    .system(
                        size: plannerMode ? 16 : 13,
                        weight: .semibold,
                        design: .rounded
                    )
                )

                Spacer()

                Text(
                    "\(state.selectedEvents.count) event\(state.selectedEvents.count == 1 ? "" : "s")"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if state.accessDenied {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calendar access is off.")
                        .font(.caption)

                    Button("Open Privacy Settings") {
                        if let url = URL(
                            string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                        ) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                }
            } else if !state.accessGranted {
                ProgressView()
                    .controlSize(.small)
            } else if state.selectedEvents.isEmpty {
                Text("Nothing scheduled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
            } else {
                ScrollView {
                    LazyVStack(spacing: plannerMode ? 7 : 5) {
                        ForEach(
                            state.selectedEvents,
                            id: \.calendarItemIdentifier
                        ) { event in
                            eventRow(event)
                        }
                    }
                }
            }
        }
    }

    private func eventRow(_ event: EKEvent) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.28))
                .frame(
                    width: 3,
                    height: plannerMode ? 38 : 30
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "Untitled")
                    .font(
                        .system(
                            size: plannerMode ? 13 : 12,
                            weight: .medium
                        )
                    )
                    .lineLimit(1)

                Text(eventSubtitle(event))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if plannerMode,
               let onEdit,
               event.calendar.allowsContentModifications {
                Button {
                    onEdit(event)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("Edit event")
            }

            if !event.isAllDay,
               event.endDate > Date() {
                Button {
                    state.startFocus(for: event)
                } label: {
                    Image(systemName: "timer")
                }
                .buttonStyle(.plain)
                .help("Start in Focus")
            }

            if plannerMode,
               event.calendar.allowsContentModifications {
                Button {
                    state.deleteEvent(event)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete event")
            }
        }
        .padding(.vertical, plannerMode ? 4 : 2)
    }

    private func eventSubtitle(_ event: EKEvent) -> String {
        if event.isAllDay {
            return "all day · \(event.calendar.title)"
        }

        let start = event.startDate.formatted(
            date: .omitted,
            time: .shortened
        )
        let end = event.endDate.formatted(
            date: .omitted,
            time: .shortened
        )
        return "\(start)–\(end) · \(event.calendar.title)"
    }
}

private struct QuickAddView: View {
    @ObservedObject var state: CalendarMenuState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Time block")
                .font(
                    .system(
                        size: 13,
                        weight: .semibold,
                        design: .rounded
                    )
                )

            TextField(
                "What are you doing?",
                text: $state.draftTitle
            )
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                DatePicker(
                    "Start",
                    selection: $state.draftStart,
                    displayedComponents: [.date, .hourAndMinute]
                )

                DatePicker(
                    "End",
                    selection: $state.draftEnd,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }

            Picker(
                "Calendar",
                selection: Binding(
                    get: { state.selectedCalendarID },
                    set: { state.setDefaultCreateCalendarID($0) }
                )
            ) {
                ForEach(
                    state.writableCalendars,
                    id: \.calendarIdentifier
                ) { calendar in
                    Text(calendar.title)
                        .tag(calendar.calendarIdentifier)
                }
            }

            HStack {
                Button("Add") {
                    state.createBlock()
                }
                .disabled(
                    !state.accessGranted ||
                    state.writableCalendars.isEmpty
                )

                Button {
                    state.createBlock(
                        startFocusAfterSave: true
                    )
                } label: {
                    Label(
                        "Add & Focus",
                        systemImage: "timer"
                    )
                }
                .disabled(
                    !state.accessGranted ||
                    state.writableCalendars.isEmpty
                )

                Spacer()
            }

            if !state.statusMessage.isEmpty {
                Text(state.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

struct CalendarMenuView: View {
    @ObservedObject var state: CalendarMenuState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .semibold))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Planner")
                        .font(.system(size: 13, weight: .semibold))

                    if let next = state.nextUpcomingBlock {
                        Text(nextBlockText(next))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("No upcoming block")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            if state.focusActive {
                HStack(spacing: 5) {
                    Image(systemName: "timer")

                    Text(state.focusLabel ?? "Focus")
                        .lineLimit(1)

                    Spacer()

                    Text(state.deadlockLinked ? "protected" : "active")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                state.showPlannerWindow()
            } label: {
                HStack {
                    Image(systemName: "rectangle.grid.2x2")
                    Text("Open Command Center")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            if let next = state.nextUpcomingBlock,
               !next.isAllDay,
               next.endDate > Date() {
                Button {
                    state.startFocus(for: next)
                } label: {
                    Label("Start next block", systemImage: "timer")
                }
                .buttonStyle(.plain)
            }

            Button {
                state.showSettingsWindow()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .onAppear {
            state.onPopoverAppear()
        }
    }

    private func nextBlockText(_ event: EKEvent) -> String {
        let title = (event.title ?? "Untitled")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let when: String

        if Calendar.current.isDateInToday(event.startDate) {
            when = event.startDate.formatted(
                date: .omitted,
                time: .shortened
            )
        } else {
            when = event.startDate.formatted(
                .dateTime
                    .weekday(.abbreviated)
                    .hour()
                    .minute()
            )
        }

        return "\(when) · \(title)"
    }
}

private struct UpcomingBlocksView: View {
    @ObservedObject var state: CalendarMenuState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Assigned")
                        .font(.system(size: 16, weight: .semibold))
                    Text(state.futureCalendarName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(state.upcomingBlocks.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if state.upcomingBlocks.isEmpty {
                Text("No future time blocks assigned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(
                            state.upcomingBlocks,
                            id: \.calendarItemIdentifier
                        ) { event in
                            upcomingRow(event)
                        }
                    }
                }
            }
        }
    }

    private func upcomingRow(_ event: EKEvent) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "Untitled")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(eventSubtitle(event))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if event.calendar.allowsContentModifications {
                Button {
                    state.showEventEditor(event)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("Edit")
            }

            if !event.isAllDay, event.endDate > Date() {
                Button {
                    state.startFocus(for: event)
                } label: {
                    Image(systemName: "timer")
                }
                .buttonStyle(.plain)
                .help("Start in Focus")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private func eventSubtitle(_ event: EKEvent) -> String {
        if event.isAllDay {
            return event.startDate.formatted(
                .dateTime
                    .weekday(.abbreviated)
                    .day()
                    .month(.abbreviated)
            ) + " · all day"
        }

        let date = event.startDate.formatted(
            .dateTime
                .weekday(.abbreviated)
                .day()
                .month(.abbreviated)
        )
        let start = event.startDate.formatted(
            date: .omitted,
            time: .shortened
        )
        let end = event.endDate.formatted(
            date: .omitted,
            time: .shortened
        )
        return "\(date) · \(start)–\(end)"
    }
}

private struct FocusHistoryView: View {
    @ObservedObject var state: CalendarMenuState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("History")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(state.focusHistory.count) sessions")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if state.focusHistory.isEmpty {
                Text("No Focus history yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(state.focusHistory) { entry in
                            historyRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: FocusHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(
                    (entry.label?.isEmpty == false)
                    ? entry.label!
                    : "Focus session"
                )
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

                Spacer()

                Text("\(entry.minutes)m")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(
                    entry.date.formatted(
                        .dateTime
                            .weekday(.abbreviated)
                            .day()
                            .month(.abbreviated)
                            .hour()
                            .minute()
                    )
                )

                Text("·")

                Text(
                    entry.kind == "completed"
                    ? "completed"
                    : "stopped"
                )

                if let rating = entry.rating {
                    Text("· \(rating)/5")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let why = entry.why, !why.isEmpty {
                Text(why)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let improve = entry.improve, !improve.isEmpty {
                Text("next: \(improve)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

private struct PlannerSidebar: View {
    @ObservedObject var state: CalendarMenuState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PLANNER")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 3)

            sidebarButton(
                "Dashboard",
                icon: "rectangle.grid.2x2",
                id: "dashboard"
            )
            sidebarButton(
                "Calendar",
                icon: "calendar",
                id: "calendar"
            )
            sidebarButton(
                "Time Blocks",
                icon: "clock",
                id: "blocks"
            )
            sidebarButton(
                "History",
                icon: "clock.arrow.circlepath",
                id: "history"
            )

            Spacer()

            if state.focusActive {
                VStack(alignment: .leading, spacing: 3) {
                    Label(
                        state.focusLabel ?? "Focus",
                        systemImage: "timer"
                    )
                    .lineLimit(1)

                    Text(
                        state.deadlockLinked
                        ? "deadlock protecting"
                        : "deadlock unavailable"
                    )
                    .foregroundStyle(.secondary)
                }
                .font(.caption2)
                .padding(10)
            }

            Button {
                state.showSettingsWindow()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .padding(.vertical, 12)
        .frame(width: 170)
        .background(Color.primary.opacity(0.025))
    }

    private func sidebarButton(
        _ title: String,
        icon: String,
        id: String
    ) -> some View {
        Button {
            state.setPlannerPanel(id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)

                Text(title)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        state.plannerPanel == id
                        ? Color.primary.opacity(0.09)
                        : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }
}

private struct PlannerDashboardView: View {
    @ObservedObject var state: CalendarMenuState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dashboardHeader

                HStack(alignment: .top, spacing: 14) {
                    focusCard
                    nextBlockCard
                }

                HStack(alignment: .top, spacing: 14) {
                    todayCard
                    goalsCard
                }

                recentHistoryCard
            }
            .padding(20)
        }
    }

    private var dashboardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Command Center")
                    .font(
                        .system(
                            size: 24,
                            weight: .semibold,
                            design: .rounded
                        )
                    )

                Text(
                    Date().formatted(
                        .dateTime
                            .weekday(.wide)
                            .day()
                            .month(.wide)
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                state.reloadOverviewData()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
    }

    private var focusCard: some View {
        plannerCard(title: "Focus", icon: "timer") {
            if state.focusActive {
                Text(state.focusLabel ?? "Focus")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                if state.focusCountUp {
                    if let startedAt = state.focusStartedAt {
                        Text(
                            "counting up since \(startedAt.formatted(date: .omitted, time: .shortened))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("count-up session")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let deadline = state.focusDeadline {
                    Text(
                        "until \(deadline.formatted(date: .omitted, time: .shortened))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text(
                    state.deadlockLinked
                    ? "Distractions protected by deadlock"
                    : "deadlock unavailable"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Text("No active session")
                    .font(.system(size: 15, weight: .medium))

                Text(
                    state.deadlockLinked
                    ? "deadlock ready"
                    : "deadlock unavailable"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var nextBlockCard: some View {
        plannerCard(title: "Next block", icon: "arrow.right.circle") {
            if let event = state.nextUpcomingBlock {
                Text(event.title ?? "Untitled")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)

                Text(eventRange(event))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !event.isAllDay, event.endDate > Date() {
                    Button {
                        state.startFocus(for: event)
                    } label: {
                        Label("Start in Focus", systemImage: "timer")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("Nothing assigned")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var todayCard: some View {
        plannerCard(title: "Today", icon: "sun.max") {
            if state.todayUpcomingBlocks.isEmpty {
                Text("No remaining blocks today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(
                    Array(state.todayUpcomingBlocks.prefix(5)),
                    id: \.calendarItemIdentifier
                ) { event in
                    HStack(alignment: .firstTextBaseline) {
                        Text(
                            event.startDate.formatted(
                                date: .omitted,
                                time: .shortened
                            )
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 68, alignment: .leading)

                        Text(event.title ?? "Untitled")
                            .font(.caption)
                            .lineLimit(1)

                        Spacer()
                    }
                }
            }
        }
    }

    private var goalsCard: some View {
        plannerCard(
            title: "Goals / exams",
            icon: "flag"
        ) {
            if state.nextGoalEvents.isEmpty {
                Text("Nothing upcoming.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(
                    state.nextGoalEvents,
                    id: \.calendarItemIdentifier
                ) { event in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title ?? "Untitled")
                            .font(.caption)
                            .lineLimit(1)

                        Text(
                            event.startDate.formatted(
                                .dateTime
                                    .weekday(.abbreviated)
                                    .day()
                                    .month(.abbreviated)
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var recentHistoryCard: some View {
        plannerCard(
            title: "Recent work",
            icon: "clock.arrow.circlepath"
        ) {
            if state.recentHistory.isEmpty {
                Text("No Focus history yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.recentHistory) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(
                                (entry.label?.isEmpty == false)
                                ? entry.label!
                                : "Focus session"
                            )
                            .font(.caption)
                            .lineLimit(1)

                            Text(
                                entry.date.formatted(
                                    .dateTime
                                        .weekday(.abbreviated)
                                        .hour()
                                        .minute()
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let planned = entry.plannedMinutes {
                            Text("\(entry.minutes)m / \(planned)m")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(entry.minutes)m")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func eventRange(_ event: EKEvent) -> String {
        if event.isAllDay {
            return event.startDate.formatted(
                .dateTime
                    .weekday(.wide)
                    .day()
                    .month(.abbreviated)
            ) + " · all day"
        }

        let date = event.startDate.formatted(
            .dateTime
                .weekday(.wide)
                .day()
                .month(.abbreviated)
        )
        let start = event.startDate.formatted(
            date: .omitted,
            time: .shortened
        )
        let end = event.endDate.formatted(
            date: .omitted,
            time: .shortened
        )
        return "\(date) · \(start)–\(end)"
    }

    @ViewBuilder
    private func plannerCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))

            content()
        }
        .padding(14)
        .frame(
            maxWidth: .infinity,
            minHeight: 150,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

private struct PlannerCalendarView: View {
    @ObservedObject var state: CalendarMenuState

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: state.previousMonth) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(
                            state.visibleMonth.formatted(
                                .dateTime.month(.wide).year()
                            )
                        )
                        .font(
                            .system(
                                size: 18,
                                weight: .semibold,
                                design: .rounded
                            )
                        )

                        Text(state.monthPreviewCalendarName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Today", action: state.goToToday)

                    Button(action: state.nextMonth) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)

                CalendarMonthGrid(
                    state: state,
                    density: .planner
                )
                .padding(18)

                Spacer(minLength: 0)
            }
            .frame(minWidth: 620)

            VStack(spacing: 0) {
                CalendarAgendaView(
                    state: state,
                    plannerMode: true,
                    onEdit: { event in
                        state.showEventEditor(event)
                    }
                )
                .padding(16)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .top
                )

                Divider()

                QuickAddView(state: state)
                    .padding(16)
            }
            .frame(
                minWidth: 340,
                idealWidth: 380,
                maxWidth: 440
            )
        }
    }
}

private struct PlannerBlocksView: View {
    @ObservedObject var state: CalendarMenuState

    var body: some View {
        HSplitView {
            UpcomingBlocksView(state: state)
                .padding(20)
                .frame(minWidth: 560)

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Assign a block")
                        .font(.system(size: 17, weight: .semibold))

                    Text(
                        "Stored in Apple Calendar · started with Focus · protected by deadlock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)

                Divider()

                QuickAddView(state: state)
                    .padding(18)

                Spacer()
            }
            .frame(
                minWidth: 340,
                idealWidth: 380,
                maxWidth: 440
            )
        }
    }
}

private struct PlannerHistoryView: View {
    @ObservedObject var state: CalendarMenuState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("History")
                        .font(
                            .system(
                                size: 22,
                                weight: .semibold,
                                design: .rounded
                            )
                        )

                    Text("What was actually done in Focus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    state.loadFocusHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }

            if state.focusHistory.isEmpty {
                Text("No Focus history yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(state.focusHistory) { entry in
                            historyRow(entry)
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    private func historyRow(
        _ entry: FocusHistoryEntry
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(
                    (entry.label?.isEmpty == false)
                    ? entry.label!
                    : "Focus session"
                )
                .font(.system(size: 14, weight: .medium))

                Text(
                    entry.date.formatted(
                        .dateTime
                            .weekday(.abbreviated)
                            .day()
                            .month(.abbreviated)
                            .hour()
                            .minute()
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                if let why = entry.why, !why.isEmpty {
                    Text(why)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let improve = entry.improve, !improve.isEmpty {
                    Text("next · \(improve)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let planned = entry.plannedMinutes {
                    Text("\(entry.minutes)m actual")
                        .font(.caption.monospacedDigit())

                    Text("\(planned)m planned")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(entry.minutes)m")
                        .font(.caption.monospacedDigit())
                }

                Text(
                    entry.kind == "completed"
                    ? "completed"
                    : "stopped"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                if let rating = entry.rating {
                    Text("\(rating)/5")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

struct CalendarPlannerView: View {
    @ObservedObject var state: CalendarMenuState

    var body: some View {
        HStack(spacing: 0) {
            PlannerSidebar(state: state)

            Divider()

            Group {
                switch state.plannerPanel {
                case "calendar":
                    PlannerCalendarView(state: state)
                case "blocks":
                    PlannerBlocksView(state: state)
                case "history":
                    PlannerHistoryView(state: state)
                default:
                    PlannerDashboardView(state: state)
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            state.onPlannerAppear()
        }
    }
}

struct CalendarSettingsView: View {
    @ObservedObject var state: CalendarMenuState

    var body: some View {
        Form {
            Section("Month overview") {
                Picker(
                    "Show entries from",
                    selection: Binding(
                        get: {
                            state.monthPreviewCalendarID
                        },
                        set: {
                            state.setMonthPreviewCalendarID($0)
                        }
                    )
                ) {
                    ForEach(
                        state.calendars,
                        id: \.calendarIdentifier
                    ) { calendar in
                        Text(calendar.title)
                            .tag(calendar.calendarIdentifier)
                    }
                }

                Text(
                    "Only this calendar is written inside the month cells. Day view still shows every calendar."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Assigned time blocks") {
                Picker(
                    "Future blocks calendar",
                    selection: Binding(
                        get: {
                            state.futureCalendarID
                        },
                        set: {
                            state.setFutureCalendarID($0)
                        }
                    )
                ) {
                    ForEach(
                        state.calendars,
                        id: \.calendarIdentifier
                    ) { calendar in
                        Text(calendar.title)
                            .tag(calendar.calendarIdentifier)
                    }
                }

                Text(
                    "The Time Blocks screen and Dashboard read assigned work from this calendar for the next 180 days."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("New time blocks") {
                Picker(
                    "Default calendar",
                    selection: Binding(
                        get: {
                            state.selectedCalendarID
                        },
                        set: {
                            state.setDefaultCreateCalendarID($0)
                        }
                    )
                ) {
                    ForEach(
                        state.writableCalendars,
                        id: \.calendarIdentifier
                    ) { calendar in
                        Text(calendar.title)
                            .tag(calendar.calendarIdentifier)
                    }
                }
            }

            Section("Integration") {
                LabeledContent(
                    "Focus",
                    value: state.focusLinked
                        ? "Ready"
                        : "Not found"
                )

                LabeledContent(
                    "deadlock",
                    value: state.deadlockLinked
                        ? "Ready"
                        : "Unavailable"
                )
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 460, height: 430)
        .onAppear {
            state.refreshIntegrationStatus()
        }
    }
}

private struct EventEditorView: View {
    @ObservedObject var state: CalendarMenuState
    @ObservedObject var model: EventEditorModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit event")
                .font(
                    .system(
                        size: 18,
                        weight: .semibold,
                        design: .rounded
                    )
                )

            TextField("Title", text: $model.title)
                .textFieldStyle(.roundedBorder)

            Toggle("All day", isOn: $model.allDay)

            if model.allDay {
                DatePicker(
                    "Start",
                    selection: $model.start,
                    displayedComponents: [.date]
                )

                DatePicker(
                    "End",
                    selection: $model.end,
                    displayedComponents: [.date]
                )
            } else {
                DatePicker(
                    "Start",
                    selection: $model.start,
                    displayedComponents: [
                        .date,
                        .hourAndMinute
                    ]
                )

                DatePicker(
                    "End",
                    selection: $model.end,
                    displayedComponents: [
                        .date,
                        .hourAndMinute
                    ]
                )
            }

            Picker(
                "Calendar",
                selection: $model.calendarID
            ) {
                ForEach(
                    state.writableCalendars,
                    id: \.calendarIdentifier
                ) { calendar in
                    Text(calendar.title)
                        .tag(calendar.calendarIdentifier)
                }
            }

            if !state.statusMessage.isEmpty {
                Text(state.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    onClose()
                }

                Button("Save") {
                    if state.updateEvent(
                        model.event,
                        title: model.title,
                        start: model.start,
                        end: model.end,
                        allDay: model.allDay,
                        calendarID: model.calendarID
                    ) {
                        onClose()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 430)
    }
}

@main
struct CalMenuApp: App {
    private let state = CalendarMenuState()

    init() {
        NSApplication.shared.setActivationPolicy(
            .accessory
        )
    }

    var body: some Scene {
        MenuBarExtra {
            CalendarMenuView(state: state)
        } label: {
            Image(systemName: "calendar")
                .accessibilityLabel("calmenu")
        }
        .menuBarExtraStyle(.window)
    }
}
