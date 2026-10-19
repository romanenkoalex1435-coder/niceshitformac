import AppKit
import CoreImage
import SwiftUI
import UniformTypeIdentifiers

struct BackgroundPreset: Hashable, Identifiable {
    enum Kind: Hashable {
        /// Empty = transparent, one color = solid, more = diagonal gradient.
        case colors([UInt32])
        /// The photo itself, heavily blurred — the popular "Apple keynote" look.
        case blurredImage
        /// A picture chosen by the user.
        case customImage
    }

    let id: String
    let kind: Kind
}

enum BackgroundPresets {
    static let gradients: [BackgroundPreset] = [
        [0xFF5A3C, 0xFFB443, 0xA06CD5],
        [0xFF5F6D, 0xFFC371],
        [0xF8B195, 0xF67280, 0xC06C84],
        [0xA18CD1, 0xFBC2EB],
        [0x2193B0, 0x6DD5ED],
        [0x43E97B, 0x38F9D7],
        [0xFA8BFF, 0x2BD2FF, 0x2BFF88],
        [0xF5EFE6, 0xE3D5C3],
        [0x0F2027, 0x203A43, 0x2C5364],
    ].map { BackgroundPreset(id: $0.map { String($0, radix: 16) }.joined(separator: "-"), kind: .colors($0)) }

    static let solids: [BackgroundPreset] = [0xFFFFFF, 0xF2F2F7, 0x1C1C1E, 0x000000, 0xFF3B30, 0xFF9500, 0x34C759, 0x007AFF]
        .map { BackgroundPreset(id: String($0, radix: 16), kind: .colors([$0])) }

    static let blurred = BackgroundPreset(id: "blurred", kind: .blurredImage)
    static let custom = BackgroundPreset(id: "custom", kind: .customImage)
    static let transparent = BackgroundPreset(id: "clear", kind: .colors([]))

    static var all: [BackgroundPreset] { gradients + [blurred] + solids + [transparent, custom] }
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
    private static let context = CIContext()

    /// `backdrop` is drawn aspect-filled behind the image for the blurred/custom presets.
    static func compose(_ image: CGImage, _ settings: BackgroundSettings, backdrop: CGImage?) -> CGImage? {
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
        ctx.interpolationQuality = .high
        switch settings.preset.kind {
        case .colors(let colors):
            fill(ctx, canvas, colors: colors)
        case .blurredImage, .customImage:
            if let backdrop {
                let scale = max(canvasWidth / CGFloat(backdrop.width), canvasHeight / CGFloat(backdrop.height))
                let width = CGFloat(backdrop.width) * scale
                let height = CGFloat(backdrop.height) * scale
                ctx.draw(backdrop, in: CGRect(x: (canvasWidth - width) / 2, y: (canvasHeight - height) / 2, width: width, height: height))
            } else {
                fill(ctx, canvas, colors: [0xFFFFFF])
            }
        }

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
        ctx.draw(image, in: imageRect)
        ctx.restoreGState()
        return ctx.makeImage()
    }

    /// Heavy blur with a little extra saturation, so the backdrop glows like the photo's own colors.
    static func blurredBackdrop(of image: CGImage) -> CGImage? {
        let small = ImageIOHelper.downscaled(image, maxSide: 600)
        let input = CIImage(cgImage: small)
        let radius = CGFloat(max(small.width, small.height)) / 10
        let output = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.35, kCIInputBrightnessKey: 0.04])
            .cropped(to: input.extent)
        return context.createCGImage(output, from: input.extent)
    }

    private static func fill(_ ctx: CGContext, _ rect: CGRect, colors hexes: [UInt32]) {
        let colors = hexes.map { CGColor.hex($0) }
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
    private let blurredBackdrop: CGImage?

    @State private var settings = BackgroundSettings(
        preset: BackgroundPresets.gradients[0],
        padding: 0.12,
        corner: 0.04,
        shadow: 0.5,
        aspect: .auto
    )
    @State private var customImage: CGImage?

    init(source: URL, image: CGImage, close: @escaping () -> Void) {
        self.source = source
        self.image = image
        self.close = close
        preview = ImageIOHelper.downscaled(image, maxSide: 900)
        blurredBackdrop = Composer.blurredBackdrop(of: image)
    }

    private var backdrop: CGImage? {
        switch settings.preset.kind {
        case .blurredImage: return blurredBackdrop
        case .customImage: return customImage
        case .colors: return nil
        }
    }

    private var longSide: Double { Double(max(image.width, image.height)) }
    private var shortSide: Double { Double(min(image.width, image.height)) }

    var body: some View {
        EditorScaffold(title: "Add BG", saveTitle: "Save PNG", onCancel: close, onSave: save) {
            if let composed = Composer.compose(preview, settings, backdrop: backdrop) {
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
                        Swatch(preset: preset, selected: settings.preset == preset, blurred: blurredBackdrop, custom: customImage)
                            .onTapGesture { select(preset) }
                    }
                }
                SliderRow(title: "Padding", value: $settings.padding, range: 0...0.35) { "\(Int($0 * longSide)) px" }
                SliderRow(title: "Corners", value: $settings.corner, range: 0...0.2) { "\(Int($0 * shortSide)) px" }
                SliderRow(title: "Shadow", value: $settings.shadow, range: 0...1) { "\(Int($0 * longSide * 0.05)) px" }
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

    private func select(_ preset: BackgroundPreset) {
        if preset.kind == .customImage, customImage == nil || settings.preset == preset {
            pickCustomImage()
            return
        }
        settings.preset = preset
    }

    private func pickCustomImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a background picture"
        guard panel.runModal() == .OK, let url = panel.url, let picked = ImageIOHelper.load(url) else { return }
        customImage = ImageIOHelper.downscaled(picked, maxSide: 2400)
        settings.preset = BackgroundPresets.custom
    }

    private func save() {
        guard let output = Composer.compose(image, settings, backdrop: backdrop) else { return }
        if ActionRunner.save(output, source: source, suffix: "With BG", type: .png) {
            close()
        }
    }
}

private struct Swatch: View {
    let preset: BackgroundPreset
    let selected: Bool
    let blurred: CGImage?
    let custom: CGImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(fill)
            .frame(width: 28, height: 28)
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.12), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.accent, lineWidth: selected ? 2.5 : 0).padding(-3))
            .contentShape(Rectangle())
            .help(help)
    }

    @ViewBuilder
    private var content: some View {
        switch preset.kind {
        case .colors(let colors) where colors.isEmpty:
            Image(systemName: "circle.slash")
                .font(.system(size: 13))
                .foregroundStyle(Color.ink.opacity(0.5))
        case .blurredImage:
            if let blurred {
                Image(decorative: blurred, scale: 1).resizable().aspectRatio(contentMode: .fill)
            }
        case .customImage:
            if let custom {
                Image(decorative: custom, scale: 1).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink.opacity(0.6))
            }
        default:
            EmptyView()
        }
    }

    private var fill: AnyShapeStyle {
        guard case .colors(let hexes) = preset.kind else { return AnyShapeStyle(Color.white.opacity(0.7)) }
        let colors = hexes.map { Color(hex: $0) }
        if colors.count > 1 {
            return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .bottomLeading, endPoint: .topTrailing))
        }
        return AnyShapeStyle(colors.first ?? Color.white.opacity(0.7))
    }

    private var help: String {
        switch preset.kind {
        case .blurredImage: return "Blurred photo"
        case .customImage: return "Your own picture (click again to change)"
        case .colors(let colors): return colors.isEmpty ? "Transparent" : "Color"
        }
    }
}
