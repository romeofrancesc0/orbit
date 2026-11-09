import Combine
import CoreGraphics
import Foundation
import SwiftUI

/// `Orbit --dump` interroga i provider una volta sola e stampa il risultato:
/// serve a capire cosa vede davvero l'app senza aprire i pannelli.
enum Diagnostics {
    /// `Orbit --selftest`: verifica le regole che non si vedono a occhio.
    @MainActor
    static func selfTest() {
        var failures = 0
        func check(_ condition: Bool, _ what: String) {
            print((condition ? "  ok   " : "  FALLITO ") + what)
            if !condition { failures += 1 }
        }

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbit-selftest-\(UUID().uuidString).json")
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

        if let encoded = SettingsStore.encode(OrbitConfig()), let decoded = SettingsStore.decode(encoded) {
            check(decoded == OrbitConfig(), "scrittura e rilettura non cambiano nulla")
        } else {
            check(false, "scrittura e rilettura non cambiano nulla")
        }

        print("── Avvisi")
        let old = SettingsStore.decode(Data(#"{"schemaVersion":1,"peeks":{"charger":true,"trackChange":true,"agentAttention":true,"agentBlocked":true,"duration":2}}"#.utf8))
        check(old?.peeks.charger == false && old?.peeks.trackChange == false && old?.peeks.agentAttention == false, "una configurazione vecchia riceve gli avvisi più discreti")
        check(old?.peeks.agentBlocked == true && old?.peeks.duration == 2, "senza toccare il resto")
        check(old?.schemaVersion == 2, "e si segna come aggiornata")
        let current = SettingsStore.decode(Data(#"{"schemaVersion":2,"peeks":{"charger":true}}"#.utf8))
        check(current?.peeks.charger == true, "una scelta fatta dopo l'aggiornamento non viene toccata")
        check(OrbitConfig().peeks.agentAttention == false && OrbitConfig().peeks.charger == false, "di serie scende solo ciò che richiede te")
        check(MediaService.isMusicApp("com.spotify.client") && !MediaService.isMusicApp("com.apple.Safari") && !MediaService.isMusicApp(nil), "un browser non è un'app di musica")

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
        check(migrated.first { $0.id == "inbox" }?.path == "~/.orbit/inbox", "la inbox passa alla nuova cartella")
        check(migrated.contains { $0.type == "codex" }, "i provider nuovi vengono aggiunti")

        // Da Powered Notch a Orbit: le cartelle si spostano, al vecchio posto resta un collegamento.
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-selftest-\(UUID().uuidString)")
        let oldDir = sandbox.appendingPathComponent(".powered-notch"), newDir = sandbox.appendingPathComponent(".orbit")
        try? FileManager.default.createDirectory(at: oldDir.appendingPathComponent("hooks"), withIntermediateDirectories: true)
        try? "x".write(to: oldDir.appendingPathComponent("hooks/powered_notch_hook.py"), atomically: true, encoding: .utf8)
        check(AppPaths.moveLeavingLink(from: oldDir, to: newDir), "la cartella di Powered Notch passa sotto il nome nuovo")
        check(FileManager.default.fileExists(atPath: newDir.appendingPathComponent("hooks/powered_notch_hook.py").path), "con i suoi file")
        check(FileManager.default.fileExists(atPath: oldDir.appendingPathComponent("hooks/powered_notch_hook.py").path), "e il vecchio percorso continua a funzionare")
        check(!AppPaths.moveLeavingLink(from: oldDir, to: newDir), "una seconda volta non cambia nulla")
        try? FileManager.default.removeItem(at: sandbox)
        var legacyConfig = OrbitConfig()
        legacyConfig.agents.providers = [ProviderConfig(id: "inbox", type: "inbox", path: "~/.powered-notch/inbox")]
        check(legacyConfig.upgraded().agents.providers.first?.path == "~/.orbit/inbox", "la inbox di Powered Notch punta alla cartella nuova")

        print("── Transcript")
        let transcript = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-selftest-\(UUID().uuidString).jsonl")
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
            check(cursor.scan.status == .done, "completata la riga, il turno risulta finito (senza chiamare)")
        }
        try? line("assistant", stop: "end_turn", text: "Vuoi che faccia il push?").write(to: transcript, atomically: true, encoding: .utf8)
        cursor = TranscriptScanner.advance(cursor, url: transcript)
        check(cursor.scan.status == .attention, "una domanda in fondo al turno chiama l'utente")
        try? """
        {"type":"assistant","timestamp":"2026-10-31T10:01:00Z","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[{"question":"Quale database?"}]}}]}}

        """.write(to: transcript, atomically: true, encoding: .utf8)
        cursor = TranscriptScanner.start(url: transcript)
        check(cursor.scan.status == .attention && cursor.scan.activity == "Quale database?", "AskUserQuestion aspetta una risposta")
        check(TranscriptScanner.endsWithQuestion("Procedo con **il push?**"), "il markdown in coda non nasconde la domanda")
        check(!TranscriptScanner.endsWithQuestion("Se vuoi, faccio il push."), "un'offerta senza domanda non chiama")
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
        check(codex.status == .done && codex.activity == "fatto", "task_complete senza domanda chiude il turno")

        print("── Widget da script")
        let json = CustomWidgetStore.parse(Data(#"{"text":"22°","symbol":"sun.max","progress":0.5}"#.utf8))
        check(json.text == "22°" && json.progress == 0.5, "l'output JSON viene letto")
        let plain = CustomWidgetStore.parse(Data("uno\ndue\ntre\n".utf8))
        check(plain.text == "uno" && plain.rows?.count == 2, "il testo semplice diventa valore e righe")

        print("── Hook di Claude Code")
        let hooksFile = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-selftest-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: hooksFile)
            try? FileManager.default.removeItem(at: hooksFile.appendingPathExtension("orbit-backup"))
        }
        let existingSettings = #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"altro-strumento"}]}]},"statusLine":{"type":"command"}}"#
        try? existingSettings.write(to: hooksFile, atomically: true, encoding: .utf8)
        func readSettings() -> [String: Any] {
            (try? JSONSerialization.jsonObject(with: Data(contentsOf: hooksFile))) as? [String: Any] ?? [:]
        }
        func stopCommands() -> [String] {
            let entries = (readSettings()["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]] ?? []
            return entries.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        }
        do {
            try ClaudeHooks.rewrite(file: hooksFile, script: "/tmp/orbit_hook.py", installing: true)
            check(ClaudeHooks.isInstalled(in: hooksFile), "l'installazione aggiunge gli hook")
            check(stopCommands().contains("altro-strumento"), "gli hook di altri strumenti restano")
            check(readSettings()["model"] as? String == "opus", "le altre impostazioni restano")
            check(FileManager.default.fileExists(atPath: hooksFile.appendingPathExtension("orbit-backup").path), "prima di scrivere si fa una copia")
            try ClaudeHooks.rewrite(file: hooksFile, script: "/tmp/orbit_hook.py", installing: true)
            check(stopCommands().filter { $0.contains("orbit_hook.py") }.count == 1, "reinstallare non crea doppioni")
            try ClaudeHooks.rewrite(file: hooksFile, script: "/tmp/orbit_hook.py", installing: false)
            check(!ClaudeHooks.isInstalled(in: hooksFile), "la rimozione toglie gli hook")
            check(stopCommands() == ["altro-strumento"], "e lascia solo quelli degli altri")
        } catch {
            check(false, "le modifiche al file riescono: \(error)")
        }
        // Hooks installed by Powered Notch point to powered_notch_hook.py: reinstalling replaces them.
        let legacyHooks = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/usr/bin/env python3 \"/Users/x/.powered-notch/hooks/powered_notch_hook.py\" Stop"}]}]}}"#
        try? legacyHooks.write(to: hooksFile, atomically: true, encoding: .utf8)
        check(ClaudeHooks.isInstalled(in: hooksFile), "gli hook di Powered Notch si riconoscono ancora")
        do {
            try ClaudeHooks.rewrite(file: hooksFile, script: "/tmp/orbit_hook.py", installing: true)
            check(stopCommands().count == 1 && stopCommands()[0].contains("orbit_hook.py"), "e reinstallando vengono sostituiti, non raddoppiati")
        } catch {
            check(false, "gli hook vecchi si sostituiscono: \(error)")
        }
        try? "non è json".write(to: hooksFile, atomically: true, encoding: .utf8)
        check((try? ClaudeHooks.rewrite(file: hooksFile, script: "/tmp/x", installing: true)) == nil, "un file rotto non viene sovrascritto")
        check((try? String(contentsOf: hooksFile, encoding: .utf8)) == "non è json", "e resta com'era")

        print("── Scorciatoie")
        check(HotKeyCenter.describe(keyCode: 122, modifiers: 0x1000) == "⌃F1", "i tasti funzione hanno un nome")
        check(HotKeyCenter.describe(keyCode: 49, modifiers: 0x0100) == "⌘Spazio", "anche i tasti speciali")
        check(!HotKeyCenter.describe(keyCode: 45, modifiers: 0x1800).isEmpty, "e le lettere, secondo la tastiera in uso")
        for binding in HotkeyBinding.defaults {
            if let code = binding.keyCode {
                check(!HotKeyCenter.describe(keyCode: code, modifiers: binding.modifiers).isEmpty, "\(binding.action.label) si può descrivere")
            }
        }

        print("── Forma")
        let shape = NotchShape(earRadius: 6, bottomRadius: 11).path(in: CGRect(x: 0, y: 0, width: 200, height: 32))
        check(shape.contains(CGPoint(x: 100, y: 16)), "il centro è dentro")
        check(!shape.contains(CGPoint(x: 1, y: 20)), "fuori dalle orecchie è vuoto")
        check(!NotchShape(earRadius: 500, bottomRadius: 500).path(in: CGRect(x: 0, y: 0, width: 40, height: 10)).isEmpty, "raggi eccessivi non rompono la forma")

        print("── Widget nella larghezza della notch")
        var wide = AppearanceConfig()
        wide.openWidth = 820
        var narrow = AppearanceConfig()
        narrow.openWidth = 520
        let home = PageConfig.defaults[0]
        check(PageLayout.hiddenWidgets(in: home, appearance: wide).isEmpty, "a 820 punti la pagina di serie entra tutta")
        check(PageLayout.hiddenWidgets(in: home, appearance: narrow).map(\.kind) == ["calendar"], "a 520 punti resta fuori l'ultimo widget, non si accavalla")
        let crowded = ["agents", "media", "calendar", "clock"].map { WidgetPlacement(kind: $0) }
        let columns = PageLayout.columns(of: crowded)
        let widths = PageLayout.widths(for: columns, width: PageLayout.contentWidth(narrow), spacing: 8)
        check(zip(columns, widths).allSatisfy { $1 + 0.5 >= PageLayout.minimumWidth(of: $0[0].kind) }, "nessuna colonna sotto il suo minimo")
        check(widths.reduce(0, +) + 8 * CGFloat(widths.count - 1) <= PageLayout.contentWidth(narrow) + 0.5, "le colonne non sforano la notch")
        check(!PageLayout.canAdd("clock", to: Array(crowded.prefix(2)) + [WidgetPlacement(kind: "calendar")], appearance: narrow), "a notch stretta non si aggiunge un widget che non entra")
        check(PageLayout.canAdd("clock", to: [WidgetPlacement(kind: "media")], appearance: narrow), "se c'è posto si aggiunge")

        print("── Testi a tempo")
        let lrc = """
        [ar: Someone]
        [offset:+500]
        [00:12.00]First line
        [00:15.50][01:02.25]Chorus
        [00:20.00]
        [00:21]
        [00:24.10]After the break
        [00:30.00]
        """
        let parsed = Lyrics.parseLRC(lrc)
        check(parsed != nil, "un LRC si legge")
        if let parsed {
            check(parsed.lines.first?.isInterlude == true, "un'introduzione lunga diventa una pausa")
            check(parsed.lines.filter(\.isInterlude).count == 3, "le pause doppie si fondono")
            check(parsed.lines.filter { $0.text == "Chorus" }.count == 2, "più istanti sulla stessa riga")
            check(abs((parsed.lines.first { $0.text == "First line" }?.time ?? 0) - 11.5) < 0.001, "l'offset sposta tutto in anticipo")
            check(parsed.lines.map(\.time) == parsed.lines.map(\.time).sorted(), "le righe sono in ordine")
            check(parsed.index(at: 0) == 0 && parsed.index(at: 11.4) == 1, "la riga giusta a ogni istante")
            check(parsed.index(at: 70) == parsed.lines.count - 1, "dopo l'ultima resta l'ultima")
        }
        let trailing = Lyrics.parseLRC("[00:01.00]Uno\n[00:02.00]\n[00:03.00]")
        check(trailing?.lines.count == 1, "le pause in fondo si tolgono")
        check(Lyrics.parseLRC("solo testo, senza tempi") == nil, "un testo senza tempi non è un LRC")
        check(Lyrics.plain("una\ndue")?.isSynced == false, "il testo semplice si legge senza tempi")

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

        // Solo quantità: un controllo di funzionamento non deve stampare i tuoi eventi.
        let calendar = CalendarService()
        calendar.start()
        print("calendario: \(calendar.eventsAccess), promemoria: \(calendar.remindersAccess)")
        print("  calendari: \(calendar.sources.count), eventi di oggi: \(calendar.events.count), prossimi: \(calendar.upcoming.count)")
        calendar.stop()
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

    /// `Orbit --demo --preview-window=lockscreen|onboarding|settings`: apre l'anteprima in una finestra
    /// qualunque, senza notch e senza badare a un'altra copia di Orbit già aperta.
    /// Con `--demo` non si salva nulla.
    @MainActor
    static func previewWindow(_ kind: String) {
        let services = AppServices.shared
        let content: AnyView
        let size: NSSize
        switch kind {
        case "settings":
            // Si apre sulla pagina della schermata di blocco.
            let navigation = SettingsNavigation()
            navigation.selection = .lockScreen
            content = AnyView(SettingsRoot(navigation: navigation, services: services).orbitEnvironment(services))
            size = NSSize(width: 1020, height: 760)
        case "onboarding":
            // La finestra vera della guida, non una copia: si prova quella che vedrà chi installa.
            OnboardingWindowController.shared.show(services: services)
            return
        default:
            content = AnyView(LockScreenStage(maxWidth: 1100).orbitEnvironment(services))
            size = NSSize(width: 1100, height: 1100 * 982 / 1512)
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Orbit preview"
        window.contentViewController = NSHostingController(rootView: content)
        window.setContentSize(size)
        window.center()
        window.isReleasedWhenClosed = false
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindowRef = window
    }

    @MainActor private static var previewWindowRef: NSWindow?

    /// `Orbit --probe-lyrics`: cosa vede il ponte in riproduzione e che testo trova per quel brano.
    @MainActor
    static func probeLyrics() {
        let media = MediaService()
        let lyrics = LyricsService()
        media.start()
        var printed = false
        var cancellables: Set<AnyCancellable> = []
        lyrics.$status.dropFirst().sink { status in
            switch status {
            case .loading: print("cerco il testo…")
            case .loaded(let found): print("testo trovato: \(found.lines.count) righe, a tempo: \(found.isSynced)"); found.lines.prefix(3).forEach { print("   [\(Format.playback($0.time))] \($0.text.isEmpty ? "•••" : $0.text)") }; printed = true
            case .instrumental: print("brano strumentale"); printed = true
            case .unavailable: print("testo non disponibile"); printed = true
            case .idle: print("nessuna ricerca"); printed = true
            }
        }.store(in: &cancellables)
        // `--probe-lyrics=Titolo|Artista|Album|Durata`: prova un brano preciso invece di quello in riproduzione.
        let fixed: NowPlaying? = CommandLine.arguments.first { $0.hasPrefix("--probe-lyrics=") }.map { argument in
            let parts = argument.dropFirst(15).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            var track = DemoData.track
            track.title = parts.first ?? ""
            track.artist = parts.count > 1 ? parts[1] : ""
            track.album = parts.count > 2 ? parts[2] : ""
            track.duration = parts.count > 3 ? Double(parts[3]) ?? 0 : 0
            return track
        }
        let source: AnyPublisher<NowPlaying, Never> = fixed.map { Just($0).eraseToAnyPublisher() }
            ?? media.$nowPlaying.compactMap { $0 }.eraseToAnyPublisher()
        source.first().sink { track in
            print("in riproduzione: \(track.title) — \(track.artist) — \(track.album) (\(Int(track.duration)) s)")
            print("app: \(track.bundleID ?? "-") genitore: \(track.parentBundleID ?? "-") musica: \(MediaService.isMusicApp(track.sourceBundleID))")
            lyrics.load(for: track)
        }.store(in: &cancellables)

        let deadline = Date().addingTimeInterval(15)
        while !printed, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        if fixed == nil, media.nowPlaying == nil { print("niente in riproduzione (o il ponte non risponde: \(media.bridgeError ?? "-"))") }
        media.stop()
        _ = cancellables
    }
}
