import AppKit
import Combine

/// L'icona nella barra dei menu: facoltativa, per chi vuole un appiglio sempre visibile.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    private var item: NSStatusItem?
    private weak var services: AppServices?
    private var cancellable: AnyCancellable?

    func start(services: AppServices) {
        self.services = services
        update()
        cancellable = services.sessions.summary.$dots
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateTitle() }
            }
    }

    func update() {
        guard let services else { return }
        if services.settings.config.behavior.showMenuBarIcon {
            if item == nil { install() }
            updateTitle()
        } else if let existing = item {
            NSStatusBar.system.removeStatusItem(existing)
            item = nil
        }
    }

    private func install() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.glyph
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        item = statusItem
    }

    private func updateTitle() {
        guard let services, let button = item?.button else { return }
        let count = services.sessions.summary.dots.count
        let show = services.settings.config.behavior.menuBarShowsAgentCount && count > 0
        let title = show ? " \(count)" : ""
        if button.title != title { button.title = title }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let services else { return }
        menu.removeAllItems()
        let toggle = ClosureMenuItem("Apri la notch", symbol: "chevron.down.circle") {
            services.notch.open()
        }
        menu.addItem(toggle)
        menu.addItem(.separator())
        for entry in NotchMenu.build(services: services).items {
            entry.menu?.removeItem(entry)
            menu.addItem(entry)
        }
    }

    /// La mezzaluna del marchio, disegnata come immagine modello: il sistema la colora da solo.
    static var glyph: NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let path = NSBezierPath()
            let radius = rect.width * 0.46
            let center = NSPoint(x: rect.midX, y: rect.midY + radius * 0.48)
            path.appendArc(withCenter: center, radius: radius, startAngle: 180, endAngle: 360, clockwise: false)
            path.close()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
