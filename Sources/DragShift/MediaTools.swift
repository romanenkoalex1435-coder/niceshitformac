import AppKit
import AVFoundation
import CoreImage
import PDFKit
import UniformTypeIdentifiers
import Vision

enum PDFTools {
    static func compress(_ url: URL) throws -> URL {
        let document = try open(url)
        let output = Engine.outputURL(next: url, suffix: "Compressed", ext: "pdf")
        var options: [PDFDocumentWriteOption: Any] = [:]
        if #available(macOS 13.4, *) {
            options[.saveImagesAsJPEGOption] = true
            options[.optimizeImagesForScreenOption] = true
        }
        guard document.write(to: output, withOptions: options) else { throw EngineError.writeFailed(output.lastPathComponent) }
        return output
    }

    static func split(_ url: URL) throws -> [URL] {
        let document = try open(url)
        guard document.pageCount > 1 else { throw EngineError.toolFailed("“\(url.lastPathComponent)” has only one page.") }
        var outputs: [URL] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index)?.copy() as? PDFPage else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            let output = Engine.outputURL(next: url, suffix: "p\(index + 1)", ext: "pdf")
            guard single.write(to: output) else { throw EngineError.writeFailed(output.lastPathComponent) }
            outputs.append(output)
        }
        return outputs
    }

    static func merge(_ urls: [URL]) throws -> URL {
        guard let first = urls.first else { return URL(fileURLWithPath: "/") }
        let merged = try open(first)
        for url in urls.dropFirst() {
            let document = try open(url)
            for index in 0..<document.pageCount {
                if let page = document.page(at: index)?.copy() as? PDFPage {
                    merged.insert(page, at: merged.pageCount)
                }
            }
        }
        let output = Engine.outputURL(next: first, suffix: "Merged", ext: "pdf")
        guard merged.write(to: output) else { throw EngineError.writeFailed(output.lastPathComponent) }
        return output
    }

    static func rotate(_ url: URL) throws -> URL {
        let document = try open(url)
        for index in 0..<document.pageCount {
            if let page = document.page(at: index) {
                page.rotation = (page.rotation + 90) % 360
            }
        }
        let output = Engine.outputURL(next: url, suffix: "Rotated", ext: "pdf")
        guard document.write(to: output) else { throw EngineError.writeFailed(output.lastPathComponent) }
        return output
    }

    static func protect(_ url: URL, password: String) throws -> URL {
        let document = try open(url)
        let output = Engine.outputURL(next: url, suffix: "Locked", ext: "pdf")
        let options: [PDFDocumentWriteOption: Any] = [.userPasswordOption: password, .ownerPasswordOption: password]
        guard document.write(to: output, withOptions: options) else { throw EngineError.writeFailed(output.lastPathComponent) }
        return output
    }

    /// Text layer if the PDF has one, otherwise OCR of the rendered pages (scans).
    static func text(_ url: URL) throws -> String {
        let document = try open(url)
        let embedded = (document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !embedded.isEmpty { return embedded }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let image = PDFConverter.render(page, scale: 2) else { continue }
            pages.append(try VisionTools.text(in: image))
        }
        return pages.joined(separator: "\n\n")
    }

    /// One PDF page per image, each fitted to A4-ish size.
    static func fromImages(_ urls: [URL]) throws -> URL {
        guard let first = urls.first else { return URL(fileURLWithPath: "/") }
        let document = PDFDocument()
        for url in urls {
            guard let image = ImageIOHelper.load(url) else { throw EngineError.unreadable(url.lastPathComponent) }
            let longSide = CGFloat(max(image.width, image.height))
            let scale = 842 / longSide
            let size = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            if let page = PDFPage(image: NSImage(cgImage: image, size: size)) {
                document.insert(page, at: document.pageCount)
            }
        }
        let output = Engine.outputURL(next: first, suffix: urls.count > 1 ? "Combined" : nil, ext: "pdf")
        guard document.write(to: output) else { throw EngineError.writeFailed(output.lastPathComponent) }
        return output
    }

    private static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw EngineError.unreadable(url.lastPathComponent) }
        return document
    }
}

enum VisionTools {
    private static let context = CIContext()

    static func text(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ru-RU", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// Lifts the main subject(s) off the background, like "Copy Subject" in Photos.
    @available(macOS 14.0, *)
    static func removeBackground(_ image: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let result = request.results?.first else {
            throw EngineError.toolFailed("Couldn't find a subject in this image.")
        }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
        let masked = CIImage(cvPixelBuffer: buffer)
        guard let output = context.createCGImage(masked, from: masked.extent) else {
            throw EngineError.toolFailed("Couldn't render the cut-out.")
        }
        return output
    }
}

enum VideoTools {
    static func export(_ url: URL, preset: String, fileType: AVFileType, suffix: String?, ext: String) throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw EngineError.toolFailed("“\(url.lastPathComponent)” can't be exported this way.")
        }
        let sameName = suffix == nil && url.pathExtension.lowercased() == ext
        let output = Engine.outputURL(next: url, suffix: sameName ? "Converted" : suffix, ext: ext)
        session.outputURL = output
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = true
        let done = DispatchSemaphore(value: 0)
        session.exportAsynchronously { done.signal() }
        done.wait()
        guard session.status == .completed else {
            throw EngineError.toolFailed(session.error?.localizedDescription ?? "Video export failed.")
        }
        return output
    }

    /// First 15 seconds at 12 fps, max 540 px — a size that still fits in a chat message.
    static func gif(_ url: URL) throws -> URL {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0 else { throw EngineError.unreadable(url.lastPathComponent) }
        let fps = 12.0
        let frameCount = max(1, Int(min(duration, 15) * fps))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 540, height: 540)
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        var frames: [CGImage] = []
        for index in 0..<frameCount {
            let time = CMTime(seconds: Double(index) / fps, preferredTimescale: 600)
            if let frame = try? generator.copyCGImage(at: time, actualTime: nil) {
                frames.append(frame)
            }
        }
        guard !frames.isEmpty else { throw EngineError.unreadable(url.lastPathComponent) }

        let output = Engine.outputURL(next: url, suffix: nil, ext: "gif")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw EngineError.writeFailed(output.lastPathComponent)
        }
        let fileProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]] as CFDictionary
        CGImageDestinationSetProperties(destination, fileProperties)
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { throw EngineError.writeFailed(output.lastPathComponent) }
        return output
    }
}
