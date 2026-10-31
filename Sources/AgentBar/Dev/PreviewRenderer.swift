import AppKit
import SwiftUI

/// Strumento di sviluppo: `AgentBar --render <cartella>` disegna i pannelli
/// fuori schermo con dati finti, per controllare il layout senza dover
/// riprodurre a mano tutti gli stati.
@MainActor
enum PreviewRenderer {
    static func run(outputDirectory: String) {
        let directory = AppPaths.expand(outputDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let store = SessionStore(preview: mockSessions)
        let presentation = PanelPresentation()
        presentation.visible = true

        render(
            PeekView(store: store, presentation: presentation),
            named: "peek",
            in: directory
        )

        render(
            DeckView(store: store, presentation: presentation, onClose: {}, scrollable: false),
            named: "deck",
            in: directory
        )

        let attentionStore = SessionStore(preview: mockSessions)
        attentionStore.filter = .attention
        render(
            DeckView(store: attentionStore, presentation: presentation, onClose: {}, scrollable: false),
            named: "deck-attention",
            in: directory
        )

        // Card espansa: è l'unico modo di vedere la riga delle azioni, che
        // compare solo al passaggio del mouse.
        render(
            VStack(spacing: 8) {
                SessionCardView(session: mockSessions[0], expanded: true, onToggleExpand: {})
                SessionCardView(session: mockSessions[2], expanded: true, onToggleExpand: {})
            }
            .frame(width: Theme.deckWidth - 24)
            .padding(12),
            named: "card-expanded",
            in: directory
        )

        render(
            SettingsView(store: store, onBack: {}, scrollable: false),
            named: "settings",
            in: directory
        )

        let emptyStore = SessionStore(preview: [])
        render(
            PeekView(store: emptyStore, presentation: presentation),
            named: "peek-empty",
            in: directory
        )
        render(
            DeckView(store: emptyStore, presentation: presentation, onClose: {}, scrollable: false),
            named: "deck-empty",
            in: directory
        )
    }

    private static func render(_ view: some View, named name: String, in directory: URL) {
        for (suffix, appearance) in [("dark", NSAppearance(named: .darkAqua)), ("light", NSAppearance(named: .aqua))] {
            let backdrop = suffix == "dark"
                ? LinearGradient(colors: [Color(hex: 0x1B2733), Color(hex: 0x2E1F3D)], startPoint: .topLeading, endPoint: .bottomTrailing)
                : LinearGradient(colors: [Color(hex: 0xDCE6F2), Color(hex: 0xF3E9F7)], startPoint: .topLeading, endPoint: .bottomTrailing)

            let content = view
                .background(backdrop)
                .environment(\.colorScheme, suffix == "dark" ? .dark : .light)

            let renderer = ImageRenderer(content: content)
            renderer.scale = 2

            var rendered: NSImage?
            if let appearance {
                appearance.performAsCurrentDrawingAppearance { rendered = renderer.nsImage }
            } else {
                rendered = renderer.nsImage
            }

            guard let image = rendered,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:])
            else { continue }

            let url = directory.appendingPathComponent("\(name)-\(suffix).png")
            try? png.write(to: url)
            print("reso \(url.path)")
        }
    }

    // MARK: - Dati finti

    private static var mockSessions: [AgentSession] {
        let now = Date()
        return [
            AgentSession(
                id: "claude-code:1",
                providerID: "claude-code",
                providerName: "Claude Code",
                accentHex: "#D97757",
                title: "Estensione barra di stato per gli agent",
                project: "creatures",
                path: "/Users/francescoromeo/Projects/creatures",
                branch: "main",
                model: "claude-opus-5",
                status: .working,
                activity: "Edit · Prop.swift",
                detail: "Voglio creare una sorta di estensione per claude code, con lo stato delle sessioni nella barra in alto.",
                host: "Desktop",
                startedAt: now.addingTimeInterval(-4200),
                updatedAt: now.addingTimeInterval(-8),
                tokensUsed: 148_320,
                tokenLimit: 200_000,
                pid: 50786,
                nativeID: "eb2864cc-34a3-43cf-9f74-fd406fefafee"
            ),
            AgentSession(
                id: "claude-code:2",
                providerID: "claude-code",
                providerName: "Claude Code",
                accentHex: "#D97757",
                title: "Refactor del parser di configurazione",
                project: "Projects",
                path: "/Users/francescoromeo/Projects",
                branch: "HEAD",
                model: "claude-opus-5",
                status: .attention,
                activity: "Ho finito la migrazione, aggiorno anche i test?",
                detail: "Ho finito la migrazione, vuoi che aggiorni anche i test?",
                host: "Desktop",
                startedAt: now.addingTimeInterval(-9000),
                updatedAt: now.addingTimeInterval(-1080),
                tokensUsed: 88_000,
                tokenLimit: 200_000,
                pid: 82685,
                nativeID: "3d6c9de2-1f63-4647-abf4-7c5b9dc97eab"
            ),
            AgentSession(
                id: "inbox:codex",
                providerID: "inbox",
                providerName: "Codex",
                accentHex: "#8B5CF6",
                title: "Aggiorna il flusso di autenticazione",
                project: "valigia",
                path: "/Users/francescoromeo/Projects/valigia",
                branch: "feat/auth",
                model: "gpt-5",
                status: .blocked,
                activity: "Bash · rm -rf build/",
                detail: nil,
                host: "Terminale",
                startedAt: now.addingTimeInterval(-600),
                updatedAt: now.addingTimeInterval(-42),
                tokensUsed: nil,
                tokenLimit: nil,
                pid: 1234,
                nativeID: "codex-77",
                actions: [SessionAction(label: "Approva", command: "echo ok", symbol: "checkmark.circle")]
            ),
            AgentSession(
                id: "claude-code:3",
                providerID: "claude-code",
                providerName: "Claude Code",
                accentHex: "#D97757",
                title: "Pulse — indicizzazione delle note",
                project: "Pulse",
                path: "/Users/francescoromeo/Projects/Pulse",
                branch: "main",
                model: "claude-sonnet-5",
                status: .idle,
                activity: nil,
                detail: nil,
                host: "VS Code",
                startedAt: now.addingTimeInterval(-26000),
                updatedAt: now.addingTimeInterval(-3400),
                tokensUsed: 31_500,
                tokenLimit: 200_000,
                pid: 95504,
                nativeID: "55d779eb-a544-43a2-8375-4d5e46749321"
            ),
            AgentSession(
                id: "claude-code:4",
                providerID: "claude-code",
                providerName: "Claude Code",
                accentHex: "#D97757",
                title: "Setup della pipeline di build per lampada-a1",
                project: "lampada-a1",
                path: "/Users/francescoromeo/Projects/lampada-a1",
                branch: "main",
                model: "claude-opus-5",
                status: .ended,
                activity: nil,
                detail: nil,
                host: nil,
                startedAt: now.addingTimeInterval(-90000),
                updatedAt: now.addingTimeInterval(-72000),
                tokensUsed: 120_000,
                tokenLimit: 200_000,
                pid: nil,
                nativeID: "f0308503-6ec9-414a-a499-1c2fa60ba296"
            )
        ]
    }
}
