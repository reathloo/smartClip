import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General", history = "History", privacy = "Privacy", about = "About SmartClip"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .history: "clock.arrow.circlepath"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }
    var subtitle: String {
        switch self {
        case .general: "Make SmartClip fit your workflow."
        case .history: "Keep your history for as long as you need it."
        case .privacy: "You decide what gets stored."
        case .about: "Version, requirements, and helpful links."
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var tab: SettingsTab
    @State private var newExcludedBundle = ""
    @State private var confirmDeleteAll = false
    @AppStorage("SUAutomaticallyUpdate") private var automaticallyInstallUpdates = true

    init(model: AppModel, initialTab: SettingsTab = .general) {
        self.model = model
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tab.rawValue).font(.system(size: 24, weight: .semibold))
                        Text(tab.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 3)
                    Group {
                        switch tab {
                        case .general: generalSettings
                        case .history: historySettings
                        case .privacy: privacySettings
                        case .about: aboutSettings
                        }
                    }
                    .id(tab)
                    .transition(.opacity)
                    if !model.statusMessage.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Label(model.statusMessage, systemImage: "info.circle")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if let recovery = model.recoveryAction {
                                Button(recovery.title) { model.performRecovery() }
                                    .buttonStyle(.link).font(.system(size: 11)).fixedSize()
                            }
                        }
                    }
                }
                .padding(.horizontal, 30).padding(.vertical, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ClipTheme.canvas)
        }
        .tint(ClipTheme.accent)
        .background(ClipTheme.canvas)
        .frame(minWidth: 700, minHeight: 580)
        .preferredColorScheme(model.darkMode ? .dark : .light)
        .environment(\.locale, Locale(identifier: "en_US"))
        .alert("Delete all history?", isPresented: $confirmDeleteAll) {
            Button("Delete all", role: .destructive) { model.deleteAllHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All regular, sensitive, and pinned entries will be permanently removed from SmartClip. Settings and the current macOS clipboard remain unchanged.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                BrandMark(size: 29)
                Text("SmartClip")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
                AppearanceToggle(isDark: model.darkMode) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        model.setDarkMode(!model.darkMode)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.top, 20).padding(.bottom, 27)
            ForEach(SettingsTab.allCases) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) { tab = item }
                } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.system(size: 12, weight: tab == item ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 11).padding(.vertical, 10)
                        .foregroundStyle(tab == item ? ClipTheme.accent : Color.primary.opacity(0.75))
                        .background(tab == item ? ClipTheme.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(ResponsiveButtonStyle()).accessibilityAddTraits(tab == item ? .isSelected : [])
            }
            Spacer()
            VStack(alignment: .leading, spacing: 5) {
                Label("Only on this Mac", systemImage: "lock.shield")
                    .font(.system(size: 10, weight: .medium))
                Text("Your clipboard stays with you.")
                    .font(.system(size: 10)).lineSpacing(2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.bottom, 20)
        }
        .padding(.horizontal, 12)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background {
            if reduceTransparency { ClipTheme.sidebar } else { Rectangle().fill(.thinMaterial) }
        }
        .overlay(alignment: .trailing) { Rectangle().fill(ClipTheme.line).frame(width: 1) }
    }

    private var generalSettings: some View {
        VStack(spacing: 18) {
            SettingsCard("Keyboard shortcut", symbol: "keyboard") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open SmartClip").font(.system(size: 12, weight: .medium))
                        Text("Anytime, from any app.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(model.shortcut?.display ?? "Not set")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(model.shortcut == nil ? Color.secondary : ClipTheme.accent)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(ClipTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                }
                ShortcutRecorder(model: model).frame(height: 37)
                HStack(spacing: 12) {
                    Button("Use ⌘⇧V") { model.setShortcut(.suggested) }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(ClipTheme.accent)
                    Text("Recommended").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                    if model.shortcut != nil {
                        Button("Remove") { model.setShortcut(nil) }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            if !model.onboardingComplete { onboardingCard }
            SettingsCard("Behavior", symbol: "cursorarrow.click") {
                settingToggle("Paste automatically", detail: "Pastes the selected entry into the previously active app.",
                              value: Binding(get: { model.autoPaste }, set: { model.setAutoPaste($0) }))
                Text("Requires Accessibility permission. Without it, the entry is only copied.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider().overlay(ClipTheme.line)
                settingToggle("Launch at login", detail: "SmartClip waits in your menu bar.",
                              value: Binding(get: { model.autoStartEnabled }, set: { model.setAutoStart($0) }))
                Divider().overlay(ClipTheme.line)
                settingToggle("Install updates automatically", detail: "Downloads trusted SmartClip releases and installs them when the app restarts.",
                              value: $automaticallyInstallUpdates)
            }
            if model.onboardingComplete {
                SettingsCard("Capture", symbol: "record.circle") {
                    settingToggle("Pause capture", detail: model.captureStatusLabel,
                                  value: Binding(get: { model.isPaused }, set: { model.setPaused($0) }))
                    HStack(spacing: 14) {
                        Button("15 minutes") { model.pause(for: 15 * 60) }
                        Button("Until next launch") { model.pauseUntilRestart() }
                        if model.isPaused { Button("Resume") { model.setPaused(false) } }
                    }
                    .buttonStyle(.link).font(.system(size: 11))
                }
            }
        }
    }

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Ready for your first copy?").font(.system(size: 14, weight: .semibold))
            Text("Capture starts when you click. macOS may then ask for clipboard access.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            Button("Start capture") { model.setMonitoring(true) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(ClipTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var historySettings: some View {
        VStack(spacing: 18) {
            SettingsCard("View", symbol: "rectangle.grid.1x2") {
                settingRow("History layout", detail: "Compact or with larger previews.") {
                    Picker("View", selection: Binding(get: { model.cardView }, set: { model.setCardView($0) })) {
                        Text("List").tag(false)
                        Text("Cards").tag(true)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 145)
                }
            }
            SettingsCard("Automatic deletion", symbol: "clock") {
                settingRow("Regular history", detail: "Time since the most recent copy.") {
                    Picker("Regular history", selection: Binding(get: { model.normalDays }, set: { model.setNormalDays($0) })) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("365 days").tag(365)
                        Text("Never").tag(0)
                    }
                    .labelsHidden().frame(width: 125)
                }
                Divider()
                settingRow("Sensitive entries", detail: "Keep for a short time even when pinned.") {
                    Picker("Sensitive entries", selection: Binding(get: { model.sensitiveSeconds }, set: { model.setSensitiveSeconds($0) })) {
                        Text("5 minutes").tag(300)
                        Text("1 hour").tag(3_600)
                        Text("24 hours").tag(86_400)
                    }
                    .labelsHidden().frame(width: 125)
                }
            }
            SettingsCard("Manage history", symbol: "trash") {
                settingRow("Delete all history",
                           detail: "Removes every entry, including favorites and sensitive content.") {
                    Button("Delete all", role: .destructive) { confirmDeleteAll = true }
                        .buttonStyle(.bordered).tint(.red)
                }
                Text("The current macOS clipboard and your settings are not changed.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 14) {
                note("pin", "Pinned entries are retained. The short limit still applies to sensitive content.")
                note("doc.on.clipboard", "Retention limits apply to SmartClip. They do not change the current macOS clipboard.")
            }
            .padding(.horizontal, 4)
        }
    }

    private var privacySettings: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield").font(.system(size: 23, weight: .light)).foregroundStyle(ClipTheme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Local. Encrypted. Private.").font(.system(size: 14, weight: .semibold))
                    Text("Your content is stored encrypted on this Mac. SmartClip needs no account or cloud service.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(ClipTheme.accent.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
            SettingsCard("Exclude apps", symbol: "app.badge.checkmark") {
                Text("Future copies from these apps are ignored. The source app is estimated at capture time.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(2)
                ForEach(model.knownApps, id: \.0) { bundle, name in
                    excludedAppRow(bundle: bundle, name: name)
                }
                ForEach(Array(model.excludedBundles).sorted().filter { bundle in
                    !model.knownApps.contains(where: { $0.0 == bundle })
                }, id: \.self) { bundle in
                    excludedAppRow(bundle: bundle, name: bundle)
                }
                if model.knownApps.isEmpty && model.excludedBundles.isEmpty {
                    Text("Detected apps appear here after you copy something.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9)
                }
                Divider()
                Text("Add app by bundle ID").font(.system(size: 11, weight: .medium))
                HStack(spacing: 8) {
                    TextField("e.g. com.apple.Terminal", text: $newExcludedBundle)
                        .textFieldStyle(.roundedBorder).onSubmit(addExcludedApp)
                    Button(action: addExcludedApp) { Image(systemName: "plus") }
                        .disabled(newExcludedBundle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Exclude app").accessibilityLabel("Exclude app")
                }
            }
            note("lock.open", "Copying masked content places its original value on the macOS clipboard.")
                .padding(.horizontal, 4)
        }
    }

    private var aboutSettings: some View {
        VStack(spacing: 18) {
            VStack(spacing: 13) {
                BrandMark(size: 68)
                VStack(spacing: 4) {
                    Text("SmartClip").font(.system(size: 22, weight: .semibold))
                    Text(AppInfo.versionLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text("Your local, encrypted clipboard history for Mac.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 10).frame(maxWidth: .infinity)

            SettingsCard("System", symbol: "desktopcomputer") {
                settingRow("Requirement", detail: "Optimized for current Macs.") {
                    Text("macOS 14+ · Apple Silicon")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                Divider()
                settingRow("Processing", detail: "No account, cloud service, or telemetry.") {
                    Label("Local", systemImage: "checkmark.shield")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(ClipTheme.accent)
                }
            }

            SettingsCard("Links", symbol: "link") {
                Button { model.onCheckForUpdates?() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(ClipTheme.accent).frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Check for updates").font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                            Text("Look for a newer signed SmartClip release.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(ResponsiveButtonStyle()).accessibilityLabel("Check for updates")
                .padding(.vertical, 2)
                Divider()
                aboutLink("Installation", detail: "Instructions for the unsigned beta.", symbol: "questionmark.circle",
                          url: "https://github.com/reathloo/smartClip/blob/main/docs/INSTALLATION.md")
                Divider()
                aboutLink("Privacy", detail: "What SmartClip stores locally.", symbol: "hand.raised",
                          url: "https://github.com/reathloo/smartClip/blob/main/PRIVACY.md")
            }

            note("exclamationmark.shield", "This free beta has no Apple Developer ID and is not notarized.")
                .padding(.horizontal, 4)
        }
    }

    private func aboutLink(_ title: String, detail: String, symbol: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(ClipTheme.accent).frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ResponsiveButtonStyle()).accessibilityLabel("Open \(title)")
        .padding(.vertical, 2)
    }

    private func excludedAppRow(bundle: String, name: String) -> some View {
        HStack(spacing: 10) {
            SourceAppIcon(bundleID: bundle, size: 25)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if bundle != name { Text(bundle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            Toggle("Exclude \(name)", isOn: Binding(
                get: { model.excludedBundles.contains(bundle) },
                set: { model.setExcluded(bundle, excluded: $0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.vertical, 5)
    }

    private func addExcludedApp() {
        model.setExcluded(newExcludedBundle, excluded: true)
        newExcludedBundle = ""
    }

    private func settingToggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        settingRow(title, detail: detail) {
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }

    private func settingRow<Control: View>(_ title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
    }

    private func note(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 15)
            Text(text).font(.system(size: 11)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum AppInfo {
    static var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !build.isEmpty else { return "Version \(version)" }
        return "Version \(version) · Build \(build)"
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            content
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(ClipTheme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(ClipTheme.line))
        .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView(frame: NSRect(x: 0, y: 0, width: 360, height: 37))
        view.onShortcut = { [weak model] shortcut in model?.setShortcut(shortcut) }
        return view
    }
    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {}
}
