# Privacy

SmartClip processes clipboard history locally on your Mac. It has no account, telemetry, cloud synchronization, or server upload.

- Content, image data, file paths, and favorite names are stored encrypted in SQLite.
- The encryption key is stored in the macOS Keychain.
- Technical metadata such as time, type, and estimated source app is not encrypted.
- Retention removes entries from SmartClip. It does not remove the current macOS clipboard content or data stored in backups.
- Files are not duplicated. SmartClip stores encrypted references to the originals.
- Automatic paste requires Accessibility permission. Copy only works without this permission.
- Sensitive-content detection recognizes known pasteboard markers and unambiguous credit card numbers. It cannot reliably detect every password.
