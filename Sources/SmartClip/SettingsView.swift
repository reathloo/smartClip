import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "Allgemein", history = "Verlauf", privacy = "Datenschutz"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .history: "clock.arrow.circlepath"
        case .privacy: "hand.raised"
        }
    }
    var subtitle: String {
        switch self {
        case .general: "So passt SmartClip in deinen Alltag."
        case .history: "Dein Verlauf, so lange du ihn brauchst."
        case .privacy: "Du bestimmst, was gespeichert wird."
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var tab: SettingsTab
    @State private var newExcludedBundle = ""

    init(model: AppModel, initialTab: SettingsTab = .general) {
        self.model = model
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(ClipTheme.line).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tab.rawValue).font(.system(size: 23, weight: .semibold))
                        Text(tab.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 3)
                    switch tab {
                    case .general: generalSettings
                    case .history: historySettings
                    case .privacy: privacySettings
                    }
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
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ClipTheme.canvas)
        }
        .tint(ClipTheme.accent)
        .background(ClipTheme.canvas)
        .frame(minWidth: 700, minHeight: 580)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                BrandMark(size: 29)
                Text("SmartClip").font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.top, 20).padding(.bottom, 27)
            ForEach(SettingsTab.allCases) { item in
                Button { tab = item } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.system(size: 12, weight: tab == item ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 11).padding(.vertical, 10)
                        .foregroundStyle(tab == item ? ClipTheme.accent : Color.primary.opacity(0.75))
                        .background(tab == item ? ClipTheme.accent.opacity(0.1) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain).accessibilityAddTraits(tab == item ? .isSelected : [])
            }
            Spacer()
            VStack(alignment: .leading, spacing: 5) {
                Label("Nur auf diesem Mac", systemImage: "lock.shield")
                    .font(.system(size: 10, weight: .medium))
                Text("Deine Zwischenablage bleibt bei dir.")
                    .font(.system(size: 10)).lineSpacing(2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.bottom, 20)
        }
        .padding(.horizontal, 12)
        .frame(width: 166)
        .frame(maxHeight: .infinity)
        .background(ClipTheme.sidebar)
    }

    private var generalSettings: some View {
        VStack(spacing: 18) {
            SettingsCard("Tastenkürzel", symbol: "keyboard") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SmartClip öffnen").font(.system(size: 12, weight: .medium))
                        Text("Jederzeit, aus jeder App.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(model.shortcut?.display ?? "Nicht festgelegt")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(model.shortcut == nil ? Color.secondary : ClipTheme.accent)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(ClipTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                }
                ShortcutRecorder(model: model).frame(height: 37)
                HStack(spacing: 12) {
                    Button("⌘⇧V verwenden") { model.setShortcut(.suggested) }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(ClipTheme.accent)
                    Text("Empfohlen").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                    if model.shortcut != nil {
                        Button("Entfernen") { model.setShortcut(nil) }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            if !model.onboardingComplete { onboardingCard }
            SettingsCard("Verhalten", symbol: "cursorarrow.click") {
                settingToggle("Direkt einfügen", detail: "Fügt den gewählten Eintrag in der vorherigen App ein.",
                              value: Binding(get: { model.autoPaste }, set: { model.setAutoPaste($0) }))
                Text("Benötigt die Bedienungshilfen-Freigabe. Ohne Freigabe wird der Eintrag nur kopiert.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider().overlay(ClipTheme.line)
                settingToggle("Beim Anmelden starten", detail: "SmartClip wartet in deiner Menüleiste.",
                              value: Binding(get: { model.autoStartEnabled }, set: { model.setAutoStart($0) }))
            }
            if model.onboardingComplete {
                SettingsCard("Aufzeichnung", symbol: "record.circle") {
                    settingToggle("Aufzeichnung pausieren", detail: model.captureStatusLabel,
                                  value: Binding(get: { model.isPaused }, set: { model.setPaused($0) }))
                    HStack(spacing: 14) {
                        Button("15 Minuten") { model.pause(for: 15 * 60) }
                        Button("Bis zum Neustart") { model.pauseUntilRestart() }
                        if model.isPaused { Button("Fortsetzen") { model.setPaused(false) } }
                    }
                    .buttonStyle(.link).font(.system(size: 11))
                }
            }
        }
    }

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Bereit für deine erste Kopie?").font(.system(size: 14, weight: .semibold))
            Text("Die Aufzeichnung beginnt mit deinem Klick. macOS kann dich anschließend um den Zugriff auf die Zwischenablage bitten.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            Button("Aufzeichnung starten") { model.setMonitoring(true) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(ClipTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var historySettings: some View {
        VStack(spacing: 18) {
            SettingsCard("Ansicht", symbol: "rectangle.grid.1x2") {
                settingRow("Verlauf darstellen", detail: "Kompakt oder mit größeren Vorschauen.") {
                    Picker("Ansicht", selection: Binding(get: { model.cardView }, set: { model.setCardView($0) })) {
                        Text("Liste").tag(false)
                        Text("Karten").tag(true)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 145)
                }
            }
            SettingsCard("Automatisch löschen", symbol: "clock") {
                settingRow("Normaler Verlauf", detail: "Frist seit dem letzten Kopieren.") {
                    Picker("Normaler Verlauf", selection: Binding(get: { model.normalDays }, set: { model.setNormalDays($0) })) {
                        Text("7 Tage").tag(7)
                        Text("30 Tage").tag(30)
                        Text("90 Tage").tag(90)
                        Text("365 Tage").tag(365)
                        Text("Niemals").tag(0)
                    }
                    .labelsHidden().frame(width: 125)
                }
                Divider()
                settingRow("Sensible Einträge", detail: "Auch angeheftet nur kurz aufbewahren.") {
                    Picker("Sensible Einträge", selection: Binding(get: { model.sensitiveSeconds }, set: { model.setSensitiveSeconds($0) })) {
                        Text("5 Minuten").tag(300)
                        Text("1 Stunde").tag(3_600)
                        Text("24 Stunden").tag(86_400)
                    }
                    .labelsHidden().frame(width: 125)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                note("pin", "Angeheftete Einträge bleiben erhalten. Für sensible Inhalte gilt weiterhin die kurze Frist.")
                note("doc.on.clipboard", "Die Löschfristen gelten für SmartClip. Der Inhalt der macOS-Zwischenablage bleibt davon unberührt.")
            }
            .padding(.horizontal, 4)
        }
    }

    private var privacySettings: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield").font(.system(size: 23, weight: .light)).foregroundStyle(ClipTheme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Lokal. Verschlüsselt. Privat.").font(.system(size: 14, weight: .semibold))
                    Text("Deine Inhalte werden verschlüsselt auf diesem Mac gespeichert. SmartClip benötigt weder Konto noch Cloud.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(ClipTheme.accent.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
            SettingsCard("Apps ausschließen", symbol: "app.badge.checkmark") {
                Text("Aus diesen Apps werden künftig keine Kopien erfasst. Die Quell-App wird zum Zeitpunkt der Erfassung geschätzt.")
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
                    Text("Sobald du etwas kopiert hast, erscheinen die erkannten Apps hier.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9)
                }
                Divider()
                Text("App über Bundle-ID hinzufügen").font(.system(size: 11, weight: .medium))
                HStack(spacing: 8) {
                    TextField("z. B. com.apple.Terminal", text: $newExcludedBundle)
                        .textFieldStyle(.roundedBorder).onSubmit(addExcludedApp)
                    Button(action: addExcludedApp) { Image(systemName: "plus") }
                        .disabled(newExcludedBundle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("App ausschließen").accessibilityLabel("App ausschließen")
                }
            }
            note("lock.open", "Maskierte Inhalte werden beim erneuten Kopieren als Originalwert in die macOS-Zwischenablage geschrieben.")
                .padding(.horizontal, 4)
        }
    }

    private func excludedAppRow(bundle: String, name: String) -> some View {
        HStack(spacing: 10) {
            SourceAppIcon(bundleID: bundle, size: 25)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if bundle != name { Text(bundle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            Toggle("\(name) ausschließen", isOn: Binding(
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
        .background(ClipTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ClipTheme.line))
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
