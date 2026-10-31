import AppKit
import Combine
import SwiftUI

/// Tutti i servizi dell'app e il collante fra di loro: chi si accende in base al
/// layout, quale evento diventa un avviso nella notch, cosa fa un tasto.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let settings: SettingsStore
    let sessions: SessionStore
    let media = MediaService()
    let calendar = CalendarService()
    let shelf: ShelfStore
    let battery = BatteryMonitor()
    let system = SystemMonitor()
    let clipboard = ClipboardStore()
    let timer = TimerStore()
    let notes: NotesStore
    let custom = CustomWidgetStore()
    let camera = CameraMirror()
    let volume = VolumeController()
    let brightness = BrightnessController()

    private(set) lazy var notch = NotchManager(services: self)

    private let mediaKeys = MediaKeyTap()
    private let bluetooth = BluetoothMonitor()
    private var bluetoothRunning = false
    private var cancellables: Set<AnyCancellable> = []
    private var knownStatuses: [String: SessionStatus] = [:]
    private var sessionsSeeded = false
    private var accessibilityTimer: Timer?
    let isDemo: Bool

    private init() {
        isDemo = CommandLine.arguments.contains("--demo")
        settings = SettingsStore(persists: !isDemo)
        sessions = isDemo ? SessionStore(preview: DemoData.sessions) : SessionStore(config: settings.config.agents)
        shelf = ShelfStore(persists: !isDemo)
        notes = NotesStore(persists: !isDemo, initial: isDemo ? DemoData.notes : nil)
    }

    var isDragActive: Bool { notch.isDragActive }

    // MARK: - Avvio

    func start() {
        wireEvents()
        if isDemo {
            DemoData.seed(self)
        } else {
            battery.start()
            sessions.start()
        }
        applyConfig(settings.config)

        settings.$config
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] config in
                DispatchQueue.main.async { self?.applyConfig(config) }
            }
            .store(in: &cancellables)

        notch.start()
        MainMenu.install(services: self)
        MenuBarController.shared.start(services: self)
        HotKeyCenter.shared.perform = { [weak self] action in self?.perform(action) }
        HotKeyCenter.shared.apply(settings.config.hotkeys)
    }

    /// Boring Notch disegna nello stesso punto: due app sulla stessa notch si coprono a vicenda.
    func warnAboutConflicts() {
        let bundleID = "theboringteam.boringnotch"
        guard !isDemo, !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return }
        notch.show(NotchPeek(
            title: "Boring Notch è aperto",
            subtitle: "Si sovrappone a Lunetta",
            icon: .symbol("exclamationmark.triangle.fill"),
            tint: Color(hex: 0xFFC145),
            duration: 12,
            group: "conflict",
            actionLabel: "Chiudilo",
            action: {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
            }
        ))
    }

    func shutdown() {
        media.stop()
        sessions.stop()
        mediaKeys.stop()
        settings.writeNow()
    }

    // MARK: - Configurazione

    /// I widget e gli elementi usati in questo momento: cosa non è usato non deve girare.
    private func usedKinds(_ config: LunettaConfig) -> Set<String> {
        var kinds = Set(config.layout.pages.flatMap { $0.widgets.map(\.kind) })
        let compacts = config.layout.closedLeading + config.layout.closedTrailing + config.layout.headerTrailing
        for id in compacts {
            if ModuleCatalog.customID(fromKind: id) != nil {
                kinds.insert(id)
            } else if let module = id.split(separator: ".").first {
                kinds.insert(String(module))
            }
        }
        return kinds
    }

    private func applyConfig(_ config: LunettaConfig) {
        sessions.apply(config: config.agents)
        media.pausedLinger = config.media.pausedLingerSeconds
        calendar.config = config.calendar
        calendar.peekLeadMinutes = config.peeks.enabled && config.peeks.upcomingEvent ? config.peeks.upcomingMinutes : 0
        shelf.copyFiles = config.shelf.copyFiles
        clipboard.maxItems = config.clipboard.maxItems

        guard !isDemo else { return }
        let kinds = usedKinds(config)

        if kinds.contains("media") || (config.peeks.enabled && config.peeks.trackChange) {
            media.start()
        } else {
            media.stop()
        }

        if kinds.contains("calendar") || (config.peeks.enabled && config.peeks.upcomingEvent) {
            calendar.start()
        } else {
            calendar.stop()
        }

        kinds.contains("clipboard") ? clipboard.start() : clipboard.stop()

        let neededCustom = Set(kinds.compactMap(ModuleCatalog.customID(fromKind:)))
        custom.apply(configs: config.customWidgets, needed: neededCustom)

        applyHUD(config)
        applyBluetooth(config)
        HotKeyCenter.shared.apply(config.hotkeys)
        MenuBarController.shared.update()
    }

    // MARK: - Eventi → avvisi

    private func wireEvents() {
        media.onTrackChange = { [weak self] track in
            guard let self, self.settings.config.peeks.enabled, self.settings.config.peeks.trackChange else { return }
            // La copertina può arrivare un istante dopo il titolo: si aspetta un attimo.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.media.nowPlaying?.trackKey == track.trackKey else { return }
                self.showPeek(NotchPeek(
                    title: track.title,
                    subtitle: track.artist.isEmpty ? track.appName : track.artist,
                    icon: self.media.artwork.map { .artwork($0) } ?? .symbol("music.note"),
                    tint: nil,
                    duration: 3,
                    group: "media",
                    action: { [weak self] in self?.notch.open() }
                ))
            }
        }

        battery.onPlugChange = { [weak self] state in
            guard let self, self.settings.config.peeks.enabled, self.settings.config.peeks.charger else { return }
            self.showPeek(NotchPeek(
                title: state.isPluggedIn ? "In carica" : "A batteria",
                subtitle: "\(Int((state.level * 100).rounded()))%",
                icon: .symbol(state.isPluggedIn ? "bolt.fill" : "battery.75percent"),
                tint: state.isPluggedIn ? Color(hex: 0x4ADE80) : nil,
                duration: 2.4,
                group: "battery"
            ))
        }

        battery.onLowBattery = { [weak self] state in
            guard let self, self.settings.config.peeks.enabled, self.settings.config.peeks.lowBattery else { return }
            self.showPeek(NotchPeek(
                title: "Batteria quasi scarica",
                subtitle: "\(Int((state.level * 100).rounded()))% rimanente",
                icon: .symbol("battery.25percent"),
                tint: Color(hex: 0xFF5A63),
                duration: 5,
                group: "battery"
            ))
        }

        calendar.onUpcoming = { [weak self] event in
            guard let self else { return }
            self.showPeek(NotchPeek(
                title: event.title,
                subtitle: Format.until(event.start),
                icon: .symbol("calendar"),
                tint: Color(hexString: event.colorHex),
                duration: 6,
                group: "calendar",
                actionLabel: event.meetingURL == nil ? nil : "Entra",
                action: { [weak self] in
                    if let url = event.meetingURL {
                        NSWorkspace.shared.open(url)
                    } else {
                        self?.calendar.open(event)
                    }
                }
            ))
        }

        timer.onFinish = { [weak self] in
            guard let self else { return }
            NSSound(named: "Glass")?.play()
            guard self.settings.config.peeks.enabled, self.settings.config.peeks.timerDone else { return }
            self.showPeek(NotchPeek(
                title: "Tempo scaduto",
                subtitle: self.timer.label.isEmpty ? nil : self.timer.label,
                icon: .symbol("timer"),
                tint: nil,
                duration: 6,
                group: "timer"
            ))
        }

        bluetooth.onChange = { [weak self] name, symbol, connected, battery in
            guard let self else { return }
            let detail = connected ? (battery.map { "Collegato · \($0)%" } ?? "Collegato") : "Scollegato"
            DispatchQueue.main.async {
                self.showPeek(NotchPeek(
                    title: name,
                    subtitle: detail,
                    icon: .symbol(symbol),
                    tint: connected ? nil : Color.white.opacity(0.5),
                    duration: 3,
                    group: "bluetooth"
                ))
            }
        }

        mediaKeys.onKey = { [weak self] key, fine in
            MainActor.assumeIsolated { self?.handleMediaKey(key, fine: fine) }
        }

        // Gli stati degli agenti sono la notizia più importante che passa dalla notch.
        sessions.$sessions
            .sink { [weak self] list in self?.diffSessions(list) }
            .store(in: &cancellables)
    }

    private func showPeek(_ peek: NotchPeek) {
        guard settings.config.peeks.enabled else { return }
        var peek = peek
        peek.duration = peek.duration == 0 ? settings.config.peeks.duration : peek.duration
        notch.show(peek)
    }

    private func diffSessions(_ list: [AgentSession]) {
        defer {
            knownStatuses = Dictionary(list.map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first })
            sessionsSeeded = true
        }
        // Al primo giro non è cambiato niente: si stava solo guardando per la prima volta.
        guard sessionsSeeded else { return }
        let rules = settings.config.peeks

        for session in list {
            let previous = knownStatuses[session.id]
            guard previous != session.status else { continue }

            let wanted: Bool
            switch session.status {
            case .blocked:   wanted = rules.agentBlocked
            case .attention: wanted = rules.agentAttention && (previous == .working || previous == nil)
            case .error:     wanted = rules.agentError
            case .ended:     wanted = rules.agentEnded && previous?.isLive == true
            default:         wanted = false
            }
            guard wanted else { continue }

            if !rules.agentSound.isEmpty, session.status.needsYou {
                NSSound(named: NSSound.Name(rules.agentSound))?.play()
            }
            showPeek(NotchPeek(
                title: session.project,
                subtitle: peekSubtitle(for: session),
                icon: .status(session.status),
                tint: session.status.tint,
                duration: rules.duration,
                group: "agent:\(session.id)",
                actionLabel: "Vai",
                action: { SessionActions.focus(session) }
            ))
        }
    }

    private func peekSubtitle(for session: AgentSession) -> String {
        switch session.status {
        case .blocked:
            return session.activity ?? session.status.label
        case .attention:
            return session.activity ?? "Ha finito, tocca a te"
        case .error:
            return session.activity ?? session.status.label
        default:
            return session.status.label
        }
    }

    // MARK: - HUD

    private func applyHUD(_ config: LunettaConfig) {
        if config.hud.replaceSystemHUD {
            if !mediaKeys.start(), accessibilityTimer == nil {
                // Il permesso può arrivare in qualsiasi momento: appena c'è, si parte.
                let timer = Timer(timeInterval: 2, repeats: true) { [weak self] timer in
                    MainActor.assumeIsolated {
                        guard let self else {
                            timer.invalidate()
                            return
                        }
                        if !self.settings.config.hud.replaceSystemHUD || self.mediaKeys.start() {
                            timer.invalidate()
                            self.accessibilityTimer = nil
                        }
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                accessibilityTimer = timer
            }
        } else {
            mediaKeys.stop()
            accessibilityTimer?.invalidate()
            accessibilityTimer = nil
        }
    }

    private func handleMediaKey(_ key: MediaKeyTap.Key, fine: Bool) {
        let step = fine ? 1.0 / 64 : 1.0 / 16
        switch key {
        case .soundUp:
            volume.change(by: step)
            playVolumeFeedback()
            showHUD(.volume, level: volume.level, muted: volume.isMuted)
        case .soundDown:
            volume.change(by: -step)
            playVolumeFeedback()
            showHUD(.volume, level: volume.level, muted: volume.isMuted)
        case .mute:
            volume.toggleMute()
            showHUD(.volume, level: volume.level, muted: volume.isMuted)
        case .brightnessUp:
            if let level = brightness.changeScreen(by: step) { showHUD(.brightness, level: level) }
        case .brightnessDown:
            if let level = brightness.changeScreen(by: -step) { showHUD(.brightness, level: level) }
        case .keyboardUp:
            if let level = brightness.changeKeyboard(by: step) { showHUD(.keyboard, level: level) }
        case .keyboardDown:
            if let level = brightness.changeKeyboard(by: -step) { showHUD(.keyboard, level: level) }
        }
    }

    private func showHUD(_ kind: NotchHUD.Kind, level: Double, muted: Bool = false) {
        notch.show(hud: NotchHUD(kind: kind, level: level, muted: muted))
    }

    /// Il "tic" del volume, se l'utente l'ha attivato nelle impostazioni di sistema.
    private func playVolumeFeedback() {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        guard (global?["com.apple.sound.beep.feedback"] as? Int) == 1 else { return }
        let path = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        NSSound(contentsOfFile: path, byReference: true)?.play()
    }

    // MARK: - Bluetooth

    private func applyBluetooth(_ config: LunettaConfig) {
        let wanted = config.peeks.enabled && config.peeks.bluetooth
        guard wanted != bluetoothRunning else { return }
        bluetoothRunning = wanted
        wanted ? bluetooth.start() : bluetooth.stop()
    }

    // MARK: - Azioni

    func notchOpenChanged() {
        let anyOpen = notch.controllers.values.contains { $0.state.isOpen }
        sessions.setActiveUI(anyOpen)
        notch.stateChanged()
    }

    func perform(_ action: HotkeyAction) {
        switch action {
        case .toggleNotch:
            notch.toggle()
        case .openAgents:
            let page = settings.config.layout.pages.first { $0.containsWidget("agents") }
            notch.open(page: page?.id)
        case .nextPage:
            notch.stepPage(1)
        case .previousPage:
            notch.stepPage(-1)
        case .playPause:
            media.togglePlayPause()
        case .nextTrack:
            media.next()
        case .previousTrack:
            media.previous()
        case .openSettings:
            SettingsWindowController.shared.show(section: nil, services: self)
        }
    }

    // MARK: - Profili

    var allProfiles: [ProfileConfig] {
        ProfileConfig.builtIn + settings.config.profiles
    }

    func apply(profile: ProfileConfig) {
        settings.update { config in
            config.layout = profile.layout
            config.appearance = profile.appearance
            config.activeProfileID = profile.id
        }
    }

    func applyProfile(id: String) -> Bool {
        guard let profile = allProfiles.first(where: { $0.id == id || $0.name.caseInsensitiveCompare(id) == .orderedSame }) else {
            return false
        }
        apply(profile: profile)
        return true
    }

    // MARK: - Riavvio

    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.4; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

extension View {
    /// Mette a disposizione di una gerarchia di viste tutti i servizi dell'app.
    @MainActor
    func lunettaEnvironment(_ services: AppServices) -> some View {
        environmentObject(services.settings)
            .environmentObject(services.sessions)
            .environmentObject(services.sessions.summary)
            .environmentObject(services.media)
            .environmentObject(services.calendar)
            .environmentObject(services.shelf)
            .environmentObject(services.battery)
            .environmentObject(services.system)
            .environmentObject(services.clipboard)
            .environmentObject(services.timer)
            .environmentObject(services.notes)
            .environmentObject(services.custom)
            .environmentObject(services.camera)
    }
}
