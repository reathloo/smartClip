# Contributing to SmartClip

Thank you for helping improve SmartClip. Focused bug reports, translations, documentation corrections, tests, and code changes are welcome.

## Before you start

- Search [existing issues](https://github.com/reathloo/smartClip/issues) before opening a new one.
- Use the bug or feature-request form so reports contain the information needed to act on them.
- Report suspected vulnerabilities privately according to [SECURITY.md](SECURITY.md).
- Keep each issue or pull request focused on one change.

## Development setup

You need:

- macOS 14 or newer;
- a Swift 6 toolchain from Xcode or Command Line Tools.

Clone the repository and run the checks:

```sh
git clone https://github.com/reathloo/smartClip.git
cd smartClip
zsh scripts/run-dev.sh --check
```

Useful commands:

```sh
zsh scripts/run-dev.sh          # build and restart the real app
zsh scripts/run-dev.sh --ui     # isolated UI preview with sample data
zsh scripts/test.sh             # run all core checks
zsh scripts/build-app.sh        # create dist/SmartClip.app
```

The UI preview uses a private pasteboard and isolated temporary data. Use the real app only when testing Keychain, Accessibility, global shortcuts, launch at login, or another system integration.

## Making a change

1. Create a branch from the current `main` branch.
2. Preserve existing behavior unless the issue or proposal explicitly changes it.
3. Add or update checks for behavior changes.
4. Update documentation and localized text when user-visible behavior changes.
5. Run `zsh scripts/test.sh` and any relevant manual checks.
6. Review your diff for unrelated files, generated artifacts, credentials, and personal clipboard data.

Do not commit build output, signing credentials, Sparkle private keys, Keychain data, or real clipboard contents.

## Localization

SmartClip's supported documentation and app languages are English, German, Simplified Chinese, Japanese, and Korean. When changing user-visible copy:

- update every supported localization;
- keep placeholders and format specifiers unchanged;
- prefer concise, native wording over literal translation;
- verify that longer translations fit the interface;
- keep technical product names such as SmartClip, SwiftUI, AppKit, SQLite, AES-GCM, Keychain, and Sparkle unchanged.

## Pull requests

A useful pull request includes:

- a concise explanation of the problem and solution;
- a linked issue when one exists;
- the tests and manual checks performed;
- screenshots for visible interface changes;
- any known limitation or follow-up work.

Maintainers may ask for a smaller scope, additional verification, or wording changes before merging. Opening a pull request does not guarantee inclusion.
