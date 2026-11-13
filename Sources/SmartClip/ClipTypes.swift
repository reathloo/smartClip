import Foundation
import CryptoKit

enum ClipKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case text, code, url, email, image, files
    var id: String { rawValue }
    var label: String {
        switch self {
        case .text: "Text"
        case .code: "Code"
        case .url: "URL"
        case .email: "Email"
        case .image: "Image"
        case .files: "Files"
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

struct ClipPayload: Codable, Equatable, Sendable {
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
        case .image: "Image"
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

struct ClipSummary: Identifiable, Equatable, Sendable {
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
    /// First capture time for display; retention and ordering use `lastCopiedAt`.
    var firstCapturedAt: Date? = nil
    var codeLanguage: String? = nil
    var favoriteName: String? = nil
    var note: String? = nil
    var hasNote: Bool = false
    var retentionOverrideSeconds: Int? = nil

    func deletionDate(normalDays: Int?, sensitiveSeconds: TimeInterval) -> Date? {
        Retention.duration(sensitive: isSensitive, pinned: isPinned, normalDays: normalDays,
                           sensitiveSeconds: sensitiveSeconds,
                           overrideSeconds: retentionOverrideSeconds)
            .map { lastCopiedAt.addingTimeInterval($0) }
    }
}

enum ClipNote {
    static let maximumCharacters = 4_000

    static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumCharacters))
    }
}

enum ClipClassifier {
    private static let credentialPatterns: [NSRegularExpression] = [
        #"-----BEGIN(?: [A-Z0-9]+)? PRIVATE KEY-----"#,
        #"\bBearer[ \t]+[A-Za-z0-9._~+/=-]{16,}"#,
        #"\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{16,}\b"#,
        #"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"#,
        #"\b(?:sk-(?:proj-|ant-[A-Za-z0-9-]*)?[A-Za-z0-9_-]{20,}|sk_live_[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{20,})\b"#,
        #"\b(?:AKIA[A-Z0-9]{16}|AIza[A-Za-z0-9_-]{30,})\b"#
    ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    private static let assignmentPattern = try? NSRegularExpression(
        pattern: #"\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|secret[_-]?key|password|passwd)\b\s*(?:=|:)\s*[\"']?([^\s\"']{16,})"#,
        options: .caseInsensitive
    )

    static func isSensitive(text: String?, pasteboardTypes: [String] = []) -> Bool {
        let markers = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword"]
        if pasteboardTypes.contains(where: { type in markers.contains(where: type.hasPrefix) }) { return true }
        guard let text else { return false }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        if credentialPatterns.contains(where: { $0.firstMatch(in: text, range: fullRange) != nil }) { return true }
        if let match = assignmentPattern?.firstMatch(in: text, range: fullRange),
           match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text),
           looksLikeAssignedSecret(String(text[range])) { return true }
        let pattern = #"(?<!\d)(?:\d[ -]?){13,19}(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.matches(in: text, range: fullRange).contains { match in
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

    private static func looksLikeAssignedSecret(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        if ["example", "placeholder", "changeme", "your_", "<", ">"].contains(where: lowercased.contains) {
            return false
        }
        let classes = [
            value.contains(where: { $0.isLowercase }), value.contains(where: { $0.isUppercase }),
            value.contains(where: { $0.isNumber }), value.contains(where: { !$0.isLetter && !$0.isNumber })
        ].filter { $0 }.count
        return classes >= 2 || value.count >= 24
    }
}

enum Retention {
    static let normalPresets = [7 * 86_400, 30 * 86_400, 90 * 86_400, 365 * 86_400]
    static let sensitivePresets = [300, 3_600, 86_400]

    static func duration(sensitive: Bool, pinned: Bool, normalDays: Int?, sensitiveSeconds: TimeInterval,
                         overrideSeconds: Int? = nil) -> TimeInterval? {
        if sensitive {
            guard let overrideSeconds, sensitivePresets.contains(overrideSeconds) else {
                return sensitiveSeconds
            }
            return TimeInterval(overrideSeconds)
        }
        if let overrideSeconds {
            return overrideSeconds == 0 ? nil : TimeInterval(overrideSeconds)
        }
        if pinned || normalDays == nil { return nil }
        return Double(normalDays!) * 86_400
    }

    static func expired(lastCopiedAt: Date, sensitive: Bool, pinned: Bool, normalDays: Int?,
                        sensitiveSeconds: TimeInterval, now: Date, overrideSeconds: Int? = nil) -> Bool {
        guard let duration = duration(sensitive: sensitive, pinned: pinned, normalDays: normalDays,
                                      sensitiveSeconds: sensitiveSeconds, overrideSeconds: overrideSeconds) else {
            return false
        }
        return now.timeIntervalSince(lastCopiedAt) >= duration
    }
}
