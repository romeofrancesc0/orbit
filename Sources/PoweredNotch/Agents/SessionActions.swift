import AppKit
import ServiceManagement

extension Notification.Name {
    /// `object` è l'id della sessione che l'utente ha aperto o segnato come vista.
    static let sessionSeen = Notification.Name("powerednotch.sessionSeen")
}

/// Azioni eseguibili su una sessione.
enum SessionActions {
    // MARK: - Apertura

    static func openInDefaultApp(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func openInTerminal(path: String) {
        let configuration = NSWorkspace.OpenConfiguration()
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: terminal, configuration: configuration)
    }

    static func openInEditor(path: String) {
        let url = URL(fileURLWithPath: path)
        let candidates = [
            "/Applications/Visual Studio Code.app",
            "/Applications/Cursor.app",
            "/Applications/Zed.app",
            "\(AppPaths.home.path)/Applications/Visual Studio Code.app"
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: URL(fileURLWithPath: candidate),
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Apre *quella* sessione: se il provider ha dato un deep link si va dritti
    /// nella chat giusta, altrimenti si ripiega sull'app che la ospita.
    static func focus(_ session: AgentSession) {
        markSeen(session)
        if let raw = session.openURL, let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
            return
        }
        focusHost(of: session)
    }

    /// L'utente ha visto la sessione: smette di chiamarlo finché non succede qualcosa di nuovo.
    static func markSeen(_ session: AgentSession) {
        NotificationCenter.default.post(name: .sessionSeen, object: session.id)
    }

    /// Porta in primo piano l'app che ospita la sessione.
    static func focusHost(of session: AgentSession) {
        let bundleID: String?
        switch session.host {
        case "Desktop":   bundleID = "com.anthropic.claudefordesktop"
        case "VS Code":   bundleID = "com.microsoft.VSCode"
        case "Terminale": bundleID = "com.apple.Terminal"
        case "Codex":     bundleID = "com.openai.codex"
        default:          bundleID = nil
        }
        guard let bundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else {
            if let path = session.path { openInTerminal(path: path) }
            return
        }
        app.activate(options: [.activateAllWindows])
    }

    // MARK: - Comandi

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Esegue un comando dichiarato da un provider, in background.
    static func run(command: String, session: AgentSession) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", command]
        if let path = session.path {
            process.currentDirectoryURL = URL(fileURLWithPath: path)
        }
        var environment = ProcessInfo.processInfo.environment
        environment["POWERED_NOTCH_PATH"] = session.path ?? ""
        environment["POWERED_NOTCH_SESSION"] = session.nativeID ?? session.id
        environment["POWERED_NOTCH_PROVIDER"] = session.providerID
        process.environment = environment
        try? process.run()
    }

    /// Apre una finestra di Terminale che esegue un comando, senza chiedere permessi
    /// di automazione: si appoggia a uno script `.command` usa e getta.
    static func runInTerminal(command: String, cwd: String?) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("powerednotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cleanupOldScripts(in: directory)

        let script = directory.appendingPathComponent("powerednotch-\(UUID().uuidString.prefix(8)).command")
        var body = "#!/bin/zsh\n"
        if let cwd { body += "cd \(quote(cwd)) || exit 1\n" }
        body += command + "\n"

        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch {
            NSSound.beep()
        }
    }

    /// Riprende una sessione di Claude Code in una nuova finestra di Terminale.
    static func resumeClaudeCode(session: AgentSession) {
        guard let sessionID = session.nativeID else { return }
        markSeen(session)
        let command = """
        if ! command -v claude >/dev/null 2>&1; then
          echo "Comando 'claude' non trovato nel PATH."; exec $SHELL -l
        fi
        claude --resume \(sessionID)
        """
        runInTerminal(command: command, cwd: session.path)
    }

    private static func cleanupOldScripts(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-3600)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Avvio automatico al login (funziona solo quando l'app gira come bundle).
enum LoginItem {
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Imposta lo stato voluto; non fa nulla se è già quello.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        guard isEnabled != enabled else { return true }
        return toggle()
    }

    @discardableResult
    static func toggle() -> Bool {
        guard isAvailable else { return false }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }
}
