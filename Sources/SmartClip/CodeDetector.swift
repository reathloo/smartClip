import Foundation

enum CodeLanguage: String {
    case python = "Python", javascript = "JavaScript", typescript = "TypeScript"
    case swift = "Swift", shell = "Shell", json = "JSON", html = "HTML", css = "CSS"
    case sql = "SQL", go = "Go", rust = "Rust", java = "Java"
    case c = "C", cpp = "C++", csharp = "C#", php = "PHP"
    case unknown = "Sprache unklar"
}

/// Conservative, local syntax heuristics. A short snippet can fit several languages;
/// ambiguous code stays code without an asserted language. No network or execution.
enum CodeDetector {
    private struct Rule {
        let language: CodeLanguage
        let regex: NSRegularExpression
        init(_ language: CodeLanguage, _ pattern: String) {
            self.language = language
            self.regex = try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }
    }

    private static let rules: [Rule] = [
        Rule(.python, #"^\s*(?:async\s+)?def\s+\w+\s*\([^\n]*\)\s*(?:->[^\n]+)?\s*:|^\s*from\s+[\w.]+\s+import\s+\w+|^\s*(?:elif|except)\b[^\n]*:"#),
        Rule(.typescript, #"\b(?:const|let|var)\s+\w+\s*:\s*(?:string|number|boolean|unknown|any)(?:\[\])?\s*=|^\s*(?:export\s+)?(?:interface|type)\s+\w+\s*(?:[<{=])|\([^\n)]*\w+\s*:\s*(?:string|number|boolean)\b[^\n)]*\)"#),
        Rule(.javascript, #"\b(?:const)\s+[\w$]+\s*=|\b(?:async\s+)?function\s*\w*\s*\(|\bconsole\.(?:log|warn|error)\s*\(|\b(?:document|window)\.\w+\s*\("#),
        Rule(.swift, #"^\s*(?:(?:public|private|static|override|mutating)\s+)*func\s+\w+\s*\([^\n]*(?::[^\n]*\)|\)\s*->)|^\s*import\s+(?:SwiftUI|AppKit|Foundation|UIKit|Combine)\s*$|^\s*@(?:State|Published|MainActor|ObservedObject)\b|^\s*guard\s+.+\s+else\s*\{"#),
        Rule(.shell, #"^#![^\n]*\b(?:bash|zsh|sh|fish)\b|^\s*(?:export\s+[A-Z_][A-Z0-9_]*=|(?:sudo\s+)?(?:curl|chmod|mkdir|grep|git|npm|pip|brew)\s+[-\w./])|\$\{[A-Za-z_][A-Za-z0-9_]*\}"#),
        Rule(.html, #"(?i)<!doctype\s+html|<(?:html|head|body|div|span|section|button|input|a|p|h[1-6])(?:\s[^<>]*|)>[\s\S]*</[a-z][^>]*>|<(?:input|img|br)\b[^<>]*/?>"#),
        Rule(.css, #"[.#]?[a-zA-Z_][\w\s.#,:>\-]*\s*\{\s*(?:--[\w-]+|color|background(?:-color)?|display|margin(?:-\w+)?|padding(?:-\w+)?|font(?:-\w+)?|width|height)\s*:\s*[^{};]+[;}]"#),
        Rule(.sql, #"(?i)^\s*(?:SELECT\s+[\s\S]+?\s+FROM\s+[\w\"`\[]|INSERT\s+INTO\s+\w+|UPDATE\s+\w+\s+SET\s+|DELETE\s+FROM\s+\w+|CREATE\s+TABLE\s+)"#),
        Rule(.go, #"^\s*package\s+\w+\s*$|^\s*func\s+\w+\s*\([^\n]*\)\s+[\w*\[\]]+\s*\{|^\s*func\s+\w+\s*\(\w+\s+[\w*\[\]]+|\bfmt\.(?:Println|Printf|Sprintf)\("#),
        Rule(.rust, #"^\s*(?:pub\s+)?(?:async\s+)?fn\s+\w+\s*\(|\b(?:println|vec|format)!\s*[(\[]|^\s*(?:use\s+\w+::|impl\s+\w+)"#),
        Rule(.java, #"\bSystem\.out\.print(?:ln)?\s*\(|^\s*import\s+java\.[\w.*]+;|\bpublic\s+static\s+void\s+main\s*\("#),
        Rule(.c, #"^\s*#include\s*[<\"](?:stdio|stdlib|string|stdint)\.h[>\"]|\bprintf\s*\(\s*\""#),
        Rule(.cpp, #"^\s*#include\s*<(?:iostream|vector|string|memory)>|\bstd::\w+|\b(?:cout|cin)\s*(?:<<|>>)"#),
        Rule(.csharp, #"^\s*using\s+System(?:\.[\w.]+)?\s*;|\bConsole\.(?:WriteLine|ReadLine)\s*\(|^\s*namespace\s+[\w.]+\s*[;{]"#),
        Rule(.php, #"<\?php\b|\$[A-Za-z_]\w*\s*->\s*\w+|^\s*echo\s+\$\w+\s*;"#)
    ]
    private static let generic = try! NSRegularExpression(
        pattern: #"^\s*func\s+\w+\([^\n]*\)\s*\{|^\s*(?:if|for|while|switch)\s*\([^\n]+\)\s*\{|^\s*(?:let|const|var)\s+\w+\s*=\s*\S+|^\s*[A-Za-z_]\w*\s*=\s*[^\n]+;\s*$|^\s*\w+(?:\.\w+)*\([^\n]*\);\s*$"#,
        options: [.anchorsMatchLines])

    static func detect(_ text: String) -> CodeLanguage? {
        // Bound regex/JSON work even for very large clipboard entries.
        let sample = String(text.prefix(24_000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return nil }
        if sample.hasPrefix("```"), let newline = sample.firstIndex(of: "\n"), sample.dropFirst(3).contains("```") {
            let tag = String(sample[sample.index(sample.startIndex, offsetBy: 3)..<newline]).lowercased().trimmingCharacters(in: .whitespaces)
            let aliases: [String: CodeLanguage] = ["py": .python, "python": .python, "js": .javascript,
                "javascript": .javascript, "jsx": .javascript, "ts": .typescript, "typescript": .typescript,
                "tsx": .typescript, "swift": .swift, "sh": .shell, "bash": .shell, "zsh": .shell,
                "json": .json, "html": .html, "css": .css, "sql": .sql, "go": .go,
                "rust": .rust, "rs": .rust, "java": .java, "c": .c, "cpp": .cpp, "c++": .cpp,
                "csharp": .csharp, "cs": .csharp, "c#": .csharp, "php": .php]
            if let language = aliases[tag] { return language }
            let inner = String(sample[sample.index(after: newline)...].components(separatedBy: "```")[0])
            return detect(inner) ?? .unknown
        }
        if (sample.first == "{" || sample.first == "["),
           let data = sample.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data), object is [String: Any] || object is [Any] {
            return .json
        }
        let range = NSRange(sample.startIndex..<sample.endIndex, in: sample)
        var matches = Set(rules.filter { $0.regex.firstMatch(in: sample, range: range) != nil }.map(\.language))
        // These languages deliberately share syntax. Prefer the more specific evidence.
        if matches.contains(.typescript) { matches.remove(.javascript) }
        if matches.contains(.cpp) { matches.remove(.c) }
        if matches.contains(.go) { matches.remove(.swift) }
        if matches.count == 1 { return matches.first }
        if matches.count > 1 || generic.firstMatch(in: sample, range: range) != nil { return .unknown }
        return nil
    }
}
