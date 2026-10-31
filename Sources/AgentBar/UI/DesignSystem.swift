import AppKit
import SwiftUI

enum Theme {
    static let peekWidth: CGFloat = 344
    static let deckWidth: CGFloat = 470
    static let deckMaxHeight: CGFloat = 610
    static let panelRadius: CGFloat = 24
    static let rowRadius: CGFloat = 15
    /// Margine trasparente attorno al pannello: serve all'ombra e alla scala d'ingresso.
    static let shadowPad: CGFloat = 32
    static let menuBarGap: CGFloat = 6
}

// MARK: - Colori

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init?(hexString: String?) {
        guard var value = hexString?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8, let number = UInt32(value, radix: 16) else { return nil }
        if value.count == 8 {
            self.init(hex: number >> 8, opacity: Double(number & 0xFF) / 255)
        } else {
            self.init(hex: number)
        }
    }

    /// Colore che segue l'aspetto chiaro/scuro della finestra che lo ospita.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }

    static let surfaceTint = adaptive(light: .white.opacity(0.55), dark: Color(hex: 0x0E1116).opacity(0.45))
    static let rowFill = adaptive(light: .black.opacity(0.040), dark: .white.opacity(0.052))
    static let rowFillHover = adaptive(light: .black.opacity(0.075), dark: .white.opacity(0.095))
    static let hairline = adaptive(light: .black.opacity(0.10), dark: .white.opacity(0.13))
    static let hairlineSoft = adaptive(light: .black.opacity(0.06), dark: .white.opacity(0.07))
    static let chipFill = adaptive(light: .black.opacity(0.055), dark: .white.opacity(0.075))
}

extension SessionStatus {
    /// Su fondo chiaro servono tinte più profonde: le stesse dei temi scuri
    /// diventerebbero illeggibili sul testo.
    var tint: Color {
        switch self {
        case .working:   .adaptive(light: Color(hex: 0x0B84C4), dark: Color(hex: 0x3BB9F5))
        case .attention: .adaptive(light: Color(hex: 0xB0700A), dark: Color(hex: 0xF5B942))
        case .blocked:   .adaptive(light: Color(hex: 0xD03B3B), dark: Color(hex: 0xF97066))
        case .idle:      .adaptive(light: Color(hex: 0x6C7A8C), dark: Color(hex: 0x8E9BAE))
        case .ended:     .adaptive(light: Color(hex: 0x77828F), dark: Color(hex: 0x6B7789))
        case .error:     .adaptive(light: Color(hex: 0xC22F36), dark: Color(hex: 0xF2545B))
        }
    }

    var gradient: LinearGradient {
        let base = tint
        return LinearGradient(
            colors: [base, base.opacity(0.55)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Solo gli stati vivi respirano: niente animazioni perenni per una sessione chiusa.
    var animates: Bool { self == .working || self == .attention || self == .blocked }
}

extension AgentSession {
    var accentColor: Color { Color(hexString: accentHex) ?? status.tint }
}

// MARK: - Superficie in vetro

struct PanelSurface<Content: View>: View {
    var radius: CGFloat = Theme.panelRadius
    var useGlass: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if #available(macOS 26.0, *), useGlass {
                content.glassEffect(.regular, in: .rect(cornerRadius: radius))
            } else {
                content.background(fallbackMaterial)
            }
        }
        .overlay(border)
        .shadow(color: .black.opacity(0.34), radius: 26, x: 0, y: 14)
        .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
    }

    private var fallbackMaterial: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.surfaceTint)
        }
    }

    /// Bordo con luce dall'alto: dà spessore al vetro senza disegnare una cornice piatta.
    private var border: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.adaptive(light: .white.opacity(0.9), dark: .white.opacity(0.22)),
                        Color.adaptive(light: .black.opacity(0.06), dark: .white.opacity(0.04))
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.8
            )
    }
}

// MARK: - Marchio

/// Il glifo dell'app: una finestrella di terminale con tre righe di output.
/// Vive in due posti — l'icona nella barra e la testata dei pannelli — e deve
/// essere riconoscibilmente la stessa forma in entrambi: è quel rimando a dire
/// "il pannello che si è aperto viene da quell'icona lì". Per questo lo disegna
/// un tipo solo, parametrico sull'altezza.
struct AgentGlyph: View {
    var height: CGFloat = 14.5
    var tint: Color = .primary
    /// Larghezze delle tre righe, in frazione dello spazio interno.
    var bars: [CGFloat] = [0.87, 0.51, 0.67]

    private var width: CGFloat { height * 1.14 }
    private var inset: CGFloat { height * 0.234 }
    private var innerWidth: CGFloat { width - inset * 2 }

    var body: some View {
        RoundedRectangle(cornerRadius: height * 0.28, style: .continuous)
            .strokeBorder(tint, lineWidth: max(1, height * 0.088))
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: height * 0.138) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, fraction in
                        Capsule(style: .continuous)
                            .fill(tint)
                            .frame(width: innerWidth * fraction, height: max(1, height * 0.103))
                    }
                }
                .padding(.leading, inset)
            }
    }
}

/// Marchio in testata ai pannelli: lo stesso glifo dell'icona in barra, fermo e
/// monocromatico. Qui il colore non lo mettiamo mai — nemmeno per segnalare che
/// un agent aspetta: quel messaggio lo danno già i pallini, i bordi e le tinte
/// delle righe, e un marchio acceso sarebbe solo il terzo rosso della stessa
/// schermata.
struct AppMark: View {
    var height: CGFloat = 21

    var body: some View {
        AgentGlyph(height: height, tint: .primary.opacity(0.7))
    }
}

// MARK: - Componenti

/// Vero solo mentre il pannello è davvero a schermo. Un pannello nascosto ha
/// comunque una vista viva: senza questo interruttore le animazioni continuano
/// a girare (e a costare CPU) anche quando nessuno le vede.
private struct PanelVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var panelIsVisible: Bool {
        get { self[PanelVisibleKey.self] }
        set { self[PanelVisibleKey.self] = newValue }
    }
}

/// Pallino di stato con alone che pulsa quando la sessione è viva.
struct PulseDot: View {
    var status: SessionStatus
    var size: CGFloat = 8

    @Environment(\.panelIsVisible) private var panelIsVisible
    @State private var expanded = false

    private var shouldPulse: Bool { status.animates && panelIsVisible }

    var body: some View {
        ZStack {
            if shouldPulse {
                Circle()
                    .fill(status.tint)
                    .frame(width: size, height: size)
                    .scaleEffect(expanded ? 2.4 : 1)
                    .opacity(expanded ? 0 : 0.45)
            }
            Circle()
                .fill(status.gradient)
                .frame(width: size, height: size)
                .shadow(color: status.tint.opacity(status.animates ? 0.9 : 0), radius: 4)
        }
        .frame(width: size * 2.6, height: size * 2.6)
        .onAppear { syncAnimation() }
        .onChange(of: status) { _, _ in syncAnimation() }
        .onChange(of: panelIsVisible) { _, _ in syncAnimation() }
    }

    private func syncAnimation() {
        guard shouldPulse else {
            // Niente animazione in corso: torna fermo, senza transizione.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { expanded = false }
            return
        }
        expanded = false
        let duration = status == .working ? 1.6 : 1.1
        withAnimation(.easeOut(duration: duration).repeatForever(autoreverses: false)) {
            expanded = true
        }
    }
}

/// Etichetta compatta per branch, modello, host…
struct MetaChip: View {
    var text: String
    var symbol: String?
    var tint: Color?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(tint ?? .secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            Capsule(style: .continuous)
                .fill(tint?.opacity(0.14) ?? Color.chipFill)
        )
    }
}

/// Barra sottile di riempimento del contesto.
struct ContextBar: View {
    var fraction: Double
    var tint: Color
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.hairlineSoft)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.75), fraction > 0.85 ? Color(hex: 0xF2545B) : tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(height, geometry.size.width * fraction))
            }
        }
        .frame(height: height)
    }
}

/// Bottone piatto con evidenziazione all'hover, usato nelle azioni delle card.
struct GhostButton: View {
    var symbol: String
    var label: String
    var tint: Color?
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                // Etichetta vuota = pulsante di sola icona.
                if !label.isEmpty {
                    Text(label).font(.system(size: 10.5, weight: .medium, design: .rounded))
                }
            }
            .foregroundStyle(hovering ? (tint ?? .primary) : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? (tint ?? .primary).opacity(0.13) : Color.chipFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(hovering ? (tint ?? .primary).opacity(0.28) : .clear, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

/// Bottone di sola icona per il footer.
struct IconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? Color.primary : .secondary)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovering ? Color.rowFillHover : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

// MARK: - Formattazione

enum Format {
    /// Durata compatta: 45s, 12m, 2h 05m, 3g.
    static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 10 { return String(format: "%dh %02dm", hours, minutes % 60) }
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)g"
    }

    static func elapsed(since date: Date?) -> String? {
        guard let date else { return nil }
        return duration(Date().timeIntervalSince(date))
    }

    static func ago(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 8 { return "ora" }
        return duration(interval) + " fa"
    }

    static func tokens(_ value: Int) -> String {
        if value < 1000 { return "\(value)" }
        if value < 100_000 {
            return String(format: "%.1fk", Double(value) / 1000).replacingOccurrences(of: ".", with: ",")
        }
        return "\(value / 1000)k"
    }

    static func model(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20", with: " ")
            .split(separator: " ").first.map(String.init) ?? raw
    }

    /// Accorcia il percorso home in `~`.
    static func path(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let home = AppPaths.home.path
        return raw.hasPrefix(home) ? "~" + raw.dropFirst(home.count) : raw
    }
}
