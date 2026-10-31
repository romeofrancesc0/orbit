import Foundation

/// Sessioni tolte a mano dall'elenco.
///
/// Non si cancella niente: si annota *quando* una sessione è stata rimossa.
/// Finché la sessione resta ferma a prima di quel momento, sparisce; appena
/// riprende a lavorare — cioè arriva un evento più recente — torna da sola.
final class DismissedStore {
    private var entries: [String: Date]
    private let file: URL
    /// Dopo un mese l'annotazione non serve più a nessuno.
    private let maxAge: TimeInterval = 30 * 24 * 3600

    init(file: URL? = nil) {
        self.file = file ?? AppPaths.configDirectory.appendingPathComponent("dismissed.json")
        entries = [:]
        load()
    }

    var count: Int { entries.count }

    /// La sessione è nascosta se non è successo nulla dopo la rimozione.
    func isHidden(_ session: AgentSession) -> Bool {
        guard let dismissedAt = entries[session.id] else { return false }
        return session.updatedAt <= dismissedAt
    }

    func dismiss(_ session: AgentSession) {
        // Un istante avanti: copre l'evento che ha generato l'ultimo aggiornamento.
        entries[session.id] = max(Date(), session.updatedAt.addingTimeInterval(0.001))
        save()
    }

    func restoreAll() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        save()
    }

    /// Toglie le annotazioni scadute e quelle di sessioni che non esistono più.
    func prune(knownIDs: Set<String>) {
        let cutoff = Date().addingTimeInterval(-maxAge)
        let cleaned = entries.filter { id, date in
            date > cutoff && knownIDs.contains(id)
        }
        guard cleaned.count != entries.count else { return }
        entries = cleaned
        save()
    }

    // MARK: - Persistenza

    private func load() {
        guard let data = try? Data(contentsOf: file),
              let raw = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        entries = raw.compactMapValues { millis in
            let date = Date(timeIntervalSince1970: millis / 1000)
            return date > cutoff ? date : nil
        }
    }

    private func save() {
        let raw = entries.mapValues { $0.timeIntervalSince1970 * 1000 }
        guard let data = try? JSONEncoder().encode(raw) else { return }
        try? FileManager.default.createDirectory(at: AppPaths.configDirectory, withIntermediateDirectories: true)
        try? data.write(to: file)
    }
}
