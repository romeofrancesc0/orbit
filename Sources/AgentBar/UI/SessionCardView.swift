import SwiftUI

/// Card di una singola sessione: si illumina all'hover, si espande al click.
struct SessionCardView: View {
    let session: AgentSession
    var expanded: Bool
    var onToggleExpand: () -> Void
    /// Chiamata dalle azioni che portano l'utente in un'altra app: il pannello
    /// deve sparire da solo, non restare aperto alle sue spalle.
    var onNavigate: () -> Void = {}
    var onHide: () -> Void = {}

    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            topRow
            titleRow
            statusRow
            if let fraction = session.contextFraction {
                contextRow(fraction)
            }
            if hovering || expanded {
                actionsRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if expanded {
                details
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 9)
        .padding(.leading, 13)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(hovering || expanded ? Color.rowFillHover : Color.rowFill)
        )
        .overlay(alignment: .leading) {
            Capsule()
                .fill(session.accentColor.opacity(session.status == .ended ? 0.35 : 0.9))
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.leading, 4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.9)
        )
        .shadow(color: .black.opacity(hovering ? 0.16 : 0), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
        .onTapGesture(perform: onToggleExpand)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: expanded)
    }

    /// L'attività, a meno che non ripeta l'etichetta di stato accanto a cui sta.
    private var activityText: String? {
        guard let activity = session.activity, !activity.isEmpty,
              activity.caseInsensitiveCompare(session.status.label) != .orderedSame
        else { return nil }
        return activity
    }

    private var borderColor: Color {
        if session.status.needsYou { return session.status.tint.opacity(0.35) }
        return hovering ? Color.hairline : Color.hairlineSoft
    }

    // MARK: - Righe

    private var topRow: some View {
        HStack(spacing: 6) {
            PulseDot(status: session.status, size: 7)
                .frame(width: 11, height: 11)

            Text(session.project)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)

            if let branch = session.branch, branch != "HEAD", !branch.isEmpty {
                MetaChip(text: branch, symbol: "arrow.triangle.branch")
            }
            if let host = session.host {
                MetaChip(text: host)
            }

            Spacer(minLength: 4)

            Text(Format.elapsed(since: session.updatedAt) ?? "")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }

    private var titleRow: some View {
        Text(session.title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary.opacity(0.9))
            .lineLimit(expanded ? 3 : 1)
            .fixedSize(horizontal: false, vertical: expanded)
    }

    private var statusRow: some View {
        HStack(spacing: 5) {
            Image(systemName: session.status.symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(session.status.tint)
            Text(session.status.label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(session.status.tint)
            if let activity = activityText {
                Text("·")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(activity)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func contextRow(_ fraction: Double) -> some View {
        HStack(spacing: 7) {
            ContextBar(fraction: fraction, tint: session.status.tint)
            if let used = session.tokensUsed {
                Text(Format.tokens(used))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 1)
    }

    private var actionsRow: some View {
        HStack(spacing: 5) {
            if session.openURL != nil || session.status.isLive {
                GhostButton(symbol: "arrow.up.forward.app", label: "Vai", tint: session.accentColor) {
                    SessionActions.focus(session)
                    onNavigate()
                }
            } else if session.providerID.contains("claude") && session.nativeID != nil {
                GhostButton(symbol: "play.fill", label: "Riprendi", tint: session.accentColor) {
                    SessionActions.resumeClaudeCode(session: session)
                    onNavigate()
                }
            }
            if let path = session.path {
                GhostButton(symbol: "terminal", label: "Terminale", tint: nil) {
                    SessionActions.openInTerminal(path: path)
                    onNavigate()
                }
                GhostButton(symbol: "chevron.left.forwardslash.chevron.right", label: "Editor", tint: nil) {
                    SessionActions.openInEditor(path: path)
                    onNavigate()
                }
                GhostButton(symbol: "folder", label: "Finder", tint: nil) {
                    SessionActions.revealInFinder(path: path)
                    onNavigate()
                }
                GhostButton(symbol: copied ? "checkmark" : "doc.on.doc", label: copied ? "Copiato" : "Copia", tint: nil) {
                    SessionActions.copy(path)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                }
            }
            Spacer(minLength: 0)
            GhostButton(symbol: "eye.slash", label: "", tint: Color(hex: 0xF97066), action: onHide)
                .help("Togli dall'elenco · ricompare se riprendi questa chat")
        }
        .padding(.top, 2)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(Color.hairlineSoft)

            if let path = Format.path(session.path) {
                detailLine(symbol: "folder", text: path)
            }
            if let model = Format.model(session.model) {
                detailLine(symbol: "cpu", text: model)
            }
            detailLine(
                symbol: "shippingbox",
                text: session.providerName + (session.pid.map { " · pid \($0)" } ?? "")
            )
            if let started = session.startedAt {
                detailLine(symbol: "clock", text: "aperta da \(Format.duration(Date().timeIntervalSince(started)))")
            }
            if let prompt = session.detail, !prompt.isEmpty {
                Text(prompt)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.top, 1)
            }
            if !session.actions.isEmpty {
                HStack(spacing: 5) {
                    ForEach(session.actions) { action in
                        GhostButton(symbol: action.symbol ?? "bolt", label: action.label, tint: session.accentColor) {
                            SessionActions.run(command: action.command, session: session)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 1)
            }
        }
    }

    private func detailLine(symbol: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(width: 11)
            Text(text)
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}
