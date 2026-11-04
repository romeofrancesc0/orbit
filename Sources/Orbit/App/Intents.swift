import AppIntents
import SwiftUI

// Le azioni che Orbit offre a Comandi rapidi, Spotlight e Siri.

/// Una pagina della notch, scelta dall'utente nell'editor del comando rapido.
struct NotchPageEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Pagina della notch")
    static var defaultQuery = NotchPageQuery()

    var id: String
    var title: String
    var symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", image: .init(systemName: symbol))
    }
}

struct NotchPageQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [NotchPageEntity] {
        allPages().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [NotchPageEntity] {
        allPages()
    }

    @MainActor
    private func allPages() -> [NotchPageEntity] {
        AppServices.shared.settings.config.layout.pages.map {
            NotchPageEntity(id: $0.id, title: $0.title, symbol: $0.symbol)
        }
    }
}

/// Un profilo, pronto o salvato dall'utente.
struct NotchProfileEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Profilo di Orbit")
    static var defaultQuery = NotchProfileQuery()

    var id: String
    var name: String
    var symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }
}

struct NotchProfileQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [NotchProfileEntity] {
        allProfiles().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [NotchProfileEntity] {
        allProfiles()
    }

    @MainActor
    private func allProfiles() -> [NotchProfileEntity] {
        AppServices.shared.allProfiles.map {
            NotchProfileEntity(id: $0.id, name: $0.name, symbol: $0.symbol)
        }
    }
}

struct ToggleNotchIntent: AppIntent {
    static var title: LocalizedStringResource = "Apri o chiudi la notch"
    static var description = IntentDescription("Apre la notch se è chiusa e la chiude se è aperta.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AppServices.shared.notch.toggle()
        return .result()
    }
}

struct OpenNotchPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Apri una pagina della notch"
    static var description = IntentDescription("Apre la notch sulla pagina scelta.")
    static var openAppWhenRun = false

    @Parameter(title: "Pagina")
    var page: NotchPageEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Apri \(\.$page) nella notch")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppServices.shared.notch.open(page: page.id)
        return .result()
    }
}

struct ShowNotchMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Mostra un avviso nella notch"
    static var description = IntentDescription("Fa scendere un messaggio dalla notch per qualche secondo.")
    static var openAppWhenRun = false

    @Parameter(title: "Titolo")
    var title: String

    @Parameter(title: "Testo", default: "")
    var subtitle: String

    @Parameter(title: "Secondi", default: 4)
    var seconds: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Mostra \(\.$title) nella notch") {
            \.$subtitle
            \.$seconds
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppServices.shared.notch.show(NotchPeek(
            title: title,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            icon: .symbol("bell.fill"),
            tint: nil,
            duration: seconds,
            group: "intent",
            isForced: true
        ))
        return .result()
    }
}

struct SetQuietIntent: AppIntent {
    static var title: LocalizedStringResource = "Silenzia gli avvisi della notch"
    static var description = IntentDescription("Silenzia o riattiva gli avvisi. Con un'automazione dei Comandi rapidi lo puoi legare a un Focus di macOS.")
    static var openAppWhenRun = false

    @Parameter(title: "Silenzia", default: true)
    var enabled: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$enabled) gli avvisi della notch")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppServices.shared.setQuiet(enabled)
        return .result()
    }
}

struct ApplyProfileIntent: AppIntent {
    static var title: LocalizedStringResource = "Cambia profilo di Orbit"
    static var description = IntentDescription("Applica aspetto e layout di un profilo.")
    static var openAppWhenRun = false

    @Parameter(title: "Profilo")
    var profile: NotchProfileEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Passa al profilo \(\.$profile)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = AppServices.shared.applyProfile(id: profile.id)
        return .result()
    }
}

struct ActiveAgentsIntent: AppIntent {
    static var title: LocalizedStringResource = "Conta le sessioni attive"
    static var description = IntentDescription("Restituisce quante sessioni dei coding agent stanno lavorando o ti aspettano.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let sessions = AppServices.shared.sessions
        let count = sessions.activeSessions.count
        return .result(value: count, dialog: IntentDialog(stringLiteral: sessions.summaryLine))
    }
}

struct StartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Avvia un timer nella notch"
    static var description = IntentDescription("Avvia un timer visibile anche a notch chiusa.")
    static var openAppWhenRun = false

    @Parameter(title: "Minuti", default: 25)
    var minutes: Double

    @Parameter(title: "Etichetta", default: "")
    var label: String

    static var parameterSummary: some ParameterSummary {
        Summary("Avvia un timer di \(\.$minutes) minuti") {
            \.$label
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppServices.shared.timer.start(minutes: minutes, label: label)
        return .result()
    }
}

/// Filtro Full Immersion: ogni modalità può avere il suo profilo. Al lavoro gli
/// agenti, in Non disturbare una notch silenziosa, senza toccare nulla a mano.
struct OrbitFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Profilo di Orbit"
    static var description = IntentDescription("Cambia il profilo di Orbit quando attivi questa modalità Full Immersion.")

    @Parameter(title: "Profilo")
    var profile: NotchProfileEntity?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Orbit", subtitle: profile.map { "\($0.name)" } ?? "Nessun cambiamento")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let profile {
            _ = AppServices.shared.applyProfile(id: profile.id)
        }
        return .result()
    }
}

struct OrbitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleNotchIntent(),
            phrases: ["Apri la notch con \(.applicationName)", "Chiudi la notch con \(.applicationName)"],
            shortTitle: "Apri o chiudi",
            systemImageName: "rectangle.topthird.inset.filled"
        )
        AppShortcut(
            intent: ActiveAgentsIntent(),
            phrases: ["Quante sessioni attive in \(.applicationName)", "Stato degli agenti in \(.applicationName)"],
            shortTitle: "Sessioni attive",
            systemImageName: "sparkles"
        )
    }
}
