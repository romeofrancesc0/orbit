import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Comportamento

struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var updater = Updater.shared
    @State private var loginEnabled = LoginItem.isEnabled

    var body: some View {
        SettingsForm(section: .general, subtitle: tr("Come e quando la notch si apre, si chiude e si fa da parte.")) {
            Section("Lingua") {
                Picker("Lingua dell'interfaccia", selection: settings.binding(\.language)) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language == .system ? tr("Lingua di sistema") : language.nativeName).tag(language)
                    }
                }
                Text("Il cambio è immediato. Menu e finestre si aggiornano da soli.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Avvio") {
                Toggle("Avvia Orbit al login", isOn: Binding(
                    get: { loginEnabled },
                    set: { value in
                        LoginItem.set(value)
                        loginEnabled = LoginItem.isEnabled
                    }
                ))
                .disabled(!LoginItem.isAvailable)
                Toggle("Icona nella barra dei menu", isOn: settings.binding(\.behavior.showMenuBarIcon))
                if settings.config.behavior.showMenuBarIcon {
                    Toggle("Numero di sessioni attive accanto all'icona", isOn: settings.binding(\.behavior.menuBarShowsAgentCount))
                }
            }

            if updater.isAvailable {
                Section("Aggiornamenti") {
                    Toggle("Controlla automaticamente gli aggiornamenti", isOn: $updater.automaticallyChecks)
                    HStack {
                        Text(tr("Versione %@", updater.currentVersion))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Controlla adesso") { updater.checkForUpdates() }
                            .disabled(!updater.canCheckForUpdates)
                    }
                    Text("Le nuove versioni si scaricano e si installano da sole, dopo averti chiesto il permesso.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Apertura") {
                Toggle("Apri al passaggio del mouse", isOn: settings.binding(\.behavior.openOnHover))
                if settings.config.behavior.openOnHover {
                    ValueSlider(title: tr("Ritardo"), value: settings.binding(\.behavior.hoverDelay), range: 0...1, step: 0.02, format: { "\(Int($0 * 1000)) ms" })
                }
                Toggle("Gesti con il trackpad", isOn: settings.binding(\.behavior.gestures))
                    .help("Due dita in giù sulla notch per aprirla, di lato per cambiare pagina, in su sulla testata per chiuderla")
                Toggle("Risposta tattile", isOn: settings.binding(\.behavior.haptics))
            }

            Section("Chiusura") {
                Toggle("Chiudi quando il mouse esce", isOn: settings.binding(\.behavior.closeOnMouseLeave))
                if settings.config.behavior.closeOnMouseLeave {
                    ValueSlider(title: tr("Ritardo"), value: settings.binding(\.behavior.closeDelay), range: 0...2, step: 0.05, format: { "\(Int($0 * 1000)) ms" })
                }
                Toggle("Chiudi con un click fuori", isOn: settings.binding(\.behavior.closeOnClickOutside))
            }

            Section("Schermi") {
                Picker("Mostra la notch su", selection: settings.binding(\.behavior.displayMode)) {
                    ForEach(DisplayMode.allCases) { Text($0.label).tag($0) }
                }
                ValueSlider(title: tr("Larghezza sugli schermi senza notch"), value: settings.binding(\.behavior.virtualNotchWidth), range: 120...300, step: 5)
            }

            Section("Discrezione") {
                Picker("Nascondi a tutto schermo", selection: settings.binding(\.behavior.hideInFullscreen)) {
                    ForEach(FullscreenPolicy.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Non comparire in registrazioni e condivisione schermo", isOn: settings.binding(\.behavior.hideFromScreenCapture))
                Toggle("Mostra sulla schermata di blocco (sperimentale)", isOn: settings.binding(\.behavior.showOnLockScreen))
                Toggle("Ingranaggio delle impostazioni nella notch", isOn: settings.binding(\.behavior.settingsButtonInNotch))
            }
        }
        .onAppear { loginEnabled = LoginItem.isEnabled }
    }
}

// MARK: - Avvisi

struct PeeksSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var quiet: QuietMode

    private let sounds = ["", "Glass", "Tink", "Pop", "Ping", "Purr", "Hero", "Funk", "Submarine", "Morse", "Bottle", "Frog", "Sosumi", "Blow", "Basso"]

    var body: some View {
        SettingsForm(section: .peeks, subtitle: tr("I piccoli messaggi che scendono dalla notch. Decidi tu cosa merita di interromperti.")) {
            Section {
                Toggle("Attiva gli avvisi", isOn: settings.binding(\.peeks.enabled))
                ValueSlider(title: tr("Durata"), value: settings.binding(\.peeks.duration), range: 1...12, step: 0.5, format: { String(format: "%.1f s", $0) })
            }

            Section("Silenzio") {
                Toggle("Non interrompere mentre guardi un video", isOn: settings.binding(\.peeks.quietDuringVideo))
                Toggle("Non interrompere con un'app a tutto schermo", isOn: settings.binding(\.peeks.quietInFullscreen))
                Toggle("Silenzia gli avvisi adesso", isOn: Binding(
                    get: { quiet.isOn },
                    set: { AppServices.shared.setQuiet($0) }
                ))
                Text("In silenzio gli avvisi non scendono e non vengono rimandati: restano l'alone e i pallini nella notch chiusa. Un video è un'app che non fa solo musica, in primo piano. macOS non permette alle app di leggere i Focus: per legarlo a uno, crea in Comandi rapidi un'automazione \"quando attivo il Focus → Silenzia gli avvisi della notch\" (e l'inversa quando si disattiva).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Coding agent") {
                Toggle("Un agente chiede un permesso", isOn: settings.binding(\.peeks.agentBlocked))
                Toggle("Un agente ha finito e ti aspetta", isOn: settings.binding(\.peeks.agentAttention))
                    .help("Anche spento, la notch chiusa si illumina e il pallino cambia colore")
                Toggle("Un agente va in errore", isOn: settings.binding(\.peeks.agentError))
                Toggle("Una sessione si chiude", isOn: settings.binding(\.peeks.agentEnded))
                ValueSlider(title: tr("Il nuovo stato deve durare"), value: settings.binding(\.peeks.agentSettleSeconds), range: 0...15, step: 0.5, format: { String(format: "%.1f s", $0) })
                ValueSlider(title: tr("Pausa fra due avvisi della stessa sessione"), value: settings.binding(\.peeks.agentCooldownSeconds), range: 0...300, step: 5, format: { Format.duration($0) })
                HStack {
                    Picker("Suono", selection: settings.binding(\.peeks.agentSound)) {
                        ForEach(sounds, id: \.self) { Text($0.isEmpty ? tr("Nessuno") : $0).tag($0) }
                    }
                    Button {
                        NSSound(named: NSSound.Name(settings.config.peeks.agentSound))?.play()
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(settings.config.peeks.agentSound.isEmpty)
                    .help("Ascolta")
                }
            }

            Section("Altro") {
                Toggle("Cambia brano", isOn: settings.binding(\.peeks.trackChange))
                Toggle("Colleghi o scolleghi il caricatore", isOn: settings.binding(\.peeks.charger))
                Toggle("Batteria quasi scarica", isOn: settings.binding(\.peeks.lowBattery))
                Toggle("Dispositivi Bluetooth", isOn: settings.binding(\.peeks.bluetooth))
                Toggle("Evento in arrivo", isOn: settings.binding(\.peeks.upcomingEvent))
                Toggle("Timer scaduto", isOn: settings.binding(\.peeks.timerDone))
            }

            Section("Dai tuoi script") {
                Text("Qualunque programma può mandare un avviso alla notch:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("open 'orbit://peek?title=Build&subtitle=Finita&symbol=hammer.fill&tint=%234ADE80'")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Button("Prova un avviso") {
                    AppServices.shared.notch.show(NotchPeek(
                        title: tr("Ecco un avviso"),
                        subtitle: tr("Così scende dalla notch"),
                        icon: .symbol("bell.fill"),
                        tint: nil,
                        duration: settings.config.peeks.duration,
                        group: "prova",
                        isForced: true
                    ))
                }
            }
        }
    }
}

// MARK: - Volume e luminosità

struct HUDSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var trusted = MediaKeyTap.isTrusted
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsForm(section: .hud, subtitle: tr("Sostituisce gli indicatori di sistema di volume, luminosità e tastiera con quelli nella notch.")) {
            Section {
                Toggle("Sostituisci gli indicatori di sistema", isOn: Binding(
                    get: { settings.config.hud.replaceSystemHUD },
                    set: { value in
                        settings.update { $0.hud.replaceSystemHUD = value }
                        if value, !MediaKeyTap.isTrusted { MediaKeyTap.requestTrust() }
                    }
                ))
                if settings.config.hud.replaceSystemHUD, !trusted {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Serve il permesso di Accessibilità per ricevere i tasti di volume e luminosità. Finché manca compare l'indicatore di sistema.")
                                    .font(.callout)
                                Text("Se in Impostazioni di Sistema Orbit risulta già attiva, quel permesso era di una versione precedente: ripristinalo e attivalo di nuovo.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack {
                            Spacer()
                            Button("Ripristina il permesso") { MediaKeyTap.resetTrust() }
                            Button("Apri Impostazioni") { MediaKeyTap.requestTrust() }
                        }
                    }
                }
            }

            Section("Aspetto") {
                Picker("Posizione", selection: settings.binding(\.hud.style)) {
                    ForEach(HUDStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Mostra la percentuale", isOn: settings.binding(\.hud.showPercent))
                Toggle("Usa il colore d'accento", isOn: settings.binding(\.hud.useAccent))
                ValueSlider(title: tr("Resta visibile per"), value: settings.binding(\.hud.duration), range: 0.6...4, step: 0.1, format: { String(format: "%.1f s", $0) })
                HStack {
                    Spacer()
                    Button("Prova") {
                        AppServices.shared.notch.show(hud: NotchHUD(kind: .volume, level: AppServices.shared.volume.level))
                    }
                }
            }

            Section {
                Text("Con ⌥⇧ i tasti si muovono a passi più piccoli, come nell'indicatore di sistema.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(timer) { _ in trusted = MediaKeyTap.isTrusted }
    }
}

// MARK: - Scorciatoie

struct ShortcutsSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        SettingsForm(section: .shortcuts, subtitle: tr("Scorciatoie valide ovunque, anche con un'altra app in primo piano.")) {
            Section {
                ForEach(settings.config.hotkeys) { hotkey in
                    HStack {
                        Text(hotkey.action.label)
                        Spacer()
                        HotkeyRecorder(binding: binding(for: hotkey.action))
                    }
                }
            }
            Section("Con i Comandi rapidi") {
                Text("Orbit aggiunge le sue azioni all'app Comandi rapidi e a Spotlight: apri una pagina, manda un avviso, cambia profilo, conta le sessioni attive.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension ShortcutsSettingsView {
    fileprivate func binding(for action: HotkeyAction) -> Binding<HotkeyBinding> {
        Binding(
            get: {
                settings.config.hotkeys.first { $0.action == action } ?? HotkeyBinding(action: action, keyCode: nil, modifiers: 0)
            },
            set: { value in
                settings.update { config in
                    guard let index = config.hotkeys.firstIndex(where: { $0.action == action }) else { return }
                    config.hotkeys[index] = value
                }
            }
        )
    }
}

/// Clicca e premi: registra la combinazione successiva.
private struct HotkeyRecorder: View {
    @Binding var binding: HotkeyBinding

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(label)
                    .font(.callout.monospaced())
                    .frame(minWidth: 96)
            }
            .tint(recording ? .accentColor : nil)
            if binding.keyCode != nil {
                Button {
                    binding.keyCode = nil
                    binding.modifiers = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Togli la scorciatoia")
            }
        }
        .onDisappear { stop() }
    }

    private var label: String {
        if recording { return tr("Premi i tasti…") }
        guard let code = binding.keyCode else { return tr("Nessuna") }
        return HotKeyCenter.describe(keyCode: code, modifiers: binding.modifiers)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Senza modificatori una lettera non può diventare una scorciatoia globale.
            guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else { return nil }
            binding.keyCode = UInt32(event.keyCode)
            binding.modifiers = HotKeyCenter.carbonModifiers(from: flags)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: - Profili

struct ProfilesSettingsView: View {
    let services: AppServices

    @EnvironmentObject private var settings: SettingsStore
    @State private var newName = ""
    @State private var message: String?

    var body: some View {
        SettingsForm(section: .profiles, subtitle: tr("Un profilo ricorda aspetto e layout. Cambiali con un click, con un Comando rapido o con un filtro Full Immersion.")) {
            Section("Pronti all'uso") {
                ForEach(ProfileConfig.builtIn) { profile in
                    row(profile, removable: false)
                }
            }

            Section("I tuoi profili") {
                if settings.config.profiles.isEmpty {
                    Text("Salva la configurazione attuale per ritrovarla quando vuoi.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.config.profiles) { profile in
                    row(profile, removable: true)
                }
                HStack {
                    TextField("Nome del profilo", text: $newName)
                    Button("Salva quello attuale") { saveCurrent() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Condividi") {
                HStack {
                    Button("Esporta la configurazione attuale…") { exportCurrent() }
                    Button("Importa un profilo…") { importProfile() }
                    Spacer()
                }
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ profile: ProfileConfig, removable: Bool) -> some View {
        let isActive = settings.config.activeProfileID == profile.id
        return HStack(spacing: 10) {
            Image(systemName: profile.symbol)
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .frame(width: 22)
            Text(profile.name)
            if isActive {
                Text("In uso")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            if removable {
                Button {
                    settings.update { $0.profiles.removeAll { $0.id == profile.id } }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            Button("Applica") { services.apply(profile: profile) }
                .disabled(isActive)
        }
    }

    private func currentAsProfile(named name: String) -> ProfileConfig {
        ProfileConfig(
            id: UUID().uuidString,
            name: name,
            symbol: "star.fill",
            layout: settings.config.layout,
            appearance: settings.config.appearance
        )
    }

    private func saveCurrent() {
        let profile = currentAsProfile(named: newName.trimmingCharacters(in: .whitespaces))
        settings.update {
            $0.profiles.append(profile)
            $0.activeProfileID = profile.id
        }
        newName = ""
    }

    private func exportCurrent() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = tr("Profilo Orbit.json")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                try encoder.encode(currentAsProfile(named: url.deletingPathExtension().lastPathComponent)).write(to: url)
                message = tr("Profilo esportato in %@.", url.lastPathComponent)
            } catch {
                message = tr("Esportazione non riuscita: %@", error.localizedDescription)
            }
        }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
            do {
                var profile = try JSONDecoder().decode(ProfileConfig.self, from: data)
                // Un id nuovo: importare due volte lo stesso file non deve creare ambiguità.
                profile.id = UUID().uuidString
                settings.update { $0.profiles.append(profile) }
                message = tr("Profilo \"%@\" importato.", profile.name)
            } catch {
                message = tr("Questo file non è un profilo di Orbit.")
            }
        }
    }
}

// MARK: - Permessi

struct PermissionsSettingsView: View {
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var camera: CameraMirror
    @State private var accessibility = MediaKeyTap.isTrusted
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsForm(section: .permissions, subtitle: tr("Orbit chiede solo ciò che serve a ciò che usi, e nulla esce dal tuo Mac.")) {
            Section {
                row(
                    title: tr("Calendario"),
                    detail: tr("Mostra i tuoi eventi nel widget Calendario."),
                    state: map(calendar.eventsAccess)
                ) { calendar.requestEventsAccess() }
                row(
                    title: tr("Promemoria"),
                    detail: tr("Mostra i tuoi promemoria sotto gli eventi."),
                    state: map(calendar.remindersAccess)
                ) { calendar.requestRemindersAccess() }
                row(
                    title: tr("Fotocamera"),
                    detail: tr("Solo per il widget Specchio, e solo mentre lo guardi."),
                    state: camera.access == .granted ? .granted : (camera.access == .denied ? .denied : .undetermined)
                ) { camera.requestAccess() }
                row(
                    title: tr("Accessibilità"),
                    detail: tr("Solo per intercettare i tasti di volume e luminosità."),
                    state: accessibility ? .granted : .undetermined
                ) { MediaKeyTap.resetTrust() }
            }
        }
        .onReceive(timer) { _ in
            accessibility = MediaKeyTap.isTrusted
            camera.refreshAccess()
        }
    }

    private enum PermissionState { case granted, denied, undetermined }

    private func map(_ access: CalendarService.Access) -> PermissionState {
        switch access {
        case .granted:      .granted
        case .denied:       .denied
        case .undetermined: .undetermined
        }
    }

    private func row(title: String, detail: String, state: PermissionState, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch state {
            case .granted:
                StatusBadge(text: tr("Consentito"), color: .green)
            case .denied:
                StatusBadge(text: tr("Negato"), color: .red)
                Button("Apri Impostazioni", action: action)
            case .undetermined:
                StatusBadge(text: tr("Non ancora"), color: .orange)
                Button("Consenti", action: action)
            }
        }
    }
}

// MARK: - Avanzate

struct AdvancedSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var confirmingReset = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        SettingsForm(section: .advanced, subtitle: tr("Ogni impostazione vive in un file JSON leggibile: modificalo a mano e la notch si aggiorna da sola.")) {
            Section("Configurazione") {
                HStack {
                    Text(Format.path(AppPaths.configFile.path) ?? "")
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button("Apri") { settings.openConfigFile() }
                    Button("Mostra nel Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.configFile])
                    }
                }
                Button("Ripristina le impostazioni predefinite…", role: .destructive) {
                    confirmingReset = true
                }
            }

            Section("Primi passi") {
                Button("Rivedi la schermata iniziale") {
                    OnboardingWindowController.shared.show(services: AppServices.shared)
                }
            }

            Section("Informazioni") {
                LabeledContent("Orbit", value: version)
                LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                HStack {
                    Spacer()
                    Button("Riavvia Orbit") { AppServices.relaunch() }
                    Button("Esci") { NSApp.terminate(nil) }
                }
            }
        }
        .confirmationDialog(tr("Ripristinare tutte le impostazioni?"), isPresented: $confirmingReset) {
            Button("Ripristina", role: .destructive) { settings.resetToDefaults() }
        } message: {
            Text("Layout, aspetto e profili salvati tornano come all'inizio. Scaffale e note non vengono toccati.")
        }
    }
}
