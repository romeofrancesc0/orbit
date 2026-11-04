import AppKit
import SwiftUI

/// La finestra che ospita la notch: trasparente, sempre sopra la barra dei menu,
/// presente in tutti gli spazi e capace di prendere la tastiera senza rubare il
/// primo piano all'app in uso. Ha dimensione fissa (quella massima della notch
/// aperta): a cambiare è la forma disegnata dentro, non la finestra.
final class NotchPanel: NSPanel {
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
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Un campo di testo in una finestra non attiva scarterebbe il primo click: si
    /// prende la tastiera prima, ma solo se sotto il mouse c'è davvero qualcosa che la vuole.
    /// Un click su un pulsante non deve togliere il fuoco all'app in uso.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow,
           let content = contentView,
           let hit = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow),
           hit.needsPanelToBecomeKey {
            makeKey()
        }
        super.sendEvent(event)
    }

    /// AppKit spinge le finestre sotto la barra dei menu: qui è proprio dove deve stare.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Vista radice: accetta il primo click anche se la finestra non è attiva.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) non disponibile") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Le misure della notch su uno schermo: quella vera se c'è, altrimenti una virtuale.
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var hasHardwareNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat

    /// `--virtual-notch`: fa finta di essere su uno schermo esterno, per provare quel caso.
    private static let forcesVirtualNotch = CommandLine.arguments.contains("--virtual-notch")

    @MainActor
    static func of(_ screen: NSScreen, behavior: BehaviorConfig) -> NotchGeometry {
        let frame = screen.frame
        if !forcesVirtualNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            return NotchGeometry(
                screenFrame: frame,
                hasHardwareNotch: true,
                notchWidth: frame.width - left.width - right.width,
                notchHeight: screen.safeAreaInsets.top
            )
        }
        // Schermo esterno: la notch è disegnata, alta come la barra dei menu.
        let menuBar = frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(
            screenFrame: frame,
            hasHardwareNotch: false,
            notchWidth: behavior.virtualNotchWidth,
            notchHeight: menuBar > 12 ? min(menuBar, 34) : 26
        )
    }

    /// Il rettangolo in coordinate di schermo occupato da una notch larga e alta così.
    func screenRect(size: CGSize) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
