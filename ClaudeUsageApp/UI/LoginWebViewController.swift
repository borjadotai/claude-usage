import AppKit

final class LoginWebViewController: NSViewController {
    var onSessionKeyEntered: ((String) -> Void)?

    private var statusLabel: NSTextField!
    private var actionButton: NSButton!
    private var manualField: NSTextField!
    private var manualStack: NSStackView!
    private var pollTimer: Timer?
    private var pollCount = 0

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 280))
        preferredContentSize = NSSize(width: 420, height: 280)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        // Try auto-detect immediately
        attemptAutoDetect()
    }

    private func setupUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 14
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        let title = NSTextField(labelWithString: "Connect to Claude")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        stack.addArrangedSubview(title)

        statusLabel = NSTextField(wrappingLabelWithString: "Checking if you're already logged in…")
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.alignment = .center
        stack.addArrangedSubview(statusLabel)
        statusLabel.widthAnchor.constraint(equalToConstant: 356).isActive = true

        actionButton = NSButton(title: "Open claude.ai in Browser", target: self, action: #selector(openBrowserAndPoll))
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .large
        actionButton.isHidden = true
        stack.addArrangedSubview(actionButton)

        // Manual fallback (hidden initially)
        manualStack = NSStackView()
        manualStack.orientation = .vertical
        manualStack.spacing = 8
        manualStack.alignment = .centerX
        manualStack.isHidden = true

        let manualLabel = NSTextField(wrappingLabelWithString: "Or paste your sessionKey cookie manually:")
        manualLabel.font = .systemFont(ofSize: 11)
        manualLabel.textColor = .secondaryLabelColor
        manualStack.addArrangedSubview(manualLabel)
        manualLabel.widthAnchor.constraint(equalToConstant: 356).isActive = true

        manualField = NSTextField()
        manualField.placeholderString = "sk-ant-sid…"
        manualField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        manualStack.addArrangedSubview(manualField)
        manualField.widthAnchor.constraint(equalToConstant: 356).isActive = true

        let connectButton = NSButton(title: "Connect", target: self, action: #selector(manualConnect))
        connectButton.bezelStyle = .rounded
        connectButton.keyEquivalent = "\r"
        manualStack.addArrangedSubview(connectButton)

        stack.addArrangedSubview(manualStack)
    }

    private func attemptAutoDetect() {
        DispatchQueue.global(qos: .userInitiated).async {
            let key = BrowserCookieReader.findSessionKey()
            DispatchQueue.main.async {
                if let key {
                    self.statusLabel.stringValue = "Found existing session!"
                    self.onSessionKeyEntered?(key)
                } else {
                    self.statusLabel.stringValue = "Log in to claude.ai in your browser.\nThe app will detect your session automatically."
                    self.actionButton.isHidden = false
                    self.manualStack.isHidden = false
                }
            }
        }
    }

    @objc private func openBrowserAndPoll() {
        NSWorkspace.shared.open(URL(string: "https://claude.ai/login")!)
        actionButton.title = "Waiting for login…"
        actionButton.isEnabled = false
        statusLabel.stringValue = "Log in to Claude in your browser.\nThis window will close automatically when detected."
        startPolling()
    }

    private func startPolling() {
        pollCount = 0
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollForCookie()
        }
    }

    private func pollForCookie() {
        pollCount += 1
        // Poll for up to 5 minutes (150 * 2s)
        if pollCount > 150 {
            pollTimer?.invalidate()
            statusLabel.stringValue = "Timed out. Please paste your cookie manually."
            actionButton.title = "Try Again"
            actionButton.isEnabled = true
            return
        }

        statusLabel.stringValue = "Checking browser cookies… (attempt \(pollCount)/150)"

        DispatchQueue.global(qos: .userInitiated).async {
            let key = BrowserCookieReader.findSessionKey()
            DispatchQueue.main.async {
                if let key {
                    self.pollTimer?.invalidate()
                    self.statusLabel.stringValue = "Login detected!"
                    self.onSessionKeyEntered?(key)
                } else {
                    self.statusLabel.stringValue = "Waiting for login… (attempt \(self.pollCount)/150)\nLog in to Claude in your browser."
                }
            }
        }
    }

    @objc private func manualConnect() {
        let value = manualField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onSessionKeyEntered?(value)
    }

    deinit {
        pollTimer?.invalidate()
    }
}
