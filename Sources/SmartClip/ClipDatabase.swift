import Foundation
import CSQLite

enum DatabaseError: LocalizedError {
    case sqlite(String)
    case invalidRecord

    var errorDescription: String? {
        switch self {
        case .sqlite(let detail): "Datenbankfehler: \(detail)"
        case .invalidRecord: "Ein Verlaufseintrag ist beschädigt."
        }
    }
}

@MainActor
final class ClipDatabase {
    private var db: OpaquePointer?
    private let crypto: CryptoStore
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String, crypto: CryptoStore) throws {
        self.crypto = crypto
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw DatabaseError.sqlite("Datenbank konnte nicht geöffnet werden")
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA secure_delete=ON")
        try execute("""
            CREATE TABLE IF NOT EXISTS clips (
                id TEXT PRIMARY KEY,
                digest BLOB NOT NULL UNIQUE,
                kind TEXT NOT NULL,
                created REAL NOT NULL,
                last_copied REAL NOT NULL,
                source_name TEXT,
                source_bundle TEXT,
                sensitive INTEGER NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0,
                copy_count INTEGER NOT NULL DEFAULT 1,
                favorite_name BLOB,
                retention_seconds INTEGER,
                payload BLOB NOT NULL
            )
            """)
        if try !hasColumn("favorite_name", in: "clips") {
            try execute("ALTER TABLE clips ADD COLUMN favorite_name BLOB")
        }
        if try !hasColumn("retention_seconds", in: "clips") {
            try execute("ALTER TABLE clips ADD COLUMN retention_seconds INTEGER")
        }
        try execute("CREATE INDEX IF NOT EXISTS clips_order ON clips(pinned DESC, last_copied DESC)")
    }

    isolated deinit { sqlite3_close(db) }

    private func message() -> String { String(cString: sqlite3_errmsg(db)) }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw DatabaseError.sqlite(message()) }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw DatabaseError.sqlite(message())
        }
        return stmt
    }

    private func hasColumn(_ column: String, in table: String) throws -> Bool {
        let stmt = try prepare("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(stmt) }
        while try nextRow(stmt) {
            if columnString(stmt, 1) == column { return true }
        }
        return false
    }

    /// Distinguish end-of-results from SQLite failures instead of returning partial data.
    private func nextRow(_ stmt: OpaquePointer) throws -> Bool {
        switch sqlite3_step(stmt) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw DatabaseError.sqlite(message())
        }
    }

    private func bind(_ string: String?, to index: Int32, in stmt: OpaquePointer) {
        guard let string else { sqlite3_bind_null(stmt, index); return }
        _ = string.withCString { sqlite3_bind_text(stmt, index, $0, -1, transient) }
    }

    private func bind(_ data: Data, to index: Int32, in stmt: OpaquePointer) {
        _ = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(stmt, index, bytes.baseAddress, Int32(bytes.count), transient)
        }
    }

    private func columnString(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: ptr)
    }

    private func columnData(_ stmt: OpaquePointer, _ index: Int32) -> Data? {
        guard let ptr = sqlite3_column_blob(stmt, index) else { return nil }
        return Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, index)))
    }

    func capture(_ payload: ClipPayload, sourceName: String?, sourceBundleID: String?, sensitive: Bool, at date: Date = .now) throws {
        let encoded = try payload.encodedData()
        let digest = crypto.digest(payload.fingerprintData())
        let sealed = try crypto.seal(encoded)
        let stmt = try prepare("""
            INSERT INTO clips (id, digest, kind, created, last_copied, source_name, source_bundle, sensitive, pinned, copy_count, payload)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 1, ?)
            ON CONFLICT(digest) DO UPDATE SET
                last_copied=excluded.last_copied,
                kind=excluded.kind,
                source_name=excluded.source_name,
                source_bundle=excluded.source_bundle,
                sensitive=MAX(clips.sensitive, excluded.sensitive),
                copy_count=clips.copy_count+1,
                payload=excluded.payload
            """)
        defer { sqlite3_finalize(stmt) }
        bind(UUID().uuidString, to: 1, in: stmt)
        bind(digest, to: 2, in: stmt)
        bind(payload.kind.rawValue, to: 3, in: stmt)
        sqlite3_bind_double(stmt, 4, date.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 5, date.timeIntervalSince1970)
        bind(sourceName, to: 6, in: stmt)
        bind(sourceBundleID, to: 7, in: stmt)
        sqlite3_bind_int(stmt, 8, sensitive ? 1 : 0)
        bind(sealed, to: 9, in: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqlite(message()) }
    }

    func list(search: String = "", kind: ClipKind? = nil, limit: Int = 200) throws -> [ClipSummary] {
        guard limit > 0 else { return [] }
        let stmt = try prepare("""
            SELECT id, kind, last_copied, source_name, source_bundle, sensitive, pinned, copy_count, payload, favorite_name, retention_seconds
            FROM clips ORDER BY pinned DESC, last_copied DESC
            """)
        defer { sqlite3_finalize(stmt) }
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [ClipSummary] = []
        while results.count < limit, try nextRow(stmt) {
            guard let idString = columnString(stmt, 0), let id = UUID(uuidString: idString),
                  let kindString = columnString(stmt, 1), let rowKind = ClipKind(rawValue: kindString) else { continue }
            // Old text rows can become code on read; other types cannot change.
            if let kind, rowKind != kind, !(rowKind == .text && kind == .code) { continue }
            var displayKind = rowKind
            var codeLanguage: String?
            let sourceName = columnString(stmt, 3)
            let sensitive = sqlite3_column_int(stmt, 5) != 0
            let favoriteName: String?
            if let sealedName = columnData(stmt, 9) {
                favoriteName = String(data: try crypto.open(sealedName), encoding: .utf8)
            } else {
                favoriteName = nil
            }
            var preview = sensitive ? "••••••••" : rowKind == .image ? "Bild" : ""
            var missing = false
            let sourceMatches = sourceName?.localizedCaseInsensitiveContains(needle) == true
            if rowKind != .image, let sealed = columnData(stmt, 8) {
                let payload = try PropertyListDecoder().decode(ClipPayload.self, from: crypto.open(sealed))
                if rowKind == .text || rowKind == .code,
                   let text = payload.text, let language = CodeDetector.detect(text) {
                    displayKind = .code
                    if !sensitive { codeLanguage = language.rawValue }
                }
                if !sensitive { preview = payload.preview }
                missing = payload.hasMissingFiles
            }
            if let kind, kind != displayKind { continue }
            if !needle.isEmpty && !sourceMatches && favoriteName?.localizedCaseInsensitiveContains(needle) != true
                && !preview.localizedCaseInsensitiveContains(needle)
                && codeLanguage?.localizedCaseInsensitiveContains(needle) != true { continue }
            results.append(ClipSummary(
                id: id, kind: displayKind,
                lastCopiedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                sourceName: sourceName, sourceBundleID: columnString(stmt, 4),
                isSensitive: sensitive, isPinned: sqlite3_column_int(stmt, 6) != 0,
                copyCount: Int(sqlite3_column_int(stmt, 7)), preview: preview,
                hasMissingFiles: missing, codeLanguage: codeLanguage, favoriteName: favoriteName,
                retentionOverrideSeconds: sqlite3_column_type(stmt, 10) == SQLITE_NULL
                    ? nil : Int(sqlite3_column_int64(stmt, 10))
            ))
        }
        return results
    }

    func payload(for id: UUID) throws -> ClipPayload? {
        let stmt = try prepare("SELECT payload FROM clips WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        bind(id.uuidString, to: 1, in: stmt)
        guard try nextRow(stmt) else { return nil }
        guard let sealed = columnData(stmt, 0) else { throw DatabaseError.invalidRecord }
        return try PropertyListDecoder().decode(ClipPayload.self, from: crypto.open(sealed))
    }

    func setPinned(_ pinned: Bool, for id: UUID) throws { try setFlag("pinned", value: pinned, id: id) }
    func setSensitive(_ sensitive: Bool, for id: UUID) throws {
        let stmt = try prepare("UPDATE clips SET sensitive=?, retention_seconds=NULL WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, sensitive ? 1 : 0)
        bind(id.uuidString, to: 2, in: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqlite(message()) }
    }

    func setRetentionOverride(seconds: Int?, for id: UUID) throws {
        let stmt = try prepare("UPDATE clips SET retention_seconds=? WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        if let seconds { sqlite3_bind_int64(stmt, 1, sqlite3_int64(seconds)) }
        else { sqlite3_bind_null(stmt, 1) }
        bind(id.uuidString, to: 2, in: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqlite(message()) }
    }

    func setFavoriteName(_ name: String?, for id: UUID) throws {
        let stmt = try prepare("UPDATE clips SET favorite_name=? WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        if let name { bind(try crypto.seal(Data(name.utf8)), to: 1, in: stmt) }
        else { sqlite3_bind_null(stmt, 1) }
        bind(id.uuidString, to: 2, in: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqlite(message()) }
    }

    private func setFlag(_ column: String, value: Bool, id: UUID) throws {
        let stmt = try prepare("UPDATE clips SET \(column)=? WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, value ? 1 : 0)
        bind(id.uuidString, to: 2, in: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqlite(message()) }
    }

    func delete(_ id: UUID) throws {
        let stmt = try prepare("DELETE FROM clips WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        bind(id.uuidString, to: 1, in: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqlite(message()) }
    }

    @discardableResult
    func deleteAll() throws -> Int {
        try execute("DELETE FROM clips")
        let deleted = Int(sqlite3_changes(db))
        // Payloads are encrypted, but truncating the WAL also removes stale metadata pages.
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
        return deleted
    }

    func purge(normalDays: Int?, sensitiveSeconds: TimeInterval, now: Date = .now) throws -> Int {
        // One atomic statement avoids a full Swift-side scan and a transaction per row.
        let stmt = try prepare("""
            DELETE FROM clips
            WHERE (sensitive != 0 AND last_copied +
                    CASE WHEN retention_seconds IN (300, 3600, 86400) THEN retention_seconds ELSE ? END <= ?)
               OR (sensitive = 0 AND retention_seconds > 0 AND last_copied + retention_seconds <= ?)
               OR (sensitive = 0 AND retention_seconds IS NULL AND pinned = 0
                   AND ? IS NOT NULL AND last_copied <= ?)
            """)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, sensitiveSeconds)
        sqlite3_bind_double(stmt, 2, now.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 3, now.timeIntervalSince1970)
        if let normalDays {
            let cutoff = now.timeIntervalSince1970 - Double(normalDays) * 86_400
            sqlite3_bind_double(stmt, 4, cutoff)
            sqlite3_bind_double(stmt, 5, cutoff)
        } else {
            sqlite3_bind_null(stmt, 4)
            sqlite3_bind_null(stmt, 5)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.sqlite(message()) }
        return Int(sqlite3_changes(db))
    }

    func knownApps() throws -> [(String, String)] {
        let stmt = try prepare("SELECT source_bundle, COALESCE(MAX(source_name), source_bundle) FROM clips WHERE source_bundle IS NOT NULL GROUP BY source_bundle ORDER BY 2")
        defer { sqlite3_finalize(stmt) }
        var apps: [(String, String)] = []
        while try nextRow(stmt) {
            if let bundle = columnString(stmt, 0), let name = columnString(stmt, 1) { apps.append((bundle, name)) }
        }
        return apps
    }
}
