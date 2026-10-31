import SwiftUI

/// Il lettore: copertina con il suo alone, titolo, avanzamento e comandi.
struct MediaWidget: View {
    @EnvironmentObject private var media: MediaService
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.notchTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            if let state = media.nowPlaying {
                let side = min(geometry.size.height - 4, min(geometry.size.width * 0.38, 126))
                HStack(spacing: 13) {
                    artwork(side: side)
                    VStack(alignment: .leading, spacing: 0) {
                        titles(state)
                        Spacer(minLength: 2)
                        MediaProgress(state: state)
                        Spacer(minLength: 2)
                        controls(state)
                    }
                    .frame(maxHeight: min(side + 4, geometry.size.height))
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            } else {
                emptyState
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    private func artwork(side: CGFloat) -> some View {
        Button(action: media.activateSource) {
            ZStack(alignment: .bottomTrailing) {
                // L'alone: la copertina sfocata che le sta dietro e la fa sembrare accesa.
                if let image = media.artwork {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: side, height: side)
                        .blur(radius: 18)
                        .opacity(0.55 * theme.appearance.glow / 0.55)
                        .scaleEffect(1.04)
                        .allowsHitTesting(false)
                }

                ArtworkThumbnail(image: media.artwork, size: side, radius: side * 0.14, showsPlaceholder: true)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

                if let icon = media.sourceIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        .offset(x: 5, y: 5)
                }
            }
        }
        .buttonStyle(NotchPressStyle())
        .help("Apri \(media.nowPlaying?.appName ?? "l'app")")
    }

    private func titles(_ state: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            MarqueeText(text: state.title, size: 13.5, weight: .semibold, color: theme.primary)
            MarqueeText(
                text: state.artist.isEmpty ? (state.appName ?? "") : state.artist,
                size: 11.5,
                color: theme.secondary
            )
        }
    }

    private func controls(_ state: NowPlaying) -> some View {
        HStack(spacing: 2) {
            if settings.config.media.showShuffleRepeat {
                NotchIconButton(symbol: "shuffle", size: 26, iconSize: 11, isActive: state.shuffle > 1, action: media.toggleShuffle)
            }
            NotchIconButton(symbol: "backward.fill", size: 30, iconSize: 13, action: media.previous)
            NotchIconButton(
                symbol: state.isPlaying ? "pause.fill" : "play.fill",
                size: 36,
                iconSize: 18,
                action: media.togglePlayPause
            )
            .contentTransition(.symbolEffect(.replace))
            NotchIconButton(symbol: "forward.fill", size: 30, iconSize: 13, action: media.next)
            if settings.config.media.showShuffleRepeat {
                NotchIconButton(
                    symbol: state.repeatMode == 2 ? "repeat.1" : "repeat",
                    size: 26,
                    iconSize: 11,
                    isActive: state.repeatMode > 1,
                    action: media.cycleRepeat
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme.tertiary)
            Text("Niente in riproduzione")
                .font(theme.font(11, .medium))
                .foregroundStyle(theme.secondary)
            if let error = media.bridgeError {
                Text(error)
                    .font(theme.font(9))
                    .foregroundStyle(theme.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
    }
}

/// Avanzamento trascinabile. Solo questa vista si ridisegna ogni secondo: il resto
/// del lettore resta fermo finché non cambia qualcosa.
struct MediaProgress: View {
    let state: NowPlaying

    @EnvironmentObject private var media: MediaService
    @Environment(\.notchTheme) private var theme
    @Environment(\.panelIsVisible) private var panelIsVisible

    @State private var dragPosition: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: state.isPlaying && panelIsVisible ? 1 : 60)) { context in
            let elapsed = dragPosition ?? state.currentElapsed(at: context.date)
            let fraction = state.duration > 0 ? elapsed / state.duration : 0

            VStack(spacing: 3) {
                track(fraction: fraction)
                HStack {
                    Text(Format.playback(elapsed))
                    Spacer()
                    Text(state.duration > 0 ? "-" + Format.playback(max(0, state.duration - elapsed)) : "")
                }
                .font(theme.numberFont(9.5))
                .foregroundStyle(theme.tertiary)
            }
        }
    }

    private func track(fraction: Double) -> some View {
        GeometryReader { geometry in
            let height: CGFloat = hovering || dragPosition != nil ? 6 : 4
            let tint = settingsTint
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, geometry.size.width * min(1, max(0, fraction))))
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard state.duration > 0 else { return }
                        let position = min(1, max(0, value.location.x / geometry.size.width))
                        dragPosition = position * state.duration
                    }
                    .onEnded { _ in
                        if let dragPosition { media.seek(to: dragPosition) }
                        // La posizione vera arriva fra un istante: fino ad allora vale quella scelta.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.dragPosition = nil }
                    }
            )
            .onHover { hovering = $0 }
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: height)
        }
        .frame(height: 10)
    }

    private var settingsTint: Color {
        theme.appearance.accentMode == .artwork ? (theme.ambient ?? theme.primary) : theme.accent
    }
}
