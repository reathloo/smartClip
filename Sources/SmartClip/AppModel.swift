import AppKit
import ApplicationServices
import Carbon
import Combine
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var items: [ClipSummary] = [] {
        didSet { itemsByID = items.reduce(into: [:]) { $0[$1.id] = $1 } }
    }
    private var itemsByID: [UUID: ClipSummary] = [:]
    @Published var search = ""
    @Published var showingSettings = false
    @Published var selectedID: UUID?
    @Published var previewedID: UUID?
    @Published var pendingDeleteID: UUID?
    @Published var focusSearchRequest = 0
    @Published var filter: ClipKind?
    @Published var timeFilter: HistoryTimeFilter = .all
    @Published var sourceBundleFilter: String?
    @Published var favoritesOnly = false
    @Published var cardView: Bool
    @Published var darkMode: Bool
    @Published var appearanceMode: AppearanceMode
    @Published var statusMessage = ""
    @Published private(set) var copyConfirmationMessage: String?
    @Published private(set) var recoveryAction: RecoveryAction?
    @Published private(set) var pauseMode: PauseMode
    @Published var shortcut: Shortcut?
    @Published var normalDays: Int
    @Published var sensitiveSeconds: Int
    @Published var storeSensitive: Bool
    @Published var storageLimitBytes: Int64
    @Published var autoPaste: Bool
    @Published var excludedBundles: Set<String>
    @Published var knownApps: [(String, String)] = []
    @Published var onboardingComplete: Bool
    @Published private(set) var storageReady = false
    @Published private(set) var clipboardAccessDenied = false
    @Published private(set) var hasMoreHistory = false
    @Published private(set) var isLoadingHistory = false
    @Published private(set) var isCleaningHistory = false
    @Published private(set) var storageStatistics = StorageStatistics.empty

    var isPaused: Bool { pauseMode.isPaused }
    var accessibilityPermissionGranted: Bool { AXIsProcessTrusted() }
    var captureStatusLabel: String { isPaused ? pauseMode.label(now: now()) : captureState.label }
    var hasActiveHistoryRefinements: Bool {
        timeFilter != .all || sourceBundleFilter != nil || favoritesOnly
    }

    var captureState: CaptureState {
        if !storageReady { return .unavailable }
        if !onboardingComplete { return .setup }
        if isPaused { return .paused }
        return clipboardAccessDenied ? .denied : .active
    }

    func item(for id: UUID) -> ClipSummary? { itemsByID[id] }

    /// Direct adapter used only by deterministic local fixtures. Production work
    /// crosses the actor-isolated `HistoryStore` seam below.
    private var database: ClipDatabase?
    private var historyStore: HistoryStore?
    private var historyCursor: HistoryCursor?
    private var historyGeneration = 0
    private let historyPageSize = 100
    private var pollTimer: Timer?
    private var purgeTimer: Timer?
    private var pauseTimer: Timer?
    private var searchTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private let now: () -> Date
    private let copyConfirmationDelay: TimeInterval
    private let systemIntegrationsEnabled: Bool
    private var lastChangeCount: Int
    var previousApp: NSRunningApplication?
    var onClosePanel: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    let hotkey = HotkeyManager()

    init(defaults: UserDefaults = .standard, pasteboard: NSPasteboard = .general,
         database: ClipDatabase? = nil, now: @escaping () -> Date = { .now },
         systemIntegrationsEnabled: Bool = true, copyConfirmationDelay: TimeInterval = 0.7) {
        self.defaults = defaults
        self.pasteboard = pasteboard
        self.database = database
        self.storageReady = database != nil
        self.now = now
        self.copyConfirmationDelay = copyConfirmationDelay
        self.systemIntegrationsEnabled = systemIntegrationsEnabled
        self.lastChangeCount = pasteboard.changeCount
        cardView = defaults.bool(forKey: "cardView")
        let initialAppearance = defaults.string(forKey: "appearanceMode").flatMap(AppearanceMode.init(rawValue:))
            ?? (defaults.bool(forKey: "darkMode") ? .midnight : .light)
        appearanceMode = initialAppearance
        darkMode = initialAppearance != .light
        pauseMode = defaults.bool(forKey: "paused") ? .manual : .active
        recoveryAction = nil
        normalDays = defaults.object(forKey: "normalDays") as? Int ?? 30
        sensitiveSeconds = defaults.object(forKey: "sensitiveSeconds") as? Int ?? 3_600
        storeSensitive = defaults.object(forKey: "storeSensitive") as? Bool ?? true
        storageLimitBytes = defaults.object(forKey: "storageLimitBytes") as? Int64 ?? 500 * 1_024 * 1_024
        autoPaste = defaults.bool(forKey: "autoPaste")
        excludedBundles = Set(defaults.stringArray(forKey: "excludedBundles") ?? [])
        onboardingComplete = defaults.bool(forKey: "onboardingComplete")
        if let data = defaults.data(forKey: "shortcut") {
            shortcut = try? JSONDecoder().decode(Shortcut.self, from: data)
        }
        if let database {
            storageStatistics = (try? database.statistics()) ?? .empty
        }
    }

    #if DEBUG
    static func designPreview() -> AppModel {
        let model = AppModel()
        model.cardView = false
        model.pauseMode = .active
        model.onboardingComplete = true
        model.storageReady = true
        model.shortcut = .suggested
        model.normalDays = 30
        model.sensitiveSeconds = 3_600
        model.autoPaste = false
        model.excludedBundles = ["com.apple.Terminal"]
        model.knownApps = [("com.apple.Safari", "Safari"), ("com.apple.Terminal", "Terminal")]
        return model
    }
    #endif

    func start(databaseURL: URL? = nil,
               keyLoader: @escaping @Sendable () throws -> CryptoStore = { try CryptoStore.loadOrCreate() }) async {
        // Keep the menu and shortcut usable while macOS waits for Keychain approval.
        if let shortcut { setShortcut(shortcut) }
        showStatus("Opening protected history… approve Keychain access if requested.")
        do {
            let crypto = try await Task.detached(priority: .userInitiated) { try keyLoader() }.value
            let url: URL
            if let databaseURL { url = databaseURL }
            else {
                let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                url = support.appendingPathComponent("SmartClip/history.sqlite")
            }
            let store = try await Task.detached(priority: .userInitiated) {
                try HistoryStore(path: url.path, crypto: crypto)
            }.value
            historyStore = store
            _ = try await store.purge(normalDays: normalDays == 0 ? nil : normalDays,
                                      sensitiveSeconds: TimeInterval(sensitiveSeconds), now: now())
            if storageLimitBytes > 0 { _ = try await store.enforceQuota(bytes: storageLimitBytes) }
            await refreshHistory(reset: true)
            knownApps = try await store.knownApps()
            storageStatistics = try await store.statistics()
            storageReady = true
            showStatus("History ready.")
        } catch {
            database = nil
            historyStore = nil
            storageReady = false
            showStatus("Could not open history: \(error.localizedDescription)", recovery: .retryStorage)
            return
        }
        pollTimer?.invalidate()
        purgeTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        purgeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.purgeAsync() }
        }
    }

    isolated deinit {
        pollTimer?.invalidate()
        purgeTimer?.invalidate()
        pauseTimer?.invalidate()
        searchTask?.cancel()
    }

    private func poll() async {
        updateTimedPause()
        guard onboardingComplete, !isPaused, historyStore != nil else { return }
        let denied: Bool
        if #available(macOS 26, *) { denied = pasteboard.accessBehavior == .alwaysDeny }
        else { denied = false }
        // Still notice permission changes without a new copy; resolve the app only for new content.
        guard pasteboard.changeCount != lastChangeCount || denied != clipboardAccessDenied else { return }
        let app = pasteboard.changeCount != lastChangeCount ? NSWorkspace.shared.frontmostApplication : nil
        await processChangesAsync(sourceName: app?.localizedName, sourceBundleID: app?.bundleIdentifier,
                                  accessDenied: denied)
    }

    /// Shared capture path; tests provide an isolated pasteboard and an explicit source.
    func processChanges(sourceName: String?, sourceBundleID: String?, accessDenied: Bool = false) {
        if database != nil {
            processChangesDirect(sourceName: sourceName, sourceBundleID: sourceBundleID,
                                 accessDenied: accessDenied)
        } else {
            Task { await processChangesAsync(sourceName: sourceName, sourceBundleID: sourceBundleID,
                                             accessDenied: accessDenied) }
        }
    }

    /// Deterministic async entry point for startup/integration checks.
    func processChangesAndWait(sourceName: String?, sourceBundleID: String?, accessDenied: Bool = false) async {
        if database != nil {
            processChangesDirect(sourceName: sourceName, sourceBundleID: sourceBundleID,
                                 accessDenied: accessDenied)
        } else {
            await processChangesAsync(sourceName: sourceName, sourceBundleID: sourceBundleID,
                                      accessDenied: accessDenied)
        }
    }

    private func processChangesDirect(sourceName: String?, sourceBundleID: String?, accessDenied: Bool) {
        guard onboardingComplete, !isPaused, let database else { return }
        guard let captured = capturedClipboardChange(sourceName: sourceName, sourceBundleID: sourceBundleID,
                                                     accessDenied: accessDenied) else { return }
        do {
            try database.capture(captured.payload, sourceName: sourceName,
                                 sourceBundleID: sourceBundleID, sensitive: captured.sensitive, at: now())
            try purge()
            if storageLimitBytes > 0 { _ = try database.enforceQuota(bytes: storageLimitBytes) }
            refresh()
            knownApps = try database.knownApps()
            storageStatistics = try database.statistics()
        } catch {
            showStatus(error.localizedDescription)
        }
    }

    private func processChangesAsync(sourceName: String?, sourceBundleID: String?, accessDenied: Bool) async {
        guard onboardingComplete, !isPaused, let historyStore else { return }
        guard let captured = capturedClipboardChange(sourceName: sourceName, sourceBundleID: sourceBundleID,
                                                     accessDenied: accessDenied) else { return }
        do {
            let outcome = try await historyStore.capture(
                captured.payload, sourceName: sourceName, sourceBundleID: sourceBundleID,
                sensitive: captured.sensitive, at: now(), quotaBytes: storageLimitBytes == 0 ? nil : storageLimitBytes
            )
            _ = try await historyStore.purge(normalDays: normalDays == 0 ? nil : normalDays,
                                             sensitiveSeconds: TimeInterval(sensitiveSeconds), now: now())
            await refreshHistory(reset: true)
            knownApps = try await historyStore.knownApps()
            storageStatistics = try await historyStore.statistics()
            if let quota = outcome.quota, quota.removedCount > 0 {
                showStatus("Storage limit reached. Removed \(quota.removedCount) oldest unpinned entries.")
            } else if outcome.quota?.blockedByPinnedItems == true {
                showStatus("Pinned entries exceed the storage limit. They were kept.")
            }
        } catch is CancellationError {
            return
        } catch {
            showStatus(error.localizedDescription)
        }
    }

    private func capturedClipboardChange(sourceName: String?, sourceBundleID: String?, accessDenied: Bool)
        -> (payload: ClipPayload, sensitive: Bool)? {
        if clipboardAccessDenied != accessDenied {
            clipboardAccessDenied = accessDenied
            showStatus(accessDenied ? "Clipboard access is blocked in System Settings."
                : "Clipboard access is available again.",
                       recovery: accessDenied ? .openClipboardSettings : nil)
        }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return nil }
        lastChangeCount = count
        if accessDenied {
            showStatus("Clipboard access is blocked in System Settings.", recovery: .openClipboardSettings)
            return nil
        }
        if let sourceBundleID, excludedBundles.contains(sourceBundleID) { return nil }
        let captured: (payload: ClipPayload, sensitive: Bool)
        switch ClipboardReader.read(pasteboard) {
        case .captured(let payload, let sensitive): captured = (payload, sensitive)
        case .skipped(let reason):
            if let reason { showStatus(reason) }
            return nil
        }
        if captured.sensitive && !storeSensitive {
            showStatus("Sensitive clipboard content was not stored.")
            return nil
        }
        return captured
    }

    func refresh() {
        guard let database else {
            searchTask?.cancel()
            searchTask = Task { await refreshHistory(reset: true) }
            return
        }
        do {
            let page = try database.page(query: historyQuery,
                                         after: nil, limit: historyPageSize)
            let refreshedItems = page.items
            historyCursor = page.nextCursor
            hasMoreHistory = page.hasMore
            storageStatistics = try database.statistics()
            guard refreshedItems != items else { return }
            items = refreshedItems
        }
        catch { showStatus(error.localizedDescription) }
    }

    func scheduleSearch(_ query: String? = nil) {
        let pendingQuery = query ?? search
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            if search != pendingQuery { search = pendingQuery }
            if database != nil { refresh() }
            else { await refreshHistory(reset: true) }
        }
    }

    func applySearchImmediately(_ query: String? = nil) {
        searchTask?.cancel()
        searchTask = nil
        if let query, search != query { search = query }
        if database != nil { refresh() }
        else { searchTask = Task { await refreshHistory(reset: true) } }
    }

    func resetSearch() {
        search = ""
        filter = nil
        resetHistoryRefinements(refresh: false)
        applySearchImmediately()
    }

    func resetHistoryRefinements(refresh: Bool = true) {
        timeFilter = .all
        sourceBundleFilter = nil
        favoritesOnly = false
        if refresh { applySearchImmediately() }
    }

    private var historyQuery: HistoryQuery {
        HistoryQuery(search: search, kind: filter,
                     copiedSince: timeFilter.startDate(now: now()),
                     sourceBundleID: sourceBundleFilter, favoritesOnly: favoritesOnly)
    }

    func purge() throws {
        guard let database else { return }
        if try database.purge(normalDays: normalDays == 0 ? nil : normalDays,
                              sensitiveSeconds: TimeInterval(sensitiveSeconds), now: now()) > 0 { refresh() }
    }

    private func purgeAsync() async {
        guard let historyStore else { return }
        do {
            if try await historyStore.purge(normalDays: normalDays == 0 ? nil : normalDays,
                                            sensitiveSeconds: TimeInterval(sensitiveSeconds), now: now()) > 0 {
                await refreshHistory(reset: true)
            }
            storageStatistics = try await historyStore.statistics()
        } catch { showStatus(error.localizedDescription) }
    }

    private func refreshHistory(reset: Bool) async {
        guard let historyStore else { return }
        if reset {
            historyGeneration += 1
            historyCursor = nil
            hasMoreHistory = false
        }
        let generation = historyGeneration
        let cursor = reset ? nil : historyCursor
        let query = historyQuery
        isLoadingHistory = true
        defer { if generation == historyGeneration { isLoadingHistory = false } }
        do {
            let page = try await historyStore.page(query, after: cursor, limit: historyPageSize)
            guard !Task.isCancelled, generation == historyGeneration,
                  query == historyQuery else { return }
            if reset {
                items = page.items
            } else {
                let existing = Set(items.map(\.id))
                items.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            }
            historyCursor = page.nextCursor
            hasMoreHistory = page.hasMore
            storageStatistics = try await historyStore.statistics()
        } catch is CancellationError {
            return
        } catch {
            showStatus(error.localizedDescription)
        }
    }

    func loadMoreHistory() {
        guard hasMoreHistory, !isLoadingHistory else { return }
        if let database {
            do {
                let page = try database.page(query: historyQuery,
                                             after: historyCursor, limit: historyPageSize)
                let existing = Set(items.map(\.id))
                items.append(contentsOf: page.items.filter { !existing.contains($0.id) })
                historyCursor = page.nextCursor
                hasMoreHistory = page.hasMore
            } catch { showStatus(error.localizedDescription) }
            return
        }
        searchTask = Task { await refreshHistory(reset: false) }
    }

    func payload(for id: UUID) -> ClipPayload? {
        do {
            // Recheck expiry at use time, not just at the periodic cleanup tick.
            try purge()
            return try database?.payload(for: id)
        }
        catch { showStatus(error.localizedDescription); return nil }
    }

    func loadPayload(for id: UUID) async -> ClipPayload? {
        if let database {
            do { return try database.payload(for: id) }
            catch { showStatus(error.localizedDescription); return nil }
        }
        guard let historyStore else { return nil }
        do {
            _ = try await historyStore.purge(normalDays: normalDays == 0 ? nil : normalDays,
                                             sensitiveSeconds: TimeInterval(sensitiveSeconds), now: now())
            return try await historyStore.payload(for: id)
        } catch {
            showStatus(error.localizedDescription)
            return nil
        }
    }

    func loadNote(for id: UUID) async -> String? {
        do {
            if let database { return try database.note(for: id) }
            return try await historyStore?.note(for: id)
        } catch {
            showStatus(error.localizedDescription)
            return nil
        }
    }

    @discardableResult
    func saveNote(_ value: String, for item: ClipSummary) async -> Bool {
        let note = ClipNote.normalized(value)
        do {
            if let database {
                try database.setNote(note, for: item.id)
                if storageLimitBytes > 0 { _ = try database.enforceQuota(bytes: storageLimitBytes) }
                refresh()
            } else if let historyStore {
                try await historyStore.setNote(note, for: item.id)
                if storageLimitBytes > 0 { _ = try await historyStore.enforceQuota(bytes: storageLimitBytes) }
                await refreshHistory(reset: true)
            } else {
                return false
            }
            guard self.item(for: item.id) != nil else {
                showStatus("The entry was removed because the storage limit was reached.")
                return false
            }
            showStatus(note == nil ? "Note removed." : "Encrypted note saved.")
            return true
        } catch {
            showStatus(error.localizedDescription)
            return false
        }
    }

    func copy(_ item: ClipSummary) {
        guard database != nil else {
            Task { await copyFromStore(item) }
            return
        }
        guard let payload = payload(for: item.id) else {
            showStatus("The entry is no longer available or has expired.")
            return
        }
        if payload.kind == .files,
           !(payload.filePaths ?? []).allSatisfy({ FileManager.default.fileExists(atPath: $0) }) {
            showStatus("One or more original files are missing.")
            return
        }
        let success = writeToPasteboard(payload, sensitive: item.isSensitive)
        guard success else { showStatus("Copy failed."); return }
        lastChangeCount = pasteboard.changeCount
        var updatedHistory = true
        do {
            try database?.capture(payload, sourceName: item.sourceName,
                                  sourceBundleID: item.sourceBundleID, sensitive: item.isSensitive, at: now())
            refresh()
        } catch {
            updatedHistory = false
            showStatus("Copied, but history could not be updated: \(error.localizedDescription)")
        }
        finishCopy(updatedHistory ? "Copied!" : "Copied, but history could not be updated.")
    }

    private func copyFromStore(_ item: ClipSummary) async {
        guard let historyStore, let payload = await loadPayload(for: item.id) else {
            showStatus("The entry is no longer available or has expired.")
            return
        }
        if payload.kind == .files,
           !(payload.filePaths ?? []).allSatisfy({ FileManager.default.fileExists(atPath: $0) }) {
            showStatus("One or more original files are missing.")
            return
        }
        guard writeToPasteboard(payload, sensitive: item.isSensitive) else {
            showStatus("Copy failed.")
            return
        }
        lastChangeCount = pasteboard.changeCount
        do {
            _ = try await historyStore.capture(
                payload, sourceName: item.sourceName, sourceBundleID: item.sourceBundleID,
                sensitive: item.isSensitive, at: now(), quotaBytes: storageLimitBytes == 0 ? nil : storageLimitBytes
            )
            await refreshHistory(reset: true)
            finishCopy("Copied!")
        } catch {
            finishCopy("Copied, but history could not be updated: \(error.localizedDescription)")
        }
    }

    /// Keeps the confirmation visible before the compact panel dismisses.
    private func finishCopy(_ message: String) {
        showStatus(message)
        copyConfirmationMessage = message
        let close = { [weak self] in
            guard let self else { return }
            self.copyConfirmationMessage = nil
            self.onClosePanel?()
            if self.autoPaste && self.systemIntegrationsEnabled { self.pasteIntoPreviousApp() }
        }
        if copyConfirmationDelay == 0 { close() }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + copyConfirmationDelay, execute: close) }
    }

    private func writeToPasteboard(_ payload: ClipPayload, sensitive: Bool) -> Bool {
        pasteboard.clearContents()
        let success: Bool
        switch payload.kind {
        case .text, .code, .url, .email:
            success = pasteboard.setString(payload.text ?? "", forType: .string)
        case .image:
            if let data = payload.imageData, let image = NSImage(data: data) {
                success = pasteboard.writeObjects([image])
            } else { success = false }
        case .files:
            success = pasteboard.writeObjects((payload.filePaths ?? []).map { NSURL(fileURLWithPath: $0) })
        }
        if success && sensitive {
            let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
            pasteboard.addTypes([concealed], owner: nil)
            pasteboard.setData(Data(), forType: concealed)
        }
        return success
    }

    private func pasteIntoPreviousApp() {
        guard AXIsProcessTrusted(), let previousApp else {
            showStatus("Accessibility permission is missing for automatic paste. The content was copied.",
                       recovery: .openAccessibilitySettings)
            return
        }
        previousApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    func openURL(_ item: ClipSummary) {
        guard database != nil else {
            Task {
                guard let text = await loadPayload(for: item.id)?.text,
                      let url = URL(string: text),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
                if systemIntegrationsEnabled { NSWorkspace.shared.open(url) }
                else { showStatus("Test mode: URL checked; browser not opened.") }
            }
            return
        }
        guard item.kind == .url, let text = payload(for: item.id)?.text,
              let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        if systemIntegrationsEnabled { NSWorkspace.shared.open(url) }
        else { showStatus("Test mode: URL checked; browser not opened.") }
    }

    func pin(_ item: ClipSummary) {
        guard database != nil else {
            Task {
                do {
                    try await historyStore?.setPinned(!item.isPinned, for: item.id)
                    if item.isPinned { try await historyStore?.setFavoriteName(nil, for: item.id) }
                    await refreshHistory(reset: true)
                } catch { showStatus(error.localizedDescription) }
            }
            return
        }
        mutate {
            try $0.setPinned(!item.isPinned, for: item.id)
            if item.isPinned { try $0.setFavoriteName(nil, for: item.id) }
        }
    }
    func nameFavorite(_ item: ClipSummary, _ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard database != nil else {
            Task {
                do {
                    try await historyStore?.setFavoriteName(trimmed.isEmpty ? nil : trimmed, for: item.id)
                    if !trimmed.isEmpty { try await historyStore?.setPinned(true, for: item.id) }
                    await refreshHistory(reset: true)
                    showStatus(trimmed.isEmpty ? "Favorite name removed." : "Favorite named and pinned.")
                } catch { showStatus(error.localizedDescription) }
            }
            return
        }
        guard mutate({
            try $0.setFavoriteName(trimmed.isEmpty ? nil : trimmed, for: item.id)
            if !trimmed.isEmpty { try $0.setPinned(true, for: item.id) }
        }) else { return }
        showStatus(trimmed.isEmpty ? "Favorite name removed." : "Favorite named and pinned.")
    }
    func excludeSourceApp(of item: ClipSummary) {
        guard let bundle = item.sourceBundleID else { return }
        setExcluded(bundle, excluded: true)
        showStatus("\(item.sourceName ?? bundle) will no longer be captured.")
    }
    func markSensitive(_ item: ClipSummary, _ sensitive: Bool) {
        guard database != nil else {
            Task {
                do {
                    try await historyStore?.setSensitive(sensitive, for: item.id)
                    await purgeAsync()
                    await refreshHistory(reset: true)
                } catch { showStatus(error.localizedDescription) }
            }
            return
        }
        mutate { try $0.setSensitive(sensitive, for: item.id) }
        try? purge()
    }
    func setRetentionOverride(_ seconds: Int?, for item: ClipSummary) {
        guard !item.isSensitive || seconds == nil || Retention.sensitivePresets.contains(seconds!) else {
            showStatus("Sensitive entries can be stored for no more than 24 hours.")
            return
        }
        guard database != nil else {
            Task {
                do {
                    try await historyStore?.setRetentionOverride(seconds: seconds, for: item.id)
                    await purgeAsync()
                    await refreshHistory(reset: true)
                    guard let current = self.item(for: item.id) else {
                        showStatus("The entry was deleted because the selected retention period had already expired.")
                        return
                    }
                    showRetentionStatus(current, seconds: seconds)
                } catch { showStatus(error.localizedDescription) }
            }
            return
        }
        guard mutate({ try $0.setRetentionOverride(seconds: seconds, for: item.id) }) else { return }
        try? purge()
        guard let current = self.item(for: item.id) else {
            showStatus("The entry was deleted because the selected retention period had already expired.")
            return
        }
        showRetentionStatus(current, seconds: seconds)
    }
    private func showRetentionStatus(_ item: ClipSummary, seconds: Int?) {
        if let deletionDate = item.deletionDate(normalDays: normalDays == 0 ? nil : normalDays,
                                                sensitiveSeconds: TimeInterval(sensitiveSeconds)) {
            showStatus("The entry will be deleted on \(deletionDate.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Locale(identifier: "en_US")))).")
        } else {
            showStatus(seconds == nil ? "The global retention setting is used." : "The entry will not be deleted automatically.")
        }
    }
    func delete(_ item: ClipSummary) {
        guard database != nil else {
            Task {
                do {
                    try await historyStore?.delete(item.id)
                    if previewedID == item.id { previewedID = nil }
                    await refreshHistory(reset: true)
                } catch { showStatus(error.localizedDescription) }
            }
            return
        }
        mutate { try $0.delete(item.id) }
    }
    func deleteAllHistory() {
        guard let database else {
            Task {
                guard let historyStore else { return }
                isCleaningHistory = true
                defer { isCleaningHistory = false }
                do {
                    let deleted = try await historyStore.deleteAll()
                    previewedID = nil
                    await refreshHistory(reset: true)
                    knownApps = try await historyStore.knownApps()
                    storageStatistics = try await historyStore.statistics()
                    showStatus(deleted == 0 ? "History is already empty." : "Deleted all history (\(deleted) entries).")
                } catch { showStatus(error.localizedDescription) }
            }
            return
        }
        do {
            let deleted = try database.deleteAll()
            refresh()
            showStatus(deleted == 0 ? "History is already empty." : "Deleted all history (\(deleted) entries).")
        } catch {
            showStatus(error.localizedDescription)
        }
    }
    func deleteUnpinnedHistory() {
        if let database {
            do {
                let deleted = try database.deleteUnpinned()
                refresh()
                knownApps = try database.knownApps()
                storageStatistics = try database.statistics()
                showStatus(deleted == 0 ? "There is no unpinned history to delete."
                                        : "Deleted \(deleted) unpinned entries. Favorites were kept.")
            } catch { showStatus(error.localizedDescription) }
            return
        }
        Task {
            guard let historyStore else { return }
            isCleaningHistory = true
            defer { isCleaningHistory = false }
            do {
                let deleted = try await historyStore.deleteUnpinned()
                previewedID = nil
                await refreshHistory(reset: true)
                knownApps = try await historyStore.knownApps()
                storageStatistics = try await historyStore.statistics()
                showStatus(deleted == 0 ? "There is no unpinned history to delete."
                                        : "Deleted \(deleted) unpinned entries. Favorites were kept.")
            } catch { showStatus(error.localizedDescription) }
        }
    }
    @discardableResult
    private func mutate(_ action: (ClipDatabase) throws -> Void) -> Bool {
        guard let database else { return false }
        do { try action(database); refresh(); return true }
        catch { showStatus(error.localizedDescription); return false }
    }

    func setShortcut(_ value: Shortcut?) {
        let result = hotkey.register(value) { [weak self] in self?.onOpenHistory?() }
        if result {
            shortcut = value
            defaults.set(try? JSONEncoder().encode(value), forKey: "shortcut")
            showStatus(value == nil ? "Keyboard shortcut disabled." : "Keyboard shortcut saved.")
        } else {
            showStatus("That keyboard shortcut is already in use. Choose another one.", recovery: .openSmartClipSettings)
        }
    }
    var onOpenHistory: (() -> Void)?

    func setMonitoring(_ enabled: Bool) {
        onboardingComplete = enabled
        defaults.set(enabled, forKey: "onboardingComplete")
        lastChangeCount = pasteboard.changeCount
    }
    func setPaused(_ value: Bool) {
        pauseTimer?.invalidate()
        pauseTimer = nil
        pauseMode = value ? .manual : .active
        defaults.set(value, forKey: "paused")
        if !value { lastChangeCount = pasteboard.changeCount }
    }
    func pause(for seconds: TimeInterval) {
        let end = now().addingTimeInterval(seconds)
        defaults.set(false, forKey: "paused")
        pauseMode = .until(end)
        schedulePauseTimer(seconds: seconds)
        showStatus("Capture paused until \(end.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "en_US")))).")
    }
    func pauseUntilRestart() {
        pauseTimer?.invalidate()
        pauseTimer = nil
        defaults.set(false, forKey: "paused")
        pauseMode = .untilRestart
        showStatus("Capture paused until the next launch.")
    }
    func updateTimedPause(at date: Date? = nil) {
        guard case .until(let end) = pauseMode, (date ?? now()) >= end else { return }
        setPaused(false)
        showStatus("Capture resumed automatically.")
    }
    private func schedulePauseTimer(seconds: TimeInterval) {
        pauseTimer?.invalidate()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: max(0.1, seconds), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.updateTimedPause(at: .distantFuture) }
        }
    }
    func setCardView(_ value: Bool) { cardView = value; defaults.set(value, forKey: "cardView") }
    func setDarkMode(_ value: Bool) { setAppearanceMode(value ? .midnight : .light) }
    func setAppearanceMode(_ mode: AppearanceMode) {
        appearanceMode = mode
        darkMode = mode != .light
        defaults.set(mode.rawValue, forKey: "appearanceMode")
        defaults.set(darkMode, forKey: "darkMode")
    }
    func setNormalDays(_ value: Int) {
        normalDays = value; defaults.set(value, forKey: "normalDays")
        if database != nil { try? purge(); refresh() }
        else { Task { await purgeAsync(); await refreshHistory(reset: true) } }
    }
    func setSensitiveSeconds(_ value: Int) {
        sensitiveSeconds = value; defaults.set(value, forKey: "sensitiveSeconds")
        if database != nil { try? purge(); refresh() }
        else { Task { await purgeAsync(); await refreshHistory(reset: true) } }
    }
    func setStoreSensitive(_ value: Bool) {
        storeSensitive = value
        defaults.set(value, forKey: "storeSensitive")
        showStatus(value ? "Sensitive entries will use the selected short retention period."
                         : "Sensitive clipboard content will no longer be stored.")
    }
    func setStorageLimitBytes(_ value: Int64) {
        storageLimitBytes = max(0, value)
        defaults.set(storageLimitBytes, forKey: "storageLimitBytes")
        if let database {
            do {
                if storageLimitBytes > 0 { _ = try database.enforceQuota(bytes: storageLimitBytes) }
                refresh()
            } catch { showStatus(error.localizedDescription) }
        } else {
            Task {
                guard let historyStore else { return }
                do {
                    if storageLimitBytes > 0 {
                        let result = try await historyStore.enforceQuota(bytes: storageLimitBytes)
                        if result.blockedByPinnedItems {
                            showStatus("Pinned entries exceed the selected limit. They were kept.")
                        } else if result.removedCount > 0 {
                            showStatus("Removed \(result.removedCount) old entries to meet the storage limit.")
                        }
                    }
                    await refreshHistory(reset: true)
                } catch { showStatus(error.localizedDescription) }
            }
        }
    }

    func select(_ id: UUID?) { selectedID = id }
    func togglePreview() {
        if previewedID != nil { previewedID = nil; return }
        let resolved = HistoryNavigation.selected(in: items.map(\.id), explicit: selectedID, search: search)
        previewedID = resolved
        if selectedID == nil { selectedID = resolved }
    }
    func closePreview() { previewedID = nil }
    func focusSearch() { focusSearchRequest &+= 1 }
    func moveSelection(_ offset: Int) {
        selectedID = HistoryNavigation.moved(in: items.map(\.id), explicit: selectedID,
                                             search: search, offset: offset)
    }
    var selectedItem: ClipSummary? {
        guard let id = HistoryNavigation.selected(in: items.map(\.id), explicit: selectedID, search: search) else {
            return nil
        }
        return item(for: id)
    }
    func setAutoPaste(_ value: Bool) {
        autoPaste = value; defaults.set(value, forKey: "autoPaste")
        if value && systemIntegrationsEnabled && !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }
    func setExcluded(_ bundle: String, excluded: Bool) {
        let trimmed = bundle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if excluded { excludedBundles.insert(trimmed) } else { excludedBundles.remove(trimmed) }
        defaults.set(Array(excludedBundles).sorted(), forKey: "excludedBundles")
    }
    func setAutoStart(_ enabled: Bool) {
        guard systemIntegrationsEnabled else { showStatus("Launch at login is disabled in test mode."); return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            showStatus(enabled ? "Launch at login enabled." : "Launch at login disabled.")
        } catch { showStatus("Autostart: \(error.localizedDescription)") }
    }
    var autoStartEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func checkPermissions() {
        if accessibilityPermissionGranted {
            showStatus("Permissions are ready. SmartClip can paste into the previous app.")
        } else {
            showStatus("Accessibility permission is needed for automatic paste.",
                       recovery: .openAccessibilitySettings)
        }
    }

    func showStatus(_ message: String, recovery: RecoveryAction? = nil) {
        statusMessage = message
        recoveryAction = recovery
    }

    func performRecovery() {
        guard let action = recoveryAction else { return }
        performRecoveryAction(action)
    }

    func performRecoveryAction(_ action: RecoveryAction) {
        switch action {
        case .retryStorage:
            Task { await start() }
        case .openClipboardSettings:
            openSystemSettings("Privacy_Pasteboard")
        case .openAccessibilitySettings:
            openSystemSettings("Privacy_Accessibility")
        case .openSmartClipSettings:
            onOpenSettings?()
        }
    }

    private func openSystemSettings(_ pane: String) {
        guard systemIntegrationsEnabled,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            showStatus("System Settings are disabled in test mode.")
            return
        }
        NSWorkspace.shared.open(url)
    }
}
