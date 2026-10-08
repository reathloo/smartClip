import Foundation
import CryptoKit

enum ClipKind: String, Codable, CaseIterable, Identifiable {
    case text, code, url, email, image, files
    var id: String { rawValue }
    var label: String {
        switch self {
        case .text: "Text"
        case .code: "Code"
        case .url: "URL"
        case .email: "E-Mail"
        case .image: "Bild"
        case .files: "Dateien"
        }
    }
    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .url: "link"
        case .email: "envelope"
        case .image: "photo"
        case .files: "doc.on.doc"
        }
    }
}

struct ClipPayload: Codable, Equatable {
    let kind: ClipKind
    let text: String?
    let imageData: Data?
    let filePaths: [String]?

    static func text(_ value: String) -> Self {
        let kind: ClipKind
        if let url = URL(string: value),
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           url.host != nil,
           !value.contains(where: \.isWhitespace) {
            kind = .url
        } else if value.range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#, options: .caseInsensitive.union(.regularExpression)) != nil {
            kind = .email
        } else {
            kind = CodeDetector.detect(value) == nil ? .text : .code
        }
        return Self(kind: kind, text: value, imageData: nil, filePaths: nil)
    }

    static func image(_ data: Data) -> Self {
        Self(kind: .image, text: nil, imageData: data, filePaths: nil)
    }

    static func files(_ paths: [String]) -> Self {
        Self(kind: .files, text: nil, imageData: nil, filePaths: paths)
    }

    var preview: String {
        switch kind {
        case .text, .code, .url, .email: text ?? ""
        case .image: "Bild"
        case .files: filePaths?.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ") ?? ""
        }
    }

    var hasMissingFiles: Bool {
        guard let filePaths else { return false }
        return filePaths.contains { !FileManager.default.fileExists(atPath: $0) }
    }

    func fingerprintData() -> Data {
        // Preserve the fingerprint of pre-existing text entries when they become code.
        var data = Data((kind == .code ? ClipKind.text : kind).rawValue.utf8)
        data.append(0)
        switch kind {
        case .text, .code, .url, .email:
            data.append(contentsOf: (text ?? "").utf8)
        case .image:
            data.append(imageData ?? Data())
        case .files:
            for path in filePaths ?? [] {
                let bytes = Data(path.utf8)
                var length = UInt64(bytes.count).bigEndian
                withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
                data.append(bytes)
            }
        }
        return data
    }

    func encodedData() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }
}

struct ClipSummary: Identifiable {
    let id: UUID
    let kind: ClipKind
    let lastCopiedAt: Date
    let sourceName: String?
    let sourceBundleID: String?
    let isSensitive: Bool
    let isPinned: Bool
    let copyCount: Int
    let preview: String
    let hasMissingFiles: Bool
    var codeLanguage: String? = nil
    var favoriteName: String? = nil
}

enum ClipClassifier {
    static func isSensitive(text: String?, pasteboardTypes: [String] = []) -> Bool {
        let markers = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword"]
        if pasteboardTypes.contains(where: { type in markers.contains(where: type.hasPrefix) }) { return true }
        guard let text else { return false }
        let pattern = #"(?<!\d)(?:\d[ -]?){13,19}(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).contains { match in
            guard let swiftRange = Range(match.range, in: text) else { return false }
            let digits = text[swiftRange].compactMap(\.wholeNumberValue)
            guard (13...19).contains(digits.count), digits.contains(where: { $0 != 0 }) else { return false }
            var sum = 0
            for (index, digit) in digits.reversed().enumerated() {
                let doubled = index.isMultiple(of: 2) ? digit : digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
            return sum.isMultiple(of: 10)
        }
    }
}

enum Retention {
    static func expired(lastCopiedAt: Date, sensitive: Bool, pinned: Bool, normalDays: Int?, sensitiveSeconds: TimeInterval, now: Date) -> Bool {
        if sensitive { return now.timeIntervalSince(lastCopiedAt) >= sensitiveSeconds }
        if pinned || normalDays == nil { return false }
        return now.timeIntervalSince(lastCopiedAt) >= Double(normalDays!) * 86_400
    }
}
