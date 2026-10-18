import SwiftUI

struct BackgroundPreset: Hashable, Identifiable {
    let id: String
    /// Empty = transparent, one color = solid, more = diagonal gradient.
    let colors: [UInt32]
}

enum BackgroundPresets {
    static let gradients: [BackgroundPreset] = [
        BackgroundPreset(id: "sonoma", colors: [0xFF5A3C, 0xFFB443, 0xA06CD5]),
        BackgroundPreset(id: "sunset", colors: [0xFF5F6D, 0xFFC371]),
        BackgroundPreset(id: "peach", colors: [0xF8B195, 0xF67280, 0xC06C84]),
        BackgroundPreset(id: "lavender", colors: [0xA18CD1, 0xFBC2EB]),
        BackgroundPreset(id: "ocean", colors: [0x2193B0, 0x6DD5ED]),
        BackgroundPreset(id: "mint", colors: [0x43E97B, 0x38F9D7]),
        BackgroundPreset(id: "aurora", colors: [0xFA8BFF, 0x2BD2FF, 0x2BFF88]),
        BackgroundPreset(id: "linen", colors: [0xF5EFE6, 0xE3D5C3]),
        BackgroundPreset(id: "night", colors: [0x0F2027, 0x203A43, 0x2C5364]),
    ]

    static let solids: [BackgroundPreset] = [0xFFFFFF, 0xF2F2F7, 0x1C1C1E, 0x000000, 0xFF3B30, 0xFF9500, 0x34C759, 0x007AFF, 0xAF52DE]
        .map { BackgroundPreset(id: String($0, radix: 16), colors: [$0]) }

    static let transparent = BackgroundPreset(id: "clear", colors: [])

    static var all: [BackgroundPreset] { gradients + solids + [transparent] }
}

enum CanvasAspect: String, CaseIterable, Hashable {
    case auto = "Auto"
    case square = "1:1"
    case fourThree = "4:3"
    case sixteenNine = "16:9"
    case nineSixteen = "9:16"

    var ratio: CGFloat? {
        switch self {
        case .auto: return nil
        case .square: return 1
        case .fourThree: return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        case .nineSixteen: return 9.0 / 16.0
        }
    }
}

struct BackgroundSettings {
    var preset: BackgroundPreset
    var padding: Double
    var corner: Double
    var shadow: Double
    var aspect: CanvasAspect
}

enum Composer {
    static func compose(_ image: CGImage, _ settings: BackgroundSettings) -> CGImage? {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let longSide = max(imageWidth, imageHeight)
        let padding = CGFloat(settings.padding) * longSide
        var canvasWidth = imageWidth + padding * 2
        var canvasHeight = imageHeight + padding * 2
        if let ratio = settings.aspect.ratio {
            if canvasWidth / canvasHeight < ratio {
                canvasWidth = canvasHeight * ratio
            } else {
                canvasHeight = canvasWidth / ratio
            }
        }
        guard let ctx = ImageIOHelper.context(width: Int(canvasWidth.rounded()), height: Int(canvasHeight.rounded())) else { return nil }
        let canvas = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        fillBackground(ctx, canvas, settings.preset)

        let imageRect = CGRect(x: (canvasWidth - imageWidth) / 2, y: (canvasHeight - imageHeight) / 2, width: imageWidth, height: imageHeight)
        let shortSide = min(imageWidth, imageHeight)
        let radius = min(CGFloat(settings.corner) * shortSide, shortSide / 2)
        let path = CGPath(roundedRect: imageRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        if settings.shadow > 0 {
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -CGFloat(settings.shadow) * longSide * 0.015),
                blur: CGFloat(settings.shadow) * longSide * 0.05,
                color: CGColor(gray: 0, alpha: 0.45)
            )
            ctx.addPath(path)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.interpolationQuality = .high
        ctx.draw(image, in: imageRect)
        ctx.restoreGState()
        return ctx.makeImage()
    }

    private static func fillBackground(_ ctx: CGContext, _ rect: CGRect, _ preset: BackgroundPreset) {
        let colors = preset.colors.map { CGColor.hex($0) }
        guard let first = colors.first else { return }
        guard colors.count > 1 else {
            ctx.setFillColor(first)
            ctx.fill(rect)
            return
        }
        if let gradient = CGGradient(colorsSpace: ImageIOHelper.sRGB, colors: colors as CFArray, locations: nil) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.minX, y: rect.maxY),
                end: CGPoint(x: rect.maxX, y: rect.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        // Soft light bloom for a less flat, wallpaper-like look.
        let glowColors = [CGColor(gray: 1, alpha: 0.28), CGColor(gray: 1, alpha: 0)] as CFArray
        if let glow = CGGradient(colorsSpace: ImageIOHelper.sRGB, colors: glowColors, locations: [0, 1]) {
            let center = CGPoint(x: rect.width * 0.25, y: rect.height * 0.8)
            ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: max(rect.width, rect.height) * 0.6, options: [])
        }
    }
}

struct BackgroundEditor: View {
    let source: URL
    let image: CGImage
    let close: () -> Void
    private let preview: CGImage

    @State private var settings = BackgroundSettings(
        preset: BackgroundPresets.gradients[0],
        padding: 0.12,
        corner: 0.04,
        shadow: 0.5,
        aspect: .auto
    )

    init(source: URL, image: CGImage, close: @escaping () -> Void) {
        self.source = source
        self.image = image
        self.close = close
        preview = ImageIOHelper.downscaled(image, maxSide: 900)
    }

    var body: some View {
        EditorScaffold(title: "Add BG", saveTitle: "Save PNG", onCancel: close, onSave: save) {
            if let composed = Composer.compose(preview, settings) {
                Image(decorative: composed, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
            }
        } controls: {
            VStack(alignment: .leading, spacing: 10) {
                Text("Background")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.ink.opacity(0.65))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 10), alignment: .leading, spacing: 8) {
                    ForEach(BackgroundPresets.all) { preset in
                        Swatch(preset: preset, selected: settings.preset == preset)
                            .onTapGesture { settings.preset = preset }
                    }
                }
                SliderRow(title: "Padding", value: $settings.padding, range: 0...0.35)
                SliderRow(title: "Corners", value: $settings.corner, range: 0...0.2)
                SliderRow(title: "Shadow", value: $settings.shadow, range: 0...1)
                HStack(spacing: 10) {
                    Text("Canvas")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.ink.opacity(0.65))
                        .frame(width: 78, alignment: .leading)
                    ChipPicker(options: CanvasAspect.allCases, title: \.rawValue, selection: $settings.aspect)
                }
            }
        }
    }

    private func save() {
        guard let output = Composer.compose(image, settings) else { return }
        if ActionRunner.save(output, source: source, suffix: "With BG", type: .png) {
            close()
        }
    }
}

private struct Swatch: View {
    let preset: BackgroundPreset
    let selected: Bool

    var body: some View {
        let colors = preset.colors.map { Color(hex: $0) }
        RoundedRectangle(cornerRadius: 7)
            .fill(fill(colors))
            .frame(width: 28, height: 28)
            .overlay {
                if colors.isEmpty {
                    Image(systemName: "circle.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ink.opacity(0.5))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.12), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.accent, lineWidth: selected ? 2.5 : 0).padding(-3))
            .contentShape(Rectangle())
    }

    private func fill(_ colors: [Color]) -> AnyShapeStyle {
        if colors.count > 1 {
            return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .bottomLeading, endPoint: .topTrailing))
        }
        return AnyShapeStyle(colors.first ?? Color.white.opacity(0.7))
    }
}
