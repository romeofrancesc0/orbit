import SwiftUI

/// Azioni comuni sulle sessioni, condivise da riga e card.
@MainActor
private enum SessionMenu {
    static func canGo(_ session: AgentSession) -> Bool {
        session.openURL != nil || session.status.isLive
    }

    static func canResume(_ session: AgentSession) -> Bool {
        session.providerID.contains("claude") && session.nativeID != nil
    }

    /// Il gesto principale: portami lì. Una sessione chiusa si riprende, una viva si apre.
    static func primary(_ session: AgentSession, navigate: () -> Void) {
        if canGo(session) {
            SessionActions.focus(session)
        } else if canResume(session) {
            SessionActions.resumeClaudeCode(session: session)
        } else if let path = session.path {
            SessionActions.revealInFinder(path: path)
        }
        navigate()
    }
}

/// Menu contestuale di una sessione: le azioni meno frequenti non rubano spazio alla riga.
private struct SessionContextMenu: View {
    let session: AgentSession
    var navigate: () -> Void
    var hide: () -> Void

    var body: some View {
        if SessionMenu.canGo(session) {
            Button("Vai alla chat") {
                SessionActions.focus(session)
                navigate()
            }
        }
        if SessionMenu.canResume(session) {
            Button("Riprendi nel Terminale") {
                SessionActions.resumeClaudeCode(session: session)
                navigate()
            }
        }
        if let path = session.path {
            Divider()
            Button("Apri nel Terminale") {
                SessionActions.openInTerminal(path: path)
                navigate()
            }
            Button("Apri nell'editor") {
                SessionActions.openInEditor(path: path)
                navigate()
            }
            Button("Mostra nel Finder") {
                SessionActions.revealInFinder(path: path)
                navigate()
            }
            Button("Copia percorso") { SessionActions.copy(path) }
        }
        if !session.actions.isEmpty {
            Divider()
            ForEach(session.actions) { action in
                Button(action.label) { SessionActions.run(command: action.command, session: session) }
            }
        }
        Divider()
        Button("Togli dall'elenco", action: hide)
    }
}

/// Da quanto è ferma una sessione. Il dato non cambia, il tempo sì: senza questo
/// una sessione silenziosa continuerebbe a dire "4s" per ore.
private struct ElapsedLabel: View {
    let date: Date
    var size: CGFloat = 9.5

    @Environment(\.notchTheme) private var theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { _ in
            Text(Format.elapsed(since: date) ?? "")
                .font(theme.numberFont(size))
                .foregroundStyle(theme.tertiary)
        }
    }
}

/// Riga compatta di una sessione, per il widget quando divide la pagina con altri.
struct SessionRow: View {
    let session: AgentSession
    var onNavigate: () -> Void
    var onHide: () -> Void

    @Environment(\.notchTheme) private var theme
    @State private var hovering = false

    private var activityText: String {
        if let activity = session.activity, !activity.isEmpty,
           activity.caseInsensitiveCompare(session.status.label) != .orderedSame {
            return activity
        }
        return session.status.label
    }

    var body: some View {
        HStack(spacing: 7) {
            PulseDot(status: session.status, size: 7)
                .frame(width: 13, height: 13)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.project)
                    .font(theme.font(11.5, .semibold))
                    .foregroundStyle(theme.primary)
                    .lineLimit(1)
                Text(activityText)
                    .font(theme.font(10))
                    .foregroundStyle(session.status.needsYou ? session.status.tint : theme.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 2)

            if hovering {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(session.accentColor)
                    .transition(.opacity)
            } else {
                trailingInfo
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? theme.hoverFill : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { SessionMenu.primary(session, navigate: onNavigate) }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .contextMenu { SessionContextMenu(session: session, navigate: onNavigate, hide: onHide) }
        .help(session.title)
    }

    private var trailingInfo: some View {
        HStack(spacing: 5) {
            ElapsedLabel(date: session.updatedAt)
            if let fraction = session.contextFraction {
                ContextRing(fraction: fraction, tint: session.status.tint, size: 11, lineWidth: 1.6, warnsWhenFull: true)
            }
        }
    }
}

/// Card completa, per quando gli agenti hanno una pagina tutta per loro.
/// Lo stato è il protagonista: un badge colorato, un alone che sale dall'angolo e
/// una riga che dice cosa sta succedendo. Il resto resta sullo sfondo finché non serve.
struct SessionCard: View {
    let session: AgentSession
    var onNavigate: () -> Void
    var onHide: () -> Void

    @Environment(\.notchTheme) private var theme
    @State private var hovering = false

    private var tint: Color { session.status.tint }

    private var activityText: String? {
        guard let activity = session.activity, !activity.isEmpty,
              activity.caseInsensitiveCompare(session.status.label) != .orderedSame
        else { return nil }
        return activity
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: max(theme.cardRadius - 2, 10), style: .continuous)
    }

    /// Quanto deve farsi sentire l'alone: forte per ciò che richiede te, tenue per il resto.
    private var glow: Double {
        if session.status.needsYou { return 0.26 }
        return session.status == .working ? 0.16 : 0.06
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            statusLine
            footer
                .frame(height: 18)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(border)
        .shadow(color: .black.opacity(hovering ? 0.38 : 0.16), radius: hovering ? 12 : 4, y: hovering ? 6 : 2)
        .scaleEffect(hovering ? 1.014 : 1)
        .contentShape(shape)
        .onTapGesture { SessionMenu.primary(session, navigate: onNavigate) }
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: hovering)
        .contextMenu { SessionContextMenu(session: session, navigate: onNavigate, hide: onHide) }
    }

    // MARK: - Superficie

    private var background: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [.white.opacity(hovering ? 0.125 : 0.09), .white.opacity(hovering ? 0.065 : 0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RadialGradient(
                    colors: [tint.opacity(glow), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 170
                )
                .clipShape(shape)
            )
    }

    /// Un filo di luce sul bordo alto, come il vetro: più nitido sopra, sparisce sotto.
    private var border: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: session.status.needsYou
                    ? [tint.opacity(0.65), tint.opacity(0.14)]
                    : [.white.opacity(hovering ? 0.26 : 0.17), .white.opacity(0.03)],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 0.8
        )
    }

    // MARK: - Testata

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            statusBadge

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 6) {
                    Text(session.project)
                        .font(theme.font(13, .semibold))
                        .foregroundStyle(theme.primary)
                        .lineLimit(1)
                    if let branch = session.branch, branch != "HEAD", !branch.isEmpty {
                        MetaChip(text: branch, symbol: "arrow.triangle.branch")
                            .layoutPriority(-1)
                    }
                }
                Text(session.title)
                    .font(theme.font(10.5))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            ElapsedLabel(date: session.updatedAt, size: 10)
        }
    }

    /// L'icona dello stato in un quadrato dai bordi morbidi; chi è vivo ha un pallino che respira.
    private var statusBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.34), tint.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 0.7)
            Image(systemName: session.status.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 30, height: 30)
        .overlay(alignment: .topTrailing) {
            if session.status.animates {
                PulseDot(status: session.status, size: 5.5)
                    .frame(width: 13, height: 13)
                    .offset(x: 4, y: -4)
            }
        }
    }

    // MARK: - Stato e attività

    /// Cosa sta succedendo, in una riga sola. Per ciò che richiede te la riga si tinge.
    private var statusLine: some View {
        HStack(spacing: 7) {
            Text(session.status.label)
                .font(theme.font(10.5, .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize()
            if let activityText {
                Capsule()
                    .fill(.white.opacity(0.16))
                    .frame(width: 1, height: 10)
                Text(activityText)
                    .font(theme.font(10.5))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(session.status.needsYou ? tint.opacity(0.13) : Color.black.opacity(0.22))
        )
    }

    // MARK: - Piede

    /// A riposo mostra provider e contesto consumato; al passaggio del mouse lascia il posto alle azioni.
    @ViewBuilder
    private var footer: some View {
        if hovering {
            HStack(spacing: 4) {
                if SessionMenu.canGo(session) {
                    NotchPillButton(symbol: "arrow.up.forward.app", label: "Vai", tint: session.accentColor) {
                        SessionMenu.primary(session, navigate: onNavigate)
                    }
                } else if SessionMenu.canResume(session) {
                    NotchPillButton(symbol: "play.fill", label: "Riprendi", tint: session.accentColor) {
                        SessionMenu.primary(session, navigate: onNavigate)
                    }
                }
                if let path = session.path {
                    NotchPillButton(symbol: "terminal", label: "", tint: nil) {
                        SessionActions.openInTerminal(path: path)
                        onNavigate()
                    }
                    .help("Apri nel Terminale")
                    NotchPillButton(symbol: "chevron.left.forwardslash.chevron.right", label: "", tint: nil) {
                        SessionActions.openInEditor(path: path)
                        onNavigate()
                    }
                    .help("Apri nell'editor")
                    NotchPillButton(symbol: "folder", label: "", tint: nil) {
                        SessionActions.revealInFinder(path: path)
                        onNavigate()
                    }
                    .help("Mostra nel Finder")
                }
                Spacer(minLength: 0)
                NotchPillButton(symbol: "eye.slash", label: "", tint: nil, action: onHide)
                    .help("Togli dall'elenco · ricompare se riprendi questa chat")
            }
            .transition(.opacity)
        } else {
            HStack(spacing: 7) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(session.accentColor)
                        .frame(width: 5, height: 5)
                    Text(session.providerName)
                        .font(theme.font(9.5, .medium))
                        .foregroundStyle(theme.tertiary)
                        .lineLimit(1)
                }
                .fixedSize()
                if let fraction = session.contextFraction {
                    LevelBar(fraction: fraction, tint: fraction > 0.85 ? Color(hex: 0xFF5A63) : tint.opacity(0.9), height: 3)
                    if let used = session.tokensUsed {
                        Text(Format.tokens(used))
                            .font(theme.numberFont(9))
                            .foregroundStyle(theme.tertiary)
                            .fixedSize()
                    }
                } else {
                    Spacer(minLength: 0)
                }
                if let host = session.host {
                    MetaChip(text: host)
                }
            }
            .transition(.opacity)
        }
    }
}

/// Il widget degli agenti. Si adatta allo spazio che riceve: elenco compatto quando
/// divide la pagina con altri, griglia di card quando ha la pagina tutta per sé.
struct AgentsWidget: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var actions: NotchActions
    @Environment(\.notchTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > 520
            VStack(alignment: .leading, spacing: wide ? 8 : 4) {
                header(wide: wide)
                if store.sessions.isEmpty {
                    emptyState
                } else if wide {
                    board(width: geometry.size.width)
                } else {
                    list
                }
            }
        }
    }

    private func header(wide: Bool) -> some View {
        HStack(spacing: 6) {
            Text("Agenti")
                .font(theme.font(12, .semibold))
                .foregroundStyle(theme.primary)
            Text(store.summaryLine)
                .font(theme.font(10))
                .foregroundStyle(theme.secondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            if wide {
                filterPicker
                if store.hiddenCount > 0 {
                    NotchPillButton(symbol: "eye", label: "\(store.hiddenCount)", tint: nil) {
                        store.restoreHidden()
                    }
                    .help("Rimetti in elenco le sessioni nascoste")
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var filterPicker: some View {
        HStack(spacing: 2) {
            ForEach(SessionFilter.allCases) { filter in
                let selected = store.filter == filter
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { store.filter = filter }
                } label: {
                    Text(filter.label)
                        .font(theme.font(10, selected ? .semibold : .medium))
                        .foregroundStyle(selected ? theme.primary : theme.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(selected ? theme.chipFill : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 1) {
                ForEach(store.sessions) { session in
                    SessionRow(session: session, onNavigate: actions.close) {
                        withAnimation(.spring(response: 0.3)) { store.hide(session) }
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .fadingBottom()
    }

    private func board(width: CGFloat) -> some View {
        let columns = width > 880 ? 3 : 2
        let grid = Array(repeating: GridItem(.flexible(), spacing: 7), count: columns)
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: grid, spacing: 7) {
                ForEach(store.filteredSessions) { session in
                    SessionCard(session: session, onNavigate: actions.close) {
                        withAnimation(.spring(response: 0.3)) { store.hide(session) }
                    }
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.85), value: store.filteredSessions.map(\.id))
            .padding(.bottom, 10)
        }
        .fadingBottom(18)
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme.tertiary)
            Text("Nessuna sessione")
                .font(theme.font(11, .medium))
                .foregroundStyle(theme.secondary)
            Text("Avvia il tuo coding agent e comparirà qui")
                .font(theme.font(9.5))
                .foregroundStyle(theme.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
