import AppKit
import SwiftUI

enum RadialGeometry {
    static let size: CGFloat = 380
    static let inner: CGFloat = 62
    static let outer: CGFloat = 160

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
        guard radius > inner, radius < outer + 18 else { return nil }
        let span = 360 / Double(count)
        var degrees = atan2(Double(dy), Double(dx)) * 180 / .pi + 90 + span / 2
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }
        return min(Int(degrees / span), count - 1)
    }
}

final class RadialModel: ObservableObject {
    @Published var actions: [FileAction] = []
    @Published var hovered: Int?
    @Published var visible = false
    @Published var summary = ""
}

@MainActor
final class RadialPanelController {
    let model = RadialModel()
    private let panel: NSPanel
    private var files: [URL] = []
    private var generation = 0

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
        panel.setFrameOrigin(origin)
        model.hovered = nil
        panel.orderFrontRegardless()
        model.visible = true
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
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard let self, self.generation == current else { return }
            self.panel.orderOut(nil)
            self.files = []
        }
    }

    private func configure(with files: [URL]) {
        self.files = files
        let kind = FileKind.common(files)
        model.actions = kind.actions(for: files)
        model.summary = Self.summary(for: files)
    }

    private static func summary(for files: [URL]) -> String {
        if files.count > 1 { return "\(files.count) files" }
        guard let url = files.first else { return "" }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values?.isDirectory == true { return "Folder" }
        let bytes = Int64(values?.fileSize ?? 0)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: Drop handling

    func dragUpdated(at point: NSPoint, pasteboard: NSPasteboard) -> NSDragOperation {
        if files.isEmpty {
            let urls = Self.fileURLs(in: pasteboard)
            if !urls.isEmpty { configure(with: urls) }
        }
        let index = RadialGeometry.segment(at: point, count: model.actions.count)
        if model.hovered != index { model.hovered = index }
        return index == nil ? [] : .copy
    }

    func dragExited() {
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
