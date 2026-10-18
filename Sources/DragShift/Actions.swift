import Foundation
import UniformTypeIdentifiers

enum DocFormat: String, Sendable {
    case pdf, docx, txt, rtf, png, jpg
}

enum ImageFormat: String, Sendable {
    case png, jpg
}

enum FileAction: Hashable, Sendable {
    case pdfTo(DocFormat)
    case textTo(DocFormat)
    case compress
    case stripMetadata
    case convertImage(ImageFormat)
    case crop
    case addBackground
    case adjust
    case annotate
    case redact
    case zip
    case duplicate
    case copyPath

    var title: String {
        switch self {
        case .pdfTo(let format), .textTo(let format): return format.rawValue.uppercased()
        case .compress: return "Compress"
        case .stripMetadata: return "Metadata"
        case .convertImage(let format): return "To " + format.rawValue.uppercased()
        case .crop: return "Crop"
        case .addBackground: return "Add BG"
        case .adjust: return "Edit"
        case .annotate: return "Annotate"
        case .redact: return "Redact"
        case .zip: return "ZIP"
        case .duplicate: return "Duplicate"
        case .copyPath: return "Copy Path"
        }
    }

    var symbol: String? {
        switch self {
        case .pdfTo, .textTo: return nil
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .stripMetadata: return "tag"
        case .convertImage: return "arrow.triangle.2.circlepath"
        case .crop: return "crop"
        case .addBackground: return "photo"
        case .adjust: return "slider.horizontal.3"
        case .annotate: return "pencil.tip.crop.circle"
        case .redact: return "eye.slash"
        case .zip: return "doc.zipper"
        case .duplicate: return "plus.square.on.square"
        case .copyPath: return "link"
        }
    }

    var opensEditor: Bool {
        switch self {
        case .crop, .addBackground, .adjust, .annotate, .redact: return true
        default: return false
        }
    }
}

enum FileKind {
    case pdf, image, text, other

    private static let textExtensions: Set<String> = ["txt", "md", "markdown", "rtf", "rtfd", "docx", "doc", "odt", "html", "htm"]

    static func of(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if textExtensions.contains(ext) { return .text }
        if ext != "svg", let type = UTType(filenameExtension: ext), type.conforms(to: .image) { return .image }
        return .other
    }

    static func common(_ urls: [URL]) -> FileKind {
        let kinds = Set(urls.map(of))
        return kinds.count == 1 ? kinds.first! : .other
    }

    func actions(for urls: [URL]) -> [FileAction] {
        switch self {
        case .pdf:
            return [.pdfTo(.docx), .pdfTo(.jpg), .pdfTo(.png), .pdfTo(.txt)]
        case .image:
            let allPNG = urls.allSatisfy { $0.pathExtension.lowercased() == "png" }
            return [.compress, .stripMetadata, .adjust, .annotate, .addBackground, .convertImage(allPNG ? .jpg : .png), .crop, .redact]
        case .text:
            let extensions = Set(urls.map { $0.pathExtension.lowercased() })
            let formats: [DocFormat] = [.pdf, .docx, .txt, .rtf]
            return formats
                .filter { extensions.count > 1 || !extensions.contains($0.rawValue) }
                .map { .textTo($0) }
        case .other:
            return [.zip, .duplicate, .copyPath]
        }
    }
}
