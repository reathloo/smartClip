# Release Process

SmartClip releases are built from version tags. The GitHub Actions workflow
runs the core checks, creates and verifies the styled DMG, publishes the GitHub
Release, signs the update with Sparkle EdDSA, and deploys `appcast.xml` to
GitHub Pages.

The app is currently ad hoc-signed and not notarized. Sparkle signatures secure
updates after installation, but they do not replace Apple Developer ID signing
or notarization for the first download.

## One-time repository setup

Local DMG creation requires Python 3.10 or newer. GitHub Actions installs the
required Python version automatically.

1. Authenticate GitHub CLI:

   ```sh
   gh auth login
   ```

2. Upload the existing Sparkle private key to GitHub Actions without printing it:

   ```sh
   zsh scripts/configure-update-secret.sh
   ```

   The matching public key is stored in `Resources/Info.plist`. Never generate a
   replacement key for later releases: installed copies trust this exact key.

3. In the GitHub repository settings, set **Pages → Build and deployment →
   Source** to **GitHub Actions**.

4. Make the release and Pages endpoints publicly readable. A private GitHub
   Release cannot be downloaded by Sparkle without authentication.

## Prepare a release

1. Update `CFBundleShortVersionString` and increment the numeric
   `CFBundleVersion` in `Resources/Info.plist`.
2. Add release notes at `docs/releases/vX.Y.Z.md`.
3. Complete the open system checks in [TEST_REPORT.md](TEST_REPORT.md).
4. Verify the repository is clean and run:

   ```sh
   zsh scripts/package-release.sh vX.Y.Z
   ```

5. Inspect the mounted DMG and confirm the app, Applications shortcut,
   background, labels, and first-launch hint are positioned correctly.

## Publish

Create and push the version tag on the verified commit:

```sh
git tag vX.Y.Z
git push origin vX.Y.Z
```

Tags containing a suffix such as `-beta.1` create a GitHub prerelease. Stable
tags create a normal release. The workflow uploads:

- `SmartClip-X.Y.Z-macOS-arm64.dmg`
- `SmartClip-X.Y.Z-macOS-arm64.dmg.sha256`
- `SmartClip-X.Y.Z-macOS-arm64.txt`
- `appcast.xml`

## Verify after publishing

1. Confirm the release workflow and GitHub Pages deployment succeeded.
2. Open `https://reathloo.github.io/smartClip/appcast.xml` without signing in.
3. Install the previous SmartClip version and choose **Check for Updates …**.
4. Confirm the new version downloads, validates, installs, and relaunches while
   preserving history and settings.
5. Download the published DMG and compare its SHA-256 with the uploaded checksum.

The feed is checked hourly by default. Update archives are accepted only when
their Sparkle EdDSA signature matches the public key embedded in the app.
