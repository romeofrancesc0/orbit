import SwiftUI

/// La silhouette della notch: pende dal bordo dello schermo con due "orecchie"
/// concave in alto e angoli continui in basso, come il ritaglio vero del display.
/// Entrambi i raggi sono animabili: è questa forma a fare il morphing fra chiusa e aperta.
struct NotchShape: Shape {
    var earRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(earRadius, bottomRadius) }
        set {
            earRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let ear = max(0, min(earRadius, rect.width / 4, rect.height))
        let bodyLeft = rect.minX + ear
        let bodyRight = rect.maxX - ear
        // Lo smusso continuo occupa circa 1,53 volte il raggio su ogni lato.
        let limit = Self.smoothing
        let radius = max(0, min(bottomRadius, (bodyRight - bodyLeft) / (2 * limit), (rect.height - ear) / limit))
        let bottom = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Orecchio sinistro: raccordo concavo col bordo dello schermo.
        path.addCurve(
            to: CGPoint(x: bodyLeft, y: rect.minY + ear),
            control1: CGPoint(x: rect.minX + ear * 0.55, y: rect.minY),
            control2: CGPoint(x: bodyLeft, y: rect.minY + ear * 0.45)
        )

        // Angolo in basso a sinistra: si scende lungo il fianco e si esce sul fondo.
        func left(_ alongSide: CGFloat, _ alongBottom: CGFloat) -> CGPoint {
            CGPoint(x: bodyLeft + alongBottom * radius, y: bottom - alongSide * radius)
        }
        path.addLine(to: left(limit, 0))
        addContinuousCorner(to: &path, point: left)

        // Angolo in basso a destra: si arriva dal fondo e si risale lungo il fianco.
        func right(_ alongBottom: CGFloat, _ alongSide: CGFloat) -> CGPoint {
            CGPoint(x: bodyRight - alongBottom * radius, y: bottom - alongSide * radius)
        }
        path.addLine(to: right(limit, 0))
        addContinuousCorner(to: &path, point: right)

        // Orecchio destro.
        path.addLine(to: CGPoint(x: bodyRight, y: rect.minY + ear))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: bodyRight, y: rect.minY + ear * 0.45),
            control2: CGPoint(x: rect.maxX - ear * 0.55, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }

    /// Coefficienti degli angoli continui di iOS: raccordano la curvatura invece di
    /// spezzarla come un arco di cerchio, ed è la differenza che si percepisce come "Apple".
    private static let smoothing: CGFloat = 1.528665

    private func addContinuousCorner(to path: inout Path, point: (CGFloat, CGFloat) -> CGPoint) {
        path.addCurve(
            to: point(0.63149379, 0.07491139),
            control1: point(1.08849296, 0),
            control2: point(0.86840694, 0)
        )
        path.addCurve(
            to: point(0.07491139, 0.63149379),
            control1: point(0.37282383, 0.16905956),
            control2: point(0.16905956, 0.37282383)
        )
        path.addCurve(
            to: point(0, Self.smoothing),
            control1: point(0, 0.86840694),
            control2: point(0, 1.08849296)
        )
    }
}
