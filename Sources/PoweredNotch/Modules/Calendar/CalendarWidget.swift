import SwiftUI

/// La settimana in una striscia, gli eventi del giorno scelto e i promemoria.
struct CalendarWidget: View {
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var actions: NotchActions
    @Environment(\.notchTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if calendar.eventsAccess == .granted {
                WeekStrip(selected: $calendar.selectedDate)
                content
            } else {
                accessPrompt
            }
        }
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 3) {
                if calendar.events.isEmpty {
                    Text("Niente in programma")
                        .font(theme.font(10.5))
                        .foregroundStyle(theme.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
                ForEach(calendar.events) { event in
                    EventRow(event: event, showJoin: settings.config.calendar.showJoinButton)
                }
                if settings.config.calendar.showReminders, Calendar.current.isDateInToday(calendar.selectedDate) {
                    if calendar.remindersAccess == .granted {
                        ForEach(calendar.reminders.prefix(6)) { reminder in
                            ReminderRow(reminder: reminder)
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .fadingBottom()
    }

    private var accessPrompt: some View {
        VStack(spacing: 7) {
            Spacer(minLength: 0)
            Image(systemName: "calendar")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(theme.tertiary)
            Text(calendar.eventsAccess == .denied ? "Accesso negato" : "Calendario")
                .font(theme.font(11, .medium))
                .foregroundStyle(theme.secondary)
            NotchPillButton(symbol: nil, label: calendar.eventsAccess == .denied ? "Apri Impostazioni" : "Consenti accesso", tint: theme.accent) {
                actions.keepOpenDuringSystemPrompt()
                calendar.requestEventsAccess()
                calendar.requestRemindersAccess()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

/// I sette giorni attorno a oggi: un click cambia il giorno mostrato.
private struct WeekStrip: View {
    @Binding var selected: Date
    @Environment(\.notchTheme) private var theme

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (-1...5).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                dayCell(day)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let calendar = Calendar.current
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day)
        return Button {
            selected = day
        } label: {
            VStack(spacing: 1.5) {
                Text(Self.weekday.string(from: day).uppercased())
                    .font(theme.font(8, .semibold))
                    .foregroundStyle(isToday ? theme.accent : theme.tertiary)
                Text("\(calendar.component(.day, from: day))")
                    .font(theme.numberFont(11, isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.black : (isToday ? theme.accent : theme.secondary))
                    .frame(width: 21, height: 21)
                    .background(Circle().fill(isSelected ? (isToday ? theme.accent : Color.white.opacity(0.85)) : .clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct EventRow: View {
    let event: CalendarEventItem
    var showJoin: Bool

    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var actions: NotchActions
    @Environment(\.notchTheme) private var theme
    @State private var hovering = false

    private var color: Color { Color(hexString: event.colorHex) ?? theme.accent }

    private var timeText: String {
        if event.isAllDay { return "Tutto il giorno" }
        return event.start.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(color)
                .frame(width: 3)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(theme.font(11, .medium))
                    .foregroundStyle(event.end < Date() ? theme.tertiary : theme.primary)
                    .lineLimit(1)
                Text(timeText)
                    .font(theme.numberFont(9.5))
                    .foregroundStyle(event.isOngoing ? color : theme.tertiary)
            }
            Spacer(minLength: 2)
            if showJoin, let url = event.meetingURL, event.end > Date() {
                NotchIconButton(symbol: "video.fill", size: 22, iconSize: 10, tint: color, help: "Entra nella riunione", isActive: true) {
                    NSWorkspace.shared.open(url)
                    actions.close()
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? theme.hoverFill : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            calendar.open(event)
            actions.close()
        }
        .help(event.title)
    }
}

private struct ReminderRow: View {
    let reminder: ReminderItem

    @EnvironmentObject private var calendar: CalendarService
    @Environment(\.notchTheme) private var theme
    @State private var hovering = false

    private var color: Color { Color(hexString: reminder.colorHex) ?? theme.accent }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                calendar.complete(reminder)
            } label: {
                Image(systemName: hovering ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
            }
            .buttonStyle(NotchPressStyle())
            .help("Segna come completato")

            Text(reminder.title)
                .font(theme.font(10.5))
                .foregroundStyle(reminder.isOverdue ? Color(hex: 0xFF8A80) : theme.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
