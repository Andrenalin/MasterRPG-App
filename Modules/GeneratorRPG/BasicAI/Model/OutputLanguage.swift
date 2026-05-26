// @copyright André Trettin

import Foundation

/// Represents an output language for AI analysis, with native display name and English name for prompts.
public struct OutputLanguage: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let englishName: String

    public static func forCurrentLocale() -> OutputLanguage {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return supported.first { $0.id == code } ?? supported[0]
    }

    public static let supported: [OutputLanguage] = [
        OutputLanguage(id: "en", displayName: "English",    englishName: "English"),
        OutputLanguage(id: "de", displayName: "Deutsch",    englishName: "German"),
        OutputLanguage(id: "fr", displayName: "Français",   englishName: "French"),
        OutputLanguage(id: "es", displayName: "Español",    englishName: "Spanish"),
        OutputLanguage(id: "it", displayName: "Italiano",   englishName: "Italian"),
        OutputLanguage(id: "pt", displayName: "Português",  englishName: "Portuguese"),
        OutputLanguage(id: "nl", displayName: "Nederlands", englishName: "Dutch"),
        OutputLanguage(id: "pl", displayName: "Polski",     englishName: "Polish"),
        OutputLanguage(id: "ja", displayName: "日本語",      englishName: "Japanese"),
    ]
}
