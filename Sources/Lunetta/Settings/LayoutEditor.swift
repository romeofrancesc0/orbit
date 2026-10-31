import SwiftUI
import UniformTypeIdentifiers

/// L'editor del layout: si costruisce la notch trascinando elementi nelle zone,
/// e l'anteprima mostra subito il risultato vero.
struct LayoutEditorView: View {
    let services: AppServices

    @EnvironmentObject private var settings: SettingsStore
    @State private var selectedPageID: String?
    @State private var selectedWidgetID: String?
    @State private var pinned = false

    private var layout: LayoutConfig { settings.config.layout }
    private var custom: [CustomWidgetConfig] { settings.config.customWidgets }

    private var selectedPage: PageConfig? {
        layout.pages.first { $0.id == selectedPageID } ?? layout.pages.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    SettingsHeader(
                        section: .layout,
                        subtitle: "Decidi cosa compare nella notch. Trascina gli elementi nelle zone: le modifiche valgono subito."
                    )
                    Toggle("Tieni aperta la notch", isOn: $pinned)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help("Lascia aperta la notch vera mentre lavori qui, per vedere le modifiche sullo schermo")
                }

                closedSection
                pagesSection
                startSection
            }
            .padding(24)
        }
        .onChange(of: pinned) { _, value in services.notch.setPreviewPinned(value) }
        .onDisappear {
            if pinned { services.notch.setPreviewPinned(false) }
        }
    }

    // MARK: - Notch chiusa

    private var closedSection: some View {
        EditorCard(title: "Notch chiusa", subtitle: "Ciò che si vede ai lati del ritaglio. Un elemento compare solo quando ha qualcosa da dire.") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 0) {
                    CompactZoneView(
                        items: settings.binding(\.layout.closedLeading),
                        alignment: .trailing,
                        placeholder: "Sinistra"
                    )
                    NotchCutout()
                    CompactZoneView(
                        items: settings.binding(\.layout.closedTrailing),
                        alignment: .leading,
                        placeholder: "Destra"
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.9)))

                CompactPalette(
                    used: Set(layout.closedLeading + layout.closedTrailing),
                    custom: custom,
                    destinations: [
                        ("Aggiungi a sinistra", settings.binding(\.layout.closedLeading)),
                        ("Aggiungi a destra", settings.binding(\.layout.closedTrailing))
                    ]
                )

                Toggle("Ali della stessa larghezza", isOn: settings.binding(\.layout.symmetricWings))
                    .help("La notch resta perfettamente centrata anche con contenuti diversi ai due lati")
            }
        }
    }

    // MARK: - Pagine

    private var pagesSection: some View {
        EditorCard(title: "Notch aperta", subtitle: "Le pagine e i widget che le compongono. Trascina per riordinare, tira il bordo fra due widget per ridimensionare.") {
            VStack(alignment: .leading, spacing: 14) {
                PageTabsEditor(selectedPageID: $selectedPageID)

                if let page = selectedPage {
                    PageCanvas(page: page, selectedWidgetID: $selectedWidgetID)
                    pageInspector(page)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Widget disponibili")
                        .font(.subheadline.weight(.semibold))
                    WidgetPalette(custom: custom) { kind in
                        addWidget(kind)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Testata")
                        .font(.subheadline.weight(.semibold))
                    Text("Le piccole informazioni in alto a destra quando la notch è aperta.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    CompactZoneView(
                        items: settings.binding(\.layout.headerTrailing),
                        alignment: .leading,
                        placeholder: "Trascina qui un elemento",
                        isHeader: true
                    )
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.9)))
                    CompactPalette(
                        used: Set(layout.headerTrailing),
                        custom: custom,
                        destinations: [("Aggiungi alla testata", settings.binding(\.layout.headerTrailing))]
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func pageInspector(_ page: PageConfig) -> some View {
        let index = layout.pages.firstIndex { $0.id == page.id } ?? 0

        if let widgetID = selectedWidgetID, let widget = page.widgets.first(where: { $0.id == widgetID }) {
            WidgetInspector(pageIndex: index, widget: widget) {
                selectedWidgetID = nil
            }
        } else {
            HStack(spacing: 12) {
                TextField("Nome", text: settings.binding(\.layout.pages[index].title))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                SymbolPicker(symbol: settings.binding(\.layout.pages[index].symbol))
                Spacer(minLength: 8)
                Text("Altezza")
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { settings.config.layout.pages[safe: index]?.height ?? settings.config.appearance.openHeight },
                        set: { value in settings.update { $0.layout.pages[index].height = value } }
                    ),
                    in: 180...420,
                    step: 4
                )
                .frame(width: 160)
                Button("Elimina pagina", role: .destructive) { deletePage(page) }
                    .disabled(layout.pages.count <= 1)
            }
        }
    }

    private func addWidget(_ kind: String) {
        guard let page = selectedPage, let index = layout.pages.firstIndex(where: { $0.id == page.id }) else { return }
        let weight = ModuleCatalog.widget(kind, custom: custom)?.defaultWeight ?? 1
        settings.update {
            $0.layout.pages[index].widgets.append(WidgetPlacement(id: UUID().uuidString, kind: kind, weight: weight))
        }
    }

    private func deletePage(_ page: PageConfig) {
        settings.update { $0.layout.pages.removeAll { $0.id == page.id } }
        selectedPageID = settings.config.layout.pages.first?.id
        selectedWidgetID = nil
    }

    // MARK: - Pagina iniziale

    private var startSection: some View {
        EditorCard(title: "All'apertura", subtitle: "Su quale pagina si apre la notch.") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Pagina iniziale", selection: settings.binding(\.layout.startMode)) {
                    ForEach(StartPageMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if layout.startMode == .specific {
                    Picker("Pagina", selection: settings.binding(\.layout.startPageID)) {
                        ForEach(layout.pages) { Text($0.title).tag(Optional($0.id)) }
                    }
                }
                Text(layout.startMode.help)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Componenti dell'editor

private struct EditorCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.45)))
    }
}

/// Il ritaglio fra le due zone: serve a orientarsi, come nella notch vera.
private struct NotchCutout: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.white.opacity(0.25))
            Text("notch")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(width: 92, height: 34)
        .padding(.horizontal, 8)
    }
}

/// Carico utile del trascinamento: distingue un elemento compatto da un widget.
private enum DragPayload {
    static func compact(_ id: String) -> String { "compact|\(id)" }
    static func widget(_ id: String) -> String { "widget|\(id)" }
    static func newWidget(_ kind: String) -> String { "new-widget|\(kind)" }

    static func parse(_ raw: String) -> (kind: String, value: String)? {
        guard let split = raw.firstIndex(of: "|") else { return nil }
        return (String(raw[..<split]), String(raw[raw.index(after: split)...]))
    }
}

/// Una zona di elementi compatti: riceve dalla tavolozza e dalle altre zone.
private struct CompactZoneView: View {
    @Binding var items: [String]
    var alignment: Alignment
    var placeholder: String
    var isHeader = false

    @EnvironmentObject private var settings: SettingsStore
    @State private var targeted = false
    @State private var targetChip: String?

    var body: some View {
        HStack(spacing: 5) {
            if items.isEmpty {
                Text(placeholder)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.35))
            }
            ForEach(items, id: \.self) { id in
                CompactChip(id: id, custom: settings.config.customWidgets, showsDropMark: targetChip == id) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        items.removeAll { $0 == id }
                    }
                }
                .draggable(DragPayload.compact(id))
                .dropDestination(for: String.self) { payloads, _ in
                    place(payloads.first, before: id)
                } isTargeted: { hovering in
                    targetChip = hovering ? id : (targetChip == id ? nil : targetChip)
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: alignment)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : Color.white.opacity(0.1), lineWidth: targeted ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { payloads, _ in
            place(payloads.first, before: nil)
        } isTargeted: { targeted = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: items)
    }

    /// Nella notch chiusa un elemento è uno solo: spostandolo lascia la zona di partenza.
    private func place(_ raw: String?, before target: String?) -> Bool {
        guard let raw, let payload = DragPayload.parse(raw), payload.kind == "compact" else { return false }
        let id = payload.value
        guard id != target else { return false }
        if !isHeader {
            settings.update { config in
                config.layout.closedLeading.removeAll { $0 == id }
                config.layout.closedTrailing.removeAll { $0 == id }
            }
        }
        var updated = items
        updated.removeAll { $0 == id }
        if let target, let index = updated.firstIndex(of: target) {
            updated.insert(id, at: index)
        } else {
            updated.append(id)
        }
        items = updated
        return true
    }
}

private struct CompactChip: View {
    let id: String
    let custom: [CustomWidgetConfig]
    var showsDropMark: Bool
    var onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        let descriptor = ModuleCatalog.compact(id, custom: custom)
        HStack(spacing: 4) {
            Image(systemName: descriptor?.symbol ?? "questionmark")
                .font(.system(size: 10, weight: .semibold))
            Text(descriptor?.name ?? id)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Togli dalla notch")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .background(Capsule(style: .continuous).fill(.white.opacity(hovering ? 0.22 : 0.14)))
        .overlay(alignment: .leading) {
            if showsDropMark {
                Capsule().fill(Color.accentColor).frame(width: 2.5).offset(x: -4)
            }
        }
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .help(descriptor?.summary ?? "")
    }
}

/// Tutti gli elementi compatti disponibili: si trascinano o si aggiungono dal menu.
private struct CompactPalette: View {
    let used: Set<String>
    let custom: [CustomWidgetConfig]
    let destinations: [(String, Binding<[String]>)]

    var body: some View {
        let all = ModuleCatalog.allCompacts(custom: custom)
        let groups = Dictionary(grouping: all, by: \.group)
        let order = ["Agenti", "Musica", "Calendario", "Sistema", "Strumenti", "Personalizzati"]

        VStack(alignment: .leading, spacing: 6) {
            ForEach(order.filter { groups[$0] != nil }, id: \.self) { group in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .leading)
                    FlowLayout(spacing: 5) {
                        ForEach(groups[group] ?? []) { descriptor in
                            PaletteChip(descriptor: descriptor, isUsed: used.contains(descriptor.id), destinations: destinations)
                        }
                    }
                }
            }
        }
    }
}

private struct PaletteChip: View {
    let descriptor: CompactDescriptor
    let isUsed: Bool
    let destinations: [(String, Binding<[String]>)]

    var body: some View {
        Menu {
            ForEach(destinations, id: \.0) { destination in
                Button(destination.0) {
                    if !destination.1.wrappedValue.contains(descriptor.id) {
                        destination.1.wrappedValue.append(descriptor.id)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: descriptor.symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(descriptor.name)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(isUsed ? .secondary : .primary)
            .background(Capsule(style: .continuous).fill(.quaternary))
            .opacity(isUsed ? 0.55 : 1)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .draggable(DragPayload.compact(descriptor.id)) {
            Text(descriptor.name)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.regularMaterial))
        }
        .help(descriptor.summary)
    }
}

/// Va a capo quando non c'è più spazio, come le etichette di un articolo.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.items.isEmpty, current.width + spacing + size.width > width {
                rows.append(current)
                current = Row()
            }
            current.width += (current.items.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.items.append(index)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Pagine

private struct PageTabsEditor: View {
    @Binding var selectedPageID: String?
    @EnvironmentObject private var settings: SettingsStore
    @State private var targetID: String?

    var body: some View {
        let pages = settings.config.layout.pages
        HStack(spacing: 6) {
            ForEach(pages) { page in
                let isSelected = (selectedPageID ?? pages.first?.id) == page.id
                Button {
                    selectedPageID = page.id
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: page.symbol).font(.system(size: 11, weight: .semibold))
                        Text(page.title).font(.callout.weight(.medium)).lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(Capsule(style: .continuous).fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15)))
                    .overlay(alignment: .leading) {
                        if targetID == page.id {
                            Capsule().fill(Color.accentColor).frame(width: 2.5).offset(x: -4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .draggable("page|\(page.id)")
                .dropDestination(for: String.self) { payloads, _ in
                    guard let raw = payloads.first, let payload = DragPayload.parse(raw), payload.kind == "page" else { return false }
                    movePage(payload.value, before: page.id)
                    return true
                } isTargeted: { hovering in
                    targetID = hovering ? page.id : (targetID == page.id ? nil : targetID)
                }
            }

            Button {
                addPage()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.secondary.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .help("Aggiungi una pagina")

            Spacer(minLength: 0)
        }
    }

    private func movePage(_ id: String, before target: String) {
        guard id != target else { return }
        settings.update { config in
            guard let from = config.layout.pages.firstIndex(where: { $0.id == id }) else { return }
            let page = config.layout.pages.remove(at: from)
            let to = config.layout.pages.firstIndex { $0.id == target } ?? config.layout.pages.count
            config.layout.pages.insert(page, at: to)
        }
    }

    private func addPage() {
        let id = UUID().uuidString
        let number = settings.config.layout.pages.count + 1
        settings.update {
            $0.layout.pages.append(PageConfig(id: id, title: "Pagina \(number)", symbol: "square.grid.2x2.fill", widgets: []))
        }
        selectedPageID = id
    }
}

/// La pagina vera, in miniatura, con sopra le maniglie per modificarla.
private struct PageCanvas: View {
    let page: PageConfig
    @Binding var selectedWidgetID: String?

    @EnvironmentObject private var settings: SettingsStore
    @State private var canvasWidth: CGFloat = 640

    var body: some View {
        let appearance = settings.config.appearance
        let scale = min(1, canvasWidth / CGFloat(appearance.openWidth))
        let height = CGFloat(page.height ?? appearance.openHeight) * scale

        ZStack(alignment: .topLeading) {
            NotchLivePreview(pageID: page.id, maxWidth: canvasWidth)
            // Stesse proporzioni della pagina: le maniglie cadono esattamente sui widget.
            PageCanvasOverlay(page: page, selectedWidgetID: $selectedWidgetID, scale: scale)
                .frame(width: CGFloat(appearance.openWidth) * scale, height: height)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: height)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { canvasWidth = min(proxy.size.width, 760) }
                .onChange(of: proxy.size.width) { _, value in canvasWidth = min(value, 760) }
        })
    }
}

private struct PageCanvasOverlay: View {
    let page: PageConfig
    @Binding var selectedWidgetID: String?
    let scale: CGFloat

    @EnvironmentObject private var settings: SettingsStore
    @State private var dropTargeted = false

    private var pageIndex: Int? {
        settings.config.layout.pages.firstIndex { $0.id == page.id }
    }

    private var columns: [[WidgetPlacement]] {
        var result: [[WidgetPlacement]] = []
        for widget in page.widgets {
            if widget.stacked, !result.isEmpty {
                result[result.count - 1].append(widget)
            } else {
                result.append([widget])
            }
        }
        return result
    }

    var body: some View {
        let spacing = CGFloat(settings.config.appearance.widgetSpacing) * scale
        let header = max(32, 30) * scale

        GeometryReader { geometry in
            let horizontalPadding = 11 * scale
            let width = geometry.size.width - horizontalPadding * 2
            let columns = columns
            let totalWeight = max(columns.reduce(0) { $0 + $1[0].weight }, 0.01)
            let available = max(0, width - spacing * CGFloat(max(columns.count - 1, 0)))

            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.element.first?.id) { index, column in
                    VStack(spacing: spacing) {
                        ForEach(column) { widget in
                            WidgetTile(
                                widget: widget,
                                isSelected: selectedWidgetID == widget.id,
                                onSelect: { selectedWidgetID = selectedWidgetID == widget.id ? nil : widget.id },
                                onRemove: { remove(widget) },
                                onDrop: { raw in place(raw, before: widget) }
                            )
                        }
                    }
                    .frame(width: available * column[0].weight / totalWeight)

                    if index < columns.count - 1 {
                        ResizeHandle(width: spacing) { delta in
                            resize(columnIndex: index, delta: delta, available: available, totalWeight: totalWeight)
                        }
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, header + 3 * scale)
            .padding(.bottom, 11 * scale)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .overlay {
                if page.widgets.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "plus.rectangle.on.rectangle")
                            .font(.title2)
                        Text("Trascina qui un widget")
                            .font(.callout)
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
            .dropDestination(for: String.self) { payloads, _ in
                place(payloads.first, before: nil)
            } isTargeted: { dropTargeted = $0 }
        }
    }

    private func remove(_ widget: WidgetPlacement) {
        guard let pageIndex else { return }
        settings.update { config in
            let widgets = config.layout.pages[pageIndex].widgets
            // Il widget impilato sotto quello che se ne va deve ereditarne il posto in colonna.
            if let index = widgets.firstIndex(where: { $0.id == widget.id }) {
                if !widget.stacked, index + 1 < widgets.count, widgets[index + 1].stacked {
                    config.layout.pages[pageIndex].widgets[index + 1].stacked = false
                    config.layout.pages[pageIndex].widgets[index + 1].weight = widget.weight
                }
            }
            config.layout.pages[pageIndex].widgets.removeAll { $0.id == widget.id }
        }
        if selectedWidgetID == widget.id { selectedWidgetID = nil }
    }

    private func place(_ raw: String?, before target: WidgetPlacement?) -> Bool {
        guard let raw, let payload = DragPayload.parse(raw), let pageIndex else { return false }
        switch payload.kind {
        case "new-widget":
            let weight = ModuleCatalog.widget(payload.value, custom: settings.config.customWidgets)?.defaultWeight ?? 1
            let widget = WidgetPlacement(id: UUID().uuidString, kind: payload.value, weight: weight)
            settings.update { config in
                insert(widget, into: &config.layout.pages[pageIndex].widgets, before: target)
            }
            return true
        case "widget":
            guard payload.value != target?.id else { return false }
            settings.update { config in
                var widgets = config.layout.pages[pageIndex].widgets
                guard let from = widgets.firstIndex(where: { $0.id == payload.value }) else { return }
                var moving = widgets.remove(at: from)
                // Spostato altrove, un widget impilato torna ad avere una colonna sua.
                moving.stacked = false
                insert(moving, into: &widgets, before: target)
                config.layout.pages[pageIndex].widgets = widgets
            }
            return true
        default:
            return false
        }
    }

    private func insert(_ widget: WidgetPlacement, into widgets: inout [WidgetPlacement], before target: WidgetPlacement?) {
        if let target, let index = widgets.firstIndex(where: { $0.id == target.id }) {
            widgets.insert(widget, at: index)
        } else {
            widgets.append(widget)
        }
    }

    private func resize(columnIndex: Int, delta: CGFloat, available: CGFloat, totalWeight: Double) {
        guard let pageIndex, available > 0 else { return }
        let columns = columns
        guard columnIndex + 1 < columns.count,
              let leftID = columns[columnIndex].first?.id,
              let rightID = columns[columnIndex + 1].first?.id
        else { return }
        let change = Double(delta / available) * totalWeight

        settings.update { config in
            var widgets = config.layout.pages[pageIndex].widgets
            guard let left = widgets.firstIndex(where: { $0.id == leftID }),
                  let right = widgets.firstIndex(where: { $0.id == rightID })
            else { return }
            let minimum = totalWeight * 0.12
            guard widgets[left].weight + change >= minimum, widgets[right].weight - change >= minimum else { return }
            widgets[left].weight += change
            widgets[right].weight -= change
            config.layout.pages[pageIndex].widgets = widgets
        }
    }
}

private struct WidgetTile: View {
    let widget: WidgetPlacement
    var isSelected: Bool
    var onSelect: () -> Void
    var onRemove: () -> Void
    var onDrop: (String?) -> Bool

    @EnvironmentObject private var settings: SettingsStore
    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        let descriptor = ModuleCatalog.widget(widget.kind, custom: settings.config.customWidgets)
        let radius = CGFloat(settings.config.appearance.cardRadius) * 0.7

        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(hovering || targeted ? 0.06 : 0.001))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        isSelected || targeted ? Color.accentColor : Color.white.opacity(hovering ? 0.5 : 0.14),
                        style: StrokeStyle(lineWidth: isSelected || targeted ? 2 : 1, dash: isSelected ? [] : [4, 3])
                    )
            }
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.black.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .help("Togli dalla pagina")
                }
            }
            .overlay(alignment: .bottomLeading) {
                if hovering, let descriptor {
                    Text(descriptor.name)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.7)))
                        .padding(5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { hovering = $0 }
            .onTapGesture(perform: onSelect)
            .draggable(DragPayload.widget(widget.id)) {
                Label(descriptor?.name ?? widget.kind, systemImage: descriptor?.symbol ?? "square")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.regularMaterial))
            }
            .dropDestination(for: String.self) { payloads, _ in
                onDrop(payloads.first)
            } isTargeted: { targeted = $0 }
    }
}

/// La maniglia fra due colonne: tirandola si sposta il confine.
private struct ResizeHandle: View {
    let width: CGFloat
    var onDrag: (CGFloat) -> Void

    @State private var hovering = false
    @State private var lastTranslation: CGFloat = 0

    var body: some View {
        ZStack {
            Color.white.opacity(0.001)
            Capsule()
                .fill(Color.white.opacity(hovering ? 0.9 : 0.3))
                .frame(width: 3, height: 34)
        }
        .frame(width: max(width, 8))
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    onDrag(value.translation.width - lastTranslation)
                    lastTranslation = value.translation.width
                }
                .onEnded { _ in lastTranslation = 0 }
        )
    }
}

private struct WidgetInspector: View {
    let pageIndex: Int
    let widget: WidgetPlacement
    var onDone: () -> Void

    @EnvironmentObject private var settings: SettingsStore

    private var widgetIndex: Int? {
        settings.config.layout.pages[safe: pageIndex]?.widgets.firstIndex { $0.id == widget.id }
    }

    var body: some View {
        let descriptor = ModuleCatalog.widget(widget.kind, custom: settings.config.customWidgets)
        HStack(spacing: 14) {
            Label(descriptor?.name ?? widget.kind, systemImage: descriptor?.symbol ?? "square")
                .font(.callout.weight(.semibold))

            if let index = widgetIndex {
                Toggle("Impila sotto il precedente", isOn: Binding(
                    get: { settings.config.layout.pages[safe: pageIndex]?.widgets[safe: index]?.stacked ?? false },
                    set: { value in settings.update { $0.layout.pages[pageIndex].widgets[index].stacked = value } }
                ))
                .disabled(index == 0)
                .help("Mette questo widget nella stessa colonna di quello che lo precede")
            }

            Spacer(minLength: 0)
            Button("Fatto", action: onDone)
        }
        .padding(.vertical, 2)
    }
}

/// Tutti i widget che si possono aggiungere.
private struct WidgetPalette: View {
    let custom: [CustomWidgetConfig]
    var onAdd: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(ModuleCatalog.allWidgets(custom: custom)) { descriptor in
                Button {
                    onAdd(descriptor.kind)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: descriptor.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor.opacity(0.14)))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(descriptor.name)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(descriptor.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.background.opacity(0.6)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .draggable(DragPayload.newWidget(descriptor.kind)) {
                    Label(descriptor.name, systemImage: descriptor.symbol)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.regularMaterial))
                }
            }
        }
    }
}

/// Scelta dell'icona di una pagina.
struct SymbolPicker: View {
    @Binding var symbol: String
    @State private var isPresented = false

    private static let symbols = [
        "house.fill", "sparkles", "star.fill", "bolt.fill", "moon.stars.fill", "sun.max.fill", "cloud.fill", "flame.fill",
        "music.note", "headphones", "play.circle.fill", "waveform", "calendar", "clock.fill", "timer", "alarm.fill",
        "tray.full.fill", "folder.fill", "doc.text.fill", "note.text", "paperclip", "link", "bookmark.fill", "tag.fill",
        "terminal.fill", "chevron.left.forwardslash.chevron.right", "hammer.fill", "wrench.and.screwdriver.fill", "cpu", "memorychip", "server.rack", "network",
        "person.fill", "person.2.fill", "bubble.left.fill", "envelope.fill", "phone.fill", "video.fill", "camera.fill", "photo.fill",
        "gamecontroller.fill", "book.fill", "graduationcap.fill", "briefcase.fill", "cart.fill", "creditcard.fill", "chart.bar.fill", "gauge.with.dots.needle.50percent",
        "square.grid.2x2.fill", "rectangle.3.group.fill", "circle.hexagongrid.fill", "heart.fill", "leaf.fill", "pawprint.fill", "airplane", "car.fill"
    ]

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: symbol)
                .frame(width: 22, height: 18)
        }
        .help("Scegli l'icona")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 8), spacing: 4) {
                ForEach(Self.symbols, id: \.self) { name in
                    Button {
                        symbol = name
                        isPresented = false
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 13))
                            .frame(width: 30, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6).fill(symbol == name ? Color.accentColor.opacity(0.25) : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
    }
}
