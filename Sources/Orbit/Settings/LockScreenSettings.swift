import CoreImage
import ImageIO
import SwiftUI

// MARK: - Impostazioni

struct LockScreenSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            // L'anteprima resta in vista mentre si scorrono i controlli, come per la notch.
            if settings.config.lockScreen.style != .off {
                VStack(spacing: 10) {
                    LockScreenStage(maxWidth: 500, editable: true)
                    LockScreenPlacementBar()
                        .frame(width: 500)
                }
                .frame(maxWidth: .infinity)
                // Sotto la barra della finestra c'è la sfumatura del vetro: l'anteprima parte dopo.
                .padding(.top, 52)
                .padding(.bottom, 12)
                    .transition(.opacity)
                Divider()
            }
            form
        }
        .animation(.easeInOut(duration: 0.25), value: settings.config.lockScreen.style == .off)
    }

    private var form: some View {
        let config = settings.config.lockScreen
        return SettingsForm(section: .lockScreen, subtitle: tr("Quando blocchi il Mac, la musica resta a portata: comandi, avanzamento e il testo che scorre a tempo.")) {
            Section("Stile") {
                LockScreenStylePicker(columns: 2)
                    .padding(.vertical, 4)
            }

            if config.style != .off {
                Section {
                    LockScreenLookGallery()
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                } header: {
                    Text("Aspetto")
                } footer: {
                    Text("Un punto di partenza: sotto puoi ritoccare ogni dettaglio.")
                }

                Section("Scheda") {
                    Picker("Sfondo", selection: settings.binding(\.lockScreen.background)) {
                        ForEach(LockScreenBackground.allCases) { Text($0.label).tag($0) }
                    }
                    switch config.background {
                    case .artwork, .glass:
                        ValueSlider(
                            title: tr("Oscuramento"),
                            value: settings.binding(\.lockScreen.dim),
                            range: 0...0.9,
                            step: 0.05,
                            format: { "\(Int(($0 * 100).rounded()))%" }
                        )
                    case .dark, .color:
                        ValueSlider(
                            title: tr("Opacità"),
                            value: settings.binding(\.lockScreen.dim),
                            range: 0.1...1,
                            step: 0.05,
                            format: { "\(Int(($0 * 100).rounded()))%" }
                        )
                    case .none:
                        EmptyView()
                    }
                    if config.background == .color {
                        HexColorPicker(title: tr("Colore"), hex: settings.binding(\.lockScreen.colorHex))
                    }
                    if config.background == .glass {
                        Toggle("Vetro più limpido", isOn: settings.binding(\.lockScreen.clearGlass))
                            .help("Lascia vedere di più il wallpaper, come i widget della schermata di blocco di iPhone.")
                        Toggle("Colora il vetro con la copertina", isOn: settings.binding(\.lockScreen.tintGlass))
                    }
                    if config.background != .none {
                        ValueSlider(
                            title: tr("Arrotondamento"),
                            value: settings.binding(\.lockScreen.cornerRadius),
                            range: 0...50,
                            step: 1,
                            format: { "\(Int($0.rounded())) pt" }
                        )
                        Toggle("Bordo sottile", isOn: settings.binding(\.lockScreen.border))
                        Toggle("Ombra sotto la scheda", isOn: settings.binding(\.lockScreen.shadow))
                    }
                    if config.background.showsWallpaper {
                        Toggle("Ombra sotto testo e comandi", isOn: settings.binding(\.lockScreen.textShadow))
                            .help("Tiene leggibile il testo bianco anche sulle parti chiare del wallpaper.")
                    }
                }

                Section {
                    Picker("Copertina e comandi", selection: settings.binding(\.lockScreen.flipped)) {
                        Text("A sinistra").tag(false)
                        Text("A destra").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if config.style == .full {
                        ValueSlider(
                            title: tr("Spazio fra copertina e testo"),
                            value: settings.binding(\.lockScreen.gap),
                            range: 12...80,
                            step: 2,
                            format: { "\(Int($0.rounded())) pt" }
                        )
                    }
                    ValueSlider(
                        title: tr("Grandezza"),
                        value: settings.binding(\.lockScreen.scale),
                        range: 0.75...1.3,
                        step: 0.05,
                        format: { "\(Int(($0 * 100).rounded()))%" }
                    )
                    Button("Rimetti al centro") {
                        settings.update {
                            $0.lockScreen.placementX = nil
                            $0.lockScreen.placementY = nil
                            $0.lockScreen.side = .center
                            $0.lockScreen.position = .center
                        }
                    }
                } header: {
                    Text("Disposizione")
                } footer: {
                    Text("La posizione si sceglie trascinando il lettore nell'anteprima. Le zone rosse sono quelle di data, ora e password: lì il lettore non va mai.")
                }

                Section("Contenuto") {
                    Toggle("Copertina", isOn: settings.binding(\.lockScreen.showArtwork))
                    if config.showArtwork {
                        Picker("Forma della copertina", selection: settings.binding(\.lockScreen.artworkShape)) {
                            ForEach(LockArtworkShape.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if config.style == .full {
                            Toggle("Icona dell'app sulla copertina", isOn: settings.binding(\.lockScreen.showSourceIcon))
                        }
                    }
                    Toggle("Barra di avanzamento", isOn: settings.binding(\.lockScreen.showProgress))
                    if config.showProgress {
                        Toggle("Tempo trascorso e rimanente", isOn: settings.binding(\.lockScreen.showTimes))
                    }
                    Picker("Colore della barra", selection: settings.binding(\.lockScreen.accent)) {
                        ForEach(LockScreenAccent.allCases) { Text($0.label).tag($0) }
                    }
                    if config.accent == .custom {
                        HexColorPicker(title: tr("Colore"), hex: settings.binding(\.lockScreen.accentHex))
                    }
                }

                Section {
                    Toggle("Mostra il testo del brano", isOn: settings.binding(\.lockScreen.showLyrics))
                    if config.showLyrics {
                        Toggle("Testo centrato", isOn: settings.binding(\.lockScreen.lyricsCentered))
                        Toggle("Se manca, cercalo anche su NetEase Cloud Music", isOn: settings.binding(\.lockScreen.moreLyricsSources))
                            .help("LRCLIB ha pochi brani recenti o poco noti: NetEase ne ha molti di più, anche italiani.")
                        ValueSlider(
                            title: tr("Grandezza del testo"),
                            value: settings.binding(\.lockScreen.lyricsScale),
                            range: 0.8...1.3,
                            step: 0.05,
                            format: { "\(Int(($0 * 100).rounded()))%" }
                        )
                    }
                } header: {
                    Text("Testo")
                } footer: {
                    Text("Il testo arriva da LRCLIB, un archivio libero, e se lì non c'è da NetEase Cloud Music: a Mac bloccato Orbit vi cerca titolo e artista del brano, solo per le app di musica. Ciò che trova resta sul Mac.")
                }

                Section {
                    Toggle("Tieni acceso lo schermo mentre suona la musica", isOn: settings.binding(\.lockScreen.keepScreenOn))
                    if config.keepScreenOn {
                        Toggle("Anche quando il Mac va a batteria", isOn: settings.binding(\.lockScreen.keepScreenOnBattery))
                        Picker("Per quanto", selection: settings.binding(\.lockScreen.keepScreenOnLimited)) {
                            Text("Finché suona").tag(false)
                            Text("Per un tempo scelto").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if config.keepScreenOnLimited {
                            ScreenOnDurationPicker(minutes: settings.binding(\.lockScreen.keepScreenOnMinutes))
                        }
                    }
                } header: {
                    Text("Schermo")
                } footer: {
                    Text("A Mac bloccato macOS spegne lo schermo dopo pochi secondi. Così il testo e i comandi restano in vista, per esempio a una festa, e il Mac resta bloccato. Il tempo scelto parte quando blocchi il Mac; passato quello, o dopo un minuto di pausa, lo schermo torna a spegnersi come sempre.")
                }

                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                        Text("Per vederlo dal vivo, fai partire un brano e blocca il Mac con ⌃⌘Q.")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Comparire sopra la schermata di blocco richiede un'interfaccia privata di macOS: se un aggiornamento la cambia, il lettore smette di comparire senza altri effetti.")
                }
            }
        }
    }
}

// MARK: - Scelta dello stile

/// Le quattro schede degli stili, con lo stesso aspetto nella guida e nelle impostazioni.
struct LockScreenStylePicker: View {
    var columns = 2

    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        let selected = settings.config.lockScreen.style
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(LockScreenStyle.allCases) { style in
                Button {
                    settings.update { $0.lockScreen.style = style }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: style.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selected == style ? .white : .secondary)
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected == style ? Color.accentColor : Color.secondary.opacity(0.15)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(style.label).font(.body.weight(.medium)).foregroundStyle(.primary)
                            Text(style.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if selected == style {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(selected == style ? 0.7 : 0.3)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Una zona riservata: rossa a righe, con il suo nome sul lato verso il bordo dello schermo
/// (dove il lettore non arriva mai) e una linea piena sul lato verso lo spazio libero.
private struct LockZoneBand: View {
    let label: String
    /// Il lato della banda che dà sul bordo dello schermo.
    let edge: VerticalEdge

    var body: some View {
        ZStack(alignment: edge == .top ? .bottom : .top) {
            Color.red.opacity(0.16)
            Canvas { context, size in
                var path = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 46
                }
                context.stroke(path, with: .color(.red.opacity(0.28)), lineWidth: 6)
            }
            Rectangle()
                .fill(Color.red.opacity(0.9))
                .frame(height: 4)
        }
        .overlay(alignment: edge == .top ? .topLeading : .bottomLeading) {
            Text(label)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.red.opacity(0.85)))
                .padding(edge == .top ? .top : .bottom, 22)
                .padding(.leading, 40)
        }
    }
}

/// Sotto l'anteprima: dove sta il lettore, a colpo d'occhio, e gli allineamenti rapidi.
struct LockScreenPlacementBar: View {
    @EnvironmentObject private var settings: SettingsStore

    private static var freeMid: Double {
        Double(LockScreenZones.top + (1 - LockScreenZones.top - LockScreenZones.bottom) / 2)
    }

    var body: some View {
        HStack(spacing: 14) {
            Label("Trascinalo dove vuoi", systemImage: "hand.draw")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            ControlGroup {
                button("align.horizontal.left", tr("Tutto a sinistra")) { $0.placementX = 0 }
                button("align.horizontal.center", tr("Al centro")) { $0.placementX = 0.5 }
                button("align.horizontal.right", tr("Tutto a destra")) { $0.placementX = 1 }
            }
            .fixedSize()
            ControlGroup {
                button("align.vertical.top", tr("Subito sotto l'ora")) { $0.placementY = 0 }
                button("align.vertical.center", tr("A metà altezza")) { $0.placementY = Self.freeMid }
                button("align.vertical.bottom", tr("Subito sopra la password")) { $0.placementY = 1 }
            }
            .fixedSize()
        }
    }

    private func button(_ symbol: String, _ help: String, _ change: @escaping (inout LockScreenConfig) -> Void) -> some View {
        Button {
            settings.update { change(&$0.lockScreen) }
        } label: {
            Image(systemName: symbol)
        }
        .help(help)
    }
}

// MARK: - Aspetti pronti

/// Gli aspetti del lettore in miniatura, sopra il wallpaper vero: come la galleria dei temi.
struct LockScreenLookGallery: View {
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var wallpaper = WallpaperSnapshot.shared

    var body: some View {
        let current = LockScreenLook.current(settings.config.lockScreen)
        // Le schede si stringono fino a stare tutte in una riga, e vanno a capo solo se non c'è posto.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 10)], spacing: 10) {
            ForEach(LockScreenLook.all) { look in
                LockLookCard(look: look, wallpaper: wallpaper.image, isSelected: current?.id == look.id) {
                    settings.update { look.apply(to: &$0.lockScreen) }
                }
            }
        }
        .padding(.vertical, 2)
        .onAppear { wallpaper.load() }
    }
}

private struct LockLookCard: View {
    let look: LockScreenLook
    let wallpaper: NSImage?
    var isSelected: Bool
    var action: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Color.clear
                    .aspectRatio(104 / 66, contentMode: .fit)
                    .overlay(LockStageWallpaper(image: wallpaper))
                    .overlay(miniPlayer)
                    .clipShape(shape)
                .overlay(shape.stroke(isSelected ? Color.accentColor : Color.white.opacity(0.14), lineWidth: isSelected ? 2 : 1))

                Text(look.name)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var miniPlayer: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFF7A59), Color(hex: 0xC2337A)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(.white.opacity(0.95)).frame(width: 34, height: 4)
                Capsule().fill(.white.opacity(0.55)).frame(width: 22, height: 3)
                Capsule().fill(.white.opacity(0.75)).frame(width: 40, height: 2)
            }
        }
        .shadow(color: .black.opacity(look.background.showsWallpaper ? 0.4 : 0), radius: 2)
        .padding(7)
        .background(miniBackground)
    }

    @ViewBuilder
    private var miniBackground: some View {
        let card = RoundedRectangle(cornerRadius: look.cornerRadius / 4, style: .continuous)
        switch look.background {
        case .artwork:
            card
                .fill(LinearGradient(colors: [Color(hex: 0xA2365F), Color(hex: 0x5A2448)], startPoint: .top, endPoint: .bottom))
                .overlay(card.strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        case .glass:
            Group {
                if #available(macOS 26.0, *) {
                    let tint = look.tintGlass ? Color(hex: 0xC2337A).opacity(0.45) : nil
                    Color.clear.glassEffect((look.clearGlass ? Glass.clear : Glass.regular).tint(tint), in: card)
                } else {
                    VisualEffectBackground(material: .hudWindow, blending: .withinWindow).clipShape(card)
                }
            }
            .overlay(card.fill(.black.opacity(look.dim)))
        case .dark:
            card.fill(.black.opacity(look.dim))
        case .color:
            card.fill((Color(hexString: look.colorHex ?? "") ?? .indigo).opacity(look.dim))
        case .none:
            Color.clear
        }
    }
}

/// Il wallpaper del Mac, letto una volta e rimpicciolito: le anteprime lo usano come sfondo,
/// così si vede come sta il lettore sopra il proprio, non sopra uno inventato.
@MainActor
final class WallpaperSnapshot: ObservableObject {
    static let shared = WallpaperSnapshot()

    @Published private(set) var image: NSImage?
    private var loading = false

    func load() {
        guard image == nil, !loading else { return }
        guard let screen = NSScreen.screens.first, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return }
        loading = true
        Task.detached(priority: .utility) {
            let thumbnail = Self.thumbnail(of: url, maxPixels: 1600)
            await MainActor.run {
                self.image = thumbnail
                self.loading = false
            }
        }
    }

    private nonisolated static func thumbnail(of url: URL, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

/// Il wallpaper vero se lo si è potuto leggere, altrimenti un tramonto inventato.
struct LockStageWallpaper: View {
    let image: NSImage?

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0x1B2A5E), Color(hex: 0x3B2C6E), Color(hex: 0x9A4A7A), Color(hex: 0xE58A5C)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                GeometryReader { geometry in
                    RadialGradient(colors: [Color(hex: 0x6FA8FF).opacity(0.5), .clear], center: .init(x: 0.2, y: 0.25), startRadius: 0, endRadius: geometry.size.width * 0.46)
                    RadialGradient(colors: [Color(hex: 0xFFB36B).opacity(0.45), .clear], center: .init(x: 0.85, y: 0.9), startRadius: 0, endRadius: geometry.size.width * 0.4)
                }
            }
        }
    }
}

// MARK: - Anteprima

/// Una schermata di blocco in miniatura con il lettore vero sopra, alimentato da un brano
/// inventato: così si vede com'è anche senza musica, e i comandi non toccano il lettore vero.
struct LockScreenStage: View {
    var maxWidth: CGFloat = 560
    /// Nelle impostazioni il lettore si trascina, e si vedono le zone da lasciare libere.
    var editable = false

    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var demoMedia = MediaService()
    @StateObject private var demoLyrics = LyricsService()
    @ObservedObject private var wallpaperSnapshot = WallpaperSnapshot.shared
    /// Durante il trascinamento la posizione vive qui: si salva solo quando si lascia.
    @State private var dragConfig: LockScreenConfig?
    @State private var dragStart: CGPoint?
    @State private var snapX = false
    @State private var snapY = false
    @State private var hovering = false

    /// Lo schermo di un MacBook Pro da 14": la scheda vi appare nelle sue proporzioni vere.
    private static let screen = CGSize(width: 1512, height: 982)
    private static var bounds: CGRect { CGRect(origin: .zero, size: screen) }

    var body: some View {
        let config = dragConfig ?? settings.config.lockScreen
        let scale = maxWidth / Self.screen.width
        let placement = LockScreenWidgetController.placement(for: config, in: Self.bounds)
        // AppKit conta dal basso, SwiftUI dall'alto.
        let frame = CGRect(
            x: placement.frame.minX,
            y: Self.screen.height - placement.frame.maxY,
            width: placement.frame.width,
            height: placement.frame.height
        )

        ZStack(alignment: .topLeading) {
            wallpaper
            clock
            loginArea
            if editable { zones(active: hovering || dragConfig != nil) }

            if config.style != .off {
                LockScreenWidgetView(anchor: placement.anchor, scale: placement.scale, isPreview: true)
                    .environmentObject(demoMedia)
                    .environmentObject(demoLyrics)
                    .offset(x: frame.minX, y: frame.minY)
                    .transition(.opacity)
            }

            if editable, dragConfig != nil { snapGuides }
        }
        .frame(width: Self.screen.width, height: Self.screen.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: Self.screen.width * scale, height: Self.screen.height * scale, alignment: .topLeading)
        .allowsHitTesting(false)
        .overlay(alignment: .topLeading) {
            if editable, config.style != .off { handle(frame: frame, scale: scale) }
        }
        .coordinateSpace(name: "lockStage")
        // Mentre si trascina il lettore segue il puntatore, senza rincorrerlo.
        .animation(dragConfig == nil ? .easeInOut(duration: 0.3) : nil, value: config)
        .onAppear {
            wallpaperSnapshot.load()
            demoMedia.seedForPreview(DemoData.track, artwork: DemoData.artwork)
            demoLyrics.seedForPreview(DemoData.lyrics, track: DemoData.track)
            if CommandLine.arguments.contains("--cycle-tracks") { cycleTracks(step: 0) }
        }
    }

    // MARK: Trascinamento

    /// La presa: un riquadro invisibile sopra la finestra del lettore, che si sposta col puntatore.
    @ViewBuilder
    private func handle(frame: CGRect, scale: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: frame.width * scale, height: frame.height * scale)
            .offset(x: frame.minX * scale, y: frame.minY * scale)
            .onHover { inside in
                guard inside != hovering else { return }
                hovering = inside
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("lockStage"))
                    .onChanged { value in drag(by: value.translation, from: frame, scale: scale) }
                    .onEnded { _ in endDrag() }
            )
            .help("Trascina il lettore dove vuoi")
    }

    private func drag(by translation: CGSize, from frame: CGRect, scale: CGFloat) {
        let start = dragStart ?? CGPoint(x: frame.midX, y: frame.midY)
        if dragStart == nil {
            dragStart = start
            NSCursor.closedHand.push()
        }
        let screen = Self.screen
        var center = CGPoint(x: start.x + translation.width / scale, y: start.y + translation.height / scale)

        // Vicino al centro, il lettore si aggancia: è la posizione che si cerca più spesso.
        let free = LockScreenZones.free(in: Self.bounds)
        let freeMidY = screen.height - free.midY
        let threshold = 10 / scale
        snapX = abs(center.x - screen.width / 2) < threshold
        snapY = abs(center.y - freeMidY) < threshold
        if snapX { center.x = screen.width / 2 }
        if snapY { center.y = freeMidY }

        var config = settings.config.lockScreen
        config.placementX = Double(center.x / screen.width)
        config.placementY = Double(center.y / screen.height)
        // Si ricorda la posizione dentro la zona libera, non quella del puntatore oltre il bordo.
        let placed = LockScreenWidgetController.placement(for: config, in: Self.bounds).frame
        if !snapX { config.placementX = Double(placed.midX / screen.width) }
        if !snapY { config.placementY = Double((screen.height - placed.midY) / screen.height) }
        dragConfig = config
    }

    private func endDrag() {
        if dragStart != nil { NSCursor.pop() }
        if let dragConfig {
            settings.update {
                $0.lockScreen.placementX = dragConfig.placementX
                $0.lockScreen.placementY = dragConfig.placementY
            }
        }
        dragConfig = nil
        dragStart = nil
        snapX = false
        snapY = false
    }

    // MARK: Zone

    /// In alto data e ora, in basso l'utente e la password: lì il lettore non può andare.
    private func zones(active: Bool) -> some View {
        let screen = Self.screen
        return ZStack(alignment: .topLeading) {
            LockZoneBand(label: tr("Data e ora"), edge: .top)
                .frame(width: screen.width, height: screen.height * LockScreenZones.top)
            LockZoneBand(label: tr("Utente e password"), edge: .bottom)
                .frame(width: screen.width, height: screen.height * LockScreenZones.bottom)
                .offset(y: screen.height * (1 - LockScreenZones.bottom))
        }
        .opacity(active ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.2), value: active)
    }

    /// Le linee del centro, quando il lettore vi si aggancia.
    private var snapGuides: some View {
        let screen = Self.screen
        let free = LockScreenZones.free(in: Self.bounds)
        let top = screen.height - free.maxY
        return ZStack(alignment: .topLeading) {
            if snapX {
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 3, height: free.height)
                    .offset(x: screen.width / 2 - 1.5, y: top)
            }
            if snapY {
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: free.width, height: 3)
                    .offset(x: free.minX, y: top + free.height / 2 - 1.5)
            }
        }
    }

    /// `--cycle-tracks`: cambia brano ogni pochi secondi, per guardare i passaggi.
    /// Il testo arriva un attimo dopo il brano, come dalla rete; ogni terzo brano non ne ha.
    private func cycleTracks(step: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            var track = DemoData.track
            track.title = step % 2 == 0 ? "Paper Satellites" : DemoData.track.title
            track.artist = step % 2 == 0 ? "The Long Weekend" : DemoData.track.artist
            track.timestamp = Date()
            demoMedia.seedForPreview(track, artwork: step % 2 == 0 ? DemoData.artwork.hueShifted : DemoData.artwork)
            demoLyrics.seedForPreview(.loading, track: track)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                demoLyrics.seedForPreview(step % 3 == 2 ? .unavailable : .loaded(DemoData.lyrics), track: track)
            }
            cycleTracks(step: step + 1)
        }
    }

    private var wallpaper: some View {
        LockStageWallpaper(image: wallpaperSnapshot.image)
            .frame(width: Self.screen.width, height: Self.screen.height)
            .clipped()
    }

    private var clock: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 0) {
                Text(context.date.formatted(Date.FormatStyle(locale: L10n.locale).weekday(.wide).day().month(.wide)))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text(context.date.formatted(Date.FormatStyle(locale: L10n.locale).hour().minute()))
                    .font(.system(size: 132, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
            }
            .frame(width: Self.screen.width)
            .padding(.top, 70)
        }
    }

    private var loginArea: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(.white.opacity(0.25))
                .frame(width: 64, height: 64)
                .overlay(Image(systemName: "person.fill").font(.system(size: 30)).foregroundStyle(.white.opacity(0.85)))
            Capsule()
                .fill(.white.opacity(0.2))
                .frame(width: 210, height: 34)
        }
        .frame(width: Self.screen.width)
        .offset(y: Self.screen.height - 150)
    }
}

private extension NSImage {
    /// Una copertina diversa per l'anteprima che cambia brano.
    var hueShifted: NSImage {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }
        let output = CIImage(cgImage: cg).applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: 2.2])
        guard let shifted = CIContext().createCGImage(output, from: output.extent) else { return self }
        return NSImage(cgImage: shifted, size: size)
    }
}
