import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private let store = SessionStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(store: store)
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
