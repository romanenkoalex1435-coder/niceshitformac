import CoreImage
import SwiftUI

enum MarkTool: String, CaseIterable, Hashable {
    case pen, highlighter, box, arrow, blackout, pixelate, blur

    static let annotate: [MarkTool] = [.pen, .highlighter, .box, .arrow]
    static let redact: [MarkTool] = [.blackout, .pixelate, .blur]

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlight"
        case .box: return "Box"
        case .arrow: return "Arrow"
        case .blackout: return "Black Box"
        case .pixelate: return "Pixelate"
        case .blur: return "Blur"
        }
    }

    var symbol: String {
        switch self {
        case .pen: return "pencil"
        case .highlighter: return "highlighter"
        case .box: return "square"
        case .arrow: return "arrow.up.right"
        case .blackout: return "rectangle.fill"
        case .pixelate: return "square.grid.3x3.fill"
        case .blur: return "drop"
        }
    }

    var isFreehand: Bool { self == .pen || self == .highlighter }
}

struct Mark: Identifiable {
    let id = UUID()
    var tool: MarkTool
    var color: CGColor
    /// Line width as a fraction of the image width, so preview and export match.
    var width: CGFloat
    /// Normalized points (0…1, top-left origin). Shapes use the first and last point.
    var points: [CGPoint]

    struct Drawing {
        let path: CGPath
        let color: CGColor
        let lineWidth: CGFloat
        let filled: Bool
    }

    var bounds: CGRect {
        guard let a = points.first, let b = points.last else { return .zero }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    var isMeaningful: Bool {
        tool.isFreehand ? points.count > 1 : (bounds.width > 0.004 || bounds.height > 0.004)
    }

    /// Vector drawing in a top-left-origin space of the given size.
    func drawings(in size: CGSize) -> [Drawing] {
        let pts = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let lineWidth = max(1, width * size.width)
        let box = CGRect(x: bounds.minX * size.width, y: bounds.minY * size.height, width: bounds.width * size.width, height: bounds.height * size.height)
        switch tool {
        case .pen, .highlighter:
            let path = CGMutablePath()
            path.addLines(between: pts)
            if tool == .highlighter {
                return [Drawing(path: path, color: color.copy(alpha: 0.4) ?? color, lineWidth: lineWidth * 3, filled: false)]
            }
            return [Drawing(path: path, color: color, lineWidth: lineWidth, filled: false)]
        case .box:
            let radius = min(lineWidth, box.width / 2, box.height / 2)
            let path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
            return [Drawing(path: path, color: color, lineWidth: lineWidth, filled: false)]
        case .arrow:
            guard let a = pts.first, let b = pts.last else { return [] }
            let angle = atan2(b.y - a.y, b.x - a.x)
            let head = max(lineWidth * 4, 10)
            let line = CGMutablePath()
            line.move(to: a)
            line.addLine(to: CGPoint(x: b.x - cos(angle) * head * 0.6, y: b.y - sin(angle) * head * 0.6))
            let tip = CGMutablePath()
            tip.move(to: b)
            tip.addLine(to: CGPoint(x: b.x - head * cos(angle - .pi / 7), y: b.y - head * sin(angle - .pi / 7)))
            tip.addLine(to: CGPoint(x: b.x - head * cos(angle + .pi / 7), y: b.y - head * sin(angle + .pi / 7)))
            tip.closeSubpath()
            return [
                Drawing(path: line, color: color, lineWidth: lineWidth, filled: false),
                Drawing(path: tip, color: color, lineWidth: 0, filled: true),
            ]
        case .blackout:
            return [Drawing(path: CGPath(rect: box, transform: nil), color: CGColor(gray: 0.05, alpha: 1), lineWidth: 0, filled: true)]
        case .pixelate, .blur:
            return []
        }
    }
}

enum Redactor {
    static let context = CIContext()

    static func pixelated(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let scale = max(CGFloat(image.width), CGFloat(image.height)) / 48
        let output = input.clampedToExtent()
            .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: scale, kCIInputCenterKey: CIVector(x: 0, y: 0)])
            .cropped(to: input.extent)
        return context.createCGImage(output, from: input.extent)
    }

    static func blurred(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let radius = max(CGFloat(image.width), CGFloat(image.height)) / 50
        let output = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: input.extent)
        return context.createCGImage(output, from: input.extent)
    }

    /// Full-resolution export of the base image with all marks applied.
    static func render(base: CGImage, marks: [Mark]) -> CGImage? {
        let width = CGFloat(base.width)
        let height = CGFloat(base.height)
        guard let ctx = ImageIOHelper.context(width: base.width, height: base.height) else { return nil }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.draw(base, in: full)

        let pixelLayer = marks.contains { $0.tool == .pixelate } ? pixelated(base) : nil
        let blurLayer = marks.contains { $0.tool == .blur } ? blurred(base) : nil
        for mark in marks where mark.tool == .pixelate || mark.tool == .blur {
            guard let layer = mark.tool == .pixelate ? pixelLayer : blurLayer else { continue }
            let b = mark.bounds
            let area = CGRect(x: b.minX * width, y: (1 - b.maxY) * height, width: b.width * width, height: b.height * height)
            ctx.saveGState()
            ctx.clip(to: area)
            ctx.draw(layer, in: full)
            ctx.restoreGState()
        }

        // Marks are defined top-down; flip to match.
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for mark in marks {
            for drawing in mark.drawings(in: CGSize(width: width, height: height)) {
                ctx.addPath(drawing.path)
                if drawing.filled {
                    ctx.setFillColor(drawing.color)
                    ctx.fillPath()
                } else {
                    ctx.setStrokeColor(drawing.color)
                    ctx.setLineWidth(drawing.lineWidth)
                    ctx.strokePath()
                }
            }
        }
        return ctx.makeImage()
    }
}

struct MarkupEditor: View {
    enum Mode { case annotate, redact }

    static let palette: [CGColor] = [0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759, 0x007AFF, 0xAF52DE, 0x1C1C1E, 0xFFFFFF]
        .map { CGColor.hex($0) }

    let mode: Mode
    let source: URL
    let image: CGImage
    let close: () -> Void
    private let preview: CGImage
    private let pixelPreview: CGImage?
    private let blurPreview: CGImage?

    @State private var marks: [Mark] = []
    @State private var current: Mark?
    @State private var tool: MarkTool
    @State private var colorIndex = 0
    @State private var lineWidth = 6.0

    init(mode: Mode, source: URL, image: CGImage, close: @escaping () -> Void) {
        self.mode = mode
        self.source = source
        self.image = image
        self.close = close
        let preview = ImageIOHelper.downscaled(image, maxSide: 1400)
        self.preview = preview
        pixelPreview = mode == .redact ? Redactor.pixelated(preview) : nil
        blurPreview = mode == .redact ? Redactor.blurred(preview) : nil
        _tool = State(initialValue: mode == .annotate ? .pen : .blackout)
    }

    private var allMarks: [Mark] {
        if let current { return marks + [current] }
        return marks
    }

    var body: some View {
        EditorScaffold(title: mode == .annotate ? "Annotate" : "Redact", onCancel: close, onSave: save) {
            GeometryReader { geo in
                let fit = fittedRect(imageSize: CGSize(width: preview.width, height: preview.height), in: geo.size, inset: 16)
                ZStack {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: fit.width, height: fit.height)
                        .position(x: fit.midX, y: fit.midY)

                    if let pixelPreview {
                        effectLayer(pixelPreview, tool: .pixelate, fit: fit)
                    }
                    if let blurPreview {
                        effectLayer(blurPreview, tool: .blur, fit: fit)
                    }

                    Canvas { context, size in
                        for mark in allMarks {
                            for drawing in mark.drawings(in: size) {
                                let path = Path(drawing.path)
                                let color = Color(cgColor: drawing.color)
                                if drawing.filled {
                                    context.fill(path, with: .color(color))
                                } else {
                                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: drawing.lineWidth, lineCap: .round, lineJoin: .round))
                                }
                            }
                        }
                        if let current, current.tool == .pixelate || current.tool == .blur {
                            let b = current.bounds
                            let area = CGRect(x: b.minX * size.width, y: b.minY * size.height, width: b.width * size.width, height: b.height * size.height)
                            context.stroke(Path(area), with: .color(.white), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                    }
                    .frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)
                    .allowsHitTesting(false)

                    Color.white.opacity(0.001)
                        .frame(width: fit.width, height: fit.height)
                        .contentShape(Rectangle())
                        .gesture(drawGesture(fit: fit))
                        .position(x: fit.midX, y: fit.midY)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        } controls: {
            controls
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(mode == .annotate ? MarkTool.annotate : MarkTool.redact, id: \.self) { item in
                    ToolChip(title: item.title, symbol: item.symbol, selected: tool == item) { tool = item }
                }
                Spacer()
                ToolChip(title: "Undo", symbol: "arrow.uturn.backward", selected: false) {
                    if !marks.isEmpty { marks.removeLast() }
                }
                .keyboardShortcut("z", modifiers: .command)
                ToolChip(title: "Clear", symbol: nil, selected: false) { marks.removeAll() }
            }
            if mode == .annotate {
                HStack(spacing: 10) {
                    ForEach(Self.palette.indices, id: \.self) { index in
                        Circle()
                            .fill(Color(cgColor: Self.palette[index]))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 1))
                            .overlay(Circle().stroke(Color.accent, lineWidth: colorIndex == index ? 2.5 : 0).padding(-3))
                            .contentShape(Circle())
                            .onTapGesture { colorIndex = index }
                    }
                }
                SliderRow(title: "Thickness", value: $lineWidth, range: 2...30)
            }
        }
    }

    private func effectLayer(_ layer: CGImage, tool: MarkTool, fit: CGRect) -> some View {
        let areas = allMarks.filter { $0.tool == tool }.map(\.bounds)
        return Image(decorative: layer, scale: 1)
            .resizable()
            .frame(width: fit.width, height: fit.height)
            .mask { NormalizedRects(rects: areas) }
            .position(x: fit.midX, y: fit.midY)
            .allowsHitTesting(false)
    }

    private func drawGesture(fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = CGPoint(x: clamp(value.location.x / fit.width, 0, 1), y: clamp(value.location.y / fit.height, 0, 1))
                if current == nil {
                    current = Mark(tool: tool, color: Self.palette[colorIndex], width: lineWidth / 1000, points: [point])
                } else if tool.isFreehand {
                    current?.points.append(point)
                } else if let first = current?.points.first {
                    current?.points = [first, point]
                }
            }
            .onEnded { _ in
                if let mark = current, mark.isMeaningful {
                    marks.append(mark)
                }
                current = nil
            }
    }

    private func save() {
        guard let output = Redactor.render(base: image, marks: marks) else { return }
        if ActionRunner.save(output, source: source, suffix: mode == .annotate ? "Annotated" : "Redacted") {
            close()
        }
    }
}

private struct NormalizedRects: Shape {
    var rects: [CGRect]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for area in rects {
            path.addRect(CGRect(
                x: rect.minX + area.minX * rect.width,
                y: rect.minY + area.minY * rect.height,
                width: area.width * rect.width,
                height: area.height * rect.height
            ))
        }
        return path
    }
}
