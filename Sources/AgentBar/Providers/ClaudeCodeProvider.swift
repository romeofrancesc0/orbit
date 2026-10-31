import Foundation

/// Provider nativo per Claude Code.
///
/// Non richiede hook né configurazione: incrocia il registro dei processi vivi
/// (`~/.claude/sessions/<pid>.json`) con la coda dei transcript
/// (`~/.claude/projects/<slug>/<sessionId>.jsonl`).
actor ClaudeCodeProvider: SessionProvider {
    nonisolated let id: String
    nonisolated let displayName: String
    nonisolated let accentHex: String?

    private let root: URL
    private let hintsDirectory: URL
    private let desktopIndex = ClaudeDesktopIndex()
    private var scanCache: [String: CachedScan] = [:]

    /// Suggerimento scritto da un hook: cattura ciò che il transcript non dice,
    /// per esempio una richiesta di permesso ancora pendente.
    private struct Hint {
        var status: SessionStatus?
        var activity: String?
        var at: Date
    }

    private struct HintFile: Decodable {
        var status: String?
        var activity: String?
        var at: Double?
    }

    private struct CachedScan {
        var size: Int
        var modified: Date
        var scan: TranscriptScan
    }

    private struct LiveEntry: Decodable {
        var pid: Int32
        var sessionId: String
        var cwd: String
        var startedAt: Double?
        var version: String?
        var kind: String?
        var entrypoint: String?
        var name: String?
        var nameSource: String?

        var startedDate: Date? {
            guard let startedAt else { return nil }
            return Date(timeIntervalSince1970: startedAt / 1000)
        }
    }

    private struct TranscriptRef {
        var url: URL
        var modified: Date
        var created: Date?
        var size: Int
    }

    init(config: ProviderConfig) {
        id = config.id
        displayName = config.name ?? "Claude Code"
        accentHex = config.accent ?? "#D97757"
        root = config.path.map(AppPaths.expand) ?? AppPaths.home.appendingPathComponent(".claude", isDirectory: true)
        hintsDirectory = AppPaths.home.appendingPathComponent(".agentbar/hints", isDirectory: true)
    }

    func fetch(config: AppConfig) async -> ProviderResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else {
            return ProviderResult(error: "cartella \(root.lastPathComponent) non trovata")
        }

        let index = transcriptIndex()
        let hints = readHints()
        // Claude Desktop tiene una propria anagrafica delle chat: da lì arrivano
        // il titolo che l'utente vede e l'id con cui si apre la chat giusta.
        let desktop = desktopIndex.load()
        var sessions: [AgentSession] = []
        var liveIDs: Set<String> = []

        // 1. Sessioni con un processo ancora vivo.
        for entry in liveEntries() {
            liveIDs.insert(entry.sessionId)
            let ref = index[entry.sessionId]
            var scan: TranscriptScan?
            if let ref { scan = scanTranscript(ref: ref) }
            sessions.append(
                makeSession(
                    entry: entry,
                    ref: ref,
                    scan: scan,
                    hint: hints[entry.sessionId],
                    desktop: desktop[entry.sessionId],
                    config: config
                )
            )
        }

        // 2. Sessioni recenti già chiuse, per avere continuità con ciò che si stava facendo.
        if config.showRecent {
            let cutoff = Date().addingTimeInterval(-config.recentWindowHours * 3600)
            let recent = index
                .filter { !liveIDs.contains($0.key) && $0.value.modified > cutoff && $0.value.size > 400 }
                .sorted { $0.value.modified > $1.value.modified }
                .prefix(6)
            for (sessionID, ref) in recent {
                let scan = scanTranscript(ref: ref)
                sessions.append(
                    makeEndedSession(
                        sessionID: sessionID,
                        ref: ref,
                        scan: scan,
                        desktop: desktop[sessionID],
                        config: config
                    )
                )
            }
        }

        pruneCache(keeping: Set(index.values.map(\.url.path)))
        return ProviderResult(sessions: sessions)
    }

    // MARK: - Sorgenti

    private func liveEntries() -> [LiveEntry] {
        let fm = FileManager.default
        let directory = root.appendingPathComponent("sessions", isDirectory: true)
        let urls = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var entries: [LiveEntry] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let entry = try? JSONDecoder().decode(LiveEntry.self, from: data)
            else { continue }
            guard ProcessProbe.isAlive(pid: entry.pid, startedAt: entry.startedDate) else { continue }
            entries.append(entry)
        }
        return entries
    }

    private func transcriptIndex() -> [String: TranscriptRef] {
        let fm = FileManager.default
        let projects = root.appendingPathComponent("projects", isDirectory: true)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey, .fileSizeKey, .isDirectoryKey]
        guard let projectDirs = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: keys) else { return [:] }

        var index: [String: TranscriptRef] = [:]
        for directory in projectDirs {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let values = try? file.resourceValues(forKeys: Set(keys))
                let ref = TranscriptRef(
                    url: file,
                    modified: values?.contentModificationDate ?? .distantPast,
                    created: values?.creationDate,
                    size: values?.fileSize ?? 0
                )
                let sessionID = file.deletingPathExtension().lastPathComponent
                // Con più file per la stessa sessione vince il più recente.
                if let existing = index[sessionID], existing.modified > ref.modified { continue }
                index[sessionID] = ref
            }
        }
        return index
    }

    private func scanTranscript(ref: TranscriptRef) -> TranscriptScan {
        let key = ref.url.path
        if let cached = scanCache[key], cached.size == ref.size, cached.modified == ref.modified {
            return cached.scan
        }
        let scan = TranscriptScanner.scan(url: ref.url)
        scanCache[key] = CachedScan(size: ref.size, modified: ref.modified, scan: scan)
        return scan
    }

    /// Legge i suggerimenti lasciati dagli hook in `~/.agentbar/hints/<sessionId>.json`.
    /// Quelli vecchi vengono ignorati: un hook può sempre morire senza ripulire.
    private func readHints() -> [String: Hint] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: hintsDirectory, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var hints: [String: Hint] = [:]
        let cutoff = Date().addingTimeInterval(-30 * 60)
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let payload = try? JSONDecoder().decode(HintFile.self, from: data)
            else { continue }
            let at = payload.at.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast
            guard at > cutoff else { continue }
            hints[file.deletingPathExtension().lastPathComponent] = Hint(
                status: SessionStatus.parse(payload.status),
                activity: payload.activity,
                at: at
            )
        }
        return hints
    }

    private func pruneCache(keeping paths: Set<String>) {
        guard scanCache.count > paths.count else { return }
        scanCache = scanCache.filter { paths.contains($0.key) }
    }

    // MARK: - Costruzione delle sessioni

    private func makeSession(
        entry: LiveEntry,
        ref: TranscriptRef?,
        scan: TranscriptScan?,
        hint: Hint?,
        desktop: DesktopSession?,
        config: AppConfig
    ) -> AgentSession {
        var updated = scan?.lastEventAt ?? ref?.modified ?? entry.startedDate ?? Date()
        var activity = scan?.activity

        var status = scan?.status ?? .idle

        // Un hook che ha parlato dopo l'ultimo evento del transcript sa qualcosa
        // che il transcript non ha ancora scritto (tipico: permesso in attesa).
        if let hint, hint.at >= updated.addingTimeInterval(-2) {
            if let hinted = hint.status { status = hinted }
            if let hintedActivity = hint.activity { activity = hintedActivity }
            updated = max(updated, hint.at)
        }

        let stale = Date().timeIntervalSince(updated) > config.idleAfterMinutes * 60
        if stale && status != .error { status = .idle }

        let project = URL(fileURLWithPath: entry.cwd).lastPathComponent
        let title = preferredTitle(scan: scan, entry: entry, desktop: desktop, project: project)

        return AgentSession(
            id: "\(id):\(entry.sessionId)",
            providerID: id,
            providerName: displayName,
            accentHex: accentHex,
            title: title,
            project: project,
            path: entry.cwd,
            branch: scan?.branch,
            model: scan?.model,
            status: status,
            activity: stale ? nil : activity,
            detail: scan?.lastPrompt,
            host: hostLabel(entry.entrypoint),
            startedAt: entry.startedDate ?? ref?.created,
            updatedAt: updated,
            tokensUsed: scan?.tokensUsed,
            tokenLimit: scan?.tokensUsed.map { config.contextLimit(for: $0) },
            pid: entry.pid,
            nativeID: entry.sessionId,
            openURL: desktop?.deepLink,
            actions: []
        )
    }

    private func makeEndedSession(
        sessionID: String,
        ref: TranscriptRef,
        scan: TranscriptScan,
        desktop: DesktopSession?,
        config: AppConfig
    ) -> AgentSession {
        let path = scan.cwd
        let project = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "sessione"
        let title = desktop?.title
            ?? scan.title
            ?? scan.lastPrompt.map { shorten($0) }
            ?? project

        return AgentSession(
            id: "\(id):\(sessionID)",
            providerID: id,
            providerName: displayName,
            accentHex: accentHex,
            title: title,
            project: project,
            path: path,
            branch: scan.branch,
            model: scan.model,
            status: .ended,
            activity: nil,
            detail: scan.lastPrompt,
            host: nil,
            startedAt: ref.created,
            updatedAt: scan.lastEventAt ?? ref.modified,
            tokensUsed: scan.tokensUsed,
            tokenLimit: scan.tokensUsed.map { config.contextLimit(for: $0) },
            pid: nil,
            nativeID: sessionID,
            openURL: desktop?.deepLink,
            actions: []
        )
    }

    private func preferredTitle(scan: TranscriptScan?, entry: LiveEntry, desktop: DesktopSession?, project: String) -> String {
        // Il titolo dell'app desktop è quello che l'utente riconosce.
        if let title = desktop?.title, !title.isEmpty { return title }
        if let title = scan?.title, !title.isEmpty { return title }
        if let name = entry.name, !name.isEmpty, entry.nameSource != "derived" { return name }
        if let prompt = scan?.lastPrompt, !prompt.isEmpty { return shorten(prompt) }
        return project
    }

    private func shorten(_ text: String, limit: Int = 64) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func hostLabel(_ entrypoint: String?) -> String? {
        switch entrypoint {
        case "claude-desktop", "desktop": "Desktop"
        case "cli", "terminal": "Terminale"
        case "vscode", "ide", "vscode-extension": "VS Code"
        case "jetbrains": "JetBrains"
        case .some(let other) where !other.isEmpty: other
        default: nil
        }
    }
}
