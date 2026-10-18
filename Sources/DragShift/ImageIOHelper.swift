import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}

extension CGColor {
    static func hex(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

enum ImageIOHelper {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func context(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: max(width, 1),
            height: max(height, 1),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// Loads an image at full resolution with its EXIF orientation applied.
    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func downscaled(_ image: CGImage, maxSide: CGFloat) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = maxSide / max(width, height)
        guard scale < 1 else { return image }
        let newWidth = Int((width * scale).rounded())
        let newHeight = Int((height * scale).rounded())
        guard let ctx = context(width: newWidth, height: newHeight) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return ctx.makeImage() ?? image
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    static func flattened(_ image: CGImage) -> CGImage {
        guard let ctx = context(width: image.width, height: image.height) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage() ?? image
    }

    /// Format to save edits in: keep JPEG/HEIC/PNG, fall back to PNG for everything else.
    static func outputType(for url: URL) -> UTType {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "heic", "heif": return .heic
        default: return .png
        }
    }

    static func fileExtension(for type: UTType) -> String {
        if type == .jpeg { return "jpg" }
        return type.preferredFilenameExtension ?? "png"
    }

    static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double = 0.92) throws {
        let output = (type == .jpeg && hasAlpha(image)) ? flattened(image) : image
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw EngineError.writeFailed(url.lastPathComponent)
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, output, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw EngineError.writeFailed(url.lastPathComponent)
        }
    }
}
