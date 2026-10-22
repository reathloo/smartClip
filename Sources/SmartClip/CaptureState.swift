import Foundation

enum CaptureState {
    case unavailable, setup, paused, denied, active

    var label: String {
        switch self {
        case .unavailable: "History not ready"
        case .setup: "Not set up yet"
        case .paused: "Paused"
        case .denied: "Access blocked"
        case .active: "Capture active"
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
        case .active: "Capture active"
        case .manual: "Paused"
        case .until(let date): "Paused until \(date.formatted(date: .omitted, time: .shortened))"
        case .untilRestart: "Paused until next launch"
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
        case .retryStorage: "Try again"
        case .openClipboardSettings, .openAccessibilitySettings: "Open System Settings"
        case .openSmartClipSettings: "Change shortcut"
        }
    }
}
