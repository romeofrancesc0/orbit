import Foundation
import SwiftUI

/// The languages the interface is available in. Italian is the source language:
/// its strings are the keys, so it needs no table of its own.
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, italian, english, spanish, french, german

    var id: String { rawValue }

    /// Language code used for the `.lproj` folder and the locale.
    var code: String? {
        switch self {
        case .system:  nil
        case .italian: "it"
        case .english: "en"
        case .spanish: "es"
        case .french:  "fr"
        case .german:  "de"
        }
    }

    /// Always written in the language itself, so it can be found from any other.
    var nativeName: String {
        switch self {
        case .system:  "System"
        case .italian: "Italiano"
        case .english: "English"
        case .spanish: "Español"
        case .french:  "Français"
        case .german:  "Deutsch"
        }
    }

    static let supportedCodes = ["it", "en", "es", "fr", "de"]

    /// The language actually used: the chosen one, or the best match for the system's.
    var resolvedCode: String {
        if let code { return code }
        for preferred in Locale.preferredLanguages {
            let base = Locale(identifier: preferred).language.languageCode?.identifier ?? ""
            if Self.supportedCodes.contains(base) { return base }
        }
        return "en"
    }

    var locale: Locale { Locale(identifier: resolvedCode) }
}

/// Looks strings up in the table of the language chosen in the settings.
/// Views get theirs from the SwiftUI environment; this is for everything that
/// builds a `String` by hand (alerts, menus, labels computed in code).
enum L10n {
    nonisolated(unsafe) private(set) static var code = "it"
    nonisolated(unsafe) private static var bundle: Bundle?

    static func use(_ language: AppLanguage) {
        let resolved = language.resolvedCode
        code = resolved
        guard resolved != "it",
              let path = Bundle.main.path(forResource: resolved, ofType: "lproj")
        else {
            bundle = nil
            return
        }
        bundle = Bundle(path: path)
    }

    static var locale: Locale { Locale(identifier: code) }

    static func string(_ key: String) -> String {
        bundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }
}

/// Translates a string written in Italian. Arguments fill `%@`, `%lld`, `%.1f`…
func tr(_ key: String, _ arguments: CVarArg...) -> String {
    let format = L10n.string(key)
    return arguments.isEmpty ? format : String(format: format, locale: L10n.locale, arguments: arguments)
}
