import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum ActionRunner {
    static func run(_ action: FileAction, files: [URL]) {
        switch action {
        case .copyPath:
            copyToPasteboard(files.map(\.path).joined(separator: "\n"))
            HUD.shared.done(files.count == 1 ? "Path copied" : "\(files.count) paths copied")
        case .airDrop:
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: files) else {
                HUD.shared.failed("AirDrop isn't available right now")
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            service.perform(withItems: files)
        case .crop, .addBackground, .adjust, .annotate, .redact:
            for url in files.prefix(5) {
                openEditor(action, for: url)
            }
        case .pdfProtect:
            guard let password = askPassword() else { return }
            runInBackground("Locking…") { try files.map { try PDFTools.protect($0, password: password) } }
        case .copyText:
            copyText(from: files)
        case .textTo:
            // NSAttributedString's HTML importer must run on the main thread.
            do {
                finished(try Engine.perform(action, files: files))
            } catch {
                fail(error)
            }
        default:
            runInBackground("\(action.title)…") { try Engine.perform(action, files: files) }
        }
    }

    /// Saves an editor result next to the source. Returns false (after reporting) on failure.
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
        let text = outputs.count == 1 ? "Saved \(outputs[0].lastPathComponent)" : "Saved \(outputs.count) files"
        HUD.shared.done(text, files: outputs)
        if Prefs.revealOutput, !outputs.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(outputs)
        }
    }

    static func fail(_ error: Error) {
        NSSound.beep()
        HUD.shared.failed(error.localizedDescription)
    }

    private static func runInBackground(_ label: String, _ work: @escaping @Sendable () throws -> [URL]) {
        HUD.shared.working(label)
        Task.detached(priority: .userInitiated) {
            do {
                let outputs = try work()
                await MainActor.run { ActionRunner.finished(outputs) }
            } catch {
                await MainActor.run { ActionRunner.fail(error) }
            }
        }
    }

    private static func copyText(from files: [URL]) {
        if FileKind.common(files) == .text {
            do {
                copyRecognized(try files.map { try Engine.extractText(from: $0) }.joined(separator: "\n\n"))
            } catch {
                fail(error)
            }
            return
        }
        HUD.shared.working("Reading text…")
        Task.detached(priority: .userInitiated) {
            do {
                let text = try files.map { try Engine.extractText(from: $0) }.joined(separator: "\n\n")
                await MainActor.run { ActionRunner.copyRecognized(text) }
            } catch {
                await MainActor.run { ActionRunner.fail(error) }
            }
        }
    }

    private static func copyRecognized(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            HUD.shared.failed("No text found")
            return
        }
        copyToPasteboard(trimmed)
        NSSound(named: NSSound.Name("Pop"))?.play()
        HUD.shared.done("Copied \(trimmed.count) characters")
    }

    private static func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private static func askPassword() -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Lock PDF"
        alert.informativeText = "This password will be required to open the locked copy."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Lock")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return nil }
        return field.stringValue
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
            EditorWindows.open(title: title, size: NSSize(width: 600, height: 800)) { close in
                BackgroundEditor(source: url, image: image, close: close)
            }
        case .adjust:
            EditorWindows.open(title: title, size: NSSize(width: 560, height: 780)) { close in
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
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 460, height: 520)
        let close: () -> Void = { [weak window] in window?.close() }
        let hosting = NSHostingView(rootView: content(close))
        hosting.sizingOptions = []
        window.contentView = glassContainer(for: hosting)
        window.center()
        windows.append(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Frosted window background: Liquid Glass on macOS 26, a behind-window blur before that.
    private static func glassContainer(for content: NSView) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.tintColor = NSColor(srgbRed: 1, green: 0.86, blue: 0.76, alpha: 0.35)
            glass.contentView = content
            return glass
        }
        #endif
        let effect = NSVisualEffectView()
        effect.blendingMode = .behindWindow
        effect.material = .popover
        effect.state = .active
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return effect
    }
}
