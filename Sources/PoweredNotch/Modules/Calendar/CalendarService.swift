import AppKit
import Combine
import EventKit
import SwiftUI

struct CalendarEventItem: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var colorHex: String
    var calendarName: String
    var location: String?
    var meetingURL: URL?

    var isOngoing: Bool {
        let now = Date()
        return start <= now && now < end
    }
}

struct ReminderItem: Identifiable, Equatable {
    var id: String
    var title: String
    var due: Date?
    var colorHex: String
    var isOverdue: Bool { (due ?? .distantFuture) < Date() }
}

struct CalendarSource: Identifiable, Equatable {
    var id: String
    var title: String
    var colorHex: String
    var accountName: String
}

/// Calendario e promemoria di sistema. Non chiede mai permessi da solo: la
/// richiesta parte solo quando l'utente la fa dal widget o dalle impostazioni.
@MainActor
final class CalendarService: ObservableObject {
    enum Access: Equatable {
        case undetermined, granted, denied
    }

    @Published private(set) var eventsAccess: Access = .undetermined
    @Published private(set) var remindersAccess: Access = .undetermined
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date()) {
        didSet { reload() }
    }
    @Published private(set) var events: [CalendarEventItem] = []
    @Published private(set) var upcoming: [CalendarEventItem] = []
    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var sources: [CalendarSource] = []

    var config = CalendarConfig() {
        didSet { if config != oldValue { reload() } }
    }
    var peekLeadMinutes: Double = 5

    /// Chiamata una volta per ogni evento in arrivo.
    var onUpcoming: ((CalendarEventItem) -> Void)?

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var dayTimer: Timer?
    private var announced: Set<String> = []
    private var started = false
    private var isPreview = false

    func start() {
        guard !started, !isPreview else { return }
        started = true
        refreshAccess()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.minuteTick() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        dayTimer = timer
        reload()
    }

    func stop() {
        guard started else { return }
        started = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        dayTimer?.invalidate()
        dayTimer = nil
    }

    func seedForPreview(events: [CalendarEventItem], reminders: [ReminderItem]) {
        isPreview = true
        eventsAccess = .granted
        remindersAccess = .granted
        self.events = events
        upcoming = events
        self.reminders = reminders
    }

    private func refreshAccess() {
        eventsAccess = Self.map(EKEventStore.authorizationStatus(for: .event))
        remindersAccess = Self.map(EKEventStore.authorizationStatus(for: .reminder))
    }

    private static func map(_ status: EKAuthorizationStatus) -> Access {
        switch status {
        case .notDetermined: .undetermined
        case .fullAccess, .authorized: .granted
        default: .denied
        }
    }

    // MARK: - Permessi

    func requestEventsAccess() {
        guard eventsAccess != .denied else {
            openPrivacySettings("Privacy_Calendars")
            return
        }
        store.requestFullAccessToEvents { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshAccess()
                self?.reload()
            }
        }
    }

    func requestRemindersAccess() {
        guard remindersAccess != .denied else {
            openPrivacySettings("Privacy_Reminders")
            return
        }
        store.requestFullAccessToReminders { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshAccess()
                self?.reload()
            }
        }
    }

    private func openPrivacySettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Lettura

    func reload() {
        guard !isPreview else { return }
        refreshAccess()
        if eventsAccess == .granted {
            loadSources()
            loadEvents()
        } else {
            events = []
            upcoming = []
        }
        if remindersAccess == .granted, config.showReminders {
            loadReminders()
        } else {
            reminders = []
        }
    }

    private func loadSources() {
        sources = store.calendars(for: .event).map { calendar in
            CalendarSource(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                colorHex: Self.hex(calendar.color),
                accountName: calendar.source?.title ?? ""
            )
        }
        .sorted { ($0.accountName, $0.title) < ($1.accountName, $1.title) }
    }

    private var visibleCalendars: [EKCalendar] {
        store.calendars(for: .event).filter { !config.hiddenCalendarIDs.contains($0.calendarIdentifier) }
    }

    private func loadEvents() {
        let calendars = visibleCalendars
        guard !calendars.isEmpty else {
            events = []
            upcoming = []
            return
        }
        let dayStart = Calendar.current.startOfDay(for: selectedDate)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        events = fetch(from: dayStart, to: dayEnd, calendars: calendars)
            .filter { config.showAllDay || !$0.isAllDay }

        let now = Date()
        let horizon = now.addingTimeInterval(36 * 3600)
        upcoming = fetch(from: now, to: horizon, calendars: calendars)
            .filter { !$0.isAllDay && $0.end > now }
    }

    private func fetch(from start: Date, to end: Date, calendars: [EKCalendar]) -> [CalendarEventItem] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).map { event in
            CalendarEventItem(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Senza titolo",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                colorHex: Self.hex(event.calendar?.color),
                calendarName: event.calendar?.title ?? "",
                location: event.location,
                meetingURL: Self.meetingURL(in: event)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.start < rhs.start
        }
    }

    private func loadReminders() {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] items in
            let mapped = (items ?? []).map { reminder in
                ReminderItem(
                    id: reminder.calendarItemIdentifier,
                    title: reminder.title ?? "Senza titolo",
                    due: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                    colorHex: Self.hex(reminder.calendar?.color)
                )
            }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            .prefix(20)
            let list = Array(mapped)
            Task { @MainActor in self?.reminders = list }
        }
    }

    private func minuteTick() {
        // A mezzanotte la data selezionata "di oggi" deve seguire il calendario.
        let today = Calendar.current.startOfDay(for: Date())
        if selectedDate < today, Date().timeIntervalSince(selectedDate) < 26 * 3600 {
            selectedDate = today
        } else {
            reload()
        }
        guard peekLeadMinutes > 0 else { return }
        let now = Date()
        for event in upcoming where !announced.contains(event.id) {
            let wait = event.start.timeIntervalSince(now)
            if wait > 0, wait <= peekLeadMinutes * 60 {
                announced.insert(event.id)
                onUpcoming?(event)
            }
        }
    }

    // MARK: - Azioni

    func complete(_ reminder: ReminderItem) {
        guard let item = store.calendarItem(withIdentifier: reminder.id) as? EKReminder else { return }
        item.isCompleted = true
        try? store.save(item, commit: true)
        reminders.removeAll { $0.id == reminder.id }
    }

    func open(_ event: CalendarEventItem) {
        if let url = URL(string: "ical://ekevent/\(event.id)?method=show&options=more") {
            NSWorkspace.shared.open(url)
        }
    }

    func openCalendarApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    func openRemindersApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app"))
    }

    // MARK: - Utilità

    /// Cerca il link di una riunione dove di solito finisce: URL, luogo, note.
    private static func meetingURL(in event: EKEvent) -> URL? {
        let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "whereby.com", "meet.jit.si", "facetime.apple.com"]
        func matches(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        if let url = event.url, matches(url) { return url }

        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url).first(where: matches)
    }

    private static func hex(_ color: NSColor?) -> String {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return "#8E8E93" }
        return String(
            format: "#%02X%02X%02X",
            Int(rgb.redComponent * 255),
            Int(rgb.greenComponent * 255),
            Int(rgb.blueComponent * 255)
        )
    }
}
