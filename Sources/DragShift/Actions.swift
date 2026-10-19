import Foundation
import ImageIO
import UniformTypeIdentifiers

enum DocFormat: String, Sendable {
    case pdf, docx, txt, rtf, png, jpg
}

enum ImageFormat: String, CaseIterable, Sendable {
    case png, jpg, heic, webp, tiff, avif

    var utType: UTType? {
        switch self {
        case .png: return .png
        case .jpg: return .jpeg
        case .heic: return .heic
        case .webp: return .webP
        case .tiff: return .tiff
        case .avif: return UTType("public.avif")
        }
    }

    /// Formats this Mac's ImageIO can actually encode (WebP/AVIF depend on the macOS version).
    static let writable: [ImageFormat] = {
        let identifiers = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        return allCases.filter { format in
            format.utType.map { identifiers.contains($0.identifier) } ?? false
        }
    }()
}

enum FileAction: Hashable, Sendable {
    // PDF
    case pdfTo(DocFormat)
    case pdfCompress
    case pdfSplit
    case pdfMerge
    case pdfRotate
    case pdfProtect
    // Documents
    case textTo(DocFormat)
    // Images
    case compress
    case stripMetadata
    case removeBackground
    case convertImage(ImageFormat)
    case imagesToPDF
    case crop
    case addBackground
    case adjust
    case annotate
    case redact
    // Video
    case videoMP4
    case video720
    case videoGIF
    case videoAudio
    // Anything
    case copyText
    case airDrop
    case copyPath
    case zip
    case duplicate

    var title: String {
        switch self {
        case .pdfTo(let format), .textTo(let format): return format.rawValue.uppercased()
        case .pdfCompress, .compress: return "Compress"
        case .pdfSplit: return "Split"
        case .pdfMerge: return "Merge"
        case .pdfRotate: return "Rotate"
        case .pdfProtect: return "Lock"
        case .stripMetadata: return "Metadata"
        case .removeBackground: return "Remove BG"
        case .convertImage(let format): return format.rawValue.uppercased()
        case .imagesToPDF: return "PDF"
        case .crop: return "Crop"
        case .addBackground: return "Add BG"
        case .adjust: return "Edit"
        case .annotate: return "Annotate"
        case .redact: return "Redact"
        case .videoMP4: return "MP4"
        case .video720: return "720p"
        case .videoGIF: return "GIF"
        case .videoAudio: return "Audio"
        case .copyText: return "Text"
        case .airDrop: return "AirDrop"
        case .copyPath: return "Path"
        case .zip: return "ZIP"
        case .duplicate: return "Duplicate"
        }
    }

    var symbol: String? {
        switch self {
        case .pdfTo, .textTo, .convertImage, .imagesToPDF, .videoMP4, .videoGIF: return nil
        case .pdfCompress, .compress, .video720: return "arrow.down.right.and.arrow.up.left"
        case .pdfSplit: return "square.split.2x1"
        case .pdfMerge: return "arrow.triangle.merge"
        case .pdfRotate: return "rotate.right"
        case .pdfProtect: return "lock"
        case .stripMetadata: return "tag"
        case .removeBackground: return "person.crop.rectangle"
        case .crop: return "crop"
        case .addBackground: return "photo"
        case .adjust: return "slider.horizontal.3"
        case .annotate: return "pencil.tip.crop.circle"
        case .redact: return "eye.slash"
        case .videoAudio: return "waveform"
        case .copyText: return "text.viewfinder"
        case .airDrop: return "dot.radiowaves.left.and.right"
        case .copyPath: return "link"
        case .zip: return "doc.zipper"
        case .duplicate: return "plus.square.on.square"
        }
    }
}

enum FileKind {
    case pdf, image, text, video, other

    private static let textExtensions: Set<String> = ["txt", "md", "markdown", "rtf", "rtfd", "docx", "doc", "odt", "html", "htm"]

    static func of(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if textExtensions.contains(ext) { return .text }
        guard ext != "svg", let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        return .other
    }

    static func common(_ urls: [URL]) -> FileKind {
        let kinds = Set(urls.map(of))
        return kinds.count == 1 ? kinds.first! : .other
    }

    /// Pages of the radial menu; tapping the trigger key mid-drag moves to the next one.
    func pages(for urls: [URL]) -> [ActionPage] {
        let share = ActionPage(title: "Share", actions: [.airDrop, .copyPath, .zip, .duplicate])
        switch self {
        case .pdf:
            return [
                ActionPage(title: "Convert", actions: [.pdfTo(.docx), .pdfTo(.jpg), .pdfTo(.png), .pdfTo(.txt)]),
                ActionPage(title: "PDF Tools", actions: [.pdfCompress, urls.count > 1 ? .pdfMerge : .pdfSplit, .pdfRotate, .pdfProtect, .copyText]),
                share,
            ]
        case .image:
            var tools: [FileAction] = [.compress, .stripMetadata, .adjust, .annotate, .addBackground]
            if #available(macOS 14.0, *) { tools.append(.removeBackground) }
            tools += [.crop, .redact]
            let extensions = Set(urls.map { $0.pathExtension.lowercased() == "jpeg" ? "jpg" : $0.pathExtension.lowercased() })
            let formats = ImageFormat.writable.filter { !(extensions.count == 1 && extensions.contains($0.rawValue)) }
            let convert = formats.map { FileAction.convertImage($0) } + [.imagesToPDF, .copyText]
            return [
                ActionPage(title: "Tools", actions: tools),
                ActionPage(title: "Convert", actions: convert),
                share,
            ]
        case .text:
            let extensions = Set(urls.map { $0.pathExtension.lowercased() })
            let formats: [DocFormat] = [.pdf, .docx, .txt, .rtf]
            let convert = formats
                .filter { extensions.count > 1 || !extensions.contains($0.rawValue) }
                .map { FileAction.textTo($0) }
            return [ActionPage(title: "Convert", actions: convert + [.copyText]), share]
        case .video:
            return [ActionPage(title: "Convert", actions: [.videoMP4, .video720, .videoGIF, .videoAudio]), share]
        case .other:
            return [share]
        }
    }
}
