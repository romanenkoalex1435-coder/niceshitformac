import CoreImage
import SwiftUI

struct Adjustments: Equatable {
    var brightness = 0.0
    var contrast = 1.0
    var saturation = 1.0
    var exposure = 0.0
    var vibrance = 0.0
    var sharpness = 0.0
    var quarterTurns = 0
    var flipped = false
}

enum Adjuster {
    static let context = CIContext()

    static func apply(_ adjustments: Adjustments, to image: CGImage) -> CGImage? {
        var output = CIImage(cgImage: image)
        let extent = output.extent
        output = output.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: adjustments.brightness,
            kCIInputContrastKey: adjustments.contrast,
            kCIInputSaturationKey: adjustments.saturation,
        ])
        if adjustments.exposure != 0 {
            output = output.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: adjustments.exposure])
        }
        if adjustments.vibrance != 0 {
            output = output.applyingFilter("CIVibrance", parameters: ["inputAmount": adjustments.vibrance])
        }
        if adjustments.sharpness > 0 {
            output = output.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: adjustments.sharpness])
        }
        output = output.cropped(to: extent)
        for _ in 0..<(adjustments.quarterTurns % 4) {
            output = output.oriented(.right)
        }
        if adjustments.flipped {
            output = output.oriented(.upMirrored)
        }
        return context.createCGImage(output, from: output.extent)
    }
}

struct AdjustEditor: View {
    let source: URL
    let image: CGImage
    let close: () -> Void
    private let preview: CGImage

    @State private var adjustments = Adjustments()

    init(source: URL, image: CGImage, close: @escaping () -> Void) {
        self.source = source
        self.image = image
        self.close = close
        preview = ImageIOHelper.downscaled(image, maxSide: 1000)
    }

    var body: some View {
        EditorScaffold(title: "Edit", onCancel: close, onSave: save) {
            if let rendered = Adjuster.apply(adjustments, to: preview) {
                Image(decorative: rendered, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
            }
        } controls: {
            VStack(alignment: .leading, spacing: 8) {
                SliderRow(title: "Exposure", value: $adjustments.exposure, range: -1.5...1.5)
                SliderRow(title: "Brightness", value: $adjustments.brightness, range: -0.4...0.4)
                SliderRow(title: "Contrast", value: $adjustments.contrast, range: 0.5...1.5)
                SliderRow(title: "Saturation", value: $adjustments.saturation, range: 0...2)
                SliderRow(title: "Vibrance", value: $adjustments.vibrance, range: -1...1)
                SliderRow(title: "Sharpness", value: $adjustments.sharpness, range: 0...2)
                HStack(spacing: 6) {
                    ToolChip(title: "Rotate", symbol: "rotate.right", selected: false) {
                        adjustments.quarterTurns = (adjustments.quarterTurns + 1) % 4
                    }
                    ToolChip(title: "Flip", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", selected: adjustments.flipped) {
                        adjustments.flipped.toggle()
                    }
                    Spacer()
                    ToolChip(title: "Reset", symbol: "arrow.counterclockwise", selected: false) {
                        adjustments = Adjustments()
                    }
                }
            }
        }
    }

    private func save() {
        guard let output = Adjuster.apply(adjustments, to: image) else { return }
        if ActionRunner.save(output, source: source, suffix: "Edited") {
            close()
        }
    }
}
