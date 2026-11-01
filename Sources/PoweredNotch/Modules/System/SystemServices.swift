import AppKit
import Combine
import Darwin
import IOKit.ps

// MARK: - Batteria

struct BatteryState: Equatable {
    var hasBattery = false
    var level: Double = 1
    var isCharging = false
    var isPluggedIn = false
    var isOptimizedHold = false
    var minutesRemaining: Int?
    var isLowPowerMode = false
}

/// Stato della batteria, aggiornato dalle notifiche di sistema: nessun polling.
@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var state = BatteryState()

    /// Chiamate per gli avvisi nella notch.
    var onPlugChange: ((BatteryState) -> Void)?
    var onLowBattery: ((BatteryState) -> Void)?

    private var source: CFRunLoopSource?
    private var lowWarned = false
    private var powerObserver: NSObjectProtocol?

    func start() {
        guard source == nil else { return }
        refresh(notify: false)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.refresh(notify: true) }
        }
        if let created = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
            source = created
        }
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh(notify: false) }
        }
    }

    func seedForPreview(_ preview: BatteryState) { state = preview }

    private func refresh(notify: Bool) {
        let previous = state
        var next = Self.read()
        next.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard next != previous else { return }
        state = next
        guard notify, next.hasBattery else { return }

        if next.isPluggedIn != previous.isPluggedIn { onPlugChange?(next) }

        if next.isPluggedIn || next.level > 0.21 {
            lowWarned = false
        } else if !lowWarned, next.level <= 0.2 {
            lowWarned = true
            onLowBattery?(next)
        }
    }

    private static func read() -> BatteryState {
        var state = BatteryState()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return state }

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }

            state.hasBattery = true
            let current = description[kIOPSCurrentCapacityKey] as? Double ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Double ?? 100
            state.level = maximum > 0 ? current / maximum : 1
            state.isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            state.isPluggedIn = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            state.isOptimizedHold = state.isPluggedIn && !state.isCharging && state.level < 1

            let minutes = (state.isCharging ? description[kIOPSTimeToFullChargeKey] : description[kIOPSTimeToEmptyKey]) as? Int
            state.minutesRemaining = (minutes ?? -1) > 0 ? minutes : nil
        }
        return state
    }
}

// MARK: - Sistema

struct SystemSnapshot: Equatable {
    var cpu: Double = 0
    var memory: Double = 0
    var memoryUsedGB: Double = 0
    var memoryTotalGB: Double = 0
    var disk: Double = 0
    var diskFreeGB: Double = 0
    var networkDownPerSecond: Double = 0
    var networkUpPerSecond: Double = 0
    var thermalIsElevated = false
    var cpuHistory: [Double] = []
}

/// Misure del sistema. Gira solo finché qualcuno le sta guardando.
@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()

    private var timer: Timer?
    private var users = 0
    private var previousTicks: [UInt32]?
    private var previousNetwork: (down: UInt64, up: UInt64, at: Date)?
    private var diskCheckedAt: Date = .distantPast
    private var isPreview = false

    func retain() {
        users += 1
        guard users == 1, !isPreview else { return }
        sample()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func release() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func seedForPreview(_ preview: SystemSnapshot) {
        isPreview = true
        snapshot = preview
    }

    private func sample() {
        var next = snapshot
        next.cpu = readCPU() ?? next.cpu
        next.cpuHistory = Array((next.cpuHistory + [next.cpu]).suffix(30))

        if let memory = Self.readMemory() {
            next.memory = memory.used / memory.total
            next.memoryUsedGB = memory.used / 1_073_741_824
            next.memoryTotalGB = memory.total / 1_073_741_824
        }

        if Date().timeIntervalSince(diskCheckedAt) > 60 {
            diskCheckedAt = Date()
            let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
            if let free = values?.volumeAvailableCapacityForImportantUsage, let total = values?.volumeTotalCapacity, total > 0 {
                next.diskFreeGB = Double(free) / 1_000_000_000
                next.disk = 1 - Double(free) / Double(total)
            }
        }

        if let counters = Self.readNetwork() {
            let now = Date()
            if let previous = previousNetwork {
                let elapsed = max(now.timeIntervalSince(previous.at), 0.1)
                next.networkDownPerSecond = Double(counters.down &- previous.down) / elapsed
                next.networkUpPerSecond = Double(counters.up &- previous.up) / elapsed
            }
            previousNetwork = (counters.down, counters.up, now)
        }

        let thermal = ProcessInfo.processInfo.thermalState
        next.thermalIsElevated = thermal == .serious || thermal == .critical
        snapshot = next
    }

    private func readCPU() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { previousTicks = ticks }
        guard let previous = previousTicks else { return nil }

        let deltas = zip(ticks, previous).map { Double($0 &- $1) }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return nil }
        // L'ordine è user, system, idle, nice.
        return 1 - deltas[2] / total
    }

    private static func readMemory() -> (used: Double, total: Double)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        return (used, Double(ProcessInfo.processInfo.physicalMemory))
    }

    private static func readNetwork() -> (down: UInt64, up: UInt64)? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }

        var down: UInt64 = 0, up: UInt64 = 0
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            let name = String(cString: interface.pointee.ifa_name)
            guard name.hasPrefix("en"),
                  interface.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
                  let raw = interface.pointee.ifa_data
            else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self).pointee
            down += UInt64(data.ifi_ibytes)
            up += UInt64(data.ifi_obytes)
        }
        return (down, up)
    }
}

// MARK: - Appunti

struct ClipboardEntry: Identifiable, Equatable {
    enum Content: Equatable {
        case text(String)
        case image(NSImage)
        case files([URL])
    }

    let id = UUID()
    var content: Content
    var sourceApp: String?
    var copiedAt: Date

    static func == (lhs: ClipboardEntry, rhs: ClipboardEntry) -> Bool { lhs.id == rhs.id }

    var preview: String {
        switch content {
        case .text(let text):   text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image:            "Immagine"
        case .files(let urls):  urls.map(\.lastPathComponent).joined(separator: ", ")
        }
    }

    var symbol: String {
        switch content {
        case .text:  "text.alignleft"
        case .image: "photo"
        case .files: "doc"
        }
    }
}

/// Cronologia degli appunti. Resta solo in memoria e salta ciò che le app
/// segnano come riservato, per esempio le password copiate da un gestore.
@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    var maxItems = 30

    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    private var isPreview = false

    func start() {
        guard timer == nil, !isPreview else { return }
        lastChange = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func seedForPreview(_ preview: [ClipboardEntry]) {
        isPreview = true
        entries = preview
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount

        let types = pasteboard.types?.map(\.rawValue) ?? []
        let private_ = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword"]
        guard !types.contains(where: private_.contains) else { return }

        let source = NSWorkspace.shared.frontmostApplication?.localizedName
        let content: ClipboardEntry.Content
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            content = .files(urls)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            content = .text(text)
        } else if let image = NSImage(pasteboard: pasteboard) {
            content = .image(image)
        } else {
            return
        }

        if case .text(let text) = content, case .text(let last)? = entries.first?.content, text == last { return }
        entries.insert(ClipboardEntry(content: content, sourceApp: source, copiedAt: Date()), at: 0)
        if entries.count > maxItems { entries.removeLast(entries.count - maxItems) }
    }

    func copy(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch entry.content {
        case .text(let text):  pasteboard.setString(text, forType: .string)
        case .image(let img):  pasteboard.writeObjects([img])
        case .files(let urls): pasteboard.writeObjects(urls as [NSURL])
        }
        lastChange = pasteboard.changeCount
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
    }

    func remove(_ entry: ClipboardEntry) { entries.removeAll { $0.id == entry.id } }
    func clear() { entries.removeAll() }
}

// MARK: - Timer

/// Timer e cronometro. Il tempo si calcola dalle date: niente tick da tenere in vita.
@MainActor
final class TimerStore: ObservableObject {
    enum Mode: Equatable {
        case idle
        case running(endsAt: Date, total: TimeInterval)
        case paused(remaining: TimeInterval, total: TimeInterval)
        case stopwatch(startedAt: Date, accumulated: TimeInterval)
        case stopwatchPaused(accumulated: TimeInterval)
    }

    @Published private(set) var mode: Mode = .idle
    @Published var label = ""

    var onFinish: (() -> Void)?

    private var finishWork: DispatchWorkItem?

    var isActive: Bool { mode != .idle }

    func start(minutes: Double, label: String = "") {
        let total = minutes * 60
        self.label = label
        run(remaining: total, total: total)
    }

    private func run(remaining: TimeInterval, total: TimeInterval) {
        mode = .running(endsAt: Date().addingTimeInterval(remaining), total: total)
        finishWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.finish() }
        }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
    }

    func pause() {
        finishWork?.cancel()
        switch mode {
        case .running(let endsAt, let total):
            mode = .paused(remaining: max(0, endsAt.timeIntervalSinceNow), total: total)
        case .stopwatch(let startedAt, let accumulated):
            mode = .stopwatchPaused(accumulated: accumulated + Date().timeIntervalSince(startedAt))
        default:
            break
        }
    }

    func resume() {
        switch mode {
        case .paused(let remaining, let total):
            run(remaining: remaining, total: total)
        case .stopwatchPaused(let accumulated):
            mode = .stopwatch(startedAt: Date(), accumulated: accumulated)
        default:
            break
        }
    }

    func startStopwatch() {
        finishWork?.cancel()
        mode = .stopwatch(startedAt: Date(), accumulated: 0)
    }

    func reset() {
        finishWork?.cancel()
        mode = .idle
        label = ""
    }

    private func finish() {
        mode = .idle
        onFinish?()
    }

    /// Secondi da mostrare: rimanenti per il timer, trascorsi per il cronometro.
    func displaySeconds(at date: Date = Date()) -> TimeInterval {
        switch mode {
        case .idle:                                  0
        case .running(let endsAt, _):                max(0, endsAt.timeIntervalSince(date))
        case .paused(let remaining, _):              remaining
        case .stopwatch(let startedAt, let accumulated): accumulated + date.timeIntervalSince(startedAt)
        case .stopwatchPaused(let accumulated):      accumulated
        }
    }

    /// Frazione di timer ancora da trascorrere; `nil` per il cronometro.
    func fraction(at date: Date = Date()) -> Double? {
        switch mode {
        case .running(let endsAt, let total):
            total > 0 ? max(0, endsAt.timeIntervalSince(date)) / total : 0
        case .paused(let remaining, let total):
            total > 0 ? remaining / total : 0
        default:
            nil
        }
    }

    var isRunning: Bool {
        switch mode {
        case .running, .stopwatch: true
        default: false
        }
    }
}

// MARK: - Note

/// Un foglio di appunti veloce, salvato in `~/.config/powered-notch/note.md`.
@MainActor
final class NotesStore: ObservableObject {
    @Published var text: String {
        didSet { scheduleSave() }
    }

    private var saveWork: DispatchWorkItem?
    private let persists: Bool

    init(persists: Bool = true, initial: String? = nil) {
        self.persists = persists
        text = initial ?? (persists ? (try? String(contentsOf: AppPaths.notesFile, encoding: .utf8)) : nil) ?? ""
    }

    private func scheduleSave() {
        guard persists else { return }
        saveWork?.cancel()
        let snapshot = text
        let work = DispatchWorkItem {
            try? FileManager.default.createDirectory(at: AppPaths.configDirectory, withIntermediateDirectories: true)
            try? snapshot.write(to: AppPaths.notesFile, atomically: true, encoding: .utf8)
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

// MARK: - Widget da script

/// Ciò che un comando può stampare per riempire un widget.
struct CustomWidgetOutput: Decodable, Equatable {
    struct Row: Decodable, Equatable, Identifiable {
        var title: String
        var value: String?
        var symbol: String?
        var tint: String?
        var id: String { title + (value ?? "") }
    }

    var text: String?
    var subtitle: String?
    var symbol: String?
    var tint: String?
    var progress: Double?
    var rows: [Row]?
    var url: String?
    /// Testo per la notch chiusa; se manca si usa `text`.
    var compact: String?
    /// A `false` l'elemento sparisce dalla notch chiusa.
    var active: Bool?
}

/// Esegue i comandi dei widget personalizzati, ognuno con il suo ritmo.
@MainActor
final class CustomWidgetStore: ObservableObject {
    @Published private(set) var outputs: [String: CustomWidgetOutput] = [:]
    @Published private(set) var errors: [String: String] = [:]

    private var configs: [CustomWidgetConfig] = []
    private var lastRun: [String: Date] = [:]
    private var running: Set<String> = []
    private var timer: Timer?
    private var neededIDs: Set<String> = []

    func apply(configs newConfigs: [CustomWidgetConfig], needed: Set<String>) {
        let changed = newConfigs != configs
        configs = newConfigs
        neededIDs = needed
        if changed { lastRun.removeAll() }

        if needed.isEmpty {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            timer.tolerance = 0.4
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        tick()
    }

    func runNow(_ id: String) {
        guard let config = configs.first(where: { $0.id == id }) else { return }
        run(config)
    }

    /// Prova un comando senza salvarlo: lo usa la schermata delle impostazioni.
    func test(_ config: CustomWidgetConfig) { run(config) }

    func seedForPreview(_ id: String, output: CustomWidgetOutput) { outputs[id] = output }

    private func tick() {
        let now = Date()
        for config in configs where neededIDs.contains(config.id) {
            let last = lastRun[config.id] ?? .distantPast
            if now.timeIntervalSince(last) >= max(1, config.refreshSeconds) { run(config) }
        }
    }

    private func run(_ config: CustomWidgetConfig) {
        guard !running.contains(config.id) else { return }
        running.insert(config.id)
        lastRun[config.id] = Date()
        let command = config.command
        let id = config.id

        Task.detached(priority: .utility) { [weak self] in
            let result = Self.execute(command)
            await MainActor.run {
                guard let self else { return }
                self.running.remove(id)
                switch result {
                case .success(let output):
                    if self.outputs[id] != output { self.outputs[id] = output }
                    self.errors[id] = nil
                case .failure(let error):
                    self.errors[id] = error.message
                }
            }
        }
    }

    private struct RunError: Error { var message: String }

    private nonisolated static func execute(_ command: String) -> Result<CustomWidgetOutput, RunError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", command]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            return .failure(RunError(message: error.localizedDescription))
        }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .failure(RunError(message: message.isEmpty ? "uscita con codice \(process.terminationStatus)" : String(message.prefix(160))))
        }
        return .success(parse(data))
    }

    /// JSON se è JSON, altrimenti testo semplice: prima riga il valore, le altre sotto.
    nonisolated static func parse(_ data: Data) -> CustomWidgetOutput {
        if let decoded = try? JSONDecoder().decode(CustomWidgetOutput.self, from: data) { return decoded }
        let text = String(data: data, encoding: .utf8) ?? ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        var output = CustomWidgetOutput()
        output.text = lines.first
        if lines.count == 2 {
            output.subtitle = lines[1]
        } else if lines.count > 2 {
            output.rows = lines.dropFirst().map { CustomWidgetOutput.Row(title: $0) }
        }
        return output
    }
}
