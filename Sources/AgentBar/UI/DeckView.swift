import AppKit
import SwiftUI

/// Pannello interattivo che si apre al click: elenco completo, filtri e azioni.
struct DeckView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var presentation: PanelPresentation
    var onClose: () -> Void
    /// Il renderer di anteprima disegna l'elenco disteso: ImageRenderer non
    /// sa rendere il contenuto di uno ScrollView.
    var scrollable: Bool = true

    @State private var listHeight: CGFloat = 0
    @State private var expandedID: String?
    @State private var showingSettings = false
    @Namespace private var filterNamespace

    private var sessions: [AgentSession] { store.visibleSessions }

    var body: some View {
        PanelSurface(useGlass: store.config.useLiquidGlass) {
            Group {
                if showingSettings {
                    SettingsView(
                        store: store,
                        onBack: { withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { showingSettings = false } },
                        scrollable: scrollable
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                } else {
                    sessionsPage
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .frame(width: Theme.deckWidth)
        }
        .padding(Theme.shadowPad)
        .panelTransition(presentation)
        // Tornando al pannello si riparte sempre dall'elenco.
        .onChange(of: presentation.visible) { _, visible in
            if !visible { showingSettings = false }
        }
    }

    private var sessionsPage: some View {
        VStack(spacing: 0) {
            header
            filterBar
            Divider().overlay(Color.hairlineSoft)
            content
            Divider().overlay(Color.hairlineSoft)
            footer
        }
    }

    // MARK: - Testata

    private var header: some View {
        HStack(spacing: 10) {
            AppMark(height: 25)
            VStack(alignment: .leading, spacing: 1) {
                Text("Agenti")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                if let subtitle = store.headerSubtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(store.isRefreshing ? Color(hex: 0x3BB9F5) : Color.secondary.opacity(0.45))
                    .frame(width: 5, height: 5)
                    .animation(.easeInOut(duration: 0.25), value: store.isRefreshing)
                Text(Format.ago(store.lastRefresh))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 11)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(DeckFilter.allCases) { filter in
                filterPill(filter)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 11)
    }

    private func filterPill(_ filter: DeckFilter) -> some View {
        let selected = store.filter == filter
        let count = countFor(filter)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                store.filter = filter
            }
        } label: {
            HStack(spacing: 4) {
                Text(filter.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(selected ? Color.primary.opacity(0.14) : Color.chipFill))
                }
            }
            .foregroundStyle(selected ? .primary : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(Color.rowFillHover)
                        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 0.7))
                        .matchedGeometryEffect(id: "filter", in: filterNamespace)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func countFor(_ filter: DeckFilter) -> Int {
        switch filter {
        case .all:       store.sessions.count
        case .live:      store.liveSessions.count
        case .attention: store.attentionCount
        }
    }

    // MARK: - Elenco

    @ViewBuilder
    private var content: some View {
        if sessions.isEmpty {
            emptyState
        } else if scrollable {
            ScrollView(.vertical, showsIndicators: false) {
                cardStack
            }
            .frame(height: min(max(listHeight, 80), Theme.deckMaxHeight))
        } else {
            cardStack
        }
    }

    /// L'elenco delle card, con la misura che dimensiona il pannello.
    private var cardStack: some View {
        // VStack e non LazyVStack: le sessioni sono poche e l'altezza misurata
        // dev'essere quella reale.
        VStack(spacing: 8) {
            ForEach(sessions) { session in
                SessionCardView(
                    session: session,
                    expanded: expandedID == session.id,
                    onToggleExpand: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            expandedID = expandedID == session.id ? nil : session.id
                        }
                    },
                    onNavigate: onClose,
                    onHide: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            store.hide(session)
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { listHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, value in listHeight = value }
            }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    .foregroundStyle(Color.hairline)
                    .frame(width: 52, height: 52)
                Image(systemName: store.filter == .attention ? "checkmark.circle" : "terminal")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.tertiary)
            }
            Text(store.filter == .attention ? "Niente da fare" : "Nessuna sessione")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(store.filter == .attention
                 ? "Nessun agent sta aspettando una tua risposta."
                 : "Avvia un agent in un progetto: comparirà qui.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Piede

    private var footer: some View {
        HStack(spacing: 8) {
            providerChips
            Spacer(minLength: 6)
            IconButton(symbol: "arrow.clockwise", help: "Aggiorna") { store.refresh() }
            IconButton(symbol: "gearshape", help: "Impostazioni") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { showingSettings = true }
            }
            IconButton(symbol: "power", help: "Esci da AgentBar") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var providerChips: some View {
        HStack(spacing: 6) {
            ForEach(providerSummaries, id: \.id) { summary in
                HStack(spacing: 4) {
                    Circle()
                        .fill(summary.color)
                        .frame(width: 5, height: 5)
                    Text(summary.name)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let error = summary.error {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color(hex: 0xF5B942))
                            .help(error)
                    } else {
                        Text("\(summary.count)")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Capsule().fill(Color.chipFill))
            }
        }
    }

    private struct ProviderSummary {
        var id: String
        var name: String
        var color: Color
        var count: Int
        var error: String?
    }

    private var providerSummaries: [ProviderSummary] {
        var summaries: [String: ProviderSummary] = [:]
        for provider in store.config.providers where provider.enabled {
            summaries[provider.id] = ProviderSummary(
                id: provider.id,
                name: provider.name ?? provider.id,
                color: Color(hexString: provider.accent) ?? .secondary,
                count: 0,
                error: store.providerErrors[provider.id]
            )
        }
        for session in store.sessions {
            summaries[session.providerID]?.count += 1
        }
        return summaries.values.sorted { $0.name < $1.name }
    }
}
