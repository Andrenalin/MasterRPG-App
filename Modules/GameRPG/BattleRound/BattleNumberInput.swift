// @copyright André Trettin

import CoreRPG
import Foundation

/// Reading and writing the whole numbers the game master types into a battle
/// card (initiative, hit points).
enum BattleNumberInput {
    /// The number in `text`, read the way the locale writes numbers: grouping
    /// separators, the locale's own digits and its minus sign are accepted.
    /// Plain ASCII digits and a typographic minus ("−") work in every locale.
    /// `nil` when the text is not a whole number.
    static func parse(_ text: String, locale: Locale = .current) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let asciiMinus = trimmed.replacing("\u{2212}", with: "-")
        if let value = Int(asciiMinus) {
            return SheetNumberLimit.clamped(value)
        }
        // The format style reads a leading number and ignores what follows
        // ("12abc" would be 12), so only text made of number characters gets
        // that far.
        guard isNumberText(trimmed, locale: locale) else { return nil }
        let format = IntegerFormatStyle<Int>.number.locale(locale)
        let parsed = (try? Int(trimmed, format: format, lenient: false))
            ?? (try? Int(asciiMinus, format: format, lenient: false))
        return parsed.map { SheetNumberLimit.clamped($0) }
    }

    /// Only digits (of any script), signs, the locale's grouping separator,
    /// spaces (a grouping separator in some locales) and invisible
    /// directional marks.
    private static func isNumberText(_ text: String, locale: Locale) -> Bool {
        let grouping = (locale.groupingSeparator ?? "").unicodeScalars
        let signs = "+-\u{2212}".unicodeScalars
        return text.unicodeScalars.allSatisfy { scalar in
            scalar.properties.numericType == .decimal
                || signs.contains(scalar)
                || grouping.contains(scalar)
                || scalar.properties.isWhitespace
                || scalar.properties.generalCategory == .format
        }
    }

    /// The text shown in the field for `value`: the locale's digits, without
    /// grouping separators, so it reads back through `parse` unchanged.
    static func text(for value: Int?, locale: Locale = .current) -> String {
        guard let value else { return "" }
        return value.formatted(.number.grouping(.never).locale(locale))
    }
}
