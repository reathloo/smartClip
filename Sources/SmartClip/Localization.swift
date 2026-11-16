import Foundation

enum L10n {
    static var locale: Locale { .autoupdatingCurrent }

    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = localizationBundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }

    private static var localizationBundle: Bundle {
        if Bundle.main.url(forResource: "Localizable", withExtension: "strings") != nil {
            return .main
        }
        return .module
    }
}
