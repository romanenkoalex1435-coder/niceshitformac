import AppKit
import ImageIO
import SwiftUI

/// Glass toast at the bottom of the screen: progress while working, then the result. Click to reveal.
@MainActor
final class HUD {
    static let shared = HUD()

    enum Status { case working, done, failed }

    final class Model: ObservableObject {
        @Published var status: Status = .working
        @Published var text = ""
        @Published var thumbnail: NSImage?
        @Published var visible = false
    }

    private let model = Model()
    private let panel: NSPanel
    private var files: [URL] = []
    private var generation = 0
    private static let size = NSSize(width: 440, height: 90)

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let hosting = NSHostingView(rootView: HUDView(model: model) { [weak self] in self?.reveal() })
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    func working(_ text: String) {
        show(.working, text, files: [], autoHide: false)
    }

    func done(_ text: String, files: [URL] = []) {
        show(.done, text, files: files, autoHide: true)
    }

    func failed(_ text: String) {
        show(.failed, text, files: [], autoHide: true)
    }

    private func show(_ status: Status, _ text: String, files: [URL], autoHide: Bool) {
        model.status = status
        model.text = text
        model.thumbnail = files.first.map(Self.thumbnail(for:))
        self.files = files
        position()
        panel.orderFrontRegardless()
        model.visible = true
        generation += 1
        guard autoHide else { return }
        let current = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: status == .failed ? 4_500_000_000 : 2_800_000_000)
            guard let self, self.generation == current else { return }
            self.hide()
        }
    }

    private func hide() {
        model.visible = false
        let current = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, self.generation == current else { return }
            self.panel.orderOut(nil)
        }
    }

    private func reveal() {
        if !files.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(files)
        }
        hide()
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 60))
    }

    private static func thumbnail(for url: URL) -> NSImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 96,
        ]
        if FileKind.of(url) == .image,
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return NSImage(cgImage: image, size: .zero)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct HUDView: View {
    @ObservedObject var model: HUD.Model
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 34, height: 34)
            Text(model.text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
            if model.status == .done, model.thumbnail != nil {
                Text("Show")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accent)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .liquidGlass(Capsule(), tint: Color.white.opacity(0.2), fallback: AnyShapeStyle(Color(hex: 0xFFF4EC, opacity: 0.94)))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .contentShape(Capsule())
        .onTapGesture(perform: onTap)
        .scaleEffect(model.visible ? 1 : 0.85)
        .opacity(model.visible ? 1 : 0)
        .offset(y: model.visible ? 0 : 18)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: model.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var icon: some View {
        switch model.status {
        case .working:
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.accent)
        case .done:
            if let thumbnail = model.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(hex: 0x34C759))
            }
        }
    }
}
