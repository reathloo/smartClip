#if DEBUG
import AppKit
import CryptoKit

/// An opt-in development app with synthetic data and disposable storage.
/// No Keychain access, clipboard monitoring, login registration or synthetic paste.
@MainActor
final class UITestSession {
    let model: AppModel
    private let directory: URL
    private let defaults: UserDefaults
    private let suite: String
    private let pasteboard: NSPasteboard

    init() throws {
        suite = "dev.smartclip.uitest.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        pasteboard = NSPasteboard.withUniqueName()
        let db = try ClipDatabase(path: directory.appendingPathComponent("history.sqlite").path,
                                  crypto: CryptoStore(key: SymmetricKey(size: .bits256)))
        model = AppModel(defaults: defaults, pasteboard: pasteboard, database: db, systemIntegrationsEnabled: false)
        let samples: [(String, Bool, String)] = [
            ("https://example.org", false, "Safari"),
            ("SmartClip Testnotiz", false, "Notizen"),
            ("def greet(name):\n    return name", false, "Visual Studio Code"),
            ("hallo@example.org", false, "Mail"),
            ("synthetic-secret-42", true, "Test-Passwortmanager")
        ]
        for (index, sample) in samples.enumerated() {
            try db.capture(.text(sample.0), sourceName: sample.2, sourceBundleID: nil,
                           sensitive: sample.1, at: .now.addingTimeInterval(-Double(index * 10)))
        }
        let first = try db.list()[0]
        try db.setPinned(true, for: first.id)
        try db.capture(.files([directory.appendingPathComponent("missing-file.txt").path]),
                       sourceName: "Finder", sourceBundleID: nil, sensitive: false)
        model.setMonitoring(true)
        model.refresh()
        model.statusMessage = "Testmodus: Beispieldaten und separate Zwischenablage."
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }
}
#endif
