import AppKit
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

/// Lo scaffale: una fila di oggetti da trascinare via, condividere o aprire.
struct ShelfWidget: View {
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var actions: NotchActions
    @Environment(\.notchTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            AirDropTile()
            if shelf.items.isEmpty {
                dropHint
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(shelf.items) { item in
                            ShelfItemTile(item: item)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                VStack {
                    NotchIconButton(symbol: "trash", size: 24, iconSize: 10.5, help: "Svuota lo scaffale") {
                        shelf.clear()
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropHint: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 5]))
            .foregroundStyle(theme.tertiary)
            .overlay {
                VStack(spacing: 5) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(theme.secondary)
                    Text("Trascina qui file, link o testo")
                        .font(theme.font(11, .medium))
                        .foregroundStyle(theme.secondary)
                    Text("Restano a portata di mano finché non li togli")
                        .font(theme.font(9.5))
                        .foregroundStyle(theme.tertiary)
                }
            }
    }
}

/// Lascia cadere qui un file per inviarlo subito con AirDrop.
private struct AirDropTile: View {
    @EnvironmentObject private var shelf: ShelfStore
    @Environment(\.notchTheme) private var theme
    @State private var targeted = false
    @State private var hovering = false

    var body: some View {
        Button {
            shelf.airDrop(shelf.items)
        } label: {
            VStack(spacing: 5) {
                if let icon = NSSharingService(named: .sendViaAirDrop)?.image {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(targeted ? Color(hex: 0x4FC3F7) : theme.secondary)
                }
                Text("AirDrop")
                    .font(theme.font(9.5, .medium))
                    .foregroundStyle(theme.secondary)
            }
            .frame(width: 66)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(targeted ? Color(hex: 0x4FC3F7).opacity(0.18) : (hovering ? theme.hoverFill : theme.chipFill))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(NotchPressStyle())
        .help(shelf.items.isEmpty ? "Trascina qui un file per inviarlo" : "Invia tutto lo scaffale")
        .onHover { hovering = $0 }
        .onDrop(of: [.fileURL, .url], isTargeted: $targeted) { providers in
            let collector = URLCollector()
            let group = DispatchGroup()
            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { collector.append(url) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
                NSApp.activate(ignoringOtherApps: true)
                service.perform(withItems: collector.urls)
            }
            return true
        }
    }
}

/// Raccoglie gli URL che arrivano da thread diversi durante un rilascio.
private final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(url)
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private struct ShelfItemTile: View {
    let item: ShelfItem

    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var actions: NotchActions
    @Environment(\.notchTheme) private var theme
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            preview
                .frame(width: 58, height: 58)
                .scaleEffect(hovering ? 1.05 : 1)
            Text(item.name)
                .font(theme.font(9.5))
                .foregroundStyle(theme.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 76, height: 26, alignment: .top)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? theme.hoverFill : .clear)
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button {
                    shelf.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(white: 0.3))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onTapGesture(count: 2) {
            shelf.open(item)
            actions.close()
        }
        .onDrag {
            let provider = shelf.dragProvider(for: item)
            if settings.config.shelf.removeAfterDragOut {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { shelf.remove(item) }
            }
            return provider
        }
        .contextMenu { menu }
        .help(item.name)
        .onAppear { shelf.loadThumbnail(for: item) }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .file:
            if let image = shelf.thumbnails[item.id] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "doc.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(theme.secondary)
            }
        case .link:
            symbolTile("link", tint: Color(hex: 0x4FC3F7))
        case .text:
            symbolTile("text.alignleft", tint: Color(hex: 0xFFC145))
        }
    }

    private func symbolTile(_ symbol: String, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(tint.opacity(0.16))
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(tint)
            }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Apri") {
            shelf.open(item)
            actions.close()
        }
        if let url = item.fileURL {
            Button("Anteprima") { QuickLook.shared.show(url) }
            Button("Mostra nel Finder") {
                shelf.reveal(item)
                actions.close()
            }
        }
        Button("Copia") { shelf.copy(item) }
        Divider()
        Button("Invia con AirDrop") { shelf.airDrop([item]) }
        let services = NSSharingService.sharingServices(forItems: [shelf.shareable(item)])
        if !services.isEmpty {
            Menu("Condividi") {
                ForEach(services, id: \.title) { service in
                    Button(service.title) {
                        NSApp.activate(ignoringOtherApps: true)
                        service.perform(withItems: [shelf.shareable(item)])
                    }
                }
            }
        }
        Divider()
        Button("Togli dallo scaffale") { shelf.remove(item) }
    }
}

// MARK: - Quick Look

@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLook()
    private var url: URL?

    func show(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .mainMenu + 4
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { url as NSURL? }
    }
}
