import AppKit

/// Watches for "a file is being dragged + trigger key is held" anywhere on screen.
///
/// Polling is used instead of event monitors: it needs no Accessibility permission and keeps
/// working while another app (Finder) owns the drag session.
@MainActor
final class DragMonitor: NSObject {
    static let shared = DragMonitor()

    private lazy var panel = RadialPanelController()
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var timer: Timer?
    private var baselineChangeCount = 0
    private var mouseWasDown = false
    private var shownForCurrentDrag = false
    private var triggerWasDown = false

    func start() {
        baselineChangeCount = dragPasteboard.changeCount
        let timer = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func tick() {
        let mouseDown = NSEvent.pressedMouseButtons & 1 == 1
        guard mouseDown else {
            // While the button is up, any pasteboard change is not a drag in progress.
            baselineChangeCount = dragPasteboard.changeCount
            if mouseWasDown {
                shownForCurrentDrag = false
                panel.dragDidEnd()
            }
            mouseWasDown = false
            return
        }
        mouseWasDown = true

        let triggerDown = NSEvent.modifierFlags.contains(Prefs.trigger.flag)
        defer { triggerWasDown = triggerDown }

        if shownForCurrentDrag {
            // Tapping the trigger key again flips to the next page of actions.
            if triggerDown && !triggerWasDown {
                panel.nextPage()
            }
            return
        }

        guard Prefs.enabled, triggerDown else { return }
        guard dragPasteboard.changeCount != baselineChangeCount else { return }

        let files = RadialPanelController.fileURLs(in: dragPasteboard)
        guard !files.isEmpty else { return }

        shownForCurrentDrag = true
        panel.show(at: NSEvent.mouseLocation, files: files)
    }
}
