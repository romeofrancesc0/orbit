import SwiftUI

// MARK: - Misuratore

/// Barra del livello che reagisce a ogni pressione del tasto: il riempimento segue con
/// una molla che sfora appena, una manopola esce mentre si regola e rientra a riposo,
/// e a fondo corsa la barra si gonfia di un battito invece di restare ferma.
struct HUDMeter: View {
    var fraction: Double
    var tint: Color
    var height: CGFloat = 5
    /// Cambia a ogni pressione, anche quando il livello resta uguale (fondo corsa).
    var kick: UUID
    /// Tacche sulla barra: a 16 coincidono con i passi dei tasti del volume.
    var segments = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active = false
    @State private var bump = false
    @State private var settle: Task<Void, Never>?
    @State private var lastFraction: Double?

    var body: some View {
        GeometryReader { geometry in
            let level = min(1, max(0, fraction))
            let width = geometry.size.width
            let fill = height + (width - height) * level
            let knob = height * 2.2

            ZStack(alignment: .leading) {
                // Alone: segue la punta del riempimento e si accende mentre si regola.
                Capsule()
                    .fill(tint)
                    .frame(width: fill)
                    .blur(radius: height)
                    .opacity(active ? 0.55 : 0.18)

                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: fill)
                    if segments > 1 {
                        ForEach(1..<segments, id: \.self) { index in
                            Rectangle()
                                .fill(.black.opacity(0.3))
                                .frame(width: 1.2, height: height)
                                .offset(x: width * CGFloat(index) / CGFloat(segments) - 0.6)
                        }
                    }
                }
                .clipShape(Capsule())

                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.35), radius: 2.5, y: 1)
                    .scaleEffect(active ? 1 : 0.2)
                    .opacity(active ? 1 : 0)
                    .offset(x: fill - height / 2 - knob / 2)
            }
            .frame(height: height)
            .scaleEffect(x: 1, y: bump ? 1.3 : 1)
            .frame(maxHeight: .infinity)
            // Il riempimento scivola senza rimbalzare: tenendo premuto il tasto, una molla
            // che sfora ripartiva a ogni passo e la barra andava a scatti.
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1), value: level)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82), value: active)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.6), value: bump)
        }
        .frame(height: height)
        .onChange(of: kick) { trigger() }
        .onAppear { trigger() }
    }

    private func trigger() {
        guard !reduceMotion else { return }
        // Il battito solo a fondo corsa, quando la pressione non può più cambiare il livello:
        // a ogni passo farebbe tremare la barra.
        let level = min(1, max(0, fraction))
        let atLimit = (level >= 0.999 || level <= 0.001) && lastFraction.map { abs($0 - level) < 0.001 } == true
        lastFraction = level
        active = true
        bump = atLimit
        settle?.cancel()
        settle = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            bump = false
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            active = false
        }
    }
}

// MARK: - Icona

/// L'icona dell'indicatore: onde dell'altoparlante e raggi del sole si accendono in
/// proporzione al livello, e a ogni pressione l'icona dà un colpetto.
struct HUDGlyph: View {
    let hud: NotchHUD
    var size: CGFloat = 13

    @Environment(\.notchTheme) private var theme

    var body: some View {
        let name = hud.kind.symbol(level: hud.level, muted: hud.muted)
        Group {
            if hud.kind.usesVariableValue, !hud.muted, hud.level > 0 {
                Image(systemName: name, variableValue: hud.level)
            } else {
                Image(systemName: name)
            }
        }
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(hud.muted ? theme.tertiary : theme.primary)
        // Cambia forma (muto, livello) con una dissolvenza: niente colpetto a ogni pressione.
        .contentTransition(.symbolEffect(.replace))
    }
}

/// Il numero scorre invece di cambiare di colpo.
private struct HUDPercent: View {
    let value: Int
    var size: CGFloat
    var width: CGFloat
    var weight: Font.Weight = .medium
    var color: Color

    @Environment(\.notchTheme) private var theme

    var body: some View {
        Text("\(value)")
            .font(theme.numberFont(size, weight))
            .foregroundStyle(color)
            .contentTransition(.numericText(value: Double(value)))
            .animation(.snappy(duration: 0.22), value: value)
            .frame(width: width, alignment: .trailing)
    }
}

private extension NotchHUD {
    var shown: Double { muted ? 0 : level }
    var percent: Int { Int((shown * 100).rounded()) }
}

// MARK: - Ali della notch chiusa

struct HUDInlineLeading: View {
    let hud: NotchHUD

    var body: some View {
        HUDGlyph(hud: hud, size: 13)
            .frame(width: 20, height: 16)
            .accessibilityHidden(true)
    }
}

struct HUDInlineTrailing: View {
    let hud: NotchHUD
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.notchTheme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            HUDMeter(
                fraction: hud.shown,
                tint: hud.muted ? theme.tertiary : (settings.config.hud.useAccent ? theme.accent : .white),
                height: 4.5,
                kick: hud.stamp
            )
            .frame(width: 54, height: 16)
            if settings.config.hud.showPercent {
                HUDPercent(value: hud.percent, size: 10.5, width: 22, color: theme.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hud.kind.label)
        .accessibilityValue("\(hud.percent)%")
    }
}

// MARK: - Sotto la notch

struct HUDBelow: View {
    let hud: NotchHUD
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.notchTheme) private var theme

    var body: some View {
        let tint = hud.muted ? theme.tertiary : (settings.config.hud.useAccent ? theme.accent : .white)

        HStack(spacing: 11) {
            HUDGlyph(hud: hud, size: 13)
                .frame(width: 28, height: 28)
                .background(Circle().fill(hud.muted ? Color.white.opacity(0.08) : tint.opacity(0.18)))

            VStack(spacing: 5) {
                HStack(spacing: 0) {
                    Text(hud.muted ? tr("Muto") : hud.kind.label)
                        .font(theme.font(10.5, .semibold))
                        .foregroundStyle(theme.secondary)
                    Spacer(minLength: 4)
                    if settings.config.hud.showPercent {
                        HUDPercent(value: hud.percent, size: 11.5, width: 26, weight: .semibold, color: theme.primary)
                    }
                }
                HUDMeter(fraction: hud.shown, tint: tint, height: 6, kick: hud.stamp, segments: 16)
                    .frame(height: 10)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hud.kind.label)
        .accessibilityValue("\(hud.percent)%")
    }
}
