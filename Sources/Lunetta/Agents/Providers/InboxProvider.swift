import Foundation

/// Provider push: legge i file JSON depositati in una cartella.
///
/// Qualunque agent (o un hook di Claude Code) può scrivere
/// `~/.lunetta/inbox/<qualcosa>.json` e comparire subito nella notch.
actor InboxProvider: SessionProvider {
    nonisolated let id: String
    nonisolated let displayName: String
    nonisolated let accentHex: String?

    private let directory: URL
    /// Oltre questa età un file viene ignorato: evita sessioni fantasma dimenticate sul disco.
    private let maxAge: TimeInterval = 24 * 3600

    init(config: ProviderConfig) {
        id = config.id
        displayName = config.name ?? "Inbox"
        accentHex = config.accent ?? "#8B5CF6"
        directory = config.path.map(AppPaths.expand) ?? AppPaths.defaultInbox
    }

    func fetch(config: AgentsConfig) async -> ProviderResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            return ProviderResult()
        }

        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else {
            return ProviderResult(error: "cartella non leggibile")
        }

        var sessions: [AgentSession] = []
        var failures = 0

        for file in files where file.pathExtension == "json" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            guard Date().timeIntervalSince(modified) < maxAge else { continue }
            guard let data = try? Data(contentsOf: file) else { continue }
            guard let payloads = try? SessionPayload.decodeList(from: data) else {
                failures += 1
                continue
            }
            let stem = file.deletingPathExtension().lastPathComponent
            for (index, payload) in payloads.enumerated() {
                var session = payload.session(
                    providerID: id,
                    providerName: displayName,
                    accentHex: accentHex,
                    fallbackID: payloads.count > 1 ? "\(stem)-\(index)" : stem,
                    config: config
                )
                // Senza updatedAt esplicito vale la data del file.
                if payload.updatedAt == nil { session.updatedAt = modified }
                // Un processo dichiarato ma morto significa sessione chiusa.
                if let pid = session.pid, session.status.isLive, !ProcessProbe.isAlive(pid: pid, startedAt: nil) {
                    session.status = .ended
                }
                sessions.append(session)
            }
        }

        return ProviderResult(
            sessions: sessions,
            error: failures > 0 ? "\(failures) file JSON non validi" : nil
        )
    }
}
