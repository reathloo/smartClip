#if DEBUG
import AppKit
import Combine
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
        model = AppModel(defaults: defaults, pasteboard: pasteboard, database: db, now: { time },
                         systemIntegrationsEnabled: false)
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
    for card in ["4111 1111 1111 1111", "5555-5555-5555-4444", "378282246310005", "Card: 6011111111111117."] {
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
    integration("database.encrypted-named-favorite-search-and-dedup") { f in
        let secretName = "Mein geheimer Textbaustein"
        try f.capture(.text("reusable content"))
        let id = try f.row().id
        try f.db.setFavoriteName(secretName, for: id)
        try f.db.setPinned(true, for: id)
        try f.capture(.text("reusable content"), at: f.time.addingTimeInterval(10))
        let favorite = try f.db.list(search: "Textbaustein").first
        try expect(favorite?.id == id && favorite?.favoriteName == secretName && favorite?.isPinned == true,
                   "Named favorite was not searchable or survived deduplication")
        for name in ["history.sqlite", "history.sqlite-wal"] {
            let data = try Data(contentsOf: f.directory.appendingPathComponent(name))
            try expect(data.range(of: Data(secretName.utf8)) == nil, "Favorite name stored as plaintext")
        }
        try f.db.setFavoriteName(nil, for: id)
        try expect(try f.row().favoriteName == nil, "Favorite name was not removed")
    }
    test("database.favorite-name-migrates-existing-history") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SmartClipMigration-\(UUID())")
        let path = directory.appendingPathComponent("history.sqlite").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var handle: OpaquePointer?
        try expect(sqlite3_open(path, &handle) == SQLITE_OK, "Cannot create legacy database")
        let legacySchema = """
            CREATE TABLE clips (
                id TEXT PRIMARY KEY, digest BLOB NOT NULL UNIQUE, kind TEXT NOT NULL,
                created REAL NOT NULL, last_copied REAL NOT NULL, source_name TEXT,
                source_bundle TEXT, sensitive INTEGER NOT NULL, pinned INTEGER NOT NULL DEFAULT 0,
                copy_count INTEGER NOT NULL DEFAULT 1, payload BLOB NOT NULL
            )
            """
        try expect(sqlite3_exec(handle, legacySchema, nil, nil, nil) == SQLITE_OK, "Cannot create legacy schema")
        sqlite3_close(handle)
        _ = try ClipDatabase(path: path, crypto: CryptoStore(key: SymmetricKey(size: .bits256)))
        try expect(sqlite3_open(path, &handle) == SQLITE_OK, "Cannot reopen migrated database")
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        try expect(sqlite3_prepare_v2(handle, "PRAGMA table_info(clips)", -1, &statement, nil) == SQLITE_OK,
                   "Cannot inspect migrated schema")
        defer { sqlite3_finalize(statement) }
        var columns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            columns.insert(String(cString: sqlite3_column_text(statement, 1)))
        }
        try expect(columns.contains("favorite_name") && columns.contains("retention_seconds"),
                   "Existing database did not receive new columns")
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
    integration("database.per-entry-retention-overrides") { f in
        try f.capture(.text("thirty days"), at: f.time.addingTimeInterval(-8 * 86_400))
        let thirtyDays = try f.row()
        try f.db.setPinned(true, for: thirtyDays.id)
        try f.db.setRetentionOverride(seconds: 30 * 86_400, for: thirtyDays.id)

        try f.capture(.text("never"), at: f.time.addingTimeInterval(-400 * 86_400))
        let never = try f.db.list().first { $0.preview == "never" }!
        try f.db.setRetentionOverride(seconds: 0, for: never.id)

        try f.capture(.text("seven days"), at: f.time.addingTimeInterval(-8 * 86_400))
        let sevenDays = try f.db.list().first { $0.preview == "seven days" }!
        try f.db.setPinned(true, for: sevenDays.id)
        try f.db.setRetentionOverride(seconds: 7 * 86_400, for: sevenDays.id)

        try expect(try f.db.purge(normalDays: 7, sensitiveSeconds: 3_600, now: f.time) == 1,
                   "Per-entry expiry did not override pin/global policy")
        let survivors = try f.db.list()
        try expect(survivors.contains { $0.id == thirtyDays.id && $0.retentionOverrideSeconds == 30 * 86_400 },
                   "30-day override was lost")
        try expect(survivors.contains { $0.id == never.id && $0.retentionOverrideSeconds == 0 },
                   "Never override expired")

        try f.db.capture(.text("thirty days"), sourceName: "Again", sourceBundleID: nil,
                         sensitive: false, at: f.time)
        let refreshed = try f.db.list().first { $0.id == thirtyDays.id }!
        try expect(refreshed.retentionOverrideSeconds == 30 * 86_400 && refreshed.lastCopiedAt == f.time,
                   "Duplicate did not preserve and restart entry retention")
    }
    integration("model.delete-all-history") { f in
        try f.capture(.text("normal"))
        try f.capture(.text("secret"), sensitive: true)
        try f.capture(.text("favorite"))
        let favorite = try f.db.list().first { $0.preview == "favorite" }!
        try f.db.setPinned(true, for: favorite.id)
        try f.write("system clipboard remains")
        f.model.refresh()
        try expect(f.model.items.count == 3, "Delete-all fixture incomplete")
        f.model.deleteAllHistory()
        try expect(try f.db.list().isEmpty && f.model.items.isEmpty, "Delete-all kept history entries")
        try expect(f.pasteboard.string(forType: .string) == "system clipboard remains",
                   "Delete-all changed the system clipboard")
        try expect(f.model.normalDays == 30, "Delete-all changed settings")
        try expect(f.model.statusMessage.contains("3 entries"), "Delete-all result was not explained")
        f.model.deleteAllHistory()
        try expect(f.model.statusMessage.contains("already empty"), "Empty delete-all was not explained")
    }
    integration("model.per-entry-retention-and-sensitive-reset") { f in
        try f.capture(.text("custom retention"))
        f.model.refresh()
        let item = f.model.items[0]
        f.model.setRetentionOverride(30 * 86_400, for: item)
        try expect(f.model.item(for: item.id)?.retentionOverrideSeconds == 30 * 86_400,
                   "Model did not apply entry retention")
        f.model.markSensitive(f.model.item(for: item.id)!, true)
        try expect(f.model.item(for: item.id)?.retentionOverrideSeconds == nil,
                   "Sensitive classification kept an incompatible normal override")
        f.model.setRetentionOverride(0, for: f.model.item(for: item.id)!)
        try expect(f.model.item(for: item.id)?.retentionOverrideSeconds == nil,
                   "Sensitive entry accepted never retention")
    }
    integration("model.safe-defaults-and-persistent-settings") { f in
        try expect(f.model.shortcut == nil && !f.model.autoPaste && !f.model.onboardingComplete, "Unsafe first-run default")
        try expect(f.model.normalDays == 30 && f.model.sensitiveSeconds == 3_600, "Wrong retention default")
        f.model.setCardView(true); f.model.setDarkMode(true); f.model.setPaused(true); f.model.setNormalDays(90)
        f.model.setSensitiveSeconds(300); f.model.setExcluded("  test.excluded  ", excluded: true)
        f.model.setExcluded("   ", excluded: true); f.model.setMonitoring(true)
        let reloaded = AppModel(defaults: f.defaults, pasteboard: f.pasteboard)
        try expect(reloaded.cardView && reloaded.darkMode && reloaded.isPaused && reloaded.onboardingComplete,
                   "Settings not persisted")
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
    integration("model.temporary-and-restart-pause") { f in
        f.model.pause(for: 15 * 60)
        try expect(f.model.isPaused && f.model.captureStatusLabel.contains("until"), "Timed pause not visible")
        try expect(f.defaults.bool(forKey: "paused") == false, "Timed pause persisted as manual pause")
        f.model.updateTimedPause(at: f.time.addingTimeInterval(899))
        try expect(f.model.isPaused, "Timed pause ended early")
        f.model.updateTimedPause(at: f.time.addingTimeInterval(900))
        try expect(!f.model.isPaused, "Timed pause did not end")
        f.model.pauseUntilRestart()
        try expect(f.model.isPaused && f.model.captureStatusLabel.contains("next launch"), "Restart pause not visible")
        let relaunched = AppModel(defaults: f.defaults, pasteboard: f.pasteboard)
        try expect(!relaunched.isPaused, "Restart pause survived relaunch")
    }
    integration("model.excluded-and-access-denied") { f in
        f.model.setMonitoring(true)
        f.model.setExcluded("test.excluded", excluded: true)
        try f.write("excluded"); f.poll(bundle: "test.excluded")
        try expect(try f.db.list().isEmpty, "Excluded app captured")
        try f.write("denied"); f.poll(denied: true)
        try expect(try f.db.list().isEmpty && f.model.statusMessage.contains("blocked"), "Denial not respected/explained")
        try f.write("allowed"); f.poll()
        try expect(try f.db.list().count == 1, "Allowed copy not captured")
    }
    integration("model.exclude-source-from-entry-and-recovery-action") { f in
        try f.capture(.text("source"), source: "Browser", bundle: "test.browser")
        f.model.excludeSourceApp(of: try f.row())
        try expect(f.model.excludedBundles.contains("test.browser") && f.model.statusMessage.contains("Browser"),
                   "Source app was not excluded from entry")
        f.model.setMonitoring(true)
        try f.write("denied"); f.poll(denied: true)
        try expect(f.model.recoveryAction == .openClipboardSettings, "Denied access has no recovery action")
        f.model.performRecovery()
        try expect(f.model.statusMessage.contains("test mode"), "Recovery action was not routed safely in tests")
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
        try expect(f.model.statusMessage.contains("missing"), "Missing file not explained")
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
    integration("model.name-favorite-pins-and-unpin-clears-name") { f in
        try f.capture(.text("snippet")); f.model.refresh()
        f.model.nameFavorite(try f.row(), "Support-Antwort")
        var row = try f.row()
        try expect(row.isPinned && row.favoriteName == "Support-Antwort", "Naming did not pin favorite")
        f.model.pin(row)
        row = try f.row()
        try expect(!row.isPinned && row.favoriteName == nil, "Unpinning kept an orphaned favorite name")
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
        try expect(!first.register(alternate) { fired += 100 }, "Conflicting replacement accepted")
        first.fire()
        try expect(fired == 2, "Failed replacement changed the active callback")
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
    integration("database.bulk-expiry") { f in
        for index in 0..<500 {
            try f.capture(.text("expiry-\(index)"), at: f.time.addingTimeInterval(-31 * 86_400))
        }
        let start = Date()
        let removed = try f.db.purge(normalDays: 30, sensitiveSeconds: 3_600, now: f.time)
        print("METRIC expiry of 500 entries: \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        try expect(removed == 500 && f.db.list().isEmpty, "Bulk expiry failed")
    }
    test("navigation.search-enter-and-explicit-selection") {
        let ids = [UUID(), UUID(), UUID()]
        try expect(HistoryNavigation.selected(in: ids, explicit: nil, search: "query") == nil, "Search Enter selects a result implicitly")
        let selected = HistoryNavigation.moved(in: ids, explicit: nil, search: "query", offset: 1)
        try expect(selected == ids[0], "First arrow skips first search result")
        try expect(HistoryNavigation.selected(in: ids, explicit: selected, search: "query") == ids[0], "Explicit selection lost")
        try expect(HistoryNavigation.selected(in: ids, explicit: nil, search: "  ") == ids[0], "Default selection changed")
    }
    test("navigation.bounds-empty-and-removed-selection") {
        let ids = [UUID(), UUID()]
        try expect(HistoryNavigation.moved(in: [], explicit: nil, search: "", offset: 1) == nil, "Empty list selected")
        try expect(HistoryNavigation.moved(in: ids, explicit: ids[0], search: "", offset: -1) == ids[0], "Moved before start")
        try expect(HistoryNavigation.moved(in: ids, explicit: ids[1], search: "", offset: 1) == ids[1], "Moved beyond end")
        try expect(HistoryNavigation.selected(in: ids, explicit: UUID(), search: "") == nil, "Removed row reused")
        try expect(HistoryNavigation.moved(in: ids, explicit: nil, search: "query", offset: -1) == ids[1], "Up did not select last search result")
    }
    integration("model.current-item-index-updates-and-removes") { f in
        try f.capture(.text("indexed")); f.model.refresh()
        let original = try f.row()
        try expect(f.model.item(for: original.id)?.isPinned == false, "Initial index missing")
        f.model.pin(original)
        try expect(f.model.item(for: original.id)?.isPinned == true, "Pin snapshot stale")
        f.model.markSensitive(original, true)
        try expect(f.model.item(for: original.id)?.preview == "••••••••", "Sensitive snapshot stale")
        f.model.delete(original)
        try expect(f.model.item(for: original.id) == nil, "Deleted row retained by index")
    }
    integration("model.unchanged-refresh-does-not-republish-history") { f in
        try f.capture(.text("stable"))
        var publications = 0
        let observation = f.model.$items.dropFirst().sink { _ in publications += 1 }
        f.model.refresh()
        let publicationsAfterFirstRefresh = publications
        f.model.refresh()
        withExtendedLifetime(observation) {}
        try expect(publicationsAfterFirstRefresh == 1, "Initial history refresh was not published")
        try expect(publications == publicationsAfterFirstRefresh, "Unchanged history was published again")
    }
    integration("model.search-flush-before-keyboard-selection") { f in
        try f.capture(.text("first")); try f.capture(.text("second"))
        f.model.refresh()
        f.model.scheduleSearch("first")
        f.model.applySearchImmediately("second")
        let ids = f.model.items.map(\.id)
        let selected = HistoryNavigation.moved(in: ids, explicit: nil, search: f.model.search, offset: 1)
        try expect(selected != nil && f.model.item(for: selected!)?.preview == "second", "Keyboard used old search results")
        f.model.filter = .url; f.model.applySearchImmediately()
        try expect(f.model.items.isEmpty, "Filter not applied")
        f.model.resetSearch()
        try expect(f.model.search.isEmpty && f.model.filter == nil && f.model.items.count == 2, "Reset search/filter failed")
    }
    integration("model.capture-status-denied-and-recovery-without-new-copy") { f in
        try expect(f.model.captureState == .setup, "Unconfigured status wrong")
        f.model.setMonitoring(true)
        try expect(f.model.captureState == .active, "Active status wrong")
        f.poll(denied: true)
        try expect(f.model.captureState == .denied, "Denied access advertised as active")
        f.model.setPaused(true)
        try expect(f.model.captureState == .paused, "Paused status wrong")
        f.model.setPaused(false); f.poll(denied: false)
        try expect(f.model.captureState == .active, "Access recovery not detected")
        let unavailable = AppModel(defaults: f.defaults, pasteboard: f.pasteboard)
        try expect(unavailable.captureState == .unavailable, "Unavailable storage advertised as active")
    }
    integration("database.expiry-sql-matches-retention-policy") { f in
        for normalDays in [nil, 7, 30, 90, 365] as [Int?] {
            for seconds in [300.0, 3_600, 86_400] {
                var expected: Set<UUID> = []
                var all: [UUID] = []
                let ages: [TimeInterval] = [
                    seconds - 1, seconds, seconds + 1,
                    604_799, 604_800, 2_592_000, 7_776_000, 31_536_000, -1
                ]
                for sensitive in [false, true] {
                    for pinned in [false, true] {
                        for age in ages {
                            let value = UUID().uuidString
                            let date = f.time.addingTimeInterval(-age)
                            try f.capture(.text(value), sensitive: sensitive, at: date)
                            let row = try f.db.list(limit: 1000).first { $0.lastCopiedAt == date && !all.contains($0.id) }!
                            all.append(row.id)
                            try f.db.setPinned(pinned, for: row.id)
                            if !Retention.expired(lastCopiedAt: date, sensitive: sensitive, pinned: pinned,
                                                  normalDays: normalDays, sensitiveSeconds: seconds, now: f.time) {
                                expected.insert(row.id)
                            }
                        }
                    }
                }
                let removed = try f.db.purge(normalDays: normalDays, sensitiveSeconds: seconds, now: f.time)
                try expect(removed == all.count - expected.count, "Expiry count differs from policy")
                let survivors = try f.db.list(limit: 1000)
                try expect(Set(survivors.map(\.id)) == expected, "SQL expiry differs from policy")
                for row in survivors { try f.db.delete(row.id) }
            }
        }
    }
    integration("database.zero-limit-and-filter-skip-unrelated-payload") { f in
        try f.capture(.text("corrupt text"))
        var handle: OpaquePointer?
        try expect(sqlite3_open(f.path, &handle) == SQLITE_OK, "Cannot open fixture")
        defer { sqlite3_close(handle) }
        try expect(sqlite3_exec(handle, "UPDATE clips SET payload=x'00'", nil, nil, nil) == SQLITE_OK, "Cannot corrupt fixture")
        try f.capture(.text("https://example.org"))
        try expect(try f.db.list(limit: 0).isEmpty, "Zero limit still decoded rows")
        try expect(try f.db.list(kind: .url).count == 1, "URL filter decoded unrelated text")
        try expectFailure { _ = try f.db.list() }
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
    integration("menu-bar.pause-actions") { f in
        let delegate = AppDelegate(model: f.model)
        var titles = delegate.makeStatusMenu().items.map(\.title)
        try expect(titles.contains("Pause for 15 minutes") && titles.contains("Pause until next launch"),
                   "Menu-bar pause actions missing")
        try expect(titles.contains("Check for Updates …"), "Menu-bar update action missing")
        f.model.pauseUntilRestart()
        titles = delegate.makeStatusMenu().items.map(\.title)
        try expect(titles.first == "Resume capture", "Paused menu cannot resume capture")
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
        try expect(model.statusMessage.contains("Could not open history"), "Key failure hidden")
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
        let waiting = model.statusMessage.contains("Keychain")
        gate.signal()
        await task.value
        try expect(responsive && waiting, "Main actor blocked while loading key")
        try expect(model.statusMessage == "History ready.", "Successful startup not completed")
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
