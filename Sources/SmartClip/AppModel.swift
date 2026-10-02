import AppKit
import ApplicationServices
import Carbon
import Combine
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var items: [ClipSummary] = []
    @Published var search = ""
    @Published var filter: ClipKind?
    @Published var cardView: Bool
    @Published var statusMessage = ""
    @Published var isPaused: Bool
    @Published var shortcut: Shortcut?
    @Published var normalDays: Int
    @Published var sensitiveSeconds: Int
    @Published var autoPaste: Bool
    @Published var excludedBundles: Set<String>
    @Published var knownApps: [(String, String)] = []
    @Published var onboardingComplete: Bool
    @Published private(set) var storageReady = false

    private var database: ClipDatabase?
    private var pollTimer: Timer?
    private var purgeTimer: Timer?
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
        isPaused = defaults.bool(forKey: "paused")
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
        model.isPaused = false
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
        statusMessage = "Geschützten Verlauf öffnen … gegebenenfalls Schlüsselbund-Freigabe bestätigen."
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
            statusMessage = "Verlauf bereit."
        } catch {
            database = nil
            storageReady = false
            statusMessage = "Verlauf konnte nicht geöffnet werden: \(error.localizedDescription)"
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
        searchTask?.cancel()
    }

    private func poll() {
        let app = NSWorkspace.shared.frontmostApplication
        let denied: Bool
        if #available(macOS 26, *) { denied = pasteboard.accessBehavior == .alwaysDeny }
        else { denied = false }
        processChanges(sourceName: app?.localizedName, sourceBundleID: app?.bundleIdentifier, accessDenied: denied)
    }

    /// Shared capture path; tests provide an isolated pasteboard and an explicit source.
    func processChanges(sourceName: String?, sourceBundleID: String?, accessDenied: Bool = false) {
        guard onboardingComplete, !isPaused, let database else { return }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if accessDenied {
            statusMessage = "Zwischenablage-Zugriff ist in den Systemeinstellungen gesperrt."
            return
        }
        if let sourceBundleID, excludedBundles.contains(sourceBundleID) { return }
        let captured: (payload: ClipPayload, sensitive: Bool)
        switch ClipboardReader.read(pasteboard) {
        case .captured(let payload, let sensitive): captured = (payload, sensitive)
        case .skipped(let reason):
            if let reason { statusMessage = reason }
            return
        }
        do {
            try database.capture(captured.payload, sourceName: sourceName,
                                 sourceBundleID: sourceBundleID, sensitive: captured.sensitive, at: now())
            try purge()
            refresh()
            knownApps = try database.knownApps()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refresh() {
        do { items = try database?.list(search: search, kind: filter) ?? [] }
        catch { statusMessage = error.localizedDescription }
    }

    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            refresh()
        }
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
        catch { statusMessage = error.localizedDescription; return nil }
    }

    func copy(_ item: ClipSummary) {
        guard let payload = payload(for: item.id) else {
            statusMessage = "Eintrag ist nicht mehr verfügbar oder bereits abgelaufen."
            return
        }
        if payload.kind == .files,
           !(payload.filePaths ?? []).allSatisfy({ FileManager.default.fileExists(atPath: $0) }) {
            statusMessage = "Eine oder mehrere Originaldateien fehlen."
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
        guard success else { statusMessage = "Kopieren fehlgeschlagen."; return }
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
            statusMessage = "Kopiert, aber Verlauf konnte nicht aktualisiert werden: \(error.localizedDescription)"
        }
        onClosePanel?()
        if updatedHistory { statusMessage = "In die Zwischenablage kopiert." }
        if autoPaste && systemIntegrationsEnabled { pasteIntoPreviousApp() }
    }

    private func pasteIntoPreviousApp() {
        guard AXIsProcessTrusted(), let previousApp else {
            statusMessage = "Für automatisches Einfügen fehlt die Bedienungshilfen-Freigabe. Inhalt wurde kopiert."
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
        else { statusMessage = "Testmodus: URL geprüft, Browser nicht geöffnet." }
    }

    func pin(_ item: ClipSummary) { mutate { try $0.setPinned(!item.isPinned, for: item.id) } }
    func markSensitive(_ item: ClipSummary, _ sensitive: Bool) {
        mutate { try $0.setSensitive(sensitive, for: item.id) }
        try? purge()
    }
    func delete(_ item: ClipSummary) { mutate { try $0.delete(item.id) } }
    private func mutate(_ action: (ClipDatabase) throws -> Void) {
        guard let database else { return }
        do { try action(database); refresh() }
        catch { statusMessage = error.localizedDescription }
    }

    func setShortcut(_ value: Shortcut?) {
        let result = hotkey.register(value) { [weak self] in self?.onOpenHistory?() }
        if result {
            shortcut = value
            defaults.set(try? JSONEncoder().encode(value), forKey: "shortcut")
            statusMessage = value == nil ? "Tastenkürzel deaktiviert." : "Tastenkürzel gespeichert."
        } else {
            statusMessage = "Tastenkürzel ist bereits belegt. Bitte ein anderes wählen."
        }
    }
    var onOpenHistory: (() -> Void)?

    func setMonitoring(_ enabled: Bool) {
        onboardingComplete = enabled
        defaults.set(enabled, forKey: "onboardingComplete")
        lastChangeCount = pasteboard.changeCount
    }
    func setPaused(_ value: Bool) {
        isPaused = value
        defaults.set(value, forKey: "paused")
        if !value { lastChangeCount = pasteboard.changeCount }
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
        guard systemIntegrationsEnabled else { statusMessage = "Autostart im Testmodus deaktiviert."; return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            statusMessage = enabled ? "Autostart aktiviert." : "Autostart deaktiviert."
        } catch { statusMessage = "Autostart: \(error.localizedDescription)" }
    }
    var autoStartEnabled: Bool { SMAppService.mainApp.status == .enabled }
}
