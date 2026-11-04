import AppKit
import Combine
import os
import SwiftUI

/// Tiene una notch per ogni schermo scelto, distribuisce gli eventi del mouse e
/// mette in fila avvisi e indicatori.
@MainActor
final class NotchManager {
    private static let log = Logger(subsystem: "com.francescoromeo.powerednotch", category: "avvisi")
    private let services: AppServices
    private(set) var controllers: [CGDirectDisplayID: NotchController] = [:]

    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var pollTimer: Timer?

    private var peekQueue: [NotchPeek] = []
    private var currentPeek: NotchPeek?
    private var peekWork: DispatchWorkItem?
    private var hudWork: DispatchWorkItem?

    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var isMouseDown = false
    private(set) var isDragActive = false

    init(services: AppServices) {
        self.services = services
    }

    func start() {
        rebuildControllers()
        installMonitors()
        observeSystem()

        services.settings.$config
            .map(\.behavior.displayMode)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.rebuildControllers() }
            }
            .store(in: &cancellables)

        services.settings.$config
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.applyConfig() }
            }
            .store(in: &cancellables)

        updateSuppression()
    }

    // MARK: - Schermi

    private func applyConfig() {
        controllers.values.forEach { $0.applyConfig() }
        updateSuppression()
    }

    private func rebuildControllers() {
        let wanted = screensForMode()
        let wantedIDs = Set(wanted.map(\.0))

        for (id, controller) in controllers where !wantedIDs.contains(id) {
            controller.tearDown()
            controllers[id] = nil
        }
        for (id, screen) in wanted {
            if let existing = controllers[id] {
                existing.update(screen: screen)
            } else {
                controllers[id] = NotchController(screen: screen, displayID: id, services: services)
            }
        }
        updateSuppression()
    }

    private func screensForMode() -> [(CGDirectDisplayID, NSScreen)] {
        let screens = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, NSScreen)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen)
        }
        switch services.settings.config.behavior.displayMode {
        case .all:
            return screens
        case .main:
            guard let main = NSScreen.main else { return Array(screens.prefix(1)) }
            return screens.filter { $0.1 == main }
        case .auto:
            // Il ritaglio vero se c'è; altrimenti, a coperchio chiuso, lo schermo principale.
            if let notched = screens.first(where: { $0.1.safeAreaInsets.top > 0 }) { return [notched] }
            return Array(screens.prefix(1))
        }
    }

    /// La notch dello schermo su cui si sta lavorando.
    var activeController: NotchController? {
        let location = NSEvent.mouseLocation
        let underMouse = controllers.values.first { $0.state.geometry.screenFrame.contains(location) }
        return underMouse ?? controllers.values.first
    }

    // MARK: - Eventi

    private func installMonitors() {
        let mouse: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mouse, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mouse, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
        // Un campo di testo terrebbe per sé l'Esc: lo si intercetta prima.
        if let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53, event.window is NotchPanel else { return event }
            MainActor.assumeIsolated { self?.close() }
            return nil
        }) {
            monitors.append(escape)
        }
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            MainActor.assumeIsolated {
                if event.window is NotchPanel { self?.activeController?.handleScroll(event) }
            }
            return event
        }) {
            monitors.append(scroll)
        }

    }

    /// Quando la finestra riceve il mouse, i monitor globali tacciono e i movimenti
    /// locali non sono garantiti: finché il cursore è sulla notch lo si segue così.
    /// A notch chiusa e senza mouse sopra il timer non esiste, e l'app può dormire.
    private func updatePolling() {
        let needed = controllers.values.contains { $0.state.isOpen || $0.state.isHovering }
        if needed, pollTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.dispatchMouse() }
            }
            timer.tolerance = 0.01
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else if !needed, let timer = pollTimer {
            timer.invalidate()
            pollTimer = nil
        }
    }

    private func dispatchMouse() {
        let location = NSEvent.mouseLocation
        controllers.values.forEach { $0.mouseMoved(to: location) }
        updatePolling()
    }

    /// Da chiamare quando la notch si apre o si chiude senza che il mouse si sia mosso.
    func stateChanged() {
        updatePolling()
    }

    private func handle(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            isMouseDown = true
            dragChangeCount = NSPasteboard(name: .drag).changeCount
            controllers.values.forEach { $0.clicked(at: location) }
            if event.window is NotchPanel { activeController?.handleClickOnClosed() }

        case .rightMouseDown:
            controllers.values.forEach { $0.clicked(at: location) }

        case .leftMouseDragged, .rightMouseDragged:
            if !isDragActive, isMouseDown, NSPasteboard(name: .drag).changeCount != dragChangeCount {
                isDragActive = true
            }
            if isDragActive {
                controllers.values.forEach { $0.dragMoved(to: location) }
            }

        case .leftMouseUp:
            isMouseDown = false
            if isDragActive {
                isDragActive = false
                controllers.values.forEach { $0.dragEnded() }
            }

        default:
            break
        }
        dispatchMouse()
    }

    private func observeSystem() {
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked() }
        })
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenUnlocked() }
        })

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildControllers() }
        })

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Il cambio di spazio si completa un attimo dopo la notifica.
                    self?.updateSuppression()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.updateSuppression() }
                }
            })
        }

        services.media.$nowPlaying
            .map { $0?.isPlaying == true }
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateSuppression() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Schermata di blocco

    private func screenLocked() {
        close()
        guard services.settings.config.behavior.showOnLockScreen else { return }
        controllers.values.forEach { LockScreenSpace.shared.add($0.panel) }
    }

    /// Una finestra uscita da quello spazio non torna da sola negli spazi normali:
    /// il modo più pulito di ripartire è ricreare le notch.
    private func screenUnlocked() {
        guard LockScreenSpace.shared.hasWindows else { return }
        controllers.values.forEach {
            LockScreenSpace.shared.remove($0.panel)
            $0.tearDown()
        }
        controllers.removeAll()
        rebuildControllers()
    }

    // MARK: - Tutto schermo

    private func updateSuppression() {
        let policy = services.settings.config.behavior.hideInFullscreen
        for (id, controller) in controllers {
            let suppressed: Bool
            switch policy {
            case .never:
                suppressed = false
            case .always:
                suppressed = FullscreenDetector.isFullscreen(displayID: id)
            case .mediaOnly:
                // Solo se a tutto schermo c'è proprio l'app che sta riproducendo: sta guardando un film.
                let now = services.media.nowPlaying
                let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                suppressed = now?.isPlaying == true
                    && frontmost != nil
                    && frontmost == now?.sourceBundleID
                    && FullscreenDetector.isFullscreen(displayID: id)
            }
            if controller.state.isSuppressed != suppressed {
                if suppressed { controller.close() }
                controller.state.isSuppressed = suppressed
            }
        }
    }

    // MARK: - Azioni globali

    func toggle() { activeController?.toggle() }
    func open(page: String? = nil) { activeController?.open(page: page) }
    func close() { controllers.values.forEach { $0.close() } }

    func stepPage(_ delta: Int) {
        guard let controller = activeController else { return }
        if !controller.state.isOpen { controller.open() }
        controller.state.step(page: delta, pages: services.settings.config.layout.pages)
    }

    func setPreviewPinned(_ pinned: Bool) {
        controllers.values.forEach { $0.setPinnedForPreview(pinned) }
    }

    // MARK: - Avvisi

    func show(_ peek: NotchPeek) {
        // Durante un video o a tutto schermo gli avvisi non scendono: ciò che serve si vede
        // comunque dall'alone e dai pallini. Un avviso scartato non viene rimandato:
        // tra dieci minuti sarebbe una notizia vecchia.
        guard peek.isForced || !services.isQuietNow else {
            Self.log.notice("avviso scartato per il silenzio: \(peek.group ?? "-", privacy: .public)")
            return
        }
        Self.log.notice("avviso: \(peek.group ?? "-", privacy: .public)")
        if let group = peek.group {
            peekQueue.removeAll { $0.group == group }
            if currentPeek?.group == group {
                presentPeek(peek)
                return
            }
        }
        peekQueue.append(peek)
        pumpPeeks()
    }

    private func pumpPeeks() {
        guard currentPeek == nil, !peekQueue.isEmpty else { return }
        presentPeek(peekQueue.removeFirst())
    }

    private func presentPeek(_ peek: NotchPeek) {
        peekWork?.cancel()
        currentPeek = peek
        controllers.values.forEach { $0.present(peek: peek) }

        schedulePeekEnd(after: peek.duration)
    }

    private func schedulePeekEnd(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Se il mouse è sull'avviso qualcuno lo sta leggendo: resta ancora un po'.
                if self.controllers.values.contains(where: { $0.state.peek != nil && $0.state.isHovering }) {
                    self.schedulePeekEnd(after: 1)
                    return
                }
                self.currentPeek = nil
                self.controllers.values.forEach { $0.present(peek: nil) }
                // Un attimo di respiro fra un avviso e il successivo.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.pumpPeeks() }
            }
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - HUD

    func show(hud: NotchHUD) {
        guard !controllers.isEmpty else { return }
        hudWork?.cancel()
        // Il volume è uno solo, ma l'indicatore compare dove si sta guardando.
        let target = activeController
        controllers.values.forEach { $0.present(hud: $0 === target ? hud : nil) }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.controllers.values.forEach { $0.present(hud: nil) }
            }
        }
        hudWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + services.settings.config.hud.duration, execute: work)
    }
}

// MARK: - Menu

/// Il menu del tasto destro sulla notch. I widget possono averne uno proprio: vince il più interno.
struct NotchContextMenu: View {
    let services: AppServices

    var body: some View {
        Button("Personalizza la notch…") {
            SettingsWindowController.shared.show(section: .layout, services: services)
        }
        Button("Aspetto…") {
            SettingsWindowController.shared.show(section: .appearance, services: services)
        }
        Menu(tr("Profilo")) {
            ForEach(services.allProfiles) { profile in
                Button(profile.name) { services.apply(profile: profile) }
            }
        }
        Divider()
        Button(services.quiet.isOn ? tr("Riattiva gli avvisi") : tr("Silenzia gli avvisi")) {
            services.setQuiet(!services.quiet.isOn)
        }
        Button("Impostazioni…") {
            SettingsWindowController.shared.show(section: nil, services: services)
        }
        if Updater.shared.isAvailable {
            Button("Controlla aggiornamenti…") { Updater.shared.checkForUpdates() }
        }
        Button("Esci da Powered Notch") { NSApp.terminate(nil) }
    }
}

/// Il menu dell'icona nella barra.
@MainActor
enum NotchMenu {
    static func build(services: AppServices) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(ClosureMenuItem(tr("Personalizza la notch…"), symbol: "slider.horizontal.3") {
            SettingsWindowController.shared.show(section: .layout, services: services)
        })
        menu.addItem(ClosureMenuItem(tr("Aspetto…"), symbol: "paintpalette") {
            SettingsWindowController.shared.show(section: .appearance, services: services)
        })

        let profiles = NSMenuItem(title: "Profilo", action: nil, keyEquivalent: "")
        profiles.image = NSImage(systemSymbolName: "person.2", accessibilityDescription: nil)
        let submenu = NSMenu()
        for profile in services.allProfiles {
            let item = ClosureMenuItem(profile.name, symbol: profile.symbol) {
                services.apply(profile: profile)
            }
            item.state = services.settings.config.activeProfileID == profile.id ? .on : .off
            submenu.addItem(item)
        }
        profiles.submenu = submenu
        menu.addItem(profiles)

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(services.quiet.isOn ? tr("Riattiva gli avvisi") : tr("Silenzia gli avvisi"), symbol: services.quiet.isOn ? "bell" : "bell.slash") {
            services.setQuiet(!services.quiet.isOn)
        })
        menu.addItem(ClosureMenuItem(tr("Impostazioni…"), symbol: "gearshape") {
            SettingsWindowController.shared.show(section: nil, services: services)
        })
        if Updater.shared.isAvailable {
            menu.addItem(ClosureMenuItem(tr("Controlla aggiornamenti…"), symbol: "arrow.down.circle") {
                Updater.shared.checkForUpdates()
            })
        }
        menu.addItem(ClosureMenuItem(tr("Riavvia Powered Notch"), symbol: "arrow.clockwise") {
            AppServices.relaunch()
        })
        menu.addItem(ClosureMenuItem(tr("Esci da Powered Notch"), symbol: "power") {
            NSApp.terminate(nil)
        })
        return menu
    }
}

/// NSMenuItem che esegue una chiusura: evita di dover passare da un target per ogni voce.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) non disponibile") }

    @objc private func run() { handler() }
}
