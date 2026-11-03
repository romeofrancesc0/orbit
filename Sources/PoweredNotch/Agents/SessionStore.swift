import Combine
import Foundation

enum SessionFilter: String, CaseIterable, Identifiable {
    case all, live, attention

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:       tr("Tutte")
        case .live:      tr("Attive")
        case .attention: tr("Attenzione")
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

/// Ciò che serve alla notch chiusa: chi lavora e chi aspetta, nient'altro. Mentre un
/// agent è al lavoro le sessioni cambiano di continuo (ora, attività, token), ma questo
/// riassunto cambia solo quando cambia uno stato. Così la notch chiusa non viene
/// ridisegnata a ogni riga scritta in un transcript.
@MainActor
final class SessionSummary: ObservableObject {
    struct Dot: Equatable, Identifiable {
        var id: String
        var status: SessionStatus
    }

    @Published private(set) var dots: [Dot] = []
    @Published private(set) var aggregate: SessionStatus?
    @Published private(set) var accentHex: String?

    func update(from sessions: [AgentSession]) {
        let active = sessions.filter { $0.status.isActive }
        let newDots = active.map { Dot(id: $0.id, status: $0.status) }
        if newDots != dots { dots = newDots }
        let newAggregate = active.min(by: { $0.status.rank < $1.status.rank })?.status
        if newAggregate != aggregate { aggregate = newAggregate }
        let newAccent = active.first?.accentHex
        if newAccent != accentHex { accentHex = newAccent }
    }
}

/// Aggrega i provider e pubblica lo stato per la UI. Gli aggiornamenti partono
/// dagli eventi su disco (FSEvents); il giro periodico resta solo come riserva,
/// per ciò che nessun file annuncia: un processo morto, una sessione che si addormenta.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var providerErrors: [String: String] = [:]
    @Published var filter: SessionFilter = .all
    /// Quante sessioni l'utente sta nascondendo in questo momento.
    @Published private(set) var hiddenCount = 0

    let summary = SessionSummary()
    private(set) var config: AgentsConfig
    private let dismissed: DismissedStore
    private var providers: [SessionProvider] = []
    private var providerSignature: [ProviderConfig] = []
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var pendingRefresh = false
    private var throttleWork: DispatchWorkItem?
    private var lastRefreshStarted: Date = .distantPast
    private var watcher: TreeWatcher?
    private var isActiveUI = false
    private let isPreview: Bool

    init(config: AgentsConfig) {
        self.config = config
        dismissed = DismissedStore()
        isPreview = false
        rebuildProviders()
    }

    /// Store statico con dati finti, usato per le anteprime e per gli screenshot.
    init(preview sessions: [AgentSession]) {
        config = AgentsConfig()
        dismissed = DismissedStore(file: FileManager.default.temporaryDirectory.appendingPathComponent("powerednotch-preview-dismissed.json"))
        isPreview = true
        self.sessions = AgentSession.ordered(sessions)
        summary.update(from: self.sessions)
    }

    // MARK: - Ciclo di vita

    func start() {
        guard !isPreview else { return }
        installWatcher()
        scheduleTimer()
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        watcher = nil
        refreshTask?.cancel()
    }

    /// Cadenza più fitta mentre la sessione è sotto gli occhi dell'utente.
    func setActiveUI(_ active: Bool) {
        guard isActiveUI != active else { return }
        isActiveUI = active
        scheduleTimer()
        if active { refresh() }
    }

    func apply(config newConfig: AgentsConfig) {
        guard newConfig != config else { return }
        config = newConfig
        guard !isPreview else { return }
        rebuildProviders()
        installWatcher()
        scheduleTimer()
        refresh()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        guard !isPreview else { return }
        let interval = max(1, isActiveUI ? config.activeRefreshSeconds : config.refreshSeconds)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = interval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Le cartelle che fanno scattare un aggiornamento appena cambiano.
    private func installWatcher() {
        let home = AppPaths.home.path
        var paths = [
            AppPaths.hintsDirectory.path,
            AppPaths.defaultInbox.path,
            "\(home)/Library/Application Support/Claude/claude-code-sessions"
        ]
        for provider in config.providers where provider.enabled {
            switch provider.type {
            case "claude-code":
                let root = provider.path.map { AppPaths.expand($0).path } ?? "\(home)/.claude"
                paths += ["\(root)/sessions", "\(root)/projects"]
            case "codex":
                let root = provider.path.map { AppPaths.expand($0).path } ?? "\(home)/.codex"
                paths += ["\(root)/sessions", "\(root)/session_index.jsonl"]
            case "inbox":
                if let path = provider.path { paths.append(AppPaths.expand(path).path) }
            default:
                break
            }
        }
        watcher = TreeWatcher(paths: Array(Set(paths))) { [weak self] in
            Task { @MainActor in self?.scheduleThrottledRefresh() }
        }
    }

    /// Mentre un agent scrive, gli eventi sono continui: se ne elabora uno ogni tanto.
    private func scheduleThrottledRefresh() {
        guard throttleWork == nil else { return }
        let minimumGap: TimeInterval = isActiveUI ? 0.4 : 1.2
        let wait = max(0, minimumGap - Date().timeIntervalSince(lastRefreshStarted))
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.throttleWork = nil
                self?.refresh()
            }
        }
        throttleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    // MARK: - Refresh

    func refresh() {
        guard !isPreview else { return }
        guard refreshTask == nil else {
            pendingRefresh = true
            return
        }
        lastRefreshStarted = Date()
        let providers = self.providers
        let config = self.config
        guard !providers.isEmpty else {
            apply(sessions: [], errors: [:])
            return
        }

        refreshTask = Task { [weak self] in
            var collected: [AgentSession] = []
            var errors: [String: String] = [:]

            await withTaskGroup(of: (String, ProviderResult).self) { group in
                for provider in providers {
                    group.addTask { (provider.id, await provider.fetch(config: config)) }
                }
                for await (id, result) in group {
                    collected.append(contentsOf: result.sessions)
                    if let error = result.error { errors[id] = error }
                }
            }

            guard let self, !Task.isCancelled else { return }
            self.apply(sessions: collected, errors: errors)
            self.refreshTask = nil
            if self.pendingRefresh {
                self.pendingRefresh = false
                self.scheduleThrottledRefresh()
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
        if ordered != sessions {
            sessions = ordered
            summary.update(from: ordered)
        }
        if errors != providerErrors { providerErrors = errors }
    }

    private func rebuildProviders() {
        guard config.providers != providerSignature else { return }
        providerSignature = config.providers
        providers = ProviderFactory.make(config.providers)
    }

    // MARK: - Derivati per la UI

    var filteredSessions: [AgentSession] {
        sessions.filter { filter.matches($0) }
    }

    var liveSessions: [AgentSession] { sessions.filter { $0.status.isLive } }
    /// Le sessioni che meritano un posto nella notch chiusa: una sessione che dorme non è una notizia.
    var activeSessions: [AgentSession] { sessions.filter { $0.status.isActive } }
    var workingCount: Int { sessions.filter { $0.status == .working }.count }
    var attentionCount: Int { sessions.filter { $0.status.needsYou }.count }
    var idleCount: Int { sessions.filter { $0.status == .idle }.count }

    /// Stato riassuntivo: vince ciò che richiede attenzione.
    var aggregateStatus: SessionStatus? {
        activeSessions.min(by: { $0.status.rank < $1.status.rank })?.status
    }

    /// La sessione più urgente: è quella che si racconta quando c'è spazio per una sola.
    var leadingSession: AgentSession? { activeSessions.first }

    /// Riepilogo testuale ("2 al lavoro · 1 attende").
    var summaryLine: String {
        var parts: [String] = []
        if workingCount > 0 { parts.append(tr("%lld al lavoro", workingCount)) }
        if attentionCount > 0 { parts.append(tr("%lld in attesa", attentionCount)) }
        if idleCount > 0 { parts.append(tr("%lld in pausa", idleCount)) }
        if parts.isEmpty {
            let ended = sessions.count
            return ended == 0 ? tr("nessuna sessione") : tr("%lld recenti", ended)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Azioni

    /// Toglie la sessione dall'elenco. Non tocca nulla dell'agent: se la chat
    /// riparte, il prossimo evento la fa ricomparire.
    func hide(_ session: AgentSession) {
        dismissed.dismiss(session)
        sessions.removeAll { $0.id == session.id }
        summary.update(from: sessions)
        hiddenCount += 1
    }

    func restoreHidden() {
        dismissed.restoreAll()
        hiddenCount = 0
        refresh()
    }
}

extension SessionStatus {
    /// Sta succedendo qualcosa di cui vale la pena accorgersi.
    var isActive: Bool { self == .working || needsYou }
}
