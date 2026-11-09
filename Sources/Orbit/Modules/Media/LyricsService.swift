import CryptoKit
import Foundation
import os

/// Una riga del testo: quando comincia e cosa dice. Una riga vuota è una pausa strumentale.
struct LyricLine: Equatable, Identifiable {
    var id: Int
    var time: TimeInterval
    var text: String

    var isInterlude: Bool { text.isEmpty }
}

/// Il testo di un brano: a tempo (una riga per istante) o solo da leggere.
struct Lyrics: Equatable {
    var lines: [LyricLine]
    var isSynced: Bool

    /// Una riga si accende un attimo prima del suo istante: la voce sembra seguirla, non inseguirla.
    static let lead: TimeInterval = 0.25

    /// L'ultima riga cominciata a questo punto del brano, o -1 prima della prima.
    func index(at position: TimeInterval) -> Int {
        guard isSynced, !lines.isEmpty else { return -1 }
        let target = position + Self.lead
        var low = 0, high = lines.count - 1, found = -1
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= target {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// Legge il formato LRC: `[mm:ss.xx] testo`, anche con più istanti sulla stessa riga.
    static func parseLRC(_ source: String) -> Lyrics? {
        let stamp = #/\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]/#
        var offset: TimeInterval = 0
        var timed: [(TimeInterval, String)] = []

        for raw in source.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if let match = line.firstMatch(of: #/^\[offset:\s*([+-]?\d+)\]/#) {
                // L'offset di LRC è in millisecondi, e positivo vuol dire "prima".
                offset = -(Double(match.1) ?? 0) / 1000
                continue
            }
            let matches = line.matches(of: stamp)
            guard let last = matches.last else { continue }
            // L'LRC "esteso" segna anche le singole parole (<00:12.34>): qui conta la riga.
            let text = String(line[last.range.upperBound...])
                .replacing(#/<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>/#, with: "")
                .trimmingCharacters(in: .whitespaces)
            // I crediti in testa ("作词 : …", "Composer: …") non sono parole da cantare.
            if isCredit(text) { continue }
            for match in matches {
                let minutes = Double(match.1) ?? 0
                let seconds = Double(match.2.replacingOccurrences(of: ":", with: ".")) ?? 0
                timed.append((minutes * 60 + seconds + offset, text))
            }
        }
        guard !timed.isEmpty else { return nil }

        timed.sort { $0.0 < $1.0 }
        var lines: [LyricLine] = []
        for (time, text) in timed {
            // Due pause di fila, o una pausa in fondo, non dicono nulla.
            if text.isEmpty, lines.last?.isInterlude ?? true { continue }
            lines.append(LyricLine(id: lines.count, time: max(0, time), text: text))
        }
        while lines.last?.isInterlude == true { lines.removeLast() }
        guard lines.contains(where: { !$0.isInterlude }) else { return nil }
        // Un'introduzione lunga ha i suoi tre punti, come le pause in mezzo al brano.
        if let first = lines.first, !first.isInterlude, first.time > 3 {
            lines.insert(LyricLine(id: 0, time: 0, text: ""), at: 0)
            for index in lines.indices { lines[index].id = index }
        }
        return Lyrics(lines: lines, isSynced: true)
    }

    private static let creditWords = ["lyricist", "lyrics by", "composer", "composed by", "written by", "producer", "produced by", "arranger", "arranged by", "mixing", "mastering", "mixed by", "mastered by"]

    static func isCredit(_ text: String) -> Bool {
        guard let colon = text.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return false }
        let label = text[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        guard !label.isEmpty, label.count <= 16 else { return false }
        if label.unicodeScalars.contains(where: { $0.properties.isIdeographic }) { return true }
        return creditWords.contains(label)
    }

    static func plain(_ source: String) -> Lyrics? {
        let texts = source.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard texts.contains(where: { !$0.isEmpty }) else { return nil }
        return Lyrics(lines: texts.enumerated().map { LyricLine(id: $0.offset, time: 0, text: $0.element) }, isSynced: false)
    }
}

/// Cerca il testo del brano in riproduzione su LRCLIB, un archivio libero e senza chiavi.
/// Ogni risposta si tiene sul disco: lo stesso brano non si chiede due volte.
@MainActor
final class LyricsService: ObservableObject {
    enum Status: Equatable {
        case idle
        case loading
        case loaded(Lyrics)
        case instrumental
        case unavailable
    }

    @Published private(set) var status: Status = .idle
    /// Il brano a cui si riferisce `status`.
    @Published private(set) var trackKey: String?

    var lyrics: Lyrics? {
        if case .loaded(let lyrics) = status { return lyrics }
        return nil
    }

    private static let log = Logger(subsystem: "com.francescoromeo.powerednotch", category: "testi")
    private var task: Task<Void, Never>?
    private var retryWork: DispatchWorkItem?
    private var memory: [String: Status] = [:]
    private var isPreview = false
    /// Dopo un errore di rete si riprova, ma non a raffica.
    private static let retryDelay: TimeInterval = 20

    /// Un brano lo si cerca solo se viene da un'app di musica: il titolo di un video
    /// nel browser non deve finire in una ricerca. `moreSources` aggiunge NetEase quando
    /// LRCLIB non ha il brano.
    func load(for track: NowPlaying?, moreSources: Bool = true) {
        guard !isPreview else { return }
        guard let track, !track.title.isEmpty, MediaService.isMusicApp(track.sourceBundleID) else {
            task?.cancel()
            retryWork?.cancel()
            trackKey = nil
            status = .idle
            return
        }
        let key = Self.cacheKey(track) + (moreSources ? "|+" : "")
        guard key != trackKey else { return }
        task?.cancel()
        retryWork?.cancel()
        trackKey = key

        if let known = memory[key] {
            status = known
            return
        }
        if let cached = LyricsCache.read(key: key) {
            let resolved = cached.status
            memory[key] = resolved
            status = resolved
            return
        }

        status = .loading
        let query = LyricsQuery(track)
        task = Task { [weak self] in
            let result = await LyricsSources.fetch(query, moreSources: moreSources)
            guard !Task.isCancelled, let self, self.trackKey == key else { return }
            switch result {
            case .success(let record):
                LyricsCache.write(record, key: key)
                let resolved = record.status
                self.memory[key] = resolved
                self.status = resolved
                Self.log.info("testo: \(record.source ?? "nessuna fonte", privacy: .public)")
            case .failure(let error):
                // Senza rete non si ricorda nulla: fra poco si riprova, se il brano è ancora questo.
                Self.log.info("testo non scaricato: \(error.localizedDescription, privacy: .public)")
                self.status = .unavailable
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.trackKey == key else { return }
                    self.trackKey = nil
                    self.load(for: track, moreSources: moreSources)
                }
                self.retryWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay, execute: work)
            }
        }
    }

    func seedForPreview(_ lyrics: Lyrics, track: NowPlaying) {
        isPreview = true
        trackKey = Self.cacheKey(track)
        status = .loaded(lyrics)
    }

    /// Per provare i passaggi fra un brano e l'altro: attesa, testo, nessun testo.
    func seedForPreview(_ status: Status, track: NowPlaying) {
        isPreview = true
        trackKey = Self.cacheKey(track)
        self.status = status
    }

    private static func cacheKey(_ track: NowPlaying) -> String {
        "\(track.title.lowercased())|\(track.artist.lowercased())|\(Int(track.duration.rounded()))"
    }
}

// MARK: - LRCLIB

private struct LyricsQuery: Sendable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval

    init(_ track: NowPlaying) {
        title = track.title
        artist = track.artist
        album = track.album
        duration = track.duration
    }

    /// "Brano - Remastered 2011", "Brano (feat. Altro)": l'archivio li conosce col titolo nudo.
    var cleanTitle: String {
        var value = title
        for pattern in [#/\s+[-–]\s+.*(remaster|live|version|edit|mix|mono|stereo|deluxe).*$/#.ignoresCase(),
                        #/\s*[(\[](feat\.|ft\.|with |remaster|live|version|edit).*?[)\]]/#.ignoresCase()] {
            value = value.replacing(pattern, with: "")
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    /// Spotify e altri scrivono "Artista, Ospite": per cercare basta il primo.
    var mainArtist: String {
        artist.split(whereSeparator: { $0 == "," || $0 == "&" }).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? artist
    }
}

/// Ciò che si ricorda di un brano: il testo trovato, o il fatto che non c'è.
struct LyricsRecord: Codable {
    var synced: String?
    var plain: String?
    var instrumental: Bool
    var fetchedAt = Date()
    /// Da dove arriva: "lrclib", "netease", o nessuna.
    var source: String?

    var status: LyricsService.Status {
        if let synced, let lyrics = Lyrics.parseLRC(synced) { return .loaded(lyrics) }
        if instrumental { return .instrumental }
        if let plain, let lyrics = Lyrics.plain(plain) { return .loaded(lyrics) }
        return .unavailable
    }
}

/// Le fonti, in ordine: prima LRCLIB, aperto e curato; poi NetEase Cloud Music, che ha
/// molti più brani recenti e meno noti, anche italiani. Si cerca sempre il testo a tempo:
/// quello solo da leggere vale finché nessuna fonte ne ha uno che scorre con la voce.
private enum LyricsSources {
    static func fetch(_ query: LyricsQuery, moreSources: Bool) async -> Result<LyricsRecord, Error> {
        var fallback: LyricsRecord?
        var networkError: Error?

        switch await LRCLib.fetch(query) {
        case .success(let record):
            if record.synced != nil || record.instrumental { return .success(record) }
            if !record.isMissing { fallback = record }
        case .failure(let error):
            networkError = error
        }

        if moreSources {
            do {
                if let record = try await NetEase.fetch(query) {
                    if record.synced != nil { return .success(record) }
                    if fallback == nil { fallback = record }
                }
            } catch {
                // NetEase irraggiungibile: vale ciò che ha detto LRCLIB, che è una risposta vera.
                // Se anche LRCLIB era irraggiungibile, resta il suo errore e fra poco si riprova.
            }
        }

        if let fallback { return .success(fallback) }
        if let networkError { return .failure(networkError) }
        return .success(LyricsRecord(synced: nil, plain: nil, instrumental: false))
    }
}

private enum LRCLib {
    private struct Entry: Decodable {
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?

        var isSynced: Bool {
            guard let syncedLyrics, !syncedLyrics.isEmpty else { return false }
            return Lyrics.parseLRC(syncedLyrics) != nil
        }

        var hasContent: Bool {
            instrumental == true || syncedLyrics?.isEmpty == false || plainLyrics?.isEmpty == false
        }

        var record: LyricsRecord {
            LyricsRecord(synced: syncedLyrics, plain: plainLyrics, instrumental: instrumental ?? false, source: "lrclib")
        }
    }

    private static let base = URL(string: "https://lrclib.net/api/")!

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.httpAdditionalHeaders = ["User-Agent": "Orbit/\(Bundle.main.shortVersion) (https://github.com/romeofrancesc0/orbit)"]
        return URLSession(configuration: configuration)
    }()

    /// Prima la ricerca esatta (titolo, artista, album, durata), poi quella libera.
    /// Un brano che l'archivio non conosce è un risultato valido, non un errore.
    /// La voce esatta può avere solo il testo da leggere mentre un'altra versione dello
    /// stesso brano (un altro album, una riedizione) ce l'ha a tempo: si va avanti finché
    /// se ne trova una, e il testo semplice resta come riserva.
    static func fetch(_ query: LyricsQuery) async -> Result<LyricsRecord, Error> {
        do {
            var fallback: Entry?
            if query.duration > 0, !query.album.isEmpty, let entry = try await get(query), entry.hasContent {
                if entry.isSynced || entry.instrumental == true { return .success(entry.record) }
                fallback = entry
            }
            var tried = Set<String>()
            let attempts = [(query.title, query.artist), (query.cleanTitle, query.mainArtist)]
            for (title, artist) in attempts where tried.insert("\(title)|\(artist)").inserted {
                let entries = try await search(title: title, artist: artist, duration: query.duration)
                if let synced = entries.first(where: \.isSynced) { return .success(synced.record) }
                if fallback == nil { fallback = entries.first { $0.hasContent } }
            }
            return .success(fallback?.record ?? LyricsRecord(synced: nil, plain: nil, instrumental: false))
        } catch {
            return .failure(error)
        }
    }

    private static func get(_ query: LyricsQuery) async throws -> Entry? {
        let url = endpoint("get", [
            "track_name": query.title,
            "artist_name": query.artist,
            "album_name": query.album,
            "duration": String(Int(query.duration.rounded()))
        ])
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    private static func search(title: String, artist: String, duration: TimeInterval) async throws -> [Entry] {
        guard !title.isEmpty else { return [] }
        var items = ["track_name": title]
        if !artist.isEmpty { items["artist_name"] = artist }
        let (data, response) = try await session.data(from: endpoint("search", items))
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }

        // Una versione di durata molto diversa ha il testo fuori tempo: meglio nessuno.
        // Le più vicine per durata vengono prima.
        return entries
            .filter { entry in
                guard duration > 0, let length = entry.duration else { return true }
                return abs(length - duration) <= 4
            }
            .sorted { abs(($0.duration ?? duration) - duration) < abs(($1.duration ?? duration) - duration) }
    }

    private static func endpoint(_ path: String, _ items: [String: String]) -> URL {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }
}

extension LyricsRecord {
    var isMissing: Bool { synced == nil && plain == nil && !instrumental }
}

// MARK: - NetEase

/// L'interfaccia pubblica del sito di NetEase Cloud Music: non chiede chiavi, ma non è
/// documentata. Se un giorno cambia, resta LRCLIB.
private enum NetEase {
    private struct SearchResponse: Decodable {
        struct Result: Decodable { var songs: [Song]? }
        var result: Result?
    }

    private struct Song: Decodable {
        struct Artist: Decodable { var name: String }
        var id: Int
        var name: String
        var artists: [Artist]?
        /// In millisecondi.
        var duration: Double?
    }

    private struct LyricResponse: Decodable {
        struct Part: Decodable { var lyric: String? }
        var lrc: Part?
        var pureMusic: Bool?
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Orbit",
            "Referer": "https://music.163.com/"
        ]
        return URLSession(configuration: configuration)
    }()

    /// Lo stesso brano compare spesso più volte (album, singolo, raccolte), non tutte col testo:
    /// si provano le prime finché una l'ha a tempo.
    static func fetch(_ query: LyricsQuery) async throws -> LyricsRecord? {
        var tried = Set<String>()
        var checked = Set<Int>()
        for title in [query.title, query.cleanTitle] where tried.insert(title).inserted {
            for song in try await search(title: title, query: query).prefix(3) where checked.insert(song.id).inserted {
                if let record = try await lyrics(for: song.id) { return record }
            }
        }
        return nil
    }

    private static func search(title: String, query: LyricsQuery) async throws -> [Song] {
        var components = URLComponents(string: "https://music.163.com/api/search/get")!
        components.queryItems = [
            URLQueryItem(name: "s", value: "\(title) \(query.mainArtist)"),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "10")
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let songs = try? JSONDecoder().decode(SearchResponse.self, from: data).result?.songs
        else { return [] }

        let wantedTitle = normalize(title)
        let wantedArtist = normalize(query.mainArtist)
        // Stesso titolo, stesso artista e, se si sa, la stessa durata: un omonimo o una cover
        // avrebbero il testo sbagliato o fuori tempo.
        return songs.filter { song in
            let name = normalize(song.name)
            let titleMatches = name == wantedTitle || name.hasPrefix(wantedTitle) || wantedTitle.hasPrefix(name)
            let artists = (song.artists ?? []).map { normalize($0.name) }
            let artistMatches = wantedArtist.isEmpty || artists.contains { $0 == wantedArtist || $0.contains(wantedArtist) || wantedArtist.contains($0) }
            let durationMatches = query.duration <= 0 || song.duration.map { abs($0 / 1000 - query.duration) <= 4 } ?? true
            return titleMatches && artistMatches && durationMatches
        }
    }

    private static func lyrics(for id: Int) async throws -> LyricsRecord? {
        var components = URLComponents(string: "https://music.163.com/api/song/lyric")!
        components.queryItems = [URLQueryItem(name: "id", value: String(id)), URLQueryItem(name: "lv", value: "1")]
        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(LyricResponse.self, from: data)
        else { return nil }
        let text = decoded.lrc?.lyric ?? ""
        // "纯音乐，请欣赏": musica senza parole.
        if decoded.pureMusic == true || text.contains("纯音乐") {
            return LyricsRecord(synced: nil, plain: nil, instrumental: true, source: "netease")
        }
        guard Lyrics.parseLRC(text) != nil else { return nil }
        return LyricsRecord(synced: text, plain: nil, instrumental: false, source: "netease")
    }

    /// Minuscole, senza accenti e senza punteggiatura: "CENERE" e "Cenere" sono lo stesso titolo.
    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}

private extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
}

// MARK: - Cache

/// I testi scaricati, in `~/Library/Caches`. Un "non trovato" o un testo senza tempi
/// valgono qualche giorno: gli archivi crescono, e un brano nuovo può comparirci a tempo.
private enum LyricsCache {
    private static let missingLifetime: TimeInterval = 3 * 86_400

    private static var folder: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            // v3: le versioni prima si fermavano al testo semplice anche quando ne esisteva uno a tempo.
            .appendingPathComponent("com.francescoromeo.powerednotch/Lyrics/v3", isDirectory: true)
    }

    private static func file(for key: String) -> URL? {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder?.appendingPathComponent(String(digest.prefix(32)) + ".json")
    }

    static func read(key: String) -> LyricsRecord? {
        guard let url = file(for: key),
              let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(LyricsRecord.self, from: data)
        else { return nil }
        // Anche il testo solo da leggere scade: spesso quello a tempo arriva qualche giorno dopo l'uscita.
        if record.isMissing || record.synced == nil, !record.instrumental,
           Date().timeIntervalSince(record.fetchedAt) > missingLifetime { return nil }
        return record
    }

    static func write(_ record: LyricsRecord, key: String) {
        guard let folder, let url = file(for: key), let data = try? JSONEncoder().encode(record) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
