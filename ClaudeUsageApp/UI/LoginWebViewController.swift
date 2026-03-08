import AppKit
import WebKit

final class LoginWebViewController: NSViewController {
    var onSessionKeyEntered: ((String) -> Void)?

    private var instructionsView: NSView!
    private var tokenField: NSTextField!
    private var statusLabel: NSTextField!

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        preferredContentSize = NSSize(width: 500, height: 400)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 16
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        // Title
        let title = NSTextField(labelWithString: "Connect to Claude")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        stack.addArrangedSubview(title)

        // Step 1
        let step1 = NSTextField(wrappingLabelWithString: "1. Click the button below to open Claude in your browser and log in:")
        step1.font = .systemFont(ofSize: 13)
        stack.addArrangedSubview(step1)
        step1.widthAnchor.constraint(equalToConstant: 420).isActive = true

        let openButton = NSButton(title: "Open claude.ai in Browser", target: self, action: #selector(openBrowser))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .large
        stack.addArrangedSubview(openButton)

        // Step 2
        let step2 = NSTextField(wrappingLabelWithString: "2. After logging in, open your browser's Developer Tools:\n    • Safari: Develop → Show Web Inspector → Storage → Cookies\n    • Chrome: F12 → Application → Cookies → claude.ai")
        step2.font = .systemFont(ofSize: 13)
        stack.addArrangedSubview(step2)
        step2.widthAnchor.constraint(equalToConstant: 420).isActive = true

        // Step 3
        let step3 = NSTextField(wrappingLabelWithString: "3. Find the cookie named \"sessionKey\" (starts with sk-ant-sid) and paste its value below:")
        step3.font = .systemFont(ofSize: 13)
        stack.addArrangedSubview(step3)
        step3.widthAnchor.constraint(equalToConstant: 420).isActive = true

        // Token field
        tokenField = NSTextField()
        tokenField.placeholderString = "sk-ant-sid__..."
        tokenField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tokenField.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(tokenField)
        tokenField.widthAnchor.constraint(equalToConstant: 420).isActive = true

        // Connect button
        let connectButton = NSButton(title: "Connect", target: self, action: #selector(connectTapped))
        connectButton.bezelStyle = .rounded
        connectButton.controlSize = .large
        connectButton.keyEquivalent = "\r" // Enter key
        stack.addArrangedSubview(connectButton)

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .systemRed
        stack.addArrangedSubview(statusLabel)
    }

    @objc private func openBrowser() {
        if let url = URL(string: "https://claude.ai/login") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func connectTapped() {
        let value = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            statusLabel.stringValue = "Please paste the session cookie value."
            return
        }
        if !value.hasPrefix("sk-ant-sid") {
            statusLabel.stringValue = "This doesn't look like a valid session key. It should start with sk-ant-sid"
            statusLabel.textColor = .systemOrange
            // Allow it anyway — cookie format might change
        }
        print("[LoginVC] Session key entered, length: \(value.count), prefix: \(value.prefix(15))...")
        onSessionKeyEntered?(value)
    }
}
