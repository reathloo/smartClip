# Install SmartClip

## Requirements

- Mac with Apple Silicon (M1 or newer)
- macOS 14 or newer

## Installation

1. Download `SmartClip-0.1.0-beta.2-macOS-arm64.dmg`.
2. Optionally verify the checksum in Terminal:

   ```sh
   shasum -a 256 -c SmartClip-0.1.0-beta.2-macOS-arm64.dmg.sha256
   ```

3. Open the DMG and drag **SmartClip.app** to **Applications**.
4. Open SmartClip once from Applications. macOS will report that it cannot verify the developer.
5. Open **System Settings → Privacy & Security** and choose **Open Anyway** for SmartClip.
6. Choose **Open** again in the confirmation dialog.

This confirmation is required because the free beta has no Apple Developer ID and is not notarized. macOS then records a local exception for this app. See Apple's guide: [Open a Mac app from an unidentified developer](https://support.apple.com/en-us/guide/mac-help/mh40616/mac).

## First launch

- Enable clipboard capture.
- Choose a global keyboard shortcut. SmartClip suggests `⌘⇧V`.
- Copy only works without Accessibility permission.
- Automatic paste requires permission under **Privacy & Security → Accessibility**.
- Launch at login is optional and can be enabled in SmartClip.

## Update

Release builds check for signed updates once per hour. By default, a trusted update is downloaded in the background and installed when SmartClip restarts. Use **Check for Updates …** in the menu-bar menu or Settings → About SmartClip to check immediately. Automatic installation can be disabled in Settings → General.

You can also update manually: quit SmartClip, open the new DMG, and replace the existing app in Applications. History and settings are stored outside the app bundle and remain available.

## Uninstall

Quit SmartClip, disable launch at login, and remove the app from Applications. This does not automatically remove history or settings.
