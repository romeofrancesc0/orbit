import AppKit
import SwiftUI

/// Vista AppKit dentro l'elemento della barra: intercetta hover e click,
/// mentre il disegno è delegato a SwiftUI.
final class StatusItemView: NSView {
    var onHover: ((Bool) -> Void)?
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { onLeftClick?() }
    override func rightMouseDown(with event: NSEvent) { onRightClick?() }

    /// Tutti gli eventi arrivano qui, non alla vista SwiftUI sottostante.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }
}

/// L'icona nella barra dei menu: un blocco di codice che "scrive" quando un
/// agent sta lavorando, più il conteggio delle sessioni vive.
struct StatusIconView: View {
    @ObservedObject var store: SessionStore

    /// Fotogramma corrente della "scrittura". È volutamente discreto: una
    /// animazione interpolata qui costringerebbe a ridisegnare i tracciati a
    /// ogni frame dello schermo, ed è il tipo di spreco che in barra si paga
    /// sempre, anche quando nessuno guarda.
    @State private var frame = 0
    private let ticker = Timer.publish(every: 0.42, on: .main, in: .common).autoconnect()

    /// Larghezze delle tre righe, in frazione dello spazio interno del glifo.
    private static let frames: [[CGFloat]] = [
        [0.87, 0.51, 0.67],
        [0.56, 0.87, 0.67],
        [0.72, 0.62, 0.87]
    ]

    private var status: SessionStatus? { store.aggregateStatus }

    private var tint: Color {
        guard let status, status.animates else { return .primary.opacity(0.82) }
        return status.tint
    }

    var body: some View {
        HStack(spacing: 4) {
            glyph
            if store.config.showCountInMenuBar, store.badgeCount > 0 {
                Text("\(store.badgeCount)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(needsAttention ? tint : .primary.opacity(0.9))
            }
        }
        .padding(.horizontal, needsAttention ? 5 : 3)
        .frame(height: 22)
        .background(
            Capsule(style: .continuous)
                .fill(needsAttention ? tint.opacity(0.16) : .clear)
        )
        .onReceive(ticker) { _ in
            guard store.workingCount > 0 else {
                if frame != 0 { frame = 0 }
                return
            }
            frame = (frame + 1) % StatusIconView.frames.count
        }
    }

    private var needsAttention: Bool { status?.needsYou ?? false }

    private var glyph: some View {
        AgentGlyph(height: 14.5, tint: tint.opacity(0.9), bars: StatusIconView.frames[frame])
            .overlay(alignment: .topTrailing) {
                if needsAttention {
                    Circle()
                        .fill(tint)
                        .frame(width: 5, height: 5)
                        .offset(x: 2.5, y: -2)
                        .shadow(color: tint.opacity(0.8), radius: 2)
                }
            }
    }
}
