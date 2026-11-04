import Foundation

/// Stato normalizzato di una sessione, comune a tutti i provider.
enum SessionStatus: String, Codable, Sendable, CaseIterable {
    /// L'agent sta lavorando (tool in esecuzione, risposta in streaming).
    case working
    /// L'agent ti aspetta davvero: una domanda, un piano da approvare.
    case attention
    /// Il turno è finito e non c'è niente da decidere: una notizia, non una chiamata.
    case done
    /// L'agent è bloccato in attesa di un permesso/approvazione.
    case blocked
    /// Sessione viva ma ferma da un po'.
    case idle
    /// Processo terminato / sessione chiusa.
    case ended
    /// Ultimo turno finito in errore.
    case error

    var label: String {
        switch self {
        case .working:   tr("in esecuzione")
        case .attention: tr("attende te")
        case .done:      tr("finita")
        case .blocked:   tr("permesso richiesto")
        case .idle:      tr("in pausa")
        case .ended:     tr("terminata")
        case .error:     tr("errore")
        }
    }

    var symbol: String {
        switch self {
        case .working:   "bolt.fill"
        case .attention: "hand.raised.fill"
        case .done:      "checkmark.circle.fill"
        case .blocked:   "lock.fill"
        case .idle:      "moon.zzz.fill"
        case .ended:     "checkmark"
        case .error:     "exclamationmark.triangle.fill"
        }
    }

    /// Richiede un intervento umano adesso.
    var needsYou: Bool { self == .attention || self == .blocked || self == .error }

    /// La sessione è ancora aperta.
    var isLive: Bool { self != .ended }

    /// Ordinamento: prima ciò che è bloccato, poi ciò che chiede attenzione, poi il lavoro in corso.
    var rank: Int {
        switch self {
        case .blocked:   0
        case .error:     1
        case .attention: 2
        case .working:   3
        case .done:      4
        case .idle:      5
        case .ended:     6
        }
    }

    /// Mappa le stringhe libere che arrivano dai provider esterni.
    static func parse(_ raw: String?) -> SessionStatus? {
        guard let raw = raw?.lowercased().trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        switch raw {
        case "working", "running", "busy", "active", "thinking", "in_progress", "in-progress":
            return .working
        case "attention", "waiting", "waiting_input", "waiting-input", "input", "needs_input", "ready", "done_turn":
            return .attention
        case "blocked", "permission", "permission_request", "approval", "confirm", "paused_permission":
            return .blocked
        case "turn_done", "turn-done":
            return .done
        case "idle", "paused", "sleeping", "stale":
            return .idle
        case "ended", "done", "finished", "complete", "completed", "closed", "exited":
            return .ended
        case "error", "failed", "failure", "crashed":
            return .error
        default:
            return nil
        }
    }
}

/// Azione eseguibile su una sessione (i provider esterni possono dichiararne di proprie).
struct SessionAction: Codable, Equatable, Sendable, Identifiable {
    var label: String
    /// Comando shell eseguito con `/bin/sh -c`, con `$ORBIT_PATH` e `$ORBIT_SESSION` nell'ambiente.
    var command: String
    /// Nome di un SF Symbol.
    var symbol: String?

    var id: String { label + command }
}

/// Una sessione agent, indipendente dalla sorgente.
struct AgentSession: Identifiable, Equatable, Sendable {
    var id: String
    var providerID: String
    var providerName: String
    var accentHex: String?

    var title: String
    var project: String
    var path: String?
    var branch: String?
    var model: String?

    var status: SessionStatus
    var activity: String?
    var detail: String?
    /// Dove gira la sessione: "Desktop", "Terminale", "VS Code"…
    var host: String?

    var startedAt: Date?
    var updatedAt: Date

    var tokensUsed: Int?
    var tokenLimit: Int?

    var pid: Int32?
    /// Identificativo nativo della sessione presso il provider (es. sessionId di Claude Code).
    var nativeID: String?
    /// URL che apre *questa* sessione nella sua app (deep link). Se manca, "Vai"
    /// si limita a portare in primo piano l'app che la ospita.
    var openURL: String?
    var actions: [SessionAction]

    init(
        id: String,
        providerID: String,
        providerName: String,
        accentHex: String? = nil,
        title: String,
        project: String,
        path: String? = nil,
        branch: String? = nil,
        model: String? = nil,
        status: SessionStatus,
        activity: String? = nil,
        detail: String? = nil,
        host: String? = nil,
        startedAt: Date? = nil,
        updatedAt: Date,
        tokensUsed: Int? = nil,
        tokenLimit: Int? = nil,
        pid: Int32? = nil,
        nativeID: String? = nil,
        openURL: String? = nil,
        actions: [SessionAction] = []
    ) {
        self.id = id
        self.providerID = providerID
        self.providerName = providerName
        self.accentHex = accentHex
        self.title = title
        self.project = project
        self.path = path
        self.branch = branch
        self.model = model
        self.status = status
        self.activity = activity
        self.detail = detail
        self.host = host
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.tokensUsed = tokensUsed
        self.tokenLimit = tokenLimit
        self.pid = pid
        self.nativeID = nativeID
        self.openURL = openURL
        self.actions = actions
    }

    var contextFraction: Double? {
        guard let used = tokensUsed, let limit = tokenLimit, limit > 0 else { return nil }
        return min(1, max(0, Double(used) / Double(limit)))
    }

    /// Ordinamento di default della lista.
    static func ordered(_ list: [AgentSession]) -> [AgentSession] {
        list.sorted { a, b in
            if a.status.rank != b.status.rank { return a.status.rank < b.status.rank }
            return a.updatedAt > b.updatedAt
        }
    }
}

// MARK: - Payload per provider esterni

/// Schema JSON pubblico che qualunque agent può produrre per comparire in Orbit.
struct SessionPayload: Decodable, Sendable {
    var id: String?
    var title: String?
    var project: String?
    var path: String?
    var branch: String?
    var model: String?
    var status: String?
    var activity: String?
    var detail: String?
    var startedAt: FlexibleDate?
    var updatedAt: FlexibleDate?
    var tokens: TokenPayload?
    var pid: Int32?
    var accent: String?
    var provider: String?
    /// Deep link per aprire la sessione nella sua app.
    var openURL: String?
    var url: String?
    var actions: [SessionAction]?

    struct TokenPayload: Decodable, Sendable {
        var used: Int?
        var limit: Int?
    }

    /// Accetta sia un singolo oggetto, sia un array, sia `{"sessions": [...]}`.
    static func decodeList(from data: Data) throws -> [SessionPayload] {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([SessionPayload].self, from: data) { return list }
        if let wrapper = try? decoder.decode(Wrapper.self, from: data), let list = wrapper.sessions { return list }
        return [try decoder.decode(SessionPayload.self, from: data)]
    }

    private struct Wrapper: Decodable { var sessions: [SessionPayload]? }

    func session(providerID: String, providerName: String, accentHex: String?, fallbackID: String, config: AgentsConfig) -> AgentSession {
        let rawPath = path.map { NSString(string: $0).expandingTildeInPath }
        let derivedProject = project
            ?? rawPath.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? providerName
        let updated = updatedAt?.date ?? Date()
        let status = SessionStatus.parse(status) ?? .working
        return AgentSession(
            id: "\(providerID):\(id ?? fallbackID)",
            providerID: providerID,
            providerName: provider ?? providerName,
            accentHex: accent ?? accentHex,
            title: title ?? derivedProject,
            project: derivedProject,
            path: rawPath,
            branch: branch,
            model: model,
            status: status,
            activity: activity,
            detail: detail,
            startedAt: startedAt?.date,
            updatedAt: updated,
            tokensUsed: tokens?.used,
            tokenLimit: tokens?.limit ?? tokens?.used.map { config.contextLimit(for: $0) },
            pid: pid,
            nativeID: id,
            openURL: openURL ?? url,
            actions: actions ?? []
        )
    }
}

/// Data che accetta ISO-8601, epoch in secondi o epoch in millisecondi.
struct FlexibleDate: Decodable, Sendable {
    let date: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            date = number > 3_000_000_000 ? Date(timeIntervalSince1970: number / 1000) : Date(timeIntervalSince1970: number)
            return
        }
        let string = try container.decode(String.self)
        if let parsed = DateParsing.iso(string) {
            date = parsed
        } else if let number = Double(string) {
            date = number > 3_000_000_000 ? Date(timeIntervalSince1970: number / 1000) : Date(timeIntervalSince1970: number)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Data non riconosciuta: \(string)")
        }
    }
}

enum DateParsing {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func iso(_ string: String) -> Date? {
        withFraction.date(from: string) ?? plain.date(from: string)
    }
}
