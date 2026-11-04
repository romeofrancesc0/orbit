import AppKit
import Combine
import SwiftUI

/// Il brano o il video in riproduzione, da qualunque app arrivi.
struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var elapsed: TimeInterval
    var rate: Double
    var timestamp: Date
    var isPlaying: Bool
    var bundleID: String?
    var parentBundleID: String?
    var appName: String?
    var artworkID: String?
    var shuffle: Int
    var repeatMode: Int

    /// Il sistema dice dov'era il brano in un certo istante: da lì si calcola il resto.
    func currentElapsed(at date: Date = Date()) -> TimeInterval {
        guard isPlaying, rate > 0 else { return elapsed }
        let position = elapsed + date.timeIntervalSince(timestamp) * rate
        return duration > 0 ? min(position, duration) : position
    }

    /// Per un video in Safari il "client" è WebKit: l'app che conta è il genitore.
    var sourceBundleID: String? { parentBundleID ?? bundleID }

    var trackKey: String { "\(title)|\(artist)|\(album)" }
}

/// Legge Now Playing dal ponte e invia i comandi a MediaRemote.
@MainActor
final class MediaService: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var artworkColor: NSColor?
    /// Vero mentre vale la pena mostrarla nelle ali: in riproduzione o appena messa in pausa.
    @Published private(set) var isActive = false
    /// L'avvio del ponte è fallito: serve a spiegarlo nelle impostazioni.
    @Published private(set) var bridgeError: String?

    /// Chiamata quando cambia brano (non a ogni aggiornamento della posizione).
    var onTrackChange: ((NowPlaying) -> Void)?

    var pausedLinger: TimeInterval = 12
    /// Copertina e visualizzatore solo per le app di musica.
    var restrictToMusicApps = true {
        didSet { if restrictToMusicApps != oldValue { updateActivity() } }
    }

    /// App fatte per ascoltare: ciò che suona in un browser è quasi sempre un video.
    static let musicApps: Set<String> = [
        "com.apple.Music", "com.apple.iTunes", "com.spotify.client", "com.apple.podcasts",
        "com.tidal.desktop", "com.deezer.deezer-desktop", "com.amazon.music", "com.coppertino.Vox",
        "com.swinsian.Swinsian", "tv.plex.plexamp", "com.audirvana.Audirvana", "io.github.mpv.Doppler",
        "com.apple.Books", "audio.pulsar", "com.yamahamusic.Doppler"
    ]

    static func isMusicApp(_ bundleID: String?) -> Bool {
        bundleID.map(musicApps.contains) ?? false
    }

    func qualifiesForNotch(_ track: NowPlaying) -> Bool {
        !restrictToMusicApps || Self.isMusicApp(track.sourceBundleID)
    }

    private let bridge = MediaBridgeProcess()
    private let commands = MediaRemoteCommands()
    private var lingerWork: DispatchWorkItem?
    private var started = false
    private var trackKey: String?
    private var optimisticUntil: Date = .distantPast
    private var isPreview = false

    init() {
        bridge.onMessage = { [weak self] message in
            Task { @MainActor in self?.handle(message) }
        }
        bridge.onFailure = { [weak self] reason in
            Task { @MainActor in self?.bridgeError = reason }
        }
    }

    func start() {
        guard !started, !isPreview else { return }
        started = true
        bridge.start()
    }

    func stop() {
        guard started else { return }
        started = false
        bridge.stop()
    }

    // MARK: - Stato dal ponte

    private func handle(_ message: [String: Any]) {
        bridgeError = nil
        let hasTrack = (message["title"] as? String)?.isEmpty == false

        guard hasTrack else {
            nowPlaying = nil
            trackKey = nil
            artwork = nil
            artworkColor = nil
            updateActivity()
            return
        }

        let playing = (message["playing"] as? Bool) ?? false
        let rate = (message["rate"] as? Double) ?? (playing ? 1 : 0)
        var state = NowPlaying(
            title: message["title"] as? String ?? "",
            artist: message["artist"] as? String ?? "",
            album: message["album"] as? String ?? "",
            duration: message["duration"] as? Double ?? 0,
            elapsed: message["elapsed"] as? Double ?? 0,
            rate: rate,
            timestamp: (message["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date(),
            isPlaying: playing,
            bundleID: message["bundle"] as? String,
            parentBundleID: message["parent"] as? String,
            appName: message["name"] as? String,
            artworkID: message["artworkID"] as? String,
            shuffle: message["shuffle"] as? Int ?? 0,
            repeatMode: message["repeat"] as? Int ?? 0
        )

        // Subito dopo un comando il sistema può rispondere ancora col vecchio stato.
        if Date() < optimisticUntil, let current = nowPlaying {
            state.isPlaying = current.isPlaying
        }

        let isNewTrack = state.trackKey != trackKey
        let artworkChanged = state.artworkID != nowPlaying?.artworkID
        if isNewTrack || artworkChanged, message["artwork"] == nil {
            artwork = nil
            artworkColor = nil
        }

        if let encoded = message["artwork"] as? String, let data = Data(base64Encoded: encoded), let image = NSImage(data: data) {
            artwork = image
            artworkColor = ArtworkColor.extract(from: image)
        }

        if isNewTrack {
            let hadTrack = trackKey != nil
            trackKey = state.trackKey
            nowPlaying = state
            if hadTrack || state.isPlaying { onTrackChange?(state) }
        } else {
            nowPlaying = state
        }
        updateActivity()
    }

    private func updateActivity() {
        lingerWork?.cancel()
        guard let nowPlaying, qualifiesForNotch(nowPlaying) else {
            isActive = false
            return
        }
        if nowPlaying.isPlaying {
            isActive = true
            return
        }
        // In pausa la copertina resta qualche secondo: un attimo di stop non deve far ballare la notch.
        guard isActive else { return }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.isActive = false }
        }
        lingerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + pausedLinger, execute: work)
    }

    // MARK: - Comandi

    func togglePlayPause() {
        commands.send(.togglePlayPause)
        if var state = nowPlaying {
            // Il controllo risponde subito: la conferma del sistema arriva dopo.
            state.elapsed = state.currentElapsed()
            state.timestamp = Date()
            state.isPlaying.toggle()
            nowPlaying = state
            optimisticUntil = Date().addingTimeInterval(0.6)
            updateActivity()
        }
    }

    func next() { commands.send(.next) }
    func previous() { commands.send(.previous) }

    func seek(to position: TimeInterval) {
        commands.seek(to: position)
        if var state = nowPlaying {
            state.elapsed = position
            state.timestamp = Date()
            nowPlaying = state
        }
    }

    func toggleShuffle() {
        guard var state = nowPlaying else { return }
        // Valori di MediaRemote: 1 spento, 3 tutti.
        let enabled = state.shuffle > 1
        commands.setShuffle(enabled ? 1 : 3)
        state.shuffle = enabled ? 1 : 3
        nowPlaying = state
    }

    func cycleRepeat() {
        guard var state = nowPlaying else { return }
        // Valori di MediaRemote: 1 spento, 2 una, 3 tutti.
        let next: Int
        switch state.repeatMode {
        case 3:  next = 2
        case 2:  next = 1
        default: next = 3
        }
        commands.setRepeat(next)
        state.repeatMode = next
        nowPlaying = state
    }

    func activateSource() {
        guard let bundle = nowPlaying?.sourceBundleID else { return }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.open(url)
        }
    }

    var sourceIcon: NSImage? {
        guard let bundle = nowPlaying?.sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - Anteprima

    func seedForPreview(_ state: NowPlaying, artwork image: NSImage?) {
        isPreview = true
        nowPlaying = state
        trackKey = state.trackKey
        artwork = image
        artworkColor = image.flatMap(ArtworkColor.extract)
        isActive = true
    }
}

// MARK: - Comandi a MediaRemote

/// I comandi non hanno i limiti della lettura: si inviano direttamente dall'app.
final class MediaRemoteCommands {
    enum Command: Int32 {
        case play = 0, pause = 1, togglePlayPause = 2, next = 4, previous = 5
    }

    private typealias SendFn = @convention(c) (Int32, CFDictionary?) -> Bool
    private typealias SeekFn = @convention(c) (Double) -> Void
    private typealias ModeFn = @convention(c) (Int) -> Void

    private let sendFn: SendFn?
    private let seekFn: SeekFn?
    private let shuffleFn: ModeFn?
    private let repeatFn: ModeFn?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        sendFn = symbol("MRMediaRemoteSendCommand", as: SendFn.self)
        seekFn = symbol("MRMediaRemoteSetElapsedTime", as: SeekFn.self)
        shuffleFn = symbol("MRMediaRemoteSetShuffleMode", as: ModeFn.self)
        repeatFn = symbol("MRMediaRemoteSetRepeatMode", as: ModeFn.self)
    }

    func send(_ command: Command) { _ = sendFn?(command.rawValue, nil) }
    func seek(to position: TimeInterval) { seekFn?(position) }
    func setShuffle(_ mode: Int) { shuffleFn?(mode) }
    func setRepeat(_ mode: Int) { repeatFn?(mode) }
}

// MARK: - Ponte

/// Fa girare il ponte in `/usr/bin/perl` e ne legge le righe JSON.
final class MediaBridgeProcess: @unchecked Sendable {
    var onMessage: (([String: Any]) -> Void)?
    var onFailure: ((String) -> Void)?

    private var process: Process?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "orbit.media-bridge")
    private var shouldRun = false
    private var failures = 0

    private static let loader = """
    use DynaLoader;
    my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
    my $sym = DynaLoader::dl_find_symbol($lib, "orbit_media_stream") or die "simbolo mancante";
    my $fn = DynaLoader::dl_install_xsub("main::stream", $sym);
    &$fn();
    """

    private static var libraryPath: String? {
        let name = "libOrbitMediaBridge.dylib"
        let candidates = [
            Bundle.main.privateFrameworksURL?.appendingPathComponent(name),
            Bundle.main.resourceURL?.appendingPathComponent(name)
        ]
        return candidates.compactMap { $0?.path }.first { FileManager.default.fileExists(atPath: $0) }
    }

    func start() {
        queue.async {
            self.shouldRun = true
            self.failures = 0
            self.launch()
        }
    }

    func stop() {
        queue.async {
            self.shouldRun = false
            self.process?.terminate()
            self.process = nil
        }
    }

    private func launch() {
        guard shouldRun, process == nil else { return }
        guard let library = Self.libraryPath else {
            onFailure?(tr("Libreria del ponte non trovata nel bundle"))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.loader, library]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.queue.async { self?.consume(data) }
        }

        process.terminationHandler = { [weak self] finished in
            self?.queue.async {
                guard let self else { return }
                self.process = nil
                guard self.shouldRun else { return }
                self.failures += 1
                if self.failures > 5 {
                    self.onFailure?(tr("Il ponte verso Now Playing si chiude di continuo (codice %lld)", Int(finished.terminationStatus)))
                    return
                }
                self.queue.asyncAfter(deadline: .now() + 2) { self.launch() }
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            onFailure?(tr("Impossibile avviare il ponte: %@", error.localizedDescription))
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else { continue }
            // Una riga arrivata vuol dire che il ponte è vivo.
            failures = 0
            onMessage?(object)
        }
    }
}

// MARK: - Colore della copertina

enum ArtworkColor {
    /// Il colore che si ricorda di una copertina: non la media, che verrebbe grigia,
    /// ma la media pesata sulla saturazione, schiarita quel che basta per stare su un fondo nero.
    static func extract(from image: NSImage) -> NSColor? {
        let side = 24
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        var red = 0.0, green = 0.0, blue = 0.0, total = 0.0
        for x in 0..<side {
            for y in 0..<side {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let saturation = Double(color.saturationComponent)
                let brightness = Double(color.brightnessComponent)
                let weight = 0.04 + saturation * saturation * brightness
                red += Double(color.redComponent) * weight
                green += Double(color.greenComponent) * weight
                blue += Double(color.blueComponent) * weight
                total += weight
            }
        }
        guard total > 0 else { return nil }

        let mixed = NSColor(deviceRed: red / total, green: green / total, blue: blue / total, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        mixed.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            deviceHue: hue,
            saturation: min(saturation * 1.15, 0.85),
            brightness: max(brightness, 0.78),
            alpha: 1
        )
    }
}
