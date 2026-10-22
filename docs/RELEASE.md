# Release Process

SmartClip is currently distributed for free without an Apple Developer ID or notarization.

## Create the package

```sh
zsh scripts/package-release.sh v0.1.0-beta.1
```

The script runs all 113 core checks, creates the production app and DMG, then verifies the checksum, contents, architecture, minimum macOS version, and expected Gatekeeper rejection. Output is written to `dist/release/`.

## Before publishing

- Complete the open system checks in [TEST_REPORT.md](TEST_REPORT.md) on a physical Mac.
- Confirm that the Git working tree is clean and the package matches the release commit.
- Review the release notes and version number.
- Install the DMG in a separate user account by following [INSTALLATION.md](INSTALLATION.md).

## GitHub Release

1. Create tag `v0.1.0-beta.1` on the verified commit.
2. Create a GitHub Release named **SmartClip v0.1.0-beta.1** and mark it as a **pre-release**.
3. Upload:
   - `SmartClip-0.1.0-beta.1-macOS-arm64.dmg`
   - `SmartClip-0.1.0-beta.1-macOS-arm64.dmg.sha256`
   - `SmartClip-0.1.0-beta.1-macOS-arm64.txt`
4. Use [releases/v0.1.0-beta.1.md](releases/v0.1.0-beta.1.md) as the description.

Only authorized GitHub users can download a release from a private repository.
