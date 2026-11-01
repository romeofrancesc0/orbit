import AppKit
import Combine
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case welcome, layout, appearance, general, profiles
    case agents, music, calendar, shelf, launcher, widgets
    case peeks, hud, shortcuts, permissions, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome:     "Primi passi"
        case .layout:      "Layout"
        case .appearance:  "Aspetto"
        case .general:     "Comportamento"
        case .profiles:    "Profili"
        case .agents:      "Agenti"
        case .music:       "Musica"
        case .calendar:    "Calendario"
        case .shelf:       "Scaffale"
        case .launcher:    "Collegamenti"
        case .widgets:     "Widget personalizzati"
        case .peeks:       "Avvisi"
        case .hud:         "Volume e luminosità"
        case .shortcuts:   "Scorciatoie"
        case .permissions: "Permessi"
        case .advanced:    "Avanzate"
        }
    }

    var symbol: String {
        switch self {
        case .welcome:     "moon.stars.fill"
        case .layout:      "rectangle.3.group.fill"
        case .appearance:  "paintpalette.fill"
        case .general:     "cursorarrow.motionlines"
        case .profiles:    "person.2.fill"
        case .agents:      "sparkles"
        case .music:       "music.note"
        case .calendar:    "calendar"
        case .shelf:       "tray.full.fill"
        case .launcher:    "square.grid.2x2.fill"
        case .widgets:     "terminal.fill"
        case .peeks:       "bell.badge.fill"
        case .hud:         "speaker.wave.2.fill"
        case .shortcuts:   "command"
        case .permissions: "lock.shield.fill"
        case .advanced:    "gearshape.2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .welcome:     .indigo
        case .layout:      .blue
        case .appearance:  .pink
        case .general:     .gray
        case .profiles:    .purple
        case .agents:      Color(hex: 0xD97757)
        case .music:       .red
        case .calendar:    .orange
        case .shelf:       .teal
        case .launcher:    .mint
        case .widgets:     Color(white: 0.3)
        case .peeks:       .red
        case .hud:         .blue
        case .shortcuts:   Color(white: 0.45)
        case .permissions: .green
        case .advanced:    .gray
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var selection: SettingsSection? = .layout
}

/// La finestra delle impostazioni. Finché resta aperta l'app compare nel Dock e
/// nel selettore delle app, come una normale finestra di macOS.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let navigation = SettingsNavigation()

    func show(section: SettingsSection?, services: AppServices) {
        if let section { navigation.selection = section }
        if window == nil { makeWindow(services: services) }

        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow(services: AppServices) {
        let root = SettingsRoot(navigation: navigation, services: services)
            .powerednotchEnvironment(services)
            .frame(minWidth: 820, minHeight: 560)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1020, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Powered Notch"
        window.titlebarAppearsTransparent = true
        // Ogni pagina ha già la sua intestazione: il titolo in barra sarebbe un doppione,
        // e il contenuto gli scorrerebbe sotto.
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        // Si apre nello spazio in cui stai lavorando, anche sopra un'app a tutto schermo,
        // invece di trascinarti via sulla scrivania.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: root)
        window.setContentSize(NSSize(width: 1020, height: 720))
        window.setFrameAutosaveName("PoweredNotchSettings")
        window.center()
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        AppServices.shared.notch.setPreviewPinned(false)
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Struttura

struct SettingsRoot: View {
    @ObservedObject var navigation: SettingsNavigation
    let services: AppServices

    private let groups: [(String, [SettingsSection])] = [
        ("Notch", [.layout, .appearance, .general, .profiles]),
        ("Contenuti", [.agents, .music, .calendar, .shelf, .launcher, .widgets]),
        ("Sistema", [.peeks, .hud, .shortcuts, .permissions, .advanced])
    ]

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                ForEach(groups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1) { section in
                            SidebarRow(section: section).tag(section)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 225, max: 280)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(navigation.selection?.title ?? "Powered Notch")
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selection ?? .layout {
        case .welcome:     WelcomeView(services: services) { navigation.selection = .layout }
        case .layout:      LayoutEditorView(services: services)
        case .appearance:  AppearanceSettingsView(services: services)
        case .general:     GeneralSettingsView()
        case .profiles:    ProfilesSettingsView(services: services)
        case .agents:      AgentsSettingsView()
        case .music:       MusicSettingsView()
        case .calendar:    CalendarSettingsView()
        case .shelf:       ShelfSettingsView()
        case .launcher:    LauncherSettingsView()
        case .widgets:     CustomWidgetsSettingsView()
        case .peeks:       PeeksSettingsView()
        case .hud:         HUDSettingsView()
        case .shortcuts:   ShortcutsSettingsView()
        case .permissions: PermissionsSettingsView()
        case .advanced:    AdvancedSettingsView()
        }
    }
}

private struct SidebarRow: View {
    let section: SettingsSection

    var body: some View {
        Label {
            Text(section.title)
        } icon: {
            SectionIcon(section: section, size: 20)
        }
    }
}

/// La piastrella colorata delle impostazioni di sistema.
struct SectionIcon: View {
    let section: SettingsSection
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(section.tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: section.symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

// MARK: - Componenti

/// Intestazione comune alle pagine: dice in una riga a cosa serve quella schermata.
struct SettingsHeader: View {
    let section: SettingsSection
    var subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            SectionIcon(section: section, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title).font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Pagina standard: intestazione e modulo raggruppato in stile Impostazioni di Sistema.
struct SettingsForm<Content: View>: View {
    let section: SettingsSection
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Section {
                SettingsHeader(section: section, subtitle: subtitle)
            }
            .listRowBackground(Color.clear)
            content
        }
        .formStyle(.grouped)
    }
}

/// Cursore con il valore accanto: "quanto" si legge senza dover indovinare.
struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { "\(Int($0.rounded()))" }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            Slider(value: $value, in: range, step: step)
                .frame(maxWidth: 260)
                .labelsHidden()
            Text(format(value))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

/// Selettore di colore collegato a un valore esadecimale della configurazione.
struct HexColorPicker: View {
    let title: String
    @Binding var hex: String

    private var color: Binding<Color> {
        Binding(
            get: { Color(hexString: hex) ?? .white },
            set: { hex = $0.hexString ?? hex }
        )
    }

    var body: some View {
        ColorPicker(title, selection: color, supportsOpacity: false)
    }
}

/// Riga col riquadro di stato di un permesso o di un componente.
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Anteprima dal vivo

/// La notch vera, in miniatura: stesse viste, stessi dati, solo più piccola.
/// Quello che si vede qui è esattamente quello che comparirà sullo schermo.
struct NotchLivePreview: View {
    var pageID: String?
    var maxWidth: CGFloat = 640

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var media: MediaService
    @StateObject private var state = NotchState(geometry: NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        hasHardwareNotch: true,
        notchWidth: 185,
        notchHeight: 32
    ))
    @StateObject private var actions = NotchActions()

    var body: some View {
        let config = settings.config
        let theme = NotchTheme.resolve(config.appearance, artwork: config.media.tintWithArtwork ? media.artworkColor : nil)
        let page = pageID.flatMap { id in config.layout.pages.first { $0.id == id } } ?? config.layout.pages.first
        let size = CGSize(
            width: config.appearance.openWidth,
            height: page?.height ?? config.appearance.openHeight
        )
        let scale = min(1, maxWidth / size.width)
        let shape = NotchShape(
            earRadius: CGFloat(config.appearance.openEarRadius),
            bottomRadius: CGFloat(config.appearance.openBottomRadius)
        )

        ZStack(alignment: .top) {
            NotchSurface(isOpen: true, shape: shape, size: size)
            if state.isOpen {
                OpenNotchContent(state: state)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(
            shape.stroke(
                LinearGradient(
                    colors: [.white.opacity(0), .white.opacity(0.28 * config.appearance.border)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        )
        .environment(\.notchTheme, theme)
        .environment(\.panelIsVisible, false)
        .environmentObject(actions)
        .allowsHitTesting(false)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
        .onAppear { sync() }
        .onChange(of: pageID) { _, _ in sync() }
        .onChange(of: settings.config.layout.pages) { _, _ in sync() }
    }

    private func sync() {
        let config = settings.config
        state.open(page: pageID ?? config.layout.pages.first?.id, config: config, hasAttention: false)
        if let pageID { state.selectedPageID = pageID }
    }
}
