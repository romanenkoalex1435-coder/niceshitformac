import AppKit
import CoreText
import PDFKit
import UniformTypeIdentifiers

enum EngineError: LocalizedError {
    case unreadable(String)
    case writeFailed(String)
    case toolFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "Couldn't read “\(name)”."
        case .writeFailed(let name): return "Couldn't write “\(name)”."
        case .toolFailed(let message): return message
        }
    }
}

/// Non-interactive conversions. Every function writes next to the source and returns the new files.
enum Engine {
    static func perform(_ action: FileAction, on url: URL) throws -> [URL] {
        switch action {
        case .pdfTo(let format):
            return try PDFConverter.convert(url, to: format)
        case .textTo(let format):
            return [try TextConverter.convert(url, to: format)]
        case .compress:
            guard let image = ImageIOHelper.load(url) else { throw EngineError.unreadable(url.lastPathComponent) }
            let output = outputURL(next: url, suffix: "Compressed", ext: "jpg")
            try ImageIOHelper.write(ImageIOHelper.downscaled(image, maxSide: 2560), to: output, type: .jpeg, quality: 0.72)
            return [output]
        case .stripMetadata:
            // Re-encoding without properties drops EXIF, GPS and camera data; orientation is baked in.
            guard let image = ImageIOHelper.load(url) else { throw EngineError.unreadable(url.lastPathComponent) }
            let type = ImageIOHelper.outputType(for: url)
            let output = outputURL(next: url, suffix: "Clean", ext: ImageIOHelper.fileExtension(for: type))
            try ImageIOHelper.write(image, to: output, type: type, quality: 0.95)
            return [output]
        case .convertImage(let format):
            guard let image = ImageIOHelper.load(url) else { throw EngineError.unreadable(url.lastPathComponent) }
            let type: UTType = format == .png ? .png : .jpeg
            let output = outputURL(next: url, suffix: nil, ext: format.rawValue)
            try ImageIOHelper.write(image, to: output, type: type)
            return [output]
        case .zip:
            let output = uniqueURL(in: url.deletingLastPathComponent(), base: url.lastPathComponent, ext: "zip")
            try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", url.path, output.path])
            return [output]
        case .duplicate:
            let output = outputURL(next: url, suffix: "copy", ext: url.pathExtension)
            try FileManager.default.copyItem(at: url, to: output)
            return [output]
        case .crop, .addBackground, .adjust, .annotate, .redact, .copyPath:
            return []
        }
    }

    /// "Page 001.pdf" + suffix "Cropped" + "jpg" → "Page 001 Cropped.jpg" (or "… 2.jpg" if taken).
    static func outputURL(next source: URL, suffix: String?, ext: String) -> URL {
        var base = source.deletingPathExtension().lastPathComponent
        if let suffix { base += " " + suffix }
        return uniqueURL(in: source.deletingLastPathComponent(), base: base, ext: ext)
    }

    static func uniqueURL(in directory: URL, base: String, ext: String) -> URL {
        func make(_ name: String) -> URL {
            let url = directory.appendingPathComponent(name)
            return ext.isEmpty ? url : url.appendingPathExtension(ext)
        }
        var url = make(base)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = make("\(base) \(counter)")
            counter += 1
        }
        return url
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw EngineError.toolFailed("\(URL(fileURLWithPath: tool).lastPathComponent) failed with code \(process.terminationStatus).")
        }
    }
}

enum PDFConverter {
    static func convert(_ url: URL, to format: DocFormat) throws -> [URL] {
        guard let document = PDFDocument(url: url) else { throw EngineError.unreadable(url.lastPathComponent) }
        switch format {
        case .txt:
            let output = Engine.outputURL(next: url, suffix: nil, ext: "txt")
            try (document.string ?? "").write(to: output, atomically: true, encoding: .utf8)
            return [output]
        case .docx:
            let text = NSMutableAttributedString()
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index)?.attributedString else { continue }
                if text.length > 0 { text.append(NSAttributedString(string: "\n\n")) }
                text.append(page)
            }
            let output = Engine.outputURL(next: url, suffix: nil, ext: "docx")
            try TextConverter.write(text, to: output, format: .docx)
            return [output]
        case .png, .jpg:
            let type: UTType = format == .png ? .png : .jpeg
            var outputs: [URL] = []
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index), let image = render(page, scale: 2) else { continue }
                let suffix = document.pageCount > 1 ? "p\(index + 1)" : nil
                let output = Engine.outputURL(next: url, suffix: suffix, ext: format.rawValue)
                try ImageIOHelper.write(image, to: output, type: type)
                outputs.append(output)
            }
            return outputs
        case .pdf, .rtf:
            return []
        }
    }

    static func render(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let rotated = page.rotation % 180 != 0
        let width = Int(((rotated ? box.height : box.width) * scale).rounded())
        let height = Int(((rotated ? box.width : box.height) * scale).rounded())
        guard let ctx = ImageIOHelper.context(width: width, height: height) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }
}

enum TextConverter {
    static func convert(_ url: URL, to format: DocFormat) throws -> URL {
        let text = try load(url)
        let ext = format == .docx ? "docx" : format.rawValue
        let output = Engine.outputURL(next: url, suffix: nil, ext: ext)
        try write(text, to: output, format: format)
        return output
    }

    static func load(_ url: URL) throws -> NSAttributedString {
        let documentType: NSAttributedString.DocumentType
        switch url.pathExtension.lowercased() {
        case "docx": documentType = .officeOpenXML
        case "doc": documentType = .docFormat
        case "odt": documentType = .openDocument
        case "rtf": documentType = .rtf
        case "rtfd": documentType = .rtfd
        case "html", "htm": documentType = .html
        default:
            let string = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .windowsCP1251))
                ?? ""
            return NSAttributedString(string: string, attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.black,
            ])
        }
        return try NSAttributedString(url: url, options: [.documentType: documentType], documentAttributes: nil)
    }

    static func write(_ text: NSAttributedString, to url: URL, format: DocFormat) throws {
        let printable = withFixedColors(text)
        let range = NSRange(location: 0, length: printable.length)
        switch format {
        case .txt:
            try printable.string.write(to: url, atomically: true, encoding: .utf8)
        case .rtf:
            let data = try printable.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            try data.write(to: url)
        case .docx:
            let data = try printable.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
            try data.write(to: url)
        case .pdf:
            try writePDF(printable, to: url)
        case .png, .jpg:
            break
        }
    }

    /// Dynamic system colors (labelColor etc.) would render white in Dark Mode; pin them to black.
    private static func withFixedColors(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        let range = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.foregroundColor, in: range) { value, subrange, _ in
            let color = value as? NSColor
            if color == nil || color?.type == .catalog {
                result.addAttribute(.foregroundColor, value: NSColor.black, range: subrange)
            }
        }
        return result
    }

    /// Paginates text onto A4 pages with CoreText.
    private static func writePDF(_ text: NSAttributedString, to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw EngineError.writeFailed(url.lastPathComponent)
        }
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let path = CGPath(rect: mediaBox.insetBy(dx: 56, dy: 56), transform: nil)
        var location = 0
        repeat {
            ctx.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            ctx.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length == 0 { break }
            location += visible.length
        } while location < text.length
        ctx.closePDF()
    }
}
