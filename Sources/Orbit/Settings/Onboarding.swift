import AppKit
import SwiftUI

/// La guida del primo avvio: una finestra a parte, a passi, con la notch in miniatura
/// sempre in vista. Ogni scelta si applica subito e l'anteprima la mostra nello stesso istante.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?

    func show(services: AppServices) {
        if window == nil { makeWindow(services: services) }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow(services: AppServices) {
        let root = OnboardingView(services: services) { [weak self] in self?.window?.close() }
            .orbitEnvironment(services)
            .frame(minWidth: 860, minHeight: 680)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Orbit"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: root)
        window.setContentSize(NSSize(width: 880, height: 700))
        window.center()
        self.window = window
    }

    /// Chiudere la guida, con "Inizia" o con la X, vale come averla vista: non si ripresenta
    /// a ogni avvio. Si può sempre riaprire da Avanzate.
    func windowWillClose(_ notification: Notification) {
        AppServices.shared.settings.update { $0.onboardingDone = true }
        if !SettingsWindowController.shared.isVisible { NSApp.setActivationPolicy(.accessory) }
        // La prossima volta riparte dal primo passo.
        DispatchQueue.main.async { [weak self] in self?.window = nil }
    }
}

// MARK: - Passi

private enum OnboardingStep: Int, CaseIterable {
    case welcome, content, look, tutorial, ready
}

struct OnboardingView: View {
    let services: AppServices
    var onFinish: () -> Void

    @EnvironmentObject private var settings: SettingsStore
    @State private var step = OnboardingStep.welcome
    @State private var goingForward = true
    @State private var previewPage: String?
    @State private var login = LoginItem.isAvailable

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case .welcome:  WelcomeStep()
                case .content:  ContentStep(selected: profileBinding, previewPage: $previewPage)
                case .look:     LookStep(previewPage: $previewPage)
                case .tutorial: TutorialStep(services: services)
                case .ready:    ReadyStep(login: $login)
                }
            }
            .id(step)
            .transition(.asymmetric(
                insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                removal: .opacity
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider()
            footer
        }
        .background(.background)
        .onChange(of: settings.config.layout.pages.map(\.id)) { _, ids in
            if let previewPage, !ids.contains(previewPage) { self.previewPage = nil }
        }
    }

    /// Il profilo attivo, o quello di partenza se ancora non si è toccato nulla.
    private var profileBinding: Binding<String> {
        Binding(
            get: { settings.config.activeProfileID ?? "default" },
            set: { id in
                guard let profile = ProfileConfig.builtIn.first(where: { $0.id == id }) else { return }
                previewPage = nil
                services.apply(profile: profile)
            }
        )
    }

    // MARK: - Piè di pagina

    private var footer: some View {
        HStack {
            Button("Indietro") { move(by: -1) }
                .opacity(step == .welcome ? 0 : 1)
                .disabled(step == .welcome)
                .frame(width: 100, alignment: .leading)

            Spacer()
            HStack(spacing: 7) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                    Circle()
                        .fill(item == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()

            Group {
                if step == .ready {
                    Button("Inizia") { finish() }
                } else {
                    Button(step == .welcome ? "Cominciamo" : "Avanti") { move(by: 1) }
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func move(by delta: Int) {
        guard let next = OnboardingStep(rawValue: step.rawValue + delta) else { return }
        goingForward = delta > 0
        withAnimation(.easeInOut(duration: 0.28)) { step = next }
    }

    private func finish() {
        LoginItem.set(login)
        onFinish()
    }
}

// MARK: - Anteprima

/// La notch in miniatura su uno sfondo che ricorda la scrivania, più i chip per
/// sfogliarne le pagine: così si vede tutto ciò che il profilo contiene.
private struct PreviewStage: View {
    @Binding var pageID: String?
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        let pages = settings.config.layout.pages
        VStack(spacing: 10) {
            NotchLivePreview(pageID: pageID ?? pages.first?.id, maxWidth: 560)
                .frame(maxWidth: .infinity, minHeight: 224, alignment: .top)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0x28324A), Color(hex: 0x4B3A5C)], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .animation(.easeInOut(duration: 0.25), value: settings.config.layout)

            HStack(spacing: 6) {
                if pages.count > 1 {
                    ForEach(pages) { page in
                        let isCurrent = (pageID ?? pages.first?.id) == page.id
                        Button {
                            pageID = page.id
                        } label: {
                            Label(tr(page.title), systemImage: page.symbol)
                                .font(.callout)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(isCurrent ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12)))
                                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 26)
        }
        .padding(.horizontal, 28)
    }
}

/// Titolo e sottotitolo di un passo.
private struct StepHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - 1 · Benvenuto

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 14) {
            OrbitGlyph()
                .fill(LinearGradient(colors: [Color(hex: 0xFFE9B3), Color(hex: 0xFFA86B), Color(hex: 0xE85C8F)], startPoint: .top, endPoint: .bottom))
                .frame(width: 110, height: 55)
                .padding(.bottom, 8)
            Text("Ti diamo il benvenuto in Orbit")
                .font(.largeTitle.weight(.semibold))
            Text("La notch diventa la parte più utile dello schermo. Passaci sopra col mouse per aprirla.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Text("In un minuto la rendi tua: scegli cosa mostra, come appare e come si usa.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - 2 · Contenuto

private struct ContentStep: View {
    @Binding var selected: String
    @Binding var previewPage: String?

    private struct Choice: Identifiable {
        var id: String
        var title: String
        var detail: String
        var symbol: String
    }

    private var choices: [Choice] { [
        Choice(id: "default", title: tr("Un po' di tutto"), detail: tr("Agenti, musica e calendario, tutti nella prima pagina"), symbol: "moon.stars.fill"),
        Choice(id: "coding", title: tr("Prima di tutto gli agenti"), detail: tr("La notch si apre sulle tue sessioni di coding"), symbol: "chevron.left.forwardslash.chevron.right"),
        Choice(id: "music", title: tr("Prima di tutto la musica"), detail: tr("Il lettore in grande, con i colori della copertina"), symbol: "music.note"),
        Choice(id: "agenda", title: tr("Prima di tutto la giornata"), detail: tr("Calendario, timer e note"), symbol: "calendar"),
        Choice(id: "minimal", title: tr("L'essenziale"), detail: tr("Quasi invisibile, finché non serve"), symbol: "circle")
    ] }

    var body: some View {
        VStack(spacing: 14) {
            PreviewStage(pageID: $previewPage)
                .padding(.top, 34)

            StepHeader(title: "Da dove vuoi partire?", subtitle: "L'anteprima si aggiorna a ogni scelta. Puoi cambiare tutto in qualsiasi momento.")

            // Cinque scelte: in due colonne restano tutte in vista senza scorrere.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(choices) { choice in
                    ChoiceRow(
                        symbol: choice.symbol,
                        title: choice.title,
                        detail: choice.detail,
                        isSelected: selected == choice.id
                    ) { selected = choice.id }
                }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 780)

            Spacer(minLength: 0)
        }
    }
}

private struct ChoiceRow: View {
    let symbol: String
    let title: String
    let detail: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(isSelected ? 0.7 : 0.3)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 3 · Aspetto

private struct LookStep: View {
    @Binding var previewPage: String?
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 14) {
            PreviewStage(pageID: $previewPage)
                .padding(.top, 34)

            StepHeader(title: "Che aspetto deve avere?", subtitle: "Scegli un tema: l'anteprima cambia subito.")

            ThemeGallery()
                .padding(.horizontal, 28)
                .frame(maxWidth: 780)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - 4 · Come si usa

private struct TutorialStep: View {
    let services: AppServices

    @EnvironmentObject private var settings: SettingsStore
    @State private var demoRunning = false

    private var hotkeyText: String {
        guard let binding = settings.config.hotkeys.first(where: { $0.action == .toggleNotch }),
              let code = binding.keyCode
        else { return tr("Assegna una scorciatoia da Impostazioni › Scorciatoie.") }
        return tr("%@ apre e chiude la notch da qualsiasi app.", HotKeyCenter.describe(keyCode: code, modifiers: binding.modifiers))
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            StepHeader(title: "Come si usa", subtitle: "Cinque cose da sapere, poi è tutta tua.")

            VStack(spacing: 8) {
                TutorialRow(
                    symbol: "cursorarrow.motionlines",
                    tint: .blue,
                    title: "Apri con il mouse",
                    detail: "Porta il puntatore sulla notch, oppure clicca: si apre. Allontanalo e si chiude."
                ) {
                    Button(demoRunning ? "Guarda in alto…" : "Provala") { playDemo() }
                        .disabled(demoRunning)
                }
                TutorialRow(
                    symbol: "hand.draw.fill",
                    tint: .purple,
                    title: "Scorri le pagine",
                    detail: "A notch aperta, scorri a sinistra e a destra con due dita per cambiare pagina."
                )
                TutorialRow(
                    symbol: "command",
                    tint: .gray,
                    title: "Dalla tastiera",
                    detailText: hotkeyText
                )
                TutorialRow(
                    symbol: "tray.full.fill",
                    tint: .teal,
                    title: "Trascina i file",
                    detail: "Porta un file verso la notch: finisce nello Scaffale, pronto da riprendere."
                )
                TutorialRow(
                    symbol: "gearshape.fill",
                    tint: .orange,
                    title: "Le impostazioni",
                    detail: "L'icona di Orbit nella barra dei menu apre le impostazioni quando vuoi."
                )
            }
            .frame(maxWidth: 620)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
    }

    /// Apre la notch vera, la lascia un attimo e la richiude: il movimento si vede sul serio.
    private func playDemo() {
        demoRunning = true
        services.notch.open()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            services.notch.close()
            demoRunning = false
        }
    }
}

private struct TutorialRow<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let detailText: Text
    @ViewBuilder var accessory: Accessory

    init(symbol: String, tint: Color, title: LocalizedStringKey, detail: LocalizedStringKey, @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.detailText = Text(detail)
        self.accessory = accessory()
    }

    init(symbol: String, tint: Color, title: LocalizedStringKey, detailText: String, @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.detailText = Text(verbatim: detailText)
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.medium))
                detailText
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.3)))
    }
}

extension TutorialRow where Accessory == EmptyView {
    init(symbol: String, tint: Color, title: LocalizedStringKey, detail: LocalizedStringKey) {
        self.init(symbol: symbol, tint: tint, title: title, detail: detail) { EmptyView() }
    }

    init(symbol: String, tint: Color, title: LocalizedStringKey, detailText: String) {
        self.init(symbol: symbol, tint: tint, title: title, detailText: detailText) { EmptyView() }
    }
}

// MARK: - 5 · Ultimi ritocchi

private struct ReadyStep: View {
    @Binding var login: Bool

    @EnvironmentObject private var calendar: CalendarService
    @State private var accessibility = MediaKeyTap.isTrusted
    @State private var boringNotchRunning = ReadyStep.isBoringNotchRunning
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private static var isBoringNotchRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "theboringteam.boringnotch").isEmpty
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            StepHeader(title: "Ultimi ritocchi", subtitle: "Due permessi facoltativi, poi hai finito.")

            VStack(spacing: 8) {
                PermissionCard(
                    title: tr("Calendario"),
                    detail: tr("Mostra i tuoi eventi nel widget Calendario."),
                    state: calendarState
                ) { calendar.requestEventsAccess() }
                PermissionCard(
                    title: tr("Accessibilità"),
                    detail: tr("Solo per intercettare i tasti di volume e luminosità."),
                    state: accessibility ? .granted : .undetermined
                ) { MediaKeyTap.requestTrust() }

                if boringNotchRunning {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Boring Notch è aperto: due app sulla stessa notch si sovrappongono.")
                            .font(.callout)
                        Spacer()
                        Button("Chiudilo") {
                            NSRunningApplication.runningApplications(withBundleIdentifier: "theboringteam.boringnotch").forEach { $0.terminate() }
                            boringNotchRunning = false
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.12)))
                }

                Toggle("Avvia Orbit al login", isOn: $login)
                    .disabled(!LoginItem.isAvailable)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
            }
            .frame(maxWidth: 620)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .onReceive(timer) { _ in accessibility = MediaKeyTap.isTrusted }
    }

    private var calendarState: PermissionCard.Status {
        switch calendar.eventsAccess {
        case .granted:      .granted
        case .denied:       .denied
        case .undetermined: .undetermined
        }
    }
}

private struct PermissionCard: View {
    enum Status { case granted, denied, undetermined }

    let title: String
    let detail: String
    let state: Status
    var action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            switch state {
            case .granted:
                StatusBadge(text: tr("Consentito"), color: .green)
            case .denied:
                StatusBadge(text: tr("Negato"), color: .red)
                Button("Apri Impostazioni", action: action)
            case .undetermined:
                StatusBadge(text: tr("Non ancora"), color: .orange)
                Button("Consenti", action: action)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.3)))
    }
}
