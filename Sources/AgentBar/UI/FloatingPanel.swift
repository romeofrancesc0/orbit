import AppKit
import SwiftUI

/// Stato di presentazione condiviso con SwiftUI: pilota l'animazione di entrata/uscita.
final class PanelPresentation: ObservableObject {
    @Published var visible = false
}

/// Pannello senza cornice: nessuna barra del titolo, nessun bordo di sistema,
/// tutta la grafica è disegnata da SwiftUI.
final class FloatingPanel: NSPanel {
    private let keyable: Bool

    init(keyable: Bool) {
        self.keyable = keyable
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { keyable }
    override var canBecomeMain: Bool { false }
}

/// Gestisce un pannello ancorato all'elemento della barra di stato:
/// posizionamento, ridimensionamento dal contenuto e chiusura animata.
@MainActor
final class PanelHost {
    let panel: FloatingPanel
    let presentation = PanelPresentation()

    private(set) var isVisible = false
    private var anchorRect: NSRect?
    private var anchorScreen: NSScreen?
    private var hideWork: DispatchWorkItem?
    private var lastSize: CGSize = .zero

    init(keyable: Bool, interactive: Bool) {
        panel = FloatingPanel(keyable: keyable)
        panel.ignoresMouseEvents = !interactive
    }

    func setRootView<Content: View>(_ view: Content) {
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
    }

    // MARK: - Presentazione

    func show(anchoredTo button: NSStatusBarButton) {
        hideWork?.cancel()
        hideWork = nil

        guard let window = button.window else { return }
        anchorRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        anchorScreen = window.screen ?? NSScreen.main
        reposition()

        panel.alphaValue = 1
        if panel.canBecomeKey {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        isVisible = true

        // Il passaggio false → true dà a SwiftUI la transizione da animare.
        presentation.visible = false
        DispatchQueue.main.async { [weak self] in
            self?.presentation.visible = true
        }
    }

    func hide(animated: Bool = true) {
        guard isVisible else { return }
        isVisible = false
        presentation.visible = false

        hideWork?.cancel()
        guard animated else {
            panel.orderOut(nil)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isVisible else { return }
            self.panel.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: work)
    }

    /// Chiamato da SwiftUI quando il contenuto cambia altezza.
    func updateSize(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        guard abs(size.width - lastSize.width) > 0.5 || abs(size.height - lastSize.height) > 0.5 else { return }
        lastSize = size
        reposition()
    }

    func contains(screenPoint: NSPoint) -> Bool {
        isVisible && panel.frame.contains(screenPoint)
    }

    private func reposition() {
        guard let anchor = anchorRect, lastSize.width > 1 else {
            if let anchor = anchorRect {
                // Prima misura non ancora arrivata: usa la dimensione naturale.
                let fitting = panel.contentView?.fittingSize ?? NSSize(width: 320, height: 200)
                place(size: fitting, anchor: anchor)
            }
            return
        }
        place(size: lastSize, anchor: anchor)
    }

    private func place(size: CGSize, anchor: NSRect) {
        let screen = anchorScreen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = anchor.midX - size.width / 2
        x = min(max(visible.minX - Theme.shadowPad + 8, x), visible.maxX + Theme.shadowPad - size.width - 8)

        // Il bordo alto della card cade appena sotto la barra dei menu.
        let cardTop = anchor.minY - Theme.menuBarGap
        let y = cardTop + Theme.shadowPad - size.height

        panel.setFrame(NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), display: true)
    }
}

/// Misura la dimensione del contenuto e la propaga al pannello.
struct PanelSizeReader: ViewModifier {
    var onChange: (CGSize) -> Void

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { onChange(geometry.size) }
                    .onChange(of: geometry.size) { _, newValue in onChange(newValue) }
            }
        )
    }
}

extension View {
    func measurePanel(_ onChange: @escaping (CGSize) -> Void) -> some View {
        modifier(PanelSizeReader(onChange: onChange))
    }

    /// Animazione di comparsa condivisa da peek e deck. Propaga anche la
    /// visibilità, così ciò che sta dentro può fermarsi quando è nascosto.
    func panelTransition(_ presentation: PanelPresentation) -> some View {
        modifier(PanelTransition(presentation: presentation))
            .environment(\.panelIsVisible, presentation.visible)
    }
}

struct PanelTransition: ViewModifier {
    @ObservedObject var presentation: PanelPresentation

    func body(content: Content) -> some View {
        content
            .scaleEffect(presentation.visible ? 1 : 0.94, anchor: .top)
            .offset(y: presentation.visible ? 0 : -10)
            .opacity(presentation.visible ? 1 : 0)
            .animation(.spring(response: 0.34, dampingFraction: 0.84), value: presentation.visible)
    }
}
