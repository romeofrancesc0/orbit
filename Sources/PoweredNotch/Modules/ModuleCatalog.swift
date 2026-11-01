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
    static let widgets: [WidgetDescriptor] = [
        WidgetDescriptor(kind: "agents", name: "Agenti", symbol: "sparkles", summary: "Le sessioni dei tuoi coding agent, con stato e azioni", defaultWeight: 1.3),
        WidgetDescriptor(kind: "media", name: "Musica", symbol: "music.note", summary: "Copertina, comandi e avanzamento da qualunque app", defaultWeight: 1.25),
        WidgetDescriptor(kind: "calendar", name: "Calendario", symbol: "calendar", summary: "La settimana, gli eventi e i promemoria", defaultWeight: 0.9),
        WidgetDescriptor(kind: "shelf", name: "Scaffale", symbol: "tray.full.fill", summary: "File, link e testi a portata di mano, con AirDrop", defaultWeight: 1.4),
        WidgetDescriptor(kind: "mirror", name: "Specchio", symbol: "person.crop.square.fill", summary: "La fotocamera, per controllarti prima di una call", defaultWeight: 0.6),
        WidgetDescriptor(kind: "battery", name: "Batteria", symbol: "battery.100percent", summary: "Carica, autonomia e risparmio energetico", defaultWeight: 0.6),
        WidgetDescriptor(kind: "system", name: "Sistema", symbol: "cpu", summary: "Processore, memoria, disco e rete", defaultWeight: 0.8),
        WidgetDescriptor(kind: "clipboard", name: "Appunti", symbol: "doc.on.clipboard", summary: "Le ultime cose copiate, solo in memoria", defaultWeight: 1),
        WidgetDescriptor(kind: "timer", name: "Timer", symbol: "timer", summary: "Timer e cronometro, visibili anche a notch chiusa", defaultWeight: 0.8),
        WidgetDescriptor(kind: "notes", name: "Note", symbol: "note.text", summary: "Un foglio di appunti sempre pronto", defaultWeight: 1),
        WidgetDescriptor(kind: "launcher", name: "Collegamenti", symbol: "square.grid.2x2.fill", summary: "App, comandi rapidi, link e script a un click", defaultWeight: 0.9),
        WidgetDescriptor(kind: "clock", name: "Orologio", symbol: "clock.fill", summary: "Ora e data, grandi e leggibili", defaultWeight: 0.6)
    ]

    static let compacts: [CompactDescriptor] = [
        CompactDescriptor(id: "agents.status", name: "Stato agenti", symbol: "sparkles", summary: "Un'icona che cambia se lavorano o ti aspettano", group: "Agenti"),
        CompactDescriptor(id: "agents.dots", name: "Pallini sessioni", symbol: "circle.grid.2x1.fill", summary: "Un pallino colorato per ogni sessione attiva", group: "Agenti"),
        CompactDescriptor(id: "agents.count", name: "Numero sessioni", symbol: "number", summary: "Quante sessioni sono attive", group: "Agenti"),
        CompactDescriptor(id: "agents.activity", name: "Attività corrente", symbol: "text.alignleft", summary: "Cosa sta facendo la sessione più urgente", group: "Agenti"),
        CompactDescriptor(id: "media.artwork", name: "Copertina", symbol: "photo.fill", summary: "La copertina del brano in riproduzione", group: "Musica"),
        CompactDescriptor(id: "media.visualizer", name: "Visualizzatore", symbol: "waveform", summary: "Le barre a tempo di musica", group: "Musica"),
        CompactDescriptor(id: "media.title", name: "Titolo", symbol: "music.note", summary: "Il titolo che scorre", group: "Musica"),
        CompactDescriptor(id: "calendar.next", name: "Prossimo evento", symbol: "calendar", summary: "Compare nell'ora prima dell'evento", group: "Calendario"),
        CompactDescriptor(id: "battery.level", name: "Batteria", symbol: "battery.75percent", summary: "Icona e percentuale", group: "Sistema"),
        CompactDescriptor(id: "system.cpu", name: "Processore", symbol: "cpu", summary: "Carico del processore in tempo reale", group: "Sistema"),
        CompactDescriptor(id: "clock.time", name: "Ora", symbol: "clock", summary: "L'ora corrente", group: "Sistema"),
        CompactDescriptor(id: "timer.remaining", name: "Timer", symbol: "timer", summary: "Il tempo che manca, mentre è attivo", group: "Strumenti"),
        CompactDescriptor(id: "shelf.count", name: "Scaffale", symbol: "tray.full.fill", summary: "Quanti oggetti aspettano sullo scaffale", group: "Strumenti")
    ]

    // MARK: - Widget personalizzati

    private static let customPrefix = "custom:"

    static func customKind(_ id: String) -> String { customPrefix + id }

    static func customID(fromKind kind: String) -> String? {
        kind.hasPrefix(customPrefix) ? String(kind.dropFirst(customPrefix.count)) : nil
    }

    static func allWidgets(custom: [CustomWidgetConfig]) -> [WidgetDescriptor] {
        widgets + custom.map {
            WidgetDescriptor(kind: customKind($0.id), name: $0.name, symbol: $0.symbol, summary: "Widget personalizzato")
        }
    }

    static func allCompacts(custom: [CustomWidgetConfig]) -> [CompactDescriptor] {
        compacts + custom.map {
            CompactDescriptor(id: customKind($0.id), name: $0.name, symbol: $0.symbol, summary: "Il valore del tuo script", group: "Personalizzati")
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

    static let all: [ThemePreset] = [
        ThemePreset(id: "notte", name: "Notte", surface: .solid, accentMode: .artwork, accentHex: "#FFB37C"),
        ThemePreset(id: "vetro", name: "Vetro", surface: .glass, glassDim: 0.3, accentMode: .system, accentHex: "#FFFFFF", border: 0.7, glow: 0.2),
        ThemePreset(id: "copertina", name: "Copertina", surface: .artwork, accentMode: .artwork, accentHex: "#FFFFFF", glow: 0.8),
        ThemePreset(id: "brace", name: "Brace", surface: .gradient, gradientHex: ["#0B0605", "#2B1209"], accentMode: .custom, accentHex: "#FF8A5C", glow: 0.7),
        ThemePreset(id: "aurora", name: "Aurora", surface: .gradient, gradientHex: ["#03090B", "#0B2A2B", "#1D1A3A"], accentMode: .custom, accentHex: "#6CF0C2", glow: 0.75),
        ThemePreset(id: "oceano", name: "Oceano", surface: .gradient, gradientHex: ["#02060E", "#0A2342"], accentMode: .custom, accentHex: "#5AC8FA", glow: 0.65),
        ThemePreset(id: "lavanda", name: "Lavanda", surface: .gradient, gradientHex: ["#07050D", "#221A3F"], accentMode: .custom, accentHex: "#B9A5FF", glow: 0.65),
        ThemePreset(id: "grafite", name: "Grafite", surface: .solid, solidHex: "#1C1C1F", accentMode: .system, accentHex: "#FFFFFF", border: 0.25, glow: 0, cardStyle: .outlined),
        ThemePreset(id: "inchiostro", name: "Inchiostro", surface: .solid, accentMode: .custom, accentHex: "#FFFFFF", border: 0, glow: 0, cardStyle: .plain)
    ]

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
            ProfileConfig(id: "default", name: "Predefinito", symbol: "moon.stars.fill", layout: LayoutConfig(), appearance: AppearanceConfig()),
            ProfileConfig(id: "coding", name: "Coding", symbol: "chevron.left.forwardslash.chevron.right", layout: coding, appearance: themed("brace")),
            ProfileConfig(id: "music", name: "Musica", symbol: "music.note", layout: music, appearance: themed("copertina")),
            ProfileConfig(id: "agenda", name: "Agenda", symbol: "calendar", layout: agenda, appearance: themed("oceano")),
            ProfileConfig(id: "minimal", name: "Essenziale", symbol: "circle", layout: minimal, appearance: themed("inchiostro"))
        ]
    }
}
