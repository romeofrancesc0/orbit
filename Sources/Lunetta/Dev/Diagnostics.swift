import CoreGraphics
import Foundation
import SwiftUI

/// `Lunetta --dump` interroga i provider una volta sola e stampa il risultato:
/// serve a capire cosa vede davvero l'app senza aprire i pannelli.
enum Diagnostics {
    /// `Lunetta --selftest`: verifica le regole che non si vedono a occhio.
    static func selfTest() {
        var failures = 0
        func check(_ condition: Bool, _ what: String) {
            print((condition ? "  ok   " : "  FALLITO ") + what)
            if !condition { failures += 1 }
        }

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("lunetta-selftest-\(UUID().uuidString).json")
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

        print("── Configurazione")
        let partial = #"{"appearance":{"openWidth":900},"behavior":{"hoverDelay":0.5},"chiaveSconosciuta":true}"#
        let merged = SettingsStore.decode(Data(partial.utf8))
        check(merged?.appearance.openWidth == 900, "un valore scritto nel file viene letto")
        check(merged?.appearance.openHeight == AppearanceConfig().openHeight, "una chiave mancante prende il default")
        check(merged?.behavior.hoverDelay == 0.5, "vale anche nelle altre sezioni")

        let broken = #"{"appearance":{"surface":"inesistente"},"behavior":{"hoverDelay":0.9}}"#
        let tolerant = SettingsStore.decode(Data(broken.utf8))
        check(tolerant?.appearance.surface == .solid, "una sezione illeggibile ricade sul default")
        check(tolerant?.behavior.hoverDelay == 0.9, "senza trascinare giù le altre")
        check(SettingsStore.decode(Data("non è json".utf8)) == nil, "un file rotto non viene scambiato per una configurazione")

        if let encoded = SettingsStore.encode(LunettaConfig()), let decoded = SettingsStore.decode(encoded) {
            check(decoded == LunettaConfig(), "scrittura e rilettura non cambiano nulla")
        } else {
            check(false, "scrittura e rilettura non cambiano nulla")
        }

        print("── Layout")
        let defaults = LayoutConfig()
        let catalogue = Set(ModuleCatalog.widgets.map(\.kind))
        check(defaults.pages.flatMap(\.widgets).allSatisfy { catalogue.contains($0.kind) }, "le pagine predefinite usano widget esistenti")
        let compacts = Set(ModuleCatalog.compacts.map(\.id))
        check((defaults.closedLeading + defaults.closedTrailing + defaults.headerTrailing).allSatisfy(compacts.contains), "gli elementi predefiniti della notch chiusa esistono")
        check(defaults.closedLeading.contains("agents.status"), "gli agenti compaiono nella notch chiusa di serie")
        check(defaults.pages.contains { $0.containsWidget("agents") }, "gli agenti hanno una pagina di serie")
        for profile in ProfileConfig.builtIn {
            let widgetsOK = profile.layout.pages.flatMap(\.widgets).allSatisfy { catalogue.contains($0.kind) }
            let compactsOK = (profile.layout.closedLeading + profile.layout.closedTrailing + profile.layout.headerTrailing).allSatisfy(compacts.contains)
            check(widgetsOK && compactsOK, "il profilo \(profile.name) usa solo elementi esistenti")
        }

        print("── Migrazione")
        let migrated = LegacyMigration.merged(legacy: [
            ProviderConfig(id: "claude-code", type: "claude-code", enabled: false),
            ProviderConfig(id: "inbox", type: "inbox", path: "~/.agentbar/inbox")
        ])
        check(migrated.first { $0.id == "claude-code" }?.enabled == false, "un provider spento da AgentBar resta spento")
        check(migrated.first { $0.id == "inbox" }?.path == "~/.lunetta/inbox", "la inbox passa alla nuova cartella")
        check(migrated.contains { $0.type == "codex" }, "i provider nuovi vengono aggiunti")

        print("── Transcript")
        let transcript = FileManager.default.temporaryDirectory.appendingPathComponent("lunetta-selftest-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: transcript) }
        func line(_ type: String, stop: String?, text: String) -> String {
            let reason = stop.map { "\"\($0)\"" } ?? "null"
            return "{\"type\":\"\(type)\",\"timestamp\":\"2026-10-31T10:00:00Z\",\"message\":{\"stop_reason\":\(reason),\"content\":[{\"type\":\"text\",\"text\":\"\(text)\"}]}}\n"
        }
        try? line("assistant", stop: nil, text: "lavoro").write(to: transcript, atomically: true, encoding: .utf8)
        var cursor = TranscriptScanner.start(url: transcript)
        check(cursor.scan.status == .working, "una risposta in corso vuol dire al lavoro")
        if let handle = try? FileHandle(forWritingTo: transcript) {
            _ = try? handle.seekToEnd()
            let finished = line("assistant", stop: "end_turn", text: "fatto")
            // La riga arriva in due pezzi, come quando si legge a metà di una scrittura.
            let middle = finished.index(finished.startIndex, offsetBy: 40)
            handle.write(Data(finished[..<middle].utf8))
            cursor = TranscriptScanner.advance(cursor, url: transcript)
            check(cursor.scan.status == .working, "una riga a metà non viene letta")
            handle.write(Data(finished[middle...].utf8))
            try? handle.close()
            cursor = TranscriptScanner.advance(cursor, url: transcript)
            check(cursor.scan.status == .attention, "completata la riga, il turno risulta finito")
        }
        try? line("assistant", stop: nil, text: "x").write(to: transcript, atomically: true, encoding: .utf8)
        cursor = TranscriptScanner.advance(cursor, url: transcript)
        check(cursor.scan.status == .working, "un file riscritto si rilegge da capo")

        print("── Codex")
        check(
            CodexProvider.threadID(fromFileName: "rollout-2026-10-22T21-09-54-01a1653c-0399-7123-9e2c-562e6dbc8bb1") == "01a1653c-0399-7123-9e2c-562e6dbc8bb1",
            "l'id del thread si ricava dal nome del file"
        )
        var codex = CodexScan()
        CodexScanner.absorb(["type": "event_msg", "payload": ["type": "task_started"]], into: &codex)
        check(codex.status == .working, "task_started vuol dire al lavoro")
        CodexScanner.absorb(["type": "event_msg", "payload": ["type": "exec_approval_request"]], into: &codex)
        check(codex.status == .blocked, "una richiesta di approvazione blocca la sessione")
        CodexScanner.absorb(["type": "event_msg", "payload": ["type": "task_complete", "last_agent_message": "fatto"]], into: &codex)
        check(codex.status == .attention && codex.activity == "fatto", "task_complete passa la palla all'umano")

        print("── Widget da script")
        let json = CustomWidgetStore.parse(Data(#"{"text":"22°","symbol":"sun.max","progress":0.5}"#.utf8))
        check(json.text == "22°" && json.progress == 0.5, "l'output JSON viene letto")
        let plain = CustomWidgetStore.parse(Data("uno\ndue\ntre\n".utf8))
        check(plain.text == "uno" && plain.rows?.count == 2, "il testo semplice diventa valore e righe")

        print("── Forma")
        let shape = NotchShape(earRadius: 6, bottomRadius: 11).path(in: CGRect(x: 0, y: 0, width: 200, height: 32))
        check(shape.contains(CGPoint(x: 100, y: 16)), "il centro è dentro")
        check(!shape.contains(CGPoint(x: 1, y: 20)), "fuori dalle orecchie è vuoto")
        check(!NotchShape(earRadius: 500, bottomRadius: 500).path(in: CGRect(x: 0, y: 0, width: 40, height: 10)).isEmpty, "raggi eccessivi non rompono la forma")

        print(failures == 0 ? "\ntutto ok" : "\n\(failures) verifiche fallite")
    }

    /// Legge volume e luminosità e riscrive lo stesso valore: prova le API senza cambiare nulla.
    @MainActor
    static func probeControls() {
        let volume = VolumeController()
        print("volume: \(volume.level), muto: \(volume.isMuted)")
        volume.set(level: volume.level)
        print("  dopo la riscrittura: \(volume.level)")

        let brightness = BrightnessController()
        print("luminosità: \(brightness.screenLevel.map { "\($0)" } ?? "non disponibile")")
        print("  dopo la riscrittura: \(brightness.changeScreen(by: 0).map { "\($0)" } ?? "non riuscita")")
        print("tastiera: \(brightness.keyboardLevel.map { "\($0)" } ?? "non disponibile")")
        print("accessibilità concessa: \(MediaKeyTap.isTrusted)")
        print("tutto schermo: \(FullscreenDetector.isFullscreen(displayID: CGMainDisplayID()))")
    }

    static func dump() async {
        let saved = (try? Data(contentsOf: AppPaths.configFile)).flatMap(SettingsStore.decode)
        let config = saved?.agents ?? AgentsConfig()
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
