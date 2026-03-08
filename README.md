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
brew tap borjaarias/tap
brew install --cask claudeusage
```

### Manual download

1. Download `ClaudeUsage-<version>.zip` from the [latest release](../../releases/latest)
2. Unzip and drag `ClaudeUsage.app` to `/Applications`
3. On first launch, right-click the app → **Open** → **Open** (required for unsigned apps)

### Build from source

Requires Xcode 15+.

```bash
git clone https://github.com/borjaarias/claudeusage.git
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

## License

[MIT](LICENSE)
