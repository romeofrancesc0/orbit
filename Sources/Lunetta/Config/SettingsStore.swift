import AppKit
import Combine
import Foundation
import SwiftUI

/// Unica fonte di verità della configurazione: la tiene in memoria, la scrive su
/// disco con un piccolo ritardo e la rilegge se qualcuno modifica il file a mano.
@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var config: LunettaConfig

    private var saveWork: DispatchWorkItem?
    private var lastDiskData: Data?
    private var watcher: TreeWatcher?
    private let file: URL
    private let persists: Bool

    init(file: URL = AppPaths.configFile, persists: Bool = true) {
        self.file = file
        self.persists = persists

        if persists {
            LegacyMigration.runIfNeeded()
            let fm = FileManager.default
            try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.createDirectory(at: AppPaths.defaultInbox, withIntermediateDirectories: true)
        }

        if let data = try? Data(contentsOf: file), let decoded = Self.decode(data) {
            config = decoded
            lastDiskData = data
        } else {
            config = LunettaConfig()
        }

        if persists {
            if lastDiskData == nil { writeNow() }
            // FSEvents e non un watcher sulla cartella: deve vedere anche gli editor che
            // riscrivono il file sul posto, senza sostituirlo.
            watcher = TreeWatcher(paths: [file.deletingLastPathComponent().path]) { [weak self] in
                Task { @MainActor in self?.reloadIfChanged() }
            }
        }
    }

    // MARK: - Scrittura

    func update(_ mutate: (inout LunettaConfig) -> Void) {
        var updated = config
        mutate(&updated)
        guard updated != config else { return }
        // Toccare a mano aspetto o layout significa uscire dal profilo attivo.
        let changedLook = updated.layout != config.layout || updated.appearance != config.appearance
        if changedLook, updated.activeProfileID == config.activeProfileID {
            updated.activeProfileID = nil
        }
        config = updated
        scheduleSave()
    }

    /// Collegamento diretto fra un controllo SwiftUI e un valore della configurazione.
    func binding<Value>(_ keyPath: WritableKeyPath<LunettaConfig, Value>) -> Binding<Value> {
        Binding(
            get: { self.config[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    /// Come `binding`, per un campo di un elemento in una lista. L'elemento si cerca per id
    /// a ogni accesso: con un indice fisso, cancellarlo farebbe crashare le viste ancora
    /// in uscita, che possono leggere il valore un'ultima volta.
    func binding<Element: Identifiable, Value>(
        in list: WritableKeyPath<LunettaConfig, [Element]>,
        id: Element.ID,
        _ field: WritableKeyPath<Element, Value>,
        default fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { self.config[keyPath: list].first { $0.id == id }?[keyPath: field] ?? fallback },
            set: { newValue in
                self.update { config in
                    guard let index = config[keyPath: list].firstIndex(where: { $0.id == id }) else { return }
                    config[keyPath: list][index][keyPath: field] = newValue
                }
            }
        )
    }

    private func scheduleSave() {
        guard persists else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.writeNow() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func writeNow() {
        guard persists, let data = Self.encode(config) else { return }
        guard data != lastDiskData else { return }
        lastDiskData = data
        try? data.write(to: file, options: .atomic)
    }

    // MARK: - Lettura

    private func reloadIfChanged() {
        guard let data = try? Data(contentsOf: file), data != lastDiskData else { return }
        lastDiskData = data
        guard let decoded = Self.decode(data), decoded != config else { return }
        config = decoded
    }

    func openConfigFile() {
        writeNow()
        NSWorkspace.shared.open(file)
    }

    func resetToDefaults() {
        update { current in
            let onboarding = current.onboardingDone
            current = LunettaConfig()
            current.onboardingDone = onboarding
        }
    }

    // MARK: - Codifica

    nonisolated static func encode(_ config: LunettaConfig) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(config)
    }

    /// Fonde il file sopra i default, poi decodifica: le chiavi nuove o mancanti
    /// prendono il valore predefinito invece di invalidare tutto il file.
    nonisolated static func decode(_ data: Data) -> LunettaConfig? {
        guard let user = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let baseData = try? JSONEncoder().encode(LunettaConfig()),
              let base = (try? JSONSerialization.jsonObject(with: baseData)) as? [String: Any]
        else { return nil }
        let merged = deepMerge(base, user)
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(LunettaConfig.self, from: mergedData)
    }

    nonisolated static func deepMerge(_ base: [String: Any], _ overlay: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in overlay {
            if let baseChild = result[key] as? [String: Any], let overlayChild = value as? [String: Any] {
                result[key] = deepMerge(baseChild, overlayChild)
            } else {
                result[key] = value
            }
        }
        return result
    }
}

// MARK: - Migrazione da AgentBar

/// Porta in Lunetta ciò che l'utente aveva già impostato in AgentBar. Non tocca i
/// file di partenza e gira una volta sola: quando la nuova configurazione ancora
/// non esiste.
enum LegacyMigration {
    private struct LegacyConfig: Decodable {
        var showRecent: Bool?
        var recentWindowHours: Double?
        var idleAfterMinutes: Double?
        var defaultTokenLimit: Int?
        var providers: [ProviderConfig]?
    }

    static func runIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: AppPaths.configFile.path),
              let data = try? Data(contentsOf: AppPaths.legacyConfigDirectory.appendingPathComponent("config.json")),
              let legacy = try? JSONDecoder().decode(LegacyConfig.self, from: data)
        else { return }

        var config = LunettaConfig()
        if let value = legacy.showRecent { config.agents.showRecent = value }
        if let value = legacy.recentWindowHours { config.agents.recentWindowHours = value }
        if let value = legacy.idleAfterMinutes { config.agents.idleAfterMinutes = value }
        if let value = legacy.defaultTokenLimit { config.agents.defaultTokenLimit = value }
        if let providers = legacy.providers {
            config.agents.providers = merged(legacy: providers)
        }

        try? fm.createDirectory(at: AppPaths.configDirectory, withIntermediateDirectories: true)
        if let encoded = SettingsStore.encode(config) { try? encoded.write(to: AppPaths.configFile, options: .atomic) }

        let dismissed = AppPaths.legacyConfigDirectory.appendingPathComponent("dismissed.json")
        let target = AppPaths.configDirectory.appendingPathComponent("dismissed.json")
        if fm.fileExists(atPath: dismissed.path), !fm.fileExists(atPath: target.path) {
            try? fm.copyItem(at: dismissed, to: target)
        }
    }

    /// Conserva i provider dell'utente e aggiunge quelli nuovi, senza cambiarne l'ordine.
    static func merged(legacy: [ProviderConfig]) -> [ProviderConfig] {
        var result = legacy.map { provider -> ProviderConfig in
            var copy = provider
            if copy.path == "~/.agentbar/inbox" { copy.path = "~/.lunetta/inbox" }
            return copy
        }
        for provider in AgentsConfig.defaultProviders where !result.contains(where: { $0.type == provider.type }) {
            result.append(provider)
        }
        return result
    }
}
