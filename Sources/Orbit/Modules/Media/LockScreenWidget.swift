import Combine
import CoreImage
import SwiftUI

// MARK: - Misure

extension LockScreenStyle {
    /// La finestra è grande quanto la versione più ricca dello stile: la scheda dentro
    /// cresce e si restringe (testo trovato o no) senza spostare la finestra.
    var windowSize: CGSize {
        switch self {
        case .off:     .zero
        case .compact: CGSize(width: 460, height: 260)
        case .full:    CGSize(width: 780, height: 510)
        case .lyrics:  CGSize(width: 660, height: 540)
        }
    }
}

extension LockScreenConfig {
    /// Il lettore ingrandito o rimpicciolito porta con sé la sua finestra.
    var clampedScale: CGFloat { CGFloat(min(1.3, max(0.75, scale))) }

    var windowSize: CGSize {
        let size = style.windowSize
        return CGSize(width: (size.width * clampedScale).rounded(), height: (size.height * clampedScale).rounded())
    }

    /// Ciò che il lettore deve sapere di sé, passato una volta sola a tutti i pezzi.
    func resolved(artworkColor: NSColor?) -> LockLook {
        let accentColor: Color
        switch accent {
        case .white:   accentColor = .white
        case .artwork: accentColor = artworkColor.map { Color(nsColor: $0.lockScreenReadable) } ?? .white
        case .custom:  accentColor = Color(hexString: accentHex) ?? .white
        }
        return LockLook(
            accent: accentColor,
            showArtwork: showArtwork,
            artworkShape: artworkShape,
            showSourceIcon: showSourceIcon,
            showProgress: showProgress,
            showTimes: showTimes,
            lyricsCentered: lyricsCentered,
            onWallpaper: background == .none || (background == .glass && clearGlass)
        )
    }
}

/// Le scelte dell'utente che riguardano i pezzi del lettore.
struct LockLook: Equatable {
    var accent: Color = .white
    var showArtwork = true
    var artworkShape: LockArtworkShape = .rounded
    var showSourceIcon = true
    var showProgress = true
    var showTimes = true
    var lyricsCentered = false
    /// Senza un fondo pieno dietro, le righe non cantate si sbiadiscono meno: sparirebbero nel wallpaper.
    var onWallpaper = false
}

private extension NSColor {
    /// Il colore della copertina, schiarito quanto basta da leggersi su uno sfondo scuro.
    var lockScreenReadable: NSColor {
        guard let rgb = usingColorSpace(.sRGB) else { return self }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(saturation, 0.75), brightness: max(brightness, 0.85), alpha: 1)
    }
}

// MARK: - Radice

/// Il lettore sulla schermata di blocco. Compare solo finché c'è qualcosa in riproduzione.
struct LockScreenWidgetView: View {
    /// Dove sta la scheda dentro la finestra: lo calcola chi posiziona la finestra.
    var anchor: UnitPoint = .center
    /// La grandezza davvero usata: quella scelta, ridotta se lo schermo non ha posto.
    var scale: CGFloat?
    /// Nelle anteprime (guida, impostazioni) i comandi non devono raggiungere il lettore vero.
    var isPreview = false

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var media: MediaService
    @StateObject private var artwork = LockArtworkHolder()

    var body: some View {
        let config = settings.config.lockScreen
        let base = config.style.windowSize
        let factor = scale ?? config.clampedScale
        let scaled = CGSize(width: (base.width * factor).rounded(), height: (base.height * factor).rounded())
        ZStack(alignment: .topLeading) {
            Color.clear
            if config.style != .off, let state = media.nowPlaying {
                LockScreenPlayer(state: state, config: config)
                    // La scheda sta nella finestra al punto `anchor`: 0 tutta a sinistra (o in alto), 1 tutta a destra.
                    .alignmentGuide(.leading) { d in -(base.width - d.width) * anchor.x }
                    .alignmentGuide(.top) { d in -(base.height - d.height) * anchor.y }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(width: base.width, height: base.height, alignment: .topLeading)
        // La scala non cambia l'ingombro: si scala attorno ad `anchor` e si riporta nella finestra scalata.
        .scaleEffect(factor, anchor: anchor)
        .offset(x: anchor.x * (scaled.width - base.width), y: anchor.y * (scaled.height - base.height))
        .frame(width: scaled.width, height: scaled.height, alignment: .topLeading)
        .environment(\.notchTheme, NotchTheme.resolve(settings.config.appearance, artwork: media.artworkColor))
        .environment(\.lockScreenIsPreview, isPreview)
        .environment(\.lockLook, config.resolved(artworkColor: media.artworkColor))
        .environmentObject(artwork)
        .onAppear { artwork.bind(to: media) }
        .animation(.easeInOut(duration: 0.35), value: media.nowPlaying == nil)
        .animation(.easeInOut(duration: 0.3), value: config)
    }
}

private struct LockScreenPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

private struct LockLookKey: EnvironmentKey {
    static let defaultValue = LockLook()
}

extension EnvironmentValues {
    var lockScreenIsPreview: Bool {
        get { self[LockScreenPreviewKey.self] }
        set { self[LockScreenPreviewKey.self] = newValue }
    }

    var lockLook: LockLook {
        get { self[LockLookKey.self] }
        set { self[LockLookKey.self] = newValue }
    }
}

private struct LockScreenPlayer: View {
    let state: NowPlaying
    let config: LockScreenConfig

    @EnvironmentObject private var lyricsService: LyricsService

    /// Cosa va nello spazio del testo. Lo spazio resta lo stesso da un brano all'altro
    /// (testo, attesa, "nessun testo"): la scheda non cambia misura, cambia solo il contenuto.
    private var lyricsContent: LyricsContent {
        guard config.showLyrics, let key = lyricsService.trackKey else { return .none }
        switch lyricsService.status {
        case .loaded(let lyrics): return .lyrics(lyrics, key: key)
        case .loading:            return .loading
        case .instrumental:       return .missing(tr("Brano strumentale"))
        case .unavailable:        return .missing(tr("Nessun testo per questo brano"))
        case .idle:               return .none
        }
    }

    private var wantsTextShadow: Bool {
        config.textShadow && config.background.showsWallpaper
    }

    private var showArtwork: Bool { config.showArtwork }

    var body: some View {
        Group {
            switch config.style {
            case .off:     EmptyView()
            case .compact: compact
            case .full:    full
            case .lyrics:  lyricsFirst
            }
        }
        // Sopra il wallpaper il testo bianco si perde nei punti chiari: un alone scuro lo tiene leggibile.
        .shadow(color: .black.opacity(wantsTextShadow ? 0.35 : 0), radius: 2, y: 1)
        .shadow(color: .black.opacity(wantsTextShadow ? 0.5 : 0), radius: 12, y: 2)
        .background(LockCardBackground(config: config))
        .shadow(color: .black.opacity(config.shadow && config.background != .none ? 0.35 : 0), radius: 30, y: 12)
        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: lyricsContent.hasArea)
    }

    // MARK: Compatto

    private var compact: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                if showArtwork, !config.flipped { LockArtwork(size: 78) }
                VStack(alignment: .leading, spacing: 8) {
                    LockTitles(state: state, titleSize: 15, artistSize: 13)
                    LockScrubber(state: state, compact: true)
                }
                if showArtwork, config.flipped { LockArtwork(size: 78) }
            }
            if lyricsContent.hasArea {
                CompactLyricRow(content: lyricsContent, state: state, size: 15 * config.lyricsScale)
                    .transition(.opacity)
            }
            LockControls(state: state, size: 0.9)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(width: 420)
    }

    // MARK: Completo

    /// Copertina e comandi da un lato, il testo dall'altro: quale lato lo sceglie l'utente.
    private var full: some View {
        HStack(alignment: .top, spacing: CGFloat(min(80, max(12, config.gap)))) {
            if config.flipped { fullLyrics }
            VStack(alignment: .leading, spacing: 14) {
                if showArtwork { LockArtwork(size: 240) }
                LockTitles(state: state, titleSize: 19, artistSize: 15)
                LockScrubber(state: state)
                LockControls(state: state, size: 1.1)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 240)
            if !config.flipped { fullLyrics }
        }
        .padding(26)
    }

    @ViewBuilder
    private var fullLyrics: some View {
        if lyricsContent.hasArea {
            LyricsArea(content: lyricsContent, state: state, fontSize: 24 * config.lyricsScale)
                .frame(width: 400, height: 420)
                .transition(.opacity)
        }
    }

    // MARK: Testo in primo piano

    private var lyricsFirst: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                if config.flipped {
                    LockControls(state: state, size: 0.85)
                        .padding(.trailing, 8)
                    LockTitles(state: state, titleSize: 16, artistSize: 13.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showArtwork { LockArtwork(size: 64) }
                } else {
                    if showArtwork { LockArtwork(size: 64) }
                    LockTitles(state: state, titleSize: 16, artistSize: 13.5)
                    Spacer(minLength: 8)
                    LockControls(state: state, size: 0.85)
                }
            }
            LockScrubber(state: state, compact: true)

            if lyricsContent.hasArea {
                LyricsArea(content: lyricsContent, state: state, fontSize: 30 * config.lyricsScale)
                    .frame(height: 340)
                    .transition(.opacity)
            }
        }
        .padding(24)
        .frame(width: 620)
    }
}

private enum LyricsContent: Equatable {
    case lyrics(Lyrics, key: String)
    case loading
    case missing(String)
    case none

    var hasArea: Bool { self != .none }

    /// Cambia quando cambia ciò che si vede: un brano nuovo, o l'attesa che finisce.
    var id: String {
        switch self {
        case .lyrics(_, let key): "lyrics|" + key
        case .loading:            "loading"
        case .missing(let text):  "missing|" + text
        case .none:               "none"
        }
    }
}

/// Lo spazio del testo: il contenuto nuovo entra in dissolvenza sopra quello vecchio.
private struct LyricsArea: View {
    let content: LyricsContent
    let state: NowPlaying
    let fontSize: CGFloat

    var body: some View {
        ZStack {
            Group {
                switch content {
                case .lyrics(let lyrics, _):
                    LyricsPanel(lyrics: lyrics, state: state, fontSize: fontSize)
                case .loading:
                    LyricsPlaceholder()
                case .missing(let text):
                    LyricsMissingNote(text: text, size: 15)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .none:
                    Color.clear
                }
            }
            .id(content.id)
            // Il vecchio esce in fretta, il nuovo entra subito dopo: due testi sovrapposti confondono.
            .transition(.asymmetric(
                insertion: .opacity.animation(.easeOut(duration: 0.35).delay(0.12)),
                removal: .opacity.animation(.easeIn(duration: 0.18))
            ))
        }
    }
}

/// Nello stile compatto c'è posto per una riga: quella cantata, o una nota se il testo non c'è.
private struct CompactLyricRow: View {
    let content: LyricsContent
    let state: NowPlaying
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            Group {
                if case .lyrics(let lyrics, _) = content, lyrics.isSynced {
                    CurrentLyricLine(lyrics: lyrics, state: state, size: size)
                } else if case .missing(let text) = content {
                    LyricsMissingNote(text: text)
                } else {
                    Text("♪")
                        .font(.system(size: size, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .id(content.id)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, minHeight: size * 2.6, maxHeight: size * 2.6, alignment: .leading)
        .animation(.easeInOut(duration: 0.4), value: content.id)
    }
}

// MARK: - Copertina

/// La copertina mostrata, e la sua versione sfocata per lo sfondo. Lo sfondo si sfoca una
/// volta sola, su un'immagine piccola e fuori dal thread principale: sfocare ogni volta la
/// copertina intera era il lavoro più pesante del lettore, e lo faceva scattare.
@MainActor
final class LockArtworkHolder: ObservableObject {
    struct Shown {
        let id: Int
        let image: NSImage
        let backdrop: NSImage?
    }

    @Published private(set) var current: Shown?

    private var cancellable: AnyCancellable?
    private var clearWork: DispatchWorkItem?
    private var pending: Task<Void, Never>?
    private var counter = 0

    func bind(to media: MediaService) {
        guard cancellable == nil else { return }
        cancellable = media.$artwork
            .removeDuplicates { $0 === $1 }
            .sink { [weak self] image in self?.show(image) }
    }

    private func show(_ image: NSImage?) {
        clearWork?.cancel()
        pending?.cancel()
        guard let image else {
            // Al cambio di brano la copertina nuova arriva un attimo dopo il titolo: intanto
            // resta la vecchia, invece di un lampo di vuoto.
            let work = DispatchWorkItem { [weak self] in self?.current = nil }
            clearWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
            return
        }
        counter += 1
        let id = counter
        let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        pending = Task { [weak self] in
            let blurred = await Task.detached(priority: .userInitiated) { source.flatMap(LockBackdrop.make) }.value
            guard !Task.isCancelled, let self else { return }
            let backdrop = blurred.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
            self.current = Shown(id: id, image: image, backdrop: backdrop)
        }
    }
}

private enum LockBackdrop {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// La copertina rimpicciolita, sfocata e più satura: il colore del brano senza i dettagli.
    static func make(from image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let side = max(input.extent.width, input.extent.height)
        guard side > 0 else { return nil }
        let scale = 72 / side
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 7)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.5])
            .cropped(to: small.extent)
        return context.createCGImage(blurred, from: small.extent)
    }
}

// MARK: - Sfondo della scheda

private struct LockCardBackground: View {
    let config: LockScreenConfig

    @EnvironmentObject private var holder: LockArtworkHolder
    @EnvironmentObject private var media: MediaService

    private var artworkColor: NSColor? { media.artworkColor }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CGFloat(min(60, max(0, config.cornerRadius))), style: .continuous)
    }

    var body: some View {
        fill
            .overlay {
                if config.border, config.background != .none {
                    shape.strokeBorder(.white.opacity(config.background == .glass ? 0.2 : 0.12), lineWidth: 1)
                }
            }
    }

    @ViewBuilder
    private var fill: some View {
        switch config.background {
        case .artwork:
            // In un overlay la copertina riempie la scheda senza imporle la sua forma quadrata.
            Color.black
                .overlay {
                    // Lo sfondo già sfocato: qui si allarga soltanto, e cambia in dissolvenza.
                    ZStack {
                        if let shown = holder.current, let backdrop = shown.backdrop {
                            Image(nsImage: backdrop)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fill)
                                .scaleEffect(1.25)
                                .opacity(0.95)
                                .id(shown.id)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.8), value: holder.current?.id)
                }
                .overlay(LinearGradient(colors: [.black.opacity(config.dim * 0.6), .black.opacity(min(0.9, config.dim * 1.4))], startPoint: .top, endPoint: .bottom))
                .clipShape(shape)
        case .glass:
            glass
                .overlay(shape.fill(.black.opacity(config.dim)))
        case .dark:
            shape.fill(.black.opacity(max(0.1, config.dim)))
        case .color:
            let color = Color(hexString: config.colorHex) ?? .indigo
            shape
                .fill(color.opacity(max(0.1, config.dim)))
                .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center)))
        case .none:
            Color.clear
        }
    }

    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26.0, *) {
            let tint = config.tintGlass ? artworkColor.map { Color(nsColor: $0).opacity(0.45) } : nil
            Color.clear.glassEffect((config.clearGlass ? Glass.clear : Glass.regular).tint(tint), in: shape)
        } else {
            VisualEffectBackground(material: config.clearGlass ? .popover : .hudWindow)
                .opacity(config.clearGlass ? 0.7 : 1)
                .overlay {
                    if config.tintGlass, let artworkColor { Color(nsColor: artworkColor).opacity(0.3) }
                }
                .clipShape(shape)
        }
    }
}

// MARK: - Pezzi

private struct LockArtwork: View {
    let size: CGFloat

    @EnvironmentObject private var media: MediaService
    @EnvironmentObject private var holder: LockArtworkHolder
    @Environment(\.lockLook) private var look

    private var radius: CGFloat {
        switch look.artworkShape {
        case .rounded: size * 0.1
        case .square:  size * 0.025
        case .circle:  size / 2
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                ArtworkThumbnail(image: holder.current?.image, size: size, radius: radius, showsPlaceholder: true)
                    .id(holder.current?.id ?? 0)
                    .transition(.opacity)
            }
            .shadow(color: .black.opacity(0.4), radius: size * 0.06, y: size * 0.03)
            .animation(.easeInOut(duration: 0.45), value: holder.current?.id)
            if size >= 100, look.showSourceIcon, let icon = media.sourceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .offset(x: look.artworkShape == .circle ? -8 : 8, y: look.artworkShape == .circle ? -8 : 8)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct LockTitles: View {
    let state: NowPlaying
    let titleSize: CGFloat
    let artistSize: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: state.title, size: titleSize, weight: .semibold, color: .white)
                MarqueeText(
                    text: state.artist.isEmpty ? (state.appName ?? "") : state.artist,
                    size: artistSize,
                    weight: .medium,
                    color: .white.opacity(0.62)
                )
            }
            .id(state.trackKey)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.35), value: state.trackKey)
    }
}

private struct LockControls: View {
    let state: NowPlaying
    var size: CGFloat = 1

    @EnvironmentObject private var media: MediaService
    @Environment(\.lockScreenIsPreview) private var isPreview

    var body: some View {
        HStack(spacing: 18 * size) {
            LockButton(symbol: "backward.fill", iconSize: 20 * size, side: 42 * size) { run(media.previous) }
            LockButton(symbol: state.isPlaying ? "pause.fill" : "play.fill", iconSize: 30 * size, side: 54 * size) {
                run(media.togglePlayPause)
            }
            .contentTransition(.symbolEffect(.replace))
            LockButton(symbol: "forward.fill", iconSize: 20 * size, side: 42 * size) { run(media.next) }
        }
    }

    private func run(_ action: () -> Void) {
        guard !isPreview else { return }
        action()
    }
}

private struct LockButton: View {
    let symbol: String
    let iconSize: CGFloat
    let side: CGFloat
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.92))
                .frame(width: side, height: side)
                .background(Circle().fill(.white.opacity(hovering ? 0.14 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(NotchPressStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

/// L'avanzamento: si trascina per spostarsi nel brano.
private struct LockScrubber: View {
    let state: NowPlaying
    var compact = false

    @EnvironmentObject private var media: MediaService
    @Environment(\.notchTheme) private var theme
    @Environment(\.lockScreenIsPreview) private var isPreview
    @Environment(\.lockLook) private var look
    @State private var dragPosition: Double?
    @State private var hovering = false

    var body: some View {
        if look.showProgress { scrubber }
    }

    private var scrubber: some View {
        TimelineView(.periodic(from: .now, by: state.isPlaying ? 0.5 : 60)) { context in
            let elapsed = dragPosition ?? state.currentElapsed(at: context.date)
            let fraction = state.duration > 0 ? min(1, max(0, elapsed / state.duration)) : 0

            VStack(spacing: compact ? 3 : 5) {
                bar(fraction: fraction)
                if look.showTimes {
                    HStack {
                        Text(Format.playback(elapsed))
                        Spacer()
                        Text(state.duration > 0 ? "-" + Format.playback(max(0, state.duration - elapsed)) : "")
                    }
                    .font(theme.numberFont(compact ? 10 : 11))
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private func bar(fraction: Double) -> some View {
        GeometryReader { geometry in
            let active = hovering || dragPosition != nil
            let height: CGFloat = active ? 9 : 6
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule()
                    .fill(look.accent.opacity(active ? 0.98 : 0.85))
                    .frame(width: max(height, geometry.size.width * fraction))
                    // Fra un aggiornamento e l'altro la barra scivola invece di andare a scatti.
                    .animation(dragPosition == nil && state.isPlaying ? .linear(duration: 0.5) : .easeOut(duration: 0.15), value: fraction)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard state.duration > 0, !isPreview else { return }
                        let position = min(1, max(0, value.location.x / geometry.size.width))
                        dragPosition = position * state.duration
                    }
                    .onEnded { _ in
                        if let dragPosition { media.seek(to: dragPosition) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.dragPosition = nil }
                    }
            )
            .onHover { hovering = $0 }
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: active)
        }
        .frame(height: 14)
    }
}

// MARK: - Testo

/// Il testo a tempo, come in Musica: la riga cantata in pieno, le altre sfumate,
/// e lo scorrimento che segue la voce riga dopo riga, con un'onda leggera.
private struct LyricsPanel: View {
    let lyrics: Lyrics
    let state: NowPlaying
    let fontSize: CGFloat

    var body: some View {
        if lyrics.isSynced {
            SyncedLyrics(lyrics: lyrics, state: state, fontSize: fontSize)
        } else {
            PlainLyrics(lyrics: lyrics, fontSize: fontSize * 0.72)
        }
    }
}

private struct LineHeightsKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct SyncedLyrics: View {
    let lyrics: Lyrics
    let state: NowPlaying
    let fontSize: CGFloat

    @EnvironmentObject private var media: MediaService
    @Environment(\.notchTheme) private var theme
    @Environment(\.lockScreenIsPreview) private var isPreview
    @Environment(\.lockLook) private var look
    @State private var heights: [Int: CGFloat] = [:]
    @StateObject private var clock = LyricsClock()

    /// La riga cantata sta a un terzo dell'altezza: sopra si vede da dove arriva, sotto cosa viene.
    private let anchor: CGFloat = 0.3
    private var spacing: CGFloat { fontSize * 0.6 }

    /// Le righe si ridisegnano solo quando cambia quella cantata, non a ogni frazione di secondo.
    var body: some View {
        let current = clock.index
        GeometryReader { geometry in
            let offset = geometry.size.height * anchor - top(of: max(current, 0))
            VStack(alignment: look.lyricsCentered ? .center : .leading, spacing: spacing) {
                ForEach(lyrics.lines) { line in
                    row(line, current: current, width: geometry.size.width)
                        .offset(y: offset)
                        .animation(
                            .spring(response: 0.7, dampingFraction: 0.86).delay(delay(for: line.id, current: current)),
                            value: current
                        )
                }
            }
            .frame(width: geometry.size.width, alignment: look.lyricsCentered ? .top : .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .onPreferenceChange(LineHeightsKey.self) { value in
                if value != heights { heights = value }
            }
        }
        .onAppear { clock.follow(lyrics, state) }
        .onChange(of: state) { _, newState in clock.follow(lyrics, newState) }
        .onDisappear { clock.stop() }
        .clipped()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.1),
                    .init(color: .black, location: 0.78),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    @ViewBuilder
    private func row(_ line: LyricLine, current: Int, width: CGFloat) -> some View {
        let distance = line.id - current
        let isCurrent = distance == 0
        Group {
            if line.isInterlude {
                InterludeDots(
                    isActive: isCurrent,
                    start: line.time,
                    end: lyrics.lines.first { $0.id == line.id + 1 }?.time ?? (line.time + 4),
                    state: state,
                    size: fontSize * 0.42,
                    color: look.accent
                )
            } else {
                Button {
                    if !isPreview { media.seek(to: max(0, line.time)) }
                } label: {
                    Text(line.text)
                        .font(.system(size: fontSize, weight: .bold, design: theme.appearance.font.design))
                        .foregroundStyle(.white.opacity(isCurrent ? 1 : (distance < 0 ? 0.3 : 0.38) + (look.onWallpaper ? 0.2 : 0)))
                        .multilineTextAlignment(look.lyricsCentered ? .center : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: width, alignment: look.lyricsCentered ? .center : .leading)
                        .scaleEffect(isCurrent ? 1 : 0.965, anchor: look.lyricsCentered ? .center : .leading)
                        // Le righe fuori vista non si sfocano: è lavoro che nessuno vedrebbe.
                        .blur(radius: isCurrent || abs(distance) > 7 ? 0 : min(Double(abs(distance)) * 0.7, 3))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: LineHeightsKey.self, value: [line.id: proxy.size.height])
            }
        )
    }

    /// Dove comincia una riga dentro la colonna, dalle altezze misurate.
    private func top(of index: Int) -> CGFloat {
        var y: CGFloat = 0
        for line in lyrics.lines where line.id < index {
            y += (heights[line.id] ?? fontSize * 1.25) + spacing
        }
        return y
    }

    /// Le righe sotto quella cantata partono un filo dopo l'una dopo l'altra: è l'onda.
    private func delay(for id: Int, current: Int) -> Double {
        let after = id - current
        guard after > 0 else { return 0 }
        return min(Double(after) * 0.04, 0.3)
    }

}

/// Quale riga si canta adesso. Invece di ricalcolarla cinque volte al secondo, si mette una
/// sveglia all'istante esatto della riga dopo: il testo si ridisegna solo quando serve.
@MainActor
private final class LyricsClock: ObservableObject {
    @Published private(set) var index = -1

    private var lyrics: Lyrics?
    private var state: NowPlaying?
    private var timer: Timer?

    func follow(_ lyrics: Lyrics, _ state: NowPlaying) {
        self.lyrics = lyrics
        self.state = state
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        timer?.invalidate()
        timer = nil
        guard let lyrics, let state else { return }
        let position = state.currentElapsed()
        let current = lyrics.index(at: position)
        if current != index { index = current }

        guard state.isPlaying, state.rate > 0, current + 1 < lyrics.lines.count else { return }
        let next = lyrics.lines[current + 1].time - Lyrics.lead
        let wait = max(0.02, (next - position) / state.rate + 0.01)
        let timer = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

/// Le pause strumentali: tre punti che si accendono mentre manca poco alla prossima riga.
private struct InterludeDots: View {
    let isActive: Bool
    let start: TimeInterval
    let end: TimeInterval
    let state: NowPlaying
    let size: CGFloat
    var color: Color = .white

    var body: some View {
        // Solo la pausa in corso si aggiorna nel tempo; le altre restano ferme e invisibili.
        if isActive, state.isPlaying {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                dots(progress: progress(at: context.date))
            }
        } else {
            dots(progress: isActive ? progress(at: Date()) : 0)
        }
    }

    private func progress(at date: Date) -> Double {
        let length = max(0.5, end - start)
        return min(1, max(0, (state.currentElapsed(at: date) + Lyrics.lead - start) / length))
    }

    private func dots(progress: Double) -> some View {
        HStack(spacing: size * 0.55) {
            ForEach(0..<3) { index in
                let lit = min(1, max(0, progress * 3 - Double(index)))
                Circle()
                    .fill(color.opacity(0.28 + 0.72 * lit))
                    .frame(width: size, height: size)
                    .scaleEffect(isActive ? 0.85 + 0.25 * lit : 0.6)
            }
        }
        .frame(height: isActive ? size * 2.2 : size * 0.6)
        .opacity(isActive ? 1 : 0.0)
        .animation(.easeInOut(duration: 0.25), value: progress)
    }
}

private struct PlainLyrics: View {
    let lyrics: Lyrics
    let fontSize: CGFloat

    @Environment(\.notchTheme) private var theme
    @Environment(\.lockLook) private var look

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: look.lyricsCentered ? .center : .leading, spacing: fontSize * 0.35) {
                ForEach(lyrics.lines) { line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(size: fontSize, weight: .semibold, design: theme.appearance.font.design))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(look.lyricsCentered ? .center : .leading)
                        .frame(maxWidth: .infinity, alignment: look.lyricsCentered ? .center : .leading)
                }
            }
            .padding(.vertical, 12)
        }
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

/// Nello stile compatto basta la riga del momento, che sale quando cambia.
private struct CurrentLyricLine: View {
    let lyrics: Lyrics
    let state: NowPlaying
    let size: CGFloat

    @Environment(\.notchTheme) private var theme
    @StateObject private var clock = LyricsClock()

    var body: some View {
        let index = clock.index
        let text = index >= 0 && index < lyrics.lines.count ? lyrics.lines[index].text : ""
        Group {
            ZStack(alignment: .leading) {
                Text(text.isEmpty ? "♪" : text)
                    .font(.system(size: size, weight: .bold, design: theme.appearance.font.design))
                    .foregroundStyle(.white.opacity(text.isEmpty ? 0.45 : 0.95))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(index)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
            .frame(height: size * 2.6, alignment: .leading)
            .clipped()
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: index)
        }
        .onAppear { clock.follow(lyrics, state) }
        .onChange(of: state) { _, newState in clock.follow(lyrics, newState) }
        .onDisappear { clock.stop() }
    }
}

private struct LyricsMissingNote: View {
    let text: String
    var size: CGFloat = 12

    var body: some View {
        Label(text, systemImage: "quote.bubble")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
    }
}

/// Mentre si cerca il testo: tre punti che respirano al posto delle righe.
private struct LyricsPlaceholder: View {
    @State private var breathing = false
    @State private var visible = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(.white.opacity(0.5))
                    .frame(width: 9, height: 9)
                    .scaleEffect(breathing ? 1 : 0.6)
                    .animation(.easeInOut(duration: 0.7).repeatForever().delay(Double(index) * 0.18), value: breathing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Un testo già in cache arriva in un attimo: i puntini compaiono solo se l'attesa dura.
        .opacity(visible ? 1 : 0)
        .onAppear {
            breathing = true
            withAnimation(.easeIn(duration: 0.3).delay(0.6)) { visible = true }
        }
    }
}
