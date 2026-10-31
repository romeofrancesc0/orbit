import Foundation

/// Configurazione utente, letta da `~/.config/agentbar/config.json` e ricaricata a caldo.
struct AppConfig: Codable, Sendable, Equatable {
    var refreshSeconds: Double
    var activeRefreshSeconds: Double
    var showRecent: Bool
    var recentWindowHours: Double
    var maxPeekRows: Int
    var idleAfterMinutes: Double
    var defaultTokenLimit: Int
    var useLiquidGlass: Bool
    var showCountInMenuBar: Bool
    var providers: [ProviderConfig]

    static let `default` = AppConfig(
        refreshSeconds: 3,
        activeRefreshSeconds: 1,
        showRecent: true,
        recentWindowHours: 12,
        maxPeekRows: 4,
        idleAfterMinutes: 6,
        defaultTokenLimit: 200_000,
        useLiquidGlass: true,
        showCountInMenuBar: true,
        providers: [
            ProviderConfig(id: "claude-code", type: "claude-code", name: "Claude Code", enabled: true, accent: "#D97757"),
            ProviderConfig(id: "inbox", type: "inbox", name: "Inbox", enabled: true, accent: "#8B5CF6", path: "~/.agentbar/inbox")
        ]
    )

    init(
        refreshSeconds: Double = 3,
        activeRefreshSeconds: Double = 1,
        showRecent: Bool = true,
        recentWindowHours: Double = 12,
        maxPeekRows: Int = 4,
        idleAfterMinutes: Double = 6,
        defaultTokenLimit: Int = 200_000,
        useLiquidGlass: Bool = true,
        showCountInMenuBar: Bool = true,
        providers: [ProviderConfig] = []
    ) {
        self.refreshSeconds = refreshSeconds
        self.activeRefreshSeconds = activeRefreshSeconds
        self.showRecent = showRecent
        self.recentWindowHours = recentWindowHours
        self.maxPeekRows = maxPeekRows
        self.idleAfterMinutes = idleAfterMinutes
        self.defaultTokenLimit = defaultTokenLimit
        self.useLiquidGlass = useLiquidGlass
        self.showCountInMenuBar = showCountInMenuBar
        self.providers = providers
    }

    /// La finestra di contesto non è scritta nei transcript e cambia da modello a
    /// modello: si sceglie il primo scaglione che contiene i token già usati.
    func contextLimit(for used: Int) -> Int {
        let tiers = [defaultTokenLimit, 500_000, 1_000_000, 2_000_000].sorted()
        if let tier = tiers.first(where: { used <= $0 }) { return tier }
        let million = 1_000_000
        return ((used / million) + 1) * million
    }

    // Decoder tollerante: ogni campo mancante ricade sul default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig.default
        refreshSeconds = (try? c.decode(Double.self, forKey: .refreshSeconds)) ?? d.refreshSeconds
        activeRefreshSeconds = (try? c.decode(Double.self, forKey: .activeRefreshSeconds)) ?? d.activeRefreshSeconds
        showRecent = (try? c.decode(Bool.self, forKey: .showRecent)) ?? d.showRecent
        recentWindowHours = (try? c.decode(Double.self, forKey: .recentWindowHours)) ?? d.recentWindowHours
        maxPeekRows = (try? c.decode(Int.self, forKey: .maxPeekRows)) ?? d.maxPeekRows
        idleAfterMinutes = (try? c.decode(Double.self, forKey: .idleAfterMinutes)) ?? d.idleAfterMinutes
        defaultTokenLimit = (try? c.decode(Int.self, forKey: .defaultTokenLimit)) ?? d.defaultTokenLimit
        useLiquidGlass = (try? c.decode(Bool.self, forKey: .useLiquidGlass)) ?? d.useLiquidGlass
        showCountInMenuBar = (try? c.decode(Bool.self, forKey: .showCountInMenuBar)) ?? d.showCountInMenuBar
        providers = (try? c.decode([ProviderConfig].self, forKey: .providers)) ?? d.providers
    }
}

struct ProviderConfig: Codable, Sendable, Equatable, Identifiable {
    var id: String
    /// `claude-code` | `command` | `inbox`
    var type: String
    var name: String?
    var enabled: Bool
    var accent: String?
    /// Provider `command`: eseguibile o riga di comando completa.
    var command: String?
    var args: [String]?
    /// Provider `inbox`: cartella osservata. Provider `claude-code`: root alternativa di `~/.claude`.
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
    static var configDirectory: URL { home.appendingPathComponent(".config/agentbar", isDirectory: true) }
    static var configFile: URL { configDirectory.appendingPathComponent("config.json") }
    static var defaultInbox: URL { home.appendingPathComponent(".agentbar/inbox", isDirectory: true) }

    static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }
}

/// Carica la configurazione e la ricarica quando il file cambia sul disco.
final class ConfigStore: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: AppConfig
    private var stamp: Date?

    init() {
        cached = ConfigStore.readFromDisk() ?? .default
        ConfigStore.bootstrapIfNeeded()
    }

    var current: AppConfig {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    /// Rilegge il file solo se la data di modifica è cambiata.
    @discardableResult
    func reloadIfChanged() -> AppConfig {
        let attrs = try? FileManager.default.attributesOfItem(atPath: AppPaths.configFile.path)
        let modified = attrs?[.modificationDate] as? Date
        lock.lock()
        let unchanged = modified == stamp
        lock.unlock()
        if unchanged { return current }

        let fresh = ConfigStore.readFromDisk() ?? .default
        lock.lock()
        cached = fresh
        stamp = modified
        lock.unlock()
        return fresh
    }

    private static func readFromDisk() -> AppConfig? {
        guard let data = try? Data(contentsOf: AppPaths.configFile) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    /// Alla prima esecuzione scrive un config di esempio commentato (via file affiancato).
    private static func bootstrapIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: AppPaths.configDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: AppPaths.defaultInbox, withIntermediateDirectories: true)

        if !fm.fileExists(atPath: AppPaths.configFile.path) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(AppConfig.default) {
                try? data.write(to: AppPaths.configFile)
            }
        }
    }

    func write(_ config: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? FileManager.default.createDirectory(at: AppPaths.configDirectory, withIntermediateDirectories: true)
        try? data.write(to: AppPaths.configFile)
        lock.lock()
        cached = config
        stamp = (try? FileManager.default.attributesOfItem(atPath: AppPaths.configFile.path))?[.modificationDate] as? Date
        lock.unlock()
    }
}
