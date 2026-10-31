import AppKit
import Combine
import SwiftUI

/// Avviso temporaneo che scende dalla notch chiusa.
struct NotchPeek: Identifiable, Equatable {
    enum Icon: Equatable {
        case symbol(String)
        case artwork(NSImage)
        case status(SessionStatus)
    }

    let id = UUID()
    var title: String
    var subtitle: String?
    var icon: Icon
    var tint: Color?
    var duration: TimeInterval
    /// Chiave che raggruppa avvisi dello stesso tipo: il più recente sostituisce il precedente.
    var group: String?
    var actionLabel: String?
    var action: (() -> Void)?

    static func == (lhs: NotchPeek, rhs: NotchPeek) -> Bool { lhs.id == rhs.id }
}

/// Indicatore di volume, luminosità e simili.
struct NotchHUD: Equatable {
    enum Kind: Equatable {
        case volume, brightness, keyboard

        var label: String {
            switch self {
            case .volume:     "Volume"
            case .brightness: "Luminosità"
            case .keyboard:   "Tastiera"
            }
        }

        func symbol(level: Double, muted: Bool) -> String {
            switch self {
            case .volume:
                if muted || level <= 0 { return "speaker.slash.fill" }
                if level < 0.34 { return "speaker.wave.1.fill" }
                if level < 0.67 { return "speaker.wave.2.fill" }
                return "speaker.wave.3.fill"
            case .brightness:
                return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
            case .keyboard:
                return level <= 0 ? "light.min" : "light.max"
            }
        }
    }

    var kind: Kind
    var level: Double
    var muted = false
    var stamp = UUID()
}

/// Lo stato di una notch su uno schermo. I modelli dei contenuti (musica, agenti…)
/// sono condivisi fra gli schermi; questo no: ogni notch apre e chiude per conto suo.
@MainActor
final class NotchState: ObservableObject {
    @Published var geometry: NotchGeometry
    @Published private(set) var isOpen = false
    @Published var isHovering = false
    @Published var peek: NotchPeek?
    @Published var hud: NotchHUD?
    @Published var selectedPageID: String?
    /// La pagina si è spostata in avanti: serve a scegliere il verso della transizione.
    @Published private(set) var pageDirection: Edge = .trailing
    @Published private(set) var leadingWidth: CGFloat = 0
    @Published private(set) var trailingWidth: CGFloat = 0
    /// Un trascinamento di file è sopra la notch.
    @Published var isDropTargeted = false
    /// Nascosta perché un'app è a tutto schermo.
    @Published var isSuppressed = false
    /// Tenuta aperta dalle impostazioni, per vedere subito cosa cambia.
    @Published var isPinnedForPreview = false

    /// Motivi per cui la notch non deve richiudersi: un menu aperto, un testo in scrittura…
    private(set) var holds: Set<String> = []
    private var lastPageID: String?

    var onOpenChange: ((Bool) -> Void)?

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    // MARK: - Ali

    /// Scrivere un valore pubblicato ridisegna anche se è identico: si scrive solo se cambia.
    func setLeadingWidth(_ width: CGFloat) {
        if abs(width - leadingWidth) > 0.5 { leadingWidth = width }
    }

    func setTrailingWidth(_ width: CGFloat) {
        if abs(width - trailingWidth) > 0.5 { trailingWidth = width }
    }

    // MARK: - Apertura

    func open(page requested: String? = nil, config: LunettaConfig, hasAttention: Bool) {
        let target = requested ?? startPage(config: config, hasAttention: hasAttention)
        if let target { selectPage(target, pages: config.layout.pages, animated: isOpen) }
        guard !isOpen else { return }
        isOpen = true
        peek = nil
        onOpenChange?(true)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        holds.removeAll()
        isDropTargeted = false
        onOpenChange?(false)
    }

    private func startPage(config: LunettaConfig, hasAttention: Bool) -> String? {
        let pages = config.layout.pages
        switch config.layout.startMode {
        case .first:
            return pages.first?.id
        case .last:
            return lastPageID.flatMap { id in pages.contains { $0.id == id } ? id : nil } ?? pages.first?.id
        case .specific:
            return config.layout.startPageID.flatMap { id in pages.contains { $0.id == id } ? id : nil } ?? pages.first?.id
        case .smart:
            if hasAttention, let page = pages.first(where: { $0.containsWidget("agents") }) { return page.id }
            return lastPageID.flatMap { id in pages.contains { $0.id == id } ? id : nil } ?? pages.first?.id
        }
    }

    // MARK: - Pagine

    func selectPage(_ id: String, pages: [PageConfig], animated: Bool = true) {
        guard pages.contains(where: { $0.id == id }) else { return }
        if let current = selectedPageID,
           let from = pages.firstIndex(where: { $0.id == current }),
           let to = pages.firstIndex(where: { $0.id == id }) {
            pageDirection = to >= from ? .trailing : .leading
        }
        selectedPageID = id
        lastPageID = id
    }

    func step(page delta: Int, pages: [PageConfig]) {
        guard !pages.isEmpty else { return }
        let index = pages.firstIndex { $0.id == selectedPageID } ?? 0
        let next = (index + delta + pages.count) % pages.count
        selectPage(pages[next].id, pages: pages)
    }

    func currentPage(in pages: [PageConfig]) -> PageConfig? {
        pages.first { $0.id == selectedPageID } ?? pages.first
    }

    // MARK: - Trattenute

    func hold(_ reason: String) { holds.insert(reason) }
    func release(_ reason: String) { holds.remove(reason) }
    var isHeld: Bool { !holds.isEmpty || isPinnedForPreview }

    // MARK: - Misure

    /// Larghezza di una delle due ali, compreso lo spazio ai bordi.
    var wingsAreEmpty: Bool { leadingWidth == 0 && trailingWidth == 0 }

    func closedBodyWidth(config: LunettaConfig) -> CGFloat {
        let notch = geometry.notchWidth + 2
        if config.layout.symmetricWings {
            return notch + 2 * max(leadingWidth, trailingWidth)
        }
        return notch + leadingWidth + trailingWidth
    }

    /// La dimensione che la notch deve avere adesso, orecchie incluse.
    func size(config: LunettaConfig) -> CGSize {
        let appearance = config.appearance
        if isOpen {
            let page = currentPage(in: config.layout.pages)
            return CGSize(width: appearance.openWidth, height: page?.height ?? appearance.openHeight)
        }

        let ear = CGFloat(appearance.closedEarRadius)
        var width = closedBodyWidth(config: config) + 2 * ear
        var height = geometry.notchHeight

        if let peek {
            width = max(width, peekWidth(peek))
            height += Self.peekHeight
        } else if hud != nil, config.hud.style == .below {
            width = max(width, 300)
            height += Self.hudBelowHeight
        } else if hud == nil, isHovering, appearance.hoverBump {
            width += 12
            height += 3
        }
        return CGSize(width: width, height: height)
    }

    func radii(config: LunettaConfig) -> (ear: CGFloat, bottom: CGFloat) {
        let appearance = config.appearance
        if isOpen {
            return (CGFloat(appearance.openEarRadius), CGFloat(appearance.openBottomRadius))
        }
        if peek != nil {
            return (CGFloat(appearance.closedEarRadius) + 2, 22)
        }
        return (CGFloat(appearance.closedEarRadius), CGFloat(appearance.closedBottomRadius))
    }

    static let peekHeight: CGFloat = 46
    static let hudBelowHeight: CGFloat = 38

    private func peekWidth(_ peek: NotchPeek) -> CGFloat {
        // Stima sufficiente: la forma non deve seguire il testo al pixel, deve solo contenerlo.
        let characters = max(peek.title.count, peek.subtitle?.count ?? 0)
        let text = CGFloat(characters) * 6.6 + (peek.actionLabel == nil ? 0 : 66)
        return min(max(geometry.notchWidth + 80, text + 76), 520)
    }
}

extension PageConfig {
    func containsWidget(_ kind: String) -> Bool {
        widgets.contains { $0.kind == kind }
    }
}
