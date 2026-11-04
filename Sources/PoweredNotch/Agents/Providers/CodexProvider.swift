import Foundation

/// Provider nativo per Codex: legge i rollout in `~/.codex/sessions/AAAA/MM/GG/`.
///
/// Codex non tiene un registro dei processi vivi come Claude Code: se una sessione
/// sia ancora in corso si deduce dall'ultimo evento e da quanto tempo è passato.
actor CodexProvider: SessionProvider {
    nonisolated let id: String
    nonisolated let displayName: String
    nonisolated let accentHex: String?

    private let root: URL
    private var cursors: [String: CodexCursor] = [:]
    private var titles: [String: String] = [:]
    private var titlesStamp: Date?

    /// Oltre questo silenzio un turno "in corso" non è più credibile.
    private let workingStaleAfter: TimeInterval = 180
    /// Quanti giorni indietro cercare: un thread lungo continua a scrivere nel file di quando è nato.
    private let daysToScan = 7

    init(config: ProviderConfig) {
        id = config.id
        displayName = config.name ?? "Codex"
        accentHex = config.accent ?? "#10A37F"
        root = config.path.map(AppPaths.expand) ?? AppPaths.home.appendingPathComponent(".codex", isDirectory: true)
    }

    func fetch(config: AgentsConfig) async -> ProviderResult {
        guard FileManager.default.fileExists(atPath: root.path) else { return ProviderResult() }
        reloadTitlesIfNeeded()

        let recentCutoff = Date().addingTimeInterval(-config.recentWindowHours * 3600)
        var sessions: [AgentSession] = []
        var seen: Set<String> = []

        for file in rolloutFiles(modifiedAfter: recentCutoff) {
            seen.insert(file.url.path)
            let cursor = updatedCursor(for: file)
            guard let session = makeSession(from: cursor.scan, file: file, config: config) else { continue }
            if session.status == .ended && !config.showRecent { continue }
            sessions.append(session)
        }

        cursors = cursors.filter { seen.contains($0.key) }
        return ProviderResult(sessions: sessions)
    }

    // MARK: - File

    private struct RolloutFile {
        var url: URL
        var modified: Date
        var size: UInt64
        var threadID: String
    }

    private func rolloutFiles(modifiedAfter cutoff: Date) -> [RolloutFile] {
        let fm = FileManager.default
        let calendar = Calendar(identifier: .gregorian)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let sessionsRoot = root.appendingPathComponent("sessions", isDirectory: true)
        var result: [RolloutFile] = []

        for offset in 0..<daysToScan {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let folder = sessionsRoot.appendingPathComponent(
                String(format: "%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
                isDirectory: true
            )
            guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { continue }
            for url in files where url.pathExtension == "jsonl" {
                let values = try? url.resourceValues(forKeys: Set(keys))
                let modified = values?.contentModificationDate ?? .distantPast
                guard modified > cutoff else { continue }
                result.append(RolloutFile(
                    url: url,
                    modified: modified,
                    size: UInt64(values?.fileSize ?? 0),
                    threadID: Self.threadID(fromFileName: url.deletingPathExtension().lastPathComponent)
                ))
            }
        }
        return result.sorted { $0.modified > $1.modified }.prefix(8).map { $0 }
    }

    /// `rollout-2026-10-22T21-09-54-<uuid>`: l'id del thread sono gli ultimi 36 caratteri.
    static func threadID(fromFileName name: String) -> String {
        guard name.count >= 36 else { return name }
        return String(name.suffix(36))
    }

    private func updatedCursor(for file: RolloutFile) -> CodexCursor {
        let key = file.url.path
        if var cursor = cursors[key] {
            if file.size == cursor.offset { return cursor }
            if file.size > cursor.offset {
                CodexScanner.advance(&cursor, url: file.url)
                cursors[key] = cursor
                return cursor
            }
        }
        let cursor = CodexScanner.start(url: file.url)
        cursors[key] = cursor
        return cursor
    }

    /// I titoli dei thread stanno in `session_index.jsonl`, una riga per ogni rinomina.
    private func reloadTitlesIfNeeded() {
        let url = root.appendingPathComponent("session_index.jsonl")
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard modified != titlesStamp, let data = try? Data(contentsOf: url) else { return }
        titlesStamp = modified

        var updated: [String: String] = [:]
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = object["id"] as? String,
                  let name = object["thread_name"] as? String, !name.isEmpty
            else { continue }
            updated[id] = name
        }
        titles = updated
    }

    // MARK: - Sessione

    private func makeSession(from scan: CodexScan, file: RolloutFile, config: AgentsConfig) -> AgentSession? {
        let updated = scan.lastEventAt ?? file.modified
        let age = Date().timeIntervalSince(updated)
        var status = scan.status ?? .ended

        // Senza un registro dei processi, il silenzio è l'unico segnale di chiusura.
        switch status {
        case .working where age > workingStaleAfter:
            status = .idle
        case .blocked where age > config.idleAfterMinutes * 60,
             .attention where age > config.idleAfterMinutes * 60,
             .done where age > config.idleAfterMinutes * 60,
             .error where age > config.idleAfterMinutes * 60,
             .idle where age > config.idleAfterMinutes * 60:
            status = .ended
        default:
            break
        }

        let project = scan.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Codex"
        let title = titles[file.threadID]
            ?? scan.lastPrompt.map { TranscriptScanner.snippet($0, limit: 64) }
            ?? project
        let isDesktop = scan.originator?.localizedCaseInsensitiveContains("desktop") == true

        return AgentSession(
            id: "\(id):\(file.threadID)",
            providerID: id,
            providerName: displayName,
            accentHex: accentHex,
            title: title,
            project: project,
            path: scan.cwd,
            branch: scan.branch,
            model: scan.model,
            status: status,
            activity: status.isLive ? scan.activity : nil,
            detail: scan.lastPrompt,
            host: isDesktop ? "Codex" : "Terminale",
            startedAt: scan.startedAt,
            updatedAt: updated,
            tokensUsed: scan.tokensUsed,
            tokenLimit: scan.tokenLimit ?? scan.tokensUsed.map { config.contextLimit(for: $0) },
            pid: nil,
            nativeID: file.threadID,
            openURL: isDesktop ? "codex://threads/\(file.threadID)" : nil,
            actions: []
        )
    }
}

// MARK: - Lettura dei rollout

struct CodexScan: Sendable {
    var lastEventAt: Date?
    var startedAt: Date?
    var status: SessionStatus?
    var activity: String?
    var lastPrompt: String?
    var cwd: String?
    var model: String?
    var branch: String?
    var originator: String?
    var tokensUsed: Int?
    var tokenLimit: Int?
}

struct CodexCursor: Sendable {
    var offset: UInt64 = 0
    var scan = CodexScan()
    var remainder = Data()
}

enum CodexScanner {
    static func start(url: URL, tailBytes: Int = 256 * 1024) -> CodexCursor {
        var cursor = CodexCursor()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return cursor }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return cursor }

        // L'intestazione sta nella prima riga: fuori dalla coda sui file lunghi.
        try? handle.seek(toOffset: 0)
        if let head = try? handle.read(upToCount: 256 * 1024),
           let line = head.split(separator: UInt8(ascii: "\n"), maxSplits: 1).first,
           let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
            absorb(object, into: &cursor.scan)
        }

        let truncated = size > UInt64(tailBytes)
        try? handle.seek(toOffset: truncated ? size - UInt64(tailBytes) : 0)
        guard let data = try? handle.readToEnd() else { return cursor }
        cursor.offset = size
        absorb(data, skipFirstLine: truncated, cursor: &cursor)
        return cursor
    }

    static func advance(_ cursor: inout CodexCursor, url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > cursor.offset else { return }
        try? handle.seek(toOffset: cursor.offset)
        guard let data = try? handle.readToEnd() else { return }
        cursor.offset = size
        absorb(data, skipFirstLine: false, cursor: &cursor)
    }

    private static func absorb(_ data: Data, skipFirstLine: Bool, cursor: inout CodexCursor) {
        var buffer = cursor.remainder
        buffer.append(data)
        cursor.remainder = Data()

        var lines = buffer.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if skipFirstLine, !lines.isEmpty { lines.removeFirst() }
        if buffer.last != UInt8(ascii: "\n"), let last = lines.popLast() {
            cursor.remainder = Data(last)
        }
        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            absorb(object, into: &cursor.scan)
        }
    }

    static func absorb(_ event: [String: Any], into scan: inout CodexScan) {
        if let timestamp = event["timestamp"] as? String, let date = DateParsing.iso(timestamp) {
            scan.lastEventAt = date
        }
        let payload = event["payload"] as? [String: Any] ?? [:]

        switch event["type"] as? String {
        case "session_meta":
            scan.cwd = payload["cwd"] as? String ?? scan.cwd
            scan.originator = payload["originator"] as? String ?? scan.originator
            if let started = payload["timestamp"] as? String { scan.startedAt = DateParsing.iso(started) }
            if let git = payload["git"] as? [String: Any], let branch = git["branch"] as? String {
                scan.branch = branch
            }

        case "turn_context":
            scan.cwd = payload["cwd"] as? String ?? scan.cwd
            scan.model = payload["model"] as? String ?? scan.model

        case "event_msg":
            absorbEventMessage(payload, into: &scan)

        case "response_item":
            switch payload["type"] as? String {
            case "function_call", "custom_tool_call":
                if let name = payload["name"] as? String {
                    scan.status = .working
                    scan.activity = name
                }
            case "reasoning":
                scan.status = .working
                scan.activity = tr("ragiona…")
            default:
                break
            }

        default:
            break
        }
    }

    private static func absorbEventMessage(_ payload: [String: Any], into scan: inout CodexScan) {
        let type = payload["type"] as? String ?? ""
        switch type {
        case "task_started":
            scan.status = .working
            scan.activity = tr("prompt inviato")
        case "task_complete":
            let message = payload["last_agent_message"] as? String
            scan.status = message.map(TranscriptScanner.endsWithQuestion) == true ? .attention : .done
            if let message {
                scan.activity = TranscriptScanner.snippet(message)
            }
        case "turn_aborted":
            scan.status = .done
            scan.activity = tr("turno interrotto")
        case "user_message":
            if let message = payload["message"] as? String, !message.isEmpty { scan.lastPrompt = message }
        case "agent_message":
            if let message = payload["message"] as? String { scan.activity = TranscriptScanner.snippet(message) }
        case "token_count":
            if let info = payload["info"] as? [String: Any] {
                if let last = info["last_token_usage"] as? [String: Any], let total = last["total_tokens"] as? Int {
                    scan.tokensUsed = total
                }
                if let limit = info["model_context_window"] as? Int { scan.tokenLimit = limit }
            }
        case "error", "stream_error":
            scan.status = .error
            if let message = payload["message"] as? String { scan.activity = TranscriptScanner.snippet(message) }
        default:
            if type.contains("approval_request") {
                scan.status = .blocked
                scan.activity = tr("permesso richiesto")
            }
        }
    }
}
