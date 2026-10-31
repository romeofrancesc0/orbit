import AppKit
import Combine
import SwiftUI

/// Collega l'elemento della barra ai due pannelli: anteprima all'hover, deck al click.
@MainActor
final class StatusItemController {
    private let store: SessionStore
    private let statusItem: NSStatusItem
    private let itemView = StatusItemView()
    private let iconHost: NSHostingView<StatusIconView>

    private let peek = PanelHost(keyable: false, interactive: false)
    private let deck = PanelHost(keyable: true, interactive: true)

    private var hoverWork: DispatchWorkItem?
    private var peekHideWork: DispatchWorkItem?
    private var peekWatchdog: Timer?
    private var suppressPeek = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    init(store: SessionStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: 36)
        iconHost = NSHostingView(rootView: StatusIconView(store: store))

        configureStatusItem()
        configurePanels()

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateLength() }
            .store(in: &cancellables)

        observeAppActivation()
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    /// Se il fuoco passa a un'altra app — perché hai premuto "Vai", o per
    /// qualunque altra strada — il pannello non deve restare aperto alle spalle.
    private func observeAppActivation() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated {
                self?.dismissPanels()
            }
        }
    }

    private func dismissPanels() {
        hoverWork?.cancel()
        peek.hide(animated: false)
        stopPeekWatchdog()
        if deck.isVisible { closeDeck() }
    }

    // MARK: - Barra di stato

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.image = nil
        button.title = ""

        iconHost.translatesAutoresizingMaskIntoConstraints = false
        itemView.translatesAutoresizingMaskIntoConstraints = false
        itemView.addSubview(iconHost)
        button.addSubview(itemView)

        NSLayoutConstraint.activate([
            itemView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            itemView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            itemView.topAnchor.constraint(equalTo: button.topAnchor),
            itemView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            iconHost.centerXAnchor.constraint(equalTo: itemView.centerXAnchor),
            iconHost.centerYAnchor.constraint(equalTo: itemView.centerYAnchor)
        ])

        itemView.onHover = { [weak self] inside in
            inside ? self?.hoverBegan() : self?.hoverEnded()
        }
        itemView.onLeftClick = { [weak self] in self?.toggleDeck() }
        itemView.onRightClick = { [weak self] in self?.showContextMenu() }

        updateLength()
    }

    private func updateLength() {
        let width = max(30, iconHost.fittingSize.width + 8)
        if abs(statusItem.length - width) > 0.5 {
            statusItem.length = width
        }
    }

    // MARK: - Pannelli

    private func configurePanels() {
        peek.setRootView(
            PeekView(store: store, presentation: peek.presentation)
                .measurePanel { [weak peek] size in peek?.updateSize(size) }
        )

        deck.setRootView(
            DeckView(
                store: store,
                presentation: deck.presentation,
                onClose: { [weak self] in self?.closeDeck() }
            )
            .measurePanel { [weak deck] size in deck?.updateSize(size) }
        )
    }

    // MARK: - Hover

    private func hoverBegan() {
        peekHideWork?.cancel()
        guard !deck.isVisible, !suppressPeek else { return }
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            guard !self.deck.isVisible, !self.suppressPeek else { return }
            self.store.setPanelOpen(true)
            self.peek.show(anchoredTo: button)
            self.startPeekWatchdog()
        }
        hoverWork = work
        // Piccolo ritardo: passare sopra l'icona di sfuggita non apre nulla.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13, execute: work)
    }

    private func hoverEnded() {
        suppressPeek = false
        hoverWork?.cancel()
        peekHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.peek.hide()
            self.stopPeekWatchdog()
            if !self.deck.isVisible { self.store.setPanelOpen(false) }
        }
        peekHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: work)
    }

    /// Rete di sicurezza: se l'evento di uscita non arriva (cambio di Spazio,
    /// mouse teletrasportato, tracking area invalidata) l'anteprima resterebbe
    /// appesa sullo schermo. Qui si controlla dov'è davvero il puntatore.
    private func startPeekWatchdog() {
        stopPeekWatchdog()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.verifyPeekStillHovered() }
        }
        RunLoop.main.add(timer, forMode: .common)
        peekWatchdog = timer
    }

    private func stopPeekWatchdog() {
        peekWatchdog?.invalidate()
        peekWatchdog = nil
    }

    private func verifyPeekStillHovered() {
        guard peek.isVisible else {
            stopPeekWatchdog()
            return
        }
        guard let frame = statusItemFrame else { return }
        if !frame.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) {
            hoverEnded()
        }
    }

    // MARK: - Deck

    private func toggleDeck() {
        deck.isVisible ? closeDeck() : openDeck()
    }

    private func openDeck() {
        guard let button = statusItem.button else { return }
        hoverWork?.cancel()
        peek.hide(animated: false)
        stopPeekWatchdog()
        suppressPeek = true
        store.setPanelOpen(true)
        deck.show(anchoredTo: button)
        installMonitors()
    }

    private func closeDeck() {
        deck.hide()
        removeMonitors()
        store.setPanelOpen(false)
    }

    /// Frame dell'elemento in coordinate schermo: serve a non chiudere il deck
    /// con lo stesso click che poi lo riaprirebbe.
    private var statusItemFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func installMonitors() {
        removeMonitors()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.handleOutsideClick(at: NSEvent.mouseLocation) }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in self?.handleOutsideClick(at: NSEvent.mouseLocation) }
            return event
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // esc
                Task { @MainActor in self?.closeDeck() }
                return nil
            }
            return event
        }
    }

    private func handleOutsideClick(at point: NSPoint) {
        guard deck.isVisible else { return }
        if deck.contains(screenPoint: point) { return }
        if let frame = statusItemFrame, frame.insetBy(dx: -2, dy: -2).contains(point) { return }
        closeDeck()
    }

    private func removeMonitors() {
        for monitor in [globalMonitor, localMonitor, keyMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitor = nil
        localMonitor = nil
        keyMonitor = nil
    }

    // MARK: - Menu di emergenza (click destro)

    private func showContextMenu() {
        peek.hide(animated: false)
        let menu = NSMenu()
        menu.addItem(withTitle: "Aggiorna adesso", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Apri config.json", action: #selector(openConfig), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Esci da AgentBar", action: #selector(quit), keyEquivalent: "q").target = self

        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    @objc private func refreshNow() { store.refresh() }
    @objc private func openConfig() { store.openConfigFile() }
    @objc private func quit() { NSApp.terminate(nil) }
}
