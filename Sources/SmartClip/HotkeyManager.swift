import AppKit
import Carbon

struct Shortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let display: String

    static let suggested = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey), display: "⌘⇧V")
}

@MainActor
final class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?
    private var current: Shortcut?
    private var nextID: UInt32 = 1

    isolated deinit {
        if let hotkeyRef { UnregisterEventHotKey(hotkeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    func register(_ shortcut: Shortcut?, action: @escaping () -> Void) -> Bool {
        if shortcut == current {
            self.action = shortcut == nil ? nil : action
            return true
        }
        guard let shortcut else {
            if let hotkeyRef { UnregisterEventHotKey(hotkeyRef); self.hotkeyRef = nil }
            current = nil
            self.action = nil
            return true
        }
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), smartClipHotkeyHandler, 1, &spec,
                                             Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
            guard status == noErr else { return false }
        }
        let id = EventHotKeyID(signature: 0x53434C50, id: nextID)
        nextID &+= 1
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                        GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr else { return false }
        if let hotkeyRef { UnregisterEventHotKey(hotkeyRef) }
        hotkeyRef = replacement
        current = shortcut
        self.action = action
        return true
    }

    func fire() { action?() }
}

private func smartClipHotkeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { manager.fire() }
    return noErr
}

final class ShortcutRecorderView: NSView {
    var onShortcut: ((Shortcut) -> Void)?
    private var recording = false
    private let label = NSTextField(labelWithString: "Eigenes Kürzel aufnehmen")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10)
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel("Eigenes Tastenkürzel aufnehmen")
    }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.borderColor = recording ? NSColor(srgbRed: 0.2, green: 0.55, blue: 0.48, alpha: 1).cgColor
            : NSColor(white: dark ? 0.28 : 0.85, alpha: 1).cgColor
        layer?.backgroundColor = NSColor(white: dark ? 0.15 : 0.975, alpha: 1).cgColor
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording = true
        label.stringValue = "Kürzel drücken …"
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { return }
        if event.keyCode == UInt16(kVK_Escape) {
            recording = false
            label.stringValue = "Eigenes Kürzel aufnehmen"
            needsDisplay = true
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option),
              let key = event.charactersIgnoringModifiers?.uppercased(), key.count == 1 else {
            label.stringValue = "⌘, ⌃ oder ⌥ plus Taste wählen"
            return
        }
        let display = "\(flags.contains(.control) ? "⌃" : "")\(flags.contains(.option) ? "⌥" : "")\(flags.contains(.shift) ? "⇧" : "")\(flags.contains(.command) ? "⌘" : "")\(key)"
        recording = false
        label.stringValue = display
        needsDisplay = true
        onShortcut?(Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, display: display))
    }
}
