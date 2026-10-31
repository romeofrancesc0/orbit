import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Musica

struct MusicSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var media: MediaService

    var body: some View {
        SettingsForm(section: .music, subtitle: "Funziona con qualunque app che riproduce: Musica, Spotify, Safari, YouTube, e tutte le altre.") {
            Section("In riproduzione") {
                if let track = media.nowPlaying {
                    HStack(spacing: 10) {
                        ArtworkThumbnail(image: media.artwork, size: 40, radius: 8, showsPlaceholder: true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.title).lineLimit(1)
                            Text(track.appName ?? track.sourceBundleID ?? "")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(media.bridgeError ?? "Niente in riproduzione")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Lettore") {
                Toggle("Mostra casuale e ripetizione", isOn: settings.binding(\.media.showShuffleRepeat))
                Toggle("Colora la notch con la copertina", isOn: settings.binding(\.media.tintWithArtwork))
                Picker("Visualizzatore", selection: settings.binding(\.appearance.visualizer)) {
                    ForEach(VisualizerStyle.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Notch chiusa") {
                ValueSlider(
                    title: "La copertina resta dopo la pausa per",
                    value: settings.binding(\.media.pausedLingerSeconds),
                    range: 0...120,
                    step: 3,
                    format: { "\(Int($0)) s" }
                )
                Toggle("Avvisa quando cambia brano", isOn: settings.binding(\.peeks.trackChange))
            }

            Section("A tutto schermo") {
                Picker("Nascondi la notch", selection: settings.binding(\.behavior.hideInFullscreen)) {
                    ForEach(FullscreenPolicy.allCases) { Text($0.label).tag($0) }
                }
            }
        }
    }
}

// MARK: - Calendario

struct CalendarSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var calendar: CalendarService

    var body: some View {
        SettingsForm(section: .calendar, subtitle: "Il tuo calendario di sistema, compresi gli account iCloud, Google ed Exchange. I dati restano sul Mac.") {
            Section("Accesso") {
                HStack {
                    Text("Calendario")
                    Spacer()
                    accessBadge(calendar.eventsAccess)
                    if calendar.eventsAccess != .granted {
                        Button(calendar.eventsAccess == .denied ? "Apri Impostazioni" : "Consenti") { calendar.requestEventsAccess() }
                    }
                }
                HStack {
                    Text("Promemoria")
                    Spacer()
                    accessBadge(calendar.remindersAccess)
                    if calendar.remindersAccess != .granted {
                        Button(calendar.remindersAccess == .denied ? "Apri Impostazioni" : "Consenti") { calendar.requestRemindersAccess() }
                    }
                }
            }

            Section("Cosa mostrare") {
                Toggle("Eventi di tutto il giorno", isOn: settings.binding(\.calendar.showAllDay))
                Toggle("Promemoria di oggi", isOn: settings.binding(\.calendar.showReminders))
                Toggle("Pulsante per entrare nelle riunioni online", isOn: settings.binding(\.calendar.showJoinButton))
            }

            Section("Avvisi") {
                Toggle("Avvisa prima di un evento", isOn: settings.binding(\.peeks.upcomingEvent))
                if settings.config.peeks.upcomingEvent {
                    ValueSlider(title: "Quanti minuti prima", value: settings.binding(\.peeks.upcomingMinutes), range: 1...30, format: { "\(Int($0)) min" })
                }
            }

            if !calendar.sources.isEmpty {
                Section("Calendari") {
                    ForEach(calendar.sources) { source in
                        Toggle(isOn: visibility(of: source)) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hexString: source.colorHex) ?? .gray)
                                    .frame(width: 9, height: 9)
                                Text(source.title)
                                Text(source.accountName)
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func accessBadge(_ access: CalendarService.Access) -> some View {
        switch access {
        case .granted:      StatusBadge(text: "Consentito", color: .green)
        case .denied:       StatusBadge(text: "Negato", color: .red)
        case .undetermined: StatusBadge(text: "Da decidere", color: .orange)
        }
    }

    private func visibility(of source: CalendarSource) -> Binding<Bool> {
        Binding(
            get: { !settings.config.calendar.hiddenCalendarIDs.contains(source.id) },
            set: { visible in
                settings.update { config in
                    config.calendar.hiddenCalendarIDs.removeAll { $0 == source.id }
                    if !visible { config.calendar.hiddenCalendarIDs.append(source.id) }
                }
            }
        )
    }
}

// MARK: - Scaffale

struct ShelfSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var shelf: ShelfStore

    var body: some View {
        SettingsForm(section: .shelf, subtitle: "Trascina qualcosa sulla notch e la ritrovi lì: file, link, testo, immagini. Con AirDrop a un gesto di distanza.") {
            Section("Trascinamento") {
                Toggle("Apri la notch quando ci trascini sopra qualcosa", isOn: settings.binding(\.behavior.openShelfOnDrag))
                Toggle("Togli dallo scaffale ciò che trascini fuori", isOn: settings.binding(\.shelf.removeAfterDragOut))
            }
            Section("File") {
                Toggle("Copia i file nello scaffale", isOn: settings.binding(\.shelf.copyFiles))
                Text("Spenta, lo scaffale ricorda dove si trovano i file. Accesa, ne tiene una copia propria: resta anche se cancelli l'originale, ma occupa spazio.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Contenuto") {
                HStack {
                    Text("Oggetti sullo scaffale")
                    Spacer()
                    Text("\(shelf.items.count)").foregroundStyle(.secondary)
                    Button("Svuota") { shelf.clear() }
                        .disabled(shelf.items.isEmpty)
                }
            }
        }
    }
}

// MARK: - Collegamenti

struct LauncherSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var shortcuts: [String] = []
    @State private var linkName = ""
    @State private var linkTarget = ""
    @State private var commandName = ""
    @State private var commandTarget = ""

    private var items: [LauncherItem] { settings.config.launcher.items }

    var body: some View {
        SettingsForm(section: .launcher, subtitle: "App, comandi rapidi, link e script da lanciare con un click. Aggiungi il widget Collegamenti da Layout.") {
            Section("Elementi") {
                if items.isEmpty {
                    Text("Nessun collegamento").foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        icon(item)
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name)
                            Text(item.kind.label)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            settings.update { $0.launcher.items.removeAll { $0.id == item.id } }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onMove { from, to in
                    settings.update { $0.launcher.items.move(fromOffsets: from, toOffset: to) }
                }
            }

            Section("Aggiungi") {
                HStack {
                    Text("Un'app")
                    Spacer()
                    Button("Scegli…") { chooseApp() }
                }
                Picker("Un comando rapido", selection: Binding<String>(
                    get: { "" },
                    set: { name in
                        guard !name.isEmpty else { return }
                        add(LauncherItem(name: name, kind: .shortcut, target: name))
                    }
                )) {
                    Text("Scegli…").tag("")
                    ForEach(shortcuts, id: \.self) { Text($0).tag($0) }
                }
                .task { shortcuts = await Self.loadShortcuts() }

                HStack {
                    TextField("Nome del link", text: $linkName)
                    TextField("https://…", text: $linkTarget)
                    Button("Aggiungi") {
                        add(LauncherItem(name: linkName, kind: .url, target: linkTarget))
                        linkName = ""
                        linkTarget = ""
                    }
                    .disabled(linkName.isEmpty || URL(string: linkTarget)?.scheme == nil)
                }

                HStack {
                    TextField("Nome del comando", text: $commandName)
                    TextField("Riga di comando", text: $commandTarget)
                        .font(.system(.body, design: .monospaced))
                    Button("Aggiungi") {
                        add(LauncherItem(name: commandName, kind: .command, target: commandTarget))
                        commandName = ""
                        commandTarget = ""
                    }
                    .disabled(commandName.isEmpty || commandTarget.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func icon(_ item: LauncherItem) -> some View {
        if item.kind == .app {
            Image(nsImage: NSWorkspace.shared.icon(forFile: AppPaths.expand(item.target).path)).resizable()
        } else {
            Image(systemName: item.symbol ?? LauncherRunner.defaultSymbol(item.kind))
                .foregroundStyle(.secondary)
        }
    }

    private func add(_ item: LauncherItem) {
        settings.update { $0.launcher.items.append(item) }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            add(LauncherItem(name: url.deletingPathExtension().lastPathComponent, kind: .app, target: url.path))
        }
    }

    private static func loadShortcuts() async -> [String] {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [String]() }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)?
                .split(separator: "\n")
                .map(String.init)
                .sorted() ?? []
        }.value
    }
}

// MARK: - Widget personalizzati

struct CustomWidgetsSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var store: CustomWidgetStore

    private struct Template: Identifiable {
        var id: String { name }
        var name: String
        var symbol: String
        var command: String
        var refresh: Double
        var summary: String
    }

    private let templates = [
        Template(name: "Meteo", symbol: "cloud.sun.fill", command: "curl -fsS 'https://wttr.in/?format=%t+%C'", refresh: 1800, summary: "Temperatura e cielo da wttr.in"),
        Template(name: "Pull request", symbol: "arrow.triangle.pull", command: "gh search prs --author=@me --state=open --json title,repository --jq '{text: (length|tostring), subtitle: \"aperte\", rows: [.[] | {title: .title, value: .repository.name}]}'", refresh: 300, summary: "Le tue PR aperte, via GitHub CLI"),
        Template(name: "Uptime", symbol: "clock.arrow.circlepath", command: "uptime | sed 's/.*up \\([^,]*\\),.*/\\1/'", refresh: 300, summary: "Da quanto è acceso il Mac"),
        Template(name: "IP pubblico", symbol: "network", command: "curl -fsS https://ifconfig.me", refresh: 900, summary: "L'indirizzo con cui esci su Internet")
    ]

    var body: some View {
        SettingsForm(section: .widgets, subtitle: "Se lo puoi scrivere in uno script, lo puoi mettere nella notch. Il comando stampa testo o JSON, Lunetta lo mostra.") {
            Section("I tuoi widget") {
                if settings.config.customWidgets.isEmpty {
                    Text("Nessun widget. Parti da un modello qui sotto o creane uno vuoto.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.config.customWidgets) { widget in
                    CustomWidgetEditor(widget: widget)
                }
                Button("Nuovo widget") {
                    add(CustomWidgetConfig(name: "Nuovo widget", command: "date '+%H:%M'"))
                }
            }

            Section("Modelli") {
                ForEach(templates) { template in
                    HStack(spacing: 10) {
                        Image(systemName: template.symbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(template.name)
                            Text(template.summary)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Aggiungi") {
                            add(CustomWidgetConfig(name: template.name, symbol: template.symbol, command: template.command, refreshSeconds: template.refresh))
                        }
                    }
                }
            }

            Section("Cosa può stampare il comando") {
                Text("Testo semplice: la prima riga è il valore, le altre vanno sotto. Oppure JSON, tutti i campi facoltativi:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("""
                {
                  "text": "22°",  "subtitle": "Milano",
                  "symbol": "sun.max.fill",  "tint": "#FFD60A",
                  "progress": 0.4,
                  "rows": [{ "title": "Domani", "value": "19°", "symbol": "cloud.fill" }],
                  "url": "https://…",
                  "compact": "22°",  "active": true
                }
                """)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5)))
            }
        }
    }

    private func add(_ widget: CustomWidgetConfig) {
        settings.update { $0.customWidgets.append(widget) }
        // Un widget nuovo si prova subito: si vede se il comando funziona.
        store.test(widget)
    }
}

private struct CustomWidgetEditor: View {
    let widget: CustomWidgetConfig

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var store: CustomWidgetStore
    @State private var expanded = false

    private func field<Value>(_ keyPath: WritableKeyPath<CustomWidgetConfig, Value>, default fallback: Value) -> Binding<Value> {
        settings.binding(in: \.customWidgets, id: widget.id, keyPath, default: fallback)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SymbolPicker(symbol: field(\.symbol, default: "terminal.fill"))
                    TextField("Nome", text: field(\.name, default: ""))
                }
                TextField("Comando", text: field(\.command, default: ""), axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...4)
                ValueSlider(title: "Aggiorna ogni", value: field(\.refreshSeconds, default: 60), range: 5...3600, step: 5, format: { Format.duration($0) })

                HStack {
                    Button("Prova adesso") { store.test(widget) }
                    Spacer()
                    Button("Elimina", role: .destructive) { delete(widget) }
                }

                if let error = store.errors[widget.id] {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                } else if let output = store.outputs[widget.id] {
                    Text("Ultimo risultato: \(output.text ?? "(nessun testo)")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text("Compare fra i widget e gli elementi disponibili in Layout.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        } label: {
            Label(widget.name, systemImage: widget.symbol)
        }
    }

    private func delete(_ widget: CustomWidgetConfig) {
        let kind = ModuleCatalog.customKind(widget.id)
        settings.update { config in
            config.customWidgets.removeAll { $0.id == widget.id }
            // Non deve restare un riquadro vuoto nelle pagine che lo usavano.
            for index in config.layout.pages.indices {
                config.layout.pages[index].widgets.removeAll { $0.kind == kind }
            }
            config.layout.closedLeading.removeAll { $0 == kind }
            config.layout.closedTrailing.removeAll { $0 == kind }
            config.layout.headerTrailing.removeAll { $0 == kind }
        }
    }
}
