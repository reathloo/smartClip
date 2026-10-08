import Foundation

enum CaptureState {
    case unavailable, setup, paused, denied, active

    var label: String {
        switch self {
        case .unavailable: "Verlauf nicht bereit"
        case .setup: "Noch nicht eingerichtet"
        case .paused: "Pausiert"
        case .denied: "Zugriff gesperrt"
        case .active: "Aufzeichnung aktiv"
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
        case .active: "Aufzeichnung aktiv"
        case .manual: "Pausiert"
        case .until(let date): "Pausiert bis \(date.formatted(date: .omitted, time: .shortened))"
        case .untilRestart: "Pausiert bis zum Neustart"
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
        case .retryStorage: "Erneut versuchen"
        case .openClipboardSettings, .openAccessibilitySettings: "Systemeinstellungen öffnen"
        case .openSmartClipSettings: "Kürzel ändern"
        }
    }
}
