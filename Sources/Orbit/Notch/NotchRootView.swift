import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Ciò che i widget possono chiedere alla notch che li ospita.
@MainActor
final class NotchActions: ObservableObject {
    var closeHandler: () -> Void = {}
    var holdHandler: (String, Bool) -> Void = { _, _ in }
    var settingsHandler: (SettingsSection?) -> Void = { _ in }

    func close() { closeHandler() }
    func setHold(_ reason: String, _ active: Bool) { holdHandler(reason, active) }
    func openSettings(_ section: SettingsSection? = nil) { settingsHandler(section) }

    /// Una richiesta di permesso di sistema porta via il fuoco: la notch non deve chiudersi nel frattempo.
    func keepOpenDuringSystemPrompt() {
        holdHandler("permesso", true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.holdHandler("permesso", false)
        }
    }
}

/// La notch intera: disegna la forma che cambia e ci mette dentro il contenuto giusto.
struct NotchRootView: View {
    @ObservedObject var state: NotchState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var media: MediaService
    @EnvironmentObject private var summary: SessionSummary
    @EnvironmentObject private var shelf: ShelfStore

    var body: some View {
        let config = settings.config
        let theme = NotchTheme.resolve(config.appearance, artwork: config.media.tintWithArtwork ? media.artworkColor : nil)
        let size = state.size(config: config)
        let radii = state.radii(config: config)
        let shape = NotchShape(earRadius: radii.ear, bottomRadius: radii.bottom)

        ZStack(alignment: .top) {
            NotchSurface(isOpen: state.isOpen, shape: shape, size: size)

            Group {
                if state.isOpen {
                    OpenNotchContent(state: state)
                        .transition(.notchContent(blur: config.appearance.contentBlur))
                } else {
                    ClosedNotchContent(state: state)
                        .transition(.opacity.animation(.easeOut(duration: 0.14)))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipped()

            if state.isDropTargeted {
                DropOverlay(hasShelf: true)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(borderOverlay(shape: shape, theme: theme))
        .contentShape(shape)
        .contextMenu { NotchContextMenu(services: AppServices.shared) }
        .background(shadowLayer(shape: shape, theme: theme))
        .onDrop(of: ShelfStore.dropTypes, isTargeted: dropBinding) { providers in
            shelf.handleDrop(providers: providers)
            return true
        }
        .offset(x: state.isOpen ? 0 : closedOffset(config: config))
        .opacity(state.isSuppressed ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.notchTheme, theme)
        .environment(\.panelIsVisible, !state.isSuppressed)
        .animation(theme.animation, value: state.isOpen)
        .animation(theme.animation, value: size)
        .animation(theme.animation, value: radii.bottom)
        .animation(theme.animation, value: state.peek?.id)
        .animation(.easeOut(duration: 0.18), value: state.isDropTargeted)
        .animation(.easeOut(duration: 0.2), value: state.isSuppressed)
    }

    private var dropBinding: Binding<Bool> {
        Binding(get: { state.isDropTargeted }, set: { state.isDropTargeted = $0 })
    }

    /// Con ali diverse la forma va spostata perché il ritaglio vero resti coperto.
    private func closedOffset(config: OrbitConfig) -> CGFloat {
        guard !config.layout.symmetricWings else { return 0 }
        return (state.trailingWidth - state.leadingWidth) / 2
    }

    private func borderOverlay(shape: NotchShape, theme: NotchTheme) -> some View {
        let strength = state.isOpen ? theme.appearance.border : 0
        return shape
            .stroke(
                LinearGradient(
                    colors: [.white.opacity(0), .white.opacity(0.28 * strength)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
    }

    /// A riposo nessuna ombra: la notch deve sembrare hardware, non una finestra.
    /// Si stacca dal fondo solo quando si apre, o si accende se un agente ti cerca.
    @ViewBuilder
    private func shadowLayer(shape: NotchShape, theme: NotchTheme) -> some View {
        let raised = state.isOpen || state.peek != nil
        let attention = theme.appearance.attentionGlow && !state.isOpen ? summary.aggregate : nil
        let glowColor: Color? = (attention?.needsYou == true) ? attention?.tint : nil

        shape
            .fill(.black)
            .shadow(
                color: .black.opacity(raised ? 0.6 * theme.appearance.shadow : 0),
                radius: state.isOpen ? 30 : 14,
                y: state.isOpen ? 16 : 6
            )
            .shadow(color: (glowColor ?? .clear).opacity(glowColor == nil ? 0 : 0.75), radius: 9, y: 1)
            .animation(.easeInOut(duration: 0.4), value: glowColor == nil)
    }
}

extension AnyTransition {
    /// Il contenuto arriva dalla notch: si schiarisce, si mette a fuoco e cresce dall'alto.
    static func notchContent(blur: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: NotchContentModifier(progress: 0, blur: blur),
                identity: NotchContentModifier(progress: 1, blur: blur)
            ),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }
}

private struct NotchContentModifier: ViewModifier {
    var progress: Double
    var blur: Bool

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.94 + 0.06 * progress, anchor: .top)
            .blur(radius: blur ? (1 - progress) * 10 : 0)
    }
}

// MARK: - Superficie

/// Il materiale della notch. Da chiusa è sempre nero pieno: deve confondersi con
/// il ritaglio vero del display. Da aperta prende lo stile scelto, ma sfuma comunque
/// al nero in alto, così la notch hardware non resta un buco nero su un pannello chiaro.
struct NotchSurface: View {
    var isOpen: Bool
    var shape: NotchShape
    var size: CGSize

    @EnvironmentObject private var media: MediaService
    @Environment(\.notchTheme) private var theme

    var body: some View {
        let appearance = theme.appearance
        let isGlass = isOpen && appearance.surface == .glass

        ZStack {
            if isGlass {
                glassLayer
                    .transition(.opacity)
            }

            Color.black.opacity(isGlass ? appearance.glassDim : 1)

            if isOpen {
                openFill
                    .transition(.opacity)
                topFade
                    .transition(.opacity)
                ambientGlow
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private var glassLayer: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            VisualEffectBackground(material: .hudWindow)
        }
    }

    @ViewBuilder
    private var openFill: some View {
        let appearance = theme.appearance
        switch appearance.surface {
        case .solid:
            Color(hexString: appearance.solidHex) ?? .black
        case .gradient:
            LinearGradient(
                colors: appearance.gradientHex.compactMap { Color(hexString: $0) },
                startPoint: .top,
                endPoint: .bottom
            )
        case .glass:
            Color.clear
        case .artwork:
            ZStack {
                if let artwork = media.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .blur(radius: 46)
                        .saturation(1.25)
                        .opacity(0.6)
                        .clipped()
                }
                LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    /// Raccorda la superficie alla notch hardware.
    private var topFade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 54)
            Spacer(minLength: 0)
        }
    }

    /// La luce che sale dal basso: tiene insieme il colore del brano e quello del tema.
    private var ambientGlow: some View {
        let strength = theme.appearance.glow
        let color = theme.appearance.accentMode == .artwork ? (theme.ambient ?? theme.accent) : theme.accent
        return RadialGradient(
            colors: [color.opacity(0.26 * strength), .clear],
            center: .bottom,
            startRadius: 0,
            endRadius: max(size.width * 0.56, 200)
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Notch chiusa

private struct WingWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Le ali attorno al ritaglio, più l'eventuale avviso che scende sotto.
struct ClosedNotchContent: View {
    @ObservedObject var state: NotchState

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var summary: SessionSummary
    @EnvironmentObject private var media: MediaService
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var battery: BatteryMonitor
    @EnvironmentObject private var timer: TimerStore
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var custom: CustomWidgetStore
    @Environment(\.notchTheme) private var theme

    private var availability: CompactAvailability {
        CompactAvailability(summary: summary, media: media, calendar: calendar, battery: battery, timer: timer, shelf: shelf, custom: custom)
    }

    var body: some View {
        let layout = settings.config.layout
        let hud = settings.config.hud.style == .inline ? state.hud : nil
        let leading = hud == nil ? layout.closedLeading.filter(availability.isActive) : []
        let trailing = hud == nil ? layout.closedTrailing.filter(availability.isActive) : []
        let symmetric = layout.symmetricWings
        let shared = max(state.leadingWidth, state.trailingWidth)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                wing(alignment: .leading, width: symmetric ? shared : state.leadingWidth, measure: { state.setLeadingWidth($0) }) {
                    if let hud {
                        HUDInlineLeading(hud: hud)
                    } else {
                        ForEach(leading, id: \.self) { CompactItemView(id: $0).transition(.compactItem) }
                    }
                }
                .opacity(state.peek == nil ? 1 : 0.9)

                Color.clear.frame(width: state.geometry.notchWidth + 2)

                wing(alignment: .trailing, width: symmetric ? shared : state.trailingWidth, measure: { state.setTrailingWidth($0) }) {
                    if let hud {
                        HUDInlineTrailing(hud: hud)
                    } else {
                        ForEach(trailing, id: \.self) { CompactItemView(id: $0).transition(.compactItem) }
                    }
                }
            }
            .frame(height: state.geometry.notchHeight)
            .frame(maxWidth: .infinity)
            .animation(theme.animation, value: leading)
            .animation(theme.animation, value: trailing)

            if let peek = state.peek {
                PeekContent(peek: peek, dismiss: { state.peek = nil })
                    .frame(height: NotchState.peekHeight)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let below = state.hud, settings.config.hud.style == .below {
                HUDBelow(hud: below)
                    .frame(height: NotchState.hudBelowHeight)
                    .transition(.opacity)
            }
        }
    }

    /// Un'ala si misura da sola: è il suo contenuto a dire quanto deve allargarsi la notch.
    @ViewBuilder
    private func wing<Content: View>(
        alignment: Alignment,
        width: CGFloat,
        measure: @escaping (CGFloat) -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isLeading = alignment == .leading
        ZStack(alignment: alignment) {
            Color.clear.frame(width: width, height: 1)
            HStack(spacing: 7) { content() }
                .padding(.leading, isLeading ? 11 : 8)
                .padding(.trailing, isLeading ? 8 : 11)
                .fixedSize()
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: WingWidthKey.self, value: proxy.size.width)
                })
        }
        .frame(width: width, alignment: alignment)
        .onPreferenceChange(WingWidthKey.self) { value in
            // Padding da solo significa ala vuota: non deve allargare nulla.
            measure(value <= 19.5 ? 0 : min(value, CGFloat(settings.config.appearance.maxWingWidth)))
        }
    }
}

extension AnyTransition {
    static var compactItem: AnyTransition {
        .scale(scale: 0.6).combined(with: .opacity)
    }
}

// MARK: - Avvisi

struct PeekContent: View {
    let peek: NotchPeek
    var dismiss: () -> Void

    @Environment(\.notchTheme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            icon
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(peek.title)
                    .font(theme.font(12, .semibold))
                    .foregroundStyle(theme.primary)
                    .lineLimit(1)
                if let subtitle = peek.subtitle {
                    Text(subtitle)
                        .font(theme.font(10.5))
                        .foregroundStyle(peek.tint ?? theme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let label = peek.actionLabel, let action = peek.action {
                NotchPillButton(symbol: nil, label: label, tint: peek.tint ?? theme.accent) {
                    action()
                    dismiss()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let action = peek.action else { return }
            action()
            dismiss()
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch peek.icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(peek.tint ?? theme.accent)
        case .artwork(let image):
            ArtworkThumbnail(image: image, size: 22, radius: 5)
        case .status(let status):
            AgentsStatusGlyph(status: status, accent: peek.tint)
        }
    }
}

// MARK: - Notch aperta

/// Le misure del contenuto aperto, condivise con l'editor del layout: le sue maniglie
/// devono cadere esattamente sopra i widget della vera anteprima.
enum NotchMetrics {
    static let contentInset: CGFloat = 11
    static let contentTopGap: CGFloat = 3

    static func headerHeight(notchHeight: CGFloat) -> CGFloat { max(notchHeight, 30) }
}

struct OpenNotchContent: View {
    @ObservedObject var state: NotchState

    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.notchTheme) private var theme

    var body: some View {
        let config = settings.config
        let page = state.currentPage(in: config.layout.pages)
        let size = state.size(config: config)

        VStack(spacing: 0) {
            NotchHeader(state: state)

            ZStack {
                if let page {
                    PageContent(page: page)
                        .id(page.id)
                        .transition(pageTransition)
                }
            }
            // Le orecchie stanno dentro la larghezza della forma: il margine si conta da dopo di loro.
            .padding(.horizontal, NotchMetrics.contentInset + CGFloat(config.appearance.openEarRadius))
            .padding(.bottom, NotchMetrics.contentInset)
            .padding(.top, NotchMetrics.contentTopGap)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .animation(theme.animation, value: state.selectedPageID)
    }

    private var pageTransition: AnyTransition {
        let edge = state.pageDirection
        let opposite: Edge = edge == .trailing ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: opposite).combined(with: .opacity)
        )
    }
}

/// Testata: le pagine a sinistra del ritaglio, le informazioni a destra.
struct NotchHeader: View {
    @ObservedObject var state: NotchState

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var actions: NotchActions
    @Environment(\.notchTheme) private var theme
    @Namespace private var selection

    var body: some View {
        let config = settings.config
        let pages = config.layout.pages
        let side = (CGFloat(config.appearance.openWidth) - state.geometry.notchWidth) / 2 - 8
        let ear = CGFloat(config.appearance.openEarRadius)

        HStack(spacing: 0) {
            HStack(spacing: 2) {
                if pages.count > 1 {
                    ForEach(pages) { page in
                        tab(page, config: config)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, ear + 8)
            .frame(width: side, alignment: .leading)

            Spacer(minLength: state.geometry.notchWidth)

            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if let hud = state.hud {
                    HStack(spacing: 6) {
                        HUDInlineLeading(hud: hud)
                        HUDInlineTrailing(hud: hud)
                    }
                    .transition(.opacity)
                } else {
                    ForEach(config.layout.headerTrailing, id: \.self) { CompactItemView(id: $0) }
                }
                if config.behavior.settingsButtonInNotch {
                    NotchIconButton(symbol: "gearshape.fill", size: 24, iconSize: 11.5, help: tr("Impostazioni")) {
                        actions.openSettings()
                    }
                }
            }
            .padding(.trailing, ear + 6)
            .frame(width: side, alignment: .trailing)
        }
        .frame(height: NotchMetrics.headerHeight(notchHeight: state.geometry.notchHeight))
        .animation(.easeOut(duration: 0.15), value: state.hud == nil)
    }

    private func tab(_ page: PageConfig, config: OrbitConfig) -> some View {
        let isSelected = state.selectedPageID == page.id || (state.selectedPageID == nil && config.layout.pages.first?.id == page.id)
        let style = config.appearance.tabStyle
        return Button {
            state.selectPage(page.id, pages: config.layout.pages)
        } label: {
            HStack(spacing: 4) {
                if style != .titles {
                    Image(systemName: page.symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                if style != .icons {
                    Text(tr(page.title))
                        .font(theme.font(11, .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isSelected ? theme.primary : theme.tertiary)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.white.opacity(0.14))
                        .matchedGeometryEffect(id: "tab", in: selection)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(NotchPressStyle())
        .help(tr(page.title))
    }
}

/// Una pagina: colonne di widget in proporzione al loro peso.
struct PageContent: View {
    let page: PageConfig

    @Environment(\.notchTheme) private var theme

    /// Un widget "impilato" si unisce alla colonna di quello prima.
    private var columns: [[WidgetPlacement]] {
        var result: [[WidgetPlacement]] = []
        for widget in page.widgets {
            if widget.stacked, !result.isEmpty {
                result[result.count - 1].append(widget)
            } else {
                result.append([widget])
            }
        }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let columns = columns
            let spacing = CGFloat(theme.appearance.widgetSpacing)
            let totalWeight = max(columns.reduce(0) { $0 + $1[0].weight }, 0.01)
            let available = max(0, geometry.size.width - spacing * CGFloat(columns.count - 1))

            HStack(spacing: spacing) {
                ForEach(columns, id: \.first?.id) { column in
                    VStack(spacing: spacing) {
                        ForEach(column) { widget in
                            WidgetHost(kind: widget.kind)
                        }
                    }
                    .frame(width: available * column[0].weight / totalWeight)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
        }
    }
}

/// La cornice comune a tutti i widget, con lo stile di card scelto dall'utente.
struct WidgetHost: View {
    let kind: String

    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.notchTheme) private var theme

    var body: some View {
        let style = theme.appearance.cardStyle
        let shape = RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)

        WidgetContent(kind: kind)
            .padding(style == .plain ? 3 : 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                switch style {
                case .filled:
                    shape.fill(.white.opacity(0.055))
                case .outlined:
                    shape.strokeBorder(.white.opacity(0.11), lineWidth: 0.8)
                case .plain:
                    Color.clear
                }
            }
            .clipShape(shape)
    }
}

/// Il contenuto vero di un widget.
struct WidgetContent: View {
    let kind: String

    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        if let customID = ModuleCatalog.customID(fromKind: kind) {
            CustomWidgetView(config: settings.config.customWidgets.first { $0.id == customID })
        } else {
            switch kind {
            case "agents":    AgentsWidget()
            case "media":     MediaWidget()
            case "calendar":  CalendarWidget()
            case "shelf":     ShelfWidget()
            case "mirror":    MirrorWidget()
            case "battery":   BatteryWidget()
            case "system":    SystemWidget()
            case "clipboard": ClipboardWidget()
            case "timer":     TimerWidget()
            case "notes":     NotesWidget()
            case "launcher":  LauncherWidget()
            case "clock":     ClockWidget()
            default:          EmptyView()
            }
        }
    }
}

// MARK: - Rilascio

struct DropOverlay: View {
    var hasShelf: Bool
    @Environment(\.notchTheme) private var theme

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.62))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                .foregroundStyle(theme.accent.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.top, 36)
                .padding(.bottom, 14)
            VStack(spacing: 4) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text("Lascia qui per aggiungere allo scaffale")
                    .font(theme.font(12, .semibold))
                    .foregroundStyle(theme.primary)
            }
            .padding(.top, 18)
        }
        .allowsHitTesting(false)
    }
}
