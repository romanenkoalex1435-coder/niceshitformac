import SwiftUI

struct RadialMenuView: View {
    @ObservedObject var model: RadialModel

    var body: some View {
        let count = model.actions.count
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(Color(hex: 0xFFE6D5, opacity: 0.35)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
                .frame(width: (RadialGeometry.outer + 10) * 2, height: (RadialGeometry.outer + 10) * 2)
                .shadow(color: .black.opacity(0.28), radius: 30, y: 14)

            ForEach(Array(model.actions.enumerated()), id: \.offset) { index, action in
                RadialSegment(action: action, index: index, count: count, hovered: model.hovered == index)
            }

            centerBadge
        }
        .frame(width: RadialGeometry.size, height: RadialGeometry.size)
        .scaleEffect(model.visible ? 1 : 0.55)
        .opacity(model.visible ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: model.visible)
        .animation(.easeOut(duration: 0.12), value: model.hovered)
    }

    private var centerBadge: some View {
        let hoveredTitle = model.hovered.flatMap { $0 < model.actions.count ? model.actions[$0].title : nil }
        let diameter = (RadialGeometry.inner - 8) * 2
        return ZStack {
            Circle().fill(Color.white.opacity(0.92))
            Text(hoveredTitle ?? model.summary)
                .font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: 0x3A2A22))
                .padding(6)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}

struct RadialSegment: View {
    let action: FileAction
    let index: Int
    let count: Int
    let hovered: Bool

    var body: some View {
        let span = 360.0 / Double(count)
        let mid = RadialGeometry.angle(of: index, count: count)
        let shape = AnnularSector(
            start: .degrees(mid - span / 2),
            end: .degrees(mid + span / 2),
            inner: RadialGeometry.inner,
            outer: RadialGeometry.outer
        )
        let labelRadius = (RadialGeometry.inner + RadialGeometry.outer) / 2 + 4
        let radians = mid * .pi / 180
        let hot = LinearGradient(colors: [Color(hex: 0xFF7A45), Color(hex: 0xF0302A)], startPoint: .topLeading, endPoint: .bottomTrailing)

        ZStack {
            shape.fill(hovered ? AnyShapeStyle(hot) : AnyShapeStyle(Color(hex: 0xF9DCC8, opacity: 0.94)))
            shape.stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            VStack(spacing: 5) {
                if let symbol = action.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(action.title.uppercased())
                    .font(.system(size: count > 4 ? 9.5 : 12, weight: .bold))
                    .tracking(0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 84)
            .foregroundStyle(hovered ? Color.white : Color(hex: 0x3A2A22))
            .offset(x: cos(radians) * labelRadius, y: sin(radians) * labelRadius)
        }
        .frame(width: RadialGeometry.size, height: RadialGeometry.size)
        .scaleEffect(hovered ? 1.04 : 1)
    }
}

struct AnnularSector: Shape {
    var start: Angle
    var end: Angle
    var inner: CGFloat
    var outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}
