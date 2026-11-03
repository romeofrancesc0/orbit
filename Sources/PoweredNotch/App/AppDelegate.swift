import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Due notch sovrapposte sarebbero un disastro: se Powered Notch è già aperta, questa copia
    /// (lanciata per esempio da un link `powerednotch://`) inoltra ciò che ha ricevuto e si chiude.
    private var isSecondaryInstance = false
    private static let forwardNotification = Notification.Name("com.francescoromeo.powerednotch.forward-url")

    @MainActor
    func applicationWillFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != NSRunningApplication.current }
        isSecondaryInstance = !others.isEmpty
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isSecondaryInstance else {
            // Si lascia il tempo ad AppKit di consegnare l'eventuale URL.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
            return
        }

        let services = AppServices.shared
        services.start()

        DistributedNotificationCenter.default().addObserver(
            forName: Self.forwardNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let raw = note.object as? String, let url = URL(string: raw) else { return }
            MainActor.assumeIsolated { URLRouter.handle(url) }
        }

        if !services.settings.config.onboardingDone, !services.isDemo {
            // La schermata iniziale spiega già il conflitto con Boring Notch.
            SettingsWindowController.shared.show(section: .welcome, services: services)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { services.warnAboutConflicts() }
        }
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        guard !isSecondaryInstance else { return }
        AppServices.shared.shutdown()
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        if isSecondaryInstance {
            urls.forEach {
                DistributedNotificationCenter.default().postNotificationName(
                    Self.forwardNotification,
                    object: $0.absoluteString,
                    userInfo: nil,
                    deliverImmediately: true
                )
            }
            return
        }
        urls.forEach { URLRouter.handle($0) }
    }

    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !isSecondaryInstance else { return false }
        // Riaprire l'app dal Finder o da Spotlight mostra le impostazioni: non ha altre finestre.
        if !flag { SettingsWindowController.shared.show(section: nil, services: AppServices.shared) }
        return true
    }
}

/// `powerednotch://…`: il modo con cui script, Comandi rapidi e altre app parlano alla notch.
/// Espone solo azioni innocue: niente che esegua comandi o tocchi file.
@MainActor
enum URLRouter {
    static func handle(_ url: URL) {
        guard url.scheme == "powerednotch" else { return }
        let services = AppServices.shared
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }

        switch url.host {
        case "open":
            services.notch.open(page: value("page"))
        case "close":
            services.notch.close()
        case "toggle":
            services.notch.toggle()
        case "settings":
            let section = value("section").flatMap(SettingsSection.init(rawValue:))
            SettingsWindowController.shared.show(section: section, services: services)
        case "peek":
            services.notch.show(NotchPeek(
                title: value("title") ?? "Powered Notch",
                subtitle: value("subtitle"),
                icon: .symbol(value("symbol") ?? "bell.fill"),
                tint: Color(hexString: value("tint")),
                duration: value("duration").flatMap(Double.init) ?? 4,
                group: value("group")
            ))
        case "hud":
            let level = value("level").flatMap(Double.init) ?? 0.5
            let kind: NotchHUD.Kind
            switch value("kind") {
            case "brightness": kind = .brightness
            case "keyboard":   kind = .keyboard
            default:           kind = .volume
            }
            services.notch.show(hud: NotchHUD(kind: kind, level: level))
        case "quiet":
            // `on=1` silenzia, `on=0` riattiva, senza parametro inverte.
            let target = value("on").map { $0 == "1" || $0 == "true" } ?? !services.quiet.isOn
            services.setQuiet(target)
        case "profile":
            if let id = value("id") { _ = services.applyProfile(id: id) }
        case "language":
            // A language code ("it", "en", "es", "fr", "de") or "system".
            if let id = value("id"), let language = AppLanguage.allCases.first(where: { $0.rawValue == id || $0.code == id }) {
                services.settings.update { $0.language = language }
            }
        case "theme":
            if let preset = value("id").flatMap(ThemePreset.preset) {
                services.settings.update { preset.apply(to: &$0.appearance) }
            }
        default:
            break
        }
    }
}
