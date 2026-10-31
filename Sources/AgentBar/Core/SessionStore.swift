import Combine
import Foundation

enum DeckFilter: String, CaseIterable, Identifiable {
    case all, live, attention

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:       "Tutte"
        case .live:      "Attive"
        case .attention: "Attenzione"
        }
    }

    func matches(_ session: AgentSession) -> Bool {
        switch self {
        case .all:       true
        case .live:      session.status.isLive
        case .attention: session.status.needsYou
        }
    }
}

/// Aggrega i provider, fa polling adattivo e pubblica lo stato per la UI.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var providerErrors: [String: String] = [:]
    @Published private(set) var lastRefresh: Date = .distantPast
    @Published private(set) var isRefreshing = false
    @Published private(set) var config: AppConfig
    @Published var filter: DeckFilter = .all

    /// Quante sessioni l'utente sta nascondendo in questo momento.
    @Published private(set) var hiddenCount = 0

    private let configStore = ConfigStore()
    private let dismissed = DismissedStore()
    private var providers: [SessionProvider] = []
    private var providerSignature: [ProviderConfig] = []
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var panelIsOpen = false

    init() {
        config = configStore.current
        rebuildProviders(config)
    }

    /// Store statico con dati finti, usato dal renderer di anteprima.
    init(preview sessions: [AgentSession]) {
        var previewConfig = AppConfig.default
        // ImageRenderer non sa disegnare il vetro: in anteprima si usa il fallback.
        previewConfig.useLiquidGlass = false
        config = previewConfig
        self.sessions = AgentSession.ordered(sessions)
        lastRefresh = Date()
    }

    // MARK: - Ciclo di vita

    func start() {
        scheduleTimer()
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
    }

    /// Cadenza più fitta mentre un pannello è visibile.
    func setPanelOpen(_ open: Bool) {
        guard panelIsOpen != open else { return }
        panelIsOpen = open
        scheduleTimer()
        if open { refresh() }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = max(0.5, panelIsOpen ? config.activeRefreshSeconds : config.refreshSeconds)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // .common: continua a scattare anche durante il tracking del mouse nella barra.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Refresh

    func refresh() {
        guard refreshTask == nil else { return }
        let freshConfig = configStore.reloadIfChanged()
        if freshConfig != config {
            config = freshConfig
            rebuildProviders(freshConfig)
            scheduleTimer()
        }
        let providers = self.providers
        guard !providers.isEmpty else {
            sessions = []
            lastRefresh = Date()
            return
        }

        isRefreshing = true
        refreshTask = Task { [weak self] in
            var collected: [AgentSession] = []
            var errors: [String: String] = [:]

            await withTaskGroup(of: (String, ProviderResult).self) { group in
                for provider in providers {
                    group.addTask { (provider.id, await provider.fetch(config: freshConfig)) }
                }
                for await (id, result) in group {
                    collected.append(contentsOf: result.sessions)
                    if let error = result.error { errors[id] = error }
                }
            }

            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.apply(sessions: collected, errors: errors)
                self.refreshTask = nil
            }
        }
    }

    private func apply(sessions incoming: [AgentSession], errors: [String: String]) {
        var deduped: [String: AgentSession] = [:]
        for session in incoming { deduped[session.id] = session }

        dismissed.prune(knownIDs: Set(deduped.keys))
        let all = Array(deduped.values)
        let visible = all.filter { !dismissed.isHidden($0) }
        let hidden = all.count - visible.count
        if hidden != hiddenCount { hiddenCount = hidden }

        let ordered = AgentSession.ordered(visible)
        if ordered != sessions { sessions = ordered }
        if errors != providerErrors { providerErrors = errors }
        isRefreshing = false
        lastRefresh = Date()
    }

    private func rebuildProviders(_ config: AppConfig) {
        guard config.providers != providerSignature else { return }
        providerSignature = config.providers
        providers = ProviderFactory.make(config.providers)
    }

    // MARK: - Derivati per la UI

    var visibleSessions: [AgentSession] {
        sessions.filter { filter.matches($0) }
    }

    var liveSessions: [AgentSession] { sessions.filter { $0.status.isLive } }
    var workingCount: Int { sessions.filter { $0.status == .working }.count }
    var attentionCount: Int { sessions.filter { $0.status.needsYou }.count }
    var idleCount: Int { sessions.filter { $0.status == .idle }.count }

    /// Stato riassuntivo mostrato nella barra: vince ciò che richiede attenzione.
    var aggregateStatus: SessionStatus? {
        liveSessions.min(by: { $0.status.rank < $1.status.rank })?.status
    }

    var badgeCount: Int { liveSessions.count }

    /// Riepilogo testuale ("2 al lavoro · 1 attende").
    var summaryLine: String {
        var parts: [String] = []
        if workingCount > 0 { parts.append("\(workingCount) al lavoro") }
        if attentionCount > 0 { parts.append("\(attentionCount) in attesa") }
        if idleCount > 0 { parts.append("\(idleCount) in pausa") }
        if parts.isEmpty {
            let ended = sessions.count
            return ended == 0 ? "nessuna sessione" : "\(ended) recenti"
        }
        return parts.joined(separator: " · ")
    }

    /// Sottotitolo della testata. Quando non c'è nessuna sessione resta vuoto:
    /// lo stato vuoto poco più sotto dice già "Nessuna sessione", e sentirselo
    /// dire due volte a due righe di distanza è solo rumore.
    var headerSubtitle: String? {
        sessions.isEmpty ? nil : summaryLine
    }

    // MARK: - Impostazioni scrivibili dal pannello

    /// Unico punto di scrittura della configurazione: salva su disco e riapplica
    /// subito ciò che dipende da essa (cadenza del polling, elenco dei provider).
    func updateConfig(_ mutate: (inout AppConfig) -> Void) {
        var updated = config
        mutate(&updated)
        guard updated != config else { return }
        configStore.write(updated)
        config = updated
        rebuildProviders(updated)
        scheduleTimer()
        refresh()
    }

    /// Toglie la sessione dall'elenco. Non tocca nulla dell'agent: se la chat
    /// riparte, il prossimo evento la fa ricomparire.
    func hide(_ session: AgentSession) {
        dismissed.dismiss(session)
        sessions.removeAll { $0.id == session.id }
        hiddenCount += 1
    }

    func restoreHidden() {
        dismissed.restoreAll()
        hiddenCount = 0
        refresh()
    }

    func setProviderEnabled(_ providerID: String, _ enabled: Bool) {
        updateConfig { config in
            guard let index = config.providers.firstIndex(where: { $0.id == providerID }) else { return }
            config.providers[index].enabled = enabled
        }
    }

    func openConfigFile() {
        _ = configStore.reloadIfChanged()
        SessionActions.openInDefaultApp(AppPaths.configFile)
    }
}
