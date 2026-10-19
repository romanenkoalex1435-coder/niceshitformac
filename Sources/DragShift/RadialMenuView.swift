import SwiftUI

struct RadialMenuView: View {
    @ObservedObject var model: RadialModel

    var body: some View {
        let actions = model.actions
        let disc = RadialGeometry.discRadius * 2
        ZStack {
            // Soft drop shadow, visible only outside the frosted disc.
            Circle()
                .fill(Color.black.opacity(0.22))
                .frame(width: disc, height: disc)
                .blur(radius: 18)
                .offset(y: 12)
            BehindWindowBlur(cornerRadius: RadialGeometry.discRadius)
                .frame(width: disc, height: disc)
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0xFFF3EA, opacity: 0.35), Color(hex: 0xFFB98A, opacity: 0.22)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.15), .white.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.2
                    )
                )
                .frame(width: disc, height: disc)

            GlassGroup {
                ZStack {
                    ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                        RadialSegment(action: action, index: index, count: actions.count, hovered: model.hovered == index, visible: model.visible)
                    }
                    CenterLens(title: centerTitle, subtitle: model.nextPageTitle.map { "\(Prefs.trigger.symbol) \($0)" })
                }
            }
            .id(model.page)
            .transition(.asymmetric(insertion: .scale(scale: 0.88).combined(with: .opacity), removal: .opacity))
        }
        .frame(width: RadialGeometry.size, height: RadialGeometry.size)
        .scaleEffect(model.visible ? 1 : 0.6)
        .opacity(model.visible ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: model.visible)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: model.hovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.page)
    }

    private var centerTitle: String {
        if let index = model.hovered, index < model.actions.count {
            return model.actions[index].title.uppercased()
        }
        return model.summary
    }
}

struct RadialSegment: View {
    let action: FileAction
    let index: Int
    let count: Int
    let hovered: Bool
    let visible: Bool

    var body: some View {
        let span = 360.0 / Double(count)
        let mid = RadialGeometry.angle(of: index, count: count)
        let shape = RoundedSector(
            start: mid - span / 2,
            end: mid + span / 2,
            inner: RadialGeometry.inner,
            outer: RadialGeometry.outer,
            corner: 14,
            gap: 7
        )
        let radians = mid * .pi / 180
        let labelRadius = (RadialGeometry.inner + RadialGeometry.outer) / 2 + 2
        let push: CGFloat = hovered ? 7 : 0
        let hot = LinearGradient(colors: [Color(hex: 0xFF7A45), Color(hex: 0xF0302A)], startPoint: .topLeading, endPoint: .bottomTrailing)

        ZStack {
            Color.clear
                .liquidGlass(
                    shape,
                    tint: hovered ? Color(hex: 0xFF4A1F, opacity: 0.85) : Color(hex: 0xFFE2CC, opacity: 0.3),
                    fallback: hovered ? AnyShapeStyle(hot) : AnyShapeStyle(Color(hex: 0xFFE4D0, opacity: 0.62))
                )
                .shadow(color: hovered ? Color(hex: 0xFF4A1F, opacity: 0.55) : .clear, radius: 14)

            VStack(spacing: 5) {
                if let symbol = action.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(action.title.uppercased())
                    .font(.system(size: count > 5 ? 9.5 : 11.5, weight: .bold))
                    .tracking(0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 80)
            .foregroundStyle(hovered ? Color.white : Color.ink)
            .offset(x: cos(radians) * labelRadius, y: sin(radians) * labelRadius)
        }
        .frame(width: RadialGeometry.size, height: RadialGeometry.size)
        .offset(x: cos(radians) * push, y: sin(radians) * push)
        .scaleEffect(visible ? 1 : 0.7)
        .opacity(visible ? 1 : 0)
        .animation(.spring(response: 0.36, dampingFraction: 0.7).delay(Double(index) * 0.018), value: visible)
    }
}

struct CenterLens: View {
    let title: String
    let subtitle: String?

    var body: some View {
        let diameter = (RadialGeometry.inner - 8) * 2
        ZStack {
            Color.clear
                .liquidGlass(Circle(), tint: Color.white.opacity(0.12), fallback: AnyShapeStyle(Color.white.opacity(0.32)))
                .frame(width: diameter, height: diameter)
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.9)))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.ink.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(width: diameter - 12)
        }
    }
}

/// A ring sector with rounded corners and a constant-width gap to its neighbours.
///
/// Built as an inset sector whose straight sides run parallel to the neighbouring boundary rays,
/// then grown outward by `corner` (each corner becomes an arc of that radius).
struct RoundedSector: Shape {
    var start: Double  // degrees, SwiftUI convention
    var end: Double
    var inner: CGFloat
    var outer: CGFloat
    var corner: CGFloat
    var gap: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let c = corner
        let a = inner + c
        let b = outer - c
        let d = gap / 2 + c
        guard a > d, b > a, end > start else { return Path() }

        let p1 = start * .pi / 180
        let p2 = end * .pi / 180
        let sb = Double(asin(d / b))
        let sa = Double(asin(d / a))
        func point(_ angle: Double, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
        let e1 = point(p1 + sb, b)
        let e2 = point(p2 - sb, b)
        let i1 = point(p1 + sa, a)
        let i2 = point(p2 - sa, a)

        var path = Path()
        path.addArc(center: center, radius: b + c, startAngle: .radians(p1 + sb), endAngle: .radians(p2 - sb), clockwise: false)
        path.addArc(center: e2, radius: c, startAngle: .radians(p2 - sb), endAngle: .radians(p2 + .pi / 2), clockwise: false)
        path.addArc(center: i2, radius: c, startAngle: .radians(p2 + .pi / 2), endAngle: .radians(p2 - sa + .pi), clockwise: false)
        path.addArc(center: center, radius: a - c, startAngle: .radians(p2 - sa), endAngle: .radians(p1 + sa), clockwise: true)
        path.addArc(center: i1, radius: c, startAngle: .radians(p1 + sa + .pi), endAngle: .radians(p1 + 1.5 * .pi), clockwise: false)
        path.addArc(center: e1, radius: c, startAngle: .radians(p1 - .pi / 2), endAngle: .radians(p1 + sb), clockwise: false)
        path.closeSubpath()
        return path
    }
}
