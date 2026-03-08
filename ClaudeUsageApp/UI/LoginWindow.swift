import AppKit

@MainActor
final class LoginWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var onSessionKey: ((String) -> Void)?

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        NSApp.setActivationPolicy(.regular)

        let vc = LoginWebViewController()
        vc.onSessionKeyEntered = { [weak self] key in
            self?.onSessionKey?(key)
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Sign in to Claude"
        win.contentViewController = vc
        win.delegate = self
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    func close() {
        window?.close()
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
