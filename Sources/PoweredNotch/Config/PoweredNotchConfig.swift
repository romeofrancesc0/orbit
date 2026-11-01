import Foundation
import SwiftUI

/// Tutto ciò che si può personalizzare. Vive in `~/.config/powered-notch/config.json`,
/// si modifica dalle impostazioni o a mano, e viene riletto a caldo.
///
/// Ogni valore ha un default: `SettingsStore` fonde il file dell'utente sopra i
/// default prima di decodificarlo, così le chiavi mancanti non sono mai un errore.
struct PoweredNotchConfig: Codable, Equatable {
    var schemaVersion = 1
    var onboardingDone = false
    var agents = AgentsConfig()
    var layout = LayoutConfig()
    var appearance = AppearanceConfig()
    var behavior = BehaviorConfig()
    var peeks = PeekConfig()
    var media = MediaConfig()
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

    /// Una sezione illeggibile ricade sul suo default senza trascinare giù le altre.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decode(T.self, forKey: key)) ?? fallback
        }
        let d = PoweredNotchConfig()
        schemaVersion = read(.schemaVersion, d.schemaVersion)
        onboardingDone = read(.onboardingDone, d.onboardingDone)
        agents = read(.agents, d.agents)
        layout = read(.layout, d.layout)
        appearance = read(.appearance, d.appearance)
        behavior = read(.behavior, d.behavior)
        peeks = read(.peeks, d.peeks)
        media = read(.media, d.media)
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
        case .first:    "La prima"
        case .last:     "L'ultima usata"
        case .smart:    "Intelligente"
        case .specific: "Una a scelta"
        }
    }
    var help: String {
        switch self {
        case .first:    "Si apre sempre sulla prima pagina."
        case .last:     "Riprende dalla pagina che avevi lasciato."
        case .smart:    "Va sulla pagina degli agenti se una sessione ti aspetta, altrimenti sulla prima."
        case .specific: "Si apre sempre sulla pagina che scegli."
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
        case .solid:    "Tinta unita"
        case .gradient: "Sfumatura"
        case .glass:    "Liquid Glass"
        case .artwork:  "Dalla copertina"
        }
    }
}

enum AccentMode: String, Codable, CaseIterable, Identifiable {
    case custom, system, artwork
    var id: String { rawValue }
    var label: String {
        switch self {
        case .custom:  "Personalizzato"
        case .system:  "Di sistema"
        case .artwork: "Dalla copertina"
        }
    }
}

enum CardStyle: String, Codable, CaseIterable, Identifiable {
    case filled, outlined, plain
    var id: String { rawValue }
    var label: String {
        switch self {
        case .filled:   "Piene"
        case .outlined: "Bordo"
        case .plain:    "Nessuna"
        }
    }
}

enum FontChoice: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, mono
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system:  "San Francisco"
        case .rounded: "Arrotondato"
        case .serif:   "New York"
        case .mono:    "Monospaziato"
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
        case .icons:          "Icone"
        case .iconsAndTitles: "Icone e nomi"
        case .titles:         "Nomi"
        }
    }
}

enum MotionStyle: String, Codable, CaseIterable, Identifiable {
    case fluid, snappy, bouncy, gentle, instant
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fluid:   "Fluido"
        case .snappy:  "Scattante"
        case .bouncy:  "Elastico"
        case .gentle:  "Morbido"
        case .instant: "Nessuna animazione"
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
        case .bars:     "Barre"
        case .capsules: "Capsule"
        case .dots:     "Puntini"
        case .off:      "Nascosto"
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
        case .auto: "Schermo con la notch"
        case .main: "Schermo principale"
        case .all:  "Tutti gli schermi"
        }
    }
}

enum FullscreenPolicy: String, Codable, CaseIterable, Identifiable {
    case never, mediaOnly, always
    var id: String { rawValue }
    var label: String {
        switch self {
        case .never:     "Mai"
        case .mediaOnly: "Solo guardando un video"
        case .always:    "Sempre"
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
    var agentAttention = true
    var agentError = true
    var agentEnded = false
    var agentSound = ""
    var trackChange = true
    var charger = true
    var lowBattery = true
    var bluetooth = false
    var upcomingEvent = true
    var upcomingMinutes: Double = 5
    var timerDone = true
}

struct MediaConfig: Codable, Equatable {
    var showShuffleRepeat = false
    var tintWithArtwork = true
    /// Per quanti secondi la copertina resta nelle ali dopo la pausa.
    var pausedLingerSeconds: Double = 12
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
        case .inline: "Ai lati della notch"
        case .below:  "Sotto la notch"
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
        case .app:      "App"
        case .shortcut: "Comando rapido"
        case .url:      "Link"
        case .command:  "Comando di shell"
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
        case .toggleNotch:   "Apri o chiudi la notch"
        case .openAgents:    "Apri gli agenti"
        case .nextPage:      "Pagina successiva"
        case .previousPage:  "Pagina precedente"
        case .playPause:     "Riproduci o metti in pausa"
        case .nextTrack:     "Brano successivo"
        case .previousTrack: "Brano precedente"
        case .openSettings:  "Apri le impostazioni"
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
