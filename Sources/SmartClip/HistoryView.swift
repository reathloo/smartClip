import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var searchFocused: Bool
    @State private var searchText = ""
    @State private var showingRefinements = false
    private var theme: ClipPalette { ClipTheme.palette(for: model.appearanceMode) }

    private var selectedItem: ClipSummary? {
        guard let id = HistoryNavigation.selected(in: model.itemIDs, explicit: model.selectedID, search: searchText) else { return nil }
        return model.item(for: id)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if let previewedID = model.previewedID, let item = model.item(for: previewedID) {
                    ClipPreviewView(
                        item: item,
                        loadPayload: { await model.loadPayload(for: $0) },
                        loadNote: { await model.loadNote(for: $0) },
                        saveNote: { await model.saveNote($0, for: item) },
                        onClose: { model.closePreview() },
                        onCopy: { model.copy(item) },
                        onOpen: item.kind == .url ? { model.openURL(item) } : nil
                    )
                } else {
                    topBar
                    if model.items.isEmpty {
                        emptyState
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: model.cardView ? 10 : 4) {
                                    entrySection("Pinned", pinned: true)
                                    entrySection("Recently copied", pinned: false)
                                    loadMoreSection
                                }
                                .padding(.horizontal, 12).padding(.bottom, 14)
                            }
                            .onChange(of: model.selectedID) { _, id in
                                if let id { proxy.scrollTo(id) }
                            }
                        }
                    }
                    footer
                }
            }
            if let message = model.copyConfirmationMessage {
                copyConfirmation(message)
            }
        }
        .tint(theme.accent)
        .background(theme.canvas)
        .frame(minWidth: 560, minHeight: 540)
        .preferredColorScheme(model.appearanceMode.colorScheme)
        .environment(\.clipPalette, theme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .onChange(of: model.itemIDs) { _, ids in
            if let selectedID = model.selectedID, !ids.contains(selectedID) { model.selectedID = nil }
            if let previewedID = model.previewedID, !ids.contains(previewedID) { model.previewedID = nil }
        }
        .onAppear {
            searchText = model.search
            searchFocused = false
        }
        .onChange(of: model.focusSearchRequest) { _, _ in searchFocused = true }
        .alert("Delete selected entry?", isPresented: Binding(
            get: { model.pendingDeleteID != nil },
            set: { if !$0 { model.pendingDeleteID = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = model.pendingDeleteID, let item = model.item(for: id) { model.delete(item) }
                model.pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) { model.pendingDeleteID = nil }
        } message: {
            Text("This removes the entry from SmartClip. The current macOS clipboard is unchanged.")
        }
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 1), value: model.cardView)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: model.filter)
    }

    private func copyConfirmation(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(theme.accent)
            Text(message)
                .font(.system(size: 17, weight: .semibold))
        }
        .padding(.horizontal, 30).padding(.vertical, 24)
        .background(theme.surface.opacity(reduceTransparency ? 1 : 0.96),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.line))
        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
        .zIndex(10)
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 8) {
                searchField
                    .frame(maxWidth: .infinity)
                    .layoutPriority(-1)
                refinementMenu
                    .fixedSize()
                    .layoutPriority(1)
            }
            .padding(.horizontal, 20)
            filters.padding(.horizontal, 20).padding(.top, 11).padding(.bottom, 13)
        }
        .background { chromeBackground }
        .shadow(color: .black.opacity(0.055), radius: 10, y: 4)
        .zIndex(1)
    }

    @ViewBuilder private var chromeBackground: some View {
        if reduceTransparency { theme.surface } else { Rectangle().fill(.ultraThinMaterial) }
    }

    private var header: some View {
        HStack(spacing: 11) {
            BrandMark()
            VStack(alignment: .leading, spacing: 2) {
                Text("SmartClip").font(.system(size: 17, weight: .semibold))
                Text("Everything you copied. Within reach.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                viewButton("List", symbol: "list.bullet", cards: false)
                viewButton("Cards", symbol: "rectangle.grid.1x2", cards: true)
            }
            .padding(3)
            .background(theme.subtleFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            AppearancePicker(mode: model.appearanceMode) { setAppearanceMode($0) }
            Button { model.onOpenSettings?() } label: { Image(systemName: "gearshape") }
                .buttonStyle(IconControlStyle()).help("Settings")
                .accessibilityLabel("Open settings")
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 14)
    }

    private func setAppearanceMode(_ mode: AppearanceMode) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { model.setAppearanceMode(mode) }
    }

    private func viewButton(_ title: String, symbol: String, cards: Bool) -> some View {
        Button { model.setCardView(cards) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(model.cardView == cards ? theme.accent : Color.secondary)
                .frame(width: 30, height: 25)
                .background(model.cardView == cards ? theme.surface : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(ResponsiveButtonStyle()).help(title).accessibilityLabel(title)
        .accessibilityAddTraits(model.cardView == cards ? .isSelected : [])
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(.secondary)
            TextField("Search history…", text: $searchText)
                .textFieldStyle(.plain).font(.system(size: 14))
                .focused($searchFocused)
                .onChange(of: searchText) { _, query in
                    model.selectedID = nil
                    model.scheduleSearch(query)
                }
                .onChange(of: model.search) { _, query in
                    if searchText != query { searchText = query }
                }
                .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                .onKeyPress(.return) {
                    model.applySearchImmediately(searchText)
                    if let selectedItem { model.copy(selectedItem) }
                    return .handled
                }
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Clear search")
            } else if let shortcut = model.shortcut {
                KeyboardHint(text: shortcut.display)
            }
        }
        .padding(.horizontal, 12).frame(height: 38)
        .background(theme.surface.opacity(reduceTransparency ? 1 : 0.82),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(searchFocused ? theme.accent.opacity(0.45) : theme.line))
        .shadow(color: searchFocused ? theme.accent.opacity(0.08) : .clear, radius: 5)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                filterButton("All", symbol: "square.stack", kind: nil)
                ForEach(ClipKind.allCases) { kind in
                    filterButton(kind.label, symbol: kind.symbol, kind: kind)
                }
            }
        }
    }

    private var refinementMenu: some View {
        Button { showingRefinements.toggle() } label: {
            Label("Filters", systemImage: model.hasActiveHistoryRefinements
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(model.hasActiveHistoryRefinements ? theme.accent : Color.secondary)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(theme.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Refine history")
        .accessibilityLabel(model.hasActiveHistoryRefinements ? "Refine history, filters active" : "Refine history")
        .popover(isPresented: $showingRefinements, arrowEdge: .bottom) { refinementPanel }
    }

    private var refinementPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filter history").font(.system(size: 13, weight: .semibold))
            refinementSection("Copied") {
                ForEach(HistoryTimeFilter.allCases) { filter in
                    refinementOption(filter.label, selected: model.timeFilter == filter) {
                        model.timeFilter = filter
                    }
                }
            }
            refinementSection("Source app") {
                refinementOption("All apps", selected: model.sourceBundleFilter == nil) {
                    model.sourceBundleFilter = nil
                }
                ForEach(model.knownApps, id: \.0) { bundleID, name in
                    refinementOption(name, selected: model.sourceBundleFilter == bundleID) {
                        model.sourceBundleFilter = bundleID
                    }
                }
            }
            Divider()
            refinementOption("Favorites only", selected: model.favoritesOnly) {
                model.favoritesOnly.toggle()
            }
            if model.hasActiveHistoryRefinements {
                Button("Clear refinements") {
                    model.resetHistoryRefinements()
                    showingRefinements = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
                .font(.system(size: 11, weight: .medium))
            }
        }
        .padding(14)
        .frame(width: 210)
    }

    private func refinementSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func refinementOption(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            model.selectedID = nil
            model.applySearchImmediately()
        } label: {
            HStack {
                Text(title)
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }
            .font(.system(size: 11))
            .foregroundStyle(selected ? theme.accent : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func filterButton(_ title: String, symbol: String, kind: ClipKind?) -> some View {
        let active = model.filter == kind
        return Button {
            model.filter = kind; model.selectedID = nil; model.applySearchImmediately()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .medium))
                Text(title).font(.system(size: 11, weight: active ? .semibold : .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(active ? Color.white : Color.secondary)
            .background(active ? theme.accentFill : .clear,
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
                ClipRow(model: model, snapshot: item, card: model.cardView, selected: selectedID == item.id,
                        onPreview: { model.selectedID = item.id; model.previewedID = item.id })
                    .id(item.id)
            }
        }
    }

    private var emptyState: some View {
        let searching = !searchText.isEmpty || model.filter != nil || model.hasActiveHistoryRefinements
        let state = model.captureState
        let title: String
        let message: String
        let symbol: String
        if searching {
            title = "No matching entries"
            message = "Try another search term or reset the filters."
            symbol = "magnifyingglass"
        } else {
            switch state {
            case .unavailable:
                title = "History is not available yet"
                message = "Check whether macOS is waiting for Keychain approval."
                symbol = "lock"
            case .setup:
                title = "Your clipboard, within reach"
                message = "Set up SmartClip and enable capture."
                symbol = "doc.on.clipboard"
            case .paused:
                title = "Capture paused"
                message = "Resume capture to store new copies."
                symbol = "pause"
            case .denied:
                title = "Clipboard access is blocked"
                message = "Allow SmartClip access in macOS System Settings."
                symbol = "hand.raised"
            case .active:
                title = "Room for your next ideas"
                message = "Copy text, an image, or a file.\nSmartClip keeps it ready for you here."
                symbol = "doc.on.clipboard"
            }
        }
        return VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 27, weight: .light)).foregroundStyle(theme.accent)
                .frame(width: 66, height: 66)
                .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 19))
                .accessibilityHidden(true)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineSpacing(3)
            if searching {
                Button("Reset search and filters") {
                    model.selectedID = nil
                    searchText = ""
                    model.resetSearch()
                }
                    .buttonStyle(.bordered).padding(.top, 4)
            } else if state == .paused {
                Button("Resume capture") { model.setPaused(false) }
                    .buttonStyle(.bordered).padding(.top, 4)
            } else if state == .setup {
                Button("Set up SmartClip") { model.onOpenSettings?() }
                    .buttonStyle(.bordered).padding(.top, 4)
            } else if state == .denied || state == .unavailable, model.recoveryAction != nil {
                Button(model.recoveryAction?.title ?? "Resolve issue") { model.performRecovery() }
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
                Circle().fill(model.captureState == .active ? theme.accent : Color.orange)
                    .frame(width: 6, height: 6).accessibilityHidden(true)
                Text(model.captureStatusLabel)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Menu {
                    if model.isPaused {
                        Button("Resume capture", systemImage: "play.fill") { model.setPaused(false) }
                        Divider()
                    }
                    Button("Pause for 15 minutes", systemImage: "timer") { model.pause(for: 15 * 60) }
                    Button("Pause until next launch", systemImage: "power") { model.pauseUntilRestart() }
                    Button("Pause indefinitely", systemImage: "pause.fill") { model.setPaused(true) }
                } label: {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11)).frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).foregroundStyle(.secondary)
                .help("Control capture")
                .accessibilityLabel("Control capture")
                .disabled(!model.onboardingComplete || !model.storageReady)
                Spacer()
                KeyboardHint(text: "↑ ↓")
                Text("Select").font(.system(size: 10)).foregroundStyle(.secondary)
                KeyboardHint(text: "↵")
                Text(selectedItem == nil && !searchText.isEmpty ? "Search" : model.autoPaste ? "Paste" : "Copy")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Menu {
                    Button("Settings") { model.onOpenSettings?() }
                    Divider()
                    Button("Quit SmartClip") { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
                .help("More options").accessibilityLabel("More options")
            }
            .padding(.horizontal, 20).frame(height: 42)
        }
        .background { chromeBackground }
        .shadow(color: .black.opacity(0.06), radius: 10, y: -4)
        .zIndex(1)
    }

    private func moveSelection(_ offset: Int) {
        // Resolve the latest query before selecting, even within the debounce interval.
        model.applySearchImmediately(searchText)
        model.selectedID = HistoryNavigation.moved(in: model.itemIDs, explicit: model.selectedID,
                                                   search: searchText, offset: offset)
    }

    @ViewBuilder private var loadMoreSection: some View {
        if model.hasMoreHistory || model.isLoadingHistory {
            HStack(spacing: 10) {
                if model.isLoadingHistory { ProgressView().controlSize(.small) }
                Button(model.isLoadingHistory ? "Loading…" : "Load 100 older entries") {
                    model.loadMoreHistory()
                }
                .buttonStyle(.bordered)
                .disabled(model.isLoadingHistory)
                Text("Showing \(model.items.count)")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ClipRow: View {
    @Environment(\.clipPalette) private var theme
    let model: AppModel
    let snapshot: ClipSummary
    // Lazy rows may retain their identity when moving between sections. Resolve
    // actions and labels from the current model instead of the old row snapshot.
    private var item: ClipSummary { model.item(for: snapshot.id) ?? snapshot }
    private var dragState: ClipRowDragState { ClipRowDragState(item: item) }
    let card: Bool
    let selected: Bool
    let onPreview: () -> Void
    @State private var confirmUnmark = false
    @State private var confirmExclude = false
    @State private var editFavoriteName = false
    @State private var favoriteDraft = ""
    @State private var hovered = false
    @State private var dragFileURLs: [URL] = []

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { model.copy(item) } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.isSensitive ? "lock" : item.kind.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(item.isSensitive ? Color.orange : item.kind.color(in: theme))
                        .frame(width: 36, height: 36)
                        .background((item.isSensitive ? Color.orange : item.kind.color(in: theme)).opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 7) {
                        if let favoriteName = item.favoriteName {
                            Label(favoriteName, systemImage: "pin.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .lineLimit(1)
                        }
                        if item.isSensitive {
                            Text("Sensitive content").font(.system(size: 13, weight: .medium))
                            Text("••••••••••••").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        } else {
                            if item.kind == .code {
                                Text(item.codeLanguage ?? "Unknown language")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(ClipKind.code.color(in: theme))
                                    .help("Language estimated automatically from syntax")
                            }
                            Text(item.preview.isEmpty ? item.kind.label : item.preview)
                                .font(.system(size: 13, weight: .medium, design: item.kind == .code ? .monospaced : .default))
                                .lineSpacing(3).lineLimit(card ? 4 : 2)
                                .multilineTextAlignment(.leading)
                        }
                        if card && item.kind == .image && !item.isSensitive {
                            ClipImagePreview(model: model, id: item.id)
                        }
                        if item.hasNote {
                            Label(item.isSensitive ? "Encrypted note" : item.note ?? "Note",
                                  systemImage: "note.text")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(card ? 2 : 1)
                        }
                        HStack(spacing: 5) {
                            SourceAppIcon(bundleID: item.sourceBundleID, size: 13)
                            Text(item.sourceName ?? "Unknown app").help("Source app estimated at copy time")
                            Text("·").foregroundStyle(.tertiary)
                            Text(item.firstCapturedAt ?? item.lastCopiedAt, style: .relative)
                            if item.hasMissingFiles {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                                    .help("Original file is missing")
                            }
                        }
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        if item.retentionOverrideSeconds != nil {
                            retentionNote
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ResponsiveButtonStyle())
            .accessibilityLabel("\(item.favoriteName.map { "\($0), " } ?? "")\(item.kind.label): \(item.isSensitive ? "sensitive entry" : item.preview)\(item.hasNote ? ", has note" : "")")
            .accessibilityAddTraits(selected ? .isSelected : [])
            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 2) {
                    if dragState.allowsFileURLs, dragFileURLs.count > 1 {
                        MultiFileDragHandle(urls: dragFileURLs)
                            .frame(width: 24, height: 24)
                    }
                    Button(action: onPreview) {
                        Image(systemName: "eye")
                            .font(.system(size: 11)).frame(width: 24, height: 24)
                    }
                    .buttonStyle(IconControlStyle())
                    .foregroundStyle(.secondary)
                    .opacity(hovered || selected ? 1 : 0.65)
                    .help("Preview")
                    .accessibilityLabel("Preview entry")
                    Button { model.pin(item) } label: {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 11)).frame(width: 24, height: 24)
                    }
                    .buttonStyle(IconControlStyle())
                    .foregroundStyle(item.isPinned ? theme.accent : Color.secondary)
                    .opacity(item.isPinned || hovered || selected ? 1 : 0.65)
                    .help(item.isPinned ? "Unpin" : "Pin")
                    .accessibilityLabel(item.isPinned ? "Unpin entry" : "Pin entry")
                    actions
                }
                if item.copyCount > 1 {
                    Text("\(item.copyCount)×").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(card ? 15 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? theme.selection
                    : card ? theme.surface : hovered ? theme.surface.opacity(0.72) : .clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(selected ? theme.accent.opacity(0.34) : card ? theme.line : .clear))
        .shadow(color: card ? .black.opacity(0.035) : .clear, radius: 5, y: 2)
        .onHover { hovered = $0 }
        .modifier(ClipDragModifier(model: model, item: item))
        .task(id: dragState) {
            dragFileURLs = []
            guard dragState.allowsFileURLs,
                  let paths = await model.loadPayload(for: item.id)?.filePaths else { return }
            guard dragState == ClipRowDragState(item: item) else { return }
            dragFileURLs = paths.map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        .confirmationDialog("Keep longer?", isPresented: $confirmUnmark) {
            Button("Mark as regular") { model.markSensitive(item, false) }
        } message: {
            Text("This entry will then use the regular retention period. A pinned entry remains until you delete it manually.")
        }
        .confirmationDialog("Exclude this app in the future?", isPresented: $confirmExclude) {
            Button("Exclude \(item.sourceName ?? "this app")", role: .destructive) {
                model.excludeSourceApp(of: item)
            }
        } message: {
            Text("New copies from this app will no longer be stored. Existing entries remain.")
        }
        .alert(item.favoriteName == nil ? "Name favorite" : "Rename favorite",
               isPresented: $editFavoriteName) {
            TextField("Name", text: $favoriteDraft)
            Button("Save") { model.nameFavorite(item, favoriteDraft) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The name is stored encrypted and can be found through search.")
        }
    }

    private var actions: some View {
        Menu {
            Button("Copy", systemImage: "doc.on.doc") { model.copy(item) }
            if item.kind == .url { Button("Open URL", systemImage: "arrow.up.right") { model.openURL(item) } }
            Button(item.isPinned ? "Unpin" : "Pin", systemImage: "pin") { model.pin(item) }
            Button(item.favoriteName == nil ? "Name favorite …" : "Rename favorite …",
                   systemImage: "tag") {
                favoriteDraft = item.favoriteName ?? ""
                editFavoriteName = true
            }
            if item.favoriteName != nil {
                Button("Remove favorite name", systemImage: "tag.slash") { model.nameFavorite(item, "") }
            }
            Button(item.hasNote ? "View note" : "Add note …", systemImage: "note.text") { onPreview() }
            Button(item.isSensitive ? "Mark as regular" : "Mark as sensitive", systemImage: "lock") {
                if item.isSensitive { confirmUnmark = true }
                else { model.markSensitive(item, true) }
            }
            retentionMenu
            if item.sourceBundleID != nil {
                Divider()
                Button("Exclude \(item.sourceName ?? "source app") in the future", systemImage: "app.badge") {
                    confirmExclude = true
                }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { model.delete(item) }
        } label: { Image(systemName: "ellipsis").font(.system(size: 12)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22, height: 24)
            .help("Entry actions").accessibilityLabel("Entry actions")
    }

    private var retentionMenu: some View {
        Menu("Retention", systemImage: "clock") {
            retentionChoice("Global setting", seconds: nil)
            Divider()
            if item.isSensitive {
                retentionChoice("5 minutes", seconds: 300)
                retentionChoice("1 hour", seconds: 3_600)
                retentionChoice("24 hours", seconds: 86_400)
                Divider()
                Text("Mark as regular before choosing “Never”")
            } else {
                retentionChoice("7 days", seconds: 7 * 86_400)
                retentionChoice("30 days", seconds: 30 * 86_400)
                retentionChoice("90 days", seconds: 90 * 86_400)
                retentionChoice("1 year", seconds: 365 * 86_400)
                retentionChoice("Never", seconds: 0)
            }
        }
    }

    @ViewBuilder private func retentionChoice(_ title: String, seconds: Int?) -> some View {
        Button {
            model.setRetentionOverride(seconds, for: item)
        } label: {
            if item.retentionOverrideSeconds == seconds {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    @ViewBuilder private var retentionNote: some View {
        if let deletionDate = item.deletionDate(normalDays: model.normalDays == 0 ? nil : model.normalDays,
                                                sensitiveSeconds: TimeInterval(model.sensitiveSeconds)) {
            Label {
                Text("Delete: \(deletionDate.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Locale(identifier: "en_US"))))")
            } icon: {
                Image(systemName: "clock")
            }
            .help("Scheduled deletion: \(deletionDate.formatted(Date.FormatStyle(date: .long, time: .shortened, locale: Locale(identifier: "en_US"))))")
            .font(.system(size: 10)).foregroundStyle(.secondary)
        } else {
            Label("No automatic deletion", systemImage: "infinity")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

struct ClipRowDragState: Hashable {
    let id: UUID
    let kind: ClipKind
    let isSensitive: Bool
    let hasMissingFiles: Bool

    init(item: ClipSummary) {
        id = item.id
        kind = item.kind
        isSensitive = item.isSensitive
        hasMissingFiles = item.hasMissingFiles
    }

    var allowsFileURLs: Bool {
        kind == .files && !isSensitive && !hasMissingFiles
    }
}

private struct ClipDragModifier: ViewModifier {
    let model: AppModel
    let item: ClipSummary

    @ViewBuilder func body(content: Content) -> some View {
        if item.isSensitive || item.hasMissingFiles {
            content
        } else {
            content.onDrag {
                ClipDragProvider.makeProvider(for: item) { await model.loadPayload(for: $0) }
                    ?? NSItemProvider()
            }
        }
    }
}

private struct ClipImagePreview: View {
    let model: AppModel
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
        .task(id: id) {
            guard let data = await model.loadPayload(for: id)?.imageData,
                  !Task.isCancelled else { return }
            guard let decoded = await ClipImageDecoder.decode(data), !Task.isCancelled else { return }
            image = NSImage(cgImage: decoded, size: .zero)
        }
        .onDisappear { image = nil }
    }
}
