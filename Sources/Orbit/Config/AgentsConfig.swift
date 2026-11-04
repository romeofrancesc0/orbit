import Foundation

/// Impostazioni delle sessioni dei coding agent.
struct AgentsConfig: Codable, Sendable, Equatable {
    /// Giro di riserva a notch chiusa: i cambiamenti su disco arrivano subito via FSEvents.
    var refreshSeconds: Double = 6
    /// Giro di riserva a notch aperta.
    var activeRefreshSeconds: Double = 2
    var showRecent: Bool = true
    var recentWindowHours: Double = 12
    var idleAfterMinutes: Double = 6
    var defaultTokenLimit: Int = 200_000
    var providers: [ProviderConfig] = AgentsConfig.defaultProviders

    /// La finestra di contesto non è scritta nei transcript e cambia da modello a
    /// modello: si sceglie il primo scaglione che contiene i token già usati.
    func contextLimit(for used: Int) -> Int {
        let tiers = [defaultTokenLimit, 500_000, 1_000_000, 2_000_000].sorted()
        if let tier = tiers.first(where: { used <= $0 }) { return tier }
        let million = 1_000_000
        return ((used / million) + 1) * million
    }

    static var defaultProviders: [ProviderConfig] {
        [
            ProviderConfig(id: "claude-code", type: "claude-code", name: "Claude Code", enabled: true, accent: "#D97757"),
            ProviderConfig(id: "codex", type: "codex", name: "Codex", enabled: true, accent: "#10A37F"),
            ProviderConfig(id: "inbox", type: "inbox", name: "Inbox", enabled: true, accent: "#8B5CF6", path: "~/.orbit/inbox")
        ]
    }
}

struct ProviderConfig: Codable, Sendable, Equatable, Identifiable {
    var id: String
    /// `claude-code` | `codex` | `command` | `inbox`
    var type: String
    var name: String?
    var enabled: Bool
    var accent: String?
    /// Provider `command`: eseguibile o riga di comando completa.
    var command: String?
    var args: [String]?
    /// Provider `inbox`: cartella osservata. Provider nativi: root alternativa della cartella dell'agent.
    var path: String?

    init(id: String, type: String, name: String? = nil, enabled: Bool = true, accent: String? = nil,
         command: String? = nil, args: [String]? = nil, path: String? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.enabled = enabled
        self.accent = accent
        self.command = command
        self.args = args
        self.path = path
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = (try? c.decode(String.self, forKey: .type)) ?? "command"
        name = try? c.decode(String.self, forKey: .name)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        accent = try? c.decode(String.self, forKey: .accent)
        command = try? c.decode(String.self, forKey: .command)
        args = try? c.decode([String].self, forKey: .args)
        path = try? c.decode(String.self, forKey: .path)
    }
}

/// Percorsi standard dell'app.
enum AppPaths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var configDirectory: URL { home.appendingPathComponent(".config/orbit", isDirectory: true) }
    static var configFile: URL { configDirectory.appendingPathComponent("config.json") }
    static var dataDirectory: URL { home.appendingPathComponent(".orbit", isDirectory: true) }
    static var defaultInbox: URL { dataDirectory.appendingPathComponent("inbox", isDirectory: true) }
    static var hintsDirectory: URL { dataDirectory.appendingPathComponent("hints", isDirectory: true) }
    static var hooksDirectory: URL { dataDirectory.appendingPathComponent("hooks", isDirectory: true) }
    static var notesFile: URL { configDirectory.appendingPathComponent("note.md") }
    static var shelfFile: URL { configDirectory.appendingPathComponent("scaffale.json") }
    static var shelfStorage: URL {
        // The copies made before Orbit live under the old name: they stay there, nothing to move.
        let legacy = home.appendingPathComponent("Library/Application Support/Powered Notch/Scaffale", isDirectory: true)
        if FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        return home.appendingPathComponent("Library/Application Support/Orbit/Scaffale", isDirectory: true)
    }
    /// Dove l'app teneva i suoi file quando si chiamava Powered Notch.
    static var poweredNotchConfigDirectory: URL { home.appendingPathComponent(".config/powered-notch", isDirectory: true) }
    static var poweredNotchDataDirectory: URL { home.appendingPathComponent(".powered-notch", isDirectory: true) }

    /// Porta le cartelle di Powered Notch sotto il nome nuovo, una volta sola. Al vecchio posto resta un
    /// collegamento: gli hook già installati in `~/.claude/settings.json` e gli script di chi ha scelto
    /// quei percorsi continuano a funzionare.
    static func migrateFromPoweredNotch() {
        moveLeavingLink(from: poweredNotchConfigDirectory, to: configDirectory)
        moveLeavingLink(from: poweredNotchDataDirectory, to: dataDirectory)
    }

    /// Sposta `old` in `new` e lascia al suo posto un collegamento. Non fa nulla se `new` esiste già
    /// o se `old` non c'è (o è già un collegamento). Restituisce se ha spostato qualcosa.
    @discardableResult
    static func moveLeavingLink(from old: URL, to new: URL) -> Bool {
        let fm = FileManager.default
        let isLink = (try? old.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
        guard fm.fileExists(atPath: old.path), !isLink, !fm.fileExists(atPath: new.path) else { return false }
        do {
            try fm.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: old, to: new)
            try fm.createSymbolicLink(at: old, withDestinationURL: new)
            return true
        } catch {
            // Se qualcosa va storto a metà si rimette tutto com'era: meglio la vecchia cartella che nessuna.
            if !fm.fileExists(atPath: old.path), fm.fileExists(atPath: new.path) { try? fm.moveItem(at: new, to: old) }
            return false
        }
    }

    /// Il nome con cui l'app si chiamava prima di Powered Notch.
    static var lunettaConfigDirectory: URL { home.appendingPathComponent(".config/lunetta", isDirectory: true) }
    static var legacyConfigDirectory: URL { home.appendingPathComponent(".config/agentbar", isDirectory: true) }

    static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }
}
