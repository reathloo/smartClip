#if DEBUG
import AppKit
import SwiftUI

/// Renders the actual views with synthetic content, without starting clipboard capture.
@MainActor
func renderDesignPreviews() async throws {
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/design-previews")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let model = AppModel.designPreview()
    let samples: [(ClipKind, String, String, String, Bool, Bool)] = [
        (.url, "https://developer.apple.com/design/", "Safari", "com.apple.Safari", true, false),
        (.code, "def greet(name):\n    return f\"Hello {name}\"", "Visual Studio Code", "com.microsoft.VSCode", true, false),
        (.text, "The best tools make the next step a little easier.", "Notes", "com.apple.Notes", false, false),
        (.email, "hello@example.com", "Mail", "com.apple.mail", false, false),
        (.files, "Project-draft.pdf, Notes.md", "Finder", "com.apple.finder", false, false),
        (.text, "••••••••", "Safari", "com.apple.Safari", false, true)
    ]
    model.items = samples.enumerated().map { index, item in
        ClipSummary(id: UUID(), kind: item.0, lastCopiedAt: .now.addingTimeInterval(index == 2 ? -172_800 : -Double(120 + index * 90)),
                    sourceName: item.2, sourceBundleID: item.3, isSensitive: item.5,
                    isPinned: item.4, copyCount: index == 0 ? 3 : 1, preview: item.1, hasMissingFiles: false,
                    codeLanguage: item.0 == .code ? "Python" : nil,
                    retentionOverrideSeconds: index == 2 ? 30 * 86_400 : nil)
    }
    if !model.items.isEmpty {
        let first = model.items[0]
        model.items[0] = ClipSummary(id: first.id, kind: first.kind, lastCopiedAt: first.lastCopiedAt,
                                     sourceName: first.sourceName, sourceBundleID: first.sourceBundleID,
                                     isSensitive: first.isSensitive, isPinned: true, copyCount: first.copyCount,
                                     preview: first.preview, hasMissingFiles: first.hasMissingFiles,
                                     codeLanguage: first.codeLanguage, favoriteName: "Apple Design")
    }
    for dark in [false, true] {
        let scheme: ColorScheme = dark ? .dark : .light
        let suffix = dark ? "dark" : "light"
        model.darkMode = dark
        model.cardView = false
        try await snapshot(HistoryView(model: model), size: NSSize(width: 600, height: 680),
                           scheme: scheme, to: output.appendingPathComponent("history-\(suffix).png"))
        if !dark {
            model.cardView = true
            try await snapshot(HistoryView(model: model), size: NSSize(width: 600, height: 680),
                               scheme: scheme, to: output.appendingPathComponent("cards-light.png"))
            model.cardView = false
        }
        try await snapshot(SettingsView(model: model), size: NSSize(width: 760, height: 660),
                           scheme: scheme, to: output.appendingPathComponent("settings-\(suffix).png"))
    }
    model.darkMode = false
    try await snapshot(SettingsView(model: model, initialTab: .history), size: NSSize(width: 760, height: 660),
                       scheme: .light, to: output.appendingPathComponent("retention-light.png"))
    try await snapshot(SettingsView(model: model, initialTab: .privacy), size: NSSize(width: 760, height: 660),
                       scheme: .light, to: output.appendingPathComponent("privacy-light.png"))
    try await snapshot(SettingsView(model: model, initialTab: .about), size: NSSize(width: 760, height: 660),
                       scheme: .light, to: output.appendingPathComponent("about-light.png"))
    try await snapshot(HistoryView(model: model), size: NSSize(width: 560, height: 540),
                       scheme: .light, to: output.appendingPathComponent("history-compact.png"))
    model.onboardingComplete = false
    model.shortcut = nil
    try await snapshot(SettingsView(model: model), size: NSSize(width: 700, height: 580),
                       scheme: .light, to: output.appendingPathComponent("onboarding-compact.png"))
    model.onboardingComplete = true
    model.items = []
    try await snapshot(HistoryView(model: model), size: NSSize(width: 600, height: 680),
                       scheme: .light, to: output.appendingPathComponent("empty-light.png"))
    model.search = "no result"
    try await snapshot(HistoryView(model: model), size: NSSize(width: 560, height: 540),
                       scheme: .light, to: output.appendingPathComponent("search-empty-compact.png"))
    model.search = ""
    model.pauseUntilRestart()
    try await snapshot(HistoryView(model: model), size: NSSize(width: 560, height: 540),
                       scheme: .dark, to: output.appendingPathComponent("paused-dark-compact.png"))
    print("Design previews: \(output.path)")
}

@MainActor
private func snapshot<V: View>(_ view: V, size: NSSize, scheme: ColorScheme, to url: URL) async throws {
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "en_US")))
    host.frame = NSRect(origin: .zero, size: size)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(200))
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        throw CocoaError(.fileWriteUnknown)
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
    window.close()
}
#endif
