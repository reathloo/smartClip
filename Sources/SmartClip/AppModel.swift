import AppKit
import ApplicationServices
import Carbon
import Combine
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var items: [ClipSummary] = [] {
        didSet { itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest }) }
    }
    private var itemsByID: [UUID: ClipSummary] = [:]
    @Published var search = ""
    @Published var filter: ClipKind?
    @Published var cardView: Bool
    @Published var statusMessage = ""
    @Published private(set) var recoveryAction: RecoveryAction?
    @Published private(set) var pauseMode: PauseMode
    @Published var shortcut: Shortcut?
    @Published var normalDays: Int
    @Published var sensitiveSeconds: Int
    @Published var autoPaste: Bool
    @Published var excludedBundles: Set<String>
    @Published var knownApps: [(String, String)] = []
    @Published var onboardingComplete: Bool
    @Published private(set) var storageReady = false
    @Published private(set) var clipboardAccessDenied = false

    var isPaused: Bool { pauseMode.isPaused }
    var captureStatusLabel: String { isPaused ? pauseMode.label(now: now()) : captureState.label }

    var captureState: CaptureState {
        if !storageReady { return .unavailable }
        if !onboardingComplete { return .setup }
        if isPaused { return .paused }
        return clipboardAccessDenied ? .denied : .active
    }

    func item(for id: UUID) -> ClipSummary? { itemsByID[id] }

    private var database: ClipDatabase?
    private var pollTimer: Timer?
    private var purgeTimer: Timer?
    private var pauseTimer: Timer?
    private var searchTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private let now: () -> Date
    private let systemIntegrationsEnabled: Bool
    private var lastChangeCount: Int
    var previousApp: NSRunningApplication?
    var onClosePanel: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    let hotkey = HotkeyManager()

    init(defaults: UserDefaults = .standard, pasteboard: NSPasteboard = .general,
         database: ClipDatabase? = nil, now: @escaping () -> Date = { .now },
         systemIntegrationsEnabled: Bool = true) {
        self.defaults = defaults
        self.pasteboard = pasteboard
        self.database = database
        self.storageReady = database != nil
        self.now = now
        self.systemIntegrationsEnabled = systemIntegrationsEnabled
        self.lastChangeCount = pasteboard.changeCount
        cardView = defaults.bool(forKey: "cardView")
        pauseMode = defaults.bool(forKey: "paused") ? .manual : .active
        recoveryAction = nil
        normalDays = defaults.object(forKey: "normalDays") as? Int ?? 30
        sensitiveSeconds = defaults.object(forKey: "sensitiveSeconds") as? Int ?? 3_600
        autoPaste = defaults.bool(forKey: "autoPaste")
        excludedBundles = Set(defaults.stringArray(forKey: "excludedBundles") ?? [])
        onboardingComplete = defaults.bool(forKey: "onboardingComplete")
        if let data = defaults.data(forKey: "shortcut") {
            shortcut = try? JSONDecoder().decode(Shortcut.self, from: data)
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
        showStatus("Geschützten Verlauf öffnen … gegebenenfalls Schlüsselbund-Freigabe bestätigen.")
        do {
            let crypto = try await Task.detached(priority: .userInitiated) { try keyLoader() }.value
            let url: URL
            if let databaseURL { url = databaseURL }
            else {
                let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                url = support.appendingPathComponent("SmartClip/history.sqlite")
            }
            database = try ClipDatabase(path: url.path, crypto: crypto)
            try purge()
            refresh()
            knownApps = try database?.knownApps() ?? []
            storageReady = true
            showStatus("Verlauf bereit.")
        } catch {
            database = nil
            storageReady = false
            showStatus("Verlauf konnte nicht geöffnet werden: \(error.localizedDescription)", recovery: .retryStorage)
            return
        }
        pollTimer?.invalidate()
        purgeTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        purgeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in try? self?.purge() }
        }
    }

    isolated deinit {
        pollTimer?.invalidate()
        purgeTimer?.invalidate()
        pauseTimer?.invalidate()
        searchTask?.cancel()
    }

    private func poll() {
        updateTimedPause()
        guard onboardingComplete, !isPaused, database != nil else { return }
        let denied: Bool
        if #available(macOS 26, *) { denied = pasteboard.accessBehavior == .alwaysDeny }
        else { denied = false }
        // Still notice permission changes without a new copy; resolve the app only for new content.
        guard pasteboard.changeCount != lastChangeCount || denied != clipboardAccessDenied else { return }
        let app = pasteboard.changeCount != lastChangeCount ? NSWorkspace.shared.frontmostApplication : nil
        processChanges(sourceName: app?.localizedName, sourceBundleID: app?.bundleIdentifier, accessDenied: denied)
    }

    /// Shared capture path; tests provide an isolated pasteboard and an explicit source.
    func processChanges(sourceName: String?, sourceBundleID: String?, accessDenied: Bool = false) {
        guard onboardingComplete, !isPaused, let database else { return }
        if clipboardAccessDenied != accessDenied {
            clipboardAccessDenied = accessDenied
            showStatus(accessDenied ? "Zwischenablage-Zugriff ist in den Systemeinstellungen gesperrt."
                : "Zwischenablage-Zugriff wieder verfügbar.",
                       recovery: accessDenied ? .openClipboardSettings : nil)
        }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if accessDenied {
            showStatus("Zwischenablage-Zugriff ist in den Systemeinstellungen gesperrt.", recovery: .openClipboardSettings)
            return
        }
        if let sourceBundleID, excludedBundles.contains(sourceBundleID) { return }
        let captured: (payload: ClipPayload, sensitive: Bool)
        switch ClipboardReader.read(pasteboard) {
        case .captured(let payload, let sensitive): captured = (payload, sensitive)
        case .skipped(let reason):
            if let reason { showStatus(reason) }
            return
        }
        do {
            try database.capture(captured.payload, sourceName: sourceName,
                                 sourceBundleID: sourceBundleID, sensitive: captured.sensitive, at: now())
            try purge()
            refresh()
            knownApps = try database.knownApps()
        } catch {
            showStatus(error.localizedDescription)
        }
    }

    func refresh() {
        do { items = try database?.list(search: search, kind: filter) ?? [] }
        catch { showStatus(error.localizedDescription) }
    }

    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    func applySearchImmediately() {
        searchTask?.cancel()
        searchTask = nil
        refresh()
    }

    func resetSearch() {
        search = ""
        filter = nil
        applySearchImmediately()
    }

    func purge() throws {
        guard let database else { return }
        if try database.purge(normalDays: normalDays == 0 ? nil : normalDays,
                              sensitiveSeconds: TimeInterval(sensitiveSeconds), now: now()) > 0 { refresh() }
    }

    func payload(for id: UUID) -> ClipPayload? {
        do {
            // Recheck expiry at use time, not just at the periodic cleanup tick.
            try purge()
            return try database?.payload(for: id)
        }
        catch { showStatus(error.localizedDescription); return nil }
    }

    func copy(_ item: ClipSummary) {
        guard let payload = payload(for: item.id) else {
            showStatus("Eintrag ist nicht mehr verfügbar oder bereits abgelaufen.")
            return
        }
        if payload.kind == .files,
           !(payload.filePaths ?? []).allSatisfy({ FileManager.default.fileExists(atPath: $0) }) {
            showStatus("Eine oder mehrere Originaldateien fehlen.")
            return
        }
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
            let paths = payload.filePaths ?? []
            success = pasteboard.writeObjects(paths.map { NSURL(fileURLWithPath: $0) })
        }
        guard success else { showStatus("Kopieren fehlgeschlagen."); return }
        if item.isSensitive {
            let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
            pasteboard.addTypes([concealed], owner: nil)
            pasteboard.setData(Data(), forType: concealed)
        }
        lastChangeCount = pasteboard.changeCount
        var updatedHistory = true
        do {
            try database?.capture(payload, sourceName: item.sourceName,
                                  sourceBundleID: item.sourceBundleID, sensitive: item.isSensitive, at: now())
            refresh()
        } catch {
            updatedHistory = false
            showStatus("Kopiert, aber Verlauf konnte nicht aktualisiert werden: \(error.localizedDescription)")
        }
        onClosePanel?()
        if updatedHistory { showStatus("In die Zwischenablage kopiert.") }
        if autoPaste && systemIntegrationsEnabled { pasteIntoPreviousApp() }
    }

    private func pasteIntoPreviousApp() {
        guard AXIsProcessTrusted(), let previousApp else {
            showStatus("Für automatisches Einfügen fehlt die Bedienungshilfen-Freigabe. Inhalt wurde kopiert.",
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
        guard item.kind == .url, let text = payload(for: item.id)?.text,
              let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        if systemIntegrationsEnabled { NSWorkspace.shared.open(url) }
        else { showStatus("Testmodus: URL geprüft, Browser nicht geöffnet.") }
    }

    func pin(_ item: ClipSummary) {
        mutate {
            try $0.setPinned(!item.isPinned, for: item.id)
            if item.isPinned { try $0.setFavoriteName(nil, for: item.id) }
        }
    }
    func nameFavorite(_ item: ClipSummary, _ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mutate({
            try $0.setFavoriteName(trimmed.isEmpty ? nil : trimmed, for: item.id)
            if !trimmed.isEmpty { try $0.setPinned(true, for: item.id) }
        }) else { return }
        showStatus(trimmed.isEmpty ? "Favoritenname entfernt." : "Favorit benannt und angeheftet.")
    }
    func excludeSourceApp(of item: ClipSummary) {
        guard let bundle = item.sourceBundleID else { return }
        setExcluded(bundle, excluded: true)
        showStatus("\(item.sourceName ?? bundle) wird künftig nicht mehr erfasst.")
    }
    func markSensitive(_ item: ClipSummary, _ sensitive: Bool) {
        mutate { try $0.setSensitive(sensitive, for: item.id) }
        try? purge()
    }
    func delete(_ item: ClipSummary) { mutate { try $0.delete(item.id) } }
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
            showStatus(value == nil ? "Tastenkürzel deaktiviert." : "Tastenkürzel gespeichert.")
        } else {
            showStatus("Tastenkürzel ist bereits belegt. Bitte ein anderes wählen.", recovery: .openSmartClipSettings)
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
        showStatus("Aufzeichnung bis \(end.formatted(date: .omitted, time: .shortened)) pausiert.")
    }
    func pauseUntilRestart() {
        pauseTimer?.invalidate()
        pauseTimer = nil
        defaults.set(false, forKey: "paused")
        pauseMode = .untilRestart
        showStatus("Aufzeichnung bis zum nächsten Start pausiert.")
    }
    func updateTimedPause(at date: Date? = nil) {
        guard case .until(let end) = pauseMode, (date ?? now()) >= end else { return }
        setPaused(false)
        showStatus("Aufzeichnung automatisch fortgesetzt.")
    }
    private func schedulePauseTimer(seconds: TimeInterval) {
        pauseTimer?.invalidate()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: max(0.1, seconds), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.updateTimedPause(at: .distantFuture) }
        }
    }
    func setCardView(_ value: Bool) { cardView = value; defaults.set(value, forKey: "cardView") }
    func setNormalDays(_ value: Int) {
        normalDays = value; defaults.set(value, forKey: "normalDays")
        try? purge(); refresh()
    }
    func setSensitiveSeconds(_ value: Int) {
        sensitiveSeconds = value; defaults.set(value, forKey: "sensitiveSeconds")
        try? purge(); refresh()
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
        guard systemIntegrationsEnabled else { showStatus("Autostart im Testmodus deaktiviert."); return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            showStatus(enabled ? "Autostart aktiviert." : "Autostart deaktiviert.")
        } catch { showStatus("Autostart: \(error.localizedDescription)") }
    }
    var autoStartEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func showStatus(_ message: String, recovery: RecoveryAction? = nil) {
        statusMessage = message
        recoveryAction = recovery
    }

    func performRecovery() {
        guard let action = recoveryAction else { return }
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
            showStatus("Systemeinstellungen sind im Testmodus deaktiviert.")
            return
        }
        NSWorkspace.shared.open(url)
    }
}
