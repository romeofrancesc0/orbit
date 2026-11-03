import AVFoundation
import SwiftUI

// MARK: - Batteria

struct BatteryWidget: View {
    @EnvironmentObject private var battery: BatteryMonitor
    @Environment(\.notchTheme) private var theme

    private var state: BatteryState { battery.state }

    private var tint: Color {
        if state.isCharging || state.isPluggedIn { return Color(hex: 0x4ADE80) }
        if state.isLowPowerMode { return Color(hex: 0xFFC145) }
        if state.level <= 0.2 { return Color(hex: 0xFF5A63) }
        return theme.accent
    }

    private var statusText: String {
        if !state.hasBattery { return tr("Alimentazione") }
        if state.isCharging {
            return state.minutesRemaining.map { tr("Piena tra %@", Format.duration(Double($0) * 60)) } ?? tr("In carica")
        }
        if state.isOptimizedHold { return tr("Carica in pausa") }
        if state.isPluggedIn { return tr("Collegata") }
        return state.minutesRemaining.map { tr("Restano %@", Format.duration(Double($0) * 60)) } ?? tr("A batteria")
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                ContextRing(fraction: state.level, tint: tint, size: 62, lineWidth: 6)
                VStack(spacing: 0) {
                    if state.isCharging || state.isPluggedIn {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    Text("\(Int((state.level * 100).rounded()))")
                        .font(theme.numberFont(17, .semibold))
                        .foregroundStyle(theme.primary)
                }
            }
            VStack(spacing: 1) {
                Text(statusText)
                    .font(theme.font(10.5, .medium))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                if state.isLowPowerMode {
                    Text("Risparmio energetico")
                        .font(theme.font(9))
                        .foregroundStyle(Color(hex: 0xFFC145))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sistema

struct SystemWidget: View {
    @EnvironmentObject private var system: SystemMonitor
    @Environment(\.notchTheme) private var theme

    var body: some View {
        let snapshot = system.snapshot
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                gauge(label: "CPU", fraction: snapshot.cpu, value: "\(Int(snapshot.cpu * 100))%")
                gauge(label: tr("Memoria"), fraction: snapshot.memory, value: "\(Int(snapshot.memory * 100))%")
                gauge(label: tr("Disco"), fraction: snapshot.disk, value: "\(Int(snapshot.disk * 100))%")
            }
            CPUSparkline(values: snapshot.cpuHistory, tint: theme.accent)
                .frame(maxHeight: .infinity)
            HStack(spacing: 10) {
                Label(Format.bytesPerSecond(snapshot.networkDownPerSecond), systemImage: "arrow.down")
                Label(Format.bytesPerSecond(snapshot.networkUpPerSecond), systemImage: "arrow.up")
                Spacer(minLength: 0)
                if snapshot.thermalIsElevated {
                    Image(systemName: "thermometer.high")
                        .foregroundStyle(Color(hex: 0xFF5A63))
                        .help("Il Mac si sta scaldando")
                }
            }
            .font(theme.numberFont(9.5))
            .foregroundStyle(theme.secondary)
            .labelStyle(TightLabelStyle())
        }
        .onAppear { system.retain() }
        .onDisappear { system.release() }
    }

    private func gauge(label: String, fraction: Double, value: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                ContextRing(fraction: fraction, tint: fraction > 0.85 ? Color(hex: 0xFFC145) : theme.accent, size: 38, lineWidth: 4)
                Text(value)
                    .font(theme.numberFont(9, .semibold))
                    .foregroundStyle(theme.primary)
            }
            Text(label)
                .font(theme.font(9))
                .foregroundStyle(theme.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon
            configuration.title
        }
    }
}

private struct CPUSparkline: View {
    var values: [Double]
    var tint: Color

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let step = values.count > 1 ? size.width / CGFloat(max(values.count - 1, 1)) : 0
            let points = values.enumerated().map { index, value in
                CGPoint(x: CGFloat(index) * step, y: size.height * (1 - CGFloat(value)))
            }
            ZStack {
                Path { path in
                    guard let first = points.first, let last = points.last else { return }
                    path.move(to: CGPoint(x: first.x, y: size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: last.x, y: size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.3), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(tint.opacity(0.9), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Appunti

struct ClipboardWidget: View {
    @EnvironmentObject private var clipboard: ClipboardStore
    @Environment(\.notchTheme) private var theme
    @State private var copiedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Appunti")
                    .font(theme.font(12, .semibold))
                    .foregroundStyle(theme.primary)
                Spacer()
                if !clipboard.entries.isEmpty {
                    NotchIconButton(symbol: "trash", size: 20, iconSize: 9.5, help: tr("Svuota la cronologia"), action: clipboard.clear)
                }
            }
            .padding(.horizontal, 4)

            if clipboard.entries.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(theme.tertiary)
                    Text("Copia qualcosa e la ritrovi qui")
                        .font(theme.font(10.5))
                        .foregroundStyle(theme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 1) {
                        ForEach(clipboard.entries) { entry in
                            ClipboardRow(entry: entry, copied: copiedID == entry.id) {
                                clipboard.copy(entry)
                                copiedID = entry.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    if copiedID == entry.id { copiedID = nil }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    var copied: Bool
    var action: () -> Void

    @EnvironmentObject private var clipboard: ClipboardStore
    @Environment(\.notchTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                leading
                    .frame(width: 18, height: 18)
                Text(entry.preview)
                    .font(theme.font(10.5))
                    .foregroundStyle(theme.primary.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if copied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Color(hex: 0x4ADE80))
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? theme.hoverFill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copia", action: action)
            Button("Rimuovi") { clipboard.remove(entry) }
        }
        .help(entry.sourceApp.map { tr("Da %@", $0) } ?? "")
    }

    @ViewBuilder
    private var leading: some View {
        if case .image(let image) = entry.content {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: entry.symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.tertiary)
        }
    }
}

// MARK: - Timer

struct TimerWidget: View {
    @EnvironmentObject private var timer: TimerStore
    @Environment(\.notchTheme) private var theme

    private let presets: [Double] = [1, 5, 10, 25, 45]

    var body: some View {
        VStack(spacing: 8) {
            if timer.isActive {
                running
            } else {
                picker
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: timer.isActive)
    }

    private var running: some View {
        VStack(spacing: 7) {
            TimelineView(.periodic(from: .now, by: timer.isRunning ? 1 : 60)) { context in
                ZStack {
                    if let fraction = timer.fraction(at: context.date) {
                        ContextRing(fraction: fraction, tint: theme.accent, size: 84, lineWidth: 5)
                    }
                    Text(Format.countdown(timer.displaySeconds(at: context.date)))
                        .font(theme.numberFont(20, .semibold))
                        .foregroundStyle(theme.primary)
                        .contentTransition(.numericText(countsDown: true))
                }
            }
            HStack(spacing: 6) {
                NotchIconButton(symbol: timer.isRunning ? "pause.fill" : "play.fill", size: 30, iconSize: 13, isActive: true) {
                    timer.isRunning ? timer.pause() : timer.resume()
                }
                NotchIconButton(symbol: "xmark", size: 30, iconSize: 12, action: timer.reset)
            }
        }
    }

    private var picker: some View {
        VStack(spacing: 8) {
            Text("Timer")
                .font(theme.font(12, .semibold))
                .foregroundStyle(theme.primary)
            HStack(spacing: 4) {
                ForEach(presets, id: \.self) { minutes in
                    NotchPillButton(symbol: nil, label: "\(Int(minutes))", tint: nil) {
                        timer.start(minutes: minutes)
                    }
                    .help("\(Int(minutes)) minuti")
                }
            }
            NotchPillButton(symbol: "stopwatch", label: tr("Cronometro"), tint: theme.accent, action: timer.startStopwatch)
        }
    }
}

// MARK: - Note

struct NotesWidget: View {
    @EnvironmentObject private var notes: NotesStore
    @EnvironmentObject private var actions: NotchActions
    @Environment(\.notchTheme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $notes.text)
                .font(theme.font(12))
                .foregroundStyle(theme.primary)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .focused($focused)
            if notes.text.isEmpty {
                Text("Scrivi qualcosa…")
                    .font(theme.font(12))
                    .foregroundStyle(theme.tertiary)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        // Mentre scrivi la notch non si chiude se il mouse scivola via.
        .onChange(of: focused) { _, isFocused in
            actions.setHold("note", isFocused)
        }
    }
}

// MARK: - Collegamenti

struct LauncherWidget: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var actions: NotchActions
    @Environment(\.notchTheme) private var theme

    var body: some View {
        let items = settings.config.launcher.items
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 2)], spacing: 4) {
                ForEach(items) { item in
                    LauncherTile(item: item) {
                        LauncherRunner.run(item)
                        actions.close()
                    }
                }
                NotchIconButton(symbol: "plus", size: 34, iconSize: 13, help: tr("Aggiungi un collegamento")) {
                    actions.openSettings(.launcher)
                }
                .frame(height: 62)
            }
        }
    }
}

private struct LauncherTile: View {
    let item: LauncherItem
    var action: () -> Void

    @Environment(\.notchTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                icon
                    .frame(width: 34, height: 34)
                    .scaleEffect(hovering ? 1.08 : 1)
                Text(tr(item.name))
                    .font(theme.font(9.5))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 58)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? theme.hoverFill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchPressStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }

    @ViewBuilder
    private var icon: some View {
        if item.kind == .app {
            Image(nsImage: NSWorkspace.shared.icon(forFile: AppPaths.expand(item.target).path))
                .resizable()
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.accent.opacity(0.2))
                .overlay {
                    Image(systemName: item.symbol ?? LauncherRunner.defaultSymbol(item.kind))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
        }
    }
}

enum LauncherRunner {
    static func defaultSymbol(_ kind: LauncherItemKind) -> String {
        switch kind {
        case .app:      "app.fill"
        case .shortcut: "square.2.layers.3d.fill"
        case .url:      "link"
        case .command:  "terminal.fill"
        }
    }

    static func run(_ item: LauncherItem) {
        switch item.kind {
        case .app:
            NSWorkspace.shared.open(AppPaths.expand(item.target))
        case .url:
            if let url = URL(string: item.target) { NSWorkspace.shared.open(url) }
        case .shortcut:
            launch("/usr/bin/shortcuts", ["run", item.target])
        case .command:
            launch("/bin/sh", ["-lc", item.target])
        }
    }

    private static func launch(_ executable: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

// MARK: - Orologio

struct ClockWidget: View {
    @Environment(\.notchTheme) private var theme

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 2) {
                Text(context.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale)))
                    .font(theme.numberFont(30, .semibold))
                    .foregroundStyle(theme.primary)
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(L10n.locale)))
                    .font(theme.font(10.5))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Specchio

struct MirrorWidget: View {
    @EnvironmentObject private var camera: CameraMirror
    @EnvironmentObject private var actions: NotchActions
    @Environment(\.notchTheme) private var theme
    @State private var enabled = false

    var body: some View {
        ZStack {
            if enabled, camera.access == .granted {
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: max(theme.cardRadius - 6, 8), style: .continuous))
                    .onAppear { camera.start() }
                    .onDisappear { camera.stop() }
                    .overlay(alignment: .topTrailing) {
                        NotchIconButton(symbol: "xmark", size: 22, iconSize: 9.5) { enabled = false }
                            .background(Circle().fill(.black.opacity(0.4)))
                            .padding(5)
                    }
            } else {
                Button {
                    if camera.access == .granted {
                        enabled = true
                    } else {
                        actions.keepOpenDuringSystemPrompt()
                        camera.requestAccess()
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "person.crop.square.fill")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(theme.secondary)
                        Text(camera.access == .denied ? tr("Consenti in Impostazioni") : tr("Specchio"))
                            .font(theme.font(10.5, .medium))
                            .foregroundStyle(theme.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NotchPressStyle())
            }
        }
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        if layer.connection?.isVideoMirroringSupported == true {
            layer.connection?.automaticallyAdjustsVideoMirroring = false
            layer.connection?.isVideoMirrored = true
        }
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

// MARK: - Widget da script

struct CustomWidgetView: View {
    let config: CustomWidgetConfig?

    @EnvironmentObject private var store: CustomWidgetStore
    @EnvironmentObject private var actions: NotchActions
    @Environment(\.notchTheme) private var theme

    var body: some View {
        if let config {
            content(config)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "questionmark.square.dashed")
                    .foregroundStyle(theme.tertiary)
                Text("Widget rimosso")
                    .font(theme.font(10.5))
                    .foregroundStyle(theme.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func content(_ config: CustomWidgetConfig) -> some View {
        let output = store.outputs[config.id]
        let tint = Color(hexString: output?.tint) ?? theme.accent

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: output?.symbol ?? config.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(config.name)
                    .font(theme.font(11, .semibold))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                NotchIconButton(symbol: "arrow.clockwise", size: 18, iconSize: 8.5) { store.runNow(config.id) }
            }

            if let text = output?.text {
                Text(text)
                    .font(theme.font(19, .semibold))
                    .foregroundStyle(theme.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            if let subtitle = output?.subtitle {
                Text(subtitle)
                    .font(theme.font(10.5))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(2)
            }
            if let progress = output?.progress {
                LevelBar(fraction: progress, tint: tint, height: 4)
            }
            if let rows = output?.rows, !rows.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(rows) { row in
                            HStack(spacing: 5) {
                                if let symbol = row.symbol {
                                    Image(systemName: symbol)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(Color(hexString: row.tint) ?? theme.tertiary)
                                }
                                Text(row.title)
                                    .font(theme.font(10.5))
                                    .foregroundStyle(theme.secondary)
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                if let value = row.value {
                                    Text(value)
                                        .font(theme.numberFont(10.5))
                                        .foregroundStyle(theme.primary)
                                }
                            }
                        }
                    }
                }
            }
            if let error = store.errors[config.id], output == nil {
                Text(error)
                    .font(theme.font(9.5))
                    .foregroundStyle(Color(hex: 0xFF8A80))
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let raw = output?.url, let url = URL(string: raw) else { return }
            NSWorkspace.shared.open(url)
            actions.close()
        }
    }
}
