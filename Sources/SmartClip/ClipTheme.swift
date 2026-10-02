import AppKit
import SwiftUI

enum ClipTheme {
    static let accent = adaptive(light: 0x237B70, dark: 0x72CDBB)
    static let canvas = adaptive(light: 0xF5F6F5, dark: 0x202423)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x2A2F2D)
    static let sidebar = adaptive(light: 0xEBEEEC, dark: 0x1C201F)
    static let line = Color.primary.opacity(0.08)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

extension ClipKind {
    var color: Color {
        switch self {
        case .text: .secondary
        case .code: .indigo
        case .url: ClipTheme.accent
        case .email: .orange
        case .image: .purple
        case .files: .blue
        }
    }
}

struct BrandMark: View {
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: "paperclip")
            .font(.system(size: size * 0.49, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(red: 0.14, green: 0.48, blue: 0.43),
                        in: RoundedRectangle(cornerRadius: size * 0.29))
            .accessibilityHidden(true)
    }
}

struct IconControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(configuration.isPressed ? Color.primary.opacity(0.09) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct KeyboardHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(ClipTheme.line))
    }
}

struct SourceAppIcon: View {
    let bundleID: String?
    var size: CGFloat = 14
    var body: some View {
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: size, height: size).accessibilityHidden(true)
        } else {
            Image(systemName: "app.dashed").font(.system(size: size)).foregroundStyle(.tertiary)
                .frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}
