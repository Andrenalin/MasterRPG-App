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
    public static func selectorRange(for name: String) -> ClosedRange<Int>? {
        let trimmed = name
            .trimmingCharacters(in: CharacterSet(charactersIn: "*`[]() "))
        let prefix = trimmed.prefix {
            $0.isNumber || $0.isWhitespace || $0 == "-" || $0 == "–" || $0 == "—"
        }
        let values = prefix.split { !$0.isNumber }.compactMap { Int($0) }
        guard let first = values.first else { return nil }
        let last = values.dropFirst().first ?? first
        return min(first, last)...max(first, last)
    }
}
