import AppKit
import SwiftUI

/// Una ghiera come quella delle app per il parcheggio: la si gira in tondo, in senso orario
/// il tempo cresce e in senso antiorario cala. Un giro intero è un'ora, e i giri si sommano.
struct DurationDial: View {
    @Binding var minutes: Int
    var range: ClosedRange<Int> = LockScreenConfig.screenOnMinutesRange
    var step = 5
    var size: CGFloat = 208

    /// Durante il giro il valore resta qui e va nelle impostazioni solo a dito alzato.
    @State private var live: Int?
    @State private var turned: Double = 0
    @State private var lastAngle: Double?
    @State private var dragging = false
    /// Dove è cominciato il giro in corso: se cambia, è un giro nuovo anche se il
    /// precedente è stato interrotto senza chiudersi.
    @State private var gestureStart: CGPoint?
    @GestureState private var pressing = false

    private let ring: CGFloat = 20
    private var shown: Int { live ?? minutes }

    var body: some View {
        let value = shown
        let laps = value / 60
        let rest = value % 60
        let fraction = rest == 0 && laps > 0 ? 1 : Double(rest) / 60
        let radius = (size - ring) / 2

        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.14), lineWidth: ring)

            // I giri già fatti restano come un anello più tenue sotto quello in corso.
            if laps > 0, rest > 0 {
                Circle()
                    .stroke(Color.accentColor.opacity(0.32), lineWidth: ring)
            }

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: ring, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Le tacche dei quarti d'ora stanno sulla corona, così il centro resta al testo.
            ticks(radius: radius)

            Circle()
                .fill(.white)
                .frame(width: ring + 8, height: ring + 8)
                .shadow(color: .black.opacity(0.35), radius: dragging ? 5 : 3, y: 1)
                .overlay(Circle().fill(Color.accentColor).frame(width: 6, height: 6))
                .scaleEffect(dragging ? 1.12 : 1)
                .offset(y: -radius)
                .rotationEffect(.degrees(fraction * 360))

            centerLabel(value)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(turn(radius: radius))
        .onChange(of: pressing) { _, isPressing in
            if !isPressing { finishTurn() }
        }
        .animation(dragging ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: value)
        .animation(.easeOut(duration: 0.15), value: dragging)
        .onHover { inside in
            if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Durata"))
        .accessibilityValue(Text(Self.describe(value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: minutes = clamp(minutes + step)
            case .decrement: minutes = clamp(minutes - step)
            @unknown default: break
            }
        }
    }

    private func ticks(radius: CGFloat) -> some View {
        ForEach(0..<12, id: \.self) { index in
            let major = index % 3 == 0
            Capsule()
                .fill(Color.primary.opacity(major ? 0.22 : 0.12))
                .frame(width: major ? 2.5 : 1.5, height: major ? 10 : 5)
                .offset(y: -radius)
                .rotationEffect(.degrees(Double(index) * 30))
        }
    }

    private func centerLabel(_ value: Int) -> some View {
        VStack(spacing: 3) {
            Self.styled(value)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            TimelineView(.everyMinute) { context in
                Text(tr("fino alle %@", Self.clock(context.date.addingTimeInterval(TimeInterval(value * 60)))))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Il gesto segue l'angolo del dito attorno al centro, non la sua posizione: conta di
    /// quanto si è girato, così si può fare più di un giro e tornare indietro.
    private func turn(radius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($pressing) { _, state, _ in state = true }
            .onChanged { drag in
                let center = CGPoint(x: size / 2, y: size / 2)
                let dx = drag.location.x - center.x
                let dy = drag.location.y - center.y
                // Troppo vicino al centro l'angolo salta: si aspetta che il dito esca.
                guard hypot(dx, dy) > 14 else { return }
                let angle = atan2(dx, -dy)

                if !dragging || gestureStart != drag.startLocation {
                    dragging = true
                    gestureStart = drag.startLocation
                    live = minutes
                    turned = Double(minutes)
                    lastAngle = angle
                    NSCursor.closedHand.set()
                    return
                }
                guard let last = lastAngle else { lastAngle = angle; return }
                var delta = angle - last
                if delta > .pi { delta -= 2 * .pi }
                if delta < -.pi { delta += 2 * .pi }
                lastAngle = angle

                turned = min(Double(range.upperBound), max(Double(range.lowerBound), turned + delta / (2 * .pi) * 60))
                let snapped = clamp(Int((turned / Double(step)).rounded()) * step)
                if snapped != live {
                    live = snapped
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                }
            }
            .onEnded { _ in finishTurn() }
    }

    /// Chiude il giro sia quando si alza il dito sia quando il gesto viene interrotto.
    private func finishTurn() {
        guard dragging else { return }
        if let live, live != minutes { minutes = live }
        live = nil
        lastAngle = nil
        gestureStart = nil
        dragging = false
        NSCursor.openHand.set()
    }

    private func clamp(_ value: Int) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }

    // MARK: - Testi

    static func styled(_ minutes: Int) -> Text {
        let hours = minutes / 60
        let rest = minutes % 60
        let number = Font.system(size: 34, weight: .semibold, design: .rounded)
        let unit = Font.system(size: 14, weight: .semibold, design: .rounded)
        if hours == 0 {
            return Text("\(rest)").font(number) + Text(" min").font(unit).foregroundColor(.secondary)
        }
        var text = Text("\(hours)").font(number) + Text(" h").font(unit).foregroundColor(.secondary)
        if rest > 0 {
            text = text + Text(" \(rest)").font(number) + Text(" min").font(unit).foregroundColor(.secondary)
        }
        return text
    }

    static func describe(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// La ghiera con i tasti per il passo fine e le durate più comuni a portata di clic.
struct ScreenOnDurationPicker: View {
    @Binding var minutes: Int
    private let presets = [15, 30, 60, 120, 240]

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 22) {
                stepButton("minus", by: -5)
                DurationDial(minutes: $minutes)
                stepButton("plus", by: 5)
            }
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { value in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { minutes = value }
                    } label: {
                        Text(DurationDial.describe(value))
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(minutes == value ? Color.white : Color.primary)
                            .background(Capsule(style: .continuous).fill(minutes == value ? Color.accentColor : Color.secondary.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Gira la ghiera: in senso orario aumenta, all'indietro cala. Un giro è un'ora.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func stepButton(_ symbol: String, by delta: Int) -> some View {
        let range = LockScreenConfig.screenOnMinutesRange
        let next = min(range.upperBound, max(range.lowerBound, minutes + delta))
        return Button {
            minutes = next
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .disabled(next == minutes)
        .help(delta > 0 ? tr("5 minuti in più") : tr("5 minuti in meno"))
    }
}
