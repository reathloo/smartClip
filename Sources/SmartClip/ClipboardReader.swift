import AppKit

enum ClipboardReadResult {
    case captured(ClipPayload, sensitive: Bool)
    case skipped(String?)
}

@MainActor
enum ClipboardReader {
    static func read(_ pasteboard: NSPasteboard) -> ClipboardReadResult {
        let types = (pasteboard.pasteboardItems ?? []).flatMap { $0.types.map(\.rawValue) }
        let fileURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []).filter(\.isFileURL)
        if !fileURLs.isEmpty {
            let paths = fileURLs.map { $0.standardizedFileURL.path }
            return .captured(.files(paths), sensitive: ClipClassifier.isSensitive(text: nil, pasteboardTypes: types))
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            guard data.count <= 20 * 1_024 * 1_024 else { return .skipped("Image skipped: larger than 20 MB.") }
            guard let bitmap = NSBitmapImageRep(data: data),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                return .skipped("Image skipped: image data is corrupted or unreadable.")
            }
            guard png.count <= 20 * 1_024 * 1_024 else { return .skipped("Image skipped: larger than 20 MB.") }
            return .captured(.image(png), sensitive: ClipClassifier.isSensitive(text: nil, pasteboardTypes: types))
        }
        if let text = pasteboard.string(forType: .string) ?? pasteboard.string(forType: .URL), !text.isEmpty {
            return .captured(.text(text), sensitive: ClipClassifier.isSensitive(text: text, pasteboardTypes: types))
        }
        return .skipped(nil)
    }
}
