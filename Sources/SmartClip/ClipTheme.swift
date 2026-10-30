import AppKit
import SwiftUI

enum ClipTheme {
    static let accent = adaptive(light: 0x237B70, dark: 0x72CDBB)
    static let canvas = adaptive(light: 0xF3F5F4, dark: 0x1B1F1E)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x262B29)
    static let sidebar = adaptive(light: 0xE9EDEB, dark: 0x171B1A)
    static let line = Color.primary.opacity(0.075)
    static let subtleFill = Color.primary.opacity(0.045)
    static let selection = accent.opacity(0.11)

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
            .background(
                LinearGradient(colors: [Color(red: 0.17, green: 0.55, blue: 0.49),
                                        Color(red: 0.10, green: 0.39, blue: 0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            )
            .shadow(color: ClipTheme.accent.opacity(0.18), radius: 7, y: 3)
            .accessibilityHidden(true)
    }
}

struct IconControlStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(configuration.isPressed ? Color.primary.opacity(0.10) : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 1),
                       value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ResponsiveButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 1),
                       value: configuration.isPressed)
    }
}

struct AppearanceToggle: View {
    let isDark: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isDark ? "sun.max.fill" : "moon.fill")
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(IconControlStyle())
        .help(isDark ? "Hellmodus" : "Dunkelmodus")
        .accessibilityLabel(isDark ? "Hellmodus aktivieren" : "Dunkelmodus aktivieren")
    }
}

struct KeyboardHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(ClipTheme.subtleFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(ClipTheme.line))
    }
}

struct SourceAppIcon: View {
    let bundleID: String?
    var size: CGFloat = 14
    var body: some View {
        if let bundleID, let icon = SourceAppIconCache.icon(for: bundleID) {
            Image(nsImage: icon)
                .resizable().frame(width: size, height: size).accessibilityHidden(true)
        } else {
            Image(systemName: "app.dashed").font(.system(size: size)).foregroundStyle(.tertiary)
                .frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}

@MainActor
private enum SourceAppIconCache {
    private static let images = NSCache<NSString, NSImage>()

    static func icon(for bundleID: String) -> NSImage? {
        let key = bundleID as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        images.setObject(image, forKey: key)
        return image
    }
}
