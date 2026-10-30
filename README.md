# SmartClip

<div align="center">
  <img src="Resources/AppIcon.png" width="112" alt="SmartClip app icon">

  **A private, encrypted clipboard history that feels at home on macOS.**

  [![CI](https://img.shields.io/github/actions/workflow/status/reathloo/smartClip/ci.yml?branch=main&style=flat-square&label=checks)](https://github.com/reathloo/smartClip/actions/workflows/ci.yml)
  [![Release](https://img.shields.io/github/v/release/reathloo/smartClip?include_prereleases&style=flat-square)](https://github.com/reathloo/smartClip/releases)
  ![macOS](https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square&logo=apple)
  ![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-0b8f87?style=flat-square)
  [![MIT](https://img.shields.io/badge/license-MIT-0b8f87?style=flat-square)](LICENSE)

  [Features](#features) · [Install](#install) · [Privacy](#privacy-by-design) · [Development](#development)
</div>

SmartClip lives in the menu bar and keeps copied text, links, code, images, and
file references close at hand. Everything stays on your Mac: no account, cloud
service, telemetry, or remote processing.

## Why SmartClip?

- **Private by default.** Clipboard payloads are encrypted with AES-GCM and the
  key is stored in the macOS Keychain.
- **Fast to reach.** Open the history from the menu bar or a configurable global
  shortcut, then search and copy without leaving your workflow.
- **Native on macOS.** Built with SwiftUI and AppKit, with light and dark modes,
  launch at login, native keyboard behavior, and Accessibility-aware paste.
- **Careful with sensitive data.** Concealed clipboard markers and valid card
  numbers are masked and receive shorter retention limits.

## Features

| History | Workflow | Privacy and control |
| --- | --- | --- |
| Text, URLs, email, code, images, and file references | Search, filters, list and card views | Encrypted local payloads |
| Duplicate handling and source-app estimate | Named favorites and per-entry retention | Sensitive-content masking |
| Missing-file detection | Configurable shortcut and optional automatic paste | Capture pauses and excluded apps |
| Automatic cleanup | Menu-bar status and launch at login | Delete-all confirmation and no telemetry |

> [!NOTE]
> SmartClip stores references to files rather than copying them. Source-app,
> code, and sensitive-content detection are intentionally best-effort.

## Install

SmartClip currently supports **Apple Silicon Macs running macOS 14 or newer**.

1. Download the newest DMG from [GitHub Releases](https://github.com/reathloo/smartClip/releases).
2. Open the DMG and drag **SmartClip** to **Applications**.
3. Launch SmartClip and complete the short setup.

> [!WARNING]
> The current free beta is not signed with an Apple Developer ID or notarized.
> On first launch, macOS requires **System Settings → Privacy & Security → Open
> Anyway**. See the [installation guide](docs/INSTALLATION.md) for every step.

Published builds check the signed SmartClip update feed hourly. Trusted updates
can download in the background and install when SmartClip restarts; you can turn
automatic installation off in Settings or choose **Check for Updates …** at any
time.

## Privacy by design

SmartClip uses a local SQLite database for metadata and AES-GCM for clipboard
payloads. The encryption key is kept in Keychain. Sensitive entries stay masked,
are excluded from full-text search, and expire after a shorter period even when
pinned.

Some metadata—such as type, timestamps, and estimated source-app name—remains
unencrypted so the app can organize the history. Read the complete
[privacy explanation](PRIVACY.md) before using SmartClip with sensitive data.

## Development

Prerequisites:

- macOS 14 or newer
- Swift 6 toolchain from Xcode or Command Line Tools

```sh
git clone https://github.com/reathloo/smartClip.git
cd smartClip
zsh scripts/run-dev.sh --check
```

Useful commands:

```sh
zsh scripts/run-dev.sh          # build and restart the real app
zsh scripts/run-dev.sh --ui     # isolated UI preview with sample data
zsh scripts/test.sh             # run all 114 core checks
zsh scripts/build-app.sh        # create dist/SmartClip.app
```

The UI preview uses a private pasteboard and isolated temporary data. Use the
real app only for integration tests involving Keychain, Accessibility, the
global shortcut, or launch at login.

## Release process

A pushed `v*` tag triggers the release workflow. It runs the checks, builds the
styled DMG, verifies the package, signs the update with Sparkle EdDSA, creates a
GitHub Release, and publishes the appcast through GitHub Pages.

```sh
zsh scripts/package-release.sh v0.1.0-beta.2
```

See the [release guide](docs/RELEASE.md), [test report](docs/TEST_REPORT.md), and
[third-party notices](THIRD_PARTY_NOTICES.md) for the complete details.
