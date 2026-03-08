import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var usageFetcher: UsageFetcher?
    private var loginWindow: LoginWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)

        let fetcher = UsageFetcher()
        self.usageFetcher = fetcher

        let menuBar = MenuBarController()
        menuBar.onRefresh = { [weak self] in
            self?.usageFetcher?.refresh()
        }
        menuBar.onRelogin = { [weak self] in
            self?.startRelogin()
        }
        menuBar.bind(to: fetcher)
        self.menuBarController = menuBar

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionExpired),
            name: .sessionExpired,
            object: nil
        )

        if let savedKey = KeychainService.load() {
            print("[AppDelegate] Found saved session key in Keychain")
            fetcher.start(sessionKey: savedKey)
        } else {
            // Try auto-detect from browser cookies
            print("[AppDelegate] No saved key, trying browser cookies...")
            DispatchQueue.global(qos: .userInitiated).async {
                let browserKey = BrowserCookieReader.findSessionKey()
                DispatchQueue.main.async {
                    if let browserKey {
                        print("[AppDelegate] Auto-detected session from browser!")
                        self.handleLoginSuccess(sessionKey: browserKey)
                    } else {
                        print("[AppDelegate] No browser session found, showing login")
                        fetcher.markNotLoggedIn()
                        self.showLoginWindow()
                    }
                }
            }
        }
    }

    private func handleLoginSuccess(sessionKey: String) {
        print("[AppDelegate] Login success, saving key")
        do {
            try KeychainService.save(sessionKey)
        } catch {
            print("[AppDelegate] Keychain save error: \(error)")
        }
        loginWindow?.close()
        loginWindow = nil
        usageFetcher?.start(sessionKey: sessionKey)
    }

    private func showLoginWindow() {
        if loginWindow == nil {
            let win = LoginWindow()
            win.onSessionKey = { [weak self] key in
                self?.handleLoginSuccess(sessionKey: key)
            }
            loginWindow = win
        }
        loginWindow?.show()
    }

    private func startRelogin() {
        print("[AppDelegate] Re-login")
        usageFetcher?.stop()
        KeychainService.delete()
        loginWindow?.close()
        loginWindow = nil
        showLoginWindow()
    }

    @objc private func handleSessionExpired() {
        print("[AppDelegate] Session expired")
        startRelogin()
    }
}
