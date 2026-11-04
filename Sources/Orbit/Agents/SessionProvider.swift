import Foundation

/// Risultato di un giro di polling su un provider.
struct ProviderResult: Sendable {
    var sessions: [AgentSession]
    var error: String?

    init(sessions: [AgentSession] = [], error: String? = nil) {
        self.sessions = sessions
        self.error = error
    }
}

/// Una sorgente di sessioni. Aggiungere un agent significa aggiungere un provider
/// (o, senza scrivere Swift, un provider `command`/`inbox` nel config).
protocol SessionProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var accentHex: String? { get }
    func fetch(config: AgentsConfig) async -> ProviderResult
}

/// Costruisce i provider a partire dalla configurazione.
enum ProviderFactory {
    static func make(_ configs: [ProviderConfig]) -> [SessionProvider] {
        configs.compactMap { entry in
            guard entry.enabled else { return nil }
            switch entry.type.lowercased() {
            case "claude-code", "claudecode", "claude":
                return ClaudeCodeProvider(config: entry)
            case "codex":
                return CodexProvider(config: entry)
            case "command", "exec", "script":
                return CommandProvider(config: entry)
            case "inbox", "folder", "watch":
                return InboxProvider(config: entry)
            default:
                return nil
            }
        }
    }
}
