import AppKit
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case light
    case midnight
    case forest

    var id: String { rawValue }
    var label: String {
        switch self {
        case .light: "Light"
        case .midnight: "Midnight"
        case .forest: "Forest"
        }
    }
    var symbol: String {
        switch self {
        case .light: "sun.max.fill"
        case .midnight: "moon.stars.fill"
        case .forest: "leaf.fill"
        }
    }
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
    var accentNSColor: NSColor {
        switch self {
        case .light: NSColor(srgbRed: 0.14, green: 0.48, blue: 0.44, alpha: 1)
        case .midnight: NSColor(srgbRed: 0.63, green: 0.67, blue: 1, alpha: 1)
        case .forest: NSColor(srgbRed: 0.45, green: 0.80, blue: 0.73, alpha: 1)
        }
    }
}

struct ClipPalette: Equatable {
    let accent: Color
    let accentFill: Color
    let canvas: Color
    let surface: Color
    let sidebar: Color
    let brandTop: Color
    let brandBottom: Color

    var line: Color { Color.primary.opacity(0.075) }
    var subtleFill: Color { Color.primary.opacity(0.045) }
    var selection: Color { accent.opacity(0.12) }
}

enum ClipTheme {
    static func palette(for mode: AppearanceMode) -> ClipPalette {
        switch mode {
        case .light:
            ClipPalette(accent: hex(0x237B70), accentFill: hex(0x237B70),
                        canvas: hex(0xF3F5F4), surface: .white, sidebar: hex(0xE9EDEB),
                        brandTop: hex(0x2B8C7D), brandBottom: hex(0x1A6359))
        case .midnight:
            ClipPalette(accent: hex(0xA1AAFF), accentFill: hex(0x5968D9),
                        canvas: hex(0x15161A), surface: hex(0x202228), sidebar: hex(0x111216),
                        brandTop: hex(0x7480EE), brandBottom: hex(0x4D59BA))
        case .forest:
            ClipPalette(accent: hex(0x72CDBB), accentFill: hex(0x397F71),
                        canvas: hex(0x1B1F1E), surface: hex(0x262B29), sidebar: hex(0x171B1A),
                        brandTop: hex(0x2B8C7D), brandBottom: hex(0x1A6359))
        }
    }

    private static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 255) / 255,
              green: Double((value >> 8) & 255) / 255,
              blue: Double(value & 255) / 255)
    }
}

private struct ClipPaletteKey: EnvironmentKey {
    static let defaultValue = ClipTheme.palette(for: .light)
}

extension EnvironmentValues {
    var clipPalette: ClipPalette {
        get { self[ClipPaletteKey.self] }
        set { self[ClipPaletteKey.self] = newValue }
    }
}

extension ClipKind {
    func color(in palette: ClipPalette) -> Color {
        switch self {
        case .text: .secondary
        case .code: .indigo
        case .url: palette.accent
        case .email: .orange
        case .image: .purple
        case .files: .blue
        }
    }
}

struct BrandMark: View {
    @Environment(\.clipPalette) private var theme
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: "paperclip")
            .font(.system(size: size * 0.49, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [theme.brandTop, theme.brandBottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            )
            .shadow(color: theme.accent.opacity(0.18), radius: 7, y: 3)
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

struct AppearancePicker: View {
    let mode: AppearanceMode
    let onSelect: (AppearanceMode) -> Void

    var body: some View {
        Menu {
            ForEach(AppearanceMode.allCases) { candidate in
                Button { onSelect(candidate) } label: {
                    Label(candidate.label, systemImage: candidate == mode ? "checkmark" : candidate.symbol)
                }
            }
        } label: {
            Image(systemName: mode.symbol).symbolRenderingMode(.hierarchical)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(IconControlStyle())
        .help("Appearance: \(mode.label)")
        .accessibilityLabel("Choose appearance. Current theme: \(mode.label)")
    }
}

struct KeyboardHint: View {
    @Environment(\.clipPalette) private var theme
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(theme.subtleFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(theme.line))
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
