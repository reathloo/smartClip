# SmartClip Test Report and Reproducible Verification

Last updated: October 30, 2026.

## Result

Run the automated suite with `zsh scripts/test.sh`. It contains **114 named checks** with multiple assertions. Machine-readable results are written to `.build/test-results/core.json`; console output is written to `.build/test-results/core.log`.

The initial 54-check run reproduced five failures. All five were fixed, and later integration coverage expanded the suite. UI checks are separate and are not counted among the 114 automated checks.

Tests use random temporary databases, isolated UserDefaults suites, named private pasteboards, and generated keys. They do not read real clipboard history or access the real Keychain. The shortcut check temporarily registers ⌃⌥⇧⌘F18/F19 and releases both combinations afterward. It fails with an explanation if another process already owns either shortcut.

## Fixed defects

1. All-zero numbers could pass the Luhn checksum and be classified as credit cards. They are now rejected.
2. URLs without a separate text representation were ignored. `public.url` is now supported.
3. Corrupt image data was stored as an image. It is now skipped with an explanation.
4. Recopying an unmarked value could unmask a sensitive entry. Automatic capture no longer downgrades sensitivity; manual reclassification remains available.
5. An expired sensitive entry could be recopied before the next timer tick. Expiration is now checked when the entry is retrieved.
6. Keychain waits blocked the main loop. Key loading now runs away from the UI thread; waiting, failure, and reopening are tested with controlled key loaders.
7. Rows could retain stale button state after pinning. Actions and labels now resolve the current model entry.
8. Enter during search immediately copied the first result. Enter now confirms the search; copying requires explicit arrow-key selection first.

Sensitive values receive a ConcealedType marker when copied. Hotkey handlers and timers are released with their owners. All settings windows share the same model.

## Automated coverage

| Area | Evidence | Limit |
| --- | --- | --- |
| Text, URL, email | Positive and negative classification, Unicode and NUL round trips, pasteboard representations | No semantic check that a URL is reachable |
| Password managers and cards | Concealed, Transient, and 1Password markers; valid and invalid Luhn numbers | Arbitrary unmarked passwords cannot be detected reliably |
| Images | PNG and TIFF reading, copying, decoding, 20 MiB limit, corrupt data | Not every image format or decompression-bomb scenario |
| Files | Multiple original references, missing originals, round trip, clipboard preserved on failure | Finder end-to-end check remains manual |
| Encryption | Empty, small, and 1 MiB payloads; random nonces; wrong key; tampering; truncated data | No independent security audit |
| Storage | Every type in SQLite, reopen, encrypted content in DB and WAL, corrupt record | Type, time, and app name metadata remain unencrypted |
| Duplicates and favorites | Text, image, and file groups; count, time, source, pin, encrypted name, search | UI ordering also checked interactively |
| Search and filters | Content and app name, case handling, type filter, limit, results beyond first page | Sensitive plaintext intentionally excluded from search |
| Retention | Every preset at its exact boundary, never, favorites, recopy, setting changes, expired retrieval | Controlled time rather than a multi-day real-time run |
| Capture | Onboarding, manual and timed pauses, restart pause, changeCount, exclusions, denied access, self-copy suppression | Operating-system permission state is simulated |
| Settings | Safe defaults and persistent view, pause, retention, exclusions, and onboarding | Launch at login and Accessibility permissions are not changed automatically |
| Copy | Original and masked values, URLs, email, images, files, Concealed marker, failure preservation | Automatic paste into third-party apps remains manual |
| Shortcut | Native registration, conflict, failed replacement, removal, release, callback | Physical global key routing remains manual |
| Window | Native close and minimize controls, movable and resizable panel, minimum size, reuse | Visibility, dragging, minimizing, and reopening need interactive confirmation |
| Startup | Key-loading failure, responsive UI during wait, reopening existing history with the same key | Real Keychain ACL and macOS restart remain manual |
| Updates | Embedded Sparkle framework, signed-feed configuration, menu action, package linkage, and public-key presence | Published feed and end-to-end replacement remain release acceptance checks |

## Direct UI check with sample data

The following behavior was checked in `.build/SmartClip Test.app` in Dark Mode:

- Searching for the sample note returns exactly one result.
- Search plus Enter keeps the history open; selecting with ↓ changes Enter to Copy.
- Text filtering shows regular and masked sensitive entries.
- List and card views preserve selection and update layout.
- Pin and unpin update order and button state.
- Sensitive content remains masked in accessibility labels.
- Mark as regular opens a confirmation before revealing the synthetic value.
- Settings open and the suggested shortcut can be registered in the test instance.
- Escape in the search field hides the history window.

Computer control sometimes activated the additional SwiftUI settings window after hiding the panel. This is not complete proof of global reopening, minimizing, or window-position persistence; those remain in the manual checklist.

## Open system acceptance checks

These require an interactive Mac and the relevant permissions. They are not marked as passed:

- [ ] Approve real Keychain access, restart, and reopen the same history. Do not create a replacement key when access is denied.
- [ ] Copy from a browser, Terminal, and Finder. Each copy appears once and the estimated source app is plausible.
- [ ] Copy a real image and multiple Finder files, then move or delete an original and verify the missing-file state.
- [ ] Deny and restore clipboard access; explain the state and capture nothing without permission.
- [ ] Trigger the shortcut from another app, hide and reopen the panel, report conflicts, record a custom shortcut, and cancel recording with Escape.
- [ ] Move and resize the window; close with the red button, ⌘W, and Escape; minimize with the yellow button; reopen with the shortcut; preserve position during the session.
- [ ] Copy only leaves the target app unchanged. With Accessibility permission, automatic paste inserts once into the previous app. Without permission, copied content remains available.
- [ ] Open a synthetic HTTP(S) URL in the default browser.
- [ ] Enable launch at login, sign out and back in, verify one menu-bar instance, disable it, and repeat.
- [ ] Measure idle CPU and memory with real capture running, then test a long history and several large images.
- [ ] Run on macOS 14 to confirm the declared minimum version.
- [ ] Publish a signed test appcast, update from the previous version, and verify history and settings survive relaunch.

## Known limits

- Browser page metadata is not inspected. SmartClip shows the estimated source app and the copied URL when available.
- JSON, color, and IP actions, statistics, synchronization, Developer ID signing, notarization, and public distribution are outside this beta.
- Retention removes SmartClip entries, not plaintext already placed on the system clipboard.
- SmartClip does not claim universal password detection or forensic deletion from SSDs and backups.
- `swift test` is blocked here because the active Command Line Tools do not provide XCTest. The shared checks run through the debug executable; the XCTest integration requires full Xcode.

## Run the tests

```sh
zsh scripts/test.sh
zsh scripts/build-ui-test-app.sh
open '.build/SmartClip Test.app'
```

The test app does not monitor the real clipboard. Copy uses a private pasteboard; automatic paste, browser opening, and launch at login are disabled. Generated data is removed during normal termination. A forced stop can leave randomly named `dev.smartclip.uitest.*` temporary files or preferences. Do not confuse the test app with `dist/SmartClip.app`.

With full Xcode, `swift test` runs the same core checks through XCTest. Render design previews with:

```sh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift run SmartClip --render-design
```

## Coverage history

- **Code and language detection:** expanded the suite to 96 checks with 16 language patterns, ambiguous syntax, Markdown fences, prose negatives, persistence, filters, language search, copying, legacy text migration, and masked sensitive code.
- **UI and codebase review, October 4, 2026:** expanded to 104 checks covering retention boundaries, SQL cleanup, keyboard selection, current row index, access status, and recovery.
- **Convenience features, October 8, 2026:** expanded to 110 checks covering timed pauses, restart pause, menu-bar menu structure, direct app exclusion, recovery actions, encrypted favorite names, and migration.
- **Per-entry retention, October 12, 2026:** expanded to 112 checks. Regular entries support 7, 30, 90, or 365 days and Never; sensitive entries remain limited to 5 minutes, 1 hour, or 24 hours.
- **Unsigned release package, October 20, 2026:** package verification checks the read-only DMG, Applications link, minimum version, architecture, ad hoc signature, checksum, and expected Gatekeeper rejection.
- **Release controls, October 20, 2026:** expanded to 113 checks. Delete all history requires confirmation, removes every entry, and preserves settings and the system clipboard. About SmartClip shows version, requirements, local processing, and documentation links.
- **History responsiveness, October 30, 2026:** expanded to 114 checks. Unchanged history refreshes no longer publish another list update; search focus and row rendering were checked in the local test app.
