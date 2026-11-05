import SwiftUI

/// L'aspetto: un tema come punto di partenza, poi ogni dettaglio a piacere.
struct AppearanceSettingsView: View {
    let services: AppServices

    @EnvironmentObject private var settings: SettingsStore
    @State private var pinned = false

    private var appearance: AppearanceConfig { settings.config.appearance }

    var body: some View {
        VStack(spacing: 0) {
            previewArea
            Divider()
            form
        }
        .onChange(of: pinned) { _, value in services.notch.setPreviewPinned(value) }
        .onDisappear {
            if pinned { services.notch.setPreviewPinned(false) }
        }
    }

    /// L'anteprima resta sempre in vista mentre si scorrono i controlli.
    private var previewArea: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Anteprima")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Prova il movimento") { playMotionDemo() }
                    .controlSize(.small)
                Toggle("Tieni aperta la notch", isOn: $pinned)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            NotchLivePreview(pageID: settings.config.layout.pages.first?.id, maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0x28324A), Color(hex: 0x4B3A5C)], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func playMotionDemo() {
        services.notch.open()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { services.notch.close() }
    }

    private var form: some View {
        Form {
            Section("Tema") {
                ThemeGallery()
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            Section("Superficie") {
                Picker("Materiale", selection: settings.binding(\.appearance.surface)) {
                    ForEach(SurfaceStyle.allCases) { Text($0.label).tag($0) }
                }
                switch appearance.surface {
                case .solid:
                    HexColorPicker(title: tr("Colore"), hex: settings.binding(\.appearance.solidHex))
                case .gradient:
                    GradientEditor()
                case .glass:
                    ValueSlider(
                        title: tr("Oscuramento"),
                        value: settings.binding(\.appearance.glassDim),
                        range: 0...0.9,
                        step: 0.05,
                        format: { "\(Int($0 * 100))%" }
                    )
                case .artwork:
                    Text("Usa la copertina del brano in riproduzione, sfocata, come sfondo della notch aperta.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Colore d'accento") {
                Picker("Accento", selection: settings.binding(\.appearance.accentMode)) {
                    ForEach(AccentMode.allCases) { Text($0.label).tag($0) }
                }
                if appearance.accentMode != .system {
                    HexColorPicker(
                        title: appearance.accentMode == .artwork ? tr("Quando non c'è musica") : tr("Colore"),
                        hex: settings.binding(\.appearance.accentHex)
                    )
                }
            }

            Section("Forma") {
                ValueSlider(title: tr("Larghezza da aperta"), value: settings.binding(\.appearance.openWidth), range: 520...1100, step: 10)
                ValueSlider(title: tr("Altezza da aperta"), value: settings.binding(\.appearance.openHeight), range: 170...420, step: 4)
                ValueSlider(title: tr("Angoli da aperta"), value: settings.binding(\.appearance.openBottomRadius), range: 8...48)
                ValueSlider(title: tr("Raccordo in alto da aperta"), value: settings.binding(\.appearance.openEarRadius), range: 0...28)
                ValueSlider(title: tr("Angoli da chiusa"), value: settings.binding(\.appearance.closedBottomRadius), range: 4...20)
                ValueSlider(title: tr("Raccordo in alto da chiusa"), value: settings.binding(\.appearance.closedEarRadius), range: 0...14)
                ValueSlider(title: tr("Larghezza massima delle ali"), value: settings.binding(\.appearance.maxWingWidth), range: 60...320, step: 5)
            }

            Section("Profondità") {
                ValueSlider(title: tr("Ombra"), value: settings.binding(\.appearance.shadow), range: 0...1, step: 0.05, format: { "\(Int($0 * 100))%" })
                ValueSlider(title: tr("Bordo luminoso"), value: settings.binding(\.appearance.border), range: 0...1, step: 0.05, format: { "\(Int($0 * 100))%" })
                ValueSlider(title: tr("Luce ambientale"), value: settings.binding(\.appearance.glow), range: 0...1, step: 0.05, format: { "\(Int($0 * 100))%" })
                Toggle("Alone quando un agente ti aspetta", isOn: settings.binding(\.appearance.attentionGlow))
            }

            Section("Contenuto") {
                Picker("Card dei widget", selection: settings.binding(\.appearance.cardStyle)) {
                    ForEach(CardStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                ValueSlider(title: tr("Angoli delle card"), value: settings.binding(\.appearance.cardRadius), range: 4...30)
                ValueSlider(title: tr("Spazio fra i widget"), value: settings.binding(\.appearance.widgetSpacing), range: 0...20)
                Picker("Carattere", selection: settings.binding(\.appearance.font)) {
                    ForEach(FontChoice.allCases) { Text($0.label).font(.system(.body, design: $0.design)).tag($0) }
                }
                ValueSlider(title: tr("Dimensione del testo"), value: settings.binding(\.appearance.textScale), range: 0.85...1.25, step: 0.05, format: { "\(Int($0 * 100))%" })
                Picker("Pagine nella testata", selection: settings.binding(\.appearance.tabStyle)) {
                    ForEach(TabStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Movimento") {
                Picker("Animazione", selection: settings.binding(\.appearance.motion)) {
                    ForEach(MotionStyle.allCases) { Text($0.label).tag($0) }
                }
                ValueSlider(title: tr("Velocità"), value: settings.binding(\.appearance.motionSpeed), range: 0.5...2, step: 0.1, format: { String(format: "%.1f×", $0) })
                Toggle("Messa a fuoco del contenuto all'apertura", isOn: settings.binding(\.appearance.contentBlur))
                Toggle("Piccolo rimbalzo al passaggio del mouse", isOn: settings.binding(\.appearance.hoverBump))
                Picker("Visualizzatore musicale", selection: settings.binding(\.appearance.visualizer)) {
                    ForEach(VisualizerStyle.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// I temi, ognuno disegnato col proprio materiale e col proprio accento.
struct ThemeGallery: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ThemePreset.all) { preset in
                    ThemeCard(preset: preset, isSelected: settings.config.appearance.themeID == preset.id) {
                        settings.update { preset.apply(to: &$0.appearance) }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct ThemeCard: View {
    let preset: ThemePreset
    var isSelected: Bool
    var action: () -> Void

    private var accent: Color {
        preset.accentMode == .system ? Color(nsColor: .controlAccentColor) : (Color(hexString: preset.accentHex) ?? .white)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack(alignment: .top) {
                    background
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(.black)
                            .frame(width: 26, height: 6)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.white.opacity(preset.cardStyle == .plain ? 0 : 0.1))
                            .overlay {
                                Capsule()
                                    .fill(accent)
                                    .frame(width: 38, height: 4)
                            }
                            .padding(.horizontal, 7)
                            .padding(.bottom, 7)
                    }
                }
                .frame(width: 84, height: 54)
                .clipShape(NotchShape(earRadius: 5, bottomRadius: 12))
                .overlay(
                    NotchShape(earRadius: 5, bottomRadius: 12)
                        .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.14), lineWidth: isSelected ? 2 : 1)
                )

                Text(preset.name)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var background: some View {
        switch preset.surface {
        case .solid:
            Color(hexString: preset.solidHex) ?? .black
        case .gradient:
            LinearGradient(colors: preset.gradientHex.compactMap { Color(hexString: $0) }, startPoint: .top, endPoint: .bottom)
        case .glass:
            LinearGradient(colors: [.black, Color(white: 0.35, opacity: 0.8)], startPoint: .top, endPoint: .bottom)
        case .artwork:
            LinearGradient(colors: [.black, Color(hex: 0x8B2A6B), Color(hex: 0xF08A4B)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Da due a quattro colori, con l'anteprima della sfumatura che ne esce.
private struct GradientEditor: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        let colors = settings.config.appearance.gradientHex
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Colori")
                Spacer()
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: colors.compactMap { Color(hexString: $0) }, startPoint: .leading, endPoint: .trailing))
                    .frame(width: 120, height: 18)
                ForEach(colors.indices, id: \.self) { index in
                    ColorPicker("", selection: colorBinding(index), supportsOpacity: false)
                        .labelsHidden()
                }
                Button {
                    settings.update { config in
                        guard config.appearance.gradientHex.count < 4 else { return }
                        config.appearance.gradientHex.append(config.appearance.gradientHex.last ?? "#14141B")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(colors.count >= 4)
                Button {
                    settings.update { config in
                        guard config.appearance.gradientHex.count > 2 else { return }
                        config.appearance.gradientHex.removeLast()
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(colors.count <= 2)
            }
            Text("Il primo colore è quello in alto: più è scuro, meglio si fonde con la notch vera.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { Color(hexString: settings.config.appearance.gradientHex[safe: index]) ?? .black },
            set: { color in
                guard let hex = color.hexString else { return }
                settings.update { $0.appearance.gradientHex[index] = hex }
            }
        )
    }
}
