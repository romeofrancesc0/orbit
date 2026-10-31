import Foundation

/// `AgentBar --dump` interroga i provider una volta sola e stampa il risultato:
/// serve a capire cosa vede davvero l'app senza aprire i pannelli.
enum Diagnostics {
    /// `AgentBar --selftest`: verifica le regole che non si vedono a occhio.
    static func selfTest() {
        var failures = 0
        func check(_ condition: Bool, _ what: String) {
            print((condition ? "  ok   " : "  FALLITO ") + what)
            if !condition { failures += 1 }
        }

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentbar-selftest-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        let now = Date()
        func session(updated: Date) -> AgentSession {
            AgentSession(
                id: "claude-code:test", providerID: "claude-code", providerName: "Test",
                title: "t", project: "p", status: .idle, updatedAt: updated
            )
        }

        print("── Sessioni nascoste")
        let store = DismissedStore(file: file)
        let original = session(updated: now)
        check(!store.isHidden(original), "prima della rimozione è visibile")

        store.dismiss(original)
        check(store.isHidden(original), "dopo la rimozione sparisce")
        check(store.isHidden(session(updated: now.addingTimeInterval(-60))), "resta nascosta se non succede nulla")
        check(!store.isHidden(session(updated: now.addingTimeInterval(30))), "ricompare se la chat riparte")

        let reloaded = DismissedStore(file: file)
        check(reloaded.isHidden(original), "la rimozione sopravvive al riavvio")
        check(!reloaded.isHidden(session(updated: now.addingTimeInterval(30))), "e la regola vale anche dopo il riavvio")

        reloaded.prune(knownIDs: [])
        check(reloaded.count == 0, "le sessioni sparite dal disco non lasciano tracce")

        reloaded.dismiss(original)
        reloaded.restoreAll()
        check(!reloaded.isHidden(original), "Ripristina rimette tutto")

        print(failures == 0 ? "\ntutto ok" : "\n\(failures) verifiche fallite")
    }

    static func dump() async {
        let store = ConfigStore()
        let config = store.current
        let providers = ProviderFactory.make(config.providers)

        print("config: \(AppPaths.configFile.path)")
        print("provider attivi: \(providers.map(\.id).joined(separator: ", "))\n")

        for provider in providers {
            let started = Date()
            let result = await provider.fetch(config: config)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)

            print("── \(provider.displayName) [\(provider.id)] — \(result.sessions.count) sessioni in \(elapsed)ms")
            if let error = result.error {
                print("   errore: \(error)")
            }
            for session in AgentSession.ordered(result.sessions) {
                let status = session.status.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
                let project = session.project.padding(toLength: 16, withPad: " ", startingAt: 0)
                let age = Format.elapsed(since: session.updatedAt) ?? "-"
                print("   \(status) \(project) \(age.padding(toLength: 7, withPad: " ", startingAt: 0)) \(session.title)")
                var meta: [String] = []
                if let activity = session.activity { meta.append(activity) }
                if let branch = session.branch { meta.append("branch \(branch)") }
                if let model = session.model { meta.append(model) }
                if let tokens = session.tokensUsed { meta.append("\(Format.tokens(tokens)) token") }
                if let pid = session.pid { meta.append("pid \(pid)") }
                if let url = session.openURL { meta.append(url) }
                if !meta.isEmpty {
                    print("              └ " + meta.joined(separator: " · "))
                }
            }
            print("")
        }
    }
}
