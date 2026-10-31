import Foundation

/// Una sessione come la conosce l'app Claude Desktop.
struct DesktopSession: Sendable {
    var sessionID: String          // local_<uuid>: l'id con cui l'app la indirizza
    var cliSessionID: String?      // l'uuid del transcript, il ponte verso il CLI
    var title: String?
    var cwd: String?
    var isArchived: Bool
    var lastActivityAt: Date?

    /// Deep link che porta Claude Desktop dentro *questa* chat.
    var deepLink: String { "claude://claude.ai/claude-code-desktop/\(sessionID)" }
}

/// Indice delle sessioni di Claude Desktop, letto da
/// `~/Library/Application Support/Claude/claude-code-sessions/<account>/<workspace>/local_*.json`.
///
/// Serve per due cose che il transcript da solo non dà: l'id con cui l'app
/// apre una chat specifica, e il titolo che l'utente vede nell'app.
final class ClaudeDesktopIndex {
    private let root: URL
    private var cache: [String: (modified: Date, session: DesktopSession)] = [:]

    init(root: URL? = nil) {
        self.root = root ?? AppPaths.home.appendingPathComponent(
            "Library/Application Support/Claude/claude-code-sessions",
            isDirectory: true
        )
    }

    /// Mappa `cliSessionId` → sessione desktop.
    func load() -> [String: DesktopSession] {
        let fm = FileManager.default
        guard let accounts = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return [:]
        }

        var result: [String: DesktopSession] = [:]
        var livePaths: Set<String> = []

        for account in accounts {
            guard (try? account.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard let workspaces = try? fm.contentsOfDirectory(at: account, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }

            for workspace in workspaces {
                guard (try? workspace.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                guard let files = try? fm.contentsOfDirectory(
                    at: workspace,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                ) else { continue }

                for file in files where file.pathExtension == "json" && file.lastPathComponent.hasPrefix("local_") {
                    livePaths.insert(file.path)
                    let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast

                    let session: DesktopSession
                    if let cached = cache[file.path], cached.modified == modified {
                        session = cached.session
                    } else {
                        // I file pesano decine di KB: si rileggono solo se cambiati.
                        guard let decoded = decode(file) else { continue }
                        cache[file.path] = (modified, decoded)
                        session = decoded
                    }

                    if let cli = session.cliSessionID {
                        // A parità di cliSessionId vince la sessione toccata più di recente.
                        if let existing = result[cli],
                           (existing.lastActivityAt ?? .distantPast) > (session.lastActivityAt ?? .distantPast) {
                            continue
                        }
                        result[cli] = session
                    }
                }
            }
        }

        if cache.count > livePaths.count {
            cache = cache.filter { livePaths.contains($0.key) }
        }
        return result
    }

    private func decode(_ url: URL) -> DesktopSession? {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode(RawSession.self, from: data),
              let id = raw.sessionId
        else { return nil }
        return DesktopSession(
            sessionID: id,
            cliSessionID: raw.cliSessionId,
            title: raw.title,
            cwd: raw.cwd,
            isArchived: raw.isArchived ?? false,
            lastActivityAt: raw.lastActivityAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        )
    }

    private struct RawSession: Decodable {
        var sessionId: String?
        var cliSessionId: String?
        var title: String?
        var cwd: String?
        var isArchived: Bool?
        var lastActivityAt: Double?
    }
}
