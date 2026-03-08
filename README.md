# ClaudeUsage

A macOS menu bar app that monitors your Claude Pro/Team usage quota in real time.

## Features

- Lives in the menu bar — shows remaining usage at a glance
- Detects your session automatically from Safari or Chrome cookies
- Polls the Claude API periodically for up-to-date quota info
- Displays usage breakdown with reset timing
- Lightweight, no external dependencies — pure Swift/AppKit

## Requirements

- macOS 13.0 (Ventura) or later
- An active Claude Pro or Team subscription

## Installation

### Homebrew Cask

```bash
brew tap borjadotai/tap
brew install --cask claudeusage
```

### Manual download

1. Download `ClaudeUsage-<version>.zip` from the [latest release](../../releases/latest)
2. Unzip and drag `ClaudeUsage.app` to `/Applications`
3. On first launch, right-click the app → **Open** → **Open** (required for unsigned apps)

### Build from source

Requires Xcode 15+.

```bash
git clone https://github.com/borjadotai/claude-usage.git
cd claudeusage
make build
# App is at build/Build/Products/Release/ClaudeUsage.app
```

## Gatekeeper note

Since the app is not notarized with an Apple Developer ID, macOS will block it on first launch. To allow it:

- **Right-click → Open → Open** (easiest), or
- Run `xattr -cr /Applications/ClaudeUsage.app` in Terminal

This is standard for open-source Mac apps distributed outside the App Store.

## How it works

1. On launch, the app reads your `sessionKey` cookie from Safari or Chrome
2. It uses this session to query the Claude usage API at regular intervals
3. Current usage and quota reset time are displayed in the menu bar and dropdown

## Privacy & Keychain access

**You will see a macOS Keychain password prompt on first launch.** Here's exactly why and what we access:

- **Chrome users**: Chrome encrypts all cookies with a key stored in macOS Keychain under "Chrome Safe Storage". We read *only* that key to decrypt the `sessionKey` cookie for `claude.ai` — nothing else. This is the standard way any app reads Chrome cookies on macOS. See the exact query on line 111 of [`BrowserCookieReader.swift`](ClaudeUsageApp/Services/BrowserCookieReader.swift#L111): it calls `security find-generic-password -s "Chrome Safe Storage"` and uses the result solely to decrypt the one `sessionKey` cookie ([line 61](ClaudeUsageApp/Services/BrowserCookieReader.swift#L61)).

- **Safari users**: No Keychain prompt. Safari cookies are read directly from the binary cookie store, filtered to only the `sessionKey` for `claude.ai` ([`SafariCookieReader.swift`](ClaudeUsageApp/Services/SafariCookieReader.swift#L18-L21)).

- **What we store**: The `sessionKey` value is saved in your own Keychain under `com.claudeusage.app` so we don't need to re-read browser cookies every time ([`KeychainService.swift`](ClaudeUsageApp/Services/KeychainService.swift)).

**We do not read, store, or transmit any other cookies, passwords, or browser data.** The code is ~1,300 lines of Swift with zero external dependencies — feel free to audit it.

## License

[MIT](LICENSE)
