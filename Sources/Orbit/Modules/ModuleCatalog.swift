import Foundation

/// Un widget che si può mettere in una pagina della notch aperta.
struct WidgetDescriptor: Identifiable, Equatable {
    var id: String { kind }
    var kind: String
    var name: String
    var symbol: String
    var summary: String
    var defaultWeight: Double = 1
}

/// Un elemento che si può mettere accanto alla notch chiusa o nella testata.
struct CompactDescriptor: Identifiable, Equatable {
    var id: String
    var name: String
    var symbol: String
    var summary: String
    var group: String
}

/// L'elenco di tutto ciò che l'editor del layout può offrire.
enum ModuleCatalog {
    static var widgets: [WidgetDescriptor] { [
        WidgetDescriptor(kind: "agents", name: tr("Agenti"), symbol: "sparkles", summary: tr("Le sessioni dei tuoi coding agent, con stato e azioni"), defaultWeight: 1.3),
        WidgetDescriptor(kind: "media", name: tr("Musica"), symbol: "music.note", summary: tr("Copertina, comandi e avanzamento da qualunque app"), defaultWeight: 1.25),
        WidgetDescriptor(kind: "calendar", name: tr("Calendario"), symbol: "calendar", summary: tr("La settimana, gli eventi e i promemoria"), defaultWeight: 0.9),
        WidgetDescriptor(kind: "shelf", name: tr("Scaffale"), symbol: "tray.full.fill", summary: tr("File, link e testi a portata di mano, con AirDrop"), defaultWeight: 1.4),
        WidgetDescriptor(kind: "mirror", name: tr("Specchio"), symbol: "person.crop.square.fill", summary: tr("La fotocamera, per controllarti prima di una call"), defaultWeight: 0.6),
        WidgetDescriptor(kind: "battery", name: tr("Batteria"), symbol: "battery.100percent", summary: tr("Carica, autonomia e risparmio energetico"), defaultWeight: 0.6),
        WidgetDescriptor(kind: "system", name: tr("Sistema"), symbol: "cpu", summary: tr("Processore, memoria, disco e rete"), defaultWeight: 0.8),
        WidgetDescriptor(kind: "clipboard", name: tr("Appunti"), symbol: "doc.on.clipboard", summary: tr("Le ultime cose copiate, solo in memoria"), defaultWeight: 1),
        WidgetDescriptor(kind: "timer", name: tr("Timer"), symbol: "timer", summary: tr("Timer e cronometro, visibili anche a notch chiusa"), defaultWeight: 0.8),
        WidgetDescriptor(kind: "notes", name: tr("Note"), symbol: "note.text", summary: tr("Un foglio di appunti sempre pronto"), defaultWeight: 1),
        WidgetDescriptor(kind: "launcher", name: tr("Collegamenti"), symbol: "square.grid.2x2.fill", summary: tr("App, comandi rapidi, link e script a un click"), defaultWeight: 0.9),
        WidgetDescriptor(kind: "clock", name: tr("Orologio"), symbol: "clock.fill", summary: tr("Ora e data, grandi e leggibili"), defaultWeight: 0.6)
    ] }

    static var compacts: [CompactDescriptor] { [
        CompactDescriptor(id: "agents.status", name: tr("Stato agenti"), symbol: "sparkles", summary: tr("Un'icona che cambia se lavorano o ti aspettano"), group: tr("Agenti")),
        CompactDescriptor(id: "agents.dots", name: tr("Pallini sessioni"), symbol: "circle.grid.2x1.fill", summary: tr("Un pallino colorato per ogni sessione attiva"), group: tr("Agenti")),
        CompactDescriptor(id: "agents.count", name: tr("Numero sessioni"), symbol: "number", summary: tr("Quante sessioni sono attive"), group: tr("Agenti")),
        CompactDescriptor(id: "agents.activity", name: tr("Attività corrente"), symbol: "text.alignleft", summary: tr("Cosa sta facendo la sessione più urgente"), group: tr("Agenti")),
        CompactDescriptor(id: "media.artwork", name: tr("Copertina"), symbol: "photo.fill", summary: tr("La copertina del brano in riproduzione"), group: tr("Musica")),
        CompactDescriptor(id: "media.visualizer", name: tr("Visualizzatore"), symbol: "waveform", summary: tr("Le barre a tempo di musica"), group: tr("Musica")),
        CompactDescriptor(id: "media.title", name: tr("Titolo"), symbol: "music.note", summary: tr("Il titolo che scorre"), group: tr("Musica")),
        CompactDescriptor(id: "calendar.next", name: tr("Prossimo evento"), symbol: "calendar", summary: tr("Compare nell'ora prima dell'evento"), group: tr("Calendario")),
        CompactDescriptor(id: "battery.level", name: tr("Batteria"), symbol: "battery.75percent", summary: tr("Icona e percentuale"), group: tr("Sistema")),
        CompactDescriptor(id: "system.cpu", name: tr("Processore"), symbol: "cpu", summary: tr("Carico del processore in tempo reale"), group: tr("Sistema")),
        CompactDescriptor(id: "clock.time", name: tr("Ora"), symbol: "clock", summary: tr("L'ora corrente"), group: tr("Sistema")),
        CompactDescriptor(id: "timer.remaining", name: tr("Timer"), symbol: "timer", summary: tr("Il tempo che manca, mentre è attivo"), group: tr("Strumenti")),
        CompactDescriptor(id: "shelf.count", name: tr("Scaffale"), symbol: "tray.full.fill", summary: tr("Quanti oggetti aspettano sullo scaffale"), group: tr("Strumenti"))
    ] }

    // MARK: - Widget personalizzati

    private static let customPrefix = "custom:"

    static func customKind(_ id: String) -> String { customPrefix + id }

    static func customID(fromKind kind: String) -> String? {
        kind.hasPrefix(customPrefix) ? String(kind.dropFirst(customPrefix.count)) : nil
    }

    static func allWidgets(custom: [CustomWidgetConfig]) -> [WidgetDescriptor] {
        widgets + custom.map {
            WidgetDescriptor(kind: customKind($0.id), name: $0.name, symbol: $0.symbol, summary: tr("Widget personalizzato"))
        }
    }

    static func allCompacts(custom: [CustomWidgetConfig]) -> [CompactDescriptor] {
        compacts + custom.map {
            CompactDescriptor(id: customKind($0.id), name: $0.name, symbol: $0.symbol, summary: tr("Il valore del tuo script"), group: tr("Personalizzati"))
        }
    }

    static func widget(_ kind: String, custom: [CustomWidgetConfig]) -> WidgetDescriptor? {
        allWidgets(custom: custom).first { $0.kind == kind }
    }

    static func compact(_ id: String, custom: [CustomWidgetConfig]) -> CompactDescriptor? {
        allCompacts(custom: custom).first { $0.id == id }
    }
}

// MARK: - Temi

/// Un tema è un punto di partenza: tocca colori e superficie, lascia stare le misure.
struct ThemePreset: Identifiable {
    var id: String
    var name: String
    var surface: SurfaceStyle
    var solidHex = "#000000"
    var gradientHex = ["#050507", "#14141B"]
    var glassDim: Double = 0.35
    var accentMode: AccentMode
    var accentHex: String
    var border: Double = 0.5
    var glow: Double = 0.55
    var cardStyle: CardStyle = .filled

    func apply(to appearance: inout AppearanceConfig) {
        appearance.themeID = id
        appearance.surface = surface
        appearance.solidHex = solidHex
        appearance.gradientHex = gradientHex
        appearance.glassDim = glassDim
        appearance.accentMode = accentMode
        appearance.accentHex = accentHex
        appearance.border = border
        appearance.glow = glow
        appearance.cardStyle = cardStyle
    }

    static var all: [ThemePreset] { [
        ThemePreset(id: "notte", name: tr("Notte"), surface: .solid, accentMode: .artwork, accentHex: "#FFB37C"),
        ThemePreset(id: "vetro", name: tr("Vetro"), surface: .glass, glassDim: 0.3, accentMode: .system, accentHex: "#FFFFFF", border: 0.7, glow: 0.2),
        ThemePreset(id: "copertina", name: tr("Copertina"), surface: .artwork, accentMode: .artwork, accentHex: "#FFFFFF", glow: 0.8),
        ThemePreset(id: "brace", name: tr("Brace"), surface: .gradient, gradientHex: ["#0B0605", "#2B1209"], accentMode: .custom, accentHex: "#FF8A5C", glow: 0.7),
        ThemePreset(id: "aurora", name: tr("Aurora"), surface: .gradient, gradientHex: ["#03090B", "#0B2A2B", "#1D1A3A"], accentMode: .custom, accentHex: "#6CF0C2", glow: 0.75),
        ThemePreset(id: "oceano", name: tr("Oceano"), surface: .gradient, gradientHex: ["#02060E", "#0A2342"], accentMode: .custom, accentHex: "#5AC8FA", glow: 0.65),
        ThemePreset(id: "lavanda", name: tr("Lavanda"), surface: .gradient, gradientHex: ["#07050D", "#221A3F"], accentMode: .custom, accentHex: "#B9A5FF", glow: 0.65),
        ThemePreset(id: "grafite", name: tr("Grafite"), surface: .solid, solidHex: "#1C1C1F", accentMode: .system, accentHex: "#FFFFFF", border: 0.25, glow: 0, cardStyle: .outlined),
        ThemePreset(id: "inchiostro", name: tr("Inchiostro"), surface: .solid, accentMode: .custom, accentHex: "#FFFFFF", border: 0, glow: 0, cardStyle: .plain)
    ] }

    static func preset(_ id: String) -> ThemePreset? { all.first { $0.id == id } }
}

// MARK: - Profili pronti

extension ProfileConfig {
    /// Profili di partenza: si possono applicare, duplicare e modificare.
    static var builtIn: [ProfileConfig] {
        func themed(_ id: String) -> AppearanceConfig {
            var appearance = AppearanceConfig()
            ThemePreset.preset(id)?.apply(to: &appearance)
            return appearance
        }

        var coding = LayoutConfig()
        coding.closedLeading = ["agents.status", "agents.activity"]
        coding.closedTrailing = ["agents.dots", "media.visualizer"]
        coding.startMode = .first
        coding.pages = [
            PageConfig(id: "agents", title: "Agenti", symbol: "sparkles", widgets: [WidgetPlacement(kind: "agents")], height: 300),
            PageConfig(id: "tools", title: "Strumenti", symbol: "wrench.and.screwdriver.fill", widgets: [
                WidgetPlacement(kind: "system", weight: 0.9),
                WidgetPlacement(kind: "clipboard", weight: 1.2),
                WidgetPlacement(kind: "notes", weight: 1.2)
            ]),
            PageConfig(id: "shelf", title: "Scaffale", symbol: "tray.full.fill", widgets: [WidgetPlacement(kind: "shelf")])
        ]

        var music = LayoutConfig()
        music.closedLeading = ["media.artwork", "media.title"]
        music.closedTrailing = ["media.visualizer"]
        music.symmetricWings = false
        music.startMode = .first
        music.pages = [
            PageConfig(id: "music", title: "Musica", symbol: "music.note", widgets: [
                WidgetPlacement(kind: "media", weight: 1.7),
                WidgetPlacement(kind: "calendar", weight: 0.9)
            ]),
            PageConfig(id: "shelf", title: "Scaffale", symbol: "tray.full.fill", widgets: [WidgetPlacement(kind: "shelf")])
        ]

        var minimal = LayoutConfig()
        minimal.closedLeading = ["media.artwork"]
        minimal.closedTrailing = ["media.visualizer"]
        minimal.headerTrailing = []
        minimal.startMode = .first
        minimal.pages = [
            PageConfig(id: "home", title: "Home", symbol: "house.fill", widgets: [
                WidgetPlacement(kind: "media", weight: 1.3),
                WidgetPlacement(kind: "clock", weight: 0.7)
            ])
        ]

        var agenda = LayoutConfig()
        agenda.closedLeading = ["calendar.next"]
        agenda.closedTrailing = ["timer.remaining", "clock.time"]
        agenda.startMode = .first
        agenda.pages = [
            PageConfig(id: "day", title: "Giornata", symbol: "calendar", widgets: [
                WidgetPlacement(kind: "calendar", weight: 1.3),
                WidgetPlacement(kind: "timer", weight: 0.8),
                WidgetPlacement(kind: "notes", weight: 1.1)
            ]),
            PageConfig(id: "shelf", title: "Scaffale", symbol: "tray.full.fill", widgets: [WidgetPlacement(kind: "shelf")])
        ]

        return [
            ProfileConfig(id: "default", name: tr("Predefinito"), symbol: "moon.stars.fill", layout: LayoutConfig(), appearance: AppearanceConfig()),
            ProfileConfig(id: "coding", name: tr("Coding"), symbol: "chevron.left.forwardslash.chevron.right", layout: coding, appearance: themed("brace")),
            ProfileConfig(id: "music", name: tr("Musica"), symbol: "music.note", layout: music, appearance: themed("copertina")),
            ProfileConfig(id: "agenda", name: tr("Agenda"), symbol: "calendar", layout: agenda, appearance: themed("oceano")),
            ProfileConfig(id: "minimal", name: tr("Essenziale"), symbol: "circle", layout: minimal, appearance: themed("inchiostro"))
        ]
    }
}
