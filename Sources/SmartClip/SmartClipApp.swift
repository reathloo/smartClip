import AppKit
import Combine
import Sparkle
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
    private var pauseObservation: AnyCancellable?
    private var updaterController: SPUStandardUpdaterController?

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
        #if DEBUG
        let shouldStartUpdater = testSession == nil
        #else
        let shouldStartUpdater = true
        #endif
        if shouldStartUpdater {
            let updater = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            updaterController = updater
            model.onCheckForUpdates = { [weak updater] in updater?.checkForUpdates(nil) }
        }
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
        menu.addItem(withTitle: "Check for Updates …", action: #selector(checkForUpdates), keyEquivalent: "")
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
    @objc private func checkForUpdates() { updaterController?.checkForUpdates(nil) }
    @objc private func openSettingsFromMenu() { showSettings() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    private func toggleHistory() {
        if let panel, panel.isVisible && !panel.isMiniaturized {
            if model.showingSettings { showHistory() }
            else { panel.orderOut(nil) }
            return
        }
        showHistory()
    }

    private func showHistory() {
        model.showingSettings = false
        showPanel()
    }

    private func showSettings() {
        model.showingSettings = true
        showPanel()
    }

    private func showPanel() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            model.previousApp = frontmost
        }
        if panel == nil {
            let panel = HistoryPanel()
            panel.contentView = NSHostingView(rootView: SmartClipWindowContent(model: model))
            panel.commandHandler = { [weak self] event in self?.handlePanelCommand(event) ?? false }
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

    private func handlePanelCommand(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let character = event.charactersIgnoringModifiers?.lowercased()
        if character == "w", modifiers == .command { panel?.orderOut(nil); return true }
        if character == "f", modifiers == .command, !model.showingSettings {
            model.focusSearch(); return true
        }
        guard !model.showingSettings else { return false }
        if event.keyCode == 53, modifiers.isEmpty {
            if model.previewedID != nil { model.closePreview() }
            else if !model.search.isEmpty || model.filter != nil { model.resetSearch() }
            else { panel?.orderOut(nil) }
            return true
        }
        let isEditingText = panel?.firstResponder is NSTextView
        guard !isEditingText else { return false }
        if event.keyCode == 49, modifiers.isEmpty { model.togglePreview(); return true }
        if character == "c", modifiers == .command, let item = model.selectedItem {
            model.copy(item); return true
        }
        if character == "o", modifiers == .command, let item = model.selectedItem, item.kind == .url {
            model.openURL(item); return true
        }
        if character == "p", modifiers == .command, let item = model.selectedItem {
            model.pin(item); return true
        }
        if (event.keyCode == 51 || event.keyCode == 117), modifiers.isEmpty, let item = model.selectedItem {
            model.pendingDeleteID = item.id; return true
        }
        if event.keyCode == 125, modifiers.isEmpty { model.moveSelection(1); return true }
        if event.keyCode == 126, modifiers.isEmpty { model.moveSelection(-1); return true }
        if event.keyCode == 36, modifiers.isEmpty, let item = model.selectedItem {
            model.copy(item); return true
        }
        return false
    }
}

private struct SmartClipWindowContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.showingSettings { SettingsView(model: model) }
        else { HistoryView(model: model) }
    }
}

final class HistoryPanel: NSPanel {
    var commandHandler: ((NSEvent) -> Bool)?
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "SmartClip"
        titlebarSeparatorStyle = .none
        isReleasedWhenClosed = false
        isMovable = true
        contentMinSize = NSSize(width: 700, height: 580)
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = true
        hasShadow = true
        collectionBehavior = [.fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) {
        if commandHandler?(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                            timestamp: 0, windowNumber: windowNumber, context: nil,
                                            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                            isARepeat: false, keyCode: 53)!) == true { return }
        orderOut(nil)
    }

    override func sendEvent(_ event: NSEvent) {
        // Handle dismissal before the search field's editor consumes Escape.
        if event.type == .keyDown {
            if commandHandler?(event) == true { return }
        }
        super.sendEvent(event)
    }
}
