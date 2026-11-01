import AppKit
import SwiftUI

/// Tutto ciò che riguarda i coding agent: quali seguire e come farli comparire.
struct AgentsSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var sessions: SessionStore
    @State private var hooksInstalled = ClaudeHooks.isInstalled
    @State private var hookMessage: String?
    @State private var addingProvider = false

    private var layout: LayoutConfig { settings.config.layout }

    /// Gli elementi con cui gli agenti compaiono nella notch chiusa.
    private var showsInClosedNotch: Binding<Bool> {
        Binding(
            get: { (layout.closedLeading + layout.closedTrailing).contains { $0.hasPrefix("agents.") } },
            set: { show in
                settings.update { config in
                    if show {
                        if !config.layout.closedLeading.contains("agents.status") { config.layout.closedLeading.append("agents.status") }
                        if !config.layout.closedTrailing.contains("agents.dots") { config.layout.closedTrailing.insert("agents.dots", at: 0) }
                    } else {
                        config.layout.closedLeading.removeAll { $0.hasPrefix("agents.") }
                        config.layout.closedTrailing.removeAll { $0.hasPrefix("agents.") }
                    }
                }
            }
        )
    }

    /// Gli agenti come prima cosa che si vede aprendo la notch.
    private var isDefaultPage: Binding<Bool> {
        Binding(
            get: {
                guard layout.startMode == .specific, let id = layout.startPageID else { return false }
                return layout.pages.first { $0.id == id }?.containsWidget("agents") == true
            },
            set: { enabled in
                settings.update { config in
                    if enabled {
                        // Una pagina tutta sua, se non esiste già.
                        var page = config.layout.pages.first { $0.widgets.count == 1 && $0.containsWidget("agents") }
                        if page == nil {
                            let created = PageConfig(id: "agents", title: "Agenti", symbol: "sparkles", widgets: [WidgetPlacement(kind: "agents")], height: 300)
                            config.layout.pages.removeAll { $0.id == created.id }
                            config.layout.pages.append(created)
                            page = created
                        }
                        config.layout.startMode = .specific
                        config.layout.startPageID = page?.id
                    } else {
                        config.layout.startMode = .smart
                        config.layout.startPageID = nil
                    }
                }
            }
        )
    }

    var body: some View {
        SettingsForm(section: .agents, subtitle: "Le sessioni dei tuoi coding agent, sempre sotto gli occhi. Funziona senza configurare nulla.") {
            Section("Nella notch") {
                Toggle("Mostra le sessioni nella notch chiusa", isOn: showsInClosedNotch)
                Toggle("Apri la notch direttamente sugli agenti", isOn: isDefaultPage)
                Toggle("Alone quando un agente ti aspetta", isOn: settings.binding(\.appearance.attentionGlow))
                Text("Per scegliere esattamente quali elementi mostrare e dove, vai su Layout.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Agenti collegati") {
                ForEach(settings.config.agents.providers) { provider in
                    ProviderRow(provider: provider)
                }
                Button("Aggiungi un altro agent…") { addingProvider = true }
            }

            Section("Permessi in tempo reale (Claude Code)") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hook di Claude Code")
                        Text("Senza hook una richiesta di permesso appare come \"in esecuzione\": il transcript non la registra finché non rispondi. Con gli hook la notch ti chiama subito.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    StatusBadge(text: hooksInstalled ? "Installati" : "Non installati", color: hooksInstalled ? .green : .secondary)
                    Button(hooksInstalled ? "Rimuovi" : "Installa") { toggleHooks() }
                }
                if let hookMessage {
                    Text(hookMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Elenco") {
                Toggle("Mostra anche le sessioni chiuse di recente", isOn: settings.binding(\.agents.showRecent))
                if settings.config.agents.showRecent {
                    ValueSlider(title: "Da quante ore", value: settings.binding(\.agents.recentWindowHours), range: 1...72, format: { "\(Int($0)) h" })
                }
                ValueSlider(title: "In pausa dopo", value: settings.binding(\.agents.idleAfterMinutes), range: 1...30, format: { "\(Int($0)) min" })
                HStack {
                    Text("Sessioni nascoste")
                    Spacer()
                    Text("\(sessions.hiddenCount)").foregroundStyle(.secondary)
                    Button("Rimettile in elenco") { sessions.restoreHidden() }
                        .disabled(sessions.hiddenCount == 0)
                }
            }
        }
        .sheet(isPresented: $addingProvider) {
            AddProviderSheet()
        }
    }

    private func toggleHooks() {
        do {
            if hooksInstalled {
                try ClaudeHooks.remove()
                hookMessage = "Hook rimossi. Riavvia le sessioni di Claude Code per applicare la modifica."
            } else {
                try ClaudeHooks.install()
                hookMessage = "Hook installati. Valgono dalle prossime sessioni di Claude Code. Copia di sicurezza: ~/.claude/settings.json.powered-notch-backup"
            }
        } catch {
            hookMessage = "Non è stato possibile modificare ~/.claude/settings.json: \(error.localizedDescription)"
        }
        hooksInstalled = ClaudeHooks.isInstalled
    }
}

private struct ProviderRow: View {
    let provider: ProviderConfig

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var sessions: SessionStore

    private var count: Int {
        sessions.sessions.filter { $0.providerID == provider.id }.count
    }

    private var isBuiltIn: Bool {
        ["claude-code", "codex", "inbox"].contains(provider.id)
    }

    private var detail: String {
        if let error = sessions.providerErrors[provider.id] { return error }
        switch provider.type {
        case "claude-code", "codex":
            switch count {
            case 0:  return "Nessuna sessione adesso"
            case 1:  return "1 sessione"
            default: return "\(count) sessioni"
            }
        case "inbox":
            return provider.path ?? "~/.powered-notch/inbox"
        default:
            return provider.command ?? ""
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ColorPicker("", selection: accentBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.name ?? provider.id)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(sessions.providerErrors[provider.id] != nil ? .red : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if !isBuiltIn {
                Button {
                    settings.update { $0.agents.providers.removeAll { $0.id == provider.id } }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Rimuovi questo agent")
            }
            Toggle("", isOn: settings.binding(in: \.agents.providers, id: provider.id, \.enabled, default: false))
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private var accentBinding: Binding<Color> {
        Binding(
            get: { Color(hexString: provider.accent) ?? .gray },
            set: { color in
                guard let hex = color.hexString else { return }
                settings.update { config in
                    guard let index = config.agents.providers.firstIndex(where: { $0.id == provider.id }) else { return }
                    config.agents.providers[index].accent = hex
                }
            }
        )
    }
}

/// Qualunque agent può comparire nella notch: basta un comando o una cartella.
private struct AddProviderSheet: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type = "command"
    @State private var command = ""
    @State private var path = "~/.powered-notch/inbox-mioagent"
    @State private var accent = Color.purple

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Aggiungi un agent").font(.title3.weight(.semibold))

            Form {
                TextField("Nome", text: $name, prompt: Text("Mio Agent"))
                Picker("Come parla con Powered Notch", selection: $type) {
                    Text("Un comando che stampa JSON").tag("command")
                    Text("Una cartella di file JSON").tag("inbox")
                }
                if type == "command" {
                    TextField("Comando", text: $command, prompt: Text("~/bin/mio-agent --json"))
                        .font(.system(.body, design: .monospaced))
                } else {
                    TextField("Cartella", text: $path)
                        .font(.system(.body, design: .monospaced))
                }
                ColorPicker("Colore", selection: $accent, supportsOpacity: false)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            Text("Lo schema delle sessioni è nel README. Solo il campo id è obbligatorio.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                Button("Aggiungi") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || (type == "command" && command.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func add() {
        let provider = ProviderConfig(
            id: "\(type)-\(UUID().uuidString.prefix(8))",
            type: type,
            name: name,
            enabled: true,
            accent: accent.hexString,
            command: type == "command" ? command : nil,
            path: type == "inbox" ? path : nil
        )
        settings.update { $0.agents.providers.append(provider) }
        dismiss()
    }
}

// MARK: - Hook di Claude Code

/// Installa e rimuove gli hook in `~/.claude/settings.json`. La configurazione viene
/// fusa e non riscritta: gli hook di altri strumenti restano dove sono, e prima di
/// ogni modifica se ne salva una copia. Parte solo quando l'utente lo chiede.
enum ClaudeHooks {
    private static var settingsFile: URL { AppPaths.home.appendingPathComponent(".claude/settings.json") }
    private static var script: URL { AppPaths.hooksDirectory.appendingPathComponent("powered_notch_hook.py") }
    private static let raising = ["PermissionRequest", "PermissionDenied", "Notification"]
    private static let clearing = ["PostToolUse", "Stop", "UserPromptSubmit", "SessionEnd"]

    enum HookError: LocalizedError {
        case missingScript
        case unreadableSettings

        var errorDescription: String? {
            switch self {
            case .missingScript:      "script dell'hook non trovato nell'app"
            case .unreadableSettings: "il file non è un JSON valido, non l'ho toccato"
            }
        }
    }

    static var isInstalled: Bool { isInstalled(in: settingsFile) }

    static func isInstalled(in file: URL) -> Bool {
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8)
        else { return false }
        return text.contains("powered_notch_hook.py")
    }

    static func install() throws {
        guard let bundled = Bundle.main.url(forResource: "powered_notch_hook", withExtension: "py") else {
            throw HookError.missingScript
        }
        let fm = FileManager.default
        try fm.createDirectory(at: AppPaths.hooksDirectory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: script.path) { try fm.removeItem(at: script) }
        try fm.copyItem(at: bundled, to: script)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try rewrite(file: settingsFile, script: script.path, installing: true)
    }

    static func remove() throws {
        try rewrite(file: settingsFile, script: script.path, installing: false)
        try? FileManager.default.removeItem(at: script)
        try? FileManager.default.removeItem(at: AppPaths.hintsDirectory)
    }

    static func rewrite(file: URL, script: String, installing: Bool) throws {
        let fm = FileManager.default
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: file) {
            guard let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw HookError.unreadableSettings
            }
            settings = parsed
            let backup = file.appendingPathExtension("powerednotch-backup")
            if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
            try fm.copyItem(at: file, to: backup)
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in raising + clearing {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.removeAll(where: isOurs)
            if installing {
                entries.append([
                    "hooks": [[
                        "type": "command",
                        "command": "/usr/bin/env python3 \"\(script)\" \(event)",
                        "async": true,
                        "timeout": 5
                    ] as [String: Any]]
                ])
            }
            if entries.isEmpty {
                hooks[event] = nil
            } else {
                hooks[event] = entries
            }
        }

        if hooks.isEmpty {
            settings["hooks"] = nil
        } else {
            settings["hooks"] = hooks
        }

        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: file, options: .atomic)
    }

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        let inner = entry["hooks"] as? [[String: Any]] ?? []
        return inner.contains { ($0["command"] as? String)?.contains("powered_notch_hook.py") == true }
    }
}
