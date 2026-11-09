import SwiftUI

/// Decide se un elemento compatto ha qualcosa da dire adesso. La notch resta
/// invisibile finché non serve: un elemento senza notizie non occupa spazio.
@MainActor
struct CompactAvailability {
    let summary: SessionSummary
    let media: MediaService
    let calendar: CalendarService
    let battery: BatteryMonitor
    let timer: TimerStore
    let shelf: ShelfStore
    let custom: CustomWidgetStore

    func isActive(_ id: String) -> Bool {
        if let customID = ModuleCatalog.customID(fromKind: id) {
            guard let output = custom.outputs[customID] else { return false }
            return output.active ?? (output.compact ?? output.text != nil)
        }
        switch id {
        case "agents.status", "agents.dots", "agents.count", "agents.activity":
            return !summary.dots.isEmpty
        case "media.artwork", "media.visualizer", "media.title":
            return media.isActive
        case "calendar.next":
            return calendar.upcoming.first.map { $0.isOngoing || $0.start.timeIntervalSinceNow < 3600 } ?? false
        case "battery.level":
            return battery.state.hasBattery
        case "timer.remaining":
            return timer.isActive
        case "shelf.count":
            return !shelf.items.isEmpty
        case "system.cpu", "clock.time":
            return true
        default:
            return false
        }
    }
}

/// Disegna un elemento compatto. Ogni elemento osserva solo il servizio che gli serve:
/// la notch chiusa resta sullo schermo tutto il giorno, e un cambiamento qualsiasi
/// non deve ridisegnare anche ciò che non c'entra.
struct CompactItemView: View {
    let id: String

    var body: some View {
        if let customID = ModuleCatalog.customID(fromKind: id) {
            CustomCompactItem(customID: customID)
        } else {
            switch id {
            case "agents.status":    AgentsStatusItem()
            case "agents.dots":      AgentsDotsItem()
            case "agents.count":     AgentsCountItem()
            case "agents.activity":  AgentsActivityItem()
            case "media.artwork":    MediaArtworkItem()
            case "media.visualizer": MediaVisualizerItem()
            case "media.title":      MediaTitleItem()
            case "calendar.next":    NextEventItem()
            case "battery.level":    BatteryItem()
            case "timer.remaining":  TimerCompact()
            case "shelf.count":      ShelfCountItem()
            case "system.cpu":       SystemCPUCompact()
            case "clock.time":       ClockItem()
            default:                 EmptyView()
            }
        }
    }
}

private struct CustomCompactItem: View {
    let customID: String

    @EnvironmentObject private var custom: CustomWidgetStore
    @Environment(\.notchTheme) private var theme

    var body: some View {
        let output = custom.outputs[customID]
        HStack(spacing: 4) {
            if let symbol = output?.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color(hexString: output?.tint) ?? theme.secondary)
            }
            if let text = output?.compact ?? output?.text {
                Text(text)
                    .font(theme.font(11, .medium))
                    .foregroundStyle(Color(hexString: output?.tint) ?? theme.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct AgentsStatusItem: View {
    @EnvironmentObject private var summary: SessionSummary

    var body: some View {
        AgentsStatusGlyph(status: summary.aggregate ?? .idle, accent: Color(hexString: summary.accentHex))
    }
}

private struct AgentsDotsItem: View {
    @EnvironmentObject private var summary: SessionSummary

    var body: some View {
        AgentsDots(dots: summary.dots)
    }
}

private struct AgentsCountItem: View {
    @EnvironmentObject private var summary: SessionSummary

    var body: some View {
        AgentsCount(count: summary.dots.count, status: summary.aggregate ?? .idle)
    }
}

/// L'unico elemento che segue le sessioni riga per riga: racconta proprio quello.
private struct AgentsActivityItem: View {
    @EnvironmentObject private var sessions: SessionStore

    var body: some View {
        AgentsActivityText(session: sessions.leadingSession)
    }
}

private struct MediaArtworkItem: View {
    @EnvironmentObject private var media: MediaService

    var body: some View {
        ArtworkThumbnail(image: media.artwork, size: 20, radius: 5, showsPlaceholder: true)
    }
}

private struct MediaVisualizerItem: View {
    @EnvironmentObject private var media: MediaService
    @Environment(\.notchTheme) private var theme

    var body: some View {
        AudioVisualizer(
            color: theme.accent,
            isPlaying: media.nowPlaying?.isPlaying == true,
            style: theme.appearance.visualizer == .off ? .bars : theme.appearance.visualizer
        )
        .frame(width: 20, height: 14)
    }
}

private struct MediaTitleItem: View {
    @EnvironmentObject private var media: MediaService
    @Environment(\.notchTheme) private var theme

    var body: some View {
        MarqueeText(text: media.nowPlaying?.title ?? "", size: 11, weight: .medium, color: theme.secondary)
            .frame(width: 96)
    }
}

private struct NextEventItem: View {
    @EnvironmentObject private var calendar: CalendarService

    var body: some View {
        NextEventCompact(event: calendar.upcoming.first { $0.isOngoing || $0.start.timeIntervalSinceNow < 3600 })
    }
}

private struct BatteryItem: View {
    @EnvironmentObject private var battery: BatteryMonitor

    var body: some View {
        BatteryCompact(state: battery.state)
    }
}

private struct ShelfCountItem: View {
    @EnvironmentObject private var shelf: ShelfStore
    @Environment(\.notchTheme) private var theme

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "tray.full.fill").font(.system(size: 10, weight: .semibold))
            Text("\(shelf.items.count)").font(theme.numberFont(11))
        }
        .foregroundStyle(theme.secondary)
    }
}

private struct ClockItem: View {
    @Environment(\.notchTheme) private var theme

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, style: .time)
                .font(theme.numberFont(11.5))
                .foregroundStyle(theme.secondary)
        }
    }
}

// MARK: - Agenti

/// L'icona di stato. La forma dice cosa succede ancora prima del colore: chi lavora
/// "pulsa", chi aspetta ti guarda con la mano alzata, chi è bloccato ha il lucchetto.
struct AgentsStatusGlyph: View {
    var status: SessionStatus
    var accent: Color?

    private var symbol: String {
        switch status {
        case .working:   "sparkle"
        case .attention: "hand.raised.fill"
        case .blocked:   "lock.fill"
        case .error:     "exclamationmark.triangle.fill"
        case .done:      "checkmark.circle.fill"
        case .idle:      "moon.zzz.fill"
        case .ended:     "checkmark"
        }
    }

    private var color: Color {
        status == .working ? (accent ?? status.tint) : status.tint
    }

    var body: some View {
        PulsingSymbol(name: symbol, color: color, pulses: status.animates)
            .frame(width: 16, height: 16)
    }
}

/// Un pallino per sessione: si conta a colpo d'occhio e il colore dice chi chiama.
struct AgentsDots: View {
    var dots: [SessionSummary.Dot]
    private let maximum = 6

    @Environment(\.notchTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(dots.prefix(maximum))) { dot in
                PulseDot(status: dot.status, size: 6)
                    .frame(width: 10, height: 14)
                    .transition(.scale.combined(with: .opacity))
            }
            if dots.count > maximum {
                Text("+\(dots.count - maximum)")
                    .font(theme.numberFont(9.5))
                    .foregroundStyle(theme.tertiary)
                    .padding(.leading, 2)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dots.map(\.id))
    }
}

struct AgentsCount: View {
    var count: Int
    var status: SessionStatus

    @Environment(\.notchTheme) private var theme

    var body: some View {
        Text("\(count)")
            .font(theme.numberFont(11.5, .semibold))
            .foregroundStyle(status.needsYou ? status.tint : theme.secondary)
            .contentTransition(.numericText())
            .animation(.spring(response: 0.3), value: count)
    }
}

struct AgentsActivityText: View {
    var session: AgentSession?

    @Environment(\.notchTheme) private var theme

    private var text: String {
        guard let session else { return "" }
        if session.status.needsYou { return "\(session.project) · \(session.status.label)" }
        return session.activity ?? session.project
    }

    var body: some View {
        MarqueeText(text: text, size: 10.5, weight: .medium, color: theme.secondary)
            .frame(width: 104)
    }
}

// MARK: - Musica

struct ArtworkThumbnail: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat
    var showsPlaceholder = false

    @Environment(\.notchTheme) private var theme

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else if showsPlaceholder {
                ZStack {
                    theme.chipFill
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(theme.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Altri

struct NextEventCompact: View {
    var event: CalendarEventItem?

    @Environment(\.notchTheme) private var theme

    var body: some View {
        if let event {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                HStack(spacing: 5) {
                    Capsule()
                        .fill(Color(hexString: event.colorHex) ?? theme.accent)
                        .frame(width: 3, height: 12)
                    Text(event.title)
                        .font(theme.font(10.5, .medium))
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 88, alignment: .leading)
                    Text(event.isOngoing ? tr("ora") : Format.duration(event.start.timeIntervalSinceNow))
                        .font(theme.numberFont(10))
                        .foregroundStyle(theme.tertiary)
                }
            }
        }
    }
}

struct BatteryCompact: View {
    var state: BatteryState

    @Environment(\.notchTheme) private var theme

    private var color: Color {
        if state.isCharging || state.isPluggedIn { return Color(hex: 0x4ADE80) }
        if state.isLowPowerMode { return Color(hex: 0xFFC145) }
        if state.level <= 0.2 { return Color(hex: 0xFF5A63) }
        return theme.secondary
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("\(Int((state.level * 100).rounded()))")
                .font(theme.numberFont(10.5))
                .foregroundStyle(theme.secondary)
            BatteryGlyph(level: state.level, color: color, isCharging: state.isCharging || state.isPluggedIn)
        }
    }
}

/// La batteria disegnata a mano: quella dei simboli di sistema ha solo cinque livelli.
struct BatteryGlyph: View {
    var level: Double
    var color: Color
    var isCharging: Bool
    var width: CGFloat = 22

    var body: some View {
        let height = width * 0.5
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .stroke(.white.opacity(0.4), lineWidth: 1)
                RoundedRectangle(cornerRadius: height * 0.18, style: .continuous)
                    .fill(color)
                    .padding(1.5)
                    .frame(width: max(height * 0.3, (width - 2) * min(1, max(0.04, level))))
                if isCharging {
                    // Il fulmine bianco con un bordo scuro, come quello di macOS: si legge sia
                    // sopra il verde della carica sia sul vuoto della batteria. Nero da solo,
                    // su una batteria poco carica finiva sul fondo nero e sembrava una macchia.
                    ZStack {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: height * 0.98, weight: .black))
                            .foregroundStyle(.black.opacity(0.85))
                        Image(systemName: "bolt.fill")
                            .font(.system(size: height * 0.7, weight: .black))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(width: width - 2, height: height)
            Capsule()
                .fill(.white.opacity(0.4))
                .frame(width: 1.4, height: height * 0.38)
        }
    }
}

struct TimerCompact: View {
    @EnvironmentObject private var timer: TimerStore
    @Environment(\.notchTheme) private var theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: timer.isRunning ? 1 : 60)) { context in
            HStack(spacing: 4) {
                if let fraction = timer.fraction(at: context.date) {
                    ContextRing(fraction: fraction, tint: theme.accent, size: 12, lineWidth: 1.8)
                } else {
                    Image(systemName: "stopwatch.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
                Text(Format.countdown(timer.displaySeconds(at: context.date)))
                    .font(theme.numberFont(11))
                    .foregroundStyle(theme.primary)
            }
        }
    }
}

struct SystemCPUCompact: View {
    @EnvironmentObject private var system: SystemMonitor
    @Environment(\.notchTheme) private var theme

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "cpu").font(.system(size: 10, weight: .semibold))
            Text("\(Int(system.snapshot.cpu * 100))%").font(theme.numberFont(10.5))
        }
        .foregroundStyle(system.snapshot.cpu > 0.8 ? Color(hex: 0xFFC145) : theme.secondary)
        .onAppear { system.retain() }
        .onDisappear { system.release() }
    }
}
