# Privacy

SmartClip processes clipboard history locally on your Mac. It has no account, telemetry, cloud synchronization, or server upload.

- Content, image data, file paths, favorite names, and entry notes are stored encrypted in SQLite.
- The encryption key is stored in the macOS Keychain.
- Technical metadata such as time, type, and estimated source app is not encrypted.
- Retention removes entries from SmartClip. It does not remove the current macOS clipboard content or data stored in backups.
- Files are not duplicated. SmartClip stores encrypted references to the originals.
- Notes stay attached to their SmartClip entry. They are never added to copied or dragged content and are deleted with the entry.
- Automatic paste requires Accessibility permission. Copy only works without this permission.
- Sensitive-content detection recognizes known pasteboard markers and unambiguous credit card numbers. It cannot reliably detect every password.
- By default, detected sensitive entries are encrypted, masked, excluded from content search, and given shorter retention limits. You can instead configure SmartClip to never store them.
- The configurable storage limit is based on encrypted payload size. When it is reached, SmartClip removes the oldest unpinned entries first and never removes pinned favorites automatically.
- Drag-and-drop is disabled for sensitive entries and missing file references.
