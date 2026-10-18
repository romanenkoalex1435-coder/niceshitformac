import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum ActionRunner {
    static func run(_ action: FileAction, files: [URL]) {
        switch action {
        case .copyPath:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(files.map(\.path).joined(separator: "\n"), forType: .string)
            finished([])
        case .crop, .addBackground, .adjust, .annotate, .redact:
            for url in files.prefix(5) {
                openEditor(action, for: url)
            }
        case .textTo:
            // NSAttributedString's HTML importer must run on the main thread.
            do {
                finished(try files.flatMap { try Engine.perform(action, on: $0) })
            } catch {
                fail(error)
            }
        default:
            Task.detached(priority: .userInitiated) {
                do {
                    let outputs = try files.flatMap { try Engine.perform(action, on: $0) }
                    await MainActor.run { ActionRunner.finished(outputs) }
                } catch {
                    await MainActor.run { ActionRunner.fail(error) }
                }
            }
        }
    }

    /// Saves an editor result next to the source. Returns false (after showing an alert) on failure.
    static func save(_ image: CGImage, source: URL, suffix: String, type: UTType? = nil) -> Bool {
        let outputType = type ?? ImageIOHelper.outputType(for: source)
        let output = Engine.outputURL(next: source, suffix: suffix, ext: ImageIOHelper.fileExtension(for: outputType))
        do {
            try ImageIOHelper.write(image, to: output, type: outputType)
            finished([output])
            return true
        } catch {
            fail(error)
            return false
        }
    }

    static func finished(_ outputs: [URL]) {
        NSSound(named: NSSound.Name("Pop"))?.play()
        if Prefs.revealOutput, !outputs.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(outputs)
        }
    }

    static func fail(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "DragShift couldn't finish"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private static func openEditor(_ action: FileAction, for url: URL) {
        guard let image = ImageIOHelper.load(url) else {
            fail(EngineError.unreadable(url.lastPathComponent))
            return
        }
        let title = "\(action.title) — \(url.lastPathComponent)"
        switch action {
        case .crop:
            EditorWindows.open(title: title, size: NSSize(width: 560, height: 700)) { close in
                CropEditor(source: url, image: image, close: close)
            }
        case .addBackground:
            EditorWindows.open(title: title, size: NSSize(width: 580, height: 780)) { close in
                BackgroundEditor(source: url, image: image, close: close)
            }
        case .adjust:
            EditorWindows.open(title: title, size: NSSize(width: 560, height: 760)) { close in
                AdjustEditor(source: url, image: image, close: close)
            }
        case .annotate:
            EditorWindows.open(title: title, size: NSSize(width: 620, height: 720)) { close in
                MarkupEditor(mode: .annotate, source: url, image: image, close: close)
            }
        case .redact:
            EditorWindows.open(title: title, size: NSSize(width: 620, height: 700)) { close in
                MarkupEditor(mode: .redact, source: url, image: image, close: close)
            }
        default:
            break
        }
    }
}

@MainActor
enum EditorWindows {
    private static var windows: [NSWindow] = []

    static func open<Content: View>(title: String, size: NSSize, content: (@escaping () -> Void) -> Content) {
        windows.removeAll { !$0.isVisible }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 460, height: 520)
        let close: () -> Void = { [weak window] in window?.close() }
        let hosting = NSHostingView(rootView: content(close))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.center()
        windows.append(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
