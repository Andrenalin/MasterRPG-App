// @copyright André Trettin

import Foundation

/// Parses a dice-table entry name like `"5-10"`, `"5–10"`, or `"7"` into the
/// inclusive range of roll results it matches. Shared by
/// `TableGenerationController` (the live roll UI) and `GameController`
/// (`TableGameStorable.entry(for:with:)`) so the two roll-resolution paths
/// in this module can no longer silently diverge — `GameController` used to
/// hand-roll a version that only checked the upper bound and only split on
/// an ASCII hyphen. See CODE_AUDIT_Table §5.1/§5.2.
public enum TableRollRange {
    /// A token of two or more zeros ("00", "000") is the die maximum — 100, 1000 — when it is the
    /// only value or the upper end of a range ("96-00"): printed d100 tables write 100 as 00. As
    /// the lower end ("00-09" on a 00-99 table) it stays 0. Only ASCII digits count; "½" or "²"
    /// end the selector instead of shifting the values. See CODE_AUDIT_26 §5.2.
    public static func selectorRange(for name: String) -> ClosedRange<Int>? {
        let trimmed = name
            .trimmingCharacters(in: CharacterSet(charactersIn: "*`[]() "))
        let prefix = trimmed.prefix {
            $0.isASCIIDigit || $0.isWhitespace || $0 == "-" || $0 == "–" || $0 == "—"
        }
        let tokens = prefix.split { !$0.isASCIIDigit }
        let values = tokens.enumerated().compactMap { index, token -> Int? in
            let isAllZeros = token.count >= 2 && token.allSatisfy { $0 == "0" }
            let isUpperEnd = index == tokens.count - 1
            if isAllZeros, isUpperEnd, let maximum = Int("1" + token) {
                return maximum
            }
            return Int(token)
        }
        guard let first = values.first else { return nil }
        let last = values.dropFirst().first ?? first
        return min(first, last)...max(first, last)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
