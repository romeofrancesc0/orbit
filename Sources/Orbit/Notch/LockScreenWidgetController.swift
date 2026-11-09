import AppKit
import Combine
import IOKit.ps
import IOKit.pwr_mgt
import SwiftUI

/// La finestra del lettore sulla schermata di blocco: trasparente, mai in primo piano,
/// e capace di ricevere i click senza togliere la tastiera al campo della password.
final class LockScreenPanel: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        worksWhenModal = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
        canBecomeVisibleWithoutLogin = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Mette il lettore sopra la schermata di blocco quando il Mac si blocca, e lo toglie
/// allo sblocco. La finestra si crea ogni volta: uscita dallo spazio del blocco non
/// tornerebbe da sola negli spazi normali.
@MainActor
final class LockScreenWidgetController {
    private let services: AppServices
    private var panel: LockScreenPanel?
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var showsPreviewWindow = false
    private let displayAwake = DisplayAwakeHold()
    private var releaseWork: DispatchWorkItem?
    /// Fin quando, al massimo, lo schermo resta acceso in questo blocco (nil: senza limite).
    private var awakeDeadline: Date?
    private var deadlineWork: DispatchWorkItem?

    init(services: AppServices) {
        self.services = services
    }

    func start() {
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked() }
        })
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenUnlocked() }
        })

        // `--lock-screen-preview`: la stessa finestra sulla scrivania, per provarla senza bloccare il Mac.
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--lock-screen-preview") }) {
            showsPreviewWindow = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.present(onLockScreen: false) }
        }
    }

    private func screenLocked() {
        guard !showsPreviewWindow else { return }
        present(onLockScreen: true)
    }

    private func screenUnlocked() {
        guard !showsPreviewWindow else { return }
        dismiss()
    }

    private func present(onLockScreen: Bool) {
        dismiss()
        let config = services.settings.config.lockScreen
        guard config.style != .off, let screen = NSScreen.screens.first else { return }

        let placement = Self.placement(for: config, in: screen.frame)
        let panel = LockScreenPanel(frame: placement.frame)
        let root = LockScreenWidgetView(anchor: placement.anchor, scale: placement.scale)
            .orbitEnvironment(services)
        let host = NotchHostingView(rootView: AnyView(root))
        host.frame = NSRect(origin: .zero, size: panel.frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.ignoresMouseEvents = services.media.nowPlaying == nil
        panel.orderFrontRegardless()
        if onLockScreen { LockScreenSpace.shared.add(panel) }
        self.panel = panel

        if onLockScreen, config.keepScreenOn, config.keepScreenOnLimited {
            let deadline = Date().addingTimeInterval(TimeInterval(config.keepScreenOnMinutes * 60))
            awakeDeadline = deadline
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.releaseWork?.cancel()
                self.releaseWork = nil
                self.displayAwake.release()
            }
            deadlineWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + deadline.timeIntervalSinceNow, execute: work)
        }

        // Mentre è in vista segue il brano: i click passano solo se c'è qualcosa da toccare,
        // e il testo si cerca solo adesso, non per ogni brano ascoltato a Mac sbloccato.
        services.media.$nowPlaying
            .sink { [weak self] track in
                guard let self else { return }
                self.panel?.ignoresMouseEvents = track == nil
                if config.showLyrics { self.services.lyrics.load(for: track, moreSources: config.moreLyricsSources) }
                if onLockScreen { self.updateDisplayAwake(playing: track?.isPlaying == true, config: config) }
            }
            .store(in: &cancellables)
    }

    /// A Mac bloccato macOS spegne lo schermo dopo pochi secondi senza input, qualunque sia
    /// l'impostazione di risparmio energia. Mentre la musica suona lo si tiene acceso, così
    /// testo e comandi restano in vista; in pausa da un minuto, o passato il tempo scelto,
    /// si torna alla regola di sempre.
    private func updateDisplayAwake(playing: Bool, config: LockScreenConfig) {
        let inTime = awakeDeadline.map { Date() < $0 } ?? true
        let allowed = inTime && config.keepScreenOn && (config.keepScreenOnBattery || DisplayAwakeHold.isOnACPower)
        if playing, allowed {
            releaseWork?.cancel()
            releaseWork = nil
            displayAwake.hold(reason: "Orbit: music player on the lock screen")
        } else if displayAwake.isHeld, releaseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.releaseWork = nil
                self?.displayAwake.release()
            }
            releaseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (allowed ? 60 : 0), execute: work)
        }
    }

    private func dismiss() {
        cancellables.removeAll()
        releaseWork?.cancel()
        releaseWork = nil
        deadlineWork?.cancel()
        deadlineWork = nil
        awakeDeadline = nil
        displayAwake.release()
        guard let panel else { return }
        LockScreenSpace.shared.remove(panel)
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
    }

    /// Dove sta la finestra: dove l'utente l'ha trascinata, o all'altezza e al lato scelti,
    /// sempre fuori dalle zone dell'orologio e del campo della password.
    static func frame(for config: LockScreenConfig, on screen: NSScreen) -> NSRect {
        frame(for: config, in: screen.frame)
    }

    static func frame(for config: LockScreenConfig, in bounds: CGRect) -> CGRect {
        placement(for: config, in: bounds).frame
    }

    /// In coordinate di AppKit (origine in basso a sinistra). `anchor` dice dove sta la scheda
    /// dentro la finestra, che è un po' più grande: tutta a sinistra quando la finestra tocca il
    /// bordo sinistro della zona libera, tutta a destra sul bordo destro, a metà nel mezzo.
    /// Così la scheda arriva fino ai bordi della zona, e si muove senza salti.
    static func placement(for config: LockScreenConfig, in bounds: CGRect) -> (frame: CGRect, anchor: UnitPoint, scale: CGFloat) {
        let free = LockScreenZones.free(in: bounds)
        // Su uno schermo piccolo il lettore ingrandito non entrerebbe fra l'ora e la password:
        // si rimpicciolisce quanto basta, invece di finire sopra.
        let base = config.style.windowSize
        let fit = base.width > 0 && base.height > 0 ? min(free.width / base.width, free.height / base.height) : 1
        let scale = min(config.clampedScale, fit)
        let size = CGSize(width: (base.width * scale).rounded(), height: (base.height * scale).rounded())

        let centerX: CGFloat
        if let x = config.placementX {
            centerX = bounds.minX + CGFloat(x) * bounds.width
        } else {
            switch config.side {
            case .leading:  centerX = free.minX + size.width / 2
            case .center:   centerX = bounds.midX
            case .trailing: centerX = free.maxX - size.width / 2
            }
        }
        let centerY: CGFloat
        if let y = config.placementY {
            centerY = bounds.maxY - CGFloat(y) * bounds.height
        } else {
            switch config.position {
            case .upper:  centerY = free.maxY - size.height / 2
            case .center: centerY = free.midY
            case .lower:  centerY = free.minY + size.height / 2
            }
        }

        func clamp(_ center: CGFloat, _ length: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            guard high - low > length else { return (low + high) / 2 - length / 2 }
            return min(max(center - length / 2, low), high - length)
        }
        let x = clamp(centerX, size.width, free.minX, free.maxX).rounded()
        let y = clamp(centerY, size.height, free.minY, free.maxY).rounded()
        let frame = CGRect(x: x, y: y, width: size.width, height: size.height)

        let spanX = free.width - size.width
        let spanY = free.height - size.height
        let anchor = UnitPoint(
            x: spanX > 1 ? min(1, max(0, (frame.minX - free.minX) / spanX)) : 0.5,
            y: spanY > 1 ? min(1, max(0, (free.maxY - frame.maxY) / spanY)) : 0.5
        )
        return (frame, anchor, scale)
    }
}

/// Le zone della schermata di blocco che il lettore non deve coprire: in alto data e ora,
/// in basso l'utente e il campo della password, e un piccolo margine ai lati.
enum LockScreenZones {
    static let top: CGFloat = 0.27
    static let bottom: CGFloat = 0.18
    static let side: CGFloat = 0.02

    /// La zona libera, in coordinate di AppKit.
    static func free(in bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX + bounds.width * side,
            y: bounds.minY + bounds.height * bottom,
            width: bounds.width * (1 - 2 * side),
            height: bounds.height * (1 - top - bottom)
        )
    }
}

/// Tiene acceso lo schermo come `caffeinate -d`: un'asserzione di risparmio energia che
/// impedisce lo spegnimento per inattività, e niente altro (il Mac resta bloccato).
@MainActor
final class DisplayAwakeHold {
    private var assertion = IOPMAssertionID(0)
    private(set) var isHeld = false

    func hold(reason: String) {
        guard !isHeld else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertion
        )
        isHeld = result == kIOReturnSuccess
    }

    func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertion)
        isHeld = false
    }

    static var isOnACPower: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return true }
        return (type as String) == kIOPMACPowerKey
    }
}
