import AppKit
import Combine
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Un oggetto parcheggiato nello scaffale.
struct ShelfItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case file, text, link }

    var id = UUID().uuidString
    var kind: Kind
    var name: String
    /// Percorso del file, testo o URL a seconda del tipo.
    var value: String
    /// Segnalibro: ritrova il file anche se nel frattempo è stato spostato.
    var bookmark: Data?
    var addedAt = Date()
    /// Il file è una copia che appartiene allo scaffale, e si può cancellare con lui.
    var ownedCopy = false

    var fileURL: URL? {
        guard kind == .file else { return nil }
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale) {
                return url
            }
        }
        return URL(fileURLWithPath: value)
    }

    var linkURL: URL? { kind == .link ? URL(string: value) : nil }
}

/// Lo scaffale: raccoglie file, testi e link trascinati sulla notch e li
/// conserva anche dopo un riavvio.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var thumbnails: [String: NSImage] = [:]

    var copyFiles = false
    private let persists: Bool

    init(persists: Bool = true) {
        self.persists = persists
        if persists { load() }
    }

    func seedForPreview(_ preview: [ShelfItem]) { items = preview }

    // MARK: - Aggiunta

    /// Tipi accettati dalla zona di rilascio.
    static let dropTypes: [UTType] = [.fileURL, .url, .image, .utf8PlainText, .plainText, .text]

    func add(providers: [NSItemProvider]) {
        for provider in providers { add(provider: provider) }
    }

    private func add(provider: NSItemProvider) {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url else { return }
                Task { @MainActor in self?.add(url: url) }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url else { return }
                Task { @MainActor in self?.add(url: url) }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                guard let data else { return }
                Task { @MainActor in self?.add(imageData: data) }
            }
        } else if provider.canLoadObject(ofClass: String.self) {
            _ = provider.loadObject(ofClass: String.self) { [weak self] text, _ in
                guard let text, !text.isEmpty else { return }
                Task { @MainActor in self?.add(text: text) }
            }
        }
    }

    func add(url: URL) {
        if url.isFileURL {
            addFile(url)
        } else {
            let item = ShelfItem(kind: .link, name: url.host ?? url.absoluteString, value: url.absoluteString)
            insert(item)
        }
    }

    private func addFile(_ original: URL) {
        var url = original
        var owned = false
        if copyFiles, let copy = copyIntoStorage(original) {
            url = copy
            owned = true
        }
        guard !items.contains(where: { $0.kind == .file && $0.value == url.path }) else { return }
        let bookmark = try? url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        insert(ShelfItem(kind: .file, name: url.lastPathComponent, value: url.path, bookmark: bookmark, ownedCopy: owned))
    }

    func add(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Un testo che è solo un link vale più come link.
        if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true, !trimmed.contains(" ") {
            add(url: url)
            return
        }
        let name = String(trimmed.prefix(60)).replacingOccurrences(of: "\n", with: " ")
        insert(ShelfItem(kind: .text, name: name, value: trimmed))
    }

    private func add(imageData: Data) {
        let directory = AppPaths.shelfStorage
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'alle' HH.mm.ss"
        let ext = NSBitmapImageRep(data: imageData)?.representation(using: .png, properties: [:]) != nil ? "png" : "img"
        let url = directory.appendingPathComponent("Immagine \(formatter.string(from: Date())).\(ext)")
        let payload = NSBitmapImageRep(data: imageData)?.representation(using: .png, properties: [:]) ?? imageData
        guard (try? payload.write(to: url)) != nil else { return }
        insert(ShelfItem(kind: .file, name: url.lastPathComponent, value: url.path, ownedCopy: true))
    }

    private func copyIntoStorage(_ url: URL) -> URL? {
        let fm = FileManager.default
        let directory = AppPaths.shelfStorage.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(url.lastPathComponent)
        do {
            try fm.copyItem(at: url, to: target)
            return target
        } catch {
            return nil
        }
    }

    private func insert(_ item: ShelfItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            items.insert(item, at: 0)
        }
        save()
        loadThumbnail(for: item)
    }

    // MARK: - Rimozione

    func remove(_ item: ShelfItem) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            items.removeAll { $0.id == item.id }
        }
        thumbnails[item.id] = nil
        discardOwnedCopy(item)
        save()
    }

    func clear() {
        let removed = items
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { items.removeAll() }
        thumbnails.removeAll()
        removed.forEach(discardOwnedCopy)
        save()
    }

    private func discardOwnedCopy(_ item: ShelfItem) {
        guard item.ownedCopy, let url = item.fileURL, url.path.hasPrefix(AppPaths.shelfStorage.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Azioni

    func open(_ item: ShelfItem) {
        switch item.kind {
        case .file:
            if let url = item.fileURL { NSWorkspace.shared.open(url) }
        case .link:
            if let url = item.linkURL { NSWorkspace.shared.open(url) }
        case .text:
            SessionActions.copy(item.value)
        }
    }

    func reveal(_ item: ShelfItem) {
        guard let url = item.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copy(_ item: ShelfItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let url = item.fileURL {
            pasteboard.writeObjects([url as NSURL])
        } else {
            pasteboard.setString(item.value, forType: .string)
        }
    }

    /// Cosa passare a chi condivide: l'URL del file o del link, altrimenti il testo.
    func shareable(_ item: ShelfItem) -> Any {
        if let url = item.fileURL { return url }
        if let url = item.linkURL { return url }
        return item.value
    }

    func airDrop(_ items: [ShelfItem]) {
        let payload = items.map(shareable)
        guard !payload.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: payload)
    }

    /// Ciò che esce dallo scaffale quando lo si trascina via.
    func dragProvider(for item: ShelfItem) -> NSItemProvider {
        if let url = item.fileURL, let provider = NSItemProvider(contentsOf: url) { return provider }
        if let url = item.linkURL { return NSItemProvider(object: url as NSURL) }
        return NSItemProvider(object: item.value as NSString)
    }

    // MARK: - Miniature

    func loadThumbnail(for item: ShelfItem) {
        guard thumbnails[item.id] == nil, let url = item.fileURL else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 96, height: 96),
            scale: scale,
            representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let image = representation?.nsImage ?? NSWorkspace.shared.icon(forFile: url.path)
            let id = item.id
            Task { @MainActor in self?.thumbnails[id] = image }
        }
    }

    // MARK: - Persistenza

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.shelfFile),
              let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data)
        else { return }
        // Un file nel frattempo cancellato non ha più senso sullo scaffale.
        items = decoded.filter { item in
            guard let url = item.fileURL else { return true }
            return FileManager.default.fileExists(atPath: url.path)
        }
        items.forEach(loadThumbnail)
    }

    private func save() {
        guard persists else { return }
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? FileManager.default.createDirectory(at: AppPaths.configDirectory, withIntermediateDirectories: true)
        try? data.write(to: AppPaths.shelfFile, options: .atomic)
    }
}
