import SwiftUI

/// Pagina impostazioni interna al pannello: stessa grafica del resto,
/// niente finestra di sistema e niente JSON da modificare a mano.
struct SettingsView: View {
    @ObservedObject var store: SessionStore
    var onBack: () -> Void
    var scrollable: Bool = true

    @State private var contentHeight: CGFloat = 0
    @State private var loginEnabled = LoginItem.isEnabled

    private var config: AppConfig { store.config }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.hairlineSoft)
            if scrollable {
                ScrollView(.vertical, showsIndicators: false) { sections }
                    .frame(height: min(max(contentHeight, 120), Theme.deckMaxHeight))
            } else {
                sections
            }
        }
    }

    // MARK: - Testata

    private var header: some View {
        HStack(spacing: 9) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.rowFill)
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text("Impostazioni")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("si applicano subito")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 11)
    }

    // MARK: - Sezioni

    private var sections: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("Aggiornamento") {
                stepperRow(
                    "Controlla ogni",
                    value: Int(config.refreshSeconds), range: 1...30, unit: "s"
                ) { new in store.updateConfig { $0.refreshSeconds = Double(new) } }

                stepperRow(
                    "Con un pannello aperto",
                    value: Int(config.activeRefreshSeconds), range: 1...10, unit: "s"
                ) { new in store.updateConfig { $0.activeRefreshSeconds = Double(new) } }
            }

            section("Sessioni") {
                toggleRow(
                    "Mostra le sessioni chiuse",
                    detail: "le ultime \(Int(config.recentWindowHours))h, per riprenderle",
                    isOn: config.showRecent
                ) { new in store.updateConfig { $0.showRecent = new } }

                stepperRow(
                    "Finestra delle recenti",
                    value: Int(config.recentWindowHours), range: 1...72, unit: "h"
                ) { new in store.updateConfig { $0.recentWindowHours = Double(new) } }

                stepperRow(
                    "In pausa dopo",
                    value: Int(config.idleAfterMinutes), range: 1...120, unit: "min"
                ) { new in store.updateConfig { $0.idleAfterMinutes = Double(new) } }

                stepperRow(
                    "Righe nell'anteprima",
                    value: config.maxPeekRows, range: 1...8, unit: ""
                ) { new in store.updateConfig { $0.maxPeekRows = new } }
            }

            section("Aspetto") {
                toggleRow(
                    "Vetro Liquid Glass",
                    detail: "su macOS 26; altrimenti materiale classico",
                    isOn: config.useLiquidGlass
                ) { new in store.updateConfig { $0.useLiquidGlass = new } }

                toggleRow(
                    "Numero nella barra",
                    detail: "accanto all'icona",
                    isOn: config.showCountInMenuBar
                ) { new in store.updateConfig { $0.showCountInMenuBar = new } }

                if LoginItem.isAvailable {
                    toggleRow(
                        "Avvia al login",
                        detail: "AgentBar riparte a ogni accesso",
                        isOn: loginEnabled
                    ) { _ in
                        if LoginItem.toggle() { loginEnabled = LoginItem.isEnabled }
                    }
                }
            }

            if store.hiddenCount > 0 {
                section("Elenco") {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(store.hiddenCount) \(store.hiddenCount == 1 ? "sessione nascosta" : "sessioni nascoste")")
                                .font(.system(size: 12, weight: .medium))
                            Text("tornano da sole se le riprendi")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 8)
                        GhostButton(symbol: "arrow.uturn.backward", label: "Ripristina", tint: nil) {
                            store.restoreHidden()
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.rowFill)
                    )
                }
            }

            section("Provider") {
                ForEach(config.providers) { provider in
                    providerRow(provider)
                }
                Button {
                    store.openConfigFile()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "curlybraces")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Aggiungi un provider in config.json")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)
                .help("Apre il file per i provider personalizzati")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { contentHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, value in contentHeight = value }
            }
        )
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.tertiary)
            content()
        }
    }

    // MARK: - Righe

    private func toggleRow(_ title: String, detail: String?, isOn: Bool, action: @escaping (Bool) -> Void) -> some View {
        settingRow(title, detail: detail) {
            SoftToggle(isOn: isOn, action: action)
        }
    }

    private func stepperRow(
        _ title: String,
        value: Int,
        range: ClosedRange<Int>,
        unit: String,
        action: @escaping (Int) -> Void
    ) -> some View {
        settingRow(title, detail: nil) {
            SoftStepper(value: value, range: range, unit: unit, action: action)
        }
    }

    private func settingRow(_ title: String, detail: String?, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.rowFill)
        )
    }

    private func providerRow(_ provider: ProviderConfig) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hexString: provider.accent) ?? .secondary)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.name ?? provider.id)
                    .font(.system(size: 12, weight: .medium))
                Text(providerSubtitle(provider))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            SoftToggle(isOn: provider.enabled) { new in
                store.setProviderEnabled(provider.id, new)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.rowFill)
        )
    }

    private func providerSubtitle(_ provider: ProviderConfig) -> String {
        var parts = [provider.type]
        if let error = store.providerErrors[provider.id] {
            parts.append("errore: \(error)")
        } else if let command = provider.command {
            parts.append(command)
        } else if let path = provider.path {
            parts.append(Format.path(path) ?? path)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Controlli

/// Interruttore disegnato a mano: quelli di sistema stonerebbero col resto.
struct SoftToggle: View {
    var isOn: Bool
    var action: (Bool) -> Void

    var body: some View {
        Button { action(!isOn) } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn
                          ? LinearGradient(colors: [Color(hex: 0x4C8DF6), Color(hex: 0x7C6BF5)],
                                           startPoint: .leading, endPoint: .trailing)
                          : LinearGradient(colors: [Color.chipFill, Color.chipFill],
                                           startPoint: .leading, endPoint: .trailing))
                    .frame(width: 34, height: 20)
                    .overlay(Capsule().strokeBorder(Color.hairlineSoft, lineWidth: 0.6))
                Circle()
                    .fill(.white)
                    .frame(width: 15, height: 15)
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 0.5)
                    .padding(.horizontal, 2.5)
            }
            .frame(width: 34, height: 20)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isOn)
    }
}

/// Stepper compatto: [−] valore [+].
struct SoftStepper: View {
    var value: Int
    var range: ClosedRange<Int>
    var unit: String
    var action: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            button("minus", enabled: value > range.lowerBound) {
                action(max(range.lowerBound, value - 1))
            }
            Text(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 44)
            button("plus", enabled: value < range.upperBound) {
                action(min(range.upperBound, value + 1))
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.chipFill)
        )
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(enabled ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.35))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
