import AppKit
import SwiftUI

enum RadialGeometry {
    static let size: CGFloat = 400
    static let inner: CGFloat = 64
    static let outer: CGFloat = 160
    static let discRadius: CGFloat = 172

    /// Center angle of a segment in degrees, SwiftUI convention (0° = right, clockwise, first segment on top).
    static func angle(of index: Int, count: Int) -> Double {
        -90 + Double(index) * 360 / Double(count)
    }

    /// Segment under a point given in the panel's (non-flipped) AppKit coordinates.
    static func segment(at point: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let center = size / 2
        let dx = point.x - center
        let dy = center - point.y
        let radius = hypot(dx, dy)
        guard radius > inner, radius < discRadius + 12 else { return nil }
        let span = 360 / Double(count)
        var degrees = atan2(Double(dy), Double(dx)) * 180 / .pi + 90 + span / 2
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }
        return min(Int(degrees / span), count - 1)
    }
}

struct ActionPage: Equatable {
    let title: String
    let actions: [FileAction]
}

final class RadialModel: ObservableObject {
    @Published var pages: [ActionPage] = []
    @Published var page = 0
    @Published var hovered: Int?
    @Published var visible = false
    @Published var summary = ""

    var actions: [FileAction] {
        pages.indices.contains(page) ? pages[page].actions : []
    }

    var nextPageTitle: String? {
        pages.count > 1 ? pages[(page + 1) % pages.count].title : nil
    }
}

@MainActor
final class RadialPanelController {
    let model = RadialModel()
    private let panel: NSPanel
    private var files: [URL] = []
    private var generation = 0
    private var lastDragPoint: NSPoint?

    init() {
        let size = RadialGeometry.size
        let frame = NSRect(x: 0, y: 0, width: size, height: size)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let container = NSView(frame: frame)
        let hosting = NSHostingView(rootView: RadialMenuView(model: model))
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        let dropView = RadialDropView(frame: container.bounds)
        dropView.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        container.addSubview(dropView)
        panel.contentView = container
        dropView.controller = self
    }

    var isShowing: Bool { panel.isVisible && model.visible }

    static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        return (objects as? [URL]) ?? []
    }

    func show(at point: NSPoint, files: [URL]) {
        configure(with: files)
        let size = RadialGeometry.size
        var origin = NSPoint(x: point.x - size / 2, y: point.y - size / 2)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
            let bounds = screen.frame
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size)
            origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size)
        }
        generation += 1
        lastDragPoint = nil
        panel.setFrameOrigin(origin)
        model.hovered = nil
        panel.orderFrontRegardless()
        model.visible = true
    }

    /// Cycles Tools → Convert → Share (triggered by tapping the trigger key again mid-drag).
    func nextPage() {
        guard isShowing, model.pages.count > 1 else { return }
        model.page = (model.page + 1) % model.pages.count
        model.hovered = lastDragPoint.flatMap { RadialGeometry.segment(at: $0, count: model.actions.count) }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    func dragDidEnd() {
        hide()
    }

    func hide() {
        guard panel.isVisible else { return }
        model.visible = false
        model.hovered = nil
        generation += 1
        let current = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard let self, self.generation == current else { return }
            self.panel.orderOut(nil)
            self.files = []
        }
    }

    private func configure(with files: [URL]) {
        self.files = files
        model.pages = FileKind.common(files).pages(for: files)
        model.page = 0
        model.summary = Self.summary(for: files)
    }

    private static func summary(for files: [URL]) -> String {
        if files.count > 1 { return "\(files.count) FILES" }
        guard let url = files.first else { return "" }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values?.isDirectory == true { return "FOLDER" }
        let bytes = Int64(values?.fileSize ?? 0)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: Drop handling

    func dragUpdated(at point: NSPoint, pasteboard: NSPasteboard) -> NSDragOperation {
        if files.isEmpty {
            let urls = Self.fileURLs(in: pasteboard)
            if !urls.isEmpty { configure(with: urls) }
        }
        lastDragPoint = point
        let index = RadialGeometry.segment(at: point, count: model.actions.count)
        if model.hovered != index {
            model.hovered = index
            if index != nil {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        return index == nil ? [] : .copy
    }

    func dragExited() {
        lastDragPoint = nil
        model.hovered = nil
    }

    func performDrop(at point: NSPoint, pasteboard: NSPasteboard) -> Bool {
        var urls = Self.fileURLs(in: pasteboard)
        if urls.isEmpty { urls = files }
        guard !urls.isEmpty,
              let index = RadialGeometry.segment(at: point, count: model.actions.count),
              index < model.actions.count
        else { return false }
        let action = model.actions[index]
        hide()
        // Let the drag session finish before running the action (editors open windows).
        Task { @MainActor in
            ActionRunner.run(action, files: urls)
        }
        return true
    }
}

/// Transparent view on top of the SwiftUI menu that receives the file drop.
final class RadialDropView: NSView {
    weak var controller: RadialPanelController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        controller?.dragUpdated(at: convert(sender.draggingLocation, from: nil), pasteboard: sender.draggingPasteboard) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        controller?.dragUpdated(at: convert(sender.draggingLocation, from: nil), pasteboard: sender.draggingPasteboard) ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        controller?.dragExited()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        controller?.performDrop(at: convert(sender.draggingLocation, from: nil), pasteboard: sender.draggingPasteboard) ?? false
    }
}
