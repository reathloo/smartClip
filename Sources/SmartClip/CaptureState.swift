import Foundation

enum CaptureState {
    case unavailable, setup, paused, denied, active

    var label: String {
        switch self {
        case .unavailable: L10n.text("History not ready")
        case .setup: L10n.text("Not set up yet")
        case .paused: L10n.text("Paused")
        case .denied: L10n.text("Access blocked")
        case .active: L10n.text("Capture active")
        }
    }
}

enum PauseMode: Equatable {
    case active
    case manual
    case until(Date)
    case untilRestart

    var isPaused: Bool { self != .active }

    func label(now: Date = .now) -> String {
        switch self {
        case .active: L10n.text("Capture active")
        case .manual: L10n.text("Paused")
        case .until(let date): L10n.text("Paused until %@", date.formatted(date: .omitted, time: .shortened))
        case .untilRestart: L10n.text("Paused until next launch")
        }
    }
}

enum RecoveryAction: Equatable {
    case retryStorage
    case openClipboardSettings
    case openAccessibilitySettings
    case openSmartClipSettings

    var title: String {
        switch self {
        case .retryStorage: L10n.text("Try again")
        case .openClipboardSettings, .openAccessibilitySettings: L10n.text("Open System Settings")
        case .openSmartClipSettings: L10n.text("Change shortcut")
        }
    }
}
