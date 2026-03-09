import Cocoa
import SwiftUI

// MARK: - Charts Window Controller (SwiftUI)
class ChartsWindowController: NSWindowController {

    override init(window: NSWindow?) {
        super.init(window: window)
        setupWindow()
        setupSwiftUIContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = L("charts_window_title")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1000, height: 700)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .controlBackgroundColor

        self.window = window
    }

    private func setupSwiftUIContent() {
        let hostingController = NSHostingController(rootView: ChartsContentView())
        window?.contentViewController = hostingController
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)

        window?.alphaValue = 0.0
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            window?.animator().alphaValue = 1.0
        }
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.delegate = self
    }

    deinit {
        print("ChartsWindowController: Deallocated")
    }
}

// MARK: - NSWindowDelegate
extension ChartsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.chartsWindowDidClose()
        }
    }
}
