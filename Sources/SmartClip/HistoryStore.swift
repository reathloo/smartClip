import Foundation

struct HistoryQuery: Sendable, Equatable {
    var search: String = ""
    var kind: ClipKind?
}

struct HistoryCursor: Sendable, Equatable {
    let pinned: Bool
    let lastCopiedAt: Date
    let id: UUID
}

struct HistoryPage: Sendable, Equatable {
    let items: [ClipSummary]
    let nextCursor: HistoryCursor?
    let hasMore: Bool
}

struct StorageStatistics: Sendable, Equatable {
    let itemCount: Int
    let contentBytes: Int64
    let diskBytes: Int64
    let pinnedCount: Int

    static let empty = StorageStatistics(itemCount: 0, contentBytes: 0, diskBytes: 0, pinnedCount: 0)
}

struct QuotaResult: Sendable, Equatable {
    let removedCount: Int
    let blockedByPinnedItems: Bool
    let statistics: StorageStatistics
}

struct CaptureOutcome: Sendable, Equatable {
    let quota: QuotaResult?
}

/// Serializes SQLite and cryptographic work away from the main actor.
actor HistoryStore {
    private let database: ClipDatabase

    init(path: String, crypto: CryptoStore) throws {
        database = try ClipDatabase(path: path, crypto: crypto)
    }

    /// The caller transfers operational ownership of the adapter to this actor.
    init(database: ClipDatabase) {
        self.database = database
    }

    func capture(_ payload: ClipPayload, sourceName: String?, sourceBundleID: String?, sensitive: Bool,
                 at date: Date = .now, quotaBytes: Int64? = nil) throws -> CaptureOutcome {
        try database.capture(payload, sourceName: sourceName, sourceBundleID: sourceBundleID,
                             sensitive: sensitive, at: date)
        let quota = try quotaBytes.map { try database.enforceQuota(bytes: $0) }
        return CaptureOutcome(quota: quota)
    }

    func page(_ query: HistoryQuery = HistoryQuery(), after cursor: HistoryCursor? = nil,
              limit: Int = 100) throws -> HistoryPage {
        try database.page(query: query, after: cursor, limit: limit)
    }

    func payload(for id: UUID) throws -> ClipPayload? { try database.payload(for: id) }
    func note(for id: UUID) throws -> String? { try database.note(for: id) }
    func setPinned(_ pinned: Bool, for id: UUID) throws { try database.setPinned(pinned, for: id) }
    func setSensitive(_ sensitive: Bool, for id: UUID) throws { try database.setSensitive(sensitive, for: id) }
    func setRetentionOverride(seconds: Int?, for id: UUID) throws {
        try database.setRetentionOverride(seconds: seconds, for: id)
    }
    func setFavoriteName(_ name: String?, for id: UUID) throws { try database.setFavoriteName(name, for: id) }
    func setNote(_ note: String?, for id: UUID) throws { try database.setNote(note, for: id) }
    func delete(_ id: UUID) throws { try database.delete(id) }
    func deleteAll() throws -> Int { try database.deleteAll() }
    func deleteUnpinned() throws -> Int { try database.deleteUnpinned() }
    func purge(normalDays: Int?, sensitiveSeconds: TimeInterval, now: Date = .now) throws -> Int {
        try database.purge(normalDays: normalDays, sensitiveSeconds: sensitiveSeconds, now: now)
    }
    func knownApps() throws -> [(String, String)] { try database.knownApps() }
    func statistics() throws -> StorageStatistics { try database.statistics() }
    func enforceQuota(bytes: Int64) throws -> QuotaResult { try database.enforceQuota(bytes: bytes) }
}
