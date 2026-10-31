import Foundation

/// Ciò che si riesce a dedurre da un transcript `.jsonl` di Claude Code.
struct TranscriptScan: Sendable {
    var lastEventAt: Date?
    var status: SessionStatus?
    var activity: String?
    var title: String?
    var lastPrompt: String?
    var tokensUsed: Int?
    var model: String?
    var branch: String?
    var cwd: String?
}

/// Punto a cui è arrivata la lettura di un transcript. Un agent al lavoro aggiunge
/// righe di continuo: si leggono solo quelle nuove invece di rielaborare la coda
/// del file a ogni giro.
struct TranscriptCursor: Sendable {
    var offset: UInt64 = 0
    var scan = TranscriptScan()
    /// Ultima riga ancora incompleta quando è stata letta.
    var remainder = Data()
}

enum TranscriptScanner {
    /// Prima lettura: solo la coda, perché i transcript arrivano a decine di MB.
    static func start(url: URL, tailBytes: Int = 256 * 1024) -> TranscriptCursor {
        var cursor = TranscriptCursor()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return cursor }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd(), size > 0 else { return cursor }
        let window = UInt64(tailBytes)
        let truncated = size > window
        let offset = truncated ? size - window : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return cursor }

        cursor.offset = size
        let parsed = absorb(data, skipFirstLine: truncated, cursor: &cursor)

        // Se una singola riga era più grande della finestra non abbiamo letto nulla di
        // utile: si riprova una volta sola con una finestra molto più larga.
        if parsed == 0, truncated, tailBytes < 4 * 1024 * 1024 {
            return start(url: url, tailBytes: 4 * 1024 * 1024)
        }
        return cursor
    }

    /// Letture successive: solo ciò che è stato aggiunto dall'ultima volta.
    static func advance(_ cursor: TranscriptCursor, url: URL) -> TranscriptCursor {
        var next = cursor
        guard let handle = try? FileHandle(forReadingFrom: url) else { return next }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return next }
        // Il file si è accorciato: è stato riscritto, si riparte da capo.
        if size < cursor.offset { return start(url: url) }
        guard size > cursor.offset else { return next }

        try? handle.seek(toOffset: cursor.offset)
        guard let data = try? handle.readToEnd() else { return next }
        next.offset = size
        _ = absorb(data, skipFirstLine: false, cursor: &next)
        return next
    }

    /// Compatibilità: una lettura completa e nient'altro.
    static func scan(url: URL) -> TranscriptScan {
        start(url: url).scan
    }

    private static func absorb(_ data: Data, skipFirstLine: Bool, cursor: inout TranscriptCursor) -> Int {
        var buffer = cursor.remainder
        buffer.append(data)
        cursor.remainder = Data()

        var lines = buffer.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        // La prima riga della finestra è quasi certamente tagliata a metà.
        if skipFirstLine, !lines.isEmpty { lines.removeFirst() }

        // Un'ultima riga senza a capo finale è ancora in scrittura.
        if buffer.last != UInt8(ascii: "\n"), let last = lines.popLast() {
            cursor.remainder = Data(last)
        }

        var parsed = 0
        for line in lines {
            guard line.count > 2,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else { continue }
            parsed += 1
            absorb(object, into: &cursor.scan)
        }
        return parsed
    }

    // MARK: - Interpretazione dei singoli eventi

    private static func absorb(_ event: [String: Any], into scan: inout TranscriptScan) {
        let type = event["type"] as? String ?? ""

        if let cwd = event["cwd"] as? String { scan.cwd = cwd }
        if let branch = event["gitBranch"] as? String, !branch.isEmpty { scan.branch = branch }
        if let timestamp = event["timestamp"] as? String, let date = DateParsing.iso(timestamp) {
            scan.lastEventAt = date
        }

        switch type {
        case "custom-title":
            if let title = event["customTitle"] as? String, !title.isEmpty { scan.title = title }
            return

        case "last-prompt":
            if let prompt = event["lastPrompt"] as? String, !prompt.isEmpty { scan.lastPrompt = prompt }
            return

        case "queue-operation":
            if (event["operation"] as? String) == "enqueue" {
                scan.status = .working
                scan.activity = "prompt in coda"
            }
            return

        case "assistant":
            absorbAssistant(event, into: &scan)

        case "user":
            absorbUser(event, into: &scan)

        default:
            // attachment, system, file-history-snapshot, summary…: non cambiano lo stato.
            return
        }
    }

    private static func absorbAssistant(_ event: [String: Any], into scan: inout TranscriptScan) {
        guard let message = event["message"] as? [String: Any] else { return }
        let sidechain = (event["isSidechain"] as? Bool) ?? false

        if let model = message["model"] as? String, !model.isEmpty { scan.model = model }
        if let usage = message["usage"] as? [String: Any] {
            // Con più iterazioni la usage di primo livello è la somma di tutte:
            // sommarla darebbe multipli della finestra di contesto. L'ultima
            // iterazione è invece la fotografia del contesto in quel momento.
            let iterations = usage["iterations"] as? [[String: Any]]
            let snapshot = iterations?.last ?? usage
            let input = (snapshot["input_tokens"] as? Int) ?? 0
            let cacheRead = (snapshot["cache_read_input_tokens"] as? Int) ?? 0
            let cacheWrite = (snapshot["cache_creation_input_tokens"] as? Int) ?? 0
            let output = (snapshot["output_tokens"] as? Int) ?? 0
            let total = input + cacheRead + cacheWrite + output
            if total > 0 { scan.tokensUsed = total }
        }

        let blocks = (message["content"] as? [[String: Any]]) ?? []
        let stopReason = message["stop_reason"] as? String

        var activity: String?
        var status: SessionStatus = .working

        for block in blocks {
            switch block["type"] as? String {
            case "tool_use":
                let name = (block["name"] as? String) ?? "tool"
                activity = describeTool(name: name, input: block["input"] as? [String: Any])
                status = .working
            case "thinking", "redacted_thinking":
                activity = activity ?? "ragiona…"
                status = .working
            case "text":
                let text = (block["text"] as? String) ?? ""
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    activity = activity ?? snippet(text)
                }
            default:
                break
            }
        }

        switch stopReason {
        case "tool_use":
            status = .working
        case "end_turn", "stop_sequence":
            // Turno concluso senza tool: tocca all'umano. Non se a finire è un subagent:
            // lì il lavoro continua, e un falso "attende te" accenderebbe la notch per niente.
            if !sidechain, !blocks.contains(where: { ($0["type"] as? String) == "tool_use" }) {
                // L'etichetta di stato dice già "attende te": qui resta al più
                // l'ultima frase dell'agent, che è informativa.
                status = .attention
            }
        case "max_tokens":
            status = .error
            activity = "risposta troncata (max tokens)"
        case "refusal":
            status = .attention
        default:
            break
        }

        scan.status = status
        if let activity {
            scan.activity = sidechain ? "subagent · \(activity)" : activity
        }
    }

    private static func absorbUser(_ event: [String: Any], into scan: inout TranscriptScan) {
        guard let message = event["message"] as? [String: Any] else { return }
        let sidechain = (event["isSidechain"] as? Bool) ?? false

        var isToolResult = false
        var isError = false
        if let blocks = message["content"] as? [[String: Any]] {
            for block in blocks where (block["type"] as? String) == "tool_result" {
                isToolResult = true
                if (block["is_error"] as? Bool) == true { isError = true }
            }
        }

        if isToolResult {
            scan.status = .working
            let base = isError ? "tool fallito, riprova…" : "elabora i risultati"
            scan.activity = sidechain ? "subagent · \(base)" : base
        } else {
            // Un vero prompt umano: da qui riparte il lavoro.
            scan.status = .working
            scan.activity = "prompt inviato"
            if let text = message["content"] as? String, !text.isEmpty {
                scan.lastPrompt = text
            } else if let blocks = message["content"] as? [[String: Any]] {
                let text = blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
                if !text.isEmpty { scan.lastPrompt = text }
            }
        }
    }

    // MARK: - Etichette

    /// "Edit · Prop.swift", "Bash · swift build -c release"…
    private static func describeTool(name: String, input: [String: Any]?) -> String {
        let clean = name.hasPrefix("mcp__")
            ? name.split(separator: "_").filter { !$0.isEmpty }.last.map(String.init) ?? name
            : name
        guard let input else { return clean }

        let hint: String?
        switch clean {
        case "Bash", "BashOutput":
            hint = (input["command"] as? String) ?? (input["description"] as? String)
        case "Read", "Edit", "Write", "NotebookEdit":
            hint = (input["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        case "Glob", "Grep":
            hint = (input["pattern"] as? String)
        case "Task", "Agent":
            hint = (input["description"] as? String)
        case "WebFetch", "WebSearch":
            hint = (input["url"] as? String).flatMap { URL(string: $0)?.host } ?? (input["query"] as? String)
        case "Skill":
            hint = (input["skill"] as? String)
        default:
            hint = (input["description"] as? String)
                ?? (input["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? (input["command"] as? String)
        }

        guard let hint, !hint.isEmpty else { return clean }
        return "\(clean) · \(snippet(hint, limit: 46))"
    }

    static func snippet(_ text: String, limit: Int = 70) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
