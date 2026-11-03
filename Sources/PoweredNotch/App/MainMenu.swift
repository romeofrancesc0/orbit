import AppKit

/// Il menu principale. Si vede solo quando è aperta la finestra delle impostazioni, ma
/// serve comunque: senza un menu Modifica, ⌘C e ⌘V non funzionano nei campi di testo.
@MainActor
enum MainMenu {
    static func install(services: AppServices) {
        let main = NSMenu()
        main.addItem(submenu("Powered Notch", application(services: services)))
        main.addItem(submenu(tr("Modifica"), edit))
        let window = self.window
        main.addItem(submenu(tr("Finestra"), window))
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }

    private static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        item.submenu = menu
        return item
    }

    private static func application(services: AppServices) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: tr("Informazioni su Powered Notch"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let settings = ClosureMenuItem(tr("Impostazioni…")) {
            SettingsWindowController.shared.show(section: nil, services: services)
        }
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("Nascondi Powered Notch"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = menu.addItem(withTitle: tr("Nascondi le altre"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: tr("Mostra tutte"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("Esci da Powered Notch"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static var edit: NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: tr("Annulla"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: tr("Ripeti"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("Taglia"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: tr("Copia"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: tr("Incolla"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: tr("Seleziona tutto"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    private static var window: NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: tr("Contrai"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: tr("Chiudi"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }
}
