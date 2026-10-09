import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var searchFocused: Bool
    @State private var selectedID: UUID?

    private var selectedItem: ClipSummary? {
        guard let id = HistoryNavigation.selected(in: model.items.map(\.id), explicit: selectedID, search: model.search) else { return nil }
        return model.item(for: id)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if model.items.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: model.cardView ? 10 : 4) {
                            entrySection("Angeheftet", pinned: true)
                            entrySection("Zuletzt kopiert", pinned: false)
                        }
                        .padding(.horizontal, 12).padding(.bottom, 14)
                    }
                    .onChange(of: selectedID) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            }
            footer
        }
        .tint(ClipTheme.accent)
        .background(ClipTheme.canvas)
        .frame(minWidth: 560, minHeight: 540)
        .preferredColorScheme(model.darkMode ? .dark : .light)
        .onChange(of: model.items.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 1), value: model.cardView)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: model.filter)
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            header
            searchField.padding(.horizontal, 20)
            filters.padding(.horizontal, 20).padding(.top, 11).padding(.bottom, 13)
        }
        .background { chromeBackground }
        .shadow(color: .black.opacity(0.055), radius: 10, y: 4)
        .zIndex(1)
    }

    @ViewBuilder private var chromeBackground: some View {
        if reduceTransparency { ClipTheme.surface } else { Rectangle().fill(.ultraThinMaterial) }
    }

    private var header: some View {
        HStack(spacing: 11) {
            BrandMark()
            VStack(alignment: .leading, spacing: 2) {
                Text("SmartClip").font(.system(size: 17, weight: .semibold))
                Text("Alles Kopierte. Griffbereit.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                viewButton("Liste", symbol: "list.bullet", cards: false)
                viewButton("Karten", symbol: "rectangle.grid.1x2", cards: true)
            }
            .padding(3)
            .background(ClipTheme.subtleFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            AppearanceToggle(isDark: model.darkMode) { setDarkMode(!model.darkMode) }
            Button { model.onOpenSettings?() } label: { Image(systemName: "gearshape") }
                .buttonStyle(IconControlStyle()).help("Einstellungen")
                .accessibilityLabel("Einstellungen öffnen")
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 14)
    }

    private func setDarkMode(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { model.setDarkMode(value) }
    }

    private func viewButton(_ title: String, symbol: String, cards: Bool) -> some View {
        Button { model.setCardView(cards) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(model.cardView == cards ? ClipTheme.accent : Color.secondary)
                .frame(width: 30, height: 25)
                .background(model.cardView == cards ? ClipTheme.surface : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(ResponsiveButtonStyle()).help(title).accessibilityLabel(title)
        .accessibilityAddTraits(model.cardView == cards ? .isSelected : [])
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(.secondary)
            TextField("Verlauf durchsuchen …", text: $model.search)
                .textFieldStyle(.plain).font(.system(size: 14))
                .focused($searchFocused)
                .onAppear { searchFocused = true }
                .onChange(of: model.search) { _, _ in selectedID = nil; model.scheduleSearch() }
                .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                .onKeyPress(.return) {
                    model.applySearchImmediately()
                    if let selectedItem { model.copy(selectedItem) }
                    return .handled
                }
            if !model.search.isEmpty {
                Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Suche leeren")
            } else if let shortcut = model.shortcut {
                KeyboardHint(text: shortcut.display)
            }
        }
        .padding(.horizontal, 12).frame(height: 38)
        .background(ClipTheme.surface.opacity(reduceTransparency ? 1 : 0.82),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(searchFocused ? ClipTheme.accent.opacity(0.45) : ClipTheme.line))
        .shadow(color: searchFocused ? ClipTheme.accent.opacity(0.08) : .clear, radius: 5)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                filterButton("Alle", symbol: "square.stack", kind: nil)
                ForEach(ClipKind.allCases) { kind in
                    filterButton(kind.label, symbol: kind.symbol, kind: kind)
                }
            }
        }
    }

    private func filterButton(_ title: String, symbol: String, kind: ClipKind?) -> some View {
        let active = model.filter == kind
        return Button {
            model.filter = kind; selectedID = nil; model.applySearchImmediately()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .medium))
                Text(title).font(.system(size: 11, weight: active ? .semibold : .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(active ? Color.white : Color.secondary)
            .background(active ? ClipTheme.accent : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(ResponsiveButtonStyle()).accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder private func entrySection(_ title: String, pinned: Bool) -> some View {
        let items = model.items.filter { $0.isPinned == pinned }
        let selectedID = selectedItem?.id
        if !items.isEmpty {
            HStack(spacing: 6) {
                if pinned { Image(systemName: "pin.fill").font(.system(size: 10)) }
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(items.count)").font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 5)
            ForEach(items) { item in
                ClipRow(model: model, snapshot: item, card: model.cardView, selected: selectedID == item.id)
                    .id(item.id)
            }
        }
    }

    private var emptyState: some View {
        let searching = !model.search.isEmpty || model.filter != nil
        let state = model.captureState
        let title: String
        let message: String
        let symbol: String
        if searching {
            title = "Keine passenden Einträge"
            message = "Versuche einen anderen Suchbegriff oder setze die Filter zurück."
            symbol = "magnifyingglass"
        } else {
            switch state {
            case .unavailable:
                title = "Verlauf noch nicht verfügbar"
                message = "Prüfe, ob macOS auf deine Schlüsselbund-Freigabe wartet."
                symbol = "lock"
            case .setup:
                title = "Deine Zwischenablage, griffbereit"
                message = "Richte SmartClip ein und aktiviere die Aufzeichnung."
                symbol = "doc.on.clipboard"
            case .paused:
                title = "Aufzeichnung pausiert"
                message = "Setze die Aufzeichnung fort, um neue Kopien zu speichern."
                symbol = "pause"
            case .denied:
                title = "Zugriff auf die Zwischenablage gesperrt"
                message = "Erlaube SmartClip den Zugriff in den macOS-Systemeinstellungen."
                symbol = "hand.raised"
            case .active:
                title = "Platz für deine nächsten Ideen"
                message = "Kopiere einen Text, ein Bild oder eine Datei.\nSmartClip hält es hier für dich bereit."
                symbol = "doc.on.clipboard"
            }
        }
        return VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 27, weight: .light)).foregroundStyle(ClipTheme.accent)
                .frame(width: 66, height: 66)
                .background(ClipTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 19))
                .accessibilityHidden(true)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineSpacing(3)
            if searching {
                Button("Suche und Filter zurücksetzen") { selectedID = nil; model.resetSearch(); searchFocused = true }
                    .buttonStyle(.bordered).padding(.top, 4)
            } else if state == .paused {
                Button("Aufzeichnung fortsetzen") { model.setPaused(false) }
                    .buttonStyle(.bordered).padding(.top, 4)
            } else if state == .setup {
                Button("SmartClip einrichten") { model.onOpenSettings?() }
                    .buttonStyle(.bordered).padding(.top, 4)
            } else if state == .denied || state == .unavailable, model.recoveryAction != nil {
                Button(model.recoveryAction?.title ?? "Problem beheben") { model.performRecovery() }
                    .buttonStyle(.bordered).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if !model.statusMessage.isEmpty {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "info.circle")
                    Text(model.statusMessage).frame(maxWidth: .infinity, alignment: .leading)
                    if let recovery = model.recoveryAction {
                        Button(recovery.title) { model.performRecovery() }
                            .buttonStyle(.link).fixedSize()
                    }
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.vertical, 9)
            }
            HStack(spacing: 7) {
                Circle().fill(model.captureState == .active ? ClipTheme.accent : Color.orange)
                    .frame(width: 6, height: 6).accessibilityHidden(true)
                Text(model.captureStatusLabel)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Menu {
                    if model.isPaused {
                        Button("Aufzeichnung fortsetzen", systemImage: "play.fill") { model.setPaused(false) }
                        Divider()
                    }
                    Button("15 Minuten pausieren", systemImage: "timer") { model.pause(for: 15 * 60) }
                    Button("Bis zum Neustart pausieren", systemImage: "power") { model.pauseUntilRestart() }
                    Button("Unbegrenzt pausieren", systemImage: "pause.fill") { model.setPaused(true) }
                } label: {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11)).frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).foregroundStyle(.secondary)
                .help("Aufzeichnung steuern")
                .accessibilityLabel("Aufzeichnung steuern")
                .disabled(!model.onboardingComplete || !model.storageReady)
                Spacer()
                KeyboardHint(text: "↑ ↓")
                Text("Auswählen").font(.system(size: 10)).foregroundStyle(.secondary)
                KeyboardHint(text: "↵")
                Text(selectedItem == nil && !model.search.isEmpty ? "Suchen" : model.autoPaste ? "Einfügen" : "Kopieren")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Menu {
                    Button("Einstellungen") { model.onOpenSettings?() }
                    Divider()
                    Button("SmartClip beenden") { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
                .help("Weitere Optionen").accessibilityLabel("Weitere Optionen")
            }
            .padding(.horizontal, 20).frame(height: 42)
        }
        .background { chromeBackground }
        .shadow(color: .black.opacity(0.06), radius: 10, y: -4)
        .zIndex(1)
    }

    private func moveSelection(_ offset: Int) {
        // Resolve the latest query before selecting, even within the debounce interval.
        model.applySearchImmediately()
        selectedID = HistoryNavigation.moved(in: model.items.map(\.id), explicit: selectedID,
                                              search: model.search, offset: offset)
    }
}

private struct ClipRow: View {
    @ObservedObject var model: AppModel
    let snapshot: ClipSummary
    // Lazy rows may retain their identity when moving between sections. Resolve
    // actions and labels from the current model instead of the old row snapshot.
    private var item: ClipSummary { model.item(for: snapshot.id) ?? snapshot }
    let card: Bool
    let selected: Bool
    @State private var confirmUnmark = false
    @State private var confirmExclude = false
    @State private var editFavoriteName = false
    @State private var favoriteDraft = ""
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { model.copy(item) } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.isSensitive ? "lock" : item.kind.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(item.isSensitive ? Color.orange : item.kind.color)
                        .frame(width: 36, height: 36)
                        .background((item.isSensitive ? Color.orange : item.kind.color).opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 7) {
                        if let favoriteName = item.favoriteName {
                            Label(favoriteName, systemImage: "pin.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ClipTheme.accent)
                                .lineLimit(1)
                        }
                        if item.isSensitive {
                            Text("Sensibler Inhalt").font(.system(size: 13, weight: .medium))
                            Text("••••••••••••").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        } else {
                            if item.kind == .code {
                                Text(item.codeLanguage ?? "Sprache unklar")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(ClipKind.code.color)
                                    .help("Sprache automatisch anhand der Syntax geschätzt")
                            }
                            Text(item.preview.isEmpty ? item.kind.label : item.preview)
                                .font(.system(size: 13, weight: .medium, design: item.kind == .code ? .monospaced : .default))
                                .lineSpacing(3).lineLimit(card ? 4 : 2)
                                .multilineTextAlignment(.leading)
                        }
                        if card && item.kind == .image && !item.isSensitive {
                            ClipImagePreview(model: model, id: item.id)
                        }
                        HStack(spacing: 5) {
                            SourceAppIcon(bundleID: item.sourceBundleID, size: 13)
                            Text(item.sourceName ?? "Unbekannte App").help("Quell-App zum Kopierzeitpunkt geschätzt")
                            Text("·").foregroundStyle(.tertiary)
                            Text(item.lastCopiedAt, style: .relative)
                            if item.hasMissingFiles {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                                    .help("Originaldatei fehlt")
                            }
                        }
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ResponsiveButtonStyle())
            .accessibilityLabel("\(item.favoriteName.map { "\($0), " } ?? "")\(item.kind.label): \(item.isSensitive ? "sensibler Eintrag" : item.preview)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 2) {
                    Button { model.pin(item) } label: {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 11)).frame(width: 24, height: 24)
                    }
                    .buttonStyle(IconControlStyle())
                    .foregroundStyle(item.isPinned ? ClipTheme.accent : Color.secondary)
                    .opacity(item.isPinned || hovered || selected ? 1 : 0.65)
                    .help(item.isPinned ? "Lösen" : "Anheften")
                    .accessibilityLabel(item.isPinned ? "Eintrag lösen" : "Eintrag anheften")
                    actions
                }
                if item.copyCount > 1 {
                    Text("\(item.copyCount)×").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(card ? 15 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? ClipTheme.selection
                    : card ? ClipTheme.surface : hovered ? ClipTheme.surface.opacity(0.72) : .clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(selected ? ClipTheme.accent.opacity(0.34) : card ? ClipTheme.line : .clear))
        .shadow(color: card ? .black.opacity(0.035) : .clear, radius: 5, y: 2)
        .onHover { hovered = $0 }
        .confirmationDialog("Länger speichern?", isPresented: $confirmUnmark) {
            Button("Als normal einstufen") { model.markSensitive(item, false) }
        } message: {
            Text("Dieser Eintrag erhält dann die normale Aufbewahrungsfrist. Ein angehefteter Eintrag bleibt bis zum manuellen Löschen gespeichert.")
        }
        .confirmationDialog("App künftig ausschließen?", isPresented: $confirmExclude) {
            Button("\(item.sourceName ?? "Diese App") ausschließen", role: .destructive) {
                model.excludeSourceApp(of: item)
            }
        } message: {
            Text("Neue Kopien aus dieser App werden nicht mehr gespeichert. Vorhandene Einträge bleiben erhalten.")
        }
        .alert(item.favoriteName == nil ? "Favorit benennen" : "Favoritenname ändern",
               isPresented: $editFavoriteName) {
            TextField("Name", text: $favoriteDraft)
            Button("Speichern") { model.nameFavorite(item, favoriteDraft) }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der Name wird verschlüsselt gespeichert und ist über die Suche auffindbar.")
        }
    }

    private var actions: some View {
        Menu {
            Button("Kopieren", systemImage: "doc.on.doc") { model.copy(item) }
            if item.kind == .url { Button("URL öffnen", systemImage: "arrow.up.right") { model.openURL(item) } }
            Button(item.isPinned ? "Lösen" : "Anheften", systemImage: "pin") { model.pin(item) }
            Button(item.favoriteName == nil ? "Favorit benennen …" : "Favoritenname ändern …",
                   systemImage: "tag") {
                favoriteDraft = item.favoriteName ?? ""
                editFavoriteName = true
            }
            if item.favoriteName != nil {
                Button("Favoritenname entfernen", systemImage: "tag.slash") { model.nameFavorite(item, "") }
            }
            Button(item.isSensitive ? "Als normal einstufen" : "Als sensibel einstufen", systemImage: "lock") {
                if item.isSensitive { confirmUnmark = true }
                else { model.markSensitive(item, true) }
            }
            if item.sourceBundleID != nil {
                Divider()
                Button("\(item.sourceName ?? "Quell-App") künftig ausschließen", systemImage: "app.badge") {
                    confirmExclude = true
                }
            }
            Divider()
            Button("Löschen", systemImage: "trash", role: .destructive) { model.delete(item) }
        } label: { Image(systemName: "ellipsis").font(.system(size: 12)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22, height: 24)
            .help("Eintragsaktionen").accessibilityLabel("Eintragsaktionen")
    }
}

private struct ClipImagePreview: View {
    @ObservedObject var model: AppModel
    let id: UUID
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 155)
                    .padding(8)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .onAppear {
            if let data = model.payload(for: id)?.imageData { image = NSImage(data: data) }
        }
        .onDisappear { image = nil }
    }
}
