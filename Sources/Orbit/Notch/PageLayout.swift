import CoreGraphics

/// Come stanno i widget di una pagina nella larghezza della notch aperta. Ogni widget ha
/// una larghezza sotto la quale il suo contenuto non entra più: se la notch è troppo
/// stretta per tutti, quelli in fondo restano fuori invece di accavallarsi.
/// La stessa regola vale per la notch vera, per l'editor del layout e per la guida.
enum PageLayout {
    /// Sotto queste misure (card compresa) il contenuto del widget si schiaccia.
    private static let minimumWidths: [String: CGFloat] = [
        "agents": 210, "media": 210, "calendar": 150, "shelf": 170,
        "mirror": 84, "battery": 84, "system": 120, "clipboard": 150,
        "timer": 110, "notes": 130, "launcher": 120, "clock": 90
    ]

    static func minimumWidth(of kind: String) -> CGFloat {
        minimumWidths[kind] ?? 110
    }

    /// Un widget "impilato" si unisce alla colonna di quello prima.
    static func columns(of widgets: [WidgetPlacement]) -> [[WidgetPlacement]] {
        var result: [[WidgetPlacement]] = []
        for widget in widgets {
            if widget.stacked, !result.isEmpty {
                result[result.count - 1].append(widget)
            } else {
                result.append([widget])
            }
        }
        return result
    }

    /// Lo spazio per i widget dentro la notch aperta, tolti margini e orecchie.
    static func contentWidth(_ appearance: AppearanceConfig) -> CGFloat {
        CGFloat(appearance.openWidth) - 2 * (NotchMetrics.contentInset + CGFloat(appearance.openEarRadius))
    }

    /// Le larghezze delle colonne che entrano, nell'ordine: le altre restano fuori.
    /// Ogni colonna riceve la sua parte secondo il peso, ma mai meno del suo minimo.
    /// `scale` serve alle anteprime rimpicciolite.
    static func widths(for columns: [[WidgetPlacement]], width: CGFloat, spacing: CGFloat, scale: CGFloat = 1) -> [CGFloat] {
        guard !columns.isEmpty, width > 0 else { return [] }
        let minimums = columns.map { column in column.map { minimumWidth(of: $0.kind) }.max() ?? 110 }.map { $0 * scale }

        // Quante colonne entrano: almeno una, anche se da sola è già troppo larga.
        var count = 0
        var used: CGFloat = 0
        for minimum in minimums {
            let needed = used + (count > 0 ? spacing : 0) + minimum
            if count > 0, needed > width + 0.5 { break }
            used = needed
            count += 1
        }

        // Una colonna sola prende tutto lo spazio che c'è, poco o tanto.
        if count == 1 { return [width] }

        let visible = Array(columns.prefix(count))
        let floors = Array(minimums.prefix(count))
        let weights = visible.map { max($0[0].weight, 0.01) }
        let available = max(0, width - spacing * CGFloat(count - 1))

        // Si fissano al minimo le colonne che scenderebbero sotto, e il resto si divide fra le altre.
        var fixed = Array(repeating: false, count: count)
        var result = Array(repeating: CGFloat(0), count: count)
        for _ in 0..<count {
            let free = available - zip(fixed, floors).reduce(0) { $0 + ($1.0 ? $1.1 : 0) }
            let freeWeight = zip(fixed, weights).reduce(0) { $0 + ($1.0 ? 0 : $1.1) }
            var changed = false
            for index in 0..<count where !fixed[index] {
                let share = freeWeight > 0 ? free * CGFloat(weights[index] / freeWeight) : 0
                if share < floors[index] {
                    fixed[index] = true
                    changed = true
                }
                result[index] = share
            }
            if !changed { break }
        }
        for index in 0..<count where fixed[index] { result[index] = floors[index] }
        return result
    }

    /// Quanti widget della pagina restano fuori con questa larghezza.
    static func hiddenWidgets(in page: PageConfig, appearance: AppearanceConfig) -> [WidgetPlacement] {
        let columns = columns(of: page.widgets)
        let shown = widths(for: columns, width: contentWidth(appearance), spacing: CGFloat(appearance.widgetSpacing)).count
        return columns.dropFirst(shown).flatMap { $0 }
    }

    /// Se un widget in più, in una colonna sua, entrerebbe ancora nella pagina.
    static func canAdd(_ kind: String, to widgets: [WidgetPlacement], appearance: AppearanceConfig) -> Bool {
        let columns = columns(of: widgets + [WidgetPlacement(kind: kind)])
        return widths(for: columns, width: contentWidth(appearance), spacing: CGFloat(appearance.widgetSpacing)).count == columns.count
    }
}
