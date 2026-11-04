import AppKit
import Combine
import Sparkle

/// Aggiornamenti automatici, con Sparkle.
///
/// Una volta al giorno l'app legge `appcast.xml` dall'ultima release su GitHub (SUFeedURL in
/// Info.plist). Se c'è una versione più nuova la scarica, ne verifica la firma EdDSA con la chiave
/// pubblica SUPublicEDKey e la installa al posto di questa: niente da riscaricare dal sito, e
/// niente "Apri comunque" (il file non arriva dal browser, quindi non è in quarantena).
/// Il feed e le firme li prepara `scripts/release.sh`.
@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecks = true {
        didSet {
            guard let updater = controller?.updater, updater.automaticallyChecksForUpdates != automaticallyChecks else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecks
        }
    }

    private var controller: SPUStandardUpdaterController?
    private var cancellables: Set<AnyCancellable> = []

    /// La versione installata, come la vede chi usa l'app: "1.0.0".
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    /// Senza feed (o in modalità demo) non si controlla niente.
    var isAvailable: Bool { controller != nil }

    /// Solo le copie uscite da `scripts/release.sh` hanno un numero di build vero (il conteggio dei
    /// commit). Quelle di `build.sh` restano a 1: non devono rimpiazzarsi con la versione pubblicata.
    private var isReleaseBuild: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap(Int.init).map { $0 > 1 } ?? false
    }

    func start(enabled: Bool) {
        guard enabled, isReleaseBuild, controller == nil,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        automaticallyChecks = updater.automaticallyChecksForUpdates
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
            .store(in: &cancellables)
    }

    /// "Controlla aggiornamenti…": la finestra di Sparkle risponde anche se non c'è niente di nuovo.
    func checkForUpdates() {
        guard let controller else { return }
        // L'app vive nella notch, senza Dock: va portata davanti, o la finestra finirebbe dietro le altre.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    /// Un'app senza Dock non deve rubare il primo piano per un controllo programmato:
    /// Sparkle lascia a noi il modo di farlo notare, e la notch è il posto giusto.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let version = update.displayVersionString
        let userInitiated = state.userInitiated
        MainActor.assumeIsolated {
            // Se Sparkle mostra la finestra adesso, l'app va davanti: senza Dock finirebbe dietro le altre.
            if handleShowingUpdate || userInitiated { NSApp.activate(ignoringOtherApps: true) }
            guard !userInitiated else { return }
            AppServices.shared.notch.show(NotchPeek(
                title: tr("Aggiornamento disponibile"),
                subtitle: "Orbit \(version)",
                icon: .symbol("arrow.down.circle.fill"),
                tint: .accentColor,
                duration: 10,
                group: "update",
                actionLabel: tr("Vedi"),
                action: { Updater.shared.checkForUpdates() }
            ))
        }
    }
}
