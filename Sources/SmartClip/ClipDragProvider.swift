import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum ClipDragProvider {
    static func makeProvider(
        for item: ClipSummary,
        loadPayload: @escaping @MainActor @Sendable (UUID) async -> ClipPayload?
    ) -> NSItemProvider? {
        guard !item.isSensitive, !item.hasMissingFiles else { return nil }

        let provider = NSItemProvider()
        switch item.kind {
        case .text, .code, .email:
            registerData(UTType.utf8PlainText, with: provider, item: item, loadPayload: loadPayload) { payload in
                payload.text.map { Data($0.utf8) }
            }
        case .url:
            registerData(UTType.url, with: provider, item: item, loadPayload: loadPayload) { payload in
                guard let text = payload.text, let url = URL(string: text) else { return nil }
                return Data(url.absoluteString.utf8)
            }
            registerData(UTType.utf8PlainText, with: provider, item: item, loadPayload: loadPayload) { payload in
                payload.text.map { Data($0.utf8) }
            }
        case .image:
            registerData(UTType.png, with: provider, item: item, loadPayload: loadPayload) { $0.imageData }
        case .files:
            registerFirstFile(with: provider, item: item, loadPayload: loadPayload)
            registerData(UTType.utf8PlainText, with: provider, item: item, loadPayload: loadPayload) { payload in
                guard let paths = payload.filePaths, !paths.isEmpty else { return nil }
                return Data(paths.joined(separator: "\n").utf8)
            }
        }
        provider.suggestedName = item.favoriteName ?? suggestedName(for: item)
        return provider
    }

    /// Use this after resolving a file payload when an AppKit dragging session can
    /// carry one item provider per file. SwiftUI's single-provider onDrag path can
    /// otherwise expose only the first file as a native file representation.
    static func fileProviders(for payload: ClipPayload) -> [NSItemProvider] {
        guard payload.kind == .files else { return [] }
        return (payload.filePaths ?? []).compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return NSItemProvider(contentsOf: url)
        }
    }

    private static func registerData(
        _ type: UTType,
        with provider: NSItemProvider,
        item: ClipSummary,
        loadPayload: @escaping @MainActor @Sendable (UUID) async -> ClipPayload?,
        transform: @escaping @Sendable (ClipPayload) -> Data?
    ) {
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
            let task = Task { @MainActor in
                guard let payload = await loadPayload(item.id), let data = transform(payload) else {
                    completion(nil, DragProviderError.unavailable)
                    return
                }
                completion(data, nil)
            }
            let progress = Progress(totalUnitCount: 1)
            progress.cancellationHandler = { task.cancel() }
            return progress
        }
    }

    private static func registerFirstFile(
        with provider: NSItemProvider,
        item: ClipSummary,
        loadPayload: @escaping @MainActor @Sendable (UUID) async -> ClipPayload?
    ) {
        provider.registerFileRepresentation(forTypeIdentifier: UTType.item.identifier,
                                            fileOptions: [], visibility: .all) { completion in
            let task = Task { @MainActor in
                guard let payload = await loadPayload(item.id),
                      let path = payload.filePaths?.first,
                      FileManager.default.fileExists(atPath: path) else {
                    completion(nil, false, DragProviderError.unavailable)
                    return
                }
                completion(URL(fileURLWithPath: path), false, nil)
            }
            let progress = Progress(totalUnitCount: 1)
            progress.cancellationHandler = { task.cancel() }
            return progress
        }
    }

    private static func suggestedName(for item: ClipSummary) -> String {
        switch item.kind {
        case .text: "SmartClip Text"
        case .code: "SmartClip Code"
        case .url: "SmartClip URL"
        case .email: "SmartClip Email"
        case .image: "SmartClip Image.png"
        case .files: "SmartClip Files"
        }
    }
}

struct MultiFileDragHandle: NSViewRepresentable {
    let urls: [URL]

    func makeNSView(context: Context) -> MultiFileDragSourceView {
        MultiFileDragSourceView(urls: urls)
    }

    func updateNSView(_ nsView: MultiFileDragSourceView, context: Context) {
        nsView.urls = urls
    }
}

final class MultiFileDragSourceView: NSView, NSDraggingSource {
    var urls: [URL]
    private let imageView = NSImageView()

    init(urls: [URL]) {
        self.urls = urls
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        imageView.image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: nil)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.imageScaling = .scaleProportionallyDown
        imageView.frame = bounds.insetBy(dx: 5, dy: 5)
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Drag all files")
        toolTip = "Drag all files"
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDragged(with event: NSEvent) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard existing.count > 1 else { return }
        let items = existing.enumerated().map { index, url -> NSDraggingItem in
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(url.absoluteString, forType: .fileURL)
            let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let origin = NSPoint(x: CGFloat(index) * 3, y: -CGFloat(index) * 3)
            item.setDraggingFrame(NSRect(origin: origin, size: NSSize(width: 32, height: 32)), contents: icon)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}

private enum DragProviderError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "This SmartClip entry is no longer available."
    }
}
