import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocused: Bool
    @State private var selectedID: UUID?

    private var selectedItem: ClipSummary? {
        if let selectedID { return model.items.first { $0.id == selectedID } }
        return model.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? model.items.first : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField.padding(.horizontal, 20)
            filters.padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 16)
            Rectangle().fill(ClipTheme.line).frame(height: 1)
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
        .onChange(of: model.items.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        }
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
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            Button { model.onOpenSettings?() } label: { Image(systemName: "gearshape") }
                .buttonStyle(IconControlStyle()).help("Einstellungen")
                .accessibilityLabel("Einstellungen öffnen")
        }
        .padding(20)
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
        .buttonStyle(.plain).help(title).accessibilityLabel(title)
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
                    if let selectedItem { model.copy(selectedItem) }
                    else { model.refresh() }
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
        .padding(.horizontal, 13).frame(height: 43)
        .background(ClipTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(searchFocused ? ClipTheme.accent.opacity(0.5) : ClipTheme.line))
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 5) {
            filterButton("Alle", symbol: "square.stack", kind: nil)
            ForEach(ClipKind.allCases) { kind in
                filterButton(kind.label, symbol: kind.symbol, kind: kind)
            }
            Spacer(minLength: 0)
        }
        }
    }

    private func filterButton(_ title: String, symbol: String, kind: ClipKind?) -> some View {
        let active = model.filter == kind
        return Button {
            model.filter = kind; selectedID = nil; model.refresh()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .medium))
                Text(title).font(.system(size: 11, weight: active ? .semibold : .medium))
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .foregroundStyle(active ? ClipTheme.accent : Color.secondary)
            .background(active ? ClipTheme.accent.opacity(0.10) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder private func entrySection(_ title: String, pinned: Bool) -> some View {
        let items = model.items.filter { $0.isPinned == pinned }
        if !items.isEmpty {
            HStack(spacing: 6) {
                if pinned { Image(systemName: "pin.fill").font(.system(size: 10)) }
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(items.count)").font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 5)
            ForEach(items) { item in
                ClipRow(model: model, snapshot: item, card: model.cardView, selected: selectedItem?.id == item.id)
                    .id(item.id)
            }
        }
    }

    private var emptyState: some View {
        let searching = !model.search.isEmpty || model.filter != nil
        let paused = model.isPaused && !searching
        return VStack(spacing: 12) {
            Image(systemName: searching ? "magnifyingglass" : paused ? "pause" : "doc.on.clipboard")
                .font(.system(size: 27, weight: .light)).foregroundStyle(ClipTheme.accent)
                .frame(width: 66, height: 66)
                .background(ClipTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 19))
            Text(searching ? "Keine passenden Einträge" : paused ? "Aufzeichnung pausiert" : "Platz für deine nächsten Ideen")
                .font(.system(size: 15, weight: .semibold))
            Text(searching ? "Versuche einen anderen Suchbegriff oder Filter."
                 : paused ? "Setze die Aufzeichnung fort, um neue Kopien zu speichern."
                 : "Kopiere einen Text, ein Bild oder eine Datei.\nSmartClip hält es hier für dich bereit.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineSpacing(3)
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
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.vertical, 9)
                .background(ClipTheme.surface)
            }
            Rectangle().fill(ClipTheme.line).frame(height: 1)
            HStack(spacing: 7) {
                Circle().fill(model.isPaused || !model.onboardingComplete || !model.storageReady ? Color.orange : ClipTheme.accent)
                    .frame(width: 6, height: 6).accessibilityHidden(true)
                Text(!model.storageReady ? "Verlauf nicht bereit" : !model.onboardingComplete ? "Noch nicht eingerichtet" : model.isPaused ? "Pausiert" : "Aufzeichnung aktiv")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button { model.setPaused(!model.isPaused) } label: {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill").font(.system(size: 9))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(model.isPaused ? "Aufzeichnung fortsetzen" : "Aufzeichnung pausieren")
                .accessibilityLabel(model.isPaused ? "Aufzeichnung fortsetzen" : "Aufzeichnung pausieren")
                .disabled(!model.onboardingComplete)
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
    }

    private func moveSelection(_ offset: Int) {
        guard !model.items.isEmpty else { return }
        if let current = model.items.firstIndex(where: { $0.id == selectedItem?.id }) {
            selectedID = model.items[min(max(0, current + offset), model.items.count - 1)].id
        } else {
            selectedID = (offset > 0 ? model.items.first : model.items.last)?.id
        }
    }
}

private struct ClipRow: View {
    @ObservedObject var model: AppModel
    let snapshot: ClipSummary
    // Lazy rows may retain their identity when moving between sections. Resolve
    // actions and labels from the current model instead of the old row snapshot.
    private var item: ClipSummary { model.items.first { $0.id == snapshot.id } ?? snapshot }
    let card: Bool
    let selected: Bool
    @State private var confirmUnmark = false
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
                            Text(item.sourceName ?? "Unbekannte App")
                            Text("·").foregroundStyle(.tertiary)
                            Text(item.lastCopiedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
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
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.kind.label): \(item.isSensitive ? "sensibler Eintrag" : item.preview)")
            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 2) {
                    Button { model.pin(item) } label: {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 11)).frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(item.isPinned ? ClipTheme.accent : Color.secondary)
                    .opacity(item.isPinned || hovered || selected ? 1 : 0.25)
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
        .background(selected ? ClipTheme.accent.opacity(0.065)
                    : card ? ClipTheme.surface : hovered ? Color.primary.opacity(0.025) : .clear,
                    in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(selected ? ClipTheme.accent.opacity(0.3) : card ? ClipTheme.line : .clear))
        .onHover { hovered = $0 }
        .confirmationDialog("Länger speichern?", isPresented: $confirmUnmark) {
            Button("Als normal einstufen") { model.markSensitive(item, false) }
        } message: {
            Text("Dieser Eintrag erhält dann die normale Aufbewahrungsfrist. Ein angehefteter Eintrag bleibt bis zum manuellen Löschen gespeichert.")
        }
    }

    private var actions: some View {
        Menu {
            Button("Kopieren", systemImage: "doc.on.doc") { model.copy(item) }
            if item.kind == .url { Button("URL öffnen", systemImage: "arrow.up.right") { model.openURL(item) } }
            Button(item.isPinned ? "Lösen" : "Anheften", systemImage: "pin") { model.pin(item) }
            Button(item.isSensitive ? "Als normal einstufen" : "Als sensibel einstufen", systemImage: "lock") {
                if item.isSensitive { confirmUnmark = true }
                else { model.markSensitive(item, true) }
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
