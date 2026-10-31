import AppKit
import Combine
import SwiftUI

/// Una notch su uno schermo: tiene la finestra, decide quando riceve il mouse e
/// quando aprirsi e chiudersi.
@MainActor
final class NotchController {
    let displayID: CGDirectDisplayID
    let state: NotchState
    let panel: NotchPanel

    private let services: AppServices
    private let actions = NotchActions()
    private var hostingView: NotchHostingView<AnyView>!
    private var hoverWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var mouseInside = false
    /// Margine di comodo attorno alla notch chiusa: è sottile e va presa con un gesto veloce.
    private let hoverMargin: CGFloat = 6

    private var config: LunettaConfig { services.settings.config }

    init(screen: NSScreen, displayID: CGDirectDisplayID, services: AppServices) {
        self.displayID = displayID
        self.services = services
        let geometry = NotchGeometry.of(screen, behavior: services.settings.config.behavior)
        state = NotchState(geometry: geometry)
        panel = NotchPanel(frame: Self.panelFrame(geometry: geometry, config: services.settings.config))

        let root = NotchRootView(state: state)
            .lunettaEnvironment(services)
            .environmentObject(actions)
        hostingView = NotchHostingView(rootView: AnyView(root))
        hostingView.frame = NSRect(origin: .zero, size: panel.frame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        hostingView.onKeyEscape = { [weak self] in self?.close() }

        actions.closeHandler = { [weak self] in self?.close() }
        actions.holdHandler = { [weak self] reason, active in
            guard let self else { return }
            if active {
                self.state.hold(reason)
            } else {
                self.state.release(reason)
                self.reevaluate()
            }
        }
        actions.settingsHandler = { [weak self] section in
            self?.close()
            SettingsWindowController.shared.show(section: section, services: services)
        }

        state.onOpenChange = { [weak self] open in
            guard let self else { return }
            self.services.notchOpenChanged()
            self.updateMouseAcceptance()
            if open, self.config.behavior.haptics {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
            if !open, self.panel.isKeyWindow { self.panel.resignKey() }
        }

        applyBehavior()
        panel.orderFrontRegardless()
    }

    func tearDown() {
        hoverWork?.cancel()
        closeWork?.cancel()
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: - Finestra

    /// La finestra copre la notch alla sua massima estensione, più lo spazio per l'ombra.
    private static func panelFrame(geometry: NotchGeometry, config: LunettaConfig) -> NSRect {
        let pad: CGFloat = 70
        let tallest = max(
            CGFloat(config.appearance.openHeight),
            config.layout.pages.compactMap { $0.height.map { CGFloat($0) } }.max() ?? 0
        )
        let width = max(CGFloat(config.appearance.openWidth), 560) + pad * 2
        let height = max(tallest, 140) + pad
        return NSRect(
            x: geometry.screenFrame.midX - width / 2,
            y: geometry.screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    func update(screen: NSScreen) {
        state.geometry = NotchGeometry.of(screen, behavior: config.behavior)
        applyFrame()
    }

    func applyConfig() {
        state.geometry.notchWidth = state.geometry.hasHardwareNotch ? state.geometry.notchWidth : CGFloat(config.behavior.virtualNotchWidth)
        applyFrame()
        applyBehavior()
        // Una pagina eliminata non può restare selezionata.
        if let selected = state.selectedPageID, !config.layout.pages.contains(where: { $0.id == selected }) {
            state.selectedPageID = config.layout.pages.first?.id
        }
    }

    private func applyFrame() {
        let frame = Self.panelFrame(geometry: state.geometry, config: config)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    private func applyBehavior() {
        panel.sharingType = config.behavior.hideFromScreenCapture ? .none : .readOnly
        panel.canBecomeVisibleWithoutLogin = config.behavior.showOnLockScreen
    }

    func setPinnedForPreview(_ pinned: Bool) {
        state.isPinnedForPreview = pinned
        if pinned {
            open()
        } else {
            reevaluate()
        }
    }

    // MARK: - Mouse

    /// Il rettangolo su cui la notch reagisce adesso, in coordinate di schermo.
    private var interactiveRect: CGRect {
        let size = state.size(config: config)
        var rect = state.geometry.screenRect(size: size)
        if !state.isOpen, !config.layout.symmetricWings {
            rect.origin.x += (state.trailingWidth - state.leadingWidth) / 2
        }
        if !state.isOpen {
            rect = rect.insetBy(dx: -hoverMargin, dy: 0)
            rect.origin.y -= hoverMargin
            rect.size.height += hoverMargin
        }
        return rect
    }

    /// Chiamata a ogni movimento del mouse dal monitor globale.
    func mouseMoved(to location: NSPoint, isDragging: Bool) {
        guard !state.isSuppressed else { return }
        let inside = interactiveRect.contains(location)
        if inside != mouseInside {
            mouseInside = inside
            inside ? mouseEntered() : mouseExited()
        }
        updateMouseAcceptance()
        _ = isDragging
    }

    /// Per trascinare un file la finestra deve poter ricevere eventi anche se si
    /// sta arrivando da fuori: la si sveglia appena il trascinamento si avvicina.
    func dragMoved(to location: NSPoint) {
        guard !state.isSuppressed, config.behavior.openShelfOnDrag else { return }
        let size = state.size(config: config)
        let activation = state.geometry.screenRect(size: size).insetBy(dx: -50, dy: 0).insetBy(dx: 0, dy: -30)
        guard activation.contains(location) else { return }
        panel.ignoresMouseEvents = false
        if !state.isOpen {
            let page = config.layout.pages.first { $0.containsWidget("shelf") }
            open(page: page?.id)
        }
    }

    func dragEnded() {
        updateMouseAcceptance()
        reevaluate()
    }

    func clicked(at location: NSPoint) {
        guard state.isOpen, config.behavior.closeOnClickOutside, !state.isPinnedForPreview else { return }
        guard !interactiveRect.contains(location) else { return }
        state.holds.forEach { state.release($0) }
        close()
    }

    /// La finestra lascia passare i click ovunque tranne che sulla notch.
    private func updateMouseAcceptance() {
        if panel.ignoresMouseEvents == mouseInside { panel.ignoresMouseEvents = !mouseInside }
    }

    private func mouseEntered() {
        closeWork?.cancel()
        closeWork = nil
        state.isHovering = true

        // Un avviso resta lì finché il mouse ci sta sopra: aprire la notch adesso
        // lo farebbe sparire proprio mentre si sta per cliccarlo.
        guard !state.isOpen, state.peek == nil, config.behavior.openOnHover else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mouseInside else { return }
            self.open()
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + config.behavior.hoverDelay, execute: work)
    }

    private func mouseExited() {
        hoverWork?.cancel()
        hoverWork = nil
        state.isHovering = false
        scheduleCloseIfNeeded()
    }

    private func scheduleCloseIfNeeded() {
        guard state.isOpen, config.behavior.closeOnMouseLeave, !state.isHeld else { return }
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.mouseInside, !self.state.isHeld, !self.services.isDragActive else { return }
            self.close()
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + config.behavior.closeDelay, execute: work)
    }

    /// Una trattenuta è finita: se il mouse è già altrove, è ora di chiudere.
    private func reevaluate() {
        if !mouseInside { scheduleCloseIfNeeded() }
    }

    // MARK: - Apertura

    func open(page: String? = nil) {
        guard !state.isSuppressed else { return }
        closeWork?.cancel()
        state.open(page: page, config: config, hasAttention: services.sessions.attentionCount > 0)
    }

    func close() {
        hoverWork?.cancel()
        closeWork?.cancel()
        state.close()
        updateMouseAcceptance()
    }

    func toggle() {
        state.isOpen ? close() : open()
    }

    /// Il click sulla notch chiusa la apre anche senza aspettare il ritardo.
    func handleClickOnClosed() {
        guard !state.isOpen, state.peek == nil else { return }
        hoverWork?.cancel()
        open()
    }

    // MARK: - Gesti

    private var scrollAccumulated = CGSize.zero
    private var gestureConsumed = false

    /// Due dita verso il basso aprono, di lato cambiano pagina, verso l'alto sulla testata chiudono.
    func handleScroll(_ event: NSEvent) {
        guard config.behavior.gestures else { return }
        if event.phase == .began {
            scrollAccumulated = .zero
            gestureConsumed = false
        }
        guard !gestureConsumed else { return }
        scrollAccumulated.width += event.scrollingDeltaX
        scrollAccumulated.height += event.scrollingDeltaY

        if !state.isOpen {
            if scrollAccumulated.height > 18, abs(scrollAccumulated.height) > abs(scrollAccumulated.width) {
                gestureConsumed = true
                open()
            }
            return
        }

        if abs(scrollAccumulated.width) > 46, abs(scrollAccumulated.width) > abs(scrollAccumulated.height) * 1.6 {
            gestureConsumed = true
            state.step(page: scrollAccumulated.width < 0 ? 1 : -1, pages: config.layout.pages)
            if config.behavior.haptics {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            return
        }

        let location = NSEvent.mouseLocation
        let headerBottom = state.geometry.screenFrame.maxY - max(state.geometry.notchHeight, 30)
        if scrollAccumulated.height < -30, location.y > headerBottom {
            gestureConsumed = true
            close()
        }
    }

    // MARK: - Avvisi e HUD

    func present(peek: NotchPeek?) {
        guard !state.isOpen || peek == nil else { return }
        state.peek = peek
    }

    func present(hud: NotchHUD?) {
        state.hud = hud
    }
}
