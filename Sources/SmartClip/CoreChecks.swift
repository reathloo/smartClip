#if DEBUG
import AppKit
import CryptoKit
import CSQLite
import Carbon

private struct CheckFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw CheckFailure(message: message) }
}
private func expectFailure(_ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    throw CheckFailure(message: "Expected an error, but operation succeeded")
}

@MainActor
private final class Fixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SmartClipTests-\(UUID())")
    let suite = "dev.smartclip.tests.\(UUID())"
    let defaults: UserDefaults
    let pasteboard = NSPasteboard.withUniqueName()
    let crypto = CryptoStore(key: SymmetricKey(size: .bits256))
    let db: ClipDatabase
    let model: AppModel
    let time = Date(timeIntervalSince1970: 1_700_000_000)
    var path: String { directory.appendingPathComponent("history.sqlite").path }

    init() throws {
        defaults = UserDefaults(suiteName: suite)!
        db = try ClipDatabase(path: directory.appendingPathComponent("history.sqlite").path, crypto: crypto)
        let time = time
        model = AppModel(defaults: defaults, pasteboard: pasteboard, database: db, now: { time })
    }
    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }
    func capture(_ payload: ClipPayload, sensitive: Bool = false, at date: Date? = nil,
                 source: String = "Test App", bundle: String = "test.app") throws {
        try db.capture(payload, sourceName: source, sourceBundleID: bundle, sensitive: sensitive, at: date ?? time)
    }
    func write(_ text: String, marker: String? = nil) throws {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if let marker { item.setString("", forType: .init(marker)) }
        try expect(pasteboard.writeObjects([item]), "Failed to write private test pasteboard")
    }
    func poll(denied: Bool = false, bundle: String = "test.app") {
        model.processChanges(sourceName: "Test App", sourceBundleID: bundle, accessDenied: denied)
    }
    func read() throws -> (ClipPayload, Bool) {
        guard case .captured(let payload, let sensitive) = ClipboardReader.read(pasteboard) else {
            throw CheckFailure(message: "Expected captured clipboard content")
        }
        return (payload, sensitive)
    }
    func row() throws -> ClipSummary {
        guard let row = try db.list().first else { throw CheckFailure(message: "Missing history row") }
        return row
    }
}

private struct CheckResult: Codable {
    let name: String
    let passed: Bool
    let detail: String?
}

/// Runs the same suite from the debug CLI and XCTest, without accessing the user's
/// clipboard, keychain, preferences, or history. Each integration case has its own fixtures.
@MainActor
func runCoreChecks() async throws {
    var results: [CheckResult] = []
    func test(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            results.append(CheckResult(name: name, passed: true, detail: nil))
            print("PASS \(name)")
        } catch {
            results.append(CheckResult(name: name, passed: false, detail: error.localizedDescription))
            print("FAIL \(name): \(error.localizedDescription)")
        }
    }
    func integration(_ name: String, _ body: (Fixture) throws -> Void) {
        test(name) {
            let f = try Fixture()
            defer { f.cleanup() }
            try body(f)
        }
    }
    func png() throws -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        bitmap.setColor(NSColor(deviceRed: 0.1, green: 0.5, blue: 0.4, alpha: 1), atX: 0, y: 0)
        return bitmap.representation(using: .png, properties: [:])!
    }

    for (text, kind) in [("https://example.org/a?q=1", ClipKind.url), ("HTTP://example.org", .url),
                         ("person+tag@example.org", .email), ("hello\nworld 👋", .text),
                         ("javascript:alert(1)", .text), ("file:///tmp/a", .text),
                         ("https://example.org with spaces", .text), ("a@b", .text)] {
        test("classification.\(text)") { try expect(ClipPayload.text(text).kind == kind, "Wrong content type") }
    }
    for card in ["4111 1111 1111 1111", "5555-5555-5555-4444", "378282246310005", "Karte: 6011111111111117."] {
        test("sensitive.valid-card.\(card)") { try expect(ClipClassifier.isSensitive(text: card), "Valid Luhn number missed") }
    }
    for value in ["4111111111111112", "0000000000000000", "123456789012", "1234567890123456789012345", "tR!cky-password-42", "ordinary text"] {
        test("sensitive.negative.\(value)") { try expect(!ClipClassifier.isSensitive(text: value), "False sensitive detection") }
    }
    for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword"] {
        test("sensitive.marker.\(marker)") { try expect(ClipClassifier.isSensitive(text: nil, pasteboardTypes: [marker]), "Marker ignored") }
    }
    test("sensitive.unrelated-marker") {
        try expect(!ClipClassifier.isSensitive(text: "hello", pasteboardTypes: ["public.utf8-plain-text"]), "Unrelated type marked sensitive")
    }
    test("payload.serialization-and-fingerprint") {
        for payload in [ClipPayload.text("nul\0é 👋"), .files(["/a|b", "/c"]), .image(try png())] {
            let decoded = try PropertyListDecoder().decode(ClipPayload.self, from: payload.encodedData())
            try expect(decoded == payload, "Payload round trip failed")
        }
        try expect(ClipPayload.files(["/a", "/b"]).fingerprintData() != ClipPayload.files(["/a/b"]).fingerprintData(), "Ambiguous file fingerprint")
    }
    test("crypto.authentication-and-random-nonce") {
        let a = CryptoStore(key: SymmetricKey(size: .bits256))
        let b = CryptoStore(key: SymmetricKey(size: .bits256))
        for data in [Data(), Data("private test value 👋".utf8), Data(repeating: 42, count: 1_024 * 1_024)] {
            let encrypted = try a.seal(data)
            try expect(try a.open(encrypted) == data, "Round trip failed")
            try expect(try a.seal(data) != encrypted, "Nonce reused")
            try expectFailure { _ = try b.open(encrypted) }
            var changed = encrypted; changed[changed.count - 1] ^= 1
            try expectFailure { _ = try a.open(changed) }
            try expectFailure { _ = try a.open(encrypted.prefix(8)) }
        }
        try expect(a.digest(Data("a".utf8)) != b.digest(Data("a".utf8)), "Digest not key-specific")
    }
    for days in [7, 30, 90, 365] {
        test("retention.normal-\(days)-boundary") {
            let start = Date(timeIntervalSince1970: 0)
            let end = start.addingTimeInterval(Double(days) * 86_400)
            try expect(!Retention.expired(lastCopiedAt: start, sensitive: false, pinned: false, normalDays: days, sensitiveSeconds: 3600, now: end.addingTimeInterval(-1)), "Expired early")
            try expect(Retention.expired(lastCopiedAt: start, sensitive: false, pinned: false, normalDays: days, sensitiveSeconds: 3600, now: end), "Boundary not expired")
            try expect(!Retention.expired(lastCopiedAt: start, sensitive: false, pinned: true, normalDays: days, sensitiveSeconds: 3600, now: end), "Favorite expired")
        }
    }
    for seconds in [300.0, 3_600, 86_400] {
        test("retention.sensitive-\(Int(seconds))-boundary") {
            let start = Date(timeIntervalSince1970: 0)
            for pinned in [false, true] {
                try expect(!Retention.expired(lastCopiedAt: start, sensitive: true, pinned: pinned, normalDays: nil, sensitiveSeconds: seconds, now: start.addingTimeInterval(seconds - 1)), "Sensitive expired early")
                try expect(Retention.expired(lastCopiedAt: start, sensitive: true, pinned: pinned, normalDays: nil, sensitiveSeconds: seconds, now: start.addingTimeInterval(seconds)), "Sensitive favorite survived")
            }
        }
    }
    test("retention.never") {
        try expect(!Retention.expired(lastCopiedAt: .distantPast, sensitive: false, pinned: false, normalDays: nil, sensitiveSeconds: 3600, now: .now), "Never expired")
    }
    integration("clipboard.text-url-email-marked-password") { f in
        for value in ["plain text", "https://example.org", "hi@example.org"] {
            try f.write(value)
            try expect(try f.read().0 == .text(value), "Text clipboard changed")
        }
        try f.write("test-password", marker: "org.nspasteboard.ConcealedType")
        try expect(try f.read().1, "Password marker lost")
    }
    integration("clipboard.url-only-representation") { f in
        f.pasteboard.setString("https://example.org", forType: .URL)
        try expect(try f.read().0.kind == .url, "URL-only clipboard missed")
    }
    integration("clipboard.empty-and-unsupported") { f in
        try f.write("")
        if case .captured = ClipboardReader.read(f.pasteboard) { throw CheckFailure(message: "Empty content captured") }
        f.pasteboard.clearContents()
        f.pasteboard.setData(Data([1, 2]), forType: .init("test.unsupported"))
        if case .captured = ClipboardReader.read(f.pasteboard) { throw CheckFailure(message: "Unsupported data captured") }
    }
    integration("clipboard.png-and-tiff") { f in
        let data = try png()
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            f.pasteboard.clearContents()
            f.pasteboard.setData(type == .png ? data : NSImage(data: data)!.tiffRepresentation!, forType: type)
            let payload = try f.read().0
            try expect(payload.kind == .image && NSImage(data: payload.imageData!) != nil, "Image decode failed")
        }
    }
    integration("clipboard.image-over-20mb") { f in
        f.pasteboard.setData(Data(repeating: 0, count: 20 * 1_024 * 1_024 + 1), forType: .png)
        guard case .skipped(let reason) = ClipboardReader.read(f.pasteboard), reason?.contains("20 MB") == true else {
            throw CheckFailure(message: "Oversized image not explained/skipped")
        }
    }
    integration("clipboard.corrupt-image") { f in
        f.pasteboard.setData(Data("not an image".utf8), forType: .png)
        guard case .skipped(let reason) = ClipboardReader.read(f.pasteboard), reason != nil else {
            throw CheckFailure(message: "Corrupt image saved")
        }
    }
    integration("clipboard.multiple-files-and-missing-reference") { f in
        let urls = [f.directory.appendingPathComponent("a.txt"), f.directory.appendingPathComponent("b.pdf")]
        for url in urls { try Data("fixture".utf8).write(to: url) }
        try expect(f.pasteboard.writeObjects(urls as [NSURL]), "File pasteboard write failed")
        let payload = try f.read().0
        try expect(payload.filePaths == urls.map(\.path), "Files lost or reordered")
        try expect(!payload.hasMissingFiles, "Existing files marked missing")
        try FileManager.default.removeItem(at: urls[0])
        try expect(payload.hasMissingFiles, "Deleted original not detected")
    }
    integration("database.all-types-reopen") { f in
        let payloads: [ClipPayload] = [.text("persistent text"), .text("https://example.org"), .text("x@y.org"), .image(try png()), .files(["/test/private-file"])]
        for (index, payload) in payloads.enumerated() { try f.capture(payload, at: f.time.addingTimeInterval(Double(index))) }
        let reopened = try ClipDatabase(path: f.path, crypto: f.crypto)
        let rows = try reopened.list()
        try expect(rows.count == payloads.count, "Reopen lost rows")
        for row in rows { try expect(try payloads.contains(reopened.payload(for: row.id)!), "Reopen payload changed") }
        let wrongKey = try ClipDatabase(path: f.path, crypto: CryptoStore(key: SymmetricKey(size: .bits256)))
        try expectFailure { _ = try wrongKey.payload(for: rows[0].id) }
    }
    integration("database.no-plaintext-in-db-or-wal") { f in
        let secret = "UNIQUE-TEST-SECRET-6DD82A9F"
        let path = "/private/UNIQUE-TEST-PATH-AD531F"
        let bytes = Data("UNIQUE-TEST-IMAGE-BYTES-37A922".utf8)
        try f.capture(.text(secret), sensitive: true)
        try f.capture(.files([path]))
        try f.capture(.image(bytes))
        for name in ["history.sqlite", "history.sqlite-wal"] {
            let data = try Data(contentsOf: f.directory.appendingPathComponent(name))
            for token in [Data(secret.utf8), Data(path.utf8), bytes] {
                try expect(data.range(of: token) == nil, "Plaintext content on disk")
            }
        }
    }
    integration("database.dedup-order-source-count-pin") { f in
        try f.capture(.text("repeat"))
        let id = try f.row().id
        try f.db.setPinned(true, for: id)
        try f.capture(.text("other"), at: f.time.addingTimeInterval(5))
        try f.capture(.text("repeat"), at: f.time.addingTimeInterval(10), source: "Second", bundle: "test.second")
        let rows = try f.db.list()
        try expect(rows.count == 2 && rows[0].id == id && rows[0].isPinned, "Dedup/pin failed")
        try expect(rows[0].copyCount == 2 && rows[0].sourceName == "Second" && rows[0].sourceBundleID == "test.second", "Metadata not refreshed")
        try expect(rows[0].lastCopiedAt == f.time.addingTimeInterval(10), "Timestamp not refreshed")
        try f.db.setPinned(false, for: id)
        try expect(try f.row().id == id, "Most recent not first")
    }
    integration("database.duplicate-must-not-remove-sensitive-flag") { f in
        try f.capture(.text("marked secret"), sensitive: true)
        try f.capture(.text("marked secret"), sensitive: false)
        try expect(try f.row().isSensitive, "Unmarked duplicate exposed sensitive content")
        try f.db.setSensitive(false, for: f.row().id)
        try expect(try !f.row().isSensitive, "Explicit manual reclassification failed")
    }
    integration("database.search-filter-limit-and-mask") { f in
        try f.capture(.text("Café HELLO"))
        try f.capture(.text("https://example.org"), source: "Browser")
        try f.capture(.text("secret-no-search"), sensitive: true, source: "Vault")
        try expect(try f.db.list(search: "hello").count == 1, "Case-insensitive search failed")
        try expect(try f.db.list(search: "Browser", kind: .url).count == 1, "Source search/filter failed")
        try expect(try f.db.list(search: "hello", kind: .url).isEmpty, "Filter ignored")
        try expect(try f.db.list(limit: 1).count == 1 && f.db.list(limit: 0).isEmpty, "Limit ignored")
        try expect(try f.db.list(search: "secret-no-search").isEmpty, "Sensitive search exposed secret")
        try expect(try f.db.list(search: "Vault").first?.preview == "••••••••", "Sensitive preview unmasked")
        try expect(try f.db.knownApps().count == 1, "Source apps not deduplicated")
    }
    integration("database.retention-refresh-delete") { f in
        try f.capture(.text("old"), at: f.time.addingTimeInterval(-31 * 86_400))
        try f.capture(.text("pin"), at: f.time.addingTimeInterval(-400 * 86_400))
        let pinned = try f.db.list(search: "pin")[0]
        try f.db.setPinned(true, for: pinned.id)
        try f.capture(.text("secret"), sensitive: true, at: f.time.addingTimeInterval(-3_600))
        let secret = try f.db.list().first { $0.isSensitive }!
        try f.db.setPinned(true, for: secret.id)
        try f.capture(.text("refreshed"), at: f.time.addingTimeInterval(-31 * 86_400))
        try f.capture(.text("refreshed"))
        try expect(try f.db.purge(normalDays: 30, sensitiveSeconds: 3_600, now: f.time) == 2, "Wrong expiry count")
        try expect(try f.db.list().count == 2, "Pinned or refreshed row removed")
        try f.db.delete(pinned.id)
        try expect(try f.db.payload(for: pinned.id) == nil, "Delete failed")
        try expect(try f.db.payload(for: UUID()) == nil, "Missing ID returns content")
    }
    integration("model.safe-defaults-and-persistent-settings") { f in
        try expect(f.model.shortcut == nil && !f.model.autoPaste && !f.model.onboardingComplete, "Unsafe first-run default")
        try expect(f.model.normalDays == 30 && f.model.sensitiveSeconds == 3_600, "Wrong retention default")
        f.model.setCardView(true); f.model.setPaused(true); f.model.setNormalDays(90)
        f.model.setSensitiveSeconds(300); f.model.setExcluded("  test.excluded  ", excluded: true)
        f.model.setExcluded("   ", excluded: true); f.model.setMonitoring(true)
        let reloaded = AppModel(defaults: f.defaults, pasteboard: f.pasteboard)
        try expect(reloaded.cardView && reloaded.isPaused && reloaded.onboardingComplete, "Settings not persisted")
        try expect(reloaded.normalDays == 90 && reloaded.sensitiveSeconds == 300, "Retention not persisted")
        try expect(reloaded.excludedBundles == ["test.excluded"], "Exclusions not trimmed/persisted")
        f.model.setExcluded("test.excluded", excluded: false)
        try expect(f.model.excludedBundles.isEmpty, "Unexclude failed")
    }
    integration("model.onboarding-pause-and-change-count") { f in
        try f.write("before opt in"); f.poll()
        try expect(try f.db.list().isEmpty, "Captured before consent")
        f.model.setMonitoring(true); f.poll()
        try expect(try f.db.list().isEmpty, "Captured stale clipboard at opt in")
        try f.write("new copy"); f.poll(); f.poll()
        try expect(try f.row().copyCount == 1, "Unchanged clipboard recaptured")
        f.model.setPaused(true); try f.write("while paused"); f.poll()
        f.model.setPaused(false); f.poll()
        try expect(try f.db.list().count == 1, "Paused content captured")
        try f.write("after resume"); f.poll()
        try expect(try f.db.list().count == 2, "Resume failed")
    }
    integration("model.excluded-and-access-denied") { f in
        f.model.setMonitoring(true)
        f.model.setExcluded("test.excluded", excluded: true)
        try f.write("excluded"); f.poll(bundle: "test.excluded")
        try expect(try f.db.list().isEmpty, "Excluded app captured")
        try f.write("denied"); f.poll(denied: true)
        try expect(try f.db.list().isEmpty && f.model.statusMessage.contains("gesperrt"), "Denial not respected/explained")
        try f.write("allowed"); f.poll()
        try expect(try f.db.list().count == 1, "Allowed copy not captured")
    }
    integration("model.copy-original-secret-and-no-self-recapture") { f in
        f.model.setMonitoring(true)
        try f.write("test-secret", marker: "org.nspasteboard.ConcealedType"); f.poll()
        let item = try f.row()
        try expect(item.isSensitive && item.preview == "••••••••", "Secret preview exposed")
        var closed = false
        f.model.onClosePanel = { closed = true }
        f.model.copy(item)
        try expect(f.pasteboard.string(forType: .string) == "test-secret" && closed, "Original secret not copied/window not dismissed")
        try expect(try f.read().1, "Sensitive marker lost when copied back")
        f.poll()
        try expect(try f.row().copyCount == 2 && f.row().isSensitive, "Own copy recaptured or downgraded")
        try expect(try f.db.purge(normalDays: 30, sensitiveSeconds: 3_600, now: f.time.addingTimeInterval(3_600)) == 1, "Secret not purged")
        try expect(f.pasteboard.string(forType: .string) == "test-secret", "Purge modified system-equivalent clipboard")
    }
    integration("model.copy-all-types") { f in
        let file = f.directory.appendingPathComponent("original.txt")
        try Data("fixture".utf8).write(to: file)
        for payload in [ClipPayload.text("hello"), .text("https://example.org"), .text("a@b.org"), .files([file.path]), .image(try png())] {
            try f.capture(payload)
            let row = try f.db.list(kind: payload.kind).first!
            f.model.copy(row)
            let actual = try f.read().0
            try expect(actual.kind == payload.kind, "Copied type changed")
            if payload.kind != .image { try expect(actual == payload, "Copied value changed") }
            else { try expect(NSImage(data: actual.imageData!) != nil, "Copied image invalid") }
        }
    }
    integration("model.missing-file-does-not-clear-clipboard") { f in
        try f.capture(.files([f.directory.appendingPathComponent("missing").path]))
        try f.write("keep this")
        f.model.copy(try f.row())
        try expect(f.pasteboard.string(forType: .string) == "keep this", "Missing file cleared clipboard")
        try expect(f.model.statusMessage.contains("fehlen"), "Missing file not explained")
    }
    integration("model.expired-secret-cannot-be-revived-by-copy") { f in
        try f.capture(.text("expired"), sensitive: true, at: f.time.addingTimeInterval(-3_601))
        let old = try f.row()
        try f.write("keep")
        f.model.copy(old)
        try expect(f.pasteboard.string(forType: .string) == "keep", "Expired secret copied")
        try expect(try f.db.list().isEmpty, "Expired secret revived")
    }
    integration("model.pin-sensitive-and-delete-actions") { f in
        try f.capture(.text("action target"))
        f.model.refresh(); f.model.pin(try f.row())
        try expect(try f.row().isPinned && f.model.items.first?.isPinned == true, "Pin not reflected")
        f.model.markSensitive(try f.row(), true)
        try expect(try f.row().isSensitive && f.model.items.first?.preview == "••••••••", "Mark sensitive failed")
        f.model.markSensitive(try f.row(), false)
        try expect(try f.row().preview == "action target", "Manual normal classification failed")
        f.model.delete(try f.row())
        try expect(f.model.items.isEmpty, "Delete not reflected")
    }
    integration("database.corrupted-payload-rejected") { f in
        try f.capture(.text("authenticated record"))
        let id = try f.row().id
        var handle: OpaquePointer?
        try expect(sqlite3_open(f.path, &handle) == SQLITE_OK, "Cannot open fixture database")
        defer { sqlite3_close(handle) }
        try expect(sqlite3_exec(handle, "UPDATE clips SET payload=x'00010203'", nil, nil, nil) == SQLITE_OK, "Cannot corrupt fixture")
        try expectFailure { _ = try f.db.payload(for: id) }
        try expectFailure { _ = try f.db.list() }
        try f.write("keep original")
        f.model.copy(ClipSummary(id: id, kind: .text, lastCopiedAt: f.time, sourceName: nil,
                                sourceBundleID: nil, isSensitive: false, isPinned: false,
                                copyCount: 1, preview: "fixture", hasMissingFiles: false))
        try expect(f.pasteboard.string(forType: .string) == "keep original", "Corrupt payload cleared clipboard")
    }
    integration("database.images-and-file-groups-deduplicate") { f in
        let image = ClipPayload.image(try png())
        let files = ClipPayload.files(["/fixture/a", "/fixture/b"])
        for payload in [image, image, files, files] { try f.capture(payload) }
        let rows = try f.db.list()
        try expect(rows.count == 2 && rows.allSatisfy { $0.copyCount == 2 }, "Binary/file dedup failed")
    }
    integration("model.search-and-type-filter") { f in
        try f.capture(.text("find this")); try f.capture(.text("https://example.org"))
        f.model.search = "find"; f.model.refresh()
        try expect(f.model.items.count == 1 && f.model.items[0].kind == .text, "Model search not applied")
        f.model.filter = .url; f.model.refresh()
        try expect(f.model.items.isEmpty, "Model filter ignored")
        f.model.search = ""; f.model.refresh()
        try expect(f.model.items.count == 1 && f.model.items[0].kind == .url, "Clearing search failed")
    }
    integration("model.never-and-shorter-retention-settings") { f in
        try f.capture(.text("old"), at: f.time.addingTimeInterval(-400 * 86_400))
        f.model.setNormalDays(0)
        try expect(try f.db.list().count == 1, "Never setting not honored")
        f.model.setNormalDays(7)
        try expect(try f.db.list().isEmpty, "Shorter normal retention not applied")
        try f.capture(.text("sensitive"), sensitive: true, at: f.time.addingTimeInterval(-301))
        f.model.setSensitiveSeconds(300)
        try expect(try f.db.list().isEmpty, "Shorter sensitive retention not applied")
    }
    integration("model.unchanged-poll-does-not-create-or-touch-rows") { f in
        f.model.setMonitoring(true); try f.write("once"); f.poll()
        let before = try f.row()
        let start = Date()
        for _ in 0..<1_000 { f.poll() }
        let after = try f.row()
        try expect(after.copyCount == 1 && before.lastCopiedAt == after.lastCopiedAt, "Idle polling changed database")
        print("METRIC 1000 unchanged capture polls: \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    }
    integration("database.search-beyond-first-page") { f in
        let start = Date()
        for index in 0..<250 {
            try f.capture(.text("entry-\(index)"), at: f.time.addingTimeInterval(Double(index)))
        }
        try expect(try f.db.list().count == 200, "Default page limit changed")
        try expect(try f.db.list(search: "entry-0").count == 1, "Search only examined first page")
        print("METRIC 250 encrypted inserts and history/search queries: \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    }
    test("hotkey.registration-conflict-replacement-and-release") {
        let first = HotkeyManager()
        let second = HotkeyManager()
        let primary = Shortcut(keyCode: UInt32(kVK_F19), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey), display: "Test F19")
        let alternate = Shortcut(keyCode: UInt32(kVK_F18), modifiers: primary.modifiers, display: "Test F18")
        defer { _ = first.register(nil) {}; _ = second.register(nil) {} }
        var fired = 0
        try expect(first.register(primary) { fired += 1 }, "Test chord is unavailable")
        first.fire(); try expect(fired == 1, "Hotkey callback failed")
        try expect(!second.register(primary) {}, "Duplicate shortcut accepted")
        try expect(second.register(alternate) {}, "Alternate test chord unavailable")
        try expect(!first.register(alternate) {}, "Conflicting replacement accepted")
        try expect(!second.register(primary) {}, "Failed replacement released original shortcut")
        try expect(first.register(nil) {}, "Shortcut removal failed")
        try expect(second.register(primary) {}, "Removed shortcut was not released")
    }
    let codeSamples: [(String, CodeLanguage)] = [
        ("def greet(name):\n    return name", .python),
        ("const value = 42;\nconsole.log(value);", .javascript),
        ("const value: number = 42;", .typescript),
        ("func greet(name: String) -> String { return name }", .swift),
        ("#!/bin/zsh\necho hello", .shell),
        (#"{"enabled": true, "count": 3}"#, .json),
        ("<div class=\"card\">Hello</div>", .html),
        (".card { color: red; }", .css),
        ("SELECT name FROM users WHERE active = 1;", .sql),
        ("package main\nfunc main() { fmt.Println(42) }", .go),
        ("fn main() { println!(\"Hello\"); }", .rust),
        ("System.out.println(\"Hello\");", .java),
        ("#include <stdio.h>\nint main(void) { return 0; }", .c),
        ("std::cout << value;", .cpp),
        ("Console.WriteLine(\"Hello\");", .csharp),
        ("<?php echo $name;", .php),
        ("if (ready) { run(); }", .unknown),
        ("let value = 42", .unknown),
        ("var value = 42;", .unknown),
        ("func greet() { work() }", .unknown),
        ("```python\nprint('hi')\n```", .python),
        ("```elixir\nIO.puts(42)\n```", .unknown)
    ]
    for (index, sample) in codeSamples.enumerated() {
        test("code.language-\(sample.1.rawValue)-\(index)") {
            try expect(CodeDetector.detect(sample.0) == sample.1, "Wrong code language: \(String(describing: CodeDetector.detect(sample.0)))")
            try expect(ClipPayload.text(sample.0).kind == .code, "Code kind not assigned")
        }
    }
    for text in ["Please select a name from the list", "This function makes things easier.", "hello@example.org", "https://example.org", "42", "Meeting at 10:30", "{not valid json}"] {
        test("code.prose-negative-\(text)") { try expect(CodeDetector.detect(text) == nil, "Prose misclassified") }
    }
    integration("code.persistence-filter-search-and-copy") { f in
        let original = "def greet(name):\n    return name\n"
        try f.capture(.text(original))
        let row = try f.row()
        try expect(row.kind == .code && row.codeLanguage == "Python", "Code summary lost language")
        try expect(try f.db.list(kind: .code).count == 1 && f.db.list(kind: .text).isEmpty, "Code filter failed")
        try expect(try f.db.list(search: "Python").count == 1, "Language search failed")
        f.model.copy(row)
        try expect(f.pasteboard.string(forType: .string) == original, "Code formatting changed on copy")
        let reopened = try ClipDatabase(path: f.path, crypto: f.crypto)
        try expect(try reopened.list().first?.codeLanguage == "Python", "Language lost after reopening")
    }
    integration("code.legacy-text-and-dedup") { f in
        let original = "const value = 42;"
        let legacy = ClipPayload(kind: .text, text: original, imageData: nil, filePaths: nil)
        try f.capture(legacy)
        let id = try f.row().id
        try expect(try f.db.list(kind: .code).first?.id == id, "Old text not recognized as code")
        try f.capture(.text(original))
        let rows = try f.db.list()
        try expect(rows.count == 1 && rows[0].id == id && rows[0].copyCount == 2, "Reclassification duplicated old entry")
        try expect(try f.db.payload(for: id)?.kind == .code, "Stored type not updated on recopy")
    }
    integration("code.sensitive-stays-masked") { f in
        try f.capture(.text("const password = 'synthetic';"), sensitive: true)
        let row = try f.row()
        try expect(row.kind == .code && row.preview == "••••••••" && row.codeLanguage == nil, "Sensitive code metadata exposed")
        try expect(try f.db.list(search: "synthetic").isEmpty, "Sensitive code searchable")
        f.model.copy(row)
        try expect(f.pasteboard.string(forType: .string) == "const password = 'synthetic';", "Sensitive code not copied")
    }
    test("window.native-controls-and-sizing") {
        let panel = HistoryPanel()
        defer { panel.close() }
        try expect(panel.isMovable && panel.styleMask.contains(.resizable), "Window cannot move/resize")
        try expect(panel.standardWindowButton(.closeButton)?.isEnabled == true, "Close button missing")
        try expect(panel.standardWindowButton(.miniaturizeButton)?.isEnabled == true, "Minimize button missing")
        try expect(!panel.isReleasedWhenClosed && panel.canBecomeKey, "Window cannot be reused/focused")
        try expect(panel.contentMinSize == NSSize(width: 560, height: 540), "Minimum size not enforced")
    }

    func startupTest(_ name: String, _ body: (Fixture) async throws -> Void) async {
        do {
            let f = try Fixture()
            defer { f.cleanup() }
            try await body(f)
            results.append(CheckResult(name: name, passed: true, detail: nil))
            print("PASS \(name)")
        } catch {
            results.append(CheckResult(name: name, passed: false, detail: error.localizedDescription))
            print("FAIL \(name): \(error.localizedDescription)")
        }
    }
    await startupTest("startup.key-failure-is-visible") { f in
        let model = AppModel(defaults: f.defaults, pasteboard: f.pasteboard)
        await model.start(databaseURL: f.directory.appendingPathComponent("startup.sqlite")) {
            throw CryptoStoreError.keychain(-25293)
        }
        try expect(model.statusMessage.contains("Verlauf konnte nicht geöffnet"), "Key failure hidden")
        model.setMonitoring(true); try f.write("not stored")
        model.processChanges(sourceName: nil, sourceBundleID: nil)
        try expect(model.items.isEmpty, "Recording started without a key")
    }
    await startupTest("startup.waiting-key-does-not-block-main-actor") { f in
        let model = AppModel(defaults: f.defaults, pasteboard: f.pasteboard)
        let gate = DispatchSemaphore(value: 0)
        let crypto = f.crypto
        let start = Date()
        let task = Task { await model.start(databaseURL: f.directory.appendingPathComponent("startup.sqlite")) {
            _ = gate.wait(timeout: .now() + 2)
            return crypto
        } }
        try await Task.sleep(for: .milliseconds(30))
        let responsive = Date().timeIntervalSince(start) < 1
        let waiting = model.statusMessage.contains("Schlüsselbund")
        gate.signal()
        await task.value
        try expect(responsive && waiting, "Main actor blocked while loading key")
        try expect(model.statusMessage == "Verlauf bereit.", "Successful startup not completed")
        model.setMonitoring(true); try f.write("after startup")
        model.processChanges(sourceName: "Test", sourceBundleID: "test.startup")
        try expect(model.items.count == 1, "Capture unavailable after startup")
    }
    await startupTest("startup.reopens-existing-history-with-same-key") { f in
        try f.capture(.text("survives restart"))
        let time = f.time
        let model = AppModel(defaults: f.defaults, pasteboard: f.pasteboard, now: { time })
        let crypto = f.crypto
        await model.start(databaseURL: URL(fileURLWithPath: f.path)) { crypto }
        try expect(model.items.first?.preview == "survives restart", "Startup lost persisted history")
    }

    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/test-results")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(results).write(to: directory.appendingPathComponent("core.json"))
    let failed = results.filter { !$0.passed }
    print("\n\(results.count - failed.count)/\(results.count) cases passed; \(failed.count) failed. Report: .build/test-results/core.json")
    if !failed.isEmpty { throw CheckFailure(message: "\(failed.count) test cases failed") }
}
#endif
