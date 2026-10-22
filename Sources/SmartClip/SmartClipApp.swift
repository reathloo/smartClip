import AppKit
import Combine
import SwiftUI

@main
@MainActor
enum SmartClipApp {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
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

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func applicationWillTerminate(_ notification: Notification) {
        #if DEBUG
        testSession?.cleanup()
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHistory()
        return true
    }

    private var statusItem: NSStatusItem?
    private var panel: HistoryPanel?
    private var settingsWindow: NSWindow?
    private var pauseObservation: AnyCancellable?

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
        item.button?.action = #selector(handleStatusItemClick)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        pauseObservation = model.$pauseMode.sink { [weak self] _ in self?.updateStatusItemAppearance() }
        if !model.onboardingComplete { showSettings() }
        #if DEBUG
        if testSession != nil { toggleHistory() }
        #endif
    }

    @objc private func handleStatusItemClick() {
        if NSApp.currentEvent?.type == .rightMouseUp { showStatusMenu() }
        else { toggleHistory() }
    }

    private func showStatusMenu() {
        guard let button = statusItem?.button else { return }
        let menu = makeStatusMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        if model.isPaused {
            menu.addItem(withTitle: "Resume capture", action: #selector(resumeCapture), keyEquivalent: "")
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Pause for 15 minutes", action: #selector(pauseFor15Minutes), keyEquivalent: "")
        menu.addItem(withTitle: "Pause until next launch", action: #selector(pauseUntilNextLaunch), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings …", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        menu.addItem(withTitle: "Quit SmartClip", action: #selector(quitFromMenu), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        return menu
    }

    private func updateStatusItemAppearance() {
        let symbol = model.isPaused ? "pause.circle" : "paperclip.circle"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: model.captureStatusLabel)
        statusItem?.button?.toolTip = "SmartClip · \(model.captureStatusLabel)"
    }

    @objc private func resumeCapture() { model.setPaused(false) }
    @objc private func pauseFor15Minutes() { model.pause(for: 15 * 60) }
    @objc private func pauseUntilNextLaunch() { model.pauseUntilRestart() }
    @objc private func openSettingsFromMenu() { showSettings() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    private func toggleHistory() {
        if let panel, panel.isVisible && !panel.isMiniaturized { panel.orderOut(nil); return }
        showHistory()
    }

    private func showHistory() {
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
            window.title = "SmartClip Settings"
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
