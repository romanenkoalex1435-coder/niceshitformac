import AppKit
import ServiceManagement
import SwiftUI

@main
struct DragShiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("DragShift", systemImage: "circle.circle") {
            MenuContent()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DragMonitor.shared.start()
    }
}

enum TriggerKey: String, CaseIterable, Identifiable {
    case shift, option, control, command

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shift: return "Shift ⇧"
        case .option: return "Option ⌥"
        case .control: return "Control ⌃"
        case .command: return "Command ⌘"
        }
    }

    var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .option: return "⌥"
        case .control: return "⌃"
        case .command: return "⌘"
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: return .shift
        case .option: return .option
        case .control: return .control
        case .command: return .command
        }
    }
}

enum Prefs {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true }
    static var trigger: TriggerKey { TriggerKey(rawValue: UserDefaults.standard.string(forKey: "trigger") ?? "") ?? .shift }
    static var revealOutput: Bool { UserDefaults.standard.bool(forKey: "revealOutput") }
}

struct MenuContent: View {
    @AppStorage("enabled") private var enabled = true
    @AppStorage("trigger") private var trigger: TriggerKey = .shift
    @AppStorage("revealOutput") private var revealOutput = false

    var body: some View {
        Toggle("Enabled", isOn: $enabled)
        Picker("Trigger Key", selection: $trigger) {
            ForEach(TriggerKey.allCases) { key in
                Text(key.title).tag(key)
            }
        }
        Toggle("Reveal Results in Finder", isOn: $revealOutput)
        Toggle("Launch at Login", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSSound.beep()
                }
            }
        ))
        Divider()
        Button("How to Use…") { showHelp() }
        Button("Quit DragShift") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "DragShift"
        alert.informativeText = """
        Start dragging any file (from Finder or the Desktop) and hold \(trigger.title). \
        A radial menu appears under the cursor — drop the file on an action. \
        Tap \(trigger.symbol) again while dragging to switch pages.

        Images → Tools (Compress, Metadata, Edit, Annotate, Add BG, Remove BG, Crop, Redact) · Convert (PNG, JPG, HEIC, WEBP, TIFF, AVIF, PDF, Text)
        PDF → Convert (DOCX, JPG, PNG, TXT) · Tools (Compress, Split/Merge, Rotate, Lock, Text)
        Documents → PDF, DOCX, TXT, RTF, Text
        Video → MP4, 720p, GIF, Audio
        Every file → Share (AirDrop, Path, ZIP, Duplicate)

        Results are saved next to the original file.
        """
        alert.runModal()
    }
}
