import Foundation
import SwiftUI

/// Tutto ciò che si può personalizzare. Vive in `~/.config/orbit/config.json`,
/// si modifica dalle impostazioni o a mano, e viene riletto a caldo.
///
/// Ogni valore ha un default: `SettingsStore` fonde il file dell'utente sopra i
/// default prima di decodificarlo, così le chiavi mancanti non sono mai un errore.
struct OrbitConfig: Codable, Equatable {
    /// 2: avvisi più discreti (solo ciò che richiede te). Vedi `upgraded()`.
    var schemaVersion = 2
    var onboardingDone = false
    var language: AppLanguage = .system
    var agents = AgentsConfig()
    var layout = LayoutConfig()
    var appearance = AppearanceConfig()
    var behavior = BehaviorConfig()
    var peeks = PeekConfig()
    var media = MediaConfig()
    var lockScreen = LockScreenConfig()
    var calendar = CalendarConfig()
    var shelf = ShelfConfig()
    var hud = HUDConfig()
    var clipboard = ClipboardConfig()
    var launcher = LauncherConfig()
    var customWidgets: [CustomWidgetConfig] = []
    var hotkeys: [HotkeyBinding] = HotkeyBinding.defaults
    var profiles: [ProfileConfig] = []
    var activeProfileID: String?

    init() {}

    /// Porta una configurazione salvata da una versione precedente alle regole attuali.
    nonisolated func upgraded() -> OrbitConfig {
        var config = self
        if config.schemaVersion < 2 {
            // Le versioni precedenti avvisavano di tutto: chi le aveva lasciate così riceve
            // i nuovi valori, chi le aveva già ridotte a mano le ritrova a posto.
            config.peeks.agentAttention = false
            config.peeks.trackChange = false
            config.peeks.charger = false
            config.peeks.lowBattery = false
            config.schemaVersion = 2
        }
        // Powered Notch kept its inbox under ~/.powered-notch: the folder now lives under the new name.
        let legacyPrefix = "~/.powered-notch/"
        for index in config.agents.providers.indices {
            if let path = config.agents.providers[index].path, path.hasPrefix(legacyPrefix) {
                config.agents.providers[index].path = "~/.orbit/" + path.dropFirst(legacyPrefix.count)
            }
        }
        return config
    }

    /// Una sezione illeggibile ricade sul suo default senza trascinare giù le altre.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decode(T.self, forKey: key)) ?? fallback
        }
        let d = OrbitConfig()
        schemaVersion = read(.schemaVersion, d.schemaVersion)
        onboardingDone = read(.onboardingDone, d.onboardingDone)
        language = read(.language, d.language)
        agents = read(.agents, d.agents)
        layout = read(.layout, d.layout)
        appearance = read(.appearance, d.appearance)
        behavior = read(.behavior, d.behavior)
        peeks = read(.peeks, d.peeks)
        media = read(.media, d.media)
        lockScreen = read(.lockScreen, d.lockScreen)
        calendar = read(.calendar, d.calendar)
        shelf = read(.shelf, d.shelf)
        hud = read(.hud, d.hud)
        clipboard = read(.clipboard, d.clipboard)
        launcher = read(.launcher, d.launcher)
        customWidgets = read(.customWidgets, d.customWidgets)
        hotkeys = read(.hotkeys, d.hotkeys)
        profiles = read(.profiles, d.profiles)
        activeProfileID = try? c.decodeIfPresent(String.self, forKey: .activeProfileID)
    }
}

// MARK: - Layout

/// Cosa compare nella notch e dove.
struct LayoutConfig: Codable, Equatable {
    /// Elementi a sinistra della notch chiusa, nell'ordine in cui compaiono.
    var closedLeading: [String] = ["media.artwork", "agents.status"]
    /// Elementi a destra della notch chiusa.
    var closedTrailing: [String] = ["agents.dots", "media.visualizer"]
    /// Ali uguali: la notch resta centrata anche con contenuti diversi ai due lati.
    var symmetricWings = true
    /// Elementi compatti a destra nella testata della notch aperta.
    var headerTrailing: [String] = ["battery.level"]
    var pages: [PageConfig] = PageConfig.defaults
    var startMode: StartPageMode = .smart
    var startPageID: String?
}

enum StartPageMode: String, Codable, CaseIterable, Identifiable {
    case first, last, smart, specific
    var id: String { rawValue }
    var label: String {
        switch self {
        case .first:    tr("La prima")
        case .last:     tr("L'ultima usata")
        case .smart:    tr("Intelligente")
        case .specific: tr("Una a scelta")
        }
    }
    var help: String {
        switch self {
        case .first:    tr("Si apre sempre sulla prima pagina.")
        case .last:     tr("Riprende dalla pagina che avevi lasciato.")
        case .smart:    tr("Va sulla pagina degli agenti se una sessione ti aspetta, altrimenti sulla prima.")
        case .specific: tr("Si apre sempre sulla pagina che scegli.")
        }
    }
}

/// Una pagina della notch aperta: una riga di widget.
struct PageConfig: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var symbol: String
    var widgets: [WidgetPlacement]
    /// Altezza di questa pagina; se manca vale quella generale.
    var height: Double?

    static var defaults: [PageConfig] {
        [
            PageConfig(id: "home", title: "Home", symbol: "house.fill", widgets: [
                WidgetPlacement(kind: "agents", weight: 1.3),
                WidgetPlacement(kind: "media", weight: 1.25),
                WidgetPlacement(kind: "calendar", weight: 0.85)
            ]),
            PageConfig(id: "agents", title: "Agenti", symbol: "sparkles", widgets: [
                WidgetPlacement(kind: "agents")
            ], height: 300),
            PageConfig(id: "shelf", title: "Scaffale", symbol: "tray.full.fill", widgets: [
                WidgetPlacement(kind: "shelf")
            ])
        ]
    }
}

struct WidgetPlacement: Codable, Equatable, Identifiable {
    var id: String
    var kind: String
    /// Larghezza relativa rispetto agli altri widget della pagina.
    var weight: Double
    /// Si impila sotto il widget precedente invece di stargli accanto.
    var stacked: Bool

    /// Senza un id esplicito vale il tipo: i layout di serie restano così sempre uguali
    /// a se stessi. L'editor ne passa uno univoco, perché lo stesso widget può comparire due volte.
    init(id: String? = nil, kind: String, weight: Double = 1, stacked: Bool = false) {
        self.id = id ?? kind
        self.kind = kind
        self.weight = weight
        self.stacked = stacked
    }
}

// MARK: - Aspetto

enum SurfaceStyle: String, Codable, CaseIterable, Identifiable {
    case solid, gradient, glass, artwork
    var id: String { rawValue }
    var label: String {
        switch self {
        case .solid:    tr("Tinta unita")
        case .gradient: tr("Sfumatura")
        case .glass:    tr("Liquid Glass")
        case .artwork:  tr("Dalla copertina")
        }
    }
}

enum AccentMode: String, Codable, CaseIterable, Identifiable {
    case custom, system, artwork
    var id: String { rawValue }
    var label: String {
        switch self {
        case .custom:  tr("Personalizzato")
        case .system:  tr("Di sistema")
        case .artwork: tr("Dalla copertina")
        }
    }
}

enum CardStyle: String, Codable, CaseIterable, Identifiable {
    case filled, outlined, plain
    var id: String { rawValue }
    var label: String {
        switch self {
        case .filled:   tr("Piene")
        case .outlined: tr("Bordo")
        case .plain:    tr("Nessuna")
        }
    }
}

enum FontChoice: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, mono
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system:  tr("San Francisco")
        case .rounded: tr("Arrotondato")
        case .serif:   tr("New York")
        case .mono:    tr("Monospaziato")
        }
    }
    var design: Font.Design {
        switch self {
        case .system:  .default
        case .rounded: .rounded
        case .serif:   .serif
        case .mono:    .monospaced
        }
    }
}

enum TabStyle: String, Codable, CaseIterable, Identifiable {
    case icons, iconsAndTitles, titles
    var id: String { rawValue }
    var label: String {
        switch self {
        case .icons:          tr("Icone")
        case .iconsAndTitles: tr("Icone e nomi")
        case .titles:         tr("Nomi")
        }
    }
}

enum MotionStyle: String, Codable, CaseIterable, Identifiable {
    case fluid, snappy, bouncy, gentle, instant
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fluid:   tr("Fluido")
        case .snappy:  tr("Scattante")
        case .bouncy:  tr("Elastico")
        case .gentle:  tr("Morbido")
        case .instant: tr("Nessuna animazione")
        }
    }

    func animation(speed: Double) -> Animation? {
        let speed = max(0.25, speed)
        switch self {
        case .fluid:   return .spring(response: 0.46 / speed, dampingFraction: 0.82)
        case .snappy:  return .spring(response: 0.30 / speed, dampingFraction: 0.86)
        case .bouncy:  return .spring(response: 0.52 / speed, dampingFraction: 0.66)
        case .gentle:  return .spring(response: 0.70 / speed, dampingFraction: 0.92)
        case .instant: return nil
        }
    }
}

enum VisualizerStyle: String, Codable, CaseIterable, Identifiable {
    case bars, capsules, dots, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bars:     tr("Barre")
        case .capsules: tr("Capsule")
        case .dots:     tr("Puntini")
        case .off:      tr("Nascosto")
        }
    }
}

struct AppearanceConfig: Codable, Equatable {
    var themeID = "notte"
    var surface: SurfaceStyle = .solid
    var solidHex = "#000000"
    var gradientHex = ["#050507", "#14141B"]
    /// Quanto scurire il vetro: troppo chiaro e il testo non si legge più.
    var glassDim: Double = 0.35
    var accentMode: AccentMode = .artwork
    var accentHex = "#FFB37C"

    // Forma
    var closedEarRadius: Double = 6
    var closedBottomRadius: Double = 11
    var openEarRadius: Double = 15
    var openBottomRadius: Double = 30
    var openWidth: Double = 820
    var openHeight: Double = 244
    var maxWingWidth: Double = 170

    // Profondità
    var shadow: Double = 0.75
    var border: Double = 0.5
    var glow: Double = 0.55
    /// La notch chiusa si illumina quando un agente ti aspetta.
    var attentionGlow = true

    // Contenuto
    var cardStyle: CardStyle = .filled
    var cardRadius: Double = 18
    var widgetSpacing: Double = 8
    var font: FontChoice = .system
    var textScale: Double = 1
    var tabStyle: TabStyle = .icons

    // Movimento
    var motion: MotionStyle = .fluid
    var motionSpeed: Double = 1
    var contentBlur = true
    var hoverBump = true
    var visualizer: VisualizerStyle = .bars
}

// MARK: - Comportamento

enum DisplayMode: String, Codable, CaseIterable, Identifiable {
    case auto, main, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: tr("Schermo con la notch")
        case .main: tr("Schermo principale")
        case .all:  tr("Tutti gli schermi")
        }
    }
}

enum FullscreenPolicy: String, Codable, CaseIterable, Identifiable {
    case never, mediaOnly, always
    var id: String { rawValue }
    var label: String {
        switch self {
        case .never:     tr("Mai")
        case .mediaOnly: tr("Solo guardando un video")
        case .always:    tr("Sempre")
        }
    }
}

struct BehaviorConfig: Codable, Equatable {
    var openOnHover = true
    var hoverDelay: Double = 0.14
    var closeDelay: Double = 0.28
    var closeOnMouseLeave = true
    var closeOnClickOutside = true
    var gestures = true
    var haptics = true
    var displayMode: DisplayMode = .auto
    var virtualNotchWidth: Double = 190
    var hideInFullscreen: FullscreenPolicy = .mediaOnly
    var hideFromScreenCapture = false
    var showMenuBarIcon = true
    var menuBarShowsAgentCount = false
    var settingsButtonInNotch = true
    var showOnLockScreen = false
    var openShelfOnDrag = true
}

struct PeekConfig: Codable, Equatable {
    var enabled = true
    var duration: Double = 4
    var agentBlocked = true
    // Di serie scende solo ciò che richiede una tua azione. "Ha finito" resta come alone
    // nella notch chiusa: un avviso a ogni passaggio di stato diventa rumore in fretta.
    var agentAttention = false
    var agentError = true
    var agentEnded = false
    var agentSound = ""
    /// Quanto deve restare stabile il nuovo stato prima di avvisare.
    var agentSettleSeconds: Double = 4
    /// Una sessione non avvisa più di una volta in questo tempo.
    var agentCooldownSeconds: Double = 60
    var trackChange = false
    var charger = false
    var lowBattery = false
    var bluetooth = false
    var upcomingEvent = true
    var upcomingMinutes: Double = 5
    var timerDone = true
    /// Niente avvisi mentre guardi un video (un'app che non è di sola musica, in primo piano).
    var quietDuringVideo = true
    /// Niente avvisi mentre un'app è a tutto schermo.
    var quietInFullscreen = false
}

struct MediaConfig: Codable, Equatable {
    var showShuffleRepeat = false
    var tintWithArtwork = true
    /// Copertina e visualizzatore nella notch chiusa solo per le app di musica: un video
    /// nel browser non deve allargare la notch.
    var wingsMusicAppsOnly = true
    /// Per quanti secondi la copertina resta nelle ali dopo la pausa.
    var pausedLingerSeconds: Double = 12
}

// MARK: - Schermata di blocco

/// Quanto mostra il lettore sulla schermata di blocco.
enum LockScreenStyle: String, Codable, CaseIterable, Identifiable {
    case off, compact, full, lyrics
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off:     tr("Nessuno")
        case .compact: tr("Compatto")
        case .full:    tr("Completo")
        case .lyrics:  tr("Testo in primo piano")
        }
    }
    var detail: String {
        switch self {
        case .off:     tr("La schermata di blocco resta quella di macOS.")
        case .compact: tr("Copertina, comandi e avanzamento in una scheda discreta.")
        case .full:    tr("Copertina grande e il testo che scorre a tempo.")
        case .lyrics:  tr("Il testo in grande, come in Musica a tutto schermo.")
        }
    }
    var symbol: String {
        switch self {
        case .off:     "lock.slash"
        case .compact: "rectangle.fill"
        case .full:    "rectangle.split.2x1.fill"
        case .lyrics:  "quote.bubble.fill"
        }
    }
}

enum LockScreenPosition: String, Codable, CaseIterable, Identifiable {
    case upper, center, lower
    var id: String { rawValue }
    var label: String {
        switch self {
        case .upper:  tr("Sotto l'orologio")
        case .center: tr("Al centro")
        case .lower:  tr("In basso")
        }
    }
}

enum LockScreenBackground: String, Codable, CaseIterable, Identifiable {
    case artwork, glass, dark, color, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .artwork: tr("Dalla copertina")
        case .glass:   tr("Liquid Glass")
        case .dark:    tr("Scuro")
        case .color:   tr("Colore")
        case .none:    tr("Trasparente")
        }
    }
    /// Lo sfondo lascia vedere il wallpaper: il testo ha bisogno di un'ombra per leggersi.
    var showsWallpaper: Bool { self == .none || self == .glass }
}

/// Di lato, rispetto al centro dello schermo.
enum LockScreenSide: String, Codable, CaseIterable, Identifiable {
    case leading, center, trailing
    var id: String { rawValue }
    var label: String {
        switch self {
        case .leading:  tr("A sinistra")
        case .center:   tr("Al centro")
        case .trailing: tr("A destra")
        }
    }
}

/// Il colore della barra di avanzamento e dei punti delle pause.
enum LockScreenAccent: String, Codable, CaseIterable, Identifiable {
    case white, artwork, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .white:   tr("Bianco")
        case .artwork: tr("Dalla copertina")
        case .custom:  tr("Personalizzato")
        }
    }
}

enum LockArtworkShape: String, Codable, CaseIterable, Identifiable {
    case rounded, square, circle
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rounded: tr("Arrotondata")
        case .square:  tr("Quadrata")
        case .circle:  tr("Rotonda")
        }
    }
}

struct LockScreenConfig: Codable, Equatable {
    /// Spento di serie: si sceglie nella guida del primo avvio o nelle impostazioni.
    var style: LockScreenStyle = .off
    var position: LockScreenPosition = .center
    var side: LockScreenSide = .center
    /// Dove l'utente ha trascinato il lettore: il centro, in frazioni dello schermo (y dall'alto).
    /// Senza, valgono altezza e lato. Ogni asse è indipendente.
    var placementX: Double?
    var placementY: Double?
    /// Grandezza dell'intero lettore rispetto a quella di serie.
    var scale: Double = 1
    /// Copertina e comandi a destra, testo a sinistra.
    var flipped = false
    /// Lo spazio fra la colonna della copertina e il testo, nello stile completo.
    var gap: Double = 30

    // Scheda
    var background: LockScreenBackground = .artwork
    /// Quanto si scurisce lo sfondo (copertina, vetro) o quanto è pieno il colore (scuro, colore).
    var dim: Double = 0.3
    var colorHex = "#1F3A6E"
    /// Il vetro più limpido, quello della schermata di blocco di iOS.
    var clearGlass = false
    /// Il vetro prende il colore della copertina.
    var tintGlass = false
    var cornerRadius: Double = 30
    var border = true
    var shadow = true
    /// Un'ombra morbida sotto testo e comandi, per leggerli sopra qualunque wallpaper.
    var textShadow = true

    // Contenuto
    var showArtwork = true
    var artworkShape: LockArtworkShape = .rounded
    var showSourceIcon = true
    var showProgress = true
    var showTimes = true
    var accent: LockScreenAccent = .white
    var accentHex = "#FF5E7A"

    // Testo
    /// Il testo sincronizzato: titolo e artista si cercano su LRCLIB.
    var showLyrics = true
    /// Se LRCLIB non ha il brano, lo si cerca anche su NetEase Cloud Music.
    var moreLyricsSources = true
    /// Grandezza del testo rispetto a quella di serie.
    var lyricsScale: Double = 1
    var lyricsCentered = false

    /// Mentre la musica suona lo schermo bloccato resta acceso, invece di spegnersi dopo pochi secondi.
    var keepScreenOn = true
    var keepScreenOnBattery = true
    /// Se attivo, lo schermo resta acceso al massimo `keepScreenOnMinutes` dal blocco del Mac.
    var keepScreenOnLimited = false
    var keepScreenOnMinutes = 60

    static let screenOnMinutesRange = 5...480

    init() {}

    /// Le chiavi aggiunte dopo restano al loro default: una configurazione vecchia non torna a zero.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LockScreenConfig()
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        style = read(.style, d.style)
        position = read(.position, d.position)
        side = read(.side, d.side)
        placementX = (try? c.decodeIfPresent(Double.self, forKey: .placementX)) ?? nil
        placementY = (try? c.decodeIfPresent(Double.self, forKey: .placementY)) ?? nil
        scale = read(.scale, d.scale)
        flipped = read(.flipped, d.flipped)
        gap = read(.gap, d.gap)
        background = read(.background, d.background)
        dim = read(.dim, background == .dark ? 0.58 : d.dim)
        colorHex = read(.colorHex, d.colorHex)
        clearGlass = read(.clearGlass, d.clearGlass)
        tintGlass = read(.tintGlass, d.tintGlass)
        cornerRadius = read(.cornerRadius, d.cornerRadius)
        border = read(.border, background != .none)
        shadow = read(.shadow, background != .none)
        textShadow = read(.textShadow, d.textShadow)
        showArtwork = read(.showArtwork, d.showArtwork)
        artworkShape = read(.artworkShape, d.artworkShape)
        showSourceIcon = read(.showSourceIcon, d.showSourceIcon)
        showProgress = read(.showProgress, d.showProgress)
        showTimes = read(.showTimes, d.showTimes)
        accent = read(.accent, d.accent)
        accentHex = read(.accentHex, d.accentHex)
        showLyrics = read(.showLyrics, d.showLyrics)
        moreLyricsSources = read(.moreLyricsSources, d.moreLyricsSources)
        lyricsScale = read(.lyricsScale, d.lyricsScale)
        lyricsCentered = read(.lyricsCentered, d.lyricsCentered)
        keepScreenOn = read(.keepScreenOn, d.keepScreenOn)
        keepScreenOnBattery = read(.keepScreenOnBattery, d.keepScreenOnBattery)
        keepScreenOnLimited = read(.keepScreenOnLimited, d.keepScreenOnLimited)
        keepScreenOnMinutes = min(Self.screenOnMinutesRange.upperBound,
                                  max(Self.screenOnMinutesRange.lowerBound, read(.keepScreenOnMinutes, d.keepScreenOnMinutes)))
    }
}

/// Un aspetto pronto per il lettore della schermata di blocco: come i temi della notch,
/// un punto di partenza che poi si ritocca a piacere.
struct LockScreenLook: Identifiable {
    let id: String
    let name: String
    let background: LockScreenBackground
    var dim: Double = 0.3
    var clearGlass = false
    var tintGlass = false
    var colorHex: String?
    var cornerRadius: Double = 30
    var border = true
    var shadow = true

    func apply(to config: inout LockScreenConfig) {
        config.background = background
        config.dim = dim
        config.clearGlass = clearGlass
        config.tintGlass = tintGlass
        if let colorHex { config.colorHex = colorHex }
        config.cornerRadius = cornerRadius
        config.border = border
        config.shadow = shadow
        if background.showsWallpaper { config.textShadow = true }
    }

    func matches(_ config: LockScreenConfig) -> Bool {
        guard config.background == background else { return false }
        switch background {
        case .glass: return config.clearGlass == clearGlass && config.tintGlass == tintGlass
        default:     return true
        }
    }

    static let all: [LockScreenLook] = [
        LockScreenLook(id: "artwork", name: tr("Copertina"), background: .artwork, dim: 0.3),
        LockScreenLook(id: "glass", name: tr("Liquid Glass"), background: .glass, dim: 0.12, cornerRadius: 34),
        LockScreenLook(id: "clear-glass", name: tr("Vetro limpido"), background: .glass, dim: 0, clearGlass: true, cornerRadius: 34, shadow: false),
        LockScreenLook(id: "tinted-glass", name: tr("Vetro colorato"), background: .glass, dim: 0.05, tintGlass: true, cornerRadius: 34),
        LockScreenLook(id: "transparent", name: tr("Trasparente"), background: .none, cornerRadius: 30, border: false, shadow: false),
        LockScreenLook(id: "dark", name: tr("Scuro"), background: .dark, dim: 0.58),
        LockScreenLook(id: "color", name: tr("Colore"), background: .color, dim: 0.8, colorHex: "#1F3A6E")
    ]

    static func current(_ config: LockScreenConfig) -> LockScreenLook? {
        all.first { $0.matches(config) }
    }
}

struct CalendarConfig: Codable, Equatable {
    var hiddenCalendarIDs: [String] = []
    var showAllDay = true
    var showReminders = true
    var showJoinButton = true
}

struct ShelfConfig: Codable, Equatable {
    /// Copia i file nello scaffale invece di limitarsi a ricordarne la posizione.
    var copyFiles = false
    var removeAfterDragOut = false
}

enum HUDStyle: String, Codable, CaseIterable, Identifiable {
    case inline, below
    var id: String { rawValue }
    var label: String {
        switch self {
        case .inline: tr("Ai lati della notch")
        case .below:  tr("Sotto la notch")
        }
    }
}

struct HUDConfig: Codable, Equatable {
    var replaceSystemHUD = false
    var style: HUDStyle = .inline
    var showPercent = true
    var useAccent = false
    var duration: Double = 1.6
}

struct ClipboardConfig: Codable, Equatable {
    var maxItems = 30
}

// MARK: - Collegamenti

enum LauncherItemKind: String, Codable, CaseIterable, Identifiable {
    case app, shortcut, url, command
    var id: String { rawValue }
    var label: String {
        switch self {
        case .app:      tr("App")
        case .shortcut: tr("Comando rapido")
        case .url:      tr("Link")
        case .command:  tr("Comando di shell")
        }
    }
}

struct LauncherItem: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var kind: LauncherItemKind
    /// Percorso dell'app, nome del comando rapido, URL o riga di comando.
    var target: String
    var symbol: String?
}

struct LauncherConfig: Codable, Equatable {
    var items: [LauncherItem] = [
        LauncherItem(id: "terminal", name: "Terminale", kind: .app, target: "/System/Applications/Utilities/Terminal.app"),
        LauncherItem(id: "notes", name: "Note", kind: .app, target: "/System/Applications/Notes.app"),
        LauncherItem(id: "shortcuts", name: "Comandi rapidi", kind: .app, target: "/System/Applications/Shortcuts.app"),
        LauncherItem(id: "settings", name: "Impostazioni", kind: .app, target: "/System/Applications/System Settings.app")
    ]
}

// MARK: - Widget personalizzati

/// Un widget alimentato da un comando: chiunque sappia scrivere uno script può
/// aggiungere alla notch quello che vuole, senza toccare il codice dell'app.
struct CustomWidgetConfig: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var symbol = "terminal.fill"
    var command: String
    var refreshSeconds: Double = 60
}

// MARK: - Scorciatoie

enum HotkeyAction: String, Codable, CaseIterable, Identifiable {
    case toggleNotch, openAgents, nextPage, previousPage, playPause, nextTrack, previousTrack, openSettings

    var id: String { rawValue }
    var label: String {
        switch self {
        case .toggleNotch:   tr("Apri o chiudi la notch")
        case .openAgents:    tr("Apri gli agenti")
        case .nextPage:      tr("Pagina successiva")
        case .previousPage:  tr("Pagina precedente")
        case .playPause:     tr("Riproduci o metti in pausa")
        case .nextTrack:     tr("Brano successivo")
        case .previousTrack: tr("Brano precedente")
        case .openSettings:  tr("Apri le impostazioni")
        }
    }
}

struct HotkeyBinding: Codable, Equatable, Identifiable {
    var action: HotkeyAction
    var keyCode: UInt32?
    /// Modificatori nel formato di Carbon (cmdKey, optionKey…).
    var modifiers: UInt32

    var id: String { action.rawValue }

    static var defaults: [HotkeyBinding] {
        // ⌃⌥N e ⌃⌥A: comode a una mano e senza conflitti con le app comuni.
        let controlOption: UInt32 = 0x1000 | 0x0800
        return HotkeyAction.allCases.map { action in
            switch action {
            case .toggleNotch: HotkeyBinding(action: action, keyCode: 45, modifiers: controlOption)
            case .openAgents:  HotkeyBinding(action: action, keyCode: 0, modifiers: controlOption)
            default:           HotkeyBinding(action: action, keyCode: nil, modifiers: 0)
            }
        }
    }
}

// MARK: - Profili

/// Un'istantanea di aspetto e layout, da richiamare con un click, un comando
/// rapido o un filtro Full Immersion.
struct ProfileConfig: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var symbol: String
    var layout: LayoutConfig
    var appearance: AppearanceConfig
}
