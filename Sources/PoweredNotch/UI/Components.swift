import AppKit
import QuartzCore
import SwiftUI

// MARK: - Colori

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init?(hexString: String?) {
        guard var value = hexString?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8, let number = UInt32(value, radix: 16) else { return nil }
        if value.count == 8 {
            self.init(hex: number >> 8, opacity: Double(number & 0xFF) / 255)
        } else {
            self.init(hex: number)
        }
    }

    /// Rappresentazione esadecimale, per salvare nel config un colore scelto dal selettore.
    var hexString: String? {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }
}

extension SessionStatus {
    var tint: Color {
        switch self {
        case .working:   Color(hex: 0x4FC3F7)
        case .attention: Color(hex: 0xFFC145)
        case .blocked:   Color(hex: 0xFF6B6B)
        case .idle:      Color(hex: 0x8E9BAE)
        case .ended:     Color(hex: 0x6B7789)
        case .error:     Color(hex: 0xFF5A63)
        }
    }

    /// Solo gli stati vivi respirano: niente animazioni perenni per una sessione chiusa.
    var animates: Bool { self == .working || self == .attention || self == .blocked }
}

extension AgentSession {
    var accentColor: Color { Color(hexString: accentHex) ?? status.tint }
}

// MARK: - Tema

/// L'aspetto scelto dall'utente, tradotto in valori pronti per le viste.
struct NotchTheme {
    var appearance = AppearanceConfig()
    var accent = Color.white
    /// Il colore della copertina in riproduzione, se c'è.
    var ambient: Color?

    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * CGFloat(appearance.textScale), weight: weight, design: appearance.font.design)
    }

    /// Le cifre restano sempre arrotondate e tabulari: non devono ballare quando cambiano.
    func numberFont(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        let design: Font.Design = appearance.font == .system ? .rounded : appearance.font.design
        return .system(size: size * CGFloat(appearance.textScale), weight: weight, design: design).monospacedDigit()
    }

    var primary: Color { .white.opacity(0.96) }
    var secondary: Color { .white.opacity(0.62) }
    var tertiary: Color { .white.opacity(0.38) }
    var hairline: Color { .white.opacity(0.09) }
    var chipFill: Color { .white.opacity(0.08) }
    var hoverFill: Color { .white.opacity(0.09) }
    var cardRadius: CGFloat { CGFloat(appearance.cardRadius) }

    var animation: Animation? {
        // "Riduci movimento" di macOS vince su qualunque scelta: niente rimbalzi, solo una dissolvenza.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return .easeOut(duration: 0.15)
        }
        return appearance.motion.animation(speed: appearance.motionSpeed)
    }

    /// Risolve l'accento in base alla modalità scelta.
    static func resolve(_ appearance: AppearanceConfig, artwork: NSColor?) -> NotchTheme {
        var theme = NotchTheme(appearance: appearance)
        let custom = Color(hexString: appearance.accentHex) ?? .white
        let artworkColor = artwork.map { Color(nsColor: $0) }
        theme.ambient = artworkColor
        switch appearance.accentMode {
        case .custom:  theme.accent = custom
        case .system:  theme.accent = Color(nsColor: .controlAccentColor)
        case .artwork: theme.accent = artworkColor ?? custom
        }
        return theme
    }
}

private struct NotchThemeKey: EnvironmentKey {
    static let defaultValue = NotchTheme()
}

/// Vero solo mentre la notch mostra davvero questa vista: un contenuto nascosto
/// non deve continuare ad animarsi e a consumare.
private struct PanelVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var notchTheme: NotchTheme {
        get { self[NotchThemeKey.self] }
        set { self[NotchThemeKey.self] = newValue }
    }

    var panelIsVisible: Bool {
        get { self[PanelVisibleKey.self] }
        set { self[PanelVisibleKey.self] = newValue }
    }
}

// MARK: - Marchio

/// Il marchio di Powered Notch: una mezzaluna che pende dal bordo in alto.
struct PoweredNotchGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width / 2, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY - radius / 2)
        path.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - Componenti di base

/// Pallino di stato con alone che pulsa quando la sessione è viva. L'alone è un
/// layer di Core Animation: con diverse sessioni al lavoro resta acceso per ore, e
/// non deve svegliare l'app a ogni fotogramma.
struct PulseDot: NSViewRepresentable {
    var status: SessionStatus
    var size: CGFloat = 8

    @Environment(\.panelIsVisible) private var panelIsVisible

    func makeNSView(context: Context) -> PulseDotView { PulseDotView() }

    func updateNSView(_ view: PulseDotView, context: Context) {
        view.configure(
            color: NSColor(status.tint),
            diameter: size,
            pulses: status.animates && panelIsVisible,
            period: status == .working ? 1.7 : 1.1,
            glows: status.animates
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PulseDotView, context: Context) -> CGSize? {
        CGSize(width: size * 2.4, height: size * 2.4)
    }
}

final class PulseDotView: NSView {
    private let halo = CALayer()
    private let dot = CALayer()
    private var pulsing = false
    private var period: Double = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(halo)
        layer?.addSublayer(dot)
        dot.shadowRadius = 3
        dot.shadowOffset = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) non disponibile") }

    private var diameter: CGFloat = 8

    func configure(color: NSColor, diameter newDiameter: CGFloat, pulses: Bool, period newPeriod: Double, glows: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.backgroundColor = color.cgColor
        dot.shadowColor = color.cgColor
        dot.shadowOpacity = glows ? 0.8 : 0
        halo.backgroundColor = color.cgColor
        CATransaction.commit()

        if newDiameter != diameter {
            diameter = newDiameter
            needsLayout = true
        }
        guard pulses != pulsing || newPeriod != period else { return }
        pulsing = pulses
        period = newPeriod
        refreshAnimation()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let frame = CGRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2, width: diameter, height: diameter)
        for shape in [halo, dot] {
            shape.frame = frame
            shape.cornerRadius = diameter / 2
        }
        CATransaction.commit()
    }

    private func refreshAnimation() {
        halo.removeAllAnimations()
        guard pulsing else {
            halo.opacity = 0
            return
        }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 2.3
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.45
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = period
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        halo.add(group, forKey: "pulse")
    }

    /// Core Animation toglie le animazioni quando la vista lascia la finestra.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { refreshAnimation() }
    }
}

/// Anello sottile di avanzamento: contesto consumato, batteria, timer…
struct ContextRing: View {
    var fraction: Double
    var tint: Color
    var size: CGFloat = 14
    var lineWidth: CGFloat = 2
    /// Quasi pieno è un problema solo per il contesto: una batteria carica non lo è.
    var warnsWhenFull = false

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, fraction))
                .stroke(warnsWhenFull && fraction > 0.85 ? Color(hex: 0xFF5A63) : tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

/// Barra di riempimento con angoli pieni.
struct LevelBar: View {
    var fraction: Double
    var tint: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, geometry.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

/// Etichetta compatta per branch, modello, host…
struct MetaChip: View {
    var text: String
    var symbol: String?
    var tint: Color?

    @Environment(\.notchTheme) private var theme

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 8, weight: .semibold))
            }
            Text(text)
                .font(theme.font(9.5, .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint ?? theme.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule(style: .continuous).fill(tint?.opacity(0.16) ?? theme.chipFill))
    }
}

/// Bottone tondo per le azioni nella notch: si accende al passaggio del mouse.
struct NotchIconButton: View {
    var symbol: String
    var size: CGFloat = 26
    var iconSize: CGFloat = 12
    var tint: Color?
    var help: String?
    var isActive = false
    var action: () -> Void

    @Environment(\.notchTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isActive ? (tint ?? theme.accent) : (hovering ? theme.primary : theme.secondary))
                .frame(width: size, height: size)
                .background(Circle().fill(hovering ? theme.hoverFill : .clear))
                .contentShape(Circle())
                .scaleEffect(hovering ? 1.06 : 1)
        }
        .buttonStyle(NotchPressStyle())
        .help(help ?? "")
        .accessibilityLabel(help ?? symbol)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

/// Pulsante con etichetta, per le azioni principali di una card.
struct NotchPillButton: View {
    var symbol: String?
    var label: String
    var tint: Color?
    var action: () -> Void

    @Environment(\.notchTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
                }
                if !label.isEmpty {
                    Text(label).font(theme.font(10.5, .semibold)).lineLimit(1)
                }
            }
            .foregroundStyle(hovering ? (tint ?? theme.primary) : (tint?.opacity(0.9) ?? theme.secondary))
            .padding(.horizontal, label.isEmpty ? 6 : 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill((tint ?? .white).opacity(hovering ? 0.24 : (tint == nil ? 0.08 : 0.15)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(NotchPressStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

/// La pressione si sente: un piccolo rimpicciolimento immediato, nient'altro.
struct NotchPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Testo che scorre solo se non entra nello spazio disponibile. Lo scorrimento è
/// un'animazione di Core Animation: un titolo lungo può girare per ore senza costare nulla.
struct MarqueeText: NSViewRepresentable {
    var text: String
    var size: CGFloat
    var weight: NSFont.Weight = .regular
    var color: Color

    @Environment(\.notchTheme) private var theme
    @Environment(\.panelIsVisible) private var panelIsVisible

    private var font: NSFont {
        let scaled = size * CGFloat(theme.appearance.textScale)
        let base = NSFont.systemFont(ofSize: scaled, weight: weight)
        let design: NSFontDescriptor.SystemDesign
        switch theme.appearance.font {
        case .system:  design = .default
        case .rounded: design = .rounded
        case .serif:   design = .serif
        case .mono:    design = .monospaced
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return NSFont(descriptor: descriptor, size: scaled) ?? base
    }

    func makeNSView(context: Context) -> MarqueeLabelView { MarqueeLabelView() }

    func updateNSView(_ view: MarqueeLabelView, context: Context) {
        view.configure(text: text, font: font, color: NSColor(color), animates: panelIsVisible)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarqueeLabelView, context: Context) -> CGSize? {
        let line = ceil(font.ascender - font.descender + font.leading)
        return CGSize(width: proposal.width ?? nsView.contentWidth, height: line)
    }
}

final class MarqueeLabelView: NSView {
    private let track = CALayer()
    private let first = CATextLayer()
    private let second = CATextLayer()
    private let fade = CAGradientLayer()
    private let gap: CGFloat = 30
    private let fadeWidth: CGFloat = 16
    private let speed: CGFloat = 26

    private var text = ""
    private var font = NSFont.systemFont(ofSize: 12)
    private var color = NSColor.white
    private var animates = true
    private(set) var contentWidth: CGFloat = 0
    private var runningKey: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(track)
        track.addSublayer(first)
        track.addSublayer(second)
        fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) non disponibile") }

    func configure(text newText: String, font newFont: NSFont, color newColor: NSColor, animates newAnimates: Bool) {
        guard newText != text || newFont != font || newColor != color || newAnimates != animates else { return }
        text = newText
        font = newFont
        color = newColor
        animates = newAnimates
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        contentWidth = ceil(attributed.size().width)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for label in [first, second] {
            label.string = attributed
            label.truncationMode = .none
            label.isWrapped = false
        }
        CATransaction.commit()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        let height = bounds.height
        let overflows = contentWidth > bounds.width + 1 && bounds.width > 0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = CGRect(x: 0, y: 0, width: contentWidth * 2 + gap, height: height)
        first.frame = CGRect(x: 0, y: 0, width: contentWidth, height: height)
        second.frame = CGRect(x: contentWidth + gap, y: 0, width: contentWidth, height: height)
        second.isHidden = !overflows
        first.contentsScale = scale
        second.contentsScale = scale

        if overflows {
            fade.frame = bounds
            let stop = max(0, (bounds.width - fadeWidth) / bounds.width)
            fade.locations = [0, NSNumber(value: Double(stop)), 1]
            layer?.mask = fade
        } else {
            layer?.mask = nil
        }
        CATransaction.commit()
        refreshAnimation(overflows: overflows)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        runningKey = nil
        needsLayout = true
    }

    private func refreshAnimation(overflows: Bool) {
        let wanted = overflows && animates && window != nil
        let key = wanted ? "\(text)|\(contentWidth)" : nil
        guard key != runningKey else { return }
        runningKey = key
        track.removeAllAnimations()
        guard wanted else { return }

        // Parte, fa il giro e si ferma un attimo: il tempo per leggere l'inizio.
        let distance = contentWidth + gap
        let travel = Double(distance / speed)
        let pause = 1.6
        let total = travel + pause
        let slide = CAKeyframeAnimation(keyPath: "transform.translation.x")
        slide.values = [0, 0, -distance]
        slide.keyTimes = [0, NSNumber(value: pause / total), 1]
        slide.duration = total
        slide.repeatCount = .infinity
        slide.isRemovedOnCompletion = false
        track.add(slide, forKey: "marquee")
    }
}

/// Un simbolo di sistema che può pulsare. È un layer di Core Animation perché
/// `symbolEffect` di SwiftUI ridisegna a ogni fotogramma: nella notch chiusa, accesa
/// tutto il giorno, costava da solo il 5% di CPU.
struct PulsingSymbol: NSViewRepresentable {
    var name: String
    var color: Color
    var pointSize: CGFloat = 11.5
    var weight: NSFont.Weight = .bold
    var pulses: Bool

    @Environment(\.panelIsVisible) private var panelIsVisible

    func makeNSView(context: Context) -> PulsingSymbolView { PulsingSymbolView() }

    func updateNSView(_ view: PulsingSymbolView, context: Context) {
        view.configure(name: name, color: NSColor(color), pointSize: pointSize, weight: weight, pulses: pulses && panelIsVisible)
    }
}

final class PulsingSymbolView: NSView {
    private let symbol = CALayer()
    private var signature = ""
    private var pulsing = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(symbol)
        symbol.contentsGravity = .center
        symbol.shadowOffset = .zero
        symbol.shadowRadius = 3
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) non disponibile") }

    func configure(name: String, color: NSColor, pointSize: CGFloat, weight: NSFont.Weight, pulses: Bool) {
        let newSignature = "\(name)|\(color)|\(pointSize)"
        if newSignature != signature {
            let isFirst = signature.isEmpty
            signature = newSignature
            let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)

            CATransaction.begin()
            CATransaction.setDisableActions(isFirst)
            if !isFirst {
                let crossfade = CATransition()
                crossfade.type = .fade
                crossfade.duration = 0.25
                symbol.add(crossfade, forKey: "contents")
            }
            let scale = window?.backingScaleFactor ?? 2
            symbol.contentsScale = scale
            symbol.contents = image?.layerContents(forContentsScale: scale)
            symbol.shadowColor = color.cgColor
            symbol.shadowOpacity = 0.55
            CATransaction.commit()
        }
        if pulses != pulsing {
            pulsing = pulses
            refreshAnimation()
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        symbol.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { refreshAnimation() }
    }

    private func refreshAnimation() {
        symbol.removeAnimation(forKey: "pulse")
        guard pulsing else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.35
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.isRemovedOnCompletion = false
        symbol.add(pulse, forKey: "pulse")
    }
}

extension View {
    /// Il contenuto di una lista sfuma verso il fondo invece di interrompersi di netto.
    func fadingBottom(_ height: CGFloat = 14) -> some View {
        mask(
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
            }
        )
    }
}

// MARK: - Visualizzatore

/// Le barre animate della musica. Sono layer di Core Animation: girano sulla GPU
/// senza svegliare SwiftUI a ogni fotogramma, quindi non pesano sulla batteria.
struct AudioVisualizer: NSViewRepresentable {
    var color: Color
    var isPlaying: Bool
    var style: VisualizerStyle
    var barCount = 4

    func makeNSView(context: Context) -> AudioVisualizerView { AudioVisualizerView() }

    func updateNSView(_ view: AudioVisualizerView, context: Context) {
        view.configure(color: NSColor(color), isPlaying: isPlaying, style: style, barCount: barCount)
    }
}

final class AudioVisualizerView: NSView {
    private var bars: [CALayer] = []
    private var isPlaying = false
    private var style: VisualizerStyle = .bars

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) non disponibile") }

    func configure(color: NSColor, isPlaying newPlaying: Bool, style newStyle: VisualizerStyle, barCount: Int) {
        var rebuild = false
        if bars.count != barCount {
            bars.forEach { $0.removeFromSuperlayer() }
            bars = (0..<barCount).map { _ in
                let bar = CALayer()
                layer?.addSublayer(bar)
                return bar
            }
            rebuild = true
        }
        let changedPlaying = newPlaying != isPlaying
        let changedStyle = newStyle != style
        isPlaying = newPlaying
        style = newStyle

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bars.forEach { $0.backgroundColor = color.cgColor }
        CATransaction.commit()

        if rebuild || changedStyle { needsLayout = true }
        if rebuild || changedPlaying || changedStyle { refreshAnimations() }
    }

    override func layout() {
        super.layout()
        guard !bars.isEmpty, bounds.width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let gap = bounds.width * (style == .dots ? 0.16 : 0.13)
        let width = (bounds.width - gap * CGFloat(bars.count - 1)) / CGFloat(bars.count)
        let height = style == .dots ? width : bounds.height
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            bar.position = CGPoint(x: CGFloat(index) * (width + gap) + width / 2, y: bounds.midY)
            bar.cornerRadius = style == .bars ? min(width * 0.32, 1.6) : width / 2
        }
        CATransaction.commit()
        refreshAnimations()
    }

    private func refreshAnimations() {
        for (index, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            if isPlaying, style != .off {
                bar.add(makeAnimation(index: index), forKey: "pulse")
            } else {
                bar.transform = restingTransform
            }
        }
        isHidden = style == .off
    }

    private var restingTransform: CATransform3D {
        style == .dots ? CATransform3DMakeScale(0.7, 0.7, 1) : CATransform3DMakeScale(1, 0.2, 1)
    }

    private func makeAnimation(index: Int) -> CAAnimation {
        // Durate e altezze diverse per ogni barra, così il ritmo non si ripete mai uguale.
        let seeds: [[CGFloat]] = [
            [0.25, 0.9, 0.4, 1.0, 0.3, 0.75, 0.25],
            [0.6, 0.3, 1.0, 0.45, 0.85, 0.35, 0.6],
            [0.35, 1.0, 0.55, 0.25, 0.9, 0.5, 0.35],
            [0.8, 0.4, 0.7, 1.0, 0.35, 0.9, 0.8],
            [0.5, 0.85, 0.3, 0.7, 1.0, 0.4, 0.5]
        ]
        let values = seeds[index % seeds.count]
        let animation = CAKeyframeAnimation(keyPath: style == .dots ? "transform" : "transform.scale.y")
        if style == .dots {
            animation.values = values.map { value -> NSValue in
                let scale = 0.55 + value * 0.45
                return NSValue(caTransform3D: CATransform3DMakeScale(scale, scale, 1))
            }
        } else {
            animation.values = values
        }
        animation.duration = 1.35 + Double(index % 3) * 0.28
        animation.repeatCount = .infinity
        animation.calculationMode = .cubic
        animation.isRemovedOnCompletion = false
        animation.timeOffset = Double(index) * 0.21
        return animation
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        bars.forEach { $0.contentsScale = window?.backingScaleFactor ?? 2 }
    }
}

// MARK: - Sfondi di sistema

/// Materiale di macOS per chi non ha ancora Liquid Glass.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

// MARK: - Formattazione

enum Format {
    /// Durata compatta: 45s, 12m, 2h 05m, 3g.
    static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 10 { return String(format: "%dh %02dm", hours, minutes % 60) }
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)g"
    }

    static func elapsed(since date: Date?) -> String? {
        guard let date else { return nil }
        return duration(Date().timeIntervalSince(date))
    }

    static func ago(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 8 { return "ora" }
        return duration(interval) + " fa"
    }

    static func tokens(_ value: Int) -> String {
        if value < 1000 { return "\(value)" }
        if value < 100_000 {
            return String(format: "%.1fk", Double(value) / 1000).replacingOccurrences(of: ".", with: ",")
        }
        return "\(value / 1000)k"
    }

    static func model(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20", with: " ")
            .split(separator: " ").first.map(String.init) ?? raw
    }

    /// Accorcia il percorso home in `~`.
    static func path(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let home = AppPaths.home.path
        return raw.hasPrefix(home) ? "~" + raw.dropFirst(home.count) : raw
    }

    /// Posizione di un brano: 3:07, 1:02:45.
    static func playback(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// Timer: 25:00, 1:05:00.
    static func countdown(_ seconds: TimeInterval) -> String {
        playback(seconds.rounded(.up))
    }

    static func bytesPerSecond(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var amount = max(0, value)
        var index = 0
        while amount >= 1000, index < units.count - 1 {
            amount /= 1000
            index += 1
        }
        return (amount < 10 && index > 0 ? String(format: "%.1f", amount) : String(format: "%.0f", amount)) + " " + units[index] + "/s"
    }

    /// "tra 12m", "tra 2h".
    static func until(_ date: Date) -> String {
        "tra " + duration(date.timeIntervalSinceNow)
    }
}
