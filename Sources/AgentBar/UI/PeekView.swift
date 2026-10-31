import SwiftUI

/// Anteprima mostrata al passaggio del mouse: sola lettura, sparisce da sola.
struct PeekView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var presentation: PanelPresentation

    private var rows: [AgentSession] {
        let live = store.liveSessions
        if !live.isEmpty { return Array(live.prefix(store.config.maxPeekRows)) }
        return Array(store.sessions.prefix(2))
    }

    private var overflow: Int {
        max(0, store.liveSessions.count - store.config.maxPeekRows)
    }

    var body: some View {
        PanelSurface(useGlass: store.config.useLiquidGlass) {
            VStack(alignment: .leading, spacing: 10) {
                header
                if rows.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 6) {
                        ForEach(rows) { session in
                            PeekRow(session: session)
                        }
                    }
                    if overflow > 0 {
                        Text("+\(overflow) altre sessioni")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                footer
            }
            .padding(14)
            .frame(width: Theme.peekWidth)
        }
        .padding(Theme.shadowPad)
        .panelTransition(presentation)
    }

    private var header: some View {
        HStack(spacing: 9) {
            AppMark()
            VStack(alignment: .leading, spacing: 1) {
                Text("Agenti")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if let subtitle = store.headerSubtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            if store.badgeCount > 0 {
                Text("\(store.badgeCount)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary.opacity(0.85))
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 9) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Nessuna sessione")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Text("Avvia un agent in un progetto")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(Color.rowFill)
        )
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 9, weight: .semibold))
            Text("Clicca per aprire il pannello")
                .font(.system(size: 10, weight: .medium, design: .rounded))
            Spacer()
            Text(Format.ago(store.lastRefresh))
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.tertiary)
        .padding(.top, 2)
    }
}

/// Riga compatta dell'anteprima.
struct PeekRow: View {
    let session: AgentSession

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Capsule()
                .fill(session.accentColor.opacity(0.85))
                .frame(width: 2.5)
                .padding(.vertical, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    PulseDot(status: session.status, size: 6.5)
                        .frame(width: 10, height: 10)
                    Text(session.project)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    if let branch = session.branch, branch != "HEAD" {
                        MetaChip(text: branch, symbol: "arrow.triangle.branch")
                    }
                    Spacer(minLength: 4)
                    if let elapsed = Format.elapsed(since: session.updatedAt) {
                        Text(elapsed)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(session.status.needsYou ? session.status.tint : .secondary)
                    .lineLimit(1)

                if let fraction = session.contextFraction {
                    ContextBar(fraction: fraction, tint: session.status.tint)
                        .padding(.top, 1)
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(Color.rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .strokeBorder(session.status.needsYou ? session.status.tint.opacity(0.28) : .clear, lineWidth: 0.8)
        )
    }

    private var subtitle: String {
        guard let activity = session.activity, !activity.isEmpty,
              activity.caseInsensitiveCompare(session.status.label) != .orderedSame
        else { return session.status.label }
        return session.status == .working ? activity : "\(session.status.label) · \(activity)"
    }
}
