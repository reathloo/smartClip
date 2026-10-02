import AppKit
import SwiftUI

@main
struct SmartClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { SettingsView(model: delegate.model) } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    fileprivate let model: AppModel
    #if DEBUG
    private var testSession: UITestSession?
    #endif

    override init() {
        #if DEBUG
        if Bundle.main.object(forInfoDictionaryKey: "SmartClipUITest") as? Bool == true {
            do {
                let session = try UITestSession()
                testSession = session
                model = session.model
            } catch { fatalError("UI test fixtures failed: \(error)") }
        } else { model = .shared }
        #else
        model = .shared
        #endif
        super.init()
    }

    func applicationWillTerminate(_ notification: Notification) {
        #if DEBUG
        testSession?.cleanup()
        #endif
    }
    private var statusItem: NSStatusItem?
    private var panel: HistoryPanel?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if CommandLine.arguments.contains("--render-design") {
            Task { @MainActor in
                do { try await renderDesignPreviews(); exit(0) }
                catch { print("Design preview failed: \(error)"); exit(1) }
            }
            return
        }
        if CommandLine.arguments.contains("--self-test") {
            Task { @MainActor in
                do { try await runCoreChecks(); print("SmartClip core checks passed"); exit(0) }
                catch { fputs("SmartClip core checks failed: \(error)\n", stderr); exit(1) }
            }
            return
        }
        #endif
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if testSession == nil { Task { await model.start() } }
        #else
        Task { await model.start() }
        #endif
        model.onOpenHistory = { [weak self] in self?.toggleHistory() }
        model.onClosePanel = { [weak self] in self?.panel?.orderOut(nil) }
        model.onOpenSettings = { [weak self] in self?.showSettings() }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "paperclip.circle", accessibilityDescription: "SmartClip")
        item.button?.target = self
        item.button?.action = #selector(toggleHistoryFromMenuBar)
        statusItem = item
        if !model.onboardingComplete { showSettings() }
        #if DEBUG
        if testSession != nil { toggleHistory() }
        #endif
    }

    @objc private func toggleHistoryFromMenuBar() { toggleHistory() }

    private func toggleHistory() {
        if let panel, panel.isVisible && !panel.isMiniaturized { panel.orderOut(nil); return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            model.previousApp = frontmost
        }
        if panel == nil {
            let panel = HistoryPanel()
            panel.contentView = NSHostingView(rootView: HistoryView(model: model))
            panel.center()
            self.panel = panel
        }
        guard let panel else { return }
        // Recover a window left on a display that has since been disconnected.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        panel.makeKeyAndOrderFront(nil)
    }

    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 660),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "SmartClip Einstellungen"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 700, height: 600)
            window.titlebarAppearsTransparent = true
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

final class HistoryPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 680),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "SmartClip"
        titlebarSeparatorStyle = .none
        isReleasedWhenClosed = false
        isMovable = true
        contentMinSize = NSSize(width: 560, height: 540)
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = true
        hasShadow = true
        collectionBehavior = [.fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    override func sendEvent(_ event: NSEvent) {
        // Handle dismissal before the search field's editor consumes Escape.
        if event.type == .keyDown {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            if (event.keyCode == 53 && modifiers.isEmpty)
                || (event.charactersIgnoringModifiers == "w" && modifiers == .command) {
                orderOut(nil)
                return
            }
        }
        super.sendEvent(event)
    }
}
